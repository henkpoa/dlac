--[[
    statdefs.lua -- SINGLE SOURCE OF TRUTH for stat metadata (dlac).

    Every stat's presentation + weighting properties live here, keyed by the canonical
    gear.lua / catalog Stats key (the "gear string"). Add or adjust a stat in ONE place and
    the stat page, weight page, optimizer aliases / negative-good handling, and augment labels
    all derive from it. A stat NOT listed here still works -- it degrades to its raw key in the
    "Misc" section until you add a line (graceful fallback), so this never blocks a re-crawl.

    PRESENTATION ONLY -- NO server mod-ids live here (those stay in the gitignored tools/).
    Safe to publish: it only knows stat NAMES and how to show / weigh them.

    Fields per entry (only `key` is required):
      key         exact Stats-table key it annotates, e.g. 'MagicAttackBonus'
      label       short display name (defaults to key)
      section     bucket for the grouped stat / weight panels (see SECTIONS below)
      percent     true if the value is a percentage (%) -- display + augment formatting
      lowerBetter true if you want the value as LOW / negative as possible (DT/PDT/MDT, Delay).
                  The optimizer negates it, so a POSITIVE weight rewards the good (low) side.
      aliases     alternate spellings that mean the same stat (MATK/MAB -> MagicAttackBonus)
]]--

local M = {};

-- Section display order for the grouped stat / weight panels.
M.SECTIONS = { 'Attributes', 'HP/MP', 'Offense', 'Magic', 'Defense', 'Misc' };

-- ====================================================================================
-- THE REGISTRY.  Edit here to add / adjust a stat.  Order within a section = display order.
-- ====================================================================================
M.list = {
    -- ---- Attributes ----
    { key = 'STR', section = 'Attributes' },
    { key = 'DEX', section = 'Attributes' },
    { key = 'VIT', section = 'Attributes' },
    { key = 'AGI', section = 'Attributes' },
    { key = 'INT', section = 'Attributes' },
    { key = 'MND', section = 'Attributes' },
    { key = 'CHR', section = 'Attributes' },

    -- ---- HP / MP ----
    { key = 'HP',  section = 'HP/MP' },
    { key = 'HPP', label = 'HP%', section = 'HP/MP', percent = true },
    { key = 'MP',  section = 'HP/MP' },
    { key = 'MPP', label = 'MP%', section = 'HP/MP', percent = true },
    { key = 'Refresh',    section = 'HP/MP' },
    { key = 'Regen',      section = 'HP/MP' },
    { key = 'ConserveMP', label = 'Conserve MP', section = 'HP/MP' },
    { key = 'HMP', label = 'Rest MP', section = 'HP/MP' },   -- MP recovered while healing
    { key = 'HHP', label = 'Rest HP', section = 'HP/MP' },   -- HP recovered while healing

    -- ---- Offense ----
    { key = 'Accuracy',        label = 'Acc',         section = 'Offense' },
    { key = 'Attack',          label = 'Att',         section = 'Offense' },
    { key = 'RangedAccuracy',  label = 'R.Acc',       section = 'Offense' },
    { key = 'RangedAttack',    label = 'R.Att',       section = 'Offense' },
    { key = 'CriticalHitRate', label = 'Crit',        section = 'Offense', percent = true },
    { key = 'DoubleAttack',    label = 'Dbl.Atk',     section = 'Offense', percent = true },
    { key = 'TripleAttack',    label = 'Triple Atk',  section = 'Offense', percent = true },
    { key = 'StoreTP',         label = 'Store TP',    section = 'Offense' },
    { key = 'SubtleBlow',      label = 'Subtle Blow', section = 'Offense', percent = true },
    { key = 'Haste',           label = 'Haste',       section = 'Offense', percent = true },
    { key = 'DualWield',       label = 'Dual Wield',  section = 'Offense', percent = true },
    { key = 'Counter',         label = 'Counter',     section = 'Offense', percent = true },
    { key = 'DMG',             label = 'DMG',         section = 'Offense' },   -- weapon base damage

    -- ---- Magic ----
    { key = 'MagicAccuracy',     label = 'M.Acc', section = 'Magic', aliases = { 'MACC' } },
    { key = 'MagicAttackBonus',  label = 'MAB',   section = 'Magic', aliases = { 'MATK', 'MAB', 'MagicAttack' } },
    { key = 'MagicDefenseBonus', label = 'M.Def', section = 'Magic', aliases = { 'MDB', 'MagicDefense' } },
    { key = 'FastCast',          label = 'Fast Cast', section = 'Magic', percent = true },
    { key = 'CurePotency',       label = 'Cure Pot.', section = 'Magic', percent = true },
    { key = 'SpellInterruptionRateDown', label = 'Spell Intr', section = 'Magic', percent = true },
    { key = 'Enmity',            label = 'Enmity', section = 'Magic' },   -- raw value; may be negative (enmity down)

    -- ---- Defense / mitigation ----
    { key = 'DEF',          label = 'DEF',     section = 'Defense' },
    { key = 'Evasion',      label = 'Evasion', section = 'Defense' },
    { key = 'MagicEvasion', label = 'M.Eva',   section = 'Defense' },
    -- Mitigation: the beneficial side is LOW / negative (less damage taken). lowerBetter makes
    -- the scorer negate it so a positive weight rewards damage reduction.
    { key = 'DT',  section = 'Defense', percent = true, lowerBetter = true },
    { key = 'PDT', section = 'Defense', percent = true, lowerBetter = true },
    { key = 'MDT', section = 'Defense', percent = true, lowerBetter = true },

    -- ---- Misc ----
    { key = 'MovementSpeed', label = 'Move Spd', section = 'Misc', percent = true },
    { key = 'Delay',         label = 'Delay',    section = 'Misc', lowerBetter = true },  -- weapon delay; rarely weighted
};

