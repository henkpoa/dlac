--[[
    dlac/gearoptim.lua

    Stat-aware gear optimization.  Two independent tools, both READ-ONLY (they only
    ever PRINT recommendations -- nothing is equipped and no game state is touched):

      Part A -- MP analysis + max-MP -> potency swap advice
        While your MP is near full, big-MP pieces are still buying you casts. Once
        you have burned past a threshold, that MP pool is dead weight, so we tell you
        which slots to swap out of max-MP gear and into potency (Magic Atk.) gear.

      Part B -- stat weights + best-set builder
        You assign each stat a piecewise-linear value ("20 points per Accuracy up to
        +60, then 0"). `M.score` turns an item's Stats into a number with that rule,
        and `M.buildBestSet` picks the highest-scoring eligible item for every slot.
        `M.buildMaxStatSet` instead maximizes one raw stat (best Accuracy set, etc.).

    Self-contained and additive: it registers its OWN command alias and only ever
    acts on its own subcommands ( weight | best | mp | maxmp ), leaving every other
    /dl subcommand to utils.lua and gearimport.lua. Every AshitaCore/gData/memory
    read is pcall-guarded, so nothing in here can break profile loading or a cast.

    Commands (prefix /dl or /dlac):
        /dl weight <Stat> <perUnit> <cap>   set a stat weight (cap optional)
        /dl weight show                     list current weights
        /dl weight clear <Stat>             remove a stat weight
        /dl best                            print the best set using the weights
        /dl best <stat>                     print the set that maximizes one stat
        /dl mp                              print current / max / spent MP
        /dl maxmp [on|off|<n>]              toggle max-MP mode / set threshold / status

    Weights persist to  <profile>\dlac\gearweights.lua  (a `return {...}` module,
    written the same way gearimport writes its files) and load on first use.

    Integrating a recommendation with LuAshitacast: the builders return slot->item
    Name pairs. To actually wear them, copy those Names into the matching
    `sets.Dynamic.<SetName>.<Slot>` list in your job file (or hand them to a future
    equip helper) -- BuildDynamicSets already resolves a Name string via
    gear.NameToObject, so a printed pick can be pasted straight in.
]]--

local gear = require("dlac\\gear");
-- Level-scaling stats (Rajas/Tamas/Sattva etc.): rank slots on the EFFECTIVE stats
-- for the build level, not the catalog's flat base. Guarded: absent module = no-op.
local _lsok, lscale = pcall(require, "dlac\\data\\levelstats");
local hasLScale = _lsok and type(lscale) == 'table';
-- Gear-set bonus evaluator (docs/design/conditional-effects.md P3): buildBestSet
-- wires its membership/tier lookups into optimizePicks via opts.effects.
-- Guarded: absent module = set-blind builds, exactly the pre-P3 behavior.
local _gfxok, gfx = pcall(require, "dlac\\gear\\geareffects");
local hasGfx = _gfxok and type(gfx) == 'table' and type(gfx.setsOf) == 'function';

-- Colored [dlac] chat output (chatfmt): the shadowed `print` re-heads
-- "[dlac] ..."-prefixed lines with the colored header; plain when unavailable.
local _cfmtok, _cfmt = pcall(require, 'dlac\\chatfmt');
local print = (_cfmtok and type(_cfmt) == 'table' and type(_cfmt.print) == 'function') and _cfmt.print or print;

local M = {};

-- ===========================================================================
-- Shared helpers: stat spelling, alias groups, single-stat value, entry resolve
-- ===========================================================================

-- Wrap any AshitaCore/gData/io access so a nil manager, a not-logged-in state, or
-- a missing field returns nil instead of throwing. Used everywhere below.
local function safeCall(fn)
    local ok, res = pcall(fn);
    if ok then return res; end
    return nil;
end

-- gear.lua spells the same concept a few ways (MATK / Magic Atk. Bonus / MAB).
-- Reading a stat sums every spelling in its group, so weighting or summing "MATK"
-- also counts the other two however an entry happened to write them. Extend here.
local ALIAS_GROUPS = {
    { "MATK", "MagicAttackBonus", "MAB" },
    { "MagicAccuracy", "MACC" },
};
local CANON_GROUP = {};   -- lower(spelling) -> the group table it belongs to
for _, grp in ipairs(ALIAS_GROUPS) do
    for _, k in ipairs(grp) do CANON_GROUP[string.lower(k)] = grp; end
end

-- "Negative-good" (lower-is-better) stats: gear stores a beneficial effect as a
-- NEGATIVE number -- e.g. "Damage Taken -15%" is stored as DT = -15, and taking
-- LESS damage is better. M.score negates these so a POSITIVE weight rewards a
-- negative (good) value and penalizes a positive (bad) one. Add a stat here (in
-- gear.lua's canonical spelling) whenever a NEGATIVE value is the beneficial one.
-- Future candidates once catalogued and stored that way: SongRecast (song recast
-- time), CureCastTime (cure casting time), SpellInterruptionRateDown -- reductions
-- not present in the gear yet.
local NEGATIVE_GOOD_STATS = { "DT", "PDT", "MDT" };
local NEGATIVE_GOOD = {};   -- lower(spelling) -> true (matched case-insensitively)
for _, k in ipairs(NEGATIVE_GOOD_STATS) do NEGATIVE_GOOD[string.lower(k)] = true; end

-- Build once: lower(stat) -> the exact spelling used in gear.lua. Lets a typed
-- "accuracy" or "matk" normalize to the real "Accuracy" / "MATK" key, so weights
-- and lookups are case-insensitive and match what the entries actually store.
local _statSpelling = nil;
local function statSpellings()
    if _statSpelling ~= nil then return _statSpelling; end
    _statSpelling = {};
    if type(gear) == 'table' and type(gear.NameToObject) == 'table' then
        for _, obj in pairs(gear.NameToObject) do
            if type(obj) == 'table' and type(obj.Stats) == 'table' then
                for k in pairs(obj.Stats) do
                    if type(k) == 'string' then _statSpelling[string.lower(k)] = k; end
                end
            end
        end
    end
    -- make sure the alias spellings are always resolvable even if unused so far
    for _, grp in ipairs(ALIAS_GROUPS) do
        for _, k in ipairs(grp) do
            if _statSpelling[string.lower(k)] == nil then _statSpelling[string.lower(k)] = k; end
        end
    end
    return _statSpelling;
end

-- Reset caches derived from gear.lua's stats. gearui calls this after re-enriching the raw
-- gear table from the catalog (e.g. on Commit), so newly-owned stat names resolve.
function M.invalidate() _statSpelling = nil; end

-- Normalize a user/stored stat name to gear.lua's spelling (case-insensitive). An
-- unknown stat is returned unchanged, so you can still weight something rare.
local function canonStat(key)
    if type(key) ~= 'string' then return key; end
    return statSpellings()[string.lower(key)] or key;
end
M.canonStat = canonStat;

-- Value of one stat on a Stats table, alias-aware. Non-number values (booleans
-- like DomainIncursion, or the nested Pet table) count as 0 so scoring never errors.
local function statValue(stats, key)
    if type(stats) ~= 'table' or key == nil then return 0; end
    key = canonStat(key);
    local grp = CANON_GROUP[string.lower(key)];
    if grp ~= nil then
        local total = 0;
        for _, k in ipairs(grp) do
            local v = stats[k];
            if type(v) == 'number' then total = total + v; end
        end
        return total;
    end
    local v = stats[key];
    return (type(v) == 'number') and v or 0;
end
M.statValue = statValue;

-- Resolve one member of a set into a gear entry (a table with .Stats). Accepts:
--   * a Name string        -> looked up in gear.NameToObject
--   * a {gear=..., ...}     -> the utils.lua per-item override wrapper (unwrap .gear)
--   * a raw entry table     -> returned as-is
-- Returns nil for anything that isn't gear (so callers can skip it safely).
local function resolveEntry(v)
    if v == nil then return nil; end
    if type(v) == 'string' then
        local nto = (type(gear) == 'table') and gear.NameToObject or nil;
        return (nto ~= nil) and nto[v] or nil;
    end
    if type(v) == 'table' then
        if v.gear ~= nil then return resolveEntry(v.gear); end   -- {gear=entryOrName, minLevel=..}
        if type(v.Stats) == 'table' then return v; end
        if type(v.Name) == 'string' then return v; end
    end
    return nil;
end
M.resolveEntry = resolveEntry;

-- ---------------------------------------------------------------------------
-- M.sumStat(setOrItems, statKey) -> number
-- Total of one stat across every piece in a set (or plain list) of items. A "set"
-- is any table whose values are item Names, {gear=..} wrappers, or entry tables --
-- e.g. the slot->Name table BuildDynamicSets produces, or a job file's flat set.
-- Alias groups are summed (statValue), so "MATK" also counts Magic Atk. Bonus.
--
-- Percent stats (MPP / HPP) are percent-of-BASE MP/HP, so this returns the total
-- percentage POINTS (two +2% pieces -> 4), not a flat MP/HP amount. Converting to
-- flat needs the character's base pool, which this low-level helper deliberately
-- doesn't read -- combine sumStat(set,"MPP") with M.getMaxMP() at the call site if
-- you need an absolute figure.
-- ---------------------------------------------------------------------------
function M.sumStat(setOrItems, statKey)
    if type(setOrItems) ~= 'table' then return 0; end
    local total = 0;
    for k, v in pairs(setOrItems) do
        if k ~= 'NameToObject' then                    -- skip the reverse-index if a whole gear table is passed
            local entry = resolveEntry(v);
            if entry ~= nil and type(entry.Stats) == 'table' then
                total = total + statValue(entry.Stats, statKey);
            end
        end
    end
    return total;
end

-- ===========================================================================
-- PART A -- live MP + max-MP -> potency swap advice
-- ===========================================================================

-- All four read live MP the way LuAshitacast's own data.lua does. gData.GetPlayer()
-- already surfaces .MP / .MaxMP / .MPP (it wraps GetParty():GetMemberMP(0) and
-- GetPlayer():GetMPMax()), so we prefer it for consistency and fall back to the raw
-- Ashita memory API. Guarded end-to-end -> nil when not logged in / unavailable.
function M.getCurrentMP()
    local v = safeCall(function() return gData.GetPlayer().MP; end);
    if type(v) == 'number' then return v; end
    v = safeCall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberMP(0); end);
    if type(v) == 'number' then return v; end
    return nil;
end

function M.getMaxMP()
    local v = safeCall(function() return gData.GetPlayer().MaxMP; end);
    if type(v) == 'number' then return v; end
    v = safeCall(function() return AshitaCore:GetMemoryManager():GetPlayer():GetMPMax(); end);
    if type(v) == 'number' then return v; end
    return nil;
end

function M.getMPP()
    local v = safeCall(function() return gData.GetPlayer().MPP; end);
    if type(v) == 'number' then return v; end
    v = safeCall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberMPPercent(0); end);
    if type(v) == 'number' then return v; end
    -- derive from cur/max if the percent API is unreachable this frame
    local cur, mx = M.getCurrentMP(), M.getMaxMP();
    if type(cur) == 'number' and type(mx) == 'number' and mx > 0 then
        return math.floor((cur / mx) * 100 + 0.5);
    end
    return nil;
end

-- MP "lost to max" = how much you've spent = maxMP - curMP (never negative).
function M.getMPLostToMax()
    local cur, mx = M.getCurrentMP(), M.getMaxMP();
    if type(cur) == 'number' and type(mx) == 'number' then
        local lost = mx - cur;
        if lost < 0 then lost = 0; end
        return lost;
    end
    return nil;
end

-- Max-MP mode configuration (in memory; a GUI or the /dl maxmp command drives it).
--   enabled     : the master toggle
--   threshold   : MP you must have SPENT (maxMP-curMP) before we advise swapping
--   potencyStat : the offensive stat(s) that define "potency" (alias-summed)
M._maxMP = M._maxMP or { enabled = false, threshold = 100, potencyStat = { "MATK" } };

function M.getMaxMPConfig() return M._maxMP; end
function M.setMaxMPEnabled(b) M._maxMP.enabled = (b == true); return M._maxMP.enabled; end
function M.setMaxMPThreshold(n)
    n = tonumber(n);
    if n == nil then return false; end
    M._maxMP.threshold = n;
    return true;
end
function M.setMaxMPPotencyStat(statOrList)
    if type(statOrList) == 'string' then M._maxMP.potencyStat = { statOrList };
    elseif type(statOrList) == 'table' then M._maxMP.potencyStat = statOrList;
    else return false; end
    return true;
end

