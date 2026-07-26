# 0024 — Free equip is the ceiling, not a claim

2026-07-26, requested by Henrik (*"I want to have similar feature as /lac disable & lac disable
&lt;slot&gt; into dlac… simply make it claim the slot / slots, then don't do anything at all with it,
so people can free equip all they want without DLAC intervention"*). Engine v129.

## Context

`/lac disable` exists so a player can take the automation off their gear and equip by hand. dlac
had no equivalent, and had quietly lost the borrowed one: the Equipped tab's **Free equip**
checkbox fires `/lac disable`, which sets `gState.Disabled` in LuaAshitacast — and under the native
engine (ADR 0015, the standing direction since 2026-07-23) LuaAshitacast is not the thing equipping
you. The switch that says *"stop auto-swapping my gear"* did nothing at all in the mode we ship.
It had gone inert without a single line of code changing, and nothing said so.

Two existing mechanisms look like they could carry this, and neither can:

- **A slot lock cannot.** `M.locks` is a veto *inside* the rank walk (ADR 0012 step 3): a claimant
  ranked above `Locks` punches straight through it, and that punch-through is the Claim Priority
  list's whole promise. Naked, Pins and anything a player drags above the row would all dress a
  "locked" slot. "Do not touch this" cannot be said by a thing four other rows may overrule.
- **`gState.Disabled` cannot.** It is LAC-only and sits *below* the engine — the standing dlac
  ruling from issue #58, restated in ADR 0021's rejected alternatives. Writing it splits the two
  engines and fences off exactly what the Priority list is supposed to arbitrate.

There is also a shape question the codebase had already half-answered. Every Arbiter row wins a
slot **in order to put something in it** — even Naked, whose `'remove'` is an instruction to strip.
A row that wins a slot in order to write *nothing* is a different kind of thing.

## Decision

1. **Free equip is the CEILING — the mirror of the Triggers floor.** `ARB_ORDER_DEFAULT` gains
   `Disabled` at the front and both ends of that list become invariants rather than rankings:
   the claims dress *over* `Triggers`, and nothing dresses *through* `Disabled`. `M.arbOrder`
   places both itself, so a hand-mangled file — and **every** `arbstate.lua` written before v129,
   which omits the row entirely — still gets a ceiling. `arbwatch.FIXED` gains it too, and
   `moveClaimant` refuses both directions: picking the row up, and swapping a neighbour *onto* it.
   This is what makes Henrik's "over EVERYTHING, even /dl naked" a boundary rather than a default
   someone can undo.

2. **It is enforced at `engineEquipSet`, the one write seam — not in the rank walk.** The obvious
   home was `equipResolved`'s per-slot chain, next to the lock strip, and it is not enough: the
   whole-table post-passes that run *after* that chain write slots the set never named
   (`mp-stage`'s battery, `trinket-vs-ranged`'s worn-Ammo displace), so a slot nil'd early is put
   straight back a few lines later. One filter on the way out covers the per-slot chain, every
   post-pass, the Triggers floor, and any caller this seam grows later. `POST_ORDER` is untouched.

3. **The claim is registered for ATTRIBUTION ONLY.** `claims['Disabled']` exists so `/dl why` and
   the Priority panel can name it, and — registered above the `mpCeded` computation — so woven
   MaxMP cedes a disabled slot for free instead of needing a special case. Its `applyClaim` closure
   equips nothing and could not: there is no item, and no unequip either. It is the one entry in
   that table that only writes a trace line.

4. **It claims only the disabled slots, not all sixteen.** The opposite of ADR 0021 rule 4, and for
   the opposite reason: Naked must claim every slot because an unclaimed one keeps whatever a
   lower-ranked layer wrote into the buffer. Nothing is applied here, so there is no buffer to
   defend — and claiming sixteen would make `/dl why` say something untrue.

5. **The comparison is case-INSENSITIVE.** The vocabulary arrives in both cases: sets and claims
   are canonical (`Main`), `/dl lock` and this command are lac-case (`main`), and
   `gear\equipcore.lua`'s `SLOT_ID` map is case-**sensitive**. A raw-key compare would disable a
   slot in one engine and silently miss in the other — the divergence NK3 exists to catch. Keys
   starting `__` are set metadata and pass through untouched.

6. **`/lac disable`'s grammar, deliberately.** `/dl disable [slot|all]`, `/dl enable [slot|all]`,
   bare = all sixteen, plus `/dl disable off` and `/dl disable <slot> off` so nobody has to guess
   which release word works. Never a toggle: typing "disable" must not be the thing that re-enables
   a slot (ADR 0021's rule for the word "naked"). `M.setDisabled` is shaped exactly like
   `M.setLock` — same vocabulary, same `all` fan-out, same nil-for-unknown-slot — because to a
   player these are two settings on one row of the same gear menu.

7. **Lifetime is `M.worldWatch`'s** (Henrik, 2026-07-26, confirming the recommendation): a main job
   change or leaving the world releases it, and it is never written to disk — the one rule v124
   gave all three ways of deliberately holding gear still. It survives an engine self-swap, for
   `M.locks`'s reason one step stronger: a `git pull` firing the 2s content check must not hand
   your slots back while you are mid-swap in the gear menu. Mirrored to `modestate.lua` as
   `__disabled`, inside the reserved `__` namespace `loadModeState` skips, so it can never be
   restored — logging in with three slots silently inert is ADR 0021's worst outcome wearing
   different clothes, and quieter.

8. **The Equipped tab's "Free equip" now drives THIS**, and is drawn from the engine mirror rather
   than a remembered addon-side flag. `/dl disable` from chat and the job-change release both have
   to move that checkbox, which the retired `ui._freePrev` edge-detect could not do. `ui.freeEquip`
   survives as a per-frame copy for one job: while free equip is on, clicking an alternative goes
   out as the game's native `/equip`.

9. **AMENDED 2026-07-26, same day, on Henrik's first field run — the chat output is ONE LINE.**
   (*"Works, but please remove all the text. Just say stuff like 'Hands disabled - enable by
   /dlac enable hands'."*) The five-line arm message stated precedence, lifetime, both release
   doors and what "no equip and no unequip" means. Every one of those has a better home that
   already existed — precedence is the Claim Priority panel, the live state is `/dl prio`, and
   what actually happened to a slot is `/dl why`. A chat line is for the **acknowledgement**.

   What survives the cut is the release door, because an ack you cannot undo is worse than a
   paragraph: `Hands disabled - enable by /dlac enable hands`. The lines say **`/dlac`**, the
   long prefix, because it is the form Henrik reaches for and `argStart` has always accepted
   both — `CMD17c`–`CMD17f` drive `/dlac` end to end so that stays true. The tests pin the
   exact strings *and* the line COUNT (`CMD16c`, `CMD18f`): terse is the requirement, and a
   count is the only thing that can catch prose creeping back in.

Extends ADR 0012 (a second pinned row, and the first claim with no apply) and ADR 0021 (shares its
watch; inverts its claim-all-sixteen rule, with the reason). Supersedes nothing.

## Consequences

- **Naked can no longer strip a disabled slot**, and says so at the moment you type `/dl naked`
  rather than leaving you to run `/dl why`. The Equipped tab's Naked switch renders unavailable
  when free equip owns all sixteen — the same treatment it already had for LAC's fence, now a
  stated rule in both engines instead of LuaAshitacast's accident.
- **The Priority panel gains a row nobody can drag.** That is the point, and the hover says so
  outright ("This row cannot be moved. Every other row is a ranking; this one is a boundary")
  rather than leaving a player hunting for a handle that is not there.
- **`/dl why` collapses it to one line**, Naked's treatment for Naked's reason — it can claim up to
  sixteen slots, and `/dl why` is exactly what someone runs when a slot has stopped moving. The
  line goes *first*, because when free equip is on it is the answer to the question that was asked.
- **A disabled slot is invisible to the trust stamps and the plan-satisfied short-circuit** only in
  the sense that nothing is ever sent for it. `equipResolved` still resolves the slot, and its
  return value still names it for `slotSrc` attribution; the Arbiter's own resolve is what makes
  `/dl why` correct, because `Disabled` outranks the floor.
- **`/lac disable` still exists and still fences LAC below the engine.** Nothing dlac ships sends
  it any more, but a player who types it themselves gets the old behaviour, and the `/dl naked`
  warning that counts `gState.Disabled` slots is still there for exactly that case.
- **Free equip on ANY slot draws the checkbox checked.** The box means "free equip is in effect",
  and the red line beside it says how much — "dlac is off your gear" at sixteen, "N slot(s) are
  yours" below that. A tri-state checkbox would have been more precise and less readable.
- **Unchecking the box still fires `/dl lock all off`.** Unchanged from the old wiring: leaving
  free equip is a "hand control back to the engine" gesture.

## Alternatives rejected

- **A draggable `Disabled` claimant at rank 1** — one drag away from a player wondering why the
  slot they told dlac to leave alone is being dressed by their pins. The exception mechanism ADR
  0021 rule 6 prizes for Naked is a defect here: "hands off" has no meaningful degree.
- **`M.setLock` with a new absolute flag** — two kinds of lock on one row with different
  precedence, which is the confusion ADR 0022 decision 2 spent a paragraph avoiding in the other
  direction.
- **Writing `equipengine.state.disabled`** (the unwired native twin, present since v111) — the
  right *semantics* (`equipcore`'s plan already skips a disabled slot) but native-only, so legacy
  mode would silently keep swapping. The seam filter gets both engines from one line.
- **Filtering in `equipResolved`'s per-slot chain** — see decision 2. It looks correct, tests
  green on a set the post-passes do not touch, and leaks the first time MaxMP puts a battery in a
  slot the player disabled.
- **Persisting it to disk** — the failure it creates is worse than the friction it saves: a slot
  that quietly does not swap, on a login the player has forgotten setting up.
- **Blocking the slot at `gear\equipcore.lua`'s plan builder** — deeper than the seam and reachable
  only in native mode, and it would fence the slot off from `/dl why`'s attribution too.
