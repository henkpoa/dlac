# Architecture review — 2026-07-25 (PARKED, awaiting Henrik's pick)

> **Status: parked mid-skill.** `/improve-codebase-architecture` ran through step 2 (explore +
> present candidates). Step 3 — the `/grilling` loop on a chosen candidate — has **not** started.
> Nothing in the codebase was changed. This file exists so the next session can resume without
> re-running the exploration.
>
> **The one open question for Henrik: which candidate do we grill first?**
> My recommendation is **#2 (Statefile write half)**; the biggest long-term prize is **#1**.

Base: `main` @ 2332088, addon v2026.07.25b. Line anchors are as of that commit — treat them as
anchors, not gospel (the repo moves fast; `docs/architecture.md` carries the same warning).

Companion artifact: the rendered HTML report, `docs/design/architecture-review-2026-07-25.html`
(self-contained, open it in a browser — it carries the before/after diagrams this file summarises).

---

## How this was produced

Five parallel `Explore` agents walked disjoint areas, plus direct verification of every headline
number by me afterwards:

| Agent | Area |
|---|---|
| 1 | `dispatch.lua` (6,115 lines) — sections, exports, twins, statefile reads, claim pipeline |
| 2 | the watcher family + `lib/statefile` + `lib/safewrite` |
| 3 | the UI layer — `gearui`/`triggersui`/`automationsui`/`uihost`, the `deps` table, the shared `ui` table |
| 4 | `tests/run_tests.lua` + `smoke_ui.lua` + the gear pipeline (`gearoracle`, `gearoptim`, `gearimport`) |
| 5 | the hobby feature family + the storage/persistence layer (`profiles.lua`, path composition) |

**Ignore `.claude/worktrees/automation-sections/`** — a stale duplicate checkout that doubles every
`wc -l`/grep result. All five agents were told to skip it; anyone re-running this must too.

---

## The finding under all seven candidates

dlac's **leaves are deep and well tested**. Named explicitly so a future review doesn't propose
breaking them: `dispatch._ensureStateFile`, `arbResolve`/`arbCededAbove`/`arbExplain`/`arbWhyLines`,
`resolveAmmoPlan`, the RSlot family (`reservedDrops`/`trinketRangeDrop`/`trinketWornDisplace`),
`M.jobReady`, `swapWanted`, `engineEquipSet`, `MATCHERS`/`TIER`/`PRETTY_KEY`, `mpPlanLines`,
`equipcore.planSet`, `lib/safewrite`, `lib/entwatch`, `feature/idleexcl`, `feature/digrank`,
`fishcalc`/`digcalc`/`mpbands`, `restockwatch.plan`, `gearimport.compute*`, `profiles.firstRunAction`
/ `planMigration` / `planEngineCopy`, `ui/uihost`, `ui/uistyle`, `ui/itemicons`, `ui/filetex`,
`ui/hobbybar`, `ui/priorityui`'s pure seams, `gearui.renderSlotGrid`, `gearui.tabGuard`,
`gear/modeslibrary` + `gear/blueprintsmodel`, `gear/triggermodel`.

**The compositions that call them are shallow, repetitive, and untested.** The project has felt this
and responded by *widening interfaces* rather than *deepening modules*:

- **105 `M._` exports across 23 files** (33 in `dispatch.lua` alone).
- **67 comments in production source literally say "test seam"** or "exported for the tests".
- **69 of `dispatch.lua`'s 111 exports exist only for tests**; 25 more have no consumer at all.
- **`M.dispatch` — the function every trigger flows through — is called zero times by either test
  file.** So are the 283-line `d3d_present` tick and the 422-line command handler. Every wiring bug
  in the v112–v119 changelog lives in exactly that untested region.

The counter-example is already in the repo: **`equipcore.planSet(set, snapshot)`** takes a plain-table
world and returns a plan. It needs no seams, and its tests (EQC\*) are the least-stubbed in the suite.
Same shape: `gearimport.compute{Fixes,Dedupe,Prune}(text, data) -> (text, report)`, and the
`configure(deps)` pattern in `automationsui`/`geareffects`/`gearfmt`.

**Each candidate below moves one composition toward that shape.**

---

## The seven candidates

### 1 — Make a claimant a row, like a condition already is · **Strong**

**Files:** `dispatch.lua` — `M.dispatch` 4148-4579 · `ARB_ORDER_DEFAULT` 2590 · overlay blocks
3281-3467 · `resolveVirtual` 1221-1388 · `/dl prio` 5759

