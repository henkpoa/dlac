# The Gear Oracle — one door for every gear question

> THE reference for `gear/gearoracle.lua` and the rules around it: what it answers, the
> four boundary rulings and why they were made, the golden gate, the HARD RULE guards,
> the engine twins, and what to do when any of them fires. Companion records: **ADR 0013**
> (the rulings, condensed), **PRD #69** (the commissioning spec), history.md 2026-07-22
> (the build timeline). Shipped complete 2026-07-22 — PRD to done in one day, five PRs
> (#75–#79), agent-built under maintainer review.

## What it is, in one paragraph

The oracle is the **single sanctioned door for gear questions in the addon state**. Any
feature or UI module that wants to know *what is worn, what bags count, what an item is,
whether a job can wear it, or what its effective stats are* asks `gear/gearoracle.lua` —
and nothing else. The interpreters that actually know the answers (`data/levelstats`,
`gear/geareffects`, `feature/augments`, `gear/catalogindex`, `gear/ownedcache`) keep
their homes; the oracle fronts them. CI enforces the door (guards GRD1–5 in
run_tests.lua); a committed golden corpus proves the stat pipeline never drifts.

## Why it exists — the duplication it ended

A documented sweep (2026-07-22, recorded in PRD #69) found the *interpretation* layer
already centralized and correct, but the *fetch* layer duplicated by hand:

| Deduction | Copies found | Where they lived |
|---|---|---|
| Worn-item packed-Index decode | **4** | gearui, augments, dispatch, useitem |
| Equip-eligible bag list `{0,8,10..16}` | **4** | gearimport, augments, dispatch, fishcalc/ownedcache |
| Main-job "can wear" inline fallbacks | 2 (+1 central) | gearoptim, gearui beside dispatch's rule |
| Any-job gate + 22-job list | twins + 3 list copies | dispatch, jobgate, gearui/gearoptim |
| Catalog nested walk | 2 | catalogindex (blessed), gearexport (debt) |
| Stats+augment hand-glue | per ladder | automationsui manifests, gearui scoring |

Every copy was a place where one edit (a new wardrobe, a job-gate nuance) could silently
change what "owned" or "eligible" meant in one module and not another. The oracle deleted
them all; the guards make re-growing one a CI failure.

## The door — API and semantics

All answers are **capability**, never permission (see ruling 2). Names use could-words.

| Question | Call | Semantics that matter |
|---|---|---|
| What's worn in slot N? | `wornItem(slot)` | THE packed-Index decode (high byte = container, low byte = slot). Returns `{id, rec, extra, item}` or nil; hands the id back **raw** (0/65535 included) — interpretation of "empty" belongs to the caller. |
| Which bags count as equippable? | `equipBags()` | Inventory + the 8 Wardrobes. The ONE list. |
| Can my main job wear this? | `canWear(rec, job, level)` | Delegates to the engine rule (`dispatch.canWear`): **main job only — sub never widens** (field-verified on CatsEyeXI), level gated on main level. If the engine module is somehow absent, answers a **conservative false** — never a private re-statement of the rule. (The old inline fallbacks guessed permissively; that state is unreachable in a loaded addon, and false is the safe direction.) |
| Could ANY of my jobs wear this? | `anyJobCanWear(rec, jobLevels)` | The lockstyle gate (server's `canEquipItemOnAnyJob`). Delegates to `gear/jobgate` (which stays the parity-pinned addon twin; FAIL-OPEN on unknown records — the server decides). A missing gate *module* fails open; a nil `jobLevels` short-circuit belongs to the CALLER (the Save-gate lesson). |
| What is this item? | `lookup(idOrName)` | Owned-record + catalog join: owned first, then catalog; **id authoritative, name the fallback** (multi-stage relic names are single-winner traps — see the Iridescence id-pin rule). Enriched flat indexes are injected by the surface that builds them (`setLookupSource`). |
| Effective stats for me, now? | `stats(rec, ctx)` | `levelstats.effective` (level scaling — never value a Tamas at base) **plus the full augment fold**. Note: full map, not MP/Refresh-only — a deliberate, disclosed widening in #79; Henrik's law "augs must always be calculated into the total". |
| A whole composition's stats? | `setStats(comp, ctx)` | Thin delegation to `geareffects.comboStats` — level scaling + augments + server-verified set-bonus tiers. The reference interpreter, untouched. |
| What does this grant my PET? | `petStats(recOrId)` | The pet channel (`data/petmods.lua`, SQL-sourced — the live API never serializes it). Returns `{ PetTypeName -> { statKey -> value } }` or nil. **Deliberately separate from `stats()`**: pet values never fold into master stats (wyvern HP is not your HP), and the golden gate pins `stats()` byte-identical. Display composition stays with the presenter (`gearfmt.petLines`). |
| The pet channel, priced for weights? | `petScoreStats(recOrId)` | The channel FLATTENED under **`Pet:`-namespaced keys** (`{ ['Pet:Haste'] = 6 }`) so the weights system prices it in the same map as master stats **without ever colliding with them** — the never-folded ruling survives pricing by namespace. Per stat the context-free scalar is **All + the BEST named type**: the server grants a pet All plus its own type's mods, and a pet is exactly ONE type, so summing across named types would credit mutually exclusive pets (max is exact whenever one named type carries the stat — the overwhelming case). Consumers: gearui's `candidateStats` seam (every per-item score), the composition score's per-piece fold (setStats itself stays pet-blind — goldens), `gearoptim`'s spelling/negation tables (`pet:haste` types resolve; `Pet:PDT` is negative-good like `PDT`). |
| Which pet stats exist at all? | `petStatKeys()` | Sorted distinct raw stat keys across the pet data — the weights editor's "add stat" menu source (prefix `Pet:` before use as a weight key). `statdefs` derives label/section for the namespace (`Pet:Haste` → "Pet: Haste", section Pet). |
| Owned / available? | ADR 0005 verbatim | Ownership = ALL containers; availability = Inventory + Wardrobes; stored-only renders red. The oracle exposes the predicates; it invents no new semantics. |

**Not the oracle's job:** browsing the catalog (`catalogindex` is a standing central
service — the oracle fronts it only for the identity join), entity scanning (`entwatch`),
ownership counting (`ownedcache`), and *anything involving locks, pins, or claims* (see
ruling 2).

## The four boundary rulings (ADR 0013) — and the why behind each

1. **Facade, not absorb.** The interpreters keep their homes, tests, and field-tuned
   behavior. *Why:* moving thousands of field-verified lines buys adjacency, not
   correctness — pure churn risk. "One place" is about the **door**, not where the
   machinery sits. The interpreters' own suites staying green through the migration was
   itself evidence the facade moved nothing.
2. **Claim-blind, permanently.** The oracle answers "*could* this character use this
   item"; the Claim/Arbiter registry (ADR 0012) answers "*may* this slot change now, and
   who wins". They compose; they never contest. Method names enforce the reading:
   `canWear`, never `canEquip`. *Why (Henrik):* "otherwise they would contest, that
   would only create complexity" — one precedence authority was the entire point of the
   arbiter; a second one wearing an oracle badge would recreate the disease it cured.
3. **Twins, with parity pins.** ADR 0002's two-Lua-state split means the seeded engine
   cannot require addon-folder modules. The engine keeps exactly **three** tiny twins
   inside dispatch.lua — `M.decodeEquipIndex`, `M.AMMO_BAGS`, and the any-job style gate
   (`_lsStyleGate`, twinned by `gear/jobgate`) — each held byte-identical by the
   OR-section parity pins in run_tests.lua, which **fail CI naming the twin** on any
   drift. *Why:* a pinned twin is a *guaranteed* agreement; an unpinned shared file is
   an assumed one.
4. **No sixth seeded engine file.** Rejected explicitly. *Why:* it would join the
   cast-time path (blast radius: a bug breaks equipping, not a panel), demand
   seeding/reload discipline for every edit, and *still* fork internally because the
   catalog is addon-state-only — one filename, two behavior modes, to unify ~30 lines.
   The three pinned twins are the cheaper, safer contract.

## The require discipline (who may load what)

- Feature and UI modules require **the oracle** (and standing services: catalogindex,
  ownedcache, entwatch, gamemode, location...). They never require `levelstats`,
  `geareffects`, or `augments` directly — that is hand-gluing stats, and GRD5 fails CI
  on it. The allowlist that once exempted the pre-migration surfaces is **empty and must
  stay empty**.
- The oracle and the gear pipeline's own internals are the only sanctioned homes for the
  interpreters, raw equipped/inventory reads, the packed-Index arithmetic, the bag list,
  and the 22-job list (plus the engine's three twins).
- Extending gear knowledge = **adding an answer to the oracle**, never building a rival
  door. If the oracle can't answer it, that's a gap in the oracle.

## The golden gate — how Phase 2 was proven, and what it guards now

Phase 2 (migrating the stat-glue: automationsui's MaxMP/HELM/fishing/craft manifest
ladders, gearui's Sets-core scoring, equippedui's worn-augment display) was the risky
half: those ladders were field-tuned through long sagas (MaxMP v76–v94). The rule was
**proven byte-identical, not assumed**:

- `tests/goldenfixtures.lua` — deterministic synthetic BLM Lv74 + curated bag, run
  through the REAL builders. Covers the named traps: level scaling (Tamas 15→29 at 74),
  the augment fold (Hlr. Bliaut +1 = 35+18; Clr. Bliaut +1 Refresh 1+1), a duplicate
  item feeding both ring ladders, one item in multiple ladders, every builder.
- `tests/golden/*.golden` — the committed truth. `.gitattributes` pins them `-text`
  (autocrlf would turn byte-identical into a CRLF lie).
- smoke_ui §12 asserts the builders reproduce them **byte-identically**, naming the
  first differing line on drift.
- The #74 migration routed the same fixtures through `oracle.stats()`/`setStats()` and
  produced the same bytes — on both platforms. Zero accepted diffs.

**The gate stays standing.** Any future change to a stat-glue surface must keep the
goldens byte-identical or *justify the diff explicitly*: regenerate with
`lua5.4 tests/gen_goldens.lua` and treat the diff as a claim that a field-tuned ladder's
output moved — which needs Henrik-level sign-off, not a casual re-commit.

**Windows trap (cost one round):** the builder's write path appends the literal
`dlac\autogear.lua` — on Linux that is ONE filename (backslash in the name); on Windows
it is a **subpath**, so the fixture must create the `dlac\` scaffold dir or the write
fails silently and the capture reads nil (CI green, Windows red). Fixed in #76
(`60facb5`); the lesson generalizes: golden work must run BOTH loops before merge —
CI-green is not Windows-green.

## The guards (run_tests §GRD) — what each failure means

Every guard scans source with comments stripped and carries self-checks in three
directions: the pattern is detectable, prose doesn't false-positive, and **the
sanctioned home still contains the idiom** (a guard watching nothing is a false sense of
security).

| Guard | Fires when | What it means / what to do |
|---|---|---|
| GRD1 | raw `GetEquippedItem` read outside oracle/engine | Someone re-rolled the worn read. Route through `oracle.wornItem`. |
| GRD2 | packed-Index arithmetic outside the two homes | A private decode. Same fix. |
| GRD3 | the equip-bag list re-declared | Use `oracle.equipBags()` / the engine twin. A *legitimate* bag change edits BOTH homes — the parity pin will force the twin edit. |
| GRD4 | a 22-job list copy outside the twins | Consume the decoded job list; don't re-list jobs. |
| GRD5 | `levelstats`/`geareffects`/`augments` required from feature/ or ui/ | Hand-glued stats. Ask `oracle.stats`/`setStats`/the augment passthrough. The allowlist is `{}` — **no exemptions**; do not re-add entries. |

A parity-pin failure (OR section) is different: it means the oracle and an engine twin
**disagree** — someone edited one home without the other. The failure message names the
twin; mirror the edit. Never silence the pin.

## Ship record & pipeline notes

- PRD #69 → issues #70–#74 → PRs **#75** (fetch + pins), **#76** (goldens; + the
  Windows scaffold fix), **#77** (eligibility + identity), **#78** (guards + ADR 0013),
  **#79** (stat-glue migration, allowlist emptied). All squash-merged 2026-07-22.
  Agent-built (issue-agent label dispatch, serial), maintainer-reviewed each PR:
  footprint check, claim-blind grep, both-platform battery, golden cleanliness.
- Engine `dispatch.M.VERSION` never bumped — the engine five's behavior was untouched
  throughout (the step-1 twin refactor was arithmetic-identical, hoisted only for
  test reachability).
- First post-ship consumer: **landed same day** — the pet-channel stats surface
  (`petStats`, fronting `data/petmods.lua`) with `gearfmt.petLines` asking the door;
  the PM test section swap-proves the routing (the fresh-each-call require made it
  observable). The oracle gained its first new answer without a rival door forming —
  the extension path working as designed.
- Second extension, same evening (Henrik: "pet stats become stat weights + stat
  menu"): `petScoreStats` + `petStatKeys` price the channel — `Pet:`-namespaced
  keys through gearui's `candidateStats` seam and the weights picker, master
  `stats()`/`setStats()` untouched (goldens byte-identical through the change,
  PM17+ pins the flatten rule). **Field-confirmed the same night** after one
  instinct fix: pet-type names became picker search terms ("wyvern" finds
  Pet:HP% — `petStatKeys`' second return).

## Troubleshooting quick table

| Symptom | Likely truth |
|---|---|
| A ladder/manifest output changed | Golden diff will name it. If unintentional: bug in the change, not the gate. If intentional: regenerate goldens WITH review + sign-off. |
| GRD failure on new code | The code re-derived a gear answer. Ask the oracle; extend the oracle if the answer doesn't exist yet. |
| Parity pin failure | One-sided edit of a twinned rule. Mirror it. |
| `canWear` false where the old code said true | Only reachable if the engine module failed to load (conservative-false by design) — the real problem is the load failure. |
| `lookup` returns the wrong relic stage | Name-keyed lookup on a multi-stage name; use the id (the Iridescence id-pin rule). |
| Goldens fail on Windows only | Line-endings (`.gitattributes` must keep `-text`) or the `dlac\` scaffold-dir asymmetry above. |
