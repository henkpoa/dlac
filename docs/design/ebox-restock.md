# E-Box Restock — keeping the bags stocked from the Ephemeral Box

Status: **DESIGNED 2026-07-23** — grilled with Henrik (decisions R1–R11). Implementation pending. A CW-only sibling of AutoAmmo's E-Box section, but a different animal: AutoAmmo decides what sits in the *Ammo slot*; this tracks a player-authored list of consumables you want to keep on hand (food, oils, powders, tool stacks, job ammo), shows **On-hand vs Target**, and — on your click, never silently — withdraws the **Shortfall** from the Ephemeral Box, pre-clamped so it can never over-draw and lose items. A floating **Restock nudge** appears when you stand near a box with something worth fetching. Pure Addon-state UI + packet client: no dispatch/engine involvement, no gear, **no engine VERSION bump**.

**Scope guard (Henrik, R2b/R11):** 100% Crystal-Warrior-only. The Automations row is *hidden entirely* off-CW — not greyed, not peekable (unlike AutoIridescence's CW columns). The gate is `gamemode.get() == 'CW'` **affirmative only**; `nil`/`Wings`/`ACE` all hide it (the never-gate-on-nil rule: unknown = hidden). The server's `LOCKED` reply is the belt-and-braces second gate. The feature never fires a `/item`, never eats a consumable, and never withdraws without an explicit click — it *nudges*, you *click*.

## 0. Protocol grounding (verified in code)

Trust ladder: live game memory > the trove wire format below > nothing. The full 0x1A4 protocol lives in `trove/utils/packet.lua` + `trove/plugins/ebox.lua`; dlac already mirrors the *ammo slice* in `feature/eboxammo.lua`. Restock needs one C2S action eboxammo skipped — **SEARCH** (its add-picker) — plus `GET_CATEGORY` across arbitrary ahCats (eboxammo only ever fetches category 15). Everything is reimplemented in dlac with plain `string.byte`/byte-math (no `struct`, no `bit`) so every wire path runs headless — the eboxammo discipline, tests `EB*`/`EBR*`.

- **Packet** `0x1A4`, action byte at `@0x04`.
- **C2S** (`trove/utils/packet.lua` `C2S`): `WITHDRAW = 2`, `GET_SUMMARY = 4`, `GET_CATEGORY = 5`, `SEARCH = 6`.
- **S2C**: `CLEAR = 0`, `ITEM = 1`, `END_LIST = 2`, `ACK = 3`, `LOCKED = 4`, `SUMMARY = 5`.
- **GET_CATEGORY**: ahCat as `u8 @0x0A`. Streams `CLEAR` → N × `ITEM` → `END_LIST`. An **ITEM row** is `u16 id @0x08`, `u8 ahCat @0x0A`, `u32 qty @0x0C`, `zstr name @0x10 (31)`. `END_LIST` carries `source @0x05` (**0 = ebox**; others belong to helmwatch/trove) and totals `u16 viewTotal @0x08` / `u32 viewQty @0x0C`.
- **SEARCH**: query string via `writeString(p, 0x10, str, 31)`. Same `CLEAR`/`ITEM`/`END_LIST` stream, but server-capped (`viewTotal >= 20` ⇒ "first 20 matches, refine"). The ITEM row is where we learn a new item's **ahCat**.
- **WITHDRAW**: `u16 itemId @0x08`, `u32 qty @0x0C`. Server replies `ACK`: request action `@0x05`, success `@0x06` (1/0), server message `zstr @0x10 (31)` — shown verbatim on refusal (Rare/Ex over-draw, box drained mid-batch).
- **LOCKED**: reason `@0x05` (1 = not a Crystal Warrior, 2 = box not unlocked), message `@0x10`.
- **Batch withdraw** = trove's `crafting.lua executePrepare`: fire one `WITHDRAW` per pull, set `batchWithdrawCount = #pulls`, decrement on each `ACK`, refresh counts at zero.
- **Pending discipline** (helmwatch's rule): 0x1A4 is a party line. Stage `ITEM` rows only while *our* request is in flight; consume/`e.blocked` only what we asked for. Blocking matters — the retail client has no idea what 0x1A4 is — and Ashita still hands blocked events to every other addon, so nobody is starved.

## 1. Scope + nature

- **CW-only, row-hidden.** The Automations list row `E-Box Restock` is appended by `buildAutoRows` *only* when `hasGmode and gmode.get() == 'CW'`. Off-CW there is no row, no detail view, and no packet traffic.
- **Addon-state UI + packet client.** No `dlac:` set marker, no dispatch overlay, no manifest ladder, no `M.VERSION` bump. It reads bags + the box and writes a config file; that is all.
- **Nudge-and-click.** The only automatic thing is *counting the box while you stand next to one*. Withdrawing is always a click (nudge left-click, per-row **Fetch**, or **Fetch all**).
- **Never over-draws.** Every fetch is pre-clamped to `min(shortfall, in-box, room)` and split so it can never exceed free Inventory slots (§3). The E-Box does not protect you — the client must.

## 2. The model — two lists that work together (R3)

**Effective set on job J = Character ∪ Job(J).** Two tracked-item lists, edited on one panel:

- **Character list** — always-on staples that apply on *every* job: food, silent oil, prism powder, echo drops, the ninja tools you always carry.
- **Job list** — that job's unique needs, applied *only while on it*: RNG/COR ammo, DRG angons, a mage's ethers.

**Guidance** (Henrik): truly-universal → Character; job-specific → Job. There is **no per-item suppression** — you don't want arrows on WHM, so you put them in the RNG job list, not the Character list. Simpler than a matrix of "off on these jobs".

**Same item in both (R3b):** the **Job Target always overrides** the Character Target — specificity, exactly like Triggers. A Character `keep 12 Echo Drops` and an `RNG` `keep 30` resolve to 30 while on RNG. The panel shows the shadow: the job row reads **"(overrides baseline 12)"** beside its own Target.

**Storage (R3 / defaults):** one **per-character** file `<char>\dlac\restock.lua` (`profiles.dataDir() .. 'restock.lua'`, beside `autogear.lua` / `ammostate.lua`), a plain addon config — **OUT of Profiles** (a supply list is not gear; it does not clone or import with a Profile, and there is no cross-state engine consumer, so it is *not* a Statefile). Sections: a `character` array + a `jobs` map keyed by job (§8).

## 3. Counts + the slot-safety math (R4/R4b/R5b/R6)

**On-hand(id)** = the summed `Count` across the four **field bags** the game lets you consume from: **Inventory 0, Satchel 5, Sack 6, Case 7** (`feature/useitem.lua BAG_NAMES`; Henrik: "those are usable in the field" — *not* wardrobes, *not* Mog-House bags).

**Shortfall(id)** = `max(0, Target − On-hand)`.
**in-box(id)** = the shared category-counts cache (§6), `0` if the item's category was fetched and the id is absent, *unknown* until that category has been fetched near a box.
**stackSize(id)** = `AshitaCore:GetResourceManager():GetItemById(id).StackSize` (the equipmon/find recipe — no catalog dependency).

**THE slot rule (Henrik-confirmed Model A: per item AND per stack).** Drawing N units lands as N units *on arrival*, in **fresh Inventory slots**, even if they would auto-sort/merge into an existing partial stack a moment later. The box neither tracks nor cares about your space; too few slots ⇒ **lost items**. So a tracked item's fetch of `f` units costs `ceil(f / stackSize)` fresh **Inventory (container 0)** slots — and we **never** assume an existing partial stack absorbs any of it. *24 fire crystal at stack 12 = 2 slots.* Each item's `f` is then emitted as `ceil(f / stackSize)` `WITHDRAW` packets, each `≤ stackSize`.

**Room** = free Inventory(0) slots = `GetInventory():GetContainerCountMax(0)` − (slots with `GetContainerItem(0, i)` non-nil, `Id > 0`, `Count > 0`). Withdrawals are **assumed to land in Inventory(0)** — so Inventory is the only bag whose free slots gate a fetch, *not* the other field bags (needs one field test; §11).

**Budget across the batch, greedy partial, Job list first (R6).** Given `R` free slots, walk the effective list **Job entries top-to-bottom, then Character entries** (order is not critical — Henrik):

```
plan(effectiveList, R):
  fetches, remainder = {}, {}
  for e in effectiveList:                    -- job entries first, then character
    s     = stackOf(e.id)
    want  = min( max(0, e.target - onHand(e.id)), inBox(e.id) )
    if want <= 0: continue
    fetch = min(want, R * s)                  -- whole stacks until Inventory is full
    if fetch <= 0: remainder += {e.id, want}; continue
    slots = ceil(fetch / s)                   -- <= R by construction: never over-draws
    R    -= slots
    fetches  += {e.id, qty=fetch, slots, packets = ceil(fetch/s) WITHDRAWs <= s each}
    if fetch < want: remainder += {e.id, want - fetch}
  return fetches, remainder, R
```

`fetch = min(want, R*s)` is Henrik's "space for 2 ⇒ fetch 2" at stack granularity: with one free slot and stack 12 you fetch one stack and **report the remainder** rather than dropping the overflow on the floor. A single item may be partially filled. Auto-sort after a fetch usually frees slots, so the remainder is rarely permanent — the panel keeps showing the shortfall for a re-click (auto-sort-then-fetch-remainder is a possible later nicety; §11).

Worked example — near a box, 3 free Inventory slots:

| Item | Target | On-hand | Shortfall | in-box | stack | want | fetch | slots | remainder |
|---|---|---|---|---|---|---|---|---|---|
| Fire Crystal | 24 | 0 | 24 | 40 | 12 | 24 | 24 | 2 | 0 |
| Sole Sushi +1 | 12 | 4 | 8 | 12 | 12 | 8 | 8 | 1 | 0 |
| Silent Oil | 24 | 0 | 24 | 99 | 12 | 24 | 0 | — | 24 |

Slots exhausted after the first two (2 + 1 = 3); Silent Oil is deferred and reported. Re-click after auto-sort.

## 4. The Restock nudge (R8/R9)

A small floating icon (the wicker-box item icon 43, the icon trove uses) that appears **near a box** and reuses the `ui/floatgear.lua` pattern: chromeless (`NoTitleBar`/`NoBackground`/`AlwaysAutoResize`), rendered directly from gearui's `d3d_present` (not the `drawWindow` window contract — it must stay up while you play), Shift/keyless-drag move, position remembered + settle-persisted (`ui._*Pos` / `_*MovedAt`).

- **Near** = `eboxclient.boxDistance() ~= nil and <= BOX_RANGE` (entwatch "Ephemeral Box", `BOX_RANGE = 5` — field-pinned).
- **Hover** = the exact fetch plan tooltip: each item and the count it will pull (`fetches` from §3), plus a `free N slots` line and any deferred `remainder`.
- **LEFT-click** = execute that plan (Fetch all, pre-clamped — it cannot over-draw or lose items).
- **RIGHT-click** = open the panel (queues `/dl restock`, landing on the E-Box Restock detail view).
- **Badge** = the number of tracked items with a **box-fillable shortfall** (below target AND `in-box ≥ 1`).

**Two settings** (both stored in `restock.lua`):

1. **Show restock nudge** — default **ON**.
2. **Only when needed** — default **ON**. "needed" = at least one tracked item below target AND box holds `≥ 1` — **space-independent**: the nudge shows even when Inventory is full, its tooltip reading `free N slots` (space only limits how much a click fetches, never whether the nudge appears — R9). With this OFF, the nudge shows near *any* box, greyed when there is nothing to fetch.

**Data cadence** (the whole nudge lights off the shared cache, §6): counts are pulled **only while near a box**, per-category, **one request in flight**, on a **~20–30 s stale window**, with a **~1 s settle** after the first commit before the nudge lights (no flicker on walk-up).

## 5. Add flow (R7)

Adding a tracked item **searches the box** — you can only add what the box actually holds, which also hands us the ahCat for free:

- The per-section **+ Add** control opens a search box, **near-box only** (SEARCH is meaningless away from a box). Typing is **debounced ~0.3 s** (trove's `searchDebounce.delay`), one SEARCH in flight, results are box-contents-only (server-capped at ~20 — "refine to see more").
- Picking a result stores `{ id, name, ahCat, stack, target }` into the current section. **ahCat comes from the SEARCH ITEM row `@0x0A`** so later counts can be gathered per-category (§6); `stack` from `GetItemById(id).StackSize`.
- **New-item default Target = one full stack** (`stackSize`), editable inline.
- **Rare/Ex** items are allowed but Target effectively caps at 1 (the server refuses a 2nd — its `ACK` message is shown, not second-guessed client-side).

## 6. Architecture + the hard server-load NFR (R1b/R7b/R10)

**Exactly one 0x1A4 client: `feature/eboxclient.lua`.** It owns the whole protocol (GET_SUMMARY/SUMMARY, GET_CATEGORY, SEARCH, WITHDRAW + ACK, LOCKED, CLEAR/ITEM/END_LIST), a **shared multi-category counts cache**, entwatch proximity, and the throttle. Both AutoAmmo's E-Box section **and** E-Box Restock become thin consumers.

**`feature/eboxammo.lua` is REFACTORED into a thin consumer** — identical shipped behaviour (AutoAmmo is field-confirmed; the refactor must be invisible to it). Its public surface (`counts`, `refresh`/`refreshIfStale`, `withdraw`, `boxDistance`, `isCW`, `rescan`, the `/dl ebox` diag) is preserved, delegating to eboxclient for the wire, the cache (category 15), proximity, and the throttle. Guard: the existing `EB*` headless tests stay green, plus **new parity tests**; Henrik **field-tests AutoAmmo first** before this is called done.

**The hard NFR (Henrik — server operators care): do not flood 0x1A4 with auto-queries.** Met by the shared client, not by each consumer:

- **One request in flight** at a time; generous **~20–30 s** stale windows before re-requesting a category.
- **Near-box-only** — the entwatch proximity gate makes an away-from-box addon free (idle = zero packets).
- **Per-category, not per-item** — counts via `GET_CATEGORY` over the **distinct ahCats** of the tracked items (a few requests), never SEARCH-per-item.
- **Coalesced between consumers** — one flat `counts[id] = qty` view plus per-ahCat freshness stamps. AutoAmmo's category **15 (Ammunition)** is fetched **once** and read by both AutoAmmo and Restock.
- **Debounced SEARCH** (~0.3 s), only while the add-picker is open.
- A **global min-gap** between any two outgoing 0x1A4 requests (a rate cap over the whole client).

Withdrawals are a separate channel: user-initiated, bounded (`ceil(fetch/stack)` packets per item, budgeted across the batch), fired as one `executePrepare`-style burst and ACK-counted — not the auto-query path the min-gap governs. `master = false` ⇒ Restock issues **zero** queries (AutoAmmo may still fetch category 15 for its own needs — that is AutoAmmo's business, not Restock's).

Companion decision record: **ADR 0016 — one E-Box client** (single 0x1A4 owner; eboxammo refactored onto it).

## 7. UI — Automations → "E-Box Restock" (`ui/restockui.lua`)

New CW-gated row in `buildAutoRows` (key `restock`, appended by-key so index-reads stay stable), detail delegated to `ui/restockui.lua` on the helm/ammo contract: **`render(deps, availW)` / `status(deps)` / `maxLevel`**. `status(deps)` returns `level, txt` for the shared ramp (`levelColor`): green when every tracked item is at/above Target, reddening as **box-fillable** shortfalls grow (a shortfall the box cannot fill is not actionable and does not alarm). Detail arm added to `renderAutomations` (`auto.view == 'restock'` → pcall-require `restockui.render`).

Layout, top to bottom:

- **Master ON/OFF** — OFF ⇒ the panel is **fully dark and issues zero queries** (and the nudge never shows).
- **The two nudge settings** (Show restock nudge; Only when needed).
- **Proximity line + Rescan** — the eboxammo idiom: "in range / too far / no box in sight" + a Rescan button (entwatch `poke` + count re-request).
- **Two sections** — **"Always (every job)"** (Character list) and **"`<JOB>` only"** (Job list), sharing **fixed-offset columns**: `[ icon · name · on-hand · in-box · Target(input) · Fetch · ✕ ]`. **On-hand is RED below Target.** A job row shadowing a character entry shows **"(overrides baseline N)"**.
- **Per-row Fetch** = top-up-to-Target (one button; Target *is* the "up to", box-and-room-clamped; dead when nothing to fetch / not near a box / busy, reason in the tooltip).
- **Per-section + Add** — the box-search picker (§5), near-box only.
- **[Fetch all]** — runs the §3 plan across the effective list.
- **Slot-safety footer** — one live line: `free N Inventory slots · this Fetch all pulls M items (K slots); P deferred` — the plain-language "why it stopped".

## 8. Data — `<char>\dlac\restock.lua`

Written whole-file, pcall'd (the ammowatch/fishwatch pattern); a torn read falls back to empty rather than throwing.

```lua
return {
  fmt            = 1,
  master         = true,
  showNudge      = true,
  onlyWhenNeeded = true,
  -- Always-on staples (every job). id/name/ahCat/stack learned at add-time
  -- from the SEARCH ITEM row; target defaults to one full stack, editable.
  character = {
    { id = 4372, name = 'Sole Sushi +1', ahCat = 6,  stack = 12, target = 12 },
    { id = 4148, name = 'Echo Drops',    ahCat = 8,  stack = 12, target = 12 },
    { id = 1020, name = 'Silent Oil',    ahCat = 8,  stack = 12, target = 24 },
  },
  -- Job-specific needs, applied only while on that job. A same-id entry here
  -- OVERRIDES the character target (specificity); shown as "(overrides baseline N)".
  jobs = {
    RNG = {
      { id = 18700, name = 'Fire Arrow',  ahCat = 15, stack = 99, target = 99 },
      { id = 4148,  name = 'Echo Drops',  ahCat = 8,  stack = 12, target = 30 },
    },
  },
}
```

(`ahCat` values above are illustrative — 15 = Ammunition is the one pinned constant; the rest are learned live.)

## 9. Modules

| File | Role |
|---|---|
| `feature/eboxclient.lua` | THE one 0x1A4 client: GET_SUMMARY/SUMMARY / GET_CATEGORY / SEARCH / WITHDRAW+ACK / LOCKED, shared multi-category counts cache (flat `counts[id]` + per-ahCat stamps), entwatch proximity (`boxDistance`, `BOX_RANGE = 5`), throttle (one-in-flight, global min-gap, stale windows), `executePrepare`-style batch withdraw + ACK count; seams `_onPacket`/`_beginStream`/`_clampQty` (headless `EB*`) |
| `feature/restockwatch.lua` | config load/save (`master`/`showNudge`/`onlyWhenNeeded`/`character`/`jobs`); the **pure** effective-list union+override and the **pure** slot-budget planner (`plan(list, R)`, §3) — headless `RS*`/`EBR*`; test seams `_saveState`/`_setDeps` |
| `ui/restockui.lua` | Automations detail view (`render`/`status`/`maxLevel`) **and** the floating **Restock nudge** (floatgear pattern); owned counts via the field-bag scan, in-box via eboxclient, box-search add-picker |
| `ui/automationsui.lua` | +1 CW-gated row (built only when `gmode.get() == 'CW'`) + detail-dispatch arm (pcall-require) + `openDetail('restock')` |
| `feature/eboxammo.lua` | REFACTORED to a thin eboxclient consumer — identical AutoAmmo behaviour, guarded by `EB*` + new parity tests |
| `tests/run_tests.lua` | new `RS`/`EBR` sections (planner, union/override, slot budget, greedy partial); eboxclient parity + `EB*` unchanged |
| `docs/design/ebox-restock.md` · `ADR 0016` · `CONTEXT.md` | this file · one-ebox-client · E-Box Restock glossary (E-Box entry already added) |

Command: `/dl restock` opens the panel on this detail view (the hidden `/dl ebox` diag stays, now eboxclient-backed, dumping both consumers).

## 10. Field tests

1. **CW-invisible off-CW.** Non-CW char (Wings/ACE/unknown): no `E-Box Restock` row, no detail, no nudge, zero 0x1A4 traffic. A `LOCKED` reason 1 mid-session re-hides.
2. **Slot-loss safety, near-full Inventory.** Inventory with 1 free slot, a tracked item needing 24 (stack 12) with 40 in box: **Fetch all** pulls exactly 12 (one stack, one slot), stops, reports 12 deferred — nothing is lost, no `ACK` refusal.
3. **Greedy partial + Job-first.** Multiple below-target items, 3 free slots: the current job's list fills before the Character list, top-to-bottom; the footer/tooltip name the deferred remainder; a re-click after auto-sort pulls the rest.
4. **Job overrides baseline.** Same item in Character (12) and current-job list (30): the panel shows "(overrides baseline 12)", On-hand reds below 30, and Fetch tops up to 30.
5. **Nudge trigger + hover + left-click.** Walk to a box: nudge lights ~1 s after counts settle; hover shows `item x count` + `free N slots`; left-click fetches the plan; badge = # box-fillable shortfalls. "Only when needed" OFF shows the nudge (greyed) with nothing to fetch.
6. **Add flow.** Near a box, + Add search returns box-contents only, debounced; picking stores ahCat + stack; default Target = one full stack; away from a box the picker refuses.
7. **AutoAmmo E-Box parity after the refactor.** Every AutoAmmo E-Box behaviour (counts, Fetch, Fetch-up-to, proximity, refusal message, `/dl ebox`) is byte-for-byte unchanged — category 15 is fetched once and read by both.
8. **Landing bag.** Confirm withdrawals arrive in **Inventory (0)** — the assumption the room gate rests on.
9. **Rare/Ex.** Target on a Rare item caps behaviour at 1; a 2nd draw surfaces the server's own `ACK` message.

## 11. Open questions

- **Landing bag = Inventory(0)** — assumed (room gate = free Inventory slots only), promoted by field test 8. If withdrawals can spill to other field bags, the budget widens.
- **Hand-edited config row lacking `ahCat`** — lazily re-learned: a near-box SEARCH by name recovers the ahCat before the first count for that item.
- **Auto-sort-then-fetch-remainder** — after a partial fill, wait for the client auto-sort to free slots, then fetch the deferred remainder in a second pass. A future nicety; today the panel just keeps the shortfall visible for a re-click.
- **Nudge nag-threshold for tiny shortfalls** — should a shortfall of 1–2 units light the nudge, or only proportionally-large gaps? Deferred; today any box-fillable shortfall counts toward the badge.
