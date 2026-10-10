A log of AscensionXI catalog refreshes, newest first. To get one from DLAC main to players
(AXI pin PR, staging channel, prod promotion), follow
[ascensionxi-release-routine.md](ascensionxi-release-routine.md).

---

# AscensionXI catalog refresh, October 9, 2026

DLAC `2026.10.09a` regenerates the complete pack from AscensionXI main
`b311f830b3` (AXI #834). The four guild crafting headpieces are added with
their icons: Carpenter's Cap (26576), Smithy's Goggles (26577), Tanner's
Bandana (26578) and Alchemist's Goggles (26579). Each is a level-1 Head piece
with DEF 1 and +1 to its craft. Carpenter's Gloves, Smithy's Mitts, Tanner's
Gloves and Caduceus lose their +1 craft skill. Those pieces sat outside the
Head slot, so they could stack with Artisan's Hat past the intended +10. The
refresh also picks up Almogavar Bow +1 (19997) and Faerie Tunic +1 (26575),
which were already live on the server. Totals: 15,466 equipment records, all
named from tracked client DATs, and 71 icon overrides.

A fresh `gen_pack.py` run from that commit is byte-identical to the
committed pack. Generator tests (37), AscensionXI pack lint, the core and UI
suites, and `tests/ascensionxi_guild_headgear.lua` all pass. That last test
checks +10 for all eight crafts with the full set. The server half (items,
guild menus, free exchanges, the Artisan recipe) shipped in AXI #834. The
DLAC pin follows in an AXI PR
([ascensionxi-release-routine.md](ascensionxi-release-routine.md)). Prod must
promote that pin's channel together with #834's server image.

---

# AscensionXI catalog refresh, October 4, 2026

DLAC `2026.10.04b` regenerates the complete pack from AscensionXI main
`b0222b6a41`. It adds the fourteen Rekindled +1/+2 weapons (19983-19996)
and their icons: seven level-20 weapons and seven level-30 weapons. No
existing equipment records change or disappear. Totals: 15,460 equipment
records, all named from tracked client DATs, and 65 icon overrides.

The generator change to write `data/digdata.lua` on every run is already
merged in AscensionXI (`3271801528`, PR #780). This refresh verifies that
the table in DLAC #197 matches main: 26 zones, 649 rows, Burrow and Bore
enabled. The other generated datasets and hand-maintained pack files are
unchanged. No new generator code is needed.

Reproduce from that server commit with hydrated item DATs:

```powershell
python -m unittest discover -s tools/dlac-pack -v
python tools/dlac-pack/gen_pack.py --out <dlac>/servers/ascensionxi --game "C:/AscensionXI/Game/FINAL FANTASY XI"
```

The release extends DLAC #197 so the accepted digging feature and current
catalog ship together. The companion AscensionXI launcher PR must pin this
exact DLAC revision and resolve every file hash; re-resolve if review changes
the payload. Human merge order: DLAC first, launcher pin second. The pin merge
publishes the staging DAT channel automatically. Test that channel, then select
its resulting `sha-...` tag as `channel_tag` in today's production deployment;
`keep` would retain the old DLAC release. See the companion server handoff
`documentation/custom/dlac-2026-10-04-release.md` for validation and rollback.

Players following addon updates receive this version on their next launcher
start after channel promotion. Developer Git installs require a Git update;
running clients need `/addon reload dlac`. Verify `/dl check` says
`2026.10.04b`, inspect the new weapons and icons, and open the Digging tab.
The digging feature was owner-accepted in the client in #197; this catalog
refresh is verified offline only. Prepared for review, not deployed.

Verification: 35 generator tests; all DLAC CI commands (7,547 core checks,
1,628 UI smoke checks and focused regressions); 35 pack-lint checks; digging
and HELM tests against the source server checkout. A complete record comparison
confirms exactly IDs 19983-19996 were added at the intended levels, each with
a PNG, and every previous catalog record is unchanged.

---

# AscensionXI catalog refresh, October 2, 2026

DLAC `2026.10.02a` regenerates the complete pack from AscensionXI main
`3a3e7f9df1`. It adds six equipment records and icons (26569-26574):
Shaman's Belt +1, Artisan's Apron, Artisan's Hat, Kupo Shield +1/+2 and
Artisan's Torque. The base Kupo Shield now grants +1 crafting skills;
eight individual crafting torques now require level 1. No records are removed.
The pack contains 15,446 equipment records and 51 icon overrides, with all
names read from tracked client DATs. Hand-maintained pack files are unchanged.

Reproduce from that server checkout (with LFS DATs available):

```powershell
python -m unittest discover -s tools/dlac-pack -v
python tools/dlac-pack/gen_pack.py --out <dlac>/servers/ascensionxi --game "C:/AscensionXI/Game/FINAL FANTASY XI"
```

The normal generation command also runs the icon pipeline. Commit the whole
pack, including PNGs. Verification passed: 24 generator tests, all DLAC CI
commands (7,521 core checks, 1,620 UI smoke checks and focused regressions),
and 33 pack-lint checks. Live client rendering remains unverified.

Prepared for review, not deployed. Merge this DLAC PR before the companion
AscensionXI launcher-pin PR; that PR must pin the exact reviewed DLAC commit
and be re-resolved if the payload changes. Human release and client acceptance
remain required. After installation, reload DLAC and check new names, icons
and crafting bonuses. Developer Git installations need a Git update because
the launcher protects them. Rollback restores the previous full pack and
launcher pin together; no player configuration or database changes.

---

# AscensionXI catalog refresh, September 27, 2026

DLAC `2026.09.27e` regenerates the complete AscensionXI pack from server
main `2999eea01c`. Exactly 36 existing records change: the six base-job
Artifact weapons (level 40) and thirty armor pieces (level 50), matching
`client/sources/artifact-gear/items.json` and enabled `artifact_gear.sql`.
Traveler's Mantle +1 (26568, level 12) and its icon are added. Nothing is
removed: 15,437 equipment records, 42 icon overrides, 866 latent-stat items.
All equipment names come from tracked client DATs.

The generated latents include Berserk (56) and RDM stance (419) conditions.
This exports reference data; it does not add runtime latent evaluation or
new stat mappings. Existing unmapped modifiers remain raw server keys.
Hand-maintained pack modules and features are preserved.

Reproduce from the server checkout:

```powershell
python tools/dlac-pack/gen_pack.py --out C:/repos/dlac-catalog-refresh/servers/ascensionxi --game "C:/AscensionXI/Game/FINAL FANTASY XI"
python -m unittest discover -s tools/dlac-pack -v
```

Verification: 21 generator tests; DLAC pack lint (33 checks), catalog,
custom equipment and icon regressions; core suite (7,519 checks) and UI
smoke (1,612 checks). A comparison against the previous catalog verifies
that the changed IDs are exactly the 36 authored Artifact IDs and all
have the intended levels. No live-client verification was performed.

Prepared for review, not deployed. Merge this DLAC PR before its paired
AXI launcher-catalog PR. The AXI PR pins this immutable release commit;
re-resolve it if review changes the payload. A human releases the staging
channel and promotes it after acceptance. Check Artifact names, levels,
stats, and Traveler's Mantle +1 artwork in the client. Developer Git
installations require a Git update and `/addon reload dlac`; the launcher
protects them from overwrites. Rollback restores the prior full pack and
launcher pin together. No player configuration or database changes.

---

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
