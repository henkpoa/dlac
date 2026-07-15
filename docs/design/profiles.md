# Profiles — the dlac storage layer (v33)

**Status:** landed 2026-07-13 (engine v33). Henrik's brother's idea: "different
profiles with different sets", which also answers import/export and the
"new players should never touch legacy files" goal in one move.

## The idea

A **profile** is a named bundle of dlac-owned per-job data; one job's slice of
it (the files sharing one `<JOB>` name) is a **job entry**:

```
<char>\dlac\profile.lua                          active-profile pointer (return { active = 'Default' })
<char>\dlac\profiles\<Name>\sets\<JOB>.lua       committed Dynamic sets
<char>\dlac\profiles\<Name>\triggers\<JOB>.lua   trigger rules
<char>\dlac\profiles\<Name>\lockstyles\<JOB>.lua lockstyle boxes (engine v41; falls back to the v40 per-profile lockstyles.lua, then the pre-profile dlac\lockstyles.lua)
```

LuaAshitacast keeps auto-loading `<JOB>.lua` on every job change — we ride that,
never fight it. The job file is (or becomes) a thin **shim** with zero data; the
engine resolves *active profile + current job* and installs the right sets into
the freshly loaded `gProfile` (dispatch's profile auto-install, the factored
`/dl sets reload` hot-swap). **The profile picks the folder; the job picks the
file inside it.** Switching profiles (`/dl profile use <Name>`) rewrites the
pointer, reinstalls sets, reloads triggers — no LAC reload.

## The one compatibility rule

* **READS fall back per file:** profile path first, else the legacy location
  (`sets.Dynamic` inside `<JOB>.lua`; `dlac\triggers\<JOB>.lua`). An unmigrated
  character behaves exactly as before — the auto-install only fires for jobs
  that HAVE a profile sets file.
* **WRITES always land in profile storage.** The first Commit for a job creates
  the profile sets file by importing the job file's whole Dynamic block
  verbatim (sets never split across two sources), then says so in the status
  line. dlac never writes a `<JOB>.lua` again — except the one-time migration.

The profile sets file keeps the exact `sets = { Dynamic = {...} }` shape the job
files used, so setmanager's field-proven brace scanners (`spliceSet`,
`deleteSetText`) work on it **unchanged** (pinned by tests Y19–Y22).

## Migration (`/dl profile migrate`, then `... migrate go`)

Per `<JOB>.lua` found (all 22 abbrs probed), in this order, each step verified
before the next:

1. **Backup first, loudly.** Original copied to `backups\pre-profiles\<JOB>.lua`
   and read back byte-identical before anything else happens. An existing
   backup means the file is SKIPPED entirely — the first backup is the
   pre-profiles truth and is never overwritten.
2. **Dynamic block moves verbatim** (byte-for-byte textual extraction, tests
   Y8–Y15) into `profiles\Default\sets\<JOB>.lua`. An existing profile sets
   file is never imported over.
3. **Triggers move** (copy → verify → backup copy → remove legacy).
4. **The job file is rewritten as the clean shim** — last, so any earlier
   failure leaves the original fully in charge. Then LAC is reloaded.

Dry run is the default: `/dl profile migrate` prints the full per-file plan and
touches nothing; only `migrate go` executes. Every action is printed per file.

