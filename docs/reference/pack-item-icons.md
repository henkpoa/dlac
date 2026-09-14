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
