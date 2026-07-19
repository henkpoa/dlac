# BLU midcast import payload — groups + weights

Paste-ready data for Blue Mage midcast automation, derived from the CatsEyeXI server
source investigation (2026-07-19, Catsandboats layer: `scripts/globals/bluemagic.lua`,
per-spell params, `magic_hit_rate.lua`, `charentity.cpp`). Spell categorization is
Henrik's table, taken as CORRECT for the live server (the hidden CEXI repo layers custom
changes over Catsandboats — the documented wiki changes confirm the post-75 spells:
<https://www.bg-wiki.com/ffxi/CatsEyeXI_Systems/Jobs#Spells>).

## How to use

1. **Groups** — Triggers tab > Groups > *Import Lua Table(s)*: paste the Groups block.
2. **Weights** — Weights editor (Sets tab > Weights) > *import...*: paste the Weights
   block. One Saved Set lands per category, named to MATCH its group.
3. Per category: create/bind a midcast set (e.g. `Midcast_STRDEX`), open its weights,
   *copy from... > Saved Sets > STR_DEX*, Auto-build, Commit; then point a Midcast
   trigger for the group at the set.

Names avoid characters that need bracket-quoting, but dashed set names (e.g.
`Midcast_STR-VIT`) commit fine since 2026-07-19 — the serializer bracket-quotes
non-identifier names.

## Scaling facts the weights encode (server source)

- **TP does nothing outside Chain Affinity / Azure Lore.** Under CA the damage
  multiplier interpolates over the spell's tp150/tp300 values and "varies with TP"
  side-effects (crit%, acc) activate; AL substitutes the max values. The CA/AL spell
  also consumes ALL TP and is the only way blue magic skillchains (or magic bursts).
  Midcast weights therefore ignore TP entirely.
- **Physical** spells roll normal melee Accuracy for hit rate, Attack vs DEF for pDIF;
  base D comes from Blue Magic skill but is HARD-CAPPED per spell (the strongest spells
  stop gaining around 330 total skill; a merited 75 BLU sits at 292 before gear —
  hence the gear-side cap of ~40 on skill). STR always adds (fSTR ~0.5 D/pt + 0.5
  Attack/pt); the category's WSC stat adds ~0.17 D per point per 0.2 coefficient.
- **Cannonball** substitutes YOUR Defense for Attack in pDIF — the small DEF weight in
  the VIT profile exists only for it.
- **Magical** spells gain nothing from skill damage-wise (base D = level+2): INT (WSC +
  dINT) and MAB carry the damage; skill and MACC only defeat resists.
- **Debuffs/added effects** resist-check with dINT + Blue Magic skill (1:1 macc) + MACC
  gear, and the resist tier also multiplies duration.
- **Cures** = 3×MND + VIT (Healing skill only via subjob) + Cure Potency (50% cap).
- **Breaths** = currentHP / divisor; Breath Dmg% gear multiplies (1% ≈ several HP-points
  worth); MACC defends the resist.
- **Blu_Skill** buffs: Metallic Body stoneskin = 0.375×skill+12.5, Diamondhide = ⅔×skill
  — skill is the only stat. The Domain nukes in that category are taken as
  skill-scaled per Henrik's table (hidden-repo custom).
- **BluMagDiffus**: CEXI change (8-22-2024) — Diffusion'd blue magic gains from
  Enhancing Magic Duration gear.

## Groups (paste into Triggers > Groups > Import Lua Table(s))

Note: the source table had `'CMain Wave'` in Debuff — imported here as `'Cold Wave'`
(the frost AGI-down AoE; the only plausible expansion). Client-abbreviated spellings
(`'Winds of Promy.'`, `'Nat. Meditation'`, `'Quad. Continuum'`) are kept verbatim.

