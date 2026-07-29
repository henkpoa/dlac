# `dayMatch` is the third environment condition — a day-only bonus is invisible to both the obi net and the weather match

The `dayMatch` trigger condition (the action's element equals TODAY's day element) is a **third** condition beside `dayWeatherBonus` and `weatherMatch`, not a mode of either. Gear that pays out on the day and nothing else exists, and neither neighbour tracks it: the obi's net folds weather and opposition into the same number, and `weatherMatch` has no day term at all.

## Context

Henrik, field: *"There are items that give you bonus solely if the day match what you're casting."* dlac already had two environment tests, and a player who wanted to gear that item had to pick the wrong one of them:

- `dayWeatherBonus` (v1) — the obi's **signed net** over day AND weather, with the opposing element as a minus: +1 per matching day/weather, −1 per the opposing one, favourable when > 0.
- `weatherMatch` (v121, ADR 0018) — a **plain weather-element equality**: no day, no opposition.

Neither is the day-only test. This is exactly the shape ADR 0018 already ruled on once, on the other axis, and the answer generalizes: an environment condition must track the mechanic it is named for, not a superset that happens to overlap it most of the time.

## Decision

Add `dayMatch` (a plain equality: spell element == current day element) on Precast + Midcast, tier 30, with the `weatherMatch` polarity contract. The three environment conditions are now:

- `dayWeatherBonus` — the obi's signed net over day + weather, with opposition.
- `weatherMatch` — the spell's element == the CURRENT weather element.
- `dayMatch` — the spell's element == TODAY's day element.

`dayMatchesAction` reads `gData.GetEnvironment().DayElement` — the same field `netForElement` already scores for the obi, so the day half of the net and this condition can never disagree — cached once per dispatch on `ctx.del`, beside `weatherMatch`'s `ctx.wel`. No action element (Default handler / Non-Elemental) or an unreadable day matches **neither** polarity: a `dayMatch` rule never fires blind, the discipline `target`/`inTown`/`weatherMatch` all share.

## Why not extend `dayWeatherBonus`

The same both-directions proof ADR 0018 ran for weather, run for day. For a **Fire** spell:

- **Firesday, Water (opposing) weather** — the net is +1 −1 = **0**, so `dayWeatherBonus` stays quiet. But the day matches: the item **is** paying out. It **under-fires**.
- **Earthsday, Fire weather** — the net is **+1** (weather matches, Earth does not oppose Fire), so `dayWeatherBonus` fires. But the day does not match: the item is **dark**. It **over-fires**.

`weatherMatch` is not a candidate at all — it has no day term, so it is simply the wrong axis. Only the plain day equality tracks when a day-only bonus is live.

## The day/weather asymmetry, which is real and worth knowing

There is **no "clear day."** All eight Vana'diel weekdays carry an element (`WeekDayElement` in LAC's `constants.lua`, `WEEK_DAY_ELEMENT` in `nativedata.lua`: Fire, Earth, Water, Wind, Ice, Thunder, Light, Dark), so a day we can read is always a real match or a real non-match, and only a **failed read** is unknown. Weather has a genuine `None` (Clear / Sunshine / Clouds / Fog), which `weatherMatch` must treat as a real non-match rather than as unknown. Same three-state contract in both, but `dayMatch` can only reach the unknown state through a broken read.

Day is also **not storm-aware**, correctly: `GetEnvironment().WeatherElement` folds the caster's own storm buff over the zone weather (which is why a Scholar's Firestorm counts for `weatherMatch`), but nothing in the game changes the day, so `DayElement` is the plain calendar read.

## What was NOT verified

ADR 0018 pinned `weatherMatch` to a **named** server mechanic (`ALACRITY_CELERITY_EFFECT`, read out of `battleutils.cpp`). This ADR does **not** do that: the CatsEyeXI server source is not on this machine, and no specific item was named in the request. `dayMatch` is therefore shipped as a **primitive** — "the day element equals the spell's element", a statement about the calendar that is true regardless of which item motivated it — and deliberately not as a bespoke bundle for one piece of gear. If a day-only item later needs its exact gate pinned (does it want day only, or day-or-weather the way the retail obi tooltip reads?), that is a follow-up verification against the server, and it changes which conditions a player **composes** — not this condition's meaning.

## Consequences

Three environment conditions coexist, and the honest answer to "why three?" is that they are three different questions about the world. The pairwise distinction is now pinned in `CONTEXT.md` (*Day match* / *Weather match* / *Day/weather favourability*, each with the others in its `_Avoid_` line), in the `docs/design/trigger-system.md` vocabulary table, and in the GUI hints, which cross-reference each other so the builder menu itself steers a player to the right one. Tests DM1–DM24, including DM14–DM17, which pin the independence directly: the Firesday/Water-weather case where `dayMatch` fires and the other two do not, and its mirror.
