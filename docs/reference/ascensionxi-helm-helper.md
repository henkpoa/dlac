# AscensionXI HELM helper — September 14, 2026

## September 15 live reply fix (2026.09.15a)

The live probe confirmed successful 0x80 replies every five seconds, carrying
2,478 points and raw skills 5/0/107/39. Ashita exposes these 28-byte packets
as 512-byte strings. The decoder's `#data ~= 28` check rejected all of them.
It now validates the wire length from the transport header and checks that
the buffer contains enough bytes. The regression first failed on the padded
buffer, then passed with this fix; it also rejects truncated packets and
incorrect declared lengths. Earlier offline fixtures missed the backing buffer.

The release candidate is `2026.09.15a`, distinguishing this HELM redesign
and fix from published `2026.09.14g`. The owner confirmed the values populate
after reloading the fixed addon on September 15. The subsequent label change
from "Skill level" to "Skill" passed the UI smoke checks. No server change is required.
The observation-only probe lives outside product code in `dlacprobe/helm.lua`.

UI revision `2026.09.14d`: the menu shows the three gear columns, extra-roll
chance, then Mining/Harvesting/Excavation/Logging columns with a skill row and
five success-chance rows. The title explanation, matrix explanation,
expandable quest section and planned-outfit list are removed. Unknown skill
cells are blank; unknown band chances remain `--`. Locked bands require skill
0/20/40/60/80 respectively; open bands follow the server's linear 50–80%
per-roll curve. Every 100 extra-roll bonus guarantees one additional roll,
with the remainder shown as a chance of another. Percentages use
`TextUnformatted` to avoid ImGui format-string interpretation.

The AXI hobby bar has a centered on/off switch, HELM points, extra rolls and
tool-break reduction. It has no gathering-category icons, planned-gear heading,
wearing/status text or Refresh button. AXI uses the same gear for all four
gathering types. Other packs retain their category controls.

