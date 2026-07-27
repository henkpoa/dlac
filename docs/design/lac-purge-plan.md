# The LuaShitacast purge — staged deletion plan

2026-07-27, ruled by Henrik: *"I think we can remove anything that points to luashitacast now.
Everyone have migrated, we don't want anything to be pointing to that at all, unless looking into
the 'job lua files' for static imports and tables"* — refined the same day: *"we want to keep the
import from the job files, group (table) and static set import."*

Standing context: ADR 0015 (native-first, legacy = sunset fallback), ADR 0025 (born native,
always — the boot never scans legacy, an explicit flag is the only road to legacy), engine v130.
This plan executes the sunset.

## What SURVIVES (the keep-list, exact)

Old `<JOB>.lua` files are **data to import**, never an engine to serve. The surfaces that read
them as data stay, byte-for-byte in spirit:

| Keeper | Where | What it does |
| --- | --- | --- |
| Sandbox job-file reader | `gear\profilesets.lua` (`sandboxSets`) | Sets-tab data source: static sets listed from `<JOB>.lua` **and** `backups\pre-profiles\<JOB>.lua` — the "Copy from static works forever after a migration" promise |
| Static set import | `gear\setimport.lua` (`importStaticSet`) + gearui's static path (~:2680) | One static set → a dynamic set in the profile store |
| Group (table) import | `gear\setimport.lua` (`resolveNewSetNames`) + gearui's marked-sets flow (~:2826) | A marked GROUP of sets imported in one plan, rename-suffixed against collisions |
| Whole-block import at creation | `gear\setmanager.lua` (~:555) | A job's first profile sets file imports the job file's whole `Dynamic` block |
| Legacy path authority for the above | `profiles.charBase()` (+ `listCharFolders`) | The importers' pointer INTO `config\addons\luashitacast\` — reframed as "legacy data-source root", read-only |
| The GUI promise string | gearui ~:1566 | *"Your old job files and backups stay where they are and remain importable"* — stays true |

**Also kept (recommended, Henrik to confirm — open question 1):** `engineAutoMigrate` +
`/dl profile migrate` as *manual/first-login data carriers* (they READ the legacy tree to copy
data INTO the native home — that is import at the storage altitude). The coexistence **tripwire**
in equipengine also stays: it is protection against a foreign engine, cheap, and names LAC only
in its warning text.

## Inventory (grep sweep 2026-07-27, counts per file)

`luashitacast` (any case): tests 31, profiles 14, setupui 6, gearui 6, gearimport 5, engine 4,
dlac.lua 4, setmanager 3, gearoptim 3, dispatch 2, +12 files ×1.
`inLac(`: dispatch 16. `gProfile|gFunc`: dispatch 44, tests 35, lockstyle 4, profilesets 3, +7 files.
`Reload LAC` strings: dispatch 17, gearui 11, triggersui 10, +9 files. `/lac` commands: useitem 2,
gearui 2, equippedui 1, dispatch 1, smoke_ui 4. `gcinclude|ffxi-lac`: setupui 6, utils 2, +6 files ×1.
`shim`: tests 40, setupui 29, profiles 29, dispatch 15, setmanager 12, check 9.
Docs: architecture.md, HANDOFF.md, history.md, profiles.md, storage-move.md, trigger-system.md,
ADRs 0015/0025, + design notes.

## Phases

Each phase is one whole-or-not-at-all `dev` batch: both suites green, one field beat from Henrik,
then the Ready-to-merge queue (hard rule 14). Order matters — writers first, then the mode, then
the surfaces, then the words.

### Phase 1 — stop feeding LAC (the writers) — **EXECUTED 2026-07-27** (`2026.07.27j`, engine v131)

Landed as planned, with three judgment calls worth naming:
- **Setup writes NO job files in EITHER mode** (stronger than drafted): the Phase-1 law is
  "nothing writes under luashitacast\", and a flag-off user's Setup writing starters would
  break it. Storage + base sets + starter triggers are the whole setup now (NO19 re-pinned).