```lua
STR_DEX = T{'Foot Kick', 'Wild Oats', 'Queasyshroom', 'Battle Dance', 'Feather Storm', 'Helldive',
            'Bludgeon', 'Claw Cyclone', 'Screwdriver', 'Smite of Rage', 'Pinecone Bomb', 'Jet Stream',
            'Uppercut', 'Terror Touch', 'Mandibular Bite', 'Sickle Slash', 'Dimensional Death',
            'Spiral Spin', 'Death Scissors', 'Seedspray', 'Hydro Shot', 'Frenetic Rip', 'Spinal Cleave',
            'Hysteric Barrage', 'Asuran Claws', 'Disseverment', 'Ram Charge', 'Vertical Cleave', 'Final Sting',
            'Goblin Rush', 'Vanity Dive', 'Whirl of Rage', 'Benthic Typhoon', 'Empty Thrash',
            'Delta Thrust', 'Heavy Strike', 'Quadrastrike', 'Tourbillion', 'Amorphic Spikes', 'Barbed Crescent',
            'Bilgestorm', 'Bloodrake', 'Paralyzing Triad', 'Thrashing Assault',
            'Sinker Drill', 'Sweeping Gouge', 'Saurian Slide', 'Glutinous Dart' },
STR_VIT = T{'Quad. Continuum' },
VIT     = T{'Cannonball', 'Tail Slap', 'Body Slam', 'Grand Slam', 'Sprout Smack', 'Power Attack', 'Sub-zero Smash'},
Debuff  = T{'Filamented Hold', 'Cimicine Discharge', 'Demoralizing Roar', 'Venom Shell', 'Light of Penance',
            'Sandspray', 'Auroral Drape', 'Frightful Roar', 'Enervation', 'Infrasonics', 'Lowing', 'Cold Wave',
            'Awful Eye', 'Voracious Trunk', 'Sheep Song', 'Soporific', 'Yawn', 'Dream Flower', 'Chaotic Eye',
            'Sound Blast', 'Blank Gaze', 'Stinking Gas', 'Geist Wall', 'Feather Tickle', 'Reaving Wind',
            'Mortal Ray', 'Absolute Terror', 'Blistering Roar', 'Cruel Joke'},
Stun    = T{'Head Butt', 'Frypan', 'Sudden Lunge'},
Buff    = T{'Refueling', 'Feather Barrier', 'Memento Mori', 'Zephyr Mantle', 'Warm-Up',
            'Amplification', 'Triumphant Roar', 'Saline Coat', 'Reactor Cool', 'Plasma Charge',
            'Regeneration', 'Animating Wail', 'Battery Charge', 'Winds of Promy.', 'Barrier Tusk',
            'Orcish Counterstance', 'Pyric Bulwark', 'Nat. Meditation', 'Cocoon', 'Restoral', 'Erratic Flutter',
            'Carcharian Verve', 'Harden Shell', 'Mighty Guard'},
Blu_Skill = T{'Metallic Body', 'Diamondhide', 'Spectral Floe', 'Tenebral Crush', 'Scouring Spate', 'Anvil Lightning'},
BluMagDiffus = T{'Erratic Flutter', 'Harden Shell', 'Mighty Guard' },
MND     = T{'Pollen', 'Magic Hammer', 'Healing Breeze', 'Wild Carrot', 'Magic Fruit', 'Plenilune Embrace'},
Magic   = T{'Firespit' },
HP      = T{'Heat Breath'},
Enmity  = T{'Actinic Burst', 'Exuviation', 'Fantod', 'Jettatura', 'Temporal Shift'}
```

## Weights (paste into Weights editor > import...)

Points mode; a value is `pts` or `{ pts, cap }` — the cap is the GEAR-side total beyond
which the stat stops scoring (Blue Magic skill: 292 base at 75 w/ 8/8 merits, physical
D caps land ~330 total → gear cap 40; Cure Potency caps at 50%).

```lua
STR_DEX = {
    Accuracy = 12,
    Attack = 10,
    STR = 10,
    DEX = 4,
    BlueMagicSkill = { 3, 40 },
},
STR_VIT = {
    Accuracy = 12,
    Attack = 10,
    STR = 10,
    VIT = 3,
    BlueMagicSkill = { 3, 40 },
},
VIT = {
    Accuracy = 12,
    Attack = 9,
    STR = 8,
    VIT = 5,
    DEF = 3,
    BlueMagicSkill = { 3, 40 },
},
Debuff = {
    MACC = 12,
    BlueMagicSkill = 12,
    INT = 10,
},
Stun = {
    Accuracy = 12,
    MACC = 10,
    BlueMagicSkill = 10,
    INT = 8,
    Attack = 3,
},
Buff = {
    SpellInterruptionRateDown = 10,
},
Blu_Skill = {
    BlueMagicSkill = 12,
    MACC = 6,
    MAB = 4,
    INT = 3,
},
BluMagDiffus = {
    EnhancingMagicDuration = 12,
    SpellInterruptionRateDown = 6,
},
MND = {
    CurePotency = { 15, 50 },
    MND = 10,
    VIT = 3,
},
Magic = {
    MAB = 12,
    INT = 10,
    MACC = 6,
    BlueMagicSkill = 3,
},
HP = {
    BreathDamage = 15,
    HP = 3,
    MACC = 3,
},
Enmity = {
    Enmity = 12,
    MACC = 8,
    BlueMagicSkill = 6,
    INT = 5,
    SpellInterruptionRateDown = 4,
}
```

## Per-category rationale (one line each)

| Profile | Why |
|---|---|
| STR_DEX / STR_VIT | Physical engine: a miss is 0 (Acc first), Attack multiplies via pDIF, STR triple-dips (fSTR + WSC + 0.5 Att/pt); the WSC partner stat is worth ~⅙ point of D per point. |
| VIT | Same, plus a token DEF for Cannonball's DEF-based pDIF. |
| Debuff | Landing is everything: MACC gear + Blue skill (1:1 macc) + dINT; duration scales with the resist roll too. |
| Stun | Physical hit first (melee Acc), then the stun proc's macc chain (INT-based). |
| Buff | Nothing scales potency; only casting uninterrupted matters. |
| Blu_Skill | Metallic/Diamondhide stoneskin is pure skill; Domain nukes taken as skill-scaled per the table. |
| BluMagDiffus | CEXI 8-22-2024: Diffusion'd spells honor Enhancing Magic Duration gear. |
| MND | Cure power = 3×MND + VIT; Cure Potency multiplies (capped 50%). |
| Magic | Magical engine: INT (WSC + dINT) and MAB carry damage; skill is macc-only. |
| HP | Breath = current HP ÷ divisor; Breath Dmg% is worth several HP-points per %. |
| Enmity | The stat the set exists for, plus enough macc that Jettatura/Actinic actually stick. |