-- ---------------------------------------------------------------------------
-- M.recommendMaxMPSwaps(opts) -> result
-- Given the max-MP loadout and its potency alternative, decide -- based on how much
-- MP you've spent -- which slots to swap. Reads gear Stats only; the live MP figure
-- comes from the guarded helpers (override with opts.mpLost for testing/GUI).
--
-- opts = {
--   maxMPSet    = { slot = NameOrEntry, ... },   -- what you wear near full MP
--   potencySet  = { slot = NameOrEntry, ... },   -- the offensive alternative
--   potencyStat = "MATK" | { ... }               -- default = config.potencyStat
--   threshold   = number,                        -- default = config.threshold
--   mpLost      = number,                         -- default = M.getMPLostToMax()
--   enabled     = bool,                           -- default = config.enabled
-- }
-- returns {
--   active   = bool,        -- true only when we're past threshold and advising swaps
--   mpLost   = number|nil,
--   threshold= number,
--   swaps    = { { slot, from, to, gain, fromMP, toMP }, ... },  -- sorted by gain desc
--   keep     = { slot, ... },
--   note     = string,
-- }
-- ---------------------------------------------------------------------------
function M.recommendMaxMPSwaps(opts)
    opts = opts or {};
    local cfg = M._maxMP;
    local enabled = opts.enabled; if enabled == nil then enabled = cfg.enabled; end
    local threshold = tonumber(opts.threshold) or cfg.threshold or 100;
    local potStat = opts.potencyStat or cfg.potencyStat or { "MATK" };
    if type(potStat) == 'string' then potStat = { potStat }; end

    local result = { active = false, swaps = {}, keep = {}, threshold = threshold, mpLost = nil, note = nil };

    if not enabled then
        result.note = 'maxMP mode off';
        return result;
    end

    local mpLost = opts.mpLost;
    if mpLost == nil then mpLost = M.getMPLostToMax(); end
    result.mpLost = mpLost;
    if type(mpLost) ~= 'number' then
        result.note = 'live MP unavailable';
        return result;
    end

    -- Still near full: the max-MP pieces are earning their keep -- hold position.
    if mpLost < threshold then
        result.note = string.format('spent %d MP (< %d) -- keep max-MP gear', mpLost, threshold);
        for slot in pairs(opts.maxMPSet or {}) do result.keep[#result.keep + 1] = slot; end
        return result;
    end

    -- Past the threshold: for each slot, if the potency piece carries more of the
    -- offensive stat than the max-MP piece, recommend the swap. The MP each piece
    -- gives is reported for context (how much pool you'd be giving up).
    result.active = true;
    result.note = string.format('spent %d MP (>= %d) -- swap max-MP -> potency where it gains', mpLost, threshold);

    local function potOf(stats)
        local t = 0;
        for _, s in ipairs(potStat) do t = t + statValue(stats, s); end
        return t;
    end

    local maxSet, potSet = opts.maxMPSet or {}, opts.potencySet or {};
    for slot, mv in pairs(maxSet) do
        local me, pe = resolveEntry(mv), resolveEntry(potSet[slot]);
        if me ~= nil and pe ~= nil and type(me.Stats) == 'table' and type(pe.Stats) == 'table' then
            local mPot, pPot = potOf(me.Stats), potOf(pe.Stats);
            if pPot > mPot then
                result.swaps[#result.swaps + 1] = {
                    slot   = slot,
                    from   = me.Name,
                    to     = pe.Name,
                    gain   = pPot - mPot,
                    fromMP = statValue(me.Stats, 'MP'),
                    toMP   = statValue(pe.Stats, 'MP'),
                };
            else
                result.keep[#result.keep + 1] = slot;
            end
        end
    end
    table.sort(result.swaps, function(a, b) return a.gain > b.gain; end);
    return result;
end

-- ===========================================================================
-- PART B -- stat weights, scorer, and best-set builder
-- ===========================================================================

-- Build-at-max-level toggle. When true, M.buildBestSet / M.buildMaxStatSet treat the
-- character as level MAX_LEVEL for the item-Level ELIGIBILITY cap ONLY, so you can
-- preview the best set you'll grow into. The JOB restriction is unchanged (jobAllowed
-- still filters on your real main job), so gear your job can't wear stays excluded.
-- ON by default (Henrik 2026-07-17: building sets should always ignore the level
-- cap unless deliberately narrowed). An UNTICK is remembered across reloads via
-- uiflags.lua (absent key = this ON default).
local MAX_LEVEL = 75;
M.MAX_LEVEL = MAX_LEVEL;
M.buildAtMaxLevel = true;

-- In-memory weight table: canonicalStat -> { perUnit = number, cap = number|nil }.
-- M._weights is the ACTIVE table the editor/optimizer read. It aliases either the
-- SHARED table (no set bound; legacy files load here) or one entry of the per-set
-- memory, switched by M.bindSetWeights -- every set remembers its own weights.
-- The "shared" (no-set) table is DEAD (Henrik 2026-07-17, round 3: "we start
-- blank, have weights per set and can save -- delete it, it's a dead concept").
-- While no set is bound the actives alias read-only EMPTY sentinels: every
-- reader sees "no weights", every mutator refuses with 'no set selected', and
-- nothing unbound is ever persisted, offered as a copy source, or seeded from.
-- Old files' shared sections (and pre-per-set flat files) are DROPPED on load.
local UNBOUND_W    = {};                 -- weights sentinel -- must stay empty
local UNBOUND_PRIO = {};                 -- priority-list sentinel
M._weights  = M._weights or UNBOUND_W;   -- ACTIVE points table (follows the binding)
M._perSet   = M._perSet or {};           -- '<JOB>|<SetName>' -> weights table
M._boundKey = nil;                       -- current binding, nil = none

-- Priority-list mode (2026-07-17, the "simple" weights): an ORDERED stat list --
-- top matters most, each entry optionally capped -- for people the pts/cap point
-- system doesn't click for. Same per-set binding architecture as the weights;
-- its OWN named store (a point template and a priority list never cross-load).
-- Which of the two drives scoring is a per-binding MODE ('points' | 'priority'),
-- flipped by whichever editor you touch.
M._prioPerSet = M._prioPerSet or {};     -- '<JOB>|<SetName>' -> ordered { stat, cap }
M._prio       = M._prio or UNBOUND_PRIO; -- ACTIVE list (follows the binding)
M._prioNamed  = M._prioNamed or {};      -- name -> list ("Saved Lists")
M._prioUndo   = M._prioUndo or {};       -- bindingKey -> pre-first-copy snapshot
M._modePerSet = M._modePerSet or {};     -- key -> 'priority' (absent = points)

local ensureWeightsLoaded;   -- forward: defined with the persistence block below, but
                             -- every accessor must lazy-load -- the GUI reads through
                             -- these long before any /dl command would run (the fix
                             -- for "weights editor empty after every addon reload").
local activeWeights;         -- forward: the mode-resolved scoring table (points table,
                             -- or the dominance weights DERIVED from the priority list)

-- The table scoring actually uses right now. The points editor must NOT read
-- this (it would render derived numbers in priority mode) -- it reads
-- M.getPointWeights instead.
function M.getWeights()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    return activeWeights();
end

-- The raw points table of the current binding, whatever the mode -- the points
-- EDITOR's view.
function M.getPointWeights()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    return M._weights;
end

-- Set/replace one stat weight. perUnit is required; cap is optional (nil = no cap).
-- Editing a mode's data makes that mode ACTIVE for the binding (the invariant
-- both editors and the /dl weight command lean on: you build where you type).
-- Refused while no set is bound: there is no shared table anymore.
function M.setWeight(stat, perUnit, cap)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end   -- never edit-then-save over an unloaded file
    if M._boundKey == nil then return false, 'no set selected'; end
    stat = canonStat(stat);
    if type(stat) ~= 'string' or stat == '' then return false, 'bad stat name'; end
    perUnit = tonumber(perUnit);
    if perUnit == nil then return false, 'perUnit must be a number'; end
    cap = tonumber(cap);   -- nil stays nil -> uncapped
    M._weights[stat] = { perUnit = perUnit, cap = cap };
    M.setWeightsMode('points');
    return true;
end

function M.clearWeight(stat)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    stat = canonStat(stat);
    if M._weights[stat] ~= nil then
        M._weights[stat] = nil;
        M.setWeightsMode('points');
        return true;
    end
    return false;
end

-- Per-set weight memory (Henrik): bind the ACTIVE weights to a set, so switching
-- sets never drags the previous set's tuning along. A never-bound set starts
-- BLANK (Henrik 2026-07-17: seeding made every new set inherit leftover
-- weights); after the first bind the set owns its tables and edits stick to IT
-- only. The PRIORITY list rides the same binding, blank too; the build-slot
-- MASK starts from the fixed default (a blank mask would mean "fill nothing"
-- and read as a dead Auto-build button). job or setName nil/'' (or the
-- pre-login '?' job) UNBINDS: the actives alias the read-only empty sentinels.
-- Returns true when the active table CHANGED (callers refresh buffers/caches).
function M.bindSetWeights(job, setName)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local key = nil;
    if type(job) == 'string' and job ~= '' and job ~= '?'
       and type(setName) == 'string' and setName ~= '' then
        key = job .. '|' .. setName;
    end
    if key == M._boundKey then return false; end
    M._boundKey = key;
    if key == nil then
        M._weights = UNBOUND_W;
        M._prio    = UNBOUND_PRIO;
        M._slots   = M._slotsUnbound;
        return true;
    end
    local t = M._perSet[key];
    if t == nil then
        t = {};
        M._perSet[key] = t;
    end
    M._weights = t;
    local pl = M._prioPerSet[key];
    if pl == nil then
        pl = {};
        M._prioPerSet[key] = pl;
    end
    M._prio = pl;
    local sm = M._slotsPerSet[key];
    if sm == nil then
        sm = M.defaultSlotMask();
        M._slotsPerSet[key] = sm;
    end
    M._slots = sm;
    return true;
end

-- The current binding key ('JOB|SetName'), or nil when nothing is bound.
function M.weightsBoundTo() return M._boundKey; end

-- ---------------------------------------------------------------------------
-- Build-slot mask (2026-07-17, replaces the "Skip weapons" checkbox): which
-- slots Auto-build FILLS. Same shared/per-set architecture as the weights --
-- M._slots is the ACTIVE mask, re-aliased by the same bindSetWeights call, so
-- every set remembers its build scope the way it remembers its weights. A mask
-- is { [label] = true } over the 16 optimizer labels; missing/false = leave
-- that slot exactly as the working set has it. Default = everything EXCEPT
-- Main/Sub/Range (weapon swaps reset TP -- the old checkbox's ON state); Ammo
-- stays in (ammo trinkets are real picks, ADR 0010).
-- ---------------------------------------------------------------------------
local SLOT_LABELS = { 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'Ear1', 'Ear2',
                      'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' };
local SLOT_OK = {};
for _, l in ipairs(SLOT_LABELS) do SLOT_OK[l] = true; end
local WEAPON_LABEL = { Main = true, Sub = true, Range = true };

function M.defaultSlotMask()
    local m = {};
    for _, l in ipairs(SLOT_LABELS) do
        if not WEAPON_LABEL[l] then m[l] = true; end
    end
    return m;
end

M._slotsUnbound = M._slotsUnbound or M.defaultSlotMask();   -- read-only: shown while
                                                            -- nothing is bound
M._slotsPerSet  = M._slotsPerSet or {};       -- '<JOB>|<SetName>' -> mask
M._slots        = M._slots or M._slotsUnbound;-- ACTIVE mask (follows the binding)

-- The ACTIVE mask (the bound set's; the fixed default while nothing is bound).
-- Callers treat it read-only; edits go through setSlotEnabled so persistence
-- stays honest.
function M.getSlotMask()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    return M._slots;
end

function M.setSlotEnabled(label, on)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    if SLOT_OK[label] ~= true then return false, 'unknown slot label'; end
    M._slots[label] = (on == true) and true or nil;
    return true;
end

-- Stored per-set weight keys ('JOB|Set'), sorted -- the copy-from picker list.
-- EMPTY tables are skipped: blank is the new-binding default (Henrik 07-17),
-- so every set ever selected has one, and an empty source is nothing to copy.
function M.perSetKeys()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local keys = {};
    for k, t in pairs(M._perSet) do
        if next(t) ~= nil then keys[#keys + 1] = k; end
    end
    table.sort(keys);
    return keys;
end

-- ---------------------------------------------------------------------------
-- Copy sources (the weights editor's cascading "copy from" menu).
-- NAMED weight profiles ("Saved Sets"): a tuning you liked, saved under a
-- proper name, independent of any job or set -- stored beside perSet in
-- gearweights.lua (named/namedSlots sections). Plus a one-shot session
-- snapshot per binding, taken before its FIRST copy, so "This set (revert)"
-- can undo a copy experiment.
-- ---------------------------------------------------------------------------
M._named      = M._named or {};        -- name -> weights table
M._namedSlots = M._namedSlots or {};   -- name -> slot mask
M._copyUndo   = M._copyUndo or {};     -- bindingKey -> { w = ..., s = ... }

local function undoKey() return M._boundKey or '<none>'; end
local function deepWeights(t)
    local c = {};
    for k, w in pairs(t) do c[k] = { perUnit = w.perUnit, cap = w.cap }; end
    return c;
end
local function deepMask(t)
    local c = {};
    for k, v in pairs(t) do c[k] = v; end
    return c;
end

-- Replace the ACTIVE tables' CONTENTS (they are aliases into _perSet entries,
-- so identity must survive) with a copy of sw/sm; snapshot first for revert.
-- Refused unbound: there is nothing to copy INTO without a set.
local function applyCopy(sw, sm)
    if M._boundKey == nil then return false, 'no set selected'; end
    if sw == nil then return false, 'no such weights source'; end
    if sw == M._weights then return false, 'that is already the active table'; end
    if M._copyUndo[undoKey()] == nil then
        M._copyUndo[undoKey()] = { w = deepWeights(M._weights), s = deepMask(M._slots) };
    end
    for k in pairs(M._weights) do M._weights[k] = nil; end
    for k, w in pairs(sw) do M._weights[k] = { perUnit = w.perUnit, cap = w.cap }; end
    if sm ~= nil and sm ~= M._slots then
        for k in pairs(M._slots) do M._slots[k] = nil; end
        for k, v in pairs(sm) do M._slots[k] = v; end
    end
    return true;
end

-- src = 'JOB|Set' (the shared source is gone with the shared table).
function M.copyWeightsFrom(src)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if type(src) ~= 'string' then return false, 'no such weights source'; end
    local ok, err = applyCopy(M._perSet[src], M._slotsPerSet[src]);
    if ok then M.setWeightsMode('points'); end
    return ok, err;
end

function M.copyWeightsFromNamed(name)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local ok, err = applyCopy(M._named[name], M._namedSlots[name]);
    if ok then M.setWeightsMode('points'); end
    return ok, err;
end

-- Save the ACTIVE weights + slot mask under a proper name (overwrites an
-- existing profile of the same name -- that is the update path).
function M.saveNamedWeights(name)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    name = string.gsub(string.gsub(tostring(name or ''), '^%s+', ''), '%s+$', '');
    if name == '' then return false, 'name required'; end
    M._named[name] = deepWeights(M._weights);
    M._namedSlots[name] = deepMask(M._slots);
    return true, name;
end

-- Bulk-add named weight profiles: the applier behind the weights IMPORT
-- (weightimport.lua parses; this lands the result). Unlike saveNamedWeights it
-- reads nothing from the ACTIVE table and needs no binding -- the pasted data
-- IS the profile. Stat keys canonicalize through canonStat so ACC / Acc /
-- Accuracy all land on the catalog spelling. Same-name = overwrite (the caller
-- confirms via weightimport.classify first). Returns { created, updated,
-- stats }; the caller persists with M.saveWeights().
function M.importNamedWeights(profiles)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end   -- mutate-after-load, or the lazy load would clobber the import
    local summary = { created = 0, updated = 0, stats = 0 };
    if type(profiles) ~= 'table' then return summary; end
    for name, wmap in pairs(profiles) do
        if type(name) == 'string' and name ~= '' and type(wmap) == 'table' then
            local t, n = {}, 0;
            for k, w in pairs(wmap) do
                if type(k) == 'string' and type(w) == 'table' and type(w.perUnit) == 'number' then
                    t[canonStat(k)] = { perUnit = w.perUnit, cap = (type(w.cap) == 'number') and w.cap or nil };
                    n = n + 1;
                end
            end
            if n > 0 then
                if M._named[name] ~= nil then summary.updated = summary.updated + 1;
                else summary.created = summary.created + 1; end
                M._named[name] = t;
                summary.stats = summary.stats + n;
            end
        end
    end
    return summary;
end

-- The priority-list twin of importNamedWeights: lands ordered lists in the
-- prio named store ("Saved Lists"). Entries arrive as { stat, cap|nil } rows
-- (weightimport.parsePrio's output); stats canonicalize, caps must be > 0.
function M.importNamedPrio(lists)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local summary = { created = 0, updated = 0, stats = 0 };
    if type(lists) ~= 'table' then return summary; end
    for name, list in pairs(lists) do
        if type(name) == 'string' and name ~= '' and type(list) == 'table' then
            local out = {};
            for _, e in ipairs(list) do
                if type(e) == 'table' and type(e.stat) == 'string' and e.stat ~= '' then
                    local cap = tonumber(e.cap);
                    out[#out + 1] = { stat = canonStat(e.stat),
                                      cap = (cap ~= nil and cap > 0) and cap or nil };
                end
            end
            if #out > 0 then
                if M._prioNamed[name] ~= nil then summary.updated = summary.updated + 1;
                else summary.created = summary.created + 1; end
                M._prioNamed[name] = out;
                summary.stats = summary.stats + #out;
            end
        end
    end
    return summary;
end

-- Read-only views of the two named stores, for the EXPORT popups (weightimport
-- renders them back into importable text). Callers must not mutate.
function M.allNamedWeights()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    return M._named;
end

function M.allNamedPrio()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    return M._prioNamed;
end

function M.deleteNamedWeights(name)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._named[name] == nil then return false, 'no such profile'; end
    M._named[name] = nil;
    M._namedSlots[name] = nil;
    return true;
end

function M.namedKeys()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local keys = {};
    for k in pairs(M._named) do keys[#keys + 1] = k; end
    table.sort(keys);
    return keys;
end

-- Read-only peek at a stored source, for the menu's (?) tooltips.
-- kind: 'set' (key = 'JOB|Set') | 'named' (key = profile name).
function M.peekWeights(kind, key)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if kind == 'set'    then return M._perSet[key]; end
    if kind == 'named'  then return M._named[key]; end
    return nil;
end

function M.copyUndoAvailable()
    return M._copyUndo[undoKey()] ~= nil;
end

-- Restore the binding to its pre-first-copy state (the snapshot survives, so
-- revert stays available after further copies this session).
function M.revertCopiedWeights()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local u = M._copyUndo[undoKey()];
    if u == nil then return false, 'nothing to revert'; end
    for k in pairs(M._weights) do M._weights[k] = nil; end
    for k, w in pairs(u.w) do M._weights[k] = { perUnit = w.perUnit, cap = w.cap }; end
    for k in pairs(M._slots) do M._slots[k] = nil; end
    for k, v in pairs(u.s) do M._slots[k] = v; end
    M.setWeightsMode('points');
    return true;
end

-- The Clear button: empty the ACTIVE points table in place (identity survives
-- the _perSet aliases), after the same pre-first-copy snapshot the copy path
-- takes -- so copy from... > This set (revert) can bring a mis-click back.
-- Build-slot marks are NOT touched: clearing your stat tuning shouldn't
-- silently change which slots Auto-build fills.
function M.clearAllWeights()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    if M._copyUndo[undoKey()] == nil then
        M._copyUndo[undoKey()] = { w = deepWeights(M._weights), s = deepMask(M._slots) };
    end
    for k in pairs(M._weights) do M._weights[k] = nil; end
    M.setWeightsMode('points');
    return true;
end

-- ===========================================================================
-- Priority-list mode -- the "simple" weights (Henrik's friends, 2026-07-17).
--
-- An ORDERED stat list: the top stat matters most, each entry may carry a cap.
-- Semantics are waterfall ("fill Accuracy to its cap first, then Attack, then
-- STR"), implemented by DERIVING a points table with dominance weights: walking
-- the list bottom-up, each stat's perUnit is 1 + (the maximum total score
-- everything below it could ever contribute), so one point of a higher stat
-- always outranks everything under it. A capped stat's ceiling is its cap; an
-- uncapped one is assumed to top out at UNCAPPED_ASSUMED_TOTAL across a set.
-- The derived table then rides the EXISTING pipeline untouched -- score,
-- optimizePicks (set-level caps), pairLadders, Auto-build -- via
-- activeWeights(), which every scoring default resolves through.
--
-- Which mode drives a binding is per-binding state ('points' | 'priority'),
-- flipped by whichever editor's data you MUTATE -- looking at a tab never
-- switches it. Priority lists have their OWN per-set store and their OWN named
-- store ("Saved Lists"): a point template and a priority list never cross-load.
-- ===========================================================================
local UNCAPPED_ASSUMED_TOTAL = 500;   -- generous set-total bound for an uncapped stat

local _prioCache, _prioCacheFor = nil, nil;   -- derived weights, keyed by list identity
local function invalidatePrioCache() _prioCache = nil; end

local function deriveFromPrio(list)
    local out = {};
    local below = 0;   -- max total score of every stat under the one being placed
    for i = #list, 1, -1 do
        local e = list[i];
        if type(e) == 'table' and type(e.stat) == 'string' then
            local per = 1 + below;
            local cap = (type(e.cap) == 'number' and e.cap > 0) and e.cap or nil;
            out[canonStat(e.stat)] = { perUnit = per, cap = cap };
            below = below + per * (cap or UNCAPPED_ASSUMED_TOTAL);
        end
    end
    return out;
end
M._deriveFromPrio = deriveFromPrio;   -- exposed for tests

function M.weightsMode()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return 'points'; end   -- unbound: nothing scores anyway
    return M._modePerSet[M._boundKey] or 'points';
end

function M.setWeightsMode(mode)
    if mode ~= 'points' and mode ~= 'priority' then return false; end
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    -- sparse: absent = points, so old sets never carry a mode row
    M._modePerSet[M._boundKey] = (mode == 'priority') and mode or nil;
    return true;
end

-- The mode-resolved scoring table (assigned to the forward local every scoring
-- default reads). Binding switches invalidate the cache by identity; in-place
-- list mutations call invalidatePrioCache explicitly.
activeWeights = function()
    if M.weightsMode() == 'priority' then
        if _prioCache == nil or _prioCacheFor ~= M._prio then
            _prioCache = deriveFromPrio(M._prio);
            _prioCacheFor = M._prio;
        end
        return _prioCache;
    end
    return M._weights;
end

-- The ACTIVE priority list (the bound set's, else shared). Read-only to
-- callers; edits go through the mutators so the cache and mode stay honest.
function M.getPrio()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    return M._prio;
end

local function deepPrio(list)
    local c = {};
    for i, e in ipairs(list) do c[i] = { stat = e.stat, cap = e.cap }; end
    return c;
end

function M.prioAdd(stat, cap)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    stat = canonStat(stat);
    if type(stat) ~= 'string' or stat == '' then return false, 'bad stat name'; end
    for _, e in ipairs(M._prio) do
        if string.lower(e.stat) == string.lower(stat) then return false, 'already listed'; end
    end
    cap = tonumber(cap);
    M._prio[#M._prio + 1] = { stat = stat, cap = (cap ~= nil and cap > 0) and cap or nil };
    invalidatePrioCache();
    M.setWeightsMode('priority');
    return true;
end

function M.prioRemove(i)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    if M._prio[i] == nil then return false; end
    table.remove(M._prio, i);
    invalidatePrioCache();
    M.setWeightsMode('priority');
    return true;
end

-- Swap entry i with entry i+delta (the editor's up/down arrows use +-1).
function M.prioMove(i, delta)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    local j = i + (tonumber(delta) or 0);
    if M._prio[i] == nil or M._prio[j] == nil or i == j then return false; end
    M._prio[i], M._prio[j] = M._prio[j], M._prio[i];
    invalidatePrioCache();
    M.setWeightsMode('priority');
    return true;
end

function M.prioSetCap(i, cap)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    local e = M._prio[i];
    if e == nil then return false; end
    cap = tonumber(cap);
    e.cap = (cap ~= nil and cap > 0) and cap or nil;
    invalidatePrioCache();
    M.setWeightsMode('priority');
    return true;
end

-- The priority tab's Clear button; snapshots first, like the points clear.
function M.prioClear()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    if M._prioUndo[undoKey()] == nil then
        M._prioUndo[undoKey()] = deepPrio(M._prio);
    end
    for i = #M._prio, 1, -1 do M._prio[i] = nil; end
    invalidatePrioCache();
    M.setWeightsMode('priority');
    return true;
end

-- Replace the ACTIVE list's contents (identity survives) with a copy of src;
-- snapshot first so "This list (revert)" can undo the experiment.
local function applyPrioCopy(src)
    if M._boundKey == nil then return false, 'no set selected'; end
    if src == nil then return false, 'no such priority list'; end
    if src == M._prio then return false, 'that is already the active list'; end
    if M._prioUndo[undoKey()] == nil then
        M._prioUndo[undoKey()] = deepPrio(M._prio);
    end
    for i = #M._prio, 1, -1 do M._prio[i] = nil; end
    for i, e in ipairs(src) do M._prio[i] = { stat = e.stat, cap = e.cap }; end
    invalidatePrioCache();
    M.setWeightsMode('priority');
    return true;
end

-- src = 'JOB|Set' (the shared source is gone with the shared table).
function M.copyPrioFrom(src)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if type(src) ~= 'string' then return false, 'no such priority list'; end
    return applyPrioCopy(M._prioPerSet[src]);
end

function M.copyPrioFromNamed(name)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    return applyPrioCopy(M._prioNamed[name]);
end

function M.savePrioNamed(name)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._boundKey == nil then return false, 'no set selected'; end
    name = string.gsub(string.gsub(tostring(name or ''), '^%s+', ''), '%s+$', '');
    if name == '' then return false, 'name required'; end
    M._prioNamed[name] = deepPrio(M._prio);
    return true, name;
end

function M.deletePrioNamed(name)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if M._prioNamed[name] == nil then return false, 'no such list'; end
    M._prioNamed[name] = nil;
    return true;
end

function M.prioNamedKeys()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local keys = {};
    for k in pairs(M._prioNamed) do keys[#keys + 1] = k; end
    table.sort(keys);
    return keys;
end

-- Stored per-set priority keys with a non-empty list, sorted (copy-from menu).
function M.prioPerSetKeys()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local keys = {};
    for k, t in pairs(M._prioPerSet) do
        if #t > 0 then keys[#keys + 1] = k; end
    end
    table.sort(keys);
    return keys;
end

-- Read-only peek at a stored list, for the menu's (?) tooltips.
-- kind: 'set' (key = 'JOB|Set') | 'named' (key = list name).
function M.peekPrio(kind, key)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    if kind == 'set'    then return M._prioPerSet[key]; end
    if kind == 'named'  then return M._prioNamed[key]; end
    return nil;
end

function M.prioUndoAvailable()
    return M._prioUndo[undoKey()] ~= nil;
end

function M.revertCopiedPrio()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    local u = M._prioUndo[undoKey()];
    if u == nil then return false, 'nothing to revert'; end
    for i = #M._prio, 1, -1 do M._prio[i] = nil; end
    for i, e in ipairs(u) do M._prio[i] = { stat = e.stat, cap = e.cap }; end
    invalidatePrioCache();
    M.setWeightsMode('priority');
    return true;
end

-- ---------------------------------------------------------------------------
-- M.score(itemStats [, weights]) -> number
-- Weighted score of one item's Stats using the piecewise-linear rule per stat:
--
--     contribution = perUnit * min(value, cap)
--
-- i.e. each point of the stat is worth `perUnit` up to `cap`, after which extra
-- points add nothing (marginal value 0) -- exactly "20 pts/Accuracy up to +60,
-- then 0". A NEGATIVE stat value passes through linearly (perUnit*value), so a
-- penalty stat still lowers the score; there is no lower bound. No weight cap
-- means the stat is purely linear.
--
-- Exception: "negative-good" stats (see NEGATIVE_GOOD -- DT/PDT/MDT) have their
-- value NEGATED before scoring, because gear stores their benefit as a negative
-- (DT -15%). So a positive weight on DT rewards -DT and penalizes +DT, and the cap
-- clamps the negated (goodness) value. Nothing else about stats is changed.
--
-- Note: the cap is applied PER ITEM here (that is all M.score can see). For genuine
-- set-wide diminishing returns you would cap the running total in buildSet; that is
-- left as a future pass -- greedy per-slot selection can't enforce a global cap
-- optimally, and the per-item clamp is a good, predictable proxy.
-- ---------------------------------------------------------------------------
function M.score(itemStats, weights)
    if weights == nil then
        if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
        weights = activeWeights();   -- points table, or the priority-derived one
    end
    if type(itemStats) ~= 'table' or type(weights) ~= 'table' then return 0; end
    local total = 0;
    for stat, w in pairs(weights) do
        if type(w) == 'table' and type(w.perUnit) == 'number' then
            local v = statValue(itemStats, stat);
            if v ~= 0 then
                -- Negative-good stats (DT/PDT/MDT) store their benefit as a negative
                -- number, so score the negation: -15 DT -> +15 goodness. Matched on the
                -- same canonical/lowercased spelling statValue uses, so a weight typed
                -- "dt" still hits. The cap below then clamps the goodness value.
                if NEGATIVE_GOOD[string.lower(canonStat(stat))] then v = -v; end
                local eff = v;
                if type(w.cap) == 'number' and v > w.cap then eff = w.cap; end
                total = total + w.perUnit * eff;
            end
        end
    end
    return total;
end

-- ---- eligibility -----------------------------------------------------------

-- Job + level for eligibility. Mirrors utils.determineLevels: the global
-- staticMainLevel override (set via /dl set level main N) wins for testing. Job is
-- gData's abbreviation string (e.g. "WHM"). Guarded -> ("", 0) if nothing is live.
function M.getPlayerJobLevel()
    local job = safeCall(function() return gData.GetPlayer().MainJob; end);
    if type(job) ~= 'string' then job = ''; end
    local level;
    if type(staticMainLevel) == 'number' and staticMainLevel > 0 then
        level = staticMainLevel;
    else
        level = safeCall(function() return gData.GetPlayer().MainJobSync; end);
    end
    if type(level) ~= 'number' then level = 0; end
    return job, level;
end

-- An entry may be worn if: it has Stats + a numeric Level <= your level, and its
-- Jobs list is absent (unrestricted, gear.lua's convention for most armor), contains
-- "All", or names your job. Entries without a numeric Level are skipped -- same
-- caution BuildDynamicSets takes, so we never recommend something un-vettable.
-- Delegates to THE central rule (dispatch.jobCanEquip); inline fallback kept.
local _dspok, _dsp = pcall(require, "dlac\\dispatch");
local function jobAllowed(entry, job)
    if job == nil or job == '' then return true; end     -- unknown job -> don't filter
    if _dspok and type(_dsp) == 'table' and type(_dsp.jobCanEquip) == 'function' then
        return _dsp.jobCanEquip(entry.Jobs, job);
    end
    local jobs = entry.Jobs;
    if type(jobs) ~= 'table' then return true; end
    for _, j in ipairs(jobs) do
        if j == 'All' or j == job then return true; end
    end
    return false;
end

local function isEligible(entry, job, level)
    if type(entry) ~= 'table' then return false; end
    if type(entry.Stats) ~= 'table' then return false; end
    if type(entry.Level) ~= 'number' then return false; end
    if entry.Level > (level or 0) then return false; end
    return jobAllowed(entry, job);
end

-- ---- slot iteration --------------------------------------------------------

-- gear.lua layout: Main/Range nest by weapon category; every other wearable slot is
-- flat. We optimize all of them. Ear/Ring have two physical slots, so we report the
-- best two distinct picks for those.
local NESTED_SLOTS = { "Main", "Range" };
local FLAT_SLOTS   = { "Sub", "Ammo", "Head", "Neck", "Ear", "Body", "Hands", "Ring", "Back", "Waist", "Legs", "Feet" };
local DUAL_SLOTS   = { Ear = true, Ring = true };

-- Ammo a Range weapon FIRES, keyed by the catalog's AmmoType -- and the pair is legal
-- only when the weapon's Type matches (arrows want a bow, not a gun). Everything else
-- in the slot has NO corresponding Range weapon and so demands an EMPTY one:
--   * Throwing (shuriken, pebble) fires from the Ammo slot itself, and the server
--     reads Range FIRST -- m_Weapons[SLOT_RANGED] ? SLOT_RANGED : SLOT_AMMO -- so any
--     Range weapon shadows it completely.
--   * The unfirable stat sticks (Cinderstone, Morion Tathlum, Coiste Bodhar, pet food)
--     carry no AmmoType at all: they only occupy the slot.
local RANGE_FIRED = { Archery = true, Marksmanship = true, FishingRod = true };

-- Call fn(entry) for every entry in a top-level slot, flattening the weapon-category
-- layer for Main/Range so the caller sees a flat stream of candidate entries.
local function forEachInSlot(slotKey, fn)
    local slot = (type(gear) == 'table') and gear[slotKey] or nil;
    if type(slot) ~= 'table' then return; end
    if slotKey == 'Main' or slotKey == 'Range' then
        for _, catTable in pairs(slot) do
            if type(catTable) == 'table' then
                for _, entry in pairs(catTable) do
                    if type(entry) == 'table' then fn(entry); end
                end
            end
        end
    else
        for _, entry in pairs(slot) do
            if type(entry) == 'table' then fn(entry); end
        end
    end
end

-- Rank a slot's eligible items by scoreFn (highest first; ties -> higher Level, then
-- Name, for stable, deterministic output). Returns a list of { entry, score }.
local function rankSlot(slotKey, scoreFn, job, level)
    local ranked = {};
    forEachInSlot(slotKey, function(entry)
        if isEligible(entry, job, level) then
            local st = entry.Stats;
            if hasLScale and type(lscale.effective) == 'function' then
                st = lscale.effective(entry, level);      -- THE central stats-at-level resolver
            end
            ranked[#ranked + 1] = { entry = entry, score = scoreFn(st), stats = st };
        end
    end);
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score; end
        local la, lb = a.entry.Level or 0, b.entry.Level or 0;
        if la ~= lb then return la > lb; end
        return tostring(a.entry.Name) < tostring(b.entry.Name);
    end);
    return ranked;
end

-- Core builder shared by both public builders. For each slot, take the top pick
-- (top two distinct for Ear/Ring). Returns:
--   { slots={label=itemName}, order={labels..}, perSlot={label={item,score,level}},
--     total=<sum of chosen scores>, job, level }
--
-- WEAPON CAVEAT: Main/Sub/Range are scored and picked independently, so dual-wield /
-- grip / shield pairing rules (which BuildDynamicSets enforces) are NOT applied here.
-- This is a pure stat maximizer -- vet a suggested weapon pair before wearing it.
-- acceptScore(score) -> bool gates whether a slot's best pick is worth wearing at
-- all. A slot whose top candidate fails the gate (e.g. carries none of the weighted
-- stats, so it scores 0) is left UNFILLED rather than padded with a junk piece --
-- represented exactly like a slot with no eligible gear: absent from slots/order/
-- perSlot. Nil gate = accept everything (old behavior).
-- Range + Ammo are decided TOGETHER, not greedily slot-by-slot. Picking each slot's own
-- best pairs a stat-stick ammo with whatever Range weapon happened to score -- and the
-- server then adds that ammo's delay to ranged delay for TP with NO compatibility check
-- (CBattleEntity::GetRangedWeaponDelay), so a bow + Cinderstone silently costs the stat
-- stick's full 999. Enumerate only LEGAL combinations and take the highest-scoring:
--   (Range, matching ammo) | (Range, no ammo) | (empty Range, unpaired ammo)
-- Ammo with no corresponding Range weapon -- unfirable, Throwing, or simply no owned
-- weapon of its type -- always leaves Range EMPTY (Henrik's ruling).
-- Returns { Range = pick|nil, Ammo = pick|nil }; both nil when nothing clears the gate.
local function pickRangeAmmo(scoreFn, job, level, acceptScore)
    local rangeR = rankSlot('Range', scoreFn, job, level);
    local ammoR  = rankSlot('Ammo',  scoreFn, job, level);
    local function ok(p) return p ~= nil and acceptScore(p.score); end

    local firedBy = {};                                 -- AmmoType -> best accepted Range of that Type
    for _, p in ipairs(rangeR) do
        local t = p.entry.Type;
        if t ~= nil and firedBy[t] == nil and ok(p) then firedBy[t] = p; end
    end

    local best = nil;
    -- Ties keep the fuller set (matches the old greedy placement when nothing is
    -- weighted); strict improvement is required to swap, so this stays deterministic.
    local function consider(r, a)
        local s = (r and r.score or 0) + (a and a.score or 0);
        local n = (r and 1 or 0) + (a and 1 or 0);
        if best == nil or s > best.score or (s == best.score and n > best.n) then
            best = { score = s, n = n, Range = r, Ammo = a };
        end
    end

    if ok(rangeR[1]) then consider(rangeR[1], nil); end   -- Range alone, Ammo not worth wearing
    for _, a in ipairs(ammoR) do
        if ok(a) then
            local t = a.entry.AmmoType;
            if t ~= nil and RANGE_FIRED[t] then consider(firedBy[t], a);   -- nil weapon -> Range empty
            else consider(nil, a); end                                     -- unpaired -> Range MUST be empty
        end
    end
    return best or {};
end

local function buildSet(scoreFn, job, level, acceptScore)
    if type(acceptScore) ~= 'function' then acceptScore = function() return true; end end
    local out = { slots = {}, order = {}, perSlot = {}, total = 0, job = job, level = level };

    local function place(label, pick)
        out.slots[label] = pick.entry.Name;
        out.order[#out.order + 1] = label;
        out.perSlot[label] = { item = pick.entry.Name, score = pick.score, level = pick.entry.Level };
        out.total = out.total + pick.score;
    end

    local slots = {};
    for _, s in ipairs(NESTED_SLOTS) do slots[#slots + 1] = s; end
    for _, s in ipairs(FLAT_SLOTS) do slots[#slots + 1] = s; end

    local ra;   -- the joint Range/Ammo decision, resolved once and read by both slots
    for _, slotKey in ipairs(slots) do
        if slotKey == 'Range' or slotKey == 'Ammo' then
            ra = ra or pickRangeAmmo(scoreFn, job, level, acceptScore);
            if ra[slotKey] ~= nil then place(slotKey, ra[slotKey]); end
        else
            local ranked = rankSlot(slotKey, scoreFn, job, level);
            if #ranked > 0 then
                if DUAL_SLOTS[slotKey] then
                    if acceptScore(ranked[1].score) then place(slotKey .. '1', ranked[1]); end
                    if #ranked > 1 and acceptScore(ranked[2].score) then place(slotKey .. '2', ranked[2]); end
                else
                    if acceptScore(ranked[1].score) then place(slotKey, ranked[1]); end
                end
            end
        end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- Set-level optimization under caps -- the "future pass" M.score's comment
-- promised. Greedy per-slot picking overspends capped stats: a slot whose item
-- brings ONLY a capped stat (Haste+5 head) can hold cap budget that another
-- slot would fill alongside more (Haste+5 + SwordSkill + Acc feet). This is a
-- multiple-choice knapsack; we solve it with hill-climbing on the SET total:
-- start empty, then repeatedly re-visit each slot with everything else fixed
-- and keep whichever candidate -- or EMPTY -- maximizes the total with caps
-- applied to the summed stats. Ties prefer EMPTY (never churn another set's
-- piece needlessly); swapping items requires strict improvement. Converges in
-- a few passes for 16 slots.
--
-- M.optimizePicks(pools, weights, opts) -> { picks = {label->index|nil}, total }
--   pools: { label -> { { stats = <stats table>, ref = <opaque> }, ... } }
--   opts.baseStats: array of stats tables counted as a fixed background
--     (e.g. the already-chosen pieces when optimizing one slot alone).
--   opts.conflict(refA, refB): true when two picks cannot coexist (paired
--     Ear/Ring slots sharing one physical copy).
--   opts.effects: gear-set bonus crediting (conditional-effects P3, ADR 0011):
--     { setsOf(itemId) -> {setId,..}|nil, setTier(setId, count) -> deltas|nil,
--       baseComposition = { rec, ... } -- already-chosen pieces whose set
--       membership pre-loads the counts (they are counted, never searched) }.
--     nil (or no set-carrying candidate) is structurally zero: no bonus term,
--     no restarts -- the H1-H8 exact totals are bit-identical.
-- ---------------------------------------------------------------------------
function M.optimizePicks(pools, weights, opts)
    opts = opts or {};
    weights = weights or activeWeights();
    local wl = {};                                     -- weight list, negation pre-resolved
    for stat, w in pairs(weights or {}) do
        if type(w) == 'table' and type(w.perUnit) == 'number' then
            wl[#wl + 1] = {
                stat    = stat,
                perUnit = w.perUnit,
                cap     = (type(w.cap) == 'number' and w.cap > 0) and w.cap or nil,
                neg     = NEGATIVE_GOOD[string.lower(canonStat(stat))] == true,
            };
        end
    end
    local labels = {};
    for label in pairs(pools) do labels[#labels + 1] = label; end
    table.sort(labels);                                -- deterministic climb order
    if #wl == 0 or #labels == 0 then return { picks = {}, total = 0 }; end

    -- Project a stats-shaped table onto wl. Shared by candidates, baseStats and
    -- set-bonus tiers, so alias groups and negative-good handling are identical
    -- everywhere (a DT set bonus scores as goodness like a DT stat does).
    local function project(st)
        local vec = {};
        for wi, w in ipairs(wl) do
            local v = statValue(st, w.stat);
            if w.neg then v = -v; end
            vec[wi] = v;
        end
        return vec;
    end

    -- Per-candidate value vector over wl, computed ONCE (the climb then only
    -- does sums), plus the fixed background from opts.baseStats.
    local vecs = {};
    for _, label in ipairs(labels) do
        local vv = {};
        for ci, cand in ipairs(pools[label]) do vv[ci] = project(cand.stats); end
        vecs[label] = vv;
    end
    local base = {};
    for wi = 1, #wl do base[wi] = 0; end
    if type(opts.baseStats) == 'table' then
        for _, st in ipairs(opts.baseStats) do
            local v = project(st);
            for wi = 1, #wl do base[wi] = base[wi] + v[wi]; end
        end
    end

    -- ---- gear-set bonuses: membership, counts, projected tiers --------------
    local eff = opts.effects;
    if type(eff) ~= 'table' or type(eff.setsOf) ~= 'function' or type(eff.setTier) ~= 'function' then
        eff = nil;
    end
    local candSets = nil;   -- label -> ci -> {setId,...} (only set-carrying candidates)
    local baseCnt  = {};    -- setId -> pieces already in baseComposition
    local tierVec  = nil;   -- setId -> count -> projected vec (nil below the set's min)
    local minOf    = {};    -- setId -> activation floor (probed via setTier)
    local relList  = {};    -- sorted setIds whose tiers carry any weighted stat
    if eff ~= nil then
        local seen = {};
        candSets = {};
        for _, label in ipairs(labels) do
            local cs = {};
            for ci, cand in ipairs(pools[label]) do
                local id = (type(cand.ref) == 'table') and cand.ref.Id or nil;
                local sids = (id ~= nil) and eff.setsOf(id) or nil;
                if sids ~= nil and #sids > 0 then
                    cs[ci] = sids;
                    for _, sid in ipairs(sids) do seen[sid] = true; end
                end
            end
            candSets[label] = cs;
        end
        if type(eff.baseComposition) == 'table' then
            for _, rec in pairs(eff.baseComposition) do
                local id = (type(rec) == 'table') and rec.Id or nil;
                local sids = (id ~= nil) and eff.setsOf(id) or nil;
                if sids ~= nil then
                    for _, sid in ipairs(sids) do
                        baseCnt[sid] = (baseCnt[sid] or 0) + 1;
                        seen[sid] = true;
                    end
                end
            end
        end
        -- Materialize every seen set's tier vectors per reachable count. A set
        -- none of whose tiers moves any weighted stat is dropped outright.
        local cmax = #labels;
        for _, n in pairs(baseCnt) do cmax = math.max(cmax, #labels + n); end
        tierVec = {};
        for sid in pairs(seen) do
            local tv, any, mn = {}, false, nil;
            for c = 1, cmax do
                local d = eff.setTier(sid, c);
                if d ~= nil then
                    if mn == nil then mn = c; end
                    local v = project(d);
                    tv[c] = v;
                    if not any then
                        for wi = 1, #wl do
                            if v[wi] ~= 0 then any = true; break; end
                        end
                    end
                end
            end
            if any then
                tierVec[sid] = tv;
                minOf[sid] = mn;
                relList[#relList + 1] = sid;
            end
        end
        table.sort(relList);
        if #relList == 0 then eff = nil; candSets = nil; end   -- nothing weightable
    end

    local picks = {};                                  -- label -> candidate index (nil = empty)
    local cnt = {};                                    -- setId -> pieces among picks + baseComposition
    for sid, n in pairs(baseCnt) do cnt[sid] = n; end
    -- Assignment wrapper: keeps the per-set piece counts incremental, O(1) per
    -- probe (a candidate's setIds list is almost always length 0 or 1). Counting
    -- is per LABEL with no uniqueness check -- two owned copies in Ring1/Ring2
    -- count as two, the verified server semantics (design #7.2).
    local function setPick(label, ci)
        local old = picks[label];
        if old == ci then return; end
        if candSets ~= nil then
            local cs = candSets[label];
            local oldIds = (old ~= nil) and cs[old] or nil;
            if oldIds ~= nil then
                for _, sid in ipairs(oldIds) do cnt[sid] = cnt[sid] - 1; end
            end
            local newIds = (ci ~= nil) and cs[ci] or nil;
            if newIds ~= nil then
                for _, sid in ipairs(newIds) do cnt[sid] = (cnt[sid] or 0) + 1; end
            end
        end
        picks[label] = ci;
    end

    local function totalScore()
        local t = 0;
        for wi, w in ipairs(wl) do
            local sum = base[wi];
            for _, label in ipairs(labels) do
                local ci = picks[label];
                if ci ~= nil then sum = sum + vecs[label][ci][wi]; end
            end
            -- Active set tiers land INSIDE the cap fold: bonuses share the cap
            -- budget with regular stats (capped Haste from a set is still capped).
            for si = 1, #relList do
                local sid = relList[si];
                local tv = tierVec[sid][cnt[sid] or 0];
                if tv ~= nil then sum = sum + tv[wi]; end
            end
            if w.cap ~= nil and sum > w.cap then sum = w.cap; end
            t = t + w.perUnit * sum;
        end
        return t;
    end
    local function conflicts(label, ci)
        if type(opts.conflict) ~= 'function' then return false; end
        local ref = pools[label][ci].ref;
        for _, other in ipairs(labels) do
            if other ~= label and picks[other] ~= nil then
                if opts.conflict(ref, pools[other][picks[other]].ref) == true then return true; end
            end
        end
        return false;
    end

    local EPS = 1e-6;
    local function climb()
        for _ = 1, 8 do
            local improved = false;
            for _, label in ipairs(labels) do
                local saved = picks[label];
                setPick(label, nil);
                local bestIdx, bestSc = nil, totalScore();  -- EMPTY is the tie-winning baseline
                for ci = 1, #pools[label] do
                    if not conflicts(label, ci) then
                        setPick(label, ci);
                        local sc = totalScore();
                        if sc > bestSc + EPS then bestSc = sc; bestIdx = ci; end
                    end
                end
                setPick(label, bestIdx);
                if bestIdx ~= saved then improved = true; end
            end
            if not improved then break; end
        end
    end
    climb();

    -- ---- set-seeded restarts (design #7.3, ADR 0011) ------------------------
    -- Single-slot hill climbing provably cannot ENTER a k-piece bonus whose
    -- pieces are each a solo loss (every single insertion scores <= 0). Restart
    -- from the converged baseline with a feasible set's pieces force-placed,
    -- climb again, and keep the result only on STRICT improvement -- monotone
    -- acceptance: the answer is never worse than the plain climb. Seeded pieces
    -- are not pinned; a seed that doesn't pay for itself is evicted by the climb
    -- and the restart dissolves back to the baseline answer.
    if eff ~= nil then
        local function snapshot()
            local s = {};
            for _, l in ipairs(labels) do s[l] = picks[l]; end
            return s;
        end
        local function restore(s)
            for _, l in ipairs(labels) do setPick(l, s[l]); end
        end
        -- Solo projected value, uncapped -- ordering / least-loss heuristics only
        -- (the true objective is always totalScore).
        local function soloVal(label, ci)
            local v, vec = 0, vecs[label][ci];
            for wi = 1, #wl do v = v + wl[wi].perUnit * vec[wi]; end
            return v;
        end
        -- Placement plan for one set against a reference assignment: (label, ci)
        -- options holding a piece, best candidate first, one per label, the
        -- least-losing incumbent as tiebreak, capped at the tier ceiling
        -- (alternate-piece lists can EXCEED it -- 37 shipped sets do).
        local function planFor(sid, refPicks)
            local options = {};
            for _, label in ipairs(labels) do
                for ci, sids in pairs(candSets[label]) do
                    for _, s in ipairs(sids) do
                        if s == sid then
                            local inc = refPicks[label];
                            options[#options + 1] = {
                                label = label, ci = ci,
                                val  = soloVal(label, ci),
                                loss = (inc ~= nil) and soloVal(label, inc) or 0,
                            };
                            break;
                        end
                    end
                end
            end
            table.sort(options, function(a, b)
                if a.val ~= b.val then return a.val > b.val; end
                if a.loss ~= b.loss then return a.loss < b.loss; end
                if a.label ~= b.label then return a.label < b.label; end
                return a.ci < b.ci;
            end);
            local plan, used, refs = {}, {}, {};
            local capPieces = 0;
            for c in pairs(tierVec[sid]) do capPieces = math.max(capPieces, c); end
            for _, o in ipairs(options) do
                if #plan >= capPieces then break; end
                if not used[o.label] then
                    local ref = pools[o.label][o.ci].ref;
                    local clash = false;
                    if type(opts.conflict) == 'function' then
                        for _, r2 in ipairs(refs) do
                            if opts.conflict(ref, r2) == true then clash = true; break; end
                        end
                    end
                    if not clash then
                        plan[#plan + 1] = o;
                        used[o.label] = true;
                        refs[#refs + 1] = ref;
                    end
                end
            end
            return plan, used;
        end
        local B0 = snapshot();
        local best, bestPicks = totalScore(), B0;
        -- Relevant sets by DESCENDING best-tier projected value (ascending setId
        -- ties): the hard seed caps then drop the least valuable sets, never
        -- arbitrary ones. Net-negative projections never seed.
        local ranked = {};
        for _, sid in ipairs(relList) do
            local top, topC = nil, 0;
            for c, v in pairs(tierVec[sid]) do
                if c > topC then topC = c; top = v; end
            end
            local val = 0;
            if top ~= nil then
                for wi = 1, #wl do val = val + wl[wi].perUnit * top[wi]; end
            end
            if val > EPS then ranked[#ranked + 1] = { sid = sid, val = val }; end
        end
        table.sort(ranked, function(a, b)
            if a.val ~= b.val then return a.val > b.val; end
            return a.sid < b.sid;
        end);
        local SEED_SINGLE_CAP, SEED_TOTAL_CAP = 6, 12;   -- hard deterministic ceilings
        local seeds = {};                                -- each: array of setIds
        local plans = {};                                -- sid -> { plan, used } against B0
        local nSingles = math.min(#ranked, SEED_SINGLE_CAP);
        for i = 1, nSingles do
            local sid = ranked[i].sid;
            local plan, used = planFor(sid, B0);
            plans[sid] = { plan = plan, used = used };
            seeds[#seeds + 1] = { sid };
        end
        for i = 1, nSingles do
            for j = i + 1, nSingles do
                if #seeds >= SEED_TOTAL_CAP then break; end
                local a, b = ranked[i].sid, ranked[j].sid;
                local disjoint = true;
                for l in pairs(plans[a].used) do
                    if plans[b].used[l] then disjoint = false; break; end
                end
                if disjoint then seeds[#seeds + 1] = { a, b }; end
            end
            if #seeds >= SEED_TOTAL_CAP then break; end
        end
        for _, seed in ipairs(seeds) do
            restore(B0);
            for _, sid in ipairs(seed) do
                for _, o in ipairs(plans[sid].plan) do
                    local ref = pools[o.label][o.ci].ref;
                    if type(opts.conflict) == 'function' then
                        -- one physical copy: a conflicting pick elsewhere yields
                        -- its slot (the climb refills it)
                        for _, other in ipairs(labels) do
                            if other ~= o.label and picks[other] ~= nil
                               and opts.conflict(ref, pools[other][picks[other]].ref) == true then
                                setPick(other, nil);
                            end
                        end
                    end
                    setPick(o.label, o.ci);
                end
            end
            local feasible = true;
            for _, sid in ipairs(seed) do
                if (cnt[sid] or 0) < minOf[sid] then feasible = false; break; end
            end
            if feasible then
                climb();
                local t = totalScore();
                if t > best + EPS then best = t; bestPicks = snapshot(); end
            end
        end
        restore(bestPicks);
    end

    return { picks = picks, total = totalScore() };
end

-- ---------------------------------------------------------------------------
-- M.pairLadders(cands, opts) -> chain1, chain2
-- Dynamic-mode ladders for a PAIRED slot (Ear1/Ear2, Ring1/Ring2), built
-- TOGETHER as the running top-2 of the level-sorted candidates. The old shape
-- -- stack every upgrade into slot 1's ladder, then bar slot 2 from everything
-- in it -- starved the second slot outright whenever each new piece beat the
-- last (field case: Curates' + Roundel earrings under Cure Potency weights
-- both laddered onto Ear1 and Ear2 stayed empty, so the pair never wore both).
-- Here each upgrade lands in whichever chain currently holds the WEAKER top,
-- so the two flattens together wear the best two distinct pieces owned at
-- EVERY level, not just the build level.
--
--   cands: { { ref=<opaque>, score=n, level=n, copies=n, id=?, name=? }, ... }
--     score  : weighted score at the build level -- computed by the CALLER;
--              this function never reads gear tables or the weight state
--     copies : owned count (default 1); 2+ lets one item occupy both slots
--     id/name: physical-identity keys -- same id OR same (case-insensitive)
--              name = same physical item, optimizePicks' legacy-duplicate rule
--   opts.pins: 0-2 cands elements (matched by identity) -- the set-level
--     optimizer's picks for the pair. A pin already topping a chain claims it
--     untouched; a leftover pin trims an unclaimed chain the way the single-
--     slot ladder cap does (rungs at/above its level give way, lower rungs
--     stay as leveling fallbacks, the pin is appended), and a single-copy pin
--     is stripped from the other chain so the pair stays disjoint at every
--     level. No pins = the ladders stand as built.
--
-- Returns two arrays of cands elements, level-ascending with strictly rising
-- scores, ready for independent best-by-level flattening. Deterministic, and
-- seeded at score 0: a slot is never padded with a piece that scores nothing.
-- ---------------------------------------------------------------------------
function M.pairLadders(cands, opts)
    opts = opts or {};
    local function copiesOf(c) return tonumber(c.copies) or 1; end
    local function samePhysical(a, b)
        if a == b then return true; end
        if a.id ~= nil and a.id == b.id then return true; end
        return a.name ~= nil and b.name ~= nil
           and string.lower(tostring(a.name)) == string.lower(tostring(b.name));
    end

    -- Instance expansion: an item owned twice may fill both slots of the pair.
    local inst = {};
    for _, c in ipairs(cands or {}) do
        if type(c) == 'table' and type(c.score) == 'number' then
            inst[#inst + 1] = c;
            if copiesOf(c) >= 2 then inst[#inst + 1] = c; end
        end
    end
    table.sort(inst, function(a, b)
        local la, lb = a.level or 0, b.level or 0;
        if la ~= lb then return la < lb; end
        if a.score ~= b.score then return a.score > b.score; end
        return tostring(a.name or a.ref) < tostring(b.name or b.ref);
    end);

    -- Running top-2. Ties send the upgrade to the FIRST chain (so a lone
    -- candidate fills slot 1); a single-copy item never enters both chains.
    local chains, tops = { {}, {} }, { 0, 0 };
    for _, c in ipairs(inst) do
        local w = (tops[1] <= tops[2]) and 1 or 2;
        if c.score > tops[w] then
            local dup = false;
            if copiesOf(c) < 2 then
                for _, o in ipairs(chains[3 - w]) do
                    if samePhysical(o, c) then dup = true; break; end
                end
            end
            if not dup then
                chains[w][#chains[w] + 1] = c;
                tops[w] = c.score;
            end
        end
    end

    -- Pin reconciliation (the joint optimizer's picks; ears are interchangeable,
    -- so match pins to chains as a SET before disturbing anything).
    local pins = opts.pins;
    if type(pins) == 'table' and #pins > 0 then
        local claimed, rest = {}, {};
        for _, p in ipairs(pins) do
            local hit = nil;
            for ci = 1, 2 do
                if claimed[ci] == nil and chains[ci][#chains[ci]] == p then hit = ci; break; end
            end
            if hit ~= nil then claimed[hit] = true; else rest[#rest + 1] = p; end
        end
        for _, p in ipairs(rest) do
            for ci = 1, 2 do
                if claimed[ci] == nil then
                    claimed[ci] = true;
                    local trimmed = {};
                    for _, o in ipairs(chains[ci]) do
                        if (o.level or 0) < (p.level or 0) and o ~= p then trimmed[#trimmed + 1] = o; end
                    end
                    trimmed[#trimmed + 1] = p;
                    chains[ci] = trimmed;
                    -- Disjointness sweep: the pin may have sat as a rung of the
                    -- OTHER chain -- a single copy lingering there would double-
                    -- equip at the levels where both flatten to it.
                    if copiesOf(p) < 2 then
                        local keep = {};
                        for _, o in ipairs(chains[3 - ci]) do
                            if not samePhysical(o, p) then keep[#keep + 1] = o; end
                        end
                        chains[3 - ci] = keep;
                    end
                    break;
                end
            end
        end
    end
    return chains[1], chains[2];
end

-- Segment emission shared by levelLadder and pairLevelLadders. segs = ordered
-- disjoint { ref, from, to }; lvOf[ref] = adoption level. Prefers the classic
-- chain (unique winners, no windows) whenever the plain flatten -- a ranged
-- entry live at this level owns its window, otherwise highest adoption wins,
-- exactly bestByLevel and the engine -- already lands every segment winner;
-- else each segment gets explicit windows (first opens at adoption, last stays
-- open-ended so the set keeps working above the build cap).
local function emitLadder(segs, cap, lvOf)
    local function flattenPick(entries, L)
        local best, bLv, bRank = nil, -1, -1;
        for _, e in ipairs(entries) do
            local lv = lvOf[e.ref];
            local rank = (e.minLevel ~= nil or e.maxLevel ~= nil) and 1 or 0;
            if lv <= L and L >= (e.minLevel or 0) and L <= (e.maxLevel or 999)
               and (rank > bRank or (rank == bRank and lv > bLv)) then
                best, bLv, bRank = e.ref, lv, rank;
            end
        end
        return best;
    end
    local function matchesSegs(entries)
        for _, sg in ipairs(segs) do
            if flattenPick(entries, sg.from) ~= sg.ref
               or flattenPick(entries, sg.to) ~= sg.ref then return false; end
        end
        return true;
    end

    local classic, seen = {}, {};
    for _, sg in ipairs(segs) do
        if not seen[sg.ref] then seen[sg.ref] = true; classic[#classic + 1] = { ref = sg.ref }; end
    end
    if matchesSegs(classic) then return classic; end

    local out = {};
    for i, sg in ipairs(segs) do
        local e = { ref = sg.ref };
        if i > 1 then e.minLevel = sg.from; end
        if sg.to < cap then e.maxLevel = sg.to; end
        out[#out + 1] = e;
    end
    return out;
end

-- Level-banded ladder for ONE slot (dynamic Auto-build): score candidates at every
-- level where any candidate's value can change -- adoption (item Level) plus its
-- level-scaling thresholds (levelstats.thresholds) -- then merge same-winner bands
-- into segments. A piece whose value DECAYS (Garrison Tunica +1: Refresh+1 dies
-- past Lv.50) gets an explicit window and the next-best piece takes over -- the
-- between-level-x-and-y entries the sets already support, assigned automatically.
-- When the classic chain (no windows, highest-Level-wins flatten) reproduces the
-- segment winners, it is emitted instead, so monotone slots keep today's output.
--
--   items: { { ref = <record>, level = N, breaks = { L1, L2, ... } or nil }, ... }
--   opts:  { cap = N, scoreAt = function(ref, L) -> number, joint = <ref> or nil }
--
-- Returns an ordered array of { ref, minLevel?, maxLevel? } ({} = nothing scores).
-- Joint rule mirrors the classic chain: segments at/above the joint pick's level
-- give way to it, lower ones stay as leveling fallbacks.
function M.levelLadder(items, opts)
    opts = opts or {};
    local cap = tonumber(opts.cap) or M.MAX_LEVEL or 75;
    local scoreAt = opts.scoreAt;
    if type(items) ~= 'table' or #items == 0 or type(scoreAt) ~= 'function' then return {}; end

    local lvOf = {};
    for _, it in ipairs(items) do lvOf[it.ref] = math.max(tonumber(it.level) or 0, 1); end

    -- Band starts: each candidate's adoption level + its in-range thresholds.
    local startSet = {};
    for _, it in ipairs(items) do
        local lv = lvOf[it.ref];
        if lv <= cap then
            startSet[lv] = true;
            for _, b in ipairs(it.breaks or {}) do
                b = tonumber(b);
                if b ~= nil and b > lv and b <= cap then startSet[b] = true; end
            end
        end
    end
    local starts = {};
    for s in pairs(startSet) do starts[#starts + 1] = s; end
    table.sort(starts);
    if #starts == 0 then return {}; end

    -- Winner per band, scored AT the band start (nothing changes inside a band).
    -- score > 0 to win (a 0-value item is never kept). Ties keep the previous
    -- band's winner (fewest segments), else the higher-Level item.
    local segs = {};   -- { ref, from, to }, level-ascending, disjoint
    for i, s in ipairs(starts) do
        local bandEnd = (i < #starts) and (starts[i + 1] - 1) or cap;
        local prev = (#segs > 0) and segs[#segs].ref or nil;
        local win, winSc, winLv = nil, 0, -1;
        for _, it in ipairs(items) do
            local lv = lvOf[it.ref];
            if lv <= s then
                local sc = tonumber(scoreAt(it.ref, s)) or 0;
                if sc > 0 and (sc > winSc
                   or (sc == winSc and win ~= prev and (it.ref == prev or lv > winLv))) then
                    win, winSc, winLv = it.ref, sc, lv;
                end
            end
        end
        if win ~= nil then
            if #segs > 0 and segs[#segs].ref == win and segs[#segs].to == s - 1 then
                segs[#segs].to = bandEnd;
            else
                segs[#segs + 1] = { ref = win, from = s, to = bandEnd };
            end
        elseif #segs > 0 then
            -- Winner-less band (everything scores 0 here): keep wearing the last
            -- piece that was worth anything -- unweighted stats (DEF) still count
            -- for something, and the classic chain never bared the slot either.
            segs[#segs].to = bandEnd;
        end
    end

    -- Joint trim: everything at/above the joint pick's adoption level yields.
    local joint = opts.joint;
    if joint ~= nil then
        local jlv = lvOf[joint] or 0;
        local kept = {};
        for _, sg in ipairs(segs) do
            if sg.from < jlv then
                if sg.to >= jlv then sg.to = jlv - 1; end
                kept[#kept + 1] = sg;
            end
        end
        if #kept > 0 and kept[#kept].ref == joint and kept[#kept].to == jlv - 1 then
            kept[#kept].to = cap;   -- contiguous with its own earlier window: one entry
        else
            kept[#kept + 1] = { ref = joint, from = math.max(jlv, 1), to = cap };
        end
        segs = kept;
    end
    if #segs == 0 then return {}; end
    return emitLadder(segs, cap, lvOf);
end

-- Level-banded PAIR ladders (Ear/Ring twin of levelLadder): at every band the
-- pair must wear the true TOP-2 by score-at-that-level, so a decaying earring
-- hands its slot over at the breakpoint instead of squatting on a stale score.
-- Chain assignment prefers continuity (an item stays on the chain that wears
-- it), so segments stay long; a single physical copy is never live on both
-- chains at the same level (a twin owned twice may be). Pins reconcile exactly
-- like pairLadders: a pin already topping a chain claims it untouched, a
-- leftover pin trims an unclaimed chain and is swept from the other.
--
--   cands: { { ref, name, id, level, copies, breaks }, ... }  (pairLadders'
--          shape plus breaks; the static score field is ignored)
--   opts:  { cap = N, scoreAt = function(ref, L) -> number, pins = {cand,...} }
--
-- Returns two ordered arrays of { ref, minLevel?, maxLevel? }.
function M.pairLevelLadders(cands, opts)
    opts = opts or {};
    local cap = tonumber(opts.cap) or M.MAX_LEVEL or 75;
    local scoreAt = opts.scoreAt;
    if type(cands) ~= 'table' or #cands == 0 or type(scoreAt) ~= 'function' then return {}, {}; end

    local function copiesOf(c) return tonumber(c.copies) or 1; end
    local function samePhysical(a, b)
        if a == b then return true; end
        if a.id ~= nil and a.id == b.id then return true; end
        return a.name ~= nil and b.name ~= nil
           and string.lower(tostring(a.name)) == string.lower(tostring(b.name));
    end

    local lvOf, startSet = {}, {};
    for _, c in ipairs(cands) do
        local lv = math.max(tonumber(c.level) or 0, 1);
        lvOf[c] = lv;
        if lv <= cap then
            startSet[lv] = true;
            for _, b in ipairs(c.breaks or {}) do
                b = tonumber(b);
                if b ~= nil and b > lv and b <= cap then startSet[b] = true; end
            end
        end
    end
    local starts = {};
    for s in pairs(startSet) do starts[#starts + 1] = s; end
    table.sort(starts);
    if #starts == 0 then return {}, {}; end

    local segsA, segsB = {}, {};
    local function lastRef(segs) return (#segs > 0) and segs[#segs].ref or nil; end
    local function extendOrAdd(segs, c, s, bandEnd)
        if c == nil then
            -- winner-less band for this chain: keep wearing the last piece
            if #segs > 0 then segs[#segs].to = bandEnd; end
        elseif #segs > 0 and segs[#segs].ref == c and segs[#segs].to == s - 1 then
            segs[#segs].to = bandEnd;
        else
            segs[#segs + 1] = { ref = c, from = s, to = bandEnd };
        end
    end

    for i, s in ipairs(starts) do
        local bandEnd = (i < #starts) and (starts[i + 1] - 1) or cap;
        local prevA, prevB = lastRef(segsA), lastRef(segsB);
        -- Top-2 at this band. Ties prefer the current holders (fewest segments),
        -- then the higher-Level item, then name -- deterministic.
        local function beats(c, sc, lv, bc, bsc, blv)
            if bc == nil then return true; end
            if sc ~= bsc then return sc > bsc; end
            local cPrev = (c == prevA or c == prevB);
            local bPrev = (bc == prevA or bc == prevB);
            if cPrev ~= bPrev then return cPrev; end
            if lv ~= blv then return lv > blv; end
            return tostring(c.name or c.ref) < tostring(bc.name or bc.ref);
        end
        local P, Psc, Plv = nil, 0, -1;
        for _, c in ipairs(cands) do
            if lvOf[c] <= s then
                local sc = tonumber(scoreAt(c.ref, s)) or 0;
                if sc > 0 and beats(c, sc, lvOf[c], P, Psc, Plv) then P, Psc, Plv = c, sc, lvOf[c]; end
            end
        end
        local Q, Qsc, Qlv = nil, 0, -1;
        if P ~= nil then
            -- second slot: a different physical, or the same one owned twice
            for _, c in ipairs(cands) do
                if lvOf[c] <= s and (not samePhysical(c, P) or copiesOf(c) >= 2) then
                    local sc = tonumber(scoreAt(c.ref, s)) or 0;
                    if sc > 0 and beats(c, sc, lvOf[c], Q, Qsc, Qlv) then
                        Q, Qsc, Qlv = c, sc, lvOf[c];
                    end
                end
            end
        end
        -- Chain assignment: continuity first, else the better scorer to chain 1.
        local a, b;
        if P ~= nil and Q ~= nil then
            if P == prevA or Q == prevB then a, b = P, Q;
            elseif P == prevB or Q == prevA then a, b = Q, P;
            else a, b = P, Q; end
        elseif P ~= nil then
            if P == prevB then b = P;
            elseif P == prevA then a = P;
            elseif prevA == nil and prevB ~= nil then a = P;
            elseif prevB == nil and prevA ~= nil then b = P;
            else a = P; end
        end
        extendOrAdd(segsA, a, s, bandEnd);
        extendOrAdd(segsB, b, s, bandEnd);
    end

    -- Pin reconciliation (the joint optimizer's picks; the two physical slots
    -- are interchangeable, so match pins to chains as a SET first).
    local pins = opts.pins;
    if type(pins) == 'table' and #pins > 0 then
        local segsPair = { segsA, segsB };
        local claimed, rest = {}, {};
        for _, p in ipairs(pins) do
            local hit = nil;
            for ci = 1, 2 do
                if claimed[ci] == nil and lastRef(segsPair[ci]) == p then hit = ci; break; end
            end
            if hit ~= nil then claimed[hit] = true; else rest[#rest + 1] = p; end
        end
        for _, p in ipairs(rest) do
            for ci = 1, 2 do
                if claimed[ci] == nil then
                    claimed[ci] = true;
                    local jlv = lvOf[p] or 1;
                    local kept = {};
                    for _, sg in ipairs(segsPair[ci]) do
                        if sg.from < jlv then
                            if sg.to >= jlv then sg.to = jlv - 1; end
                            kept[#kept + 1] = sg;
                        end
                    end
                    if #kept > 0 and kept[#kept].ref == p and kept[#kept].to == jlv - 1 then
                        kept[#kept].to = cap;
                    else
                        kept[#kept + 1] = { ref = p, from = math.max(jlv, 1), to = cap };
                    end
                    segsPair[ci] = kept;
                    -- A single-copy pin is swept from the OTHER chain (it would
                    -- double-equip where both flatten to it). Its windows fall to
                    -- the previous segment -- unless that piece is live on the
                    -- pin's chain there (the double-equip guard), then the gap
                    -- stays empty.
                    if copiesOf(p) < 2 then
                        local other, swept = segsPair[3 - ci], {};
                        for _, sg in ipairs(other) do
                            if samePhysical(sg.ref, p) then
                                if #swept > 0 then
                                    local prev = swept[#swept];
                                    local clash = false;
                                    for _, og in ipairs(segsPair[ci]) do
                                        if samePhysical(og.ref, prev.ref)
                                           and og.from <= sg.to and og.to >= sg.from then clash = true; break; end
                                    end
                                    if not clash then prev.to = sg.to; end
                                end
                            elseif #swept > 0 and swept[#swept].ref == sg.ref
                               and swept[#swept].to == sg.from - 1 then
                                swept[#swept].to = sg.to;
                            else
                                swept[#swept + 1] = sg;
                            end
                        end
                        segsPair[3 - ci] = swept;
                    end
                    break;
                end
            end
        end
        segsA, segsB = segsPair[1], segsPair[2];
    end

    -- Emit each chain independently (each physical slot flattens on its own),
    -- then unwrap to the caller's records.
    local function convert(entries)
        local out = {};
        for _, e in ipairs(entries) do
            out[#out + 1] = { ref = e.ref.ref, minLevel = e.minLevel, maxLevel = e.maxLevel };
        end
        return out;
    end
    return convert(#segsA > 0 and emitLadder(segsA, cap, lvOf) or {}),
           convert(#segsB > 0 and emitLadder(segsB, cap, lvOf) or {});
end

-- Resolve job/level from opts, falling back to the live player.
local function jobLevelFromOpts(opts)
    local job, level = opts.job, opts.level;
    if job == nil or level == nil then
        local pj, pl = M.getPlayerJobLevel();
        job = job or pj; level = level or pl;
    end
    return job, level;
end

-- ---------------------------------------------------------------------------
-- M.buildBestSet(opts) -> set        (opts.weights, opts.job, opts.level all optional)
-- Best set by the current (or supplied) stat weights.
-- ---------------------------------------------------------------------------
function M.buildBestSet(opts)
    opts = opts or {};
    local job, level = jobLevelFromOpts(opts);
    -- Level-75 preview: lift the item-Level cap only. Job is left untouched, so the
    -- job-eligibility filter (jobAllowed) still excludes gear your job can't wear.
    if M.buildAtMaxLevel == true then level = MAX_LEVEL; end
    local weights = opts.weights or activeWeights();
    -- Rank each slot's candidates, then optimize the SET as a whole under the
    -- weight caps (M.optimizePicks): a slot is filled only when it improves the
    -- capped set total, so cap budget goes to the pieces that bring the most
    -- alongside it, and redundant single-stat pieces stay home. Ear/Ring share a
    -- pool with a distinct-entry conflict rule.
    local effects = hasGfx and { setsOf = gfx.setsOf, setTier = gfx.setTier } or nil;
    -- Set relevance memo for the pool augmentation below: does ANY tier of this
    -- set move a weighted stat? (Probed through setTier; shipped tiers top out
    -- at 5 pieces, 16 is a safe ceiling.)
    local relMemo = {};
    local function setMatters(sid)
        if relMemo[sid] == nil then
            local rel = false;
            for c = 2, 16 do
                local d = gfx.setTier(sid, c);
                if d ~= nil and M.score(d, weights) ~= 0 then rel = true; break; end
            end
            relMemo[sid] = rel;
        end
        return relMemo[sid];
    end
    local pools = {};
    local function poolFor(slotKey)
        local ranked = rankSlot(slotKey, function(stats) return M.score(stats, weights); end, job, level);
        local p = {};
        for i, r in ipairs(ranked) do
            if i <= 20 then                            -- top 20 per slot is plenty...
                p[#p + 1] = { stats = r.stats, ref = r.entry, score = r.score };
            elseif effects ~= nil and r.entry.Id ~= nil then
                -- ...APPENDED (never replacing -- the augmentation is add-only)
                -- by any member of a weight-relevant gear set: a piece that is
                -- individually worthless can pay via its bonus, and the seeded
                -- restarts need it in the pool to try it (design #7.3a).
                local sids = gfx.setsOf(r.entry.Id);
                if sids ~= nil then
                    for _, sid in ipairs(sids) do
                        if setMatters(sid) then
                            p[#p + 1] = { stats = r.stats, ref = r.entry, score = r.score };
                            break;
                        end
                    end
                end
            end
        end
        if #p == 0 then return nil; end
        return p;
    end
    for _, s in ipairs(NESTED_SLOTS) do pools[s] = poolFor(s); end
    for _, s in ipairs(FLAT_SLOTS) do
        if DUAL_SLOTS[s] then
            local p = poolFor(s);
            pools[s .. '1'] = p;
            pools[s .. '2'] = p;
        else
            pools[s] = poolFor(s);
        end
    end
    local res = M.optimizePicks(pools, weights, {
        -- One physical item can't fill both paired slots: same record, same Id,
        -- or same NAME (legacy gear.lua duplicates). This builder reads gear.lua
        -- with no live bag counts, so it conservatively assumes one copy of
        -- everything -- genuinely-owned doubles are Auto-build's department.
        conflict = function(a, b)
            return a == b or (a.Id ~= nil and a.Id == b.Id)
                or string.lower(tostring(a.Name or '?')) == string.lower(tostring(b.Name or '??'));
        end,
        effects = effects,
    });
    local out = { slots = {}, order = {}, perSlot = {}, total = res.total,
                  job = job, level = level, mode = 'weights' };
    local ORDER = { 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'Ear1', 'Ear2',
                    'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' };
    for _, label in ipairs(ORDER) do
        local pool = pools[label];
        local ci = (pool ~= nil) and res.picks[label] or nil;
        if ci ~= nil then
            local c = pool[ci];
            out.slots[label] = c.ref.Name;
            out.order[#out.order + 1] = label;
            out.perSlot[label] = { item = c.ref.Name, score = c.score, level = c.ref.Level };
        end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- M.buildMaxStatSet(statKey, opts) -> set
-- Set that maximizes ONE raw stat (alias-summed), e.g. best Accuracy or STR set.
-- Deliberately SET-BLIND (ADR 0011): this greedy path is raw-single-stat by
-- design and owns the Range/Ammo legality rule; gear-set bonuses are credited
-- only in the optimizePicks paths. A set bonus can therefore never change
-- (and in particular never legalize) a Range/Ammo pairing here.
-- ---------------------------------------------------------------------------
function M.buildMaxStatSet(statKey, opts)
    opts = opts or {};
    local job, level = jobLevelFromOpts(opts);
    -- Level-75 preview: lift the item-Level cap only. Job is left untouched, so the
    -- job-eligibility filter (jobAllowed) still excludes gear your job can't wear.
    if M.buildAtMaxLevel == true then level = MAX_LEVEL; end
    statKey = canonStat(statKey);
    -- Only fill a slot with a piece that actually carries some of the stat; a slot
    -- whose best pick has 0 of it (nothing to maximize) is left empty, not padded.
    -- Uses a NON-ZERO gate (not > 0) so this maximizer keeps the raw-stat semantics
    -- untouched -- a stat stored as a negative value still counts as "has some".
    local set = buildSet(function(stats) return statValue(stats, statKey); end, job, level,
        function(score) return score ~= 0; end);
    set.mode = 'stat:' .. tostring(statKey);
    set.stat = statKey;
    return set;
end

-- ===========================================================================
-- Weight persistence:  <profile>\dlac\gearweights.lua  (return {...} module)
-- ===========================================================================

-- Built exactly like gearimport's stagingPath, so it lands in the same dlac
-- folder this module lives in, next to gear.lua.
-- The weights file of ANY character folder ('Name_1234'); the per-job export/
-- import path goes through here, so there is exactly one path rule.
local function weightsPathFor(charFolder)
    local install = safeCall(function() return AshitaCore:GetInstallPath(); end);
    if type(install) ~= 'string' or type(charFolder) ~= 'string' or charFolder == '' then return nil; end
    return string.format('%sconfig\\addons\\luashitacast\\%s\\dlac\\gearweights.lua', install, charFolder);
end

function M.weightsPath()
    -- gState inside a profile, else the party manager (dlac addon context).
    local name, id;
    if gState ~= nil and gState.PlayerName ~= nil and gState.PlayerId ~= nil then
        name, id = gState.PlayerName, gState.PlayerId;
    else
        pcall(function()
            local party = AshitaCore:GetMemoryManager():GetParty();
            name = party:GetMemberName(0);
            id   = party:GetMemberServerId(0);
            if name == '' then name = nil; end
        end);
    end
    if name == nil or id == nil then return nil; end
    return weightsPathFor(tostring(name) .. '_' .. tostring(id));
end

-- Validating deep-cleaners for weights-file data, shared by loadWeights and
-- the export/import paths (hoisted out of loadWeights 2026-07-19 -- one way
-- of reading these files, not two).
local function cleanTable(src)
    local clean = {};
    for k, w in pairs(src) do
        if type(k) == 'string' and type(w) == 'table' and type(w.perUnit) == 'number' then
            local cap = w.cap;
            if type(cap) ~= 'number' then cap = nil; end
            clean[canonStat(k)] = { perUnit = w.perUnit, cap = cap };
        end
    end
    return clean;
end
local function cleanMask(src)
    local m = {};
    for _, l in ipairs(src) do
        if type(l) == 'string' then m[l] = true; end   -- labels validated on use
    end
    return m;
end
local function cleanPrioList(src)
    local out = {};
    for _, e in ipairs(src) do
        if type(e) == 'table' and type(e.stat) == 'string' and e.stat ~= '' then
            local cap = tonumber(e.cap);
            out[#out + 1] = { stat = canonStat(e.stat),
                              cap = (cap ~= nil and cap > 0) and cap or nil };
        end
    end
    return out;
end

-- A decoded weights-file table -> validated store-shaped data, or nil for a
-- legacy flat file (nothing but the dead shared table -- dropped on sight).
-- result.shared / slotsShared / prioShared / mode are deliberately ignored.
local function parseWeightsData(result)
    if type(result) ~= 'table'
       or (type(result.shared) ~= 'table' and type(result.perSet) ~= 'table') then
        return nil;
    end
    local d = { perSet = {}, slotsPerSet = {}, named = {}, namedSlots = {},
                modePerSet = {}, prioPerSet = {}, prioNamed = {} };
    if type(result.perSet) == 'table' then
        for k, t in pairs(result.perSet) do
            if type(k) == 'string' and type(t) == 'table' then d.perSet[k] = cleanTable(t); end
        end
    end
    if type(result.slotsPerSet) == 'table' then
        for k, t in pairs(result.slotsPerSet) do
            if type(k) == 'string' and type(t) == 'table' then d.slotsPerSet[k] = cleanMask(t); end
        end
    end
    if type(result.named) == 'table' then
        for k, t in pairs(result.named) do
            if type(k) == 'string' and type(t) == 'table' then d.named[k] = cleanTable(t); end
        end
    end
    if type(result.namedSlots) == 'table' then
        for k, t in pairs(result.namedSlots) do
            if type(k) == 'string' and type(t) == 'table' and d.named[k] ~= nil then
                d.namedSlots[k] = cleanMask(t);
            end
        end
    end
    if type(result.modePerSet) == 'table' then
        for k, v in pairs(result.modePerSet) do
            if type(k) == 'string' and v == 'priority' then d.modePerSet[k] = 'priority'; end
        end
    end
    if type(result.prioPerSet) == 'table' then
        for k, t in pairs(result.prioPerSet) do
            if type(k) == 'string' and type(t) == 'table' then d.prioPerSet[k] = cleanPrioList(t); end
        end
    end
    if type(result.prioNamed) == 'table' then
        for k, t in pairs(result.prioNamed) do
            if type(k) == 'string' and type(t) == 'table' then d.prioNamed[k] = cleanPrioList(t); end
        end
    end
    return d;
end

-- Serialize the per-set weights and write it. Alphabetical order -> stable
-- diffs. Format: return { perSet = { ['JOB|Set'] = {...} }, slotsPerSet,
-- named/namedSlots, and the priority-mode sections (modePerSet/prioPerSet/
-- prioNamed -- ordered arrays). The shared sections older files carried are
-- gone (dead concept, Henrik 07-17); loadWeights DROPS them on sight.
-- Render store-shaped data ({perSet, slotsPerSet, named, namedSlots,
-- modePerSet, prioPerSet, prioNamed}) as the gearweights file text.
-- saveWeights feeds it the live stores; the per-job export feeds it a
-- filtered copy -- ONE writer for this format, not two.
local function renderWeightsFileText(d)
    local function rows(L, t, indent)
        local keys = {};
        for k in pairs(t) do keys[#keys + 1] = k; end
        table.sort(keys);
        for _, k in ipairs(keys) do
            local w = t[k];
            if type(w) == 'table' and type(w.perUnit) == 'number' then
                local capStr = (type(w.cap) == 'number') and tostring(w.cap) or 'nil';
                L[#L + 1] = string.format('%s[%q] = { perUnit = %s, cap = %s },', indent, k, tostring(w.perUnit), capStr);
            end
        end
    end
    local L = {
        '-- dlac gear stat weights  (auto-written by gearoptim.lua)',
        '-- Each stat scores perUnit points per point of the stat, up to cap; beyond',
        '-- the cap it adds nothing. Edit here or via  /dl weight <Stat> <perUnit> <cap>.',
        '-- perSet["JOB|SetName"] = that set\'s own tuning (every set carries its own).',
        'return {',
    };
    L[#L + 1] = '    perSet = {';
    local skeys = {};
    -- Empty tables are skipped: blank is the new-binding default (07-17), so
    -- rebinding recreates one -- persisting them would only bloat the file.
    for k, t in pairs(d.perSet) do
        if next(t) ~= nil then skeys[#skeys + 1] = k; end
    end
    table.sort(skeys);
    for _, sk in ipairs(skeys) do
        L[#L + 1] = string.format('        [%q] = {', sk);
        rows(L, d.perSet[sk], '            ');
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    -- Build-slot masks: arrays of ENABLED labels, sorted (stable diffs). A file
    -- from before this feature has no slots sections and loads with the default
    -- mask; a PRESENT empty array is a real "fill nothing" choice.
    local function maskRow(t)
        local on = {};
        for l in pairs(t) do on[#on + 1] = l; end
        table.sort(on);
        local q = {};
        for _, l in ipairs(on) do q[#q + 1] = string.format('%q', l); end
        return '{ ' .. table.concat(q, ', ') .. ' }';
    end
    L[#L + 1] = '    slotsPerSet = {';
    local mkeys = {};
    for k in pairs(d.slotsPerSet) do mkeys[#mkeys + 1] = k; end
    table.sort(mkeys);
    for _, mk in ipairs(mkeys) do
        L[#L + 1] = string.format('        [%q] = %s,', mk, maskRow(d.slotsPerSet[mk]));
    end
    L[#L + 1] = '    },';
    -- Named weight profiles ("Saved Sets" in the copy-from menu): the tunings
    -- you saved on purpose, independent of any job or set.
    L[#L + 1] = '    named = {';
    local nkeys = {};
    for k in pairs(d.named) do nkeys[#nkeys + 1] = k; end
    table.sort(nkeys);
    for _, nk in ipairs(nkeys) do
        L[#L + 1] = string.format('        [%q] = {', nk);
        rows(L, d.named[nk], '            ');
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    namedSlots = {';
    for _, nk in ipairs(nkeys) do
        if d.namedSlots[nk] ~= nil then
            L[#L + 1] = string.format('        [%q] = %s,', nk, maskRow(d.namedSlots[nk]));
        end
    end
    L[#L + 1] = '    },';
    -- Priority-list mode (its OWN store; point templates and priority lists
    -- never cross-load). Lists are ORDERED arrays -- order IS the data. Empty
    -- lists are skipped like empty per-set weight tables; a file from before
    -- this feature has none of these sections and loads as all-points.
    local function prioRows(t, indent)
        for _, e in ipairs(t) do
            L[#L + 1] = string.format('%s{ stat = %q%s },', indent, e.stat,
                (type(e.cap) == 'number') and (', cap = ' .. tostring(e.cap)) or '');
        end
    end
    L[#L + 1] = '    modePerSet = {';
    local mokeys = {};
    for k, v in pairs(d.modePerSet) do
        if v == 'priority' then mokeys[#mokeys + 1] = k; end
    end
    table.sort(mokeys);
    for _, mk in ipairs(mokeys) do
        L[#L + 1] = string.format('        [%q] = "priority",', mk);
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    prioPerSet = {';
    local pkeys = {};
    for k, t in pairs(d.prioPerSet) do
        if #t > 0 then pkeys[#pkeys + 1] = k; end
    end
    table.sort(pkeys);
    for _, pk in ipairs(pkeys) do
        L[#L + 1] = string.format('        [%q] = {', pk);
        prioRows(d.prioPerSet[pk], '            ');
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    prioNamed = {';
    local pnkeys = {};
    for k in pairs(d.prioNamed) do pnkeys[#pnkeys + 1] = k; end
    table.sort(pnkeys);
    for _, pk in ipairs(pnkeys) do
        L[#L + 1] = string.format('        [%q] = {', pk);
        prioRows(d.prioNamed[pk], '            ');
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '}';
    L[#L + 1] = '';
    return table.concat(L, '\n');
end

local function writeTextFile(path, text)
    local ok = safeCall(function()
        local f = io.open(path, 'w');
        if f == nil then return false; end
        f:write(text);
        f:close();
        return true;
    end);
    return ok == true;
end

local function liveWeightsData()
    return { perSet = M._perSet, slotsPerSet = M._slotsPerSet,
             named = M._named, namedSlots = M._namedSlots,
             modePerSet = M._modePerSet, prioPerSet = M._prioPerSet,
             prioNamed = M._prioNamed };
end

function M.saveWeights()
    local path = M.weightsPath();
    if path == nil then return false, 'profile path unavailable (not logged in?)'; end
    if not writeTextFile(path, renderWeightsFileText(liveWeightsData())) then
        return false, 'could not write ' .. tostring(path);
    end
    return true, path;
end

-- Load persisted weights, validating each row. Silently no-ops (returns false) if
-- the file is missing or malformed, leaving whatever is in memory. Older files'
-- shared sections (and pre-per-set flat files, which were ONLY a shared table)
-- are DROPPED -- the shared concept is dead (Henrik 07-17); per-set tuning,
-- masks, modes and both named stores load as saved.
function M.loadWeights()
    local path = M.weightsPath();
    if path == nil then return false, 'profile path unavailable'; end
    local chunk = safeCall(function() return loadfile(path); end);
    if chunk == nil then return false, 'no weights file'; end
    local ok, result = pcall(chunk);
    if not ok or type(result) ~= 'table' then return false, 'weights file did not return a table'; end

    local d = parseWeightsData(result);   -- the ONE validating reader for this format
    if d ~= nil then
        M._perSet      = d.perSet;
        M._slotsPerSet = d.slotsPerSet;
        M._named       = d.named;
        M._namedSlots  = d.namedSlots;
        M._modePerSet  = d.modePerSet;
        M._prioPerSet  = d.prioPerSet;
        M._prioNamed   = d.prioNamed;
    else
        -- Legacy FLAT file: it was nothing but the dead shared table -- drop it.
        M._perSet = {};
        M._slotsPerSet = {};
        M._named, M._namedSlots = {}, {};
        M._modePerSet = {};
        M._prioPerSet, M._prioNamed = {}, {};
    end
    -- Re-point the active tables through whatever binding was live before the load.
    local key = M._boundKey;
    M._boundKey = nil;                    -- force bindSetWeights to re-alias
    M._weights = UNBOUND_W;
    M._slots = M._slotsUnbound;
    M._prio = UNBOUND_PRIO;
    if key ~= nil then
        local j, s = string.match(key, '^([^|]+)|(.+)$');
        M.bindSetWeights(j, s);
    end
    return true, path;
end

-- Load persisted weights once per session, lazily. Pre-login the path won't resolve,
-- so we don't mark "loaded" and the next call retries. Never throws. The flag is set
-- BEFORE loading: loadWeights re-binds via bindSetWeights, which re-enters here.
local _weightsLoaded = false;
ensureWeightsLoaded = function()
    if _weightsLoaded then return; end
    if M.weightsPath() == nil then return; end   -- not logged in yet -> retry later
    _weightsLoaded = true;
    M.loadWeights();                              -- ok even if there's simply no file yet
end

-- ===========================================================================
-- Per-job weights export / import (the Profiles menu's selective export,
-- 2026-07-19). A job's weights are every per-set entry keyed '<JOB>|...'
-- (points, masks, modes, priority lists -- NOT the char-global named stores).
-- The payload text IS the gearweights format, produced and consumed by the
-- same renderer/parser the live file uses.
-- ===========================================================================

-- charFolder's weights data: the LIVE stores when it is (or resolves like)
-- the current character, else that character's file read through the one
-- validating parser. Returns data | nil.
local function weightsDataFor(charFolder)
    local pf = weightsPathFor(charFolder);
    if pf == nil or pf == M.weightsPath() then
        if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
        return liveWeightsData();
    end
    local chunk = safeCall(function() return loadfile(pf); end);
    if chunk == nil then return nil; end
    local ok, result = pcall(chunk);
    if not ok then return nil; end
    return parseWeightsData(result);
end

-- Copy `map`'s entries whose key starts with '<srcJob>|', re-prefixed to
-- '<dstJob>|'. Returns copies (cheap deep enough: values are re-rendered or
-- re-cleaned downstream, never shared with a live store).
local function rekeyJobEntries(map, srcJob, dstJob, out)
    local pre, n = srcJob .. '|', 0;
    for k, v in pairs(map or {}) do
        if type(k) == 'string' and k:sub(1, #pre) == pre then
            out[dstJob .. '|' .. k:sub(#pre + 1)] = v;
            n = n + 1;
        end
    end
    return n;
end

-- Render charFolder's weights for one job as importable gearweights text.
-- Returns text, setCount | nil, why.
function M.renderJobWeightsTextAt(charFolder, job)
    local d = weightsDataFor(charFolder);
    if d == nil then return nil, 'no weights file for ' .. tostring(charFolder); end
    local out = { perSet = {}, slotsPerSet = {}, named = {}, namedSlots = {},
                  modePerSet = {}, prioPerSet = {}, prioNamed = {} };
    rekeyJobEntries(d.perSet, job, job, out.perSet);
    rekeyJobEntries(d.slotsPerSet, job, job, out.slotsPerSet);
    rekeyJobEntries(d.modePerSet, job, job, out.modePerSet);
    rekeyJobEntries(d.prioPerSet, job, job, out.prioPerSet);
    -- Meaningful = at least one set with real weights or a real priority
    -- list (empty tables and bare masks are skipped by the renderer anyway).
    local sets = {};
    for k, t in pairs(out.perSet) do if next(t) ~= nil then sets[k] = true; end end
    for k, t in pairs(out.prioPerSet) do if #t > 0 then sets[k] = true; end end
    local n = 0;
    for _ in pairs(sets) do n = n + 1; end
    if n == 0 then return nil, 'no stat weights stored for ' .. tostring(job); end
    return renderWeightsFileText(out), n;
end

-- Import a weights payload (renderJobWeightsTextAt's output) into
-- charFolder's weights, re-keying '<srcJob>|Set' -> '<dstJob>|Set' (imports
-- may rename the job). Current character: merged into the LIVE stores and
-- saved through saveWeights; another character: their file is read, merged
-- and re-rendered -- the same parser and renderer either way.
-- Returns setCount | nil, why.
function M.importJobWeightsTextAt(charFolder, text, srcJob, dstJob)
    if type(text) ~= 'string' or type(srcJob) ~= 'string' or type(dstJob) ~= 'string' then
        return nil, 'bad arguments';
    end
    local chunk = (loadstring or load)(text, 'dlac-weights-import');
    if chunk == nil then return nil, 'weights payload does not parse'; end
    if setfenv ~= nil then setfenv(chunk, {}); end   -- data file: runs against nothing
    local ok, result = pcall(chunk);
    if not ok then return nil, 'weights payload errored'; end
    local d = parseWeightsData(result);
    if d == nil then return nil, 'not a dlac weights payload'; end

    local add = { perSet = {}, slotsPerSet = {}, modePerSet = {}, prioPerSet = {} };
    local n = 0;
    n = n + rekeyJobEntries(d.perSet, srcJob, dstJob, add.perSet);
    rekeyJobEntries(d.slotsPerSet, srcJob, dstJob, add.slotsPerSet);
    rekeyJobEntries(d.modePerSet, srcJob, dstJob, add.modePerSet);
    n = n + rekeyJobEntries(d.prioPerSet, srcJob, dstJob, add.prioPerSet);
    if n == 0 then return nil, 'payload holds no weights for ' .. tostring(srcJob); end

    local pf = weightsPathFor(charFolder);
    if pf == nil or pf == M.weightsPath() then
        -- The current character: merge live, save through the one writer.
        if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
        for k, v in pairs(add.perSet) do M._perSet[k] = v; end
        for k, v in pairs(add.slotsPerSet) do M._slotsPerSet[k] = v; end
        for k, v in pairs(add.modePerSet) do M._modePerSet[k] = v; end
        for k, v in pairs(add.prioPerSet) do M._prioPerSet[k] = v; end
        M.saveWeights();   -- may report "not logged in" headless; the merge itself stands
        return n;
    end
    -- Another character: read-merge-rewrite their file.
    local dst = weightsDataFor(charFolder) or { perSet = {}, slotsPerSet = {}, named = {}, namedSlots = {},
                                                modePerSet = {}, prioPerSet = {}, prioNamed = {} };
    for k, v in pairs(add.perSet) do dst.perSet[k] = v; end
    for k, v in pairs(add.slotsPerSet) do dst.slotsPerSet[k] = v; end
    for k, v in pairs(add.modePerSet) do dst.modePerSet[k] = v; end
    for k, v in pairs(add.prioPerSet) do dst.prioPerSet[k] = v; end
    if not writeTextFile(pf, renderWeightsFileText(dst)) then
        return nil, 'could not write ' .. tostring(pf);
    end
    return n;
end

-- ===========================================================================
-- Printing
-- ===========================================================================
local function printSet(set, label)
    if set == nil then print('[dlac] optim: nothing to show.'); return; end
    local jobStr = (set.job ~= nil and set.job ~= '') and set.job or '??';
    print(string.format('[dlac] %s set for %s Lv%s:', label or set.mode or 'best', jobStr, tostring(set.level)));
    if #set.order == 0 then
        print('  (no eligible gear found -- is gear.lua loaded, and are you the expected job/level?)');
    end
    for _, slot in ipairs(set.order) do
        local ps = set.perSlot[slot];
        print(string.format('  %-6s %-28s (score %s)', slot, tostring(ps.item), tostring(ps.score)));
    end
    print(string.format('[dlac] total score: %s', tostring(set.total)));
    print('[dlac] recommendation only -- paste picks into your sets.Dynamic lists to equip.');
end
M.printSet = printSet;

-- ===========================================================================
-- Command hook:  /dl (or /dlac)  weight | best | mp | maxmp
-- Additive: only these four subs are handled/blocked; everything else falls through
-- to utils.lua and gearimport.lua untouched.
-- ===========================================================================
local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'       or string.sub(raw, 1, 4)  == '/dl '       then return 5;  end
    return nil;
end

ashita.events.register('command', 'dlac-optim', function(e)
    local rawLower = string.lower(e.command);
    local start = argStart(rawLower);
    if start == nil then return; end

    -- Split the ORIGINAL-case tail so typed stat names keep their casing; the
    -- subcommand is matched case-insensitively.
    local args = {};
    for a in string.gmatch(string.sub(e.command, start), '%S+') do args[#args + 1] = a; end
    local sub = args[1] and string.lower(args[1]) or nil;
    if sub ~= 'weight' and sub ~= 'best' and sub ~= 'mp' and sub ~= 'maxmp' then
        return;   -- leave scan/preview/stage/commit/fix/dedupe/autostat/set/recalc/... alone
    end
    e.blocked = true;

    -- ---- /dl weight ... ----
    if sub == 'weight' then
        local a2 = args[2] and string.lower(args[2]) or nil;
        ensureWeightsLoaded();

        -- Every set carries its own tuning and there is no shared table anymore:
        -- without a bound set there is nothing to show or edit.
        if M._boundKey == nil then
            print('[dlac] no set selected -- weights live per set now. Open the GUI (/dl ui), pick a set on the Sets tab, then use /dl weight.');
            return;
        end

        if a2 == nil or a2 == 'show' then
            local whoseP = ' for set ' .. M._boundKey;
            if M.weightsMode() == 'priority' then
                local pl = M.getPrio();
                if #pl == 0 then
                    print('[dlac] priority mode with an empty list' .. whoseP .. '. Add stats on the Priority tab (dlac Stat Weights window).');
                else
                    print('[dlac] stat priorities' .. whoseP .. ' (top matters most):');
                    for i, e in ipairs(pl) do
                        print(string.format('  %2d. %-22s %s', i, e.stat,
                            (e.cap ~= nil) and ('cap ' .. tostring(e.cap)) or 'no cap'));
                    end
                end
                return;
            end
            local ws = M.getPointWeights();
            local keys = {};
            for k in pairs(ws) do keys[#keys + 1] = k; end
            table.sort(keys);
            local whose = whoseP;
            if #keys == 0 then
                print('[dlac] no stat weights set' .. whose .. '. Use:  /dl weight <Stat> <perUnit> <cap>  (e.g. /dl weight Accuracy 20 60)');
            else
                print('[dlac] stat weights' .. whose .. ' (perUnit points per point, up to cap):');
                for _, k in ipairs(keys) do
                    local w = ws[k];
                    print(string.format('  %-22s perUnit %s  cap %s', k, tostring(w.perUnit),
                        (w.cap ~= nil) and tostring(w.cap) or 'none'));
                end
            end
            return;
        end

        if a2 == 'clear' then
            local stat = args[3];
            if stat == nil then print('[dlac] usage:  /dl weight clear <Stat>'); return; end
            ensureWeightsLoaded();
            if M.clearWeight(stat) then
                local ok, err = M.saveWeights();
                print(string.format('[dlac] cleared weight for %s.%s', tostring(canonStat(stat)),
                    ok and '' or ('  (save failed: ' .. tostring(err) .. ')')));
            else
                print('[dlac] no weight set for ' .. tostring(stat) .. '.');
            end
            return;
        end

        -- set:  /dl weight <Stat> <perUnit> [cap]
        local stat    = args[2];
        local perUnit = tonumber(args[3]);
        local cap     = tonumber(args[4]);   -- optional
        if stat == nil or perUnit == nil then
            print('[dlac] usage:  /dl weight <Stat> <perUnit> <cap>   (e.g. /dl weight Accuracy 20 60)');
            return;
        end
        ensureWeightsLoaded();
        local ok, err = M.setWeight(stat, perUnit, cap);
        if not ok then print('[dlac] could not set weight: ' .. tostring(err)); return; end
        local sok, serr = M.saveWeights();
        print(string.format('[dlac] weight set:  %s = %s/point up to %s%s',
            tostring(canonStat(stat)), tostring(perUnit),
            (cap ~= nil) and tostring(cap) or 'no cap',
            sok and '' or ('  (save failed: ' .. tostring(serr) .. ')')));
        return;
    end

    -- ---- /dl best  |  /dl best <stat> ----
    if sub == 'best' then
        ensureWeightsLoaded();
        local statArg = args[2];
        if statArg ~= nil then
            printSet(M.buildMaxStatSet(statArg), 'max-' .. tostring(canonStat(statArg)));
        else
            local n = 0;
            for _ in pairs(M.getWeights()) do n = n + 1; end
            if n == 0 then
                if M._boundKey == nil then
                    print('[dlac] no set selected -- pick a set on the Sets tab (/dl ui) to build with its weights, or max one stat (/dl best <stat>).');
                else
                    print('[dlac] no weights set yet. Set some (/dl weight <Stat> <perUnit> <cap>) or max one stat (/dl best <stat>).');
                end
                return;
            end
            printSet(M.buildBestSet(), 'weighted-best');
        end
        return;
    end

    -- ---- /dl mp ----
    if sub == 'mp' then
        local cur, mx = M.getCurrentMP(), M.getMaxMP();
        if cur == nil and mx == nil then print('[dlac] MP unavailable (not logged in?).'); return; end
        print(string.format('[dlac] MP: %s / %s   (%s%%,  %s spent from max)',
            tostring(cur), tostring(mx), tostring(M.getMPP()), tostring(M.getMPLostToMax())));
        return;
    end

    -- ---- /dl maxmp [on|off|<n>] ----
    if sub == 'maxmp' then
        local a2 = args[2] and string.lower(args[2]) or nil;
        if a2 == 'on' or a2 == 'off' then
            M.setMaxMPEnabled(a2 == 'on');
            print('[dlac] maxMP swap mode ' .. (a2 == 'on' and 'ON' or 'OFF') .. '.');
            return;
        end
        if a2 ~= nil and tonumber(a2) ~= nil then
            M.setMaxMPThreshold(tonumber(a2));
            print(string.format('[dlac] maxMP swap threshold set to %s MP spent.', tostring(M._maxMP.threshold)));
            return;
        end

        local cfg = M._maxMP;
        print(string.format('[dlac] maxMP mode %s | threshold %s MP | potency stat %s',
            cfg.enabled and 'ON' or 'OFF', tostring(cfg.threshold), table.concat(cfg.potencyStat, '+')));
        local lost = M.getMPLostToMax();
        if lost ~= nil then
            print(string.format('[dlac] MP spent from max: %s  ->  %s', tostring(lost),
                (lost >= cfg.threshold) and 'past threshold (swap to potency)' or 'within threshold (keep max-MP)'));
        else
            print('[dlac] live MP unavailable right now.');
        end
        print('[dlac] per-slot swap recs need candidate sets: call M.recommendMaxMPSwaps{maxMPSet=..,potencySet=..} (GUI/profile).');
        return;
    end
end);

-- Best-effort startup load (guarded; a pre-login failure just defers to first use).
pcall(ensureWeightsLoaded);

return M;
