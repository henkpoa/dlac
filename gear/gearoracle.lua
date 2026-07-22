--[[
    dlac/gear/gearoracle.lua -- THE Gear Oracle: one door for gear-fetch questions
    (issue #70, PRD #69). A Central Service (architecture.md) in the ADDON state --
    callers ask the question, the plumbing is the oracle's problem. Two answers today,
    the two that were duplicated hardest:

        wornItem(equipSlot) -> { id, rec, extra, item } | nil   -- THE equipped-item resolution
        equipBags()         -> { 0, 8, 10, 11, 12, 13, 14, 15, 16 }  -- THE equip-eligible bag list

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

return M;
