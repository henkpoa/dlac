# CatsEyeXI Custom Job Changes — Reference

- **Source:** https://www.bg-wiki.com/ffxi/CatsEyeXI_Systems/Jobs (full wikitext via MediaWiki API `action=parse`)
- **Fetched:** 2026-07-10
- **Scope:** the wiki page is the only per-job mechanics page under `CatsEyeXI_Systems/` (verified against the wiki's page index on the same date); links out of it go to quest/content/equipment pages, not job-mechanic sub-pages.

> **RULE: CatsEyeXI custom changes OVERRIDE retail/LSB assumptions — consult this
> before hardcoding any job mechanic.** Where the wiki and the server repo
> (CatsAndBoats/catseyexi, branch `base`) disagree, verify against the server
> source; where dlac can read live game memory (traits, abilities), prefer
> memory over both.

## Trust ladder (verified 2026-07-10)

The cross-checks below revealed something bigger than any single claim: **the
public server repo does not contain the job customizations at all.**

1. **Live game memory** — the only ground truth dlac can observe (e.g.
   `Player:HasAbility(1554)` for the Dual Wield trait bit; the server ships the
   computed trait/ability bitmask in packet 0x0AC).
2. **This wiki page** — documents intended live behavior, including changes the
   public source never shows. May lag or contain typos (one flagged below).
3. **Public repo SQL (`CatsAndBoats/catseyexi`, branches `base`/`stable`/`staging`)** —
   byte-identical to upstream `LandSandBoat/server` for every job row spot-checked
   (traits, abilities, spell_list, skill_ranks, blue_traits). The actual
   customizations live in **private git submodules**: `modules/catseyexi` →
   `github.com/catsandboats/modules` (404 publicly) and `src/map/cexi` →
   `github.com/catsandboats/cexi-src` (404 publicly). Treat the public SQL as
   "stock LSB", not as CatsEyeXI.

Server-wide context relevant to level gating:

- Level cap is **75**. `settings/default/main.lua` on `base` sets
  `ENABLE_ABYSSEA = 1` (all expansion/content tags enabled by default), so
  era-tagged rows are active — but any stock row above level 75 is unreachable
  unless a private module moves it down (which, per this wiki, is exactly what
  CatsEyeXI does for many abilities).

## Cross-check results (spot verification, 2026-07-10)

Checked against `CatsAndBoats/catseyexi` branch `base` (and re-checked on
`stable` and `staging` — identical), plus upstream `LandSandBoat/server`.

| # | Wiki claim | Public server SQL says | Verdict |
|---|---|---|---|
| V1 | THF gains Dual Wield I at 20, II at 40 (10-10-2024 update) | `sql/traits.sql`: THF (job 6) Dual Wield ranks at **83/90/98**, tagged `ABYSSEA` — identical to upstream LSB. DNC (job 19) has 20/40/60/80 `ABYSSEA`. | **Not in public source.** Live memory observation (the discovery that led to dlac's memory-based DW check) found THF without the trait at ≤75, contradicting the wiki's 20/40 claim too. Memory is authoritative; do not trust either static source for THF DW. |
| V2 | BLU gets Dual Wield from blue-magic trait sets | `sql/blue_traits.sql`: trait_category 25 grants traitid 18 (Dual Wield) at 2/4/6 set points (DW values 10/15/25). | **Verified** in public source. Inherently un-level-gateable — depends on set spells. |
| V3 | DRK Occult Acumen I at 37 ("down from 45") | `sql/traits.sql`: DRK ranks at 45/58/71/84/97 `ABYSSEA` (stock LSB). | **Not in public source** — lives in private modules. |
| V4 | WAR Blood Rage at 75 | `sql/abilities.sql`: `blood_rage` WAR level **87** (stock LSB). | **Not in public source.** |
| V5 | THF Accomplice and Collaborator at 40 | `sql/abilities.sql`: both at THF level **65**, tagged `WOTG` (stock LSB). dlac's generated `abilities.lua` carries 65. | **Not in public source.** |
| V6 | RNG Bounty Shot at 55 | `sql/abilities.sql`: level **87** (stock LSB). | **Not in public source.** |
| V7 | BLM Scythe E→C+; COR Marksmanship B→A and Club added at E; DNC Club added at E | `sql/skill_ranks.sql`: BLM scythe rank 10 (E); COR marksmanship rank 4 (B), club 0 (none); DNC club 0 (none) — all stock LSB. | **Not in public source.** |
| V8 | Custom spell access (WHM Enlight 75 / Arise 75 / Baramnesra 65; RDM Baramnesia 65; RUN Flash 38 / Crusade 56 / Baramnesia 63; DRK Absorb-Attri 75) | `sql/spell_list.sql` is stock retail: Enlight PLD 85 `ABYSSEA`; Arise WHM 99; Baramnesra WHM 78; Baramnesia RDM 78 / RUN 76; Crusade PLD/RUN 88 `SOA`; Absorb-Attri DRK 91 `SOA`; Flash RUN 45. | **Not in public source.** dlac's generated `spells.lua` inherited the stock values (Flash RUN 45) and dropped the >75 rows entirely. |

**Honest summary:** of the wiki's custom claims, only the BLU trait-set
mechanism (V2) is verifiable in public source, because it is retail behavior
LSB already implements. Every CatsEyeXI-specific level change checked (V1,
V3–V8) is absent from the public repo — not contradicted by a different custom
value, but simply stock LSB. The claims cannot be verified or falsified
against public source; they can only be confirmed in-game.

---

# Per-job changes

Everything below is transcribed from the wiki page with names and numbers
preserved verbatim. Dated parenthetical updates are the wiki's own.

## Warrior

### Abilities and Traits
- **Shield Mastery** acquired at level 40.
- **Retaliation** is now considered a "stance" and lasts 2 hours with a 1-minute recast.
- **Blood Rage** acquired at level 75. [V4]

## Monk

### Abilities and Traits
- The duration of the **Focus** and **Dodge** job abilities has been extended from 30 seconds to 75 seconds.
- The duration of **Footwork** has been extended from 60 seconds to 120 seconds.
- **Attack Bonus** I acquired at level 30, II at level 55, and III at level 70.
- **Smite** acquired at level 37.
- **Counterstance** is now considered a "stance" and lasts 2 hours with a 1-minute recast.
- **Smite II** acquired at level 75.
- **Perfect Counter** acquired at level 75.
- **Impetus** acquired at level 75.

### Adjustments
- The penalty to TP gained on hand-to-hand auto-attacks from Martial Arts delay reduction has been reduced by half.
- Crystal Warriors with a Black Belt may re-obtain their Brown Belt via a quest from *Raving Fist* in Mhaura (for use in level-cap content).

## White Mage

### Abilities and Traits
- Gains access to **Baramnesra** at level 65. [V8]
- Gains access to **Enlight** at level 75. Enlight is now a White Mage only spell. [V8]
- Gains access to **Arise** at level 75. Cost reduced to 150 MP and cast time reduced to 10 sec. [V8]

### Adjustments
- Bar-status spells scale with enhancing magic skill.

## Black Mage

### Abilities and Traits
- **Occult Acumen** I acquired at Lv60.
- **Occult Acumen** II acquired at Lv75.
- **Enmity Douse** acquired at Lv75.
- Gains access to **Tier V elemental spells** at Lv75. Obtainable from Higher VNMs (CatsEyeXI Ventures). Each spell is equal in power level and MP cost.

### Adjustments
- **Scythe** skill increased from E to C+, and can learn the weaponskill **Entropy**. [V7]

## Red Mage

- **Magic Burst Bonus** I acquired at Lv70.
- **Magic Atk. Bonus** III acquired at Lv75.
- Gains access to **Baramnesia** at level 65. [V8]
- **Inundation** is not currently learnable, and there are currently no plans to implement it.
- Bar-status spells scale with enhancing magic skill.

## Thief

### Abilities and Traits
- The **Trick Attack** ability transfers a portion of the thief's total enmity to the Trick Attack partner (not just the enmity from the attack itself).
- **Accomplice** and **Collaborator** acquired at level 40. [V5]
- **Assassin** at level 50.
- **Bully** at level 60.
- **Conspirator** at level 75.
- **Despoil** at level 75.

As of the 10-10-2024 update:
- **Dual Wield I** at level 20 [V1]
- **Dual Wield II** at level 40 [V1]

> **[V1] caution:** public server SQL keeps THF Dual Wield at 83/90/98
> (Abyssea-tagged, stock LSB), and dlac's live-memory observation found a
> ≤75 THF *without* the trait — which is why dlac reads the trait bit from
> memory instead of trusting any table. Treat the wiki's 20/40 claim as
> unconfirmed until observed live.

### Merits
- In addition to granting an accuracy bonus, **Ambush** merits also reduce the cooldown of **Sneak Attack** and **Trick Attack**.

### Weaponskills
- **Viper Bite** is obtained at 40 Dagger Skill (Level 13).
- **Wasp Sting** and **Viper Bite** have increased damage.

### Treasure Hunter

#### Max attainable
Hard cap on total Treasure Hunter from all sources (gear, traits, server bonuses):

To Thief main: **ACE 6 / CW 6 / WEW 8**

| TH | Item / source | Type |
|---|---|---|
| +2 | Native Treasure Hunter II trait at level 45 | All |
| +2 | Prestige (see below) | All |
| +1 | Thief's Knife or Vajra (do not stack) | All |
| +1 | Assassin's Armlets or augmented Rogue's Armlets +1 | All |
| +1 | White Rarab Cap +1 (from Exp Ventures) or augmented Dragon Cap +1 | All |
| +1 | Tartarus Platemail (A Winged Resurgence) | WEW |
| +1 | Talaria (A Winged Resurgence)* | WEW |
| +1 | Summit of the Stars Bonus (NPC: Lanira) | All |

To non-Thief main: **ACE 4 / CW 4 / WEW 4**

| TH | Item / source | Type |
|---|---|---|
| +4 | THF prestige level 5 | All |
| +2 | Avarice (from Venture Battles), OR | All |
| +1 | White Rarab Cap +1 | All |
| +1 | Native Treasure Hunter trait at level 15 /THF | All |
| +1 | Tartarus Platemail | WEW |
| +1 | Talaria* | WEW |
| +1 | Summit of the Stars Bonus | All |

\* Wiki footnote: "The team has discussed internally and decided to continue
allowing Telaria [sic] to be obtainable via the 'Gobbie Box'. If you've already
opened them this way, you are safe to keep them." — CEXI discord announcements,
12/20/2024.

#### Prestige
- TH+1 prestige bonus (THF main): THF prestige level 4+, and trade either a Rogue's Armlets +1 augmented with Treasure Hunter or a Dragon Cap +1 augmented with Treasure Hunter to Prestix in Upper Jeuno (items are returned).
- TH+2 prestige bonus (THF main): THF prestige level 5, and trade **both** augmented items to Prestix (returned after inspection).

#### Proc system (January 2025)
Chance to proc the next tier of TH on a mob. Table assumes character TH5 with
that TH gear equipped when attacking (adjust first column for other TH levels).
"Feint" = max-merited Feint on the attack or its evasion-down already applied.
Maximum TH tier proccable on CEXI is **12**.

| Mob's TH tier | Base proc chance | With Feint | SA *or* TA | SA *and* TA | Feint + (SA or TA) | Feint + SA + TA |
|---|---|---|---|---|---|---|
| 5 → 6 | 4% | 8% | 40% | 80% | 80% | 100% |
| 6 → 7 | 2% | 4% | 20% | 40% | 40% | 80% |
| 7 → 8 | 1% | 2% | 10% | 20% | 20% | 40% |
| 8 → 9 | 0.5% | 1% | 5% | 10% | 10% | 20% |
| 9 → 10 | 0.25% | 0.5% | 2.5% | 5% | 5% | 10% |
| 10 → 11 | 0.125% | 0.25% | 1.25% | 2.5% | 2.5% | 5% |
| 11 → 12 | 0.0625% | 0.125% | 0.625% | 1.25% | 1.25% | 2.5% |

## Paladin

**No changes.** (Explicitly stated by the wiki.)

## Dark Knight

### Abilities and Traits
- **Nether Void** acquired at level 75.
- **Scarlet Delirium** acquired at level 75.
- **Occult Acumen** I acquired at level 37 (down from 45). [V3]
- Gains access to **Absorb-Attri** at level 75. [V8]
- **Job Ability Haste** (e.g. from Desperate Blows, Hasso, Haste Samba) caps at **30% instead of 25%** on CatsEyeXI. Noted here due to DRK's unique ability to cap JA haste while Last Resort is active — players can get 25% from Desperate Blows and still benefit from JA haste from other sources. Equipment-based haste still caps at 25% as normal. *(Server-wide rule, documented under DRK.)*

### Weaponskills
- **Frostbite** and **Freezebite** have increased damage and apply **Frost** for a short duration.
- **Shadow of Death** has increased damage.

## Beastmaster

### Abilities and Traits
- **Call Beast** acquired at level 10 (see Custom Jugs).
- **Fencer** I acquired at level 60, and II acquired at level 75.
- **Stout Servant** acquired at level 75.

### Adjustments (jug pets)
Adjusted in two parts: Ready Strength and Stats.

**Ready Strength** — all jug pets' damage-dealing Ready abilities increased by:
- Job level factor: x/75 if main job, x/37 if sub job
- CHR factor: x/43 — **+CHR only**, not base CHR

Formula: increase = (% of max player level) + (% of CHR stat). Wiki examples:
- BST75 main, CHR+80: (75/75) + (80/43) = 1 + 1.86 = **2.86x** *(wiki's own arithmetic; its text shows "(100 / 43)" in one spot — transcribed as printed elsewhere)*
- BST60 main, CHR+20: (60/75) + (20/43) = 0.8 + 0.47 = **1.27x**
- BST30 sub, CHR+8: (30/37) + (8/43) = 0.81 + 0.28 = **1.09x** *(wiki's middle term prints "(12 / 43)"; inputs say CHR+8)*

Disclaimers (wiki): never a damage loss, only an increase; gear buffs still
count, this is a bonus on top. Recommend a `<wait 2>` after the Ready ability;
check CHR in case of latency.

**Stats** — ALL jug pets: DEF increased by a flat 10%.

Additional enmity for tanking:

| Jug pet | Enmity+ |
|---|---|
| Crab Familiar | 10 |
| Courier Carrie | 15 |
| Beetle Familiar | 10 |
| Panzer Galahad | 15 |

Added stats per pet (consolidated from the wiki's rowspan table):

| Jug pet | ACC+ | ATT+ | DEF+ |
|---|---|---|---|
| Sheep Familiar | 30 | 88 | 45 |
| Hare Familiar | 30 | 88 | 45 |
| Crab Familiar | 30 | 25 | 105 |
| Courier Carrie | 30 | 35 | 105 |
| Homunculus | 30 | 88 | 45 |
| Flytrap Familiar | 30 | 88 | 45 |
| Tiger Familiar | 30 | 88 | 45 |
| Flowerpot Bill | 30 | 88 | 45 |
| Eft Familiar | 30 | 88 | 45 |
| Lizard Familiar | 30 | 88 | 45 |
| Mayfly Familiar | 30 | 88 | 45 |
| Funguar Familiar | 30 | 88 | 45 |
| Beetle Familiar | 30 | 35 | 105 |
| Antlion Familiar | 30 | 88 | 45 |
| Mite Familiar | 30 | 113 | 0 |
| Lullaby Melodia | 30 | 88 | 45 |
| Keeneared Steffi | 30 | 88 | 45 |
| Flowerpot Ben | 30 | 88 | 45 |
| Saber Siravarde | 30 | 88 | 45 |
| Coldblood Como | 30 | 88 | 45 |
| Shellbuster Orob | 30 | 88 | 45 |
| Voracious Audrey | 30 | 88 | 45 |
| Ambusher Allie | 30 | 88 | 45 |
| Lifedrinker Lars | 30 | 113 | 0 |
| Panzer Galahad | 30 | 35 | 105 |
| Chopsuey Chucky | 30 | 88 | 45 |
| Amigo Sabotender | 30 | 88 | 45 |
| Turbid Toloi | 30 | 88 | 45 |

**Level cap** raised to 75 for these high-quality pets: Lullaby Melodia
(Sheep), Keeneared Steffi (Rabbit), Flowerpot Ben (Mandragora), Saber
Siravarde (Tiger), Coldblood Como (Lizard), Shellbuster Orob (Fly).

### Beast Raising (CatsEyeXI-exclusive)
Via the Bestiary Book (G-12) inside the Lower Jeuno Chocobo Stables.
- Bonuses apply to high-quality jug pets; fully leveled pets provide **aura effects for the whole party**.
- **Bonuses only apply when summoned by Call Beast — NOT via Bestial Loyalty.**
- Bestiary Book will not respond until you have acquired at least one pet.

Unlock: no level requirement; as BST, kill the source mobs below; random
chance to obtain the pet after the kill (NMs give higher chance).

Activities/feeding: one randomly selected activity per day plus one feeding
per day. Feeding (trade the listed food) 100 xp; Rest 200 xp; Kill targets
400 xp; Hot and Cold (`/think` in zone) 500 xp.

| Pet | Source (VC = very common, VR = very rare, R = rare drop) | Food | Activities | Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | Aura |
|---|---|---|---|---|---|---|---|---|---|
| Lullaby Melodia | Stray Mary (VC, Konschtat Highlands); Mad Sheep (VR, La Theine Plateau) | Boyahda Moss | 15 Huge Wasp (La Theine/Konschtat) 400xp; Hot and Cold (La Theine/Tahrongi) 500xp | Att+10 Def+10 | Att+15 Def+15 | Att+20 Def+20 | Att+25 Def+25 | Att+30 Def+30 | Attack +15% |
| Keeneared Steffi | Ratatoskr (VC, Fort Karugo-Narugo (S)); Beach Bunny (VR, Cape Teriggan) | San d'Or. Carrot | 15 Akbaba (La Theine/Tahrongi) 400xp | Acc+10 Eva+10 | Acc+15 Eva+15 | Acc+20 Eva+20 | Acc+25 Eva+25 | Acc+30 Eva+30 | Evasion +15% |
| Flowerpot Ben | Backoo (VC, Buburimu Peninsula); Mourioche (VR, The Boyahda Tree) | Yuhtunga Sulfur | 15 Canyon Crawler (La Theine) / 15 Carnivorous Crawler (Buburimu) 400xp | VIT+5 Att+5 | VIT+8 Att+8 | VIT+10 Att+10 | VIT+12 Att+12 | VIT+15 Att+15 | Counter +15% |
| Saber Siravarde | Tempest Tigon (VC, Carpenters' Landing); Wajaom Tiger (VR, Wajaom Woodlands) | G. Sheep Meat | 10 Goblin Butcher (Jugner Forest) / 10 Orcish Impaler (Batallia Downs) 400xp | DEX+5 Acc+10 | DEX+8 Acc+15 | DEX+10 Acc+20 | DEX+12 Acc+25 | DEX+15 Acc+30 | Critical Hit Rate +10% |
| Coldblood Como | Geyser Lizard (VC, Dangruf Wadi); Maze Lizard (VR, Crawlers' Nest) | Crawler Egg | 15 Raptor (Meriphataud Mountains); 10 Goblin Ambusher (Konschtat) 400xp; Hot and Cold (Tahrongi, ???) 500xp | INT+5 Acc+10 | INT+8 Acc+15 | INT+10 Acc+20 | INT+12 Acc+25 | INT+15 Acc+30 | Accuracy +30 |
| Shellbuster Orob | Elusive Edwin (VC, The Sanctuary of Zi'Tah); Monarch Ogrefly (VR, Attohwa Chasm) | Honey | 15 Coeurl (Meriphataud); 10 Yagudo Votary (Meriphataud) 400xp | DEX+5 MND+5 | DEX+8 MND+8 | DEX+10 MND+10 | DEX+12 MND+12 | DEX+15 MND+15 | MND +15% |
| Voracious Audrey | Lizardtrap (VC, Aydeewa Subterrane); Hawkertrap (R, Riverne - Site A01) | Skull Locust | 15 Forest Tiger (Carpenters' Landing, Jugner entrance); 10 Land Pugil (Carpenters' Landing, San d'Oria entrance) 400xp; Hot and Cold (Tahrongi) | AGI+5 INT+5 | AGI+8 INT+8 | AGI+10 INT+10 | AGI+12 INT+12 | AGI+15 INT+15 | Magic Attack +15% |

## Bard

- **Fencer** I acquired at level 75.
- Can access **Requiescat** (see CatsEyeXI Aeonic Weapon Skill).

## Ranger

### Abilities and Traits
- **Bounty Shot** acquired at level 55. [V6]

### Weaponskills
- **Flaming Arrow** and **Hot Shot** will apply **Burn** for a short duration.
- **Wasp Sting** and **Viper Bite** have increased damage.

### Ranged Distance Penalty
Ranger — as with **all jobs on CatsEyeXI** — does not use the ranged distance
system: ranged weapons work at point-blank range with no penalty. Attack
messages ("strikes true") may still display, but the penalty is not in effect.

## Samurai

### Abilities and Traits
- **Hasso** and **Seigan** are now considered "stances" and last 2 hours with a 1-minute recast.
- **Skillchain Bonus** trait at level 75.

## Ninja

- All ninjutsu cast on enemies gains **+15 magic accuracy**.

### Abilities & Traits
- **Futae** acquired at level 75.
- **Magic Burst Bonus** I acquired at level 75.
- **Tactical Parry** I acquired at level 75.
- **Mijin Gakure** has been modified to give 3 shadows, and reduces the character to 1 HP.
- Casting elemental ninjutsu grants TP similar to Occult Acumen: on dealing at least 1 damage, gain TP equal to your **Ninja Tool Expertise** (max 100); Store TP increases the gain.

## Dragoon

### Abilities and Traits
- **Fly High** acquired at level 75.
- **Dragon Breaker** and the ability to use **fjoturangons** acquired via a quest at Sigmund in Mhaura (after the Dragonslayer intro quest). Requirements: defeated at least 5 different "DKP" dragons; Level 75 Dragoon; 1,000 DKP; 200 Stored Merits (ACE) / 75 Stored Merits (CW/WEW); trade a dragon heart, dragon talon, wyrm scale, and wyrm tooth. A fjoturangon used with **Angon** forces a flying Wyrm to the ground (and procs a Dragonslaying foe); its defense-down lasts 15 seconds longer than a standard angon.

### Merits
- **Call Wyvern** recast is reduced by 3 minutes per tier of **Empathy** (10-10-2024 update).

## Summoner

- **Odin**, **Cait Sith**, **Siren**, and **Atomos** are not available at this time. (Wings-Era Warriors who merged from WingsXI can call Cait Sith.)

### Abilities and Traits
- **Mana Cede** acquired at level 75.
- **Fleet Wind** acquired at level 75.

### Adjustments
- Summoners may teleport to Cloisters after completing "Trial-Size" Mini-fork trials, without a Mini-fork (trade 100 gil to the respective NPC).
- **Light Spirit** adjusted to cast its protect and shell spells, enhanced similarly to how a scholar can make them AoE.
- All magical Blood Pacts gain **+15 magic accuracy**.
- Group 2 Merit Blood Pacts deal **+25% damage**.

### Magic — Summons

| Lvl | Summon |
|---|---|
| 1 | Light Spirit, Fire Spirit, Ice Spirit, Air Spirit, Earth Spirit, Thunder Spirit, Water Spirit, Dark Spirit |
| 1 | Carbuncle, Cait Sith, Ifrit, Shiva, Garuda, Titan, Ramuh, Leviathan, Fenrir, Diabolos |
| 75 | Alexander |

### Blood Pacts: Rage

| Lvl | Name | Avatar | Type | Properties |
|---|---|---|---|---|
| 1 | Inferno (2hr) | Ifrit | Magical | Fire |
| 1 | Earthen Fury (2hr) | Titan | Magical | Earth |
| 1 | Tidal Wave (2hr) | Leviathan | Magical | Water |
| 1 | Aerial Blast (2hr) | Garuda | Magical | Wind |
| 1 | Diamond Dust (2hr) | Shiva | Magical | Ice |
| 1 | Judgment Bolt (2hr) | Ramuh | Magical | Thunder |
| 1 | Searing Light (2hr) | Carbuncle | Magical | Light |
| 1 | Howling Moon (2hr) | Fenrir | Magical | Dark |
| 1 | Ruinous Omen (2hr) | Diabolos | Magical | Dark |
| 1 | Punch | Ifrit | Blunt | Liquefaction |
| 1 | Rock Throw | Titan | Blunt | Scission |
| 1 | Barracuda Dive | Leviathan | Slashing | Reverberation |
| 1 | Claw | Garuda | Piercing | Detonation |
| 1 | Axe Kick | Shiva | Blunt | Induration |
| 1 | Shock Strike | Ramuh | Blunt | Impaction |
| 1 | Camisado | Diabolos | Blunt | Compression |
| 1 | Regal Scratch | Cait Sith | Slashing | Scission |
| 5 | Poison Nails | Carbuncle | Piercing | Transfixion |
| 5 | Moonlit Charge | Fenrir | Blunt | Compression |
| 10 | Fire II | Ifrit | Magical | Fire |
| 10 | Stone II | Titan | Magical | Earth |
| 10 | Water II | Leviathan | Magical | Water |
| 10 | Aero II | Garuda | Magical | Wind |
| 10 | Blizzard II | Shiva | Magical | Ice |
| 10 | Thunder II | Ramuh | Magical | Thunder |
| 10 | Crescent Fang | Fenrir | Piercing | Transfixion |
| 19 | Thunderspark | Ramuh | Magical | Thunder |
| 21 | Rock Buster | Titan | Blunt | Reverberation |
| 23 | Burning Strike | Ifrit | Hybrid (Blunt) | Impaction (Fire) |
| 26 | Tail Whip | Leviathan | Blunt | Detonation |
| 30 | Double Punch | Ifrit | Blunt | Compression |
| 35 | Megalith Throw | Titan | Blunt | Induration |
| 50 | Double Slap | Shiva | Blunt | Scission |
| 55 | Meteorite | Carbuncle | Magical | Light |
| 60 | Fire IV | Ifrit | Magical | Fire |
| 60 | Stone IV | Titan | Magical | Earth |
| 60 | Water IV | Leviathan | Magical | Water |
| 60 | Aero IV | Garuda | Magical | Wind |
| 60 | Blizzard IV | Shiva | Magical | Ice |
| 60 | Thunder IV | Ramuh | Magical | Thunder |
| 65 | Eclipse Bite | Fenrir | Slashing | Gravitation / Scission |
| 65 | Nether Blast | Diabolos | Breath | Dark |
| 70 | Flaming Crush | Ifrit | Hybrid (Blunt) | Fusion / Reverberation (Fire) |
| 70 | Mountain Buster | Titan | Blunt | Gravitation / Induration |
| 70 | Spinning Dive | Leviathan | Slashing | Distortion / Detonation |
| 70 | Predator Claws | Garuda | Slashing | Fragmentation / Scission |
| 70 | Rush | Shiva | Blunt | Distortion / Scission |
| 70 | Chaotic Strike | Ramuh | Blunt | Fragmentation / Transfixion |
| 75 | Meteor Strike (merit) | Ifrit | Magical | Fire |
| 75 | Geocrush (merit) | Titan | Magical | Earth |
| 75 | Grand Fall (merit) | Leviathan | Magical | Water |
| 75 | Wind Blade (merit) | Garuda | Magical | Wind |
| 75 | Heavenly Strike (merit) | Shiva | Magical | Ice |
| 75 | Thunderstorm (merit) | Ramuh | Magical | Thunder |
| 75 | Level ? Holy | Cait Sith | Magical | Light |
| 76 | Holy Mist [a] | Carbuncle | Magical | Light |

### Blood Pacts: Ward

| Lvl | Name | Avatar |
|---|---|---|
| 1 | Altana's Favor (2hr) | Cait Sith |
| 1 | Healing Ruby | Carbuncle |
| 15 | Raise II | Cait Sith |
| 20 | Somnolence | Diabolos |
| 21 | Lunar Cry | Fenrir |
| 24 | Shining Ruby | Carbuncle |
| 25 | Mewing Lullaby | Cait Sith |
| 25 | Aerial Armor | Garuda |
| 28 | Frost Armor | Shiva |
| 29 | Nightmare | Diabolos |
| 30 | Reraise II | Cait Sith |
| 31 | Rolling Thunder | Ramuh |
| 32 | Lunar Roar | Fenrir |
| 33 | Slowga | Leviathan |
| 36 | Whispering Wind | Garuda |
| 37 | Ultimate Terror | Diabolos |
| 38 | Crimson Howl | Ifrit |
| 39 | Sleepga | Shiva |
| 42 | Lightning Armor | Ramuh |
| 43 | Ecliptic Growl | Fenrir |
| 44 | Glittering Ruby | Carbuncle |
| 46 | Earthen Ward | Titan |
| 47 | Spring Water | Leviathan |
| 48 | Hastega | Garuda |
| 49 | Noctoshield | Diabolos |
| 54 | Ecliptic Howl | Fenrir |
| 55 | Eerie Eye | Cait Sith |
| 56 | Dream Shroud | Diabolos |
| 65 | Healing Ruby II | Carbuncle |
| 75 | Fleet Wind | Garuda |
| 75 | Perfect Defense (2hr) [b] | Alexander |

Wiki footnotes: **[a]** Holy Mist requires augmented Apogee Sabots from the
Stronghold System to increase Carbuncle's level. **[b]** Perfect Defense
starts at 75% and begins to decay after 1/3 duration.

## Blue Mage

### Adjustments
- Blue Mage gets **Unbridled Learning** at 75 (9-12-2024 update). It must be active to use **Harden Shell**, **Pyric Bulwark**, and **Carcharian Verve** — no need to set these spells; they become available while the Unbridled Learning effect is active.
- Blue Magic affected by **Diffusion** gets the bonus from gear that increases Enhancing Magic Duration (8-22-2024 update).
- Blue Mage gets an **extra set point per tier of Assimilation**, for a total of +10 at rank 5 (8-8-2024 update).
- **Boruko** (J-10) in Aht Urghan Whitegate (near Waoud) provides additional Blue Magic Points (9-19-2024 update): points based on how many Blue Magic spells you have learned, up to a maximum of **25 points**. Requires Lv.75 Blue Mage with access to merits.
- *(Cross-check note [V2]: BLU also acquires Dual Wield through blue-magic trait sets — trait-set category grants DW I/II/III at 2/4/6 set points; verified in public `sql/blue_traits.sql`.)*

### Spells
Spells normally higher than Lv.75 added to Blue Mage at level 75. Found in the
same areas/mobs as retail unless noted (some source mobs were moved because
their retail areas do not exist on CatsEyeXI).

| Spell | Level | Notes |
|---|---|---|
| Acrid Stream | 75 | Clionid, Escha - Ru'Aun on Seiryu's island |
| Demoralizing Roar | 75 | Wivre |
| Empty Thrash | 75 | Craver |
| Heavy Strike | 75 | Golem |
| Blazing Bound | 75 | Limule, Escha - Ru'Aun on Suzaku's island |
| Quadratic Continuum | 75 | Gorger |
| Barbed Crescent | 75 | Fomor |
| Plenilune Embrace | 75 | Gnole |
| Osmosis | 75 | Amoeban, Escha - Ru'Aun on Genbu's Island |
| Occultation | 75 | Seether |
| Barrier Tusk | 75 | Marid |
| Magic Barrier | 75 | Ahriman |
| Orcish Counterstance | 75 | Any Orcs in the past [S] zones |
| Harden Shell | 75 | Pygmytoise in Gustav Tunnel lower level. Requires Unbridled Learning to use. |
| Pyric Bulwark | 75 | Tinnin hydra mobs. Requires Unbridled Learning to use. |
| Carcharian Verve | 75 | Tchakka in Domain Invasion. Requires Unbridled Learning to use. |
| Animating Wail | 75 | Qutrub |
| Battery Charge | 75 | Magic Pot |
| Anvil Lightning | 75 | Wild Ungeweder (Lesser Domain NM) |
| Blinding Fulgor | 75 | Wild Baelfyr (Lesser Domain NM) |
| Silent Storm | 75 | Wild Ungeweder (Lesser Domain NM) |
| Entomb | 75 | Wild Byrgen (Lesser Domain NM) |
| Glutinous Dart | 75 | Velkk Intruder (Lesser Domain NM) |
| Searing Tempest | 75 | Wild Baelfyr (Lesser Domain NM) |
| Scouring Spate | 75 | Wild Gefyrst (Lesser Domain NM) |
| Spectral Floe | 75 | Wild Gefyrst (Lesser Domain NM) |
| Tenebral Crush | 75 | Wild Byrgen (Lesser Domain NM) |

### Limit Break
Custom LB5 quest (see CatsEyeXI_Systems/Quests#Limit_Breaks).

## Corsair

- **Marksmanship** skill increased from B to A. [V7]
- **Club** skill added at E. [V7]

### Extra Rolls
Rolls beyond level 75 granted on the server:
- **Caster's Roll** (Fast Cast) — complete the custom quest "X Marks the Spot" (Aht Urghan).
- **Bolter's Roll** (Movement Speed) — complete the custom quest "X Marks the Spot".

### Artifact Armor
- The AF quest "Against All Odds" does not function correctly; work-around: start the quest, then speak to Mnejing in Aht Urhgan Whitegate (G-10) to receive the Corsair's Tricorne.
- The Hydrogauge for "Navigating the Unfriendly Seas": click the ??? on the Aht Urhgan Whitegate docks at I-11/12, or fish it up from Aht Urhgan Whitegate, Al Zahbi, Nashmau, or the Silver Sea route to Al Zahbi with any rod and any bait.

### Limit Break
Custom LB5 quest.

## Puppetmaster

### Adjustments
- The penalty to TP gained on hand-to-hand auto-attacks from Martial Arts delay reduction has been reduced by half.

### Important note
**Due to balancing and server stability /pup is not usable** — you can set PUP
as a subjob, but summoning the Automaton will not function.

### Frames
- Frames are obtained via Ghatsad, as per retail.
- Crystal Warriors can obtain the required materials via a custom quest ("The Purse Strings").

### Attachments
Most attachments work.
- See Mnejing's Puppetmaster Shop for attachments not otherwise sold by Yoyoroon in Nashmau (G-6). **Rararoon is disabled** on the server.
- Crystal Warriors **cannot** use Mnejing's shop; his attachments are obtained from Goblin's Gambit, Ob, Hilltroll Puppetmasters or Troll Machinists.
- Some previously obtained attachments were the wrong version and cannot be equipped; exchange permitted attachments free of charge at Geppetto (I-6) in Aht Urhgan Whitegate.
- To equip: while main job PUP, speak with Tateeya in the Automaton Workshop (I-7) Aht Urhgan Whitegate, then trade her the attachments (after the initial dialogue, tradeable on any job). Once traded they cannot be turned back into items.

Permitted attachments (wiki note: not all may function correctly, e.g. Barrage
Turbine). Capacity is in maneuver-element units:

**Fire:** Attuner (2), Flame Holder (1), Heat Capacitor (1), Heat Capacitor II (2), Inhibitor (1), Inhibitor II (2), Reactive Shield (1), Speedloader (1), Speedloader II (2), Strobe (1), Strobe II (2), Tension Spring (1), Tension Spring II (2), Tension Spring III (3), Magniplug (1), Magniplug II (2)

**Ice:** Amplifier (2), Ice Maker (1), Loudspeaker (1), Loudspeaker II (2), Loudspeaker III (3), Mana Booster (2), Power Cooler (2), Scanner (1), Tactical Processor (1), Tranquilizer (1), Tranquilizer II (2), Arcanoclutch (1)

**Wind:** Accelerator (2), Accelerator II (3), Accelerator III (4), Barrage Turbine (2), Drum Magazine (2), Pattern Reader (1), Repeater (2), Replicator (1), Scope (1), Scope II (2), Turbo Charger (2)

**Earth:** Analyzer (1), Armor Plate (2), Armor Plate II (3), Armor Plate III (4), Barrier Module (1), Barrier Module II (2), Equalizer (2), Hammermill (1), Schurzen (1), Shock Absorber (1)

**Thunder:** Coiler (2), Dynamo (2), Galvanizer (2), Heat Seeker (1), Stabilizer (1), Stabilizer II (2), Stabilizer III (3), Target Marker (2), Volt Gun (1)

**Water:** Condenser (1), Heatsink (1), Mana Channeler (2), Mana Jammer (2), Mana Jammer II (3), Mana Jammer III (4), Percolator (2), Resister (1), Stealth Screen (1), Stealth Screen II (2), Steam Jacket (1)

**Light:** Arcanic Cell (1), Auto-Repair Kit (2), Auto-Repair Kit II (3), Auto-Repair Kit III (4), Damage Gauge (1), Eraser (2), Flashbulb (2), Optic Fiber (1), Vivi-Valve (2)

**Dark:** Disruptor (2), Economizer (1), Mana Conserver (1), Mana Converter (2), Mana Tank (2), Mana Tank II (3), Mana Tank III (4), Smoke Screen (2)

### Artifact Armor
The quest "Puppetmaster Blues" **is not functional**.
- Puppetry Taj: complete "Operation Teatime", then speak to Mnejing in Aht Urhgan Whitegate (G-10).
- Other AF pieces are commissioned by **Mnejing** instead of Dhima Polevhia — trade materials and currency at the same time; no game-day wait or zoning between commissions.

| Armor | Ingredients | Coin cost |
|---|---|---|
| Puppetry Babouches | Ruby, Wamoura Cloth, Marid Leather, Platinum Sheet | Imperial Mythril Piece x2 |
| Puppetry Dastanas | Rainbow Thread, Wamoura Cloth, Marid Leather, Platinum Sheet | Imperial Mythril Piece |
| Puppetry Tobe | Ruby, Wamoura Cloth, Moblinweave, Scarlet Linen | Imperial Gold Piece |

### Limit Break
Custom LB5 quest.

### Specific Changes
- As of the 1/2/2026 update, Automatons have a **95% resistance to instant-death** spells and mob abilities (Haruuc).

## Dancer

- **Club** skill added at E. [V7]

### Abilities and Traits
- **Divine Waltz II** acquired at level 60.
- **Feather Step** acquired at level 65.
- **Presto** acquired at level 75.
- **Tactical Parry** I acquired at level 75.
- **Critical Attack Bonus** I acquired at level 75.

### Limit Break
Custom LB5 quest.

## Scholar

### Abilities and Traits
- Gains **Immanence** at 75.
- Gains **Perpetuance** at 75.
- Gains **Occult Acumen** I at level 60, II at level 75.

Max stratagem amount & recharge rate:

| Level | # of charges | Time to regain one charge |
|---|---|---|
| 10 | 1 | 4 min. |
| 30 | 2 | 2 min. |
| 50 | 3 | 1 min. 20 sec. |
| 65 | 4 | 1 min. |
| 75 | 5* | 48 sec. |

\* The FFXI client will only show 4 charges but you have 5 available when maxed.

### Limit Break
Custom LB5 quest.

### Artifact Armor
- SCH AF3 workaround: next to Erlene is a box labeled "SCH AF3"; click it to start "Seeing Blood-red". Travel to Pashhow Marshlands (S) (E-11) and click the box labeled "SCH AF Hat" (instead of Indescript Markings) for the Unaddressed sealed letter; return to The Eldieme Necropolis (S) and click the SCH AF3 box to obtain the Scholar's M.board.
- Remaining pieces from Loussaire work as intended. (Wiki anecdote: the Indescript Markings for Scholar's Pants appeared around 10:00 game time, outside the suggested 16:00-6:00 window.)

## Geomancer

### Unlock
Complete one job to level 75, then the quest **"The Unnamed Way"** from Master
Lao in Windurst Waters (South) (K-8).

### Job Traits

| Lvl | Trait |
|---|---|
| 10 | Conserve MP |
| 20 | Clear Mind |
| 25 | Cardinal Chant (custom, see Adjustments) |
| 25 | Conserve MP II |
| 30 | Max MP Boost I |
| 40 | Clear Mind II |
| 40 | Conserve MP III |
| 45 | Cardinal Chant II (custom) |
| 55 | Elemental Celerity |
| 55 | Conserve MP IV |
| 60 | Clear Mind III |
| 60 | Max MP Boost II |
| 25 | Cardinal Chant III (custom) — *sic; the wiki trait table prints level 25, but its own Cardinal Chant tier table (below) says Tier III is level 65. Likely a wiki typo for 65.* |
| 70 | Conserve MP V |
| 75 (merit) | Curative Recantation |
| 75 (merit) | Primordial Zeal |

### Job Abilities

| Lvl | Ability |
|---|---|
| 1 | Bolster |
| 5 | Full Circle |
| 25 | Lasting Emanation |
| 25 | Ecliptic Attrition |
| 40 | Collimated Fervor |
| 50 | Life Cycle |
| 60 | Blaze of Glory |
| 70 | Dematerialize |
| 75 | Entrust |
| 75 (merit) | Mending Halation |
| 75 (merit) | Radial Arcana |

### Adjustments — Cardinal Chant (custom mechanic)
**Cardinal Chant** was altered to provide an **affinity boost to magic**,
determined by where the target is located relative to the caster when the
elemental magic spell actually lands, instead of the retail bonuses.

Affinity is a separate Magic Damage multiplier per element (base 1.0). For
reference, an NQ elemental staff adds 0.05 to the multiplier and +10 magic
accuracy; an HQ adds 0.1 and +20.

**Collimated Fervor** enhances the bonuses of Cardinal Chant by 50%.

Directions (target's bearing from the caster):

| Direction | Element |
|---|---|
| N | Dark |
| NE | Light |
| E | Ice |
| SE | Wind |
| S | Earth |
| SW | Thunder |
| W | Water |
| NW | Fire |

| Tier | Level | Affinity | Magic Accuracy |
|---|---|---|---|
| I | 25 | +0.05 | +5 |
| II | 45 | +0.1 | +10 |
| III | 65 | +0.15 | +15 |

### Geomancy spells
Geocolure spells are learned through **Geomantic Reservoirs** after learning
the corresponding Indicolure spell. While available at the appropriate level
of GEO as a sub-job, **only main job Geomancers may cast Geocolure spells**.
Element column derived from the wiki's icon markup.

| Lvl | Spell | Element (icon) | Acquisition |
|---|---|---|---|
| 1 | Indi-Poison | Water | Sylvie |
| 4 | Indi-Voidance | Wind | Sylvie |
| 4 | Stone | Earth | Various |
| 5 | Geo-Poison | Water | Reservoir |
| 8 | Geo-Voidance | Wind | Reservoir |
| 9 | Water | Water | Various |
| 10 | Indi-Precision | Thunder | Sylvie |
| 14 | Aero | Wind | Various |
| 14 | Geo-Precision | Thunder | Reservoir |
| 15 | Drain | Dark | Quest (The Rumor) |
| 15 | Indi-Regen | Light | Sylvie |
| 16 | Indi-Attunement | Light | Sylvie |
| 19 | Fire | Fire | Various |
| 19 | Geo-Regen | Light | Reservoir |
| 20 | Geo-Attunement | Light | Reservoir |
| 22 | Indi-Focus | Dark | Sylvie |
| 24 | Blizzard | Ice | Various |
| 25 | Stonera | Earth | Sylvie |
| 26 | Geo-Focus | Dark | Reservoir |
| 28 | Indi-Barrier | Earth | Sylvie |
| 29 | Thunder | Thunder | Various |
| 30 | Indi-Refresh | Light | Sylvie |
| 30 | Aspir | Dark | Quest (Making the Grade) |
| 30 | Indi-CHR | Light | Sylvie |
| 30 | Watera | Water | Sylvie |
| 32 | Geo-Barrier | Earth | Reservoir |
| 33 | Indi-MND | Water | Sylvie |
| 34 | Indi-Fury | Fire | Sylvie |
| 34 | Geo-Refresh | Light | Reservoir |
| 34 | Geo-CHR | Light | Reservoir |
| 34 | Stone II | Earth | Chutarmire |
| 35 | Aera | Wind | Sylvie |
| 35 | Sleep | Dark | Various |
| 36 | Indi-INT | Ice | Sylvie |
| 37 | Geo-MND | Water | Reservoir |
| 38 | Geo-Fury | Fire | Reservoir |
| 38 | Water II | Water | Chutarmire |
| 39 | Indi-AGI | Wind | Sylvie |
| 40 | Indi-Fend | Water | Sylvie |
| 40 | Geo-INT | Ice | Reservoir |
| 40 | Fira | Fire | Sylvie |
| 42 | Aero II | Wind | Chutarmire |
| 42 | Indi-VIT | Earth | Sylvie |
| 43 | Geo-AGI | Wind | Reservoir |
| 44 | Geo-Fend | Water | Reservoir |
| 45 | Indi-DEX | Thunder | Sylvie |
| 45 | Blizzara | Ice | Sylvie |
| 46 | Fire II | Fire | Chutarmire |
| 46 | Indi-Acumen | Ice | Sylvie |
| 46 | Geo-VIT | Earth | Reservoir |
| 48 | Indi-STR | Fire | Sylvie |
| 48 | Indi-Slow | Earth | Sylvie |
| 49 | Geo-DEX | Thunder | Reservoir |
| 50 | Blizzard II | Ice | Chutarmire |
| 50 | Geo-Acumen | Ice | Reservoir |
| 50 | Thundara | Thunder | Sylvie |
| 52 | Indi-Torpor | Ice | Sylvie |
| 52 | Geo-STR | Fire | Reservoir |
| 52 | Geo-Slow | Earth | Reservoir |
| 54 | Thunder II | Thunder | Chutarmire |
| 56 | Geo-Torpor | Ice | Reservoir |
| 58 | Indi-Slip | Earth | Sylvie |
| 58 | Stone III | Earth | Susu |
| 61 | Water III | Water | Susu |
| 62 | Geo-Slip | Earth | Reservoir |
| 64 | Aero III | Wind | Susu |
| 64 | Indi-Languor | Dark | Sylvie |
| 67 | Fire III | Fire | Susu |
| 68 | Indi-Paralysis | Ice | Sylvie |
| 68 | Geo-Languor | Dark | Reservoir |
| 70 | Blizzard III | Ice | Susu |
| 70 | Indi-Vex | Light | Sylvie |
| 70 | Sleep II | Dark | Susu |
| 70 | Stonera II | Earth | Sylvie |
| 72 | Geo-Paralysis | Ice | Reservoir |
| 73 | Thunder III | Thunder | Susu |
| 74 | Geo-Vex | Light | Reservoir |
| 74 | Indi-Haste | Wind | AF Quest |
| 74 | Geo-Haste | Wind | AF Quest |
| 74 | Indi-Frailty | Wind | AF Quest |
| 74 | Geo-Frailty | Wind | AF Quest |
| 75 | Watera II | Water | Sylvie |

### Artifact Armor
- GEO artifact weapons via the custom quest "The Earth Holds Its Breath": **Dowser's Wand** (Club, Lv40 GEO, DMG 15 Delay 216, INT+2 Magic Accuracy+2) and **Filiae Bell** (Handbell, Lv40 GEO, MP+15 MND+1).
- GEO artifact armor via a custom process at Drunk Taru in Bibiki Bay (G-10) once at level 75: #1 trade a Pearlscale (Domain Invasion points) → Geomancy Sandals; #2 trade a Seal of Byakko → Geomancy Mitaines; #3 obtain a Siren's Tear (??? by the river at J-8/9 North Gustaberg with no main or sub weapon equipped) → Geomancy Galero; #4 trade an Oil-Soaked Cloth → Geomancy Pants; #5 earn the title "Sandworm Wrangler" → Geomancy Tunic.
- After AF #5, speak to Drunk Taru once more to have **Geo-Frailty / Indi-Frailty** and **Geo-Haste / Indi-Haste** added directly to your spell list.

Custom Level 75 Geomancy armor set stats:

| Item | Stats |
|---|---|
| Geomancy Galero | DEF: 25 MP +25 INT +5 Elemental Skill +15 Enhances Cardinal Chant |
| Geomancy Tunic | DEF: 40 MP +35 Dark Skill +12 Enhances Life Cycle |
| Geomancy Mitaines | DEF: 15 MP +16 INT +3 MND +4 Geomancy Skill +15 Luopan: Damage Taken -6% |
| Geomancy Pants | DEF: 30 MP +20 Fast Cast +10% Spell Interruption Rate -15% |
| Geomancy Sandals | DEF: 12 MP +15 AGI +5 CHR +5 Movement Speed +12% |

### Relic Armor / Relic Weapon / Ergon Weapon
- Relic Armor: obtained in Dynamis (see CatsEyeXI Dynamis, RUN and GEO Relic Armor).
- Relic Weapon: Geomancer has access to **Mjollnir (Level 75)**.
- Ergon Weapon: **Idris** added as of the 9-12-2024 update.

## Rune Fencer

### Unlock
Complete one job to level 75, then the quest **"Runic Insurrection"** from
Octavien in Bastok Markets (F-10).

### Job Traits

| Lvl | Trait |
|---|---|
| 5 | Tenacity |
| 10 | Magic Defense Bonus |
| 15 | Inquartata |
| 20 | Max HP Boost I |
| 30 | Magic Defense Bonus II |
| 35 | Auto Regen |
| 40 | Tactical Parry |
| 40 | Max HP Boost II |
| 45 | Inquartata II |
| 50 | Magic Defense Bonus III |
| 50 | Accuracy Bonus I |
| 60 | Max HP Boost III |
| 65 | Auto Regen II |
| 70 | Magic Defense Bonus IV |
| 70 | Accuracy Bonus II |
| 75 | Magic Defense Bonus V |
| 75 | Inquartata III |
| 75 (merit) | Inspiration |
| 75 (merit) | Sleight of Sword |

### Job Abilities

| Lvl | Ability |
|---|---|
| 1 | Elemental Sforzo |
| 5 | Ignis |
| 5 | Gelus |
| 5 | Flabra |
| 5 | Tellus |
| 5 | Sulpor |
| 5 | Unda |
| 5 | Lux |
| 5 | Tenebrae |
| 10 | Vallation |
| 20 | Swordplay |
| 25 | Swipe |
| 25 | Lunge |
| 40 | Pflug |
| 50 | Valiance |
| 60 | Embolden |
| 65 | Vivacious Pulse |
| 70 | Gambit |
| 75 | One for All |
| 75 (merit) | Battuta |
| 75 (merit) | Rayke |

Maximum rune amount:

| Level | # of runes |
|---|---|
| 1 | 1 |
| 35 | 2 |
| 65 | 3 |

### Magic
- Gains access to **Flash** at level 38. [V8]
- Gains access to **Crusade** at level 56. [V8]
- Gains access to **Baramnesia** at level 63. [V8]
- Bar-status spells scale with enhancing magic skill.

### Artifact Armor
- RUN artifact weapon via the custom quest "Forged in Frost and Flame": **Beorc Sword** (Great Sword, Lv40 RUN, DMG 56 Delay 480, Magic Attack Bonus +2, Parrying Skill +3).
- RUN artifact armor via a custom process once at level 75: #1 West Minstrel (Ru'Lude Gardens H-9) → Varado (South Gustaberg J-8) → Stranger Flower at Blueblade Fell (Lufaise Meadows J-6, key item Yahse wildflower petal) → Varado again → zone → Varado once more → **Runeist Mitons**. #2/3/4 Caida (East Ronfaure H-10): Rune of Power (Rolanberry Fields K-10 ??? NM battle → Vivid Rainbow Extract), Rune of Wisdom (solve the cipher at the Aged Arbor, E-5 Batallia Downs from the Beaucedine Glacier entrance), Rune of Courage (Monastic Cavern J-7 ??? → Runic Kinegraver) → **Runeist Bottes, Runeist Trousers, Runeist Coat**. #5 Babus (Eastern Altepa Desert F-10): trade Seals of Byakko, Genbu, Seiryu, Suzaku (returned) → **Runeist Bandeau**.

Custom Level 75 Runeist armor set stats:

| Item | Stats |
|---|---|
| Runeist Bandeau | DEF: 27 HP +27 DEX +5 Physical Damage Taken -3% Increases Regen Duration +3 |
| Runeist Coat | DEF: 50 HP +20 MP +20 STR +5 VIT +5 Resist All Elements +10 Enhances Valiance and Vallation |
| Runeist Mitons | DEF: 21 MP +22 DEX +3 VIT +3 Refresh +1 Enhances Gambit |
| Runeist Trousers | DEF: 40 HP +15 MP +15 STR +7 Enmity +5 Damage Taken -3% |
| Runeist Bottes | DEF: 18 MP +18 VIT +6 Magic Defense Bonus +2 "Pflug" +10 |

### Relic Armor / Ergon Weapon
- Relic Armor: obtained in Dynamis (see CatsEyeXI Dynamis, RUN and GEO Relic Armor).
- Ergon Weapon: **Epeolatry** added as of the 9-12-2024 update.

---

# dlac impact

How the documented changes touch existing and planned dlac features. File
references are to this repo.

## Dual Wield detection (`utils.lua` — shipped, memory-based)
- `utils.isDualWieldAvailable` reads the live trait bit (`Player:HasAbility(1554)`,
  trait id 18 + 0x600 offset) — **keep it that way**. This is the one job
  mechanic where all three sources disagree:
  - Wiki: THF DW I@20 / II@40 (10-10-2024 update).
  - Public server SQL (base/stable/staging, = stock LSB): THF DW 83/90/98
    `ABYSSEA`-tagged — unreachable at the 75 cap.
  - Live observation (the original dlac discovery): THF at ≤75 without DW.
- **BLU Dual Wield comes from blue-magic trait sets** (`blue_traits` category 25:
  DW I/II/III at 2/4/6 set points — verified in public SQL). No level gate can
  ever model this; only the memory bit is correct.
- The legacy fallback table in `utils.lua` (THF 20 / NIN 10 / DNC 20) happens to
  match the wiki for THF and the (Abyssea-tagged but active) DNC rows; it is
  acceptable only as a fallback when the player block isn't populated.

## Picker DB "usable at level" filter (`spells.lua` / `abilities.lua` — planned filter)
Both files are **generated from the public server SQL** (`tools/gen_pickerdb.py`),
which this investigation showed is stock LSB — it does not contain the live
customizations. Known divergences the picker filter will get wrong until the
generator gains a wiki-override layer:

- `abilities.lua` wrong levels: **Accomplice THF 65** and **Collaborator THF 65**
  (wiki: 40 for both).
- `abilities.lua` missing entirely (stock level >75 was filtered out by the
  75-era generator, but the wiki grants them at ≤75):
  Blood Rage (WAR 75), Perfect Counter (MNK 75), Impetus (MNK 75),
  Enmity Douse (BLM 75), Bully (THF 60),
  Conspirator (THF 75), Despoil (THF 75), Nether Void (DRK 75),
  Scarlet Delirium (DRK 75), Bounty Shot (RNG 55), Futae (NIN 75),
  Fly High (DRG 75), Mana Cede (SMN 75), Unbridled Learning (BLU 75),
  Divine Waltz II (DNC 60), Feather Step (DNC 65), Presto (DNC 75),
  Immanence (SCH 75), Perpetuance (SCH 75), One for All (RUN 75).
- ~~Generator bug~~ (fixed, commit `bc91206`): rows with a trailing SQL
  comment were silently dropped. Recovered: Bolster (GEO 1), Blood Pact
  Ward (SMN 1), Maintenance (PUP 30), Naturalist's Roll (COR 67),
  Random Needles (BST 25).
- `spells.lua` wrong level: **Flash RUN 45** (wiki: 38).
- `spells.lua` missing entirely: Enlight (WHM 75, now WHM-only),
  Arise (WHM 75, 150 MP / 10 s cast), Baramnesra (WHM 65),
  Baramnesia (RDM 65, RUN 63), Crusade (RUN 56), Absorb-Attri (DRK 75),
  BLM Tier V elemental spells (75, from Higher VNMs), and the 27+ BLU spells
  added at 75 (table above; three require Unbridled Learning active and are
  usable without being set).
- Trait-level features (if dlac ever gates on traits): MNK Attack Bonus
  I/II/III at 30/55/70; BLM & SCH Occult Acumen I/II at 60/75; DRK Occult
  Acumen I at 37; RDM Magic Burst Bonus I at 70 and MAB III at 75; BST Fencer
  I/II at 60/75; BRD Fencer I at 75; SAM Skillchain Bonus at 75; NIN Magic
  Burst Bonus I / Tactical Parry I at 75; DNC Tactical Parry I / Critical
  Attack Bonus I at 75; THF Assassin at 50; WAR Shield Mastery at 40; BST
  Stout Servant at 75; full custom GEO/RUN trait tables above.

## Trigger rules matching by ability name (`dispatch.lua`)
Rules match `ctx.action.Name` case-insensitively. Users on CatsEyeXI can
legitimately fire abilities that a retail-75 mindset says don't exist at 75 —
rule authoring and any future name validation/autocomplete must accept them:
"Presto", "Blood Rage", "Impetus", "Perfect Counter", "Futae", "Fly High",
"Mana Cede", "Fleet Wind", "Unbridled Learning", "Despoil", "Bully",
"Conspirator", "Bounty Shot", "Divine Waltz II", "Feather Step", "Immanence",
"Perpetuance", "Nether Void", "Scarlet Delirium", "Enmity Douse",
"One for All", plus the whole GEO/RUN kits (Bolster, Entrust, Full Circle,
Elemental Sforzo, rune enchantments Ignis/Gelus/Flabra/Tellus/Sulpor/Unda/
Lux/Tenebrae, Vallation, Valiance, Swordplay, Swipe, Lunge, Pflug, Embolden,
Vivacious Pulse, Gambit, Battuta, Rayke, Mending Halation, Radial Arcana).

## Stance mechanics (duration/recast assumptions)
Retaliation (WAR), Counterstance (MNK), Hasso and Seigan (SAM) are "stances":
**2-hour duration, 1-minute recast**. Any future buff-uptime logic, recast
display, or trigger heuristics must not assume retail durations/recasts for
these. Same for MNK Focus/Dodge (75 s) and Footwork (120 s).

## Subjob-sensitive behavior
- **/pup is non-functional** — automaton cannot be summoned with PUP subjob.
  Any pet-aware feature should not expect an automaton from a PUP sub.
- **Geocolure (Geo-) spells are main-job GEO only**, even though sub-GEO gets
  the levels; Indicolure spells follow normal subjob rules. A picker
  "usable now" filter needs a main-job-only flag for Geo- spells.
- SMN: Odin, Cait Sith, Siren, Atomos unavailable (except legacy WEW Cait
  Sith); Alexander at 75. Spirit/avatar summons all level 1.
- TH from /THF: native TH trait at 15 contributes +1 within the non-THF cap
  of 4 (ACE/CW/WEW).

## Stat math notes (gear scoring / `gearweights.lua`, `gearoptim.lua`)
- **Job Ability Haste caps at 30%** on CatsEyeXI (not 25%); equipment haste
  still caps at 25%. Relevant if haste capping is ever modeled.
- Ranged distance penalty is disabled server-wide (no point-blank penalty) —
  do not down-weight ranged setups for melee-range play.
- Ninjutsu +15 magic accuracy (NIN), magical blood pacts +15 magic accuracy
  and Group 2 merit pacts +25% damage (SMN) are server-side bonuses invisible
  to gear math but relevant to any future "effective macc" displays.

## Regenerating the picker DB
`tools/gen_pickerdb.py` reads github.com/CatsAndBoats/catseyexi SQL. Since the
live customizations are in **private submodules**, regeneration alone can
never produce correct CatsEyeXI data — it needs an overlay file sourced from
this document (or better, in-game observation) applied after generation.
