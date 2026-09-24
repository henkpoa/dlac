# Void Restock

Implemented in the AscensionXI feature batch, draft PR #179. Lockstyle has
been field-tested; Void Restock still needs the in-game checks below.

## Player behavior

On AscensionXI, Gear Helpers and the quick menu expose **Void Restock**.
`/dl restock` opens it. CatsEyeXI retains its existing E-Box helper.

The character list applies on every job. A current-job entry overrides the
same item in the character list, including a target of zero. Targets count
**Inventory only**: the purpose is to preserve supplies in Inventory while
storing excess, and withdrawals land there. Satchel, Sack, Case, bundles,
wardrobes and other jobs' lists do not satisfy these inventory targets.

- **Fetch shortfall** draws up to the target, available stored stock and a
  conservative fresh-slot budget, with job entries taking priority.
- **Store excess** deposits only `inventory quantity - target` for listed
  items. Unlisted items are untouched. This was explicitly chosen by the
  owner over sweeping all other eligible inventory items.
- A zero target stores all inventory copies of that listed item.
- No move runs automatically. Entering range of a Void Coffer refreshes the
  stored counts once. Buttons initiate moves; Stop cancels unsent work.
- The tray keeps the red store button first and shows the green fetch button
  when a shortage can be filled. Right-click either to edit lists. With stale
  stock, Store waits for a successful refresh and then deposits listed surplus.
  A click during the approach refresh also retains that intent. Stop, context
  changes and failed reads cancel it. Completion and no-op reasons appear in chat.

Items can be added from Inventory, the stored holdings list, or a case-insensitive
partial-name search across AXI's allowed supplies, even without current stock.
Search caches names only and rechecks tier access and active lists each time.
All paths exclude equipment except Ammo, using
the Gear Oracle's slot when known and the client resource mask otherwise.
Previously saved equipment entries also stay out of move plans. The editor
uses an 880px-wide fixed-column table layout with bounded scrolling regions
for the lists and picker. The server remains authoritative for membership,
attunement, tiers, busy items and Rare restrictions. A refusal/partial move
is displayed and stops the run. Duplicate scrolls follow the server's normal
sale rule, which is explained in the Store tooltip.

## Implementation and protocol

`servers/ascensionxi/modules/voidrestock/` contains:

- `model.lua`: normalization, stable serialization, effective list and plans.
- `client.lua`: Void Storage v1, using the shared AscensionXI transport.
- `restock.lua`: character configuration, live inventory and move sequencing.
- `ui.lua`: list editor, action buttons and tray contribution.
- `init.lua`: pack service, helper/tray registrations and event hooks.

The hand-maintained pack `modules.lua` mounts it; `features.lua` enables the
`restock` helper. No core E-Box code or server changes are needed.

Grounding: the companion AscensionXI checkout's
`modules/custom/lua/void_storage.lua`, `src/map/void_store.h`, and
`modules/custom/lua/void_storage_npcs.lua`. Ops on 0x1E0 are HELLO 0,
DEPOSIT 1, WITHDRAW 2 and LIST_ITEMS 4. Coffer range is 5 yalms.
Mutation payloads are `u16 count, u16 reserved`, then `u16 item, u16 quantity`.
This helper sends exactly one explicit item per move. **Never send a zero-entry
deposit: the server interprets that as sweep-all.**

Paged reads publish only after the final page. Move ACKs must match op,
sequence, item and requested quantity. Actual moved quantities update the
mirror. Mutations are never automatically retried; the server's replay
window is limited and a repeated withdrawal can otherwise move twice.

Each move is replanned from live inventory immediately before sending. After
an ACK, the controller waits for the expected inventory quantity before
continuing, including after Stop. Unexpected inventory changes, timeouts,
job changes, zones and leaving range stop further moves. An already-sent
request cannot be cancelled. The wire has no atomic keep-target operation:
independent consumption/movement during the server round trip can still
change the final quantity; the client stops when settlement disagrees.

All requests use `servers/ascensionxi/transport.lua`, sharing its pacing and
pending-request gate with Gear Vault and HELM. The module consumes only the
Void Storage partition, leaving vault/HELM replies to their existing clients.

## Persistence

`profiles.dataDir()/void-restock.lua` is per character, outside profiles.
On first use, an existing `restock.lua` supplies the lists if the new file is
absent; the old file is never modified. Edits save to the new file through
`lib/safewrite`, with five rotating backups under the character's `backups/`.
A failed backup/write preserves the current live configuration. Malformed
saved config blocks writes instead of silently resetting it. Character
changes clear config, pending work and stored balances.

