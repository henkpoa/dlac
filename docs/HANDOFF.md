# dlac — Handoff (start here)

You are picking up **dlac** ("dynamic LuaAshitacast"): an Ashita v4 addon for the
CatsEyeXI FFXI private server that GUI-drives LuaAshitacast so players never hand-edit
Lua. Maintainer of record is Henrik (in-game character **Mindie**, profile dir
`Mindie_29909`); most code is written by Claude sessions under his direction — his
words: *"don't ask for permissions to edit files within the addon, you are the
maintainer IMO, I am just the one with the creative vision."*

## Read in this order

1. **This file** — environment, rules, current state.
2. [CONTEXT.md](../CONTEXT.md) — the controlled vocabulary. Use these terms; avoid the
   listed synonyms.
3. [architecture.md](architecture.md) — module map, two-Lua-state design, data flow,
   `/dl` command surface, per-char file layout.
4. [design/trigger-system.md](design/trigger-system.md) — the trigger engine spec.
   [design/profiles.md](design/profiles.md) — the profile storage layer (where sets
   and triggers live since v33, the one read/write compatibility rule, migration).
5. [adr/](adr/) — decision records; **0002** (data-driven dispatch) and **0003**
   (overlay) explain most "why is it like this" questions.
6. [history.md](history.md) — session journal: what was tried, what was abandoned, and
   why. **Read the dead-ends lists before proposing anything.**
7. Reference: [reference/catseyexi-jobs.md](reference/catseyexi-jobs.md) (server job
   truth), [design/storage-move.md](design/storage-move.md) (packet-level research for
   the gearmove branch), [design/picker-database.md](design/picker-database.md).

