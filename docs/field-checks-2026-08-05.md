# Field checks owed — against `v2026.08.05a`

**Reload first.** `/addon reload dlac`, then check the load banner says **`2026.08.05a`**.
If it says anything else, stop — you are testing a different tree than this list describes,
and every answer below becomes unreliable.

This is the whole of the debt on `main`: four features that have **never run in game**, plus
a tail on Job Helpers that is partly closed. Sourced from `docs/HANDOFF.md`, which stays the
authoritative ledger — this file is the running order, not a second record.

**When something is wrong, do this before describing it:**
`/dl mark <a few words>` at the moment it happens, then `/dl report` when the run is over.
The report captures the decisions **already in memory** when you press record, so marking
first and reporting after covers the moment. That file answers questions a description
can't, and it is worth more than a careful account of what you saw.

---

## Session A — Mode Locks (run this one first)

**Why first:** it is a claimant sitting directly above `External` in the priority ladder, so
if it misbehaves it misbehaves over *everything*. It is also the only feature on this list
that can hold your gear hostage. The other three produce wrong information; this one can
produce a wrong character.

**Setup:** your own Weapon cycle, Main + Sub locked under the melee value.

- [ ] **A1 — the lock holds.** Cast something and use a WS. Weapons must not move on
      Precast, Midcast or WS.
- [ ] **A2 — the lock releases.** Flip the cycle off. Weapons come back **with no reload**.
- [ ] **A3 — the Trigger Monitor** shows a `locks` line naming the held slots.
- [ ] **A4 — the Arbiter Monitor's** Main cell is **gold**; hovering it reads
      `Mode lock (rank 11)` sitting over `Triggers`.
- [ ] **A5 — contention.** Two modes locking one slot: the one flipped **first** keeps it,
      the other shows as **queued**.

> **Before reporting "the lock did nothing":** check that the set the lock names actually has
> an entry for that slot. A lock naming an empty slot claims nothing *by design* and the
> trigger keeps the slot — the edit window flags that red. This is the most likely false
> alarm in the whole file.

---

## Session B — NM Compendium

**Setup:** Uleguerand Range, the Bonnacon camp. Check (1), index parity, is already
confirmed from your pre-GUI Bonnacon run — that was the one no test could make, and it held.

- [ ] **B1 — counts key on INDEX, not name** *(the sharpest one)*. In Uleguerand the Buffalo
      at indices **26–29 are not placeholders**; **354–359 are**. Kill both kinds. Only the
      second may move the counter. If killing a 26–29 Buffalo moves it, the counter is
      matching on name and every count in the addon is wrong.
- [ ] **B2 — staleness.** Zone out and back. The percentage must **vanish**, not persist.
- [ ] **B3 — persistence.** `/addon reload dlac`. The counts must survive it.
- [ ] **B4 — the `apply` verb** with FilterScan loaded: `/dl nm <name> apply`.
- [ ] **B5 — cooldown/primed** readout after an actual NM kill.
- [ ] **B6 — the menu row's icon** renders as the dragon and not a text button. No suite can
      ever see this one — `filetex` is nil headless — so this check is the only evidence
      that will ever exist.

---

## Session C — the two small ones

Both are one round each, and neither needs a particular camp.

- [ ] **C1 — Wardrobe audit.** `/dl unused scan`, then open the window. Does the split match
      what you know about your own bags: the four categories (unused / set-nobody-points-at /
      lockstyle-only / helper-picked) landing where you'd put them by hand?
- [ ] **C2 — Dual Wield gear rule.** On a job with the trait: the Suppanomimi should be
      offered as a **candidate** only while the trait is up, and rank normally when it is —
      no tier bump, no priority jump. Flip sub-jobs to see it appear and disappear. `/dl dw`
      prints the trait bit itself, which is already field-proven; what's unproven is the
      **gate** reading it.

---

## Session D — Job Helpers tail (BST)

