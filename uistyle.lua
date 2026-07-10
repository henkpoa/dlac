--[[
    dlac/uistyle.lua

    The shared window theme -- matched to CatsEyeXI's partyfinder addon
    (partyfinder.lua "themeStyles") so dlac looks native beside it: near-black
    blue-tinted translucent window background, soft gray text, muted gray-blue
    frames/buttons/headers, subtle borders. The entries below partyfinder's set
    (tabs, check marks, sliders, separators, grips) extend the same family for
    widgets dlac uses that partyfinder doesn't.

    Pushed once per frame around the whole draw (gearui's render hook), so every
    dlac window, popup and tooltip inherits it. The hook pushes BEFORE
    pcall(drawWindow) and pops after, so an imgui error mid-frame can never
    leak the style stack.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local hasImgui = _iok and imgui ~= nil;

-- {ImGuiCol_*, {r,g,b,a}} pairs. Built through add() so a color id this
-- binding doesn't define is skipped instead of pushing to a nil slot.
local STYLES = {};
local function add(id, col) if id ~= nil then STYLES[#STYLES + 1] = { id, col }; end end

-- partyfinder parity ---------------------------------------------------------
add(ImGuiCol_Text,                 { 0.90, 0.90, 0.90, 1.00 });
add(ImGuiCol_TextDisabled,         { 0.50, 0.50, 0.50, 1.00 });
add(ImGuiCol_WindowBg,             { 0.06, 0.06, 0.08, 0.96 });
add(ImGuiCol_ChildBg,              { 0.08, 0.08, 0.10, 1.00 });
add(ImGuiCol_PopupBg,              { 0.08, 0.08, 0.10, 0.96 });
add(ImGuiCol_Border,               { 0.30, 0.30, 0.35, 0.50 });
add(ImGuiCol_FrameBg,              { 0.12, 0.12, 0.15, 1.00 });
add(ImGuiCol_FrameBgHovered,       { 0.18, 0.18, 0.22, 1.00 });
add(ImGuiCol_FrameBgActive,        { 0.22, 0.22, 0.28, 1.00 });
add(ImGuiCol_TitleBg,              { 0.05, 0.05, 0.07, 1.00 });
add(ImGuiCol_TitleBgActive,        { 0.10, 0.10, 0.14, 1.00 });
add(ImGuiCol_ScrollbarBg,          { 0.05, 0.05, 0.07, 0.80 });
add(ImGuiCol_ScrollbarGrab,        { 0.30, 0.30, 0.35, 1.00 });
add(ImGuiCol_ScrollbarGrabHovered, { 0.40, 0.40, 0.45, 1.00 });
add(ImGuiCol_ScrollbarGrabActive,  { 0.50, 0.50, 0.55, 1.00 });
add(ImGuiCol_Button,               { 0.18, 0.18, 0.22, 1.00 });
add(ImGuiCol_ButtonHovered,        { 0.28, 0.28, 0.35, 1.00 });
add(ImGuiCol_ButtonActive,         { 0.35, 0.35, 0.42, 1.00 });
add(ImGuiCol_Header,               { 0.18, 0.18, 0.24, 1.00 });
add(ImGuiCol_HeaderHovered,        { 0.26, 0.26, 0.34, 1.00 });
add(ImGuiCol_HeaderActive,         { 0.32, 0.32, 0.40, 1.00 });

-- dlac extensions, same family ------------------------------------------------
add(ImGuiCol_TitleBgCollapsed,     { 0.05, 0.05, 0.07, 0.80 });
add(ImGuiCol_Tab,                  { 0.12, 0.12, 0.16, 1.00 });
add(ImGuiCol_TabHovered,           { 0.28, 0.28, 0.36, 1.00 });
add(ImGuiCol_TabActive,            { 0.22, 0.22, 0.30, 1.00 });
add(ImGuiCol_TabUnfocused,         { 0.08, 0.08, 0.11, 1.00 });
add(ImGuiCol_TabUnfocusedActive,   { 0.16, 0.16, 0.22, 1.00 });
add(ImGuiCol_CheckMark,            { 0.65, 0.75, 0.90, 1.00 });
add(ImGuiCol_SliderGrab,           { 0.40, 0.45, 0.55, 1.00 });
add(ImGuiCol_SliderGrabActive,     { 0.55, 0.60, 0.72, 1.00 });
add(ImGuiCol_Separator,            { 0.30, 0.30, 0.35, 0.50 });
add(ImGuiCol_SeparatorHovered,     { 0.40, 0.40, 0.48, 0.78 });
add(ImGuiCol_SeparatorActive,      { 0.50, 0.50, 0.58, 1.00 });
add(ImGuiCol_ResizeGrip,           { 0.30, 0.30, 0.35, 0.40 });
add(ImGuiCol_ResizeGripHovered,    { 0.40, 0.40, 0.48, 0.66 });
add(ImGuiCol_ResizeGripActive,     { 0.50, 0.50, 0.58, 0.90 });
add(ImGuiCol_TextSelectedBg,       { 0.30, 0.40, 0.60, 0.55 });

-- Push the theme; returns true when pushed (pass that to pop). A false return
-- means imgui is unavailable and nothing was pushed.
function M.push()
    if not hasImgui then return false; end
    for _, s in ipairs(STYLES) do
        imgui.PushStyleColor(s[1], s[2]);
    end
    return true;
end

function M.pop()
    if not hasImgui then return; end
    imgui.PopStyleColor(#STYLES);
end

return M;
