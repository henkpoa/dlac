# Rabbit Charm +1 displayed as Body / Lv127

Pipeline follow-up (`2026.09.14g`): the normal AscensionXI catalog generator
now emits icons and catalog data together, and artwork lives inside the pack.
This supersedes the separate icon generation procedure below. See
[Catalog item artwork](pack-item-icons.md) for the current workflow.


September 14 update (`2026.09.14f`): the owner confirmed Field Cap can equip,
but still had its placeholder icon. The single-item artwork mapping described
below is superseded by generated coverage for all 25 changed staging catalog
icons. See [Catalog item artwork](pack-item-icons.md) for regeneration,
verification and release steps. Equipment metadata remains catalog-driven.

## September 14 follow-up: native equip and icon (`2026.09.14e`)

The subsequent screenshot shows Neck/Lv7/All and correct stats, but the reporter
also confirms equipment/set trouble and the gray icon. Read-only inspection of
this install's `Mindlor_4/gear.lua` found Neck/Lv7/All, and its WAR Idle set
already refers to `gear.Neck.RabbitCharm_1`. Repeating `/dl repair` therefore
has no remaining saved metadata to change.

`lua tests/custom_equipment.lua` initially failed with
`Rabbit Charm +1: repaired Neck/Lv7 set must send an equip for WAR20 despite
Body/Lv127 resources`. This drives the real native bag snapshot, resolver and
packet-building path with an injected resource and inventory. Changing only
the fixture resource's level/slot to 7/Neck made it pass. The engine previously
read `res.Level`, `res.Jobs` and `res.Slots` directly in all three snapshot paths,
bypassing the earlier import/repair correction.

The importer and native engine now share `gearrecord.equipMetadata`, including
catalog job-mask conversion and preservation of valid combined slot masks.
The corrected facts reach bag candidates, live worn equipment and the trust
cache; correcting the latter two prevents repeated attempts to equip an item
that is already worn. Names, flags and instance data retain their original
source. Unknown/catalog-less items keep resource-based gates.

The same regression exercises the actual WAR20 Neck picker and confirms the
repaired charm is offered. A separate picker failure was not reproduced.
It also checks the outgoing Neck packet, repeated-dispatch stability, level/job
restrictions, disabled/encumbered slots, equippable flags and catalog absence.

Read-only extraction of item 26549's icon from the base `ROM/286/73.DAT` produces
the gray square in the screenshot; extraction from the installed
`ascensionxi-staging` overlay produces the charm with the white +1 frame.
There is no competing `ascensionxi-staging-hd` override of this shard.
The existing staging pixels are shipped as `assets/ascensionxi/items/26549.png`,
declared by the optional AscensionXI `itemicons.lua` companion. Both icon rows
and the equipped grid use the shared override. No client DAT or launcher
configuration was changed. `lua tests/itemicons.lua` first failed on the retail
placeholder choice, then passed with the override; it also covers missing
artwork, other packs and texture ownership.

Verification: custom equipment, item icon, catalog/import, saved repair, vault
count, main engine and UI smoke suites. Apply with `/addon reload dlac`; the
version should read `2026.09.14e`. Live equip/render verification remains pending.
These are local addon changes, not a staging-server deployment.

Diagnosis September 13; automatic repair added September 14, 2026. Implemented
locally as DLAC `2026.09.14a`; not yet published or verified in a running client.
Client DATs, server data and actual player configuration were not changed.

## Result

The reported display matches the base client placeholder for item **26549**.
The installed custom overlays and DLAC's AscensionXI catalog instead identify
it as **Rabbit Charm +1, Neck, level 7**. Both vault panes obtain their grouping
and level locally; the vault protocol does not transmit those fields.

DLAC also preserves an incorrectly imported record: a deterministic replay
through its actual enrichment, flattening and lookup functions returns
Body/Lv127 even with the correct catalog loaded. The reporter subsequently
supplied `gear.lua`, confirming the exact `Body.RabbitCharm_1` entry with level
127 and the base placeholder's 20-job list. Their `/dl check` shows
`2026.09.12a`, engine 168, the AscensionXI pack and 15,418 catalog items.
Whether their running resource manager still returns the base metadata or
the saved entry originated earlier remains unobserved.

