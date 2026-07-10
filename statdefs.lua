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
M.SECTIONS = { 'Attributes', 'HP/MP', 'Offense', 'Magic', 'Defense', 'Skill', 'Misc' };

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
    { key = 'ConvertHPtoMP', label = 'HP->MP', section = 'HP/MP' },
    { key = 'ConvertMPtoHP', label = 'MP->HP', section = 'HP/MP' },

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
    { key = 'QuadrupleAttack', label = 'Quad.Atk',    section = 'Offense', percent = true },
    { key = 'Regain',          label = 'Regain',      section = 'Offense' },   -- TP per tick
    { key = 'TPBonus',         label = 'TP Bonus',    section = 'Offense' },   -- flat, literal TP
    { key = 'Snapshot',        label = 'Snapshot',    section = 'Offense', percent = true },
    { key = 'RapidShot',       label = 'Rapid Shot',  section = 'Offense', percent = true },
    { key = 'CriticalHitDamage', label = 'Crit Dmg',  section = 'Offense', percent = true },   -- crit DMG, not rate
    { key = 'WeaponSkillAccuracy',       label = 'WS Acc',     section = 'Offense' },
    { key = 'WeaponSkillDamage',         label = 'WS Dmg',     section = 'Offense', percent = true, aliases = { 'WSDmg' } },
    { key = 'WeaponSkillDamageFirstHit', label = 'WS Dmg 1st', section = 'Offense', percent = true },
    { key = 'SkillchainDamage', label = 'SC Dmg',     section = 'Offense', percent = true, aliases = { 'SCdmg', 'SkillchainDmg' } },
    { key = 'MartialArts',      label = 'Martial Arts', section = 'Offense' },   -- MNK, H2H delay
    { key = 'KickAttackRate',   label = 'Kick Rate',    section = 'Offense', percent = true },
    { key = 'KickAttackDamage', label = 'Kick Dmg',     section = 'Offense', percent = true },
    { key = 'Zanshin',        label = 'Zanshin',      section = 'Offense', percent = true },   -- SAM
    { key = 'StepAccuracy',   label = 'Step Acc',     section = 'Offense' },   -- DNC
    { key = 'AttackPct',      label = 'Att%',         section = 'Offense', percent = true },
    { key = 'DoubleShotRate', label = 'Dbl.Shot',     section = 'Offense', percent = true },   -- RNG
    { key = 'SubtleBlowII',   label = 'Subtle Blow II', section = 'Offense', percent = true },
    { key = 'Sharpshot',      label = 'Sharpshot',    section = 'Offense' },   -- RNG
    { key = 'Daken',          label = 'Daken',        section = 'Offense', percent = true },   -- NIN
    { key = 'Barrage',        label = 'Barrage',      section = 'Offense' },   -- RNG, +shots

    -- ---- Magic ----
    { key = 'MACC', label = 'M.Acc', section = 'Magic', aliases = { 'MagicAccuracy' } },
    { key = 'MAB',  label = 'MAB',   section = 'Magic', aliases = { 'MATK', 'MagicAttackBonus', 'MagicAttack' } },
    { key = 'MagicDefenseBonus', label = 'M.Def', section = 'Magic', aliases = { 'MDB', 'MagicDefense' } },
    { key = 'FastCast',          label = 'Fast Cast', section = 'Magic', percent = true },
    { key = 'CurePotency',       label = 'Cure Pot.', section = 'Magic', percent = true },
    { key = 'SpellInterruptionRateDown', label = 'Spell Intr', section = 'Magic', percent = true },
    { key = 'Enmity',            label = 'Enmity', section = 'Magic' },   -- raw value; may be negative (enmity down)
    { key = 'MDMG',              label = 'Magic Dmg', section = 'Magic', aliases = { 'MagicDamage' } },   -- flat; NOT MAB (mod 28)
    { key = 'MagicBurstDamage',  label = 'M.Burst',   section = 'Magic', percent = true, aliases = { 'MagicBurst', 'MBdmg' } },
    -- Elemental Magic Atk Bonus / Accuracy (short keys, matching base MAB/MACC). Thunder, not Lightning.
    { key = 'FireMAB',     label = 'Fire MAB',     section = 'Magic', aliases = { 'FireMagicAttackBonus' } },
    { key = 'IceMAB',      label = 'Ice MAB',      section = 'Magic', aliases = { 'IceMagicAttackBonus' } },
    { key = 'WindMAB',     label = 'Wind MAB',     section = 'Magic', aliases = { 'WindMagicAttackBonus' } },
    { key = 'EarthMAB',    label = 'Earth MAB',    section = 'Magic', aliases = { 'EarthMagicAttackBonus' } },
    { key = 'ThunderMAB',  label = 'Thunder MAB',  section = 'Magic', aliases = { 'ThunderMagicAttackBonus', 'LightningMAB', 'LightningMagicAttackBonus' } },
    { key = 'WaterMAB',    label = 'Water MAB',    section = 'Magic', aliases = { 'WaterMagicAttackBonus' } },
    { key = 'LightMAB',    label = 'Light MAB',    section = 'Magic', aliases = { 'LightMagicAttackBonus' } },
    { key = 'DarkMAB',     label = 'Dark MAB',     section = 'Magic', aliases = { 'DarkMagicAttackBonus' } },
    { key = 'FireMACC',    label = 'Fire MACC',    section = 'Magic', aliases = { 'FireMagicAccuracy' } },
    { key = 'IceMACC',     label = 'Ice MACC',     section = 'Magic', aliases = { 'IceMagicAccuracy' } },
    { key = 'WindMACC',    label = 'Wind MACC',    section = 'Magic', aliases = { 'WindMagicAccuracy' } },
    { key = 'EarthMACC',   label = 'Earth MACC',   section = 'Magic', aliases = { 'EarthMagicAccuracy' } },
    { key = 'ThunderMACC', label = 'Thunder MACC', section = 'Magic', aliases = { 'ThunderMagicAccuracy', 'LightningMACC', 'LightningMagicAccuracy' } },
    { key = 'WaterMACC',   label = 'Water MACC',   section = 'Magic', aliases = { 'WaterMagicAccuracy' } },
    { key = 'LightMACC',   label = 'Light MACC',   section = 'Magic', aliases = { 'LightMagicAccuracy' } },
    { key = 'DarkMACC',    label = 'Dark MACC',    section = 'Magic', aliases = { 'DarkMagicAccuracy' } },
    -- CatsEyeXI staff affinity: Iridescence = every element at once (tiered +1/+2/+3);
    -- a per-element Staff Bonus is that one element's affinity. Read by the auto-staff
    -- automation; crawled from the API (mods 566, 347-354).
    { key = 'Iridescence',       label = 'Iridescence',   section = 'Magic' },
    { key = 'FireStaffBonus',    label = 'Fire Staff',    section = 'Magic' },
    { key = 'IceStaffBonus',     label = 'Ice Staff',     section = 'Magic' },
    { key = 'WindStaffBonus',    label = 'Wind Staff',    section = 'Magic' },
    { key = 'EarthStaffBonus',   label = 'Earth Staff',   section = 'Magic' },
    { key = 'ThunderStaffBonus', label = 'Thunder Staff', section = 'Magic' },
    { key = 'WaterStaffBonus',   label = 'Water Staff',   section = 'Magic' },
    { key = 'LightStaffBonus',   label = 'Light Staff',   section = 'Magic' },
    { key = 'DarkStaffBonus',    label = 'Dark Staff',    section = 'Magic' },
    { key = 'DrainAspirPotency', label = 'Drain/Aspir', section = 'Magic', percent = true },   -- DRK
    { key = 'SongCastTime',      label = 'Song Cast',   section = 'Magic', percent = true, lowerBetter = true },   -- BRD; low = faster
    { key = 'CureCastTime',      label = 'Cure Cast',   section = 'Magic', percent = true, lowerBetter = true },   -- WHM
    { key = 'WaltzPotency',      label = 'Waltz Pot.',  section = 'Magic', percent = true },   -- DNC
    { key = 'CurePotencyReceived',    label = 'Cure Rcvd',    section = 'Magic', percent = true },
    { key = 'CurePotencyII',          label = 'Cure Pot. II', section = 'Magic', percent = true },
    { key = 'MagicCriticalHitRate',   label = 'M.Crit',       section = 'Magic', percent = true },
    { key = 'MagicCriticalHitDamage', label = 'M.Crit Dmg',   section = 'Magic', percent = true },
    { key = 'EnfeeblingMagicPotency', label = 'Enf.Pot.',     section = 'Magic' },
    { key = 'EnhancingMagicDuration', label = 'Enh.Dur.',     section = 'Magic' },
    { key = 'EnfeeblingMagicDuration', label = 'Enf.Dur.',    section = 'Magic' },
    { key = 'SongDurationBonus',      label = 'Song Dur.',    section = 'Magic' },   -- BRD

    -- ---- Defense / mitigation ----
    { key = 'DEF',          label = 'DEF',     section = 'Defense' },
    { key = 'Evasion',      label = 'Evasion', section = 'Defense' },
    { key = 'MagicEvasion', label = 'M.Eva',   section = 'Defense' },
    -- Mitigation: the beneficial side is LOW / negative (less damage taken). lowerBetter makes
    -- the scorer negate it so a positive weight rewards damage reduction.
    { key = 'DT',  section = 'Defense', percent = true, lowerBetter = true },
    { key = 'PDT', section = 'Defense', percent = true, lowerBetter = true },
    { key = 'MDT', section = 'Defense', percent = true, lowerBetter = true },
    { key = 'RDT', section = 'Defense', percent = true, lowerBetter = true, aliases = { 'RangedDamageTaken' } },
    { key = 'BDT', section = 'Defense', percent = true, lowerBetter = true, aliases = { 'BreathDamageTaken' } },
    -- Elemental resistances (raw points). Lightning uses the existing key 'ThunderResistance'.
    { key = 'FireResistance',    label = 'Fire Res.',    section = 'Defense' },
    { key = 'IceResistance',     label = 'Ice Res.',     section = 'Defense' },
    { key = 'WindResistance',    label = 'Wind Res.',    section = 'Defense' },
    { key = 'EarthResistance',   label = 'Earth Res.',   section = 'Defense' },
    { key = 'ThunderResistance', label = 'Thunder Res.', section = 'Defense', aliases = { 'LightningResistance' } },
    { key = 'WaterResistance',   label = 'Water Res.',   section = 'Defense' },
    { key = 'LightResistance',   label = 'Light Res.',   section = 'Defense' },
    { key = 'DarkResistance',    label = 'Dark Res.',    section = 'Defense' },
    -- Status resists (flat). "Resist<X>" matches the in-game "Resist Poison" wording.
    { key = 'ResistParalyze', label = 'Res.Para',    section = 'Defense' },
    { key = 'ResistSilence',  label = 'Res.Silence', section = 'Defense' },
    { key = 'ResistPoison',   label = 'Res.Poison',  section = 'Defense' },
    { key = 'ResistPetrify',  label = 'Res.Petrify', section = 'Defense' },
    { key = 'ResistVirus',    label = 'Res.Virus',   section = 'Defense' },
    { key = 'ResistStatus',   label = 'Res.Status',  section = 'Defense' },   -- occ. resist all ailments
    { key = 'ResistGravity',  label = 'Res.Gravity', section = 'Defense' },
    { key = 'ResistSleep',    label = 'Res.Sleep',   section = 'Defense' },
    { key = 'ResistSlow',     label = 'Res.Slow',    section = 'Defense' },
    { key = 'ResistBlind',    label = 'Res.Blind',   section = 'Defense' },
    { key = 'ResistStun',     label = 'Res.Stun',    section = 'Defense' },
    { key = 'ResistCharm',    label = 'Res.Charm',   section = 'Defense' },
    { key = 'ResistDeath',    label = 'Res.Death',   section = 'Defense' },
    { key = 'ResistAmnesia',  label = 'Res.Amnesia', section = 'Defense' },
    { key = 'ResistBind',     label = 'Res.Bind',    section = 'Defense' },
    { key = 'ResistCurse',    label = 'Res.Curse',   section = 'Defense' },
    { key = 'EnemyCriticalHitRate', label = 'Enemy Crit', section = 'Defense', percent = true },   -- reduces enemy crit (positive-good)

    -- ---- Skill (flat) ----
    { key = 'HandToHandSkill',      label = 'H2H',        section = 'Skill' },
    { key = 'DaggerSkill',          label = 'Dagger',     section = 'Skill' },
    { key = 'SwordSkill',           label = 'Sword',      section = 'Skill' },
    { key = 'GreatSwordSkill',      label = 'G.Sword',    section = 'Skill' },
    { key = 'AxeSkill',             label = 'Axe',        section = 'Skill' },
    { key = 'GreatAxeSkill',        label = 'G.Axe',      section = 'Skill' },
    { key = 'ScytheSkill',          label = 'Scythe',     section = 'Skill' },
    { key = 'PolearmSkill',         label = 'Polearm',    section = 'Skill' },
    { key = 'KatanaSkill',          label = 'Katana',     section = 'Skill' },
    { key = 'GreatKatanaSkill',     label = 'G.Katana',   section = 'Skill' },
    { key = 'ClubSkill',            label = 'Club',       section = 'Skill' },
    { key = 'StaffSkill',           label = 'Staff',      section = 'Skill' },
    { key = 'ArcherySkill',         label = 'Archery',    section = 'Skill' },
    { key = 'MarksmanshipSkill',    label = 'Marksman',   section = 'Skill' },
    { key = 'ThrowingSkill',        label = 'Throwing',   section = 'Skill' },
    { key = 'GuardSkill',           label = 'Guard',      section = 'Skill' },
    { key = 'EvasionSkill',         label = 'Eva Skill',  section = 'Skill' },   -- skill, not the Evasion stat
    { key = 'ShieldSkill',          label = 'Shield',     section = 'Skill' },
    { key = 'ParryingSkill',        label = 'Parry',      section = 'Skill' },
    { key = 'DivineMagicSkill',     label = 'Divine',     section = 'Skill' },
    { key = 'HealingMagicSkill',    label = 'Healing',    section = 'Skill' },
    { key = 'EnhancingMagicSkill',  label = 'Enhancing',  section = 'Skill' },
    { key = 'EnfeeblingMagicSkill', label = 'Enfeebling', section = 'Skill' },
    { key = 'ElementalMagicSkill',  label = 'Elemental',  section = 'Skill' },
    { key = 'DarkMagicSkill',       label = 'Dark Mag',   section = 'Skill' },
    { key = 'SummoningMagicSkill',  label = 'Summon',     section = 'Skill' },
    { key = 'NinjutsuSkill',        label = 'Ninjutsu',   section = 'Skill' },
    { key = 'SingingSkill',         label = 'Singing',    section = 'Skill' },
    { key = 'StringInstrumentSkill', label = 'String',    section = 'Skill' },
    { key = 'WindInstrumentSkill',  label = 'Wind Instr', section = 'Skill' },
    { key = 'BlueMagicSkill',       label = 'Blue Mag',   section = 'Skill' },
    { key = 'GeomancySkill',        label = 'Geomancy',   section = 'Skill' },
    { key = 'HandbellSkill',        label = 'Handbell',   section = 'Skill' },

    -- ---- Misc ----
    { key = 'MovementSpeed', label = 'Move Spd', section = 'Misc', percent = true },
    { key = 'SynthSkillGain',   label = 'Synth Skill+', section = 'Misc', percent = true,
      aliases = { 'SynthesisSkillGainRate', 'SynthesisSkillUpRate' } },   -- crafting gear (Midras's set)
    { key = 'SynthSuccessRate', label = 'Synth Success', section = 'Misc', percent = true,
      aliases = { 'SynthesisSuccessRate' } },
    { key = 'Delay',         label = 'Delay',    section = 'Misc', lowerBetter = true },  -- weapon delay; rarely weighted
    { key = 'TreasureHunter', label = 'TH',      section = 'Misc' },   -- THF
    { key = 'Steal',          label = 'Steal',   section = 'Misc' },   -- THF
    { key = 'Recycle',        label = 'Recycle', section = 'Misc', percent = true },   -- RNG, conserve ammo
    { key = 'BloodPactDelay',   label = 'BP Delay',   section = 'Misc', lowerBetter = true },   -- SMN
    { key = 'PerpetuationCost', label = 'Perp. Cost', section = 'Misc', lowerBetter = true },   -- SMN
    { key = 'BloodPactDamage',  label = 'BP Dmg',     section = 'Misc', percent = true },   -- SMN
    -- SMN per-element avatar perpetuation affinity (Fire Affinity Perp +N on items).
    { key = 'FireAffinityPerp',    label = 'Fire Aff.',    section = 'Misc' },
    { key = 'IceAffinityPerp',     label = 'Ice Aff.',     section = 'Misc' },
    { key = 'WindAffinityPerp',    label = 'Wind Aff.',    section = 'Misc' },
    { key = 'EarthAffinityPerp',   label = 'Earth Aff.',   section = 'Misc' },
    { key = 'ThunderAffinityPerp', label = 'Thunder Aff.', section = 'Misc' },
    { key = 'WaterAffinityPerp',   label = 'Water Aff.',   section = 'Misc' },
    { key = 'LightAffinityPerp',   label = 'Light Aff.',   section = 'Misc' },
    { key = 'DarkAffinityPerp',    label = 'Dark Aff.',    section = 'Misc' },
    { key = 'CharmChance',   label = 'Charm Chance', section = 'Misc' },   -- BST
    { key = 'CharmDuration', label = 'Charm Dur.',   section = 'Misc' },   -- BST
    -- Killers (flat): +acc/att vs a monster family.
    { key = 'VerminKiller',   label = 'Vermin K.',   section = 'Misc' },
    { key = 'BirdKiller',     label = 'Bird K.',     section = 'Misc' },
    { key = 'AmorphKiller',   label = 'Amorph K.',   section = 'Misc' },
    { key = 'LizardKiller',   label = 'Lizard K.',   section = 'Misc' },
    { key = 'AquanKiller',    label = 'Aquan K.',    section = 'Misc' },
    { key = 'PlantoidKiller', label = 'Plantoid K.', section = 'Misc' },
    { key = 'BeastKiller',    label = 'Beast K.',    section = 'Misc' },
    { key = 'UndeadKiller',   label = 'Undead K.',   section = 'Misc' },
    { key = 'ArcanaKiller',   label = 'Arcana K.',   section = 'Misc' },
    { key = 'DragonKiller',   label = 'Dragon K.',   section = 'Misc' },
    { key = 'DemonKiller',    label = 'Demon K.',    section = 'Misc' },
    { key = 'EmptyKiller',    label = 'Empty K.',    section = 'Misc' },
    { key = 'HumanoidKiller', label = 'Humanoid K.', section = 'Misc' },
    { key = 'LuminianKiller', label = 'Luminian K.', section = 'Misc' },
    { key = 'LuminionKiller', label = 'Luminion K.', section = 'Misc' },
};

--[[ NOT YET IN THE CATALOG -- promote these to real entries above as the crawl maps them.
     (Skills, the 8 elemental resists, the status resists, and the elemental MAB/MACC
      family are all promoted above now; lightning uses the existing key
      'ThunderResistance', matching gearimport.) What's left:

       Casting (section 'Magic', %):  SongRecast (lowerBetter), OccQuickenSpell
       Pet     (section 'Pet', flat): Pet_STR, Pet_DEF, Pet_Accuracy, Pet_Attack, ...
                                      (add a 'Pet' section to M.SECTIONS when you do)

     Remaining decisions live in tools/api_cache/stats_decisions.txt. Iridescence and
     the per-element Staff Bonus / Affinity mods arrive with issue #5 (modifier_map
     crawl extension).
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
