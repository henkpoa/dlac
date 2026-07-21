# Max-MP mode — the banded ladder

**Status: BUILT and field-settled** (engine v95, addon 2026.07.21; confirmed
live on WHM). One marathon arc — 2026-07-20 evening through 07-21 morning,
~20 engine versions, thirteen field rounds — took this from a per-dispatch
heuristic to a precomputed plan. This document is the definitive reference:
the final architecture, the rulings that shaped it, and the failure museum
(kept deliberately — the dead ends teach more than the survivor).

Henrik's original spec (2026-07-11): *"Find the piece with the highest MP,
keep that piece active until you have spent enough MP for any potential
pieces that would be equipped."* Weapons (Main/Sub/Range) always exempt —
TP preservation.

---

## The final architecture

**One idea:** stop making marginal per-dispatch decisions against live
max-MP readings (this client cannot provide an accurate max during gear
churn — see the failure museum), and instead **precompute the whole plan as
absolute current-MP thresholds**. Current MP is the only live input; it is
the one number that never lies.

### The band ladder (`feature/mpbands.lua` — pure, tests MB*)

ONE band per non-weapon slot: the slot's **top battery** versus its
**potency point**:

- `HIGH` = the best owned battery for the slot — augments ALWAYS included
  (manifest fmt 12+); at equal MP the higher-Refresh copy wins the pick.
- `LOW` = the LEAST MP any trigger-reachable set puts in the slot (the true
  potency point — combat sets full of 0-MP gear legitimately make this 0).
