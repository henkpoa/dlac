# Repeat Last Synth — field-test handoff

**Status:** built, committed, **not field-tested**.
**Where:** branch `dev`, commit `d46195b`, one ahead of `main` (`2332088`).
**Version:** addon `2026.07.25c`. **Decision record:** [ADR 0020](../adr/0020-repeat-last-synth.md).
**Tests:** 3329 (`run_tests.lua`) + 364 (`smoke_ui.lua`) green on Windows *and* WSL `lua5.4`.

Nothing is pushed and nothing is merged to `main`. Picking this back up = read
§4, run it in the field, report back.

---

## 1. What was asked for

1. Troubleshoot "after the hobby menu was changed, Last Synth doesn't work".
2. Add `2 3 4 5 6` buttons under Last Synth — synth the last recipe that many
   times. Six because six is what a macro bar holds.
3. A green "Crafting complete" report in chat when it finishes.
4. A wait-timer box, player-set, default 30, remembered per character.

All four are built.

## 2. The bug — what it actually was

Henrik could not reproduce it and assumed a local plugin overlay eating the
click. The evidence says otherwise, and the two explanations are compatible:
he had no hobby armed.

`ui/hobbybar.lua` pinned `ui._hobbySel` to the **armed** hobby every frame and
locked the other tabs. With **Auto HELM or Chocobo on — both persist to disk and
survive relogs — the Craft tab was never drawn**, so the Last Synth button did
not exist on screen. Auto-Craft being off is the normal state for someone who
only uses Last Synth, so any other hobby won unconditionally.

Both escape hatches were dead too: `effectiveSel()` could never return `'craft'`
while another hobby was armed, so `toggle('craft')` could not close the bar and
`isShown('craft')` was permanently false — `/dl craft bar` printed a false
`"hobby bar hidden."` *while opening it*.

Root cause was a category error worth remembering: **ADR 0017's exclusivity is an
ARMING rule** (`idleexcl.guardActivate` refuses the second arm), and hobbybar had
re-implemented it as a **LOOKING** rule. Every tab is reachable now; the green `*`
and the on/off pill carry the rule. ADR 0017 point 3 is marked superseded.

**Ruled out with evidence:** `QueueCommand(1, …)` is correct —
`Ashita::CommandMode::Typed = 1` (`plugins/sdk/Ashita.h:193-213`), 1115 mode-1
call sites install-wide. The button's own code is byte-identical to the version
that worked (`1c20333`, moved verbatim by `92e1fb2`). No dlac handler intercepts
`/lastsynth`. No ImGui id collision. No orphaned craftbar window.

**Still open, deliberately not acted on:** commit `81c9af1` removed the one-click
header hobby-bar button and buried the bar behind *Menu > Hobby bar*. That may be
the other half of what the reporter meant by "doesn't work". Henrik's call.

## 3. How the repeat works

Still only **types** the native `/lastsynth` — dlac never wraps it (07-13 rule).
There is no return value, so verification is passive, off the wire:

| packet | when | what it gives |
|---|---|---|
| s2c `0x030` synthesis animation | ~130 ms after the synth starts | *proof the shot landed* — result type `@0x0C`, actor index `@0x08` |
| s2c `0x06F` synthesis results | ~17 s later | *what came out* — result `@0x04`, quantity `@0x06`, item id `@0x08` |

Offsets are Ashita's stock `addons/craftmon/craftmon.lua`, matched against the
CatsEyeXI server structs. `0x030` alone drives pacing; `0x06F` only feeds the
report, and the report waits for the **last** one (30 s grace) so it can name what
the final synth produced.

**The wait floor is field truth, not source math.** Server allows ~17 s (15 s
cooldown from synth start + a 16 s AI state). Henrik measures **~22 s** in perfect
conditions, more in frame-heavy zones, because the client's synth animation is
frame-tied. Hence default **30**, range **20–120**, per character in
`craftstate.lua` (which `craftwatch` **solely** owns — do not add a second writer).

A shot that draws no `0x030` is **retried once after 2 s**, then the run aborts.
Frame lag is transient; out-of-materials and inventory-full are permanent and both
present as that same silence — the *client* refuses to send `0x096` and prints
`Unable to execute that command.`

Stop is the `Last Synth` button turning red in place (`Stop 2/6`). The number
buttons and wait box grey out **and their clicks are dropped**, so a double-click
cannot stack a second batch. Zone / unload / reload abort.

```
Crafting complete -- 6 synths: 10x Bronze Ingot, 2x Bronze Ingot +1.     green
Crafting complete -- 6 synths (5 made, 1 broke): 10x Bronze Ingot.       green
Crafting stopped after 3 of 6 -- the game did not start a synth
  (out of materials, inventory full, or Wait too short).                 yellow
Crafting stopped -- 3 of 6 done.                                         white
```

HQ needs no special case — the game names HQ items `… +1`, so they separate
themselves in the tally and `data/crafts.lua` did not need regenerating.

---

## 4. THE FIELD TEST

Ordered so a failure early tells you not to bother with the rest.

### A — the tab lock (the reported bug)

