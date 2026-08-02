# `/dl report` — handoff, 2026-08-02

**Paused waiting on ONE thing: a level-up during a capture.** Henrik is not levelling for a
while (in-game events), and the outstanding field round cannot be run without it. Everything
else in the train is done and green.

---

## Status

| | |
|---|---|
| **On `main`** | `ecb7f3a` — `/dl report` v1 (`2026.08.03a`–`c`) |
| **On `dev`, NOT promoted** | `a64d1f4` (`03d`), `ead3afa` (`03e`), `df77475` (`03f`, engine **v163**) |
| **Suites** | 5938 headless + 1003 UI smoke, both interpreters |
| **Promotion** | **not accepted** — Henrik has not said merge for `03d`–`03f`. Do not promote on your own read. |

`dev` is pushed through `eb33824`; the three commits above are **local only** at the time of
writing — check `git log --oneline origin/dev..dev` before assuming.

The addon is `2026.08.03f`; the engine is `M.VERSION = 163`.

---

## The one thing that is owed

**A `/dl report` captured across a level-up.** That is the exact condition the v163 fix
addresses, and nothing else reproduces it.

Why: the retrace signature covers matched rules + cases, locks, claimant legs, the sets-store
revision and the rank order — **not the player's level**. Levelling changes which candidates a
set resolves to *while the signature holds*, which is what let a record's plan move while its
contest stayed behind.

### Recipe

1. `/addon reload dlac` — **non-negotiable**. A previous round was spent reading a report from
   a stale addon state; a player testing the old build looks exactly like a fix that failed.
   Confirm the report header says `dlac 2026.08.03f`.
2. `/dl report` (normal scope is enough — `full` adds 690 KB of bundle and nothing relevant).
3. **Level at least one rung during the window**, ideally two, on a job whose sets contain gear
   that becomes eligible at the crossed level. The low DRG is ideal: Optical Earring (Ear1,
   Lv10), Faceguard +1 (Head, Lv10), Solid Mail (Body, Lv10), Scale Cuisses (Legs, Lv10).
4. `/dl mark levelled here` at the moment the level lands.

### What should be GONE

- `NO CLAIMANT RECORDED (the plan has it, the contest names nobody)` — the whole reason v163
  exists. Any occurrence means the rebuild did not fire; report the block verbatim.
- Zero-change records that exist **only** because a claimant caught up a beat late (a block
  whose sole content is a `claim moved: (nobody) -> Triggers` line right after a level-up).

### What should still be THERE, and is correct

- `(not placed)` on **Main/Sub** across the level-up, with
  `Triggers claimed this slot with <weapon>, but the plan did not carry it`. That is the
  **level-sync weapon hold** (`ctx.syncHold`, engine v56) doing its job — Main/Sub/Range are
  deliberately held as worn while a level reading settles. Not a bug. Do not "fix" it.
- `was:` lines on changed slots, and `sets:` on every block.
- Genuine `claim moved:` lines when a claimant really does hand a slot over.

### If `NO CLAIMANT RECORDED` still appears

The rebuild is `M._planOutrunsContest(planSnap, contest)` in `dispatch.lua` (~line 4059,
called ~6800). It is **one-way by design**: it fires when the plan names a slot the contest
cannot account for, or swaps the item inside one it covers. It deliberately does **not** fire
when the contest names *more* than the plan — that is a lock or the weapon hold, two questions
answered correctly, and rebuilding there would re-explain on every held beat.

---

## Proven vs assumed — read this before claiming anything

| Claim | Evidence |
|---|---|
| Recorder, bundler, streamed log, file write | **Field-proven** (three live reports) |
| `full` scope | **Field-proven** — 93 files, zero dropped, raw `gear.lua` whole, 736 KB |
| Pre-roll | **Field-proven** — caught a decision 26 s before the button |
| Digest's two lists, `ABOVE YOUR LEVEL` | **Field-proven** on a DRG that levelled 9→10 |
| `claim moved:`, `sets:`, relabelled action counter, engine-version note | **Field-proven** |
| `was:`, `(not placed)`, `NO CLAIMANT RECORDED` | Suites + replay of his real records only |
| **v163 engine fix** | **Suites + reasoning only — THE OWED ROUND** |
| Un-mark button | **Never field-run.** Henrik reported the duplicate-mark bug, the fix landed, nothing re-ran |
| Crash path (dead client leaves `dlac-capture-<Char>.log`) | **Never exercised by anyone** |

`PO8` asserts the invariant over every record the suite's real dispatches build, but it is
**not proof of the fix**: disabling the rebuild leaves it green, because the suite never
produces a non-retrace pass whose plan moved. It is a regression guard.

---

## A correction, so nobody re-derives the wrong thing

An earlier commit message and history entry called *"Main and Sub reported changed while
carrying the same items"* a pattern **confirmed from the artifact**. It was not. That output
came from a **replay fixture** that had assumed both plans carried Main.

The real cause is the level-sync weapon hold, behaving correctly. What made it look like a bug
was a renderer ambiguity — a slot the plan skipped printed the *winner's* item, formatted
identically to a piece that had gone on. Fixed in `03e`/`03f` (`(not placed)`).

The general lesson, worth keeping: **a replay fixture proves the renderer, never the engine.**
Shape a fixture the way you expect records to look and it will agree with you.

---

## Risk surface of the v163 change

Small but real — it is in the equip engine's hot path.

- `slotSrc`/`floorTbl` are now allocated and filled on **every** dispatch, not just retraces.
  The `if retrace` they shared also gated the `/dl why` line formatting (a `string.format` per
  rule); only the formatting stayed gated. Cost is a handful of table writes next to the
  `equipSetByName` that already ran.
- The contest may now be rebuilt on a non-retrace pass. That is one extra `M.arbExplain` on the
  rare pass where the plan outran its explanation.
- If a performance problem is ever traced here, the cheap mitigation is to narrow
  `_planOutrunsContest` back to coverage-only (drop the item comparison); the item half exists
  because the level is not in the signature.

---

## Not built, deliberately

- **The level in the retrace signature.** That is the root-cause fix for *stale traces*
  generally, not just the contest. Rejected for now: it would change retrace cadence globally,
  and a flapping level reading during a sync landing would churn the Trigger Monitor's fired
  ring. The contest guard was the right-sized fix. Revisit only with a reason.
- **Engine-recorded flatten refusals** — having the engine record *"this entry was dropped at
  flatten, and why (level/job/not owned)"* would answer "my set did nothing" at the decision
  instead of by inference from the digest's second list. Touches the trigger floor.
- A Menu row for the recorder. Discovery is currently the Monitor button, `/dl report`, and the
  README's "Something went wrong?" section.

---

## Files

`feature/report.lua` (the recorder) · `ui/arbmonui.lua` (the button) · `dispatch.lua`
(`M._planOutrunsContest`, the contest rebuild, always-on attribution) · `feature/sendlog.lua`
(`M.observer`) · `feature/check.lua` (`M.gather`) · `docs/reference/report-format.md` (**read
this before reading a player's report**) · tests `RPT*` in `run_tests.lua`, `PO*` in the
decision-ring section, `AM9`–`AM11` in `smoke_ui.lua`.

---

## Branch note

`dev` carried parallel work on 2026-08-02 (floating-armor / pin refactor in `dispatch.lua`
~5378-5436, `feature/pinwatch.lua`, `ui/tray.lua`; an E-Box-into-the-Teleport-menu thread).
Nothing collided with this train, but **stage by explicit path and re-check `git log` before
committing** — `dispatch.lua`, `tests/run_tests.lua`, `docs/history.md` and `dlac.lua` are all
shared surfaces.
