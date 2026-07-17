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
| Precast / Midcast | `any`, `skill` (Enfeebling Magic, Singing, ...), `magicType` (White/Black Magic, Bard Song, ...), `element` (Fire..Dark), `songType` (Buff/Debuff — small static list of debuff families), `contains` (substring: "Madrigal" matches Blade+Sword, "Stone" every tier; legacy alias `family`), `group` (action name is in the named Groups list — single name or list-OR; ADR 0009), `name`, `dayWeatherBonus` (net day+weather sign for the spell's element) |
| Ability | `any`, `abilityType` (Blood Pact: Rage/Ward, Corsair Roll, Quick Draw, Ready, Rune Enchantment), `contains`, `group`, `name` |
| Item | `name`, `contains`, `group` |
| Weaponskill | `any`, `name`, `group` |
| Preshot / Midshot | `any` |
| **every handler** (v54) | Player-state gates, raw AND percent variants: `playerHPBelow`/`playerHPAbove`, `playerHPPercentBelow`/`playerHPPercentAbove` (0–100), `playerMPBelow`/`playerMPAbove`, `playerMPPercentBelow`/`playerMPPercentAbove` (0–100), `tpBelow`/`tpAbove` (raw TP, 1000 = a full shot), `buff`/`buffNot` (active status effect by name — case-insensitive — or numeric id). Strict compares. Tier 95, just under `mode`. Buffs resolve through a per-dispatch cache of the client's own buff array; unreadable state matches NEITHER polarity, so a failed read never flaps gear. The v53 spellings (`hpBelow`… percent semantics) load as hidden aliases. |

**OR groups (v54).** A rule may carry `whenAny = { { buff = "Sleep" }, { buff = "Lullaby" } }`
beside `when`: the rule matches when ALL `when` conditions hold **or** ANY `whenAny` entry
holds (an entry with several keys is AND within itself). An OR-only rule (empty `when`) is
NOT always-on — only its `whenAny` leg counts. Unknown keys in either leg drop the rule
with a chat warn. `ruleLabel` appends the OR leg after `|` (rules without `whenAny` label
exactly as before, so existing pin scope keys keep matching); the default priority scans
both legs. Field case: Toxin Earring poison-wakeup — `whenAny` of Sleep OR Lullaby → the
WakeMeUp set.

v2 candidates (matcher is an open table; additive): day/weather/moon beyond the obi rule,
area, target type, subjob.

## Evaluation (ADR 0003)

Every matching Trigger applies: sort priority ascending, `EquipSet`/inline-equip each in order —
later overlays earlier per slot. Full sets are replacements; partial sets are layers.
Specificity defaults: Any 10 · skill/status 20 · class/element 30 · family/contains 40 ·
**group 45** · exact name 50 · **Automations 60** · Mode 100. Ties: file order. A `group`
rule is a baseline a per-spell `name` rule overrides, and still beats `contains` / `skill`.

Groups are stored in a `Groups` section of the trigger file, beside `Modes` — a named,
untyped list of action names per Job entry (`Groups = { StrBlue = { 'Quad. Continuum', ... } }`).
The section round-trips through the serializer like `Modes`. G1 is the engine (matcher +
storage); **G2 (issue #25) adds the GUI** — a top-level **Groups tab** (create / rename / delete
groups, add / remove typed members; `gear/groupsmodel.lua` is the pure CRUD core) and a `group`
condition in the trigger editor whose value is a dropdown of the current job's groups. A rule
pointing at a missing / renamed group is surfaced as `[missing group]` (parity with a missing
set; hard rule 12), never a silent no-op. Free-name member typing for now; the searchable
spell/ability browse-list picker is a later slice (issue #12).

## Modes

Named flags, dlac-owned. Toggled from the Triggers tab or `/dl mode <name> [on|off|toggle]`
(macro-able). The engine mirrors every change to `modestate.lua` and reads it back on load,
so flags survive a Reload LAC exactly like a dlac reload — one lifetime rule. Guardrails:
restore is same-job only (`__job` stamp) and recent-only (1 h — a mid-session reload heals,
last Tuesday's DT-mode stays dead), and `maxmp` drops itself the moment the main job changes.

## Automations (ADR 0004)

**Virtual slot entries** ("slot functions", ADR 0004 4th revision): a set slot holds a marker
alongside its regular items — `dlac:AutoStaff` (Main), `dlac:AutoObi` (Waist) — added via the
Sets tab's `+ Add` picker and committed into `sets.Dynamic` like any entry. `BuildDynamicSets`
flattens it WITH the slot's normal best-by-level pick as fallback (`dlac:AutoStaff|Maple Wand`);
the engine resolves at equip time, level-gated (manifest entries record item levels — an
under-leveled Chatoyant is not a candidate), equips the fallback when unresolvable, and drops
the slot only when there's no fallback. Gear data comes from a GUI-derived manifest
(`<char>\dlac\autogear.lua` — the engine never loads the catalog), regenerated automatically
on login / job change alongside the gear.lua auto-sync (the Automations Rescan button is a
manual override). Obis: the eight elemental ones are preferred for their element, with the
universal Hachirin-no-obi as the owned fallback:
- **dlac:AutoStaff**: tiered Iridescence pick per cast — elemental staves carry it for their own
  element only (NQ +1 / HQ +2), universal weapons for all elements (Iridal Staff +1, Chatoyant
  Staff / Foreshadow +1 = +2). Higher tier wins; ties go to the universal, which also covers
  elementless actions (e.g. Ability triggers).
- **dlac:AutoObi**: action element E, net day/weather > 0, obi owned → equip in Waist.
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

## GUI: Groups tab (G2, issue #25)

Fifth tab (uihost registry, after Triggers). Edits the same trigger file's `Groups` section:
create / rename / delete groups and add / remove members by **typing** action names (free-name).
Modeled on the Modes builder — a per-group box (members listed with remove buttons, a typed-member
input, rename / delete) and a `+ Group...` create popup. The pure CRUD + name/member validation
core is `gear/groupsmodel.lua` (Ashita/imgui-free, headless-tested TGM*); the Groups tab and the
Triggers tab share one `trig.data` / one Commit, so they never stomp each other's file writes.

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
