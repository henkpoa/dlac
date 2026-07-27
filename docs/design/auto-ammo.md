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

One config **per job** (fmt 2, field round 2 — Henrik: "all jobs can't use all
ammos, I want this list to be seperate for all jobs seperately, where it
remembers if you have activated it or not"): every job carries its OWN
priority-ordered list and its OWN persisted on/off. Every entry is an owned
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

`enabled` (per job) PERSISTS across sessions — a deliberate deviation from the
craftstate/fishstate session-only rule. Those are activity pills (a gathering
overlay must not glue itself on at login); this is a protection system, and a
protection that silently disarms at login is how the bullet dies. The per-job
split IS the blast-radius limiter (it replaced fmt 1's jobs boolean map; the
GUI migrates old files — every ticked job gets its own copy of the list, and
a list no job owned is adopted by the first job that opens the panel).

## 2. UI — Automations → "AutoAmmo" (slot automation (Ammo))

New row in ui/automationsui.lua's rows table (key `ammo`, appended per the
branch's row-index rules), detail view delegated to a new `ui/ammoui.lua`
(helmui contract: `render(deps, availW)` / `status(deps)` / `maxLevel`).

Layout, top to bottom:
- "AutoAmmo on <JOB>:" ON/OFF — the CURRENT job's own switch (fmt 2); the
  whole panel edits that job's section, and a dim "also configured:" line
  summarizes the other jobs' sections. The engine resolves against the main
  job's section only — no section, or its switch off, means do nothing.
- **Ammo type selector** (field round 5: "list is gonna become super
  bloated") — **SUPERSEDED by the green type TABS in §9.6 (v128); the combo and
  its "Ammo type:" label are gone, and the split is now driven by the exact
  subskill rather than the item name.** As built it was a combo
  (Bullets / Bolts / Arrows / Throwing, + Other only when
  it exists) filtering BOTH lists below; each entry shows "(n set up, m more
  owned)". Category is a VIEW, derived per item (`ammowatch.categoryOf`:
  Archery→Arrows, Throwing→Throwing, Marksmanship split by NAME into
  Bullets/Bolts — the catalog doesn't crawl item_weapon.subskill); the job's
  priority order still spans all types underneath, and the filtered view's
  ▲▼ swap VISIBLE neighbours (`swapAmmo` — not necessarily adjacent in the
  full list).
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

> **REMOVED 2026-07-27 — see §10.8.** The whole section below is history: the
> panel's E-Box surface and `feature/eboxammo.lua` are gone, superseded by
> **E-Box Restock**, and the panel no longer consults `gamemode` at all. Kept
> because the wire facts and the entity-scan lessons outlived the feature (they
> live on in `feature/eboxclient.lua` and `/dl debug ebox scan`).

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

Per configured row (CW only): an `E-Box: xN` line + a qty input (120 px —
triple digits fit; both buttons work from it, always clamped to what the box
holds) + two buttons:
- **Fetch** — withdraw exactly the typed qty (box-clamped).
- **Fetch up to** (field round 2) — top-up: reads how many you carry in the
  equippable bags and fetches the DIFFERENCE so you end at the typed number
  (box-clamped; refuses when you already carry that many).

Above the list, the **proximity check**: E-Boxes are ordinary zone NPCs named
**"Ephemeral Box"** (Henrik's Bastok Mines sample, server id 17737730, decodes
to a plain zone-NPC slot), so the panel scans the entity array by NAME — no
targeting needed, the helmwatch proximity conventions (GetDistance is SQUARED;
reads memory-only, ~2 s throttle). The scan idiom is gearmove's field-verified
mhBootstrap one — GetRawEntity for existence, RenderFlags0 bit 0x200 =
rendered (signed-u32 fix) before trusting distance, **names TRIMMED + ci**
(GetName returns trailing whitespace) — over the **WHOLE entity array
0x000-0x8FF**: E-Boxes are DYNAMIC entities (the Bastok Mines sample 17737730
= zone 234, index **0x802**). Two field rounds of always-red buttons paid for
those rules: round 2's exact-name compare could never match, round 3's
0-1023 static sweep could never reach the box (tests EB8-EB8e pin both).
The status line is always-on when CW (in range / too far / none in sight) with
a `rescan` button (cache-bust + count re-request), and the HIDDEN `/dl ebox`
diagnostic dumps gamemode, every 'ephemeral' entity hit (idx, exact name,
server id, render flags, distance) and the nearest named entities — the
data-not-theories probe for any future round. `BOX_RANGE = 5` yalms is
**FIELD-PINNED**
(Henrik, field round 2; the round-1 trade-range guess was 6). Out of range (or
no box rendered): the warning line shows AND both fetch buttons go dead —
dim RED for out-of-range, GREY for nothing-to-fetch/busy — with the reason in
the tooltip. The server's ACK still has the final word.
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
  fmt = 2,                      -- per-job sections (v74); fmt 1 = one shared
                                -- list + jobs boolean map, engine-supported
                                -- until the GUI migrates the file
  jobs = {
    ["RNG"] = {
      enabled = true,           -- THIS job's own persisted switch
      at = 1753000000,          -- stamp (set on enable)
      ammo = {                  -- array order = priority order
        { name = "Bronze Bullet",   id = 21306, type = "Marksmanship",
          level = 5,  ranged = true,  ws = false, special = false },
        { name = "Animikii Bullet", id = 21334, type = "Marksmanship",
          level = 75, ranged = false, ws = false,
          special = { unlimited = true, quickdraw = true, freews = true } },
      },
    },
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
| ~~`feature/eboxammo.lua`~~ | **DELETED 2026-07-27 (§10.8).** Was the E-Box 0x1A4 client (CW-only), a thin adapter over `feature/eboxclient.lua` from ADR 0016 onward. Its `/dl ebox` entity probe moved to `feature/eboxtrace.lua` as `/dl debug ebox scan` |
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
- ~~Whether ranged ammo ↔ ranged weapon skill-type mismatch (arrows in a gun)
  needs a UI hint; the server gate only checks "a weapon-type ammo exists".
  Deferred — users enable sensible ammo.~~ **ANSWERED THE HARD WAY — see §9.**
  It was never a hint question, and "the server gate only checks a weapon-type
  ammo exists" was true of the wrong gate. `CanUseRangedAttack` is lax;
  `charutils.cpp EquipItem` is not, and it does not refuse the equip — it
  **strips the other slot**. "Users enable sensible ammo" was the assumption
  that made the bug: a sensible ammo for your gun is nonsense for your bow, and
  the engine picked from one flat list without ever looking at either.
- ~~Does the server enforce Ephemeral-Box PROXIMITY, and at what range?~~
  **ANSWERED (field round 2, Henrik): the box range is 5 yalms** —
  `BOX_RANGE = 5`, pinned by test EB9; the fetch buttons go dead-red beyond it.
- ~~PLANNED: a central entity watcher~~ **BUILT (field round 6, after Henrik
  confirmed the box detection works): `lib/entwatch.lua`** — the subscription
  registry he specced: `watch(who, name [, cb])` registers WHAT is looked for
  and WHO is asking; one shared full-array sweep (2 s) serves every active
  watch, tracked matches get fast (0.25 s) distance refreshes with per-index
  name re-verification (slot reuse evicts, and evictions notify — a despawn
  between sweeps must not go silent); callbacks fire on match-SET changes;
  callback-less watches are demand-windowed (idle = zero work); `poke()` is
  the rescan cache-bust. All the entity-array idioms live there now.
  `eboxammo.boxDistance` = a three-line consumer (#1); gearmove's moogle
  scans migrate whenever that (GM-frozen) branch is next touched. Tests EW*.

## 8. PARKED — NIN shuriken: Daken / Sange / Yoru Shuriken (grill 2026-07-24)

**Status: PINNED, NOT BUILT.** Henrik's call at the end of the grill: *"We need to
test this properly before we put this into main branch. Let's leave this for now
until we get our ninjas up and can test properly."* Nothing below is implemented.
The research and the agreed design are recorded so the next session starts here
instead of re-deriving it.

### 8.1 What the server actually does (base code, local `stable` clone)

Trust ladder as always: live memory > this > nothing. The private override modules
(`modules/catseyexi`, `src/map/cexi`) are NOT in the checkout, and §8.2 proves they
matter here.

- **Daken** (`src/map/attackround.cpp` `CreateDakenAttack`, ~:529) requires a
  **shuriken worn** — `CItemWeapon::isShuriken()` = Throwing skill AND
  `subskill == SUBSKILL_SHURIKEN` (`src/map/items/item_weapon.cpp:96`) — rolls
  `Mod::DAKEN` and adds **one extra THROW swing per attack round**, weapon slot
  `SLOT_AMMO` (`attack.cpp:270`).
- Trait: NIN **main job only**, `traits.sql:692-696` → 20/25/30/35/40 % at
  Lv 25/40/55/70/95. Plus gear (`item_mods` 23142 → DAKEN 5), augment id 251
  ("Daken +1"), and job-point gifts (+2..+5).
- **The Daken throw consumes NOTHING in the base code.** The one and only
  consumption site is `src/map/entities/battleentity.cpp:3072` — a DAKEN swing
  removes 1 shuriken **only while `EFFECT_SANGE` (352) is up**.
- **Sange**: NIN Lv75 merit ability, 3 min recast, **1 min duration**;
  `scripts/effects/sange.lua` adds `DAKEN 100`. Its own header comment:
  *"Daken will always activate but consumes shuriken while active."*
- This CONTRADICTS retail (where Daken consumes per proc). Do not treat the
  no-consumption reading as truth until it is watched in the field.

### 8.2 Yoru Shuriken — the motivating item

**Id 22999**, Lv75, NIN, `AmmoType = "Throwing"`, DMG 85, Delay 192, Accuracy +8,
Ranged Accuracy +8, Magic Accuracy +8, Dark Resistance +10. It IS in the shipped
catalog; it is **NOT anywhere in the public server repo** — a CatsEyeXI private
custom. Henrik: it **does not consume during Sange**.

**The consequence that shapes the whole design: that property is server-side and
totally invisible to dlac.** No packet, no stat, no catalog field carries it. It can
only ever be *declared by the player*, never inferred. Its passive stats are also
the best of any shuriken, so the player wants it worn essentially always — which is
exactly what makes an accidental throw expensive.

### 8.3 The two real bugs this uncovered (both live on main today)

1. **The WS-ammo leak.** In `dispatch.lua`'s `resolveAmmoPlan`, Preshot/Midshot
   branch: with no ranged-enabled ammo in stock, the slot is emptied **only if the
   worn ammo is flagged Special**; otherwise it returns *hold*. So a **WS-only**
   ammo left worn from the last weapon skill, with the ranged stack exhausted,
   **stays in the slot and gets fired.** Henrik's words for the requirement:
   *"it shouldn't equip, and will empty the ammo slot if the target ammo for normal
   ranged attacks has been all consumed — to avoid accidentally using WS ammo or
   special-case ammo."*
2. **Special vs. a trigger, with no winning move.** The motivating setup is a
   trigger rule (`Has(De)Buff = Sange`) planning Yoru from the TP/Engaged set. Mark
   Yoru **Special** → the Default sweep runs *before* the yield-to-sets check, so
   AutoAmmo rips Yoru out **during** Sange, fighting the trigger every tick. Don't
   mark it → AutoAmmo yields, but nothing protects Yoru once the cheap stack is
   empty. **Neither configuration is safe today.**

### 8.4 The agreed design (to build after field testing)

- **`Sange` becomes a Special sub-behaviour** — the exact mirror of Unlimited Shot:
  wear it while effect **352** is up, sweep it the moment the buff drops. Read with
  the existing one-liner idiom, `buffActive(ctx, 352)`. This replaces the trigger
  rule entirely; the player stops hand-rolling it.
- **Widen the emptying mandate from "Special" to "not valid for this context"**, and
  scope it by what can actually be *lost*: **empty the slot when the worn item is a
  shootable ammo** (`AmmoType` ∈ Marksmanship / Archery / Throwing) that is not
  enabled for the current context — **whether or not it is on the player's list**.
  **Trinkets are left alone**: they are set-managed, they cannot be consumed, and the
  server refuses the shot anyway. (Implementation risk to check FIRST: the engine
  deliberately never loads the Catalog, so confirm `AmmoType` is already on the
  `gear.lua` stamp — if not, that stamp needs one field.)
- **No NIN hardcode.** AutoAmmo config is already per-job; choosing to flag shuriken
  under NIN IS the gate.
- A **`Melee` flag** (third sibling of Ranged / WS — "may be worn while engaged, for
  Daken") is the shape if passive Daken turns out to consume nothing. It is NOT
  settled: build it only once §8.5 answers the consumption question.
- **Player-facing text is part of the spec, not polish** (Henrik, verbatim intent):
  enabling the Sange behaviour must **clearly state that a second shuriken flagged
  Ranged + WS is required**, or the shot is blocked instead; and when AutoAmmo pulls
  the item, a **red chat line naming the item and the reason** —
  *"Yoru Shuriken removed — no shuriken enabled for Ranged/WS in your bags."*
  OPEN: whether that line repeats on a throttle while the condition holds (an empty
  Ammo slot also means zero Daken procs, i.e. silent damage loss) or fires once.

### 8.5 Timing truths worth keeping (verified in `feature/equipengine.lua`)

- **Preshot is the ONLY real seam for Ammo.** Ranged attack is outgoing 0x01A
  category **0x10** (`M.ACTION_ROUTES`, :127). `handleAction` (:536) **blocks** the
  packet, fires **Preshot — the equip goes out here** — and only then re-injects.
  The throw never leaves the client until dlac has dressed the slot, so there is no
  race and no reaction time involved.
- **`Midshot` fires AFTER the re-inject** (:551), i.e. mid-shot. Henrik field-tested
  the equivalent by hand (dlac unloaded, throw animating, manual unequip) and **the
  game refused it** — the server already owned the shot. So **any Midshot ammo plan
  is probably a silent no-op.** Verify before relying on one.
- **Daken procs are not action packets.** They resolve server-side inside the melee
  attack round; dlac never sees one and can never dress the slot per proc. The only
  levers are *when the item goes in* and *when it comes out*.

### 8.6 The field test that unblocks all of it

Needs a real NIN (Henrik: *"until we get our ninjas up"*).

1. Passive Daken, Sange DOWN: melee a few hundred rounds with a counted stack of
   cheap shuriken. **Does the count drop?** If it does not, §8.1 holds and a
   Special item is safe to wear for melee. If it does, retail behaviour wins and
   nothing Special may ever sit in the slot while engaged.
2. Sange UP with a cheap shuriken: confirm ~1 consumed per attack round.
3. Sange UP with **Yoru**: confirm the count does NOT drop (the custom property).
4. Sange expiring while Yoru is worn: confirm nothing is consumed in the gap before
   the next Default tick (~0.4 s).
5. Optional, and it makes step 1 self-answering: AutoAmmo already re-counts bags on
   every action event, so a **shuriken count that drops while engaged with no shot
   and no WS fired is proof Daken consumes** — the same self-teaching shape as the
   MP merit watcher. Offered, not yet chosen.

## 9. The Range slot decides the type (v128, 2026-07-26)

**Status: BUILT on dev, NOT field-tested.** Henrik's report: *"If my trigger rule
says 'Have this ranged bow equipped' while AutoAmmo was forcing a bolt into ammo
slot... AutoAmmo does NOT dictate if it's bolt, arrows or what not that gets
equipped. That is 100 % decided on what gets put in ranged. It should NEVER force
ranged off, that is HANDS OFF."*

### 9.1 What was actually wrong

`resolveAmmoPlan` was **type-blind**. It read the list order, the
Ranged/WS/Special flags, the live bag counts and the event — and nothing else. The
only type-aware line in the whole feature was Quick Draw's
`firstSpecial('quickdraw', 'Marksmanship')`. So the first `ranged`-flagged entry
with stock won, whatever it was, whatever you were holding.

The panel's Bullets/Bolts/Arrows/Throwing selector did **not** constrain it either
and never had: `categoryOf` is derived per render and stored nowhere (§2, "category
is a VIEW"). Picking Bolts in the GUI changed what you saw, not what loaded.

### 9.2 Why the cost was a flap, not a wasted swap

`src/map/utils/charutils.cpp` `EquipItem`, the SLOT_AMMO arm:

```cpp
// If the subtype of the ammo is not compatible with the ranged weapon, unequip it,
// except for Archery where Longbow and Shortbow both use arrows
if (PItem->getSkillType() != weapon->getSkillType() ||
    (weapon->getSkillType() != SKILL_ARCHERY &&
     PItem->getSubSkillType() != weapon->getSubSkillType()))
{
    UnequipItem(PChar, SLOT_RANGED, false);
}
```

The SLOT_RANGED arm is the mirror and strips SLOT_AMMO. **The server does not
refuse the equip — it takes the other slot off.** So AutoAmmo's bolt removed the
bow, the trigger put the bow back, the server dropped the ammo, AutoAmmo re-planned
the bolt. That is ADR 0010's "keeping both flaps forever" arriving through the
skill/subskill door instead of the rslot one — and it is why Henrik saw Range being
forced off by something that never writes Range.

### 9.3 The law, and the three special cases it absorbs

> compatible <=> same `skill` AND (`skill` is Archery OR same `subskill`)

Pair key = `"<skill>:<subskill>"`, from `item_weapon`. Surveyed over every
Range/Ammo item the API knows:

| key | Range | Ammo |
|---|---|---|
| 25:0 / 25:4 | shortbows (58) / longbows (133) | arrows (60) — **subskill EXEMPT, every bow fires every arrow** |
| 26:1 | guns (166) | bullets (39) |
| 26:0 | crossbows (83) | bolts (44) |
| 26:2 | culverins (2) | shells (2) |
| 27:0 | boomerangs, chakrams (47) | pebbles, tathlums, coins (34) |
| 27:3 | *(none)* | shuriken (19) — thrown with **Range empty** |
| 0:10 | Animators (13) | Automaton Oils (4) |
| 48:0 | fishing rods (20) | bait (39) |

Archery being exempt is not a nicety: a Longbow is 25:4 and a Shortbow 25:0, so a
uniform subskill match would break every bow in the game.

Three things previously hardcoded fall out of this one field: `ANIMATOR_FED`'s
id-pinned oil list is just 0:10 == 0:10 (and Animator P II is 0:11, which is why it
refuses the same oil); the Rimestone-class stat sticks are 0:0 / 1:0 and match no
real ranged weapon, which is the ADR 0010 trinket rule; and rod+bait is 48:0.

Two data quirks worth knowing, both upstream LSB, not CatsEyeXI:
**Hauksbok Bullet (22295) is subskill 0 — a BOLT** despite its name, which is why
the name-based Bullets/Bolts split can never be the authority. And
`Almogavar Bow` / `Staurobow` are skill 26 subskill 0 — **crossbows named "bow"**,
which is why the weapon side could never be name-derived at all.

### 9.4 The rules, in Henrik's words

- **Range is HANDS OFF.** AutoAmmo reads the slot; it has never written it and
  still does not. Its claim table is `{ Ammo = ... }` and nothing else.
- **No ranged weapon worn -> do nothing, on every event.** Safe because with Range
  empty the server refuses the shot, ranged WS need a weapon and Quick Draw needs a
  Marksmanship one — so nothing can be consumed and there is nothing to protect.
- **A weapon worn but nothing in the list pairs with it -> hold.** *"then autoammo
  should ignore it"* — never force a mismatch in, and never empty the slot over it.
- The protection sweep now also asks whether the worn special can be fired by the
  equipped weapon. One it cannot fire is in no danger, so removing it would be pure
  churn.

**THE PARKED EXCEPTION:** throwing ammo IS firable with Range empty
(`CanUseRangedAttack`'s `|| PAmmo->isThrowing()`) — that is how a NIN throws
shuriken, and 27:3 has no Range partner at all. Henrik: *"throwing may be an
exception, but we still need field tests for that."* The no-weapon gate therefore
stays shut for Throwing too until §8.6 is answered by a real ninja. **Do not widen
it on reasoning alone.**

### 9.5 Where the key comes from, and why it degrades instead of breaking

`apicrawl` emits `Pair` on every Range/Ammo record (the API's `weapon.subskill` was
always there — 1,173 such items cached, all with it, customs like Yoru Shuriken
included). The first pass emitted only 1,151 of them: the missing 22 were the
skill-0 Range families (Animators, Soultrappers), which apicrawl's category-nesting
walk had been discarding from `catalog.lua` outright. Fixed in `2fe7105` — that gap
is what kept an Animator from ever carrying the `0:10` key that pairs it with
Automaton Oil. From there it rides exactly the path `RSlot` already rides:
catalog -> `gearrecord.enrich` -> `gearimport` stamps it into `gear.lua` -> the
engine reads the raw file (`pairOf`, the twin of `rslotOf`). The GUI stores it on
each configured entry; `ammowatch._serialize` round-trips it.

`M.pairsWith` is **three-valued — true / false / nil** — and nil must never be read
as false. Both sides fall back rather than fail:

| side | best | fallback | worst |
|---|---|---|---|
| worn Range | manifest `Pair` (exact) | client resource `Skill` -> `"26"` | nil |
| list entry | stamped `pair` (exact) | `AMMO_TYPE_SKILL[entry.type]` | nil |

A skill-only key still separates a bow from a gun from a throwing weapon — the
headline bug — so **the update alone fixes it for every existing manifest and
ammostate file**; a manifest refresh upgrades it to telling a gun from a crossbow.
An unknown pair constrains nothing, because a missing data field must never read as
"AutoAmmo stopped working".

### 9.6 UI — type tabs, and the live one is green

Henrik's call, replacing the combo: *"Remove the text 'Ammo Type'... add tabs for
each type you can select, and have the tab that currently has a type active turn
green. For example, if a bow has been equipped, then Arrows tab lights up green."*

Buttons-as-tabs (the hobbybar strip idiom — `ImGuiCol_Button` is the one style enum
proven in the field in this file). The two signals are kept on separate channels so
they never fight over one colour: **green background = what your equipped weapon
fires**, blue = the tab you are editing, and the `Priority list -- <type>` header
carries the selection so it stays readable when green wins the same tab. The live
category comes from `gearoracle.wornItem(2)` — the catalog record, so it is exact in
the panel with no manifest refresh at all. `Other` still only appears when it has
contents *or* is the live type, so a culverin lights something.

First open lands on the type you are holding; after that the selection is yours and
a weapon swap never yanks it (the green tab reports the change instead).

### 9.7 Tests

`PW1-PW14c` pin the law itself (including the Archery exemption, the Animator
0:10-vs-0:11 pair, and unknown-is-nil-not-false). `AM40-AM50d` drive
`resolveAmmoPlan`: the no-weapon gate on every event, hold-when-nothing-pairs, the
exact field case (an arrow above a bullet with a gun equipped), crossbow-vs-gun
separation, both fallback ladders, and specials filtered by weapon.
`AW21h-AW21v` cover the category split and the serializer round-trip.
`AU1-AU10` are new: **the ammo panel's render had never been executed by any
test** — only its headless status half — so the tab strip is now driven for real
once per weapon branch with stack-balance assertions (the S50 crash class).

### 9.8 Field tests this needs

1. COR with a gun: bullets load, and an arrow sitting ABOVE them in the priority
   list is skipped instead of winning.
2. Swap gun -> crossbow with both bolts and bullets configured: the pick follows the
   weapon on the next dispatch, with no manual change.
3. RNG with a bow: arrows load; confirm a **Shortbow and a Longbow both** accept the
   same arrows (the Archery exemption — the one that would break loudest).
4. The original report: a trigger holding a bow, AutoAmmo on, bolts configured —
   the bow must STAY ON and nothing may flap.
5. Unequip the ranged weapon entirely: AutoAmmo goes quiet, touches nothing.
6. The panel: the tab matching your equipped weapon is green; swapping weapons moves
   the green without moving your selected tab.
7. PUP: an Animator with oils still behaves (0:10 pairs) — this is the regression
   risk from retiring nothing but touching the same law.

## 10. The level decides which rung (v134, 2026-07-27)

**Status: BUILT on dev + FIELD-CONFIRMED 2026-07-27** (Henrik: *"it works now"*) —
queued for promotion in HANDOFF's **Ready to merge**. `41432db` (engine, v134,
`2026.07.27m`), `401a6bb` (the CW removal, `27n`), `4d6bb12` (the panel, `27o`).
Henrik's report: *"on my Mindie DRK, even though I made a list of bolts on AutoAmmo and
enabled it, it is not equipping automatically even though I have them set to
ranged and ws. When I went from level 50+ to 8 it didn't equip any bolt (crossbow
bolt), then I levelled up to 10 (or rather, level cap did), it did not equip blind
bolt."*

The sibling of §9, and the same shape of hole one door further along: v128 taught
the ladder what the **weapon** can fire; it still had no idea what the **player**
can wear.

### 10.1 The artifacts answered it before any theory did

Live `ammostate.lua`, DRK section, exactly as the GUI wrote it:

| # | entry | Lv | flags | pair |
|---|---|---|---|---|
| 1 | Acid Bolt | 15 | ranged + ws | 26:0 |
| 2 | Blind Bolt | 10 | ranged + ws | 26:0 |
| 3 | Crossbow Bolt | 1 | ranged + ws | 26:0 |

Best-first — what the *Sort by level* button produces, and per field round 1
"that's usually how you want it either way". `enabled = true`, pair stamps all
present, so §9's machinery was working perfectly. And his DRK sets carry a real
Range ladder (`Light Crossbow +1` → `Lgn. Crossbow` → `Crossbow +1` → …), so a
crossbow WAS worn and §9's no-weapon gate never fired. Three of the four inputs
were right; the fourth was never asked for.

**The two observations are one bug, and it is blind twice over.** The testing was
done with the **level override** (`/dl set level main N`, §10.3) on a DRK whose
real level is 50-something — which is what makes the symptom so clean, because
the override is invisible to everything downstream:

- *"I have it overridden to level 10 now. When I make the slot empty, it still
  tries to auto equip acid bolts."* — `firstRanged` returns Acid Bolt (it pairs
  26:0, it is stocked, it is ranged-flagged) and stops. The equip then
  **succeeds**: `equipcore` and the server both judge the REAL level. Blind when
  choosing.
- *"When I was my normal level, and set it lower, I had acid bolts on me already
  but didn't change."* — the Default arm never re-judges what is already worn
  (`if wornL == nil`, `dispatch.lua:4830`). Blind to what it had already chosen.

**The override is the sharpest case, not a special one.** A real low level or a
real level cap produces the same wrong pick — it just fails one step later, and
more quietly, because there the name dies at `equipcore.checkUsable`
(`gear/equipcore.lua:170-176`, the `level < item.Level` arm) or at the server. And
nothing downstream can recover it:

> **The overlay collapses a ladder to a single name before the equip layer ever
> sees it.** A set hands `equipcore` a slot with candidates and the level walk
> picks a rung; AutoAmmo hands it `{ Ammo = "Acid Bolt" }` and there is no rung 2.

(Under a real cap, `equipengine.SETTINGS.AllowSyncEquip = true` feeds dlac's own
gate the TRUE job level, so the over-cap plan sails past dlac and dies silently on
the wire: no bolt, no message, no trace.)

**Why the Range slot looked fine while the Ammo slot did nothing** — the two
travel different roads. `utils.determineLevels` (`utils.lua:69-87`) reads
`player.MainJobSync`, the capped number, and `checkRebuildNeeded` re-flattens on
every level change, so set rungs follow the cap by themselves. AutoAmmo's ladder
had no level input and no re-ask.

`helmwatch` had this right all along (`feature/helmwatch.lua:721-752`:
`playerLevel()` off `GetMainJobLevel()`, `(hat.level or 0) <= lvl` down the
ladder). AutoAmmo was the one gear picker that never got it.

### 10.2 The rule, in Henrik's words

> *"Ammo should scale with level according to the list if they have an
> interoperable ranged. So take the best ammo out of the list according to the
> sort order based off of the current level."*

**List order stays the authority; level is a filter, not a sort key.** Walk the
list top-down and take the first entry that clears all four gates:

1. **flag** — ranged / ws / the special's window, per the §3 decision table
2. **pair** — §9's `M.pairsWith` against what is in Range (unknown never disqualifies)
3. **stock** — count ≥ 1 in the equippable bags (`AMMO_BAGS`, `dispatch.lua:4538`)
4. **level + job** — NEW: the current level can actually wear it

Gate 4 goes inside `firstRanged` / `firstWs` / `firstSpecial` (`dispatch.lua:4739-4759`),
so every context inherits it at once — normal shots, consuming WS, free WS,
Quick Draw. The ladder now asks exactly the question the equip layer will ask,
one step earlier, where it can still fall through to the next rung.

### 10.3 Where the level comes from — the resource, not the record

`ammostate.lua` persists a `level` per entry, but that is a GUI convenience
written for the *Sort by level* button: it can be stale and pre-2026-07-20
entries have none.

The authoritative source is already in hand. `bagCounts` (`dispatch.lua:4542`)
calls `GetItemById` for every item in the bags and memoizes id → name; `Level`
and the `Jobs` bitmask come off the **same resource**, so a parallel memo is two
lines in a loop that already runs. And because gate 3 already requires the item
to be in your bags, **every candidate gate 4 judges has a live resource** —
"unknown level" is very nearly unreachable.

Ladder: client resource by id → stored `entry.level` → unknown. Unknown **allows**
— the standing law from `M.pairsWith`, *a missing data field must never read as
"AutoAmmo stopped working"*.

**The job bitmask rides along**, same read, same reason: `equipcore.checkUsable`
refuses a wrong-job item at the equip layer (`bitSet(item.Jobs, job)`), which is
the identical silent dead-end one door down. A DRK list carrying a RNG-only bolt
should skip that entry, not stall on it.

**The level source is `playerLevel(ctx)` (`dispatch.lua:1305`) — the house
authority, and the engine already owns it:**

```lua
-- The character's current effective level (honours the /dl set level main override).
local function playerLevel(ctx)
    local sl = rawget(_G, 'staticMainLevel');
    if type(sl) == 'number' and sl > 0 then return sl; end
    local lv = ctx.player and ctx.player.MainJobSync;
    if type(lv) == 'number' and lv > 0 then return lv; end
    return 75;
end
```

Not raw `MainJobSync`, and this is the correction the field round forced. The
**level override** (`staticMainLevel`, typed via `/dl set level main N` or the
`ui/menuui.lua:369` panel) is honoured by the set flatten (`utils.lua:74`), by
the virtual-slot resolver (AutoStaff / AutoObi are gated on this very function),
by the optimizer and by the GUI — but **not** by `feature/equipengine.lua`, whose
`snap.level` reads live memory only. So under an override your sets gear down
while the equip layer keeps accepting anything your real level can wear. Reading
`MainJobSync` would have left AutoAmmo the last picker in dlac that ignores the
override — which is exactly the bug the player reported, unfixed.

The division is clean and worth keeping straight: **`playerLevel` is what dlac
gears you AT (choice); `equipcore`'s level is only a legality gate against the
real game (permission).** AutoAmmo is a chooser.

And `MainJobSync` is still the fallback inside it, so a real low job and a real
level cap ride the same code — the same number the set flatten and `helmwatch`
already use. Never `MainJobLevel`: under a cap the true level is exactly the
number that produces the bug.

### 10.4 The Default arm re-judges what is already worn

The level filter alone fixes observation 1 and **not** observation 2. The Default
arm is `if wornL == nil then` (`dispatch.lua:4830`) — it only ever loads into an
EMPTY slot. Ding 8 → 10 with Crossbow Bolt worn and Blind Bolt would sit
unreachable until the next Preshot re-asked the question.

Henrik: *"if a level moves down, and you have an ammo in it that is over the
level, then it should automatically equip the next best thing according to that
level"*, and on the way up, *"yes, swap it up."*

So the arm becomes: compute the best legal pick, then act when **any** of these
holds —

- the slot is **empty** (today's reload), or
- the worn ammo is **over-level** (explicit — do not trust the server's strip; a
  sync that doesn't strip must still be corrected; worn level via `levelOf`,
  `dispatch.lua:2878`), or
- the worn ammo is **on this job's own list** and is no longer the best pick.

— and otherwise hold. **The guard is the whole safety story: AutoAmmo only ever
replaces ammo that is on its own list.** A legal ammo that is not on the list is
untouchable, which is what keeps the DRK **Midshot** set's `Cinderstone` in place
after every ranged attack. The rejected alternative was *"AutoAmmo owns the Ammo
slot outright when enabled"* — that strips Cinderstone every idle tick after a
shot, which is ADR 0010's keeping-both-flaps-forever arriving through a third
door.

No new level-change hook is needed: Default already re-asks every ~0.4 s, so a
cap landing re-picks by itself once the arm is allowed to act on an occupied slot.

### 10.5 The sync-settle coupling (new, and it is the point of this scenario)

`M.syncSettleHold` (v56, `dispatch.lua:1890`) arms a 1 s hold the instant
`MainJobSync` jumps, and while it is up every dispatch keeps Main/Sub/Range **as
worn** — *a level reading that just changed is not trusted yet*. Ammo is not a
weapon slot (`WEAPON_SLOTS`, `dispatch.lua:3759`), so AutoAmmo ran straight
through that window.

That was harmless while the picker ignored the level. **It is not any more.**
`ammoOverlayFor` now holds while `ctx.syncHold` is true: at most one second, only
when the level moves, and it stops AutoAmmo planning a bolt off a half-settled
level against a Range slot that is itself being held as worn. Same reasoning that
already governs the weapon slots, applied to the one other slot that just became
level-sensitive. The cost — a second of empty Ammo slot at a cap landing — buys
nothing back for an attacker, because an empty slot is a server-blocked shot.

**A level OVERRIDE change does not arm this hold, and must not.** `syncSettleStep`
tracks `MainJobSync`, which an override never moves. That asymmetry is correct:
typing a level is a deliberate act with nothing in flight to settle, so the new
pick should land on the very next dispatch (~0.4 s) — which is also what makes the
override the fastest way to field-test this whole section. Do not "fix" it into
symmetry.

### 10.6 Loudness: stock talks, level doesn't

Henrik: *"If you run out of ammo, do a print to notify the player. [...] But no
prints should be necessary for ammo change due to level change."*

This forces a mechanical change: **`resolveAmmoPlan` returns a machine-readable
reason code** beside the prose `why` — `stockout` / `level` / `pick` / `protect`
— because the printer now speaks for one class and stays silent for another. The
prose string keeps carrying the detail for `/dl why`.

| event | channel |
|---|---|
| a stack empties, ladder falls through | chat: *"AutoAmmo: Acid Bolt is out — loading Blind Bolt."* |
| nothing enabled left in the bags | chat, red: *"AutoAmmo: no enabled ammo left in your bags."* |
| protection `remove` (existing) | chat, unchanged |
| the pick changed because the level moved | **nothing** |
| routine skips down the ladder | nothing (`/dl why` carries it) |

Prints are **edge-triggered on a change of cause**, not on a timer: the engine
re-plans every ~0.4 s, so a remembered last-cause is what keeps one stack-out
from becoming a scroll. (The existing 10 s `_ammoWarnAt` throttle stays as the
backstop for the `remove` line.)

`/dl why` gains the skip in its note: `ranged pick: Crossbow Bolt (Acid Bolt,
Blind Bolt need a higher level)`.

### 10.7 UI — the Lv column and the green row

- **A level column in the priority row**, mirroring the qty column's idiom
  exactly: `Lv15` in red when out of reach, tooltip *"Needs Lv 15, you are Lv 10 —
  the engine skips this entry"*, the twin of the existing *"None in your
  equippable bags — the engine skips this entry"*. Had it existed, the DRK list
  would have shown two red rows and one white one at a glance.
- **The live row is green** — green marks *the entry actually in your Ammo slot
  right now*, the same law the §9.6 type tabs already follow (green = live fact,
  blue = your selection). If a set or a trinket owns the slot, no row is green,
  which reads correctly.
- Row space comes free from §10.8.

### 10.8 The Crystal Warrior half is removed

Henrik: *"let's remove the CW side of it. Please also remove the fetch rows for
CW. We have E-box restocker now which is better."*

Out of `ui/ammoui.lua`: the `eboxammo` require, the `cwBox` gate +
`refreshIfStale(15)`, the proximity strip (*in range / too far / none in sight* +
`rescan`), the per-row `E-Box: xN` + qty input + **Fetch** / **Fetch up to**, and
the trailing status line. **The panel keeps no gamemode awareness at all** — no
`gamemode.get()` call remains in it, everyone sees the same AutoAmmo.

Nothing is lost: `restockwatch` entries carry an `ahCat`, so category 15
(Ammunition) is already fully within **E-Box Restock**'s reach, with targets and
top-up — which is what *"Fetch up to"* was reaching for.

`feature/eboxammo.lua` (a 199-line thin adapter over `eboxclient` since ADR 0016)
is **deleted whole**. Its one non-panel surface — the hidden `/dl ebox`
diagnostic: gamemode + entwatch state + the full 0x000-0x8FF entity dump with
render flags and distances — **moves to `feature/eboxtrace.lua` as
`/dl debug ebox scan`** rather than dying with it. That probe ended the two
"buttons are always red" field rounds; proximity is still what refuses a
Restocker withdraw, so the day a fetch goes dead-red again it answers it in one
command — and it lands in the module that already owns E-Box diagnostics.

§2b above is superseded and kept only as history.

### 10.9 Tests

- `AM51-AM6x` on `resolveAmmoPlan`: the level filter on every context arm
  (ranged / consuming WS / free WS / Quick Draw / specials); list order preserved
  under the filter; job-bitmask skip; unknown level allows; the exact field case
  (Acid 15 / Blind 10 / Crossbow 1 at levels 8, 10 and 15); the Default arm's
  three act-conditions and the not-on-my-list hold; the reason codes.
- `PW`-style pins for the level source ladder (resource → entry → unknown).
- `AU*` gains the Lv column and the green row; its E-Box branches are deleted.
- `EB*` (the eboxammo adapter checks) are deleted with the module; the entity-dump
  move gets one `/dl debug ebox scan` smoke check.
- The sync-hold coupling gets a pure test alongside the `LS*` family.

### 10.10 Field tests this needs

1. **The report itself, via the override** (fastest loop — no zoning, no
   levelling): DRK, `/dl set level main 10`, empty the Ammo slot → **Blind Bolt**
   loads, not Acid Bolt. Set 8 → Crossbow Bolt. Set 15 → Acid Bolt. Set 0
   (override off) → back to Acid Bolt. Each swap lands within ~0.4 s and prints
   **nothing**.
2. **Wearing the wrong one already**: at full level with Acid Bolt worn, drop the
   override to 10 → Acid Bolt is swapped out for Blind Bolt on its own (the case
   that "didn't change" in the field).
3. A **real** cap or a genuinely low job behaves identically — the override is
   only the fast path to the same code (`playerLevel`'s `MainJobSync` fallback).
4. Run a stack dry mid-fight → one chat line naming the fallback; run them all dry
   → the red dead-end line, once, not per tick.
5. A trinket in Ammo from a Midshot set → still there at idle, never swept.
6. RNG at 75 with the mixed bullets/bolts/arrows list → §9's behaviour is
   unchanged (the level gate must be invisible when everything is wearable).
7. Panel: the worn bolt's row is green, out-of-reach rows show a red `Lv`, and no
   E-Box anything appears on a Crystal Warrior character.
8. `/dl debug ebox scan` near an Ephemeral Box reports it, and E-Box Restock is
   untouched by the removal.