There is also a cross-session memory dir (Claude-specific) at
`~\.claude\projects\C--catseyexi-catseyexi-client-Ashita-addons-dlac\memory\` — it
holds working-preference notes; the repo docs are the durable record.

## The one-paragraph mental model

Two Lua states share files. The **dlac addon** (this repo, loaded via `/addon load
dlac`) is the GUI + writer: it scans bags, writes `gear.lua`, splices sets into
`<JOB>.lua`, writes trigger files, and seeds a 4-file runtime
(`utils/dispatch/chatfmt/gear`) into `<char>\dlac\`. **LuaAshitacast** requires that
seeded runtime into *its* state; at every handler event the profile's one-line shim
calls `utils.dispatch('<Handler>')`, and the engine overlays every matching trigger's
flattened set, resolving virtual entries (auto staff/obi) per cast. Coordination
between the states is by files only (`modestate.lua` mirror + `dispatch.M.VERSION`
handshake).

## Environment & workflow

- **Platform:** Windows 11, PowerShell 5.1 primary. Repo lives inside the game install:
  `C:\catseyexi\catseyexi-client\Ashita\addons\dlac`. Per-char state:
  `C:\catseyexi\catseyexi-client\Ashita\config\addons\luashitacast\Mindie_29909\`
  (old pre-dlac code in `...\ffxi-lac\` — reference only).
- **Headless tests:** `& "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" tests\run_tests.lua`
  (Lua 5.4 via winget DEVCOM.Lua; not on PATH). `luac.exe -p <file>` is the fast syntax
  gate — run it on every touched Lua file. The pure-logic modules
  (utils/gearimport/setmanager cores) are testable without Ashita; add checks when you
  fix behavior there.
- **In-game loop:** Henrik drives; you cannot run the game. Ship small, ask him to
  `/addon reload dlac` (+ **Reload LAC** when seeded files changed — always that order),
  read his chat output/screenshots. `/dl debug on` reveals dev buttons; `/dl why`,
  `/dl env`, `/dl dw`, `/dlmv` (branch) are the diagnostic probes.
- **Git:** work on `main`; `feature/storage-move` is **local-only** (never push it)
  pending GM approval. Multi-line commit messages: write to a file and `git commit -F`
  (PowerShell 5.1 mangles embedded quotes in `-m`). Do not push without being asked.
- **Merging a branch that predates the folder move: use `-X find-renames=20%`.** Branches
  older than the layout commit still edit the flat root paths. Git's default 50% rename
  threshold silently fails where main also grew the file a lot since the branch forked —
  `statdefs.lua` (24.5 KB at the fork, 52.9 KB on main) lands as a
  `CONFLICT (modify/delete)`, and resolving it naively leaves a **stale root
  `statdefs.lua` that nothing requires** while the branch's real edit never reaches
  `data/statdefs.lua` — a silent no-op, not a visible break. Verified: with
  `-X find-renames=20%` the rename is detected, the edit lands, and the merge conflicts
  *less* than it did pre-move. After any such merge: `ls *.lua` at root — anything there
  besides the entry point, the engine five, and PROFILE_TEMPLATE is a mis-resolved rename.
- **Parallel sessions are normal.** Henrik runs several Claude sessions plus his own
  edits on one checkout. Before any branch switch / stash / commit: `git status` and
  re-read files you're about to edit. Never switch branches while another session's
  agent is committing.

## Hard rules (each one paid for in debugging time)

1. **LuaJIT 200-local cap per chunk.** gearui.lua sat at EXACTLY 200/200 until the
   uihost split (v40: uihost/itemicons/equippedui/setupui/syncflags/weightsui/
   profilesmenu — see architecture.md); now ~134 with headroom. Every new UI feature
   still registers a tab/window via uihost instead of adding gearui locals. Parsers
   don't catch a breach — it's a load-time crash; `lua tests\smoke_ui.lua`
   headless-loads the whole UI chunk and DOES catch it (run it with run_tests.lua).
2. **`imgui` is not a global** in addon modules — `require('imgui')` it. A nil-guard
   around a missing require silently disabled an entire feature's UI once (gearmove
   v1–v4). Probe the Ashita binding before using an ImGui API (`BeginPopupContextItem`
   needs an explicit id string here; right-click on item rows never worked — use
   Trove-style left-click buttons).
3. **Write Lua with the Write/Edit tools only.** Shell-heredoc/Python splicing has
   shipped two corruption bugs (`"dlac\triggersui"` → `\t` tab; a literal newline in a
   string). Keep code Lua-5.1/LuaJIT-compatible (tests run on 5.4 — write to the
   intersection).
4. **Two Lua states.** Disk reseed ≠ hot swap; LAC picks up seeded files only on ITS
   reload. Bump `dispatch.M.VERSION` whenever seeded-file behavior changes so the red
   staleness banner fires (it watches dispatch.lua only — utils.lua changes still need
   a manual "Reload LAC" reminder).
5. **Text-parsing Lua profiles must be comment-aware on BOTH find and walk** — a finder
   matching inside comments plus a walker skipping them = guaranteed false "unparsable"
   (the BLU shim bug), and header parsers must tolerate trailing `-- comments` (the
   prune bug).
6. **Never gate set *building* on current game state** — sets are plans; the engine
   decides at equip time (ADR 0006). Immediate-equip UI (Alternatives list) may gate.
   **Sub-slot corollary (reverted 3×, never again — ADR 0006 addendum):** while
   building, the Sub picker ALWAYS offers every shield/grip/one-hander — never narrow
   it by the DW trait, the planned/equipped Main (2H included), or an empty Main plan.
   The `A* HARD RULE` tests fail on any re-gating; do not "fix" them.
7. **All file writes follow the safety pattern:** backup (rotated, in `<char>\backups\`)
   → write temp → parse/sandbox-validate → atomic swap → abort untouched on any
   failure. Loud on failure, quiet on routine success.
8. **`pairs()` order is undefined** — any resolution-order dependency (Sub after Main)
   must be explicit. Locals referenced before declaration are silent nil globals —
   forward-declare.
9. **Data authority:** live game memory > BG-wiki (docs/reference/catseyexi-jobs.md) >
   public server SQL (it's byte-identical to stock LSB; real customization is in
   private submodules). Never hardcode retail/LSB job mechanics. Private-repo material
   (the augment enum, `tools/`) must never be committed.
10. **The GUI is the product.** Nothing may force a player to open a Lua file. Player
    code is never deleted or uncommented — migration is append-only.
11. **The addon root is what LAC sees; folders are what only the addon sees.** Modules are
    folder-qualified (`require('dlac\\ui\\gearui')`), EXCEPT the five seeded engine files at
    root — `utils`, `dispatch`, `chatfmt`, `profiles`, `gear`. They are copied into
    `<char>\dlac\` and load in LAC's state too, so one require line must resolve under two
    roots; and `require("dlac\\utils")` is published API in every user profile. Never
    folder-qualify them. Corollary when grepping/moving: `dlac\X` is **not always a module**
    — `dlac\triggers`, `dlac\modestate`, `dlac\lockstyles`, `dlac\macrobooks`,
    `dlac\craftstate`, `dlac\gearweights`, `dlac\profiles\<name>\` are per-character DATA.
    Watch the near-misses: module `lockstyle` vs data `lockstyles`; `macrobook` vs
    `macrobooks`; `crafts` vs `craftstate`. See architecture.md "Repository layout".

## Working with Henrik

- Edit addon files freely; recommend + reason instead of presenting option menus.
- **User-facing naming needs his row-by-row sign-off** (stat names especially — "if
  there is ANYTHING people will complain about, it is this"). Don't extrapolate
  approval from silence.
- Examples in docs/UI use generic names, never his personal set names.
- He tests live and reports fast; expect mid-session scope shifts and parallel edits.
- A GM is currently evaluating the addon for server approval — polish requests from
  that channel (like the word-wrap fix) take priority.

## Current state (as of 2026-07-15)

- **THE ACC SYSTEM LIVES ON `feature/autoacc` (07-14, Henrik's call, pending GM
  approval — do not merge or push without his word):** LuaAshitacast is on the
  server's special approved list *because* of automation; auto-swapping gear by
  calculated ACC may be more than the GMs allow, so the whole arc was moved off
  main the day it was finished (field-verified working). ON THE BRANCH:
  `accwatch.lua` (the `/dl acc` engage watch, labeled line, auto-/check
  injection — c2s 0x0DD, **16-byte struct, read the server's header not
  XiPackets**), `accdata.lua` + `tools/acc_calc.py` (12k-mob EVA table + 350
  per-family curves; custom mobs priced via cross-zone name match or
  `/dl acc family`), the accstate feed, AutoAcc selectable in the GUI, the
  Automations-panel row (Kind: Equip Type), and the accwatch tests (AD).
  Standing rulings still apply there: **level correction = SIGNED 4 ACC/lvl
  everywhere (ruling v3)**; model EVA is a floor, the /check bracket corrects
  live. Research kit: **dlacprobe v1.5** (not in git). Read history.md
  "ACC calculator -> acc watch" through "level correction ruling v3" before
  touching any of it. Cross-session memory: `memory/mob-eva-pipeline.md`.
  - **ON MAIN (the foundation, deliberately inert):** the Type-automation
    plumbing stays so branch and main share one set format — `autoType`/
    `removePrio`/`acc` wrapper fields (serializer + loader), the flatten's
    `dlac:AutoAcc:<prio>:<acc>:<Name>|<fallback>` markers (utils), the engine's
    budgeted-release machinery (dispatch v36) and tests AC1–24. The Behaviour
    popup shows "Auto Type" but offers **None only**; nothing on main writes
    `accstate.lua`, so any branch-committed markers resolve to "worn". The
    feedback-loop design notes live in history.md "AutoAcc -- the first Type
    automation" — read them before touching the dormant machinery.
- **Reserved slots (RSlot) — dispatch v43, new this session.** Items that take a
  slot away while worn (Ryl.Ftm. Tunic = Body reserves Head; robes reserve Hands;
  boomerangs reserve Ammo) made dlac and the server fight forever over the reserved
  slot. The fact is server data (`item_equipment.rslot`), now crawled into
  `catalog.lua` as `RSlot`, stamped into gear.lua by the scan, **backfilled by
  `/dl fix`** (the engine has no catalog — unstamped = old behavior), and resolved by
  `dispatch.reservedDrops` at equip time. Read the **ADR 0006 addendum** before
  touching it: build-time stripping (what ffxi-lac did, and what dlac had ported as
  dead code in utils.lua) is WRONG under overlay. Worn pieces reserve too. Tests: AK,
  E7–E11. history.md "Reserved slots" has the data scan + the two traps.
- **main**: healthy; **426 tests green + 49 smoke_ui** (was 293 at last handoff) —
  current as of this session. The whole **crafting-gear system** landed here (see
  history.md "crafting system + catalog pipeline"): read that section before touching
  craftwatch/craftbar/dispatch-overlay/triggersui-craft code.
  - **Craft gear model (know this before editing):** MANUAL — you pick craft + goal +
    on/off in the craft bar (`craftbar.lua`) or Automations panel; craftwatch WRITES
    `<char>\dlac\craftstate.lua`; the **dispatch engine OVERLAYS** the craft gear on
    Default at top priority (v31, `dispatch.craftOverlay`). Do NOT re-add
    command/lock/`/lac disable` equipping (all dead ends), and do NOT revive
    detection-driven auto-equip (`0x096` is the first synth packet — too late).
  - New this arc: `craftwatch.lua`, `craftbar.lua`, `crafts.lua`, `filetex.lua`,
    `assets/craft/*.png`, `assets/{macrobook,craftbar}.png`, `tools/gen_craftdb.py`.
  - **Last Synth (07-13, final form): `/lastsynth` is the GAME'S OWN retail
    text command** (client re-sends 0x096 itself; `/lastsynth check` shows the
    recipe). **dlac must NEVER intercept it** -- an interception round broke it
    (Henrik: "let /lastsynth be /lastsynth"). The craft bar button just types
    the command; craftwatch passively observes 0x096 to label the "Last
    synth:" line (persisted per char in `<char>\dlac\lastsynth.lua`).
    crafts.lua rows carry `r = <result item id>` for that label. A full
    dlac-side replay-injection implementation existed briefly and WORKS
    (server handlers verified; see history) -- deleted as redundant, ref
    c38c2ff if the packet knowledge is ever needed. **RULE (Henrik, 07-13):
    probing/diagnostic tools never ship in dlac -- they go in the dlacprobe
    addon** (`/probe synth` captures a synth on the wire).
  - **Verify-then-automate — DONE (2026-07-13):** guild-points self-request (c2s
    `0x10F`) turn-in-verified; now auto-fires once on login + on AutoCraft panel
    open (debounced). `/dl craft gp` remains the manual check.
- **feature/storage-move**: gearmove v8 + gearcheck + the gearui modularization
  commits. Local-only pending GM verdict; strip TEMP probes (`/dlmv`, RMB debug,
  branch-print) before any merge. The Storage-into-Provenance packet experiment is
  designed, unrun (docs/design/storage-move.md "open questions").
- **Open threads:** see the "Standing loose ends" section at the end of
  [history.md](history.md) — notably `/dl dw` positive-case verification, GitHub issues
  #8/#9/#12/#13, picker-DB wiki overlay, stat hover descriptors, TPBonus scale,
  auto-build permissiveness.