- **`M.migrate` leaves originals in place** (step 4, the shim rewrite, deleted): the old
  job file is inert data under the native engine, and leaving it untouched makes the
  keep-list promise stronger. The shim writer (`shimFileText`/`SHIM_BODY`/`BOOT_LINE`,
  `MIGRATE_BOOT`/`STARTER_PROFILE`) died; the recognizers (`SHIM_MARKER`, `isCleanShim`)
  stay for files already on disk.
- **check.lua got a comment-only touch**: the seeded-copies comparison still prints (frozen
  seeds = expected STALE noise, already known as #131) and dies wholesale in Phase 3.

Also extinct with the self-swap: the whole "`M.x = {}` at file scope is wiped by every
self-swap" hazard class — a plain require owns the module table now (X0 pins that a set
`__dlacEngineRoot` is ignored). Suites: 3857 + 584, both interpreters.

Nothing may CREATE or refresh LAC-era artifacts anymore. The luashitacast tree becomes read-only
territory (imports + migration reads only).

- `dlac.lua`: delete `seedCharFolder()` and its 5s watch half (utils/dispatch/chatfmt/profiles
  seeding + the gear.lua template seed). `maintainStorage` keeps only the native branch.
- `profiles.lua`: delete the shim writer (`SHIM_BODY`, `SHIM_MARKER` writes, `BOOT_LINE`) and
  `PROFILE_TEMPLATE.lua`; `setupui`'s `MIGRATE_BOOT` / shim-conversion machinery goes with it
  (Setup keeps only `autoSetupNative`).
- `dispatch.lua`: native-gate or delete `/dl profile migrate go`'s mixed-tree write (the known
  ungated hole from the limbo notes).
- Delete the LAC-alive polite ask (`lacAlive`, `shouldAskUnloadLac`) — the tripwire stays and its
  DISARMED line keeps naming the problem.
- Engine self-swap + reseed machinery (`dispatch.lua` SW block, content-keyed): it existed to
  carry a git pull into LuaAshitacast's running state; with seeding gone it watches nothing.
  Verify the native state never rides it (survey says it doesn't), then delete, tests SW* with it.

### Phase 2 — kill legacy MODE (the engine diet) — **EXECUTED 2026-07-27** (`2026.07.27k`, v132, -1063 lines)

As planned: `nativeMode()` constant true, the flag retired in place (readers/writer/
first-run machinery deleted), path authorities native-only, `inLac()` + the whole
gProfile/gFunc world out of dispatch (LAC engine path, gProfile installSets twin,
`readJobSets` + legacy sets fallback, `warnShadowedStatics`, the HandleEquipEvent wrap,
the LAC tick half, the request-file bridge, both lockstyle engine halves —
`lockstyleapply` owns native apply with its own byte-for-byte core). `/dl engine` is
status-only per Henrik's answers. End-to-end test rigs re-pointed at the NATIVE equip
door (equipengine stub, not `gFunc.EquipSet`).

The big one: there is one engine and it is native.

- `profiles.nativeMode()` → constant true; the engine flag file is retired (read-ignored, never
  written; `/dl engine native off` refuses with one line — open question 2). `dataDir`/`charRoot`
  lose their legacy branches; the ADR-0025 undecided hold and `firstRunInit`/`firstRunAction`
  collapse to "ensure the flag file exists" or vanish outright.
- `dispatch.lua`: `inLac()` sites (16) and the gProfile/gFunc world (44 refs) — delete the
  LAC-hosted engine paths: the gProfile branch of `installSets`, the LAC tick, the LAC-state
  command registration split, `engineActive()` → engine-armed only, `readJobSets()` +
  `readSetsSource`'s legacy fallback (the GUI importers own that road now; the engine reads
  profile sets files only).
- `feature\lockstyle` / `lockstyleapply`: drop the LAC-state pinning branches.
- `/lac` command emitters (useitem 2, gearui 2, equippedui 1): each is either already dead under
  native (the free-equip lesson: an emitter can be inert with no code change) or gets its native
  equivalent named; none may remain.
- Tests: the gProfile/gFunc simulation worlds (35 refs) shrink to importer coverage; the
  LAC-parity EQUIP SEMANTICS pins (equipcore EQC section) STAY — they define what the native
  engine equips, the name is history.

