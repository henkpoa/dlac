# Max-MP mode — design (staged)

Henrik's spec, 2026-07-11: *"Find the piece with the highest MP, keep that piece
active until you have spent enough MP for any potential pieces that would be
equipped."* Example: a +50 MP head vs trigger sets whose lowest head gives +5 MP
→ the head may swap out once 45 MP has been spent. Applies to every slot except
Main/Sub/Range (TP preservation). Plus: resting-recovery-aware re-equipping, and
topping off before a completed Sublimation is popped.

## The key insight

The engine-side rule is **generic and slot-local** — it does not care how the MP
gear got equipped (a resting set, a trigger, a manual equip):

> Keep the WORN piece while swapping it for the incoming piece would waste
> unspent MP: `hold when curMP > maxMP − (wornMP − incomingMP)`.

Everything else — *which* MP gear to put on and *when* — is data (sets and
trigger rules), which the existing machinery already handles. This mirrors the
"builder is a plan, the engine decides" split (ADR 0006).

## Stage 1 — equip + hold (BUILT, engine VERSION 10)

`/dl mode maxmp` is the whole interface — no set-building required:

- **MP-EQUIP**: whenever the pool is FULL (`curMP >= maxMP`), each dispatch
  wears the slot's best owned battery instead of the set piece (per-slot picks
  from the manifest's `mpBest` map, level-checked; ear/ring carry the top two).
  Full-pool gating is what makes equipping worthwhile: batteries only pay when
  recovery (refresh, resting, sublimation) can land into the larger pool.
- **MP-HOLD**: the battery then stays until its surplus over the incoming piece
  is spent — `hold while curMP >= maxMP − (wornMP − incomingMP)`. The boundary
  is `>=` on purpose: a battery equipped at a full pool sits exactly on it, and
  a `>` rule would drop it before any recovery landed (field case: 960/960,
  Cleric's Bliaut +29 → Bunzi's Robe +50). Release requires spending strictly
  past the surplus; a released slot has a 15 s re-equip cooldown so the
  full/spent boundary can't churn gear per action.
- Weapons exempt (`MP_HOLD_EXEMPT`), `dlac:` virtual markers exempt (staff/obi
  automation keeps its two slots). Both decisions annotate `/dl why`:
  `body=MP-EQUIP Bunzi's Robe (+21 MP)` / `body=MP-HOLD Bunzi's Robe (+21 MP unspent)`.
- Data: the autogear manifest's `mp` (lower(name) → flat MP, every owned piece)
  and `mpBest` (slot → best battery) maps — written by the Automations rescan,
  auto-regenerated on login/job change; the engine never loads the catalog
  (ADR 0004). The pure rule is `dispatch.mpHoldNeeded` (tests I1–I7).
- Caveat: MP-EQUIP only touches slots the active sets address (the dispatch
  walks the applied set's slots); a slot no set ever writes keeps whatever is
  worn. In practice trigger sets cover the wardrobe.

### Optional extras

- Sublimation top-off as plain trigger data:
  `Ability: name = Sublimation, mode = maxmp -> <any MP-ish set>` — HandleAbility
  fires before the JA lands, so the grant arrives into the enlarged pool. With
  MP-EQUIP this is usually unnecessary (a full pool already wears batteries),
  but it forces the swap when the pool is NOT full at pop time.

## Stage 2 — resting escalation (NOT BUILT)

While `status = Resting` and the mode is on, progressively re-equip max-MP
pieces as the pool refills, so recovery is never capped early:

- **Measure, don't model**: CatsEyeXI's hMP traits are custom (private
  submodules; wiki incomplete). Instead of trait tables, observe the actual MP
  delta on each rest tick (~10 s cadence) from memory — self-calibrating and
  server-proof. (Trust ladder: live memory > wiki > public SQL.)
- **Headroom leeway**: equip the next MP piece when
  `maxMP − curMP < lastTickRecovery + margin` would otherwise overflow a tick —
  i.e. always keep at least one tick of headroom.
- **Replacement order**: fill slots whose RESTING pieces carry no hMP/Refresh
  first, so the recovery-boosting pieces stay on longest.
- Likely shape: a small engine-side state machine ticking on the Default
  dispatch while resting; candidates from the manifest `mp` map sorted by MP,
  filtered by an `hmp`/`refresh` map (manifest addition).

## Stage 3 — refinements (NOT BUILT)

- Buff-aware Sublimation: gate the rule on the *completed* charge (buff id) so
  the top-off only fires on the release, not the activation. Needs a `buff`
  trigger condition — useful far beyond this feature.
- Percent MP gear (`MPP`) and convert gear in the manifest values.
- Waist: `dlac:AutoObi` vs an MP belt — today the obi automation wins its slot;
  revisit if a real conflict shows up in play.

## Open questions

- Does unequipping +MP gear on CatsEyeXI clamp current MP exactly as retail
  (cur = min(cur, newMax))? The hold rule assumes yes — field-verify with
  `/dl why` + the MP-HOLD notes.
- Rest tick cadence/size on CatsEyeXI (stage 2 measurement makes this moot,
  but knowing it helps pick the margin).
