# The pet's element gets the three environment tests: `petDayWeatherBonus`, `petWeatherMatch`, `petDayMatch`

The three environment conditions (`dayWeatherBonus`, `weatherMatch`, `dayMatch`) test the **action's** element. Their pet twins test **your pet's** element, an avatar's or an elemental spirit's, against the same day and weather. They are three new conditions in the Pet cascade, not a mode of the old three, because the element they need is one the action never carries.

## Context

Henrik, 2026-10-17: *"We need to have under pet category like dayWeatherBonus, weatherMatch and dayMatch, but for pets. This is mainly for summoner … they want to be able to match elements for gear etc, if the weather, day match etc."* He named the **Default** and **Ability** handlers.

The gear exists on AscensionXI (`sql/item_mods.sql`, origin/main), and the server's rule for it is plain:

- **Summoner's Dblt.** (15101) and **Smn. Doublet +1** (14514): `DAY_REDUCTION` 3, avatar perpetuation −3 while the day is the avatar's element.
- **Summoner's Horn** (15086) and **Smn. Horn +1** (15259): `WEATHER_REDUCTION` 3, perpetuation −3 while the weather is the avatar's element. **Caller's Pendant** (11619): `WEATHER_REDUCTION` 1.

The server applies these in `CStatusEffectContainer::TickRegen` (`src/map/status_effect_container.cpp`): `dayMatch = dayElement == petElement`, and `weatherMatch` is the pet element's single **or** double weather read through `battleutils::GetWeather(PChar, false)`. That is the master's weather with the master's own storm folded in. Neither check has an opposition term. `HALF_PERPETUATION_DAY` and `HALF_PERPETUATION_WEATHER` use the same two booleans.

Elemental Siphon, an Ability, drains `power × calculateDayAndWeather(player, spiritElement, true)` (`scripts/actions/abilities/elemental_siphon.lua`). That is the obi's signed day and weather rule over the **spirit's** element, always applied, and Iridescence and Twilight Cape add to it. So all three questions have Ability-side gear too.

None of the existing conditions can ask them. Default has no action at all. In Ability a Blood Pact or Elemental Siphon is an ability, and abilities carry no element (`nativedata.GetAction`, LAC parity: only spells resolve one). The element these gear pieces key on belongs to the **pet**.

## Decision

Three conditions, each the pet twin of an existing one:

- `petDayWeatherBonus` is the obi's signed net (+1 per matching day or weather, −1 per the opposing element) over the pet's element. `true` means net > 0, `false` means net ≤ 0, and a number means net ≥ n, the same three forms `dayWeatherBonus` takes.
- `petWeatherMatch` means the current weather element equals the pet's element: single or double, the player's own storm counted, no day and no opposition.
- `petDayMatch` means today's day element equals the pet's element: no weather and no opposition.

**The element.** `dispatch.PET_ELEMENT`, keyed by the pet's name, is the server's `pet_list.element` column: eight spirits, Carbuncle, Fenrir, Ifrit, Titan, Leviathan, Garuda, Shiva, Ramuh, Diabolos, Alexander, Odin, Atomos, Cait Sith and Siren. CatsEyeXI's rows are identical where it has them. Every other pet (jug pets, the wyvern, automatons, luopans) has element 0 on the server and has no entry here. The key is the name lowercased with everything but letters stripped. The server sends a spirit as `FireSpirit` (`pet_list.name`, verbatim in the 0x00E name field), its summoning spell is `Fire Spirit`, and `Cait Sith` keeps its space, so all three spellings land on one key. Test PE1 pins every row against the SQL row it came from.

**The reads.** `weatherMatchesAction` and `dayMatchesAction` became `weatherMatchesElement(ctx, el)` and `dayMatchesElement(ctx, el)`. The action conditions pass the action's element and the pet conditions pass the pet's. Both read the same `ctx.wel` and `ctx.del` cache, and the pet net is built from those same two reads, so nothing can disagree about the world inside one dispatch. The pet's element is cached on `ctx.pel`.

**Unknown matches neither polarity.** No pet, a pet without an element, or an unreadable day or weather fails both `= true` and `= false`, the discipline `weatherMatch`, `dayMatch`, `target` and `inTown` share. This is deliberately stricter than the v1 `dayWeatherBonus`, which scores an unknown as a net of 0 and so fires its `false` polarity blind. That old behaviour is left alone: changing it would change rules players already have.

**Tier 24.** That is one step above `petStatus` (23) and under `moving` (25). The pet tiers were placed with one rule (v63): a pet-refined rule outranks its base rule without a hand priority, and Movement still overlays. A rule refined by the pet's element is a refined pet rule, so `{ pet = true }` plus `petDayMatch` overlays the plain perpetuation set (22) and the pet-fighting set (23), and movement gear still wins its slot while moving. The action siblings sit at 30, but that is the element band of spell rules. Placing the pet twins there would put an idle perpetuation piece above Movement.

**The GUI.** The three are entries in the shared Pet cascade, beside HasPet, NoPet, PetStatus and PetName, as flags (`kind = 'fixed', value = true`). They have live `[on now]` markers and wear their environment siblings' colours, so the colour says which test and the `pet` in the name says whose element. The Pet cascade is offered on every handler, so they appear on every handler too. Default and Ability, the two Henrik named, are the ones the gear needs, and the engine judges them the same everywhere.

## Why not reuse the action's three

There are two reasons. Each one alone would settle it.

1. **There is nothing to read.** Default has no action, and Ability's actions carry no element, so a `dayMatch` rule there matches neither polarity forever. Teaching the action conditions to fall back to the pet's element when the action has none would make one key mean two things depending on the handler. It would also quietly change what an existing `dayMatch` rule in PetAction means.
2. **The two elements differ even when both exist.** A Summoner casting a Fire spell on Firesday in Ice weather with Shiva out has a spell that matches the day and a pet that matches the weather. `dayMatch` must say the first and `petDayMatch` must not. Tests PE37–PE40 pin that independence.

## Consequences

The condition count grows by three, but they add no new concept. Each pet twin is its sibling with the element taken from somewhere else. The glossary (`CONTEXT.md`, *Pet element match*), the trigger-system vocabulary table and the GUI hints say so in those words.

The element table is static. FFXI's avatar elements have never moved, but a server that adds a pet with an element needs a row here, and PE2 pins the row count so the addition is deliberate. A server-side `pet_list` change is the signal to look.

Tests PE1–PE54 (run_tests) and TB43–TB49 (smoke_ui). TB43–TB49 drive the real builder popup on Default and Ability and load each saved rule back through the engine.
