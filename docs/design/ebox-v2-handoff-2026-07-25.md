# E-Box Restock v2 — handoff (2026-07-25 evening)

**Pick this up here.** Built, **partly field-tested**, on `main` since the `7231143` merge.
`addon.version 2026.07.25e`. 3420 checks green on Windows lua **and** WSL lua5.4.

- The design + the whole decision record: **`docs/design/ebox-restock-v2-grill-2026-07-25.md`**
  — read it before changing anything here. It carries the nine locked decisions, the three
  adversarial review rounds (12 defects), and the two field rounds.
- Memory: `[[ebox-v2-arithmetic-model]]`, which supersedes nothing in `[[ebox-restock-design]]`
  (that one is v1, shipped 07-24).

---

## 1. What this changed, in one paragraph

E-Box Restock used to poll the box: every 25s, and again on every inventory event. Crafting at
an Ephemeral Box — which is *the* place you craft, since the Ephemeral Moogles are the crafting
moogles — cost 200-300 packets a session, every one of them re-learning a number that had not
changed. **The box's contents are now a number we already know**: verified once on approach,
**debited locally** when we send a withdraw, and re-counted only when something we could not
compute changed it. Crafting at a box now costs **zero**.

## 2. What shipped

| File | What |
|---|---|
| `feature/eboxclient.lua` | The arithmetic model, the dirty marks, the menu rule, the party-line repair, the traffic trace |
| `feature/restockwatch.lua` | `otherBagNeed` — the yellow icon's pure question (**renamed `homeStockNeed` on 07-28**, see the grill's C2 revision: the icon asks about the Mog House, not the other field bags) |
| `feature/eboxtrace.lua` **(new)** | The `/dl debug ebox` readout |
| `feature/debug.lua` | New `ebox` topic (alias `box`) — **and a prefix fix, see §5** |
| `ui/restockui.lua` | Search button, panel rework, the 3-icon nudge, container-aware on-hand |
| `data/ammocontainers.lua` **(new)** | 62 quiver/pouch → ammo pairings |
| `tests/run_tests.lua` | EBC11-26, EBT1-8, RS9-9f, AC1-6d, DBT2b-2h |

**The generator `tools/gen_ammocontainers.py` is NOT in the repo** — `tools/` is gitignored by
project rule, same as `gen_zones.py` and the rest. It lives on Henrik's disk and reads the
server clone at `~\scripts\catseyexi`. Re-run it if CatsEye adds ammo:
`python tools/gen_ammocontainers.py`.

## 3. VERIFIED — do not re-litigate

**In the field (Henrik, 07-25 evening):**
- The `!box` watch fires and **there is no spam**.
- The menu rule works end to end: `!box ammo` at `18:47:05` → armed → **silent for the eight
  seconds he browsed** → fired only when items actually moved at `18:47:13`.
- ~~`/dl debug ebox` prints and reads correctly in game.~~ **WITHDRAWN 07-28 — this was a false
  positive, see §5.** It printed the *empty-ring* line; the first time it had an event to
  format it threw and Ashita unloaded the addon. Fixed in `2026.07.28s`; **still owed a real
  field round with traffic in the ring.**

**Headless (3420 checks, both runtimes):** the whole model — believe/dirty/re-count, debit
arithmetic and its floor, refusal-repairs-vs-success-doesn't, the settle window, PEND_HOLD,
the party-line repair and its brakes, the menu rule and its burst coalescing, search
correlation, the yellow icon's divergence rule, the container pairings.

## 4. FIELD ROUND 2 (Henrik, 2026-07-28, on `2026.07.28s`) — 3 of 5 closed

1. ~~**Does dlac hear the `!box store` that TROVE queued?**~~ **CONFIRMED — yes, we saw it.**
   Cross-addon `command` visibility is real, so the `!box` prefix watch covers trove's four
   commands as designed. **The fallback is dead:** the tracked-item inventory heuristic is not
   needed and must not be re-added — `!box <item name>` withdrawals cannot drift us low.
