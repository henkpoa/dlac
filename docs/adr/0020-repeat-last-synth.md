# 0020 — Repeat Last Synth (the 2–6 buttons), and exclusivity is an *arming* rule

2026-07-25, requested by Henrik (grilled to shared understanding before any code).
Addon-state only — `dispatch.lua` untouched, no engine version bump. **Revises point
3 of [ADR 0017](0017-idle-hobbies-mutually-exclusive.md)**; everything else in 0017
stands.

## Context

The craft bar has a `Last Synth` button that types the game's own `/lastsynth` —
the client's retail-native repeat command. dlac may **type** it and nothing else
(Henrik's 07-13 ruling, learned by breaking it: dlac once registered its own
`/lastsynth` handler, which blocked the real one).

A player reported that after the hobby-menu work, Last Synth "doesn't work".
Henrik could not reproduce it. Investigation found the button's own code
byte-identical to the version that worked (`1c20333`, moved verbatim by
`92e1fb2`), and `QueueCommand(1, …)` correct — `Ashita::CommandMode::Typed = 1`
(`plugins/sdk/Ashita.h:193-213`), "forward the command as if a player typed it".

The break was in `ui/hobbybar.lua`. It read ADR 0017's exclusivity rule as a rule
about **looking**: it pinned `ui._hobbySel` to the armed hobby *every frame* and
greyed out the other tabs. With Auto HELM or Chocobo on — both of which persist to
disk and survive relogs — the Craft tab was never drawn, so the Last Synth button
did not exist on screen. Auto-Craft being off is the normal state for someone who
only uses Last Synth, so any other hobby won unconditionally. Both escape hatches
were structurally dead too: `effectiveSel()` could never return `'craft'` while
another hobby was armed, so `toggle('craft')` could not close the bar and
`isShown('craft')` was permanently false — `/dl craft bar` printed a false
`"hobby bar hidden."` while opening it.

