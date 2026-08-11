--[[
    bludex/ui/setsui.lua -- the Sets tab, timeline flavor (2026-08-08,
    docs/timeline-sets-plan.md):

      left    saved sets (badges, backup rings, name, built-for floor)
      middle  the level slider (preview only) and the bracket-grouped chain
              list -- each slot's active spell at the preview level with the
              rest of its timeline beneath; then meters, the whole-curve
              band verdict, and the game actions (Apply / Apply for Lv.N /
              Read current / Clear, the level-change rule)
      right   Stats (at the preview level) | Assign (the picker for the
              selected slot -- ALL set mutation lives here now)

    The grid and the quick-add strip are gone; cfg.setsLayout is ignored.
    The budget meter prefers the LIVE client value at the live level and
    the measured model elsewhere. Everything degrades: no signature ->
    settings override -> '?'.
]]--

local ROOT = (...):sub(1, -#('ui\\setsui') - 1);     -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local spellsui = require(ROOT .. 'ui\\spellsui');
local blusetsimport = require(ROOT .. 'lib\\blusetsimport');

local M = {};

local LEFT_W  = 210;
local MID_W   = 330;

-- ---------------------------------------------------------------------------
-- the two systems a set can be (docs/set-types-plan.md; Henrik 2026-08-10,
-- second field round: flat and Lvl Subsets are ONE kind -- "a level set
-- list is basically a flat list but additional level sync opportunity").
-- The blurbs are the chooser's copy. Order is canonical; the chooser
-- floats cfg.newSetKind to the top.
-- ---------------------------------------------------------------------------
M.KIND_ORDER = { 'levels', 'timeline' };
M.KIND_INFO = {
    levels = {
        label = 'Flat',
        blurb = 'One spell per slot, applied as-is -- the simplest kind.\n'
            .. 'Add dedicated builds per level range (level sync) under\n'
            .. 'the same name whenever you want them; the base build\n'
            .. 'answers wherever no range is built.',
    },
    timeline = {
        label = 'Slotlist',
        blurb = 'A list of spells per slot, each taking over at its own\n'
            .. 'level. Recommended when you want granular control over\n'
            .. 'which spells go to which slot at specific levels. The most\n'
            .. 'capable kind: one set can plan the whole climb to 75.',
    },
};
M.KIND_INFO.flat = M.KIND_INFO.levels;   -- the old key, kept for callers

-- ---------------------------------------------------------------------------
-- the set actions -- ONE definition each, shared by the Sets tab buttons and
-- the window header's Save / Apply / Revert (host.renderBody)
-- ---------------------------------------------------------------------------

-- The budget for ANY level -- the band sweep's oracle. The model (base +
-- learned bonus, + merits only at 75) is the one source that can answer at
-- an arbitrary level; the client's live cap only ever describes the level
-- it was computed at. The level-75 settings override fills in when the
-- model has no learned bonus yet -- at 75 only, where its number means
-- what it says. nil = unknown (bandViolations then marks PROVISIONAL).
function M.budgetFn(ctx)
    return function(L)
        local c = ctx.blu.expectedCap(L);
        if c ~= nil then return c; end
        if L >= 75 and ctx.cfg.budgetOverride and ctx.cfg.budgetOverride > 0 then
            return ctx.cfg.budgetOverride;
        end
        return nil;
    end;
end

-- Save the editing set into the saved list (the active entry, or a new
-- one). A LEVELS DRAFT saves through groupPut -- one build written back,
-- the entry's other builds untouched. Overwriting a DIFFERENT saved state
-- banks it on the set's backup ring first (cap 5, newest first, EVERY
-- kind since 2026-08-10) -- the save is undoable.
function M.saveEditing(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    if st.editingSet.draft then
        local level = st.editingSet.level;
        local entry = st.activeSet and cfg.sets[st.activeSet] or nil;
        if entry == nil then
            entry = ctx.sets.new(st.editingSet.name, 'levels');
            table.insert(cfg.sets, entry);
            st.activeSet = #cfg.sets;
        end
        -- bank the entry as it stands before the draft lands in it -- the
        -- ring lives on the entry, and groupPut mutates in place
        local was = ctx.sets.clone(entry, entry.name);
        entry.name = st.editingSet.name;
        ctx.sets.groupPut(entry, level, st.editingSet.ids);
        if not ctx.sets.equal(was, entry) then
            ctx.sets.pushBackup(entry, was, os.time());
        end
        cfg.activeSetName = entry.name;            -- remembered across loads
        if ctx.save then ctx.save(); end
        st.applyNote = (level == nil) and 'Saved.'
            or ('Saved %s, Lv.%d.'):format(entry.name, level);
        return;
    end
    local copy = ctx.sets.clone(st.editingSet, st.editingSet.name);
    copy.name = st.editingSet.name;
    if st.activeSet and cfg.sets[st.activeSet] then
        local old = cfg.sets[st.activeSet];
        -- the RING LIVES ON THE SAVED ENTRY: the editing clone's ring is a
        -- snapshot from selection time, so adopting it here would reset the
        -- ring to depth one on every save (review 2026-08-08). Carry the
        -- entry's own ring forward, then bank the state being replaced.
        copy.backups = old.backups;
        if not ctx.sets.equal(old, copy) then
            ctx.sets.pushBackup(copy, old, os.time());
        end
        cfg.sets[st.activeSet] = copy;
    else
        table.insert(cfg.sets, copy);
        st.activeSet = #cfg.sets;
    end
    cfg.activeSetName = copy.name;                 -- remembered across loads
    if ctx.save then ctx.save(); end
    st.applyNote = 'Saved.';
end

-- Revert the editing set to its saved copy (or to a fresh empty set when
-- nothing is saved yet) -- removes ALL unsaved changes. A levels draft
-- reverts to ITS build's saved state, no other build is touched.
function M.revertEditing(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local saved = st.activeSet and cfg.sets[st.activeSet] or nil;
    if saved ~= nil then
        if st.editingSet.draft then
            st.editingSet = ctx.sets.draft(saved, st.editingSet.level, ctx.book);
            st.applyNote = (st.editingSet.level == nil)
                and 'Reverted to the saved base build.'
                or ('Reverted to the saved Lv.%d build.'):format(st.editingSet.level);
        else
            st.editingSet = ctx.sets.clone(saved, saved.name);
            st.applyNote = 'Reverted to the saved set.';
        end
    else
        st.editingSet = ctx.sets.new(('Set %d'):format(#cfg.sets + 1),
            ctx.sets.kindOf(st.editingSet));
        st.applyNote = 'Reverted - empty set.';
    end
    st.addNote = nil;
end

-- Apply the editing set in game: the timeline RESOLVED for a level --
-- forLevel when given (the preemptive 'Apply for Lv.N'), else the live
-- effective level. Hard-blocked while an ENFORCED band violation exists
-- (at/above the set's builtFor, budget actually known -- plan 2.6); the
-- block message is the band message. Snapshots what was sent and the
-- level it was FOR, so the dirty compare can recognize a preemptive
-- apply instead of glowing green against it.
function M.applyEditing(ctx, forLevel)
    local st = ctx.state;
    if ctx.blu.applying then return; end
    -- refusals ALSO speak in chat: the nudge float, /bdx replan and the
    -- auto re-plan all land here with no window to show applyNote in
    -- (review 2026-08-08 -- a refused click must never be silent)
    local function refuse(note)
        st.applyNote = note;
        if ctx.blu.announce then pcall(ctx.blu.announce, note); end
    end
    if not ctx.blu.canApply() then
        refuse(ctx.blu.onBlu()
            and 'Cannot apply: the client memory signatures did not resolve.'
            or 'Cannot apply: BLU is not your main or sub job.');
        return;
    end
    local viol = ctx.sets.enforcedViolations(st.editingSet, ctx.book, M.budgetFn(ctx));
    if #viol > 0 then
        refuse(('Cannot apply: %s.'):format(ctx.sets.bandText(viol[1])));
        return;
    end
    local lvl = forLevel or ctx.blu.effectiveLevel() or 75;
    local ids = ctx.sets.resolveAtLevel(st.editingSet, lvl, ctx.book);
    -- the layout is the kind's call: a timeline's slots are authorship,
    -- flat/levels keep sorted placement (setmodel.applyLayout)
    if ctx.blu.applyDiff(ids, ctx.book, nil,
        ctx.sets.applyLayout(st.editingSet, ids, ctx.book)) then
        local snap = {};
        for k = 1, 20 do snap[k] = ids[k] or 0; end
        ctx.cfg.lastApplied = { ids = snap, level = lvl };
        -- WHAT THIS LEVEL WILL REFUSE, and a promise to come back for it
        -- (Henrik 2026-08-10, sixth round). Applying a 75 plan under a sync
        -- gets the tail bounced by the game; that used to be silent, and
        -- the only cure was remembering to Apply again once the sync ended.
        -- Bank it and the level watcher finishes the job. Measured at the
        -- LIVE level whatever level the plan was sent for -- 'Apply for
        -- Lv.41' at 75 is refused nothing.
        --
        -- FIELD NAMES ARE NOT FREE HERE: this table lands in cfg, whose
        -- default is an Ashita T{}, and a T{} carries the table helpers as
        -- fields. `count` is one of them, and reading it back cost a crash
        -- (field 2026-08-10). ids/need/waiting only, read back through
        -- host.pendingPromise, never field by field.
        local liveLvl = ctx.blu.effectiveLevel();
        ctx.cfg.pendingSync = {};         -- a new apply retires any old tail
        if liveLvl ~= nil then
            local refused, need = ctx.sets.refusedAtLevel(snap, liveLvl, ctx.book);
            if #refused > 0 and need ~= nil then
                ctx.cfg.pendingSync = { ids = snap, need = need, waiting = refused };
                local line = ('Lv.%d cannot hold %d of these spells - Bludex will set them\nwhen you reach Lv.%d.'):format(
                    liveLvl, #refused, need);
                st.applyNote = (line:gsub('\n', ' '));
                if ctx.blu.announce then pcall(ctx.blu.announce, (line:gsub('\n', ' '))); end
            end
        end
        -- WHICH SET this came from, by name: the level-change watcher obeys
        -- the FOLLOWED set's kind and rule. Only a SAVED set has a name to
        -- follow -- an unsaved draft leaves nothing, and says so by clearing.
        local entry = st.activeSet and ctx.cfg.sets[st.activeSet] or nil;
        ctx.cfg.lastAppliedSet = (entry ~= nil) and entry.name or '';
        st.replanPending = nil;
        if ctx.save then ctx.save(); end
        -- no success note (Henrik 2026-08-10, from the field: "the green
        -- button says it all") -- the chat log narrates the apply itself,
        -- and this line only ever restated it. Refusals still speak above,
        -- and so does the sync promise set just now.
        if (ctx.cfg.pendingSync or {}).ids == nil then st.applyNote = nil; end
    end
end

-- Does the editing set differ from its SAVED copy? Drives the header's
-- green Save and the Revert. With no active saved set, any content counts.
-- A levels draft compares against ITS build in the saved entry; whole-set
-- authorship (chains, builtFor, name) compares through sets.equal.
function M.unsaved(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local saved = st.activeSet and cfg.sets[st.activeSet] or nil;
    if saved == nil then
        return ctx.sets.count(st.editingSet) > 0;
    end
    if st.editingSet.draft then
        if tostring(saved.name) ~= tostring(st.editingSet.name) then return true; end
        local was = ctx.sets.groupIds(saved, st.editingSet.level);
        for i = 1, 20 do
            if was[i] ~= (st.editingSet.ids[i] or 0) then return true; end
        end
        return false;
    end
    return not ctx.sets.equal(saved, st.editingSet);
end

-- The ONE live-vs-plan compare (formerly duplicated in host.renderBody and
-- the Sets tab, now consolidated -- plan 5). Against the SORTED layout of
-- the resolution, so right-spells-wrong-order still counts as pending.
-- Returns state, level:
--   'clean'   live matches the plan for the LIVE level
--   'planned' live matches the plan applied FOR another level (the
--             preemptive apply) -- level names it
--   'dirty'   live differs from both
--   nil       the live set is unreadable
function M.applyState(ctx)
    local live = ctx.blu.currentSet();
    if #live ~= 20 then return nil; end
    local st = ctx.state;
    local lvl = ctx.blu.effectiveLevel() or 75;
    local function matches(atLevel)
        -- against the layout the apply would SEND (kind-aware since the
        -- 2026-08-10 field round: a timeline's positions count, so two
        -- levels' plans that differ only by slot no longer compare equal)
        local T = ctx.sets.applyLayout(st.editingSet,
            ctx.sets.resolveAtLevel(st.editingSet, atLevel, ctx.book), ctx.book);
        for i = 1, 20 do
            if (live[i] or 0) ~= T[i] then return false; end
        end
        return true;
    end
    if matches(lvl) then return 'clean', lvl; end
    local la = ctx.cfg.lastApplied;
    if la ~= nil and la.level ~= nil and la.level ~= lvl and matches(la.level) then
        return 'planned', la.level;
    end
    return 'dirty', lvl;
end


-- ---------------------------------------------------------------------------
-- shared helpers
-- ---------------------------------------------------------------------------

-- The PREVIEW level: the slider's explicit choice, else the live effective
-- level, else 75. The slider only previews -- the plain Apply never reads
-- it (plan 2.9); only the explicit 'Apply for Lv.N' button does.
local function previewLevel(ctx)
    local st = ctx.state;
    if st.preview ~= nil and st.preview.value ~= nil then return st.preview.value; end
    return ctx.blu.effectiveLevel() or 75;
end

local function bracketTop(floor)
    if floor == 1 then return 10; end
    return math.min(floor + 9, 75);
end

-- 41 -> '41-50', 71 -> '71-75' (the levels kind's band naming)
local function bandText(ctx, level)
    return ('%d-%d'):format(level, ctx.sets.bandTop(level));
end

-- Selectable in a color of our choosing (a row's color IS its state here:
-- dim = nothing built, accent = a build that fits, red = one that cannot).
local function tintedSelectable(im, col, label, selected)
    local pushed = false;
    if kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
        pushed = pcall(im.PushStyleColor, 0, col);         -- ImGuiCol_Text
    end
    local ok, clicked = pcall(im.Selectable, kit.esc(label), selected);
    if pushed then pcall(im.PopStyleColor, 1); end
    return ok and clicked or false;
end

-- THE BUDGET FOR ONE RUNG, and where the number came from (the 2026-08-06
-- law, back with the levels kind). The model (blu.rungCap) answers at every
-- rung once the learned bonus is measured; the client's own number only
-- ever describes the level it was computed at, so it may speak for the rung
-- you are standing in and no other.
local function rungBudget(ctx, level)
    local cap, src = ctx.blu.rungCap(level);
    if src == 'model' then return cap, 'model'; end
    local here = ctx.sets.rungFor(ctx.blu.effectiveLevel());
    if level == nil or here == nil or level == here then
        local live = ctx.blu.budget();
        if live then return live, 'live'; end
        local ov = ctx.cfg.budgetOverride;
        if ov and ov > 0 then return ov, 'live'; end
    end
    return cap, src;                   -- 'base', or nil,nil with no rung at all
end

-- Load one build of one saved LEVELS set into the editor as a draft (level
-- nil = its base build). This is the ONE way a levels draft is created, so
-- every path remembers the same things.
local function loadBuild(ctx, index, level)
    local st, cfg = ctx.state, ctx.cfg;
    local entry = cfg.sets[index];
    if entry == nil then return; end
    ctx.sets.normalizeGroup(entry);
    st.activeSet, st.editLevel = index, level;
    st.editingSet = ctx.sets.draft(entry, level, ctx.book);
    st.applyNote = nil;
    st.addNote = nil;
    st.assignSlot = nil;
    cfg.activeSetName = entry.name;                -- remembered across loads
    if ctx.save then ctx.save(); end
end
M.loadBuild = loadBuild;

-- THE HEADER SET PICKER (Henrik 2026-08-10, from the field: "between
-- slots and save/apply, a scroll menu with all the sets"): switch the
-- editing set from any tab, without the trip to the Sets tab. A merged
-- set that HAS level builds opens a second menu beside it for WHICH
-- build. Drawn by host.renderBody on the header line.
function M.headerPicker(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    if #cfg.sets == 0 then return; end
    -- THE KINDS STAY SEPARATE (Henrik 2026-08-10: "so you understand what
    -- lists you're working with"): flat sets first, slotlists after, and a
    -- slotlist wears its tag in the list AND in the closed combo
    local names, map = {}, {};
    for i, e in ipairs(cfg.sets) do
        if ctx.sets.kindOf(e) ~= 'timeline' then
            names[#names + 1] = e.name;
            map[#names] = i;
        end
    end
    for i, e in ipairs(cfg.sets) do
        if ctx.sets.kindOf(e) == 'timeline' then
            names[#names + 1] = e.name .. '  [Slotlist]';
            map[#names] = i;
        end
    end
    local cur = nil;
    local curEntry = st.activeSet and cfg.sets[st.activeSet] or nil;
    if curEntry ~= nil then
        cur = curEntry.name
            .. (ctx.sets.kindOf(curEntry) == 'timeline' and '  [Slotlist]' or '');
    end
    local pick = { value = cur };    -- rebuilt each frame: reflects, reacts
    local w = math.min(kit.measure(im, names, 90) + 24, 220);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.dim, ' ');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.combo(im, '##bdxheaderset', pick, names, cur or 'Pick a set', w) then
        for j, label in ipairs(names) do
            if label == pick.value then
                local e = cfg.sets[map[j]];
                if ctx.sets.kindOf(e) == 'levels' then
                    loadBuild(ctx, map[j], nil);
                else
                    st.activeSet = map[j];
                    st.editLevel = nil;
                    st.editingSet = ctx.sets.clone(e, e.name);
                    st.assignSlot = nil;
                    st.applyNote = nil;
                    cfg.activeSetName = e.name;
                    if ctx.save then ctx.save(); end
                end
                break;
            end
        end
    end
    kit.tip(im, 'Switch the set being edited, from any tab.\nFlat sets list first, Slotlists after (tagged).\nUnsaved edits on the current one are discarded\n(same as clicking a set in the Sets tab).');
    -- the second menu: WHICH BUILD of a set that has level builds
    local entry = st.activeSet and cfg.sets[st.activeSet] or nil;
    if entry ~= nil and ctx.sets.kindOf(entry) == 'levels' then
        local lvls = ctx.sets.groupLevels(entry);
        if #lvls > 0 then
            local bnames = { 'Base' };
            for _, lvl in ipairs(lvls) do
                bnames[#bnames + 1] = ('Lv.%d-%d'):format(lvl, ctx.sets.bandTop(lvl));
            end
            local bcur = 'Base';
            if st.editingSet.draft and st.editingSet.level ~= nil then
                bcur = ('Lv.%d-%d'):format(st.editingSet.level,
                    ctx.sets.bandTop(st.editingSet.level));
            end
            local bpick = { value = bcur };
            local bw = kit.measure(im, bnames, 70) + 24;
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if kit.combo(im, '##bdxheaderbuild', bpick, bnames, bcur, bw) then
                if bpick.value == 'Base' then
                    loadBuild(ctx, st.activeSet, nil);
                else
                    local lv = tonumber(bpick.value:match('^Lv%.(%d+)'));
                    if lv ~= nil then loadBuild(ctx, st.activeSet, lv); end
                end
            end
            kit.tip(im, 'Which build of this set is being edited:\nthe base, or one of its level ranges.');
        end
    end
end

-- ---------------------------------------------------------------------------
-- saved sets (left column): select, badge, backups, name, built-for
-- ---------------------------------------------------------------------------
-- saved-row badges, refreshed at most once a second: a band sweep per set
-- per frame is pure GC churn inside a render hook (review 2026-08-08) --
-- sets only change on explicit edits, and a one-second-stale badge is fine
local badgeCache = { at = -10, viols = {} };

-- One band row of the selected LEVELS set: '>41  12 / 30   8 / 14' -- the
-- band you stand in marked, points against the rung's budget, spells
-- against the rung's slots. Click = edit that build.
local function rungRow(ctx, index, entry, level, here)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local ids   = ctx.sets.groupIds(entry, level);
    local used  = ctx.sets.usedPoints(ids, book);
    local n     = ctx.sets.countIds(ids);
    local slots = ctx.sets.slotsAtLevel(level);
    local cap, src = rungBudget(ctx, level);
    -- '79' the number we stand behind, '45+' the base rule with this
    -- character's bonus still unmeasured, '?' nothing known at all
    local capTxt = (cap ~= nil and cap > 0)
        and (tostring(cap) .. (src == 'base' and '+' or '')) or '?';
    local over = (n > slots) or (cap ~= nil and cap > 0 and src ~= 'base' and used > cap);
    local col = kit.COL.dim;
    if over then col = kit.COL.err; elseif n > 0 then col = kit.COL.accent; end

    local label = ('%s%2d   %2d / %-4s %2d / %2d##bdxrung%d_%d'):format(
        (here == level) and '>' or ' ', level, used, capTxt, n, slots, index, level);
    local selected = (st.activeSet == index and st.editingSet.draft
        and st.editingSet.level == level);
    if tintedSelectable(im, col, label, selected) then
        loadBuild(ctx, index, level);
    end

    -- the hover: the rung's own rules first, then what is actually in it
    local lines = {
        ('Lv.%s -- the build for levels %s'):format(level, bandText(ctx, level)),
        ('%d point%s, %d slot%s'):format(cap or 0, (cap == 1) and '' or 's',
            slots, (slots == 1) and '' or 's'),
    };
    if src == 'base' then
        lines[2] = ('%d points (the base rule -- your learned bonus is not\n'
            .. 'measured yet, so the real total is higher), %d slots'):format(cap or 0, slots);
    elseif cap == nil then
        lines[2] = ('point total unknown, %d slots'):format(slots);
    end
    if n == 0 then
        lines[#lines + 1] = '';
        lines[#lines + 1] = 'Nothing built here yet -- click to start.';
    else
        local from = ctx.sets.usableFrom(ids, book);
        if from ~= nil and from > level then
            lines[#lines + 1] = ('complete from Lv.%d (its highest spell)'):format(from);
        end
        if over then
            lines[#lines + 1] = 'OVER what this level allows -- remove something.';
        end
        lines[#lines + 1] = '';
        for i = 1, 20 do
            local s = book.spells[ids[i] or 0];
            if s ~= nil then
                lines[#lines + 1] = ('  %s  (%d pts)'):format(s.name, s.setPoints or 0);
            elseif (ids[i] or 0) ~= 0 then
                lines[#lines + 1] = ('  #%d'):format(ids[i]);
            end
        end
    end
    kit.tip(im, table.concat(lines, '\n'));
end

-- WHAT THIS SET DOES WHEN YOUR LEVEL MOVES. A property of the SET (Henrik
-- 2026-08-07: "Level Change should NOT be a setting for a Level Set, it
-- should only be on a set") -- so it lives here beside the name, not in
-- the editor, which shows whichever build you happen to have open. The
-- wording is Henrik's, kept verbatim. Order is his too.
M.RULES = {
    { key = 'restore', label = 'Restore',
      tip = 'Will equip spells as spell slots and points\nbecome available.' },
    { key = 'switch',  label = 'Lvl Set Switch',
      tip = 'Will behave as Restore, unless you have added a\n'
         .. 'Level Set for the range your level is currently\n'
         .. 'set to.' },
    { key = 'manual',  label = 'Manual',
      tip = 'All changes must be manually applied.' },
};

local function ruleRow(ctx, entry)
    local im = ctx.im;
    local rule = ctx.sets.ruleOf(entry);
    local shown = M.RULES[1];
    for _, r in ipairs(M.RULES) do if r.key == rule then shown = r; end end
    local function pick(key)
        if key == rule then return; end
        ctx.sets.setRule(entry, key);
        if ctx.save then ctx.save(); end
        -- picking the level rule may put you on the right build right now,
        -- rather than at the next band change (bandSwitch stays silent when
        -- you are already wearing it)
        if key == 'switch' and ctx.armSwitch then ctx.armSwitch(); end
    end

    kit.helpLabel(im, 'Level change',
        'Here you can set how your set behaves during level ups.\n\n'
        .. 'Each set has its own, and the one that runs belongs to\n'
        .. 'the set you last applied.');
    local w = LEFT_W - 20;
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(w); end
    if kit.isFn(im, 'BeginCombo') and kit.isFn(im, 'EndCombo') and kit.isFn(im, 'Selectable') then
        local opened = false;
        pcall(function() opened = im.BeginCombo('##bdxlvlrule', kit.esc(shown.label)); end);
        if opened then
            for _, r in ipairs(M.RULES) do
                local okSel, hit = pcall(im.Selectable, kit.esc(r.label), r.key == rule);
                if okSel and hit then pick(r.key); end
                kit.tip(im, r.tip);              -- every choice explains itself
            end
            im.EndCombo();
        else
            kit.tip(im, shown.tip);
        end
    else
        -- no combo in this binding: the same three as a lit row
        local labels = {};
        for i, r in ipairs(M.RULES) do labels[i] = r.label; end
        local lvW = kit.measure(im, labels, 60);
        for i, r in ipairs(M.RULES) do
            if kit.litButton(im, r.label, r.key == rule, lvW, 20) then pick(r.key); end
            kit.tip(im, r.tip);
            if i < #M.RULES and kit.isFn(im, 'SameLine') then im.SameLine(); end
        end
    end

    -- ONE LINE ON WHY NOTHING HAPPENED. A rule that stays quiet looks the
    -- same whether the beat never reached it, it has no set to follow, or it
    -- simply had nothing to do -- so say which, where the eye is.
    if rule == 'manual' then return; end
    if ctx.watchAlive and ctx.watchAlive() == false then
        kit.ctext(im, kit.COL.err, 'The level watch is not running');
        kit.tip(im, 'This rule needs a per-frame beat that is not arriving, so\n'
            .. 'nothing will fire on a level change. In dlac the beat is gated\n'
            .. 'on its own activity check; reloading the addon re-subscribes it.');
        return;
    end
    local follow = ctx.cfg.lastAppliedSet;
    if follow == nil or follow == '' then
        kit.ctext(im, kit.COL.warn, 'Nothing applied yet');
        kit.tip(im, 'The rule runs for the set you last APPLIED, by name -- not\n'
            .. 'the one selected here. Apply one once and it takes over.');
    elseif follow ~= entry.name then
        kit.ctext(im, kit.COL.dim, ('"%s" is applied'):format(follow));
        kit.tip(im, ('The rule that runs right now is the one on "%s" -- the set\n'
            .. 'you last applied. This one takes over when you apply it.'):format(follow));
    else
        local hereRung = ctx.sets.rungFor(ctx.blu.effectiveLevel());
        kit.ctext(im, kit.COL.dim, ('Applied%s'):format(
            (hereRung ~= nil) and (' - Lv.' .. bandText(ctx, hereRung)) or ''));
        kit.tip(im, 'This set is the one being followed, and the band you are\n'
            .. 'standing in right now.');
    end
end

-- The Levels section under the name box, LEVELS sets only. Only the bands
-- actually ADDED are listed. A set opens with none; eight rows offered up
-- front read as eight things you are behind on.
local function levelsSection(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    local entry = st.activeSet and cfg.sets[st.activeSet] or nil;
    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.helpLabel(im, 'Levels',
        'Here you can add subsets for your set.\n'
        .. 'These subsets have designated level ranges, e.g., 31-40.\n'
        .. 'The set uses that subset at those levels, so it can adapt\n'
        .. 'perfectly as you level.\n\n'
        .. 'Where no level range is built, the BASE build (the set\'s\n'
        .. 'name row) answers instead.');
    if entry == nil then
        kit.ctext(im, kit.COL.dim, 'save the set first');
        return;
    end
    ctx.sets.normalizeGroup(entry);
    local here = ctx.sets.rungFor(ctx.blu.effectiveLevel());
    local levels = ctx.sets.groupLevels(entry);
    if #levels == 0 then
        kit.ctext(im, kit.COL.dim, 'none yet - only the base build');
    else
        kit.ctext(im, kit.COL.dim, '  Lv   points    slots');
        kit.tip(im, 'What each build costs against what its level allows.\n'
            .. '">" is the band you are standing in right now.');
        for _, lvl in ipairs(levels) do
            rungRow(ctx, st.activeSet, entry, lvl, here);
        end
    end

    -- add: only the bands this set does not have yet, plus all of them at once
    local free = ctx.sets.groupFree(entry);
    local rowW = kit.measure(im, { 'Remove' }, 66);
    if #free > 0 then
        local choices = {};
        for _, lvl in ipairs(free) do
            choices[#choices + 1] = ('Lv.%s'):format(bandText(ctx, lvl));
        end
        if #free > 1 then choices[#choices + 1] = 'All of them'; end
        st.addLevel = st.addLevel or {};
        if kit.combo(im, '##bdxaddlvl', st.addLevel, choices, 'Add a level',
                     LEFT_W - 24 - rowW) then
            local pickIdx = nil;
            for i, c in ipairs(choices) do if c == st.addLevel.value then pickIdx = i; end end
            st.addLevel.value = nil;                  -- back to the prompt
            if pickIdx == #choices and #free > 1 then
                for _, lvl in ipairs(free) do ctx.sets.groupAdd(entry, lvl); end
                st.applyNote = ('Added every level to "%s".'):format(entry.name);
                if ctx.save then ctx.save(); end
            elseif pickIdx ~= nil and free[pickIdx] ~= nil then
                local lvl = free[pickIdx];
                ctx.sets.groupAdd(entry, lvl);
                if ctx.save then ctx.save(); end
                loadBuild(ctx, st.activeSet, lvl);    -- open what you just made
                st.applyNote = ('Added Lv.%d. Build it, or copy one you have into it.'):format(lvl);
            end
        end
        kit.tip(im, 'Give this set a build of its own for one more level band.\n'
            .. 'It starts empty, and opens for editing straight away.');
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
    end
    -- remove: the band being edited, and only ever that one
    local editing = st.editingSet.draft and st.editingSet.level or nil;
    local canRemove = (editing ~= nil) and (ctx.sets.groupBuild(entry, editing) ~= nil);
    if kit.litButton(im, 'Remove', false, rowW, 20, canRemove and nil or kit.PAL.off)
        and canRemove then
        local n = ctx.sets.countIds(ctx.sets.groupIds(entry, editing));
        ctx.sets.groupRemove(entry, editing);
        if ctx.save then ctx.save(); end
        loadBuild(ctx, st.activeSet, nil);            -- back to the base build
        st.applyNote = (n > 0)
            and ('Removed the Lv.%d build and its %d spell%s.'):format(
                editing, n, (n == 1) and '' or 's')
            or ('Removed Lv.%d.'):format(editing);
    end
    kit.tip(im, canRemove
        and ('Take Lv.%d away from this set, spells and all.\n'
            .. 'The set falls back to its base build at those levels again.'):format(editing)
        or 'Open one of the levels above to remove it.');
end

local function savedList(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    kit.header(im, 'Saved sets');
    local now = os.clock();
    if now - badgeCache.at > 1.0 then
        badgeCache.at = now;
        badgeCache.viols = {};
        local budgetFn = M.budgetFn(ctx);
        for i, entry in ipairs(cfg.sets) do
            local v = ctx.sets.enforcedViolations(entry, ctx.book, budgetFn);
            if #v > 0 then badgeCache.viols[i] = v[1]; end
        end
    end
    if kit.isFn(im, 'Selectable') then
        -- THE KINDS STAY SEPARATE (Henrik 2026-08-10): flat sets under one
        -- heading, slotlists under another, so what you are working with is
        -- never a guess. Indices stay cfg.sets indices -- only the display
        -- is grouped.
        local anyFlat, anyTl = false, false;
        for _, e in ipairs(cfg.sets) do
            if ctx.sets.kindOf(e) == 'timeline' then anyTl = true;
            else anyFlat = true; end
        end
        local function setRow(i, entry)
            local kind = ctx.sets.kindOf(entry);
            local tag = tostring(ctx.sets.count(entry));
            if kind == 'levels' then
                local built = ctx.sets.groupLevels(entry);
                if #built > 0 then
                    tag = ('%d, %d level%s'):format(ctx.sets.countIds(entry.ids),
                        #built, (#built == 1) and '' or 's');
                else
                    tag = tostring(ctx.sets.countIds(entry.ids));
                end
            end
            local label = ('%s (%s)##bdxset%d'):format(entry.name, tag, i);
            local ok, clicked = pcall(im.Selectable, kit.esc(label), st.activeSet == i);
            local rclicked = false;
            if kit.isFn(im, 'IsItemClicked') then
                local okc, rc = pcall(im.IsItemClicked, 1);
                rclicked = okc and rc or false;
            end
            kit.tip(im, ('%s -- a %s set.\nLeft-click: edit it.\nRight-click: its backups.%s'):format(
                entry.name, M.KIND_INFO[kind].label,
                (kind == 'levels') and '\nIts level builds list under the name box.' or ''));
            if ok and clicked then
                if kind == 'levels' then
                    loadBuild(ctx, i, nil);        -- the row IS the base build
                else
                    st.activeSet = i;
                    st.editLevel = nil;
                    st.editingSet = ctx.sets.clone(entry, entry.name);
                    st.applyNote = nil;
                    st.assignSlot = nil;
                    cfg.activeSetName = entry.name;    -- remembered across loads
                    if ctx.save then ctx.save(); end
                end
            end
            if rclicked then
                st.backupsFor = (st.backupsFor == i) and nil or i;
            end
            -- the badge (plan 2.6): a saved set carrying an enforced band
            -- violation says so on its row; it saves fine, it cannot apply
            if badgeCache.viols[i] ~= nil then
                if kit.isFn(im, 'SameLine') then im.SameLine(); end
                kit.ctext(im, kit.COL.err, '!');
                kit.tip(im, ctx.sets.bandText(badgeCache.viols[i])
                    .. '.\nApply is blocked for this set until it fits its built-for range.');
            end
            -- the backup ring, inline under the row (no popup: the embedded
            -- Panel may not open windows)
            if st.backupsFor == i then
                local backups = entry.backups or {};
                if #backups == 0 then
                    kit.ctext(im, kit.COL.dim, '   no backups yet');
                end
                for bi, b in ipairs(backups) do
                    local when = ('backup %d'):format(bi);
                    pcall(function()
                        local d = os.date('%m-%d %H:%M', b.ts);
                        if type(d) == 'string' then when = d; end
                    end);
                    local blabel = ('   restore %s##bdxbak%d_%d'):format(when, i, bi);
                    local okb, bclick = pcall(im.Selectable, kit.esc(blabel), false);
                    kit.tip(im, 'Restore this backup. The current saved state is banked\nfirst, so a restore is itself undoable.');
                    if okb and bclick then
                        ctx.sets.restoreBackup(entry, bi, ctx.book, os.time());
                        -- a backup may be another KIND of this set (a
                        -- conversion banked it): the editor reloads on
                        -- whatever the restore made the entry
                        if st.activeSet == i then
                            if ctx.sets.kindOf(entry) == 'levels' then
                                st.editLevel = nil;
                                st.editingSet = ctx.sets.draft(entry, nil, ctx.book);
                            else
                                st.editingSet = ctx.sets.clone(entry, entry.name);
                            end
                            st.assignSlot = nil;
                        end
                        if ctx.save then ctx.save(); end
                        st.applyNote = 'Backup restored (the replaced state is now backup 1).';
                        st.backupsFor = nil;
                        break;                     -- the ring just changed
                    end
                end
            end
        end
        if anyFlat then
            if anyTl then kit.ctext(im, kit.COL.head, 'Flat sets'); end
            for i, entry in ipairs(cfg.sets) do
                if ctx.sets.kindOf(entry) ~= 'timeline' then setRow(i, entry); end
            end
        end
        if anyTl then
            if anyFlat then
                if kit.isFn(im, 'Separator') then im.Separator(); end
                kit.ctext(im, kit.COL.head, 'Slotlists');
            end
            for i, entry in ipairs(cfg.sets) do
                if ctx.sets.kindOf(entry) == 'timeline' then setRow(i, entry); end
            end
        end
    end
    if #cfg.sets == 0 then
        kit.ctext(im, kit.COL.dim, 'none yet');
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local rowW = kit.measure(im, { 'New', 'Save', 'Delete' }, 50);
    if kit.litButton(im, 'New', st.pickKind == true, rowW, 22) then
        -- the chooser takes over the middle column: a new set IS its kind
        -- from the first click (docs/set-types-plan.md 3)
        st.pickKind = not st.pickKind or nil;
        st.shareOpen, st.importOpen = nil, nil;
    end
    kit.tip(im, 'Start a new set. You pick which of the three kinds it is\n'
        .. '(Flat / Lvl Subsets / Slotlist) before anything is created.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Save', false, rowW, 22) then
        M.saveEditing(ctx);
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Delete', false, rowW, 22) then
        if st.activeSet and cfg.sets[st.activeSet] then
            table.remove(cfg.sets, st.activeSet);
            st.activeSet = nil;
            st.editLevel = nil;
            st.backupsFor = nil;
            cfg.activeSetName = '';
            if ctx.save then ctx.save(); end
            st.applyNote = 'Deleted.';
        end
    end

    -- ONE import door (Henrik 2026-08-10, from the field: two import
    -- buttons read as clutter): the pane behind it takes a pasted line
    -- AND carries the blusets file pull at its bottom
    if kit.litButton(im, 'Import', st.importOpen == true, LEFT_W - 20, 20) then
        st.importOpen = not st.importOpen or nil;
        st.shareOpen, st.pickKind, st.copyOpen = nil, nil, nil;
    end
    kit.tip(im, 'Paste a set someone sent you (a BDXSET1 line) and\n'
        .. 'save it as your own. Importing from the old blusets\n'
        .. 'addon\'s files lives in there too.');

    -- name box, with the set's kind beside the label -- the one fact about
    -- a set that never changes after the chooser
    local ekind = ctx.sets.kindOf(st.editingSet);
    kit.ctext(im, kit.COL.dim, 'Name');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.accent, ('  %s'):format(M.KIND_INFO[ekind].label));
    kit.tip(im, M.KIND_INFO[ekind].blurb
        .. '\n\nA set keeps its kind for life; New makes one of another kind.');
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(LEFT_W - 20); end
    if kit.isFn(im, 'InputText') then
        st.nameBuf[1] = st.editingSet.name;
        if pcall(im.InputText, '##bdxsetname', st.nameBuf, 48) then
            st.editingSet.name = st.nameBuf[1];
        end
    end

    -- COPY FROM ANOTHER SET (Henrik 2026-08-10, sixth round -- this took
    -- Convert's place): seed the build you are editing from one you already
    -- have. The source is read at its TOP LEVEL, which is the one reading
    -- that means the same thing whatever kind it came from; the spells
    -- cross, the per-level authorship does not, and the tooltip says so
    -- rather than letting it be discovered.
    local halfW = math.floor((LEFT_W - 24) / 2);
    if kit.litButton(im, 'Copy from...', st.copyOpen == true, halfW, 20) then
        st.copyOpen = not st.copyOpen or nil;
        st.copyConfirm = nil;
        st.shareOpen, st.importOpen = nil, nil;
    end
    kit.tip(im, 'Fill this build from another saved set - its top-level\n'
        .. 'spells, laid out the way THIS set\'s kind wants them.\n\n'
        .. 'It REPLACES what is here. Nothing is saved until you Save,\n'
        .. 'so Revert is always the way back.');
    local shareEntry = st.activeSet and cfg.sets[st.activeSet] or nil;
    if shareEntry ~= nil then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if kit.litButton(im, 'Share...', st.shareOpen == true, halfW, 20) then
            st.shareOpen = not st.shareOpen or nil;
            st.importOpen, st.pickKind, st.copyOpen = nil, nil, nil;
        end
        kit.tip(im, 'This set as one line of text -- send it to a friend,\nthey paste it under Import.');
    end
    if st.copyOpen then
        -- every saved set except the one being edited -- copying a set onto
        -- itself is the one move with nothing to offer
        local srcN = 0;
        for i, e in ipairs(cfg.sets) do
            if i ~= st.activeSet then
                srcN = srcN + 1;
                local n = ctx.sets.countIds(ctx.sets.resolveAtLevel(e, 75, ctx.book));
                local confirming = st.copyConfirm ~= nil and st.copyConfirm.i == i
                    and os.clock() < st.copyConfirm.till;
                if st.copyConfirm ~= nil and st.copyConfirm.i == i and not confirming then
                    st.copyConfirm = nil;              -- the 4s window closed
                end
                local label = confirming and 'Confirm copy?'
                    or ('%s  (%d)'):format(e.name, n);
                if kit.litButton(im, label, confirming, LEFT_W - 20, 20,
                    confirming and kit.PAL.go or nil) then
                    -- ONE CLICK into an empty build, TWO over a full one:
                    -- the same idiom Read current uses, for the same reason
                    if not confirming and ctx.sets.count(st.editingSet) > 0 then
                        st.copyConfirm = { i = i, till = os.clock() + 4.0 };
                    else
                        st.copyConfirm = nil;
                        local src = ctx.sets.resolveAtLevel(e, 75, ctx.book);
                        local rep = ctx.sets.copyFrom(st.editingSet, src, ctx.book);
                        st.assignSlot, st.slotEdit = nil, nil;
                        local parts = { ('Copied %d spell%s from "%s".'):format(
                            rep.taken, (rep.taken == 1) and '' or 's', e.name) };
                        if (rep.tooHigh or 0) > 0 then
                            parts[#parts + 1] = ('%d need a higher level than this build reaches.'):format(rep.tooHigh);
                        end
                        if (rep.noSlot or 0) > 0 then
                            parts[#parts + 1] = ('%d had no slot left.'):format(rep.noSlot);
                        end
                        if (rep.refused or 0) > 0 then
                            parts[#parts + 1] = ('%d could not be set (unlearned, or not settable).'):format(rep.refused);
                        end
                        parts[#parts + 1] = 'Save to keep it.';
                        st.applyNote = table.concat(parts, ' ');
                        st.copyOpen = nil;
                    end
                end
                kit.tip(im, ('Fill this build with the %d spell%s "%s" holds at\n'
                    .. 'Lv.75.%s%s'):format(n, (n == 1) and '' or 's', e.name,
                    (ctx.sets.kindOf(e) == 'timeline')
                        and '\n\nIts per-slot levels do NOT come along -- a flat reading\nis all one set can hand another.' or '',
                    (ctx.sets.count(st.editingSet) > 0)
                        and '\n\nThis build has spells in it: one click arms, a second copies.' or ''));
            end
        end
        if srcN == 0 then
            kit.wrapped(im, kit.COL.dim, 'No other saved set to copy from yet.');
        end
    end

    -- THE 'Built for Lv.' BOX IS GONE (Henrik 2026-08-10, sixth round: "it
    -- should always be built for 75"). It set where budget enforcement
    -- STARTS, and every set is enforced from 75 now -- setmodel.upgrade
    -- pins the field, which stays in the model and on the wire so shared
    -- and stored sets keep their shape.
    if ekind == 'levels' then
        -- everything else about the SET, in order: what it does on a level
        -- change, then the levels it has. Both belong to the set, not to
        -- the build open in the editor.
        local entry = st.activeSet and cfg.sets[st.activeSet] or nil;
        if entry ~= nil then ruleRow(ctx, entry); end
        levelsSection(ctx);
    end
end

-- ---------------------------------------------------------------------------
-- the middle column: the level slider and the bracket-grouped chain list
-- (the grid and the quick-add strip are GONE -- plan 2.15; cfg.setsLayout
-- is ignored). Slot numbers never show: the unlock bracket is the identity
-- that matters, and the engine re-sorts slots on every apply anyway.
-- ---------------------------------------------------------------------------

-- One slot's chain: the '+' assign target, the ACTIVE entry at the preview
-- level as a codex-grammar row (name + its level range + live tag), and
-- the rest of the timeline compact beneath -- retired dim, future blue.
local slotRowMenu;                     -- defined below, used by slotPlanner

local function chainRow(ctx, slot, shown, liveIds, locked, nameW)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    local chain = set.chains[slot];
    local floor = ctx.sets.bracketFloor(slot);
    local selected = st.assignSlot == slot;

    -- THE WHOLE ROW IS THE MARK (Henrik 2026-08-10, from the field: "remove
    -- the + ... just let me mark the whole slot"): clicking anywhere on the
    -- slot selects it as the Assign target; clicking again deselects.
    local function markSlot()
        if selected then
            st.assignSlot = nil;
        else
            st.assignSlot = slot;
            st.rightTab = 'Assign';
        end
    end

    if #chain == 0 then
        local elabel = (locked and ('(empty - opens at Lv.%d)'):format(floor) or '(empty)')
            .. ('##bdxslot%d'):format(slot);
        if tintedSelectable(im, kit.COL.dim, elabel, selected) then
            markSlot();
        end
        kit.tip(im, selected
            and 'This slot is the Assign target (right pane). Click to deselect.'
            or 'Click to mark this slot - the spell picker opens on the right.');
        return;
    end

    local activeIdx = nil;
    if not locked then
        for i, e in ipairs(chain) do
            if e.from <= shown then activeIdx = i; end
        end
    end

    if activeIdx == nil then
        local lo = ctx.sets.entryRange(set, slot, 1);
        local flabel = ('(first at Lv.%d)##bdxslot%d'):format(lo or floor, slot);
        if tintedSelectable(im, kit.COL.dim, flabel, selected) then
            markSlot();
        end
        kit.tip(im, 'Click to mark this slot for Assign.');
    else
        local e = chain[activeIdx];
        if e.id == 0 then
            local mlabel = ('(empty from Lv.%d)##bdxslot%d'):format(e.from, slot);
            if tintedSelectable(im, kit.COL.dim, mlabel, selected) then
                markSlot();
            end
            kit.tip(im, 'Click to mark this slot for Assign.');
        else
            local s = book.spells[e.id];
            local lo, hi = ctx.sets.entryRange(set, slot, activeIdx);
            -- SYNC-DISABLED IS GREY, NOT LABELLED (Henrik 2026-08-10, sixth
            -- round) -- the same law the flat list follows, and the row
            -- already carries the levels that explain it. Not waiting for an
            -- apply either: the game gives it back when the sync ends.
            local lvl = ctx.blu.effectiveLevel();
            local why = nil;
            if lvl ~= nil and lvl < 75 and s ~= nil
                and s.level ~= nil and s.level > lvl then
                why = ('Lv.%d cannot cast this - the sync disabled it, and\nthe game gives it back when the sync ends.'):format(lvl);
            end
            local pending = (why == nil) and liveIds ~= nil and not liveIds[e.id];
            local label = ((s ~= nil) and s.name or ('#' .. e.id))
                .. ('  %d-%d'):format(lo or floor, hi or 75)
                .. (pending and '  (not active yet)' or '');
            -- every row here is 'in the set', so the green tint says
            -- nothing -- head color instead, grey for what the level cannot
            -- give you, and unlearned stays loud over both
            local headCol = (why ~= nil) and kit.COL.dim or kit.COL.head;
            if ctx.blu.onBlu() and not book.learned(e.id) then headCol = kit.COL.err; end
            local lclick, rclick, hov = spellsui.listRow(ctx, e.id, 24, nameW,
                selected, true,
                { label = label, textCol = headCol, dimArt = why ~= nil });
            if lclick then
                -- the click MARKS the slot (Henrik 2026-08-10); the spell
                -- becomes the info target without forcing the window open
                markSlot();
                st.selectedId = e.id;
            end
            if rclick then
                -- the menu, not the axe (Henrik 2026-08-10): Edit slot or
                -- Remove -- falling back to the immediate remove only when
                -- this binding has no popups
                if kit.isFn(im, 'OpenPopup') and kit.isFn(im, 'BeginPopup') then
                    st.slotMenu = { slot = slot, idx = activeIdx, id = e.id };
                    pcall(im.OpenPopup, '##bdxslotrowmenu');
                else
                    local okR, whyR = ctx.sets.removeEntry(set, slot, activeIdx, book);
                    st.applyNote = okR and nil or ('Cannot remove: %s.'):format(whyR);
                    spellsui.tooltip(ctx, e.id, hov);
                    return;                        -- the chain just changed
                end
            end
            local extra = { { 'click: mark the slot for Assign - right-click: Edit slot / Remove', kit.COL.dim } };
            if why ~= nil then table.insert(extra, 1, { why, kit.COL.warn }); end
            spellsui.tooltip(ctx, e.id, hov, extra);
        end
    end

    -- the rest of the timeline, compact under the head
    for i, e in ipairs(chain) do
        if i ~= activeIdx then
            local lo, hi = ctx.sets.entryRange(set, slot, i);
            local nm = (e.id == 0) and 'empty'
                or ((book.spells[e.id] and book.spells[e.id].name) or ('#' .. e.id));
            local dead = (lo == nil or lo > hi);
            local future = (not dead) and lo > shown;
            local col = future and kit.COL.accent or kit.COL.dim;
            local text = dead and ('      (never)  %s'):format(nm)
                or ('      %d-%d  %s'):format(lo, hi, nm);
            if kit.isFn(im, 'Selectable') then
                local p2 = false;
                if kit.isFn(im, 'PushID') then
                    pcall(im.PushID, ('bdxsub%d_%d'):format(slot, i));
                    p2 = true;
                end
                local pcol = false;
                if kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
                    im.PushStyleColor(0, col);     -- Text
                    pcol = true;
                end
                local okS, sclick = pcall(im.Selectable, kit.esc(text), false);
                if pcol then im.PopStyleColor(1); end
                local rc = false;
                if kit.isFn(im, 'IsItemClicked') then
                    local okc, r = pcall(im.IsItemClicked, 1);
                    rc = okc and r or false;
                end
                if e.id ~= 0 then
                    spellsui.tooltip(ctx, e.id, nil,
                        { { 'right-click: remove this entry', kit.COL.dim } });
                else
                    kit.tip(im, 'The slot is deliberately empty over this range\n(the points go to other slots).\nright-click: remove the marker');
                end
                if p2 and kit.isFn(im, 'PopID') then pcall(im.PopID); end
                if okS and sclick and e.id ~= 0 then
                    st.selectedId = e.id;
                    st.detailOpen[1] = true;
                    st.detailFocus = true;
                end
                if rc then
                    local okR, whyR = ctx.sets.removeEntry(set, slot, i, book);
                    st.applyNote = okR and nil or ('Cannot remove: %s.'):format(whyR);
                    return;                        -- indices just shifted
                end
            else
                kit.ctext(im, col, text);
            end
        end
    end
end

local function slotPlanner(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    st.detailOpen = st.detailOpen or { false };
    st.preview = st.preview or {};

    -- the level slider: PREVIEW ONLY -- the plain Apply never reads it
    local liveLvl = ctx.blu.effectiveLevel();
    local shown = previewLevel(ctx);
    kit.ctext(im, kit.COL.head, 'Level');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local sbuf = { shown };
    if kit.sliderInt(im, '##bdxlevel', sbuf, 1, 75, math.max(120, MID_W - 170)) then
        st.preview.value = sbuf[1];
        shown = sbuf[1];
    end
    kit.tip(im, 'Preview the set at any level: the slot list, the meters and\n'
        .. 'the Stats pane all follow. Applying always uses your REAL\n'
        .. 'level -- except the explicit "Apply for Lv." button below.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Live', st.preview.value == nil,
        kit.measure(im, { 'Live' }, 40), 20) then
        st.preview.value = nil;
        shown = previewLevel(ctx);
    end
    kit.tip(im, 'Follow your real level (75 while off BLU).');
    if liveLvl ~= nil and shown ~= liveLvl then
        kit.ctext(im, kit.COL.warn, ('previewing Lv.%d - live Lv.%d'):format(shown, liveLvl));
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    -- meters at the PREVIEW level. At the live level the client-preferred
    -- budget applies (ctx.budgetMax); elsewhere only the model can answer.
    -- METERS AND ACTIONS SIT ABOVE THE LIST (Henrik 2026-08-10, from the
    -- field): the slot list runs twenty rows deep, and Apply must not
    -- live at the bottom of it.
    local ids = ctx.sets.resolveAtLevel(set, shown, book);
    local capShown;
    if liveLvl ~= nil and shown == liveLvl then
        capShown = ctx.budgetMax();
    else
        capShown = M.budgetFn(ctx)(shown);
    end
    -- the LIVE reading rides in brackets rather than on its own line (Henrik
    -- 2026-08-10, sixth round) -- and only while it says something the plan
    -- does not: previewing the very level you stand at, the two agree.
    local ss = ctx.blu.syncStats(book);
    local synced = (ss ~= nil and ss.level < 75 and ss.level ~= shown) and ss or nil;
    kit.meter(im, ('Points Lv.%d'):format(shown), ctx.sets.usedPoints(ids, book), capShown, '',
        synced and synced.activePoints or nil, synced and ctx.blu.budget() or nil);
    kit.tip(im, (capShown == nil
        and 'The budget for this level is not known yet (learned bonus\nunmeasured). Bands below are provisional meanwhile.'
        or ('The plan at Lv.%d against that level\'s budget.'):format(shown))
        .. (synced and ('\n\nIn brackets: what the game holds RIGHT NOW at Lv.%d.'):format(synced.level) or ''));
    local activeN = 0;
    for i = 1, 20 do if (ids[i] or 0) ~= 0 then activeN = activeN + 1; end end
    kit.meter(im, 'Slots ', activeN, ctx.sets.slotsAtLevel(shown), '',
        synced and synced.active or nil, synced and synced.maxSlots or nil);
    kit.ctext(im, kit.COL.dim, ('Total MP %d'):format(ctx.sets.usedMP(ids, book)));

    -- the whole-curve verdict (plan 2.6): red = enforced and real (Apply
    -- blocked), orange = enforced but provisional, grey = below builtFor
    local bands = ctx.sets.bandViolations(set, book, M.budgetFn(ctx));
    for bi, b in ipairs(bands) do
        if bi > 4 then
            kit.ctext(im, kit.COL.dim, ('  ...and %d more band(s)'):format(#bands - 4));
            break;
        end
        local col = (b.enforced and not b.provisional) and kit.COL.err
            or (b.enforced and kit.COL.warn or kit.COL.dim);
        kit.ctext(im, col, '  ' .. ctx.sets.bandText(b));
    end

    -- game actions (widths measured -- the clipping law)
    if kit.isFn(im, 'Separator') then im.Separator(); end
    local astate = M.applyState(ctx);
    local applyW = kit.measure(im, { 'Apply in game', 'Applying...' }, 100);
    local readW  = kit.measure(im, { 'Read current', 'Confirm read?' }, 90);
    local clearW = kit.measure(im, { 'Clear' }, 50);
    local pal = nil;
    if not ctx.blu.applying then
        if astate == 'dirty' then pal = kit.PAL.go;
        elseif astate ~= nil then pal = kit.PAL.off; end
    end
    if kit.litButton(im, ctx.blu.applying and 'Applying...' or 'Apply in game', false, applyW, 26, pal) then
        if astate == 'clean' then
            st.applyNote = 'Already up to date - nothing to apply.';
        else
            M.applyEditing(ctx);
        end
    end
    kit.tip(im, astate == 'planned'
        and 'The live set matches a plan you applied for another level.\nClicking applies the plan for your CURRENT level instead.'
        or 'Send the plan for your REAL level - only the changed slots.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    -- Read current: TWO clicks (plan 2.11 -- too easy to overwrite), and
    -- the replaced chains are banked as a backup first
    local confirming = st.readConfirm ~= nil and os.clock() < st.readConfirm;
    if not confirming then st.readConfirm = nil; end
    if kit.litButton(im, confirming and 'Confirm read?' or 'Read current', false, readW, 26,
        confirming and kit.PAL.go or nil) then
        if not confirming then
            st.readConfirm = os.clock() + 4.0;
        else
            st.readConfirm = nil;
            local liveNow = ctx.blu.currentSet();
            if #liveNow == 20 then
                ctx.sets.pushBackup(set, set, os.time());
                set.chains = ctx.sets.buildChains(liveNow, book);
                ctx.sets.syncLegacyIds(set, book);
                local unknown = 0;
                for i = 1, 20 do
                    if liveNow[i] ~= 0 and book.spells[liveNow[i]] == nil then
                        unknown = unknown + 1;
                    end
                end
                -- unknown ids are kept (honest mirror of the client) -- the
                -- rows draw them as '#id' and the totals simply skip them
                st.applyNote = unknown == 0
                    and 'Read the live set - the old chains are backup 1.'
                    or ('Read the live set (old chains backed up); %d slot(s) hold ids the data does not know.'):format(unknown);
            else
                st.applyNote = 'Could not read the live set.';
            end
        end
    end
    kit.tip(im, confirming
        and 'Click again to REPLACE the editing set with what the game\nholds (flat - the game knows nothing of chains). The current\nchains are banked as a backup first.'
        or 'Copy the in-game set here. Takes TWO clicks, because it\nreplaces your chains (a backup is banked first).');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Clear', false, clearW, 26) then
        ctx.sets.clear(st.editingSet);
        st.applyNote = nil;
    end

    -- the preemptive apply (plan 2.9): only offered while previewing away
    -- from the live level, and never bearing the plain Apply's label
    if liveLvl ~= nil and shown ~= liveLvl and not ctx.blu.applying then
        local aflLbl = ('Apply for Lv.%d'):format(shown);
        local aflW = kit.measure(im, { aflLbl }, 110);
        if kit.litButton(im, aflLbl, false, aflW, 24, kit.PAL.go) then
            M.applyEditing(ctx, shown);
        end
        kit.tip(im, ('Send the plan for Lv.%d NOW, at Lv.%d -- eat the 60s cast\n'
            .. 'lock before a level sync instead of during it. The header\n'
            .. 'then reads "matches your Lv.%d plan" instead of glowing.')
            :format(shown, liveLvl, shown));
    end
    if not ctx.blu.onBlu() then
        kit.ctext(im, kit.COL.warn, 'BLU is not your main or sub job.');
    end
    if st.applyNote then kit.wrapped(im, kit.COL.dim, st.applyNote); end

    -- level-change behavior (plan 2.7-2.8): the timeline may plan different
    -- spells for a new level; auto applies by itself, manual nudges
    -- the naming law: name the rule for its condition, never 'Auto <thing>'
    kit.ctext(im, kit.COL.dim, 'Level change:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local lvW = kit.measure(im, { 'Auto-apply', 'Manual' }, 64);
    local auto = ctx.cfg.replan == 'auto';
    if kit.litButton(im, 'Auto-apply', auto, lvW, 20) and not auto then
        ctx.cfg.replan = 'auto';
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'After a level change (up, down, or a sync), the plan for the\n'
        .. 'new level is applied by itself once the level settles. THIS MAY\n'
        .. 'UNSET SPELLS - the timeline replaces as you level. Stays quiet\n'
        .. 'when the change would only remove (the game\'s own disable\n'
        .. 'already covers that). Every change costs the 60s cast lock.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Manual', not auto, lvW, 20) and auto then
        ctx.cfg.replan = 'manual';
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'Nothing applies by itself. A note in the header, a small\n'
        .. 'float window while Bludex is closed, and one chat line -\n'
        .. 'you click Apply when it suits.');

    -- the slot list, below everything that describes and acts on it
    if kit.isFn(im, 'Separator') then im.Separator(); end
    -- what the CLIENT has set right now, for the per-row live tags
    local liveIds = nil;
    local live = ctx.blu.currentSet();
    if #live == 20 then
        liveIds = {};
        for i = 1, 20 do if live[i] ~= 0 then liveIds[live[i]] = true; end end
    end
    local nameW = math.max(kit.availWidth(im, MID_W) - 78, 120);
    for _, g in ipairs(ctx.sets.brackets()) do
        local locked = shown < g.floor;
        kit.ctext(im, locked and kit.COL.dim or kit.COL.head,
            ('Lv.%d-%d'):format(g.floor, bracketTop(g.floor)));
        if locked then
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            kit.ctext(im, kit.COL.dim, '  (locked at this level)');
        end
        for _, slot in ipairs(g.slots) do
            chainRow(ctx, slot, shown, liveIds, locked, nameW);
        end
    end
    slotRowMenu(ctx);
end

-- ---------------------------------------------------------------------------
-- THE KIND CHOOSER -- what New opens (docs/set-types-plan.md 3): three
-- rows, each a kind and its recommendation, cfg.newSetKind listed first
-- and lit. Nothing exists until a kind is clicked; Cancel walks away.
-- ---------------------------------------------------------------------------
local function kindChooser(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    kit.header(im, 'New set - what kind?');
    -- WRAPPED, never clipped (Henrik 2026-08-10, from the field: the blurb
    -- lines ran off the column edge)
    kit.wrapped(im, kit.COL.dim, 'The kind decides how the set thinks about levels. It is chosen once, here.');
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local order = {};
    local first = cfg.newSetKind;
    if M.KIND_INFO[first] ~= nil then order[1] = first; end
    for _, k in ipairs(M.KIND_ORDER) do
        if k ~= first then order[#order + 1] = k; end
    end

    local w = math.max(140, kit.availWidth(im, MID_W) - 16);
    for _, k in ipairs(order) do
        local info = M.KIND_INFO[k];
        local isDefault = (k == cfg.newSetKind);
        if kit.litButton(im, info.label .. (isDefault and '  (your default)' or ''),
            isDefault, w, 26) then
            st.editingSet = ctx.sets.new(('Set %d'):format(#cfg.sets + 1), k);
            st.activeSet = nil;
            st.editLevel = nil;
            st.assignSlot = nil;
            st.applyNote = nil;
            st.pickKind = nil;
        end
        kit.tip(im, info.blurb);
        kit.wrapped(im, kit.COL.dim, (info.blurb:gsub('\n', ' ')));
        if kit.isFn(im, 'NewLine') then im.NewLine(); end
    end

    if kit.litButton(im, 'Cancel', false, kit.measure(im, { 'Cancel' }, 60), 22) then
        st.pickKind = nil;
    end
    kit.wrapped(im, kit.COL.dim, 'Which kind is offered first lives in Settings - "New sets start as".');
end

-- ---------------------------------------------------------------------------
-- the middle column, FLAT flavor -- flat sets and levels drafts: the
-- id-array editor (codex-grammar rows, right-click removes), its meters,
-- and the game actions. The timeline keeps slotPlanner below.
-- ---------------------------------------------------------------------------
local function flatPlanner(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    st.detailOpen = st.detailOpen or { false };
    local slotMax = ctx.sets.slotMax(set);

    -- WHICH BUILD this is (levels drafts only). The set name lives in the
    -- box on the left; this is the one thing that changes what the editor
    -- allows.
    if set.draft then
        kit.ctext(im, kit.COL.head, (set.level == nil)
            and 'Editing the base build'
            or ('Editing Lv.%d - levels %s'):format(set.level, bandText(ctx, set.level)));
        kit.tip(im, (set.level == nil)
            and 'The build the set falls back to wherever no level range\nis built. The set\'s level builds list under its name.'
            or ('The game gives the same %d slots and the same points\n'
                .. 'anywhere in Lv.%s, so one build serves the whole band.\n\n'
                .. 'Other levels of this set are under its name on the left.'):format(
                slotMax, bandText(ctx, set.level)));
        if kit.isFn(im, 'Separator') then im.Separator(); end
    end

    -- Copy from: an EMPTY band offers its neighbors (base, nearest below,
    -- nearest above) as one-click sources -- the 2026-08-06 workflow
    if set.draft and set.level ~= nil and ctx.sets.count(set) == 0 then
        local entry = st.activeSet and ctx.cfg.sets[st.activeSet] or nil;
        if entry ~= nil then
            local srcs = {};
            if ctx.sets.countIds(entry.ids) > 0 then
                srcs[#srcs + 1] = { level = nil, label = 'the base' };
            end
            local below, above = nil, nil;
            for _, lvl in ipairs(ctx.sets.groupLevels(entry)) do
                if ctx.sets.countIds(ctx.sets.groupIds(entry, lvl)) > 0 then
                    if lvl < set.level then below = lvl;
                    elseif lvl > set.level and above == nil then above = lvl; end
                end
            end
            if below ~= nil then srcs[#srcs + 1] = { level = below, label = ('Lv.%d'):format(below) }; end
            if above ~= nil then srcs[#srcs + 1] = { level = above, label = ('Lv.%d'):format(above) }; end
            if #srcs > 0 then
                kit.ctext(im, kit.COL.dim, 'Copy from:');
                for _, src in ipairs(srcs) do
                    if kit.isFn(im, 'SameLine') then im.SameLine(); end
                    local w = kit.measure(im, { src.label }, 44);
                    if kit.litButton(im, src.label, false, w, 18) then
                        local from = ctx.sets.groupIds(entry, src.level);
                        local ids, rep = ctx.sets.copyInto(from, set.level, ctx.book);
                        for i = 1, 20 do set.ids[i] = ids[i]; end
                        local parts = { ('Copied %d spell%s from %s.'):format(
                            rep.taken, (rep.taken == 1) and '' or 's', src.label) };
                        if rep.tooHigh > 0 then
                            parts[#parts + 1] = ('%d need%s a higher level than Lv.%s reaches.'):format(
                                rep.tooHigh, (rep.tooHigh == 1) and 's' or '', bandText(ctx, set.level));
                        end
                        if rep.noSlot > 0 then
                            parts[#parts + 1] = ('%d had no slot (Lv.%d has %d).'):format(
                                rep.noSlot, set.level, slotMax);
                        end
                        st.applyNote = table.concat(parts, ' ');
                    end
                    kit.tip(im, ('Fill this build from %s: lowest spell levels first,\n'
                        .. 'only what Lv.%s can cast, only as many as its %d slots\n'
                        .. 'hold. It can land OVER the point budget -- that is yours\n'
                        .. 'to trim, not mine to guess at.'):format(
                        src.label, bandText(ctx, set.level), slotMax));
                end
                if kit.isFn(im, 'Separator') then im.Separator(); end
            end
        end
    end

    -- meters: the BUILD against ITS OWN allowance -- a Lv.41 draft against
    -- the Lv.41 budget and slots, everything else against the live budget.
    -- METERS AND ACTIONS SIT ABOVE THE LIST (Henrik 2026-08-10, from the
    -- field), same as the slotlist editor.
    local cap, src;
    if set.draft and set.level ~= nil then
        cap, src = rungBudget(ctx, set.level);
    else
        cap = ctx.budgetMax();
    end
    local capShown = cap;
    if src == 'base' then capShown = nil; end      -- a floor is not a total
    kit.meter(im, 'Points', ctx.sets.usedPoints(set, book), capShown, '');
    if src == 'base' then
        kit.tip(im, ('At least %d (the base rule) - your learned bonus is not\nmeasured yet, so the real total is higher.'):format(cap or 0));
    end
    kit.meter(im, 'Slots ', ctx.sets.count(set), slotMax, '');
    kit.ctext(im, kit.COL.dim, ('Total MP %d'):format(ctx.sets.usedMP(set, book)));

    -- game actions (widths measured -- the clipping law)
    if kit.isFn(im, 'Separator') then im.Separator(); end
    local astate = M.applyState(ctx);
    local applyW = kit.measure(im, { 'Apply in game', 'Applying...' }, 100);
    local readW  = kit.measure(im, { 'Read current', 'Confirm read?' }, 90);
    local clearW = kit.measure(im, { 'Clear' }, 50);
    local pal = nil;
    if not ctx.blu.applying then
        if astate == 'dirty' then pal = kit.PAL.go;
        elseif astate ~= nil then pal = kit.PAL.off; end
    end
    if kit.litButton(im, ctx.blu.applying and 'Applying...' or 'Apply in game', false, applyW, 26, pal) then
        if astate == 'clean' then
            st.applyNote = 'Already up to date - nothing to apply.';
        else
            M.applyEditing(ctx);
        end
    end
    kit.tip(im, set.draft and (set.level == nil
            and 'Send the base build - only the changed slots.'
            or ('Send this Lv.%d build - only the changed slots.'):format(set.level))
        or 'Send this set - only the changed slots.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    -- Read current: TWO clicks (plan 2.11 -- too easy to overwrite)
    local confirming = st.readConfirm ~= nil and os.clock() < st.readConfirm;
    if not confirming then st.readConfirm = nil; end
    if kit.litButton(im, confirming and 'Confirm read?' or 'Read current', false, readW, 26,
        confirming and kit.PAL.go or nil) then
        if not confirming then
            st.readConfirm = os.clock() + 4.0;
        else
            st.readConfirm = nil;
            local liveNow = ctx.blu.currentSet();
            if #liveNow == 20 then
                for i = 1, 20 do set.ids[i] = liveNow[i] or 0; end
                -- into the flat set's own order -- the game's slot numbers
                -- are not authorship here, and Apply would re-sort anyway.
                -- Nothing is dropped: ids the data does not know sort last.
                ctx.sets.sortFlat(set, book);
                local unknown = 0;
                for i = 1, 20 do
                    if liveNow[i] ~= 0 and book.spells[liveNow[i]] == nil then
                        unknown = unknown + 1;
                    end
                end
                st.applyNote = unknown == 0
                    and 'Read the live set.'
                    or ('Read the live set; %d slot(s) hold ids the data does not know.'):format(unknown);
            else
                st.applyNote = 'Could not read the live set.';
            end
        end
    end
    kit.tip(im, confirming
        and 'Click again to REPLACE this build with what the game holds.'
        or 'Copy the in-game set here. Takes TWO clicks, because it\nreplaces this build.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Clear', false, clearW, 26) then
        ctx.sets.clear(st.editingSet);
        st.applyNote = nil;
    end

    if not ctx.blu.onBlu() then
        kit.ctext(im, kit.COL.warn, 'BLU is not your main or sub job.');
    end
    if st.applyNote then kit.wrapped(im, kit.COL.dim, st.applyNote); end

    -- the spell list, below everything that describes and acts on it
    if kit.isFn(im, 'Separator') then im.Separator(); end
    -- what the CLIENT has set right now, for the per-row live tags
    local liveIds = nil;
    local live = ctx.blu.currentSet();
    if #live == 20 then
        liveIds = {};
        for i = 1, 20 do if live[i] ~= 0 then liveIds[live[i]] = true; end end
    end
    -- EVERY SLOT THE GAME HAS, grouped by the level it opens at -- the same
    -- list shape the slotlist editor draws (Henrik 2026-08-10, fifth round:
    -- "for Normal sets, add similar list as in slotlist"). It reads as the
    -- LEVEL-SYNC ORDER: the spells sit lowest-level-first (setmodel.sortFlat
    -- keeps the array that way, and that is exactly what Apply sends), and
    -- a sync closes slots from the bottom of this list upward.
    kit.ctext(im, kit.COL.head, 'Slots');
    kit.tip(im, 'Every slot, grouped by the level it opens at.\n\n'
        .. 'The spells sit in LEVEL ORDER, lowest first -- which is the order\n'
        .. 'Apply sends them, so reading up from the bottom is the order a\n'
        .. 'level sync takes them away in.\n\n'
        .. 'A row your level cannot give you yet is GREYED, never barred:\n'
        .. 'its own Lv. says why, and it edits like any other.\n\n'
        .. 'Left-click a row for Spell Info, right-click removes it.');
    if ctx.sets.count(set) == 0 then
        kit.wrapped(im, kit.COL.dim, 'The set is empty - add spells from the Codex or Traits.');
    end
    local nameW = math.max(kit.availWidth(im, MID_W) - 78, 120);
    local lvl = ctx.blu.effectiveLevel();
    -- WHICH LEVEL GRADES THE SLOTS: a band draft is built for its own band
    -- and is graded there whatever you happen to be right now; everything
    -- else is graded at the level you are actually at.
    local gradeLvl = (set.draft and set.level ~= nil) and set.level or (lvl or 75);
    -- a band build is graded for its WHOLE band -- Lv.41-50 has the same 14
    -- slots at either end, so naming one level of it would read as a limit
    -- that lifts halfway through
    local gradeText = (set.draft and set.level ~= nil)
        and ('Lv.%s'):format(bandText(ctx, set.level))
        or ('Lv.%d'):format(gradeLvl);
    for _, g in ipairs(ctx.sets.brackets()) do
        local locked = gradeLvl < g.floor;
        kit.ctext(im, locked and kit.COL.dim or kit.COL.head,
            ('Lv.%d-%d'):format(g.floor, bracketTop(g.floor)));
        if locked then
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            kit.ctext(im, kit.COL.dim, ('  (no slots here at %s)'):format(gradeText));
        end
        for _, i in ipairs(g.slots) do
            local id = set.ids[i] or 0;
            if id == 0 then
                kit.ctext(im, kit.COL.dim, locked
                    and ('   (opens at Lv.%d)'):format(g.floor)
                    or '   (empty)');
            else
                local s = book.spells[id];
                -- WHAT YOUR LEVEL CANNOT GIVE YOU IS GREY, NOT LABELLED
                -- (Henrik 2026-08-10, sixth round: "instead of saying on
                -- every slot (disabled by) or (no slot until), maybe we
                -- should just grey it out... we already provide the levels
                -- on the slots"). Two reasons, one look: the slot is past
                -- the level's bracket, or the spell is over the sync
                -- ceiling. Neither is WAITING for an apply -- the game
                -- returns them when the sync ends -- and neither stops you
                -- editing the row. The reason still lives in the tooltip,
                -- where it costs no space.
                local why = nil;
                if lvl ~= nil and lvl < g.floor then
                    why = ('Lv.%d has no slot this deep - it opens at Lv.%d.'):format(
                        lvl, g.floor);
                elseif lvl ~= nil and lvl < 75 and s ~= nil
                    and s.level ~= nil and s.level > lvl then
                    why = ('Lv.%d cannot cast this - the sync disabled it, and\nthe game gives it back when the sync ends.'):format(lvl);
                end
                -- 'not active yet' is a DIFFERENT thing and keeps its words:
                -- the game could hold this and does not, so Apply is the fix
                local pending = (why == nil) and liveIds ~= nil and not liveIds[id];
                local label = ('%s  Lv.%s%s'):format(
                    (s ~= nil) and s.name or ('#' .. id),
                    (s ~= nil) and (s.level or '?') or '?',
                    pending and '  (not active yet)' or '');
                -- every row here is in the set, so the green tint says
                -- nothing: head normally, grey for out of reach, and
                -- unlearned still wins outright (Apply drops it entirely)
                local rowCol = (why ~= nil) and kit.COL.dim or kit.COL.head;
                if ctx.blu.onBlu() and not book.learned(id) then rowCol = kit.COL.err; end
                local lclick, rclick, hov = spellsui.listRow(ctx, id, 24, nameW,
                    st.selectedId == id, true,
                    { label = label, textCol = rowCol, dimArt = why ~= nil });
                if lclick then
                    st.selectedId = id;
                    st.detailOpen[1] = true;
                    st.detailFocus = true;
                end
                if rclick then
                    ctx.sets.removeSlot(set, i);
                    st.applyNote = nil;
                    return;                    -- the rows just shifted down
                end
                local extra = { { 'right-click: remove from the set', kit.COL.dim } };
                if why ~= nil then
                    table.insert(extra, 1, { why, kit.COL.warn });
                end
                spellsui.tooltip(ctx, id, hov, extra);
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- SHARE / IMPORT FROM TEXT (docs/set-types-plan.md 8) -- the dlac
-- friend-share flow, one set at a time: Share shows the line and copies
-- it; Import parses a paste LIVE and says what it recognized before
-- anything is created. Both take the middle column, like the chooser.
-- ---------------------------------------------------------------------------
local function sharePane(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    local entry = st.activeSet and cfg.sets[st.activeSet] or nil;
    if entry == nil then st.shareOpen = nil; return; end
    kit.header(im, ('Share "%s"'):format(entry.name));
    -- WRAPPED, never clipped (Henrik 2026-08-10, from the field: the
    -- guidance lines ran off the column edge)
    kit.wrapped(im, kit.COL.dim, 'One line, sent whole: chat, Discord, anywhere. '
        .. 'The other side pastes it under Import. '
        .. 'Backups stay home - the text is the set, not its history.');
    if M.unsaved(ctx) then
        kit.wrapped(im, kit.COL.warn, 'Unsaved edits are NOT in this text - Save to include them.');
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end
    local text = ctx.sets.shareText(entry);
    -- a copy SOURCE, rebuilt every frame -- not an editor. The pane owns
    -- the whole width while it is open (the render drops the right panel),
    -- so the box gets room to show a real stretch of the line.
    local boxW = kit.availWidth(im, MID_W) - 8;
    if kit.isFn(im, 'InputTextMultiline') then
        pcall(im.InputTextMultiline, '##bdxsharetext', { text }, #text + 8, { boxW, 110 });
    elseif kit.isFn(im, 'InputText') then
        if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(boxW); end
        pcall(im.InputText, '##bdxsharetext', { text }, #text + 8);
    else
        kit.wrapped(im, kit.COL.dim, text);
    end
    if kit.isFn(im, 'SetClipboardText') then
        if kit.litButton(im, 'Copy to clipboard', false,
            kit.measure(im, { 'Copy to clipboard' }, 120), 24) then
            pcall(im.SetClipboardText, text);
            st.applyNote = ('Copied "%s" to the clipboard - paste it to your friend.'):format(entry.name);
        end
        kit.tip(im, 'The whole line, one click.');
    else
        kit.ctext(im, kit.COL.dim, '(no clipboard in this binding - select the text and Ctrl+C)');
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Back', false, kit.measure(im, { 'Back' }, 50), 24) then
        st.shareOpen = nil;
    end
    if st.applyNote then kit.wrapped(im, kit.COL.dim, st.applyNote); end
end

local function importPane(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    kit.header(im, 'Import');
    kit.wrapped(im, kit.COL.dim, 'Paste the whole BDXSET1 line someone sent you. '
        .. 'Chat framing around it is fine - the line is found inside.');
    if kit.isFn(im, 'Separator') then im.Separator(); end
    st.importBuf = st.importBuf or { '' };
    local boxW = kit.availWidth(im, MID_W) - 8;
    if kit.isFn(im, 'InputTextMultiline') then
        pcall(im.InputTextMultiline, '##bdximporttext', st.importBuf, 16384, { boxW, 70 });
    elseif kit.isFn(im, 'InputText') then
        if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(boxW); end
        pcall(im.InputText, '##bdximporttext', st.importBuf, 16384);
    end
    -- parsed LIVE, dlac-style: the moment the paste lands, it is named --
    -- or refused with a reason a person can act on
    local cur = st.importBuf[1] or '';
    if st.importLen ~= #cur then
        st.importLen = #cur;
        st.importSet, st.importWhy = nil, nil;
        if cur ~= '' then
            st.importSet, st.importWhy = ctx.sets.parseShare(cur);
        end
    end
    if st.importSet ~= nil then
        local inc = st.importSet;
        local kind = ctx.sets.kindOf(inc);
        local extra = '';
        if kind == 'levels' and #(inc.builds or {}) > 0 then
            extra = (', %d level build%s'):format(#inc.builds,
                (#inc.builds == 1) and '' or 's');
        elseif kind == 'timeline' then
            extra = (', built for Lv.%d'):format(inc.builtFor or 75);
        end
        kit.wrapped(im, kit.COL.ok, ('Recognized: "%s" - a %s set, %d spell%s%s.'):format(
            inc.name, M.KIND_INFO[kind].label, ctx.sets.count(inc),
            (ctx.sets.count(inc) == 1) and '' or 's', extra));
        -- a name collision imports under a numbered name, never clobbers
        local final = inc.name;
        local n = 2;
        local function taken(want)
            for _, e in ipairs(cfg.sets) do
                if ctx.book.norm(e.name) == ctx.book.norm(want) then return true; end
            end
            return false;
        end
        while taken(final) do
            final = ('%s (%d)'):format(inc.name, n);
            n = n + 1;
        end
        if final ~= inc.name then
            kit.wrapped(im, kit.COL.warn, ('The name is taken - it will import as "%s".'):format(final));
        end
        if kit.litButton(im, 'Import', false, kit.measure(im, { 'Import' }, 70), 24, kit.PAL.go) then
            local entry = ctx.sets.clone(inc, final);
            ctx.sets.upgrade(entry, ctx.book);
            table.insert(cfg.sets, entry);
            st.activeSet = #cfg.sets;
            if ctx.sets.kindOf(entry) == 'levels' then
                st.editLevel = nil;
                st.editingSet = ctx.sets.draft(entry, nil, ctx.book);
            else
                st.editLevel = nil;
                st.editingSet = ctx.sets.clone(entry, entry.name);
            end
            st.assignSlot = nil;
            cfg.activeSetName = entry.name;
            if ctx.save then ctx.save(); end
            st.importOpen = nil;
            st.importBuf, st.importLen, st.importSet = nil, nil, nil;
            st.applyNote = ('Imported "%s" - a %s set.'):format(
                entry.name, M.KIND_INFO[ctx.sets.kindOf(entry)].label);
        end
        kit.tip(im, 'Saves it as your own set and opens it for editing.');
    elseif st.importWhy ~= nil then
        kit.wrapped(im, kit.COL.warn, st.importWhy);
    end
    if kit.isFn(im, 'SameLine') and st.importSet ~= nil then im.SameLine(); end
    if kit.litButton(im, 'Back', false, kit.measure(im, { 'Back' }, 50), 24) then
        st.importOpen = nil;
    end

    -- the OTHER import, tucked in here rather than crowding the left
    -- column (Henrik 2026-08-10): the one-way pull from the old blusets
    -- addon's saved lists; existing bludex names are skipped, never
    -- overwritten -- safe to click repeatedly
    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.wrapped(im, kit.COL.dim, 'Coming from the blusets addon instead? Its saved '
        .. 'spell lists (config/addons/blusets/*.txt) import in one click:');
    if kit.litButton(im, 'Import blusets files', false,
        kit.measure(im, { 'Import blusets files' }, 130), 22) then
        local res = blusetsimport.importAll(cfg, ctx.book);
        if #res.imported > 0 and ctx.save then ctx.save(); end
        st.applyNote = blusetsimport.describe(res);
    end
    kit.tip(im, 'Every blusets list becomes a bludex saved set.\nA set name that already exists here is skipped.');
    if st.applyNote then kit.wrapped(im, kit.COL.dim, st.applyNote); end
end

-- the middle column, dispatched: the chooser while New is deciding, the
-- share/import panes while one is open, then the editor the editing set's
-- kind calls for
local function midColumn(ctx)
    local st = ctx.state;
    if st.pickKind then
        kindChooser(ctx);
        return;
    end
    if st.shareOpen then
        sharePane(ctx);
        return;
    end
    if st.importOpen then
        importPane(ctx);
        return;
    end
    if ctx.sets.kindOf(st.editingSet) == 'timeline' then
        slotPlanner(ctx);
    else
        flatPlanner(ctx);
    end
end

-- ---------------------------------------------------------------------------
-- the right column: Stats (default) | Assign (the picker for one slot)
-- ---------------------------------------------------------------------------
local function statsPanel(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local shown = previewLevel(ctx);
    local ids = ctx.sets.resolveAtLevel(st.editingSet, shown, book);
    kit.header(im, ('Set stats - Lv.%d'):format(shown));
    local stats = ctx.sets.stats(ids, book);
    if #stats == 0 then
        kit.ctext(im, kit.COL.dim, 'no stat bonuses at this level');
    else
        for _, e in ipairs(stats) do
            kit.ctext(im, e.value >= 0 and kit.COL.ok or kit.COL.err,
                ('%s %+d'):format(ctx.sets.prettyStat(e.stat), e.value));
        end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.header(im, 'Traits');
    local evals = ctx.sets.traitEval(ids, book);
    if #evals == 0 then
        kit.ctext(im, kit.COL.dim, 'no trait points at this level');
    end
    for _, ev in ipairs(evals) do
        -- what the SET earns is not always what you GET: a job trait of the
        -- same name discards the blue one (Traits tab has the full story) --
        -- the attribution came back with the trait work, review 2026-08-10:
        -- the timeline rewrite of this tab had lost it
        local v = ctx.verdict and ctx.verdict(ev.cat, ev.weight) or nil;
        if v ~= nil and v.deadWeight and v.blocker ~= nil then
            -- given, not blocked (the CEXI law, field 2026-08-10): the job
            -- grants this tier already; the points buy nothing NEW, and a
            -- higher tier is still reachable for its full points
            kit.ctext(im, kit.COL.dim, ('%s: from %s (rank %d)'):format(
                ev.name, v.blocker.code or 'your job', v.blocker.rank));
            kit.tip(im, ('%s grants %s at rank %d whatever this set does, so the %d\n'
                .. 'points buy nothing new. Feeding PAST that tier still climbs --\n'
                .. 'a higher blue tier takes over. See the Traits tab.'):format(
                v.blocker.name or 'Your job', ev.name, v.blocker.rank, ev.weight));
        elseif ev.tier then
            kit.ctext(im, kit.COL.ok, ('%s: %s'):format(ev.name, ev.tierText));
        else
            kit.ctext(im, kit.COL.dim, ('%s: below tier 1'):format(ev.name));
        end
        if ev.nextPoints then
            kit.ctext(im, kit.COL.dim, ('   %d more Points -> %s'):format(
                ev.nextPoints - ev.weight, ev.nextText or 'next tier'));
        end
    end
end

-- The picker for the selected slot: search + category over the codex data,
-- rows sorted by level, right-click assigns (the level control's choice or
-- the spell's own level), blocked rows dim with the reason in the tooltip.
local function assignPane(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    if st.assignSlot == nil then
        kit.wrapped(im, kit.COL.dim, 'Pick a target first: click a slot row in the middle column to mark it.');
        return;
    end
    local slot = st.assignSlot;
    local floor = ctx.sets.bracketFloor(slot);
    kit.ctext(im, kit.COL.head, ('Assign - bracket Lv.%d-%d'):format(floor, bracketTop(floor)));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Close', false, kit.measure(im, { 'Close' }, 54), 20) then
        st.assignSlot = nil;
        st.rightTab = 'Stats';
        return;
    end

    -- the activation-level control (plan 2.3: default = the spell's level)
    st.assignLevel = st.assignLevel or { '' };
    kit.helpLabel(im, 'Activate at Lv.',
        'Blank = the spell\'s own level (the default, and the earliest\n'
        .. 'legal moment). Type a level to delay a swap -- or to place the\n'
        .. 'empty marker, which needs an explicit level.', kit.COL.dim);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(40); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxassignlvl', st.assignLevel, 3);
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local lvOverride = tonumber(st.assignLevel[1]);
    if lvOverride ~= nil then lvOverride = math.floor(lvOverride); end
    local mw = kit.measure(im, { 'Empty from that Lv.' }, 120);
    if kit.litButton(im, 'Empty from that Lv.', false, mw, 20) then
        if lvOverride == nil then
            st.addNote = 'Type the level the slot should go empty at first.';
        else
            local okE, whyE = ctx.sets.addEntry(set, slot, 0, lvOverride, book);
            st.addNote = okE and ('The slot goes empty at Lv.%d.'):format(lvOverride)
                or ('Cannot: %s.'):format(whyE);
        end
    end
    kit.tip(im, 'End the chain deliberately: from that level the slot sits\n'
        .. 'vacant and its points go elsewhere. Shows as an entry;\n'
        .. 'remove it like one.');
    if st.addNote then kit.ctext(im, kit.COL.dim, st.addNote); end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    st.assignFilter = st.assignFilter or { text = { '' }, category = {}, trait = {} };
    st.assignFilter.trait = st.assignFilter.trait or {};
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(140); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxassignsearch', st.assignFilter.text, 48);
        kit.tip(im, 'Filter by name');
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxassigncat', st.assignFilter.category, book.categories, 'All types',
        kit.measure(im, book.categories, 80) + 24);
    -- the TRAIT filter (Henrik 2026-08-10: with slotlist adds living here,
    -- picking by trait has to live here too -- per slot)
    local traitNames = {};
    for _, t in ipairs(book.traitChoices) do traitNames[#traitNames + 1] = t.name; end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxassigntrait', st.assignFilter.trait, traitNames, 'All traits',
        kit.measure(im, traitNames, 90) + 24);
    kit.tip(im, 'Only spells feeding one trait ladder - build a trait\nslot by slot.');
    local traitCat = nil;
    for _, t in ipairs(book.traitChoices) do
        if t.name == st.assignFilter.trait.value then traitCat = t.cat; end
    end

    local ids = book.filter({
        text = st.assignFilter.text[1],
        category = st.assignFilter.category.value,
        traitCat = traitCat,
    });
    local sp = book.spells;
    table.sort(ids, function(a, b)
        local la, lb = sp[a].level or 999, sp[b].level or 999;
        if la ~= lb then return la < lb; end
        return sp[a].name < sp[b].name;
    end);

    if not (kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild')) then return; end
    if im.BeginChild('bdxassignlist', { 0, 0 }, false) then
        local nameW = math.max(kit.availWidth(im, 340) - 52, 120);
        for _, id in ipairs(ids) do
            local s = sp[id];
            local okA, whyA = ctx.sets.canAddEntry(set, slot, id, lvOverride, book);
            local label = ('%s  Lv.%s  %spt'):format(s.name, s.level or '?', s.setPoints or '?');
            local lclick, rclick, hov = spellsui.listRow(ctx, id, 24, nameW, false, true,
                okA and { label = label } or { label = label, textCol = kit.COL.dim });
            if lclick then
                st.selectedId = id;
                st.detailOpen[1] = true;
                st.detailFocus = true;
            end
            if rclick then
                if okA then
                    local okDo, whyDo = ctx.sets.addEntry(set, slot, id, lvOverride, book);
                    st.addNote = okDo and ('Assigned %s.'):format(s.name)
                        or ('Cannot assign %s: %s.'):format(s.name, whyDo);
                else
                    st.addNote = ('Cannot assign %s: %s.'):format(s.name, whyA);
                end
            end
            spellsui.tooltip(ctx, id, hov, okA
                and { { 'right-click: assign into the slot', kit.COL.dim } }
                or { { 'blocked: ' .. tostring(whyA), kit.COL.err } });
        end
    end
    im.EndChild();
end

-- ---------------------------------------------------------------------------
-- THE SLOT EDITOR (Henrik 2026-08-10, fourth round): ONE recurring window
-- for one slot of a slotlist -- edit the levels of its entries, remove
-- them, and take an add handed over by a codex/traits right-click ("so it
-- synergizes ... a re-usable recurring window"). Opened from the slot
-- row's right-click menu (Edit slot...) and from the assign menu's "Add
-- here...". Renders from the host beside the Spell Info window.
-- ---------------------------------------------------------------------------
function M.slotEditorWindow(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local se = st.slotEdit;
    if se == nil then return; end
    local set = st.editingSet;
    if ctx.sets.kindOf(set) ~= 'timeline' or set.chains == nil then
        st.slotEdit = nil;
        return;
    end
    if not (kit.isFn(im, 'Begin') and kit.isFn(im, 'End')) then return; end
    local floor = ctx.sets.bracketFloor(se.slot);
    se.open = se.open or { true };
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        pcall(im.SetNextWindowSizeConstraints, { 400, 180 }, { 900, 700 });
    end
    local visible = false;
    local ok = pcall(function()
        visible = im.Begin(('Slot %d  (opens at Lv.%d)###bdxslotedit'):format(
            se.slot, floor), se.open);
    end);
    if ok and visible then
        local chain = set.chains[se.slot];
        -- any mutation re-sorts the chain, so the level buffers are only
        -- trusted while the chain holds its shape
        if se.sig ~= #chain then se.sig = #chain; se.bufs = {}; end

        -- the pending add, handed over by a codex/traits right-click
        if se.addId ~= nil then
            local s = book.spells[se.addId];
            kit.ctext(im, kit.COL.head, ('Add %s'):format(s and s.name or ('#' .. se.addId)));
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            kit.ctext(im, kit.COL.dim, ' at Lv.');
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            -- PREFILLED WITH THE SPELL'S OWN LEVEL (Henrik 2026-08-10, sixth
            -- round: "auto fill in the level of the ability so it's not just
            -- blank"). It is exactly what the blank box already meant --
            -- setmodel.addEntry defaults to s.level -- now shown rather than
            -- implied, and a starting point to edit from instead of an empty
            -- field you have to know the answer for.
            --
            -- Keyed to the pending id: handing a DIFFERENT spell to this
            -- window refills it, instead of leaving the last one's number
            -- sitting there looking deliberate.
            if se.addFor ~= se.addId then
                se.addFor = se.addId;
                se.addLvl = { tostring((s and s.level) or 1) };
            end
            se.addLvl = se.addLvl or { '' };
            if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(40); end
            if kit.isFn(im, 'InputText') then
                pcall(im.InputText, '##bdxseaddlvl', se.addLvl, 3);
            end
            kit.tip(im, ('Filled in with %s\'s own level - the earliest it can\n'
                .. 'activate. Type any level from there up; blank means the\n'
                .. 'same thing as the number shown.'):format(
                (s and s.name) or 'the spell'));
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if kit.litButton(im, 'Add', false, kit.measure(im, { 'Add' }, 44), 20, kit.PAL.go) then
                local lv = tonumber(se.addLvl[1]);
                local okA, whyA = ctx.sets.addEntry(set, se.slot, se.addId, lv, book);
                se.note = okA and ('Added %s.'):format(s and s.name or se.addId)
                    or ('Cannot add: %s.'):format(whyA);
                if okA then se.addId, se.addFor = nil, nil; se.bufs = {}; end
            end
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if kit.litButton(im, 'Drop', false, kit.measure(im, { 'Drop' }, 44), 20) then
                -- addFor goes with it, so handing the SAME spell over again
                -- comes back prefilled rather than holding the dropped edit
                se.addId, se.addFor = nil, nil;
            end
            kit.tip(im, 'Forget this add (the slot keeps what it has).');
            if kit.isFn(im, 'Separator') then im.Separator(); end
        end

        -- the chain: each entry's level editable in place, each removable
        if #chain == 0 then
            kit.wrapped(im, kit.COL.dim,
                'Nothing here yet - right-click a spell in the Codex or Traits and pick this slot.');
        end
        for i, e in ipairs(chain) do
            local nm = (e.id == 0) and '(empty marker)'
                or ((book.spells[e.id] and book.spells[e.id].name) or ('#' .. e.id));
            kit.ctext(im, (e.id == 0) and kit.COL.dim or kit.COL.head, nm);
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            kit.ctext(im, kit.COL.dim, ' from Lv.');
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            se.bufs[i] = se.bufs[i] or { tostring(e.from) };
            if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(40); end
            if kit.isFn(im, 'InputText') then
                pcall(im.InputText, ('##bdxself%d'):format(i), se.bufs[i], 3);
            end
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if kit.litButton(im, ('Set##bdxsemove%d'):format(i), false,
                kit.measure(im, { 'Set' }, 40), 20) then
                local lv = tonumber(se.bufs[i][1]);
                if lv == nil then
                    se.note = 'Type the level it should activate at.';
                else
                    local okM, whyM = ctx.sets.setEntryLevel(set, se.slot, i, lv, book);
                    se.note = okM and ('Moved to Lv.%d.'):format(lv)
                        or ('Cannot move: %s.'):format(whyM);
                    se.bufs = {};
                    break;                         -- the chain just re-sorted
                end
            end
            kit.tip(im, 'Move this entry to the typed activation level.\nThe same rules as any add apply; a refused move\nchanges nothing.');
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if kit.litButton(im, ('Remove##bdxserem%d'):format(i), false,
                kit.measure(im, { 'Remove' }, 60), 20) then
                local okR, whyR = ctx.sets.removeEntry(set, se.slot, i, book);
                se.note = okR and 'Removed.' or ('Cannot remove: %s.'):format(whyR);
                se.bufs = {};
                break;                             -- indices just shifted
            end
        end
        if se.note then kit.wrapped(im, kit.COL.dim, se.note); end
        if kit.litButton(im, 'Close', false, kit.measure(im, { 'Close' }, 54), 22) then
            st.slotEdit = nil;
        end
    end
    if ok then pcall(im.End); end
    if se.open ~= nil and se.open[1] == false then st.slotEdit = nil; end
end

-- The slot row's right-click menu (Henrik 2026-08-10: "instead of removing
-- the spell immediately, give a menu"). Opened by chainRow, rendered once
-- per frame here at the planner's scope.
slotRowMenu = function(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local sm = st.slotMenu;
    if sm == nil then return; end
    if not (kit.isFn(im, 'BeginPopup') and kit.isFn(im, 'EndPopup')) then return; end
    local opened = false;
    pcall(function() opened = im.BeginPopup('##bdxslotrowmenu'); end);
    if not opened then return; end
    local nm = (sm.id == 0) and 'the empty marker'
        or ((book.spells[sm.id] and book.spells[sm.id].name) or ('#' .. tostring(sm.id)));
    local okE, hitE = pcall(im.Selectable, 'Edit slot...');
    if okE and hitE then
        st.slotEdit = { slot = sm.slot };
        st.slotMenu = nil;
        pcall(im.CloseCurrentPopup);
    end
    kit.tip(im, 'The slot editor: move entry levels, remove, add.');
    local okR, hitR = pcall(im.Selectable, kit.esc(('Remove %s'):format(nm)));
    if okR and hitR then
        local okD, whyD = ctx.sets.removeEntry(st.editingSet, sm.slot, sm.idx, book);
        st.applyNote = okD and nil or ('Cannot remove: %s.'):format(whyD);
        st.slotMenu = nil;
        pcall(im.CloseCurrentPopup);
    end
    pcall(im.EndPopup);
end

local function rightPanel(ctx)
    local im, st = ctx.im, ctx.state;
    -- the Assign pane is chain machinery -- timeline sets only; the other
    -- kinds add from the Codex/Traits rows (right-click), as they always did
    if ctx.sets.kindOf(st.editingSet) ~= 'timeline' then
        statsPanel(ctx);
        return;
    end
    st.rightTab = st.rightTab or 'Stats';
    local w = kit.measure(im, { 'Stats', 'Assign' }, 64);
    if kit.litButton(im, 'Stats', st.rightTab ~= 'Assign', w, 20) then
        st.rightTab = 'Stats';
    end
    kit.tip(im, 'Stats and traits at the preview level.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Assign', st.rightTab == 'Assign', w, 20) then
        st.rightTab = 'Assign';
    end
    kit.tip(im, 'The spell picker for the selected slot.');
    if kit.isFn(im, 'Separator') then im.Separator(); end
    if st.rightTab == 'Assign' then
        assignPane(ctx);
    else
        statsPanel(ctx);
    end
end

function M.render(ctx)
    local im = ctx.im;
    -- child widths follow their widest measured rows (the clipping law --
    -- 'Clea', 'Man' and 'Dele' all clipped in the field at the old fixed
    -- widths)
    local rowW = kit.measure(im, { 'New', 'Save', 'Delete' }, 50);
    -- the left column must also hold a rung row whole ('>71  77 / 79+ 19 / 20')
    -- and the Levels row (add list beside Remove) -- measured, never guessed
    -- (the clipping law; field 2026-08-07: the rows clipped at the old width)
    local rungW = kit.measure(im, { '>71   77 / 79+  19 / 20  ' }, 0) + 24;
    local lvlW = kit.measure(im, { 'Add a level' }, 90)
        + kit.measure(im, { 'Remove' }, 66) + 30;
    LEFT_W = math.max(210, rowW * 3 + 32, rungW, lvlW);
    local gameRow = kit.measure(im, { 'Apply in game', 'Applying...' }, 100)
        + kit.measure(im, { 'Read current', 'Confirm read?' }, 90)
        + kit.measure(im, { 'Clear' }, 50);
    local levelRow = kit.measure(im, { 'Level change:' }, 60)
        + kit.measure(im, { 'Auto-apply', 'Manual' }, 64) * 2;
    -- the floor is a READING width, not a fitting one: the slot list runs
    -- twenty spell names deep and 340 clipped the longer ones (Henrik
    -- 2026-08-10, sixth round: "can we make the middle column a little
    -- wider"). The measured rows still win whenever they need more.
    MID_W = math.max(400, gameRow + 34, levelRow + 34);
    -- while the share/import panes are up they own EVERYTHING right of the
    -- saved list (Henrik 2026-08-10, from the field: "we have ample space")
    -- -- the stats panel has nothing to say about a text box anyway
    local wide = ctx.state.shareOpen or ctx.state.importOpen;
    if kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild') then
        if im.BeginChild('bdxsaved', { LEFT_W, 0 }, true) then savedList(ctx); end
        im.EndChild();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if im.BeginChild('bdxslots', { wide and 0 or MID_W, 0 }, true) then midColumn(ctx); end
        im.EndChild();
        if not wide then
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if im.BeginChild('bdxstats', { 0, 0 }, true) then rightPanel(ctx); end
            im.EndChild();
        end
    else
        savedList(ctx); midColumn(ctx);
        if not wide then rightPanel(ctx); end
    end
end

return M;
