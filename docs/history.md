# dlac — Project history & session journal

> What happened, in order, with the reasoning that is NOT recoverable from the code.
> Sources: git history + mined Claude Code session transcripts (2026-07-10).
> New sessions: append a section here when a work block lands; keep the same headings.

The project was born 2026-07-09 and reached its current shape in two days of intense
Henrik+Claude sessions, several running in parallel on the same checkout.

## Day 1 (07-09) — bootstrap era *(documented from git log only; no transcripts survive)*

Initial import of the pre-dlac profile code ("ffxi-lac") into an addon: entry point,
per-char gear loading, Sets tab reading `sets.Dynamic` from `<JOB>.lua` on disk, path
fixes for running without `gState` (party manager fallback), full catalog crawl
(~1.7k → 14.9k items), Setup button (fresh profiles based on LAC's `/lac newlua`
skeleton + dlac wiring; migration keeps player code), library seeding into
`<char>\dlac\`, stats moved 100% to the catalog (scanner stopped parsing them), add-only
auto-sync on job change, first augment id→stat maps.

## Session "augments → stat standard" (08a38488)

**Theme:** decode a friend's augment dump; then a full stat-vocabulary standardization
with Henrik ruling on every name ("if there is ANYTHING people will complain about, it
is this").

**Landed:** 58 of 64 unknown augment ids resolved (LSB `augments.sql`, then confirmed by
CatsEyeXI's own `enum_augment_name` from the private server repo — the remaining 6 are
undefined no-op gaps, do not chase); augment display value = base-in-name + tier (SCALE
table); full AUG_NAME regeneration (~328 ids). Debug flag persistence
(`<char>\dlac\uiflags.lua`); stat-weights GUI moved to its own window, integer inputs,
searchable stat dropdown. Crawl-side: `apicrawl.py` taught to emit ignored-mod reports;
14,874 items cached; 574 unmapped mods triaged to 105 real stats; `statdefs.lua` grown
49 → 178 entries with Henrik's naming standard (extreme abbreviations for extremely
common terms: PDT/MDT/DT/MDMG/MAB/MACC canonical, descriptive forms as aliases).
`tools/` untracked+gitignored (privacy; history rewrite declined).

**Key decisions:** authority chain for augments (server enum > LSB SQL > wiki; the enum
must never be committed); non-linear augment ids stay display-only (would corrupt worn
totals); 311 = flat Magic Damage (MDMG), NOT Magic Attack Bonus; ThunderResistance not
LightningResistance (reuse existing keys, never invent parallels); status resists verb
style (ResistPoison); lowerBetter flags so positive weights reward reductions; statdefs
carries no server mod-ids ("I don't think the server wants to expose it") — the
mod→key bridge lives in gitignored `tools/api_cache/stats_decisions.txt`.

**Field-verified:** DT-family mods and SkillchainDamage are stored ×100 (Defending Ring
= −1000); TP_BONUS 345 is literal TP; 1472 is Parrying *rate*.

**Dead ends:** asking what the 6 unknown augments "read in-game" (they're gaps); live-API
fetching when `apicrawl.py` exists ("Calm down, we already have a python script").

**Follow-through (landed in later commits):** the three wiring tasks — crawler CORE
expansion (ed97adb, 96f113c), catalog/statdefs review (1971bb0), weights picker via
statdefs (9099837). Still open from this session: stat hover descriptors (text ready in
`tools/api_cache/stats_tiers.txt`); augment decoder boundary fix (stop at first 0x0000
word — verify against real scans first).

## Session "trigger system day" (96c90bd5 — the big one)

**Theme:** opened with `/grill-with-docs` — "challenge me properly, it is important to
get this right." Full design → ADRs 0001-0004 + glossary + trigger-system.md + 13 GitHub
issues → same-day implementation of the engine, Triggers tab, automations, modes — then
storage-move research and the gearmove branch. Henrik's product rule, verbatim:
**"nothing that this addon makes should force a player to use lua files or edit them
manually."** And the working agreement: **"don't ask for permissions to edit files
within the addon, you are the maintainer IMO, I am just the one with the creative
vision."**

**Landed (chronological):** dispatch engine (data-driven triggers, hot-reload, `/dl
mode|why|triggers`); Triggers tab + convert-in-place Setup (per-handler health check,
append-only shims, `.flbak` + rotated backups); LuaJIT 200-local cap forced the
triggersui split; automations saga — ADR 0004 revised 4×: global toggles → per-set
flags → **virtual slot entries** (`dlac:AutoStaff`/`dlac:AutoObi` living IN the set,
Henrik's "maybe it's simpler to handle this as a slot function?"), tiered Iridescence
(NQ+1/HQ+2 elemental, universals; ties to universal), level-gating with best-by-level
fallback; `contains` condition + AND-stacking; universal Hachirin-no-obi reality;
manifest auto-regen on login/job change; picker DB from the server's public SQL
(Pianissimo is BRD 20 here vs retail 45); README rewrite; cycle modes replacing the
hand-written variant-table pattern (keybinds, builder popup, from→to prints, VERSION
staleness banner); `/dl why` per-slot attribution; level-scaling (31 items from
`item_latents`); catalog stat keys 41→176; engine-owned slot locks (LAC forgets
`/lac disable` on reload); `/dl prune`; all-container ownership + red stored names +
container-naming tooltips; quiet auto-sync; DW from live memory (`HasAbility(1554)`);
CatsEyeXI jobs reference from BG-wiki; storage-move research + live packet probe
(dlacprobe) + gearmove v1→v7 + gearcheck on `feature/storage-move`.

**Key decisions:** see ADRs 0001-0004 (all written this session) and
docs/design/storage-move.md. Highlights not in the ADRs: modes are session-only (all
OFF / first cycle value at login — "no surprise DT-mode from last Tuesday"); trigger
Commit is live but set Commit needs Reload LAC (accepted asymmetry); storage-move gate
is client-side and fail-closed, trusting only 0x00A LoginState (the memory MH flag is
field-falsified — ACE `!mog` flips it anywhere); feature/storage-move stays local
pending GM approval; gearcheck deliberately self-contained for cherry-picking; move UI
only in the All Equipment browser, equipped gear green + blocked.

**Field-verified (live CatsEyeXI):** trigger hot-reload end-to-end ("I can do pianissimo
and it changes even without reload lac, incredible"); ACE `!mog` falsifies the memory MH
flag; **Provenance broadcasts MogZoneFlag=1 — the live DB diverges from every public
repo branch**; Safe↔Inventory moves work at the Provenance hub today; Storage absent
from the hub moogle menu; 0x029 packet layout byte-for-byte, ~150 ms confirm, silence =
rejection; ~900 item packets flood zone-in; Chatoyant Staff carries Iridescence +2;
Blade Madrigal is Thunder element; LAC only re-requires seeded files on ITS reload.

**Dead ends (do not retry):** codegen for triggers (ADR 0002); global automation
toggles AND per-set SetOptions (both fully built, then deleted — the SetOptions
serializer also caused the flag-wipe bug: fileToModel must carry ALL sections);
Iridescence-as-suppression (inverted — Chatoyant IS the auto staff);
eight-era-elemental-obi assumption; right-click context menus in this ImGui binding
(two failed rounds → Trove-style `[mv]` left-click button); LAC memory MH flag as a
gate; nomad-moogle interaction gating (access is zone-wide; 0x02E has no close event);
inventory-hop move routing (direct is legal); `/lac disable` slot locks;
catseyexi.com API for spells/abilities (items only); public repo SQL for job mechanics
(byte-identical to stock LSB — customization lives in private submodules; trust ladder:
live memory > BG-wiki > public SQL).

## Session "offhand" (f3c35992)

**Theme:** "I can't set off-hand weapons… you should still be able to build what you can
wield in sub as long as it is one-handed. Then the logic if you have dual wield or not
should decide." Established the **"builder is a plan, the engine decides"** principle
(ADR 0006), lifted from Henrik's old ffxi-lac code.

**Landed:** builder DW gate removed (Add popup passes `building=true`; the
immediately-equipping Alternatives list keeps the gate); `BuildDynamicSets` resolves
Main before Sub explicitly (pairs() hash order starved Sub); `jobCanEquip` honors the
support job; `utils.subSlotAllowed` as the one shared pairing rule;
`utils.classifySub` (catalog says `Type="Sub"` for shields AND grips — classify by "*
Grip"/"* Strap" name); `subCandidatePool` (1H Main-slot weapons now reach the Sub
picker); `/dl fix` backfills Type/OneHanded into gear.lua (the LAC-state engine reads
raw gear.lua and never sees GUI enrichment); `/dl dw` probe; comment-aware shim parser
(commented-out handlers no longer wedge Setup — they count as missing and get a fresh
shim); Reload LAC clears the setup status line; chat overhaul (chatfmt.lua palette,
print-shadowing, coral vs LAC's teal, quiet routine loads); author/license = Mindie,
MIT. Headless test suite born this session (`winget install DEVCOM.Lua`;
`tests\run_tests.lua`, 21 → 44 checks).

**Key decisions:** asymmetric gating (planning permissive, immediate-equip strict);
Auto-build stays equip-correct (shield when no DW) — making it permissive is an open
user decision; repairer's conservatism preserved (fix the parser's honesty, not the
repairer's caution); commented-out player code is never uncommented.

**Dead ends:** fixing only the visible filter (the pool and metadata upstream still
blocked everything — trace the full pipeline: pool → metadata → vocabulary → filter);
chasing "still prints" ghosts (stale LAC memory state, not code).

**Open:** `/dl dw` positive-case verification on an actual DW job (the trait bit has
only ever been observed false; if NIN main shows shield-paired, suspect a HasAbility
id-cap and reprioritize the fallback).

## Session "GM feedback & prune" (c89bcd85 — this one)

**Theme:** polish while a GM evaluates the addon for approval; then this documentation
effort.

**Landed (main):** word-wrap for long status lines (GM feedback — `textWrapped` helper);
`/dl prune` parser made comment-tolerant (25 of 637 real gear.lua entries had trailing
`-- comments` on their headers and were invisible to prune/fix/dedupe); `/dl prune why
<item>` per-container ownership probe; scan messages updated to the all-container
reality (ADR 0005). Meanwhile a parallel session ran the gearui modularization
(profilesets/gearfmt/cmdqueue extractions, locals 200 → 180) on feature/storage-move.

**Key decisions:** delete-and-regenerate gear.lua rejected — nothing recreates a missing
gear.lua (the commit pipeline aborts), and regeneration would lose deep-storage entries;
prune is the tool. Brigandine's survival was a genuine ownership match, not a bug — use
`/dl prune why` before assuming.

## Standing loose ends (as of 2026-07-10, end of day)

- **feature/storage-move**: local-only, awaiting GM verdict. Before any merge: strip the
  TEMP probes (`/dlmv`, RMB debug experiment, branch-print). gearcheck (v8) is
  cherry-pickable independently. The Storage-into-Provenance 0x029 experiment is
  designed but unrun.
- **`/dl dw` positive case** never observed live (see offhand session).
- **GitHub issues open:** #8 multi-mark browse-assign; #9 in-GUI `/dl why` panel;
  #12 wire spells.lua/abilities.lua into the Triggers tab pickers; #13 polish
  (Sets-tab trigger cross-ref, mode mini-HUD, user docs).
- **Picker DB corrections:** ~40 ability/spell levels differ from the wiki — planned
  wiki-sourced overlay (list in docs/reference/catseyexi-jobs.md "dlac impact").
- **Stat hover descriptors** (text ready in tools/api_cache/stats_tiers.txt).
- **Iridescence detection**: replace triggersui's curated UNIVERSAL list with a catalog
  `Stats.Iridescence` scan.
- **TPBonus display scale** decision open (server stores 1000 = +100 TP).
- **Auto-build permissiveness** (plan-style like the Add popup?) — open user decision.
- **Augment decoder boundary** (stop at first 0x0000 word) — verify before changing.
- dlacprobe addon dormant at `Ashita\addons\dlacprobe\` — reuse for packet questions.
