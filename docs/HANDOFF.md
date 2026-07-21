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
   `/dl` command surface, per-char file layout — and **"Central services"**, the
   table of one-answer functions (is this a Crystal Warrior → `gamemode.get()`;
   entity-near-me → `lib/entwatch`; owned counts, catalog lookups, char dir,
   native MP, command queue...). When Henrik says "the global/central function
   for X", that table is where it lives — consume it, never re-derive it.
4. [design/trigger-system.md](design/trigger-system.md) — the trigger engine spec.
   [design/profiles.md](design/profiles.md) — the profile storage layer (where sets
   and triggers live since v33, the one read/write compatibility rule, migration).
5. [adr/](adr/) — decision records; **0002** (data-driven dispatch) and **0003**
   (overlay) explain most "why is it like this" questions. **0006** (the builder plans,
   the engine decides) and **0007** (resolve only when ready; a latch must remember what
   it answered) are the two that bite hardest if ignored.
6. [history.md](history.md) — session journal: what was tried, what was abandoned, and
   why. **Read the dead-ends lists before proposing anything.**
7. [server-questions.md](server-questions.md) — suspected server-side bugs / undocumented
   intent, each with the workaround dlac carries meanwhile. Nothing urgent; the point is
   that the workarounds get **deleted** when an answer lands, not left to calcify.
8. Reference: [reference/catseyexi-jobs.md](reference/catseyexi-jobs.md) (server job
   truth), [design/storage-move.md](design/storage-move.md) (packet-level research for
   the gearmove branch), [design/picker-database.md](design/picker-database.md),
   [design/sync-settle-hold.md](design/sync-settle-hold.md) (the level-sync TP fix,
   v56/v57 — and the WRAP_GEN rule for anything that must survive an engine hot-swap).

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
  `/dl env`, `/dl dw`, `/dlmv` (branch) are the diagnostic probes. **When a timing bug
  survives one round of code-reading, stop reading and make the engine print its own
  state** — the "NON" bug (v49) cost two wrong theories deduced from the source and fell
  in one line to a temporary `/dl instdiag` dump. Build the throwaway probe earlier than
  feels justified; it lives in `cb2fbe2..40288e3` if this class returns. Two gotchas it
  hit, both since commented in place: a new `/dl` subcommand must be added to the command
  handler's **WHITELIST**, not just given a branch (v46 printed nothing for exactly that,
  and looked like the command did not exist); and a changed seeded file at an **unmoved
  `M.VERSION`** never loads at all (hard rule 4).
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

## Agent skills

This repo is wired for the Matt-Pocock engineering skills and an event-driven GitHub
agent; the per-repo setup lives in `docs/agents/`.

- **Issue tracker** — GitHub issues on henkpoa/dlac (PRs are not a request surface).
  Labeling an issue `ready-for-agent` dispatches a cloud Claude agent
  (`.github/workflows/issue-agent.yml`) that implements it on a branch and opens a PR.
  See `docs/agents/issue-tracker.md`.
- **Triage labels** — the five canonical roles (`needs-triage` / `needs-info` /
  `ready-for-agent` / `ready-for-human` / `wontfix`), plus `agent:max` to raise the
  agent's budget on hard FFXI/engine issues. See `docs/agents/triage-labels.md`.
- **Domain docs** — single-context: `CONTEXT.md` + `docs/adr/` at the root, with
  HANDOFF / architecture / history as additional binding records. See
  `docs/agents/domain.md`.

## Hard rules (each one paid for in debugging time)

1. **LuaJIT 200-local cap per chunk.** gearui.lua sat at EXACTLY 200/200 until the
   uihost split (v40: uihost/itemicons/equippedui/setupui/syncflags/weightsui/
   profilesmenu — see architecture.md); now ~134 with headroom. Every new UI feature
   still registers a tab/window via uihost instead of adding gearui locals. Parsers
   don't catch a breach — it's a load-time crash; `lua tests\smoke_ui.lua`
   headless-loads the whole UI chunk and DOES catch it (run it with run_tests.lua).