- `lowRf` = the **POTENTIAL refresh**: the MOST Refresh any trigger-reachable
  set puts there (NOT the min-MP piece's refresh — that reads 0 the moment a
  combat set exists; v95's field lesson).
- `diff = HIGH − LOW`, `rfDelta = HIGH's refresh − lowRf`.

**Order** (release order, top-down as MP is spent): `rfDelta` ascending,
then `diff` ascending. One rule expresses everything:

- refresh-COST bands (a flat battery displacing a set's refresh piece,
  e.g. Hlr. Bliaut +1 over Clr. Bliaut +1) float **shallowest** — first
  off as spending starts, back on only at the true peak, so the refresh
  piece is worn through the whole spend-and-recover cycle;
- plain bands run by smallest difference (lowest-hanging fruit first out);
- refresh-GAIN bands sink by magnitude — the strongest refresh battery
  releases last and returns first. *"Refresh > least mp diff; mp recovery
  is key."*

**Thresholds** (Henrik's data points, chained from `TOTAL` = max with every
battery worn):

```
lastMax_i = TOTAL − Σ diffs of shallower bands
endMax_i  = lastMax_i − diff_i
offAt_i   = endMax_i − tick              (unequip: an incoming tick can
                                          never be capped by the swap)
onAt_i    = min(lastMax_i − tick,        (re-equip EARLY so the next tick
             endMax_i)                    lands in the headroom — clamped
                                          to the reachable pool: the raw
                                          formula is unreachable whenever
                                          diff > tick)
```

The `offAt..onAt` gap is `min(diff, tick)` wide — **hysteresis is
structural**; churn is impossible by construction, no cooldowns needed.
Worked example (the spec's, pinned as tests MB1/MB13d): TOTAL 1100, feet
5→15 (diff 10), tick 15 → unequip at 1075, re-equip at 1085.

**Per dispatch** the engine reads current MP, walks the ladder to a target
loadout (`target()` answers a piece NAME per slot, or false = the set's
piece), diffs against worn, and issues **all** needed swaps at once — batch
moves are safe because the margins are in the thresholds. Big drops
(spell dumps) batch-release; big rises (Sublimation pops) batch-equip.

### The recovery tick — measured, never modeled

`mpbands.observe()` (fed by the engine's 0.4s tick) records upward MP jumps
into standing/resting buckets; `tick()` answers the median. CatsEyeXI's
refresh/hMP numbers are custom — live memory beats every table. The
measurement is honest (unbuffed gear refresh really ticks +1..3), so the
MARGIN floors at `MIN_TICK = 5` to keep hysteresis from going hair-width;
`DEFAULT_TICK = 15` (endgame buffed refresh) until anything is measured.

### The TOTAL anchor

`TOTAL = wornMax + remaining battery headroom`, where wornMax is predicted
(nativemp base + auto-learned merits + every worn piece's manifest MP) and
corrected by ONE offset learned whenever the party MP% reads a true full —
floored MP% reads 100 *only* at cur == max, the single exact fullness
signal this client offers (maxmp≠modmp lesson: never trust computed
absolutes alone; never trust `GetMPMax` at all below full).

### Paired slots (ears/rings)

- **Pair homes** (manifest fmt 13): the ear/ring battery ladders re-home to
  the positions the player's IDLE SET declares — detected from the Default
  trigger rule matching exactly `status = Idle`; the MaxMP panel's idle-set
  picker ALWAYS overrides detection; a set literally named `Idle` is the
  convention fallback. The idle set is used for pairing positions ONLY.
- **Sticky pairs** (`M.mpStickyPairs`): at apply time, a candidate whose
  piece is claimed by the sibling slot — in THIS dispatch's resolved plan
  (which cannot lag) OR on the body — never writes. Genuine duplicates
  (2× Astral Ring) stay exempt: the manifest lists dup-owned items in both
  ladders, so a sibling claim proves a second copy. Once an MP earring or
  ring sits in a paired slot, the engine never relocates it.

### What the bands DON'T decide

Bands decide **WHEN**. The existing machinery decides **WHAT** and stands
guard underneath: `M.mpRungs`/`mpBestPick` (the one pair-veto-aware battery
resolver shared by engine, plan and builder), equippable-NOW filtering
(owned AND not stored — LAC silently drops what it can't find),
`mpStageEligible` (the v78 RSlot ruling: a battery reserving an occupied
slot never stages), explicit `remove` plans win over batteries (v91:
fishing/AutoAmmo empty-slot claims), and slot locks/pins/virtuals keep
their precedence in the per-slot chain.

### Surfaces

- `/dl mode maxmp [on|off]` — the mode; **auto-disables on job change**,
  re-enable per job.
- `/dl plan` — prints the band table: release order, thresholds,
  `[refresh]`/`[refresh-cost]` tags, live state per band. It renders the
  SAME context object the engine executes — **the plan IS the behavior**;
  they cannot disagree by construction. This one property cracked most of
  the field bugs.
- `/dl why` — per-dispatch notes (`MP-EQUIP`/`MP-HOLD`/`MP-RELEASE` with
  band thresholds, `MP-SKIP`, `MP-PAIR sticky`).
- **Automations tab → MaxMP** (graduated 2026-07-21; the hidden ruling
  rescinded): ON/OFF switch reflecting the live mode (modestate mirror,
  1s re-read; toggles via the explicit command), battery grid, idle-set
  picker. The Teleports quick menu carries the same switch.

### Data flow

```
catalog + bags + augments (augments.ownedAugStats — the player's ACTUAL copies)
        │  addon state: automationsui manifest builder (fmt 13)
        ▼
autogear.lua: mp (name→MP), rf (name→Refresh), mpBest (per-slot ladders,
              pair-homed, equippable-NOW), mpPairIdle(+Override), mpMerits
        │  LAC state: dispatch.M.mpBands (per dispatch)
        ▼
LOW/lowRf (trigger-set scan, 10s TTL) + rungs + TOTAL anchor + measured tick
        │  feature/mpbands.lua (pure)
        ▼
bands → target loadout → per-slot chain + mp-stage pass (batch, guarded)
        │
        ├── gFunc.EquipSet (LAC)
        └── /dl plan (the same context, printed)
```

---

## The rulings ledger (Henrik's design law, in his words)

1. *"Find the piece with the highest MP, keep it until you have spent
   enough for any potential pieces."* — the founding spec (07-11).
2. *"Stop with dynamic equipping — make it orderly and calculated /
   planned."* — the banded-ladder redesign (07-21 night).
3. *"Refresh > least mp diff. Refresh pieces should release last and be
   returned first — mp recovery is key."*
4. *"To get refresh in is NOT YOUR JOB — that is the idle set's job...
   but you should be aware that there is a POTENTIAL refresh piece there
   and adapt accordingly."* — refresh lives in the ORDERING only; the
   engine never wears refresh gear itself (v92), and the baseline is the
   potential (max) refresh, not the minimum (v95).
5. *"Augs must always be calculated into the total."* — every MP/Refresh
   number folds the player's actual augments (fmt 12; S169b-e).
6. *"Have MP earrings and rings sticky — don't move positions once set."*
   + *"pair positions follow the idle set; the GUI picker always
   overrides."* (v93/v94 + fmt 13).
7. Positions beat optimality: the engine accepts a few MP of theoretical
   loss to never rearrange the player's pair placement.
8. The player's sets are the authority on what a slot returns to; the
   engine works around them, never through them.

---

## The failure museum (v76–v95 — why per-dispatch heuristics died)

Kept for inspiration: each of these was a real field round with a
screenshot, and each produced a pinned test.

1. **All-at-once flip** (pre-v76): every battery on at full, every battery
   off past the surplus — and the mass release was an accounting bug: N
   per-slot holds each justify removing only THEIR piece, so simultaneous
   releases dropped max by the SUM and the server clamp ate the
   difference. *Lesson: slot-local rules break when applied in bulk.*
2. **The silent equip stall** (v77 era): a release re-decided identically
   forever because LAC drops un-locatable pieces with no message.
   *Lessons: name the target in every trace (v77) — a repeating decision
   with unmoved gear then diagnoses itself; automation must only plan
   equippable-NOW gear (the stored-battery freeze, round 3).*
3. **The held-battery deadlock** (v80): the hold branch swallowed the
   upgrade check, so a worn small battery blocked its own upgrade forever.
   *Lesson: a guard that eats a branch eats its candidates too.*
4. **The ear shuffle** (v83): disjoint alternating pair ladders + LAC's
   UnequipConflicts moved one physical earring across ears, leaving holes.
5. **Stale max-MP reads** (v86/v87): `GetMPMax` goes stale in BOTH
   directions across gear churn (engine read 975/1052 vs a 975/975 bar;
   LAC's own `.MaxMP` is the same call). False fullness over-equipped;
   ±1% window error at exact boundaries dumped fresh batteries; the whole
   ladder oscillated — climb, alternate, cascade to idle, repeat.
   *Lessons: floored party MP% == 100 is the ONLY exact fullness signal;
   below full, bias any estimate toward HOLDING; and ultimately — remove
   the live-max dependency entirely (the banded ladder).*
6. **The multi-rung overreach** (v90, retired by ruling): the engine wore
   refresh mid-rungs itself — overstepping the idle set's job AND
   deadlocking (wearing mid-rungs depressed the pool below the top bands'
   re-equip triggers: unreachable whenever diff > tick → the v92 clamp).
7. **The plan-shadowed worn claim** (v94): sticky checked `plan or worn`,
   so a sibling plan naming a different piece hid the worn claim.
   *Lesson: independent claims veto independently.*
8. **The collapsed refresh baseline** (v95): lowRf from the min-MP piece
   reads 0 once any combat set exists → every [refresh-cost] tag vanished
   → a deep plain band displaced the refresh body at MP ~800. *Lesson:
   "potential X" means MAX over the possibilities, and the /dl plan tags
   are the instant diagnostic — no tags = collapsed baseline.*
9. **Cross-cutting**: worn-state reads lag ~a dispatch behind LAC's swaps —
   the same-dispatch resolved plan is the only lag-free claim signal; and
   twice a "bug" was actually data (a set ladder resolving a different
   rung than the player assumed) — `/dl plan` + `/dl why` together settled
   every single round.

---

## Parked / open

- **Un-landable release targets**: `BuildDynamicSets` has no
  ownership/bag check, so a set plan can name gear LAC can't equip; under
  maxmp a stalled slot's release repeats (named in `/dl why` since v77).
  Options parked: flatten-side filter vs staleness-yield vs player-fixes.
- **Sets-file lint**: `gear.*` references that don't resolve vanish as nil
  silently — a text scan against the gear table would catch the class.
- Resting-tick bucket barely exercised; Sublimation-pop-as-tick question;
  the equipment-menu freeze (re-observe fresh on v2 before chasing);
  clamp-on-unequip server behavior (assumed retail-like, unfalsified).
- Multi-job sweep: architecture is job-generic (per-job manifest, per-job
  LOW scan, job-aware base); confirmed WHM + a BLU cameo.

## Test map

`MB*` band build/target/measurement (worked-example pins) · `MPS*` pair
veto + shared resolver · `MSS*` sticky pairs · `MPL*` plan formatter ·
`MR*/MF*` max reconciliation + exact fullness (legacy but live fallbacks) ·
`I*/K*/MS1-8` v1-era pure rules (exported for compat) · `S169b-e` the
augment fold end-to-end · smoke: manifest build incl. pair-homed ladders.
