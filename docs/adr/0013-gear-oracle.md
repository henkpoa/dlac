# 0013 — The Gear Oracle: one door for gear questions, and the four boundary rulings

2026-07-22. PRD #69 (Gear Oracle — one door for every gear question); shipped across
issues #70 (fetch), #71 (eligibility + identity), #72 (golden harness), #73 (this record
+ the HARD RULE guards), #74 (the Phase-2 stat-glue migration). Confirmed by Henrik.

## Context

Gear truth was fetched and interpreted in many places, and every module made its own
deductions. A full sweep of the checkout found the *interpretation* layer already
centralized and correct (the set-bonus composition evaluator over the level-stats
resolver and augment decoder is the most complete interpreter), while the *fetch* layer
had hard duplication: the worn-item packed-index decode existed four times, the
equip-eligible bag list four times as a literal, the main-job equip gate as a central
rule plus two inline fallback copies, the catalog nested walk twice, the Shield/Grip
split three times. Feature manifest builders (MaxMP batteries, HELM, fishing, craft
ladders) privately hand-glued level-scaled stats and augment folds. Any copy could drift
and silently change what "owned", "eligible", or "worth wearing" meant in one module and
not another — the same class of hidden divergence the Claim/Arbiter (ADR 0012) ended for
slot contention.

The fix is a single **Gear Oracle** (`gear/gearoracle.lua`) — the one door for every gear
question in the addon state, joining the Central-services table as "Any question about
gear → the oracle". This record fixes the four boundary rulings that shape it, so future
sessions inherit the decisions and not just the code.

## Decision — the four boundary rulings

1. **Facade, not absorb.** The oracle newly owns the *homeless* fetch layer (worn-item
   decode, the equip-bag list, the gate delegations) and the combination *recipes*
   callers hand-assembled (effective stats = level-scaled + augment fold; identity =
   owned + catalog join). It **delegates** the proven math to the existing interpreters —
   the level-stats resolver (`data/levelstats`), the set-bonus composition evaluator
   (`gear/geareffects`), the augment decoder (`feature/augments`), the catalog index
   (`gear/catalogindex`), the owned-cache — which keep their homes, interfaces, tests and
   field-tuned behaviour **byte-identical**. No field-verified interpreter code moves.
   The interpreters keeping their existing suites green is itself evidence the facade did
   not move behaviour.

2. **Claim-blind, permanently.** The oracle answers **capability** — "*could* this
   character use this item?" (identity, stats, eligibility, availability). The
   Claim/Arbiter registry (ADR 0012) remains the sole authority on **permission** — "*may*
   this slot change right now, and who wins?". The two compose; they never contest. Method
   names use could-words (`canWear`, `available`), never may-words (`canEquip`). The oracle
   never consults locks, pins, or claims.

3. **Twins, with parity pins.** Per ADR 0002 the seeded LAC engine cannot require
   addon-folder modules, so the engine keeps exactly **three** tiny twins inside
   `dispatch.lua`: the worn-item decode (`decodeEquipIndex`), the any-job-style gate + the
   22-job list (`LS_JOBS`), and the equip-bag list (`AMMO_BAGS`). Each is guarded by a
   **parity-pin test** (`tests/run_tests.lua`, section OR) that feeds both the oracle door
   and the engine twin a fixture matrix and **fails CI naming the twin** on any drift — the
   same mechanism as the Blueprints serializer pins. No new engine-side gear helper may be
   added without a pin.

4. **No sixth seeded engine file.** Rejected explicitly. A sixth seeded file would join
   the cast-time path, demand seeding + Reload-LAC discipline on every change (hard rule
   4), widen the blast radius of a bug into the equip loop, and *still* need an internal
   state fork because the catalog is addon-state-only (ADR 0004) — one filename, two
   behaviour modes, for ~30 lines of unification. The three CI-pinned twins are the
   cheaper, safer trade.

## Enforcement — the door becomes law (issue #73)

The rulings are held by **HARD RULE source guards** (`tests/run_tests.lua`, section GRD),
the source-level ratchet that turns a private gear deduction into a CI failure rather than
a review catch (prior art in spirit: the Sub-slot never-gated A* rules, the OR parity
pins):

- **GRD1/GRD2** — the raw equipped-item read (`GetEquippedItem`) and its packed-index
  decode arithmetic are confined to the engine twin + the oracle.
- **GRD3** — the equip-bag list literal is confined to the same two homes.
- **GRD4** — the 22-job ordered list is confined to the engine twins + the addon-state
  gate (`gear/jobgate`, the home `anyJobCanWear` delegates to). The id→name *map* form is
  a different structure and is not policed.
- **GRD5** — the stat interpreters (`levelstats`/`geareffects`/`augments`) may be required
  only by the oracle and the gear pipeline; a feature/UI module that loads one is
  hand-gluing stats and must ask the oracle instead. The catalog index is a **standing**
  central service (browsed directly, architecture.md) — the oracle fronts it only for the
  identity join, so it is deliberately not policed by GRD5.

GRD5 carries the **one temporary allowlist** — the Phase-2 stat-glue surfaces that still
hand-glue stats and so still load an interpreter. It is the ratchet: Oracle step 5 (#74)
migrates those surfaces onto `oracle.stats()`/`setStats()`, **empties** the allowlist, and
from then the rule is absolute. Every guard carries a self-check proving its pattern is
actually detectable — a guard that matches nothing is a false sense of security.

## Alternatives rejected

- **Absorb the interpreters into the oracle** — would move field-tuned code (the MaxMP
  banded ladder came out of a long debug saga; the set-bonus evaluator is the most
  complete interpreter) for a purity win, risking attribution poisoning. Facade keeps the
  behaviour where its tests are.
- **A sixth seeded engine file** — see ruling 4.
- **Permission words on the oracle** (`canEquip`) — blurs the capability/permission line
  the Arbiter owns; the two authorities must never appear to contest.
- **Migrate the stat-glue in the same slice as the fetch layer** — the field-tuned ladders
  are protected by a golden-output harness (#72) captured *before* migration, so Phase 2
  is proven byte-identical, not assumed. Splitting fetch (behaviour-identical by
  construction) from stat-glue (golden-gated) keeps a later field failure from being
  misattributed to the refactor.

## Consequences

- Any module can ask one door: `wornItem`, `equipBags`, `canWear`, `anyJobCanWear`,
  `lookup`, and (after #74) `stats`/`setStats`. A future bag addition is one edit; a gate
  rule lives in one place.
- The retired duplicates were **deleted, not deprecated**, so copy-paste cannot resurrect
  them; the guards keep them from coming back under a new name.
- The oracle and the Arbiter are two clean authorities an automation composes — "*could*
  I wear this" (oracle) AND "*may* this slot change" (Arbiter) — rather than one blurred
  one.
- Extending gear answers means extending the oracle, never inventing a rival; a new engine
  gear helper means a new parity pin.