**Problem.** Adding a *claimant* costs **15 diff hunks / +108 lines** in `dispatch.lua` across 6
non-adjacent regions. Adding a *condition* to the same file costs **5 hunks / +39 lines**, three of
them registry rows. Both measured:

```
git show 3e95959 -- dispatch.lua    # Chocobo claimant, v120 → 15 hunks, +108 −9
git show a7b350a -- dispatch.lua    # weatherMatch condition, v121 → 5 hunks, +39 −2
```

The 14 logical edit sites (line anchors current):

| # | anchor | edit |
|---|---|---|
| 1 | 52 | `M.VERSION` bump + changelog paragraph (engine handshake — mandatory) |
| 2 | 1330 | `resolveVirtual` branch (4th copy of the same ladder walk) |
| 3 | 2590 | `ARB_ORDER_DEFAULT` rank row |
| 4 | 2599 | `arbOrder` fix (adding the 4th claimant *exposed a latent bug* here) |
| 5 | 3435 | cache + `ensureXState` + `X_OVERLAY_SLOTS` + `xStateActive` + `xOverlayFor` + 2 test seams |
| 6 | 4203 | `ensureXState()` + `xStateActive()` call |
| 7 | **4222** | **composite bail #1** — add `and not xOn` |
| 8 | 4254 | `xEquip = xOn and xOverlayFor(...)` |
| 9 | 4309 | `claims['X'] = xEquip` |
| 10 | **4339** | **composite bail #2** — add `and xEquip == nil` |
| 11 | 4384 | `xSig` retrace-signature block (6th copy) |
| 12 | **4400** | **the `sig` concat string** |
| 13 | 4517 | `applyClaim['X']` closure (6th copy) |
| 14 | 5759 + 5777 | `/dl prio` re-read + status row |

Rows 7, 10, 12 **fail silently** when forgotten — a missed bail is a claimant that never applies; a
missed concat is a stale `/dl why` trace.

**Solution.** One `CLAIMANTS` table — `{ name, stateFile, active(st), overlayFor(st, ctx), slots }` —
that the ensure loop, both bails, the claims map, the signature and the `applyClaim` walk all iterate,
exactly as `MATCHERS`/`TIER`/`PRETTY_KEY` already do for conditions.

**Wins.** 15 hunks → 1 row · six copied shapes deleted · the silent-bail class ends · precedence
becomes one readable table · `M.dispatch` becomes drivable in tests · seven `_xOverlayFor` test seams
retire.

**ADR:** *delivers* ADR 0012, doesn't contradict it. The registry comment at `dispatch.lua:2718-2722`
already promises a new claimant costs "exactly TWO things and NO new arm". The Arbiter part genuinely
*is* 3 edits; the other 11 are the surrounding bookkeeping this candidate absorbs.

