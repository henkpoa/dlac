# 0021 — Naked is a claim, not a lock

2026-07-25, requested by Henrik ("there's a command called `/lac naked`… can we have that as
well? Be sure to use the claim arbiter, maybe use locks?"). Engine v122.

## Context

LuaAshitacast's `/lac naked` is two lines:

```lua
for i = 1,16,1 do gEquip.UnequipSlot(i); gState.Disabled[i] = true; end
```

A one-shot strip, then a fence. dlac cannot copy it, and not only because the native engine has
no `UnequipSlot`: the fence is `gState.Disabled`, which sits *below* the engine and defeats the
punch-through the Claim Priority list promises. Refusing that flag is a standing dlac ruling
(issue #58).

The obvious dlac translation — strip once, then `/dl lock all on` — was the question Henrik
actually asked, and it is wrong for reasons the codebase had already written down once, in
`pinOverlay`'s header, when pins faced the same choice:

> *Why an overlay and not /dl lock: a lock only makes the engine ignore the slot, so anything
> else that strips the piece wins — and the lock state leaks when a session ends abnormally.*

Naked is that argument with the sign flipped. Specifically:

- **A lock cannot undress you.** It only deletes a slot from a layer's plan (`equipResolved`
  writes `W()[slot] = nil`, never a value). So a lock-based naked is strip-once plus a fence,
  and the strip half has no way to retry.
- **The fence leaks.** `M.locks` is wiped by `M.locks = {}` on every engine *self-swap* — the
  2-second content check that carries a `git pull` into the running engine. A background reseed
  would silently re-dress you.
- **Pins punch through it.** Pins outrank Locks by default, so a lock-fenced naked hands your
  pinned ring straight back within 0.4s.
- **Three unrelated buttons release it**: `/dl lock all off`, the Sets tab's Unlock, and
  unchecking Free equip.
- **It would destroy the player's own locks** — the Incursion-T3 state `/dl lock set` exists for.

## Decision

1. **Naked is an Arbiter claimant, ranked first by default.** One rank row plus one claim
   table, exactly the shape ADR 0012 documents for a new claimant — no new arm, no new
   Statefile, no new watcher module.
2. **The claim is `{ [slot] = 'remove' }` for all 16 slots**, in the equip vocabulary's proper
   case. `'remove'` is a first-class literal in *both* engines (LuaAshitacast's `MakeItemTable`
   and `gear/equipcore.lua`'s `normalizeEntry`/`planSet` both map it to Index 0), so one table
   drives legacy and native with no per-mode branch.
3. **It is recomputed and re-applied every dispatch.** This is the property the whole decision
   turns on: every way the server can refuse a strip — dead or in a cutscene (`isNormalStatus`),
   mid-ranged-attack, the level-sync settle holding the weapon slots — heals on the next pass
   instead of leaking a dressed slot forever.
4. **Always all 16 slots, even when already bare.** Claiming only the occupied slots is a
   correctness bug, not an optimization: the apply loop walks rank low-to-high, so an unclaimed
   slot keeps whatever a *lower*-ranked layer wrote into the buffer this pass. Drop the empty
   slots and a MaxMP battery lands in every slot the previous dispatch just cleared.
5. **`/dl naked` does not touch `M.locks`.** Locks stay the user's word, and `/dl lock all off`
   does not release naked.
6. **Total nudity is the default; the rank list is the exception mechanism.** At rank 1 Naked
   beats everything, pins included. Drag Pins (or Locks) above it in Automations → Claim
   Priority and you get "naked except those" — emergent from machinery that already exists, at
   zero code cost, and the reason Naked must stay a *draggable* row.
7. **A hold placed on behalf of a claimant Naked outranks is void.** `ctx.pinReserved` keeps a
   pinned piece's RSlot neighbours as-worn; when Naked outranks Pins that piece is being
   stripped in the same call, so the reservation must not leave a hat on. Implemented as
   save/nil/restore around the one call, never a `ctx` copy — `ctx` memoizes buffs/target/pet
   lazily and a copy would silently drop those for that layer.
   `ctx.syncHold` is deliberately **not** voided: it is transient and rule 3 covers it.
8. **A missing rank row is restored at its DEFAULT POSITION, not appended.** Every character
   who has ever opened the Priority section has an `arbstate.lua` listing the rows that existed
   then, so every new claimant arrives missing from real files. Appended, Naked would have
   shipped at rank 9 — under Locks, under everything — and lost every slot it exists to win,
   for everyone except a fresh character. One positional law replaces what was becoming a set
   of per-row special cases: it subsumes the Chocobo append and the Triggers-last floor pin.
9. **Lifetime is `M.nakedArmed = (M.nakedArmed == true)` plus a logout guard** — the
   `M._loadStamp` idiom. The module table survives an engine self-swap, so the flag reads
   itself back and a `git pull` cannot re-dress you; a fresh Lua state (Reload LAC,
   `/addon reload`) has no `__dlacEngineRoot`, so the field is nil and **you start dressed**.
   Mirrored to `modestate.lua` as `__naked` for the GUI — the `__locks` contract: display
   only, in the reserved `__` namespace `loadModeState` skips, so it is never restored from
   disk and cannot collide with a user-defined Mode named `naked`.

   **A relog is NOT a fresh Lua state**, and the first draft of this ADR claimed it was.
   An Ashita addon *survives a logout* — `pinwatch.loadPinState`'s header already records
   this, and re-keying pins on the character dir is its answer — and LuaAshitacast never
   clears `package.loaded` either, so in **neither** mode does the engine get a new state
   when you change characters. Pinwatch's charDir re-key would not close it here anyway: a
   same-character relog yields the same dir. So the tick disarms on the character-select
   read (`GetMainJob()` nil or 0), the one moment that sees you leave the world —
   `M.nakedWorldWatch`, which only ever clears, never arms. The login settle reads 0 for its
   first ~6s too; clearing spuriously leaves you dressed, which is the safe direction.
   **Logging in naked is the worst outcome this feature has**, and it is handled there.

   **A JOB CHANGE also disarms** (Henrik, 2026-07-25 — the same watch, the rule the maxmp
   drop already used): changing job is a fresh loadout, and standing there naked on the new
   job with nothing on screen to explain it is the relog failure in a smaller box. Main job
   only, since `GetMainJob` is what the tick reads — a subjob swap does not drop it. It
   announces itself, because unlike the logout case there is someone there to read the line.
10. **Applying a lockstyle is refused while naked.** The apply freezes every slot the box does
    not name to the *worn* id, which is 0 while stripped, and style 0 renders a slot *empty*.
    That writes permanent nudity into every unnamed visual slot, server-side, outliving
    `/dl dress` — and because styles survive having no armor, the player cannot see it happen.
    The refusal lives in **`lockstyle._applyDirect`**, the addon-resident executor, not only in
    the engine's apply half: `_applyDirect` is what the GUI Apply button, the native typed
    handler and every *scripted* apply funnel into — and town transitions, OnLoad restore and
    keep-on-subjob fire with **no user action at all**, so a naked player zoning into town
    would otherwise style themselves bare by itself. (The engine-side guard stays for the
    legacy request-file door.)

Extends ADR 0012 (adds a row and the positional-restore rule). Supersedes nothing.

## Consequences

- **Nothing restores what you were wearing.** `/dl dress` hands your gear back to the triggers
  and automations, so you get the slots your sets *name*; anything you had put on by hand (a
  ring, a trinket in Ammo) you re-equip yourself. This is exact parity with `/lac naked`, and
  the chat line says it plainly rather than implying otherwise. Snapshot-and-restore is a
  reasonable follow-up, deliberately not in this change.
- **The TP wipe is accepted, not worked around** (Henrik, 2026-07-25: *"TP loss is acceptable
  cause it's a deliberate command"*). It is stated once in the chat line and the hover; nothing
  gates, holds or defers on account of it.
- **Taking a weapon off zeroes your TP and drops Aftermath.** Server-side, in `EquipItem` for
  Main/Sub/Range whenever there is no incoming item — the string/wind-instrument exemption
  cannot apply to an unequip. Not fixable here; it is stated up front in the chat line and the
  hover.
- **Free equip (`/lac disable`) silently defeats naked in legacy mode.** LuaAshitacast's
  `PrepareEquip` drops the unequip for any slot in `gState.Disabled`, so an armed strip produces
  zero packets and zero complaints. The command warns, and the Equipped-tab switch renders as
  unavailable rather than clickable-and-inert. Native mode is unaffected (nothing writes
  `equipengine.state.disabled`).
- **MaxMP is the one rank row that cannot except itself from Naked.** Every other claimant
  has an `applyClaim` closure, so a higher rank simply applies later and wins. MaxMP's equip
  stays *woven* inside `equipResolved` (rule 6 of ADR 0012's consequences), and both of its
  write points skip a `'remove'` entry outright — so dragging it above Naked cedes the slots
  but still equips nothing. The `/dl naked` chat line therefore omits MaxMP from the "these
  rank above you" list rather than promising an exception that does not happen.
- **`/dl why` collapses the sweep to one line.** Sixteen identical `Naked (rank 1)` rows would
  bury everything else `/dl why` exists to say — and `/dl why` is what a confused naked player
  runs. The line still names who it beat.
- **In LAC mode every dispatch does a full bag scan while naked.** `FlagEquippedItems` can
  never mark a set containing a `remove` as satisfied, so `LocateItems` walks the equip bags on
  every pass. No packets result, and correctness (rule 4) outranks it. Native mode short-circuits
  at `plan.satisfied`.
- **One LAC-side veto still sits above the rank list**: `EquipItemToBuffer` refuses to overwrite
  a buffer entry marked `.Locked`. Nothing in dlac's path sets it today.
- **A 16-slot unequip goes out as a single `0x051`** in both engines (both pick the set packet at
  ≥9 entries), and the server validates the container of every entry against one allow-list. A
  worn piece in a disallowed container would fail the *whole* packet silently. Unreached in
  practice — the server's own `EQUIP_FROM_OTHER_CONTAINERS` is off, so the equip that put it
  there would have been rejected first — but it is the one way naked can do nothing at all.

## Alternatives rejected

- **`gState.Disabled[i] = true`** (`/lac naked`'s second half) — blocks the slot below the
  engine and defeats the Priority list; a standing dlac ruling forbids it.
- **Writing `equipengine.state.disabled`** (the unwired native twin) — different semantics
  (a disabled slot also blocks the *unequip*), and native-only, so it would split the two modes.
- **A loop of `gEquip.UnequipSlot(i)`** — LAC-only, no native equivalent, bypasses the Arbiter,
  skips the trust stamps, and is a one-shot.
- **`M.setLock('all', true)` as a side effect** — destroys the player's own locks, adds three
  hidden release doors, and is wiped every 2s by the self-swap check.
- **A `nakedstate.lua` Statefile + a `nakedwatch` module** — a new two-state protocol for one
  boolean, and it would survive a relog: silently naked at login is the worst outcome this
  feature has.
- **Putting the flag in `M.modes`** — it would collide with a user-defined Mode named `naked`,
  re-gate their Dynamic sets on every toggle, and inherit `loadModeState`'s restore window,
  whose only relog protection is a documented login race on `GetMainJob() == 0`.
- **Kicking a dispatch on arm/release** — the 0.4s tick is the only Default entry point carrying
  the zoning, player-action, pet-action and sync-settle gates. A command-path dispatch that
  skipped them would fire a full re-equip inside a cast or mid-zone to save 400ms, against a
  claim that is standing anyway.