Separately, Henrik asked for what a macro bar already does: repeat the last synth
2–6 times (six is a macro bar's capacity), a player-set wait between them, and a
green "Crafting complete" report at the end.

## Decision

**1. Exclusivity is an ARMING rule, never a LOOKING rule.** `idleexcl.guardActivate`
already refuses the second arm at the enable layer — that is the whole guard. The
hobby-bar selector no longer pins or locks: every tab is always reachable, switching
tabs arms nothing, and the armed hobby is marked green with a trailing `*` as before.
Its on/off pill is what refuses. This supersedes 0017 point 3.

**2. The repeat run lives in `feature/synthrun.lua`, not in the bar.** One door:
`start(n)` / `stop()` / `status()` / `tick()`. `ui/craftbar.lua` draws `status()` and
nothing else. Six is a hard cap.

**3. It never wraps `/lastsynth` — it watches the wire instead.** There is no return
value to check, so the run reads two incoming packets, both proven on this client
stack by Ashita's stock `craftmon` addon and matched against the CatsEyeXI server
structs:

| packet | when | what we take |
|---|---|---|
| s2c `0x030` synthesis animation | ~130 ms after the synth starts | *proof the shot landed* — result type at `@0x0C`, actor index at `@0x08` |
| s2c `0x06F` synthesis results | ~17 s later | *what came out* — result code `@0x04`, quantity `@0x06`, item id `@0x08` |

`0x030` alone drives pacing decisions; `0x06F` only feeds the report. Bystanders'
animations are filtered on `TargetIndex`; if the player entity is unreadable we
**trust** the animation, because a missed one would abort a healthy batch.

**4. The wait is the player's knob, and its floor is FIELD TRUTH.** Source math says
~17 s is legal (15 s server cooldown from synth start, `synthutils.cpp:1083`, plus a
16 s AI state, `synth_state.h:59`). The real interval is **~22 s in perfect
conditions** and longer in a frame-heavy zone like Lower Jeuno, because the client's
synthesis animation is frame-tied — the server's `0x06F` arrives before the client
will accept another `0x096` (Henrik, years of field use). So: default **30**, range
**20–120**, per character, and the tooltip carries the 22 s figure and the
busy-zone warning. Stored in `craftstate.lua`, which `craftwatch` **solely owns** —
a second writer would clobber it.

**5. A missed shot is retried exactly once, after 2 s.** Frame lag is transient; "out
of materials" and "inventory full" are permanent, so the retry costs ~2 s at the end
of a run that was over regardless. A second miss aborts. `0x030` lands in ~130 ms, so
2 s is already generous (Henrik: "if you need more than that, your timer is way too
tight").

**6. Stop is the `Last Synth` button itself.** Mid-run it turns red and reads
`Stop  2/6`; the 2–6 buttons and the wait box grey out and their clicks are
**dropped**, so a double-click cannot stack a second batch. Keeping a live "fire one
now" button during a run would desync the count. Zoning, `/addon reload` and unload
abort automatically.

**7. Silence during the run, one line at the end.** Every per-synth print was
stripped from `craftwatch` on 07-13 as "too chatty"; the bar's `Stop 3/6` and
`next in 12s` *are* the progress display. Green (`chatfmt.good`) is reserved for a
run that completed in full; an early stop is yellow (`.warn`); your own Stop is
plain white — you asked for it, it is not an alarm.

```
Crafting complete -- 6 synths: 10x Bronze Ingot, 2x Bronze Ingot +1.     green
Crafting complete -- 6 synths (5 made, 1 broke): 10x Bronze Ingot.       green
Crafting stopped after 3 of 6 -- the game did not start a synth
  (out of materials, inventory full, or Wait too short).                 yellow
Crafting stopped -- 3 of 6 done.                                         white
```

HQ needs no special case: the game names HQ items `… +1`, so they separate
themselves in the tally. `data/crafts.lua` stores only the NQ result id (`r`) and
did not need regenerating.

**8. The report waits for the last `0x06F`** (up to a 30 s grace) so it can name what
the final synth produced, rather than reporting at the moment the last synth *starts*.

## Alternatives rejected

- **Blind timer with no verification** (the first sketch, and what a macro bar does).
  Rejected once `0x030` turned out to be free: a blind run keeps firing into the void
  after your materials run out and still claims success.
- **Pace off `0x06F` instead of a fixed wait.** Rejected — `0x06F` is the *server*
  finishing; the client's frame-tied animation is the real bottleneck, which is
  exactly why 22 s ≠ 17 s. Reacting to `0x06F` would fire too early in a busy zone.
- **`0x096`-counting as the verifier** (the second sketch). Rejected — `0x096` only
  proves *we typed the command*, not that the game accepted it.
- **Narrating each synth to chat.** Rejected against 07-13's "too chatty" ruling.
- **Reporting `6x Bronze Ingot` from the recipe.** Rejected as dishonest — synths
  break. The tally comes from `0x06F`, so it reports what actually came out.
- **A separate Stop button.** Rejected — a live `Last Synth` during a batch desyncs
  the count, and a second widget crowds an already-busy bar.
- **Blocking the run when inventory is nearly full.** Considered because the server
  never checks `AddItem`'s return (`synthutils.cpp:1272`) and would destroy the
  result while consuming ingredients. Rejected: the **client** refuses to send
  `0x096` first and says `Unable to execute that command.` (Henrik), so that path is
  unreachable — and it presents to us as a missed `0x030`, which already aborts.

## Enforcement

- **U1–U44** (`tests/run_tests.lua`) drive the whole state machine headless on an
  injected clock (`M._now`), a recording `AshitaCore` and a stub `chatfmt` — so the
  *colour* of every report is asserted, not just its text. Covers packet decode,
  the tally, the bystander filter, the wait gate, retry-then-abort, cancel codes,
  the zone abort, the grace timeout, and manual stop.
- **CB1–CB16** (`tests/smoke_ui.lua`) render the **real** `craftbar.renderContent`.
  This closes a live gap: every previous suite stubbed it with a no-op, so nothing
  had ever executed that file's body — and an unknown Lua name is a silent nil
  global that a load-only test cannot catch (it has bitten this project three
  times). CB2 was verified to fail, naming `craftbar.lua:130`, when an imgui
  function was removed from the stub.
- **HB9–HB13** are the regression guard for the tab lock: render must leave the
  selection alone while another hobby is armed, and `toggle`/`isShown` must work on
  a tab that is not the armed one.
- `feature/synthrun.lua` is on the source-scan roster (`FEATURE`).
- **T24b–T24g** pin the wait clamp (floor 20, ceiling 120, default 30).
- Packet handlers stash only; `M.onPacket` is a named door so the suite can drive
  the machine without an Ashita event loop.