> #### 2026-07-27 — Henrik has raised the ceiling on this candidate. READ BEFORE GRILLING #1.
>
> After the multi-slot dominance work (engine v135), Henrik asked for something **larger than the
> registry refactor described above**, and explicitly parked it for a dedicated session rather than
> letting it be decided on a whim: *"I feel like utils.BuildDynamicSets are very legacy… I feel like
> just having one point where gears are built is very limiting. The Claim Arbiter really has a
> central role, and I'd like for it to be able to talk back to the functions that call it so it's
> just not a one way communication, and that sets can be changed on the fly."*
>
> **The diagnosis this candidate should absorb: `utils.BuildDynamicSets` is EARLY BINDING.** It
> collapses each slot's ladder to one name (`utils.lua:554`) using only level / subjob / mode — the
> least information anyone in the pipeline will ever have. It cannot know which triggers matched,
> which priority won a slot, what is worn, what reserves what, or what the Arbiter concluded. Every
> later pass is therefore left with a single name, so its only available move is **veto** — and a
> veto is terminal. Two shipped bugs are the same root:
> * **AutoAmmo v134** — "the overlay COLLAPSES A LADDER TO ONE NAME before the equip layer sees it,
>   so there is no rung 2 to fall to"; the failure was total and silent.
> * **Dominance v135** — an ineligible Royal Cloak leaves Body **unwritten** instead of falling to
>   the next Body piece, which is the one part of Henrik's ruling that could not be built.
>
> That is also *why* the Arbiter is one-way: by the time it speaks, the alternatives are gone, so
> there is nobody left to answer. #1 as written above only makes the existing one-way contract
> cheaper to add to. The upgraded contract to grill:
>
> ```lua
> -- today:    one-way, one name, decided long before anyone can object
> overlayFor(state, ctx)            -> { Body = 'Kupo Suit' }
> -- proposed: the claimant can be asked again, and told why
> propose(ctx, slot, refusedSoFar)  -> candidate | nil
> refuse(slot, candidate, reason)      -- 'reserved-by' | 'pair' | 'locked' | 'level' | ...
> ```
>
> The resolve becomes a bounded negotiation over a deterministic slot walk (the `RSLOT_ORDER` law):
> highest-ranked claimant proposes, constraints validate, a refusal returns **with its reason**, the
> claimant offers its next candidate, loop to a fixed point. Today's post-passes (dominance, the
> Range/Ammo pair law, trinket displacement, sub-slot pairing, locks, disabled) each become a refusal
> reason rather than a veto. "Sets changed on the fly" falls out for free — the collapse happens per
> dispatch against live context instead of being baked at flatten time. `BuildDynamicSets` survives
> as a candidate **filter** (level/subjob/mode is legitimately its job) and stops being a picker.
>
> **Why this is the right place to test it:** the review's own headline finding is that `M.dispatch`
> is called **zero times** by either suite. A pure `negotiate(slots, proposers, constraints) -> plan`
> is exactly the `equipcore.planSet(set, snapshot)` shape praised above, whose tests are the least
> stubbed in the repo. The prize is not only fewer hunks per claimant — it is making the path every
> feature rides testable at all.
>
> **A staging sketch (unvalidated — the grill should challenge it, not inherit it):** (1) carry the
> ladder additively, zero behaviour change; (2) first consumer — v135's ineligible piece falls to its
> next rung, completing the ruling; (3) extract pure `negotiate()`, migrating post-passes into it one
> at a time, each pinned by tests that already exist (AK\*, AKD\*, TR\*, TB\*, AM\*); (4) claimants
> become rows with the proposer contract — #1 delivered; (5) retire the collapse. Stage 4 also gets
> the deferred half of Henrik's ruling for free: dominance across **arbiter rank**, not just trigger
> priority, so a Craft or AutoAmmo claim on a reserved slot makes the reserving piece ineligible by
> the same rule instead of a second copy of it.
>
> Nothing above is built. Stages 1–2 were offered on 07-27 and Henrik declined to start them yet:
> *"this is too central and too big of a decision to just be made on a whim."* **Do not begin any
> stage without his pick.**

**Fix on the way:** `dispatch.lua:4271-4283` does hardcoded Pins-beats-Craft Sub arbitration *before*
the rank walk, contradicting the "single precedence authority" claim 1,700 lines above it.

---

### 2 — Give the Statefile seam its write half · **Strong** · ⭐ recommended first

**Files:** `lib/statefile.lua` (44 lines) · `lib/safewrite.lua` · craft/helm/fish/choco/ammo/pin/arb/restock watchers

**Problem.** The **read** side is deep: `dispatch._ensureStateFile` (`dispatch.lua:408-424`) is 17
lines behind `(cache, filename)`, serves 9 statefiles, owns one corrupt-drop policy, has 10 tests
(SF0–SF9), and its docstring records that it replaced six drifted clones.

The **write** side does not exist as a module:

- **13 hand-rolled serialize→`io.open(p,'wb')`→write→close blocks** across 8 watchers.
- **Only `feature/arbwatch.lua` uses the atomic `lib/safewrite` ladder** (verified: it is the sole
  file in `feature/` that even mentions `safewrite`). The other 12 write the live file directly.
- **13 `xxxPath()` composers**, 13 hand-rolled `loadfile`+`pcall` readers, 8 identical guarded-require
  preambles, and **~24 independent `return {…}` emitters repo-wide**.
- **Zero tests touch any write path.** `run_tests.lua:8395` says why: *"Headless: charDir is nil, so
  every save is a silent no-op."* The `_saveState`/`_charDir` seams exist to **disable** IO, never to
  observe it — there is no filesystem to fake.

So the engine was hardened to survive torn writes while nothing was done to stop *producing* them.

**`lib/statefile.lua` is misnamed.** 44 lines, one function (`charDir()`), which pcall-delegates to
`profiles.dataDir()`. It does not know what a statefile is. Three modules (`gearui:1114`,
`lockstyle:171`, `macrobook:56`) bypass it and hand-roll the same answer anyway.

