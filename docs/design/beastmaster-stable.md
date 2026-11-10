# AscensionXI Beastmaster Stable

DLAC owns the Stable interface in `servers/ascensionxi/modules/stable/`:
`init.lua` handles packets/lifecycle, `gauge.lua` holds the pure Ready clock,
`draw.lua` owns the floating window/settings, `grid.lua` caches filtered rows,
and `view.lua` draws the collection and shared paws. It mounts through the existing `modules.lua` list and uses the
shared AscensionXI transport and UI host. No private installer is needed for
a release checkout. Non-AscensionXI packs do not mount it.

The server owns gameplay and persistence. Protocol version 4 uses 0x1E0
operations F0–F6 for collection state, roster edits, names, capture registration,
habitats, saved roster operations and Ready timing. State refreshes are paged,
nonce-correlated and applied only after every page arrives. Ashita event size
bounds the read even when the backing buffer is 512 bytes. Ready reads fractional
seconds from native recast slot 102 on the frame after 0x119, then counts down
locally. F6 supplies the recharge period once per zone, main job/level change or
merit update (0x08C), with at most three attempts. A foreground request can
preempt F6. There is no periodic query or six-second expiry. The server keeps the
unused Call field in protocol v4 for compatibility; DLAC does not decode it.
The gauge hides off BST, on zone-out and with Scroll Lock. The Stable tab is
browsable on every job and honors Settings > Features > Stable. Off BST, F0/F4
load the collection, saved rosters and habitats; mutation buttons are disabled
with an explanation. F1/F2/F3/F5 and F6 remain main-BST-only on both sides.
This owner-requested change in `2026.11.09c` replaces the review's BST-only tab
gate. AscensionXI's native saved-state view and wire read permissions must ship
with it; changing only the tab gate would leave WAR browsing rejected.
No ability, charge, shiny or equipment formula is enforced by the addon.

## Other servers: November 10 isolation check

CatsEyeXI keeps its own `cexi` pack, catalog and pet modifiers. Its module list
is still `gamemode, prestige, ebox, giftbox`; the loader never mounts the AXI
Stable, transport, gauge commands or portraits. No CEXI pack files changed in
this PR. Unknown installations with no selection remain neutral. Server
selection is per install: an explicit Settings > Server choice outranks launcher
detection, and switching packs reloads the addon.

The audit found a Settings-only leak: the globally listed Stable checkbox
appeared on CEXI even though its tab could not load. `2026.11.10a` adds a generic
module dependency to that tab's setting; `featuregate.tabOptions()` offers only
tabs whose required module exists in the active pack. A saved override cannot
make the unsupported checkbox appear. AXI retains the same Stable checkbox.

`tests/server_pack_isolation.lua` mounts the real CEXI modules and data headlessly,
checks that no AXI runtime module or BST gauge service loads, exercises idle
module pumps, and verifies the Settings control, neutral pack choice, optional
stat-label cache across pack resets, and unchanged whole-second recast rounding.
It runs in the existing Stable CI step under Lua 5.4 and also passed under
LuaJIT locally. `stable_assets.lua` additionally checks that the existing shared
and CEXI synchronous texture API still loads immediately, caches and separates
paths, and does no texture work with an empty queue.

Validation: 8,083 core checks, 1,778 CEXI UI smoke checks, CEXI pack lint (39),
AXI pack lint (49), Stable mount/protocol/assets checks and AXI catalog checks
passed under Lua 5.4. These are headless compatibility checks, not a live CEXI
session. Repeat with `lua tests/server_pack_isolation.lua` plus the suites above.

## Source ownership and refreshing

The AscensionXI generator `tools/dlac-pack/gen_pack.py` refreshes catalog.lua,
134 pre-cropped 256px portraits in assets/stable, item data, pet modifiers and the pack manifest.
It never writes Stable init.lua, view.lua or the handwritten modules.lua.
The server repository no longer carries copies of the two UI files. Make UI
changes here. Make server catalog, ability descriptions, scaling reference or
portrait-authoring changes there, then regenerate this pack and review it.

The release pairs with AscensionXI PR #1121. Deploying the addon to an older
server cannot enable the gameplay. The server must support the Stable wire.
Do not pin a DLAC commit containing this catalog before #1121 is deployed to
the corresponding server environment, including via an unrelated hotfix. It
changes existing Beast/Monster equipment and Barbaroi Axe as well as new items.
Save the Queen's model 1195 -> 954 is intentional: AXI's November 8 off-hand
animation fix is documented in `documentation/custom/custom-weapons.md`.
The launcher catalog pin remains an owner-controlled release step after review.

