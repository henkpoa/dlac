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

## Stage 1 — the hold (BUILT, engine VERSION 9)

- `dispatch.mpHoldNeeded(wornMP, targetMP, curMP, maxMP)` — the pure rule
  (tests I1–I7). Weapons exempt (`MP_HOLD_EXEMPT`), `dlac:` virtual markers
  exempt (the staff/obi automation keeps priority in its two slots).
- Active while the **`maxmp` toggle mode** is ON (`/dl mode maxmp`, or a
  Triggers-tab chip once the mode exists). Every dispatch then checks each
  slot: worn item read from equipment memory, MP values from the **autogear
  manifest's new `mp` map** (lower(name) → flat MP for every owned piece;
  written by the Automations rescan, auto-regenerated on login/job change —
  the engine never loads the catalog, ADR 0004).
- Held slots are stripped from the applied set with a `/dl why` note:
  `head=MP-HOLD Wise Cap +1 (+45 MP unspent)`.

### How to use it today

1. Sets tab: Auto-build a set named e.g. `MaxMP` with an `MP` weight
   (weapons skipped) — or hand-build it. Commit, Reload LAC.
2. Triggers tab: add rules that equip `MaxMP` when you want the pool filled —
   e.g. `Default: status = Resting AND mode = maxmp -> MaxMP` (stack the mode
   condition so the rule only lives while the mode is on).
3. `/dl mode maxmp` — from then on, MP batteries stay on exactly until spent,
   released slot by slot as you cast.
4. Sublimation top-off works with a plain rule TODAY:
   `Ability: name = Sublimation, mode = maxmp -> MaxMP` — HandleAbility fires
   before the JA lands, so the MP grant arrives into the enlarged pool, and the
   hold releases the pieces as it is spent. (It also fires on the initial
   charge activation, which is harmless: nothing grants MP, the hold releases
   immediately on the next dispatch.)

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