| | do | expect |
|---|---|---|
| A1 | Turn **Auto HELM** on. Open the hobby bar. | Craft tab is clickable and shows the craft controls. HELM tab is green with a trailing `*`. **This is the fix.** |
| A2 | With HELM armed, go to the Craft tab and click the craft on/off pill. | **Refused**, with `Craft` staying off and a line naming HELM. Exclusivity must still hold at the *arm*. |
| A3 | `/dl craft bar` twice while HELM is armed. | First: opens on Craft, says `hobby bar shown (Craft)`. Second: **closes**, says `hidden`. (Before: said "hidden" both times and never closed.) |
| A4 | Automations → Craft → the Show/Hide bar button. | Label flips correctly and matches reality. |
| A5 | Turn every hobby off. Repeat A1. | Unchanged behaviour — no tab is ever green. |

### B — Last Synth itself (unchanged code, sanity only)

| | do | expect |
|---|---|---|
| B1 | Synth once through the game menu. | The bar's `Last synth:` line names the item. |
| B2 | Click `Last Synth`. | One synth. **If it does nothing, type `/lastsynth` in chat.** If *that* also does nothing, dlac is not involved — it is the deeps overlay or the client's own memory. |

### C — the repeat run

| | do | expect |
|---|---|---|
| C1 | Click `3`. | Three synths ~30 s apart. Bar reads `Stop 1/3` then `Synth 1 of 3 -- next in Ns`. |
| C2 | Let it finish. | One **green** line: `Crafting complete -- 3 synths: Nx <item>.` |
| C3 | Run a recipe that can HQ, until one lands. | The HQ appears in the tally as `<item> +1`, counted separately. |
| C4 | Run one that can break. | `(N made, M broke)` appears, still green. |
| C5 | Click `6`. | Six, not five, not seven. |

### D — Stop and greying

| | do | expect |
|---|---|---|
| D1 | Click `4`, then `Stop` mid-run. | **White** line `Crafting stopped -- N of 4 done.` No further synths. |
| D2 | While running, click `2`. | **Nothing.** No second batch, no count change. |
| D3 | While running, look at the Wait box. | Static grey text `30s`, not an editable box. |
| D4 | While running, double-click `Stop`. | Stops once, no error. |

### E — the wait timer

| | do | expect |
|---|---|---|
| E1 | Set 25. `/addon reload dlac`. Reopen the bar. | Still 25. |
| E2 | Log to a different character. | That character has its **own** value (30 if never set). |
| E3 | Type `45` into the box. | Reaches 45 — must **not** snap to 20 while you are mid-type on the `4`. |
| E4 | Type `5`, then click away. | Clamps up to 20 on blur. |
| E5 | Type `500`. | Clamps to 120 immediately. |

### F — the failure paths (**the data I most want**)

| | do | expect |
|---|---|---|
| F1 | Materials for only 2. Click `4`. | Stops after 2, **yellow** `Crafting stopped after 2 of 4 …`. Should take ~2 s of retry, not 30. |
| F2 | Fill inventory. Click `3`. | Same yellow stop. The game's own `Unable to execute that command.` should appear too. |
| F3 | **Set Wait to 20, stand in Lower Jeuno, click `4`.** | This is the frame-tied hypothesis under test. Either it survives on the one retry, or it aborts early — **either result is useful, please report which**. |
| F4 | Start a batch, then zone mid-run. | Batch aborts. (Note: zoning mid-synth destroys the materials — that is the server, not dlac.) |
| F5 | Start a batch, `/addon reload dlac` mid-run. | Batch vanishes silently. No stray `/lastsynth` afterwards. |

### G — the one thing packets could not settle

| | do | expect |
|---|---|---|
| G1 | Synth once. **Zone.** Click `Last Synth`. | Unknown — does the client still remember the recipe? The server has no state for it (`/lastsynth` is 100% client-side), so only the field can answer. |
| G2 | Synth once. `/addon reload dlac`. Click `Last Synth`. | Should work — it is the *client's* memory, not dlac's. |

**If G1 fails**, the repeat buttons need a "synth once after zoning" note, and
possibly a friendlier first-failure message than the generic yellow line. Say so
and I will add it.

---

## 5. Where the code is

| file | what |
|---|---|
| `feature/synthrun.lua` | **new** — the whole run. `start`/`stop`/`status`/`tick`/`onPacket`. |
| `feature/craftwatch.lua` | `getSynthWait`/`setSynthWait` + `wait` in `craftstate.lua`. Owns that file. |
| `ui/craftbar.lua` | the row: 2–6 buttons, wait box, Stop-in-place. Draws `status()` and nothing else. |
| `ui/hobbybar.lua` | the tab-lock fix. |
| `dlac.lua` | `feature\synthrun` on the load ledger; version `2026.07.25c`. |

**Tests.** `U1–U44` (`run_tests.lua`) drive the whole state machine headless on an
injected clock (`M._now`), a recording `AshitaCore` and a stub `chatfmt` — so each
report's *colour* is asserted, not just its text. `CB1–CB16` (`smoke_ui.lua`)
render the **real** `craftbar.renderContent`; every previous suite stubbed it with
a no-op, so nothing had ever executed that file's body, which is the silent-nil-
global class that has bitten this project three times. CB2 was verified to fail —
naming `craftbar.lua:130` — with an imgui function removed from the stub. Do that
teeth-check on any future render test. `HB9–HB13` guard the tab-lock regression.
`T24b–T24g` pin the wait clamp.

## 6. Coming back to this

1. Run §4. Note which rows fail and paste any chat lines verbatim.
2. If it is clean → `dev` → `main` is Henrik's call (branch rule: work commits
   directly on `dev`, never a feature branch; `dev` promotes whole-or-not-at-all).
3. If G1 fails, or F3 shows dropped synths at 20 s, those are the two changes
   most likely to be wanted, and both are small.
