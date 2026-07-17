# Fishing Gear System — design

Status: **DESIGNED 2026-07-18** — implementation in progress. The third sibling of the
craft-gear (docs/design/craft-automation.md) and HELM (docs/design/helm-gear.md) systems.
Same philosophy: **don't fight the engine, BE the engine** — a per-char state file read by
dispatch every tick, engine wears the result as the last writer, idle-only.

**Scope guard (Henrik, verbatim intent):** *"I am NOT out to automate fishing, I just want
to streamline the experience."* This system equips gear and informs. It never casts, never
reacts to bites, never touches the mini-game. The server carries an explicit anti-bot
surface (`[Fish]LastCastTime` char var written per cast, core `GetRecentFishers()`, GM
`!getfishers` — fishingutils.cpp:1957-1968) — one more reason the line stays bright.

Heritage: Henrik's pre-dlac hand-written profile had exactly this feature in miniature —
`/fishset` toggling `{ Range = 'Halcyon Rod', Ring2 = 'Pelican Ring' }` in the idle pass
(ffxi-lac/gcinclude.lua:60-63, 255-258). The fish pill is its descendant.

---

## 0. Server research summary (2026-07-18, CatsAndBoats/catseyexi branch `base`)

Fishing is **stock-LSB C++** (an older snapshot: chart quests stripped, chest catching
commented out): `src/map/utils/fishingutils.cpp` (3,242 lines) + `.h` (all enums), driven
by public SQL: `fishing_fish` (138), `fishing_bait` (39), `fishing_bait_affinity` (617),
`fishing_rod` (20), `fishing_zone` (294), `fishing_area` (169), `fishing_catch` (165),
`fishing_group` (1,068), `fishing_mob` (286). There is NO scripts/globals/fishing.lua and
NO hobbies/fishing dir. Trust ladder (per-table assessment in the research): public code +
SQL are the baseline the server builds; the **private overlay provably adds content on
top** — custom mods 2004/2005 (semantics NOT public; carriers: Ebisu =10, Ebisu +1 =15,
Halieutica =50/=5, Mariners Tunica/Boots, Brigands Eyepatch) and those custom items have
no public rows at all. We ship the public baseline, mark the customs "stats unverified",
and let live captures correct us — never guess private semantics (server-questions.md §4).

