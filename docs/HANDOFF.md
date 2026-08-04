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
9. **How other addons read dlac — and, since 2026-08-01, CLAIM GEAR through it** (both
   halves BUILT and field-confirmed). **Writing an integration? Start at
   [examples/claim-example/README.md](../examples/claim-example/README.md)** — a complete
   runnable addon plus the model, written to be enough on its own:
   [design/integration-surface.md](design/integration-surface.md) — the push/pull
   `plugin_event` surface, its two timing contracts, and the **parked plugin-folder**
   design with its rulings (section 10), so neither gets re-derived.
   [reference/integration-guide.md](reference/integration-guide.md) is the consumer-facing
   spec written to be handed to a third-party addon author verbatim.
   **Resuming this work: read §13 of the design doc first** — it holds the state, the
   decision ledger, tomorrow's first move (the **Dispatch Monitor**, which Henrik is
   managing), and the four things not to re-derive.
10. **Writing or reviewing a Job helper module** (the modules that ACT — pet commands,
    ability use — as opposed to Gear helpers, which only equip):
    [reference/jobhelper-authoring-guide.md](reference/jobhelper-authoring-guide.md) is the
    author-facing contract, written as the sibling of the integration guide and to be
    buildable-from without reading dlac source — folder anatomy, the exported table and what
    an `api` mismatch does, **the module API table `S`** (`feature/modapi.lua` — the one surface
    a module asks for everything, since `api = 2`), the lifecycle and containment guarantees,
    declared settings stored by the framework (`feature/modcfg.lua`), the Panel widget kit
    (`ui/panelkit.lua`), the central services a module may consume, and the five hard rules
    (claim-not-commit, one-line acks, consume central services, module independence, the
    sequencer's serialization). The decisions behind it: **ADR 0028** (a module is a folder;
    one folder = one unit of server approval) and **ADR 0030** (a module owns initiation —
    and the "can't catch it in time" rationale that was falsified in the field).

11. **Adding a "click here, land there" control** — a quick-menu row, a nudge click, a bar
    button, a `/dl` subcommand that opens a panel:
    [reference/shortcuts-and-jumps.md](reference/shortcuts-and-jumps.md). A jump is three
    things (panel + tab + window), there is one door for all of them
    (`gearui.openAutomation`), and the tab half is harder than it looks — **ADR 0033** records
    why: this build's imgui binding drops `ImGuiTabItemFlags_SetSelected` on the floor, so the
    host takes the selection by rebuilding the tab bar instead of asking for it. Read the
    guide before writing the row, not after.

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
- **A player's report is the best evidence you will get.** `/dl report` (or the
  Arbiter Monitor's **[Record a report]**) records up to 5 minutes and writes ONE
  sendable file, `addons\dlac\debug\dlac-report-<Char>.txt`: health verdict, config,
  a gear digest with live bag availability, and the decision timeline — starting with
  the decisions **already in memory** when they pressed record. Layout and what it
  deliberately omits: `docs/reference/report-format.md`. Ask for one before theorising;
  `/dl mark <note>` is how the player points at the moment.
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
    only he may add that marker, **and his saying "merge" is itself the marker** for
    everything riding that promotion (2026-08-01; `dev` promotes whole-or-not, so there is
    nothing left to ask about once he has said it). Claude may run the merge and the push
    since 2026-08-01 (`ff92f4e` was the first); older notes below saying the classifier
    refuses both are **historical records of how it was then**, not live procedure.

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

