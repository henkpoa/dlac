# Built-in Automations (auto staff/obi) are engine-generated Triggers, not user data

"Auto elemental staff" and "auto obi" are dlac-shipped behaviors — the engine synthesizes their Triggers at dispatch time from *owned gear*. They run in their own priority band (60): above exact-name Triggers (50), so automation overrides a dedicated per-spell set as requested, but below Modes (100), so manual intent always wins. Keeping them as ordinary Triggers in the overlay pipeline (rather than a special code path) means `/dl why` explains them like anything else.

**Activation is PER SET, two independent flags** (revised 2026-07-10 from the original global toggles, on Henrik's direction): a set carries `Auto staff` / `Auto obi` settings — `SetOptions = { <SetName> = { staff=, obi= } }` in the trigger file, edited from the Sets tab — and the automation fires only on a Midcast whose matched triggers equip a flagged set. Rationale: the automation belongs to the set's *purpose* (a nuke set wants staff+obi; a cure or song set may not), not to the character globally.

Rules:
- **Staff** (Midcast, spell has element E): equip the owned elemental staff for E (HQ preferred) into Main. Iridescence suppression, v1: *owning* an Iridescence weapon disables staff swapping entirely — you keep it in your sets, so per-element staves gain nothing ("you don't need to use elemental staves anymore"). A per-cast pending-Main check was considered and deferred: the engine can't see LAC's pending equip state cheaply, and ownership answers the practical question.
- **Obi** (Midcast, spell has element E): equip E's obi into Waist when the net day+weather bonus for E is positive ("the moment it's positive, it's better"). Independent of Iridescence — obis stay relevant after staff swapping retires.

Implementation split (two Lua states): the **GUI derives** a per-character manifest — `<char>\dlac\autogear.lua` with the toggles, the best owned staff/obi per element, and the Iridescence flag (from bags + catalog names) — and the **engine reads** it, hot-reloaded like the trigger file. The engine never loads the 5 MB catalog.

Two supporting decisions:
- **Inline equip payloads**: a Trigger's action is either a set name or an inline slot map (`equip = { Waist = 'Karin Obi' }`). Automations require this (no auto-generating 16 one-slot sets), and users get it too.
- **Iridescence detection reads the catalog**: the CatsEyeXI API exposes `Iridescence` (e.g. Chatoyant Staff 18633 has +2; Foreshadow +1 is another carrier) and per-element `Staff Bonus` mods — `tools/modifier_map.lua` must be extended to map them so the crawl stops dropping them. No hand-curated item list.
