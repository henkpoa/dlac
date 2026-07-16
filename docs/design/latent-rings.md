# Conditional item effects — latents & set bonuses (research → plan)

> Status: **RESEARCH, corrected.** An earlier version of this doc concluded these effects were
> "not scrapeable, must be hand-authored." **That was wrong** — the effects are *data* in the
> public CatsAndBoats/catseyexi repo, so they're **generatable**, the same way the catalog and
> level-scaling already are. This is the corrected plan.
> **2026-07-17:** the research below stands; the *plan* section is superseded by
> `docs/design/conditional-effects.md` (scope expanded to sets + latents + totals, and the
> "optimizer out of scope" call is reversed — set bonuses now enter the weight objective).

## The ask (recap)

Items whose effect only applies **under a condition** (weather / day / HP%) or **when a set is
worn** (Lava's + Kusha's, Salvage sets) should feed the **stat page, weights, and hover** — right
now dlac shows only their unconditional stats.

## What we actually learned

**It's two related mechanics, and each has ONE machine-readable home in the server repo:**

1. **Set bonuses → `scripts/globals/gear_sets.lua`** — one structured Lua table. Each set = a
   piece-list + per-piece-count mod tiers, applied when `wornCount >= minEquipped`.
2. **Conditional latents (weather/day/HP/TP/…) → `sql/item_latents.sql`** — SQL rows
   `(itemId, modId, modValue, latentId, latentParam)`. **dlac already downloads this file**
   (`tools/gen_levelscaling.py`) — it just only extracts the *level* latents (50/51/52) today.

This LSB fork has **no `scripts/globals/items/` directory at all** — nothing is buried in opaque
per-item scripts. It is *all* data files, so a generator can read it directly.

### Lava's / Kusha's, specifically — it's a SET, not a latent (field-confirmed)

Entry `[70]` of `gear_sets.lua`: a **2-piece set** of exactly Lava's Ring (15850) + Kusha's Ring
(15851). Both worn → **Attack +6, Accuracy +12, Defense +6** (the DEF is undocumented even in the
server's own comment). Plus each ring's static per-element Magic Evasion (already in the catalog).
dlac shows the MEVA but **misses the set bonus** — the maintainer confirmed it live (`/checkparam`:
de-equip one ring → lose ATT *and* ACC). So the "missing latent" was really a **missing set bonus**.

### The condition vocabulary is handed to us

`scripts/enum/latent.lua` defines ~65 conditions with their numeric ids — `WEATHER_ELEMENT`,
`FIRESDAY`…`DARKSDAY`, `HP_UNDER_PERCENT`, `TP_OVER`, `DURING_WS`, `EQUIPPED_IN_SLOT`,
`WEAPON_DRAWN`, … — which is exactly the `when` vocabulary our evaluator must speak. (Note: there is
**no** `ITEMSET` latent condition — set bonuses are their own system, `gear_sets.lua`, not latents.)

## The data model

A conditional effect is **`{ effect = <mod deltas>, active = <predicate over game state> }`**, and a
set bonus is the same shape with two wrinkles:

- **`active`** for a set = "`N` pieces of set `S` are worn, `N >= minEquipped`."
- **the effect can be TIERED by piece count.** Two real shapes seen in `gear_sets.lua`:
  - **Flat** (Lava/Kusha `[70]`): one value, applied at `>= minEquipped`.
  - **Tiered** (Iron Ram Haubert `[71]`): `{ FIRE_MEVA, 5, 10, 15, 30 }` = values at 2 / 3 / 4 / 5
    pieces (`modData[wornCount - minEquipped + 2]`).

Unified: an effect's **"level"** is a computed number (piece count for sets; `0/1` for a boolean
condition), and a **tier table** maps that level → mod deltas. One evaluator covers both.

## The build — three pieces

1. **Generator (`tools/`, maintainer's scrape domain — ships its output with the addon like the
   catalog):**
   - Parse `gear_sets.lua` → `data/gearsets.lua`: `{ setId, pieceIds[], minEquipped, maxEquipped,
     modTiers[] }`, resolving `xi.item.*` / `xi.mod.*` via the enums.
   - Extend the latent generator to pull **all** of `item_latents.sql` (not just level), mapping
     `latentId` via `scripts/enum/latent.lua` → `data/latentstats.lua`: `{ itemId, mod, value,
     condition, param }`.
2. **Runtime evaluator (addon):**
   - **Sets:** count worn pieces of each set (from the worn/planned set), apply the matching tier.
   - **Latents:** map each condition id → a live check against `gData` (weather/day/HP%/TP/
     worn-slot/…), returning the active mod deltas.
3. **Fold at the one resolver** (`effStats` / `levelstats.effective`): the **stat page and hover**
   light up immediately; the **weights optimizer is explicitly OUT OF SCOPE for v1** — a set bonus
   is a whole-combination property, not a per-slot stat, so per-slot scoring can't credit it (the
   same cross-slot problem as ring-pairing). We'll note "optimizer ignores set bonuses" honestly.

## Scope (from the generator spike)

A parser was run over the real repo data (`gear_sets.lua` + `item_latents.sql`, resolving the
enums). **It works end-to-end** — it already emits both files' data. What's actually there:

