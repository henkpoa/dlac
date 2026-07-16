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
-- Off by default; the gearui "Build as lv.75" checkbox (or any caller) drives it.
local MAX_LEVEL = 75;
M.MAX_LEVEL = MAX_LEVEL;
M.buildAtMaxLevel = false;

-- In-memory weight table: canonicalStat -> { perUnit = number, cap = number|nil }.
-- M._weights is the ACTIVE table the editor/optimizer read. It aliases either the
-- SHARED table (no set bound; legacy files load here) or one entry of the per-set
-- memory, switched by M.bindSetWeights -- every set remembers its own weights.
M._weights  = M._weights or {};
M._shared   = M._shared or M._weights;   -- the no-set-bound table
M._perSet   = M._perSet or {};           -- '<JOB>|<SetName>' -> weights table
M._boundKey = nil;                       -- current binding, nil = shared
local ensureWeightsLoaded;   -- forward: defined with the persistence block below, but
                             -- every accessor must lazy-load -- the GUI reads through
                             -- these long before any /dl command would run (the fix
                             -- for "weights editor empty after every addon reload").

function M.getWeights()
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    return M._weights;
end

-- Set/replace one stat weight. perUnit is required; cap is optional (nil = no cap).
function M.setWeight(stat, perUnit, cap)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end   -- never edit-then-save over an unloaded file
    stat = canonStat(stat);
    if type(stat) ~= 'string' or stat == '' then return false, 'bad stat name'; end
    perUnit = tonumber(perUnit);
    if perUnit == nil then return false, 'perUnit must be a number'; end
    cap = tonumber(cap);   -- nil stays nil -> uncapped
    M._weights[stat] = { perUnit = perUnit, cap = cap };
    return true;
end

function M.clearWeight(stat)
    if ensureWeightsLoaded ~= nil then ensureWeightsLoaded(); end
    stat = canonStat(stat);
    if M._weights[stat] ~= nil then M._weights[stat] = nil; return true; end
    return false;
end

-- Per-set weight memory (Henrik): bind the ACTIVE weights to a set, so switching
-- sets never drags the previous set's tuning along. A never-bound set SEEDS its
-- copy from the shared table (continuity: existing weights don't vanish on the
-- upgrade); after that the set owns its copy and edits stick to IT only. job or
-- setName nil/'' (or the pre-login '?' job) binds back to the shared table.
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
    local t = M._shared;
    if key ~= nil then
        t = M._perSet[key];
        if t == nil then
            t = {};
            for k, w in pairs(M._shared) do t[k] = { perUnit = w.perUnit, cap = w.cap }; end
            M._perSet[key] = t;
        end
    end
    M._weights = t;
    return true;
end

