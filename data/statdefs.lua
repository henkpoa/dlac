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
M.SECTIONS = { 'Attributes', 'HP/MP', 'Offense', 'Magic', 'Defense', 'Skill', 'Ability', 'Pet', 'Misc' };

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
    { key = 'SublimationBonus', label = 'Sublimation+', section = 'HP/MP' },   -- SCH; MP/tick added to Sublimation

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
    -- 2026-07-14 adoption round.
    { key = 'TripleAttackDamage', label = 'Triple Atk Dmg', section = 'Offense', percent = true },
    { key = 'DoubleAttackDamage', label = 'Dbl.Atk Dmg', section = 'Offense', percent = true },
    { key = 'CounterDamage', label = 'Counter Dmg', section = 'Offense', percent = true },
    { key = 'EnspellDamage', label = 'Enspell Dmg', section = 'Offense' },   -- flat added enspell damage
    { key = 'FencerTPBonus', label = 'Fencer TP', section = 'Offense' },   -- flat literal TP, like TPBonus
    { key = 'FencerCritRate', label = 'Fencer Crit', section = 'Offense', percent = true },
    { key = 'ConserveTP', label = 'Conserve TP', section = 'Offense', percent = true },
    { key = 'WSNoTPDeplete', label = 'Occ. WS keeps TP', section = 'Offense', percent = true },
    { key = 'TacticalParry', label = 'Parry TP', section = 'Offense' },   -- flat TP gained on parry
    { key = 'TacticalGuard', label = 'Guard TP', section = 'Offense' },
    { key = 'ShieldMasteryTP', label = 'Block TP', section = 'Offense' },
    { key = 'BreathDamage', label = 'Breath Dmg', section = 'Offense', percent = true },   -- breath dmg DEALT (taken side is BDT)
    { key = 'ExtraKickAttack', label = 'Extra Kick Chance', section = 'Offense', percent = true },
    { key = 'DamageCapBonus', label = 'Dmg Cap+', section = 'Offense', percent = true },   -- pDIF cap+
    { key = 'DelayPct', label = 'Delay %', section = 'Offense', percent = true, lowerBetter = true },   -- stored negative
    { key = 'RangedDelayPct', label = 'R.Delay %', section = 'Offense', percent = true, lowerBetter = true },
    { key = 'CritRateWeapon', label = 'Crit (this wpn)', section = 'Offense', percent = true },   -- applies to this weapon's swings only
    -- Elemental gorget/belt fTP family (Fotia = all WS).
    { key = 'AnyWSBonus', label = 'All WS fTP+', section = 'Offense', percent = true },
    { key = 'DayWSBonus', label = 'Day WS fTP+', section = 'Offense', percent = true },   -- WS element matches day
    { key = 'FireWSBonus', label = 'Fire WS+', section = 'Offense', percent = true },
    { key = 'IceWSBonus', label = 'Ice WS+', section = 'Offense', percent = true },
    { key = 'WindWSBonus', label = 'Wind WS+', section = 'Offense', percent = true },
    { key = 'EarthWSBonus', label = 'Earth WS+', section = 'Offense', percent = true },
    { key = 'ThunderWSBonus', label = 'Thunder WS+', section = 'Offense', percent = true },
    { key = 'WaterWSBonus', label = 'Water WS+', section = 'Offense', percent = true },
    { key = 'LightWSBonus', label = 'Light WS+', section = 'Offense', percent = true },
    { key = 'DarkWSBonus', label = 'Dark WS+', section = 'Offense', percent = true },
    { key = 'WSStrBonus', label = 'WS STR+%', section = 'Offense', percent = true },   -- adds stat% to that weapon's WS calc
    { key = 'WSDexBonus', label = 'WS DEX+%', section = 'Offense', percent = true },
    { key = 'WSAgiBonus', label = 'WS AGI+%', section = 'Offense', percent = true },
    { key = 'WSIntBonus', label = 'WS INT+%', section = 'Offense', percent = true },
    { key = 'WSChrBonus', label = 'WS CHR+%', section = 'Offense', percent = true },

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
    { key = 'SongCastTime',      label = 'Song Cast Time-', section = 'Magic', percent = true, lowerBetter = true },   -- BRD; low = faster
    { key = 'CureCastTime',      label = 'Cure Cast Time-', section = 'Magic', percent = true, lowerBetter = true },   -- WHM
    { key = 'WaltzPotency',      label = 'Waltz Pot.',  section = 'Magic', percent = true },   -- DNC
    { key = 'CurePotencyReceived',    label = 'Cure Rcvd',    section = 'Magic', percent = true },
    { key = 'CurePotencyII',          label = 'Cure Pot. II', section = 'Magic', percent = true },
    { key = 'MagicCriticalHitRate',   label = 'M.Crit',       section = 'Magic', percent = true },
    { key = 'MagicCriticalHitDamage', label = 'M.Crit Dmg',   section = 'Magic', percent = true },
    { key = 'EnfeeblingMagicPotency', label = 'Enf.Pot.',     section = 'Magic' },
    { key = 'EnhancingMagicDuration', label = 'Enh.Dur.',     section = 'Magic' },
    { key = 'EnfeeblingMagicDuration', label = 'Enf.Dur.',    section = 'Magic' },
    { key = 'SongDurationBonus',      label = 'Song Dur.',    section = 'Magic' },   -- BRD
    -- 2026-07-14 adoption round.
    { key = 'OccultAcumen', label = 'Occ. Acumen', section = 'Magic' },   -- TP gained from elemental/dark magic
    { key = 'ElementalMagicRecast', label = 'Elem. Recast', section = 'Magic', lowerBetter = true },   -- stored negative
    { key = 'BlueMagicRecast', label = 'Blue Recast', section = 'Magic', lowerBetter = true },
    { key = 'UncappedFastCast', label = 'Fast Cast (uncap)', section = 'Magic', percent = true },   -- fast cast that bypasses the FC cap
    { key = 'QuickMagic', label = 'Quick Magic Chance', section = 'Magic', percent = true },   -- proc: instant cast
    { key = 'ElementalCelerity', label = 'Elem. Cast Time-', section = 'Magic', percent = true },
    { key = 'BlackMagicCast', label = 'Black Cast Time-', section = 'Magic', percent = true, lowerBetter = true },   -- stored negative
    { key = 'WhiteMagicCast', label = 'White Cast Time-', section = 'Magic', percent = true, lowerBetter = true },
    { key = 'DarkMagicCast', label = 'Dark Cast Time-', section = 'Magic', percent = true, lowerBetter = true },
    { key = 'SummoningMagicCast', label = 'Summon Cast Time-', section = 'Magic' },   -- VERIFY: stores +1, likely seconds reduced (positive-good)
    { key = 'SpiritCastReduction', label = 'Spirit Cast Time-', section = 'Magic', lowerBetter = true },   -- SMN spirit avatars
    { key = 'GrimoireCastTime', label = 'Grimoire Cast Time-', section = 'Magic', percent = true, lowerBetter = true },   -- SCH; stored negative
    { key = 'WhiteMagicCost', label = 'White MP Cost-', section = 'Magic', lowerBetter = true },   -- VERIFY: one item stores 300, scale unclear (/100?)
    { key = 'NoSpellMPDepletion', label = 'Occ. 0 MP', section = 'Magic', percent = true },   -- proc: spell costs no MP
    { key = 'CureToMP', label = 'Cure->MP', section = 'Magic', percent = true },   -- % of cure amount returned as MP
    { key = 'CursnaBonus', label = 'Cursna+', section = 'Magic' },   -- Cursna success on others
    { key = 'CursnaReceived', label = 'Cursna Rcvd', section = 'Magic' },
    { key = 'DivineBenison', label = 'Divine Benison', section = 'Magic' },   -- WHM trait tiers (Yagrush)
    { key = 'BarspellPotency', label = 'Barspell+', section = 'Magic' },   -- flat resistance added
    { key = 'BarspellMDef', label = 'Barspell M.Def', section = 'Magic' },
    { key = 'StoneskinPotency', label = 'Stoneskin+', section = 'Magic' },   -- flat HP added
    { key = 'AquaveilCount', label = 'Aquaveil+', section = 'Magic' },   -- extra interrupts blocked
    { key = 'UtsusemiShadows', label = 'Utsusemi+', section = 'Magic' },   -- +N shadows
    { key = 'RegenPotency', label = 'Regen+', section = 'Magic' },   -- VERIFY: cast-Regen boost, flat HP/tick vs % unconfirmed
    { key = 'RegenDuration', label = 'Regen Dur.', section = 'Magic' },   -- seconds added to cast Regen
    { key = 'RefreshPotency', label = 'Refresh+', section = 'Magic' },   -- VERIFY: Estoqueur "Enhances Refresh" -- potency vs duration
    { key = 'LightArtsEffect', label = 'Light Arts+', section = 'Magic' },
    { key = 'DarkArtsEffect', label = 'Dark Arts+', section = 'Magic' },
    { key = 'SpikesDamage', label = 'Spikes Dmg', section = 'Magic' },   -- flat
    { key = 'SpikesDamageBonus', label = 'Spikes Dmg+', section = 'Magic', percent = true },
    { key = 'NinjutsuDamage', label = 'Ninjutsu Dmg', section = 'Magic' },   -- flat
    { key = 'DayNukeBonus', label = 'Day Nuke+', section = 'Magic', percent = true },   -- nuke element matches day
    { key = 'DarkMagicDuration', label = 'Dark Dur.+', section = 'Magic', percent = true },
    { key = 'DiaDot', label = 'Dia DoT+', section = 'Magic' },   -- dmg/tick added to Dia
    { key = 'ElementalDebuffEffect', label = 'Elem. Debuff+', section = 'Magic' },   -- shock/rasp etc.
    { key = 'SaboteurBonus', label = 'Saboteur+', section = 'Magic', percent = true },
    { key = 'ShadowBindDuration', label = 'Shadowbind Dur.', section = 'Magic' },   -- seconds
    { key = 'AbsorbPotency', label = 'Absorb+', section = 'Magic', percent = true },   -- DRK absorb spell amount
    { key = 'MagicCritRateII', label = 'M.Crit II', section = 'Magic', percent = true },
    { key = 'OccQuickenSpell', label = 'Occ. Quick Cast', section = 'Magic', percent = true },   -- augment id 351 only (no crawler mod)

    -- ---- Defense / mitigation ----
    { key = 'DEF',          label = 'DEF',     section = 'Defense' },
    { key = 'DEFP',         label = 'DEF%',    section = 'Defense', percent = true },   -- mirrors HPP/MPP
    { key = 'Evasion',      label = 'Evasion', section = 'Defense' },
    { key = 'MagicEvasion', label = 'M.Eva',   section = 'Defense' },
    -- proc stat -> named "Chance" per the stat-naming ruling (never reads as a reduction)
    { key = 'AbsorbDamageChance', label = 'Absorb Dmg Chance', section = 'Defense', percent = true },
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
    -- 2026-07-14 adoption round (stats_tiers2.txt, row-by-row approved).
    -- Labeling rulings: proc stats say "Chance" (never readable as a reduction); cast speed says "Cast Time-".
    { key = 'EnmityLossReduction', label = 'Enmity Loss-', section = 'Defense', percent = true },   -- enmity lost when damaged, reduced
    { key = 'ShieldBlockRate', label = 'Block Rate', section = 'Defense', percent = true },
    { key = 'ShieldDefBonus', label = 'Shield DEF', section = 'Defense' },   -- flat DEF while blocking
    { key = 'Inquartata', label = 'Inquartata', section = 'Defense', percent = true },   -- parry rate+
    { key = 'GuardRate', label = 'Guard Rate', section = 'Defense', percent = true },
    { key = 'PDTII', label = 'PDT II', section = 'Defense', percent = true, lowerBetter = true },   -- 2nd PDT pool (Burtgang); crawler scales /100 like DT
    { key = 'MDTII', label = 'MDT II', section = 'Defense', percent = true, lowerBetter = true },   -- Aegis; positive values (Aettir) are penalties
    { key = 'KnockbackReduction', label = 'Knockback-', section = 'Defense' },
    { key = 'PhalanxReceived', label = 'Phalanx Rcvd', section = 'Defense' },   -- flat reduction added to Phalanx cast ON you
    { key = 'PhysDamageToMP', label = 'Phys Dmg->MP', section = 'Defense', percent = true },   -- Ochain; % of phys dmg returned as MP
    { key = 'DamageToMP', label = 'Dmg->MP', section = 'Defense', percent = true },   -- Flume Belt
    { key = 'MagicDamageAbsorb', label = 'Absorb Magic Chance', section = 'Defense', percent = true },   -- proc: absorbs the dmg entirely
    { key = 'PhysDamageAbsorb', label = 'Absorb Phys Chance', section = 'Defense', percent = true },
    { key = 'AnnulPhysicalDamage', label = 'Annul Phys Chance', section = 'Defense', percent = true },   -- proc: COMPLETE negation, not a reduction
    { key = 'AnnulMagicalDamage', label = 'Annul Magic Chance', section = 'Defense', percent = true },
    { key = 'AnnulRangedDamage', label = 'Annul Ranged Chance', section = 'Defense', percent = true },
    { key = 'AnnulFireDamage', label = 'Annul Fire Chance', section = 'Defense', percent = true },
    { key = 'FireAbsorb', label = 'Absorb Fire Chance', section = 'Defense', percent = true },   -- sachet line
    { key = 'IceAbsorb', label = 'Absorb Ice Chance', section = 'Defense', percent = true },
    { key = 'WindAbsorb', label = 'Absorb Wind Chance', section = 'Defense', percent = true },
    { key = 'EarthAbsorb', label = 'Absorb Earth Chance', section = 'Defense', percent = true },
    { key = 'ThunderAbsorb', label = 'Absorb Thunder Chance', section = 'Defense', percent = true },   -- server mod LTNG_ABSORB
    { key = 'WaterAbsorb', label = 'Absorb Water Chance', section = 'Defense', percent = true },
    { key = 'LightAbsorb', label = 'Absorb Light Chance', section = 'Defense', percent = true },
    { key = 'DarkAbsorb', label = 'Absorb Dark Chance', section = 'Defense', percent = true },
    { key = 'WeatherDamageReduction', label = 'Weather Dmg-', section = 'Defense', percent = true },   -- elem dmg- in matching weather
    { key = 'DayDamageReduction', label = 'Day Dmg-', section = 'Defense', percent = true },
    { key = 'ProtShellReceived', label = 'Prot/Shell Rcvd', section = 'Defense' },

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
    -- Crafting skills (mods 128-135): universal gear (Kupo Shield +3, Artisans
    -- Torque +2) carries all EIGHT individually -- there is no single
    -- "all crafts" server mod; the guild gear carries just its own.
    { key = 'WoodworkingSkill',   label = 'Woodworking',  section = 'Skill' },
    { key = 'SmithingSkill',      label = 'Smithing',     section = 'Skill' },
    { key = 'GoldsmithingSkill',  label = 'Goldsmithing', section = 'Skill' },
    { key = 'ClothcraftSkill',    label = 'Clothcraft',   section = 'Skill' },
    { key = 'LeathercraftSkill',  label = 'Leathercraft', section = 'Skill' },
    { key = 'BonecraftSkill',     label = 'Bonecraft',    section = 'Skill' },
    { key = 'AlchemySkill',       label = 'Alchemy',      section = 'Skill' },
    { key = 'CookingSkill',       label = 'Cooking',      section = 'Skill' },
    { key = 'FishingSkill',       label = 'Fishing',      section = 'Skill' },   -- mod 127, sits with the crafts
    { key = 'LightArtsSkill',     label = 'Light Arts',   section = 'Skill' },   -- SCH; skill while under Light Arts
    { key = 'DarkArtsSkill',      label = 'Dark Arts',    section = 'Skill' },

    -- ---- Misc ----
    { key = 'MovementSpeed', label = 'Move Spd', section = 'Misc', percent = true },
    { key = 'SynthSkillGain',   label = 'Synth Skill+', section = 'Misc', percent = true,
      aliases = { 'SynthesisSkillGainRate', 'SynthesisSkillUpRate' } },   -- crafting gear (Midras's set)
    { key = 'SynthSuccessRate', label = 'Synth Success', section = 'Misc', percent = true,
      aliases = { 'SynthesisSuccessRate' } },
    { key = 'SynthHQRate',       label = 'Synth HQ+', section = 'Misc', percent = true },  -- Craftmasters Ring line
    -- Positive = LESS material lost on a break. In-game text (Artisans Torque +1):
    -- "Decreases likelihood of Synthesis Material loss +5%".
    { key = 'SynthMaterialLoss', label = 'Synth Mat. Loss-', section = 'Misc', percent = true },
    -- CatsEyeXI custom (modid 2016): "Conserve Ingredient N%" (Artisans Torque +1).
    { key = 'ConserveIngredient', label = 'Conserve Ingr.', section = 'Misc', percent = true },
    -- CatsEyeXI custom (modid 2000): '"Surveyor"+N' -- cuts the chance of finding
    -- "nothing" in HELM (harvesting / excavation / logging / mining). A flat point
    -- value, not a %. Held by the 4 HELM hats (+1) and the Plain set (+1 NQ / +2 HQ).
    { key = 'Surveyor', label = 'Surveyor', section = 'Misc' },
    -- The item text's "Improves Mining, Logging and Harvesting results" line (modids
    -- 513/514/515, plus CatsEyeXI's own 2006 for excavation). A FLAG, always 1: every
    -- carrier stores the same constant 73, so there is nothing to compare. Which of the
    -- four verbs a piece covers is not modelled -- read the item text for that.
    { key = 'HELM', label = 'HELM', section = 'Misc' },
    -- Guild anti-HQ gear: in-game text reads "Cannot Synthesize high quality
    -- items" (a hard HQ block, not a rate cut) -- the "NQ only" goal, e.g.
    -- skilling up on bridge recipes without wasting HQ materials.
    { key = 'AntiHQWoodworking', label = 'Anti-HQ Wood.',    section = 'Misc' },
    { key = 'AntiHQSmithing',    label = 'Anti-HQ Smith',    section = 'Misc' },
    { key = 'AntiHQGoldsmithing', label = 'Anti-HQ Gold',    section = 'Misc' },
    { key = 'AntiHQClothcraft',  label = 'Anti-HQ Cloth',    section = 'Misc' },
    { key = 'AntiHQLeathercraft', label = 'Anti-HQ Leather', section = 'Misc' },
    { key = 'AntiHQBonecraft',   label = 'Anti-HQ Bone',     section = 'Misc' },
    { key = 'AntiHQAlchemy',     label = 'Anti-HQ Alch.',    section = 'Misc' },
    { key = 'AntiHQCooking',     label = 'Anti-HQ Cook',     section = 'Misc' },
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
    -- 2026-07-14 adoption round (Misc additions).
    { key = 'BlueLearnChance', label = 'Blue Learn+', section = 'Misc', percent = true },
    { key = 'Gilfinder', label = 'Gilfinder', section = 'Misc' },
    { key = 'Stealth', label = 'Stealth', section = 'Misc' },
    { key = 'CombatSkillupRate', label = 'Combat Skillup+', section = 'Misc', percent = true },
    { key = 'MagicSkillupRate', label = 'Magic Skillup+', section = 'Misc', percent = true },
    { key = 'EXPBonus', label = 'EXP+', section = 'Misc', percent = true },
    { key = 'CapacityBonus', label = 'Capacity+', section = 'Misc', percent = true },
    { key = 'SneakDuration', label = 'Sneak Dur.', section = 'Misc' },
    { key = 'InvisibleDuration', label = 'Invisible Dur.', section = 'Misc' },
    { key = 'ChocoboRidingTime', label = 'Chocobo Time', section = 'Misc' },   -- minutes
    { key = 'DigRareAbility', label = 'Dig Rare+', section = 'Misc' },   -- chocobo digging
    { key = 'DigBypassFatigue', label = 'Dig Fatigue-', section = 'Misc' },
    { key = 'NinjaToolExpertise', label = 'Tool Expertise', section = 'Misc', percent = true },   -- chance to not consume a tool
    { key = 'ClammingCapacity', label = 'Clamming Cap.', section = 'Misc' },
    { key = 'ClammingIncidents', label = 'Clamming Safe', section = 'Misc' },
    -- Per-craft synth success (the eight guild rings); generic rate is SynthSuccessRate above.
    { key = 'SynthSuccessWoodworking', label = 'Wood Success', section = 'Misc', percent = true },
    { key = 'SynthSuccessSmithing', label = 'Smith Success', section = 'Misc', percent = true },
    { key = 'SynthSuccessGoldsmithing', label = 'Gold Success', section = 'Misc', percent = true },
    { key = 'SynthSuccessClothcraft', label = 'Cloth Success', section = 'Misc', percent = true },
    { key = 'SynthSuccessLeathercraft', label = 'Leather Success', section = 'Misc', percent = true },
    { key = 'SynthSuccessBonecraft', label = 'Bone Success', section = 'Misc', percent = true },
    { key = 'SynthSuccessAlchemy', label = 'Alch. Success', section = 'Misc', percent = true },
    { key = 'SynthSuccessCooking', label = 'Cook Success', section = 'Misc', percent = true },
    { key = 'BloodPactDelayII', label = 'BP Delay II', section = 'Misc', lowerBetter = true },   -- 2nd pool, sits with BloodPactDelay

    -- ---- Ability (JA / trait / song enhancers; new section, approved 2026-07-14) ----
    -- WAR
    { key = 'BerserkDuration', label = 'Berserk Dur.', section = 'Ability' },   -- durations are seconds unless noted
    { key = 'BerserkPotency', label = 'Berserk+', section = 'Ability', percent = true },
    { key = 'AggressorDuration', label = 'Aggressor Dur.', section = 'Ability' },
    { key = 'WarcryDuration', label = 'Warcry Dur.', section = 'Ability' },
    { key = 'DefenderDuration', label = 'Defender Dur.', section = 'Ability' },
    { key = 'Retaliation', label = 'Retaliation+', section = 'Ability' },
    { key = 'BloodRageBonus', label = 'Blood Rage+', section = 'Ability' },
    { key = 'RestraintBonus', label = 'Restraint+', section = 'Ability' },   -- VERIFY: values 50-120, likely the WS-dmg accumulation cap
    { key = 'ImpetusBonus', label = 'Impetus+', section = 'Ability' },
    { key = 'ConspiratorBonus', label = 'Conspirator+', section = 'Ability' },
    -- MNK
    { key = 'ChakraPotency', label = 'Chakra+', section = 'Ability', percent = true },   -- VIT multiplier bonus
    { key = 'ChakraRemoval', label = 'Chakra Cures', section = 'Ability' },   -- VERIFY: values 1-6 may be a bitmask of removable ailments
    { key = 'BoostEffect', label = 'Boost+', section = 'Ability' },
    { key = 'DodgeEffect', label = 'Dodge+', section = 'Ability' },
    { key = 'FocusEffect', label = 'Focus+', section = 'Ability' },
    { key = 'CounterstanceEffect', label = 'Counterstance+', section = 'Ability' },
    { key = 'PerfectCounterAttack', label = 'Perf.Counter Att', section = 'Ability' },
    { key = 'FootworkAttack', label = 'Footwork Att', section = 'Ability' },
    -- WHM
    { key = 'DivineVeil', label = 'Divine Veil', section = 'Ability', percent = true },   -- trait: Divine Veil always active, -na spells work AoE (Henrik-confirmed)
    { key = 'AfflatusSolaceBonus', label = 'Solace+', section = 'Ability' },
    { key = 'AuspiceEffect', label = 'Auspice+', section = 'Ability' },
    -- PLD
    { key = 'ShieldBash', label = 'Shield Bash+', section = 'Ability' },   -- flat dmg
    { key = 'WeaponBash', label = 'Weapon Bash+', section = 'Ability' },
    { key = 'SentinelEffect', label = 'Sentinel+', section = 'Ability' },
    { key = 'RampartDuration', label = 'Rampart Dur.', section = 'Ability' },
    { key = 'HolyCircleDuration', label = 'H.Circle Dur.', section = 'Ability' },
    { key = 'HolyCirclePotency', label = 'H.Circle+', section = 'Ability' },
    { key = 'CoverToMP', label = 'Cover->MP', section = 'Ability' },
    { key = 'CoverMagicRanged', label = 'Cover M/R', section = 'Ability' },   -- cover extends to magic/ranged
    { key = 'CoverDuration', label = 'Cover Dur.', section = 'Ability' },
    { key = 'ReprisalBlockBonus', label = 'Reprisal Block+', section = 'Ability' },
    { key = 'ReprisalSpikesBonus', label = 'Reprisal Spikes+', section = 'Ability' },
    { key = 'DivineEmblemBonus', label = 'Divine Emblem+', section = 'Ability' },
    -- DRK
    { key = 'ArcaneCircleDuration', label = 'A.Circle Dur.', section = 'Ability' },
    { key = 'ArcaneCirclePotency', label = 'A.Circle+', section = 'Ability' },
    { key = 'SouleaterEffect', label = 'Souleater+', section = 'Ability', percent = true },   -- extra HP% converted
    { key = 'StalwartSoul', label = 'Stalwart Soul', section = 'Ability' },
    { key = 'BloodWeaponBonus', label = 'Blood Weapon+', section = 'Ability' },
    { key = 'DreadSpikesEffect', label = 'Dread Spikes+', section = 'Ability' },
    -- BST
    { key = 'RewardHPBonus', label = 'Reward HP', section = 'Ability' },
    { key = 'RewardRecast', label = 'Reward Recast-', section = 'Ability' },   -- VERIFY: sign (positive stored = seconds reduced?)
    { key = 'TameSuccess', label = 'Tame+', section = 'Ability' },
    { key = 'SicReadyRecast', label = 'Sic/Ready Recast-', section = 'Ability' },
    { key = 'SpurBonus', label = 'Spur+', section = 'Ability' },   -- pet att+
    -- BRD songs
    { key = 'AllSongsEffect', label = 'All Songs+', section = 'Ability' },   -- Gjallarhorn
    { key = 'MaximumSongs', label = 'Max Songs+', section = 'Ability' },   -- Daurdabla
    { key = 'SongRecast', label = 'Song Recast-', section = 'Ability' },   -- positive stored = seconds reduced; also augment id 337
    { key = 'MarchEffect', label = 'March+', section = 'Ability' },
    { key = 'MadrigalEffect', label = 'Madrigal+', section = 'Ability' },
    { key = 'LullabyEffect', label = 'Lullaby+', section = 'Ability' },
    { key = 'MinuetEffect', label = 'Minuet+', section = 'Ability' },
    { key = 'PaeonEffect', label = 'Paeon+', section = 'Ability' },
    { key = 'EtudeEffect', label = 'Etude+', section = 'Ability' },
    { key = 'BalladEffect', label = 'Ballad+', section = 'Ability' },
    { key = 'RequiemEffect', label = 'Requiem+', section = 'Ability' },
    { key = 'ThrenodyEffect', label = 'Threnody+', section = 'Ability' },
    { key = 'FinaleEffect', label = 'Finale+', section = 'Ability' },
    { key = 'CarolEffect', label = 'Carol+', section = 'Ability' },
    { key = 'ElegyEffect', label = 'Elegy+', section = 'Ability' },
    { key = 'MazurkaEffect', label = 'Mazurka+', section = 'Ability' },
    { key = 'HymnusEffect', label = 'Hymnus+', section = 'Ability' },
    { key = 'VirelaiEffect', label = 'Virelai+', section = 'Ability' },
    { key = 'MinneEffect', label = 'Minne+', section = 'Ability' },
    { key = 'PreludeEffect', label = 'Prelude+', section = 'Ability' },
    { key = 'ScherzoEffect', label = 'Scherzo+', section = 'Ability' },
    { key = 'MamboEffect', label = 'Mambo+', section = 'Ability' },
    -- RNG
    { key = 'VelocitySnapshotBonus', label = 'Velocity Snapshot', section = 'Ability' },
    { key = 'VelocityRAttBonus', label = 'Velocity R.Att', section = 'Ability' },
    { key = 'BarrageAcc', label = 'Barrage Acc', section = 'Ability' },   -- flat acc during Barrage
    { key = 'ScavengeEffect', label = 'Scavenge+', section = 'Ability' },
    { key = 'CamouflageDuration', label = 'Camouflage Dur.', section = 'Ability' },
    { key = 'BountyShotTH', label = 'Bounty Shot TH+', section = 'Ability' },
    { key = 'TrueShotEffect', label = 'True Shot+', section = 'Ability' },
    -- SAM
    { key = 'MeditateDuration', label = 'Meditate Dur.', section = 'Ability' },
    { key = 'ThirdEyeCounter', label = '3rd Eye Counter', section = 'Ability', percent = true },
    { key = 'ThirdEyeRetention', label = '3rd Eye Ret.', section = 'Ability', percent = true },
    { key = 'SengikoriBonus', label = 'Sengikori+', section = 'Ability' },
    { key = 'WardingCircleDuration', label = 'W.Circle Dur.', section = 'Ability' },
    { key = 'WardingCirclePotency', label = 'W.Circle+', section = 'Ability' },
    -- NIN
    { key = 'MijinReraise', label = 'Mijin Reraise', section = 'Ability' },   -- Nagi
    { key = 'FutaeBonus', label = 'Futae+', section = 'Ability' },
    -- DRG
    { key = 'JumpAttack', label = 'Jump Att.', section = 'Ability' },
    { key = 'JumpTP', label = 'Jump TP', section = 'Ability' },   -- flat literal TP
    { key = 'JumpCrit', label = 'Jump Crit', section = 'Ability' },   -- jumps always crit (Ryunohige)
    { key = 'HighJumpEnmity', label = 'H.Jump Enmity-', section = 'Ability' },
    { key = 'JumpDoubleAttack', label = 'Jump Dbl.Atk', section = 'Ability' },
    { key = 'JumpSpiritTP', label = 'Spirit Jump TP', section = 'Ability' },
    { key = 'JumpSoulSpiritAttack', label = 'Soul/Spirit Jump Att', section = 'Ability' },
    { key = 'SpiritLinkBonus', label = 'Spirit Link+', section = 'Ability' },
    { key = 'AncientCircleDuration', label = 'An.Circle Dur.', section = 'Ability' },
    { key = 'AncientCirclePotency', label = 'An.Circle+', section = 'Ability' },
    -- SMN
    { key = 'BloodBoon', label = 'Blood Boon', section = 'Ability', percent = true },   -- BP MP cost occ. reduced
    { key = 'AvatarsFavorBonus', label = 'Avatar\'s Favor+', section = 'Ability' },
    { key = 'ElementalSiphonBonus', label = 'Elem. Siphon+', section = 'Ability' },   -- flat MP
    { key = 'ManaCedeBonus', label = 'Mana Cede+', section = 'Ability' },   -- flat MP
    -- BLU
    { key = 'BurstAffinityBonus', label = 'Burst Affinity+', section = 'Ability' },
    { key = 'ChainAffinityBonus', label = 'Chain Affinity+', section = 'Ability' },
    -- COR
    { key = 'PhantomDuration', label = 'Roll Dur.', section = 'Ability' },
    { key = 'PhantomRoll', label = 'Roll Potency', section = 'Ability' },
    { key = 'RollRange', label = 'Roll Range', section = 'Ability' },   -- yalms
    { key = 'RollAllies', label = 'Roll (allies)', section = 'Ability' },
    { key = 'RandomDealBonus', label = 'Random Deal+', section = 'Ability' },
    { key = 'CoursersRollBonus', label = 'Courser\'s Roll+', section = 'Ability' },   -- AF3 set; 100 = full enhancement flag
    { key = 'CastersRollBonus', label = 'Caster\'s Roll+', section = 'Ability' },
    { key = 'BlitzersRollBonus', label = 'Blitzer\'s Roll+', section = 'Ability' },
    { key = 'AlliesRollBonus', label = 'Allies\' Roll+', section = 'Ability' },
    { key = 'TacticiansRollBonus', label = 'Tactician\'s Roll+', section = 'Ability' },
    { key = 'JobBonusChance', label = 'Job Bonus %', section = 'Ability', percent = true },   -- roll job bonus without the job
    { key = 'QuickDrawMACC', label = 'Q.Draw M.Acc', section = 'Ability' },
    { key = 'QuickDrawDamage', label = 'Q.Draw Dmg', section = 'Ability' },   -- flat
    { key = 'QuickDrawDamagePct', label = 'Q.Draw Dmg %', section = 'Ability', percent = true },
    -- PUP
    { key = 'OverloadThreshold', label = 'Overload Thresh.', section = 'Ability' },
    { key = 'SuppressOverload', label = 'Overload-', section = 'Ability' },   -- Kenkonken
    { key = 'ManeuverBonus', label = 'Maneuver+', section = 'Ability' },
    { key = 'RepairEffect', label = 'Repair+', section = 'Ability' },
    { key = 'RepairPotency', label = 'Repair Pot.', section = 'Ability', percent = true },
    -- DNC
    { key = 'SambaDuration', label = 'Samba Dur.', section = 'Ability' },
    { key = 'SambaPDuration', label = 'Samba Dur.%', section = 'Ability', percent = true },
    { key = 'JigDuration', label = 'Jig Dur.', section = 'Ability', percent = true },
    { key = 'WaltzDelay', label = 'Waltz Recast-', section = 'Ability', lowerBetter = true },   -- stored negative
    { key = 'StepTPConsumed', label = 'Step TP-', section = 'Ability', lowerBetter = true },   -- stored negative
    { key = 'StepFinish', label = 'Step Finish+', section = 'Ability' },   -- extra finishing moves
    { key = 'VFlourishMACC', label = 'V.Flourish M.Acc', section = 'Ability' },
    { key = 'ReverseFlourishEffect', label = 'Rev.Flourish+', section = 'Ability' },
    { key = 'MaxFinishingMoves', label = 'Max Finish+', section = 'Ability' },
    -- RUN
    { key = 'PflugBonus', label = 'Pflug+', section = 'Ability' },
    { key = 'ValianceVallationDuration', label = 'Valiance Dur.', section = 'Ability' },
    { key = 'SwordplayBonus', label = 'Swordplay+', section = 'Ability' },
    { key = 'GambitDuration', label = 'Gambit Dur.', section = 'Ability' },
    { key = 'BattutaBonus', label = 'Battuta+', section = 'Ability' },
    { key = 'LiementBonus', label = 'Liement+', section = 'Ability' },
    { key = 'LiementArea', label = 'Liement AoE', section = 'Ability' },   -- Epeolatry
    { key = 'VivaciousPulsePotency', label = 'V.Pulse+', section = 'Ability' },
    { key = 'VivaciousPulseBonus', label = 'V.Pulse Aug.', section = 'Ability' },
    { key = 'SwipeBonus', label = 'Swipe+', section = 'Ability' },   -- Swipe/Lunge (Aettir)
    -- THF
    { key = 'Despoil', label = 'Despoil+', section = 'Ability' },
    { key = 'MugEffect', label = 'Mug+', section = 'Ability' },
    { key = 'TrickAttackAGI', label = 'TA AGI+%', section = 'Ability', percent = true },   -- AGI% added to Trick Attack
    { key = 'SneakAttackDEX', label = 'SA DEX+%', section = 'Ability', percent = true },
    { key = 'HideDuration', label = 'Hide Dur.', section = 'Ability' },
    { key = 'AccompliceBonus', label = 'Accomplice+', section = 'Ability' },   -- Accomplice/Collaborator
    { key = 'FleeDuration', label = 'Flee Dur.', section = 'Ability' },
    -- SCH
    { key = 'AlacrityCelerityBonus', label = 'Alacrity/Celerity+', section = 'Ability' },
    { key = 'RaptureAmount', label = 'Rapture+', section = 'Ability' },
    { key = 'EbullienceAmount', label = 'Ebullience+', section = 'Ability' },
    -- GEO
    { key = 'GeomancyBonus', label = 'Geomancy+', section = 'Ability' },   -- indi/geo potency (Idris)
    { key = 'IndiDuration', label = 'Indi Dur.', section = 'Ability' },
    { key = 'CardinalChantBonus', label = 'Cardinal Chant+', section = 'Ability' },
    { key = 'FullCircleBonus', label = 'Full Circle+', section = 'Ability' },
    { key = 'LifeCycleEffect', label = 'Life Cycle+', section = 'Ability' },
    -- BLM (relic)
    { key = 'ElementalSealBonus', label = 'Elem. Seal+', section = 'Ability' },   -- Laevateinn

    -- ---- Pet (new section, approved 2026-07-14) ----
    { key = 'Pet_STR', label = 'Pet STR', section = 'Pet' },   -- augment id 1792; first of the Pet_ attribute family
    { key = 'Pet_AttDef', label = 'Pet Att/DEF', section = 'Pet' },
    { key = 'Pet_AccEva', label = 'Pet Acc/Eva', section = 'Pet' },
    { key = 'Pet_TPBonus', label = 'Pet TP Bonus', section = 'Pet' },   -- literal TP
    { key = 'AvatarLevel', label = 'Avatar Lv.+', section = 'Pet' },
    { key = 'CarbuncleLevel', label = 'Carbuncle Lv.+', section = 'Pet' },
    { key = 'CaitSithLevel', label = 'Cait Sith Lv.+', section = 'Pet' },
    { key = 'PerpetuationCarbuncle', label = 'Carby Perp-', section = 'Pet' },   -- halves carbuncle perpetuation
    { key = 'PerpetuationDay', label = 'Day Perp-', section = 'Pet' },
    { key = 'PerpetuationWeather', label = 'Weather Perp-', section = 'Pet' },
    { key = 'AutomatonLevel', label = 'Automaton Lv.+', section = 'Pet' },
    { key = 'AutoMeleeSkill', label = 'Auto Melee', section = 'Pet' },   -- automaton skills
    { key = 'AutoRangedSkill', label = 'Auto Ranged', section = 'Pet' },
    { key = 'AutoMagicSkill', label = 'Auto Magic', section = 'Pet' },
    { key = 'WyvernBreath', label = 'Wyvern Breath', section = 'Pet' },   -- healing-breath trigger HP threshold
    { key = 'WyvernEffectiveBreath', label = 'Wyvern Breath+', section = 'Pet' },
    { key = 'WyvernBreathMACC', label = 'Wyvern Breath M.Acc', section = 'Pet' },
    { key = 'WyvernSubjobTraits', label = 'Wyvern Subjob', section = 'Pet' },
    { key = 'WyvernLevel', label = 'Wyvern Lv.+', section = 'Pet' },
    { key = 'JugLevelRange', label = 'Jug Lv.Range', section = 'Pet' },
    { key = 'FamiliarBonus', label = 'Familiar+', section = 'Pet' },
    { key = 'TandemStrikePower', label = 'Tandem Strike+', section = 'Pet' },
    { key = 'TandemBlowPower', label = 'Tandem Blow+', section = 'Pet' },
    -- pet-channel-only mods (item_mods_pet / gen_petmods.py; no master-side carrier known)
    { key = 'MainDMGRating', label = 'Pet Weapon DMG', section = 'Pet' },
    { key = 'MonsterCorrelation', label = 'Pet Correlation', section = 'Pet' },   -- pet acc/att vs weaker ecosystem
};