**Statics stay reachable forever:** the Sets tab's "Copy from static" reads
non-Dynamic sets from the live job file AND from `backups\pre-profiles\`
(profilesets merges both, live file wins name collisions). Clean files, old
statics still one click away.

## Veterans (heavy hand-written LUAs)

Nothing changes in their execution model: their handler code runs first,
`utils.dispatch(...)` overlays last per slot. Profiles only change where dlac
reads/writes ITS data — and remove the scariest thing dlac did to them
(setmanager's text surgery on their hand-tuned file). Their file becomes
read-only to us unless they opt into migration.

One new hazard, guarded: a profile dynamic set whose name collides with a
file-authored static gets silently shadowed by the flatten (full replace, NOT a
per-slot merge — `BuildDynamicSets` builds into a fresh table, `utils.lua`
`sets[setName] = currentSet`). The engine warns once per profile load
(`warnShadowedStatics`). The right fix for a sparse set is seeding via "Copy
from static", not runtime merging — merge semantics were considered and
rejected (spooky resurrection of static picks; nothing left to merge against
after the first flatten).

## Commands

```
/dl profile                 status: active name, this job's sources, profiles on disk
/dl profile use <name>      switch (creates empty storage if new) — hot, no LAC reload
/dl profile new <name>      create empty storage, don't switch
/dl profile clone <name>    copy the ACTIVE profile's files to a new name (export/import primitive)
/dl profile migrate [go]    dry-run plan / execute the one-time migration
```

Import/export = copy a `profiles\<Name>\` folder (gear refs are catalog-based,
not character-specific); `/dl profile use` makes a hand-dropped folder live.

## State-plumbing notes (the parts that bite)

* `profiles.lua` is **seeded into `<char>\dlac\`** by dlac.lua like
  utils/dispatch — the LAC state requires it from there. Forgetting the seed
  list = `_pok` false = silent legacy behavior (by design, but confusing).
* The active pointer is read **throttled at 1/sec** (lock-mirror pattern)
  because the other Lua state can rewrite it at any time.
* GUI trigger path (`triggersui.trigFilePath`) and engine trigger path
  (`dispatch.triggersPath`) implement the SAME resolution rule on purpose; if
  they ever diverge, the GUI edits one file while the engine reads another.
* Tests Y1–Y33 in `tests\run_tests.lua`; everything fs-touching is call-time +
  pcall so the module loads headless.

## The Profiles menu (browser + cross-character import)

Top-left `Profiles` button in the GUI: a snapshot tree of **character >
profile > jobs** across the whole install (every `<Name>_<ServerId>` folder
under `config\addons\luashitacast\` -- that folder IS the account/character
axis; there is no separate account level on disk). Current character sorts
first and defaults open; rows show `[active]` / `use` / `clone` on your own
profiles and `import` on other characters' -- import copies the per-job files
into THIS character under a new name (deterministic 22-job probe, never
overwrites, refuses a name that already has files). Snapshot builds on
open/Refresh only; directory listing = `ashita.fs.get_dir` with a
`dir /b /ad` popen fallback (`profiles.listDirs`).

### Menu actions (final v1 shape)

Header: centered `PROFILES`, Refresh pinned right. Profile rows: `use` /
`[active]`, `clone` (form: destination character + profile name), `rename`
(own char; repoints the active pointer), `delete` (never offered on the live
one). Job rows: `clone`, `rename` (sets+triggers move together; renaming away
from a job abbr = dormant backup slot, renaming back revives it), `delete`.
Every destructive form states exactly what happens behind a red DELETE
PERMANENTLY button, and deletion always writes verified safety copies first
(`backups\deleted-profiles\<prof>-<stamp>\`, `backups\deleted-jobs\`) -- the
"never delete backups" house rule applies to the deleter itself. Actions that
touch the CURRENT character's ACTIVE profile ping `/dl sets reload` +
`/dl triggers reload` so the engine follows instantly (the two-rename
swap-from-backup workflow needs no manual reload).

### Per-job export / import (friend sharing)

One file = one job's dlac data. `export` on a job row writes
`config\addons\luashitacast\dlac-exports\<Job>-<Profile>-<Char>-<stamp>.lua`
-- a plain `return {...}` with the sets/triggers file texts %q-embedded
verbatim (round trip pinned byte-exact, tests Y43-Y51). Send the file; the
friend drops it into THEIR dlac-exports\ and the menu's "Shared exports"
section lists it with an `import` button -- destination character / profile /
name form, collision-gated, payloads parse-checked before anything is
written, never overwrites. Missing gear on the importer's side is already
handled by the missing-gear-safe loader: ladders degrade to what they own and
self-heal as they scan new gear.
