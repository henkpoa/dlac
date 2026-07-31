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

**Ammo ladder**:
AutoAmmo's per-job ordered list of ammo *plus the rule that reads it*: walk top-down and take the first entry that clears all four gates — the context flag (ranged / WS / a special's window), pairing with the ranged weapon actually worn, stock in the equippable bags, and what the current level and job can wear. The player's order is the priority; every gate only ever *removes* candidates, never reorders them. Kin to a **Dynamic Set**'s per-slot candidate list — the same "ordered candidates, best eligible for the current level" idea, applied to the one slot a set cannot safely own — and it is named for that kinship because the two looked alike while behaving differently until the level gate landed (2026-07-27). An instance of the general **Ladder**.
_Avoid_: priority list (that is the order alone; the gates are what make it a ladder), fallback list

**Ladder**:
The general term the Ammo ladder is one instance of (ratified 2026-07-27): an ordered candidate list *plus the rule that reads it* — walk top-down, take the first **rung** that clears every gate; gates only ever *remove* candidates, never reorder them. A Dynamic Set's per-slot lists, the automation manifest chains (craft / HELM / fishing / chocobo / staff / obi) and the Ammo ladder are all ladders. The two-way Arbiter (`docs/design/two-way-arbiter.md`, built 2026-07-28) keeps ladders alive into the arbitration so a refused rung *falls* to the next.
_Avoid_: priority list, fallback list (the order alone; the gates make it a ladder)

**Handler**:
One of LuaAshitacast's profile event functions (`HandleDefault`, `HandlePrecast`, `HandleMidcast`, `HandleAbility`, `HandleItem`, `HandleWeaponskill`, ...). dlac's dispatch shim runs at the end of each. Under the Native engine the same handler names are dispatch points fired by dlac's own action pipeline — the vocabulary is engine-independent.

**Native engine**:
dlac's own equip pipeline (`feature/equipengine` + `gear/equipcore`) replacing LuaAshitacast entirely: it blocks outgoing action packets, fires Precast, re-injects, fires Midcast, and sends the 0x050/0x051 equip packets itself. Armed by the **Engine flag**; mutually exclusive with a loaded LuaAshitacast (the **Tripwire** disarms on contact). LAC-parity by construction: same set semantics, same timing formulas.
_Avoid_: standalone mode, LAC-less mode

**Engine flag**:
`config\addons\dlac\engine.lua` (`return { native = true }`) — the ONE install-wide switch both Lua states read (throttled) deciding which engine equips and where storage lives. Written by `/dl engine native on|off`; a broken flag file reads as OFF (the battle-tested LAC path is the failure mode).

