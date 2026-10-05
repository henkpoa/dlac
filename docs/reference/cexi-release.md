# Public CatsEyeXI ZIP

The CEXI distribution is built from the shared codebase, without a second public
development branch. The ZIP contains only the CEXI pack and selects it automatically.
Neither live installation nor its character settings are changed by a build.

Run from the repository root with Python 3 and Lua 5.4:

```sh
python tests/cexi_release_test.py
python release/build_cexi.py --ref HEAD --output dist/dlac-cexi.zip
```

The builder reads committed Git blobs, never dirty working files. The named output
must not already exist. It writes a ZIP rooted at `dlac/`, a SHA-256 sidecar, and
an embedded `RELEASE.json` with the source commit and every payload file's hash.
Fixed entry order and timestamps make repeated builds reproducible with the same
builder, source revision and compression runtime.

The **CEXI release ZIP** GitHub Actions workflow tests and builds on pull requests,
main pushes, and manual dispatch. Its artifact contains the distributable ZIP and
checksum. It does not create or publish a GitHub Release. For public distribution,
attach the verified ZIP to a release; GitHub's automatic source archive is **not**
the CEXI package.

## Public feature boundary

- Omit the E-Box Restock UI, planner and diagnostic module.
- Replace the E-Box client with a passive proximity reader using `lib/entwatch`.
  Giftbox's Crystal Warrior place gate continues to work; there are no storage
  requests, withdrawals or protocol listeners in this replacement.
- Remove E-Box from the CEXI manifest and retain an inert module entry point so an
  older `modules.lua` override cannot register Restock.
- Omit `feature/synthrun.lua` and its eager load. Remove Last Synth, repeat-count,
  wait and stop controls from the packaged craft bar. Crafting equipment, goals,
  skills and passive last-recipe information remain. The game's own typed commands
  are untouched.
- Refuse any source tree containing the private auto-acc or storage-move modules.
- Exclude other server packs, maintainer tools, probes, tests, config and Git metadata.
  Runtime assets and vendored BLU icons/licenses remain included.

The shared source is unchanged by this projection. It still contains the original
implementations; this is a distribution boundary, not a claim that previously
public source has become secret. The existing local-only `hidden-features` branch
in the CatsEyeXI checkout already preserves Restock and synth repeats together with
auto-acc and storage move. It predates the server-pack refactor; this packaging work
does not merge, rebase, push or otherwise change that private branch.

The projection checks each source boundary and fails if that layout changes; update
the builder and its extracted-package tests together. The tests verify the ZIP's
file list and hashes, parse all shipped Lua, mount and lint the real CEXI pack, draw
the craft bar while clicking its controls, and exercise Giftbox's near/far gates.

## Installation

Unload DLAC, back up and **replace** `Ashita/addons/dlac` with the ZIP's `dlac`
folder, then load DLAC. Do not overlay an old addon folder: obsolete files would
remain. Keep `config/addons/dlac` and `config/addons/luashitacast` intact. The ZIP's
README includes these instructions.