**Round-2 update (2026-07-18, Henrik's field pass):** mods **2004/2005 are
IDENTIFIED** — the bg-wiki page https://www.bg-wiki.com/ffxi/CatsEyeXI_Content/Ventures
lists "Expert Angler: Fatigue Limit +10%, Golden Arrow Rate +1%" on Mariners
Tunica/Boots, matching the live DB values exactly (2004 = 10/20 base/+1, 2005 = 1/2).
So **2004 = Fatigue Limit +%, 2005 = Golden Arrow Rate +%** (server-questions.md §4
updated). Display policy from the same pass: only Mariners glows (the real fishing
end-game); Halieutica, Brigands Eyepatch and the legendary-rod +1s are NOT displayed
(unmentioned in-game / look unobtainable — data stays shipped, autoPick still honours
an owned one); owning Lu Shang's or Ebisu greens the whole standard rod ladder.

Mechanics the addon USES (file:line = fishingutils.cpp unless noted):

- **What bites**: position → fishing area (point-in-poly/cylinder, :1287) → catch groups
  (`fishing_catch` zone+area → `fishing_group`) → fish list. A fish is in YOUR pool only
  if `fishing_bait_affinity[bait][fish]` exists — **no affinity row = that fish can never
  bite that bait**. That's what makes bait isolation computable offline.
- **Pool weights** (:2140-2154): four buckets rolled once per cast — Fish / Item / Mob /
  NoCatch, all moon-modulated; mobs only outside cities; item share +boost with
  Robber/Rogue Rig (POOR_FISH flag), −25% into NoCatch with Fisherman's Apron/Smock.
  Items and monsters ride SEPARATE buckets: perfect fish-isolation still leaves item and
  (outside cities) mob bites possible — the UI must say so, not imply exclusivity.
- **Hook chance per fish** (:610-673): bait affinity power 1/2/3 → +35/+65/+80 (lures −5),
  moon×3+hour×2+month cosine patterns, skill deficit −0.25/level, over-skill −0.15/level
  past +10, small/large rod mismatch −3/−5 (non-legendary), shellfish+SHELLFISH_AFFINITY
  bait +50, ×rarity/1000, clamp 20..120.
- **The three fail rolls** — this is the "which rod won't break" math, rolled at reel-in
  (`ReelCheck` :2626, order lose → linesnap → rodbreak):
  - *Lose* (:719-782): non-legendary rod + fish.size&gt;rod.size + fish.ranking&gt;rod.max_rank
    → "too large" 50+(fishSkill−skill), cap 50; small-fish-on-large-rod analog cap 50;
    skill+7 &lt; fishSkill → 0.8/level, cap 55.
  - *Line snap* (:784-826): `durability = rod.max_rank + (skill+10&gt;fishSkill ? 2 : 0) +
    (legendary rod on legendary fish ? 1 : 0) − (fish.size&gt;rod.size on non-leg ? 2 : 0) −
    (legendary fish on non-leg rod ? 3 more : 0)`; snap when `fish.ranking &gt; durability`,
    chance `floor((ranking−durability)*8.5)` cap 55.
  - *Rod break* (:828-869): breakable rods only (`fishing_rod.breakable`; **Ebisu, Judge's,
    Goldfish Basket never break; Lu Shang's DOES** → broken id 489, restorable via
    quests/otherAreas/Recycling_Rods.lua); same durability idea, penalty +2 wrong-size,
    +5 legendary fish on non-legendary rod, ×1.3 cap 55.
- **Skill** (:1062): effective = floor(raw/10) + `Mod::FISH` (127) from gear. Hook gate
  :2208: fish enters pool while `fish.skill_level − skill ≤ 100` (you can always TRY far
  up; the fail math is the wall). Skill-ups peak ~11 levels above current (:1756-1904);
  cap = (guild rank + 1) × 10, Expert = 110; rank-up = trade test fish to **Thubu
  Parohren, Port Windurst** (rank→fish table shipped in fishdb).
- **Bite-time patterns** per fish: `hour_pattern` 0-7 / `moon_pattern` 0-5 /
  `month_pattern` 0-10 → cosine curves (fishingutils.h:773-809). Displayable hints
  (hour 3 = ONLY 5:00/17:00, 4 = night 20:00-3:00, 2 = anything except dawn/dusk).
  New/Full moon −4 s bite wait; rain ×1.1 / squall ×1.2 fish pool.
- **Bait vs lure**: `fishing_bait.type` 0 = consumed bait (stack 99), 1 = lure (persists;
  lost only on line break), 2 = one-use special. Sabiki Rig 17399 / Super Scoop 17003
  `maxhook=3` multi-catch on 9 specific fish. Bait NOT consumed when an item bites.
- **Guild points**: fishing guild = **guild id 0** (sql/guilds.sql). Balance arrives in
  s2c 0x113 at **offset 0x20** — the exact packet craftwatch already parses (its
  GP_OFFSET starts at 0x24 and a run_tests fixture proves 0x20 is currently skipped).
  Today's turn-in item = server-random `rand(8)` daily pattern (guildutils.cpp:150-176)
  — NOT predictable offline; the panel shows balance + the static GP shop, not the item.
  GP shop (hobbies/crafting/guild_points.lua): Fisherman's Belt 10k, Waders 70k,
  Fisherman's Apron 100k, Net &amp; Lure 50k, Fishermen's Emblem 15k, Fishing Hole Map 150k,
  Signboard 200k; KIs: Frog Fishing 30k, Serpent Rumors 95k, **Mooching 115k** (+30 s
  hook time on live bait), Angler's Almanac 20k (Expert prerequisite).
- **Lu Shang's**: the retail 10,000-carp pair IS active (quests/sandoria/The_Rivalry.lua
  + The_Competition.lua; Moat Carp 4401 / Forest Carp 4289). Ebisu acquisition is not in
  public source (private overlay).
