--[[
    dlac/gear/gearoracle.lua -- THE Gear Oracle: one door for gear-fetch questions
    (issues #70/#71, PRD #69). A Central Service (architecture.md) in the ADDON state --
    callers ask the question, the plumbing is the oracle's problem.

    FETCH answers (issue #70), the two that were duplicated hardest:
        wornItem(equipSlot) -> { id, rec, extra, item } | nil   -- THE equipped-item resolution
        equipBags()         -> { 0, 8, 10, 11, 12, 13, 14, 15, 16 }  -- THE equip-eligible bag list

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

return M;
