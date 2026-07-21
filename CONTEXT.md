# dlac

dlac ("dynamic LuaAshitacast") is an Ashita v4 addon for CatsEyeXI that lets players build and drive LuaAshitacast equipment sets through a GUI, instead of hand-editing Lua profiles.

## Language

**Catalog**:
The full CatsEyeXI equipment reference (`catalog.lua`), crawled from the live API — base-truth stats for every item, keyed by Id. Access goes through `gear\catalogindex` (the one walker: rawIndex/rawById/flat/flatten); the equip-time engine never loads it — gear.lua stamps carry what it needs.
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
A dlac-shipped behavior (auto elemental staff, auto obi) expressed as a **virtual slot entry** inside a set (`dlac:AutoStaff` in Main, `dlac:AutoObi` in Waist) and resolved by the engine at equip time from owned gear.
_Avoid_: smart swap, feature flag, SetOptions (retired)

**Type automation**:
An Automation assigned to a specific set PIECE through its Behaviour rules (`autoType` on the entry wrapper), as opposed to occupying a slot: the engine decides at equip time whether to wear the piece or the slot's normal pick, releasing candidates in the player's **Removal Priority** order (`removePrio`, higher releases first). Main ships the FOUNDATION only (the Auto Type combo offers None); the first member, **AutoAcc** — released while the acc watch measures the player over the hit cap by at least the piece's baked ACC — lives on `feature/autoacc` pending GM approval.
_Avoid_: per-piece automation, gear tag

**Virtual slot entry**:
A `dlac:`-prefixed marker string occupying a set's slot in place of an item; the dispatch engine substitutes the concrete item per cast, or drops the slot when unresolvable.
_Avoid_: slot function (Henrik's coinage for the idea — canonicalized to this term)

**Mode**:
A named, player-controlled switch that Triggers can match — how manual intent enters the otherwise-automatic dispatch. Either a *toggle* (on/off, e.g. `DT`) or a *cycle* (an ordered value list with exactly one value active, e.g. `Weapon`: Melee→Ranged→Caster; matched as `Weapon:Melee`).
_Avoid_: stance, variant table

**Group**:
A named, player-authored list of action names (primarily blue-magic spells), stored per Job entry beside Modes; a Trigger matches `group = '<name>'` when the current action's name is in the list. Unlike a Mode (player *state*), a Group is tested against the *current action* — one Trigger can cover many spells that share gear (e.g. all STR-scaling blue magic) instead of one Trigger per spell.
_Avoid_: tag, category, spell set (a set is gear)

**Overlay**:
The combining rule for matching Triggers: all of them apply, ascending priority, later winning per slot. A full-16-slot set acts as a replacement; a partial set layers onto whatever came before.
_Avoid_: merge, stack

**Specificity**:
How narrowly a Trigger's condition matches (Any → skill/status → class/element → family → group → exact name → Mode). Drives the *default* priority: more specific overlays less specific.

**Claim**:
A feature's declared wish to dress one or more slots (wear this item, or keep what's worn), registered with the Arbiter instead of equipped directly. Slots are contested one by one — losing a contest costs a claimant only that slot.
_Avoid_: pin (the floatgear feature — one claimant among many), override, hijack

**Arbiter**:
The single decision point that gathers every Claim and decides, per slot, which claimant wins, by user-visible priority. The Triggers' overlay result is the floor that Claims dress over; the Arbiter can list every claimant and why each slot went the way it did.
_Avoid_: pinning system, priority manager

**Profile**:
A character's named bundle of dlac data (e.g. `Default`) — the unit the PROFILES menu switches, clones, and imports. Exactly one is active per character; changing jobs never changes the Profile.
_Avoid_: character profile (redundant — a Profile is always per character), LAC profile

