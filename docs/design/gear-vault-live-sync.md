# Gear Vault live sync (2026-09-30)

**Status:** dlac side on `dev` (`2026.09.30a`; the zone-line round of
2026-10-01 in `2026.10.01a`); server side in AscensionXI PR
[#728](https://github.com/henkpoa/AscensionXI/pull/728), branch
`claude/gear-vault-sync` (pushes, one-request reads, the deposit cap, the
session-long subscription). The dlac side is useful on its own against today's
server: every server addition is negotiated in HELLO and stays off until the
server advertises it. **Field round owed** (checklist at the end).

Henrik's ask: "The 8 second sync is confusing, can we optimize this somewhat
even if it increases server resources? Can dlac assume happy cases more and in
the backend queue up syncs etc? Sometimes some things don't show up unless a
manual sync happens." Two rulings arrived during the work and bind everything
below:

- **The vault only changes in a city** — "there should not be any gear vault
  events when outside the city, since you can only interact with it inside
  one." Deposits and withdrawals happen at a Gear Vault counter, live edits to
  the active job's layout need a city (the zone type's CITY bit) or the Mog
  House, and job changes happen in the Mog House. Out in the field the client
  holds still.
- **Dupe safety outranks speed** — "our highest priority last time was the
  duping risk, where performance got the back seat. Keep duping risks in mind."
  Every change was checked against it (the section below).

## What the evidence said

Four read-only investigations (the dlac state machine, the server backend, the
server's push and pacing machinery, and 25,278 lines of field wire logs from
eight characters, 2026-09-18 to 09-29):

- **"Doesn't show up without a manual Sync" was a real bug**: a trade to a Gear
  Vault counter — the NPC's own suggestion, "trade it gear" — deposits on the
  server with no 0x1E0 frame, and dlac had no hook for it. The mirror stayed
  *fresh* until a zone line, a job change or Sync. Five more state bugs came
  with it, all reproduced headlessly: a finished read wiped a resync requested
  while it ran; the zone probe compared the running revision instead of the one
  the rows were listed at (count-neutral changes slipped through); a job change
  kept probe-only mode; Sync could not cut a 30 s backoff; the reconcile push
  key parked BUSY-refused adds forever, re-sent city-refused adds after every
  re-read in the field, and left the city badge stuck. The + Add picker's
  candidate cache filtered by ownership once and was never rebuilt by a vault
  read.
- **"The 8 second sync" was not a sync.** It was the additions engine's local
  beat, painted as a countdown that ran whether or not anything was pending. It
  put up to 8 s — often 16 s — between a deposit and its add.
- **34-58 % of all vault requests were waste.** Every gear swap sends a 0x01F
  lock-flag update; dlac treated every 0x01D-0x020 as "everything moved",
  dropped every slot identity and marked the layout stale, so combat re-read
  the layout, the lost list and the worn slots on every beat. One session
  idled at 20 requests a minute for two hours; layout reads restarted forever
  under churn (runs of 24-30 pages).
- **Two thirds of every chained read was dlac's own 0.35 s gap.** The server
  drops a second 0x1E0 within 50 ms, but one request in flight already keeps
  our frames in separate client datagrams (~270 ms apart); the gap only added
  latency.
- **The fixed waits dominated edits:** a layout edit's follow-up took a median
  11.1 s, 6 s of it a fixed settle. The server applies the layout INSIDE the
  request and queues its item packets before the ack (FIFO), so the vault is
  final when the ack arrives — the same holds for a job change (the apply runs
  before the job packets that tell us).
- **A server bug:** a DEPOSIT ack for 63+ entries does not fit one 500-byte
  frame; the server committed every deposit and the reply vanished (dlac let
  Store all send up to 124).

## What dlac does now