**Solution.** `statefile.open(name)` → `{ read(), write(tbl) }` — a handle owning the path, one
serializer, the `safewrite` ladder, and an injectable fs for tests.

**Deletion test (the whole case).** Delete `lib/statefile.lua` *today* → 30 lines **move** to 8
callers. Delete the *deepened* one → 13 writers **scatter**. That flip is the signal.

**Wins.** 13 writers → 1 · 13 path composers deleted · torn-write hazard closed · write paths testable
for the first time · one durability guarantee instead of two-by-accident.

**Why first:** addon-state only, no engine `VERSION` bump, no ADR touched, smallest blast radius, and
the project has already proved this exact collapse works on the other side of the same seam.

---

### 3 — Split the optimizer from the weights store · **Strong**

**Files:** `gear/gearoptim.lua` (2,918 lines) → `gearoptim.lua` + new `gear/gearweights.lua`

**Problem.** A pure optimizer and a mutable persisted-preference singleton share one file.
`ensureWeightsLoaded()` is called from **46 sites** including plain accessors, so `M.getWeights()` can
hit the disk. Tests must monkey-patch `optim.weightsPath` and write real files into the repo root
(`tests_tmp_gearweights*.lua`, not in `.gitignore`, leaked on an early `os.exit(1)`).

**The split is already 90% there.** Verified seam at `gearoptim.lua:1347`:

```lua
function M.optimizePicks(pools, weights, opts)
    opts = opts or {};
    weights = weights or activeWeights();      -- ← the seam; make it required
```

| lines | belongs to |
|---|---|
| 378-824, 825-1084 | **store** — per-set binding, slot mask, named profiles, priority mode |
| 2260-2592, 2592-2732 | **store** — `gearweights.lua` IO, cross-character transfer |
| 1320-1689, 1689-2129 | **optimizer** — `optimizePicks` + ladders, already fully pure |

~1,175 of 2,918 lines (40%) move. The two halves share only `canonStat` and a key format.

**Wins.** A getter stops doing file IO · order-dependent AE/AS/AW tests end · no repo-root test
artifacts · optimizer already pure, so its tests are unchanged.

---

### 4 — One storage-home authority · **Strong** (carries two live divergences)

**Problem.** `docs/architecture.md:785-786` claims `profiles.dataDir()`/`charRoot()`/`storageRoot()`/
`charDataDirAt()` are "the ONLY path composers". Grep finds **38 `GetInstallPath` sites in 22 files**.
Nine "ask first, compose a fallback" copies are defensible; the rest never ask at all.

**Two divergences I verified directly against the source:**

1. **`gear/setmanager.lua:42-56`** composes the legacy LAC path with *no* `profiles` delegation, while
   its sibling `gear/gearimport.lua:993-997` asks `prof.charRoot()` first. **Under the Native engine,
   set backups land in the legacy tree and gear backups in the native tree.** Line 505 also does
   `profileDir() .. 'backups\\'` with **no nil guard** — it throws pre-login where every sibling
   returns nil-and-retry.
2. **`feature/debug.lua:153-162`** hardcodes the legacy home; `dispatch.lua:302` `charDir()` prefers
   the mode-aware `dataDir()`. `/dl check` at `dispatch.lua:5731` is **not** `inLac()`-pinned, so in
   native mode the engine writes its half to the native home while the addon-side watcher reads the
   legacy one. (Severity is bounded — `architecture.md` already flags `/dl check` as native-degraded —
   but the cause is this, not the two-state dissolution.)

Same class, lower severity: `check.lua:168`, `macrobook.lua:38/150`, `lockstyle.lua:141`,
`augments.lua:332`, `gearexport.lua:217`, `gearui.lua:756`. Plus **6 copies of addon-install-dir
composition** with no `addonDir()`/`assetPath()` authority at all, and `dispatch.lua:4935`
`string.sub(dir, 1, #dir - 5)` — a path *de*composer hardcoding a trailing `dlac\` the native home
does not have.

**Solution.** Make `profiles` the only module that knows the string `'config\addons\'`; export
`addonDir`/`assetPath` too; every other site takes `nil` as "not logged in yet, retry" instead of
fabricating a legacy path. **The fallbacks are what turn one seam into ten.** A GRD guard can then
hold the line.

---

### 5 — A registry for the windows that outlive the main box · **Worth exploring**

**Files:** `ui/gearui.lua:4546-4724` · `ui/uihost.lua:107-113`