--[[ NOT YET IN THE CATALOG -- promote these to real entries above as the crawl maps them.
     They already appear on augmented / older-scan gear, so wiring them in here styles them
     instead of dumping them in "Misc". Suggested homes / flags:

       Skill   (section 'Skill', flat):     AxeSkill, GreatAxeSkill, PolearmSkill, ScytheSkill,
                                             SwordSkill, GreatSwordSkill, DaggerSkill, ClubSkill,
                                             ArcherySkill, MarksmanshipSkill, ThrowingSkill,
                                             SingingSkill, StringInstrumentSkill, WindInstrumentSkill,
                                             plus the magic skills (Elemental/Enhancing/Enfeebling/...)
       Casting (section 'Magic', %):        SongRecast (lowerBetter), CureCastTime (lowerBetter),
                                             OccQuickenSpell, EnhancingDuration
       Pet     (section 'Pet', flat):       Pet_STR, Pet_DEF, Pet_Accuracy, Pet_Attack, ...
       Resist  (section 'Defense', flat):   FireResistance, IceResistance, WindResistance,
                                             EarthResistance, LightningResistance, WaterResistance,
                                             LightResistance, DarkResistance
     (Add a new section name to M.SECTIONS above when you introduce 'Skill' / 'Pet'.)
]]--

-- ====================================================================================
-- Derived lookups (built from M.list) + fallback-safe accessors. Consumers read these.
-- ====================================================================================
M.byKey = {};
for _, e in ipairs(M.list) do M.byKey[e.key] = e; end

M.aliasOf = {};   -- lower(alias) -> canonical key
for _, e in ipairs(M.list) do
    if e.aliases ~= nil then
        for _, a in ipairs(e.aliases) do M.aliasOf[string.lower(a)] = e.key; end
    end
end

-- Resolve any spelling (case-insensitive, alias-aware) to its entry. An unknown stat falls
-- back to { key, label=key, section='Misc' } so a new/unlisted stat never errors -- it just
-- shows un-styled until it's added above.
function M.get(key)
    if type(key) ~= 'string' then return nil; end
    local e = M.byKey[key];
    if e == nil then
        local canon = M.aliasOf[string.lower(key)];
        e = (canon ~= nil) and M.byKey[canon] or nil;
    end
    return e or { key = key, label = key, section = 'Misc' };
end

-- Canonical key for any spelling (alias-aware); returns the input unchanged if unknown.
function M.canon(key)
    if type(key) ~= 'string' then return key; end
    if M.byKey[key] ~= nil then return key; end
    return M.aliasOf[string.lower(key)] or key;
end

return M;
