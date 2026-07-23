# dlac — dynamic LuaAshitacast

A GUI companion for **LuAshitacast** (Final Fantasy XI on Ashita v4, built for
**CatsEyeXI**) that removes the Lua editing from gear automation: build sets, wire
them to game events, toggle combat modes, and let situational gear resolve itself —
all from a window in game.

**Nothing dlac does requires you to open or edit a Lua file.** The files stay
hand-editable for power users, but they are storage, not the interface.

**New to LuaAshitacast or gear automation entirely?** Open
[docs/guide.html](docs/guide.html) in a browser — a from-zero walkthrough of sets,
triggers, modes, the automations and their priority ladder, lockstyle, and the
teleport/convenience surfaces.

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
| **Equipped** | Live 16-slot view, worn stat totals (augment- and set-bonus-aware), per-slot alternatives, slot locking, the **floating equipment window** (an always-up 4×4 with right-click item **pins**) |
| **All Equipment** | Browse everything you own — or the full CatsEyeXI catalog — with search and stats |
| **Sets** | Build sets by hand or **Auto-build** from stat weights (**Points** or ordered **Priority** mode); level-scaling candidate lists per slot; live score; **Equip & Lock**; import your old profile's sets via **Copy from** |
| **Triggers** | Wire sets to the game: statuses, spells (by skill / type / element / `contains` / exact name), abilities, items, weaponskills, pets, **player state** (HP/MP — raw or percent — TP, active buffs & debuffs), **in-town**, **target = Self**, with **AND/OR condition groups** — plus player-defined **Modes** with live toggle buttons and the **Blueprints** rule library |
| **Automations** | The self-driving gear family (below) with live per-job coverage, and the **Priority** section — the draggable ladder that referees which automation wins a contested slot |

Beyond the tabs: **lockstyle sets** (the armor header button — your look, in 30
saved boxes per job, with town behaviour), the **Teleports** menu (one click from
anywhere to anywhere, plus quick rows for every automation), per-job **macro
books**, and named **profiles** per character.

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

### Blueprints — share rules like macros

Any trigger rule can be saved as a **Blueprint** (the `bp` button on its row): a
job-independent copy in your per-character library (Triggers tab, Blueprints
section). **Stamp** one onto any job's handler — the stamped rule is an ordinary
trigger afterwards — or **Edit** it in the same rule builder. Blueprints travel as
plain text: **View/Copy** per entry, **Copy all** for the whole library, and
**Import from text** parses a friend's pasted blob with a live preview and
collision choices. The payload is the rule verbatim; a stamped rule that names a
set the job doesn't have simply warns until you create it.

### Automations — gear that picks itself

The **Automations** tab hosts the whole family; each row shows live per-job
coverage, and the same rows appear as quick controls inside the Teleports menu
(left-click opens the panel, right-click toggles). Slot automations are **virtual
entries** you place in a set slot via the normal **+ Add** picker; the other items
in the same slot list act as the fallback, and everything is level-checked and
re-detected on login/job change/inventory change.

- **`dlac:AutoIridescence`** (Main) — your best *usable* Iridescence option per
  cast: HQ/NQ elemental staff vs a universal weapon (Chatoyant/Iridal for anyone;
  job-specific pieces up to Iridescence +3 — Inanna, Keraunos, Gridarvor, the Lv75
  relic staves — rank above them), highest tier wins, ties go to the universal.
  Every owned universal rides a level-ordered ladder, so a level sync falls
  through to the best one you can still wear. CW-only Incursion weapons appear in
  the tab only in CW mode (other modes get a "Show Crystal Warrior gear" preview
  checkbox). *(Sets written as `dlac:AutoStaff` keep working.)*
- **`dlac:ElementalObi`** (Waist) — the matching elemental obi (or the universal
  Hachirin-no-obi) only when the day/weather bonus for the spell's element is net
  positive. *(`dlac:AutoObi` keeps working.)*
- **`dlac:AutoOneiros`** (Sub) — Oneiros Grip while its latent Refresh +1 is
  actually live (MP at or below 50% of your *base* pool — merit-aware, gear
  excluded), your regular grip otherwise.
- **AutoAmmo** (Ammo) — keeps the slot fed per job: your ammo by category
  (Bullets / Bolts / Arrows / Throwing), level-sorted, with the free-WS trio
  recognized; Crystal Warriors get Ephemeral Box counts and one-click fetch.
