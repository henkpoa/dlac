# dlac × Gear Vault — the integration design (AscensionXI only)

- **Status:** design ratified 2026-08-26 (Henrik grill, 7 questions); slice 1
  next. This document is the decision record; the server side is ALREADY
  BUILT AND GREEN — its design authority is the ascensionxi repo's
  `documentation/custom/gear-vault.md` (D1–D13) and the wire/implementation
  map is `gear-vault-implementation.md` there. Nothing here re-decides a
  server ruling.
- **Where it lands:** a pack module, `servers/ascensionxi/modules/gearvault/`
  (ADR 0035). Mounts only with the ascensionxi pack — this feature is
  AscensionXI/AscensionXI-only by Henrik's ruling and will most likely never
  exist elsewhere. No featuregate row needed: a pack-registered tab shows
  through the gear-only default because the gate never hides labels it
  cannot name (ADR 0037).

## The server system, in five lines (see the ascensionxi docs for the rest)

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
MALFORMED 2, BUSY 3, TOO_FAR 4, UNAVAILABLE 5, PROTO_UNSUPPORTED 6,
NOT_ATTUNED 7. Flags bit 1 = MORE (another chunk exists).

**Attunement (server D14, 2026-09-03):** the vault does not exist for a
character who has not finished the quest *The Deeper Room* (the Hollow
One in the starting city, level 5, after *The Hollow Room*). The server
answers NOT_ATTUNED to EVERY vault op, reads included, before the replay
ring. dlac's client treats it as its own state, `unattuned` — not
dormant (the quest can land mid-session) and not a failed sync: no
30 s retry loop, no layout asks (the reconcile engine idles), the mirror
reads as an empty vault, and the tab and `/dl vault` name the quest that
opens it (no chat line: a first-time player is not greeted by it). One HELLO re-checks
every 5 min; zone-in, a job change, an outgoing `!vault`, and the tab's
Check now / Sync pull that forward. The first OK afterwards says so once
and runs a full sync.

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

**Layout count semantics:** ADD increments the stored count; it does not
replace it with a desired total. REMOVE with a positive count subtracts
that many units; REMOVE with zero deletes the entry. PIN is separate.

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
  Superseded for instance-mode unused gear on 2026-09-18: unpinned,
  unworn entries no current-job set or trigger references are released in
  town before additions, even without pressure. Outside and review rows
  are retained. Incomplete derivations pause cleanup. The existing pressure
  settings still govern eviction of referenced gear. Removal modes: **Default** — when the layout outgrows live
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
  **Amended 2026-09-08 — the vault is a SOURCE OF TRUTH for gear.lua, not
  only a counter.** Field report: gear stored with a Void Warden before
  dlac's first run never became a gear.lua record (the fold only re-counts
  records that already exist), so the + Add picker could not offer it.
  `gearimport.scan` now walks the mirror's rows exactly like bag slots
  (itemId = Id, the 24 identity bytes = Extra, one row = one unit; an
  explicit bag list stays bags-only), and every mirror commit slides the
  same debounced add-only sync an inventory packet does. Tests GVS0-10.
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
## Duplicate messages (2026-09-10)

Single-item deposit refusals show `<item>: Already in gear vault`,
`<item>: Already Equipped`, or `<item>: Already in Mog Wardrobe`.
`vaultclient.parseDepositAck` reads the former reserved header word as a
location hint for a one-entry response: 1=vault, 2=equipped, 3=wardrobe.
Zero/unknown values use the short gear-vault fallback. Batch responses
ignore the hint and keep their summary. Result codes, entry sizes and
the protocol version are unchanged; older addons ignore this word.

