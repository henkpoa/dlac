# Craft automation — `dlac:AutoCraft` (design)

Status: designed with Henrik 2026-07-13, building on the shipped craft
detection (craftwatch.lua, field-verified) and the crafting stat family
(8 craft skills, SynthSuccessRate/SynthHQRate/SynthMaterialLoss,
AntiHQ<craft>, ConserveIngredient). Not yet implemented.

Henrik's ask, verbatim: *"would be nice if we could implement this into the
trigger system (Default), where it would be selectable as a set. Where the
craft modes are natively built in, always there for every profile / lua. Can
you do something similar with as with AutoIridescence where we list all the
Torque's in a row then universal Torque, then do the same with the rest?"*

## Shape (mirrors ADR 0004's virtual slot entries)

1. **Manifest section** — "Rescan owned gear" (and its auto-regen cadence)
   derives `autogear.lua` a new `craft` block from bags + catalog stats:
   for each SLOT that has any owned craft gear, a tiered candidate chain
   per craft plus a universal chain — exactly the AutoStaff shape:
   craft-specific first ("all the Torques in a row"), then the universal
   piece (Artisans Torque / Kupo Shield), each entry `{ name, level,
   stats-summary }`. Data-driven from catalog stats (`<Craft>Skill`,
   `SynthSuccessRate`, `SynthHQRate`, `AntiHQ<craft>`, `SynthMaterialLoss`,
   `ConserveIngredient`) — no hardcoded item lists, new server gear appears
   on the next Rescan after a catalog update.

2. **Active-craft signal** — craftwatch already knows the craft from packet
   0x096. It publishes a dlac-owned mode (`craft = Alchemy`), crossing into
   the LAC state via the existing modestate mirror. A GUI cycle mode
   ("Craft: Off → Alchemy → … ") gives the manual pre-flip that covers the
   FIRST synth (the server rolls at 0x096 arrival; detection-driven swaps
   count from the next synth — see craftwatch.lua header).

3. **Goal signal** — cycle mode `craftgoal`: `skillup` (weights SynthSkillGain
   + <Craft>Skill), `hq` (SynthHQRate + skill), `nq` (AntiHQ<craft> first),
   `safe` (SynthSuccessRate + SynthMaterialLoss + ConserveIngredient).
   Resolution = weighted pick over the slot's chain for the active craft.

4. **Engine resolution** — `resolveVirtual` learns `dlac:AutoCraft`: active
   craft mode + goal + manifest chain → item name; no active craft → the
   standard unresolvable path (fallback `dlac:AutoCraft|<item>` or slot
   drop). Level-gated like staves/obis.

5. **Native availability** — a built-in dynamic set **`CraftAuto`** (every
   participating slot = `dlac:AutoCraft`) synthesized by the engine, so any
   profile can reference it from triggers with zero setup — Henrik's
   "always there for every profile". The Automations panel gets a Craft row
   (enable toggle + goal + manifest health), like the staff/obi rows.

6. **Equip driver** — crafting fires no LAC handler, so the dispatch tick
   (the maxmp pattern) applies `CraftAuto` when the craft mode flips on/off,
   and craftwatch's direct-equip path (v1, shipped) remains as the
   detection-time kick.

## Open decisions (Henrik)

- **D1 — restore behavior:** when the craft mode clears (zone, manual off,
  timeout?), does the engine re-equip the job's normal Default set, or leave
  worn gear alone? (maxmp precedent: drop on job change, leave gear.)
- **D2 — participating slots:** derive from data (any slot with owned craft
  gear) vs a fixed whitelist (Main/Sub/Neck/Body/Ring1/Ring2/…). Data-driven
  recommended.
- **D3 — v1 goal set:** ship all four goals, or start `skillup`/`hq` only?

## Non-goals (v1)

- First-synth menu detection (memory probe, separate research).
- Trove-channel recipe learner (blocked on GM blessing, see history).
