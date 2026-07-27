--[[
    dlac/ui/hobbybar.lua

    The ONE shared "hobby bar" window (Henrik, ADR 0017). Craft, HELM, Fishing and
    Chocobo used to each have their own floating bar; now they share a single
    window with a selector across the top -- open any hobby's bar and it is this
    window, focused on that hobby, so switching between them is one click.

    LOCK-WHILE-ACTIVE, AND WHAT IT IS NOT (fixed 2026-07-25). The four idle hobbies
    are mutually exclusive (idleexcl): arming a second while one runs is REFUSED by
    idleexcl.guardActivate, at the enable layer. That rule is about ARMING. This
    window used to enforce it as a rule about LOOKING -- it pinned ui._hobbySel to
    the armed hobby every frame and greyed out the other tabs -- which meant that
    with Auto HELM or Chocobo on (both of which persist across relogs), the Craft
    tab was never drawn and the Last Synth button did not exist on screen. That is
    the "after the hobby menu was changed, Last Synth doesn't work" report.

    So: every tab is always reachable, and switching tabs arms nothing. The armed
    hobby is MARKED (green) and its on/off pill is the thing that refuses --
    exactly where the real guard lives.

    TAB ART (2026-07-27). A tab with `assets\hobby\<Name>.png` draws as a 64px
    icon; one without keeps its text button, so the four convert one at a time as
    art arrives. See the iconTab block below for why selection rides brightness
    and armed rides a frame, rather than both riding colour.

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
--
-- `n` is what the PLAYER is told this tab is -- the hover word, and the label if
-- the tab has no art (Henrik 2026-07-27: "just show simple terms"). `img` is the
-- asset basename, kept separate because it names a FILE: the art is a digging
-- chocobo, so `Chocobo.png` is the right file name while "Digging" is the right
-- word. Renaming one must never silently rename the other.
local TABS = {
    { k = 'craft', n = 'Crafting', img = 'Craft'   },
    { k = 'helm',  n = 'HELM',     img = 'HELM'    },
    { k = 'fish',  n = 'Fishing',  img = 'Fishing' },
    { k = 'choco', n = 'Digging',  img = 'Chocobo' },
};
local VALIDSEL = { craft = true, helm = true, fish = true, choco = true };

local COL_SELECTED = { 0.20, 0.35, 0.60, 1.0 };   -- viewing this tab
local COL_ACTIVE   = { 0.16, 0.55, 0.24, 1.0 };   -- this hobby is armed
local COL_LOCKED   = { 0.50, 0.50, 0.50, 1.0 };   -- can't switch here right now

local isOpen = { true };

-- ---------------------------------------------------------------------------
-- Tab ART (2026-07-27). `assets\hobby\<Name>.png` drawn at ICON_W; a tab with no
-- PNG keeps its TEXT button. That fallback is the feature, not a safety net: the
-- four tabs can gain art ONE AT A TIME (drop Craft.png / HELM.png / Fishing.png
-- in beside Chocobo.png and they convert themselves, no code change), and a
-- texture that fails to load leaves a labelled button rather than a mystery
-- hole -- menuui.headerButton's rule, for the same reason.
--
-- SIZE: 64, up from the first cut's 30 (Henrik: "I want the icons bigger, at
-- least twice as big"). The art ships at 128 so that drawing it here lands on
-- mip level 1 -- a clean 2:1 box filter, i.e. as sharp as shipping 64 -- and so
-- the tabs can grow again without regenerating every file.
--
-- Loading goes through filetex, which RETAINS the texture object; caching only
-- the numeric handle lets Lua GC it, D3D free it, and imgui draw a dangling
-- pointer -- that was the header-icon crash.
-- ---------------------------------------------------------------------------
local ICON_W = 64;

local function iconHandle(name)
    local h = nil;
    pcall(function() h = require('dlac\\ui\\filetex').handle('hobby\\' .. name); end);
    return h;
end

-- Draws one tab as art. Returns (drew, clicked) -- `drew == false` means the
-- caller should fall back to the text button.
--
-- Colour is deliberately NOT the state channel here. The text tabs carry
-- selection and armed-ness in the BUTTON colour, but tinting art recolours the
-- art itself (a green wash turns a yellow chocobo olive), and the whole point of
-- the icon is that you recognise it. So: brightness carries selection -- the
-- craft-glyph idiom -- and ARMED gets a literal green frame around the icon.
local function iconTab(t, isSel, isActive)
    local h = iconHandle(t.img or t.n);
    if h == nil then return false, false; end
    local x, y = imgui.GetCursorScreenPos();
    local tint = isSel and { 1, 1, 1, 1 } or { 1, 1, 1, 0.45 };
    local drew = pcall(function()
        imgui.Image(h, { ICON_W, ICON_W }, { 0, 0 }, { 1, 1 }, tint);
    end);
    if not drew then                      -- binding without the tint overload
        drew = pcall(function() imgui.Image(h, { ICON_W, ICON_W }); end);
    end
    if not drew then return false, false; end
    local clicked = imgui.IsItemClicked();
    if isActive and type(x) == 'number' and type(y) == 'number' then
        -- 0x00CC00 reads green whichever byte order the binding packs, so the
        -- armed marker cannot come out red on a different imgui build.
        pcall(function()
            local dl = imgui.GetWindowDrawList();
            dl:AddRect({ x - 2, y - 2 }, { x + ICON_W + 2, y + ICON_W + 2 },
                       0xFF00CC00, 4, ImDrawCornerFlags_All or 0, 2);
        end);
    end
    return true, clicked;
end

-- ---- open / close API (called by the /dl commands, header button, panels) ----
local function uiTable() return host.services and host.services.ui or nil; end

-- The hobby the window is showing. Just the stored selection: the armed hobby
-- used to override it, which made this function unable to return 'craft' while
-- anything else was on -- so M.toggle('craft') never matched, M.isShown('craft')
-- was permanently false, and both /dl craft bar and the Automations "Show bar"
-- button read the wrong state (they reported "hidden" while opening it).
local function effectiveSel(ui)
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
-- on `key`, or hide it if it is already showing `key`.
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
    -- Dig search, straight from the bar (2026-07-27). Was a grey sentence telling
    -- you to go to Automations > Chocobo; these are the panel's OWN two buttons,
    -- routed through chocoui's openers so the two surfaces cannot drift (Area
    -- still lands on the zone you are standing in, and each closes the other).
    -- The windows themselves are drawn from ONE place, gearui's d3d_present.
    imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Dig:');
    imgui.SameLine(0, 8);
    if imgui.SmallButton('Area##hbchocoarea') then
        pcall(function() require('dlac\\ui\\chocoui').openAreaSearch(); end);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Everything diggable in a zone, priced for your rank + moon.\nOpens on your current zone if you are standing in a digging area.');
    end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('Item##hbchocoitem') then
        pcall(function() require('dlac\\ui\\chocoui').openItemSearch(); end);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Search an item -> every zone + pool it drops from.\nClick a zone there to jump to its Area window.');
    end
    imgui.SameLine(0, 12);
    -- The panel owns the DIG RANK picker, and every odds figure in both search
    -- windows is computed from that rank -- so the moment a search looks wrong,
    -- this is where you go.
    if imgui.SmallButton('Panel##hbchocopanel') then
        pcall(function()
            local g = require('dlac\\ui\\gearui');
            if type(g.openAutomation) == 'function' then g.openAutomation('choco'); end
        end);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Open Automations > Chocobo: the dig rank picker, riding-time\ngear and the live moon/day/weather odds.');
    end
    imgui.Dummy({ 300, 1 });
end

-- --------------------------------- the window --------------------------------
function M.render()
    if imgui == nil then return; end
    local ui = uiTable();
    if ui == nil or ui._hobbyBar ~= true then return; end
    if not VALIDSEL[ui._hobbySel] then ui._hobbySel = 'craft'; end

    -- Which hobby is armed -- for the ARMED MARK only (a green button + trailing
    -- * on a text tab, a green frame on an icon one). It does NOT move the
    -- selector: see the LOCK note in the header. (Was: the selector was pinned
    -- to the armed hobby every frame, which hid every other tab's controls.)
    local excl = try('dlac\\feature\\idleexcl');
    local active = excl ~= nil and excl.getActive() or nil;
    local activeKey = active and active.key or nil;

    imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always or 0);
    isOpen[1] = true;
    if imgui.Begin('dlac Hobbies##dlac_hobbybar', isOpen, ImGuiWindowFlags_AlwaysAutoResize or 0) then
        -- Selector row: every tab is always reachable; the armed one is marked
        -- green (a trailing * on text, a frame on art).
        for i, t in ipairs(TABS) do
            local isSel    = (ui._hobbySel == t.k);
            local isActive = (activeKey == t.k);
            -- Art if this tab has any, else the text button unchanged. Both end
            -- with the SAME hover contract below -- with the label gone, the
            -- tooltip is the only thing naming an icon tab, so it must not be
            -- inside either branch.
            local drewIcon, iconClicked = iconTab(t, isSel, isActive);
            if drewIcon then
                if iconClicked then M.open(t.k); end
            else
                local pushed = 0;
                if isActive then
                    imgui.PushStyleColor(ImGuiCol_Button, COL_ACTIVE); pushed = pushed + 1;
                elseif isSel then
                    imgui.PushStyleColor(ImGuiCol_Button, COL_SELECTED); pushed = pushed + 1;
                end
                local label = t.n .. (isActive and ' *' or '') .. '##hbtab' .. t.k;
                if imgui.Button(label, { 0, 0 }) then M.open(t.k); end
                if pushed > 0 then imgui.PopStyleColor(pushed); end
            end
            -- ONE WORD (Henrik 2026-07-27: "just show simple terms"). The three
            -- branches this replaced said which hobby was armed and which one to
            -- turn off first -- but the green frame already says the former, and
            -- the latter is spoken by the pill that actually refuses
            -- (idleexcl.guardActivate), in chat, at the moment you try it. A
            -- hover on a picture only has to answer "what is this?".
            if imgui.IsItemHovered() then imgui.SetTooltip(t.n); end
            -- 6px, not the old 4: at 64px the icons crowd each other, and the
            -- armed frame is drawn 2px OUTSIDE the icon, so a 4px gap would put
            -- a frame edge almost touching its neighbour's art.
            if i < #TABS then imgui.SameLine(0, 6); end
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
