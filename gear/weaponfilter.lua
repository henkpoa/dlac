--[[
    dlac/weaponfilter.lua -- the pure weapon-type picker filter (issue #16, F2a; PRD #14).

    The Add-item picker (Sets tab) can narrow its VISIBLE candidates by weapon type: a
    multiselect "All + types" dropdown alongside the existing search / available /
    hide-travel filters. It changes only what is SHOWN, never which items are eligible
    (HARD RULE 6 / ADR 0006). This module is the pure, ImGui-free core the headless suite
    pins; gearui draws the dropdown and applies the predicate in the candidate loop.

    F2a wired the Main slot (the 12 weapon types). F2b (issue #17) grows the same seam to
    Range (`Type`) and Ammo (`AmmoType`, absent = Trinket). F2c (issue #18) adds Sub:
    Shield, Grip, and the one-hander weapon types present in the pool. `M.SLOTS` is the
    extension seam: add a slot entry, nothing else changes -- gearui draws the same dropdown
    for any slot here.

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

-- Range buckets (issue #17): the catalog `Type` of a Range weapon -> player-facing label.
-- Guns and crossbows share the Marksmanship skill and one bucket. Instruments (String /
-- Wind / Handbell) and the Fishing Rod stand as their own buckets, offered only when owned.
-- (Player-facing strings -- pending maintainer sign-off.)
local RANGE_ORDER = { 'Archery', 'Marksmanship', 'Throwing', 'StringInstrument',
                      'WindInstrument', 'Handbell', 'FishingRod' };
local RANGE_LABEL = {
    Archery          = 'Bows',            Marksmanship = 'Guns & Crossbows',
    Throwing         = 'Throwing',        Handbell     = 'Handbell',
    StringInstrument = 'String Instrument', WindInstrument = 'Wind Instrument',
    FishingRod       = 'Fishing Rod',
};

-- Ammo buckets (issue #17): the catalog `AmmoType` -- what a Range weapon fires this ammo
-- AS -> player-facing label. Bolts and bullets both fire as Marksmanship and fold into one
-- bucket. An ammo-slot item with NO AmmoType (Cinderstone, Morion Tathlum) is fired by
-- nothing; it is its own Trinket bucket, keyed by the AMMO_TRINKET sentinel so it can never
-- collide with a real AmmoType. (Player-facing strings -- pending maintainer sign-off.)
local AMMO_TRINKET = '__trinket';
local AMMO_ORDER = { 'Archery', 'Marksmanship', 'Throwing', AMMO_TRINKET };
local AMMO_LABEL = {
    Archery       = 'Arrows',      Marksmanship = 'Bolts & Bullets',
    Throwing      = 'Throwables',  [AMMO_TRINKET] = 'Trinkets',
};

-- Sub buckets (issue #18): Shield, Grip, then the one-hander weapon types. Shields and grips
-- both carry catalog `Type = "Sub"` (grip-vs-shield falls out by name -- every grip/strap is
-- named "* Grip" / "* Strap", exactly as utils.classifySub decides); a one-hander keeps its
-- weapon `Type` (Dagger / Sword / ...). H2H and the 2H types are never Sub-capable, so they
-- are not listed -- present-but-unknown buckets still trail alphabetically, never vanish.
-- (Player-facing strings -- pending maintainer sign-off.)
local SUB_ORDER = { 'Shield', 'Grip', 'Dagger', 'Sword', 'Axe', 'Katana', 'Club' };
local SUB_LABEL = {
    Shield = 'Shield', Grip   = 'Grip',   Dagger = 'Dagger',
    Sword  = 'Sword',  Axe    = 'Axe',    Katana = 'Katana', Club = 'Club',
};

-- Bucket a Sub-slot record: mirror of utils.classifySub for shields/grips, but a one-hander
-- keeps its weapon Type instead of classifying to nil. A view narrowing only -- this NEVER
-- decides eligibility (that stays utils.subSlotAllowed's call at equip time; HARD RULE 6).
local function subBucket(rec)
    local t = rec.Type;
    if t == 'Grip' or t == 'Shield' then return t; end
    if t == 'Sub' then                                 -- catalog collapses shield + grip here
        local n = string.lower(tostring(rec.Name or ''));
        if n:find('grip', 1, true) ~= nil or n:find('strap', 1, true) ~= nil then return 'Grip'; end
        return 'Shield';
    end
    return t;                                           -- a one-hander weapon type, or nil
end

-- Slot -> how a candidate record maps to a bucket key, the canonical bucket order, and the
-- key -> label map. THE EXTENSION SEAM: add a slot entry here; the rest of the module (and
-- gearui's dropdown) is already slot-agnostic. F2a filled Main; F2b adds Range and Ammo;
-- F2c adds Sub.
M.SLOTS = {
    Main = {
        order  = MAIN_ORDER,
        label  = MAIN_LABEL,
        bucket = function(rec) return rec.Type; end,   -- the weapon category
    },
    Range = {
        order  = RANGE_ORDER,
        label  = RANGE_LABEL,
        bucket = function(rec) return rec.Type; end,   -- Archery / Marksmanship / Throwing / instrument / rod
    },
    Ammo = {
        order  = AMMO_ORDER,
        label  = AMMO_LABEL,
        -- AmmoType is the discriminator; absent = a Trinket (fired by nothing). Never nil,
        -- so every ammo-slot record buckets -- a stat stick can't fall through to "no bucket".
        bucket = function(rec) return rec.AmmoType or AMMO_TRINKET; end,
    },
    Sub = {
        order  = SUB_ORDER,
        label  = SUB_LABEL,
        bucket = subBucket,   -- Shield / Grip (by name) / the one-hander's weapon Type
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
