# 0015 — Native-first: LAC independence is the end-goal; legacy is a sunset, not a sibling

2026-07-23. Henrik's four rulings, verbatim intent, issued the evening the Native engine
survived its first field rounds (dispatch v111–v119 on `feature/native-engine`). Follows
the Addendum-2 independence ruling on issue #80 (this branch is THE development branch;
main is frozen as the stable fallback until graduation). Companions: ADR 0014 (lockstyle
addon-resident) — whose "never cross the bus" law native mode satisfies by construction —
and architecture.md § The Native engine.

## The four rulings

1. **Legacy must work — but not for however long. We push hard to migrate.**
   LAC mode (Engine flag off) stays byte-identical and field-usable, but it is a
   SUNSET, not a co-equal mode. There is no commitment to indefinite dual-engine
   maintenance; the support window ends when the roster of real users is native
   (Henrik's circle is small and known — this is a migration of people, not a
   deprecation policy for strangers).

2. **All new features are developed for the native client. LAC is no longer a design
   input.** The old posture ("engine-native over commands", designing within LAC's
   handler contract) inverts: a new feature targets the native pipeline and MAY be
   native-only from birth. Legacy mode receives fixes, not features. A feature that
   would need bridge machinery (files, request rides, twin implementations) to work
   in legacy mode is the signal that it should not try.

