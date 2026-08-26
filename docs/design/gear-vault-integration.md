# dlac × Gear Vault — the integration design (Vanaheim/AscensionXI only)

- **Status:** design ratified 2026-08-26 (Henrik grill, 7 questions); slice 1
  next. This document is the decision record; the server side is ALREADY
  BUILT AND GREEN — its design authority is the vanaheim repo's
  `documentation/custom/gear-vault.md` (D1–D13) and the wire/implementation
  map is `gear-vault-implementation.md` there. Nothing here re-decides a
  server ruling.
- **Where it lands:** a pack module, `servers/vanaheim/modules/gearvault/`
  (ADR 0035). Mounts only with the vanaheim pack — this feature is
  Vanaheim/AscensionXI-only by Henrik's ruling and will most likely never
  exist elsewhere. No featuregate row needed: a pack-registered tab shows
  through the gear-only default because the gate never hides labels it
  cannot name (ADR 0037).

## The server system, in five lines (see the vanaheim docs for the rest)

The vault is an unlimited per-character store for equippable items. Mog
Wardrobes 1–8 are a **sealed cache** — the vault system is the only door.
Each **main job** owns one layout (identity → count, wardrobe hint, pinned);
on job change the server swaps the shelf to the incoming job's layout,
moving only the difference (~3–4 s of themed item streaming). Deposit and
withdraw happen **only at a Void Warden**; live layout edits to the ACTIVE
job are **city-gated**, while edits to any other job's layout are pure data
writes, legal anywhere, applied at the next job change. Duplicates are
refused at the counter per identity (pairs allowed twice); the swap engine
itself is never refused.

## The wire (both directions ride packet id 0x1E0)

Envelope: `[u16 id/size][u16 sync][u8 Op][u8 Seq][u8 Status*][u8 Flags*][payload ≤500]`
(*C2S: both reserved, must be 0*). Seq is client-chosen and echoed verbatim;
mutating ops sit behind a 5 s server replay ring (a retried frame returns
the SAME reply — retries are safe). Frame statuses: OK 0, BAD_OP 1,
MALFORMED 2, BUSY 3, TOO_FAR 4, UNAVAILABLE 5, PROTO_UNSUPPORTED 6.
Flags bit 1 = MORE (another chunk exists).

Vault partition 0x40–0x7F:

| Op | C2S payload | S2C payload |
|---|---|---|
| HELLO 0x40 | `u16 Proto; u16 Rsvd` | `u16 ServerProto; u16 Rsvd; u32 VaultCount; u8 MaxList(15); u8 MaxDeposit(124); u8 MaxWithdraw(62); u8 Rsvd` |
| LIST 0x41 | `u32 AfterRowId` (keyset cursor) | `u16 Count; u16 Rsvd; N×{ u32 RowId; u16 ItemNo; u16 Qty; u8 IdentityExtra[24] }` + MORE flag |
| DEPOSIT 0x42 | `u16 Count; u16 Rsvd; N×{ u8 Container; u8 Slot; u16 Rsvd }` | `u16 Count; u16 Rsvd; N×{ u8 Container; u8 Slot; u16 Code; u32 RowId }` — Warden gate + D9 counter apply |
| WITHDRAW 0x43 | `u16 Count; u16 Rsvd; N×{ u32 RowId; u16 Qty; u16 Rsvd }` | `u16 Count; u16 Rsvd; N×{ u32 RowId; u16 Moved; u16 Code }` |
| LAYOUT_LIST 0x44 | `u8 Job(0=main); u8 Rsvd; u16 AfterOrdinal` | `u16 Count; u16 Rsvd; N×{ u16 Ordinal; u16 ItemNo; u16 Count; u8 Hint(0=none); u8 Pinned; u8 IdentityExtra[24] }` + MORE |
| LAYOUT_SET 0x45 | `u8 Job(0=main, 1..22); u8 Verb(0 add/1 remove/2 pin); u16 ItemNo; u16 Count; u8 Hint; u8 Pinned; u8 IdentityExtra[24]` — one entry per frame, batch via distinct Seq | `u16 Code; u16 Rsvd` |

Per-entry result codes (`GearVaultCode`, u16 on the wire): OK 0, PARTIAL 1,
NOTHING_TO_DO 2, NOT_ELIGIBLE 3, ITEM_BUSY 4, NO_INSTANCE 5,
INVENTORY_FULL 6, RARE_HELD 7, BUSY 8, STORE_ERROR 9, DUPLICATE 10,
TOO_FAR 11, NOT_IN_CITY 12, UNKNOWN_ITEM 13, AMBIGUOUS_NAME 14,
NOT_IN_LAYOUT 15.

**Identity:** the server mints `"<itemId>:<hex48>"` from ItemNo + the 24
exdata bytes the client sends, normalizing volatile bytes itself (charge
counts, timers) — dlac always sends the RAW `extra` bytes it can see (bag
scan / shelf) or echoes `IdentityExtra` from a LIST/LAYOUT_LIST row, and
never constructs identities by hand. Unaugmented gear = id + 24 zero bytes.

