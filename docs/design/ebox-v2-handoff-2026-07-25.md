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
- `/dl debug ebox` prints and reads correctly in game.

**Headless (3420 checks, both runtimes):** the whole model — believe/dirty/re-count, debit
arithmetic and its floor, refusal-repairs-vs-success-doesn't, the settle window, PEND_HOLD,
the party-line repair and its brakes, the menu rule and its burst coalescing, search
correlation, the yellow icon's divergence rule, the container pairings.

## 4. NOT verified — the next session's job

1. **Does dlac hear the `!box store` that TROVE queued?** Type `!box store` yourself, then click
   trove's Store All, and watch `/dl debug ebox` for both. If trove's does **not** register,
   `!box <item name>` withdrawals drift our count low silently, and the fallback is to add the
   tracked-item inventory heuristic back as a narrow safety net.
2. **The zero-packet promise.** `/dl debug ebox on`, then synth at a box for a few minutes with
   crystals tracked. Nothing should scroll. (An empty log is also what a dead instrument looks
   like — EBC23f/g pin that the instrument is alive, so an empty log is now real evidence.)
3. **Container counting against real inventory.** Track an ammo you hold a pouch for; the panel
   should read `have x99*` with the star's hover breaking it down. Never run against real bags.
4. **The nudge's three icons** — imgui is not headless-testable. Green fetch, yellow (needs
   tracked ammo in a Mog Case/Sack/Satchel while Inventory is short), and red arm-then-confirm.
   **Do not test red carelessly: `!box store` instantly deposits every storable item you carry.**
5. **Does the foreign-stream loop return?** If `dirty ... (a foreign 0x1A4 stream overlapped our
   answer)` reappears, the log now names the intruder: `foreign list ended: rows=N source=S`.
   That line is the evidence — bring it back.

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
- **`main` has none of this.** dev → main is Henrik's call.

## 7. Also uncommitted, unrelated

`.gitignore` has a `share/` rule in the working tree that **this session did not write** —
probably a parallel session (the checkout is shared). It was deliberately left out of these
commits.