The fix makes `resolveItem` use the active catalog for slot, level, jobs and
available weapon category/handedness. It runs before the resource's zero-slot
eligibility check, so a placeholder cannot exclude known catalog equipment.
Client names, flags and instance augments remain intact. Unknown items or an
unavailable catalog retain the previous resource-based behavior. No custom
item IDs are hard-coded. Both bag scans and vault-only imports use this resolver.

Henrik superseded the manual-repair plan on September 14: players should not
need to edit files. Character load now checks saved records against the active
catalog, independently of the auto-import setting and of bag/vault freshness.
It repairs slot/category, level and jobs, preserving keys where possible,
instance augments, counts, stats and comments. A destination key collision uses
a free `_2`, `_3`, etc. suffix rather than overwriting another item.

Old reference paths remain usable through a self-contained `do` block before
`return gear`: per-container `__index` aliases resolve to the relocated record
but do not appear in `pairs`, so ownership and UI grouping do not double-count
it. Subsequent relocations retarget old aliases too. Existing set SLOT choices
are not rewritten; a set that explicitly selected Body still selects Body.

The original file is backed up through the existing safewrite helper before
replacement, and the candidate file is executed in a sandbox before replacing
the original. A file changed since planning is refused. Unsupported field
expressions or file shapes are reported without a partial repair. No file is
written when all supported records already match. A successful repair queues
one addon reload; imports are held until it runs, and the next load makes no
changes. This refreshes active sets and the vault's cached views together.
The manual action is **Menu > Settings > Repair gear data**, also `/dl repair`.
It refuses to run while the Sets editor has pending edits, preserving drafts.

## Evidence

- `servers/ascensionxi/data/catalog.lua`: item 26549 is under `Neck`, has
  `Type = "Neck"` and `Level = 7`.
- Before this fix, `gear/gearimport.lua`, `resolveItem` took `Level`, `Slots`
  and `Jobs` from `AshitaCore:GetResourceManager():GetItemById`, and derived
  the saved equipment bucket from `Slots`.
- `gear/gearrecord.lua`, `enrich`: enriches stats and pairing metadata without
  correcting an owned entry's level or its parent slot table.
- `gear/gearoracle.lua`, `lookup`: returns an owned record before the catalog.
- `servers/ascensionxi/modules/gearvault/vaultui.lua`: both `vaultView` and
  `layoutView` call the shared `lookupById`; `bucket` groups by `rec.Slot`.
- `docs/design/gear-vault-integration.md`: LIST and LAYOUT_LIST carry item IDs,
  counts and instance identity, not equipment slot or level.

Decoded item 26549 read-only using the existing server tool
`C:/repos/ascensionxi/tools/dat-items.py` (`decode` and `parse_entries`):

| Local file | Name | Level | Slot mask |
|---|---|---:|---|
| `C:/AscensionXI/Game/FINAL FANTASY XI/ROM/286/73.DAT` | `.` | 127 | `0x20` (Body) |
| `C:/AscensionXI/Ashita/polplugins/DATs/ascensionxi-prod/ROM/286/73.DAT` | Rabbit Charm +1 | 7 | `0x200` (Neck) |
| Same relative path in `ascensionxi-staging` | Rabbit Charm +1 | 7 | `0x200` |
| Same relative path in `ascensionxi-dev` | Rabbit Charm +1 | 7 | `0x200` |
| `C:/repos/ascensionxi/client/dats/ROM/286/73.DAT` | Rabbit Charm +1 | 7 | `0x200` |

The server checkout's `client/sources/gear/rabbit_charm/set.yaml` and generated
`modules/custom/sql/gear_rabbit_charm.sql` also specify Neck/7. These are local
source files, not a query of production's database. The installed boot configs
enable resource overrides and Pivot; this investigation did not observe the
reporter's loaded resources or establish how their resource manager resolves
the overlays. Do not infer that the presence of a retail base DAT is itself an
installation error: custom data is intentionally supplied through overlays.

Two local characters' saved entries already have Neck/7. They are not the
reporter's data and were left untouched.

