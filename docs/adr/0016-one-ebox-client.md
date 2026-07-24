# 0016 — One E-Box client: one 0x1A4 door, every feature a consumer

2026-07-23, grilled and confirmed by Henrik, ahead of the E-Box Restock build
(design doc `docs/design/ebox-restock.md`; the R1b/R10 rulings there). No engine
version — the whole thing is addon-state, no `dispatch.lua` involvement (contrast
ADR 0013's twin problem, below).

## Context

CatsEyeXI's Ephemeral Box — the Crystal-Warrior-only store (CONTEXT.md) — is
reached over a custom **0x1A4** request/response protocol, and that opcode is a
shared **party line**. helmwatch's `GET_POINTS(8)`, the trove addon's own panels,
and dlac all send and receive on the one packet; Ashita hands every inbound
0x1A4 to every addon, and the retail client has no idea what the opcode is. So a
reader must both stage *only its own* stream and block *only what it asked for*
(the helmwatch rule, already living in `feature/eboxammo.lua`).

Today dlac has exactly one 0x1A4 reader, `feature/eboxammo.lua`, and it speaks
only the **subset AutoAmmo needs**: `GET_CATEGORY(5)` for the Ammunition count
stream (parsing the inbound `CLEAR(0)`/`ITEM(1)`/`END_LIST(2)` that carry it),
`WITHDRAW(2)` + `ACK(3)`, and the `LOCKED(4)` gate — a partial mirror of the full
wire (`trove/utils/packet.lua`), skipping the outbound `GET_SUMMARY(4)` /
`SEARCH(6)` / `WITHDRAW_PROMPT(3)` and the inbound `SUMMARY(5)`. E-Box Restock
(Henrik's next feature) needs `SEARCH` — the code eboxammo skipped — for its
add-picker, plus `GET_CATEGORY` counts across its tracked items' distinct
`ahCat`s (eboxammo fetches only category 15) — and Henrik has said **more E-Box
features are coming**. The question the grill answered: does Restock get its own
client, or does dlac grow one?

The forcing fact is **request volume**. CatsEyeXI operators care about it
(Henrik's hard NFR, R7b): do not flood 0x1A4. The only way to honour that is to
make coalescing and throttle *structural*, not per-feature — and both need shared
state:

- **Coalescing** — counts come from `GET_CATEGORY` per *distinct* `ahCat`, never
  `SEARCH`-per-item. AutoAmmo wants category 15 (Ammunition); Restock wants
  whatever categories its tracked items span, which overlap 15. Fetched once,
  read by both — but only if both read **one** cache.
- **Single-in-flight** — one GET stream (`_pending`) and one `WITHDRAW`+ACK
  (`busy`, 3 s lost-ACK timeout) at a time, a global min-gap between any two
  outgoing requests, and a proximity gate (query only while near a box,
  `lib/entwatch` "Ephemeral Box", `BOX_RANGE = 5`, field-pinned). Two clients
  would each stage streams, each block 0x1A4, and double the traffic.

## Decision

dlac has **exactly one 0x1A4 client, `feature/eboxclient.lua`**. It joins the
roll of one-door authorities — the Gear Oracle for gear questions (ADR 0013), the
Arbiter for slot claims (ADR 0012), and now the E-Box client for the box — and
CONTEXT.md already names it ("Every dlac feature that reads or withdraws from it
… speaks through the one shared **E-Box client**").

1. **One client owns the whole protocol.** `eboxclient` speaks the full 0x1A4
   wire dlac only partly mirrored — summary, category, search, withdraw, ACK,
   LOCKED — plus the shared machinery: the per-category counts cache, the
   Ephemeral-Box proximity, and the throttle/party-line discipline. Parsing stays
   plain `string.byte` (no `struct`) so the whole wire path runs headless
   (tests EB\*).

2. **eboxammo becomes a thin consumer, byte-identical.** AutoAmmo's shipped E-Box
   behaviour is field-confirmed; it does not change. `feature/eboxammo.lua` keeps
   the surface `ui/ammoui.lua` already calls (`counts` / `refreshIfStale` /
   `withdraw` / `boxDistance` / `isCW`) and delegates each to `eboxclient`,
   narrowing the shared cache to category 15. The refactor happens *behind*
   AutoAmmo, not through it. E-Box Restock is the second consumer of the same
   door — its Fetch-all runs the batch-withdraw pattern (trove `executePrepare`:
   one `WITHDRAW` per item, count the ACKs down) through the one client.

3. **Coalescing + throttle live in the client because they can live nowhere
   else.** This is the load-bearing ruling, not a nicety. A shared category
   cache, single-in-flight, the global request min-gap, and the near-box gate are
   all *shared state* — they exist only if there is one stateful client to hold
   them. Two clients cannot coalesce a category request neither owns, and cannot
   serialize outgoing packets neither counts.

4. **Addon-state only — no engine twin, no VERSION bump.** The equip engine never
   touches 0x1A4 (it equips gear and reports on its equipping, nothing else;
   ADR 0014), so unlike the Gear Oracle (ADR 0013, rulings 3–4) there is no
   seeded-engine copy to keep in parity and no `dispatch.M.VERSION` to bump. The
   one client lives entirely in the Addon state; the only parity that matters is
   eboxammo's behaviour before vs. after the refactor.

## Alternatives rejected

- **Leave eboxammo untouched; give Restock its own second client.** The
  cheap-looking option, and the one this decision exists to refuse. Two
  independent clients each stage streams and each block 0x1A4 on the party line
  (the helmwatch rule guards each client but cannot coordinate *across* clients),
  and they double the outgoing traffic on the exact wire operators asked us not
  to flood — category 15 would be fetched twice, once per feature. No coalescing
  is possible when neither client owns the other's cache.
- **A shared library of stateless helpers, but two stateful clients.**
  Deduplicates the parsing but not the thing that matters: the counts cache, the
  in-flight flags, and the request min-gap are *state*, and split state cannot
  coalesce or throttle. Helpers-only leaves the traffic problem exactly where it
  was.

## Enforcement

The refactor touches a **field-confirmed** feature, so the guard is
behaviour-preservation, not new capability:

- The existing **EB\*** headless tests (wire parsing, the proximity name-trim +
  full-array sweep, `BOX_RANGE = 5`, `_clampQty`) stay green — they already pin
  eboxammo's behaviour and now pin it *through* the client.
- **New parity tests** feed the same fixtures to `eboxclient`'s seams
  (`_onPacket` / `_beginStream` / `_clampQty`) and to the eboxammo adapter, so a
  drift between the old direct path and the delegated path fails CI — the same
  mechanism, in spirit, as the Blueprints serializer pins and the Oracle's OR
  parity pins.
- **Henrik field-tests AutoAmmo** before the refactor is considered done. The
  scarce resource is field-attribution (ADR 0012): a regression in a shipped
  feature must be caught on the board, not in review.

## Consequences

- Every future E-Box feature inherits a working, throttled, proximity-gated,
  coalescing client — a new feature is a new *consumer*, never a new 0x1A4
  speaker. This is the reusable door the "more coming" (Henrik) is built to sit
  on.
- The hidden `/dl ebox` diagnostic (data-not-theories, the `/dl merits`
  precedent) reports the one client's own view — gamemode, the counts cache, box
  distance, the entwatch state — for every consumer at once.
- The party line carries dlac's minimum: overlapping categories are fetched once,
  requests are serialized and min-gapped, and nothing goes out while away from a
  box. Operators get the lightest footprint the feature set allows.
- One risk, deliberately taken and mitigated: a bug in the shared client is a bug
  in AutoAmmo too. The EB\* green bar, the parity tests, and Henrik's field pass
  are the price of the single door — paid once, not per feature.
