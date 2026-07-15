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
    pin an item into it; a pinned slot's box turns RED. SHIFT+drag moves it
    (equipmon's gesture -- and the only one available: see the NoMove note in
    M.render). The Equipped tab's slider scales it; the scale is one number,
    `opts.box`, that renderSlotGrid derives the icon and frame pad from.

    Right-click: IsMouseClicked(1) + IsItemHovered feeding the ordinary
    OpenPopup/BeginPopup pair -- the pattern gearmove field-confirmed on
    feature/storage-move. (BeginPopupContextItem is the one that failed twice and
    put "right-click" on the dead-ends list; do not reach for it.) The grid
    reports the click from inside its own BeginChild and this module opens the
    popup at WINDOW scope, because OpenPopup and BeginPopup must share a scope.

    FIELD-CONFIRMED 07-15 (Henrik): right-click opens the menu AND imgui.BeginMenu
    cascades in this binding -- the first Lua caller of BeginMenu in this install.
    The drill-down fallback below is now dead weight kept only as a guard for a
    binding change; hasMenu has never been false in the field.

    Two hard-won imgui facts live in this file, both about the same rule -- a
    SUBMENU is drawn outside the rect of the window that declares it:
      * the pin list must NOT sit in a BeginChild, or moving the mouse toward a
        submenu leaves the child and ImGui tears down the whole popup;
      * so the popup is bounded with SetNextWindowSizeConstraints instead.

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
local BOX0   = 40;        -- renderSlotGrid's default box; scale 1.0 == the tab's size

-- Shift: the Win32 key state, straight from user32. TWO earlier attempts failed in
-- the field, and the reason is the same both times -- they asked something that
-- only knows about shift SOMETIMES:
--
--   1. imgui.GetIO().KeyShift -- dead during normal play. Ashita only feeds the
--      keyboard into ImGui's IO when ImGui wants it; standing in the world it does
--      not. (fancychat DOES use it -- inside its chat-INPUT mode, where ImGui has
--      focus. Proven in this install, wrong for this context.)
--   2. Ashita's `key` (WNDPROC) event, VK_SHIFT + the lparam transition bit --
--      equipmon's exact code. Also never fired here.
--
-- GetKeyState asks the OS, so it is true whenever the key is physically down, no
-- matter who has focus or which input path the client is using. This is what trove
-- uses -- its comment reads "Win32 key state for shift-to-move", the same gesture.
-- The high bit means "down", hence < 0. cdef is pcall'd because another addon in
-- this Lua state may have declared the same symbol already.
-- BOTH user32 reads, OR'd. They differ in a way that matters here: GetKeyState is
-- relative to the calling thread's message queue, GetAsyncKeyState is the physical
-- key. trove uses the first, XIUI the second; after two field misses this is not
-- the place to bet on one. The high bit means "down", hence < 0 on the short.
local ffi = (function()
    local ok, m = pcall(require, 'ffi');      -- ffi is not a plain table: guard on nil,
    return (ok and m ~= nil) and m or nil;    -- the itemicons pattern, not try()
end)();
if ffi ~= nil then
    -- pcall'd separately: another addon in this Lua state may have declared either
    -- symbol already, and one failing must not take the other down with it.
    pcall(ffi.cdef, 'short __stdcall GetKeyState(int nVirtKey);');
    pcall(ffi.cdef, 'short __stdcall GetAsyncKeyState(int vKey);');
end
local VK_SHIFT = 0x10;
local function shiftDown()
    if ffi == nil then return false; end
    local ok, v = pcall(function() return ffi.C.GetAsyncKeyState(VK_SHIFT) < 0; end);
    if ok and v == true then return true; end
    local ok2, v2 = pcall(function() return ffi.C.GetKeyState(VK_SHIFT) < 0; end);
    return ok2 and v2 == true;
end
-- Test seam: the smoke suite overrides this. The OS call cannot run headless, so
-- what the tests cover is the LATCH and the click suppression around it -- the
-- logic that broke -- not the key read itself.
M.shiftHeld = shiftDown;

-- The window's scale, clamped HERE rather than at the slider: uiflags.lua is a
-- plain Lua file a player can edit, and a 0 or a negative there would collapse the
-- grid to nothing with no way back through the GUI.
M.SCALE_MIN, M.SCALE_MAX = 0.5, 3.0;
function M.scale()
    local s = tonumber(ui._gfScale) or 1.0;
    if s < M.SCALE_MIN then s = M.SCALE_MIN; end
    if s > M.SCALE_MAX then s = M.SCALE_MAX; end
    return s;