## Review fixes, November 9

The gauge remains visible on main BST even without a pet, as before. Use
`/dl gauge show|hide|lock|unlock|scale N|status|demo` (also `/dlac gauge`). Settings
and settled position are written through `safewrite` to the character's
`bstgauge.lua`. WHM yields shared commands to BST when this module is mounted.
`/dl stable status` compares the locally aged slot-102 and last F6 timers; an old
F6 is diagnostic, not authoritative after a subsequent Ready use. Native
packets round up to seconds, so a small difference is expected.

Portraits use a generic queued loader capped at two new textures per frame.
The collection filters are cached until snapshot/search/filter changes, and only
viewport rows plus one overscan row are submitted. Reopening Stable refreshes
F0; continuous display does not poll. Zone changes preserve search/filter/card
choices. Live revision pushes remain deferred: use Refresh while the tab stays
open. Give-up is measured from the first successful send, never time spent
waiting behind another transport producer. F0-FF share the `stable` producer.

Pack-local stat definitions label `BSTShinyChance` as **Shiny Chance Bonus**
(+100% means double the base odds) and `BSTReadyTPKept` as **Ready TP Retained**,
both percentages. The shared stat reader only provides the optional pack hook.

Measured headlessly at e4686f1 versus this revision:

| Check | Before | After |
| --- | --- | --- |
| Ten idle minutes, F6 answered in 100ms | 282 requests; transport busy 10.5% | 1 request; busy <0.1% |
| Ten idle minutes, no F6 answer | 48 requests; busy 24.0% | 3 bounded attempts; busy 1.5% |
| Catalog portrait size | 134 x 600x600 | 134 x 256x256, 4.82 MiB PNG total |
| New portrait loads in one frame | all submitted uncached portraits | at most 2 |
| 134 forms, 4 columns, 500px viewport | 134 cards | 12 including overscan |

The independent hour-long tests keep the request count at one and recast-read
count unchanged between events. The review harness's “sends/hour” extrapolates
a ten-minute sample; after the change those are one-time startup/retry counts,
not a sustained rate. The whole-addon frame harness (Mikate_1, BST, 60 seconds,
15-second warm-up) measured 0.155 -> 0.169 ms/frame and 15.4 -> 15.6 KB/frame,
with zero handler errors. Its fake UI has no populated Stable or real textures;
these numbers establish no in-game GPU or first-open improvement. The owner
still checks `/dl perf`, first-open smoothness and private bytes in the client.

## Tests

Field correction, November 9 (`2026.11.09b`): `/dl stable status` exposed an
invalid `chatfmt.info` call shared by all BST gauge feedback. Use the existing
`chatfmt.msg` API. The draw suite now captures final chat output instead of
replacing `_say`, so it exercises the production formatter for status aliases,
control acknowledgements and drawing-error messages. The revised test reproduced
the owner's exact nil-function error before the fix and passes afterward.
This is an addon-only update on the existing DLAC #245; reload DLAC after installing.

From a clean DLAC checkout:

```text
lua tests/ascensionxi_stable.lua
lua tests/stable_protocol.lua
lua tests/stable_gauge.lua
lua tests/stable_draw.lua
lua tests/stable_assets.lua
lua tests/pack_lint.lua ascensionxi
lua tests/ascensionxi_catalog.lua
lua tests/ascensionxi_pldgauge.lua
lua tests/ascensionxi_whmgauge.lua
lua tests/ascensionxi_dncstatus.lua
```

The five Stable suites run together in one CI step. The mount check validates all 67 catalog
entries and 134 PNG files, registers the interface and exercises real shared
transport with controlled clock/send seams, including job changes and zoning.
`tests/fixtures/stable/server.lua` comes from the production AXI wire handler
with synthetic backend state. Regenerate from AXI by setting `BST_DLAC_FIXTURES`
to that file and running `tools/bst_playtest/export_dlac_fixtures.lua` with the
project LuaJIT runtime. Protocol tests exercise atomic out-of-order/duplicate
pages, truncation, padded backing buffers, stale nonces, error statuses, queued
timeouts and reopen refreshes. Draw tests inject failures inside the real paw
renderer and tooltip to check stack cleanup, settings and command routing.
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
