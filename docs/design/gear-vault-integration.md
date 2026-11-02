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
withdraw happen **only at a Gear Vault**; live layout edits to the ACTIVE
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
every 5 min; arriving in a city (once the zone has loaded), a job change,
an outgoing `!vault`, and the tab's Check now / Sync pull that forward. The first OK afterwards says so once
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

**Structural exclusions dlac must mirror:** cat-15 ammunition that is
fired or thrown is vault-ineligible (void-storage territory — the Ammo
ladder contributes NOTHING to layouts and the ammo flow is untouched);
linkshell items are excluded. Since 2026-09-27 (server
`gv.isKeptOutOfVault`) fishing rods AND bait are refused too, and the
ammo-slot trinkets with no `AmmoType` (Bomb Core, Morion Tathlum) store
like any other gear. `vaultui.keptOutOfVault(rec)` is dlac's mirror.

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
  only a counter.** Field report: gear stored with a Gear Vault before
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

## Bag copies keep their slots, and the tab says so (2026-10-31, #230)

Field report: "Mog Wardrobe is full: 2 equipment pieces cannot fit in." under
`Wardrobes 1-8: 62/65`. Three of the THF layout's 65 entries were copies in
the bags (wire kind 0, state 2). Each still counts one unit, so it keeps a
wardrobe slot, and the server's apply pulls nothing for it, so the slot stays
physically empty. The banner's advice, to withdraw gear and keep using it from
the bags, made it worse: a Warden withdrawal never edits a layout.

Keeping the slot stays: it is how a stored copy finds its way back. The client
now says so. "Mog Wardrobe is full" is kept for wardrobes that are really
full with no bag entry. Otherwise the banner says the layout is full and names
the bag pieces, and the counter adds "-- N kept for gear in your bags".
`usage.rankEvictions` ranks bag entries first, worn or not: removing one moves
nothing. Auto removal follows the same order. The layout's right-click menu
gains Remove from layout and withdraw, which keeps the sets. Counting bag
entries as free space is an owner decision on #230 and is not done.


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
because its signature stores EXP. **Amended 2026-10-01:** a set entry that names
no augment takes plain vault copies first, then augmented copies when nothing is
being chosen: the shortfall takes every augmented copy there is, or copies whose
rolls are identical. Differently rolled copies competing for fewer places stay
manual and are named in the vault tab ("choose with Add to Mog Wardrobe") instead
of counting as not vaulted. An entry pinned to the plain copy (`AugKey = ''`)
never draws an augmented one. Items with legacy rows awaiting review are
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
then use the ordinary deposit flow, which still requires a Gear Vault.

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

### Sync efficiency investigation (2026-09-20)

[Measured request overhead and proposed client/server improvements](gear-vault-sync-efficiency.md)
records a 13-request manual-add sequence, a reproducible comparison of singleton
and batched identity lookups, implementation status and remaining steps. Batching,
refresh coalescing and negotiated atomic instance ADD are implemented locally;
the shared pacing and six-second post-edit mirror delay are unchanged.

### Live sync (2026-09-30)

