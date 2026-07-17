--[[
    dlac/helmbar.lua -- floating HELM control bar (craftbar's gathering twin;
    docs/design/helm-gear.md).

    A small always-available window: the four category glyphs (click to
    select -- the engine wears that category's gear while the switch is ON),
    the on/off pill, and a status line: the category's venture points, the
    break-roll rating (+5 = tool breakage impossible -- excavation excepted,
    As Square Enix Intended), and the Surveyor total. The overlay applies to
    IDLE ONLY (dispatch v59 gates it to Default) -- an action event always
    wins its own gear.

    Toggle: /dl helm bar  (or the button in the Automations panel).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
if not _iok then return M; end
local hw = require('dlac\\feature\\helmwatch');
local _uok, uistyle = pcall(require, 'dlac\\ui\\uistyle');
_uok = _uok and type(uistyle) == 'table';

local ORDER = { 'Harvesting', 'Excavation', 'Logging', 'Mining' };

-- Category glyphs come from helmui's loader (same texture cache both places).
local function texture(g)
    local ok, ui = pcall(require, 'dlac\\ui\\helmui');
    if ok and type(ui) == 'table' and type(ui.texture) == 'function' then return ui.texture(g); end
    return nil;
end

-- One clickable category glyph (bright = selected). Returns true on click.
local function gatherButton(g, selected, size)
    local drew, tex = false, texture(g);
    if tex ~= nil then
        drew = pcall(function()
            local ffi = require('ffi');
            imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { size, size },
                { 0, 0 }, { 1, 1 }, selected and { 1, 1, 1, 1 } or { 1, 1, 1, 0.4 });
        end);
    end
    if not drew then
        if imgui.Button(g:sub(1, 4) .. '##hb_' .. g, { size, size }) then return true; end
        return false;
    end
    local clicked = imgui.IsItemClicked();
    if imgui.IsItemHovered() then imgui.SetTooltip(g .. '  -- click to gear up for this (idle only)'); end
    return clicked;
end

-- The on/off pill is craftbar's (one implementation, two bars).
local function onOffSwitch(on, id, tipOn, tipOff)
    local ok, cb = pcall(require, 'dlac\\ui\\craftbar');
    if ok and type(cb) == 'table' and type(cb.onOffSwitch) == 'function' then
        return cb.onOffSwitch(on, id, tipOn, tipOff);
    end
    if imgui.Button((on and 'ON' or 'OFF') .. '##hbonoff_' .. id, { 46, 22 }) then return true; end
    return false;
end

local isOpen = { true };
local BAR_MIN_W = 300;   -- fits the status line with air

local function centerNext(availW, rowW)
    local indent = math.max(0, math.floor((availW - rowW) / 2));
    if indent > 0 then imgui.Dummy({ 0, 0 }); imgui.SameLine(indent); end
end

function M.render()
    if not hw.barVisible then return; end
    local pushed = _uok and uistyle.push();
    pcall(function()
        imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always or 0);
        isOpen[1] = true;
        if imgui.Begin('dlac HELM##dlac_helmbar', isOpen, ImGuiWindowFlags_AlwaysAutoResize or 0) then
            local availW = imgui.GetContentRegionAvail();
            if type(availW) ~= 'number' or availW < BAR_MIN_W then availW = BAR_MIN_W; end
            local sel = hw.getGather();
            local on = hw.isEnabled();
            -- Row 1, centered: the four category glyphs + the on/off switch.
            centerNext(availW, 4 * 30 + 3 * 6 + 6 + 46);
            for _, g in ipairs(ORDER) do
                if gatherButton(g, sel == g, 30) then hw.selectGather(g); end
                imgui.SameLine(0, 6);
            end
            if onOffSwitch(on, 'helmbar',
                'HELM idle set is ON -- gathering gear stays on while idle. Click to turn off.',
                'Set HELM Idle: wears your best gathering gear whenever idle, until turned off.\n(Auto HELM -- swing-detected auto-equip -- lives in the Automations panel or /dl helm auto.)')
            then hw.setEnabled(not on); end
            imgui.Separator();
            -- Status line: points + rating + surveyor for the selected category.
            if sel == nil then
                imgui.TextColored({ 0.55, 0.55, 0.55, 1 }, 'Pick a category to gear for.');
            else
                local vp = nil;
                pcall(function() vp = hw.pointsFor(sel); end);
                local helm, surv, bp = 0, 0, false;
                pcall(function() helm, surv, bp = hw.rating(sel); end);
                imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, sel .. ' VP:');
                imgui.SameLine(0, 6);
                imgui.TextColored(vp ~= nil and { 0.95, 0.85, 0.45, 1 } or { 0.55, 0.55, 0.55, 1 },
                    vp ~= nil and tostring(vp) or '?');
                imgui.SameLine(0, 14);
                imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Rating:');
                imgui.SameLine(0, 6);
                if sel == 'Excavation' then
                    imgui.TextColored({ 0.55, 0.55, 0.55, 1 }, string.format('%d (tools break anyway -- SE\'s little joke)', helm));
                elseif bp then
                    imgui.TextColored({ 0.45, 0.90, 0.45, 1 }, string.format('%d -- BREAK-PROOF', helm));
                else
                    imgui.TextColored({ 0.85, 0.80, 0.35, 1 }, string.format('%d/5', helm));
                end
                if surv > 0 then
                    imgui.SameLine(0, 14);
                    imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, string.format('Surveyor +%d', surv));
                end
            end
            -- Auto-detect breadcrumb + the Auto HELM hold state.
            if hw.isAutoHelm() then
                if hw.autoActive() then
                    imgui.TextColored({ 0.45, 0.90, 0.45, 1 },
                        string.format('AUTO: wearing %s gear', tostring(hw.getGather() or '?')));
                else
                    imgui.TextColored({ 0.55, 0.55, 0.55, 1 }, 'Auto HELM armed -- waiting for a swing');
                end
            elseif hw.lastDetect ~= nil and (os.clock() - (hw.lastDetect.at or 0)) < 120 then
                imgui.TextColored({ 0.55, 0.55, 0.55, 1 },
                    string.format('Detected: %s', hw.lastDetect.gather));
            end
            imgui.Dummy({ BAR_MIN_W, 1 });   -- enforces the min width under AlwaysAutoResize
        end
        imgui.End();
        if isOpen[1] == false then hw.barVisible = false; end
    end);
    if pushed then uistyle.pop(); end
end

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('d3d_present', 'dlac-helmbar-render', function()
        pcall(M.render);
    end);
end

return M;