**Storage home**:
Where a character's dlac data lives. Legacy home: inside LuaAshitacast's config tree (`config\addons\luashitacast\<char>\dlac\`). Native home: dlac's own root (`config\addons\dlac\<char>\`, no extra `dlac\` level). `profiles.dataDir()` / `charRoot()` / `storageRoot()` are the only composers; the flip auto-migrates by COPY (legacy files never move, so flipping back finds everything).

**Tripwire**:
equipengine's coexistence guard: every packet it injects is fingerprinted; a foreign injected action packet matching a fresh fingerprint means another engine (LuaAshitacast) re-emitted it — interception disarms for the session, loudly. Two engines both blocking action packets is a feedback hazard; the tripwire makes the failure mode a chat line instead.

**Trigger**:
A data rule connecting a game condition to gear: *when* (matcher on the current action / player state) → *action* (a set name, or an inline slot→item payload), evaluated by the dispatch engine inside a Handler.
_Avoid_: binding, hook, rule

**Gear helper**:
A dlac-shipped behavior that picks EQUIPMENT for a situation (elemental staff, obi, ammo, MP batteries, the hobby outfits). Slot rules are expressed as a **virtual slot entry** inside a set (`dlac:AutoStaff` in Main, `dlac:AutoObi` in Waist) and resolved by the engine at equip time from owned gear; set-wide rules overlay outfits without touching the sets. All of them live on the **Gear Helpers** tab.
_Avoid_: **automation** (RETIRED as user-facing wording 2026-07-28 — a GM read "Auto \<activity\>" as *the addon performs the activity*; a helper only equips gear, the player still casts/crafts/fishes/digs); "Auto \<activity\>" names (Auto Fish Set → **Fishing Gear**, Auto HELM Set → **Gathering Gear**, Auto Craft Set → **Crafting Gear**, AutoIridescence → **Elemental Staff**, AutoAmmo → **Ammo**); smart swap, feature flag, SetOptions (retired). The word survives ONLY in internals never shown to a player: `dlac:Auto*` slot markers (on-disk set contracts), row keys, the Arbiter claimant **identity** `AutoAmmo` (persisted in arbstate; rendered everywhere as **"Ammo rule"** via `arbiter.claimantLabel`), module/file names — see architecture.md "Naming: display labels vs internal names".

**Gear rule**:
A gear helper assigned to a specific set PIECE through its Behaviour rules (`autoType` on the entry wrapper), as opposed to occupying a slot: the engine decides at equip time whether to wear the piece or the slot's normal pick, releasing candidates in the player's **Removal Priority** order (`removePrio`, higher releases first). Main ships the FOUNDATION only (the Gear Rule combo offers None); the first member, **AutoAcc** — released while the acc watch measures the player over the hit cap by at least the piece's baked ACC — lives on `feature/autoacc` pending GM approval.
_Avoid_: type automation / per-piece automation (pre-2026-07-28 wording), gear tag

**Job helper**:
A dlac module that performs a job's own actions for the player — pet commands, ability use — in the situations the player configured. The deliberate counterpart of a **Gear helper**, which only ever picks equipment; the two must never be conflated, because the "only equips gear" line is what the Gear Helpers wording promises. Each Job helper is one drop-in folder under its job's directory — `jobhelpers\<job>\<module>\`, the job folder groups and the module folder is the unit ("bst-helper is the module of bst") = one row on the **Job Helpers** tab = **one unit of server approval** — the reason they are modules at all: approval is sought per helper (precedent: the approved Pup-Helper addon), never re-litigated for the whole addon. The tab exists only while at least one module is loaded, whatever the current job, and its rows are grouped in per-job sections (display-only grouping, the Gear Helpers pattern): a job section may hold **several** modules — different authors' helpers for the same job coexist, nothing competes for a "job slot" — and a module declaring several jobs appears under each, same row, same switch. Within a section, the row order is that job's module priority (drag to reorder, remembered per job) — the **Action sequence** tie-breaker. A helper for another job shows as inactive rather than vanishing. Identity is the folder name, never the job.
_Avoid_: automation (RETIRED — see Gear helper), gear helper (equips only, never acts), plugin (the parked third-party-code-inside-dlac idea, integration-surface §10 — a Job helper is first-party dlac code shipped as a module)

**Module API**:
The one table a **Job helper** is handed (`feature/modapi`, conventionally `S`), minted per module by the loader and closed over that module's identity: its id and job folder, the one monotonic clock, every central service, the two act doors, its settings store and the Panel widget kit. Entries are named for the QUESTION an author asks rather than for the dlac service that answers it — `S.item.own('Carrot Broth')`, not "the availability map is keyed by item id, so keep your own name-to-id table" — and the point of that is that **the right answer becomes the only reachable one**: `S.player.level()` returns the level the engine will gear at, and raw `MainJobLevel` is not reachable from here because reaching it already cost a live field round. It is emphatically **not a sandbox** (ADR 0028 settled that: visibility and contracts, not walls) — a module can still `require` anything. It is the surface that is documented, versioned by `api`, covered by tests, and will keep working; reaching past it is legal, unsupported, and a sign the table is missing an entry. Because the loader mints it, three things a module previously had to get right are now structural: subscription keys are namespaced by identity, every subscription is recorded (so teardown is possible at all), and an **Action sequence** request is stamped with the module's own id and section order and cannot be spoofed.
_Avoid_: sandbox / capability tier (there is none, by decision), deps (the api-1 name, when it carried two keys and nothing used it), wrapper / shim (most entries are plain references — it is a curated namespace, not a translation layer)

**Virtual slot entry**:
A `dlac:`-prefixed marker string occupying a set's slot in place of an item; the dispatch engine substitutes the concrete item per cast, or drops the slot when unresolvable.
_Avoid_: slot function (Henrik's coinage for the idea — canonicalized to this term)

**Mode**:
A named, player-controlled switch that Triggers can match — how manual intent enters the otherwise-automatic dispatch. Either a *toggle* (on/off, e.g. `DT`) or a *cycle* (an ordered value list with exactly one value active, e.g. `Weapon`: Melee→Ranged→Caster; matched as `Weapon:Melee`).
_Avoid_: stance, variant table

**Group**:
A named, player-authored list of action names (primarily blue-magic spells), stored per Job entry beside Modes; a Trigger matches `group = '<name>'` when the current action's name is in the list. Unlike a Mode (player *state*), a Group is tested against the *current action* — one Trigger can cover many spells that share gear (e.g. all STR-scaling blue magic) instead of one Trigger per spell.
_Avoid_: tag, category, spell set (a set is gear)

**Blueprint**:
A job-independent saved Trigger kept in a per-character library outside Profiles; adding one to a job stamps an ordinary Trigger into that job entry. Detached both ways — editing a Blueprint never retro-edits stamped Triggers, and vice versa. Shareable as text.
_Avoid_: favourite, template, preset, saved rule

**Mode library**:
The Blueprint idea applied to **Modes**: a per-character store of job-independent Mode definitions (`<char>\dlac\modes.lua`, outside Profiles, addon-state only), where adding one to a job **stamps** an ordinary Mode into that job entry. Shareable as text — the library file format IS the share format. It exists because Modes live per job entry and the GUI only ever sees the current job's, so without it the same toggle is retyped once per job. Stamping onto a name that already exists is an **overwrite**, not a duplicate (a `Modes` section is keyed by name): a cycle Mode offers *Append* (merge values, nothing deleted) or *Overwrite* (replace values, and strip references to values that no longer exist) — ADR 0019.
_Avoid_: mode preset, mode blueprint (a Blueprint is a Trigger; these are siblings, not the same thing)

**Overlay**:
The combining rule for matching Triggers: all of them apply, ascending priority, later winning per slot. A full-16-slot set acts as a replacement; a partial set layers onto whatever came before.
_Avoid_: merge, stack

**Specificity**:
How narrowly a Trigger's condition matches (Any → skill/status → class/element → family → group → exact name → Mode). Drives the *default* priority: more specific overlays less specific.

**Weather match**:
The Trigger condition (`weatherMatch`) true when the action's element equals the CURRENT weather element — a plain equality, day-agnostic. It is what CatsEyeXI's Scholar cast-time bonus (server mod `ALACRITY_CELERITY_EFFECT`, active under Celerity/Alacrity) actually keys on — verified in the server: weather only, no day and no opposition. Reads the same `gData.GetEnvironment().WeatherElement` the obi uses, so a Scholar's own storm buff (which overrides zone weather) counts; single and double weather both match.
_Avoid_: favourability (that is the obi's signed day+weather net — see Day/weather favourability); day match (a DIFFERENT condition — see Day match)

**Day match**:
The Trigger condition (`dayMatch`, engine v156) true when the action's element equals TODAY's day element — a plain equality, weather-agnostic, with no opposing-element penalty. The day half of the favourability net standing alone, for gear whose bonus keys on the day and nothing else. Reads `gData.GetEnvironment().DayElement`, the same field the net scores, so the two can never disagree about the day. There is no "clear day" — all eight weekdays carry an element — so a day we can read is always a real match or a real non-match, and only a failed read is unknown; and the day is NOT storm-aware, unlike the weather read.
_Avoid_: favourability (the signed net both over- and under-fires a day-only item — ADR 0029); weather match (the other one-sided equality — see Weather match)

**Day/weather favourability**:
The obi's environment score for an element: +1 per matching day OR weather, −1 per the OPPOSING element on the elemental wheel; net > 0 = favourable. Powers `dlac:AutoObi` and the `dayWeatherBonus` Trigger condition. A SIGNED net over day AND weather WITH opposition — deliberately different from both one-sided equalities.
_Avoid_: weather match / day match (the two one-sided equalities above — the net over- and under-fires either one); "favourable weather" (it folds in day and opposition, not just weather)

**Claim**:
A feature's declared wish to dress one or more slots (wear this item, or keep what's worn), registered with the Arbiter instead of equipped directly. Slots are contested one by one — losing a contest costs a claimant only that slot.
_Avoid_: pin (the floatgear feature — one claimant among many), override, hijack

**Arbiter**:
The single decision point that gathers every Claim and decides, per slot, which claimant wins, by user-visible priority. The Triggers' overlay result is the floor that Claims dress over; the Arbiter can list every claimant and why each slot went the way it did. The two-way deepening is BUILT (vocabulary ratified 2026-07-27; mechanics landed and promoted 2026-07-28, ADR 0027 — `docs/design/two-way-arbiter.md`): Claims carry whole **Ladders** submitted up front, a Refusal either **falls** a rung or **holds** a slot, and one **arbitration** per dispatch (sixteen contests) produces the plan plus the **trace** `/dl why` renders and the **Decision record** captures.
_Avoid_: pinning system, priority manager

**Decision record**:
One dispatch's arbitration answer, captured the moment it was decided: the resolved items per slot, the contest (every claimant in rank order, the winner first), the verdict words (fell / ineligible / held empty), the source ladders as they were asked, and the world context it was decided under. Kept in a session ring, appended only when the OUTCOME moved — the resolved items, or any slot's winning claimant ("only push changes"). ONE record, three renderers — `/dl why` in chat, the **Arbiter Monitor**, and the **Integration surface**'s stream — none of which re-derives.
_Avoid_: trace (`/dl why`'s per-event stash the record is built from), history log (the log renders records; it is not the record)

**Arbiter Monitor**:
The Floating window rendering the **Decision record**: the 4x4 equip-screen grid of the viewed decision, each cell coloured by the claimant that won the slot with the full per-slot contest on hover, and the decision log underneath — clicking a line pins the grid to that moment. It shows what the Arbiter DID; the Trigger Monitor keeps showing what the trigger layer PROPOSED — two altitudes, one record underneath.
_Avoid_: Dispatch Monitor (the design doc's earlier name for it)

**Action sequence**:
The Job-helper act pattern (BST's Reward and pet summon today; future helpers alike): claim the needed gear and ammo as ONE Claim, verify it is actually worn, fire the action, release — the Arbiter's next dispatch redresses the slots. Exists for two reasons, neither of them swap timing: the module INITIATES acts on its own signal (a pet-HP threshold, a pet death), and the act's equip PRECONDITION must hold before the command is even issued — Reward consumes the food that is WORN and Call Beast reads the jug that is WORN, and an empty Ammo slot can refuse the act before any trigger could dress it. Reactive gear via a normal Trigger DOES land in time (field-confirmed 2026-07-29: the Native engine blocks the action packet, equips, re-injects), so a player's own Reward-gear Trigger composes freely with a food-only sequence claim. Every module's sequences ride ONE shared claimant row (identity `JobHelper`, rendered **"Job helper"**, default rank directly below Locks; its Claim Priority position is remembered **per job** — dragging it places it for the current job only) whose status text names the live module and act ("BST: Reward"). One sequence is live at a time: when two modules of the current job contend, the job's module order — the row order of that job's section on the Job Helpers tab — picks the winner; the loser is refused loudly, and a started sequence is never preempted. Never fired under-equipped: a senior claimant holding a needed slot (Locks, Naked, Free equip) means a loud one-line refusal, not a bare fire.
_Avoid_: macro (a game feature), rotation (reads as botting), combo (fighting-game speak), "can't catch it in time" as the rationale (falsified in the field 2026-07-29 — the engine's re-inject pipeline is timely; initiation + precondition are the reasons)

**Engage/target edge**:
One outgoing action packet the player's own client sent, decoded once by the central edge service (`feature/engagewatch`) and never decoded twice. Two kinds — the **engage edge** (you attacked something) and the **retarget edge** (your battle target changed while engaged, which is what auto-target rolling to the next mob sends). The entity is taken FROM the packet and carried with the edge, together with the server id that survives an entity slot being reused. A per-(target, kind) debounce (5 seconds) means the same entity notifies at most once a window while a different one notifies immediately, so client re-sends and target stutter never reach a consumer. An edge is **precision about a moment**, and that is all it is: it is the authority on *whether the target changed*, never the source of a command's target — a command carries `<t>` and resolves at execution. A **Job helper** does not subscribe to edges to gate a standing rule; it reads them folded into the **Combat state** beat.
_Avoid_: auto-engage (names the ACT, and reads as the addon fighting for you — the naming law; the player still attacks, dlac only forwards the pet), auto-target (the game's own feature, which is one SOURCE of a retarget edge, not the edge), captured target (the entity rides along for DISPLAY and change detection; building a command out of it failed a live round)

**Combat state**:
The signal a **Job helper** gates a standing combat rule on, answered by the central service (`feature/combat`, reached as `S.combat`) and published once per dispatch beat: *am I engaged, what am I targeting, did that target just change, and has my own auto-attack swung this engagement.* It exists because dlac had two half-answers to one question and a module had to know which half to ask. Its one design decision is that **`targetChanged` is answered by the retarget Engage/target edge whenever one arrived, and by its own poll otherwise** — the record says which, so nothing has to choose. That split is the field history, exactly: the edge is the only witness to an A→B→A switch inside one beat and the only one that can tell a real change from a recycled entity index, while the BEAT is the only thing that provides a **retry** — a command the server refused leaves the world unchanged, so the next beat tries again, where an edge fires once and a refusal is simply lost. Reads nothing at all while nobody is subscribed, so it costs nothing on a job with no combat helper installed. First consumer: the BST Helper's **Fight** switch, whose three ways are Off / **When I attack** / **Follow my target**.
_Avoid_: tick / timer (it is the engine's own 0.4s dispatch beat, not a private clock), engage edge (one of its two witnesses, not the thing itself)

**Pet vitals**:
The other signal a **Job helper** acts on: your pet's presence, HP%, TP and name, answered by the central service (`feature/petvitals`) and published to subscribers once per dispatch beat. Unlike an **Engage/target edge** it IS a poll, because "my pet is hurt" is a state and not an event. Two laws travel with it. **Dead pet = no pet** — a pet at 0 HP% is not a pet any consumer may act on, the same rule `gData.GetPet()` has always encoded. And **presence is two-state on purpose**: "no pet" and "the read could not be made" answer identically, because every consumer of the answer issues a command or spends an item, and a read we cannot make is not permission to do either. Individual vitals stay nil-able — a present pet whose HP could not be read is reported honestly, never guessed at. First consumer: the BST Helper's **Reward rule**, which asks for the **Action sequence** while the pet sits below the player's pet-HP% threshold, once per **retry lockout** window. The same beat carries the **Pet-loss edge**, the service's other answer.
_Avoid_: pet state (that is the pet's own Idle/Engaged, a trigger condition), auto-Reward (names the ACT — the naming law; the rule is named for its condition, not for what it does), pet watch (nothing is watched — it is asked)

**Pet-loss edge**:
The **Pet vitals** service's second answer, and the one a **Job helper** may spend a jug on: your pet is gone, and *why*. Classified once, on the beat the pet stops being present, and pushed to its own subscribers. The law is **death is confirmed, never assumed** — only two things prove one, the **pet-falls chat line** (read where the client already rendered it, not hunted for in a packet) and a pet vanishing after a **low last-seen HP%**. Three observations SUPPRESS ahead of both proofs, because each is a deliberate act rather than a death: an observed outgoing **Leave**, **zoning**, and **logging out**. Anything else the edge calls *unknown*, which confirms nothing and lets nothing act — the deliberate asymmetry being that a missed resummon costs a player nothing and a wrongly-assumed one costs them a jug. The edge also carries **whose** pet it was: **jug** pets are recognised by their unique pet names, and a name that is not one is a **charmed** mob — so charm loss and a charmed pet's death alike trigger nothing at all, and charm play stays fully manual. The roster of names is the consuming module's data, never the service's: the service owns the rule, the module owns the list. First consumer: the BST Helper's **Resummon** rule.
_Avoid_: pet death (only one of the kinds — a Leave and a zone are losses too, and the whole point is telling them apart), pet_change (GearSwap's event, which says gain-or-loss and nothing about cause), death detection (there is no detector — there are two proofs and three suppressors)

**Retry lockout**:
A **Job helper** rule's "how often may this act, and how often may it speak" budget: after any ATTEMPT — fired, refused or aborted alike — the rule holds for the window before it may try again. It exists because a rule reads a STATE, and a state persists: a pet under the threshold is still under it on the next beat, so without a lockout one hurt pet becomes a stream of commands and a stream of chat lines. One attempt per window means at most one refusal line per window, whatever the bar does in between. A hold that ATTEMPTED nothing never arms it — a sequence already running, or an ability still on cooldown, both simply wait, and the cooldown wait is silent because the button it mirrors is greyed out and silent too.
_Avoid_: cooldown (that is the game's own ability recast, which the rule reads separately), debounce (that is the **Engage/target edge** service's per-target window, on the signal side), throttle (says nothing about what resets it)

**Naked**:
A Claim that dresses every slot with *nothing* (`/dl naked`; `/dl dress` releases). Ranked first among the *claimants*, so it beats every other one — a player who wants "naked except my pins" drags Pins above it in Claim Priority. It is a standing claim re-applied every dispatch, which is what makes it survive a strip the server refuses. Free equip outranks it and is not draggable.
_Avoid_: strip, unequip all, disable (that is `/lac naked`'s mechanism — a one-shot strip plus a below-the-engine fence, which dlac deliberately does not use; and "disable" now means Free equip)

**Free equip**:
The **ceiling** — the slots dlac has been told to keep its hands off (`/dl disable <slot|all>`; `/dl enable` releases; the Equipped tab's *Free equip* switch does all 16). dlac writes nothing to them, no equip and no unequip, so gear you put on by hand stays on. Not a Claim and not a lock: a lock is a veto *inside* the rank walk that claimants above it punch through, whereas this is pinned above every row, cannot be dragged, and is enforced at the one write seam. It is the mirror of the Triggers floor — the claims dress *over* the floor, nothing dresses *through* the ceiling (ADR 0024).
_Avoid_: disabled slots (as a state name — the row is `Disabled`, the feature is Free equip), lock, `/lac disable` (LuaAshitacast's own fence, which sits below the engine and is inert in native mode)

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

**Wishlist entry**:
A player-authored record of an item they mean to acquire, keyed by item **Id** and existing on its own — independent of any set, and never created or removed by dlac on the player's behalf. Carries one free-text note and any number of **Wishlist links**. Whether the item is *Owned* is never stored on it: that is read from the bags every time, so an entry can never claim you still have something you sold.
_Avoid_: wanted item, shopping-list item, TODO

**Wishlist link**:
A player's stated intention that a **Wishlist entry** belongs to a job, or to one of that job's named sets. Recorded on the entry, never derived, and never revoked by dlac. Deliberately distinct from the *fact* of whether the piece currently sits in that set — which is read live from the set file and shown beside the link. The two are allowed to disagree: the link is what you meant, the fact is what is.
_Avoid_: tag, assignment, set membership

**Food history**:
What this character has eaten, most recent first, unique by item id and persisted per character (`feature/foodwatch`). Its one hard problem is that **food is not a client-side category** — the item resource cannot tell a Mithkabob from a Potion, and the Catalog is gear-only — so dlac ships no food list and instead reads the server's own definition off the wire: an outgoing item use names the ITEM, and the FOOD status effect (251) *moving* right after proves it was food. Moving means its **expiry changed**, not that the icon appeared: eating over a live food never flickers the icon, which is the case a presence test gets wrong. A food dlac has never seen is learned the first time you eat it. Because dlac is always loaded, an effect still up at login is taken to be the newest entry — that is what lets the history NAME the food you are under instead of reporting a bare "food active".
_Avoid_: food tracker / food timer (nothing is timed here — how long is left is the buff-timer addons' question, deliberately not re-answered), pet food (a **Pet food ladder** is BST's Reward stock, a different thing entirely)

**E-Box (Ephemeral Box)**:
CatsEyeXI's custom Crystal-Warrior-only item store, reached only while in **Crystal Warrior** play mode and standing near an in-world "Ephemeral Box". It is NOT one of the 17 ownership containers: an item sitting in the E-Box is neither *Owned* nor *Available* until it is withdrawn into the bags. Every dlac feature that reads or withdraws from it (today: **E-Box Restock** alone) speaks through the one shared **E-Box client**.
_Avoid_: bank, storage (dlac has several — say which), moogle/porter storage (a different game system)

**E-Box client**:
The one dlac module (`feature/eboxclient.lua`) that speaks CatsEyeXI's custom **E-Box** wire protocol — list a category, search by name, withdraw — reimplemented inside dlac so it never depends on the **trove** addon being installed. Exactly one exists: every E-Box feature is a thin consumer over its shared, throttled counts, so overlapping requests coalesce and outgoing traffic stays rate-capped — the party-line courtesy server operators care about. **E-Box Restock** is the only consumer (AutoAmmo had a counts-and-fetch section until 2026-07-27; it was removed as redundant once Restock could carry category 15).
_Avoid_: trove wrapper (a clean reimplementation, no trove dependency); a per-feature client (only one exists — features consume it, they never each open the box)

**E-Box Restock**:
The Crystal-Warrior-only feature that keeps chosen items topped up from the **E-Box**: the player names items to carry and a per-item Target ("keep N"), and Restock fetches the shortfall from the box — clamped to what the box holds and to free bag space — on demand while standing near a box. A pure GUI-plus-**E-Box client** feature (its own Gear Helpers row, no gear and no dispatch-engine involvement); it nudges and fetches on a click, never withdrawing on its own.
_Avoid_: part of AutoAmmo (a separate feature — a sibling consumer of the E-Box client, not folded in); auto-restock / silent withdrawal (it never fetches without a click)

**Plan vs Equip**:
A set is a *plan*: it may contain anything the character can ever wield (a 1H weapon in Sub with no Dual Wield). Legality is decided by the engine at *equip* time (`subSlotAllowed`: DW up → weapon; otherwise the list's shield/grip). GUI surfaces that equip immediately gate; builders never do.
_Avoid_: validating sets against current traits/state

**Addon state**:
The Lua state Ashita loads via `/addon load dlac` — the GUI, editors, previews, writers, and every addon-tree module. It scans bags, writes the per-character files, seeds the runtime (legacy mode), and (since the lockstyle pivot, ADR 0014) owns lockstyle apply end to end. In legacy mode it reaches the Engine's state only by files; under the Native engine it IS the Engine's host — one state, direct calls.
_Avoid_: dlac side, GUI state, the front end

**Engine**:
The equip decision core — `dispatch.lua` and its companions (`utils`/`chatfmt`/`profiles`/`gear`). Its job is to **equip gear** (overlay matching Triggers' sets, resolve virtual entries, honor Claims) and report on its own equipping (`/dl why`, `/dl prio`) — nothing else (ADR 0014). It runs in ONE of two hosts: LuaAshitacast's Lua state (legacy mode — the seeded copies, loaded by the job shim, detected by `inLac()`) or the Addon state itself (Native engine, armed by the Engine flag, detected by `engineActive()`). Only the active engine's host `EquipSet`s — through `gFunc` in legacy, through `equipengine`/`equipcore` natively.
_Avoid_: LAC engine (LAC is LuaAshitacast; the Engine is dlac's code, whichever state hosts it), seeded side, dispatch (that is one file of it)

**Engine handshake**:
`dispatch.M.VERSION`, mirrored through `modestate.lua`, lets the GUI detect that LuaAshitacast is still running a stale seeded engine and show the red "Reload LAC" banner. Bump it whenever seeded-file behavior changes.

**Statefile**:
A per-character `return {...}` mirror crossing the two Lua states (craftstate, helmstate, fishstate, pinstate, accstate, arbstate, the autogear manifest): a watcher/GUI writes it, the engine hot-reloads it on a ~1s throttle through ONE reader (`ensureStateFile`, engine v70) with one policy — a torn/corrupt write DROPS that state until the next good write self-heals it. The trigger file is deliberately NOT a Statefile (hand-editable: it keeps the previous rules and says so). Addon-side path truth: `lib\statefile.charDir`.
_Avoid_: config file, settings file

**Setting**:
A player preference the GUI remembers for a character, held in `<char>\dlac\uiflags.lua` and owned by `gear\syncflags.lua` (the one loader/writer). Addon-state only: the Engine never reads it — a Setting changes what the GUI *shows or does*, never what gets equipped. That is the whole line between a Setting and a **Statefile** (which exists to cross into the Engine). Every Setting is reachable from the Menu's **Settings** panel; some also keep a shortcut checkbox where they're used.
_Avoid_: config, option, flag (the file is called uiflags for history, but "flag" also means the Engine flag — say Setting)

**Session switch**:
A player-controlled switch dlac deliberately forgets — never written to disk, gone by the next session. The sibling of a **Setting** (which is remembered) and named because dlac has several: naked, slot locks, free equip, the locked set, every Floating window's open flag, and the **Integration surface**'s stream. Session-only is not free: an Ashita addon survives a logout, so a switch that must die with the session has to be dropped explicitly — and the world read goes 0/nil during a *zone load* exactly as it does at character select, so the drop keys on absence OUTLASTING a zone, never on absence itself (engine v146).
_Avoid_: Setting (that one persists), temporary flag, toggle

**Integration surface**:
The one channel another addon reads dlac through (`docs/design/integration-surface.md`, designed 2026-07-28): a **push** stream of labelled events plus **pull** queries, both over Ashita's `plugin_event` broadcast — the mechanism LuaAshitacast's own `integration.lua` already uses. It exists because every Ashita addon gets its own Lua state, so a foreign addon can otherwise reach dlac only by file or the command bus that ADR 0014 outlawed. Deliberately **read-only and gated behind a Session switch**: it publishes what dlac decided, and nothing on it can equip, commit or configure anything.
_Avoid_: API (it is a channel, not a callable surface — nothing outside dlac's state can call in), export, plugin (a plugin runs INSIDE dlac's state — designed and parked, section 10 of the design doc)

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

**Floating window**:
An ImGui window a UI module owns, gated on its own session-only open flag and drawn from exactly ONE call site — gearui's `d3d_present`, above its `M.visible` return — so it lives whether or not the main window is open. Any surface may OPEN one (a bar button, a panel button, a `/dl` command); only that one site may DRAW it. Today: lockstyle, floatgear, the Trigger Monitor, the Arbiter Monitor, the restock nudge, the two Chocobo dig searches, the Hobby bar, idlefloat, the fishing target window. That one site is also what makes **Scroll Lock** work: it gates every dlac window — floating and main alike — on `gamehud.hidden()`, so the whole UI blinks out with the game's own HUD and comes back where it was.
_Avoid_: popup (that is the Menu/Teleports kind, which closes on click-away and draws inline), dialog, panel

**Panel**:
One Automation's detail view inside the Automations tab, reached by clicking its list row. Has no chrome of its own and dies with the main window.
_Avoid_: window (a Panel is not one — see Floating window); screen; "the <x> automation" when you mean its panel (an Automation is the feature; the Panel is where you configure it)

**Hobby bar**:
The one shared Floating window holding the Craft / HELM / Fishing / Chocobo tabs (ADR 0017). Switching tabs arms nothing; the armed hobby is merely marked.
_Avoid_: hobby menu (that is the Menu popup's row that opens it), craft bar / fish bar / helm bar (the three separate windows it replaced — dead since ADR 0017)
