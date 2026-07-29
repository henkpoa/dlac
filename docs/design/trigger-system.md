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
| Default | `status` (Engaged/Resting/Idle), `moving`, `inTown` (v84 — see below), `mode` (user-defined name) |
| Precast / Midcast | `any`, `skill` (Enfeebling Magic, Singing, ...), `magicType` (White/Black Magic, Bard Song, ...), `element` (Fire..Dark), `songType` (Buff/Debuff — small static list of debuff families), `contains` (substring: "Madrigal" matches Blade+Sword, "Stone" every tier; legacy alias `family`), `group` (action name is in the named Groups list — single name or list-OR; ADR 0009), `name`, `dayWeatherBonus` (net day+weather sign for the spell's element — the obi's logic), `weatherMatch` (the spell's element equals the CURRENT weather element — a plain weather match, no day and no opposition; single/double weather and a Scholar's own storm all count; engine v121), `dayMatch` (the spell's element equals TODAY's day element — a plain day match, no weather and no opposition; engine v156) |
| Ability | `any`, `abilityType` (Blood Pact: Rage/Ward, Corsair Roll, Quick Draw, Ready, Rune Enchantment), `contains`, `group`, `name` |
| Item | `name`, `contains`, `group` |
| Weaponskill | `any`, `name`, `group` |
| Preshot / Midshot | `any` |
| **every handler** (v54) | Player-state gates, raw AND percent variants: `playerHPBelow`/`playerHPAbove`, `playerHPPercentBelow`/`playerHPPercentAbove` (0–100), `playerMPBelow`/`playerMPAbove`, `playerMPPercentBelow`/`playerMPPercentAbove` (0–100), `tpBelow`/`tpAbove` (raw TP, 1000 = a full shot), `buff`/`buffNot` (active status effect by name — case-insensitive — or numeric id). Strict compares. Tier 95, just under `mode`. Buffs resolve through a per-dispatch cache of the client's own buff array; unreadable state matches NEITHER polarity, so a failed read never flaps gear. The v53 spellings (`hpBelow`… percent semantics) load as hidden aliases. |
| **action handlers** (v81) | `target` — WHO the action is aimed at; v1 vocabulary: `Self` (the action targets YOU). Field case: waltz potency reads the **target's** VIT beside your CHR, so a self-waltz wants a VIT+CHR set while waltzing someone else keeps the plain CHR set. Live read: `gData.GetActionTarget().Index` (LAC stores the outgoing action packet's target index for Spell/Ability/Item/WS/Ranged before Precast fires) vs my own party index, once per dispatch (`ctx.targetSelf`, tri-state). Unknown target (Default handler, failed read) and unknown values match NOTHING — a target rule never fires blind. Tier 55: a self-refined rule overlays its base `name`/`contains`/`group` rule with no hand priority, under Automations (60). GUI: a `target` dropdown on Precast/Midcast/Ability — one value today, the list shape is deliberate (more answers slot in: party member, enemy, ...). |
| **Default** (v84) | `inTown` — am I standing in a town? `true` = in a town (the classic `status = 'Idle'` + `inTown = true` → show off your gear in the cities), `false` = NOT in a town (a field-idle set). Town = the **curated set in `data/zones.lua`** (generated by `tools/gen_zones.py` from the server's `zone_settings.sql`, stable branch): every `zonetype & CITY` zone **plus Nashmau** (a real town the server mistypes as OUTDOORS — its `misc` even carries AH + Nomad Moogle), **minus** combat-staging CITY zones (Sealion's Den, Outer RaKaznar) and the demo stub. Celennia Memorial Library (284, the Wings hangout) is a genuine SoA CITY zone, so it counts for free. `data/zones.lua` also carries each zone's raw `zonetype`/`misc` masks, so it later powers `IN_DYNAMIS` (`zonetype & 0x80`) etc. Live read: `GetParty():GetMemberZone(0)`, memoized on `ctx.zone` like `targetSelf`; an unknown zone (failed/headless read, or the demo zone 0) matches NEITHER polarity, so a rule never fires blind. Tier 95 (a location gate, beside the player-state band): a town set decisively overlays the plain Idle set, while `mode` still wins. The engine accepts `inTown` on **any** handler; the GUI offers it on Default, where "idle in town" lives — a `flag` on the Default row with a live `[on now]` marker. |
| **every handler** (v63) | Pet conditions, off `ctx.pet` = `gData.GetPet()` read once per dispatch: `pet` (true/false — a LIVING pet exists; GetPet is nil petless AND at pet HPP 0, so a dead pet counts as none and `pet = false` fires), `petStatus` (the pet's own Idle/Engaged — `status = 'Idle'` + `petStatus = 'Engaged'` is the classic "master idle while the pet fights"), `petName` (exact, case-insensitive — avatar/spirit identity, SMN perpetuation gear). `petStatus`/`petName` IMPLY existence: they never match petless. Tiers: `pet` 22 / `petStatus` 23 sit between `status` (20) and `moving` (25), so a pet-refined rule outranks its base status rule with no hand priority and Movement still overlays; `petName` 50 = the identity (name) tier. GUI: a second cascading **Pet** row beside Player (HasPet / NoPet / PetStatus / PetName) with live `[on now]` markers. Ecosystem survey behind the design: `docs/reference/pet-handling-other-luas.md`. |

**`weatherMatch` vs `dayWeatherBonus` (engine v121, 2026-07-24 grilling; ADR 0018).** These are two
DIFFERENT environment tests, kept as separate conditions on purpose. `dayWeatherBonus` is the
obi's SIGNED net — +1 per matching day/weather, −1 per the opposing element, favourable when
> 0. `weatherMatch` is a plain equality: the spell's element == the current weather element,
with no day term and no opposition. The driver was Scholar cast-time gear (Argute/Pedagogy,
server mod `ALACRITY_CELERITY_EFFECT`): its "+10% casting & recast under Celerity/Alacrity"
was verified against the CatsEyeXI server (`battleutils.cpp` — `WeatherMatchesElement` over
`GetWeather(…, false)`) to key on **weather only**, single or double, counting the caster's
own storm — so gating that set on `dayWeatherBonus` (net) would both over- and under-fire.
`weatherMatch` reads the same `gData.GetEnvironment().WeatherElement` (storm-aware) the obi
uses; tier 30 (element band); offered on Precast + Midcast (cast-time snapshots at Precast,
recast at Midcast). The buff gate (Celerity for white magic / Alacrity for black) is left to
the player to compose via the existing `buff` conditions — `weatherMatch` is the minimal
reusable primitive, nothing bundled. Tests WM1–WM21.

**`dayMatch`, the third environment test (engine v156; ADR 0029).** Henrik, field: *"there are
items that give you bonus solely if the day match what you're casting."* `dayMatch` is the day
half of the above, alone: the spell's element == TODAY's day element, no weather term and no
opposition. It is a THIRD condition because neither neighbour tracks a day-only bonus — the
same both-directions proof ADR 0018 ran for weather, for a Fire spell: on **Firesday in Water
(opposing) weather** the net is +1 −1 = 0, so `dayWeatherBonus` is quiet while the item IS
paying out (under-fires); on **Earthsday in Fire weather** the net is +1, so `dayWeatherBonus`
fires while the item is dark (over-fires). `weatherMatch` has no day term at all, so it is the
wrong axis outright. `dayMatchesAction` reads `gData.GetEnvironment().DayElement` — the same
field `netForElement` already scores, so the net's day half and this condition can never
disagree — cached on `ctx.del` beside `weatherMatch`'s `ctx.wel`; tier 30; Precast + Midcast;
unknown day or no action element matches NEITHER polarity. **The asymmetry to know:** there is
no "clear day" — all eight weekdays carry an element — so a readable day is always a real match
or a real non-match, and only a broken read is unknown; weather's genuine `None` (Clear /
Sunshine / Clouds / Fog) has no day counterpart. Day is also **not** storm-aware (nothing in
game changes the day), unlike the weather read. Unlike ADR 0018 this one is **not** pinned to a
named server mechanic — it ships as a calendar primitive, and pinning a specific item's exact
gate is a follow-up. Tests DM1–DM24 (DM14–DM17 pin the independence from both neighbours).