[The live-sync round](gear-vault-live-sync.md): the vault only changes in a city
(Henrik's ruling -- the client holds still in the field), the additions engine is
event-driven (the 8 s beat and its countdown are gone), gear swaps no longer
invalidate anything, counter trades are noticed, the staleness bugs of the
2026-09-30 audit are fixed, your own edits show at once, and the server gains
opt-in CHANGED pushes, one-request streamed reads and a 62-entry deposit cap.
Its dupe-safety review covers every change. It supersedes the six-second
post-edit delay and the 0.35 s pacing described above.

### EXP band recharge in Teleports (2026-10-03)

AXI now enables the normal Teleports menu by default (character overrides still
win). Right-click an EXP ring for **Recharge ring**. The option is inert and dim
when unavailable, with visible reasons underneath. Chariot, Empress and Emperor
Bands held only in a fresh vault mirror also appear in the menu. Other EXP rings
explain that the counter cannot recharge them. CEXI has no recharge service.

`ui/rechargeui.lua` draws the context menu. The active pack provides
`expRingRecharge`; AXI's `modules/gearvault/recharge.lua` owns its state, reads and
explicit action. The existing command `/say !vault charge_exp_band` remains the
only write. It uses the shared guard purchase/recharge allowance and current
nation CP. There is no automatic unequip, withdrawal, recharge or retry.

The companion AXI change advertises HELLO capability **16** and serves read-only
op **0x4C**. Payloads: request `u32 nonce`; reply `u32 nonce, u16 selected item,
u8 reason, u8 near counter`. Reasons: 0 ready, 1 busy, 2 weekly allowance used,
3 equipped/reserved, 4 full, 5 insufficient CP, 6 absent from vault/wardrobes,
7 error. The outer status still reports attunement and protocol errors. The
server measures range independently, so weekly and distance reasons can both
appear. All integers are little-endian; normal 0x1E0 envelope/padding applies.

Queries run only while the context menu needs them, at most once every two
seconds through the shared transport. A five-second timeout abandons its slot;
responses older than three seconds cannot enable a recharge. Full nonces reject
late replies across resets/zone lines. A live entity distance check also disables
the action after walking away. Clicking rechecks eligibility and holds further
actions for two seconds while the command settles. Legacy duplicate bands follow
the server's first-match order; the option refuses if it would target another band.

**Compatibility:** until the companion server binary and Lua are deployed, the
menu says recharge status is unsupported and stays disabled. The server's preview
capability is advertised only when the native binding declares support: an old
binding would otherwise ignore the extra preview argument and perform a recharge.
The preview returns before all recharge writes and outgoing item/CP packets.

Regression: `lua tests/exp_ring_recharge.lua`, the normal core/UI suites and
the AXI native `charge_exp_band` suite. Server source and native test handoff:
`C:/repos/axi-dlac-ring-recharge/documentation/custom/vault-exp-band-recharge.md`.
Live Ashita rendering and the deployed command round-trip still need a field check.

### The Shared Vault (Group Ironman, 2026-11-02)

**Status:** dlac `2026.11.02a`, branch `claude/shared-vault`. It pairs with
AscensionXI branch `claude/group-ironman`: the server is
`modules/custom/lua/group_ironman_vault.lua`, and the wire is in that repo's
`documentation/custom/group-ironman-implementation.md`, "The Shared Vault
(DLAC)". The headless suite and the mutation sweep are green. Not deployed;
**a field round is owed** (the checklist ends this section).

Group Ironman lets up to six characters share a shelf of gear, the **Shared
Vault**, beside each member's own Gear Vault. The Gear Vault window gets a
third tab, **Shared Vault**, after Vault and Inventory.

**When the tab shows.** The vault HELLO reply sets capability **32**
(`cap.SHELF`) and appends 12 bytes, and the character is in a group: the
tail's GroupId is not 0, or the latest SV_CHANGED said InGroup 1. An
SV_CHANGED with InGroup 0, a HELLO with GroupId 0 or a NOT_IN_GROUP answer
hides the tab and forgets the shelf. An older server never shows it, and dlac
never sends it a shelf op.

**The wire** (vault partition, little-endian, payloads after the 8-byte
envelope):

| Op | C2S | S2C |
|---|---|---|
| HELLO 0x40 | word @2: bit 1 (value 2) asks for SV_CHANGED; bit 0 is still the vault's own push | caps bit 32; bytes 20-31: `u32 GroupId; u32 VaultRev; u32 ShelfCount` |
| SV_LIST 0x60 | `u32 AfterRowId` + the stream tail (flags 1, up to 8 frames) | per frame `u16 Count; u16 Rsvd; u32 Rev;` then Count x 40: `u32 RowId; u16 ItemNo; u16 Rsvd; u32 InstanceId; u32 SharedBy; u8 IdentityExtra[24]`. Up to 12 rows a frame; MORE 1, FOLLOWS 4 |
| SV_PUT 0x61 | `u32 VaultRowId; u8 Container; u8 Slot; u8 Flags (bit 0 confirm); u8 Rsvd`. VaultRowId 0 names a wardrobe piece | `u16 Code; u8 JobCount; u8 Wardrobe; u32 ShelfRowId; u32 Rev;` then JobCount x `u8 Job` |
| SV_TAKE 0x62 | `u32 ShelfRowId` | `u16 Code; u16 Rsvd; u32 VaultRowId; u32 Rev` |
| SV_MEMBERS 0x63 | 4 bytes, ignored | `u16 Count; u16 Rsvd; u32 GroupId; u32 Leader;` then Count x 24: `u32 CharId; u8 Flags (1 active, 2 leader, 4 online); u8 Rsvd[3]; char Name[16]` |
| SV_CHANGED 0x6F | (push, seq 0) | `u32 Rev; u32 ShelfCount; u8 InGroup; u8 Rsvd[3]; u32 GroupId` |

A move's result is a GroupIronmanCode (`vaultclient.giCode`): 0 OK, 1
NOT_IN_GROUP, 12 BUSY, 13 STORE_ERROR, 17 STAYS_WITH_YOU, 18 SHELF_CAP, 19
RARE_IN_STORE, 20 NEEDS_CONFIRM, 21 NOT_ELIGIBLE, 22 NO_ROW, 23 RARE_HELD, 24
DUPLICATE, 25 ITEM_BUSY, and others a share or a take never meets.
`sharedvault.REFUSAL` puts the ones they can meet into words.

**What the player sees.**

- The shelf, grouped by slot like the Vault tab: icon, name, level, `[aug]`,
  the hover card with the augments, and "from Alice" (names from SV_MEMBERS,
  read when the tab opens). A line above names the members still in the
  group, the leader marked.
- **Take** on each row (SV_TAKE): the piece goes into your own Gear Vault.
  It works at a Gear Vault.
- **Share with your group** in the Vault tab's right-click menu: that vault
  row (SV_PUT by row). Stacks are not offered: pieces only (S12 rule 3).
- **Share from your Mog Wardrobes**: the unworn gear in Wardrobes 1-8, each
  with **Share** (SV_PUT by container and slot).
- One piece per click: one share or take at a time. The buttons go dim while
  one is out or a question waits.
- **The question.** A piece in your job layouts, and every wardrobe piece,
  comes back NEEDS_CONFIRM. A popup opens over whichever sub-tab is showing:
  "Share X with your group? It is in your WAR and PLD layouts. Sharing it
  removes it from those layouts, pins included." A wardrobe piece says "It is
  in your Mog Wardrobe." **Share anyway** sends SV_PUT again with the confirm
  flag, as a new request with its own seq. Cancel, a click elsewhere, leaving
  the group, or a minute without an answer sends nothing.
- Results and refusals land on the window's result line and in chat as
  "shared vault: ...". `/dl vault` adds a line for the shelf.

**Reads (S9).** Opening the tab reads the member list, then the shelf. After
that the shelf is read again only when the server names a Rev other than the
one the rows were read at: an SV_CHANGED (including the one a map process sends
after a zone line or a login), a HELLO tail (the server counts that Rev as
told), or the answer to our own share or take. Only while the tab is open; a
closed tab reads at its next open. Never on a timer. Two refinements:

- A Rev announced while a read is on the wire waits for that read, and reads
  once more only if it is newer than the answer. The server's counter only
  grows, so the same Rev, or an older one the read overtook, is covered.
- A take answered at the read Rev + 1 was our change alone: its row is
  dropped locally and nothing is read.

A row whose sharer the member list cannot name asks for the members once per
Rev.

**Write laws (C1: the vault's own are unchanged).** SV_PUT and SV_TAKE are on
`isWrite`: two retries with the same seq, none past WRITE_DEADLINE from the
first send, so all inside the server's 5 s replay window. A lost answer, or one
cut by a zone line, is outcome unknown: the vault and the layout are re-read
(the shelf too, when its tab is open), and the write is never re-sent. Shelf
ops ride the vault client's one request in flight, its pacing and the shared
gate, where 0x60-0x6F is the vault's own module. A shelf answer never changes
the vault's state:

- BAD_OP or PROTO_UNSUPPORTED on a shelf op hides the shelf for the session
  and leaves the vault alone.
- A refusal decided before anything moves (TOO_FAR, NOT_ATTUNED, MALFORMED)
  re-reads nothing.
- BUSY, UNAVAILABLE or an unreadable answer may follow a move that ran, so
  both stores are re-read.

**The vault after a move.** A share takes the vault row out of the mirror at
once (the server deleted it; a withdraw's subtraction) and re-reads the vault
after SETTLE_EDIT, and the layout too when the piece left job layouts or a
wardrobe. A take marks the vault for one LIST (a deposit's rule), and the layout
when it names the item. The server's own CHANGED push for the same move lands
inside SETTLE_EDIT, so the two make one read. The shelf never joins the mirror:
ownership, the + Add picker and lockstyle never see it (S12 rule 6).

**Files.** `vaultclient.lua` (its "THE SHARED VAULT" section: codecs, state,
requests, answers), `sharedvault.lua` (the moves, the question, the words),
`vaultui.lua` (the tab, the menu item, the popup, the wardrobe list) and
`init.lua` (`/dl vault`'s line; a character switch forgets an open question).

**Tests.** `tests/gearvault_shared.lua`, 222 checks, in CI. Every check was
seen red at least once under a deliberate break, and the mutation sweep keeps
those breaks: S01-S52 break the guards, X01-X84 the codecs, words, tab and
glue. Board: 268 mutants, 264 killed, 4 accepted, none open
([gear-vault-live-sync.md](gear-vault-live-sync.md), "Re-running it"). S09
is equivalent: the pump drops every shelf read wanted while the tab is closed
(S13).

**Server notes** (found while building this; nothing was changed server-side):

1. SV_PUT and SV_TAKE also arm the vault's own CHANGED push for the acting
   session. The shelf ops do not pass through `gv.onPacket`, so `servingId` is
   nil when `sv.put`/`sv.take` call `gv.markChanged`; the vault's own writes
   are never echoed. dlac folds the echo into the same read (above), so it
   costs one small frame per move.
2. The implementation doc's "Live updates (S9)" paragraph still says a HELLO
   resets the session to "told nothing" so that the next tick pushes. The code
   now records the HELLO tail's Rev as told (`sv.onHello`). dlac reads the
   tail either way.
3. SV_LIST reads the counter before the rows, outside the group lock, so a
   frame can carry rows newer than its Rev. That direction costs dlac at most
   one extra read; the reverse order would hide a change.

**Field round owed** (local shard on AscensionXI `claude/group-ironman`, two
clients in one group):

1. `/dl check` shows `2026.11.02a`. A character in no group sees Vault and
   Inventory only.
2. Found a group, or accept an invite, with dlac loaded: the Shared Vault tab
   appears within a few seconds, with no reload.
3. Open the tab: the member line names the group, and the shelf lists what is
   shared, with "from <name>".
4. At a Gear Vault, right-click a vault piece and choose Share with your
   group: the row leaves the Vault tab at once and shows on the shelf. A piece
   in a job layout asks first and names the layouts; Cancel leaves it, and
   Share anyway shares it and the layouts lose it.
5. Share an unworn wardrobe piece from the tab's list: it asks first, and a
   yes shares it.
6. Take a piece: it leaves the shelf and joins the Vault tab within about a
   second, and the member who shared it gets a chat line.
7. With the tab open on client A, share a piece on client B: A shows it within
   about 2.5 s, without Sync.
8. Away from a Gear Vault, Take and Share say "stand at a Gear Vault to use the
   Shared Vault".
9. Leave the group: the tab disappears.
10. `debug/gear-vault-wire.log` shows no 0x60-0x63 requests while the tab is
    closed and none on a clock while it is open, and `push op=6F` lines when
    the shelf moves.
11. The map server log shows no new rate-limit lines.
