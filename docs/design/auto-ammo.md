# AutoAmmo — the Ammo-slot automation

Status: **DESIGNED 2026-07-20** — implementation in progress. Sibling of the
craft/HELM/fish gear systems in mechanism (state file + dispatch overlay), but a
different animal in intent: those dress you for an activity you picked; this one
guards a consumable slot on every shot. Same law as always: don't fight the
engine, BE the engine.

**Scope guard (Henrik, verbatim intent):** the player configures, per owned
ammo: (1) OK for normal ranged attacks, (2) OK for ranged weapon skills, (3)
special behaviours / limitations — and special-case ammo is "NEVER EVER supposed
to shoot, unless the behaviours deem true. [...] If a special case bullet is
equipped, make sure that another ammo gets equipped, if not, empty the slot."
AutoAmmo decides WHAT sits in the Ammo slot; it never fires a ranged attack,
weapon skill or ability itself. It is not a hidden feature — it ships on main.

**The LuaAshitacast failure it fixes** (verified in LAC source, `equip.lua`):
LAC only acts on handler events and has NO fallback — a set naming an ammo you
no longer own makes `LocateItems` find nothing and silently equip *nothing*,
leaving whatever is worn (your one Rare/Ex super-bullet) in the slot for the
next shot to eat. `GetCurrentEquip` does read real memory (a depleted stack
reads as an empty slot), and `'remove'` is a first-class unequip
(`MakeItemTable`: `Name == 'remove'` → `Index = 0`). So the engine can do what
LAC can't: decide per event from real bag counts, fall back down an enabled
list, and end in an explicit `remove`.

## 0. Server research summary (CatsEyeXI `stable`, HEAD 9bb0ec8c67)

Trust ladder: live game memory > this section (public base code) > nothing.
The private override modules (`modules/catseyexi`, `src/map/cexi`) are not in
the local checkout; any of the below could in principle be overridden there.
Field tests (§6) are what promote these to pinned.

- **Normal ranged attack** consumes the equipped ammo per shot
  (`src/map/entities/charentity.cpp` `OnRangedAttack`, ~:2025-2053 →
  `battleutils::RemoveAmmo` :2146). Recycle / JP `AMMO_CONSUMPTION` can skip a
  given shot randomly — irrelevant to us, counts are re-read live.
- **Unlimited Shot** = ability 86 → **effect id 115**, 60 s
  (`scripts/globals/job_utils/ranger.lua:258`). While active, `recycleChance =
  100` — zero consumption; the buff is removed **on hit** for normal shots
  (charentity.cpp:2034-2043) and unconditionally inside physical ranged WS
  (`scripts/globals/combat/ranged_utilities.lua:117-134`).
- **Ranged WS consume ammo ONLY via the physical handler**
  (`doRangedWeaponskill`, weaponskills.lua:721, removeAmmo at :794-797).
  **The magical handler has no ammo code at all** — and exactly three ranged WS
  route through it: **Trueflight 217 (RNG), Leaden Salute 218 (COR),
  Wildfire 220 (COR)**. Leaden Salute consuming no bullet is CONFIRMED
  (`scripts/actions/weaponskills/leaden_salute.lua:34`). The `weapon_skills.type`
  column can NOT discriminate this (all three are type 26 Marksmanship); the
  three ids are the hardcoded no-ammo exceptions.
- **WS skill types** (`sql/weapon_skills.sql` `type` col; battleentity.h):
  Archery = 25 → ids 192,193,194,196,197,198,199,200,201,203;
  Marksmanship = 26 → ids 208,209,210,212,213,214,215,216,219,221 physical
  (consume) + 217,218,220 magical (free). No Throwing (27) WS exist in the data.
  Everything else is a melee WS: `attack.slot = MAIN`, never touches ammo.
- **Quick Draw** (the eight `*_shot.lua` abilities, recast timer 195): REQUIRES
  a Marksmanship weapon in Range AND a Marksmanship ammo equipped (hard gate,
  error 216 otherwise — fire_shot.lua:12-17), consumes an elemental card or
  Trump Card from inventory (:81), and **never decrements the equipped bullet**
  (no removeAmmo anywhere in the scripts). Equipping a bullet at the Ability
  event doesn't just add its MACC — it un-blocks QD when the slot ran empty.
- **Depletion**: consuming the last of the stack UNEQUIPS the Ammo slot
  server-side and pushes item packets (`battleutils.cpp` `RemoveAmmo`
  :6184-6208) — client memory is promptly correct.
- **Empty slot**: gun/bow ranged attack with no ammo is BLOCKED server-side
  (`range_state.cpp` `CanUseRangedAttack` :204-285, NO_RANGED_WEAPON). So
  `remove` is a genuine protection: the shot refuses instead of eating the
  bullet. Boomerang-type (throwing weapon in Range) needs and consumes nothing;
  throwing ammo in the Ammo slot is consumed like a bullet.
