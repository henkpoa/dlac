# The two-way Arbiter — late binding, ladders, one settle per dispatch

> **Status: PROPOSAL (2026-07-27) — nothing here is built.** This is the dedicated hard
> look Henrik parked on 07-27 (*"too central and too big of a decision to just be made on
> a whim"*) and then asked for: *"take a hard look and see if we can in a scalable way
> move away from this legacy, where things talk to each other much better… check in with
> the Arbiter more often in a more open communication… to scale up the decision process
> considerably."* He has explicitly opened old decisions and rules for debate (§6).
> **No stage in §7 starts without his ruling.** When he rules, the contract in §4 should
> be recorded as an ADR (next free number: 0027).
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
  live state. Ladders are built free; the *settle* gates. Nothing here touches the
  picker.
- **Determinism laws.** `RSLOT_ORDER` walks, no `pairs()` in any decision, fixed tie
  rules (ties favor the reserver, `reserveVerdict` `:2704`), same-input-same-output.
- **The rank list UX** — one draggable list, restore-at-default-position (v122), floor
  and ceiling pinned. The registry survives; only what a row *contains* deepens.
- **ADR 0013** — the Oracle stays claim-blind: capability, never permission. The settle
  asks "can this be worn / is it owned"; only the Arbiter decides precedence.
- **ADR 0024's placement** — the Disabled filter stays at the write seam even after the
  settle also models it: the seam covers every caller the seam grows later. Belt and
  braces, deliberately.
- **`equipcore.planSet`** — the pure snapshot→plan resolver stays the executor exactly
  as is. It is the shape the whole redesign is aiming the *decision* layer at.
- **The perf envelope.** Default dispatches every frame. Whatever settles must be
  memoizable on a signature, like retrace already is.
- **Engine-native over commands** — stateless holds, nothing persisted, everything
  recomputed per dispatch. The settle is *more* of this, not less.

## 4. The target — one settle per dispatch

### 4.1 The one-sentence version

**Promote the pure model from explaining to deciding:** collect *proposals* (with
ladders) from every source, run *constraints* (with named refusal reasons) over one
deterministic walk, produce **one plan** and **one record of the conversation**, write
the plan **once**, and let `/dl why` print the record — the same object that decided.

### 4.2 Vocabulary (CONTEXT.md candidates, Henrik's call)

- **Proposal** — one source's wish for one slot: `{ slot, ladder, strength, source }`.
  The ladder is the ordered candidate list (often length 1); "the set changed on the
  fly" = the ladder is consulted at settle time, against live context.
- **Strength** — the one comparable: `(row, prio, ord)`. `row` = the Arbiter rank index
  (Triggers is simply the bottom row); `prio`/`ord` = ADR 0003 within the Triggers row,
  `0` inside claim rows. This single ordering is what unlocks dominance across rank —
  the deferred half of the v135 ruling.
- **Constraint** — a named validator consulted during the walk: reservation/dominance,
  the Range↔Ammo pair law, Sub↔Main pairing, usability (level/job/owned), sync-hold,
  locks, ceiling. Each returns a **verdict**.
- **Verdicts** — the refusal taxonomy, and the heart of "talk back":
  - `pass` — the candidate stands.
  - `fall(reason)` — this candidate is refused, **the same proposal's next rung is
    asked**. Reasons: `level`, `job`, `not-owned`, `ineligible` (reserves a slot a
    stronger proposal owns), `pair` (bolt under a bow — the ammo falls to the next ammo).
  - `hold(reason)` — terminal for the slot: write nothing, keep worn. Reasons: `locked`,
    `sync-hold`, `mp-hold`, `reserved-by <piece>` (the server will empty it; see the
    asymmetry in §4.5).
  - Naked's `remove` and Locks' `LOCK_HELD` stop being special-cased arms — they are
    ordinary proposals whose candidate is a sentinel, exactly as `arbResolve` already
    models them. The special rows become unspecial.
- **Settle** — the per-dispatch resolution: `settle(session) -> plan, minutes`.
- **Minutes** — the decision record: per slot, who proposed what, who was refused and
  why, who won at what strength. `/dl why` becomes a formatter over the minutes;
  `arbExplain`'s parallel model retires into it.

### 4.3 The contract, concretely

```lua
-- gear/settle.lua -- PURE (equipcore's sibling): no AshitaCore, no io, no globals.
-- session = {
--   order   = arbOrder,                    -- the rank rows, as today
--   rows    = {                            -- one per ACTIVE source (registry rows)
--     { name = 'Triggers', proposals = { { slot='Body', ladder={...}, prio=25, ord=3 }, ... } },
--     { name = 'AutoAmmo', proposals = { { slot='Ammo', ladder={rung1, rung2, ...} } } },
--     { name = 'Locks',    proposals = { { slot='Head', ladder={ SENTINEL_HELD } } } },
--     ...
--   },
--   reads   = { rslotOf=f, pairOf=f, levelOf=f, usable=f, worn=f, level=n, ... },
--   constraints = CONSTRAINTS,             -- ordered, named; data like POST_ORDER is today
-- }
-- returns plan    = { [SlotKey] = name | 'remove' | nil }   -- nil = engine says nothing
--         minutes = { [SlotKey] = { winner={source,name,strength},
--                                   refused={ {source,name,why}, ... },
--                                   held=..., }, ... }
function M.settle(session) ... end
```

- **Ladders are data by default, a function by escape hatch** (`ladder = f(view)`), for
  the few sources whose candidates genuinely depend on the contest (MaxMP's hold needs
  "what would win below me"; the `view` argument exposes the tentative winner under a
  given strength — that is the literal two-way channel). Data-first keeps the walk
  deterministic and the tests flat; the parked sketch's pure callback protocol
  (`propose/refuse` as the *only* interface) is rejected for the general case — a
  conversation of closures re-introduces "the answer depends on when you were asked,"
  which is the `pairs()` bug wearing a nicer suit.
- **The walk**: slots in `RSLOT_ORDER`; per slot, proposals sorted by strength; take the
  strongest proposal's first rung; run constraints; `fall` → next rung, then next
  proposal; `hold` → done, slot held. Reservation makes it a fixed point: a winner that
  reserves other slots injects a synthetic `reserved-empty` proposal into each reserved
  slot *at its own strength* — if something stronger already stands there, the reserver
  is refused `ineligible` instead and **falls to its next rung** (v135's two directions,
  now with the fallthrough v135 could not build). Refusals only accumulate, so the
  worklist terminates; cap the re-walk (3 rounds) and log a cap hit as a bug signal.
- **One write.** `M.dispatch` becomes: collect → settle → apply the one plan → one
  `engineEquipSet`. The equipengine buffer stops being the hidden merger; `planSet`'s
  satisfied-check sees the whole intent at once (fewer packets, quieter server — the
  same "don't spam the server" Henrik ruling that shaped the pair law).
- **Usability is a constraint, not a location failure.** Post-purge the settle can ask
  the oracle/ownedcache (injected, claim-blind): a name the executor could never locate
  is refused `not-owned`/`level` *during* the settle, where rung 2 is still alive —
  today it silently dies in `planSet`'s bag scan.

### 4.4 What each existing mechanism becomes

| Today | Becomes |
|---|---|
| flatten's pick (`utils:554`) | the ladder order (comparator kept; truncation retired) |
| `marker\|fallback` strings | virtuals are ladder *entries* resolved at settle (their manifest chains — `resolveVirtual`'s best-first walks — flow through instead of collapsing) |
| `reservedDrops` / v135 verdict + clear | the reservation constraint, all rows, strength-compared |
| `trinket-vs-ranged` + `trinketWornDisplace` | the pair-law constraint (ADR 0010's decision rules intact; scope widens from within-set to within-plan) |
| `craft-sub-guard` + pin-vs-craft special case | the pairing constraint (`subSlotAllowed` on the *plan's* Main, whoever proposed it) |
| `sync-hold` + `sync-hold-ammo` | one hold constraint (weapon slots + Range-reserving ammo) |
| `ctx.pinReserved`, naked-voids special case | gone — reservation is one constraint, Naked outranking Pins falls out of strength |
| locks / naked / locked set / disabled arms | ordinary rows with sentinel ladders (ceiling keeps its seam filter too) |
| `mpCeded`/`mpRespectLocks` weave | Phase 1: unchanged (see §6). End state: MaxMP proposals + an mp-hold constraint reading the `view` |
| `applyClaim` closures + reverse rank walk | gone — one plan application |
| `arbResolve`/`arbExplain` under retrace | *the decider*; minutes replace the parallel model |
| `/dl why` trace lines | a formatter over minutes — refusals finally get printed with reasons ("Body: Royal Cloak refused (reserves Head, owned by Movement@25) → fell to Gold Harness") |

### 4.5 The multi-slot asymmetry, stated once

Henrik's pain case deserves its law in one place: **a refused piece falls; a reserved
slot does not.** If the Kupo Suit (Body, 25) is dominant, Legs is `hold: reserved-by`
— *no* legs candidate may land, at any rung, because the server will strip whatever
goes there (falling down the Legs ladder would be re-deriving the flap). If the suit is
*not* dominant, the suit is refused `ineligible` and **Body falls to the next Body
candidate** — which is then itself dominance-checked (rung 2 may also reserve). Both
directions are one rule at one altitude, with fallthrough on exactly one side.

## 5. Why this scales

- **Adding a claimant** = one registry row + one proposals function. It inherits
  reservation, pairing, usability, locks, ceiling, attribution — all nine §2.2
  mechanisms — without meeting any of them. N×M pairwise patches become N sources + M
  constraints.
- **Adding a constraint** = one named validator with a reason string. It automatically
  applies to every source, with its refusals printed.
- **"Check in with the Arbiter more often"** = every Default settles against live
  context (memoized when nothing moved), and the `view` channel lets a source's policy
  read the contest instead of being woven through `ctx`.
- **Testability** — the review's headline finding was that `M.dispatch` is called zero
  times by any test. `settle(session)` is the `equipcore.planSet(set, snapshot)` shape:
  plain tables in, plain tables out. The path every feature rides becomes drivable
  headless for the first time, and the minutes make every assertion self-explaining.
- **Explainability is structural.** Today a silent nil is the failure mode (v134's
  "total silent failure"). In the settle, *nothing* is dropped without a recorded
  reason — the bug class "a slot quietly stopped" becomes grep-able.

## 6. Old rules re-examined (the debate Henrik invited)

| Rule | Verdict | Why |
|---|---|---|
| ADR 0006 "builder plans, engine decides" | **Keep, complete** | The flattener was a third actor deciding early. Retire its *pick*, keep its *filter/sort*. Addendum 2's "post-pass on the final names" doctrine retires with the post-passes: reservation declared as proposals replaces "each later EquipSet must declare what it takes away." |
| ADR 0012 claim = `{slot->name}` | **Revise** | Becomes `{slot -> ladder}` (+ optional function). The recipe comment at `dispatch.lua:3652-3667` ("exactly TWO things and NO new arm") finally becomes true — today it is 2 things plus 11 hunks of bookkeeping (the review measured 15 hunks for Chocobo). |
| "MaxMP stays woven" (ADR 0012) | **Keep for now, fold only with evidence** | The weave is the hardest, most field-tuned logic (bands, sticky pairs, movement yield — a rulings ledger of its own). The settle must not *require* folding it: MaxMP keeps its claim row for precedence and its woven equip until stages 0–4 prove the constraint vocabulary. Fold-in is a stage 5+ candidate, not a dependency. |
| ADR 0010 trinket contest "within-set only" | **Revise scope** | "Within-set" was the honest scope when only one table was visible at a time. With one plan, the natural scope is within-*plan* — same decision rules (higher level wins the trinket contest; Range is HANDS OFF), wider, and the worn-displace arm stays. |
| The Triggers floor as a special phase | **Revise** | The floor becomes the bottom rank row with internal `(prio, ord)` strength. This is precisely what v135 lacked ("a priority number that never modelled it") — after unification, the clear at `:6041` and the "extend across rank later" caveat both retire. |
| `marker\|fallback` strings | **Retire gradually** | A 2-rung ladder encoded for a state boundary that no longer exists. Authoring format can keep the strings (profiles on disk); the in-memory store expands them to ladder entries at install. |
| Per-claim `equipResolved` + N sends | **Retire** | One plan, one send. All production callers are dispatch-internal (verified), so the consolidation is contained; `M._equipResolved` stays as a seam for the within-set passes' tests during migration. |
| The attribution parallel model | **Retire into minutes** | One machine decides *and* explains. The AR*/LV* tests move to the settle with their assertions intact. |
| Disabled at the write seam | **Keep** (also modeled in settle) | ADR 0024's argument — the seam covers callers the rank walk never sees — survives the redesign verbatim. |
| Oracle twins in dispatch (ADR 0002) | **Flag for later** | "The engine has no catalog" died in the purge; the byte-identical twins (`decodeEquipIndex`, `AMMO_BAGS`) could collapse into the one door. Separate cleanup, not scoped here — noted so the review's GRD-parity pins are re-aimed deliberately, not by accident. |
| AutoAcc stays within-set (Henrik 07-21) | **Keep** | It is a candidate *transform* inside a proposal's ladder, not a claimant. The settle changes nothing about it. |

## 7. Staging — every stage ships whole, field-confirmed before the next

Deviations from the parked sketch are marked ⚠ with the reason. Each stage is a normal
dev commit train (branch law), version-bumped when behavior changes, promoted
whole-or-not.

**Stage 0 — the registry rows (candidate #1 as originally written).** One `CLAIMANTS`
table — `{ name, ensure, active, overlayFor, slots, sig }` — that the ensure block, the
bails, the claims map, the signature and the applyClaim walk all iterate. Zero behavior
change, pinned by AR*/LV* + goldens. ⚠ *Moved from the sketch's stage 4 to first:* it
pays for itself standalone (15 hunks → 1 row, the silent-bail class dies), it shrinks
`M.dispatch` before surgery, and the settle then lands against rows instead of eight
locals. If everything after this stalls, stage 0 was still worth shipping.

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

**Stage 3 — extract `gear/settle.lua` and make it the decider.** Pure module; migrate
constraints one at a time in POST_ORDER's own order, each pinned by the tests that
already exist (AK*, AKD*, TR*, TB*, AM*, PL*, LS*, AR*, LV*): reservation first (it is
already pure — `reserveFloor`/`reserveVerdict` *are* the seed), then pair law, then the
guards, MP weave untouched. Dispatch's apply loop becomes collect → settle → one apply →
one send. `/dl why` reads minutes (deliberate, reviewed text diff — the goldens gate
moves with it). This is the stage where decide-and-explain become one machine.

**Stage 4 — claimants propose ladders; dominance across rank.** Registry rows gain
`proposals()`; AutoAmmo emits its level ladder (the v134 gap class ends), craft/HELM/
fish/choco pass their manifest chains through instead of pre-resolving; pins/locks/
naked/locked-set stay single-rung by nature. Strength `(row, prio, ord)` goes live —
the deferred half of Henrik's ruling ("a Craft or AutoAmmo claim on a reserved slot
makes the reserving piece ineligible by the same rule") lands here, as one comparison,
not a second copy.

**Stage 5 — retire the collapse.** The flat top-level store becomes an explicit derived
cache of ladder heads (GUI previews and `gearcheck` migrate to `candidatesFor`);
`BuildDynamicSets` shrinks to filter+sort+normalize; marker strings expand at install.
Follow-ons unlocked, not scoped: `settle.preview(proposal)` for GUI equip-now surfaces
("would this land, or be fought?"), immediate-equip paths routing through the settle,
the ADR 0002 twin collapse.

## 8. Performance & determinism

- **Steady state gets cheaper, not dearer.** Today: N active layers × (16-slot chain +
  5 post-passes) + N buffer sends per dispatch. Target: one 16-slot walk + one send.
- **The settle memoizes on the signature machinery that already exists** (the retrace
  sig): unchanged inputs → the previous plan, no walk at all. Ladders memoize on the
  rebuild latch. The fast path (uncontested slot, first rung passes) is the common case;
  the loop only spins on refusal, which is rare and short (ladders are a handful of
  rungs).
- **Determinism invariants, test-pinned:** `RSLOT_ORDER` slot walk; proposals sorted by
  strength then row name then ord; no `pairs()` in any decision; ties favor the
  reserver (today's law, `:2704`); the fixed-point cap logged when hit.
- **Level authority:** `candidatesFor` and the settle read the same level the v134
  lesson pinned (`playerLevel`/`determineLevels`, override-aware) — one level, everywhere.

## 9. Risks, honestly

- **`/dl why` text changes at stage 3.** The goldens gate exists to catch exactly this;
  the diff is deliberate and reviewed, not incidental.
- **The weave.** If MaxMP's fold-in is ever attempted, it is its own field campaign with
  its own rulings ledger. The design deliberately does not depend on it.
- **The fixed point.** Reservation chains (Body takes Legs takes nothing…) are bounded
  and ordered today; the synthetic-proposal formulation must keep the "an ineligible
  piece reserves nothing" invariant (`:2680-2684`) or a piece could suppress on its way
  out. The v135 functions carry the tests for this; they migrate, not rewrite.
- **GUI preview drift between stages 1–5.** The Sets tab shows flattened names until
  stage 5; after stage 4 the worn truth may legitimately be rung 2 while the tab shows
  rung 1. Mitigation: the tab gains a "(fell to X — /dl why)" hint early, reading
  minutes.
- **Scope creep.** The one-state unlock (§2.6) invites collapsing every twin and every
  string seam at once. Staged deliberately; each stage ships alone.

## 10. Open questions for Henrik

1. **Vocabulary.** Keep Claim/Arbiter/rank and add *ladder / refusal / settle /
   minutes*? (CONTEXT.md entries ride the ruling. "Minutes" can be plain "decision log"
   if it reads too cute in chat.)
2. **Stage 4's comparison law.** Strength puts a prio-25 trigger *above* every claim row
   below Triggers' rank only within its own row — across rows, rank wins outright, as
   today. Dominance across rank therefore reads: *any* claim-row proposal beats *any*
   floor proposal on a contested reservation (rank order), while floor-vs-floor keeps
   priority. Confirm that is the ruling's intent ("am I dominant in both pieces
   according to you?" — where "you" is now the whole rank list).
3. **MaxMP's end state** — fold in eventually, or woven permanently as the one blessed
   exception? (Recommendation: decide after stage 4, with the constraint vocabulary
   proven and the minutes showing where the weave actually bites.)
4. **`/dl why` verbosity** — refusal reasons make the trace richer; is the current
   one-screen budget a constraint, or may contested slots grow a line each?
