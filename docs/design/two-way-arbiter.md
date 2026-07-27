# The two-way Arbiter — late binding, ladders, one arbitration per dispatch

> **Status: RATIFIED 2026-07-27; stages 0–4 + 6 SHIPPED on dev the same day (engine
> v136 → v151) — stage 5 (collapse retirement) is the one stage left.** This is the
> dedicated hard look Henrik parked on 07-27 (*"too central and too big of a decision to
> just be made on a whim"*) and then asked for: *"take a hard look and see if we can in a
> scalable way move away from this legacy, where things talk to each other much better…
> check in with the Arbiter more often in a more open communication… to scale up the
> decision process considerably."* He explicitly opened old decisions and rules for
> debate (§6), and all four §10 items were then discussed one at a time and **ratified
> the same day**; the contract is recorded as **ADR 0027**.
> Every stage started only on Henrik's explicit go (and did); per-stage status blocks in §7.
>
> Companion: candidate #1 in `docs/design/architecture-review-2026-07-25.md` — this
> document absorbs and supersedes the staging sketch parked inside that block (the
> sketch said "the grill should challenge it, not inherit it"; §7 does both, and says
> where it deviates and why). Line anchors below are as of dev @ b970983, v135.

---

## 1. The asks, verbatim

Three Henrik quotes carry the whole requirement:

1. *"I feel like utils.BuildDynamicSets are very legacy… I feel like just having one
   point where gears are built is very limiting."*
2. *"The Claim Arbiter really has a central role, and I'd like for it to be able to talk
   back to the functions that call it so it's just not a one way communication, and that
   sets can be changed on the fly."*
3. (07-27, this session) *"We had an issue earlier with how things reserve and equip with
   gear that uses more than 1 slot, where I want things to be able to communicate better
   and take decisions and check in with the Arbiter more often in a more open
   communication. This to scale up the decision process considerably."*

Read together: he is not asking for many *write* points — he is asking for many
*proposers* and a richer conversation with the one decider. The target shape is:
**building distributed (every feature owns its candidates), deciding single (the
Arbiter), writing single (the seam).** Today only the third of those is true.

## 2. Diagnosis — why the current shape cannot scale

### 2.1 The root: early binding

`utils.BuildDynamicSets` collapses each slot's authored candidate list to **one name**
(`utils.lua:554`, `currentSet[slotName] = gearObject.Name`) using only level, subjob,
mode, and the DW/pairing rules — the least information anyone in the pipeline will ever
have. It cannot know which triggers matched, what priority won a slot, what is worn,
what reserves what, or what the Arbiter concluded — all of that exists only later, at
dispatch time. Every downstream actor therefore receives a single name, and its only
available move is **veto** (nil the slot = keep worn). A veto is terminal: the
alternatives were discarded at flatten time, so there is nobody left to ask for a second
candidate.

Two shipped field bugs are this root wearing different coats:

* **AutoAmmo v134** — the overlay collapsed its own ladder to one name before the equip
  layer saw it; a level gate it skipped was a *total, silent* failure ("there is no rung
  2 to fall to").
* **Dominance v135** — an ineligible Royal Cloak leaves Body **unwritten** instead of
  falling to the next Body piece. That fallthrough is the one part of Henrik's ruling
  that could not be built — because by the time the verdict runs, the ladder is gone.

And this is also *why* the Arbiter is one-way: by the time it speaks, there is only one
name per slot left in the world. There is nothing to negotiate *with*.

### 2.2 The evidence of non-scaling: the mechanism inventory

Because no layer can ask another layer for its next-best candidate, every pairwise
interaction between features has been patched with a bespoke mechanism at a bespoke
altitude. Inventory, all verified live:

| # | Mechanism | Altitude | Covers |
|---|---|---|---|
| 1 | per-slot precedence chain (`elseif` ladder) | `equipResolved` `dispatch.lua:3884` | locks > sync-hold > pin-reserved > AutoAcc > virtuals > MP weave |
| 2 | five post-passes, `POST_ORDER` | `dispatch.lua:3031,3983` | mp-stage, craft-sub-guard, sync-hold-ammo, trinket-vs-ranged, reserved-drops |
| 3 | `ctx.pinReserved` stateless hold | dispatch `:5738` | pins' reservations vs everything below |
| 4 | `ctx.craftMainGuard` (+ pin-vs-craft special case `:5744`) | dispatch | Sub/Main pairing across two specific layers |
| 5 | `ctx.mpCeded` + `ctx.mpRespectLocks` | dispatch `:5824,5834` | woven MaxMP vs the rank list |
| 6 | v135 merged floor + verdict, built `:5978`, **cleared `:6041`** | trigger floor only | multi-slot dominance within triggers |
| 7 | `marker\|fallback` string encoding | utils `:577`, chain `:3910` | a 2-rung ladder, for virtuals only |
| 8 | `stripDisabled` at the write seam | `engineEquipSet` `:393` | the ceiling vs every writer |
| 9 | naked-voids-pinReserve save/restore | applyClaim `:6128` | Naked vs Pins' reservation, one pair |

Nine mechanisms, each the answer to "who may write this slot" for one *pair* of
features. That is O(n²) growth: mechanism #9 exists because #3 (built for pins-vs-sets)
met Naked. The next claimant meets all nine.

### 2.3 Two orderings that cannot compare

Trigger **priority** (ADR 0003, numbers within the floor) and Arbiter **rank** (rows
across claims) are separate orderings. v135's dominance uses priority, and therefore had
to be scoped to the floor and *cleared before the claims apply* (`dispatch.lua:6036-6041`
— "reading a rank contest off a priority number that never modelled it"). The deferred
half of Henrik's ruling — a Craft or AutoAmmo claim making a reserving piece ineligible
by the same rule — is blocked on exactly this: there is no single "strength" a Body-from-
a-trigger and a Body-from-a-claim can be compared by.

### 2.4 Decide and explain are two parallel machines

The live gear is produced by the *imperative* path: each claim applied through its own
`equipResolved` in reverse rank order (`:6150-6153`), last writer wins, holds and ceding
woven through `ctx`. The *pure* model (`arbResolve`/`arbExplain`/`arbWhyLines`) runs only
under retrace, **for attribution** (`:6172-6199`). Two machines, kept in agreement by
hand — every weave (`mpCeded`, `layerRespectsLocks`, the Locks-row merge `:6182-6193`)
exists to make the imperative path do what the model says. The model is the better
design, and it is currently the passenger.

### 2.5 N writes per dispatch; the buffer is the hidden merger

Every `equipResolved` call ends in `engineEquipSet` (`:4162`) — the trigger floor sends
per hit, then each claim sends again. The final worn state is whatever the equipengine
buffer accumulated, in apply order. No decision logic ever sees "the final plan" as a
value; the closest thing (v135's `floorTbl`) exists only under retrace, only for the
floor — and the comment at `:5967-5972` names that gap as the bug ("the merged view used
to exist ONLY… to draw /dl why, while the equip path resolved each rule blind").

### 2.6 The one-state unlock nobody has cashed in

Half of the legacy encoding exists because flatten-time and dispatch-time used to live in
different Lua states with a file between them: markers are *strings* with prio/acc baked
in "because the seeded engine state has no catalog to look them up in" (`utils.lua:598`),
and dispatch keeps byte-identical twins of oracle reads (ADR 0002) because "the LAC-state
engine has no catalog." **The purge (v131–v133) ended that.** One state, one engine, one
home — `utils` already lazily requires `feature/wishlist` (`utils.lua:338`). The sets
store keeps the authored ladders in memory *right next to* the flattened picks
(`store.Dynamic`, `installSets` `:6655-6661`); the ladder is discarded only logically,
never physically. Late binding does not need a new data path. It needs permission.

## 3. What survives untouched

Not everything old is legacy. These are field-paid laws the redesign must keep, stated
so the debate in §6 has a floor:

- **The pick comparator.** Range-tier beats unbounded, item level within tier, earlier
  entry on ties, active-mode pass before unconditional pass (`utils.lua:519-544,561-566`).
  Field-proven. It stops being a *truncation* and becomes the **ladder order** — kept
  verbatim as the sort.
- **ADR 0003** — priority ascending, file order on ties — becomes the intra-floor
  strength component, unchanged.
- **ADR 0006's title** — "the builder is a plan; the engine decides at equip time." The
  redesign *completes* this ADR rather than contradicting it: today a third actor (the
  flattener) decides before the engine can. The builder's plan becomes the whole ladder;
  the engine's decision becomes real.
- **The sub-slot building freedom hard rule** (3× reverted). Building never gates on
  live state. Ladders are built free; the *arbitration* gates. Nothing here touches the
  picker.
- **Determinism laws.** `RSLOT_ORDER` walks, no `pairs()` in any decision, fixed tie
  rules (ties favor the reserver, `reserveVerdict` `:2704`), same-input-same-output.
- **The rank list UX** — one draggable list, restore-at-default-position (v122), floor
  and ceiling pinned. The registry survives; only what a row *contains* deepens.
- **ADR 0013** — the Oracle stays claim-blind: capability, never permission. The arbitration
  asks "can this be worn / is it owned"; only the Arbiter decides precedence.
- **ADR 0024's placement** — the Disabled filter stays at the write seam even after the
  arbitration also models it: the seam covers every caller the seam grows later. Belt and
  braces, deliberately.
- **`equipcore.planSet`** — the pure snapshot→plan resolver stays the executor exactly
  as is. It is the shape the whole redesign is aiming the *decision* layer at.
- **The perf envelope.** Default dispatches every frame. Whatever arbitrates must be
  memoizable on a signature, like retrace already is.
- **Engine-native over commands** — stateless holds, nothing persisted, everything
  recomputed per dispatch. The arbitration is *more* of this, not less.

## 4. The target — one arbitration per dispatch

### 4.1 The one-sentence version

**Promote the pure model from explaining to deciding:** collect *Claims* (each carrying
whole ladders) from every source, run *constraints* (with named refusal reasons) over
one deterministic walk, produce **one plan** and **one trace**, write the plan **once**,
and let `/dl why` render the trace — the same object that decided.

### 4.2 Vocabulary — **RATIFIED by Henrik, 2026-07-27** (item 1 of the §10 discussion)

- **Ladder** — generalized from the already-ratified *Ammo ladder* (CONTEXT.md): an
  ordered candidate list plus the rule that reads it — walk top-down, take the first
  **rung** that clears every gate; gates only ever *remove* candidates, never reorder.
  A Dynamic Set slot's list, the automation manifest chains and the Ammo ladder are all
  ladders. "The set changed on the fly" = the ladder is consulted at arbitration time,
  against live context.
- **Claim (widened — no new "Proposal" noun).** A Claim stays CONTEXT.md's "declared
  wish to dress one or more slots"; its per-slot content deepens from one name to one
  **ladder**, submitted whole, up front — the source speaks once, before the
  arbitration starts, and its full preference order is in the room after it has gone
  home. A reserving piece *claims the reserved slot with emptiness* — Henrik's original
  ruling sentence ("it shall claim both slots"), now literal mechanics.
- **Strength** — the one comparable: `(row, prio, ord)`. `row` = the Arbiter rank index
  (Triggers is simply the bottom row); `prio`/`ord` = ADR 0003 within the Triggers row,
  `0` inside claim rows. This single ordering is what unlocks dominance across rank —
  the deferred half of the v135 ruling. **The dominance comparison itself is RATIFIED
  (§10 item 2, 2026-07-27): `(row, prio)` only — `ord` is excluded, so moving a rule
  down the trigger file never silently flips a reservation; `ord` stays the
  slot-contest tiebreak.**
- **Constraint** — a named validator consulted during the walk: reservation/dominance,
  the Range↔Ammo pair law, Sub↔Main pairing, usability (level/job/owned), sync-hold,
  locks, ceiling. Each returns a **verdict**.
- **Refusal** — a constraint saying no *with a recorded reason*. Two flavors:
  - `pass` — the rung stands.
  - `fall(reason)` — this rung is refused, **the same claim's next rung is asked** —
    inside the arbitration, no round-trip to the source. Reasons: `level`, `job`,
    `not-owned`, `ineligible` (reserves a slot a stronger claim owns), `pair` (bolt
    under a bow — the ammo falls to the next ammo rung).
  - `hold(reason)` — terminal for the slot: write nothing, keep worn. Reasons: `locked`,
    `sync-hold`, `mp-hold`, `reserved-by <piece>` (the server will empty it; see the
    asymmetry in §4.5).
  - Naked's `remove` and Locks' `LOCK_HELD` stop being special-cased arms — they are
    ordinary claims whose rung is a sentinel, exactly as `arbResolve` already models
    them. The special rows become unspecial.
- **Contest** (existing, kept) — the per-slot decision ("slots are contested one by
  one"). **Arbitration** — the per-dispatch whole: sixteen contests, one plan, one
  write. `arbiter.arbitrate(session) -> plan, trace`. ("Settle" was considered and
  dropped — it collides with the sync-*settle* hold already in dispatch and `/dl why`.)
- **Trace** (existing, deepened — "minutes" was considered and dropped) — the decision
  record the arbitration returns: per slot, who claimed what, who fell and why, who won
  at what strength. Today's `_trace[event]` rendered-lines cache becomes a formatter
  over this structured object; "retrace" keeps its meaning (re-render when the
  signature moves). The trace that decided is the trace you read — `arbExplain`'s
  parallel model retires into it.

### 4.3 The contract, concretely

```lua
-- gear/arbiter.lua -- PURE (equipcore's sibling): no AshitaCore, no io, no globals.
-- session = {
--   order   = arbOrder,                    -- the rank rows, as today
--   rows    = {                            -- one per ACTIVE source (registry rows)
--     { name = 'Triggers', claims = { { slot='Body', ladder={...}, prio=25, ord=3 }, ... } },
--     { name = 'AutoAmmo', claims = { { slot='Ammo', ladder={rung1, rung2, ...} } } },
--     { name = 'Locks',    claims = { { slot='Head', ladder={ SENTINEL_HELD } } } },
--     ...
--   },
--   reads   = { rslotOf=f, pairOf=f, levelOf=f, usable=f, worn=f, level=n, ... },
--   constraints = CONSTRAINTS,             -- ordered, named; data like POST_ORDER is today
-- }
-- returns plan  = { [SlotKey] = name | 'remove' | nil }   -- nil = engine says nothing
--         trace = { [SlotKey] = { winner={source,name,strength},
--                                 fell={ {source,name,why}, ... },
--                                 held=..., }, ... }
function M.arbitrate(session) ... end
```

- **Ladders are data by default, a function by escape hatch** (`ladder = f(view)`), for
  the few sources whose candidates genuinely depend on the contest (MaxMP's hold needs
  "what would win below me"; the `view` argument exposes the tentative winner under a
  given strength — that is the literal two-way channel). Data-first keeps the walk
  deterministic and the tests flat; the parked sketch's pure callback protocol
  (`propose/refuse` as the *only* interface) is rejected for the general case — a
  conversation of closures re-introduces "the answer depends on when you were asked,"
  which is the `pairs()` bug wearing a nicer suit. (Ratified with the vocabulary:
  Henrik independently proposed "send the whole ladder" on 07-27.)
- **The walk**: slots in `RSLOT_ORDER`; per slot, claims sorted by strength; take the
  strongest claim's first rung; run constraints; `fall` → next rung, then next
  claim; `hold` → done, slot held. Reservation makes it a fixed point: a winner that
  reserves other slots claims each reserved slot *with emptiness, at its own strength*
  — if something stronger already stands there, the reserver is refused `ineligible`
  instead and **falls to its next rung** (v135's two directions, now with the
  fallthrough v135 could not build). Refusals only accumulate, so the worklist
  terminates; cap the re-walk (3 rounds) and log a cap hit as a bug signal.
- **One write.** `M.dispatch` becomes: collect → arbitrate → apply the one plan → one
  `engineEquipSet`. The equipengine buffer stops being the hidden merger; `planSet`'s
  satisfied-check sees the whole intent at once (fewer packets, quieter server — the
  same "don't spam the server" Henrik ruling that shaped the pair law).
- **Usability is a constraint, not a location failure.** Post-purge the arbitration can
  ask the oracle/ownedcache (injected, claim-blind): a name the executor could never
  locate is refused `not-owned`/`level` *during* the arbitration, where rung 2 is still
  alive — today it silently dies in `planSet`'s bag scan.

### 4.4 What each existing mechanism becomes

| Today | Becomes |
|---|---|
| flatten's pick (`utils:554`) | the ladder order (comparator kept; truncation retired) |
| `marker\|fallback` strings | virtuals are ladder *entries* resolved in the arbitration (their manifest chains — `resolveVirtual`'s best-first walks — flow through instead of collapsing) |
| `reservedDrops` / v135 verdict + clear | the reservation constraint, all rows, strength-compared |
| `trinket-vs-ranged` + `trinketWornDisplace` | the pair-law constraint (ADR 0010's decision rules intact; scope widens from within-set to within-plan) |
| `craft-sub-guard` + pin-vs-craft special case | the pairing constraint (`subSlotAllowed` on the *plan's* Main, whoever proposed it) |
| `sync-hold` + `sync-hold-ammo` | one hold constraint (weapon slots + Range-reserving ammo) |
| `ctx.pinReserved`, naked-voids special case | gone — reservation is one constraint, Naked outranking Pins falls out of strength |
| locks / naked / locked set / disabled arms | ordinary rows with sentinel ladders (ceiling keeps its seam filter too) |
| `mpCeded`/`mpRespectLocks` weave | interim: unchanged. End state RATIFIED (§10 item 3): MaxMP ladder claims + an mp-hold constraint reading the `view` — migrated last, §7 stage 6 |
| `applyClaim` closures + reverse rank walk | gone — one plan application |
| `arbResolve`/`arbExplain` under retrace | *the decider*; the structured trace replaces the parallel model |
| `/dl why` rendered lines | a formatter over the trace — refusals finally get printed with reasons ("Body: Royal Cloak refused (reserves Head, owned by Movement@25) → fell to Gold Harness") |

### 4.5 The multi-slot asymmetry, stated once

Henrik's pain case deserves its law in one place: **a refused piece falls; a reserved
slot does not.** If the Kupo Suit (Body, 25) is dominant, Legs is `hold: reserved-by`
— *no* legs candidate may land, at any rung, because the server will strip whatever
goes there (falling down the Legs ladder would be re-deriving the flap). If the suit is
*not* dominant, the suit is refused `ineligible` and **Body falls to the next Body
candidate** — which is then itself dominance-checked (rung 2 may also reserve). Both
directions are one rule at one altitude, with fallthrough on exactly one side.

## 5. Why this scales

- **Adding a claimant** = one registry row + one ladder-bearing claims function. It inherits
  reservation, pairing, usability, locks, ceiling, attribution — all nine §2.2
  mechanisms — without meeting any of them. N×M pairwise patches become N sources + M
  constraints.
- **Adding a constraint** = one named validator with a reason string. It automatically
  applies to every source, with its refusals printed.
- **"Check in with the Arbiter more often"** = every Default re-arbitrates against live
  context (memoized when nothing moved), and the `view` channel lets a source's policy
  read the contest instead of being woven through `ctx`.
- **Testability** — the review's headline finding was that `M.dispatch` is called zero
  times by any test. `arbitrate(session)` is the `equipcore.planSet(set, snapshot)`
  shape: plain tables in, plain tables out. The path every feature rides becomes
  drivable headless for the first time, and the trace makes every assertion
  self-explaining.
- **Explainability is structural.** Today a silent nil is the failure mode (v134's
  "total silent failure"). In the arbitration, *nothing* is dropped without a recorded
  reason — the bug class "a slot quietly stopped" becomes grep-able.

## 6. Old rules re-examined (the debate Henrik invited)

| Rule | Verdict | Why |
|---|---|---|
| ADR 0006 "builder plans, engine decides" | **Keep, complete** | The flattener was a third actor deciding early. Retire its *pick*, keep its *filter/sort*. Addendum 2's "post-pass on the final names" doctrine retires with the post-passes: reservation declared as claims replaces "each later EquipSet must declare what it takes away." |
| ADR 0012 claim = `{slot->name}` | **Revise** | Becomes `{slot -> ladder}` (+ optional function). The recipe comment at `dispatch.lua:3652-3667` ("exactly TWO things and NO new arm") finally becomes true — today it is 2 things plus 11 hunks of bookkeeping (the review measured 15 hunks for Chocobo). |
| "MaxMP stays woven" (ADR 0012) | **Revise — END STATE RATIFIED 2026-07-27: fold in** | Henrik's ruling (§10 item 3): the Arbiter is *the aware one* — decision logic does not live outside it. Batteries → ladder claims (band thresholds are gates); MP-hold → a named constraint the arbitration calls; movement yield + sticky pairs → view-reading gates on its own claims. The weave survives only as interim scaffolding: the arbitration never *requires* the fold before its migration stage (§7 stage 6 — last, after simpler constraints prove the vocabulary, behind parity tests + goldens + its own field campaign). |
| ADR 0010 trinket contest "within-set only" | **Revise scope** | "Within-set" was the honest scope when only one table was visible at a time. With one plan, the natural scope is within-*plan* — same decision rules (higher level wins the trinket contest; Range is HANDS OFF), wider, and the worn-displace arm stays. |
| The Triggers floor as a special phase | **Revise** | The floor becomes the bottom rank row with internal `(prio, ord)` strength. This is precisely what v135 lacked ("a priority number that never modelled it") — after unification, the clear at `:6041` and the "extend across rank later" caveat both retire. |
| `marker\|fallback` strings | **Retire gradually** | A 2-rung ladder encoded for a state boundary that no longer exists. Authoring format can keep the strings (profiles on disk); the in-memory store expands them to ladder entries at install. |
| Per-claim `equipResolved` + N sends | **Retire** | One plan, one send. All production callers are dispatch-internal (verified), so the consolidation is contained; `M._equipResolved` stays as a seam for the within-set passes' tests during migration. |
| The attribution parallel model | **Retire into the trace** | One machine decides *and* explains. The AR*/LV* tests move to the arbitration with their assertions intact. |
| Disabled at the write seam | **Keep** (also modeled in the arbitration) | ADR 0024's argument — the seam covers callers the rank walk never sees — survives the redesign verbatim. |
| Oracle twins in dispatch (ADR 0002) | **Flag for later** | "The engine has no catalog" died in the purge; the byte-identical twins (`decodeEquipIndex`, `AMMO_BAGS`) could collapse into the one door. Separate cleanup, not scoped here — noted so the review's GRD-parity pins are re-aimed deliberately, not by accident. |
| AutoAcc stays within-set (Henrik 07-21) | **Keep** | It is a candidate *transform* inside a claim's ladder, not a claimant. The arbitration changes nothing about it. |

## 7. Staging — every stage ships whole, field-confirmed before the next

Deviations from the parked sketch are marked ⚠ with the reason. Each stage is a normal
dev commit train (branch law), version-bumped when behavior changes, promoted
whole-or-not.

**Stage 0 — the registry rows (candidate #1 as originally written).** One `CLAIMANTS`
table — `{ name, ensure, active, claim, sig, apply, prioStatus }` — that the ensure
block, both bails, the claims map, the signature and the rank-walk applies all iterate.
Zero behavior change, pinned by AR*/LV* + goldens. ⚠ *Moved from the sketch's stage 4
to first:* it pays for itself standalone (15 hunks → 1 row, the silent-bail class
dies), it shrinks `M.dispatch` before surgery, and the arbitration then lands against
rows instead of eight locals. If everything after this stalls, stage 0 was still worth
shipping.

> **Status: SHIPPED on dev 2026-07-27 — Henrik's go, same session as the ratification.**
> Commit `05f7be8` (engine v136) + the CR test commit: CR0–CR9c pin the registry shape
> as data (row set = rank rows minus Triggers; the sig-leg byte order; MaxMP as the
> only claim-less/apply-less row; Locks as the only leg-less row; the two bail sets;
> rows driven directly through the real `equipResolved` + write seam), and NK26 drives
> the rewired `M.dispatch` end to end. Suite green at 3934 checks on Windows Lua AND
> WSL lua5.4 (CI parity). `/dl prio` now reads the rows — its hand-kept twin of the
> dispatch reads is gone. **FIELD-CONFIRMED 2026-07-27** — *"Stage 0 is confirmed"*:
> the SCH Royal-Cloak-vs-Head case still resolves (v135 intact), craft + HELM work;
> queued in HANDOFF per hard rule 14. Follow-up `cad6b1f` (v137) made the AutoAmmo
> `/dl prio` line job-aware (the one quirk the field pass flagged; pre-existing, not a
> stage-0 regression). **Stage 1 starts on Henrik's go.**

> **Stage 1 status: SHIPPED on dev 2026-07-27, commit `b26a1da` (engine v138, addon `27z`)
> — Henrik's go, same session.** Deeper than sketched, deliberately: rather than a second
> walk emitting lists (a twin that would drift), `BuildDynamicSets` itself was rebuilt on
> ONE evaluator — `utils.slotLadder` (the comparator as a sort) + `utils.flattenHead` (the
> one `marker|fallback`/AutoAcc composition site) — so the flatten IS the ladder's head and
> parity holds by construction (LD9 verifies anyway). `dispatch.candidatesFor(setName,
> slot)` is the on-demand door, answering with the last flatten's own context, memoized per
> `utils._laddersRev`. The old walk's virtual re-adoption quirk is preserved and pinned
> (LD8). Tests LD1–LD10d; suites 3973 + 693 on Windows Lua and WSL lua5.4.
> **FIELD-CONFIRMED 2026-07-27 with stage 2 and queued (hard rule 14).**

**Stage 1 — ladders on demand.** `candidatesFor(setName, slot)` — the `evalEntry` walk
emitting the *ordered list* instead of its head, memoized on the existing rebuild latch
(+ `modesRev`). ⚠ *The sketch said "carry the ladder additively" in the store; not
needed* — the authored ladders already live in `store.Dynamic` (§2.6); carrying them
again would duplicate state. Zero behavior change. Parity pin: `candidatesFor(...)[1] ==
the flattened pick`, property-tested across the suite's set fixtures.

**Stage 2 — complete the v135 ruling (first behavior change).** At the floor-verdict
build (`:5978-5994`): an `ineligible` slot re-proposes its source set's next candidate
(via `slotSrc`, made unconditional — trivial cost) that passes the re-run verdict; cap
the rounds. The Royal Cloak falls to the next Body piece. Floor-scoped exactly like
v135; small diff; immediately field-testable by the two 07-27 cases.

> **Stage 2 status: SHIPPED on dev 2026-07-27, commit `ad7ab30` (engine v139, addon
> `27za`) — Henrik's go, same session, spec'd by his own Mindie BRD test.
> FIELD-CONFIRMED 2026-07-27 — "Yes, the harness landed on Body" — and queued with
> stage 1 (hard rule 14). The craft-bench worn-reserver case he hit is the PRE-EXISTING
> Example C from the item-2 ruling, recorded as the stage-4 acceptance test.** One
> implementation deviation: provenance rides `reserveFloor` itself (`entries[].src` →
> `floor[slot].src`) rather than `slotSrc`, and the fall is the pure
> `M.reserveResolve(entries, lookup, ladderOf)` — verdict → ladder walk → re-verdict,
> fixed point capped at three re-runs, replacements delivered via `ctx.reserveReplace`
> into the refused piece's own writer pass (`Body=Royal Cloak fell -> Scorpion Harness
> +1 (reserves Head -- owned above)` in `/dl why`). A rung that reserves a dominated
> slot suppresses it like any dominant reserver; a rung beaten the same way falls
> again; a dry ladder or an inline equip keeps v135's INELIGIBLE behavior; **a
> reserved slot never falls** (AKF8 pins the asymmetry law). Tests AKF1–AKF10; suites
> 3997 + 693 on Windows Lua and WSL lua5.4. **Awaiting field confirmation — the
> acceptance test is Henrik's exact setup: Kabuto on Head, Scorpion Harness +1 on
> Body.** Stage 3 (extract `gear/arbiter.lua`) on his go after.

> **Stage 3 status: FIRST SLICE SHIPPED on dev 2026-07-27, commit `86b3447` (engine
> v140, addon `27zb`, zero behavior change) — Henrik's go, same session.**
> `gear/arbiter.lua` exists and is PURE (ARM1 loads it with no stubs): the slot + rank
> vocabulary, the reservation family (v135 verdict + stage-2 fall) and the
> resolve/explain family moved verbatim; every old dispatch seam is a rawequal-pinned
> delegation (ARM2* — never a twin; `LOCK_HELD` keeps identity); `arbitrate(session)`
> owns the APPLY ORDER and `M.dispatch` executes the plan. dispatch.lua shed 547 net
> lines. Suites 4011 + 693, both runtimes. **Remaining stage-3 slices, in order:** (a)
> per-slot contests + the structured trace (`/dl why` rendered from the object that
> decided — the deliberate goldens-gated text change), (b) one plan → one
> `engineEquipSet` send, (c) the pair law + the guards migrate in as constraints. Each
> slice ships and field-confirms like everything else; MaxMP's weave waits for stage 6.

**Stage 3 — extract `gear/arbiter.lua` and make it the decider.** Pure module; migrate
constraints one at a time in POST_ORDER's own order, each pinned by the tests that
already exist (AK*, AKD*, TR*, TB*, AM*, PL*, LS*, AR*, LV*): reservation first (it is
already pure — `reserveFloor`/`reserveVerdict` *are* the seed), then pair law, then the
guards, MP weave untouched. Dispatch's apply loop becomes collect → arbitrate → one
apply → one send. `/dl why` renders the trace (deliberate, reviewed text diff — the
goldens gate moves with it). This is the stage where decide-and-explain become one
machine.

> **Stage 4 status: FIRST SLICE SHIPPED on dev 2026-07-27, commit `af37d01` (engine
> v141, addon `27zc`) — Henrik's go; his craft bench is the acceptance.** The
> cross-rank law is live: verdict entries carry their Arbiter row, strength = rank
> outright across rows / priority within the floor / ties favor the reserver / ord
> excluded (ARK1–ARK3 pin each clause); worn pieces are not claims — with the
> dispatch verdict as the one authority (`ctx.reserveGlobal`) no floor or claim pass
> runs the single-set + worn fallback, and direct callers keep the old judgement
> (ARK7/7b). A dominant claim reserver suppresses floor slots by the general rule
> (ARK4); a beaten claim piece is killed v135-style, ladder-less this slice (ARK5).
> Suites 4026 + 693, both runtimes. **FIELD-CONFIRMED 2026-07-27 on the craft bench —
> "now it equips Scorpion Harness +1 in body and midrass helm +1 in head. So test case
> 100 % works, field validated" — and queued (hard rule 14).** Remaining stage-4
> slices: claim-side ladders
> (AutoAmmo rungs, hobby manifest chains), sentinel rows in the verdict (a reserver
> can no longer bulldoze a locked/free slot), `ctx.pinReserved` + naked-voids
> retirement.

**Stage 4 — claimants submit ladders; dominance across rank.** Registry rows gain
`claims()`; AutoAmmo submits its level ladder (the v134 gap class ends), craft/HELM/
fish/choco pass their manifest chains through instead of pre-resolving; pins/locks/
naked/locked-set stay single-rung by nature. Strength `(row, prio, ord)` goes live —
the deferred half of Henrik's ruling ("a Craft or AutoAmmo claim on a reserved slot
makes the reserving piece ineligible by the same rule") lands here, as one comparison,
not a second copy.

**Stage 5 — retire the collapse.** The flat top-level store becomes an explicit derived
cache of ladder heads (GUI previews and `gearcheck` migrate to `candidatesFor`);
`BuildDynamicSets` shrinks to filter+sort+normalize; marker strings expand at install.
Follow-ons unlocked, not scoped: `arbiter.preview(claim)` for GUI equip-now surfaces
("would this land, or be fought?"), immediate-equip paths routing through the
arbitration, the ADR 0002 twin collapse.

**Stage 6 — the MaxMP migration (the fold, ratified §10 item 3).** Last on purpose:
the constraint vocabulary is proven on simpler constraints first, and MP regressions
are the worst class to field-confirm (they show as mana quietly wasted over a session,
not as a wrong slot). Batteries become ladder claims at MaxMP's row; MP-hold becomes a
named constraint; movement yield and sticky pairs become view-reading gates;
`ctx.mpCeded`/`ctx.mpRespectLocks` — the last ctx-thread — die with the weave. Gated
behind band-behavior parity tests + goldens + a dedicated field campaign; the woven
code is deleted only after its replacement is field-confirmed.

> **Stage 6 status: SHIPPED on dev 2026-07-27 (engine v151, addon `27zm`) — code-complete,
> FIELD CAMPAIGN PENDING (the ratified gate).** The woven per-slot MP branch + the mp-stage
> post-pass are DELETED; MaxMP claims and applies through its registry row: band targets →
> the claim (`mpClaimFor` as the row's `claim`), and the apply runs the four gates —
> remove-respect (v91), movement yield (v96), sticky pairs (v93/v94, museum #7), RSlot
> eligibility (v78) — against the **same-dispatch view** (`ctx.planOut` for rows already
> applied + the strongest **unapplied above-rank claim** per slot, museum #9), then dresses
> via `equipResolved` at its rank. Ceding = apply order; lock-respect = the ordinary
> `respect('MaxMP')`; `ctx.mpCeded`/`ctx.mpRespectLocks` retired. The **mp-hold constraint**
> survives at the head of `POST_ORDER`: a worn no-band battery holds against an MP-lighter
> incoming piece unless the asking claimant (`who`) ranks at or above MaxMP. Supporting:
> the rank order HOISTS above the claim build (ranks exist before anyone claims —
> `ctx.rankOf`), `mpBands` reads it for the lock consult (a locked slot's rungs leave the
> threshold math, band parity kept), and `mpBands` memoizes per dispatch (one sample, one
> moment — the purity ruling). Bands + resolver family untouched. 4059 checks, Windows +
> WSL lua5.4. Execution log: `docs/design/maxmp-fold-plan.md`.

## 8. Performance & determinism

- **Steady state gets cheaper, not dearer.** Today: N active layers × (16-slot chain +
  5 post-passes) + N buffer sends per dispatch. Target: one 16-slot walk + one send.
- **The arbitration memoizes on the signature machinery that already exists** (the
  retrace sig): unchanged inputs → the previous plan, no walk at all. Ladders memoize on
  the rebuild latch. The fast path (uncontested slot, first rung passes) is the common
  case; the loop only spins on refusal, which is rare and short (ladders are a handful
  of rungs).
- **Determinism invariants, test-pinned:** `RSLOT_ORDER` slot walk; claims sorted by
  strength then row name then ord; no `pairs()` in any decision; ties favor the
  reserver (today's law, `:2704`); the fixed-point cap logged when hit.
- **Level authority:** `candidatesFor` and the arbitration read the same level the v134
  lesson pinned (`playerLevel`/`determineLevels`, override-aware) — one level, everywhere.

## 9. Risks, honestly

- **`/dl why` text changes at stage 3.** The goldens gate exists to catch exactly this;
  the diff is deliberate and reviewed, not incidental.
- **The weave.** MaxMP's fold-in (ratified, stage 6) is its own field campaign with its
  own rulings ledger. The design deliberately does not depend on it before that stage.
- **The fixed point.** Reservation chains (Body takes Legs takes nothing…) are bounded
  and ordered today; the claim-with-emptiness formulation must keep the "an ineligible
  piece reserves nothing" invariant (`:2680-2684`) or a piece could suppress on its way
  out. The v135 functions carry the tests for this; they migrate, not rewrite.
- **GUI preview drift between stages 1–5.** The Sets tab shows flattened names until
  stage 5; after stage 4 the worn truth may legitimately be rung 2 while the tab shows
  rung 1. Mitigation: the tab gains a "(fell to X — /dl why)" hint early, reading the
  trace.
- **Scope creep.** The one-state unlock (§2.6) invites collapsing every twin and every
  string seam at once. Staged deliberately; each stage ships alone.

## 10. The four rulings — ALL RATIFIED 2026-07-27 (discussed one at a time)

1. **Vocabulary — RATIFIED 2026-07-27** (discussed item by item, this session):
   **ladder** generalized (rungs; gates only remove) · **Claim widened** to carry whole
   ladders, submitted up front — no separate "Proposal" noun (Henrik independently
   proposed ladder-up-front while reading the fall/hold taxonomy) · **Refusal** with
   **fall**/**hold** · **contest** per slot (existing) + **arbitration** per dispatch
   ("settle" dropped: collides with the sync-settle hold) · **trace** as the returned
   decision record ("minutes" dropped as confusing; the existing `/dl why` trace deepens
   into it, "retrace" keeps its meaning).
2. **The cross-rank dominance law — RATIFIED 2026-07-27** (worked examples A–E were
   presented and accepted, including the two that change lived behavior):
   - **Across rows, rank wins outright** — the same ordering the slot contest already
     uses, asked about the reserved slots. **Within Triggers, priority** (ADR 0003 —
     v135's shipped behavior). **Ties favor the reserver** (v135's shipped law).
   - **The dominance comparison is `(row, prio)` — `ord` excluded**, so reordering
     rules in the file never flips a reservation.
   - **Only claims defend slots; worn pieces are not claims** (the Mindie ruling,
     generalized) — a beaten worn reserver is displaced by the server when the winner
     lands. This fixes the live claim-level bug where a worn floor reserver silently
     drops a higher row's claim (verified in the fallback `reservedDrops` worn arm).
   - Consequences accepted: pins' bespoke `ctx.pinReserved` + the naked-voids case
     retire into the general rule; a reserving piece can no longer bulldoze a locked
     slot; the drag list is the dominance authority ("according to you" = the rank
     list the player ordered). The pair law (ADR 0010) stays its own constraint —
     item 2 governs RSlot reservation only.
3. **MaxMP's end state — RATIFIED 2026-07-27: fold in.** Henrik, verbatim: *"Can we
   migrate this into our arbiter instead? Instead of purely being a ranker per slot and
   item, maybe we can call functions in arbiter to make this the aware one? Instead of
   having the logic outside of the arbiter?"* Ruled: **the Arbiter is the aware one** —
   comparative judgments (MP-hold, movement yield, sticky pairs) live *inside* the
   arbitration as constraint functions and view-reading gates, never woven outside it.
   The rank list stays the spine; constraints + the `view` are the awareness; purity
   holds because liveness (current MP, moving) enters as session inputs sampled once
   per dispatch — same session in, same plan out. Migration is the LAST stage
   (§7 stage 6), gated as written there.
4. **`/dl why` verbosity — RATIFIED 2026-07-27: depth on demand** (the chat form of the
   panel-text hover rule). Bare `/dl why` keeps today's one-screen budget — one line per
   contested slot with any fall folded inline and short
   (`Body: Gold Harness — Triggers Movement@25  [Royal Cloak fell: reserved Head]`);
   the uncontested-floor, Naked and Free-equip collapses are unchanged. The new
   **`/dl why <slot>`** prints the full contest for that one slot: every claim in
   strength order, every rung's verdict with its reason
   (`Royal Cloak (Idle@20) — fell: ineligible (reserves Head; Head owned by Craft,
   rank 4)`). "Inform by printing as little as possible" holds for the bare command;
   the arbitration's full conversation prints only when asked, about the slot being
   stared at.
