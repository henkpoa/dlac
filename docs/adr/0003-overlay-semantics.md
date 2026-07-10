# Triggers overlay — every match applies, specificity sets default priority

When multiple Triggers match one Handler event, ALL of them apply: sorted by priority ascending, each `EquipSet` overlays the previous per-slot (later wins). There is no exclusive/first-match mode — a set that fills all slots *is* a replacement under overlay, so overlay expresses both behaviors; exclusive can't express overlay. Ties break by trigger-file order.

Default priorities come from matcher specificity, so casual users never type a number — the more specific, the later it lands (canonical example: Enfeebling → White Enfeebling → Slow):

| tier | example | default |
|---|---|---|
| Any (whole handler) | all Precast → FastCast | 10 |
| Skill / school / status | Enfeebling Magic, Singing, Engaged | 20 |
| Derived class / element | White Enfeebling, songType=Buff, element=Earth | 30 |
| Family / group | "Minuet" (all tiers), "Cure" | 40 |
| Exact name | Slow II, Repair, Holy Water | 50 |
| Mode (manual intent) | DT mode | 100 |

Every priority is user-overridable in the GUI; the numbers above are only what a blank field means.

Consequence (documented, deliberate): unlike classic `if/elseif` profiles, being idle *and* moving equips the Idle set with Movement overlaying its slots (e.g. Feet), instead of the Movement set alone — statuses like Engaged/Resting/Idle remain naturally exclusive because only one can be true.
