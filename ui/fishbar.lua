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

-- Bait count left (equippable bags), ~1s cached.
local _cnt = { at = 0, v = nil };
local function baitCount(id)
    if id == nil then return nil; end
    if os.clock() > _cnt.at then
        _cnt.at = os.clock() + 1;
        _cnt.v = nil;
        pcall(function()
            local oc = require('dlac\\gear\\ownedcache');
            local t = oc.counts();
            if type(t) == 'table' then _cnt.v = t; end
        end);
    end
    return (_cnt.v ~= nil) and (_cnt.v[id] or 0) or nil;
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
            -- Row 2: rod + bait, icons first (the identity).
            if _icok then icons.renderIcon(rodId, 18); end
            imgui.TextColored(rodName ~= nil and COL_TEXT or COL_DIM,
                rodName ~= nil and tostring(rodName) or 'no rod picked');
            if baitName ~= nil then
                imgui.SameLine(0, 12);
                if _icok then icons.renderIcon(baitId, 18); end
                local n = baitCount(baitId);
                local col = COL_TEXT;
                if n ~= nil and n == 0 then col = COL_WARN; end
                imgui.TextColored(col, string.format('%s%s', tostring(baitName),
                    n ~= nil and (' x' .. n) or ''));
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Bait in your equippable bags. A used-up stack re-equips\nitself; when the LAST one goes, the next owned bait for the\ntarget takes over (chat line says so).');
                end
            end
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