- **Player status while fishing**: the entity animation byte — new-client values
  **56 FISHING_START … 62 FISHING_STOP** (baseentity.h:60-93). LAC/gData knows nothing of
  these (no fishing event exists in LAC — verified), so the engine's Default-event gate
  keeps running while fishing; only Engaged/Dead stand the overlay down (helm precedent).

## 1. The progression this UI models

### Item matrix (ids catalog-verified; stats from server SQL + live API cache)

| Row | Base | Next tier | Source |
|---|---|---|---|
| Head | — | Tlahtlamah Glasses 25608 (Fish+1, custom shop?) | catalog custom block |
| Body | Fisherman's Tunica 13808 (+1) | Angler's Tunica 13809 (+1, Lv15) · Fisherman's Smock 11337 (+1, item-bite −25%) | retail/AH · GP tier |
| Hands | Fisherman's Gloves 14070 (+1) | Angler's Gloves 14071 (+1) | |
| Legs | Fisherman's Hose 14292 (+1) | Angler's Hose 14293 (+1) | |
| Feet | Fisherman's Boots 14171 (+1) | Angler's Boots 14172 (+1) · Waders 14195 (+2, GP 70k) | |
| Neck | Fisher's Torque 10925 (+2) | — | |
| Waist | Fisherman's Belt 15452 (+2 via 2 h enchantment) | Fisherman's Apron 14400 (GP 100k, item-bite −25%) | |
| Ring | Pelican Ring 15554 (skill-up rolls, 20 min ench.) | Angler's Ring 39051 (Fish+2, Lv75, custom) | |
| CUSTOM | — | see below | live DB only |

**The Mariners set is fishing's VP tier** (generator discovery 2026-07-18): its ids
interleave HELM's Plain block — Plain Hose 25897/98 then **Mariners Hose 25899/25900
(+1)**, Plain Boots 25964/65 then **Mariners Boots 25966/67**, Plain Gloves 25984/85 then
**Mariners Gloves 25986/87**, Plain Tunica 26533/34 then **Mariners Tunica 26535/36** —
and **Brigands Eyepatch 28443** is the hat analog. All carry Fish+1 (+2 on +1 pieces);
Tunica/Boots (+1s) add cx-mods 2004/2005 (10/1 base, 20/2 on +1). The panel's Mariners
column is the Plain column's sibling; VP prices field-verifiable (likely 3000/hat 5000).
**Halieutica 20945 is NOT a rod** — a Main-slot weapon (polearm-skill fishing spear):
DEX/ATT + Fish+2 + cx4=50/cx5=5. **Ebisu carries cx4 only (10; +1 = 15)** and Brigands
Eyepatch cx4=20/cx5=2 with NO Fish mod — those two are the only pieces invisible to the
catalog's FishingSkill stat, which is exactly what the fishdb `gearBonus` supplement is
for. cx = **Expert Angler** (2004 Fatigue Limit +%, 2005 Golden Arrow Rate +% — round-2
identification above); ladder tiebreakers below real skill. Halieutica/Eyepatch/the +1
rods ship in fishdb but are NOT displayed (round-2 ruling).