**OR groups (v54).** A rule may carry `whenAny = { { buff = "Sleep" }, { buff = "Lullaby" } }`
beside `when`: the rule matches when ALL `when` conditions hold **or** ANY `whenAny` entry
holds (an entry with several keys is AND within itself). An OR-only rule (empty `when`) is
NOT always-on — only its `whenAny` leg counts. Unknown keys in either leg drop the rule
with a chat warn. `ruleLabel` appends the OR leg after `|` (rules without `whenAny` label
exactly as before, so existing pin scope keys keep matching); the default priority scans
both legs. Field case: Toxin Earring poison-wakeup — `whenAny` of Sleep OR Lullaby → the
WakeMeUp set.

**Cases (v127, PRD #124, ADR 0023).** A second `&`/`|` tier. A rule gains an optional
`cases = { { op = '&'|'|', when = {...}, whenAny = {...}? }, ... }` — each case carries an
operator plus the **same two legs a body has**, and matches internally by the same one
sentence: *`&` things bind into one together-block; each `|` thing stands alone; fire if the
together-block holds, or any `|` thing does.* At the rule tier the `&` members are the body's
`&` leg + every `& case`; the standalone `|` things are the body's `whenAny` entries + every
`| case`. The empty-together-block law generalizes — no `&` member (empty body leg, no `& case`)
is never always-on. Cases cannot contain cases (hard one-tier cap).
- **Canonical serialization is oldest-form-first.** A `| case` with only `&` conditions
  serializes as a multi-condition `whenAny` entry in the *existing* schema, so `(A & B) | (C & D)`
  is evaluated by every addon version ever shipped. Only `&` cases and `| cases` with an internal
  `|` leg use the new `cases` list.
- **Version guard.** Any rule serialized with a surviving `cases` list also gets
  `hasCases = true` stamped in its body — this engine registers it as an always-true matcher at
  the bottom tier and strips it on load; an older engine sees an unknown key and drops the rule
  with the standard warn (warn, never misread). Auto-priority spans every leg of every case; the
  guard (tier 10, the floor) never moves it. `ruleLabel` extends over cases deterministically
  while case-less rules label byte-for-byte as before. `/dl why` names the winning case
  (together-block / a standalone / `case a & (x | y)`). The rule builder emits cases as of
  the editor slice (below); the rule list and `/dl why` render/name cases-list rules today.

**One value per condition type on the & leg.** `when` is a Lua *map*, so a condition type
appears at most once — and stacking two would be meaningless anyway (`name = "test"` AND
`name = "testar"` can never both hold; every matcher compares ONE value, `mode` alone reading
a list, as OR). The rule builder therefore *replaces* when you add a type that is already on
the & leg. That is right when you are correcting a value and wrong when you meant "either",
so since v2026.07.25h it is never silent: the popup names the swap it made
(`name replaced: test -> testar`) and offers **Match either instead**, which moves BOTH values
to the | leg. Field case (Henrik, 07-25): Item rule, `name = test` then `name = testar` — the
second ate the first with nothing said, and it read as "I cannot add & conditions any more".
The same-type test is case-insensitive: the pickers spell keys as the defs do (`magicType`),
an edited rule loads them lowercased off the file, and the save lowercases both — a
case-sensitive test let an edit stack two rows of one type, of which the save kept one.
`triggersui._pushCond` / `._orBothToAny` are the pure seams; tests TB1–TB32 (`smoke_ui`) cover
them and drive the real popup frame by frame.

**Trigger cases — read-side (engine v125, issue #125, slice 1/5 of PRD #124).** The
display vocabulary over the *existing* `whenAny` schema — no schema change, no editor
change. The rule body is **case 1**, the **together-block** (its `&` leg). Each `whenAny`
entry is a **standalone alternative**: a *single-condition* entry is a plain standalone `|`
condition, a *multi-condition* entry (AND-within-OR) is a **`| case`**. The read surfaces
became case-aware:
- **Rule list** (`ui/triggersui.lua`, `caseSplit`): single-condition entries render as `|`
  lines exactly as before; each multi-condition entry renders as a bordered, indented
  `| case` box with the together-block `& ` prefix on its 2nd+ conditions. A rule with no
  multi-condition entry renders pixel-identical to today (zero new chrome for the 99%). A
  case box carries one live `[on now]`/`[off now]` — the whole case ANDed — but only when
  every condition is a player-state gate (`caseLiveHolds`; an action condition can't be
  judged at idle, so it shows no marker rather than a wrong one).
- **`/dl why`** (`dispatch.matchedCase`): the winning rule's line names its matched case —
  `[via together-block]`, `[via standalone <k=v>]`, or `[via case <a & b>]`. Mirrors
  `matches()` with the engine's own MATCHERS (together-block first, then the first `|` entry
  that holds in file order); folded into the retrace signature so a rule that switches cases
  re-names. A case-less rule names nothing — `/dl why` reads byte-for-byte as before.
- **Priority chip**: now passes `whenAny` to `defaultPriority` (both legs), matching the
  engine — a rule whose highest tier lives on the `|` leg no longer displays low.
Vocabulary: **case**, **together-block**, **standalone alternative** — never "group" (spell
groups own that word). Tests: engine `CS1-CS10`, render `TC1-TC10`.

**Trigger cases — edit-side (addon v2026.07.26f, issue #127, slice 3/5 of PRD #124).** The
rule builder gains exactly two buttons — **+ & case** and **+ | case** — and renders added
cases as bordered boxes below the rule body: together-block (`&`) cases first, an `-- or --`
divider, then standalone (`|`) cases. **A rule with no added cases renders as before, plus
only the two buttons** (box chrome exists only while cases exist). Each box hosts the
*identical* condition flow the body uses — the same shared picker, the same
`+ & condition` / `+ | condition` buttons, the same repeat-replaces contract (`pushCond`) and
the same **Match either instead** escape — so there is nothing new to learn inside a case.
- **Loading** (`triggersui._loadCases`): the flatten-corruption fix. A body `whenAny`
  *single-condition* entry stays a body `|` row (as before); a *multi-condition* entry loads
  as a `| case` box instead of flattening to separate `|` rows; each `cases`-list entry loads
  as its box. A multi-condition `|` rule now round-trips **byte-identically** (test TE10).
  One depth the editor cannot represent (one-tier cap): a hand-written *combined* `|` entry
  **inside** a case, which the engine honors as AND-within-OR. It splits to standalone `|`
  rows on load — **with a note on the case box, never silently** (v2026.07.26g; the `&` leg's
  law one tier down), and Cancel keeps the file as written.
- **Saving** (`_buildLegs` + `_buildCases`): the body legs and each case's legs are rebuilt
  and handed to `dispatch.serializeTriggers`, which owns canonicalization — a `| case` of only
  `&` rows folds back to the oldest `whenAny` form (no guard); only `&` cases and `| cases`
  with an internal `|` use the new list and carry the guard. **An empty case is never saved
  silently**: the popup refuses Save while one exists and says so.
- Deferred to the completion slice (not built here): copy-case, "Match either instead" between
  cases, hover help beyond the button tooltips, chrome polish. Tests: pure seams + real-popup
  frame drive `TE1-TE53` (`smoke_ui`).

**Field iteration 1 (addon v2026.07.26h, Henrik's first click-through, 2026-07-26).** Two
reads, both structural:
- **The shared picker sits at the TOP of the popup, outside every container.** Rendered
  between the body rows and the case boxes it read as owned by case 1 forever. Now:
  `condition:` picker row first, a separator, then the containers — and every container
  (the body included) carries its own `+ & condition` / `+ | condition` buttons below its
  rows, the same rows-then-buttons shape throughout. (TE49)
- **Case 1 is a real case.** With no added cases the body renders flat, exactly as before
  (the 99% see nothing new). Once a case exists the body renders as **case 1** — a box like
  every other, with the same **top-right AND/OR selection** every box has; it used to be the
  one case whose type only the system could set. Flipping any box moves it across the
  `-- or --` divider on the fly. (TE50–TE51)
  - **Case 1 = OR saves an empty body**: its rows ride the cases list as the leading
    `| case` (`_buildRuleShape`); the engine's OR-only law (`matches()`: `nAnd > 0`) keeps
    such a rule from ever being always-on (TE48, TE52), and the serializer still folds
    oldest-form when it can — a pure-OR rule round-trips byte-identically through the
    case-1 seat (TE47).
  - **An empty-body rule seats its first case as case 1 on load** (op and split-note ride
    along), so the editor never shows an empty un-savable body box (TE45); deleting case 1
    promotes the next case into the seat (TE53).

**Field round 2 (addon v2026.07.26m, 2026-07-26).** Henrik's `/dl why` screenshot witnessed
the case-naming live — and showed a rule labeled `any#|(any|status=Engaged)#|(any|status=
Resting)`: both conditions were added with `+ |`, so each case saved as
`{ when = {}, whenAny = { {..} } }` — an empty `&` leg plus a one-entry `|` leg, which the
serializer's oldest-form fold cannot reach (it only folds cases with no internal `|`), so
the rule also carried a `hasCases` guard it did not need. **Canonical case legs**
(`triggersui` `foldLoneAny`, applied in `_buildCases` and to case 1 in `_buildRuleShape`):
a case whose `&` leg is empty and whose `|` leg holds exactly ONE entry folds that entry
into the `&` leg — identical semantics (with one lone entry the two legs say the same
thing), and the whole chain then collapses: Henrik's exact rule re-saves as the OLD pure-OR
form (`whenAny` two entries, no cases list, no guard) and `/dl why` names the winner
`standalone status=Resting` instead of `case (status=Resting)`. The BODY never folds —
case-less labels stay byte-for-byte stable. Already-saved noisy rules canonicalize on
their next edit-save. (TE54–TE56)

v2 candidates (matcher is an open table; additive): day/weather/moon beyond the obi rule,
subjob. (`area` landed in v84 as `inTown`, off the server-derived `data/zones.lua` town set;
more zone predicates — a specific-zone match, `IN_DYNAMIS` — reuse the same file. Target
landed in v81 with `Self`; more target answers — party member, enemy, NPC — extend its
dropdown, not the vocabulary.)

## Evaluation (ADR 0003)

Every matching Trigger applies: sort priority ascending, `EquipSet`/inline-equip each in order —
later overlays earlier per slot. Full sets are replacements; partial sets are layers.
Specificity defaults: Any 10 · skill/status 20 · **pet 22 / petStatus 23** · moving 25 ·
class/element 30 · family/contains 40 · **group 45** · exact name/petName 50 ·
**target 55** · **Automations 60** · player state 95 · Mode 100. Ties: file order. A `group`
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
  element only (NQ +1 / HQ +2), universal weapons for all elements (+1..+3 per the catalog:
  Iridal/Ephemeron +1; Chatoyant, Foreshadow +1 and the other job-specific customs +2;
  Inanna/Keraunos/Gridarvor and the Lv75 relic staves +3 — engine v82 reads the manifest's
  preference-ordered `universals` ladder, first rung usable at the live level). Higher tier
  wins; ties go to the universal, which also covers elementless actions (e.g. Ability triggers).
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
