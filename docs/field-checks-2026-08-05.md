# Field checks owed

**Reload first.** `/addon reload dlac`, then check the load banner matches `addon.version`
at the top of `dlac.lua` **in the tree you pulled**. If they disagree the reload did not
take, and you are testing a different build than this list describes — stop, because every
answer below becomes unreliable.

*(Deliberately not a hardcoded version number. This line named one for the first three
versions of this file and was stale in all three, which is worse than useless: a check that
lies tells you to abort a session that was fine. The two things that must agree are the
running addon and the checkout — so compare those, and the line never rots.)*

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
- [ ] **E5** — the new **P** button beside the E-Box **Store** crate: it opens the Restock
      panel, it lines up with the `x4` badge below it, and a click aimed at it does not land
      on Store — which deposits your whole inventory with no confirm. That last half is the
      only reason this is on the list; P sits one badge-width from it.

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

**The original case is CLOSED** (root cause fixed in `c5d09c6`, same version). It was neither
of the two things I was chasing. `engineAutoMigrate` copies the LuaAshitacast `dlac\` tree
whole into the native home, landing an old `triggers\<JOB>.lua` at the **legacy tier** —
which `seedTriggersFile` refuses to overwrite and `nativeBaselineComplete` refused to count.
Two halves disagreeing about what "has a trigger file" means, forever. The gate now accepts a
legacy-tier file, because the engine and the Triggers tab both resolve to it.

- [ ] **F5 — the migrated character goes quiet.** Anyone who ever ran the LuaAshitacast era:
      confirm no "could not create its native starter files" line at login, and that the
      Triggers tab opens their existing rules rather than an empty file.

**Support fact worth keeping:** wiping `config\addons\dlac\` does **not** reset a migrated
character — it makes `engineAutoMigrate` run again on the next login and re-copy the same
legacy tree. The lever is the LuaAshitacast `dlac\` folder, not dlac's own.

---

## Session G — the debug handoff, which has been broken for a while (`2026.08.05b`)

Found in the legacy-fallback sweep, not by anyone noticing. `dispatch.writeDebugHandoff` writes
the engine half to `charDir() .. name`; all three readers in `feature\debug.lua` were asking for
`handoffDir() .. 'dlac\' .. name`. The native home already carries the character level, so the
readers have been looking one folder too deep since the purge moved the home — **no engine
section has merged into a `/dl report` since**, and the handoff watch (the fallback that fires
the addon half when this state misses the command) never fired either.

This one is worth running deliberately, because it silently degraded the artifact this whole
file tells you to send.

- [ ] **G1 — `/dl debug ls`, then `/dl report`.** The bundle must contain a populated
      `== engine half ==` section, not `NO_ENGINE_HALF` and not an empty one.
- [ ] **G2 — the handoff watch.** Run `/dl check` and confirm the engine's `alive` line and the
      addon readout both appear. If the addon half is missing, the watch is still not firing.
- [ ] **G3 — nothing new under `luashitacast\`.** After a login and a profile switch, confirm
      `config\addons\luashitacast\<Char>\` has no freshly-created empty `dlac\` folder —
      `profiles.setActive` was creating one on every pointer write.

---

## Session H — the mode condition picker (`2026.08.05c`/`d`)

Cheap, and it needs nothing but a job with modes defined. Here because this file claims to be
the whole of the debt on `main`, and these two shipped unfielded like everything above them.

- [ ] **H1 — the picker offers the right vocabulary.** Triggers → a rule → `mode` condition:
      it is a dropdown now. A cycle must offer one entry **per value** (`Weapon:Melee`,
      `Weapon:Caster`), a toggle its **bare name** (`DT`).
- [ ] **H2 — an empty job says where to go.** On a job with no modes defined, the combo reads
      *"no modes yet -- create one in the Modes section"* rather than offering a dead pick.
- [ ] **H3 — the marker fires.** Delete a value from a cycle that a rule still names (or edit
      a trigger file by hand to name a mode that does not exist). The rule must show a red
      **[missing mode]**, and a banner must appear over the tab naming it.
- [ ] **H4 — and clears.** Re-create the mode or repoint the rule; both must go out.

*The Sets tab's mode gate reads the same list — if H1 disagrees with what that combo offers,
the two tabs have drifted and that is the bug, not either list on its own.*

---

## Session I — the giftbox tray icon (`2026.08.05g`)

**The opening loop itself is FIELD-CONFIRMED** (Henrik, 2026-08-05: it worked first try;
the settle between opens was raised 0.6s → 1.2s afterwards on his lag concern, and that
raise has not been run). What is unfielded is the icon.

- [ ] **I1 — it appears at all.** As a **Crystal Warrior**, with a giftbox in inventory, an
      icon shows in the floating tray **under** the E-Box crates. It draws the box's own
      in-game art — the highest rung you are carrying, so a Grand Giftbox shows the Grand icon.
- [ ] **I1b — and only there.** On a non-CW character holding giftboxes, the icon must NOT
      appear at all. `/dl giftbox` itself still works — the gate is on the icon, not the
      command.
- [ ] **I2 — it dims when there is no room.** Below 6 free slots the icon greys out and the
      hover says how many slots short you are. It must NOT disappear — you still have boxes.
- [ ] **I3 — it does not push Store around.** Walk up to an E-Box with giftboxes in your bag:
      the Store crate must stay exactly where it was. Giftboxes are the most volatile member
      of the tray and Store is one click with no confirm.
- [ ] **I4 — the click does what the command does.** Clicking the icon runs the same open-all
      as `/dl giftbox` (it issues the command rather than duplicating the logic).
- [ ] **I5 — the longer settle still completes a run.** 1.2s between opens: a stack of several
      boxes should still empty without stalling or double-firing. If lag still bothers it, this
      is one number in `feature/giftbox.lua` (`M.SETTLE`) and any decimal is honoured.

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