The server determines the location by the same normalized identity that
refused admission (AscensionXI PR #420), so this UI does not guess from
item names or stale client holdings. The first stored count that reaches
the allowance reports vault; otherwise the matching wardrobe instance
that reaches it reports equipped or wardrobe. This is a display hint,
not a new admission rule. The server extension must be deployed before
the equipped/wardrobe distinctions appear; wording is short on older servers too.

Files: `servers/ascensionxi/modules/gearvault/{vaultclient,vaultui}.lua`.
Verification: `lua tests/smoke_ui.lua` (1499 checks, including exact strings
through Store callbacks and decoded response bytes), `lua tests/run_tests.lua`
(7474 checks). Reload the installed addon with `/addon reload dlac`, then
try Store with a duplicate in each location. No client visual playtest has
been performed by the agent. Rollback is the previous two Lua files plus
an addon reload; player data and settings are untouched.

## Repeated layout adds and phantom pressure (2026-09-14)

Field report: repeated Add clicks on Field Tunica inflated the layout,
producing a full warning despite live occupancy of 19/23. Earlier hiding
of the Leaping Boots x2 badge only concealed the symptom. The server's
`GearVaultLayoutAdd` increments (`src/map/gear_vault.cpp`); the reconciler
had sent the desired total when raising an existing pair. Manual adds
also lacked a membership/pending guard, and successful layout edits did
not invalidate the vault mirror despite moving its items.

The addon now sends only the missing quantity, waits for current vault
stock, blocks repeated manual additions while edits are pending, and
refreshes both views after active layout edits. Known single-slot gear
counts are bounded at one; rings, earrings and potentially dual-wielded
weapons allow two, known two-handed weapons one. Unknown items and bait
are left unchanged. `layoutcounts.lua` owns this rule for UI, admission,
and capacity accounting. `reconcile.lua` corrects existing excess with a
positive-count REMOVE, retaining the entry, pin and hint. Corrections
wait for town, precede additions/evictions, and re-read the layout after
the acknowledgements. They target an explicit job so a queued correction
cannot decrement the next job's layout after a job change.

Apply by reloading `/addon reload dlac` in town and letting the next sync
finish. Repeated clicks must not increase Field Tunica's count; the bench
must no longer subtract phantom copies from capacity. The separate
startup gear-file repair removes identical shadowed records (the reported
Spatha/BronzeSword duplicates) through its existing backup/validation
path. Differing duplicate blocks remain intact while unrelated records
can still be repaired. A read-only run on the reported saved gear file
preserved all 39 loaded records and produced a second-pass no-op.

Verification: `lua tests/gearvault_counts.lua`, `lua tests/gear_repair.lua`,
`lua tests/smoke_ui.lua`, `lua tests/run_tests.lua`, and
`lua tests/ascensionxi_catalog.lua`. Regression coverage includes additive
pair upgrades, inflated 19/23 layouts, pin preservation, city gating,
pending clicks, mirror invalidation and duplicate gear blocks. Live
in-game verification remains with the owner. No server change is needed.
Rollback the addon changes and reload; startup gear-file writes keep a
timestamped backup. Layout corrections persist on the server.


## Persistent instances: client implementation (2026-09-18)

Server contract: AscensionXI PRs #549 (design), #553 and #554 (implementation),
merged main. HELLO capability bit 0 selects instance mode; a legacy HELLO keeps
all v1 codecs and behavior. Result codes follow the implementation: lost 17,
outside 18, already bound 19 (the original design's 16/17/18 list is stale).

The existing single wire queue now also owns LIST2 (0x46), LAYOUT_LIST2 (0x47),
LAYOUT_SET2 (0x48), INSTANCE_LOOKUP (0x49), and LOST_LIST (0x4A). Codecs enforce
13/12/41/30 row bounds. Lookup results are accepted only at the requested
revision and inventory epoch; a stale reply retries at most three times before
being deferred. Bag-slot caches invalidate on inventory packets, revision
changes, or zoning. Snapshots happen on later present beats, never in packet_in.
Multi-page list reads are discarded if their revisions differ. Layout writes
retain their originating job and same-sequence retries; job changes complete
cancelled queued requests so reconciliation cannot remain stuck in flight.

Layouts, per-copy admission, usage stamps and edits use instance IDs. Missing
legacy entries reserve zero; stack rows reserve one slot. Existing bound copies
continue satisfying generic item demand when their extra bytes change. New
augmented-copy choices stay manual; Anchor Ring (27556) is the explicit exception
because its signature stores EXP. Items with legacy rows awaiting review are
not silently re-added by derivation. Equipment selection, augment requirements,
item-ID ownership totals and stackable identity semantics stay unchanged.

The Gear Vault's **Needs review** section lists missing/ambiguous rows, displays
saved augments and candidate-copy augments, and binds by ordinal or dismisses the
old row. Candidates come from the fresh vault mirror or verified wardrobe-slot
lookups; bag items must first be stored. Pins retain the existing two-click
removal confirmation. Removed/replaced/unverified copies are visible in a
separate expandable list. The `[aug]` badge requires decoded augments, not merely
nonzero signature bytes.

Headless verification: `lua tests/gearvault_instances.lua`,
`lua tests/gearvault_counts.lua`, `lua tests/smoke_ui.lua`, and
`lua tests/run_tests.lua`. The new instance suite is also in CI.

Live acceptance remains required after `/addon reload dlac`: confirm HELLO
negotiation with `/dl vault`, bank Anchor Ring EXP and change jobs twice; upgrade
an augment; bind/dismiss review rows; verify distinct ring copies, a lost item,
and the lost/replaced display. Exercise movement during lookups, including
identical copies, and verify Ashita packet/present ordering. Headless tests prove
revision/epoch rejection, not the game's memory-update timing. No live game
interaction or shard mutation was performed during the client implementation.

### Layout location and retirement (2026-09-18)

HELLO capability changes invalidate pre-negotiation layout rows and request a
fresh layout. Otherwise an early v1 reply can hide instance locations forever.
Outside copies show a gold name and `[In bags]`, with recovery instructions.
Container 17 is the Recycle Bin and instead shows `[Recycle Bin]` with recovery
instructions. A discarded copy remains live while recoverable: the September
18 Mindlorprod report was instance 2909 at location 17, slot 1, with matching
inventory item 12503 and revision 308, including after addon reload. This is
not a tombstone or a client-cache loss. Do not prune it merely because it left
Inventory; permanent loss remains the server's registry/prune responsibility.

Right-click a layout row for **Remove from sets and send to gear vault**. It
updates the current job's committed dynamic sets in one backed-up write, then
synchronously activates them before releasing that instance. Generic references
are removed too; references pinned to different augments are retained. Unsaved
editor changes, unresolved entries, direct trigger references, and slot locks
block the action with a reason. Equipped copies use the existing strip lease
and wait for the client to show them unequipped. Outside copies in Inventory
then use the ordinary deposit flow, which still requires a Void Warden.

Automatic unused-gear cleanup runs in town in instance mode. It preserves
layout pins, worn pieces, outside assignments and legacy review rows. All
augmented set references and trigger payloads protect their item IDs. Missing
set/trigger reads, unresolved references and virtual `dlac:` helpers pause
cleanup because the derivation cannot prove their gear unused. This is separate
from the existing pressure/LRU policy. Pin a manually assigned piece to keep
it without a set reference. Legacy-server behavior is unchanged.

### Shared opcode pacing and edit evidence (2026-09-18)

The server drops a second 0x1E0 frame within 100 ms. The old client's 350 ms
check lived only in the pump's new-request branch: HELLO-to-LIST and MORE-page
continuations called `beginOp` directly from the reply handler and bypassed it.
HELM polls also injected the same opcode independently. A deterministic test
reproduced two sends at the same timestamp before this fix.

`servers/ascensionxi/transport.lua` now gates both DLAC producers with at least
350 ms between actual injections, using LuaSocket wall time (whole-second
`os.time` fallback). Vault `sendPending` also enforces its interval. Work denied
by either gate remains pending without a send timestamp; only a real send
starts its timeout or increments its retry count. Retries retain the same
sequence. Unsent layout edits can still be cancelled on a job change. HELM
retries a denied poll on a later touch. The server limit is unchanged.

`tests/gearvault_instances.lua` drives immediate replies, all three paginated
v2 lists, HELM competition, a dropped-write retry and unsent-job cancellation
through the real shared gate. Existing state-machine harnesses now advance
through deferred sends instead of assuming synchronous page transmission.
Live acceptance: reload DLAC, Sync, change jobs and zone with HELM polling;
check the map log for new `Rate-limiting ... 0x1e0` entries. Headless coverage
proves injection spacing, not network delivery timing.

Historical WHM headband removal cannot be proven from DLAC logs: only the last
wire event was retained in memory, the inspected character debug directory
had no vault edit log, and Ashita's application logs did not contain the
reported item operations. The live headband's unpinned WHM row was eligible
for the newly requested unused-gear cleanup before manual auto-pinning was
added; that is a possible explicit REMOVE source, not a confirmed historical
event. Do not attribute disappearance to a silently dropped REMOVE alone.

Future layout mutation sends/replies/refusals/timeouts append to the character's
`debug/gear-vault-edits.log`: timestamp, sequence, job, verb, item, instance,
ordinal, reason and result. Reasons distinguish manual layout edits,
remove-from-sets, unused-unpinned cleanup, pressure eviction and derived adds.
This logs actual sends (including retries), not merely queued intent. Reply
codes are server outcomes; a timeout explicitly means outcome unknown.

#### Live follow-up: buffered traffic and cleanup decision

The owner explicitly reaffirmed **keep automatic cleanup** after the rollback
drill. The edit log proves 16 RDM REMOVE operations at 22:10:49–22:10:57 with
`reason=unused-unpinned`, including Anchor Ring instance 2810, and successful
server replies. Restored unpinned rows absent from local sets/triggers remain
eligible. This is the chosen behavior, not a server prune defect. It does not
prove which particular operation removed the earlier WHM headband row.

Injection-only pacing did not establish live correctness: the map log records
six 0x1E0 rate-limit drops for Mindlorprod and three for Mindlor between
22:10:24 and 22:11:12. The prior headless check proved calls into Ashita were
spaced, not when buffered packets reached the server.

The shared transport now permits only one distinct request awaiting a reply
and starts another 350 ms cooldown on inbound replies. Same-sequence retries
are allowed; an abandoned pending request expires eight seconds after its last
send. HELM preserves its token across denied sends/retries and bounds attempts
so it cannot hold the channel forever. Both protocol receivers notify the
same transport. A regression demonstrates that the old gate accepted a
different producer after 400 ms without any acknowledgement; the new gate
rejects it until a reply and cooldown. This covers a possible buffering cause,
not proof of the original network timing. Exceptionally delayed originals
and retries can still arrive together; server logs remain the acceptance test.

`debug/gear-vault-wire.log` now records enqueue, reply and expired-request events
with subsecond wall timestamps, op and sequence. It rotates at 2 MB to
`.previous`. Compare it with the active map log after a reload and sync;
enqueue timestamps are deliberately not labeled actual network transmission.
