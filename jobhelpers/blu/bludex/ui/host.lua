--[[
    bludex/ui/host.lua -- the window shell: blue theme, header with the live
    point budget, the tab row (lit/unlit buttons -- BeginTabBar is not
    field-proven in this install), and per-frame ctx wiring for the tabs.

    Frame discipline: each tab renders inside pcall; a tab error draws as text
    instead of tearing the frame. Style pushes pop on every path.
]]--

local ROOT = (...):sub(1, -#('ui\\host') - 1);       -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local filetex  = require(ROOT .. 'ui\\filetex');
local spellsui = require(ROOT .. 'ui\\spellsui');
local setsui   = require(ROOT .. 'ui\\setsui');
local traitsui = require(ROOT .. 'ui\\traitsui');
local settingsui = require(ROOT .. 'ui\\settingsui');

local M = {};

M.state = nil;

local function freshState(sets)
    return {
        open = { false, },
        tab = 'Codex',
        selectedId = nil,
        detailOpen = { false, },
        detailFocus = nil,
        learnOpen = { false, },
        learnFocus = nil,
        scOpen = { false, },
        scFocus = nil,
        scWeapon = { value = 'Sword' },
        editingSet = sets.new('Set 1'),
        activeSet = nil,
        addNote = nil,
        applyNote = nil,
        nameBuf = { '' },
        addBuf = { '' },
        openCat = {},
        filters = {
            text = { '' },
            category = {}, element = {}, spellType = {}, trait = {}, learned = {},
            sort = {}, stat = {},
        },
    };
end

function M.init(deps)
    M.deps = deps;                      -- { im, book, blu, sets, cfg, save }
    M.state = freshState(deps.sets);
    -- restore the measured point-budget gap and keep it saved. Both flavors
    -- come through here, so the dlac module gets this for free. 0 means
    -- never measured: blu treats that as unknown, not as a real zero gap.
    -- measurements taken under an older model meant something else: drop
    -- them rather than compute confidently from them (2026-08-06: a sub-75
    -- gap learned from a stale reading produced 133 points against a true 79)
    if (deps.cfg.capModelVer or 0) < 3 then
        deps.cfg.capModelVer = 3;
        deps.cfg.capLearnedBonus, deps.cfg.capMeritPoints = -1, -1;
        if deps.save then deps.save(); end
    end
    local function known(v) if v ~= nil and v >= 0 then return v; end return nil; end
    deps.blu.learnedBonus = known(deps.cfg.capLearnedBonus);
    deps.blu.meritPts     = known(deps.cfg.capMeritPoints);
    deps.blu.onCapLearn = function()
        deps.cfg.capLearnedBonus = deps.blu.learnedBonus or -1;
        deps.cfg.capMeritPoints  = deps.blu.meritPts or -1;
        if deps.save then deps.save(); end
    end;
    -- restore the last active saved set (matched by name -- indices shift
    -- when sets are deleted), exactly as if it had been clicked
    local want = deps.cfg.activeSetName;
    if want ~= nil and want ~= '' then
        for i, entry in ipairs(deps.cfg.sets) do
            if entry.name == want then
                M.state.activeSet = i;
                M.state.editingSet = deps.sets.clone(entry, entry.name);
                break;
            end
        end
    end
end

function M.toggle()
    if M.state then
        M.state.open[1] = not M.state.open[1];
        -- every open re-asks the server for job data (field-confirmed cure
        -- for the stale points/set structs)
        if M.state.open[1] and M.deps then M.deps.blu.refreshIfOnBlu(); end
    end
end

function M.isOpen()
    return M.state and M.state.open[1] or false;
end

local function budgetMax(deps)
    -- blu.budget prefers the client's own number while it is trustworthy and
    -- falls back to the measured model for the level we are actually at --
    -- the client only recomputes its cap when the native Set Spells menu
    -- opens, so after a level change its number describes the level we left.
    local max = deps.blu.budget();
    if max then return max; end
    if deps.cfg.budgetOverride and deps.cfg.budgetOverride > 0 then
        return deps.cfg.budgetOverride;
    end
    return nil;
end

local TABS = { 'Codex', 'Sets', 'Traits', 'Settings' };

-- The job/level watch and auto-restore, run once per frame whether or not
-- anything renders: a level change invalidates the BLU structs like a fresh
-- login (refresh fires inside the watch). BY DIRECTION (Henrik 2026-08-06):
--   level UP / job change -- if the setting is on, spells the change
--     stripped from the last-applied set are re-added (two delayed checks
--     so the 0x061 answer has landed; quiet when nothing is missing);
--   level DOWN (sync down, delevel) -- NOTHING is sent: the client disables
--     over-level spells itself and re-enables them when the level returns,
--     and the level-sorted layout keeps the survivors in the low slots.
--     One delayed chat line reports what the sync disabled, nothing more.
-- The standalone render calls this itself; an EMBEDDING host (dlac's BLU
-- helper) calls it directly every frame, even while its panel is hidden.
function M.tick()
    local deps = M.deps;
    if deps == nil then return; end
    -- the cap-staleness watch runs every frame whether or not anything
    -- renders: the client recomputes the cap on its own schedule (the native
    -- Set Spells menu), and we have to catch the moment it does
    deps.blu.watchCap();
    local change = deps.blu.watchJobState();
    if change == 'down' then
        M.downCheck = os.clock() + 2.0;
        M.restoreChecks = nil;             -- a pending restore is moot now
    elseif change ~= nil then
        local now = os.clock();
        M.restoreChecks = { now + 2.0, now + 8.0 };
        M.downCheck = nil;
    end
    if M.downCheck ~= nil and os.clock() >= M.downCheck then
        M.downCheck = nil;
        deps.blu.reportLevelDown(deps.book);
    end
    if M.restoreChecks ~= nil then
        local due = M.restoreChecks[1];
        if due ~= nil and os.clock() >= due then
            table.remove(M.restoreChecks, 1);
            if #M.restoreChecks == 0 then M.restoreChecks = nil; end
            if deps.cfg.autoRestore == true then
                local last = deps.cfg.lastApplied;
                if last ~= nil and last.ids ~= nil then
                    deps.blu.restoreMissing(last.ids, deps.book);
                end
            end
        end
    end
end

-- body theme: what embedded rendering needs (child panels + the blue
-- Selectable/combo highlight -- the default theme's Header is RED); the
-- standalone window adds its own chrome on top. Both return the push count.
local function pushBodyTheme(im)
    if not (kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor')) then return 0; end
    im.PushStyleColor(3,  { 0.06, 0.09, 0.15, 0.97 });     -- ChildBg
    im.PushStyleColor(24, { 0.16, 0.34, 0.62, 0.85 });     -- Header
    im.PushStyleColor(25, { 0.20, 0.42, 0.74, 0.85 });     -- HeaderHovered
    im.PushStyleColor(26, { 0.24, 0.48, 0.80, 1.00 });     -- HeaderActive
    return 4;
end

local function pushWindowTheme(im)
    if not (kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor')) then return 0; end
    im.PushStyleColor(2,  { 0.055, 0.075, 0.125, 0.97 });  -- WindowBg
    im.PushStyleColor(11, { 0.10, 0.18, 0.34, 1.00 });     -- TitleBgActive
    im.PushStyleColor(10, { 0.07, 0.11, 0.20, 1.00 });     -- TitleBg
    return 3 + pushBodyTheme(im);
end

-- the per-frame ctx handed to every tab (and to the detail float)
local function tabCtx(im, st, deps, embedded)
    return {
        im = im, book = deps.book, blu = deps.blu, sets = deps.sets,
        cfg = deps.cfg, save = deps.save, state = st,
        embedded = embedded == true,
        -- true once an embedding host's sanctioned float surface has run:
        -- the codex then routes Spell Info there instead of its in-panel pane
        floatWindow = deps.floatWindow == true,
        budgetMax = function() return budgetMax(deps); end,
    };
end

-- Does the LIVE in-game set differ from the editing set's SORTED layout
-- (slot-wise -- what applyDiff would send)? So a right-spells-wrong-order
-- set lights Apply green, and one click re-sorts it. true / false, nil
-- when the live set is unreadable.
local function applyDirty(deps, st)
    local live = deps.blu.currentSet();
    if #live ~= 20 then return nil; end
    local T = deps.sets.sortedLayout(st.editingSet.ids, deps.book);
    for i = 1, 20 do
        if (live[i] or 0) ~= T[i] then return true; end
    end
    return false;
end

-- header + tab row + the active tab: everything between Begin and End,
-- shared verbatim by the standalone window and the embedded flavor.
-- `embedded` reaches the tabs through ctx: a dlac Job helper Panel may not
-- open windows itself, so the codex either uses the host's float surface
-- (renderDetailFloat below) or falls back to an in-panel pane.
local function renderBody(im, st, deps, embedded)
    -- header: logo + budget
    local logo = filetex.ui('logo-64');
    if logo ~= nil and kit.isFn(im, 'Image') then
        pcall(im.Image, logo, { 22, 22 });
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
    end
    kit.ctext(im, kit.COL.head, 'BLUDEX');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    -- the header meters are the EDITING set against the budget -- the
    -- planning numbers needed while adding from the codex. Live-vs-
    -- planned shows per-slot in the Sets tab (dimming).
    local max = budgetMax(deps);
    kit.meter(im, '   Set:', deps.sets.usedPoints(st.editingSet, deps.book), max, ' pts');
    kit.tip(im, max ~= nil
        and 'Points used by the set you are editing /\nyour total from the game client (CatsEyeXI bonuses included).'
        or 'Points used by the set you are editing.\nThe total appears when you are on BLU (or set budgetOverride).');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.meter(im, '   Slots:', deps.sets.count(st.editingSet), 20, '');
    -- the level-sync line (Henrik 2026-08-06): the meters above stay the
    -- PLAN (the editing set at full level); when the effective BLU level is
    -- under the 75 cap this shows what the client holds RIGHT NOW -- the
    -- sync-enabled spells' points against the synced budget, and those
    -- spells against the synced slot count (the server's slot rule).
    local ss = deps.blu.syncStats(deps.book);
    if ss ~= nil and ss.level < 75 then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        -- the budget FOR THE SYNCED LEVEL, not the client's leftover from
        -- full level (field 2026-08-06: this read "7 / 79 pts" at a Lv40 sync
        -- whose real budget is 49, because points() had not recomputed)
        local liveMax = deps.blu.budget();
        kit.ctext(im, kit.COL.warn, ('   Sync Lv.%d: %d / %s pts  %d / %d slots'):format(
            ss.level, ss.activePoints, liveMax and tostring(liveMax) or '?',
            ss.active, ss.maxSlots));
        kit.tip(im, ('Level sync: what is live RIGHT NOW at Lv.%d.\n'
            .. 'The game disabled the rest of the set itself; everything\n'
            .. 'returns when the sync ends. The Set/Slots meters keep\n'
            .. 'showing the plan at full level.'):format(ss.level));
    end
    -- the cap the client holds can belong to a level we have left (the client
    -- only recomputes it when the native Set Spells menu opens). Say so
    -- rather than showing a confident wrong number -- and name the one action
    -- that actually fixes it, because nothing Bludex can send does.
    local differs, watched = deps.blu.capDisagrees();
    if differs and not watched then
        -- The client's number was never seen to recompute -- Bludex has only
        -- found it sitting there. Almost always the level sync's leftover.
        -- Tell the player the two clicks that refresh it for good.
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.warn, '   refresh points');
        kit.tip(im, ('The game client still reports %s points; Bludex works your\n'
            .. 'total out as %s and is showing that.\n\n'
            .. 'To refresh the game\'s own number, open:\n'
            .. '    Magic  ->  Blue Magic  ->  Set\n'
            .. 'That is the only thing that makes the client recalculate it.\n\n'
            .. 'Also zone once after loading Bludex: your merits arrive with the\n'
            .. 'zone, and Bludex needs them to work the total out.'):format(
            tostring(deps.blu.capValue()), tostring(deps.blu.expectedCap())));
    elseif differs then
        -- we WATCHED it recompute at this level and it still disagrees:
        -- our own parts are wrong, and the game is the authority
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.err, '   check Settings');
        kit.tip(im, ('The game client recalculated its total for your current\n'
            .. 'level and got %s, but Bludex works it out as %s.\n\n'
            .. 'The game is right, and it is the number being shown. One of the\n'
            .. 'parts on the Settings tab is wrong -- most likely the learned\n'
            .. 'bonus, if you have collected more from Boruko since.'):format(
            tostring(deps.blu.capValue()), tostring(deps.blu.expectedCap())));
    elseif deps.blu.capStale() then
        local _, src = deps.blu.budget();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if src == 'model' then
            -- we have measured this character's gap, so the number above is
            -- ours and correct -- say where it came from, quietly
            kit.ctext(im, kit.COL.dim, '   (computed)');
            kit.tip(im, ('The game client has not recomputed its point total since\n'
                .. 'your level changed -- it still holds the Lv.%s figure. The\n'
                .. 'total above is Bludex\'s own, from the parts on the Settings\n'
                .. 'tab: the base rule for Lv.%s plus your learned bonus, plus\n'
                .. 'Assimilation merits when you are at 75.\n\n'
                .. 'Open the native Blue Magic set menu to see the game agree.'):format(
                tostring(deps.blu.capLevel()),
                tostring(deps.blu.effectiveLevel())));
        else
            kit.ctext(im, kit.COL.warn, '   cap stale');
            kit.tip(im, ('The point total above was computed by the game at Lv.%s\n'
                .. 'and it has not recomputed since your level changed.\n\n'
                .. 'Open the native Set Spells menu once: it corrects the number\n'
                .. 'AND teaches Bludex your point bonus, after which Bludex can\n'
                .. 'work it out for itself at every level. The cap never crosses\n'
                .. 'the network, so this one look is the only way to learn it.'):format(
                tostring(deps.blu.capLevel())));
        end
    end
    if deps.blu.onBlu() and (deps.blu.points()) == nil then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   (live points: reading...)');
        kit.tip(im, 'The client has not filled the points struct yet.\n'
            .. 'Bludex is requesting the data from the server (the same\n'
            .. '0x061 ask the native menus send). If it stays stuck:\n'
            .. '/bludex refresh re-asks, /bludex debug shows details.');
        deps.blu.nudgePoints();
    elseif not deps.blu.onBlu() then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   (not on BLU)');
    end

    -- set actions on the header line, every tab (Henrik 2026-08-04): Save
    -- and Apply light GREEN when they have work, Revert discards the unsaved
    -- changes. One definition each -- setsui owns the verbs.
    local ctx = tabCtx(im, st, deps, embedded);
    local unsaved = setsui.unsaved(ctx);
    local dirty = applyDirty(deps, st);
    local bw = kit.measure(im, { 'Save', 'Apply', 'Revert', 'Applying...' }, 48);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Save', false, bw, 22, unsaved and kit.PAL.go or kit.PAL.off) then
        if unsaved then setsui.saveEditing(ctx);
        else st.applyNote = 'Nothing to save.'; end
    end
    kit.tip(im, unsaved and 'Save the editing set - it has unsaved changes.'
        or 'The editing set matches its saved copy.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local applyPal = nil;
    if not deps.blu.applying then
        if dirty == true then applyPal = kit.PAL.go;
        elseif dirty == false then applyPal = kit.PAL.off; end
    end
    if kit.litButton(im, deps.blu.applying and 'Applying...' or 'Apply', false, bw, 22, applyPal) then
        if dirty == false then
            st.applyNote = 'Already up to date - nothing to apply.';
        else
            setsui.applyEditing(ctx);
        end
    end
    kit.tip(im, 'Apply the editing set in game - only the changed slots are sent.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Revert', false, bw, 22, unsaved and nil or kit.PAL.off) then
        if unsaved then setsui.revertEditing(ctx); end
    end
    kit.tip(im, unsaved and 'Discard the unsaved changes - back to the saved set.'
        or 'No unsaved changes to revert.');

    -- the cast lock countdown: changing set spells locks Blue Magic casting
    -- for about a minute (the game's rule) -- count it down where the eye is
    local lockRem = deps.blu.castReadyIn();
    if lockRem > 0 then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.warn, ('   castable in %ds'):format(lockRem));
        kit.tip(im, 'Changing set spells locks Blue Magic casting for about a\n'
            .. 'minute. The countdown runs from the last set change Bludex sent.');
    end

    -- tab row
    local w = kit.measure(im, TABS, 90);
    for _, t in ipairs(TABS) do
        if kit.litButton(im, t, st.tab == t, w, 26) then st.tab = t; end
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
    end
    if kit.isFn(im, 'NewLine') then im.NewLine(); end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local tabfn = (st.tab == 'Sets' and setsui.render)
        or (st.tab == 'Traits' and traitsui.render)
        or (st.tab == 'Settings' and settingsui.render)
        or spellsui.render;
    local tok, terr = pcall(tabfn, ctx);
    if not tok then
        kit.ctext(im, kit.COL.err, 'tab error: ' .. tostring(terr));
    end
    -- The Spell Info window serves EVERY tab (codex and traits rows both
    -- open it), so it draws once here after the active tab -- except in the
    -- embedded-Panel fallback, where a Panel may not open windows (the
    -- codex's in-panel pane covers it there).
    if not ctx.embedded then
        local dok, derr = pcall(spellsui.detailWindow, ctx);
        if not dok then
            kit.ctext(im, kit.COL.err, 'detail error: ' .. tostring(derr));
        end
        -- the Learn-from and Skillchain-partners windows ride along the
        -- same way (their open buttons live inside Spell Info)
        pcall(spellsui.learnWindow, ctx);
        pcall(spellsui.scWindow, ctx);
    end
end

-- the floating Bludex window itself (Begin/End + chrome), shared by the
-- standalone render and the dlac float surface
local function renderWindow(im, st, deps)
    if not kit.isFn(im, 'Begin') or not kit.isFn(im, 'End') then return; end
    local pushed = pushWindowTheme(im);
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        -- 920 wide fits the measured filter row; below that the Reset button clips
        pcall(im.SetNextWindowSizeConstraints, { 920, 520 }, { 4096, 4096 });
    end
    local visible = false;
    local ok = pcall(function()
        visible = im.Begin('Bludex##bdxmain', st.open);
    end);
    if ok and visible then
        renderBody(im, st, deps, false);
    end
    if ok then im.End(); end
    if pushed > 0 then im.PopStyleColor(pushed); end
end

-- the standalone flavor (the bludex addon's own d3d_present hook)
function M.render()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil then return; end
    M.tick();
    if not st.open[1] then return; end
    renderWindow(deps.im, st, deps);
end

-- Open the window outright (the toggle flips; a launcher wants OPEN).
-- Same open-refresh as toggle: field-confirmed cure for stale structs.
function M.open()
    if M.state == nil then return; end
    if not M.state.open[1] then
        M.state.open[1] = true;
        if M.deps then M.deps.blu.refreshIfOnBlu(); end
    end
end

-- The WHOLE Bludex window through an embedding host's float surface (dlac's
-- `window` hook): the full codex/sets/traits experience in its own window,
-- alive independent of the host's main box. Self-gates on st.open -- the
-- host's Panel is the launcher. Marks the float surface live even while
-- closed, so the Panel knows the launcher flavor applies (and the Spell
-- Info window rides along exactly as in standalone, embedded = false).
-- Ticking stays with the host's beat subscription, not here.
function M.renderWindowFloat()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil or deps.im == nil then return; end
    deps.floatWindow = true;
    if not st.open[1] then return; end
    renderWindow(deps.im, st, deps);
end

-- The Spell Info window ALONE, for an embedding host's sanctioned float
-- surface (dlac's `window` contract hook, ADR 0028 amendment 2026-08-04):
-- the codex list stays in the Panel; the detail window draws from the
-- host's float site, so it survives the host's main window closing. It
-- self-gates -- spellsui.detailWindow returns unless a spell was clicked
-- open. Marks the float surface live so the embedded codex stops offering
-- its in-panel fallback pane.
function M.renderDetailFloat()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil or deps.im == nil then return; end
    deps.floatWindow = true;
    local im = deps.im;
    local pushed = pushWindowTheme(im);      -- a float owns its window chrome
    local ctx = tabCtx(im, st, deps, true);
    pcall(spellsui.detailWindow, ctx);
    pcall(spellsui.learnWindow, ctx);
    pcall(spellsui.scWindow, ctx);
    if pushed > 0 then im.PopStyleColor(pushed); end
end

-- The embedded flavor for a hosting addon's own window (dlac's BLU helper):
-- no Begin/End, no window chrome -- the body draws into whatever window or
-- child is current. The host addon calls M.init once, M.tick() every frame
-- (visible or not), and this when its panel shows. See INTEGRATION.md.
function M.renderEmbedded()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil then return; end
    local im = deps.im;
    local pushed = pushBodyTheme(im);
    local ok, err = pcall(renderBody, im, st, deps, true);
    if not ok then
        kit.ctext(im, kit.COL.err, 'bludex error: ' .. tostring(err));
    end
    if pushed > 0 then im.PopStyleColor(pushed); end
end

return M;
