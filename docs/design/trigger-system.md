# Trigger system — design

Status: agreed 2026-07-10 (grilling session). Decisions of record: ADR 0002 (data-driven dispatch),
ADR 0003 (overlay semantics), ADR 0004 (automations). Glossary: /CONTEXT.md.

## Goal

Replace the last hand-written Lua in a LuaAshitacast profile — the Handle* logic — with data
edited in the dlac GUI, so a player who can't (or won't) code gets full gear automation:
status sets, ability/item/spell sets, modes, and staff/obi automation.

**Product rule: nothing dlac ships may FORCE a player to open or edit a Lua file.** Every
capability gets a GUI path (Setup wires profiles, the Triggers tab edits rules, buttons toggle
modes). The Lua files remain hand-editable for power users — they are storage, not interface.

## Architecture (ADR 0002)

Two Lua states. The dlac addon (GUI) writes *data*; the seeded library (`dlac\utils` required by
the profile, refreshed on every addon load) evaluates it inside LAC where `gFunc.EquipSet` lives.

```
<JOB>.lua (written once by Setup)          <char>\dlac\triggers\<JOB>.lua (written by GUI)
  HandleDefault:                             return {
    sets = utils.rebuildSets(sets)             Default  = { {when={status='Engaged'}, set='Tp_Default'}, ... },
    utils.dispatch('Default')      ──reads──▶  Midcast  = { {when={song='Minuet'},   set='Minuet'}, ... },
  HandleMidcast:                              }
    utils.dispatch('Midcast')
```

- `dispatch(event)` fetches `gData.GetPlayer()` / `gData.GetAction()` itself — profiles carry no logic.
- Trigger files hot-reload (mtime check) — no `/lac reload` after a trigger edit. Sets still need reload.
- Handlers shimmed: Default, Precast, Midcast, Ability, Item, Weaponskill, Preshot, Midshot.
- Migration is append-only: Setup adds the dispatch line at the END of an existing handler; user
  code is never removed. dispatch runs last → dlac wins per-slot where configured.
- Setup is an idempotent VERIFIER: for every handler it checks (a) the function exists,
  (b) it contains `utils.dispatch('<Event>')`, (c) the dispatch call is the LAST statement
  (after `rebuildSets` in HandleDefault). Missing handlers are created, missing shims appended,
  present-but-not-last shims reported. The GUI setup warning reflects per-handler shim health.
  Same safety rails as setmanager: backup + parse-check before any write.

## Trigger shape

```lua
{ when = { <conditions, ANDed> },
  set = 'SetName'  |  equip = { Waist = 'Karin Obi' },   -- action: set name or inline slot map
  priority = 40,                                          -- optional; default = specificity tier
}
```

## Condition vocabulary (v1)

All matched against live LAC data (luashitacast data.lua / constants.lua) — no database needed
at dispatch time:

| Handler | Conditions |
|---|---|
| Default | `status` (Engaged/Resting/Idle), `moving`, `mode` (user-defined name) |
| Precast / Midcast | `any`, `skill` (Enfeebling Magic, Singing, ...), `magicType` (White/Black Magic, Bard Song, ...), `element` (Fire..Dark), `songType` (Buff/Debuff — small static list of debuff families), `family` (name-group: "Minuet" matches all tiers), `name`, `dayWeatherBonus` (net day+weather sign for the spell's element) |
| Ability | `any`, `abilityType` (Blood Pact: Rage/Ward, Corsair Roll, Quick Draw, Ready, Rune Enchantment), `family`, `name` |
| Item | `name`, `family` |
| Weaponskill | `any`, `name` |
| Preshot / Midshot | `any` |

v2 candidates (matcher is an open table; additive): MP%/TP/HP% thresholds, active buffs,
day/weather/moon beyond the obi rule, area, target type.

## Evaluation (ADR 0003)

Every matching Trigger applies: sort priority ascending, `EquipSet`/inline-equip each in order —
later overlays earlier per slot. Full sets are replacements; partial sets are layers.
Specificity defaults: Any 10 · skill/status 20 · class/element 30 · family 40 · exact name 50 ·
**Automations 60** · Mode 100. Ties: file order.

## Modes

Named flags, session-only (reset on load). Toggled from the Triggers tab or `/dl mode <name>
[on|off|toggle]` (macro-able; the command is handled in the LAC state where mode state lives).

## Automations (ADR 0004)

Engine-generated Triggers at band 60, from owned gear. **Activation is per set, two independent
flags**: `SetOptions = { <SetName> = { staff=, obi= } }` in the trigger file, edited from the
Sets tab ("Auto staff" / "Auto obi" checkboxes on the selected set); fires on ANY handler whose
matched triggers equip a flagged set. Gear data comes from a GUI-derived manifest
(`<char>\dlac\autogear.lua`: best owned staff/obi per element, the Iridescence weapon name —
the engine never loads the catalog):
- **Auto staff**: tiered Iridescence pick per cast — elemental staves carry it for their own
  element only (NQ +1 / HQ +2), universal weapons for all elements (Iridal Staff +1, Chatoyant
  Staff / Foreshadow +1 = +2). Higher tier wins; ties go to the universal, which also covers
  elementless actions (e.g. Ability triggers).
- **Auto obi**: action element E, net day/weather > 0, obi owned → equip in Waist.
  Always element-gated, independent of Iridescence.

## Debugging

`/dl why` — trace of the last dispatch: which triggers matched, their order, what each equipped.
Also surfaced as a GUI view (Triggers tab, "Explain last action").

## GUI: Triggers tab

Fourth tab. Sections = Handlers. Each section lists rules (condition → set/item → priority chip).
Browse lists (all spells/abilities, search, "usable now" incl. subjob) support **multi-mark →
assign one set to N marked entries** in one action. Mode toggle buttons live in the Status &
Modes section. Automations section holds the option checkboxes + the explain view.
The browse lists degrade gracefully until the picker database exists (typed-name rules only).

## Picker database (GUI-only concern)

Per-job ability/spell acquisition levels (incl. subjob availability + main-only flags, e.g.
/SCH37 → Light Arts, Stratagems, Sublimation). Source to investigate in order: CatsEyeXI live
API endpoints → CatsEyeXI/LSB server SQL (`abilities.sql`, `spell_list.sql`). Ships as generated
data files (per ADR 0001), same pattern as catalog.lua. Not required for dispatch correctness.

## Milestones

1. **Engine** — dispatch module (matchers, overlay, hot-reload, inline equip), `/dl mode`,
   `/dl why`, shim writer in Setup + starter profile, per-handler shim detection/repair
   (idempotent Setup). Testable in-game with a hand-written trigger file, no GUI.
2. **Automations** — modifier_map extension (Iridescence, Staff Bonus, Affinity, ...) + re-crawl;
   staff/obi rules + option toggles.
3. **Triggers tab** — sections, rule editing, multi-mark assign, mode buttons, commit/hot-reload.
4. **Picker database** — source investigation, generator, `abilities.lua`/`spells.lua`, browse
   list integration ("usable now" with subjob rules).
5. **Polish** — Sets-tab cross-reference ("triggers using this set"), optional mode mini-HUD,
   README/docs for end users.