### Phase 3 — native-aware surfaces (#131 dies here) — **EXECUTED 2026-07-27** (`2026.07.27l`, v133, with Phase 4)

- `feature\check.lua` + `feature\debug.lua`: the addon half reads the NATIVE home (stamp, job
  state, request bridge); the "seeded copies" line is deleted with the seeds; the false alarms
  ("seeded STALE", "stamp BEHIND", "ENGINE HALF MISSING → Reload LAC") become impossible. Closes
  issue #131.
- `ui\gearui.lua` (11) / `ui\triggersui.lua` (10, incl. the banner pointing at the deleted
  "Reload LAC (top-right)" button) / menuui / priorityui / equippedui / arbwatch / macrobook:
  every "Reload LAC" string becomes `/dl reload` (which already reloads dlac, ad935d6) or
  disappears with its dead surface. gearui's `jobSetupState` reads native paths.
- `dlac.lua`: gear preload drops the legacy-home candidates (native home only — the importers,
  not the boot, read old trees); `addon.desc` loses "(for LuaAshitacast)".

### Phase 4 — keep-list hardening — **EXECUTED 2026-07-27** (same commit as Phase 3)

The allowlist guard (tests PRG1/PRG2) scans shipped files for the `\\luashitacast`
STRING-LITERAL form (comments use one backslash and never trip it); allowlist =
profiles.lua, gear/setmanager.lua, feature/lockstyle.lua, feature/macrobook.lua,
gear/gearoptim.lua. It caught three stragglers on its first run (statefile + gearui
fallbacks, a profilesmenu label). Every module-local legacy path FALLBACK died;
gearui's charBase delegates to profiles.charBase, the one sanctioned composer.
STILL OWED FROM THIS PHASE: the in-game field round importing all three ways
(static set, marked group, "Copy from static" from a pre-profiles backup).

- The importers get their own header block naming the contract: luashitacast paths appear ONLY in
  `profilesets.sandboxSets` sources, `setimport`, `setmanager`'s import half, `charBase`, and (if
  kept) the migrate carriers. A guard test greps the shipped tree and pins the allowlist, so a
  stray LAC reference can never creep back silently.
- Field round: import a static set, import a marked group, "Copy from static" from a
  pre-profiles backup — all three land on a purged build.

### Phase 5 — the words — **EXECUTED 2026-07-27 (first pass)**

dlac.lua's header says what dlac IS; HANDOFF's mental model + hard rule 4 rewritten;
architecture.md carries a purge banner marking its LAC-era sections as history (full
rewrite deliberately deferred — the banner is honest and cheap, the rewrite is not);
history.md carries the day. Historical changelog comments (dispatch's version notes,
ADRs) are KEPT verbatim by design: history is not a pointer.

- `docs/architecture.md` (two-state model → one-state), HANDOFF's mental model + hard rules that
  assume seeding/LAC, CONTEXT.md terms, history.md gets the purge entry. ADRs stay as history.
- Sweep the remaining ×1 files (statefile, entwatch, augments, gearexport, gearoptim, accwatch,
  macrobook…) — mostly comments; each either dies with its machinery or gets rewritten to name
  the native home.

## Open questions for Henrik

1. **The migrate carriers**: keep `engineAutoMigrate` + `/dl profile migrate` as manual importers
   for stragglers/old backups (recommended — they are reads that serve native), or purge them
   with Phase 2 and let the set importers be the only road in?
2. **`/dl engine` post-purge**: keep the command as a native-only status readout (recommended —
   it is the field discriminator we keep reaching for), with `native off` refusing loudly?
3. **The flag file**: retire in place (ignored, never deleted — recommended, zero-risk) or
   actively remove `engine.lua` from the native root on boot?

## Sizing

Phase 1 and 3 are each one focused session; Phase 2 is the big one (dispatch loses its second
personality — expect the largest diff since the native era began) and wants its own quiet day;
Phases 4-5 are small. Suggested order is as numbered — every phase leaves the addon shippable.