2. ~~**The zero-packet promise.**~~ **CONFIRMED — the design's central claim holds.** Henrik
   tracked Wind Crystal and synthed at a box: **no packets.** This is the one that justified the
   whole v2 rewrite, and it is now measured rather than argued — with a *live* instrument
   (§5's `at`/`when` fix), so the empty log is real evidence and not a dead readout.
3. **Container counting — STILL OPEN, and it needs an ammo item.** Round 2 ran against Wind
   Crystal, which has no quiver or pouch, so the `have x99*` star and its breakdown were never
   exercised. Needs a tracked ammo you hold a quiver/pouch for. **But it surfaced a bigger
   hole — see §4b, clusters.**
4. ~~**The nudge's three icons.**~~ **CONFIRMED, including the 07-28 Mog House ruling.** Henrik:
   *"properly tested and works, it will clearly state if any item is in a non field-container and
   where, and let you draw extra if you want."* The C2 revision is field-good.
5. **The foreign-stream loop — INCONCLUSIVE, needs the actual numbers.** Henrik sees
   `foreign list ended: rows=N source=S` lines. **That line alone is the instrument working**,
   not the bug: it fires whenever trove or an open box menu talks on 0x1A4 while we have nothing
   pending. The *loop* symptom is `dirty cat=N (a foreign 0x1A4 stream overlapped our answer)`
   at ~1/s. Owed: the literal lines. `rows=0` is the dangerous shape (a zero-match search, the
   E-review-2 case); and **`source` matters because the code is asymmetric** — the commit path
   requires `source == 0` (`eboxclient.lua:757`, "source 0 = ebox") but the foreign-repair path
   (`:702-713`, `:750-752`) triggers on **any** source. If the field lines show `source ~= 0`
   we are repairing against traffic that was never the box.

### 4b. NEW — `!box cluster` is the quiver hole again, for crystals (found 07-28, NOT built)
`data/ammocontainers.lua` covers quivers and pouches only. **Clusters are the same trick and
are not in it**, verified in the server clone: `scripts/items/wind_cluster.lua` (ID 4106) is
`onItemUse → npcUtil.giveItem(target, { { xi.item.WIND_CRYSTAL, 12 } })` — byte-for-byte the
shape `gen_ammocontainers.py` already parses. Eight elemental clusters, **ids 4104-4111**
(fire 4104, ice 4105, wind 4106, earth 4107, lightning 4108, water 4109, light 4110, dark 4111),
each worth **12** of its crystal.

**Why it bites exactly the user we have:** `!box cluster` is one of trove's four commands and one
of the box's own subcommands, Henrik tracks Wind Crystal, and a cluster is invisible to the
on-hand scan — so Restock keeps offering to fetch crystals he is already carrying 12×N of. Same
defect as F3, same fix as G1, same counting rule (a cluster counts toward *"do I have enough"*
but **never** toward *"is it in my Inventory"* — you cannot synth with a cluster any more than
you can shoot a quiver; you must break it first).

Mechanical, if Henrik wants it: extend the generator's glob to `*_cluster.lua` / `cluster_of_*.lua`,
keep every existing rule (single-`giveItem` only, key off `item_basic.sql`, refuse duplicate ids).
The existing skip logic already handles the non-elemental strays correctly — `cluster_of_paprika`
is a food (`addStatusEffect`, no `giveItem`) and is dropped; `cluster_of_bitter_memories` is a
true 12-pack and would be picked up, which is harmless and arguably right. Open naming question:
the data file is called `ammocontainers` and would no longer be about ammo.

## 5. Landmines for whoever picks this up

- **`/dl debug <topic>` was unreachable from `/dl` for its whole life.** The router matched
  `'^/dlac?%s+debug'`, and `c?` makes the *C* optional — the literal prefix was `/dla`. Fixed
  (`M._afterDebug`, DBT2c-2h). A handler that never fires is indistinguishable from a command
  that does nothing; three rounds of agent review missed it because they all called the
  functions directly instead of typing the command.
- **0x1A4 is a party line with NO request id.** trove speaks the same protocol on the same
  opcode. A foreign stream landing while our GET_CATEGORY is out is consumed as our answer. It
  **cannot be prevented** — only made self-correcting. Any future 0x1A4 work must assume someone
  else is talking.
- **A `!box ...` command does not change the box** — it opens a *menu*, and an open menu streams
  0x1A4 lists of its own. We arm and wait for inventory movement as proof, and stay off the wire
  while armed.
- **`!box ammo` returns CONTAINERS, not ammo.** Blind Bolt → Blind Bolt Quiver (99 each, stack
  12 = 1188 per Inventory slot). Arrows *drop* the word ("Beetle Arrow" → "Beetle Quiver");
  bullets use pouches. Never string-match this — use `data/ammocontainers.lua`.
- **Key ammo containers off `sql/item_basic.sql`, not the scripts' `-- ID:` headers**:
  `oberon_bullet_pouch.lua` repeats dweomer's id (5822 vs the real 5823), which silently dropped
  a row from the generated table.
- **A local declared after its use is a nil GLOBAL, silently** — `M.rescan` read `_ewok`/`_ew`
  that way for its whole life, so Rescan's box re-sweep never ran. EBC22 pins it as a
  source-order check because nothing at runtime can see it.
- **A green suite on both sides of a seam does not mean the seam is joined (07-28, cost: the
  addon).** `eboxclient._trace` wrote `{ when = … }` from its first commit; `eboxtrace.lines`
  read `e.at`. `/dl debug ebox` therefore threw `arithmetic on field 'at' (a nil value)` and
  **Ashita unloaded dlac** — asking a question about traffic cost the player every dlac
  feature. It hid for three days behind two green halves that never touched: EBT3-8 format a
  *hand-built* stand-in that spells the field the formatter's way, and EBC23f/g drive the real
  trace calls but only ever inspect `dir`/`what`. Nothing handed the real ring to the real
  formatter. It then survived the 07-25 field round because the ring was **empty** — the
  `#tr == 0` branch is the one path that never touches a timestamp, which is E-review-3's own
  warning ("an empty log is what a dead instrument looks like") landing on the instrument
  itself. **EBT9/EBT9b now format the live ring left by EBC23f/g** (mutation-verified: put
  `when` back and exactly those two fail). And `/dl debug`'s router now `pcall`s the topic —
  a read-only readout must never be able to unload the addon.
- **Deleting a refresh cycle deletes what was quietly healing things.** Four of the five
  round-one review defects were transient wrong beliefs that the 25s poll used to age out and
  now never would. When you remove a poll, audit everything that was leaning on it.

## 6. Still open

- **Yellow icon option (b)** — MOVING items Mog Case → Inventory instead of buying more from the
  box. Better design (zero box stock, composes with green to land exactly `target`), blocked on
  dlac being allowed to move items between containers. **Wire format already known, do not
  re-research:** `dlacprobe.lua:1238-1258` decodes OUT `0x029` from a real capture
  (`qty u32 @0x04, from @0x08, to @0x09, fromSlot @0x0A, toSlot @0x0B`; success = 2× `0x020` +
  `0x01D`). Open question for that day: does a moved partial stack merge into an existing
  Inventory stack, or take a fresh slot the way box withdrawals do?
- **Opening a quiver from the panel.** We can count containers now but not open them; `!box ammo`
  fills your bags with quivers and the only way to use one is manually. `feature/useitem` exists
  and is the obvious seam. Not designed, not asked for — Henrik's call.
- **Deposit is still WITHDRAW-ONLY at the packet level** (server-ask #7 in
  `docs/server-questions.md`). The red icon is a `!box store` chat command, not a packet.
- ~~**`main` has none of this.**~~ **STALE — all of it is on `main`** (promoted in `7231143`,
  07-25), as are the two 07-28 rulings (`ef82f1f`) and the yellow-hover trim. `dev` and `main`
  are level.

## 7. ~~Also uncommitted, unrelated~~ — resolved

The stray `.gitignore` `share/` rule from a parallel session is gone; the tree is clean.
