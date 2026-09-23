# Catalog item artwork

Implemented in local DLAC `2026.09.14g` and the matching AscensionXI generator
change. The normal catalog build now includes icon generation automatically.
The earlier Rabbit Charm-only mapping and separate addon-side icon script are
superseded. New catalog items need no per-item icon patch or second build step.

## One generation command

From an AscensionXI source checkout containing the pipeline change:

```powershell
python tools/dlac-pack/gen_pack.py --out 'C:/AscensionXI/Ashita/addons/dlac/servers/ascensionxi' --game 'C:/AscensionXI/Game/FINAL FANTASY XI'
```

The generator uses enabled item SQL, catalog IDs and `client/dats/` from that
same checkout. The required base-client path supplies the comparison artwork.
`tools/dlac-pack/itemicons.py` emits a PNG for every icon with different RGBA
pixels; metadata-only differences do not emit redundant images. Unsupported
changed bitmap formats or corrupt/LFS-pointer input fail before the staged
build is copied into the target pack. Client DATs are opened read-only.

The generated pack contains all required data and artwork:

- `data/catalog.lua` and the other reference tables
- `manifest.lua`
- `itemicons.lua`
- `assets/items/<id>.png`

Commit and distribute the complete `servers/ascensionxi/` folder. The shared
icon service calls `filetex.packHandle` to load from that folder; there is no
second asset directory to copy. Ordinary item icons and missing assets retain
the client fallback. Other packs never use AscensionXI's mapping. Existing
hand-maintained modules, feature settings and detection files survive a build.

Artwork must exist in the server's authored DATs; a catalog cannot invent image
pixels. Updating those inputs and running the normal catalog command is enough.
The launcher release still follows its existing reviewed DLAC commit/pin process.
No launcher pin, server or client DAT was changed by this work.

## Verification

Server: `python -m unittest discover -s tools/dlac-pack -v` passes 11 tests.
The pipeline regression adds an arbitrary future catalog ID, runs the normal
command and confirms its map entry and PNG appear automatically. It also checks
changed artwork, deterministic regeneration, preserved hand-maintained files,
and refusal to publish a new catalog when artwork input is corrupt.

A full run from server main 221d0f8114 produced 15,419 equipment records and 26
icons. Zealot's Mitts +1 (26564) appeared in both automatically, demonstrating
coverage beyond the earlier 25-item snapshot. The generated files are applied
locally; the source generator lives in `C:/repos/ascensionxi-dlac-icons` pending
its PR. The older `C:/repos/ascensionxi` checkout was left intact.

DLAC checks: `lua tests/itemicons.lua`, `lua tests/custom_equipment.lua`,
`lua tests/pack_lint.lua ascensionxi`, and `lua tests/smoke_ui.lua`.
They cover all map entries and PNGs, the actual pack-relative texture path,
pack isolation, texture caching, equipment and set selection.

Use `/addon reload dlac` after receiving the complete release. `/dl repair`
is not required for artwork. Live rendering of this build remains pending.
Rollback restores the previous complete addon release; no player-data migration.

## September 23, 2026 pack refresh

Generated from AscensionXI main `8af39bbf5e` using its normal `gen_pack.py`
command and LFS-backed `client/dats/`, with the read-only base client at
`C:/AscensionXI/Game/FINAL FANTASY XI`. This supersedes the pending-generator
checkout described above: the generator and icon pipeline are now on server main.

The pack contains 15,434 equipment records and 39 icon overrides. All twelve
Forsaken/Rekindled weapons (19968-19979) have catalog records and bundled PNGs.
The two other added records are upstream Colibri Scythe and Travesty; the
catalog is reference data, not an obtainability list. Existing RSE level and
item-stat corrections, two additional latent-stat items, and current zone YAML
flags are included by the same complete generation run. No fallback item names
were needed. Dynamic weapon effects implemented in server Lua are outside this
SQL-based catalog's scope.

Verification: all 21 server generator tests; DLAC's complete CI command set
(7,499 core checks, 1,603 UI smoke checks, catalog/import, repair, equipment,
icons, Gear Vault, HELM and probe regressions); pack lint (31 checks).
Live in-game rendering and equipping still require player acceptance.

Release version: `2026.09.23a`. Review the DLAC pack PR first, then the matching
AscensionXI launcher catalog PR. The latter pins the exact reviewed DLAC commit
and resolves every runtime file, including all icons. Human merge and channel
promotion remain required. After installation, run `/addon reload dlac`, inspect
Forsaken and Rekindled weapon names/icons/stats, and check equip/set selection.
Rollback restores the previous complete addon pin; no player-data migration.
