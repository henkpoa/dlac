# `weatherMatch` is its own condition — the Scholar cast-time bonus is weather-only, not the obi's day/weather net

The `weatherMatch` trigger condition (the action's element equals the CURRENT weather element) is deliberately a **separate** condition from `dayWeatherBonus` (the obi's signed day+weather net with opposition), not an extension of it. The driver was a Scholar Celerity/Alacrity cast-time set; the natural assumption was to reuse the existing "favourable day/weather" logic — but verifying the item against the server showed the two mechanics are genuinely different, and conflating them would mislabel one as the other.

## Context

A player asked to gate a Scholar cast-time set on "favourable elemental conditions," defining favourable as the obi's rule (net positive over day + weather). The item — "+10% casting & recast under Celerity/Alacrity while under a weather effect matching the element of the spell" (server mod `ALACRITY_CELERITY_EFFECT`) — was verified in the CatsEyeXI source (`src/map/utils/battleutils.cpp`: `WeatherMatchesElement(GetWeather(PEntity, false), spell element)`, on white magic under `EFFECT_CELERITY` / black magic under `EFFECT_ALACRITY`). It keys on **weather only** — no day term, no opposing-element penalty, single or double weather both count, and `GetWeather(…, false)` counts the caster's own storm. The retail tooltip's "or day" is not implemented here.

## Decision

Add a new condition, `weatherMatch` (a plain equality: spell element == current weather element), on Precast + Midcast, tier 30. Keep it distinct from `dayWeatherBonus`:

- `dayWeatherBonus` — the obi's **signed net**: +1 per matching day/weather, −1 per the opposing element, favourable when > 0.
- `weatherMatch` — a **plain weather-element equality**: no day, no opposition.

It reads the same `gData.GetEnvironment().WeatherElement` the obi uses, which is storm-aware (LAC's `data.lua` and dlac's `nativedata.lua` both override zone weather with the caster's active storm buffs), so a self-cast storm counts for free. The Celerity/Alacrity buff gate is left to the player to compose via the existing `buff` conditions — `weatherMatch` stays a minimal, reusable primitive rather than a bespoke "SCH cast-time" bundle.

## Why not extend `dayWeatherBonus`

Gating the cast-time set on the net would be wrong in **both** directions (for a Thunder spell): on Thunder day with no Thunder weather the net is +1 so it would fire, but the item does **not** proc (no matching weather); on Earth day with Thunder weather the net is 0 so it would stay silent, but the item **does** proc (weather matches). Only the plain weather match tracks when the bonus is actually live. A dual-mode or param-carrying `dayWeatherBonus` was considered and rejected: the mechanics are different enough that one condition serving both invites exactly the "favourable" overload that started this (now pinned apart in `CONTEXT.md`: *Weather match* vs *Day/weather favourability*).

## Consequences

Two weather-ish conditions coexist; a future reader's "why two?" is answered here and in `docs/design/trigger-system.md`. The condition is a primitive — the buff gate and any white/black-magic split are the player's rule composition, not baked in.

*Numbering: 0017 is reserved by the concurrent `feature/idle-hobby-exclusion` branch (its ADR 0017), so this ADR takes 0018 to avoid a merge-time collision.*
