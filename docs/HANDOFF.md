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
   [design/gear-oracle.md](design/gear-oracle.md) — the one door for gear questions
   (API + the four boundary rulings + guards/goldens troubleshooting); read it
   before touching anything gear-flavored.
5. [adr/](adr/) — decision records; **0002** (data-driven dispatch) and **0003**
   (overlay) explain most "why is it like this" questions. **0006** (the builder plans,
   the engine decides) and **0007** (resolve only when ready; a latch must remember what
   it answered) are the two that bite hardest if ignored. **0014** (lockstyle is
   addon-resident; the Engine equips gear only) records the 2026-07-23 pivot and the
   command-bus law it turns on — read it before touching lockstyle or the `/dl` surface.
   **0015** (native-first; LAC independence is the end-goal, legacy is a sunset) is the
   STANDING DIRECTION: new features target the native engine, never LAC — read it before
   designing anything.
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

**One Lua state, one engine** (since the LuaShitacast purge, 2026-07-27). The dlac
addon is GUI, writer AND engine: it scans bags, writes `gear.lua`, keeps sets and
triggers in the profile store (`config\addons\dlac\<char>\profiles\<active>\`), and
`feature\equipengine` + `dispatch.lua` equip via dlac's own authentic 0x050/0x051
packets — at every handler event the engine overlays every matching trigger's
flattened set, resolving virtual entries (auto staff/obi) per cast. Old
`config\addons\luashitacast\` trees are read-only IMPORT territory: the Sets tab's
static/group imports and the login auto-migration read them, nothing ever writes
them. *(The pre-purge model — two Lua states sharing seeded files, LuaAshitacast
hosting the engine — is history; see `docs/design/lac-purge-plan.md` and history.md.)*

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
- **Git:** work on `dev` — **directly, no feature branch** (hard rule, see "Branch model"
  below); `feature/storage-move` and `feature/autoacc` are **parked local-only archives**
  (never push, never merge, never check out). Multi-line commit messages: write to a file
  and `git commit -F` (PowerShell 5.1 mangles embedded quotes in `-m`). Do not push
  without being asked.
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
4. **~~Two Lua states~~ ONE Lua state** (the purge, 2026-07-27 — seeding and the
   self-swap are gone; `/dl reload` / `/addon reload dlac` is the one update hop).
   Still bump `dispatch.M.VERSION` whenever engine behavior changes so the
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
14. **Branch state lives in git, never in prose.** Before telling anyone — Henrik included —
    what is or is not on main, run **`git log --oneline main..dev`**. That command is the
    authority; this file is not, and neither is the Claude memory dir. Status lines rot at
    *merge* time because whoever merges is never whoever wrote them: on 2026-07-25 the
    `/dl naked` entry below, plus memory entries for E-Box v2 and repeat Last Synth, all
    still read "on `dev`, NOT on main" for work that had been on main since `7231143` — and
    a session repeated that to Henrik, who had to correct it. Two duties follow. **Writing:**
    a finished, field-confirmed commit goes in the **Ready to merge** section above, never
    only in a per-day "Current state" bullet. **Merging:** empty that section in the same
    commit as the merge, and fix any "on `dev`" claim the merge just falsified. An entry
    marked **ACCEPTED** there already has Henrik's go-ahead — carry it and don't re-ask;
    only he may add that marker.

## Working with Henrik

- Edit addon files freely; recommend + reason instead of presenting option menus.
- **You are the maintainer; Henrik has the vision and field-tests** (his words,
  2026-07-24). Execution decisions — including **user-facing naming/wording** — are
  YOURS to make and sign off; don't punt a wording menu to him or wait on his
  approval to ship strings. Name with care anyway: it's the thing players notice and
  complain about most ("if there is ANYTHING people will complain about, it is this"),
  so match existing conventions and keep it clear and honest. His lane is **vision**
  (what to build, design rulings) + **field test** (he'll flag anything that reads
  wrong in-game). Bring him direction forks and things only live testing can settle;
  decide the rest. Don't extrapolate a design *direction* from silence.
- Examples in docs/UI use generic names, never his personal set names.
- He tests live and reports fast; expect mid-session scope shifts and parallel edits.
- A GM is currently evaluating the addon for server approval — polish requests from
  that channel (like the word-wrap fix) take priority.

## Ready to merge (dev → main)

**A queue, not a record.** Everything listed here is committed on `dev`, green on both
suites, and field-confirmed by Henrik — it waits only on his go-ahead to promote. The agent
that performs the promotion **empties this section in the same commit as the merge**. An
entry left standing here after a merge is how "is this on main?" becomes unanswerable —
see hard rule 14, which this section exists to serve.

**Two states, and the difference matters.** *Field-confirmed* means it works on Henrik's
machine; **ACCEPTED** means he has additionally said *promote it* — so the next dev → main
merge carries it **without asking him again**. Only he can move an entry to ACCEPTED. Note
this does not make an accepted entry mergeable *alone*: `dev` promotes
**whole-or-not-at-all**, so an accepted entry rides the next promotion of the whole branch.

### ✅ ACCEPTED — Minimizing the hobby bar ate the other windows — `ad476ea` (2026-07-27)

Addon `27t` → **`27u`**, engine unchanged. Suites **3901 + 693**, Windows and WSL lua5.4.
**FIELD-CONFIRMED 2026-07-27** by Henrik — *"it works now :)"* — and **ACCEPTED the same
day**: *"Document this as an accepted fix and put it as an accepted part of the dev → main
merge in the future."* **The next promotion carries this; do not re-ask.**

- **One deleted line in `ui/hobbybar.lua`.** It opened with
  `imgui.SetNextWindowSize({0,0}, ImGuiCond_Always)` in front of an `AlwaysAutoResize`
  `Begin`. A zero component is not "auto-size", it is **"keep measuring"**: ImGui's
  `SetWindowSize` sets `AutoFitFramesX/Y = 2`, and `Cond_Always` re-armed them every frame,
  so they never reached zero. ImGui's rule is
  `skip = (Collapsed or not Active or Hidden) and AutoFitFrames <= 0` — so a **collapsed**
  hobby bar kept returning `true` from `Begin()` and kept drawing its whole body into a
  title-bar-sized window. Every other dlac window collapses normally; this was the only
  trigger, and **closing** the bar was always safe. Focus picked the victim: `FocusWindow`
  moves a window's draw list to the display front, i.e. *behind* this one in emission order,
  so clicking the Teleports float — or opening `/dl ui` — put it there and it went invisible.
  `AlwaysAutoResize` had been doing the sizing since the bar shipped (`92e1fb2`, 07-24);
  the call was redundant the whole time.
- **`HB21`** records every size the bar requests and asserts none is zero. Mutation-verified.
- **Docs:** history.md carries the law and the diagnosis, including the `/dl metrics` read
  (`active` vs `visible` + the vertex delta) that named *active, rendered, drawing nothing*.

### The claimant registry — ADR 0027 stage 0 — `05f7be8` + `bda43fd` (2026-07-27)

Engine v135 → **v136**, addon letter unchanged (the `27w` letter raced to the parallel
autobuildimport commit — shared checkout; the engine handshake is stage 0's marker). Suites
**3934 + 693** at commit time, Windows and WSL lua5.4. **FIELD-CONFIRMED 2026-07-27** by
Henrik — *"Stage 0 is confirmed"*; the SCH Royal-Cloak-vs-Head case still resolves (v135
intact), craft and HELM work. Waits only on the go-ahead.

- One `CLAIMANTS` table — one row per rank row minus the Triggers floor — that the ensure
  pass, BOTH bail guards, the claims map, the retrace-signature legs, the rank-walk applies
  and `/dl prio` all iterate. A new claimant = one row + one `ARB_ORDER_DEFAULT` entry; the
  silent-bail class (a missed bail term, a missed signature leg) is structurally gone. Zero
  behavior change by construction; `CLAIMANT_SIG_ORDER` kept the legs' byte order, so live
  sessions did not even retrace on the upgrade.
- CR0–CR9c pin the registry's shape as data; NK26 drives the rewired `M.dispatch` end to end.
- **Follow-up on dev, NOT yet field-looked:** `cad6b1f` (v137, `27x`) makes the AutoAmmo
  `/dl prio` line **job-aware** — the field-flagged "ON when it really isn't" read the FILE
  (any job's enabled section); it now answers for the current job and an off line names who
  has it set up ("off (this job -- set up on DRK)"). CR10a–i; suites **3943 + 693**. (The
  MaxMP Cassandra's-over-Outlaw's earring pick is OLD weave behavior, untouched by both
  commits — one `/dl plan` while it is happening will name the rung and thresholds.)

### Reserved slots: visible, then correct — `05da34a` + `aa3c60d` (2026-07-27)

Addon `27o` → **`27t`**, engine v134 → **v135**. Suites 3901 + 692, Windows and WSL lua5.4.
**FIELD-CONFIRMED 2026-07-27** by Henrik on both reported characters — *"It works now."*
Waits only on the go-ahead. (The `27q`–`27s` wishlist commits between these two are a
separate session's work with its own queue standing.)

- **`05da34a` — the reservation stops being invisible.** Every hover card says *"Takes Head
  — that slot stays empty while this is worn"*; the Sets builder marks a reserved tile and
  names the reserver. New seams `dispatch.rslotText` + `gearimport.rslotFor` so the GUI owns
  neither rule. Also: `apicrawl.py` audits RSlot on every rebuild (`--rslot-audit`), because
  a *lost* reservation is silent and `/dl fix` would retract it from every player's gear.lua.
  Coverage was verified, not assumed: 383 reserving items, byte-exact against the server's
  `item_equipment.rslot`. **There is no list to maintain** — that was the question that
  started the day, and the answer was arithmetic already in the repo.
- **`aa3c60d` — multi-slot dominance (v135).** The reserve rule was correct and being handed
  the wrong input: each rule's set is resolved through its own `equipResolved`, so priority
  never got a vote. Now a reserving piece is a candidate only while its claim is dominant
  over every slot it takes — dominant, it claims them (left empty); beaten, it is ineligible.
  Fixed both field cases at once, in opposite directions. See history.md for the two wrong
  diagnoses that came first; the trace killed both.

### The Wishlist — `d18c614`..`5e55cdf` (2026-07-27)

Three commits, addon `2026.07.27p` → **`27s`**, ADR 0026. Green on both suites
(**3875 + 692**), Windows and WSL lua5.4. **FIELD-CONFIRMED 2026-07-27** across two
rounds — Henrik: *"The extra level worked cascade menu wise… It looks great! I can also
add the stuff to sets if I press add, also works!"* then, after the layout pass,
*"It looks good and works."* Waits only on the go-ahead.

- **`d18c614` — the feature (ADR 0026).** A **Wishlist entry is an ENTITY** keyed by item
  Id (`feature/wishlist.lua`, `<char>\dlac\wishlist.lua`), with one note and any number
  of **links**. Henrik's correction to the first, derived design — *"add the item to the
  wish list as its own entity… then connect the set / sets that want it"* — and the better
  model: you can wishlist a piece **for** WHM/Idle without stuffing it into the set.
  The law it produces: **the stored half is an intention, the computed half is a fact,
  neither is derived from the other, and where they disagree is where Apply belongs.**
  Links are never revoked by dlac; set membership and ownership are re-read every time.
  Set files are UNCHANGED (his call, *"b, keep set files clean"*) — the engine asks
  `wishlist.isWished(name)` to silence `warnMissingGear`, failing toward warning.
  `resolveGearName` became apostrophe-blind as a **fallback layer** beneath the exact
  index (the API drops possessives but keeps `San D'Orian`), without which the whole
  feature would have failed silently on the day a piece was finally acquired.
  Bug caught on the way: catalog records carry a `Key` exactly like owned ones, so
  `recordPath` would have written `gear.Body.X` for an unowned piece — `nil` in the set
  file, entry gone without a word. Unowned pieces serialize as a quoted **name**.
- **`8564e9e` — every column is measured.** Field round 1 banked a durable fact: the
  **2-deep imgui cascade IS supported in this binding** (floatgear had only ever proven
  one), so `popup → BeginMenu → BeginMenu → MenuItem` is now known-good for any future
  context menu. What broke was layout — hardcoded pixel columns in a window whose content
  is player-named. Also: a nil check is **not** redundant with a pcall around an imgui
  call (`imgui.CalcTextSize` throws while EVALUATING its argument), and smoke's stub
  `CalcTextSize` now returns a proportional width, because a stub answering a constant
  cannot tell a real measurement from a hardcoded one — which is why the suite was green
  straight through the bug.
- **`5e55cdf` — the link column reserves instead of fits.** Field round 2: fitting the
  column to the current entry is the right width for that entry and the wrong one for the
  next, so it shifts under you as you select rows and a longer set name has nowhere to go.
  Now `2×` the widest label on a 180 floor, capped at 360.
- **Docs:** ADR 0026, CONTEXT.md (**Wishlist entry** / **Wishlist link**), architecture.md
  (the module + the intention/fact split), README + `docs/guide.html` (player-facing:
  the tab tick, the window, and building sets ahead of the hunt), history.md.

### AutoAmmo: the level ladder + the CW removal — `41432db`..`4d6bb12` (2026-07-27)

Three commits, addon `2026.07.27l` → **`27o`**, engine v133 → **v134**. Green on both
suites (3821 + 593), Windows and WSL lua5.4. **FIELD-CONFIRMED 2026-07-27** on the
reported setup (his DRK, under the level override) — Henrik: *"it works now"*. Waits
only on the go-ahead.

- **`41432db` — the ladder learns the level (v134).** Field report: a DRK list of Acid
  Bolt 15 / Blind Bolt 10 / Crossbow Bolt 1, sorted best-first by the panel's own button,
  loaded nothing at an overridden level of 8 and nothing at 10. `resolveAmmoPlan` asked
  the flag, the pair (v128) and the bag count, never the level — and the overlay collapses
  a ladder to ONE name before the equip layer sees it, so there is no rung 2 to fall to.
  Now a fourth gate mirroring `equipcore.checkUsable` (level + Jobs mask), read off the
  live client resource for an item already counted in the bags; unknown never
  disqualifies. The level is **`playerLevel(ctx)`, so `/dl set level main N` wins** —
  reading `MainJobSync` straight would have shipped a "fix" that still ignored the
  override, which IS the report. The Default arm re-judges what is WORN (empty slot /
  over-level / ours-but-not-best) instead of only reloading an empty one, while anything
  worn that is not on the list stays untouchable. Stock-outs print, level changes do not.
- **`401a6bb` — the CW E-Box side is removed.** Henrik: *"we have E-box restocker now
  which is better."* `feature/eboxammo.lua` deleted whole; the panel has no gamemode
  awareness left. The `/dl ebox` entity probe survives as **`/dl debug ebox scan`** in
  `eboxtrace`.
- **`4d6bb12` — the panel shows the gate.** A red `Lv` column when a rung is out of
  reach, and the row actually in your Ammo slot renders green (the v128 tab law).

Docs: `docs/design/auto-ammo.md` §10 (rulings, rejected alternatives, 8 field tests);
CONTEXT.md gains **Ammo ladder**; ADR 0016 gains a later-note (one consumer now, not two).

*(Last promotion: 2026-07-27 — **THE LUASHITACAST PURGE, all five phases**,
`e478817`..`489e677`, addon `2026.07.27j` → **`27l`**, engine v131 → **v133**, on
Henrik's go-ahead: *"go ahead."* Field-confirmed on Mindie 11:48 — the first ever
clean `/dl check` on a native install: stamp v133 matching file v133 from the NATIVE
home (#131 closed), no seeded/shim lines, "NO ISSUES" verdict, engine ARMED. One Lua
state, one engine, one storage home; luashitacast\ is read-only import territory
(keep-list intact + PRG1/2 allowlist guard). Per-phase log:
docs/design/lac-purge-plan.md. Still open, post-promotion: the three-way import field
round (static / group / Copy-from-static) — guard-tested, not yet field-driven. The
record is the merge commit on `main`.)*

*(Previous promotion: 2026-07-27 evening — **the Xvs engine-era batch**,
`0f1ae6e`..`c074da9`, addon `2026.07.27f` → **`2026.07.27i`**, engine **v130**, ADR 0025 —
on Henrik's go-ahead: *"Everything is working perfectly now. … Regardless, push to main."*
Field-confirmed on Xvs's live installs, the boxes the bugs owned: **the native flatten no
longer waits for the GUI** (`utilsModule()` lazy require at all five bare
`package.loaded['dlac\\utils']` sites — the per-session "won't equip whatsoever" killer),
**dataDir holds while the first run is undecided** (the manufactured-legacy-evidence
race), and **born native, always** (ADR 0025: flag absent → native, the boot never scans
luashitacast\, an explicit flag stays the only road to legacy). Even the WS-menu-closing
weirdness stopped with it — the sick engine's full re-equip volleys were colliding with
open native menus via the server's 0x0AC rebuild. The record is the merge commit on
`main`.)*

*(Previous promotion: 2026-07-27 — **the hobby-bar day**, `96b49be`..`3446978`, addon
`2026.07.27a` → **`2026.07.27e`**, on Henrik's go-ahead: *"merge dev into main and push
both."* Two halves, promoted as one. **The searches came to the bar**: Fishing's
`TARGET FISH` section became a Floating window (`fishui.renderSearch` →
`renderTargetBody`) that the bar's target NAME opens, Chocobo's tab got the panel's own
Area/Item buttons via new `chocoui` openers, both tabs gained a `Panel` button, plus
`/dl fish find [name]` and `/dl choco dig [item]`; the invariant it rests on — any
surface may OPEN a floating window, exactly one place may DRAW it — went into
architecture.md, and CONTEXT.md gained **Floating window / Panel / Hobby bar**. **The
tabs became art**: all four draw Henrik's chocobo set (smith, miner, angler, digger) at
64px, hovers cut to one plain word each — Crafting / HELM / Fishing / Digging — with the
text button kept as the fallback for a missing or failed PNG.

The ART was field-approved (*"This was sooo good"*, *"Looks great"*). The SEARCH windows
went out **WITHOUT a field run of their own**, on the promote-the-queue call and the
whole-or-not-at-all rule — the Auto HELM 4s→5s precedent. Of the three questions that rode
to main, Henrik answered two later the same day: **three pills — bar, window, panel — is
right** (*"Perfection"*), and the **armed green frame reads fine** (*"Looks great"*), so
that pair is settled and neither needs revisiting.

**All three are answered now.** The target window was opened and approved — *"very
satisfied with how it opens a new window and search for the fish, instead of having to do
it solely WITHIN the fish automation menu"* — and its 760×520 default drew no complaint, so
the column-width worry closes unchanged.

**Second promotion the same day (`2026.07.27f`)**, carrying what that field run surfaced —
a fault older than anything above it: only the bait CELL was clickable in the spot list, a
~6-character hit box at 55% across a row you read left-to-right, so the natural click on
the place name did nothing. Present since the original fishing feature, through five field
rounds, unreported. The whole row is the hit target now (a full-width Selectable first,
columns drawn over it with an absolute SameLine — `automationsui.autoRow`'s shape), with
the three per-cell tooltips merged into one row hover. `FS9b/FS9c` pin the SHAPE of the
interaction rather than "does a click work", because the old test clicked the bait
Selectable and passed. The record is the merge commits on `main`.)*

*(Previous promotion: 2026-07-26 night — the **Teleports floating menu rework**
(`2026.07.26v`; Nexus Cape + Shadow Lord Shirt into "Other Teleports", the
Automations/HELM/Fishing cascades deleted, Hobby bar + Lockstyle rows added —
field-confirmed by Henrik: *"Looks good and works great"*), the **Sets-tab selection
drop on job change** (`2026.07.26t`, field-confirmed), the **WSL `nul`-file test fix**,
and the **Auto HELM hold tail 4s → 5s** (`2026.07.26u`) — the one entry that went out
WITHOUT its own field run, on Henrik's promote-the-queue call and the whole-or-not-at-all
rule. Its open question rides to main with it: whether 5s covers a brisk re-trade pace
without costing movement gear between points. The record is the merge commit on `main`.)*

## What's left (open work, as of 2026-07-25)

Nothing below is half-built — these are deliberate stopping points, each with its
research already recorded. In rough priority order:

0. **THE LUASHITACAST PURGE — EXECUTED, ALL FIVE PHASES, 2026-07-27** on `dev`
   (Henrik: *"Can't you just go all the way to phase 5, I really just want this to
   die"*). Plan + per-phase execution log: `docs/design/lac-purge-plan.md`; the day:
   `docs/history.md`. The batch, on top of the field-running `27j`:
   `e478817` P1 (`27j`/v131, writers+self-swap), `8b5e8fd` P2 (`27k`/v132, legacy MODE
   dies whole, −1063 lines), `58c75e0` P3+4 (`27l`/v133, native-aware check/debug —
   **#131 closed** — every "Reload LAC" string gone, legacy job files READ-ONLY, all
   module-local legacy fallbacks dead, PRG1/2 allowlist guard), P5 docs. One state,
   one engine, one home; luashitacast\ is read-only import territory (the keep-list:
   static/group/whole-block imports + the migrate carriers, all intact).
   **ON MAIN since 2026-07-27** (field-confirmed on Mindie, promoted on Henrik's
   "go ahead"). Only open thread: the three-way import field round (static / group /
   Copy-from-static) — guard-tested, not yet field-driven.
1. **FIELD TEST the 07-25 release.** Henrik approved the Menu/Settings **visuals**, but
   the **Mode library has not been driven in-game at all**. Everything in it is
   headless-tested only; the suites stub imgui by design, so popup behaviour, the
   pre-commit window and the stamp→commit round-trip are unverified against the live
   client. Start here.
2. **`[missing mode]` surfacing does not exist** (found during the ADR 0019 recon; the
   single most valuable follow-up). There is no marker on rule boxes, no banner, and on
   the Sets tab a **dead `@Weapon:Caster` gate renders byte-identical to a live-but-
   inactive one** — the player cannot tell them apart. Blueprints' import popup claims
   "the warning appears when you Stamp", but `bpStamp` only checks for an identical rule
   and never inspects mode refs. Build the twin of `groupDefined`/`[missing group]`
   (`ui/triggersui.lua:885`) plus a dead-gate tint on the Sets tab. **This gap is why the
   Overwrite cascade is deliberately confined to the two job-scoped stores and never
   touches the Blueprint library** — a value dead on this job may be alive on eight others.
3. **NIN shuriken: Daken / Sange / Yoru Shuriken** — designed, NOT built, waiting on a
   real NIN. Full record in `docs/design/auto-ammo.md` §8, including the **two live bugs
   on main** it uncovered (the WS-ammo leak at Preshot; Special-vs-trigger having no safe
   configuration) and the five-step field test that unblocks it.
4. **Debug output → files** (Henrik's stated direction, 2026-07-24): rework `/dl debug` so
   output lands in `<dataDir>\debug\` txt files instead of chat. Explicitly deferred
   ("we can leave it as it is for now"), but it is the intended end state.
5. **Icon polish, optional:** the four developer rows share one question mark on their
   section heading rather than each carrying one. Trivial to change if it reads wrong.

## Current state (as of 2026-07-26)

- **2026-07-27: an import can land verbatim — ON `dev`, awaiting field test**
  (`2026.07.27w`). The first feature dlac has taken from **a second player's field
  report** — a friend of Henrik's, who round-trips his own profiles to compare them:
  *"I'm importing dlac how I want them, and it's just changing it every time."* He was
  right, and about a behavior that was correct-by-design in only half its cases: the
  `afterImport` hook re-solves every weighted set from the importer's own gear because
  an export ships **empty shells** — but the export form has a **"Set equipment"** tick,
  and when that gear travels on purpose the re-solve overwrites exactly what was sent.
  New Setting **"Auto-build sets on import"** (Menu > Settings) / `/dl autobuildimport
  [on|off]`, persisted in `uiflags.lua`, **default on** — an absent key reads as on, so
  no existing install changes behavior. Off makes an import land byte-for-byte as
  exported; **Auto-Build All** on the Sets tab still does the re-solve on demand, and the
  import status line says which of the two happened. The gate is checked **after** the
  two "we couldn't build anyway" guards (wrong profile / wrong job), so the opt-out never
  masks their diagnosis. `UIF6a/18a/21a` pin the round-trip, the load and the
  absent-key default; `UIF21b/21c` pin at the source that the hook reads the flag and
  reads it *before* it builds. Suites **3906 + 693**, Windows and WSL lua5.4.
  Still open: whether **default** behavior should also skip the re-solve when the payload
  carried gear — see the note at the end of history.md's entry.
  **Follow-on (`27y`): the last engine-flag-era legacy fallback is gone.** `gearui.dataDir`,
  `gearui.charRoot` and `syncflags.uiFlagsPath` all ended in `charBase() .. 'dlac\\'` —
  unreachable (`profiles.dataDir` and `profiles.charBase` are one `charFolder()` behind two
  roots, so they go nil together), and its only possible effect was to write a dlac-owned
  file into the read-only import tree. All three return `nil` now. **`NE30`** pins the
  nil-together invariant, mutation-verified. Suites **3947 + 693**.
- **2026-07-27: reserved slots stop being invisible — ON `dev`, awaiting field test**
  (`2026.07.27p`). Henrik: *"if we equip a tunic that takes up the headslot, it ignores
  to equip the headslot… there are more items like this. How do we keep track of all
  of these?"* **Answer: we already do, and there is nothing to keep.** `RSlot` (the
  server's `item_equipment.rslot`) has been mirrored per item since v43 and resolved
  generically by `dispatch.reservedDrops` — Vermillion Cloak is not special-cased
  anywhere, it just carries `RSlot = 16`. Verified rather than assumed: catalog.lua
  diffed against the server clone's `sql/item_equipment.sql` = **383 reserving items,
  383 present, 0 missing, 0 mismatched, 0 absent**. The three he named were already
  correct (Kupo Suit → Legs `128`, Decennial Coat → Hands `64`, Decennial Hose → Feet
  `256`), and the whole space is only **9 distinct masks** (Range 131, Hands 74, Feet
  71, Head 52, Ammo 35, Legs 11, Hands+Feet 4, Hands+Legs+Feet 3, Head+Hands 2).
  So the two real gaps were **visibility** and **drift**, and both are now closed:
  1) **The GUI says it out loud.** `renderItemTooltip` prints *"Takes Head — that slot
  stays empty while this is worn"* on every hover card (Equipped / All Equipment / Sets
  / floatgear / lockstyle all share it), and the Sets builder previews the conflict
  *before* dispatch eats it: the reserved tile goes dark red, the hover names the
  reserver (*"Head is RESERVED by Vermillion Cloak — this piece will NOT be equipped"*),
  and one line under the grid lists the slots. New seams `dispatch.rslotText` and
  `gearimport.rslotFor`, so the UI owns **neither** rule — a builder warning that
  disagreed with the engine would be worse than no warning at all. `rsv` is exported
  through `host.provide` on purpose: it runs inside a render pcall, so smoke drives it
  directly rather than letting a dead resolver fail silently forever.
  2) **`apicrawl.py` audits RSlot on every rebuild** (`--rslot-audit` = report only,
  no write), naming every item that gained, lost or changed a reservation. Cosmetic-armour
  batches are exactly this drift class (the clone's last item commit is literally
  "Cosmetic Armor Update"), and a *lost* reservation is the quiet one — `/dl fix` will
  retract that stamp from every player's gear.lua.
  Tests AK23–33 / TR4c–e / smoke S16a–p (3836 + 609, Windows **and** WSL lua5.4).
  Not in the merge queue: Henrik has not field-tested it yet.
- **2026-07-27: the Xvs field day — THREE engine-era fixes, ON MAIN, FIELD-CONFIRMED**
  (`0f1ae6e` v130/`2026.07.27g`, `67edec8` `2026.07.27h`, `c074da9` `2026.07.27i`/ADR
  0025; promoted the same evening on Henrik's go-ahead after Xvs confirmed:
  *"Everything is working perfectly now"* — equips, commits, reinstall, and even the
  WS-menu weirdness gone).
  1) **The native flatten never ran without the GUI.** Every dispatch utils lookup read
  `package.loaded['dlac\\utils']` bare — "loaded first in the LAC state", the job shim's
  own first require — but the NATIVE state has no shim and nothing loads utils at boot,
  so every install refused `flatten produced no sets (world not settled)` every 0.4s
  (Xvs: 20 COR sets, forever; the GUI showed sets fine because it reads FILES, while the
  refusal nil'd the ENGINE store — `/dl lock set Idle` found nothing and nothing
  equipped) until a gearui picker's own lazy `pcall(require)` healed the session. Hence
  "DRK works, BLU/COR don't": per-SESSION, not per-job — a reload broke DRK too.
  Mindie's own mpwarm.txt opens with the same wall EVERY boot, healed in ~1.6s by GUI
  habit — the "~2s of designed refusals" lore was this bug all along. `utilsModule()`
  now requires lazily at all five sites (cycle-safe in both states); tests RQU0-2.
  2) **Manufactured legacy evidence, round two.** Xvs's CLEAN reinstall (both config
  trees deleted) still got "migrate to native": the 07-23 fix held maintainStorage's OWN
  writers during the undecided first-run window, but `profiles.dataDir` kept composing
  the LEGACY home (flag absent → nativeMode false), so the login gear scan planted
  gear.lua under `luashitacast\` and the next beat read dlac's own file back as legacy
  evidence. dataDir now answers nil until firstRunInit latches — addon state only (the
  LAC state's presence IS the legacy verdict; holding there would starve a flag-less
  legacy engine); tests NO50/b, and NE9-14's legacy checks now run under a DECIDED
  legacy world. Pre-promotion field workaround: `/dl engine native on` once on a fresh
  install skips the race outright.
- **2026-07-27, third fix: BORN NATIVE, ALWAYS (ADR 0025, `2026.07.27i`)** — Henrik:
  *"Make it so users start in native mode by default, regardless if there are dlac files
  under luashitacast conf."* `firstRunAction('absent', *)` = `'write-native'`
  unconditionally; the boot no longer scans for legacy data at all (the can't-tell limbo
  is unreachable); an explicit flag on disk is still honored (`/dl engine native off` =
  the only road to legacy); flag-less legacy data becomes a MIGRATION SOURCE
  (`engineAutoMigrate` carries it in on first native login). Tests NO5/NO47/NO49/NO50b
  re-pinned to the new law.
- **Henrik's 07-27 ruling — the LuaShitacast PURGE**: *"remove anything that points to
  luashitacast now. Everyone have migrated"* (stated exception: reading legacy job luas
  for static imports/tables stays). Not started — wants its own staged plan: the 5s
  legacy seeder, `inLac()` branches, check.lua's LAC-tree reads (#131's false alarms),
  "Reload LAC" strings + the Triggers-tab banner, legacy fallback readers. The two fixes
  above are compatible first steps, not the purge itself.
- **The hobby-bar day — DONE, ON MAIN** (promoted 2026-07-27, `96b49be`..`3446978`,
  `2026.07.27a`→`e`; the **Ready to merge** section above stays the authority on status —
  this bullet is the detail, not the queue). Two halves, promoted as one: the searches, then the tab art
  (all four tabs are Henrik's chocobo icons at 64px, hovers reduced to one plain word
  each). Henrik: *"most things are available just fine in the hobby bar, except
  for fishing, but we don't want to overdo it."* Two hobby tabs could only point at the
  Automations tab in grey text; now they open the real thing.
  - **Fishing.** The `TARGET FISH` section moved out of the panel (`fishui.lua`, ~180
    lines) into a **Floating window** — `fishui.renderSearch` → `renderTargetBody`,
    `Fishing -- Target fish###dlac_fish_target`. On the bar, the **target name IS the
    button** (the rod and bait names beside it have worked that way since field round 5);
    the panel keeps a `Target: <fish>` button on its status row and finally gets the
    shared pill, the crowded row that forced its one-off text button having left.
  - **Chocobo.** No new window: the Area/Item dig searches were already floating windows,
    so the tab got the panel's own two buttons routed through new `chocoui.openAreaSearch`
    / `openItemSearch` openers. The grey "go to Automations > Chocobo" sentence is gone.
    Both tabs also got a `Panel` button — on Chocobo it matters, because every odds figure
    in those windows is computed from the dig RANK, which only the panel can set.
  - `/dl fish find [name]` (deliberately not `target`: that one picks the top match, and
    bare it *clears*) and `/dl choco dig [item]`.
  - **The rule this is built on** is now written down in architecture.md and CONTEXT.md:
    *any surface may OPEN a floating window; exactly one place may DRAW it* (gearui's
    `d3d_present`). Two `Begin()`s on one window name silently append into the same
    window — content twice, ids colliding. Openers set flags; they never render.
  - CONTEXT.md gained **Floating window / Panel / Hobby bar** — it had no UI vocabulary at
    all, which is why this task's first sentence ("the hobby menu", "the fish automation")
    needed three rounds of grilling to pin down.
  - Coverage that did not exist before: smoke `FS1-FS19` drive the REAL target window and
    the REAL `fishbar.renderContent` (7c stubs it with a no-op, so those ~180 moved lines
    had never been executed by any test — the craftbar lesson of 7d), plus `HB14` and
    `S139kk-mm` for the openers. `HB3.choco` caught the first version of this work: the
    7c stub had no `SmallButton`.
  - **Field verdicts (2026-07-27, after the promotion).** Three pills — bar, window, panel
    — are right: *"Perfection"*. The armed green frame reads at a glance: *"Looks great"*.
    Both settled; don't reopen them.
  - **The target window is FIELD-CONFIRMED** (2026-07-27, after the promotion): *"I was
    very satisfied with how it opens a new window and search for the fish, instead of
    having to do it solely WITHIN the fish automation menu."* The 760×520 default drew no
    complaint, so the column-width worry is closed. What the field run DID surface was
    older than this work: **only the bait cell was clickable** in the spot list — a
    ~6-character hit box on a row you read left-to-right, so the natural click (on the
    place) did nothing. Present since the feature began, never reported until now. Fixed in
    `2026.07.27f`: the whole row is the hit target (automationsui.autoRow's shape — a
    full-width Selectable first, columns drawn over it), and the three per-cell tooltips
    merged into one row hover. `FS9b/FS9c` pin it, mutation-verified.

- **AutoAmmo is Range-aware — DONE, field-confirmed, ON MAIN** (promoted 2026-07-26 in
  `03d25e1`; this bullet said "QUEUED for main" until the 07-26 night promotion, pointing
  at a queue entry that had already been emptied — hard rule 14's other half). Engine
  **v128**, addon **`2026.07.26j`**. The design record is
  [auto-ammo.md §9](design/auto-ammo.md). Only the loose ends live here:
  - **Hauksbok Bullet (22295) is server subskill 0 — a BOLT despite its name.** Upstream
    LSB data, not a CatsEye divergence, and the server enforces it, so dlac follows it.
    One for `docs/server-questions.md`. (It is also why the name-based Bullets/Bolts
    split can never be the authority, and why `Almogavar Bow` / `Staurobow` — skill 26
    subskill 0, i.e. crossbows named "bow" — made the weapon side undecidable by name.)
  - The Animator/Soultrapper catalog gap found alongside it **is fixed** (`2fe7105`,
    in the queue entry above), not carried.
  - **`tools/` stays gitignored by Henrik's ruling (2026-07-26):** the crawler is not
    shipped, so nobody can spam the server with it. He keeps his own backup. The live
    consequence to remember: `refresh_all.py` → `apicrawl.py` is the only thing that can
    emit `Pair`, and a rebuild from a copy of the tools that predates 2026-07-26 would
    silently drop the field from ~1,173 records and revert AutoAmmo to skill-only with
    no error and green tests.
  - **Open question for Henrik, undecided:** should the within-set rule
    (`trinketRangeDrop`) use the full pairing law instead of only the trinket `RSlot`
    bit? Today a SET naming a bolt with a bow equipped is not arbitrated at all, and
    the server strips a slot. It is the same incompleteness AutoAmmo had.
  - **A field-debug lesson worth not repeating:** the live per-character home is
    `config\addons\dlac\<Char>\` in native mode, NOT
    `config\addons\luashitacast\<Char>\dlac\`. The legacy path still exists with stale
    files in it, and reading it produced a confident, completely wrong "your edits are
    not saving" diagnosis. Resolve through `profiles.dataDir()`, or check mtimes.

- **TRIGGER CASES — the live pipeline. START HERE.** A second tier of `&`/`|` logic for
  trigger rules: every rule body is **case 1**; `+ & case` / `+ | case` add cases, each
  built exactly like the body. One sentence at both tiers: *`&` things bind into one
  together-block, each `|` thing stands alone; fire if the together-block holds or any
  `|` thing does.* Full record: **PRD #124** (grilled 07-26; the design is Henrik's own —
  do not re-litigate; "case"/"together-block", never "group").
  [ADR 0023](adr/0023-trigger-cases-schema.md) records the schema.
  - **ON MAIN since the 2026-07-26 promotion.** Merged: slice 1 display (#125 → PR #130, `da67194`, engine v125 — rule list
    + `/dl why` case-aware, priority-chip fix); slice 2 schema backbone (#126 → PR #132,
    `09f398b`, engine **v127**, addon `2026.07.26e` — `cases` list, oldest-form-first
    serialization, `hasCases` version guard, both serializers in lockstep, dead-mode sweep);
    and slice 3 the **editor skeleton** (#127 → PR #133, merged 2026-07-26, addon
    **`2026.07.26f`** + follow-up `1408ce2` **`26g`** — `+ & case` / `+ | case` buttons, case
    boxes hosting the identical picker flow, pure seams `_loadCases`/`_buildLegs`/`_buildCases`,
    and **the editor flatten fix is IN**: a hand-written multi-condition `|` entry loads as a
    `| case` box and round-trips byte-identically, so editing such rules is safe now). The
    `26g` follow-up (shepherd review finding): a combined `|` entry *inside* a case — engine
    honors it as AND-within-OR, a depth the editor can't represent — splits to standalone
    rows **with a note on the case box, never silently** (the `&` leg's law one tier down).
    Tests TE1–TE44; suites **3691** + **486**, green Windows + WSL. No engine bump in slice 3
    (addon-state UI only).
  - **FIELD-CONFIRMED 2026-07-26 (Henrik): both case types built in the GUI and firing.**
    His click-through produced **field iteration 1** (addon **`2026.07.26h`**, direct on
    dev, same session): (1) the shared condition picker moved to the TOP of the popup,
    outside every container — between the body rows and the boxes it read as owned by
    case 1 forever; every container (body included) now owns its `+ &`/`+ |` buttons;
    (2) **case 1 is a real case** — once boxes exist the body renders as a box with the
    same top-right **AND/OR selection** every box has (it was the one case whose type only
    the system could set); case 1 = OR saves an empty body riding the `|` tier, safe under
    the engine's OR-only law (`matches()` `nAnd > 0`), byte-identical round-trip pinned.
    Tests TE45–TE53. Detail: trigger-system.md §"Field iteration 1".
    **Field round 2 (same day, addon `26m`): `/dl why` case-naming WITNESSED live** — and
    the screenshot exposed a shape bug: a lone `+ |` condition inside a case saved an
    empty-`&`-leg case (`any|` label noise, `case (x)` naming, an unneeded `hasCases`
    guard). Fixed by **canonical case legs** (`foldLoneAny`: an empty `&` leg + exactly one
    `|` entry folds into the `&` leg; the BODY never folds). Henrik's exact rule now
    re-saves as the old pure-OR form, named `standalone status=Resting`. Already-saved
    noisy rules canonicalize on their next edit-save. TE54–TE56;
    trigger-system.md §"Field round 2".
  - **In flight: #128 (polish) — `ready-for-agent` toggled 2026-07-26 after the field
    read landed.** Shepherd its PR next. The agent must NOT regress field iteration 1
    (TE45–TE53 pin it; the layout reactions on #128/#127 override the skeleton's own
    choices). #129 (blueprints) stays unlabeled until #128 merges — one at a time.
    Collision watchlist: engine **v128 is TAKEN** (AutoAmmo Range-awareness, same day) and
    addon is at **`26m`** → next free **v129** / **`26n`**; test ranges
    CS/TC/TE/TRC/MC/TB/LS*/CMD/NK*/LSP are all taken (TE runs through TE56).
  - **Both naming decisions CLOSED 2026-07-26**: (1) the `hasCases` guard token stays —
    maintainer sign-off (camelCase like every condition key; a post-main rename would
    need a player-file migration, so it was decided before promotion, deliberately);
    (2) the slice-1 `/dl why` strings were field-witnessed in Henrik's screenshot and
    survive as designed (`standalone <k=v>` for a lone condition — field round 2's
    canonical legs made that the shape simple rules actually take).
  - Also from this session: the `/dl why` frozen-trace field bug — diagnosed, fixed
    (v126, `97f1edc`), **field-confirmed**; see Ready-to-merge. `/dl check` turned out
    **native-era-blind** (three false alarms on a healthy native setup) — filed as **#131**,
    unlabeled, independent of the cases pipeline.

- **`/dl lock set …` IS A FROZEN CLAIM — ON MAIN since the 2026-07-26 promotion, PARTLY
  field-confirmed** (lock + release of a named set, WHM). Henrik waived the remaining
  field tests as the promotion gate ("I see that the locks worked, and that is enough");
  the owed list at the bottom of this block stays as the post-main checklist.
  (Engine v123→v124, addon `2026.07.26`–`26c`, [ADR 0022](adr/0022-locked-set-is-a-claim.md)).
  This closes the "adjacent bug found, NOT fixed" note left by the naked work, and it
  closes it by **deleting the code** rather than repairing it. Henrik's steer:
  *"take inspiration from how we locked everything \[in naked]… only difference is we
  want this locked to what a specific set holds, instead of no gear."*
  - **What was wrong**: `rawget(_G,'gEquip')` is nil in the addon state, so in native
    mode the one-shot equip landed in `equipengine`'s buffer and the next `fireEvent`'s
    `bufferClear` wiped it — then `setLock('all', true)` locked all 16 slots onto
    whatever you were wearing and printed success. **Why it hid**: three *other*
    unbracketed `M.dispatch('Default')` calls have the same flaw and are harmless,
    because Default re-fires every 0.4s and heals them. `/dl lock set` is the one site
    where that is impossible — the locks it installs are exactly what stops the next
    dispatch from equipping.
  - **A claim is applied inside `M.dispatch`**, which the native engine already
    brackets, so there is no command-path equip left to get wrong.
  - **Four commands, one claim shape** — they differ only in what fills a slot the set
    does not name: `/dl lock set` (held EMPTY), `set-loose` (left available),
    `set-snapshot` (held as worn), `set-current` (all 16 as worn, no set name).
  - **It rides the EXISTING `Locks` row.** No new rank row and no new word — to the
    player, *lock* is one thing. `ARB_ORDER_DEFAULT` is untouched, so **a locked slot
    moves for Naked and Pins and nothing else**, exactly as it does today.
  - **Frozen at arm means the INSTRUCTION, not the outcome**: `dlac:` markers collapse
    to concrete entries once (a locked obi can't follow the weather), but the names are
    re-*located* in your bags every dispatch — freezing container+index would strand the
    hold on the first bag shuffle.
  - **A piece you don't have leaves that slot LOOSE, not empty** ("that's better than an
    empty slot, is it not?"), reported by name and container from a live all-bags scan.
  - **Slot locks coexist** — arming no longer destroys them. `layerRespectsLocks('Locks')`
    is false on its own row, so the hold punches through `M.locks`; a stale lock can
    never sabotage it, and it's still set on release.
  - **ONE LIFETIME RULE for all three** (v124, Henrik: *"I don't want locks to outlive
    a relog, it should not outlive a main job change nor a log… same with naked"*).
    `M.nakedWorldWatch` → **`M.worldWatch`** (old name kept as an alias — the seeded
    LAC-side engine calls it), and it now drops **slot locks** as well as the strip and
    a locked set, on a main job change or the character-select read. Slot locks were the
    odd one out only by accident: nothing watched them, so they rode through character
    select, and the pre-v123 self-swap wipe *looked* like a lifetime rule while really
    being a bug. **None of the three is written to disk** — `__locks` / `__naked` /
    `__held` all sit in the reserved `__` namespace `loadModeState` skips.
  - Release: `/dl lock all off` **and** `/dl lock set off`. `/dl lock` with no args
    prints state plus every variant.
  - **GUI**: the Sets tab's `Equip & Lock` opens a two-option popup — **Strict** fires
    `/dl lock set`, **Loose** fires `/dl lock set-loose` (which had no GUI home before).
    It is no longer a toggle: nothing locks 16 slots any more, so the old
    "16 locked ⇒ show Unlock" flip test had no counter left to read. The **Equipped tab
    owns the state** — the `LOCKED:` readout and the `Lock gear` switch (`set-current`).
    `set-snapshot` stays command-only.
  - **The hovers are three lines each, and that is deliberate** (Henrik, 2026-07-26:
    *"there is TOOOOO much text… this is minimalistic and every word matters"*). What
    outranks a lock lives in Claim Priority, how to release lives on the Equipped tab,
    and which pieces were missing is said in chat at the moment it matters. Do not
    re-import the explanation into the tooltip; it has homes.
  - **The Sets tab render has NO smoke drive** — `S9` checks its tab label and nothing
    else — so the popup is the least-covered thing here. `LSP1`–`LSP10` pin it as
    *source*, because the failure is silent: an `OpenPopup` id that does not match its
    `BeginPopup` id registers the click, opens nothing, and logs nothing. `LSP9` asks
    dispatch's own `LOCKSET_MODES` rather than trusting a string, so a renamed command
    word fails there instead of in the field.
  - Tests `LS1`–`LS20`, `CMD10`–`CMD15`, `LSU1`–`LSU4`. Suites at **3620** and **417**,
    green on Windows and WSL.
  - **Field-CONFIRMED 2026-07-26 (Henrik, WHM):** locking a named set (`DT`) lands it,
    and releasing it lets go — verified after a false alarm that is worth remembering.
    It first read as "he doesn't release it": the cause was **a leftover test trigger on
    idle that re-equipped DT**, not the lock. When a hold *looks* stuck, check the
    Triggers tab before the lock — `/dl why` names the winner.
  - **Field tests still owed**: (1) the same thing at an actual Incursion T3 entrance —
    does the set survive the server-side lock; (2) the missing-piece report, with
    something deliberately left in a Satchel; (3) `set-loose` — do the unnamed slots
    really keep swapping; (4) `/dl lock all off` releasing both halves at once;
    (5) the Equipped tab's `Lock gear` switch and its LOCKED readout.

- **`/dl` COMMANDS ARE TESTABLE NOW — 2026-07-26, ON MAIN** (`7906cd4`, tests only).
  Every `/dl` subcommand used to be tested by *searching `dispatch.lua` for its own
  name* — `NK23`: *"the handler only registers inside `engineActive()`, which is false
  headlessly, so the whitelist cannot be driven — pin it as SOURCE instead."* That is
  precisely how the lock-set bug shipped: present, spelled right, whitelisted, inert.
  The harness arms the native flag, re-loads dispatch so the real handler registers, and
  calls commands with the game closed. It loads a **second** dispatch module, so it
  saves and restores `package.loaded` (dispatch + chatfmt), `gFunc`/`gState`,
  `profiles.nativeMode`/`dataDir`, `ashita.events` and equipengine's `onEvent`/tripwire —
  and redirects `dataDir` to `tests\`, because the `engineActive` block runs
  `loadModeState`/`saveModeState` **at load**. `chatfmt` must be stubbed *before* the
  load: `dispatch.lua:139` binds its shadowed `print` once, at load time.

- **`/dl naked` — BUILT 2026-07-25, ON MAIN since `7231143`, NOT FIELD-TESTED** (engine v122,
  addon `2026.07.25f`, [ADR 0021](adr/0021-naked-is-a-claim.md)). Henrik asked for
  LuaAshitacast's `/lac naked` ("be sure to use the claim arbiter, maybe use locks?").
  The answer to the locks half is **no**, and the ADR records why: a lock only
  *withholds* — it cannot take a piece off — it is wiped by every engine self-swap,
  Pins punch through it, three unrelated buttons release it, and arming it would
  destroy the player's own locks. So naked is an ordinary **Arbiter claimant**, ranked
  first, claiming all 16 slots with the `'remove'` literal both engines already speak.
  - `/dl naked [on|off|toggle]`, `/dl dress`, an Equipped-tab switch, and a transient
    red **NAKED** header button. Bare `/dl naked` always arms — typing "naked" must
    never be the thing that dresses you.
  - **"Naked except my pins" is a drag, not a code path**: drag Pins (or Locks) above
    Naked in Automations → Claim Priority. That falls out of the rank list for free and
    is the reason Naked must stay a *draggable* row.
  - **Lifetime is one line** — `M.nakedArmed = (M.nakedArmed == true)`, the
    `M._loadStamp` idiom. Survives an engine self-swap (a `git pull` mid-session must
    not re-dress you); a fresh Lua state starts dressed, so there is no path by which
    you log in naked — **but a relog is not a fresh Lua state** (an Ashita addon survives
    a logout; `pinwatch.lua:89` records the fact), so the tick disarms on the
    character-select read, and on a **job change** (main job only, announced). Mirrored to
    `modestate.lua` as `__naked` for the GUI only.
  - **`arbOrder` changed for everyone**: a rank row missing from the character's
    `arbstate` file is now restored at its *default position* instead of appended.
    Appended, Naked would have shipped at rank 9 for every character who had ever
    opened the Priority section, and lost every slot it exists to win.
  - Tests `NK1`–`NK29` + `NKU1`–`NKU4`; suites at **3495** and **376**, green on
    Windows and WSL. `NKU*` drives the real Equipped-tab render, because the failure
    it exists for (an unknown Lua name = a silent nil global) is invisible to a load
    test — and the pre-existing drives in that harness `pcall` the render without
    checking, so they never noticed it was dying halfway through on a stub gap.
  - **Henrik's rulings, 07-25**: must not persist through a logout (done); must not persist
    through a job change (done); the TP wipe is **acceptable** because the command is
    deliberate, so nothing is built around it.
  - **Two things to watch in the field**: (1) unequipping a weapon **zeroes your TP**
    and drops Aftermath — accepted, stated in the chat line;
    (2) **Free equip / `/lac disable` silently defeats naked in legacy mode** (LAC
    refuses to unequip a `Disabled` slot) — the command warns and the switch renders as
    unavailable, but confirm that reads right; (3) `/dl dress` brings back only what
    your sets *name* — anything hand-equipped you re-equip yourself (exact `/lac naked`
    parity; snapshot-and-restore is an open follow-up).
  - **Adjacent bug found here, FIXED 2026-07-26** in [ADR 0022](adr/0022-locked-set-is-a-claim.md):
    `/dl lock set` was broken in **native** mode — its `rawget(_G,'gEquip')` bracket is
    nil in the addon state, so the equip fell to the unbracketed path, landed in
    `equipengine`'s buffer, and the next `fireEvent`'s `bufferClear` wiped it. It is now
    a frozen claim on the Locks row, so there is no command-path equip left to bracket.
    See the top of this section.

- **E-BOX RESTOCK v2 — BUILT + PARTLY FIELD-TESTED 2026-07-25, ON MAIN since `7231143`**
  (`2026.07.25e`). The box's contents are no longer polled: they are verified once on
  approach, **debited locally** on our own withdraws, and re-counted only on the few
  events arithmetic cannot see. **Crafting at an E-Box now costs zero packets** (it used
  to cost 200-300 a session). Also: an explicit **Search** button in the add-picker, a
  three-icon nudge (fetch / other-bags / `!box store` with arm-then-confirm), quiver and
  pouch contents counted toward tracked ammo, and **`/dl debug ebox`** — a live readout of
  every packet sent, when, and what caused it.
  - **Start here: [design/ebox-v2-handoff-2026-07-25.md](design/ebox-v2-handoff-2026-07-25.md)**
    — what is verified, the five field tests still owed, and the landmines. The full
    decision record (nine locked decisions, three adversarial review rounds, two field
    rounds) is [design/ebox-restock-v2-grill-2026-07-25.md](design/ebox-restock-v2-grill-2026-07-25.md).
  - Two facts that will bite anyone touching this area: **0x1A4 is a party line with no
    request id** (trove speaks it too, so a foreign stream can be consumed as our answer —
    it cannot be prevented, only made self-correcting), and **a `!box ...` command opens a
    MENU rather than changing anything**, so it arms and waits for inventory movement as
    proof instead of re-counting on a timer.
  - **`/dl debug <topic>` had never worked from the `/dl` prefix** — the router matched
    `'^/dlac?%s+debug'`, and `c?` makes the *C* optional, so the literal prefix was `/dla`.
    Fixed; `/dl debug ls` works now too.

## Current state (as of 2026-07-24, end of day)

- **MODE LIBRARY — BUILT 2026-07-25 (ADR 0019), awaiting Henrik's field test.**
  Triggers tab → new **Mode library** section (beside Blueprints). Per-character
  `<char>\dlac\modes.lua`, outside Profiles, addon-state only; **stamp** an entry onto
  whichever job you are on; share/import as text (the library format IS the share
  format). Pure core `gear/modeslibrary.lua`, UI in `ui/triggersui.lua`.
  - Per-mode **`lib`** button on every mode box saves THAT one mode (the section-level
    "Save this job's modes..." takes all of them); a name already in the library arms a
    gold **`replace?`** second click rather than silently overwriting shared text.
  - **`stamp` = Append** (merge values, nothing removed) — the plain button, because it
    can never strand a reference. **`replace` = Overwrite** — always routed through the
    **pre-commit reference window** (deliberately the same movable window a mode Delete
    opens) listing every trigger rule and every set entry it will edit, with an
    "Append instead" escape hatch. Nothing is changed until the player confirms.
  - **Two corrections to ADR 0019, both found by recon and both load-bearing** — see the
    ADR: (1) the cascade needs **two** ref-walkers, since set-entry gates are a separate
    store from trigger conditions and a dead gate on the Sets tab is *visually identical*
    to a live-but-inactive one; (2) a stranded value does **not** make the engine complain
    per dispatch — it fails **silently**, and a cycle re-seats itself on the commit's
    trigger reload, so only a **demotion to toggle** needs the explicit `/dl mode X off`.
  - **`modeSetRefs`'s decision logic moved out of gearui** into
    `modeslibrary.gateRefsInSet` (tests **MG1-26**). It is the half that DELETES gear
    rows and had no headless coverage while it was a gearui chunk-local. gearui keeps
    the impure rim and now **bails entirely** if the walker is unavailable — a half-run
    cascade (triggers stripped, sets not) is the worst outcome.
  - Engine-owned implicit mode names (`maxmp`, `craft`, `craftgoal`) are refused at
    capture, rename and import. On a name collision the **existing spelling wins** and a
    differently-cased duplicate key is dropped (the Modes section is keyed by name).
  - **Tests: 3279 run_tests (ML\* core, MG\* gate walk) + 341 smoke_ui (MLU\* drives the
    real render path).** Green Windows + WSL. **MLU exists because of a bug it catches:**
    the first draft called a `helpLine()` that does not exist. A *load* test proves
    nothing about that — an undefined global only errors when the line RUNS — so the
    section drives `renderModeLibrary` against a stub imgui. Mutation-verified.
  - **STILL OPEN (recon-found, not yet built):** there is **no `[missing mode]`
    surfacing anywhere** — no marker on rule boxes, no banner, and on the Sets tab a dead
    `@Weapon:Caster` gate renders identically to a live-but-inactive one. Blueprints
    claim "the warning appears when you Stamp", but `bpStamp` only checks for an
    identical rule and never inspects mode refs. That gap is why the cascade is
    deliberately confined to the two job-scoped stores and does **not** touch the
    Blueprint library (a value dead on this job may be alive on eight others).

- **HEADER MENU + SETTINGS — BUILT 2026-07-24 (`ui/menuui.lua`, addon `2026.07.24u`),
  awaiting Henrik's field test.** The header was eight right-aligned buttons; it is now
  **Profiles** (left, unchanged) and **Menu · Migrate** (right). Everything that used to
  sit left of "Reload LAC" — Lockstyle, Macro book, Hobby bar, Teleports, Level override
  — plus **Settings** and a debug-only developer section (Scan/Stage/Commit/Augs) now
  live inside the Menu popup.
  - **"Reload LAC" is DELETED, not relocated.** Legacy LAC is no longer a design
    consideration; both of its red-arm sites in `ui/setupui.lua` were legacy-only, so
    under the native engine it was dead weight. Those two sites are now comments.
  - **The one thing kept OUT of the menu: the in-flight ABORT.** While a teleport/ring
    use is pending the header grows a red STOP button. Transient state must not hide
    behind a click — the same reasoning that killed Reload LAC keeps this visible. No
    pending use, no button.
  - **Settings** (Menu > Settings) is the one place every **Setting** (CONTEXT.md term)
    is reachable: *Open the dlac window* (**new**, 3 values — Never / On login / On login
    + job change), Show all (moved out of the header **and now remembered**), Auto-sync,
    Show item IDs, Auto-build sets on import (**added 07-27**), Debug mode — plus mirrors
    of Build as lv.75, Floating equipment
    window, Teleports floating button and Trigger monitor. The mirrors rebuild from the
    live source field every frame, so they cannot drift from their contextual checkboxes.
  - **Level override is a TYPED number now** (Henrik: the ± buttons "spam level changes,
    it's tedious"). Each ± click used to queue its own `/dl set level main N`; the box
    commits **once**, on Enter or the Set button, clamped 1–75, 0 = back to live.
  - **Icon column is always reserved** (`M._ICON_W`), Dummy'd when a PNG is missing or
    fails to load, so art can land later without shifting layout. **All six icons
    shipped same-day** (Henrik's art, 64×64 transparent, drawn at 16×16):
    `assets\teleports.png` (beacon), `hobbybar.png` (axe — **renamed from
    `craftbar.png`**, which was the asset's only reference; the *module* `ui/craftbar`
    is untouched), `lockstyle.png` (masks), `macrobook.png` (book), `level.png`,
    `settings.png` (gears). The **floating** Teleports button now uses the SAME
    `teleports.png` instead of borrowing the in-game Warp Ring item icon (a different
    visual language); the item icon remains as its fallback. Drawn at **30px** (`t`) —
    and the in-flight ABORT button **derives** its size and its hand-drawn circle/bar
    geometry from that one constant, because the float is `AlwaysAutoResize` and would
    visibly jump size mid-use if the two states disagreed. (The derived ratios
    reproduce the original 26px artwork exactly: radius 10, a 10×4 bar.)
  - **`menu.png` (book) and `debug.png` (question mark) followed.** The Menu header
    button is a **26px icon button when the art loads and the labelled wide text button
    when it does not** — a failed texture must leave an obvious labelled button, never a
    mystery 26px square, and the declared `w` has to match what is drawn because gearui
    right-aligns the row by summing `b.w`. The four developer rows share **one** question
    mark on their *Developer* heading rather than repeating it down the column.
  - **Sized up after Henrik's visual pass** (`s`): row icons **16 → 24**, label column
    30 → 38, header-button icon **16 → 24** (declared width 26 → 34, matching the row icons exactly — SET54). The row's
    `Selectable` now takes an **explicit height** (`_ROW_H`) — without it the click
    target stays text-height and the bottom of every taller row goes dead. `SET51-53`
    pin the layout invariant (`_LABEL_X >= _ICON_GAP + _ICON_W`, `_ROW_H >= _ICON_W`,
    button width > its icon); mutation-verified by bumping `_ICON_W` alone, which is
    precisely how labels would start printing over the art.
  - **`SET42-53` / `MN27-35` pin the icon wiring**: a missing or misspelled asset name
    fails *silently* at runtime (blank cell, right width), so the suite asserts all
    **eight** names (six rows + header button + Developer heading) exist on disk, and
    that `headerButton()` returns the right shape in BOTH the art and no-art cases —
    mutation-verified by removing `teleports.png`.
  - **Why a new module:** hard rule 1. Everything arrives by `M.configure(deps)`
    injection, so gearui gained **zero** chunk locals and the whole thing is headless.
    `dumpAugs` is *passed*, not required — GRD5 forbids a `ui/` module requiring
    `feature/augments`.
  - **Tests: 3164 run_tests (+62: `SET*` menuui cores, `UIF*` the uiflags round-trip —
    `gear/syncflags.lua` had NO behavioural test before) + 324 smoke_ui (+28: `MN*`
    render-stack balance, icon-column reservation, auto-open). Green on Windows AND
    WSL.** The popup bodies run guarded and now print the error LOUDLY (gearui's
    tabGuard rule) instead of swallowing it; `MN12a/MN12b` count what each body draws so
    a dead body fails the suite instead of shipping as a blank panel — mutation-verified.

- **BRANCH MODEL — `main → dev`, and ALL work commits on `dev` DIRECTLY.** Henrik's
  2026-07-24 (evening) revision of that morning's rule: **no local feature branches at
  all.** A branch checked out in this working tree cannot be checked out anywhere else,
  and several Claude sessions plus Henrik share ONE checkout — feature branches made the
  sessions fight over the tree. So: every session commits on `dev`, and `dev` promotes to
  `main` **only on Henrik's explicit go-ahead** (a release he considers stable).
  **Last promotion: 2026-07-26 (`main` == `dev` at the merge, `addon.version`
  2026.07.26n).** Origin
  holds exactly two branches (`main`, `dev`); local-only parked branches
  `feature/autoacc` (GM pending) and `feature/storage-move` are archives — kept, never
  merged, never checked out.
  - **The accepted cost (Henrik's explicit call):** `dev` promotes **as a whole or not at
    all**. A half-finished feature on `dev` blocks promoting an unrelated finished one.
    That is the price of never fighting over the checkout — do not "solve" it by
    reintroducing feature branches.
  - **The one carve-out: GitHub agent runs.** Cloud agents clone their own workspace, so
    their branch can never collide with this checkout — the label-dispatch pipeline keeps
    opening `<slug>` branches and PRs, and those PRs merge into **`dev`** (never `main`).
  (This supersedes the "main is the one development line / origin holds exactly one branch"
  wording in the graduation block below.)

- **Idle hobbies — SHIPPED + field-confirmed 2026-07-24 (ADR 0017).** Craft / HELM /
  Fishing / Chocobo idle are now competing hobbies: **one shared "hobby bar"**
  (`ui/hobbybar.lua`, a `Craft|HELM|Fishing|Chocobo` selector that marks the active
  tab and **locks** to it while it runs), **one active at a time** (lock-while-active —
  `feature/idleexcl.lua` `guardActivate` REFUSES arming a second, no auto-disarm), and
  **one HELM switch** (Auto HELM; the manual "Set HELM Idle" is gone from every surface).
  The floating badge (`ui/idlefloat.lua`) names the active hobby with an Off button. NOT
  the ADR 0012 claim-side dead end — the engine's co-claim is untouched (AR8/9/10 green).
  The three old craft/helm/fish bar windows were unified: each bar body is now
  `<bar>.renderContent(availW)` drawn by `hobbybar`.

- **weatherMatch trigger condition — SHIPPED 2026-07-24 (ADR 0018).** New trigger flag
  `weatherMatch` (Precast+Midcast, tier 30): true when the action's element == the
  CURRENT weather element (`gData.GetEnvironment().WeatherElement`, storm-aware).
  DISTINCT from `dayWeatherBonus` (the obi's signed day+weather net). Engine handshake
  v121. Both this and idle-hobby went `feature → dev → main`; combined **3102 run_tests +
  296 smoke_ui green (Windows + WSL)**.

- **🎓 GRADUATED — main IS the native era.** `feature/native-engine` fast-forwarded
  onto main (`d0736a0..4ae8665`, record `77b4c7e`) after Henrik field-verified every
  onboarding path (fresh install, existing-native boot, legacy Migrate box, AND the
  migration Commit end-to-end). **Main's freeze is over; main is the one development
  line; origin holds exactly one branch.** The tracker is ZERO open issues / ZERO open
  PRs by Henrik's standing rule — #84 (the Phase D lockstyle line-item) is CLOSED as
  parked; **ADR 0015's Phase D section is the deletion list of record** (reopen/refile
  #84 when the sunset window ends with zero legacy users). Onboarding is native-first
  and SILENT: fresh installs are born native and auto-set-up with no ceremony and no
  chat (only FAILURES speak, once — deliberate); a legacy-data user gets the red
  **Migrate** button + the three-part box with the hard rule ("either LAC or DLAC —
  never both at once"). The boot decision seam survived a field bug worth remembering:
  an undecided first-run beat must stay INERT (it used to seed the legacy home and
  then read its own gear.lua template as legacy evidence — history.md "the
  self-manufactured-evidence bug"; also: in-game `ashita.fs.get_dir` returns nil for a
  MISSING dir while the headless popen fallback returns {}, so the suite masked it).
  What remains, all unhurried: the sunset window → the Phase D deletion party; the
  standing offers (maxmp tick/offset persistence, Trigger Monitor native feed,
  augment-string pins); and the graduation-day branding question (the addon is named
  after the thing it no longer needs). One live pre-native artifact: local branch
  `feature/autoacc` (GM approval pending) — never delete, never push. The two blocks
  below are the build-up story, kept as history.

- **E-Box Restock — SHIPPED + field-confirmed 2026-07-24 (grill-with-docs → build).** A
  Crystal-Warrior-ONLY Automations feature — **invisible and inert off-CW at every surface**
  (row, panel, nudge, status, and the `/dl restock` command all gate on `gamemode.get() == 'CW'`).
  A per-item **Target** list where the effective set on a job = **Character list ∪ current-Job
  list** (a same-item Job Target overrides the character baseline); Restock fetches the
  **Shortfall** from the Ephemeral Box on your click — never silently. The load-bearing rule is
  **slot-loss safety** (Henrik's field law, in the pure `feature/restockwatch.plan`): each
  withdrawn stack lands in a *fresh* Inventory slot, so a fetch costs `⌈fetch/stackSize⌉` slots
  and must **never over-draw** (24 fire crystal @ stack 12 = 2 slots; too few slots = lost
  items). On-hand = the field bags {Inventory 0, Satchel 5, Sack 6, Case 7}; room = free
  Inventory(0) slots. A floating **Restock nudge** (Henrik's crate icon, `assets/ebox.png`)
  pops up near a box: hover = the fetch plan, left-click = Fetch all, right-click = open the
  panel. Field-confirmed working (panel, planner, Fetch all, E-Box detection, nudge).
  **↳ REUSE THE E-BOX CLIENT:** ALL E-Box traffic goes through the ONE client
  **`feature/eboxclient.lua`** (**ADR 0016**; it's in architecture.md's Central-services table
  with the full API) — every E-Box feature is a thin CONSUMER (`ui/restockui` = Restock, the
  only one since AutoAmmo's section was removed 2026-07-27). **NEVER open a second 0x1A4 client** — it's a
  party line; two clients race and double the traffic. The client owns the protocol, a shared
  multi-category counts cache, entwatch proximity (`BOX_RANGE = 5`), and the server-load
  throttle (one-in-flight, global min-gap, near-box gate, per-category coalesced). Full spec:
  [design/ebox-restock.md](design/ebox-restock.md). Commits `975896a..b2fab33` on main;
  addon.version 2026.07.24b.

- **THE LOCKSTYLE PIVOT — lockstyle is addon-resident; the Engine equips gear only
  (07-23, PRD #80, RULED — code lands slice by slice).** After the week-long
  silent-apply saga (docs/history.md "the silent apply", "the rest of the travel
  wardrobe"), Henrik reversed the earlier engine-move direction: lockstyle equips
  nothing (it builds its own 0x053 and injects via `AshitaCore`), so its executor moves
  to the ADDON state beside its trigger, and every state-crossing becomes a direct call —
  the command bus stops being in the picture at all. **Start at #80 and its PRD**
  ([issue #80 comment](https://github.com/henkpoa/dlac/issues/80#issuecomment-5057732153))
  — the two-phase hand-over (phase 1 addon-only, phase 2 engine-only v110, gated on a
  field-confirmed spike), the user stories, and the testing gates live there. Decision
  recorded in **ADR 0014**; the durable command-bus law + command-surface rule are in
  architecture.md's "Dual identity" boundary section; the engine-move design doc is
  superseded (banner on it). CONTEXT.md carries the **Addon state** / **Engine** glossary
  entries.

- **THE NATIVE ENGINE — dlac absorbing LuaAshitacast (07-23, branch
  `feature/native-engine` = THE dev branch; main FROZEN until graduation; ADR
  0015 is the standing direction).** The whole LAC dependency behind one
  default-OFF flag (`config\addons\dlac\engine.lua`): `gear/equipcore` (pure
  resolver + 0x050/0x051 builders, LAC-parity), `feature/equipengine` (the
  block→Precast→re-inject→Midcast timing service, 0x028 completion/interrupts/
  pet stream, coexistence tripwire, `ACTION_ROUTES` = the future-dispatchers
  table), `feature/nativedata` (LAC-parity gData incl. sig-scan weather/
  vanatime), dispatch v111–v119 (`engineActive()`; the native sets store
  `M._nativeSets`; bridge machinery inLac-pinned), the storage move
  (`profiles.dataDir()` → `config\addons\dlac\<char>\`, copy-only
  auto-migration). Board: `/dl engine native on` → `/addon unload luashitacast`
  → `/addon reload dlac`. Flag off = byte-identical legacy (2671 + 225 checks
  green both platforms). **Field state: Henrik plays native daily; six rounds
  survived — the maxmp boot saga (v112–v119, history.md "the absorption") ended
  field-CONFIRMED with the boot-readiness architecture: attestations → the
  stability latch → world-keyed belief → producer-validated installs, plus the
  warm trace (`<char>\debug\mpwarm.txt`). Zero packet-pipeline faults so far.**
  Post-merge (main's executor #86 + ADR 0014 absorbed): **lockstyle is fully
  native** (#83 — queueCmd's apply funnel + the typed handler route to
  `M._applyDirect`; field-confirm of the three paths pending). Remaining gaps:
  Trigger Monitor stream, augment-string pins, native check/debug — all listed
  in architecture § The Native engine. NEXT: ruling-4 onboarding (native by
  default for new users + the LAC-alive ask), then the ADR 0015 phases
  (recruit roster → graduation merge → deletion party). Henrik's debug-folder
  rule (07-23): per-char debug artifacts go in `<data home>\debug\`.

- **THE GEAR ORACLE — one door for every gear question (07-22, PRD #69, COMPLETE,
  PRs #75–#79).** `gear/gearoracle.lua` is the single sanctioned door in the addon
  state: `wornItem` / `equipBags` / `canWear` / `anyJobCanWear` / `lookup` /
  `stats` / `setStats` / `petStats` + the augment passthrough. Feature/UI modules ask, never
  re-derive — CI-enforced (run_tests §GRD guards, allowlist EMPTY and it must stay
  so; parity pins hold the three engine twins byte-identical per ADR 0002). The
  oracle is CLAIM-BLIND: capability only — the Arbiter (ADR 0012) stays the sole
  precedence authority; the two compose, never contest. Stat migration proven
  byte-identical by the committed golden corpus (tests/golden/, a STANDING gate —
  a golden diff is a claim a field-tuned ladder moved and needs sign-off). Read
  **docs/design/gear-oracle.md** before touching anything gear-flavored; rulings
  in **ADR 0013**. Field-cleared 07-22 along with the whole prior UNRUN pile.
  Post-ship same day: **pet-channel gear stats** joined the door as `petStats`
  (data/petmods.lua, generated by tools/gen_petmods.py from the server's
  `item_mods_pet` table — the live API never serializes that channel, so the
  repo SQL is the only source). A SEPARATE answer from `stats()` BY DESIGN:
  pet values never fold into master stats (wyvern HP is not your HP) and the
  golden gate pins `stats()` byte-identical. Display composition stays with
  the presenter (`gearfmt.petLines`). Priced for weights later the same evening
  (Henrik's call): `petScoreStats` flattens the channel under `Pet:`-namespaced
  keys (All + best named type — a pet is exactly ONE type), merged at gearui's
  `candidateStats` seam so every scoring path prices pet gear identically;
  `petStatKeys` + statdefs' derived `Pet:` labels put the family in the weights
  stat menu (type "pet" to browse it; pet-type names are search terms too —
  "wyvern" finds Pet:HP%). `stats()`/`setStats()` stay pet-blind — goldens
  byte-identical through the change. **Field-CONFIRMED 07-22.** Deployment
  lesson from round 1: the game loads the MAIN checkout — after pushing, pull
  it (`git -C <checkout> pull --ff-only`) before asking for a field round.

- **Iridescence catalog sweep + universals ladder (07-21, engine v82, manifest
  fmt 10, field-CONFIRMED 07-22).** The shipped catalog's `Iridescence` stat is now the
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
  - **E-Box counts + fetch — REMOVED 2026-07-27** (auto-ammo.md Section 10.8;
    Henrik: "we have E-box restocker now which is better" — Restock reaches
    category 15 with targets and top-up). `feature/eboxammo.lua` is DELETED and
    the panel has no gamemode awareness left at all. Kept below because the
    lessons outlived the feature. It was the FIRST consumer of `gamemode.get()`
    (affirmative `'CW'` shows, Wings/ACE/nil see NOTHING; the server's 0x1A4
    `LOCKED` reply is the second gate), and trove's ebox wire format reimplemented
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
    idiom lives THERE, tests EW*) — use entwatch for any future "is there an X
    near me?", never a local scan. The hidden diagnostic SURVIVED the removal:
    it is `/dl debug ebox scan` now, in `feature/eboxtrace.lua`.
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
  **Visible since `2026.07.27p`:** the drop used to happen in silence, which is exactly
  why it reads as a bug ("it ignores the head slot"). Every hover card now says *"Takes
  Head — that slot stays empty while this is worn"*, and the Sets builder marks a
  reserved tile dark red with a one-line summary under the grid. The GUI keeps **no**
  copy of either rule: masks come from `gearimport.rslotFor` (the resolver the scan
  stamps gear.lua with) and slot names from `dispatch.rslotText`; the preview itself is
  `dispatch.reservedDrops`, the same pass that runs at equip time. Tests: AK23–33,
  TR4c–e, smoke S16a–p (the full live chain against the real catalog).
  **Coverage is not a list to maintain** — the catalog carries all 383 reserving items,
  diffed byte-exact against the server's `item_equipment.rslot` on 2026-07-27. Drift is
  guarded at the source: `apicrawl.py` prints an **RSlot audit** on every rebuild
  (`--rslot-audit` = report only, no write) naming every item that gained, lost or
  changed a reservation. A LOST reservation is the loud one — `/dl fix` will retract
  that stamp from every player's gear.lua. Note `rslotlook` is appearance-only and is
  deliberately NOT mirrored: a Kupo Suit *looks* like it covers hands/legs/feet
  (`rslotlook=448`) but only **Legs** is actually blocked (`rslot=128`).
- **Multi-slot DOMINANCE — dispatch v135 (`2026.07.27t`), Henrik's ruling.** `RSlot` data
  was right and `reservedDrops` was right, but it was being **handed the wrong input**:
  the overlay applies each matching rule's set through its *own* `equipResolved`, so that
  pass never sees more than one rule at a time and **priority never gets a vote**. Two
  field cases the same afternoon, the one gap pulling opposite ways — Hunklor SAM
  (Movement(25) `Body=Kupo Suit` over Idle(20) `Legs=Amir Dirs`: Idle wrote the legs,
  Movement wrote the suit, the server stripped the legs, ~0.4s forever with `moving=true`
  throughout) and Mindie SCH (Idle(20) `Body=Royal Cloak` under Movement(25) `Head=…`,
  where the `worn` arm let the cloak already on his back reserve Head away from the rule
  that **outranked** it — *"This is the wrong logic"*). The rule now: a reserving piece is
  a **candidate only while its claim is dominant over every slot it takes**. Dominant → it
  wins its slot **and claims the reserved ones**, left empty (the server clears them
  itself). Beaten → **ineligible**, its own slot unwritten. `M.reserveFloor` merges every
  matching rule's set in apply order (last-writer-wins, each slot tagged with the priority
  that won it); `M.reserveVerdict` judges it in `RSLOT_ORDER`, resolving dominance **before**
  suppressing anything (a piece must never reserve on its way out) and refusing to let a
  claimed slot claim further (Body takes Legs, so the Legs piece cannot take Feet). Built
  before the first write, **retired right after the trigger loop** — Claim layers keep the
  single-set + worn judgement they were field-tested with, because this floor is the
  *trigger* contest and a rank contest is not a priority number. **NOT YET:** *"go for the
  next available piece"* — `utils.BuildDynamicSets` collapses each slot's list to one name
  before the engine sees it (the AutoAmmo rung-2 trap again), so an ineligible piece leaves
  its slot **unwritten** rather than falling to its next rung. Carrying per-slot alternates
  is the follow-up. Tests AKD1–26 (both real cases, both directions, plus the consumption
  seam pinned so a verdict nothing reads fails loudly).
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
  - **Repeat Last Synth (07-25, `feature/synthrun.lua`, ADR 0020).** The `2 3 4
    5 6` buttons under Last Synth run the same native command N times -- six
    because six is a macro bar's capacity. Still only TYPES it. Verification is
    passive: s2c **`0x030`** (synthesis animation, ~130ms, result type at
    `@0x0C`, actor at `@0x08`) proves the shot landed; s2c **`0x06F`**
    (synthesis results, ~17s, result `@0x04` / quantity `@0x06` / item id
    `@0x08`) names what came out. Offsets are Ashita's stock `craftmon` addon's,
    matched to the CatsEyeXI server structs. **The wait floor is FIELD TRUTH,
    not source math**: the server allows ~17s (15s cooldown + a 16s AI state)
    but the client's synth animation is FRAME-TIED, so the real interval is
    **~22s** in a quiet zone and more in a busy one (Henrik) -- hence default
    30, range 20-120, per character in `craftstate.lua` (craftwatch owns that
    file; do not add a second writer). A shot that draws no `0x030` is retried
    ONCE after 2s, then the run aborts -- inventory-full and out-of-materials
    are permanent and both present as that same silence, because the CLIENT
    refuses to send `0x096` and says `Unable to execute that command.` One
    report line at the end: green `chatfmt.good` only for a full run, yellow
    for an early stop, white for your own Stop. HQ needs no special case -- the
    game names HQ items `... +1`.
    **NOT FIELD-TESTED (as of 07-25). Test plan + full write-up:
    `docs/design/repeat-last-synth-fieldtest.md`** -- read it before touching
    this feature again. Two questions only the field can answer: does the
    client's `/lastsynth` memory survive a ZONE, and does a 20s wait drop
    synths in a frame-heavy zone.
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
    main → `dlac:AutoOneiros|<fallback>`, a 1H or H2H main vetoes the marker; the
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