`uihost.renderWindows` exists but is unreachable for these: it is called from inside `drawWindow`,
which early-returns when the main box is shut. So **eight floating windows** (tp float, `_tgMon`,
lockstyle, floatgear, restock nudge, choco search, hobbybar, idlefloat) are wired by hand in
`d3d_present` as near-identical `pcall(require)` → `style.push` → `pcall(render)` → `style.pop` blocks.

**Solution.** `host.registerFloat{name, render}` + `host.renderFloats()` called *outside* `drawWindow`.

**Why it matters now:** `ui/idlefloat.lua` is a floating window with a position write-back and **zero
stack-balance test** — the exact crash class `S50`/`HB1-HB8` exist for (one extra `PopStyleVar` shipped
an `EXCEPTION_ACCESS_VIOLATION` no `pcall` catches).

---

### 6 — Split the shared `ui` table · **Worth exploring**

**Files:** `ui/gearui.lua:107-134` · `gear/syncflags.lua:73-153`

**21 keys declared, 94 in use, 10 modules read/write it** — 78% of keys are created by mutation from
outside the declaration. `_flagsDirty` alone has **11 write sites across 7 modules and 1 reader**
(`gearui.lua:4524`): any module triggers a `uiflags.lua` disk write by setting a boolean. There is no
`markDirty()`. `hobbybar.lua:135` writes the persisted selection *from inside render* — render is not
idempotent, and `smoke_ui.lua:1458` pins that behaviour.

**It is two tables fused:** ~15 persisted preferences (the exact set `syncflags.lua:73-153` already
serializes — the list is written down) and ~79 per-frame scratch keys that each have exactly one
legitimate owner.

**Related budget.** The 200-local cap is the strongest force in this layer and it works — features are
born as modules. But it governs *where code lives*, not *what depends on what*: every extraction
relieved the local count while widening the bundle. `deps` is now 20 keys (no consumer uses more than
60%; panels need 9), `host.services` 38 (one dead — `setLabelOf`; three unpinned by the contract test —
`STATS_W`, `hasCatalog`, `getPlayerInfo`). A companion budget on key count would stop the next
extraction widening them again.

---

### 7 — Collapse the hobby plumbing ring · **Worth exploring**

**Files:** craft/helm/fish/choco watchers · `feature/idleexcl.lua` · `ui/hobbybar.lua` ·
`ui/automationsui.lua` · `ui/gearui.lua` · `ui/priorityui.lua`

Each hobby is ~20-30% real domain math wrapped in ~150 lines of identical plumbing. **Verified: four
`ensureManifestFresh()` copies with a self-documenting clone chain** —

```
feature/craftwatch.lua:432   (original)
feature/helmwatch.lua:200    "-- Manifest freshness (craftwatch.ensureManifestFresh clone)"
feature/fishwatch.lua:152    "-- Manifest freshness (helmwatch clone)"
feature/chocowatch.lua:158   "-- Manifest freshness (fishwatch clone)"
```

Plus 4 copies each of `statePath`/`saveState`/`loadState`/`setEnabled`, 3 near-identical ~60-line
ladder builders in `automationsui`, and the `!ventures` capture subsystem duplicated wholesale between
helm and fish.

**Five hand-maintained rosters of the same four hobbies:** `idleexcl.MEMBERS`, `hobbybar.TABS`
(whose comment literally says *"Tab order = idleexcl.MEMBERS order"* — a comment where a loop would
do), `automationsui`'s Hobbies section keys, `gearui`'s `SWITCH`, `priorityui`'s `live.*` probes.
**A fifth hobby touches 23 sites across 9 files.**

**Solution.** Invert `idleexcl`: watchers **register** rather than being described by a `MEMBERS` table
that re-states their policy (it currently encodes helmwatch's switch model, and goes stale silently if
helmwatch changes). The guard becomes unforgeable instead of opt-in. Everything ordered by hobby reads
that one roster.

**ADR 0017 is not reopened** — one shared bar, one active at a time, lock-while-active all stand. This
is about who owns the list, not what the list means.

---

## Deliberately excluded

