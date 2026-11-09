# AutoAcc stuck on "Starting": start telemetry when dlac loads in game

**Written:** 2026-11-09, from an AscensionXI session (a read-only look at prod plus
two players' wire logs).
**For:** the dlac agent who builds the fix.
**State:** diagnosed, not built. This branch, `claude/autoacc-start-in-game`, holds only
this document. Build the fix here, so the diagnosis and the code ship in one PR.
**Owner's condition:** *"That sounds good, as long as it doesn't spam the server if there
is a real problem."*

## TL;DR

- **Symptom.** `/dl acc` (the accuracy box) says **Starting** and never shows a monster.
  AutoAcc keeps every piece on. `/addon reload dlac` does not help.
- **Cause.** The telemetry client starts only when it sees a zone-in packet (0x00A).
  If dlac finishes loading after that packet (a slow load at login, a reload or a load
  in game), the client stays in phase `off` until the player's next zone change. Nothing
  else starts it, and the box shows `off` as "Starting".
- **Fix.**
  1. Start the client when dlac is loaded in game.
  2. Recover from a HELLO reply that names another character.
  3. Make every automatic re-HELLO back off, so a server that really is not answering
     hears from a client a few times a minute, not about 40.
- **Player workaround until it ships:** cross any zone line with dlac loaded (not a relog,
  not a reload). The box connects within a few seconds.

## 1. The report

Player **Fallen** on prod (charid 16, WAR75/DNC37, The Boyahda Tree, map process
`map-outlands`) opened `/dl acc`. The box showed **Starting** and the AutoAcc rows
(Head Precision Bandana, Neck Peacock Charm, Ear2 Fowling Earring, Waist Virtuoso
Belt) but never a monster. He reloaded dlac and it still said Starting. The owner says it
has happened to him before and may not be his alone.

## 2. Evidence

### 2.1 The server is fine (prod, read-only, 2026-11-09)

- Prod runs AscensionXI `eb8ad6fb6fd6` (image `sha-eb8ad6fb6fd6`, deployed 2026-11-08
  13:15 UTC), which pins dlac `dcc8caa` (2026.11.07b) in `client/addons/catalog.json`.
  The telemetry files on dlac `main` (`e7de8d9`) are identical to that pin.
- `modules/custom/lua/combat_telemetry.lua` is listed in `modules/init.txt`.
  `void_storage.lua` routes ops 0xC0–0xCF to it.
- Over 20 hours of `map-outlands` logs: no telemetry errors and no `Rate-limiting packet`
  lines (the server's warning when it drops a 0x1E0 frame).
- The server logs nothing per HELLO. Its logs cannot show whether one arrived, but the
  client's wire log can (next section).

### 2.2 Fallen's wire log: dlac never sent a HELLO

The file was `config\addons\dlac\Fallen_16\debug\gear-vault-wire.log` on his machine. It
covers two sessions (2026-11-06 15:37–15:53 and 2026-11-09 07:26–07:36, his clock about
UTC). It has **zero lines for ops C0–CF**: no HELLO, WATCH or anything else from
telemetry, in either session. Everything else worked. The 11-09 session, requests only:

```
07:26:05 enqueue op=A0 seq=142 ascension status     <- server logged the login at 07:26:01.9 UTC
07:26:09 enqueue op=40 seq=3   gear vault           <- then a normal vault sync, all answered
...      op=49 every minute, op=A0 every minute
07:31:34 enqueue op=A0 seq=215 ascension status     <- /addon reload dlac (seq counters restart)
07:31:34 enqueue op=40 seq=57  gear vault
...      (no op=C0 to the end, 07:36:35)
```

That session had only three foreign 0x1E0 frames (Nexus) and no `yield` lines. So the
send gate was free, and telemetry simply never asked to send.

### 2.3 The owner's login the same morning, which works

Mindie on prod, server login 07:47:58.0 UTC, client clock UTC+1:

```
08:47:51     load-report.txt: "dlac 2026.11.07b loading at 08:47:51" (finished by 08:47:51.39)
08:47:57.5   Ashita log: "Patched log file path! [Path: TEMP/Mindie]"   = the login
08:48:00     enqueue op=40 gear vault
08:48:01     enqueue op=C0 combat telemetry -> reply op=C0 the same second
08:48:01     enqueue op=C1 combat telemetry -> reply
08:48:02     enqueue op=A0 ascension status
```

### 2.4 What the order tells us

dlac's other two modules start on a zone-in and also have an on-load path, so the order
of the first requests shows which path ran:

- **Ascension status** (`servers/ascensionxi/modules/ascension/status.lua`): `zoneIn` (line
  42) waits `SETTLE` = 5 s; `reset()` at load (line 55) asks as soon as job levels read
  above zero.
- **Gear vault**: syncs about 2–3 s after a zone-in.

The owner's order was vault +2 s, HELLO +3 s, ascension +4 s: the zone-in path.
Fallen's was ascension +3 s, then vault +7 s: the on-load path, the same order his reload
produced at 07:31:34. **So Fallen's dlac finished loading about 3 s after his login
zone-in.** The order argument does not depend on the two clocks agreeing: the two
requests are 4 s apart in the wrong order.

Not known: why his dlac loads that late. The launcher's boot script loads dlac at
startup, and on the owner's machine it loads in under a second, 6.5 s before login. The
fix does not depend on the answer.

### 2.5 Seen but not investigated

Fallen's 11-06 session ran 16 minutes with ascension polls every 60 s and **no gear vault
traffic at all**. It may be another late-load symptom. It is not needed for this fix.

## 3. The defects (dlac `main` `e7de8d9`)

All paths are under `servers/ascensionxi/modules/telemetry/` unless named.

**D1. Nothing starts the client without a zone-in.**
- `init.lua:152` keeps `_charId`, which is set only by the 0x00A tap at `init.lua:201-205`,
  which then calls `client.zoneIn()`.
- `client.lua` `M.reset()` leaves the phase `off`, and `M.pump()` (`client.lua:248`)
  returns immediately in `off`.
- The box draws any phase other than `live` and `dormant` as **Starting**, with the hover
  "Connecting to the server." (`monitor.lua:221`).

So any dlac that loads after the zone-in never connects until the next zone. That covers
a slow load at login, `/addon reload dlac` and `/addon load dlac` in game. The box's
demand cannot help: `monitor.drawBody` calls `client.wantTarget()` every frame
(`monitor.lua:377`), but `pump` ignores demand in `off`.

The gear vault already solved this. `gearvault/vaultclient.lua:1910` `M.pump(ready)`:
*"First readiness of the session (addon load mid-session included, where no zone-in
packet will ever arrive)"*. `ready` means the main job is not 0
(`gearvault/init.lua:316, 591, 603`), and a `zoning` flag runs from 0x00B until the new
zone settles. Ascension's `status.reset()` is the second example. Telemetry has neither.

**D2. A HELLO reply naming another character stalls the client for good.**
`client.lua:351` returns when the reply's `charId` differs from `_charId`. By then
`M.onFrame` has already cleared `st.pending` (`client.lua:447`) and freed the transport
slot. The phase stays `hello` with nothing queued, and `pump` never queues again. The box
shows "Starting" until a zone change. This is rare, but nothing recovers from it. Once D1
reads the id from memory, make sure it cannot become a new way in.

**D3. A server that does not answer gets a HELLO every 1.5 s, without end.**
In `client.lua:248-264`, an unanswered HELLO is re-sent `TRIES` = 3 times, `RETRY` = 1.5 s
apart. Then it escalates (`client.lua:263`, `st.phase = 'hello'; queue('hello')`), and the
same pump call starts a new HELLO. The result is one HELLO every 1.5 s, about 40 a minute
per client. It lasts as long as the session is wanted: the box is open, or under 5
minutes have passed since AutoAcc last asked. Only UNAVAILABLE backs off
(`BACKOFF` = 30 s, `client.lua:335`).

This is the "real problem" case the owner means. D1's fix sends more clients down this
path (every in-game load), so bound it in the same change.

## 4. What to build

**R1. Start in game.** Start the client exactly as `zoneIn` does (phase `settling`,
`SETTLE` 3 s) when all of these hold:
- the client is `off` because no zone-in was seen since load;
- the player is in game (main job not 0, the vault's test);
- no 0x00B has arrived without its 0x00A.

Take the id from `AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)`, which
dlac already reads in `dlac.lua:596`, `feature/engagewatch.lua` and others. That value is
the server's character id, which the HELLO reply's `charId` is checked against.

- Before login (title screen, character select) the main job reads 0, so nothing starts
  and the login 0x00A starts the client as it does today.
- Never start between a 0x00B and the next 0x00A: memory is stale mid-zone.
- Start once per load. A later 0x00A takes over exactly as today.
- Keep the memory reads behind seams in `init.lua` (say `client._inGame` beside `_charId`,
  `_engaged` and `_cursorTarget`) so `client.lua` stays headless-testable.

**R2. No stall on a foreign reply.** A HELLO reply that names another character counts as
a failed attempt and goes to R3's backoff. It must never leave the phase at `hello` with
nothing queued.

**R3. No spam (the owner's condition).**
- After each failed HELLO round, the next round waits a backoff that grows. I suggest
  5 → 10 → 20 → 40 → 60 s and then stays at 60. A failed round is the `TRIES` sends gone
  unanswered, or a foreign reply.
- At most one round per backoff window.
- Reset the backoff on an accepted HELLO reply or a zone-in. Box demand does not reset it.
- The resulting bound: a server that never answers sees at most 3 HELLOs a minute from
  one client, against about 40 now. If you prefer to stop entirely after N rounds until
  the next zone-in, do so, but write the bound down.
- Keep the existing answers as they are: BUSY (`BUSY_WAIT` 1.2 s), UNAVAILABLE
  (`BACKOFF` 30 s), BAD_OP and PROTO_UNSUPPORTED (dormant).
- WATCH and RESYNC escalations that end in a HELLO go through the same backoff.

What the bound sits against on the server (AscensionXI repo):
- `combat_telemetry.lua:37-40`: one HELLO per second per character (else BUSY), a 45 s
  lease, renew after 15 s, a 5 s replay window for a retried nonce.
- `src/map/packet_system.cpp:389`: the 0x1E0 ingress limit, 50 ms, shared by every module
  and addon.

**R4. Say it, once.** While backing off after failures, the box must not say "Starting"
indefinitely. Follow the minimal-box rule (decision 10 in
[ascensionxi-combat-telemetry-autoacc.md](ascensionxi-combat-telemetry-autoacc.md)): a
short label with a hover, only while something is wrong. The existing **Unavailable**
label with a hover like "The server isn't answering; DLAC will try again." fits. Do the
same for the Gear Helpers row's text in `monitor.status()`. The wording is yours
(HANDOFF.md, "Working with Henrik").

**R5. Recommended: make the start visible.** Add one line in `gear-vault-wire.log` when
the client starts without a zone-in, and one when it backs off. The transport writes
only `enqueue` and `reply` lines. "Telemetry never asked" took two players' logs and a
timing argument to prove; a single line would have shown it directly.

No version bump of `dispatch.M.VERSION`: engine behaviour does not change. Bump
`addon.version` in `dlac.lua` (`YYYY.MM.DD` plus a letter, step 4 of the release routine).

## 5. Tests owed

Baseline, measured 2026-11-09 on `dcc8caa` with `%LOCALAPPDATA%\Programs\Lua\bin\lua.exe`:
`ascensionxi_telemetry_client.lua` 135, `ascensionxi_telemetry_wire.lua` 90,
`ascensionxi_autoacc_ui.lua` 367, all passed.

New cases (client cases in `tests/ascensionxi_telemetry_client.lua`, UI cases in
`tests/ascensionxi_autoacc_ui.lua`):

1. Loaded in game with demand: one HELLO within `SETTLE`, no zone-in needed.
2. Loaded before login (main job 0): nothing until the 0x00A, then exactly one HELLO.
3. Loaded in game, then a 0x00A arrives: still one session at a time; the zone-in replaces
   it as today.
4. Between a 0x00B and its 0x00A: no start.
5. A HELLO reply naming another character: backoff, then retry; never stuck.
6. A silent server for 10 simulated minutes with the box open: the HELLO count stays
   within R3's bound and follows its schedule. An accepted reply resets it.
7. The box's label and hover during backoff.

Add a guard to `tests/autoacc_mutation_sweep.py` for each rule: the in-game gate, the
zoning gate, backoff growth, its cap, its reset, and the foreign-reply recovery. Then run
the usual set (the sweep needs a clean tree, so commit first):

```
cd C:\repos\dlac-autoacc-start-in-game
& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\ascensionxi_telemetry_client.lua
& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\ascensionxi_telemetry_wire.lua
& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\ascensionxi_autoacc.lua
& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\ascensionxi_autoacc_dispatch.lua
& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\ascensionxi_autoacc_ui.lua
& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\run_tests.lua
python tests\autoacc_mutation_sweep.py
```

## 6. Live checks for the owner

Install the branch build where the owner asks (HANDOFF.md: `C:\AscensionXI-Prod\Ashita\addons\dlac`
only on his request; the launcher may put the pinned version back). The wire log is at
`C:\AscensionXI-Prod\Ashita\config\addons\dlac\<Name>_<id>\debug\gear-vault-wire.log`.

1. In game, `/addon reload dlac`, then `/dl acc` and target a monster. The box shows the
   monster's name and level within about 5 s **without zoning**. The log shows one
   `enqueue op=C0` a few seconds after the reload, then `reply op=C0`.
2. Fresh login with the box open: exactly one `enqueue op=C0` after the login, not two.
3. Cross one zone line: one new `op=C0` after the zone.

A silent server cannot be produced in a live client without changing the server, so case
6 is proven headless only.

## 7. Shipping

This branch → PR to dlac `main` → Henrik merges. Then the AXI pin bump, following
[ascensionxi-release-routine.md](../reference/ascensionxi-release-routine.md): AXI
`client/addons/catalog.json` gets the new sha, a merged pin PR reaches staging by
itself, and prod changes when a human promotes the channel. No server change is needed.

The pin PR can add one sentence to AXI's `documentation/custom/combat-telemetry.md`
("What dlac does with it"): dlac starts a session when loaded in game, and backs off
when the server does not answer.

## 8. Where things stand

- **Branch:** `claude/autoacc-start-in-game` from `main` `e7de8d9`, worktree
  `C:\repos\dlac-autoacc-start-in-game`. This document is the only change.
- **Start here:** §3, then `client.lua` (`M.pump`, `onHelloReply`, `M.onFrame`), then
  `init.lua` (the 0x00A tap and the seams), then `vaultclient.lua` `M.pump(ready)` for the
  pattern to copy.
- **Nothing to clean up:** prod was only read. No server or client state was changed.
- **When done:** add a `Status` section to
  [ascensionxi-combat-telemetry-autoacc.md](ascensionxi-combat-telemetry-autoacc.md) and
  turn this document's state line into "built".
