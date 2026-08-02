# dlac — Architecture

> Module map and data-flow reference for anyone (human or agent) picking the project up.
> Line references are as of 2026-07-10 (main @ 591a207); the code moves fast — treat them
> as anchors, not gospel. Start with [HANDOFF.md](HANDOFF.md) if you're brand new.

> **THE PURGE (2026-07-27, `docs/design/lac-purge-plan.md`):** everything below that
> describes TWO Lua states, seeded engine copies, the self-swap, the engine flag /
> legacy mode, LAC-hosted dispatch, or writes under `config\addons\luashitacast\` is
> **HISTORY**. There is one Lua state, one engine (dlac's own, always), one storage
> home (`config\addons\dlac\<char>\`); old luashitacast trees are read-only import
> territory (Sets tab static/group imports + login auto-migration — Henrik's
> keep-list). HANDOFF's mental model is current; this file's LAC-era sections await
> a full rewrite.

dlac ("dynamic LuaAshitacast" — the name is history; it absorbed its host) is an
Ashita v4 addon for CatsEyeXI whose GUI builds equipment sets and whose OWN engine
equips them, so players never hand-edit profile Lua. It runs as a
normal `/addon`, reads player/inventory through `AshitaCore`, and drives gear through
LAC's `gFunc.EquipSet` from library modules that are *seeded into each character's LAC
profile folder*. The design rests on a deliberate two-Lua-state split (ADR 0002): the
**addon state** writes data files; the **LAC state** evaluates them at cast time.

---

## Repository layout

**The rule: the addon root is what LuaAshitacast sees. Folders are what only the addon sees.**

```
dlac.lua                 Ashita entry point (Ashita requires <addon>/<addon>.lua — cannot move)
utils.lua  dispatch.lua  chatfmt.lua  profiles.lua  gear.lua
                         ^ the SEEDED ENGINE — dlac.lua copies these into <char>\dlac\, where
                           they load a second time inside LAC's Lua state. Flat by necessity;
                           see "Dual identity" below before touching their paths.
PROFILE_TEMPLATE.lua     what Setup writes into a user's <JOB>.lua

ui/        imgui modules: gearui, triggersui, automationsui, equippedui, profilesmenu,
           setupui, weightsui, craftbar, uistyle, uihost, itemicons, filetex, floatgear,
           ammoui (the AutoAmmo panel)
data/      generated / static tables: catalog, crafts, fishdb, spells, abilities,
           statdefs, levelscaling, levelstats
gear/      the gear pipeline: gearoptim, gearimport, gearexport, gearcheck, gearfmt,
           setmanager, setimport, profilesets, ownedcache, syncflags, weaponfilter,
           groupsmodel, actionpicker, catalogindex, gearoracle (THE worn-item +
           equip-bag door)
feature/   self-contained features: lockstyle, macrobook, useitem, craftwatch, augments,
           pinwatch, helmwatch, fishwatch, fishcalc (pure fishing math -- headless),
           ammowatch (AutoAmmo config state), synthrun (repeat-Last-Synth batches:
           types /lastsynth N times, verifies each on s2c 0x030, reports on 0x06F)
lib/       generic helpers: cmdqueue, statefile, entwatch (the central entity
           watcher: subscription registry + one shared scan, all the
           entity-array idioms in one place)
jobhelpers/  drop-in Job helper modules, filed <job>\<module>\ -- one MODULE folder is one
           module and one unit of server approval. The author-facing contract + the services
           a module may consume: docs/reference/jobhelper-authoring-guide.md
