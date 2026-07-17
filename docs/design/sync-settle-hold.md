# Level-sync settle hold — design (engine v56/v57)

Henrik's field report, 2026-07-17: *"I noticed when I receive level sync, sometimes I
lose TP … In Incursion you are already level synced, then you pop a boss, a new level
sync is in place. That's when I lose TP."* His follow-up framing, confirmed correct by
the diagnosis: *"it's more of a LAC issue where it's too fast, and you're here to give
it leeway basically."*

**Status: field-confirmed.** Tested in Incursion same day — TP survived the boss pop
(previously it sometimes zeroed). Henrik keeps testing; this doc exists so the issue can
be reopened with full context if it ever recurs.

Commits: `dda6943` (v56, the hold) · `7ea8050` (v57, window 3s → 1s).

## Root cause

Every gear consumer trusts the level reading **the same frame it changes**:

- `gData.GetPlayer().MainJobSync` is Ashita's `GetMainJobLevel()` — the *effective*
  (synced) level. It jumps the moment a sync (re)applies.
- `utils.checkRebuildNeeded` / `utils.rebuildSets` (called at the top of every template
  profile's `HandleDefault`) re-flattens all dynamic sets at the new level immediately.
- The engine's `playerLevel(ctx)` feeds virtuals (`dlac:AutoStaff`, ladders, AutoAcc)
  per dispatch; a different level → possibly a different pick.
- Legacy hand-written LAC profiles `gFunc.EquipSet` directly from `HandleDefault` with
  their own level logic.

During a sync transition the reading is briefly unstable (staged server re-application,
mid-flight gear re-staging). A dispatch landing inside that window can resolve a
**different Main weapon** at the transient level; one equip later the main hand swaps
and **saved TP zeroes**. "Sometimes" = whether a gear pass (they run per frame) lands
inside the window. This is a LAC-layer behavior, not dlac-specific — it started for
Henrik exactly when LAC began managing weapon swaps. Any swap addon with
level-dependent weapon rules is exposed; dlac's fix protects only sessions with dlac
loaded.

## The rule (pure, headless-tested)

> A level reading that JUST changed is not trusted yet. A `MainJobSync` change on the
> SAME job arms a hold for `M.SYNC_SETTLE_S` (1.0s); while it holds, weapon slots stay
> as worn and Default gear passes wait.

- **Stability-since-last-change**, not time-since-first: every flip inside the window
  re-arms it, so a staged transition (75→60→50) stays covered however long it drags.
  The window only has to outlast the quiet gap AFTER the final flip — where resolution
  is already correct. That is why 1s suffices (v57; v56 shipped 3s, Henrik: "3 sounds
  like a long time").
- **Job changes and first reads adopt instantly** — re-gearing a new job must not wait,
  and a job change also *drops* a live hold.
- **Not-ready readings never touch the tracker**: level 0, job `nil`/`''`/`'?'`/`'NON'`
  (the v49 login shapes) can neither arm nor drop a hold.
- Pure rule: `dispatch.M.syncSettleStep(st, job, lv, now)` — tests LS1–LS8d. Live
  consult (reads `gData`, stamps `os.clock()`): `M.syncSettleHold()` — tests LS22–LS25.

## Enforcement points (dispatch.lua)

Three, all engine-native (the ratified stateless-hold pattern — no `/lac disable`, no
lock-state commands, per the engine-native ruling):

1. **`ctx.syncHold`** — computed ONCE per dispatch in `M.dispatch` (the `pinReserved`
   precedent) and ridden by every `equipResolved` call (rule hits, craft overlay, pin
   overlay). In `equipResolved`'s slot loop a branch nulls `WEAPON_SLOTS`
   (main/sub/range) in the copy-on-write plan — kept as worn, traced as
   `Main=SYNC-HOLD (level just changed; kept as worn)` in `/dl why`. **The branch MUST
   sit above the AutoAcc and `dlac:` virtual branches**: a virtual in a weapon slot has
   to be held *unresolved* — resolving it at the transient level IS the bug (order
   pinned by LS17; a post-pass refactor on final names would silently regress this).
   Action events (Precast/WS/…) keep dispatching during the window — armor swaps, only
   the TP-bearing slots hold. Ammo is deliberately NOT in `WEAPON_SLOTS` (no TP cost;
   rangers feed arrows constantly) — **except** the companion rule below.

2. **The trinket companion rule** — with Range held out of the plan, a stat-stick Ammo
   (RSlot reserves Range, ADR 0010) must hold too: `trinketRangeDrop` judges only the
   plan, so the trinket would sail through, land, and the SERVER would strip the worn
   ranged weapon — a Range unequip during the very window the hold protects, and the
   post-release stable state would be trinket-worn/Range-empty. Implemented as a
   post-step just before the `trinketRangeDrop` call: while `ctx.syncHold`, an Ammo
   whose `rslotOf` mask has the Range bit (0x0004) is nulled with its own SYNC-HOLD
   note. Fired ammo (no Range bit) keeps dispatching. Tests LS20–LS21b.

3. **`M.defaultGateHold()`** — the whole HandleDefault gate (pet hold first, then the
   sync hold), covering legacy profiles' direct `gFunc.EquipSet` and stopping
   transient-level `rebuildSets` from being consumed. Consulted **at call time** by a
   thin shell wrapped over `gState.HandleEquipEvent`, so gate logic changes deploy via
   the normal engine self-swap with no reinstall. Tests LS26–LS29.

## The WRAP_GEN lesson (hot-swap delivery trap)

The v56 first draft put the sync check *inside* the wrap closure, guarded by the old
`st._dlacPetHold` boolean — which the running v55 wrap had already set. An engine
self-swap (the NORMAL upgrade path) re-executes the file but deliberately skips the
install block, so a v55→v56 hot-swap would have printed "no Reload LAC needed" while
the gate stayed dead until a full Reload LAC. The shipped design:

- The shell's install is guarded by `st._dlacWrapGen ~= WRAP_GEN` (a shape-generation
  constant, **bumped only when the shell's own body changes** — not `M.VERSION`).
- The true original is preserved in `st._dlacOrigHEE` and reused by every later
  generation, so re-installs never stack. The one v55-shaped pre-wrap (boolean set, its
  original unrecoverable) is wrapped OVER once — its inner pet check running under the
  gate's is idempotent, and depth stops at 2 forever.
- `st._dlacPetHold = true` is still stamped so a pre-gen engine run can't wrap over us.
- The tracker is parked on the module table (`M._syncSt`, the `M._loadStamp`
  swap-survival pattern) — a module-local would reset on self-swap mid-hold and adopt
  the transient level as a fresh first read.

**Rule of thumb this leaves behind:** logic that must update on hot-swap goes in a
function ON `M`, looked up at call time; anything install-once (wraps, event handlers
guarded by flags on foreign state) will run STALE code after a self-swap.

Tests LS30–LS34 drive the shell for real: fresh `dofile` of the engine with `gFunc` + a
stub `gState` carrying the v55-shaped boolean, asserting the generational re-install
happens, Default gates while settling, Precast flows, and the gate releases.

## Deliberately out of scope

- `utils.checkRebuildNeeded` untouched: plans rebuild freely at the transient level; the
  ENGINE decides what equips (ADR 0006). The wrap gate makes this moot for template
  profiles anyway (rebuildSets runs inside HandleDefault, which is gated).
- No TP-threshold weapon guard ("never swap Main while TP > X") — bigger behavioral
  change, not needed by the evidence; revisit only if a *stable-level* weapon swap ever
  eats TP.
- Manual equips during the window bypass nothing dlac controls (they don't flow through
  `equipResolved`) — explicit user intent wins.

## Reopening this issue

- **TP loss recurs for a dlac user on v57+**: raise `M.SYNC_SETTLE_S` first (one
  constant, top of the settle-hold section in dispatch.lua). Check `/dl why` for
  `SYNC-HOLD` traces around the incident.
- **TP loss for a plain-LAC user (no dlac)**: expected — this fix only ships with dlac.
  Not a server issue either.
- **TP loss for a player with NO swap addon at all**: points at server-side sync
  re-application (unequip/re-equip) — that goes to [../server-questions.md](../server-questions.md)
  as a new entry.
- Provenance: the v56 draft was hardened by a 4-lens adversarial review (findings: the
  trinket inversion, the hot-swap gap, the tracker reset, mutation-tested coverage
  holes) — see history.md "level-sync settle hold" session for the narrative.
