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

ui/        imgui modules: gearui, triggersui, equippedui, profilesmenu, setupui,
           weightsui, craftbar, uistyle, uihost, itemicons, filetex, floatgear
data/      generated / static tables: catalog, crafts, spells, abilities, statdefs,
           levelscaling, levelstats
gear/      the gear pipeline: gearoptim, gearimport, gearexport, gearcheck, gearfmt,
           setmanager, profilesets, ownedcache, syncflags
feature/   self-contained features: lockstyle, macrobook, useitem, craftwatch, augments,
           pinwatch
lib/       generic helpers: cmdqueue
assets/    PNGs (loaded by absolute path via AshitaCore:GetInstallPath — not by module path)
docs/  tests/  tools/
```

Module names carry the folder: `require('dlac\\ui\\gearui')` → `addons\dlac\ui\gearui.lua`,
because the `package.path` shim substitutes the whole name into `addons\?.lua`.

Two traps when moving files or grepping module names:

1. **`dlac\X` is not always a module.** The same prefix names *per-character data files* under
   `<char>\dlac\` — `dlac\triggers`, `dlac\modestate`, `dlac\lockstyles`, `dlac\macrobooks`,
   `dlac\craftstate`, `dlac\gearweights`, `dlac\profiles\<name>\`. Those are user state and must
   never be folder-qualified. Note the near-misses: the `lockstyle` **module** vs the
   `lockstyles` **data file**; `macrobook` vs `macrobooks`; `crafts` vs `craftstate`.
2. **The engine five cannot move.** See below.

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
`feature\useitem`, `feature\craftwatch`, `ui\craftbar`, `feature\lockstyle`, `ui\gearui`;
everything else (`utils`, `dispatch`, `gear\setmanager`, `ui\triggersui`,
`gear\profilesets`, `gear\gearcheck`) loads transitively. That list is built by string
concat (`'dlac\\' .. mod`), so a grep for a literal `require('dlac\\gearexport')` finds
nothing — the loop is the only loader for some modules.
**Writes** `<char>\dlac\{utils,dispatch,chatfmt,profiles}.lua` every load (always flat —
see Repository layout); seeds `<char>\dlac\gear.lua` only if absent.

### utils.lua — profile-side rebuild engine
The single `require` a migrated profile needs. Re-exports the gear inventory and the
dispatch entry point, and owns the level-scaling **Dynamic-set rebuild** engine plus the
dual-wield / sub-slot pairing rules. Refreshed into every character's `dlac\` folder on
each addon load.
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
Reads/writes `<char>\dlac\triggers\<JOB>.lua`; reads `<char>\dlac\autogear.lua`; writes
`<char>\dlac\modestate.lua`.

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
(`jobSetupState` + convert-in-place `migrateCurrentJob` + starter profile/trigger
seeding; `setup.configure{}` deps), **syncflags.lua** (auto-sync loop + uiflags.lua
persistence; owns `sf.flags.debug`/`sf.flags.autosync`; gearui's d3d_present calls
`sf.loadUiFlags` BEFORE `sf.tick` — order is load-bearing, the real gear.lua must swap
in before the first sync), **weightsui.lua** (stat-weights editor; scoring stays in
gearui), **profilesmenu.lua** (the Profiles popup tree + forms; state in the shared ui
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

### ui/triggersui.lua — Triggers tab
GUI editor for the dispatch engine's data: rules per handler, mode toggle buttons, and
the Automations manifest builder. Split out of gearui for the 200-local cap. Commit
rewrites the trigger file via `dispatch.serializeTriggers` and pings the engine to
hot-reload. Writes `<char>\dlac\triggers\<JOB>.lua` and `<char>\dlac\autogear.lua`.

### gear/profilesets.lua — profile `sets` reader
Reads the loaded profile's `sets` table for the Sets tab. In LAC state reads
`gProfile.Sets`; in addon state parses the current `<JOB>.lua` in a permissive sandbox.

### gear/setmanager.lua — `<JOB>.lua` reader/writer
Splices dynamic sets into `<JOB>.lua` and analyzes/repairs the dispatch handler shims —
the write side of both Sets-tab Commit and the Setup button. Pure-text core
(`analyzeShims`, `repairShimsText` — comment-aware since 84de48a) with file wrappers
(`repairShims`, `commitSet`, `deleteSet`). All edits are backup + parse-checked, abort
untouched on failure. Writes rotated backups in `<char>\backups\`.

### gear/gearoptim.lua — stat-weight optimizer
Two read-only tools: MP-spent→potency swap advice, and a stat-weight scorer/best-set
builder (`M.score`, `M.buildBestSet`). Purely advisory — never equips. Reads/writes
`<char>\dlac\gearweights.lua`.

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
the Triggers-tab "usable now" browse lists (milestone M4). **Not yet required by any
module** — wiring is open issue #12. Generated by `tools/gen_pickerdb.py`. Known: ~40
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

### tools/ — maintainer scripts (gitignored, not shipped)
`apicrawl.py` builds catalog.lua; `gen_levelscaling.py` builds levelscaling.lua;
`gen_pickerdb.py` builds spells/abilities; `modifier_map.lua` = modid→stat map;
`api_cache/` holds the crawl cache + the stat-naming decision log
(`stats_decisions.txt` — the agreed mod→key bridge). Gitignored so scraping details and
the mod enum aren't published; only generated data ships.

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

## Data flow

- **catalog.lua** (shipped) — crawled base-truth stats; addon-state only (browse,
  tooltips, enrichment, optimizer). `enrichGearFromCatalog` fills statless owned entries
  by Id.
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
   Iridescence staff from autogear.lua (level-gated; ties go to the universal); AutoObi =
   elemental/universal obi only when the day/weather net is positive. Unresolvable →
   fallback; no fallback → drop the slot.
7. Per-slot attribution is recorded for `/dl why`.

## The `/dl` (= `/dlac`) command surface

Registered across six handlers; each blocks only its own subcommands.

| Command | Module | Does |
|---|---|---|
| `/dl ui [on\|off\|toggle]` | gearui | GUI window |
| `/dl sync` | gearui | Import new gear now |
| `/dl autosync [on\|off]` | gearui | Toggle on-job-change sync |
| `/dl debug [on\|off]` | gearui | Reveal dev header buttons |
| `/dl mode <name> [on\|off\|toggle\|<value>]` | dispatch | Flip a mode (no arg: list) |
| `/dl lock <slot\|all> [on\|off\|toggle]` | dispatch | Engine-owned slot locks |
| `/dl why` | dispatch | Last-dispatch trace, per-slot attribution |
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
| `dlac\autogear.lua` | triggersui | automations manifest |
| `dlac\modestate.lua` | dispatch | mode/lock/VERSION mirror |
| `dlac\uiflags.lua` | gearui | debug/autosync flags |
| `dlac\gearweights.lua` | gearoptim | stat weights |
| `dlac\augdump.txt` | augments | shareable augment dump |
| `<JOB>.lua` (+ `.flbak`) | Setup / `/dl profile migrate` (shim only) | the LAC profile (post-migration: a managed shim, never written again) |
| `backups\` | setmanager/gearimport | rotated backups |
| `backups\pre-profiles\` | profiles.migrate (written ONCE, never overwritten) | pre-migration originals; "Copy from static" reads statics from here forever |

The old pre-dlac profile code lives at `<char>\ffxi-lac\` (reference only — the origin of
the "builder is a plan" pairing semantics).