end
local scaleNow = M.scale;
local _openFor  = nil;    -- slot label whose menu should open next frame
local _menuSlot = nil;    -- slot the open popup belongs to
local _dragging = false;  -- shift+drag latch: set on press, cleared on release
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
    -- NO BeginChild around this list, deliberately. A submenu is drawn OUTSIDE the
    -- rect of the window it is declared in; inside a child, moving the mouse from
    -- one item toward its submenu leaves the child, ImGui decides the menu
    -- hierarchy lost the cursor, and it tears down the WHOLE popup -- Henrik:
    -- "the whole initial right click menu disappears when you keep moving the
    -- mouse to the next gear piece". The popup itself is size-constrained instead
    -- (see the SetNextWindowSizeConstraints before BeginPopup), so a long list
    -- still scrolls without a child window in the menu chain.
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

    -- Unpin-all lives here rather than under the grid: the window is chrome-less
    -- now, and a stray line of text below it would put the box back.
    if pins.count() > 0 then
        imgui.Separator();
        if imgui.Selectable(string.format('Remove all %d pins', pins.count())) then
            pins.clearAll();
            pcall(function() imgui.CloseCurrentPopup(); end);
        end
    end
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

    -- Once, not FirstUseEver (the TP float's choice): FirstUseEver defers to
    -- imgui.ini if ImGui remembered this window itself, and OUR uiflags copy is
    -- the one the addon maintains. Applies on the session's first frame, then the
    -- shift-drag below owns the position.
    if type(ui._gfPos) == 'table' then
        imgui.SetNextWindowPos({ ui._gfPos[1], ui._gfPos[2] }, ImGuiCond_Once or 0);
    end

    -- Chrome off (Henrik: "remove the actual box or hide the borders") -- no title
    -- bar, no border, no background: just the 16 boxes, equipmon-style.
    -- AlwaysAutoResize sizes the window to the tight grid, so there is no size to
    -- remember and none to get wrong.
    --
    -- NoMove is ALWAYS on and the window is moved by hand under Shift instead
    -- (equipmon's gesture). ImGui's own drag only moves a window from a spot no
    -- item claimed, and a 4x4 of ImageButtons leaves no such spot -- the old
    -- "drag it by the invisible rim" was the best that flag could do, and it was
    -- a bad answer. NoMove also stops the window sliding when you grab a slot.
    local shift = M.shiftHeld();       -- through the seam, so the tests can drive it
    local FL = (ImGuiWindowFlags_NoTitleBar or 0) + (ImGuiWindowFlags_NoResize or 0)
             + (ImGuiWindowFlags_NoScrollbar or 0) + (ImGuiWindowFlags_NoCollapse or 0)
             + (ImGuiWindowFlags_AlwaysAutoResize or 0) + (ImGuiWindowFlags_NoBackground or 0)
             + (ImGuiWindowFlags_NoMove or 0);
    -- Padding to 0 as well now that nothing needs a drag rim: the window is then
    -- EXACTLY the grid. Popped straight after Begin -- both vars are consumed
    -- there, and leaving them pushed would flatten the pin popup's own frame.
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });

    -- No title bar means no close button, so this table is never written back --
    -- but keep passing one (force-true each frame, the TP float's shape) rather
    -- than nil: this binding is fed a table everywhere else. The Equipped tab's
    -- checkbox is what closes the window.
    ui._gfOpenT = ui._gfOpenT or { true };
    ui._gfOpenT[1] = true;
    local shown = imgui.Begin('##dlac_float', ui._gfOpenT, FL);
    imgui.PopStyleVar(2);            -- WindowBorderSize + WindowPadding: consumed by
                                     -- Begin; the pin popup below must not inherit them
    if shown then
        local box  = math.floor(BOX0 * scaleNow() + 0.5);
        local grid = box * 4;        -- tight: no spacing, no child padding
        S.renderSlotGrid('float', grid, nil,
            function(sl) return S.getEquippedId(sl.equip); end,
            function(sl)
                local id = S.getEquippedId(sl.equip);
                return fmt.truncate(id and (S.displayName(id) or ('#' .. tostring(id))) or '(empty)', 18);
            end,
            -- Left-click opens the menu too (RMB is the ask, LMB the guarantee) --
            -- but never while Shift is held or a drag is still latched: that click
            -- is a drag, and the button fires on RELEASE, by which time Shift may
            -- already be back up. `_dragging` is what covers that gap.
            function(labelKey) if not (shift or _dragging) then _openFor = labelKey; end end,
            function(sl) return S.lookupById(S.getEquippedId(sl.equip)); end,
            grid,
            {
                tight = true,
                box   = box,
                boxColorOf = function(sl)
                    if pins.isPinned(sl.label) then return PIN_BOX; end
                    return nil;
                end,
                onRightClick = function(labelKey) if not shift then _openFor = labelKey; end end,
            });

        -- Shift+drag anywhere on the grid moves the window. Done by hand because
        -- the ImageButton under the cursor owns the click, so ImGui would never
        -- move the window itself -- but the mouse state is global, so it reports
        -- the drag regardless of which item is active.
        --
        -- LATCHED: shift+press over the window starts it, and it then runs until
        -- the button comes up. Testing hover every frame instead would drop the
        -- drag the moment the cursor outran the window (or crossed the pin popup),
        -- and re-testing shift would drop it if you let the key go mid-drag --
        -- equipmon needs Shift only to START, and this matches.
        -- Starts on IsMouseDown, not IsMouseClicked: Clicked is true for exactly one
        -- frame, so any frame we miss (or a Shift pressed just after the button
        -- went down) loses the gesture entirely. Down is forgiving and the latch
        -- makes it idempotent.
        -- RectOnly, not AllowWhenBlockedByActiveItem alone: it is that flag PLUS
        -- AllowWhenBlockedByPopup and AllowWhenOverlapped (libs/imgui.lua:332), so
        -- the grid still counts as hovered with a button held, the pin popup up, or
        -- another window overlapping. It is also the combo fancychat uses, i.e. the
        -- one with field miles on it here.
        local LMB = ImGuiMouseButton_Left or 0;
        local overWin = imgui.IsWindowHovered(ImGuiHoveredFlags_RectOnly
                                              or ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0);
        if not _dragging and shift and imgui.IsMouseDown(LMB) and overWin then
            _dragging = true;
            pcall(function() imgui.ResetMouseDragDelta(LMB); end);
        end
        if _dragging then
            if not imgui.IsMouseDown(LMB) then
                _dragging = false;
                ui._gfMovedAt = os.clock() + 1;      -- persist once the drag settles
            else
                pcall(function()
                    local dx, dy = imgui.GetMouseDragDelta(LMB);
                    if type(dx) == 'table' then dy = (dx[2] or dx.y); dx = (dx[1] or dx.x); end
                    if type(dx) == 'number' and type(dy) == 'number' and (dx ~= 0 or dy ~= 0) then
                        local wx, wy = imgui.GetWindowPos();
                        if type(wx) == 'table' then wy = (wx[2] or wx.y); wx = (wx[1] or wx.x); end
                        imgui.SetWindowPos({ wx + dx, wy + dy });
                        imgui.ResetMouseDragDelta(LMB);
                    end
                end);
            end
        end

        -- Shift held: outline the grid gold. A window with no frame has no other
        -- way to say "grabbable now", and the drag is otherwise invisible until it
        -- works. It also answers, in one glance, WHICH half is broken if it ever
        -- misbehaves again: outline = the key read is fine, look at the drag.
        if shift or _dragging then
            pcall(function()
                local x, y = imgui.GetWindowPos();
                if type(x) == 'table' then y = (x[2] or x.y); x = (x[1] or x.x); end
                imgui.GetWindowDrawList():AddRect({ x - 1, y - 1 }, { x + grid + 1, y + grid + 1 },
                    imgui.GetColorU32({ 0.95, 0.80, 0.35, 0.90 }), 0, 0, 2);
            end);
        end

        -- Popup at WINDOW scope: the grid detected the click inside its child,
        -- but OpenPopup/BeginPopup have to share a scope, so both happen here.
        if _openFor ~= nil then
            _menuSlot, _drillItem = _openFor, nil;
            _search[1] = '';
            _openFor = nil;
            imgui.OpenPopup(POPUP);
        end
        -- Constrain the POPUP instead of wrapping its list in a child window: a
        -- child in the menu chain is what killed the cascade (see renderPinMenu).
        -- BeginPopup forces AlwaysAutoResize on popups, so a constraint is the way
        -- to bound one -- clamped, it grows a scrollbar by itself.
        --
        -- Safe to call unconditionally even on the frames the popup is shut: this
        -- binding is ImGui >= 1.77 (the header declares ImGuiPopupFlags), and
        -- BeginPopup's early-out consumes the next-window data exactly as Begin
        -- would. Otherwise the constraint would leak onto the next window opened
        -- anywhere in the frame -- including another addon's.
        imgui.SetNextWindowSizeConstraints({ 250, 0 }, { 380, 460 });
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
    -- NOTHING to pop here: both vars were already popped right after Begin (line
    -- above the grid). An extra PopStyleVar underflows ImGui's style stack, which
    -- is not a Lua error -- it is an EXCEPTION_ACCESS_VIOLATION in Present that
    -- takes the whole client down. Shipped exactly that in e85cc43 by adding the
    -- second push without removing this round's older pop. Count the pushes.
    imgui.End();
    if ui._gfMovedAt ~= nil and os.clock() >= ui._gfMovedAt then
        ui._gfMovedAt = nil;
        ui._flagsDirty = true;
    end
end

M._triggerChoices = triggerChoices;   -- test seam
M.hasMenu = hasMenu;

-- Published so the Equipped tab's size slider can share this module's clamp
-- instead of keeping a second copy of the range. gearui requires equippedui
-- BEFORE floatgear, so the tab must read host.services.floatgear at CALL time
-- (it does) rather than capture it at load.
host.provide({ floatgear = M });

return M;
