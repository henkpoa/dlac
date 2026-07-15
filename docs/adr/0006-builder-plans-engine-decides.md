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

## Addendum (2026-07-15): reserved slots are the engine's call too

Some items take a slot away while worn — the Ryl.Ftm. Tunic (Body) reserves Head,
robes reserve Hands, a boomerang (Range) reserves Ammo, party suits reserve most of
the body. It is the server's `item_equipment.rslot`, and it is the same shape of
problem as the Main/Sub pair: **item identity, not game state.** Equipping into a
reserved slot is not something the server half-tolerates — it strips the piece back,
dlac re-equips it, and the two flap forever (Henrik's report: "it just flashes back
and forth infinitely").

ffxi-lac solved it at BUILD time (`BuildDynamicSets` stripped `currentSet.Head` when
the body carried a `CannotEquipHeadgear` flag), and that code was ported into dlac's
`utils.lua` verbatim. Both halves of it were wrong here, which is why the bug survived
the port:

- **Wrong altitude.** Sets overlay (ADR 0003). A Head this set owns is perfectly
  legal under a higher-priority trigger that swaps the Body out — stripping it during
  the build silently loses it. And the build cannot see the slots MP-EQUIP writes that
  no set ever named, or what a virtual/AutoAcc marker resolves to.
- **Wrong data.** `CannotEquipHeadgear` was never a dlac field, so the ported check
  read nil every time — dead code. (In ffxi-lac itself it was hand-authored from
  parsed description text and only ever true for 2 items; the parser mangled the flag
  on the Ryl.Ftm. Tunic, so the exact reported item was broken there too.)

The rule now lives once, in `dispatch.reservedDrops`, as a post-pass on the FINAL
resolved names — the same place and shape as the craft Sub guard. The reserver wins
and the reserved slot is dropped (= left as worn; the server clears it anyway).
Worn pieces reserve as well as planned ones: a set that only writes Head still has to
answer to the Tunic already on your back. Slots resolve in a fixed order so mutual
reservations settle identically every pass instead of by `pairs()` luck.

Consequences:
- `RSlot` (the mask) rides in gear.lua per item, exactly like `Type`/`OneHanded`/
  `Count`, because the LAC-state engine has no catalog: the scan stamps it and
  **`/dl fix` backfills it** into files written before v43. Unstamped = invisible =
  pre-v43 behavior, never a wrong drop.
- The client resource has no such field — reservation is server data, so `catalog.lua`
  is the only possible source (`apicrawl.py` carries `rslot`, masking out the item's
  own bit; a few records repeat it and would otherwise read as "removes itself").
- Tests: section AK (`reservedDrops` + the wiring through the manifest), E7–E11
  (the `/dl fix` backfill, idempotent).

### Addendum 2 (2026-07-15, v44): "the FINAL resolved names" has a seam — overlays

The pass above is correct *within one `equipResolved` call*, and that is the whole
catch: it judges ONE table at a time. The craft overlay (v31) and pins (v44) each land
in their **own** `equipResolved`, so neither the set's pass nor the overlay's pass can
see the other:

- the SET's pass judges the set's plan, and never learns that the overlay is about to
  put a reserver in Body;
- the OVERLAY's pass knows its reserver's mask, but the drop loop can only drop slots
  its **own table names** — and the overlay's table does not name the Head it reserves.

So the set equips Head every pass, the overlay equips the reserver, the server strips
Head, and the flap this ADR exists to kill is back — reached the long way round. It
went unnoticed for the craft overlay because craft gear is a narrow, known catalog; a
**pin is any item you own**, including the Ryl.Ftm. Tunic that motivated v43 in the
first place.

Fixed the same way as the Sub/Main conflict rather than by widening `reservedDrops`:
what a top-priority overlay reserves becomes a **stateless hold** (`pinReservedSlots` →
`ctx.pinReserved`), computed per dispatch and consumed inside `equipResolved` next to
the slot locks. Unpin and the slot dispatches normally on the very next pass — nothing
to restore, nothing to leak (the ruling in `memory/engine-native-over-commands`).

The general lesson for the next overlay: **"post-pass on the final names" only holds
for names in the SAME table.** Anything applied as a separate, later `EquipSet` has to
declare what it takes away from the passes below it.

Not done: the craft overlay still has the un-held version of this hole. Checked against
the whole catalog rather than assumed — **387 items carry an `RSlot`, 77 carry a craft
stat, and the intersection is empty** — so no craft ladder can currently put a reserver
on you, and the hole is unreachable. Left alone deliberately rather than fixed blind. If
a craft rung ever gains a reserver (a re-crawl is the thing that would change this),
`ctx.pinReserved` is the shape to reuse: build it from `cEquip` too and pass it the same
way.
