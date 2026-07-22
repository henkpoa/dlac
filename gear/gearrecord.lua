--[[
    dlac/gearrecord.lua -- the Owned-gear record rules, in ONE place.

    An owned record (gear.lua entry: Name/Id/Level/Type/OneHanded/Count/RSlot/
    AmmoType/Model/Stats/...) is an interface consumed by the GUI, the optimizer,
    gearcheck AND the equip-time engine -- which reads the FILE raw in LAC's Lua
    state with no catalog, so pairing/conflict facts must be stamped to disk
    (ADR 0006/0010) and the GUI's in-memory view must be enriched from the
    catalog at load. Before this module those rules were re-encoded per site
    (importer fresh write, /dl fix backfill, gearui enrich, gearexport, the
    weapon-type filter), and every silently-missed stamp was a field bug: the
    invisible spaced-Type Savagery, the reserved-slot flap, the duplicate-entry
    storm. The rules live here now; the call sites keep their I/O mechanics.

    Everything is pure (no Ashita, no ImGui, no file IO) -- tests REC* pin each
    rule. Addon-state only -- never seeded into LAC; the engine-side mirrors of
    these decisions (utils.classifySub, dispatch.reservedDrops) stay engine-owned.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- Canonical Type vocabulary. gear.lua and the catalog spell weapon/range types
-- in the no-space form (WEAPON_CATEGORY / RANGE_CATEGORY at import); legacy
-- files carry display forms ('Great Axe', 'Hand-to-Hand', bare 'String') from
-- early vocabularies, and a scan never rewrites an existing entry -- so every
-- consumer must resolve spellings through ONE normalizer or drift makes gear
-- invisible (field case 2026-07-18: Mindie's 'Great Axe' Savagery vanished
-- under the GreatAxe filter while name search still found it).
-- ---------------------------------------------------------------------------
M.TYPES = {
    -- Main weapon categories
    'HandToHand', 'Dagger', 'Sword', 'GreatSword', 'Axe', 'GreatAxe',
    'Scythe', 'Polearm', 'Katana', 'GreatKatana', 'Club', 'Staff',
    -- Range categories (instruments and rods carry a skill but no damage)
    'Archery', 'Marksmanship', 'Throwing',
    'StringInstrument', 'WindInstrument', 'Handbell', 'FishingRod',
    -- Sub vocabulary ('Sub' is the catalog's collapsed shield+grip label)
    'Shield', 'Grip', 'Sub',
};
local TYPE_ALIAS = { string = 'StringInstrument' };   -- legacy Range oddity (bare 'String')

function M.normKey(s) return string.lower((tostring(s):gsub('%W', ''))); end

local CANON = {};
for _, k in ipairs(M.TYPES) do CANON[M.normKey(k)] = k; end
for a, k in pairs(TYPE_ALIAS) do CANON[a] = k; end

-- Canonical spelling for a Type value; unknown types pass through untouched
-- (defensive: an unknown bucket must stay visible, never vanish).
function M.canonType(t)
    if t == nil then return nil; end
    return CANON[M.normKey(t)] or t;
end

-- The Type an owned record should carry, given the catalog's: absent takes the
-- catalog's; a LEGACY spelling of the same type heals to the catalog key; a
-- genuinely different owned Type wins (owned overrides, catalog fills).
function M.healType(ownedType, catType)
    if ownedType == nil then return catType; end
    if catType ~= nil and ownedType ~= catType
       and M.normKey(ownedType) == M.normKey(catType) then
        return catType;
    end
    return ownedType;
end

-- The OneHanded flag a record should carry given its Type: HandToHand pins
-- FALSE -- H2H occupies both hands (the server knocks even grips off an H2H
-- main; ADR 0006 addendum 2026-07-22) -- everything else keeps the given
-- value (false and nil pass through intact). Exists because the flag LIES in
-- the wild for H2H: apicrawl's ONE set stamped the catalog true (fixed
-- locally 2026-07-22, ships with the next crawl) and /dl fix propagated it
-- into gear.lua files. Every stamp this module's callers write goes through
-- here, and computeFixes corrects a wrong stamped value in place
-- (machine-owned BOTH ways, the RSlot precedent). Readers ALSO refuse H2H by
-- Type (utils.subSlotAllowed isH2H + mirrors), so a stamp not yet corrected
-- stays inert.
function M.healOneHanded(recType, oneHanded)
    local k = M.normKey(recType or '');
    if k == 'handtohand' or k == 'h2h' then return false; end
    return oneHanded;
end

-- 'Grip' for grips/straps, else 'Shield' -- a Sub-only item is one or the other,
-- and every grip/strap is named "* Grip" / "* Strap". GUI-side mirror of the
-- engine's utils.classifySub (which stays engine-owned: the seeded state cannot
-- require addon modules).
function M.subTypeFromName(name)
    local n = string.lower(tostring(name or ''));
    if n:find('grip', 1, true) ~= nil or n:find('strap', 1, true) ~= nil then return 'Grip'; end
    return 'Shield';
end

-- ---------------------------------------------------------------------------
-- Reserved slots (server item_equipment.rslot) + the ADR 0010 trinket
-- completion. The catalog's RSlot mirrors the server column faithfully, but
-- rslot is not the whole conflict story: the server ALSO strips a Range/Ammo
-- pair whose weapon skill/subskill differ (charutils.cpp EquipItem,
-- SLOT_RANGED/SLOT_AMMO arms) -- that check, not rslot, is what clears the
-- Rimestone-class stat sticks (their server rslot is 0). So an AmmoType-less
-- Ammo item is completed to the Range bit HERE, the one place gear.lua's
-- RSlot is decided, and the fresh write and the /dl fix backfill can never
-- disagree. EXCEPT the Automaton Oils: item_weapon gives them subskill 10,
-- the subskill of every Animator, so the server KEEPS oil + Animator together
-- (field case 2026-07-22: Mindie's manually equipped Automat. Oil +2 was
-- displaced by trinketWornDisplace every Default dispatch because the
-- completion had stamped it Range-reserving).
-- ---------------------------------------------------------------------------
M.RANGE_BIT = 0x0004;

-- Ammo the server PAIRS with a Range piece instead of conflicting: the four
-- Automaton Oils (item_weapon skill 0 / subskill 10 == every Animator; the
-- census over item_equipment x item_weapon shows they are the ONLY such
-- class). By id -- names vary, ids are pinned.
M.ANIMATOR_FED = { [18731] = true, [18732] = true, [18733] = true, [19185] = true };

function M.effectiveRSlot(catRec)
    if type(catRec) ~= 'table' then return nil; end
    if catRec.RSlot ~= nil then return catRec.RSlot; end
    if catRec.Type == 'Ammo' and catRec.AmmoType == nil
       and M.ANIMATOR_FED[catRec.Id] ~= true then
        return M.RANGE_BIT;
    end
    return nil;
end

-- ---------------------------------------------------------------------------
-- Catalog enrichment of an owned record: owned overrides, catalog fills gaps.
-- ---------------------------------------------------------------------------

-- In-place enrich (the GUI's load-time fill; gearui walks its containers and
-- calls this per record). Semantics preserved exactly, including the shared
-- Stats table when the record had none (copy-on-write discipline is the
-- CONSUMERS' rule -- see docs/design/conditional-effects.md).
function M.enrich(rec, c)
    if type(rec) ~= 'table' or type(c) ~= 'table' then return rec; end
    -- Pairing metadata (Sub-slot rule) + the legacy-spelling heal. OneHanded
    -- rides through the record rule: catalog fills a missing flag, and an H2H
    -- record's lying true (see healOneHanded) is corrected in memory.
    rec.Type = M.healType(rec.Type, c.Type);
    local oh = rec.OneHanded;
    if oh == nil then oh = c.OneHanded; end
    rec.OneHanded = M.healOneHanded(rec.Type, oh);
    -- Pairing metadata (Range/Ammo rule). Absent stays absent -- nil is
    -- meaningful: it marks an unfirable stat stick that forces Range empty.
    if rec.AmmoType == nil then rec.AmmoType = c.AmmoType; end
    -- Appearance model id (lockstyle look preview). Absent stays absent.
    if rec.Model == nil then rec.Model = c.Model; end
    if type(c.Stats) == 'table' and next(c.Stats) ~= nil then
        if type(rec.Stats) ~= 'table' or next(rec.Stats) == nil then
            rec.Stats = c.Stats;
        else
            rec.Stats = M.mergedStats(rec, c);
        end
    end
    return rec;
end

-- Read-only merge of a record's Stats with the catalog's (same precedence as
-- enrich, fresh table): nil when neither side has stats; one side's table when
-- only it does; else catalog base overlaid by owned. gearexport reads through
-- this so an export before the GUI ever opened matches one after.
function M.mergedStats(rec, catRec)
    local cs = (type(catRec) == 'table') and catRec.Stats or nil;
    local rs = (type(rec) == 'table') and rec.Stats or nil;
    local hasCs = type(cs) == 'table' and next(cs) ~= nil;
    local hasRs = type(rs) == 'table' and next(rs) ~= nil;
    if not hasCs and not hasRs then return nil; end
    if not hasCs then return rs; end
    if not hasRs then return cs; end
    local m = {};
    for k, x in pairs(cs) do m[k] = x; end
    for k, x in pairs(rs) do m[k] = x; end
    return m;
end

return M;