- **Animikii Bullet** (21334, the motivating item): Rare/Ex, **stack size 1**,
  RNG/COR, RACC+40 / MATT+30 / MACC+30, DMG 240 in base data (level custom on
  CatsEyeXI — the crawled catalog is the live truth). The MATT/MACC is exactly
  why it wants to be worn for the three free WS and Quick Draw — the contexts
  that don't consume it.

## 1. The model

One per-character config, one priority-ordered list. Every entry is an owned
shooting ammo (catalog `AmmoType` ∈ Marksmanship / Archery / Throwing —
trinkets are set-managed and never AutoAmmo's business) with three flags:

- **Ranged** — may be loaded for normal ranged attacks.
- **WS** — may be loaded for ammo-consuming ranged weapon skills.
- **Special** — never loaded where it could be consumed. Sub-behaviours (all
  default off): **Unlimited Shot** (wear it while effect 115 is up),
  **Quick Draw** (wear it for the shot abilities), **Free weapon skills**
  (wear it for Trueflight / Leaden Salute / Wildfire). Special is exclusive —
  it forces Ranged/WS off.

List order IS the fallback order: the engine picks the FIRST entry whose flag
matches the context and whose live bag count (equippable bags: inventory +
wardrobes) is ≥ 1. Count-verification is the whole point — the engine never
plans a name it hasn't just counted.

The strict invariant (the friend's `HandlePreshot` workaround, made total): on
any event where consumption can happen, if the worn ammo is special-flagged and
no behaviour window is open, the engine plans a replacement — first
ranged-enabled with stock, else **`remove`** (empty slot = shot blocked
server-side = bullet saved).

`enabled` PERSISTS across sessions — a deliberate deviation from the
craftstate/fishstate session-only rule. Those are activity pills (a gathering
overlay must not glue itself on at login); this is a protection system, and a
protection that silently disarms at login is how the bullet dies. The `jobs`
map (below) is what keeps it from acting on jobs it wasn't meant for.

## 2. UI — Automations → "AutoAmmo" (slot automation (Ammo))

New row in ui/automationsui.lua's rows table (key `ammo`, appended per the
branch's row-index rules), detail view delegated to a new `ui/ammoui.lua`
(helmui contract: `render(deps, availW)` / `status(deps)` / `maxLevel`).

Layout, top to bottom:
- Master ON/OFF + "Active on: <job chips>" — the jobs map. Enabling adds the
  current main job; chips toggle. The engine ignores every event when the
  current job isn't ticked.
- **Priority list** (configured ammo, order = fallback order): per row —
  icon + name (shared renderIcon/itemTooltip), live count (red at 0),
  `Ranged` / `WS` / `Special` checkboxes, ▲▼ reorder, ✕ remove-from-config.
  Ticking Special disables/clears Ranged+WS and reveals the three behaviour
  ticks inline: `Unlimited Shot`, `Quick Draw`,
  `Free WSs (Leaden/Wildfire/Trueflight)`. A `Sort by level` button reorders
  the whole list best-first (level DESC, stable ties; entries persist `level`,
  the sorter backfills pre-level entries from the catalog) — field round 1
  (Henrik): "that's usually how you want it either way."
- **Owned, not configured** below: every owned AmmoType item not yet in the
  list, one `+ Add` per row (adds with all flags off).
- **Columns are fixed-offset and SHARED between the two lists** (field round 1:
  "make the table look nice") — name/qty in both; the priority row continues
  with the flag ticks, the owned row with skill / Lv / `+ Add`, and the space
  right of `+ Add` is deliberately reserved for future per-row controls.

### 2b. E-Box counts + fetch — CRYSTAL WARRIORS ONLY (field round 1)

Henrik: "This should not be seen at all if you are not Crystal Warrior mode,
only crystal warriors may view this." The gate is `gamemode.get() == 'CW'`
**affirmative only** (Wings/ACE/nil-unknown all see nothing — the
never-gate-on-nil rule points the safe way: unknown = hidden). This is the
FIRST consumer of the gamemode foundation. The server's `LOCKED` reply is the
belt-and-braces second gate (reason 1 = not CW shuts the section again; reason
2 = E-Box not unlocked shows the server's own message).

`feature/eboxammo.lua` speaks CatsEyeXI's custom **0x1A4** protocol — the
trove addon's wire format (`trove/utils/packet.lua` + `plugins/ebox.lua`),
reimplemented exactly like helmwatch reimplemented GET_POINTS so dlac never
depends on trove being installed:

- counts: `GET_CATEGORY(5)` with ahCat **15 = Ammunition** at 0x0A — ONE
  request streams every ammo in the box (`ITEM(1)`: u16 id @0x08, u32 qty
  @0x0C; `CLEAR(0)` resets, `END_LIST(2)` with source byte @0x05 == 0
  commits). Refreshed while the panel is open (15 s stale window) and after
  every fetch.
- fetch: `WITHDRAW(2)` — u16 itemId @0x08, u32 qty @0x0C; the `ACK(3)`
  carries success @0x06 + the server's message @0x10 (shown verbatim on
  refusal). One in flight at a time, 3 s lost-ACK timeout (trove's rule).
- pending discipline: 0x1A4 is a party line (helmwatch's points, trove's own
  panels) — ITEM rows are staged only while OUR request is in flight, and only
  what we asked for is consumed/blocked (Ashita still hands blocked events to
  every addon; blocking matters because the retail client has no idea what
  opcode 0x1A4 is).
- Parsing is plain `string.byte` (no struct) so the whole wire path is
  headless-tested (EB*).

Per configured row (CW only): an `E-Box: xN` line + a qty input (clamped to
what the box holds) + `Fetch`. Above the list, the **proximity warning**
(field round 1 addition): E-Boxes are ordinary zone NPCs named **"Ephemeral
Box"** (Henrik's Bastok Mines sample, server id 17737730, decodes to a plain
zone-NPC slot), so the panel scans the entity array by NAME — no targeting
needed, the helmwatch proximity conventions (GetDistance is SQUARED; reads
memory-only, ~2 s throttle) — and warns when the nearest box is beyond
`BOX_RANGE = 6` yalms or none is rendered in the zone. Warn only; the fetch
stays clickable and the server's ACK has the final word.
- Footer: the strictness one-liner ("Special ammo is never left equipped where
  a shot could consume it; with nothing else to load, the slot is emptied.").

## 3. Engine — the ammo overlay (dispatch v73)

New state-file reader `ensureAmmoState()` (`ensureStateFile` one-liner, same as
fish). New overlay `ammoOverlayFor(event, ctx, plannedAmmo)` applied in
`M.dispatch` **after the fish overlay, before pins** (pins stay the last word),
on EVERY event — the craft/helm/fish Default-only gate does not apply; the
whole point is owning Preshot/Midshot/Weaponskill/Ability.

The decision core is a PURE function (the resolveOneiros shape, headless-tested):

```
resolveAmmoPlan(cfg, f) -> name | 'remove' | nil (hold), why
-- f: { event, wsId, wsName, abilityType, abilityName, unlimited (buff 115),
--      worn (name|nil), count(nameOrId) -> n, plannedAmmo (name|nil),
--      plannedOwned (bool|nil), fishing (bool) }
```

Rules (first match wins inside each event):

| Event | Plan |
|---|---|
| gate | not enabled / job not in `jobs` / no config → nil everywhere |
| Preshot, Midshot | buff 115 up AND a special has `unlimited` AND count≥1 → that special · else first `ranged` count≥1 · else worn is special → `remove` · else nil |
| Weaponskill, id ∈ {217,218,220} | first special with `freews` count≥1 → it · else first `ws` count≥1 · else first `ranged` count≥1 · else nil (free WS — worn ammo is safe regardless) |
| Weaponskill, id ∈ consuming ranged set | first `ws` count≥1 · else worn is special → (first `ranged` count≥1 or `remove`) · else nil |
| Weaponskill, any other id (melee/unknown) | nil — melee WS never touch ammo |
| Ability, Quick Draw (Type 'Quick Draw' or the 8 shot names) | first special with `quickdraw`, Marksmanship type, count≥1 → it · else nil |
| Default | fishing overlay live → nil · sets planned an Ammo they actually own → nil (their equip replaces any special) · worn special: buff-115 window open → nil, else first `ranged` count≥1, else `remove` · worn empty → first `ranged` count≥1 (reload) · else nil |
| everything else | nil |

Supporting machinery, all new in dispatch.lua:
- Per-dispatch lazy bag counter over the equippable containers
  {0, 8, 10, 11, 12, 13, 14, 15, 16}: id → summed Count, plus memoized
  id → resource-name for by-name lookups (the LAC state's first bag scanner —
  the LocateItems pattern, once per dispatch at most).
- The two WS id sets (RANGED_CONSUMING, RANGED_FREE) baked as data — server
  SQL is the source, §0 the provenance.
- `'remove'` flows through equipResolved untouched (it's not `dlac:`-prefixed,
  has no RSlot, reserves nothing) into `gFunc.EquipSet` → LAC unequips.
- Loudness (hard rule 12): a protection `remove` and an exhausted fallback each
  print one throttled chat line with the cause; routine picks stay quiet in
  chat and visible in `/dl why` via equipResolved's note channel.

What it deliberately does NOT do: no `dlac:AutoAmmo` set marker in v1 (the
overlay owns the slot; sets keep owning trinkets/idle ammo via the
planned-and-owned stand-down), no flatten/virtualMinLevel work, no bar.

## 4. Data — `<char>\dlac\ammostate.lua`

Written by `feature/ammowatch.lua` (safety: pcall'd whole-file write, same as
fishwatch's saveState; loadState restores EVERYTHING including `enabled`):

```lua
return {
  enabled = true,
  at = 1753000000,            -- arbitration stamp (set on enable)
  jobs = { COR = true, RNG = true },
  ammo = {                    -- array order = priority order
    { name = "Bronze Bullet",   id = 21306, type = "Marksmanship",
      ranged = true,  ws = false, special = false },
    { name = "Animikii Bullet", id = 21334, type = "Marksmanship",
      ranged = false, ws = false,
      special = { unlimited = true, quickdraw = true, freews = true } },
  },
}
```

No autogear-manifest block: nothing here is derived from bags, so there is
nothing for a rescan to regenerate (the mpMerits carry-forward dance buys
nothing). The fish split precedent — manifest for derived armor, state file for
the live Range/Ammo picks — lands AutoAmmo entirely on the state-file side.

## 5. Modules

| File | Role |
|---|---|
| `feature/ammowatch.lua` | config state + load/save (persisted enabled), pure list helpers; test seams `_saveState`, `_setDeps` |
| `feature/eboxammo.lua` | E-Box 0x1A4 client (CW-only): GET_CATEGORY(15) counts, WITHDRAW + ACK, LOCKED gates, Ephemeral-Box proximity scan; seams `_onPacket`/`_beginStream`/`_scanBox`/`_clampQty` |
| `ui/ammoui.lua` | Automations detail view (helmui contract); owned-ammo enumeration via catalogindex.flat() ∩ ownedcache.counts(); CW-gated E-Box rows |
| `ui/automationsui.lua` | +1 row (`ammo`) + detail-view dispatch arm (pcall-require pattern) |
| `dispatch.lua` | ensureAmmoState, bag counter, WS id sets, resolveAmmoPlan (pure), ammoOverlayFor, M.dispatch wiring; **M.VERSION 73** |
| `tests/run_tests.lua` | new AM section, `(function() ... end)()` wrapped |
| `docs/design/auto-ammo.md` | this file |

## 6. Field tests (cheap stack standing in as the "special" bullet)

1. Ranged attacks consume the ranged-enabled stack; when it dies mid-volley the
   next enabled ammo loads without a manual touch (the marquee fix).
2. Special bullet worn manually, `/ra` with other enabled ammo in bags → it
   swaps off before the shot.
3. Special bullet worn, NO other enabled ammo → slot empties, shot is blocked
   by the server, bullet intact, one loud chat line.
4. Quick Draw with special.quickdraw ticked → bullet equips for the shot, swaps
   back after; QD works even when the slot was empty beforehand.
5. Leaden Salute with special.freews ticked → bullet equips for the WS, is NOT
   consumed (server §0 claim promoted to pinned), swaps back after.
6. Unlimited Shot (RNG) → special loads while the buff is up, shot consumes
   nothing, sweep swaps it back off after the buff drops.
7. Last Stand / Slug Shot (consuming WS) with a ws-enabled stack → that stack
   is used, the special never appears.
8. Fishing pill ON + AutoAmmo ON → bait keeps the Ammo slot at Default
   (stand-down verified).
9. Job not in the jobs map → AutoAmmo does nothing at all on that job.
10. E-Box section (CW char): counts appear and match the box; fetch lands the
    qty in the bags; refusal shows the server's message; the proximity warning
    reads sane yalms near a real Ephemeral Box and clears within 6.
11. E-Box section (non-CW char / Wings / ACE): completely invisible.

## 7. Open questions

- Private-module overrides of §0 (Leaden/QD/Unlimited/Animikii) — resolved only
  by the field tests above; log any divergence in docs/server-questions.md.
- Barrage (multi-hit consumption) — counts re-read live so logic holds, but
  worth one observation pass with a small stack.
- Whether ranged ammo ↔ ranged weapon skill-type mismatch (arrows in a gun)
  needs a UI hint; the server gate only checks "a weapon-type ammo exists".
  Deferred — users enable sensible ammo.
- Does the server enforce Ephemeral-Box PROXIMITY on GET_CATEGORY/WITHDRAW,
  or is the box remote-usable (trove carries no distance check)? The warning
  threshold (6 yalms) is the trade-range convention, unverified — field test
  10 calibrates or deletes it.
