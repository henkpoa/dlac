# Automations (auto staff/obi) are VIRTUAL SLOT ENTRIES inside the set

**Current model (4th revision, 2026-07-10, Henrik's "slot function" insight):** a set's slot can hold a virtual entry instead of an item — `dlac:AutoStaff` in Main, `dlac:AutoObi` in Waist, added from the same `+ Add` picker as gear. `BuildDynamicSets` passes the marker through the flattening; the dispatch engine resolves it **at equip time** from the gear manifest; an unresolvable marker drops its slot so LAC leaves what's worn. `/dl why` shows each resolution inline (`[dlac:AutoStaff=Chatoyant Staff]` / `skipped (reason)`).

Why this beat the alternatives we actually shipped first: global toggles (rev 1) weren't granular; per-set `SetOptions` flags (rev 3) were **invisible in the set builder** — a whole debugging session happened because Main *looked* empty while a hidden flag was supposed to fill it — and lived in a different file than the set, enabling a Commit to wipe them. A slot entry is visible exactly where the gear it produces will appear, is naturally per-slot, and needs no extra config section at all. There is no priority band anymore: the entry rides its set's own rule priority.

Rules:
- **Staff**: equip the best-Iridescence staff into Main. CatsEyeXI's Iridescence is **tiered**: elemental staves carry it for their own element only (NQ +1, HQ +2); universal weapons carry it for every element (Iridal Staff +1; Chatoyant Staff / Foreshadow +1 = +2). Per cast: higher tier wins, **ties go to the universal** (no cross-element swapping, works for elementless actions like Ability triggers, and Chatoyant-class weapons carry the per-element staff bonuses anyway). Third revision (tiering) from Henrik's mechanics walkthrough; the second made the universal weapon *the* staff; the first cut wrongly suppressed staff swapping for Iridescence owners.
- **Obi** (action has element E): equip E's obi into Waist when the net day+weather bonus for E is positive ("the moment it's positive, it's better"). Always element-gated, independent of Iridescence.

Implementation split (two Lua states): the **GUI derives** a per-character manifest — `<char>\dlac\autogear.lua` with the toggles, the best owned staff/obi per element, and the Iridescence flag (from bags + catalog names) — and the **engine reads** it, hot-reloaded like the trigger file. The engine never loads the 5 MB catalog.

Two supporting decisions:
- **Inline equip payloads**: a Trigger's action is either a set name or an inline slot map (`equip = { Waist = 'Karin Obi' }`). Automations require this (no auto-generating 16 one-slot sets), and users get it too.
- **Iridescence detection reads the catalog**: the CatsEyeXI API exposes `Iridescence` (e.g. Chatoyant Staff 18633 has +2; Foreshadow +1 is another carrier) and per-element `Staff Bonus` mods — `tools/modifier_map.lua` must be extended to map them so the crawl stops dropping them. No hand-curated item list.
