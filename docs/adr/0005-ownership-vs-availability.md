# Ownership scans every container; availability stays narrow

`gear.lua` documents everything the character OWNS, wherever it lives: the scan default
is `ALL_CONTAINERS` (Inventory, Safe/Safe2, Storage, Temporary, Locker, Satchel, Sack,
Case, 8 Wardrobes). Equip decisions — the dispatch engine, pairing rules, automations,
and the GUI's red-name marking — use the separate AVAILABILITY set (`SCAN_CONTAINERS`:
Inventory + Wardrobes), refreshed live (~4 s heartbeat).

We rejected the original single narrow scan (Inventory + Wardrobes for everything): it
silently dropped deep-storage gear from the library, made prune impossible to trust, and
regenerating a lost gear.lua could not recover stored items. We also rejected treating
stored gear as equippable: LAC would try to equip items the server won't accept.

Consequences:
- Auto-sync stays ADD-ONLY over all containers; removal is exclusively `/dl prune`
  (dry-run first; `prune why <item>` attributes a keep to a real bag). Only
  non-container storage (Porter Moogle slips, delivery box) is invisible — prune's
  output says so.
- Stored-but-owned gear shows red in the GUI with the holding container named;
  `gearcheck` warns when a trigger-referenced set needs unavailable gear.
- Any message or comment claiming a narrower scan is a bug (one round of stale prose
  already had to be corrected).
