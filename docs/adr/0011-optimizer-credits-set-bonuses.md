# ADR 0011 — Optimizer credits gear-set bonuses via the true combination objective

**Status:** accepted, shipped 2026-07-18 (conditional-effects P1 display + P3 optimizer,
`docs/design/conditional-effects.md`)

## Context

CatsEyeXI applies 126 gear-set bonuses server-side (Lava's + Kusha's, Iron Ram, the
level-30/50 JSE quest sets…). dlac's evaluation layer valued every item in isolation, so
a set piece whose worth IS its partners scored as junk, totals under-reported worn
reality, and Auto-build could never choose a bonus pair on purpose.
`docs/design/latent-rings.md` had originally called the optimizer side out of scope;
Henrik reversed that ("would be nice if they could be part of weight calculations…
consider set pieces as a potential candidate if they were together or not").

## Decision

One evaluator, one objective:

- **`gear\geareffects.lua`** (pure core, data-injected, headless-tested) owns set
  membership (`setsOf`), tier lookup (`setTier` = `tiers[math.min(count, max)]`, nil
  below `min`), and **`comboStats(composition, ctx)`** — the single source of truth for
  "what stats does this whole composition have". Worn totals, planned totals, the panel
  captions and the hover ladder all derive from it.
- **`optimizePicks` gains `opts.effects`** `{ setsOf, setTier, baseComposition }`:
  per-set piece counts are maintained incrementally per assignment (per SLOT, no
  uniqueness check — two owned copies count twice, verified against the server applier,
  design Appendix C), and active tier deltas are folded **inside the per-weight cap
  fold** — bonuses share the cap budget with regular stats, which is the game truth.
- **Set-seeded restarts** close the local-search hole: single-slot hill climbing
  provably cannot enter a k-piece bonus whose pieces are each a solo loss. After the
  plain climb converges, each weight-relevant set (top 6 by projected best-tier value,
  plus slot-disjoint pairs, ≤ 12 seeds — hard deterministic caps) is force-placed onto
  the converged baseline (least-loss incumbent choice) and climbed again; a result is
  kept **only on strict improvement** (monotone acceptance). Seeded pieces are never
  pinned — a seed that doesn't pay for itself is evicted and dissolves back to the
  baseline answer.
- **Pool augmentation is append-only**: buildBestSet's top-20 prune now APPENDS (never
  removes) ranked-out members of weight-relevant sets. The Sub marginal call passes the
  joint pick as `baseComposition`, so a grip that completes a set is credited — credit
  added, the offered list never narrowed (the Sub HARD RULE stands untouched).
- **`workingWeightedScore` is the same function**: the Sets panel's weighted number is
  now `score(comboStats(plannedComposition).stats + augments)` — the number the panel
  shows, the tooltip math, and the optimizer's reported total are one evaluation.

## Exact vs. approximated (stated honestly)

**Exact:** the objective. Every reported number is the true whole-combination
evaluation of the returned assignment, caps and set tiers included.

**Approximated:** the search. Each restart converges to a local optimum under
single-slot moves; combinations of ≥3 mutually-dependent sets can be missed within the
seed budget. Realistic failure mode: a marginal 3-piece tier upgrade missed — never
"Lava/Kusha not credited".

## Deliberate exclusions

- **Greedy `/dl` single-stat builds stay set-blind** (`buildSet`/`buildMaxStatSet`):
  raw-single-stat by design, and that path owns the Range/Ammo legality rule
  (H9-H14). Routing it through optimizePicks would require porting that rule — deferred
  indefinitely; revisit only on real demand. A set bonus can therefore never change
  (in particular never legalize) a Range/Ammo pairing — pinned by HB10.
- **Per-item sorts stay set-blind** (`scoreOfItem`, candidate list ordering, ladder
  rungs): a single item has no combination; keystroke-path cost stays zero.
- **Pre-existing gap noted, not fixed:** the optimizePicks paths carry no Range/Ammo
  legality rule of their own (they never did); the greedy path remains its owner.

## Rejected alternatives

- *Meta-candidates spanning slots* (offer Lava+Kusha as one pooled candidate): the
  conflict fn can veto pairs but cannot REQUIRE them, and merging paired labels makes
  pool size a product (Ring1×Ring2 = 400 at the top-20 cap).
- *Per-item pseudo-stat thresholds* (a "SetPiece70" weight with cap tricks): the weight
  shape (`perUnit`/`cap`) cannot express piece-count tiers.
- *Ascending-setId seed order under the cap*: deterministic but value-blind — the cap
  would drop sets by id accident. Kept: descending projected value, setId tiebreak.

## Tests

HB1-HB11 (`tests\run_tests.lua`): numeric objective pin, seeded pair discovery, EMPTY
tie survival, conflict-beats-set + two-copies counting, seed eviction/monotone
acceptance, cap sharing, effects-nil bit-identity (H1-H8 rerun through the same code),
tiered marginal entry, baseComposition partner credit, greedy-path set-blindness,
append-only augmentation end-to-end. GD/GE sections pin the shipped data shapes and the
evaluator semantics (per-slot counting, level gate, alternates, tier replacement).
