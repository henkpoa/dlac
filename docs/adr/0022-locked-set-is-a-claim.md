# 0022 — A locked set is a claim on the Locks row

2026-07-26, requested by Henrik (*"We just made a new feature called /dl naked, can you take
inspiration from how we locked everything here? Only difference really, is that we want this to be
locked to what a specific set holds, instead of no gear."*). Engine v123.

## Context

`/dl lock set <name>` — the Sets tab's **Equip & Lock**, written for Incursion T3, where the server
locks your equipment on entry — did two things: equip the committed set once, then
`M.setLock('all', true)`.

**It was broken in native mode, and nothing could see it.** The one-shot equip was bracketed with
`rawget(_G, 'gEquip')`, which is nil in the addon state. So the resolved set fell to the unbracketed
path, `engineEquipSet` wrote it into `equipengine`'s `_buffer`, and the next `fireEvent` opened with
`bufferClear`. The command then locked all sixteen slots onto whatever the player happened to be
wearing and printed `"<name>" equipped -- ALL slots locked`.

Two things made this invisible rather than merely wrong:

- **The lock is what hid it.** A Default dispatch runs every 0.4s and is idempotent, so the three
  *other* unbracketed `M.dispatch('Default')` calls in the file (`installSets` ×2, `/dl mode`) cost
  latency and nothing else — the next tick redoes the work and flushes it properly. `/dl lock set` is
  the one site where that self-healing is structurally impossible, because the very next thing it
  does is install the locks that guarantee the next dispatch equips nothing.
- **No test could reach it.** Every `/dl` subcommand was tested by searching `dispatch.lua` for its
  own name — `NK23`'s note: *"the whitelist cannot be driven — pin it as SOURCE instead"*. A source
  pin proves a command is spelled right and whitelisted. `/dl lock set` was both.

ADR 0021 had already written down why the *mechanism* was wrong, in the other direction. Listing why
a lock-based Naked was rejected, it named this command as collateral:

> **It would destroy the player's own locks** — the Incursion-T3 state `/dl lock set` exists for.

and among the rejected alternatives:

> **`M.setLock('all', true)` as a side effect** — destroys the player's own locks, adds three hidden
> release doors, and is wiped every 2s by the self-swap check.

So the ADR rejected for Naked the exact mechanism this command still used. It just did not circle
back to the neighbour. Three defects, not one: the native equip, the destroyed locks, and the fence
itself — `M.locks = {}` at module scope re-runs on every engine self-swap, so in LAC a `git pull`
mid-Incursion silently unlocked all sixteen slots.

## Decision

1. **A locked set is an Arbiter claim, applied every dispatch.** This deletes the bug rather than
   repairing it: a claim is applied inside `M.dispatch`, which the native engine already brackets
   (`fireEvent` = `bufferClear` → handler → `bufferFlush`), so there is no command-path equip left to
   bracket wrongly. `M.setLock('all', true)`, the clear-your-locks loop and the `gEquip` bracket are
   all gone.

2. **It rides the EXISTING `Locks` row.** No new rank row (Henrik: *"I am personally also a bit
   confused to why we aren't simply using lock when it would do what we needed, why we must create
   new categories for every function"*). To the player, *lock* is one word, one row, one drag target,
   and the Priority panel's tooltip already described it that way. `arbResolve` already returns
   `slot -> item OR LOCK_HELD`, so one row carries real item names for held slots and the veto
   sentinel for plainly-locked ones. The only new machinery is an `applyClaim['Locks']` closure;
   a veto had nothing to apply.

   The one thing that genuinely cannot be a lock, recorded so it does not come back: **a lock cannot
   put gear on.** `equipResolved` writes `W()[slot] = nil` and never a value. That is why the old
   command had to equip first, and why the hold must be a claim internally even though it is a lock
   to the player.

3. **`ARB_ORDER_DEFAULT` is unchanged: `Naked, Pins, Locks, …`** A locked slot moves for Naked and
   Pins, and for nothing else. Pins stay above (Henrik: *"pins are always on demand and is
   universally understood to be there when needed"*), which also means this change does not quietly
   alter precedence while it is fixing an equip bug. "Locked except my pins" is the default;
   "locked beats my pins" is the existing Locks-above-Pins drag.

4. **Four command words, one claim shape.** They differ *only* in what fills a slot the set does not
   name, so `M.dispatch` never learns which command made the claim:

   | command | slots the set names | every other slot |
   |---|---|---|
   | `/dl lock set <s>` | held | **held empty** (`remove`) |
   | `/dl lock set-loose <s>` | held | **available** |
   | `/dl lock set-snapshot <s>` | held | **held as worn** |
   | `/dl lock set-current` | *(no set)* | **all 16 held as worn** |

   In Henrik's words: *"Strict = hard reserve EVERYTHING, even empty slots. Loose = reserve ONLY the
   slots that have anything on them, the rest gets free use for any other claimants."* `set-current`
   is strict, so a slot that is empty snapshots as empty.

5. **Frozen at arm — the instruction, never the outcome.** (Henrik: *"Once you lock, it shall be
   constant, like with naked. Even if you lock a set then change it, it should not change what you
   wear."*) `dlac:` markers are collapsed to concrete entries once, at arm, so a locked
   Hachirin-no-Obi cannot follow the weather. But the claim still **re-locates** those names in your
   bags every dispatch: freezing container+index instead would strand the hold the first time a bag
   shuffled, which is strip-once-with-no-retry again — the failure ADR 0021 rule 3 exists to prevent.
   Entries are frozen whole (`{ Name, Augment, Bag }`), not as bare strings, so `planSet` still picks
   the right copy of a ring you own twice.

6. **A piece that is not on you leaves that slot LOOSE, not empty** (Henrik: *"That's better than an
   empty slot, is it not?"*), and arming reports which pieces, and where they are, from a live scan
   of every container. It arms anyway — *"We create the tools, they use them… but we shall make good
   hammers."* The slot stays loose until you lock again: the claim is frozen, so moving the item into
   your inventory mid-run does not re-join it.

7. **Slot locks coexist; arming never clears them.** `layerRespectsLocks('Locks')` asks
   `rank > lockRank` about its own row, which is `false`, so the hold punches through `M.locks` and
   dresses every slot it named. That is what makes the old clear-first unnecessary: a stale lock can
   never strip a slot out of the hold that outranks it, and it is still set when the hold is
   released. Under `set-loose`, plain locks become the tool for "lock this set *and* freeze my ammo",
   which was not expressible before.

8. **Both dispatch bail guards must let a lone hold through.** `M.dispatch` returns early twice when
   nothing has claimed anything, and a locked set with no triggers, no pins and no hobby armed is
   exactly the Incursion case. This is `NK26`'s lesson verbatim; `LS16` is the check, and reverting
   either guard fails six tests.

9. **Lifetime is Naked's, sharing `nakedWorldWatch`.** It survives an engine self-swap — a `git pull`
   firing the 2s content check mid-Incursion must not hand your gear back, so the state uses the
   `M._loadStamp` idiom and deliberately **not** `M.locks`'s home, which that event wipes. It drops
   on a job change (announced), on the character-select read (silent), and on a fresh Lua state. It
   is never written to disk: logging in silently locked to last night's set is ADR 0021's worst
   outcome wearing different clothes, and meaner — a naked player knows instantly, a locked one just
   finds their gear mysteriously stuck.

10. **Released by `/dl lock all off` AND `/dl lock set off`.** ADR 0021 counted release doors as a
    defect, but that was about a *naked* released by lock commands. A hold armed by `/dl lock set`
    and released by `/dl lock all off` is the same verb, and Henrik's reading is the player's:
    *"if I didn't know any better as a player, /dl lock would have to be turned off the same way as
    the normal dl lock all."* `/dl lock all off` says what it released.

11. **`/dl lock` with no arguments prints both halves of the row and every variant.** Four commands
    that differ only in which slots they freeze are unguessable otherwise.

12. **Arming while naked is allowed, warned, and blocked by the Arbiter — not by a special case.**
    (Henrik: *"Warn that naked mode is on, but let lock try to equip it, but the claim arbiter will
    block due to naked. Once naked is turned off, that lock should be next in place to take
    priority."*) The apply loop walks rank low-to-high, so Locks writes its items and Naked
    overwrites all sixteen. It tries and is blocked, every pass; `/dl dress` and it wins 0.4s later,
    behind Pins. No refusal, no auto-disarm, no code.

13. **AMENDED 2026-07-26, engine v124 — one lifetime rule for all three.** Henrik: *"I don't want
    locks to outlive a relog, it should not outlive a main job change nor a log. It should not be
    saved. Same with naked."* Plain **slot locks** now share the watch too, so every way of
    deliberately holding gear still — the strip, a locked set, a slot lock — ends on a main job
    change or on leaving the world, and none of the three is written to disk.

    Slot locks were the odd one out only by accident. Nothing ever watched them, so they rode
    straight through character select (an Ashita addon survives a logout and LuaAshitacast never
    clears `package.loaded`). Before v123 an engine self-swap happened to wipe them, which *looked*
    like a lifetime rule and was really a bug — a `git pull` unlocking your gear mid-Incursion.
    Fixing that accident is what left the real gap visible.

    `M.nakedWorldWatch` is renamed `M.worldWatch`, with the old name kept as an alias because the
    seeded LAC-side engine and the `NK28` checks call it. The job-change drop is announced per kind;
    leaving the world stays silent, because nobody is there to read it. Tests `LS14k`–`LS14s`.

Extends ADR 0012 (the Locks row gains an `applyClaim` and a positive claim table) and ADR 0021
(shares its watch and its freeze-the-instruction rule; decision 13 widens that watch to slot locks).
Supersedes nothing.

## Consequences

- **The Sets tab's Equip & Lock is a plain action, not a toggle.** It flipped to "Unlock" when the
  mirror showed sixteen locked slots; nothing locks sixteen slots now, so that counter is permanently
  zero and the toggle would have jammed. The held state and its release moved to the **Equipped
  tab**, which is where what you are wearing is already shown — the Sets tab builds sets (Henrik:
  *"Set tab is only to build sets that may or may not be equipped by trigger level of claimant
  arbiter"*). That tab also gets the `set-current` switch, the one variant with no set to pick.
- **The Sets tab button offers Strict or Loose on click** (amended 2026-07-26 the same day, on
  Henrik's read of the first draft). It opens a two-option popup rather than firing strict blind,
  which gives `set-loose` a GUI home; `set-snapshot` stays command-only, being the one variant whose
  meaning is hard to state in two words. The hover is three lines and stays three lines — *"there is
  TOOOOO much text… this is minimalistic and every word matters"*. Everything cut from it had a home
  already: precedence is Claim Priority, release is the Equipped tab, and the missing-piece list is
  said in chat at the moment it matters.
- **The popup is the least-tested thing in this change.** The Sets tab render has no smoke drive, so
  `LSP1`–`LSP10` pin it as source. That is honest about its limit: a source pin cannot tell you the
  popup renders, only that its `OpenPopup`/`BeginPopup` ids agree — the failure that would otherwise
  register a click, open nothing, and log nothing.
- **Unchecking "Free equip" releases the hold**, because `equippedui` fires `/dl lock all off` when
  leaving free-equip and that is now the universal release. Left as-is: leaving free-equip is a
  "hand control back to the engine" gesture, and narrowing it would mean inventing a slot-locks-only
  command to serve one checkbox.
- **A set named `off` cannot be locked by name** — `/dl lock set off` releases. Documented rather
  than worked around; the alternative is a set nobody can release by name.
- **Arming resolves the set with the live context once**, so arming during a level-sync settle or
  with a bag closed freezes a worse answer than a second later would have given, with no
  self-correction. That is the cost of "constant", accepted deliberately. Naked has no equivalent
  exposure because `remove` cannot be resolved wrong.
- **Both halves of the Locks row now have one lifetime** (decision 13). A `git pull` mid-session no
  longer releases either — the self-swap wipe of `M.locks` was fixed in its own commit — and a main
  job change or a logout releases both. Changing a job therefore drops slot locks that used to
  persist; that is the intended behaviour, not a side effect.
- **`/dl why` attributes a held slot to `Locks`**, with the set named in the layer line. The retrace
  merges the two kinds of opinion rather than assigning, or whichever was written second would erase
  the other.

## Alternatives rejected

- **A one-line native bracket at the call site** (`eng.bufferClear()` / `eng.bufferFlush('auto')`) —
  fixes today's symptom and leaves the next command-path equip free to make the identical mistake.
  The asymmetry *is* the bug: this shipped because the author copied the PetAction bracket, which is
  correct only in LAC.
- **A shared `engineEquipNow(fn)` door** bracketing both engines — the right shape for a command that
  equips, but under this decision no command equips, so the door has no callers.
- **A new `Held` Arbiter row at rank 2** — airtight for Incursion with no drag, but it adds a second
  thing called almost the same as Locks, and at rank 2 it would have silently taken away pins'
  ability to punch through Equip & Lock, which is today's behaviour.
- **Moving `Locks` above `Pins`** to make a lock absolute — rejected on the merits (pins are on
  demand and universally understood to win) and on rollout: `arbOrder` keeps the user's order for any
  row their `arbstate.lua` lists, so the new default would only reach players who had never opened
  the Priority panel.
- **Re-reading the set by name every dispatch** — keeps resolution live and makes editing a set
  update the hold, but "I locked it and it changed anyway" is the complaint the freeze exists to
  answer.
- **Freezing the resolved container+index** — the other reading of "constant", and dead: bag indices
  move, and the hold would strand permanently the first time one did.
- **Holding a missing piece's slot as-worn** instead of leaving it loose — freezes you into whatever
  random piece is there, when the normal machinery could put something useful in it.
- **`ownedcache.whereText`** for the "where is it" report — it is the addon's existing answer, but
  ADR 0002 keeps the engine from requiring addon modules, and it is a cache, so it can be stale at
  the one moment this has to be right.