**"Merge" IS an accept** (Henrik's ruling, 2026-08-01: *"When I say merge, treat it as an
accept."*). When he says merge / promote / push to main, that instruction **carries the
acceptance of everything riding the promotion** — `dev` promotes whole-or-not, so there is
nothing left to ask about. Do not go back and ask him to confirm the queue entries first.
The rest of the rule is unchanged and still sharp: **only he grants acceptance**, so never
infer it from a field confirmation, from *"works"*, or from your own read that something is
ready — his own note on the exchange was *"you are right not to assume otherwise since I
haven't told you."* Ask when he has **not** said merge; never ask twice when he has.

**Craft skills under the glyphs, blue when capped** — `2026.08.03zb`. Asked for by Henrik's
friend, in his words: *"he'd love to see his skill levels under the craft icons in hobby bar
for crafting"*, and *"when skill is capped, can we use the same blue"* — with a screenshot of
the in-game skills menu attached. **Both glyph rows carry it** — the hobby bar first, then
the Automations panel's craft row when Henrik said *"Sure, go ahead"* to the offer.

**The blue is the SERVER'S, not a colour dlac invents.** CatsEye sets bit `0x8000` on a craft's
skill word the moment it reaches the guild cap — `charutils.cpp` comments it *"Blue text."* and
`synthutils.cpp` re-sets it on the skill-up that arrives at the cap — and that is the same bit
the game's own skills menu paints. `craftwatch.craftSkillInfo` reads it back through Ashita's
`craftskill_t.IsCapped()`, so the bar cannot disagree with the menu. The arithmetic fallback
(`skill >= (rank + 1) * 10`, the server's own `getCraftSkillCap`) is there only for a binding
that does not expose the bit — it is the same rule, so the two can never diverge.

***FIELD-CONFIRMED, BOTH SURFACES*** *(Henrik, 2026-08-03: *"It works, I checked both. Confirmed
x2"*). Suites **6249 + 1138** on both interpreters — and now the part the suites could never
answer, because every skill value in them is a stub and the exact blue was a sample off a JPEG.
It has been on his screen, on the bar and on the Gear Helpers → Crafting Gear panel. **NOTHING IS
OWED HERE.** Waiting only on his go-ahead to promote.*

*The colour, for anyone who has to touch it later: `COL_SKILL_CAPPED` in `ui/craftbar.lua`, one
constant, sampled at `#659EC9` off the screenshot he sent and nudged up for the antialiasing the
JPEG flattened. It read right against the game's own menu in the field, so it is now a MEASURED
value in the only sense that matters — do not "correct" it back toward the raw sample.*

***What landed:*** *`feature/craftwatch.lua` gains the guild-rank half it never had —
`craftRankCap`, `craftRankName`, `craftIsCapped` (all pure, headless-tested T24h..T24v) over
`M.CRAFT_RANKS` taken from the server's* `scripts/enum/craft_rank.lua` *(to **Legend**, 15; the
enum's own comment ends "16+ invalid", which is why rank 31 — the masked-word rank — is refused
rather than priced at 320). `craftSkillInfo` is the Ashita glue, cached a second because the bar
asks for all eight every frame.*

***The two rows share the CELL, not the row*** *(`craftbar.craftSkillCell` measures,
`craftbar.craftSkillUnder` draws). The bar's glyphs are 30px and equip on click; the panel's are
32px, have their own texture cache, and only switch which craft's items are listed — so the rows
stay separate, but the number, its blue and its hover come from one place and cannot drift. Both
now wrap each glyph in a GROUP and measure the row before drawing it, since a 3-digit skill is
wider than the icon above it and both rows center themselves. **While here:** the comment on
`craftButton` claiming it was shared with the Automations panel was stale — it has no second
caller — and now says what actually is shared.*

**THE QUEUE WAS EMPTIED BY THE LAST PROMOTION; THE ENTRY ABOVE IS NEW.**

*(Emptied by the fourth 2026-08-03 promotion — **`/dl nm`, the placeholders and a FilterScan
filter** (`2026.08.03z`). Henrik: *"merge, and push to origin main"* — an accept under the
08-01 ruling, so nothing was asked twice. It never sat in this queue: asked for, built, and
promoted inside one session. Three already-merged **docs** commits rode along (foodwatch
field-confirmed ×2, the floating icon tray 7-of-7) — records of field rounds already closed,
not new code.*

***NOT FIELD-RUN.*** *Suites **6234** on both interpreters, and the two camps it is pinned
against (**Bonnacon** — Uleguerand, six Buffalo at 354-359, NM 360; **Shadow Eye** —
Xarcabard, one Evil Eye at 206, NM 212) were read out of the server clone **by hand** before
any code existed, then frozen as data tripwires. But **nothing here has been run in game**:
no widescan has been filtered with a generated line. Do not read `/dl nm` onto main as
field-proven.*

***The round owed*** *is small and specific: stand in a zone with a known camp, run `/dl nm`
(does the zone list match what is actually around you?), then `/dl nm <that NM>` and compare
the PH indexes against a live widescan — **the one thing no test can check is whether the
index dlac prints is the index FilterScan shows**, because the two derive it from different
sources (the server's `mob_spawn_points` vs. the client's zone NPC DAT). They agree in the
code (`mobid & 0xFFF` both sides); the field decides whether they agree in fact. Then
`/dl nm <name> apply` with FilterScan loaded, to confirm the queued command actually bites.*

***What landed:*** *`feature/nmlookup.lua` + generated `data/nmdata.lua` (221 zones, 3128
NMs, **371 with placeholders**), built by `tools/gen_nmdata.py` from the **local server
clone** — the generator is gitignored with the rest of `tools/`, so re-running it after a
patch is a maintainer step (`refresh_all.py` step 5), never a player one. The mechanism is
the NM's own `entity.phList`, **not** the scattered `ID.mob.*_PH` tables, and `GetFirstID`
is **zone-scoped** — full reasoning in [architecture.md](architecture.md).*

*(Emptied by the third 2026-08-03 promotion — **the mode lock queue reaches both monitors**
(`2026.08.03y`, **engine v167**). Henrik: *"merge and push"* — an accept under the 08-01
ruling, so nothing was asked twice. One train, and it exists because he asked one question
about the train promoted an hour earlier: *"Where do I see the queue for the mode lock?"*
The answer was one place, and it was the wrong place. Full reasoning in
[history.md](history.md) — *"where do I see the queue"*.*

***NOT FIELD-RUN.*** *Suites **6168 + 1129** on both interpreters, every new rule
mutation-checked, but nothing here has been looked at in game.*

***What landed:*** *the mode lock QUEUE now rides the **decision record** (`contest.mlq`) —
the Arbiter Monitor renders stashed and pinned records and derives nothing, so a live
lookup there would have shown today's answer under an older decision. It is a **signature
leg** as well (the v152 rank-order case: a queuing mode moves no gear and no claim, so
nothing would otherwise retrace), and deliberately **not** part of the decision fingerprint
— the ring appends on a moved outcome, and a queue-only record with zero changed slots is
the v163 symptom. **Arbiter Monitor:** a* `q` *on the cell in both grid modes, holder +
waiter in the hover. **Trigger Monitor:** an* `(n queued)` *count on the* `locks` *line.*

***THE ROUND OWED does not grow*** *— it gives check (5) of the Mode Locks round below
somewhere to look: two modes locking one slot should read* `(1 queued)` *on the Trigger
Monitor and put a* `q` *on the Arbiter Monitor's Main cell, whose hover names both.*

*(Emptied by the second 2026-08-03 promotion — **Mode Locks** (`2026.08.03x`, **engine
v166**, ADR 0034) and **the food register stops believing a zone** (`2026.08.03w`). Henrik:
*"document this, have it ready for merge, merge it and push"* — an accept under the 08-01
ruling, so nothing was asked twice. Two trains built in parallel sessions on one checkout;
the food commit staged itself out of the shared tree without touching the Mode Locks work,
and this promotion carries both. Full reasoning for each in [history.md](history.md) —
*"the slot that stops listening"* and *"the food register stops believing a zone"*.*

***THE FOOD HALF IS NOW FIELD-CONFIRMED, BOTH PATHS*** *(2026-08-03, see the note below).*
***MODE LOCKS IS NOT — do not read it onto main as field-proven.*** *The suites are green on
both interpreters (**6157 + 1121**) and every new rule is mutation-checked, but no mode lock
has held a weapon in game.* **One round is owed, and it is the Mode Locks one.**

***Mode Locks*** *(Triggers → Modes → the* `locks` *button; ADR 0034). On the job with your
Weapon cycle, lock* `Main` *and* `Sub` *to a melee set under the melee value, then pull
something and cast through it — five checks:* **(1)** *the weapons do not move on
Precast/Midcast/WS;* **(2)** *flipping the cycle to the caster value hands them straight back
with no reload;* **(3)** *the Trigger Monitor's* `locks` *line names the held slots while the
rules below it still show their sets;* **(4)** *the Arbiter Monitor's Main cell is gold and
its hover reads* `Mode lock (rank 11)` *over* `Triggers`*;* **(5)** *turn on a second mode
that locks the same slot and confirm the one flipped FIRST keeps it, with the other listed
as queued.*

***One thing to watch, because it degrades quietly by design:*** *a lock naming a set with
no entry for that slot claims **nothing** — the trigger keeps the slot. The window flags it
in red (`[!] no Main in this set`), so if a lock ever "does nothing" in the field, check that
before assuming the claim path is broken.*

***The food register*** — ***FIELD-CONFIRMED 2026-08-03*** *(Henrik, on Mindie BRD:* "Tested,
does not register as eaten food if using warp scroll directly after scrolling"*). The bug the
fix exists for is **gone in game**, on the exact reproduction that found it.*

***The sweep half is confirmed too*** *(Henrik, same day:* "Food watch self heal works, I have
confirmed"*). So **both code paths are proven in game**: the `fmt` 1 → 2 self-heal actually
rewrote his real `foodhistory.lua` and dropped the two impostors, and new registrations no
longer credit a warp scroll with a meal. The dry-run's 7-in / 5-kept result reproduced on the
live file. **NOTHING IS OWED ON FOODWATCH.***

---

*(Emptied by the 2026-08-03 promotion — **two field bugs from one support report**,
`2026.08.03t`, **engine v164**. Henrik: *"commit, merge push to main"* — an accept under the
08-01 ruling, so nothing was asked twice. Both bugs came out of reading Coffeepoo's
`/dl report` (a **second** field tester, not Henrik), and both were the same mistake twice:
**a fact that changes, cached in a file nothing rewrites.** Full reasoning in
[history.md](history.md) — *"two knives and an invisible animator"*.*

***ON MAIN AND FIELD-CONFIRMED*** *(2026-08-03, same day, on Coffeepoo's character —
Henrik: *"Field tested, both fixes worked"*). The base Animator indexed itself with no hand
edit, and the DNC Idle set's `Sub` took the second Bone Knife +1 with no `Count = 2`
anywhere in his `gear.lua`. Suites green on both interpreters (**6054**). **No round is
owed on this one** — both halves are proven in game, not just offline.*

***What landed, for whoever picks this up:***
- ***Two of one weapon pair from your BAGS, not from a stamp.*** *`subSlotAllowed`'s
  same-name off-hand rule had only the `Count` stamp to go on at equip time, and no command
  can refresh it (`/dl sync` is add-only, `/dl fix` is catalog-only by design) — so a twin
  acquired after the first was indexed could never sit in the Sub. `dispatch.M.bagCopies`
  → `utils.slotLadder`. **Best-of**, so a stamped file behaves identically and an unreadable
  bag scan falls back to the stamp rather than demoting gear. `LD6c`–`LD6h`.*
- ***The skill-0 Range families get indexed at all.*** *`gearimport.rangeCategory` replaces
  an exact `Jobs == PUP_ONLY_MASK` test that dropped the ALL-JOBS Animator (17859) and the
  whole soultrapper family out of `gear.lua` entirely. **It can never return nil** — nil is
  what made them invisible. `E29`–`E29i`, `SH10c`–`SH10f`.*
- ***The reason neither was ever reported:*** *`M.stage` printed its skipped items only when
  `not quiet`, and `M.sync` stages **quiet**. Now printed regardless, once per name per Lua
  state. **If you touch the sync path, keep that property** — an item dlac cannot index has
  to say so on the path players are actually on.*
- *Henrik's own `Mindie_29909\gear.lua` carries a **hand-written** Animator entry (a
  `Stats = {}` block no writer in the tree emits). Leave it: it is harmless, the new bucket
  agrees with where he put it, and it is the evidence of what the bug was.*

*(Emptied by the sixth 2026-08-02 promotion — **the pin menu**, `2026.08.03h`–`2026.08.03q`,
plus everything else standing on `dev`. Henrik: *"can you properly document all this, merge and
push to origin. Do note that other things will come with, which is 100 % known by me and OK"* —
an accept under the 08-01 ruling, explicitly extended to the riders, so nothing was asked
twice.*

***What rode along, and its state, because "100% known and OK" is not the same as "verified".***
*The **floating icon tray** (`03g` + `03i`, `ui/tray.lua`) rode along unverified and is now
**FIELD-CONFIRMED, 7 of 7 (2026-08-03)** — see its entry below; the drag-persistence half was
answered last and it stays put. **`/dl report`'s three follow-ups** (`03d`–`03f`, carrying **engine v163**) were in this
queue as NOT accepted, paused on a `/dl report` captured across a **LEVEL-UP** — the only
condition that exercises the v163 fix. The promotion does not close that round: the work is on
main, the verification is still owed, and the recipe survives in
**[design/report-handoff-2026-08-02.md](design/report-handoff-2026-08-02.md)**. Do not read
these onto main as field-proven.)*

*(Emptied by the fifth 2026-08-02 promotion — **`/dl report`, the support recorder**,
`2026.08.03a`–`2026.08.03c`, the dev train `d95371a` + `0c9d113` + `b06e361`. Henrik:
*"document, merge, push"* — an accept under the 08-01 ruling, so nothing was asked twice.
Built, field-run, twice corrected on what the field run showed, and promoted inside one
session, so it never sat here.*

***PARTLY FIELD-CONFIRMED, and the split matters.*** *`03a` was **run in the field**: Henrik
recorded a live DRG session and sent the artifact back — 46 KB, every section intact, and the
PRE-ROLL caught a decision **26 seconds before he pressed record**, which was the whole bet of
the design. So the recorder, the bundler, the streamed log and the file write are field-proven.
`03b` and `03c` are **NOT**: they are the fixes that came OUT of reading that artifact, and
nothing has re-run since. `03c` was verified offline against his real 777-entry `gear.lua` and a
reconstructed record, which is stronger than a suite and weaker than a session.*

***The round owed is one fresh `/dl report` on that same DRG***, checking the three things the
first run could not: the button reading **Un-mark** once a moment is flagged (and one mark in
the summary where he got four), the weaponskill blocks reading `0 placed, 7 left as worn`
instead of seven contradictory `(kept)` rows, and the digest's **second list** naming the 38
pieces his DRG sets ask for that DRG26 cannot wear. Never exercised in the field at all, by
anyone: **`/dl report full`**, and the crash path — the premise that a client which dies
mid-capture still leaves `dlac-capture-<Char>.log` behind.*

*Two things worth carrying forward. The first field report was **read back rather than filed**,
and that is what found three of the four fixes — an artifact nobody reads is an artifact nobody
has tested. The second is the shape of the bug that mattered: the digest was scoped to what
HAPPENED, and the answer lived in what was asked for and never happened. A DRG26 whose entire
`Ws_Default` is level 33-75 gets weaponskills that silently wear TP gear, and no decision record
can say so — the level filter runs at flatten time, before any ladder exists. **A diagnostic
built from observed events cannot explain an absence of events, and an absence of events is what
a support report is usually about.**)*

*(Emptied by the fourth 2026-08-02 promotion — **the missing-set banner is short and ends in a
button**, `2026.08.02e`, `55faca3`. Henrik: *"Field tested, works perfect, merge, push to origin
main"* — an accept under the 08-01 ruling, so nothing was asked twice. Built, field-tested and
promoted inside one session, so it never entered the queue; **FIELD-CONFIRMED**, the second
08-02 promotion that is. The pass covered the banner, the Create click and the created sets on
the DRG that started it; the only thing it could not is the commit-failure path, which needs a
torn or unwritable sets file. Worth carrying forward: the ask was "shorten the message", and
the thing that actually shortened it was giving the player the fix instead of describing it.)*

*(Emptied by the third 2026-08-02 promotion — **"copy to…", the per-rule copy across job
entries**, `2026.08.02b`–`2026.08.02d`, the dev train `13dbf16` + `7f82d57` + `a55049b`.
Henrik: *"Tested it out, document, commit, merge, push to origin main"* — an accept under the
08-01 ruling, so nothing was asked twice, and the first of the three 08-02 promotions that is
**FIELD-CONFIRMED** rather than suites-only. It never sat in this queue for long: built,
corrected twice on his word and promoted inside one session. The correction is the part worth
carrying forward — he asked for the copy across **profiles**, then came back with *"I am in the
wrong here… I meant the job"*, and the job axis cost one round only because the core was written
against the (profile, job) COORDINATE rather than against either surface. What his pass does NOT
cover, and nothing pretends otherwise: the two refusal paths (a torn destination file, a safety
backup that cannot be written) are suite-only by nature — you cannot exercise them in a normal
session — and the profile axis, which he did not ask for and may yet want gone.)*

*(Emptied before that by the second 2026-08-02 promotion, `850e6d5` — **`/dl sends` bills dlac
only for what dlac added**, `2026.08.02a`. Henrik: *"document, merge and push"*. It corrects
the readout promoted hours earlier the same day: a re-injected `0x01A`/`0x037` is the
player's own packet, and lumping it into one total billed dlac for how much he acted. Worth
noting as a pattern rather than an incident — **the promoted version was not wrong, it was
misleading**, and it took him reading one label to find it. Still suites-only; the field
round the first promotion owes now covers both.)*

*(Still empty after the 2026-08-02 promotion of `28ab08d` — **`/dl sends`**, `2026.08.02`.
Henrik: *"Merge and push this to origin main"* — an accept under the 08-01 ruling, so nothing
was asked twice. It never entered the queue: it was built and promoted inside one session,
and `main..dev` was empty when it started, so the promotion carried this train alone.
**NOT field-confirmed — suites only** (5652 green both platforms); the round it owes is one
glance, `/dl sends` after an Incursion stretch, and it is a readout, so a wrong answer costs
a re-read rather than gear. Worth remembering for the next borderline diagnostic: the thing
that decided dlac-over-dlacprobe was that **only the send site knows why it sent**.)*

*(Emptied again by the 2026-08-01 promotion of `a9f1033` — **the clock stops when you log
out**, `2026.08.01l`. Henrik: *"Please push everything locally, even food."* It was written
in a parallel session and had been deliberately left out of the promotion an hour earlier;
his instruction overrode that. **NOT field-confirmed — suites only**, and the Active-food
round it owes is now four checks long. Relabelled `j` → `l` on the way out, because the
external-claims train reached the version line first and took `k`; the card says so, so the
gap in the letters is not a mystery later.)*

*(Emptied before that by the 2026-08-01 promotion of `508d410` — **other addons can claim gear
through dlac**, `2026.08.01k`, engine v162. It never sat in this queue: the field round and
the merge instruction arrived together (*"Make it a permanent setting, then commit,
document, merge and push to origin main"*), which is the "merge IS an accept" rule doing
what it is for. Staged **hunk by hunk** out of a shared checkout — a parallel session's food
work was live in the same tree and is deliberately NOT in this promotion; it is still
uncommitted on disk. Suites were run on the committed tree in an isolated worktree, not
just alongside that work: 5594 + 936, Windows and WSL.)*

*(Emptied before that by the 2026-08-01 promotion of `36da078` — **Auto-build can stay in the
field, and Auto-Build All asks first**, `2026.08.01h`, no engine change. It never sat in
this queue: Henrik's field confirmation and his merge instruction arrived in one message
(*"Works in field, thank you, both settings and the auto build. Document, commit, merge and
push to origin"*), which is the "merge IS an accept" rule doing exactly what it is for. One
Setting — **"Auto-build with gear in storage"** / `/dl buildstored`, default on — plus a
two-click arm on **Auto-Build All**; the scope lines and the three placement decisions are
in the Current-state entry below and in history.md.)*

*(Last emptied before that by the 2026-08-01 promotion — `ff92f4e`, `main` at `4810f94` before it: four
commits, `b64a702..6da40a4` — **the Range/Ammo pair is an Arbiter verdict, and item facts
come from the catalog**, `2026.08.01d`–`2026.08.01f`, engine v159→v161. One field bug and
the two things it exposed underneath.

**The report** (DRK72 Mindie): *"it is trying to both equip Arcane Arbalest in Range, and
Cinderstone in Ammo back and forth, I thought we had that rule set in place so higher level
in non interoperable range ↔ ammo combos would win."*

**`b64a702` — the pair law moves to the Arbiter (v159).** The Level rule was fine. ADR
0010's pair law ran on ONE RESOLVED TABLE while a dispatch's plan is MERGED ACROSS TABLES:
his DRK triggers fire two rules on one condition — `Idle` (Range ladder + `Ammo =
Cinderstone`) and `Weapons` (Range ladder, **no Ammo**). Idle judged the pair correctly;
Weapons, being Ammo-less, asked `trinketWornDisplace` instead and wrote `Ammo='remove'` for
a crossbow the same dispatch had already dropped. Merged, the stick came off; next dispatch,
Ammo empty, nothing to displace, Idle's Cinderstone went back on. Off, on, off, on, forever.
No per-table fix exists — *"is a ranged piece coming in?"* is a question about the FINAL
PLAN. Henrik: *"Maybe it's better to move this rule into the arbiter, since it gets the full
picture from all the sets?"* `arbiter.pairVerdict` judges the merged floor once per
dispatch. **Three laws worth not re-deriving:** it runs FIRST inside `reserveResolve` and
deletes the loser from the floor (adjacency made literal, and the two verdicts can no longer
contradict each other — a Lv75 crossbow *wins* the Level contest while
tie-favours-the-reserver would suppress Range for a Lv60 stick, leaving the plan holding
neither); the loser is **suppressed, never ineligible** (an ineligible piece falls, the next
crossbow down conflicts with the same stick, and the fall re-derives the flap); and it is
one implementation, with the two old functions kept as the direct-caller fallback exactly as
`reservedDrops` is. **FIELD-CONFIRMED** the same day.

**`d052f58` — item facts come from the catalog (v160).** Told the law needed a `/dl fix` to
reach existing files, Henrik cut the migration off at the root: *"It's not like my personal
Arcane arbalest can behave differently in this aspect as anyone else's."* `RSlot` and `Pair`
lived in personal `gear.lua` only because the engine ran in LAC's own Lua state and could
not reach a 5 MB catalog — **the purge ended that**, and `catalogindex`'s header claiming
otherwise was corrected. The stamp is now a **cache**; the catalog answers by id. This
turned out bigger than the missing `Pair`: a `gear.lua` older than `RSlot` (v43) had ADR
0010 **fully blind** and flapping, and never said so. ADR 0010's *"run `/dl fix`"*
consequence is struck out.

**`6da40a4` — one answer per slot (v161).** His screenshot of the working verdict caught the
blemish: `/dl why range` printed both *"nobody claimed it (kept as worn)."* and *"held
EMPTY: …"*. The no-contest line is not a verdict, and a refused slot has an empty contest by
construction. `arbiter.slotVerdict` is the one walk all three renderers ask first, and
**[two-way-arbiter.md §11](design/two-way-arbiter.md)** now states the whole rendering
contract — *"document this properly since we'll probably be touching it again"*.

**Method note.** The whole train was diagnosed and verified headlessly by driving the real
pure functions with values read straight out of `Mindie_29909/gear.lua` and
`profiles/Default/{sets,triggers}/DRK.lua` **before any code changed** — artifacts first,
then theory — and re-running the same script after is what predicted the field result.

**FIELD-CONFIRMED, all three engine versions.** v159/v160 the same day (*"it is not flapping
between arcane arbalest and cinderstone now, so seems to work!"*), and v161 right after
(*"when issuing /dl why on range, it does no longer in fact, say 'nobody claimed it (kept as
worn)'"*) — so both chat surfaces of the verdict are confirmed on the character, not just
headlessly.

**Owed:** one look at the Sets tab's DRK `Idle` set — the Range tile should carry the PAIR
sentence rather than the reservation one, and Set totals should no longer count the
Arbalest. Everything else in this train has been seen working in game.)
commits, `be7250f..a1c6758` — **the arbiter refuses gear you cannot equip, and the Sets tab
stops lying about it**, `2026.08.01`–`2026.08.01c`, engine v158. One bug seen from two
sides: Henrik parked a Minstrel's Coat in a bag he cannot equip out of and lowered his level
until the Coat was his set's best-by-level Body.

**The engine side** (`46c4829`): the whole selection chain asked LEVEL and never asked the
BAG, and availability was only discovered at the end in `equipcore.planSet`, by which time
the ladder was gone — nothing was sent, the slot kept what was worn, and the rung below the
Coat was never asked. Availability is now a **second refusal reason** in `gear/arbiter`,
riding the same fall loop the v135 dominance verdict rides. Henrik's ruling on where it must
NOT go, stated twice: *"It is FINE if claimants file ladders where some of the pieces are
ineligible… which also saves us the trouble of adding yet another field they need to
populate."* No claimant changed. The Monitor reports it (whole ladder, each refused rung
struck through with its reason) and the **receipt** — `vLadderOf` notes each ladder as it
hands it over — means what you read is the ladder that decided, for claimants as well as
sets. **Field-confirmed** the same day (*"Works, thanks"*).

**The panel side** (`a16e3ed`): the engine fell correctly but the Sets tab still highlighted
the parked Coat as the chosen piece while the Royal Cloak beneath it carried no marking. The
highlight now follows the piece that will be **worn**, which also frees the Coat to read red
— the picked-row colour had been painting over the very warning that explained it. Set
totals score what you would actually wear, so **they now move as you shuffle bags**. The
panel calls `arbiter.availPick` — the same module, not a copy — and answers the availability
question ONLY; rank, claims and reservations stay the Monitor's to explain.

Also carried: `4691915` the storage warning once per main job (`2026.08.01` — queued before
its round and **still owing an in-game look**: change to a job whose triggers name something
in the Mog Safe, read the warning once, move gear, confirm it stays quiet until the next main
job change), `4d0d364` the foodwatch round written out, `be7250f` the `2026.07.31f`
promotion record, and `a1c6758` Provenance flagged as a town in `data/zones.lua` — that one
was in the working tree unattributed and was checked rather than assumed (`town` there is
hand-curated, and Celennia Memorial Library and Feretory already carry it with Provenance's
identical misc 4096). Suites **5410 + 925** on both interpreters, re-run **on the merged
main** before the push.

The entry before it:*

*(Last emptied by the 2026-07-31 promotion — `bc581d1`, `main` at `4afec20` before it: two
commits, `d982f91..dcc4eb1` — **the E-Box nudge and the Teleports float are one 36x36
button**, `2026.07.31f` (the other commit is the `2026.07.31e` promotion record, written
after that merge). The nudge asked for 40px of art and passed **no frame padding**, so
ImageButton fell back to the style's `FramePadding` (4,3) and drew 48x46 — bigger than the
Teleports float and not square; it now passes the long form with `NUDGE_SZ = 30` +
`NUDGE_PAD = 3`, matching gearui's `TPF_ICON`/`TPF_PAD`. Suites **5343 + 913** on both
interpreters, re-run **on the merged main** before the push.

**Promoted NOT field-confirmed, on Henrik's explicit call** (*"push to origin main"*,
2026-07-31) — the **third** promotion in one day under that override. Unlike the other two
this one has no headless substitute: it is a pixel size, and eyes on a screen are the only
test. **Still owed:** one look at a box with the crate and the Teleports float both on
screen.

The entry before it:*

*(The 2026-07-31 promotion — `4afec20`, `main` at `5d46bcb` before it: one
commit, `12531f1` — **reserved slots count against the piece that eats them**,
`2026.07.31e`. Auto-build and `/dl best` scored a Royal/Vermillion Cloak in Body *and* a hat
in the Head it eats; `optimizePicks` now takes `opts.reserves` and solves once per
reservation regime (a hill climb can enter a reservation but never leave one),
`levelLadder opts.emptyFrom` cuts the reserved slot's dynamic ladder at the reserver's
level, and Set totals drop what `arbiter.reservedDrops` will drop. Suites **5343 + 913** on
both interpreters, re-run **on the merged main** before the push.

**Promoted NOT field-confirmed, on Henrik's explicit call** (*"push to origin main, you have
my approval"*, 2026-07-31) — the second promotion in one day under that override. Verified
headlessly and through the live resolver chain against the real catalog, but it has had no
in-game look. **Still owed:** rebuild the MP/Refresh set, confirm Dalmatica + the head now
wins, and confirm a genuinely-better Cloak shows an EMPTY Head rather than a hat the engine
throws away.

The entry before it:*

*(The 2026-07-31 promotion — `605045f`, `main` at `b056ff6` before it: the
**Ashitacast/LegacyAC import + "missing gear is never a refusal"**, `2026.07.31a`–`2026.07.31d`
(`910e673`), carrying with it the two commits that were already sitting on `dev` —
`7667a9e` (`2026.07.30f`, the combat FUNCTION-reads fix) and `121af5b` (`2026.07.30g`,
foodwatch). Suites 5320 + 908 on both interpreters, re-run **on the merged main** before
the push.

**Promoted NOT field-confirmed, on Henrik's explicit call** ("push it to main", then "I
allow you to do it", 2026-07-31). The Ashitacast work is verified headlessly and against
his real XML + `gear.lua` — three field rounds went into it — but none of it has had an
in-game look, and foodwatch rode along in the same state after its own bullet below had
said "not queued for merge until it is". Recorded here rather than quietly reclassified:
the queue's field-confirmed rule was **overridden by the maintainer**, not met.

The previous entry, kept because its lesson is the one this section exists for:*

*(The 2026-07-30 promotion — `1551faa`, `main` at `56221c1` before it: the
**Job helper module API v2 + the BST field-round train + the E-Box Restock shortcut and the tab
jump that never worked**, `2026.07.30a`–`2026.07.30e`, engine v157 — **fifteen** commits,
`8471e2d..c8e157c`.

**A correction this promotion forced, and it is the exact failure hard rule 14 exists to
prevent.** The note below claimed the api-2 train (`f8df96b`, `2026.07.30a`) had already gone to
main earlier the same day. It had not: `main` sat at `56221c1` — the 07-29 state — until this
merge, so the Module API, `modcfg`, `combat`, the Panel kit, ADR 0031 and the percent fix all
rode **here**. Neither promotion route named down there was ever completed; PR #150 shows
**MERGED** because these commits reached `main` by the command-block route instead, and GitHub
closed it when they landed. Read the branch state from git, never from this file.

The BST train: `8945574` (pet-death by corpse witness, the
summon space, Dynamic sets, the Summon set, the **keybind registry + ADR 0032**, `/dl jh`,
searchable dropdowns, the jug cap), `cafd7e7` (the jiffies unit, the name-index hedge, the
pickMethod tri-state, once-per-zone food), `8f9e1b5` (**the real root cause** — `type(rec) ==
'table'` on an Ashita resource object, which is *userdata*: the by-name recast resolution had
never worked, and Reward's hardcoded `timerId = 103` masked it), `740dec0` (the field case pinned
end to end), `2761780` (**the pause** — a confirmed death waits `resummonDelay`, default 1.0s,
because "soooo instant" reads as a bot; implemented as the queue, so every existing cancel applies
during the wait). Then `ae6f6a4`: **E-Box Restock in the Teleports quick menu** (above the Hobby
bar, CW-only, the nudge's own crate) and **`host.selectTab` fixed** — a jump had never moved the
tab bar in any cross-link, because a one-shot cannot observe a selection ImGui applies on the
following frame, and because **this build's imgui binding drops
`ImGuiTabItemFlags_SetSelected` entirely**; the host now holds the request until it takes and, if
the flag goes nowhere, rebuilds the tab bar under a new ID with the wanted tab first (**ADR
0033**, `docs/reference/shortcuts-and-jumps.md`, smoke_ui `TAB1`–`TAB25`). Suites **5141 + 867**,
both interpreters. Field-confirmed by Henrik across the day — *"the death detection … is solved
now"*, *"it can read now"*, *"Now it works, perfection"*, and for the jump *"Now it works"* —
and ACCEPTED whole on his *"I also want everything to be merged to main and pushed to origin"*.
**Still owed, and not covered by any of those confirmations:** the Summon set actually landing on
a summon (and the OPEN CHR question in [reference/catseyexi-jobs.md](reference/catseyexi-jobs.md)
— summon-time vs Ready-time — remains open, so it may be aimed at the wrong moment entirely); the
bindable **Summon now** key and `/dl jh`; the searchable dropdowns; the once-per-zone food line;
the jug cap at 75; and **the friend's original report, the Dynamic sets picker**, which nobody has
confirmed fixed. The entry that was standing here for it, written when it was believed promoted: the **Job helper module API v2 + the percent
that printed a pointer**, `2026.07.30a` — `f8df96b` (the api-2 train: `feature\modapi.lua`, the
Module API `S` at `api = 2`; `feature\modcfg.lua`, declared settings stored by the framework;
`feature\combat.lua`, the combat state service; `ui\panelkit.lua`, the Panel kit;
`docs\templates\example-helper\`; BST's four behaviour files rewritten onto all of it; the
authoring guide rewritten; ADR 0031 — **and**, swept in with it, the percent fix: every imgui
text call is a `printf` format string, so `below 51% pet HP` printed a heap address, the kit
escapes at its funnels now and the caption is deleted), `712ccbf` + `b35383c` (the queue entry,
the SHA-and-location correction, and the provenance record of the sweep). Suites **4960 + 817**,
both interpreters. ACCEPTED for promotion on Henrik's *"please document this properly and set it
for handover to push to main"*, and **pushed to `origin/dev`; `main` is HENRIK'S, whole knot and
all.** The 07-29 pattern (*Claude ties the merge knot on local main, Henrik runs the push*) is
**revised by what happened here: the permission classifier refuses Claude the `main` MERGE too,
not just the push.** So the promotion is one command block for him, and the message is
pre-written at **`.git/PROMOTE_MSG`** (untracked by construction, and it holds the honest
train + fix + field-state ledger):

```
git checkout main; git merge --no-ff dev -F .git/PROMOTE_MSG; git push origin main; git checkout dev
```

The trailing `git checkout dev` is not tidiness — **the game plays this checkout's working
tree**, so a checkout left on `main` is the deployment gap all over again.

**PREFER THE PR: [#150](https://github.com/henkpoa/dlac/pull/150) (`dev` → `main`)**, opened on
Henrik's *"push and open the PR"* by the session that built the train — written up before this
note existed, which is why the command block above does not mention it. Merging #150 does the
same promotion and is strictly better here: **CI runs both suites on the exact tree first**
(the command block merges unverified), the promotion stays reviewable, and it needs **no local
merge and no checkout dance**, so the working tree never sits on `main` at all — the deployment
gap cannot open. The command block stands as the offline fallback if the PR route is
unavailable; **do not run both.** Either way the claim is identical: **`main` does not have this
train until one of them completes.** **`git log --oneline origin/main..main` is the authority on
whether the promotion happened, not this file** (hard rule 14).
Behaviour field rounds owed by the Job Helpers era are unchanged and still owed — see *Current
state*; the percent fix's own glance is one look at the Reward section with the rule armed and
acting. Before that: **`dayMatch` was cleared from this queue on 2026-07-30**, late and by a
reader rather than by
its promoter: it went to main inside the SECOND 2026-07-29 promotion, `c07f7ae` (whose subject
names it — *"the Job Helpers era … + dayMatch (2026.07.29a-o)"*), and
`git merge-base --is-ancestor a2153ba main` confirms it. Nobody emptied the section in that
merge, so the queue spent a day claiming a merged feature was pending — precisely the
"is this on main?" unanswerability hard rule 14 exists to prevent. Its field round is
**still owed** and is tracked where owed rounds belong, in *Current state* below, not here.
Its records: ADR 0029, the DM1–DM24 tests, history.md. Before that, last emptied by the FIRST
2026-07-29 promotion: `2026.07.28s`–`2026.07.28v`, the
nine-commit train that closed the E-Box v2 record — the `/dl debug ebox` crash fix (`28s`,
field-confirmed by the bare-snapshot pass: an 11-event ring spanning 1h24m formatted clean, and
the header measured the design's whole promise on its way past — **1 packet sent, 0.0/min,
standing 1.9 yalms from the box**), itembundles 62 → 109 (`28t`, field-confirmed via the
fire-cluster and `198*` Beetle Quiver readings), the Gear Helpers Status column (`28u`,
field-confirmed), the arbiter claimant display labels (`28v`, promoted **before its field
glance** — display-only strings at the render seam, the bounded shape), and five docs commits
closing the record: field round 2 went 5-of-5 (the foreign-stream loop is dead; the "intruder"
was trove's own ebox streams, `rows=0 source=0`), trove's raw 0x1A4 withdraws ruled an
**ACCEPTED COST** ("don't track trove, just don't spam" — §4c of the v2 handoff carries the
ruling and the one condition that reopens it), §6 emptied (option (b) obsoleted-then-declined,
quiver-opening declined, the deposit ask HENRIK-CARRIED to the Trove creator). Both suites
green at 4225. Promoted on Henrik's *"push to origin main"*. Before that, the SEVENTH
2026-07-28 promotion: `2026.07.28r`, a two-line trim to
the yellow hover on Henrik's *"Completely unnecessary. Just bloats the window."* — the header
already said the copies are at your Mog House. Nothing else rode with it. Before that, the
SIXTH 2026-07-28 promotion: `2026.07.28p`–`q`, the two E-Box
Restock rulings — the **yellow icon now asks about the Mog House** (your own Sack/Case/Satchel
count as held; the deliberate over-draw retired) and **searching the box no longer needs a box
in reach** (trove has no distance check on any 0x1A4 action; the near-box gate now covers only
the automatic counting and withdrawals). Promoted on Henrik's *"push to main"* **before their
field round** — the third such inversion today. Both are bounded: the yellow icon is one
advisory surface, and the search ungate can only fail as a query the server ignores. The one
open field question rode with it: whether Mog House containers read from memory while you are
standing in the field (proven for the Mog Safe by gearcheck, unproven for the Locker here).
Records: history.md's *"the bag you are carrying is not somewhere else"* entry, the v2 grill's
C2 revision and §B1. Before that, the FIFTH 2026-07-28 promotion: `2026.07.28o`, the Ventures rings
in the Crafting Gear panel, promoted on Henrik's *"push to main"* **before its field round**
— the second deliberate inversion today, and a cheaper one: display plus one coverage light,
no scoring change, so the worst case is a panel column reading wrong. It rode with the
already-on-dev docs commit confirming the legacy-import fix. Before that, the FOURTH
2026-07-28 promotion: `2026.07.28n`, the legacy-import
robustness fix, promoted **deliberately un-field-confirmed** on Henrik's *"push to main so
he can test"* — the second tester cannot re-test the thing that broke for him unless it is
on main first. **He confirmed it the same hour** (*"it works"*), so the inversion paid for
itself; nothing else was riding. Before that, the THIRD 2026-07-28 promotion: `2026.07.28m`, the fishing
ventures wrap fix, field-confirmed by Henrik the same hour ("Works") and promoted on his
"push to main"; it rode with the integration session-handover doc commit. The entry that
follows records it. Before that, the SECOND 2026-07-28 promotion: the whole `dev` train
`2026.07.28c`–`2026.07.28l` went to main on Henrik's "push it all to main". It carried
four ACCEPTED entries — the **Integration surface end to end + the Arbiter Monitor**
(v152–v154; field-confirmed by eye and by dlacprobe: "I can see the events happening…
it is streaming as we think"; invalidate/confirm/anchors/queries headless-only until
the parser friend connects), the **gear.lua shape fix + seed-own-gear ruling**
(`e`/`f` — accepted un-field-confirmed on the diagnosis; the friend's re-test still
owed), the **old FFXI-LAC Dynamic sets import** (`d`, field-confirmed), and the
**Scroll Lock hide** (`c`, field-confirmed "Seems to work" — `gamehud.hidden()`
central service, fails open, one gate at gearui's draw seam; record: the commit
message + architecture.md Central services + CONTEXT.md Floating window) — plus the
**"Gear Helpers" display rename** (`j`) riding whole-or-not ahead of its own field
round. Full records: the dated entries below, `docs/design/integration-surface.md`
§13, history.md, architecture.md.)*

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
   Copy-from-static) — guard-tested, not yet field-driven. The Copy-from leg grew a
   fourth source on 2026-07-28 (the old files' `sets.Dynamic` block) and a second
   backup home; that ride wants the same field round. Its first real-world file
   (a tester's SCH.lua, same day) failed on all three of parse / old module name /
   pre-flat Ammo — all three now handled or reported (`2026.07.28n`), his re-test owed.
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

## Current state (as of 2026-08-02)

- **2026-08-03: THE NM COMPENDIUM IS FINISHED — the card, and a third way to search — ON A PR
  BRANCH off `dev` (`feature/157-nm-detail-card`), NOT field-run** (issue #157, PRD #151). #156
  shipped the window with the right pane holding a place. This fills it: **select an NM and the
  card shows everything the four slices before it gathered**, and the third filter mode answers
  the one question the feature could not — *who drops this?*
  - **THE CARD COMPUTES NOTHING, and that is the design.** Placeholders and their indexes come
    from `nmlookup.runs`/`filterFor`; the pop kind, repop window, base chance and disfavour
    curve from `nmlookup.popLines`; the live count from `nmtrack.entryLines`; the drop table and
    every TH figure from `nmloot`. Not one percentage is worked out in `ui/nmui.lua`. The payoff
    is not tidiness: **the stale-count rule now holds BY CONSTRUCTION** — `nmtrack` answers
    `chance = nil` for a stale record, so there is no number in the window to render, and the
    window cannot start hedging differently from chat about the same monster in one session.
    Even the *colour* of the count block comes from `status` rather than from reading its words
    back.
  - **BY DROP — the join run backwards.** `nmloot` grew a reverse index (item → pools, built
    once, pool ids sorted first so two runs cannot order the list two ways) and `nmlookup` grew
    `dropRows`. Item NAMES stay out of the index for the same reason they are not in the data
    file: the client cannot name anything pre-login, so the name list is retried while any id is
    unresolved and **frozen the moment they all answer** — a miss must never latch (ADR 0007),
    and `NM74a/b` pins exactly that.
  - **MATCHING IS STRICTER HERE, deliberately.** By name, a typo should still find the monster,
    so a weak match is shown and **labelled a guess**. By drop the player has one item in mind
    out of **2183**, and a list of NMs dropping something spelled a bit like it does not answer
    the question — it buries it. So `ITEM_FLOOR` refuses the near-miss, and a drop row is
    **never** a guess whatever the score: nothing about the monster was matched.
  - **Clicking a drop pivots the list to it**, the mirror of clicking a zone, and both pivots are
    deferred to the end of the frame — acting mid-draw leaves the rows after the click reading a
    mode the rows before it were not drawn in. Pinned: the pivot happens and **exactly one
    window is ever begun**.
  - **Two TH presentation rulings**, both consequences of the bracket lookup. The **verdict** is
    printed at *every* level including TH0 — "no gain, it already drops every time" is the answer
    a player needs before they know to ask for a level. The **figure** at TH0 is held back where
    it would only repeat the rate beside it, *except* for an off-tier rate, which does not read
    back as itself (`gr = 750` reads 24%) and is exactly the number that looks like a bug when
    left unsaid. Both pinned (`NW16h2`-`NW16h5`).
  - The one-click FilterScan apply goes through **`lib/cmdqueue.issue`**, the central command
    door — so the line leaves on the next frame on the main thread rather than from inside a
    render call — and the card **says it went** (hard rule 12: a silent button and a broken one
    must not look alike). The card is deliberately **uncapped** where chat stops at 32 rolls and
    twelve group members: the pane scrolls, so the reason for the cap does not exist.
  - **The window's own list cache had to learn the same lesson.** An empty by-drop result from a
    client that could name *nothing* is "cannot tell yet", not "no NM drops that" — cached, it
    would keep saying so after the client caught up — so that one result is deliberately left
    uncached and heals itself on the next frame (`NW19n`/`NW19o`).
  - Tests `NM70*`-`NM74*` (pure: the index, the mode, the refusal, the lazy-name rule, the
    tie-break) and `NW14`-`NW19` (render, through `nmui._state`). Suites **6777 + 1262** green.
    No engine bump — addon-state only, no seeded file moved, and no new gearui locals (hard
    rule 1).
  - **NOT FIELD-RUN, and the round it owes is specific.** `/dl nm window leaping lizzy`, pick the
    row: the card must show **Rock Lizard x2 at indexes 379, 399**, the curve, and five rolls with
    real item names — **Leaping Boots at `common (15%)`**, Rock Salt twice, and Beastcoin under
    Steal. Set the picker to **TH4**: Leaping Boots must read **45%**. Then `Mee Deggi the
    Punisher` at any TH level: the group must still say **no gain** and Ochiudo's Kote must still
    read a **10% share** (an 18% anywhere means TH reached a member's weight). Then **click
    Leaping Boots** — the list must pivot to the by-drop mode *in the same window*. Then the
    **Apply FilterScan filter** button with FilterScan loaded, which is the only thing here that
    touches the game. It inherits the round owed on `/dl nm` itself and on the four slices below.
  - **The new player-facing strings are unapproved and flagged in the PR** — "By drop", the card
    headings ("Placeholders", "How it pops", "Your count", "Drops"), "Apply FilterScan filter",
    and the by-drop refusal wording. Only "NM Compendium" is settled, from the PRD.
- **2026-08-03: THE NM COMPENDIUM HAS A WINDOW — one list, two filter modes — ON A PR BRANCH off
  `dev` (`issue-156-nm-compendium-window`), NOT field-run** (issue #156, PRD #151). Everything
  `/dl nm` knows was chat-only. `ui/nmui.lua` is the **Floating window** half: master-detail, the
  filter and the result list on the left, the detail card's place held on the right. This slice
  is the **shell** — the list and the **by-name** and **by-area** modes. The card and the by-drop
  mode are #157 and were deliberately not built here.
  - **ONE LIST, SEVERAL FILTER MODES — not several windows.** Every search here returns NMs, so
    one list serves all of them and **clicking a zone re-filters the list already on screen**.
    That is the whole difference from the Chocobo dig search, which needs two windows because its
    two searches return different *kinds* of thing (items and zones) and the cross-link needs a
    second window to land in. Pinned in the smoke suite: a zone click flips the mode and **exactly
    one window is ever begun**.
  - **THE WINDOW OWNS NO ANSWERS.** `feature/nmlookup` grew the pure list side (`nameRows`,
    `areaRows`, `zoneChoices`, `rowNote`, `zoneIds`) rather than the window growing a second
    matcher, and the reason is behavioural: **a weak match is labelled a guess and gibberish is
    refused on both surfaces**, out of one implementation and one `M.GUESS_FLOOR` (800 — the
    threshold chat was already hedging on, now named). On a score tie the entry **with
    placeholders wins**, expressed as a total sort order (score → placeholders → zone → name) so
    a 2000-row list cannot reshuffle between frames. Pinned twice: against `Poisonhand Gnadgad`
    (Davoi, 8 placeholders, beats two Campaign copies with none — and Davoi's zone id is the
    *higher* one, so the tie-break is doing real work) **and** against a synthetic pair, so the
    rule stays pinned on a day the shipped table holds no tie.
  - **ONE DRAW SITE**, gearui's `d3d_present`, self-gated on `M.visible` — any surface may open a
    floating window, exactly one may draw it, or two `Begin()` calls on one name merge both
    bodies into it. Pinned as **source** (`imgui.Begin` once in the module, `nmMod.render` once
    in gearui), because a render check can only see the window the module itself draws.
  - **The list scrolls and the cap speaks.** Escha Ru'Aun holds **61** NMs; the rows sit in their
    own child, and a name search is capped at 200 rows with the remainder counted out loud. The
    result list is cached on (mode, query, zone) — a name search scores every shipped entry,
    Levenshtein included, and doing that per frame is the difference between a window and a
    stutter.
  - Opened from `/dl nm window [name]`; **bare it opens on the zone you are standing in**, so the
    common case takes no input. `apply` / `reset` / `th` beside it are answered, not eaten. A
    build where the GUI failed to load loses the verb *and says so*. Tests `NM60*`-`NM68*`
    (pure) and `NW1`-`NW13` (render, through the exported `nmui._state` seam). Suites
    **6742 + 1197** green. No engine bump — addon-state only, no seeded file moved; the UI chunk
    still loads headless (no new gearui chunk locals, hard rule 1).
  - **NOT FIELD-RUN, and the round it owes is specific.** `/dl nm window` while standing in a
    zone with a known camp: the list must hold what is actually around you, campable ones first.
    Then **`/dl nm window bonnacon`** (an exact hit, no "(guess)" anywhere) and
    **`/dl nm window bonacon`** (the same NM, and the list must *say* these are closest matches).
    Then click a row's zone button — the list must pivot to that area **in the same window**.
    Finally a busy zone (Escha Ru'Aun) to confirm the list scrolls rather than running off the
    bottom. It inherits the round already owed on `/dl nm` itself. **The small labels are
    unapproved** — "By name", "By area" and the pane wording are flagged in the PR for a naming
    call; only "NM Compendium" is settled, from the PRD.
- **2026-08-03: `/dl nm` NOW ANSWERS "IS A THF WORTH BRINGING FOR THIS?" — a per-drop Treasure
  Hunter verdict — ON A PR BRANCH off `dev` (`issue-154-th-verdict`), NOT field-run** (issue
  #154, PRD #151). The drops section could say what an NM gives but not whether TH would move
  any of it. `feature/nmloot.lua` now carries the server's own TH table (rows 0-14, seven
  rarity brackets) and its `getDropRate`, ported verbatim, and `/dl nm <name> th4` renders every
  roll's rate at that level.
  - **TH IS A BRACKET LOOKUP, NOT A MULTIPLIER**, which is the only reason this is answerable:
    the rate selects a bracket, the TH level selects the value inside it. A common ungrouped
    drop reads **15% at TH0, 45% at TH4, 70% at TH14** — Leaping Boots, pinned against the
    live-verified figures.
  - **THE UNITS ARE THE TRAP.** The lookup works out of 10000 and its caller hands it
    `DropRate * 10`; every entry point takes the STORED rate and does the times-ten itself, so
    no caller holds two scales. A missing times-ten reads a common drop as ultra rare and still
    looks like a percentage.
  - **THE VERDICT IS THE FEATURE, NOT THE NUMBER.** A rate already at 100% short-circuits
    unchanged, so **Ochiudo's Kote — a 10% share inside a `gr = 1000` group — gains nothing from
    any amount of TH**, and the line says so *in words*: an unchanged number is indistinguishable
    from a number nobody applied TH to. Asserted at every level 0-14, in both directions (the
    group rate and the share).
  - **TH applies to the GROUP rate only**, never to a member's weight, and never to which member
    wins. The Kote's weight of 100 would read 18% at TH4 if the wrong rate were looked up; that
    number is pinned absent. Shares still sum to 100 after the group rate is lifted.
  - **One consequence needs a ruling and is flagged in the PR:** because the rate only *selects*
    a bracket, an off-tier rate does not read back as itself — the 68 shipped rows at `gr = 750`
    sit in the top bracket and read **24% at TH0, 64% at TH4**, i.e. *below* the rate the table
    states. That is the lookup as the issue specifies it; the line says the stated rate only
    picks the bracket so it cannot read as "TH lowered my rate". If the live server does not run
    the lookup on off-tier rates, this is the line to revisit.
  - Figures are opt-in (`th4`, `th 4`, clamped to 0-14 out loud, composing with `apply` and
    `reset` in any order); without a level the section gains **one** line — whether TH can lift
    anything here — because a TH figure on every line is noise for the four jobs in five that
    cannot bring any. Steal and Despoil carry no TH figures and say why. Tests `ND10*`-`ND19*`;
    suites **6688 + 1138** green. No engine bump — addon-state only, no seeded file moved, and
    no UI (no gearui locals, nothing new in the UI chunk).
  - **NOT FIELD-RUN.** Everything here is arithmetic over a committed table, so the round it
    owes is short: **`/dl nm Leaping Lizzy th4` — Leaping Boots must read `common (15%) | TH4
    45%`**, which proves the units, the bracket and the render in one command. Second:
    **`/dl nm Mee Deggi th14`**, which must still say *no gain* and still show the Kote at a 10%
    share. Third: `/dl nm <anything> th20` clamps to TH14 and says it did. It inherits the round
    already owed on `/dl nm` itself and on the drops readout below.
- **2026-08-03: `/dl nm` NOW SAYS WHAT AN NM DROPS — grouped as groups, Steal and Despoil kept
  out of it — ON A PR BRANCH off `dev` (`feat/153-nm-drops`), NOT field-run** (issue #153,
  PRD #151). The command could tell you how an NM pops and where you stood on the curve, but
  not whether it was worth camping. `feature/nmloot.lua` joins the NM to the committed
  `data/nmdrops.lua` (973 pools, 5372 rows, crawled from the **live API**) through its `pool`
  field and closes the card with the drop table. **Addon side only** — the crawler half was
  already committed by the maintainer, `tools/` is gitignored and nothing under it or under
  `data/` was touched.
  - **A GROUPED ROW'S `r` IS A WEIGHT, NOT A PERCENTAGE.** The group rolls once at `gr` and
    then ONE item inside it wins by weight, so 2009 of the 5372 rows — more than a third of the
    table — would be misstated by a flat percentage. Groups render **as groups** ("one of
    these, always (100%): Impact Knuckles 90%, Ochiudo's Kote 10%") with each member's **share**
    of the group. **Mee Deggi cannot pin this and must not be used to**: its weights sum to
    exactly 1000, so the share and the flattened reading are both 10% and a flattening bug
    passes. The pin is **Ouryu's pool 3070** — two items at 425 under `gr = 750`, share 50%
    against a flattened 42.5%.
  - **Duplicate rows are two rolls, and stay two.** Leaping Lizzy lists item 926 at 240 *and*
    at 150; the section head counts **rolls**, not items, so the repetition reads as the
    mechanic it is rather than a bug.
  - **Steal and Despoil are not kill loot** and get their own section — listing them as drops
    tells a player to expect something a kill will never give. Most carry `r = 0` (the API
    states no rate) and that is left **unsaid**, never printed as "0%".
  - **Where one group ends is a RUN over `(g, gr)`, and the data forced it.** Pool 245 lists
    group 1 four times at `gr = 1000` and then the same four items as group 1 again at
    `gr = 100`; 86 rows carry a group id whose rate changes under it. Keying on the group id
    alone would discard one of the two rates and the roll with it. **This is the one place the
    issue is silent** — flagged in the PR for a ruling.
  - **Item names resolve from the client's own resources, lazily and one id at a time**, never
    at load (a name table built at load runs before login and gets nothing back). Only a HIT is
    cached — a miss is "cannot tell yet", not "no such item", and latching it would make one
    early read permanent (ADR 0007). An id that will not resolve renders **as an id**.
  - Three absences are told apart (hard rule 12): no drop table names the file; an NM whose
    pool has no rows says so plainly; a pre-`pool` `nmdata.lua` says the drops cannot be looked
    up. Two caps keep chat sane (12 members per group, 32 rolls) and **both say what they left
    out**. Suites **6596 + 1138** green. No engine bump — addon-state only, no seeded file
    moved, and no UI (no gearui locals, nothing new in the UI chunk).
  - **NOT FIELD-RUN, and one thing can only be settled in game: THE ITEM NAMES.** Everything
    else is arithmetic over a committed table, but `AshitaCore:GetResourceManager():GetItemById`
    is stubbed in the suite. **First field check: `/dl nm Leaping Lizzy` — five rolls with real
    item names (Rock Salt twice, Leaping Boots) and Beastcoin under Steal proves the whole chain
    (join → rolls → tiers → names) in one command.** Second: `/dl nm Mee Deggi` for the group
    line. Third: any `item #<number>` still showing after a full login means the resource read
    is wrong, not the table. It inherits the round still owed on `/dl nm` itself.
- **2026-08-03: PASSIVE POP TRACKING — the placeholder rounds you personally witnessed, and a
  count that refuses to lie — ON A PR BRANCH off `dev` (`issue-155-pop-tracking`), NOT
  field-run** (issue #155, PRD #151). `/dl nm <name>` could state the disfavour curve but not
  where on it you were. `feature/nmtrack.lua` counts placeholder kills as they happen,
  converts them to **rounds** (`kills / phCount` — six Buffalo make **one** Bonnacon round)
  and renders the **current** chance under the curve, plus the rounds left to a guaranteed pop.
  **Automatic, nothing to arm.**
  - **BY TARGET INDEX, NEVER BY NAME.** Uleguerand holds ten Buffalo and only six (354-359)
    are placeholders; a name would credit four mobs that never rolled and read HIGH. A name is
    allowed to answer for the **NM itself** only — where a false positive can only RESET a
    count, never inflate one.
  - **Two observations already in the addon, joined:** `engagewatch` knows the INDEX of what
    you attacked, the `text_in` death line knows WHAT died. A death is matched to the newest
    engaged target of that name and **consumes** it, so one engagement credits at most one
    kill. What is left over is an **under-count**, which is the safe direction.
  - **The honesty rules are the feature.** The count is a **floor** (the server's counter is
    zone-wide and shared) and says so beside every number. Zoning, a relog/reload, or an age
    past the NM's **own** ceiling makes it **stale**, and a stale record shows the raw count
    and when it was last vouched for and renders **no percentage at all** — the error a break
    makes runs optimistic. Staleness is **sticky** (nothing can re-vouch for a break); pop
    evidence zeroes the count, and `/dl nm <name> reset` is the one manual door. Kills inside
    the post-kill **cooldown** or while the NM is **primed** are tallied as wasted effort
    rather than sold back as progress, and the *uncertain* part of the cooldown window is said
    out loud instead of counted as clear.
  - **The curve is CONSUMED, not re-carried** — `chanceAfter`/`roundsToGuaranteed` stay in
    `nmlookup` with their anchors; `NT00d` greps the tracker's source to pin that the formula
    was never copied. Load-time dependency runs one way (`nmtrack` → `nmlookup`); the reverse
    is call-time, so there is no cycle.
  - Persisted per character at `<char>\dlac\nmcounts.lua` through `lib/statefile` +
    `lib/safewrite`, like the other passive watchers. New: `/dl nm counts` (which camps am I
    part-way through) and `/dl nm <name> reset`. Suites **6475 + 1138** green. No engine bump
    — addon-state only, no seeded file moved, and no UI (no gearui locals, nothing new in the
    UI chunk).
  - **NOT FIELD-RUN, and one thing here can only be settled in game: THE DEATH LINE.** The
    tracker recognises `"The Buffalo falls to the ground."` and `"<Player> defeats the
    Buffalo."` (`M.DEATH_FALLS` / `M.DEATH_DEFEATS`). If CatsEyeXI words a mob death
    differently, **nothing will ever count** — silently, because an under-count is the
    designed-safe direction. **`/dl nm counts` on an empty tracker is the diagnosis**: it
    prints the last engaged target *with its index* and the last death line it recognised, so
    "nothing killed yet" and "the wording is different here" cannot look alike.
    **First field check: kill one placeholder at a known camp and run `/dl nm <that NM>` — if
    the count says 1, the whole chain (edge → death line → correlation → index → round) is
    proven in one kill.** Second: zone out and back and confirm it reads STALE with no
    percentage. Third, the one that would be embarrassing to miss: kill a same-named mob that
    is NOT a placeholder (Uleguerand's Buffalo at 26-29) and confirm the count does **not**
    move. It also inherits the round already owed on `/dl nm` itself (below): no widescan has
    yet been filtered with a generated line.
- **2026-08-03: `/dl nm` STOPS PRESENTING THE BASE CHANCE AS FLAT — the disfavour curve is
  hand-carried — ON A PR BRANCH off `dev` (`issue-152-nm-disfavour`), NOT field-run**
  (issue #152, PRD #151). `/dl nm <name>` printed *"5% per kill"*. That is only the **base**:
  CatsEyeXI applies **disfavour** (bad-luck protection) to lottery pops, so every completed
  placeholder **round** lifts the chance until a pop is guaranteed, and a camper reading 5%
  had no idea that 30 rounds in he is at 17% and that the last quarter is near-vertical. The
  readout now states the base, that it is **not flat**, three quarter-way sample points and
  the rounds to a guaranteed pop.
  - **The curve is a hand-carried constant** (`nmlookup.M.DISFAVOUR`) with its **source and
    verification date beside it** — it exists in **no branch** of the public server repo,
    because the loader activates a `catseyexi` overlay that is empty there, and scraping a
    wiki for it was rejected as a way to silently poison the odds. **The tests are its
    source**: `NM40*` pins all four published anchors (5→40, 10→20, 15→14, 20→10) and `NM41*`
    pins the **middle** of the curve — anchors alone only fix where it reaches 100%, and six
    plausible wrong formulas were checked to confirm the mid-curve values are what actually
    discriminate them.
  - **Only `kind == "lottery"` gets a curve.** `scripted` / `timed` / `weather` / `night` NMs
    get their own plain words and their respawn. **Five shipped entries carry placeholders
    AND a scripted kind** (Charybdis, Crypt Ghost, Magicked Bones, Sea Horror ×2) — their
    indexes stay in the filter, the lottery language does not. Charybdis is pinned as the
    tripwire for exactly that, so a regeneration that lost `kind` fails the suite instead of
    quietly restoring the wrong words.
  - Everything else is untouched and still pinned: fuzzy matching, guess labelling, gibberish
    refusal, the FilterScan filter, `apply`, and the missing-data warning. No engine bump —
    `nmlookup` is addon-state only, and no seeded file moved. Suites **6337 + 1138** green.
  - **NOT FIELD-RUN, and it inherits the round still owed on `/dl nm` itself** (the entry
    under the fourth 2026-08-03 promotion above): nothing has ever filtered a live widescan
    with a generated line. Two things this slice adds to that round — does the `kind` word
    match what the zone actually does, and does the curve read right to someone who camps?
- **2026-08-03 (`2026.08.03w`): THE FOOD REGISTER STOPS BELIEVING A ZONE.** Henrik's first
  field round on foodwatch found it: *"it is showing my instant warp scroll as recently
  eaten... I tried to use a warp scroll almost immediately after zoning after everything
  hadn't loaded in properly."* His own `foodhistory.lua` carried **two** bad rows, not one —
  an **Instant Warp** and a **Flask of Echo Drops** — and each was wearing the *remaining
  time of the real meal still running underneath it* (`dur 19381` against the Pork Cutlet's
  `21598` eaten 2219s earlier; the Echo Drops the same against a Grape Daifuku). That
  arithmetic is the diagnosis: the food effect never dropped, so nothing was eaten.
  - **THE MECHANISM: food is PAUSED while a zone loads.** The server hands the effect back
    with its expiry pushed forward by however long the load took — **+2s** and **+6s** in
    those two rows, and the raw values are in the file if you want to check the subtraction.
    `_step` compared expiries for **inequality**, so it read that drift as a second meal and
    blamed whatever item you had used in the last 8 seconds. A warp scroll is used at exactly
    that moment, and a warp scroll IS a zone, so it triggers the very thing that frames it.
  - **The comment above that branch said it "cannot fire wrongly."** It had been there two
    days. It is the reason to distrust a claim that a comparison is safe *because nothing
    else can move the value* — something else could, and the field found it first.
  - **`data\fooddb.lua` now VOUCHES, and the display-only law is retired.** It is generated
    from the server's own predicate (`xi.itemUtils.foodOnItemCheck`, 783 scripts on `stable`
    `9bb0ec8c67`), so it is the same authority the effect is, only readable *before* the
    fact. Neither impostor is in it. **Absence is still not a veto** — a food the server adds
    tomorrow looks exactly like a non-food from in here, so an unlisted item is *unvouched*,
    not refused, and is still learned from a clean edge (FW31 guards that; it is the reason
    the escape hatch exists at all).
  - **Four gates, and each one earns its place**: a re-eat must clear `REEAT_JUMP` (15s — a
    zone drifted 2s and 6s, the shortest food on the server runs 30s, so the band is real
    and not a fudge); a meal cannot have more time left than the item could grant, doubled
    for `FOOD_DURATION` (this is the *refused use* — you cannot eat over food here, so an
    over-long effect is an older meal reappearing); an unvouched item is believed only on an
    **appeared** edge, never a re-eat; and never within `ZONE_SETTLE` (15s) of an `IN 0x00A`.
    A **catalogued** food skips the zone wait, so "zone in, eat" still works.
  - **The catalogue also PICKS, which the effect never could.** Eat a Cutlet, quaff a potion
    two seconds later, and the potion is the newest use when the effect lands — one pending
    slot hands it the credit. `M._choose` keeps a second slot for the newest use the table
    calls food and prefers it. That hole predates this bug and was never reported.
  - **The history file heals itself on load** (`fmt` 1 → 2, `M._sweep`). Verified against
    Henrik's real file: drops exactly the two impostors, keeps all five real meals in order.
    `/dl food forget` was the wrong tool — it would have taken the Pork Cutlet with them.
    Rows learned without the table carry `learned = true` and are never swept.
  - **NOT field-confirmed — suites only** (**6087** + **1108** on the committed tree in an
    isolated worktree; 6157 + 1121 alongside the parallel Mode Locks work in the shared
    checkout). The round it owes is short and specific: zone, use a warp scroll immediately,
    then `/dl food` and check nothing new was recorded; and confirm the two junk rows are
    gone after one load.
  - Full reasoning: `docs/history.md` → *"the food register stops believing a zone"*.

- **2026-08-03 (`2026.08.03r`): `/dl unused` — THE WARDROBE AUDIT.** *"which pieces you have
  in mog wardrobes that are actively not being used at all"* (Henrik). `gear/unusedgear.lua`
  is `gearcheck` read backwards: start from the BAG, ask whether anything references the
  piece, across **every profile and job entry** (dormant archives included) — triggers → the
  sets they point at, lockstyle boxes, the gear-helper manifests, ammo rules, rod+bait, job
  helper pins, and what you are wearing. `ui/unusedui.lua` shows the **last saved** report
  (`<char>\unusedreport.lua`) with a Refresh button; `/dl unused scan` answers in chat.
  **ON MAIN** (promoted 2026-08-03 on Henrik's *"commit to dev, merge and push"*), and
  **NOT field-confirmed** — one round is owed: `/dl unused`, Refresh, and a look at whether
  the three sections say true things about his own wardrobes. Suites **6035** + **1108**.
  - **ITERATION 1, and he said so while accepting it**: *"this is just a first iteration, we
    will most likely work on this more and combine features, especially when / if storage
    move is accepted."* The join he means is `docs/design/storage-move.md` — the right-click
    **Move To →** research (feasible, server-validated, never built): with it, a flagged row
    could move itself to the Mog Safe instead of just naming itself. The rows already carry
    id + container + copy count, which is what a move needs. New "what asks for an item"
    sources belong in `M.collect`'s buckets / `M.HELPER_PINS`, never a second walk.
  - **A lockstyle-only piece is MOVEABLE, and that is a server fact — in two halves.**
    `c2s/0x053_lockstyle.cpp` (`Set`) stores the id checking only that it is real equipment
    that fits the slot; the RENDER gate is `charutils.cpp UpdateArmorStyle`, which needs
    `HasItem(PChar, id)` + `canEquipItemOnAnyJob`, and `HasItem` walks **every** container.
    So: **container irrelevant, ownership still required** — move it anywhere, do not sell
    it. (I first wrote "never reads ownership or container" off the packet handler alone and
    shipped that wording; corrected one commit later. A handler that accepts a value is not
    the code that uses it.)
  - **Three sections, because there are three answers**: nothing references it / only a
    lockstyle box does / only a set no rule triggers (his character: 63 untriggered sets out
    of 257 — never call those pieces junk). Helper picks COUNT as use and name their helper;
    the manifest's `mp`/`rf`/`mv` tables do NOT — they are stat caches, not pick lists, and
    counting them would mark every refresh piece owned as used.
  - **Set names claimed by config, not by a rule**, are promoted with the reason attached:
    `autogear.mpPairIdle` and a job helper's `summonSet` (BST's `Chr_Swap`). New pins go in
    `M.HELPER_PINS` — declared, never sniffed.
  - Full reasoning: `docs/history.md` → *"what is in the wardrobe that nothing asks for"*.

- **2026-08-03 (`2026.08.03h`–`2026.08.03q`): THE PIN MENU — several pins per slot, and a
  right-click window that holds still. **FIELD-CONFIRMED** by Henrik across ~six rounds of
  screenshots and a final play test (*"I field verified it now, it works also"*). Suites
  **5990** + **1089**. See `docs/architecture.md` → *Pins* for the design; this entry is the
  reasoning that is not recoverable from the code.
  - **Three asks** (Henrik, one message): offer only gear wearable *at that moment*; show
    **icons**; allow **several pins on one slot** (Optical Hat on `TP_Default`, Walahra
    Turban on `Movement`), with clearing by *this pin / this slot / everything*.
  - **The engine tie-break was BORROWED, not invented.** An overlay is an equip table and a
    slot wears one thing, so a dispatch where two pinned triggers both matched must pick.
    `dispatch._pinRank` scores an entry by **the index of the last hit it names** — and
    `hits` is already sorted ascending by priority and applied last-writer-wins (ADR 0003).
    So the pin belonging to the trigger that would have won the slot anyway wins it, and
    nothing new had to be decided about precedence. `'All'` scores 0, which is what makes an
    All pin a *fallback* under its scoped siblings with no special case anywhere.
  - **A one-pin slot still serializes byte-for-byte as before.** The list shape appears only
    where a second pin exists, so the common case never touches the new path and an older
    seeded engine copy reads the file unchanged.
  - **Two outside placements for the stats panel were built and BOTH failed in the field**,
    for reasons now in the file header so nobody re-tries them: a tooltip follows the cursor
    and the cursor is on the menu; and **a plain `Begin()` window is always drawn under an
    open popup**, whatever order it is created in. Henrik's call — *"have it integrated in
    the right click window … that way it doesn't have to adapt as an outside window"* —
    dissolved the problem instead of solving it.
  - **That forced a rewrite, and it is the transferable lesson: you cannot MEASURE a card
    without drawing it.** Reserving space for the tallest piece in a pool is impossible with
    an opaque renderer, so the block builds its lines as **data first**. `renderItemTooltip`
    briefly grew a `bare` flag for the outside panel and lost it again.
  - **Four rounds of "the window still moves", each a different cause**, all worth knowing:
    a size constraint whose min ≠ max is a *permission*, not a width (popups are
    `AlwaysAutoResize`); padding with a `Dummy` adds one extra `ItemSpacing.y`, so the piece
    with **fewer** rows rendered **taller**; a pinned piece is not necessarily a candidate,
    so "all the pieces" is the pool **plus** the pins; and an estimated chrome height was two
    lines short, which is a scrollbar for one row. Every one of them was found by Henrik
    looking at it, not by a suite — see [[field-debug-artifacts-first]]'s cousin: **when the
    thing you need is already on screen, read it, do not model it.**
  - **Owed:** nothing known. The cascade's compact spelling, the scroll, the static sizing
    and the multi-pin swap in play are all confirmed.

- **2026-08-03 (`2026.08.03g` + `2026.08.03i`): THE FLOATING ICON TRAY — the Teleports button
  and the E-Box crates are ONE window (`ui/tray.lua`), stacked top to bottom. BUILT, suites
  green both interpreters (**5990** + **1048**), **NOT field-confirmed — never run in
  game.** On `dev`.
  - **The ask** (Henrik): *"Isn't it weird that we have two separate floating menus… could we
    integrate E-box restock and teleport button into the same box instead of having two
    separate?"* The 4×4 armor float stays on its own — explicitly fine as it is.
  - **It was already half-decided.** `restockui` sized its crate to 30+3 *specifically* to
    match gearui's `TPF_ICON`/`TPF_PAD`, with a comment warning the two files must change
    together "or they drift" (the 07-31 promotion above). Two windows enforcing a shared
    size by comment is exactly what merging removes — and it **closes that entry's owed
    check**: *"one look at a box with the crate and the Teleports float both on screen"* is
    now a look at one tray.
  - **The slot contract** (ADR 0017's hobby-bar move applied to the floats): a member
    exposes `trayWants(deps)` — a **cheap** gate, flags and proximity only — and
    `trayDraw(deps)`, which draws inline and never begins a window. **Every member is asked
    before anything is drawn**, because an `AlwaysAutoResize` window begun with an empty
    body is a grey box parked on the player's screen that eats clicks. Visibility is an
    **OR**: unpinning Teleports must not silently kill the restock nudge.
  - **The axis is top-to-bottom** (Henrik, same session, right after the first cut landed):
    one **column**, `Teleports / Store / green / yellow`, and nothing in the tray calls
    `SameLine` except a badge beside its own icon. `AlwaysAutoResize` pins the top-left and
    grows down and right, so a column hangs off the corner you dragged it to instead of
    creeping sideways as icons appear.
  - **Order is Henrik's ruling, not a layout detail:** constant members first, volatile
    last, because a member that comes and goes shifts everything *below* it. **Store is one
    click, no confirm, and deposits your whole Inventory**, so it moved to the FRONT of the
    crates — it used to be drawn last, so every appearance of the green crate pushed it
    down a row — and now only the two that come and go can shift each other.
  - **Position:** one tray, one spot — `ui._tpPos` (`tpx`/`tpy`), inherited from the
    Teleports float, so the button you pinned stays where you put it and the crates come to
    *it*. The old `##dlac_restock_nudge` imgui.ini entry is orphaned and harmless.
  - **Tests:** `smoke_ui` **7c2 / TR1–TR25** — nothing-wanted opens no window, two members
    draw `tp,ebox` separated by a **vertical** `Dummy` and never a `SameLine`, a **throwing
    gate does not cost the other member its window**, no window size is ever requested (the
    hobbybar collapse law), and the real `restockui.trayDraw` pushes
    `rsnudge_red,rsnudge_green,rsnudge_yellow` **in that order** — the ruling asserted where
    it actually lives. **TR21b** is the axis guard: it reads an interleaved draw log and
    fails if any icon is preceded by a `SameLine` (a badge beside its own icon is legal, an
    icon glued to the previous icon is not) — a bare `SameLine` *count* cannot tell those
    apart, and this was verified to fail when a `SameLine` was reintroduced.
  - **FIELD-CONFIRMED 2026-08-03 — 7 of 7, the round is CLOSED.** Henrik ran it in two
    sittings. Confirmed: Teleports alone draws one icon; **nothing at all on screen when
    every member is quiet** (the grey-box-that-eats-clicks case, the one that mattered);
    crates appear below Teleports near a box; Store sits above green; the crates survive
    unpinning Teleports (the OR); walking away drops the crates and leaves Teleports. The
    last one, answered separately: **drag it somewhere new, leave it ~2s, `/addon reload
    dlac` — it stays put.** So the whole position chain works end to end —
    `GetWindowPos` → `ui._tpPos` → the 1s settle → `_flagsDirty` → `saveUiFlags` →
    `tpx`/`tpy` → `loadUiFlags` → `SetNextWindowPos(..., ImGuiCond_Once)`.
  - **One narrow fragility is still there and is NOT what he hit.** The settle flush lives
    *below* `M.render`'s `if #live == 0 then return; end`, so a drag whose 1-second settle
    expires on a frame where **no member wants to draw** is never flushed — it stays pending
    until the tray shows again, and a `/addon reload` in that gap loses the position.
    Reachable only by dragging and then having Teleports unpinned *and* walking out of box
    range within the second. Not observed; the fix is to flush the pending save before the
    early return.
- **2026-08-02 (`2026.08.03a`–`2026.08.03c`): `/dl report` — THE SUPPORT RECORDER. BUILT,
  **PARTLY FIELD-CONFIRMED**, and **ON MAIN** (promoted the same session), suites green both
  interpreters (**5886** + **1003**).
  - **The ask:** *"once the user base grows, I want people to enable the debug… their whole
    dlac profile that is active + gear, sets, triggers, everything… max 5 minutes. Then he
    should be able to send those files to me so I can feed you the data."* The consumer is
    known and unusual — Henrik reads it, then feeds it to a model — and that decided the design.
  - **What it is:** `/dl report [seconds|full|stop]` (60–300s, default 300), `/dl mark <note>`
    (macro-able), and a **[Record a report]** button in the Arbiter Monitor. Writes ONE file,
    `addons\dlac\debug\dlac-report-<Char>.txt`: health + config + gear digest + timeline.
    Format pinned in [reference/report-format.md](reference/report-format.md) — **read that
    before reading a player's report**; it says what the file deliberately omits.
  - **The five design calls**, each with a field reason: **pre-roll** (dump the rings that were
    already in memory — nobody records before the bug); **stream, don't buffer** (a crash is
    exactly when the log matters); **scope for the reader** (the budget is CONTEXT — raw
    `gear.lua` is 264 KB of bag index, so gear ships as a digest); **the mark** (finding the
    moment is the expensive step); **overwrite** (support wants THE latest).
  - **FIELD-PROVEN:** the recorder, bundler, streamed log and file write. His live DRG run
    produced a clean 46 KB artifact whose **pre-roll caught a decision 26 seconds before he
    pressed record** — the design's central bet, landing on the first real run.
  - **ROUND OWED — one fresh `/dl report` on that DRG.** `03b` (one moment, one mark; the
    **Un-mark** button) and `03c` (four fixes from reading the artifact back) have **not** run
    in the field. Check: one mark where he got four; weaponskill blocks reading
    `0 placed, 7 left as worn` rather than seven contradictory `(kept)` rows; and the digest's
    **second list**. Never exercised at all: **`/dl report full`**, and the crash path (a dead
    client still leaving `dlac-capture-<Char>.log`).
  - **The finding worth carrying, and it is not about tooling.** He was **DRG26** under level
    sync and every piece in his `Ws_Default` is level 33–75, so every weaponskill silently wore
    TP gear — correct engine behaviour, and exactly what a player files as *"my WS set doesn't
    work"*. **No decision record can say so:** the level filter runs at **flatten time**, before
    any ladder exists, so there is no refusal to record and no rung to strike through. The
    digest now carries a second list off the bundled sets file flagging `ABOVE YOUR LEVEL`.
    Generalise it: **a diagnostic built from observed events cannot explain an absence of
    events — and an absence of events is what a support report is usually about.**
  - **The deeper fix is NOT built:** having the engine record *"this entry was dropped at
    flatten, and why"* would answer it at the decision instead of by inference. It touches the
    trigger floor; the digest buys most of the answer for a fraction of the risk.

- **2026-08-02 (`2026.08.02e`): THE MISSING-SET BANNER IS SHORT AND ENDS IN A BUTTON. BUILT,
  **FIELD-CONFIRMED** (Henrik, *"Field tested, works perfect"*) and **ON MAIN** (promoted the
  same session), suites green both interpreters.
  - **The ask:** *"On my Mindie DRG, I have two sets missing. Resting and Movement. The
    message is way too long and isn't word wrapped… maybe shorten it up"* — with his own mock
    ending in `-- [Create?]`, *"and it will create two empty profiles with those sets and
    commit. Easily guide the player to do the right thing."*
  - **What it says now:** `[!] 2 set(s) missing: Movement, Resting` + a **Create** button. The
    consequence ("those rules equip NOTHING") moved into the hover — the **panel-text
    standard**, applied where it is cheapest to obey: the paragraph was replaced by the action
    it described. Over six names it lists six and counts the rest; Create still takes them all.
  - **Create** writes each name as an EMPTY set through the ordinary `setmanager.commitSet`
    rails (parse-check + one backup per set), then one `/dl sets reload` — as
    `deps.createEmptySets` on the table gearui already hands triggersui. An empty set is a
    legitimate target that changes no gear, so the rule stops being a dead end today.
  - **The ruling worth keeping** (his second message): *"if we have trigger rules that match
    the base rules but point to other sets, don't tell them to create them, since there are
    obviously sets with other names doing the base thing we're after."* The banner now hides a
    missing name whose **conditions are already covered** — another rule, same handler, same
    condition signature, landing on a set that exists (or a direct `equip`). Keep
    `moving = true -> Speed` and nothing nags about `Movement`.
  - **Identity, not resemblance.** The signature is `when` + the `whenAny` legs + the `cases`
    legs, each sorted (authoring order and `pairs()` must not decide it), raw keys (a
    PRETTY_KEY label must not either). A rule with one extra condition is a different rule and
    still reports. The per-row `[missing]` marker is **not** suppressed — that is a fact about
    one rule; the banner is the "you must act" signal. A multi-set rule's own absent member
    still reports: it is not covering itself.
  - **Pinned:** `triggersui._missingSetNames` is pure (TGM0-11); the smoke half pins the seam
    BETWEEN the files — `deps.createEmptySets` named on both ends, the button id, and the
    absence of the old paragraph — because a renamed deps key is a button that does nothing,
    silently, not an error.
  - **What his pass covered:** the banner, the Create click, and the created sets landing on
    the DRG that started it. **What it could not:** the commit-failure path (`N FAILED`) —
    `setmanager.commitSet` only refuses on a torn or unwritable sets file, which cannot be
    produced in a normal session, so it stays suite-and-source only.

- **2026-08-02 (`2026.08.02b`–`2026.08.02d`): "copy to…" — ONE TRIGGER, LANDED IN THE JOB
  ENTRIES YOU TICK. BUILT, **FIELD-CONFIRMED** (Henrik, *"Tested it out"*) and **ON MAIN**
  (promoted the same session), suites green both interpreters. **What the pass could not
  cover:** the two refusal paths — a destination trigger file that does not parse, and a
  safety backup that cannot be written — are suite-only by nature; neither can be produced in
  a normal session, and both are the reason the destructive half is safe, so they are named
  here rather than counted as confirmed.
  - **Where it came from, including the correction.** Henrik asked for *"a copy to... button
    by all the trigger rules"* and named **profiles**; the profile version shipped, and he
    came straight back: *"I am in the wrong here. What did we call the job profiles again? I
    don't mean the actual character profiles, I meant the job."* The vocabulary he was
    reaching for is **Job entry** (CONTEXT.md). Worth keeping as a pattern: the ask named the
    wrong axis, and building it revealed which one he meant — the correction cost one round
    because the machinery was axis-agnostic underneath.
  - **What it is:** a `copy to...` button on every trigger row, opening a window with **two**
    tick-lists — **Jobs (this profile)** first, the ask, and **Other profiles (same job)**
    below, each with its own All, None and Copy button. A trigger file is addressed by
    (profile, job); a copy varies one coordinate, so both lists are the same question and
    share one classifier and one writer.
  - **Why it is not a Blueprint.** A Blueprint stamps onto the ONE job you are standing in.
    Reaching five jobs with it costs five job changes; here you tick them. It still travels
    **as a Blueprint entry** internally — capture, detach, identical-rule detection and the
    stamp transform are `blueprintsmodel`'s and already pinned (TGB\*) — which is what
    guarantees a copied rule is byte-identical to a stamped one, instead of a third
    hand-rolled emitter drifting from `dispatch.serializeTriggers`.
  - **Every row says what will happen before the click**, and every outcome is named after
    it: `create` (no rules for that job yet — the job worth seeding), `dup` (identical rule
    already there — warn-but-allow, gold), `add`, and a torn target file **refused, never
    overwritten**. Where the rule already lives is shown dim and untickable.
  - **All ticks only the non-duplicates** (`rulecopy.allNames`). He asked for the duplicate
    check by name, so the bulk button must not spend it: one click across 21 jobs is exactly
    where a silent double would go unnoticed. A duplicate stays reachable by hand.
  - **"Include the set if it isn't there"** (a tick in the window, default on — *"not a
    setting under the settings menu"*: it belongs to the copy you are making, not to the
    character). Any set the rule NAMES that the destination lacks is carried across by
    `setmanager.copySetText` — **verbatim** (re-rendering would round-trip every entry through
    the writer's vocabulary and quietly rewrite a shape it does not know, or a comment the
    player wrote inside the block) and **never over an existing name**. Sets follow only a rule
    that actually LANDED, and a set that could not follow is named in the receipt: a rule
    reported as copied while its set stayed behind is the exact dud this prevents.
  - **The window opens straight onto the job list.** Title, subtitle, rule text and the
    uncommitted-edits banner are gone — Henrik: *"Please remove all the text above the job
    list, it's bloating."* Only the error line can appear above the list, and it only exists
    when something is wrong; the explaining lives in hovers (the panel-text standard).
  - **The write ladder** (triggersui, not the pure core): re-read each target at write time
    (the rows are a snapshot and both Lua states plus a parallel session share the disk),
    timestamped backup into `<char>\backups\rule-copy\` — **and a backup that cannot be
    written refuses the overwrite**, the profiles-deleter house rule — then
    `lib/safewrite.replaceLua` and a read-back verify. Nothing hot-reloads because the live
    job entry is never a target; the copies are there on the next job change.
  - `gear/rulecopy.lua` (RC1–36 pure), `M.renderTrigCopyPopup` / `M._cpOpen` exposed as
    render seams so smoke_ui CP1–33 drives the whole window on both axes, including both
    failed-write paths and the pin that a refused target is left byte-identical.

- **2026-08-02 (`2026.08.02`): `/dl sends` — WHAT DLAC PUT ON THE WIRE. BUILT and **ON MAIN**
  (`28ab08d`, promoted same session), suites green both platforms, **NOT field-confirmed — a
  field round is owed** (it is a readout, so the round is one glance: `/dl sends` after an
  Incursion run).
  - **Where it came from.** Henrik, mid-Incursion, level-synced, sets only: *"Does this
    addon send or receive many packets... does it send constant packets to have things
    equipped or only once?"* The code answer is **only on a real difference** —
    `bufferFlush` bails at `plan.satisfied`, so the 0.4 s Default tick resolves a plan
    ~2.5×/s and sends **nothing** while what you want is what you wear. But a code answer
    is a claim. This makes it readable off disk, which is the whole point of the debug-file
    rule.
  - **What it is:** `feature\sendlog.lua` — total / per-packet-id / **per-cause** counters
    plus a 24-deep ring of recent sends with ages. `/dl sends` prints and writes
    `debug\dlac-sends-<Char>.txt`; `/dl sends reset` restarts the clock. Zero sends prints
    as `NOTHING sent in <dur>` **and says why that is the expected state** — the silence
    has an author.
  - **Self-check, not a probe**, so it belongs in dlac (the 07-23 ruling that put
    `/dl check` here and left forensics in dlacprobe). It never reads the wire. The
    argument that settles it: a dlacprobe `packet_out` observer sees anonymous injected
    bytes and cannot tell ours from another addon's, let alone name the dispatch point
    behind them — **only the send site knows why it sent**, and the why is the diagnosis.
    A re-dress is one burst named for its dispatch point; a **flap** is the same cause
    repeating at 0.4 s.
  - **The invariant, pinned as source (SND12):** every `AddOutgoingPacket` in the shipped
    tree sits beside a `sendlog.note()`. Five chokepoints carry all of them —
    `equipengine.injectPacket` (0x050/0x051 + the 0x01A/0x037 re-injects; cause = the
    dispatch point, stashed by `fireEvent` in `_curEvent`), `lockstyleapply.liveInject`,
    `craftwatch.requestGuildPoints`, `eboxclient.sendRaw`, `helmwatch.requestPoints`. A new
    send site without a note **fails the suite**, because an uncounted send is the one way
    this readout could lie — and it would lie in the direction that matters. A new *file*
    that sends must be added to `SEND_FILES` in the test; the test says so.
  - **The follow-up, same day (`2026.08.02a`, ON MAIN, `850e6d5`):** Henrik asked what
    `reinject (your own action, passed through)` meant, and the answer exposed a readout bug
    — a re-injected `0x01A`/`0x037` is **his** packet handed back to the wire, so billing
    dlac for it made the headline read higher than dlac's real contribution. The counter now
    splits **own** from **passed-through**, quotes the rate on dlac's own count only, marks
    the affected ids, and prints the "dlac itself sent NOTHING" verdict whenever `own == 0`
    (the shape a real casting session takes). The flag rides in the **data** (`note(id, why,
    pass)`), not in the wording of the cause. Tests SND15a–j. Side lesson worth keeping: the
    SND12 invariant pin fired on its **own documentation** — a plain `AddOutgoingPacket`
    substring matched prose about the send sites. It matches an *invocation* now
    (`AddOutgoingPacket%s*%(`), because a pin that fails on its own comments teaches people
    to weaken it.
  - **Answered along the way** (worth not re-deriving): under level sync there is no
    strip/re-equip loop, because both sides use the **real** job level —
    `AllowSyncEquip = true` reads `GetJobLevel(mainJob)`, and CatsEyeXI's equip check is
    `getReqLvl() > (DISABLE_GEAR_SCALING ? GetMLevel() : jobs.job[MJob])` with
    `DISABLE_GEAR_SCALING = false` (`charutils.cpp:2306`, `settings/default/map.lua:100`).
    Client and server agree, so no equip is refused and nothing retries. The sync landing
    itself arms the 1 s settle hold (`M.SYNC_SETTLE_S`) and then one re-dress.

- **2026-08-01 (`2026.08.01k`, engine v162): OTHER ADDONS CAN CLAIM GEAR — BUILT and
  **FIELD-CONFIRMED — all four checks, plus the re-check on the last fix** (Henrik: *"This
  works, real nice ... Says verdict lost, that MaxMP won it"*; *"The lease works"*; *"I have
  dragged it around, moved it over MaxMP when it was winning and then it won"*; *"B gets the
  verdict line now, works"*). **UNCOMMITTED** — see the working-tree note at the end of this
  entry before staging anything.** The write half of the
  Integration surface. A separate addon — its own Lua state, its own folder, **not** a dlac
  module — files a Claim over `plugin_event` and the Arbiter settles it like any other
  claimant. Henrik asked whether it was possible without a module; the answer turned out to
  be small, because a Claim is already just `{ [SlotKey] = itemName }`.
  - **What was built:** `feature\extclaim.lua` (the mailbox + the protocol, pure core),
    one rank row **`External`** shipped directly above the Triggers floor (the rank the
    plugin design already ruled for a third party — `integration-surface.md` §10), one
    `CLAIMANTS` row in `dispatch.lua`, one signature leg, the `/dl claims on|off|list`
    switch + a Menu > Settings row, a Claim Priority row that **names the addons holding
    slots**, and `lib\dlacclaim.lua` — the published client shim third parties load so
    nobody hand-rolls the wire format. Consumer spec: **integration-guide §7**.
  - **The three laws that are new** (everything else is inherited from ADR 0012/0027):
    **push, never pull** — dlac asks nobody anything mid-decision, so no third-party Lua is
    ever on the equip path (cost, stated: a *reactive* external claim is one action late);
    **every claim is a lease** — TTL 10s default / 300 max, renewed by heartbeat, because a
    foreign holder can *vanish* and gear stuck with nobody to blame is the worst outcome;
    **claim, never commit** — session-only, no writer for sets/triggers/modes/lockstyle.
  - **The switch is deliberately NOT `/dl stream`.** Reading your gear and dressing you are
    different consents, and a misbehaving claimant has to be killable without also killing
    a parser's feed. `hello` is answered even while claims are off, so a consumer can tell
    "dlac is not installed" from "the player has not turned this on".
  - **IT IS PERSISTED** (Henrik's call after the perf answer below), and the SPLIT is the
    whole design: the **permission** is a saved preference (`syncflags.flags.extclaim`, the
    uiflags store every other Setting rides, absent = off so no install changes behavior),
    while the **claims** stay session state and die with the world exactly as before.
    Nothing an addon holds crosses a logout; only your answer to the question does. Read
    ONCE per session, on the frame beat, and written on every `setOn` — read-once is
    load-bearing: a re-read each frame would undo `/dl claims off` the moment it was typed
    (EX26*). And because a logout now clears claims WITHOUT revoking permission, every
    `expired` push carries **`data.on`** — the switch state, explicit, so a consumer never
    infers permission from a reason string (the shim reads that field; it used to sniff the
    reason, which would have read a logout as a revocation).
  - **The trap for whoever adds the next claimant of any kind:** the `CLAIMANT_SIG_ORDER`
    leg. A claim that changes without moving the retrace signature never re-dispatches — it
    sits in the mailbox looking accepted, reaches no slot, and the failure is invisible from
    both sides of the wire. `EX16f` exists to fail loudly instead.
  - **Evidence so far:** suites **5616 + 944**, Windows and WSL lua5.4. `EX1–EX16` pin the
    receiver (validator refusals, deterministic merge, lease, gated-but-never-silent door,
    the wire format, the registry wiring); **`EX17–EX23` wire the SHIPPED SHIM to the real
    receiver and run the whole conversation** — hello, refusal-while-off, claim,
    canonicalisation, verdict, heartbeat, lease lapse, kill switch, logout. The shim's
    serializer is a second implementation by necessity (it runs where dlac's own is
    unreachable), so it is tested against the first rather than trusted. That proves the two
    halves agree; it proves **nothing** about Ashita's real broadcast or about gear moving.
  - **FIELD ROUND 1 — ALL FOUR CHECKS PASSED.** (1) a claim lands; (2) it LOSES to a senior
    claimant and the verdict names who won — *and* wins after the row is dragged above the
    winner (Henrik moved it over MaxMP); (3) the lease works; (4) two identities contend.
  - **THE RIG BECAME A SHIPPED EXAMPLE** (Henrik, same day: *"I also want you to have the
    claimtest addon (rename it claim-example) in DLAC as an example how to integrate with
    DLAC over this, as well as properly document it so humans and claude / AI can understand
    how it works properly"*). It now lives at **`examples\claim-example\`** — the addon plus
    a README written for whoever does the integration, human or AI, holding the model, the
    five things that bite, and a table of what each command proves. Copy the folder to
    `<Ashita>\addons\` to run it; Ashita only loads addons from its own directory, so the
    repo copy is canonical and the deployed one is a copy (the README says so, because that
    is exactly the pair that drifts). `addons\claimtest\` is deleted — one example, not two.
  - **Three bugs the field round produced, all fixed:**
    - **The module installed a `d3d_present` handler from inside one.** The engine requires
      it lazily, on the first dispatch, which itself runs in a frame callback. Now pumped
      from `dlac.lua`'s beat like actionseq/engagewatch. It also fixed a bug nobody had hit
      yet: the inbound listener did not exist until dlac's first gear decision, so an addon
      that claimed before that was answered **by nobody**.
    - **The verdict join was CASE-SENSITIVE** (`M.externalLost`, now a pure exported seam
      with tests EX24*). `arbExplain` says it outright and this is the same join: the
      producers disagree on case — overlay tables are proper-case, the Locks veto rides
      lowercased `M.locks`, a pin table or locked set carries whatever its source wrote. A
      case-sensitive compare does not name the *wrong* winner, it names **no** winner — so
      the addon is told it still holds a slot something else took, silently, and only for
      the claimants that spell slots the other way. The report also moved to BEFORE the
      equip: downstream of `equipResolved`, a bad frame would have cost the explanation as
      well as the gear.
    - **A claim shadowed by ANOTHER EXTERNAL ADDON was never reported** (`merge` now returns
      `shadow`, tests EX4d–g / EX13d–e). Henrik's check 4: B claimed A's slot, got `ok`,
      and heard nothing more. The *outcome* was right — a shadowed claim is accepted on
      purpose, so it takes the slot the instant the winner releases or lapses, with no
      round trip — but the reporting was the same silence the verdict push exists to end,
      arriving from the one direction the ARBITER CANNOT SEE: this contest is settled in
      the merge, before the Arbiter is handed anything. Now it rides the same `verdict`
      notice, so the addon learns "something else has that slot" ONE way rather than two.
      Note for the next reader: the two losses want **opposite** advice — a dlac claimant
      is the player's Claim Priority drag, a peer addon is `prio` and never appears in that
      list at all. `claim-example` prints the right one for each.
  - **Not built, on purpose:** a synchronous pull (dlac asking claimants mid-dispatch), a
    per-addon rank row (they share the one `External` row; between themselves `prio` then id
    ascending decides), and any writer at all. The parked plugin-folder design
    (`integration-surface.md` §10) stays parked — this needed none of it.
  - **COST OF LEAVING IT ON (measured 2026-08-01, 200k iterations, whole per-frame path =
    dlac.lua's pump + the registry's `active` + `claim`):** switch **off 0.41 µs/frame**;
    **on with nobody claiming 0.44 µs** (0.0026% of a 60 fps frame); on with one addon
    holding two slots **2.1 µs**; two addons contending **3.6 µs** (0.02%). So leaving it
    on permanently is free in any sense a player could perceive — the answer to *"can I
    just leave it on"* is yes, and the number is written down so nobody has to re-derive
    it. (Those two idle figures are conservative: the harness has no `syncflags`, so the
    once-per-second flag restore never settles and keeps retrying a failing `require`. In
    the addon it succeeds once and stops.) Three cheap changes got the idle path there and
    are worth keeping: `merge` and
    `claim` early-out on an empty store and hand back a **shared** `EMPTY` map instead of a
    fresh `{}` per dispatch (`EX25*` pins that by identity); `active()` no longer merges at
    all, it answers the question it was asked; the pump's world check is throttled to 1/sec
    (`M.WORLD_S`) because "did you log out" is not a per-frame question; and
    `extclaimMod()` uses `pcall(require, …)` rather than `pcall(function() … end)`, which
    was allocating a closure twice per dispatch for nothing.
  - **THE ONE PATTERN TO CARRY FORWARD.** All three bugs were the same failure wearing
    different clothes: **the addon is told it holds a slot it does not.** No frame handler
    yet / no winner named / a whole category of loss invisible. None of them is findable by
    asking "is the gear right" — the gear was right every time. They are findable only by
    asking, at every point where something takes a slot, **"how would the losing addon find
    out?"** Ask that of any new claimant, any new refusal reason, any new verdict channel.
  - **COMMITTED OUT OF A SHARED TREE (2026-08-01).** A parallel session's in-flight food
    work was live in the same checkout, so this commit was staged **hunk by hunk**, not
    with `git add`: `feature/foodwatch.lua` was left entirely alone, and the four files
    carrying both sets of changes (`ui/menuui.lua`, `tests/run_tests.lua`,
    `tests/smoke_ui.lua`, this file) had the other session's hunks filtered out of the
    index — `git apply --cached`, which never touches the working tree, so their copy
    survived intact. Anyone continuing from here: that work is still uncommitted on disk
    and is **not** in this commit or on `main`. See [[shared-checkout-contamination]].

- **2026-08-01 (`2026.08.01h`): Auto-build can be told to stay in the field, and
  Auto-Build All asks first — FIELD-CONFIRMED and ON MAIN (`36da078`).** Two small
  Sets-tab requests from Henrik, both about giving the player leeway. Confirmed in game
  the same day — *"Works in field, thank you, both settings and the auto build"* — and
  promoted in the same breath.
  - **New Setting "Auto-build with gear in storage"** (Menu > Settings) / `/dl buildstored
    [on|off]`, persisted in `uiflags.lua`, **default on** — absent key reads as on, so no
    install changes behavior. On, Auto-build picks from everything you own wherever it sits
    (a set is a plan, ADR 0006, and a stored piece can be retrieved). Off, its candidate
    pools narrow to the **Available** half — Inventory + the 8 Mog Wardrobes (CONTEXT.md
    "Owned vs Available") — so a build made in the field is wearable on the spot.
  - Three scope lines that are easy to get wrong later. It narrows **pools only**: sets
    already built are never rewritten, slots outside the build mask keep what they have,
    and the `+ Add` picker still offers everything you own (the Sub HARD RULE is untouched
    — the filter sits in `autoBuild`, not in the shared `candidatesForSlot`). It reads
    `ownedcache.isStored`, the same fact that paints those names red, so colour and pool
    can never disagree. And it is the one place set *building* consults a live bag fact —
    hard rule 6 still holds by default; this is opt-in and asked for. `UIF22/22a/22b` pin
    all three at the source.
  - **Auto-Build All now takes two clicks.** Henrik: *"it can be highly impacting
    accidentally pressing it, so let's give some leeway just in case."* The first click
    arms (the button turns red and reads **"Sure?"**), the second re-solves and commits
    every weighted set of the job; the arm expires by itself after ~5s so a stray click
    leaves nothing live under the cursor. Not a popup — there is nothing to name in a
    dialog for a whole-job action. `UIF23/23a` pin that only an armed click builds.
  - Suites **5480 + 925**, Windows and WSL lua5.4. Nothing here touches the engine, so
    the reload was `/addon reload dlac` alone.

- **2026-08-01 (`2026.08.01b`, engine v158): gear availability is an ARBITER refusal —
  FIELD-CONFIRMED and ON MAIN (`4810f94`).**
  Henrik's report: at Lv75 all is well; park a Minstrel's Coat in the Mog Safe, lower your
  level until the Coat is the set's best-by-level Body, and dlac picks it — a piece it
  cannot equip. Diagnosis: the whole selection chain asks **level** and never asks the
  **bag** (`utils.slotLadder`, `resolveVirtual`'s chain walks, `mpRungs`), and availability
  is only discovered at the very end in `equipcore.planSet`, whose locate pass first-fits
  over the equip-eligible bags only. A stored piece simply is not there, so nothing is sent,
  the slot keeps what was worn, and **the rung below it is never asked** — by then the
  ladder is gone.
  - **The ruling (Henrik, and he had to state it twice):** the check goes in the **arbiter,
    centrally**, and nowhere else. *"It is FINE if claimants file ladders where some of the
    pieces are ineligible… which also saves us the trouble of adding yet another field they
    need to populate."* Do **not** put availability in the ladder builders, and do **not**
    generalise this into an eligibility framework — *"everything is working fine as it is,
    we just want to give it more intelligence… let's add arbiter's intelligence as we go and
    need."*
  - `gear/arbiter.availVerdict(floor, have)` is a **second refusal reason** riding the fall
    loop the v135 dominance verdict already rides: refuse a rung → ask `ladderOf` for the
    next → re-judge → fixed point. No claimant changed. Every row with an `rladder`
    (Craft/HELM/Fishing/Chocobo) and the floor's `candidatesFor` inherit it.
  - Three laws worth not re-deriving: an unavailable piece is **hidden from the dominance
    view** (it is not on your body, so it neither defends its slot nor reserves another);
    `have` is **three-valued** and an unreadable **or empty** bag map answers `nil`, because
    a two-valued read would say "you own nothing" at char select / mid-zone / mid-load and
    strip all sixteen slots; and a slot whose whole ladder is refused is **not killed** —
    `planSet` cannot locate those names either, so it keeps what is worn.
  - **The receipt:** `vLadderOf` is the one door every ladder passes through, so it now
    notes each one down and `recordDecision` keeps *that* instead of rebuilding the rung
    list afterwards from `contest.src` (floor-only, and re-asked later so it could answer
    differently than the list that decided). The Monitor hover shows the **whole ladder with
    each refused rung struck through and its reason**, marks the cell without a hover (`*` =
    wearing its second choice, `!` = whole ladder refused), and `/dl why <slot>` prints the
    same lines off the same record.
  - Suites **5395 + 913**, both interpreters (`UA1–UA8`, `DR9–DR12`). **Field round run and
    passed the same day** (Henrik: *"Works, thanks"*) — **ON MAIN** (`4810f94`), promoted
    2026-08-01 with the panel half below.
  - **Follow-up the same day (`2026.08.01c`): the Sets tab was still lying about it.** The
    engine fell correctly, but the panel highlighted the parked Coat as the chosen piece
    while wearing the Royal Cloak below it. The preview now previews the WORN pick — see the
    promotion record at the top of this file for the shape and for the one behavioural
    consequence (Set totals move as you shuffle bags). Henrik's scope line for it, worth
    keeping: the GUI answers availability only; rank, claims and reservations stay the
    Monitor's to explain. Suites **5410 + 925**; **ON MAIN** (`4810f94`), and the panel half
    has NOT had its own in-game look yet — the engine half is what he confirmed.

- **2026-08-01 (`2026.08.01`): the storage warning speaks once per main job, and it is a
  Setting.** Field report from Henrik: *"only inform me once, and only once, until I change
  main job."* The **"…please retrieve if needed"** line (`gear/gearcheck.lua`) rides
  `automationsui.rescanAutogear`, which fires on job change **and ~5s after every inventory
  settle** — and the signature dedup it relied on could not hold that back, because moving a
  piece moves the availability counts the signature is built from. So the same advice came
  back all session, which is the fastest way to teach someone to read past a warning.
  - **The gate is the main job id, and only that.** A sub job change is deliberately *not* a
    re-arm: the audit walks the main job's triggers and sets, so `/NIN` under a new sub is
    the same audit with the same answer. `/dl gearcheck` (force) always answers, and stamps
    the job as told so a manual check is not echoed by the next auto-sync a few seconds
    later.
  - **The one law worth keeping.** `M.audit()` now returns `(warnings, ran)`, because
    "nothing to warn about" and "no trigger model / no bags yet" both came back as an empty
    list — and login hands you the second one. A gate spent on that empty answer would
    silence the real one for the whole job (hard rule 11's shape, on a new surface), so an
    audit that could not RUN says nothing and arms nothing.
  - **The Setting** is `gearwarn` in `gear/syncflags.lua` — Menu > Settings > **"Warn about
    gear in storage"**, or `/dl gearwarn [on|off]`, defaulting ON with the usual absent-key
    rule (every `uiflags.lua` written before today lacks it and keeps the behavior it has).
    Off silences the automatic report only: the Triggers tab's **Gear warnings** section and
    `/dl gearcheck` still answer whenever asked. Turning it back on calls `gearcheck.rearm()`
    so the answer lands on the job you are standing on, not the next one.
  - Suites **5360 + 913**, both interpreters (new `GCJ1–GCJ7b`, plus the uiflags round-trip
    pins). **ON MAIN** (`4810f94`) — promoted 2026-08-01 riding the arbiter train, and it
    went into the queue ahead of the round the queue normally requires, so it reached main
    **NOT field-confirmed**. Its round is still owed and is one line long: change to a job whose triggers name something parked in the
    Mog Safe, read the warning once, move some gear around, and confirm it stays quiet until
    the next main job change.
- **2026-08-01 (`2026.08.01l` — written as `j`, relabelled on the way out: the external-claims
  train reached the version line first and took `k`, so this landed after it):
  the clock stops when you log out — the meal's length is
  MEASURED, never looked up.** Henrik, after field-testing the row above: *"Is it possible to
  stop the clock when you log out? ... the food duration doesn't go down when you're logged
  out."* Correct, and the wall-clock "eaten X ago" was overstating by the length of every
  logout. His suggested fix was an accumulator ticking every 5s; **it was not built, because
  the client already knows.** **NOT field-confirmed** — suites only.
  - **The status timer decodes.** A raw `GetStatusTimers()` value is the expiry in
    **sixtieths of a second since the Vana'diel epoch** (`0x3C307D70`), in a uint32 that wraps
    ~every 2.3 years — hence the re-add loop, undoing ~10 wraps in 2026. Ported by hand from
    the two sibling addons that already carry it (`timers\helpers.lua`,
    `statustimers\party.lua`, which agree line for line — [[sibling-addons-signature-authority]]
    again). Those read the **client's** UTC stamp behind a signature scan; dlac uses
    `os.time()` instead, so there is no sig to break on a client patch. It was checked against
    Henrik's own recorded meals and lands within the poll interval — **`FW32` is that golden**,
    built from real `foodhistory.lua` values rather than a hand-made fixture.
  - **Why an accumulator would have been worse.** The server sends the true remaining time at
    login — that is why the buff addons are right after a relog. Counting seconds ourselves
    would re-derive, with drift, a number the game hands over for free, and would be wrong
    after any crash, `/addon reload`, or missed tick. Reading it needs no bookkeeping, no
    periodic disk write, and nothing to resync.
  - **The duration is MEASURED at the moment the meal lands, not read from `fooddb`.** This is
    the load-bearing part: `xi.mod.FOOD_DURATION` grants **+100%** from `sanction.lua` and
    `sigil.lua`, so the same Pork Cutlet runs 3 hours or 6 depending on what you were under
    when you ate it. That is not theory — Henrik's recorded Pork Cutlet decoded to **exactly
    2.00×** its 10800s script duration, which is how the mod was found. What is left the
    instant the effect lands IS the meal's real length, so it is stored (`dur` in
    `foodhistory.lua`) and `used = dur - left` is read live thereafter. **This also fixes a
    bug shipped in `i`**: the tooltip's duration line was reading `fooddb`'s book value and
    said "3 hr food." for a six-hour meal.
  - Rows written before this carry no `dur`; those fall back to wall-clock until re-eaten, and
    an out-of-band decode is dropped rather than stored — a missing number beats a wrong one.
  - **The countdown is ON after all** — Henrik reversed the earlier "timers are fine not
    including" once the number existed: *"if we have the number, just let it show an estimated
    countdown."* It rides the tooltip line that names the meal's length
    (`6 hr food -- ~4 hr 51 min left.`) rather than the row label, because showing *a* timer is
    the buff bar's job and the only thing dlac adds is **whose** timer it is. `/dl food` says
    it too. The `~` is honest, not decoration: the decode leans on `os.time()` against the
    client's own clock and the poll runs at 250ms. `_fmtLeft` is deliberately not `_fmtDur` —
    a length may round to the nearest minute, a countdown may not round 20 seconds up to
    "1 min" and must say *expiring now* rather than going blank at zero.
  - **`left` never depended on the measurement**, so a row recorded before this still counts
    down; it just cannot report how much is spent (`FW39`, `MN18q4`).
  - **Bonus, from the same dig:** "you can never eat over food" is now confirmed in the server
    source, not just the field — `xi.itemUtils.foodOnItemCheck` returns `xi.msg.basic.IS_FULL`
    when `hasStatusEffect(xi.effect.FOOD)`.
  - Suites **5527 + 944**, both interpreters. Tests FW32–FW39, MN18o2–MN18q6.
- **2026-08-01 (`2026.08.01i`): the Active food row — dlac now answers a question FFXI
  refuses to.** Henrik's framing, and it is the whole rationale: *"The problem with FFXI is
  that the status icon does NOT show what food you ate. So if you eat a food, then log out,
  forget, log in, you have no idea what food effect is active."* The icon is generic. dlac
  already knew which food it was (the history names it — field-confirmed the same day); it
  just had no way to say what that food *does*. **NOT field-confirmed** — suites only.
  - **`data\fooddb.lua`, generated by `tools\gen_fooddb.py`** from the server clone's own
    `scripts\items\*.lua` (branch `stable`). **783 foods**, 95 KB, keyed by item id: duration
    plus the effect lines. Same distribution model as the catalog — generator in gitignored
    `tools/`, output ships, only Henrik regenerates; the file is stamped with the server
    commit it came from so a stale one is visible rather than silent.
  - **The text is the server script's own English header, not a translation of its `addMod`
    calls.** Mapping 86 `xi.mod` names to English is 86 chances to mislabel a stat in a way
    the player cannot check, against a cosmetic cost: phrasing is inconsistent between foods
    ("Attack +20%" in one, "Defense % 12" in another) because different contributors wrote
    those comments. The header is also the *only* source that survives the awkward foods —
    the curries build their mods from a party-size `dataTable` and expose no literal `addMod`
    line at all. **11 foods branch** on race or party size; their header documents every
    branch *with labels* ("Galka" / "Other", "IF ELVAAN ONLY"), so the whole block is shown
    and dlac does not try to pick the branch that applies — the text already says which is
    which, and a wrong guess would be invisible. **16 have no header**: those fall back to the
    client's own item `Description`, so a gap is a weaker tooltip, never an empty one.
  - **DISPLAY ONLY, and the split is load-bearing.** `fooddb` must never be asked whether an
    item IS food. That answer stays learned from the FOOD effect moving, so a food the server
    adds tomorrow is still remembered and still eatable — it just has no stats to hover. Wire
    the table into detection and the "dlac ships no food list" guarantee is gone and a shipped
    copy that goes stale starts deciding what counts as food. **FW31 is the regression guard**:
    a food the table has never heard of is still learned, still eatable, and simply shows
    nothing. If that test ever fails, someone has crossed the line.
  - **The row.** `Active food` above `Recently eaten` in `ui\menuui.renderFoodSection` — so it
    is in the Menu popup **and** the Teleports float from one definition, as before. Drawn
    **independently** of the eat rows, because their empty cases are opposite: the moment you
    most need to be told what you are under is after a relog with nothing left to eat. It is
    **not clickable** — CatsEyeXI refuses an item use while FOOD is up, so a re-eat from there
    could only fail; the Selectable is there for the hit area. Hover gives the duration and
    the effect lines. **No time remaining** — Henrik: *"Timers are fine not including, we
    usually see those just fine"*; how long is left stays the buff-timer addons' question.
  - **Those lines are full of literal `%`** ("Attack +20% (cap 120)"), which is the panelkit
    law's first real ammunition rather than a hypothetical: unescaped, imgui's printf prints
    a heap address. `MN18q` asserts the escaping.
  - **The eat list went from two rows to three** in the same pass, on Henrik's call after
    seeing it (`M.MENU_N`). `FW14a`–`FW14d` pin the constant and the `CAP > MENU_N` gap that
    gives the walk-past somewhere to walk to — `_pick` defaults to it, so nothing else would
    have noticed it quietly going back to two.
  - Suites **5505 + 936**, both interpreters. Tests FW14a–FW14d, FW26–FW31, MN18k–MN18u.
  - **FIELD ROUND OWED — and it is short.** On `main` (`c405a59`) on Henrik's go, suites only.
    This is the *same shape* as the round directly below, which sat unconfirmed for days
    because nothing pointed at it; the whole round is three checks: **(1)** under food, the
    `Active food` row names it and hovers with sane effects — in the Menu popup **and** the
    Teleports float; **(2)** a food with a race branch (Galkan Sausage, Royal Omelette) reads
    understandably with both blocks shown; **(3)** the eat list now offers **three** rows;
    **(4)** *(added by `l`)* eat something, note the "eaten X ago", **log out for a good
    while**, log back in — the elapsed must be roughly where you left it, not the wall-clock
    gap, and the duration line must match what the meal really ran (double under Sigil or
    Sanction). Delete this line when it is done.
- **2026-08-01: foodwatch is FIELD-CONFIRMED — the owed round ran and found no fault.**
  `feature/foodwatch.lua` (`121af5b`, `2026.07.30g`) had been **on `main` since `605045f`**
  and had never once run in game: it rode the Ashitacast promotion because `dev` promotes
  whole-or-not, so the queue's field-confirmed bar was *overridden* rather than met. It is
  met now. The seven-check card that stood here is deleted; this is the result in its place.
  Evidence, artifacts-first: `foodhistory.lua` in the live char dir (`storagefile.charDir()`
  — the **native** home, which moves with the active Profile as well as the character)
  carried two learned rows, `Pork Cutlet` and `Hobgoblin Pie`, correct names, most recent
  first, real expiries.
  - **The detection spine works**, end to end and unaided: OUT `0x037` → pending id → the
    FOOD effect moving → `nameOf` → `_remember` → disk. dlac ships no food list, so every row
    in that file is one it *learned* — the rows existing at all is the proof.
  - **The one structural finding, and it outranks the round: you can never eat over live food
    on CatsEyeXI.** Henrik, in the field: *"You can never eat over something in this game,
    server prevents you to."* The server refuses an item use while the FOOD effect is up. The
    expiry-inequality read was built for exactly that case, which means **the case the module
    was designed around does not exist on this server** and the absent → present edge is the
    only path that fires. Do not re-derive this; do not re-queue a re-eat check. The branch in
    `_step` **stays and needs no change** — it is now insurance for the one narrow reachable
    case, a food wearing off and being re-eaten inside the same 250ms poll gap where the
    absent state is never sampled. One comparison, cannot fire wrongly.
  - **Passed in the field:** rows draw with the right name and icon; `/dl food N` (and the
    row click) queues the right `/item` string and the client accepts it; **a login while
    still under food NAMES the food and its age** — Henrik's 2026-07-30 ruling working, not a
    bare "food active"; a food you have run out of **drops off the list**. That last one also
    settles the walk-past: `_pick` has no early break, so continuing past a zero-count row is
    the same line that hides it — hiding one while another still shows *is* the walk.
  - **Left open, and it is a product call, not a fault:** `/dl food N` while you are already
    under food says *"eating X."* and queues a command the server is now known to refuse
    **every time**. That is a no-op the player has to diagnose from game chat. It could
    instead say which food is blocking it and not send. Not built — Henrik's call.
- **2026-07-31 (`2026.07.31f`): the E-Box nudge and the Teleports float are now the same
  36x36 button** (`ui\restockui.lua`). Henrik's second tester finally noticed the crate — and
  was annoyed by it, which is the feature working — but the two floats sit on the same screen
  at different sizes. The nudge asked for 40px of art and passed **no frame padding**, so
  ImageButton fell back to the style's `FramePadding` (4,3) and drew **48 wide by 46 tall** —
  bigger than the Teleports float *and* not square. It now passes the long form
  (`uv0`/`uv1`/padding/bg/tint) with `NUDGE_SZ = 30` + `NUDGE_PAD = 3`, matching gearui's
  `TPF_ICON`/`TPF_PAD` exactly; the bg stays transparent so the themed button colour still
  shows through and only the size changed. The text fallback (PNG failed to load) is the same
  36 tall and takes its width from the label per the themed-font law, so a missing asset can
  no longer resize the stack or clip `At home`. **The two constants are duplicated across two
  files — change them together or they drift.** Suites **5343 + 913**. **ON MAIN**
  (`bc581d1`) — promoted on Henrik's explicit call while **NOT field-confirmed**, and unlike
  the two promotions before it there is no headless substitute here: it is a pixel size, and
  eyes on a screen are the only test. **One look at a box is still owed.**
- **2026-07-31 (`2026.07.31d`): "Copy from" learns the OTHER legacy engine —
  Ashitacast XML (`gear/acimport.lua`).** Suites **5320 + 908**, both interpreters.
  **ON MAIN** (`605045f`) — promoted on Henrik's explicit call while still **NOT
  field-confirmed**: three field rounds shaped it and it is verified against his real XML +
  `gear.lua`, but nothing here has had an in-game look. **An in-game pass is still owed**;
  if it turns up a fault, the fix goes to `dev` like anything else.
  - **What it is.** *Ashitacast* is the legacy XML gear-swap format — LuAshitacast's
    ancestor. On Ashita v4 it is served by the **LegacyAC plugin**, which is already
    installed here (`plugins\LegacyAC.dll`) and keeps one swap file per character AND job
    at `<install>\config\legacyac\<Char>_<JOB>.xml`. **The schema authority was already on
    disk** — `Ashita\docs\LegacyAC\XML Structure.xml` + `readme.txt` + `Variables.txt`.
    Read those before touching the parser; nothing in this was guessed.
  - **Almost nothing downstream changed, and that was the point.** `importStaticSet` already
    eats a plain `label → value` table, and `resolveSetItem`'s string path already resolves a
    bare item NAME against owned gear case-insensitively — which is exactly what the format
    stores and exactly what it needs (set and equipment names are explicitly *not* case
    sensitive there, and real files write `hlr. cap +1`). So the new code is a parser, a slot
    map, and `baseset` resolution. One candidate per slot means the ADR 0008 best-first
    warning cannot apply — there is no order to diverge from.
  - **Apostrophes: checked, and NOT a problem — but know which index is which.** `catalog.lua`
    drops apostrophes ("Bunzis Hat"); a scanned `gear.lua` keeps them ("Genbu's Shield",
    because `gearimport` takes `res.Name` from the resource manager). Measured on the real WHM
    file: 18 of its 63 distinct names miss the catalog on punctuation alone, **0** miss for
    that reason against owned gear. The string path never consults the catalog, so the import
    is unaffected. Do not "fix" this by normalising the catalog — you would be fixing the
    wrong index.
  - **The rules that bit, each one a real-file fact** (tests AC0–AC57): both slot dialects
    ship in one file (`ear1`/`ear2` in `<sets>`, `lring`/`rring` in `<idlegear>`); `none` is a
    KEYWORD that empties a slot, tracked as an explicit CLEAR because with a `baseset`
    "not mentioned" inherits and "explicitly empty" must not; `baseset` needs a SECOND pass
    (a base is declared later in the file, chains are legal, `baseset="idle"` finds `Idle`,
    `baseset = "X"` with spaces is legal); comments must be stripped FIRST because they
    contain whole commented-out `<set>` blocks; `<setvar>` is one character from matching a
    plain find for `'<set'` and lives in the same files.
  - **Mis-nesting is tolerated ON PURPOSE.** The spec sample **shipped with the plugin**
    contains `<statusupdate>true</statuspdate>` and `</petsspell>`. A strict parser would
    reject files LegacyAC itself loads happily, so slot content reads "up to the next `<`"
    and never checks that the close tag matches.
  - **Two things cannot come across, and the copy says so** (hard rule 12): `augment="S…"` is
    LegacyAC's own fingerprint from `/la print augs` — opaque, not decodable against dlac's
    augment table, so the BASE item is imported; and `lock=` has no meaning in a dlac set (a
    lock is an Arbiter claim). `acimport.dropNote` turns the counts into the chat sentence.
    Without it the WHM file's `39q04` and `4950` — sets that exist ONLY to pin an augment —
    arrive looking like pointless one-piece sets.
  - **Ashitacast names get their OWN name space in the picker.** The existing lac/static
    dedupe exists because those two sources are the SAME file; this is a different engine's
    file, so a shared "Idle" is a different set and hiding one behind the other would lose it.
  - **FIELD ROUND 1 (`2026.07.31b`) — the home is a SEARCH, and it must name what it read.**
    Henrik dropped the file in and the column stayed empty. Nothing was wrong with the file
    (it parses to 23 sets, zero notes): he put it in **`config\addons\legacyac\`** and dlac
    looked only in `config\legacyac\`. His guess was the reasonable one — `luashitacast\` and
    `dlac\` both live under `config\addons\`, and this install *also* shows the third
    convention in use for another plugin (`config\plugins\FindAll\`). Fixed by looking in all
    three (`profiles.legacyacRoots` / `legacyacPaths`, first file that reads wins, readme home
    first on a tie) **and** by printing `Read from: <path>` under the column
    (`profilesets.acSource`) — the silence was the actual defect, not the folder.
  - Verified end to end against the real install afterwards: found at candidate 2, **23 sets,
    zero notes**, `baseset` chains resolving (DT←Idle 15 slots,
    MidcastBarspell←MidcastEnhancing 13, MidcastCursna←MidcastHeal 15), `TP`/`MidcastRaise`
    correctly empty, drop notes firing on `MidcastDivine` (2 augments), `39q04` and `4950`.
  - **FIELD ROUND 2 (`2026.07.31c`) — a marked set gathered as nothing.** The column listed
    the sets, but marking one and pressing Create answered *"Mark at least one set on the left
    first"* over a set visibly ticked. Cause: **the popup walks the legacy kinds TWICE** —
    once to draw the rows, once to gather what was marked — and those were **two separate
    literals**. `'ac'` went into the render list only, so the mark was stored under a kind the
    gather never asked about. Nothing was wrong with the parse, the file, or the resolver.
  - **The lesson is the shape, not the typo.** A kind present in one loop and absent from the
    other is invisible to review and to every headless test — the UI looks right and the
    button lies. Fixed by hoisting **`LEGACY_GROUPS`** (module-level, next to `KIND_WORD`) as
    the ONE list both loops read. Pinned by construction in smoke (LSP13a–e): the kinds are
    parsed OUT of that table, the gather is required to iterate it, a second hardcoded kind
    list is required NOT to exist, and every kind on it must be resolvable by
    `workingForSource` AND nameable via `KIND_WORD` — so the next kind added cannot repeat
    this. The guard was verified by reintroducing the bug and watching LSP13d fail.
  - **FIELD ROUND 3 (`2026.07.31d`) — missing gear is never a refusal, on ANY import.**
    Henrik's call, and it applies to all four source kinds, not just Ashitacast:
    *"if the gear wasn't found, just ignore it, inform (temporarily) and move on instead of
    not importing it at all."* Skipping an unresolvable candidate was already the
    per-candidate behaviour — but **silent**, and a set where *nothing* resolved was refused
    outright (`doCopyFrom` left the target "unchanged"; `copyAsNewSets` skipped the set).
    Migrating someone else's job file therefore reported *"Created 0 new sets"* and read as
    a broken importer, when the honest answer was "you don't own this gear yet".
  - **Measured on the real pair** (Mindie's `gear.lua` × the WHM XML) — worth knowing the
    old behaviour was not as broken as it looked, and exactly how it looked wrong:
    **19 of 23 sets already imported** (partially filled, no word about what was missing);
    4 were silently skipped. Now: **23 created, 4 as empty placeholders, 37 distinct pieces
    named**. That is the whole difference — nothing about the parse or the resolver changed.
  - **Where the accounting lives.** `importStaticSet` returns `missing` (distinct names,
    first-seen order) + `missingCount` (every drop, including candidates too broken to
    name — a MISSING sentinel answers every key with itself, so `elem.Name` is a *table*;
    `elemName` reads TYPED for that reason). An EMPTY slot list is "no candidates", not a
    failed one, or it would inflate the count with a piece nobody named.
  - **Reporting shape differs by path ON PURPOSE.** A single copy names what *that* set
    lost (per set). The migrate-many pools the batch into ONE deduped line — 23 sets would
    otherwise print 23 lines of chat. The status line (which auto-expires after 5s) carries
    the counts; chat carries the names.
  - **All four kinds now run ONE walk** (`importVia` → `setimport`). The dynamic path
    hand-rolled its own copy of the same loop, so the accounting would have had to exist in
    two places that must agree — the exact shape of the bug from round 2, hours earlier.
  - **Still needs an in-game look** — everything above is headless plus a run against the
    real XML and `gear.lua`. It went to main anyway on Henrik's call (`605045f`); that is a
    deliberate override of the queue's field-confirmed rule, not evidence it was met.
  - **A thing worth telling the friend:** that file is half-migrated. Its `<sets>` defines 23
    sets, but its rules reference **17 that do not exist** in it (`Precast`, `EnhPre`,
    `SelfRefresh`, `Enfeebles`, `Helix`, `MB`, `Nukes`, `DarkMagic`, `Death`, `SS`,
    `Enhancing`, `Impact`, `MDT`, `PDT`, `Myrkr`, `MultiWS`, `TP-$Set`), while
    `MidcastEnfeebling` and `MidcastStoneskin` are defined and never used — a BLM/generic
    template with a WHM `<sets>` block pasted in. The import is unaffected (it reads `<sets>`
    only), but he is not running the config he thinks he is.
  - **Group import: there is nothing to import.** Asked and answered — the format has no Lua
    at all, so `groupimport`/`groupscan` have nothing to eat. The three table-ish things and
    why none qualifies: `<variables>` are scalar MODE flags (they map to the Modes library,
    not Groups); `ad_name="Cure*|Cura*"` is a pipe-separated GLOB list inside a rule, and dlac
    Groups hold literal action names — expanding globs is a different feature that would
    silently change meaning; `<include>` is a DressMe item fetch list. Don't re-derive this.

- **2026-07-30 (`2026.07.30g`): what you last ate, and one click to eat it again
  (`feature/foodwatch.lua`).** Suites **5203 + 877**, both interpreters. **ON MAIN**
  (`605045f`, 2026-07-31) — it rode the Ashitacast promotion, because `dev` promotes
  whole-or-not. Still **NOT field-confirmed**: an in-game pass is owed on this too — and it
  is now written up as a round to actually run, in the **2026-08-01 entry at the top of this
  section**. This bullet is the design; that one is the checklist.
  - **The design problem was "what is food".** Nothing client-side answers it — the item
    resource calls a Mithkabob and a Potion the same thing (usable items), and the Catalog is
    gear-only. The server's answer is the only one: eating grants `xi.effect.FOOD` (251; 787
    item scripts carry it on stable). So dlac ships **no food list**: an outgoing item use
    (OUT `0x037`, `equipengine.parseItemUse`'s twin) says WHICH item, and the FOOD effect
    moving right after says it WAS food. A food dlac has never seen is learned the first time
    you eat it — custom server foods included — and a Potion can never be mistaken for one.
  - **"Moving", precisely — and this is the part presence alone gets wrong.** Re-eating over a
    live food never flickers the icon, so presence is not the signal; the **expiry** changing
    is. Read from `player:GetStatusTimers()` alongside `GetBuffs()` (the two arrays pair by
    index — the `timers` addon's read, field-proven on this client), compared for
    **inequality only**: no epoch, no clock arithmetic, no wrap to get wrong. *How long is
    left* is a question the buff-timer addons already answer and this module deliberately does
    not re-answer. With no timer array readable, a re-eat is honestly unknowable and nothing
    is recorded (the first food of a session still lands, on the absent → present edge).
    **2026-08-01 field correction:** the premise is a retail one and does not hold here —
    **CatsEyeXI refuses an item use while the FOOD effect is up**, so you cannot eat over a
    live food at all and the expiry edge is not the primary path, the absent → present edge
    is. The branch is kept as insurance for a wear-off-and-re-eat inside one 250ms poll gap.
    Neither the code nor the "no list, learn it from the effect" design is affected: what
    proves an item is food is still the effect moving.
  - **Henrik's ruling (2026-07-30) is what makes the history trustworthy across a login:**
    dlac is always loaded, so if the effect is still up at login it is — near-certainly — the
    last food the file recorded. `status().current` therefore **names** the food that is up,
    instead of reporting a bare "food active" that helps nobody.
  - **The rows.** The most recent foods you are CARRYING (**two** as shipped here, **three**
    since 2026-08-01 — `M.MENU_N`) — it walks *past* a food you
    have run out of to the next one you still have, rather than showing a dead row (the
    history keeps 10 so it has somewhere to walk to). Inventory only: `/item` reads nowhere
    else. They draw in the **Menu popup** under the roster (every row above is a door; these
    are the only two that spend an item) **and** in the **Teleports popup**, which is the
    floating quick menu — "my food just wore off" happens mid-fight with the main window shut.
    One definition, `ui/menuui.renderFoodSection`, geometry passed in; the row art is the
    item's **own** icon (`ui/itemicons`), so there is no PNG to ship and no food list to keep
    art in step with. Nothing is drawn at all when you carry none.
  - **`/dl food`** — what is up and what you can eat; `/dl food 1|2` eats that row;
    `/dl food forget` clears the history. Per character, `<char>\dlac\foodhistory.lua`.
  - **Threading:** the packet handler takes the one read it cannot defer (the item id — the
    last item of a stack is gone by the next frame) and does **nothing** else; naming, the
    history, the file write and every chat line happen on the frame tick (the
    synthrun/chocowatch law).
  - **Tests FW0–FW25** drive the pump off an injected **function**-valued read table, which is
    the shape the live path passes — the `combat.lua` lesson below, applied at birth rather
    than after a promotion. **MN18a–MN18j** render the section inside the menu popup and pin
    the stacks balanced, the empty case drawing nothing, and a throwing foodwatch costing its
    own rows and not the menu.

- **2026-07-30 (`2026.07.30f`): the combat service never CALLED its reads, and
  BST Fight has been dead on `main` since the api-2 promotion.** Suites **5149 + 867**, both
  interpreters. **`main` is currently carrying this bug** — it rode in with `f8df96b`
  (`2026.07.30a`) and shipped in the `1551faa` promotion the same day.
  - **The bug.** `feature/combat.lua`'s pure core `fromReads` *stored* `reads.engaged` /
    `reads.target` / `reads.swung` instead of **calling** them. The live table (`M.reads.*`) is
    **functions**, so `engaged` was a function reference — and a function is never `== true`, so
    every consumer's positive-true gate failed forever. `tonumber(<function>)` is `nil`, so there
    was never a `targetIndex` either. BST's Fight switch (`fight.lua` → `pollDecide`) therefore
    answered **`not-engaged` on every beat**: the pet was never sent, in either Attack or Follow
    mode, and the Panel said "you are not engaged" while you were swinging. Reward, Resummon and
    the Summon set are **unaffected** — they ride `petvitals`, which reads correctly.
  - **Why no round caught it.** Fight's 07-29 field confirmation was on its *private* pet-vitals
    poll; `f8df96b` moved it onto the new service and onto this bug in the same commit, and the
    api-2 train was promoted before a BST round ran against it.
  - **Why the suite stayed green, and this is the lesson.** All 31 existing CBT checks injected a
    stub of **values**; nothing ever drove the service off a **function**-valued table, which is
    the only shape the addon actually passes. **A service with injected reads needs at least one
    check that drives `get()`/`pump()` off `M.reads` itself** — new **CBT32–CBT39** do exactly
    that (they fail on the pre-fix file; verified by reverting and re-running). `feature/petvitals`
    is the correct idiom and never had the bug: `if type(r.pet) == 'function' then pcall(r.pet)`.
  - **Credit + provenance:** found by Henrik's friend while building a **PUP** helper against the
    same beat — the second module on `S.combat` is what exposed it. His patch was read as evidence
    and **ported by hand** (the standing rule for field reports), not applied.
  - **Not field-confirmed yet; not queued for merge until Henrik sees the pet go in.**

- **2026-07-30 (later, UNCOMMITTED on `dev` at time of writing — `2026.07.30b`, engine v157):
  the BST field round — two bugs, one feature, one registry.** Suites **5073 + 817**, both
  interpreters. Not field-confirmed yet; **not queued for merge** until it is.
  - **The Reward set picker listed the wrong sets** (friend's field report). `S.sets.names()`
    answered `profilesets.staticSetNames()` — the pre-profiles job file's flattened leftovers plus
    the pre-migration backup, i.e. the Copy-from helper's **import sources**, not a live library.
    Now the **Dynamic** sets, and `S.sets.slotsOf` answers from the engine's own flatten
    (`dispatch.flattenedSet`) so a helper claims the piece the engine would equip at the live
    level, ladders and virtual entries included. No `api` bump: the entry was pointing at the
    wrong table, not changing meaning. Tests MA23–MA28d.
  - **The Resummon rule never fired, and the server says why.** `CMobEntity::Die` pushes the
    "falls to the ground" battle message; a jug pet is a `CPetEntity` and **`CPetEntity::Die`
    pushes nothing at all** (`src/map/entities/petentity.cpp:232`). So dlac's chat proof could
    never arrive for a pet, leaving only the ≤25% last-seen-HP guess, which misses any pet killed
    from above it. The fix is a **witness, not a wording**: the vitals record now carries the pet's
    `id`/`index`, and on the vanish the service re-reads that index RAW (`M.reads.entity` — the one
    read allowed to see a corpse, since `gData.GetPet()` refuses an HPP-0 pet) and confirms by
    **server id**. A corpse that reads ALIVE now suppresses; the low-HP guess is demoted to "only
    when the corpse could not be read". Jug-vs-charm gained **provenance** — the Call Beast /
    Bestial Loyalty / Charm we watched you press stamps the pet that appears next — so a **custom
    jug** no roster describes resummons like any other. Tests PVL67–PVL89.
  - **The Summon set** (Henrik's ask): an optional set worn around the summon, best-effort, jug
    still the only slot that must verify, **weapon slots left alone by default** (a swap costs TP),
    claim held `2s` past the fire. Plus **Summon now** — a Panel button and a bindable action,
    the third requester of the one act. Tests BRS85–BRS105.
  - **Every dropdown in the Panel is searchable** (`panelkit.combo` — so the Reward set, the Summon
    set and the jug picker all got it at once, and so does every future module's). The box opens
    focused, filters live off the buffer (no Enter, no ImGui flag global), clears when the popup
    closes, and matches **all** whitespace-separated terms as literal substrings against the label
    plus an optional `searchOf(row)` — so `carrot hare` finds the Carrot Broth that calls a Hare
    Familiar, and a typed `-` cannot behave like a pattern quantifier. Tests PK25–PK34 (the rule,
    pure) + S357i–S357n (drawn and wired, on the real Panel).
  - **The jug picker is capped at 75** (`jugs.MAX_LEVEL`). The catalog is retail's: **65 of its 98
    BST-only Ammo rows are Lv76–99**, so two thirds of the picker was jugs nobody on this server
    can equip, none of them even mapped to a pet. 98 rows → 33. The cap is applied to the level the
    row *reports*, so `M.LEVEL` (live-observed) still wins — a jug this server re-tuned into reach
    comes back with one row there, not by moving the cap. Tests JUG17a–JUG17d.
  - **The keybind registry** (`feature\keybinds.lua`, **ADR 0032**) and the module `commands`
    block: `/dl jobhelper <module> <action>` (`/dl jh`), `/dl binds`, blocking-with-the-holder-named
    on a collision, and **mode binds moved onto it** — so they finally release on a job change.
    Tests KB1–KB40, JHC1–JHC24.
  - **"You are not carrying any pet food" now speaks ONCE PER ZONE**, not once per lockout window
    (Henrik, off his own probe log, where it turned up mid-fight). The lockout is a budget for how
    often the rule may speak and fits every refusal the world may resolve on its own; an empty bag
    is fixed by shopping, not by waiting 30s. Zoning re-arms it, and so does carrying food again.
    New API entry `S.player.zone()` (the central `location.zoneId()`), and the **zone id itself is
    the latch** — an unreadable zone is a value like any other, so a headless world gets one line
    and silence. Tests BRW74–BRW79c.
  - **THE SPACE** (field, from a chat line in a screenshot: *"The SheepFamiliar defeats the
    Clipper."*). The client's entity name for a jug pet carries **no space**; every published
    table, `jugs.PETS` included, writes one. Compared raw, **not one jug pet matched its own roster
    row** — so the classifier called every one of them CHARMED and the Resummon rule refused
    exactly as designed. A total, silent failure of the feature from one space, and the second
    half of why the field report happened. `jugs.isJugPet` now compares SQUASHED (spaces out,
    lowercased) on both sides. Tests JUG5a–JUG5e.
  - **THE CORPSE IS FIELD-CONFIRMED** (2026-07-30, `/probe pet` on a SheepFamiliar killed by a
    Gigas's Leech, dlacprobe 2.5). The flip is **instant** — last attached read `hpp=1 status=Idle`,
    and on the same 50ms poll the index already read `hpp=0 status=Dead(3)`, **+1ms** — so the
    `corpse == false` suppress cannot misfire on a real death. The corpse then **persisted the full
    15s** the probe watched, same index, same server id (against the ~2.5s `Internal_Die(2500ms)`
    suggested), so a 0.4s beat gets ~37 looks, not ~6. And the death was **totally silent**: not one
    `falls to the ground`, `is defeated` or 0x029 battle message in the whole run. Raw dead status
    reads **3**. The entity name came back `SheepFamiliar` — the spaceless form, straight from the
    entity table. No code changed as a result; the flagged assumptions in `petvitals` were replaced
    with the measured numbers.
  - **2026-07-30 (later still, `2026.07.30c`): the resummon FIRED, and picked wrong.** Field: the
    pet died and was detected — the corpse witness works — but the rule fired **Bestial Loyalty into
    its own cooldown** while "use the other if mine is on cooldown" was on and Call Beast sat
    unused. Three defects, each real on its own:
    1. **The recast unit was wrong by 15x.** The client stores ability recast in **jiffies (1/60s)**;
       `feature/recast.lua` divided by **4** (a quarter-second guess borrowed from `nativedata`'s
       `RecastDelay`, which is a RESOURCE field and a different unit). Settled by two independent
       addons on this disk — `timers\recasts.lua` (`60 * (90 + reduction)`, "the same format as
       timer is stored in") and Rune-Actually-Helper ("jiffies -> seconds"). It never flipped
       ready/down, but every countdown dlac ever showed was fifteen times too big.
    2. **The by-NAME recast-slot resolution NEVER worked, and it is one guard.** Ashita's resource
       objects are **not Lua tables** — they index with `.` and answer `userdata` to `type()` — and
       `recast.lua` tested `type(rec) == 'table'` where every working reader in dlac and in the
       sibling addons tests `~= nil` (`nativedata`: `res ~= nil` then `res.RecastTimerId`;
       `dispatch`'s item lookup; Rune-Actually-Helper). So every by-name resolution answered
       UNKNOWN, unknown reads READY, and that is how a summon twenty minutes from usable looked
       available. **Reward hid it since the file was written**: it declares `timerId = 103` and
       never takes the name path, so its countdown always worked while both summons were blind.
       Field reads go through `M._field` now (nil-guarded, pcall'd, a real seam). Belt and braces
       beside it: several name indexes are probed, then a one-time walk of the ability table
       indexed by name. **Caught by mutation-testing the new checks** — restoring either guard
       fails RC28 / RC30, and the first draft of RC30 used a table stand-in that passed either
       way, which is exactly how the original survived a test suite.
    3. **"Unknown reads READY" was applied to a CHOICE.** That courtesy gate is right for greying
       out a button and wrong for picking between two abilities, where it does not permit an action
       but PREFERS one. `pickMethod` is now a real tri-state, and — because `ready` alone answered
       `true` for both "measured idle" and "could not measure" — `liveRemaining` now returns **0**
       for the former and **nil** for the latter, so the difference exists at all. `resummon.measure`
       is the one place the module reads it.
    The Summon section now prints each method's measured state (`Call Beast: ready` /
    `Bestial Loyalty: 12m 34s` / **`cannot read its cooldown`**) — so if defect 2 ever returns it is
    visible before it costs a resummon. Tests RC19–RC26, BRS33a–d, BRS101a–f.
  - **FIELD 2026-07-30, the Summon set:** Henrik — *"Summon with chr+ worked even with beastial
    loyalty"*. The set lands, on **both** methods, which is what the code shape predicts (the claim
    rides `METHOD_COMMAND[method]`, so it dresses Call Beast and Bestial Loyalty alike) but had
    never been seen. Note the asymmetry it does NOT settle: CatsEyeXI's **Beast Raising** bonuses
    are documented as Call Beast only, so whether the CHR bonus is likewise Call-Beast-gated is a
    separate question from whether the gear went on.
  - **Still owed:** the behaviour round — Resummon actually firing end to end, the key binding.
    **And read the OPEN box in
    [reference/catseyexi-jobs.md](reference/catseyexi-jobs.md) under Beastmaster → Ready Strength
    before extending the CHR work**: the wiki's own advice suggests the CHR is sampled at **Ready**,
    not at summon — in which case the same set belongs on an `Ability` trigger matching `Ready`,
    which needs no new code.

- **2026-07-30: the Job helper MODULE API v2 is on `dev` (pushed), waiting on Henrik for the
  whole promotion — the merge AND the push, since the classifier refuses Claude both
  (`2026.07.30a`; the queue above is emptied and carries his one command block, message
  pre-written at `.git/PROMOTE_MSG`; `git log --oneline origin/main..main` says whether it
  landed).** The framework half the first module paid for
  by hand: **the Module API** (`feature\modapi.lua` — the one table `S`, versioned `api = 2`;
  the *supported* surface, still no wall — ADR 0028 stands), **declared settings** stored by the
  framework (`feature\modcfg.lua`; BST's own 193-line `config.lua` deleted), **the combat state
  service** (`feature\combat.lua` — one record for engaged / target / targetChanged / swung, its
  own beat after engagewatch's, so a combat feature stops borrowing the *pet* service's
  metronome), **the Panel widget kit** (`ui\panelkit.lua`), and **a copyable working template**
  (`docs\templates\example-helper\`, held to the real contract by its own tests). BST's four
  behaviour files are rewritten onto all of it and the authoring guide is rewritten for `api = 2`.
  **Built 07-29 late and left uncommitted overnight** — it was running unversioned on Henrik's
  client, which is how the next item was found. Riding with it: **the percent fix** — every imgui
  text call is a `printf` format string, so the Reward caption printed a heap address
  (`below 51F4A60263et HP`); the kit escapes at its funnels now and the caption is deleted on
  Henrik's *"not really relevant text"*. Suites **4960 + 817**, both interpreters. No engine
  change. The behaviour field rounds below are unchanged by this train — the logic moved file,
  not meaning.

- **2026-07-29: THE JOB HELPERS ERA IS ON MAIN — the whole PRD #135 train, grill to guide
  in ONE day, promoted `56221c1` on Henrik's push (main content-identical to dev).**
  What exists now: the **Job helper** module system (drop-in folders `jobhelpers\<job>\<module>\`,
  one folder = one row = one server-approval unit — ADR 0028 as amended; loader with loud
  containment; per-job tab sections; the per-job `JobHelper` Claim Priority anchor), the
  complete **BST Helper** (`bst\bst-helper\`: Fight — POLL-driven after two failed edge field
  rounds, with the **Respect Heel** and **Send when: drawn/first-swing** options; **Reward
  now** + the auto-Reward rule; death-only **Resummon** over the classified pet-loss edge),
  six consumable central services (Action sequencer ADR 0030, engagewatch + first-swing,
  petvitals + classifyLoss, recast, petfood, `cmdqueue.issue`), and the
  [authoring guide](reference/jobhelper-authoring-guide.md). Engine v154 → **v156** (v156 =
  dayMatch, the parallel session's train, promoted together). Addon `2026.07.29a`–`29o`.
  **FIELD-CONFIRMED:** the tab + sections, Fight (both modes), Reward-now end-to-end
  (recast id 103 + the `/ja` token proven), the Locks refusal, per-job rank drag, the
  blueprint round-trip of case rules. **FIELD ROUND OWED (every unknown fails SAFE —
  worst case is an act that does not happen):** the auto-Reward rule at its threshold;
  Resummon whole (jug→pet rows, the pet-falls wording, `LOW_HP_PCT = 25`, summon target
  tokens, pet commands on category 0x09); the Heel latch and the first-swing gate in real
  pulls; `dayMatch` on a matching day; the trigger-cases fieldtest checklist
  ([design/trigger-cases-fieldtest.md](design/trigger-cases-fieldtest.md), copy-case above
  all). **Queue:** the agent pipeline is EMPTY (all of #136–#142 merged + closed; workers
  now run Opus 5 at max effort); **#129** (blueprints finish, de-risked by the field
  round-trip) waits unlabeled as the next natural dispatch. The tester's BST is level 21:
  Bestial Loyalty and food tiers ≥ Beta stay out of field reach for now. Deep story:
  `docs/history.md` ("the maintainer day") for the two paid ops lessons — the shared-checkout
  smuggle and the deployment gap — plus this train's per-slice entries below.

- **2026-07-29: the Job helper module paper — authoring guide + ADR 0030 + the service rows
  — DOCS ONLY, no behavior** (issue #142, PRD #135; the last slice of the Job Helpers train).
  [`reference/jobhelper-authoring-guide.md`](reference/jobhelper-authoring-guide.md) is the
  author-facing contract, written as the sibling of the integration guide and *as shipped*:
  folder anatomy (`jobhelpers\<job>\<module>\`), the exported table and what an `api`
  mismatch does, the load lifecycle, the containment table (what dlac guarantees, what it
  expects back), per-character config storage, every central service a module may consume
  with the rules that bite, a complete two-file working module, and the five hard rules —
  **claim-not-commit**, **one-line acks**, **consume the central services**, **module
  independence on shared jobs**, and the **sequencer's serialization**. Glossary terms are
  linked to CONTEXT.md, never restated. **ADR 0030** records "a module owns initiation" with
  its real alternatives — and records that the rationale the PRD carried (*an instant ability
  cannot be caught reactively*) was **falsified in the field on 2026-07-29**: the reasons that
  hold are initiation and the equip precondition, and a player's own precast Trigger composes
  freely with a food-only claim. ADR 0028's Deferred section now points at it. The
  Central-services table gains the **recast** and **Action sequencer** rows (the edge and
  vitals rows were already there; their consumer/path lines are corrected to the job-first
  layout and to Fight's poll rewrite). **Doc drift corrected:** the command queue does *not*
  "drain one per frame" — `tick()` flushes everything due, in insertion order, and spacing is
  the caller's `delayFrames`. No engine change, no `dispatch.M.VERSION` bump, no version
  date-bump: nothing executable moved. Suites **4779 + 817**.
- **2026-07-29: BST Resummon — the pet-loss edge gets CLASSIFIED, and only a proven jug
  death spends a jug — MERGED to `dev` (`2026.07.29o`), field round owed**
  (issue #141, PRD #135). The third standing BST Helper behavior, and the
  one whose failure mode costs real money. Its whole design is one asymmetry: **a missed
  resummon costs the player nothing, a wrongly-assumed one costs them a jug** — so
  `petvitals.classifyLoss` proves a death or reports `unknown`, and never guesses.
  **Two proofs**: the pet-falls chat line (read off `text_in`, the channel the client
  already renders — history.md's dig-obtained lesson, where two packet guesses lost to one
  hgather grep) and a present→absent transition after a **low last-seen HP%**
  (`LOW_HP_PCT = 25`). **Three suppressors, checked first**: an observed outgoing Leave
  (0x01A category 0x09, ability resolved BY NAME off the client's own resource — no
  hardcoded ability id anywhere in this slice), zoning, and logging out. **Jug vs charm is
  decided by NAME** through an injected authority, so the service owns the rule and the
  BST module owns the list (`jobhelpers/bst/jugs.lua`) — charm loss and a charmed pet's
  death trigger nothing at all.
  The Panel gains the **Resummon** section: a jug picker over the CATALOG's own jugs (a jug
  is exactly a BST-only Ammo item — the mapping module ships the jug→pet names and the
  level *overrides*, never a second copy of the catalog), the binary Call Beast / Bestial
  Loyalty choice, and the "use the other if mine is on cooldown" checkbox (default on) with
  the trade in its hover. Out of jug is ONE loud line, and the Loyalty fallback does not
  rescue an empty bag — both methods need the jug WORN, which is why this is an Action
  sequence and not a bare command. Both recasts down **queues**, and the queue is cancelled
  by zoning / Leave / logout / any pet appearing — and by disarming the rule, which is the
  row pill's whole job. It deliberately has no expiry: Bestial Loyalty's recast is measured
  in minutes.
  Suites **4732 + 817**. **NOT field-tested** — and three things in it can only be settled
  in the field: every jug→pet row (hand-transcribed, `cexi`-anchored rows first, unplaceable
  rows shipped EMPTY rather than guessed), the exact pet-falls wording, and whether pet
  commands really ride action category 0x09. All three fail SAFE: the worst case of each is
  a resummon that does not happen. The maintainer's ruling for this slice is recorded in
  `jugs.lua`'s header — live > wiki > repo, and repo SQL is inherited-base only.
- **2026-07-29: `dayMatch`, the day-only environment condition — ON `dev`, IN THE MERGE
  QUEUE, field round owed** (`2026.07.29h`, engine v156, ADR 0029; the queue entry above is
  the status authority). Henrik: *"there are items that give you bonus solely if the day
  match what you're casting."* The environment vocabulary is now a TRIO, and the three are
  three different questions about the world: `dayWeatherBonus` (the obi's signed day+weather
  net, with opposition), `weatherMatch` (spell element == CURRENT weather element),
  `dayMatch` (spell element == TODAY's day element). The net cannot stand in for a day-only
  item — on Firesday in Water weather it reads +1 −1 = 0 and stays quiet while the item IS
  paying out, and on Earthsday in Fire weather it reads +1 and fires while the item is dark;
  `weatherMatch` has no day term at all. Precast + Midcast, tier 30; `dayMatchesAction` reads
  `GetEnvironment().DayElement` (the same field `netForElement` scores, cached on `ctx.del`);
  unknown day or no action element matches NEITHER polarity. **There is no "clear day"** —
  all eight weekdays carry an element, so only a broken read is unknown (weather's `None` has
  no day counterpart), and the day is not storm-aware. **Deliberately NOT pinned to a named
  server mechanic** the way ADR 0018 pinned `weatherMatch` to `ALACRITY_CELERITY_EFFECT`: the
  server source is not on this machine and no item was named, so it ships as a calendar
  primitive. Pinning one item's exact gate (day only, or day-or-weather the way the retail
  obi tooltip reads?) is an open follow-up that changes what a player *composes*, not what
  this condition means. Tests DM1–DM24; full story in `docs/history.md`.

- **2026-07-28: the Ventures rings reach the Crafting Gear panel — ON MAIN, field round
  owed** (`2026.07.28o`; promoted the same hour on Henrik's *"push to main"*, deliberately
  un-field-confirmed — the second such call today. It is display + one coverage light with
  no scoring change, so the blast radius is a panel column). Henrik, with the two wiki pages: the EXP Ventures exchange belongs
  in Gear Helpers → Crafting Gear — Craftkeeper's / Artificer's Ring at 1,000, Craftmaster's
  at 2,000 — plus the **+1** upgrade through Synergy. The rings were never invisible to the
  ENGINE: all four sit in the catalog with their synth mods and the craft ladders are
  data-driven off exactly those stats, so an owned Craftmaster's Ring has been equipping on
  the `hq` goal all along. Only the *panel* omitted them, which meant it answered "what
  should I go get?" with eight guild grinds and no mention of Populox. They render in the
  **third** column under a `Ventures` divider (a per-row price tag needs a column with
  nothing to its right); Midras's Helm +1 moved into the same block — same exchange, 3,000
  — because one home per item beats two. Prose lives in hovers per the panel-text standard:
  Populox at Upper Jeuno (I-11), and the Port Jeuno furnace wanting **3x Guild Token** for
  the +1 (CatsEyeXI never implemented the synergy minigame — no skill, fewell or rank). The
  `Torques`/`Rings` headers became help labels for the Artisan's +1 halves, one string
  re-worded by gsub so they cannot drift. **One bug fell out of listing them:**
  `CRAFT_UI.level()` counted only guild gear, so a Craftmaster's-only character read
  *"nothing applicable"* while the ladder was equipping the ring; Populox rings now count as
  level 1 and that label reads "basic craft gear". New smoke `CV0-CV14` drives the **real**
  craft detail view — it had **no** render coverage, and `renderTab` swallows render errors
  in a pcall, so a typo'd upvalue would have blanked the panel in-game and passed every load
  test. Suites **4198 + 726**. Display + one coverage light; **no scoring change**. Not in
  Open question left for him:
  Craftkeeper's Ring scores only on `nq` (`SynthMaterialLoss` is read into `nqScore` and
  nowhere else) — arguably it helps every goal, but that moves what the engine equips.
- **2026-07-28: three faults, one sentence — the tester's SCH import — ON MAIN,
  FIELD-CONFIRMED** (`2026.07.28n`; promoted un-field-confirmed on Henrik's *"push to main
  so he can test"*, confirmed within the hour: *"it works"*). The parse error was **his own
  hand edit**, not decay: he had removed an even-older aug-suffixed entry
  (`MistSilkCapeAug`) from the list and not put the comma back — which is the ordinary way
  a legacy file breaks, and exactly why the red parse line earns its place. He tried to import his **Cure** set with the new
  FFXI-LAC column and got *"Created 0 new sets — nothing created, 1 skipped: no owned/known
  gear."* Henrik sent the file; it carries **three** independent faults, and dlac answered
  all three with that one sentence (hard rule 12, undiluted). **(1)** It does not parse —
  line 266 ends `gear.Back.MistSilkCape` with no comma. `sandboxSets` now separates "file
  absent" from "file present and will not parse", and `legacyDiag()` prints the name plus
  **the parser's own message** in the Copy-from popup, in red. **(2)** It requires dlac's
  library under dlac's former addon name, which does not exist here — the soft require
  returned the STUB, so every `gear.X.Y.Z` became the stub object (and reached
  `string.lower()` as a table, whose error discarded the whole set). Module names are
  aliased onto dlac's now, so the file resolves against **this character's** inventory.
  **(3)** It uses the pre-flat `gear.Ammo.Throwing.X` shape, which either errored or left a
  `nil` hole that **truncated the `ipairs` walk** of a candidate list (60 entries → 10).
  The importer reads through `legacyGear` now, whose **MISSING sentinel** answers any key at
  any depth and is skipped — Henrik's ruling verbatim: *"If pieces don't exist, just skip
  them and move on like he doesn't have it."* Hardening rides along: `resolveSetItem` reads
  `Name`/`Id` **typed**, and `importStaticSet` pcalls each candidate so a throwing resolver
  costs one entry, not a set. `SH21` respected in letter and spirit (this renames a MODULE,
  it never opens a file in that tree). Tests **`PSM0-PSM14`** drive a fixture shaped like
  his file and install a `setfenv` polyfill so 5.4 finally exercises the LuaJIT sandbox
  path all of this lives in. Suites **4198 + 707**. **He must still add the comma** — no
  reader can load a file Lua itself refuses.
- **2026-07-28: today's fishing ventures lost the wrapped line — ON MAIN, FIELD-CONFIRMED**
  (`11aa270`, `2026.07.28m`). Henrik: clicking **[!ventures fishing]** "only reads the first
  line, not the 2nd". The capture mirror answered it before any theory did
  (`Mindie_29909\fishventures_capture.txt` — *artifacts first*): the server's fishing reply
  is **level bands over TWO chat lines**, and the second carries no `Fishing:` prefix —
  `Fishing: (0-19) Quus, (20-39) Cheval Salmon, (40-59) Bluetail,` / `(60-79) Bladefish,
  (80-99) Gavial Fish, (100+) Giant Chirai`. The parser knew only HELM's
  `(Low)/(Mid)/(High)` shape, so line 1 survived as an unparsed raw tail and line 2 — a
  category line without a category — fell to the `general` bucket, which the panel draws
  **only in the `elseif`**, i.e. never beside a parsed line. The saved `fishventures.lua`
  showed the split verbatim: line 1 in `lines`, line 2 in `general`, captured and invisible.
  Fix: `parseBands` (band entries → aligned rows, **two minimum** so a stray parenthesis in
  party chat can't pass for a band list) + `parseVentureCont` gated on an **armed** flag —
  the wrap joins the header's block and stays armed, so a third line would join too; unarmed,
  bare bands are chatter and cannot hijack the block. A re-ask reprints everything, so the
  first *named* reply line (banner / header / wrap) swaps the stored answer out instead of
  layering on old-format leftovers. And the panel now draws unrecognized captured lines dim
  ("also captured") **beside** a parsed block — the bug class was a line being kept but
  never shown, and that hole is closed for the next format drift too. 11 checks replay the
  real field lines through `onChatLine`; format now PINNED in
  `docs/design/fishing-gear.md` §2.5. Suites **4183 + 707**.

- **2026-07-28: "Automations" is now "Gear Helpers" — ON `dev`, NOT yet field-confirmed**
  (`2026.07.28j`). A **GM** objected to the naming: a tab called *Automations* full of
  *Auto \<activity\>* rows reads as *the addon plays for you*, and botting is not allowed
  on CatsEyeXI. Henrik brought it as a naming question. The diagnosis: a synonym for
  "automation" fixes nothing — the rows were named after the **activity** ("Auto Fish
  Set"), when every one of them only picks **equipment**. So the rename **names the gear,
  not the act**: tab **Gear Helpers**; rows **Elemental Staff**, **Elemental Obi**,
  **Oneiros Grip**, **Ammo**, **MaxMP**, **Crafting Gear**, **Gathering Gear**, **Fishing
  Gear**, **Chocobo Gear**, **E-Box Restock**; Kind column **gear rule (Main slot)** /
  **hobby gear (idle only)**. HELM's proximity switch speaks **armed / ARMED** instead of
  "Auto HELM is ON" (the verb `helmbar` already used). A standing line sits above the list
  and in the guide: *"dlac equips gear. It never acts for you — you still cast, craft, fish
  and dig."* — the reply to the objection, on screen, permanently.
  **Display-only, and that boundary is the point:** `dlac:Auto*` slot markers are on-disk
  contracts inside users' set files, row `key`s index `openDetail`/`AUTO_SECTIONS`/the quick
  menu, and Arbiter claimant names are persisted in `arbstate` **and printed by `/dl why`**
  — none of those identities moved. **Follow-up the same day** (Henrik: *"I'd rather not
  have it called AutoAmmo in the arbiter list. I don't mind its name being that internally,
  but not in the GUI"*): `arbiter.ARB_DISPLAY` / `claimantLabel` — one map, and every
  surface that names a claimant to a human goes through it (Priority list, Arbiter Monitor
  chips + hover, `/dl why`, `/dl prio`, the naked/lock "rank ABOVE" notices), so the GUI and
  the chat cannot drift. `AutoAmmo` renders **"Ammo rule"** — *rule*, because a claimant
  prints next to a slot (`Ammo: <claimant> (rank 5) over MaxMP`) and test `AR12` caught
  "Ammo: Ammo". Identity untouched, so no saved ladder reorders.
  The full split is a table in architecture.md ("Naming: display labels vs internal
  names"); `CONTEXT.md` retires **Automation** as user-facing vocabulary in favour of
  **gear helper** / **gear rule**. `host.selectTab` matches on the tab LABEL, so
  `gearui.openAutomation` and smoke_ui `S10b` moved with it. Also renamed: the Equipped
  tab's per-piece **Auto Type** → **Gear Rule** (dormant on main). `Auto-build` /
  `Auto-Import` were left alone on purpose — those are GUI tools the player clicks, not
  gear that moves on its own. `autogear.golden` regenerated for the manifest's header line
  (`gen_goldens.lua`, one-line diff, reviewed). Suites **4146 + 707**.
  **Rode the 2026-07-28 promotion to main** (`dev` promotes whole-or-not) ahead of its
  own field round — the round is still owed, though Henrik played the whole 07-28
  session on it without a snag; display-only by construction.

- **2026-07-28: the INTEGRATION SURFACE end to end + the ARBITER MONITOR — ON MAIN
  (promoted 2026-07-28), FIELD-CONFIRMED** (engine v152–v154, `2026.07.28g`–`l`;
  commits `5c1874b` `f645d25` `1eeb749` `9c4b17c` `b3e3e72` + five docs commits). The
  one-day arc, Henrik managing: the **decision ring** (one record per moved outcome —
  items or any slot's winning claimant, *"only push changes"*; the rank order became a
  retrace-sig leg, `|ao`); the **Arbiter Monitor** (4x4 equip-screen grid of the viewed
  decision, claimant chips + legend, hover = the full per-slot contest, decision log
  with pin-to-moment + Live; responsive on Henrik's call — icon-only narrow, double-
  space names wide; openers Menu → Settings + Gear Helpers → Claim Priority; the
  Trigger Monitor untouched — proposals there, outcomes here, one record three
  renderers); the **plugin_event probe verdict** (evprobe + dlacprobe 2.3: send = byte
  table only, receive = `e.data` already a STRING + `e.size`, `e` is userdata, a state
  hears its own RaiseEvent); and the **stream end to end** (`feature\integration.lua`,
  `/dl stream on|off` Session switch dying only when world absence outlasts a zone —
  the new read-only `worldAbsentOutlasted` seam — and surviving job changes; snapshot-
  on-enable; four kinds on ONE stream-side `seq` — `worn`, `dispatch` ANCHORS off the
  v154 engine ACTION FEED (one anchor per action, worn XOR dispatch), `invalidate`
  (sets-rev + job), delta-only `confirm` (landed-whole = silence); five queries, the
  switch gating the whole channel). Suites **4172 + 707** both runtimes.
  Field-confirmed: the monitor by eye (*"Looks good"*), the stream envelope-by-envelope
  through dlacprobe (*"I can see the events happening… it is streaming as we think"*);
  `invalidate`/`confirm`/anchors/queries are headless-tested only until the parser
  friend's first connection — the consumer handover
  (`docs/reference/integration-guide.md`: start-here + "the Arbiter in 90 seconds")
  says so. Record: `docs/design/integration-surface.md` (§13 = the living state) +
  CONTEXT.md (Decision record, Arbiter Monitor, Integration surface, Session switch).
- **2026-07-28: the old FFXI-LAC *Dynamic* sets import too — ON MAIN (promoted
  2026-07-28), FIELD-CONFIRMED** (`2026.07.28d`). Henrik: *"when it sees a dynamic set, it's old FFXI-lac… it should be
  detected and enabled to be imported as a LAC import. If set names collide, prioritize
  the dynamic ones."* A legacy `<JOB>.lua` (and its pre-profiles backup) carries **both**
  kinds of source — LuaAshitacast statics at the root and dlac's own `sets.Dynamic` block
  from before profile storage — and only the statics were reachable. Now
  `profilesets.lacSetNames/getLacSets` harvest that block as an import source (never into
  the sets root: an FFXI-LAC set must never look live, and `liveSetNames` stays the
  trigger-target authority — `PSL7/8`), the Copy-from picker's right column carries both
  kinds as two headed lists — **Old FFXI-LAC sets** above **Old Static Sets**, both in the
  header blue (a dim sub-header under a blue one confused Henrik himself on the first
  pass) — and a name in both is listed once, as the **dynamic** one
  (`setimport.mergeLegacySources`, `AQ*`). The unmigrated
  character is the one exception: there the job file's block *is* the live list, so it is
  not offered as an import of itself (`PSL1/2`). The import itself rides the pinned
  `importStaticSet` transform — minus the not-best-first warning, which is a
  LuaAshitacast-static fact (those lists were always read by dlac's highest-Level rule).
  **Two bugs fell out of the same file read**, both real on this install:
  `profiles.legacyBackupPath` adds the pre-storage-move backup home
  (`luashitacast\<char>\backups\pre-profiles\`) — a character migrated in the LAC-tree era
  had its originals *only* there, so its whole legacy column read empty (5 SAM + 10 WAR
  statics were invisible); and the sandbox now hands legacy files the **missing-safe gear
  proxy** (`profiles._wrapGear`), so one unowned weapon category (`gear.Main.Club` on a
  char who never scanned a club) can no longer nil-index the chunk away and take every
  static in the file with it. Suites **4114 + 693**, Windows and WSL lua5.4; driven
  against the real files on this install before shipping (Mindie BLU: 8 old dynamic sets
  found, `Idle` resolving to 15 ordered slots). **Field-confirmed the same day** — *"looks
  good and works"* — after one revision Henrik called in himself: the first cut split the
  column with dim `Dynamic` / `Static` sub-headers under one blue heading, and *"Static atm
  is greyed out like dynamic, so it's hard to notice… even I got confused"*. Group labels
  are not dim.
- **2026-07-28: dlac seeds its OWN gear.lua, always — ON MAIN (promoted 2026-07-28)**
  (`2026.07.28f`, together with `2026.07.28e`).
  Henrik's ruling once the entry below was diagnosed: *"ALWAYS handle your own gear
  locally in DLAC. ONLY FFXI-LAC integration we should have, is SOLELY on importing
  dynamic gear."* `setupui.seedGearFile` used to **prefer** an existing
  `<charBase>\ffxi-lac\gear.lua` over dlac's bundled template — *"a returning player
  keeps their scanned inventory"* — which is exactly how a **brand-new install** ended up
  with a legacy, Ammo-nested, `Id`-less inventory (the entry below). It never paid: such a
  file carries **no `Id`**, and `RSlot` + the Range/Ammo `Pair` key are looked up BY id, so
  reserved-slot conflicts and ammo pairing were dead for every entry in it; its `Stats`
  blocks are inert (dlac derives stats from the catalog); and its contents are a
  *catalogue*, not the player's bags. `/dl scan` rebuilds all of it correctly in seconds.
  Now: bundled template, always. Guard `SH21` fails if anything reads a path out of that
  tree again; `SH22` pins the one door that must survive — the **content** sniff
  (`text:find('ffxi-lac')` → `st = 'ffxilac'`) that routes an old profile into the sets
  migration, i.e. the Dynamic-sets import, which is the only sanctioned integration.
  Prose about ffxi-lac is untouched; it is a **path** guard.
- **2026-07-28: commit READS gear.lua's shape instead of assuming its own — ON `dev`,
  awaiting field test** (`2026.07.28e`). The second field report from Henrik's friend
  (character `Abraxis_42505`), and the first bug that **needed a second player's file to
  see at all**. His `gear.lua` is a legacy LuAshitacast one: it nests **Ammo** by category
  (`Archery`/`Marksmanship`/`Throwing`) and its own trailer says so (`slotName == "Main"
  or "Range" or "Ammo"`). dlac writes Ammo flat (`WEAPON_SLOTS = { Main, Range }`), so
  `spliceStaging` inserted the new flat entry as a **sibling of the category tables**.
  The result still *parses* — which is why the parse check passed — and then the trailer
  descends into the entry's own fields and evaluates `("Bone Arrow").Name` → nil →
  `table index is nil`, reported against the **trailer**, ~6400 lines from the cause.
  Commit is all-or-nothing, so **no gear of any slot ever landed**: the same batch
  re-staged on every auto-sync and aborted again, leaving 15 byte-identical backups in
  90 minutes. Three fixes, one family — *commit's text readers disagreeing with the file
  in front of them*:
  **(1)** new `slotShapes` reads each slot's actual shape, and a disagreement ABORTS
  naming the slot (`SH1-11`) instead of writing a file that cannot load;
  **(2)** `gearProblems` walks the built table and names the culprit entry **and its
  line** — the raw error only ever named the trailer (`SH12-17`). Deliberately
  shape-**agnostic**: a consistent legacy file is never flagged, because which slots
  nest is that file's trailer's business, not ours;
  **(3)** `parseStaging`/`indexGear` now share `hdrAt`/`closeAt` with
  `parseGearEntries`, which already tolerated a trailing `-- comment` — a commented
  CATEGORY header was invisible to `indexGear` alone, so commit "created" a section that
  already existed, Lua's last-key-wins discarded the new block, and it **reported success
  while the items never landed** (`SH18-20`). Independent of the Ammo bug, and latent for
  anyone with a hand-annotated `gear.lua`.
  Two silent fallbacks lost their silence with it: `dlac.lua`'s boot preload and
  `gearui.refreshGear` both swallowed an unloadable `gear.lua` and ran on the bundled
  empty template — GUI shows no gear, every scan calls every item new, nothing says why.
  Suites **4134 + 693**, Windows and WSL lua5.4; reproduced and re-verified against his
  real 8,895-line file. Henrik's remedy for the friend: delete `gear.lua`, let `/dl scan`
  rebuild it flat. **PROMOTED to main 2026-07-28** on the diagnosis and the
  reproduction, before the friend re-tests — accepted un-field-confirmed, and this
  record says so.
- **2026-07-28: MaxMP pair homes anchor CHOSEN picks only — ON MAIN, FIELD-CONFIRMED**
  (`2026.07.28b`, promoted 2026-07-28 on Henrik's "push to main").
  Henrik's own diagnosis of the stage 6 field oddity (Outlaws
  Earring never equipped), confirmed exactly: the fmt 13 pair-home harvest homed **every
  authored rung** of the idle set's ear/ring ladders, so an unchosen leveling rung
  (Outlaws Lv50 under Loquacious Lv75 in Ear2) was exiled from ear1's ladder while its
  own slot's band read diff 0 — no band could ever build for it. The harvest now reads
  the **flattened** set (new `dispatch.flattenedSet` accessor — the same world the
  potency-point map always read): only the set's chosen picks anchor pair positions,
  unchosen rungs float and balance like undocumented gear. Chosen pieces still never
  plan across the pair. Tests FS*; full story in `docs/history.md` ("the earring that
  could never equip") + the re-ruled section in `docs/design/maxmp-mode.md`. The field
  check passed 2026-07-28: Outlaws restored to Ear2, and it equips — *"Now it works!"*
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
  - **Completion slice #128 — MERGED to `dev` 2026-07-29 (PR #134, addon `2026.07.29a`),
    NOT FIELD-TESTED as a whole.** Copy case (per-box `copy` affordance; case 1 = the body
    box, so "copy the rule body into a new case" falls straight out — pure seam
    `_copyConds`, deep-copy so the duplicate is independent), "Match either instead" + the
    repeat-replaces note working INSIDE a case (field iteration 1's `renderBox`
    already carried it; #128 pins it under test), box-header **hover help** via the
    panel-text standard (`uistyle.helpLabel` — underlined `& case`/`| case` label,
    one-sentence semantics in the hover), and the empty-case save refusal (incl. an
    empty case 1). No engine bump — pure addon-state UI (hard rule 4). Tests
    **TE57–TE66** (the PR predated field round 2 and numbered them TE54–TE63; renumbered
    at merge — field round 2 owns TE54–TE56). **Field-test gate:**
    [design/trigger-cases-fieldtest.md](design/trigger-cases-fieldtest.md) — the
    dev→main acceptance list (old rules byte-identical, `| case` fires independently,
    `& case` gates, `/dl why` names the case, old-version drop-with-warn). Did NOT
    regress field iteration 1 (TE45–TE53 still green). **#129 (blueprints) stays
    unlabeled** — the Job Helpers train (#135 PRD, #136–#142) holds the one-label
    pipeline now; queue order between them is Henrik's call.
    Collision watchlist: engine **v128 is TAKEN** (AutoAmmo Range-awareness); addon now
    **`2026.07.29a`**; test ranges CS/TC/TE/TRC/MC/TB/LS*/CMD/NK*/LSP are all taken
    (TE runs through **TE66**).
  - **Both naming decisions CLOSED 2026-07-26**: (1) the `hasCases` guard token stays —
    maintainer sign-off (camelCase like every condition key; a post-main rename would
    need a player-file migration, so it was decided before promotion, deliberately);
    (2) the slice-1 `/dl why` strings were field-witnessed in Henrik's screenshot and
    survive as designed (`standalone <k=v>` for a lone condition — field round 2's
    canonical legs made that the shape simple rules actually take). The completion PR's
    "open Henrik decisions" flag predated this closure — nothing is owed there.
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
  three-icon nudge (fetch / other-bags / `!box store` — **one click, no confirm since
  `2026.08.01g`**: dumping your haul on reaching town is the ordinary move), quiver and
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
  **2026-07-28 (`u`), on `dev`, FIELD-CONFIRMED same day:** those same four hobbies now
  carry the SAME on/off pill in the Gear Helpers **Status** column (Henrik: *"on or off
  slider, same as hobby, only one can be active"*) — one row per hobby, all four visible
  at once. It drives the new `idleexcl.setOn(key, on)`, which routes through the watchers,
  so the lock and its chat refusal are unchanged; the coverage sentence the column used to
  print moved into the pill's hover. The other five rows (Elemental Staff / Obi / Oneiros
  Grip / Ammo / MaxMP, plus E-Box Restock on CW) keep their status sentence untouched.
  Field read: flipping either surface moves the other. There is **no listener** — every
  surface re-reads the watcher's live state each frame, which is why they cannot drift.
  A new hobby surface must read live too; never cache an armed flag.

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
  throttle (one-in-flight, global min-gap, near-box gate, per-category coalesced). **The
  near-box gate covers traffic nobody clicked for — the automatic counting — plus withdrawals;
  SEARCH is exempt since 2026-07-28** (trove searches from anywhere in the field; see the v2
  grill's §B1 revision and `eboxclient.search`). Full spec:
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
