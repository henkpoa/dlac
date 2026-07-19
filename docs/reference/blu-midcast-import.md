# BLU midcast import payload — groups + weights (corrected)

Paste-ready data for Blue Mage midcast automation, derived from the CatsEyeXI server
source investigation (2026-07-19, Catsandboats layer: `scripts/globals/bluemagic.lua`,
per-spell params, `magic_hit_rate.lua`, `charentity.cpp`). Base categorization is
Henrik's table; corrections were applied ONLY where the visible server source (or, for
Final Sting, unambiguous retail lore) contradicts the category — post-75 spells with no
visible source stay where Henrik put them (the hidden CEXI repo is authoritative there;
documented changes: <https://www.bg-wiki.com/ffxi/CatsEyeXI_Systems/Jobs#Spells>).

## Corrections applied to the original table

- `'CMain Wave'` → `'Cold Wave'` (typo; the frost AGI-down AoE).
- **New `AGI` group** — clone-verified `agi_wsc` spells moved out of STR_DEX:
  Wild Oats, Feather Storm, Helldive, Pinecone Bomb (STR+AGI), Jet Stream,
  Spiral Spin, Hydro Shot.
- **`Magic` populated** — every clone-verified INT-attribute magical nuke added
  (Death Ray, Bomb Toss, Cursed Sphere, Blastbomb, Blitzstrahl, Ice Break, Maelstrom,
  Sandspin, Corrosive Ooze, Regurgitation, Rending Deluge) plus wiki-live Acrid Stream
  and Blazing Bound.
- **New `Magic_CHR`** (Eyes On Me, Mysterious Light — dCHR magical) and
  **`Magic_MND`** (Magic Hammer — moved out of MND, Mind Blast — dMND magical).
- **`Blu_Skill` extended** — the other four wiki-live Domain nukes (Searing Tempest,
  Blinding Fulgor, Silent Storm, Entomb; same family as Spectral Floe et al.) and the
  drains (Blood Drain, Blood Saber, Digest, MP Drainkiss), whose damage is
  `floor(skill × 0.11) × mult` — skill IS the damage stat.
- **`HP` populated** — all breath spells (damage = current HP ÷ divisor): Poison/Frost/
  Radiant Breath, Magnetite Cloud, Hecatomb Wave, Bad Breath, Flying Hip Press,
  Self-Destruct; plus **Final Sting moved from STR_DEX** (retail-derived: damage varies
  with current HP — flag if the hidden repo made it physical).
- **`Buff` gains Magic Barrier** (wiki-live defensive buff). Osmosis is live but left
  uncategorized (absorb mechanics unverified).
- Oddballs KEPT in STR_DEX with wrong-but-minor WSC stats (partner stat ≈ 0.17 D/pt,
  noise next to Acc/Att/STR): Queasyshroom (INT), Bludgeon (CHR), Terror Touch
  (DEX/INT), Mandibular Bite (STR/INT), Screwdriver (STR/MND), Ram Charge (STR/MND).

## How to use

1. **Groups** — Triggers tab > Groups > *Import Lua Table(s)*: paste the Groups block
   (re-importing overwrites same-named groups with these members).
2. **Weights** — Weights editor (Sets tab > Weights) > *import...*: paste the Weights
   block. One Saved Set per category, named to MATCH its group.
3. Per category: create/bind a midcast set, *copy from... > Saved Sets > <name>*,
   Auto-build, Commit; point the group's Midcast trigger at the set.

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
- **Magical** spells gain nothing from skill damage-wise (base D = level+2): the
  attribute stat (INT/MND/CHR: WSC + dStat) and MAB carry the damage; skill and MACC
  only defeat resists.
- **Debuffs/added effects** resist-check with dINT + Blue Magic skill (1:1 macc) + MACC
  gear, and the resist tier also multiplies duration.
- **Cures** = 3×MND + VIT (Healing skill only via subjob) + Cure Potency (50% cap).
- **Breaths** = currentHP / divisor; Breath Dmg% gear multiplies (1% ≈ several HP-points
  worth); MACC defends the resist.
- **Blu_Skill**: Metallic Body stoneskin = 0.375×skill+12.5, Diamondhide = ⅔×skill;
  drains = skill×0.11; Domain nukes taken as skill-scaled per Henrik's table.
- **BluMagDiffus**: CEXI change (8-22-2024) — Diffusion'd blue magic gains from
  Enhancing Magic Duration gear.

## Groups (paste into Triggers > Groups > Import Lua Table(s))

```lua
STR_DEX = T{'Foot Kick', 'Queasyshroom', 'Battle Dance', 'Bludgeon', 'Claw Cyclone', 'Screwdriver',
            'Smite of Rage', 'Uppercut', 'Terror Touch', 'Mandibular Bite', 'Sickle Slash',
            'Dimensional Death', 'Death Scissors', 'Seedspray', 'Frenetic Rip', 'Spinal Cleave',
            'Hysteric Barrage', 'Asuran Claws', 'Disseverment', 'Ram Charge', 'Vertical Cleave',
            'Goblin Rush', 'Vanity Dive', 'Whirl of Rage', 'Benthic Typhoon', 'Empty Thrash',
            'Delta Thrust', 'Heavy Strike', 'Quadrastrike', 'Tourbillion', 'Amorphic Spikes',
            'Barbed Crescent', 'Bilgestorm', 'Bloodrake', 'Paralyzing Triad', 'Thrashing Assault',
            'Sinker Drill', 'Sweeping Gouge', 'Saurian Slide', 'Glutinous Dart' },
AGI     = T{'Wild Oats', 'Feather Storm', 'Helldive', 'Pinecone Bomb', 'Jet Stream', 'Spiral Spin',
            'Hydro Shot' },
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
            'Carcharian Verve', 'Harden Shell', 'Mighty Guard', 'Magic Barrier'},
Blu_Skill = T{'Metallic Body', 'Diamondhide', 'Spectral Floe', 'Tenebral Crush', 'Scouring Spate',
            'Anvil Lightning', 'Searing Tempest', 'Blinding Fulgor', 'Silent Storm', 'Entomb',
            'Blood Drain', 'Blood Saber', 'Digest', 'MP Drainkiss' },
BluMagDiffus = T{'Erratic Flutter', 'Harden Shell', 'Mighty Guard' },
MND     = T{'Pollen', 'Healing Breeze', 'Wild Carrot', 'Magic Fruit', 'Plenilune Embrace'},
Magic   = T{'Firespit', 'Death Ray', 'Bomb Toss', 'Cursed Sphere', 'Blastbomb', 'Blitzstrahl',
            'Ice Break', 'Maelstrom', 'Sandspin', 'Corrosive Ooze', 'Regurgitation', 'Rending Deluge',
            'Acrid Stream', 'Blazing Bound' },
Magic_CHR = T{'Eyes On Me', 'Mysterious Light' },
Magic_MND = T{'Magic Hammer', 'Mind Blast' },
HP      = T{'Heat Breath', 'Poison Breath', 'Frost Breath', 'Radiant Breath', 'Magnetite Cloud',
            'Hecatomb Wave', 'Bad Breath', 'Flying Hip Press', 'Self-Destruct', 'Final Sting'},
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
AGI = {
    Accuracy = 12,
    Attack = 10,
    STR = 8,
    AGI = 4,
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
    MACC = 8,
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
Magic_CHR = {
    MAB = 12,
    CHR = 10,
    MACC = 6,
    BlueMagicSkill = 3,
},
Magic_MND = {
    MAB = 12,
    MND = 10,
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

## Priority-list alternative (paste into Weights editor > Priority tab > import...)

The same tunings as ORDERED lists for the Priority tab (top matters most, caps where
the points version caps). Import here instead if the set should build waterfall-style;
apply via *copy from... > Saved Lists*.

```lua
STR_DEX = { 'Accuracy', 'Attack', 'STR', 'DEX', { 'BlueMagicSkill', 40 } },
AGI     = { 'Accuracy', 'Attack', 'STR', 'AGI', { 'BlueMagicSkill', 40 } },
STR_VIT = { 'Accuracy', 'Attack', 'STR', 'VIT', { 'BlueMagicSkill', 40 } },
VIT     = { 'Accuracy', 'Attack', 'STR', 'VIT', 'DEF', { 'BlueMagicSkill', 40 } },
Debuff  = { 'MACC', 'BlueMagicSkill', 'INT' },
Stun    = { 'Accuracy', 'MACC', 'BlueMagicSkill', 'INT', 'Attack' },
Buff    = { 'SpellInterruptionRateDown' },
Blu_Skill = { 'BlueMagicSkill', 'MACC', 'MAB', 'INT' },
BluMagDiffus = { 'EnhancingMagicDuration', 'SpellInterruptionRateDown' },
MND     = { { 'CurePotency', 50 }, 'MND', 'VIT' },
Magic   = { 'MAB', 'INT', 'MACC', 'BlueMagicSkill' },
Magic_CHR = { 'MAB', 'CHR', 'MACC', 'BlueMagicSkill' },
Magic_MND = { 'MAB', 'MND', 'MACC', 'BlueMagicSkill' },
HP      = { 'BreathDamage', 'HP', 'MACC' },
Enmity  = { 'Enmity', 'MACC', 'BlueMagicSkill', 'INT', 'SpellInterruptionRateDown' }
```

## Per-category rationale (one line each)

| Profile | Why |
|---|---|
| STR_DEX / STR_VIT | Physical engine: a miss is 0 (Acc first), Attack multiplies via pDIF, STR triple-dips (fSTR + WSC + 0.5 Att/pt); the WSC partner stat is worth ~⅙ point of D per point. |
| AGI | Same physical engine; AGI is only the WSC stat — Acc/Att/STR still carry. |
| VIT | Same, plus a token DEF for Cannonball's DEF-based pDIF. |
| Debuff | Landing is everything: MACC gear + Blue skill (1:1 macc) + dINT; duration scales with the resist roll too. |
| Stun | Physical hit first (melee Acc), then the stun proc's macc chain (INT-based). |
| Buff | Nothing scales potency; only casting uninterrupted matters. |
| Blu_Skill | Stoneskins and drains scale on raw skill; Domain nukes per the table; macc to land the nukes/drains. |
| BluMagDiffus | CEXI 8-22-2024: Diffusion'd spells honor Enhancing Magic Duration gear. |
| MND | Cure power = 3×MND + VIT; Cure Potency multiplies (capped 50%). |
| Magic / Magic_CHR / Magic_MND | Magical engine: MAB + the spell's attribute stat (dStat + WSC) carry damage; skill is macc-only. |
| HP | Breath = current HP ÷ divisor; Breath Dmg% is worth several HP-points per %. |
| Enmity | The stat the set exists for, plus enough macc that Jettatura/Actinic actually stick. |
