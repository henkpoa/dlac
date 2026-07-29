# 0030 — A module owns initiation: the Action sequence claims, verifies, fires, releases

Accepted 2026-07-29. Records the load-bearing design stance of PRD #135 (Job Helpers), built in
issues #138–#141 and deferred out of ADR [0028](0028-job-helper-modules.md) until the sequencer
slice existed. 0028 records the **module system** — a module is a folder, identity is the folder
name, `api` is checked loudly, containment is structural, one folder = one unit of server
approval. This ADR records the other half: **how a module is allowed to act**, and why the acting
runs through one shared, serialized sequencer instead of through the modules themselves.

## Context

dlac's normal path is **reactive and it is timely.** The Native engine blocks the outgoing action
packet, equips precast, re-injects, and the action lands with the gear on — field-confirmed
2026-07-29 by a second tester, for a player-pressed Reward. So the sentence the PRD and the first
draft of this decision leaned on — *"an instant ability cannot be caught reactively; by the time
anything sees it the ability has left"* — is **false on this server**, and CONTEXT.md now lists it
under *Avoid* on the **Action sequence** entry. It is recorded here rather than quietly dropped,
because the design it justified survived the falsification while the justification did not, and a
reader who finds the old sentence elsewhere needs to know which one the code answers to.

The two reasons that do hold are both about *who starts the act*, not about swap timing:

1. **Initiation.** The behaviors PRD #135 asks for fire on the *module's* own signal: a pet
   crossing an HP threshold, a pet dying. There is no player action to hook, so there is no
   outgoing packet for the engine to block, and no Trigger can match a moment the player did not
   create. Something must decide to act, and that something is the module.
2. **The equip precondition.** Reward consumes the food that is **worn**; Call Beast and Bestial
   Loyalty read the jug that is **worn** — the server takes the species from the ammo slot. An
   empty or wrong Ammo slot can make the server refuse the act *before* any precast could dress
   it. The gear is not the act's costume, it is the act's **precondition**, and a precondition has
   to hold before the command is issued.

Once a module initiates, a third question appears that a player pressing a macro never asks:
**what happens if the gear did not land?** A player sees their own ammo slot. An automatic act
does not, and the failure it produces is silent item loss — the worst failure class this feature
can have.

## Decision

**A module owns initiation, and every act with an equip precondition runs as an Action sequence**
(CONTEXT.md, *Action sequence*; `feature/actionseq.lua`):

1. **claim → verify worn → fire → release**, with `refused(reason)` and `aborted(reason)` as the
   two failure exits. The claim is ONE Claim — an optional named Set's slots ∪ specific items —
   registered with the **Arbiter** like any other, never equipped directly.
2. **Never fire bare.** The command is sent only after every slot the request marks `need` reads
   worn, and exactly once (a latch, not a hope). Worn state is read through the engine's own worn
   reader, the gear oracle's twin — not through a second decode.
3. **A definitive blocker on a needed slot is a loud refusal**, not a bare fire: Locks, **Free
   equip**, or a senior claimant winning the slot means the act does not happen and the player
   gets one line naming the blocker. **Gear that never lands inside the timeout aborts**, and
   nothing fires.
4. **One sequence is live at a time, addon-wide, and a started sequence is never preempted.** A
   request arriving while one runs is refused, naming the holder. Two requests contending in the
   *same* resolution step resolve by the current job's **module order** — the row order of that
   job's section on the Job Helpers tab, which is the player's own drag order — and the loser is
   refused loudly.
5. **Every module's sequences ride ONE shared claimant row:** identity `JobHelper`, rendered
   **"Job helper"** through the display-label seam, status text naming the live module and act
   ("BST: Reward"). Default rank directly below **Locks** — above every standing Gear helper,
   below Locks, Naked and Free equip — draggable, and remembered **per job**.
6. **Acks are one line.** Success is silent. A refusal or an abort is exactly one chat line naming
   the blocker, and a **Retry lockout** bounds how often a rule may attempt — and therefore how
   often it may speak. A hold that attempted nothing (a sequence already running; an ability still
   on cooldown) never arms it, and the cooldown hold is silent, because the button it mirrors is
   greyed out and silent too.
