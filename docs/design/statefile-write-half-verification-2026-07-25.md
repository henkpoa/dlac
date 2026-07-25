{
  "summary": "Verify the architecture review candidate #2 claims against the real code before designing the write half",
  "agentCount": 6,
  "logs": [],
  "result": {
    "design": "## A) VERDICT\n\n**Proceed — but the review's two headline wins are both wrong, and one of them is inverted. Candidate #2 survives as a *path-collapse and testability* move, not as a durability move.**\n\nThree things I measured myself (Windows Lua 5.4, `C:\\Users\\Henrik Johansson\\AppData\\Local\\Programs\\Lua\\bin\\lua.exe`, cwd = addon root):\n\n1. `os.rename('b','a')` where `a` exists → `nil  File exists  17`, target unchanged. Under WSL it succeeds. So `lib/safewrite.lua:77`'s `os.remove(path)` is load-bearing on Windows and **the ladder necessarily creates a window in which the live file does not exist**. `dispatch.lua:415` reads missing as `cache.raw, cache.data = nil, nil` → state OFF. For the 9 engine-polled statefiles the ladder converts a *corrupt-drop* (self-healing, one syscall wide) into a *missing-drop* (also clears `cache.raw`, two syscalls plus a parse wide). **Adopting safewrite universally makes the hazard worse for exactly the file class the review targeted.**\n\n2. **`lib/safewrite.lua:41` writes with `io.open(p, 'w')` — TEXT mode.** All 14 watcher writes use `'wb'`. Measured: `'w'` writes `x\\r\\ny\\r\\n` (6 bytes), `'wb'` writes `x\\ny\\n` (4 bytes). Routing any watcher through `replaceLua` **rewrites every statefile on disk in CRLF on the first save**. Nobody in the five recon reports caught this. It destroys the byte-identical migration proof on day one and silently changes the bytes of 9 files the engine content-compares.\n\n3. The `M._charDir` / `M._saveState` \"test seams\" on all seven watchers are **inert**. Measured: pre-seeded a fake `statefile`, loaded `feature/ammowatch.lua`, wrote once, then reassigned `aw._charDir` to a different directory and wrote again — the *original* path still received the write. Call sites use the local upvalue (`feature/ammowatch.lua:43` exports, `:54` and `:178` call the local). A test plan built on them passes for the wrong reason.\n\n**Re-aimed proposal.** The honest deliverable is: 13 path composers + 4 `charDir` copies collapse to one handle; the write glue becomes injectable and observable for the first time; durability becomes a **per-file-class opt-in that defaults OFF** (byte-identical to today), applied afterward to exactly the two files that want it (`restock.lua`, `ammostate.lua` — irreplaceable user-authored config with no self-heal). Do **not** sell this as a torn-write fix.\n\nIt is still the right first move — it is addon-side only, has no engine `VERSION` bump, and it is the prerequisite for every other write-side cleanup. But one prerequisite jumps ahead of it: `profiles.charIdentity` (`profiles.lua:57-71`) accepts `id == 0` while four of the hand-rolled copies it replaced guard against it. Centralizing more writers onto `dataDir()` **concentrates** that gap. That guard lands first, on its own.\n\n---\n\n## B) CORRECTIONS\n\n**Would have broken the build:**\n\n| # | Review said | Actually | Design consequence |\n|---|---|---|---|\n| 1 | \"torn-write hazard closed\" | `os.rename` over an existing file fails on Windows (measured). `safewrite` removes first; `dispatch.lua:415` treats missing as state OFF. | Atomicity is **opt-in, default off**. Engine-polled mirrors stay tier 0. Delete \"torn-write hazard closed\" from the pitch. |\n| 2 | (unstated) safewrite is a drop-in for the watcher writes | safewrite writes `'w'`; watchers write `'wb'` (measured 6 vs 4 bytes). | `safewrite.replaceLua` gains `opts.binary`; **that lands before any watcher adopts tier 1**, or every statefile flips to CRLF. |\n| 3 | \"`_saveState`/`_charDir` seams exist to disable IO\" | Inert — export-only, callers use locals (measured). | The seams get **deleted**, not reused. The real seam is call-time dir resolution inside the handle. |\n| 4 | `statefile.open(name) -> { read(), write(tbl) }` | `write(tbl)` cannot exist. Five pure byte-pinned serializers would be discarded (`feature/ammowatch.lua:72`, `feature/arbwatch.lua:90`, `feature/lockstyle.lua:252`, `feature/pinwatch.lua:49`, `feature/restockwatch.lua:102`), and six payloads are not serializable tables at all. | **`write(text)`.** This is the single largest correction. |\n| 5 | \"13 writers\", \"the other 12 write directly\" | 14 `'wb'` sites in the 8 watchers + 2 `'ab'` appenders. `feature/arbwatch.lua:140` is a *fallback* branch beside the ladder. | 14 targets; arbwatch's is **deleted**, not migrated; the 2 appenders are explicitly out of scope. |\n\n**Would have mis-scoped the work:**\n\n6. **\"Zero tests touch any write path.\"** False. `tests/run_tests.lua:5212-5264` (SW) drives `safewrite`'s real writes/renames/removes against real files. `tests/smoke_ui.lua` §9 + `tests/goldenfixtures.lua:174-230` write a real manifest through production code and re-read it. AM8 (`tests/run_tests.lua:3491`) is a genuine cross-state contract test. The untested surface is the ~8-line glue per watcher, not \"the write path\". **The win is narrower and more specific: the other 9 writers get the treatment `pinwatch` already has.**\n\n7. **\"an injectable fs for tests.\"** Not this repo's idiom. No test anywhere stubs `io.open`. Four precedents all inject the *directory* and use real disk (`dispatch.lua:303` `_charDirOverride`; SF, AR7, SW, golden). Copy that.\n\n8. **\"Three modules bypass it and hand-roll the same answer\" framed as divergence.** They compute the identical path — `ui/gearui.lua:1114`, `feature/lockstyle.lua:171`, `feature/macrobook.lua:56` are verbatim copies of `lib/statefile.lua:27-42`. Duplication, not a latent bug. Do not promise Henrik a behaviour change here; there is none.\n\n9. **The real divergences are elsewhere and are separate commits:** `feature/check.lua:203` reads `modestate.lua` from the hardcoded legacy home while `dispatch.lua:302` writes it mode-aware — that, not `feature/debug.lua`, is why `/dl check` is native-degraded. `gear/setmanager.lua:505` backs up dlac-owned profile sets into the legacy LAC tree.\n\n10. **The engine cannot participate.** `dispatch.lua` writes 4 per-character files with its own `charDir` (`:302`) and `writeFile` (`:292`); ADR 0002 forbids it requiring an addon module, and `lib/statefile.lua:9-12` says the split is deliberate. \"One writer\" is honestly \"one writer for the addon half, plus a pinned twin in the engine.\"\n\n11. **`CONTEXT.md:148` is stale** — lists 7 statefiles, the reader serves 9 (`chocostate.lua`, `ammostate.lua` missing). The authority is the `ensureStateFile` call sites.\n\n12. **Only 5 of 14 sites have a pure serializer.** The other 9 build their text inline inside the io block (`feature/craftwatch.lua:131/193/412/590`, `feature/helmwatch.lua:151/310/440`, `feature/fishwatch.lua:111/461`, `feature/chocowatch.lua:120`). Each migration is therefore **two** mechanical steps, not one: extract-serializer (verbatim, byte-identical, testable alone), then adopt-handle.\n\n---\n\n## C) THE DESIGN\n\n`C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac\\lib\\statefile.lua` grows a handle. `charDir()` keeps its current signature and behaviour.\n\n```lua\n-- statefile.open(name, opts) -> handle          (never nil; resolution is deferred)\n--   name : bare filename, e.g. 'ammostate.lua'. NEVER a path.\n--   opts : {\n--     mode   = 'wb' | 'ab',   -- default 'wb'. Binary always; 'ab' = append handle.\n--     tier   = 0 | 1 | 2,     -- default 0. 0 plain, 1 atomic, 2 backup+atomic.\n--     prefix = string,        -- tier 2 only: timestampBackup prefix.\n--     subdir = string,        -- e.g. 'debug\\\\'. Created on first write.\n--   }\n```\n\nThe handle is created at module load (pure, no AshitaCore touch). **The directory is resolved on every call**, never cached — that is what makes it a live seam and what makes pre-login retry work unchanged.\n\n```lua\nh:path()        -> string | nil          -- charDir()..subdir..name, or nil pre-login\nh:write(text)   -> true | nil, err       -- text is written VERBATIM. nil pre-login (no error).\nh:append(text)  -> true | nil, err       -- mode 'ab' handles only; errors on 'wb' handles\nh:read()        -> string | nil          -- raw bytes, mode 'rb'. No parsing.\nh:load()        -> table | nil, err      -- read + (loadstring or load) + pcall; table-or-nil\nh:remove()      -> true | nil\nh:exists()      -> boolean\n```\n\nSemantics, spelled out:\n\n- **`write` takes TEXT, never a table.** Non-negotiable, and it is what lets one interface survive every divergence found: `feature/craftwatch.lua:590`'s hex blob of raw 0x096 bytes; `feature/restockwatch.lua:102`'s `--` comments *inside* the table body; `feature/chocowatch.lua:118`'s deliberate lie (`enabled` written OFF-truthfully while `rankFloor` persists); `feature/ammowatch.lua`'s `special` union field, sorted job keys but a **user-ordered ammo array that must not be sorted**; `feature/pinwatch.lua:57`'s literal `'return { }\\n'`. Callers keep their serializers; the five pure ones and their determinism tests survive untouched.\n- **`write` never debounces, never coalesces, never skips a no-op write, never treats empty as nothing.** `feature/pinwatch.lua:88-101` uses `save()` as a *clear-to-disk*; any of those optimizations resurrects last session's pins at login — the exact bug pins exist to prevent.\n- **`write` returns nil (not an error) pre-login.** Today's `if p == nil then return; end` behaviour, preserved exactly.\n- **`write` never returns the text.** `feature/lockstyle.lua:342` needs the exact bytes it wrote for its content-follow baseline — it already has them (it built them), so `write(text)` composes fine where `write(tbl)` would not.\n- **Mode is always binary.** `'wb'` for statefiles, `'ab'` for captures, `'rb'` for reads. This is what keeps output byte-identical across Windows and WSL and is the single most important guard against the CRLF flip.\n- **`open()` sweeps a stale `<name>.lua.tmp`** on its first successful path resolution. Nothing sweeps them today.\n- **Tier 1/2 route through `safewrite.replaceLua` with `opts.binary = true`** (a new 3-line change threading a mode through `safewrite`'s private `writeFile`). Tier 1 also supplies `origText` from `h:read()` automatically — the manual pre-read at `feature/arbwatch.lua:132-136` disappears. Tier 2 calls `timestampBackup` first.\n- **`load()` is offered but is not the engine's reader.** It replaces the 13 hand-rolled `loadfile`+`pcall` blocks in the watchers. `dispatch._ensureStateFile` stays exactly where it is — it is the *cached, throttled, corrupt-drop* reader for a different Lua state and must not be touched.\n\n### Sites that stay hand-rolled, and why\n\n| Site | Why it does not join |\n|---|---|\n| `dispatch.lua:4768` `saveModeState`, `:4786` `saveFiredState`, `:334` `writeDebugHandoff`, `:1820` `mpWarmNote` | ADR 0002 — the engine requires no addon module. The twin stays. Say so in the ADR rather than pretending completeness. |\n| `feature/helmwatch.lua:501`, `feature/fishwatch.lua:510` (`*_capture.txt`) | `'ab'` free-text captures. They *can* take an `'ab'` handle for the path collapse, but they gain nothing else and must never see tier 1. Migrate for the path only, or leave — see fork 5. |\n| `ui/automationsui.lua:62` (`autogear.lua`) | Deps-injected (`deps.dataDir` → `deps.charBase`), 15 schema versions, engine warns on stale fmt, re-reads itself and queues `/dl triggers reload`. Biggest file, most contracts. Follow-up, not first pass. |\n| `gear/syncflags.lua:94` (`uiflags.lua`) | Dependency-injected `D.writeFileText` from `ui/gearui.lua`. No require edge to migrate; joining breaks the injection contract these deliberately-light UI modules rely on. |\n| `gear/setmanager.lua` job shims (`M.jobPath`) | `profiles.lua:107-109` — LAC-only concepts stay on `charBase()` unconditionally. Moving them puts job files where LuaAshitacast will never look. |\n| `feature/arbwatch.lua:140` | **Deleted**, not migrated. It is the unprotected fallback beside the ladder. |\n| `feature/craftwatch.lua:129` `kiSave` | Takes the handle for the path (it has no composer today — inlined twice) but stays **tier 0 forever**. It runs on `packet_in`, once per 0x055 block, N blocks per zone-in, each preceded by a full sort. Any ladder here costs 4 syscalls + 2 parses × N × every zone, on the packet thread. |\n\n---\n\n## D) MIGRATION ORDER\n\nEvery step is its own commit. Proof column: **BI** = byte-identical on disk, before vs after, same inputs, same process.\n\n**Step 0 — prerequisites (no watcher touched):**\n\n| | Change | Proof |\n|---|---|---|\n| 0a | `profiles.charIdentity` rejects `id == 0` (`profiles.lua:57-71`) | New check; a `<Name>_0\\` orphan becomes impossible. Independent bug fix — do it even if the rest is dropped. |\n| 0b | `safewrite.replaceLua` gains `opts.binary` | SW suite green + a new SW asserting an `'\\n'` payload survives round-trip with no `\\r` on Windows. |\n| 0c | `safewrite.lua:77` gains a one-line comment recording the measured Windows `os.rename` fact | Prevents a future \"simplification\" that stays green on WSL and breaks only in the field. |\n| 0d | Delete the 7 inert `M._charDir`/`M._saveState`/`M._save`/`M._saveCraftState` exports | Suite green (nothing references them). |\n| 0e | `lib/statefile.lua` handle + `M._dirOverride`, no callers yet | New SFW section, real files under `tests\\tmp_sfw\\`. |\n\n**Step 1 — `feature/pinwatch.lua:80` (safest, most representative).** It is the only writer that already has a pure serializer (`M.serialize`, `:49`), an order-stability pin (AM12), a byte-shape pin (AM3, the literal `'return { }\\n'`) **and** a cross-state contract test (AM8, feeding its output into `dispatch._pinOverlayFor`). One write site, no timestamp field. **BI achievable exactly.** If pinwatch is not byte-identical, the design is wrong and we stop.\n\n**Step 2 — `feature/chocowatch.lua:117`.** One site, inline `string.format`. Demonstrates the two-step shape: extract `M._serialize` verbatim (commit A, BI by construction, new pure test), then adopt the handle (commit B, BI). Carries `at = os.time()` → **BI with the `at =` field masked**.\n\n**Step 3 — `feature/restockwatch.lua:158`, `feature/ammowatch.lua:120`.** Both already have pure serializers. Both are irreplaceable user-authored config. These are the two that then get **tier 2** in a *separate* follow-up commit whose diff is one word. **BI at tier 0**; tier 2 changes bytes only by adding a backup file beside them.\n\n**Step 4 — `feature/arbwatch.lua`.** Adopt tier 1 via the handle, **delete the `'wb'` fallback at :140** and the manual `origText` pre-read at `:132-136`. Not BI in mechanism, but BI in output. Its recorded \"no rotated backup\" decision (`:117-119`) is honoured by choosing tier 1, not tier 2.\n\n**Step 5 — `feature/craftwatch.lua` ×4, `feature/fishwatch.lua` ×2.** Bulk. `craftstate.lua` BI-masked (`at`); `keyitems.lua`/`guildpoints.lua` BI exactly; `lastsynth.lua` BI-masked (`wallAt`); `fishstate.lua` BI-masked (`at`); `fishventures.lua` BI exactly.\n\n**Step 6 — `feature/helmwatch.lua` ×3 (riskiest, last).** `helmstate.lua` is reached from three execution contexts — UI setters, `packet_in` 0x034 (`:767`), and a `d3d_present` tick at 4Hz (`:807`, self-throttled to ~1 write/2s at `:636-640`). Highest sustained cost, so any per-write multiplier lands here first. It stays tier 0. BI-masked (`at`, `autoUntil`).\n\n**Where BI is not achievable and what replaces it:** six files embed `os.time()` (`helmstate` ×2, `craftstate`, `chocostate`, `fishstate`, `lastsynth`). The proof there is byte-identical **with the timestamp assignment regex-masked** — no new clock seam required, and the mask is one line in the harness. For `keyitems.lua`, `guildpoints.lua`, `pinstate.lua`, `arbstate.lua`, `ammostate.lua`, `restock.lua`, `helmventures.lua`, `fishventures.lua`, `venturepoints.lua`, BI is exact and unmasked.\n\n---\n\n## E) TEST PLAN\n\n**The seam is path redirection, not a fake filesystem.** No test in this repo stubs `io.open`; four sections already inject a directory and use real disk. New section **SFW** in `tests/run_tests.lua` as an IIFE (main chunk is at 186/200 locals — 14 spare, so it must be an IIFE regardless; that is the convention in 94 other sections), sitting next to SW.\n\n```lua\nstatefile._dirOverride = 'tests\\\\tmp_sfw\\\\';   -- checked INSIDE charDir(), dispatch.lua:303 shape\n```\n\nBecause the handle resolves the directory **on every call**, this works after load — which is exactly what the current inert seams cannot do. The watchers stop capturing `charDir` as a load-time upvalue as part of each migration step, which is the change that makes them testable. (Pre-seeding `package.loaded['dlac\\\\lib\\\\statefile']` before `dofile` also works — I proved it — but it burns a restore-dance per section and is unnecessary once resolution is deferred.)\n\nOne narrow addition beyond path redirection: `statefile._fs = { open =, remove =, rename = }`, defaulting to `io.open`/`os.remove`/`os.rename`, used **only** by `lib/statefile` and threaded into `safewrite` for tier 1/2. Its sole justification is fault injection — real disk cannot make `os.rename` fail on demand.\n\n**What becomes provable that is not provable today:**\n\n1. **On-disk bytes for a given in-memory state, for all 14 writers.** Today 5 serializers are pinned as pure functions and 9 are not pinned at all — the entire text of `helmstate.lua`, `craftstate.lua`, `fishstate.lua`, `chocostate.lua`, `keyitems.lua`, `guildpoints.lua`, `lastsynth.lua`, `helmventures.lua`, `fishventures.lua` has never been asserted.\n2. **The cross-state contract, for all 9 statefiles.** Feed each watcher's real output straight into `dispatch._ensureStateFile` and assert the engine reads what the watcher meant. Today exactly one file has this (AM8, pinwatch). This is the highest-value new test in the plan: it is the class of bug the corrupt-drop policy exists to survive.\n3. **Order-stability under `pairs()` luck, for all 9.** Today only AM12/pinwatch. Instability silently costs a full re-parse of every statefile every second via `dispatch.lua:417`'s raw compare.\n4. **The tier-0 write never makes the path non-existent** — a direct regression guard against someone \"upgrading\" an engine-polled mirror to tier 1 and reintroducing the missing-drop.\n5. **`safewrite`'s two restore branches.** `lib/safewrite.lua:79` and `:84` have **zero** coverage today despite commit 12edbf7 claiming \"including crash-stage restores\". Force `_fs.rename` to return nil, assert `origText` is back on disk. Also fix the latent lie: both branches ignore `writeFile`'s boolean and still append `'; restored'` — assert the message is only emitted when the restore actually succeeded.\n6. **Pre-login is a silent no-op.** Asserted today only by a comment at `tests/run_tests.lua:8575`.\n7. **No `\\r` in any statefile on either platform** — the guard against correction #2 regressing.\n\n**Housekeeping the plan must not repeat:** `tests/fixtures/keepflow/.../lspreview.lua` is rewritten by every suite run with no teardown and flip-flops between 113 bytes (CRLF, Windows) and 109 (LF, WSL). SFW writes only into `tests\\tmp_sfw\\` and removes it at section end. Note the `dlac\\` trap — `root .. 'dlac\\\\x.lua'` is one filename on Linux and a subpath on Windows (`tests/goldenfixtures.lua:179-183`); SFW's names are bare, so it is unaffected, and the handle's `subdir` option is the only place it can bite.\n\n---\n\n## F) FORKS FOR HENRIK\n\n**Real forks — his call.** None of them block; each is a small, late, isolated diff.\n\n1. **Do `restock.lua` and `ammostate.lua` get tier 2 (backup + atomic)?** They are irreplaceable user-authored config with no self-heal, written with the same unprotected `io.open` as the ephemeral mirrors. Everything else stays tier 0. **Recommend yes.** Proceed on the assumption — tier is a one-word change per call site, landing after the collapse, reversible.\n\n2. **Does the ADR claim completeness, given the engine keeps its twin?** ADR 0002 forbids `dispatch.lua` requiring an addon module, so \"13 writers → 1\" is really \"the addon half → 1, plus a pinned twin\". **Recommend stating the twin out loud** and adding a test that asserts the two `charDir` implementations agree on a given identity — they already differ (`dispatch.lua:303` override, `:309-311` gState-first) and are held together by comment convention alone. Proceed.\n\n3. **`gear/setmanager.lua:505` — set backups land in the legacy LAC tree while `gear/gearimport.lua:993` backs up into the native tree.** `profiles.lua:795` says \"legacy files never move: flipping back finds everything where it was\", which argues *for* the pin. **Recommend leaving it and documenting the split.** Out of scope for candidate #2; proceed either way.\n\n4. **Do `helmventures_capture.txt` / `fishventures_capture.txt` move under `<dataDir>\\debug\\`?** His 07-23 rule says per-char debug artifacts go there; these two still append at the char root with no rotation. Moving them changes where he looks during field tests. **Recommend leaving them in place for this pass** (path-collapse only), flagged in the ADR. Proceed.\n\n5. **Does `autogear.lua` join in a follow-up?** It is the biggest producer and the seam's biggest remaining hole, but it is deps-injected in a UI module and carries `AUTO_FMT = 15` with an engine-visible warning. **Recommend a separate ADR after the watcher collapse ships and is field-tested.** Proceed.\n\n**Not forks — I am answering these:** `write(text)` not `write(tbl)` (the divergences make `write(tbl)` impossible). Path-redirection seam, not a fake fs (house idiom, 4 precedents, zero `io.open` stubs). Delete the inert seams rather than converting them (the handle replaces them). `.tmp` sweep on `open()`, yes. `CONTEXT.md:148` glossary corrected from 7 statefiles to 9 in the same change. The count is 14 write sites plus 2 appenders, not 13.\n\n**Needs a field probe, not an opinion.** Two facts would change the tier assignment and I cannot get them headless: (a) how many 0x055 blocks a real zone-in delivers — `base = byte(0x84+1)*512` with CatsEyeXI ids past 2000 suggests 5-7 full rewrites of `keyitems.lua` per zone on the packet thread, which is a coalescing question independent of this work; (b) whether `ashita.fs.rename` (which exists in the wider addon ecosystem alongside `ashita.fs.remove`) overwrites on Windows — if it does, the remove-first window could actually be *closed* rather than merely shortened, and the durability story changes for the better. Neither blocks; both belong in the ADR's open-questions section.",
    "bundle": [
      {
        "key": "writers",
        "result": {
          "summary": "VERDICT ON THE NUMBER: the review's \"13\" is wrong by one — there are **14** hand-rolled serialize→`io.open(…,'wb')`→write→close blocks across the 8 named watchers, plus **2 plain-text `'ab'` APPEND writers in the same files** that the review missed entirely (16 write sites in the watcher family). The related sub-claim \"the other 12 write the live file directly\" is also off by one: 13 write the live file directly, and arbwatch has BOTH a safewrite path AND a hand-rolled `'wb'` fallback (feature/arbwatch.lua:140), so it is not cleanly \"the one that uses the ladder\". \"13 xxxPath() composers\" and \"13 hand-rolled loadfile+pcall readers\" are both EXACTLY right, but only when scoped to the 8 watchers — and they don't line up 1:1 with the writers (keyitems.lua has a writer but no composer; pinstate.lua has a writer and composer but NO reader at all).\n\n=== THE DEFINITIVE TABLE — the 8 watchers (feature/), 14 Lua-table writers + 2 text appenders ===\n\n| # | file:line | function | writes | serializer (verbatim) | trigger | thread/context |\n|---|---|---|---|---|---|---|\n| 1 | feature/craftwatch.lua:129 | `kiSave` | `keyitems.lua` | `f:write('-- dlac key-item mirror (0x055-tracked; permanent unlocks persist across reloads)\\nreturn {' .. table.concat(parts,'') .. '}\\n')`; `parts[#parts+1]=string.format('[%d]=true,',id)` after `table.sort(ids)` | EVERY 0x055 key-item block | **packet_in** (craftwatch.lua:650) |\n| 2 | craftwatch.lua:192 | `gpSave` | `guildpoints.lua` | `f:write('-- dlac guild-points mirror (0x113-tracked)\\nreturn {' .. table.concat(parts,'') .. '}\\n')`; `[%q]=%d,` then `table.sort(parts)` — sorts the FORMATTED STRINGS, not the keys | 0x113 currency packet | **packet_in** (:651) |\n| 3 | craftwatch.lua:411 | `saveCraftState` | `craftstate.lua` | `string.format('return { craft = %q, goal = %q, enabled = %s, at = %d, wait = %d }\\n', …)` — no header, fixed field order | setCraft / setGoal / setEnabled / setWait (:444,459,503,515,523) | command + UI |\n| 4 | craftwatch.lua:589 | `lsSave` | `lastsynth.lua` | `f:write(\"-- dlac last-synth mirror (raw 0x096, hex)\\nreturn { wallAt = \" .. os.time() .. \", raw = '\" .. hex .. \"' }\\n\")` — **HEX BLOB of raw packet bytes** | every outgoing 0x096 synth | **packet_out** (:638-646) |\n| 5 | feature/helmwatch.lua:150 | `saveState` | `helmstate.lua` | `string.format('return { gather = %q, enabled = %s, at = %d, auto = %s, autoUntil = %d, range = %d }\\n', …)` | setters + `proximityStep` + `onEventNum` | UI/command **AND packet_in 0x034 (:767) AND d3d_present @4Hz (:807)** |\n| 6 | helmwatch.lua:309 | `vpSave` | `venturepoints.lua` | `parts = { '-- dlac venture-points mirror (0x1A4 GET_POINTS-tracked)\\nreturn {\\n' }` … nested `    [%q] = {\\n` (groups `table.sort`ed) / `        [%q] = %d,\\n` (labels `table.sort`ed) | 0x1A4 points commit | **packet_in** (:752, packet is `e.blocked`) |\n| 7 | helmwatch.lua:439 | `ventSave` | `helmventures.lua` | `'-- dlac ventures mirror (0x017-captured, keyword-bucketed)\\nreturn {\\n'` + `day = %d,` + `general` array + `cats` keyed by `M.ORDER` (deterministic by constant, NOT sorted) | 0x017 chat inside `!ventures` window | **packet_in** (:768) |\n| 8 | helmwatch.lua:501 | `M.onChatLine` | `helmventures_capture.txt` | **NOT LUA, `'ab'` APPEND**: `f:write(string.format('%s  type=%d  sender=%s  |  %s\\n', os.date('%Y-%m-%d %H:%M:%S'), …))` | same 0x017 window | **packet_in** |\n| 9 | feature/fishwatch.lua:110 | `saveState` | `fishstate.lua` | `string.format('return { enabled = %s, at = %d, target = %d, targetName = %q, rod = %q, bait = %q,' .. ' rodId = %d, baitId = %d, rodPin = %s, baitPin = %s }\\n', …)` | setters + `revalidate` | UI/command + **d3d_present bag heartbeat @0.5Hz (:580)** |\n| 10 | fishwatch.lua:460 | `ventSave` | `fishventures.lua` | `'-- dlac fishing ventures mirror (0x017-captured)\\nreturn {\\n'` + `day` + `lines` + `general` | 0x017 window | **packet_in** |\n| 11 | fishwatch.lua:510 | `M.onChatLine` | `fishventures_capture.txt` | **NOT LUA, `'ab'` APPEND** (same shape as #8) | 0x017 window | **packet_in** |\n| 12 | feature/ammowatch.lua:120 | `saveState` | `ammostate.lua` | `f:write(M._serialize(M.jobsData))`; pure `M._serialize` at :73 — 3-line comment header, `fmt = 2`, `table.sort(jk)` on job keys, per-entry `{ name = %q, id = %d, type = %q, level = %d, ranged = %s, ws = %s, special = %s }` where `special` is `false` OR `{ unlimited = true, … }` | 14 GUI mutators + fmt-1 migration | UI/command |\n| 13 | feature/chocowatch.lua:117 | `saveState` | `chocostate.lua` | `string.format('return { enabled = %s, at = %d, rankManual = %d, rankFloor = %d }\\n', …)` | setters + one-way rank ratchet | UI/command + **text_in** pump (`-- Main-thread text only`, :440) |\n| 14 | feature/pinwatch.lua:80 | `save` | `pinstate.lua` | `f:write(M.serialize(M.pins))`; pure `M.serialize` at :48 — NO header, `table.sort(slots)`, empty case returns the literal `'return { }\\n'`, rows `  [%q] = { item = %q, scope = %s },` | 4 mutators + `loadPinState` CLEAR | UI + **d3d_present render hook** (gearui:4536), once per char-dir |\n| 15 | feature/restockwatch.lua:158 | `saveState` | `restock.lua` | `f:write(M._serialize({ master = …, showNudge = …, onlyWhenNeeded = …, character = …, jobs = … }))`; pure `M._serialize` at :102 — 2-line header, `fmt = 1`, **inline `--` comments INSIDE the table body**, `table.sort(jk)` | 6 GUI mutators | UI |\n| 16 | feature/arbwatch.lua:140 | `M.setOrder` **fallback branch** | `arbstate.lua` | `M.serialize(order)` (:92) → `'return { order = { ' .. table.concat(parts, ', ') .. ' } }\\n'` | priority drag/arrows (ui/priorityui.lua:225) | UI. **PRIMARY path is `safewrite.replaceLua(p, text, { origText = orig })` at :137** |\n\n=== ENGINE-SIDE WRITERS (dispatch.lua, LAC Lua state) ===\n| dispatch.lua:4768 (`saveModeState`, def :4746) | `modestate.lua` via `writeFile(p,'w')` | `'-- dlac mode state (dlac-owned; read back on engine load, GUI reads for display)\\nreturn { ' .. table.concat(parts,' ') .. ' }\\n'`; `[\"__version\"] = M.VERSION`, `[\"__job\"]`, `[\"__at\"] = os.time()`, `[\"__loadstamp\"]`, `[\"__locks\"] = { … }` (`table.sort(lk)`), then modes, all under `table.sort(parts)` on FORMATTED STRINGS | 7 call sites incl. the 0.4s tick (:5472) | read back by itself (:4794) AND by 5 addon modules |\n| dispatch.lua:4786 (`saveFiredState`) | `firedstate.lua` | `'-- dlac fired-trigger mirror (GUI display only)\\nreturn { ' .. table.concat(q,' ') .. ' }\\n'` — an ARRAY of ≤5 `%q,` strings, not a keyed table | coalesced flush from the **0.4s dispatch tick** when `_firedDirty` (:5684) | read only by ui/triggersui.lua:775 |\n| dispatch.lua:334 (`writeDebugHandoff`) | `debug-<topic>-engine.txt` `'wb'` | **NOT A LUA TABLE**: `f:write(tostring(os.time()) .. '\\n' .. table.concat(lines,'\\n') .. '\\n')` | `/dl debug` window close | LAC state |\n| dispatch.lua:1820 (`mpWarmNote`) | `debug\\mpwarm.txt` | plain text, **mode is `_mpWarm.opened and 'a' or 'w'` — APPEND after the first line**, capped at 150 lines | MaxMP warm-up trace | tick |\n\n=== GUI / GEAR WRITERS ===\n| ui/automationsui.lua:62 `writeFileText` ← `autoCommit` (:858) | **`autogear.lua`** — the biggest engine-read file, `AUTO_FMT = 15`, multi-hundred-line manifest, every sub-map key `table.sort`ed (`hbKeys`, `fbKeys`, `chbKeys`, …) | regenerated on **every login/job change** via gearui's sync hook (gearui:4481) and on every automation flag toggle | READ BY THE ENGINE (dispatch:1098) and by helmwatch:694 |\n| gear/syncflags.lua:94 `saveUiFlags` → `uiflags.lua` via injected `D.writeFileText` (= ui/gearui.lua:1093) | one-line 17-field `return { debug = %s, autosync = %s, viewids = %s, buildmax = %s, tgmon = %s, tpfloat = %s, tpx = %d, tpy = %d, gearfloat = %s, gfx = %d, gfy = %d, gfscale = %.2f, ifx = %d, ify = %d, openui = %q, showall = %s }\\n` | render loop via `ui._flagsDirty` (gearui:4524) |\n| feature/lockstyle.lua:336 `save` → `lockstyles.lua` (`M._serialize`); also resets `dataRaw` as the content-follow baseline |\n| feature/lockstyle.lua:760 `retireLegacyPreview` → `lspreview.lua`, literal one-shot text |\n| feature/macrobook.lua:101 `save` → `macrobooks.lua`, 2-line header, `table.sort(jobs)`, `    %s = { book = %d, set = %d },` |\n| feature/augments.lua:385 → `dumpPath()`, **`#`-prefixed report lines, not a Lua table** |\n| gear/gearoptim.lua:2513 `writeTextFile` ← `saveWeights` → `gearweights.lua`, all key sets sorted |\n| gear/setmanager.lua:36 `writeFile` → `<JOB>.lua` sets, guarded by `backupWithRotation(text, job, 20)` (:503) — its own keep-newest-20 policy, deliberately NOT in safewrite |\n| ui/triggersui.lua:86 `writeFileText` → `triggers\\<JOB>.lua` (:456), blueprints (:543), mode library (:3074); the safewrite ladder is used at :522 and :3054 |\n| gear/gearimport.lua:845/985 → `gear.lua` via `safewrite.replaceLua` with a sandbox `validate` |\n| gear/gearexport.lua:251 · profiles.lua:172 (`setNativeMode`, with `os.execute mkdir` retry) / :268 / :1562 (`writeFileB`, byte-verified tree copy) · feature/debug.lua:202 (`'a'` append) / :223 / :246 · dlac.lua:41 / :107 / :327 |\n\n=== READ SIDE ===\nTHE ONE deep reader: `dispatch.lua:408 ensureStateFile(cache, filename)` — `readFile`+`(loadstring or load)(raw,'@'..filename)`+`pcall`, throttled to 1 disk check/sec, raw-text compare short-circuit, corrupt→DROP policy. Serves 9 files: `autogear.lua` (:1098), `accstate.lua` (:2247), `craftstate.lua` (:3289), `helmstate.lua` (:3319), `fishstate.lua` (:3375), `chocostate.lua` (:3435), `ammostate.lua` (:3529), `pinstate.lua` (:3871), `arbstate.lua` (:3878).\nHand-rolled `loadfile`+`pcall` readers — 13 in the 8 watchers: ammowatch:183 · arbwatch:108 · chocowatch:137 · craftwatch:107 (kiLoad) / :203 (gpLoad) / :426 (loadCraftState) / :602 (lsLoad) · fishwatch:129 / :470 · helmwatch:165 / :319 / :449. Plus helmwatch:694 (cross-reads `autogear.lua`) and restockwatch:147. Elsewhere: dispatch:4794 (`modestate.lua`) / :4942 (triggers `<JOB>.lua`) · dlac.lua:77 / :164 · feature/check.lua:203 · feature/lockstyle.lua:237 · feature/macrobook.lua:76 · gear/gearimport.lua:855 · gear/gearoptim.lua:2546 / :2609 · gear/profilesets.lua:37 · gear/syncflags.lua:119 · profiles.lua:345 / :1325 · ui/automationsui.lua:145 / :1176 · ui/gearui.lua:758 / :1147 · ui/priorityui.lua:166 · ui/triggersui.lua:732 / :775.\n`xxxPath()` composers — 13 in the 8 watchers: ammowatch:53 `statePath` · arbwatch:81 `arbStatePath` (+ `M._path` seam :84) · chocowatch:109 `statePath` · craftwatch:185 `gpPath` / :403 `craftStatePath` / :583 `lsPath` · fishwatch:102 `statePath` / :449 `ventPath` · helmwatch:142 `statePath` / :290 `vpPath` / :421 `ventPath` · pinwatch:40 `pinStatePath` · restockwatch:47 `statePath`. **`keyitems.lua` has NO composer** — inlined at craftwatch:107 and :129. Outside the watchers: feature/augments.lua:318 · feature/lockstyle.lua:181 · feature/macrobook.lua:66 · ui/automationsui.lua:130 `autoPath` · gear/syncflags.lua:53 `uiFlagsPath` · gear/gearoptim.lua:2283 `weightsPath` · gear/setmanager.lua:56 `M.jobPath` · dispatch.lua:428 `triggersPath` — 21 total repo-wide.\ncharDir duplication: `lib/statefile.lua:27 M.charDir` (the one addon copy, 44-line module) vs 5 independent re-implementations: dispatch.lua:302 `charDir` (+`M._charDirOverride`), feature/lockstyle.lua:171 `dataDir`, feature/macrobook.lua:56 `dataDir`, ui/gearui.lua `dataDir`/`charBase`, gear/setmanager.lua:40 `profileDir`.",
          "verified": [
            {
              "claim": "The read side is deep: dispatch._ensureStateFile is one reader behind (cache, filename), throttled 1/sec, with a single corrupt-drop policy, serving 9 statefiles",
              "evidence": "dispatch.lua:408-424 (def, `if now == cache.lastCheck then return cache.data; end`, `if chunk == nil then cache.data = nil; return nil; end`); consumers at dispatch.lua:1098, 2247, 3289, 3319, 3375, 3435, 3529, 3871, 3878"
            },
            {
              "claim": "13 hand-rolled loadfile+pcall readers",
              "evidence": "ammowatch:183, arbwatch:108, chocowatch:137, craftwatch:107/203/426/602, fishwatch:129/470, helmwatch:165/319/449 — exactly 13 own-statefile readers in the 8 watchers"
            },
            {
              "claim": "13 xxxPath() composers",
              "evidence": "ammowatch:53, arbwatch:81, chocowatch:109, craftwatch:185/403/583, fishwatch:102/449, helmwatch:142/290/421, pinwatch:40, restockwatch:47 — exactly 13"
            },
            {
              "claim": "lib/statefile.lua is 44 lines with one function charDir() that pcall-delegates to profiles.dataDir()",
              "evidence": "lib/statefile.lua:1-44; `function M.charDir()` at :27, `local ok, prof = pcall(require, 'dlac\\\\profiles')` at :28"
            },
            {
              "claim": "Three modules bypass lib/statefile and hand-roll the same answer",
              "evidence": "feature/lockstyle.lua:171 `local function dataDir()`, feature/macrobook.lua:56 `local function dataDir()`, gear/syncflags.lua:53 `uiFlagsPath` via injected D.charBase — and dispatch.lua:302 + gear/setmanager.lua:40 make five, not three"
            },
            {
              "claim": "~24 independent `return {…}` emitters repo-wide",
              "evidence": "26 emitter sites counted outside tests/: dispatch:4628, ammowatch:77, arbwatch:97, chocowatch:120, craftwatch:131/193/412/590, fishwatch:112, helmwatch:151, lockstyle:258/762, macrobook:90, pinwatch:57/58, restockwatch:107, blueprintsmodel:316, gearimport:804/1046, gearoptim:2410, groupimport:72, modeslibrary:433, syncflags:94, profiles:171/1023, automationsui:686"
            },
            {
              "claim": "arbwatch is the only file in feature/ that mentions safewrite",
              "evidence": "grep -rn safewrite feature/ → only feature/arbwatch.lua:120,121,131,137"
            },
            {
              "claim": "Tests disable IO rather than observe it; the io block is untested",
              "evidence": "tests/run_tests.lua:8575 `--     Headless: charDir is nil, so every save is a silent no-op -- the` / :8576 `--     in-memory jobsData is what's under test.`"
            },
            {
              "claim": "The engine's corrupt-drop policy was hardened because a torn write once glued a stale overlay on forever",
              "evidence": "dispatch.lua:395-407 comment block: `a torn/corrupt write DROPS the state -- cache.raw is already the corrupt text, so keeping the last good table would glue it on forever ... not even the watcher's clear-on-load`"
            }
          ],
          "corrections": [
            {
              "reviewSaid": "13 hand-rolled serialize→io.open(p,'wb')→write→close blocks across 8 watchers",
              "actually": "14 such blocks across the 8 watchers (craft 4, helm 3, fish 2, ammo 1, choco 1, pin 1, restock 1, arb 1). Plus 2 more write sites in the same files that are NOT Lua-table writers at all.",
              "evidence": "grep io.open(...,'wb') feature/*.lua returns 16 hits; 2 belong to feature/debug.lua (not a watcher). Watcher hits: craftwatch:129,192,411,589 · helmwatch:150,309,439 · fishwatch:110,460 · ammowatch:120 · chocowatch:117 · pinwatch:80 · restockwatch:158 · arbwatch:140",
              "impact": "A statefile.write(tbl) collapse has 14 targets, not 13 — and one of the 14 (arbwatch:140) is a fallback that should be DELETED rather than migrated, since the safewrite path at :137 already does the right thing. Sizing the work off 13 also silently drops the two append writers from the plan."
            },
            {
              "reviewSaid": "Only feature/arbwatch.lua uses the atomic lib/safewrite ladder. The other 12 write the live file directly.",
              "actually": "13 write the live file directly, and arbwatch is not cleanly 'the safe one' — it carries a hand-rolled unprotected `io.open(p,'wb')` fallback branch that runs whenever `require('dlac\\\\lib\\\\safewrite')` fails.",
              "evidence": "feature/arbwatch.lua:131-144: `if hasSafe and type(safewrite.replaceLua) == 'function' then … else pcall(function() local f = io.open(p, 'wb'); … f:write(text); f:close(); ok = true; end) end`",
              "impact": "The 'one file already proves the ladder works' argument is weaker than stated: arbwatch proves the ladder works AND that people still write an unprotected fallback beside it. statefile.write() must own the fallback policy itself so no caller re-invents one."
            },
            {
              "reviewSaid": "Zero tests touch any write path.",
              "actually": "Zero tests touch any io.open BLOCK, but five of the serializers are pure functions with byte-level and determinism tests. The untested surface is exactly the 3-line io wrapper, not the serialization.",
              "evidence": "tests/run_tests.lua:3466/3506-3508 (pinwatch.serialize + sort determinism), :5883/:5893 (arbwatch.serialize exact-string), :8589 (ammowatch._serialize), :8978 (restockwatch._serialize round-trip via loadstring), :7913-7931 (lockstyle._serialize), :4196-4235 (blueprints byte-stable), :11040-11063 (modeslibrary)",
              "impact": "The deepening is cheaper than the review implies — the hard part (deterministic serialization) is already pure and pinned. The seam needed is only `write(path, text)` with the ladder + an injectable fs. Conversely, a write(tbl) API that takes a TABLE instead of TEXT would throw away those existing pure serializers and their tests."
            },
            {
              "reviewSaid": "13 writers → 1 · 13 path composers deleted (implying a 1:1:1 correspondence between writers, composers and readers)",
              "actually": "The three sets do not align. keyitems.lua has a writer and a reader but NO path composer (inlined twice). pinstate.lua has a writer and a composer but NO reader — `loadPinState` is a CLEAR-and-write, by design. arbstate.lua's reader is not a raw reader either: `M.order()` returns a SANITIZED order, never the raw table.",
              "evidence": "craftwatch.lua:107 `loadfile(dir .. 'keyitems.lua')` and :129 `io.open(dir .. 'keyitems.lua', 'wb')` — no composer exists; feature/pinwatch.lua:88-101 `function M.loadPinState() … M.pins = {}; save(); end`; feature/arbwatch.lua:100-116 `function M.order() … return M.sanitize(st); end`",
              "impact": "A handle API `statefile.open(name) -> {read(), write(tbl)}` fits 11 of the 14 but is a bad fit for pinstate (whose 'load' is a write) and arbstate (whose 'read' is a validated projection). Those two need read() to be optional/overridable or they'll be forced through a shape that hides their real contract."
            },
            {
              "reviewSaid": "the write half does not exist as a module (framed as pure duplication with no policy divergence)",
              "actually": "There IS a second, deliberate durability policy already factored elsewhere and explicitly ring-fenced: setmanager's keep-newest-20 rotated backups, which safewrite's own header says is deliberately NOT in safewrite.",
              "evidence": "lib/safewrite.lua:23-28 `DELIBERATELY NOT HERE: setmanager's rotated set backups (keep-newest-20 via backupWithRotation) -- a different, deliberate policy on a different file class, already factored inside setmanager and pinned by its tests.`; gear/setmanager.lua:503 `local function backupWithRotation(srcText, job, maxN, tag)`",
              "impact": "'one durability guarantee instead of two-by-accident' is really THREE tiers (none / atomic-replace / atomic-replace+rotated-backup) and the third is intentional. statefile.write must pick a tier per file class, not one global tier."
            }
          ],
          "divergences": [
            {
              "site": "feature/craftwatch.lua:129 kiSave (keyitems.lua)",
              "whatsSpecial": "Writes the ENTIRE key-item mirror from a packet_in handler, once per 0x055 BLOCK — and a zone-in delivers many blocks (each packet covers 512 ids: `base = byte(0x84+1)*512`). So a single zone produces a burst of full-file rewrites on the network thread, each preceded by a table.sort over every owned key item. This is the one place where an atomic rename ladder (write .tmp → loadfile → os.remove → os.rename → loadfile) would be catastrophically expensive: 4 extra syscalls plus two full parses, times N blocks, times every zone, on the packet thread.",
              "evidence": "feature/craftwatch.lua:137-155 `function M.onKeyItemPacket(data) … local base = (string.byte(data, 0x84 + 1) or 0) * 512; … M.kiBlocksSeen = M.kiBlocksSeen + 1; kiSave(); end`; registered at :650 `ashita.events.register('packet_in', 'dlac-craftwatch-in', …) if e.id == 0x055 then`"
            },
            {
              "site": "feature/craftwatch.lua:589 lsSave (lastsynth.lua)",
              "whatsSpecial": "Not a state table — a HEX BLOB of raw packet bytes plus a wall clock. `os.time()` is embedded, so the file's bytes change on EVERY write even when the content is identical, defeating any raw-compare short-circuit. Its reader hex-decodes back to a packet and replays it through M.onSynth, then DECREMENTS a counter to undo the side effect. A generic write(tbl) would have to be told the value is opaque binary.",
              "evidence": "feature/craftwatch.lua:585-592 `local hex = (M._lastRaw:gsub('.', function(c) return string.format('%02X', c:byte()); end)); … f:write(\"-- dlac last-synth mirror (raw 0x096, hex)\\nreturn { wallAt = \" .. os.time() .. \", raw = '\" .. hex .. \"' }\\n\")`; reader :604-616 `local raw = (t.raw:gsub('%x%x', function(h) return string.char(tonumber(h,16)); end)); … if sk ~= nil and (M.counts[sk] or 0) > 0 then M.counts[sk] = M.counts[sk] - 1; end`"
            },
            {
              "site": "feature/helmwatch.lua:501 and feature/fishwatch.lua:510 (helmventures_capture.txt / fishventures_capture.txt)",
              "whatsSpecial": "The only APPEND writers in the watcher family, and the only non-Lua output there. Mode `'ab'`, timestamped free text, one line per captured chat packet. The review's inventory misses them entirely. A write(tbl) API cannot express them; an atomic rename would destroy them (each append would rewrite the whole growing log). They also sit in packet_in.",
              "evidence": "feature/helmwatch.lua:497-505 `-- Raw mirror ALWAYS (append) -- that file is what pins the real parser` … `local f = io.open(dir .. 'helmventures_capture.txt', 'ab'); … f:write(string.format('%s  type=%d  sender=%s  |  %s\\n', os.date('%Y-%m-%d %H:%M:%S'), …))`; fishwatch.lua:506-514 identical shape"
            },
            {
              "site": "feature/pinwatch.lua:80 save (pinstate.lua)",
              "whatsSpecial": "The ONLY file whose 'load' is a WRITE. `loadPinState` clears the table and immediately saves — it never reads. It is also keyed on the char DIR, not a boolean, so a logout/login re-fires the clearing write. And its determinism is load-bearing for the ENGINE's performance, not for git diffs: the sorted-slot order exists specifically so dispatch's raw-text compare skips the re-parse. Empty state is the literal string `'return { }\\n'`, not `'return {}\\n'` — a byte-shape a naive serializer would silently change.",
              "evidence": "feature/pinwatch.lua:88-101 `function M.loadPinState() … M.pins = {}; save(); end`; :45-47 `-- Slots are emitted in sorted order: a stable file means dispatch's raw-text compare skips the re-parse when nothing actually changed.`; :57 `if #slots == 0 then return 'return { }\\n'; end`"
            },
            {
              "site": "feature/helmwatch.lua:150 saveState (helmstate.lua)",
              "whatsSpecial": "The most-written engine statefile, reached from THREE different execution contexts: the UI/command setters, a packet_in 0x034 handler, and a d3d_present tick at 4Hz. The tick self-throttles to roughly one write per 2s via `(M._autoUntil or 0) < now + 2`, and the file embeds `autoUntil` and `at` (both os.time()), so consecutive writes always differ in bytes. Any per-write cost multiplier lands here first.",
              "evidence": "feature/helmwatch.lua:602-605 `-- Returns true while any point holds us (and keeps the engine hold alive, with sparse state writes -- roughly one per 2s, not one per frame).`; :636-640 `if (M._autoUntil or 0) < now + 2 then M._autoUntil = now + M.AUTO_HOLD_S; M._enabledAt = now; saveState(); end`; registered at :807 with `_proxAt = os.clock() + 0.25`; packet path at :767"
            },
            {
              "site": "feature/restockwatch.lua:158 saveState (restock.lua)",
              "whatsSpecial": "Emits `--` COMMENTS INSIDE the returned table body, interleaved with the fields they document. It is also the only watcher file that is explicitly NOT a statefile (no engine reads it) yet holds pure USER-AUTHORED CONFIG that has no self-healing source — a torn write is unrecoverable data loss, unlike every engine statefile which self-heals from the corrupt-drop policy.",
              "evidence": "feature/restockwatch.lua:102-112 `'-- dlac E-Box Restock config -- written by the GUI (Automations > E-Box Restock).', '-- Per-character; NOT a Statefile (no engine reads it). See docs/design/ebox-restock.md.', 'return {', '    fmt = 1', … '    -- Always-on staples (every job). id/name/ahCat/stack learned at', '    -- add-time from the box SEARCH row; target defaults to one stack.', '    character = {'`"
            },
            {
              "site": "feature/ammowatch.lua:120 saveState (ammostate.lua)",
              "whatsSpecial": "Engine-read AND user-authored: the per-job ammo ladders are hand-built lists the player cannot regenerate, but the file is written with the same unprotected io.open as the ephemeral mirrors. Its `special` field is a UNION (`false` OR a table of three booleans), and the ammo array's order is USER-MEANINGFUL priority — so a generic serializer must not sort it, even though it must sort the job keys.",
              "evidence": "feature/ammowatch.lua:73-108 `M._serialize`: `table.sort(jk)` on job keys only; `local sp = 'false'; if type(e.special) == 'table' then … sp = '{ ' .. table.concat(bits, ', ') .. ' }'; end`; engine reader dispatch.lua:3529"
            },
            {
              "site": "feature/arbwatch.lua:125 M.setOrder (arbstate.lua)",
              "whatsSpecial": "The INVERSION at the heart of the durability story: the ONE file that got the atomic ladder is the one whose own comment says losing it is harmless, while ammostate/restock (irreplaceable user config) got nothing. It also does a manual pre-read of the whole file just to supply `origText` for the restore path — work statefile.write() would have to replicate or drop.",
              "evidence": "feature/arbwatch.lua:117-119 `-- No rotated backup: a lost arbstate self-heals to the default, so the file class does not warrant the set-file backup policy`; :132-137 `local orig = nil; pcall(function() local f = io.open(p, 'r'); if f ~= nil then orig = f:read('*a'); f:close(); end end); ok = (safewrite.replaceLua(p, text, { origText = orig }) == true);`"
            },
            {
              "site": "dispatch.lua:4768 saveModeState (modestate.lua)",
              "whatsSpecial": "Lives in the OTHER Lua state (LAC), is the version HANDSHAKE (`__version = M.VERSION`), and is the only file read back by its own writer AND by five addon-side readers. It sorts FORMATTED STRINGS rather than keys, and embeds `__at = os.time()` so every write differs. It is written from the 0.4s dispatch tick. dispatch.lua cannot require lib/statefile by design — the two states share FILES, not CODE.",
              "evidence": "dispatch.lua:4753-4770 `local parts = { string.format('[\"__version\"] = %d,', M.VERSION) }; … parts[#parts+1] = string.format('[\"__at\"] = %d,', os.time()); … table.sort(parts); writeFile(dir .. 'modestate.lua', …)`; lib/statefile.lua:9-12 `The ENGINE'S half stays dispatch-local on purpose … the two Lua states share the FILES, not the code`; readers at dispatch:4794, check.lua:203, automationsui:1176, gearui:1147, priorityui:166, triggersui:732"
            },
            {
              "site": "dispatch.lua:4786 saveFiredState (firedstate.lua)",
              "whatsSpecial": "An ARRAY of ≤5 display strings, not a keyed table, and the file exists specifically to AVOID riding modestate: the comment says its churn must not bump `modesRev` or the GUI rebuild signal. It is flushed from the 0.4s combat tick, giving it the highest sustained write rate of any per-character file — 2.5 writes/sec during a fight. Torn write is entirely harmless (display only), so paying for atomicity here is pure waste.",
              "evidence": "dispatch.lua:4774-4777 `-- Trigger-monitor mirror (v55): display-only, never read back by the engine. Its own small file, NOT modestate -- fired lines change per action and must not bump modesRev`; :5682-5687 `-- Coalesced trigger-monitor flush: whatever fired since the last pass lands in firedstate.lua as ONE write. if _firedDirty and saveFiredState ~= nil then`"
            },
            {
              "site": "ui/automationsui.lua:62 writeFileText ← autoCommit :858 (autogear.lua)",
              "whatsSpecial": "By far the largest engine-read file and the one with a real BYTE-SHAPE CONTRACT plus a schema version the engine version-checks and warns on. It is regenerated wholesale on every login and job change from the render loop, and on success it immediately re-reads what it wrote and queues a `/dl triggers reload`. This one has a legitimate case for the ladder (a torn manifest costs a visible engine warning) but is also the most expensive to write.",
              "evidence": "ui/automationsui.lua:127 `local AUTO_FMT = 15;` with the full fmtver changelog; :858-862 `if writeFileText(p, table.concat(L, '\\n')) then auto.data = nil; autoLoad(); pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl triggers reload'); end)`; engine warning dispatch.lua:1102 `printwarn('autogear.lua is an old format (staff swapping is OFF) …')`; render-loop driver ui/gearui.lua:4481-4488"
            },
            {
              "site": "gear/syncflags.lua:94 saveUiFlags (uiflags.lua)",
              "whatsSpecial": "The one writer that is explicitly rate-limited by a dirty flag because the render loop would otherwise write it ~60×/sec. It does not use lib/statefile at all — it takes writeFileText by DEPENDENCY INJECTION from gearui, so it has no require edge to migrate. Any collapse either leaves it out or has to break the injection contract.",
              "evidence": "ui/floatgear.lua:596 `-- marking the flags dirty per frame would rewrite uiflags.lua ~60x/sec.`; ui/gearui.lua:4524 `if ui._flagsDirty then ui._flagsDirty = nil; pcall(sf.saveUiFlags); end`; gear/syncflags.lua:94 `D.writeFileText(p, string.format('return { debug = %s, …'`"
            },
            {
              "site": "feature/lockstyle.lua:336 save (lockstyles.lua)",
              "whatsSpecial": "Its write is part of a CONTENT-FOLLOW protocol: after writing it stamps `dataRaw = text` so its own 1s file-watcher does not mistake the save for an external edit. A statefile.write() that returns only a boolean would break that — the caller needs the exact text it wrote. It also switches destination between a per-job profile path and a legacy global path, and filters the payload accordingly.",
              "evidence": "feature/lockstyle.lua:320-343 `local d = perJob and M._entryData(data, dataJob) or data; … f:write(text); f:close(); -- Our own write is the content-follow's new baseline (load_): without this, every Save would read as an external change. dataRaw = text;`"
            },
            {
              "site": "dispatch.lua:334 writeDebugHandoff / dispatch.lua:1820 mpWarmNote / feature/debug.lua:202,223,246 / dlac.lua:41,107,327",
              "whatsSpecial": "Per-character writes that are NOT Lua tables at all: bridge handoffs (`os.time()` header + bare lines), an APPEND-after-first-write trace (`_mpWarm.opened and 'a' or 'w'`), an appended command-receipt log, and load reports. Two of them (`debug-request.txt`, `debug-<topic>-engine.txt`) are a field-proven cross-Lua-state protocol whose byte shape is parsed by the other state's reader.",
              "evidence": "dispatch.lua:334-337 `local f = io.open(dir .. name, 'wb'); … f:write(tostring(os.time()) .. '\\n' .. table.concat(lines, '\\n') .. '\\n')`; dispatch.lua:1820 `local f = io.open(dir .. 'debug\\\\mpwarm.txt', _mpWarm.opened and 'a' or 'w')`; feature/debug.lua:202 `io.open(d .. 'cmd-receipt.txt', 'a')`; :223 `io.open(base .. 'dlac\\\\debug-request.txt', 'wb')`; dispatch.lua:1798-1804 `The LAC-bridge handoff files (debug-request / debug-*-engine) stay at the char root untouched: their paired readers are field-proven bridge protocol`"
            }
          ],
          "openQuestions": [
            "What is the real 0x055 block count per zone-in? `base = byte(0x84+1) * 512` means each packet covers 512 key-item ids; with CatsEyeXI ids running past 2000 that is 5-7 full rewrites of keyitems.lua per zone, on the packet thread. Measuring this decides whether kiSave can afford ANY ladder, or whether it needs coalescing (dirty-flag + flush on the main-thread tick, the way dispatch already coalesces firedstate) before the seam is even worth building.",
            "Does Ashita v4 run packet_in/packet_out handlers on the network thread? The MEMORY note from the chocobo work says packet-thread work must avoid chat/IO (it crashed dig.lua), yet SEVEN of the 14 watcher writers do full-file IO from packet handlers (craftwatch kiSave/gpSave/lsSave, helmwatch saveState/vpSave/ventSave + capture append, fishwatch ventSave + capture append). If that memory is right, the current code is already living on borrowed time and the deepening is a safety fix, not a tidiness fix — and os.remove+os.rename from that thread would make it strictly worse.",
            "Should statefile.write take a TABLE or TEXT? Five serializers are already pure, tested and byte-pinned (pinwatch.serialize, arbwatch.serialize, ammowatch._serialize, restockwatch._serialize, lockstyle._serialize). A write(tbl) API throws those away and their determinism tests with them; a write(text) API keeps them and only collapses the io block. The review assumes write(tbl) without arguing it.",
            "Which file class gets which durability tier? Today it is inverted: arbstate (self-heals to a default) has the ladder; ammostate and restock.lua (irreplaceable user-authored config with no self-heal) have nothing; firedstate (display-only, 2.5 writes/sec) would get the ladder for free under a blanket policy and pay for it every combat tick. A per-file tier flag (`{ atomic = true }`) seems mandatory, but nothing in the review's proposed `statefile.open(name) -> {read(), write(tbl)}` signature carries it.",
            "Do the 2 append-mode capture writers and the 4 non-Lua debug/bridge writers belong in the same module at all, or is the right shape two modules (statefile for the return-table family, a separate log/append helper)? Folding them in would force the API to grow modes it otherwise does not need.",
            "Can dispatch.lua participate? It writes 4 per-character files (modestate, firedstate, and two debug artifacts) with its OWN charDir (dispatch.lua:302) and its own writeFile (dispatch.lua:292), and lib/statefile.lua:9-12 says the engine half stays dispatch-local ON PURPOSE. If the engine can't require the new module, 'one writer' is really 'one writer for the addon state, plus an untouched twin in the engine' — which is the exact drift condition the seam exists to end.",
            "pinstate.lua and arbstate.lua do not fit the handle shape: pinwatch's load IS a write (loadPinState clears then saves), and arbwatch's read is a sanitizing projection (M.order returns dispatch.arbOrder(st), never the raw table). Does the API make read() optional, or do those two keep hand-rolled halves and undercut the 'delete the deepened one → 13 writers scatter' argument?"
          ]
        }
      },
      {
        "key": "safewrite",
        "result": {
          "summary": "SAFEWRITE IS NOT A DURABILITY LADDER — IT IS A *VALIDATION-AND-RESTORE* LADDER. There is no fsync, no retry, no rotation, and on Windows no atomic swap either.\n\n=== 1. THE MODULE (C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac\\lib\\safewrite.lua, 101 lines, ONE commit ever) ===\nHeader (lines 1-32) declares three verbs — timestampBackup / replaceLua / verifiedMove — and states \"DELIBERATELY NOT HERE: setmanager's rotated set backups ... One adapter is a hypothetical seam; if a third rotated-backup consumer ever appears, lift it then.\" and \"Pure definitions at load (no Ashita/file touches until called)\".\n\nPrivate helpers (36-44):\n  local function readFile(p)  -> io.open(p,'r'); f:read('*a'); f:close()   (nil on any miss)\n  local function writeFile(p,t) -> io.open(p,'w'); f:write(t); f:close(); return true/false\n\nM.timestampBackup(dir, prefix, text)  (48-56)\n  48: if dir == nil or text == nil then return nil, 'bad args'; end\n  50-52: pcall(function() if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(dir); end end);\n  53: local path = dir .. (prefix or '') .. os.date('%Y%m%d_%H%M%S') .. '.lua';\n  54: if not writeFile(path, text) then return nil, 'could not write backup'; end\n  55: return path;\n  NOTE: second-resolution stamp — two backups in the same second SILENTLY OVERWRITE. No rotation, no pruning, ever.\n\nM.replaceLua(path, newText, opts)  (62-88) — the \"ladder\". Seven rungs:\n  R1 arg/parse gate  65: if (loadstring or load)(newText) == nil then return nil, 'result would not parse'; end   -> live file untouched.\n  R2 write temp      66-67: local tmp = path .. '.tmp'; if not writeFile(tmp,newText) then return nil,'could not write temp file'; end  -> live file untouched.\n  R3 loadfile(tmp)   68-69: if chunk == nil then os.remove(tmp); return nil,'temp failed to parse'; end  -> tmp swept, live file untouched.\n  R4 opts.validate   70-76: local vok,verr = opts.validate(chunk, tmp); if not vok then os.remove(tmp); return nil,'would error on load: '..tostring(verr); end  -> tmp swept, live untouched. (chunk is loaded, NOT run — the caller decides whether to run it.)\n  R5 remove target   77: os.remove(path);            <-- RETURN VALUE IGNORED. From here the live file DOES NOT EXIST.\n  R6 rename          78-82: if not os.rename(tmp,path) then if opts.origText ~= nil then writeFile(path,opts.origText); end os.remove(tmp); return nil,'rename failed'..(opts.origText ~= nil and '; restored' or ''); end   <-- restore write's success is IGNORED; the ';restored' suffix is asserted, not verified.\n  R7 post-write      83-86: if loadfile(path) == nil then if opts.origText ~= nil then writeFile(path,opts.origText); end return nil,'post-write check failed'..(...' ; restored'); end\n  88: return true;\n  NO fsync/flush-to-disk anywhere (f:close() only). NO retry at any rung. NO backup — the caller must call timestampBackup first (header line 15: \"The caller does its backup FIRST\").\n\nM.verifiedMove(src, dst)  (92-99)\n  93-94: local t = readFile(src); if t == nil then return nil,'source unreadable', TRUE; end   (3rd return = `missing`)\n  95: if not writeFile(dst,t) then return nil,'copy failed'; end\n  96: if readFile(dst) ~= t then return nil,'copy verify failed'; end     <-- the only read-back verify in the module\n  97: if not os.remove(src) then return nil,'remove failed (copy kept at '..dst..')'; end\n  98: return true;\n\n=== 4. THE TESTS (tests/run_tests.lua:5212-5264, section \"SW\") — quoted in full in the evidence below ===\n15 checks, REAL files under tests\\, no fake filesystem, no injected fs. Seeded at run_tests.lua:17 (`package.loaded['dlac\\\\lib\\\\safewrite'] = dofile('lib/safewrite.lua')`). Whole suite green on Windows right now: I ran it — \"OK -- 3329 checks passed\".\nCoverage: SW1-3 happy path; SW4-5 unparseable refused; SW6-8 validator refusal; SW9 validator receives a runnable chunk; SW10 timestampBackup; SW11-14 verifiedMove incl. the `missing` flag.\nNOT covered: rungs R5/R6/R7 failure — no test makes os.remove or os.rename fail, so BOTH origText restore branches (lines 79 and 84) have never executed in a test. The commit message's claim \"SW0-SW14 exercise the ladder on real files including crash-stage restores\" is not true of the code as it stands.\n\n=== 5. INTERFACE ===\nreplaceLua(path, STRING, opts) — a path and TEXT, never a table. No serializer, no path composition, no charDir knowledge. It also needs opts.origText, which the caller must pre-READ off disk (arbwatch does exactly that at arbwatch.lua:133-136). So `statefile.write(tbl)` cannot forward to it directly: the handle must own (a) a serializer tbl->text, (b) a pre-read for origText, (c) the parse/validate opts. It IS a clean bottom layer for such a handle — it just is not the handle.",
          "verified": [
            {
              "claim": "lib/statefile.lua really is 44 lines with ONE function and no write half — it does not know what a statefile is",
              "evidence": "lib/statefile.lua:1-45 (M.charDir is the only member; `return M` at :44)"
            },
            {
              "claim": "feature/arbwatch.lua is the ONLY file under feature/ that mentions safewrite, and it is the only watcher whose primary write path is the ladder",
              "evidence": "feature/arbwatch.lua:120-137 (require at :120, replaceLua at :137); no other feature/*.lua matches 'safewrite'"
            },
            {
              "claim": "The watcher family writes the live file directly with a hand-rolled 3-line pcall/io dance",
              "evidence": "feature/ammowatch.lua:120, chocowatch.lua:117, craftwatch.lua:129/192/411/589, fishwatch.lua:110/460, helmwatch.lua:150/309/439, pinwatch.lua:80, restockwatch.lua:158"
            },
            {
              "claim": "Zero tests observe any WATCHER write path; the _save/_saveState seams exist to disable IO, not to observe it",
              "evidence": "feature/pinwatch.lua:84 `M._save = save; -- test seam`; feature/ammowatch.lua:124 and restockwatch.lua:164 `M._saveState = saveState; -- test seam`"
            },
            {
              "claim": "The engine reader's policy makes a MISSING file equal to state-off, so any window where the file does not exist is a live drop",
              "evidence": "dispatch.lua:414-415 `local raw = readFile(dir .. filename); if raw == nil then cache.raw, cache.data = nil, nil; return nil; end`"
            },
            {
              "claim": "No ADR governs safewrite; its only doctrine lives in its own header and two architecture.md sentences",
              "evidence": "docs/architecture.md:300 and :384 (the only doc mentions outside history.md and the 07-25 review)"
            }
          ],
          "corrections": [
            {
              "reviewSaid": "\"Only feature/arbwatch.lua uses the atomic lib/safewrite ladder ... The other 12 write the live file directly.\" (architecture-review-2026-07-25.md:134-135)",
              "actually": "Four modules and EIGHT call sites use safewrite today. The review's parenthetical scope (\"the sole file in feature/\") is correct, but the bullet's headline is not — the ladder is already load-bearing in the two biggest user-data writers in the addon.",
              "evidence": "gear/gearimport.lua:29 `local sw = require(\"dlac\\\\lib\\\\safewrite\")` — UNGUARDED require; sites at :1038 (timestampBackup) + :1040 (replaceLua, /dl commit) and :1254 + :1256 (safeReplaceGear, /dl fix). profiles.lua:48 guarded require; sites at :945 and :983 (verifiedMove), with HARD refusal at :916 and :969 `if not _swok then return nil, 'safewrite module unavailable -- deletion refused'`. ui/triggersui.lua:522-533 (Blueprints library bpSave) and :3054-3065 (Mode library mlSave), both timestampBackup + replaceLua with a validate that pcalls the chunk. feature/arbwatch.lua:120-137.",
              "impact": "The ladder is PROVEN in production on gear.lua, the Blueprints library and the Mode library — it is not an unproven one-consumer experiment. That removes the main risk objection to routing statefile.write through it. It also means the collapse must not re-invent an interface: four existing callers already depend on the (path, text, opts) shape."
            },
            {
              "reviewSaid": "Implied throughout candidate 2: adopting the safewrite ladder closes the torn-write hazard (\"torn-write hazard closed\" in the Wins line)",
              "actually": "On Windows it does NOT close it — it changes its shape. os.rename over an EXISTING file FAILS on the user's own Lua, so line 77 deletes the target first and there is a genuine window in which the live file does not exist. dispatch.lua:414 reads a missing file as state-OFF, so a reader landing in that window drops the state exactly as it would on an empty/torn write. The ladder's real wins are the parse/validate rungs and the origText restore, not atomicity.",
              "evidence": "Empirical, this machine, Lua 5.4 at C:\\Users\\Henrik Johansson\\AppData\\Local\\Programs\\Lua\\bin\\lua: `os.rename('b.txt','a.txt')` over an existing a.txt -> `nil  File exists  17`, content unchanged. Same probe under WSL lua5.4: `true`, target overwritten. safewrite.lua:77-78 `os.remove(path); if not os.rename(tmp, path) then`.",
              "impact": "Sell the collapse on validation + restore + one testable write seam, not on atomicity. If true atomicity is wanted on Windows it needs MoveFileEx/ReplaceFile, which Lua's os.rename does not use and which the addon has no binding for (only ashita.fs.create_directory and ashita.fs.get_dir are used anywhere in the tree)."
            },
            {
              "reviewSaid": "Nothing in the review flags it, and safewrite's own header narrates the sequence as \"remove target -> rename tmp in\" as if it were incidental ordering",
              "actually": "That os.remove is the single most platform-critical line in the module and NOTHING records why. On Linux rename() silently overwrites, so deleting line 77 as a 'simplification' would keep the WSL/CI suite fully green and break only in the field on Windows — the exact inversion of the usual Windows-green-vs-CI-green trap in this repo.",
              "evidence": "safewrite.lua:13-14 header text `remove target -> rename tmp in`; no occurrence of 'Windows', 'File exists', or any rename rationale anywhere in the repo (grep over *.lua and docs/). The two probes above prove the divergence.",
              "impact": "Whatever gets built on top of safewrite, add (a) a one-line comment at :77 recording the field fact, and (b) an SW test that asserts replaceLua succeeds when the target ALREADY EXISTS and is non-empty (SW1 does cover this incidentally — make the intent explicit so no one deletes the remove)."
            },
            {
              "reviewSaid": "Commit 12edbf7: \"SW0-SW14 exercise the ladder on real files including crash-stage restores.\"",
              "actually": "No test reaches either restore branch. Nothing forces os.rename or the post-write loadfile to fail, so lines 79 and 84 (`writeFile(path, opts.origText)`) have zero coverage. Worse, both branches IGNORE writeFile's boolean and still append '; restored' to the error string — so a caller can be told the file was restored when it was not.",
              "evidence": "tests/run_tests.lua:5217-5264 — the section is exactly SW0, SW1-3 (happy), SW4-5 (parse refusal), SW6-8 (validate refusal), SW9-9b, SW10 (backup), SW11-14 (verifiedMove). safewrite.lua:78-82 and :83-86.",
              "impact": "The restore net — the thing that justifies the whole design — is untested. It is trivially testable by pointing replaceLua at a path whose directory does not exist (rename fails) or by holding the target open. Do that BEFORE 13 watchers start depending on it."
            },
            {
              "reviewSaid": "\"13 hand-rolled serialize -> io.open(p,'wb') -> write -> close blocks across 8 watchers\" and \"the other 12 write the live file directly\"",
              "actually": "13 plain 'wb' statefile writes live in SEVEN watcher files; the 8th (arbwatch) contributes a FOURTEENTH plain write as its own fallback branch when the require fails. So arbwatch is not purely on the ladder either. Two further watcher writes are APPEND-mode text captures that cannot ride replaceLua at all.",
              "evidence": "Plain 'wb': ammowatch:120, chocowatch:117, craftwatch:129/192/411/589, fishwatch:110/460, helmwatch:150/309/439, pinwatch:80, restockwatch:158 = 13. Plus feature/arbwatch.lua:139-144 (the `else` fallback). Append-mode, not statefiles: fishwatch.lua:510 fishventures_capture.txt, helmwatch.lua:501 helmventures_capture.txt.",
              "impact": "The collapse target is 13 sites, not 12, and the fallback branch inside arbwatch should be deleted (or the guarded-require pattern dropped) rather than replicated 13 times — otherwise the 'one durability guarantee' is really two, and the untested one is the fallback."
            },
            {
              "reviewSaid": "Framing that the watchers were somehow left on the old pattern because the ladder came later or was unsuitable",
              "actually": "The reason is recorded verbatim and it is a CHURN judgement, not a technical objection — and it was made on the SAME DAY the ladder landed, with the ladder already in hand. Furthermore three watchers were written AFTER the ladder existed and still copied the old dance, so 'they predate it' is false for ammowatch (07-20), restockwatch (07-23) and chocowatch (07-24).",
              "evidence": "12edbf7 (2026-07-19, safewrite born) then 3094d67 (2026-07-19, lib/statefile born): \"Deliberately NOT consolidated: the watchers own write sites (each a 3-line pcall io dance around its own serializer) -- the churn outweighed the depth.\" arbwatch adopted it in 8972a7f (07-21) with its own recorded reason at arbwatch.lua:116-119: \"No rotated backup: a lost arbstate self-heals to the default ... but a torn write must never clobber the live list, which the atomic swap guarantees.\"",
              "impact": "DECISIVE and in the collapse's favour: there is no recorded engineering reason the others were left alone — only 'not worth the churn' at a moment when the churn bought nothing. Candidate 2 changes that calculus (the churn now buys a testable write seam). Quote 3094d67 in the ADR; it is the counter-argument and it is weak."
            }
          ],
          "divergences": [
            {
              "site": "feature/pinwatch.lua (pinstate.lua)",
              "whatsSpecial": "SESSION-ONLY by design, and the clear MUST reach disk before the engine's next read. Durability is actively unwanted — a surviving pinstate is the exact bug pins exist to prevent. A backup rung here would be a hazard, and a failed write that leaves the OLD file in place (which the ladder's restore branch does deliberately) re-arms last session's pins on a new character.",
              "evidence": "feature/pinwatch.lua:76-84 (save) and the load=CLEAR header at :87-95: \"an Ashita addon survives a logout ... last session's pins would force gear on them at login, which is the exact thing session-only pins exist to prevent\""
            },
            {
              "site": "feature/arbwatch.lua (arbstate.lua)",
              "whatsSpecial": "The ONLY file class with a written durability rationale, and it explicitly REFUSES the backup rung: loss self-heals to a built-in default, so only the swap matters. Any statefile.write(tbl) that adds timestampBackup by default would contradict a recorded decision.",
              "evidence": "feature/arbwatch.lua:116-119 and :100-102 (\"A missing or torn/unparseable file reads as the built-in default (the Statefile drop policy)\")"
            },
            {
              "site": "feature/restockwatch.lua (restock.lua)",
              "whatsSpecial": "Not a mirror of anything — it persists USER-AUTHORED config (master toggle, per-character and per-job Target lists). There is no source of truth to self-heal from, so a lost write is real data loss. This file class wants the backup rung that arbstate refuses.",
              "evidence": "feature/restockwatch.lua:155-163 saveState writes `{ master, showNudge, onlyWhenNeeded, character, jobs }`; loadState at :141-153 is the only reader"
            },
            {
              "site": "feature/craftwatch.lua — FOUR different files, only one of which is a statefile",
              "whatsSpecial": "keyitems.lua (:129) is a PERMANENT unlock mirror, guildpoints.lua (:192) is a packet-tracked accumulator, craftstate.lua (:411) is the real cross-state statefile, lastsynth.lua (:589) is a last-event record. Different lifetimes, different loss consequences, different serializers — one write() shape must not imply one durability policy.",
              "evidence": "feature/craftwatch.lua:119-133 (kiSave), :185-195 (gpSave), :405-414 (craftstate), :583-591 (lsPath/lastsynth)"
            },
            {
              "site": "feature/helmwatch.lua and feature/fishwatch.lua",
              "whatsSpecial": "Each owns THREE writes of two different kinds: a statefile ('wb' Lua), a ventures/points mirror ('wb' Lua), and an APPEND-mode plaintext capture ('ab' .txt). The append writers can never ride replaceLua — it parses its input as Lua and rewrites the whole file. A collapse that claims '13 writers -> 1' must say out loud that the 2 append captures stay hand-rolled.",
              "evidence": "feature/helmwatch.lua:150 / :309 (points) / :501 (`io.open(dir .. 'helmventures_capture.txt', 'ab')`); feature/fishwatch.lua:110 / :460 (ventures) / :510 (capture .txt)"
            },
            {
              "site": "feature/chocowatch.lua (chocostate.lua)",
              "whatsSpecial": "Deliberately writes a LIE — `enabled` is serialized as its session-only value while rankManual/rankFloor persist. The permanent max-latch (rankFloor) is the durable part. A generic write(tbl) that just serializes the module's state table would either persist `enabled` truthfully (behaviour change) or need per-field policy the handle does not have.",
              "evidence": "feature/chocowatch.lua:113-124, comment at :118-119 \"enabled is session-only (written OFF-truthfully here); rankManual / rankFloor persist\""
            },
            {
              "site": "gear/gearimport.lua",
              "whatsSpecial": "The heaviest consumer and the only one with an UNGUARDED require and a real validator: it sandbox-RUNS the candidate gear.lua and checks that env.gear is a table. It also always calls timestampBackup FIRST and prints the backup path in every abort message. Any interface change to replaceLua must carry the (chunk, tmpPath) validator signature — gearLoadValidator depends on receiving a loaded-but-unrun chunk and on setfenv still being available.",
              "evidence": "gear/gearimport.lua:29 (bare require), :1005-1011 (gearLoadValidator with `if setfenv ~= nil then setfenv(chunk, env)`), :1038-1044, :1253-1259"
            },
            {
              "site": "profiles.lua deleters",
              "whatsSpecial": "Uses a DIFFERENT verb (verifiedMove) and treats module absence as a hard stop, not a degrade: the deleters REFUSE rather than delete without the net. It also depends on the third return value `missing` to distinguish 'no such kind file' (a skip) from a real failure. Any refactor of verifiedMove's return shape silently turns skips into failures.",
              "evidence": "profiles.lua:44-49, :916, :969, :983-985 (`local mok, _, missing = sw.verifiedMove(sp, bp); if mok then removed = removed + 1; elseif not missing then failed = failed + 1; end`)"
            },
            {
              "site": "ui/triggersui.lua Blueprints + Mode library",
              "whatsSpecial": "The only callers with a guarded require AND a plain-write fallback path, and the only ones whose validator merely pcalls the chunk and checks for a table. Two near-identical 30-line copies (bpSave at :514, mlSave at :3046) — a second, smaller duplication the review does not mention, and one that a statefile-shaped handle would NOT absorb (these are library files under backups\\, not cross-state statefiles).",
              "evidence": "ui/triggersui.lua:511-545 and :3043-3076 — same structure, differing only in path/serializer/status-setter"
            },
            {
              "site": "tests/run_tests.lua SW section (cross-platform)",
              "whatsSpecial": "Hardcodes `local base = 'tests\\\\'`. On Windows those are real paths under tests\\; under WSL/Linux they become single filenames containing a literal backslash in the repo root. The section still passes on both, so any Windows-only behaviour it covers is covered ACCIDENTALLY on Linux — which is precisely how a dropped os.remove at :77 would sail through CI.",
              "evidence": "tests/run_tests.lua:5220 `local base = 'tests\\\\';` and the cleanup at :5263"
            }
          ],
          "openQuestions": [
            "Does Ashita v4 expose an atomic replace (MoveFileEx/ReplaceFile) anywhere? Only ashita.fs.create_directory and ashita.fs.get_dir are used in the entire addon. If ashita.fs has a move/copy that overwrites, the Windows remove-then-rename window could actually be closed instead of merely shortened — worth one grep of the Ashita API before committing to the current ladder as the durability story.",
            "Is the remove->rename absence window ever wide enough to matter in the field? Both the current 'wb' truncate-then-write and the ladder produce a state DROP if the engine's 1s poll lands mid-write (dispatch.lua:414 treats missing as off, and an empty file parses to nil data). Nobody has measured which window is wider, and the answer decides whether candidate 2 can honestly claim a torn-write fix at all.",
            "Should statefile.write default to backup-off? arbwatch has a recorded refusal of the backup rung (self-heals to default) while restockwatch persists irreplaceable user config. If the handle takes a policy flag, what is the default, and who audits the 13 call sites for the right one?",
            "Nothing ever sweeps a stale <file>.lua.tmp. If the game crashes between R2 and R6 the temp file lives forever in the character's dlac dir. Harmless today (no lister globs that dir), but 13 watchers writing on packet events multiplies the chance. Does the handle sweep on open()?",
            "timestampBackup's second-resolution stamp silently overwrites two backups made in the same second. Irrelevant at gearimport's human cadence, potentially relevant if a watcher-frequency writer ever gets the backup rung.",
            "Should the two triggersui library savers (bpSave :514 / mlSave :3046) collapse too? They are a second verbatim duplication of the same 30-line ladder-plus-fallback shape — outside candidate 2's stated scope, but the same argument applies and doing both at once is cheaper than doing them twice."
          ]
        }
      },
      {
        "key": "readhalf",
        "result": {
          "summary": "## The READ half of the statefile seam — verbatim record\n\n### 1. `dispatch._ensureStateFile` — `C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac\\dispatch.lua:395-424` (docstring + body, IN FULL)\n\n```lua\n-- ---------------------------------------------------------------------------\n-- Cached per-character state-file reader -- the ONE implementation behind the\n-- auto/acc/craft/helm/fish/pin caches (the GUI->engine statefile handoff, v70;\n-- they were six near-identical clones and had already drifted). Throttle: one\n-- disk check per second; missing file = state off (nil); pre-login (no char\n-- dir) keeps whatever is cached. POLICY, unified from the pin reader's field\n-- lesson (v44): a torn/corrupt write DROPS the state -- cache.raw is already\n-- the corrupt text, so keeping the last good table would glue it on forever\n-- (the raw-compare short-circuits every later call and nothing could clear\n-- it, not even the watcher's clear-on-load). The next good write self-heals.\n-- The TRIGGER file deliberately does NOT ride this: it is hand-editable, so\n-- mid-typo it keeps the previous rules and says so (ensureLoaded below).\n-- ---------------------------------------------------------------------------\nlocal function ensureStateFile(cache, filename)\n    local now = os.time();\n    if now == cache.lastCheck then return cache.data; end\n    cache.lastCheck = now;\n    local dir = charDir();\n    if dir == nil then return cache.data; end\n    local raw = readFile(dir .. filename);\n    if raw == nil then cache.raw, cache.data = nil, nil; return nil; end\n    if raw == cache.raw then return cache.data; end\n    cache.raw = raw;\n    local chunk = (loadstring or load)(raw, '@' .. filename);\n    if chunk == nil then cache.data = nil; return nil; end\n    local ok, t = pcall(chunk);\n    if ok and type(t) == 'table' then cache.data = t; else cache.data = nil; end\n    return cache.data;\nend\nM._ensureStateFile = ensureStateFile;   -- headless seam: the corrupt-drop policy pinned once (SF*)\n```\n\n**Signature.** `(cache, filename) -> table|nil`. `cache` is a caller-owned mutable `{ raw, data, lastCheck }` singleton declared beside each consumer — the reader is stateless, the *caller* owns the state. `filename` is a bare basename; the directory comes from dispatch's own `charDir()` (dispatch.lua:302). `readFile` is dispatch.lua:288 (`io.open(p,'r')`, `'*a'`).\n\n**Caching — three independent short-circuits, in order:**\n1. **Second-equality throttle** (`now == cache.lastCheck`). Not a 1-second *duration*: an equality on `os.time()`. Every call in the same wall-clock second returns the cached table without touching disk. Tests defeat it with `cache.lastCheck = -1`.\n2. **Raw-text compare** (`raw == cache.raw`). Skips `loadstring` + `pcall` when the bytes are byte-identical. This is why writer output must be **order-stable** — an unstable `pairs()` key order would re-parse all 9 files every second (pinned only for pinwatch, `run_tests.lua:3504-3510` AM12).\n3. **Pre-login hold** (`dir == nil` → `return cache.data`). Keeps whatever is cached; does *not* drop.\n\n**Corrupt-drop policy — and its deliberate asymmetry:**\n- **Missing file** → `cache.raw, cache.data = nil, nil` — *both* cleared, so a re-created file re-parses. Missing = state OFF.\n- **Parse failure** (`loadstring` returns nil) → `cache.data = nil`, but **`cache.raw` keeps the corrupt text**. Deliberate: the docstring says keeping the last-good table \"would glue it on forever (the raw-compare short-circuits every later call and nothing could clear it, not even the watcher's clear-on-load)\".\n- **Runs but errors, or returns a non-table** → same drop.\n- **Self-heal**: the next write with different bytes fails the raw-compare and re-parses.\n- The trigger file is explicitly excluded (hand-editable → keeps previous rules).\n\n**The 9 statefiles it serves** (all `dispatch.lua`):\n| file | reader | line |\n|---|---|---|\n| `autogear.lua` | `ensureAutoLoaded` | 1098 |\n| `accstate.lua` | `ensureAccState` | 2247 |\n| `craftstate.lua` | `ensureCraftState` | 3289 |\n| `helmstate.lua` | `ensureHelmState` | 3319 |\n| `fishstate.lua` | `ensureFishState` | 3375 |\n| `chocostate.lua` | `ensureChocoState` | 3435 |\n| `ammostate.lua` | `ensureAmmoState` | 3529 |\n| `pinstate.lua` | `ensurePinState` | 3871 |\n| `arbstate.lua` | `ensureArbState` | 3878 |\n\n### 2. Tests SF0–SF9 — `tests\\run_tests.lua:5377-5439` (IN FULL)\n\n```lua\n-- SF. The statefile seam (engine v70): ONE cached reader (ensureStateFile)\n--     behind the auto/acc/craft/helm/fish/pin caches -- they were six\n--     near-identical clones and had drifted (pin dropped corrupt writes, the\n--     others kept the last good table glued on forever). Policy pinned HERE,\n--     once, for all of them; _charDirOverride makes the file-driven surface\n--     run headless for the first time.\n(function()\n    local esf = dispatchM._ensureStateFile;\n    check('SF0 helper exported', type(esf), 'function');\n    local function put(p, t) local f = io.open(p, 'w'); f:write(t); f:close(); end\n    dispatchM._charDirOverride = 'tests\\\\';\n    local cache = { raw = nil, data = nil, lastCheck = -1 };\n\n    put('tests\\\\sf_state.lua', 'return { enabled = true, craft = \"Alchemy\" }');\n    local d = esf(cache, 'sf_state.lua');\n    check('SF1 file read + parsed', d ~= nil and d.craft, 'Alchemy');\n\n    -- same-second throttle: a changed file is not re-read until the clock moves\n    put('tests\\\\sf_state.lua', 'return { craft = \"Smithing\" }');\n    cache.lastCheck = os.time();\n    check('SF2 throttled within the second', esf(cache, 'sf_state.lua').craft, 'Alchemy');\n\n    -- THE POLICY: corrupt write -> DROP (not last-good); re-reads stay dropped\n    cache.lastCheck = -1;\n    put('tests\\\\sf_state.lua', 'return {');\n    check('SF3 corrupt write drops the state', esf(cache, 'sf_state.lua'), nil);\n    cache.lastCheck = -1;\n    check('SF4 corrupt stays dropped on re-read', esf(cache, 'sf_state.lua'), nil);\n\n    -- the next good write self-heals\n    cache.lastCheck = -1;\n    put('tests\\\\sf_state.lua', 'return { craft = \"Bonecraft\" }');\n    check('SF5 good write self-heals', esf(cache, 'sf_state.lua').craft, 'Bonecraft');\n\n    -- a file that parses but ERRORS on run drops too\n    cache.lastCheck = -1;\n    put('tests\\\\sf_state.lua', 'error(\"boom\")');\n    check('SF6 run-error drops the state', esf(cache, 'sf_state.lua'), nil);\n\n    -- missing file = state off\n    cache.lastCheck = -1;\n    os.remove('tests\\\\sf_state.lua');\n    check('SF7 missing file = state off', esf(cache, 'sf_state.lua'), nil);\n\n    -- pre-login (no char dir) keeps whatever is cached\n    cache.lastCheck = -1; cache.data = { keep = true };\n    dispatchM._charDirOverride = nil;\n    check('SF8 no char dir keeps cache', esf(cache, 'sf_state.lua').keep, true);\n\n    -- WIRING: with no test override, the auto manifest reads through the seam.\n    -- The _auto singleton's 1s throttle may have been armed by an earlier\n    -- section in this same second -- cross the boundary so the read is live.\n    dispatchM._charDirOverride = 'tests\\\\';\n    dispatchM._autoOverride = nil;\n    put('tests\\\\autogear.lua', 'return { universal = { name = \"Chatoyant Staff\", tier = 2, level = 51 } }');\n    local t0 = os.time(); repeat until os.time() ~= t0;\n    check('SF9 resolveVirtual reads the manifest through the seam',\n        dispatchM._resolveVirtual('dlac:AutoStaff', { player = { MainJobSync = 75 } }), 'Chatoyant Staff');\n    os.remove('tests\\\\autogear.lua');\n    dispatchM._charDirOverride = nil;\nend)();\n```\n\n**What they fake, and how — nothing is mocked.** They inject the *directory*, not a filesystem: `dispatchM._charDirOverride = 'tests\\\\'` is read as the first line of `dispatch.charDir()` (dispatch.lua:303). Real `io.open` writes real files into `tests\\`, `os.remove` cleans up. The cache is hand-surgered (`cache.lastCheck = -1`) to defeat the second-throttle, and SF9 spins `repeat until os.time() ~= t0` to cross a real second boundary. AR7/AR7b (`run_tests.lua:5548-5565`) reuse the same three lines verbatim for `arbstate.lua`.\n\n**Filesystem faking a write half could reuse — yes, three proven patterns, none of them an fs abstraction:**\n- `_charDirOverride` (inject the dir, use real disk) — used by SF and AR7.\n- **`SW0–SW14`, `run_tests.lua:5212-5264`** — `lib/safewrite`'s real writes, renames, removes and restores driven against real files in `tests\\`, including the validator callback. This is a *tested write ladder that already exists*.\n- **`AM1–AM12+`, `run_tests.lua:3455-3520`** — pure-serializer round-trips, plus **AM8, a genuine cross-state contract test**: `dispatchM._pinOverlayFor(r2, ...)` is fed `pinwatch.serialize()` output.\n- The `put`/`get` helper pair is copy-pasted three times (5222-5223, 5388, 5552).\n\n### 3-5\nSee `verified` / `corrections` / `divergences` below. Short answers: **(3)** confirmed misnamed — 44 lines, one function, 8 callers, all in `feature/`. **(4)** 9 files cross addon→engine via this reader, 2 cross engine→addon (`modestate.lua`, `firedstate.lua`) with *no* shared reader at all, plus `triggers\\<JOB>.lua` deliberately outside the seam. **(5)** Yes — `dispatch.lua:302-321`, and the reasoning is written down in `lib/statefile.lua:9-12`.",
          "verified": [
            {
              "claim": "dispatch._ensureStateFile is at dispatch.lua:408-424, 17 lines behind (cache, filename), and is exported as a headless seam",
              "evidence": "dispatch.lua:408-424 (body), dispatch.lua:424 `M._ensureStateFile = ensureStateFile;   -- headless seam: the corrupt-drop policy pinned once (SF*)`"
            },
            {
              "claim": "It serves exactly 9 statefiles",
              "evidence": "dispatch.lua:1098 autogear.lua, :2247 accstate.lua, :3289 craftstate.lua, :3319 helmstate.lua, :3375 fishstate.lua, :3435 chocostate.lua, :3529 ammostate.lua, :3871 pinstate.lua, :3878 arbstate.lua"
            },
            {
              "claim": "Its docstring records that it replaced six drifted clones, and names the field lesson it unified",
              "evidence": "dispatch.lua:396-404 \"they were six near-identical clones and had already drifted... POLICY, unified from the pin reader's field lesson (v44)\"; dispatch.lua:3869-3870 \"(The corrupt-write DROP that used to be special-cased here is now the shared ensureStateFile policy -- this reader is where the field lesson came from.)\""
            },
            {
              "claim": "It has exactly 10 tests, SF0-SF9",
              "evidence": "tests/run_tests.lua:5385-5439"
            },
            {
              "claim": "lib/statefile.lua is 44 lines and exports exactly one function, charDir() — no read, no write, no filename, no serializer",
              "evidence": "lib/statefile.lua:1-44; the only export is `function M.charDir()` at lib/statefile.lua:27"
            },
            {
              "claim": "statefile.charDir() has 8 callers, all in feature/, all using an identical guarded-require preamble",
              "evidence": "feature/ammowatch.lua:41, feature/arbwatch.lua:78, feature/chocowatch.lua:29, feature/craftwatch.lua:95 (bound as kiCharDir), feature/fishwatch.lua:42, feature/helmwatch.lua:64, feature/pinwatch.lua:37, feature/restockwatch.lua:35. Preamble form (pinwatch.lua:36-38): `local _sfok, _sfile = pcall(require, 'dlac\\\\lib\\\\statefile'); local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir or function() return nil; end;`. Zero callers in ui/ or gear/. Harness seeding at tests/run_tests.lua:20; module-invariant LIB list at tests/run_tests.lua:232"
            },
            {
              "claim": "Three modules bypass lib/statefile with byte-identical hand-rolled dataDir() copies (review's gearui/lockstyle/macrobook claim)",
              "evidence": "ui/gearui.lua:1112-1120, feature/lockstyle.lua:169-178, feature/macrobook.lua:54-60 — all three open with the identical comment \"-- The dlac data home (mode-aware -- feature/native-engine): profiles.dataDir() with the legacy composition as fallback.\""
            },
            {
              "claim": "dispatch.lua has its OWN charDir copy, and the reason it is deliberately dispatch-local is written down in lib/statefile.lua",
              "evidence": "dispatch.lua:302-321. Reasoning, lib/statefile.lua:9-12: \"The ENGINE'S half stays dispatch-local on purpose (charDir + ensureStateFile in dispatch.lua): the two Lua states share the FILES, not the code -- the LAC-state engine reads gState first and self-swaps on version moves, and keeping its reader in the one seeded file keeps the handshake in one place.\" Mirrored in docs/architecture.md:75: \"(The seeded engine has its own charDir() inside dispatch.lua.)\""
            },
            {
              "claim": "The two charDir twins already differ, and are held together by comment convention with no test (review's twins claim)",
              "evidence": "dispatch.lua:303 `if M._charDirOverride ~= nil then return M._charDirOverride;` and dispatch.lua:309-311 `if gState ~= nil and gState.PlayerName ~= nil and gState.PlayerId ~= nil then name, id = gState.PlayerName, gState.PlayerId;` — neither exists in lib/statefile.lua:27-42, which goes straight to the party memory read. Review's own note at docs/design/architecture-review-2026-07-25.md:338-340"
            },
            {
              "claim": "ADR 0002 forbids the engine requiring any addon module — this is why the seam is files, not code",
              "evidence": "docs/adr/0002-data-driven-trigger-dispatch.md:3 \"dlac and LuaAshitacast run in separate Lua states; only code required *by the profile* (the seeded `dlac\\utils` library) can call `gFunc.EquipSet`\"; dispatch.lua:356 \"Twin of feature/debug.lua's M._watchFire (ADR 0002: the engine requires no addon module -- twin constants, twin logic)\""
            },
            {
              "claim": "The GUI-derives / engine-reads split for the autogear manifest is an ADR-level decision",
              "evidence": "docs/adr/0004-automations-staff-obi.md:11 \"Implementation split (two Lua states): the **GUI derives** a per-character manifest -- `<char>\\dlac\\autogear.lua` ... and the **engine reads** it, hot-reloaded like the trigger file. The engine never loads the 5 MB catalog.\""
            },
            {
              "claim": "The write side is 13+ hand-rolled serialize->io.open->write->close blocks, and no write module exists",
              "evidence": "feature/ write sites: ammowatch.lua:120, arbwatch.lua:140 (fallback arm), chocowatch.lua:117, craftwatch.lua:129/192/411/589, fishwatch.lua:110/460, helmwatch.lua:150/309/439, pinwatch.lua:80, restockwatch.lua:158. Plus ui/automationsui.lua:62 (autogear) and ui/triggersui.lua:86. All are `io.open(p,'wb')` / `io.open(p,'w')` + write + close under pcall"
            },
            {
              "claim": "Writer output must be order-stable because the reader content-compares raw text — and this is pinned for exactly one file",
              "evidence": "feature/pinwatch.lua:47-48 \"Slots are emitted in sorted order: a stable file means dispatch's raw-text compare skips the re-parse when nothing actually changed.\"; tests/run_tests.lua:3504-3510 AM12 \"serialization is order-stable across pairs() luck\". No equivalent pin for the other 8 statefiles"
            }
          ],
          "corrections": [
            {
              "reviewSaid": "\"Only `feature/arbwatch.lua` uses the atomic `lib/safewrite` ladder (verified: it is the sole file in `feature/` that even mentions `safewrite`). The other 12 write the live file directly.\" (review md:134-135)",
              "actually": "True as scoped to feature/, but the bolded takeaway is wrong repo-wide: lib/safewrite has FOUR consumers, and two of them are recent GUI write paths with the full backup+validate ladder. Also arbwatch is not purely on the ladder — it keeps a plain io.open('wb') fallback arm for when the pcall-require fails.",
              "evidence": "feature/arbwatch.lua:120-145 (ladder + `else` plain-write fallback at :138-144); ui/triggersui.lua:513-540 (Blueprints library, timestampBackup + replaceLua + validate); ui/triggersui.lua:3045-3070 (Mode library, same); gear/gearimport.lua:29 `local sw = require(\"dlac\\\\lib\\\\safewrite\");` + :1036, :1251; profiles.lua:48, :916, :969 (verifiedMove, deletion refused without it)",
              "impact": "The write half does not need to invent a ladder or an adoption story. There is an established, tested, four-consumer idiom — guarded pcall-require, timestampBackup of prev, replaceLua with a `validate = function(chunk) local vok, ret = pcall(chunk); return vok and type(ret) == 'table' end` closure, plain-write fallback. Copy that shape rather than designing one; and decide deliberately whether the fallback arm survives the collapse (see divergences)."
            },
            {
              "reviewSaid": "\"Zero tests touch any write path... The `_saveState`/`_charDir` seams exist to **disable** IO, never to observe it — there is no filesystem to fake.\" (review md:138-140)",
              "actually": "Two overstatements. (a) SW0-SW14 test lib/safewrite's real write path — real files, real os.rename, real restore-on-failure — in tests\\. (b) The serializers ARE tested as pure functions, and AM8 is a genuine cross-state contract test that feeds pinwatch.serialize() output straight into the engine's overlay. What is untested is only the ~8 lines of glue per watcher: path composition + io.open + write + close.",
              "evidence": "tests/run_tests.lua:5212-5264 (SW section header: \"Real files under tests\\ (cwd = addon root), removed at section end\"); tests/run_tests.lua:3455-3520 (AM section header: \"the writer half of the pin contract. Serializes the table the engine's ensurePinState() loads back, so the two must agree on the format exactly\"); AM8 at :3491-3492 `local eng = dispatchM._pinOverlayFor(r2, { { label = 'name=slow ii' } }, 'Midcast');`",
              "impact": "Two things change. First, the untested surface is smaller and more specific than the review implies, so the win is narrower than \"write paths testable for the first time\" — it is \"the other 8 writers get the AM8 treatment pinwatch already has\". Second, the review's proposed remedy (\"an injectable fs for tests\") is NOT this repo's idiom and would be the only fs abstraction in the tree; the proven pattern is inject-the-DIR (`_charDirOverride = 'tests\\\\'`) and use real files. Prefer a `statefile.dirOverride` seam over a fake-fs parameter."
            },
            {
              "reviewSaid": "\"13 `xxxPath()` composers... across 8 watchers\" — framing the write half as a watcher-only problem, and \"addon-state only, no engine `VERSION` bump, no ADR touched, smallest blast radius\" (review md:133-136, :157)",
              "actually": "The largest and most-consumed statefile, autogear.lua, is not written by a watcher at all — it is written by a UI module that never touches lib/statefile and composes its own path through injected deps. And two statefiles flow the OTHER way (engine writes, addon reads), written by dispatch's own writeFile with no shared reader on the addon side.",
              "evidence": "ui/automationsui.lua:127-135 `autoPath()` (deps.dataDir() -> deps.charBase() .. 'dlac\\\\autogear.lua'), writer at ui/automationsui.lua:62 `writeFileText`, manifest schema `AUTO_FMT = 15` at :122. Reverse direction: dispatch.lua:4746-4772 saveModeState -> modestate.lua, dispatch.lua:4778-4788 saveFiredState -> firedstate.lua; addon-side hand-rolled loadfile readers at dlac.lua:162, feature/check.lua:203, ui/gearui.lua:1147, ui/triggersui.lua:732 and :775, ui/priorityui.lua:166, ui/automationsui.lua:1176",
              "impact": "Scope the write half explicitly. A collapse that covers only feature/*watch leaves the biggest producer (autogear, 15 format versions) outside the seam and leaves 7 hand-rolled modestate/firedstate readers untouched. The \"addon-state only, no VERSION bump\" claim holds only while the emitted BYTES stay parseable by today's engine — see the shape constraints below."
            },
            {
              "reviewSaid": "CONTEXT.md's Statefile glossary entry enumerates the file set: \"(craftstate, helmstate, fishstate, pinstate, accstate, arbstate, the autogear manifest)\"",
              "actually": "Stale — it lists 7, the reader serves 9. chocostate.lua and ammostate.lua are missing from the domain term.",
              "evidence": "CONTEXT.md:148 vs dispatch.lua:3435 (`ensureChocoState`) and dispatch.lua:3529 (`ensureAmmoState`)",
              "impact": "Any design that enumerates statefiles from the glossary will silently omit two. The authority is the ensureStateFile call sites, not CONTEXT.md. Fix the glossary entry in the same change (it is also the doc that would name the new write verb)."
            },
            {
              "reviewSaid": "The seam's throttle is \"one disk check per second\" / \"~1s throttle\"",
              "actually": "It is an equality test on os.time(), not a 1-second duration. Two calls 0.9s apart that straddle a second boundary both hit disk; two calls 0.01s apart within one second both hit the cache. The tests know this and cross a real boundary with a spin loop.",
              "evidence": "dispatch.lua:409-411 `local now = os.time(); if now == cache.lastCheck then return cache.data; end cache.lastCheck = now;`; tests/run_tests.lua:5434 `local t0 = os.time(); repeat until os.time() ~= t0;`",
              "impact": "Matters for a write half only if the design ever tries to reason about write/read interleaving windows. The observable worst case is not \"1s stale\" — it is \"up to ~2s stale\", and the write-visibility window is not uniform."
            },
            {
              "reviewSaid": "Implicitly, that lib/statefile.charDir's caller set is the statefile set",
              "actually": "feature/restockwatch.lua uses statefile.charDir but its file is explicitly declared NOT a Statefile — nothing in the engine reads it. Conversely accstate.lua IS a statefile the engine reads, but nothing on main writes it.",
              "evidence": "feature/restockwatch.lua:35 (charDir) vs feature/restockwatch.lua:106 `'-- Per-character; NOT a Statefile (no engine reads it). See docs/design/ebox-restock.md.'`; dispatch.lua:2238-2240 \"the WRITER (accwatch.lua + accdata.lua) ships on feature/autoacc pending GM approval -- on main nothing writes accstate.lua\"",
              "impact": "A write API cannot infer durability policy from \"is it in the watcher family\". restock config is player-authored data (losing it is a real loss, warrants backup); craftstate is a toggle mirror that self-heals on the next click (warrants none). The handle needs a policy argument, not one policy."
            }
          ],
          "divergences": [
            {
              "site": "feature/arbwatch.lua — the only watcher already on safewrite, and it keeps a plain-write fallback",
              "whatsSpecial": "setOrder() branches: if the pcall-require of lib/safewrite succeeded, read the current text as origText and use replaceLua; otherwise plain io.open('wb'). Its comment also states a deliberate policy choice a one-size collapse would erase: NO rotated backup, because 'a lost arbstate self-heals to the default'. A collapse that always backs up would start littering timestamped arbstate backups for a file whose loss is a non-event.",
              "evidence": "feature/arbwatch.lua:115-145 — \"No rotated backup: a lost arbstate self-heals to the default, so the file class does not warrant the set-file backup policy -- but a torn write must never clobber the live list, which the atomic swap guarantees.\""
            },
            {
              "site": "feature/pinwatch.lua — save() is used as a CLEAR-TO-DISK, and an empty table must still produce a file",
              "whatsSpecial": "loadPinState() calls save() with an empty table specifically to erase the previous session's pins BEFORE the engine's next read; the clear is keyed on the char dir so a logout/login re-clears. serialize({}) deliberately returns the canonical 'return { }\\n' rather than nothing. Any write handle that debounces, buffers, skips no-op writes, or treats an empty table as 'nothing to write' resurrects last Tuesday's pins at login — the exact bug this module exists to prevent. AM3 pins the empty spelling.",
              "evidence": "feature/pinwatch.lua:17-21 \"The clear must reach DISK, not just this table: the engine reads the file from LAC's own Lua state on its own schedule, so a stale file would dress you at login\"; :57 `if #slots == 0 then return 'return { }\\n'; end`; :96-103 loadPinState keyed on `_loadedFor == dir`; tests/run_tests.lua:3477 AM3"
            },
            {
              "site": "ui/automationsui.lua — autogear.lua, the biggest statefile, written by a UI module outside lib/statefile",
              "whatsSpecial": "Its path composer is deps-injected (deps.dataDir -> deps.charBase), not statefile.charDir. It carries a schema version AUTO_FMT = 15 that the ENGINE never reads — self-healing is driven from the addon side (an old fmtver triggers a rescan on render). It is also read back by a second addon module (helmwatch) as well as the engine.",
              "evidence": "ui/automationsui.lua:127-135 autoPath(), :62 writeFileText, :122 `local AUTO_FMT = 15;`, :122-123 \"Manifest schema version: bump when autoCommit writes NEW fields. An on-disk manifest with an older fmtver self-heals\"; helmwatch.lua:693-694 `local chunk = loadfile(dir .. 'autogear.lua')`"
            },
            {
              "site": "dispatch.lua — modestate.lua and firedstate.lua flow ENGINE -> addon",
              "whatsSpecial": "These are written by the engine's own writeFile (dispatch.lua:292) inside a state that must not require any addon module (ADR 0002). modestate carries the VERSION handshake and is read BACK by the engine on load; firedstate is display-only and rewritten per action pass, coalesced to one write. A single 'writer module' living in the addon tree cannot serve them — and neither rides ensureStateFile, so a unified write half would still leave a reader asymmetry.",
              "evidence": "dispatch.lua:4740-4744 \"Mode state, DLAC-OWNED. modestate.lua is written on every change (the GUI -- a different Lua state -- reads it for display) and read BACK by loadModeState when the engine loads\"; :4752 `parts = { string.format('[\"__version\"] = %d,', M.VERSION) };   -- engine handshake`; :4774-4777 \"display-only, never read back by the engine. Its own small file, NOT modestate\"; :5683 \"pass lands in firedstate.lua as ONE write\""
            },
            {
              "site": "ammostate.lua — two live on-disk formats the engine tolerates simultaneously",
              "whatsSpecial": "ammoStateOn() branches on shape, not on a version field: `if type(as.ammo) == 'table' then -- legacy fmt 1` vs `if type(as.jobs) == 'table' then -- fmt 2`. There is no version gate to lean on anywhere in the reader. A rewritten serializer must keep emitting a shape one of these two arms recognises.",
              "evidence": "dispatch.lua:3531-3542; dispatch.lua:99 \"legacy fmt-1 files (top-level ammo list + jobs map) keep working unchanged until the GUI migrates them\""
            },
            {
              "site": "autogear.lua — the engine reads legacy shapes inline at three separate sites",
              "whatsSpecial": "Not one schema, a set of independently-tolerated shapes: `a.universal` (single) vs `a.universals` (v82 ladder), an old boolean-format manifest that triggers a one-shot player warning, and `if cands.name ~= nil then cands = { cands }` for the legacy fmtver-1 shape. Each engine read site owns its own tolerance.",
              "evidence": "dispatch.lua:1100-1104 (old-boolean warning), :1416-1419 (`consider(a.universal)` then the `a.universals` ladder), :1505 `if cands.name ~= nil then cands = { cands }; end   -- legacy fmtver-1 shape`, :2044-2046 (`a.mp` / `a.mpBest` / `a.rf`)"
            },
            {
              "site": "feature/craftwatch.lua — writes four files of three different classes",
              "whatsSpecial": "craftstate.lua is a Statefile (engine reads it); keyitems.lua, guildpoints.lua and lastsynth.lua are display mirrors — one of them (guildpoints) is read by a DIFFERENT addon module, and lastsynth deliberately stamps os.time() on every save (which would be fatal for the raw-compare if it were a statefile). Same module, same io.open shape, three different contracts.",
              "evidence": "feature/craftwatch.lua:411 (craftstate), :129 (keyitems.lua), :186-195 (guildpoints.lua; :185 \"fishwatch reads this one\"), :583-592 (lastsynth.lua, `\"... return { wallAt = \" .. os.time() .. ...\"`, :581-583 \"DISPLAY ONLY\")"
            },
            {
              "site": "feature/helmwatch.lua and feature/fishwatch.lua — write their statefile AND unrelated per-character ledgers, and helmwatch READS a file it does not own",
              "whatsSpecial": "helmwatch writes helmstate.lua (statefile), venturepoints.lua and helmventures.lua (ledgers); fishwatch writes fishstate.lua and fishventures.lua. helmwatch also loadfile()s autogear.lua — a file the ADDON writes from a different module. Any handle API needs read-only handles to files the caller does not own, and must not imply ownership from having a handle.",
              "evidence": "feature/helmwatch.lua:150 (helmstate), :290 vpPath -> venturepoints.lua, :421 ventPath -> helmventures.lua, :693-694 (reads autogear.lua); feature/fishwatch.lua:110 (fishstate), :449 ventPath -> fishventures.lua"
            }
          ],
          "openQuestions": [
            "Does safewrite.replaceLua's os.remove(path) -> os.rename(tmp, path) WIDEN the failure window for a file the engine polls every second? The current plain io.open('wb') never makes the file vanish; replaceLua does, for the duration of a rename. ensureStateFile treats missing (dispatch.lua:415, clears BOTH raw and data, returns nil = state OFF) differently from corrupt — so a rename landing between the engine's readFile and the next tick turns a craft/helm/fish overlay off for one dispatch, i.e. a visible gear flap. The corrupt-drop policy was designed for torn CONTENT, not for a momentarily absent file. Worth measuring before making the atomic ladder universal.",
            "Where does the deepened module LIVE? lib/safewrite.lua:30-31 explicitly claims it is 'requirable from BOTH Lua states'; lib/statefile.lua does NOT — its charDir pcall-requires dlac\\profiles (an addon module), which ADR 0002 forbids the engine from depending on. If the write half is ever to serve dispatch's own modestate/firedstate writes, it must be profiles-free; if it is addon-only, say so in the header the way safewrite does, and accept that the engine keeps its twin.",
            "Should the raw-text-compare contract be promoted to a tested invariant for all 9 writers? Today only AM12 pins order-stability, and only for pinwatch. A single serializer would make this trivially enforceable (one test), but it also means the serializer must never emit a timestamp — and craftwatch's lastsynth mirror and dispatch's modestate both DO stamp os.time() on every save. Is 'no wall-clock in a statefile' a rule the new module enforces, or a per-file opt-out? Note helmstate/fishstate/chocostate all carry an `at` field already (dispatch.lua:3313, :3366, :3427).",
            "Does the write half claim autogear.lua? It is the largest statefile, has 15 format versions, is written by a UI module rather than a watcher, and its path comes from injected deps rather than lib/statefile. Including it makes the collapse genuinely complete; excluding it means the seam still has a hole the size of its biggest file. The AUTO_FMT self-heal machinery (ui/automationsui.lua:122-123) would need a home either way.",
            "What happens to accstate.lua, which the engine reads but nothing on main writes (writer lives on feature/autoacc, GM-pending)? A write-half enumerated from writers omits it; a write-half enumerated from readers includes a file with no producer. Either choice creates a merge conflict against feature/autoacc when accwatch.lua lands.",
            "ensureStateFile RUNS the file (`pcall(chunk)`, dispatch.lua:420) via `(loadstring or load)(raw, '@'..filename)` with no mode argument — so whatever the addon writes, the engine executes, and in 5.1 semantics a bytecode payload would load too. This is fine today because both sides are ours, but if the write half ever gains an 'import a shared statefile' path (the Blueprints/Mode-library precedent at ui/triggersui.lua:513 and :3045, which BOTH sandbox-validate before committing), the reader has no such gate. Should the deepened writer's validate callback become the only door, or does the reader need one too?",
            "Is the 8-copy guarded-require preamble worth keeping? Every caller does `pcall(require, 'dlac\\\\lib\\\\statefile')` and falls back to `function() return nil; end`. If lib/statefile grows write verbs, that fallback silently becomes 'writes are no-ops' rather than 'path is unknown' — a much worse silent failure. Does the new module need to be a hard require (like gear/gearimport.lua:29 does for safewrite) rather than a guarded one?"
          ]
        }
      },
      {
        "key": "bypassers",
        "result": {
          "summary": "The three modules the review names (gearui:1114, lockstyle:171, macrobook:56) DO bypass `lib/statefile.charDir()` — but all three compute the IDENTICAL path. They are byte-for-byte the same \"ask `profiles.dataDir()`, else compose the legacy home inline\" body as statefile itself. That is duplication (4 copies of a 9-line function, plus ~7 more variants), not divergence — no latent write-to-nowhere bug there. The REAL divergences are in files the review either ranked lower or attributed to the wrong module: `gear/setmanager.lua:505` (set backups hardcoded to the legacy LAC tree — dlac-owned profile data backed up outside the native home), `feature/check.lua:203` (the `/dl check` engine-stamp read, hardcoded legacy — this, not `feature/debug.lua`, is what makes `/dl check` native-degraded), and `gear/gearoptim.lua:2280`. The path chain is: `charIdentity()` → `charFolder()` = `<Name>_<Id>` → `nativeMode()` flag picks the root → `dataDir()` → ~14 leaf composers. \"Mode-aware\" means the NATIVE-ENGINE storage flag, not the CW/Wings game mode. The addon writes ~37 distinctly-named per-character files plus 4 variable per-job/per-profile families plus 4 seeded library copies. There is NO authoritative list anywhere — the closest is a prose docstring at profiles.lua:200-202 that literally ends in an ellipsis.",
          "verified": [
            {
              "claim": "gearui.lua:1114, feature/lockstyle.lua:171 and feature/macrobook.lua:56 each define a local dataDir() that bypasses lib/statefile",
              "evidence": "ui/gearui.lua:1114-1122, feature/lockstyle.lua:171-179, feature/macrobook.lua:56-64 — none of the three requires dlac\\\\lib\\\\statefile anywhere in the file"
            },
            {
              "claim": "lib/statefile.lua is 44 lines with one function, charDir(), which pcall-delegates to profiles.dataDir()",
              "evidence": "lib/statefile.lua:27-42 (file is exactly 45 lines incl. trailing newline)"
            },
            {
              "claim": "docs/architecture.md claims profiles.dataDir()/charRoot()/storageRoot()/charDataDirAt() are the ONLY path composers, and grep contradicts it",
              "evidence": "docs/architecture.md:786-787 vs 37 GetInstallPath sites in 21 non-test .lua files (42 sites / 22 files including tests/run_tests.lua)"
            },
            {
              "claim": "gear/setmanager.lua:42-56 composes the legacy LAC path with no profiles delegation, while gear/gearimport.lua:988-997 asks prof.charRoot() first — so under the native engine set backups land in the legacy tree and gear backups in the native tree",
              "evidence": "gear/setmanager.lua:42-56 + :505 `local dir = profileDir() .. 'backups\\\\'` vs gear/gearimport.lua:993 `r = prof.charRoot()`"
            },
            {
              "claim": "Set backups really do carry dlac-owned PROFILE data, not just LAC job files — so the legacy pin is a genuine split",
              "evidence": "gear/setmanager.lua:596-605: commitSet resolves `path` via commitTarget → _prof.setsPath(job) (profiles\\<Name>\\sets\\<JOB>.lua) and then backs THAT text up through backupWithRotation into the legacy backups\\ dir"
            },
            {
              "claim": "dispatch.lua:302 charDir() prefers the mode-aware dataDir() while the addon-side /dl check half reads the legacy home, so in native mode the engine writes modestate to the native home and the addon reads the legacy one",
              "evidence": "dispatch.lua:302-320 (mode-aware) + dispatch saveModeState→charDir vs feature/check.lua:203 `loadfile(base .. 'dlac\\\\modestate.lua')` with base from check.lua:168-178 (hardcoded legacy)"
            },
            {
              "claim": "ensureStateFile serves 9 statefiles",
              "evidence": "dispatch.lua:1098 autogear, :2247 accstate, :3289 craftstate, :3319 helmstate, :3375 fishstate, :3435 chocostate, :3529 ammostate, :3871 pinstate, :3878 arbstate"
            },
            {
              "claim": "charDir has two twins held together by comment only, and they already differ — dispatch reads gState first",
              "evidence": "dispatch.lua:308-318 checks gState.PlayerName/PlayerId before the party manager; lib/statefile.lua:34-40 uses the party manager ONLY"
            },
            {
              "claim": "get_dir's mask is a REGEX (not a Lua pattern) and its 3rd arg is RECURSIVE — both traps are recorded in code",
              "evidence": "profiles.lua:375-380 (canonical note) and gear/setmanager.lua:511-514 (independent copy of the same finding); both call get_dir(path, '.*', false) and filter Lua-side"
            },
            {
              "claim": "Only feature/arbwatch.lua uses lib/safewrite among the watchers",
              "evidence": "grep of io.open write sites across feature/: 14 hand-rolled io.open(p,'wb'/'w') sites; lib/safewrite.lua is referenced from profiles.lua:48 and arbwatch only"
            }
          ],
          "corrections": [
            {
              "reviewSaid": "\"Three modules (gearui:1114, lockstyle:171, macrobook:56) bypass it and hand-roll the same answer anyway\" — presented under a heading about drift/divergence, and the task framing says \"a path that diverges is a latent bug\"",
              "actually": "All three compute the EXACT same path as statefile.charDir(). They are not drift, not a latent bug, and not a write-to-nowhere hazard. Each is a verbatim copy of the same 9-line body: pcall(require,'dlac\\\\profiles') → prof.dataDir() → else `<install>config\\addons\\luashitacast\\<Name>_<Id>\\dlac\\`. The one textual difference is that lockstyle/macrobook's fallback charBase() additionally guards `id == 0` and gearui's/statefile's do not — and that guard is UNREACHABLE in practice, because profiles.dataDir() answers first in every live case.",
              "evidence": "ui/gearui.lua:1114-1122 vs feature/lockstyle.lua:171-179 vs feature/macrobook.lua:56-64 vs lib/statefile.lua:27-42 — same delegation, same fallback string.format, same trailing 'dlac\\\\'",
              "impact": "The case for deepening statefile is DUPLICATION and the missing write half, not path divergence. Do not sell the refactor as a bug fix for these three — the fix is real but the payoff is 4 copies collapsing to 1, plus safewrite reaching 13 writers. Selling it as a divergence fix will make Henrik expect a behavior change and see none."
            },
            {
              "reviewSaid": "Divergence #2: \"feature/debug.lua:153-162 hardcodes the legacy home; ... in native mode the engine writes its half to the native home while the addon-side watcher reads the legacy one\" — blamed on feature/debug.lua",
              "actually": "Wrong file for the /dl check symptom. feature/debug.lua's charBase feeds only the LAC-BRIDGE files (debug-request.txt, debug-check-engine.txt, debug-ls-open.txt, debug-ls-engine.txt), and dispatch.lua:1799-1804 explicitly rules those stay at the char root as bridge protocol that \"leaves with LAC\". The actual /dl check native degradation comes from feature/check.lua:190-207, a SEPARATE hardcoded charBase copy that reads `base .. 'dlac\\\\modestate.lua'` for the engine version stamp while dispatch writes modestate through the mode-aware charDir().",
              "evidence": "feature/debug.lua:221-227 (requestEngine), :290-298 and :326-328 (handoff reads) — all bridge files; feature/check.lua:168-178 + :202-207 (modestate stamp read)",
              "impact": "Fixing debug.lua alone would not fix /dl check. The one-line fix is check.lua:203 → route through profiles.dataDir(). Also: check.lua:190-199's OTHER use of that same charBase (comparing seeded utils/dispatch/chatfmt/profiles copies) is CORRECTLY legacy-pinned — those are LuaAshitacast concepts. So check.lua's charBase must NOT simply be swapped wholesale; only the modestate read moves."
            },
            {
              "reviewSaid": "\"Same class, lower severity: check.lua:168, macrobook.lua:38/150, lockstyle.lua:141, augments.lua:332, gearexport.lua:217, gearui.lua:756\"",
              "actually": "That list mixes three unrelated categories. (a) macrobook.lua:150 is not a dlac storage path at all — it reads the GAME's own macro title files at `<install>..\\Game\\FINAL FANTASY XI\\USER\\<serverid-in-hex>\\mcr.ttl`. It can never be mode-aware and is not the same class. (b) macrobook.lua:38, lockstyle.lua:141, gearui.lua:756, augments.lua:332, gearexport.lua:217 are all FALLBACK arms inside ask-first composers — dead code whenever profiles.lua loads, i.e. always. (c) Only check.lua:168 is a genuine never-asks site.",
              "evidence": "feature/macrobook.lua:146-152 (`userDir = ...'..\\\\Game\\\\FINAL FANTASY XI\\\\USER\\\\%x\\\\'`, reading mcr.ttl/mcr_2.ttl); feature/augments.lua:318-336 and gear/gearexport.lua:200-218 both `if d ~= nil then return ... end` before the legacy compose",
              "impact": "The \"sweep every site\" scope is smaller than it looks. Roughly 11 of the ~37 GetInstallPath sites are ask-first fallbacks (delete them for free when statefile gets a write half), ~6 are addon-asset/debug-tree paths that are correctly install-relative (documented at architecture.md:44), and only ~3 are real never-ask offenders: setmanager.lua:55/505, check.lua:203, gearoptim.lua:2280."
            },
            {
              "reviewSaid": "setmanager \"Line 505 also does profileDir() .. 'backups\\\\' with no nil guard — it throws pre-login where every sibling returns nil-and-retry\"",
              "actually": "The missing nil guard is real in the function itself but UNREACHABLE from every shipped caller. All five call sites resolve a path and bail out first: commitSet→commitTarget returns 'not logged in (no profile path)' (setmanager.lua:565-566), deleteSet:614-615, renameSet:636-637, repairShims:534-535, deleteStaticSet:694-695. Pre-login, none of them reaches line 505.",
              "evidence": "gear/setmanager.lua:534-535, 565-566, 614-615, 636-637, 694-695 — every caller nil-checks M.jobPath(job) or _prof.setsPath(job) before backing up",
              "impact": "Don't present this as a live crash. It is a latent hazard worth one guard line, not a bug worth a fix commit on its own. The legacy-vs-native backup split in the SAME function is the part that actually bites a user today."
            },
            {
              "reviewSaid": "\"Grep finds 38 GetInstallPath sites in 22 files\"",
              "actually": "37 sites in 21 files excluding tests; 42 sites in 22 files including tests/run_tests.lua. One of the 21 files is dlacprobe/dig.lua — a SEPARATE addon that happens to live inside the dlac tree and is out of scope by the no-probing-in-dlac rule.",
              "evidence": "grep -rn --include=*.lua GetInstallPath . (excluding .claude/worktrees/, which contributes an identical 42 and doubles every count)",
              "impact": "Cosmetic, but the dlacprobe exclusion matters if anyone scopes a mechanical sweep by file list."
            },
            {
              "reviewSaid": "profiles.dataDir() described as the trustworthy \"ONE storage-home authority\"",
              "actually": "The authority itself has a gap the copies it replaced did NOT have: profiles.charIdentity() (profiles.lua:57-71) accepts `id == 0`, and charFolder() formats it as '%s_%u'. During the login window where the party manager reports a name but a still-zero server id, dataDir() returns `<Name>_0\\` and every writer in the addon writes there. The hand-rolled charBase copies in lockstyle.lua:140, macrobook.lua:37, check.lua:174 and debug.lua:159 all explicitly guard `id == 0` — but only in fallback arms that dataDir() short-circuits.",
              "evidence": "profiles.lua:57-71 (`if name == nil or id == nil then return nil, nil; end` — no zero check) and profiles.lua:74-78 (`string.format('%s_%u', name, id)`) vs feature/lockstyle.lua:140 `if name == nil or name == '' or id == nil or id == 0 then return; end`",
              "impact": "Centralizing MORE writers onto dataDir() concentrates this gap rather than closing it. Add the `id == 0` guard to charIdentity BEFORE (or as part of) the statefile write-half work, otherwise the deepening makes a Name_0 orphan folder more likely, not less."
            }
          ],
          "divergences": [
            {
              "site": "gear/setmanager.lua:42-56 profileDir() — and only that one",
              "whatsSpecial": "It is deliberately NOT mode-aware for its PRIMARY use: M.jobPath(job) → `<charBase>\\<JOB>.lua`, the LuaAshitacast job-file shim. profiles.lua:107-109 states the rule explicitly — \"LAC-only concepts (job-file shims, seeded engine copies) stay on charBase() unconditionally\". A one-size collapse onto dataDir() would move job shims into config\\addons\\dlac\\ where LuaAshitacast will never look for them. Only the :505 backups\\ use is wrong and must move to charRoot().",
              "evidence": "gear/setmanager.lua:57 `M.jobPath = function(job) local d = profileDir(); ...` vs profiles.lua:107-109 and profiles.lua:240-242 M.jobFilePath which also uses charBase() unconditionally"
            },
            {
              "site": "feature/check.lua:168-178 charBase()",
              "whatsSpecial": "Serves TWO callers with opposite requirements from one local. :190-199 compares the SEEDED library copies (utils/dispatch/chatfmt/profiles.lua) inside `<charBase>\\dlac\\` — correctly legacy-pinned forever, because seeding is a LuaAshitacast concept (dlac.lua:96-120 seeds only there). :202-207 reads modestate.lua — must become mode-aware. Swapping the whole function breaks the seeded-file check.",
              "evidence": "feature/check.lua:193-198 (`slurp(base .. 'dlac\\\\' .. f)` over SEEDED) vs feature/check.lua:203 (`loadfile(base .. 'dlac\\\\modestate.lua')`)"
            },
            {
              "site": "feature/debug.lua:153-162 charBase() and dispatch.lua:330-339 writeDebugHandoff",
              "whatsSpecial": "A PAIRED protocol across two Lua states, and the two halves already sit on different rules: dispatch writes handoffs through the mode-aware charDir(), debug.lua reads them at a hardcoded legacy path. dispatch.lua:1799-1804 rules the bridge family stays at the char ROOT (exempt from Henrik's debug\\-folder rule) because \"the whole family leaves with LAC\". Collapsing debug.lua onto dataDir() would fix the mode split but must keep the files at the char root, not move them into debug\\.",
              "evidence": "dispatch.lua:332 `local dir = charDir();` vs feature/debug.lua:223/293/302/327 `base .. 'dlac\\\\...'`; the exemption is spelled out at dispatch.lua:1802-1804"
            },
            {
              "site": "gear/gearoptim.lua:2270-2297 weightsPathFor / weightsPath",
              "whatsSpecial": "The only composer that must work for a FOREIGN character folder, not just the current one — it takes an arbitrary '<Name>_<Id>' so the Weights export/import can read another character's file. It therefore uses profiles.charDataDirAt(charFolder), NOT dataDir(). A statefile handle keyed on \"this character\" cannot serve it. It also builds its folder name as `tostring(name) .. '_' .. tostring(id)` rather than profiles' `string.format('%s_%u', ...)` — a second, independent folder-name formatter.",
              "evidence": "gear/gearoptim.lua:2275 `d = prof.charDataDirAt(charFolder);` and :2297 `return weightsPathFor(tostring(name) .. '_' .. tostring(id));` vs profiles.lua:74-78"
            },
            {
              "site": "feature/lockstyle.lua:128-132 fsp() at every io boundary",
              "whatsSpecial": "The only per-character writer that normalizes '\\' → '/' before touching the filesystem, so the headless suite can run it on Linux/WSL where '\\' is a filename character. Every other writer passes Windows paths straight to io.open. A shared statefile write handle must adopt fsp() (or the CI-parity rule silently regresses) — and note that lockstyle applies it at the io site, not in dataDir(), so the path VALUE is unchanged.",
              "evidence": "feature/lockstyle.lua:125-132 (DIRSEP/fsp) and its use at :336 `io.open(fsp(p), 'w')` and :760 `io.open(fsp(base .. 'lspreview.lua'), 'w')`"
            },
            {
              "site": "ui/automationsui.lua:129-136, ui/triggersui.lua:351-358, gear/syncflags.lua:53-61, ui/priorityui.lua:160, ui/setupui.lua:142/200/318/392",
              "whatsSpecial": "A FOURTH resolution style the review does not name: these do not require profiles at all — they take dataDir INJECTED through gearui's deps/D table, with `deps.charBase() .. 'dlac\\\\'` as fallback. They converge on the same answer but their seam is the deps table, so a statefile handle must either be injectable the same way or these modules gain a new hard require they currently avoid (they are UI modules loaded by uihost, deliberately dependency-light).",
              "evidence": "ui/automationsui.lua:130-135, ui/triggersui.lua:352-357, gear/syncflags.lua:55-60 — all `if type(deps.dataDir) == 'function'` first, `deps.charBase()` fallback; wired at ui/gearui.lua:1171 and :2254 and :4478"
            },
            {
              "site": "feature/helmwatch.lua:501 and feature/fishwatch.lua:510 (*_capture.txt), vs dispatch.lua:1806-1826 (debug\\mpwarm.txt)",
              "whatsSpecial": "Henrik's 2026-07-23 rule says per-char debug artifacts live in `<dataDir>\\debug\\`, and dispatch.lua is the ONLY module that complies (it even sweeps the pre-rule location). helmventures_capture.txt and fishventures_capture.txt still append at the char ROOT, in 'ab' mode with no rotation. A write-half module that hard-codes the char root for everything would cement the violation; one that routes everything through debug\\ would break the bridge files.",
              "evidence": "feature/helmwatch.lua:501 `io.open(dir .. 'helmventures_capture.txt', 'ab')`, feature/fishwatch.lua:510 same shape, vs dispatch.lua:1815-1820 `create_directory(dir .. 'debug\\\\')` + `io.open(dir .. 'debug\\\\mpwarm.txt', ...)`"
            }
          ],
          "openQuestions": [
            "profiles.charIdentity accepts id == 0 (profiles.lua:57-71) while four hand-rolled copies reject it. Has anyone field-seen a `<Name>_0\\` folder? If yes, that is the highest-value one-line fix in this whole area and it belongs BEFORE the statefile deepening, not after.",
            "gear/setmanager.lua:505 backups: should set backups move to profiles.charRoot() (matching gearimport.lua:993), or is the legacy pin intentional so backups survive flipping the engine flag back? profiles.lua:795-796 says \"Legacy files never move: flipping back finds everything where it was\" — which is an argument FOR the legacy pin. Needs Henrik's ruling, not a mechanical sweep.",
            "feature/check.lua:203 reads modestate from the legacy home. Is the fix (route through dataDir) enough, or does /dl check also need to say WHICH home it looked in? architecture.md already flags /dl check as native-degraded — is that note now the workaround for this exact line, and can it be deleted with the fix?",
            "No doc enumerates the per-character files. The closest is profiles.lua:200-202's docstring, which ends in a literal ellipsis (\"...watcher state files, debug handoffs...\"), and architecture.md:137 which names 5 of the 9 ensureStateFile statefiles. Should the statefile deepening produce a generated manifest (the module would know every name), and would that manifest also become the migration checklist engineMigrateStorage currently walks by directory copy?",
            "lspreview.lua (feature/lockstyle.lua:748-765) is a one-shot retirement writer whose own comment says \"Delete this once no pre-v42 seeded copies plausibly remain in the wild.\" It writes an otherwise-dead file to every character's home on every session. Is v42 old enough to delete now? It is one of the 37 files.",
            "accstate.lua is read by dispatch.lua:2247 but the comment at :2239 says \"on main nothing writes accstate.lua\" (the writer lives on feature/autoacc, GM-pending). Does it count as a per-character file for the manifest, or is it a read-only forward declaration?",
            "feature/debug.lua:238-256 writes its reports as `addons\\dlac\\debug\\<base>-<charName>.txt` — per-CHARACTER files in the ADDON tree, not the char tree. Deliberate (a git-checkout folder the user can find and attach to a report), or does Henrik's debug-folder rule intend these under <dataDir>\\debug\\ too?"
          ]
        }
      },
      {
        "key": "testinfra",
        "result": {
          "summary": "The review's premise is inverted. The suite is not save-blind: it already contains two full write-path tests that hit real disk (`SW` in run_tests.lua:5212-5264, and smoke_ui section 9 / goldenfixtures `captureManifest`), and a third that writes disk *by accident and never cleans up* (`LGF`, which rewrites a committed fixture on every run — I reproduced the CRLF/LF flip on both platforms). The quoted comment is at run_tests.lua:8575, not 8395, and it describes **one section** (ammowatch), not a suite-wide policy. The bigger correction: the `M._saveState` / `M._charDir` / `M._save` / `M._saveCraftState` \"test seams\" on all seven watchers are **export-only and inert** — every internal call site uses the local upvalue, so assigning to them redirects nothing. I proved this with a prototype on both Windows lua and WSL lua5.4. The working fs-injection route is to pre-seed `package.loaded['dlac\\\\lib\\\\statefile']` *before* `dofile`-ing the watcher, which I also proved works cross-platform. run_tests.lua's main chunk is at 186/200 locals (14 spare), so yes — new sections must be IIFEs, which is already the universal convention (94 of them).",
          "verified": [
            {
              "claim": "A comment reading \"Headless: charDir is nil, so every save is a silent no-op\" exists in run_tests.lua",
              "evidence": "C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac\\tests\\run_tests.lua:8575"
            },
            {
              "claim": "Something in the suite writes real files to disk during the run",
              "evidence": "tests/run_tests.lua:5222 (SW), :5388 (SF), :5552 (AR7), :9235; tests/goldenfixtures.lua:185-222; feature/lockstyle.lua:760 fires under LGF"
            },
            {
              "claim": "A fixture file's line endings are dirtied by running the suite on Windows",
              "evidence": "tests/fixtures/keepflow/config/addons/luashitacast/Testy_1234/dlac/lspreview.lua — measured 113 bytes (CRLF) after Windows lua, 109 bytes (LF) after WSL lua5.4, flipping on every run"
            },
            {
              "claim": "run_tests.lua's main chunk is near Lua's 200-local limit",
              "evidence": "tests/run_tests.lua — measured 186/200 used, 14 spare; the constraint is already documented in-file at tests/run_tests.lua:1638"
            },
            {
              "claim": "There is a recorded lesson that '\\' paths break Linux",
              "evidence": "docs/history.md:3921-3927, and the fix lives at feature/lockstyle.lua:126-132 (fsp)"
            },
            {
              "claim": "Modules are loaded with dofile, not require, in run_tests.lua",
              "evidence": "tests/run_tests.lua:10-20 (package.loaded pre-seeding via dofile) and ~40 per-section dofile sites e.g. :8579, :8668, :3463"
            },
            {
              "claim": "dispatch.lua carries a genuine headless charDir override seam",
              "evidence": "dispatch.lua:302-303 — the check is INSIDE charDir(), so assignment actually redirects; exercised at tests/run_tests.lua:5389, :5431, :5553"
            }
          ],
          "corrections": [
            {
              "reviewSaid": "The comment is at tests/run_tests.lua around line 8395.",
              "actually": "It is at tests/run_tests.lua:8575-8576. Line 8395 is `check('PX13 payload is gearweights-shaped', ...)` in the PX (profile-export) section, unrelated to saves.",
              "evidence": "tests/run_tests.lua:8575 — \"--     Headless: charDir is nil, so every save is a silent no-op -- the\" / \"--     in-memory jobsData is what's under test.\" It is the tail of the section header for \"AW. ammowatch\" starting at :8569.",
              "impact": "Anyone chasing the review's line number lands in the wrong section and concludes the seam is somewhere it isn't. The comment's scope is one module (ammowatch), attached to `local aw = dofile('feature/ammowatch.lua');` at :8579."
            },
            {
              "reviewSaid": "Implied: the suite has no answer for saves — every save is a silent no-op, so the write path is untested.",
              "actually": "The suite already has TWO deliberate, cleaned-up write-path tests against real disk, plus a third that writes uncleaned. What is untested is the *watcher* write path specifically, not \"the write path\".",
              "evidence": "SW section, tests/run_tests.lua:5212-5264 — header says \"Real files under tests\\ (cwd = addon root), removed at section end\"; it does `put(target, ...)`, calls `sw.replaceLua`, reads back with `get()`, asserts bytes (SW2 `check('SW2 new content live', get(target), 'return { new = true }\\n')`), and ends `os.remove(target); if bp then os.remove(bp); end os.remove(base .. 'sw_dst.lua');`. Second: tests/smoke_ui.lua:1010-1155 + tests/goldenfixtures.lua:174-230 — a real manifest is written by production code, re-read, and asserted (S160 `check('S160 rescan wrote a loadable manifest', chunk ~= nil, true)`).",
              "impact": "The design question is not \"how do we build a write-path test\" — it is \"how do we extend the existing write-path pattern to the watcher family\". Two working templates already exist to copy."
            },
            {
              "reviewSaid": "Implied by the seam naming: `M._saveState` / `M._charDir` are test seams that let a test disable or observe io.",
              "actually": "They are export-only handles. Every internal call site uses the LOCAL upvalue (`charDir()`, `saveState()`), never the `M.` field, so assigning to `M._charDir` or `M._saveState` redirects nothing. They neither disable nor observe. No test in the repo references any of them.",
              "evidence": "feature/ammowatch.lua:43 `M._charDir = charDir;` and :125 `M._saveState = saveState;`, but the call sites are `local dir = charDir();` (:54, :178) and bare `saveState();` (:190, 212, 248, 266, 273, 281, 289, 320, 334, 344, 372). Same shape in chocowatch:31/126, fishwatch:44/121, helmwatch:66/157, restockwatch:37/164, pinwatch:85 (`M._save = save`, callers at :102,116,125,132), craftwatch:418 (`M._saveCraftState`, callers at :444,459,503,515,523). Prototype run on Windows lua AND WSL lua5.4: reassigning `aw._charDir` after load -> \"redirected the write? false\" / \"ORIGINAL path still receiving writes? true\". `grep '_saveState|_save |_charDir' tests/*.lua` returns only `_charDirOverride` hits.",
              "impact": "A design that plans to inject through these seams will silently no-op and the test will pass for the wrong reason. They must either be deleted or converted to `if M._x ~= nil then` runtime checks (the dispatch.lua:303 shape)."
            },
            {
              "reviewSaid": "Implied: `_charDir` and `_charDirOverride` are the same kind of thing.",
              "actually": "They are opposites. `dispatch.lua`'s `M._charDirOverride` is checked INSIDE charDir at call time, so it genuinely redirects; the watchers' `M._charDir` is a copy of a function value and redirects nothing.",
              "evidence": "dispatch.lua:302-303 `local function charDir() / if M._charDirOverride ~= nil then return M._charDirOverride; end   -- headless test seam` vs feature/ammowatch.lua:43. The override is used for real at tests/run_tests.lua:5389 (`dispatchM._charDirOverride = 'tests\\\\';`) driving SF1-SF9 and AR7.",
              "impact": "`_charDirOverride` is the one proven-working precedent in the repo and is the shape any new seam should copy. Note it redirects the DIR only — the write still lands on real disk (SF/AR write and `os.remove` real files under tests/)."
            },
            {
              "reviewSaid": "Implied: the fixture dirtying is a Windows-only annoyance.",
              "actually": "It is bidirectional and reproducible: the file flip-flops on EVERY run and exactly one platform leaves it clean. The committed blob is LF; with core.autocrlf=true git expects CRLF in the worktree, so a Windows run (113 bytes, CRLF) reads clean and a WSL run (109 bytes, LF) shows ` M ... LF will be replaced by CRLF`. Nothing cleans it up — LGF has no teardown for this file at all.",
              "evidence": "Measured cycle: 113 bytes/clean -> WSL lua5.4 run -> 109 bytes/`M` + git warning -> Windows lua run -> 113 bytes/clean. Cause: feature/lockstyle.lua:757-766 `retireLegacyPreview()` does `io.open(fsp(base .. 'lspreview.lua'), 'w')` (TEXT mode) unconditionally on the first `ls.pump()`, which LGF calls at tests/run_tests.lua:8033. `base` is `tests\\fixtures\\keepflow\\...` because AshitaCore.GetInstallPath is stubbed at tests/run_tests.lua:7995.",
              "impact": "Any new write-path test that lands committed fixtures inherits this trap. The mitigation already in the repo is `.gitattributes` `tests/golden/*.golden -text` (goldens only) — the keepflow tree is NOT covered. Prefer writing to a tmp dir you create and delete (the tmp_golden / tmp_autogear pattern) over writing into a committed fixture."
            }
          ],
          "divergences": [
            {
              "site": "The watcher family (ammowatch, chocowatch, fishwatch, helmwatch, restockwatch, pinwatch, craftwatch)",
              "whatsSpecial": "Path comes from `lib/statefile.charDir`, captured as a LOAD-TIME upvalue. Injectable ONLY by pre-seeding `package.loaded['dlac\\\\lib\\\\statefile']` BEFORE the `dofile`. Patching the module table after load does nothing (the local already holds the old function value). All of them write with mode 'wb' — binary, so bytes are identical on Windows and Linux.",
              "evidence": "feature/ammowatch.lua:40-42 `local _sfok, _sfile = pcall(require, 'dlac\\\\lib\\\\statefile'); local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir or function() return nil; end;` — same 3 lines verbatim in chocowatch:28-30, fishwatch:41-43, helmwatch:63-65, restockwatch:34-36, pinwatch:37-39; craftwatch:95 names it `kiCharDir`. Writes: ammowatch:120, chocowatch:117, fishwatch:110, helmwatch:150, restockwatch:158, pinwatch:80, craftwatch:192/411/589 — all `io.open(p, 'wb')`. PROVEN injectable via pre-seeding: prototype printed \"A: charDir seen by watcher = tests\\tmp_probe\\\" / \"file written? true\" on Windows and \"tests/tmp_probe/\" on WSL."
            },
            {
              "site": "dispatch.lua (the engine half of the statefile seam)",
              "whatsSpecial": "Does NOT use lib/statefile — it has its own charDir, deliberately, so the two Lua states share files not code. It is the only site with a working runtime override. Mixed write modes: 'w' at :293, 'wb' at :334, and an append-or-truncate at :1820. Pre-seeding statefile has zero effect here.",
              "evidence": "lib/statefile.lua:9-12 \"The ENGINE'S half stays dispatch-local on purpose (charDir + ensureStateFile in dispatch.lua): the two Lua states share the FILES, not the code\". dispatch.lua:302-303 for the override; dispatch.lua:1820 `io.open(dir .. 'debug\\\\mpwarm.txt', _mpWarm.opened and 'a' or 'w')`."
            },
            {
              "site": "feature/lockstyle.lua",
              "whatsSpecial": "Three-way path resolution that no other module has: `profiles.lockstylesPath(job)` when the profiles module is loaded, else `legacyPath()` from AshitaCore.GetInstallPath. LGF must NIL OUT package.loaded['dlac\\\\profiles'] to force the legacy tier. It is also the only module carrying `fsp()` separator normalization. Writes with mode 'w' (text) — so its output is CRLF on Windows, LF on Linux.",
              "evidence": "feature/lockstyle.lua:320-346 `save()`; :128-132 `local DIRSEP = package.config:sub(1,1); local function fsp(p) if p == nil or DIRSEP == '\\\\' then return p; end return (p:gsub('\\\\','/')); end`; :336 `io.open(fsp(p), 'w')`; :760 same. tests/run_tests.lua:7985-7986 `local savedProf = package.loaded['dlac\\\\profiles']; package.loaded['dlac\\\\profiles'] = nil;   -- force the legacy-tier read (restored below)`."
            },
            {
              "site": "ui/automationsui.lua (and the UI family generally)",
              "whatsSpecial": "The ONLY write site with true constructor-style DI: the path is `deps.charBase()`, supplied through `M.init(d)`. This is why it is the one production writer with an end-to-end byte-level test. Writes with 'w' (text mode).",
              "evidence": "ui/automationsui.lua:44-46 `local deps = nil; function M.init(d) deps = d; end`; :61-64 `local function writeFileText(p, t) local f = io.open(p, 'w'); ... end`. Driven at tests/smoke_ui.lua:1047-1056 `aui.init({ charBase = function() return root; end, lookupByName = ..., ownedCounts = ..., playerJob = function() return 'BLM'; end })` then `aui.rescanAutogear()` at :1064."
            },
            {
              "site": "lib/safewrite.lua",
              "whatsSpecial": "The only tmp-write + parse-validate + os.remove + os.rename ladder in the repo, and the only place os.rename appears outside profiles.lua. It removes the target BEFORE renaming (Windows os.rename won't clobber; POSIX will) — a naive fs-injection layer that only intercepts io.open would leave this half unmocked and the rename would hit real disk.",
              "evidence": "lib/safewrite.lua:69-80 — `if chunk == nil then os.remove(tmp); return nil, 'temp failed to parse'; end ... os.remove(path); if not os.rename(tmp, path) then`. Its test (SW1-SW14, tests/run_tests.lua:5217-5264) is consequently full real-disk."
            },
            {
              "site": "profiles.lua",
              "whatsSpecial": "Carries the only dir-creation retry in the repo — it opens, fails, makes the directory, and reopens. Any fs seam that stubs io.open must reproduce the failure-then-success sequence or this branch is never exercised.",
              "evidence": "profiles.lua:172-179 `local f = io.open(p, 'w'); if f == nil then ... -- io.open never creates directories, and a FRESH install has no ... f = io.open(p, 'w');`. Also gear/gearoptim.lua:2713 carries the same warning in prose."
            },
            {
              "site": "tests/goldenfixtures.lua + tests/smoke_ui.lua section 9 (the golden round-trip)",
              "whatsSpecial": "Byte-identical goldens survive both platforms only because the WRITE ('w') and the CAPTURE READ ('r') are BOTH text mode, so Windows CRLF is inserted on write and stripped on read. The committed .golden is then read with 'rb' against a `-text` gitattribute. Break either half of that symmetry (e.g. capture with 'rb') and the goldens diverge across platforms.",
              "evidence": "ui/automationsui.lua:62 writes with 'w'; tests/goldenfixtures.lua:219 `local f = io.open(mpath, 'r');`; tests/smoke_ui.lua:1369 `local f = io.open(fixtures.pathFor(name), 'rb');`; .gitattributes: \"tests/golden/*.golden -text\" with the comment \"Never let git's autocrlf rewrite their line endings on Windows checkout, or the byte-identical assertion (smoke_ui section 12) would fail against a CRLF-mangled copy.\""
            },
            {
              "site": "The `dlac\\` literal in composed paths",
              "whatsSpecial": "`root .. 'dlac\\\\autogear.lua'` is ONE filename on Linux and a SUBPATH on Windows — so the golden harness has to mkdir a `dlac` subdir on Windows and not on Linux, and rmdir differently. Any new write-path test that composes a path with an embedded backslash inherits this.",
              "evidence": "tests/goldenfixtures.lua:179-183 `-- autoPath appends the literal 'dlac\\autogear.lua'. On Linux that is ONE / -- filename (backslash inside the name); on Windows the same string is a / -- subpath, so the dlac\\ directory must exist or the write silently fails.` then `if sep == '\\\\' then os.execute('mkdir \"tests\\\\tmp_golden\\\\dlac\" >nul 2>&1'); else os.execute('mkdir -p \"tests/tmp_golden\" >/dev/null 2>&1'); end`. Recorded in docs/history.md:4077-4078: \"`dlac\\autogear.lua` is one *filename* on Linux, a *subpath* on Windows — CI-green ≠ Windows-green on golden work.\""
            }
          ],
          "openQuestions": [
            "Should the seven inert `M._saveState`/`M._charDir`/`M._save`/`M._saveCraftState` exports be DELETED or CONVERTED? Converting them to the dispatch.lua:303 shape (`if M._charDirOverride ~= nil then return M._charDirOverride; end` inside charDir) makes them work with a one-line change per module and needs no test-load-order discipline. Deleting them is honest but throws away the only naming that says \"write path here\". Right now they are worse than either: they look injectable and aren't.",
            "Do we want the fs seam at charDir (path redirection, writes still hit real disk under tests/tmp_*) or at io.open (writes captured in memory, nothing touches disk)? Every existing precedent in the repo — SW, SF, AR7, golden — chose path redirection, and NO test anywhere stubs io.open (grep for `io.open =` in tests/ returns nothing). Path redirection also keeps `os.rename`/`os.remove` honest, which safewrite needs. Introducing an io.open stub would be the first of its kind.",
            "Should the LGF keepflow fixture stop being written to? Options: (a) have LGF point `retireLegacyPreview` at a tmp dir it deletes, (b) add `tests/fixtures/** -text` to .gitattributes so both platforms agree, (c) leave it. (b) is one line and matches the existing golden precedent, but doesn't fix that the suite mutates a committed file with no teardown.",
            "run_tests.lua is 11,397 lines / 186 of 200 top-level locals / 94 IIFE sections. smoke_ui.lua is 1,841 lines and only 120/200 locals — 80 spare. Should a new watcher write-path section go in smoke_ui.lua (real headroom, already the home of the one end-to-end writer test) rather than run_tests.lua? The counter-argument is that smoke_ui is billed as a LOAD test, not a behavior test — but section 9 already broke that framing.",
            "Is the pre-seed-package.loaded injection route acceptable given it must be UNDONE before the next section? run_tests.lua's convention is save-into-a-local-then-restore (`local _savedChatfmt = package.loaded['dlac\\\\chatfmt']` at :1642, restored at :1799; `savedProf` at :7985/:8023). A write-path section would need the same for `dlac\\\\lib\\\\statefile`, and it burns one of the 14 remaining top-level local slots unless the whole section is an IIFE — which it must be anyway."
          ]
        }
      }
    ]
  },
  "workflowProgress": [
    {
      "type": "workflow_phase",
      "index": 1,
      "title": "Recon"
    },
    {
      "type": "workflow_phase",
      "index": 2,
      "title": "Design"
    },
    {
      "type": "workflow_agent",
      "index": 1,
      "label": "recon:writers",
      "phaseIndex": 1,
      "phaseTitle": "Recon",
      "agentId": "a14eda9680e4d5d7a",
      "model": "claude-opus-5[1m]",
      "state": "done",
      "startedAt": 1784975143883,
      "queuedAt": 1784975141615,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "VERDICT ON THE NUMBER: the review's \"13\" is wrong by one — …",
      "promptPreview": "In the Ashita v4 addon at C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac, enumerate and characterise EVERY per-character state WRITE site. IGNORE .claude\\worktrees\\ entirely — it is a stale duplicate checkout that doubles every grep result.\n\nThe architecture review claims \"13 hand-rolled serialize -> io.open(p,'wb') -> write -> close blocks across 8 watchers\". Verify that number exactly and prod…",
      "lastProgressAt": 1784975649710,
      "tokens": 129590,
      "toolCalls": 46,
      "durationMs": 505827,
      "resultPreview": "{\"summary\":\"VERDICT ON THE NUMBER: the review's \\\"13\\\" is wrong by one — there are **14** hand-rolled serialize→`io.open(…,'wb')`→write→close blocks across the 8 named watchers, plus **2 plain-text `'ab'` APPEND writers in the same files** that the review missed entirely (16 write sites in the watcher family). The related sub-claim \\\"the other 12 write the live file directly\\\" is also off by one: …"
    },
    {
      "type": "workflow_agent",
      "index": 2,
      "label": "recon:safewrite",
      "phaseIndex": 1,
      "phaseTitle": "Recon",
      "agentId": "a06629b6fc19fbaf2",
      "model": "claude-opus-5[1m]",
      "state": "done",
      "startedAt": 1784975144027,
      "queuedAt": 1784975141616,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "SAFEWRITE IS NOT A DURABILITY LADDER — IT IS A *VALIDATION-…",
      "promptPreview": "In the Ashita v4 addon at C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac, read lib/safewrite.lua IN FULL and explain exactly what durability ladder it implements. IGNORE .claude\\worktrees\\ entirely — it is a stale duplicate checkout that doubles every grep result.\n\nAnswer precisely:\n1. Quote the whole module. What is the \"ladder\" — temp file + rename? fsync? retries? What happens at each rung wh…",
      "lastProgressAt": 1784975526839,
      "tokens": 83518,
      "toolCalls": 34,
      "durationMs": 382812,
      "resultPreview": "{\"summary\":\"SAFEWRITE IS NOT A DURABILITY LADDER — IT IS A *VALIDATION-AND-RESTORE* LADDER. There is no fsync, no retry, no rotation, and on Windows no atomic swap either.\\n\\n=== 1. THE MODULE (C:\\\\catseyexi\\\\catseyexi-client\\\\Ashita\\\\addons\\\\dlac\\\\lib\\\\safewrite.lua, 101 lines, ONE commit ever) ===\\nHeader (lines 1-32) declares three verbs — timestampBackup / replaceLua / verifiedMove — and state…"
    },
    {
      "type": "workflow_agent",
      "index": 3,
      "label": "recon:readhalf",
      "phaseIndex": 1,
      "phaseTitle": "Recon",
      "agentId": "a48e9ee7c36b6b6c5",
      "model": "claude-opus-5[1m]",
      "state": "done",
      "startedAt": 1784975144397,
      "queuedAt": 1784975141616,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "## The READ half of the statefile seam — verbatim record ##…",
      "promptPreview": "In the Ashita v4 addon at C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac, document the READ half of the statefile seam, which the architecture review calls deep and wants the write half to mirror. IGNORE .claude\\worktrees\\ entirely — it is a stale duplicate checkout that doubles every grep result.\n\n1. Quote dispatch._ensureStateFile (around dispatch.lua:408-424) IN FULL. Explain its signature, i…",
      "lastProgressAt": 1784975533886,
      "tokens": 97081,
      "toolCalls": 30,
      "durationMs": 389489,
      "resultPreview": "{\"summary\":\"## The READ half of the statefile seam — verbatim record\\n\\n### 1. `dispatch._ensureStateFile` — `C:\\\\catseyexi\\\\catseyexi-client\\\\Ashita\\\\addons\\\\dlac\\\\dispatch.lua:395-424` (docstring + body, IN FULL)\\n\\n```lua\\n-- ---------------------------------------------------------------------------\\n-- Cached per-character state-file reader -- the ONE implementation behind the\\n-- auto/acc/cr…"
    },
    {
      "type": "workflow_agent",
      "index": 4,
      "label": "recon:bypassers",
      "phaseIndex": 1,
      "phaseTitle": "Recon",
      "agentId": "a565cccc8081bc5de",
      "model": "claude-opus-5[1m]",
      "state": "done",
      "startedAt": 1784975143867,
      "queuedAt": 1784975141616,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "The three modules the review names (gearui:1114, lockstyle:…",
      "promptPreview": "In the Ashita v4 addon at C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac, investigate the modules that BYPASS lib/statefile.charDir() and hand-roll the per-character directory themselves. IGNORE .claude\\worktrees\\ entirely — it is a stale duplicate checkout that doubles every grep result.\n\nThe architecture review names three: gearui.lua:1114, feature/lockstyle.lua:171, feature/macrobook.lua:56. …",
      "lastProgressAt": 1784975532908,
      "tokens": 116378,
      "toolCalls": 51,
      "durationMs": 389041,
      "resultPreview": "{\"summary\":\"The three modules the review names (gearui:1114, lockstyle:171, macrobook:56) DO bypass `lib/statefile.charDir()` — but all three compute the IDENTICAL path. They are byte-for-byte the same \\\"ask `profiles.dataDir()`, else compose the legacy home inline\\\" body as statefile itself. That is duplication (4 copies of a 9-line function, plus ~7 more variants), not divergence — no latent wri…"
    },
    {
      "type": "workflow_agent",
      "index": 5,
      "label": "recon:testinfra",
      "phaseIndex": 1,
      "phaseTitle": "Recon",
      "agentId": "a8048b9c15c2eec37",
      "model": "claude-opus-5[1m]",
      "state": "done",
      "startedAt": 1784975144305,
      "queuedAt": 1784975141616,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "The review's premise is inverted. The suite is not save-bli…",
      "promptPreview": "In the Ashita v4 addon at C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac, work out how a write-path test would actually be built, given the suite as it stands. IGNORE .claude\\worktrees\\ entirely — it is a stale duplicate checkout that doubles every grep result.\n\n1. Read tests/run_tests.lua around line 8395 — the review quotes a comment \"Headless: charDir is nil, so every save is a silent no-op.\"…",
      "lastProgressAt": 1784975594450,
      "tokens": 110661,
      "toolCalls": 43,
      "durationMs": 450145,
      "resultPreview": "{\"summary\":\"The review's premise is inverted. The suite is not save-blind: it already contains two full write-path tests that hit real disk (`SW` in run_tests.lua:5212-5264, and smoke_ui section 9 / goldenfixtures `captureManifest`), and a third that writes disk *by accident and never cleans up* (`LGF`, which rewrites a committed fixture on every run — I reproduced the CRLF/LF flip on both platfor…"
    },
    {
      "type": "workflow_agent",
      "index": 6,
      "label": "design",
      "phaseIndex": 2,
      "phaseTitle": "Design",
      "agentId": "a4828ab240a41fc24",
      "model": "claude-opus-5[1m]",
      "state": "done",
      "startedAt": 1784975654080,
      "queuedAt": 1784975651764,
      "attempt": 1,
      "lastToolName": "Bash",
      "lastToolSummary": "cd \"C:/catseyexi/catseyexi-client/Ashita\" && ls addons/ 2>/…",
      "promptPreview": "You are the lead engineer on the Ashita v4 FFXI addon dlac (C:\\catseyexi\\catseyexi-client\\Ashita\\addons\\dlac).\n\nA parked architecture review proposed candidate #2: give lib/statefile.lua a WRITE half —\n  statefile.open(name) -> { read(), write(tbl) }\na handle owning the path, one serializer, the lib/safewrite atomic ladder, and an injectable fs for tests. Claimed wins: 13 writers collapse to 1, 13…",
      "lastProgressAt": 1784975962002,
      "tokens": 95808,
      "toolCalls": 11,
      "durationMs": 307921,
      "resultPreview": "## A) VERDICT\n\n**Proceed — but the review's two headline wins are both wrong, and one of them is inverted. Candidate #2 survives as a *path-collapse and testability* move, not as a durability move.**\n\nThree things I measured myself (Windows Lua 5.4, `C:\\Users\\Henrik Johansson\\AppData\\Local\\Programs\\Lua\\bin\\lua.exe`, cwd = addon root):\n\n1. `os.rename('b','a')` where `a` exists → `nil  File exists  …"
    }
  ],
  "totalTokens": 633036,
  "totalToolCalls": 215
}