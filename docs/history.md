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
  opening the currency menu does). **VERIFIED 2026-07-13** (a real turn-in reflected via
  `/dl craft gp`), so it now fires automatically: one-shot on login (craftwatch
  `dlac-craftwatch-gp` tick) + on EVERY entry into the Auto Craft Set view (triggersui,
  >1s render gap = just entered; `force=true` skips the 5s debounce — Henrik wants each
  visit fresh — with a 1s anti-flicker floor). Offsets locked by tests T27–T33.

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

## Session "engine self-swap" (2026-07-13, on `main`)

**Reload LAC is now extinct for engine updates too (v32).** The last remaining reload
was the engine's own require-cache staleness: the seeder refreshes
`<char>\dlac\dispatch.lua` on every addon load, but LAC's `require` kept running the old
code until Reload LAC (the version banner's whole reason). Now the engine tick parses
the seeded file's `M.VERSION = <n>` every ~2s; when it differs from the running version,
the file is re-executed INTO THE SAME MODULE TABLE via the `_G.__dlacEngineRoot`
handshake at the top of dispatch.lua — utils' captured reference and the profile shims
run the new code with no re-require. Why this was nearly free: mode state already
survives via the modestate mirror (loadModeState on init), the pet-hold wrap is
guarded (`_dlacPetHold`) and captures no engine state, and utils calls
`_dispatch.dispatch` through the table at call time. The re-run re-registers both
event handlers (unregister-first, pcall'd — deterministic whatever Ashita's same-alias
behavior); swap semantics = Reload LAC semantics (modes kept, slot locks reset,
modestate re-stamped so the banner clears). Failures degrade to today: syntax errors
are caught by loadstring before execution; a mid-execution error rolls `M.VERSION`
back, re-stamps modestate (banner stays honest), and remembers the broken CONTENT
(`M._swapFailedRaw`) so a same-version fix still retries but a broken build isn't
re-tried every 2s. X-tests cover the handshake identity and the version-parse (a
reformat of the VERSION line would kill the swap silently). **One manual Reload LAC
is still needed to get v32 itself live** (v31 has no swapper); after that, engine
updates land within ~2s of an addon reload. The banner stays as the fallback detector.
Dev loop is now: edit → reload dlac addon → watch for "[dlac] engine hot-swapped".
NOT yet covered: utils.lua staleness (rarer; same trick applies if it earns it).
**Field-verified same day, both directions** (v32→v33→v32 by editing the SEEDED file
while Henrik played; modestate re-stamped within seconds each time). Bonus find: the
login BOOT RACE is real — at 13:15 LAC required the old v31 file ~seconds before the
seeder wrote v32 (modestate stamped 31 against a v32 file on disk), which is exactly
the strand the swapper now heals: from v32 on, a race-loser engine notices the fresh
seed within ~2s and swaps itself.

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
- ~~**Guild-points self-request (VERIFY, then automate)**~~ **CLOSED 2026-07-13:**
  Henrik turned in GP items and confirmed `/dl craft gp` (c2s `0x10F` self-request →
  s2c `0x113`) reflects the new total. Automation re-enabled exactly as planned:
  one-shot fetch on login (craftwatch `dlac-craftwatch-gp` d3d_present tick — waits
  for main job ≠ 0 and not zoning, fires once, unregisters itself) + a fetch on EVERY
  entry into the Auto Craft Set view (triggersui `_gpSectionSeen`, >1s render gap =
  just entered; `requestGuildPoints(true)` forces past the 5s debounce per Henrik —
  1s floor dedupes flicker). `/dl craft gp` stays as the manual verify tool. Offsets
  locked by tests T27–T33.

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

## Session "profile storage layer" (07-13, engine v33)

**Theme:** Henrik's brother suggested a layer of PROFILES — named bundles of sets.
One design conversation later it became the storage move that also answers
import/export and "new players never touch legacy files".

**Landed:** `profiles.lua` (new, seeded to `<char>\dlac\` like utils/dispatch) —
active pointer `dlac\profile.lua`, storage `dlac\profiles\<Name>\{sets,triggers}\<JOB>.lua`;
engine v33 auto-installs "active profile + current job" into every fresh `gProfile`
(LAC load / job change / `/dl profile use` — the factored `/dl sets reload` core), so
LAC's own job auto-load composes with profiles for free: the profile picks the folder,
the job picks the file. Commits/deletes now land in profile storage (first commit
imports the job file's Dynamic block verbatim); `/dl profile use|new|clone|migrate`;
migration = backup-first (byte-verified, never overwritten, refuses re-runs) →
verbatim Dynamic move → trigger move → clean-shim rewrite, dry-run by default, every
step printed. "Copy from static" reads `backups\pre-profiles\` forever. Tests Y1–Y33
(extract→frame→extract byte-identical roundtrip; setmanager scanners unchanged on the
framed file; planner skip rules; headless safety). Docs: `docs/design/profiles.md`.

**Key decisions:** one compatibility rule everywhere (reads fall back per file to
legacy; writes always land in profile storage); collision semantics stay FULL REPLACE
(merge rejected — nothing to merge against after the first flatten; sparse sets should
seed via Copy-from-static) with a once-per-load `warnShadowedStatics`; profile names
one word `[%w_-]`; migration always lands in `Default`; the first backup is sacred
(existing backup = file skipped). Veterans: dlac stops writing their `<JOB>.lua`
entirely — the overlay contract (their code first, dispatch last per slot) unchanged.

**Loose ends:** GUI has no profile switcher yet (chat commands + a "Profile: X" line
in the Sets tab — deliberate, gearui is at the 200-local cap); "Delete static" on a
backup-sourced static reports not-found (harmless; statics live in the backup after
migration); `ashita.fs.get_dir(root, '.*', true)` as a DIRECTORY lister is unverified
in the field — `listProfiles` degrades to nil (status still names the active profile).
Field test pending on Mindie: `/dl profile migrate` (dry run first), confirm dynamic
sets survive + statics copyable from backup.

**Follow-up same day (GUI setup):** the Setup button is now plan-first -- clicking it
opens a popup that explains, in plain words per state (fresh / convert-in-place /
migrate-to-profiles / healthy), exactly what will happen, and NOTHING runs until the
Commit button at the bottom (Cancel/click-away aborts). The migrate mode renders the
full per-job plan (profiles.currentPlan) inside the popup and runs the same
backup-first migration as /dl profile migrate go, then auto-reloads LAC. Henrik's real
char data (47 items) is stashed at
`config\addons\luashitacast\Mindie_29909\_stash-pre-freshtest-2026-07-13\` (with a
README-RESTORE.txt) so he can walk the first-time flow himself; restore = move it back.

**Follow-up (profiles menu):** top-left `Profiles` button -- install-wide
character > profile > jobs browser (snapshot on open, not per-frame; get_dir +
popen-fallback listing); use/clone on own rows, cross-character `import` copies
a profile's per-job files into the current character under a new name
(`profiles.importProfile`, never merges into an existing one). Reload-LAC
red-until-reloaded detection landed the same day (v34 __loadstamp), plus fresh-
Setup ordering fix (storage before trigger seed) and Setup-button visibility on
storage-less dlac-wired chars. Field flow validated by Henrik on a stashed-clean
char: fresh run, veteran-migration run (BLU from pre-profiles backup) -- both
passed.

**Menu completion (same evening):** job-row rename/delete + profile delete
landed; deletes are red-button confirmed and ALWAYS write verified safety
copies first (backups\deleted-profiles\, backups\deleted-jobs\). get_dir's
REAL semantics field-verified via Henrik's screenshot: mask is a REGEX
('.*%.lua' matches nothing -- setmanager's backup rotation had silently never
pruned) and arg 3 = RECURSIVE (files+dirs, relative paths). All listings now
mask '.*', non-recursive, Lua-filtered. Cross-char clone field-confirmed
working by Henrik.

## Session "GP auto-fetch + craft bar Last Synth" (07-13, on `main`)

**Guild points automated** (loose end closed above): login one-shot + forced
fetch on every Auto Craft Set entry, after Henrik's turn-in verification.

**Last Synth (craft bar):** Henrik asked for a repeat button -- gated on
proving a synth can actually be SENT. Proven against the server source
(CatsAndBoats/catseyexi `stable`, `packets/c2s/0x096_combine_ask.cpp` +
`synthutils.cpp`): `validate()` checks crystal id / 1-8 items / idle status,
`process()` checks a **15s cooldown from synth START** (`m_LastSynthTime`, set
in `startSynth`), no pending trade, and per-slot `TableNo` item+quantity in
LOC_INVENTORY (same slot repeated = stack draw). No client menu state anywhere
-- so REPLAYING the last captured 0x096 with freshly resolved slots is a legal
synth. Implementation (craftwatch): raw 0x096 kept (`M._lastRaw`), `M.current`
gains `crystal`/`ings`; pure `resolveSlots` (per-slot budgets; crystal claim
reserves its copy -- crystal-as-ingredient safe; T34-T42) + `repeatLastSynth`
(client-side 15s mirror, restock refusals name the missing item, sync zeroed,
CrystalIdx/TableNo patched, one packet per click -- NOT automation) +
`lastSynth()` info for UIs. The injected packet re-enters our own packet_out
handler, so the cooldown re-arms itself. **crafts.lua fmt change:** rows now
carry `r = <NQ result item id>` (gen_craftdb.py; names resolved at runtime via
GetItemById -- no strings shipped; 9470 keys). **Craft bar:** min content
width 430 (bottom Dummy under AlwaysAutoResize), glyph+switch and goal rows
CENTERED (`centerNext`), `Last Synth` button (86px, right of Skill-Up, dim
while cooling, tooltip names the recipe + countdown), and a `Last synth:
<result> (craft lv) -- ready in Ns` status line under the goals.

**Test suite: 274 checks green** (T34-T42 added).

**Follow-up (same day): `/lastsynth` + probe split.** Bare `/lastsynth` = the
button as a macro-able command (stays in dlac -- it's a feature). The packet
capture around it was FIRST built into craftwatch, then Henrik ruled: **probing
tools never ship in dlac -- they live in dlacprobe** (new product rule, applies
to all future diagnostics). Moved same day: `/probe synth [secs]` (dlacprobe
v1.1) arms an all-packet watch window (default 25s, both directions, hex +
INJECTED marker, into probe_log.txt); fire `/lastsynth` after arming. Server-
side proof of the window size: the synth is fully SERVER-TIMED --
`ai/states/synth_state.cpp` counts down `m_synthFinishTime{16s}` (minus
SYNTH_SPEED mods) and calls `sendSynthDone` itself; the client's c2s `0x059`
effect-end is **explicitly ignored** ("handled in synth state").
**FIELD-VERIFIED same evening (211-packet dump, Sapara replay):** the injected
0x096 (Fire Crystal slot 12; ings 650/650/744 from slots 13/13/14 -- the
per-slot stack budget drawing twice from one stack, as designed) was ACCEPTED
in ~130ms (0x01E crystal decrement + 0x01F reserves + 0x037 + 0x030
COMBINE_INF animation), ran the full ~17s server timer, and delivered --
**an HQ: Sapara +1 (16801) into Inventory slot 18** (recipe row 20011: NQ
16551 / HQ 16801). Corrections to the pre-field expectations: the 0x06F
COMBINE_ANS arrives WITH the result at the end, not at accept time (accept is
the animation burst), and Ashita does NOT set e.injected for
PacketManager:AddOutgoingPacket traffic -- find the replay by id, not by the
INJECTED tag. Silence after the 0x096 = server reject.

**CORRECTION + final form (same night): `/lastsynth` is RETAIL-NATIVE.** Henrik:
"Lastsynth is built in somewhere, I've been using [it] for years" -- confirmed
(SE dev1215 "Synthesis Additions and Adjustments"; `/lastsynth` repeats the last
synthesis from the CLIENT's own memory, `/lastsynth check` shows it; Windower's
AutoSynth is built around it). The addon-tree grep proved nothing: client
built-ins are invisible to file search. Re-reading the field dump with this
truth: the captured 0x096 had NO INJECTED marker while another addon's traffic
did -- the client itself sent it. dlac's whole replay-injection build
(resolveSlots, repeatLastSynth, 22s gate, 0x06F pending feedback, T34-T46) was
re-implementing a native feature and then BREAKING it by intercepting the
command ("nothing synthed yet" after reload, native handler never reached).
All of it DELETED (ref c38c2ff for the packet knowledge -- the injection DID
work when armed: server handlers verified + a field HQ). Final form: the button
types `/lastsynth`; craftwatch passively observes 0x096 for the label
(per-char mirror survives reloads); the command handler deliberately does NOT
match `/lastsynth`. Suite 278 -> 267 (injection tests removed).
**Lessons pinned:** (1) never intercept native text commands; (2) check retail
text commands BEFORE inventing addon commands -- name collisions break the
native; (3) absence from the addons tree is not absence.

## Session "exp rings in the Teleports menu" (07-14, on `main`)

Henrik: the eight experience bands/rings (Empress/Emperor/Resolution/Chariot/
Kupofried's/Allied/Caliber/Echad) join the Teleports dropdown in their OWN
section under the teleports -- and only the ones you OWN are listed (you can't
have them all; eight "not owned" rows is noise -- useitem.menu() drops unowned
`xp` rows, the popup draws the section header at the first xp row). Same
machinery as the teleport items end-to-end: `/dl xp <ring>` (aliases:
empress/emperor/resolution/chariot/kupofried/allied/caliber/echad) locks
Ring2, equips, polls the game clock, fires when ready; recharge countdown in
the menu (Echad's 120-min reuse renders h:mm:ss); `/dl xp off` cancels.
Fallback wait 15s (10s equip delay + margin) -- the game-clock poll governs
in practice, as with every enchanted item here.

## Session arc "ACC calculator -> acc watch" (07-13 evening -> 07-15, on `main`)

Goal (Henrik): "how much ACC do I need on this mob?" -- automatically, per
engagement. Built in layers, each field-tested by Henrik between commits:

1. **Server-source math** (`tools/acc_calc.py`, 3b6abd6/a970306): parses the
   public CatsEyeXI repo (mob tables, grades, skill ranks, zone lists, Mod
   ids) into cached files; formulas transcribed f32-faithful with DRIFT
   SENTINELS (warns if the source line vanishes). Query / `--dump mobs.json` /
   `--families` CSV (Lv1-99 per family x job combo) / `--luadata`.
2. **Shipped data** (`accdata.lua`, cb6806f/d111213, catalog model): 12,136
   mobs x 237 zones -- spawn ranges, zone-exact EVA endpoints, NM flag, and a
   79,939-entry spawn-idx->name map (mobid = 0x1000000 + zone*4096 + idx),
   needed because **widescan replies carry NO name on CatsEyeXI** (field:
   names only appeared <=~50y = entity memory; type byte 1=NPC/Lv0, 2=mob).
3. **accwatch.lua** (cb6806f -> 6648d7e): `/dl acc` engage watch. Every
   engage (0x01A action 0x02) AND battle-target switch (action 0x0F,
   auto-target) silently injects TWO c2s 0x0DD requests -- /checkparam at
   self (Kind 2, FIRST, msg 712 p1 = live mainhand ACC) then /check at the
   mob (Kind 0, level via 0x029 p1). Replies cached + BLOCKED (mute windows;
   manual checks still print). **0x0DD is 16 bytes: UniqueNo u32, ActIndex
   u32, Kind u8 @0x0C enum-validated -- the XiPackets-style 12-byte guess is
   dropped silently** (that was the "still seeing the old message" bug).
   Output = Henrik's labeled one-liner (engage and `/dl acc now` alike):
   `<Mob> Lv<L>* - MobEVA E - CurrentAcc A - AccCmp E-A - AccCmpLvl
   (you-mob)*4 - AccPct hit% - AccCap need-A`. `/dl acc debug` traces.
4. **Bracket learning** (3b0975f): the model UNDERESTIMATES some live mobs
   (Wajaom Tiger 69: model 269, bracket proved >=287 -- private tuning).
   Every check reply narrows [lo..hi] true-EVA bounds per (zone,mob,level)
   from the eva bracket (RAW acc vs RAW eva: High>=ACC+31, neutral ACC-9..
   ACC+30, Low<=ACC-10); report clamps model into bounds; newest-wins on
   contradiction. Session-scoped.
5. **Level correction, two rulings** (0eaae9d then 3922bff): repo code grants
   +4 ACC/lvl fighting up, gated to a zone list. Ruling v1 (07-14, from the
   code): bonus is canon. Ruling v2 (07-14, from LIVE PLAY -- supersedes):
   retail semantics, **-4 ACC (-2% hit) per level above you, EVERYWHERE**
   (75-era server; the zone-list gate only runs when
   USE_ADOULIN_WEAPON_SKILL_CHANGES=true and live settings are private).
6. **dlacprobe v1.2->v1.5** (research kit, NOT in git): `/probe scan` widescan
   +/check decoder cross-checked vs accdata; `/probe scan go [secs]` injects
   widescan requests (the menu is the only native trigger; checker addon
   never polls -- its levels come from the /check reply, widescan only
   backfills NMs); `/probe tally` battle-log hit/miss counter = ground truth.

**Lessons pinned:** (1) for new-style c2s packets read the SERVER's header --
XiPackets layouts can be stale (u16 vs u32 ActIndex); validation drops bad
sizes without any reply. (2) The /check eva bracket is free ground truth --
learn from it instead of chasing formula parity with private tuning. (3)
Rulings derived from code-reading can be overturned by live play; record
both and the instrument that decides (tally). (4) Same-named mobs span zones
with different rules (Wajaom Tiger: Wajaom corrected, Bhaflau not).

**Open threads (ACC arc):** tally-verify ruling v2 (~20 swings vs a +20ish
mob: penalty/none/bonus predict ~20%/~50%/~95%); NM path (widescan is their
only level source -- consider a quiet widescan fallback on "impossible to
gauge"); persist learned EVA bounds per char (currently session-only);
regenerate accdata after server updates (`acc_calc.py --luadata accdata.lua`);
next layer = feed AccCap into gear-set selection.

## Session "AutoAcc -- the first Type automation" (07-14, on `main`, engine v36)

Henrik's design, verbatim taxonomy: **Set automation** replaces a whole set;
**Slot automation** occupies a slot and picks the best item (AutoStaff/Obi);
**Type automation** (NEW) is assigned to a PIECE -- "in my sets, I will more
or less always set my Peacock Charm as type AutoAcc, so when acc is capped,
it will not equip that but the next best candidate." Built on the acc-watch
arc's AccCap number, ASSUMED correct pending tally verification.

How it works (four hops, two Lua states):

1. **Behaviour popup** (gearui): "Auto Type" combo (None/AutoAcc) + "Removal
   Priority" int (higher = released first). Commit bakes the wrapper into the
   job file: `{ gear = ..., autoType = "AutoAcc", removePrio = N, acc = N }`
   -- `acc` is the piece's Accuracy (base + YOUR copy's augment deltas) baked
   at commit because the seeded engine state has no catalog. Recommit after
   re-augmenting. Row badge `[AutoAcc pN]`.
2. **Flatten** (utils.BuildDynamicSets): typed entries compete in their OWN
   pool (same rank tiers); between two eligible candidates the HIGHER-LEVELED
   item wins the slot (Henrik's rule). The untyped normal pick becomes the
   fallback: `'dlac:AutoAcc:<prio>:<acc>:<Name>|<fallback>'` (name LAST in
   the marker half so any item name parses). A slot automation (dlac:Auto*)
   on the same slot wins outright; AutoAcc is then ignored there.
3. **Measurement** (accwatch): every acc report also writes
   `<char>\dlac\accstate.lua  { seq, valid, capGap = need - yourACC, at, mob }`.
   valid=false when the number cannot be computed -- mob not in accdata
   (custom/HNM), no /checkparam ACC yet -- and when `/dl acc` is toggled OFF.
4. **Release** (dispatch v36, equipResolved pre-pass): while OVER cap,
   release AutoAcc pieces by removePrio desc, but only while each piece's
   baked acc fits the remaining surplus; released slot wears its fallback.
   No fallback / acc<=0 / locked slot / invalid / stale (>15 min) -> the
   piece just stays worn ("handle the equipment as per usual").

**The feedback-loop subtlety (know this before "fixing" flapping):** capGap
is measured with the CURRENTLY-RELEASED pieces off, so on each new seq the
engine rebuilds its budget as `-capGap + sum(released accs)` -- the all-worn
surplus -- then re-decides from scratch and freezes until the next seq. That
makes the fight-to-fight loop self-correcting (fallback's own ACC, manual
regear, harder mob -> pieces return) WITHOUT tracking absolute ACC anywhere,
and per-seq freezing keeps every dispatch of one fight agreeing with itself.
The budget deliberately values a release at the piece's FULL baked acc
(ignoring the fallback's acc); the next measurement absorbs the difference.

Tests AC1-AC24 (293 total green): flatten forms, marker parser, release
math incl. the stability/re-add sequence, invalid/stale/no-fallback/zero-acc
guards, serializer round-trip. Seams: `dispatch._accStateOverride`,
`_accResolveSet`, `_accDecide`, `_parseAccMarker`, `_accReset`.

**Field-verify next:** engage over cap with a typed charm (expect the
release note in `/dl why`), then a harder mob (expect it back); confirm the
accstate write survives real zone/engage timing; then tally-verify the
underlying AccCap (still assumed). Reload LAC required (utils + dispatch v36).

## Session "custom mobs -> family EVA curves" (07-14, on `main`)

Field report (Henrik): custom Toucans in Wajaom Woodlands (ids
0x1033806-0x103380F -> zone 51, idx 0x806-0x80F) get "not in the static
table... the widescan layer will learn these" -- and widescan never helps.
Diagnosis: BOTH halves of that message were wrong for customs. (1) They are
dynamic spawns absent from the public repo's mob_groups, so the zone lookup
can never hit; (2) the widescan layer only collapses LEVEL ranges for mobs
already IN the table -- a level without an EVA entry reports nothing. The
message over-promised; customs were simply unpriceable.

The unlock: customs reuse stock POOLS. "Toucan" is a stock mob (pool 3980,
family Bird, WAR/WAR) that spawns statically only in Bibiki Bay (zone 4,
Lv38-40) -- the NAME identifies the family even when the zone/level don't.

Fix, three layers:

1. **accdata families curves** (acc_calc.py --luadata): one EVA-by-level
   curve (Lv1-99) per family -- 350 curves, keyed by squashed family name.
   Computed with the family's most common (mJob,sJob) across ALL pools
   (customs may use pools that never spawn statically), no pool mods,
   non-NM, sub-job-zone floor. Verified against shipped entries: exact at
   >=50 (Tragopan 71/73 = 282/292), ~2 low under 50 (deliberate floor).
   Regen is additive-only (existing mob table byte-identical).
2. **accwatch fallback**: on a zone-table miss, resolve the family -- per-char
   manual assignment (accfamilies.lua) wins, else the CROSS-ZONE NAME MATCH
   (lazy index over all zones' descs: toucan -> bird, automatic) -- then
   synthesize the entry from the curve at the LIVE level (the auto-/check
   fired on engage answers before the report; widescan also feeds it). The
   synthetic entry flows through the NORMAL report path, so the bracket
   clamp corrects the curve immediately and accstate/AutoAcc work on
   customs too. Family known but no level yet / no family known -> targeted
   chat hints; accstate stays invalid (AutoAcc stands down).
3. **/dl acc family <name>** (bare = show, clear = remove): assigns the
   CURRENT TARGET's family for names the table has never seen; tolerant
   resolver (squash, plural 'birds'->'bird', unique prefix); persisted per
   char; reports immediately after assigning.

The Toucans need NO assignment -- the name match finds Bird. Tests AD1-AD9
(302 total green): curve bounds, resolver tolerance/ambiguity, cross-zone
index. Field-verify: engage a Toucan with /dl acc on -- first engage should
print the labeled line with Lv* from the auto-check; if customs answer
"impossible to gauge" instead, open widescan once and re-engage (whether
dynamic entities appear on CatsEyeXI widescan is UNVERIFIED -- /dl acc debug
traces the reply shape if neither works).

## Session "level correction ruling v3 + the Reload-LAC lesson" (07-14, on `main`)

Field report (Henrik, Toucan camp): the family-curve fallback WORKED
(`Toucan Lv26* - MobEVA 90`) but (a) AutoAcc left the Peacock Charm on and
(b) the numbers read low -- "I get +4 acc every level I am above a mob,
just as I get -4 when I am underleveled."

(a) was NOT a code bug: the /dl why line `-> set Tp_Default (prio 20)`
carried NO `[AutoAcc=...]` note, and the v36 engine always notes a marker
(worn or released) -- so the flattened set had no marker, i.e. LAC was
still running the pre-AutoAcc utils.lua. The flatten lives in utils, which
does NOT self-swap (the engine self-swap + red banner watch dispatch.lua
ONLY -- hard rule 4's known blind spot). Fix: Commit, then Reload LAC.
LESSON for diagnosis: "acc line works but sets don't react" = addon state
vs LAC state -- accwatch/GUI live in the addon, flatten/engine in LAC.

(b) is **ruling v3 (supersedes v2's penalty-only):** level correction is
SIGNED 4 ACC per level, everywhere -- -4/lvl with the mob above you, +4/lvl
with it below. accwatch folds it into need/AccCmpLvl/AccCap (Lv46 vs Lv26:
AccCap -103 -> -183), acc_calc.py correction() mirrors it. Need can go far
negative on greys -- intended: AutoAcc then releases everything. Tally
verification of the exact +-4 slope remains the open ground-truth check.

## Session "the GM split: ACC system -> feature/autoacc" (07-14, branch + main)

Henrik, right after field-verifying AutoAcc: LuaAshitacast is on the server's
"special approved list" BECAUSE of automation -- gear swaps driven by a
calculated acc cap may be more than the GMs allow. He has asked them for
approval; until the verdict, main must not carry it (the storage-move
precedent). His spec: keep the gear-auto-type FOUNDATION on main (GUI shows
Auto Type with None only), move "the acc calculations, mob family lookups and
everything" to a branch.

**feature/autoacc** (branched at 348815c) = main's full state PLUS the
Automations-panel row he asked for first: AutoAcc listed under Triggers ->
Automations, Kind "Equip Type", status = acc watch ON/OFF, detail view with
a /dl acc toggle (through the command bus ON PURPOSE -- the handler writes
the accstate-invalid record on OFF; flipping aw.enabled directly would skip
it). Everything ACC lives here: accwatch.lua, accdata.lua, tools/acc_calc.py,
AutoAcc selectable in the Behaviour popup, tests AD1-9.

**main** (stripped): accwatch/accdata/acc_calc deleted; 'accwatch' out of
dlac.lua's module list; Behaviour popup offers None only (a branch-committed
autoType still DISPLAYS and can be cleared -- one set format across branches);
tooltips genericized (no AutoAcc/acc-watch text). The DORMANT foundation
stays: wrapper fields + serializer/loader, flatten markers (utils), engine
budget machinery (dispatch v36 -- nothing writes accstate.lua on main, so
markers always resolve to "worn"), tests AC1-24 guarding it all.

Working rule while the verdict is out: **commit ACC work on feature/autoacc
only; do not merge or push the branch without Henrik's word.** Playing with
AutoAcc = `git checkout feature/autoacc` + `/addon reload dlac` -- no Reload
LAC needed for the flip: both branches carry IDENTICAL engine/flatten code
(utils.lua byte-equal, dispatch.lua differs only by a main-side comment, same
VERSION 36); only addon-state files (accwatch/accdata/GUI) differ.

## Session "stat classification round 2 -- the 19-mod wiring sweep" (07-14, on `main`)

Audit finding: catalog.lua itself had ZERO unclassified stats (every key resolved
through statdefs, 197 distinct) -- the real backlog was upstream, in mods the
crawler never mapped. Cross-referencing `tools/api_cache/ignored_mods.txt` against
statdefs + stats_decisions.txt exposed 19 mods whose keys were ALREADY approved
but never wired into apicrawl/apiscan CORE: elemental MAB 32-39 (explicitly
DECIDED in stats_decisions.txt, only the MACC half got wired), QUAD_ATTACK,
STATUSRES, CURE_POTENCY_II, SUBTLE_BLOW_II, ATTP, DOUBLE_SHOT_RATE, SHARPSHOT,
DAKEN, BP_DAMAGE, BARRAGE_COUNT, CRITICAL_HIT_EVASION, ENF_MAG_POTENCY,
ENF_MAG_DURATION. All wired (CORE block in BOTH apicrawl.py and apiscan.py --
keep-in-sync rule), catalog rebuilt with --build-only: 216 distinct keys now,
still zero unclassified, 293 tests green. Also fixed two augment-table keys that
drifted from their approved canon (augments.lua: EarthMagicAcc -> EarthMACC,
EnhancingDuration -> EnhancingMagicDuration) -- augment deltas are runtime-only,
so no migration needed.

The remaining 409 unmapped mods are now EXHAUSTIVELY bucketed in
`tools/api_cache/stats_tiers2.txt` (regenerate: scratchpad script, or by hand):
300 proposed adoptions with key/label/section/flags (incl. two NEW sections,
"Ability" and "Pet"), 50 recommend-skip (proc metadata, race locks, relic
aftermath machinery, mythic-specific Augments mods), 13 investigate (CatsEyeXI
2000-series customs + the value-73 gathering RESULT mods), 46 unmapped
relic-range ids (same class as the augment-table undefined gaps). **The ADOPT
rows are frozen pending Henrik's row-by-row naming sign-off** -- statdefs labels
are user-facing (his hard rule). Watch-outs recorded in the sheet: SONG_RECAST_
DELAY stores positive=reduction (the statdefs pencil note guessing lowerBetter
is wrong); DMGPHYS_II/DMGMAGIC_II are basis-point scaled with positive-penalty
outliers (Aettir +500); the fTP/WS-gorget family naming is sensitive.

## Session "tp-menu charges + the stdin hang" (07-14)

Teleports/Exp-rings menu grew a **charges column** ("2/7", Henrik: know at
a glance what's left on the exp bands): charges-remaining is Extra byte 2
(same field-proven extdata layout as the offset-5/9 timestamps), the cap is
`MaxCharges` off the item resource. Column sits between item name and
state (state shifted 340 -> 400; the popup auto-sizes); red at 0, and the
row tooltips carry ", n/m charges". Only owned, charge-tracked items show
it -- earrings/rings whose resource says MaxCharges 0 stay blank.

Found while verifying: the headless suite HUNG (zero CPU, no output).
Line-tracer wrapper (scratchpad) pinned it to profiles.activeName() --
`loadfile(M.pointerPath())` with pointerPath nil headlessly, and
**loadfile(nil) reads STDIN** -- a piped stdin never EOFs, so the run
blocked forever. Every other loadfile site already nil-guards its path;
activeName was the one outlier (guard added). Suite green again on
both branches (302 on feature/autoacc, 293 on main -- the AD section is
branch-only).
## Session "stat weights: the lazy-load gap + per-set memory" (07-14)

Bug (Henrik, DRK Midshort): weights set in an earlier session read back as
"no stat weights are set". Root cause: gearoptim's ensureWeightsLoaded()
ran only from the /dl weight|best|mp COMMAND paths and once at module load
-- which is Ashita boot, pre-login, where weightsPath() is nil and the
retry never happens. The GUI (weights editor, weightsActive, score) read
M._weights directly and never triggered the load, so gearweights.lua sat
on disk unread until some chat command happened to heal it. Fix: the
accessors (getWeights/setWeight/clearWeight/score-with-nil-weights)
lazy-load through a forward-declared ensureWeightsLoaded; the flag is set
BEFORE loading because loadWeights now re-binds, which re-enters.

Feature (his ask): **every set remembers its own weights.**
gearoptim.bindSetWeights(job, setName) switches the ACTIVE table between
the shared table (no set bound; legacy flat files load here) and
perSet['JOB|SetName']; a set's FIRST bind seeds a copy from the shared
table (continuity -- nothing vanishes on upgrade), after which edits stick
to that set only -- switching sets never drags the last-used tuning along
(isolation is the point; AE6/AE7 pin it). gearui binds at the top of
renderSetsTab AND renderSetsWeightPanel (the Weights window can be open on
another tab); a binding change clears ui._wbuf + invalidates candidates.
The editor header names the owner ("weights for set \"Midshort\" (DRK)" /
"shared weights"); /dl weight show says it too. gearweights.lua format is
now { shared = {...}, perSet = {...} } -- written on every edit as before.
Tests AE1-15. Also git-rm'd the stray addon-root gearweights.lua (initial-
commit dev artifact; the real file lives in <char>\dlac\, nothing read it).
