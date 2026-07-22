--[[
    dlac/gear/gearoracle.lua -- THE Gear Oracle: one door for gear-fetch questions
    (issues #70/#71, PRD #69). A Central Service (architecture.md) in the ADDON state --
    callers ask the question, the plumbing is the oracle's problem.

    FETCH answers (issue #70), the two that were duplicated hardest:
        wornItem(equipSlot) -> { id, rec, extra, item } | nil   -- THE equipped-item resolution
        equipBags()         -> { 0, 8, 10, 11, 12, 13, 14, 15, 16 }  -- THE equip-eligible bag list

    EFFECTIVE-STATS answers (issue #74, PRD #69 Phase 2) -- the combination recipes
    the manifest builders hand-glued, now behind the one door (goldens byte-identical):
        stats(record, ctx)  -> effective item stats: the level-scaled resolver
                               (levelstats.effective at ctx.level) PLUS the private-
                               augment fold (ctx.augStats). ONE recipe -- the MaxMP/
                               HELM/fishing/craft ladders stop gluing it by hand.
        setStats(comp, ctx) -> full composition evaluation INCLUDING set bonuses; a
                               thin delegation to the reference set-bonus evaluator
                               (gear/geareffects.comboStats), which stays untouched.
        petStats(recOrId)   -> the PET-channel stats an item grants your pet
                               (data\petmods.lua -- API-invisible, SQL-sourced);
                               separate from stats() BY DESIGN (never folded).
        petScoreStats(recOrId) -> the pet channel FLATTENED for scoring: 'Pet:'-
                               namespaced keys ({ ['Pet:Haste'] = 6 }) the weights
                               system prices like any stat; per stat the scalar is
                               All + the best named type (a pet is exactly one type).
        petStatKeys()       -> sorted distinct stat keys across the pet data --
                               the weights editor's "stat menu" source.
    Plus the interpreter passthroughs the Sets core + worn panel read through the
    door instead of requiring the interpreters directly (the GRD5 allowlist #74
    empties): set membership (setsOf/setInfo/setTier), level-scaling introspection
    (scales/levelThresholds) and the augment reads (augStats/augLabels/wornAugStats/
    wornAugExtra/describeAugments/dumpAugments) -- ADR 0013's "augment description
    passthrough". FACADE, not absorb: the interpreters keep their homes and tests.

    ELIGIBILITY + IDENTITY answers (issue #71) -- a FACADE, not an absorb (PRD #69):
    the proven interpreters keep their homes; the oracle is the one door that fronts
    them, so no module re-states the rule and drifts:
        canWear(rec, job, level) -> main-job/level equip gate; DELEGATES to the engine
                                    module's addon-visible rule (dispatch.canWear). The
                                    two inline fallbacks (gearoptim, gearui) are GONE --
                                    their re-statements of "no job list means wearable"
                                    were the exact deduction drift this ends.
        anyJobCanWear(rec, jobLevels) -> the lockstyle any-job-at-current-level gate;
                                    DELEGATES to the addon-state gate module
                                    (gear/jobgate.canEquip), which keeps its home and its
                                    FAIL-OPEN semantics.
        lookup(idOrName)         -> "what is this item": the owned-record + catalog-record
                                    join (owned first, then the full catalog; id
                                    authoritative, name the fallback). ONE recipe; the
                                    enriched flattened indexes are injected by the surface
                                    that builds them (gearui) via setLookupSource.

    Claim-BLIND, permanently (PRD #69): every answer is a CAPABILITY ("could this
    character use this item") -- never permission ("may this slot change now, who wins").
    The Arbiter is the sole precedence authority; the two compose, they never contest.
    Method names use could-words (canWear), never may-words (canEquip).

    NEVER seeded into LAC. Per ADR 0002 the seeded engine (dispatch.lua) cannot require
    addon-folder modules, so it keeps its OWN worn-item decode and bag list as TWINS
    (dispatch.decodeEquipIndex / dispatch.AMMO_BAGS). This module is behaviour-identical
    to those twins BY CONSTRUCTION -- same arithmetic, one home -- and the parity-pin
    tests (tests/run_tests.lua, section OR) feed both this door and the engine twin a
    fixture matrix, failing CI and NAMING the twin on any divergence.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- THE equip-eligible bag list.
-- ---------------------------------------------------------------------------
-- Inventory (0) + the 8 Wardrobes (8, 10-16). This is the AVAILABILITY set
-- (ADR 0005): gear in Safe/Storage/Locker/Satchel is OWNED but not equippable
-- until moved here (the GUI shows such gear with a red name). ownership truth --
-- everything that can hold your property -- is the broader ALL_CONTAINERS list,
-- which lives in gearimport and is NOT this constant.
--
-- ONE home. gearimport.SCAN_CONTAINERS, the augment scan, useitem's readiness set
-- and (through ownedcache) the fishing heartbeat all source it from here; the
-- engine's twin is dispatch.AMMO_BAGS, pinned byte-for-byte to this list.
local EQUIP_BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 };
M.EQUIP_BAGS = EQUIP_BAGS;
function M.equipBags() return EQUIP_BAGS; end

-- ---------------------------------------------------------------------------
-- THE packed-index decode.
-- ---------------------------------------------------------------------------
-- GetEquippedItem returns a PACKED Index with no separate .Slot field in this
-- build: high byte = container, low byte = slot-in-container (equipmon's
-- arithmetic). PURE and side-effect free so the parity matrix can drive it. The
-- engine's twin is dispatch.decodeEquipIndex -- identical arithmetic; change one,
-- change both, or the OR-section parity pins fail and name the twin.
function M.decodeIndex(index)
    return math.floor(index / 256) % 256, index % 256;
end

-- Catalog/owned record for an item id, best effort (nil when the catalog is
-- absent -- headless -- or the id is unknown). Lazy + guarded: gearoracle must
-- load with no heavyweight deps so gearimport can source EQUIP_BAGS from it at
-- load time without a cycle.
local function recordFor(id)
    if id == nil or id == 0 or id == 65535 then return nil; end
    local rec = nil;
    pcall(function() rec = require('dlac\\gear\\catalogindex').rawById(id); end);
    return rec;
end

-- ---------------------------------------------------------------------------
-- THE equipped-item resolution.
-- ---------------------------------------------------------------------------
-- Decode the packed Index of the item worn in equipment slot 0-15 -> its
-- container item, and hand back everything the worn readers need:
--   { id    = the container item's Id,
--     rec   = its catalog/owned record (nil when unknown -- see recordFor),
--     extra = the raw Extra bytes (augments / enchant-charge timestamps),
--     item  = the raw container item (Flags, Count -- readiness reads these) }
-- Returns nil only when the slot is empty or unreadable. The id is handed back
-- RAW (0/65535 included): each worn reader keeps its own id guard so routing
-- through the oracle is behaviour-identical to the copies it replaces. Wrapped in
-- pcall -- a mid-zone GetEquippedItem can be nil (dispatch.lua's zoning guard).
function M.wornItem(equipSlot)
    local out = nil;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        if inv == nil then return; end
        local eitem = inv:GetEquippedItem(equipSlot);
        if eitem == nil or eitem.Index == 0 then return; end
        local cont, slotInCont = M.decodeIndex(eitem.Index);
        local item = inv:GetContainerItem(cont, slotInCont);
        if item == nil then return; end
        out = { id = item.Id, rec = recordFor(item.Id), extra = item.Extra, item = item };
    end);
    return out;
end

-- ---------------------------------------------------------------------------
-- ELIGIBILITY -- main-job/level equip gate (issue #71).
-- ---------------------------------------------------------------------------
-- Lazy + guarded, exactly like recordFor: the oracle must load with no heavyweight
-- deps (gearimport sources EQUIP_BAGS from it at load time). dispatch is an engine-
-- five, always present in BOTH Lua states -- but requiring it lazily keeps that
-- load-order promise. There is NO re-statement of the rule here: a missing engine
-- yields a conservative false (never a private copy of "no job list means wearable").
local function dispatchMod()
    local m = nil;
    pcall(function() m = require('dlac\\dispatch'); end);
    return (type(m) == 'table') and m or nil;
end

-- canWear(rec, job, level): can THIS main job, at THIS level, equip rec? THE central
-- rule lives once, in the engine module's addon-visible surface (dispatch.canWear:
-- main job only -- sub NEVER widens, field-verified on CatsEyeXI -- level gated on the
-- main level). The oracle is the only door modules ask; the inline fallbacks are gone.
function M.canWear(rec, job, level)
    local d = dispatchMod();
    if d == nil or type(d.canWear) ~= 'function' then return false; end
    return d.canWear(rec, job, level);
end

-- anyJobCanWear(rec, jobLevels): can ANY of the character's jobs, each at its CURRENT
-- level, wear rec? (the lockstyle-style gate -- the server's canEquipItemOnAnyJob).
-- DELEGATES to the addon-state gate module (gear/jobgate), which keeps its home, its
-- tests and its rule (an unknown record -- no Jobs -- passes; the server decides). The
-- nil-jobLevels FAIL-OPEN belongs to the CALLER (lockstyle short-circuits on a nil
-- levels read, the Save-gate lesson) -- the door copies no logic and adds none. A
-- missing gate MODULE fails OPEN here (returns true), never crashes.
function M.anyJobCanWear(rec, jobLevels)
    local jg = nil;
    pcall(function() jg = require('dlac\\gear\\jobgate'); end);
    if type(jg) ~= 'table' or type(jg.canEquip) ~= 'function' then return true; end
    return jg.canEquip(rec, jobLevels);
end

-- ---------------------------------------------------------------------------
-- IDENTITY -- "what is this item?" the owned+catalog join (issue #71).
-- ---------------------------------------------------------------------------
-- ONE recipe: owned record first (the character's real, enriched entry), then the
-- full catalog; id authoritative, name the fallback. The enriched flattened indexes
-- live where the enrichment happens (gearui builds them once); the oracle owns the
-- JOIN and takes those indexes through setLookupSource. Each resolver takes the key
-- (name keys ALREADY lower-cased by the oracle) and returns a record or nil.
local _lookupSrc = nil;
function M.setLookupSource(src)
    _lookupSrc = (type(src) == 'table') and src or nil;
end

function M.lookup(idOrName)
    if idOrName == nil or _lookupSrc == nil then return nil; end
    local s = _lookupSrc;
    if type(idOrName) == 'number' then
        local o = (type(s.ownedById) == 'function') and s.ownedById(idOrName) or nil;
        if o ~= nil then return o; end
        return (type(s.catalogById) == 'function') and s.catalogById(idOrName) or nil;
    end
    if type(idOrName) == 'string' then
        local ln = string.lower(idOrName);
        local o = (type(s.ownedByName) == 'function') and s.ownedByName(ln) or nil;
        if o ~= nil then return o; end
        return (type(s.catalogByName) == 'function') and s.catalogByName(ln) or nil;
    end
    return nil;
end

-- ---------------------------------------------------------------------------
-- EFFECTIVE STATS -- the combination recipes (issue #74, PRD #69 Phase 2).
-- ---------------------------------------------------------------------------
-- The stat interpreters the oracle fronts. Lazy + guarded exactly like recordFor
-- / dispatchMod: the oracle must load with no heavyweight deps (gearimport sources
-- EQUIP_BAGS from it at load time). Required FRESH each call, NEVER cached in an
-- upvalue -- so a test that swaps package.loaded (the golden harness stubs the
-- augment decoder) is honoured, and no interpreter is pulled in until a stat
-- question is actually asked. ADR 0013 ruling 1 (facade, not absorb): the
-- interpreters keep their homes, tests and field-tuned math; the oracle only joins
-- level-scaling to the augment fold and fronts the set-bonus evaluator.
local function interp(path)
    local m = nil;
    pcall(function() m = require(path); end);
    return (type(m) == 'table') and m or nil;
end
local function levelstats()  return interp('dlac\\data\\levelstats');   end
local function geareffects() return interp('dlac\\gear\\geareffects');  end
local function augmod()      return interp('dlac\\feature\\augments');  end
local function petmods()     return interp('dlac\\data\\petmods');      end

-- stats(rec, ctx): the effective item stats for THIS character right now -- the
-- level-scaled resolver (levelstats.effective at ctx.level) PLUS the private-augment
-- fold (ctx.augStats = { itemId -> { statKey -> delta } }, optional; folded per Id
-- exactly like comboStats). ONE recipe, replacing the hand-glue the manifest builders
-- carried. Copy-on-write (the levelstats.apply discipline: never mutate rec.Stats) --
-- a FRESH table only when an augment delta actually lands, otherwise the resolver's
-- own (zero-copy) return. Returns nil for a non-table rec, and the level-scaled base
-- (possibly nil) when no augment applies -- each caller keeps its own type guard, so
-- routing through the oracle is behaviour-identical to the glue it replaces.
function M.stats(rec, ctx)
    if type(rec) ~= 'table' then return nil; end
    local level = (type(ctx) == 'table') and ctx.level or nil;
    local ls = levelstats();
    local base;
    if ls ~= nil and type(ls.effective) == 'function' then
        base = ls.effective(rec, level);
    else
        base = rec.Stats;
    end
    local augs = (type(ctx) == 'table' and type(ctx.augStats) == 'table') and ctx.augStats or nil;
    local a = (augs ~= nil and rec.Id ~= nil) and augs[rec.Id] or nil;
    if type(a) ~= 'table' then return base; end     -- zero-copy: nothing to fold
    local out = {};
    if type(base) == 'table' then
        for k, v in pairs(base) do out[k] = v; end
    end
    for k, v in pairs(a) do
        if type(v) == 'number' then out[k] = (out[k] or 0) + v; end
    end
    return out;
end

-- petStats(recOrId): the PET-CHANNEL stats of an item -- what wearing it grants
-- YOUR PET ("Wyvern: HP+10%"), from data\petmods.lua (generated off the server's
-- item_mods_pet table; the live API never serializes that channel, so this data
-- lives BESIDE catalog Stats and no API-fed path can answer it). Returns the raw
-- { PetTypeName -> { statKey -> value } } table (pet names = the server's
-- PetModType enum, 'All' = every pet type) or nil. DELIBERATELY a separate answer
-- from stats(): pet-channel values must never fold into master stats (wyvern HP
-- is not your HP), and the golden gate pins stats() byte-identical. Display
-- composition (labels, ordering, token budget) stays with the presenter
-- (gear/gearfmt.petLines) -- the oracle answers, it does not format.
function M.petStats(recOrId)
    local id = (type(recOrId) == 'table') and recOrId.Id or recOrId;
    if type(id) ~= 'number' then return nil; end
    local pm = petmods();
    if pm == nil then return nil; end
    local t = pm[id];
    return (type(t) == 'table') and t or nil;
end

-- petScoreStats(recOrId): the pet channel FLATTENED for the weights system --
-- one { ['Pet:'..statKey] = value } map per item, or nil when the item grants
-- nothing to pets. The 'Pet:' namespace is the whole point: pet values enter
-- the same scoring map as master stats WITHOUT ever colliding with them, so
-- the petStats ruling (wyvern HP is not your HP) survives pricing. Per stat
-- the context-free scalar is All + the BEST named type: on the server a pet
-- receives All PLUS its own type's mods, and a pet is exactly ONE type, so
-- summing across named types would credit mutually exclusive pets; max is the
-- most this item can do for a single pet (exact whenever one named type
-- carries the stat -- the overwhelming case in the data).
function M.petScoreStats(recOrId)
    local pets = M.petStats(recOrId);
    if pets == nil then return nil; end
    local best = {};   -- statKey -> best named-type value
    for ptype, st in pairs(pets) do
        if ptype ~= 'All' and type(st) == 'table' then
            for k, v in pairs(st) do
                if type(v) == 'number' and (best[k] == nil or v > best[k]) then best[k] = v; end
            end
        end
    end
    local out = {};
    if type(pets.All) == 'table' then
        for k, v in pairs(pets.All) do
            if type(v) == 'number' then out['Pet:' .. k] = v; end
        end
    end
    for k, v in pairs(best) do
        local nk = 'Pet:' .. k;
        out[nk] = (out[nk] or 0) + v;
    end
    if next(out) == nil then return nil; end
    return out;
end

-- petStatKeys(): the sorted, distinct RAW stat keys appearing anywhere in the
-- pet data -- the weights editor's "add stat" menu asks this to list exactly
-- the pet family the data can actually deliver (prefix 'Pet:' before use as a
-- weight key). SECOND return: { statKey -> sorted pet-type names carrying it }
-- ("which pets does HPP reach?") -- the menu folds those into its search terms,
-- so typing "wyvern" surfaces Pet:HP% (Henrik's field instinct, 07-22). Fresh
-- walk each call like every oracle answer; the caller memoizes.
function M.petStatKeys()
    local pm = petmods();
    if pm == nil then return {}, {}; end
    local seen, out, typeSets = {}, {}, {};
    for _, pets in pairs(pm) do
        if type(pets) == 'table' then
            for ptype, st in pairs(pets) do
                if type(st) == 'table' and type(ptype) == 'string' then
                    for k in pairs(st) do
                        if type(k) == 'string' then
                            if not seen[k] then
                                seen[k] = true; out[#out + 1] = k; typeSets[k] = {};
                            end
                            typeSets[k][ptype] = true;
                        end
                    end
                end
            end
        end
    end
    table.sort(out);
    local types = {};
    for k, set in pairs(typeSets) do
        local l = {};
        for t in pairs(set) do l[#l + 1] = t; end
        table.sort(l);
        types[k] = l;
    end
    return out, types;
end

-- setStats(composition, ctx): the FULL composition evaluation -- every piece's
-- effective stats summed, active set-bonus tiers folded, the caller's augment deltas
-- applied (ctx.augStats). A THIN delegation to the set-bonus composition evaluator
-- (gear/geareffects.comboStats), which stays THE reference interpreter, untouched.
-- Returns geareffects' { stats = {...}, setBonuses = {...} } shape, or nil when the
-- evaluator is unavailable (the caller keeps its pre-P1 per-item-sum fallback).
function M.setStats(composition, ctx)
    local g = geareffects();
    if g == nil or type(g.comboStats) ~= 'function' then return nil; end
    return g.comboStats(composition, ctx);
end

-- Presence predicates -- the door's answer to the load-time has.aug/lscale/gfx flags
-- the UI kept when it required the interpreters itself.
function M.hasLevelScaling() return levelstats() ~= nil; end
function M.hasAugments()     return augmod() ~= nil; end
function M.hasSetStats()
    local g = geareffects();
    return g ~= nil and type(g.comboStats) == 'function';
end

-- Level-scaling introspection (the Sets tab's "scales with level" markers +
-- threshold ladders), fronting levelstats.has / levelstats.thresholds.
function M.scales(itemId)
    local ls = levelstats();
    if ls == nil or type(ls.has) ~= 'function' then return false; end
    return ls.has(itemId) == true;
end
function M.levelThresholds(itemId)
    local ls = levelstats();
    if ls == nil or type(ls.thresholds) ~= 'function' then return nil; end
    return ls.thresholds(itemId);
end

-- Set membership (the optimizer seam opts.effects + the Sets/hover tier ladders),
-- fronting geareffects.setsOf / setInfo / setTier. Behaviour-identical to the
-- interpreter (nil when the set data is unavailable).
function M.setsOf(itemId)
    local g = geareffects();
    if g == nil or type(g.setsOf) ~= 'function' then return nil; end
    return g.setsOf(itemId);
end
function M.setInfo(setId)
    local g = geareffects();
    if g == nil or type(g.setInfo) ~= 'function' then return nil; end
    return g.setInfo(setId);
end
function M.setTier(setId, count)
    local g = geareffects();
    if g == nil or type(g.setTier) ~= 'function' then return nil; end
    return g.setTier(setId, count);
end

-- Augment passthroughs (ADR 0013's "augment description passthrough") -- the owned-
-- copy stat map + label list, the worn totals, the per-slot worn Extra decode + its
-- readable description, and the shareable dump. The decoder keeps its home
-- (feature/augments); the oracle is the one door the UI asks so no surface re-requires
-- it. Each is nil/no-op-safe when the decoder is unavailable (headless).
function M.augStats()
    local a = augmod();
    if a == nil or type(a.ownedAugStats) ~= 'function' then return nil; end
    return a.ownedAugStats();
end
function M.augLabels()
    local a = augmod();
    if a == nil or type(a.ownedAugments) ~= 'function' then return nil; end
    return a.ownedAugments();
end
function M.wornAugStats()
    local a = augmod();
    if a == nil or type(a.wornStats) ~= 'function' then return nil; end
    return a.wornStats();
end
function M.wornAugExtra(equipSlot)
    local a = augmod();
    if a == nil or type(a.slotExtra) ~= 'function' then return nil; end
    return a.slotExtra(equipSlot);
end
function M.describeAugments(extra)
    local a = augmod();
    if a == nil or type(a.describe) ~= 'function' then return nil; end
    return a.describe(extra);
end
function M.dumpAugments()
    local a = augmod();
    if a == nil or type(a.dumpToFile) ~= 'function' then return nil, nil, nil; end
    return a.dumpToFile();
end

return M;
