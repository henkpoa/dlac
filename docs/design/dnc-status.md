# Dancer status (AscensionXI)

**Status, 2026-10-10:** built and tested headless (`tests/ascensionxi_dncstatus.lua`); not yet
seen in game. The server half is an AscensionXI draft PR (branch `claude/dnc-status`,
`modules/custom/lua/dnc_status.lua`), whose design record is
`documentation/custom/dnc-status.md` in that repo. The window is empty in game until that PR
deploys: dlac draws nothing until the server has sent a state.

## What it is

AscensionXI gives the Dancer two abilities whose state the client cannot show:

- **Perpetual Step** remembers the Steps on the party's last kills (the best level per Step, for
  60 seconds) and puts them back on the next monster. It puts on 1 level plus 3 per Unbroken
  Rhythm stack, or all of them under Trance.
- **Unbroken Rhythm** sells those stacks for TP: 600, 900, then 1200, and 1200 again to refresh at
  three. Each stack drops 60 seconds after the last one.

The memory is the buff's power, which the client never receives. The Dazes on a monster are
invisible to the client too. The **DNC Status** Job helper (`jobhelpers\dnc\dnc-status`, the
module PR #201 proposed) shows three things, each with its own switch:

- **Perpetual Step:** the remembered Steps, how long the memory lasts, and how many levels of
  each it puts on now ("Quickstep 5, puts on 4").
- **Unbroken Rhythm:** the stacks, when the next one drops, and the next stack's price. The price
  turns orange when your TP is short of it.
- **Steps on your target:** the monster you are fighting, and each Step on it with its level and
  time left.

The lines appear in the helper's Panel and in a small floating window. The window shows itself only
while it has something to show: a memory, stacks, or a fight. In town it stays away. It can be
dragged (its place is remembered once the drag settles), locked, or switched off, and it hides
with the game HUD. The module never acts: no commands, no keys, no gear.

On AscensionXI the Job Helpers tab is on (`servers/ascensionxi/features.lua`), and DNC Status is
its only helper (the pack's `jobhelpers` list). The module declares `servers = { 'ascensionxi' }`,
so it never loads on CatsEyeXI. `/dl jh` lists any helper a server leaves out.

## Files

| File | Role |
|---|---|
| `servers/ascensionxi/modules/dncstatus/wire.lua` | Pure codec. The contract is the AXI repo's `job_gauge_wire.lua`; a shared 28-byte vector is pinned in both suites |
| `.../dncstatus/status.lua` | Pure client state: when to subscribe, and the view that joins the client's own buffs with the server's facts |
| `.../dncstatus/init.lua` | Ashita glue: the shared 0x1E0 gate, the slot-1 tap, the client reads (job, level, TP, buffs and their timers, entity names), zone and unload edges, `/dl dnc`, the `dncStatus` service |
| `jobhelpers/dnc/dnc-status/init.lua` | The Job helper: switches, the Panel, the window |
| `servers/ascensionxi/transport.lua` | `producerOf` names slot 1 of 0xD0-0xDF `dnc status` |
| `servers/ascensionxi/features.lua` | Job Helpers tab on; `jobhelpers = { ['dnc-status'] = true }` |
| `feature/jobhelpers.lua` | The pack's helper list, and a module's `servers` (both skip quietly; `/dl jh` names them) |
| `feature/modapi.lua` | `S.server.service(name)`: a pack service for a helper |
| `tests/ascensionxi_dncstatus.lua` | Headless suite (104 checks) |
| `tests/dncstatus_mutation_sweep.py` | Breaks each guard once; 34 of 34 caught on 2026-10-10 |

## The wire

The 0xD0-0xDF "job gauges" partition is shared by job: the slot is `op % 8`. Slot 0 is the White
Mage flower gauge (0xD0, 0xD8), slot 1 is the Dancer (0xD1 SUBSCRIBE, 0xD9 STATE). Each module's
tap reads only its own slot. `wire.lua`'s header has the byte layout. In short, the 28-byte STATE
carries:

- the Perpetual Step power (four bits per Step);
- the battle target's entity index (0 when not engaged to a live monster);
- each Step's Daze level on it, and the seconds left;
- the three Unbroken Rhythm prices;
- the base level and the levels each stack adds;
- a revision counter.

## Packet budget (the AutoAcc lesson)

The client asks for nothing it can see itself:

- its job, level and TP;
- the Perpetual Step buff's timer (status icon 472);
- the Unbroken Rhythm stacks (icons 624, 634 and 635) and their timer;
- Trance (376).

Timers come from `GetStatusTimers`, decoded by foodwatch's `_remaining`. The server sends only
what it alone knows.

- **One request per zone, only on demand.** `SUBSCRIBE` goes out 3 s after zone-in, only while
  the main job is Dancer **and** the window or the Panel is showing the status (`want()` within
  2 s). A Dancer with both off sends nothing and costs the server nothing. The server keeps the
  subscription in a local variable, so a zone-out ends it.
- **Pushes only on a change that's drawn:**
  - the memory;
  - the target, including disengaging and its death;
  - a Daze's level, or a Daze appearing or wearing off;
  - a Daze's end moving by 2 s or more (a new Step);
  - the prices or caps.
  The client counts the seconds down itself, so a fight with no new Steps pushes nothing.
- **Unknown or old servers cost almost nothing.**
  - `BAD_OP` or `UNAVAILABLE`: silent for the session.
  - `BUSY`: retry after 2 s.
  - Silence: back off 5, 15 and 60 s, then silent for the session.
  An AscensionXI server before the Dancer slot routes 0xD1 to the flower gauge, which answers
  `BAD_OP`.
- **Nothing is drawn until the server has sent a state.** The Panel says "Waiting for the
  server." or "This server does not send Dancer status."
- **Unload** sends a stop straight to the packet manager.

## The trust rules

- **The memory follows the server.** Its power is 0 without the buff, so presence needs no
  client icon. If the client's icon number were ever wrong, only the memory's timer would go
  missing, never the Steps.
- **The stacks follow the client's icons.** They change on the Dancer's own purchase and on each
  drop, and the client sees both at once. Sending them would double the pushes for something
  already on screen.
- **A Daze that runs out** leaves the list on the client's own count, before the server's push
  confirms it.

## Commands

`/dl dnc` prints the channel's state and the last frame, for field rounds. Everything else is in
the Panel (Job Helpers > DNC > DNC Status).

## Field checks owed

With the AscensionXI branch running on the local shard, as a main Dancer 30+:

1. The Panel shows "Waiting for the server." until the first state, then the three sections.
2. Kill a stepped monster: the window appears with the memory and its 60 s countdown.
3. Buy Unbroken Rhythm stacks: the count, the drop timer and the next price follow (600, 900,
   1200, then "Refresh 1200"), orange when TP is short.
4. Step a monster: the target section names it and counts each Step down; a second Step
   updates it within half a second; Perpetual Step's re-application shows.
5. Disengage, or the monster dies: the target section goes.
6. In town with nothing remembered and no stacks: no window.
7. The window drags, remembers its place after a reload, locks, and hides with Scroll Lock.
8. `/dl jh` on AscensionXI lists DNC Status, and names `bst-helper` and `bludex` as not loaded.

Stub-imgui tests can't catch width or printf problems. A screenshot is the test for those.
