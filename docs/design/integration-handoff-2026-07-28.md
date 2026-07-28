# Integration surface + Arbiter Monitor — session handover, 2026-07-28

> **Read this when:** the parser friend comes back with corrections, questions or
> enhancement asks about the stream/queries — or anything touches the Arbiter Monitor,
> the decision ring, or `feature\integration.lua`. It is the whole one-day arc
> compressed: what exists, where it lives, the laws that must survive any change, and
> where each *likely* piece of feedback lands. Written the evening everything was
> promoted to main.

---

## 1. State, in one table

| Piece | Where | Status |
|---|---|---|
| Decision ring (v152) | `dispatch.lua` — `M.getDecisions()`, cap 50 | ON MAIN, field-confirmed |
| Arbiter Monitor | `ui\arbmonui.lua` | ON MAIN, field-confirmed ("Looks good"; responsive cut his own ask) |
| Action feed (v154) | `dispatch.lua` — `M.getActions()`, cap 32 | ON MAIN; feeds anchors |
| The stream, 4 kinds | `feature\integration.lua` | ON MAIN; `worn` field-confirmed via dlacprobe ("it is streaming as we think"); `dispatch`/`invalidate`/`confirm` **headless-only** |
| The 5 queries | `feature\integration.lua` (`_onEvent`) | ON MAIN, **headless-only** — the friend's first connection is their field test |
| Consumer contract | `docs/reference/integration-guide.md` | THE file he was sent; build-audited 2026-07-28 |
| Probe pair | `addons\evprobe\` + `dlacprobe` 2.3 (outside dlac repo) | done its job; keep for re-probes |

Promotion: merge `f50df1f` (whole `2026.07.28c`–`l` train), queue emptied `19f274b`.
Engine v154, addon `2026.07.28l`. Suites at promotion: **4172 + 707**, Windows + WSL lua5.4.

**The friend** (see memory `friend-field-reports` + `docs/HANDOFF.md`): builds a damage
parser as its own Ashita addon, feeds everything to his own Claude, sends AI-authored
patches built on HIS older copy — *read them as evidence, never apply*. He also still
owes the gear.lua re-test from the `2026.07.28e/f` fix (delete `gear.lua` → `/dl scan`
→ `/dl commit`).

## 2. The architecture in five sentences

The engine records; the observer ships; the renderers render. Every dispatch whose
outcome moved appends ONE record to the decision ring (plan snapshot + contest +
ladders-as-asked + ctx snapshot with the numeric join key); every non-Default dispatch
also stubs the action feed, `decSeq`-linked when it produced a decision. `/dl why`, the
Arbiter Monitor and the stream are three renderers of that one record — none re-derives
(mpBands' law). `feature\integration.lua` is an addon-side observer pumping both feeds
FIFO each present frame into `plugin_event` envelopes; the engine's only involvement is
three read-only seams + command routing (ADR 0014 holds: the engine equips and
explains, it does not export). The switch (`/dl stream`) is a Session switch gating the
WHOLE channel, queries included.

## 3. The laws — do not re-derive, do not break

1. **Only push changes** (Henrik, verbatim). Ring append law: resolved items OR any
   slot's winning claimant changed (`M.decisionFp`, pure). The monitor log and the
   `worn` kind inherit it for free.
2. **One anchor per action** — `worn` XOR `dispatch`, never both. An anchor says "seen,
   decided nothing, here was your TP".
3. **ONE stream-side `seq` across all kinds** (gap detection needs one sequence);
   `worn` carries the engine's number as `decisionSeq`. Query replies use the current
   watermark, live emissions increment.
4. **`confirm` is delta-only and newest-only** — landed-whole = silence; a superseded
   plan's check is moot. Consumers are told not to wait for confirmations that
   correctly never come (guide gotcha 8).
5. **A job change never kills the stream** — it emits `invalidate`. The stream dies
   only when world absence outlasts a zone (`M.worldAbsentOutlasted`, the worldWatch
   timestamp read-only — never a second timer).
6. **Transport, probe-verified:** SEND must be a byte table (`RaiseEvent` refuses
   strings); RECEIVE gets `e.data` as a ready STRING + `e.size`; `e` is userdata
   (named fields, never `pairs`); a state hears its own RaiseEvent.
7. **A set name is not a composition** — envelopes carry resolved items + totals; set
   names only ever appear as provenance.
8. **Stamped at decision time, joined by `actionId` + backwards search** — never by
   arrival order, never "the latest envelope at damage time".
9. **Additive evolution only.** Consumers ignore unknown keys; never rename or remove
   a shipped field — add beside, deprecate in the guide.
10. **Every wire-contract change updates `docs/reference/integration-guide.md` in the
    same commit.** The guide's status table is the truth a stranger reads first; this
    session found (and fixed) two drifts the day they were created — assume drift,
    audit after building.

## 4. The seams a future session will need

Engine (`dispatch.lua`):
- `M.getDecisions()` / `M.getActions()` — the two feeds. `M.DECISION_CAP`/`M.ACTION_CAP`.
- `M._recordDecision(event, ctx, planSnap, contest)` → seq | nil; `M._recordAction(event, ctx, decSeq)` — test seams (DR*/IN*).
- `M.decisionFp(plan, explain)` — the append law, pure.
- `M.worldAbsentOutlasted(now)` — the stream's lifetime gate (WW1–3).
- ctxSnapshot captures `actionId`/`actionCategory`/`targetIndex` from `ctx.action`
  (the engine's own 0x01A decode; `equipengine.parseAction`).
- The `|ao` retrace-sig leg — the rank order re-explains on drag (DR3 pins it as source).
- `/dl stream` routes to the observer in the command whitelist + branch.

Observer (`feature\integration.lua`):
- `M.on`, `M.setOn(v)` (snapshot-on-enable, baselines all watermarks/watches), `M.command(args)`.
- `M._pump()` — gate → worn drain (ring-overflow → `dropped`) → anchors → `checkInvalidate` → `checkConfirm`.
- `M._onEvent(e)` — the query router (`worn`/`stats`/`sets`/`gear`/`item`; unknown → `err`).
- **Injectable seams:** `M._raise(name, bytes)` (tests collect + decode as a consumer),
  `M._services()` (gearui's lookups/worn reads — fake it headless), `M.CONFIRM_S`.
- `M._ser` (deterministic Lua-source serializer), `M._buildWorn`.

Monitor (`ui\arbmonui.lua`): `renderMonitor(ui)` from gearui's present hook (under the
Scroll Lock gate); `renderRecord(rec, ui)` is the smoke-drivable core; `ui._arbMon`
persists as uiflags `arbmon`; `ui._arbPin` = the pinned seq. Openers: Menu → Settings +
Gear Helpers → Claim Priority.

Tests: `tests/run_tests.lua` — DR (ring), WW (lifetime seam), IN1–IN17 (observer,
loaded via `dofile('feature/integration.lua')` — the harness seeds, it does not
search). `tests/smoke_ui.lua` — AM1–AM8 (monitor: closed/empty/live-icon/live-name/
pinned frames, hover ON everywhere); MN12a pins the Settings checkbox count (currently
11 — a new row moves it).

## 5. Likely feedback, and where each lands

- **"Field X is awkward / wrongly shaped."** `buildWorn`/`buildAnchor`/the query
  answerers in `integration.lua`. Additive only (law 9); update the guide same-commit.
- **"I want the rule-match trace on anchors"** (which trigger fired, at what priority).
  Deferred BY DESIGN until he names a concrete use (design §5). When he does: the data
  is `hits` + `hitCase` at dispatch time — capture a thin list into the action-feed
  stub (engine, VERSION bump), ship as additive keys on `dispatch` envelopes. Do NOT
  export live rule internals wholesale — stabilize only the named fields.
- **"I want `by` on `worn`."** The contest is already IN the record; a `by` builder is
  a pure render of `contest.explain`/`src`/verdict maps into the guide §2.7 shape,
  added in `buildWorn`. No engine change.
- **"Gear/item caching needs real revs."** Add counters: gear rev bumps where gear.lua
  commits/refreshes land (`syncflags.refreshGear` / commit path); extend
  `checkInvalidate` + the reply `rev`s. The guide's §2.5 invalidate bullet already
  promises this as v2.
- **"Inventory-move invalidation."** The signal exists: gearui's `packet_in`
  0x020/0x01D → `sf.invDirty`. Watch it via services (addon-side), emit `invalidate`
  with a new `changed` word — additive.
- **"Missed events during zone/load."** `seq` gaps + `dropped` already cover loss;
  his re-sync is the `worn` query. If he wants history replay: the ring holds 50 —
  a `history` query (additive `what`) could page it. Not promised anywhere; design
  call for Henrik.
- **"Too chatty / wants filtering."** The v2 shape is a TTL subscribe handshake
  (entwatch's sleep-after-no-interest), design §3 "Cost, honestly". Only if real.
- **Worn-copy augments per slot on the wire.** Deferred additive (guide §2.3 notes
  totals already fold owned augments via the oracle). Per-slot `aug` = decode via
  `feature\augments` at buildWorn; costs a lookup per changed slot only.
- **His patches:** evidence, never applied verbatim (memory `friend-field-reports` —
  his copy is older than dev; diff first, port by hand).

## 6. Open threads (beyond his feedback)

1. His **gear.lua re-test** (the `e`/`f` fix rode the promotion accepted-on-diagnosis).
2. The **Gear Helpers rename field round** (rode whole-or-not; display-only).
3. **`invalidate`/`confirm`/anchors/queries field exercise** — his first connect.
4. The **`dispatch`-kind rule-trace question** — deliberately parked on him.
5. The **plugin folder stays PARKED** (design §10) — revive only for in-state needs
   (a tab in dlac's window, or a gear claimant). Do not re-derive the debate.

## 7. Fast re-entry checklist

1. Read `docs/design/integration-surface.md` §13 (the living state) + this file.
2. `git log --oneline main..dev` — trust git, not memory, for what's promoted.
3. Suites: `lua tests/run_tests.lua` + WSL `lua5.4` (Windows-green ≠ CI-green), and
   `tests/smoke_ui.lua` both ways.
4. Live check: load `dlacprobe`, `/dl stream on`, act — envelopes dump to chat/log
   (its listener filters `dlac_*`/`evprobe_*` names).
5. Any wire change: guide same-commit (law 10), version letter bump, and remember the
   parallel-session rule — `git status` before staging, split hunks by content.
