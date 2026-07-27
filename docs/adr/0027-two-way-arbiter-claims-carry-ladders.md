# The two-way Arbiter: Claims carry ladders; one arbitration per dispatch

Accepted 2026-07-27 — **as a design contract.** The staged migration (stages 0–6)
lives in `docs/design/two-way-arbiter.md` §7; every stage started on Henrik's explicit
go, and **all seven stages are SHIPPED** (stages 0–4 + 6 on 2026-07-27, engine
v136–v151; stage 5 on 2026-07-28, addon `2026.07.28a`) — per-stage status blocks and
honest deviations in §7. This ADR records the rulings so they cannot drift. Ratified
item by item in one session, each with worked examples.

## The decision

The equip pipeline's early binding ends. `utils.BuildDynamicSets` stops being a
*picker* (collapsing each slot's candidate list to one name at flatten time — the root
under the AutoAmmo v134 and dominance v135 field bugs) and becomes a *filter/sort*;
the alternatives stay alive, per slot, into the decision. The Arbiter deepens from a
per-slot ranker into **the aware one** (Henrik's phrase): the single decision point
that runs one **arbitration** per dispatch — sixteen **contests** — over Claims that
carry whole **ladders**, calling constraint functions as it walks, and returning **one
plan** (written once, at the one seam) plus **the trace** that `/dl why` renders. The
same walk decides and explains; the imperative-applies-vs-pure-model split retires.

## The four rulings

1. **Vocabulary.** *Ladder* is generalized from the Ammo ladder (ordered rungs; gates
   only ever remove, never reorder). *Claim* widens to carry a ladder per slot,
   submitted whole, up front — no separate "Proposal" noun (a reserving piece "claims
   the reserved slot with emptiness"). A *Refusal* either **falls** a rung (the same
   claim's next rung is asked, inside the arbitration — no round-trip to the source) or
   **holds** a slot (terminal: locked, sync-hold, mp-hold, reserved-by). *Contest* per
   slot; *arbitration* per dispatch ("settle" rejected — collides with the sync-settle
   hold). *Trace* is the returned decision record ("minutes" rejected); today's
   `/dl why` trace deepens into it and "retrace" keeps its meaning.

2. **The cross-rank dominance law.** A reserving piece is a candidate only while it is
   dominant over every slot it reserves, judged by **strength**: across rows, rank wins
   outright (the same ordering the slot contest uses); within the Triggers row,
   priority (ADR 0003; v135 as shipped); ties favor the reserver. The dominance
   comparison is **`(row, prio)` — `ord` excluded**, so reordering rules in the trigger
   file can never silently flip a reservation (`ord` remains the slot-contest
   tiebreak). **Worn pieces are not claims** — only claims defend slots (the Mindie
   ruling generalized); a beaten worn reserver is displaced by the server when the
   winner lands. Consequences accepted: `ctx.pinReserved` and the naked-voids special
   case retire into the general rule; a reserver can no longer bulldoze a locked slot;
   the player's drag list is the dominance authority. The refused piece **falls** to
   its next rung; the reserved slot **never falls** (the server empties it — falling
   there would re-derive the flap). The Range↔Ammo pair law (ADR 0010) is not
   dominance and keeps its own decision rules as a separate constraint.

3. **MaxMP folds in — the Arbiter is the aware one.** Henrik, verbatim: *"maybe we can
   call functions in arbiter to make this the aware one? Instead of having the logic
   outside of the arbiter?"* Comparative judgments live inside the arbitration:
   batteries become ladder claims at MaxMP's row (band thresholds are gates), MP-hold
   becomes a named constraint the arbitration calls, movement yield and sticky pairs
   become view-reading gates on MaxMP's own claims. The rank list is the spine;
   constraints plus the `view` are the awareness. **Aware ≠ impure**: everything live
   (current MP, moving, worn) is sampled once per dispatch into the session, so the
   arbitration stays replayable and headless-testable. The migration is **stage 6,
   deliberately last**, gated behind band-parity tests, goldens and its own field
   campaign; the woven code is interim scaffolding until its replacement is
   field-confirmed, then deleted (with `ctx.mpCeded`/`ctx.mpRespectLocks`, the last
   ctx-thread).

4. **`/dl why` prints depth on demand.** Bare `/dl why` keeps today's one-screen
   budget — one line per contested slot, falls folded inline and short; the collapsed
   summaries (uncontested floor, Naked, Free equip) are unchanged. The new
   `/dl why <slot>` prints the full contest for one slot: every claim in strength
   order, every rung's verdict with its reason.

## What this amends, completes, and keeps

- **Amends ADR 0012**: the Claim record widens from `{ [Slot] = itemName }` to a
  ladder per slot; the registry, the rank rows, the restore-at-default law (v122) and
  the "one row + one claim, no new arm" promise all stand — the promise finally
  becomes literally true.
- **Completes ADR 0006** ("the builder is a plan; the engine decides"): the flattener
  was a third actor deciding before the engine could. Addendum 2's "post-pass on the
  final names" doctrine retires with the post-passes — reservations are declared as
  claims instead.
- **Keeps**: ADR 0003 priorities; ADR 0010's pair-law decision rules (as a
  constraint, scope widening from within-set to within-plan); ADR 0013's claim-blind
  Oracle (the arbitration asks capability, never permission); ADR 0024's Disabled
  filter at the write seam (belt and braces, alongside the arbitration's own model);
  the sub-slot building-freedom hard rule (ladders are built free; the arbitration
  gates); `equipcore.planSet` as the executor; determinism (RSLOT_ORDER walks, no
  `pairs()` in decisions, signature-memoized arbitration for the per-frame Default).

## Consequences

- A new claimant = one registry row + one ladder-bearing claims function; it inherits
  reservation, pairing, usability, locks, ceiling and attribution without meeting any
  of the nine bespoke pairwise mechanisms the design inventoried — those retire as the
  stages land.
- One plan, one `engineEquipSet` per dispatch: the equipengine buffer stops being the
  hidden merger, and the trigger floor becomes the bottom rank row (strength
  `(row, prio, ord)` unifies the two orderings v135 could not compare).
- Nothing is dropped silently: every fall and hold is recorded with a reason in the
  trace — the v134 failure class ("total silent failure") becomes structurally
  impossible.
- Implementation risk is carried by the staging (each stage ships whole and is
  field-confirmed before the next; goldens gate the deliberate `/dl why` text change
  at stage 3), not by this ADR.
