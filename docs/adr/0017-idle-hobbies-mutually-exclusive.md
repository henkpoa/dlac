# 0017 — Idle hobbies: one shared bar, one active at a time, one HELM switch

2026-07-24, requested by Henrik (refined across two rounds). Addon-state only — no
engine version bump (`dispatch.lua` is untouched). This decision **revises the UX
convenience** of ADR 0012's Amendment ("step 1.5", engine v98) while **leaving that
Amendment's claim-side co-claim engine fully intact**.

## Context

Four idle-activity gear overlays — **Craft, HELM, Fishing, Chocobo** — each own a
session-only switch that their watcher writes to a per-character Statefile; the
engine reads those files and the Arbiter (ADR 0012) settles which claim wins each
slot. Each also had its own floating "bar" window (`ui/craftbar`, `helmbar`,
`fishbar`; Chocobo had only its panel), and HELM had **two** switches — a manual
"Set HELM Idle" (dresses immediately while idle) and "Auto HELM" (dresses only near
a gathering Point).

ADR 0012's Amendment deliberately removed the pre-Arbiter "newest-armed
exclusivity" so the four could **co-claim**, and recorded that claim-side rule as a
**dead end**: it lived inline in `M.dispatch` and reached across at dispatch time to
silence a peer's gear *claims* wholesale (the AR10/PUP case — arming HELM yanked the
fishing rod out of Range). Henrik now wants these treated as competing *hobbies*:
one at a time, in one shared bar, with a single HELM switch.

## Decision

**1. Mutual exclusion at the ENABLE toggle — lock-while-active, not the dead end.**
`feature/idleexcl.lua` is the coordinator. Each watcher's `setEnabled(true)` (and
helm's `setAutoHelm(true)`) calls `idleexcl.guardActivate(key)`, which **refuses**
the arm when another hobby is already active (a one-line hint names the one to turn
off). We do **not** auto-disarm the running hobby — you turn it off, then arm the
next. Because only one hobby is ever *armed*, the engine's co-claim / Arbiter never
sees a conflict among the four — it is untouched, and tests AR8/AR9/AR10 (which stub
state files and never call `setEnabled`) keep passing. This is an *enable-layer*
guard, a different seam from the recorded claim-side dead end, which stays dead.

**2. One shared "hobby bar" (`ui/hobbybar.lua`).** The three separate bar windows
are unified into a single window with a `Craft | HELM | Fishing | Chocobo` selector.
Opening any hobby's bar (`/dl <hobby> bar`, the header button, a panel's "Show bar")
opens this one window on that hobby. The three existing bar bodies were extracted
verbatim into `<bar>.renderContent(availW)` and are drawn by this window; Chocobo —
which never had a bar — gets a minimal section here. It is a float on the
`floatgear`/`idlefloat` pattern (rendered from gearui's `d3d_present`, stays up while
you play); visibility is `ui._hobbyBar`, selection `ui._hobbySel`.

**3. The selector marks the active hobby and locks while it runs.** The active
hobby's tab is green with a trailing `*`; while a hobby is active the selector is
pinned to it and the other tabs are locked (dim, un-clickable) — you can only switch
once the current hobby is off. That mirrors the enable-layer rule at the UI: the bar
never lets you reach a second hobby's arm button while one runs.

**4. One HELM switch: Auto HELM.** The manual "Set HELM Idle" toggle is removed from
every UI surface (panel, quick menu, bar) — two toggles was confusing and Auto HELM
works best (Henrik). Auto HELM becomes the sole HELM switch; `idleexcl`'s HELM member
keys on `isAutoHelm`. The manual `setEnabled` primitive stays in the engine/state
(unwired) so nothing downstream breaks, and `helmStateActive` already falls through
to the auto path. Trade accepted deliberately: HELM gear now equips only near a
`<category>` Point (or after a swing), never "always on regardless of location".

**5. The floating badge (`ui/idlefloat.lua`) stays.** It names the one active hobby
with an Off button when the bar is closed; self-gates on `idleexcl.getActive()`.

No load-time cycle: the watchers require `idleexcl` and `idleexcl` requires the
watchers, but only inside function bodies (lazy `try`).

## Alternatives rejected

- **Restore the claim-side newest-armed exclusivity** (the ADR 0012 dead end).
  Rejected on sight — it silences a peer's *slots* at dispatch time (AR10). The
  enable seam keeps the decision in the features, off the engine.
- **Auto-disarm the running hobby when you arm another** (the first-round design in
  this PR's history). Henrik chose lock-while-active instead: arming a second hobby
  is refused, not a silent takeover, and the shared bar's lock makes that visible.
- **Keep the two HELM switches.** Rejected — "confusing to have two" (Henrik); Auto
  HELM is the one that works best.
- **Leave Chocobo out of the shared bar** (it never had one). Rejected — "shared
  between them all"; it gets a minimal tab.

## Enforcement

- **IE\* headless tests** pin the lock at the enable seam: arming one hobby refuses
  the others (`canActivate`/`guardActivate`), `getActive` names the armed one,
  `deactivate` stands it down, HELM is Auto-only.
- **HB\* smoke tests** drive `hobbybar.render` against a stub imgui in the idle and
  active-lock branches and assert the Begin/End and PushStyleColor/PopStyleColor
  stacks return to 0 — the floatgear S50 crash class (a push/pop imbalance is native
  UB, no Lua error).
- **AR8/AR9/AR10 stay green, unchanged** — the co-claim engine is untouched.
- `idleexcl` / `idlefloat` / `hobbybar` are on the source-scan roster.

## Consequences

- Only one of the four idle hobbies runs at a time; the shared bar and the badge
  both show which, and switching means turning the current one off first.
- **The AR10 combination is no longer expressible** (HELM armor + a fishing rod in
  Range at once), because Fishing and HELM can't both be armed. Deliberate — these
  are hobbies now, made transparent by the bar's active mark and the badge.
- HELM no longer has an "always-on regardless of location" idle set; it equips near
  a Point. This is the one capability traded for the single, clearer switch.
- The claim-side dead end **stays dead** — this ADR does not touch it. If two hobbies
  ever need to dress different slots again, the answer is the Arbiter (co-claim), not
  a claim-side stand-down, and this lock would be the thing relaxed, not the engine.
