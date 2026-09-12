# AscensionXI catalog refresh, September 12, 2026

This branch regenerates the AscensionXI pack from server main `26d8accdec`
plus the corrected `tools/dlac-pack` generator on server branch
`codex/dlac-item-catalog`. The generator now applies enabled item SQL modules
in `modules/init.txt` order. The prior generator read only stock item dumps.

Result versus DLAC main `51c6005`: 17 added equipment records, 103 existing
records corrected, no removals, 15,418 total. Names all came from client DATs.
Added IDs 26547–26563 cover the two Forge Probe vests, Rabbit Charm +1,
Field/Worker caps, five Worker +1 pieces, Fisherman's/Angler's caps and five
Angler +1 pieces. A catalog record does not mean an item is obtainable:
probe gear and deferred Angler +1 equipment remain defined reference data.

The generator also restores Anchor Ring's level 15 requirement, level and
defense updates to Worker/Angler, expert crafting weapon damage and mods,
and isolated gear model IDs. It maps FishingSkill, TreasureHunter,
ResistSilence and CursnaReceived to existing DLAC vocabulary.

New stat definitions preserve AscensionXI's gathering values:

- `HarvestingExtraRoll`, `LoggingExtraRoll`, `MiningExtraRoll`,
  `ExcavationExtraRoll`: percent. Each 100 guarantees an extra roll; the
  remainder is the chance for one more. Not per-roll success chance.
- `HelmBreakReduction`: positive percentage points removed from the 50%
  break check after a failed swing, including excavation and headgear.
  Full Field leaves 25%; full Worker and Worker +1 reach zero.
- `HELM = 1` remains a compatibility/discovery flag. Do not turn it into a
  numeric upgrade tier or treat it as the actual break reduction.

The numeric presentation is proposed pending the owner's response. A second
scope question is pending: whether this batch should adapt Gathering Gear.
**It currently does not.** Its `ui/automationsui.lua` ladders still score
CatsEyeXI HELM/Surveyor, `feature/helmwatch.lua` excludes heads and applies
the old five-point break rating, and `ui/helmui.lua` / `ui/helmbar.lua` retain
CatsEyeXI coverage text and hat assumptions. These need coordinated changes
before claiming automatic selection or immunity display is correct here.
The existing Fishing Gear helper does recognize `FishingSkill` after rescan.

Verification from this checkout:

```powershell
lua tests/pack_lint.lua ascensionxi
lua tests/ascensionxi_catalog.lua
```

Both pass. Pack lint runs 30 checks through the real mount/walker. The item
test checks names, equipment levels, stats and display units. In the server
repository, eight Python tests pass; disabling module replay makes the
Anchor Ring regression fail. No live client testing or captures were used.

For regeneration, read server `documentation/custom/dlac-item-catalog.md`
and `tools/dlac-pack/README.md`. Run the generator into this pack directory,
preserving hand-maintained `features.lua`, `detect.lua`, `modules.lua` and
`modules/`. Three extra stock zone-latent rows for item 18693 are recovered
from the old whitespace-sensitive reader; latent condition support is not
newly certified. Other unmapped historical modifiers remain a wider audit.

This is topic-branch work, not installed or deployed. The launcher pin in
the server repository is unchanged. Human merge comes first; then a server
topic PR bumps and verifies the DLAC pin. Never merge or dispatch release
workflows as an agent. Rollback uses a revert PR and, if released, restores
the previous launcher pin; no database migration is involved.
