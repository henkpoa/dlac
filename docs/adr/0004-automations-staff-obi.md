# Built-in Automations (auto staff/obi) are engine-generated Triggers, not user data

"Auto elemental staff" and "auto obi" are dlac-shipped behaviors toggled by an option — the engine synthesizes their Triggers at dispatch time from *owned gear*; nothing is written into the user's trigger file. They run in their own priority band (60): above exact-name Triggers (50), so automation overrides a dedicated per-spell set as requested, but below Modes (100), so manual intent always wins. Keeping them as ordinary Triggers in the overlay pipeline (rather than a special code path) means `/dl why` explains them like anything else.

Rules:
- **Staff** (Midcast, spell has element E): skip when the Main about to be worn carries Iridescence; else equip the owned elemental staff for E (HQ preferred) into Main.
- **Obi** (Midcast, spell has element E): equip E's obi into Waist when the net day+weather bonus for E is positive ("the moment it's positive, it's better"). Independent of Iridescence — obis stay relevant after staff swapping retires.

Two supporting decisions:
- **Inline equip payloads**: a Trigger's action is either a set name or an inline slot map (`equip = { Waist = 'Karin Obi' }`). Automations require this (no auto-generating 16 one-slot sets), and users get it too.
- **Iridescence detection reads the catalog**: the CatsEyeXI API exposes `Iridescence` (e.g. Chatoyant Staff 18633 has +2; Foreshadow +1 is another carrier) and per-element `Staff Bonus` mods — `tools/modifier_map.lua` must be extended to map them so the crawl stops dropping them. No hand-curated item list.
