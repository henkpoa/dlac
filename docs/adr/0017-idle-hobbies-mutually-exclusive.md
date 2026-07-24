# 0017 — Idle hobbies are mutually exclusive at the enable toggle, with a floating badge

2026-07-24, requested by Henrik. Addon-state only — no engine version bump
(`dispatch.lua` is untouched; contrast ADR 0012). This decision **revises the UX
convenience** of ADR 0012's Amendment (history.md "step 1.5", engine v98) while
**leaving that Amendment's claim-side co-claim engine fully intact**.

## Context

Four idle-activity gear overlays — **Craft, HELM, Fishing, Chocobo** — each own a
session-only `enabled` switch that their watcher (`feature/craftwatch.lua`,
`helmwatch.lua`, `fishwatch.lua`, `chocowatch.lua`) writes to a per-character
Statefile; the equip engine reads those files and builds one gear *Claim* per
armed activity, and the Arbiter (ADR 0012) settles which claim wins each
contested slot.

ADR 0012's **Amendment** (step 1.5) deliberately removed the pre-Arbiter
"newest-armed exclusivity" so the four could **co-claim** — the PUP field case
(AR10): arming HELM must not yank the fishing rod out of Range, because HELM never
claims Range. The recorded **dead end** was precise: *newest-armed exclusivity as
a **claim-side** rule* — a second decision point living inline in `M.dispatch`
that reached across at dispatch time and silenced a peer's claims wholesale. The
principle it established: **claimants decide WHETHER to claim, the rank decides
WHO WINS each slot, and never again does a claimant silence a peer wholesale.**

The consequence ADR 0012 accepted — "arming no longer switches activities; walking
from the bench to the pond means disarming Craft yourself" — is the UX Henrik now
wants reversed: these four are competing *hobbies*, only one makes sense at a time,
and the toggle should behave like a radio. The open question this ADR answers:
**how to bring back one-at-a-time without re-opening the dead end.**

## Decision

**Exclusivity lives at the ENABLE toggle, not at the claim.** A small coordinator,
`feature/idleexcl.lua`, holds the four members; each watcher's `setEnabled(true)`
(and helm's `setAutoHelm(true)`) calls `idleexcl.onActivated(key)`, which stands
the **other three** down via their own `setEnabled(false)`. Because only one hobby
is ever *armed*, the engine's co-claim / Arbiter is never presented with a
conflict among the four — it is untouched, and the dead end's failure mode (a
claimant silencing a peer's *slots* at dispatch time) literally cannot occur here.

1. **The enable seam catches every surface.** Every bar, panel pill, Automations
   row, Teleports quick-menu flip, and `/dl` command funnels through exactly one
   `setEnabled` writer per watcher. Hooking `onActivated` there covers all of
   them at once — no UI file is touched. Re-entrancy is impossible: `onActivated`
   fires only on `true`, and the stand-downs it issues go through `setEnabled(false)`
   (which never calls `onActivated`); a `_standingDown` guard makes that a hard
   guarantee.

2. **HELM counts both its switches.** HELM has two activation paths — the manual
   "Set HELM Idle" and proximity **Auto HELM**. For the radio, "HELM armed" =
   either one; arming a peer clears **both**, and arming HELM (either way) stands
   the other three down. So a background Auto HELM cannot dress alongside Craft.

3. **A floating badge names the one, and turns it off.** `ui/idlefloat.lua` is a
   float on the `floatgear`/TP-button pattern (rendered straight from gearui's
   `d3d_present`, its own theme bracket — it stays up while you play, outside
   uihost's window contract). It **self-gates on `idleexcl.getActive()`**: it
   draws a small draggable chip naming the armed hobby (plus its craft / gather
   category / fishing target, and an "(auto)" tag for Auto-only HELM) with an
   **Off** button, and draws *nothing* when none is armed — so the badge appears
   the instant a hobby is activated and vanishes the instant it is turned off,
   with no user visibility flag to manage. Position persists (`ui._idlePos` →
   uiflags `ifx/ify`); visibility never does, because it is derived.

4. **No load-time cycle.** The watchers require `idleexcl` and `idleexcl` requires
   the watchers, but only ever inside function bodies (lazy `try`), so neither
   load pulls the other.

## Alternatives rejected

- **Restore the claim-side newest-armed exclusivity** (the ADR 0012 dead end). It
  reaches across at dispatch time to silence a peer's slots wholesale — the exact
  failure AR10 pins. Rejected on sight; this ADR exists to get one-at-a-time
  *without* it.
- **A "keep only one" pass in the engine read-side** (`dispatch.lua` where
  `craftOn/helmOn/fishOn/chocoOn` are derived). This would re-introduce a second
  settling law fighting the Arbiter, need a tiebreak (`at` stamp), and put the
  decision back inside `M.dispatch` — the very place ADR 0012 emptied. The enable
  seam keeps the decision in the features, off the engine entirely.
- **Fold Auto HELM out of the radio** (exclude only the manual idle toggles). It
  leaves a background Auto HELM dressing alongside another hobby — "should not be
  active at the same time" (Henrik) reads HELM as one thing. Rejected.

## Enforcement

- **New IE\* headless tests** pin the radio at the enable seam: arming each of the
  four disarms the other three, Auto HELM is a HELM activation and is cleared by a
  peer, `getActive` names the armed one (with detail), `deactivate` stands it down.
- **AR8 / AR9 / AR10 stay green, unchanged.** They exercise the engine's co-claim
  by stubbing state files and calling `arbResolve` directly — they never go through
  `setEnabled`, so the enable-layer radio does not touch them. The claim-side
  co-claim law of ADR 0012's Amendment remains true at the engine level.
- `idleexcl` / `idlefloat` join the source-scan roster (the `GRD0` file-count and
  the interpreter-require guards).

## Consequences

- **One combination is no longer expressible: the AR10 PUP case** — HELM's seven
  armor slots *and* a fishing rod in Range at once — because Fishing and HELM can
  no longer both be armed. This is the deliberate reversal of ADR 0012's accepted
  consequence; it is a *hobby* choice now, made transparent by the badge (you can
  always see which one is on, and turn it off in one click), which was the missing
  piece that made the old auto-switching feel silent.
- The Automations rows, bars, and quick menu need no change: each reads
  `isEnabled` per frame, so enabling one shows the others flip to OFF on the next
  render for free.
- The claim-side dead end **stays dead** — this ADR does not touch it. If a future
  need wants two hobbies dressing different slots again, the answer is the Arbiter
  (co-claim), not a claim-side stand-down, and this radio would be the thing
  relaxed, not the engine.