Rounds 5, 6 and 7 are closed: death detection, the recast read and the fallback pick are all
field-confirmed. What's left has never been exercised.

- [ ] **D1 — the Summon set** actually landing on a summon.
- [ ] **D2 — the bindable key** and `/dl jh <module> <action>`.
- [ ] **D3 — the searchable dropdowns.**
- [ ] **D4 — once-per-zone** "no pet food" line (it should say it once, then stay quiet).
- [ ] **D5 — the jug cap.**
- [ ] **D6 — the friend's original report**: the Dynamic sets picker. Nobody has confirmed
      that fix, and it is the oldest open item in this file.

**Out of reach at BST 21:** Bestial Loyalty and food tiers ≥ Beta. Leave them; they need
levels, not a test.

> **The open CHR question — worth one deliberate look while you're on BST.** The wiki's own
> advice (*"check CHR in case of latency"* after Ready) reads as **CHR sampled at Ready, not
> at summon** — the opposite of the premise the Summon set was built on. The server clone
> settles nothing: `CalculateJugPetStats` has no CHR term at all on `stable`. If Ready is
> right, the Summon set belongs on an ordinary `Ability` trigger matching Ready and needs no
> new code at all. This is a *design* answer hiding in a field session, which is why it's
> worth the detour.

---

## Session E — one-look confirmations

Cheap, and none of them need a setup. Fold into whatever you're already doing.

- [ ] **E1** — the Sets tab's DRK `Idle` set: the Range tile should carry the pair.
- [ ] **E2** — an E-Box crate with the Teleports float both on screen at once.
- [ ] **E3** — rebuild the MP/Refresh set; confirm Dalmatica and the head land.
- [ ] **E4** — the pre-flat Ammo handling, re-tested (`2026.07.28n` handled or reported all
      three cases).

---

## Session F — the seed diagnostics (needs a BROKEN install, not a healthy one)

Added `2026.08.05a`, off a friend's clean install that never got its starter trigger file.
This one is different from the rest of the list: on a healthy install it must produce
**nothing at all**, so a green run proves only half of it. The real check needs the broken
machine.

- [ ] **F1 — the healthy install is silent.** On a working character, `/dl check` shows
      **six** addon lines and `NO ISSUES`. No baseline row. If a seventh line appeared on a
      healthy install, the gate is wrong and the row will get skipped by everyone.
- [ ] **F2 — the load report still says `0 failed`.** The spine probe adds six modules to the
      ledger, so the total goes **up** (dispatch, profiles, setupui, triggersui, triggermodel,
      uihost) while failures stay at zero. A failure here on a healthy tree means the probe
      itself is loading something that was never meant to load in this state — back it out.
- [ ] **F3 — on the broken install:** the auto-setup line now names the missing gate and the
      seeder's reason, and `/dl check` carries the same verdict as a seventh line. That line
      is the answer to the question that cost four rounds.
- [ ] **F4 — `/dl report` ships it.** The baseline verdict must be in the bundle, not only in
      chat. The whole point is that the artifact answers without the player narrating.

**What we still do not know** about the original case: whether `dispatch` fails to load in his
addon state, or whether `profiles\Default\triggers\` was never created. F3 answers it in one
line. Until then the cause is open — the hand-made `RUN.lua` silenced the message without
fixing anything, and he still cannot edit triggers.

---

## What this unblocks

These are the gate on a real v1.0, not the tagging or the tooling. A release is a promise the
thing works, and right now four features on `main` can't back that promise because nobody has
run them.

Two of these sessions also feed the **Ashita acceptance** question, which is gated on one
reviewer complaint — *too much stuff*. The NM Compendium is the largest non-gear thing in the
addon, and extracting it to its own addon stays cheap: its four modules need dlac only for
chatfmt, the zone table and location. **Session B closing is not the only way to retire those
six checks** — extraction retires them from dlac's ledger outright. Worth knowing before you
spend an evening in Uleguerand.