7. **Release restores by re-arbitration**, not from a saved snapshot: dropping the claim kicks a
   dispatch and the next arbitration re-dresses the slots. The sequencer owns no gear memory.
8. **Composition is supported and is a first-class case.** Because reactive gear *does* land, a
   player's own Reward-gear Trigger plus a module claim of the food alone is a fully valid setup:
   the Trigger dresses gear at precast, the claim guarantees the precondition. This is why `need`
   is the consumed slot alone and the optional set dresses best-effort — every extra *needed* slot
   is one more chance for a senior claimant to refuse the whole act.

## Considered and rejected

- **Reactive only — let the player press it, let a Trigger dress it.** The honest alternative, and
  the one the falsified timing claim used to dismiss. Rejected on **initiation**: the rules PRD
  #135 asks for have no player action to hook, so "the player presses it" is not a smaller version
  of the feature, it is the absence of the feature. And rejected on the **precondition**: a
  Trigger dresses at precast, which cannot guarantee the ammo slot holds the food *before* the
  command is issued. Not rejected as too slow — and the composed case (player Trigger + food-only
  claim) is explicitly supported, above.
- **Equip and fire in the same beat — no verify.** Simpler, and it is what a hand-macro does.
  Rejected because an equip can be refused after the fact (a lock, Free equip, a senior claimant,
  a level or job gate, a bag that no longer holds the item), and the act then spends the *wrong*
  worn item or fails outright with no explanation. Verify-then-fire is exactly the difference
  between a chat line and a wasted jug; the whole feature's worst failure is silent, and this is
  what makes it structurally impossible.
- **A sequencer per module, or concurrent sequences.** Rejected: two live sequences mean two
  claims and two sends in one dispatch, which breaks the standing "one claim, one send" law, and
  they contend for the same scarce resource anyway (the Ammo slot is where both BST acts live).
  Serializing makes contention explicit, explainable and losable-with-a-reason instead of racy.
- **Preempting a running sequence when a higher-priority one arrives.** Rejected: a running
  sequence has already claimed and may be one tick from firing, and interrupting between verify
  and fire is precisely how an act fires bare. Priority decides *simultaneous* contenders; it
  never interrupts. Losers are refused, not queued ahead.
- **One claimant row per module.** Rejected: Claim Priority is a player-facing list, and N
  installed modules would mean N rows to rank for a distinction most players do not have — while
  `/dl why` would gain a row that is idle almost always. One row whose status names the live
  module and act keeps both surfaces answerable.
- **Equipping directly and skipping the Arbiter.** Rejected outright: it punches through Locks,
  Naked and Free equip — the three things a player has explicitly told dlac to respect — and
  produces gear `/dl why` cannot explain. Claim, do not commit.
- **Ranking the row above the player's holds** (so a sequence always wins). Rejected: an explicit
  player hold outranks an automatic act, always. A blocked sequence refuses.
- **Retrying an aborted sequence automatically.** Rejected for this train: a death edge is spent
  once, a verify timeout means the world disagreed with us, and a retry loop is how one bad state
  becomes a stream of commands. The abort is loud; the player decides.

## Consequences

- **Never-fire-bare is structural, not a discipline.** The only place a command is sent is behind
  the verified-worn gate, so "it fired with the wrong ammo" cannot be reached by adding a caller.
- **The same path serves the button and the rule.** "Reward now" and the automatic rule are two
  requesters of one implementation, which is why their refusal behavior is identical by
  construction rather than by two test suites agreeing.
- **Only one helper acts at a time.** A second module's act waits, or is refused with a reason.
  Accepted: contention is rare, and when it happens the player can see it and re-rank the section.
- **An act costs a verify window** (up to the request's timeout) between decision and command, and
  the claimed slots are dlac's for that window plus a short post-fire hold. The gear then restores
  on the next arbitration — one extra dispatch, not a snapshot restore.
- **Two modules' acts cannot be ranked against each other in Claim Priority** — they share one
  row. They are ranked on the Job Helpers tab instead, per job, which is where a player already
  answers "which of my helpers matters more".
- **Hard to reverse.** The shared row, the per-job rank anchor, the config format, the module
  contract and every rule's "ask, do not equip" shape all encode this stance. Undoing it is a
  redesign, not a refactor — which is why it is an ADR.
