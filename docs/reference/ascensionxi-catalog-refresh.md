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

The owner approved showing both numeric bonuses on September 12, 2026.
The owner also approved the Gathering Gear correction. It now uses
`gear/gathering.lua` for category-specific ladders ordered by extra rolls,
break reduction, lower equip level, then name. The generator declares
`helmModel = 'extra-rolls'` and reads `helmBreakBase` from the enabled server
HELM module's `BREAK_CHANCE`. Packs without the numeric model keep their
existing rules. Worker +1 outranks Worker, which outranks Field; eligible
headgear participates. All candidates are retained for level fallback.

`ui/automationsui.lua` keeps job/bag gates and writes the numeric category
ladders at autogear format 16. `dispatch.lua` version 168 selects them,
refusing saved manifests older than format 16 until rescan. Opening Gear
Helpers refreshes the old format. `feature/helmwatch.lua` computes planned
outfit totals; its `bonuses()` returns extraRoll, breakReduction, breakChance
and breakProof. `ui/helmui.lua`, `ui/helmbar.lua` and `/dl helm show` present
those numeric results without CatsEyeXI hats, Surveyor or venture-point claims.
The panel shows planned pieces and their individual bonuses. Totals explicitly
describe **planned gear**, since locks/other equipment rules can alter what is
actually worn. Weapon slots remain excluded and combat stand-aside is preserved.
The existing Fishing Gear helper does recognize `FishingSkill` after rescan.

Verification from this checkout:

```powershell
lua tests/pack_lint.lua ascensionxi
lua tests/ascensionxi_catalog.lua
lua tests/run_tests.lua
lua tests/smoke_ui.lua
```

All pass. Pack lint runs 30 checks through the real mount/walker. The item
test checks names, equipment levels, stats, display units and all three full
gathering sets across all four activities. Removing headgear from the totals
deliberately makes it fail. The headless suite passes 7,490 checks and UI smoke
passes 1,508, including numeric writer/engine integration, underlevel fallback,
job/bag filtering, category selection, stale data, headgear, clamping and numeric
render branches. The CEXI golden output changes only its format marker, 15 to 16.
In the server repository, nine Python tests pass, including source-derived HELM
constants; disabling module replay makes the Anchor Ring regression fail.
No live client testing or captures were used.

Client acceptance: default helper visibility remains off. Enable Gear Helpers
and Hobby Bar under Settings > Features and open Gathering Gear to refresh the
saved manifest. Inspect Field/Worker/Worker +1 at level 1: full sets give
+50/+100/+200 extra rolls and 25/0/0 percent break chance on a failed swing,
including excavation. Remove the cap to check totals, move the upgrade to a
non-equippable bag to check fallback, arm near a Point and confirm the planned
outfit equips. Enter combat to verify stand-aside and test a slot lock to confirm
the distinction between planned stats and actual equipment. Live appearance and
equip acceptance remain outstanding.

For regeneration, read server `documentation/custom/dlac-item-catalog.md`
and `tools/dlac-pack/README.md`. Run the generator into this pack directory,
preserving hand-maintained `features.lua`, `detect.lua`, `modules.lua` and
`modules/`. Three extra stock zone-latent rows for item 18693 are recovered
from the old whitespace-sensitive reader; latent condition support is not
newly certified. Other unmapped historical modifiers remain a wider audit.

Release follow-up, September 12: both implementation PRs below merged. DLAC
main `9542854` contains the catalog and engine 168, but its entry point still
declared `2026.09.10b`. This follow-up changes `dlac.lua` to `2026.09.12a`.
The display string is independent of `dispatch.lua`'s engine version; both
must be checked when releasing behavior changes.

The reported installed copy at `C:/AscensionXI/Ashita/addons/dlac` was on
`codex/gear-vault-duplicate-text`, commit `960200a`, with engine 167. Its four
uncommitted catalog/stat files match merged main exactly after normalizing
line endings. The old branch's patches are already represented on main
(`git log --left-right --cherry-pick HEAD...origin/main` has no left-only
commits). Preserve the branch and a named stash before updating this working
copy. No player configuration lives in those four files.

The launcher's `.git` protection deliberately skips this developer install.
Separately, AscensionXI's public catalog still pinned DLAC `0b272cdb54dc`
when the report arrived. A DLAC merge alone updates neither this Git checkout
nor that public pin. After this version correction merges, run in a server
topic checkout:

```powershell
python tools/addon-catalog.py bump dlac
python tools/addon-catalog.py verify
```

Review the resolved DLAC version and hashes, then submit the pin PR for human
merge. Do not pin unmerged work or dispatch release workflows. Developer
installs need a Git update; ordinary installs receive the published pin on
their next launcher start. In either case a running addon needs
`/addon reload dlac`, then `/dl check` should show `2026.09.12a`, engine 168.
Open Gear Helpers to refresh saved autogear format 16. Live client acceptance
remains outstanding. Rollback uses the preserved local branch/stash or a
revert PR plus the previous launcher pin; no database migration is involved.

Review: [DLAC #169](https://github.com/henkpoa/dlac/pull/169), paired with
[server #464](https://github.com/henkpoa/AscensionXI/pull/464).
