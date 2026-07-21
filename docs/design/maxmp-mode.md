# Max-MP mode — design (staged)

Henrik's spec, 2026-07-11: *"Find the piece with the highest MP, keep that piece
active until you have spent enough MP for any potential pieces that would be
equipped."* Example: a +50 MP head vs trigger sets whose lowest head gives +5 MP
→ the head may swap out once 45 MP has been spent. Applies to every slot except
Main/Sub/Range (TP preservation). Plus: resting-recovery-aware re-equipping, and
topping off before a completed Sublimation is popped.

## v2 — the BANDED LADDER (Henrik's redesign, 2026-07-21; BUILT overnight, engine v88)

Implementation homes: `feature/mpbands.lua` (the pure core — build/target +
tick measurement; tests MB*), `dispatch.M.mpBands` (the live context: LOW
scan over trigger-reachable sets, `M.mpBestPick` the ONE pair-veto-aware
battery resolver shared by engine/plan/builder — tests MPS8*, TOTAL anchor =
nativemp base + auto-learned merits + worn MP with an offset learned at any
true-full MP%), the rewired per-slot branch + `mp-stage` pass (batch apply
through the v78 RSlot guard), and `/dl plan` v2 (`M.mpPlanLines`, tests MPL*)
which renders the exact context the engine runs — the plan IS the behavior.
The manifest carries Refresh from fmtver 11 (`rf` map + rung `rf`).

