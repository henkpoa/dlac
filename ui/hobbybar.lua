--[[
    dlac/ui/hobbybar.lua

    The ONE shared "hobby bar" window (Henrik, ADR 0017). Craft, HELM, Fishing and
    Chocobo used to each have their own floating bar; now they share a single
    window with a selector across the top -- open any hobby's bar and it is this
    window, focused on that hobby, so switching between them is one click.

    LOCK-WHILE-ACTIVE: the four idle hobbies are mutually exclusive (idleexcl). The
    active hobby's tab is MARKED (green, trailing *), and while a hobby is active you
    can only stay on it -- the other tabs are locked until you turn the current one
    off. That mirrors the enable-layer rule: arming a second hobby while one runs is
    refused. So the flow is: turn the current hobby off (its pill, or the floating
    badge's Off), then switch tabs and arm the next.

    Each hobby's controls are the SAME code the standalone bars drew, now exposed as
    <bar>.renderContent(availW) (craftbar / helmbar / fishbar) plus a small inline
    Chocobo section here; this window supplies the chrome and the selector.

    Same "float" pattern as ui/idlefloat.lua: gearui's d3d_present calls M.render
    inside its own theme bracket, so the window stays up while you play. Visibility
    is ui._hobbyBar (session-only, like the old per-bar flags); the selected hobby is
    ui._hobbySel. Position is ImGui-internal (imgui.ini), as the old bars were.
]]--

local host = require('dlac\\ui\\uihost');

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');

local M = {};

-- Tab order = idleexcl.MEMBERS order.
local TABS = {
    { k = 'craft', n = 'Craft'   },
    { k = 'helm',  n = 'HELM'    },
    { k = 'fish',  n = 'Fishing' },
    { k = 'choco', n = 'Chocobo' },
};
local VALIDSEL = { craft = true, helm = true, fish = true, choco = true };

local COL_SELECTED = { 0.20, 0.35, 0.60, 1.0 };   -- viewing this tab
local COL_ACTIVE   = { 0.16, 0.55, 0.24, 1.0 };   -- this hobby is armed
local COL_LOCKED   = { 0.50, 0.50, 0.50, 1.0 };   -- can't switch here right now

local isOpen = { true };

-- ---- open / close API (called by the /dl commands, header button, panels) ----
local function uiTable() return host.services and host.services.ui or nil; end

-- The hobby the window is EFFECTIVELY showing: while one is active the selector is
-- locked to it (see M.render), so that wins over the stored selection.
local function effectiveSel(ui)
    local excl = try('dlac\\feature\\idleexcl');
    local a = excl ~= nil and excl.getActive() or nil;
    if a ~= nil and VALIDSEL[a.key] then return a.key; end
    if VALIDSEL[ui._hobbySel] then return ui._hobbySel; end
    return 'craft';
end

function M.open(key)
    local ui = uiTable(); if ui == nil then return; end
    ui._hobbyBar = true;
    if VALIDSEL[key] then ui._hobbySel = key; end
    if not VALIDSEL[ui._hobbySel] then ui._hobbySel = 'craft'; end
end

function M.close()
    local ui = uiTable(); if ui == nil then return; end
    ui._hobbyBar = false;
end

-- Pure visibility toggle (the header button): always closes when open, so it can
-- dismiss the bar even while a hobby is active (which locks the selection).
function M.toggleVisible()
    local ui = uiTable(); if ui == nil then return; end
    if ui._hobbyBar == true then ui._hobbyBar = false; else M.open(nil); end
end

-- Hobby-specific toggle (/dl <hobby> bar, a panel's Show/Hide bar): show the bar
-- on `key`, or hide it if it is already EFFECTIVELY showing `key`. (While a hobby
-- is active the bar is locked to it, so opening a peer's bar shows the active one.)
function M.toggle(key)
    local ui = uiTable(); if ui == nil then return; end
    if ui._hobbyBar == true and effectiveSel(ui) == key then
        ui._hobbyBar = false;
    else
        M.open(key);
    end
end

-- Is the window open AND effectively showing `key`? (For "Show bar"/"Hide bar".)
function M.isShown(key)
    local ui = uiTable(); if ui == nil then return false; end
    return ui._hobbyBar == true and effectiveSel(ui) == key;
end

-- ------------------------------- the Chocobo section -------------------------
-- Chocobo never had a standalone bar; a minimal section here (on/off + a nudge to
-- the full panel) so it is genuinely one of the shared tabs.
local function renderChocoContent()
    local cw = try('dlac\\feature\\chocowatch');
    local cb = try('dlac\\ui\\craftbar');   -- the shared on/off pill lives here
    if cw == nil then imgui.TextColored(COL_LOCKED, 'Chocobo unavailable.'); return; end
    local on = cw.isEnabled();
    local toggled;
    if cb ~= nil and type(cb.onOffSwitch) == 'function' then
        toggled = cb.onOffSwitch(on, 'chocobar',
            'Chocobo riding gear is ON (idle only). Click to turn off.',
            'Set Chocobo Idle: wears your best riding-time gear whenever idle, until turned off.');
    else
        toggled = imgui.Button((on and 'ON' or 'OFF') .. '##chocobarbtn', { 46, 22 });
    end
    if toggled then cw.setEnabled(not on); end
    imgui.SameLine(0, 10);
    imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Chocobo riding gear (idle only)');
    imgui.TextColored(COL_LOCKED, 'Dig rank, guide and by-item search: Automations > Chocobo.');
    imgui.Dummy({ 300, 1 });
end

-- --------------------------------- the window --------------------------------
function M.render()
    if imgui == nil then return; end
    local ui = uiTable();
    if ui == nil or ui._hobbyBar ~= true then return; end
    if not VALIDSEL[ui._hobbySel] then ui._hobbySel = 'craft'; end

    -- LOCK: while a hobby is active the selector is pinned to it.
    local excl = try('dlac\\feature\\idleexcl');
    local active = excl ~= nil and excl.getActive() or nil;
    local activeKey = active and active.key or nil;
    if activeKey ~= nil then ui._hobbySel = activeKey; end

    imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always or 0);
    isOpen[1] = true;
    if imgui.Begin('dlac Hobbies##dlac_hobbybar', isOpen, ImGuiWindowFlags_AlwaysAutoResize or 0) then
        -- Selector row: mark the active hobby (green + *), lock the rest while active.
        for i, t in ipairs(TABS) do
            local isSel    = (ui._hobbySel == t.k);
            local isActive = (activeKey == t.k);
            local locked   = (activeKey ~= nil and activeKey ~= t.k);
            local pushed = 0;
            if isActive then
                imgui.PushStyleColor(ImGuiCol_Button, COL_ACTIVE); pushed = pushed + 1;
            elseif isSel then
                imgui.PushStyleColor(ImGuiCol_Button, COL_SELECTED); pushed = pushed + 1;
            end
            if locked then imgui.PushStyleColor(ImGuiCol_Text, COL_LOCKED); pushed = pushed + 1; end
            local label = t.n .. (isActive and ' *' or '') .. '##hbtab' .. t.k;
            if imgui.Button(label, { 0, 0 }) then
                if not locked then M.open(t.k); end
            end
            if pushed > 0 then imgui.PopStyleColor(pushed); end
            if imgui.IsItemHovered() then
                if locked then
                    imgui.SetTooltip(string.format('%s is active -- turn it off to switch to %s.',
                        tostring(active.name), t.n));
                elseif isActive then
                    imgui.SetTooltip(t.n .. ' is active now.');
                else
                    imgui.SetTooltip('Show ' .. t.n .. '.');
                end
            end
            if i < #TABS then imgui.SameLine(0, 4); end
        end
        imgui.Separator();

        -- The selected hobby's controls (the old bar bodies, now shared).
        local availW = imgui.GetContentRegionAvail();
        if type(availW) ~= 'number' then availW = nil; end
        local sel = ui._hobbySel;
        if sel == 'craft' then
            local cb = try('dlac\\ui\\craftbar');
            if cb and cb.renderContent then cb.renderContent(availW); end
        elseif sel == 'helm' then
            local hb = try('dlac\\ui\\helmbar');
            if hb and hb.renderContent then hb.renderContent(availW); end
        elseif sel == 'fish' then
            local fb = try('dlac\\ui\\fishbar');
            if fb and fb.renderContent then fb.renderContent(availW); end
        elseif sel == 'choco' then
            renderChocoContent();
        end
    end
    imgui.End();
    if isOpen[1] == false then M.close(); end
end

host.provide({ hobbybar = M });
return M;
