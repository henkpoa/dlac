--[[
    dlac/ui/idlefloat.lua

    The floating "active idle hobby" badge. When exactly one of Craft / HELM /
    Fishing / Chocobo is armed (idleexcl guarantees at most one), a small draggable
    chip appears naming it, with an Off button to stand it down. When none is
    armed, render() draws nothing -- so the badge appears the moment a hobby is
    activated and vanishes the moment it is turned off, with no user flag to
    manage.

    Same "float" pattern as ui/floatgear.lua and the TP button: this is NOT a
    uihost `window` (those render inside gearui's drawWindow, which returns early
    when the main box is shut). gearui's d3d_present handler calls M.render
    directly, inside its own theme bracket, so the badge stays up while you play.
    It SELF-GATES on idleexcl.getActive(), like the restock nudge / choco search --
    gearui calls it unconditionally and it decides whether to draw.

    Position persists across sessions via ui._idlePos (syncflags writes ifx/ify to
    uiflags.lua on settle, exactly like the TP float's tpx/tpy).
]]--

local host = require('dlac\\ui\\uihost');

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');

local M = {};

-- Colours are literal (not from the theme) so the badge reads the same under any
-- theme; the caller's theme bracket still styles the window frame + button.
local ACCENT = { 0.55, 0.85, 1.00, 1.00 };   -- the hobby name
local DIM    = { 0.62, 0.66, 0.72, 1.00 };    -- the "· detail" sub-label

function M.render()
    if imgui == nil then return; end
    local ui = host.services and host.services.ui;
    if ui == nil then return; end

    local excl = try('dlac\\feature\\idleexcl');
    if excl == nil then return; end
    local active = excl.getActive();
    if active == nil then return; end        -- nothing armed -> no badge

    if type(ui._idlePos) == 'table' then
        imgui.SetNextWindowPos({ ui._idlePos[1], ui._idlePos[2] }, ImGuiCond_Once or 0);
    end

    local FL = (ImGuiWindowFlags_NoTitleBar or 0) + (ImGuiWindowFlags_AlwaysAutoResize or 0)
             + (ImGuiWindowFlags_NoScrollbar or 0) + (ImGuiWindowFlags_NoCollapse or 0)
             + (ImGuiWindowFlags_NoFocusOnAppearing or 0);

    ui._idleOpenT = ui._idleOpenT or { true };
    ui._idleOpenT[1] = true;                 -- no title bar/close button: the Off button is the closer
    if imgui.Begin('##dlac_idlefloat', ui._idleOpenT, FL) then
        -- ● Craft: Woodworking      [Off]
        imgui.TextColored(ACCENT, tostring(active.name));
        if imgui.IsItemHovered() then
            imgui.SetTooltip('The one active idle hobby.\nOnly one of Craft / HELM / Fishing / Chocobo runs at a time.');
        end
        if active.detail ~= nil then
            imgui.SameLine();
            imgui.TextColored(DIM, '· ' .. tostring(active.detail));
        end
        imgui.SameLine();
        if imgui.SmallButton('Off##idlefloatoff') then
            pcall(excl.deactivate);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Turn ' .. tostring(active.name) .. ' idle off.');
        end

        -- Remember where it was dragged; save once the drag settles (marking the
        -- flags dirty every frame would rewrite uiflags.lua ~60x/sec -- the TP
        -- float's _tpMovedAt trick).
        local px, py = imgui.GetWindowPos();
        if type(px) == 'table' then py = (px[2] or px.y); px = (px[1] or px.x); end
        if type(px) == 'number' and type(py) == 'number' then
            px, py = math.floor(px), math.floor(py);
            if type(ui._idlePos) ~= 'table' or ui._idlePos[1] ~= px or ui._idlePos[2] ~= py then
                ui._idlePos = { px, py };
                ui._idleMovedAt = os.clock() + 1;
            end
        end
    end
    imgui.End();
    if ui._idleMovedAt ~= nil and os.clock() >= ui._idleMovedAt then
        ui._idleMovedAt = nil;
        ui._flagsDirty = true;
    end
end

host.provide({ idlefloat = M });
return M;