-- The current binding key ('JOB|SetName'), or nil when the shared table is active.
function M.weightsBoundTo() return M._boundKey; end

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
        weights = M._weights;
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
-- only when the weapon's Type matches (arrows want a bow, not a gun). The other two
-- ammo kinds are handled differently:
--   * Throwing ammo (shuriken, pebble) fires from the Ammo slot itself, and the server
--     reads Range FIRST -- m_Weapons[SLOT_RANGED] ? SLOT_RANGED : SLOT_AMMO -- so any
--     Range weapon shadows it: Throwing ammo therefore demands an EMPTY Range.
--   * The unfirable stat sticks (Cinderstone, Morion Tathlum, Coiste Bodhar, pet food)
--     carry no AmmoType at all -- they only occupy the slot, so they COEXIST with any
--     non-Throwing Range weapon (a bow + stat stick is legal; ADR 0010). Only a
--     Throwing WEAPON (boomerang) reserves the ammo slot and cannot share it.
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
-- Range + Ammo are decided TOGETHER, not greedily slot-by-slot, because the two slots
-- constrain each other. Enumerate only LEGAL combinations and take the highest-scoring:
--   (Range, its matching fired ammo) | (Range, no ammo) | (empty Range, Throwing ammo)
--   | (non-Throwing Range, stat stick)     -- ADR 0010: a stat stick coexists with a bow
-- A stat stick (no AmmoType) USED to force Range EMPTY, to dodge a server bug where
-- GetRangedWeaponDelay adds the stick's delay (999) to ranged TP with no compatibility
-- check -- but that only bites if you actually FIRE, which a stat-stick set never does,
-- so a bow/xbow/gun + stat stick is now allowed to coexist (Henrik's ruling). Throwing
-- ammo still empties Range (the server shadows it), and fired ammo with no owned weapon
-- of its type still leaves Range empty.
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

    -- The best Range weapon a stat stick can SHARE the ammo slot with: anything but a
    -- Throwing weapon (a boomerang reserves Ammo outright and can't coexist with a
    -- stick). rangeR is score-sorted, so the first accepted non-Throwing entry is best.
    local sharing = nil;
    for _, p in ipairs(rangeR) do
        if ok(p) and p.entry.Type ~= 'Throwing' then sharing = p; break; end
    end

    if ok(rangeR[1]) then consider(rangeR[1], nil); end   -- Range alone, Ammo not worth wearing
    for _, a in ipairs(ammoR) do
        if ok(a) then
            local t = a.entry.AmmoType;
            if t ~= nil and RANGE_FIRED[t] then
                consider(firedBy[t], a);        -- fired ammo pairs with its matching weapon
            elseif t ~= nil then
                consider(nil, a);               -- Throwing/other typed ammo: any Range weapon shadows it -> Range empty
            else
                consider(sharing, a);           -- stat stick (no AmmoType): coexists with the best non-Throwing Range (ADR 0010)
            end
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
-- ---------------------------------------------------------------------------
function M.optimizePicks(pools, weights, opts)
    opts = opts or {};
    weights = weights or M._weights;
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

    -- Per-candidate value vector over wl, computed ONCE (the climb then only
    -- does sums), plus the fixed background from opts.baseStats.
    local vecs = {};
    for _, label in ipairs(labels) do
        local vv = {};
        for ci, cand in ipairs(pools[label]) do
            local vec = {};
            for wi, w in ipairs(wl) do
                local v = statValue(cand.stats, w.stat);
                if w.neg then v = -v; end
                vec[wi] = v;
            end
            vv[ci] = vec;
        end
        vecs[label] = vv;
    end
    local base = {};
    for wi = 1, #wl do base[wi] = 0; end
    if type(opts.baseStats) == 'table' then
        for _, st in ipairs(opts.baseStats) do
            for wi, w in ipairs(wl) do
                local v = statValue(st, w.stat);
                if w.neg then v = -v; end
                base[wi] = base[wi] + v;
            end
        end
    end

    local picks = {};                                  -- label -> candidate index (nil = empty)
    local function totalScore()
        local t = 0;
        for wi, w in ipairs(wl) do
            local sum = base[wi];
            for _, label in ipairs(labels) do
                local ci = picks[label];
                if ci ~= nil then sum = sum + vecs[label][ci][wi]; end
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
    for _ = 1, 8 do
        local improved = false;
        for _, label in ipairs(labels) do
            local saved = picks[label];
            picks[label] = nil;
            local bestIdx, bestSc = nil, totalScore();  -- EMPTY is the tie-winning baseline
            for ci = 1, #pools[label] do
                if not conflicts(label, ci) then
                    picks[label] = ci;
                    local sc = totalScore();
                    if sc > bestSc + EPS then bestSc = sc; bestIdx = ci; end
                end
            end
            picks[label] = bestIdx;
            if bestIdx ~= saved then improved = true; end
        end
        if not improved then break; end
    end
    return { picks = picks, total = totalScore() };
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
    local weights = opts.weights or M._weights;
    -- Rank each slot's candidates, then optimize the SET as a whole under the
    -- weight caps (M.optimizePicks): a slot is filled only when it improves the
    -- capped set total, so cap budget goes to the pieces that bring the most
    -- alongside it, and redundant single-stat pieces stay home. Ear/Ring share a
    -- pool with a distinct-entry conflict rule.
    local pools = {};
    local function poolFor(slotKey)
        local ranked = rankSlot(slotKey, function(stats) return M.score(stats, weights); end, job, level);
        local p = {};
        for i, r in ipairs(ranked) do
            if i > 20 then break; end                  -- top 20 per slot is plenty
            p[#p + 1] = { stats = r.stats, ref = r.entry, score = r.score };
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
function M.weightsPath()
    local install = safeCall(function() return AshitaCore:GetInstallPath(); end);
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
    if type(install) ~= 'string' or name == nil or id == nil then return nil; end
    return string.format('%sconfig\\addons\\luashitacast\\%s_%s\\dlac\\gearweights.lua',
        install, tostring(name), tostring(id));
end

-- Serialize the shared + per-set weights and write it. Alphabetical order ->
-- stable diffs. Format: return { shared = {...}, perSet = { ['JOB|Set'] = {...} } }
-- (loadWeights still reads the old flat stat->weight files as `shared`).
function M.saveWeights()
    local path = M.weightsPath();
    if path == nil then return false, 'profile path unavailable (not logged in?)'; end

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
        '-- shared = weights with no set selected; perSet["JOB|SetName"] = that set\'s own.',
        'return {',
        '    shared = {',
    };
    rows(L, M._shared, '        ');
    L[#L + 1] = '    },';
    L[#L + 1] = '    perSet = {';
    local skeys = {};
    for k in pairs(M._perSet) do skeys[#skeys + 1] = k; end
    table.sort(skeys);
    for _, sk in ipairs(skeys) do
        L[#L + 1] = string.format('        [%q] = {', sk);
        rows(L, M._perSet[sk], '            ');
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '}';
    L[#L + 1] = '';

    local ok = safeCall(function()
        local f = io.open(path, 'w');
        if f == nil then return false; end
        f:write(table.concat(L, '\n'));
        f:close();
        return true;
    end);
    if ok ~= true then return false, 'could not write ' .. tostring(path); end
    return true, path;
end

-- Load persisted weights, validating each row. Silently no-ops (returns false) if
-- the file is missing or malformed, leaving whatever is in memory. Understands both
-- the { shared, perSet } format and the old flat stat->weight files (-> shared).
function M.loadWeights()
    local path = M.weightsPath();
    if path == nil then return false, 'profile path unavailable'; end
    local chunk = safeCall(function() return loadfile(path); end);
    if chunk == nil then return false, 'no weights file'; end
    local ok, result = pcall(chunk);
    if not ok or type(result) ~= 'table' then return false, 'weights file did not return a table'; end

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
    if type(result.shared) == 'table' or type(result.perSet) == 'table' then
        M._shared = cleanTable(type(result.shared) == 'table' and result.shared or {});
        M._perSet = {};
        if type(result.perSet) == 'table' then
            for k, t in pairs(result.perSet) do
                if type(k) == 'string' and type(t) == 'table' then M._perSet[k] = cleanTable(t); end
            end
        end
    else
        M._shared = cleanTable(result);   -- legacy flat file
        M._perSet = {};
    end
    -- Re-point the active table through whatever binding was live before the load.
    local key = M._boundKey;
    M._boundKey = nil;                    -- force bindSetWeights to re-alias
    M._weights = M._shared;
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

        if a2 == nil or a2 == 'show' then
            ensureWeightsLoaded();
            local ws = M.getWeights();
            local keys = {};
            for k in pairs(ws) do keys[#keys + 1] = k; end
            table.sort(keys);
            local whose = (M._boundKey ~= nil) and (' for set ' .. M._boundKey) or ' (shared -- no set selected)';
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
                print('[dlac] no weights set yet. Set some (/dl weight <Stat> <perUnit> <cap>) or max one stat (/dl best <stat>).');
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
