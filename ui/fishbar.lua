--[[
    dlac/fishbar.lua -- floating fishing control bar (craftbar/helmbar's third
    sibling; docs/design/fishing-gear.md).

    A small always-available window: the on/off pill ("Set Fish Idle" -- the
    engine wears the fishing kit while idle, combat gear always wins), the
    target fish, and the resolved rod + bait with the bait count left. No
    category glyphs -- fishing is one activity; the rod's own item icon is
    the identity (itemicons -- zero new assets). Target picking lives in the
    Automations panel (Auto Fish Set).

    Toggle: /dl fish bar  (or the button in the Automations panel).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
if not _iok then return M; end
local fw = require('dlac\\feature\\fishwatch');
local _fcok, fcalc = pcall(require, 'dlac\\feature\\fishcalc');
_fcok = _fcok and type(fcalc) == 'table';
local _uok, uistyle = pcall(require, 'dlac\\ui\\uistyle');
_uok = _uok and type(uistyle) == 'table';
local _icok, icons = pcall(require, 'dlac\\ui\\itemicons');
_icok = _icok and type(icons) == 'table' and type(icons.renderIcon) == 'function';

local COL_TEXT = { 0.70, 0.70, 0.70, 1 };
local COL_DIM  = { 0.55, 0.55, 0.55, 1 };
local COL_GOLD = { 0.95, 0.85, 0.45, 1 };
local COL_GREEN = { 0.45, 0.90, 0.45, 1 };
local COL_WARN = { 1.00, 0.60, 0.30, 1 };

-- The on/off pill is craftbar's (one implementation, three bars now).
local function onOffSwitch(on, id, tipOn, tipOff)
    local ok, cb = pcall(require, 'dlac\\ui\\craftbar');
    if ok and type(cb) == 'table' and type(cb.onOffSwitch) == 'function' then
        return cb.onOffSwitch(on, id, tipOn, tipOff);
    end
    if imgui.Button((on and 'ON' or 'OFF') .. '##fbonoff_' .. id, { 46, 22 }) then return true; end
    return false;
end

-- Equippable-bag counts, ~1s cached (bait count + the dropdown lists).
local _cnt = { at = 0, v = nil };
local function bagCounts()
    if os.clock() > _cnt.at then
        _cnt.at = os.clock() + 1;
        _cnt.v = nil;
        pcall(function()
            local oc = require('dlac\\gear\\ownedcache');
            local t = oc.counts();
            if type(t) == 'table' then _cnt.v = t; end
        end);
    end
    return _cnt.v;
end
local function baitCount(id)
    if id == nil then return nil; end
    local t = bagCounts();
    return (t ~= nil) and (t[id] or 0) or nil;
end

-- ---------------------------------------------------------------------------
-- Manual override dropdowns (Henrik, field round 5: "manual overrides beat
-- automation, every day"). Clicking the rod or bait name opens a popup of
-- what the bags actually hold; a pick PINS (fishwatch holds it until the
-- target changes or the item vanishes), AUTO hands the slot back.
-- ---------------------------------------------------------------------------
local function riskTag(v)
    if v.ok then return 'SAFE'; end
    local parts = {};
    if (v.lose or 0) > 0 then parts[#parts + 1] = string.format('lose %d%%', v.lose); end
    if (v.snap or 0) > 0 then parts[#parts + 1] = string.format('snap %d%%', v.snap); end
    if (v.brk or 0) > 0 then parts[#parts + 1] = string.format('break %d%%', v.brk); end
    return table.concat(parts, ', ');
end
local function itemName(id, fallback)
    local n = type(fw._clientName) == 'function' and fw._clientName(id) or nil;
    return n or fallback or ('item ' .. tostring(id));
end

local function rodPopup()
    if not imgui.BeginPopup('##fbrodpop') then return; end
    if imgui.Selectable('AUTO -- best rod for the target##fbrodauto') then fw.setRod(nil); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Back to automatic: the server\'s own fail math picks the\nsafest owned rod (Ebisu > Lu Shang\'s > the field).');
    end
    local db = _fcok and fcalc.db() or nil;
    local counts = bagCounts();
    if db ~= nil and counts ~= nil then
        imgui.Separator();
        local ownedSet, any = {}, false;
        for id in pairs(db.rods) do
            if (counts[id] or 0) > 0 then ownedSet[id] = true; any = true; end
        end
        if not any then
            imgui.TextDisabled('no rods in your bags');
        else
            local tid = fw.getTarget();
            local f = tid ~= nil and db.fish[tid] or nil;
            if f ~= nil then
                local eff = (fw.playerFishSkill() or 0) + (fcalc.wornFishTotal ~= nil and fcalc.wornFishTotal(counts) or 0);
                for _, r in ipairs(fcalc.rodsFor(f, eff, ownedSet)) do
                    if r.owned then
                        local lbl = string.format('%s  --  %s##fbrod%d',
                            itemName(r.id, (r.rod or {}).n), riskTag(r.v), r.id);
                        if imgui.Selectable(lbl) then fw.setRod(r.id); end
                    end
                end
            else
                local rows = {};
                for id in pairs(ownedSet) do
                    rows[#rows + 1] = { id = id, rod = db.rods[id] };
                end
                table.sort(rows, function(a, b)
                    local ar = fcalc.legRank ~= nil and fcalc.legRank(a.id) or 0;
                    local br = fcalc.legRank ~= nil and fcalc.legRank(b.id) or 0;
                    if ar ~= br then return ar > br; end
                    if ((a.rod or {}).rating or 0) ~= ((b.rod or {}).rating or 0) then
                        return ((a.rod or {}).rating or 0) > ((b.rod or {}).rating or 0);
                    end
                    return ((a.rod or {}).n or '') < ((b.rod or {}).n or '');
                end);
                for _, r in ipairs(rows) do
                    if imgui.Selectable(string.format('%s##fbrod%d', itemName(r.id, (r.rod or {}).n), r.id)) then
                        fw.setRod(r.id);
                    end
                end
            end
        end
    end
    imgui.EndPopup();
end

local function baitPopup()
    if not imgui.BeginPopup('##fbbaitpop') then return; end
    local tid = fw.getTarget();
    if imgui.Selectable('AUTO -- best bait for the target##fbbaitauto') then fw.setBait(nil); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(tid ~= nil
            and 'Back to automatic: best-power owned bait for the target\n(an isolation-row pick stays while its stack lasts).'
            or 'Back to automatic. Without a target fish, auto equips NO bait.');
    end
    local db = _fcok and fcalc.db() or nil;
    local counts = bagCounts();
    if db ~= nil and counts ~= nil then
        imgui.Separator();
        local affine, shownAffine = {}, 0;   -- baits the target actually bites, popup top
        if tid ~= nil then
            for _, e in ipairs(fcalc.baitsFor(tid)) do
                if (counts[e.id] or 0) > 0 then
                    affine[e.id] = true;
                    shownAffine = shownAffine + 1;
                    if imgui.Selectable(string.format('%s x%d  (power %d)##fbbait%d',
                            itemName(e.id, (e.bait or {}).n), counts[e.id], e.power or 0, e.id)) then
                        fw.setBait(e.id);
                    end
                end
            end
        end
        local rest = {};
        for id, b in pairs(db.baits) do
            if (counts[id] or 0) > 0 and not affine[id] then
                rest[#rest + 1] = { id = id, bait = b };
            end
        end
        table.sort(rest, function(a, b) return ((a.bait or {}).n or '') < ((b.bait or {}).n or ''); end);
        if #rest > 0 and shownAffine > 0 then imgui.Separator(); end
        for _, e in ipairs(rest) do
            local warn = (tid ~= nil) and '  -- target will NOT bite this' or '';
            if imgui.Selectable(string.format('%s x%d%s##fbbait%d',
                    itemName(e.id, (e.bait or {}).n), counts[e.id], warn, e.id)) then
                fw.setBait(e.id);
            end
        end
        if shownAffine == 0 and #rest == 0 then imgui.TextDisabled('no bait in your bags'); end
    end
    imgui.EndPopup();
end

local isOpen = { true };
local BAR_MIN_W = 280;

function M.render()
    if not fw.barVisible then return; end
    local pushed = _uok and uistyle.push();
    pcall(function()
        imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always or 0);
        isOpen[1] = true;
        if imgui.Begin('dlac Fishing##dlac_fishbar', isOpen, ImGuiWindowFlags_AlwaysAutoResize or 0) then
            local on = fw.isEnabled();
            local _, tname = fw.getTarget();
            local rodId, rodName = fw.getRod();
            local baitId, baitName = fw.getBait();
            -- Row 1: pill + target.
            if onOffSwitch(on, 'fishbar',
                'Fishing idle set is ON -- rod, bait and fishing gear stay on while idle. Click to turn off.',
                'Set Fish Idle: wears your best fishing kit whenever idle, until turned off.\nRod and bait follow the target fish (Automations > Auto Fish Set).')
            then fw.setEnabled(not on); end
            imgui.SameLine(0, 10);
            if tname ~= nil then
                imgui.TextColored(COL_GOLD, tostring(tname));
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Target fish. Change it in Automations > Auto Fish Set\n(or /dl fish target <name>).');
                end
            else
                imgui.TextColored(COL_DIM, 'no target fish');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Pick a target in Automations > Auto Fish Set -- rod and bait\nfollow it. Without one you still get gear + your best rod.');
                end
            end
            imgui.Separator();
            -- Row 2: rod + bait, icons first (the identity); the names are
            -- BUTTONS now -- click for the manual-override dropdown (* marks
            -- a manual pick holding the slot).
            if _icok then icons.renderIcon(rodId, 18); end
            local rodLbl = (rodName ~= nil and tostring(rodName) or 'no rod picked')
                           .. (fw.rodPinned() and ' *' or '');
            if imgui.SmallButton(rodLbl .. '##fbrodbtn') then imgui.OpenPopup('##fbrodpop'); end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Click: pick the rod yourself. A manual pick (*) beats auto\nuntil the target changes or the rod leaves your bags.');
            end
            rodPopup();
            imgui.SameLine(0, 12);
            if _icok and baitId ~= nil then icons.renderIcon(baitId, 18); end
            local n = baitCount(baitId);
            local baitLbl = (baitName ~= nil
                    and (tostring(baitName) .. (n ~= nil and (' x' .. n) or ''))
                    or 'no bait')
                    .. (fw.baitPinned() and ' *' or '');
            if imgui.SmallButton(baitLbl .. '##fbbaitbtn') then imgui.OpenPopup('##fbbaitpop'); end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Bait in your equippable bags -- a used-up stack re-equips\nitself; the LAST one gone auto-switches (chat line says so).\nClick: pick the bait yourself. A manual pick (*) beats auto\nwhile its stack lasts.');
            end
            baitPopup();
            -- Row 3: skill + VP breadcrumb.
            local sk = fw.playerFishSkill();
            local vp = fw.venturePoints();
            if sk ~= nil or vp ~= nil then
                imgui.TextColored(COL_DIM, string.format('skill %s   VP %s',
                    sk ~= nil and tostring(sk) or '?', vp ~= nil and tostring(vp) or '?'));
            end
            if on then
                imgui.SameLine(0, 10);
                imgui.TextColored(COL_GREEN, 'dressed while idle');
            end
            imgui.Dummy({ BAR_MIN_W, 1 });   -- enforces the min width under AlwaysAutoResize
        end
        imgui.End();
        if isOpen[1] == false then fw.barVisible = false; end
    end);
    if pushed then uistyle.pop(); end
end

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('d3d_present', 'dlac-fishbar-render', function()
        pcall(M.render);
    end);
end

return M;