**Structural exclusions dlac must mirror:** cat-15 ammunition is
vault-ineligible (void-storage territory — the Ammo ladder contributes
NOTHING to layouts and the ammo flow is untouched); linkshell items are
excluded; fishing rods AND bait are vault territory (bait rides `quantity`).

## The ratified decisions (grill of 2026-08-26)

- **GV1 — Layouts are DERIVED.** A job's layout is a projection of what
  dlac already knows the job wants: every candidate rung of every Dynamic
  Set in the job entry, every trigger's inline payload and set reference
  — all trigger points feed it automatically ("building sets IS authoring
  the shelf"). The tab is the manual window, not a second bookkeeping.
- **GV2 — The soft-lock IS the server's `pinned` flag.** A player marks an
  entry to protect it; every remover — including dlac's own automation —
  must get explicit player confirmation to touch a pinned entry, in every
  mode. One flag, shared with the website and `!vault`.
- **GV3 — Additions are free; removals are a SPACE-PRESSURE flow.**
  Settings govern both. Default: dlac pushes new derived entries freely
  (commit-time for the edited job, login reconcile as backstop; the
  active job's push queues behind the city gate with a visible badge).
  A piece no set references anymore just STAYS in the layout until shelf
  pressure. Removal modes: **Default** — when the layout outgrows live
  wardrobe capacity, present a marking dialog to free space; **Full** —
  dlac auto-evicts by LRU (unassigned-first, oldest last-used first),
  still asking permission whenever only pinned entries remain.
- **GV4 — Last-used = engine-equipped + observed worn** (A+C). Stamped
  when dlac's own engine equips the piece AND whenever it is seen worn
  (manual equips count); never stamped by mere set membership in a fired
  trigger. Identity-keyed (augment copies age independently), seeded at
  first sight so never-used gear ranks oldest. dlac-side data, per
  character — the vault has no business knowing usage.
- **GV5 — Vaulted is an OWNERSHIP TIER.** Owned = the 17 containers + the
  vault mirror (cached LIST); Available unchanged. A third verdict word
  everywhere: **"vaulted"**, its own color. Prune treats vaulted as owned;
  Auto-build's "with gear in storage" setting governs vaulted gear too.
  The mirror re-asks on a throttle and never latches (ADR 0007): refresh
  on login, after every deposit/withdraw ack, and after the job-change
  swap stream settles (the 0x020/0x01D flood already schedules dlac's
  debounced re-scan — same signal).
- **GV6 — One "Gear Vault" tab** registered by the pack module (browse +
  manual handling), auto-populated layout inside it; plus a **Warden
  nudge** float for deposits and the vaulted verdict threaded into
  existing surfaces. Sets tab cross-links in, never absorbs it.
- **GV7 — The deposit sweep is CURATED.** At a Warden the nudge offers
  exactly the inventory pieces some job's layout wants and the vault
  lacks (pairs-aware), pre-ticked, one click; an expander lists other
  vault-eligible gear unticked. Never a zero-click auto-sweep — deposit
  is the moment the player curates what enters the system. Sell-loot
  stays untouched; D9 refusals are the scrap signal, not noise.
- **GV8 — Manual layout adds in v1 come from things dlac can see the
  bytes of** (vault rows, shelf, bags). Planning UNOWNED gear into a
  layout stays a wishlist concern for now.

## Slices (risk-ordered; each one session + one field round)

1. **The wire + the mirror** — the pack module, the 0x1E0 client (HELLO
   handshake, Seq allocation, one-in-flight throttle, replay-safe
   retries), the LIST mirror with its refresh triggers, and the GV5
   ownership fold-in. READ-ONLY: no write op is sent at all. Field gate:
   vault contents show, verdicts right, job-change swap does not confuse
   the bag sync.
2. **The tab, read-first** — status header (HELLO figures, shelf occupancy
   vs live capacities), vault browser, withdraw-at-Warden, LAYOUT_LIST
   view including entries made by the website/chat. Field gate: browse +
   withdraw round-trip.
3. **The derived layout + additions push** — per-job derivation, diff,
   auto-push additions, soft-lock ticks, the city-gate queue badge.
   Field gate: edit a set, change job, the shelf follows.
4. **Deposit sweep + space pressure** — the Warden nudge (GV7), the
   full-shelf marking dialog, the GV4 stamps, the Full auto-evict mode
   with its pinned-permission prompt.

## Traps carried over from the server docs (so nobody re-derives them)

- The swap stream is ~3–4 s of ITEM_ATTR packets at job change — dlac's
  debounced inventory sync absorbs it, but slice-1 testing must confirm
  the mirror refresh waits for the settle, not the first packet.
- WITHDRAW is mutating and replay-ringed: retry the SAME Seq on a lost
  reply (safe); never re-send with a fresh Seq on timeout.
- Two same-id rings with different augments are different identities,
  each with its own D9 counter — the mirror and the sweep must group by
  identity, never by item id.
- Wardrobe container ids are NOT contiguous: 8, then 10–16 (9 is Mog
  Safe 2).
- Existing shelf contents a layout does not name are evicted to the vault
  on the first apply — that is the designed migration, not a bug report.
