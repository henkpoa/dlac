# 0010 — Trinket ammo and ranged weapons cannot coexist (keep the higher-Level one)

A stat-stick ammo (Cinderstone, Morion Tathlum, Coiste Bodhar, pet food — an Ammo-slot item that
carries stats but **no `AmmoType`**, so it fires nothing) could not stay equipped alongside a bow /
crossbow / gun: the two **flapped** (the client equips the weapon, the server strips it, the client
re-equips, forever).

## Why it flaps — it's the server

`RSlot = 4` (the Range bit) is the server's real `item_equipment.rslot`, stamped on the **entire
throwing-ammo class — 135 catalog items** (Morion, all pet food, tathlums, pebbles, bomb arms). When
such ammo is worn, the **server clears the Range slot**. `dispatch.reservedDrops` was built to mirror
exactly this — "the only stable state." The bug was never that they *should* coexist (the server
forbids it) but that the mirror was **incomplete**: the crawl left `RSlot` off a few stat sticks
(Cinderstone, Coiste Bodhar, Talon Tathlum — genuine gaps in an otherwise-systematic column), so
those weren't dropped and flapped forever.

> An earlier revision of this ADR wrongly read those gaps as evidence the reservation was a "data
> artifact" and tried to make trinkets *coexist* with ranged weapons — which removed the mirror and
> made the **whole** class flap ("flapping back and forth, no difference with Morion"). That was
> backwards and is reverted. The reservation is real; the fix is to complete the mirror.

## Decision

**A trinket and a ranged weapon can't coexist; keep the HIGHER-LEVEL of the two, drop the other.**

- **Complete the category (`gearimport.effectiveRSlot`).** A trinket is `Type='Ammo'` with no
  `AmmoType`. When gear.lua's RSlot is decided — the fresh write **and** the `/dl fix` backfill — a
  trinket missing its RSlot gets the **Range bit** stamped, so the *whole* class is marked, gaps
  included. Fired ammo (which carries an `AmmoType`) is never stamped, so a bow + arrows still
  coexist.
- **Resolve by Level, not by a fixed slot (`dispatch.trinketRangeDrop`).** At equip time, when a
  marked trinket and a ranged weapon are both resolved, the engine keeps the **higher-Level** one
  and drops the other (Henrik's ruling — keep the "best," with Level as the proxy). It runs *before*
  the reserved-slot pass, so the loser can't reserve anything and the result is deterministic — it
  settles instead of flapping. Tie → keep the trinket (matches the server's own resolution).
- The optimizer (`pickRangeAmmo`) is unchanged — it already leaves Range empty when a trinket wins
  the Ammo slot, so Auto-build never proposes the illegal pair.

## Consequences

- No coexistence (the server forbids it) — but a clean, stable result and no flap for the whole
  trinket category, keeping whichever piece is higher Level.
- Players must **re-commit their sets or run `/dl fix`** once, so the gap trinkets pick up the
  completed RSlot in their `gear.lua`.
- The catalog gaps (Cinderstone / Coiste Bodhar / Talon Tathlum missing `RSlot=4`) are worth a
  crawler cleanup, but `effectiveRSlot` makes dlac correct regardless.
- Tests: `run_tests.lua` TR0–TR10. `dispatch.M.VERSION` → 52 (needs a Reload LAC).
