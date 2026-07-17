# Conditional item effects — set bonuses + conditional latents, one evaluator

> **Status: P1 + P3 SHIPPED for gear sets (2026-07-18).** `gear\geareffects.lua`
> (evaluator), set bonuses in worn/planned totals + panel captions + the hover tier
> ladder, and the optimizer crediting (`opts.effects`, seeded restarts, append-only
> pool augmentation) are live — ADR 0011 records the optimizer decision, tests
> GD/GE/HB1-HB11 pin it. Latent data ships and loads (dormant). **Still open:** P2
> (latents in display — issue #41), P4 (latent scoring context — #43), P5 (broader
> predicates + `__env` mirror — #44). The honesty captions the phasing planned were
> skipped: P1 and P3 landed together, so there was never a sets-shown-but-not-weighted
> window. Design text below is as approved 2026-07-17; line anchors predate the ship.

> **Approved direction (2026-07-17).** Supersedes the *plan* section of
> `docs/design/latent-rings.md` (the research there stands unchanged; its "optimizer out of
> scope" call is **reversed** by maintainer direction). Henrik's ask: "we want the latent
> effects to be properly documented, scalable, as well as sets. If possible, would be nice
> if they could be part of weight calculations and total stats, where weight calculations
> would consider set pieces as a potential candidate if they were together or not."
> Angle: **one conditional-effect abstraction, one TRUE whole-combination evaluator,
> everything else derived from it** — stat page, hover, totals, and the optimizer objective.

---

## 1. Goal & non-goals

**Goal.** Every stat an item can contribute — unconditional catalog stats, level-scaling
latents, conditional latents (weather/HP/TP/…), and gear-set bonuses — is represented by one
abstraction and resolved by one evaluator, so that:

1. The **stat page, hover tooltips, and worn/planned totals** show conditional contributions
   with a clear active-vs-conditional presentation (Lava's + Kusha's finally shows
   ATT +6 / ACC +12 / DEF +6 when both rings are in the composition).
2. The **optimizer's objective function IS the true whole-combination evaluation** — a set
   piece's score rises when its partners are already chosen or jointly choosable, and the
   number the optimizer reports is the same number the totals panel shows.
3. New condition classes and new set shapes are added by **data regeneration plus a small
   evaluator entry**, never by touching UI or optimizer code.

**Non-goals.**

- The dispatch engine does not evaluate conditional effects. The game applies the real
  latents/set bonuses at equip time; dlac's evaluation is planning/display/scoring only —
  the exact posture level scaling already takes (`data\levelstats.lua:15-16`: "The dispatch
  engine never needs it -- it equips by name; the GAME applies the real latents"). No seeded
  file changes, no `dispatch.M.VERSION` bump — with one explicitly optional exception (§5,
  the `__env` mirror), which is order-independent and deferred by default.
- No runtime fetching, ever (catalog distribution model; rejected twice —
  `docs/history.md:48-49` and `:194-197`).
- No per-condition user toggles in v1 (history lesson: global automation toggles AND per-set
  SetOptions were both fully built, then deleted — `docs/history.md:103-105`). Assumptions
  are *derived first*, explicit later (§8).
- No guarantee of global optimality in the optimizer. What we do guarantee: the returned
  assignment is scored by the exact evaluator, the result is provably ≥ the plain-climb
  result (monotone restart acceptance, §7.3), and every set bonus reachable from the
  candidate pools within the seed budget gets a dedicated search basin. Approximation lives
  in the *search*, never in the *evaluation*.

---

## 2. Vocabulary (proposed CONTEXT.md additions)

| Term | Definition |
|---|---|
| **Conditional Effect** | A stat contribution that applies only under a condition: `{ source, level(composition, ctx), tiers }`. Set bonuses, conditional latents, and level scaling are all instances. |
| **Effect Level** | The computed number a tier table is indexed by: worn/planned piece count for a set; 0/1 from a predicate for a latent; character level for level scaling. |
| **Tier Table** | Map from Effect Level → flat stat deltas (`{ Accuracy = 12, ... }`). Exactly one tier applies: `tiers[min(level, max)]`, nil below `min`. Value-at-count replacement, never cumulative. |
| **Composition** | A concrete slotLabel→record assignment: the worn set, the planned working set, or the optimizer's current assignment. Sets are PLANS (ADR 0006) — a composition is a plan-side object; it never gates building. |
| **EvalContext (ctx)** | The game-state side of evaluation: level, subjob, and one truth value per condition class (`true` / `false` / `nil` = UNKNOWN), assembled per surface by `condsource` (§5). Frozen for the duration of an optimizer run. |
| **True Combination Evaluator** | `geareffects.comboStats(composition, ctx)` — the single source of truth for "what stats does this whole composition have". Totals, hover attribution, and the optimizer objective all derive from it. |
| **Plan-known condition** | A condition decidable from the plan itself (set piece count, EQUIPPED_IN_SLOT, SUBJOB, JOB_LEVEL). Always evaluated. |
| **Volatile condition** | A condition depending on live/momentary state (weather, HP%, TP, buffs). Live-read for worn display; assumption-driven for scoring. |
| **Assumption** | A scoring-ctx entry declaring a volatile condition true for scoring purposes (e.g. a WS-trigger set assumes `TP_OVER`). Derived from set purpose in v1; explicit per-set rows later (§8). |
| **Set-seeded restart** | An optimizer restart from the converged baseline assignment with a feasible gear-set's pieces force-placed, so bonuses whose pieces are individually worthless still get a search basin. Kept only on strict improvement. |
| **Conditional (display state)** | A stat delta whose effect is known but whose condition is not currently satisfied — rendered dimmed/bracketed with a `why` code, never summed into the active total. |

---

## 3. Data model

### 3.1 Generated file: `data\gearsets.lua`

```lua
-- GENERATED by tools/gen_gearsets.py from CatsAndBoats/catseyexi@base scripts/globals/gear_sets.lua
-- Set bonuses: pieces[] + per-piece-count stat-delta tiers, active when count >= min.
-- Tiers are MATERIALIZED per reachable count; runtime picks tiers[math.min(count, max)].
-- Do not hand-edit; re-run the generator instead.
return {
    [70] = {  -- Lava's + Kusha's
        pieces = { 15850, 15851 },
        min    = 2,
        max    = 2,
        tiers  = { [2] = { Attack = 6, Accuracy = 12, DEF = 6 } },
    },
    [71] = {  -- Iron Ram (5-piece, tiered)
        pieces = { --[[5 ids]] },
        min    = 2,
        max    = 5,
        tiers  = {
            [2] = { FireMagicEva = 5,  --[[...all 8 elements]] },
            [3] = { FireMagicEva = 10, --[[...]] },
            [4] = { FireMagicEva = 15, --[[...]] },
            [5] = { FireMagicEva = 30, --[[...]] },
        },
    },
    -- 126 sets total (39 flat, 87 tiered)
}
```

Key decisions:

- **Stat NAMES, never mod ids.** The spike's proof shape (`docs\design\latent-rings.md:83`)
  keys deltas by mod id; shipping that would leak the deliberately-unshipped mod enum
  (`.gitignore` tools/ block; `data\statdefs.lua:10-11`: "NO server mod-ids live here…
  Safe to publish: it only knows stat NAMES"). The generator translates through the same
  ModName→key bridge as `tools\gen_levelscaling.py` (its `CORE` dict, `:32-37`) — hoisted
  into a shared module (§4).
- **Tier semantics pinned to the server applier — verified against the actual code**
  (direct source read 2026-07-17, Appendix C). The applier computes
  `modTierIndex = math.min(setCount, maxEquippedReq) - minEquipped` and applies
  `modData[modTierIndex + 2]` (gear_sets.lua:2498-2506) — a tier value is the value **at**
  that count (replacement, not cumulative; header comment gear_sets.lua:9-11 says so
  explicitly: "Mod parameters are the total value"). Server defaults: `minEquipped = 2`,
  `maxEquipped = uncapped` (`xi.MAX_SLOTID + 1`, :2500). The generator therefore derives
  `max` as `maxEquipped` when the source sets it, else `min + (tier-value count − 1)` —
  matching the server's effective clamp and protecting against the server's own
  tier-overflow hole (an uncapped set worn above its tier length indexes nil server-side).
  The runtime rule is one lookup, `tiers[math.min(count, e.max)]`, nil when
  `count < e.min`. `max` is emitted explicitly so the runtime never re-derives server
  indexing (graft: B). No runtime tier arithmetic → no ambiguity; a flat set is a one-key
  tier table.
- **Piece lists are NOT one-piece-per-armor-slot** (Appendix C). 37 of the 126 sets carry
  MORE items than their piece cap — alternates. E.g. set `[43]` Paramount: **9 items (one
  earring + eight WEAPONS), min 2, max 2** — "any 2 of the list" activates it, including
  weapon+weapon. Sets span Main/Sub/Ranged, an item can belong to **multiple sets** (the
  server's `itemToSetId` maps id → *list*, gear_sets.lua:2451-2467, which is why `setsOf`
  returns a list), and shape census over all 126: 70× (min2, uncapped), 4× (min2, max2),
  33× (min2, max5), 19× (min5).
- Emission sorted by setId, pieces sorted ascending — deterministic diffs (the `pairs()`
  order rule, HANDOFF hard rule 8, applied to the generator).

### 3.2 Generated file: `data\latentstats.lua`

```lua
-- GENERATED by tools/gen_levelscaling.py (latent router) from CatsAndBoats/catseyexi@base sql/item_latents.sql
-- Conditional latents: additive stat deltas active while cond(param) holds.
-- Level latents (50 JOB_LEVEL_BELOW / 51 JOB_LEVEL_ABOVE) are NOT here -- they ship in levelscaling.lua.
-- Do not hand-edit; re-run the generator instead.
return {
    [10975] = { { stat = 'Attack', add = 13, cond = 'WEATHER_ELEMENT',   param = 8   } },
    [11312] = { { stat = 'STR',    add = 5,  cond = 'TP_OVER',           param = 100 } },
    [11355] = { { stat = 'Enmity', add = -1, cond = 'HP_UNDER_PERCENT',  param = 75  } },
    -- ~1,849 rows across ~800 items (1,963 total minus the latent-50/51 rows already routed to levelscaling.lua)
}
```

- Outer keying `[itemId] = { rows }` mirrors `data\levelscaling.lua` for O(1) id lookup —
  the access pattern `levelstats.apply` depends on (`data\levelstats.lua:44`).
- `cond` is the **latent enum NAME string** (from `scripts/enum/latent.lua`). Unlike the mod
  enum, latent condition names are not a scrape secret — dlac already ships
  public-SQL-derived `data\spells.lua`/`data\abilities.lua` — and name strings make the file
  self-documenting and the evaluator registry readable. A latent id that does not resolve in
  the enum is emitted as `UNKNOWN_<id>` with a generator report count — never guessed, never
  active at runtime (graft: C).
- **The level-latent boundary is 50/51, NOT 52.** `tools\gen_levelscaling.py:56` gates on
  `lat not in (50, 51)`: latent 51 = JOB_LEVEL_ABOVE (`from`), latent 50 = JOB_LEVEL_BELOW
  (`below`). Latent **52 is WEATHER_ELEMENT** — an earlier generator version misread 52 as
  "below level" and shipped bogus rows (the bug is documented at `gen_levelscaling.py:12-15`,
  with a regression assert at `:91-92` that a weather-element param can never appear as a
  `below` row). The winning-draft/digest claim of "latents 50/51/52" was wrong; the shipped
  generator is the authority. `latentstats.lua` must contain **zero** rows with latent 50
  or 51, and latent-52 rows land here as `WEATHER_ELEMENT`.
- Row arithmetic, corrected against a direct row count (Appendix C): **1,962 active INSERT
  rows / 854 distinct items**; 114 of them are level latents (105× latent 51 + 9× latent 50)
  already routed to `levelscaling.lua` (shipped: 8 items / 114 rows) — so latentstats lands
  at **~1,848 rows** — pinned as a range, not an exact count, because unmapped-mod skip
  behavior differs per file (§4.A.4).
- **Only line-initial `INSERT` rows count.** The SQL carries **128 commented-out INSERT
  rows** — latents the server does NOT implement ("TODO"s, wiki disputes). One of them
  (item 17275, a WEAPON_BROKEN crit row) is fully numeric and WOULD match the existing
  5-tuple regex scanned over the whole file — a phantom effect the game never applies. The
  latent router must anchor its regex to line-start `INSERT` (verified: with that anchor,
  zero commented rows leak; without it, exactly that one does).

### 3.3 The unified runtime effect shape

Inside the evaluator, everything normalizes to:

```lua
-- One conditional effect
{
    source = 'set' | 'latent' | 'levelscale',
    min    = <number>,                          -- activation floor for the level
    max    = <number>,                          -- clamp ceiling (from data, never re-derived)
    tiers  = { [level] = { statKey -> delta } },
    -- level is COMPUTED, per source:
    --   set:        # composition slots holding a piece of this set, counted PER SLOT
    --               (duplicates count twice -- verified server semantics, §7.2) and
    --               level-gated: a piece counts only while ctx.level >= its required
    --               level (the server's sync gate, gear_sets.lua:2488 -- Appendix C)
    --   latent:     predicate(cond, param, ctx) and 1 or 0  (min = max = 1)
    --   levelscale: ctx.level                                (thresholds as tiers)
}
```

Level scaling is *conceptually* an instance (condition class = job level, tiers = threshold
rows) and *mechanically* delegated: `geareffects.itemStats` calls the untouched
`levelstats.effective` (`data\levelstats.lua:35-39`) as its base step. This keeps the pinned
resolver tests (`tests\run_tests.lua:553-568`) and the shipped `levelscaling.lua` byte-stable
while the model stays unified: the generator pipeline, the "tier table indexed by a computed
level" semantics, and the documentation treat all three sources identically.

---

## 4. Generator (tools\, distribution, regeneration)

All generator code lives in gitignored `tools/` (`.gitignore` tools/ block: "we don't publish
how-to-scrape or the mod enum"); only `data/` outputs ship. The addon never fetches — stated
three times in-tree (`tools\README.md:42`, `tools\apicrawl.py` distribution note,
`tools\gen_craftdb.py:22`).

**A. Extend `tools\gen_levelscaling.py`** (it already downloads `item_latents.sql` —
URL `:29`, cached download `:41-45`):

1. Add a cached download of `scripts/enum/latent.lua` (same raw-URL + `api_cache/` +
   `--refresh` pattern) → regex to `latentId → NAME`.
2. The existing 5-tuple regex (`:53`) captures every row — **re-anchored to line-start
   `INSERT`** so the 128 commented-out (server-unimplemented) rows cannot leak (§3.2; one
   fully-numeric commented row exists today). Where the current gate
   `if lat not in (50, 51): continue` (`:56-57`) drops a row, route it to a second dict and
   emit `data\latentstats.lua`. Latents 50/51 keep flowing to `levelscaling.lua` exactly as
   today. **Assert the refactored script's `levelscaling.lua` output is byte-identical to
   the shipped file** before writing anything — the mechanical proof that every `levelstats`
   consumer is untouched (graft: B).
3. modId → stat key via the shared bridge (below) — inheriting the scale-trap handling
   (DT-family/SkillchainDamage stored ×100, TP_BONUS literal — `docs/history.md:45-46,
   205-209`) instead of re-deriving it. Unmapped stat *names* pass through raw, as today
   (`gen_levelscaling.py:59` — statdefs Misc-buckets them, `data\statdefs.lua:7-8` graceful
   fallback); unresolvable *conditions* are emitted as `UNKNOWN_<id>` and counted in the
   run report.
4. Sanity pins before writing (the `:83-92` convention): latentstats row/item counts within
   1,700–1,900 / 750–900; `10975 → Attack +13 WEATHER_ELEMENT(8)`;
   `11312 → STR +5 TP_OVER(100)`; `11355 → Enmity -1 HP_UNDER_PERCENT(75)`; **zero** rows
   with latent 50/51 in latentstats; the existing level-file asserts (Rajas trio, Chocobo
   Shirt, no-weather-as-below) stay live.

**B. New `tools\gen_gearsets.py`:**

1. Cached downloads: `scripts/globals/gear_sets.lua`, `scripts/enum/item.lua`,
   `scripts/enum/mod.lua` (branch `base`; sparse-checkout recipe recorded at
   `docs\design\latent-rings.md:130-133`).
2. Parser = the proven spike (`latent-rings.md:134-138`): regex enums to id→name; line
   state-machine over `gear_sets.lua` collecting per `[setId]` its `xi.item.*` pieces,
   `minEquipped`, mod tiers; materialize tiers per reachable count and emit `min`/`max`
   explicitly (§3.1).
3. Mod → stat key through the shared bridge.
4. Sanity pins: exactly 126 sets (39 flat / 87 tiered); `[70] = pieces {15850,15851},
   min 2, tiers[2] = {Attack=6, Accuracy=12, DEF=6}`; every tier key within `[min, max]`;
   `max <= #pieces` is **not** assertable — **37 sets have more pieces than max**
   (alternates, §3.1); instead pin the shape census (70/4/33/19 per §3.1) and set `[43]`
   Paramount = 9 pieces / min 2 / max 2; every piece id resolves in the item enum.
5. Fail-soft on unknowns + a README "ask the server team for a dump" closing move (the
   private-submodule gap pattern, `tools\gen_craftdb.py:25-27`, `tools\README.md:63-68`) —
   CatsEyeXI-custom sets may not exist in the public repo; log and skip, never guess.

**C. New `tools\modmap.py` — the shared modId→stat bridge (mandatory).** Hoist the
`MODMAP` regex load (`gen_levelscaling.py:47-50`) + the `CORE` dict (`:32-37`) + the ×100
scale rules into one module imported by `gen_levelscaling.py`, `gen_gearsets.py`, and any
future SQL generator. The "KEEP IN SYNC with apiscan.py's CORE" comment (`:31`) dies with
this change — the scale traps get exactly one home (graft: C, upgraded from the draft's
parenthetical suggestion to the plan of record).

**Regeneration workflow** (append to `tools\README.md`): `python gen_levelscaling.py
--refresh` (now writes two files, asserting levelscaling.lua unchanged unless the server
data actually changed) and `python gen_gearsets.py --refresh` → `/addon reload dlac` →
commit `data\levelscaling.lua`, `data\latentstats.lua`, `data\gearsets.lua`. Freshness = git
commit, as with all data files (no per-file versioning; `addon.version` at `dlac.lua:28`
untouched).

**Size/load**: gearsets ≈ a few KB, latentstats ≈ 80 KB — noise next to the 6.15 MB catalog
already loaded by plain `require` (`ui\gearui.lua:56`). Data files are `return { ... }`
constant tables: zero locals, no LuaJIT 200-cap exposure.

---

## 5. Runtime evaluator — `gear\geareffects.lua` + `feature\condsource.lua`

### 5.1 `gear\geareffects.lua` — pure core, zero Ashita imports

A new pure-core module in the `groupsmodel`/`actionpicker` mold: Ashita/imgui/file-IO-free,
data injected via `configure`, headless-tested, **never seeded into LAC**. It performs no
live reads at all — ctx comes in as a plain table (graft: C — purity is structural, not
"deps injected").

```lua
local M = {};
M.configure({ gearsets = <data or {}>, latents = <data or {}>, levelstats = <resolver> })

-- Item-local resolution (levelscale + latents). Flat table out; zero-copy
-- passthrough when the item has no effects (the levelstats.lua:37 discipline).
M.itemStats(rec, ctx, slotLabel) -> statsTable
-- Conditional (inactive) rows for display, with three-valued why codes:
--   why = 'unmet'         condition evaluated false under this ctx
--   why = 'not-evaluated' condition has no registered predicate (incl. UNKNOWN_<id>)
--   why = 'not-ready'     predicate needed a ctx field that is nil this cycle (ADR-0007)
M.itemCond(rec, ctx, slotLabel)  -> { { stat, add, cond, param, why }, ... } | nil

-- THE TRUE COMBINATION EVALUATOR. composition = { [slotLabel] = rec }.
M.comboStats(composition, ctx) -> { stats = {k->v}, setBonuses = { {setId, count, tier, deltas, active}, ... } }
M.comboCond(composition, ctx)  -> conditional (inactive) rows for display

-- Optimizer support (§7): membership + tier access without full re-evaluation
M.setsOf(itemId) -> { setId, ... } | nil        -- reverse index, built at configure()
M.setTier(setId, count) -> deltasTable | nil    -- tiers[math.min(count, max)], nil below min
```

Data is pcall-required with `{}` fallback at the composition root (gearui), exactly like
`data\levelstats.lua:21-22` — a user missing a data file degrades to today's behavior,
never errors.

**Condition predicate registry** — one small function per condition name,
`predicate(param, ctx) -> true | false | nil` (nil = UNKNOWN, produced when the ctx field
the predicate needs is nil). Unregistered names (including every `UNKNOWN_<id>`) → UNKNOWN
with `why='not-evaluated'`. UNKNOWN never adds to active stats; it renders as conditional
(§6) and scores per the context policy (§8). This registry is the "small evaluator
additions" scalability seam: lighting up a new condition class = one registry entry + one
ctx field in condsource.

**Copy-on-write discipline**: `enrichGearFromCatalog` mutates shared `Stats` tables in place
(`ui\gearui.lua:266-310`) — geareffects keeps `levelstats.apply`'s rule
(`data\levelstats.lua:46-48`): never write into `rec.Stats`; return fresh tables only when
something actually applies, the shared table otherwise.

### 5.2 `feature\condsource.lua` — the impure ctx snapshot builder

All live reads live here, not in geareffects and not inline in gearui's render hook
(graft: C — keeps the evaluator 100% headless):

```lua
M.display() -> ctx      -- live-read volatile conditions, ~1s throttled, nil on failed reads
M.scoring(policy) -> ctx -- policy-resolved volatile values (§8), frozen object per run
M.epoch() -> number      -- increments whenever any display-ctx field changes value
```

- Live reads use the existing render-hook throttle style (the modestate-mirror reads,
  `ui\gearui.lua:1010-1016`). ADR-0007 discipline: a nil/failed read makes the condition
  UNKNOWN this cycle and is re-read next cycle — no latching.
- `ctx == nil` (pre-login, tests without configure) makes **everything** volatile
  conditional with `why='not-ready'` — pinned by test (§10.2).

### 5.3 Condition coverage matrix

Addon-state readability per the live-state map (weather/day/time memory sigs are LAC-side
only; vitals/buffs/zone/job are AshitaCore-readable in both states):

| Condition | Rows | Phase | Truth source (addon state) |
|---|---|---|---|
| SET piece count | 126 sets | **P1** | Composition only, no live reads (worn: the `getEquippedId` walk, `ui\gearui.lua:596-622`; planned: the `M.working` walk, `ui\gearui.lua:1979-1993`) |
| JOB_LEVEL_ABOVE/BELOW (50/51) | 114 shipped | **shipped** | `levelstats.effective`, unchanged |
| EQUIPPED_IN_SLOT | 12 | **P2** | Composition (slotLabel is known per pool/slot at resolve time); server checks the latent's OWN slot == param (cpp:1310-1312) — plan-evaluable, zero game state |
| SUBJOB | 72 | **P2** | Plan-known: `getSubInfo` (`ui\gearui.lua:359`) / plan ctx |
| TP_OVER | 11 | **P2** | Assumption (scoring) + live `GetParty():GetMemberTP(0)` (worn display; the `gearoptim.lua:202-229` MP-helper pattern) |
| TP_UNDER | 55 | **P2** | Same truth source. This fork checks plain `tp < param` (cpp:809-811) despite the enum comment's "and during WS" — relic-style latents; correctly assume-FALSE in WS contexts where TP is full |
| HP_UNDER/OVER_PERCENT | 68+11 | **P2** | Live `GetMemberHPPercent(0)` + assumption for scoring (HP_UNDER is `<=`, HP_OVER is `>` — enum comments) |
| DURING_WS | 1 | **P2 (ctx-only)** | Never live in addon state (action state is LAC-only); TRUE by assumption in WS-trigger contexts (§8) |
| WEATHER_ELEMENT (latent 52) | 57 | **v2 (P5)** | No addon sig (`GetWeather()=0` shim stub, `dlac.lua:129`). Assumption-driven for scoring, "conditional" in display; optional `__env` engine mirror upgrades display (§5.4). Fires on the ELEMENT of current weather, single AND double (cpp:1219-1221) — an obi lights up in both |
| TIME_OF_DAY (26) + days-of-week (ids 28-36) | 70 + ~112 | **v2 (P5)** | Same (`pVanaTime` sig is LAC-side; `GetDay()=0` stub, `dlac.lua:130`). TIME_OF_DAY windows: 0 = 06-18h, 1 = 18-06h, 2 = dusk-dawn 17-07h Vana time (cpp:986-1000) |
| STATUS_EFFECT_ACTIVE / FOOD_ACTIVE | 280+119 | **v2 (P5)** | `GetPlayer():GetBuffs()` — readable in both states, needs buff-id table work |
| IN_DYNAMIS | 79 | **v2 (P5)** | `GetParty():GetMemberZone(0)` + a static Dynamis zone-id list |
| WEAPON_DRAWN | 20 (+49 WEAPON_DRAWN_MP_OVER) | **v2 (P5)** | `GetEntity():GetStatus(myIndex)` (the shim's Status is a dead 0) |
| PET_ID | 149 | **v2 (P5)** | Pet entity reads; match by Name (entity `.Id` is a server id). OR-family heavy (§6) |
| Long tail: MOON_PHASE 53, IN_ASSAULT 51, HP+TP combos 47, PARTY_MEMBERS(_IN_ZONE) 81, ZONE 33, IN_GARRISON 33, AVATAR/JOB_IN_PARTY 44, VS_ECOSYSTEM/FAMILY 38, … | ~380 | **v2+ (data ships)** | Each is one registry predicate whenever wanted; renders "known, not yet evaluated" meanwhile |
| NATION_CONTROL | 184 | **not evaluated** | No conquest read exists on either side; a 0x05E parse would be new machinery — and probing belongs in dlacprobe, never dlac. Server-side it also requires signet/sanction/sigil (cpp:1222-1237) |
| WEAPON_BROKEN | 70 | **not evaluated** | No extdata broken-flag decode; the addon is the closer side (the `feature\augments.lua` extdata machinery) if ever wanted |

Row counts are a direct count of the 1,962 active rows (Appendix C), not estimates.
"Not evaluated" rows still ship in the data and still render as conditional rows in the
hover with `why='not-evaluated'` — visibility without false numbers.

### 5.4 Optional: the `__env` engine mirror (isolated, order-independent)

Weather/day/time truth written by the engine into `modestate.lua` as an `__env` table at the
existing `saveModeState` cadence (`dispatch.lua:2092`), gated by `__version`/freshness
exactly like `__locks`, read by the GUI's ~1s throttled mirror read
(`ui\gearui.lua:1010-1016`). It upgrades weather/day *display* from "conditional" to
live-true without any addon memory sigs. It is the **only** piece of this design that
touches a seeded file, therefore the only piece requiring a `dispatch.M.VERSION` bump and
the reload-order note (HANDOFF hard rule 4). It is deliberately isolated so it can ship
**any time after P1** — before the optimizer phases if Henrik wants live weather display
early, or never (graft: C). Default: deferred to P5.

### 5.5 Caching & invalidation

- `condsource.epoch()` is the invalidation clock. `gearfmt.statSummary`'s memo
  (`rec._statStr`/`rec._statLvl`, keyed by level only today — `gear\gearfmt.lua:97-123`)
  grows its key to `(level, epoch)` — otherwise an HP/TP-conditional summary renders stale.
- `candCache` (`ui\gearui.lua:488-489`, keyed `job|level` at `:556`) additionally
  invalidates on epoch change **only when a scoring-relevant assumption changed** — volatile
  display-only changes must NOT thrash candidate sorts. Scoring ctx and display ctx are
  distinct objects (§8), so this distinction is structural, not a heuristic.
- `levelstats.effective` itself is uncached (computed fresh per call), so the resolver seam
  is already safe for volatile inputs; the staleness risk is entirely in the consumers above.

---

## 6. Stat fold — hook points, active-vs-conditional display, totals

**Principle: one resolver, six call-site families, all rerouted through geareffects.**

| Surface | Today | Change |
|---|---|---|
| `effStats` (`ui\gearui.lua:86`) | wraps `lscale.effective` | wraps `geareffects.itemStats(rec, uiCtx, slotLabel)`; still exported via `host.provide` (`ui\gearui.lua:3144`) and `fmt.configure` (`ui\gearui.lua:724`) — **the smoke_ui services-contract pin (`tests\smoke_ui.lua:173`) must be updated in the same commit** if new service keys (`condStats`, `comboStats`) are provided |
| `gearoptim.rankSlot` (`gear\gearoptim.lua:570-571`) | calls `lscale.effective` directly | takes an injected `resolve(entry, level)` defaulting to lscale (gearoptim stays pure); gearui injects the geareffects-backed resolver with the scoring ctx |
| `triggersui` manifests (`ui\triggersui.lua:694-695`, `:764-765`) | `lscale.effective` direct | switch to `geareffects.itemStats` with a **plan-known-only ctx** (no volatile conditions): manifests are scan-time snapshots by design — baking weather-dependent values there would be stale-by-design wrongness |
| `equippedui` compare (`ui\equippedui.lua:155-156`) | diffs two `S.effStats` | inherits automatically via the provided service |
| Worn totals (`wornSetTotals`, `ui\gearui.lua:596-622`) | sums effStats + aug fold | becomes `geareffects.comboStats(wornComposition, condsource.display())` + aug fold — set bonuses land here first (worn Lava+Kusha lights up) |
| Planned totals (`workingSetTotals`, `ui\gearui.lua:1979-1993`) | sums effStats over bestByLevel picks | becomes `comboStats(plannedComposition, scoringCtx)` — the planned composition is pure plan data, no live reads (the `M.working` walk needs nothing live) |

**One enrichment seam, not three patches** (graft: B). gearui gains a single
`candidateStats(rec, level, ctx)` helper = effStats + owned augment deltas
(`_ownedAugStats`, `ui\gearui.lua:523-530`) + ctx-resolved latents, and it feeds all three
scoring consumers: `scoreOfItem` (`ui\gearui.lua:534-544`), the joint optimizePicks pool
build (which today feeds raw `effStats` **without** augment deltas —
`ui\gearui.lua:2133` — a pre-existing gap this fixes en route), and the Sub marginal call
(`ui\gearui.lua:2169-2183`).

**Active vs conditional presentation.** Flat `key -> number` stats tables are load-bearing
everywhere (table values are skipped at `gear\gearfmt.lua:107,114,133,138` and in
`gearoptim`'s `statValue`, `gear\gearoptim.lua:130-145`) — so **active stats stay flat;
conditional info travels in a parallel structure**:

- **Hover tooltip** (`renderItemTooltip`, `ui\gearui.lua:877-887`): after the active stat
  list, render `itemCond` rows dimmed: `~ Attack +13 (Fire weather)`,
  `~ ACC +12 (set: with Kusha's Ring)`; `why='not-evaluated'` rows render as
  "(known, not yet evaluated)", `why='not-ready'` as "(waiting for game state)". The
  annotation precedent is the existing `'(scales with level -- shown for LvN)'` line at
  `ui\gearui.lua:884-886`. Condition names need human labels — a small `CONDLABELS` table
  in gearfmt; **label wording goes through Henrik row-by-row** (the stat-naming precedent:
  "Chance", "Cast Time-").
- **OR-families collapse to one hover row.** 173 (item, stat) groups carry multiple rows of
  the same condition class with different params (a pet list: Water / Leviathan / …; food
  tiers) — Appendix C. Evaluation needs nothing special (the predicates are mutually
  exclusive by param: one pet, one food), but display must group a family into ONE
  conditional line (`~ Attack +50 (with a water-type pet)`, `up to +N` when values differ)
  or an avatar item renders a dozen dim lines of noise. Grouping key: (stat, cond).
- **Totals panels** (`renderStatsPanel`, `ui\gearui.lua:1701`; call sites
  `ui\gearui.lua:3072` and `ui\equippedui.lua:287`): the panel gains an optional second
  table `cond`; the row renderer adds a bracketed dim suffix `[+12]` on rows with inactive
  conditional deltas. Active set-bonus deltas are already inside the flat totals
  (comboStats folded them) — a one-line "Set: Lava's + Kusha's (2/2)" caption under the
  panel attributes them.
- **Row summaries** (`gearfmt.statSummary`): unchanged content-wise (≤4 tokens of *active*
  stats) — conditional detail is hover's job.
- **Per-phase honesty labels** (graft: C): each phase ships a one-line truthful caption that
  the next phase removes — P1: "set bonuses shown in totals; not yet weighted by
  Auto-build" (removed by P3); P2: "conditional stats shown dimmed; not weighted" (removed
  by P4). The phase-gated version of the latent-rings honesty rule.

**Legacy duplicate stat registries**: any stat key newly introduced by set/latent data must
be checked against all three shadow registries, not just statdefs —
`renderStatsPanel`'s `STAT_GROUPS`/`STAT_ALIAS` (`ui\gearui.lua:1662,1679`), gearoptim's
`ALIAS_GROUPS`/`NEGATIVE_GOOD`/`canonStat` (`gear\gearoptim.lua:70-126`), and gearfmt's
`STAT_PRIORITY` (`gear\gearfmt.lua:59`). The generator's shared-bridge mapping keeps most
keys pre-existing (Attack/Accuracy/DEF already flow from levelscaling); the generator's
unmapped-names report is the trigger for this check.

**Objective/display unification**: `workingWeightedScore` (`ui\gearui.lua:1995-2002`)
currently sums per-item `scoreOfItem` — *already* inconsistent with `optimizePicks`' capped
totals. It becomes `optim.score(comboStats(plannedComposition, scoringCtx).stats, weights)`
computed on the whole composition — the panel's weighted number, the tooltip math, and the
optimizer's reported `total` are then the same function evaluated on the same object. That
is the payoff of the unified model: one evaluator, four surfaces, zero drift.

---

## 7. Optimizer integration — the algorithm

### 7.1 Decomposition that keeps the search cheap

The true objective over an assignment `A` (label → candidate) with a frozen scoring ctx:

```
Score(A) = Σ_w  perUnit_w · cap_w(  base_w  +  Σ_{label} vec_w(A[label])  +  setBonus_w(A) )
```

Two observations make this consumable by the existing hill climb (`M.optimizePicks`,
`gear\gearoptim.lua:694-786` — coordinate descent, ≤8 passes, EMPTY-preferring ties at
EPS=1e-6, `:766-777`) without explosion:

1. **Item-local conditional effects are per-candidate constants under a frozen ctx.**
   Latents and level scaling resolve *before pooling* — gearui already pre-resolves
   candidates (`ui\gearui.lua:2133`); with ctx frozen for the run, latent-active deltas are
   simply inside `cand.stats`, hence inside the precomputed per-candidate weight vectors
   (`gear\gearoptim.lua:715-728`). EQUIPPED_IN_SLOT is per-(candidate, label), and pools are
   per-label — still precomputable. **Zero new cost in the inner loop for latents.**
2. **Only set bonuses are genuinely cross-slot, and they depend on the assignment ONLY
   through per-set piece counts.** Maintain `cnt[setId]` incrementally.

### 7.2 Mechanics (all inside `M.optimizePicks`, opt-in via `opts.effects`)

New optional input, fully backward compatible (nil ⇒ bit-identical behavior to today):

```lua
opts.effects = {
    setsOf  = geareffects.setsOf,      -- itemId -> {setId,...}
    setTier = geareffects.setTier,     -- (setId, count) -> deltas | nil
    baseComposition = { rec, ... },    -- already-chosen pieces counted into cnt[] (Sub marginal call)
}
```

- **Pool prep**: each candidate carries `setIds = setsOf(ref.Id)` (computed once, with the
  vecs). Also precompute, per set, its tier deltas projected onto the weight list:
  `tierVec[setId][count][wi]` — sets whose bonus stats carry no weight project to all-zero
  and are dropped from consideration entirely.
- **Incremental counts**: the probe loop already assigns `picks[label] = ci` before calling
  `totalScore()` (`gear\gearoptim.lua:770-780`); wrap assignment in `setPick(label, ci)`
  which updates the per-set piece-presence for the old/new candidate's setIds. O(1) per
  probe (setIds is almost always length 0 or 1).
- **Duplicate-piece counting — VERIFIED from the server source** (settled after the draft
  round by a direct applier read; Appendix C). Counting is per equipped SLOT with **no
  uniqueness check** (gear_sets.lua:2479-2495): two owned copies of the same set piece in
  Ring1/Ring2 count as **2**. The only gate is level: a piece counts while
  `getMainLvl() >= its ReqLvl` (:2488) — under level sync, over-level pieces stop counting
  server-side; optimizer pools are already level-filtered, so the gate matters for worn
  display and sync scenarios, not for builds. `cnt[setId]` is therefore a plain per-slot
  increment (also the cheaper implementation). Two owned copies legitimately coexist under
  gearui's `oc[Id] >= 2` rule (`ui\gearui.lua:2142-2149`), so the case is real — e.g. 2×
  Paramount Earring alone activates set [43]. The rule stays a one-line switch in
  geareffects and a two-copies `/checkparam` remains a cheap optional field confirmation
  (§9 P3), but the source is unambiguous: the shipped default is **counts-twice**, and no
  `server-questions.md` entry is needed.
- **totalScore()**: after summing `base + vecs` per weight (`gear\gearoptim.lua:742-754`),
  add `Σ_{s : cnt[s] >= min_s} tierVec[s][min(cnt[s], max_s)][wi]` **inside the cap fold** —
  bonuses share the cap budget with regular stats, which is the game-truth (capped Haste
  from a set bonus is still capped). Cost per call: today O(#wl × #labels) ≈ 160 ops; added
  O(#activeSets × #wl) with #activeSets ≤ ~3 in practice — the inner loop stays sum-only.

### 7.3 The local-search hole and its fix: set-seeded restarts

Hill climbing with single-slot moves + strict improvement + EMPTY tie preference provably
cannot enter a k-piece bonus where each piece alone is a strict loss: every single insertion
scores ≤ 0. Two-sided fix, both at the same seam:

**(a) Set-aware pool augmentation** (fixes the top-20 prune, `gear\gearoptim.lua:817-824`,
and gearui's `#arr > 0` gate, `ui\gearui.lua:2135`): after ranking, **append** (never
remove) any eligible candidate that is a member of a *relevant* set — relevant = the set's
projected `tierVec` is nonzero AND ≥ `min` of its pieces are eligible across the run's
pools. Bounded: ≤ #pieces per relevant set, ≤ ~8 relevant sets ⇒ pools grow by a handful.
Append-only is what keeps this HARD-RULE-clean (§7.6).

**(b) Seeded restarts from the converged baseline** (grafts: B — replaces the draft's
greedy from-scratch seed placement):

```
run the plain climb once -> baseline picks B0, total T0      (bit-identical to today)
best, bestPicks = T0, B0
relevant sets, ordered by DESCENDING best-tier projected value,
                ties broken by ASCENDING setId               (deterministic, value-aware)
seeds = first SEED_SINGLE_CAP (6) relevant sets
      + unions of slot-disjoint feasible pairs among those,
        while total seeds <= SEED_TOTAL_CAP (12)             (hard deterministic ceiling)
for each seed s:
    picks = clone(bestPicks-invariant baseline B0)
    for each of the up-to-max(s) highest-value placeable pieces of s
        (piece lists can EXCEED max -- 37 alternate-piece sets, §3.1 -- so the seeder
         stops at max(s) pieces; respecting opts.conflict within the seed itself --
         one owned copy cannot fill both paired labels):
        place piece into a pool label containing a candidate with that Id;
        among eligible labels (Ring1/Ring2, Ear1/Ear2 pairs), choose the label
        whose INCUMBENT loses the least solo projected value   (least-loss heuristic)
    if #placed < s.min: discard seed
    run the 8-pass climb from this assignment (starts near-converged -> few passes)
    if total > best + EPS: best, bestPicks = total, picks     (monotone acceptance)
return bestPicks, best
```

**Weapon-membered sets ride `baseComposition`.** 37 sets span weapon slots (§3.1 — e.g.
[43]'s earring+weapon pairs), and weapon labels are typically outside an armor run's pools.
The joint autoBuild call therefore passes the already-chosen/pinned Main/Sub/Ranged/Ammo
records in `opts.effects.baseComposition` (the same channel the Sub marginal call uses) —
their setIds pre-load `cnt[]`, so an earring whose only partner is the equipped weapon is
credited without the optimizer ever touching weapon slots. A set whose remaining pieces sit
entirely outside the run's pools simply cannot be completed by the seeder — counted if
present, never searched for.

Seeded pieces are **not pinned**: the climb may evict them under strict improvement —
evicting one piece of a 2-piece set drops the bonus from `totalScore()` automatically, so
eviction happens only when genuinely better. A seed that doesn't pay for itself dissolves
back toward the baseline answer, and the monotone acceptance rule discards it: this IS the
"post-search set-substitution repair pass scored by the true evaluator", obtained
structurally rather than as an extra phase. **Monotone guarantee (for ADR-0011)**: the
returned assignment's true score is ≥ the plain-climb answer and ≥ every accepted
single-set-committed climb (graft: B).

### 7.4 Complexity, with numbers

- Today: ≤8 passes × 16 labels × ≤21 probes (20 candidates + EMPTY) ≈ 2,560 `totalScore()`
  calls × ~160 ops ≈ 4×10⁵ ops — milliseconds.
- With effects: per-probe cost 160 → ~190 ops (bonus fold), unchanged in order. Restarts
  multiply the probe count by (1 + #seeds) ≤ 13, but each restart starts from a converged
  assignment and typically converges in 1–3 passes; hard worst case ≈ 13 × 2,560 ≈ 33k
  probes ≈ 7×10⁶ ops — comfortably sub-frame for a button-press operation (`/dl best`,
  Auto-build). Auto-build pools are unpruned owned lists but small (a few dozen per slot);
  same bound shape. The hard SEED caps make degenerate wardrobes (someone owning pieces of
  30 sets) a non-event: the ordering drops the least-valuable sets, never arbitrary ones.
- Seed construction: O(#relevantSets × #pieces × #labels) ≈ 8 × 6 × 16 — negligible.
- Per-keystroke paths are untouched: `scoreOfItem` (`ui\gearui.lua:534-544`) and the
  candidate sort comparators (`ui\gearui.lua:569`) remain **per-item** — set bonuses
  deliberately do NOT enter per-item sorts (a single item has no combination), so
  weightsui's live-apply invalidation per keystroke (`ui\weightsui.lua:127-139`) costs
  nothing new.

### 7.5 What is exact, what is approximated — stated honestly

**Exact**: the objective. Every number reported (`out.total`, the totals panel,
`workingWeightedScore`) is the true whole-combination evaluation of the returned
assignment, caps and set tiers included. No proxy scores, no post-hoc bonus adjustment.

**Approximated**: the search. (1) Each restart converges to a *local* optimum of the true
objective under single-slot moves; (2) combinations of ≥3 mutually-dependent sets, or a set
whose basin is strictly dominated until some unrelated third slot changes, can be missed —
bounded by the seed budget (top-6 singles always seeded; pairs while budget allows); (3) the
least-loss seed placement may fail to place a set whose pieces compete for the same paired
slots as another seeded set — those interactions resolve in the climb, not the seeder. In
practice the relevant-set count per job/level is small (most of the 126 sets are
level-banded and job-restricted); the realistic failure mode is "a marginal 3-piece tier
upgrade missed", never "Lava/Kusha not credited".

**Not credited (by design, v1)**: set bonuses in the greedy `buildSet`/`buildMaxStatSet`
path (`gear\gearoptim.lua:640-673`, `:866-882`) — it is raw-single-stat by design and owns
the Range/Ammo legality logic (`pickRangeAmmo`, `gear\gearoptim.lua:607-638`, tests H9-H14);
routing it through optimizePicks would require porting that legality rule and is deferred
(noted in ADR-0011). `/dl` single-stat prints therefore ignore set bonuses; the command's
doc string says so.

### 7.6 HARD-RULE and existing-test compatibility

- **H1-H8 exact pins survive** (`tests\run_tests.lua:394-458`): `opts.effects` nil ⇒ no
  `setIds`, no bonus term ⇒ H3's `total == 100 * 5 + 2 * 7 + 3 * (5 + 5)`
  (`tests\run_tests.lua:415`) is bit-identical. EMPTY tie preference (H4/H5) and EPS
  semantics are untouched — the bonus lives inside `totalScore()`, not in a tiebreak channel.
- **AE1-AE15 weight-shape safety** (`tests\run_tests.lua:1349-1370`): set bonuses introduce
  **no new weight-table entries** — bonus deltas are scored by the *existing* stat weights
  (an ACC+12 bonus is worth `12 × perUnit(Accuracy)` under the caps). `saveWeights`' rows()
  and `cleanTable` (`gear\gearoptim.lua:916-927`, `:973-982`) see nothing new. The only
  persistence addition is the `assume` section (§8), written/read as its own top-level key
  with legacy tolerance.
- **HARD RULE A1-A17 / AF craft-Sub guards / pin-side Sub guards (Sub offering never
  gated)** (`tests\run_tests.lua:76-99`, `:1374-1402`, `:1816+`): pool augmentation is
  append-only and applies to *optimizer pools*,
  not the Sub picker's offered list; `subFilterAnyMain` (`ui\gearui.lua:809`) and the
  `building=true` path are untouched. The Sub marginal call (`ui\gearui.lua:2169-2183`)
  gains `effects.baseComposition = jointPick` so a grip that completes a set is credited —
  credit added, offering never narrowed.
- **H9-H14 Range/Ammo** (`tests\run_tests.lua:461-502`): the `pickRangeAmmo` path is
  untouched; in the optimizePicks paths a bonus can never *legalize* anything (there is no
  Range/Ammo legality rule there today — a pre-existing gap, out of this feature's blast
  radius, noted in ADR-0011) — and a dedicated test pins that a set bonus never legalizes
  an unfirable pairing in the greedy path (HB10).
- **Signature changes**: `opts.effects` added to `M.optimizePicks`; gearui call sites
  `ui\gearui.lua:2137` (joint) and `:2179` (Sub marginal) pass it; `buildBestSet`
  (`gear\gearoptim.lua:835`) passes it when configured. Prerequisite plumbing fixed en
  route: the joint call's augment gap (§6, the `candidateStats` seam).

### 7.7 New tests the algorithm requires (headless)

- **HB1 (numeric objective pin, H3-style)**: `W = {Accuracy={perUnit=3}}`; Ring1/Ring2
  pools each contain a set piece with `Accuracy=2`, setIds→S where
  `S = {min=2, max=2, tiers={[2]={Accuracy=12}}}` ⇒ `total == 3*(2+2+12) == 48`. Pins the
  objective numerically.
- **HB2 (pair discovery)**: same set pieces but `Accuracy=0` each, a rival non-set ring
  `Accuracy=5` in each pool ⇒ the unseeded climb picks rivals (3*10=30); the seeded restart
  must return the set pair (3*12=36).
- **HB3 (EMPTY tie survives)**: bonus exactly offsets ⇒ EMPTY still preferred.
- **HB4 (conflict beats set)**: one owned copy, same-Id pieces offered in Ring1+Ring2 with
  the copies-aware conflict ⇒ count stays 1, no bonus, one slot filled (H6 analog). Variant
  **HB4b**: two owned copies (conflict allows both) ⇒ count reaches 2, bonus credited —
  the verified per-slot counting (§7.2).
- **HB5 (seed eviction/repair + monotone acceptance)**: seed a set whose bonus is dominated
  by two independents ⇒ final result == the baseline answer, total unchanged.
- **HB6 (cap sharing)**: bonus Haste above cap contributes only up to the cap ⇒ a
  cap-redundant set stays home (H5 analog).
- **HB7 (no-effects regression)**: the H1-H8 fixtures rerun through the new code with
  `opts.effects=nil` — totals bit-identical.
- **HB8 (tiered marginal)** (graft: B): 5-piece tiered set, 3 pieces picked ⇒ tiers[3] is
  credited (not tiers[5]); the 4th piece enters only when `tiers[4]−tiers[3]` pays its slot
  cost against the incumbent.
- **HB9 (baseComposition partner)** (graft: B): a set piece in `opts.effects.
  baseComposition` makes a lone pool candidate of the same set worth the bonus — the Sub
  marginal case.
- **HB10 (bonus never legalizes Range/Ammo)** (graft: B): H11/H12 analog through
  `buildMaxStatSet` — an unfirable pairing stays illegal regardless of any set data.
- **A-extension**: bonus-aware Auto-build still offers every shield/grip/1H in the Sub
  picker (extend the A/AP3 vocabulary; the view-only-filter precedent at
  `tests\run_tests.lua:2640-2647`), plus an append-only assertion on pool augmentation
  (input pool ⊆ output pool).
- **AE-extension**: `gearweights.lua` round-trip with an `assume` section; a legacy file
  without it loads clean.

---

## 8. Latent context model for weighting

Scoring must be **deterministic and stable**: a build result must not change because it
started raining mid-click. Therefore two ctx objects, never shared (built by `condsource`,
§5.2):

- **Display ctx** (worn totals, hover): live-read volatile conditions (HP%, TP; weather/day
  when the `__env` mirror exists), ~1s-throttled, UNKNOWN on failed reads (ADR-0007).
- **Scoring ctx** (optimizer, planned totals, candidate sorts): volatile conditions come
  from a **policy**, frozen per run.

Per condition class, a three-valued scoring policy — `ALWAYS` / `NEVER` / `ASSUME(default)`:

| Condition | v1 scoring policy | Rationale |
|---|---|---|
| SET count, EQUIPPED_IN_SLOT | ALWAYS (composition-derived) | The plan *is* the truth |
| JOB_LEVEL, SUBJOB | ALWAYS (plan-known) | Deterministic for the character/plan |
| DURING_WS | ASSUME, default **derived**: TRUE when the set being weighed is bound to a Weaponskill trigger | Trigger purpose is machine-readable in the triggers model |
| TP_OVER(p) | ASSUME, derived: TRUE in WS-trigger contexts for any p a WS-ready player satisfies; else default FALSE | Same derivation (a WS requires full TP; verify the server's TP unit against item 11312 before pinning the exact threshold rule) |
| HP_UNDER/OVER_% | ASSUME, default FALSE | Building for low-HP latents is a deliberate choice, not a default |
| WEAPON_DRAWN | ASSUME, default TRUE for engaged/WS/melee-idle contexts, FALSE for casting contexts | Trigger-implied |
| WEATHER_ELEMENT, TIME_OF_DAY | ASSUME, default FALSE (v2) | No stable truth at plan time |
| STATUS/FOOD/PET/DYNAMIS | ASSUME, default FALSE (v2) | Niche; opt-in |
| NATION_CONTROL, WEAPON_BROKEN | NEVER (not evaluated) | No truth source |

**Derived-first, explicit-later** (the history lesson: two toggle systems built and deleted,
`docs/history.md:103-105`): v1 ships ONLY the derived defaults — no new UI. The explicit
assumption affordance (e.g. "assume Fire weather" for a fire-weather nuking set) lands with
v2 latents as a small "Assume" row section in the existing per-set weights editor
(`wui.editor()`, `ui\weightsui.lua:75+`) — per-set assumptions ride the per-set weights
binding (`M.bindSetWeights`, `gear\gearoptim.lua:407-427`) and persist as a distinct
top-level `assume = { WEATHER_ELEMENT = 8, ... }` section in `<profile>\dlac\gearweights.lua`,
explicitly read/written by `saveWeights`/`loadWeights` (their rows()/cleanTable already
silently drop non-`{perUnit=}` entries, so the new section must be handled by name — the
AE-extension test pins the round-trip). The ADR-0012 argument (graft: B): this is
**optimizer configuration riding an existing config surface**, not the deleted
automation-toggle class. **Pre-approved fallback** (graft: C, recorded in ADR-0012): if
Henrik rejects even per-set Assume rows, scoring falls back to structural + derived-only
conditions permanently — the design degrades to that cleanly because policies are data.

Whatever the policy resolves, **display always distinguishes**: an assumed-active latent
renders in totals with an "assumed" marker in the panel caption, so a scored number is never
mistaken for an unconditional one. All user-facing assumption labels go through Henrik
(the stat-naming rule).

---

## 9. Phasing — shippable increments

Each phase is independently revertable and leaves all prior tests green; P1/P2 ship user
value before any optimizer risk is taken. The optional `__env` mirror (§5.4) is
order-independent and can slot after P1 if wanted.

**P1 — Set bonuses visible (data + evaluator + totals/hover).**
Generators (`gen_gearsets.py`, the `gen_levelscaling.py` latent router, `modmap.py`
extraction), `data\gearsets.lua` + `data\latentstats.lua` committed (levelscaling.lua
byte-identical, asserted), `gear\geareffects.lua` pure core with set evaluation + latent
data loaded but only plan-known predicates registered; `wornSetTotals`/`workingSetTotals` →
`comboStats`; hover set-bonus attribution; the P1 honesty caption.
*Acceptance*: headless — data pins ([70] exact, 126/39/87 counts, zero latent-50/51 rows in
latentstats) + evaluator tier tests green; in-game — worn Lava's + Kusha's shows
ATT+6/ACC+12/DEF+6 in worn totals matching `/checkparam` de-equip deltas, **and one TIERED
set (Iron Ram) field-verified at 2 and 3 pieces** — the
`modData[wornCount - minEquipped + 2]` translation is the load-bearing parse (graft: B);
a planned set with both rings shows the bonus in Set totals.

**P2 — Latents in display, active-vs-conditional presentation.**
`effStats` → `geareffects.itemStats`; predicate registry v1 (TP_OVER, HP_%, SUBJOB,
EQUIPPED_IN_SLOT, DURING_WS-as-ctx); `feature\condsource.lua` with throttled live reads +
epoch; conditional rows in tooltip + bracketed panel column with `why` codes; gearfmt memo
key grows the epoch; triggersui call sites → plan-known ctx; the P2 honesty caption.
*Acceptance*: headless predicate truth-table tests incl. exact boundaries; item 11312 hover
shows `~ STR +5 (…)` conditional at low TP and active in worn totals above the threshold
(field check pins the TP unit); unknown-condition rows render "known, not yet evaluated";
`ctx=nil` ⇒ everything volatile conditional with `why='not-ready'`; no stale summaries after
HP swings (epoch test).

**P3 — Optimizer credits sets (the true objective).**
`opts.effects` in `optimizePicks` (incremental counts, tierVec fold under caps), append-only
pool augmentation, converged-baseline seeded restarts with hard caps and monotone
acceptance, `baseComposition` on the Sub marginal call, the `candidateStats` seam (fixing
the `ui\gearui.lua:2133` augment gap), `workingWeightedScore` unified onto the combo
objective; P1's honesty caption removed.
*Acceptance*: HB1-HB10 + A/AE extensions green; H1-H14, AE1-15, A1-A17, AF/AL untouched and
green; field — Auto-build with ACC-weighted config and both Lava/Kusha owned picks both
rings over a single higher-ACC ring when the bonus wins arithmetically (and not when it
doesn't). Optional: a two-owned-copies `/checkparam` as belt-and-braces confirmation of the
source-verified counts-twice rule (§7.2) — nothing blocks on it.

**P4 — Latent context in weighting.**
Trigger-derived assumptions (WS/engaged/casting), scoring-vs-display ctx split enforced,
per-set `assume` persistence + the weightsui "Assume" section (labels via Henrik; explicit
rows are also the fallback if derived assumptions prove too magical); P2's honesty caption
removed.
*Acceptance*: a WS-trigger set build credits TP_OVER/DURING_WS latents, an idle set build
doesn't (headless: same pools, different ctx, different picks pinned); assume round-trip
test; legacy gearweights.lua loads clean.

**P5 (optional) — Broader conditions + the `__env` engine mirror.**
Buff/food/pet/dynamis predicates; `__env` in modestate.lua (the one seeded-file touch ⇒
`dispatch.M.VERSION` bump + reload-order note).
*Acceptance*: weather latents show live-true in worn totals with the mirror present, degrade
to "conditional" without it.

---

## 10. Test plan (headless — the `lua tests\run_tests.lua` loop)

New sections wrapped `(function() ... end)()` (run_tests.lua has hit the 200-local cap
itself — `docs\HANDOFF.md:287-291`); generated data loaded via the established
`package.loaded['dlac\\data\\gearsets'] = dofile('data/gearsets.lua')` pattern
(`tests\run_tests.lua:559-560` precedent). Lua 5.1/5.4 intersection throughout (tests run
5.4, runtime is LuaJIT).

1. **Data pins** (against the shipped files, the smoke_ui S21 style,
   `tests\smoke_ui.lua:231`): gearsets [70] exact incl. `max`; 126 sets; every tier key in
   `[min, max]`; latentstats has zero latent-50/51 rows; spot rows 10975/11312/11355;
   `UNKNOWN_*` conditions, if any, carry no registered predicate.
2. **Evaluator unit**: tier lookup semantics (flat set at counts 1/2/3; tiered [71]-shape at
   2/3/4/5; clamp above `max`; nil below `min`); per-slot counting (two copies of one piece
   count TWICE — the verified server semantics, §7.2, pinned as the shipped default of the
   one-line switch); the level gate (a piece with ReqLvl above ctx.level does not count —
   the sync scenario); an alternate-piece set ([43]-shape: any 2 of 9 activates, weapon+
   weapon included); zero-copy passthrough for effect-free items; predicate truth at the exact param boundary (e.g. `TP_OVER(p)` at
   `p-1` vs `p`); UNKNOWN condition ⇒ inactive + listed in cond output with
   `why='not-evaluated'`; `ctx=nil` ⇒ `why='not-ready'` for every volatile row (the
   ADR-0007 login behavior, pinned).
3. **Fold**: comboStats == Σ itemStats + active tiers (property test over random
   compositions); itemStats defers level scaling to levelstats byte-identically (regression
   against the pinned lscale tests, `tests\run_tests.lua:553-568`).
4. **Optimizer**: HB1-HB10 (§7.7) + the entire H section rerun through the effects-enabled
   code path with `effects=nil`.
5. **HARD-RULE extensions**: Sub offering unchanged under effects (A-vocabulary); pool
   augmentation append-only assertion.
6. **Persistence**: gearweights `assume` round-trip + legacy tolerance (AE style).
7. **smoke_ui**: the services contract updated for any new `host.provide` keys
   (`tests\smoke_ui.lua:173`); a smoke that renderStatsPanel accepts the optional cond table.

---

## 11. Documentation plan

- **`docs\design\conditional-effects.md`** — this document. `docs\design\latent-rings.md`
  carries a status pointer here (research stands; scope expanded; optimizer call reversed).
- **ADR-0011 — "Optimizer credits set bonuses via the true combination objective
  (incremental counts + converged-baseline set-seeded restarts)"**: records the reversal of
  the latent-rings out-of-scope call; the exact/approximate boundary (§7.5); the monotone
  acceptance guarantee (§7.3); the greedy-path exclusion; the pre-existing Range/Ammo gap in
  optimizePicks noted-not-fixed; and the rejected alternatives verbatim (graft: B) —
  *meta-candidates spanning slots* rejected because the conflict fn can veto pairs but
  cannot REQUIRE them, and merging paired labels makes pool size a product (Ring1×Ring2 =
  400 at the top-20 cap); *per-item pseudo-stat thresholds* rejected because the weight
  shape (`perUnit`/`cap`) cannot express piece-count tiers.
- **ADR-0012 — "Scoring ctx is policy-frozen; display ctx is live"** (§8): the stability
  ruling that prevents weather-flap rebuilds; derived-first/explicit-later with the history
  citation; the Assume-rows-are-config argument; the pre-approved derived-only fallback.
- **CONTEXT.md**: the §2 vocabulary table, in the existing controlled-vocabulary style.
- **docs\HANDOFF.md**: one paragraph + pointer; new hard-rule candidates: "conditional
  stats never enter flat stats tables while inactive" and "scoring ctx never reads live
  volatile state".
- **tools\README.md**: gen_gearsets.py + extended gen_levelscaling.py + modmap.py
  regeneration steps, sanity pins, the byte-identical levelscaling assert, the
  private-submodule fail-soft note.
- **User guide (`docs\guide.html`)**: a "Conditional stats & set bonuses" section — how
  bracketed/dim values read, what "assumed" means, what the optimizer does and doesn't
  credit per phase (the honesty captions verbatim). All new user-visible labels (condition
  names, panel captions) sign-off by Henrik row-by-row.
- **docs\server-questions.md**: only if the P1 field check shows a tier discrepancy, add
  "confirm gear_sets applier tier semantics = value-at-count replacement (applier
  gear_sets.lua:2498-2506)". The duplicate-counting question the draft wanted parked here is
  **answered from source** (counts twice — §7.2, Appendix C); no entry needed.
- **MEMORY.md**: update the latent-set-effects entry when P1 lands (scope decision resolved:
  both mechanics, optimizer in).

---

## 12. Risks & dead-end awareness

| Risk | Mitigation / dead-end cited |
|---|---|
| Re-proposing runtime fetching | Never: generator-in-tools, data ships (rejected twice — `docs/history.md:48-49`, `:194-197`). Complied with by construction. |
| Toggle proliferation | Both prior toggle systems were built then deleted (`docs/history.md:103-105`). v1 = derived assumptions only; explicit assumptions arrive later inside the existing per-set weights editor, not as new global UI; the derived-only fallback is pre-approved. |
| Wrong altitude (build-time set handling) | The build-time-stripping dead end (ADR 0006 addendum) says whole-set properties handled at build time are wrong under overlay semantics — this design evaluates at the resolved-composition level (totals, objective); the engine/game applies reality. |
| Latent 50/51/52 confusion regressing | The generator's own bug history (`gen_levelscaling.py:12-15`) + the no-weather-as-below assert (`:91-92`) + the new zero-50/51-in-latentstats pin + the byte-identical levelscaling assert. |
| H3-style exact-pin breakage | The bonus term is structurally zero when `opts.effects` is nil / candidates carry no setIds; HB7 pins it. |
| Hill climb can't find pairs | The known hole; fixed at the same seam via append-only pool augmentation + converged-baseline seeded restarts; HB2 pins discovery, HB5 pins repair-by-eviction; residual approximation stated in ADR-0011. |
| Degenerate wardrobes blowing the run budget | Hard deterministic caps (6 singles / 12 total seeds), value-ordered so the cap drops the least valuable sets. |
| Stat scale traps (×100 DT-family, TP_BONUS literal) | `tools\modmap.py` — the scale rules exist in exactly one place, imported by all SQL generators (`docs/history.md:45-46`, `:205-209`). |
| Mod-enum leakage | gearsets/latentstats ship stat NAMES only (the statdefs rule, `data\statdefs.lua:10-11`); latent condition names are not scrape-sensitive (public-SQL precedent: spells/abilities). |
| Server-data trust | Validate like the catalog-Slot lesson: P1 acceptance includes live `/checkparam` deltas on [70] AND a tiered set at two counts; duplicate-copy counting treated as unverified; unknown/custom sets fail soft (`tools\gen_craftdb.py:25-27`). |
| Stale conditional display | gearfmt memo keyed (level, epoch); candCache invalidated only on scoring-relevant changes; triggersui manifests deliberately plan-known-only (snapshots by design). |
| Not-ready live reads at login | ADR-0007: UNKNOWN this cycle with `why='not-ready'`, re-read on throttle, no latching; UNKNOWN never adds stats. |
| Shared-table mutation | comboStats/itemStats are copy-on-write like `levelstats.apply`; never write into `rec.Stats` (`enrichGearFromCatalog` already mutates those in place, `ui\gearui.lua:266-310`). |
| 200-local cap | New logic lives in new modules (geareffects, condsource) + uihost registration, not gearui locals; test sections use the IIFE pattern; data files cost zero locals. |
| Two-state drift | Everything addon-state; only the optional `__env` mirror touches a seeded file, and it carries the mandatory `dispatch.M.VERSION` bump + reload-order note (HANDOFF hard rule 4). |
| Per-frame cost creep | Set bonuses never enter per-item sort comparators or keystroke-invalidated paths; the whole-combination evaluator runs on button-press (build) and ~1s-throttled (totals) cadences only. |

---

## 13. Decisions — RESOLVED 2026-07-17

These six were flagged as the maintainer's calls; Henrik delegated all six to the
maintainer-recommendation defaults ("Go with your recommendations", 2026-07-17). He retains
in-game veto on anything user-visible — every one of these is cheap to reverse.

1. **Condition label wording** (`CONDLABELS`): implementer drafts labels following the
   stat-naming rules ("Chance" never readable as a reduction; "Cast Time-"); Henrik vetoes
   in-game rather than pre-approving row-by-row. Starter table (v1/v2 core; remaining v2
   labels drafted in the same style):

   | Condition | Label |
   |---|---|
   | SET (active) | panel caption `Set: Lava's + Kusha's (2/2)`; hover `~ ACC +12 (set: with Kusha's Ring)` |
   | WEATHER_ELEMENT(e) | `<Element> weather` ("Fire weather", "Dark weather") |
   | TIME_OF_DAY(0/1/2) | "Daytime" / "Nighttime" / "Dusk-dawn" |
   | Days-of-week | the day name ("Firesday", …) |
   | HP_UNDER/OVER_PERCENT(p) | `HP <= p%` / `HP > p%` |
   | TP_OVER/TP_UNDER(t) | `TP > t` / `TP < t` (display unit pinned by the P2 item-11312 field check) |
   | DURING_WS | "during WS" |
   | SUBJOB(j) | `/<JOB>` ("/NIN") |
   | EQUIPPED_IN_SLOT(s) | `in <slot> slot` ("in sub slot") |
   | PET_ID family | grouped: `with <family> pet` ("with a water avatar") |
   | FOOD_ACTIVE family | grouped: `with <food>` |
   | Markers | "assumed" (caption), "known, not yet evaluated", "waiting for game state" |

2. **Conditional-value presentation**: ship as proposed — dimmed `~` rows in hover,
   bracketed dim `[+12]` suffix in totals panels, set-attribution caption.
3. **P4 explicit "Assume" rows**: SHIP them in P4 (derived defaults first within the phase,
   explicit rows in the same phase). Rationale: "assume Fire weather" for a weather-nuking
   set is inexpressible any other way, and the rows ride the existing per-set weights
   editor — config on an existing surface, not the deleted toggle class (ADR-0012).
4. **`__env` engine mirror**: stays at P5 (the doc's default). It is the only seeded-file
   touch, display-only, zero optimizer impact — keep the M.VERSION risk isolated at the
   end; pull forward only if live weather display is missed in practice after P2.
5. **Greedy `/dl` single-stat builds stay set-blind**, with the honest doc-string note.
   Routing `buildMaxStatSet` through optimizePicks (porting the Range/Ammo legality rule)
   is deferred indefinitely; revisit only on real demand. Recorded in ADR-0011.
6. **Two-copies field test**: skipped as a gate. The server source settles the rule (two
   copies count twice, §7.2/Appendix C) and that default ships; the `/checkparam`
   confirmation is parked as optional-whenever-convenient in the P3 acceptance note.

---

## Appendix A — source anchors

**Server repo** (`CatsAndBoats/catseyexi`, branch `base`; raw =
`raw.githubusercontent.com/CatsAndBoats/catseyexi/base/…`):

- `scripts/globals/gear_sets.lua` — all 126 set bonuses (applier ~2498-2510). `[70]` =
  Lava/Kusha; `[71]` = Iron Ram Haubert (the tiered shape).
- `sql/item_latents.sql` — every conditional latent row; already downloaded by
  `tools\gen_levelscaling.py`.
- `scripts/enum/{latent,mod,item}.lua` — id → name resolution.

Sparse fetch (from `docs\design\latent-rings.md:130-133`):

```
git clone --depth 1 --filter=blob:none --sparse <repo>
git sparse-checkout set --no-cone scripts/globals/gear_sets.lua sql/item_latents.sql \
    scripts/enum/mod.lua scripts/enum/item.lua scripts/enum/latent.lua
```

**dlac anchors relied on above** (verified against the working tree, 2026-07-17):
`gear\gearoptim.lua:694-786` (optimizePicks; totalScore :742-754; vecs :715-728; conflicts
:755-764; probe loop :766-784), `:817-824` (top-20 prune), `:835` (buildBestSet's
optimizePicks call), `:607-638`/`:640-673`/`:866-882` (pickRangeAmmo/buildSet/
buildMaxStatSet), `:454-477` (score), `:407-427` (bindSetWeights), `:912-1016` (persistence)
· `ui\gearui.lua:86` (effStats), `:596-622`/`:1979-2002` (totals), `:1701` +
`:1662-1692` (renderStatsPanel + shadow registries), `:877-887` (tooltip), `:2099+`
(autoBuild; :2133 joint stats, :2137/:2179 optimizePicks call sites, :2142-2149 owned-copy
conflict, :2169-2183 Sub marginal), `:3144` (host.provide), `:724` (fmt.configure),
`:488-489` (candCache), `:266-310` (enrichGearFromCatalog), `:1010-1016` (modestate mirror
read) · `data\levelstats.lua:35-60` (the delegated resolver) · `data\levelscaling.lua`
(8 items / 114 rows shipped) · `gear\gearfmt.lua:97-123` (memo), `:59` (STAT_PRIORITY) ·
`ui\weightsui.lua:75+`/`:127-139` (editor / live-apply) · `ui\equippedui.lua:155-156`/`:287`
· `ui\triggersui.lua:694-695`/`:764-765` · `tools\gen_levelscaling.py:29,32-37,41-57,63,
83-92` (extension points; the 50/51 gate and the latent-52 bug note) · `dispatch.lua:2092`
(saveModeState), `:256` (modeActive external-modes precedent), `:312` (dayweatherbonus
matcher) · `dlac.lua:110-135` (the addon-state gData shim; :129-130 weather/day stubs) ·
`tests\run_tests.lua:394-458` (H pins; :415 H3), `:461-502` (H9-H14), `:1349-1370` (AE),
`:76-99` (HARD RULE A), `:553-568` (lscale pins), `:559-560` (data-load pattern) ·
`tests\smoke_ui.lua:173` (services contract), `:231` (S21 data-pin style) ·
`docs\design\latent-rings.md` (the research base).

## Appendix B — judge grafts: merged and rejected

**Merged** (where each landed): converged-baseline seeding + least-loss incumbent placement
+ monotone acceptance (§7.3); hard deterministic seed caps (§7.3, §7.4); meta-candidate and
pseudo-stat rejection rationale verbatim (§11, ADR-0011); byte-identical levelscaling assert
+ corrected row arithmetic and the 50/51-not-52 boundary (§3.2, §4.A); tiered-marginal,
baseComposition-partner and Range/Ammo-non-legalization tests (HB8-HB10, §7.7); flat AND
tiered `/checkparam` field verification (§9 P1); duplicate-copy counting as unverified
server semantics with a one-line switch + server-questions entry (§7.2, §11); per-phase UI
honesty labels (§6, §9); `feature\condsource.lua` as the impure ctx module (§5.2);
`UNKNOWN_<id>` emission with a report count (§3.2); boundary + ctx=nil predicate tests
(§10.2); mandatory `tools\modmap.py` (§4.C); `max` emitted in gearsets data (§3.1); the
`__env` mirror as an isolated, order-independent optional phase (§5.4, §9); the explicit
weightsui "Assume" row as P4 surface and fallback, with the it's-config-not-a-toggle
argument recorded (§8, ADR-0012); the derived-only degradation path (§8); the single
`candidateStats` enrichment seam (§6).

**Rejected (with reasons):**

1. *Seed iteration in ascending-setId order* (B's ordering): deterministic but value-blind —
   under a hard cap it would drop sets by id accident rather than by worth. Kept instead:
   descending projected best-tier value with ascending setId as the tiebreak — equally
   deterministic, and the cap provably drops the least valuable sets.
2. *Hard cap of exactly 4 restarts* (B's number): raised to 6 singles / 12 total. Restarts
   now start from the converged baseline (B's own graft), so the marginal cost per seed is
   1–3 passes, not a full climb — at that price 4 is needlessly tight, and the ceiling
   remains hard and deterministic.
3. *The draft's "~1,858 rows" latentstats estimate and "latents 50/51/52" exclusion set*:
   superseded by ground truth — the shipped generator gates on 50/51 (`gen_levelscaling.py:
   56`), latent 52 is WEATHER_ELEMENT (the documented old bug), and the shipped
   levelscaling.lua is 8 items / 114 rows, putting latentstats at ~1,849 rows, pinned as a
   range. (This also retires the draft's claim that levelscaling "ships byte-identical to
   today" as an assumption — it is now a generator assert.)
4. *The draft's asserted-as-fact "duplicate copies count once, matching the server"*:
   downgraded to an explicit default over unverified semantics, per the field-verify graft.
   **Subsequently settled** by the direct server-source read (Appendix C): the applier
   counts per slot with no uniqueness check — duplicates count **twice** — so the shipped
   default flipped accordingly and the switch remains for safety.

## Appendix C — direct server-source verification (2026-07-17)

After the design round, a maintainer-authorized pass read the server code itself (sparse
clone of `CatsAndBoats/catseyexi@base`: `scripts/globals/gear_sets.lua`,
`sql/item_latents.sql`, `scripts/enum/latent.lua`, `src/map/latent_effect_container.cpp`;
the fresh SQL is cached at `tools\api_cache\item_latents.sql`). Every server-behavior claim
in §3, §5.3 and §7 traces to one of these findings:

**The set-bonus applier** (`gear_sets.lua:2473-2510`, called by core on every
equip/unequip after `clearGearSetMods()`):

- Counting is a walk over equipment slots `0..xi.MAX_SLOTID` — per SLOT, **no uniqueness
  check** (duplicates count twice), including weapon/ranged/ammo slots.
- **Level gate** (:2488): a piece counts only while `player:getMainLvl() >= item ReqLvl` —
  level sync strips set bonuses server-side; dlac's evaluator mirrors this with ctx.level.
- Tier pick (:2499-2506): `min` defaults to 2, `max` defaults to *uncapped*
  (`xi.MAX_SLOTID + 1`); `modData[math.min(setCount, max) - min + 2]`; values are totals
  at that count (header :9-11). An uncapped set worn beyond its tier length indexes nil —
  the generator's derived `max` (§3.1) closes that hole on our side.
- `itemToSetId` (:2451-2467) maps itemId → **list** of setIds (multi-set membership).
- Shape census over all 126 sets: 87 tiered / 39 flat; 70× (min2, uncapped),
  4× (min2, max2), 33× (min2, max5), 19× (min5); **37 sets have more pieces than their
  cap** (alternates) — e.g. `[43]` Paramount: 9 items (1 earring + 8 weapons), min2/max2.

**The latents table** (`item_latents.sql`): 1,962 active INSERT rows over 854 distinct
items; **128 commented-out rows** are server-unimplemented (one, item 17275 WEAPON_BROKEN,
is fully numeric and would match an unanchored regex — §3.2/§4.A); 173 (item, stat)
OR-families (same condition class, different params — pets, food tiers). Full distribution:
STATUS_EFFECT_ACTIVE 280, NATION_CONTROL 184, PET_ID 149, FOOD_ACTIVE 119,
JOB_LEVEL_ABOVE 105, IN_DYNAMIS 79, SUBJOB 72, WEAPON_BROKEN 70, TIME_OF_DAY 70,
PARTY_MEMBERS_IN_ZONE 68, HP_UNDER_PERCENT 68, WEATHER_ELEMENT 57, TP_UNDER 55,
MOON_PHASE 53, IN_ASSAULT 51, WEAPON_DRAWN_MP_OVER 49, HP_UNDER_TP_UNDER_100 47,
days-of-week ~112 across 8 ids, IN_GARRISON 33, ZONE 33, AVATAR_IN_PARTY 25,
WEAPON_DRAWN 20, VS_ECOSYSTEM 19, JOB_IN_PARTY 19, PARTY_MEMBERS 13, WEAPON_SHEATHED 13,
EQUIPPED_IN_SLOT 12, TP_OVER 11, HP_OVER_PERCENT 11, JOB_LEVEL_BELOW 9, SYNTH_TRAINEE 9,
JOB_MULTIPLE 8, NO_FOOD_ACTIVE 7, MP_UNDER_PERCENT 5, NATION_CITIZEN 4,
ZONE_HOME_NATION 3, MAINJOB 2, ELEVEN_ROLL_ACTIVE 2, DURING_WS 1, WEATHER_CONDITION 1,
IN_ADOULIN 1, MP_UNDER 1, MP_OVER 1, JOB_MULTIPLE_AT_NIGHT 1.

**Condition semantics** (`latent_effect_container.cpp`):

- `WEATHER_ELEMENT` (:1219-1221): the *element* of current weather == param — fires on
  single AND double weather of that element (`GetWeatherElement(GetWeather(...))`).
- `WEATHER_CONDITION` (:1216-1218): exact weather id (can require double weather); 1 row.
- `TIME_OF_DAY` (:986-1000): 0 = 06:00-18:00, 1 = 18:00-06:00, 2 = 17:00-07:00 Vana time.
- `TP_UNDER` (:809-811): plain `tp < param` in this fork (the enum comment's "and during
  WS" is not implemented as such); `TP_OVER` = `tp > param`.
- `DURING_WS` (:190-197, :1313-1315): a boolean flag passed by the WS code.
- `EQUIPPED_IN_SLOT` (:1310-1312): the latent's own slot == param — plan-evaluable.
- `NATION_CONTROL` (:1222-1237): region ownership AND an active signet/sanction/sigil —
  confirming the "not evaluated" classification.
- `HP_UNDER_PERCENT` is `<=`; `HP_OVER_PERCENT` is `>` (enum comments, latent.lua:6-7).

**The latent-50/51/52 boundary**: 50 = JOB_LEVEL_BELOW, 51 = JOB_LEVEL_ABOVE,
52 = WEATHER_ELEMENT (`scripts/enum/latent.lua:55-57`). The historical
gen_levelscaling.py misread of 52 was found and fixed the same day (commit `44212a0`:
shipped data regenerated from 60+ contaminated items to the true 8 items / 114 rows).