assets/    PNGs (loaded by absolute path via AshitaCore:GetInstallPath — not by module path)
docs/  tests/  tools/
```

Module names carry the folder: `require('dlac\\ui\\gearui')` → `addons\dlac\ui\gearui.lua`,
because the `package.path` shim substitutes the whole name into `addons\?.lua`.

Two traps when moving files or grepping module names:

1. **`dlac\X` is not always a module.** The same prefix names *per-character data files* under
   `<char>\dlac\` — `dlac\triggers`, `dlac\modestate`, `dlac\lockstyles`, `dlac\macrobooks`,
   `dlac\craftstate`, `dlac\ammostate`, `dlac\gearweights`, `dlac\profiles\<name>\`. Those are user state and must
   never be folder-qualified. Note the near-misses: the `lockstyle` **module** vs the
   `lockstyles` **data file**; `macrobook` vs `macrobooks`; `crafts` vs `craftstate`.
2. **The engine five cannot move.** See below.

## Central services — ask these, never re-derive

The one-answer functions ("Henrik's shape": callers ask the question, the
plumbing is the service's problem). When a feature needs one of these answers,
it CONSUMES the service — a local re-implementation is a bug waiting for the
field round that already happened. All run in the **addon state** (the seeded
engine cannot require them; it has its own minimal reads).

| The question | Call | Module | The rules that bite |
|---|---|---|---|
| **Is this character a Crystal Warrior?** (game mode at all) | `gamemode.get()` → `'CW'` \| `'Wings'` \| `'ACE'` \| `nil` | `feature/gamemode.lua` | UCW deliberately ⇒ `'CW'` (same playmode — Henrik's ruling). `nil` = UNKNOWN, never a value to gate on: CW-only UI must gate on the **affirmative** `== 'CW'` and stay hidden on nil. First consumer was AutoAmmo's E-Box section (removed 2026-07-27); today `eboxclient.isCW()` and `ui/restockui`. |
| **Is there an entity named X nearby, and how far?** | `entwatch.watch(who, name[, cb])` then `entwatch.nearest(name)` / `.matches(name)`; `.poke(name)` = rescan | `lib/entwatch.lua` | THE central entity watcher — never write a local scan. It owns the idioms that cost three field rounds: GetName pads with whitespace (trim + ci), rendered bit 0x200 (signed-u32 fix) before trusting a distance, `GetRawEntity` (never the dead `GetEntity(i)`), the FULL 0x000-0x8FF range (custom NPCs are dynamic entities). Distances in yalms (squared on the wire). Callbacks fire on match-set changes incl. evictions; callback-less watches sleep 15 s after the last ask. Consumers: `eboxclient` (Ephemeral Box — for AutoAmmo + E-Box Restock), `helmwatch` (the four "* Point" names while Auto HELM is armed). |
| **How many of item id N do I own?** | `ownedcache.counts()` (equippable bags) / `.totals()` (anywhere) / `.verdict(rec)` | `gear/ownedcache.lua` | counts = what can actually be equipped/consumed NOW; totals includes storage (the red "stored" coloring everywhere in dlac). |
| **What is this item?** (any item, owned or not) | `catalogindex.flat()` / `.rawById(id)` / `.rawIndex()` | `gear/catalogindex.lua` over `data/catalog.lua` | The catalog's `Slot` lies toward Body for unimplemented rows (`jobs==0` is the junk marker); `AmmoType` absent = trinket. |
| **Any gear question** (worn item, equip bags, eligibility, identity, effective stats) | `gearoracle.wornItem(slot)` → `{ id, rec, extra, item }` \| nil; `.equipBags()`; `.canWear(rec, job, level)`; `.anyJobCanWear(rec, jobLevels)`; `.lookup(idOrName)`; `.stats(rec, ctx)`; `.setStats(comp, ctx)` | `gear/gearoracle.lua` | THE one door in the addon state (issues #70/#71, PRD #69; boundary rulings in **ADR 0013**). **FETCH:** the worn-item decode (packed Index → container/slot → item) + the ONE equip-bag list (Inventory + 8 Wardrobes); byte-identical engine TWINS (`dispatch.decodeEquipIndex` / `dispatch.AMMO_BAGS`, ADR 0002) held by the OR-section parity pins. `wornItem` hands the id back RAW (0/65535 included). **ELIGIBILITY:** `canWear` fronts the engine rule (`dispatch.canWear` — main job only, level on main); `anyJobCanWear` delegates to the addon-state gate (`gear/jobgate.canEquip`, fail-open). **IDENTITY:** `lookup` joins owned-first then catalog (id authoritative). **Claim-BLIND, permanently** — capability only, never permission (`canWear`, never `canEquip`); the Arbiter is the sole precedence authority. FACADE, not absorb: the interpreters keep their homes. **The door is LAW (#73):** the HARD RULE source guards (run_tests §GRD) confine the worn read, the packed-index decode, the equip-bag list and the 22-job list to their one home, and forbid feature/UI modules from requiring the stat interpreters — the Phase-2 stat-glue allowlist was **emptied by #74** (`stats`/`setStats` migration), so the rule is now absolute. |
| **Where is this character's dlac state dir?** | `statefile.charDir()` | `lib/statefile.lua` | nil pre-login — retry, never cache the nil. (The seeded engine has its own `charDir()` inside dispatch.lua.) |
| **This character's native MP pool?** | `nativemp.self([meritMP])` / `.get(race, mjob, mlvl, sjob, slvl)` | `data/nativemp.lua` | The server's formula verbatim; merits are NOT native — pass them in. Never calibrate against the on-screen max (traits/gear ride the display only). |
| **Queue a chat/game command safely?** | `cmdqueue.issue(cmd)` — THE central auto-issue door; `.enqueue(delayFrames, cmd)`; `.tick()`; `.frame()` | `lib/cmdqueue.lua` | Two same-frame `QueueCommand`s arrive REVERSED in other Lua states, and an addon state never hears its OWN queued commands back — the two facts this queue exists for. **The drain policy, corrected 2026-07-29 (this row used to say "drains one per frame", which the code has never done):** `tick()` — once per `d3d_present` — advances the frame clock and then flushes **every** command whose due frame has arrived, in insertion order. So the queue does NOT space commands for you: **spacing is the caller's `delayFrames`**, which is what the lock/equip and set-lock pairs use ("commands run a fixed number of frames apart so they never block"). Two commands enqueued in the same frame at the same delay leave in the same frame — if their order must survive the trip, give them DIFFERENT frames. `issue(cmd)` = `enqueue(0, cmd)`: it leaves on the next tick, on the MAIN thread, never inside a packet or render context — and Henrik's ruling (2026-07-29) is that every helper auto-issuing a command goes through this ONE function, never a per-module wrapper. `frame()` is also the addon's steady monotonic clock (`frame()/60` → seconds) for the Action sequencer and the Job-helper rules. Command targets (`<t>`, `<me>`) resolve at EXECUTION time, not at enqueue time. |
| **E-Box (CW storage): counts / search / withdraw / proximity?** | `eboxclient.boxCount(id[, ahCat])` · `.categoryCounts(ahCat)` · `.ensureCategory(ahCat, maxAge)` / `.ensureCategories({ahCats}, maxAge)` · `.search(q)` + `.searchResults` · `.withdraw(id, qty)` / `.withdrawBatch({{id,qty},…})` · `.boxDistance()` / `.nearBox()` · `.isCW()` · `.rescan()` | `feature/eboxclient.lua` | **THE ONE 0x1A4 client (ADR 0016) — every E-Box feature is a thin CONSUMER; NEVER open a second client.** 0x1A4 is a party line, and two clients race on it AND double the traffic (CatsEyeXI operators care). CW only (gamemode row). It owns the whole protocol (summary/category/search/withdraw/ACK/LOCKED), a SHARED multi-category counts cache (`cat[ahCat]` authoritative + `counts` flat merged), Ephemeral-Box proximity (via `entwatch`, `BOX_RANGE = 5` field-pinned), and the server-load throttle that makes the NFR structural: one request in flight, a global min-gap, per-category stale windows, and a **near-box gate — query ONLY near a box**. Batch withdraw = the trove `executePrepare` shape (one WITHDRAW per pull, ACK-counted). Consumer: `ui/restockui` (**E-Box Restock**) — the only one. AutoAmmo carried a counts-and-fetch section through the `feature/eboxammo` adapter until 2026-07-27, when it was removed as redundant (Restock reaches category 15 with targets and top-up) and the adapter was deleted; its entity probe lives on as `/dl debug ebox scan`. The withdrawal SLOT-SAFETY rule (each drawn stack lands in a FRESH Inventory slot; never over-draw) lives in the pure planner `feature/restockwatch.plan`. See `docs/design/ebox-restock.md`. |
| **Item icon / hover card in UI?** | `deps.renderIcon(id, size)` / `deps.itemTooltip(rec)` | `ui/itemicons.lua` + gearui's `renderItemTooltip`, injected via the shared deps table | ONE hover card serves every equipment surface — never draw a rival. |
| **The gear-helper list + coverage status?** | `automationsui.listRows()` + `.levelColor(level, max)` | `ui/automationsui.lua` | The SAME rows/ramp the Gear Helpers tab shows — never rebuild the list or invent a rival color ramp. `{}` before init/login; MaxMP graduated 2026-07-21 and rides the same list. (The Teleports quick menu was consumer #1 until 2026-07-26, when its Automations/HELM/Fishing cascades were replaced by two rows that open the Hobby bar and Lockstyle windows.) |
| **Is the MaxMP mode on? / flip it** | `automationsui.maxmpMode()` / `.maxmpToggle()` | `ui/automationsui.lua` | THE shared reader/flipper for every surface (panel button, list row). Reads the LAC engine's modestate mirror (1s TTL — display can lag a beat); the toggle sends the EXPLICIT `/dl mode maxmp on\|off`, never a blind flip. Auto-disables on job change. |
| **The max-MP band plan?** | `dispatch.M.mpBands(ctx)` → context; `mpbands.build/target/tick` (pure core) | `dispatch.lua` (LAC state) + `feature/mpbands.lua` | ONE context serves the engine AND `/dl plan` — the plan IS the behavior, never render a rival. Current MP is the only live read; `GetMPMax` is unreliable during gear churn and floored party MP% == 100 is the only exact fullness signal. Read docs/design/maxmp-mode.md (rulings ledger + failure museum) before touching. |
| **Did I just engage / re-target something, and exactly what?** | `engagewatch.lastEdge()` → `{ kind, index, serverId, name, at }` \| nil; `.subscribe(who, cb)` / `.unsubscribe(who)`; `.decode(bytes)` (pure) | `feature/engagewatch.lua` | THE one decoder of the two battle EDGES — never register a second `0x01A` reader for them. `kind` is `'engage'` (category `0x02`) or `'retarget'` (category `0x0F`, which is what auto-target rolling to the next mob sends). The entity comes **from the packet** (UniqueNo u32 @0x04, ActIndex u16 @0x08), never re-read at consumption time — by then the target has moved on, and that is the whole point. A **per-TARGET debounce** (`DEBOUNCE_S = 5`) means the same entity notifies at most once a window while a different one notifies immediately, so client re-sends and target stutter never reach a subscriber. THREADING (the chocowatch rule): the `packet_out` handler decodes and stashes on the NETWORK thread and does nothing else; `pump()` — wired in dlac.lua's `d3d_present` — does the debounce, the entity-name read and the callbacks on the MAIN thread. Subscribers are pcall'd, so one throwing consumer never costs another its notification. Consumer: **`feature\combat`**, which is now the ONE subscriber and the only thing modules see — it folds accepted edges into its per-beat record so `targetChanged` is edge-answered, and reads `swungThisEngagement()` for the "Send when" option. Fight was rewritten poll-driven after two failed field rounds (history.md, "Fight goes poll-driven"), and what round 2 actually indicted was using the packet's captured entity as a command's TARGET, not the decode — so the edges are load-bearing again, for the one question only they can answer. The field-proven decode of both kinds is `accwatch.lua`'s engage watch on the parked `feature/autoacc` branch (history.md, "ACC calculator → acc watch"); its inert byte-identical dev copy at `share/mob-stats/accwatch.lua` is REFERENCE ONLY — THIS is the one live shared implementation, and accwatch subscribes here when it lands. |
| **Is a pet out right now, and how is it doing?** | `petvitals.get()` → `{ present, hpp, tp, name, status }`; `.subscribe(who, cb)` / `.unsubscribe(who)`; `.fromPet(pet)` (pure) | `feature/petvitals.lua` | THE pet read — never open a second `GetPetTargetIndex`/`GetHPPercent` pair (the BST Fight switch carried one until this landed, and it now asks here). It CONSUMES `gData.GetPet()`, dlac's one existing pet reader (`feature/nativedata`, the LAC-parity provider the engine already reads every dispatch for the pet trigger conditions) — a central service must not begin life as the second implementation of its own answer. **`present` is TWO-state on purpose:** `gData.GetPet()` answers nil for both "no pet" and "the read failed", and every consumer here ISSUES A COMMAND or SPENDS AN ITEM, so an unreadable pet must decide exactly the way an absent one does (the #139 `hasPet` rule). **Dead pet = no pet** — HP% 0 is not a pet, encoded both in `GetPet` and re-stated in `fromPet` for hand-built records. `hpp`/`tp`/`name` are individually nil-able: a present pet whose HP could not be read is reported honestly, never guessed. `pump()` (dlac.lua's `d3d_present`) publishes to subscribers once per `TICK_S` = 0.4 s (the engine's own dispatch beat) and **does not read the world at all while nothing is subscribed**; `get()` has no cache and reads now, so a caller can never be handed a record older than its question. Consumers: the BST Helper's Reward rule (`jobhelpers/bst/bst-helper/reward.lua`), and its Resummon queue tick. The Fight switch used to ride this beat as its metronome — a combat feature clocked by the pet service, because this was the only per-beat publisher dlac shipped; it now rides `feature\combat` and reads the pet here at decision time. |
| **My pet is gone — WHY?** (the classified pet-loss edge) | `petvitals.classifyLoss(prev, cur, ctx)` (pure) → `{ lost, kind, confirmed, how, pet, name, hpp }`; `.subscribeLoss(who, cb)` / `.unsubscribeLoss(who)`; `.lastLoss()`; `.lossText(edge)` | `feature/petvitals.lua` (issue #141) | **DEATH IS CONFIRMED, NEVER ASSUMED** — the whole law, and it exists because the one consumer SPENDS A JUG. Three proofs, strongest first: **THE CORPSE** (`corpseVerdict(prevId, ent)` — the pet's own target index re-read RAW after presence drops, matched by **server id**, at zero HP or a dead status; `M.reads.entity` is the only read in the service allowed to see a dead pet, because `gData.GetPet()` refuses an HPP-0 one), the **pet-falls chat line**, and — **only when the corpse could not be read at all** — a present→absent transition after a **low last-seen HP%** (`LOW_HP_PCT = 25`). **On CatsEyeXI the corpse is the only one that ever fires for a jug pet**: `CMobEntity::Die` pushes the falls message, `CPetEntity::Die` pushes **nothing** (server source, 2026-07-30), so the chat proof cannot come and the low-HP guess misses every pet killed from above the ceiling — which is exactly the field report that the Resummon rule never fired. A corpse read that finds the entity **alive** SUPPRESSES: live memory outranks a chat line and a guess alike. An observed outgoing **Leave**, **zoning** and **logging out** each suppress ahead of every proof, so a Leave pressed on a dying pet can never read as a death. Everything else is `unknown`, which confirms nothing. **Jug vs charm is decided by PROVENANCE first** — the summon we watched you press (`M.SUMMON_NAMES`, the same outgoing-ability drain the Leave observation rides) stamps the pet that appears next, which is what makes a **custom jug** this server ships and no roster describes still resummon — and by NAME second, through an injected authority (`M.lossCtx.isJugPet`): the service deliberately does not own the roster, that is the BST module's data (`jobhelpers/bst/bst-helper/jugs.lua`), and the next module's will be its own. Signals live in a TTL inbox (`SIGNAL_TTL_S = 8`) so nothing observed a minute ago explains a pet lost now, and they are cleared once they have explained one loss. The edge fires **once** per loss on the ordinary vitals beat; a loss subscriber alone keeps that beat alive. The Leave observation reads outgoing `0x01A` **category 0x09 (Ability)** — deliberately not one of engagewatch's two battle edges — stashing on the network thread and resolving the ability NAME on the main thread through the client's own resource tables (no hardcoded ability id). Consumer: the BST Helper's Resummon rule (`jobhelpers/bst/bst-helper/resummon.lua`). |
| **Is this ability off cooldown right now?** | `recast.readyFor(sig[, reader])` → `ready, remaining`; `.remainingFor(sig, reader)`; `.timerIdFor(sig)`; the shipped signatures `recast.rewardReady()` / `.callBeastReady()` / `.bestialLoyaltyReady()` | `feature/recast.lua` (issue #138) | THE live ability-recast read — dlac had none before this (`nativedata` carries the STATIC `RecastDelay` off the resource; `useitem` reads ITEM charge timers; neither answers "how long until I can use this again"). **UNKNOWN reads READY** — a recast we cannot measure must never be the reason a player cannot press a button, and the Action sequencer's own verify-worn is the real safety net, so this gate is a COURTESY: it grays a button and holds a rule *silently*, and never manufactures a refusal it did not measure. Pure core + injected `reader` (headless tests RC*); the live reader scans the client's 32 ability-recast slots, which store **JIFFIES (1/60s)** — corrected 2026-07-30 from a `/4` quarter-second guess borrowed from `nativedata`'s RecastDelay (a RESOURCE field, a different unit): every countdown dlac showed was 15x too big, settled by two independent addons on disk (`timers
ecasts.lua` builds `60 * (90 + reduction)` “to get the same format as timer is stored in”; Rune-Actually-Helper divides by 60, “jiffies -> seconds”). Converted to whole seconds so the core, the tests and the sequencer timeout all speak one unit. **READY and UNKNOWN are different answers** and `remaining` is what separates them: **0** = resolved and on no slot (measured idle), **nil** = the slot never resolved. Both still read `ready = true` to a button — but a caller CHOOSING between two abilities needs the difference, and not having it is exactly how the Resummon rule preferred an unmeasurable Bestial Loyalty over a Call Beast it could see was up (field 2026-07-30). A signature's declared `timerId` wins; otherwise the slot is resolved **by NAME** through the client's own ability resource. **That path never once worked until 2026-07-30, and the reason is one guard**: Ashita's resource objects are NOT Lua tables (they index with `.` and answer `userdata` to `type()`), and this file tested `type(rec) == 'table'` where every working reader in dlac and in the sibling addons tests `~= nil` — `nativedata` (`res ~= nil` then `res.RecastTimerId`), `dispatch`'s item lookup, Rune-Actually-Helper. So every by-name resolution answered UNKNOWN, unknown reads READY, and the Resummon rule fired a summon into its own cooldown while its fallback sat unused. **Reward hid it for months**: it declares `timerId = 103` and never takes the name path, so its countdown always worked. Field reads now go through `M._field` (nil-guarded, pcall'd, a real seam — stock Lua cannot fabricate userdata with fields, so proving the guard needs the read to be replaceable). Belt and braces beside it: several name indexes are probed (dlac already hedges two for items in two places) and, when none answer, the whole ability table is walked ONCE and indexed by name — latched only when it produced something, throttled because the caller is a Panel — live game memory over every other source (hard rule 9) — so an ability this server renumbered still resolves, and a failed resolution is NOT latched (hard rule 11). `REWARD = { id = 103, timerId = 103 }` is hand-ported from the approved Pup-Helper reference (`docs/reference/pet-handling-other-luas.md`) and is FLAGGED for field verification; the two summon methods deliberately carry no hardcoded slot. Consumers: the BST Helper's "Reward now" gray-out, its Reward rule's silent hold, and Resummon's method pick + queue. |
| **What is my combat situation, and what just changed?** | `combat.get()` → `{ engaged, targetIndex, targetName, targetChanged, changedBy, swung }`; `.subscribe(who, cb)` / `.unsubscribe(who)`; `.onEdge(who, cb)`; `.lastEdge()`; `.fromReads(reads, prevTarget, edges)` (pure) | `feature\combat.lua` | THE combat read for a standing rule, and the service that ended dlac having TWO half-answers to one question. Publishes a state record once per `TICK_S` = 0.4 s (the engine's own dispatch beat) and **reads nothing at all while nobody is subscribed**, so it costs nothing on a job with no combat helper installed. Its one design decision: **`targetChanged` is answered by the retarget EDGE when one arrived (`changedBy = 'edge'`) and by its own poll otherwise (`changedBy = 'poll'`)** — it bridges `feature\engagewatch` rather than decoding anything itself (hard rule 7.3), collecting accepted edges into a bounded inbox that each beat drains. That split IS the field history: the edge is the only witness to an A→B→A switch inside one beat and the only one that can tell a real change from a recycled entity index, while the BEAT is the only thing that supplies a **retry** — a refused command leaves the world unchanged so the next beat tries again, where an edge fires once and a server refusal is lost. `targetIndex`/`targetName` are for DISPLAY and change detection: a command carries `<t>` and resolves at execution, which is the round-2 lesson encoded so no consumer relearns it. UNREADABLE STAYS UNREADABLE — `engaged`/`swung` ride through as nil rather than false, because each consumer must decide which way its own nil goes. `get()` has no cache and deliberately answers `targetChanged = false` ("changed since when?" has no meaning outside a beat). Consumer: the BST Helper's Fight switch (`jobhelpers\bst\bst-helper\fight.lua`). |
| **Who holds this key, and with what?** | `keybinds.register(owner, key, command, label)` → `ok, info`; `.holder(key)` → `{ owner, label, command }` \| nil; `.heldBy(owner)`; `.syncGroup(prefix, entries)`; `.release(owner)` / `.releaseGroup(prefix)` / `.releaseAll()`; `.list()` (and `/dl binds`) | `feature/keybinds.lua` (ADR [0032](adr/0032-keybinds-are-registered-not-issued.md)) | **THE one place a `/bind` is issued.** Before it, Modes bound from the trigger loader and the window bound `^k` from `dlac.lua`, and neither could see the other: `_boundKeys` was a DEDUPE MAP, so nothing could ask *is this key taken, by whom, with what* — and nothing ever RELEASED a key, so a mode from the job you left kept its bind all session. Rules: a taken key is **REFUSED and its holder NAMED** (once per owner+key, so a loader that re-parses thirty times a minute does not say it thirty times); owners are **namespaced strings** (`mode:weapon`, `jobhelper:bst-helper:summon`, `dlac:ui`) and hold **at most one key** (registering a second MOVES it, and a move that is refused leaves the old one intact); `syncGroup` is the per-job door — releases what is gone, binds what is new, and leaves an unchanged bind **entirely alone**, which is the field-reported `/bind`-storm guard now owned by the registry instead of by each caller. Job-helper keys are installed by the FRAMEWORK (`jobhelpers.pumpBinds`, 1s, gated on main job + row pill — NOT the full activity predicate, or a key would appear and vanish under the player's fingers), so a module declares `commands[action].key` naming one of its own config keys and never touches the registry. `dispatch.lua` keeps `_boundKeys` as the degraded twin path. |
| **What may a Job helper module call?** (the **Module API**) | `modapi.build(rec)` → `S`; `.dropAll(id)`; `.subscriptionCount(id)`; `M.API` | `feature\modapi.lua` | The ONE table a module is handed — see CONTEXT.md, *Module API*. Minted per module by the loader and closed over its identity, so a module can neither declare its own id nor ask a question as another. Entries are named for the QUESTION (`S.item.own('Carrot Broth')`) rather than the service, and are mostly plain REFERENCES — a curated namespace, not a translation layer, so it cannot drift from what it names. Three properties are structural rather than remembered: subscription keys are namespaced by identity (`jobhelper:<id>:<rule>`), every subscription is RECORDED so `dropAll` can undo them, and an Action-sequence request is stamped with the module's own id and `sectionOrder`. **Not a sandbox** (ADR 0028) — `S.service(path)` is the documented, unsupported escape hatch, named so that reaching past the front door is visible in a diff. `M.API` is the version the loader gates on, re-exported as `jobhelpers.API`: it lives here because what a module depends on is the SERVICE SURFACE, not the shape of the contract table. Every read is contained — a service that failed to load degrades one answer and never throws into a module. |
| **Where do a module's settings live?** | `modcfg.open(id, spec[, charDir])` → a store (`.get`/`.set`/`.forget`/`.path`/`.keys`/`.defaults`); `.validate(spec)`; `.serialize`/`.normalize` (pure); `.fileFor(id, spec)` | `feature\modcfg.lua` | The **Statefile** policy, once, for every module that will ever exist: a module DECLARES `config = { file?, keys, defaults }` on its contract table and the framework owns the format. fmt-versioned; declared keys of the declared type ONLY (so a hand-edit, a torn write, or a key from a newer dlac cannot survive silently into an older one); written on MUTATION only; loaded once per character, re-keyed on the char dir; **never caches the pre-login nil** (reads answer the declared default, writes return false, both retried — hard rule 11); sorted output so an unchanged config re-serializes byte-identical. Scalars only. A store is closures over ITS OWN state, so N modules get N independent stores from one policy. A malformed declaration is a LOUD load refusal, not a silently dropped write. Replaces the 193-line per-module `config.lua` the api-1 guide told authors to copy — copy-paste is a poor way to distribute a policy. |
| **How does a module draw its Panel?** | `panelkit.bind(im)` → the kit; `header`/`section`/`toggle`/`choice`/`slider`/`combo`/`button`/`pill`/`ruleStatus`/`ok`/`warn`/`dim`/`err`/`disabled`/`space`/`rule`/`sameLine`/`widthFor`; `esc`; `M.COL` | `ui\panelkit.lua` | dlac's field-proven ImGui patterns AS WIDGETS, handed to a Panel as `ctx.ui` already bound to the host's handle (every function takes `im` first — the `uistyle.helpLabel` contract, and not cosmetic: the smoke suite renders against a stub binding). Encodes, as default behaviour, seven lessons prose could only ask authors to remember: presence proves nothing so every call is guarded and degrades to text (hard rule 2 — `BeginPopupContextItem` is bound here and does not work); `RadioButton` is used nowhere, so an exclusive choice is a lit/unlit Button pair; widths are MEASURED (a hardcoded one has clipped a trailing character in the field); exclusive choices STACK vertically (the right-hand Panel child is what is left of a 480-minimum window); the panel-text standard (label underlined, explanation in the hover — never an inline paragraph); **every imgui text call is a `printf` FORMAT string, so the kit escapes every string it draws and every tooltip it attaches** (`esc`, the one function `bind` carries over UNWRAPPED — a handle-first wrapper would escape a table address; `below 51% pet HP` reached the field as `below 51F4A60263et HP`, 2026-07-30); and Push/Pop balance on every path, including the failure paths. `ruleStatus` owns the status PRECEDENCE and its colour split — dim when the player turned it off, **warn only for something the player can FIX**, ok when armed, dim for the last decision — because "no pet out" / "above the threshold" / "waiting out the lockout" are the rule WORKING and colouring them orange would cry wolf all session. Also THE one on/off pill: `ui\craftbar.onOffSwitch` (the hobby bars' entry point) delegates here. |
| **Act with gear or ammo worn FIRST** (the **Action sequence**) | `actionseq.request(req)` → `{ ok = true }` \| `{ ok = false, reason = 'busy', holder, holderLabel }`, where `req = { module, label, order, claim = {SlotKey=item}, need?, command, timeout, hold? }`; `.tick(now, io)` (pure); `.arbitrateRequests(reqs)`; `.claim()` / `.active()` / `.state()` / `.statusText()`; `.pump()` | `feature/actionseq.lua` (issue #138) | THE one door for a **Job helper** act with an equip PRECONDITION — **ADR 0030**, "a module owns initiation". Lifecycle `claimed → verified worn → fired → released`, with `refused(reason)` / `aborted(reason)` the two failure exits. **Never-fire-bare:** the command sends only after every `need` slot reads worn, and exactly once (`_fired` is a latch, not a hope); `need` defaults to the whole `claim`, and keeping it to the CONSUMED slot alone is deliberate — claimed-but-not-needed slots dress best-effort, which is also what lets a player's own precast Trigger compose with a food-only claim. A DEFINITIVE blocker on a needed slot (Free equip, Locks) **refuses loudly**; gear that never lands inside `timeout` **aborts**; success is **SILENT**. **ONE sequence live addon-wide and a started one is NEVER preempted** — a request arriving mid-sequence is refused naming the holder; simultaneous contenders resolve by the current job's module order (`jobhelpers.sectionOrder`, higher wins, ties by module id — no `pairs()` dependency, hard rule 8). It rides the ONE shared `JobHelper` claimant row (default rank directly below Locks, per-job position), so the standing rank walk decides every contested slot and nothing punches through Locks / Naked / Free equip. **Release restores by RE-ARBITRATION** (`dispatch.kickDefault`), never from a snapshot — the sequencer owns no gear memory. Pure state machine + injected io (`worn / blocker / fire / release / emit`) so the whole lifecycle drives headlessly (AS*); `pump()` (dlac.lua's `d3d_present`) wires `dispatch.wornName`, `disabledOn`/`isLockedSlot`, the command bus and chatfmt. A bare command that needs nothing WORN does **not** open a sequence — it goes through `lib/cmdqueue.issue`. Consumers: the BST Helper's Reward act (button + rule) and Resummon. |
| **Is the game hiding its own interface?** (Scroll Lock) | `gamehud.hidden()` → `true` \| `false` | `feature\gamehud.lua` | FAILS OPEN — unmatched signature, null pointer or headless all answer `false`, because a UI that vanishes on a bad read is unexplainable to a player. The SCREENSHOT flag only: cutscenes and the fullscreen map have their own signatures and dlac deliberately does not fold them in (xivbar/HXUI do). One consumer, and there should only ever be one: the gate in gearui's `d3d_present`, above the first imgui call and below every per-frame pump. |

Adding a new central service: generic plumbing goes in `lib/`, game-domain
answers in `feature/` or `data/`; give it the gamemode shape (one exported
question, injectable reads, headless tests) and ADD IT TO THIS TABLE.

## Module reference

### dlac.lua — addon entry point
The Ashita addon shell. Sets `addon.*` metadata, installs the `require` path shim that
lets profile-style `require("dlac\\X")` resolve inside the addon state, preloads the
character's real `gear.lua`, seeds the library into the per-char LAC folder, provides a
`gData` shim for standalone operation, then loads the library modules.
Key points: `package.path` shim (dlac.lua:27-29); per-char `gear.lua` preload into
`package.loaded['dlac\\gear']` (34-50); library seed to `<char>\dlac\` (57-76); `gData`
shim (job/level from AshitaCore) (82-107); module load loop (111-119).
Requires `common` and `chatfmt`, then loads a folder-qualified list — `gear`,
`feature\augments`, `gear\gearoptim`, `gear\gearimport`, `gear\gearexport`,
`feature\useitem`, `feature\craftwatch`, `feature\synthrun`, `ui\craftbar`, `feature\helmwatch`,
`ui\helmbar`, `feature\fishwatch`, `ui\fishbar`, `feature\lockstyle`, `ui\gearui`;
everything else (`utils`, `dispatch`, `gear\setmanager`, `ui\triggersui`,
`ui\automationsui`, `gear\profilesets`, `gear\gearcheck`) loads transitively. That list is built by string
concat (`'dlac\\' .. mod`), so a grep for a literal `require('dlac\\gearexport')` finds
nothing — the loop is the only loader for some modules.
**Writes** `<char>\dlac\{utils,dispatch,chatfmt,profiles}.lua` every load (always flat —
see Repository layout); seeds `<char>\dlac\gear.lua` only if absent.

### utils.lua — profile-side rebuild engine
The single `require` a migrated profile needs. Re-exports the gear inventory and the
dispatch entry point, and owns the level-scaling **Dynamic-set rebuild** engine plus the
dual-wield / sub-slot pairing rules (H2H pairs with NOTHING — decided by Type via
`isH2H`, never the OneHanded flag, which lies for H2H; ADR 0006 addendum 2026-07-22).
Refreshed into every character's `dlac\` folder on each addon load.
Exports: `M.rebuildSets(sets)` (utils.lua:120-129); `M.BuildDynamicSets(sets)` (212-372,
virtual-entry handling 251-254 and 350-356); `M.subSlotAllowed` (193-210);
`M.classifySub` (176-185); `M.isDualWieldAvailable` (131-171, trusts `HasAbility(1554)`);
`M.determineLevels` (65-83). Registers the base `/dl` command handler (397-479).

### chatfmt.lua — chat styling
The one place defining dlac's colored `[dlac]` chat header (coral name, distinct from
LAC's teal). Provides a drop-in `print` that re-heads `"[dlac] "`-prefixed lines. Nearly
every module requires it (guarded) to shadow `print`.

### dispatch.lua — trigger dispatch engine
The heart of the trigger system, running in the **LAC state**. Reads the per-job trigger
file, matches the live action/player against each rule's `when`, and `EquipSet`s every
match in ascending priority (overlay, ADR 0003). Also resolves virtual slot entries
(auto staff/obi), owns session mode/lock state, and serializes trigger files for the GUI.
Key points: `M.VERSION` (35, engine-staleness handshake — bump when seeded behavior
changes); matcher table `MATCHERS` (170-205); specificity `TIER` (212-220); hot-reload
`ensureLoaded` (307-387, content-compare, throttled 1/s); automations `resolveStaff`
(451-471) / `resolveVirtual` (474-510) / `equipResolved` (521-560); `M.dispatch(event)`
(644-724); `M.serializeTriggers` (757-825); mode state mirror `saveModeState` (833-851);
command handler (946-1079).
Reads/writes `<char>\dlac\triggers\<JOB>.lua`; reads `<char>\dlac\autogear.lua` and the
per-feature state files (`craftstate`/`helmstate`/`fishstate`/`pinstate`/`ammostate`);
writes `<char>\dlac\modestate.lua`. Since v73 it also owns the **AutoAmmo overlay**
(docs/design/auto-ammo.md): a per-event Ammo-slot decision with the engine's first bag
counter and the literal-`'remove'` plan (LAC's native unequip) — pure core
`M.resolveAmmoPlan`, tests AM*.

### gear.lua — owned-gear template
The **per-character owned-gear** record: thin entries (Name/Level/Id + weapon metadata)
for items the character possesses; empty in the repo (the repo copy is only the seed).
Builds a `NameToObject` reverse index. Stats are NOT stored here — they derive from the
catalog by Id at load.

### data/catalog.lua — CatsEyeXI equipment reference (~5.8 MB, generated)
The full crawled equipment reference — base-truth stats for every item. Same nested
shape as gear.lua (`Slot -> [weapon Category] -> PascalCaseKey -> {Name, Level, Id, Jobs,
OneHanded, Type, Stats}`). Consumers flatten it into an Id index (`_allEquipById`).
Rebuilt by `tools/apicrawl.py` (gitignored). The dispatch engine never loads it (ADR
0004) — only the addon state does.

**The source is not clean, and `Slot` is where it lies (2026-07-15).** CatsEyeXI's
`item_equipment` table carries rows for **unimplemented** items, with no marker and
default values: `jobs=0`, `MId=0`, and **`slot=32`, which decodes to Body**. 258 of the
259 therefore land in the **Body** bucket — `Gletis Crossbow`, `Mpacas Bow`, `Pinaka`,
the Amini/Boii `+2`/`+3` reforge tier — which is exactly why the lockstyle picker once
offered crossbows and boots for Body. apicrawl now skips `jobs == 0` rows (Body: 1743 →
1485), so a current catalog is clean; `smoke_ui` **S21** fails if a re-crawl puts them
back. Two rules if you touch this: **`jobs==0` is the marker, not `MId==0`** (the latter
also covers 814 *real* modelless items like all `Hexed` gear, whose stats the catalog
must keep), and **an empty jobs mask is not "All"** — the decode used to publish these
stubs as equippable by every job. Details: `tools/README.md` "The junk rows".
Consumers must not assume a catalog `Slot` is the client's truth; the bag scan slots
owned gear from the CLIENT resource (`gearimport.slotFromMask`), which is authoritative.

### gear/gearimport.lua — inventory reader + gear.lua writer
Reads owned equippable gear from Ashita memory and turns it into gear.lua entries; owns
the scan→stage→commit pipeline, plus fix/dedupe/prune maintenance and the silent
auto-sync.
Key points: `M.SCAN_CONTAINERS` (availability: Inventory + 8 Wardrobes) vs
`M.ALL_CONTAINERS` (ownership truth: everything) — see ADR 0005; `M.scan`; `M.stage`;
`M.commit(quiet)` (gearimport.lua:934); `M.fix` (catalog-metadata backfill);
`M.dedupe`; `M.prune`/`M.pruneWhy`; `M.sync()` (scan→stage→commit only when new gear
exists, add-only) (1457); command handler (1483+).
Writes `<char>\dlac\gear_staging.lua`, `<char>\dlac\gear.lua`, rotated backups in
`<char>\backups\`. Every write is backup + parse-checked + sandbox-validated, aborting
untouched on failure.

### ui/gearui.lua — main GUI (host client + Sets core)
The main ImGui window shell (header buttons, Setup plan popup, tab bar) plus the Sets
machinery (working set model, auto-build, candidate pools, scoring, slot grid, stats
panel, item tooltips). Everything else moved out behind uihost (below). gearui still
owns the three Ashita hooks (`d3d_present` / `packet_in` inv-dirty / `command`) and the
shared `ui` view-state table, publishes the shared services via `host.provide{}`, and
registers its own Sets tab + the weights window like any other module.
Was pinned at EXACTLY 200/200 LuaJIT main-chunk locals (compiler-verified); now ~134
with `tests\smoke_ui.lua` guarding the cap. New features MUST still be born as modules —
register a tab/window via uihost instead of adding gearui locals.

### ui/uihost.lua — UI module registry (the Trove plugin model, v40)
`host.register({name, tabs = {{label, render}}, window = {render}, invalidate})` +
`host.provide{}`/`host.services` (ONE live table gearui fills before requiring tab
modules — modules may capture entries at load). Registration order = tab order
(Equipped, All Equipment, Sets, Triggers). Deliberately unlike trove/utils/plugins.lua:
a STATIC require list (no `io.popen` discovery — popen spawns console windows), and
renders run under the caller's guard (gearui's `tabGuard`). Extraction set that rode in
with it: **itemicons.lua** (D3D texture cache: `renderIcon`/`handleOf`/`release`, no-op
safe headless), **equippedui.lua** (Equipped + All Equipment tabs; captures
host.services at load — provide-before-require is load-bearing), **setupui.lua**
(`jobSetupState` + `migrateCurrentJob`/`migrateToCleanProfiles` — THE SETUP
STANDARD, 2026-07-17: an existing job file never stays live; it is verified into
`backups\pre-profiles\` and replaced by the clean shim (convert-in-place is dead);
starter profile/trigger seeding; `setup.configure{}` deps), **syncflags.lua** (auto-sync loop + uiflags.lua
persistence; owns `sf.flags.debug`/`sf.flags.autosync`/`sf.flags.viewids`; gearui's d3d_present calls
`sf.loadUiFlags` BEFORE `sf.tick` — order is load-bearing, the real gear.lua must swap
in before the first sync), **weightsui.lua** (stat-weights editor: Points + Priority
tabs, sortable columns, clear buttons; scoring stays in gearui/gearoptim),
**profilesmenu.lua** (the Profiles popup tree + forms; state in the shared ui
table), **floatgear.lua** (the floating 4x4 equipment window + the PIN menu — v44; a
`window`-only module, no tab; reuses `S.renderSlotGrid` so its icons and hover tooltip
are literally the Equipped tab's and cannot drift), **wishlistui.lua** (the Wishlist
window AND the item context-menu **body** — a floating window, no tab; the menu body
lives here rather than in the tab that right-clicks so future rows like `Move To ▸` join
`Wishlist ▸` without moving house). `tests\smoke_ui.lua` headless-loads
the whole chunk: 200-cap breaches, registration order, services contract.

### Floating windows — many openers, ONE draw site
A **Floating window** (CONTEXT.md) is *not* a `host.register` window: those render inside
`drawWindow`, which returns early when the main box is shut. A floating window is drawn
from gearui's `d3d_present` **above** its `if not M.visible then return`, so it survives
the main window closing — which is the entire point of every one of them (lockstyle,
floatgear, the Trigger Monitor, the icon tray, the two Chocobo dig searches, the
Hobby bar, idlefloat, the fishing target window).

#### The icon tray — ui/tray.lua (2026-08-03)
The always-on **icon chips** are one window, not several. The Teleports button and the
E-Box Restock crates each used to `Begin` their own float, which put two little boxes on
the same screen doing the same kind of job — and made them enforce a shared 36×36 button
size by *comment* (`NUDGE_SZ`/`NUDGE_PAD` "change these together with gearui's, or they
drift"). This is ADR 0017's hobby-bar move applied to the floats: **one window supplies
the chrome and the position, each member draws its icons inline.**

A tray **slot** answers two questions:

| | |
|---|---|
| `trayWants(deps) → boolean` | a **cheap** gate — flags and proximity only, no bag scans |
| `trayDraw(deps)` | draws inline: no `Begin`, no position, and never opens with `SameLine` |

Two phases, and the split is the point: **every member is asked before anything is
drawn**, because an `AlwaysAutoResize` window begun with an empty body is not nothing —
it is a grey box parked on the player's screen that eats clicks. Nothing in the tray
decides *when* an icon shows; that stays with each member (Teleports because you pinned
it, the crates because you are near a box). The tray only stops asking for a window once
every member has gone quiet.

**The axis is top-to-bottom** (Henrik, 2026-08-03): one column, one icon per line, and
**nothing in the tray calls `SameLine`** except a badge sitting beside its own icon.
`AlwaysAutoResize` pins the window's top-left and grows it down and right, so a column
keeps the tray hanging off the corner you dragged it to instead of creeping sideways
across the screen as icons appear.

**Order is a ruling, not a layout detail** (Henrik). `SLOTS` reads top-to-bottom with the
**constant members first**, and each member orders its own icons the same way, because a
member that comes and goes shifts everything *below* it. Store is one click, no confirm,
and deposits your whole Inventory, so it is anchored at the top of the crates (it used to
be drawn last, so every appearance of the green crate pushed it down a row) and only the
two volatile ones — green with "Only when needed", yellow with your Mog House stock — can
shift each other.

Position is `ui._tpPos` (`tpx`/`tpy` in uiflags) — the Teleports float's own saved spot,
inherited deliberately: the tray takes **one** position, so this way the button you
pinned stays where you put it and the crates come to *it*.

The invariant, and the only thing that makes them safe to open from several places:

> **Any surface may OPEN a floating window; exactly one place may DRAW it.**

Openers set a module-owned `open` flag (`chocoui.openAreaSearch`, `fishui.openTarget`) —
they never call the window's own render. Two `imgui.Begin()` calls on one window name in a
frame do not error: ImGui *appends* the second body into the same window, so the content
renders twice, widget ids collide, and any shared buffer is written twice per frame. That
failure is silent and looks like a UI bug, not a crash — the floatgear S50 class.

Two consequences worth stating: the render call site is where `deps` comes from
(`M._deps`, built once at gearui load), so an opener never needs it; and the window body
must re-derive its own data rather than take it from whatever panel used to hold it —
`fishui.renderTargetBody` re-reads db/owned counts/skill for exactly this reason.

### Wishlist — ui/wishlistui.lua + feature/wishlist.lua (ADR 0026)
Gear you mean to own. The model file (`<char>\dlac\wishlist.lua`) is id-keyed and carries
the item NAME because the **engine** reads it: `utils.warnMissingGear` asks
`wishlist.isWished(name)` before calling an unresolvable set entry a typo, which is the
one and only reason the engine knows this feature exists. Everything else — slot, level,
icon, stats — is looked up from the Catalog by the UI.

The shape worth remembering is the split (see CONTEXT.md's **Wishlist link**):

> **The stored half is an intention. The computed half is a fact. Neither is derived
> from the other, and they are allowed to disagree.**

A link (`WHM/Idle`) is written down and never revoked by dlac; whether the piece is *in*
that set is re-read from the set files (`wishlistui.whereInSet`, all jobs, cached per
window-open). Ownership follows the same rule — never stored, read from the bags by Id.
So there is no reconcile step anywhere, and the disagreement is not a bug to fix but the
signal that puts an **Apply** button on that row. Apply writes through
`setmanager.commitSet(job, …)` — which already takes a job, so any job's set can be
edited — and refuses while the Sets tab holds uncommitted edits to that exact set.

Set files are UNCHANGED by design: an unowned name is skipped by `BuildDynamicSets`
(`resolveGearName` misses → `warnMissingGear` → return), so the slot's real
best-by-level pick wins and the piece starts being worn the day it lands in the bags.
The one thing that had to be fixed for that promise to hold is the **apostrophe**: the
API drops the possessive (`Arhats Gi`) and keeps `San D'Orian`, so `resolveGearName`
strips on both sides, as a fallback layer beneath the exact-lowercase index.

