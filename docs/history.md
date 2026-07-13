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

**Correction (07-11, field-falsified):** this session's "main OR support job wields
it" rule in gearui's `jobCanEquip` was wrong on CatsEyeXI — RDM74/WHM37 cannot wear
Hlr. Bliaut +1 (WHM Lv74); another job's gear stays unwearable even with that job
subbed. Wearability is MAIN job only (as gearoptim's `jobAllowed` always had it).
The sub job still legitimately feeds Dual Wield detection for off-hand pairing.

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

**Late additions (same day):** CTRL+K GUI keybind; partyfinder-matched window theme
(uistyle.lua); branch hygiene restored (modularization + theme + gearcheck promoted to
main; feature/storage-move = exactly gearmove again); **mode-gated set entries** — a
slot-list entry can carry `mode = 'Weapon:Melee'` (wrapper form, like
minLevel/maxLevel, now GUI-editable via the `~` button): active-mode entries OUTRANK
unconditional ones, inactive ones are excluded, so ONE set adapts per mode instead of
mode-switched set pairs. Same matcher as trigger `mode` conditions
(`dispatch.modeActive`, VERSION 5); the GUI previews against the modestate mirror. Also
fixed: the engine's wrapper merge mutated the SHARED gear.lua record (an item wrapped
differently in two sets leaked fields between them) — it now merges onto a copy.
Tests G1-G12 (the suite now loads the real dispatch.lua headlessly).

## Session "crafting system + catalog pipeline" (2026-07-11 → 07-13, on `main`)

**Theme:** a long multi-day arc — hardened the catalog/data pipeline, shipped the whole
crafting-gear system (detection → manual craft bar → engine overlay → guild-points/key-item
panel), and fixed several load-bearing bugs. All landed on **`main`** and pushed to GitHub
(`henkpoa/dlac`). `feature/storage-move` stays local, untouched.

### Catalog & data pipeline
- **Distribution model, ruled by Henrik (memory: catalog-distribution-model):** the addon
  MUST NEVER fetch from the API at runtime. Only Henrik scrapes (`tools/apicrawl.py`), ships
  `catalog.lua` in the addon update; the ONLY live-parsed data is augments. Client-side
  fetching was rejected a 2nd time — do not re-propose.
- `apicrawl.py` gained `--gaps` (fetch ids in every char's `<char>\dlac\gear.lua` the cache
  lacks/has as 404 — the fix for "new item shows no stats") and `--refresh N` (re-fetch cache
  older than N days). `equipment_ids.txt` is a STATIC retail-era dump; CatsEyeXI customs
  (e.g. Hieratic Ring 23994, and the 39xxx block) aren't in it → `--gaps` or a GM
  `SELECT itemid FROM item_equipment` dump, or a full `--range` sweep. **Item ids are u16
  (cap 65535)**; 28671 = end of retail equipment DAT block; customs live in unused holes
  (23994) and past the end (39xxx).
- **Reproducibility bug fixed:** DT-family mods are mixed-scale (percent×100 vs literal) —
  the builder now applies the `|v|>=100` rule (same as SkillchainDamage) so a rebuild
  reproduces `catalog.lua` byte-for-byte. Per-item desc-vs-DB drift fixups live in
  `MOD_STRIP`/`MOD_ADD` (Neph. Grip 22198 has phantom craft mods; Hocho/Debahocho lack
  their Cooking mod) — KEEP IN SYNC across apicrawl.py + apiscan.py. Report drift to GMs.

