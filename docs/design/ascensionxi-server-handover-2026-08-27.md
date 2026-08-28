# Handover — what the AscensionXI server repo owes, to finish the Gear Vault

**Written:** 2026-08-27, from the dlac side.
**For:** the long-standing WIP PR on the AscensionXI repo (branch `henrik/wardrobe-lock`,
carrying `b25a572924`) and the pack generator.
**Scope note:** this is written from what dlac knows and depends on. I cannot see the
AscensionXI repo from this checkout, so everything about *its* branch state comes from
dlac's own records (`docs/HANDOFF.md`, `docs/history.md`) and may be behind. Treat the
"what dlac needs" sections as authoritative and the "what I believe is on the branch"
sections as a prompt to check.

---

## TL;DR — three things, in order

1. **Land the wardrobe lock (#107).** dlac's whole slice-4 space-pressure system is built,
   green and shipped, and is **unreachable in the field** because the shelf reports 640
   slots. Nothing else on either side is blocked on anything.
2. **Answer one integration question before merging it:** *how does the lock become visible
   to the client?* If it does not shrink `GetContainerCountMax` on wardrobes 1–8, dlac
   cannot see it and the feature stays dark even after the PR merges. See §2.
3. **Fix `tools/dlac-pack/gen_pack.py`** — it emits `modules = {}`, which silently deletes
   the entire Gear Vault module from the generated pack. Caught today. See §4.

---

## 1. What is already proven, so nobody re-litigates it

The full loop is **field-confirmed end-to-end** by Henrik on 2026-08-26, across ~a dozen
same-day rounds: *loot → Store → derivation → layout → shelf → a trigger dresses you.*

- dlac client: `2026.08.27i`, pack `ascensionxi`, module
  `servers/ascensionxi/modules/gearvault/` (6 files). Suites green: run_tests 7338,
  smoke_ui 1455.
- Server: `b25a572924` on `henrik/wardrobe-lock` — *a deposit the active layout names
  applies ON THE SPOT*. That commit is the missing quarter of "auto sets to and from"; it
  was found by three field reports in one session and it works. **It is proven code sitting
  on an unmerged branch.**
- All four dlac slices are done, including slice 4 (LRU usage stamps, the two behaviour
  settings, ask/auto pressure flows, `[wanted]` tags and *Store wanted*).

So: the PR is not "work in progress" in the sense of unfinished code. It is finished code
waiting on one server capability and a merge.

---

## 2. THE BLOCKER — the wardrobe lock, and the one question that must be answered first

### Why it blocks

dlac decides shelf pressure by comparing the derived layout against **live wardrobe
capacity**. That capacity is read client-side
(`servers/ascensionxi/modules/gearvault/init.lua`, `capacity()`):

```lua
for _, cid in ipairs({ 8, 10, 11, 12, 13, 14, 15, 16 }) do   -- wardrobes 1-8 (9 = Mog Safe 2)
    cap = cap + (inv:GetContainerCountMax(cid) or 0);
end
```

Today that sums to **640** (8 × 80). A derived layout never approaches 640 units, so
`over > 0` is never true, the pressure verdict never fires, and every removal flow — the
marking dialog, the LRU auto-evict, the pinned-permission prompt — is dead code in the
field. The machinery is correct and headless-tested; it simply has no way to trigger.

### The question for the server team

> **When the wardrobe lock is active, does `GetContainerCountMax` on containers 8 and
> 10–16 report the reduced number to the client?**

- **If yes:** nothing more is needed. dlac picks it up on the next beat with no client
  change — `reconcile.lua` deliberately re-evaluates pressure *before* its
  derivation-unchanged early-out, precisely because "capacity can move on its own". Merge
  and go to §3.
- **If no** (the lock is enforced server-side on the swap engine while the client still
  sees 80/container): **dlac is blind and the feature stays dark after merge.** In that
  case the shelf figure has to come over the wire, and the cheapest place is the HELLO
  reply — see below.

### If it has to come over the wire (the cheap route)

`HELLO 0x40`'s S2C payload today:

```
u16 ServerProto; u16 Rsvd; u32 VaultCount; u8 MaxList; u8 MaxDeposit; u8 MaxWithdraw; u8 Rsvd
```

Two facts that make this nearly free:

- **`u16 Rsvd` at offset 2 is unread by dlac.** `parseHello` reads offset 0 and offset 4+;
  bytes 2–3 are ignored today. Putting `u16 ShelfCapacity` there costs **zero** frame-size
  change and zero protocol bump.
- **`parseHello` guards `#payload < 12`, not `== 12`.** A *longer* HELLO payload is
  accepted and its tail ignored, so appending a field is also forward-compatible with every
  dlac already in the field.

Either shape works. Say which you pick and dlac adds the read in one commit — a few lines
in `parseHello` plus `capacity()` preferring the wire figure over the container sum. No
protocol version bump on our side.

### How it can be tested before the lock exists

`/dl vault cap <n>` overrides the shelf capacity for one session (`0` clears it). That is
how the pressure flows were exercised at all — it fakes a small shelf client-side. Useful
for demoing the flows in the PR, **not** a substitute for the lock: it cannot make the swap
engine actually refuse, so it proves dlac's half only.

---

## 3. The rest of what the PR owes

- **A suite case for the deposit-apply behaviour** (`b25a572924`). Recorded on the dlac
  side as owed since 2026-08-26 and, as far as dlac knows, still owed. The case worth
  pinning: *a deposit whose identity the ACTIVE job's layout names is applied to the shelf
  on the spot, not merely stored.* That is the behaviour three field reports were needed to
  discover; it should not be rediscoverable.
- **Confirm the migration behaviour is still intended and documented:** existing shelf
  contents a layout does not name are evicted to the vault on the first apply. dlac's docs
  carry this as designed, not a bug — worth a line in the PR so a reviewer doesn't "fix" it.
- **Merge it.** The deposit-apply commit is proven and is currently the only thing keeping
  Henrik's install on an unmerged branch.

---

## 4. Rename fallout — `tools/dlac-pack/gen_pack.py`

The Vanaheim → AscensionXI rename landed in dlac today (`servers/vanaheim/` →
`servers/ascensionxi/`, ids and paths throughout). Two things surfaced that belong to the
server repo:

### 4a. The generator drops pack modules — data-loss bug, fix before the next regeneration

The generated `manifest.lua` arrived with:

```lua
-- no pack modules yet
modules = {},
```

The correct value is `modules = { 'gearvault' }`. Because `manifest.lua` is stamped
*"GENERATED … do not hand-edit"*, the honest fix is in the generator: **`gen_pack.py` must
carry the modules list**, either by emitting it from a declared source or by preserving it
from the existing manifest.

Consequence if it isn't fixed: `serverpack` mounts pack modules from `manifest.modules`, so
an empty list means **the entire Gear Vault module silently does not load** — no tab, no
mirror, no wire client, and no error, because a pack that declares no modules is a
perfectly valid pack. Every future regeneration re-introduces this. I restored it by hand
in dlac for now.

### 4b. Everything else the generator emits is correct

`id = 'ascensionxi'`, `name = 'AscensionXI'`, `maxLevel`, `caps`, `consts` and the seven
data files all came through right — the data files differ from the old Vanaheim ones only
in their header comments. No further generator work needed there.

### 4c. Docs in the AscensionXI repo that name dlac paths

Anything in the server repo pointing at `dlac/servers/vanaheim/…` is now a dead path;
it is `dlac/servers/ascensionxi/…`. The two design authorities dlac defers to —
`documentation/custom/gear-vault.md` (D1–D13) and `gear-vault-implementation.md` — are
worth a grep.

### 4d. The player-facing trap, if dlac is distributed to anyone else

The per-install flag `config\addons\dlac\server.lua` must read:

```lua
return { server = "ascensionxi" };
```

A stale `"vanaheim"` does **not** fail loudly. `serverpack.init()` warns once and falls
back to the index's *first* pack — which is `cexi` — so the install quietly runs the
CatsEyeXI catalog and capability set on an AscensionXI character. Henrik's own install is
already fixed; anyone else migrating needs this line. Worth a note wherever players are
told how to install dlac.

---

## 5. The field round to run once the lock lands

In order, each one round:

1. **Capacity is visible.** `/dl vault` (or the tab header) reports a shelf figure that
   matches the locked size. If it still says 640, §2 was answered wrong.
2. **Pressure fires.** Derive a layout that outgrows the locked shelf → the banner appears,
   the marking dialog pre-marks least-used unpinned entries covering exactly the overflow,
   and each row says whether the sets still name it and when it was last seen worn.
3. **Pins hold.** A pinned entry never auto-ranks in any mode; it sits in the dialog
   unticked and ticking it is the permission. Confirm in **both** Ask and Auto.
4. **Auto evicts once.** In Auto mode, unpinned LRU eviction happens once per layout stamp
   and says so — not every beat.
5. **The swap engine agrees.** After an eviction, a job change dresses the shelf without a
   refusal, i.e. dlac's idea of capacity and the server's are the same number.

---

## 6. Nothing is owed on the dlac side

For completeness, so the PR conversation doesn't stall waiting on us: the client half is
finished, shipped and green. The only dlac work that exists is *conditional* — the
`parseHello` capacity read from §2, and only if the answer there is "no".

**Contract items dlac now depends on — please don't change silently:**

- Identity is `"<itemId>:<hex48>"`, minted server-side from ItemNo + the 24 exdata bytes;
  dlac never constructs one. Two same-id pieces with different augments are different
  identities with independent D9 counters.
- Mutating ops sit behind the 5 s replay ring — dlac retries the **same** Seq on a lost
  reply and never re-sends with a fresh one.
- `pinned` is the shared soft-lock flag (dlac, website, `!vault` all read the same bit).
- Structural exclusions dlac mirrors: cat-15 ammunition and linkshell items are
  vault-ineligible; fishing rods and bait are vault territory (bait rides `quantity`).
- Wardrobe container ids are 8, then 10–16. Nine is Mog Safe 2.

---

## Reference

- dlac design record: `docs/design/gear-vault-integration.md` (GV1–GV8, the wire table,
  the carried-over traps).
- dlac session history: `docs/history.md`, sessions *"the Gear Vault, slice 4"* and
  *"Vanaheim is AscensionXI"*.
- Promotion queue entry with the field-confirmation record: `docs/HANDOFF.md`.
- Server-side design authority (AscensionXI repo): `documentation/custom/gear-vault.md`
  (D1–D13) and `gear-vault-implementation.md`.
