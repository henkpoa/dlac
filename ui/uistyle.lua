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

-- ---------------------------------------------------------------------------
-- The panel-text STANDARD (Henrik 2026-07-24): instead of an inline explanatory
-- paragraph, render the key label as an underlined "link" and move the
-- explanation into a hover tooltip -- keeps panels short and scannable. Apply it
-- to any label that had a paragraph hanging off it.
--
--   uistyle.helpLabel(imgui, 'Total riding time:', 'Every point adds 1 minute.')
--
-- `im` is the CALLER's imgui handle (so it renders under whatever binding/stub
-- the caller holds -- a shared module requiring its own imgui would get the
-- wrong instance in tests). `tip` may be multi-line ("\n"); pass nil for none.
-- `col` is the label colour ({r,g,b,a}). Renders exactly one item (SameLine
-- after it as usual). FULLY GUARDED: a binding missing the draw-list just shows
-- plain coloured text -- the underline is cosmetic, never load-bearing, and the
-- draw is wrapped so it can never take the frame down.
-- ---------------------------------------------------------------------------
function M.helpLabel(im, text, tip, col)
    if type(im) ~= 'table' or type(im.TextColored) ~= 'function' then return; end
    col = col or { 0.90, 0.90, 0.90, 1.00 };
    im.TextColored(col, text);
    -- underline: a line along the item's bottom edge (guarded draw-list).
    if type(im.GetItemRectMin) == 'function' and type(im.GetItemRectMax) == 'function'
       and type(im.GetWindowDrawList) == 'function' then
        pcall(function()
            local x1 = im.GetItemRectMin();
            local x2, y2 = im.GetItemRectMax();
            local dl = im.GetWindowDrawList();
            if dl ~= nil and type(dl.AddLine) == 'function' then
                local u = (type(im.GetColorU32) == 'function') and im.GetColorU32(col) or 0xFFFFFFFF;
                dl:AddLine({ x1, y2 }, { x2, y2 }, u, 1.0);
            end
        end);
    end
    -- the explanation, on hover.
    if tip ~= nil and type(im.IsItemHovered) == 'function' and im.IsItemHovered()
       and type(im.SetTooltip) == 'function' then
        im.SetTooltip(tip);
    end
end

return M;