**Round-9 addendum (2026-07-21, engine v90): MULTI-RUNG bands.** A slot's
battery ladder contributes one band per meaningful rung — rungs sanitized to
falling MP / rising Refresh (dominated rungs pruned), each adjacent pair
banded with its own diff and rfDelta, the last rung banding against the
potency point. The order collapses to ONE rule: **rfDelta ascending, then
diff ascending** — refresh-cost top-ups come off first and return last;
refresh-gain bands sink by magnitude (+1 releases before +2). Field pin
(names corrected round 9b, augments ALWAYS in the totals): Hlr. Bliaut +1
at 35+18 aug = **53 MP** tops the body ladder — Bunzi's Robe (50, flat) is
DOMINATED and pruned, never worn; Erudite Cap and the Hlr. Bliaut are the
shallow top-ups; **Bunzi's Hat (+1 Refresh) holds second-last; Clr. Bliaut
+1 (Refresh 1 native + 1 augment = 2) is the last thing to go and the
first thing back.** `target()` answers the piece NAME per slot (or false =
the set's piece); tests MB13*, S169b-e prove the augment fold end-to-end.

**Night addendum (Henrik, in-flight): "Refresh > least mp diff."** A battery
whose Refresh the potency piece lacks outranks the difference ordering and
sinks to the DEEP end of the ladder — released last while spending, back on
FIRST as MP recovers, so recovery accelerates as early as possible. Ties on
the LOW side assume the incoming piece lacks refresh (keeps the battery deep
— the safe direction).

Ruling after the 07-21 field night (rounds 6–7): **stop dynamic per-dispatch
marginal decisions; precompute the whole plan.** The v1 engine decided each
slot against LIVE max-MP reads every 0.4s — and this client cannot provide an
accurate max during gear churn (`GetMPMax` stale both directions; the party MP%
window is only ±1%). Result: false-full over-equips, boundary dumps, an
equip↔release oscillation (v87 patched it with exact-fullness + low-bias, but
the climb stayed a one-piece-per-refill staircase — "VERY roundabout", and
every extra swap risks MP). Henrik's design removes the live-max dependency
entirely:

**The precomputed band ladder.** For every non-weapon slot:
- `LOW` = the LEAST slot MP across ALL sets assigned to trigger rules (the
  "no max-MP gear" point — potency gear). Conservative minimum; per-set
  variation lands inside a band instead of moving thresholds. Virtual
  (`dlac:`) entries count their fallback.
- `HIGH` = the slot's best battery (the existing mpBest pick).
- `Difference = HIGH − LOW`.

Sort slots by `Difference` ASCENDING — lowest difference = first OUT to
potency (lowest-hanging fruit), highest difference releases last (big battery
stays longest, same philosophy as v76's smallest-surplus-first, now planned).
Then chain, in that order, each piece's data points (Henrik's spec verbatim):
- `MP Difference`
- `LastMaxMP` — nil for the first piece = TOTAL max MP (all batteries worn);
  otherwise the previous piece's EndMaxMP.
- `EndMaxMP` (the max after this piece is out) = `LastMaxMP − Difference`;
  the UNEQUIP trigger fires at `cur ≤ LastMaxMP − Difference − tick` (the
  tick margin means an incoming refresh tick can never be capped by the swap).
- `StartMaxMP` (re-equip trigger) = `EndMaxMP + Difference − tick` — the
  piece goes BACK ON before the pool is full, timed so the next tick lands
  into the battery's headroom (this replaces v1's exact-full gate AND solves
  old stage 2's headroom leeway in one move).

Worked example (Henrik's): TOTAL 1100; feet LOW 5 / HIGH 15 / diff 10 =
smallest → first band. Unequip at `1100 − 10 − 15(tick) = 1075`; post-swap max
1090; re-equip at `1090 + 10 − 15 = 1085`. The 1075..1085 gap is structural
HYSTERESIS — churn is impossible by construction, no cooldown needed (the 15s
cooldown survives only as a backstop).

**Per dispatch the engine does one cheap thing:** read CURRENT MP (the one
reliable number), walk the ladder → target loadout (which batteries should be
worn), diff vs worn, issue ALL needed swaps at once. Big steps are explicitly
fine (spell casts are big); the margins make batch moves safe.

**Refinements agreed on top of the spec:**
1. **Measure ticks, don't model** (the old stage-2 ruling): observe live MP
   deltas per tick for the refresh tick standing and refresh+hMP resting —
   CatsEyeXI traits are custom, live memory beats the repo. Self-calibrating;
   optional manual override. Resting uses the bigger measured tick in both
   trigger formulas (pieces re-equip earlier, per the spec).
2. **Anchor self-correction**: TOTAL is predicted (nativemp base + auto-learned
   merits + Σ battery MP) but corrected by ONE observed offset whenever MP%
   reads 100 (the maxmp≠modmp lesson: never trust computed absolutes alone).
3. **LOW recomputes** when sets/triggers change (the manifest-rebuild events).
4. **Bands decide WHEN; the existing machinery decides WHAT**: mpBest ladders,
   equippable-NOW filtering, the ear/ring pair veto (v83), the RSlot
   eligibility guard (v78) all stay underneath. `/dl plan` v2 prints the band
   table — the plan and the behavior become the same artifact.

Open implementation parameters: where the measured tick persists (modestate vs
manifest); the loadout signature for the anchor offset; whether Sublimation's
release counts as a "tick" for the Start margins (probably yes, measured the
same way).

## The key insight

The engine-side rule is **generic and slot-local** — it does not care how the MP
gear got equipped (a resting set, a trigger, a manual equip):

> Keep the WORN piece while swapping it for the incoming piece would waste
> unspent MP: `hold when curMP > maxMP − (wornMP − incomingMP)`.

Everything else — *which* MP gear to put on and *when* — is data (sets and
trigger rules), which the existing machinery already handles. This mirrors the
"builder is a plan, the engine decides" split (ADR 0006).

## Stage 1 — equip + hold (BUILT, engine VERSION 10; STAGED movement v76)

`/dl mode maxmp` is the whole interface — no set-building required — plus
`/dl plan` (v79): the battery plan as chat lines, per slot the live pick with
WORN/gain/LOCKED status and the full ladder, sorted biggest gain first (= the
full-pool equip order), with a stale-manifest tell in the footer. Chat-only
on purpose: the Automations tab stays maxmp-free (the hidden ruling).

- **MP-EQUIP**: whenever the pool is FULL (`curMP >= maxMP`), each dispatch
  wears each slot's best owned battery — for slots the set addresses (instead
  of the set piece) AND for slots no set writes at all (a bare ring slot is
  where a battery is freest to sit). The manifest's `mpBest` carries a LADDER
  of up to 4 candidates per slot (`dispatch.mpPick`, tests K1–K7): rung 1 may
  be gear to grow into (Bunzi's Robe at 99), and the engine wears the best rung
  wearable at the LIVE level. Ear/ring ladders are disjoint (alternating), so
  one physical item can never fill both slots; genuine duplicates (two Astral
  Rings) are listed twice via owned counts. MP value counts `ConvertHPtoMP`
  (Astral Ring = 25) and is LEVEL-EFFECTIVE via the central
  `levelstats.effective` resolver (Tamas Ring: 15 on paper, 29 at Lv74) — a
  snapshot at scan-time level, kept fresh by the constant auto-rescans.
  Full-pool gating is what makes equipping worthwhile:
  batteries only pay when recovery (refresh, resting, sublimation) can land
  into the larger pool. A battery in a slot no set writes stays worn when the
  mode turns off — nothing else ever touches that slot, and no MP is wasted by
  leaving it on.
- **MP-HOLD**: the battery then stays until its surplus over the incoming piece
  is spent — `hold while curMP >= maxMP − (wornMP − incomingMP)`. The boundary
  is `>=` on purpose: a battery equipped at a full pool sits exactly on it, and
  a `>` rule would drop it before any recovery landed (field case: 960/960,
  Cleric's Bliaut +29 → Bunzi's Robe +50). Release requires spending strictly
  past the surplus; a released slot has a 15 s re-equip cooldown so the
  full/spent boundary can't churn gear per action.
- **STAGED movement (v76)**: at most ONE battery moves per dispatch — the
  field complaint was the mode reading as an on/off switch (everything on /
  everything off in one dispatch). Releases pick the SMALLEST surplus first:
  the big battery stays on longest (the original spec), and the all-at-once
  release was also an accounting bug — each per-slot hold justifies removing
  only ITS piece, so N same-dispatch releases dropped max MP by the SUM of
  surpluses and the server clamp (`cur = min(cur, newMax)`) ate the
  difference; a single smallest-surplus release is clamp-free by construction,
  and the next dispatch re-judges against the post-release max, so shedding
  each further piece takes spending ITS surplus too (cumulative). Equips pick
  the BIGGEST gain first ("find the piece with the highest MP"); the
  full-pool gate then paces the ladder — the next battery waits until
  recovery refills the headroom the last one opened. One known leak, doc'd
  not fixed: a single recovery tick larger than the just-equipped battery's
  headroom caps the difference once per rung (stage 2's headroom leeway is
  the fix if it matters in the field). Pure choosers
  `dispatch.mpStageRelease`/`mpStageEquip` (tests MS1–MS8); the staged pick
  runs in the `mp-stage` post-pass (renamed from `mp-equip-uncovered`, PL2),
  which owns both the single release and the single equip across covered and
  uncovered slots.
- Weapons exempt (`MP_HOLD_EXEMPT`), `dlac:` virtual markers exempt (staff/obi
  automation keeps its two slots). Decisions annotate `/dl why`:
  `body=MP-EQUIP Bunzi's Robe (+21 MP)` / `body=MP-HOLD Bunzi's Robe (+21 MP unspent)` /
  `Hands=MP-RELEASE Oracle's Gloves -> Zealot's Mitts (+7 MP surplus spent)` /
  `ring1=MP-STAGE Astral Ring (+25 MP; neck releases first)`. The release note
  names the INCOMING piece (v77) because of field round 1's stall: a release
  re-decided identically for 8+ seconds with the worn piece unmoved — the
  swap-back never landed, and because the stalled slot keeps the smallest
  surplus it stays the winner and BLOCKS every other release behind it. Root
  cause still OPEN. Ruled out in the field: server-side gear locks (none on
  this server) and wardrobe availability (the server hardcodes all wardrobe
  bits on — char_status.cpp writes 0x7B — and Henrik confirms no unavailable
  gear; a `ForceEnableBags` detour was reverted). Known silent-drop paths in
  LAC for reference: `LocateItems` only finds pieces in `EquipBags`,
  bazaared items are skipped (Flags 19), and `PrepareEquip` drops what it
  cannot find without a message. Separately, `BuildDynamicSets` checks level
  only, so a flattened plan can name gear that is stored, unowned, or
  bazaared.
- Data: the autogear manifest's `mp` (lower(name) → flat MP, every owned piece)
  and `mpBest` (slot → best battery, filtered by the central `canWear` +
  `haveInBags`) maps. The manifest is fully self-maintaining: it regenerates on
  login, job change and any inventory change, and an outdated schema (`fmtver`)
  self-heals when the Automations section renders — no manual rescan, ever.
  The engine never loads the catalog (ADR 0004). Pure rule:
  `dispatch.mpHoldNeeded` (tests I1–I7).
- The GUI derives the manifest in the ADDON state, where LAC's `gData` does
  not exist — the job for eligibility comes from Ashita memory
  (`deps.playerJob`). A nil job would silently keep only `Jobs={'All'}` gear
  (the field symptom: a grid of nothing but Star/Chaplain's/Astral rings).

### Optional extras

- Sublimation top-off as plain trigger data:
  `Ability: name = Sublimation, mode = maxmp -> <any MP-ish set>` — HandleAbility
  fires before the JA lands, so the grant arrives into the enlarged pool. With
  MP-EQUIP this is usually unnecessary (a full pool already wears batteries),
  but it forces the swap when the pool is NOT full at pop time.

## Stage 2 — resting escalation (NOT BUILT; partly obsoleted by v76)

The v76 staged equip already climbs one battery per refill in ANY recovery
situation (resting, refresh, sublimation) — what remains of this stage is the
headroom LEEWAY: equipping the next piece *before* the pool is strictly full,
so a big rest tick never caps against a small battery's headroom:

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
- Percent MP gear (`MPP`) in the manifest values (flat `ConvertHPtoMP` is
  already counted as of fmtver 2).
- Waist: `dlac:AutoObi` vs an MP belt — today the obi automation wins its slot;
  revisit if a real conflict shows up in play.

## Open questions

- **Un-landable release targets** (field round 1, 2026-07-20): the flatten can
  plan a piece LAC cannot equip (stored/unowned/bazaared — no ownership check
  in `BuildDynamicSets`; normally invisible because the previous piece just
  stays worn). Under maxmp the stalled slot blocks the whole release queue.
  Candidate fixes, undecided: (a) flatten skips rungs failing
  `ownedcache.haveInBags`/`isStored` — but "sets are plans" and the flatten
  runs profile-side; (b) engine-side staleness heuristic — a winner whose worn
  piece hasn't moved after N identical decisions yields to the next candidate;
  (c) leave it to the player, now that the v77 note names the piece.
- ~~**Stored batteries**~~ FIXED after field round 3 confirmed it live
  (Radiant Lantern, owned but stored, planned as the neck battery — LAC
  dropped the equip silently and, as the biggest gain, it froze the other 7
  staged batteries behind it). The gearui deps wiring now passes
  `haveInBags(rec) and not isStored(rec)`, so every automation ladder (mp,
  staff/obi, craft/HELM/fish) only plans pieces equippable RIGHT NOW; the
  manifest's inventory-change rebuild keeps it current as gear moves bags.
  NOTE the release direction can still stall the same way — the SET side
  (`BuildDynamicSets`) has no availability check (first open question above).

- Does unequipping +MP gear on CatsEyeXI clamp current MP exactly as retail
  (cur = min(cur, newMax))? The hold rule assumes yes — field-verify with
  `/dl why` + the MP-HOLD notes.
- Rest tick cadence/size on CatsEyeXI (stage 2 measurement makes this moot,
  but knowing it helps pick the margin).