**Events, not clocks.** The layout engine runs when something it depends on
changes — a vault or layout commit, a set commit (`profilesets.generation()`),
a zone or job change, a capacity packet (0x01C), a setting or Bench change —
0.2 s after the first kick, plus a quiet local re-derive every 3 s for what has
no event (a trigger file saved elsewhere; the file is re-parsed only when its
text changed). The wire is touched only when something is actually missing.
The countdown is gone; the layout header names work in progress ("adding 2
from your sets...", "saving your changes...", "updating...") or says nothing.

**The field holds still.** Bag moves in the field only forget their own slot;
they never re-read the layout. The engine holds its adds outside a city
("waiting for a city" — `location.inCity()` = the server's own CITY predicate,
or a town with a counter such as Nashmau) instead of sending edits the server
would refuse, and sends them on arrival.

**A zone line changes nothing** (2026-10-01, Henrik: "Can dlac cache between
zones? Nothing should happen during zoning"). Zoning moves no gear, so every
view — the vault rows, the layout, the slot -> copy identities, the lost list,
the push subscription — survives it whole, and nothing is sent from the
zone-out until the new zone's inventory has loaded:

- **The zone line's edges are read off the wire.** It starts at 0x00B, whose
  `LogoutState` (byte 4) is 2 (ZONECHANGE) for a zone line and 1 (LOGOUT) for
  a logout. It ends when the zone-in's inventory re-send is complete: the
  server names every container in one run of 0x01D `StillLoading` (State 0)
  and then says `AllLoaded` (State 1). Every other 0x01D sender — the vault's
  own tidy, a swap's end-of-container flush — names ONE container per
  AllLoaded, and the server's zone-in tidy can fire while the new zone is
  still loading, so only an AllLoaded after a run of two or more counts. A
  zone whose load is never seen ends its wait after 30 s.
- **The re-send is not movement.** While zoning, `noteInventory` ignores the
  item packets that refill the bags, and the 0x01C container sizes are not
  wardrobe growth. The layout engine does not run; the zone's settle kicks it
  once (adds held for a city go out then).
- **What can change the vault across a zone line is the server's zone-in
  tidy**, and a server that pushes reports it (APPLIED with Pulled / Evicted —
  most zone lines move nothing and say nothing). Against a server without
  pushes, arriving in a city probes once, 3 s after the zone has loaded (the
  tidy runs on a 2 s timer); the rows stay fresh until that probe leaves. In
  the field nothing is sent; the next city arrival catches it.
- **Every cached copy identity is pinned to the revision it was read at**, so
  the first reply carrying a newer revision drops them all. And once the zone
  has loaded, each one is checked against what its bag slot now holds — the
  tidy's own item packets were ignored with the re-send — and forgotten if the
  item differs (locally, no traffic).
- **A request on the wire at the zone line** is dropped at the zone-in (the
  old map server's entity took its reply with it): a read runs again in full
  once the zone is ours, a write is reported as outcome unknown and both
  views re-read — never re-sent (dupe safety, below).

**A login is not a zone line.** A zone-in counts as a zone line only within 60 s
of a 0x00B ZONECHANGE; anything else — a logout, a lost connection (no 0x00B at
all), a zone line that never arrived — starts a session. The server dropped the
subscription at its game-in and its login tidy may move copies, so once the
zone has loaded the client sends one probe (wherever it stands: it renews the
subscription and compares the revision) and asks for the layout once (an edit
made while away — a GM, the website — moves no copy, so the revision need not
show it). A renewal a quick zone line cut short runs at the next zone, and an
un-attuned character logging in asks once wherever it stands (that renews the
ATTUNE push).

**Gear swaps are not inventory changes.** `vaultclient.noteInventory` parses
0x01E/0x01F/0x020 in `packet_in`, where the bag memory still shows the slot's
OLD item: a same-item 0x01F (an equip's lock flag) and a non-zero 0x01E (a
stack count) change nothing; a slot whose item changed forgets only its own
copy; the layout re-reads only when that item is one the layout names.

**Reads start when the server is done, not after a guess.** After our own
active-job edit: 0.3 s (a run of edits coalesces), was 6 s. After a job
change: 1 s, was 6 s. After a counter trade or `!vault`: 3 s, pulled earlier
by a push. The post-reply gap is 0.1 s (was 0.35). No legacy layout page goes
out before HELLO any more (every login sent one and threw it away), and the
lost list re-reads only when the revision moved.

**The staleness bugs are fixed:** the counter-trade hook (`packet_out` 0x036
to an entity named "Gear Vault"); the mirror generation (`st.mirrorGen` — a
read commits fresh only if no reason arrived while it ran); the probe compares
`mirror.revision`; a job change and Sync clear probe mode; Sync always reads
now, over any backoff; the push key is "the exact adds" with a 10 s retry
clock; the city badge clears when nothing waits; the + Add picker keys on
`ownedcache.generation()`, bumped by every vault commit; a character switch
without a reload resets the vault client, the engine and the usage memory.

**Your own edits show at once** (`vaultui` overlay): Add paints a dim
"adding..." row, Remove hides the row, Pin shows the new pin, the moment the
edit is queued; a refusal takes it back and says why; an accepted edit's
overlay stays until a layout read newer than its answer shows the real row.
Store says "Storing..." from the click. The header only speaks when something
is wrong (gold "[vault unreachable]" / "[not read yet]"), or a dim
"updating..." while the vault list is really being re-read.

## The wire additions (the contract the server implements)

All on 0x1E0, vault partition. Nothing here is sent unless both sides set the
capability bit.

- **HELLO request word @2 = client capabilities** (was reserved, always 0;
  servers before this change ignore it). Bit 0 (value 1) = "subscribe me to
  CHANGED pushes".
- **HELLO reply caps word @2**, new bits: **PUSH = 4**, **STREAM = 8** (1 =
  instance ids, 2 = atomic instance ADD, unchanged).
- **CHANGED push, op 0x4B, seq 0, status OK, flags 0**, sent only to a
  subscribed session. Payload 24 bytes: `u16 Scope; u16 Cause; u32 Rev (the
  instance revision); u32 JobMask (bit 2^job); u32 VaultCount; u16 Pulled;
  u16 Evicted; u32 EventSeq`. Scope bits: VAULT 1 (vault rows moved), LAYOUT 2
  (layout rows changed for JobMask), APPLIED 4 (an apply finished; Pulled /
  Evicted say whether copies moved), LOST 8, ATTUNE 16, CAPACITY 32. The server
  coalesces a burst into one push, defers it past the change's own item packets
  (so it lands after them — FIFO), and does not push changes the subscriber
  made itself through 0x1E0 (it already has their acks). The subscription
  lasts the session (a charvar, written only when it changes): a zone line
  keeps it, a fresh login clears it (the server's `onGameIn` with `zoning` =
  false, before anything there can mark a change), and every HELLO restates
  it. When dlac unloads it sends a goodbye HELLO with client caps 0, so the
  server never keeps sending frames nothing would block from reaching the
  game. dlac never sends 0x4B and never uses seq 0, so a push is never
  mistaken for a reply (and never touches the transport's pending slot — T2).
- **STREAM reads:** LIST2 (0x46), LAYOUT_LIST2 (0x47) and LOST_LIST (0x4A) take
  an optional 2-byte tail after their cursor payload: `u8 Flags (bit 0 =
  stream); u8 MaxFrames`. The server answers with up to MaxFrames frames (it
  caps the number itself), each flagged **FOLLOWS = 4** except the last; the
  last carries **MORE = 1** if the list continues past the burst (ask again
  from the last key). Keys stay ascending, so a retried request's duplicate
  frames are skipped by key. Reads only — no write is ever streamed.
- **MaxDeposit = 62** in HELLO (was 124): one ack frame's worth. dlac caps a
  DEPOSIT at `min(MaxDeposit, 62)` and splits Store all into such requests.

## Dupe safety (every change, checked)

The replay ring (per character, per map process, last 8 mutating replies,
5 s by `os.time`, keyed on op + seq + payload bytes) is what makes a retried
write safe. Nothing here weakens it, and several changes tighten it:

- **Writes are never re-sent with a new seq**, as before: a write whose
  retries run out, or whose reply died at a zone line, is reported as
  "outcome unknown" and both views are re-read (`failWrite`).
- **Write retries now all land inside the replay window**: sends at 0, 1.5 and
  3.0 s (`MAX_RETRIES` 3 -> 2). Reads keep more patience (2.5 s, 3 retries) —
  a repeated read is harmless.
- **A write on the wire at a zone line is never retried** — the new zone can be
  another map process whose ring has never seen it, and a retry there would
  run it again. Before, the retry loop re-sent it after the zone line.
- **Nothing leaves while zoning** (2026-10-01): from the 0x00B until the new
  zone's inventory has loaded, not even a retry is sent into the void, and a
  click made meanwhile waits for the zone. An ack that arrives between the
  0x00B and the zone-in still counts.
- **The subscription moves nothing**: a lost push only delays a re-read. A
  fresh login clears it so a client without dlac never receives an unasked
  frame.
- **Seqs start at a random point per load and never use 0**, so a reload can
  never re-send an identical write inside the old ring's window, and a server
  push can never be taken for a write's reply.
- **Store says "Storing..." from the click**, so the same bag slot cannot be
  queued twice.
- **Deposits never exceed one ack frame** (62), so every deposit gets its
  answer.
- **A batch refused part-way is re-read, not trusted.** The server answers a
  DEPOSIT / WITHDRAW batch that meets BUSY or a store error mid-way with ONE
  status for the whole frame, and the entries that already moved lose their
  results. dlac used to read that as "nothing moved"; it now re-reads the vault
  (TOO_FAR, decided at the first entry, still leaves the mirror standing).
- **One request in flight stays the law.** Nothing is pipelined; the lower gap
  applies after a *matched* reply only (T1), and an abandoned request frees
  the slot without ever being re-sent (T3).
- **The optimistic overlays are display only** — the server's answer is
  still the only thing that moves anything, and the next read replaces them.
- **The narrow inventory rule keeps the deposit guard sharp:** the
  retirement deposit's `expectedInstanceId` check (client-side — the DEPOSIT
  wire names a bag slot, not an instance) still sees every change of a slot's
  item; only lock flags and stack counts, which never swap the copy in a slot,
  are ignored.
- **Everything new on the server is read-only**: the push, the streamed reads
  and the HELLO fields touch no deposit, withdraw or apply path; the deposit cap
  refuses an oversized request before anything runs.

## Field checks owed

Reload dlac (`/addon reload dlac`, `/dl check` shows `2026.09.30a`), then:

1. **Combat is quiet.** Fight for a few minutes in the field with the vault tab
   closed, then open it: no "(fetching...)", no flicker. `debug/gear-vault-
   wire.log` shows no vault traffic during the fight (the 60 s ascension poll,
   op A0, is not the vault).
2. **Counter trade.** Trade a piece to a Gear Vault counter: it appears in the
   Vault list within ~3 s without Sync (with server pushes: within ~1 s).
3. **Store a set piece.** Store a piece your sets use: it is added to the
   layout by itself within a second or two of the vault list showing it (no
   countdown anywhere).
4. **Your edits.** Remove / Pin / Add to Mog Wardrobe: the pane changes at
   once; in the field an Add to your active job is refused and the row comes
   back with the reason.
5. **Job change.** The new job's layout shows within ~2 s; the vault list
   follows.
6. **Zone lines are free.** Zone between cities and the field a few times with
   the vault tab open: the rows never flicker or go stale, and the wire log
   shows NO vault traffic at zone lines (without server pushes: one HELLO ~3 s
   after arriving in a city, nothing in the field).
7. **Log out and back in** (same character, no addon reload): one HELLO and one
   layout read after the zone loads, wherever you stand.
8. **Unload** (`/addon unload dlac`): the wire log's last vault line is a HELLO
   (the goodbye).
9. **Store all with more than 62 pieces** (if you have them): one result line,
   no timeout.
10. **Rate limits.** The map server log shows no new
   `Rate-limiting packet GP_CLI_COMMAND_VOID_STORAGE` lines.

With the server PR deployed: `/dl vault` says `live updates: on, one-request
reads`, checks 2 and 5 get faster, and check 6 sends nothing even in a city; the
wire log shows `push` lines.

## Not done (deliberately)

- **Authoritative deltas in mutation replies** — the most expensive option
  (every apply would have to report each move) for the least gain now that the
  follow-up read is one request and starts immediately.
- **Scoped revisions** (per job layout, vault contents, lost list) — needs SQL
  triggers and a C++ binding; the push's scope bits carry the same information
  for live changes.
- **Pipelining** — rejected on dupe grounds (the replay ring holds 8) and
  pointless for cursor pages.

Related: [gear-vault-integration.md](gear-vault-integration.md) (the design
record), [gear-vault-sync-efficiency.md](gear-vault-sync-efficiency.md) (the
2026-09-20 round this continues).
