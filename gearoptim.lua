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

-- In-memory weight table: canonicalStat -> { perUnit = number, cap = number|nil }.
M._weights = M._weights or {};

function M.getWeights() return M._weights; end

-- Set/replace one stat weight. perUnit is required; cap is optional (nil = no cap).
function M.setWeight(stat, perUnit, cap)
    stat = canonStat(stat);
    if type(stat) ~= 'string' or stat == '' then return false, 'bad stat name'; end
    perUnit = tonumber(perUnit);
    if perUnit == nil then return false, 'perUnit must be a number'; end
    cap = tonumber(cap);   -- nil stays nil -> uncapped
    M._weights[stat] = { perUnit = perUnit, cap = cap };
    return true;
end

function M.clearWeight(stat)
    stat = canonStat(stat);
    if M._weights[stat] ~= nil then M._weights[stat] = nil; return true; end
    return false;
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
    weights = weights or M._weights;
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
local function jobAllowed(entry, job)
    local jobs = entry.Jobs;
    if type(jobs) ~= 'table' then return true; end
    if job == nil or job == '' then return true; end     -- unknown job -> don't filter
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
            ranked[#ranked + 1] = { entry = entry, score = scoreFn(entry.Stats) };
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

    for _, slotKey in ipairs(slots) do
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
    return out;
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
    local weights = opts.weights or M._weights;
    -- Only fill a slot when its best pick makes a POSITIVE weighted contribution.
    -- If nothing in a slot carries any weighted stat, every candidate scores 0 (or
    -- worse, if it only has penalty stats), so the slot is left empty rather than
    -- padded with an irrelevant piece. DT/PDT/MDT already score POSITIVE for a
    -- beneficial (negative) value inside M.score, so useful mitigation still passes.
    local set = buildSet(function(stats) return M.score(stats, weights); end, job, level,
        function(score) return score > 0; end);
    set.mode = 'weights';
    return set;
end

-- ---------------------------------------------------------------------------
-- M.buildMaxStatSet(statKey, opts) -> set
-- Set that maximizes ONE raw stat (alias-summed), e.g. best Accuracy or STR set.
-- ---------------------------------------------------------------------------
function M.buildMaxStatSet(statKey, opts)
    opts = opts or {};
    local job, level = jobLevelFromOpts(opts);
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

-- Serialize M._weights and write it. Alphabetical order -> stable diffs.
function M.saveWeights()
    local path = M.weightsPath();
    if path == nil then return false, 'profile path unavailable (not logged in?)'; end

    local L = {
        '-- dlac gear stat weights  (auto-written by gearoptim.lua)',
        '-- Each stat scores perUnit points per point of the stat, up to cap; beyond',
        '-- the cap it adds nothing. Edit here or via  /dl weight <Stat> <perUnit> <cap>.',
        'return {',
    };
    local keys = {};
    for k in pairs(M._weights) do keys[#keys + 1] = k; end
    table.sort(keys);
    for _, k in ipairs(keys) do
        local w = M._weights[k];
        if type(w) == 'table' and type(w.perUnit) == 'number' then
            local capStr = (type(w.cap) == 'number') and tostring(w.cap) or 'nil';
            L[#L + 1] = string.format('    [%q] = { perUnit = %s, cap = %s },', k, tostring(w.perUnit), capStr);
        end
    end
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
-- the file is missing or malformed, leaving whatever is in memory.
function M.loadWeights()
    local path = M.weightsPath();
    if path == nil then return false, 'profile path unavailable'; end
    local chunk = safeCall(function() return loadfile(path); end);
    if chunk == nil then return false, 'no weights file'; end
    local ok, result = pcall(chunk);
    if not ok or type(result) ~= 'table' then return false, 'weights file did not return a table'; end

    local clean = {};
    for k, w in pairs(result) do
        if type(k) == 'string' and type(w) == 'table' and type(w.perUnit) == 'number' then
            local cap = w.cap;
            if type(cap) ~= 'number' then cap = nil; end
            clean[canonStat(k)] = { perUnit = w.perUnit, cap = cap };
        end
    end
    M._weights = clean;
    return true, path;
end

-- Load persisted weights once per session, lazily. Pre-login the path won't resolve,
-- so we don't mark "loaded" and the next command retries. Never throws.
local _weightsLoaded = false;
local function ensureWeightsLoaded()
    if _weightsLoaded then return; end
    if M.weightsPath() == nil then return; end   -- not logged in yet -> retry later
    M.loadWeights();                              -- ok even if there's simply no file yet
    _weightsLoaded = true;
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
            if #keys == 0 then
                print('[dlac] no stat weights set. Use:  /dl weight <Stat> <perUnit> <cap>  (e.g. /dl weight Accuracy 20 60)');
            else
                print('[dlac] stat weights (perUnit points per point, up to cap):');
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
