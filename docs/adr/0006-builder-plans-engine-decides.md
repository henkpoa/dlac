# The builder is a plan; the engine decides at equip time

Set building never gates on current game state. The Sub-slot picker offers every 1H
weapon the job (main OR support) can ever wield, regardless of whether Dual Wield is up
right now; the ordered slot list carries both the weapon and the shield/grip. At equip
time `utils.subSlotAllowed` resolves legality: 2H main → grip only; 1H main → shield
always, a 1H weapon only when the Dual Wield trait bit (`HasAbility(1554)`, live memory,
authoritative both ways) is set. `utils.classifySub` distinguishes grips from shields by
name ("* Grip"/"* Strap") because the catalog collapses both into `Type="Sub"`.

We rejected gating the builder on `isDualWieldAvailable()` — the original bug: a
sub-job change or trait loss would make sets unbuildable/invalid, and it contradicts how
the pre-dlac profile worked (the principle is lifted from Henrik's old ffxi-lac code).
One deliberate asymmetry stands: GUI surfaces that equip immediately (the Equipped tab's
Alternatives list) DO gate on live DW; Auto-build currently also builds equip-correct
(shield when no DW) — making it plan-style is an open decision.

Consequences:
- The pairing rule lives once in `utils.subSlotAllowed` (shared engine + GUI); Main
  resolves before Sub explicitly (never rely on `pairs()` order).
- gear.lua entries need `Type`/`OneHanded`; the engine reads raw gear.lua in LAC's
  state, so GUI-side catalog enrichment is not enough — `/dl fix` backfills the fields
  and new imports stamp them at generation time.
- Test suite sections A–C lock the rule (`building=true` vs equip-time contexts).

## Addendum (2026-07-12): building is MAIN-INDEPENDENT — hard rule, 3× reverted

This decision regressed **three times**: each time, some part of the builder was
"helpfully" re-gated on live state (the DW trait, or the *shape of the planned Main* —
a 2H Main narrowed the Sub picker to grips; an empty Main plan emptied it entirely).
Henrik, verbatim: *"Yes, I know, I have /SAM. Yes, I know, it has chosen a 2h-weapon.
I don't care, I want freedom to build sets so I can set correct triggers for when I do
dual wield. I don't want that to lock me down. […] always show available one-handers."*

The rule, stated so it cannot be mis-shrunk: **while building (`ctx.building == true`),
the Sub-slot offer never adapts to ANYTHING live — not the DW trait, not the planned or
equipped Main, not the sub job.** Every owned, job/level-usable Sub-capable item is
offered: shields, grips, AND one-handed weapons, always. The only building-time
exclusions are physical impossibilities: a 2H weapon cannot sit in Sub, and a same-name
off-hand needs a provable second copy (a copy count >= 2, from the record's scanned
`Count` or the caller's live `ctx.copies` — item identity, not game state; the legacy
`InBothHands` flag was removed 2026-07-13). Sets feed *triggers*; a set planned for
"when I dual wield" must be
composable while you are not dual wielding. Wrong-pairing safety is the ENGINE's job,
per cast, with the list's shield/grip as fallback — exactly this ADR's title.

Enforcement (all three must survive any refactor):
- `utils.subSlotAllowed` — the `ctx.building` branch runs FIRST, before any
  Main-shape logic, with the hard-rule comment block on it.
- `gearui.subCandidateOk` (fallback mirror) + `subFilterAnyMain` (an empty Main plan
  offers everything — Sub-only sets are legitimate).
- Tests: the `A* HARD RULE` checks in `tests/run_tests.lua` are written to FAIL on any
  re-gating. If one of those checks is in your way, you are the fourth reversal — stop.

Equip-*now* surfaces (Equipped tab Alternatives) remain live-gated by design, and
Auto-build remains equip-correct ("best usable now") — still an open decision, but its
output never constrains what the picker offers.