### Pins — floatgear.lua + feature/pinwatch.lua + dispatch v44
"Equip item, lock slot so nothing removes equipped item" (Henrik), built as an OVERLAY
rather than a lock — the same shape as the craft overlay, for the same reason (a lock
is passive and leaks; an overlay is recomputed every dispatch). **`floatgear`** edits
the table, **`pinwatch`** writes `<char>\dlac\pinstate.lua`, and the ENGINE wears the
named items as the LAST `equipResolved` of every dispatch — above the craft overlay, on
every event. Unpin → overlay gone → the normal set returns.

`scope` is `'All'` or a list of `"<Event>|<rule label>"` keys, spelled by
`dispatch.pinScopeKey` over `dispatch.ruleLabel` — ONE definition each, called from both
Lua states, because a label the two states spell differently is a pin that never
matches. Pins are session-only and the clear must reach DISK (`pinwatch.loadPinState`,
pumped from gearui's d3d_present whether or not the window is open): the engine reads
the file from LAC's state, so a stale file would dress you at login. "Lock" still means
the old, near-opposite thing (`M.locks` = engine ignores the slot).

**A slot holds SEVERAL pins** (2026-08-03) — Optical Hat on `TP_Default`, Walahra Turban
on `Movement`, both live. The slot's value becomes a *list* of `{ item, scope }` entries
and the engine settles it per dispatch, because an overlay is an equip table and a slot
wears one thing. The settling rule is not new, it is borrowed: `dispatch._pinRank` scores
each entry by **the index of the last hit it names** — `hits` is already sorted ascending
by priority and applied last-writer-wins (ADR 0003), so *the pin belonging to the trigger
that would have won the slot anyway is the pin that wins it*. `'All'` scores 0, the
weakest claim there is: "always" is the least specific thing a pin can say, which makes an
All pin the natural fallback underneath its scoped siblings rather than a competitor.

On the way IN the rules are pinwatch's: `'All'` replaces the slot whole (Henrik), a scoped
pin replaces only the pins already holding one of the same triggers (one item per trigger
per slot). A one-pin slot still serializes in the *original* single-entry shape, byte for
byte — the list shape appears only where a second pin actually exists, so the common case
never touches the new path and an older engine copy reads the file unchanged. Both states
read the shape through the same walk (`pinwatch.entriesOf` / `dispatch._pinEntriesOf`),
spelled twice on purpose: the engine runs in the other Lua state and must never depend on
an addon-state module being loaded.

The floating window's pin menu offers **only what you can put on at that moment** — the
job/level half was always the Gear Oracle's `canWear` (via `candidatesForSlot`), the bag
half is `gearui`'s `avail.have`, the same function the Sets tab previews the engine's own
refusal with. Three-valued there and here: only a definite `false` hides a row, because an
empty bag scan means "not answered yet", not "you own nothing".

### The Arbiter — claim registry (dispatch.lua + feature/arbwatch.lua, ADR 0012)
The **single precedence authority** for gear that dresses over the Trigger overlay floor.
Every feature that wants a slot registers a **Claim** with the Arbiter instead of equipping
directly; per slot the Arbiter walks a strict, draggable rank list top-down and the first
claimant with an opinion wins. The rank is one per character, persisted as the `arbstate`
Statefile (writer: `feature/arbwatch.lua`; reader/default/sanitize: `dispatch.arbOrder`,
one vocabulary). Default order **Naked > Pins > Locks (veto) > AutoAmmo > MaxMP > Craft >
HELM > Fishing > Chocobo > Triggers (floor)**.

A rank row the character's `arbstate` file does **not** list is restored at its *default
position*, not appended (v122) -- every existing file predates every new claimant, and
appending would have shipped `Naked` below `Locks` for everyone who had ever opened the
Priority section. That one positional law subsumes the old append and the Triggers-last pin.

**The Claim record shape** — deliberately tiny, because a new claimant must be *one
registry entry + one rank row, never a new engine arm*. (**AutoAcc is NOT a future
claimant** — Henrik's ruling 2026-07-21: it is a Type automation, per-piece candidate
release while over the hit cap, any slot — within-set resolution, the altitude below
the Arbiter. Its effect is part of whatever the floor or a claimant resolves.)

- A **Claim** is just `{ [SlotKey] = itemName }` — the slots a feature wants to dress, one
  item per slot. The Locks veto is a Claim whose values are the `M.LOCK_HELD` sentinel
  ("keep what is worn"); the Triggers floor is the merged trigger-overlay table.
- **Naked** (ADR 0021) is the worked example of the shape: a Claim of `'remove'` on all 16
  slots, ranked first. Because it is an ordinary draggable row, "naked except my pins" is a
  drag rather than a code path -- put Pins (or Locks) above it.
- To join the Arbiter a claimant adds exactly two things: **(1)** its name to
  `ARB_ORDER_DEFAULT` (+ the arbwatch UI list), and **(2)** in `M.dispatch`,
  `claims['<Name>'] = <its slot→item table>` plus — if it applies a discrete overlay —
  one `applyClaim` closure keyed by the same name. Who wins each contested slot, ceding,
  the Locks veto and `/dl why` attribution all fall out of the rank list automatically.

**Pure seams** (all headless-tested, tests `AR*`/`LV*`): `arbResolve(claims, order, floor)`
→ winners + `by` attribution; `arbCededAbove(claims, order, who)` → slots a claimant must
not contest (won above it); `arbLockClaim(locked)` → the veto Claim; `arbExplain` /
`arbWhyLines` → the per-slot `/dl why` claimant lines ("`Ammo: Ammo rule (rank 3) over MaxMP
(rank 4)`"; veto slots read "stopped by Locks"; the slots the floor dressed uncontested
collapse into one trailing "Triggers floor (uncontested): …" summary).

**MaxMP is the worked example of the boundary.** It registers a Claim (`mpClaimFor` → its
battery targets) so its *precedence* is fully in the registry, yet its *equip* stays WOVEN
inside `equipResolved` — hold/release/upgrade, sticky pairs and movement yield are
**within-set resolution**, deliberately OUTSIDE the Arbiter (ADR 0012). Also outside, by the
same rule: sync-settle/proximity holds, the PetAction gate, AutoStaff/AutoObi virtual
entries, Dynamic flattening and the ADR 0010 trinket contests. The Arbiter arbitrates
*between* claimants; each claimant's *own* conditions (idle-only stand-asides, AutoAmmo's
fishing stand-down, `'remove'`-respect) stay inside the feature.

### ui/triggersui.lua — Triggers tab (+ Groups section)
GUI editor for the dispatch engine's data: rules per handler, mode toggle buttons.
Split out of gearui for the 200-local cap. Commit rewrites the trigger file via
`dispatch.serializeTriggers` and pings the engine to hot-reload. Writes
`<char>\dlac\triggers\<JOB>.lua`. The gear-helper machinery lived here until
2026-07-18 — it is now `ui/automationsui.lua` (below), which freed 30 of this
module's 123 top-level locals (cap 200; the "noted 200-local relief", done).

Also owns the **Groups section** (`M.renderGroups`, issue #25 / ADR 0009) — a nav
section inside the Triggers tab (NOT a uihost tab; smoke_ui asserts `host.get('groups')`
is nil) that edits the *same* file's
`Groups` section, so both surfaces share one `trig.data` / one Commit. The pure CRUD +
name/member validation is `gear/groupsmodel.lua`; the `group` trigger condition's value is a
dropdown of the job's groups, and a rule pointing at a missing group is surfaced (parity
with a missing set). Members are added by free-name typing or from a searchable,
job-filtered spell/ability browse-list with multi-mark (issue #26, G3 — pure list/search
core `gear/actionpicker.lua`).

Also owns the **Blueprints section** (`M.renderBlueprints`, issue #65 / PRD #64) — the same
Groups-style nav section (NOT a uihost tab; smoke_ui asserts `host.get('blueprints')` is nil).
A per-rule **"bp" (Save as Blueprint)** button on every trigger row captures the rule into the
per-character library (`gear/blueprintsmodel.lua`, `<char>\dlac\blueprints.lua` — outside
Profiles, addon-state only); the section lists the library with **Stamp onto this job** (insert
the rule into the current job's Handler and commit through the SAME `trigCommit` path — engine
hot-reloads it, no Reload LAC; warn-but-allow on an identical rule), **Edit** (the existing rule
editor bound to the library entry via `trig._bpEdit` — no second editor, never retro-edits
stamped Triggers), rename and Delete. Library writes go through the `lib/safewrite` ladder.

And the Blueprint's one-shot sibling, **"copy to…"** (2026-08-02): a per-rule button opening a
window with **two tick-lists**, because a trigger file is addressed by two coordinates
(`profiles\<Prof>\triggers\<JOB>.lua`) and a copy varies one of them — **Jobs (this profile)**,
the main event, and **Other profiles (same job)**. Each list owns its rows, its **All** button
and its own Copy button, so the two can never cross ticks, counts or receipts. **All** ticks
every writable row that does NOT already hold an identical rule (`rulecopy.allNames`): the
duplicate check is the feature, and a bulk button that spent it would silently double a rule
across 21 jobs on one click — a duplicate stays reachable by ticking that row by hand.
Whichever coordinate the rule already lives at (the job you are on / the active profile) is
shown dim and untickable. **"Include the set if it isn't there"** is a tick in the window (not
a Setting — it belongs to the copy, not the character; default on): any set the rule NAMES that
the destination lacks is carried across with it via `setmanager.copySetText`, **verbatim** and
**never overwriting** an existing name, so the rule does not land equipping nothing. The window
opens straight onto the job list — no title, no subtitle, no rule text (Henrik: *"remove all
the text above the job list, it's bloating"*); what explaining remains lives in hovers.

Pure core `gear/rulecopy.lua` (below); the file ladder is triggersui's — each target is
**re-read at write time** (the rows are a snapshot; both Lua states and a parallel session
share the disk), a torn target file is **refused, never overwritten**, an existing file is
backed up timestamped into `<char>\backups\rule-copy\` and replaced through `lib/safewrite`,
and the result is read back; a backup that cannot be written **refuses the overwrite** (the
profiles-deleter house rule). The live job entry is never a target, so nothing hot-reloads —
the copies are simply there on the next job (or profile) change.
`M.renderTrigCopyPopup` / `M._cpOpen` are exposed as headless render seams (smoke_ui CP*, the
`renderTrigRuleBox` precedent: a popup body only runs while open).

### ui/automationsui.lua — the Gear Helpers tab + the manifest machinery
(Tab label renamed Automations → **Gear Helpers** 2026-07-28; module/file/key names are
unchanged, see "Naming" below.) The whole block, extracted verbatim from triggersui 2026-07-18 (it owned
30 of triggersui's top-level locals and shared nothing with the trigger editor beyond
the deps table). Owns DERIVING the manifest — staves/obis/Iridescence (ADR 0004),
MaxMP battery ladders, craft/HELM/fish gear ladders — from the player's bags via
`deps.ownedList`/`lookupByName` (plus `lookupById` for id-PINNED entries: relic
stages share one display name, so 'Laevateinn' pins 18994 / 'Tupsimati' 18990 —
the only stages carrying Iridescence on live; a name-resolved record with the
wrong id is rejected, never adopted), and writes `<char>\dlac\autogear.lua`
(`AUTO_FMT` schema; an outdated on-disk manifest self-heals on render). The LAC-state engine
hot-reloads that file and resolves the `dlac:` virtual markers from it.

gearui builds **one deps table** and hands it to BOTH `trigui.init` and `autoui.init`
— helmui/fishui take the whole table per call from this module's detail views, so
every downstream contract kept its pre-extraction shape. The rescan seams live here:
`M.rescanAutogear` (manifest regen + gearcheck chat warn, called by gearui's
auto-sync hook at login/job-change/inventory cadence), `M.manifestStale` /
`M.currentFmt` (craftwatch, helmwatch and fishwatch force a regen before the engine
reads stale ladders). `M.renderTab` is the tab entry point (guard ladder + login
gate). No forwarders were left on triggersui — smoke_ui S140–S151 pin both the new
home and the absence of the old one.

#### The Status column: sentence or switch (2026-07-28)
The list view's Status column prints a coverage sentence for every row EXCEPT the four
idle hobbies (`craft` / `helm` / `fish` / `choco` — exactly `idleexcl.MEMBERS`), which
draw the shared **on/off pill** (`craftbar.onOffSwitch`) instead. Those four are the only
rows describing something you ARM; the rest are slot rules waiting for their `dlac:` entry
or switches that live elsewhere. Coverage is not lost: the row NAME keeps the `levelColor`
ramp and the sentence rides the pill's hover.

The pill drives **`idleexcl.setOn(key, on)`**, which routes through each watcher's own
`setEnabled` / `setAutoHelm` — so `guardActivate` still refuses a second hobby from inside
the watcher (lock-while-active, ADR 0017), and this surface holds no lock logic of its own;
it just reports the state it did not reach. `listRows()` is UNCHANGED (`txt` still carries
the sentence) — the switch is a rendering decision in `autoRow`, not a data one.

One layout rule worth keeping: a pill row's `Selectable` click target ends at **570** while
the switch starts at 580. A full-width Selectable underneath a widget swallows its press
unless the row calls `SetItemAllowOverlap` (which `profilesmenu` feature-detects because not
every binding has it); non-overlapping hit boxes need no API at all. smoke_ui `HP0`–`HP16`.

#### Naming: display labels vs internal names (2026-07-28)
A GM read `Auto <activity>` ("Auto Fish Set", "Auto HELM Set") as *the addon performs the
activity*. Nothing in this family does: every row picks EQUIPMENT and nothing else. The
rename therefore names the GEAR, not the act — "Fishing Gear", "Gathering Gear",
"Crafting Gear", "Elemental Staff", "Ammo" — under a tab called **Gear Helpers**, with a
standing one-liner above the list ("dlac equips gear. It never acts for you").

The rename is **display-only**, and that split is load-bearing:

| Layer | Renamed? | Why |
| --- | --- | --- |
| imgui labels, tooltips, chat text, docs | YES | pure display |
| `dlac:AutoStaff` / `AutoIridescence` / `AutoOneiros` / `AutoHelm` / `AutoFish` / `AutoChoco` / `AutoAmmo` slot markers | **NO** | written into users' set files; renaming breaks every set on disk |
| row `key`s (`iridescence`, `helm`, `fish`, …) | **NO** | `openDetail`/`DETAIL_KEYS`/`AUTO_SECTIONS`/quick menu all index by key |
| Arbiter claimant names (`AutoAmmo`, `Craft`, `HELM`, …) | **identity NO, label YES** | persisted in `arbstate` order and keys `CLAIMANTS`/`CLAIM_COL`/`SOURCE`/`HINT` — but nothing shows it to a player, see below |
| module + file names (`automationsui.lua`, `openAutomation`, `buildAutoRows`) | **NO** | internal; churn without user benefit |

**Claimant display labels** (`arbiter.ARB_DISPLAY` / `arbiter.claimantLabel`, added
2026-07-28 on Henrik's *"I don't mind its name being that internally, but not in the
GUI"*). A claimant's name is its **identity**: renaming a rank row would silently reorder
every character's saved `arbstate` ladder. So identities never move — instead every
surface that names a claimant **to a human** passes it through `claimantLabel` first:

- `priorityui` — the Claim Priority row (via its own pure `M.label` seam)
- `arbmonui` — the legend chips and the per-slot contest hover
- `arbiter.arbWhyLines` — every `/dl why` claimant line (winner, "over …", "held off")
- `dispatch` — `/dl prio`, the `/dl why` retrace line, and the naked/lock "rank ABOVE"
  notices

One map, so the GUI and the chat cannot drift apart. Identity in, label out; an unmapped
name is its own label, so a new claimant needs an entry only when its internal name is not
what a player should read. Today the map holds exactly one: `AutoAmmo` → **"Ammo rule"**
— *rule*, not bare *Ammo*, because a claimant is printed next to a slot (`Ammo: <claimant>
(rank 5) over MaxMP`) and "Ammo: Ammo" is not a sentence (test `AR12` caught it). Guards:
`ARL1`–`ARL5` + `AR12f/g` (identity intact, and no `/dl why` line prints it), `S195b`–`S195e`
(the two windows share the map).

`host.selectTab` matches on the tab LABEL — `gearui.openAutomation` passes `'Gear Helpers'`
and smoke_ui S10b pins it. Change one, change both.

It is **held until it takes**, not a one-shot (2026-07-30, Henrik's field report: every
cross-link set the right panel and left the tab bar alone). ImGui applies a forced selection
at the *next* frame's tab-bar layout, so the pass carrying `ImGuiTabItemFlags_SetSelected`
still sees the tab closed — a one-shot armed it, saw nothing, and forgot, which made an
ignored flag indistinguishable from an honoured one. The request now rides every
`renderTabs` pass until that tab is observed OPEN, then clears at once so it never fights
the player's next click. `host.pendingTab()` reports what it is currently trying to reach.

**This install's imgui binding ignores the flag** (field round two: the give-up line
printed). The SDK header settles the C++ side — `BeginTabItem(label, bool* p_open,
ImGuiTabItemFlags flags)`, `SetSelected = 1 << 1` — but nothing on disk shows how Ashita's
hand-written Lua binding maps `bool*`, and no sibling addon proves it either. So the host
escalates, cheapest first: `(label, {true}, flags)` (p_open as a **table** — the shape
`imgui.Begin` demonstrably honours here), then `(label, nil, flags)` (the header's own
signature), then **the rebuild**, which needs no binding cooperation at all: a tab bar ImGui
has never seen has no selection and adopts the **first tab submitted**, so the bar's ID gets
a new generation and the wanted tab is submitted first until it opens. That is why
**`gearui` must call `host.tabBarId('##ffxilac_tabs')` and never hardcode the ID** — pinned
by smoke_ui `TAB25`. It costs one frame with the tabs reordered and the body empty. Only if
even that fails does it give up, after ~30 passes, with one chat line naming the tab.
Tests: smoke_ui `TAB1`–`TAB25`, driving four stub bindings (table-p_open / nil-p_open /
flag-blind / flag-blind-and-adopt-blind) against a stub that models ImGui's real tab-bar
semantics.

### gear/groupsmodel.lua — Trigger-Groups model core (pure)
The Ashita/imgui/file-IO-free CRUD + name/member validation the Groups tab drives (issue
#25, ADR 0009): `fromRaw` (sanitize the file's `Groups` section into the model), `names`,
`findName`/`hasGroup`, `validateName`, `add`/`rename`/`remove`, `addMember`/`removeMember`.
Group and member names compare case-insensitively (engine `M.groupMatch` parity); an empty
member list is legal. Headless-tested (TGM*). Never seeded into LAC.

### gear/groupimport.lua — the "Import Lua Table(s)" transform (pure)
The addon-state, Ashita/ImGui/file-IO-free core of the Groups section's bulk import (issue
#30, G4; ADR 0009): `parse(text)` sandbox-evaluates pasted `Name = T{...}` / `Name = {...}`
assignments (bare lines OR a whole `{ ... }` table; `T` is identity; trailing commas
tolerated) into `(groups name→members, errors[])` — flat-only, so a nested / non-string /
named-field value skips THAT key with a reported reason while the rest import. The sandbox is
the hardened `profilesets.sandboxSets` pattern (env = `T` and nothing else, `'t'`-mode load),
so malformed or hostile input yields an error, never a crash or code execution. `classify`
splits created vs collide (case-insensitive) and `apply` writes into the live `Groups` map,
overwriting a collision under its existing stored spelling. triggersui draws the paste box +
the overwrite confirmation + the summary. Headless-tested (TGI*). Never seeded into LAC.

### gear/groupscan.lua — auto-import: scan a Lua file for group tables (pure)
The auto-import sibling of `groupimport` (Item 1): `scan(fileText) -> (candidates, notes)`
text-scans a LuaAshitacast job file for top-level `[local] NAME = T?{...}` blocks and surfaces
every group-shaped table as an import candidate, so a player who already keeps spells grouped in
their file skips the copy-paste. A `%b{}` walk pulls each top-level block (never descending, so a
gear set's inner `['Idle'] = {...}` is not a hit); each body is evaluated in `groupimport`'s
sandbox (`evalTable`) and classified by its `membersOf` heuristic — a flat string array is one
candidate (a directly-defined group, or a variant/config table), a container of flat arrays
expands to one candidate per inner key (the `BlueSpells` case), and a gear set / settings block is
skipped with a note. Candidates are deduped case-insensitively and sorted; comments are stripped
first so a stray brace can't unbalance the scan. triggersui draws the `Scan → tick → Import` panel
(config-looking names pre-unticked) and reuses `groupimport`'s classify / overwrite-confirm /
apply. Headless-tested (GS*). Never seeded into LAC.

### feature/jobhelpers.lua + ui/jobhelpersui.lua — the Job helper module system (issue #137, PRD #135)
The **Job helper** (CONTEXT.md) module system: first-party modules that revive the parked
plugin-folder design (`docs/design/integration-surface.md` §10) as dlac-shipped code. A module is
a drop-in FOLDER under its job's directory — `addons\dlac\jobhelpers\<job>\<module>\` (Henrik's
layout ruling 2026-07-29: the job folder GROUPS, each module under it is its own separable folder;
never a loose file); its `<module>\init.lua` returns
a contract table `{ api, label, jobs, init?, panel, status? }`. **Identity is the MODULE folder
name**, unique addon-wide (a duplicate under a second job folder is refused loudly), not
a self-declared id — the folder is the unit of server approval (one folder = one row = one approval,
the Pup-Helper precedent).

**The author-facing spec is [reference/jobhelper-authoring-guide.md](reference/jobhelper-authoring-guide.md)**
— the contract, the consumable services, and the hard rules, written to be built from without reading
this file. Keep the two in step: a contract change (an `api` bump, a new hook, a new service row above)
lands in the guide in the same commit.

- **`feature/jobhelpers.lua`** — the loader + registry + config store + the module-activity predicate.
  `M.loadAll(opts)` is the loader CORE: injected seams (`names`, `loadModule`, `ledger`, `emit`, `deps`)
  so the good / wrong-api / throwing / malformed fixtures drive it headlessly (tests JH1–JH32). It
  validates the contract, **contains** a wrong `api` / a throwing init / a malformed folder to ONE loud
  line + one entry in the SAME load ledger `dlac.lua` stashes (`package.loaded['dlac\\loadledger']`,
  namespaced `jobhelper:<id>`), so `/dl check` counts modules and names failures with no change to
  `feature/check.lua`. `M.load(deps)` is the live glue (real `ashita.fs.get_dir` scan via
  `M._listModuleDirs`, the `profiles._listDirs` precedent; folders only — a name with a `.` is a loose
  file, skipped — and `require('dlac\\jobhelpers\\<id>\\init')` via `M._requireModule`). The **config
  store** is ONE per-character statefile `<char>\dlac\jobhelpers.lua` (`fmt`-versioned; `enabled = {[id]=bool}`
  the row pill default-ON, `order = {[JOB]={id,..}}` the per-job section order written on mutation only;
  plain write + tolerant reader, the ammowatch precedent, via `M._charDir`). The **module-activity
  predicate** `M.activityCore(mod, reads)` is pure: precedence `off → wrong job → zoning → dead → town →
  active`, and an unknown read (nil job, nil inTown) never manufactures a reason — the buff-cache
  discipline. `M.liveReads` wires `gData.GetPlayer()` (job + Status), `location.inTown()`, and the
  `GetIsZoning()` probe. Future features consult this predicate too.
- **`ui/jobhelpersui.lua`** — the **Job Helpers** tab. It does NOT self-register at require time; `dlac.lua`
  calls `M.maybeRegister(host)` AFTER `jobhelpers.load` and it registers nothing when zero modules loaded
  (drop a folder + reload → tab appears; remove it → tab gone). Because the register call runs after gearui
  already registered its tabs, the tab lands to the RIGHT of Gear Helpers. Layout is the Gear Helpers pattern:
  display-only PER-JOB sections (`CollapsingHeader` per `jobhelpers.jobs()`) over a flat module list; one row
  per module per declared job, a multi-job module under each with one shared switch (every row re-reads live
  pill + activity). The pill is the master switch (`craftbar.onOffSwitch` → `jobhelpers.setEnabled`); the row
  status shows the live inactivity reason; rows drag-reorder (up/down buttons + a drag-selectable, the Claim
  Priority mechanism — no working `BeginPopupContextItem` in this install) persisting per job. Every call INTO
  a module's render hooks is pcall-wrapped — a throwing Panel loses its own Panel and prints once, never the
  tab or other rows (frame-level imgui stack recovery is uihost's `tabGuard`).
- **`jobhelpers/bst/init.lua`** — the **BST Helper**, first real module, and a folder with more than one file in
  it: `init.lua` is the contract + the Panel, and the behaviors live beside it. Its Panel carries the three-way
  **Fight** switch (issue #139) and the demoable **"Reward now"** button (issue #138): pick the best carried pet
  food (the eight-tier Ladder), overlay an optional Reward set from the job entry's Sets, open an Action
  sequence, and gray the button while Reward is down. Death-only resummon lands in a later PRD #135 slice.
- **Load wiring:** `dlac.lua` adds `feature\jobhelpers` + `ui\jobhelpersui` to the module-load loop, then runs
  the loader + `maybeRegister` in one guarded block after the loop (so job-helper counts/failures ride the load
  beacon too). ADR 0028 records the module-system decision.
- **Test rosters:** `feature/jobhelpers` + `feature/engagewatch` + `feature/combat` + `feature/modapi` +
  `feature/modcfg` → `FEATURE`, `ui/jobhelpersui` + `ui/panelkit` → `UI`, and the
  `JOBHELP` roster (folder-relative module paths: `bst/bst-helper/init`, `.../fight`, `.../reward`,
  `.../resummon`, `.../jugs` — there is no `config` entry since api 2: a module DECLARES its settings and
  `feature/modcfg` stores them) in
  `tests/run_tests.lua`'s GRD block; `'jobhelpers'` added to `tests/smoke_ui.lua`'s tab-name roster (smoke S10c
  absent / S320–S344 present + balanced Panel + the Fight switch and the Reward rule's two controls drawn and
  clickable).

### The BST Resummon rule (issue #141, PRD #135) — death-only, and death is proven
The third standing Job-helper behavior, and the one that spends the most expensive item the module touches.
Everything new is either the **classified pet-loss edge** (a second question on the existing vitals service —
its own row in the table above) or module-local:
- **`jobhelpers/bst/jugs.lua`** — the module's DATA, and two tables answering two different questions.
  `M.PETS` is the **jug pet roster** (this server's own published BST tables: 14 families of NQ + HQ), and it
  is the whole of the classifier's jug-vs-charm rule — a name that is not on it is a charmed mob, so the helper
  does nothing for it. `M.MAP` is the **jug → pet mapping** the picker shows; nothing acts on it. The jugs
  THEMSELVES are not copied here: a jug is exactly a **BST-only Ammo item**, so `M.list()` joins the catalog
  (`catalogindex.rawIndex`) with the mapping and sorts by level. `M.LEVEL` is the live-observed level override
  table, **empty by design** — the catalog's level is the inherited base, and a field-observed level is one row
  here that wins everywhere (the maintainer's rule for this slice: live > wiki > repo, repo SQL is
  inherited-base only). The live list is memoized once (the Panel redraws its picker every frame; the catalog
  is generated and static) but an EMPTY build is never cached — hard rule 11.
- **`jobhelpers/bst/resummon.lua`** — two PURE deciders and one act. `decideLoss(edge, state)` funnels from
  "should I care" (armed, acting, a loss at all, a **death**, **confirmed**, a **jug** pet) down to "can I do
  it" (a jug configured, one in the bags, the sequencer free, an ability ready). `queueDecide(state)` is the
  queue tick: **cancels first and absolutely** (a pet appearing any other way, zoning, an observed Leave,
  logging out, the rule being switched off, running out of the jug), then holds (inactive, busy, still on
  recast), then fire. `pickMethod` is the binary choice plus the checkbox, shared by both — and an UNMEASURED
  recast reads READY, matching the recast service's courtesy gate. The act claims the jug into **Ammo alone**
  and verifies that same slot worn: both methods read the ammo slot for the species, so the jug is the act's
  precondition, not its costume — and no optional set rides along, because every extra claimed slot is one
  more chance for a senior claimant to refuse the whole sequence. The queue deliberately has **no expiry**:
  Bestial Loyalty's recast is measured in minutes, and a queue that expired before the ability it waits for
  would be a queue that never worked.
- **`feature/recast.lua`** gains `CALL_BEAST` / `BESTIAL_LOYALTY` and `timerIdFor(sig)`. Neither carries a
  hardcoded recast slot: the Pup-Helper reference only ever named Reward's, so these resolve theirs **by name**
  through the client's own ability resource (live memory over every other source — hard rule 9), and an
  unresolvable one reads UNKNOWN → READY. A failed resolution is not latched (hard rule 11).
- **`feature/jobhelpers.lua`** gains `sectionOrder(id)` — the module's Action-sequence priority within the
  current job's section. It moved here from `bst/reward.lua` when Resummon needed the same answer: it is a fact
  about the MODULE, not about whichever of its rules is asking, so the two share one implementation.
- **`jobhelpers/bst/config.lua`** gains four rows — `resummonArmed` (default **off**, for the reason the other
  two are), `resummonJug` (no default: nothing here picks a jug for the player, and none picked is a loud
  refusal), `resummonMethod` (default `call` — the one that earns Beast Raising bonuses) and
  `resummonFallback` (default **on**, the PRD's own; it can only ever change WHICH ready ability is used,
  never whether one is).
- **Test rosters:** `bst/resummon` + `bst/jugs` → `JOBHELP`. Tests: PVL*/JUG*/BRS*/RC9–RC18 in
  `run_tests.lua`, smoke S345–S357.
- **Deferred / flagged:** every jug→pet row is **field-verify before trust** (hand-transcribed; rows that could
  not be placed honestly are ABSENT, and the picker shows those jugs with no pet name); the exact pet-falls
  wording, `LOW_HP_PCT = 25`, the two summon command target tokens, and that pet commands ride action category
  0x09 are all field-round calls. Player-facing strings ("Resummon", "Jug", "Use the other if mine is on
  cooldown") await the maintainer's sign-off. A summon sequence that ABORTS (verify timeout) is not retried —
  the death edge is spent, and the sequencer's abort is its own loud line.

### The BST Reward rule (issue #140, PRD #135) — the pet-HP threshold
The second standing Job-helper behavior, and the first that SPENDS AN ITEM. One new central service plus one
new module file; the "Reward now" button from #138 stays, and the automatic rule is deliberately just a
**second requester on the same path**:
- **`feature/petvitals.lua`** — the **pet vitals** central service (its own row in the table above). One
  question — presence / HP% / TP / name — read through `gData.GetPet()`, published to subscribers once per
  dispatch beat by `pump()`, and answered on demand by `get()`. Carries the *dead pet = no pet* law and the
  deliberate two-state `present`.
- **`jobhelpers/bst/reward.lua`** — the rule AND the act. `decide(vitals, state)` is PURE — vitals + state in,
  "request the sequence?" out — so the threshold, the lockout and every gate are headless checks (BRW*). The
  threshold fires **strictly below** (a pet exactly at 50 is not below 50); the **retry lockout**
  (`LOCKOUT_S = 30`) is armed by every ATTEMPT, so a sustained sub-threshold pet costs at most one command and
  one refusal line per window. Two holds deliberately do NOT arm it because nothing was attempted: a sequence
  already running, and Reward still on cooldown — and the recast hold is **silent**, which is exactly what the
  greyed-out button says. Below it sits `request(id)`: pick the food off the Ladder, overlay the optional
  Reward set, open ONE Action sequence. The button calls it and so does the rule, which is what makes
  "identical refusal behavior to the button" a property of the code rather than of two test suites agreeing.
  `need` is the CONSUMED slot alone (Ammo = food) — the maintainer's accepted ruling at the #138 merge: the
  food is the precondition, the Reward set dresses best-effort, and that is also what lets a player's own
  Reward-gear Trigger compose with a food-only claim.
- **`jobhelpers/bst/config.lua`** gains three rows — `rewardArmed` (the rule switch, default **off**, for the
  reason Fight is: a helper that issues commands and eats a player's food never arms itself), `rewardThreshold`
  (default **50**, the slider's resting position, not an arming decision) and `rewardSet` (persisted since the
  rule has no Panel open to read a session-only choice from).
- **`feature/petfood.lua`** now reads the **override/sync-aware** level (`/dl set level main`, then
  `MainJobSync`), not raw `MainJobLevel` — the house law every picker follows, paid for by AutoAmmo v134. A raw
  read under level sync picks a tier over the cap, the equip is refused, and the sequence ends in a contained
  verify timeout instead of correctly falling a rung.
- **`jobhelpers/bst/fight.lua`**'s pet gate now asks `petvitals`, dropping the raw
  `GetPetTargetIndex`/`GetHPPercent` pair it carried — the same "one live shared implementation" move
  `engagewatch` made for the edge decode.
- **Test rosters:** `petvitals` → `FEATURE`; `bst/reward` → `JOBHELP`. Tests: PV*/BRW*/PF7–PF12 in
  `run_tests.lua`, smoke S340–S344.
- **Deferred / flagged:** the rule's player-facing strings ("Reward my pet when it drops low", "below N% pet
  HP") await the maintainer's sign-off; `LOCKOUT_S = 30` and the arm-by-default question (shipped OFF) are
  field-round calls. Pet TP is published but nothing consumes it yet — the scale (`GetPetTP` raw) is unverified
  against the live server.

### The BST Fight switch (issue #139, PRD #135) — the first standing Job-helper behavior
The first behavior a Job helper performs on its OWN signal rather than a button. Two new files beside the
central service, all pure-core-plus-thin-glue:
- **`feature/engagewatch.lua`** — the **engage/target edge** central service (its own row in the table above).
  One `0x01A` decoder for both edges, the packet's own entity, a 5-second per-target debounce, subscribers.
  Network thread decodes and stashes; `pump()` (dlac.lua's `d3d_present`) debounces, names and notifies.
- **`jobhelpers/bst/fight.lua`** — the switch itself. `decide(edge, state)` is PURE — edge + state in, command
  decision out — so every rule is a headless check (BFT*): `off` never acts; `attack` hears ENGAGE edges only
  (a mid-fight target change does nothing); `follow` hears both. `active` and `hasPet` must be POSITIVELY true
  (an unreadable world or pet read is not permission to command a pet — the one deliberate departure from the
  buff-cache "unknown never flips behavior" rule, because here the unknown-reads-as-yes branch is the one that
  ACTS), while `targetOk` blocks only on a positive contradiction. Heel needs no code: nothing polls, nothing
  repeats, so a pulled-back pet stays back until the next real edge. Jug and charmed pets are identical
  because the decision has no pet-identity input at all. The command goes through `lib/cmdqueue`, once,
  fire-and-forget. Chat stays SILENT (a line per pull is noise); the Panel reports the last decision instead.
- **`jobhelpers/bst/config.lua`** — the module's OWN per-character settings file,
  `<char>\dlac\jobhelper-bst.lua` (`fmt`-versioned, declared keys only, written on mutation only). Deliberately
  NOT the shared `jobhelpers.lua`, which holds the FRAMEWORK's state (pill, section order, rank anchor): one
  config file per module is part of what makes a module separable — Fight defaults **off**, because a helper
  that issues commands never arms itself.

### The Action sequence machinery (issue #138, PRD #135) — the "Reward now" slice
The CONTEXT.md **Action sequence** made demoable. Four pure cores with injected seams (headless-tested)
plus thin live glue:
- **`feature/actionseq.lua`** — the singleton sequencer state machine. `request(req)` opens a sequence
  (`req = { module, label, order, claim = {SlotKey=item}, need, command, timeout }`); `tick(now, io)` drives
  the lifecycle `claiming → firing → released` / `refused` / `aborted` against an injected io
  (`worn / blocker / fire / release / emit`). Success is SILENT; a definitive blocker on a needed slot refuses
  loudly (never-fire-bare); the gear never landing inside the timeout aborts; the command fires exactly once
  (`_fired` latch). `arbitrateRequests(reqs)` resolves simultaneous contenders by module order. `claim()` /
  `active()` / `statusText()` are the CLAIMANTS-row seams. Live glue: `pump()` (wired in `dlac.lua`'s
  `d3d_present`) reads worn via `dispatch.wornName`, blockers via `dispatch.disabledOn`/`isLockedSlot`, fires
  via the chat command bus, and releases via `dispatch.kickDefault` (the next arbitration restores gear).
- **`feature/recast.lua`** — the ability recast READINESS service (Central services: "is this ability off
  cooldown?"). `readyFor(sig, reader)` / `rewardReady()` — pure, reader injected; UNKNOWN reads READY (the
  courtesy gate). Reward = ability 103; the recast-timer-slot signature is ported from the Pup-Helper reference
  and FLAGGED for field verification.
- **`feature/petfood.lua`** — the eight-tier pet-food **Ladder** (`pick(reads)`): highest tier first, gated by
  equip level and equippable-bag stock; carrying none is a loud refusal. Tier data is carried locally (the
  catalog ships only six of the eight). Live reads via `ownedcache.counts` + the player level.
- **The `JobHelper` claimant row.** `arbiter.placeJobHelper(order, anchor)` weaves the row into the live rank
  order directly below its anchor (default `Locks`) — deliberately NOT in `ARB_ORDER_DEFAULT`, because its
  Claim Priority position is remembered **per job** (`jobhelpers.rankAnchorFor` / `setRankAnchor` /
  `placedOrder` / `moveRankRow`; anchor stored in the `rank = {[JOB]=row}` block of the jobhelpers config).
  `dispatch.jobHelperPlace` runs it every Default (and for `/dl prio`); the row hides with zero modules. A
  CLAIMANTS row (`active`/`claim`/`apply` reading `actionseq`) rides the standing rank walk, so a senior holder
  wins its slot and the sequencer refuses. `arbiter.claimantLabel` renders the identity as **"Job helper"**.
- **Test rosters:** `actionseq`, `petfood`, `recast` → `FEATURE`. Tests: RC*/PF*/AS*/JHR*/JHW* in
  `run_tests.lua`; the CR* registry pins updated for the new row (JobHelper is the one per-job "extra").
- **Deferred / flagged:** live blocker attribution names locks + free-equip today; naming a senior *claimant*
  from the Arbiter trace is a follow-on. The Reward command target token and the recast-timer slot need field
  confirmation. Player-facing strings ("BST Helper", "Reward now") await the maintainer's sign-off.

### gear/actionpicker.lua — searchable spell/ability browse-list core (pure)
The Ashita/imgui/file-IO-free core behind the Groups tab's member browse-list (issue #26,
G3; ADR 0009). `buildList(job, spells, abilities)` returns the job's LEARNABLE spells +
abilities as ONE combined, case-insensitively sorted list of `{ name, kind, level }` (kind =
`'spell'`/`'ability'`), deliberately **ungated** — the level is display only (build-ahead,
HARD RULE 6). The picker-DB tables (`data/spells`, `data/abilities`) are **injected** (the
setimport resolver precedent), keeping it pure/testable. `parseQuery` + `matches` are the
comma-separated, ALL-terms-substring search predicate (the item-search shape, minus stat
aliases). triggersui caches the list per job and draws the multi-mark popup; the two helpers
are the whole browse capability, coupling-free so an ordinary `name` trigger condition can
adopt the same picker later (issue #12). Headless-tested (ACP*). Never seeded into LAC.

### gear/blueprintsmodel.lua — Blueprints library + stamp transform (pure)
The Ashita/imgui/file-IO-free core of **Blueprints** (issue #65, slice 1; PRD #64; CONTEXT.md
term, ADR 0009 the structural precedent). A Blueprint is a job-independent saved Trigger kept
in ONE per-character library file OUTSIDE Profiles (`<char>\dlac\blueprints.lua`) — addon-state
only, the engine never reads it (no VERSION involvement). An entry is `{ name, handler, rule }`
where `rule` is the ordinary trigger edit-model rule VERBATIM (`when`/`whenAny`, a `set`
string/list OR inline `equip` payload, optional priority) — so a stamped rule is an ordinary
Trigger forever. Exports: `fromRaw`/`parse`/`serialize` (the library file, sandboxed load +
deterministic emit — a `blueprints v1` table), `defaultName` (a readable condition summary,
e.g. "Sleep or Lullaby"), `add`/`rename`/`remove` (CRUD), `makeEntry`, and the two transforms
the headless suite pins (TGB*): **`stamp(entry, jobData)`** → a NEW data table with the rule
appended to the entry's Handler (non-mutating, deep-copied → detached both ways) and
**`identicalExists`** (the warn-but-allow double-stamp check). `emitRule` is a self-contained
mirror of `dispatch.serializeTriggers`' per-rule form (issue #65 forbids any engine change), so
the file, the identical-rule canonical form, and (slice 2) the shareable text render a rule ONE
way. triggersui owns the file IO (the safewrite ladder) + the section render. Never seeded into LAC.

### gear/rulecopy.lua — "copy this rule to…" (pure)
The core behind the per-rule copy (2026-08-02): one Trigger landed in the **job entries** you
tick. Deliberately NOT a second Blueprint, and it exists because of what a Blueprint
structurally cannot do — a Blueprint stamps onto the ONE job you are standing in, so reaching
five jobs costs five job changes. It travels **as a Blueprint entry** on purpose — capture,
detach, identical-rule detection and the stamp transform are `blueprintsmodel`'s and already
pinned (TGB\*), and reusing them is what guarantees a copied rule is byte-identical to a
stamped one.

**One classifier, both axes**, because a trigger file is addressed by (profile, job) and the
question is the same whichever one a copy varies: `rows(entry, targets, order)` classifies each
destination as `source` (where the rule already lives — never a target) / `create` (no trigger
file there yet) / `dup` (an identical rule already there — warn-but-allow, the double-stamp
law) / `add` / `unreadable` (a torn file — refused), in `order`'s ranking (jobs read in the
game's order, not alphabetically) with anything unranked after, by name. `allNames` is what the
**All** button ticks — writable and NOT already holding the rule. `selection` counts the
ticked-and-writable rows plus the duplicates among them. `setNames` is what "include the set"
has to carry (an inline-`equip` rule names none, so the tick is a no-op rather than an error).
`applyTo` is the stamp. `receipt`
**names every outcome** — including sets brought along and, crucially, sets that could NOT be
(a rule reported as copied while the set it points at stayed behind is the exact dud the tick
exists to prevent) — and leads with the coordinate that was varied, so an all-failed copy still
says which list it came from. A copy that silently skipped a job reads as one that
worked everywhere, and the player would not find out until they changed job. Pure: no ImGui, no
Ashita, no file IO, no clock — the caller reads the target files and writes the results
(tests RC\*). Never seeded into LAC.

### gear/gearoracle.lua — THE Gear Oracle: one door for gear questions (issues #70/#71/#74, PRD #69)
The single addon-state answer for every gear question. A **facade, not an absorb**: it
fronts the proven interpreters (which keep their homes, tests and field-tuned behaviour),
so no module re-states a rule and drifts. **Claim-BLIND, permanently** — every answer is
a capability ("*could* this character use this item"), never permission ("*may* this slot
change now"); the Arbiter stays the sole precedence authority; method names use could-words
(`canWear`), never may-words (`canEquip`).

- **FETCH (issue #70).** **`wornItem(slot)`** — the equipped-item resolution (packed
  `GetEquippedItem` Index → container/slot → the container item), returning
  `{ id, rec, extra, item }` (id RAW so each caller keeps its own guard) or nil; and
  **`equipBags()`** — the ONE equip-eligible bag list (Inventory + the 8 Wardrobes). The
  three hand-rolled worn decodes (gearui `getEquippedId`, augments `slotExtra`, useitem
  `readiness`) and the bag-list literals all route here.
- **ELIGIBILITY (issue #71).** **`canWear(rec, job, level)`** — main-job/level equip gate;
  DELEGATES to the engine module's addon-visible rule (`dispatch.canWear`). The two inline
  fallbacks (gearoptim, gearui) are DELETED — their re-statements of "no job list means
  wearable" were the exact deduction drift this ends. **`anyJobCanWear(rec, jobLevels)`** —
  the lockstyle any-job-at-current-level gate; DELEGATES to the addon-state gate module
  (`gear/jobgate.canEquip`), which keeps its FAIL-OPEN semantics (the nil-levels fail-open
  belongs to the caller). lockstyle's gate calls migrated here.
- **IDENTITY (issue #71).** **`lookup(idOrName)`** — "what is this item": the owned-record +
  catalog-record join (owned first, then the full catalog; id authoritative, name the
  case-insensitive fallback). ONE recipe; the enriched flattened indexes are injected by the
  surface that builds them (gearui, via `setLookupSource`) — the oracle can't flatten raw
  gear.lua itself because a Phase-2 owned record carries no stats until enrichment. gearui's
  `lookupById`/`lookupByName` are now thin adapters over this door.
- **EFFECTIVE STATS (issue #74, the Phase-2 stat-glue migration).** **`stats(rec, ctx)`** —
  effective item stats: the level-scaled resolver (`levelstats.effective` at `ctx.level`)
  PLUS the private-augment fold (`ctx.augStats`, folded per Id, copy-on-write). ONE recipe,
  replacing the hand-glue the manifest builders carried. **`setStats(comp, ctx)`** — the
  full composition evaluation INCLUDING set bonuses, a THIN delegation to the reference
  set-bonus evaluator (`geareffects.comboStats`, untouched). Plus the interpreter
  passthroughs the Sets core + worn panel now read through the door instead of requiring the
  interpreters: `setsOf`/`setInfo`/`setTier` (membership + tier ladders), `scales`/
  `levelThresholds` (level-scaling introspection), and the augment reads (`augStats`/
  `augLabels`/`wornAugStats`/`wornAugExtra`/`describeAugments`/`dumpAugments`). The migrated
  callers — automationsui's MaxMP/HELM/fishing/craft manifest ladders, gearui's Sets-core
  totals/hover/scoring, equippedui's worn-augment display — are proven byte-identical by the
  golden harness (#72, smoke_ui §12). This **emptied the GRD5 stat-glue allowlist**
  (`tests/run_tests.lua`): no feature/UI module requires `levelstats`/`geareffects`/`augments`
  any more, and the source guard is now absolute.

Addon-state only, **never seeded** — ADR 0002 keeps the engine's own byte-identical TWINS
in dispatch.lua (`decodeEquipIndex` / `AMMO_BAGS`), and the OR-section parity pins in
`tests/run_tests.lua` feed both a fixture matrix and NAME the twin on any drift; OR14-29
pin canWear against `dispatch.canWear`, anyJobCanWear against `jobgate.canEquip`, the lookup
join, and the claim-blind boundary (no `canEquip` door). The exporter's duplicate catalog
walk is retired too — it now routes its id-index through `catalogindex.rawIndex()`, leaving
exactly one catalog nested walk in the codebase.

### gear/profilesets.lua — profile `sets` reader
Reads the loaded profile's `sets` table for the Sets tab. In LAC state reads
`gProfile.Sets`; in addon state parses the current `<JOB>.lua` in a permissive sandbox.

**The sandbox is an IMPORTER, so it assumes nothing about the file** (all three learned
from one tester's SCH.lua, 2026-07-28, whose every symptom was the same sentence — *"no
owned/known gear"*): module names are **aliased** from dlac's former addon name onto its
current one, so a file that requires the old library resolves against *this* character's
inventory instead of a stub; the inventory itself goes in through `legacyGear`, whose
**MISSING sentinel** answers any key at any depth (`gear.Ammo.Throwing.X` on a flat-Ammo
inventory is a skipped entry, not a dead chunk, and never a `nil` hole that truncates the
`ipairs` walk of a candidate list); and a file that is present but unreadable is reported
by name through `legacyDiag()` — the Copy-from popup prints it in red. Consumers spot a
sentinel by `.__dlacMissing`, which the require STUB answers identically by construction,
so one check covers both a missing piece and a missing library. Cache hits content-follow
the Dynamic source file (1s byte compare) — a Profiles-menu import rewrites the active
profile's files without moving the cache key. The same follow idiom lives in triggersui's
edit model (dirty models get a drift banner instead of a silent clobber) and lockstyle's
boxes (2026-07-22; tests TGW/PSW/LGW).

**Three tiers, and which one is LIVE matters.** Dynamic sets come from the active
profile's `sets\<JOB>.lua`, else (unmigrated) from the job file's own block. Statics come
from the job file AND both pre-profiles backup homes — the native one and, for a
character migrated before the storage move, `luashitacast\<char>\backups\pre-profiles\`
(`profiles.legacyBackupPath`). Those same legacy files' `sets.Dynamic` blocks are
harvested separately as **old FFXI-LAC sets** (`lacSetNames` / `getLacSets`, 2026-07-28):
import sources for the Sets tab's Copy-from, deliberately absent from `getSetsRoot` and
`liveSetNames` — the engine never loads them, so one must never look live or become a
trigger target. A block already ADOPTED as the live Dynamic list is not offered a second
time (tests PSL1–PSL11).

### gear/setmanager.lua — `<JOB>.lua` reader/writer
Splices dynamic sets into `<JOB>.lua` and analyzes the dispatch handler shims —
the write side of Sets-tab Commit, and `analyzeShims` powers `jobSetupState`'s
shim-health check. Pure-text core (`analyzeShims`, `repairShimsText` — comment-aware
since 84de48a) with file wrappers (`repairShims`, `commitSet`, `deleteSet`). Since the
clean-shim SETUP STANDARD (2026-07-17) nothing in the product calls `repairShims` —
the repair pair stays as the tested text engine behind any future manual wiring. All
edits are backup + parse-checked, abort untouched on failure. Writes rotated backups
in `<char>\backups\`.

### gear/setimport.lua — THE import transform (pure)
The addon-state, Ashita-free core of the Sets tab's "Copy from" (issue #15, ADR
0008). `importStaticSet(staticSet, slotLabels, resolve)` walks the source set in slot
order and returns `{ working = slotLabel→ordered candidate list, notBestFirst = slots
whose order is not highest-item-Level first, slotCount, missing, missingCount }`. The
resolver (name→owned record) is **injected** — gearui passes its `resolveSetItem`, the
headless suite a stub over owned records — so the transform is pure and testable (tests
AO0–AO48). Candidate order is carried verbatim; gearui does the full-replace into the
selected set, the overwrite confirmation, and the per-slot divergence warning. Never
seeded into LAC.

**All FOUR source kinds run this one walk** (2026-07-31): dynamic, static, FFXI-LAC and
Ashitacast, via gearui's `importVia`. The dynamic path used to hand-roll the same slot
loop — two implementations that had to agree, which is precisely the shape that produced
the vanished-mark bug the same day.

**MISSING GEAR IS NEVER A REFUSAL** (Henrik 2026-07-31: *"if the gear wasn't found, just
ignore it, inform (temporarily) and move on instead of not importing it at all"*).
Skipping an unresolvable candidate was always the per-candidate behaviour, but it was
**silent**, and a set where *nothing* resolved was refused outright — `doCopyFrom` left
the target "unchanged", `copyAsNewSets` skipped the set. Importing someone else's job
file then reported *"Created 0 new sets"* and read as a broken importer, when the honest
answer was "you don't own this gear yet". Now: the import always lands (an empty set is
a legitimate placeholder — see `commitCurrentSet`), and the drops are counted and named.
`missing` is the distinct item names in first-seen order, `missingCount` every dropped
candidate including the unnameable ones (a MISSING sentinel answers every key with
itself, so `elem.Name` on one is a *table* — `elemName` reads TYPED for that reason).
`missingNote(missing, count, cap)` renders the one capped player-facing clause.
Reporting shape differs by path on purpose: a single copy names what *that* set lost;
the migrate-many pools the whole batch into ONE deduped line, because 23 sets would
otherwise print 23 lines of chat.

`mergeLegacySources(staticNames, lacNames, acNames)` (2026-07-28; third arg 2026-07-31)
builds the picker's legacy column: one name-sorted, case-insensitively deduped list of
both kinds an old FFXI-LAC job file holds, where a name in both is kept as the
**dynamic** one (Henrik's ruling). The same transform serves the old dynamics
themselves — minus the not-best-first warning, which is a LuaAshitacast-static fact:
those lists were always read by dlac's highest-item-Level rule, so importing one
changes nothing. `acNames` (Ashitacast) is a THIRD kind with its **own name space** —
it comes from a different engine's file, so a shared name is a different set and
deduping it away would lose one (tests AQ0–AQ20).

### gear/acimport.lua — the Ashitacast (LegacyAC) XML → sets transform (pure)
The third "Copy from" source (2026-07-31). **Ashitacast** is the legacy XML gear-swap
format; on Ashita v4 it is served by the **LegacyAC plugin** (`plugins\LegacyAC.dll`),
one swap file per character AND job, named `<Char>_<JOB>.xml`. Schema authority ships
with the install: `Ashita\docs\LegacyAC\XML Structure.xml` + `readme.txt`.

**Where it lives is a SEARCH, not a path** (`profiles.legacyacRoots` / `legacyacPaths`,
first file that reads wins): `config\legacyac\` (the readme's home), then
`config\addons\legacyac\`, then `config\plugins\legacyac\`. All three conventions are
live on this install, and the first field test went straight into the second one —
a player dropping a file in by hand reasonably guesses the *addons* convention,
because that is where `luashitacast\` and `dlac\` live. Guessing wrong read as "dlac
cannot see Ashitacast files", so the picker also **names the file it read**
(`profilesets.acSource`) rather than leaving the folder a guess.

`parse(xmlText)` → `sets` (name → `slotLabel` → item-name string), `info` (name →
`{ base, slots, augments, locks }`), `notes`. Only `<sets>` is in scope — every rule
section (`premagic`, `midmagic`, `idlegear`, `inputcommands`, `init`, `variables`) is
read past. Output is deliberately the shape `importStaticSet` already eats, and
gearui's `resolveSetItem` already resolves a bare NAME string against owned gear
case-insensitively, so **nothing downstream changed to accept these**. The rules that
matter, each one a real-file fact (tests AC0–AC57):

* **Both slot dialects, at once** — `lear`/`rear` + `lring`/`rring` AND
  `ear1`/`ear2` + `ring1`/`ring2`; one real file uses both.
* **`none` is a keyword, not an item** (`<range>none</range>` unequips), and an empty
  element says the same. Tracked as an explicit CLEAR, not an absent key — with a
  `baseset`, "not mentioned" inherits and "explicitly empty" must not.
* **`baseset` is a second pass** — a base may be declared later in the file, chains are
  legal, names are case-insensitive (`baseset="idle"` → `Idle`), whitespace around `=`
  is legal, and a loop or a missing base still imports the set's own slots plus a note.
* **Comments are stripped first** — these files are densely commented and the comments
  contain tag-shaped text (whole `<set>` blocks commented out).
* **Mis-nesting is tolerated** — the spec sample SHIPPED with the plugin contains
  `<statusupdate>true</statuspdate>`; a strict parser would reject files LegacyAC loads.
* **`<setvar>` is not a `<set>`** — a plain find for `'<set'` also hits it and `<sets>`.
* **`augment=` and `lock=` cannot come across.** The augment string is LegacyAC's own
  fingerprint (`/la print augs`), not decodable against dlac's augment table; a dlac
  lock is an Arbiter claim, not part of a set. Both are dropped and `dropNote` turns
  the counts into the sentence the copy prints (hard rule 12) — a set that exists only
  to pin an augment would otherwise arrive looking like a pointless one-piece set.

Known limitation: an XML that spells items by their **log name** ("Cleric's Pantaloons
+1") rather than the game's short name ("Clr. Pantaln. +1") will not resolve —
`resolveSetItem` indexes owned gear by `Name` only. Short-form is what the format and
the game's own equip matching use; widen the shared resolver only if the field says so.

### gear/gearoptim.lua — stat-weight optimizer
Two read-only tools: MP-spent→potency swap advice, and a stat-weight scorer/best-set
builder (`M.score`, `M.buildBestSet`). Purely advisory — never equips. Reads/writes
`<char>\dlac\gearweights.lua`.

Weight tuning is PER SET only and has TWO modes per set since 2026-07-17: **points**
(the classic per-stat `perUnit`/`cap` table) and **priority** (an ordered stat list,
top matters most, optional caps — the "simple" mode). Priority scoring derives a
points table with dominance weights (bottom-up: `perUnit = 1 + max total everything
below could score`, uncapped stats assumed ≤500 across a set) so the whole existing
pipeline — `score`, `optimizePicks`, `pairLadders`, Auto-build — runs unchanged
behind `activeWeights()`. `getWeights()` returns the EFFECTIVE table; the points
editor reads `getPointWeights()`. The mode flips to whichever editor's data you
mutate; looking never switches it. Priority lists have their own per-set store and
their own named store (`prioPerSet`/`prioNamed`/`modePerSet` sections in
gearweights.lua) — a point template and a priority list never cross-load. New
bindings start BLANK (weights, priority list) with the fixed default build-slot
mask (weapons unmarked). The old SHARED (no-set) table is a **dead concept**
(Henrik 07-17): unbound, the actives alias read-only empty sentinels — every reader
sees "no weights", every mutator refuses with 'no set selected' — and older files'
`shared`/`slotsShared`/`prioShared`/`mode` sections (plus pre-per-set flat files,
which were only a shared table) are dropped on load.

**Reserved slots are part of the score (2026-07-31).** A piece that takes another slot
away — Royal/Vermillion Cloak eats Head, a boomerang eats Ammo, a suit eats
Hands+Legs+Feet — is worth that slot too, so `optimizePicks` takes `opts.reserves(ref)
-> RSlot mask` (injected like `conflict`/`effects`; the bit vocabulary stays
`arbiter.RSLOT_ORDER`, never copied). A reserved label contributes nothing and comes back
`nil` in `picks`, named in `res.reserved`. The climb can *enter* a reservation on its own
but never *leave* one, so the solve is run once per reservation **regime** and the best
total kept — the ADR 0011 seeded-restart shape, one level up. Downstream: `levelLadder`'s
`opts.emptyFrom` cuts a reserved slot's dynamic ladder at the reserver's level and appends
nothing, and gearui's `workingComposition` drops what `arbiter.reservedDrops` will drop, so
Set totals and the grid's red RESERVED box agree. `buildMaxStatSet` stays reservation-blind
on purpose (a per-slot question, same reasoning that leaves it set-blind).

### gear/gearmove.lua — storage move engine (EXPERIMENTAL, feature/storage-move only)
"[mv]" button + popup to move items between containers via the 0x029 packet, gated to
Mog House / Provenance via the 0x00A LoginState gate (see
docs/design/storage-move.md — the memory MH flag is field-falsified on CatsEyeXI).
Addon-state only; never seeded into LAC. Single-in-flight state machine with pre-send
re-verify and 2s timeout (server rejects silently).

### gear/gearcheck.lua — trigger-gear availability audit
Warns when a trigger-referenced set uses gear that isn't in an equippable bag ("set
Tp_Default uses Kraken Club in Main — it is in Mog Safe"). Fires on job change, after
moves, `/dl gearcheck`, and renders a Triggers-tab warnings section. Deliberately
self-contained so it can be cherry-picked to main independently of gearmove.

The chat half speaks **once per main job** (2026-08-01) and only while the
`gearwarn` Setting is on ("Warn about gear in storage" / `/dl gearwarn`). It rides the
auto-sync cadence, which also fires ~5s after every inventory settle, and the older
signature dedup could not hold that back — moving a piece moves the availability counts
the signature is built from, so the same advice came back all session. A sub job change
is deliberately not a re-arm (the audit is main-job scoped); `/dl gearcheck` (force)
always answers and stamps the job so a manual check isn't echoed by the next auto-sync;
`gearcheck.rearm()` re-opens the gate (what `/dl gearwarn on` and the Settings tick
call). `M.audit()` returns `(warnings, ran)` — a `ran = false` audit (no deps, no trigger
model, no bag read: login, character select, mid-zone) never spends the gate, because a
gate spent on login's empty answer would silence the real one for the whole job.

### feature/augments.lua — CatsEyeXI augment decoder
Decodes private augments from an item's `Extra` bytes (`id = word & 0x7FF; magnitude =
(word>>11)+1`) into stat deltas and readable labels. `AUG_STATS` (summable) vs `AUG_NAME`
(display); non-linear ids are deliberately display-only. Authority for id meanings:
CatsEyeXI's own `enum_augment_name` (private server repo — never commit it) > LSB
`augments.sql` > wiki. Six ids (136, 163, 205, 214, 219, 256) are undefined no-op gaps —
do not chase them. Writes `<char>\dlac\augdump.txt`.

### feature/sendlog.lua — `/dl sends`: what dlac put on the wire
The **send counter**, born from a field question (Henrik, 2026-08-01, mid-Incursion:
"does it send constant packets to have things equipped or only once?"). Counts dlac's own
outgoing packets — total, per packet id, **per cause** — plus a 24-deep ring of the most
recent sends with their ages. `/dl sends` prints it and drops one transferable
`debug\dlac-sends-<Char>.txt` (via `feature/debug.lua`'s `deliver`); `/dl sends reset`
restarts the clock.

**Own sends vs pass-throughs** (`2026.08.02a`). A re-injected `0x01A`/`0x037` is the
*player's* packet: blocked so the gear could land ahead of it, then returned byte-identical
— one in, one out. It is dlac's `AddOutgoingPacket` call, so the invariant counts it, but it
is not traffic dlac **added**, and one lumped total billed dlac for how much the player
acted. `note(id, why, pass)` carries the fact in the **data**, not in the wording of `why`
(the [[gm-naming-constraint]] shape: identity in the data, label at the render seam);
`M._own(st)` is the difference. The headline reads `N from dlac (r/min) + M of your own
actions passed through = T`, **and the rate is quoted on dlac's own count only** — a busy
caster must not read as a chatty addon. `own == 0` prints the same "dlac itself sent
NOTHING" verdict the zero case gives, which is the shape a real session actually takes.

This is a **self-check, not a probe** (Henrik's 07-23 ruling — the same one that put
`/dl check` in dlac and left packet forensics in dlacprobe). Nothing here reads the wire.
A dlacprobe `packet_out` observer would see anonymous injected bytes and could not tell
ours from another addon's, let alone name the dispatch point behind them — **only the send
site knows why it sent, and the why is the diagnostic value**. A steady state reads
`NOTHING sent`; a re-dress reads as one burst named for its dispatch point; a **flap**
reads as the same cause repeating at the 0.4 s Default tick.

**The invariant**: every `AddOutgoingPacket` call in the shipped tree is accompanied by a
`sendlog.note()`. Five chokepoints carry all of them — `equipengine.injectPacket`
(0x050/0x051 equips + 0x01A/0x037 re-injects, cause = the dispatch point via `_curEvent`),
`lockstyleapply.liveInject` (0x053), `craftwatch.requestGuildPoints` (0x10F),
`eboxclient.sendRaw` (0x1A4, cause = the protocol action `M._trace` already logs) and
`helmwatch.requestPoints` (0x1A4). **Test SND12 pins it as source** — a new send site added
without a note fails the suite, because an uncounted send is the one way this readout could
lie, and it lies in the direction that matters ("dlac sent nothing" when it did). A new
file that sends packets must be added to `SEND_FILES` there.

### data/statdefs.lua — stat metadata registry
Single source of truth for stat presentation/weighting: key, label, section, percent,
lowerBetter, aliases (~178 entries, 7 sections). Presentation only — **no server mod-ids**
(those stay in gitignored `tools/`). `M.canon()` resolves aliases to canonical keys
(PDT/MDT/DT/MDMG/MAB/MACC are canonical; descriptive forms are aliases).

### data/levelscaling.lua / data/levelstats.lua — level-scaling data + resolver
Generated map of item Id → additive threshold rows from the server's `item_latents`
(31 items: Rajas/Tamas/Sattva etc.), and the resolver that applies them at display/
scoring time. The dispatch engine never needs it — the game applies real latents.

### data/spells.lua / data/abilities.lua — picker databases (generated)
Per-job spell/ability acquisition-level tables from CatsEyeXI's public server SQL, for
the Triggers-tab "usable now" browse lists (milestone M4). First consumer: the Groups
tab's member browse-list via `gear/actionpicker.lua` (issue #26 — job-filtered, ungated);
the ordinary-trigger `name` picker (issue #12) is the next adopter of the same seam.
Generated by `tools/gen_pickerdb.py`. Known: ~40
levels differ from the wiki (private-submodule customizations); a wiki-sourced overlay
is planned — see docs/reference/catseyexi-jobs.md.

### PROFILE_TEMPLATE.lua — clean profile example
The minimal hand-written `<JOB>.lua`: one `require("dlac\\utils")`, a `sets.Dynamic`
scaffold, each handler ending in `utils.dispatch('<Handler>')`.

### tests/run_tests.lua — headless test harness
Pure-Lua tests needing no Ashita: stubs `package.loaded['dlac\\gear']`, `ashita`,
`gData`, and a controllable `AshitaCore.HasAbility(1554)` BEFORE loading modules, then
`dofile`s `utils.lua` / `gearimport.lua` / `setmanager.lua`. Sections: A subSlotAllowed,
B isDualWieldAvailable, C BuildDynamicSets, D-E computePrune/computeFixes,
F analyzeShims/repairShimsText.
Run from the addon root: `& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\run_tests.lua`

### tests/goldenfixtures.lua + tests/golden/ — the Phase 2 golden-output gate (issue #72)
**THE safety gate for the Gear Oracle Phase 2 stat-glue migration** (PRD #69, step 5).
`goldenfixtures.lua` builds one deterministic, synthetic, headless BLM character and
captures the EXACT output of every stat-glue manifest builder — the MaxMP battery ladder
(MP / Refresh / Convert batteries, the movement map, **and the augment fold**), the HELM
ladders + hat map, the fishing ladders, the fishcalc **rod-ranking gear reads**
(`rodsFor`/`bestOwnedRod`, `wornFishTotal`, `gearScore`), and the per-craft owned-gear
walk. The fixtures cover the interesting cases the PRD names: **level-scaling** items
valued at the character's level (Tamas Ring, catalog id 15545: MP 15 base → 29 at Lv74),
**augment-fold** copies (Hlr./Clr. Bliaut +1), and **one item across multiple ladders**
(Survey Sash → MaxMP + HELM + fishing). The captured strings are the builders' own output
verbatim — only the manifest's `written` clock stamp is normalized — committed under
`tests/golden/*.golden` (pinned `-text` in `.gitattributes` so Windows autocrlf can't
mangle them). **smoke_ui section 12 asserts the builders reproduce the goldens
BYTE-IDENTICALLY**, so when Phase 2 migrates the builders onto `oracle.stats()` the same
fixtures must produce the same goldens — a later field failure can never be misattributed
to the migration. Regenerate ONLY after an intentional builder/format change (review the
diff): `lua5.4 tests/gen_goldens.lua`.

### tools/ — maintainer scripts (gitignored, not shipped)
`refresh_all.py` = THE one-command update after a CatsEyeXI patch (runs everything
below in order); each script also runs alone, and all SQL generators share
`modmap.py` as the one modid→stat-key parser so a lone re-run and the umbrella can
never disagree. `apicrawl.py` builds catalog.lua (live API); `gen_petmods.py` builds
petmods.lua (item_mods_pet SQL — the pet channel the API never serializes);
`gen_levelscaling.py` builds levelscaling.lua + latentstats.lua;
`gen_gearsets.py` builds gearsets.lua; `gen_pickerdb.py` builds spells/abilities;
`modifier_map.lua` = modid→stat map; `api_cache/` holds the crawl cache + the
stat-naming decision log (`stats_decisions.txt` — the agreed mod→key bridge).
Gitignored so scraping details and the mod enum aren't published; only generated
data ships.

---

## Dual identity & the require redirection

Two Lua states load the same files for different jobs:

- **Inside a LAC profile.** LAC's `package.path` finds the seeded copy at
  `<char>\dlac\utils.lua`, which transitively requires `dlac\gear`, `dlac\dispatch`,
  `dlac\chatfmt` — the four files dlac.lua keeps refreshed there. `dispatch` detects
  this state via `inLac()` = `rawget(_G,'gFunc') ~= nil` — only here does it own
  mode/lock state, register its commands, and actually `EquipSet`.
- **Inside the dlac addon.** dlac.lua appends `<install>\addons\?.lua` to
  `package.path`, so the same `require("dlac\\X")` resolves to `addons/dlac/X.lua`.
  `inLac()` is false → `dispatch.dispatch()` no-ops. The addon preloads the character's
  real gear.lua and installs a `gData` shim so shared modules work standalone.

**Why the engine five stay flat at the repo root** (`utils`, `dispatch`, `chatfmt`,
`profiles`, `gear`): a single `require("dlac\\profiles")` line inside `dispatch.lua` has to
resolve in *both* states — to `addons\dlac\profiles.lua` in the addon, and to
`<char>\dlac\profiles.lua` under LAC. Same relative path, two roots. Folder-qualifying them
in the repo would therefore force the seeded copies into a matching subfolder, and
`require("dlac\\utils")` is **published API**: it is line 26 of PROFILE_TEMPLATE.lua and sits
in every hand-written user profile. Moving it breaks those profiles for a purely cosmetic
gain, in the one code path that runs on every job change. Everything the addon alone loads is
free to live in a folder; these five are not.

Cross-state coordination is **by files**: the LAC engine mirrors mode/lock state and its
`VERSION` to `<char>\dlac\modestate.lua`; the GUI reads it and shows a red "Reload LAC"
banner when the seeded engine is stale. The reload pair is always: `/addon reload dlac`
(reseeds files) **then** Reload LAC (makes LAC re-require them) — disk reseed alone is
never a hot swap.

**The boundary rule (ADR 0014, cross-referenced with ADR 0002): the Engine equips gear
(and reports on its own equipping) — nothing else.** The command bus between the two states
is unreliable BY DESIGN — `e.blocked` halts LATER addons in Ashita's command chain, and
`/addon reload` order IS chain order — so a feature whose trigger and executor sit in
different states can starve on one load order and go deaf on the other. The lockstyle pivot
(2026-07-23) settled the durable law: **never cross the bus.** An Automation lives Engine-
side because it equips gear THROUGH LAC (`gFunc.EquipSet`); lockstyle equips *nothing* (it
builds its own 0x053 and injects via the process-wide `AshitaCore`), so it is
**addon-resident** — trigger and executor in one state, reaching each other by direct call.
No lockstyle trigger crosses the wall in either direction; the bus problem stops existing
rather than being bridged. The engine-move direction
(`docs/design/lockstyle-engine-move.md`) is superseded by this ADR.

Under the **Native engine** (§ The Native engine) the same law holds trivially: there is
only ONE state, so "never cross the bus" is satisfied by construction — the Engine's
gear-equipping and lockstyle's 0x053 both live in the addon state, direct calls all the
way down. The two-state boundary above describes **legacy mode**; it graduates from law
to history when LAC does.

**The command-surface rule:** *a `/dl` command lives where its subject lives.* Equip state
in the Engine (`mode`, `why`, `plan`, `prio`, `lock`, `sets`, `profile`, `env`, `triggers`
— their LAC dependence is subject matter, not accident); everything else in the addon;
`check`/`debug` straddle the wall by design (they report on both states via the file
channel). Collapsing a command to ONE claiming state is what makes it chain-order-proof for
typed use — the deafness bugs came from BOTH states claiming `/dl`.

## Data flow

- **catalog.lua** (shipped) — crawled base-truth stats; addon-state only (browse,
  tooltips, enrichment, optimizer). `enrichGearFromCatalog` fills statless owned entries
  by Id.
- **petmods.lua** (shipped) — pet-channel gear stats (`item_mods_pet`: what the gear
  grants TO YOUR PET, e.g. Drachen Brais "Wyvern: HP+10%"). Lives BESIDE catalog Stats
  because the live API never serializes the pet channel — the repo SQL is the only
  source. Answered by THE Gear Oracle (`oracle.petStats`, a deliberately separate
  answer from `stats()` — pet values never fold into master stats); `gearfmt.petLines`
  composes the display (tooltips; row summaries spend leftover token budget).
  Priced for weights since 07-22 evening: `oracle.petScoreStats` flattens the channel
  under `Pet:`-namespaced keys (All + best named type — a pet is exactly one type),
  merged at gearui's `candidateStats` seam and listed in the weights stat menu via
  `oracle.petStatKeys` (+ statdefs' derived `Pet:` labels). Master `stats()`/`setStats()`
  stay pet-blind — the goldens pin them. No engine participation.
- **gear.lua** (per-char) — thin ownership record. Written by stage→commit and by
  auto-sync (`M.sync`, add-only). `refreshGear` re-reads it in place so the GUI updates
  without an addon reload. Ownership = ALL_CONTAINERS; availability (= can equip right
  now) = Inventory + Wardrobes; stored-only gear renders red (ADR 0005).
- **Profile sets files** (per-char) — `sets.Dynamic.<Name>` ordered candidate lists in
  `dlac\profiles\<active>\sets\<JOB>.lua` (same `sets = { Dynamic = {...} }` shape the
  job files used, so setmanager's scanners splice them unchanged), written by
  setmanager; legacy fallback: the block inside `<JOB>.lua` for unmigrated characters.
  At cast time `rebuildSets` → `BuildDynamicSets` flattens each Dynamic set to the best
  level-eligible piece per slot; the engine equips the flattened set. Set changes
  hot-swap (`/dl sets reload`, pinged by Commit); the engine also auto-installs the
  active profile's sets into every fresh `gProfile` (LAC load / job change / `/dl
  profile use`) — see profiles.lua and docs/design/profiles.md.
  **The auto-install is the engine's ONE latch, and it is load-bearing** (ADR 0007):
  it resolves per `(gProfile, profileName, job)` and then stops, because re-reading the
  sets file every 0.4 s tick would be absurd. That makes it the only reader that does not
  self-heal — every other one (triggers, craft state, pin state, mode mirror) re-reads on
  a throttle. So it must (a) refuse a not-ready job — `M.jobReady`, since `GetMainJob()`
  reads 0 at login and gData stringifies that to the *real-looking* `"NON"`; and (b) never
  latch on a question it could not answer (`setsPath(job) == nil` = "can't tell yet", not
  "no sets file"). Getting this wrong cost a silent session-long no-op: `Dynamic` stayed
  `{}` and every trigger equipped nothing. `/dl instdiag` (TEMPORARY) dumps its state.
- **Trigger files** `dlac\profiles\<active>\triggers\<JOB>.lua` (legacy fallback
  `dlac\triggers\<JOB>.lua`) — written by the Triggers tab via
  `dispatch.serializeTriggers`; hot-reloaded on content change. A broken hand-edit keeps
  the last good rules and reports.
- **Auto-sync chain** (addon state, on login/job change **and ~5s after every inventory
  settle**): `gearimport.sync` → `refreshGear` → automations manifest rescan
  (`autogear.lua`) → `gearcheck.chatWarn` (which speaks once per main job — see
  gear/gearcheck.lua).

## Trigger dispatch path (end to end)

1. Each `<JOB>.lua` handler ends with `utils.dispatch('<Handler>')`; `HandleDefault`
   first calls `utils.rebuildSets(sets)`. Setup appends these shims without removing
   player code.
2. `utils.dispatch` → `dispatch.dispatch(event)`, which bails unless `inLac()`.
3. `ensureLoaded` hot-reloads rules; `buildCtx` reads `gData.GetPlayer()/GetAction()`;
   each rule's `when` is ANDed through `MATCHERS`.
4. Hits sort by priority ascending (specificity tiers: any 10 / status·skill 20 /
   class·element 30 / contains 40 / name 50 / automation 60 / mode 100; file order on
   ties); each is applied in order so later writers win per slot (ADR 0003).
5. `equipSetByName` pulls the flattened `gProfile.Sets[name]` → `equipResolved` →
   `gFunc.EquipSet`. Locked slots (`/dl lock`) are stripped.
6. Virtual slot entries: `BuildDynamicSets` encodes `'dlac:AutoStaff|<fallback>'`;
   `equipResolved` splits marker/fallback → `resolveVirtual`: AutoStaff = best tiered-
   Iridescence staff from autogear.lua (level-gated; ties go to the universal; since
   v82 the universal comes from the manifest's `universals` ladder — preference-ordered,
   first rung usable at the live level, so a level sync falls through to a lower rung);
   AutoObi = elemental/universal obi only when the day/weather net is positive.
   Unresolvable → fallback; no fallback → drop the slot.
7. Per-slot attribution is recorded for `/dl why`.

## The `/dl` (= `/dlac`) command surface

Registered across ~20 handlers (one per feature module, plus the engine's); each blocks only
its own subcommands. A new engine subcommand must be added to the **whitelist** at the top of
`dispatch.lua`'s command handler as well as its branch, or it returns in silence and looks
like the command does not exist.

| Command | Module | Does |
|---|---|---|
| `/dl ui [on\|off\|toggle]` | gearui | GUI window |
| `/dl sync` | gearui | Import new gear now |
| `/dl autosync [on\|off]` | gearui | Toggle on-job-change sync |
| `/dl debug [on\|off]` | gearui | Reveal dev header buttons |
| `/dl view_ids [on\|off]` | gearui | Add item id + model id to every equipment tooltip |
| `/dl autobuildimport [on\|off]` | gearui | Whether importing a weights-bearing job re-solves its sets from YOUR gear (default on) or lands verbatim |
| `/dl buildstored [on\|off]` | gearui | May **Auto-build** plan around gear that is Owned but not Available — parked in the Mog Safe, a Locker, a Satchel (default on)? Off narrows its candidate pools to Inventory + the 8 Mog Wardrobes, for building in the field. Pools only: no set is rewritten, and the `+ Add` picker still offers everything you own |
| `/dl gearwarn [on\|off]` | gearui | The trigger-gear audit's automatic chat report (default on) — once per main job. Off silences it; `/dl gearcheck` and the Triggers tab still answer on demand. Turning it on re-arms the gate for the job you are standing on |
| `/dl mode <name> [on\|off\|toggle\|<value>]` | dispatch | Flip a mode (no arg: list) |
| `/dl lock <slot\|all> [on\|off\|toggle]` | dispatch | Engine-owned slot locks |
| `/dl naked [on\|off\|toggle]` / `/dl dress` | dispatch | Strip every slot and hold it empty -- an Arbiter Claim ranked first, **not** a lock (ADR 0021). Bare `/dl naked` always arms; `/dl dress` releases. Dies on a Reload LAC, survives an engine self-swap |
| `/dl disable [slot\|all]` / `/dl enable [slot\|all]` | dispatch | **Free equip** -- dlac writes nothing to those slots, no equip and no unequip, so hand-equipped gear stays put (ADR 0024). The **ceiling**: pinned above every rank row and undraggable, so triggers, pins, a locked set and even `/dl naked` all stop at it. Enforced at the one write seam, not in the rank walk. Bare `/dl disable` takes all 16; also `/dl disable off` and `/dl disable <slot> off`. Same lifetime as the strip and the locks (job change / logout / Reload LAC), never saved |
| `/dl why` | dispatch | Last-dispatch trace + per-slot **claimant** attribution (winner + rank, "stopped by Locks", "Triggers" floor) |
| `/dl prio` | dispatch | The Arbiter's live rank + per-claimant claim status (ADR 0012) |
| `/dl env` | dispatch | Day/weather + per-element obi math |
| `/dl triggers reload\|init\|path` | dispatch | Trigger-file management |
| `/dl scan` / `preview` / `stage` / `commit` | gearimport | Gear import pipeline |
| `/dl fix` | gearimport | Backfill catalog metadata (Type/OneHanded/**RSlot**) into gear.lua |
| `/dl dedupe` | gearimport | Remove duplicate gear.lua entries |
| `/dl prune [commit]` / `prune why <item>` | gearimport | Remove/explain unowned entries |
| `/dl weight ...` / `best` / `mp` / `maxmp` | gearoptim | Stat-weight tools |
| `/dl set level main\|sub <n>` | utils | Level override for previews |
| `/dl dw` | utils | Dual Wield trait-bit probe |
| `/dl recalc` / `test` / `reload` (`r`) | utils | Rebuild sets / probe / reload LAC |
| `/dl gearcheck` | gearcheck | Trigger-gear availability audit |
| `/dl sends [reset]` | sendlog | **What dlac has put on the wire this session** — dlac's **own** sends split from your **passed-through** actions, per packet id, **per cause**, plus the last 24 sends with their ages; also lands as `debug\dlac-sends-<Char>.txt`. Zero sends says so *and* says why that is expected (equips are edge-driven). A **flap** shows as one cause repeating at the 0.4 s Default tick. Self-check, not a probe — it counts dlac's own sends at the sites that make them, and never reads the wire |
| `/dl food [1\|2\|forget]` | foodwatch | Which food you are under and what you can re-eat; a number eats that row, `forget` clears the history. What counts as food is learned off the wire (an item use + the FOOD effect's expiry moving), never from a shipped list |
| `/dl engine [native on\|off \| migrate]` | feature/engine | The Native-engine flip: status / flag + storage migration (see § The Native engine) |
| `/dlmv` | gearmove | (branch-only) gate/version diagnostic |

## Per-character state vs repo

Per-character, under `<install>\config\addons\luashitacast\<Char>_<ServerId>\`
(Henrik's is `Mindie_29909`), never in git:

| File | Owner | Purpose |
|---|---|---|
| `dlac\utils.lua`, `dlac\dispatch.lua`, `dlac\chatfmt.lua`, `dlac\profiles.lua` | dlac.lua (refreshed every load) | profile-side runtime |
| `dlac\gear.lua` | seeded once, then auto-sync/commit | owned gear |
| `dlac\gear_staging.lua` | gearimport | transient import staging |
| `dlac\profile.lua` | profiles (`/dl profile use`) | active-profile pointer |
| `dlac\profiles\<Name>\sets\<JOB>.lua` | setmanager (Sets tab) | committed dynamic sets |
| `dlac\profiles\<Name>\triggers\<JOB>.lua` | triggersui/dispatch | trigger rules |
| `dlac\triggers\<JOB>.lua` | (legacy, read-only fallback) | pre-profile trigger rules |
| `dlac\autogear.lua` | automationsui | automations manifest |
| `dlac\blueprints.lua` | triggersui (Blueprints section) | per-character Blueprint library (reusable trigger rules; outside Profiles, addon-state only — the engine never reads it) |
| `dlac\ammostate.lua` | ammowatch (Gear Helpers > Ammo) | AutoAmmo config (persisted `enabled`, jobs map, the priority list) — the engine reads it per second |
| `dlac\foodhistory.lua` | foodwatch | what this character has eaten, most recent first (unique by item id, 10 deep) — the three most recent you are still carrying become the Menu's food rows |
| `dlac\modestate.lua` | dispatch | mode/lock/VERSION mirror |
| `dlac\uiflags.lua` | gearui | debug/autosync flags |
| `dlac\gearweights.lua` | gearoptim | stat weights |
| `dlac\augdump.txt` | augments | shareable augment dump |
| `<JOB>.lua` | Setup / `/dl profile migrate` (shim only) | the LAC profile — ALWAYS the clean managed shim after Setup (THE STANDARD: old logic never stays live); `.flbak` siblings are relics of the dead convert-in-place era |
| `backups\` | setmanager/gearimport | rotated backups |
| `backups\pre-profiles\` | profiles.migrate (first backup written ONCE, never overwritten; re-migrations add stamped `<JOB>-<stamp>.lua` copies) | pre-migration originals; "Copy from static" + Groups "Scan my Lua" read from here forever |

The old pre-dlac profile code lives at `<char>\ffxi-lac\` (reference only — the origin of
the "builder is a plan" pairing semantics).

## The Native engine (feature/native-engine)

dlac absorbing LuaAshitacast: the addon equips gear itself — LAC becomes
optional, then removable. **This is the end-goal, not an experiment — ADR 0015
(native-first) is the standing direction: new features target this pipeline,
legacy LAC mode is a sunset with a four-phase migration plan (recruit → merge →
nudge → delete).** Behind the **Engine flag**
(`config\addons\dlac\engine.lua`, `return { native = true }`; broken file
reads OFF). Flag off = byte-identical legacy behavior, pinned by the whole
test suite.

### The module trio

| Module | Role |
|---|---|
| `gear/equipcore.lua` | PURE equip pipeline: entry normalization (LAC `MakeItemTable` parity), the set resolver against an injectable snapshot (worn-view reserve semantics, first-fit bag scan, job/level/slot-bit/bag/augment gates, priority order, conflict unequips), 0x050/0x051 byte builders. Tests EQC*. |
| `feature/equipengine.lua` | The TIMING SERVICE (LAC packethandlers port): block outgoing 0x01A/0x037 → fire Precast → re-inject → fire Midcast; completion timers (LAC formulas + defaults); incoming 0x028 completion/interrupt + pet stream (fires `PetAction` at action START); 0x1B encumbrance; resend dedup; the coexistence TRIPWIRE. Pure half tested EQE*. `ACTION_ROUTES` is the dispatch-point table — **a future dispatch point is one new row (or one `fireEvent` call site); trigger files just carry the new handler name.** |
| `feature/nativedata.lua` | LAC-parity gData providers for the addon state (player/action/pet/environment/equipment/augment; vanatime+weather sig-scans). Installed as the gData shim by dlac.lua — the old zero-stub is now the fallback. |

`dispatch.lua` (v111) is the same engine in both worlds: `engineActive()` =
LAC state, or the native-armed addon state. One equip seam
(`engineEquipSet`) routes resolved sets to `gFunc.EquipSet` or the
equipengine buffer. `M._nativeSets` is the `gProfile.Sets` equivalent —
the tick's native identity latch installs the active profile's job sets on
job/profile change and `utils.rebuildSets` re-flattens on the shim's own
cadence. LAC-BRIDGE machinery stays `inLac()`-pinned: self-swap, seeding,
handoff/request files, the HandleEquipEvent wrap, lockstyle engine halves
(native lockstyle is the #80 addon-residency move's territory).

### Storage homes

`profiles.dataDir()` / `charRoot()` / `storageRoot()` / `charDataDirAt()`
are the ONLY path composers (statefile delegates; every module swept).
Legacy home: `config\addons\luashitacast\<char>\dlac\`. Native home:
`config\addons\dlac\<char>\` (no extra `dlac\` level; backups at
`<char>\backups\`; exports at `config\addons\dlac\dlac-exports\`, with the
legacy exports dir still READ so shared files never vanish). The flip
migrates by COPY — `profiles.engineMigrateStorage` (idempotent,
byte-verified, existing native files win) runs from `/dl engine native on`
and auto-runs per character on first login after the flip
(`engineAutoMigrate`, two file probes when settled). Legacy files never
move: flipping back finds everything where it was.

### Onboarding v2: fresh installs auto-setup; Setup is the migration wizard (ADR 0015 ruling 4, refined by issue #91)

**The ruling (2026-07-23):** Setup exists for exactly ONE reason now — migrating a
current *legacy* dlac user to native. New players get the native engine
automatically, with **zero ceremony**.

**First-run decision (unchanged from #87).** A **fresh install** — no Engine flag
file AND no legacy dlac data anywhere on the install (no
`config\addons\luashitacast\<char>\dlac\` for any character) — is **born native**:
the first boot writes the flag `native = true`, storage lives in dlac's own root,
and no LuaAshitacast tree is ever created. Existing users are **never auto-flipped**:
legacy data present, or a flag already on disk (either value), means current
behavior exactly — the flag is honored, never rewritten by boot. The decision is a
pure seam — `profiles.firstRunAction(flagState, legacyPresent)` (flag
`'native'|'legacy'|'absent'` × legacy-data present → `'respect'|'legacy'|'write-native'`);
`profiles.firstRunInit()` runs it once at boot (`dlac.lua` `maintainStorage`),
returning `nil` until it can decide (listing failure / flag-write failure) so the
caller retries rather than latching a half-answer, and writing the flag only for
the fresh case. The LAC-alive polite ask is unchanged: a native boot that detects
LuaAshitacast still alive (`dlac.lua` `lacAlive()` — the equipengine tripwire, or a
fresh legacy-home modestate stamp) **asks once per session** to
`/addon unload luashitacast` (`profiles.shouldAskUnloadLac`, latched); the tripwire
stays the hard backstop.

**Fresh installs: full auto-setup, no Setup interaction ever (issue #91).** Once
`firstRunInit` has resolved and native mode is on, the login/job beat calls
`setupui.autoSetupNative`: when this character+job's baseline is missing it is
created **automatically and fully silently** — storage + gear inventory + the four base
sets + starter triggers (the `setupNative` content, per job, idempotent, never
clobbering). No chat on success (Henrik, post-field-confirm: the player is told
nothing about first runs, engines, or scanning — the gear inventory auto-syncs
from bags); only a FAILURE names itself, once. No red Migrate button, no popup,
no Commit for new users, ever. A later login
on a NEW job auto-seeds that job's starters the same way. HARD GATES: never in
legacy mode; never before `firstRunInit` resolves; never for a not-ready job
(`jobFile()` returns nil until `GetMainJob` settles — id-0 `NON` never seeds, hard
rule 11). A persistent write failure names itself in status/chat **once** and is
retried next beat — never ceremonialized into the Setup box. `nativeBaselineComplete`
is the completeness probe (storage + gear.lua + this job's sets + this job's
triggers), read through the same deps the seeders write through.

**Setup is now THE migration box (issue #91).** The red MIGRATE button (renamed from Setup -- Henrik 07-23: migration is its one job) shows for
exactly one reason: a **legacy-mode** session with existing dlac data
(`needsSetup` v2 — native → always false, legacy-with-data → true, driven by
`setupui.hasDlacData`). It is the standing nudge (present all session until they
migrate — ADR 0015's Phase-C banner, early), and its popup is a three-part
migration box (what you should do / what Commit will do / why) plus the hard rule,
verbatim-clear: **"It's either LAC or DLAC — never both at once. Once migrated, do
NOT run LuaAshitacast."** Commit (`setupui.migrateToNative`) is the GUI twin of
`/dl engine native on`: `profiles.engineMigrateStorage` (COPY-ONLY — nothing under
`luashitacast\` is moved, changed, or deleted; flip back any time with
`/dl engine native off`) + `setNativeMode(true)`, then the unload/reload checklist.
The in-window warning banner rewords from "X.lua is NOT set up for dlac" to that
migration nudge. The legacy clean-shim / ffxilac Setup plans are **unreachable from
the UI**; the underlying writers (`migrateToCleanProfiles`, `migrateCurrentJob`,
`setupNative`) stay in the code for Phase D and as the auto-setup content source.
Job-file imports (Sets "Copy from", Groups "Scan my Lua", the `backups\pre-profiles\`
corpus) keep reading the LAC tree READ-ONLY in both modes. The same law covers the
OTHER legacy engine's tree (Ashitacast/LegacyAC XML, 2026-07-31): `legacyacRoots` /
`legacyacPaths` are READERS — dlac never writes to any of the three homes they search.
Headless: tests NO1–NO42.

### The flip, and coexistence

```
/dl engine            status (mode, storage home, migration, tripwire)
/dl engine native on  migrate + flag; then /addon unload luashitacast + /addon reload dlac
/dl engine native off flag off; then /addon load luashitacast + /addon reload dlac
/dl engine migrate    re-run the storage copy by hand
```

Native mode requires LAC unloaded. equipengine refuses to arm inside LAC's
Lua state (NEB2), and the tripwire disarms interception for the session if
a foreign engine re-injects one of our fingerprinted action packets —
the failure mode of "forgot to unload LAC" is a loud chat line, not a
feedback loop.

### Native-mode gaps (deliberate, v1)

- **Lockstyle**: CLOSED (post-merge, #83) — the #80 executor
  (feature/lockstyleapply) is addon-resident, and in native mode every
  apply path (GUI button, town/OnLoad/keep-sub pumps via the queueCmd
  funnel, hand-typed `/dl ls apply`) routes to it directly. Only the
  `/dl debug ls` engine dry-run stays legacy-only (bridge diagnostics).
- **Trigger Monitor stream**: the `/dlacmonev` command-bus hop is inert
  natively (self-queued commands are never heard — the Ashita law), but the
  **monitor itself works** (field-confirmed 2026-07-28) — its `firedstate.lua`
  fallback carries it on a 1 s throttle, which is invisible for a 5-line log.
  Two follow-ups, both in `docs/design/integration-surface.md` §11: in ONE
  state the ring can be read directly (deleting the dead command path *and*
  the file round-trip), and the ring is **trigger-scoped** — it shows what the
  floor proposed, while `_trace[event].contest` (v143) holds the arbitration
  that actually decided each slot.
- **`/dl check` / `/dl debug`**: diagnose the two-state bridge, which
  native mode dissolves; they still print their addon halves. A
  native-aware readout wants its own field round.
- **Augment string pins** (`Augment = 'STR+5'` entries): the header pins
  (AugPath/AugRank/AugTrial) resolve natively; per-stat strings need the
  richer augment table wiring (`equipengine.augmentStringsOf`) — until
  then such pins never match, which is the SAFE direction (a wrong-augment
  piece is never equipped).
