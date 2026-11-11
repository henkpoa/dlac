# AXI-26: decimal HELM skill on the compact surfaces

Implemented from DLAC main `c5654e6`, November 11, 2026, on
`codex/axi-26-helm-skill`. Owner approved reuse of the existing skill data and
required AscensionXI-only behavior. Keep this task in one DLAC PR.

## Behavior and scope

The ticket screenshot shows `dlac Hobbies` on its HELM tab and the small
active-hobby badge. Both now show the current gathering category and skill
to one decimal place, e.g. `Skill: Excavation 42.7` and
`HELM · Excavation 42.7`. Existing points, gear bonuses, arm switch and Off
button retain their behavior. No new window, category picker or setting.

The AscensionXI `gathering` provider owns `compactSkill(category)`. It reads
the same skills snapshot as the full Gathering Gear page and touches the same
five-second request owner. The visible badge can therefore refresh without
opening the larger window, and displaying both sends no duplicate request.
Unknown/reset skill is `--`, real zero is `0.0`, and the cap is `100.0`.

Shared `ui/helmbar.lua` and `ui/idlefloat.lua` only consume this optional
provider method. Only `servers/ascensionxi/modules/helm/init.lua` supplies it,
and the method additionally requires `serverpack.active() == 'ascensionxi'`
before touching the request owner or returning text. CEXI and neutral packs
cannot use it even if a stale provider is registered. Other hobbies and the
existing CEXI venture-points/rating display are unchanged. No CEXI pack files,
server gameplay code, packet format, skills or character data are modified.

## Verification

`tests/ascensionxi_helm_ui.lua` executes the real packet decoder/provider and
both real render paths against a recording ImGui stub. Its 42 checks cover
all four categories, tenths/zero/cap, skill-up refresh, unknown/reset state,
badge-only polling, no duplicate polls, hidden/collapsed badges, other
hobbies, existing gear bonuses/Off control, CEXI output and request isolation,
neutral mode and an intentionally stale AXI provider under CEXI.

Local passes:

- New UI suite: 42 checks, on Lua 5.4 and the native LuaJIT runtime.
- Existing `tests/ascensionxi_helm.lua` packet/skill/polling tests.
- Existing `tests/server_pack_isolation.lua`.
- Core `tests/run_tests.lua`: 8,083 checks.
- `tests/smoke_ui.lua`: 1,778 checks.
- `tests/imgui_percent_literals.lua`: 268 files.
- `tests/pack_lint.lua ascensionxi`: 49 checks; `cexi`: 39 checks.

The new suite is included in `.github/workflows/ci.yml`. Run the commands
above with Lua 5.4 from the checkout root. Local Lua 5.4 uses the existing
`C:/Claude/pr1083-lua-runtime` installation via `C:/Claude/axi26-run-lua.py`;
LuaJIT uses the existing server DLL through `C:/Claude/axi6-run-lua.py`.
No new runtime packages were installed. Local logs are `C:/Claude/axi26-*.log`.
Two temporary negative controls were also caught: removing the AXI-only guard
fails the stale-provider isolation assertion, and dropping decimal precision
fails the visible skill assertion. Original bytes were restored and all 42
checks passed again. Local runner: `C:/Claude/axi26-check-controls.py`.

## Review and release

Installed locally at the owner's request into
`C:/Spel/AscensionXI - Staging/Ashita/addons/dlac`. The Local launcher profile
uses `C:/Projects/AscensionXI`, and the addon's server flag explicitly selects
`ascensionxi`. Its existing `.git` marker protects this working copy from
launcher addon updates. All three affected runtime files matched the reviewed
baseline before installation; only those three files were replaced, with
byte-for-byte verification afterward. Other local addon work was preserved.

Original files and a SHA-256 manifest are in `C:/Claude/axi26-local-backup/`;
the installation record is `C:/Claude/axi26-install-local.py`. The 42 compact
UI checks passed against the **installed modules** using native LuaJIT.
No running client was controlled. The owner reviewed the installed display,
confirmed it works locally and requested merge. The final isolation/decimal
negative controls were rerun at acceptance; both were caught, and the
restored 42-check UI suite passed. No runtime changes followed acceptance.

No launcher pin, catalog refresh, version bump or production release is
included. At release, follow
`ascensionxi-release-routine.md` to publish/pin the reviewed DLAC revision;
this implementation needs no game-server deployment or restart.

Client test: reload with `/addon reload dlac`, then open `/dl helm bar`. Select HELM
in the Hobbies window and arm gathering near a point. The bar and badge should
name that category and display the same decimal as the full Gathering Gear
page. Gather a skill-up and allow five seconds for refresh. Close the Hobbies
window and confirm the badge still updates. Zone and check `--` changes to
the new snapshot after settling. Hide the badge and verify the existing
preference still works. On CEXI, category, VP/rating and Off behavior must
remain unchanged. Local client acceptance is complete.

Rollback the three runtime file changes and reload DLAC; no persisted data
needs migration. Keep any corrections in this task's PR.

## Ready-to-paste wiki text after release

**DLAC guide, existing Hobbies/HELM section:**

> On AscensionXI, the HELM tab and small HELM badge show your current gathering
> skill to one decimal place, such as **Excavation 42.7**. They refresh
> automatically while visible. **--** means the skill readout is still loading.

**Custom Changes, under HELM/DLAC:**

> DLAC's HELM tab and active HELM badge now show decimal skill progress for
> your current gathering type.

Preserve the existing guide layout and map pins. These are release drafts;
no live wiki page has been edited.
