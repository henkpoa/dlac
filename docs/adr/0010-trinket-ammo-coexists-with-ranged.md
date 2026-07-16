# 0010 — Trinket ammo coexists with ranged weapons

A stat-stick ammo (Cinderstone, Morion Tathlum, Coiste Bodhar, pet food — an Ammo-slot item
that carries stats but **no `AmmoType`**, so it fires nothing) could not stay equipped
alongside a bow / crossbow / gun in the Range slot. Two independent mechanisms evicted one or
the other, and they hit *different* items:

- **Equip engine (`dispatch.reservedDrops`).** Morion Tathlum carries `RSlot = 4` (the Range
  bit) in the catalog, so the engine treated the stat stick as *reserving* the Range slot and
  dropped the bow the instant the set landed. Its identical siblings (Cinderstone, Coiste
  Bodhar) carry no RSlot — proof that `RSlot = 4` on Morion is a **data artifact**, not a real
  "stat sticks block Range" rule (in retail a bow + stat stick coexist).
- **Optimizer (`gearoptim.pickRangeAmmo`).** Range and Ammo are picked jointly; a trinket has
  no `AmmoType`, so the joint pick forced Range **empty** whenever a trinket won the Ammo slot.
  This was a deliberate workaround for a server bug (see `docs/server-questions.md` #5:
  `GetRangedWeaponDelay` adds the stick's delay 999 to ranged TP with no compatibility check).

## Decision

**A trinket ammo coexists with any non-Throwing ranged weapon**, everywhere.

- **Engine:** an Ammo-slot item **never reserves the Range slot** (`reservedDrops` refuses the
  `Ammo → Range` direction). A `Range → Ammo` reservation (a Throwing boomerang, `RSlot = Ammo`)
  is still honored — that one is real. The test is slot-based, because the engine has no catalog
  and cannot see `AmmoType`.
- **Optimizer:** the stat-stick branch now pairs the trinket with the **best non-Throwing Range
  weapon** instead of forcing Range empty. Throwing ammo still empties Range (the server shadows
  it); fired ammo with no owned weapon of its type still leaves Range empty. A Throwing *weapon*
  (boomerang) reserves the Ammo slot and so is never paired with a stat stick.

## Consequences

- The server ranged-delay bug (#5) is **unchanged** — but it only costs TP if the pair is
  actually **fired**, which a stat-stick (melee / idle) set never does. Exposing the pair is the
  right trade for the far more common "I want the stick's stats and my bow's stats together."
- `docs/server-questions.md` #5's *"what dlac does meanwhile"* is updated: dlac no longer avoids
  the pair. If the server team later adds the compatibility check, nothing here regresses.
- The Morion Tathlum `RSlot = 4` catalog value should be corrected to `0` on the next crawl (a
  crawler-side cleanup); the engine guard makes dlac correct regardless of the data.
- Tests: `run_tests.lua` H9–H15 (optimizer coexistence + the Throwing-weapon exclusion) and
  AK13b (engine: an Ammo item never reserves Range). `dispatch.M.VERSION` → 52.