2. **`imgui` is not a global** in addon modules — `require('imgui')` it. A nil-guard
   around a missing require silently disabled an entire feature's UI once (gearmove
   v1–v4). Probe the Ashita binding before using an ImGui API — presence proves
   nothing (`BeginPopupContextItem` is bound and does not work here; `BeginMenu` is
   bound and nothing in the install calls it). **Right-click DOES work**, via
   `IsMouseClicked(1)` + `IsItemHovered()` → `OpenPopup`/`BeginPopup`
   (`gearmove.lua:663`, field-confirmed); it was `BeginPopupContextItem` that failed
   twice, and this rule used to blame the gesture — record the API that failed, not
   the gesture you gave up on.
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
11. **Not-ready client state can look like GOOD data, and a latch makes one bad read
    permanent** (ADR 0007; cost: a whole session's gear, silently, plus two wrong
    theories). At login the player block is unpopulated: `GetMainJob()` returns **0**
    (None) and gData stringifies it to **`"NON"`** — neither `''` nor `'?'`, so a guard
    listing *those* accepted it as a real job. Ask **`M.jobReady(id, name)`**; it gates on
    the id, because 0 is the authoritative "not ready" (`readJobSets` always did this).
    Corollaries: **never enumerate the bad values** — `"NON"` was the one nobody thought
    of; **`gProfile` existing does not mean the job is known** (LAC takes it from the 0x0A
    packet, gData reads memory — they disagree for ~6 s); and **a latch is a smell**. Every
    other engine reader re-reads on a throttle and self-heals — the auto-install was the
    sole non-retrying one, which is exactly why triggers came back at login and sets never
    did. If you must latch, key it on *everything* you resolved against and never latch on
    a question you couldn't answer (`setsPath(job) == nil` means "can't tell yet", NOT "no
    sets file"). Tests Z1–Z7.
12. **A total failure and a typo must not look identical.** v35 made a matched-but-missing
    set red in the Triggers tab instead of a chat warn — right for one typo'd name, but it
    also means the engine equipping *nothing at all* says nothing at all. That silence is
    what let 11 survive for two days. When a whole subsystem no-ops, be loud.
13. **The addon root is what LAC sees; folders are what only the addon sees.** Modules are
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

## Current state (as of 2026-07-21)

