# Pet Handling in Other FFXI Gear-Swap Frameworks — Reference

- **Sources:** GearSwap core (`Windower/Lua` dev branch), Kinematics' Mote-libs +
  GearSwap-Jobs, Selindrile's GearSwap luas, Thorny's LuAshitacast (GitHub docs +
  the **local install** at `C:\catseyexi\catseyexi-client\Ashita\addons\luashitacast\`),
  the local ffxi-lac reference configs
  (`C:\catseyexi\catseyexi-client\Ashita\config\addons\LuAshitacast\Mindie_29909\ffxi-lac\`),
  and one real-world HorizonXI luashitacast BST profile (GetAwayCoxn).
- **Fetched:** 2026-07-17 (web files read via raw.githubusercontent.com; local files read directly).
- **Why:** dlac currently has **zero pet awareness** — no pet-exists condition, no
  pet-engaged combos, no pet action windows. This maps everything the rest of the
  ecosystem does with pets so we can decide what to adopt.
- **Verification honesty:** every claim below carries its source. Web files were
  read through a summarizing fetcher, so quotes are as returned by it; anything I
  could not confirm is flagged **UNVERIFIED** inline rather than guessed.

---

## TL;DR — framework × capability

| Capability | GearSwap core | Mote-Include | Kinematics jobs | Selindrile | luashitacast core | lac profiles (real world) |
|---|---|---|---|---|---|---|
| Pet-exists condition | `pet.isvalid` global | `pet.isvalid or state.Buff.Pet` | via Mote | via Mote | `gData.GetPet() ~= nil` | yes |
| Pet status (Idle/Engaged) | `pet.status` + `pet_status_change` event | `sets.idle.Pet.Engaged` | yes | yes | `pet.Status` string | yes (2×2 incl. pet-only-engaged) |
| Pet action window (pet "midcast") | `pet_midcast`/`pet_aftercast` events off action packets | `sets.midcast.Pet` walk: name→map→skill→type | pact/ready/WS categories | + `petWillAct` anticipation hold | `gData.GetPetAction()` polled state | ability-name → set routing |
| Pet identity (avatar/head/jug) | `pet.element` (avatars), `pet.head/frame` (automaton) | — (job-level) | per-avatar perp sets; head→PetMode | jug `pet_info` metadata | `pet.Name` only | spirit-name logic (Siphon) |
| Pet vitals as conditions (HPP/TP/dist) | fields exist (`hpp`, `tp`, `distance`) | — (job-level) | — | `pet.tp` gear tiers, `pet.hpp` auto-Reward, `pet.distance` auto-Full-Circle | `HPP`, `TP`, `Distance` fields | `pet.HPP < 60 → Pet_Dt` |
| Pet gain/loss event | `pet_change(pet, gain)` | default: re-equip on change | PUP: recompute mode | resets action timers | none (poll only) | n/a |
| Luopan treated as pet | yes (same pet table) | yes (same path) | `sets.idle.Pet` in GEO.lua | auto Full Circle >50 yalms | yes (`GetPetTargetIndex`) | n/a |
| "Pet:" stats on gear | n/a | n/a | n/a | n/a | n/a | ffxi-lac: nested `Pet={}` stat tables, scored as 0 |

---

## 1. GearSwap core (Windower) — the richest pet model

Repo: `https://github.com/Windower/Lua`, dev branch, `addons/GearSwap/`.

### 1.1 The `pet` global table — `refresh.lua`, `refresh_player()`

Built every refresh from the player's pet mob table
(`table.reassign(pet, target_complete(player_pet_table))`), then:

- `pet.isvalid = true` (or `table.reassign(pet, {isvalid=false})` when no pet) —
  so `pet.isvalid` is **always safe to read**, never nil.
- Mob-table fields come along for free: name, id, index, status, distance, hpp, position.
- `pet.tp = pet.tp/10` — normalized to the familiar 0–3000 scale.
- `pet.element` — for avatars, looked up from the `avatar_element` name→element
  table in `statics.lua` (`avatar_element = {Ifrit=0, Titan=3, Leviathan=5,
  Garuda=2, Shiva=1, Ramuh=4, Carbuncle=6, ...}`); non-avatars get
  `res.elements[-1]` — "Physical".
- **Automaton extras** (PUP): `pet.head`, `pet.frame` (item names),
  `pet.attachments`, `pet.available_heads`, `pet.mp`/`pet.max_mp`/`pet.mpp`.
- A parallel `fellow` table exists for the adventuring fellow (`refresh_group_info()`).

Default state in `statics.lua`: `pet = make_user_table(); pet.isvalid = false`.

Pet TP is kept live from the pet-sync packets: `packet_parsing.lua`
`parse.i[0x067]` and `parse.i[0x068]` write `_ExtraData.pet.tp` after verifying
the owner (`player.index == data:unpack(...)`).

### 1.2 Pet events fired to user scripts

| Event | Fired from | Trigger |
|---|---|---|
| `pet_change(pet, gain)` | `packet_parsing.lua` `parse.i[0x037]` (player update) | pet index appears/disappears (`if subj_ind == 0 and pet.isvalid` → loss; queued as `next_packet_events.pet_change`) |
| `pet_status_change(newstatus, oldstatus)` | `packet_parsing.lua` `parse.i[0x00E]` (entity update) | pet's entity status byte changes (queued with resolved status strings) |
| `pet_midcast(spell)` | `triggers.lua` `parse.i[0x028]` (action packet) | actor is the pet (`if act.actor_id == pet_id then prefix = 'pet_'`) and the category is a **ready/start** category — `readies` table in `statics.lua` = categories **7, 8, 9, 12** (WS ready, spell start, item start, ranged start) — `equip_sets('pet_midcast', ts, spell)` |
| `pet_aftercast(spell)` | `triggers.lua` `parse.i[0x029]` (action message) + completion categories (`uses` = 2,3,4,5,11,13 in `statics.lua`) | pet action resolves/interrupts — `equip_sets('pet_aftercast', nil, tab.spell)` |

Plus a queryable **`pet_midaction()`** function (mirror of `midaction()`) — used
by Selindrile's lib (§4) and requested/documented in
[Windower/Lua issue #1596](https://github.com/Windower/Lua/issues/1596).

BST jug TP moves arrive as **monster skills**, resolved by `find_monster_skill(abil)`
in `triggers.lua` (searches species TP-move tables) — so pet_midcast gets a named
ability even for jug pets.

**Known timing caveat:** [Byrth/Lua-Byrth issue #404](https://github.com/Byrth/Lua-Byrth/issues/404)
"pet_midcast too slow for automaton WS" — pet actions are only observable when
the ready packet arrives; for near-instant pet WS the swap can miss. This is why
Selindrile added the anticipation hold (§4.1). **Design-relevant for dlac:** any
pet action window is packet-reactive; anticipating from the *player's command*
(Ready/Sic/BP order) is the only way to be early.

*(UNVERIFIED detail: exact per-category semantics of 9/12 in `readies` — the
table itself and the 7/8 pet routing are verified; the labels are standard action
categories.)*

---

## 2. Mote-Include (Kinematics) — the set-naming conventions everyone copied

Repo: `https://github.com/Kinematics/Mote-libs`, `Mote-Include.lua`.

### 2.1 Idle chain — `get_idle_set(petStatus)`

```lua
if (pet.isvalid or state.Buff.Pet) and idleSet.Pet then
    idleSet = idleSet.Pet
    petStatus = petStatus or pet.status
    mote_vars.set_breadcrumbs:append('Pet')
    if petStatus == 'Engaged' and idleSet.Engaged then
        idleSet = idleSet.Engaged
        mote_vars.set_breadcrumbs:append('Engaged')
    end
end
```

- **`sets.idle.Pet`** — player idle, pet out.
- **`sets.idle.Pet.Engaged`** — player idle, **pet fighting** (this IS the
  "if idle and you have an engaged pet" case). Note the `petStatus` parameter:
  callers can pass the *incoming* status so the swap happens on the
  status-change event, not a refresh later.
- `state.Buff.Pet` also satisfies the check — lets a job flag "pet effectively
  present" via a buff. (Its exact maintenance is job-side; **UNVERIFIED** beyond
  this appearance.)

### 2.2 Engaged chain — `get_melee_set()` has **no pet branch**

Player-engaged sets ignore the pet by default in Mote; jobs graft pet gear in
`customize_melee_set`. So the standard Mote matrix is: pet affects **idle** sets
natively, **engaged** sets only by job customization.

### 2.3 Pet action routing — `get_pet_midcast_set(spell, spellMap)`

Walks `sets.midcast.Pet` through `select_specific_set` in priority order:
**custom class → `spell.english` (exact ability name) → spellMap → `spell.skill`
→ `spell.type`**. So `sets.midcast.Pet['Volt Strike']` beats
`sets.midcast.Pet.MagicalBloodPactRage` beats `sets.midcast.Pet.BloodPactRage`.

### 2.4 Hook surface

`job_pet_change`/`user_pet_change`, `job_pet_status_change`,
`job_pet_midcast`/`user_pet_midcast`, `job_pet_aftercast`/`user_pet_aftercast`,
`default_pet_midcast`/`default_pet_aftercast`, `filter_pet_midcast`.
Defaults: `pet_change` → `handle_equipping_gear(player.status)` (full re-equip
on pet gain/loss); `pet_status_change` → job hook only, **no** automatic
re-equip (jobs opt in).

Mote-Mappings.lua contains **no** pet ability maps (verified absent) — pact/ready
categorization lives in the job files (§3).

---

## 3. Kinematics GearSwap-Jobs — per-job pet vocabulary

Repo: `https://github.com/Kinematics/GearSwap-Jobs`.

### SMN.lua
- `magicalRagePacts = S{'Inferno','Earthen Fury',...}`; `job_get_spell_map`:
  `spell.type == 'BloodPactRage'` → `'MagicalBloodPactRage'` or
  `'PhysicalBloodPactRage'`; `BloodPactWard` at a monster → `'DebuffBloodPactWard'`.
- Sets: `sets.midcast.Pet.BloodPactWard`, `.DebuffBloodPactWard(.Acc)`,
  `.PhysicalBloodPactRage(.Acc)`, `.MagicalBloodPactRage(.Acc)`,
  `.WhiteMagic`, `['Elemental Magic']` (avatar healing/nuking).
- **Per-avatar perpetuation**: `sets.perp.Carbuncle`, `sets.perp.Alexander`
  (keyed by `pet.name`), plus `sets.perp.Day`/`sets.perp.Weather` applied when
  `pet.element == world.day_element` (avatar element vs day/weather match).
- `sets.idle.Avatar` (+ `sets.idle.Avatar.Favor` for Avatar's Favor), and in
  `customize_idle_set`: `if pet.status == 'Engaged' then idleSet =
  set_combine(idleSet, sets.idle.Avatar.Melee)`.

### BST.lua
- `state.RewardMode = M{'Theta','Zeta','Eta'}` → `RewardFood.name = "Pet Food
  " .. newValue`; `sets.precast.JA['Reward']` equips the food in ammo.
- Ready moves: `sets.midcast.Pet.WS` (+ `.Unleash`); **monster correlation**
  gear via `sets.midcast.Pet.Neutral` / `sets.midcast.Pet.Favorable`, equipped in
  `job_pet_post_midcast` from `state.CorrelationMode`.
- `sets.idle.Pet`, `sets.idle.Pet.Engaged`.

### PUP.lua — automaton identity drives everything
- `petModes = {['Harlequin Head']='Melee', ['Sharpshot Head']='Ranged',
  ['Valoredge Head']='Tank', ['Stormwaker Head']='Magic',
  ['Soulsoother Head']='Heal', ['Spiritreaver Head']='Nuke'}`;
  `get_pet_mode()` returns `petModes[pet.head]` when `pet.isvalid`.
- `update_pet_mode()` (called from `job_pet_change`) repopulates
  `classes.CustomIdleGroups` → idle sets keyed by mode:
  `sets.idle.Pet.Engaged.Ranged`, `sets.idle.Pet.Engaged.Nuke`, etc.
- Automaton actions: `sets.midcast.Pet.WeaponSkill`, `.Cure`,
  `['Elemental Magic']`; maneuvers per mode (`defaultManeuvers['Melee'] = {'Fire
  Maneuver',...}`) with `sets.precast.JA.Maneuver`.

### GEO.lua — the luopan is just a pet
- `sets.idle.Pet` and `sets.idle.PDT.Pet` hold pet-DT gear for the luopan; they
  ride the generic Mote `pet.isvalid` idle path (no GEO-specific pet code, no
  luopan HP handling in this file).

---

## 4. Selindrile GearSwap — automation on top of pet state

Repo: `https://github.com/Selindrile/GearSwap` (libs `Sel-Include.lua` is a
Mote fork — same idle walk `(pet.isvalid or state.Buff.Pet) → sets.idle.Pet →
.Engaged`; same `sets.midcast.Pet` routing).

### 4.1 `petWillAct` — the anticipation hold (unique, and the fix for §1's caveat)
- `init_include()`: `petWillAct = 0`.
- Gear gate: `if not midaction() and not (pet_midaction() or ((petWillAct + 2) >
  os.clock())) then handle_equipping_gear(player.status)` — after commanding a
  pet action, idle refreshes are **suppressed for ~2s** so pet-action gear isn't
  stripped before the action packet lands.
- `default_pet_aftercast`: re-equip + `petWillAct = 0`; `pet_change` also resets it.
- (**UNVERIFIED**: the exact site that *sets* `petWillAct = os.clock()` — by
  pattern it's the job files' precast for Ready/BP/Sic commands; I confirmed the
  init/gate/reset sites only.)

### 4.2 BST.lua — pet vitals as live conditions
- **Pet TP tiers for gear**: TP-bonus gear applied when `pet.tp < 1900` (lower
  thresholds for non-Warrior jug jobs) — gear chosen from how much TP the pet
  still needs.
- **Auto-Reward**: fires when `pet.hpp < 34` and `state.AutoRewardMode`, with
  recast check (ability 103) and `item_available('Pet Food '..state.RewardMode.value)`.
- **Auto-engage**: `if pet.status == 'Idle' and player.target.type == 'MONSTER'`
  → `/pet Fight`.
- **Jug metadata**: `state.JugMode` over 12+ jugs; `pet_info{}` maps each jug pet
  to species/family/job (e.g. *"Crab, Aquan, Paladin"*); `ready_moves`
  preference maps per category (default/aoe/buff/debuff/physical/magical);
  Bestial Loyalty precast checks inventory for the matching broth.
- Ready set categories: `sets.midcast.Pet.DebuffReady`,
  `.MagicReady[OffenseMode]`, `.MultiHitReady`, `.PhysicalDebuffReady`; Unleash
  gear-lock (`UnleashLocked`) pins the ready set while Unleash is up.

### 4.3 GEO.lua — luopan babysitting
- Auto **Full Circle** when `pet.distance:sqrt() > 50` (luopan out of range).
- Auto **Ecliptic Attrition** / **Blaze of Glory** sequencing with
  `used_ecliptic` / `blazelocked` flags, reset in `job_pet_change` and on
  `pet.isvalid` loss.

---

## 5. LuAshitacast (Thorny, Ashita) — dlac's own ecosystem

Local primary source: `C:\catseyexi\catseyexi-client\Ashita\addons\luashitacast\`.
Docs: `https://thornyffxi.github.io/LuAshitacast/gdata.html`.

### 5.1 Pet state — `data.lua:534` `data.GetPet()`
Reads the pet via `GetEntity():GetPetTargetIndex(myIndex)`; returns **nil when no
pet or pet HPP is 0**; otherwise: `Distance` (sqrt'd), `HPP`, `Id`, `Index`,
`Name`, `Status` (resolved string: Idle/Engaged/Dead/...), `TP`
(`GetPlayer():GetPetTP()` — memory-read, no packet bookkeeping needed).
The luopan resolves through the same pet index. **No head/frame, no element, no
MP** — thinner than GearSwap's table.

### 5.2 Pet actions — polled state, not an event
- `packethandlers.lua` `HandleIncoming0x28` (action packet): when the actor is
  the pet — actionType **7** = ability ready (`actionMessage == 43` → MobSkill
  with name from `monsters.abilities`, else Ability resource) and **8** = spell
  start (resource + cast time). Stored in `gState.PetAction` with a `Completion`
  deadline: `PetskillDelay` (config, default **4.0s**, exposed as a settings
  slider "Maximum time allowed for a pet's weaponskill to finish",
  `config.lua:23`) or spell cast time + `SpellOffset`.
- Cleared on completion packet types `PetActionCompleteTypes = T{4, 11, 13}`
  (`constants.lua:3`), on interrupt markers in types 8/12, and on timeout
  (`HandleOutgoingChunk`, `packethandlers.lua:257`).
- `data.lua:552` `data.GetPetAction()` exposes it: `ActionType`
  (Spell/Ability/MobSkill) + resource fields (CastTime, Element, MpCost, Skill,
  Type, ...).
- **There is no pet callback** — no HandlePetAction hook exists in the core
  (verified: full `Handle*` inventory has only
  Command/Default/Ability/Item/Precast/Midcast/Preshot/Midshot/Weaponskill).
  Profiles must poll `gData.GetPetAction()` inside `HandleDefault`, which runs
  per outgoing chunk. This is the model dlac's dispatch engine would naturally
  improve on.

### 5.3 Real-world profile patterns (HorizonXI-era)
From `GetAwayCoxn/Luashitacast-Profiles` BST.lua
(`https://github.com/GetAwayCoxn/Luashitacast-Profiles`):
- `HandleDefault` checks `gData.GetPetAction()` **first**; if present →
  `HandlePetAction` and return (pet action outranks idle/engaged logic).
- The player×pet 2×2 spelled out as sets: player engaged → `Tp_*`; **both**
  engaged → `sets.Tp_Hybrid`; **pet only** engaged → `sets.Pet_Only_Tp`; else
  `sets.Idle`.
- Ready routing by **ability-name lists** in gcinclude: `BstPetAttack` /
  `BstPetMagicAttack` / `BstPetMagicAccuracy` → `sets.PetAttack` /
  `sets.PetMagicAttack` / `sets.PetMagicAccuracy`.
- Pet defense: DT toggle + `pet.HPP < 60` → `sets.Pet_Dt`.

### 5.4 Local ffxi-lac reference (`config\addons\LuAshitacast\Mindie_29909\ffxi-lac\`)
- `gcinclude.lua:439-446` (commented-out auto-gear): `Pet_Dt` set when
  `pet.HPP < gcinclude.settings.PetDTGearHPP`.
- `gcinclude.lua:659` `DoSiphon()`: pet-name logic — checks the summoned spirit
  vs day (`spirits = {['Firesday']='Fire Spirit', ...}`), releases and
  re-summons before Elemental Siphon.
- `gear.lua` (item DB): pet stats modeled as a **nested `Pet = {}` table** on
  item Stats (`Pet = {Attack=15, Accuracy=10}`, `Pet.DomainIncursion = true`);
  `gearoptim.lua:104` explicitly scores the nested Pet table as **0** ("the
  nested Pet table count as 0 so scoring never errors"). Direct precedent for
  how dlac's catalog/weights would need a pet-stat namespace before pet sets can
  be *optimized*, not just selected.

---

## 6. Gaps vs dlac — every distinct capability found

Conditions (the immediate ask):
1. **Pet exists** — the baseline condition every framework has (`pet.isvalid`,
   `GetPet() ~= nil`). dlac: absent.
2. **Pet status** — Idle/Engaged(/Dead) as a condition, giving the full player×pet
   matrix; the ecosystem-standard names are Mote's `sets.idle.Pet` /
   `sets.idle.Pet.Engaged` and lac-profile `Tp_Hybrid` / `Pet_Only_Tp`.
   "Player engaged + pet" natively affects only *idle* sets in Mote; engaged+pet
   combos are job-side or profile-side everywhere.
3. **Pet vitals thresholds** — `pet.HPP` (pet-DT sets, auto-Reward), `pet.TP`
   (TP-bonus gear tiers on ready moves — Selindrile only), `pet.Distance`
   (GEO auto-Full-Circle — automation, not gear).
4. **Pet identity** — by name (avatar perp sets, spirit/day logic), by element
   vs day/weather (SMN perp), by automaton head→mode (PUP idle groups). Jug
   NQ/HQ is handled by nobody better than dlac's existing sets+cycle answer;
   Selindrile's `pet_info` species/family/job metadata is the richer version.
5. **Pet buffs as state** — Avatar's Favor, Killer Instinct, Unleash lock,
   PUP maneuvers (player-side buffs standing in for pet state).

Action windows:
6. **Pet action window ("pet midcast")** — swap when the *pet* acts: BP rage/ward,
   Ready/sic, automaton WS/spells, wyvern breaths (wyvern: no framework had
   special handling beyond the generic pet action path — DRG breath sets would
   key off ability name/type like everything else). Routing precedence
   everywhere: exact ability name → category/map → skill → type.
7. **Pet aftercast / return to previous state** after the window closes
   (timeout-guarded in luashitacast: 4s default).
8. **Anticipation hold** — suppress re-equips between commanding a pet action
   and its packet arriving (Selindrile's `petWillAct + 2s` gate; fixes the
   automaton-WS-too-fast problem). Maps naturally onto dlac's engine-native
   stateless holds (sync-settle precedent).

Events:
9. **Pet gain/loss** (`pet_change(pet, gain)`) → recompute identity-derived
   state and re-equip; **pet status change** → re-resolve idle immediately
   (Mote even passes the incoming status to beat the refresh).

Periphery:
10. **Reward food selection** (mode-cycled ammo food) and broth/jug inventory
    checks — item-in-slot logic, adjacent to dlac's craft/HELM overlay pattern.
11. **Luopan = pet** — confirmed in every framework (same pet index/table);
    "GEO idle pet set" needs nothing special beyond capability 1+2, which is
    exactly the Henrik use-case that started this.
12. **Pet-stat namespace on gear** (`Pet: Attack` etc. as nested stats) — needed
    eventually if pet sets should participate in weights/optimization; ffxi-lac
    precedent parses it and deliberately scores it 0.
