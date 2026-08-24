# dlac is server-agnostic; server truth lives in server packs

**Supersedes ADR 0001 (dlac is CatsEyeXI-only).**

## Decision

dlac targets FFXI private servers, plural. Everything true of *a particular
server* — its item catalog and generated reference data, its capability set
(custom protocols, game modes, prestige, venture economies), its constants
(level cap, formula multipliers, field-calibrated thresholds), and its curated
item tables — lives in a **server pack**: `servers/<id>/` with a `manifest.lua`
at its root. Core code never assumes a server; it asks the one seam,
`gear\serverpack.lua`:

- `serverpack.active()` / `name()` — the active pack's identity
- `serverpack.maxLevel()` — the level cap (75 when no pack says otherwise)
- `serverpack.cap('<capability>')` — false unless the manifest declares it
- `serverpack.const('<key>')` — nil unless the manifest carries it
- `serverpack.data('<file>')` / the virtual `dlac\data\<file>` namespace
- `serverpack.provide()` / `service()` — the door a pack MODULE registers a
  live provider through (game-mode detection, prestige state), so core can ask
  a question whose answer only that server's module knows

**A capability the active pack does not declare does not exist.** The failure
mode of a missing pack, file, or capability is the addon's standing failure
mode everywhere: degrade soft, gate closed, say so in `/dl check` — never
guess, never crash.

## The virtual data namespace

`dlac\data\<file>` stays the require vocabulary the whole codebase (and the
test suite) already speaks, but no `data\` directory exists on disk: at boot,
`serverpack.init()` mounts one `package.preload` entry per file the active
manifest lists, resolving to `servers/<id>/data/<file>.lua`. Swapping the
active pack swaps what every existing `pcall(require, 'dlac\\data\\X')`
returns, with zero churn at the ~24 call sites. ADR 0001's one portability
concession — "server-specific data stays in swappable generated data files
with a documented shape" — becomes the load path itself.

Three files historically under `data\` are CODE, not server data, and move
out rather than into a pack: `gear\levelstats.lua` (the stats-at-level
resolver), `gear\nativemp.lua` (the MP formula — its server-tuned multipliers
come from `serverpack.const`), `gear\statdefs.lua` (stat presentation; unknown
keys already degrade to Misc, so one shared registry serves every pack).

## One install, one server

An install with exactly one pack under `servers/` needs no configuration —
that pack is active. With several packs, the per-install flag file
`config\addons\dlac\server.lua` (`return { server = '<id>' }` — the engine-flag
pattern, ADR 0015 lineage) chooses; absent a choice, the first pack in
`servers/index.lua` wins loudly. There is no login-time server detection: the
pack IS the declaration, and `/dl check` reports which one is live.

## What this buys

CatsEyeXI-only subsystems (the 0x1A4 protocol family, game modes, prestige,
ventures, gift boxes) become modules of `servers/cexi/`, mounted only when that
pack is active — on any other server they are not gated off, they are *not
there*. A second server is a generated pack plus, where its mechanics need
code, its own modules — CEXI's approval relationship, vocabulary and data are
untouched by another pack existing. The Vanaheim pack is the first proof.

## What does not change

- The scrape tooling that produces the CEXI pack stays untracked (that was
  the `.gitignore`'s secret; the data was always public).
- The catalog contract (`gear\catalogindex.lua`'s one walk, the 16 promoted
  fields) is unchanged — it is what a pack's `catalog.lua` must satisfy, now
  written down in `docs/reference/server-pack-contract.md`.
- The Job helper module system (ADR 0028) is untouched; server-pack modules
  reuse its containment discipline but are a different kind: mounted by pack,
  not by job.
