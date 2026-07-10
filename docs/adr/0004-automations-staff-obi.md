# Built-in Automations (auto staff/obi) are engine-generated Triggers, not user data

"Auto elemental staff" and "auto obi" are dlac-shipped behaviors — the engine synthesizes their Triggers at dispatch time from *owned gear*. They run in their own priority band (60): above exact-name Triggers (50), so automation overrides a dedicated per-spell set as requested, but below Modes (100), so manual intent always wins. Keeping them as ordinary Triggers in the overlay pipeline (rather than a special code path) means `/dl why` explains them like anything else.

**Activation is PER SET, two independent flags** (revised 2026-07-10 from the original global toggles, on Henrik's direction): a set carries `Auto staff` / `Auto obi` settings — `SetOptions = { <SetName> = { staff=, obi= } }` in the trigger file, edited from the Sets tab — and the automation fires on **any handler** whose matched triggers equip a flagged set (flags of all matched sets union; second revision, from in-game testing — an Ability trigger like Pianissimo→Elegy must fire it too, not just Midcast). Rationale: the automation belongs to the set's *purpose* (a nuke set wants staff+obi; a cure or song set may not), not to the character globally.

Rules:
- **Staff**: equip the staff into Main. An owned **Iridescence weapon IS the staff** — it covers every element, so it equips for elementless actions too (second revision, from in-game testing; the first cut wrongly *suppressed* staff swapping for Iridescence owners). Without one, the best owned per-element staff (HQ preferred) is used and requires the action to carry an element.
- **Obi** (action has element E): equip E's obi into Waist when the net day+weather bonus for E is positive ("the moment it's positive, it's better"). Always element-gated, independent of Iridescence.

Implementation split (two Lua states): the **GUI derives** a per-character manifest — `<char>\dlac\autogear.lua` with the toggles, the best owned staff/obi per element, and the Iridescence flag (from bags + catalog names) — and the **engine reads** it, hot-reloaded like the trigger file. The engine never loads the 5 MB catalog.

Two supporting decisions:
- **Inline equip payloads**: a Trigger's action is either a set name or an inline slot map (`equip = { Waist = 'Karin Obi' }`). Automations require this (no auto-generating 16 one-slot sets), and users get it too.
- **Iridescence detection reads the catalog**: the CatsEyeXI API exposes `Iridescence` (e.g. Chatoyant Staff 18633 has +2; Foreshadow +1 is another carrier) and per-element `Staff Bonus` mods — `tools/modifier_map.lua` must be extended to map them so the crawl stops dropping them. No hand-curated item list.
