--[[
    dlac/weaponfilter.lua -- the pure weapon-type picker filter (issue #16, F2a; PRD #14).

    The Add-item picker (Sets tab) can narrow its VISIBLE candidates by weapon type: a
    multiselect "All + types" dropdown alongside the existing search / available /
    hide-travel filters. It changes only what is SHOWN, never which items are eligible
    (HARD RULE 6 / ADR 0006). This module is the pure, ImGui-free core the headless suite
    pins; gearui draws the dropdown and applies the predicate in the candidate loop.

    F2a wires the Main slot only (the 12 weapon types). `M.SLOTS` is the extension seam
    F2b (Sub) and F2c (Range / Ammo) grow into -- add a slot entry, nothing else changes.

      presentBuckets(cands, slot) -> { { key, label }, ... }  (only the buckets actually
        present among the slot's candidates, in canonical order -- never an empty bucket)
      visible(rec, marked, slot)  -> is this record shown under the marked type set?
        (marked = { typeKey = true, ... }; nil or empty = "All" = everything visible)

    Addon-state only -- never seeded into LAC. No Ashita, no ImGui, no file I/O, so the
    headless suite exercises it directly (tests AP*).
]]--

local M = {};

-- Main weapon-type buckets: the catalog / gear.lua `Type` key (the no-space form
-- gearimport writes via WEAPON_CATEGORY) -> the player-facing label. Labels are the 12
-- weapon types the issue lists. (Player-facing strings -- pending maintainer sign-off.)
local MAIN_ORDER = { 'HandToHand', 'Dagger', 'Sword', 'GreatSword', 'Axe', 'GreatAxe',
                     'Scythe', 'Polearm', 'Katana', 'GreatKatana', 'Club', 'Staff' };
local MAIN_LABEL = {
    HandToHand  = 'Hand-to-Hand', Dagger  = 'Dagger',   Sword    = 'Sword',
    GreatSword  = 'Great Sword',  Axe     = 'Axe',      GreatAxe = 'Great Axe',
    Scythe      = 'Scythe',       Polearm = 'Polearm',  Katana   = 'Katana',
    GreatKatana = 'Great Katana', Club    = 'Club',     Staff    = 'Staff',
};

-- Slot -> how a candidate record maps to a bucket key, the canonical bucket order, and the
-- key -> label map. THE EXTENSION SEAM: F2b/F2c add Sub / Range / Ammo entries here; the
-- rest of the module (and gearui's dropdown) is already slot-agnostic.
M.SLOTS = {
    Main = {
        order  = MAIN_ORDER,
        label  = MAIN_LABEL,
        bucket = function(rec) return rec.Type; end,   -- the weapon category
    },
};

-- The bucket a record falls in for a slot, or nil (not a filterable slot, or the record
-- carries no bucket -- e.g. a virtual entry with no Type). Never errors on odd input.
function M.bucketOf(rec, slot)
    local cfg = M.SLOTS[slot];
    if cfg == nil or type(rec) ~= 'table' then return nil; end
    local ok, b = pcall(cfg.bucket, rec);
    if not ok or b == nil then return nil; end
    return b;
end

-- The buckets actually present among a slot's candidates: canonical order first, then any
-- present-but-unknown bucket appended (sorted) so nothing a candidate carries silently
-- vanishes from the dropdown. No empty buckets -- only types the player owns for the slot.
function M.presentBuckets(cands, slot)
    local out = {};
    local cfg = M.SLOTS[slot];
    if cfg == nil or type(cands) ~= 'table' then return out; end
    local seen = {};
    for _, rec in ipairs(cands) do
        local b = M.bucketOf(rec, slot);
        if b ~= nil then seen[b] = true; end
    end
    local placed = {};
    for _, key in ipairs(cfg.order) do
        if seen[key] then
            out[#out + 1] = { key = key, label = cfg.label[key] or key };
            placed[key] = true;
        end
    end
    -- Defensive: a present bucket outside the canonical order (shouldn't happen for a
    -- clean catalog) trails alphabetically, so the list stays deterministic.
    local extra = {};
    for key in pairs(seen) do if not placed[key] then extra[#extra + 1] = key; end end
    table.sort(extra);
    for _, key in ipairs(extra) do out[#out + 1] = { key = key, label = key }; end
    return out;
end

-- Is this record shown under the marked type set? `marked` is a set { typeKey = true,... };
-- nil or empty = "All" = everything visible. A VIEW narrowing only -- callers must never
-- read it as eligibility (HARD RULE 6 / ADR 0006). A record whose bucket is nil (or in an
-- unfilterable slot) is hidden as soon as ANY specific type is marked.
function M.visible(rec, marked, slot)
    if type(marked) ~= 'table' then return true; end
    local any = false;
    for _ in pairs(marked) do any = true; break; end
    if not any then return true; end
    local b = M.bucketOf(rec, slot);
    return b ~= nil and marked[b] == true;
end

return M;