Points and skills now require the silent packet endpoint in
[server PR #500](https://github.com/henkpoa/AscensionXI/pull/500), branch
`codex/helm-packet-status`, commit `37069e2961`. It supersedes the command-based readout in merged
[PR #499](https://github.com/henkpoa/AscensionXI/pull/499), removing its added
skill line from `!points`. That command retains its three player-facing
currency lines. The addon never issues or parses it. The normal 0x062 packet
carries 0xFFFF for the custom skill slots, so it cannot supply these values.
Deploying the addon alone does not install the server endpoint.

Gear Helpers and Hobby Bar are enabled by default. The hand-maintained
`servers/ascensionxi/features.lua` allowlist exposes only `helm`. It filters
the helper list, quick-menu helper rows, detail navigation and hobby tabs.
Other packs without an allowlist retain their full roster. Existing explicit
character overrides for the parent tab/menu still apply.

The owner approved all five Field and Worker pieces, with Worker +1 reserved.
The existing numeric gathering selection/engine remains responsible for gear
choice, level/job/bag eligibility and combat stand-aside. This changes the
available UI, not those equip rules. Arm **Gathering Gear** to equip near
gathering Points. It does not perform gathering actions.

## Verified acquisition

Checked against server main
[`a1e543095b`](https://github.com/henkpoa/AscensionXI/tree/a1e543095b), fetched
September 14. The local server working tree was older; prices below use the
fetched commit, not that working tree.

| Slot | Field | Acquisition | Worker | Upgrade at Helmsley |
|---|---|---|---|---|
| Head | Field Cap 26550 | 2,500 points | Worker Cap 26551 | Field Cap + 10,000 points |
| Body | Field Tunica 14374 | Rock Bottom | Worker Tunica 14375 | Field Tunica + 10,000 points |
| Hands | Field Gloves 14817 | 2,500 points | Worker Gloves 14818 | Field Gloves + 10,000 points |
| Legs | Field Hose 14297 | Branch Manager | Worker Hose 14298 | Field Hose + 10,000 points |
| Feet | Field Boots 14176 | Grass Roots | Worker Boots 14177 | Field Boots + 10,000 points |

[Helmsley's shop source](https://github.com/henkpoa/AscensionXI/blob/a1e543095b/modules/custom/lua/helm_points_shop.lua)
confirms purchases and upgrades. She is in Lower Jeuno. Upgrades consume
the matching Field piece, so the five upgrades cost 50,000 points after
obtaining the Field set (5,000 points for its two purchases).

All three quests require level 10, give 50 tools on acceptance, count ten
successful swings of their gathering type, and require returning to the NPC.
Each also grants a wardrobe slot. The suggested gathering zones are guidance;
the quest gather steps do not constrain the zone.

- [Rock Bottom](https://github.com/henkpoa/AscensionXI/blob/a1e543095b/modules/custom/lua/axq/quests/rock_bottom.lua):
  Bumbrak, Bastok Mines; mining, suggesting Zeruhn Mines; Tunica reward.
- [Branch Manager](https://github.com/henkpoa/AscensionXI/blob/a1e543095b/modules/custom/lua/axq/quests/branch_manager.lua):
  Ferdinaux, Northern San d'Oria; logging, suggesting East Ronfaure; Hose reward.
- [Grass Roots](https://github.com/henkpoa/AscensionXI/blob/a1e543095b/modules/custom/lua/axq/quests/grass_roots.lua):
  Mimu-Bumimu, Port Windurst; harvesting, suggesting West Sarutabaruta; Boots reward.

Worker is **not entirely points-only**: retained recipes 33043, 32548 and
41536 produce Field Tunica/Hose/Boots normally and their Worker versions on
HQ. See [recipes](https://github.com/henkpoa/AscensionXI/blob/a1e543095b/sql/synth_recipes.sql)
and [Field gear changes](https://github.com/henkpoa/AscensionXI/blob/a1e543095b/modules/custom/sql/helm_field_gear.sql).
The Field Gloves recipe is removed.

Worker +1 IDs 26552–26556 are defined by
[gear_worker_plus.sql](https://github.com/henkpoa/AscensionXI/blob/a1e543095b/modules/custom/sql/gear_worker_plus.sql).
No acquisition route was found in current server main. The menu therefore
shows the five names as unavailable, with no invented price or upgrade path.
Catalog presence alone is not an acquisition claim.

## Automatic points and skills

The AscensionXI pack's `helm` module provides the `gathering` service.
Its `status.lua` polls opcode 0x80 on the existing custom 0x1E0 packet channel
every five seconds while either HELM surface is visible. Both surfaces share
one polling state. The reply contains the current HELM balance and four raw
skills in tenths, read from the authenticated player. No command or chat is
involved, and no polling occurs while both surfaces are hidden.

The packet version and request token must match before the snapshot is applied.
Zone boundaries clear both points and skills and delay the next request five
seconds; late replies cannot restore the old snapshot. Malformed skill values
reject the complete snapshot. An older server's unsupported-opcode reply stops
polling until the next zone/reload; there is no command fallback. Values remain
unknown until the packet endpoint is installed and replies successfully.

The server routes HELM opcodes 0x80–0x8F independently of storage proximity.
Void Storage and Gear Vault keep their existing opcode ranges. Full wire
layout, installation and rollback are in the server handoff
`documentation/custom/helm-skill-readout.md`.

## Validation

`lua tests/ascensionxi_helm.lua C:/repos/axi-helm-readout` passes, exercising
the actual addon codec against the server Lua endpoint and shared router.
It covers polling, correlation, malformed replies, rate limits, unsupported
servers, zone resets and unchanged player-only `!points` output.
`lua tests/run_tests.lua` passes 7,499 checks and `lua tests/smoke_ui.lua`
passes 1,575 checks, including the simplified AXI surfaces and percentages.
The server's standalone `lua tools/tests/helm_status.lua` also passes.

Live packet capture and owner confirmation on September 15 established that
the deployed server responds and the fixed addon displays the values. The
release smoke check remains: sync the packaged addon on a normal installation,
open Gathering Gear, then confirm points refresh after earning/spending and
after zoning. Check the compact bar and equipping near a Point. The working
copy used for playtesting is a Git checkout, so launcher delivery needs its
own check after promotion.
