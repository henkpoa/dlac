# dlac — Architecture

> Module map and data-flow reference for anyone (human or agent) picking the project up.
> Line references are as of 2026-07-10 (main @ 591a207); the code moves fast — treat them
> as anchors, not gospel. Start with [HANDOFF.md](HANDOFF.md) if you're brand new.

dlac ("dynamic LuaAshitacast") is an Ashita v4 addon for CatsEyeXI that GUI-drives
LuaAshitacast (LAC) equipment sets so players never hand-edit profile Lua. It runs as a
normal `/addon`, reads player/inventory through `AshitaCore`, and drives gear through
LAC's `gFunc.EquipSet` from library modules that are *seeded into each character's LAC
profile folder*. The design rests on a deliberate two-Lua-state split (ADR 0002): the
**addon state** writes data files; the **LAC state** evaluates them at cast time.

---

## Repository layout

**The rule: the addon root is what LuaAshitacast sees. Folders are what only the addon sees.**

```
dlac.lua                 Ashita entry point (Ashita requires <addon>/<addon>.lua — cannot move)
utils.lua  dispatch.lua  chatfmt.lua  profiles.lua  gear.lua
                         ^ the SEEDED ENGINE — dlac.lua copies these into <char>\dlac\, where
                           they load a second time inside LAC's Lua state. Flat by necessity;
                           see "Dual identity" below before touching their paths.
PROFILE_TEMPLATE.lua     what Setup writes into a user's <JOB>.lua

ui/        imgui modules: gearui, triggersui, automationsui, equippedui, profilesmenu,
           setupui, weightsui, craftbar, uistyle, uihost, itemicons, filetex, floatgear,
           ammoui (the AutoAmmo panel)
data/      generated / static tables: catalog, crafts, fishdb, spells, abilities,
           statdefs, levelscaling, levelstats
gear/      the gear pipeline: gearoptim, gearimport, gearexport, gearcheck, gearfmt,
           setmanager, setimport, profilesets, ownedcache, syncflags, weaponfilter,
           groupsmodel, actionpicker, catalogindex, gearoracle (THE worn-item +
           equip-bag door)
feature/   self-contained features: lockstyle, macrobook, useitem, craftwatch, augments,
           pinwatch, helmwatch, fishwatch, fishcalc (pure fishing math -- headless),
           ammowatch (AutoAmmo config state)
lib/       generic helpers: cmdqueue, statefile, entwatch (the central entity
           watcher: subscription registry + one shared scan, all the
           entity-array idioms in one place)
assets/    PNGs (loaded by absolute path via AshitaCore:GetInstallPath — not by module path)
docs/  tests/  tools/
```

Module names carry the folder: `require('dlac\\ui\\gearui')` → `addons\dlac\ui\gearui.lua`,
because the `package.path` shim substitutes the whole name into `addons\?.lua`.

Two traps when moving files or grepping module names:

