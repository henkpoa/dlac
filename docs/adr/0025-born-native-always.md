# 0025 — Born native, always: legacy data is a migration source, never a verdict

2026-07-27, requested by Henrik (*"Make it so users start in native mode by default, regardless
if there are dlac files under luashitacast conf"*, following *"remove anything that points to
luashitacast now. Everyone have migrated"*). Addon `2026.07.27i`.

## Context

ADR 0015 ruling 4 made a fresh install born native but held one conservative clause: **legacy
evidence decides** — a flag-less boot that found dlac files under `config\addons\luashitacast\`
stayed legacy, because an existing LAC-era user must never be auto-flipped.

That clause has now hurt real users twice, both times on evidence **dlac wrote itself**:

- 2026-07-23 (Henrik's fresh-install sim): an undecided beat fell through to the legacy seeder,
  the login gear scan wrote `gear.lua` into the legacy home, and the next beat's scan read it
  back as "existing legacy user".
- 2026-07-27 (Xvs's clean reinstall — both config trees deleted): the same pathology one door
  further down. `maintainStorage`'s hold covered its own writers, but `profiles.dataDir` kept
  composing the legacy home during the undecided window, the gear scan planted `gear.lua` there,
  and the fresh box was offered "migrate to native" again.

Each fix narrowed the window; the clause itself kept the trap armed. Meanwhile the population it
protects has emptied — everyone has migrated — and the native era is the standing direction
(ADR 0015, the LuaShitacast purge ruling). The scan also carried its own failure mode: in-game
`ashita.fs.get_dir` returns nil for a missing directory, so a listing hiccup meant "can't tell",
and "can't tell" meant an inert, undecided boot.

## Decision

1. **No flag → native. Always.** `firstRunAction('absent', *)` returns `'write-native'`
   unconditionally; the `legacyPresent` argument is accepted but no longer decides anything.
   A flag already on disk is still honored exactly as before (`'respect'`) — `/dl engine native
   off` remains the explicit, and now only, road to legacy.
2. **The boot no longer scans.** `firstRunInit` skips `legacyDataPresent()` entirely; the
   "listing unavailable → undecided" limbo is unreachable by construction. The only undecided
   state left is a failed flag *write*, which warns once and retries each beat with all storage
   writers held (the 07-23 hold plus dataDir's own, both unchanged).
3. **Legacy data is a migration source.** A flag-less user with real luashitacast-era data is
   born native and `engineAutoMigrate` copies that data into the native home on the first native
   login — copy only, legacy files stay put, same machinery every migrated user already rode.
   `legacyDataPresent` keeps existing for migrate-era surfaces until the purge decides its fate.

## Consequences

- A fresh or wiped install can no longer be sentenced to legacy by anything on disk short of an
  explicit flag file. The two manufactured-evidence bugs lose their trigger at the root.
- The unstated ADR 0015 clause "an existing user is NEVER auto-flipped" is superseded for
  flag-less users: they are flipped, with their data carried over. Explicitly flagged users are
  still never touched.
- Tests: NO5 flips to the new law; NO47 pins the instant, silent, scan-free resolution of the old
  can't-tell world; NO49 pins that evidence alone no longer decides and an explicit legacy flag is
  respected; NO50b's legacy reopen now rides the flag, the only legacy route left.
