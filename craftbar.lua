--[[
    dlac/craftbar.lua -- floating craft control bar.

    A small always-available window: click a craft glyph to select + equip that
    craft's gear, pick the goal (HQ / NQ / Skill-Up). This is the MANUAL model
    Henrik settled on -- you set your gear BEFORE synthing, when equipment
    changes are legal (auto-detection can't, since 0x096 is the first synth
    packet). The same controls live in the Automations panel; both drive the
    single craftwatch state, so they stay in sync.

    Toggle: /dl craft bar  (or the button in the Automations panel).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
if not _iok then return M; end
local cw = require('dlac\\craftwatch');

local ORDER = { 'Woodworking', 'Smithing', 'Goldsmithing', 'Clothcraft',
                'Leathercraft', 'Bonecraft', 'Alchemy', 'Cooking' };
local GOALS = { { 'hq', 'HQ' }, { 'nq', 'NQ' }, { 'skillup', 'Skill-Up' } };

-- Craft glyph textures (assets/craft/<Craft>.png), lazy-loaded via D3DX like
-- the Automations panel. false = load failed; nil not attempted yet.
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

-- One clickable craft glyph (bright when it's the selected craft, dim else).
-- Shared by the bar and the Automations panel (deps injected for the panel).
function M.craftButton(cr, selected, size)
    local drew = false;
    local tex = texture(cr);
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
        -- No glyph: a labelled button so the bar still works.
        if imgui.Button(cr:sub(1, 4) .. '##cb_' .. cr, { size, size }) then return true; end
        return false;
    end
    local clicked = imgui.IsItemClicked();
    if imgui.IsItemHovered() then imgui.SetTooltip(cr); end
    return clicked;
end
M.texture = texture;

-- The floating window.
local isOpen = { true };
function M.render()
    if not cw.barVisible then return; end
    pcall(function()
        imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always or 0);
        isOpen[1] = true;
        if imgui.Begin('dlac Craft##dlac_craftbar', isOpen, ImGuiWindowFlags_AlwaysAutoResize or 0) then
            local sel = cw.getCraft();
            for i, cr in ipairs(ORDER) do
                if M.craftButton(cr, sel == cr, 30) then cw.selectCraft(cr); end
                if i < #ORDER then imgui.SameLine(0, 6); end
            end
            imgui.Separator();
            local goal = cw.getGoal();
            imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Goal:'); imgui.SameLine(0, 6);
            for i, gd in ipairs(GOALS) do
                local on = (goal == gd[1]);
                if on then imgui.PushStyleColor(ImGuiCol_Button, { 0.16, 0.55, 0.24, 1 }); end
                if imgui.Button(gd[2] .. '##cbgoal' .. gd[1], { 62, 20 }) then cw.setGoal(gd[1]); end
                if on then imgui.PopStyleColor(1); end
                if i < #GOALS then imgui.SameLine(0, 4); end
            end
            if sel ~= nil then
                imgui.SameLine(0, 10);
                imgui.TextColored({ 0.55, 0.78, 0.55, 1 }, sel);
            else
                imgui.SameLine(0, 10);
                imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'click a craft to equip');
            end
        end
        imgui.End();
        if isOpen[1] == false then cw.barVisible = false; end   -- window's X closes the bar
    end);
end

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('d3d_present', 'dlac-craftbar-render', function()
        pcall(M.render);
    end);
end

return M;
