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