**Set bonuses — `gear_sets.lua`: 126 sets** (39 flat, 87 piece-tiered). Both shapes parse cleanly:
- `[70]` Lava/Kusha → `pieces = {15850, 15851}, min = 2, {ATT +6, ACC +12, DEF +6}` (your rings, exactly).
- `[71]` Iron Ram (5-piece) → each element's MEVA `{5, 10, 15, 30}` at 2/3/4/5 pieces (the tiered shape).

Generated entry shape (proof): `[70] = { pieces = {15850,15851}, min = 2, tiers = { [2] = {[23]=6,[25]=12,[1]=6} } }`.

**Conditional latents — `item_latents.sql`: 1,963 rows across 854 distinct items.** The conditions
that actually appear (top by row count):

| condition | rows | condition | rows |
|---|---|---|---|
| STATUS_EFFECT_ACTIVE | 280 | IN_DYNAMIS | 79 |
| NATION_CONTROL | 184 | SUBJOB | 72 |
| PET_ID | 149 | WEAPON_BROKEN | 71 |
| FOOD_ACTIVE | 119 | TIME_OF_DAY | 70 |
| JOB_LEVEL_ABOVE (level, already done) | 105 | HP_UNDER_PERCENT | 68 |
| — | — | WEATHER_ELEMENT | 57 |

Real rows the generator resolved: `item 10975 → ATT +13 when WEATHER_ELEMENT(8)`;
`11312 → STR +5 when TP_OVER(100)`; `11355 → ENMITY -1 when HP_UNDER_PERCENT(75)`.

**Read of it:** the *data generation* is a solved problem — the parser already produces both files.
The real cost is the **evaluator's condition coverage**: some conditions are trivial to check live
(set piece-count, `HP_UNDER_PERCENT`, `WEATHER_ELEMENT`, `TIME_OF_DAY`, `TP_OVER`, `WEAPON_DRAWN`)
and some are gnarly or niche (`STATUS_EFFECT_ACTIVE`, `NATION_CONTROL`, `PET_ID`, `IN_DYNAMIS`). So
v1 should cover the high-value handful and mark the rest "known, not yet evaluated" — the data is
already there whenever we light up another condition.

## Open calls for the maintainer

1. **v1 scope — sets, latents, or both?** → **Rec:** **sets first.** Smaller, self-contained, and
   it covers exactly what you hit (Lava/Kusha + Salvage). Conditional latents (weather/day/HP) are a
   clean phase 2 on the same fold.
2. **Optimizer — confirm out-of-scope for v1** (stat page + hover only). → **Rec:** yes; revisit if
   it proves worth the cross-slot complexity.
3. **Active detection — auto vs. a toggle.** Worn-count is *always* knowable (we have the set), so
   set bonuses need no toggle. Weather/day/HP latents read from `gData` — auto, with a graceful
   fallback when a read fails. → **Rec:** auto for sets now; auto-with-fallback for latents in
   phase 2.

## Key source anchors (branch `base`, raw = `raw.githubusercontent.com/CatsAndBoats/catseyexi/base/…`)

- `scripts/globals/gear_sets.lua` — all set bonuses (applier ~2498-2510). Lava/Kusha = `[70]`;
  a tiered example = `[71]` Iron Ram Haubert.
- `sql/item_latents.sql` — every conditional latent (already pulled by `tools/gen_levelscaling.py`).
- `scripts/enum/{latent,mod,item}.lua` — the id → name resolution the generator needs.

## Resuming this in a future session

The research is finished; what remains is a maintainer decision, then the build. To pick it up cold:

- **Data sources** are the three files in the anchors above, in `CatsAndBoats/catseyexi` @ branch
  `base`. Sparse-fetch them:
  `git clone --depth 1 --filter=blob:none --sparse <repo>` then
  `git sparse-checkout set --no-cone scripts/globals/gear_sets.lua sql/item_latents.sql scripts/enum/mod.lua scripts/enum/item.lua scripts/enum/latent.lua`.
- **The spike** (a ~60-line throwaway Python parser) proved both files generate cleanly. Recreate
  it: regex each enum to `id→name`; a line state-machine over `gear_sets.lua` collecting per `[id]`
  its `xi.item.*` pieces / `minEquipped` / `{ xi.mod.*, v… }` mods; a 5-tuple regex
  `(\d+),(\d+),(-?\d+),(\d+),(-?\d+)` over `item_latents.sql`. Verified output: set `[70]` =
  `{15850,15851}, min 2, ATT+6/ACC+12/DEF+6`; 126 sets total; 1,963 latent rows / 854 items.
- **The one open decision (maintainer's): v1 scope.** Recommended = **set bonuses first** — a
  `tools/` generator → `data/gearsets.lua`, an addon worn-count evaluator, and the `effStats` fold
  (fixes Lava/Kusha + Salvage; stat-page + hover only; optimizer explicitly out of scope). Then a
  phase-2 for the trivial latent conditions (weather / HP% / TP / time-of-day). The data for every
  condition is already generatable; the gating cost is per-condition evaluator coverage.
- Once v1 scope is chosen, turn it into a PRD → issues and build. Nothing here is blocked on more
  research — the unknowns (is it scrapeable? what shape? Lava/Kusha specifically?) are all answered.
