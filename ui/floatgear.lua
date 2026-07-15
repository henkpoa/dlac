--[[
    dlac/ui/floatgear.lua

    The floating equipment window (equipmon's 4x4, but ImGui and interactive) and
    the PIN menu that hangs off it. Its own module -- gearui stays off the LuaJIT
    200-local ceiling (hard rule 1), and this file owns every local it needs.

    It reads uihost's shared services but does NOT register a uihost `window`:
    those render inside gearui's drawWindow, which returns early when the main
    box is shut, and this window's whole point is to stay up while you play. So
    gearui's d3d_present calls M.render directly, inside its own theme bracket --
    the lockstyle-window pattern.

    What it is: the same 4x4 grid the Equipped tab draws (S.renderSlotGrid, so
    icons and the full hover tooltip come for free and can never drift from the
    tab's), in a window you can leave open while you play. Right-click a slot to
    pin an item into it; a pinned slot's box turns RED.

    Right-click: IsMouseClicked(1) + IsItemHovered feeding the ordinary
    OpenPopup/BeginPopup pair -- the pattern gearmove field-confirmed on
    feature/storage-move. (BeginPopupContextItem is the one that failed twice and
    put "right-click" on the dead-ends list; do not reach for it.) The grid
    reports the click from inside its own BeginChild and this module opens the
    popup at WINDOW scope, because OpenPopup and BeginPopup must share a scope.

    Pins are the engine's, not this window's: pinwatch writes
    <char>\dlac\pinstate.lua and dispatch (v44) wears the pinned names at top
    priority every dispatch. This module only edits that table.
]]--

local host = require("dlac\\ui\\uihost");
local pins = require("dlac\\feature\\pinwatch");
local fmt  = require("dlac\\gear\\gearfmt");

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');
local dsp   = try("dlac\\dispatch");

local M = {};

local S = host.services;
local ui, COL = S.ui, S.COL;
local GEAR_OF = S.GEAR_OF;

-- gearui provides its services BEFORE requiring this file, so the captures above
-- are safe (the equippedui precedent). If that order ever changes, fail loud and
-- render nothing rather than throwing a nil index every frame.
if ui == nil or COL == nil or S.renderSlotGrid == nil then
    print('[dlac] floatgear: shared services missing -- the floating window is disabled.');
    M.render = function() end;
    return M;
end

-- Cascading submenus: BeginMenu/EndMenu are declared in the Ashita SDK and their
-- symbols are in the binding, but NOTHING in this install calls them from Lua --
-- and symbol presence proves nothing here (BeginPopupContextItem is bound too,
-- and does not work). So probe the binding rather than assume it (hard rule 2).
-- Bound -> the Windows-style "item -> All / trigger" cascade. Not bound -> the
-- same choices as a drill-down inside the popup (gearmove's quantity-chooser
-- pattern), which uses only APIs already proven in this client.
local hasMenu = (imgui ~= nil)
    and (type(imgui.BeginMenu) == 'function') and (type(imgui.EndMenu) == 'function');

local POPUP  = '##dlac_pinmenu';
local CAP    = 200;       -- rows drawn per popup; the overflow is COUNTED, not hidden
local _openFor  = nil;    -- slot label whose menu should open next frame
local _menuSlot = nil;    -- slot the open popup belongs to
local _drillItem = nil;   -- fallback mode: item picked, now choosing scope
local _search = { '' };

-- --------------------------------------------------------------------------
-- Trigger choices for the scope submenu.
-- --------------------------------------------------------------------------

-- Every trigger of the CURRENT job entry as { key, text }. `key` is the engine's
-- scope key (dispatch.pinScopeKey over dispatch.ruleLabel) -- built from the
-- engine's own functions so the addon and LAC states cannot spell it
-- differently; `text` is the human line for the menu.
local function triggerChoices()
    local out = {};
    if dsp == nil or type(dsp.pinScopeKey) ~= 'function' then return out; end
    local tui = package.loaded["dlac\\ui\\triggersui"];   -- load order: don't force it
    if tui == nil or type(tui.currentModel) ~= 'function' then return out; end
    local data = nil;
    pcall(function() data = tui.currentModel(); end);
    if type(data) ~= 'table' then return out; end
    for _, ev in ipairs(dsp.EVENTS or {}) do
        local list = data[ev];
        if type(list) == 'table' then
            for _, r in ipairs(list) do
                if type(r) == 'table' and type(r.when) == 'table' then
                    local label = dsp.ruleLabel(r.when);
                    local parts = {};
                    for k, v in pairs(r.when) do
                        local pk = (type(dsp.PRETTY_KEY) == 'table' and dsp.PRETTY_KEY[k]) or k;
                        if v == true then parts[#parts + 1] = tostring(pk);
                        elseif type(v) == 'table' then
                            local vs = {};
                            for _, x in ipairs(v) do vs[#vs + 1] = tostring(x); end
                            table.sort(vs);
                            parts[#parts + 1] = tostring(pk) .. ' = ' .. table.concat(vs, '/');
                        else parts[#parts + 1] = tostring(pk) .. ' = ' .. tostring(v); end
                    end
                    table.sort(parts);
                    local shown = (#parts > 0) and table.concat(parts, ', ') or 'any';
                    local setn = (type(r.set) == 'string') and r.set
                              or ((type(r.set) == 'table') and r.set[1] or nil);
                    out[#out + 1] = {
                        key  = dsp.pinScopeKey(ev, label),
                        text = string.format('%s  %s%s', ev, shown,
                            setn and ('  -> ' .. tostring(setn)) or ''),
                    };
                end
            end
        end
    end
    return out;
end

-- --------------------------------------------------------------------------
-- The pin menu.
-- --------------------------------------------------------------------------

local function applyPin(slot, itemName, scope)
    pins.setPin(slot, itemName, scope);
    _drillItem = nil;
    pcall(function() imgui.CloseCurrentPopup(); end);
end

-- The scope rows for one item: "All" on top (the hard set -- every dispatch),
-- then one row per trigger of this job.
--
-- `inMenu` says we are inside a BeginMenu (the cascade), where MenuItem is the
-- right widget; the drill-down fallback uses Selectable. Tying the widget to
-- `hasMenu` rather than to `imgui.MenuItem ~= nil` keeps the fallback path on
-- APIs this client has actually proven -- MenuItem is used by shipped addons
-- with one argument, but only ever inside a menu.
--
-- No fmt.esc on these labels: esc doubles '%' for imgui's FORMATTING calls
-- (Text/TextColored). Selectable and MenuItem labels are not format strings, so
-- escaping would render a literal '%%' -- which is why nothing else in dlac
-- escapes a Selectable label either.
local function renderScopeRows(slot, name, choices, inMenu)
    local function row(label)
        if inMenu then return imgui.MenuItem(label); end
        return imgui.Selectable(label);
    end
    local hit = false;
    if row('All') then applyPin(slot, name, 'All'); hit = true; end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Pin for EVERYTHING -- the engine wears this piece on\nevery dispatch and nothing can take it back off.');
    end
    imgui.Separator();
    if #choices > 0 then
        for _, c in ipairs(choices) do
            if row(c.text) then applyPin(slot, name, { c.key }); hit = true; end
        end
    else
        imgui.TextColored(COL.DIM, '(this job has no triggers yet)');
    end
    return hit;
end

-- Candidate pool for a slot -- the SAME service the Equipped tab's Alternatives
-- list uses. Gating by job/level (and, for Sub, by the worn Main) is CORRECT
-- here: a pin equips immediately, so this is not set BUILDING and ADR 0006's
-- never-gate rule does not apply. The Sub HARD RULE (reverted 3x) protects the
-- BUILDER's Sub picker; the immediately-equipping Alternatives list gates, and
-- so does this. Offering a shield you cannot hold next to your 2H would just
-- pin a piece that never lands.
local function candidatesFor(slot, job, level)
    local gearKey = GEAR_OF[slot] or slot;
    if slot == 'Sub' and S.subFilter ~= nil and S.subCandidatePool ~= nil then
        local mainRec = S.lookupById(S.getEquippedId(0x00));   -- the WORN Main
        local ok, res = pcall(S.subFilter, S.subCandidatePool(job, level),
            mainRec, job, level, false);                       -- building = false
        if ok and type(res) == 'table' then return res; end
    end
    return S.candidatesForSlot(gearKey, job, level) or {};
end

local function renderPinMenu(job, level)
    local slot = _menuSlot;
    if slot == nil then return; end

    imgui.TextColored(COL.HEADER, slot);
    imgui.Separator();

    -- Unpin first: it is the one row you want instantly when the frame is red.
    if pins.isPinned(slot) then
        local p = pins.pinOf(slot);
        imgui.TextColored(COL.SCORE, fmt.esc('Pinned: ' .. tostring(p.item)));
        imgui.TextColored(COL.DIM, fmt.esc('Applies to: ' .. tostring(pins.scopeLabel(slot))));
        if imgui.Selectable('Remove pin') then
            pins.clearPin(slot);
            pcall(function() imgui.CloseCurrentPopup(); end);
            return;
        end
        imgui.Separator();
    end

    local choices = triggerChoices();

    -- Fallback drill-down: item chosen, now pick the scope in place.
    if not hasMenu and _drillItem ~= nil then
        imgui.TextColored(COL.HEADER, fmt.esc(_drillItem));
        imgui.TextColored(COL.DIM, 'Apply to which triggers?');
        imgui.Separator();
        if imgui.Selectable('< back') then _drillItem = nil; return; end
        renderScopeRows(slot, _drillItem, choices, false);
        return;
    end

    imgui.PushItemWidth(210);
    imgui.InputText('##pinsearch', _search, 64);
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then imgui.SetTooltip('Filter by name.'); end

    local q = string.lower(tostring(_search[1] or ''));
    local list = candidatesFor(slot, job, level);
    imgui.BeginChild('##pinlist', { 260, 240 }, false);
    local shown, matched = 0, 0;
    for _, rec in ipairs(list) do
        local nm = tostring(rec.Name or '?');
        if q == '' or string.find(string.lower(nm), q, 1, true) ~= nil then
            matched = matched + 1;
            if shown < CAP then                -- a popup is not a browser
                shown = shown + 1;
                -- raw nm, not fmt.esc: menu/selectable labels are not format
                -- strings (see renderScopeRows)
                if hasMenu then
                    if imgui.BeginMenu(nm .. '##pin' .. tostring(rec.Id)) then
                        renderScopeRows(slot, nm, choices, true);
                        imgui.EndMenu();
                    end
                else
                    if imgui.Selectable(nm .. '##pin' .. tostring(rec.Id)) then
                        _drillItem = nm;
                    end
                end
            end
        end
    end
    if matched == 0 then
        imgui.TextColored(COL.DIM, 'Nothing you can equip here matches.');
    elseif matched > shown then
        -- Say what was dropped. A silent truncation reads as "that's everything
        -- you own", and the piece you wanted is the one that isn't there.
        imgui.Separator();
        imgui.TextColored(COL.DIM, string.format('+%d more -- type to narrow.', matched - shown));
    end
    imgui.EndChild();
end

-- --------------------------------------------------------------------------
-- The window.
-- --------------------------------------------------------------------------

local PIN_BOX = { 0.55, 0.13, 0.13, 1.0 };   -- red: this slot is pinned

-- Rendered INDEPENDENTLY of the main dlac box (gearui's d3d_present calls this
-- directly, the lockstyle-window pattern) -- NOT via uihost's `window` contract.
-- That contract renders inside drawWindow, which returns early unless the main
-- window is open, and the whole point of this window is that it stays up while
-- you play. gearui owns the theme bracket around this call.
function M.render()
    if imgui == nil or ui._gearFloat ~= true then return; end
    local job, level = S.getPlayerInfo();
    S.buildAllEquip();          -- catalog indexes: the hover tooltip needs them,
                                -- and drawWindow (which normally does this every
                                -- frame) is not running when the main box is shut

    if type(ui._gfPos) == 'table' then
        imgui.SetNextWindowPos({ ui._gfPos[1], ui._gfPos[2] }, ImGuiCond_FirstUseEver or 0);
    end
    imgui.SetNextWindowSize({ 212, 252 }, ImGuiCond_FirstUseEver or 0);

    local open = { true };
    if imgui.Begin('Equipment##dlac_float', open, ImGuiWindowFlags_NoScrollbar or 0) then
        S.renderSlotGrid('float', 182, nil,
            function(sl) return S.getEquippedId(sl.equip); end,
            function(sl)
                local id = S.getEquippedId(sl.equip);
                return fmt.truncate(id and (S.displayName(id) or ('#' .. tostring(id))) or '(empty)', 18);
            end,
            function(labelKey)                          -- left-click also opens it:
                _openFor = labelKey;                    -- RMB is the ask, LMB is the
            end,                                        -- guarantee (gearmove's rule)
            function(sl) return S.lookupById(S.getEquippedId(sl.equip)); end,
            190,
            {
                boxColorOf = function(sl)
                    if pins.isPinned(sl.label) then return PIN_BOX; end
                    return nil;
                end,
                onRightClick = function(labelKey) _openFor = labelKey; end,
            });

        local n = pins.count();
        if n > 0 then
            imgui.TextColored(COL.SCORE, string.format('%d pinned', n));
            imgui.SameLine(0, 8);
            if imgui.SmallButton('Unpin all') then pins.clearAll(); end
        else
            imgui.TextColored(COL.DIM, 'Right-click a slot to pin.');
        end

        -- Popup at WINDOW scope: the grid detected the click inside its child,
        -- but OpenPopup/BeginPopup have to share a scope, so both happen here.
        if _openFor ~= nil then
            _menuSlot, _drillItem = _openFor, nil;
            _search[1] = '';
            _openFor = nil;
            imgui.OpenPopup(POPUP);
        end
        if imgui.BeginPopup(POPUP) then
            renderPinMenu(job, level);
            imgui.EndPopup();
        end

        -- Remember where it was dragged, but save only once the drag SETTLES (the
        -- TP float's pattern): position changes every frame while you drag, and
        -- marking the flags dirty per frame would rewrite uiflags.lua ~60x/sec.
        pcall(function()
            local x, y = imgui.GetWindowPos();
            if type(x) == 'table' then y = (x[2] or x.y); x = (x[1] or x.x); end
            if type(x) == 'number' and type(y) == 'number' then
                x, y = math.floor(x), math.floor(y);
                local p = ui._gfPos;
                if type(p) ~= 'table' or p[1] ~= x or p[2] ~= y then
                    ui._gfPos = { x, y };
                    ui._gfMovedAt = os.clock() + 1;
                end
            end
        end);
    end
    imgui.End();
    if ui._gfMovedAt ~= nil and os.clock() >= ui._gfMovedAt then
        ui._gfMovedAt = nil;
        ui._flagsDirty = true;
    end

    if open[1] == false then                            -- window's own X
        ui._gearFloat = false;
        ui._flagsDirty = true;
    end
end

M._triggerChoices = triggerChoices;   -- test seam
M.hasMenu = hasMenu;
return M;