### Crafting stat family
- Mapped (Henrik-approved names): 8 craft skills (`WoodworkingSkill`…`CookingSkill`),
  `SynthHQRate`, `SynthMaterialLoss`, `AntiHQ<craft>` (×8), `ConserveIngredient`
  (CatsEyeXI custom **modid 2016**). `AntiHQ` = a hard "Cannot Synthesize HQ" block.
  Universal pieces carry all 8 per-craft mods individually (there is NO single "all
  crafts" mod). gearfmt collapses uniform 8-way families to "All Craft Skills+2" /
  "All Anti-HQ+1" for display only.

### Craft gear system (the big one)
- **Detection** (`craftwatch.lua`): c2s `0x096` (synth confirm) → crystal+ingredient
  multiset → `crafts.lua` (9,470 recipes, `tools/gen_craftdb.py` from the server's
  `synth_recipes.sql`) → craft skill. **Binding-craft/tier calc:** subcraft recipes carry
  a `skills` map; the craft with the smallest player-skill margin limits the HQ tier
  (breaks at >11/>31/>51). Detection is now **INFO ONLY**.
- **DEAD END — auto-equip by detection:** `0x096` is the FIRST packet the synth flow emits
  (crystal use + ingredient placement are client-local), so nothing can dress you for the
  synth that triggered it. Do not revive detection-driven equipping.
- **MANUAL model (Henrik's design):** the floating **craft bar** (`craftbar.lua`, toggle
  `/dl craft bar` or the header helmet icon) + the Automations→AutoCraft panel let you pick
  a craft + goal (**hq / nq / skillup**) and flip an on/off switch. craftwatch WRITES
  `<char>\dlac\craftstate.lua` (`{craft, goal, enabled}`); state persists (enabled is
  session-only, starts OFF).
- **THE architecture — engine OVERLAY (dispatch v31):** don't fight the engine, BE it.
  `dispatch.craftOverlay` reads `craftstate.lua` and, on every Default dispatch, overlays
  the resolved craft gear (`dlac:AutoCraft` per slot from the manifest craft ladders) LAST
  = top priority, even with no trigger match. So the engine WEARS the craft gear; nothing
  reverts it; switch off → overlay gone → normal Default returns.
  - Why not commands/locks: `/lac disable` blocks `/lac equip` on that slot; `/dl lock` is
    set in the ADDON state and its command is `e.blocked` before reaching the LAC state that
    does the revert. Both dead ends — the overlay is the answer.
- **Manifest craft ladders** (`triggersui.lua` autoCommit, `AUTO_FMT` now 6): per slot →
  craft → goal, best-first. Skill-up items (Midras's Helm, Bonze Cape, Shapers Shawl) fill
  hq/nq slots as LOW-priority fillers (`floor(gain*0.3)`, always < a skill=1 item's 10) so
  a real craft-skill item (Chef's Hat for HQ head) still wins.
- **THE bug that hid #2 for many rounds (hard rule 8):** `autoCommit` read `CRAFT_UI.goal`,
  but `CRAFT_UI` is a `local` declared LATER in the file → nil global → `.goal` threw →
  `rescanAutogear`'s pcall swallowed it → the manifest never regenerated past `fmtver 5`
  (whose head/back only had the skillup goal). Forward-reference to a later local = silent
  nil global. Fixed; watch for this class.

### Key items & guild data
- **SDK `HasKeyItem` is DEAD on this client** (returns empty bitfield; field-verified,
  "owned total 0"). craftwatch keeps its OWN key-item table from **s2c `0x055`** (FindAll's
  pattern: `u32 header | avail[0x40] | examined[0x40] | blockOffset`; id = block*512 + bit),
  persisted per char (`keyitems.lua`) so it survives reloads without a zone. KI names
  resolve via the client's own strings; the guild-KI panel lists desynth + recipe skills +
  Way-of-the per craft (ids from the server `key_item` enum), ownership from the tracker.
- **Guild points per craft:** s2c **`0x113`** (currencies_1), 8 int32 LE at absolute
  offsets `0x24..0x40` ('Weaving' = Clothcraft), persisted (`guildpoints.lua`). Fetched by
  sending header-only c2s **`0x10F`** ourselves (server `validate()` ungated — exactly what
  opening the currency menu does). **MANUAL ONLY** right now (`/dl craft gp`) pending
  Henrik's turn-in verification — see Standing loose ends. Offsets locked by tests T27–T33.

### UI / misc
- Sets: **duplicate-row button (D)** — one item across several level ranges (Rajas 30-54,
  Lava's 55-74, Rajas 75+); prominent `[Lv 30-54]` badges (green = live now).
- **Sub-slot HARD RULE (reverted 3×, ADR 0006 addendum, memory: sub-slot-building-never-gated):**
  while BUILDING, the Sub picker ALWAYS offers every shield/grip/one-hander — never gate on
  DW / Main shape / empty Main. The `A* HARD RULE` tests fail on any re-gating.
- Set-entry names resolve **case-insensitively**; a missing name warns ONCE (not per rebuild).
- Augment stats now show (gold `Aug:` tag) in Sets rows, the +Add picker, and Alternatives.
- Header: Macro button → small book icon; new craft-bar helmet toggle. `filetex.lua` loads
  `assets/*.png` (MUST retain the texture object — storing only the numeric handle GC'd the
  texture and hard-crashed the game on ImageButton).
- Craft glyphs: FFXIV Set-8 class icons in `assets/craft/` (Miner = Bonecraft). Panel craft
  icons are a VIEW-ONLY section switch (centered, no label); the craft BAR sets the active
  craft. Artisans Torque/Ring owned ⇒ the guild torques/rings show green (synergy implies
  you owned them all).

**Test suite: 189 checks, all green.** Sections T (craftwatch), V (AutoCraft overlay
resolution), W (tier/binding calc) added this arc.

## Session "field-hardening marathon" (c89bcd85 continued, 2026-07-11 → 07-13, on `main`)

**Theme:** Henrik live-tested everything on WHM/BRD/SMN and every report became a
same-hour fix with a pinned regression test. Engine VERSION 12 → 29. Ran **in parallel**
with the crafting session above — two Claude sessions committing to the same checkout
and to `main` simultaneously (expect branch flips, swept working-tree edits, and version
numbers claimed under you; always re-read files after any git operation).

**Max-MP grew up, then stepped back into the shadows (v13, fmtver 2-4).** Four field
bugs in one report: the manifest derivation read `gData` (which DOES NOT EXIST in the
addon state — job was always nil, only All-jobs gear passed); single level-99-checked
picks had no fallback (Bunzi's Robe blocked the whole body slot at RDM74) → per-slot
LADDERS picked at live level (`dispatch.mpPick`, K-tests); MP-EQUIP only touched slots
the dispatched set wrote → coverage pass for unaddressed slots; Convert and level-scaled
MP now count (Tamas Ring 15→29@74, via THE central `levelstats.effective` resolver —
gearui/gearoptim/triggersui all delegate; L-tests). Verdict: picks now believed right,
but MaxMP is **unlisted from the Automations table** (unofficial pending more
troubleshooting; `/dl mode maxmp` + manifest data + detail view all still work).

**The engine tick (v15) — the biggest architectural change.** LAC only parses
HandleDefault while OUTGOING packets flow; standing still in a menu starved dispatches
(first misread as an equip-menu block — **field-falsified**: `/lac equip` works with the
window open; v14's pause was removed). A throttled d3d tick in the LAC state now drives
`gState.HandleEquipEvent('HandleDefault','auto')` every 0.4s — menus open, standing
still, whatever. It also: drops maxmp on job change, skips while ZONING (v24 — the tick
otherwise crashed legacy profiles in LAC's equip.lua mid-zone), and synthesizes
PetAction (below).

**Modes are dlac-owned now (v15-v17).** modestate.lua is written on change AND read back
on engine load (same-job + 1-hour freshness guards — a mid-session Reload LAC heals,
last Tuesday's DT-mode stays dead). The v16 "stale cycle value purge" was
**field-falsified on WHM**: mode DEFINITIONS are per-job trigger data but VALUES are
session-global by design ("WHM Weapons" defined in BRD's file gates WHM's sets) — purge
removed (v17), setMode hardened (cross-job value jumps work; bare flips can't
toggle-corrupt a foreign cycle value; M-tests). Mode keybinds queue ONCE per session
(v18 — the automations rescan pings '/dl triggers reload' constantly and re-parsing
re-queued /bind forever). Mode DELETE is reference-aware (v16): a movable window lists
every rule and set-entry reference with one-click cleanup; delete commits immediately
and clears the live flag.

**Virtual markers hardened (v19, v20).** The Sets tab commits a GATED virtual as
`{gear="dlac:AutoIridescence", mode="Weapon:Caster"}` — BOTH utils' flatten (v19,
N-tests) and gearui's resolveSetItem (v20) only recognized bare strings; the wrapper
form vanished/flattened to nothing. A Main staff marker now pairs as a 2H staff so
grips stay legal in Sub (P-tests), gets an 8-element wheel icon (drawn, no texture),
and the automations derivation is JOB-CHECKED like everything else (Foreshadow +1 is
BLM/DRK — it sat in WHM's manifest looking dead; fmtver 4, red rows for
owned-but-wrong-job in the detail views).

**Reload LAC is nearly extinct (v21-v22).** Henrik's insight: gProfile.Sets is a live
Lua table — the reload was only ever about the FILE changing under it. '/dl sets reload'
re-reads <JOB>.lua SANDBOXED (profilesets' extractor hardened for the LAC state: gFunc/
AshitaCore/package/print/coroutine stubbed, stub __concat survives the boot line's
path-building) and swaps .Dynamic in place + re-flattens. The GUI pings it on every set
Commit/Delete. Reload LAC remains for: engine updates (version banner) and failed swaps.

**Level ranges own their windows (v23).** Garrison Tunica +1 ranged 20-51 lost to an
unbounded Lv48 robe at 50 — ranged-and-live entries now form a tier above unbounded ones
(engine + GUI preview mirror, Q-tests). A header `Lv <n>` button overrides the main
level for testing/preparing (addon global + '/dl set level main' for the engine; `*`
while active).

**Trigger rules: multi-set + searchable (v25).** One rule may wear an ORDERED list of
sets (`set = { 'WindSkill', 'Madrigal' }` — the Madrigal case), applied later-overlays-
earlier per slot; rule boxes grew reorder arrows and per-name [missing] checks
(R-tests). All set pickers are searchable — built as button+popup (InputText inside
BeginCombo kills clicks on this imgui build) — and every list row's imgui id must carry
the NAME (a shared '##..._o' suffix made only the first row clickable).

**PetAction — pets work now (v26, v27, v29).** NO LuaAshitacast version calls a pet
handler (the upstream tutorial's HandlePetAction says "you'll have to call it yourself"
— it's a DIY pattern); dlac's tick IS that pattern: dispatches 'PetAction' once per
pet-action start (ctx from gData.GetPetAction — Name/Skill/Element shape, matchers just
work; S-tests). Two field bugs: equips must be BRACKETED (gFunc.EquipSet only writes
LAC's buffer; the tick wraps ClearBuffer→dispatch→ProcessBuffer, v27) and the
Default-hold must cover LEGACY profiles (gState.HandleEquipEvent wrapped once: while
the pet acts, HandleDefault is skipped entirely — a hand-written SMN profile stomped
the pact gear every tick, v29). **Field-verified end to end: Shining Ruby equips,
holds, releases.**

**Files & data:** login dup-burst root-caused (pre-login addon load left the EMPTY gear
template as the sync baseline → +620 duplicates spliced into gear.lua; fixed + restored
from the same-second backup; sync prints debug-gated). BRD.lua stripped to pure dlac
(sets + shims only; backup `BRD.lua.pre-strip`). STATIC set deletion shipped
(structural root-walk, T-tests; picker next to Copy from; the main Delete explains
statics). Static sets on SMN cleaned by Henrik.

**GUI conveniences:** per-job macro books (header button; picker = the game's own list
look, 2 columns × 20 named rows — names decoded from USER/<id-hex>/mcr.ttl+mcr_2.ttl,
24-byte header + twenty 16-byte titles; applies on click AND login/job change).
Teleports header dropdown + PF-style floating pinned button (themed — unthemed windows
let the game world tint icons "red") that becomes the ABORT stop-sign while a use is in
flight. Automations list: headers, table-first, no chrome. `docs/guide.html`: an
illustrated from-zero user guide (9 screenshots, annotated mode-gates figure).

**Falsified this session (do not re-learn the hard way):** equipment-window equip
blocking (client-side only, packets pass); the tutorial's HandlePetAction "handler";
v16's cycle-value purge; the Warp-Ring-icon-is-red-state illusion.

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
- **Guild-points self-request (VERIFY, then automate)**: craftwatch reads guild
  points per craft from s2c `0x113` (currencies_1), and `craftwatch.requestGuildPoints()`
  sends the header-only c2s `0x10F` to fetch them (server `validate()` is ungated;
  it's exactly what opening the currency menu does). Currently MANUAL only, via
  `/dl craft gp` — Henrik wants to confirm a real GP turn-in actually reflects
  through this request before it fires on its own (no needless request spam).
  **To close:** turn in a GP item, run `/dl craft gp`, confirm the number rises to
  match the in-game currency menu. Once verified, re-enable a one-shot fetch on
  login + a debounced fetch when the AutoCraft panel opens (the `requestGuildPoints`
  call was removed from `triggersui.lua`'s panel and can be restored). Offsets are
  locked by tests T27–T33; `0x113` handler + persistence already live.

### Loose ends added 07-13 (field-hardening arc)

- **MaxMP relisting**: the Automations row is removed on purpose (picks believed correct
  now — job/bag/ladder/scaling all fixed); re-add one `rows` entry in triggersui when
  Henrik declares it official.
- **WS bailout gap**: stripping legacy profiles (BRD done, backup `.pre-strip`) lost
  gcinclude's CheckWsBailout (cancel WS at bad TP/range). No dlac equivalent yet;
  offered as a feature, unclaimed. SMN/others still run legacy handlers — strip per
  job only on request.
- **Two sessions, one checkout**: the git checkout flip-flops between `main` and
  `feature/storage-move` (game loads whatever is checked out; both carry everything —
  only /dlmv differs). Commit on the CURRENT branch, sync the other via worktree,
  never push feature/storage-move.