## Verification and playtest

`lua tests/void_restock.lua` covers planning, protocol pagination, partition
isolation, transport denial, duplicate/mismatched ACKs, partial moves,
timeouts without mutation retries, inventory settlement, job/zone/range
cancellation, settings isolation/import/failed saves, and UI registration.
CI runs it together with `tests/lockstyle_vault.lua`.

After `/addon reload dlac`, open `/dl restock` near a Void Coffer:

1. Add a consumable to Always with target 12. Hold more than 12, plus an
   unlisted storable item. Store excess should leave 12 and leave the unlisted
   item unchanged. Verify both inventory and the server's stored balance.
2. Lower inventory below 12, then Fetch shortfall. Verify it returns to 12.
3. Add a different current-job target for the same item and confirm it wins;
   switch jobs and confirm the character target returns.
4. Test a zero target, little inventory space, a locked-tier item, and leaving
   the Coffer during a run. Refusals should explain themselves without repeats.
5. Reload DLAC and confirm lists/targets persist. Check tray alignment and
   right-click navigation, and exercise Gear Vault/HELM alongside a refresh.

Do not merge the feature batch until the owner has reviewed/playtested it.

## Portal artwork (2026.09.24b)

`assets/void_storage.png` is the transparent portal icon used by the quick
menu and tray. Store/fetch use red/green button backgrounds and distinct
widget IDs. Generated using the built-in imagegen tool, referencing the
owner's portal screenshot and `assets/ebox.png` for its pixel-art style.

Generation prompt:

> Create one square transparent-background pixel-art game UI icon. Reference image 1 supplies the subject: a squat ancient dark grey stone pointed arch portal, brass-gold bands and small gold accents, pitch-black opening rimmed with vivid purple violet swirling energy, low stone base. Reference image 2 supplies the style: chunky crisp retro pixel art, dark outline, readable simple shading, isolated centered object filling the square with a small transparent margin. Match that wooden E-box icon's visual weight and pixel-art treatment, but depict only the purple stone void portal. Front view, no scenery, no lettering, no text, no extra objects. Intended display 30x30 pixels so simplify details strongly. Output a single icon PNG with genuine alpha transparency, preferably 256x256.

The generator returned a 1254px RGBA image; the original alpha is preserved.
The tray displays it at 30px with 3px frame padding, matching E-Box's 36px button.
The missing tray was reproduced through the real entity watcher. The local
server working branch still named the entity "Void Coffer", but its
`origin/main` code uses `packetName = 'Void Storage'` and the Hollow Mirror
model shown in the owner's screenshot. The watcher now recognizes both
names, retaining the 5-yalm range. Tests cover the current name, the legacy
name, out-of-range portals and unrelated entities. In-game confirmation of
the new UI and proximity behavior remains with the owner.

## Membership and KI access (2026.09.24d)

`servers/ascensionxi/data/voidstorage.lua` contains all 3,625 accepted IDs
from AXI's audited membership manifest at
`2ec81c192fddf8ec3a7c30a431bd9845c14eb290`. This includes category seeds,
explicit additions, removals and tier overrides. In particular, Onslaught
materials belong to tier 6 even though their AH categories resemble base
crafting materials. Unknown items are not inferred to be storable merely
because they are not equipment.

Reproduce the data with `python scripts/export_void_storage.py <axi-checkout>
<git-ref>`; it prints the Lua data for review. The source manifest's declared
total and duplicate IDs are validated during export. Refresh this snapshot
when the server membership changes.

HELLO's u32 TierMask is retained and refreshed on every Refresh stock, so
the server answers which KIs the character has. No unreliable client KI
memory reads are needed. Base tiers need no tier KI; gated tiers use:

| Tier | Key item |
| --- | --- |
| Medicines | 3584 |
| Fish | 3585 |
| Meals | 3586 |
| Ninja tools | 3587 |
| Pet items and ammunition | 3588 |
| Onslaught | 3590 |

Overall access is still the Hollow Room quest/attunement gate, not a KI.
Before a handshake, base members may be planned; gated members with unknown
access are hidden unless they already have stored stock. Deposits require
membership and the unlocked tier. AXI's rule that existing stock remains
withdrawable is preserved even if membership/access changes: those supplies
can be selected for withdrawal but never queued for a disallowed deposit.
Equipment other than ammunition remains excluded from this helper.

The picker omits items present in Always or the current-job list. Other-job
lists do not hide items. Always rows provide a `+ JOB` action to create an
override without needing to find the item in the picker again. Removing the
last active entry makes the item eligible to appear again.
