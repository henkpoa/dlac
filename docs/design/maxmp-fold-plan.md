# The MaxMP fold — stage 6 implementation plan (ADR 0027)

> **EXECUTED 2026-07-27 (engine v151, addon `27zm`; 4059 checks, Windows + WSL) —
> FIELD-CONFIRMED same day: "MaxMP mode seem to work just like before". The known
> pre-fold earring oddity (Cassandra's over Outlaw's) persists as expected and has
> its own diagnosis session pending.**
> Three deltas surfaced during the splice, all in the shipped code:
> 1. **The rank order hoists above the claim build pass** — the plan said the claim
>    "moves into the registry row" but the build pass ran before `rankOf` existed;
>    now `ctx.rankOf` is set before ANY builder runs (ranks exist before anyone
>    claims), and `mpBands`' lock consult reads it directly (edit 4's
>    "inline-ordered" caveat dissolved).
> 2. **The same-dispatch view includes unapplied above-rank claims** — the weave ran
>    inside every layer's `equipResolved` and saw stronger rows' tables live;
>    `ctx.planOut` alone loses that sight (a pinned ring could duplicate a battery's
>    sibling). The apply builds an `above` map from `env.built` + `ctx.rankOf`
>    (strongest claim per slot) and the sticky/eligibility gates read
>    `above → planned → worn` (ARE5 pins it).
> 3. **`mpBands` memoizes on ctx** — one dispatch samples one moment (the ratified
>    purity ruling); the claim build, the row apply and the mp-hold constraint all
>    see the same bands.

> Henrik's go, 2026-07-27 night: *"you had some good terms what to call
> everything, you can go over the code and see if there's anything to fix
> while you integrate it into the arbiter as well."* Law read first:
> docs/design/maxmp-mode.md (rulings ledger + failure museum). The bands
> (`feature/mpbands.lua`, pure) decide WHEN and are UNTOUCHED; the resolvers
> (mpRungs/mpBestPick/mpStickyPairs/mpStageEligible, pure) decide WHAT and
> are REUSED; only the DELIVERY — the woven per-slot branch + mp-stage pass —
> translates into the ratified vocabulary.

## The translation table (woven → ratified)

| Woven behavior | Becomes |
|---|---|
| target = rung name, worn == rung (hold set piece out) | MaxMP's CLAIM wins the slot by rank; the battery lands over the floor piece (satisfied-check sends nothing when already worn) |
| target = rung, worn ≠ rung (hold + mp-stage writes) | the same claim write — upgrade is natural (museum #3 honored) |
| target = false (release) | MaxMP claims nothing there; the set piece flows |
| target = nil + worn MP-heavier (no-band protect) | the **mp-hold CONSTRAINT** — a named POST_ORDER member: `hold(mp-hold)` on the incoming piece; weapons (MP_HOLD_EXEMPT) and `remove` skipped as today |
| movement yield (MP-MOVE) | a GATE on the claim: while moving+setting, a slot whose incoming floor piece carries Movement+ is dropped from MaxMP's claim (read via ctx.planOut — the floor merged before MaxMP applies) |
| sticky pairs (MP-PAIR) | a GATE on the claim: mpStickyPairs with claimsOf = ctx.planOut + worn (independent vetoes — museum #7) |
| RSlot eligibility (MP-SKIP) | a GATE on the claim: mpStageEligible with occupants = ctx.planOut or worn |
| explicit `remove` beats batteries (v91) | a GATE: a slot whose ctx.planOut value is 'remove' is never claimed (fishing/AutoAmmo rank above still overwrite by apply order regardless) |
| mp-stage "uncovered slots join" | gone as a concept — the claim covers every band target; coverage no longer depends on what sets name |
| ctx.mpCeded (never contest above) | APPLY ORDER — claims above MaxMP apply later and overwrite; the scaffolding deletes |
| ctx.mpRespectLocks | the row's ordinary `respect('MaxMP')` into equipResolved |
| MP-EQUIP/MP-HOLD/MP-RELEASE/MP-PAIR/MP-SKIP notes | the MaxMP row's apply traces its own line + gate notes |

## Edits

1. dispatch: NEW `mpApplyClaim(env)` — filter `claims['MaxMP']` through the
   four gates (remove-respect, yield, sticky, eligibility) against
   env.ctx.planOut + worn; equipResolved(filtered, ctx, respect('MaxMP'));
   trace line + gate notes. Wire as the MaxMP row's `apply`.
2. dispatch: POST_ORDER gains `mp-hold` (replacing the branch's no-band
   protect): maxmp on + no band target + worn MP > incoming MP + not
   exempt/remove/locked → nil + note. The rest of the woven branch DELETES.
3. dispatch: mp-stage pass DELETES from POST_ORDER (absorbed by 1).
4. dispatch: mpCeded computation + ctx.mpRespectLocks DELETE; mpClaimFor
   stays (the claim source) and moves into the registry row's `claim` (still
   inline-ordered after rankOf — now only because respect needs rankOf).
5. Tests: weave-specific W* checks translate (drive the row apply + the
   mp-hold pass); MB*/MPS*/MSS*/MPL* pure families untouched.
6. Parity gates before the weave text deletes: suites both runtimes; the
   worked example (MB1: TOTAL 1100, feet 5→15, tick 15 → off 1075, on 1085)
   must still print identically via /dl plan (same mpBands context).

## Review findings (the "anything to fix" pass)

- The Cassandra's-vs-Outlaw's field oddity: candidate causes are manifest MP
  data (fmt/augment fold) or band ordering (rfDelta/diff) — diagnosable via
  /dl plan capture; the fold does not change either input, so the oddity is
  data or ordering, not delivery. Await Henrik's /dl plan.
- mp-stage's uncovered-slots arm could historically write a battery into a
  slot NO set ever names and leave it there when the mode turns off
  (documented as intentional); the claim model keeps this behavior only
  while the mode is ON — a battery in a never-named slot now releases when
  MaxMP stops claiming it... it does NOT: no claim = engine says nothing =
  worn stays. Behavior preserved.
