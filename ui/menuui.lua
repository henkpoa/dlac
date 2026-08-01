--[[
    dlac/menuui.lua -- the header MENU + the SETTINGS panel (Henrik 2026-07-24).

    The header used to be a row of eight right-aligned buttons. It is now ONE "Menu"
    button (standing exactly where "Reload LAC" stood) opening a popup that holds the
    features that used to sit left of it -- Lockstyle, Macro book, Hobby bar,
    Teleports, Level override -- plus SETTINGS, plus a Debug section that only exists
    under /dl debug on. Profiles and Migrate deliberately stay OUT in the header:
    Profiles is top-level navigation, Migrate is the red onboarding call-to-action and
    burying it would defeat it.

    "Reload LAC" is GONE, not relocated. Legacy LuaAshitacast is no longer a design
    consideration (ADR 0015 + Henrik's ruling: "everything LAC Legacy does not need to
    take account for"), and its red state could only ever be armed from two legacy-only
    setupui paths -- under the native engine it was dead weight.

    WHY A MODULE AND NOT MORE gearui: hard rule 1, the LuaJIT 200-local chunk cap.
    gearui sat at exactly 200/200 before the uihost split; new UI is born as a module.
    This one takes ALL its collaborators by injection (M.configure -- the
    sf.configure / setup.configure / pmenu.configure precedent) so gearui gains ZERO
    chunk locals, and so the whole thing is drivable headlessly.

    POPUP SCOPE, the law that shapes the code: OpenPopup and BeginPopup resolve ids
    against the CURRENT window, so a click only ever sets a flag and the actual
    OpenPopup happens back at window scope (gearui.lua's ui._tpOpen / ui._lvlOpen
    idiom). That is also why picking a row CLOSES this menu instead of nesting the
    target popup inside it: '##dlac_teleports' carries its own BeginMenu cascades, and
    a CloseCurrentPopup fired from inside a nested chain walks the whole chain.

    Pure seams for the headless suite (tests SET*/MN*): _normalizeOpenMode,
    _shouldAutoOpen, _parseLevel, _menuRows. They take plain values and return plain
    values -- no imgui, no Ashita, no disk.
]]--

local M = {};

M.VERSION = 1;

-- ONE local per module, no pcall-ok temps (the 200-local cap habit).
local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local imgui  = try('imgui');
local uistyl = try('dlac\\ui\\uistyle');
local hasImgui = (imgui ~= nil);

-- Deps from gearui (M.configure). Everything the rows act on arrives here, so this
-- module never reaches into gearui's chunk and never requires anything GRD5 bans.
--   ui, COL            -- the shared UI state table + the palette
--   sf                 -- gear\syncflags (flags.debug / .autosync / .viewids / .gearwarn)
--   optim              -- gear\gearoptim (buildAtMaxLevel), optional
--   callImport(kind)   -- the debug Scan/Stage/Commit path
--   dumpAugs()         -- the debug Augs dump (NEVER require feature\augments: GRD5)
--   refreshOwnedCounts()
--   setVisible(bool)   -- flips gearui's own M.visible
--   mainJob()          -- current main job id (nil/0 = not ready)
local D = nil;
function M.configure(deps)
    if type(deps) == 'table' then D = deps; end
end

-- ---------------------------------------------------------------------------
-- Layout constants -- exported so a headless test can assert the icon column is
-- reserved even when no PNG exists (the floatgear._HOVER_FLAGS precedent).
-- ---------------------------------------------------------------------------
-- Sizes (Henrik 2026-07-24, after the first visual pass: "make the menu item just
-- slightly bigger for visibility" + "wouldn't mind making the whole menu a bit bigger
-- overall as well, to show off the icons").
--
-- The INVARIANT that binds these three, pinned by SET39/SET51: the label column must
-- clear the icon gutter, i.e. _LABEL_X >= _ICON_GAP + _ICON_W + a gap. Bump _ICON_W
-- alone and labels start printing over the art.
M._ICON_W  = 24;    -- icon box, drawn or Dummy'd -- the column is ALWAYS this wide
M._ICON_GAP = 6;    -- left inset before the icon
M._ROW_H   = 26;    -- explicit Selectable height, so the HIT AREA matches the taller
                    -- row. Without it the click target stays text-height and the
                    -- bottom of every row goes dead.
M._LABEL_X = 38;    -- absolute x for the row label, so labels line up regardless
M._MENU_W  = 104;   -- header button width when there is no art (themed font law:
                    -- ~9.5px/char + 16 padding, or the label clips)
M._MENU_ICON_W = 24;-- header button icon (16 -> 20 -> 24). Deliberately the SAME size
                    -- as a row icon (_ICON_W): the button is the entry point to the
                    -- menu, so the art reads identically in both places.
M._MENU_BTN_W  = 34;-- ...and the declared width must grow with it: gearui right-aligns
                    -- the header row by summing b.w. Keeps the original +10 slack over
                    -- the icon (16px icon declared 26), so the label can never clip.

-- The menu roster. `icon` names an assets\<name>.png. All six shipped 2026-07-24
-- (Henrik's art, 64x64 transparent, drawn at 16x16); any that is missing or fails to
-- load falls through to the Dummy path, so the column stays the same width either way.
local ROWS = {
    { key = 'lockstyle', icon = 'lockstyle', label = 'Lockstyle',
      tip = 'Lockstyle boxes -- 30 saved looks PER JOB.\nSave the marked box, import old static lockstyle sets, and\n"OnLoad Lockstyle" re-applies it on every login / job change.' },
    { key = 'macrobook', icon = 'macrobook', label = 'Macro book',
      tip = 'Macro book & set for the CURRENT job -- saved per job and applied\nautomatically on login and every job change. Jobs you don\'t manage\nare never touched.' },
    { key = 'hobbybar',  icon = 'hobbybar',  label = 'Hobby bar',
      tip = 'One shared window for Craft / HELM / Fishing / Chocobo:\npick controls and switch a hobby on (idle only).' },
    { key = 'teleports', icon = 'teleports', label = 'Teleports',
      tip = 'Warp / Retrace scrolls, teleport earrings and rings, the Chocobo Whistle,\nevery other travel enchant you own and your exp rings -- plus quick rows\nfor the Hobby bar and Lockstyle.' },
    { key = 'wishlist',  icon = 'wishlist',  label = 'Wishlist',
      tip = 'Gear you are hunting -- what it is for, and what you wanted it for.\nRight-click anything in All Equipment to add it; a piece you don\'t own\nadded to a set lands here too. Turns green when it reaches your bags.' },
    { key = 'level',     icon = 'level',     label = 'Level override',
      tip = 'Preview / test at another MAIN level: the pickers, set previews and\nthe live set flattening all follow it.' },
    { key = 'settings',  icon = 'settings',  label = 'Settings',
      tip = 'Everything dlac remembers for this character.' },
};

-- Debug-only rows (/dl debug on). Kept OUT of the header entirely -- they were pure
-- clutter there, and decluttering is what this menu is for.
local DEBUG_ROWS = {
    { key = 'scan',   label = 'Scan',
      tip = 'Scan your equipment + bags and print what you own, flagging anything not\nyet in gear.lua. Read-only -- writes nothing.' },
    { key = 'stage',  label = 'Stage',
      tip = 'Scan, then write the items you own that AREN\'T in gear.lua yet to\ngear_staging.lua for review. Your gear.lua is left untouched.' },
    { key = 'commit', label = 'Commit',
      tip = 'Merge the staged new items into your gear.lua. Aborts if the staging file\nor the merged result would not parse.' },
    { key = 'augs',   label = 'Augs',
      tip = 'Dump every augmented item you own to augdump.txt in your dlac folder.' },
};

-- ---------------------------------------------------------------------------
-- PURE SEAM: which rows exist. Tests pin that the debug quartet appears ONLY under
-- debug, and that the visible roster never silently reorders.
-- ---------------------------------------------------------------------------
function M._menuRows(debugOn)
    local out = {};
    for _, r in ipairs(ROWS) do out[#out + 1] = r.key; end
    if debugOn == true then
        for _, r in ipairs(DEBUG_ROWS) do out[#out + 1] = r.key; end
    end
    return out;
end

-- The two icons that are not row icons: the header button itself, and the Developer
-- section header. (The four debug rows share ONE question mark on their section
-- heading rather than repeating it four times down the column.)
M._MENU_ICON  = 'menu';
M._DEBUG_ICON = 'debug';

-- PURE SEAM: EVERY asset basename this module can ask filetex for. A missing or
-- misspelled name fails SILENTLY at runtime (blank cell, correct width), so the
-- headless suite asserts each one exists on disk instead -- the only way a rename
-- gets caught.
function M._menuIcons()
    local out = {};
    for _, r in ipairs(ROWS) do
        if r.icon ~= nil then out[#out + 1] = r.icon; end
    end
    out[#out + 1] = M._MENU_ICON;
    out[#out + 1] = M._DEBUG_ICON;
    return out;
end

-- ---------------------------------------------------------------------------
-- PURE SEAM: the open-on-login Setting.
--
-- ONE setting with THREE values rather than two booleans -- "off but also on job
-- change" is a meaningless combination and someone would tick it.
-- ---------------------------------------------------------------------------
M.OPEN_MODES  = { 'never', 'login', 'job' };
M.OPEN_LABELS = { never = 'Never', login = 'On login', job = 'On login + job change' };

-- Anything unrecognised (including a hand-edited uiflags.lua, which is a plain Lua
-- file a player may edit) reads as 'never': the conservative end, since the surprising
-- failure is a window that pops up uninvited.
function M._normalizeOpenMode(v)
    v = string.lower(tostring(v or ''));
    for _, m in ipairs(M.OPEN_MODES) do
        if v == m then return m; end
    end
    return 'never';
end

-- Should the main window be opened on THIS tick?
--   mode    -- the normalized setting
--   job     -- current main job id (nil or 0 = not logged in / not ready yet)
--   lastJob -- the job we last saw (caller-tracked)
--   opened  -- has the auto-open already fired once this session?
-- 'login' fires exactly once, the first tick a real job exists. 'job' fires then and
-- again on every change. A manual close is never fought: nothing re-fires until the
-- job actually changes.
function M._shouldAutoOpen(mode, job, lastJob, opened)
    mode = M._normalizeOpenMode(mode);
    if mode == 'never' then return false; end
    if job == nil or job == 0 then return false; end
    if opened ~= true then return true; end
    if mode == 'job' and job ~= lastJob then return true; end
    return false;
end

-- ---------------------------------------------------------------------------
-- PURE SEAM: the typed level override.
--
-- Returns nil for "not a number, do nothing" (so a half-typed box never commits),
-- 0 for "back to live", else the level clamped to 1..75. The point of typing it is
-- that ONE command is queued on commit instead of one per +/- click.
-- ---------------------------------------------------------------------------
function M._parseLevel(text)
    local s = tostring(text or '');
    local digits = s:match('^%s*(%-?%d+)%s*$');
    if digits == nil then return nil; end
    local n = tonumber(digits);
    if n == nil then return nil; end
    if n <= 0 then return 0; end
    if n > 75 then return 75; end
    return n;
end

-- ---------------------------------------------------------------------------
-- Small render helpers.
-- ---------------------------------------------------------------------------

-- The icon cell. ALWAYS occupies M._ICON_W x M._ICON_W: a real texture when the PNG
-- exists, an imgui.Dummy of the same size when it does not. Textures come through
-- filetex.handle and nowhere else -- it retains the texture OBJECT, and storing only
-- the numeric handle lets Lua GC it, D3D free it, and imgui draw a dangling pointer
-- (that was the original header-icon crash).
local function iconHandle(name)
    local h = nil;
    if name ~= nil then
        pcall(function() h = require('dlac\\ui\\filetex').handle(name); end);
    end
    return h;
end

local function iconCell(name)
    local drew = false;
    local h = iconHandle(name);
    if h ~= nil then
        pcall(function() imgui.Image(h, { M._ICON_W, M._ICON_W }); drew = true; end);
    end
    if not drew then imgui.Dummy({ M._ICON_W, M._ICON_W }); end
end

-- One menu row: a full-width Selectable for the hit area, then the reserved icon
-- column, then the label at a fixed x so every label lines up. Returns true on click.
local function menuRow(r, col)
    -- Explicit row height so the hit area covers the whole taller row. The 4-arg
    -- Selectable is the proven overload in this repo (automationsui), but per hard
    -- rule 2 a binding that lacks it must degrade rather than crash: fall back to the
    -- auto-sized 1-arg form, which is just the old, shorter click target.
    local hit, sized = false, false;
    pcall(function()
        hit = imgui.Selectable('##dlacmn_' .. r.key, false,
                               (ImGuiSelectableFlags_None or 0), { 0, M._ROW_H });
        sized = true;
    end);
    if not sized then hit = imgui.Selectable('##dlacmn_' .. r.key); end
    if r.tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(r.tip); end
    imgui.SameLine(M._ICON_GAP);
    iconCell(r.icon);
    imgui.SameLine(M._LABEL_X);
    imgui.TextColored(col, r.label);
    return hit == true;
end

-- imgui text is printf: an unescaped '%' in a name prints a heap address (the
-- panelkit law, 2026-07-30). Item names carry none today, but they come from the
-- game rather than from this file, so nothing reaches imgui unescaped.
local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

local function queue(cmd)
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
end

-- ---------------------------------------------------------------------------
-- THE FOOD SECTION -- the two most recently eaten foods you are actually
-- CARRYING, one click each (feature\foodwatch owns which two and why).
--
-- ONE definition, two call sites: this menu and the Teleports popup, which is
-- also the floating quick menu -- the surface you can reach mid-fight without
-- opening the main window, which is exactly when a food wears off. Same reason
-- the Hobby bar and Lockstyle rows appear in both (gearui.renderQuickWindowRow).
--
-- Geometry is passed in because those two places size their rows differently;
-- everything else -- what a row IS, what clicking one does -- lives here so it
-- cannot drift between them.
--
-- Draws NOTHING when you have eaten nothing, or have none of it left: an empty
-- section would be a permanent reminder that you are out of food. Returns the
-- number of rows drawn so a caller can react to that.
-- ---------------------------------------------------------------------------
function M.renderFoodSection(opts)
    if not hasImgui then return 0; end
    opts = (type(opts) == 'table') and opts or {};
    local rows = nil;
    pcall(function() rows = require('dlac\\feature\\foodwatch').menu(); end);
    if type(rows) ~= 'table' or #rows == 0 then return 0; end

    local iconW  = tonumber(opts.iconW) or M._ICON_W;
    local labelX = tonumber(opts.labelX) or M._LABEL_X;
    local rowH   = tonumber(opts.rowH) or M._ROW_H;
    local col    = opts.col or (D ~= nil and D.COL ~= nil and D.COL.USABLE) or { 1, 1, 1, 1 };
    local dim    = opts.dim or (D ~= nil and D.COL ~= nil and D.COL.DIM) or { 0.6, 0.6, 0.6, 1 };

    imgui.Separator();
    imgui.TextColored(dim, 'Recently eaten');
    local drewN = 0;
    for i, r in ipairs(rows) do
        local hit, sized = false, false;
        pcall(function()
            hit = imgui.Selectable('##dlacfood_' .. i, false,
                                   (ImGuiSelectableFlags_None or 0), { 0, rowH });
            sized = true;
        end);
        if not sized then hit = imgui.Selectable('##dlacfood_' .. i); end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(esc(string.format(
                'Eat %s -- one of the %d in your Inventory.\nLast eaten %s.',
                r.name, r.count,
                require('dlac\\feature\\foodwatch')._fmtAgo(os.time() - (r.at or 0)))));
        end
        imgui.SameLine(M._ICON_GAP);
        -- The item's OWN icon, from the game's resource (ui\itemicons retains the
        -- texture object -- a bare handle is the dangling-pointer crash). No PNG
        -- to ship and nothing to keep in step with the food list.
        local drew = false;
        pcall(function()
            local h = require('dlac\\ui\\itemicons').handleOf(r.id);
            if h == nil then return; end
            imgui.Image(h, { iconW, iconW });
            drew = true;
        end);
        if not drew then imgui.Dummy({ iconW, iconW }); end
        imgui.SameLine(labelX);
        imgui.TextColored(col, esc(r.name));
        imgui.SameLine(0, 6);
        imgui.TextColored(dim, esc('x' .. tostring(r.count)));
        drewN = drewN + 1;
        if hit then
            queue(r.cmd);
            if opts.closeOnPick ~= false then imgui.CloseCurrentPopup(); end
        end
    end
    return drewN;
end

-- A Settings checkbox: the box, then the panel-text standard label (underlined key
-- phrase + the explanation in a HOVER, never an inline paragraph). get() reads the
-- live source EVERY frame, so this and the contextual checkbox elsewhere cannot drift.
local function settingCheck(key, label, tip, get, set)
    local buf = { get() == true };
    if imgui.Checkbox('##dlacset_' .. key, buf) then
        set(buf[1] == true);
        if D ~= nil and type(D.ui) == 'table' then D.ui._flagsDirty = true; end
    end
    imgui.SameLine(0, 6);
    if uistyl ~= nil and type(uistyl.helpLabel) == 'function' then
        uistyl.helpLabel(imgui, label, tip);
    else
        imgui.TextColored(D.COL.USABLE, label);
        if tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(tip); end
    end
end

-- ---------------------------------------------------------------------------
-- The Settings panel.
-- ---------------------------------------------------------------------------
local function renderSettingsBody()
    local ui, COL = D.ui, D.COL;
    local sf, optim = D.sf, D.optim;

    imgui.TextColored(COL.HEADER, 'Settings');
    imgui.TextColored(COL.DIM, 'Remembered for this character.');
    imgui.Separator();

    -- The 3-value open setting, as a segmented button row. BeginCombo would work, but
    -- three tinted buttons need no popup-inside-a-popup and read at a glance (the
    -- macrobook pickGrid precedent).
    if uistyl ~= nil and type(uistyl.helpLabel) == 'function' then
        uistyl.helpLabel(imgui, 'Open the dlac window:',
            'Show this window automatically.\n\nNever -- only when you type /dl ui.\nOn login -- once, the first moment your character is known.\nOn login + job change -- also every time you change job.', COL.HEADER);
    else
        imgui.TextColored(COL.HEADER, 'Open the dlac window:');
    end
    local cur = M._normalizeOpenMode(ui._openMode);
    for i, mode in ipairs(M.OPEN_MODES) do
        if i > 1 then imgui.SameLine(0, 4); end
        local on = (mode == cur);
        if on then imgui.PushStyleColor(ImGuiCol_Button, { 0.55, 0.45, 0.15, 1.0 }); end
        if imgui.SmallButton(M.OPEN_LABELS[mode] .. '##dlacopen_' .. mode) then
            ui._openMode = mode;
            ui._flagsDirty = true;
        end
        if on then imgui.PopStyleColor(1); end
    end

    imgui.Separator();

    -- Same wording as the tab's own tick (they are ONE flag): "Show all
    -- equipment" read as a preference and nobody found it here.
    settingCheck('showall', "Show gear I don't own",
        'Off (default): the All Equipment tab lists only gear you own.\nOn: it lists the full CatsEyeXI catalog, with what you lack in orange.\n\nSame switch as the tick on the All Equipment tab itself.',
        function() return type(ui.showAll) == 'table' and ui.showAll[1] == true; end,
        function(v) if type(ui.showAll) == 'table' then ui.showAll[1] = v; end end);

    if sf ~= nil then
        settingCheck('autosync', 'Auto-sync gear',
            'Index new gear by itself -- on pickup, on login and on job change.\nOff: your gear library only updates when you scan by hand.\n(Same switch as /dl autosync.)',
            function() return sf.flags.autosync == true; end,
            function(v) sf.flags.autosync = v; end);

        settingCheck('viewids', 'Show item IDs on hover',
            'Append the item id and appearance model id to every equipment tooltip --\nthe two numbers you need when reasoning about a lockstyle (the look is\nthe MODEL id, not the item id). (Same switch as /dl view_ids.)',
            function() return sf.flags.viewids == true; end,
            function(v) sf.flags.viewids = v; end);

        settingCheck('autobuildimport', 'Auto-build sets on import',
            'On (default): importing a job that carries stat weights rebuilds its sets\nfrom YOUR gear the moment it lands -- the point of the empty shells an\nexport ships by default.\nOff: the import lands exactly as exported, gear and all. Auto-Build All on\nthe Sets tab still does the re-solve on demand. (Same switch as\n/dl autobuildimport.)',
            function() return sf.flags.autobuildimport ~= false; end,
            function(v) sf.flags.autobuildimport = v; end);

        settingCheck('gearwarn', 'Warn about gear in storage',
            'Warns you if any gear assigned to sets that are assigned to trigger rules\nare not available in the field.\nWill warn you once per main job change.\n(Same switch as /dl gearwarn.)',
            function() return sf.flags.gearwarn ~= false; end,
            function(v)
                sf.flags.gearwarn = v;
                -- Ticking it back on re-arms the once-per-job gate: the answer
                -- should come on the job you are standing on, not the next one.
                if v then pcall(function() require("dlac\\gear\\gearcheck").rearm(); end); end
            end);

        settingCheck('debug', 'Debug mode',
            'Reveal the developer tools: the Scan / Stage / Commit / Augs rows in this\nmenu, plus extra chat output. (Same switch as /dl debug.)',
            function() return sf.flags.debug == true; end,
            function(v) sf.flags.debug = v; end);
    end

    imgui.Separator();
    imgui.TextColored(COL.DIM, 'Also reachable where they are used:');

    if optim ~= nil then
        settingCheck('buildmax', 'Build as lv.75',
            'Assemble sets at level 75 even while you are lower, so a set you build now\nis the set you will wear at cap. Also on the Sets tab.',
            function() return optim.buildAtMaxLevel == true; end,
            function(v)
                optim.buildAtMaxLevel = v;
                if type(ui.buildMax) == 'table' then ui.buildMax[1] = v; end
            end);
    end

    settingCheck('gearfloat', 'Floating equipment window',
        'The small always-on-screen equipment window, independent of this one.\nAlso on the Equipped tab.',
        function() return ui._gearFloat == true; end,
        function(v) ui._gearFloat = v; end);

    settingCheck('tpfloat', 'Teleports floating button',
        'The always-on-screen Teleports button, independent of this window.\nAlso in the Teleports menu footer.',
        function() return ui._tpFloat == true; end,
        function(v) ui._tpFloat = v; end);

    settingCheck('tgmon', 'Trigger monitor',
        'The live window showing which triggers fired on your last action.\nAlso on the Triggers tab.',
        function() return ui._tgMon == true; end,
        function(v) ui._tgMon = v; end);

    settingCheck('arbmon', 'Arbiter monitor',
        'The live window showing what WON each equipment slot on the last gear\ndecision and why -- hover a slot for the full contest -- plus a history of\ndecisions. Also under Gear Helpers > Claim Priority.',
        function() return ui._arbMon == true; end,
        function(v) ui._arbMon = v; end);

    settingCheck('stream', 'Gear data stream (this session)',
        'Broadcast every gear decision to other addons on this machine (the\nIntegration surface -- e.g. a damage parser correlating your gear). Session\nonly: never saved, dies on logout. Same switch as /dl stream.',
        function()
            local on = false;
            pcall(function() on = require('dlac\\feature\\integration').on == true; end);
            return on;
        end,
        function(v)
            pcall(function() require('dlac\\feature\\integration').setOn(v == true); end);
        end);
end

-- ---------------------------------------------------------------------------
-- The level-override panel -- a TYPED number, committed ONCE.
--
-- The old +/- buttons queued '/dl set level main N' on every single click, so
-- dragging from 30 to 55 fired five engine re-flattens. Henrik: "please make it so we
-- only set a custom number instead of using +- buttons that spam level changes, it's
-- tedious."
-- ---------------------------------------------------------------------------
local function commitLevel(v)
    rawset(_G, 'staticMainLevel', v);
    pcall(function()
        AshitaCore:GetChatManager():QueueCommand(1, '/dl set level main ' .. tostring(v));
    end);
end

local function renderLevelBody()
    local ui, COL = D.ui, D.COL;
    local ovr  = rawget(_G, 'staticMainLevel');
    local on   = (type(ovr) == 'number' and ovr > 0);
    local live = 0;
    pcall(function() live = gData.GetPlayer().MainJobSync or 0; end);

    imgui.TextColored(COL.HEADER, 'Main level override');
    imgui.TextColored(COL.DIM, string.format('live: %d%s', live,
        on and ('   testing as: ' .. tostring(ovr)) or '   (no override)'));

    ui._lvlBuf = ui._lvlBuf or { '' };
    if ui._lvlSeed ~= true then
        ui._lvlBuf[1] = tostring(on and ovr or live);
        ui._lvlSeed = true;
    end

    imgui.PushItemWidth(70);
    local entered = false;
    -- Flag globals are nil-checked, never the function (hard rule 2): a binding
    -- without them just loses Enter-to-commit, it does not crash.
    local flags = 0;
    if ImGuiInputTextFlags_CharsDecimal ~= nil then flags = flags + ImGuiInputTextFlags_CharsDecimal; end
    if ImGuiInputTextFlags_EnterReturnsTrue ~= nil then flags = flags + ImGuiInputTextFlags_EnterReturnsTrue; end
    if flags ~= 0 then
        entered = imgui.InputText('##dlaclvlbuf', ui._lvlBuf, 4, flags);
    else
        imgui.InputText('##dlaclvlbuf', ui._lvlBuf, 4);
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 6);
    local set = imgui.Button('Set##dlaclvlset', { 0, 22 });
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Apply this level. One command is sent, once -- typing does nothing until you\ncommit with Enter or this button.');
    end
    if set or entered == true then
        local n = M._parseLevel(ui._lvlBuf[1]);
        if n ~= nil then
            commitLevel(n);
            ui._lvlSeed = nil;
        end
    end
    imgui.SameLine(0, 10);
    if imgui.Button('Back to live##dlaclvl0', { 0, 22 }) then
        commitLevel(0);
        ui._lvlSeed = nil;
    end
    imgui.TextColored(COL.DIM, 'Any level 1-75. 0 (or Back to live) clears the override.');
end

-- ---------------------------------------------------------------------------
-- Row actions. Kept in one place so the popup body stays readable, and so a test can
-- reach them without imgui.
-- ---------------------------------------------------------------------------
function M.activate(key)
    if D == nil then return false; end
    local ui = D.ui;
    if     key == 'lockstyle' then pcall(function() require('dlac\\feature\\lockstyle').open(); end);
    elseif key == 'macrobook' then pcall(function() require('dlac\\feature\\macrobook').open(); end);
    elseif key == 'hobbybar'  then pcall(function() require('dlac\\ui\\hobbybar').toggleVisible(); end);
    elseif key == 'wishlist'  then pcall(function() require('dlac\\ui\\wishlistui').open(); end);
    elseif key == 'teleports' then ui._tpOpen = true;
    elseif key == 'level'     then ui._lvlOpen = true; ui._lvlSeed = nil;
    elseif key == 'settings'  then ui._setOpen = true;
    elseif key == 'scan'      then
        if type(D.callImport) == 'function' then pcall(D.callImport, 'scanAndReport'); end
        if type(D.refreshOwnedCounts) == 'function' then pcall(D.refreshOwnedCounts); end
    elseif key == 'stage'     then
        if type(D.callImport) == 'function' then pcall(D.callImport, 'stage'); end
    elseif key == 'commit'    then
        if type(D.callImport) == 'function' then pcall(D.callImport, 'commit'); end
    elseif key == 'augs'      then
        if type(D.dumpAugs) == 'function' then pcall(D.dumpAugs); end
    else return false; end
    return true;
end

-- ---------------------------------------------------------------------------
-- The header button entry. gearui's btns loop draws it like any other declarative
-- entry -- this just keeps the label, width and tooltip next to the menu they open.
-- ---------------------------------------------------------------------------
M._TIP = 'Lockstyle, Macro book, Hobby bar, Teleports, your Wishlist, the level\noverride -- and Settings. (Developer tools appear here under /dl debug on.)';

function M.headerButton()
    local function arm() if D ~= nil then D.ui._menuOpen = true; end end
    -- With the art present this is a 26px icon button, matching the visual language
    -- of the row it replaced. Without it, the wide TEXT button -- so a failed texture
    -- load leaves a labelled, obvious button rather than a mystery 26px square. The
    -- declared width has to match what is actually drawn: gearui right-aligns the row
    -- by summing b.w.
    if iconHandle(M._MENU_ICON) == nil then
        return { l = 'Menu', w = M._MENU_W, tip = M._TIP, fn = arm };
    end
    return { w = M._MENU_BTN_W, tip = M._TIP,
        render = function()
            local clicked = false;
            local h = iconHandle(M._MENU_ICON);
            if h ~= nil then
                pcall(function()
                    clicked = imgui.ImageButton(h, { M._MENU_ICON_W, M._MENU_ICON_W });
                end);
            else
                clicked = imgui.Button('Menu##hdrmn', { M._MENU_BTN_W, 22 });
            end
            if clicked then arm(); end
        end };
end

-- ---------------------------------------------------------------------------
-- Everything below runs at WINDOW scope, from gearui's header. Each popup does its
-- own deferred OpenPopup: picking a row closes THIS menu and arms the target, so no
-- popup is ever nested inside another one.
-- ---------------------------------------------------------------------------
-- A body that errors mid-popup leaves the imgui stack torn for the rest of the frame,
-- which presents as "the panel is blank and buttons do nothing" with no trace. Same
-- treatment as gearui's tabGuard: run it guarded, but say so LOUDLY -- one chat line
-- per DISTINCT error, cleared by the first clean frame. Swallowing it silently is how
-- a broken Settings panel ships unnoticed.
local _bodyErr = {};
local function guarded(tag, fn)
    local ok, err = pcall(fn);
    if ok then _bodyErr[tag] = nil; return; end
    err = tostring(err);
    if err ~= _bodyErr[tag] then
        _bodyErr[tag] = err;
        pcall(function() print('[dlac] ' .. tag .. ' error: ' .. err); end);
    end
end

function M.renderPopups()
    if not hasImgui or D == nil or type(D.ui) ~= 'table' then return; end
    local ui, COL = D.ui, D.COL;
    local debugOn = (D.sf ~= nil and D.sf.flags.debug == true);

    if ui._menuOpen then imgui.OpenPopup('##dlac_menu'); ui._menuOpen = nil; end
    if imgui.BeginPopup('##dlac_menu') then
        for _, r in ipairs(ROWS) do
            if menuRow(r, COL.USABLE) then
                M.activate(r.key);
                imgui.CloseCurrentPopup();
            end
        end
        -- Food rides UNDER the roster, not in it: every row above is a DOOR that
        -- opens something, and these two are the only rows in this menu that spend
        -- an item. Guarded like the popup bodies -- a food section that threw would
        -- otherwise tear the imgui stack and blank the whole menu.
        guarded('food rows', function() M.renderFoodSection({ col = COL.USABLE, dim = COL.DIM }); end);
        if debugOn then
            imgui.Separator();
            -- The section heading carries the debug icon once, in the same reserved
            -- column as the rows above it, instead of repeating it on all four.
            imgui.Dummy({ M._ICON_GAP, M._ICON_W });
            imgui.SameLine(M._ICON_GAP);
            iconCell(M._DEBUG_ICON);
            imgui.SameLine(M._LABEL_X);
            imgui.TextColored(COL.DIM, 'Developer');
            for _, r in ipairs(DEBUG_ROWS) do
                if menuRow(r, COL.DIM) then
                    M.activate(r.key);
                    imgui.CloseCurrentPopup();
                end
            end
        end
        imgui.EndPopup();
    end

    if ui._lvlOpen then imgui.OpenPopup('##dlac_lvlovr'); ui._lvlOpen = nil; end
    if imgui.BeginPopup('##dlac_lvlovr') then
        guarded('level override', renderLevelBody);
        imgui.EndPopup();
    end

    if ui._setOpen then imgui.OpenPopup('##dlac_settings'); ui._setOpen = nil; end
    if imgui.BeginPopup('##dlac_settings') then
        guarded('Settings', renderSettingsBody);
        imgui.EndPopup();
    end
end

-- ---------------------------------------------------------------------------
-- Auto-open. There is no shared login/job-change event in this addon -- every feature
-- runs its own poller off d3d_present -- so this is one too, driven by gearui's
-- existing per-frame handler. State rides the shared ui table (no new chunk locals).
-- ---------------------------------------------------------------------------
function M.autoOpenTick()
    if D == nil or type(D.ui) ~= 'table' then return; end
    local ui = D.ui;
    local job = nil;
    if type(D.mainJob) == 'function' then
        local ok, j = pcall(D.mainJob);
        if ok then job = j; end
    end
    if M._shouldAutoOpen(ui._openMode, job, ui._autoOpenJob, ui._autoOpened) then
        ui._autoOpened = true;
        if type(D.setVisible) == 'function' then pcall(D.setVisible, true); end
    end
    if job ~= nil and job ~= 0 then ui._autoOpenJob = job; end
end

return M;
