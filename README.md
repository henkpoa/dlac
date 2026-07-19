# dlac — dynamic LuaAshitacast

A GUI companion for **LuAshitacast** (Final Fantasy XI on Ashita v4, built for
**CatsEyeXI**) that removes the Lua editing from gear automation: build sets, wire
them to game events, toggle combat modes, and let situational gear resolve itself —
all from a window in game.

**Nothing dlac does requires you to open or edit a Lua file.** The files stay
hand-editable for power users, but they are storage, not the interface.

**New to LuaAshitacast or gear automation entirely?** Open
[docs/guide.html](docs/guide.html) in a browser — a from-zero walkthrough of sets,
triggers, modes, and the automations.

## Setup — two clicks per job

You need a working LuaAshitacast install (it's part of the CatsEyeXI client).

1. **Install** — drop the `dlac` folder into `Ashita\addons\`, then
   `/addon load dlac` (add that line to your Ashita boot script to load it every time).
2. **Open the GUI** — **CTRL+K** (or `/dl ui`).
3. Click the red **Setup** button (top-right). Works on *any* profile, and always
   ends the same way — **your live `<JOB>.lua` becomes a small clean dlac shim**:
   - your existing profile — whether ffxi-lac, hand-written, or anything else — is
     first copied to `backups\pre-profiles\` and **verified byte-for-byte**, then
     replaced. Old logic never stays live: one equip engine, no conflicts;
   - nothing is lost — your old **static sets** (including `_Priority` lists, order
     kept) import via **"Copy from"** in the Sets tab, your old **group tables** via
     **"Scan my Lua"** in the Triggers tab's Groups box, dynamic sets move over
     automatically, verbatim;
   - a job with no profile gets the same clean shim from scratch;
   - the four base sets (Idle / Tp_Default / Resting / Movement, empty), the starter
     trigger rules that target them, and your gear database are seeded automatically —
     nothing complains out of the box.
4. LuaAshitacast reloads by itself (fresh jobs: click **Reload LAC**).

That's it. Your gear imports itself (bags are auto-scanned on pickup, login and job change),
and from here on everything is GUI work. Repeat for each job.

## What you get

| Tab | Does |
|---|---|
| **Equipped** | Live 16-slot view, worn stat totals (augment-aware), per-slot alternatives, slot locking |
| **All Equipment** | Browse everything you own — or the full CatsEyeXI catalog — with search and stats |
| **Sets** | Build sets by hand or **Auto-build** from stat weights; level-scaling candidate lists per slot; live score |
| **Triggers** | Wire sets to the game: statuses, spells (by skill / type / element / `contains` / exact name), abilities, items, weaponskills, **player state** (HP/MP — raw or percent — TP, active buffs & debuffs) with **AND/OR condition groups** — plus player-defined **Modes** with live toggle buttons |

### Triggers, in short

A trigger is *condition(s) → set*. All matching triggers apply, most specific last, so
partial sets **overlay**: your general Enfeebling set equips, then White-Enfeebling
over it, then your dedicated Slow set on top. Conditions stack with AND
(`skill = Elemental Magic` + `contains = Stone` = every Stone tier). Trigger edits are
**live on the next action** — no reload. `/dl why` explains exactly what fired and why.

### Modes

Named switches that triggers can match. Two kinds:

- **Toggles** (e.g. `DT`) — on/off; overlay your damage-taken set over whatever else
  won. Highest priority: manual intent always wins.
- **Cycles** (e.g. `Weapon`: Melee → Ranged → Caster) — an ordered value list, exactly
  one active; rules match a value with `mode = Weapon:Melee`. This replaces the classic
  hand-written "variant table + HandleCommand arithmetic" pattern entirely.

Flip them from the Triggers tab buttons (cycles show their current value), by chat/macro
(`/dl mode dt`, `/dl mode weapon`, `/dl mode weapon caster`), or give a mode an optional
**keybind** in the GUI — applied automatically at profile load, no OnLoad code.

### Automations (auto staff / auto obi)

Put the virtual entry **`dlac:AutoStaff`** in a set's Main slot (or **`dlac:AutoObi`**
in Waist) via the normal **+ Add** picker. At cast time dlac equips:

- **Staff** — your best *usable* Iridescence option for that cast: HQ/NQ elemental
  staff vs a universal weapon (Chatoyant Staff, Foreshadow +1, Iridal Staff), highest
  tier wins, ties go to the universal.
- **Obi** — the matching elemental obi (or the universal Hachirin-no-obi) only when
  the day/weather bonus for the spell's element is net positive.

Everything is level-checked, and the other items in the same slot list act as the
fallback — being under-leveled never blocks the slot. Owned staves/obis are
re-detected automatically on login/job change.

## Commands

`/dl` (or `/dlac`):

| Command | Does |
|---|---|
| `/dl ui` | Open/close the GUI (also bound to **CTRL+K**) |
| `/dl mode <name> [on\|off\|toggle]` | Flip a mode (no name: list active modes) |
| `/dl lock <slot\|all> [on\|off\|toggle]` | Lock a slot: the engine stops equipping into it (no arg: list locks) |
| `/dl why` | Explain the last dispatch per handler — what matched, what equipped |
| `/dl env` | Day/weather as dlac sees it + per-element obi math |
| `/dl triggers reload\|init\|path` | Force re-read / seed / locate the trigger file |
| `/dl sync` | Import new gear from bags now (also runs automatically) |
| `/dl prune` (then `/dl prune commit`) | Remove gear.lua entries for items you no longer own anywhere — dry-run first; checks every container incl. storage |
| `/dl weight` / `best` | Stat-weight helpers for set auto-building |
| `/dl set level main <n>` | Preview as another level |
| `/dl p` / `/dl w` | Panic escape: lock Ring2, equip the Provenance/Warp Ring, wait out its equip delay, use it (`off` cancels) |
| `/dl iw` | Instant Warp scroll: used straight from Inventory — no equip, no lock, no wait |
| `/dl ir` | Instant Retrace scroll: same, back to your Campaign nation |
| `/dl c` | Chocobo Whistle: lock Neck, equip it, call the chocobo the moment the game says ready (`off` cancels) |
| `/dl shirt` | Shadow Lord Shirt: lock Body, equip it, teleport to Castle Zvahl Keep (`off` cancels) |
| `/dl t <where>` | Teleport earring/ring: lock Ear2 or Ring2, equip the matching item (norg, jeuno, sandy, holla, vahzl...), wait, use it — no arg lists destinations |

## Safety

- Setup never deletes your code — your original file is copied to
  `backups\pre-profiles\` and verified byte-for-byte **before** anything is rewritten.
  A first backup is never overwritten (re-runs save a time-stamped copy beside it),
  and the Sets/Groups importers read your old sets and tables from it forever.
- Every file write is parse-checked first and aborts untouched on failure.
- A broken hand-edit to the trigger file keeps the last good rules and reports.

## For developers

**Start at [docs/HANDOFF.md](docs/HANDOFF.md)** — environment, hard rules, and current
state, with a reading order. Then: [CONTEXT.md](CONTEXT.md) (glossary),
[docs/architecture.md](docs/architecture.md) (module map & data flow),
[docs/adr/](docs/adr/) (decision records),
[docs/design/trigger-system.md](docs/design/trigger-system.md) (the trigger engine
spec), and [docs/history.md](docs/history.md) (session journal — including the
dead-ends worth not retrying). dlac is CatsEyeXI-only by design (ADR 0001).

**Repository layout** (full version: [docs/architecture.md](docs/architecture.md)):
the addon root is what LuaAshitacast sees, folders are what only the addon sees.

| Path | What lives there |
| --- | --- |
| root | `dlac.lua` (entry) + the seeded engine: `utils`, `dispatch`, `chatfmt`, `profiles`, `gear` |
| `ui/` | imgui modules (`gearui`, `triggersui`, `uihost`, ...) |
| `data/` | generated/static tables (`catalog`, `crafts`, `statdefs`, ...) |
| `gear/` | the gear pipeline (`gearimport`, `gearoptim`, `setmanager`, ...) |
| `feature/` | self-contained features (`lockstyle`, `craftwatch`, `useitem`, ...) |
| `lib/` | generic helpers (`cmdqueue`) |

The five engine files at root are copied into each character's `<char>\dlac\` folder and
load a second time inside LuaAshitacast's Lua state, so they cannot move into a subfolder:
`require("dlac\\utils")` is published API in every user profile.

## License

MIT — see [LICENSE](LICENSE). dlac works alongside LuaAshitacast but does not bundle it.
