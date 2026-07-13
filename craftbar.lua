--[[
    dlac/craftbar.lua -- floating craft control bar.

    A small always-available window: an on/off switch, the eight craft glyphs
    (click to select + equip that craft's gear), and the goal (HQ / NQ /
    Skill-Up). This is the MANUAL model Henrik settled on -- you set your gear
    BEFORE synthing, when equipment changes are legal (auto-detection can't,
    since 0x096 is the first synth packet). The same controls live in the
    Automations panel; both drive the single craftwatch state.

    Toggle the window: /dl craft bar  (or the button in the Automations panel).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
if not _iok then return M; end
local cw = require('dlac\\craftwatch');
local _uok, uistyle = pcall(require, 'dlac\\uistyle');
_uok = _uok and type(uistyle) == 'table';

local ORDER = { 'Woodworking', 'Smithing', 'Goldsmithing', 'Clothcraft',
                'Leathercraft', 'Bonecraft', 'Alchemy', 'Cooking' };
local GOALS = { { 'hq', 'HQ', 62 }, { 'nq', 'NQ', 62 }, { 'skillup', 'Skill-Up', 86 } };

-- Craft glyph textures (assets/craft/<Craft>.png), lazy-loaded via D3DX.
local _tex = {};
local function texture(cr)
    local t = _tex[cr];
    if t ~= nil then return (t ~= false) and t or nil; end
    _tex[cr] = false;
    pcall(function()
        local ffi = require('ffi');
        local d3d8 = require('d3d8');
        pcall(ffi.cdef,
            'HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);');
        local dev = d3d8.get_device();
        local path = string.format('%saddons\\dlac\\assets\\craft\\%s.png', AshitaCore:GetInstallPath(), cr);
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) == 0 then
            _tex[cr] = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
        end
    end);
    return (_tex[cr] ~= false) and _tex[cr] or nil;
end
M.texture = texture;

-- One clickable craft glyph (bright when selected, dim otherwise). Shared with
-- the Automations panel. Returns true on click.
function M.craftButton(cr, selected, size)
    local drew, tex = false, texture(cr);
    if tex ~= nil then
        drew = pcall(function()
            local ffi = require('ffi');
            imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { size, size },
                { 0, 0 }, { 1, 1 }, selected and { 1, 1, 1, 1 } or { 1, 1, 1, 0.4 });
        end);
        if not drew then
            drew = pcall(function()
                local ffi = require('ffi');
                imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { size, size });
            end);
        end
    end
    if not drew then
        if imgui.Button(cr:sub(1, 4) .. '##cb_' .. cr, { size, size }) then return true; end
        return false;
    end
    local clicked = imgui.IsItemClicked();
    if imgui.IsItemHovered() then imgui.SetTooltip(cr .. '  -- click to equip this craft\'s gear'); end
    return clicked;
end

-- Pill on/off switch: green knob-right = active, red knob-left = inactive
-- (Henrik). Draw-list pill; falls back to a colored button if the draw list
-- isn't available. Returns true when toggled this frame.
function M.onOffSwitch(on, id)
    local W, H = 46, 22;
    local toggled = false;
    local ok = pcall(function()
        local x, y = imgui.GetCursorScreenPos();
        imgui.InvisibleButton('##onoff_' .. id, { W, H });
        toggled = imgui.IsItemClicked();
        local dl = imgui.GetWindowDrawList();
        local track = on and 0xFF2E8B2E or 0xFF2E2E9E;   -- ARGB: green / red
        local knob  = 0xFFEEEEEE;
        dl:AddRectFilled({ x, y }, { x + W, y + H }, track, H / 2, ImDrawCornerFlags_All or 0);
        local kx = on and (x + W - H / 2) or (x + H / 2);
        dl:AddCircleFilled({ kx, y + H / 2 }, H / 2 - 3, knob, 16);
    end);
    if not ok then                                       -- no draw list: colored button
        if ImGuiCol_Button ~= nil then
            imgui.PushStyleColor(ImGuiCol_Button, on and { 0.18, 0.55, 0.18, 1 } or { 0.62, 0.18, 0.18, 1 });
        end
        if imgui.Button((on and 'ON' or 'OFF') .. '##onoff_' .. id, { W, H }) then toggled = true; end
        if ImGuiCol_Button ~= nil then imgui.PopStyleColor(1); end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(on and 'Auto craft set is ON -- click to turn off.'
                           or  'Auto craft set is OFF -- click to turn on (equips your selected craft).');
    end
    return toggled;
end

local isOpen = { true };
function M.render()
    if not cw.barVisible then return; end
    local pushed = _uok and uistyle.push();
    pcall(function()
        imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always or 0);
        isOpen[1] = true;
        if imgui.Begin('dlac Craft##dlac_craftbar', isOpen, ImGuiWindowFlags_AlwaysAutoResize or 0) then
            local sel = cw.getCraft();
            local on = cw.isEnabled();
            for i, cr in ipairs(ORDER) do
                if M.craftButton(cr, sel == cr, 30) then cw.selectCraft(cr); end
                imgui.SameLine(0, 6);
            end
            -- On/off switch to the RIGHT of the icons.
            imgui.SameLine(0, 6);
            if M.onOffSwitch(on, 'bar') then cw.setEnabled(not on); end
            imgui.Separator();
            local goal = cw.getGoal();
            imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Goal:'); imgui.SameLine(0, 6);
            for i, gd in ipairs(GOALS) do
                local gon = (goal == gd[1]);
                if gon then imgui.PushStyleColor(ImGuiCol_Button, { 0.16, 0.55, 0.24, 1 }); end
                if imgui.Button(gd[2] .. '##cbgoal' .. gd[1], { gd[3], 20 }) then cw.setGoal(gd[1]); end
                if gon then imgui.PopStyleColor(1); end
                if i < #GOALS then imgui.SameLine(0, 4); end
            end
        end
        imgui.End();
        if isOpen[1] == false then cw.barVisible = false; end
    end);
    if pushed then uistyle.pop(); end
end

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('d3d_present', 'dlac-craftbar-render', function()
        pcall(M.render);
    end);
end

return M;