**Job entry**:
One job's slice inside a Profile: that job's sets, triggers, and lockstyle boxes. Job changes switch which job entry is live within the active Profile.
_Avoid_: job profile (collides with both Profile and LuaAshitacast's own "profile")

**Job shim**:
The `<JOB>.lua` file LuaAshitacast loads on a job change — what LAC's own docs call a "profile". dlac manages it as a thin shim holding no data; the engine installs the active Profile's job entry over it.
_Avoid_: calling it a profile in dlac-speak

**Lockstyle box**:
One of the 30 numbered save slots for a lockstyle look, stored on the job entry. The MARKED (gold) box is where Save lands; "OnLoad Lockstyle" re-applies a box at login/job change.
_Avoid_: lockstyle set (a box holds one; the plural reads as gear sets)

**Commit**:
Writing GUI state to disk (a set into the active Profile's job entry, staged items into `gear.lua`, triggers into the trigger file).

**Iridescence**:
CatsEyeXI's tiered staff-affinity stat (+1..+3, per the catalog's `Iridescence` stat). Elemental staves carry it for their own element only (NQ +1, HQ +2); universal weapons carry it for every element — Iridal/Ephemeron +1; Chatoyant plus the job-specific customs (Incursion: Claritas, Izuna, Foreshadow +1, Arcanium +1 — CW-only; Oboro weapons: Coeus, Kaladanda; and Nightingale) +2; Inanna and Keraunos (Incursion T3, CW-only), Gridarvor (Oboro) and the Lv75 relic staves (Laevateinn, Tupsimati) +3.
_Avoid_: staff bonus (that's the related per-element potency mod)

**Owned vs Available**:
Two distinct facts about an item. *Owned* = present in any of the 17 containers (`ALL_CONTAINERS` — the truth `gear.lua` and `/dl prune` use). *Available* = in an equip-eligible bag right now (Inventory + the 8 Wardrobes, `SCAN_CONTAINERS`) — what the engine and the GUI's red-name marking use. Gear can be owned and unavailable (parked in storage). The combined per-surface answer is `ownedcache.verdict` (stored beats locked beats ok); panels map states onto their own palette — the state is the shared meaning, the colour is theirs.
_Avoid_: "has it" without saying which of the two you mean

**Plan vs Equip**:
A set is a *plan*: it may contain anything the character can ever wield (a 1H weapon in Sub with no Dual Wield). Legality is decided by the engine at *equip* time (`subSlotAllowed`: DW up → weapon; otherwise the list's shield/grip). GUI surfaces that equip immediately gate; builders never do.
_Avoid_: validating sets against current traits/state

**Engine handshake**:
`dispatch.M.VERSION`, mirrored through `modestate.lua`, lets the GUI detect that LuaAshitacast is still running a stale seeded engine and show the red "Reload LAC" banner. Bump it whenever seeded-file behavior changes.

**Statefile**:
A per-character `return {...}` mirror crossing the two Lua states (craftstate, helmstate, fishstate, pinstate, accstate, arbstate, the autogear manifest): a watcher/GUI writes it, the engine hot-reloads it on a ~1s throttle through ONE reader (`ensureStateFile`, engine v70) with one policy — a torn/corrupt write DROPS that state until the next good write self-heals it. The trigger file is deliberately NOT a Statefile (hand-editable: it keeps the previous rules and says so). Addon-side path truth: `lib\statefile.charDir`.
_Avoid_: config file, settings file

**Set bonus**:
A server-applied stat package for wearing N+ pieces of a gear set (`data\gearsets.lua`, 126 sets). Tiers are value-AT-count replacements (`tiers[min(count, max)]`, nil below `min`), counting is per SLOT (two copies count twice) and level-gated. Evaluated by `gear\geareffects.lua`; the game applies the real thing at equip time — dlac only plans, displays and scores it.
_Avoid_: treating tier values as cumulative increments; per-item "set piece" scores

**Composition**:
A concrete slotLabel→record assignment — the worn set, the planned working set, or the optimizer's current assignment. A plan-side object (sets are plans, ADR 0006); it never gates building.

**True combination evaluator**:
`geareffects.comboStats(composition, ctx)` — the single source of truth for "what stats does this whole composition have" (item stats at level + active set tiers). Worn/planned totals, panel set captions and the Sets panel's weighted score all derive from it; the optimizer's objective folds the same tier data inside its cap fold.
_Avoid_: summing per-item scores and calling it a set total

**Set-seeded restart**:
An optimizePicks restart from the converged baseline with a feasible gear set's pieces force-placed (least-loss slot choice, hard 6/12 seed caps), kept only on strict improvement. Exists because single-slot hill climbing can never enter a bonus whose pieces are each a solo loss. ADR 0011.