## Reproduce the original saved-record lookup failure

Run from the DLAC root in PowerShell. The synthetic owned entry represents the
reported metadata; enrichment, flattening and lookup are production code.
This deliberately bypasses the new startup repair to demonstrate the old
lookup failure. The passing repair regression is `tests/gear_repair.lua`.

```powershell
@'
local ci = dofile('gear/catalogindex.lua')
local gr = dofile('gear/gearrecord.lua')
local oracle = dofile('gear/gearoracle.lua')
local _, cat = ci.flatten(dofile('servers/ascensionxi/data/catalog.lua'))
local old = { Name = 'Rabbit Charm +1', Id = 26549, Level = 127 }
gr.enrich(old, cat[26549])
local _, owned = ci.flatten({Body = {RabbitCharm_1 = old}})
oracle.setLookupSource({
    ownedById = function(id) return owned[id] end,
    catalogById = function(id) return cat[id] end,
})
local r = oracle.lookup(26549)
print(string.format('Vault lookup: %s, %s, Lv%d; catalog: %s, Lv%d',
    r.Name, r.Slot, r.Level, cat[26549].Slot, cat[26549].Level))
assert(r.Slot == 'Neck' and r.Level == 7,
    'reported Body/Lv127 survives catalog enrichment')
'@ | lua -
```

Observed: `Vault lookup: Rabbit Charm +1, Body, Lv127; catalog: Neck, Lv7`,
followed by the assertion failure. Removing the owned entry makes lookup fall
back to the correct catalog record. `lua tests/ascensionxi_catalog.lua` passes.

## Applying and verifying the fix

1. Apply the updated addon files and run `/addon reload dlac`. `/dl check`
   should show `2026.09.14a`; the engine remains 168. Ordinary installations
   need the normal addon publication/launcher catalog update before receiving
   this change; editing this developer checkout does not publish it.
2. On the first character load, expect one correction message naming the
   backup, followed by an automatic addon reload if mismatches were found.
   Rabbit Charm +1 should move to Neck/7/All; Field Cap (26550) to Head/1/All.
   Another reload should produce no additional repair or backup. No player
   text editing is needed. To recheck manually, use Repair gear data in
   Settings after committing/discarding any pending set edits.
3. Verify a fresh import and the repaired existing record in both vault panes,
   the Neck picker and level-7 equip eligibility. No live UI or equip test was
   performed here.

Automated verification:

```powershell
lua tests/ascensionxi_catalog.lua
lua tests/gear_repair.lua
lua tests/run_tests.lua
lua tests/smoke_ui.lua
git diff --check
```

The catalog/import test first failed with `bag: Rabbit Charm +1 imported as
Body` before the fix and now passes. It drives the real scan and entry writer
for bag and vault-only copies, checks zero-slot placeholders, level and job
overrides, preserved names/flags/augment data, nested weapon categories and
handedness, combined slot masks, unknown-item fallback and catalog absence.
The saved-repair test first failed because the charm remained in Body. It now
covers persisted corrections, old-path resolution through the actual profile
reader, absence of duplicate ownership, destination collisions, missing slots,
repeat relocations, multiple augmented copies, future staging, malformed input,
backup/write/validation failures, idempotence and the startup reload sequence.
The existing suites pass 7,490 and 1,511 checks respectively; the latter includes
the Settings repair button. CI runs both import and saved-repair regressions.

Changed runtime files: `gear/gearimport.lua`, `gear/syncflags.lua`,
`ui/gearui.lua`, `ui/menuui.lua`, `dlac.lua` (version only).
Supporting files: `tests/{ascensionxi_catalog,gear_repair,smoke_ui}.lua`,
`.github/workflows/ci.yml`, this note and `docs/reference/server-pack-contract.md`.
Rollback restores the previous runtime files and reloads the addon. Repaired
gear files are ordinary Lua with self-contained aliases, requiring no new
runtime module. A player's pre-repair file is also available in the named
backup if needed; there is no database migration.
Further resource/Pivot investigation should start with the affected player's
live `GetItemById(26549)` values, not by changing vault SQL.
