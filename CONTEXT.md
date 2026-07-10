# dlac

dlac ("dynamic LuaAshitacast") is an Ashita v4 addon for CatsEyeXI that lets players build and drive LuaAshitacast equipment sets through a GUI, instead of hand-editing Lua profiles.

## Language

**Catalog**:
The full CatsEyeXI equipment reference (`catalog.lua`), crawled from the live API — base-truth stats for every item, keyed by Id.
_Avoid_: item database, item list

**Owned gear**:
The per-character ownership record (`gear.lua`): thin entries for items the character actually possesses, auto-synced from bags; stats derive from the Catalog by Id.
_Avoid_: inventory (that means the in-game bags themselves)

**Dynamic Set**:
A set authored as ordered per-slot candidate lists under `sets.Dynamic`; dlac flattens it to the best eligible piece per slot for the current level.
_Avoid_: level-scaling set, scaling set

**Flattened Set**:
The plain slot→item table produced from a Dynamic Set by `rebuildSets` — what LuaAshitacast actually equips.

**Handler**:
One of LuaAshitacast's profile event functions (`HandleDefault`, `HandlePrecast`, `HandleMidcast`, `HandleAbility`, `HandleItem`, `HandleWeaponskill`, ...). dlac's dispatch shim runs at the end of each.

**Trigger**:
A data rule connecting a game condition to gear: *when* (matcher on the current action / player state) → *action* (a set name, or an inline slot→item payload), evaluated by the dispatch engine inside a Handler.
_Avoid_: binding, hook, rule

**Automation**:
A dlac-shipped behavior (auto elemental staff, auto obi) implemented as engine-generated Triggers in their own priority band, enabled by an option — never written into the user's trigger file.
_Avoid_: smart swap, feature flag

**Mode**:
A named, player-toggled flag (e.g. `DT`) that Triggers can match on — how manual intent enters the otherwise-automatic dispatch.
_Avoid_: stance, toggle

**Overlay**:
The combining rule for matching Triggers: all of them apply, ascending priority, later winning per slot. A full-16-slot set acts as a replacement; a partial set layers onto whatever came before.
_Avoid_: merge, stack

**Specificity**:
How narrowly a Trigger's condition matches (Any → skill/status → class/element → family → exact name → Mode). Drives the *default* priority: more specific overlays less specific.

**Commit**:
Writing GUI state to disk (a set into `<JOB>.lua`, staged items into `gear.lua`, triggers into the trigger file).

**Iridescence**:
CatsEyeXI's tiered staff-affinity stat (+1/+2). Elemental staves carry it for their own element only (NQ +1, HQ +2); universal weapons (Iridal Staff +1; Chatoyant Staff, Foreshadow +1 at +2) carry it for every element.
_Avoid_: staff bonus (that's the related per-element potency mod)