**Shrinking `gear/gearoracle.lua`.** It is 65% pass-through — 17 one-line delegations vs 9 real
implementations, a 26-function interface serving ~35 call sites, with 8 exports having exactly one
caller. Tempting, **but ADR 0013 explicitly ruled "FACADE, not absorb"**, and the GRD5 source guard
depends on those delegations existing (it forbids `feature/`+`ui/` from requiring the stat
interpreters, and the allowlist was emptied by #74). The friction is aesthetic, not real. Per the
skill's own rule — only surface an ADR conflict when the friction warrants reopening it — this stays
closed. **Do not re-suggest it without new evidence of real pain.**

---

## Smaller findings worth keeping (not candidates)

Independent of which candidate is picked:

- **GRD guard hole.** `GRD0` (`run_tests.lua:250`) asserts every *listed* file is readable, never the
  inverse. **Six modules are outside the scan and exempt from all five rules:** `ui/chocoui.lua`,
  **`gear/equipcore.lua`**, `feature/engine.lua`, **`feature/equipengine.lua`**,
  `feature/lockstyleapply.lua`, `feature/nativedata.lua`. The two bolded are the *native equip
  pipeline* — the code most likely to grow a private worn-read or bag list. Fix: pin `#ALL` to a count.
- **`feature/nativedata.lua`** (373 lines) has zero test mentions *and* is outside the GRD scan.
- **Render-time work.** `chocoui.bestPerSlot` (`chocoui.lua:41-59`) walks the entire owned-gear list
  **every frame, uncached**, reached from the Automations list render. `gearui` runs two full
  composition evaluations per frame (`:4030`, `:4032`) and 48 `bestByLevel` ladder walks
  (`:3634-3648`).
- **Four copies of "throttled `modestate.lua` read"** — `gearui.lua:1139`, `automationsui.lua:1164`,
  `triggersui.lua:724`/`:768`, and **`priorityui.lua:158-176` which forgot the throttle entirely**
  (runs every frame the Claim Priority section is expanded). A `lib/statemirror` would be a textbook
  deep module.
- **Three copies of the D3DX texture loader** (`craftbar.lua:32`, `helmui.lua:58`,
  `automationsui.lua:1078`) while `ui/filetex.lua` exists to prevent exactly this — blocked only
  because `filetex.handle` hardcodes `assets\%s.png` with no subfolder arg. `filetex` carries the
  hard-won "retain the texture object or imgui draws a dangling pointer" fix in its comment; the three
  copies each re-derived it.
- **Six dead locals** orphaned by the hobbybar window deletion: `isOpen` and the `uistyle` pcall pair
  in `craftbar.lua:23-24,111`, `helmbar.lua:21-22,62`, `fishbar.lua:22-23,181`.
- **`craftbar` is now a shared widget library masquerading as a hobby bar** — `helmbar`, `fishbar` and
  `hobbybar` all `require` the *craft* bar to draw an on/off pill. Belongs in `uistyle` (which already
  hosts `helpLabel`) or a new `ui/widgets.lua`.
- **Five twins held together by comment convention only** (no test): `charDir` (dispatch vs
  `lib/statefile` — and they already differ: dispatch reads `gState` first), `_reqFire`/`_watchFire`,
  the 30/120 debug-ls clamp (3 copies), `_lsStyleGate`/`jobgate.canEquip`, `LS_JOBS`/`jobgate.JOBS`.
  Three others *are* test-pinned (`decodeEquipIndex`, `AMMO_BAGS`, `ANIMATOR_FED`).
- **`M.menuName`** (`dispatch.lua:2222`) carries the comment *"craftwatch reads it…"* — craftwatch
  does not, and never did. Stale comment on a near-stale export.
- **UI modules with zero test coverage:** `ui/helmui.lua` (411 lines, and the only hobby panel with an
  uncached 45-line `coverage()`), `ui/restockui.lua` (523), `ui/idlefloat.lua` (96). Largest untested
  UI module overall: `ui/weightsui.lua` (1,304).
- **`tests/fixtures/keepflow/`** is an empty directory tree — a fixture skeleton with no files.

---

## Resume instructions

1. Open `docs/design/architecture-review-2026-07-25.html` in a browser (or re-read this file).
2. **Ask Henrik which candidate to explore.** Recommendation: **#2**, then **#1**.
3. Run `/grilling` on the chosen candidate — constraints, dependencies, the shape of the deepened
   module, what sits behind the seam, which tests survive.
4. Side effects inline as decisions crystallize (`/domain-modeling`):
   - a deepened module named after a concept not in `CONTEXT.md` → add the term;
   - Henrik rejects a candidate with a load-bearing reason → offer an ADR (next free number: **0020**)
     so future reviews don't re-suggest it.
5. Re-verify line anchors before quoting them — this file is a snapshot of 2332088.

**Nothing is committed and nothing in the addon was modified.** The only new files are this document
and its HTML sibling.
