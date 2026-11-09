# AscensionXI Beastmaster Stable

DLAC owns the Stable interface in `servers/ascensionxi/modules/stable/init.lua`
and `view.lua`. It mounts through the existing `modules.lua` list and uses the
shared AscensionXI transport and UI host. No private installer is needed for
a release checkout. Non-AscensionXI packs do not mount it.

The server owns gameplay and persistence. Protocol version 4 uses 0x1E0
operations F0–F6 for collection state, roster edits, names, capture registration,
habitats, saved roster operations and Ready timing. State refreshes are paged,
nonce-correlated and applied only after every page arrives. Ashita event size
bounds the read even when the backing buffer is 512 bytes. Ready timing comes
from the server, including merits. The gauge hides off BST and on zone-out.
No ability, charge, shiny or equipment formula is enforced by the addon.

## Source ownership and refreshing

The AscensionXI generator `tools/dlac-pack/gen_pack.py` refreshes catalog.lua,
134 portraits in assets/stable, item data, pet modifiers and the pack manifest.
It never writes Stable init.lua, view.lua or the handwritten modules.lua.
The server repository no longer carries copies of the two UI files. Make UI
changes here. Make server catalog, ability descriptions, scaling reference or
portrait-authoring changes there, then regenerate this pack and review it.

The release pairs with AscensionXI PR #1121. Deploying the addon to an older
server cannot enable the gameplay. The server must support the Stable wire.
The launcher catalog pin is an owner-controlled step after PR approval and
merge. No release workflow or production deployment was dispatched here.

## Tests

From a clean DLAC checkout:

```text
lua tests/ascensionxi_stable.lua
lua tests/pack_lint.lua ascensionxi
lua tests/ascensionxi_catalog.lua
lua tests/ascensionxi_pldgauge.lua
lua tests/ascensionxi_whmgauge.lua
lua tests/ascensionxi_dncstatus.lua
```

The Stable check mounts the actual pack and module, validates all 67 catalog
entries and 134 PNG files, registers the interface and exercises real shared
transport with controlled clock/send seams, including job changes and zoning.
The server repository's protocol/UI suite accepts this checkout explicitly:

```text
python tools/bst_playtest/check_protocol.py --dlac <DLAC checkout>
```

That suite exercises the real server wire handler and this repo's UI/decoder:
paging, malformed and late replies, retry/deduplication, 134 forms, filters,
rosters, merit timing, animation, charge previews, 152 ability details and
813 habitats. It does not substitute a server-side copy of the addon.

The release check must repeat from an exported committed checkout, then refresh
the generated pack and assert that handwritten code and module registration
remain unchanged. The server generator has a regression for this boundary.
The owner still checks real in-game rendering. Automated tests do not control
an already-running game client.