3. **dlac never touches players' `<JOB>.lua` files again — but keeps READING them.**
   Native mode writes nothing into LuaAshitacast's world: no shims, no job-file
   rewrites, no seeded copies, no migration edits. The job files remain what they
   always were to their owners — THEIR files — and dlac's relationship to them is
   read-only forever: the Groups "Scan my Lua" import, the statics "Copy from"
   sources, and any future table imports keep reading job files and the existing
   `backups\pre-profiles\` corpus. Consequence: the elaborate backup choreography
   (first-backup-never-overwritten, re-shim stamped copies) loses its reason to
   grow — what is never written needs no backup. Existing backups stay readable
   import sources; native flows create no new ones.

4. **New users are native by default.** A fresh install (no legacy dlac data, no
   Engine flag) boots native without ceremony: the flag file is written
   `native = true` on first run, storage is born in `config\addons\dlac\`, and no
   LuaAshitacast tree is ever created for them. If LuaAshitacast is detected alive,
   dlac ASKS the player to turn it off (`/addon unload luashitacast`) — the
   coexistence tripwire remains the hard backstop, but the polite ask comes first.

## Consequences

- **The two-state architecture is legacy-scoped.** Everything that exists to bridge
  two Lua states — seeding + the 5s watch, the content-keyed self-swap, the VERSION
  handshake + Reload-LAC button, modestate file polling, debug handoff/request
  files, the `/dl check`+`/dl debug` bridge halves, ADR 0002's "the engine must not
  require addon modules" constraint and the oracle's parity-pinned engine twins —
  is deletion-scheduled with legacy mode, not maintained into the future.
- **ADR 0002/0014's laws survive in native trivially**: one state, direct calls.
  The dispatch engine itself survives unchanged — it was always ours; only its
  host changes.
- **Field confirms happen on the dev branch.** Main receives nothing until
  graduation.

## The migration plan (the merge-with-main path)

**Phase A — now (the dev branch).** Field rounds on `feature/native-engine` until
the native pipeline is boringly stable for Henrik's daily play: casting, WS, items,
ranged, pet, lockstyle (all apply paths addon-resident post-#83 wiring), maxmp
(boot saga closed v119, confirmed). New features land here, native-first (#83/#84
already retargeted).

**Phase B — recruit the roster.** The known users flip: `/dl engine native on`,
unload LAC, play. Their finds are field rounds; the copy-only migration means any
of them can retreat instantly. Exit criterion for the phase: every active user
native, no legacy-only regressions open.

**Phase C — graduation (the merge).** `feature/native-engine` → main; main's
freeze ends. Legacy mode ships one last time as the flag-off fallback, formally
sunset: a legacy-mode session shows a migration nudge (GUI banner — chat stays
quiet per the house rule). New-user onboarding defaults native (ruling 4
implemented by then: first-run flag write + LAC-alive ask). **DONE EARLY
(2026-07-23, issue #87):** ruling 4 and ruling 3's Setup consequence are
implemented on this branch now — `profiles.firstRunInit`/`firstRunAction`
(fresh installs write `native = true`, existing users never auto-flipped),
`profiles.shouldAskUnloadLac` (the once-per-session LAC-alive ask, tripwire still
the backstop), and `setupui.setupNative` (Setup produces a playable install
writing zero `<JOB>.lua`/shim/backup). Job-file imports stay read-only in both
modes. Tests NO1–NO19; architecture.md § The Native engine → Onboarding. The
Phase-C migration nudge banner (a legacy-mode concern) is still tracked below.

**Phase D — the deletion party.** After a sunset window with zero legacy users:
delete the bridge machinery (the list above), collapse the oracle twins to one
door, retire the `inLac()` legacy paths, drop the legacy storage-home fallbacks,
and let `/dl check`/`/dl debug` be rebuilt native-simple. The codebase after this
is the payoff the absorption was priced against.

**Open question (Henrik's call, not blocking):** the name. "dynamic LuaAshitacast"
outlives LuaAshitacast at Phase D; whether dlac keeps its name as a fossil or takes
a new one is a branding decision for graduation day.

## Follow-up work items (tracked, not yet built)

- ~~Ruling 4 implementation: first-run native default (write the flag when no legacy
  data and no flag exist) + LAC-alive detection (modestate `__loadstamp` freshness)
  with the polite ask; Setup flow grows a native path that never writes `<JOB>.lua`
  (storage + starter files only, shim migration becomes legacy-mode-only UI).~~
  **DONE 2026-07-23 (issue #87).** LAC-alive detection landed as the equipengine
  tripwire plus legacy-home modestate freshness (`dlac.lua` `lacAlive()`); the
  first-run decision + Setup native path are the pure `profiles.firstRun*` seams
  and `setupui.setupNative`.
- Legacy-mode migration nudge (Phase C banner in gearui).
- The Trigger Monitor's native feed (the `/dlacmonev` bus hop is legacy-only).
- Augment-string pins natively (`equipengine.augmentStringsOf` wiring).
- Persisting the maxmp measured tick + full-pool offset (the standing offer —
  erases the last per-session warm-up).

## Addendum (2026-07-23, issue #91) -- Onboarding v2: ruling 4 refined to ZERO ceremony; Setup = the migration wizard

Henrik's ruling the same evening #87 landed: **Setup exists for exactly ONE reason
now -- migrating a current legacy dlac user to native. New players get the native
engine automatically, with zero ceremony.** This refines ruling 4 (and finishes
ruling 3's Setup consequence) and implements the Phase-C migration nudge banner
early, on this branch.

1. **Fresh installs: full auto-setup, no Setup interaction ever.** #87 made a fresh
   install *boot* native (flag auto-written). This removes the remaining ceremony:
   when native mode is on and the character+job's baseline is missing, dlac creates
   it **automatically** at the login/job beat -- storage, gear inventory, the four
   base sets, starter triggers (the `setupNative` content, per job, idempotent,
   never clobbering) -- fully SILENTLY (Henrik, post-field-confirm: no first-run/engine/scan talk -- gear auto-syncs from bags; only a FAILURE names itself, once).
   No red Migrate button, no plan popup, no Commit for new users, ever. A later login
   on a NEW job auto-seeds that job's starters the same way. Auto-setup NEVER fires
   in legacy mode, never before `firstRunInit` has resolved, and never for a
   not-ready job (id-0 `NON` at login -- hard rule 11); a persistent failure (disk
   error) surfaces as a status/chat line and retries next beat -- it is never
   ceremonialized. The LAC-alive polite ask (ruling 4) is unchanged. Seam:
   `setupui.autoSetupNative` (+ `nativeBaselineComplete`), driven from `dlac.lua`
   `maintainStorage`.

2. **The Setup button + popup become THE migration box**, shown for exactly one
   reason: a legacy-mode session with existing dlac data. For that user the red
   Setup button is the standing nudge (present all session until they migrate), and
   the popup is a three-part migration box (what you should do / what Commit will do
   / why) plus the hard rule, verbatim-clear: **"It's either LAC or DLAC -- never
   both at once. Once migrated, do NOT run LuaAshitacast."** Commit is the GUI twin
   of `/dl engine native on`: `engineMigrateStorage` (COPY-ONLY -- nothing under
   `luashitacast\` is moved, changed, or deleted; flip back any time with
   `/dl engine native off`) + `setNativeMode(true)`, then the unload/reload
   checklist. Seam: `setupui.migrateToNative`. The legacy clean-shim / ffxilac
   Setup plans retire from the UI (the underlying writers -- `migrateToCleanProfiles`,
   `migrateCurrentJob`, `setupNative` -- stay in the code for Phase D and as the
   auto-setup content source). The in-window warning banner rewords from
   "X.lua is NOT set up for dlac" to the migration nudge.

3. **`needsSetup` v2:** native -> always false (auto-setup owns it); legacy with
   dlac data -> true ("migration offered"). Fresh installs never see the button --
   they are native before the first frame ends. Tests NO20-NO42.
