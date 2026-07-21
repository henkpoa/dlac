# 0012 — Claim/Arbiter: one decision point for gear claims, user-orderable

2026-07-21, grilled and confirmed by Henrik. Engine target: the v97+ migration series.

## Context

Six features want gear on beyond the Trigger overlay floor: Pins, AutoAmmo, MaxMP, Craft,
HELM, Fishing. Their precedence lived in **three separately-encoded constructs** in the
engine — the hardcoded overlay application sequence at the bottom of `M.dispatch`, the
per-slot first-claim-wins `elseif` chain inside `equipResolved`, and `POST_ORDER` (the
only data-driven one, covering just the five post-passes). MaxMP was not a stage at all:
every overlay's resolve re-ran the band plan, which is why batteries silently overrode
HELM/craft/fish armor. Pins beat user locks by construction (the pin overlay never checked
locks). None of this was visible to the player, and none of it was changeable.

## Decision

- **Claim** = a feature's declared wish to dress one or more slots; **Arbiter** = the
  single decision point (both in CONTEXT.md).
- One **strict, draggable priority list per character** (no numbers), persisted as the
  `arbstate` Statefile. Per slot, walk top-down; the first claimant claiming the slot
  wins. Triggers are a fixed floor row — wanting a claimant below the floor is the same
  as turning it off, and every claimant has its own switch.
- **Claimants decide WHETHER to claim; the Arbiter decides WHO WINS.** Claim-side rules
  stay inside the features: newest-armed exclusivity among Craft/HELM/Fishing (tie
  craft > helm > fish) — **SUPERSEDED, see the Amendment below**, AutoAmmo's stand-down
  while fishing is live, MaxMP's `'remove'`-respect, movement yield, sticky pairs and
  stage-eligibility (ADR 0010). The Arbiter never re-derives a feature's conditions.
- **Locks are a draggable VETO row**: a claim above it punches through, a claim below it
  stops. Default position directly under Pins — which preserves the previously-hidden
  Pin > Lock law while making it visible and user-changeable.
- **Default order: Pins > Locks (veto) > AutoAmmo > MaxMP > Craft > HELM > Fishing >
  Triggers floor.** Reproduces live behavior with ONE deliberate change: AutoAmmo's named
  projectile now beats a MaxMP battery in Ammo (Henrik's ruling — a shooting job must
  never fire its stat-trinket ammo, and AutoAmmo only ever claims the one slot).
- **Migration is incremental** — four sequential engine steps, each its own engine
  version with headless tests: (1) claim registry + arbstate + rank-ordered application,
  with woven MaxMP consulting rank ("never contest a slot won above me"); (2) the
  Automations-tab Priority section; (3) the Locks veto fold; (4) collapse of the
  remaining hardcoded arms + `/dl why` claimant attribution. Field-test attribution is
  the scarce resource, not coding time — a big-bang rewrite would hand any regression
  six suspects.

## Alternatives rejected

- **Numeric priorities** — the claimants are a small closed set; drag-to-reorder is the
  honest UI. (Triggers keep numbers because rules are open-ended and user-authored.)
- **Per-job lists** — config surface multiplied for a conflict that is rare; revisit
  only on field demand.
- **Absolute locks** — silently no-ops a pin into a locked slot, and changes live
  behavior.
- **Big-bang rewrite** — one giant field round where any regression could be any of six
  features, on corner cases (`'remove'` semantics, sticky pairs, pin reserves,
  sub-pairing guards) that each cost real field rounds to pin down the first time.

## Amendment — activities co-claim (2026-07-21, after the step-1 field round)

The newest-armed exclusivity among Craft/HELM/Fishing was carried into the Arbiter as a
claim-side rule; the first field round falsified it. Field case (PUP): idle floor names
Range = Animator; Fishing armed put Lu Shang's in Range — then arming HELM stood Fishing
down **wholesale**, and the Animator returned to Range even though HELM never claims
weapons, Range, rings or Ammo.

The exclusivity was the pre-Arbiter conflict resolution — with rank arbitration in
place it is redundant, and it actively defeats per-slot composition. **Ruling (Henrik):
all three activity claimants claim whenever armed; the rank list settles every overlap
per slot.** Each feature's own gates are untouched (idle-only stand-asides, Default-only
application, AutoAmmo's fishing stand-down). The `at` stamp loses its arbitration role.

Consequence, accepted deliberately: **arming no longer switches activities** — walking
from the bench to the pond means disarming Craft yourself (quick menu / panel);
`/dl prio` shows every concurrent claimant. Implemented as step 1.5 (between step 1 and
the UI step).

## Consequences

- The next claimant (AutoAcc, when GM-approved) is one registry entry plus a rank row,
  not three code edits.
- Deliberately below/outside the Arbiter's altitude: settle/proximity holds and the
  PetAction gate (temporal dampers with no gear opinion); within-set resolution
  (AutoStaff/AutoObi virtual entries, Dynamic flattening, the ADR 0010 trinket
  contests).
- Until step 4, woven MaxMP code consults the rank table from inside other claimants'
  resolves — accepted scaffolding, retired by the cleanup step.
- `/dl why` gains claimant names and ranks per slot.