- **Iridescence catalog sweep + universals ladder (07-21, engine v82, manifest
  fmt 10, field UNRUN).** The shipped catalog's `Iridescence` stat is now the
  tier authority: exactly **15 carriers**, a **+3 tier exists** (Inanna,
  Keraunos, Gridarvor, and the Lv75 relic stages of Laevateinn/Tupsimati), and
  **Claustrum carries none on live** (old fallback guess, removed). The
  `UNIVERSAL` list (ui/automationsui.lua) stays curated for what the catalog
  can't say: preference order (tier desc, your job's weapon over the
  Chatoyant/Iridal fallbacks), the `cw` flag (**exactly the six Incursion
  lines** — Foreshadow +1, Arcanium +1, Claritas, Izuna, Inanna, Keraunos;
  Gridarvor/Coeus/Kaladanda are "Oboro weapons", all modes — Henrik's ruling),
  and the **id pin** (relic stages share one name; Laevateinn pins 18994,
  Tupsimati 18990, resolved via `deps.lookupById`, wrong stage never adopted).
  CW-only rows display-gate on the affirmative `gamemode.get() == 'CW'`; other
  modes get a "Show Crystal Warrior gear" peek checkbox (session-only). The
  manifest's `universals` = preference-ordered ladder of every owned universal;
  the engine equips the first rung usable at the live level (a level-synced
  BLM falls through a parked Inanna to Foreshadow +1). Coverage light runs
  0..5 now (5 = +3 universal). Tests VL8-13, S166-S166c. Commits 397d75b,
  4af43b5, 5289600, c0ac739.

- **AutoAmmo — the Ammo-slot automation (07-20, engine v73, main-destined).**
  Henrik's COR-friend feature: LAC never re-equips depleted ammo and a stranded
  Rare/Ex super-bullet (Animikii) gets eaten by the next shot — dlac now owns the
  slot. `feature/ammowatch.lua` + `ui/ammoui.lua` (Automations → AutoAmmo row)
  write `<char>\dlac\ammostate.lua` (per-ammo Ranged / WS / Special flags,
  priority order; **fmt 2 since v74: one section PER JOB** — each job keeps its
  own list AND its own persisted on/off ("all jobs can't use all ammos"), fmt-1
  files migrate on first panel open; **`enabled` PERSISTS across sessions** —
  deliberate deviation from the craftstate rule, a protection must not disarm
  at login);
  the engine overlays the Ammo slot on EVERY event below pins with
  **count-verified** picks (the LAC state's first bag counter — per-second
  cache, FRESH on action events) and a ladder ending in a literal `'remove'`
  (LAC-native unequip; an empty gun is server-blocked, so the shot refuses
  instead of eating the bullet). Server truth baked in (public stable branch,
  field promotion pending — design doc §0): free ranged WS = **Trueflight 217 /
  Leaden Salute 218 / Wildfire 220 ONLY** (the sql `type` column cannot tell —
  it's the Lua handler); Quick Draw consumes a card, never the worn bullet, but
  hard-requires a Marksmanship ammo equipped (AutoAmmo un-blocks it when the
  slot ran empty); Unlimited Shot = effect 115, affirmative-only window. Pure
  core `M.resolveAmmoPlan` (tests AM*), ammowatch serializer (AW*), smoke
  S135-138. **Read docs/design/auto-ammo.md before touching it** — the decision
  table (§3) and the field-test checklist (§6, unrun) live there.
  - **E-Box counts + fetch (same day, field round 1) — CRYSTAL WARRIORS
    ONLY**, the FIRST consumer of `gamemode.get()` (affirmative `'CW'` shows,
    Wings/ACE/nil see NOTHING; the server's 0x1A4 `LOCKED` reply is the second
    gate). `feature/eboxammo.lua` = trove's ebox wire format reimplemented
    (GET_CATEGORY ahCat 15 streams every boxed ammo's count in one request;
    WITHDRAW + ACK with the server's refusal words; pending discipline on the
    shared 0x1A4 party line; `string.byte` parsing, headless EB*). Per-row
    `E-Box: xN` + qty + Fetch + **Fetch up to** (top-up against bag counts) in
    ammoui, plus a no-target proximity check — E-Boxes are **DYNAMIC entities**
    named "Ephemeral Box" (index 0x802 in the field sample; **range 5
    FIELD-PINNED**, test EB9); out of range = warning + the fetch buttons go
    dead-red. Box detection field-CONFIRMED (round 6) after two scan-bug
    rounds, then generalized at Henrik's ask into **`lib/entwatch.lua` — THE
    central entity watcher** (watch(who, name[, cb]) subscriptions, one shared
    0x000-0x8FF sweep, fast tracked-distance refresh with slot-reuse eviction
    that notifies, demand-windowed when callback-less; every entity-array
    idiom lives THERE, tests EW*). eboxammo is consumer #1; use entwatch for
    any future "is there an X near me?" — never a local scan. Hidden
    diagnostic: `/dl ebox`.
- **GEAR-SET BONUSES ARE LIVE — display + optimizer (07-18, ADR 0011).**
  `gear\geareffects.lua` is THE evaluator (`comboStats` = whole-composition truth;
  `setsOf`/`setTier` the optimizer seam; counting per SLOT — duplicates twice,
  server-verified — and level-gated). Worn/planned totals, the panel's set captions and
  the tooltip tier ladder all derive from it; `optimizePicks` credits bonuses inside the
  cap fold via `opts.effects` + set-seeded restarts; buildBestSet's prune appends
  (never removes) set members. Rule candidates already enforced by tests, keep them
  true: **set bonuses never enter per-item scores** (`scoreOfItem` stays combination-
  blind — HB pins), **pool augmentation is append-only**, and the greedy
  `buildMaxStatSet` path stays set-blind (HB10). Latents ship in
  `data\latentstats.lua` but are DORMANT (P2/P4/P5 open — issues #41/#43/#44). Read
  `docs/design/conditional-effects.md` + ADR 0011 before touching any of it.
- **DONE — engine v50, "NON is not a job" (`cb2fbe2`; docs `40288e3`).** The login
  auto-install bug: `GetMainJob()` reads 0 at login, gData stringifies it to `"NON"`, the
  guard accepted it as a real job, found no `sets\NON.lua`, installed nothing and
  **latched for the session** — so every trigger matched and silently equipped nothing.
  Latent since the storage move (v33, 07-13); masked for two days because any job change
  or Reload LAC heals it, and dev habits do both constantly. Fixed at both ends
  (`M.jobReady` + a job-keyed latch), **field-confirmed on both characters** (Hunklor
  SAM, Mindie WHM); the v46–49 `/dl instdiag` diagnostic is stripped again in v50.
  **Read ADR 0007 and hard rules 11–12 before touching anything that reads client state
  at login.** Nothing open — the diagnostic is stripped and both suites are green.
- **MAXMP = THE BANDED LADDER (07-20→21, engine v76..v95, field-settled on
  WHM, pushed):** max-MP gear follows a PRECOMPUTED threshold ladder —
  current MP is the only live read (GetMPMax is unreliable during gear
  churn; floored party MP% == 100 is the only exact fullness signal).
  `feature/mpbands.lua` pure core + `dispatch.M.mpBands` context +
  `/dl plan` (renders the SAME context the engine runs — plan IS behavior).
  Standing rulings: refresh is the IDLE SET's job (the engine adapts the
  ORDER to the *potential* refresh only); augments always in the totals;
  ear/ring pieces never relocate across their pair (sticky + idle-set pair
  homes, panel picker overrides detection); positions beat optimality.
  MaxMP is IN the Automations GUI (ON/OFF switch, live state). **Read
  docs/design/maxmp-mode.md before touching ANY of it** — the final
  architecture, the rulings ledger and the failure museum (v76–v95) live
  there; history.md "the banded ladder" is the timeline. Cross-session
  memory: `memory/maxmp-staged-hidden.md`.
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
- **PINNED slots + the floating equipment window — dispatch v44, new this session
  (07-15).** "Equip item, lock slot so nothing removes equipped item" (Henrik) —
  built as an OVERLAY, not a lock: `pinwatch.lua` writes `<char>\dlac\pinstate.lua`,
  the engine WEARS the pinned names as the LAST `equipResolved` of every dispatch
  (above the craft overlay, every event). "Lock" keeps its old, near-opposite
  meaning (`M.locks` = engine ignores the slot); the new thing is a **Pin**.
  `ui/floatgear.lua` is the equipmon-style 4x4 window (uihost module; reuses
  `S.renderSlotGrid`, so icons/tooltips can never drift from the Equipped tab).
  Scope = `'All'` or `"<Event>|<rule label>"` keys via `M.pinScopeKey`. Read
  history.md "floating equipment window + PINNED slots" before touching it —
  especially the disk-clear trap and the Sub-vs-Main guard (both directions).
  - **RIGHT-CLICK WORKS — the old dead-ends entry was wrong.** What failed twice
    was `BeginPopupContextItem`, not RMB delivery. `IsMouseClicked(1)` +
    `IsItemHovered()` → `OpenPopup`/`BeginPopup` is field-confirmed
    (`gearmove.lua:663` on feature/storage-move). Entry corrected 07-15.
  - **`imgui.BeginMenu` CASCADES — field-confirmed 07-15** (Henrik: "the
    cascading menu and pinning works"). floatgear is the first Lua caller of
    BeginMenu in this install; its drill-down fallback is now dead weight kept
    only as a guard. **But a submenu is drawn OUTSIDE the rect of the window that
    declares it, so menu items must NOT live in a `BeginChild`** — moving the
    mouse toward the submenu leaves the child and ImGui tears down the entire
    popup. Bound the popup with `SetNextWindowSizeConstraints` instead.
- **Reserved slots (RSlot) — dispatch v43.** Items that take a
  slot away while worn (Ryl.Ftm. Tunic = Body reserves Head; robes reserve Hands;
  boomerangs reserve Ammo) made dlac and the server fight forever over the reserved
  slot. The fact is server data (`item_equipment.rslot`), now crawled into
  `catalog.lua` as `RSlot`, stamped into gear.lua by the scan, **backfilled by
  `/dl fix`** (the engine has no catalog — unstamped = old behavior), and resolved by
  `dispatch.reservedDrops` at equip time. Read the **ADR 0006 addendum** before
  touching it: build-time stripping (what ffxi-lac did, and what dlac had ported as
  dead code in utils.lua) is WRONG under overlay. Worn pieces reserve too. Tests: AK,
  E7–E11. history.md "Reserved slots" has the data scan + the two traps.
- **`/dl view_ids` + lockstyle "Show gear I don't own" — new this session (07-15).**
  `/dl view_ids [on|off]` appends **item id + model id** to `renderItemTooltip`, which is
  the ONE hover card every equipment surface shares (Equipped / All Equipment / Sets /
  floatgear / the lockstyle picker) — so "all equipment hover" needed no new surface.
  They are different numbers and the difference is the point: a lockstyle shows the
  **model** id (Arhat's Gi = item 13795, model 59); accessories have no model at all.
  Flag lives in syncflags beside `debug`/`autosync`. In lockstyle, the picker's **"Show
  gear I don't own"** tick sources the full catalog, because the 0x051 preview never asks
  the server and renders anything; **Save** is what enforces ownership (Apply needs no
  gate — it reads the SAVED file). Read history.md "view_ids + lockstyle previews gear
  you don't own" before touching it — especially the by-Id ownership rule (the apostrophe
  trap saves a name the engine can't resolve), the fail-OPEN gate, and `BROWSE_CAP`
  (Main is 3749 catalog rows).
- **THE CATALOG'S `Slot` CANNOT BE TRUSTED — and it lies toward Body (07-15).**
  CatsEyeXI's `item_equipment` carries unmarked rows for **unimplemented** items with
  default values: `jobs=0`, `MId=0`, `slot=32` — and **32 decodes to Body**, so 258 of
  the 259 stub rows landed in the Body bucket (`Gletis Crossbow`, `Mpacas Bow`, the
  Amini/Boii +2/+3 tier). Found because the lockstyle picker offered crossbows for Body.
  apicrawl.py now skips `jobs == 0` (Body 1743 → 1485; it prints the skip count) and no
  longer publishes an empty jobs mask as `Jobs = {"All"}` — which is why the junk looked
  legitimate for so long. **`jobs==0` is the marker, NOT `MId==0`**: the latter also
  covers 814 real modelless items (all `Hexed` gear) whose stats the catalog must keep.
  Validate any new API field against `tools/api_cache/<id>.json` for an item you KNOW is
  unimplemented before trusting it. Runbook: `tools/README.md` "The junk rows";
  provenance: architecture.md's catalog section; story: history.md round 2.
- **main**: healthy; **1253 tests green + 170 smoke_ui** — current as of 2026-07-18
  (the automation block — manifest machinery + the Automations MAIN tab — now lives in
  its own `ui/automationsui.lua`; seams `rescanAutogear`/`manifestStale`/`currentFmt`
  and the tab entry `renderTab` moved WITH it, no forwarders left on triggersui;
  craftwatch/helmwatch/fishwatch + gearui's sync hook require automationsui now, see
  architecture.md § automationsui). Note `tests\run_tests.lua` has now hit the **200-local
  cap** itself: new sections must be `(function() ... end)()`, not `do ... end` (a do
  block shares the chunk's budget; a function body gets its own 200). The whole **crafting-gear system** landed here (see
  history.md "crafting system + catalog pipeline"): read that section before touching
  craftwatch/craftbar/dispatch-overlay/automationsui-craft code.
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
  - **HELM gear system (2026-07-17, engine v59) — the craft system's gathering
    twin** (docs/design/helm-gear.md; history.md "HELM gear automation").
    Same MANUAL model: helmwatch writes `<char>\dlac\helmstate.lua`; the engine
    overlays `dlac:AutoHelm` on **Default ONLY (idle-only is the requirement,
    not an accident)**, armor+neck+waist only, fmtver-7 manifest ladders
    (Surveyor-major, stat-driven from catalog `HELM`/`Surveyor` keys + the
    semantic hat map). Craft-vs-helm both-on → CO-CLAIM since engine v98 (ADR
    0012 amendment): each claims when armed, the Arbiter's rank settles each
    overlapping slot per slot (the newest-`at`-wins exclusivity is retired). New:
    `helmwatch.lua`, `helmbar.lua`,
    `helmui.lua` (own module; rendered from automationsui's detail views),
    `assets/helm/*.png`. Venture points ride CatsEyeXI's custom 0x1A4
    request/response (trove's protocol, reimplemented); `!ventures` replies are
    0x017-captured raw until a field capture pins the private module's format;
    category auto-detected from outgoing trade 0x036 → "* Point" NPC name.
    Field tests pending: design doc §7 (`/dl helm points`, one `!ventures helm`
    capture, one swing per category).
  - **Fishing gear system (2026-07-18, engine v64) — the THIRD sibling**
    (docs/design/fishing-gear.md; history.md "fishing gear system"). Explicitly
    NOT fishing automation (no casting, no bite reactions — the server has an
    anti-bot surface; the design doc's scope guard is binding). Same MANUAL
    model: fishwatch writes `<char>\dlac\fishstate.lua` `{enabled, at, target,
    rod, bait}` — rod/bait are TARGET-FISH-specific picks resolved with the
    server's OWN fail math (`fishingutils.cpp` lose/snap/break, ported verbatim
    in `feature/fishcalc.lua` — pure, headless-tested F1-F14 with hand-derived
    expectations) and re-picked on a ~2s bag heartbeat (bait stack dies → next
    owned bait + chat line). Engine overlays `dlac:AutoFish` on Default only,
    Engaged/Dead stand aside; Range/Ammo come straight from fishstate, armor +
    **Main** (Halieutica 20945 is a custom Main-slot fishing spear — craft
    precedent for weapon slots) ride fmtver-8 `fish` ladders
    (FishingSkill-major, the Expert Angler cx-mods as tiebreak — 2004/2005
    IDENTIFIED round 2 via bg-wiki Ventures: Fatigue Limit +% / Golden Arrow
    Rate +%; server-questions §4). Round-2 display rulings: glow =
    Mariners-only + legendary rods; Halieutica/Eyepatch/rod +1s undisplayed
    (data stays); legendary rod greens the standard ladder; carp pitch hides
    once Lu Shang's is owned. Three-way craft/helm/fish: CO-CLAIM since engine
    v98 (ADR 0012 amendment) — each claims when armed, the Arbiter's rank settles
    each slot per slot; the newest-`at`-wins-whole exclusivity is retired. Data:
    `data/fishdb.lua` generated by
    `tools/gen_fishdb.py` from the server's public SQL (stock-LSB fishing;
    pools/affinities/rods/mobs/guild) + api_cache scan — powers the panel's
    ISOLATION rows (bait+zone combos where ONLY the target bites; items/mobs
    warned separately) and rod verdicts. VP was already streaming (helmwatch
    0x1A4 `Fishing` label); GP rides craftwatch's 0x113 at offset `0x20` (was
    fixture-labeled "ignored"); `!ventures fishing` format UNPINNED — tolerant
    parse + raw capture mirror until a field run. New: `fishcalc`/`fishwatch`
    (feature), `fishui`/`fishbar` (ui, zero new assets — item icons), fishdb
    (data). The Mariners set (ids beside HELM's Plain block) + Brigands
    Eyepatch = fishing's VP tier — the panel's fourth column. Field tests: §6
    ALL CONFIRMED rounds 5–6 (07-18) — `!ventures fishing` parses (HELM line
    shape holds), GP 0x20 matches, overlay + dropdown pins verified — except
    custom-gear stat text (§6.5, needs drops) and the GetRank cap question
    (§7). Field round 5 (same day, design doc §8): legendary
    rod tier in the sort (Ebisu > Lu Shang's > the field, still BELOW risk),
    the heartbeat re-ranks every ~2s beat (a better/first rod is adopted with
    no pill toggle), fish bar rod/bait names are dropdown buttons with PINNING
    manual overrides (`rodPin`/`baitPin` persisted in fishstate, unpinned by
    vanish or target change; `*`/"(manual)" markers), and Clear's same-frame
    stale-local re-adopt is fixed (F70–F84).
  - **Game-mode detection foundation (2026-07-18)** (`feature/gamemode.lua`;
    history.md "game modes become readable"). CatsEyeXI's overhead mode icons
    are re-skinned retail name icons, readable off the rendered entity:
    RenderFlags4 `0x1000` = CW/UCW crystal (retail new-character '?'),
    `0x4000` = Wings Cait Sith (retail mentor 'M'), neither = ACE —
    field-pinned from labeled samples (dlacprobe v1.8 `/probe icons`,
    Tavnazian Safehold). ONE central question, Henrik's shape: callers ask
    for the mode, the crystal is plumbing — `gamemode.get()` → `'CW'` |
    `'Wings'` | `'ACE'` | nil, self by default, any rendered index
    optionally; nil ALWAYS means unknown — never gate on nil. Henrik's
    ruling: CW-vs-UCW is MOOT (same playmode, same restrictions) — UCW also
    returns `'CW'`; the white-vs-pink split is deliberately not pursued.
    Dormant foundation, no consumer wired yet. Tests GM1–GM8.
  - **Native MP calculator (2026-07-18)** (`data/nativemp.lua`; history.md
    "native MP becomes computable"). The server's MP formula ported verbatim
    (charutils.cpp `CalculateStats` + grades.cpp, stable branch): race pool +
    main-job pool at main level (growth rate kinks at 60), subjob pool at
    `(slvl-1)` ÷ `SJ_MP_DIVISOR = 2`; a 0-MP main job lets the RACE pool ride
    the subjob level instead. `get(race, mjob, mlvl, sjob, slvl [, meritMP])`
    → integer (nil = bad input, 0 is a real answer); `self()` reads look-race
    + jobs live, gamemode-pattern injectable. Merits are NOT native — pass
    them in: 10 MP/level, **10 usable at Lv75** (merit.cpp `cap[75]`; the
    merits.sql upgrade=15 headroom needs Lv80+, unreachable here). Field pin
    RESOLVED (Henrik: menu reads 10/10): naked 724 = 614 formula + 100
    merits + 10 SCH-sub Max MP Boost trait — the trait (Mod::BASE_MP) and
    all weapon/food MP ride `health.modmp` (the DISPLAYED max), never
    `health.maxmp`, so on-screen naked max may legitimately exceed
    get()+merits. Tests NMP1–NMP16.
  - **Auto Oneiros Grip (2026-07-18)** (`dlac:AutoOneiros`, engine v65+v66,
    manifest fmtver 9; history.md "the first nativemp consumer" + "the 724
    decomposes completely"). Sub-slot automation: equips Oneiros Grip while
    its latent Refresh +1 is LIVE — server truth (stable
    `latent_effect_container.cpp`; item_latents 18811 = latent id 4 =
    `MP_UNDER_PERCENT`): `health.mp / health.maxmp <= 75%`, and
    `health.maxmp` is the BASE pool (nativemp formula + merit MP, gear
    excluded). BG-wiki's retail "counts weapon/grip MP" rule is a DIFFERENT
    latent (`MP_UNDER_VISIBLE_GEAR`) the grip doesn't use and whose CatsEyeXI
    implementation is commented out — the grip's own MP+5 and Max MP Boost
    traits sit in the displayed max only. **The percent is FIELD truth, not
    repo truth: live fires at 50%, not the SQL's 75** (Henrik's tick test:
    break 357/358 on maxmp 714 = exactly 50.0%, equality active —
    server-questions #6). Engine threshold =
    `floor((nativemp.self() + 10×min(mpMerits,10)) × 50/100)` — boundary
    inclusive — recomputed per resolve (job/sync changes re-aim it).
    `mpMerits` (0–10; merit.cpp `cap[75]`) is the
    manifest's first USER-OWNED field: set on the Automations-tab detail view
    (live aim readout + a warning not to tune it to match the naked screen
    number), carried through every rescan by autoCommit — and it now
    **teaches itself**: `feature/meritwatch.lua` listens for s2c 0x08C
    (layout from the server's `0x08c_merit.h`). The merit protocol is
    PUSH-only — no request packet exists anywhere (the client wipes its
    merit cache at every zone and the server re-populates at zone-in,
    XiPackets 0x008C; c2s 0x0BE only spends/flips mode; the 0x061 status
    bundle carries just the point pool; Ashita memory only the unspent
    pool) — so the sync is fully automatic: **every zone-in** plus every
    merit spend, via `automationsui.setMpMerits`; the full-removal
    low-bit flag (id|1) parses as count 0. HIDDEN diagnostic:
    `/dl merits` (deliberately in no help list) prints wire-this-session
    vs manifest vs the resulting aim — the workflow check. Mindie's aim:
    614 + 100 = 714 → fires at MP ≤ 357. The flatten
    treats the marker as a GRIP under the shared subSlotAllowed rule (2H
    main → `dlac:AutoOneiros|<fallback>`, 1H main vetoes the marker; the
    + Add Sub picker offers it unconditionally per the HARD RULE);
    virtualMinLevel = the grip's Lv75 UNCONDITIONALLY (v68: one fixed item,
    so an unlearned manifest never degrades the marker to a Lv0 wildcard;
    the + Add rec is stamped Level 75 so the editor shows it). Tests
    AO1–AO14 (+clamp AO2c/d, unlearned-manifest AO10b).
  commits. Local-only pending GM verdict; strip TEMP probes (`/dlmv`, RMB debug,
  branch-print) before any merge. The Storage-into-Provenance packet experiment is
  designed, unrun (docs/design/storage-move.md "open questions").
- **The Arbiter batch + Blueprints (2026-07-21, engine v97→v100):** the six gear
  claimants (Pins, AutoAmmo, MaxMP, Craft, HELM, Fishing) now register **Claims** with
  one **Arbiter** — a strict draggable per-character rank list (`arbstate`; Priority
  section in the Automations tab; Locks = draggable VETO row, default under Pins;
  Triggers = the floor). `/dl prio` shows the live ranks, `/dl why` names each slot's
  winner + rank. Locks are engine-native (the lock path no longer emits `/lac disable`).
  **Blueprints** = job-independent saved Triggers (Triggers-tab section: save/stamp/
  edit/share-as-text, `blueprints v1`). AutoAcc is deliberately NOT a claimant (Type
  automation, within-set altitude). Start at ADR 0012 (+ Amendment) and the four
  "Arbiter, step N" + two follow-up entries in [history.md](history.md); glossary:
  Claim / Arbiter / Blueprint in CONTEXT.md. All field-confirmed 07-21.
- **Open threads:** see the "Standing loose ends" section at the end of
  [history.md](history.md) — notably `/dl dw` positive-case verification, GitHub issues
  #8/#9/#12/#13, picker-DB wiki overlay, stat hover descriptors, TPBonus scale,
  auto-build permissiveness.
