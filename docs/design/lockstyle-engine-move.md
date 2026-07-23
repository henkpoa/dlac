# Lockstyle execution moves engine-side — design handoff

> **SUPERSEDED (2026-07-23) by [ADR 0014](../adr/0014-lockstyle-addon-resident.md) —
> "Lockstyle is addon-resident; the Engine equips gear only."** The grill session that
> consumed this document reversed its direction: lockstyle equips *nothing* (it builds
> its own 0x053 and injects via the process-wide `AshitaCore`), so its executor moves to
> the ADDON state beside its trigger — NOT into the Engine as §2 below proposes — and
> every state-crossing becomes a direct call. Henrik's ruling: "Lockstyle should really be
> able to exist on its own 100% within DLAC." The durable law is *never cross the bus*, and
> the shortest bus-free path put the executor with the trigger, not in the Engine. **This
> document is kept ONLY as the fallback design** if the phase-1 injection spike (outgoing
> 0x053 from the Addon state reaching the server) fails; see the PRD on #80 and ADR 0014.
> The §1 story, §4 Ashita facts, and §5 code map remain accurate history; the §2 target
> and §6 agenda are the superseded direction — do not implement them unless the spike
> fails.

**Tracker: [issue #80](https://github.com/henkpoa/dlac/issues/80)** — the
reference number for this whole effort; the PRD and its issues chain from it.

**Status:** SUPERSEDED — see the banner above. (Original status: NOT STARTED
— this document was the grill/PRD input; Henrik's call,
2026-07-23: "Can't we just move it to the engine side completely instead of
troubleshooting an issue that shouldn't be there in the first place?").
**Base:** engine v109 / addon 2026.07.23l, field-confirmed working on both
Henrik's and the friend's machines. The refactor relocates *working,
understood* code.

**How to use this doc:** a fresh session grills Henrik over the open
questions (§6), produces a PRD, then issues (`/grill-with-docs` →
`/to-prd` → `/to-issues`). Everything referenced here is in this repo —
read §7's list before grilling.

---

## 1. The story (why this refactor exists)

dlac is two Lua states: the **addon** (GUI/editing, what Ashita loads) and
the **engine** (dispatch.lua + 4 library files, seeded into `<char>\dlac\`,
loaded inside LuaAshitacast's state by the job shim). A friend's report —
"everything works BUT lockstyle: preview fine, Apply silently does nothing"
— took a week of instrumented rounds (2026-07-23, docs/history.md) and
ended with three field-established laws:

1. **The command bus between states is unreliable by design.**
   `e.blocked = true` stops LATER addons in Ashita's chain from receiving a
   command, and `/addon reload` order IS chain order. Proven from both
   directions in one day: Henrik's reload cycles deafened his ADDON state
   (engine heard, addon inert); the friend's order starved his ENGINE
   (addon heard, engine never saw the command — his engine was alive the
   whole time, stamped in modestate).
2. **Files are the reliable cross-state channel.** The debug section's
   handoff/request files (stamped with `os.time()`, watched on ticks with
   freshness + idle gates) worked in every order/hearing combination.
3. **The engine is the reliable executor.** Everything living entirely
   engine-side (all automations — they ride LAC's internal handler flow,
   no bus) "always works". The engine also SELF-SWAPS updates into running
   games (content-keyed, v102); the addon state waits for manual reloads —
   the mid-session staleness that burned several field rounds.

Lockstyle apply was the ONE player feature whose trigger crossed the bus
(`/dl ls apply`, queued by the GUI button and the OnLoad/keep/town pumps,
or hand-typed). v109 bridged it: the apply now also rides the request file
(`debug-request.txt` → the engine's request watch → `engineApplyHalf`),
which is what fixed the friend. The bridge is a workaround wearing the
right architecture's clothes — this refactor finishes the thought.

## 2. Target architecture (Henrik's ruling)

| Component | Today | Target |
|---|---|---|
| Boxes editor / picker GUI | addon (feature/lockstyle.lua) | addon (unchanged) |
| Look preview (0x051 local inject) | addon (feature/lookpreview.lua) | addon (unchanged — client-local visual) |
| Apply executor (0x053 build + inject) | engine (`engineApplyHalf`, dispatch.lua) | engine (unchanged) |
| OnLoad pump (login/job-change apply) | **addon** (lockstyle.lua `M.pump`) | **engine** |
| Keep-on-sub machinery (0x100 obs, heal timers) | **addon** | **engine** |
| Town picks (townOff/townBox transitions) | **addon** | **engine** |
| Zone guard (packet_out 0x053 block/verdicts) | **addon** | **engine** |
| Last-applied memory (`lastBox`) | **addon** | **engine** |
| Cross-wall channel | command bus + v109 request file | **files only** |

End state: the addon EDITS (writes the boxes file, sends file-nudges for
button presses), the engine EXECUTES — the exact relationship the
automations have always had, which is why they never break.

## 3. What the move buys

- The command bus disappears from lockstyle entirely: no chain-order bug
  class, ever, for any user's addon load order.
- Engine self-swap means lockstyle EXECUTION fixes reach running games
  without `/addon reload` (the addon-editor half still needs reloads, but
  editors can be stale harmlessly; executors cannot).
- One state owns the whole timing story (login grace, keep heals, town
  delays, guard windows) next to the job-identity machinery the engine
  already runs.
- dlac's `/dl ls` command surface can collapse to ONE claiming state
  (chain-order-proof for typed commands too — the deafness bugs came from
  BOTH states claiming `/dl`).

## 4. Risks and assets

**Risk: the moving code is the most field-hardened in the addon.** The
keep/guard/town machinery cost six field rounds of packet-timing lessons
(docs/history.md, the lockstyle zone-drop investigation; the round-4 "the
kill schedules the cure" heal trigger; town apply delays). Port it, don't
rewrite it.

**Asset: the LGF/LGW/LG* headless suites** (tests/run_tests.lua) drive the
pump/guard/keep chain end-to-end with fake clocks and fixture config trees
— they move with the code and are the regression net. The AG suite pins the
apply's pure core; DBG/DBR pin the debug/request machinery.

**Risk/first: the guard needs packet events in the LAC state.** The engine
today registers `command` + `d3d_present` there; packet_in/packet_out from
seeded code is new territory (expected to work — Ashita events are
per-registration — but prove it FIRST, it gates the whole plan).

**Asset: the engine can require addon-TREE pure modules.** The shim's boot
line puts `addons\?.lua` on LAC's package.path — dispatch already requires
`dlac\data\zones`, `dlac\data\nativemp`, `dlac\feature\mpbands` this way.
So the ported machinery can live in a module (working name
`feature/lockstylecore.lua`) instead of +400 lines in dispatch.lua.
Caveat: required modules do NOT self-swap (only dispatch.lua does) — an
update to lockstylecore needs a Reload LAC, same as mpbands today.

**Known Ashita facts to carry** (proven this week, recorded in
docs/history.md): engine-injected 0x053s DO fire the addon state's
packet_out (so they will fire the engine state's too — same mechanism);
`os.clock()` is wall-clock in this environment; a state never hears its
own queued commands OR the chain blocked it first (round-6's observation
is compatible with both — the move makes the distinction moot).

## 5. Current code map (read before grilling)

- feature/lockstyle.lua — the whole addon half: GUI, `M.pump()` (OnLoad /
  keep / town), the guard (`M._lsGuard` + packet handlers), `queueCmd`
  (v109 request-writes), `M.debugLines()`, capture API.
- dispatch.lua — `engineApplyHalf` / `engineCheckHalf` / `engineLsHalf`
  (one-implementation-two-doors), the request watch + `M._reqFire` /
  `M._reqSpec`, `M._lockstyleFrom` / `M._lockstylePacket` /
  `M._lsResolvers` / `M._lsStyleGate` (pure core), `M._lsDbg*` (capture).
- feature/debug.lua — the file-channel machinery: `M.deliver`,
  `M._mergeSections`, `M._watchFire`, `M.requestEngine`, receipts.
- feature/lookpreview.lua — preview (stays put).
- feature/location.lua + data/zones.lua — the town service (engine already
  requires zones; location.lua is addon-side — decide its fate in §6).
- docs/history.md — the 2026-07-23 session entries (the whole saga, the
  laws, the confirmations) and the earlier "lockstyle zone-drop
  investigation" entry (the guard's field history).
- docs/adr/0002 (engine/addon boundary), 0012 (Arbiter — how engine-side
  subsystems register claims, if lockstyle apply should ever contest slots
  — it should NOT, lockstyle is visual-only; noted to preempt the grill).

## 6. Open design questions (the grill agenda)

1. **Module home:** `feature/lockstylecore.lua` required by the engine
   (mpbands precedent) vs folded into dispatch.lua. Core does not
   self-swap; dispatch does. Where does each moved piece land?
2. **Command surface:** post-move, who claims `/dl ls ...`? Proposal: the
   ENGINE claims apply/state; the addon claims only window-open — but
   typed window-open then dies on Henrik-order chains. Does window-open
   move to a file-nudge too ("engine hears, files the addon")? Or does
   `/dl ls` stay dual-claimed with the request bridge as permanent
   belt-and-braces?
3. **GUI state readouts:** the window shows keep/guard/town live state and
   `/dl ls state` prints it. Post-move that state lives engine-side — does
   the engine mirror it to a statefile the GUI reads (modestate pattern),
   or does the readout thin out?
4. **The v109 request bridge:** keep permanently (belt-and-braces, costs
   nothing) or retire once the bus is out of the picture?
5. **Migration shape:** staged (guard first? pumps first? apply-trigger
   files first?) vs big-bang with the LGF suite as the gate. What is the
   smallest first slice that proves packet events in the LAC state?
6. **location.lua:** town detection is an addon feature module consumed by
   the moving pumps. Engine-require it as-is (it is pure-ish), split a
   pure core, or duplicate the zone check engine-side?
7. **Failure modes:** with execution engine-side, "LAC not loaded / no
   shim" now means lockstyle fully dead (today the GUI+preview survive).
   Acceptable (automation is equally dead there, Setup is the cure) — or
   does the addon keep a degraded direct-apply fallback (the old
   addon-side-apply idea) for shimless setups?
8. **What does /dl debug ls become** once both halves' machinery is
   engine-side? (Likely: engine produces the whole report; the addon adds
   only GUI-side facts. Simplification, not loss.)

## 7. Reading list for the grilling session

1. This document.
2. docs/history.md — every entry dated 2026-07-23 (bottom of file), plus
   "lockstyle zone-drop investigation".
3. feature/lockstyle.lua header comment (the feature's own spec).
4. dispatch.lua v102–v109 changelog lines (the week, compressed).
5. tests/run_tests.lua — the LGF section header (what the net covers).