- **MaxMP** — the battery ladder: when ON, your MP+ "battery" pieces are worn
  while your MP is high (a bigger pool holds more) and each slot hands back to
  the normal set piece as MP falls past that piece's break-even point — strongest
  refresh batteries last, ear/ring pairs kept stable, movement gear allowed
  through while you move. `/dl plan` prints the ladder.
- **Auto Craft / HELM / Fishing sets** — whole-set helpers with their own
  floating bars: craft gear per craft with an HQ / NQ / Skill-Up goal, gathering
  gear while idle near a HELM point, fishing gear that re-ranks rod/bait every
  heartbeat (Ebisu > Lu Shang's > base at equal risk) with rod/bait pins on the
  bar. Gear only — dlac never automates the activity itself.

### Priority — who wins a contested slot

Automations claim slots; the **Priority** section (Automations tab) is ONE
draggable ladder that referees them: Pins, the **Locks veto row** (a claimant
above it punches through a locked slot, one below it stops), AutoAmmo, MaxMP,
Craft, HELM, Fishing, and the immovable **Triggers floor** — what you wear when
no claim wins. Reordering is live, no reload. `/dl prio` prints the ladder with
live claim status; `/dl why` names the winning claimant and its rank per slot.

### Lockstyle sets — your look, not your gear

The armor button in the header opens the lockstyle window: build a *look* in the
same 4×4 grid (one item per visual slot — the server happily styles off-job and
under-level gear) and save it into numbered boxes, stored **per job**. The
preview is client-side and equips nothing — tick "Show gear I don't own" to try
looks on before hunting the pieces (Save is what enforces ownership). **OnLoad
Lockstyle** applies your marked box on login and job change; **Keep on sub
change** re-applies it after subjob flips (the game clears style lock there);
in towns, choose either **Disable in town** (drop the style so your real gear
shows) or a dedicated **town box** worn while you're there. The picker offers
anything *any* of your jobs can wear at its current level.

## Commands

`/dl` (or `/dlac`):

| Command | Does |
|---|---|
| `/dl ui` | Open/close the GUI (also bound to **CTRL+K**) |
| `/dl mode <name> [on\|off\|toggle]` | Flip a mode (no name: list active modes) |
| `/dl lock <slot\|all> [on\|off\|toggle]` | Lock a slot: the engine stops equipping into it (no arg: list locks) |
| `/dl why` | Explain the last dispatch per handler — what matched, what equipped, which claimant won each contested slot and at what rank |
| `/dl prio` | The live claim-priority ladder (Pins / Locks veto / automations / Triggers floor) with per-claimant status |
| `/dl plan` | The MaxMP battery ladder: release order, thresholds, live state per band |
| `/dl env` | Day/weather as dlac sees it + per-element obi math |
| `/dl triggers reload\|init\|path` | Force re-read / seed / locate the trigger file |
| `/dl sync` | Import new gear from bags now (also runs automatically) |
| `/dl prune` (then `/dl prune commit`) | Remove gear.lua entries for items you no longer own anywhere — dry-run first; checks every container incl. storage |
| `/dl fix` | Re-stamp gear.lua entries with fields the scan has since learned (reserved slots etc.) |
| `/dl ls apply [box]` | Apply a saved lockstyle box (GUI: the armor header button) |
| `/dl weight` / `best` | Stat-weight helpers for set auto-building |
| `/dl set level main <n>` | Preview as another level |
| `/dl p` / `/dl w` | Panic escape: lock Ring2, equip the Provenance/Warp Ring, wait out its equip delay, use it (`off` cancels) |
| `/dl iw` | Instant Warp scroll: used straight from Inventory — no equip, no lock, no wait |
| `/dl ir` | Instant Retrace scroll: same, back to your Campaign nation |
| `/dl c` | Chocobo Whistle: lock Neck, equip it, call the chocobo the moment the game says ready (`off` cancels) |
| `/dl nexus` | Nexus Cape: lock Back, equip it, teleport to your party leader the moment the game says ready (`off` cancels) |
| `/dl shirt` | Shadow Lord Shirt: lock Body, equip it, teleport to Castle Zvahl Keep (`off` cancels) |
| `/dl t <where>` | Teleport gear: lock the item's slot (earrings Ear2, rings Ring2, caps Head, stables gear Neck, suits Body), equip it, wait, use it (norg, jeuno, maat, ducal, purgonorgo...) — shared destinations resolve to the item you own; no arg lists destinations |
| `/dl xp <ring>` | Exp/VP rings (Empress, Chariot, Kupofried, Venture...): same equip-wait-use dance on Ring2 — no arg lists what you own |

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