--[[ ADOPTION STATE (2026-07-14 round complete -- 302 entries added, all row-by-row
     approved by Henrik; see tools/api_cache/stats_tiers2.txt for the full disposition).

     Still UNMAPPED by choice: proc/latent machinery, race locks, relic aftermath ids,
     mythic-specific "Augments" mods (the sheet's SKIP + relic-range buckets), and the
     INVESTIGATE bucket (CatsEyeXI 2000-series customs, gathering RESULT mods) pending
     identification. Entries marked VERIFY above ship with their proposed reading --
     grep VERIFY before trusting their scale/sign in anything numeric.
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

-- 'Pet:'-prefixed keys = the pet-channel WEIGHT namespace (gearoracle.petScoreStats
-- flattens data\petmods.lua under them so pet values can be priced without ever
-- colliding with master stats). Not rows in M.list -- the family is derived: the
-- inner stat resolves normally and wears a 'Pet: ' label prefix, section 'Pet'.
local function petInner(key)
    return string.match(key, '^[Pp][Ee][Tt]:(.+)$');
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
    if e == nil then
        local inner = petInner(key);
        if inner ~= nil then
            local ie = M.get(inner);
            return { key = 'Pet:' .. ie.key, label = 'Pet: ' .. (ie.label or ie.key), section = 'Pet' };
        end
    end
    return e or { key = key, label = key, section = 'Misc' };
end

-- Canonical key for any spelling (alias-aware); returns the input unchanged if unknown.
function M.canon(key)
    if type(key) ~= 'string' then return key; end
    if M.byKey[key] ~= nil then return key; end
    local a = M.aliasOf[string.lower(key)];
    if a ~= nil then return a; end
    local inner = petInner(key);
    if inner ~= nil then return 'Pet:' .. M.canon(inner); end
    return key;
end

return M;