Armor ladders are **stat-driven from the catalog** (`Stats.FishingSkill`, statdefs mod
127) exactly like craft/HELM ladders — future gear lands automatically. The custom
2004/2005 carriers are invisible to the catalog (apicrawl drops unmapped mods), so the
generator also scans `tools/api_cache/*.json` for mods 127/2004/2005 and ships a
`gearBonus` supplement in fishdb — **ordering-only** (the Surveyor-2/4 precedent:
monotone, so sort-safe even though the custom mods' semantics are unverified).

### Rod ladder (all 20 public rods shipped with full stats; the four that matter)

| Rod | id | size | max_rank | breakable | notes |
|---|---|---|---|---|---|
| Willow → Yew → Bamboo → Fastwater → Tarutaru | 17391/90/89/88/87 | S | 5-9 | yes | starter wood |
| Glass Fiber / Carbon / Hume / Halcyon | 17385/84/14/15 | S | 12/13/10/18 | yes | mid synthetics |
| Mithran / Clothespole / Composite / Single Hook | 17380/83/81/82 | **L** | 18/16/24/22 | yes | large-fish rods |
| **Lu Shang's** | 17386 | S | 28 | **yes** → 489 | legendary; 10k carp |
| **Ebisu** | 17011 | S | 30 | **no** | legendary; best everything |
| Ebisu +1 / Lu Shang's +1 | 19321/19320 | S | 30/28 | no/yes | custom upgrades |
| Judge's Rod / Goldfish Basket / MMM | 17012/13/19319 | S | 40/5/25 | no/no/yes | special |
| Halieutica | (live id TBD) | ? | ? | ? | **custom, stats private — verdict shows "?"** |

## 2. UI — the fishing panel (Automations → "Auto Fish Set")

New Automations row (triggersui rows table): `key='fish'`, name **Auto Fish Set**, kind
`fishing-gear helper (idle only)`, status from `fishui.status(deps)` (level 0-4: 1 = any
fishing gear owned, 2 = base body/hands/legs/feet complete, 3 = a next-tier/GP piece,
4 = legendary rod owned; glow language identical to HELM). Detail delegates to
`ui/fishui.lua` (own module — triggersui rides the 200-local cap; helmui precedent).

Panel layout, top to bottom:

1. **Status line**: `Fishing skill 54 (+4 gear) / cap 58 · rank Apprentice` (skill =
   `GetCraftSkill(0)` memory read — craftwatch's map deliberately omitted index 0; gear
   bonus = worn Mod::FISH sum; cap/rank if Ashita exposes the rank bits, else skill
   alone) · `GP 1,250` (craftwatch, new Fishing=0x20 offset) · `VP 5,000` (helmwatch
   `pointsFor('Fishing')` — **already streaming today**, zero new packet work).
2. **Gear matrix** — four columns, helm's rendering language (green owned /
   "you're awesome" cascade within a slot / dim unowned): `BASE SET · ANGLER'S (+1) ·
   GUILD (GP) · MARINERS (VP)`. **Holy-light glow: Mariners column ONLY** (Henrik
   round 2 — the real fishing end-game; Expert Angler tooltips on Tunica/Boots) plus
   the two legendary rods. Rods below: standard ladder greens by ownership OR by the
   legendary cascade (owning Lu Shang's/Ebisu greens them all); LEGENDARY column =
   Lu Shang's + Ebisu (the +1s undisplayed). Every cell = icon + name + tooltip
   (renderItemTooltip — view_ids rides along free; explicit notes win over the card).
3. **Target fish** — search box over fishdb (picker-style filtered list, the G3
   browse-list pattern). On selection:
   - fish facts line: required skill vs yours (skill-up window note: "+11 is the
     sweet spot"), size/legendary badge, bite-pattern hint ("night only", "dawn/dusk"),
     multi-hook flag.
   - **Where + bait table**: every (zone, area) the fish swims × every bait it takes,
     sorted best-first: **ISOLATED** rows (no other fish shares that zone+bait pool)
     first — the exact "isolate the fish over others" ask — then by fewest competitors
     (competitors listed by name in the tooltip). ⚠ badge when `fishing_mob` says that
     zone+bait can hook a monster; footnote that items can always bite (less with
     Smock/Apron).
   - **Rod verdict row**: every owned rod + the recommended buy, each scored with the
     REAL server math (lose/snap/break chances at your current skill): `SAFE` /
     `RISKY n%` / `TOO SMALL` / `LOSES: TOO LARGE` / `?` (customs). Best owned rod
     highlighted; legendary fish → legendary rods pushed to front.
   - **[Make target]** button → writes fishstate (rod+bait+target) → the bar and the
     engine follow.
4. **Baits owned** — every `AmmoType="FishingRod"` item you own, with per-container
   counts from `ownedcache.whereOf` (Inventory/Wardrobes vs Safe/Storage/Locker/Satchel
   split — "and box, if available"). Click a bait → reverse lookup: what it can catch
   HERE (current zone) vs anywhere, isolation rows included.
5. **Today's fishing ventures** — `[!ventures fishing]` button (types the command
   user-visibly, opens the 6 s 0x017 capture window — helmwatch's exact pattern) +
   parsed objective lines with JST-day staleness ("run !ventures fishing to refresh").
   Format is UNPINNED until a field capture (private module); parser is tolerant
   (helm line shape first: `Fishing: (Low) …, (Mid) …, (High) …`), raw lines kept +
   mirrored to `fishventures_capture.txt` until pinned.
6. **Guild corner**: GP balance, the static GP shop list (what to save for), the
   rank-up test fish for your NEXT rank (Thubu Parohren, Port Windurst), Lu Shang
   carp-quest note (Moat Carp 4401 pays 10 g, Forest Carp 15 g, counter is server-side).

## 3. Fish bar + engine overlay (idle-only pin)

- **`ui/fishbar.lua`** — craftbar/helmbar clone (own `d3d_present` hook, outlives the
  main window; `onOffSwitch` delegated to craftbar's pill). Content: pill ON/OFF +
  target-fish name button (opens the panel) + rod and bait **item icons** (itemicons
  module — no new assets needed; icons carry the shared tooltip) + bait count left.
  No category glyphs — fishing is one category; the rod icon IS the identity.
- **`fishstate.lua`** (per char): `{ enabled, at, target = &lt;fishid|nil&gt;, rod = '&lt;Name&gt;',
  bait = '&lt;Name&gt;' }`. `enabled` is **session-only, never restored** (the craftstate
  rule); `target`/`rod`/`bait` persist. `rod`/`bait` are RESOLVED item names — fishwatch
  picks them (verdict math + ownedcache) on target change and re-validates on the ~4 s
  bag heartbeat (bait stack exhausted → next owned candidate written; none left → field
  cleared, engine leaves the slot alone). The engine stays dumb: wear what the file says.
- **Engine (dispatch v64)**: `ensureFishState` (1 s cached read) + `fishStateActive`
  (enabled only — no auto/hold mode in v1) + `fishOverlayFor`, gated `event == 'Default'`
  AND standing aside on Engaged/Dead (v61 lesson verbatim — fishing animations 56-62
  never reach LAC as a status, so no extra case needed). `FISH_OVERLAY_SLOTS = { Main,
  Range, Ammo, Head, Neck, Body, Hands, Ring1, Ring2, Waist, Legs, Feet }` — Range/Ammo
  carry rod/bait straight from fishstate; armor (and Main) resolve `dlac:AutoFish`
  through the manifest `fish` ladders. **Main included on the CRAFT precedent** (craft's
  slot list carries Main/Sub) because Halieutica is a Main-slot fishing weapon — the
  ladder only ever contains fishing Mains, so players without one never see a Main swap;
  a swap does eat TP, which idle fishing accepts (worth a doc note in the panel).
  **Sub never touched**; no Back/Ear until a fishing item shows up there.
- **Arbitration**: three-way now — craft vs helm vs fish all read at Default; if more
  than one is active the **newest `at` stamp wins whole** (generalizes the v59 pairwise
  rule; pins still beat everything). Bars keep the belt-and-suspenders writes: enabling
  fish disables craft+helm at their state files (one-way requires, no cycles: fishwatch
  → craftwatch/helmwatch).
- **Manifest**: AUTO_FMT 7 → **8**; `fish` block built in triggersui's autoCommit walk —
  candidates = owned gear with `Stats.FishingSkill &gt; 0` OR a fishdb `gearBonus` entry;
  score = FishingSkill + gearBonus.fish (+ gearBonus.cexi ordering nudge); sort score
  desc, name asc, `FLADDER=4` rungs, level-gated at resolve time like helm.

## 4. Data — `data/fishdb.lua` (shipped) + `tools/gen_fishdb.py` (local, untracked)

Generator fetches the public SQL (raw.githubusercontent, cached under
`tools/fishing_cache/`), parses INSERTs, and emits one compact shipped table:

- `fish[id]` = name, skill, size, ranking, legendary(+flags), water, patterns
  (hour/moon/month), maxhook, rarity, item-flag, contest-flag, family.
- `baits[id]` = name, type (bait/lure/special), maxhook, flags. `aff[baitid][fishid] =
  power`.
- `rods[id]` = the full fishing_rod row (verdict math needs min/max_rank, atk, sizes,
  breakable, broken id, legendary, rating).
- `pools[zoneid][areaid]` = sorted fishid list (catch → group join, deduped);
  `fishZones[fishid]` = { {z, a}, … } reverse index. `zoneNames[zoneid]` from
  fishing_zone (self-contained — no GetString dependency in tests), `areaNames`.
- `mobs[zoneid]` = { {baitid|0, areaid, nm}, … } — the ⚠ mob-bite warning.
- `guild` = GP shop rows, rank ladder + test fish, KI list.
- `gearBonus[itemid]` = { fish=+n, cexi=+n } scanned from tools/api_cache (mods
  127/2004/2005) — the private-mod supplement, ordering-only.
- `meta` = { generated = &lt;date&gt;, source = &lt;branch/sha&gt;, counts per table }.

Isolation is NOT precomputed — `fishcalc.isolationFor(fishid)` derives it live from
`pools` + `aff` (138 fish × small lists; trivial), so future skill-aware refinements
don't need a regen. The generator PRINTS a handful of verified isolation examples for
the test fixtures.

## 5. Modules

| File | Role |
|---|---|
| `data/fishdb.lua` | shipped database (generated; §4) |
| `feature/fishcalc.lua` | PURE logic, fully headless-testable: effective skill, verdictFor(fish,rod,skill) → {lose,snap,break,label}, rodRanking, isolationFor, baitsFor, hourHint, gear-ladder scoring helper |
| `feature/fishwatch.lua` | state owner: fishstate read/write (session-only enabled), target/rod/bait resolution + bag heartbeat re-validation, skill read (GetCraftSkill(0)), !ventures 0x0B5 trigger + 0x017 capture → fishventures.lua + raw mirror, `/dl fish` subcommands, barVisible; VP delegated to helmwatch, GP to craftwatch |
| `ui/fishui.lua` | the panel (§2), helmui's DI shape (`render(deps, availW)`), imgui pcall-guard |
| `ui/fishbar.lua` | floating bar (§3) |
| `dispatch.lua` v64 | ensureFishState/fishStateActive/fishOverlayFor/FISH_OVERLAY_SLOTS, `dlac:AutoFish` resolveVirtual branch (manifest `a.fish`), three-way arbitration |
| `ui/triggersui.lua` | +1 Automations row, fish detail delegation, autoCommit `fish` manifest block (AUTO_FMT 8) |
| `feature/craftwatch.lua` | GP_OFFSET += `Fishing = 0x20` (fixture test flips from "ignored" to parsed) |

## 6. Field tests (dlacprobe stays home — none of these need probes)

1. `!ventures fishing` — one capture pins the reply format (until then: tolerant parse +
   raw mirror). Also confirms the command's exact spelling.
2. VP sanity: panel VP vs in-game Fishing venture points (label already field-confirmed
   in the 0x1A4 stream 2026-07-17).
3. GP: `/dl fish gp` (or panel) vs guild NPC balance — offset 0x20 is fixture-proven but
   not field-proven.
4. Overlay: pill ON at a pond — rod+bait+armor dress on idle, combat gear returns on
   engage, bait re-equips after a stack runs out (heartbeat rewrite).
5. Halieutica/Mariners/Brigands Eyepatch: if Henrik owns any, hover shows them in
   ladders via gearBonus; report actual in-game stats text so the "unverified" labels
   can be tightened.

## 7. Open questions (server-questions.md style)

- ~~Mods **2004/2005** semantics~~ **ANSWERED round 2**: Expert Angler — 2004 Fatigue
  Limit +%, 2005 Golden Arrow Rate +% (bg-wiki Ventures page; values match the DB).
- Are Lu Shang's +1 / Ebisu +1 / Halieutica / Brigands Eyepatch obtainable at all?
  Henrik believes not (they exist only in the live DB) — undisplayed until one shows up.
- Does `!ventures fishing` exist as a sub-command (vs plain `!ventures`)? Field test 1.
- Ashita rank bits for fishing cap: if `GetCraftSkill(0)` exposes rank like retail
  (cap = (rank+1)×10), status line shows skill/cap; else skill only.
- Fish Ranking contest (fully wired server-side, 23 eligible fish) — deliberately out
  of v1; the `contest` flag ships in fishdb for a later "contest corner".