1. **`dlac\X` is not always a module.** The same prefix names *per-character data files* under
   `<char>\dlac\` — `dlac\triggers`, `dlac\modestate`, `dlac\lockstyles`, `dlac\macrobooks`,
   `dlac\craftstate`, `dlac\ammostate`, `dlac\gearweights`, `dlac\profiles\<name>\`. Those are user state and must
   never be folder-qualified. Note the near-misses: the `lockstyle` **module** vs the
   `lockstyles` **data file**; `macrobook` vs `macrobooks`; `crafts` vs `craftstate`.
2. **The engine five cannot move.** See below.

## Central services — ask these, never re-derive

The one-answer functions ("Henrik's shape": callers ask the question, the
plumbing is the service's problem). When a feature needs one of these answers,
it CONSUMES the service — a local re-implementation is a bug waiting for the
field round that already happened. All run in the **addon state** (the seeded
engine cannot require them; it has its own minimal reads).

| The question | Call | Module | The rules that bite |
|---|---|---|---|
| **Is this character a Crystal Warrior?** (game mode at all) | `gamemode.get()` → `'CW'` \| `'Wings'` \| `'ACE'` \| `nil` | `feature/gamemode.lua` | UCW deliberately ⇒ `'CW'` (same playmode — Henrik's ruling). `nil` = UNKNOWN, never a value to gate on: CW-only UI must gate on the **affirmative** `== 'CW'` and stay hidden on nil. First consumer: `eboxammo.isCW()`. |
| **Is there an entity named X nearby, and how far?** | `entwatch.watch(who, name[, cb])` then `entwatch.nearest(name)` / `.matches(name)`; `.poke(name)` = rescan | `lib/entwatch.lua` | THE central entity watcher — never write a local scan. It owns the idioms that cost three field rounds: GetName pads with whitespace (trim + ci), rendered bit 0x200 (signed-u32 fix) before trusting a distance, `GetRawEntity` (never the dead `GetEntity(i)`), the FULL 0x000-0x8FF range (custom NPCs are dynamic entities). Distances in yalms (squared on the wire). Callbacks fire on match-set changes incl. evictions; callback-less watches sleep 15 s after the last ask. Consumers: `eboxammo` (Ephemeral Box), `helmwatch` (the four "* Point" names while Auto HELM is armed). |
| **How many of item id N do I own?** | `ownedcache.counts()` (equippable bags) / `.totals()` (anywhere) / `.verdict(rec)` | `gear/ownedcache.lua` | counts = what can actually be equipped/consumed NOW; totals includes storage (the red "stored" coloring everywhere in dlac). |
| **What is this item?** (any item, owned or not) | `catalogindex.flat()` / `.rawById(id)` / `.rawIndex()` | `gear/catalogindex.lua` over `data/catalog.lua` | The catalog's `Slot` lies toward Body for unimplemented rows (`jobs==0` is the junk marker); `AmmoType` absent = trinket. |
| **Any gear question** (worn item, equip bags, eligibility, identity, effective stats) | `gearoracle.wornItem(slot)` → `{ id, rec, extra, item }` \| nil; `.equipBags()`; `.canWear(rec, job, level)`; `.anyJobCanWear(rec, jobLevels)`; `.lookup(idOrName)`; `.stats(rec, ctx)`; `.setStats(comp, ctx)` | `gear/gearoracle.lua` | THE one door in the addon state (issues #70/#71, PRD #69; boundary rulings in **ADR 0013**). **FETCH:** the worn-item decode (packed Index → container/slot → item) + the ONE equip-bag list (Inventory + 8 Wardrobes); byte-identical engine TWINS (`dispatch.decodeEquipIndex` / `dispatch.AMMO_BAGS`, ADR 0002) held by the OR-section parity pins. `wornItem` hands the id back RAW (0/65535 included). **ELIGIBILITY:** `canWear` fronts the engine rule (`dispatch.canWear` — main job only, level on main); `anyJobCanWear` delegates to the addon-state gate (`gear/jobgate.canEquip`, fail-open). **IDENTITY:** `lookup` joins owned-first then catalog (id authoritative). **Claim-BLIND, permanently** — capability only, never permission (`canWear`, never `canEquip`); the Arbiter is the sole precedence authority. FACADE, not absorb: the interpreters keep their homes. **The door is LAW (#73):** the HARD RULE source guards (run_tests §GRD) confine the worn read, the packed-index decode, the equip-bag list and the 22-job list to their one home, and forbid feature/UI modules from requiring the stat interpreters — the Phase-2 stat-glue allowlist was **emptied by #74** (`stats`/`setStats` migration), so the rule is now absolute. |
| **Where is this character's dlac state dir?** | `statefile.charDir()` | `lib/statefile.lua` | nil pre-login — retry, never cache the nil. (The seeded engine has its own `charDir()` inside dispatch.lua.) |
| **This character's native MP pool?** | `nativemp.self([meritMP])` / `.get(race, mjob, mlvl, sjob, slvl)` | `data/nativemp.lua` | The server's formula verbatim; merits are NOT native — pass them in. Never calibrate against the on-screen max (traits/gear ride the display only). |
| **Queue a chat/game command safely?** | `cmdqueue` | `lib/cmdqueue.lua` | Two same-frame QueueCommands arrive REVERSED in other states — this queue drains one per frame. Also: an addon state never hears its OWN queued commands back. |
| **E-Box (CW storage) counts / withdraw?** | `eboxammo.counts` / `.withdraw(id, qty)` / `.boxDistance()` | `feature/eboxammo.lua` | Crystal Warriors only (see gamemode row); 0x1A4 is a party line — pending-request discipline; `BOX_RANGE = 5` field-pinned. |
| **Item icon / hover card in UI?** | `deps.renderIcon(id, size)` / `deps.itemTooltip(rec)` | `ui/itemicons.lua` + gearui's `renderItemTooltip`, injected via the shared deps table | ONE hover card serves every equipment surface — never draw a rival. |
| **The automations list + coverage status?** | `automationsui.listRows()` + `.levelColor(level, max)` | `ui/automationsui.lua` | The SAME rows/ramp the Automations tab shows (Teleports quick menu is consumer #1) — never rebuild the list or invent a rival color ramp. `{}` before init/login; MaxMP graduated 2026-07-21 and rides the same list. |
| **Is the MaxMP mode on? / flip it** | `automationsui.maxmpMode()` / `.maxmpToggle()` | `ui/automationsui.lua` | THE shared reader/flipper for every surface (panel button, list row, quick menu). Reads the LAC engine's modestate mirror (1s TTL — display can lag a beat); the toggle sends the EXPLICIT `/dl mode maxmp on\|off`, never a blind flip. Auto-disables on job change. |
| **The max-MP band plan?** | `dispatch.M.mpBands(ctx)` → context; `mpbands.build/target/tick` (pure core) | `dispatch.lua` (LAC state) + `feature/mpbands.lua` | ONE context serves the engine AND `/dl plan` — the plan IS the behavior, never render a rival. Current MP is the only live read; `GetMPMax` is unreliable during gear churn and floored party MP% == 100 is the only exact fullness signal. Read docs/design/maxmp-mode.md (rulings ledger + failure museum) before touching. |

Adding a new central service: generic plumbing goes in `lib/`, game-domain
answers in `feature/` or `data/`; give it the gamemode shape (one exported
question, injectable reads, headless tests) and ADD IT TO THIS TABLE.

## Module reference

### dlac.lua — addon entry point
The Ashita addon shell. Sets `addon.*` metadata, installs the `require` path shim that
lets profile-style `require("dlac\\X")` resolve inside the addon state, preloads the
character's real `gear.lua`, seeds the library into the per-char LAC folder, provides a
`gData` shim for standalone operation, then loads the library modules.
Key points: `package.path` shim (dlac.lua:27-29); per-char `gear.lua` preload into
`package.loaded['dlac\\gear']` (34-50); library seed to `<char>\dlac\` (57-76); `gData`
shim (job/level from AshitaCore) (82-107); module load loop (111-119).
Requires `common` and `chatfmt`, then loads a folder-qualified list — `gear`,
`feature\augments`, `gear\gearoptim`, `gear\gearimport`, `gear\gearexport`,
`feature\useitem`, `feature\craftwatch`, `ui\craftbar`, `feature\helmwatch`,
`ui\helmbar`, `feature\fishwatch`, `ui\fishbar`, `feature\lockstyle`, `ui\gearui`;
everything else (`utils`, `dispatch`, `gear\setmanager`, `ui\triggersui`,
`ui\automationsui`, `gear\profilesets`, `gear\gearcheck`) loads transitively. That list is built by string
concat (`'dlac\\' .. mod`), so a grep for a literal `require('dlac\\gearexport')` finds
nothing — the loop is the only loader for some modules.
**Writes** `<char>\dlac\{utils,dispatch,chatfmt,profiles}.lua` every load (always flat —
see Repository layout); seeds `<char>\dlac\gear.lua` only if absent.

### utils.lua — profile-side rebuild engine
The single `require` a migrated profile needs. Re-exports the gear inventory and the
dispatch entry point, and owns the level-scaling **Dynamic-set rebuild** engine plus the
dual-wield / sub-slot pairing rules (H2H pairs with NOTHING — decided by Type via
`isH2H`, never the OneHanded flag, which lies for H2H; ADR 0006 addendum 2026-07-22).
Refreshed into every character's `dlac\` folder on each addon load.
Exports: `M.rebuildSets(sets)` (utils.lua:120-129); `M.BuildDynamicSets(sets)` (212-372,
virtual-entry handling 251-254 and 350-356); `M.subSlotAllowed` (193-210);
`M.classifySub` (176-185); `M.isDualWieldAvailable` (131-171, trusts `HasAbility(1554)`);
`M.determineLevels` (65-83). Registers the base `/dl` command handler (397-479).

### chatfmt.lua — chat styling
The one place defining dlac's colored `[dlac]` chat header (coral name, distinct from
LAC's teal). Provides a drop-in `print` that re-heads `"[dlac] "`-prefixed lines. Nearly
every module requires it (guarded) to shadow `print`.

### dispatch.lua — trigger dispatch engine
The heart of the trigger system, running in the **LAC state**. Reads the per-job trigger
file, matches the live action/player against each rule's `when`, and `EquipSet`s every
match in ascending priority (overlay, ADR 0003). Also resolves virtual slot entries
(auto staff/obi), owns session mode/lock state, and serializes trigger files for the GUI.
Key points: `M.VERSION` (35, engine-staleness handshake — bump when seeded behavior
changes); matcher table `MATCHERS` (170-205); specificity `TIER` (212-220); hot-reload
`ensureLoaded` (307-387, content-compare, throttled 1/s); automations `resolveStaff`
(451-471) / `resolveVirtual` (474-510) / `equipResolved` (521-560); `M.dispatch(event)`
(644-724); `M.serializeTriggers` (757-825); mode state mirror `saveModeState` (833-851);
command handler (946-1079).
Reads/writes `<char>\dlac\triggers\<JOB>.lua`; reads `<char>\dlac\autogear.lua` and the
per-feature state files (`craftstate`/`helmstate`/`fishstate`/`pinstate`/`ammostate`);
writes `<char>\dlac\modestate.lua`. Since v73 it also owns the **AutoAmmo overlay**
(docs/design/auto-ammo.md): a per-event Ammo-slot decision with the engine's first bag
counter and the literal-`'remove'` plan (LAC's native unequip) — pure core
`M.resolveAmmoPlan`, tests AM*.

### gear.lua — owned-gear template
The **per-character owned-gear** record: thin entries (Name/Level/Id + weapon metadata)
for items the character possesses; empty in the repo (the repo copy is only the seed).
Builds a `NameToObject` reverse index. Stats are NOT stored here — they derive from the
catalog by Id at load.

### data/catalog.lua — CatsEyeXI equipment reference (~5.8 MB, generated)
The full crawled equipment reference — base-truth stats for every item. Same nested
shape as gear.lua (`Slot -> [weapon Category] -> PascalCaseKey -> {Name, Level, Id, Jobs,
OneHanded, Type, Stats}`). Consumers flatten it into an Id index (`_allEquipById`).
Rebuilt by `tools/apicrawl.py` (gitignored). The dispatch engine never loads it (ADR
0004) — only the addon state does.

**The source is not clean, and `Slot` is where it lies (2026-07-15).** CatsEyeXI's
`item_equipment` table carries rows for **unimplemented** items, with no marker and
default values: `jobs=0`, `MId=0`, and **`slot=32`, which decodes to Body**. 258 of the
259 therefore land in the **Body** bucket — `Gletis Crossbow`, `Mpacas Bow`, `Pinaka`,
the Amini/Boii `+2`/`+3` reforge tier — which is exactly why the lockstyle picker once
offered crossbows and boots for Body. apicrawl now skips `jobs == 0` rows (Body: 1743 →
1485), so a current catalog is clean; `smoke_ui` **S21** fails if a re-crawl puts them
back. Two rules if you touch this: **`jobs==0` is the marker, not `MId==0`** (the latter
also covers 814 *real* modelless items like all `Hexed` gear, whose stats the catalog
must keep), and **an empty jobs mask is not "All"** — the decode used to publish these
stubs as equippable by every job. Details: `tools/README.md` "The junk rows".
Consumers must not assume a catalog `Slot` is the client's truth; the bag scan slots
owned gear from the CLIENT resource (`gearimport.slotFromMask`), which is authoritative.

### gear/gearimport.lua — inventory reader + gear.lua writer
Reads owned equippable gear from Ashita memory and turns it into gear.lua entries; owns
the scan→stage→commit pipeline, plus fix/dedupe/prune maintenance and the silent
auto-sync.
Key points: `M.SCAN_CONTAINERS` (availability: Inventory + 8 Wardrobes) vs
`M.ALL_CONTAINERS` (ownership truth: everything) — see ADR 0005; `M.scan`; `M.stage`;
`M.commit(quiet)` (gearimport.lua:934); `M.fix` (catalog-metadata backfill);
`M.dedupe`; `M.prune`/`M.pruneWhy`; `M.sync()` (scan→stage→commit only when new gear
exists, add-only) (1457); command handler (1483+).
Writes `<char>\dlac\gear_staging.lua`, `<char>\dlac\gear.lua`, rotated backups in
`<char>\backups\`. Every write is backup + parse-checked + sandbox-validated, aborting
untouched on failure.

### ui/gearui.lua — main GUI (host client + Sets core)
The main ImGui window shell (header buttons, Setup plan popup, tab bar) plus the Sets
machinery (working set model, auto-build, candidate pools, scoring, slot grid, stats
panel, item tooltips). Everything else moved out behind uihost (below). gearui still
owns the three Ashita hooks (`d3d_present` / `packet_in` inv-dirty / `command`) and the
shared `ui` view-state table, publishes the shared services via `host.provide{}`, and
registers its own Sets tab + the weights window like any other module.
Was pinned at EXACTLY 200/200 LuaJIT main-chunk locals (compiler-verified); now ~134
with `tests\smoke_ui.lua` guarding the cap. New features MUST still be born as modules —
register a tab/window via uihost instead of adding gearui locals.

### ui/uihost.lua — UI module registry (the Trove plugin model, v40)
`host.register({name, tabs = {{label, render}}, window = {render}, invalidate})` +
`host.provide{}`/`host.services` (ONE live table gearui fills before requiring tab
modules — modules may capture entries at load). Registration order = tab order
(Equipped, All Equipment, Sets, Triggers). Deliberately unlike trove/utils/plugins.lua:
a STATIC require list (no `io.popen` discovery — popen spawns console windows), and
renders run under the caller's guard (gearui's `tabGuard`). Extraction set that rode in
with it: **itemicons.lua** (D3D texture cache: `renderIcon`/`handleOf`/`release`, no-op
safe headless), **equippedui.lua** (Equipped + All Equipment tabs; captures
host.services at load — provide-before-require is load-bearing), **setupui.lua**
(`jobSetupState` + `migrateCurrentJob`/`migrateToCleanProfiles` — THE SETUP
STANDARD, 2026-07-17: an existing job file never stays live; it is verified into
`backups\pre-profiles\` and replaced by the clean shim (convert-in-place is dead);
starter profile/trigger seeding; `setup.configure{}` deps), **syncflags.lua** (auto-sync loop + uiflags.lua
persistence; owns `sf.flags.debug`/`sf.flags.autosync`/`sf.flags.viewids`; gearui's d3d_present calls
`sf.loadUiFlags` BEFORE `sf.tick` — order is load-bearing, the real gear.lua must swap
in before the first sync), **weightsui.lua** (stat-weights editor: Points + Priority
tabs, sortable columns, clear buttons; scoring stays in gearui/gearoptim),
**profilesmenu.lua** (the Profiles popup tree + forms; state in the shared ui
table), **floatgear.lua** (the floating 4x4 equipment window + the PIN menu — v44; a
`window`-only module, no tab; reuses `S.renderSlotGrid` so its icons and hover tooltip
are literally the Equipped tab's and cannot drift). `tests\smoke_ui.lua` headless-loads
the whole chunk: 200-cap breaches, registration order, services contract.

### Pins — floatgear.lua + feature/pinwatch.lua + dispatch v44
"Equip item, lock slot so nothing removes equipped item" (Henrik), built as an OVERLAY
rather than a lock — the same shape as the craft overlay, for the same reason (a lock
is passive and leaks; an overlay is recomputed every dispatch). **`floatgear`** edits
the table, **`pinwatch`** writes `<char>\dlac\pinstate.lua`, and the ENGINE wears the
named items as the LAST `equipResolved` of every dispatch — above the craft overlay, on
every event. Unpin → overlay gone → the normal set returns.

`scope` is `'All'` or a list of `"<Event>|<rule label>"` keys, spelled by
`dispatch.pinScopeKey` over `dispatch.ruleLabel` — ONE definition each, called from both
Lua states, because a label the two states spell differently is a pin that never
matches. Pins are session-only and the clear must reach DISK (`pinwatch.loadPinState`,
pumped from gearui's d3d_present whether or not the window is open): the engine reads
the file from LAC's state, so a stale file would dress you at login. "Lock" still means
the old, near-opposite thing (`M.locks` = engine ignores the slot).

### The Arbiter — claim registry (dispatch.lua + feature/arbwatch.lua, ADR 0012)
The **single precedence authority** for gear that dresses over the Trigger overlay floor.
Every feature that wants a slot registers a **Claim** with the Arbiter instead of equipping
directly; per slot the Arbiter walks a strict, draggable rank list top-down and the first
claimant with an opinion wins. The rank is one per character, persisted as the `arbstate`
Statefile (writer: `feature/arbwatch.lua`; reader/default/sanitize: `dispatch.arbOrder`,
one vocabulary). Default order **Pins > Locks (veto) > AutoAmmo > MaxMP > Craft > HELM >
Fishing > Triggers (floor)**.

**The Claim record shape** — deliberately tiny, because a new claimant must be *one
registry entry + one rank row, never a new engine arm*. (**AutoAcc is NOT a future
claimant** — Henrik's ruling 2026-07-21: it is a Type automation, per-piece candidate
release while over the hit cap, any slot — within-set resolution, the altitude below
the Arbiter. Its effect is part of whatever the floor or a claimant resolves.)

- A **Claim** is just `{ [SlotKey] = itemName }` — the slots a feature wants to dress, one
  item per slot. The Locks veto is a Claim whose values are the `M.LOCK_HELD` sentinel
  ("keep what is worn"); the Triggers floor is the merged trigger-overlay table.
- To join the Arbiter a claimant adds exactly two things: **(1)** its name to
  `ARB_ORDER_DEFAULT` (+ the arbwatch UI list), and **(2)** in `M.dispatch`,
  `claims['<Name>'] = <its slot→item table>` plus — if it applies a discrete overlay —
  one `applyClaim` closure keyed by the same name. Who wins each contested slot, ceding,
  the Locks veto and `/dl why` attribution all fall out of the rank list automatically.

**Pure seams** (all headless-tested, tests `AR*`/`LV*`): `arbResolve(claims, order, floor)`
→ winners + `by` attribution; `arbCededAbove(claims, order, who)` → slots a claimant must
not contest (won above it); `arbLockClaim(locked)` → the veto Claim; `arbExplain` /
`arbWhyLines` → the per-slot `/dl why` claimant lines ("`Ammo: AutoAmmo (rank 3) over MaxMP
(rank 4)`"; veto slots read "stopped by Locks"; the slots the floor dressed uncontested
collapse into one trailing "Triggers floor (uncontested): …" summary).

**MaxMP is the worked example of the boundary.** It registers a Claim (`mpClaimFor` → its
battery targets) so its *precedence* is fully in the registry, yet its *equip* stays WOVEN
inside `equipResolved` — hold/release/upgrade, sticky pairs and movement yield are
**within-set resolution**, deliberately OUTSIDE the Arbiter (ADR 0012). Also outside, by the
same rule: sync-settle/proximity holds, the PetAction gate, AutoStaff/AutoObi virtual
entries, Dynamic flattening and the ADR 0010 trinket contests. The Arbiter arbitrates
*between* claimants; each claimant's *own* conditions (idle-only stand-asides, AutoAmmo's
fishing stand-down, `'remove'`-respect) stay inside the feature.

### ui/triggersui.lua — Triggers tab (+ Groups section)
GUI editor for the dispatch engine's data: rules per handler, mode toggle buttons.
Split out of gearui for the 200-local cap. Commit rewrites the trigger file via
`dispatch.serializeTriggers` and pings the engine to hot-reload. Writes
`<char>\dlac\triggers\<JOB>.lua`. The Automations machinery lived here until
2026-07-18 — it is now `ui/automationsui.lua` (below), which freed 30 of this
module's 123 top-level locals (cap 200; the "noted 200-local relief", done).

Also owns the **Groups section** (`M.renderGroups`, issue #25 / ADR 0009) — a nav
section inside the Triggers tab (NOT a uihost tab; smoke_ui asserts `host.get('groups')`
is nil) that edits the *same* file's
`Groups` section, so both surfaces share one `trig.data` / one Commit. The pure CRUD +
name/member validation is `gear/groupsmodel.lua`; the `group` trigger condition's value is a
dropdown of the job's groups, and a rule pointing at a missing group is surfaced (parity
with a missing set). Members are added by free-name typing or from a searchable,
job-filtered spell/ability browse-list with multi-mark (issue #26, G3 — pure list/search
core `gear/actionpicker.lua`).

Also owns the **Blueprints section** (`M.renderBlueprints`, issue #65 / PRD #64) — the same
Groups-style nav section (NOT a uihost tab; smoke_ui asserts `host.get('blueprints')` is nil).
A per-rule **"bp" (Save as Blueprint)** button on every trigger row captures the rule into the
per-character library (`gear/blueprintsmodel.lua`, `<char>\dlac\blueprints.lua` — outside
Profiles, addon-state only); the section lists the library with **Stamp onto this job** (insert
the rule into the current job's Handler and commit through the SAME `trigCommit` path — engine
hot-reloads it, no Reload LAC; warn-but-allow on an identical rule), **Edit** (the existing rule
editor bound to the library entry via `trig._bpEdit` — no second editor, never retro-edits
stamped Triggers), rename and Delete. Library writes go through the `lib/safewrite` ladder.

### ui/automationsui.lua — Automations tab + the manifest machinery
The whole automations block, extracted verbatim from triggersui 2026-07-18 (it owned
30 of triggersui's top-level locals and shared nothing with the trigger editor beyond
the deps table). Owns DERIVING the manifest — staves/obis/Iridescence (ADR 0004),
MaxMP battery ladders, craft/HELM/fish gear ladders — from the player's bags via
`deps.ownedList`/`lookupByName` (plus `lookupById` for id-PINNED entries: relic
stages share one display name, so 'Laevateinn' pins 18994 / 'Tupsimati' 18990 —
the only stages carrying Iridescence on live; a name-resolved record with the
wrong id is rejected, never adopted), and writes `<char>\dlac\autogear.lua`
(`AUTO_FMT` schema; an outdated on-disk manifest self-heals on render). The LAC-state engine
hot-reloads that file and resolves the `dlac:` virtual markers from it.

gearui builds **one deps table** and hands it to BOTH `trigui.init` and `autoui.init`
— helmui/fishui take the whole table per call from this module's detail views, so
every downstream contract kept its pre-extraction shape. The rescan seams live here:
`M.rescanAutogear` (manifest regen + gearcheck chat warn, called by gearui's
auto-sync hook at login/job-change/inventory cadence), `M.manifestStale` /
`M.currentFmt` (craftwatch, helmwatch and fishwatch force a regen before the engine
reads stale ladders). `M.renderTab` is the tab entry point (guard ladder + login
gate). No forwarders were left on triggersui — smoke_ui S140–S151 pin both the new
home and the absence of the old one.

### gear/groupsmodel.lua — Trigger-Groups model core (pure)
The Ashita/imgui/file-IO-free CRUD + name/member validation the Groups tab drives (issue
#25, ADR 0009): `fromRaw` (sanitize the file's `Groups` section into the model), `names`,
`findName`/`hasGroup`, `validateName`, `add`/`rename`/`remove`, `addMember`/`removeMember`.
Group and member names compare case-insensitively (engine `M.groupMatch` parity); an empty
member list is legal. Headless-tested (TGM*). Never seeded into LAC.

### gear/groupimport.lua — the "Import Lua Table(s)" transform (pure)
The addon-state, Ashita/ImGui/file-IO-free core of the Groups section's bulk import (issue
#30, G4; ADR 0009): `parse(text)` sandbox-evaluates pasted `Name = T{...}` / `Name = {...}`
assignments (bare lines OR a whole `{ ... }` table; `T` is identity; trailing commas
tolerated) into `(groups name→members, errors[])` — flat-only, so a nested / non-string /
named-field value skips THAT key with a reported reason while the rest import. The sandbox is
the hardened `profilesets.sandboxSets` pattern (env = `T` and nothing else, `'t'`-mode load),
so malformed or hostile input yields an error, never a crash or code execution. `classify`
splits created vs collide (case-insensitive) and `apply` writes into the live `Groups` map,
overwriting a collision under its existing stored spelling. triggersui draws the paste box +
the overwrite confirmation + the summary. Headless-tested (TGI*). Never seeded into LAC.

### gear/groupscan.lua — auto-import: scan a Lua file for group tables (pure)
The auto-import sibling of `groupimport` (Item 1): `scan(fileText) -> (candidates, notes)`
text-scans a LuaAshitacast job file for top-level `[local] NAME = T?{...}` blocks and surfaces
every group-shaped table as an import candidate, so a player who already keeps spells grouped in
their file skips the copy-paste. A `%b{}` walk pulls each top-level block (never descending, so a
gear set's inner `['Idle'] = {...}` is not a hit); each body is evaluated in `groupimport`'s
sandbox (`evalTable`) and classified by its `membersOf` heuristic — a flat string array is one
candidate (a directly-defined group, or a variant/config table), a container of flat arrays
expands to one candidate per inner key (the `BlueSpells` case), and a gear set / settings block is
skipped with a note. Candidates are deduped case-insensitively and sorted; comments are stripped
first so a stray brace can't unbalance the scan. triggersui draws the `Scan → tick → Import` panel
(config-looking names pre-unticked) and reuses `groupimport`'s classify / overwrite-confirm /
apply. Headless-tested (GS*). Never seeded into LAC.

### gear/actionpicker.lua — searchable spell/ability browse-list core (pure)
The Ashita/imgui/file-IO-free core behind the Groups tab's member browse-list (issue #26,
G3; ADR 0009). `buildList(job, spells, abilities)` returns the job's LEARNABLE spells +
abilities as ONE combined, case-insensitively sorted list of `{ name, kind, level }` (kind =
`'spell'`/`'ability'`), deliberately **ungated** — the level is display only (build-ahead,
HARD RULE 6). The picker-DB tables (`data/spells`, `data/abilities`) are **injected** (the
setimport resolver precedent), keeping it pure/testable. `parseQuery` + `matches` are the
comma-separated, ALL-terms-substring search predicate (the item-search shape, minus stat
aliases). triggersui caches the list per job and draws the multi-mark popup; the two helpers
are the whole browse capability, coupling-free so an ordinary `name` trigger condition can
adopt the same picker later (issue #12). Headless-tested (ACP*). Never seeded into LAC.

### gear/blueprintsmodel.lua — Blueprints library + stamp transform (pure)
The Ashita/imgui/file-IO-free core of **Blueprints** (issue #65, slice 1; PRD #64; CONTEXT.md
term, ADR 0009 the structural precedent). A Blueprint is a job-independent saved Trigger kept
in ONE per-character library file OUTSIDE Profiles (`<char>\dlac\blueprints.lua`) — addon-state
only, the engine never reads it (no VERSION involvement). An entry is `{ name, handler, rule }`
where `rule` is the ordinary trigger edit-model rule VERBATIM (`when`/`whenAny`, a `set`
string/list OR inline `equip` payload, optional priority) — so a stamped rule is an ordinary
Trigger forever. Exports: `fromRaw`/`parse`/`serialize` (the library file, sandboxed load +
deterministic emit — a `blueprints v1` table), `defaultName` (a readable condition summary,
e.g. "Sleep or Lullaby"), `add`/`rename`/`remove` (CRUD), `makeEntry`, and the two transforms
the headless suite pins (TGB*): **`stamp(entry, jobData)`** → a NEW data table with the rule
appended to the entry's Handler (non-mutating, deep-copied → detached both ways) and
**`identicalExists`** (the warn-but-allow double-stamp check). `emitRule` is a self-contained
mirror of `dispatch.serializeTriggers`' per-rule form (issue #65 forbids any engine change), so
the file, the identical-rule canonical form, and (slice 2) the shareable text render a rule ONE
way. triggersui owns the file IO (the safewrite ladder) + the section render. Never seeded into LAC.

### gear/gearoracle.lua — THE Gear Oracle: one door for gear questions (issues #70/#71/#74, PRD #69)
The single addon-state answer for every gear question. A **facade, not an absorb**: it
fronts the proven interpreters (which keep their homes, tests and field-tuned behaviour),
so no module re-states a rule and drifts. **Claim-BLIND, permanently** — every answer is
a capability ("*could* this character use this item"), never permission ("*may* this slot
change now"); the Arbiter stays the sole precedence authority; method names use could-words
(`canWear`), never may-words (`canEquip`).

- **FETCH (issue #70).** **`wornItem(slot)`** — the equipped-item resolution (packed
  `GetEquippedItem` Index → container/slot → the container item), returning
  `{ id, rec, extra, item }` (id RAW so each caller keeps its own guard) or nil; and
  **`equipBags()`** — the ONE equip-eligible bag list (Inventory + the 8 Wardrobes). The
  three hand-rolled worn decodes (gearui `getEquippedId`, augments `slotExtra`, useitem
  `readiness`) and the bag-list literals all route here.
- **ELIGIBILITY (issue #71).** **`canWear(rec, job, level)`** — main-job/level equip gate;
  DELEGATES to the engine module's addon-visible rule (`dispatch.canWear`). The two inline
  fallbacks (gearoptim, gearui) are DELETED — their re-statements of "no job list means
  wearable" were the exact deduction drift this ends. **`anyJobCanWear(rec, jobLevels)`** —
  the lockstyle any-job-at-current-level gate; DELEGATES to the addon-state gate module
  (`gear/jobgate.canEquip`), which keeps its FAIL-OPEN semantics (the nil-levels fail-open
  belongs to the caller). lockstyle's gate calls migrated here.
- **IDENTITY (issue #71).** **`lookup(idOrName)`** — "what is this item": the owned-record +
  catalog-record join (owned first, then the full catalog; id authoritative, name the
  case-insensitive fallback). ONE recipe; the enriched flattened indexes are injected by the
  surface that builds them (gearui, via `setLookupSource`) — the oracle can't flatten raw
  gear.lua itself because a Phase-2 owned record carries no stats until enrichment. gearui's
  `lookupById`/`lookupByName` are now thin adapters over this door.
- **EFFECTIVE STATS (issue #74, the Phase-2 stat-glue migration).** **`stats(rec, ctx)`** —
  effective item stats: the level-scaled resolver (`levelstats.effective` at `ctx.level`)
  PLUS the private-augment fold (`ctx.augStats`, folded per Id, copy-on-write). ONE recipe,
  replacing the hand-glue the manifest builders carried. **`setStats(comp, ctx)`** — the
  full composition evaluation INCLUDING set bonuses, a THIN delegation to the reference
  set-bonus evaluator (`geareffects.comboStats`, untouched). Plus the interpreter
  passthroughs the Sets core + worn panel now read through the door instead of requiring the
  interpreters: `setsOf`/`setInfo`/`setTier` (membership + tier ladders), `scales`/
  `levelThresholds` (level-scaling introspection), and the augment reads (`augStats`/
  `augLabels`/`wornAugStats`/`wornAugExtra`/`describeAugments`/`dumpAugments`). The migrated
  callers — automationsui's MaxMP/HELM/fishing/craft manifest ladders, gearui's Sets-core
  totals/hover/scoring, equippedui's worn-augment display — are proven byte-identical by the
  golden harness (#72, smoke_ui §12). This **emptied the GRD5 stat-glue allowlist**
  (`tests/run_tests.lua`): no feature/UI module requires `levelstats`/`geareffects`/`augments`
  any more, and the source guard is now absolute.

Addon-state only, **never seeded** — ADR 0002 keeps the engine's own byte-identical TWINS
in dispatch.lua (`decodeEquipIndex` / `AMMO_BAGS`), and the OR-section parity pins in
`tests/run_tests.lua` feed both a fixture matrix and NAME the twin on any drift; OR14-29
pin canWear against `dispatch.canWear`, anyJobCanWear against `jobgate.canEquip`, the lookup
join, and the claim-blind boundary (no `canEquip` door). The exporter's duplicate catalog
walk is retired too — it now routes its id-index through `catalogindex.rawIndex()`, leaving
exactly one catalog nested walk in the codebase.

### gear/profilesets.lua — profile `sets` reader
Reads the loaded profile's `sets` table for the Sets tab. In LAC state reads
`gProfile.Sets`; in addon state parses the current `<JOB>.lua` in a permissive sandbox.
Cache hits content-follow the Dynamic source file (1s byte compare) — a Profiles-menu
import rewrites the active profile's files without moving the cache key. The same
follow idiom lives in triggersui's edit model (dirty models get a drift banner instead
of a silent clobber) and lockstyle's boxes (2026-07-22; tests TGW/PSW/LGW).

### gear/setmanager.lua — `<JOB>.lua` reader/writer
Splices dynamic sets into `<JOB>.lua` and analyzes the dispatch handler shims —
the write side of Sets-tab Commit, and `analyzeShims` powers `jobSetupState`'s
shim-health check. Pure-text core (`analyzeShims`, `repairShimsText` — comment-aware
since 84de48a) with file wrappers (`repairShims`, `commitSet`, `deleteSet`). Since the
clean-shim SETUP STANDARD (2026-07-17) nothing in the product calls `repairShims` —
the repair pair stays as the tested text engine behind any future manual wiring. All
edits are backup + parse-checked, abort untouched on failure. Writes rotated backups
in `<char>\backups\`.

### gear/setimport.lua — the "Copy from static" transform (pure)
The addon-state, Ashita-free core of the Sets tab's "Copy from static" (issue #15, ADR
0008). `importStaticSet(staticSet, slotLabels, resolve)` walks the source set in slot
order and returns `{ working = slotLabel→ordered candidate list, notBestFirst = slots
whose order is not highest-item-Level first, slotCount }`. The resolver (name→owned
record) is **injected** — gearui passes its `resolveSetItem`, the headless suite a stub
over owned records — so the transform is pure and testable (tests AO0–AO23). Candidate
order is carried verbatim; gearui does the full-replace into the selected set, the
overwrite confirmation, and the per-slot divergence warning. Never seeded into LAC.

### gear/gearoptim.lua — stat-weight optimizer
Two read-only tools: MP-spent→potency swap advice, and a stat-weight scorer/best-set
builder (`M.score`, `M.buildBestSet`). Purely advisory — never equips. Reads/writes
`<char>\dlac\gearweights.lua`.

Weight tuning is PER SET only and has TWO modes per set since 2026-07-17: **points**
(the classic per-stat `perUnit`/`cap` table) and **priority** (an ordered stat list,
top matters most, optional caps — the "simple" mode). Priority scoring derives a
points table with dominance weights (bottom-up: `perUnit = 1 + max total everything
below could score`, uncapped stats assumed ≤500 across a set) so the whole existing
pipeline — `score`, `optimizePicks`, `pairLadders`, Auto-build — runs unchanged
behind `activeWeights()`. `getWeights()` returns the EFFECTIVE table; the points
editor reads `getPointWeights()`. The mode flips to whichever editor's data you
mutate; looking never switches it. Priority lists have their own per-set store and
their own named store (`prioPerSet`/`prioNamed`/`modePerSet` sections in
gearweights.lua) — a point template and a priority list never cross-load. New
bindings start BLANK (weights, priority list) with the fixed default build-slot
mask (weapons unmarked). The old SHARED (no-set) table is a **dead concept**
(Henrik 07-17): unbound, the actives alias read-only empty sentinels — every reader
sees "no weights", every mutator refuses with 'no set selected' — and older files'
`shared`/`slotsShared`/`prioShared`/`mode` sections (plus pre-per-set flat files,
which were only a shared table) are dropped on load.

### gear/gearmove.lua — storage move engine (EXPERIMENTAL, feature/storage-move only)
"[mv]" button + popup to move items between containers via the 0x029 packet, gated to
Mog House / Provenance via the 0x00A LoginState gate (see
docs/design/storage-move.md — the memory MH flag is field-falsified on CatsEyeXI).
Addon-state only; never seeded into LAC. Single-in-flight state machine with pre-send
re-verify and 2s timeout (server rejects silently).

### gear/gearcheck.lua — trigger-gear availability audit
Warns when a trigger-referenced set uses gear that isn't in an equippable bag ("set
Tp_Default uses Kraken Club in Main — it is in Mog Safe"). Fires on job change, after
moves, `/dl gearcheck`, and renders a Triggers-tab warnings section. Deliberately
self-contained so it can be cherry-picked to main independently of gearmove.

### feature/augments.lua — CatsEyeXI augment decoder
Decodes private augments from an item's `Extra` bytes (`id = word & 0x7FF; magnitude =
(word>>11)+1`) into stat deltas and readable labels. `AUG_STATS` (summable) vs `AUG_NAME`
(display); non-linear ids are deliberately display-only. Authority for id meanings:
CatsEyeXI's own `enum_augment_name` (private server repo — never commit it) > LSB
`augments.sql` > wiki. Six ids (136, 163, 205, 214, 219, 256) are undefined no-op gaps —
do not chase them. Writes `<char>\dlac\augdump.txt`.

### data/statdefs.lua — stat metadata registry
Single source of truth for stat presentation/weighting: key, label, section, percent,
lowerBetter, aliases (~178 entries, 7 sections). Presentation only — **no server mod-ids**
(those stay in gitignored `tools/`). `M.canon()` resolves aliases to canonical keys
(PDT/MDT/DT/MDMG/MAB/MACC are canonical; descriptive forms are aliases).

### data/levelscaling.lua / data/levelstats.lua — level-scaling data + resolver
Generated map of item Id → additive threshold rows from the server's `item_latents`
(31 items: Rajas/Tamas/Sattva etc.), and the resolver that applies them at display/
scoring time. The dispatch engine never needs it — the game applies real latents.

### data/spells.lua / data/abilities.lua — picker databases (generated)
Per-job spell/ability acquisition-level tables from CatsEyeXI's public server SQL, for
the Triggers-tab "usable now" browse lists (milestone M4). First consumer: the Groups
tab's member browse-list via `gear/actionpicker.lua` (issue #26 — job-filtered, ungated);
the ordinary-trigger `name` picker (issue #12) is the next adopter of the same seam.
Generated by `tools/gen_pickerdb.py`. Known: ~40
levels differ from the wiki (private-submodule customizations); a wiki-sourced overlay
is planned — see docs/reference/catseyexi-jobs.md.

### PROFILE_TEMPLATE.lua — clean profile example
The minimal hand-written `<JOB>.lua`: one `require("dlac\\utils")`, a `sets.Dynamic`
scaffold, each handler ending in `utils.dispatch('<Handler>')`.

### tests/run_tests.lua — headless test harness
Pure-Lua tests needing no Ashita: stubs `package.loaded['dlac\\gear']`, `ashita`,
`gData`, and a controllable `AshitaCore.HasAbility(1554)` BEFORE loading modules, then
`dofile`s `utils.lua` / `gearimport.lua` / `setmanager.lua`. Sections: A subSlotAllowed,
B isDualWieldAvailable, C BuildDynamicSets, D-E computePrune/computeFixes,
F analyzeShims/repairShimsText.
Run from the addon root: `& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\run_tests.lua`

### tests/goldenfixtures.lua + tests/golden/ — the Phase 2 golden-output gate (issue #72)
**THE safety gate for the Gear Oracle Phase 2 stat-glue migration** (PRD #69, step 5).
`goldenfixtures.lua` builds one deterministic, synthetic, headless BLM character and
captures the EXACT output of every stat-glue manifest builder — the MaxMP battery ladder
(MP / Refresh / Convert batteries, the movement map, **and the augment fold**), the HELM
ladders + hat map, the fishing ladders, the fishcalc **rod-ranking gear reads**
(`rodsFor`/`bestOwnedRod`, `wornFishTotal`, `gearScore`), and the per-craft owned-gear
walk. The fixtures cover the interesting cases the PRD names: **level-scaling** items
valued at the character's level (Tamas Ring, catalog id 15545: MP 15 base → 29 at Lv74),
**augment-fold** copies (Hlr./Clr. Bliaut +1), and **one item across multiple ladders**
(Survey Sash → MaxMP + HELM + fishing). The captured strings are the builders' own output
verbatim — only the manifest's `written` clock stamp is normalized — committed under
`tests/golden/*.golden` (pinned `-text` in `.gitattributes` so Windows autocrlf can't
mangle them). **smoke_ui section 12 asserts the builders reproduce the goldens
BYTE-IDENTICALLY**, so when Phase 2 migrates the builders onto `oracle.stats()` the same
fixtures must produce the same goldens — a later field failure can never be misattributed
to the migration. Regenerate ONLY after an intentional builder/format change (review the
diff): `lua5.4 tests/gen_goldens.lua`.

### tools/ — maintainer scripts (gitignored, not shipped)
`refresh_all.py` = THE one-command update after a CatsEyeXI patch (runs everything
below in order); each script also runs alone, and all SQL generators share
`modmap.py` as the one modid→stat-key parser so a lone re-run and the umbrella can
never disagree. `apicrawl.py` builds catalog.lua (live API); `gen_petmods.py` builds
petmods.lua (item_mods_pet SQL — the pet channel the API never serializes);
`gen_levelscaling.py` builds levelscaling.lua + latentstats.lua;
`gen_gearsets.py` builds gearsets.lua; `gen_pickerdb.py` builds spells/abilities;
`modifier_map.lua` = modid→stat map; `api_cache/` holds the crawl cache + the
stat-naming decision log (`stats_decisions.txt` — the agreed mod→key bridge).
Gitignored so scraping details and the mod enum aren't published; only generated
data ships.

---

## Dual identity & the require redirection

Two Lua states load the same files for different jobs:

- **Inside a LAC profile.** LAC's `package.path` finds the seeded copy at
  `<char>\dlac\utils.lua`, which transitively requires `dlac\gear`, `dlac\dispatch`,
  `dlac\chatfmt` — the four files dlac.lua keeps refreshed there. `dispatch` detects
  this state via `inLac()` = `rawget(_G,'gFunc') ~= nil` — only here does it own
  mode/lock state, register its commands, and actually `EquipSet`.
- **Inside the dlac addon.** dlac.lua appends `<install>\addons\?.lua` to
  `package.path`, so the same `require("dlac\\X")` resolves to `addons/dlac/X.lua`.
  `inLac()` is false → `dispatch.dispatch()` no-ops. The addon preloads the character's
  real gear.lua and installs a `gData` shim so shared modules work standalone.

**Why the engine five stay flat at the repo root** (`utils`, `dispatch`, `chatfmt`,
`profiles`, `gear`): a single `require("dlac\\profiles")` line inside `dispatch.lua` has to
resolve in *both* states — to `addons\dlac\profiles.lua` in the addon, and to
`<char>\dlac\profiles.lua` under LAC. Same relative path, two roots. Folder-qualifying them
in the repo would therefore force the seeded copies into a matching subfolder, and
`require("dlac\\utils")` is **published API**: it is line 26 of PROFILE_TEMPLATE.lua and sits
in every hand-written user profile. Moving it breaks those profiles for a purely cosmetic
gain, in the one code path that runs on every job change. Everything the addon alone loads is
free to live in a folder; these five are not.

Cross-state coordination is **by files**: the LAC engine mirrors mode/lock state and its
`VERSION` to `<char>\dlac\modestate.lua`; the GUI reads it and shows a red "Reload LAC"
banner when the seeded engine is stale. The reload pair is always: `/addon reload dlac`
(reseeds files) **then** Reload LAC (makes LAC re-require them) — disk reseed alone is
never a hot swap.

**The boundary rule (ADR 0014, cross-referenced with ADR 0002): the Engine equips gear
(and reports on its own equipping) — nothing else.** The command bus between the two states
is unreliable BY DESIGN — `e.blocked` halts LATER addons in Ashita's command chain, and
`/addon reload` order IS chain order — so a feature whose trigger and executor sit in
different states can starve on one load order and go deaf on the other. The lockstyle pivot
(2026-07-23) settled the durable law: **never cross the bus.** An Automation lives Engine-
side because it equips gear THROUGH LAC (`gFunc.EquipSet`); lockstyle equips *nothing* (it
builds its own 0x053 and injects via the process-wide `AshitaCore`), so it is
**addon-resident** — trigger and executor in one state, reaching each other by direct call.
No lockstyle trigger crosses the wall in either direction; the bus problem stops existing
rather than being bridged. The engine-move direction
(`docs/design/lockstyle-engine-move.md`) is superseded by this ADR.

Under the **Native engine** (§ The Native engine) the same law holds trivially: there is
only ONE state, so "never cross the bus" is satisfied by construction — the Engine's
gear-equipping and lockstyle's 0x053 both live in the addon state, direct calls all the
way down. The two-state boundary above describes **legacy mode**; it graduates from law
to history when LAC does.

**The command-surface rule:** *a `/dl` command lives where its subject lives.* Equip state
in the Engine (`mode`, `why`, `plan`, `prio`, `lock`, `sets`, `profile`, `env`, `triggers`
— their LAC dependence is subject matter, not accident); everything else in the addon;
`check`/`debug` straddle the wall by design (they report on both states via the file
channel). Collapsing a command to ONE claiming state is what makes it chain-order-proof for
typed use — the deafness bugs came from BOTH states claiming `/dl`.

## Data flow

- **catalog.lua** (shipped) — crawled base-truth stats; addon-state only (browse,
  tooltips, enrichment, optimizer). `enrichGearFromCatalog` fills statless owned entries
  by Id.
- **petmods.lua** (shipped) — pet-channel gear stats (`item_mods_pet`: what the gear
  grants TO YOUR PET, e.g. Drachen Brais "Wyvern: HP+10%"). Lives BESIDE catalog Stats
  because the live API never serializes the pet channel — the repo SQL is the only
  source. Answered by THE Gear Oracle (`oracle.petStats`, a deliberately separate
  answer from `stats()` — pet values never fold into master stats); `gearfmt.petLines`
  composes the display (tooltips; row summaries spend leftover token budget).
  Priced for weights since 07-22 evening: `oracle.petScoreStats` flattens the channel
  under `Pet:`-namespaced keys (All + best named type — a pet is exactly one type),
  merged at gearui's `candidateStats` seam and listed in the weights stat menu via
  `oracle.petStatKeys` (+ statdefs' derived `Pet:` labels). Master `stats()`/`setStats()`
  stay pet-blind — the goldens pin them. No engine participation.
- **gear.lua** (per-char) — thin ownership record. Written by stage→commit and by
  auto-sync (`M.sync`, add-only). `refreshGear` re-reads it in place so the GUI updates
  without an addon reload. Ownership = ALL_CONTAINERS; availability (= can equip right
  now) = Inventory + Wardrobes; stored-only gear renders red (ADR 0005).
- **Profile sets files** (per-char) — `sets.Dynamic.<Name>` ordered candidate lists in
  `dlac\profiles\<active>\sets\<JOB>.lua` (same `sets = { Dynamic = {...} }` shape the
  job files used, so setmanager's scanners splice them unchanged), written by
  setmanager; legacy fallback: the block inside `<JOB>.lua` for unmigrated characters.
  At cast time `rebuildSets` → `BuildDynamicSets` flattens each Dynamic set to the best
  level-eligible piece per slot; the engine equips the flattened set. Set changes
  hot-swap (`/dl sets reload`, pinged by Commit); the engine also auto-installs the
  active profile's sets into every fresh `gProfile` (LAC load / job change / `/dl
  profile use`) — see profiles.lua and docs/design/profiles.md.
  **The auto-install is the engine's ONE latch, and it is load-bearing** (ADR 0007):
  it resolves per `(gProfile, profileName, job)` and then stops, because re-reading the
  sets file every 0.4 s tick would be absurd. That makes it the only reader that does not
  self-heal — every other one (triggers, craft state, pin state, mode mirror) re-reads on
  a throttle. So it must (a) refuse a not-ready job — `M.jobReady`, since `GetMainJob()`
  reads 0 at login and gData stringifies that to the *real-looking* `"NON"`; and (b) never
  latch on a question it could not answer (`setsPath(job) == nil` = "can't tell yet", not
  "no sets file"). Getting this wrong cost a silent session-long no-op: `Dynamic` stayed
  `{}` and every trigger equipped nothing. `/dl instdiag` (TEMPORARY) dumps its state.
- **Trigger files** `dlac\profiles\<active>\triggers\<JOB>.lua` (legacy fallback
  `dlac\triggers\<JOB>.lua`) — written by the Triggers tab via
  `dispatch.serializeTriggers`; hot-reloaded on content change. A broken hand-edit keeps
  the last good rules and reports.
- **Auto-sync chain** (addon state, on login/job change): `gearimport.sync` →
  `refreshGear` → automations manifest rescan (`autogear.lua`) → `gearcheck.chatWarn`.

## Trigger dispatch path (end to end)

1. Each `<JOB>.lua` handler ends with `utils.dispatch('<Handler>')`; `HandleDefault`
   first calls `utils.rebuildSets(sets)`. Setup appends these shims without removing
   player code.
2. `utils.dispatch` → `dispatch.dispatch(event)`, which bails unless `inLac()`.
3. `ensureLoaded` hot-reloads rules; `buildCtx` reads `gData.GetPlayer()/GetAction()`;
   each rule's `when` is ANDed through `MATCHERS`.
4. Hits sort by priority ascending (specificity tiers: any 10 / status·skill 20 /
   class·element 30 / contains 40 / name 50 / automation 60 / mode 100; file order on
   ties); each is applied in order so later writers win per slot (ADR 0003).
5. `equipSetByName` pulls the flattened `gProfile.Sets[name]` → `equipResolved` →
   `gFunc.EquipSet`. Locked slots (`/dl lock`) are stripped.
6. Virtual slot entries: `BuildDynamicSets` encodes `'dlac:AutoStaff|<fallback>'`;
   `equipResolved` splits marker/fallback → `resolveVirtual`: AutoStaff = best tiered-
   Iridescence staff from autogear.lua (level-gated; ties go to the universal; since
   v82 the universal comes from the manifest's `universals` ladder — preference-ordered,
   first rung usable at the live level, so a level sync falls through to a lower rung);
   AutoObi = elemental/universal obi only when the day/weather net is positive.
   Unresolvable → fallback; no fallback → drop the slot.
7. Per-slot attribution is recorded for `/dl why`.

## The `/dl` (= `/dlac`) command surface

Registered across six handlers; each blocks only its own subcommands.

| Command | Module | Does |
|---|---|---|
| `/dl ui [on\|off\|toggle]` | gearui | GUI window |
| `/dl sync` | gearui | Import new gear now |
| `/dl autosync [on\|off]` | gearui | Toggle on-job-change sync |
| `/dl debug [on\|off]` | gearui | Reveal dev header buttons |
| `/dl view_ids [on\|off]` | gearui | Add item id + model id to every equipment tooltip |
| `/dl mode <name> [on\|off\|toggle\|<value>]` | dispatch | Flip a mode (no arg: list) |
| `/dl lock <slot\|all> [on\|off\|toggle]` | dispatch | Engine-owned slot locks |
| `/dl why` | dispatch | Last-dispatch trace + per-slot **claimant** attribution (winner + rank, "stopped by Locks", "Triggers" floor) |
| `/dl prio` | dispatch | The Arbiter's live rank + per-claimant claim status (ADR 0012) |
| `/dl env` | dispatch | Day/weather + per-element obi math |
| `/dl triggers reload\|init\|path` | dispatch | Trigger-file management |
| `/dl scan` / `preview` / `stage` / `commit` | gearimport | Gear import pipeline |
| `/dl fix` | gearimport | Backfill catalog metadata (Type/OneHanded/**RSlot**) into gear.lua |
| `/dl dedupe` | gearimport | Remove duplicate gear.lua entries |
| `/dl prune [commit]` / `prune why <item>` | gearimport | Remove/explain unowned entries |
| `/dl weight ...` / `best` / `mp` / `maxmp` | gearoptim | Stat-weight tools |
| `/dl set level main\|sub <n>` | utils | Level override for previews |
| `/dl dw` | utils | Dual Wield trait-bit probe |
| `/dl recalc` / `test` / `reload` (`r`) | utils | Rebuild sets / probe / reload LAC |
| `/dl gearcheck` | gearcheck | Trigger-gear availability audit |
| `/dl engine [native on\|off \| migrate]` | feature/engine | The Native-engine flip: status / flag + storage migration (see § The Native engine) |
| `/dlmv` | gearmove | (branch-only) gate/version diagnostic |

## Per-character state vs repo

Per-character, under `<install>\config\addons\luashitacast\<Char>_<ServerId>\`
(Henrik's is `Mindie_29909`), never in git:

| File | Owner | Purpose |
|---|---|---|
| `dlac\utils.lua`, `dlac\dispatch.lua`, `dlac\chatfmt.lua`, `dlac\profiles.lua` | dlac.lua (refreshed every load) | profile-side runtime |
| `dlac\gear.lua` | seeded once, then auto-sync/commit | owned gear |
| `dlac\gear_staging.lua` | gearimport | transient import staging |
| `dlac\profile.lua` | profiles (`/dl profile use`) | active-profile pointer |
| `dlac\profiles\<Name>\sets\<JOB>.lua` | setmanager (Sets tab) | committed dynamic sets |
| `dlac\profiles\<Name>\triggers\<JOB>.lua` | triggersui/dispatch | trigger rules |
| `dlac\triggers\<JOB>.lua` | (legacy, read-only fallback) | pre-profile trigger rules |
| `dlac\autogear.lua` | automationsui | automations manifest |
| `dlac\blueprints.lua` | triggersui (Blueprints section) | per-character Blueprint library (reusable trigger rules; outside Profiles, addon-state only — the engine never reads it) |
| `dlac\ammostate.lua` | ammowatch (Automations > AutoAmmo) | AutoAmmo config (persisted `enabled`, jobs map, the priority list) — the engine reads it per second |
| `dlac\modestate.lua` | dispatch | mode/lock/VERSION mirror |
| `dlac\uiflags.lua` | gearui | debug/autosync flags |
| `dlac\gearweights.lua` | gearoptim | stat weights |
| `dlac\augdump.txt` | augments | shareable augment dump |
| `<JOB>.lua` | Setup / `/dl profile migrate` (shim only) | the LAC profile — ALWAYS the clean managed shim after Setup (THE STANDARD: old logic never stays live); `.flbak` siblings are relics of the dead convert-in-place era |
| `backups\` | setmanager/gearimport | rotated backups |
| `backups\pre-profiles\` | profiles.migrate (first backup written ONCE, never overwritten; re-migrations add stamped `<JOB>-<stamp>.lua` copies) | pre-migration originals; "Copy from static" + Groups "Scan my Lua" read from here forever |

The old pre-dlac profile code lives at `<char>\ffxi-lac\` (reference only — the origin of
the "builder is a plan" pairing semantics).

## The Native engine (feature/native-engine)

dlac absorbing LuaAshitacast: the addon equips gear itself — LAC becomes
optional, then removable. **This is the end-goal, not an experiment — ADR 0015
(native-first) is the standing direction: new features target this pipeline,
legacy LAC mode is a sunset with a four-phase migration plan (recruit → merge →
nudge → delete).** Behind the **Engine flag**
(`config\addons\dlac\engine.lua`, `return { native = true }`; broken file
reads OFF). Flag off = byte-identical legacy behavior, pinned by the whole
test suite.

### The module trio

| Module | Role |
|---|---|
| `gear/equipcore.lua` | PURE equip pipeline: entry normalization (LAC `MakeItemTable` parity), the set resolver against an injectable snapshot (worn-view reserve semantics, first-fit bag scan, job/level/slot-bit/bag/augment gates, priority order, conflict unequips), 0x050/0x051 byte builders. Tests EQC*. |
| `feature/equipengine.lua` | The TIMING SERVICE (LAC packethandlers port): block outgoing 0x01A/0x037 → fire Precast → re-inject → fire Midcast; completion timers (LAC formulas + defaults); incoming 0x028 completion/interrupt + pet stream (fires `PetAction` at action START); 0x1B encumbrance; resend dedup; the coexistence TRIPWIRE. Pure half tested EQE*. `ACTION_ROUTES` is the dispatch-point table — **a future dispatch point is one new row (or one `fireEvent` call site); trigger files just carry the new handler name.** |
| `feature/nativedata.lua` | LAC-parity gData providers for the addon state (player/action/pet/environment/equipment/augment; vanatime+weather sig-scans). Installed as the gData shim by dlac.lua — the old zero-stub is now the fallback. |

`dispatch.lua` (v111) is the same engine in both worlds: `engineActive()` =
LAC state, or the native-armed addon state. One equip seam
(`engineEquipSet`) routes resolved sets to `gFunc.EquipSet` or the
equipengine buffer. `M._nativeSets` is the `gProfile.Sets` equivalent —
the tick's native identity latch installs the active profile's job sets on
job/profile change and `utils.rebuildSets` re-flattens on the shim's own
cadence. LAC-BRIDGE machinery stays `inLac()`-pinned: self-swap, seeding,
handoff/request files, the HandleEquipEvent wrap, lockstyle engine halves
(native lockstyle is the #80 addon-residency move's territory).

### Storage homes

`profiles.dataDir()` / `charRoot()` / `storageRoot()` / `charDataDirAt()`
are the ONLY path composers (statefile delegates; every module swept).
Legacy home: `config\addons\luashitacast\<char>\dlac\`. Native home:
`config\addons\dlac\<char>\` (no extra `dlac\` level; backups at
`<char>\backups\`; exports at `config\addons\dlac\dlac-exports\`, with the
legacy exports dir still READ so shared files never vanish). The flip
migrates by COPY — `profiles.engineMigrateStorage` (idempotent,
byte-verified, existing native files win) runs from `/dl engine native on`
and auto-runs per character on first login after the flip
(`engineAutoMigrate`, two file probes when settled). Legacy files never
move: flipping back finds everything where it was.

### The flip, and coexistence

```
/dl engine            status (mode, storage home, migration, tripwire)
/dl engine native on  migrate + flag; then /addon unload luashitacast + /addon reload dlac
/dl engine native off flag off; then /addon load luashitacast + /addon reload dlac
/dl engine migrate    re-run the storage copy by hand
```

Native mode requires LAC unloaded. equipengine refuses to arm inside LAC's
Lua state (NEB2), and the tripwire disarms interception for the session if
a foreign engine re-injects one of our fingerprinted action packets —
the failure mode of "forgot to unload LAC" is a loud chat line, not a
feedback loop.

### Native-mode gaps (deliberate, v1)

- **Lockstyle**: CLOSED (post-merge, #83) — the #80 executor
  (feature/lockstyleapply) is addon-resident, and in native mode every
  apply path (GUI button, town/OnLoad/keep-sub pumps via the queueCmd
  funnel, hand-typed `/dl ls apply`) routes to it directly. Only the
  `/dl debug ls` engine dry-run stays legacy-only (bridge diagnostics).
- **Trigger Monitor stream**: the `/dlacmonev` command-bus hop is inert
  natively (self-queued commands are never heard — the Ashita law); the
  monitor repopulates when the ring gains a direct native feed.
- **`/dl check` / `/dl debug`**: diagnose the two-state bridge, which
  native mode dissolves; they still print their addon halves. A
  native-aware readout wants its own field round.
- **Augment string pins** (`Augment = 'STR+5'` entries): the header pins
  (AugPath/AugRank/AugTrial) resolve natively; per-stat strings need the
  richer augment table wiring (`equipengine.augmentStringsOf`) — until
  then such pins never match, which is the SAFE direction (a wrong-augment
  piece is never equipped).
