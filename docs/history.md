# dlac â€” Project history & session journal

> What happened, in order, with the reasoning that is NOT recoverable from the code.
> Sources: git history + mined Claude Code session transcripts (2026-07-10).
> New sessions: append a section here when a work block lands; keep the same headings.

The project was born 2026-07-09 and reached its current shape in two days of intense
Henrik+Claude sessions, several running in parallel on the same checkout.

## Day 1 (07-09) â€” bootstrap era *(documented from git log only; no transcripts survive)*

Initial import of the pre-dlac profile code ("ffxi-lac") into an addon: entry point,
per-char gear loading, Sets tab reading `sets.Dynamic` from `<JOB>.lua` on disk, path
fixes for running without `gState` (party manager fallback), full catalog crawl
(~1.7k â†’ 14.9k items), Setup button (fresh profiles based on LAC's `/lac newlua`
skeleton + dlac wiring; migration keeps player code), library seeding into
`<char>\dlac\`, stats moved 100% to the catalog (scanner stopped parsing them), add-only
auto-sync on job change, first augment idâ†’stat maps.

## Session "augments â†’ stat standard" (08a38488)

**Theme:** decode a friend's augment dump; then a full stat-vocabulary standardization
with Henrik ruling on every name ("if there is ANYTHING people will complain about, it
is this").

**Landed:** 58 of 64 unknown augment ids resolved (LSB `augments.sql`, then confirmed by
CatsEyeXI's own `enum_augment_name` from the private server repo â€” the remaining 6 are
undefined no-op gaps, do not chase); augment display value = base-in-name + tier (SCALE
table); full AUG_NAME regeneration (~328 ids). Debug flag persistence
(`<char>\dlac\uiflags.lua`); stat-weights GUI moved to its own window, integer inputs,
searchable stat dropdown. Crawl-side: `apicrawl.py` taught to emit ignored-mod reports;
14,874 items cached; 574 unmapped mods triaged to 105 real stats; `statdefs.lua` grown
49 â†’ 178 entries with Henrik's naming standard (extreme abbreviations for extremely
common terms: PDT/MDT/DT/MDMG/MAB/MACC canonical, descriptive forms as aliases).
`tools/` untracked+gitignored (privacy; history rewrite declined).

**Key decisions:** authority chain for augments (server enum > LSB SQL > wiki; the enum
must never be committed); non-linear augment ids stay display-only (would corrupt worn
totals); 311 = flat Magic Damage (MDMG), NOT Magic Attack Bonus; ThunderResistance not
LightningResistance (reuse existing keys, never invent parallels); status resists verb
style (ResistPoison); lowerBetter flags so positive weights reward reductions; statdefs
carries no server mod-ids ("I don't think the server wants to expose it") â€” the
modâ†’key bridge lives in gitignored `tools/api_cache/stats_decisions.txt`.

**Field-verified:** DT-family mods and SkillchainDamage are stored Ã—100 (Defending Ring
= âˆ’1000); TP_BONUS 345 is literal TP; 1472 is Parrying *rate*.

**Dead ends:** asking what the 6 unknown augments "read in-game" (they're gaps); live-API
fetching when `apicrawl.py` exists ("Calm down, we already have a python script").

**Follow-through (landed in later commits):** the three wiring tasks â€” crawler CORE
expansion (ed97adb, 96f113c), catalog/statdefs review (1971bb0), weights picker via
statdefs (9099837). Still open from this session: stat hover descriptors (text ready in
`tools/api_cache/stats_tiers.txt`); augment decoder boundary fix (stop at first 0x0000
word â€” verify against real scans first).

## Session "trigger system day" (96c90bd5 â€” the big one)

**Theme:** opened with `/grill-with-docs` â€” "challenge me properly, it is important to
get this right." Full design â†’ ADRs 0001-0004 + glossary + trigger-system.md + 13 GitHub
issues â†’ same-day implementation of the engine, Triggers tab, automations, modes â€” then
storage-move research and the gearmove branch. Henrik's product rule, verbatim:
**"nothing that this addon makes should force a player to use lua files or edit them
manually."** And the working agreement: **"don't ask for permissions to edit files
within the addon, you are the maintainer IMO, I am just the one with the creative
vision."**

**Landed (chronological):** dispatch engine (data-driven triggers, hot-reload, `/dl
mode|why|triggers`); Triggers tab + convert-in-place Setup (per-handler health check,
append-only shims, `.flbak` + rotated backups); LuaJIT 200-local cap forced the
triggersui split; automations saga â€” ADR 0004 revised 4Ã—: global toggles â†’ per-set
flags â†’ **virtual slot entries** (`dlac:AutoStaff`/`dlac:AutoObi` living IN the set,
Henrik's "maybe it's simpler to handle this as a slot function?"), tiered Iridescence
(NQ+1/HQ+2 elemental, universals; ties to universal), level-gating with best-by-level
fallback; `contains` condition + AND-stacking; universal Hachirin-no-obi reality;
manifest auto-regen on login/job change; picker DB from the server's public SQL
(Pianissimo is BRD 20 here vs retail 45); README rewrite; cycle modes replacing the
hand-written variant-table pattern (keybinds, builder popup, fromâ†’to prints, VERSION
staleness banner); `/dl why` per-slot attribution; level-scaling (31 items from
`item_latents`); catalog stat keys 41â†’176; engine-owned slot locks (LAC forgets
`/lac disable` on reload); `/dl prune`; all-container ownership + red stored names +
container-naming tooltips; quiet auto-sync; DW from live memory (`HasAbility(1554)`);
CatsEyeXI jobs reference from BG-wiki; storage-move research + live packet probe
(dlacprobe) + gearmove v1â†’v7 + gearcheck on `feature/storage-move`.

**Key decisions:** see ADRs 0001-0004 (all written this session) and
docs/design/storage-move.md. Highlights not in the ADRs: modes are session-only (all
OFF / first cycle value at login â€” "no surprise DT-mode from last Tuesday"); trigger
Commit is live but set Commit needs Reload LAC (accepted asymmetry); storage-move gate
is client-side and fail-closed, trusting only 0x00A LoginState (the memory MH flag is
field-falsified â€” ACE `!mog` flips it anywhere); feature/storage-move stays local
pending GM approval; gearcheck deliberately self-contained for cherry-picking; move UI
only in the All Equipment browser, equipped gear green + blocked.

**Field-verified (live CatsEyeXI):** trigger hot-reload end-to-end ("I can do pianissimo
and it changes even without reload lac, incredible"); ACE `!mog` falsifies the memory MH
flag; **Provenance broadcasts MogZoneFlag=1 â€” the live DB diverges from every public
repo branch**; Safeâ†”Inventory moves work at the Provenance hub today; Storage absent
from the hub moogle menu; 0x029 packet layout byte-for-byte, ~150 ms confirm, silence =
rejection; ~900 item packets flood zone-in; Chatoyant Staff carries Iridescence +2;
Blade Madrigal is Thunder element; LAC only re-requires seeded files on ITS reload.

**Dead ends (do not retry):** codegen for triggers (ADR 0002); global automation
toggles AND per-set SetOptions (both fully built, then deleted â€” the SetOptions
serializer also caused the flag-wipe bug: fileToModel must carry ALL sections);
Iridescence-as-suppression (inverted â€” Chatoyant IS the auto staff);
eight-era-elemental-obi assumption; **`BeginPopupContextItem`** in this ImGui binding
(two failed rounds â†’ Trove-style `[mv]` left-click button â€” but see the CORRECTION
below: right-click ITSELF works, this entry used to say "right-click context menus"
and was wrong); LAC memory MH flag as a
gate; nomad-moogle interaction gating (access is zone-wide; 0x02E has no close event);
inventory-hop move routing (direct is legal); `/lac disable` slot locks;
catseyexi.com API for spells/abilities (items only); public repo SQL for job mechanics
(byte-identical to stock LSB â€” customization lives in private submodules; trust ladder:
live memory > BG-wiki > public SQL).

## Session "offhand" (f3c35992)

**Theme:** "I can't set off-hand weaponsâ€¦ you should still be able to build what you can
wield in sub as long as it is one-handed. Then the logic if you have dual wield or not
should decide." Established the **"builder is a plan, the engine decides"** principle
(ADR 0006), lifted from Henrik's old ffxi-lac code.

**Landed:** builder DW gate removed (Add popup passes `building=true`; the
immediately-equipping Alternatives list keeps the gate); `BuildDynamicSets` resolves
Main before Sub explicitly (pairs() hash order starved Sub); `jobCanEquip` honors the
support job; `utils.subSlotAllowed` as the one shared pairing rule;
`utils.classifySub` (catalog says `Type="Sub"` for shields AND grips â€” classify by "*
Grip"/"* Strap" name); `subCandidatePool` (1H Main-slot weapons now reach the Sub
picker); `/dl fix` backfills Type/OneHanded into gear.lua (the LAC-state engine reads
raw gear.lua and never sees GUI enrichment); `/dl dw` probe; comment-aware shim parser
(commented-out handlers no longer wedge Setup â€” they count as missing and get a fresh
shim); Reload LAC clears the setup status line; chat overhaul (chatfmt.lua palette,
print-shadowing, coral vs LAC's teal, quiet routine loads); author/license = Mindie,
MIT. Headless test suite born this session (`winget install DEVCOM.Lua`;
`tests\run_tests.lua`, 21 â†’ 44 checks).

**Key decisions:** asymmetric gating (planning permissive, immediate-equip strict);
Auto-build stays equip-correct (shield when no DW) â€” making it permissive is an open
user decision; repairer's conservatism preserved (fix the parser's honesty, not the
repairer's caution); commented-out player code is never uncommented.

**Dead ends:** fixing only the visible filter (the pool and metadata upstream still
blocked everything â€” trace the full pipeline: pool â†’ metadata â†’ vocabulary â†’ filter);
chasing "still prints" ghosts (stale LAC memory state, not code).

**Open:** `/dl dw` positive-case verification on an actual DW job (the trait bit has
only ever been observed false; if NIN main shows shield-paired, suspect a HasAbility
id-cap and reprioritize the fallback).

**Correction (07-11, field-falsified):** this session's "main OR support job wields
it" rule in gearui's `jobCanEquip` was wrong on CatsEyeXI â€” RDM74/WHM37 cannot wear
Hlr. Bliaut +1 (WHM Lv74); another job's gear stays unwearable even with that job
subbed. Wearability is MAIN job only (as gearoptim's `jobAllowed` always had it).
The sub job still legitimately feeds Dual Wield detection for off-hand pairing.

## Session "GM feedback & prune" (c89bcd85 â€” this one)

**Theme:** polish while a GM evaluates the addon for approval; then this documentation
effort.

**Landed (main):** word-wrap for long status lines (GM feedback â€” `textWrapped` helper);
`/dl prune` parser made comment-tolerant (25 of 637 real gear.lua entries had trailing
`-- comments` on their headers and were invisible to prune/fix/dedupe); `/dl prune why
<item>` per-container ownership probe; scan messages updated to the all-container
reality (ADR 0005). Meanwhile a parallel session ran the gearui modularization
(profilesets/gearfmt/cmdqueue extractions, locals 200 â†’ 180) on feature/storage-move.

**Key decisions:** delete-and-regenerate gear.lua rejected â€” nothing recreates a missing
gear.lua (the commit pipeline aborts), and regeneration would lose deep-storage entries;
prune is the tool. Brigandine's survival was a genuine ownership match, not a bug â€” use
`/dl prune why` before assuming.

**Late additions (same day):** CTRL+K GUI keybind; partyfinder-matched window theme
(uistyle.lua); branch hygiene restored (modularization + theme + gearcheck promoted to
main; feature/storage-move = exactly gearmove again); **mode-gated set entries** â€” a
slot-list entry can carry `mode = 'Weapon:Melee'` (wrapper form, like
minLevel/maxLevel, now GUI-editable via the `~` button): active-mode entries OUTRANK
unconditional ones, inactive ones are excluded, so ONE set adapts per mode instead of
mode-switched set pairs. Same matcher as trigger `mode` conditions
(`dispatch.modeActive`, VERSION 5); the GUI previews against the modestate mirror. Also
fixed: the engine's wrapper merge mutated the SHARED gear.lua record (an item wrapped
differently in two sets leaked fields between them) â€” it now merges onto a copy.
Tests G1-G12 (the suite now loads the real dispatch.lua headlessly).

## Session "crafting system + catalog pipeline" (2026-07-11 â†’ 07-13, on `main`)

**Theme:** a long multi-day arc â€” hardened the catalog/data pipeline, shipped the whole
crafting-gear system (detection â†’ manual craft bar â†’ engine overlay â†’ guild-points/key-item
panel), and fixed several load-bearing bugs. All landed on **`main`** and pushed to GitHub
(`henkpoa/dlac`). `feature/storage-move` stays local, untouched.

### Catalog & data pipeline
- **Distribution model, ruled by Henrik (memory: catalog-distribution-model):** the addon
  MUST NEVER fetch from the API at runtime. Only Henrik scrapes (`tools/apicrawl.py`), ships
  `catalog.lua` in the addon update; the ONLY live-parsed data is augments. Client-side
  fetching was rejected a 2nd time â€” do not re-propose.
- `apicrawl.py` gained `--gaps` (fetch ids in every char's `<char>\dlac\gear.lua` the cache
  lacks/has as 404 â€” the fix for "new item shows no stats") and `--refresh N` (re-fetch cache
  older than N days). `equipment_ids.txt` is a STATIC retail-era dump; CatsEyeXI customs
  (e.g. Hieratic Ring 23994, and the 39xxx block) aren't in it â†’ `--gaps` or a GM
  `SELECT itemid FROM item_equipment` dump, or a full `--range` sweep. **Item ids are u16
  (cap 65535)**; 28671 = end of retail equipment DAT block; customs live in unused holes
  (23994) and past the end (39xxx).
- **Reproducibility bug fixed:** DT-family mods are mixed-scale (percentÃ—100 vs literal) â€”
  the builder now applies the `|v|>=100` rule (same as SkillchainDamage) so a rebuild
  reproduces `catalog.lua` byte-for-byte. Per-item desc-vs-DB drift fixups live in
  `MOD_STRIP`/`MOD_ADD` (Neph. Grip 22198 has phantom craft mods; Hocho/Debahocho lack
  their Cooking mod) â€” KEEP IN SYNC across apicrawl.py + apiscan.py. Report drift to GMs.

### Crafting stat family
- Mapped (Henrik-approved names): 8 craft skills (`WoodworkingSkill`â€¦`CookingSkill`),
  `SynthHQRate`, `SynthMaterialLoss`, `AntiHQ<craft>` (Ã—8), `ConserveIngredient`
  (CatsEyeXI custom **modid 2016**). `AntiHQ` = a hard "Cannot Synthesize HQ" block.
  Universal pieces carry all 8 per-craft mods individually (there is NO single "all
  crafts" mod). gearfmt collapses uniform 8-way families to "All Craft Skills+2" /
  "All Anti-HQ+1" for display only.

### Craft gear system (the big one)
- **Detection** (`craftwatch.lua`): c2s `0x096` (synth confirm) â†’ crystal+ingredient
  multiset â†’ `crafts.lua` (9,470 recipes, `tools/gen_craftdb.py` from the server's
  `synth_recipes.sql`) â†’ craft skill. **Binding-craft/tier calc:** subcraft recipes carry
  a `skills` map; the craft with the smallest player-skill margin limits the HQ tier
  (breaks at >11/>31/>51). Detection is now **INFO ONLY**.
- **DEAD END â€” auto-equip by detection:** `0x096` is the FIRST packet the synth flow emits
  (crystal use + ingredient placement are client-local), so nothing can dress you for the
  synth that triggered it. Do not revive detection-driven equipping.
- **MANUAL model (Henrik's design):** the floating **craft bar** (`craftbar.lua`, toggle
  `/dl craft bar` or the header helmet icon) + the Automationsâ†’AutoCraft panel let you pick
  a craft + goal (**hq / nq / skillup**) and flip an on/off switch. craftwatch WRITES
  `<char>\dlac\craftstate.lua` (`{craft, goal, enabled}`); state persists (enabled is
  session-only, starts OFF).
- **THE architecture â€” engine OVERLAY (dispatch v31):** don't fight the engine, BE it.
  `dispatch.craftOverlay` reads `craftstate.lua` and, on every Default dispatch, overlays
  the resolved craft gear (`dlac:AutoCraft` per slot from the manifest craft ladders) LAST
  = top priority, even with no trigger match. So the engine WEARS the craft gear; nothing
  reverts it; switch off â†’ overlay gone â†’ normal Default returns.
  - Why not commands/locks: `/lac disable` blocks `/lac equip` on that slot; `/dl lock` is
    set in the ADDON state and its command is `e.blocked` before reaching the LAC state that
    does the revert. Both dead ends â€” the overlay is the answer.
- **Manifest craft ladders** (`triggersui.lua` autoCommit, `AUTO_FMT` now 6): per slot â†’
  craft â†’ goal, best-first. Skill-up items (Midras's Helm, Bonze Cape, Shapers Shawl) fill
  hq/nq slots as LOW-priority fillers (`floor(gain*0.3)`, always < a skill=1 item's 10) so
  a real craft-skill item (Chef's Hat for HQ head) still wins.
- **THE bug that hid #2 for many rounds (hard rule 8):** `autoCommit` read `CRAFT_UI.goal`,
  but `CRAFT_UI` is a `local` declared LATER in the file â†’ nil global â†’ `.goal` threw â†’
  `rescanAutogear`'s pcall swallowed it â†’ the manifest never regenerated past `fmtver 5`
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
  sending header-only c2s **`0x10F`** ourselves (server `validate()` ungated â€” exactly what
  opening the currency menu does). **VERIFIED 2026-07-13** (a real turn-in reflected via
  `/dl craft gp`), so it now fires automatically: one-shot on login (craftwatch
  `dlac-craftwatch-gp` tick) + on EVERY entry into the Auto Craft Set view (triggersui,
  >1s render gap = just entered; `force=true` skips the 5s debounce â€” Henrik wants each
  visit fresh â€” with a 1s anti-flicker floor). Offsets locked by tests T27â€“T33.

### UI / misc
- Sets: **duplicate-row button (D)** â€” one item across several level ranges (Rajas 30-54,
  Lava's 55-74, Rajas 75+); prominent `[Lv 30-54]` badges (green = live now).
- **Sub-slot HARD RULE (reverted 3Ã—, ADR 0006 addendum, memory: sub-slot-building-never-gated):**
  while BUILDING, the Sub picker ALWAYS offers every shield/grip/one-hander â€” never gate on
  DW / Main shape / empty Main. The `A* HARD RULE` tests fail on any re-gating.
- Set-entry names resolve **case-insensitively**; a missing name warns ONCE (not per rebuild).
- Augment stats now show (gold `Aug:` tag) in Sets rows, the +Add picker, and Alternatives.
- Header: Macro button â†’ small book icon; new craft-bar helmet toggle. `filetex.lua` loads
  `assets/*.png` (MUST retain the texture object â€” storing only the numeric handle GC'd the
  texture and hard-crashed the game on ImageButton).
- Craft glyphs: FFXIV Set-8 class icons in `assets/craft/` (Miner = Bonecraft). Panel craft
  icons are a VIEW-ONLY section switch (centered, no label); the craft BAR sets the active
  craft. Artisans Torque/Ring owned â‡’ the guild torques/rings show green (synergy implies
  you owned them all).

**Test suite: 189 checks, all green.** Sections T (craftwatch), V (AutoCraft overlay
resolution), W (tier/binding calc) added this arc.

## Session "field-hardening marathon" (c89bcd85 continued, 2026-07-11 â†’ 07-13, on `main`)

**Theme:** Henrik live-tested everything on WHM/BRD/SMN and every report became a
same-hour fix with a pinned regression test. Engine VERSION 12 â†’ 29. Ran **in parallel**
with the crafting session above â€” two Claude sessions committing to the same checkout
and to `main` simultaneously (expect branch flips, swept working-tree edits, and version
numbers claimed under you; always re-read files after any git operation).

**Max-MP grew up, then stepped back into the shadows (v13, fmtver 2-4).** Four field
bugs in one report: the manifest derivation read `gData` (which DOES NOT EXIST in the
addon state â€” job was always nil, only All-jobs gear passed); single level-99-checked
picks had no fallback (Bunzi's Robe blocked the whole body slot at RDM74) â†’ per-slot
LADDERS picked at live level (`dispatch.mpPick`, K-tests); MP-EQUIP only touched slots
the dispatched set wrote â†’ coverage pass for unaddressed slots; Convert and level-scaled
MP now count (Tamas Ring 15â†’29@74, via THE central `levelstats.effective` resolver â€”
gearui/gearoptim/triggersui all delegate; L-tests). Verdict: picks now believed right,
but MaxMP is **unlisted from the Automations table** (unofficial pending more
troubleshooting; `/dl mode maxmp` + manifest data + detail view all still work).

**The engine tick (v15) â€” the biggest architectural change.** LAC only parses
HandleDefault while OUTGOING packets flow; standing still in a menu starved dispatches
(first misread as an equip-menu block â€” **field-falsified**: `/lac equip` works with the
window open; v14's pause was removed). A throttled d3d tick in the LAC state now drives
`gState.HandleEquipEvent('HandleDefault','auto')` every 0.4s â€” menus open, standing
still, whatever. It also: drops maxmp on job change, skips while ZONING (v24 â€” the tick
otherwise crashed legacy profiles in LAC's equip.lua mid-zone), and synthesizes
PetAction (below).

**Modes are dlac-owned now (v15-v17).** modestate.lua is written on change AND read back
on engine load (same-job + 1-hour freshness guards â€” a mid-session Reload LAC heals,
last Tuesday's DT-mode stays dead). The v16 "stale cycle value purge" was
**field-falsified on WHM**: mode DEFINITIONS are per-job trigger data but VALUES are
session-global by design ("WHM Weapons" defined in BRD's file gates WHM's sets) â€” purge
removed (v17), setMode hardened (cross-job value jumps work; bare flips can't
toggle-corrupt a foreign cycle value; M-tests). Mode keybinds queue ONCE per session
(v18 â€” the automations rescan pings '/dl triggers reload' constantly and re-parsing
re-queued /bind forever). Mode DELETE is reference-aware (v16): a movable window lists
every rule and set-entry reference with one-click cleanup; delete commits immediately
and clears the live flag.

**Virtual markers hardened (v19, v20).** The Sets tab commits a GATED virtual as
`{gear="dlac:AutoIridescence", mode="Weapon:Caster"}` â€” BOTH utils' flatten (v19,
N-tests) and gearui's resolveSetItem (v20) only recognized bare strings; the wrapper
form vanished/flattened to nothing. A Main staff marker now pairs as a 2H staff so
grips stay legal in Sub (P-tests), gets an 8-element wheel icon (drawn, no texture),
and the automations derivation is JOB-CHECKED like everything else (Foreshadow +1 is
BLM/DRK â€” it sat in WHM's manifest looking dead; fmtver 4, red rows for
owned-but-wrong-job in the detail views).

**Reload LAC is nearly extinct (v21-v22).** Henrik's insight: gProfile.Sets is a live
Lua table â€” the reload was only ever about the FILE changing under it. '/dl sets reload'
re-reads <JOB>.lua SANDBOXED (profilesets' extractor hardened for the LAC state: gFunc/
AshitaCore/package/print/coroutine stubbed, stub __concat survives the boot line's
path-building) and swaps .Dynamic in place + re-flattens. The GUI pings it on every set
Commit/Delete. Reload LAC remains for: engine updates (version banner) and failed swaps.

**Level ranges own their windows (v23).** Garrison Tunica +1 ranged 20-51 lost to an
unbounded Lv48 robe at 50 â€” ranged-and-live entries now form a tier above unbounded ones
(engine + GUI preview mirror, Q-tests). A header `Lv <n>` button overrides the main
level for testing/preparing (addon global + '/dl set level main' for the engine; `*`
while active).

**Trigger rules: multi-set + searchable (v25).** One rule may wear an ORDERED list of
sets (`set = { 'WindSkill', 'Madrigal' }` â€” the Madrigal case), applied later-overlays-
earlier per slot; rule boxes grew reorder arrows and per-name [missing] checks
(R-tests). All set pickers are searchable â€” built as button+popup (InputText inside
BeginCombo kills clicks on this imgui build) â€” and every list row's imgui id must carry
the NAME (a shared '##..._o' suffix made only the first row clickable).

**PetAction â€” pets work now (v26, v27, v29).** NO LuaAshitacast version calls a pet
handler (the upstream tutorial's HandlePetAction says "you'll have to call it yourself"
â€” it's a DIY pattern); dlac's tick IS that pattern: dispatches 'PetAction' once per
pet-action start (ctx from gData.GetPetAction â€” Name/Skill/Element shape, matchers just
work; S-tests). Two field bugs: equips must be BRACKETED (gFunc.EquipSet only writes
LAC's buffer; the tick wraps ClearBufferâ†’dispatchâ†’ProcessBuffer, v27) and the
Default-hold must cover LEGACY profiles (gState.HandleEquipEvent wrapped once: while
the pet acts, HandleDefault is skipped entirely â€” a hand-written SMN profile stomped
the pact gear every tick, v29). **Field-verified end to end: Shining Ruby equips,
holds, releases.**

**Files & data:** login dup-burst root-caused (pre-login addon load left the EMPTY gear
template as the sync baseline â†’ +620 duplicates spliced into gear.lua; fixed + restored
from the same-second backup; sync prints debug-gated). BRD.lua stripped to pure dlac
(sets + shims only; backup `BRD.lua.pre-strip`). STATIC set deletion shipped
(structural root-walk, T-tests; picker next to Copy from; the main Delete explains
statics). Static sets on SMN cleaned by Henrik.

**GUI conveniences:** per-job macro books (header button; picker = the game's own list
look, 2 columns Ã— 20 named rows â€” names decoded from USER/<id-hex>/mcr.ttl+mcr_2.ttl,
24-byte header + twenty 16-byte titles; applies on click AND login/job change).
Teleports header dropdown + PF-style floating pinned button (themed â€” unthemed windows
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
handshake at the top of dispatch.lua â€” utils' captured reference and the profile shims
run the new code with no re-require. Why this was nearly free: mode state already
survives via the modestate mirror (loadModeState on init), the pet-hold wrap is
guarded (`_dlacPetHold`) and captures no engine state, and utils calls
`_dispatch.dispatch` through the table at call time. The re-run re-registers both
event handlers (unregister-first, pcall'd â€” deterministic whatever Ashita's same-alias
behavior); swap semantics = Reload LAC semantics (modes kept, slot locks reset,
modestate re-stamped so the banner clears). Failures degrade to today: syntax errors
are caught by loadstring before execution; a mid-execution error rolls `M.VERSION`
back, re-stamps modestate (banner stays honest), and remembers the broken CONTENT
(`M._swapFailedRaw`) so a same-version fix still retries but a broken build isn't
re-tried every 2s. X-tests cover the handshake identity and the version-parse (a
reformat of the VERSION line would kill the swap silently). **One manual Reload LAC
is still needed to get v32 itself live** (v31 has no swapper); after that, engine
updates land within ~2s of an addon reload. The banner stays as the fallback detector.
Dev loop is now: edit â†’ reload dlac addon â†’ watch for "[dlac] engine hot-swapped".
NOT yet covered: utils.lua staleness (rarer; same trick applies if it earns it).
**Field-verified same day, both directions** (v32â†’v33â†’v32 by editing the SEEDED file
while Henrik played; modestate re-stamped within seconds each time). Bonus find: the
login BOOT RACE is real â€” at 13:15 LAC required the old v31 file ~seconds before the
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
- **Picker DB corrections:** ~40 ability/spell levels differ from the wiki â€” planned
  wiki-sourced overlay (list in docs/reference/catseyexi-jobs.md "dlac impact").
- **Stat hover descriptors** (text ready in tools/api_cache/stats_tiers.txt).
- **Iridescence detection**: replace triggersui's curated UNIVERSAL list with a catalog
  `Stats.Iridescence` scan.
- **TPBonus display scale** decision open (server stores 1000 = +100 TP).
- **Auto-build permissiveness** (plan-style like the Add popup?) â€” open user decision.
- **Augment decoder boundary** (stop at first 0x0000 word) â€” verify before changing.
- dlacprobe addon dormant at `Ashita\addons\dlacprobe\` â€” reuse for packet questions.
- ~~**Guild-points self-request (VERIFY, then automate)**~~ **CLOSED 2026-07-13:**
  Henrik turned in GP items and confirmed `/dl craft gp` (c2s `0x10F` self-request â†’
  s2c `0x113`) reflects the new total. Automation re-enabled exactly as planned:
  one-shot fetch on login (craftwatch `dlac-craftwatch-gp` d3d_present tick â€” waits
  for main job â‰  0 and not zoning, fires once, unregisters itself) + a fetch on EVERY
  entry into the Auto Craft Set view (triggersui `_gpSectionSeen`, >1s render gap =
  just entered; `requestGuildPoints(true)` forces past the 5s debounce per Henrik â€”
  1s floor dedupes flicker). `/dl craft gp` stays as the manual verify tool. Offsets
  locked by tests T27â€“T33.

### Loose ends added 07-13 (field-hardening arc)

- **MaxMP relisting**: the Automations row is removed on purpose (picks believed correct
  now â€” job/bag/ladder/scaling all fixed); re-add one `rows` entry in triggersui when
  Henrik declares it official.
- **WS bailout gap**: stripping legacy profiles (BRD done, backup `.pre-strip`) lost
  gcinclude's CheckWsBailout (cancel WS at bad TP/range). No dlac equivalent yet;
  offered as a feature, unclaimed. SMN/others still run legacy handlers â€” strip per
  job only on request.
- **Two sessions, one checkout**: the git checkout flip-flops between `main` and
  `feature/storage-move` (game loads whatever is checked out; both carry everything â€”
  only /dlmv differs). Commit on the CURRENT branch, sync the other via worktree,
  never push feature/storage-move.

## Session "profile storage layer" (07-13, engine v33)

**Theme:** Henrik's brother suggested a layer of PROFILES â€” named bundles of sets.
One design conversation later it became the storage move that also answers
import/export and "new players never touch legacy files".

**Landed:** `profiles.lua` (new, seeded to `<char>\dlac\` like utils/dispatch) â€”
active pointer `dlac\profile.lua`, storage `dlac\profiles\<Name>\{sets,triggers}\<JOB>.lua`;
engine v33 auto-installs "active profile + current job" into every fresh `gProfile`
(LAC load / job change / `/dl profile use` â€” the factored `/dl sets reload` core), so
LAC's own job auto-load composes with profiles for free: the profile picks the folder,
the job picks the file. Commits/deletes now land in profile storage (first commit
imports the job file's Dynamic block verbatim); `/dl profile use|new|clone|migrate`;
migration = backup-first (byte-verified, never overwritten, refuses re-runs) â†’
verbatim Dynamic move â†’ trigger move â†’ clean-shim rewrite, dry-run by default, every
step printed. "Copy from static" reads `backups\pre-profiles\` forever. Tests Y1â€“Y33
(extractâ†’frameâ†’extract byte-identical roundtrip; setmanager scanners unchanged on the
framed file; planner skip rules; headless safety). Docs: `docs/design/profiles.md`.

**Key decisions:** one compatibility rule everywhere (reads fall back per file to
legacy; writes always land in profile storage); collision semantics stay FULL REPLACE
(merge rejected â€” nothing to merge against after the first flatten; sparse sets should
seed via Copy-from-static) with a once-per-load `warnShadowedStatics`; profile names
one word `[%w_-]`; migration always lands in `Default`; the first backup is sacred
(existing backup = file skipped). Veterans: dlac stops writing their `<JOB>.lua`
entirely â€” the overlay contract (their code first, dispatch last per slot) unchanged.

**Loose ends:** GUI has no profile switcher yet (chat commands + a "Profile: X" line
in the Sets tab â€” deliberate, gearui is at the 200-local cap); "Delete static" on a
backup-sourced static reports not-found (harmless; statics live in the backup after
migration); `ashita.fs.get_dir(root, '.*', true)` as a DIRECTORY lister is unverified
in the field â€” `listProfiles` degrades to nil (status still names the active profile).
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

Field-verified same day (weights show on Midshort); follow-up ruling: the
weights editor LIVE-APPLIES -- the number in the box is the weight, no Set
click (too easy to miss). Mid-typing values apply transiently and
self-correct; the Add row keeps its button (a half-picked stat shouldn't
spring into existence).

## Session "craft Sub guard -- Kupo Shield vs the scythe" (07-14)

Field report (Henrik): AutoCraft's Kupo Shield and a Default set's scythe
knock each other off every dispatch (the game can't pair a shield with a
2H/H2H main, so each pass re-equips one and removes the other). His sketch
was a temporary `/lac disable main` + re-enable on craft off; the craft
memory's dead-ends note rules that out (`/lac disable` blocks `/lac equip`
too, and an abnormal craft end leaks a dead slot). Engine fix instead
(dispatch v37): when the craft overlay owns SUB and brings no MAIN,
equipResolved HOLDS any set Main that can't pair with that Sub --
`utils.subSlotAllowed` (the shared pairing rule) decides, so 1H mains keep
equipping next to the shield; unknown names are left alone. The hold is a
post-pass on FINAL names (covers dlac:AutoStaff/AutoAcc-resolved mains),
traced as `Main=... HELD` in /dl why, and stateless: overlay gone -> Main
dispatches again, nothing to re-enable. utils exports resolveGearName for
the record lookups (old LAC states degrade gracefully: guard just stays
off until Reload LAC). Tests AF1-12.

## Session "multi-add popup" (07-14)

The Sets tab's + Add popup no longer closes on a pick (Henrik: "you may
want to add more stuff"): both the item rows and the dlac:* virtual rows
just add, the added entry drops out of the pick list next frame (inList)
as the click feedback, and a dim header hint says the popup stays open
(Esc / click outside closes). Works because every selectable there lives
inside a child window, so ImGui's Selectable-closes-popup default never
applied -- the explicit CloseCurrentPopup calls were the only closers.

## Session "stat classification round 2 -- the 300-mod adoption" (07-14, on `main`)

The full row-by-row sign-off ran in one sitting: Henrik reviewed every section
top-to-bottom (Defense -> Offense -> Magic -> HP/MP+Skill -> Ability in 3 job
batches -> Pet -> Misc) against a live artifact sheet with per-mod example gear.
Wiring landed as one pass: **302 new statdefs entries** (300 crawler mods + the
augment-only SongRecast-mate OccQuickenSpell and Pet_STR), two NEW statdefs
sections **Ability** and **Pet**, 298 CORE pairs in apicrawl/apiscan (kept in
sync), DMGPHYS_II/DMGMAGIC_II added to BASIS100 (PDTII/MDTII, mixed /100 scale).
Catalog rebuilt from the existing cache (--build-only, zero network -- Henrik's
"reuse the crawl" call, which is how the pipeline was designed): **516 distinct
stat keys in catalog.lua** (was 216), 67,361 stat instances, still ZERO
unclassified. ignored_mods.txt: 409 -> 109 (the deliberate skip/investigate/
relic buckets). 320 tests green.

Labeling rulings that came out of the review (memory: stat-naming-chance-rule):
proc stats say **"Chance"** ("Annul Phys Chance" -- never readable as a partial
reduction); cast speed says **"Cast Time-"** (legacy Song Cast/Cure Cast renamed
to match). "Divine Veil" name confirmed by Henrik (trait: always-on Divine Veil,
-na spells work AoE). Open VERIFY flags (grep statdefs for VERIFY): Restraint
values, Chakra-Removal bitmask, RewardRecast sign, WhiteMagicCost scale (300),
RegenPotency flat-vs-%, RefreshPotency potency-vs-duration, SummoningMagicCast
seconds. INVESTIGATE bucket still parked: CatsEyeXI 2000-series customs + the
value-73 HARVESTING/LOGGING/MINING mods. Full disposition:
tools/api_cache/stats_tiers2.txt.

Mid-session note: the checkout flipped to feature/autoacc under this session
(parallel work); the Song/Cure Cast Time- rename was committed there (bb47d3e)
per the parallel-session rule and cherry-picked back to main (e934b32) once the
checkout returned.

## Session "lockstyle sets" (07-15)

A NEW set type (Henrik's spec): lockstyle sets -- one item name per VISUAL
slot, 30 numbered boxes, applied through LAC's own packet builder. Pieces:

- **lockstyle.lua** (addon state, own module -- hard rule 1): the window is
  the Equipped-tab 4x4 (gearui INJECTS renderSlotGrid/renderIcon/tooltip/
  catalog via M.wire -- load order forbids requiring gearui) editing a
  working copy; right of it, 30 boxes in 3 macro-menu columns. Box 1 is
  marked until chosen otherwise; Save lands in the MARKED box under the
  typed name; switching boxes with unsaved edits warns first (continue =
  discard). "Import from static..." copies a static set's visual slots
  (profilesets -- live job file + pre-profiles backups, where old lockstyle
  statics live). Slot picker offers gear.lua items for the slot (job-
  filtered) plus "(clear)" and "(hide -- LAC's 'remove' literal)". Non-
  visual slots (neck/ears/rings/waist/back) are inert: packet 0x53 carries
  equip slots 0-8 only. Storage: <char>\dlac\lockstyles.lua
  { active, onload = {JOB=box}, slots } -- serializer is pure (AG10-15).
- **Engine apply (dispatch v38):** '/dl ls apply [box]' in the dlac-dispatch
  command handler -> read lockstyles.lua -> M._lockstyleFrom picks the box
  (explicit n > active > 1; AG1-9) -> gFunc.LockStyle. The SAME handler runs
  in the addon state (gearui/triggersui require dispatch there): the gFunc
  guard keeps that side silent -- exactly one printer. Self-swap delivers
  v38 live; no Reload LAC needed for the command.
- **OnLoad Lockstyle:** binds CURRENT JOB -> MARKED BOX; macrobook's pump
  pattern queues '/dl ls apply <box>' ~6s after login / ~3s after a job
  change (post-zone grace; runs a beat after the macro book apply).
- Header button (Henrik's golden-armor icon, assets/lockstyle.png) sits
  LEFT of the Macro book, filetex/ImageButton 16x16 like its neighbors; the
  window renders from the present hook independent of the main box.

Field round 1 (same night): the confirm popup's side-by-side buttons
clipped at the themed font -> stacked vertically at 260w; Save matches the
name box height (h=0 = frame height); the static-import combo widened
186 -> 216. Plus **Preview** (his ask): '/lac disable' + '/lac naked' +
native /equip of the WORKING copy's wearable pieces (level/job-gated ones
are skipped, never blocked from being picked); End preview = '/lac enable'
and the engine redresses next dispatch. The pump ends a live preview if
the window closes -- nobody stays stripped with LAC disabled.

## Session "lockstyle round 2 -- the engine-native preview" (07-15)

Henrik's correction on the round-1 preview ('/lac disable' + manual /equip
= "not what we usually do"): the preview must be a top-priority overlay
INSIDE the engine, continuously fed by the working copy -- see
[[engine-native-over-commands]], his own standing ruling. Round 2
(dispatch v39): lockstyle.lua writes <char>\dlac\lspreview.lua on EVERY
working-copy mutation (all edit paths funnel through touched()) plus a
~10s heartbeat from the pump; the engine reads it craftstate-style, and
while enabled the preview OWNS Default -- equipResolved wears the pieces
(LAC's wearability checks skip under-level picks: allowed, never forced)
and UnequipSlot strips every uncovered slot (it self-guards on "anything
there?", so stripping settles after one pass). Heartbeats older than 30s
are dropped: a dead addon can never leave the player stuck stripped.
Closing the window ends the preview (pump). Traced as 'lockstyle preview
(overlay) -> ONLY {...}' for /dl why. Also: box buttons show the NAME
only (the number ate the width; tooltip keeps it), and a Del button
(confirm popup) removes the marked box + its OnLoad bindings. Tests
AG16-20 pin the plan (equip vs naked indexes).

Round 3 (same night): Apply -> "Apply lockstyle"; a "Disable lockstyle"
button sits top-right of the box-header row (the game's native
/lockstyle off -- queued, never intercepted per [[lastsynth-native]]);
and Preview queues /lockstyle off FIRST, every time -- a live lockstyle
visual hides equipment changes, so an un-disabled preview shows nothing.

## Session "the uihost split -- gearui off the 200-local ceiling" (07-15, feature/uihost)

Henrik asked what eats the "200 gui entities": it is the LuaJIT
200-local-per-chunk cap, and gearui.lua sat at EXACTLY 200/200
(compiler-verified -- appending one local fails the luac parse with "too
many local variables"). Investigated trove (sibling addon) as the model:
thin host + plugin registry (utils/plugins.lua), plugins contribute
tab/window/commands, host injects shared services, plugins own no
authoritative data. Verdict: adopt the CONTRACT, not the auto-discovery
(io.popen 'dir /b' spawns console windows -- static require list instead).

Landed as 9 commits on feature/uihost (main untouched by request):
mechanical wins first (try() require helper kills 12 pcall-ok temps;
has{} flag table; COL{} palette table -- 200 -> 171), then uihost.lua
(register{name,tabs,window,invalidate} + host.provide/services), then
the extractions: itemicons (D3D texture cache), equippedui (both browse
tabs; captures host.services at load -- provide-before-require is
load-bearing), setupui (jobSetupState + migrateCurrentJob, configure{}
deps), syncflags (auto-sync + uiflags; owns sf.flags.debug/.autosync;
loadUiFlags-before-tick hook order preserved), weightsui (editor only --
scoring stays with the Sets candidate machinery), profilesmenu (the
~400-line Profiles popup out of drawWindow). gearui: 200 -> 134 locals,
4680 -> ~3290 lines; every new module <= 27 locals.

New regression net: tests\smoke_ui.lua (46 checks) headless-loads the
whole UI chunk -- run_tests.lua NEVER loaded gearui, so the 200-cap and
registration/load-order bugs had zero coverage before. It caught one
real bug during the split (an imgui~=nil guard silently skipping tab
registration headless). Weights window = first uihost WINDOW contract
(host.renderWindows). Henrik verified in-game mid-branch: "everything
seems to work so far".

Key invariants for future modules: provide services BEFORE requiring a
tab module; one d3d_present hook (gearui's) calls sf.loadUiFlags then
sf.tick; modules capture ui/COL tables at load but they are stable
references; profilesmenu.render() must run inside gearui's imgui.Begin
(OpenPopup/BeginPopup share window scope).

## Reserved slots -- the infinite equip flash (2026-07-15)

Henrik: "items such as Royal Footmans Tunic, which reserves both body and
head. When that collides with another head piece, it just flashes back and
forth infinitely." He remembered ffxi-lac having logic for it -- check a
"canwearheadpiece" boolean once the set was chosen, drop the head piece if
false -- and asked why dlac didn't.

dlac DID have it. `utils.lua` carried the ffxi-lac block verbatim, implicit
global `bodyGearObject` and all. It was dead code: it keys off
`CannotEquipHeadgear`, which nothing in dlac has ever written, so it read nil
every pass. In ffxi-lac itself the flag was hand-authored from parsed item
description text and true for exactly TWO items (Royal Cloak, White Cloak) --
and the parser had mangled it on the Ryl.Ftm. Tunic ("Cannot Equip Headgear
DEF:12" glued into one token, commented out), so the very item Henrik named
was broken there too. The remembered fix never actually covered it.

The real fact is server data: `item_equipment.rslot`, "the slots this item
takes away while worn", and the API exposes it per item. It was sitting in
tools/api_cache the whole time, thrown away by apicrawl's `slot_name()` (which
reads `slot`, not `rslot`). 388 items carry one; the scan across the cache is
worth keeping:

    Ammo  -> Range   135   thrown/pet food (Pebble, Angon, broths, sachets)
    Body  -> Hands    74   long-sleeved robes (Decennial Coat)
    Legs  -> Feet     71   (Marine Boxers)
    Body  -> Head     52   hooded cloaks -- incl. Ryl.Ftm. Tunic
    Range -> Ammo     35   boomerangs / throwing (Rogetsurin)
    Body  -> Legs     11   party suits
    Body  -> Hands+Legs+Feet / Hands+Feet / Head+Hands   9   suits
    Range -> Range     1   Flamedancer Glaive -- reserves ITSELF

Two traps in that data. Arrows/bolts/bullets reserve NOTHING (404 ammo items
clean) -- only *thrown* ammo blocks a ranged weapon, so RNG/COR sets are
untouched; had the rule been "ammo conflicts with range" it would have broken
every archer. And the self-referential record means the item's own slot bit
MUST be masked out at crawl time or it reads as "removes itself".

Fix: `RSlot` in catalog.lua (387 lines added to a byte-identical rebuild --
`--build-only` off the cache, no network), stamped into gear.lua by the scan
and backfilled by `/dl fix` (the LAC-state engine has no catalog -- same
reason Type/OneHanded/Count live in the file), resolved by
`dispatch.reservedDrops` as an equipResolved post-pass. See the ADR 0006
addendum for WHY it is engine-time and not build-time (short version: sets
overlay, so two individually legal sets can overlay into an illegal pair, and
MP-EQUIP writes slots no set named).

Design points worth not re-deriving:
- **Worn pieces reserve too.** The common case isn't a set naming both slots;
  it's a set that only writes Head while the Tunic is already on your back. A
  slot the set DOES write is judged by the plan, not by what it replaces (a set
  swapping the Tunic out keeps its Head).
- **Fixed slot order, not pairs().** Boomerang reserves Ammo, a pebble in Ammo
  reserves Range -- mutual. Bit order resolves it identically every pass, and
  makes a dropped slot stop reserving (Body takes Legs -> the Legs piece must
  not go on to take Feet).
- **No `bit` library.** dispatch runs headless on 5.4 (no `bit`) and in LuaJIT
  (no `&` operator). `hasBit` is arithmetic; works in both.
- Henrik owns 12 reserving items (4 Body->Head incl. both cloaks ffxi-lac knew
  about, 8 thrown/tathlum/shuriken). `/dl fix` stamps them.

## Session "floating equipment window + PINNED slots" (07-15, dispatch v44)

Henrik: *"You know the equipmon addon? Since we already have a feature for 4x4 equip
viewing, can we do the same under Equipped... right click on any equipment, get a list
of all available equipment to equip, choose it, and hard set so it overrides everything
within the DLAC engine."* Then, on the word: *"that 'Lock' description sounds exactly
what I want. Equip item, lock slot so nothing removes equipped item. But Pin may be a
good word to describe that process."*

### CORRECTION: right-click WORKS. The dead-ends list was wrong for 5 days.

The 07-10 entry read "right-click context menus in this ImGui binding (two failed
rounds)". That is **false and it nearly killed this feature** â€” the first design round
here was built around avoiding right-click entirely. Henrik: *"check
feature/storage-move, that one has right click working in the all equipment menu."* He
was right. `gearmove.lua:663-669` on that branch:

```lua
-- Trigger 1: right-click (field-confirmed working in this client).
if imgui.IsMouseClicked(1) then
    local over = opts.window and imgui.IsWindowHovered() or imgui.IsItemHovered();
    if over then imgui.OpenPopup(pid); end
end
```

What actually failed twice was **`BeginPopupContextItem`** specifically â€” not RMB
delivery. `IsMouseClicked(1)` + `IsItemHovered()` feeding the ordinary
`OpenPopup`/`BeginPopup` pair is field-confirmed. The `[mv]` button survives on that
branch only as "Trigger 2 (guaranteed)", and `moveButton`'s comment there still claims
RMB is unreliable â€” stale, contradicted by the function right below it. Dead-ends
entry corrected. **Lesson: record the API that failed, not the gesture you gave up on.**

### The pin, and why it is not a lock

Henrik's ask was literally "lock the slot" and dlac already has `/dl lock` â€” but that
word is taken, and it means close to the OPPOSITE: `M.locks` makes the engine *ignore*
a slot. A lock is passive (anything else that strips the piece wins) and it LEAKS â€”
history: *"engine-owned slot locks (LAC forgets `/lac disable` on reload)"*. So the
outcome he described is delivered by the craft-overlay pattern instead: the engine
**wears** the pinned item at top priority every dispatch. Nothing can remove it,
nothing to restore, nothing to leak. He named it **Pin**; "lock" keeps its old meaning.

### Landed

- **dispatch v44**: `ensurePinState` (clone of `ensureCraftState` â€” 1/sec throttle,
  raw-text compare), `pinOverlayFor(ps, hits, event)`, applied as the LAST
  `equipResolved` of the dispatch â€” above the craft overlay, on **every event** (a pin
  that lost its slot mid-cast would not be a pin) and with zero trigger hits.
- **Scope.** `scope = 'All'` or a list of `"<Event>|<rule label>"` keys
  (`M.pinScopeKey`). Label alone is ambiguous â€” `any` is the label of EVERY
  unconditional rule, so a Precast `any` and a Midcast `any` are indistinguishable and
  one pin would silently cover both. An unknown key goes **quiet** rather than
  falling back to "All" (a pin on a trigger you later edited must not start forcing
  gear everywhere).
- **`M.ruleLabel(when)` â€” new, and a real bug fix.** normalize built the label with
  `tostring(cv)`, but `when.mode` can hold a LIST (triggersui.lua:312) and
  `tostring(table)` is an ADDRESS: different in each Lua state, different after every
  reload. Multi-mode rules had garbage labels in `/dl why` already; a scoped pin could
  never have matched one. Now ONE definition, used by normalize AND by the pin menu,
  serializing lists by value (sorted). Tests AL18-23.
- **Sub-vs-Main, both directions** (the v37 flap is the worst bug class here): a pinned
  Sub with no pinned Main becomes the `craftMainGuard` source, so it survives the set's
  Main AND the craft overlay's; and a pinned Main drops a craft Sub it cannot pair with.
  Tests AL26-33.
- **`feature/pinwatch.lua`** (addon state): owns the table, writes `pinstate.lua`,
  `serialize` is pure + **sorted** (dispatch content-compares the raw text before
  re-parsing; unstable key order would defeat that cache every second).
- **`ui/floatgear.lua`** (uihost module, hard rule 1 â€” gearui gained no locals): the
  4x4 window via the shared `S.renderSlotGrid`, so icons and the full hover tooltip
  can never drift from the Equipped tab's. Toggle + position persist via uiflags
  (`gearfloat`/`gfx`/`gfy`, the `tpfloat` precedent). Pinned slot = **red box**.
- `renderSlotGrid` grew two optional hooks: `opts.boxColorOf(sl)` and
  `opts.onRightClick(label)`. The grid only REPORTS the RMB â€” it lives inside its own
  `BeginChild` and OpenPopup/BeginPopup must share a window scope, so floatgear raises
  a flag and opens the popup at its own level.
- Tests: **AL** (pin overlay, scope, ruleLabel, guards, the RSlot flap) + **AM**
  (pinwatch round-trip through the engine's own reader, adversarial names). 426 -> 490
  green; smoke_ui 49 -> 53 (S14-17 prove floatgear actually loaded â€” gearui requires it
  inside a pcall that only PRINTS on failure, so without those checks a broken module
  would sail through as a silent no-op window).

### Three bugs an adversarial review pass caught AFTER the tests were green

Worth recording because all three were invisible to 471 passing checks:

1. **The v43 flap, reached through the overlay.** `reservedDrops` judges ONE table at a
   time, on its final names â€” but the pin lands in its OWN `equipResolved`. So the SET's
   pass never learned that the pinned Ryl.Ftm. Tunic was about to reserve the Head it
   was equipping, and the pin's pass couldn't drop a Head its table never named. Set
   equips Head â†’ pin equips Tunic â†’ server strips Head â†’ forever. Craft has the same
   hole but its catalog is narrow; **a pin is any item you own â€” including the Tunic,
   the exact item that motivated v43.** Fixed with `pinReservedSlots` + `ctx.pinReserved`,
   a stateless hold in `equipResolved` (the ratified pattern) rather than widening
   `reservedDrops`. Tests AL34-41.
2. **Both overlays were dead whenever the event had no rules.** `if list == nil or
   #list == 0 then return; end` fired BEFORE the overlays were consulted, so an "All"
   pin did nothing on a profile with no triggers â€” and the craft overlay's own comment
   ("a plain profile still gets craft gear") had been **false since v31**. M.dispatch now
   decides whether there is anything to do from rules + pins + craft together, ahead of
   the early return, using the already-throttled cached reads.
3. **A corrupt pinstate.lua kept the LAST GOOD pins forever.** `_pin.raw = raw` is
   assigned before the parse, so on a syntax error the raw-compare short-circuited every
   later call and stale pins stayed glued on with nothing able to clear them â€” including
   pinwatch's clear-on-load. `ensureCraftState` still has the identical shape (v31).

Also from that pass: `fmt.esc` was being applied to Selectable/MenuItem labels â€” esc
doubles `%` for imgui's FORMATTING calls (Text/TextColored) only, so escaping a
non-format label renders a literal `%%`. Nothing else in dlac escapes a Selectable
label; matched.

### Traps found while building

- **The clear must reach DISK, not just the table.** Pins are session-only (craftwatch's
  rule: no gear glued on at login from last Tuesday). But the ENGINE reads pinstate.lua
  from LAC's own state on its own schedule â€” clearing only the addon-side table would
  leave a stale file dressing you at login with nothing aware of it. `loadPinState`
  writes the empty file, and it is pumped from gearui's `d3d_present` **whether or not
  the window is open** â€” it is the only thing that clears it.
- **`tests\run_tests.lua` hit the 200-local cap too** (it is one ~1800-line main chunk;
  482 checks got it there). A `do ... end` block does NOT help â€” its locals share the
  enclosing chunk's budget. New sections are `(function() ... end)()`, which gets its
  own 200; that is also the cheapest fix when an older `do` section tips it over.
- `subFilter(cands, mainRec, job, level, building)` â€” the 2nd arg is the Main RECORD,
  not the job. Gating the pin menu's Sub by the worn Main is correct and NOT a breach
  of the Sub HARD RULE: that rule protects the BUILDER's Sub picker (sets are plans);
  a pin equips immediately, like the Alternatives list, which gates too (ADR 0006).
- `BeginMenu`/`EndMenu` are in the SDK and their symbols are in Addons.dll, but NOTHING
  in the whole install calls them from Lua â€” and presence proves nothing
  (`BeginPopupContextItem` is bound too, and broken). floatgear probes
  `type(imgui.BeginMenu) == 'function'` at load: bound -> the cascade Henrik asked for;
  not bound -> the same choices as an in-place drill-down (gearmove's quantity-chooser
  pattern, proven). **Unverified live â€” first thing to check in-game.**

### Field round 1 (07-15, same day): "It works!"

Henrik confirmed the whole thing live -- floating window, right-click, cascading
submenus, pinning. Two facts the codebase did not have before, both now in hard rule 2:

- **`imgui.BeginMenu` cascades in this binding.** floatgear is the FIRST Lua caller of
  BeginMenu in this entire Ashita install, so this was genuinely unknown; the probe +
  drill-down fallback are now dead weight kept only as a guard.
- **A submenu is drawn OUTSIDE the rect of the window that declares it.** Henrik: *"the
  whole initial right click menu disappears when you keep moving the mouse to the next
  gear piece, it just cancels the menus all together."* The pin list was wrapped in a
  `BeginChild` for scrolling; moving the cursor from an item toward its submenu left the
  child, ImGui judged the menu hierarchy had lost the cursor, and tore down the entire
  popup. **Menu items may not live in a child window.** The child is gone; the popup is
  bounded with `SetNextWindowSizeConstraints` instead (BeginPopup forces
  AlwaysAutoResize on popups, so a constraint is the way to bound one -- clamped, it
  grows its own scrollbar). Safe to call every frame: this binding is ImGui >= 1.77
  (the header declares `ImGuiPopupFlags`) and BeginPopup's early-out consumes the
  next-window data exactly as Begin would -- otherwise the constraint would leak onto
  the next window opened anywhere in the frame, including another addon's.

Also this round, on Henrik's screenshot (equipmon's look): window chrome off
(`NoTitleBar|NoResize|NoScrollbar|NoCollapse|AlwaysAutoResize|NoBackground` +
`WindowBorderSize = 0`), boxes bundled tight, and the "Right-click a slot to pin" hint
and the pinned-count line removed -- a stray line of text under a chrome-less window
puts the box straight back, so Unpin-all moved into the right-click menu.

`renderSlotGrid` gained `opts.tight`: spacing between boxes AND the grid child's own
WindowPadding both go to 0, so the 4x4 measures exactly 4*40 = 160 square and the window
can auto-size to it. **WindowPadding has to be pushed BEFORE `BeginChild`** -- it is read
when the child opens, and left at the default it insets the grid inside its own box and
clips the last row. The window's WindowPadding is deliberately left alone: with no title
bar an ImGui window moves when you drag any part of it that is not an item, and that thin
rim is the only drag handle a grid of 16 buttons has.

### Field round 2 (07-15): shift+drag and scaling -- "we're done"

- **SHIFT+drag moves the window** (equipmon's gesture). `NoMove` is now ALWAYS on and
  the move is done by hand: `IsWindowHovered(AllowWhenBlockedByActiveItem)` +
  `IsMouseDragging(Left)` -> `GetMouseDragDelta` -> `SetWindowPos` ->
  `ResetMouseDragDelta`. ImGui's own drag only moves a window from a spot no item
  claimed, and a 4x4 of ImageButtons leaves no such spot -- round 1's "drag it by the
  invisible rim" was the best that flag could do and it was a bad answer. **That flag
  is load-bearing:** `IsWindowHovered()` without `AllowWhenBlockedByActiveItem` returns
  FALSE whenever an item is active -- i.e. exactly while you are dragging -- so without
  it the drag silently never fires. With NoMove on, WindowPadding could go to 0 too, so
  the window is now EXACTLY the grid. Left-click and right-click are both suppressed
  while Shift is held: that click is the start of a drag, not a pin.
- **Scaling** via `renderSlotGrid`'s new `opts.box`: ONE number, with the icon
  (`BOX - 2*PAD`) and the frame pad (`round(BOX*0.1)`) derived from it, so at the
  default 40 it reproduces the old 40/32/4 exactly and every other caller is untouched.
  The element wheel scales too (`BOX*0.7` = the old 28). Slider on the Equipped tab
  beside the switch, shown only while the window is up -- it is the one setting you
  cannot discover from a window that has no chrome. Persisted as `gfscale`.
  **`floatgear.scale()` clamps on READ, not at the slider:** uiflags.lua is a plain Lua
  file a player can edit, and a hand-typed 0 would collapse the grid with no way back
  through the GUI. Tests S18-24.

**Every ImGui enum this file needs is a Lua global from `Ashita\addons\libs\imgui.lua`**
(which `require('imgui')` sets), NOT a DLL export -- grepping Addons.dll for
`ImGuiMouseButton_Left` finds nothing and proves nothing. Verified before use, per hard
rule 2: NoMove/NoBackground/AlwaysAutoResize/NoTitleBar/NoResize/NoScrollbar/NoCollapse,
ImGuiHoveredFlags_AllowWhenBlockedByActiveItem, ImGuiMouseButton_Left (== 0),
ImGuiStyleVar_WindowPadding/WindowBorderSize/ItemSpacing, ImGuiCond_Once. Headless they
are nil, hence the `or 0` guards. Position restore uses `ImGuiCond_Once`, not
`FirstUseEver`: FirstUseEver defers to imgui.ini if ImGui remembered the window itself,
and the addon's uiflags copy is the authority (the TP float made the same call).

### The crash (e85cc43 -> f546d71): one PopStyleVar too many

Shipped an `EXCEPTION_ACCESS_VIOLATION` in Present -- dlac failed to load, and
`/exec load default.txt` hard-crashed the client. Mine, and worth the write-up because
of HOW it hid.

The shift+drag round added a SECOND `PushStyleVar` (WindowPadding, so a chrome-less
window could drop to zero padding) plus a `PopStyleVar(2)` right after `Begin` -- and
left the PREVIOUS round's `PopStyleVar(1)` sitting after `End()`. Every frame the float
window rendered popped one style var too many.

**A style-stack underflow is not a Lua error.** It is native UB inside ImGui: no pcall
catches it, gearui's tabGuard cannot contain it, and it surfaces as an access violation
in Present that takes the whole client down. It only fires with the window enabled,
which is why it read as a load/startup crash -- `gearfloat=true` persists in uiflags.lua,
so it was on from the previous session's testing.

**550 green checks could not see it, because nothing in the suite ever rendered.**
smoke_ui says so in its own header: "a LOAD test, not a render test... imgui is nil here
by design". That was a real hole -- the suite could catch a 200-local breach (a crash)
but not a stack underflow (also a crash).

Closed it: **smoke_ui section 6 (S50-S58)** stubs imgui, re-requires floatgear so it
captures the stub, and drives `M.render` for real across four frames -- menu shut, menu
open, shift-dragging, window off -- counting pushes against pops on the var / color /
window / popup stacks. **Verified by re-introducing the exact bug: it fails with
"got -1, want 0" and degrades by one per frame.** It does not prove the window LOOKS
right; it proves it cannot corrupt ImGui's stacks, which is the difference between a bug
report and a crash. renderSlotGrid stays stubbed in that test on purpose -- gearui
captured the real (nil) imgui at its own load, so the genuine grid cannot run headless;
floatgear's own balance is what broke and what is now guarded.

Rule of thumb earned: **when you add a Push, count the Pops in the whole function, not
the one you are looking at.** The two are 90 lines apart here by necessity (the vars are
consumed by Begin and must be popped before the pin popup inherits them).

### Field round 3: shift+drag was dead on arrival -- imgui IO has no keyboard here

Henrik: *"Shift Click still doesn't work though."* The gesture was never firing because
**`imgui.GetIO().KeyShift` is false during normal play**: Ashita only feeds keyboard
state into ImGui's IO when ImGui actually WANTS the keyboard, and standing in the world
with a chrome-less window up, it does not. So `shift` was permanently false.

**The trap worth remembering:** GetIO().KeyShift *is* used in this install -- fancychat
calls it (bigmode.lua:196) -- and "another addon here does it" is the exact check hard
rule 2 asks for. It was still the wrong call, because fancychat's use lives inside its
chat-INPUT mode, where ImGui holds focus. A call can be proven in this binding and still
be wrong for your context. **Verify the API against the SITUATION, not just the install.**

Fixed by using what **equipmon** uses for this same gesture (and equipmon's shift+drag
demonstrably works here): the Ashita **`key` WNDPROC event**, VK_SHIFT (0x10), with
lparam bit 31 as the transition state (1 = going UP). Expression kept identical to
equipmon's.

The drag is also **latched** now: shift+press over the window starts it and it runs
until the button comes up. Re-testing hover every frame dropped it the moment the cursor
outran the window; re-testing shift dropped it if you let the key go mid-drag. equipmon
needs Shift only to START, and this matches. `_dragging` also covers a real gap in the
click suppression -- an ImageButton fires on RELEASE, by which time Shift may already be
back up, and the pin menu would open at the end of every drag.

Tests S55-S63: the smoke stub now RECORDS `ashita.events.register` handlers so the test
drives the real key handler (the transition-bit expression is easy to get backwards) and
asserts the window moves by the drag delta, that no-shift never drags, that the drag
survives Shift coming back up, and that it stops on release. **Verified by restoring the
GetIO version: fails with "shift+press moves the window: got false, want true".**

### Field round 4: shift STILL dead -- ask the OS, not the framework

Henrik: *"still doesn't work :( reloaded both dlac and lac."* Second miss on the same
gesture. Both failed attempts share one root: they asked something that only knows about
Shift **sometimes**.

1. `imgui.GetIO().KeyShift` -- Ashita only feeds the keyboard into ImGui's IO when ImGui
   wants it; standing in the world it does not. fancychat DOES call it -- inside its
   chat-INPUT mode, where ImGui has focus.
2. Ashita's **`key` WNDPROC event** (VK_SHIFT + the lparam transition bit) -- equipmon's
   exact code, copied verbatim. Also never fired here.

Now: **`GetAsyncKeyState` OR `GetKeyState` via ffi/user32** -- ask the OS. True whenever
the key is physically down, regardless of focus, message queue, or which input path the
client uses. `trove` uses GetKeyState for this ("Win32 key state for shift-to-move" --
the same gesture); XIUI uses GetAsyncKeyState. They differ (thread message queue vs
physical key) and after two misses this was not the place to bet on one, so both are
read and OR'd.

**The lesson, and it cost two rounds:** "another addon in this install does it" is the
check hard rule 2 asks for, and it is NOT sufficient. Both failed attempts passed that
check. fancychat's GetIO call is real -- in a context where ImGui owns the keyboard.
equipmon's key hook is real -- and equipmon's shift-drag was never actually verified
working HERE; that was assumed from reading its source. **Verify the API against the
SITUATION, and prefer the layer with the fewest things that can be true "sometimes."**

Hardened the rest of the path at the same time, since a third blind round was not
affordable: the drag starts on `IsMouseDown` (not `IsMouseClicked` -- true for ONE frame,
so any missed frame loses the gesture), and hover is tested with `ImGuiHoveredFlags_RectOnly`
(= AllowWhenBlockedByActiveItem + AllowWhenBlockedByPopup + AllowWhenOverlapped -- and
the combo fancychat has miles on) instead of the single flag.

**Shift now outlines the grid gold.** A chrome-less window has no way to say "grabbable",
so this is a real affordance -- and it makes the next failure self-diagnosing in one
glance: outline = the key read is fine, look at the drag.

`M.shiftHeld` is a seam the smoke suite overrides: the OS call cannot run headless, so
S55-S63 cover the LATCH and the click suppression (the logic that broke), not the key
read. Honest about what it does not prove.

### Field round 5: the indicator was lying, and a keyless route

Henrik: *"there is an outline when I hover over an equipment, but it doesn't change when
I hold in SHIFT"* -- i.e. the gold outline from round 4 NEVER DREW. That outline existed
to tell us which half was broken, and instead it added a third unknown: it used
`GetWindowDrawList():AddRect(min, max, col, rounding, flags, thickness)` -- **6 args, a
signature nothing else in dlac uses** (only the 3-arg `AddRectFilled` is proven here).
Inside its `pcall`, a wrong signature draws nothing and says nothing. **A silent
indicator is worse than no indicator: it can make a WORKING key read look broken.** If
you add instrumentation to settle a question, it must sit on a path already proven, or
it is just another suspect.

Rebuilt on the mechanism Henrik has WATCHED work: `boxColorOf` -> ImageButton's bg_col,
the same thing that paints a pinned slot red. Shift held -> every box goes gold.

Shift detection is now **four sources OR'd** (user32 GetAsyncKeyState, user32
GetKeyState, the Ashita key event, imgui IO). Not elegance -- arithmetic. Three separate
single-source attempts have failed in the field, each picked because some other addon
here "proves" it, each wrong for this context. Every source is independently harmless
and free per frame, so read them all and take any yes.

And a **keyless MOVE MODE** (right-click -> "Move window"): plain LMB drags, slots stop
taking clicks, boxes go gold, right-click -> "Done moving" leaves. Shift detection has
missed three times and every failure looks identical from the player's side -- nothing
happens. This route needs no key at all, so it cannot fail the same way; it also stays
as the accessible option for anyone who cannot chord a drag.

Traps handled in move mode: **right-click is never suppressed** (the drag is a LEFT
gesture, and the menu is the only way OUT -- gating it would strand you), and the drag
latch is cleared when the mode ends. Tests S66-S71 cover both, including the strand
case; S70 caught the latch outliving the mode.

### Field round 6: found it -- the grid is a CHILD window

Henrik: *"It lights up all the boxes when I press shift, even if I don't hover over, I
don't even have to have the game active, so it's definitely detecting shift... still
unable to move though!"* That single report killed three rounds of theory at once: shift
was fine (user32 reads physical state, hence "don't even have to have the game active").
**The drag was broken, and had been from round one.**

**`renderSlotGrid` draws the 4x4 inside its own `BeginChild`.** So when the cursor is on
a slot, ImGui's hovered window is that CHILD -- and `IsWindowHovered()` defaults to an
EXACT window match (`if (ref_window != cur_window) return false`), comparing the child
against the float window and returning **false, every frame**. The latch could never
arm. `ImGuiHoveredFlags_ChildWindows` is the fix, and libs/imgui.lua:324 says so in as
many words: *"IsWindowHovered() only: Return true if any children of the window is
hovered"*. Neither flag I tried contains it -- `AllowWhenBlockedByActiveItem` (round 2)
nor `RectOnly` (round 4, :332).

**Why this cost five rounds, and it is not "shift was hard":** a false `overWin` and a
false `shift` produce the IDENTICAL symptom -- nothing happens. I had two unknowns
multiplied together and kept re-rolling one of them. The first round should have made
the two states distinguishable instead of guessing; the gold boxes did that in ONE round
and immediately said "shift is fine, look elsewhere". **When a gesture has N silent
predicates, make them visible before changing any of them.**

Second lesson, sharper: **`or 0` on a FLAG silently disables it.** Every enum here is
`(ImGuiFoo or 0)` for headless safety -- and if `ImGuiHoveredFlags_ChildWindows` had
been missing, `or 0` would have produced exactly the bug that just cost five rounds,
with nothing to see. HOVER_FLAGS now falls back to the REAL bit values (1 and 32), which
is both correct in game and assertable headless (S72/S73 -- white-box, because the test
stubs renderSlotGrid so there is no child window to hover; verified by restoring the old
flags: "asks about CHILD windows: got false").

### Field round 7: shift+drag works -- and the cue stops being a christmas tree

Henrik: *"reloaded, shift+drag works now!"* -- the `ChildWindows` flag was it.

*"Can you remove so it doesn't light up like yellow christmas lights?"* Fair: Shift is
held constantly in normal play (running, macros), and the cue lit all 16 boxes on the
raw key state -- which is also why it fired with the game unfocused. It now shows only
when Shift could ACTUALLY start a drag (cursor over the window), while a drag is live,
or in move mode -- a state you can get stuck in and must be able to see. Not deleted:
the window has no frame, so the boxes are its only way to say "grabbable", and it is the
instrument that finally found the bug.

`grab` is deliberately the SAME expression as the click suppression, so what you see is
exactly when the slots stop taking clicks. A cue that disagreed with the behaviour would
be worse than none.

The hover read moved above the grid (the colours need it). Safe: ImGui resolves the
hovered window in NewFrame from the PREVIOUS frame's rects, so this frame's child not
being submitted yet does not matter.

**Test-hygiene note worth more than the feature:** the new S74-S76 were first dropped in
after S68, where they had to turn move mode off themselves -- which left S69 ("right
click stays live IN MOVE MODE") passing while testing nothing. Moved to after S70/S71,
where move mode is legitimately off. `cueWith` also returns a sentinel rather than nil
when the grid stub never ran, so "lights nothing" cannot pass for free. Verified by
restoring the christmas lights: S74 fails with "got table, want nil".

## Session "view_ids + lockstyle previews gear you don't own" (07-15)

Two small asks from Henrik: *"add a command `/dl view_ids` [to] view the item and
model_ids (the one's used for lockstyle, I think that was a seperate ID) when hovering
over equipment (all equipment hover)"*, and *"add a button in lockstyle to allow preview
on gear you don't own, but make it unable to save if you don't clear the ownership
check."*

His hedge was right, and the numbers say why: **Arhat's Gi is item 13795, model 59.**
The item id is what a packet names; the MODEL id is what a lockstyle shows (0x051 carries
base+model â€” `0x2000+59` for Body). Rings/necks/ears/backs/waists have **no model at all**
(`Model = nil` in the catalog â€” "no look slot", not "unknown"), so the tooltip says
`none (no look)` rather than `0`.

### view_ids

One flag, one line, no new surface. `sf.flags.viewids` (syncflags, beside `debug`/
`autosync`, persisted in `uiflags.lua`); `/dl view_ids [on|off]` is a toggle in gearui's
existing `dlac-ui` handler, cloned from `/dl debug`. The whole feature is a block at the
end of **`renderItemTooltip`** â€” which is *the* shared hover card, so "all equipment
hover" came free: Equipped, All Equipment, Sets, floatgear and the lockstyle picker all
render through it (that sharing is also why floatgear's tooltip can't drift). Model
resolves the way lockstyle's `modelOf` does â€” the record's own field, then the catalog
**by Id** â€” because an owned record only carries `Model` once the enrichment pass has run.

### "Show gear I don't own"

The preview injects your own 0x051 and never asks the server, so it can already render
anything in the game â€” the only thing standing between it and unowned gear was the
picker's source. So `listFor(slot, q, all)` grew a third arg: `all` sources gearui's flat
catalog list (already `.Slot`-carrying) instead of gear.lua. **`all` LIFTS the ownership
filter; it must never ADD one** â€” the AH HARD RULE (no job/level gate, ever) governs the
catalog list too. A 2-arg call stays owned-only and byte-identical; AH1-AH9 never moved.

**Save is the gate, not the list.** The server renders a style only if `HasItem` â€” a
piece you lack silently leaves the slot's OLD look in place (the "why is my lockstyle
stale" trap). So Save refuses while an unowned piece is in the working copy, and says
which slots. **Apply needed no gate of its own**: it reads the SAVED file, which an
ownership-gated Save can never have written. Note this is *not* the off-job case â€” an
off-job pick is ordinary here and must never be dimmed ([[lockstyle-anything-you-own]]);
ownership is a different axis, and it genuinely cannot work.

Three things that were nearly bugs:

- **The apostrophe trap, in a new place.** The API drops apostrophes, so the catalog row
  is `Arhats Gi` where gear.lua says `Arhat's Gi`. A name-keyed ownership check calls an
  item you own unowned; worse, storing the catalog spelling saves a name the engine
  **cannot resolve at apply time** (dispatch resolves saved sets by NAME). So ownership
  is decided **by Id** (`W.ownedById`, the `catalogById` precedent), and picking your own
  item off the catalog list stores *your* spelling. AN24/AN25 pin the bridge: the same
  pick is accepted with it and rejected without.
- **The gate must fail OPEN.** First cut returned "unowned" whenever the lookup failed â€”
  and pre-login `gear.lua` is the bundled EMPTY template (dlac.lua preloads at Ashita
  boot; the real one swaps in on the first frame after login). That version bricked Save
  entirely. Now an absent/empty table means "can't tell â†’ don't block", which is
  ownedcache's own rule ("a failed lookup must never take a feature away"). AN27/AN28.
  Choosing gear.lua membership over a live bag scan is the same instinct: gear.lua is
  add-only and a **superset** of what you hold, so nothing the owned picker would have
  offered can newly fail to save.
- **`Main` is 3749 catalog rows** (Body 1743, Head 1391; 14941 total) and every rendered
  row loads an icon texture. The All Equipment tab gets away with the full catalog only
  because its slot headers start COLLAPSED; the picker list renders immediately. Hence
  `BROWSE_CAP = 200`, highest-level-first so the cap keeps the good end â€” and it is
  announced ("... N more -- showing the 200 highest-level. Type above to narrow."), never
  silent. Cap applies to the catalog list only; the owned list is untouched.

The toggle sits in the picker popup rather than the window's button column: that list is
the only thing it changes, and it is where you notice the piece you want is missing. It
is sticky across opens but deliberately NOT persisted â€” it's a look-at-things mode, not a
setting. `all` is ANDed with `W.allEquip ~= nil` so it means "this list IS the catalog"
and unwired rows can't be painted as gear you don't own. Save is greyed + refuses with a
reason rather than `BeginDisabled` â€” that API is used nowhere in this install and hard
rule 2 says presence proves nothing.

Tests: **AN1-AN28** (490 -> 518) + **S17-S20** (111 -> 115). The smoke checks matter more
than the units here and for the S14-16 reason: gearui hands the two new wires over inside
a `pcall` that prints nothing on failure, so a mis-referenced upvalue would not crash --
the picker would simply never leave gear.lua and every catalog row would read "not owned".
S17/S19 drive the REAL gearui + REAL catalog and were verified to bite (nil the `allEquip`
wire -> S17 "got false, want true"; nil `ownedById` -> S19 "got nil, want Arhat's Gi"), and
AN27/AN28 were verified against the fail-closed gate ("got false, want true").

### Round 2 (same session): "unowned gear slips through the slots"

Henrik, on the browse-all picker: *"you can see hand, leg, feet, head pieces even though
you are choosing a body piece."* The filter (`rec.Slot == slot`) was correct and its
tests passed. **The catalog data was wrong**, and the picker was the first surface that
ever looked at `Slot` closely enough to notice.

His instruction â€” *"check under tools, apiscrape or w/e ... you can use that to fetch data
and validate the source"* â€” is what settled it. `tools/api_cache/23363.json`, straight
from the server:

    "name": "Amini Bottillons +2",  "slot": 32,  "MId": 0,  "jobs": 0

Bottillons are BOOTS. The server says Body. **CatsEyeXI's `item_equipment` carries rows
for unimplemented items with default values, and the default `slot` is 32 â€” which decodes
to Body.** 259 such rows; **258 land in Body** (the 1 other is Main). Their names give the
game away: `Gletis Crossbow`, `Mpacas Bow`, `Pinaka`, `Earp`, `Loughnashade`, and the
entire **Amini/Boii `+2`/`+3` reforge tier** â€” a tier this server has not implemented.
All 190 distinct stub names are **orphans**: no proper row anywhere shares the name, so
they are not duplicates of real items. The crawler copied the server faithfully, we listed
it faithfully, and Body silently carried 258 foreign names.

**A second bug fell out of reading apicrawl.py:**

    jobs = '{"All"}' if (len(js) >= 22 or not js) else ...

`not js` â€” an EMPTY jobs mask was published as **`Jobs = {"All"}`**. Every stub row was
advertised as equippable by *every job*, the exact opposite of the truth. That is why the
junk never looked suspicious in the catalog: it claimed to be All Jobs gear.

Fixed in **both layers, because they fail independently**:

- **DATA** â€” apicrawl skips `jobs == 0` and prints the count (`skipped 259 unimplemented
  stub rows`); the `{"All"}` conflation is gone. Rebuild is surgical, verified by diffing
  old vs new: **REMOVED 258, ADDED 0, and Body is the only slot that moved** (1743 â†’ 1485);
  all 258 removed were modelless. `tools/README.md` "The junk rows" is the runbook.
- **PICKER** â€” `hasLook(rec)` refuses any catalog row with no model. A lockstyle shows a
  MODEL; an item without one cannot be shown (lookpreview DROPS a modelless slot â€” the AI
  tests â€” and the server would render it EMPTY), so offering it is offering a no-op. This
  layer must hold on a dirty catalog too.

**`jobs==0` is the marker; `MId==0` is NOT** â€” and the difference is load-bearing.
`jobs==0` (259) is a strict subset of `MId==0` (1073). The other **814** are real,
equippable, wanted items that merely have no model (all the `Hexed` gear). Dropping those
from the catalog would strip their stats, and the catalog is where every owned item gets
its stats by id. So: the crawl keeps them (data), the look picker refuses them (UI). The
right filter differs by layer, which is exactly why the fix lives in both.

Not applied to the owned list: gear.lua is slotted from the CLIENT's own resource
(`gearimport.slotFromMask`), so it has no stub rows, and the AH HARD RULE says that list
filters on the search box and nothing else (AH6 pins a fixture carrying no Model at all).
The client resource stays the fallback answer if a wrong slot ever turns up on an item
that has real jobs â€” none did: a name sweep of all 1470 surviving Body pieces found zero
wrong-slot names.

Tests: AN9a-AN9g + S21-S25 (525 + 120). S21 pins the DATA and S22/S23 the PICKER; both
verified to bite â€” rebuilding the catalog with the stub skip disabled fails S21, and
removing `hasLook` fails S22/S23 and drags 'Amini Bottillons +2' to the TOP of the Body
list (AN9's failure text is the bug, reproduced).

## Session "NON is not a job" â€” the login that silently ate your sets (07-15, engine v49)

Henrik: *"Uuuh, I don't know exactly when, but either when we did the equipmon floating
box, earlier or later, my triggers don't work? Did something implement itself too hard?"*

Nothing did. The equipmon window was innocent, and the bug was **latent since the storage
move (v33, 07-13 13:55)** â€” 108 commits and two days earlier. Decision of record:
**ADR 0007**.

### The bug

At login the client's player block is not populated yet, so `GetMainJob()` returns **0**
(= None). gData resolves the main job through the resource manager â€”
`GetString('jobs.names_abbr', GetMainJob())` â€” and **0 stringifies to `"NON"`**. The
profile auto-install guarded with:

```lua
if type(job) == 'string' and job ~= '' and job ~= '?' then   -- "NON" sails through
```

So it took `"NON"` for a real job, went looking for `sets\NON.lua`, found nothing
(**nobody has one** â€” which is why it hit every migrated character identically), installed
nothing, and **LATCHED**: the latch keyed on `gProfile` + profile name and never recorded
*which job* it had answered for. ~6.4 s later (16 ticks) the read settles to the real job,
but `gProfile` has not changed, so the guard never re-fires.

Result: the whole session runs on the shim's empty `.Dynamic`. Every trigger matches and
equips **nothing**, in silence â€” `equipSetByName` skips a missing set without a word since
v35. `/lac set Idle` â†’ *"Set not found: Idle"*.

### Why it hid for two days

Any **job change** or **Reload LAC** builds a fresh `gProfile` and installs correctly. Two
days of reloading and flipping jobs while building features never left it in the one state
that bites: **log in, play the same job, touch nothing**. Henrik only noticed once the
feature work settled down and he actually just *played*. His own words: *"I've been testing
and running around a lot and haven't really done much that would make me detect this issue."*

The storage move is what made it possible. **Pre-v33 the job file CONTAINED the sets**, so
LAC populated `gProfile.Sets.Dynamic` merely by loading it â€” no install, no tick, no race.
After v33 the job file is a 1770-byte shim with `Dynamic = {}` and the engine must fill it.

### Two wrong theories (both from reading code, not running it)

1. **Royal Cloak / RSlot (v43).** Confirmed `RSlot = 16` on the Royal Cloak in the live
   `gear.lua`, and it *is* in the WHM Idle Body ladder. Dead end: best-by-level picks
   `Clr. Bliaut +1` (60) over it (59), and reservedDrops only ever drops ONE slot â€” never
   "triggers don't work". Cost: an hour.
2. **The latch fires on an unanswerable `hasSetsFile` (v45).** Right about *the latch being
   the bug*, wrong about *why it latched*. Shipped v45 (`answerable = setsPath(job) ~= nil`)
   and it did **not** fix it â€” `setsPath` is non-nil the moment `charBase()` resolves, which
   is well before the job read settles. Kept anyway (it is a real second hole), but it was
   not this.

Both died to the same mistake: **reasoning about a timing bug from static reading.** The
answer only arrived when the engine printed its own state.

### What actually found it

Henrik: *"Look, ask me to do whatever helps you, it's better than guessing."* â€” then
`/dl instdiag` (temporary, v46â€“v48: tick counters + a latch log):

```
instdiag: engine v48  ticks=101 reached=100
instdiag: latched=YES -- guard will not re-fire (act=Default, job=SAM)
instdiag: latches=tick 1: job=NON hasSets=false | tick 17: job=SAM hasSets=true
instdiag: gProfile.Sets -> Dynamic=1 entries, flattened=1 sets
```

`job=NON` in one line, after three rounds of theory. Tick 1 is the bug; tick 17 is the
v48 job-keyed latch re-firing and installing.

Two false starts on the instrument itself, both worth remembering:
- **v46's `/dl instdiag` printed nothing.** The LAC command handler gates on a
  **whitelist** of subcommands *before* the branches â€” adding a branch alone does nothing.
  Whitelist first, branch second.
- **The version must move or the instrument never loads.** `trySelfSwap` compares the
  seeded file's `M.VERSION` to the running one; a changed file at the same version is
  silently ignored. Same for the GUI's red Reload-LAC banner.

### The fix (v49) â€” both ends

- **`M.jobReady(jobId, jobName)`** rejects a not-ready job, gating on the **id** (0 is
  authoritative; `readJobSets` twenty lines away already did exactly this). The `"NON"`
  name check stays as belt-and-braces â€” id and string are two different reads.
- **The latch records the job it answered for**, so a settling read re-fires the guard.
  Defense in depth: `jobReady` stops the bogus resolve, the job-keyed latch stops any
  future wrong-job resolve from being permanent.

Tests 527 â†’ 534 (Z1â€“Z7 pin `jobReady`, incl. **Z7: WAR (id 1) is a real job** â€” the fix
must not overreach; Y55â€“Y56 pin the `setsPath == nil` retry signal).

### Lessons

- **A guard that enumerates the bad values misses the one nobody thought of.** `''` and
  `'?'` were a blocklist; `"NON"` was a *valid string*. Gate on the signal the game uses
  for "not ready", not on the shape of the value.
- **The dangerous not-ready read is the one that returns a plausible value, not nil.**
  `charBase()` returns nil pre-login and every caller retries â€” that one never bit.
  `GetMainJob() == 0 â†’ "NON"` returns *good-looking data*, and cost hours.
- **The engine's only latch was its only non-retrying reader.** Everything else re-reads on
  a throttle and self-heals. That asymmetry was the tell, visible from the first hour and
  under-weighed: **triggers recovered at login and sets never did.**
- **Silence compounds.** v35's "missing set is red in the tab, not a chat warn" is right for
  a typo'd set name, but it also means *the entire engine equipping nothing* says nothing.
  A total failure and a single typo should not look identical.
- **`gProfile` existing does not mean the job is known.** LAC picks `gProfile` from the 0x0A
  packet's job; gData's `MainJob` is a memory read. At login they disagree for ~6 s.

### Field notes (not bugs)

- **Hunklor is not a second data point for this** and cost a detour. He was un-migrated at
  login, so the tick correctly installed nothing; Setup migrated him mid-session, and
  `profiles.migrate` **does not install into the live `gProfile`** (it cannot â€” LAC is still
  running the old in-memory profile until a Reload LAC). His "same issue" was a
  half-migrated profile plus genuinely empty sets.
- **Migration carries `Dynamic` only, and that is by design.** His SAM was a hand-written
  legacy profile with *static* sets (`Idle`/`Tp`/`Ws_Default`/`Meditate`/`Transmog`), its own
  `HandleDefault`, gcinclude wiring and a `Packer` belt. `extractDynamicText` found no
  `Dynamic` block, so migration correctly wrote an empty one; the statics live on in
  `backups\pre-profiles\` for the Sets tab's "Copy from static". The shim does not carry
  hand-written logic â€” say so when someone migrates a rich profile.

### Confirmed + closed (07-15, engine v50)

Field-verified on **both** characters, each a fresh login touching nothing: Hunklor (SAM,
`latches=tick 1: job=NON ... | tick 17: job=SAM ...`, `Dynamic=1 flattened=1`) and then
Mindie (WHM) â€” Henrik: *"logged in on Mindie, worked."* Two characters, two profile
shapes, two jobs; that is the fix confirmed on the exact path that used to fail.

`/dl instdiag` and the tick counters are **stripped again in v50** â€” they were explicit
scaffolding, and dev diagnostics belong in dlacprobe (they live in `cb2fbe2..40288e3` if
this class ever returns). What stays is `M.jobReady` + the job-keyed latch, tests Z1â€“Z7,
and two comments left exactly where the scaffolding taught something: the command
handler's **whitelist-before-branch** note, and the `jobReady` header carrying the actual
field line that proved it. The cost of the instrument was ~15 minutes; it should have been
built after the FIRST theory died, not the second.

## Session "priority-preserving static import" (2026-07-16, issue #15)

Redesigned the Sets tab's "Copy from static" (F1 of PRD #14). It used to **spawn a new
Dynamic set named after the source** (source name, or a name typed in the New box);
players couldn't tell their candidate order had survived the copy and rebuilt priorities
by hand. Now it copies the chosen static set's slots **into the dynamic set the player
already has selected**, keeping that set's name.

### What landed

- **Target is the selected set.** `copyFromStaticSet` refuses when `M.workingSetName` is
  empty ("Select or create a set first, then copy into it") â€” the copy no longer invents
  a set. The New-box-rename path is gone; the flow is now *pick/create a set, then copy*.
- **Overwrite is confirmed.** A non-empty target opens a `BeginPopup` (not Modal, so
  click-away aborts â€” same reasoning as the Setup-plan popup): "Replace '<Set>' (N filled
  slots) with static '<Source>'?" Replace / Cancel / click-away. Nothing changes until
  Replace. The one-shot `ui._copyConfirmOpen` drives `OpenPopup` while the data in
  `ui._copyConfirm` persists for the popup's lifetime â€” calling `OpenPopup` every frame
  would defeat the click-away close.
- **Full-replace.** The target becomes the static's contents; slots the static doesn't
  define are cleared (`M.working = result.working`). An all-unowned copy that resolves to
  **nothing** is the one exception â€” it leaves the target untouched and says so loudly,
  rather than silently wiping the player's work (hard rule 12).
- **Order verbatim + best-first warning (ADR 0008).** Candidate order is carried as-is;
  dlac still equips the highest-item-Level candidate, which diverges from LAC's
  first-in-list only when a slot's order is **not** best-first (a lower-Level piece ranked
  above a higher one). Those slots get a per-slot chat warning naming the slot; a
  level-descending list imports silently.

### Where the logic lives

The pure transform is its own module, `gear/setimport.lua` â€”
`importStaticSet(staticSet, slotLabels, resolve) -> { working, notBestFirst, slotCount }`
â€” with the resolver **injected** (gearui passes `resolveSetItem`; the headless suite
passes a stub over owned records), which is what keeps it Ashita-free and testable. The
UI shell (refuse / confirm / warn) stays in gearui. Tests **AO0â€“AO23** pin the transform:
plain single-element slots, a level-descending `_Priority` list (silent), a not-best-first
list (named), equal-Level ties (not a divergence), unowned candidates dropped, an
all-unowned slot absent, and a virtual entry (`dlac:AutoStaff`) skipped by the best-first
check rather than read as a Level-0 candidate that would falsely flag the slot. The UI
shell is covered by `smoke_ui`'s chunk load.

No seeded-file behaviour changed (the copy is an addon-state Sets-tab edit; the engine
still flattens by highest Level), so **no `dispatch.M.VERSION` bump**. Player-facing
strings (the refuse message, the popup title/body, the warning) are **proposed for
maintainer sign-off** in the PR, not finalized.

## Session "import Lua tables to bulk-create groups" (2026-07-16, issue #30, G4)

The fast path for a player who already keeps their spells grouped in a Lua table (by stat
scaling, by role, ...): an **"Import Lua Table(s)"** control in the Groups section that
parses pasted `Name = T{...}` assignments and bulk-creates **one Group per top-level key**,
members = the key's string array. Builds on G1/G2's `groupsmodel` / `Groups` storage â€”
same file, same Commit.

### What landed

- **The pure transform is its own module, `gear/groupimport.lua`** â€”
  `parse(text) -> (groups | nil, errors[])`, plus `classify` (created vs collide, CI) and
  `apply` (write into the live map, overwriting under the existing stored spelling). No
  Ashita, no ImGui, no file I/O â€” the same shape as `setimport.lua`. Tests **TGI0â€“TGI33**
  pin it: the issue's own paste (T{...} + plain {...} mixed, trailing comma), the
  single-element `STR_VIT = T{'Quad. Continuum', }` -> `["Quad. Continuum"]` exactly, the
  whole `{ Key = {...} }` form, flat-only rejection (nested / non-string / named-field skips
  THAT key while the rest import), malformed input, a sandbox-blocked global, blank/nil
  input, and empty groups.
- **`T` is identity, sandboxed.** The text is evaluated in a minimal env â€” `T = function(t)
  return t end` and **nothing else**, no metatable, so every other global (`os`, `io`,
  `require`, ...) reads nil and a hostile paste errors at eval rather than running (the
  hardened `profilesets.sandboxSets` pattern). Compiled with `load(code, name, 't', env)` /
  `loadstring`+`setfenv` (5.4 tests, LuaJIT addon), **'t' mode = text only** so no bytecode
  can be smuggled in. Two wrappings are tried (`return {...}` for bare lines, `return ...`
  for a whole braced table); on a total failure the PRIMARY form's error is reported so an
  "unterminated table" / "nil global" message isn't masked by the fallback's `<eof> expected`.
- **Collisions are confirmed, never clobbered.** Import parses + classifies and shows a
  **preview** (create N: names / overwrite N: names / skip N: reasons). With no collisions it
  imports immediately; with collisions it waits for a red **"Overwrite N & import"** click
  (parity with "Copy from static"). Overwrite replaces members **under the existing stored
  spelling** (`str_dex` pasted over `STR_DEX` keeps `STR_DEX`). A skipped key always states
  its reason â€” no silent drop (hard rule 12). Commit still writes the file.
- **`InputTextMultiline` is probed, not assumed** (hard rule 2 â€” it is used nowhere else in
  this install). Present -> the paste box; absent -> a single-line box with a visible note
  (the parser is comma-separated, so one line still works) â€” a visible degrade, never a
  silent disable.

### Where it lives / what did NOT change

`renderGroupImport` is a `local` in `ui/triggersui.lua` (addon-state, 92 top-level locals â€”
well under the 200 cap; smoke_ui guards the load). State rides on the existing `groupUI`
table (no new UI-chunk pressure). **No seeded-file behaviour changed** â€” `groupimport.lua`
is never seeded, the trigger-file `Groups` format is exactly G2's, and the engine reads it
unchanged â€” so **no `dispatch.M.VERSION` bump**. Player-facing strings (the control label,
the preview/summary wording, the skip reasons) are **proposed for maintainer sign-off** in
the PR, not finalized.

## Session "searchable spell/ability browse-list" (2026-07-16, issue #26, G3)

Upgraded the Groups tab's member entry from typed-only to a **searchable, job-filtered
spell/ability browse-list with multi-mark** (PRD #21 stories 2/8/16/17/18; ADR 0009). The
same browse capability open issue #12 wants for ordinary `name` triggers, so it is built
once as a shared, coupling-free core.

### What landed

- **`gear/actionpicker.lua` â€” the pure core.** `buildList(job, spells, abilities)` returns
  the job's learnable spells + abilities as ONE combined, case-insensitively sorted list of
  `{ name, kind, level }` (kind = `'spell'`/`'ability'`), **ungated** â€” the level is display
  only (build-ahead, HARD RULE 6 / ADR 0006). The picker-DB tables are **injected** (the
  setimport resolver precedent) so it stays Ashita/imgui/file-IO-free. `parseQuery` +
  `matches` are the comma-separated, ALL-terms-substring search predicate â€” the item-search
  shape (gearui `parseSearch`/`itemSearchMatch`), minus the stat-alias canon (actions carry
  no stats). Never seeded into LAC. Tests **ACP0â€“ACP26**.
- **The Groups tab picker (triggersui).** Each group box gains a **Browse...** button that
  opens ONE shared popup retargeted per group via `groupUI.browseFor`. Search narrows the
  cached job list; each row is a **checkbox** mark (not a Selectable â€” the field-proven
  idiom keeps the popup open across marks without a DontClosePopups flag, mirroring gearui's
  weapon-type filter) + a `[S]`/`[A]` marker + name + dim `Lv`. **Add N marked** commits
  every mark through `gm.addMember` (case-insensitive dedup), then closes so the section
  status + member list show the result. Entries already in the group render dimmed with
  `(in group)` and no checkbox. The list is cached per job (`_listJob`) so the ~1000-row
  scan runs once per job, not per frame.
- **Free-name entry stays.** The typed input + `+ member` is untouched â€” the picker is only
  a faster path for the job's known actions; anything the data misses is still typeable.
- **Untyped, so twins are one mark.** A rare spell+ability sharing a name (e.g. BLU
  "Head Butt") lists as two rows, each labelled, but marking either sets the one
  name-keyed mark (a Group stores the bare name once). Widget IDs are keyed by row, not
  name, so the twin's two checkboxes never collide on the ImGui id stack.

### Where the logic lives

Pure transform + search: `gear/actionpicker.lua` (tests ACP*). UI shell (button, popup,
mark state, cache): `ui/triggersui.lua` `renderGroupBrowsePopup` + `renderGroupBox`, covered
by `smoke_ui`'s chunk load. Data: `data/spells.lua` / `data/abilities.lua` â€” issue #26 is
their FIRST consumer (#12 is the next adopter of the same seam).

No seeded-file behaviour changed (the group storage format is unchanged â€” still bare-name
arrays via `gm.addMember`; the engine reads the same file), so **no `dispatch.M.VERSION`
bump**. New player-facing strings (the Browse... button + tooltip, the popup title, the
`[S]`/`[A]` markers, "Add N marked", the status line) are **proposed for maintainer
sign-off** in the PR, not finalized.

## Session "trinket vs ranged weapon -- the REAL fix (server-enforced)" (2026-07-16, ADR 0010, branch fix/trinket-ranged-conflict)

The first attempt (PR #34, ADR 0010 v1) got this BACKWARDS and was closed. This is the corrected fix.

### What's actually going on (field-confirmed: it FLAPS)

A stat-stick trinket (Ammo, no `AmmoType`) and a bow/xbow/gun can't be worn together -- they flap
back and forth. It's the SERVER: `RSlot=4` (reserve-Range) is `item_equipment.rslot` on the whole
throwing-ammo class (135 catalog items -- Morion, all pet food, tathlums, pebbles), so the server
strips the Range slot when such ammo is worn. `reservedDrops` was built to mirror exactly this
("the only stable state"). The bug was that the mirror was INCOMPLETE: the crawl left `RSlot` off a
few stat sticks (Cinderstone, Coiste Bodhar, Talon Tathlum), so those flapped. v1 misread the gaps
as an "artifact" and tried to make them coexist -- which removed the mirror and made the WHOLE class
flap (Henrik: "flapping back and forth, no difference with Morion"). An investigation agent confirmed
there is NO second client mechanism: the only cross-slot Range/Ammo logic is `reservedDrops` +
`pickRangeAmmo`, and the reservation is the server's.

### The corrected fix (ADR 0010)

- **`gearimport.effectiveRSlot`** completes the category: a trinket (`Type='Ammo'`, no `AmmoType`)
  missing its `RSlot` gets the Range bit stamped -- in the ONE place gear.lua's RSlot is decided, so
  the fresh write AND the `/dl fix` backfill agree. Cinderstone/Coiste now carry `RSlot=4`.
- **`dispatch.trinketRangeDrop`** resolves by Henrik's rule -- keep the **higher-Level** of {trinket,
  ranged weapon}, drop the other -- before the reserved pass, deterministically (no flap). Tie ->
  keep the trinket (server default).
- `pickRangeAmmo` unchanged (the optimizer already avoids the pair). `dispatch.M.VERSION` -> 52.
- Players **re-commit / `/dl fix`** once so the gap trinkets pick up the completed RSlot.
- Tests TR0-TR10; 780 + 123 green.

## Session "Groups auto-import: scan my Lua file" (2026-07-16, Item 1, branch feature/groups-autoimport)

The automatic counterpart to G4's paste-based "Import Lua Table(s)": a player who already keeps
their spells grouped in their LuaAshitacast file shouldn't have to copy-paste. A new
**"Auto-import from my Lua file"** control in the Groups section scans the character's job file and
lists every group-shaped table as a tick-able candidate.

### What landed

- **`gear/groupscan.lua` â€” the pure scanner.** `scan(fileText) -> (candidates, notes)`. The
  player's group tables are usually `local`s (invisible to a sandbox-run env), so this is a TEXT
  scan: a `%b{}` walk pulls each top-level `[local] NAME = T?{...}` block (never descending, so a
  gear set's inner `['Idle'] = {...}` is not a top-level hit), evaluates its body in `groupimport`'s
  hardened sandbox, and classifies it â€” a flat string array â†’ one candidate; a container of flat
  arrays â†’ one candidate per inner key (the `BlueSpells` case); a gear set / settings block â†’
  skipped with a note. Comments are stripped first so a stray brace can't unbalance the walk;
  candidates are deduped case-insensitively and sorted. Tests **GS0â€“GS9**.
- **`groupimport` grew two exports** (`membersOf`, `evalTable`) so the flat-list heuristic and the
  safe eval live in ONE place instead of being re-implemented by the scanner.
- **Reads both files.** dlac's profile migration shims the live `<JOB>.lua`, so the real tables
  survive in `backups\pre-profiles\<JOB>.lua` â€” the scan reads the live file AND the backup and
  concatenates them.
- **The UI (`triggersui.renderGroupAutoImport`).** A `Scan my Lua file` button â†’ a tick-list of
  candidates (name + member count), pre-ticked EXCEPT obvious config tables (`*Variant*`,
  `*Settings*`, `*Table`) so `IdleVariantTable`-style false positives don't import unless chosen,
  plus a dim "skipped N" note for the gear-set/settings blocks. Import reuses the SAME `classify` /
  overwrite-confirm / `apply` (and `applyImportPlan`) as the paste flow.

### Where it lives / what did NOT change

`renderGroupAutoImport` is a `local` in `ui/triggersui.lua` (addon-state; smoke_ui guards the load).
No seeded-file behaviour changed â€” `groupscan` is never seeded and the `Groups` storage format is
G2's, read by the engine unchanged â€” so **no `dispatch.M.VERSION` bump**. New player-facing strings
(the control label, `Scan my Lua file`, `Found N tables`, `Import N selected`, the skip notes) are
**proposed for maintainer sign-off** in the PR, not finalized.

## Session "conditional effects design + the night shift" (44212a0..dadd9a8, PR #45) â€” 2026-07-17

**Theme:** Henrik expanded the latent/set-bonus scope (optimizer + totals now IN), delegated
every open decision, and left the maintainer running overnight ("you are super, go by your
recommendations").

**Landed (day):** direct server-source re-verification of the conditional-effects research
(sparse clone: the gear_sets applier + latent_effect_container.cpp, which the original
research never opened) â€” found and FIXED the gen_levelscaling latent-id bug (52 is
WEATHER_ELEMENT, 50 is the real under-level latent; shipped data carried 57 weather rows as
bogus below-Lv entries and missed all 9 real ones â€” `44212a0`). Full design via judge-panel
workflow + source amendments: `docs/design/conditional-effects.md` (`d16449a`; all six
decisions resolved `d938f7c`). PRD #39 â†’ issues #40â€“#44 (one per phase; #40 dispatched to
the cloud agent, #42 pre-carries agent:max). Generators built â€” `tools/modmap.py` shared
modIdâ†’stat bridge with the x100 scale traps, `gen_gearsets.py`, the latent router inside
`gen_levelscaling.py` (all disk-only; tools/ is gitignored) â€” and `data/gearsets.lua` +
`data/latentstats.lua` shipped (`4af3e5f`) so the cloud slices are pure addon work. Henrik
live-confirmed the Lava/Kusha de-equip drops ATT + ACC + DEF (the flat-set field check).

**Landed (night):** "Build as lv.75" defaults ON, deliberately session-only (`6577f68`).
Instant Warp scroll tops the Teleports menu â€” `/dl iw`, usable-item path (no equip/lock/
wait), stack count in the charges column; swept the parallel session's completed Chocobo
Whistle changeset along (`9e1df2e`). Per-set 4x4 build-slot grid replaces "Skip weapons":
the mask rides bindSetWeights (one binding, two payloads) and persists beside the weights
as slotsShared/slotsPerSet; AS1â€“AS20 (`ad79e61`). Player trigger conditions: hpBelow/
hpAbove, mpBelow/mpAbove (percent), tpBelow/tpAbove (raw TP), buff/buffNot (name or id) â€”
engine VERSION 53 with a per-dispatch buff cache and PM1â€“PM21 (`88bb3ba`); editor UI with
number thresholds + a searchable status-effect picker (`dadd9a8`). PR #45 (extras, for
morning review): live `[on now]`/`[off now]` markers on player-gated rules â€” evaluated by
the ENGINE's own matcher seam, never a re-implementation â€” and weights "copy from..."
(weights + slot marks together; AW1â€“AW11).

**Key decisions:** duplicate set pieces count TWICE (verified straight from the applier â€”
the design draft's "unverified, default once" was flipped); set piece counting is
level-sync-gated server-side and dlac mirrors it; 37 of 126 sets have ALTERNATE pieces
spanning weapon slots (weapon slots feed the optimizer via baseComposition); unreadable
player state matches NEITHER buff polarity (a failed read must never flap gear); the
build-as-75 off-state deliberately does NOT persist; main pushed (9 commits) so the extras
PR reviews cleanly and origin can't diverge under the incoming cloud-agent PRs.

## Session "level-sync settle hold" (after adaab2c, engine v56) â€” 2026-07-17

**Theme:** Henrik's field report â€” "in Incursion you are already level synced, then you pop
a boss, a new level sync is in place. That's when I lose TP" â€” diagnosed and fixed
engine-native.

**Root cause:** the engine trusts a just-changed MainJobSync reading immediately. A sync
landing makes level-driven resolution (virtuals, ladders, `utils.rebuildSets` re-flattens)
name a DIFFERENT Main at the transient level; one `gFunc.EquipSet` later the main weapon
swaps and saved TP zeroes. "Sometimes" = whether a dispatch frame lands inside the
transient window.

**Landed (dispatch.lua v56):** the level-sync settle hold, the ratified stateless-hold
pattern. Pure rule `M.syncSettleStep`: a level jump on the SAME job arms a ~3s hold
(`M.SYNC_SETTLE_S`); job changes and first reads adopt instantly; not-ready readings
(level 0, job '?'/'NON') never touch the tracker (parked on M â€” survives self-swap
mid-hold). While holding: every dispatch keeps Main/Sub/Range as worn (`ctx.syncHold`, the
pinReserved pattern â€” sits ABOVE the AutoAcc/virtual branches so markers hold UNRESOLVED),
a Range-reserving stat-stick Ammo holds WITH the Range it reserves (else the server strips
the worn ranged weapon â€” the ADR 0010 inversion the review caught), and HandleDefault is
gated whole for legacy profiles via `M.defaultGateHold`, consulted AT CALL TIME by a thin
generational wrap shell (`WRAP_GEN` + preserved `_dlacOrigHEE` original) so the gate
hot-swaps live â€” the old `_dlacPetHold` boolean guard would have left a v55â†’v56 hot-swap
without the gate until a full Reload LAC. Traced as `SYNC-HOLD` in /dl why. LS1â€“LS34
headless tests (929 total), including a real drive of the wrap shell over a v55-shaped
pre-wrap.

**Process note:** adversarial review workflow (4 lenses, refutation verify) confirmed 4
real defects in the first draft â€” trinket/Range inversion, the hot-swap wrap gap, the
tracker reset on self-swap, and mutation-tested coverage holes â€” all fixed before commit.

**Revision (same day, v57):** settle window 3s â†’ 1s (Henrik: "3 sounds like a long time").
Safe because the window is stability-since-last-change â€” every flip re-arms it â€” so 1s only
has to outlast the quiet gap after the final flip. `M.SYNC_SETTLE_S` is the lever if a sync
ever eats TP again.

**Field confirmation (same day):** Henrik tested in Incursion â€” TP survived the boss pop.
Henrik's framing, adopted: this was a LAC-layer reflex ("LAC is too fast, dlac gives it
leeway"), not a dlac bug; plain-LAC users with level-dependent weapon rules remain exposed
by design. Full write-up with code context: `docs/design/sync-settle-hold.md`.

## Session "second ear starved by the weight ladder" (2026-07-17)

**Field case (Henrik, WHM):** Cure Potency + Cure Potency II weighted 10/pt; owning
Curates' Earring (Lv30) and Roundel Earring (Lv73) produced BOTH as Ear1 candidates
(rungs at 30 and 73) and left Ear2 empty â€” the pair never wore both, so the Curates'
potency was lost outright. Root cause in `autoBuild` (gearui): dynamic mode built
slot 1's full ladder first (every score-improving item lands there), then barred
slot 2 from everything in slot 1's list â€” correct for double-equip safety, but it
starves slot 2 whenever each upgrade beats the last. Same defect for rings.

**Fix:** paired slots (Ear1/Ear2, Ring1/Ring2) with both halves masked now ladder as
a PAIR via `gearoptim.pairLadders` â€” one running TOP-2 walk over the level-sorted
candidates; each upgrade lands in whichever chain holds the weaker top, so the two
flattens together wear the best two distinct pieces at EVERY level, with disjoint
chains by construction (no double-equip). Owned counts pass through: an Id owned 2+
may fill both slots. The joint optimizer's picks arrive as `pins` â€” a pin already
topping a chain claims it untouched (ears are interchangeable, matched as a set);
a leftover pin trims an unclaimed chain like the single-slot ladder cap and is
stripped from the other chain (single copy) to keep the pair disjoint. The old
block-filter remains for pairs whose partner is NOT being rebuilt (unmasked half,
non-dynamic modes). Also fixed en route: unmasked slots are preserved BEFORE the
build loop, so a rebuilt Ear2 sees a hand-pinned Ear1 regardless of slot order.
PL1â€“PL13 headless tests (942 total); pairLadders is pure â€” scores computed by the
caller, no gear/weight reads.

**Field confirmation (same day):** Henrik re-ran the WHM Cure Potency build -- both
earrings now land, one per ear. Fix pushed to main.

## Session "priority weights for the friends" (2026-07-17)

**Context:** Henrik's friends are adopting dlac; feedback says the point-weight
system doesn't click for many of them. They asked for a plain top-to-bottom
priority list ("this stat first, then that one"), with caps still available.

**Feature (gearoptim + weightsui):** the Stat Weights editor is now two tabs.
**Points** is the classic editor, now with clickable Stat/Points/Cap column
headers (click to sort, click again to flip). **Priority** is the simple mode:
an ordered stat list â€” top matters most â€” with an optional cap per row, up/down
reorder, and the same copy from.../save as... verbs against its OWN stores
("Saved Lists" + per-set lists; a point template and a priority list never
cross-load, per Henrik). Both tabs carry a **clear** button to the right of
"save as..."; clear snapshots first, so copy from... > revert undoes a mis-click.

**Implementation ruling:** priority scoring is dominance-DERIVED point weights
(bottom-up, one point of a higher rank outranks everything below it combined;
uncapped stats assumed â‰¤500 set-total), resolved behind `activeWeights()` â€” so
score/optimizePicks/pairLadders/Auto-build run untouched. Which mode builds a
set is per-binding state flipped by whichever editor's data you MUTATE â€” looking
at a tab never switches it (a banner on the inactive tab says which one builds).

**Bug fixed en route (Henrik):** new sets no longer seed their weights from the
shared table â€” that seeding is why every new set arrived with a mystery "STR 5"
(leftovers in his shared table). New bindings start BLANK for weights AND
priority lists; only the build-slot mask still seeds from shared (a blank mask
would read as a dead Auto-build button). Empty per-set tables are no longer
persisted or offered as copy sources. AE4/AE6 rewritten to pin the new ruling;
AP1â€“AP38 cover the priority mode (980 checks total).

**Round 3 (same day): the shared table is deleted.** Henrik asked what "shared
weights" even were; on hearing it (the pre-per-set single table, kept as the
no-set fallback / new-set seed / legacy-file landing spot) he ruled it a dead
concept â€” "we start blank, have weights per set and can save. Delete it."
Implementation: unbound, the actives alias read-only EMPTY sentinels; every
mutator (weights, priority, masks, copies, saves, modes) refuses with 'no set
selected'; the weights panel and `/dl weight` say "pick a set" instead of
editing a phantom table; the "(shared weights)"/"(shared list)" copy rows are
gone; build-slot masks seed from the fixed default. Persistence no longer
writes `shared`/`slotsShared`/`prioShared`/`mode`, and the loader DROPS those
sections from older files (pre-per-set flat files â€” which were only a shared
table â€” load as nothing). Also folded in: an x with a red second-click confirm
on every Saved Sets / Saved Lists row in the copy-from menus, so "save as..."
templates can finally be deleted. AE/AS/AW/AP rewritten for the unbound
semantics (987 checks).

## Session "HELM gear automation" (2026-07-17, engine v59, docs/design/helm-gear.md)

**Feature: the craft-gear system's gathering twin** for Harvesting / Excavation
/ Logging / Mining (fishing excluded on purpose â€” it gets its own automation
someday). Research fanned out three ways before a line was written: the dlac
craftgear map (the template), the trove + ventures addons (the 0x1A4 protocol),
and the public server fork + wiki (mechanics, IDs, prices).

**What research settled:**
- The catalog already carries machine-readable `Stats.HELM` and
  `Stats.Surveyor` â€” HELM ladders are stat-driven exactly like craft skill
  ladders. All item IDs verified catalog-vs-server-SQL (design doc table).
- **The "+5 removes breakage" math decoded**: every field/plain piece carries a
  +73 result mod = +7.3 on the break roll (`hobbies/helm/logic.lua`: break if
  `rand(1,100)+mod/10 <= 33`) â€” five pieces â†’ min 37.5 â†’ unbreakable. This also
  explains server-questions Â§2's mystery flat 73. Excavation's result mod
  (2006) is private-module-added and stays breakable â€” As Square Enix Intended.
- **Venture points**: no retail packet â€” but trove's custom 0x1A4
  request/response streams a server-authoritative Points list (group/label/
  value; DVP arrives as group `Ventures`). helmwatch speaks the protocol
  itself (GET_POINTS=8 / POINTS_ENTRY=7); whether the four HELM pools ride the
  stream is field-test #1 (`/dl helm points` dumps everything).
- **`!ventures` reply format is unknowable from source** (private submodules:
  modules/catseyexi, cexi-src â€” all 404). helmwatch watches outgoing 0x0B5 for
  a typed `!ventures`, opens a 6s capture on incoming 0x017, mirrors raw lines
  to `helmventures_capture.txt` (the data that will pin the real regexes) and
  keyword-buckets them per category for display meanwhile.
- **Category auto-detection is NOT a dead end** (Henrik suspected it was): the
  point NPCs are literally named `Mining Point` etc. â€” outgoing trade 0x036
  target index â†’ entity name â†’ category; with the bar ON the hat auto-follows.
- 0x1A3 (the `ventures` addon's packet) is the venture-NM daily rotation, NOT
  HELM â€” a different system wearing the same name.

**What shipped:** `feature/helmwatch.lua` (state owner: helmstate/venturepoints/
helmventures mirrors, 0x1A4 + 0x017 + 0x036 + 0x0B5 glue, `/dl helm`),
`ui/helmui.lua` (the Automations panel: Henrik's four-column progression matrix
â€” Field / Plain / Plain +1 / Hats â€” with the "you're awesome" green cascade
(better piece greens its ancestors) and a holy-light backlight on owned
top-tier pieces; category tabs with the new gold glyphs; VP + today's ventures
per tab), `ui/helmbar.lua` (floating bar: four glyphs + pill + VP/rating/
Surveyor status line), engine v59 (`dlac:AutoHelm`, helmstate read gated to
Default â€” IDLE-ONLY is the feature â€” armor+neck+waist only, never weapons;
craft-vs-helm both-on arbitration by newer `at` stamp), manifest fmtver 7
(helm ladders Surveyor-major + owned-hat map). Icons: Henrik's four SVGs
rasterized to `assets/helm/*.png` at the craft-glyph spec (40Ã—40 alpha).
En route: helmOverlayFor passes ctx.player through to the ladder level gate â€”
the craft overlay's inner ctx drops it (harmless there, Lv65 Field Torque/Rope
would flap here). H1â€“H36 cover state rules, wire parsers, overlay resolution,
rating math (1023 checks).

**Field tests pending (dlacprobe / live):** Â§7 of the design doc â€” the 0x1A4
points dump, one `!ventures helm` capture, one Alternix menu, one swing per
category to confirm 0x036 offsets.

**Same-day field loop (Henrik testing live, five rounds):** first run confirmed the
0x1A4 points stream (group `Ventures`, exact category labels) and pinned the
`!ventures` reply format -> structured parser replaced keyword bucketing; button +
Automations column widths fixed (themed font); status row gained HELM+/Surv+ totals.
Swing test killed the outgoing-trade guess -- ONE captured 0x034 revealed the result
event carries the Point's ActIndex @0x28 (plus item/broke in num[]) -> detection
rebuilt on it, real bytes in the tests. Then the feature grew into its final shape:
**Auto HELM** (v60) -- persisted detection-armed mode beside the session-only "Set
HELM Idle" pill; hold tail 60->20->4s (Henrik's ruling); **proximity anchor** --
target a Point within 6y = dressed BEFORE swing 1, anchor outlives the target (the
game clears it on HELMing), rendered-check via RenderFlags0 bit 0x200 (the
storage-move nomadNearestSq precedent Henrik remembered). Final lesson (v61):
**"Default" is NOT "idle"** -- HandleDefault runs every frame, so the overlay was
pinning over combat gear; it now stands aside while Engaged/Dead ('Event' stays
dressed -- the swing animation would churn otherwise). Craft overlay deliberately
not gated (safe-zone activity). 1065 + 123 checks green; all Â§7 field tests closed
same-day.

## Session "virtual markers get a ladder level" (2026-07-17, engine v62)

Henrik's field report on his leveling Mindie WHM: the Sets tab showed
`dlac:AutoIridescence` as the Main pick "at level 0" while the character
actually wears Pilgrim's Wand â€” the marker was a Lv0 wildcard that shadowed
the real weapon ladder everywhere below the level of any owned iridescence
staff. His ruling: **a marker's level is the level of the item it resolves
to** (for him Chatoyant Staff, Lv51).

Implemented as `M.virtualMinLevel(marker)` (dispatch, v62): the LOWEST level
among the manifest items the marker can resolve to â€” AutoStaff/AutoIridescence
scan `universal` + per-element `staff`, AutoObi scans `obi` + `obiUniversal`;
craft/helm/acc families and legacy name-only shapes return nil ("no answer").
Consumers, all nil-safe (nil keeps the old always-adopt behavior, so the rule
can only ever REMOVE a marker that cannot resolve):

- **BuildDynamicSets** skips a virtual whose min level is above the main level
  â€” the flattened set then shows the real best-by-level item outright instead
  of `marker|fallback` (the engine's equip-time fallback made this invisible
  on the wire; the FLATTENED SET was what lied).
- **gearui resolveSetItem** stamps the derived level on virtual records
  (Lv51 in the ladder rows instead of 0), and **bestByLevel**'s
  virtual-takes-the-slot short-circuit now honours it, so the "current pick"
  highlight mirrors the new flatten exactly.

Tests VL1â€“VL7 (min-level derivation incl. the `marker|fallback` composite
form, flatten below/at the rung, legacy-manifest passthrough). 1078 + 125
green. Note: utils.lua changed too â€” a **Reload LAC** is needed for the
flatten half; the engine half self-swaps.

## Session "THE SETUP STANDARD -- clean shim, always" (2026-07-17)

Henrik's ruling, born from the friend-sync-lag case (the fix was an EMPTY job
file): **Setup always ends with the live `<JOB>.lua` as the clean managed
shim.** Convert-in-place -- append dispatch shims, keep the old handler logic
running underneath -- is dead. With 300+ installs coming over hand-built LUAs,
old logic left live means equip conflicts nobody can support; the maze of
setup outcomes collapses to one path.

What changed (most of the machinery already existed -- this makes it the ONLY
door):

- **profiles.planMigration**: the only skip is "already a clean shim". A
  backed-up file that holds logic again (restored/hand-edited) re-migrates
  with `reshim = true`: the FIRST backup (the statics truth "Copy from"
  imports) is never overwritten -- the current text goes to a stamped
  `backups\pre-profiles\<JOB>-<stamp>.lua` copy (skipped when byte-identical
  to the first backup).
- **setupui**: state `'shims'` died; `'wired'` = touches dlac but is NOT the
  clean shim (old in-place conversions, hand-wired files, edited shims) and
  routes -- like `'ffxilac'`/`'none'` -- into the new unified
  `setup.migrateToCleanProfiles()`: seed `dlac\gear.lua` (ffxi-lac copy else
  bundled template; gcinclude/gcdisplay seeding dropped -- nothing live
  requires them now), `profiles.migrate` over EVERY job file, per-job starter
  trigger seeding, profilesets invalidate, auto LAC reload. `'ok'` = shim +
  healthy handlers only. The `.flbak` writer and `setup.migrateJobText` are
  gone; `setmanager.repairShims*` stays (tested text engine, no product
  caller). Fixed in passing: gearui's migrate-commit wrote a GLOBAL
  `_setupState` instead of dropping setupui's cache.
- **gearui**: one 'migrate' plan popup for every non-standard state, spelling
  out the safety (verified first backup, stamped re-backup) and the import
  paths (Sets "Copy from" incl. `_Priority` order/ADR 0008, Groups "Scan my
  Lua", both reading the backup); commit calls `migrateToCleanProfiles()`.
  Red banner rewritten: old text promised "your existing logic is kept".
- **Tests**: Y29 flipped (backed-up + logic = re-shim, first backup
  untouched), Y31b (shim + backup = skip), Y31c SETUP HARD RULE: all 48
  text-x-flag combos -- every non-shim migrates, every shim skips. 1088 + 125
  green.

Docs: README setup/safety, architecture (setupui/setmanager/file table),
design/profiles.md (migration order; "Veterans" section superseded by the
standard -- hand-wiring is engine-supported but GUI-flagged, best-effort),
PROFILE_TEMPLATE header.

## Session addendum "fresh Setup seeds the four base sets" (2026-07-17)

Henrik field-tested the fresh path (renamed his dlac data folder + WHM.lua
away): Setup seeded starter triggers targeting Idle/Tp_Default/Resting/
Movement but never created those sets -- the engine complained about missing
trigger targets from the first action. Ruling: **seed the four base sets,
EMPTY, wherever the starter triggers are seeded** -- rules and their targets
always travel together.

`profiles.starterDynText` (the scaffold; also used by migrations that find no
Dynamic block, replacing the empty frame) + `setupui.seedSetsFile`
(never-clobber, active profile's sets file; called from the fresh path, the
migrateToCleanProfiles per-job loop, and the healthy-state re-seed). Tests
Y25b/Y25c; sims 26/26 + 9/9; 1090 + 125 green. (599bfd4; the sim also caught
and fixed the empty legacy dlac\triggers\ dir a fresh player used to get --
3788e62.)

## Session "pet conditions v1" (2026-07-18)

**Theme:** Henrik: no condition matches "you have a pet" -- pet jobs (BST/SMN/
PUP/DRG, GEO idle-luopan) cannot express pet-aware Default gear. Researched the
whole ecosystem FIRST (background agent over GearSwap core, Mote-Include,
Kinematics jobs, Selindrile, LuAshitacast + local ffxi-lac) ->
`docs/reference/pet-handling-other-luas.md`, every claim source-cited.

**Findings that shaped the design:** every framework's baseline is exactly two
primitives -- pet-exists + pet-status (the player x pet 2x2, incl. "master idle
while the pet fights": Mote `sets.idle.Pet.Engaged`, lac-profile `Pet_Only_Tp`);
identity comes third (avatar perp sets keyed by pet name). dlac's synthesized
PetAction event already covers the action-window half (GearSwap pet_midcast
parity, better than stock LAC's poll pattern). Jug NQ/HQ: nobody beats the
existing sets+cycle answer. Parked for later: pet HPP/TP thresholds, Selindrile's
petWillAct anticipation hold (maps onto our stateless-hold pattern if PUP
automaton WS ever misses), pet-stat namespace for the optimizer (ffxi-lac
precedent scores nested Pet={} as 0).

**Landed (engine v63):** conditions `pet` (true/false), `petStatus`
(Idle/Engaged), `petName` (Henrik: essential for SMN) off `ctx.pet =
gData.GetPet()` -- nil petless AND at pet HPP 0, so a dead pet reads as NONE;
petStatus/petName imply existence (never match petless). Tiers: pet 22 /
petStatus 23 between status (20) and moving (25) -- a pet-refined rule outranks
its base rule with no hand priority, Movement still overlays; petName 50 =
identity tier. GUI: second cascading **Pet** row beside Player (HasPet / NoPet /
PetStatus / PetName -- HasPet/NoPet are one key, two fixed values), pet family
colored green, live `[on now]` markers via an addon-side GetPet mirror
(EntityStatus map, data.lua:534 shape). `/dl why` Default line now carries
`pet=Name(Status)`. Starter-file comment + trigger-system.md updated. Tests: PT1-22
(matchers, tier ladder, 2x2 through _matches, serializer round-trip incl.
`pet = false`, normalize). 1112 green.

## Session "set bonuses land â€” display + optimizer" (2026-07-18)

**Theme:** Henrik: "First and foremost, show sets stats on gear! Secondly, make
them count in weight evaluations!" The conditional-effects groundwork (design
doc approved, `data\gearsets.lua`/`data\latentstats.lua` shipped 4af3e5f) had
never reached runtime -- issue #40's cloud dispatch produced no PR -- so P1
(sets visible) and P3 (optimizer credits) shipped together in one local pass.
Latents (P2/P4/P5, issues #41/#43/#44) remain open.

**Landed:**
- `gear\geareffects.lua` -- pure-core evaluator: `setsOf`/`setInfo`/`setTier`
  (`tiers[min(count,max)]`, nil below min), `countPieces` (per SLOT, duplicates
  twice -- server-verified; level-gated like the applier's sync rule), and
  `comboStats(composition, ctx)` -- THE whole-composition truth behind every
  number. Latent data loads dormant (`latentsOf`) for P2.
- Display: worn + planned totals evaluate through comboStats (a worn
  Lava's+Kusha's finally shows ATT+6/ACC+12/DEF+6); `renderStatsPanel` gains a
  set-attribution caption block (active gold with deltas, partial sets dim with
  "bonus at N" -- the one-more-piece hint); the item tooltip shows each set's
  tier ladder + partner pieces with owned-marks (`With: Kusha's Ring*`). Set
  display names are derived from piece names (pair -> "A + B", family -> common
  word prefix + " set", else "first +N") -- labels are Henrik-vetoable in-game.
- Optimizer (ADR 0011): `optimizePicks` `opts.effects` folds active tier deltas
  INSIDE the per-weight cap fold over incrementally-maintained per-set counts;
  converged-baseline set-seeded restarts (top-6 singles by projected value +
  disjoint pairs, <=12 hard cap, least-loss placement, monotone acceptance)
  fix the pair-discovery hole; buildBestSet's top-20 prune appends (never
  removes) weight-relevant set members; the Sub marginal call passes the joint
  pick as `baseComposition` (grip completing a set = credited, offer untouched);
  the Sets panel's weighted number is now the same combo objective.
- The `candidateStats` seam: joint pools + Sub marginal now weigh base+augment
  stats like scoreOfItem always did (a pre-existing gap the design flagged).
- Greedy `/dl` single-stat builds stay set-blind by decision (ADR 0011), pinned
  by HB10.

**Tests:** GD1-13 (shipped-data regeneration guards: 126 sets, 39/87 split,
census 20/1/86/19, [70] exact, [43] alternates 9/2/2, latents 1848 rows/zero
level-latent leakage), GE1-18 (evaluator semantics incl. the real-data
Lava/Kusha end-to-end), HB1-HB11 (objective pin, seeded discovery, EMPTY-tie
survival, conflict-vs-copies, eviction/monotone, cap sharing, effects-nil
bit-identity, tiered marginal, baseComposition credit, set-blind greedy path,
augmentation end-to-end through buildBestSet). 1161 + 125 green.

## Session "fishing gear system" (2026-07-18, engine v64, docs/design/fishing-gear.md)

**Feature: the third sibling** â€” Auto Fish Set beside Auto Craft Set and Auto HELM
Set (Henrik: "I am NOT out to automate fishing, I just want to streamline the
experience"). Research fanned out three ways before a line was written: the dlac
HELM/craft map (the template), the CatsEyeXI server source on GitHub (mechanics),
and the local catalog/api_cache (items).

**What research settled:**
- **Fishing on CatsEyeXI is stock-LSB C++** (`src/map/utils/fishingutils.cpp`,
  3,242 lines, an older snapshot: chart quests stripped, chest catching commented
  out) driven by public SQL â€” no hobbies/fishing dir, no Lua fishing scripts. The
  catch pools (zone+area â†’ group â†’ fish, gated HARD by `fishing_bait_affinity`:
  no row = that fish can never bite that bait) and the three reel-in fail rolls
  (lose :719 / line snap :784 / rod break :828) are all public, formula-exact.
  That makes **bait isolation** ("which bait+zone makes ONLY my fish bite")
  and **rod safety verdicts** computable offline â€” the two flagship asks.
- **The private overlay provably adds content on top**: custom mods 2004/2005
  (carriers: Ebisu =10, Ebisu +1 =15, Halieutica =50/5, Mariners pieces,
  Brigands Eyepatch; semantics NOT public â€” server-questions.md Â§4 stays open,
  the addon uses them as ladder tiebreakers only). **Halieutica 20945 is a
  Main-slot fishing weapon** (polearm-skill spear, Fish+2), not a rod. **The
  Mariners set is fishing's VP tier** â€” its ids interleave HELM's Plain block
  (25899/900, 25966/67, 25986/87, 26535/36 + Brigands Eyepatch 28443 as the
  hat analog).
- **Fishing VP was already streaming**: helmwatch's 0x1A4 parse stores every
  group/label and the field capture had confirmed a `Fishing` label back on
  07-17 â€” `pointsFor('Fishing')` worked before this session started. **Fishing
  guild GP sits at 0x113 offset 0x20**, one map entry away from craftwatch's
  GP_OFFSET (a run_tests fixture had it labeled "ignored" since the craft arc).
- Skill is `GetCraftSkill(0)` â€” the index craftwatch's map deliberately
  skipped. Effective skill = display skill + worn Mod::FISH; cap = (guild
  rank+1)Ã—10, rank-ups at Thubu Parohren (Port Windurst), Expert = 110. Lu
  Shang's 10k-carp quest pair is active in public scripts; Ebisu acquisition is
  private.

**What shipped:** `tools/gen_fishdb.py` (fetches the nine fishing SQL tables,
CREATE TABLE-driven parsing, scans api_cache for mods 127/2004/2005) â†’
`data/fishdb.lua` (128 fish, 39 baits, 575 affinities, 20 rods, 95 zone pools,
259 fishable mobs, guild tables, gearBonus supplement; ~70 KB).
`feature/fishcalc.lua` â€” PURE math: the three fail formulas ported VERBATIM
(including the uint8 wrap on tooBig's over-skill rebate and tooSmall's guarded
subtraction â€” F11/F12 pin both), rod ranking, live isolation derivation,
mob-bite risk, search. `feature/fishwatch.lua` â€” state owner (fishstate.lua:
enabled session-only, target/rod/bait persist as CLIENT names), rod/bait
auto-pick + ~2s bag heartbeat re-pick (bait runs dry â†’ next owned bait + chat
line), fishing-only !ventures 0x017 capture (format UNPINNED â€” raw mirror to
fishventures_capture.txt), `/dl fish` commands. `ui/fishui.lua` â€” the panel:
status line (skill/GP/VP), 4-column gear matrix (BASE / ANGLER'S / GUILD GP /
MARINERS VP + Halieutica), rod columns (standard/legendary), target-fish search
with ISOLATION-first spotÃ—bait rows (mob âš , "items can always bite" footnote),
rod verdicts from the real math, per-container bait census, ventures, guild
corner; coverage/status sit ABOVE the imgui guard (headless-testable â€” helmui
improvement). `ui/fishbar.lua` â€” pill + target + rod/bait item icons (zero new
assets). Engine v64: `ensureFishState`/`fishOverlayFor` (Default-only,
Engaged/Dead stand-aside; Range/Ammo straight from state, armor + Main via the
manifest `fish` ladders â€” Main included on the CRAFT precedent because of
Halieutica), `dlac:AutoFish` in resolveVirtual, **three-way at-stamp
arbitration** (ties keep the older system: craft > helm > fish). triggersui:
AUTO_FMT 7â†’8 (fish ladders: FishingSkill-major, cx tiebreak, disjoint rings),
fifth Automations row + fishui delegation. craftwatch: GP_OFFSET gains
`Fishing = 0x20`.

**Tests:** F1-F69 (hand-derived server-math cases â€” the expectations carry a
"re-derive from the C++ before editing" warning â€” fishdb integrity, pick rules
incl. the Yew-over-Willow least-risk case, overlay resolution, GP 0x20) +
smoke S130-134 (headless loads; fishui.status callable without imgui).
1231 + 130 green. NOTE: the F-section itself rode into cd2381c via the
parallel session's staging â€” harmless overlap, this commit brings the modules
it exercises.

**Deliberately NOT done:** any automation of fishing (no casting, no 0x115
mini-game reads, no bite reactions â€” the server carries an anti-bot surface,
`GetRecentFishers()`/`[Fish]LastCastTime`, and the bright line stays bright).
Field tests pending: design doc Â§6 â€” `!ventures fishing` format pin, GP/VP
sanity, first live overlay run, custom-gear stat text.

**Field round 1 (same day, Henrik live):** the panel worked on contact â€” his
screenshot shows Lu Shang's SAFE verdicts and Giant Donko isolation rows.
Five fixes from the pass, plus one identification that closed a server
question: **the bg-wiki CatsEyeXI Ventures page lists "Expert Angler:
Fatigue Limit +10%, Golden Arrow Rate +1%" on Mariners Tunica/Boots â€” values
matching mods 2004/2005 in the live DB exactly (10/20 base/+1, 1/2), so
2004 = Fatigue Limit +%, 2005 = Golden Arrow Rate +%** (server-questions Â§4:
two of the three unknowns answered; 2017 remains). Panel rulings: glow is
MARINERS-ONLY (the real fishing end-game â€” Angler's/guild gear just green;
Expert Angler tooltips on the carrying pieces); Lu Shang's +1 / Ebisu +1 /
Halieutica / Brigands Eyepatch UNDISPLAYED (unmentioned in-game, look
unobtainable â€” data stays, autoPick honours an owned one); owning Lu
Shang's/Ebisu greens the whole standard rod ladder (the cascade); the buy
suggestion only appears when no owned rod is SAFE (and never suggests the
+1s); [ISOLATED] column widened 90â†’128 (themed-font clipping, the
button-width lesson again); the 10k-carp guild line hides once Lu Shang's is
owned. itemLine also inherited helmui's note-beats-tooltip order en route â€”
the cascade/Expert Angler notes were silently losing to the stat card.

### Field round 1 (same day): the Salvage label bug

Henrik: Lava/Kusha good; Ares showed "gives Ares' Cuirass +4"?! Two findings:
**(1) Data truth, not a bug:** base Salvage 75 sets (Ares/Skadi/Marduk/
Morrigan/Usukane, sets 1/2/3/7/8) are min5/max5 -- all five pieces or nothing,
one flat tier (DA/Crit/FastCast/MAB/Haste +5). The remembered 2/3/4/5-piece
ladder belongs to the +1 (Salvage II) sets 77/78/80/81: 3/5/7/9. **(2) The
label fallback was the bug:** "<first piece> +N-more" reads as an HQ item name
("Ares' Cuirass +4"), and it fired because piece names drift per source --
owned resolves "Ares's Cuirass" (game), unowned "Ares Mask" (catalog short

## Session "architecture review â†’ refactor/deepening" (2026-07-18/19)

**Theme:** /improve-codebase-architecture over the whole addon (four explorer
walks: engine, GUI, gear data, test surface), then Henrik: *"You are the
maintainer, do it all, but keep it in a separate branch where we test each
step."* Eight deepening steps landed on `refactor/deepening`, one commit each,
suite-gated (1355 â†’ 1508 headless checks + 170 smoke); engine v68 â†’ v71.

**Landed (in order):**
1. `gear\triggermodel.lua` â€” the Triggers tab's rawâ†’edit-model translation,
   pure (canonEvent injected, groupsmodel pattern). THE wipe contract (Commit
   serializes the whole model; an uncarried section is erased â€” shipped once)
   finally test-pinned: TM1-19.
2. `gear\gearrecord.lua` â€” the Owned-gear record rules in one home: canonType/
   healType (legacy-spelling heal), subTypeFromName, effectiveRSlot (ADR 0010),
   enrich/mergedStats precedence. Five stamp sites delegate; REC0-26 include a
   vocabulary-closure check (every filter bucket key canonizes to itself).
   Deliberate alignment: gearexport now heals drifted Types like the GUI.
3. `lib\safewrite.lua` â€” backup/tmp/validate/rename/restore written once
   (gearimport carried it twice, near-copies); profiles' deleters ride
   verifiedMove and REFUSE when the net is missing. setmanager's rotated
   policy deliberately stays its own (one adapter = hypothetical seam). SW0-14.
4. `gear\catalogindex.lua` â€” the one catalog walker: lazy load, rawIndex/
   rawById, flat browse copies, the generic flatten (gearui's flattenGear is a
   delegate; owned gear flattens through the same code). Engine still never
   loads the catalog. CI0-12.
5. ownedcache deepened (no parallel module â€” it already IS the ADR 0005 home):
   verdict(rec, usable) with stored>locked>ok precedence + whereText caption
   builder + _splitOverride = its first test reach ever (AV1-13). Noted, not
   changed: automationsui lights an owned-but-STORED staff green.
6. **v69** â€” obi + Oneiros decisions extracted pure (resolveObi /
   resolveOneiros, the resolveStaff shape); the two field-calibrated gates
   pinned headless (VG1-15, incl. the Mindie 714â†’357-inclusive boundary
   verbatim).
7. **v70** â€” the statefile seam: ensureStateFile behind the auto/acc/craft/
   helm/fish/pin caches (six near-identical clones that had DRIFTED); corrupt-
   write policy unified on pin's v44 DROP â€” craft/helm/fish/auto used to keep
   stale state glued on forever after a torn write. _charDirOverride runs the
   file-driven surface headless (SF0-9). Then `lib\statefile.lua` = the one
   addon-side charDir (four watcher copies deleted); watcher write sites
   deliberately untouched (3-line dances, churn > depth).
8. **v71** â€” equipResolved: the five whole-table post-passes are named entries
   run in M._postPassOrder (trinket-BEFORE-reserved is checkable adjacency,
   PL1-3); the per-slot chain keeps its elseif precedence, now named; copy-on-
   write + note built once. The review card's "11 uniform passes" sketch was
   wrong about the shape â€” the per-slot chain is correct as-is and stayed.

**Key decisions:** candidate 9 (watch-bar chassis) NOT built â€” its own deletion
test failed (deleting fishbar deletes a feature, not a coupling); revisit if a
fourth gear-system twin lands. The one deliberate behavior change on the
branch: statefile corrupt policy = DROP everywhere (+ gearexport's Type heal);
everything else bit-identical by test.

**Standing:** branch `refactor/deepening`, 10 commits, unmerged. Field-test the
engine steps (the Reload LAC banner will prompt â€” v71), then merge to main.
names; the +1 sets even mix "Marduks Jubbah +1" with "Mdk. Dastanas +1"), so
the all-pieces word-prefix never matched. setLabelOf rebuilt: majority
first-word family via a drift-tolerant stem (lowercase, punctuation out,
trailing s off), word-extension within the family ("Iron Ram set"), shared
quality mark kept visible ("Ares +1 set" distinct from base "Ares set"),
"+N" form deleted outright; fallback "N-piece set". setLabelOf exported as a
uihost service; smoke S41-S44 pin Ares/Ares+1/Mdk.+1 against the REAL catalog
plus a sweep: every one of the 126 labels is a pair or "... set", never an
HQ-item shape. 1234 + 135 green.

## Session "automationsui extraction â€” the migration completed" (2026-07-18, overnight)

Henrik, heading to bed: "complete the automation tab migration -- last time we
did the cheap way and let a lot be left." The cheap move (07-17) promoted
Automations to its own MAIN tab but left the renderer + manifest machinery in
triggersui behind an `M.renderAutomationsTab` wrapper, with the extraction
spec'd in architecture.md for "when triggersui next grows."

**What moved:** the whole ~1,100-line automation block (`ELEMENTS8` through the
tab entry) went to `ui/automationsui.lua` verbatim -- manifest derivation
(staves/obis ADR 0004, MaxMP batteries, craft/HELM/fish ladders, `AUTO_FMT` 8),
the self-heal, the list/detail views, and the seams `rescanAutogear` /
`manifestStale` / `currentFmt`. The tab entry is `M.renderTab`; the dead
`noHeader` CollapsingHeader path (unreachable since the tab promotion) was
dropped rather than carried. triggersui 3713 â†’ 2609 lines, 30 top-level locals
freed (plus 3 more: its `levelstats` require turned out to be automation-only).

**The seam repoint is COMPLETE -- no forwarders.** craftwatch, helmwatch and
fishwatch's `ensureManifestFresh` and gearui's syncflags rescan hook all
require automationsui now (the commit note had said "repoint them or leave
zero-local forwarders"; forwarders would have split the manifest cache into
two modules' copies that could disagree about staleness). gearui builds ONE
deps table and hands it to both `trigui.init` and `autoui.init`, so
helmui/fishui -- which take the whole table per call -- kept their contract
bit-for-bit. smoke_ui grew S140-S151: the new module loads headless, every
seam exists and no-ops safely uninitialized, and triggersui NO LONGER carries
`rescanAutogear`/`manifestStale`/`renderAutomationsTab` (the zombie-forwarder
guard). 1234 + 147 green.

### Same night: the writer gets its net

With the machinery extracted, `autoCommit` became injectable for the first
time -- smoke section 9 (S160-S180) feeds `automationsui.init` a curated
19-item fake inventory, runs a REAL `rescanAutogear`, re-reads the written
`autogear.lua` and asserts every family's decisive rule: the HQ-over-NQ and
job-gate staff picks (the Foreshadow case, now pinned), universal pecking
order, the lowercased/ConvertHPtoMP hold map, the x2-ring disjoint ladders,
weapon batteries excluded from mpBest, anti-HQ blocked from the hq goal,
skill-up gainFill fillers, Surveyor-major helm scoring + the exact-name hat
map, FishingSkill-major fish ladders with Main IN and rods OUT, and the
fmtver/manifestStale round trip. The fmtver-5 silent-abort bug class -- the
writer dying inside its pcall and the manifest never regenerating -- can no
longer ship unseen. 1234 + 170 green.

### Field round 5: the rod that wouldn't come back (2026-07-18)

Henrik at the pond with the exact scenario the system exists for: target Moat
Carp, remove Lu Shang's, add Clothespole, take Lu Shang's back -- and dlac
kept fishing with the Clothespole. Two real defects and a missing feature
behind one symptom. The sort: `rodsFor` had no idea legendary rods ARE the
prioritization -- on a risk-0 fish the atk tiebreaker put Clothespole over Lu
Shang's. Henrik's ruling became `LEG_RANK` (Ebisu +1 > Ebisu > Lu Shang's +1 >
Lu Shang's > the field), sitting deliberately BELOW the risk sort: a fish
that would snap Lu Shang's still gets the safe base rod (F73 pins that
primacy). The heartbeat: `revalidate` only acted when the CURRENT rod
vanished -- with rodId already nil (or a better rod merely arriving) it
early-returned forever, which is why only a pill toggle re-picked. It
re-ranks every ~2s beat now; the field scenario is F79, and the chat says
"better rod in your bags -- switched to" when it happens. The suggestion
line needed a guard the same minute the tier landed: overall-best is now
always Ebisu, and "go quest Ebisu" is no shopping hint for a carp -- LEG_ANY
excluded from `suggest`.

The missing feature was Henrik's second ask made law: manual overrides >
automation, every day. The fish bar's rod and bait names are BUTTONS now --
popups listing what the bags actually hold (rods with live verdict tags at
the panel's effective-skill convention -- `wornFishTotal` moved to fishcalc
so both sides share it; baits affine-first with power, off-affinity rows
marked "target will NOT bite this" but still pickable). A pick PINS:
`rodPin`/`baitPin` persist in fishstate (the engine reads only
enabled/rod/bait/at), auto never trades a pinned item while it's owned, a
vanish unpins, and changing target unpins -- a rod pinned for carp could
snap on the new fish. `*` in the bar, "(manual)" on the panel.

And Clear, round three: the round-4 reset was CORRECT and still lost -- the
adopt line (`sel.id = tgtId` when the panel has no view) ran later in the
same frame with the stale `tgtId` local and re-pinned the old fish, so the
spot list looked unclearable. The fix is one line: Clear nils the frame's
copy too. fix/fish-isolation-bait was field-confirmed the same message and
fast-forwarded into main first. 1253 + 170 green.

### Field round 6: all clear (2026-07-18)

Henrik's confirmations closed the field-test slate in one message: `!ventures
fishing` "works like a charm" (the command exists as spelled and the reply
holds the HELM line shape -- the tolerant parser was enough; the raw mirror
stays as drift insurance), GP at 0x20 matches ("we know it works since other
times"), VP needs no worry, and the round-5 dropdown pins behave. Remaining
from the slate: only the custom-gear stat-text report (needs the items to
drop) and the GetRank cap question. Docs + fishwatch's two UNPINNED status
comments synced; no code behavior changed. A new fishing feature is planned
for a fresh session.

### Game modes become readable (2026-07-18)

Henrik asked whether the crystal next to a name -- CatsEyeXI's CW/UCW
marker -- could be read from memory. The hunt ran the whole stack in one
session: the public server repo's `base` branch turned out six months stale
(`stable` is the live branch -- correction recorded in memory),
`isCrystalWarrior()` exists there only as a CI-whitelisted PRIVATE binding,
and Nameplate.dll's "hidestars" strings gave the tell that the icons ride
the retail nameplate renderer, re-skinned. dlacprobe v1.8 grew
`/probe icons` (every rendered player's icon words in one dump) plus an
0x00D wire watch, and Henrik's labeled capture in Tavnazian Safehold pinned
the bits in one pass: RenderFlags4 `0x1000` = crystal (his UCW and
Skincrawler's CW read identically), `0x4000` = Askar's Wings Cait Sith,
ACE = neither -- XiPackets names those slots as the retail new-character '?'
and mentor 'M' icons. `feature/gamemode.lua` ships the check as dormant
foundation for whatever gets gated on play mode next -- and Henrik set its
shape: not "is there a crystal" but ONE central reusable question,
`gamemode.get()` -> `'CW'` | `'Wings'` | `'ACE'` (nil = unknown and never a
guess, GM1-GM8). The crystal is plumbing; the mode is the answer.

One thread was deliberately cut rather than resolved: white vs pink.
Mindie's extra F7/F8 bits were confounded (sole local-player sample in the
capture), and before a deconfounding capture happened Henrik ruled the
question moot -- "CW and UCW are still in the same playmode and have the
same restrictions"; crystal-vs-not IS the play-mode split, and the need is
"100 %" satisfied. The revival path, should shatter-risk ever matter to a
feature, lives in the cw-ucw-mode-detection memory file.

### Native MP becomes computable (2026-07-18)

Henrik asked whether a character's native MP -- the 724 his Hume WHM75/SCH37
shows naked -- could be produced by a callable function instead of a lookup
table. It can, exactly: the server repo's `grades.cpp` carries the whole
system (race MP grades, job MP grades, a 7-rank growth table) and
`charutils.cpp CalculateStats()` combines them -- race pool + main-job pool
grown to the main level (rate KINKS at 60: D-G grades speed UP past it),
plus the subjob's pool at `(slvl-1)` halved by `SJ_MP_DIVISOR = 2`; when the
main job has no MP grade at all, the RACE pool rides the subjob's level
instead, also halved (why NIN/WHM has any MP). The formula put Mindie at
614, not 724 -- and the 110-point gap closed on CatsEyeXI's merits.sql: Max
MP merits are 10 MP each with the cap raised 8 -> 15 levels, so 724 = 614 +
11 merit levels, a checkable prediction (open the merit menu). Merits are
the one part the client can't read passively, so they stay a caller-supplied
argument.

`data/nativemp.lua` ships the port verbatim (tables exposed for display,
`get(race, mjob, mlvl, sjob, slvl [, meritMP])`, plus a gamemode-pattern
`self()` with injectable live readers -- race comes from the entity's look
id, the exact field the server switches on). Expectations in the tests are
hand-computed from the server tables so a transcription typo fails: the 614
field pin, the 240.5-truncates-to-240 Galka case, the over-60 kink, the
race-rides-sub NIN/WHM case (NMP1-NMP16). Dormant like gamemode was --
first consumer candidates: Refresh/Convert valuation and the latent "MP <
N%" gates when latents wake (#41/#43/#44).

### Auto Oneiros Grip: the first nativemp consumer (2026-07-18)

Dormant for about an hour. Henrik's next message asked for a Sub-slot
automation around Oneiros Grip -- latent Refresh +1 while MP sits under 75%
of the "native base MP without any gear" -- and the server source confirmed
his phrasing is EXACTLY the mechanic: `MP_UNDER_PERCENT` divides
`health.mp` by `health.maxmp`, and `health.maxmp` is CalculateStats' base
pool (race/job/sub formula + merit MP) -- equipment MP rides a separate
modifier and never moves the denominator. Comparison is `<=`, and
`floor(base * 0.75)` reproduces it exactly for every integer base (a base
divisible by 4 lands the boundary ON an integer and the latent still
fires there; any other base puts it strictly between two).

`dlac:AutoOneiros` (engine v65) follows the AutoStaff shape end to end:
manifest entry `oneiros = {name, level}` (fmtver 9), resolveVirtual
computes threshold = floor((nativemp.self() + 10 x mpMerits) x 0.75) live
-- so job change, subjob change and level sync re-aim it with no rescan --
and answers /dl why with the numbers when MP is too high; virtualMinLevel
reports the grip's Lv75 so the flatten skips the marker as an unreachable
rung below that. Two things earned their own design beats: the FLATTEN now
treats the marker as a grip under the shared subSlotAllowed rule (2H main
composes 'dlac:AutoOneiros|<real grip>', a 1H main vetoes the marker
outright -- the + Add picker still offers it unconditionally per the
sub-slot HARD RULE), and merit MP became the manifest's first USER-OWNED
field: `mpMerits` (0-15, an Automations-tab input on the new detail view)
survives every rescan by riding the loaded manifest through autoCommit,
because merit allocations only cross the wire when the merit menu opens --
the one number the client cannot read passively. The detail view shows the
whole aim live: native + merit = base, the <=threshold line, and whether
the grip is ACTIVE right now. AO1-AO12 (boundary inclusive both with and
without merits, no-pool jobs, unreadable native, the 2H/1H flatten pair);
1290 + 170 green.

### The 724 decomposes completely (2026-07-18)

Henrik's field correction landed within the hour: the merit menu reads
10/10, not the predicted 11/15 -- and he brought BG-wiki's Oneiros page,
which describes the retail latent as counting weapon and grip MP (the
grip's own MP+5 included). Both threads resolved against the server source
in one pass. The merit side: merit.cpp multiplies value by
min(count, cap[level]) and cap[75] = 10 -- the merits.sql upgrade=15
headroom only opens at Lv80+, which a 75-cap server never reaches, so the
menu's 10/10 IS the mechanic. The missing 10: traits.sql gives SCH Max MP
Boost +10 at level 30 (trait 8, Mod::BASE_MP 1096), so his /SCH37 carries
it -- 614 formula + 100 merits + 10 trait = 724 on the nose.

The decisive part is WHERE each term lives. UpdateHealth builds
health.modmp -- the DISPLAYED max -- from health.maxmp + BASE_MP (traits)
+ Mod::MP (gear) + conversions + food; the latent divides by health.maxmp
alone, which only CalculateStats writes (formula + merits). And BG-wiki's
weapon-counting rule turned out to be a DIFFERENT latent id
(MP_UNDER_VISIBLE_GEAR) whose CatsEyeXI implementation is entirely
commented out -- item_latents row 18811 carries latent id 4, plain
MP_UNDER_PERCENT (the generated latentstats.lua label was right all
along). Net: the trait and the grip's MP+5 move the screen number, never
the denominator. Mindie's true aim is 714 -> Refresh live at MP <= 535,
not the 543 the 11-merit theory implied. Engine v66 clamps mpMerits to
the usable 10, nativemp's constants/comments state the modmp-vs-maxmp
split, and the detail view now warns against tuning merits to make Base
match the naked screen. A three-point field test can still adjudicate
code-vs-live if wanted: with the grip on, standing MP ticks at 535 (code),
539 (wiki rule incl. grip+main MP on a bare main), or 543 (11-merit
theory). AO grew the clamp pair; 1292 + 170 green.

### The field says 50, not 75 (2026-07-18)

Henrik ran the tick test and none of the three candidates hit: his break
is **357/358** -- with refresh gear on, 4 MP a tick through 357, back to 3
at 358. One division later the number identified itself: 357 is exactly
**50.0%** of 714. So the measurement CONFIRMED the hard part -- the
denominator is health.maxmp = formula 614 + merits 100, with gear, food
and the SCH trait all excluded (50% of the on-screen 724 would break at
362), and equality-fires confirmed the `<=` boundary -- while overturning
the easy part: the live percent is 50 where the repo's item_latents row
says 75. Repo seed vs live DB divergence, filed as server question #6;
live wins per standing rule. Engine v67 changes exactly one line
(`* 50 / 100`), the UI and tips now say 50 and cite the field pin, and
the AO tests re-aim to 357/358 (meritless 307/308). Mindie's automation
now equips the grip at MP <= 357. If the team ever answers "75 was the
intent", the same line flips back.

### Merits teach themselves (2026-07-18)

Henrik asked whether merits could be read from memory -- the one manual
input the Oneiros automation still carried. From MEMORY: no. Ashita's
IPlayer stops at the unspent pool (GetMeritPoints/Max); per-category
allocations never sit in a readable structure. From the WIRE: yes. The
server's own packet headers (packets/s2c/0x08c_merit.h) spell the layout
-- u16 count, u16 pad, {u16 id, u8 next, u8 count} entries -- and 0x08C
flows as five 61-entry chunks when the merit menu opens PLUS a
single-entry update on every merit raise/lower. There is no benign
request to inject (c2s 0x0BE only spends points or flips EXP/Limit mode
-- both mutate), so unlike craftwatch's guild-point self-request this
stays listen-only: open the menu once, ever, and the number is learned;
respec Max MP mid-session and the threshold re-aims live.

feature/meritwatch.lua is the whole feature: a pure bounds-checked
parser (max_mp = merits.sql id 66), a packet hook, and a call into
automationsui.setMpMerits -- the same clamp/persist/hot-reload path the
manual input uses, which stays as the fallback and now carries an
"auto-learns" hint. MW1-MW9 drive the parser and the write end to end
(the learn chat line fires in the test run); 1301 + 170 green.

Henrik then asked the natural next question -- inject a packet that
simulates opening the menu, as a refresh button -- and the answer
dissolved the problem entirely: the merit protocol has NO request packet.
XiPackets' 0x008C doc states the client wipes its merit cache at every
zone and the server re-populates at ZONE-IN unprompted; the menu never
asks for anything (0x0BE validates Kind to spend/mode-flip only, and the
0x061 status bundle carries just the point pool -- verified in
SendLocalPlayerPackets). His own menu reading 10/10 mid-session proves
live CatsEyeXI pushes at zone-in too. So no button: meritwatch hears the
full list at EVERY zone -- the first zone after this ships is the first
sync, and CatsEyeXI's full-form even includes zero-count entries (the
LSB 5x61 TODO shape), so a total respec also lands. One real bug fell
out of the same doc: downgrading a merit's LAST point flags the wire
entry by setting the index's low bit (66 -> 67) -- the parser now reads
odd ids as "back to zero" (MW5b/5c). 1303 + 170 green.

A hidden `/dl merits` diagnostic closes the loop (Henrik: "just to see
that this workflow works") -- wire-this-session vs manifest vs the
resulting Oneiros aim, in no help list on purpose. MW10-12 pin the new
getMpMerits getter it reads from.

And then the loop actually closed: Henrik logged in after a full
shutdown as WHM75/BLM37 and /dl merits reported wire 10 / manifest 10 /
aim 376 -- MP-checked correct. One login confirmed four things: the
zone-in push survives a cold start with no menu visit, the manifest
persists, the formula generalizes across subjobs (652 + 100 = 752 ->
376), and the aim MOVED with the sub change (357 on /SCH -> 376 on
/BLM), proving the per-resolve re-aim -- with the /BLM naked number
carrying no +10, which confirms the SCH-trait display theory from the
other side. AO13/14 pin this second field shape. 1308 + 170 green.

The last nail followed the same evening: Henrik watched the tick on
/BLM -- works at 376, gone at 377. Two shapes, both breaking at exactly
50.0% of maxmp with inclusive boundaries, and a threshold that MOVES
with the subjob: the flat-value alternative is dead, the percent rule
is tick-verified twice over, and server question #6 now carries both
data points. Every number the automation computes is double-confirmed
against the live server.

## Session "mode sections in the set builder" (2026-07-18)

Henrik: slot lists bloat once mode cycles are in play -- a WHM Main list
carries the whole Caster ladder AND the whole Club ladder in one flat
list, "kind of hard to follow properly". His design, implemented
verbatim: a mode gating MORE THAN ONE row in the list earns a
collapsible section (default collapsed) headed by the mode name plus the
ascending item-level ladder of what's inside, so level coverage per mode
reads at a glance. Membership rules: an OR-gated row appears under EVERY
sectioned gate; a row whose every gate is sectioned leaves the root; a
row ungated -- or alone on any of its gates (no section forms for one
row) -- stays in the root, and still also shows under its sectioned
gates.

Implementation: the grouping is a pure function, `gearfmt.modeSections`
(display-ordered wrappers in; root rows + alpha-ordered sections out;
case-insensitive keys, first-seen spelling names the section, per-row OR
lists deduped so {'DT','dt'} can't fake a two-row section). The Sets-tab
renderer extracts its row block into one `renderRow` closure -- ids and
the alternating row background ride a running counter, so a row
rendering twice (root + section, or two sections) keeps unique imgui
ids, and the B/D/x actions already resolve by wrapper identity so they
work from any copy. Section headers are `CollapsingHeader`s with
`###`-stable ids keyed set+slot+mode (toggled-open survives re-sorts,
never leaks across sets/slots), text green while the mode is live
(`entryModeOk`), rows indented 10px inside. MS0-MS16 pin the grouping
rules headless. 1326 + 170 green.

## Session "dead mode gates + the invisible Savagery" (2026-07-18, same evening)

Two field reports within the hour of mode sections shipping. First:
"if I change my Cycle mode, the non-existent modes are still there on
the weapons." The delete flow already swept references (modeSetRefs /
modeCondRefs) but VALUE edits never did -- so Save on an edited cycle
now diffs the value list and sweeps every removed 'Name:Value' through
the same machinery, then commits immediately (the delete-flow
discipline: the trigger reload also purges a live stale value). The
sweep also learned the v54 OR shape it never knew: whenAny legs are
honoured -- a dead & leg collapses to OR-only, a dead | entry is
removed, a rule with no live leg goes whole (MC0-18).

Second: "why can I not find my level 20 great axe Savagery with the
Great Axe filter?" -- because Mindie's owned record says Type = "Great
Axe" WITH a space. Early gear.lua vocabularies wrote display forms;
the importer now writes catalog keys ('GreatAxe'); a scan never
rewrites an existing entry, so real files MIX spellings (Mindie: 8
'Great Axe' + 6 'GreatAxe', plus 'Hand-to-Hand', 'Great Katana',
'Wind Instrument', bare 'String'). The drifted form bucketed as an
unknown type: invisible under the canonical mark AND a second
identical-looking "Great Axe" entry in the dropdown. Fixed in both
layers (the S21/S22 pattern): weaponfilter normalizes every bucket key
(strip non-alphanumerics + casefold + alias, APL1-10), and
enrichGearFromCatalog heals a spelling-drifted Type to the catalog key
by Id. Note for the future: the LIVE ownership record is
<char>\dlac\gear.lua -- <char>\gear.lua beside it is the pre-dlac
legacy file and reads stale. 1355 + 170 green.

## Session addendum "Add more -- gated adds from a section" (2026-07-18)

Henrik, minutes after trying the sections: "once a section has been
created, add an Add more button to the right in the section box" -- so
building a mode ladder stops being add-piece-then-open-Behaviour per
item. The section header now carries an Add more button (submitted
after the CollapsingHeader so the button wins the hover -- the imgui
overlap idiom); it opens the SAME + Add picker with ui._addGate set to
the section's mode, the picker announces the gate in green, and both
add paths (real items and the dlac:* virtual rows) stamp the gate on
the new row -- which therefore lands straight in the section. The
plain + Add button clears the gate. He explicitly waved off the
auto-primed weapon-type filter idea ("no need, I was just explaining a
nice scenario") -- the filter stays manual, resetting to All each open
as before.

## Session addendum "the section x ungates, never deletes" (2026-07-18)

Field report minutes later: Harpoon gated Base + Polearm, one x inside
the Polearm section, and the row vanished from BOTH ("I can understand
why, but I just want it to remove the mode if so"). Settled semantics:
sections are VIEWS, the root list is the DATA -- so x inside a section
now strips only that section's gate (gearfmt.stripGate, MS17-22; other
gates keep the row in their sections), and a row with no gate left
turns unconditional and visibly reappears in the root list rather than
silently dying OR silently entering the ladder unseen. Only the root
x deletes the row. renderRow learned its render context (sec) for
exactly this; the tooltips say which x you are hovering. 1361 + 170.

## Session "the client forgets injected lockstyles" (2026-07-19)

Field report: a dlac-applied lockstyle died on zoning -- often, not
always, no visible pattern -- while a native /lockstyle never did. Code
sweep (dlac + the new local server clone) exonerated both ends: dlac
only ever sends 0x053 SET from /dl ls apply, and the server persists the
lock (chars.isstylelocked + char_style, reloaded every zone-in) with no
zone-time clearer. That left the client, and /probe ls (dlacprobe v1.9,
decoding every OUT 0x053 mode word) convicted it in one session: the
retail client keeps a PRIVATE lockstyle flag only its own /lockstyle
command sets, and ~0.6s after every zone-in it re-asserts that flag --
CONTINUE when on (which is why native lockstyles self-healed every zone,
and why the drops looked intermittent: any session that touched native
/lockstyle had the flag on), DISABLE when off. Our injected SET never
turns the client flag on, so the client itself killed the style each
zone.

Shipped v43: a zone-in guard in feature\lockstyle.lua blocks exactly
that packet -- an outgoing DISABLE inside 10s of zone-in, while a
lockstyle we saw SET is live, that the player did not just type (the
command handler stamps a real "/lockstyle off", typed or via the
window's Disable button, and the guard yields to it). CONTINUE/QUERY
always pass; out-of-window or no-live disables pass and retire the
guard. Blocking beats re-applying: no undressed flash, no extra
traffic, and the preserved steady state (server locked, client flag
off) is the state every dlac lockstyle already lived in between zones.
Decision half is pure (_lsGuard, LG series). 1509 + 13.

## Session addendum "keep it across subjob changes" (2026-07-19)

Field round 1 on the zone guard: works; the "[dlac] lockstyle kept"
chat line removed on request ("the user doesn't need to know").

Next ask, shipped as v44: keep the lockstyle across SUBJOB switches,
as an option in the lockstyle window. Unlike the zone drop, this clear
is server-side (the 0x100 job-change handler calls SetStyleLock(false)
itself), so there is nothing to block -- it is a re-apply, the OnLoad
pump's own pattern. "Keep on sub change" (per job entry, keepSub in
the storage table): the command handler remembers the session's last
'/dl ls apply' box (GUI button, OnLoad pump and hand-typed all pass
through it), the pump watches the subjob abbreviation, and a
subjob-only flip -- not login settle, not a main change in flight,
main changes reset the memory since box numbers are per job entry --
queues that box again 3s later, but only while the zone guard still
considers a dlac lockstyle live: one the player turned off stays off.
Storage seams pure-tested (LG14-19). 1522 + 6, smoke_ui 170.

## Session addendum "the gate vetoed its own feature" (2026-07-19)

Field round 2 on keep-on-subjob: "I think the idea is right, but does
not work." Diagnosis from the round-1 wiring itself: the client sends
its confused DISABLE on job changes too (same private-flag reflex as
zone-in), it lands outside the zone window, the guard duly retires --
and the pump gated the re-apply on the guard still being live. The
safety condition ate exactly the event the feature exists for.

Fix: lastBox alone is the keep authority now. The guard grew honest
verdicts: retire (player typed it; box memory clears, nothing
resurrects) vs deactivate (unasked; box memory survives) vs adopt
(native /lockstyle on; guard arms but the box no longer describes the
shown style -- the server rebuilds from worn gear). The subjob flip
also arms the guard window, so a straggling DISABLE around the change
is swallowed on either side of the re-apply. LG repinned. 1529 + 170.

## Session addendum "arm off the packet, not the poll" (2026-07-19)

A /probe ls capture of the failing subjob switch (Upper Jeuno moogle,
11:27) fixed the order of events: mog menu opens, and the client's
lockstyle DISABLE leaves AT the confirm -- before the player struct
shows the new subjob. So the round-2 poll-armed window opens too late
to block it and could only heal afterwards (and whether that capture
ran round-1 or round-2 code, the poll race stood either way). Round 3
arms off the OUTGOING 0x100 job-change request instead -- same
confirm, but ahead of the DISABLE: a subjob-only request (main=0,
sub~=0; also catches re-selecting the SAME sub, which no poll can
see and which the server still clears for) arms the guard window and
schedules the +3s re-apply; a main-job request drops the keep memory.
The poll stays as fallback for job-change paths without 0x100.
dlacprobe v2.0 decodes OUT 0x100 under /probe ls. 1535 + 170.

## Session addendum "the kill schedules the cure" (2026-07-19)

Second /probe ls capture (11:34, dlacprobe v2.0, two clean subjob
cycles) overturned round 3: the client's DISABLE leaves BEFORE the
0x100 job-change request -- same stamp, DISABLE logged first -- so
arming off 0x100 can never beat it, and no automatic heal fired in
either cycle (the SET 17s later was Henrik re-applying by hand).

Round 4 hangs the heal on the one event every capture shows: the
unasked DISABLE itself. A 'deactivate' passing through while keep is
on and a box is remembered books the +3s re-apply on the spot
(_keepHeal, pure). Main changes cancel naturally -- their 0x100 lands
just after and nils lastBox and the timer, and the pump re-checks
lastBox at fire time; retire/adopt also cancel a booked heal. The
0x100-sub arm and the pump poll stay as belts. New '/dl ls state'
prints every value the keep decision reads plus a round marker, so a
stale seeded copy of this file diagnoses itself by silence. LG26-31.
1535 + 6, smoke 170.

## Session addendum "the window is the debugger" (2026-07-19)

'/dl ls state' came back silent. Round 5 found two truths at once.
First: in the LAC state, dispatch answered any non-apply ls subcommand
with its usage line, so the new command LOOKED unknown -- dispatch now
stays quiet for 'state'. Second and bigger: a headless sim driving the
REAL registered handlers in the 11:34 capture's exact wire order shows
the whole round-4 chain working -- DISABLE books the heal, the pump
queues the re-apply, stragglers get blocked, main changes and typed
offs cancel. So the assembled chain became a permanent test (LGF
series, fixture tree under tests\fixtures\keepflow), and the live
keep state now renders IN the lockstyle window ('keep4: box N ...'
under the checkbox) -- chat and command routing were exactly the
layers in doubt, and the window only needs to render. No keep4 line
after a reload = an old lockstyle.lua is loaded, which is then the
finding. Heal booking made book-once at all three triggers. 1555 +
170.

## Session addendum "the state does not hear itself" (2026-07-19)

Round-5 window readout in the field: after a button apply + subjob
switch, "keep4: box -, guard off" -- lastBox never set. Diagnosis: a
command QUEUED from the addon state (the Apply button's '/dl ls
apply') does not loop back into that same state's command event --
cross-state delivery works (OnLoad proves it daily, dispatch receives
in the LAC state), but self-loopback does not exist. The round-5 sim
invoked the handler directly: the one link it could not test was the
broken one. Round 6 moves the bookkeeping to the queue sites
themselves: Apply button and OnLoad pump call M._noteApplied directly;
the command observation stays for hand-typed applies. Same principle
for the Disable button -- it stamps M._guardUserOff at the click, else
its own '/lockstyle off' reads as client noise (blockable in an armed
window; lastBox left alive to resurrect a killed style on the next
subjob switch). Window marker now 'keep6'. LG32-34. 1558 + 170.

HOUSE RULE learned: an addon state never hears its own queued
commands. Any self-queued '/dl ...' whose effects the SAME state must
know about needs its bookkeeping done at the queue site, not in the
command handler.

## Session close "keep-on-subjob confirmed" (2026-07-19)

Field round 6: "Works now, perfect." The keep6 debug readout removed
from the window on request (the user does not need it); /dl ls state
stays as the on-demand readout and LGF drives the chain headlessly.
v44 keep-on-subjob is DONE: six rounds, root cause = an addon state
never hears its own queued commands (now a house rule in this file
and in memory).

## BLU midcast payload + weights import + dashed set names (2026-07-19)

Server-source investigation (Catsandboats clone) pinned BLU scaling:
TP touches blue magic ONLY under Chain Affinity / Azure Lore (fTP over
tp150/tp300, spell-side crit/acc riders, TP zeroed, the only SC/MB
path); physical spells roll melee ACC + ATT with a per-spell D cap
that tops out ~330 total skill; magical spells get NOTHING from skill
(INT/MAB carry); debuffs land on dINT + skill(1:1 macc) + MACC gear;
cures are 3xMND+VIT with a 50% potency cap; breaths are currentHP /
divisor. Henrik's category table taken as authoritative for the live
server (hidden CEXI repo confirms the post-75 additions via the wiki).
Payload doc: docs/reference/blu-midcast-import.md -- paste blocks for
Groups AND Weights, one weight profile per group name.

Weights IMPORT shipped as the groups-import sibling: pure transform in
gear/weightimport.lua (reuses groupimport.evalTable -- one sandboxed
loader), applier gearoptim.importNamedWeights (canonStat, named store,
no binding needed), UI = "import..." button + popup in the weights
editor's Points tab (paste -> preview -> overwrite-confirm, the
triggersui pattern). WI1-20.

Field bug "Midcast_STR-VIT": renderSetLines wrote set names as BARE
Lua keys, so a dashed name failed commitSet's parse check on every
commit, and the uncommitted working set haunted the panel until
reload. Fix: renderKey bracket-quotes non-identifier/keyword names,
splice/delete find BOTH key forms (findSetKey), and Delete on a
never-committed working set now DISCARDS it in-session instead of
erroring. SN1-13. 1591 + 170.

## Weights import round 2: Priority tab + export (2026-07-19)

Henrik: "make an import button for the priority system as well, also
an export for both." weightimport gains parsePrio (ORDERED paste:
'Stat' | {'Stat', cap} | {stat=, cap=}) and the two exporters
renderPoints/renderPrio, whose contract is the ROUND TRIP: render
output re-parses to identical data (WX1-5). gearoptim gains
importNamedPrio + read-only allNamedWeights/allNamedPrio. weightsui's
one-off points popup generalized into spec-driven renderImportPopup
({key, help, parse, existing, apply}) + renderExportPopup (per-frame
rebuilt buffer = read-as-copy-source, clipboard button when the
binding has SetClipboardText); both tabs now carry import.../export...
The BLU payload doc gains a Priority-list variant of every profile.
WP1-12, WX1-5. 1608 + 170.

## Selective profile export (2026-07-19)

Henrik: the Profiles-menu export should "open a box, to select what we
want to export" -- Sets / Set equipment (OFF by default, gear doesn't
align between characters) / Triggers / Groups / Modes / Stat weights
(rides Sets, inert without them) / Lockstyles. Ruling honored: no new
readers or writers -- every transform routes through the existing one.
gear/profileexport.lua builds the payloads: equipment-stripped sets =
EMPTY shells via profiles.frameSetsText + setmanager.renderKey (an
empty set is a legal trigger target); trigger filtering =
dispatch.readTriggersRaw -> drop sections -> serializeTriggers (the
wipe-contract serializer); weights = gearoptim's own file renderer
filtered to '<JOB>|' keys. To get that, gearoptim's saveWeights/
loadWeights were split into renderWeightsFileText + parseWeightsData
(one writer, one validating reader; cleaners hoisted) with
renderJobWeightsTextAt / importJobWeightsTextAt on top -- import
re-keys to the imported job name, merges LIVE for the current
character and read-merge-rewrites the file for another. The file
format stays job-export v1 with an optional `weights` key (old
readers ignore it); the import path applies it and annotates the
result; the Shared-exports list now shows [sets+triggers+...] per
file. PX1-16. 1624 + 170.

Field round (2026-07-19): export dialog tried in game -- "works
great". One default flipped on request: Lockstyles now OFF by default
too (lockstyle boxes reference the exporter's own items, same reason
as Set equipment).

## Export dependency gating (2026-07-19)

Henrik asked: a trigger conditioning on a group/mode that isn't
exported, or gated set gear whose Modes are dropped -- what happens?
Answer from the engine: nothing crashes, the reference just goes DEAD
(groupMatch/modeActive return false against nothing; a mode-gated rung
stays inert). So the export form now PREVENTS shipping dead refs
rather than warning. profileexport.analyzeJob (one disk probe at form
open) reports { trigModes, trigGroups, setModes } via pure triggerRefs
+ setsUseModes. The form disables Triggers while it uses Modes/Groups
you've unticked ("triggers use Modes -- include Modes to export them")
and disables Set equipment when the gear is Mode-gated and Modes are
off. Blocked rows render inert without mutating the remembered tick
(restore the dep, the choice comes back); the export reads f._eff, the
dependency-gated effective values. PX17-21. 1648 + 170.

## Export dep gating round 2: trigger->set (2026-07-19)

Henrik: triggers can have empty conditions, so the dependency isn't
only groups/modes -- an empty-condition rule still points at a SET.
Confirmed group/mode detection already covers when + whenAny (the
"only a group/mode condition" case = PX17/18). Added the trigger->set
dependency: triggerRefs now reports .sets (a rule with a named `set`
action; inline-equip rules carry none). The form disables Triggers
when Sets is unticked and any rule names a set -- set NAMES ride the
empty shells, so ticking Sets (gear or not) satisfies it. trigNeeds
lists Sets first, then Modes/Groups. PX18b/19b/19c. 1651 + 170.

## Teleports menu revamp: cascades + new travel items (2026-07-19)

Henrik: too many rows in the Teleports dropdown. New shape, three
tiers: (1) top strip = instant/panic options, now ALL ownedOnly --
show what you can actually reach for, otherwise nothing -- Instant
Warp, Warp Ring, Provenance, Chocobo, plus NEW Shadow Lord Shirt
(/dl shirt, Body slot, 30s delay, teleports to Castle Zvahl Keep;
server-gated on having visited) and NEW Instant Retrace scroll
(/dl ir, id 5428, usable from Inventory, back to your Campaign
nation -- SCROLL_* generalized into a SCROLLS table). (2) Cascading
submenus "Teleport Earrings" and "Teleport Rings" (BeginMenu,
floatgear-proven; flat-section fallback when unbound). The six crag
rings (Holla/Dem/Mea/Yhoat/Altep/Vahzl, Ring2, same 30s delay) join
TELEPORTS with a slot field, so /dl t holla just works; rows carry
grp ear|ring|xp (the old xp flag is gone). Unowned earrings/rings
still list dim INSIDE the submenus -- the reminder rows moved, not
died. (3) Exp rings as before, minus the "only the ones you own are
listed" hint; added the two DEDICATION rings CatsEyeXI actually
implements as exp: Expertise (+75%) and Anniversary (+100%, 15s
equip delay -> per-entry wait override). Trizek/Endorsement/
Facility/Capacity/Vocation grant COMMITMENT (capacity points, not
exp on this server) and were deliberately left out. 1651 + 170.

## Weights import split local/shared; Groups import to top buttons (2026-07-20)

Henrik: the Weights import... should feed THE SET, not the named
store. Split in two. import... (both tabs) is now LOCAL: paste ONE
nameless table -- `{ Accuracy = 12, BlueMagicSkill = { 3, 40 } }` /
`{ 'MACC', { 'INT', 60 } }` -- and it becomes the bound set's tuning
directly (weightimport.parseLocal/parsePrioLocal -> gearoptim.
importSetWeights/importSetPrio, replace semantics behind the same
revert snapshot as copy from...). A single `Name =` wrapper is
tolerated and IGNORED; two+ named tables are REFUSED with a pointer
to the shared flow. New manage shared... button (both tabs) opens
the named store's window: list + red-confirm delete, create from
the current set, the old bulk `Name = {...}` import (several at
once, overwrite-confirmed) and the export text -- export... moved
in there since it renders that same store. On Triggers > Groups the
two bottom collapsible sections ("Import Lua Table(s)", "Auto-import
from my Lua file") became two top-row buttons: Import opens the
paste window (same flow), Auto-Import runs the Lua-file scan
immediately and opens the tick-list picker (Rescan inside). All
functions kept, only the surfaces moved. LW1-12/LP1-7. 1670 + 170.

## Bare toggles persist; mode boxes get a delete x (2026-07-20)

Henrik on Mindie BLU: created a simple toggle mode, Commit worked,
but it never showed in the Modes list. Root cause: a toggle with no
keybind stored NO definition at all ("needs no definition") -- only
a rule referencing the mode made it visible, and all three layers
conspired to drop an empty def (the builder wrote nil, dispatch.
serializeTriggers skipped `#bits == 0`, triggermodel.fromRaw kept a
def only when it had values or a bind). Fixed in all three: a bare
toggle is now an EXPLICIT `[name] = {}` definition that survives
the whole wipe contract (engine v72; TM20-22 pin serialize -> load
-> fromRaw -> re-serialize byte-stable). Second ask: every mode box
now carries an x beside edit -- delete without opening the editor.
Same flow as the editor's Delete mode (unreferenced = delete +
commit now; referenced = the reference window with its one-click
cleanup) behind the red second-click confirm, because the delete
writes the file immediately. 1673 + 170.

## Set rename-everywhere; Sets row widened, Lock dropped (2026-07-20)

Henrik: rename sets so it propagates to triggers and everything --
"I don't want to look for everywhere it is used." New Rename button
on the Sets controls row opens a popup; one click renames the set
in every store: (1) the sets file re-keys the block in place
(setmanager.renameSetText -- content untouched, bare or bracket
form, dashed new names bracket-quote, collision/unknown refuse;
renameSet wraps it in the commit rails), (2) every trigger rule
whose set action names it -- string or multi-set list, all handler
sections incl. Default's mode overlays -- rewrites and commits live
(triggersui.renameSetRefs; EXACT match, case-drifted refs were
already broken and stay visibly broken), (3) the per-set weight
stores move (gearoptim.renameSetKey: points/slots/prio/mode + undo
snapshots, live binding follows), (4) the panel follows and sets
hot-swap like Commit. A never-committed set renames panel-only with
a status note. Row cleanup while at it: set picker 150->240, name
box 104->200 (dead space, clipped names), and the Lock checkbox is
GONE (applySetLock deleted) -- that workflow belongs to Equipped's
"Lock when equipped". SN14-19 / RK1-6 / RS0-7. 1693 + 170.

## Auto-Build All + auto-build on weights-bearing import (2026-07-20)

Henrik: exports deliberately carry stat weights + EMPTY set shells
(equipment/lockstyles are too individual) -- so when a profile
import lands with weights, AUTO BUILD the sets immediately: the
importer's own gear fills the shells. New gearui.autoBuildAll(job,
level): every dynamic set of the job with per-set weights (points
or priority) is loaded, bound, autoBuilt and committed; sets whose
weights score nothing keep their contents (no empty commit); the
panel returns to the set it showed. Surfaced twice: (1) a new
"Auto-Build All" button at the end of the Sets controls row (hover:
"Will auto-build all gear-sets with stat weights set."), and (2)
the Profiles menu's import flow -- profilesmenu.configure now
MERGES deps and takes an afterImport hook; a weights-bearing job
import (wn > 0) calls it and appends the result to the menu
message. The hook only builds when the import landed on THIS
character's active profile as the CURRENT job (candidate pools are
this job's); any other target gets a pointer to the button instead.
1693 + 170 (smoke pins the late-wiring load path).

## Profiles menu: real resizable window + export delete (2026-07-20)

Henrik: wider, resizable, and a delete for shared exports. The
Profiles popup became a REAL window (dlac Profiles, 980x540 default,
user-resizable 700x360..1600x1200, [X] closes via ui._profMenuOpen)
-- gearui now calls pmenu.render() AFTER its main End, beside
host.renderWindows, since no popup scope is shared anymore. The
tree layout derives W from GetWindowWidth (safe in a USER-sized
window; the old fixed-800 rule guarded the AlwaysAutoResize popup's
feedback loop) and the body child fills the window, reserving a
bottom strip when a status message shows. Every Shared exports row
gets an x beside import: red second-click confirm, deletes the
FILE from dlac-exports (profiles.deleteExport -- path-traversal
guarded; imported copies stay), re-lists. 1693 + 170.

## Sets row compacted: Manage menu; import weights hardened (2026-07-20)

Henrik round 2 on compactness: the Sets top row is now picker +
Manage... menu (New / Rename / Delete / Copy from / Delete static
-- last one only when statics exist) + Stats. New opens a name
popup (Enter creates + starts editing); Delete asks "Are you sure
you want to delete this set?"; Copy from opens a two-list window
(dynamic sources beside legacy statics -- doCopyFromDynamic is the
new dynamic twin, same FULL-REPLACE + Replace-confirm contract);
Delete static moved into its own pick-to-arm popup. Commit /
Weights / Auto-Build All moved under the Build-as-lv.75 checkbox;
the free-text new-set box, the Profile: line and the Copy from /
Delete static row are gone.

Import investigation (friend's weights didn't follow): the
mechanism itself verified CLEAN headless against Henrik's exact
export file (parse -> importJobWeightsTextAt -> perSetKeys -> bound
weights all land; scratchpad repro). Three SILENT failure holes
fixed in importJobWeightsTextAt: (1) current-character detection is
belt-and-braces now -- path-string compare OR profiles.
currentCharFolder -- because taking the file branch for the LIVE
character wrote a file the next GUI save clobbered from import-less
stores (the weights evaporate exactly as reported); (2) a live
merge whose gearweights.lua save fails now returns a WARNING that
the Profiles menu shows ([!] beside the set count) instead of dying
silently on the next reload; (3) the other-character branch creates
the target dlac\ folder first (io.open never mkdirs). PX16b/c pin
the loud-warning contract. 1695 + 170.

## Import from text + collision overwrite/keep (2026-07-20)

Henrik: importing should be easier -- paste the file instead of the
dlac-exports file dance, and a name collision should offer
OVERWRITE (optionally keeping the old job under a new name) instead
of "change the name" ping-pong. profiles.importJobMeta is the new
shared core (parse-checked payloads; opts.overwrite replaces;
opts.backupName renames the old job first via renameJobAt -- a
dormant archive in the same profile; without it the old files go
through deleteJobAt's verified backups\deleted-jobs\ copies; third
return isCollision lets callers offer the choice). importJobFile is
now a thin read+parse shell. Profiles menu: "Import from text..."
button beside the always-shown Shared exports header opens a form
with a multiline paste box -- parsed live, shows what the paste
carries, auto-fills the As-name from the export's job; both import
forms share one commit path (meta -> importJobMeta -> weights leg
-> auto-build hook) and both get the collision controls: Overwrite
checkbox + optional "keep the old one, renamed to" input, validated
live (bad/taken/same backup names block). Ashita has no OS
file-browse dialog to bind, so the paste route IS the browse
substitute. 1695 + 170.

## Export "view text" + Copy all (2026-07-20)

Henrik: sending an export should not require hunting the file down.
Every Shared exports row gets a "view text" button -> a self-
contained viewer (own branch, none of the form machinery) showing
the whole file in a copy-source text box with "Copy all to
clipboard" (SetClipboardText, probed like weightsui's; no-clipboard
builds get a select-and-Ctrl+C hint). The receiving side is
Import from text..., so a share is now copy -> paste -> done.
profiles.readExportRaw is the traversal-guarded reader. 1695 + 170.

## Auto-Build All: one summary, one hot-swap (2026-07-20)

Henrik: the sweep spammed one "sets hot-swapped" chat line per set
(every commitCurrentSet queued its own /dl sets reload). commit-
CurrentSet grows a quiet flag (no per-set status, no per-set reload;
returns ok) and autoBuildAll commits quietly, queues ONE /dl sets
reload after the loop and reports one summary -- built / scored-
nothing / failed-to-commit / no-weights counts -- in the Sets status
and the import-hook note alike. 1695 + 170.

## AutoAmmo -- the Ammo-slot automation (2026-07-20)

Henrik (for his COR friend): LuaAshitacast is "HORRENDOUS" when ammo
runs out -- it never re-equips, and a stranded one-of super-bullet
(Animikii) gets eaten by the next shot. Root cause verified in LAC
source: purely event-driven, NO fallback (a set naming unowned ammo
silently equips nothing), though 'remove' is a first-class unequip.
Server research (stable branch, field promotion pending): Leaden
Salute 218 / Wildfire 220 / Trueflight 217 are the ONLY ranged WS
that consume no ammo (magical handler, no ammo code -- the sql type
column canNOT discriminate); Quick Draw consumes a card, never the
worn bullet, but HARD-REQUIRES a Marksmanship ammo equipped; empty
gun = shot blocked server-side (which makes 'remove' a real guard);
Unlimited Shot = effect 115. Build: ammostate.lua (ammowatch, GUI =
ui/ammoui.lua under Automations; enabled PERSISTS -- a protection
system must not disarm at login; jobs map = blast radius) + engine
v73 overlay on EVERY event below pins: count-verified picks (first
LAC-state bag counter -- per-second cache, FRESH on action events,
because a stale count at Preshot is exactly how the special gets
eaten), per-context ladders (ranged / WS / the three free WS /
Quick Draw / Unlimited Shot windows), the Default protection sweep
+ empty-slot reload (stands down for fish bait and for set-planned
ammo the player actually owns), 'remove' ladder end. Pure core
M.resolveAmmoPlan; docs/design/auto-ammo.md holds the decision
table + field-test checklist. +41 checks (AM/AW), +4 smoke.

## AutoAmmo field round 1: columns, level sort, the CW E-Box (2026-07-20)

Henrik pre-play polish, three asks. (1) Fixed shared column offsets
so the two panel lists read as one table (name/qty both lists; flag
ticks vs skill/Lv/+Add; the space right of + Add stays RESERVED).
(2) "Sort by level" on the priority list -- one-shot best-first,
stable ties; entries persist `level` now, the sorter backfills
pre-level entries from the catalog. (3) E-Box counts + fetch, the
FIRST gamemode.get() consumer: Crystal Warriors ONLY (affirmative
'CW' -- Wings/ACE/unknown see nothing at all; the server's LOCKED
is the second gate). feature/eboxammo.lua reimplements trove's ebox
0x1A4 wire format (helmwatch precedent -- no trove dependency):
GET_CATEGORY(ahCat 15 Ammunition) streams every boxed ammo count in
ONE request; WITHDRAW/ACK surfaces the server's refusal words; ITEM
staging only while OUR request is pending (0x1A4 is a party line).
Parsing is string.byte only -- the whole wire path runs headless
(EB1-EB8b). Mid-round addition: proximity warning without targeting
-- E-Boxes are ordinary zone NPCs named "Ephemeral Box" (Bastok
Mines sample id 17737730 = plain zone-NPC slot), scanned by NAME
with helmwatch's squared-distance conventions; 6-yalm warn
threshold is the trade-range convention, unverified (design doc
S:7). Engine untouched all round. +31 checks, +6 smoke.

## AutoAmmo field round 2: verified live; per-job config (2026-07-20)

Henrik verified round 1 live on his RNG ("so far it works") and
pinned the E-Box interaction range: 5 yalms (BOX_RANGE, test EB9;
the trade-range guess of 6 lasted one round). Round-2 asks, all
shipped: fetch buttons go DEAD when they cannot work -- dim red out
of box range, grey for empty-box/busy, reason in the tooltip; the
qty input widened to 120px (triple digits beside the steppers);
new "Fetch up to" button tops you up -- reads the equippable-bag
count and fetches the difference so you land at the typed number
(box-clamped like everything; plain Fetch already clamped). The
big one: ammostate fmt 2 = PER-JOB sections ("all jobs can't use
all ammos") -- every job keeps its OWN priority list and its OWN
persisted on/off; the panel edits the current job's section (a dim
"also configured:" line shows the rest), the engine (v74) resolves
against as.jobs[<main job>] only, and fmt-1 files migrate on first
panel open (every ticked job gets a copy; a list no job owned is
adopted by the first job in -- nothing lost, tests AW18-19c).
Legacy fmt-1 stays engine-readable until migrated. resolveAmmoPlan
untouched. Suites 1802 + 176.

## Sets: Equip & Lock for Incursion T3 (2026-07-20)

Incursion T3 locks your equipment server-side on entry, so the play is:
land a full set, then stop the engine from fighting the server lock.
New engine command `/dl lock set <name>` (v75): wears the COMMITTED set
once -- bracketed ClearBuffer/ProcessBuffer, the PetAction tick's
lesson, or the equips evaporate -- then locks ALL 16 slots; stale locks
are cleared first (they would strip their slots out of the very equip).
The Sets tab grows an "Equip & Lock" button on the action row: it sends
that one command and reads the engine's lock mirror, flipping to
"Unlock" (= /dl lock all off) when all 16 slots are locked (~1s mirror
throttle; partial Equipped-tab locks do NOT flip it). Uncommitted
working-set edits are not equipped -- the status line says so when the
set is dirty. Locks stay session-only by their existing design, so a
Reload LAC also releases. Tests LK1-9 pin setLock('all') + the
equipResolved strip. Suites 1814 + 176.

## The central entity watcher (2026-07-20)

Box detection field-CONFIRMED (round 6), and Henrik generalized it
on the spot: "a point that scans all loaded entities, where you can
apply for things you look for and who is looking for it, [keeping]
track of the current distances to the active monitored entities."
lib/entwatch.lua is exactly that: watch(who, name [, cb]) registers
the interest; ONE full-array sweep (2s) serves every active watch;
tracked matches get 0.25s distance refreshes with per-index name
re-verification (slot reuse evicts -- and evictions NOTIFY, or a
despawn between sweeps would never fire the callback); callbacks
ride match-SET changes; callback-less watches are demand-windowed
(15s past the last ask -- an idle client does zero work); poke() =
the rescan cache-bust. Every idiom the AutoAmmo scan rounds paid
for (trimmed+ci names, rendered bit 0x200 signed-u32, GetRawEntity
not the dead GetEntity(i), the full 0x000-0x8FF range) lives THERE
now, once. eboxammo.boxDistance shrank to a three-line consumer;
/dl ebox additionally prints the watcher's registry view. Also this
arc: Nexus Cape joined the Teleports menu under the Whistle
(/dl nexus, party-leader teleport, server-gated; pushed to origin
per Henrik). Tests EW1-EW10 + smoke S139c/d. Suites 1837 + 178.

## ADR 0010 scoped within the set (2026-07-20)

Field case: a worn Rimestone (Lv60 stat stick) kept a set's Rouser
(Lv20 BRD instrument) out of Range forever -- the trinket/ranged
keep-higher-Level safeguard was acting globally. Henrik's ruling:
the Level contest is a WITHIN-SET rule; it arbitrates a Range+Ammo
pair the plan itself names, and a merely-WORN trinket never defends
Range from outside the plan. Engine v78: trinketWornDisplace adds
Ammo='remove' (LAC's native unequip) when a set names Range over a
worn trinket -- equipping the weapon alone would just be
server-stripped, the original flap -- unless Ammo is locked or
pin-reserved (the user's explicit word keeps the old mirror). The
other outside writer, MP-EQUIP, is filtered at the source:
mpStageEligible drops battery candidates whose RSlot reserves an
occupied (planned or worn) slot, which also stops a doomed
biggest-gain pick from starving the one-per-dispatch stage. Within
a set nothing changes, and every other reserved-slot mirror (Tunic
reserves Head) is untouched. Tests TR11-15 / MS9-10 / TB1-7.
Suites 1868 + 178.

## The target condition: who the action is aimed at (2026-07-20)

Henrik's case: waltzes (and kin) scale off the TARGET's VIT beside
your CHR -- a self-waltz wants VIT+CHR together, waltzing someone
else keeps the plain CHR set. The trigger vocabulary had no way to
say "aimed at me". Engine v81 adds `target`, v1 value 'Self': live
it compares gData.GetActionTarget().Index (LAC keeps the outgoing
action packet's target index on PlayerAction for Spell/Ability/
Item/WS/Ranged, set before Precast fires) against my own party
index, once per dispatch (ctx.targetSelf, tri-state -- unknown
matches NOTHING, the buff-cache rule, so Default-handler rules and
failed reads never fire a target rule). Tier 55: a self-refined
rule overlays its base name (50) / group (45) / contains (40) rule
with no hand priority and stays under the Automations band (60).
GUI: a `target` dropdown on Precast/Midcast/Ability -- one value
today, deliberately a list so future answers (party member, enemy,
NPC) extend the dropdown, not the vocabulary. /dl why tags a
self-aimed action '@self'. Tests TG1-16. Suites 1891 + 178.

## Iridescence: the catalog sweep, +3 tier, and the universals ladder (2026-07-21)

Henrik's question -- "we've inventoried a lot now; what carries
Iridescence that the automation doesn't know?" -- answered from the
shipped catalog itself (the stat the ADR 0004 crawl work paid for):
exactly 15 carriers. The old UNIVERSAL fallback list knew 4, and one
of those was wrong -- Claustrum carries NO Iridescence on live (all
six relic stages: accuracy only, an early guess now removed). New to
the list: the Incursion T3 job weapons -- Inanna (DRK/BLM), Keraunos
(BLM/SCH) and Gridarvor (SMN) at the NEW +3 tier, Claritas (RDM),
Izuna (NIN), Coeus (SCH), Kaladanda (BLM) at +2 -- plus Arcanium +1
(BLM/SCH Lv50, +2), Nightingale (BRD Lv70, +2), Ephemeron (RDM/BRD
Lv75, +1) and the Lv75 relic staves Laevateinn/Tupsimati (+3).
Local server repo is behind live for these (Claritas is still
'sanus_ensis' there); the catalog scrape is the authority, as
designed.

Two mechanics landed with the data. (1) CW-only weapons (the
Incursion lines, Foreshadow +1 included) are display-gated on the
AFFIRMATIVE gamemode.get() == 'CW' -- hidden on Wings/ACE and on
nil-unknown alike, per architecture.md's gating rule; the ownership
scan never gates (a non-CW character simply never owns them).
(2) Engine v82 + manifest fmt 10: the GUI writes `universals`, a
preference-ordered ladder of EVERY owned universal (tier desc,
job-specific over the Chatoyant/Iridal fallbacks) -- resolveStaff
takes the first rung usable at the live level, so an Incursion-
synced character falls through a parked Lv75 Inanna to Foreshadow +1
Lv50 instead of losing the universal outright (the single-pick
manifest could only go all or nothing). virtualMinLevel counts every
rung, so the set marker adopts at the LOWEST universal's level. The
coverage light grows a 5th step (universal +3) and the detail view a
+3 column. Old manifests read exactly as before; fmtver forces the
self-heal rescan. Tests VL8-13, S166b. Suites 1897 + 179.

**Correction, same day (Henrik's ruling):** the id-block inference
overreached -- Gridarvor, Coeus and Kaladanda are "Oboro weapons",
customs available to ALL game modes, so their cw flags came off
(they'd have been invisible on Wings/ACE panels while fully
functional). Arcanium +1 the inference got right: CW-only,
confirmed. CW-flagged now = exactly the Incursion lines: Foreshadow
+1, Arcanium +1, Claritas, Izuna, Inanna, Keraunos.

**Addendum (same day):** non-CW modes get a "Show Crystal Warrior
gear" checkbox at the bottom of the AutoIridescence detail
(session-only peek; Henrik: let them see what they're missing).
The affirmative-CW gate stays the default; the checkbox only widens
the DISPLAY filter, never the scan.

**Addendum 2 (same day, Henrik's catch):** the relics were adopted by
NAME, and 'Laevateinn' is half a dozen catalog records (every retail
upgrade stage) of which only the Lv75 stage -- 18994 (Tupsimati:
18990) -- carries Iridescence on live. The single-winner byName
lookup could land on the base stage and test ownership of an id
nobody holds. UNIVERSAL entries can now PIN an exact catalog id;
ownedRec/usableRec/autoItemLine resolve pinned entries through
lookupById (newly injected into the automations deps) and reject a
name-resolved record with the wrong id -- conservative: a missing
pin lookup never false-adopts. Smoke pins the trap: byName aimed at
the base, the owned Lv75 stage adopted anyway (S166-S166c).

## Session "the banded ladder -- maxmp v2 end to end" (2026-07-20 evening -> 07-21, engine v76..v95)

The maxmp marathon: one evening of field-debugging the v1 per-dispatch
engine, one overnight autonomous build of Henrik's redesign, one morning
of field rounds tuning it to settled. Full detail (architecture, rulings
ledger, failure museum) lives in docs/design/maxmp-mode.md -- THE
reference for revisiting; this entry is the timeline.

**Evening (v76-v87, the v1 endgame).** Staged one-battery-per-dispatch
movement (v76: the all-at-once release was an accounting bug -- N
slot-local holds mass-released drop max by the SUM and the clamp eats the
difference). Release notes name the incoming piece (v77) after an 8-second
identical-decision stall exposed LAC's silent drop of un-locatable gear;
the stall's true root landed later as the equippable-NOW manifest filter
(round 3: a STORED Radiant Lantern froze the whole equip queue). Held
batteries could not see their own upgrades (v80); the ear-shuffle veto
(v83). Then the deep one: GetMPMax is UNRELIABLE in both directions across
gear churn (field: engine 975/1052 vs bar 975/975; LAC's .MaxMP is the
same call) -- v86 window-clamped it, v87 made fullness exact (floored
party MP% == 100 is the ONLY exact signal) and low-biased the estimate,
killing a spectacular equip<->release oscillation caught in a /lac debug
log. Detours retracted the same night: a wardrobe-availability theory
(server hardcodes all wardrobe bits -- char_status.cpp 0x7B) and a
missing-gear-entry theory (the entry exists under the client's shortened
name).

**Overnight (v88-v89, the redesign).** Henrik: "stop with dynamic
equipping -- make it orderly and calculated." The banded ladder:
precomputed absolute current-MP thresholds chained from an anchored TOTAL,
tick-margined both directions (unequip never caps an incoming tick;
re-equip EARLY so the tick lands in the headroom), structural hysteresis,
batch swaps, CURRENT MP the only live read. feature/mpbands.lua pure core
+ measured recovery ticks (never trait tables); /dl plan renders the SAME
context the engine executes -- the plan IS the behavior, which then
cracked every remaining field bug. Night addendum: Refresh > least mp
diff; augments always in the totals (fmt 12, augments.ownedAugStats).

**Morning (v90-v95, field-settling).** Multi-rung bands (v90) RETIRED by
ruling (v92): equipping refresh gear is the IDLE SET's job -- the engine
only ADAPTS TO the potential refresh, in the ordering (rfDelta asc, diff
asc); the experiment also deadlocked (worn mid-rungs depress the pool
below big-diff re-equip triggers -> the reachability clamp, onAt =
min(lastMax - tick, endMax)). Sticky pairs (v93/v94: pair pieces never
relocate; the same-dispatch resolved plan is the only lag-free claim --
worn reads lag a dispatch). Pair HOMES (fmt 13): ear/ring ladders re-home
to the idle set's declared positions (detected from the Default rule
matching exactly status=Idle; the panel picker ALWAYS overrides).
Refresh baseline fixed to the POTENTIAL refresh -- max across
trigger-reachable sets, not the min-MP piece's (v95: every [refresh-cost]
tag had vanished and a deep plain band displaced Clr. Bliaut +1 at MP
~800); margin floors at MIN_TICK 5 (measured tick 1 was HONEST -- unbuffed
gear refresh). MaxMP GRADUATED to the Automations GUI (hidden ruling
rescinded) with a live ON/OFF switch (modestate mirror + explicit
command), idle-set picker, and the Teleports quick-menu switch.
Field-confirmed: "now it works, awesome" -- refresh ordering correct,
Loquacious holding ear2. All pushed to origin/main.

## The Arbiter, step 1: claim registry + arbstate + rank-ordered application (2026-07-21, engine v97)

**Theme:** the first of ADR 0012's four incremental steps. Give the six gear
claimants (Pins, AutoAmmo, MaxMP, Craft, HELM, Fishing) ONE user-orderable
priority list, replacing the precedence that lived in three separately-encoded
constructs -- the hardcoded overlay application sequence at the bottom of
`M.dispatch`, the per-slot `elseif` chain in `equipResolved`, and `POST_ORDER`.

**Landed (this step only -- the migration is deliberately incremental so a
regression has one suspect, not six):**
- A **claim registry** in `M.dispatch`: the discrete overlays (Pins, AutoAmmo,
  Craft, HELM, Fishing) are collected as `claims`, and the old hardcoded
  `craft > HELM > fish > AutoAmmo > pin` apply sequence is replaced by ONE loop
  walking the live rank order LOW->HIGH (overlay last-writer-wins == the rank
  walk's first-wins). At default order the applied sequence is byte-identical to
  before (craft/HELM/fish are mutually exclusive via the newest-armed
  arbitration, so their internal reorder is moot).
- The **`arbstate` Statefile** (`return { order = {...} }`): one strict draggable
  list per character, hand-editable this step (the GUI writer is step 2). Read
  through the shared `ensureStateFile` reader -- 1s throttle, torn/missing =
  built-in default. `M.arbOrder` sanitizes: unknown rows dropped, missing known
  rows appended in default order, so a partial-but-parseable file still yields a
  complete strict order.
- **Default order: Pins > Locks (veto placeholder -- semantics unchanged this
  step) > AutoAmmo > MaxMP > Craft > HELM > Fishing > Triggers floor.** Reproduces
  today's winners with exactly ONE deliberate change: **AutoAmmo's named
  projectile beats a MaxMP battery in Ammo** (a shooting job must never fire its
  stat-trinket ammo -- Henrik's ADR 0012 ruling).
- **MaxMP stays WOVEN** through the resolves (not a discrete overlay), but now
  consults the rank: `M.arbCededAbove` computes the slots any claimant ranked
  above MaxMP has won this dispatch, passed as `ctx.mpCeded`; the per-slot MP
  branch and the mp-stage pass both skip a ceded slot. So Ammo is ceded to
  AutoAmmo, while batteries still override Craft/HELM/Fishing armor (both ranked
  BELOW MaxMP -- the previously-silent behavior, now explicit and orderable). A
  hand-edited reorder that moves MaxMP above AutoAmmo un-cedes Ammo and the
  battery wins again, no LAC reload.
- **Pure resolve core** `M.arbResolve(claims, order, floor) -> winners, by` (the
  seam the acceptance criteria pin): walk the order top-down, first claimant with
  an opinion on the slot wins; 'Triggers' resolves to the floor. Headless tests
  AR* (order-pin, sanitizer, resolve, ceding) + ARE* (the AutoAmmo-over-battery
  change wired through `equipResolved` with `M.mpBands` stubbed).
- Read-only **`/dl prio`** prints the live rank + each claimant's claim status --
  the tracer's demo surface until the GUI Priority section lands (step 2). Added
  to the command WHITELIST (the v46 lesson).

**Deferred to later ADR 0012 steps (not this issue):** the Automations-tab
Priority drag UI (step 2); folding Locks from a placeholder row into a real
draggable veto (step 3); collapsing the remaining woven-MaxMP scaffolding and the
hardcoded arms, plus `/dl why` per-slot claimant attribution (step 4).

## The Arbiter, step 1.5: activities co-claim -- drop the newest-armed exclusivity (2026-07-21, engine v98)

**Theme:** the first field round on step 1 falsified a claim-side rule ADR 0012
had carried forward unquestioned. The **newest-armed (`at` stamp) exclusivity**
among Craft/HELM/Fishing -- whichever switch was enabled most recently stood the
other two down WHOLE (`at` compare inline in `M.dispatch`, generalized three-way
in v64) -- was the pre-Arbiter conflict resolver. With rank arbitration now
settling every slot, it was redundant, and it actively defeated per-slot
composition.

**The field case that drove the ruling (PUP), now a verbatim test (AR10):** the
idle floor names Range = Animator. Fishing armed put Lu Shang's in Range. Then
arming HELM stood Fishing down wholesale and the Animator came back to Range --
even though HELM never claims weapons, Range, rings or Ammo. The player wanted
both: HELM's seven armor slots AND the fishing rod still in Range.

**Landed:**
- The `at`-stamp exclusivity block is deleted from BOTH sites -- the `M.dispatch`
  arm and the `/dl prio` status read. `craftOn`/`helmOn`/`fishOn` now stay exactly
  what each feature's own gates return; all three overlays (`cEquip`/`hEquip`/
  `fEquip`) are built whenever armed and enter `claims` as separate rows.
- Nothing else moved: the rank-ordered apply loop already settled overlapping
  slots per slot (last-writer-wins in rank order == the Arbiter's first-wins
  walk), so co-claim needed only the exclusivity's removal, not a new mechanism.
  Each feature's own gates are untouched (HELM/Fishing Engaged/Dead stand-asides +
  Default-only, Craft Default-only, AutoAmmo's stand-down while fishing is live --
  now MORE consistently correct since `fishOn` no longer gets flipped off by a
  newer craft/helm arm, MaxMP's `ctx.mpCeded` rank consult).
- **Consequence, accepted deliberately (Henrik's ruling):** arming no longer
  switches activities. Walking from the bench to the pond means disarming Craft
  yourself (quick menu / panel). `/dl prio` now shows every concurrent claimant ON.
- Headless tests AR8/AR9 (two- and three-way co-claim: each keeps its exclusive
  slot, rank settles the shared one) + AR10 (the PUP case verbatim, incl. the
  Animator returning only when Fishing itself is disarmed). The exclusivity lived
  inline in `M.dispatch`, never at a pure seam, so there was no old exclusivity-pin
  test to invert -- these ADD the co-claim law that replaced it. 2096 headless +
  187 smoke green.

**Dead end recorded:** newest-armed exclusivity as a *claim-side* rule. It made
sense when it was the ONLY arbitration (v59/v64, pre-Arbiter); carried into the
Arbiter it was a second, conflicting decision point that pulled whole activities
off the board. The Arbiter's rank is the single settling law now -- claimants
decide WHETHER to claim, the rank decides WHO WINS each slot, and never again does
a claimant reach across and silence a peer wholesale.

> **2026-07-24 (ADR 0017):** one-at-a-time returned for the four idle hobbies --
> but at the **enable toggle** (`feature/idleexcl.lua`), not this claim-side rule.
> Arming a hobby while another is active is *refused* (lock-while-active), so only
> one is ever armed and the engine's co-claim never sees a conflict. This claim-side
> dead end stays dead; the new seam never reaches the claim layer. See the entry below.

## The Arbiter, step 3: locks become the draggable veto row (2026-07-21, engine v99)

**Theme:** locks were the last piece of gear-precedence encoded OUTSIDE the rank
list. Before this step Locks was a placeholder row in the arbstate order that did
nothing; the real veto lived as an **absolute per-slot strip** at the top of every
`equipResolved` (`M.locks[slot] == true -> hold as worn`), plus MaxMP's own
hardcoded `M.locks` skips in the band build and the mp-stage, plus the hidden
"pins never check locks" law the ADR wanted to make visible. Step 3 folds all of
it into the registry: **Locks is a rank position** -- a claim ranked ABOVE it
punches through a locked slot, one ranked BELOW stops.

**The mechanism (no big rewrite -- the rank already existed, only the veto moved
onto it):**
- `equipResolved(s, ctx, respectLocks)` gained a third arg. `nil == true`, so the
  Triggers floor, the immediate-equip paths (`/dl lock set`, the LK tests) all keep
  the old absolute-veto behavior with no change. The dispatch apply loop passes the
  per-claimant answer from `layerRespectsLocks(name)` = *is this claimant ranked
  below Locks?* Below -> the strip runs (stops); above -> the strip is skipped for
  its slots (punches through).
- Woven MaxMP consults its OWN rank vs Locks, carried on `ctx.mpRespectLocks`
  (MaxMP runs inside every `equipResolved` call and the band build, so it can't ride
  a single layer's flag). The two hardcoded `M.locks` skips -- the `mpBands` band
  build and the mp-stage uncovered-slot placement -- now gate on that flag instead of
  the raw lock table: at default (MaxMP below Locks) a locked slot still gets no band,
  exactly as before; drag MaxMP above Locks and its batteries punch through.
- The pure model `M.arbResolve` gained the veto too: callers pass `Locks` in
  `claims` as a veto table (`M.arbLockClaim` -> the `M.LOCK_HELD` sentinel), and the
  existing top-down rank walk does the rest -- a claim above Locks wins the slot
  first, one below never reaches it. Same law, two representations (woven flags live,
  a claim row in the model), pinned to agree by the tests.

**Default order Pins > Locks > ... reproduces today's field behavior:** pins punch
through locks, every other claimant + the Triggers floor stop at them. Locks dragged
to the TOP = an absolute veto including pins; dragged lower = everyone above punches
through, everyone below stops.

**UI:** the Locks row dropped out of `arbwatch.M.FIXED` (only the Triggers floor
stays fixed), so `moveClaimant` now reorders it and `priorityui` renders it draggable
-- still in the floor colour (`COL_FLOOR`) so the veto never reads as an ordinary
claimant. `/dl lock` and the Sets tab's "Equip & Lock" are untouched at defaults.

**Tests:** LV0-7 (the pure position semantics through `arbResolve` + the live
`respectLocks` / `ctx.mpRespectLocks` wiring through `equipResolved` with `mpBands`
stubbed), AB5/AB5a + S199b/c (the Locks row now drags), S197 inverted (Locks
draggable, only Triggers fixed). 2132 headless + 199 smoke green. Engine v99,
addon.version 2026.07.21c.

**Deferred to step 4 (not this issue):** collapsing the remaining woven-MaxMP
scaffolding (`ctx.mpCeded` / `ctx.mpRespectLocks` consulted from inside other
claimants' resolves) into a discrete stage, and `/dl why` per-slot claimant + veto
attribution. The live apply still runs the reverse-rank overlay loop, not
`arbResolve`; that unification is step 4's job.

## The Arbiter, step 4: collapse hardcoded arms; /dl why names claimants (2026-07-21, engine v100)

**Theme:** make the registry the ONLY precedence authority a reader has to consult,
and let the pure resolve that DECIDES also EXPLAIN. Two deliverables from step 3's
deferred list, plus the doc that lets the next claimant (AutoAcc) join without an
engine change.

**MaxMP becomes a registered CLAIM (the scaffolding retires).** Through step 3 MaxMP
was woven-only: it had a rank *row* but no claim *table*, so its precedence lived in
`ctx.mpCeded` â€” a rank-consult computed from `arbCededAbove` and read from *inside
every other claimant's* `equipResolved`. Step 4 gives it a real registry entry:
`mpClaimFor(ctx)` turns the banded ladder's per-slot target into a claim table
(`{ [Slot] = rungName }`) and `M.dispatch` registers `claims['MaxMP'] = mpClaim`
before computing `ctx.mpCeded` from that same `claims`. `arbCededAbove` excludes
MaxMP's own row, so the ceded set is byte-identical â€” **no behavior change**, but the
*precedence* now flows from one registry rather than woven scaffolding. Only MaxMP's
EQUIP stays woven (hold/release/upgrade, sticky pairs, movement yield are within-set
resolution, deliberately outside the Arbiter per ADR 0012). `ctx.mpRespectLocks` is
now computed *before* `mpClaimFor` so the claim and the woven `mpBands` agree on which
locked slots MaxMP dresses.

**`/dl why` names the winner + rank per slot.** The apply loop already collected the
discrete claims; step 4 also merges the trigger-overlay result into `floorTbl` (the
floor the claims dress over), then runs the Arbiter's pure resolve over the SAME
claims + rank + floor and appends a `claimants (rank order)` block to the trace. New
pure seams: `M.arbExplain(claims, order, floor)` â†’ per slot, the rank-ordered list of
every claimant with an opinion (first = winner); `M.arbWhyLines` â†’ the formatted lines
â€” `Ammo: AutoAmmo (rank 3) over MaxMP (rank 4)`, a veto slot reads `stopped by Locks`,
and the slots the trigger floor dressed uncontested collapse into one trailing
`Triggers floor (rank 8, uncontested): ...` summary (a floor-only slot wins only when no
claim touched it, so nothing is lost and idle `/dl why` stays readable). Slot matching is
case-insensitive because
the producers disagree (overlay tables proper-case, `M.locks` lowercase). Locks join the
attribution as the veto claim (`arbLockClaim(M.locks)`); the live equip already honoured
them via `layerRespectsLocks` / `ctx.mpRespectLocks`. A new `mSig` (MaxMP target) joins
the retrace signature so the attribution stays fresh when the battery plan shifts.

**The Claim record shape is documented** (arbExplain header comment + architecture.md
"The Arbiter â€” claim registry"): a Claim is `{ [SlotKey] = itemName }`; a new claimant
joins with ONE rank row + ONE claim table (+ an `applyClaim` closure if it applies a
discrete overlay), never a new engine arm. AutoAcc â€” the per-piece claimant on
`feature/autoacc` â€” is the shape's first future consumer; its `accResolveSet` arm in
`equipResolved` stays put as the shape-ready seam.

**What stayed OUT, unchanged** (existing test families prove it â€” the whole suite is
green): sync-settle/proximity holds, the PetAction gate, AutoStaff/AutoObi virtual
entries, Dynamic flattening, the ADR 0010 trinket contests, and every within-set
resolution arm of `equipResolved`. The Arbiter arbitrates *between* claimants; a
claimant's own conditions stay inside the feature.

**Tests:** AR11 (whole claim path pinned in one `arbExplain` resolve â€” the Ammo cede,
a battery over craft armor, a battery in a bare ring, the Locks veto, a floor-only
slot), AR12 (the `/dl why` line format incl. the issue's headline example + canonical
LAC slot order). 2151 headless + 199 smoke green. Engine v100, addon.version
2026.07.21d.

## Engine-native slot locks: /lac disable retired from the lock path (2026-07-21, PRD #57)

**The field find (Henrik, step-3 checkpoint):** pin-into-locked-slot did NOT punch
through at default rank â€” yet every LV* test said it must. Root cause: the Equipped-tab
lock paths queued `/lac disable <slot>` alongside the engine lock ("belt-and-suspenders
for legacy profile code"). `/lac disable` blocks the slot BELOW the engine â€” LAC refuses
every write â€” so the Arbiter's rank law was correct and unobeyable. The Priority list
showed a law the game ignored.

**The fix (#58/PR #60):** the engine lock is the ONLY lock. Lock actions queue no `/lac`
at all; unlock keeps `/lac enable <slot>` as a self-healing release for stale legacy
disables (the whole migration story â€” no sweep). Scope fences pinned BY TEST: Free equip
keeps its global `/lac disable` pair (that feature's point is "LAC hands off"), useitem's
countdown disable stays (a temporal hold, future engine-hold candidate). Tests S200â€“S211.
With the clean-shim Setup standard, legacy hand-written equip code â€” the original reason
for the belt â€” is explicitly outside the lock's guarantee. Field-confirmed same evening:
punch-through at defaults, Locks-at-top vetoes pins. The standing lesson generalized:
**a command-layer state the engine doesn't own will eventually contradict the engine**
(same family as [[self-queued-commands-not-heard]] and the v43 lockstyle saga).

## Blueprints: the trigger-rule library (2026-07-21, PRD #64, engine untouched)

**Origin (Henrik):** "slept or lullaby'd â†’ Toxic Earring" belongs on all 22 jobs;
rebuilding it per job is "atrocious". Grilled to a decision record the same evening.

**The rulings:** *Blueprint* (CONTEXT.md; _avoid_ favourite/template/preset) = a
job-independent saved Trigger in ONE per-character library file OUTSIDE Profiles;
*stamping* creates an ordinary Trigger in the job entry, detached both ways. Payload =
the rule VERBATIM (when/whenAny, action, priority) + Handler + display name â€” **carrying
referenced sets was REJECTED** (Henrik: dangling set/Mode/Group references stamp anyway
and the existing missing-reference warnings suffice; revisit only on field demand).
Inline-payload rules are the dependency-free sweet spot â€” the export system already
treats them as self-contained.

**Shape (#67+#68):** pure core `gear/blueprintsmodel.lua` (TGB1â€“46: naming, detachment,
warn-but-allow double-stamp, byte-stable `blueprints v1` round-trip, sandbox hardness,
import collision matrix); Blueprints section in the Triggers tab (Groups-section
precedent â€” NOT a uihost tab); "bp" button on every rule row; Stamp/Edit/View
text/Copy/Copy all/paste-import with live preview. **Maintenance tripwire:** `emitRule`
is a deliberate MIRROR of `serializeTriggers`' per-rule form (the issues forbade engine
changes) â€” TGB34/35 pin behavioral parity through the REAL engine path; if the engine's
rule form ever changes, the mirror follows. Polish from the first field round: rule text
wraps at the live box edge, the library scrolls in a capped child (the Sets-list
pattern). Fully field-confirmed incl. the sharing round trip.

## The day of the agents: CI parity, serial dispatch, and two corrections (2026-07-21)

Eight label-dispatched cloud-agent PRs shipped in one day (#52â†’#68: Arbiter v97â€“v100,
engine-native locks, Venture Ring, Blueprints Ã—2), every one review-gated and
field-gated. What made it possible and what it taught:

- **CI had been red since 07-19** â€” LGF4/6/8 failed ONLY on Ubuntu lua5.4: lockstyle's
  `'\'`-joined io paths are literal filename chars on Linux, so the keepflow fixture
  never loaded (the stray files literally NAMED `tests\fixtures\...` were the
  fingerprint). Fix: `fsp()` separator normalization at lockstyle's io boundaries, a
  no-op under Ashita. **Windows-green â‰  CI-green** â€” the parity loop is lua5.4 under
  WSL; agents self-verify with this suite, so a red main poisons every dispatch.
- **Serial dispatch is law** when issues share files (dispatch.lua, run_tests.lua):
  one `ready-for-agent` at a time, review, merge, next.
- **Correction 1:** step 4's docs named AutoAcc the next-claimant example. Henrik's
  ruling: AutoAcc is a **Type automation** â€” per-piece candidate release at WITHIN-SET
  altitude, any slot â€” never a claimant; the Arbiter never sees it. Docs fixed
  (ADR 0012, architecture.md, the registry comment). The rank-row+claim-table recipe
  stands for genuine future claimants.
- **Correction 2:** Venture Ring's bonus is **Venture Points +100%** (the HELM
  currency), not exp â€” it keeps its seat in the exp-rings section by ruling, labeled
  `+100% VP`.

## Gear Oracle step 3: the golden-output harness (2026-07-22, tests-only, PRD #69)

**Theme:** the Phase 2 safety gate, captured BEFORE any stat-glue migration touches the
field-tuned ladders. PRD #69 phases the Gear Oracle: Phase 1 (step 1, #70) moved the
mechanical fetch layer behind one door; Phase 2 (step 5, still BLOCKED on the unrun field
rounds) will migrate the manifest builders that hand-glue "effective stats = level-scaled
stats + augment fold" onto a shared `oracle.stats()` recipe. The PRD's phasing decision is
explicit: Phase 2 must be *proven* byte-identical, not assumed, so a later field failure
can never be misattributed to the refactor. This slice builds the proof harness.

**Landed (tests + docs only â€” no runtime file touched, no seeded behavior, no VERSION bump):**
- `tests/goldenfixtures.lua` â€” one deterministic, synthetic, headless BLM at Lv74 and one
  curated bag, fed through the REAL builders (`automationsui.rescanAutogear` for the
  manifest; `fishcalc` for the rod-ranking reads). Captures the builders' own output
  verbatim; the only value dropped is the manifest's `written` clock stamp (normalized).
- `tests/golden/autogear.golden` + `tests/golden/fishcalc.golden` â€” the committed goldens.
- `tests/gen_goldens.lua` â€” the regenerator (run ONLY after an intentional builder change,
  review the diff).
- **smoke_ui section 12** (S220â€“S223) â€” asserts the builders reproduce the goldens
  BYTE-IDENTICALLY; on drift it names the first differing line and points at the
  regenerator. `.gitattributes` pins `tests/golden/*.golden -text` so Windows autocrlf
  can't turn a byte-identical golden into a CRLF mismatch.

**Coverage (the interesting cases the PRD names, one item carries each):**
- **level-scaling** valued at the character's level, not base â€” Tamas Ring (catalog id
  15545): MP 15 base â†’ **29 at Lv74** through the central `levelstats.effective` resolver;
- **augment fold** â€” Hlr. Bliaut +1 reads MP 35+18 = **53**, Clr. Bliaut +1 reads Refresh
  1 native + 1 aug = **2** (the same decoder the set scoring uses, stubbed by id);
- **one item across multiple ladders** â€” Survey Sash lands in `mpBest.waist` + `helm.waist`
  + `fish.waist`;
- every named builder: MaxMP battery ladder (mp/rf/mv/mpBest incl. Convert), HELM ladders +
  hat map, fishing ladders + the fishcalc rod ranking / `wornFishTotal` / `gearScore`, and
  the full per-craft owned-gear walk (Bonze Cape as the skill-up filler across all eight
  crafts).

**Two determinism traps handled:** the manifest builder stamps `written = os.date(...)`
(normalized out before capture/compare), and the fishcalc reads run against a SYNTHETIC rod
db injected through the `_setDb` test seam (restored after) so the ranking never depends on
the shipped `fishdb.lua`. Merge-adjacent with step 1 in the test registry (both grew the
suites). Full headless suite green: 2268 run_tests + 225 smoke_ui, Ubuntu lua5.4 CI parity.

## Gear Oracle step 2: eligibility + identity through the oracle (2026-07-22, PRD #69, engine untouched)

**Theme:** Phase 1's second slice (#71). Step 1 (#70) moved the mechanical FETCH layer
(worn-item decode, equip-bag list) behind the oracle; this slice moves the ELIGIBILITY and
IDENTITY questions the same way, and deletes the private re-statements that were the whole
point â€” the "no job list means wearable" rule existed inline in two places besides the
central one, exactly the deduction drift the oracle ends.

**Three questions get their one door (facade, not absorb â€” the interpreters keep their homes):**
- **`canWear(rec, job, level)`** â€” main-job/level equip gate. DELEGATES to the engine
  module's addon-visible rule (`dispatch.canWear`: main job only â€” sub never widens,
  field-verified â€” level on main). The two inline fallbacks are DELETED: gearoptim's
  `jobAllowed` (its own `All`/job loop) and gearui's `jobCanEquip`/`isUsable` fallback (its
  own `#jobs == 0 -> wearable` restatement). Both now call `oracle.canWear`; gearui's
  `has.dsp` flag went with them (`_dsp` stays only for `virtualMinLevel`). gearoptim keeps
  its own "unknown job â†’ don't job-filter, level still gates" (canWear would reject a
  restricted piece against an empty job â€” not that tool's intent).
- **`anyJobCanWear(rec, jobLevels)`** â€” the any-job-at-current-level gate (the lockstyle
  rule, the server's `canEquipItemOnAnyJob`). DELEGATES to the existing addon-state gate
  module (`gear/jobgate.canEquip`), which keeps its home, tests and FAIL-OPEN semantics.
  lockstyle's two gate calls (`gateOk`, `_boxBadPiece`) migrated to the door; jobgate stays
  required there for its live level READER (`jobgate.levels()`), which the oracle does not
  front. The nil-jobLevels fail-open stays the CALLER's (lockstyle short-circuits on a nil
  levels read) â€” the door copies no logic and fabricates none; only a missing gate MODULE
  fails open inside `anyJobCanWear`.
- **`lookup(idOrName)`** â€” "what is this item": the owned-record + catalog-record join
  (owned first, then the full catalog; id authoritative, name the case-insensitive
  fallback), moved out of its UI-local home. The JOIN recipe lives in the oracle now;
  gearui's `lookupById`/`lookupByName` are thin adapters over it. **The trap:** the oracle
  can't just flatten raw `gear.lua` itself â€” a Phase-2 owned record carries no stats until
  gearui's enrichment pass mutates the shared table, so the oracle takes the enriched,
  flattened indexes through `setLookupSource` (READ-ONLY accessors that never trigger a
  build â€” the render paths own when the flatten happens, exactly the old pair's lazy-read
  semantics; a first cut that forced `buildOwned()` inside the accessor early-cached the
  owned table and broke smoke_ui S19, the apostrophe-bridge test that adds gear AFTER load).

**Also this slice:** the exporter's duplicate catalog nested walk is retired
(`gearexport.catalogIndex` deleted); `M.export` routes its id-index through
`catalogindex.rawIndex()`, so exactly ONE catalog nested walk remains in the codebase (the
acknowledged tech-debt cleanup from architecture.md; the Z-tests inject a pre-built byId map
into `buildExport` directly, so nothing there re-walks either).

**Claim-blind, permanently:** every answer is a CAPABILITY (could this character use it),
never permission (may this slot change now â€” the Arbiter's word). Method names use
could-words (`canWear`), never may-words; OR29 pins that the oracle exposes no `canEquip`
door. Behaviour-identical by construction â€” no engine change, no seeded-file behaviour, no
`dispatch.M.VERSION` bump; only the addon `version` date-bumped (`2026.07.22b`). Tests:
OR14â€“OR29 (canWear vs `dispatch.canWear`, anyJobCanWear vs `jobgate.canEquip`, the lookup
join, the claim-blind boundary). Full headless suite green: 2293 run_tests + 225 smoke_ui,
Ubuntu lua5.4 CI parity.

## The pet channel: stats the API never showed us (2026-07-22)

A friend's report ("dlac shows no Wyvern HP+ on my gear") uncovered a whole invisible
stat channel. CatsEyeXI applies pet-targeted gear stats â€” Drachen Brais "Wyvern:
HP+10%", Wyvern Mail's hidden wyvern HP+65/HHP+65 â€” through a separate
`item_mods_pet` table loaded into `CItemEquipment::addPetModifier` (a channel apart
from the regular mods). The live API serializes only `{item, mods, latents, weapon}`:
verified across all 21,860 cached responses, the pet channel NEVER leaves the server.
So apicrawl was blameless and the repo SQL is the only possible source (corollary:
live-only custom pet mods, if the live DB ever diverges like it does for latents,
stay invisible â€” nothing to cross-check).

Shipped as the established sibling-data pattern, per Henrik's tooling ruling (one
umbrella command, independently runnable steps, one shared parser):

- **`gen_petmods.py`** (gitignored tools/) parses the SQL (anchored INSERTs â€” the
  table carries ~21 commented-out rows, the item_latents trap again) through
  **`modmap.py`**, THE shared modidâ†’stat-key bridge, into shipped
  **`data/petmods.lua`**: `[itemId] = { Wyvern = { HPP = 10 } }` on canonical catalog
  keys. 396 items, 816 rows, 9 pet types; generation asserts pin the field cases.
- **`refresh_all.py`** = the one-command maintainer update (apicrawl â†’ petmods â†’
  levelscaling â†’ gearsets, continue-on-error summary). Adopting the pet mod names
  into modmap.CORE immediately rippled canonical spellings into latentstats.lua and
  gearsets.lua (`REGAIN`â†’`Regain`, `ABSORB_DMG_CHANCE`â†’`AbsorbDamageChance`) â€” the
  shared-parser effect working as intended, plus four new statdefs entries (DEFP,
  AbsorbDamageChance, MainDMGRating, MonsterCorrelation).
- **Display-first** (`gearfmt.petLines`): tooltips get one line per pet type
  ("Wyvern: HPP+10"; `All` reads as "Pet"), row summaries spend leftover token budget
  ("Wyvern:HPP+10") which also makes pet gear findable by the stat search.
  No engine/optimizer participation â€” that is a separate later call.

## The Gear Oracle: one door for every gear question (2026-07-22, PRD #69, COMPLETE)

**The arc:** Henrik's morning suspicion â€” "every time gear data tries to be fetched,
many areas of the code do their own thing" â€” grilled into PRD #69 and shipped complete
the same day: five squash-merged PRs (#75â€“#79), agent-built via the label-dispatch
pipeline, every PR maintainer-reviewed (footprint, claim-blind grep, both-platform
battery, golden cleanliness). Full reference: **docs/design/gear-oracle.md**; rulings:
**ADR 0013**. The investigation's surprise: the *interpretation* layer was already
centralized (`comboStats`/`levelstats`/`augments` â€” Henrik's hunch about the weighing
path confirmed); the real drift was the *fetch* layer (worn-item decode Ã—4, bag list
Ã—4, gate fallbacks, catalog walk Ã—2). The oracle deleted every copy.

**What shipped, per slice:** #75 â€” `gear/gearoracle.lua` born: `wornItem`/`equipBags`,
three addon-state decodes deleted, engine twins hoisted to named form
(`M.decodeEquipIndex`, `M.AMMO_BAGS`) and parity-pinned. #76 â€” the golden harness
(separate entry above) + the Windows scaffold-dir fix (`60facb5`: `dlac\autogear.lua`
is one *filename* on Linux, a *subpath* on Windows â€” CI-green â‰  Windows-green on
golden work). #77 â€” `canWear`/`anyJobCanWear`/`lookup`; the gearoptim/gearui inline
gate fallbacks deleted; gearexport's duplicate catalog walk retired onto catalogindex.
#78 â€” GRD1â€“5 HARD RULE guards (three-way self-checks incl. sanctioned-home-contains-
idiom), ADR 0013, the Central-services row; temporary allowlist named automationsui +
gearui + equippedui (wider than the issue's prose â€” the guard found every interpreter
load). #79 â€” `stats()`/`setStats()` recipes; the three allowlisted surfaces migrated;
**goldens byte-identical on both platforms with the .golden files untouched in the
diff**; allowlist emptied, rule absolute. One disclosed widening: the augment fold is
now the full map, not MP/Refresh-only (correct per "augs must always be calculated
into the total"). fishcalc untouched by design: pure/parameterized â€” its stat feed was
automationsui's ladder read, now oracle-sourced.

**The boundary that matters most:** the oracle is CLAIM-BLIND, permanently. Capability
("could I wear this") lives here; permission ("may this slot change, who wins") stays
the Arbiter's (ADR 0012). Henrik's ruling verbatim: "otherwise they would contest,
that would only create complexity." Names enforce it â€” `canWear`, never `canEquip`.

**Same-day housekeeping:** the field ledger emptied â€” Henrik blanket-confirmed the
whole UNRUN pile (fishing v91, Blueprints, town lockstyle v46, Iridescence sweep,
MaxMP pair homes, then Target condition, Teleports quick menus, Sets Equip & Lock T3,
AutoAmmo v73). Two flags turned out doubly stale (Blueprints, MaxMP pair homes were
already confirmed in their files â€” index rot). Engine VERSION untouched all day; the
pet-mods commit rode the rebases (held by its session for the oracle-reporter rewrite â€”
the oracle's first post-ship consumer).

## The oracle's first new answer: pet stats enter the door (2026-07-22, same evening)

The pet-mods session validated its held commit against the freshly-written oracle
reference and found the predicted mini rival door: `gearfmt` requiring
`data/petmods.lua` directly. GRD5 does not police data tables â€” the commit passed CI
by the letter â€” but "extending gear knowledge = adding an answer to the oracle" is
the law's spirit, and the design doc had already named pet-mods the first planned
consumer. The alignment landed the same evening:

- **`oracle.petStats(recOrId)`** â€” the pet-channel answer, in the oracle's own idiom
  (lazy `interp` require, FRESH each call, nil-safe). **Deliberately separate from
  `stats()`**: pet values never fold into master stats (wyvern HP is not your HP),
  and the golden gate pins `stats()` byte-identical â€” a fold would be a gate breach.
- **`gearfmt` asks the door** and keeps only composition (labels, order, budget) â€”
  presenter, not knower.
- **PM section grew the door proof:** swap `package.loaded['dlac\data\petmods']`
  under a live gearfmt and watch petLines change â€” observable only because the
  oracle requires fresh each call. A private copy in any presenter now fails CI.

Goldens stayed byte-identical through the rewire on both platforms (2345 + 225
checks). The extension path â€” "if the oracle can't answer it, that's a gap in the
oracle" â€” worked exactly as the doc promised on its first exercise.

## Pet stats become priceable: the channel enters the weights system (2026-07-22, later that evening)

Henrik made the "optimizer = later call" call the same day the channel shipped:
pet stats should be weightable and listed in the stat menu. The design problem was
squaring two rulings â€” pet values must never fold into master stats, yet the weights
system prices ONE flat map â€” and the answer was a **namespace**: `Pet:`-prefixed keys
(`Pet:Haste`) live in the same scoring map without ever colliding with `Haste`.

- **`oracle.petScoreStats(recOrId)`** â€” the channel flattened for scoring. Per stat
  the context-free scalar is **All + the BEST named type**: the server grants a pet
  All plus its own type's mods, and a pet is exactly ONE type â€” summing across named
  types would credit mutually exclusive pets. Max is exact whenever one named type
  carries the stat, which is nearly every row in the data.
- **`oracle.petStatKeys()`** â€” the distinct stat keys the pet data actually delivers;
  the weights editor's "add stat" picker lists the family from it (type "pet" to
  browse it; "haste" surfaces `Pet:Haste` beside `Haste`).
- **One seam, no drift:** gearui's `candidateStats` merges the pet keys, so every
  scoring consumer â€” per-item sorts, Auto-build's joint pools, pair ladders â€” prices
  pet gear identically; `workingWeightedScore` folds the same keys per piece on top
  of `setStats` (which stays pet-blind â€” the goldens pin it byte-identical, and they
  stayed so through this change).
- **The pricing plumbing followed:** `statdefs` derives label/section for the
  namespace (`Pet:Haste` â†’ "Pet: Haste", section Pet; `canon` keeps the prefix and
  canonicalizes the inner stat), `gearoptim`'s spelling table learns the family from
  the oracle (a typed `pet:haste` resolves), and `Pet:PDT` is negative-good exactly
  like `PDT`.
- **PM17+ pins it all:** the All+best-named flatten (via a swap table), the
  namespace hygiene (no bare master key ever leaks), statdefs derivation, and
  gearoptim's pricing + negation. 2363 + 225 green on Windows and WSL lua5.4.

Field rounds, same night. Round 1: "not seeing wyvern hpp+" â€” the code was fine;
the DEPLOYMENT seam wasn't. The game loads the MAIN checkout, and the feature sat
two commits ahead of it on origin â€” **pushed â‰  playable**, now a survival rule:
after pushing, pull the main checkout before asking for a field round. The report
also exposed a search-instinct gap: Henrik looked for the stat by his PET's name.
So `petStatKeys` grew a second return â€” { statKey â†’ the pet types carrying it } â€”
and the picker folds those names into its search terms: typing "wyvern" surfaces
Pet:HP%, "automaton" its accuracy family (7cc98f1; PM18a/b pin the shape). Round 2:
**field-CONFIRMED** â€” "It's there."

## The oil that would not stay: a stale stamp, not the Arbiter (2026-07-22, night)

Field report (Mindie, PUP): a MANUALLY equipped Automat. Oil +2 vanished from Ammo
every Default dispatch â€” suspicion fell on the new Claim Arbiter "blocking manual
equips completely". The Arbiter was innocent: manual equips never pass through it.
The killer was ADR 0010's worn-trinket displace running on wrong data â€” the trinket
completion ("Ammo with no AmmoType â‡’ RSlot=4") had stamped the oil Range-reserving
in the manifest, so any plan holding the idle set's Animator in Range displaced the
worn oil with `Ammo='remove'`, every dispatch.

The census that settled it (local server clone, item_equipment Ã— item_weapon over
every Ammo-slot item): the real Range/Ammo conflict law is **charutils' weapon
skill/subskill compat check**, not rslot â€” Rimestone, Cinderstone and Coiste Bodhar
all carry server rslot=0 yet genuinely conflict through that check (skill 0:0
matches no Range piece). The four Automaton Oils are skill 0 / **subskill 10 â€” the
subskill of every Animator** â€” so the server KEEPS oil + Animator together; they
are the ONLY AmmoType-less ammo class that PAIRS with a Range piece. (Animator II
variants are subskill 11: oils do not pair with them, server-enforced. Henrik's
field statement â€” "automaton oils are operable with animators" â€” was the exact
falsifier of the blanket completion.)

The fix, two altitudes (6b149ea + d4c602f, engine v101, addon 2026.07.22h):

- **gearrecord.ANIMATOR_FED** id-pins the oils (18731/18732/18733/19185) out of
  the completion â€” the one place RSlot is decided â€” and `/dl fix` learned that the
  RSlot stamp is machine-owned BOTH ways: a reservation the rule no longer asserts
  is retracted, a changed catalog value corrected in place (E12â€“E17).
- **The engine distrusts the stale stamp itself**: `M.recordRSlot` is now the one
  reader of a manifest record's RSlot and ignores it for the pinned ids (engine
  mirror of the addon-side set, TR17 parity-pinned). Because dispatch.lua re-seeds
  into every character folder on every addon load, the update alone heals every
  user â€” no `/dl fix` migration step required (that command remains as tidying).
  TB8 drives the field case end-to-end through the real glue.

**Field-CONFIRMED same night**: "I can equip all the oils now." Noted for a
follow-up during verification: the engine self-swap is keyed on `M.VERSION` alone,
so same-version content edits go unswapped until a manual Reload LAC â€” a
content-keyed swap is the proposed cure.

## Hand-to-Hand slips the craft Sub guard: the flag lied, Type now decides (2026-07-22)

Round 2 of the v37 Kupo-Shield flap, monk edition: with the craft overlay owning
Sub, a Hand-to-Hand Main was NOT held â€” it equipped, the server knocked the shield
off, craft re-equipped the shield, forever. The guard asks `utils.subSlotAllowed`,
and the rule read `OneHanded` â€” which for H2H is a lie with three faces: fresh
scans stamp `false` (gearimport's TWO_HANDED includes skill 1), the CATALOG stamped
`true` (apicrawl's `ONE` set wrongly listed HandToHand â€” fixed; Henrik's next
`--refresh` heals catalog.lua), `/dl fix` backfilled that `true` into gear.lua
files, and legacy entries carry none. Test AF4 even "covered" H2H â€” with a
flag-less fixture that passed by accident while every backfilled record failed in
the field.

A boolean cannot say "both hands" anyway: server law (charutils.cpp EquipItem) is
that an H2H main knocks ANY Sub off â€” grips included, unlike 2H â€” and a shield
equipped onto an H2H main knocks the MAIN off. So the shared rule now keys on Type
for H2H (`isH2H`, normalized 'HandToHand' / legacy 'Hand-to-Hand'): an H2H main
pairs with NOTHING at equip time; an H2H item never sits in Sub, building included
(a physical impossibility, the HARD RULE's exempt class â€” building stays
Main-blind otherwise, pinned A24/A25). gearui's fallback mirror matches; AF4 now
wears the catalog-lie shape so the accident cannot repeat. Tests A18â€“A25.
(utils.lua rides the seeder + a profile reload, not the engine self-swap: one
`/lac load` or job flip boards it; the GUI mirror boards on `/addon reload dlac`.)

Close-out, same evening: the lie's WRITERS are fixed through one record rule,
`gearrecord.healOneHanded` (H2H pins false; false/nil pass through intact).
enrich corrects the flag in memory, gearexport stops exporting it, and /dl fix
treats OneHanded as machine-owned BOTH ways like RSlot â€” a missing flag
backfills the healed value, the previously propagated true is corrected in
place, idempotent (REC27â€“33, E18â€“21). The shipped catalog keeps its wrong H2H
flags until Henrik's next crawl (tools/ is gitignored; the apicrawl fix cannot
ship via git) â€” inert either way: readers key on Type, writers heal on contact.

## Same-job profile import left the GUI in limbo: the addon-state readers now content-follow (2026-07-22)

Field report (Henrik): importing a friend's BLU export while ON BLU "imports and
builds everything, but complains a lot of sets are not known (from previous
profile)" -- importing for a job you are NOT on felt clean. Diagnosis: the import
writes the files and the ENGINE follows fine (the menu queues `/dl sets reload` +
`/dl triggers reload`, and the engine content-watches the trigger file anyway).
The limbo was three ADDON-STATE caches whose keys do not move when the import
lands on the current job + active profile:

- **triggersui's edit model** cached by JOB alone -- the tab kept showing the
  previous profile's rules against the NEW set-name list, so the missing-set
  banner listed the old profile's sets, and a Commit from that stale tab would
  have written the old rules back over the import (the real danger).
- **profilesets** cached by `jobfile|activeProfile` -- same key, new bytes; only
  the weights flow survived, because Auto-Build All happens to invalidate it.
- **lockstyle boxes** keyed `(profile, job)` -- imported `lockstyles\<JOB>.lua`
  stayed invisible until a job flip.

Cure (not a restart): the v102 content-keyed idiom extended to the GUI readers.
Each cache hit re-reads its source file's bytes at most once per second and
follows changes -- import, `/dl profile use` typed in chat, another session's
write, hand edits, all routes. The Triggers tab is an EDITOR, so it follows only
when clean; with unsaved edits it renders a red drift banner (Commit = your rules
win, Revert = the disk wins) instead of clobbering either side. Its Commit and
lockstyle's save() re-baseline the watch so their own writes never read as drift.
A profile SWITCH with unsaved trigger edits now discards them loudly (carrying
them over would splice old-profile rules into the new file). Pure decision seams
`_followTriggers` / `_followBoxes` + the profilesets behavior test are pinned as
TGW1-8 / PSW0-3 / LGW1-7.

## HELM first-contact round: the categoryless arm + the apostrophe the catalog drops (2026-07-22, addon 2026.07.22n, commit 3b999ad)

**Theme:** two same-evening HELM field cases, both presenting as "the gear
never comes" with NO HELM claimant in /dl why -- which is itself the
diagnostic: absence from /dl why means no claim ever FORMED (the state gate
or the gear gate failed), not that HELM lost an arbitration. The support
chain that cracked both, worth keeping: `/dl helm` (category + switches as
helmwatch sees them) -> `/dl prio` (the ENGINE's helmStateActive verdict --
the same gate the dispatch runs) -> `/dl helm show` (what the overlay would
resolve, or "(nothing -- no HELM gear in bags, or rescan pending)").

**Case 1 -- a friend's first session: armed, categoryless, silently dead.**
"Set HELM Idle" armed fine with no category ever picked; helmstate carried
gather="" and helmStateActive() returned false forever -- switch ON in the
UI, engine treating HELM as fully off, nothing anywhere saying so. A chat
warning at the arm choke point was written first, then replaced by Henrik's
ruling: **Harvesting is the first-timer default.** helmwatch.activeGather
now STARTS as 'Harvesting'; loadState only overrides from a VALID persisted
value, so existing gather="" state files heal to the default on their next
load. Any real pick (bar, command, 0x034 swing auto-detect, Auto-HELM
proximity) replaces it exactly as before. H0 pins the default.

**Case 2 -- Mindie's Miner's Helmet equipped under every category EXCEPT
Mining.** Perfectly backwards, and the manifest had the receipts:
hats.Mining said "Miners Helmet" (catalog spelling) while the head ladder's
rung said "Miner's Helmet" (the gear DB's client name). The hat-map builder
did a NAME-ONLY usableRec lookup with the hardcoded catalog string; the
oracle lookup missed ownedByName (apostrophe), fell through to the CATALOG
record -- id right, Name wrong -- and ownedRec validated ownership by ID,
so the manifest carried a name LAC can never equip. Mining took the hat-map
hit and failed; every other category MISSED the hat map and fell to the
generic head ladder, whose rungs come from ownedList records -- the real
client spelling -- and equipped fine. Fix: the semantic hat map is now
**id-PINNED (25557-25560, all four hats)** through usableRec's existing
pinId arm -- lookupById puts the gear-DB record (the REAL client name)
first; the catalog spelling survives only as the owned-but-not-yet-indexed
fallback, which autosync closes on its next rescan. The fixtures model the
true divergence now (real id 25560 + the apostrophe name, the Laevateinn
id-PIN precedent); S176 pins that the map adopts the DB spelling; the
regenerated golden diff is exactly the two name lines.

**The general law this round adds** (already the relic/universals rule, now
proven against the catalog itself): **any hardcoded item name must pin its
id -- catalog spellings are NOT client spellings.** The catalog drops
apostrophes; the client keeps them; an ownership check keyed by id will
happily validate a record whose Name can never equip.

No tracker items existed for either case (field reports came straight to
the session); nothing to close. Henrik declared the round fixed 2026-07-22.
Both changes are addon-side -- /addon reload dlac to board; a session's
first arm rescans the manifest and rewrites the hat map with the id-pinned
names.

**Addendum, same day: the CRAFT twin.** Henrik: activating Craft on a FIRST
dlac run equips nothing for exactly the categoryless-arm reason -- craftstate
carries craft="" and the engine gate (craftOn requires a non-empty craft)
silently stands the whole claim down. Same ruling, same shape:
**Woodworking is the first-timer default** -- craftwatch.activeCraft STARTS
as 'Woodworking', loadCraftState only overrides from a non-empty persisted
value (old craft="" state files heal), any real pick replaces it. T14b pins
the default (the H0 twin). Fishing needs no sibling: fishstate has no
category -- rod/bait picks are ownership-driven, not chosen.

## Session "the silent apply -- /dl check" (2026-07-23)

**Theme:** a friend switched to a laptop that syncs the addon tree; "everything
works except lockstyle -- preview fine, Apply produces NOTHING." Diagnosis by
architecture: preview never leaves the addon state (lookpreview's local 0x051),
while Apply crosses into the seeded engine in the LAC state ('/dl ls apply' ->
0x053) -- so total silence means the ENGINE side never heard the command. The
engine's /dl handler only exists where gFunc does (dispatch.lua header: "no
gFunc means no command handler"), and an engine that is absent, ancient, or
behind a dead shim cannot say so.

**Henrik's ruling (recorded):** "It is OK to add debug commands to help me help
players. But I don't want probe levels of debug commands needlessly. But
checking if it's doing what it should be doing is fine!" -- wiring-health
self-checks belong IN dlac; packet-level forensics stay in dlacprobe.

**Landed (engine v103 + feature/check.lua + 2026.07.23):** `/dl check`, in two
halves. The ADDON half (feature/check.lua, always hears a typed /dl) prints
three lines: addon version + the addon tree's engine file version + a
byte-compare of the four seeded library copies against the tree (the seeder's
steady state); the job file's shim classification (setupui.jobSetupState --
'clean dlac shim' or a run-Setup verdict); and the engine version last stamped
into modestate (__version handshake) plus the interpretation line: a
"[dlac] check (engine): alive" line MUST accompany the readout, and its
ABSENCE means LAC is not running the dlac engine -> Setup, then Reload LAC.
The ENGINE half is one branch in dispatch's command whitelist (added together
with the branch -- the v46 instdiag lesson): "alive -- vN, job, profile".
The design inversion: the engine cannot report its own absence, so the addon
side pre-announces what silence means. Tests CHK0-14 (pure seams: seeded-state
compare, shim wording, the three lines); FEATURE guard list grew 'check'.

**The remote-support script this replaces:** "type /dl ls state (addon state
answers), then /dl mode (engine answers) -- silence on the second means..."
-- now it is one command whose output carries its own interpretation.

**Addendum, same day: the /dl debug section (engine v104, 2026.07.23b).**
Henrik: "make a proper dl debug section, where you create dl debug ls (please
also accept dl debug lockstyle)." feature/debug.lua is the addon-state router
-- alias map, ONE usage printer, topics grow as field cases demand -- and
dispatch's 'debug' branch answers known topics only. Topic `ls`/`lockstyle`
in the two-halves pattern: the addon half is lockstyle.M.debugLines() (boxes
file + tier + byte count, marked box + piece count + onload/keepSub/town
flags, an UNSAVED-edits warning, the v47 gate verdict, keep/guard/town live
state -- `/dl ls state` now prints this same report, one readout two names);
the engine half is the APPLY PIPELINE AS A DRY RUN -- same file (path +
MISSING/no-PARSE called out), same box pick (`/dl debug ls 3`), same
resolvers (M._lsResolvers, hoisted verbatim out of the apply branch), same
job-gate prediction, printed instead of sent (M._lsDebugReport, pure). Tests
DBT0-6 (router), DBG1-6 (dry-run report), LGD1-4 (addon half headless);
FEATURE guard list grew 'debug'. The support flow for the laptop case is now:
`/dl check` (wiring) then `/dl debug ls` (feature state, both sides of the
wall) -- paste chat.

**Addendum 2: /dl check grows the ISSUE HUNT (2026.07.23c, addon-side only).**
Henrik: "dl check is a good command IF it checks the general health of dl and
can report issues" -- so it stopped being a stamp recital. New: a module-load
LEDGER (dlac.lua records every require of its load loop into a virtual
package, 'dlac\loadledger'; check reports "modules: 17/17 loaded" or names
the failures with their errors -- a corrupt/half-synced tree becomes a named
verdict instead of a scrolled-away load line); data sanity (catalog item
count through catalogindex's one door -- under ~10k = "truncated sync?"
issue; gear.lua entry count vs empty template; active profile); and an
explicit engine/file version-agreement check (stamp BEHIND file -> Reload
LAC; stamp AHEAD -> the addon tree is stale). Six lines now, the last a
verdict: "NO ISSUES addon-side" or the numbered list. States
indistinguishable from a fresh install (empty gear.lua, legacy storage,
pre-login unknowns) are reported but never called issues. Tests CHK0-17 +
CHKI1-10 (the hunt, each provable problem named). Also recorded: the friend's
folder rename was a deliberate, reversible corruption check -- support
guidance should match that register (Henrik's correction).

**Addendum 3: debug reports become FILES + the send witnesses (engine v105,
2026.07.23d).** Henrik's file rule: "all things that are considered debugs
should generate text files that can be easily transferable so we can help
debug" -- and his workflow question ("does debug ls check... if he is
sending the packets?") exposed the one unobserved step. Files: every
/dl check and /dl debug <topic> run now writes ONE
addons\dlac\debug\<base>-<Char>.txt (overwritten per run -- support wants
the latest, not an archive; dir gitignored). The two halves live in two Lua
states with no shared memory, so the file is assembled by HANDOFF: the
engine branch writes its bare lines stamped with os.time() to
<char>\dlac\debug-<topic>-engine.txt in the same command frame;
feature/debug.lua's deliver tick reads it ~1.2s later, judges freshness
(10s window) and writes the merged report -- a MISSING or STALE engine half
is written into the file in those words, so the artifact carries the
absence-is-the-diagnosis property everywhere chat does. Send witnesses,
closing the workflow gap: the apply branch stamps M._lsLastSend at its
AddOutgoingPacket ("last REAL apply this engine session: box N (M slots)
Xs ago" -- sender-side truth), and the addon guard's packet_out handler
keeps a 3-deep 0x053 observation log (M._outLine: "guard saw 0x053 out:
SET 4s ago (activate); ..." -- reports what it saw, promises nothing about
injected-packet visibility, the engine witness owns that side). Tests
DBF1-7 (merge/freshness/sanitize), LGD5-7 (traffic line), 2491 green.

## Session "the rest of the travel wardrobe" (2026-07-23)

**Theme:** Henrik: "list all the teleport items we haven't added to the teleport
menu yet (if the player has them available)" -- he named Maat's Cap and the Ducal
ring; a server-scripts sweep (scripts/items, grep for TELEPORT effects) found the
full remaining family.

**Landed (2026.07.23e):** 28 new entries in useitem's TELEPORTS table. Kazham
Earring joins the ear cascade (between Norg and Jeuno -- Elshimo neighbors; same
Marceo's Guttable Fish source as the other town earrings). Everything else is a
new grp='util' tier -- "Other Teleports" cascade in the popup, rows OWNED-ONLY
(Henrik's framing: "if the player has them available"; a grab-bag of unowned
misc is noise, unlike the ear/ring cascades where the dim row reminds you the
destination exists -- own none and the cascade hides itself): Maat's Cap +
Ducal Guard's Ring (both Ru'Lude Gardens), Tavnazian Ring (CoP 8-1), Nomad +
Moogle Caps (home nation, aoe=1 = party-range), Return + Homing Rings (SAME
enchant on this server -- both cast the current region's outpost warp, differ
only in charges 10/30), Olduum Ring (Wajaom), the three [S] Recall rings
(Jugner/Pashhow/Meriphataud), Black Chocobo Cap + the three nation stables neck
pieces, Tidal Talisman (zone-dependent destination; BODY slot here, not
retail's pendant; Obsidian Fragments, ACE/CW), the 8 HQ seasonal swimsuits
(RSE, all -> Purgonorgo Isle), Wyrmking Suit +1 (Riverne #B01) and Cumulus
Masque +1 (Reisenjima). Excluded by ruling: weapons (Warp Cudgel, the [S]
Retrace staves -- equipping Main wipes TP), Empire/Safehold Earrings (scripts
exist server-side but the items are unobtainable here).

**Mechanics:** every new item is useDelay=30 in item_usable -- the existing
TELE_WAIT=34 covers all 28, no per-entry wait needed. SLOT_ID grew head=0x04
(the lock/equip chain already accepted 'head'). All new entries id-PINNED with
load-time name resolution (the id-pin law: catalog/API names drop apostrophes,
"Maat's Cap" must be client-exact for /equip + the bag scan; SCROLLS pattern).
/dl t learned ownership narrowing for multi-hits: several items sharing a
destination resolve to the one you OWN (equippable beats stored, readiest wins
among equals; 8 suits -> yours, 'stables' -> your nation's); distinct
destinations stay ambiguous -- ownership must not silently pick a PLACE.
listTeleports dedupes repeated dests for listings and tags items by name in
ambiguity messages. menuNames() (the picker-hide export) now exempts
keepInPicker entries: Maat's Cap is +7 all stats in item_mods -- real gear the
set-building picker must keep offering; everything else in the family is DEF
1-2 trinketry and stays hidden. gearui: 'util' tier split + "Other Teleports"
cascade + a wider charges/state column pair for that tier only (stables names
run 24 chars into the old 340px column). Tests UT1-UT9 (owned-only tier,
Kazham placement, picker exemption, narrowing paths), 2505 green both loops.

**Addendum 4: the capture window (engine v106, 2026.07.23g).** Henrik: "have
it run at least 30 seconds when you issue dl debug ls... so you can capture
all the events." '/dl debug ls [seconds]' (30-120 clamp, default 45; the
number now means SECONDS -- the niche box-pick override died for it) prints
the snapshot, then opens an observation window in BOTH states off the same
command. Addon side: lockstyle's capture API notes queued commands (the
Apply button's '/dl ls apply' -- queueCmd is the hook, so the click itself
is witnessed), 0x053s leaving with their guard verdicts, zone-ins, job
packets, guard arms, user-off stamps. Engine side: the apply branch notes
every receipt/refusal/send into M._lsDbg.log; the dispatch tick flushes the
handoff at window end (M._lsDbgFlushLines, pure). feature/debug.lua delays
its merge to window + 4s and appends the addon timeline at the WRITE moment
(the log is complete then, not at booking). The report file now shows the
click's whole journey -- queued in the addon, received by the engine, SENT
or refused-with-reason -- or names the hop that went silent. One run is
still ONE window: nothing keeps running after it closes. Tests DBT7-11
(clamp twins), DBG7-8 (flush), LGD8-10 (capture cycle); 2515 green.

**Addendum 5: the provisional write (2026.07.23h, addon-side).** Field
(Henrik, local): "debug folder created, but no txt file" -- the final write
deliberately waits out the capture window (~49s), so an early folder check
finds nothing and looks like failure. Fix: deliver() writes the PROVISIONAL
report the moment the command runs (addon half + 'PENDING' engine section),
chat prints 'report file created (finalizes in ~Ns) -> path', and the tick
OVERWRITES it with the merged final. The pending note doubles as the tick's
own tripwire: "if this line is still here well after, the deliver tick never
fired -- send the file anyway, that fact is the finding." A debug run can no
longer end fileless: booking writes, finalize overwrites, and every failure
path prints itself. Test DBF8.

**Round close, 11:32-11:34 field confirmation + the deafness finding.** Both
reports produced complete on Henrik's machine (check: all-healthy, both
halves; debug ls: two Apply clicks' full journeys -- queued/noted/0x053-out
addon-side, received/SENT engine-side, timestamps aligning across the state
wall to 0.1s). The receipt file stayed EMPTY: the addon state heard NEITHER
typed command -- the command-event fallback drove the entire flow, which is
the design working, not luck. Durable facts proven in passing: (1) engine-
injected 0x053s DO fire the addon state's packet_out (the guard witness saw
every real apply leave); (2) the dlac addon state can be deaf to typed /dl
while every other event channel (d3d, packets) flows. Leading theory,
untested: /addon reload re-appends dlac to the END of Ashita's command
chain and the engine's own e.blocked (LAC ahead of it) halts propagation --
one fresh-boot receipt test settles it someday; the file-driven design is
order-proof either way. The friend script, final: update -> /addon reload
dlac -> /dl check -> /dl debug ls + click Apply during the window -> send
addons\dlac\debug\dlac-check-<Char>.txt + dlac-debug-ls-<Char>.txt.

**Round 2 close: the starvation pair + the namespace collision (v108,
2026.07.23k).** The friend's first artifacts arrived and the report did its
job: clean shim, current seeded copies, 18/18 modules, v107 modestate stamp
-- and "ENGINE HALF MISSING". Plus his receipt file HAD a line (his addon
hears /dl) and his '/dl debug ls' flipped the dev-buttons toggle. Three
findings: (1) NAMESPACE COLLISION -- '/dl debug' already belonged to
gearui's dev-buttons toggle, whose whitelist claimed 'debug' wholesale and
blocked; fixed: the toggle keeps bare/on/off only, topics pass. (2) THE
ASHITA PROPAGATION LAW, field-established from BOTH directions in one day:
e.blocked stops LATER addons in the chain from receiving a command, and
reload order is chain order -- Henrik's dlac-reloads deafened his ADDON
state (engine first, blocked), the friend's reload order starved his ENGINE
(dlac first, check.lua's own e.blocked ate the command before LAC received
it; his engine was alive the whole time -- it had stamped v107 at LAC
load). (3) The cure is SYMMETRY: the addon now writes debug-request.txt
(stamp + 'check'/'ls <dur>') when IT hears; the engine's tick watches it
(M._reqFire, twin of M._watchFire) and runs the same halves the command
branches call (engineCheckHalf/engineLsHalf -- one implementation, two
doors). Whichever state hears a typed /dl, both halves complete; the
8s idle gates keep the double-hear case single-run. check's finalize delay
1.2->3.0s to ride out the request round-trip. Tests DBR1-5; 2526 green.
The friend's NEXT run should produce a complete two-half report -- and his
original silent-apply case now has a plausible mechanism (command-chain
starvation) that the debug ls timeline will confirm or refute.

**Round 3: the original bug, mechanically closed (v109, 2026.07.23l).** The
friend's standing report -- "everything works BUT lockstyle" -- is the chain
law's precise shadow: every automation rides LAC's internal handler flow
(no command bus), while lockstyle apply was the ONE player feature whose
trigger crossed the bus ('/dl ls apply', queued by the GUI button and the
OnLoad/keep/town pumps, or hand-typed). On his load order the command died
at dlac's own blocking handlers before LAC's engine received it: preview
(addon-local) fine, apply silent -- the exact day-one symptom. v109 gives
the apply the same two-door shape as check/debug: engineApplyHalf (the
apply branch's body, extracted verbatim), called by the command branch AND
by the request watch; lockstyle's queueCmd wrapper and its typed-apply
observation write 'apply [box]' into debug-request.txt. All four
order/hearing quadrants land exactly one apply (8s idle gate); the starved
path costs ~1s of latency. M._reqSpec parses the spec line (DBR6-10).
One update now carries the friend's whole fix: tooling AND the bug.

**SAGA CLOSED -- field-confirmed by the friend, 2026-07-23.** v109's
request-file apply fixed him: Apply works on his machine, confirming chain
starvation as the root cause of the original "preview works, apply silently
doesn't" report. The week's full yield: /dl check (general health + issue
verdict), /dl debug ls (dry run + capture window + both timelines), the
load beacon, command receipts, the file-channel machinery (handoffs +
requests, stamped/watched/idle-gated), three field-established laws (the
chain law; files are the reliable channel; the engine is the reliable
executor), and one bug that was never dlac-specific: any two-state Ashita
system trusting the command bus between its own states has this failure
mode. NEXT: Henrik's ruling -- lockstyle execution moves engine-side
completely, addon becomes editor/preview, files become the only wall
crossing. Design handoff: docs/design/lockstyle-engine-move.md (the grill
agenda lives in its section 6); tracked as the GitHub issue referenced in
that document's issue link once filed.

## The pivot REVERSES: lockstyle goes ADDON-resident -- the Apply button injects its own 0x053 (2026-07-23, addon 2026.07.23m, issue #81 / PRD #80)

**Theme:** the grill (2026-07-23) reversed the engine-move direction. Henrik's
ruling: *"Lockstyle should really be able to exist on its own 100% within
DLAC"* -- the addon has grown a central Arbiter and the Gear Oracle, and LAC is
now needed only to actually equip GEAR. Lockstyle is a purely visual feature
that equips nothing; coupling it to LuaAshitacast (so it dies entirely without
LAC and needs two-state debugging to support) was historical accident, not
necessity. Apply went engine-side when it called `gFunc.LockStyle`, but since
v42 it BUILDS the 0x053 itself and injects via `AshitaCore` -- the process-wide
SDK, available in every addon state. So the whole executor can come home.
PRD #80 stages the hand-over so no mixed-generation `git pull` window can
double-apply: **phase 1** = addon gains the executor, Engine (v109) untouched;
**phase 2** = pure Engine deletion, gated on field confirmation. This is the
first slice: the GUI Apply button, the narrowest real path, proving the one
unproven mechanic -- **outgoing 0x053 injection from the addon's own Lua
state**.

**Landed (issue #81):** `feature/lockstyleapply.lua`, the executor. It reads the
saved boxes table (the caller passes lockstyle's already-Profiles-resolved
`data` -- SAVED file, never the working copy), picks the box, resolves names to
ids against Owned gear (`gear.NameToObject` + resource fallback -- identical to
the Engine's `_lsResolvers`, because `dlac\gear` resolves to the same char file
in both states), builds the 0x053 with the pure core **relocated from the
Engine byte-for-byte** (`_lockstyleFrom` / `_lockstylePacket` verbatim -- the
Engine's copy stays untouched this slice, the two pinned byte-identical by the
new LAP parity tests), injects via `AshitaCore:GetPacketManager():AddOutgoingPacket`,
and stamps a sender-side send witness (`M._lsLastSend`). Two deliberate
divergences from the Engine's copy: the silent job gate is predicted through
the **Gear Oracle's one door** (`oracle.anyJobCanWear`) -- no `_lsStyleGate`
twin, the GRD guards forbid a second eligibility home -- and the weapon-category
warning + freeze-current read come from the Addon state's own worn source
(`oracle.wornItem`), never `gData` (the addon's shim carries no `GetEquipment`).
Player-facing chat lines are preserved VERBATIM.

**The button** (`feature/lockstyle.lua`) now calls `M._applyDirect(box)` -- a
DIRECT function call, no `queueCmd`, no request-file write, the command bus
untouched -- so addon load order can never silence it (the friend's original
"preview works, Apply silently doesn't"). **Bookkeeping is at the call site**
(the established law: an addon state never hears its own queued commands, and
same-state visibility of its OWN injected packet is unproven): `_applyDirect`
notes `lastBox` (keep-on-sub then remembers this box) and arms the zone guard
(`M._guardArm` -- the applied style survives zoning, the client's zone-in
auto-DISABLE swallowed exactly as today) DIRECTLY, never off observing its own
packet_out. **The pumps (OnLoad / keep-on-sub / town) and the typed
`/dl ls apply` handler STILL ride the Engine path this slice** (queueCmd + the
v109 request bridge -> `engineApplyHalf`); moving them is later phase-1 work.
Exactly one apply either way; no order quadrant double-applies (grep-provable:
the button path is queueCmd-free and request-free).

**Tests:** section LAP (23 checks) -- `_lockstyleFrom`/`_lockstylePacket` parity
vs the Engine (`dispatchM`) across the AG/AJ fixtures (all 136 bytes identical),
plus the live `apply()` driven through its injectable deps seam: injection,
byte-0 = 0x53, the styled count, the send witness, and each warning path (job
gate through a stubbed oracle door, weapon category from the injected worn
reads, unresolved-name EMPTY) asserted with the Engine's wording verbatim, plus
inject-failure and empty-box both reporting `ok=false`. Both loops green (2554
run_tests + 225 smoke_ui). No `dispatch.M.VERSION` bump -- no seeded-file
behavior changed (the Engine is untouched); `addon.version` date-bumped to
2026.07.23m.

**Deferred / flagged:** the Apply button TOOLTIP changed from "engine-side:
/dl ls apply -- needs LuaAshitacast loaded" to "applied by dlac itself -- no
LuaAshitacast needed" (now factually true); a player-facing string, flagged for
Henrik's sign-off in the PR. The ADR (0014) and the design-doc supersession
banner are the docs slice's job (PRD #80). **FIELD CONFIRM pending (Henrik):**
button apply on both machines + one LAC-absent demonstration. If the injection
itself fails => STOP; the superseded `docs/design/lockstyle-engine-move.md` is
the designated fallback (do not improvise one).

## Session "the absorption": dlac becomes its own equip engine (2026-07-23, feature/native-engine, dispatch v110â€“v119, addon 2026.07.23mâ†’y)

Henrik's morning curiosity â€” "could DLAC technically do LAC's job?" â€” was sized
(LAC 2.02 is ~5,361 lines; the engine's ENTIRE consumption of it is
`gFunc.EquipSet` + eight gData reads + the Handle* timing contract), ruled GO by
evening, BUILT the same day, and survived six field rounds before midnight. By
the Addendum-2 ruling on #80, `feature/native-engine` is THE development branch
and main is frozen as the stable fallback.

**The build (steps 1â€“6, a84ef5e..688a623).** (1) The storage-home seam:
`profiles.dataDir()/charRoot()/storageRoot()/charDataDirAt()` are the only path
composers; native home `config\addons\dlac\<char>\` (no `dlac\` level) behind
the install-wide Engine flag (`engine.lua`; broken file reads OFF); copy-only
migration + per-char auto-migration. (2) ~15 modules swept onto the seam
(check/debug/setmanager-jobPath stay legacy BY DESIGN â€” they diagnose the
bridge). (3) `gear/equipcore.lua`: the pure LAC-parity resolver +
0x050/0x051 builders (EQC*; the FlagEquippedItems short-circuit â€” displaced-only
sets are satisfied silence â€” is a REAL LAC pin). (4) `feature/equipengine.lua`:
the timing service â€” block outgoing 0x01A/0x037 â†’ Precast â†’ re-inject â†’
Midcast; LAC's completion formulas verbatim; 0x028 completion/interrupt (28787)
+ the pet stream firing `PetAction` at action START; resend dedup;
name-prefiltered bag scans; the coexistence TRIPWIRE (fingerprinted injections;
a foreign echo disarms loudly); refuses to arm inside LAC's state.
`ACTION_ROUTES` is the dispatch-point table â€” a future dispatch point is one
row. (5) dispatch v111: `engineActive()` widens every engine gate;
`engineEquipSet` is the one write seam; `M._nativeSets` replaces gProfile.Sets
(tick identity latch + `utils.rebuildSets` on the shim's cadence); LAC-bridge
machinery stays `inLac()`-pinned. `feature/nativedata.lua` supplies LAC-parity
gData (sig-scan vanatime/weather, storm override). (6) `/dl engine` command +
docs (architecture Â§ The Native engine).

**The maxmp boot saga (field rounds 1â€“6, v112â€“v119) â€” read this before
trusting any cached compute over a staged boot.** Round 1: the observer only
ran in the LAC tick tail and `mpLowMap` read gProfile.Sets directly â†’ v112
(the seam-hunting pattern: grep the automation's dispatch region for
gProfile/gState/gEquip and check the LAC tail behind the native `return`).
Round 2: a self-healing glimpse â†’ v113 (don't cache store-less results) â€”
INSUFFICIENT. Round 3: Henrik's /dl plan screenshots (lows 0, tags gone, a
phantom ammo band) â†’ v114 THE READINESS GATE (his spec: band order is a pure
function of manifest+sets+rules) + v115 widened to LAC mode on his attribution
note ("this was the case earlier as well" â€” the install latch races existed all
along; when Henrik says a symptom feels old, believe him). Round 4: the gate
passed while the world was still wrong â†’ v116 THE STABILITY LATCH (belief
requires two identical computes â‰¥2s apart) â€” DEFEATED by a stable-wrong state.
**Dead end, named: proxy-readiness attestations and self-agreement both lose to
a world that is wrong AND stable** (a flatten over a not-yet-live input is
hollow STABLY). Round 5: v117 instrument-first â€” the WARM TRACE
(`debug\mpwarm.txt`, one row per compute: latch verdict + world counts) + the
gear ordering gate. The trace caught it in ONE reload: 'BELIEVED setN=0 flat=0'
behind a "20 set(s) installed" print â€” the install-time flatten was empty and
the belief cache (keyed by TIME) outlived the real store arriving. v118: a
hollow install is not an install (refuse + retry); BOTH install branches
invalidate the belief (caches must be keyed by world identity, not time);
flatten counts ride the signature. Round 6: Henrik's trace showed the designed
boot verbatim â€” 12 refusals holding ~4.5s, then the first-ever belief granted
to the TRUE world. **"It works now."** v119 also lands Henrik's debug-folder
rule: per-char debug artifacts live in `<data home>\debug\` (the LAC-bridge
handoff files stay put â€” they die with LAC).

**The refocus (same evening).** Step 0 done: main (executor #86 + ADR 0014)
merged in (00e6f45; reconcile list applied â€” CONTEXT's Engine entry is
native-aware, the ADR-0014 boundary paragraph gained its one-state postscript).
#83 done (9214912): every lockstyle apply path is addon-resident natively â€” the
`queueCmd` apply funnel (town/OnLoad/keep-sub) and the typed handler route to
`M._applyDirect` (nil box = the marked one) because one state means a
self-queued command is heard by NO ONE; legacy paths untouched. **ADR 0015**
(3f86c3c) records Henrik's four rulings: legacy is a sunset (push migration
hard); new features are native-first (LAC is no longer a design input); dlac
never writes `<JOB>.lua` again but reads them forever (imports); new users
default native with a polite LAC-alive ask. Four phases: field rounds â†’ recruit
the roster â†’ graduation merge (+ legacy nudge) â†’ the deletion party (the bridge
machinery, the oracle twins, the inLac paths).

**Tests:** 2648â†’2671 checks (NE/EQC/EQE/NEB sections + main's LAP arrived in
the merge), 225 smoke, green Windows Lua + WSL lua5.4 at every commit.

**Deferred / next:** ruling-4 onboarding (first-run native default + LAC-alive
ask + a Setup path that never writes job files); the legacy-mode nudge banner;
Trigger Monitor's native feed; augment-string pins (`augmentStringsOf`); maxmp
tick+offset persistence (standing offer). FIELD CONFIRM pending: the three
native lockstyle paths (Apply button / town flip / typed apply). #84 (delete
dispatch's lockstyle machinery) is safe to dispatch â€” origin's branch is
current.

## Ruling-4 onboarding: fresh installs boot native by default; Setup never writes a job file (2026-07-23, feature/native-engine, addon 2026.07.23z, issue #87)

**Theme:** the "Deferred / next" item from the absorption session â€” ADR 0015
ruling 4 (new users native by default) plus ruling 3's Setup consequence (dlac
never writes a `<JOB>.lua` again) â€” built on `feature/native-engine`.

**The first-run decision is a pure seam.** `profiles.firstRunAction(flagState,
legacyPresent)` maps the flag file state (`'native' | 'legacy' | 'absent'`,
where a present-but-broken file counts as `'legacy'` â€” present, so never
clobbered) Ã— whether ANY character on the install has legacy dlac data
(`config\addons\luashitacast\<char>\dlac\`) to one of three actions:
`'respect'` (a flag is on disk â€” honor it, boot NEVER rewrites it, existing
users are never auto-flipped), `'legacy'` (no flag but legacy data present â€” an
existing user, stay legacy, write nothing), or `'write-native'` (no flag, no
legacy data â€” a FRESH install, born native). `profiles.firstRunInit()` runs it
once at boot (`dlac.lua` `maintainStorage`, before the native-mode branch) and
writes `native = true` only for the fresh case. The one trap avoided: a
directory-listing API that returns nil ("couldn't tell") must NOT be read as
"fresh" â€” `legacyDataPresent()` returns `present, scanned` and firstRunInit
declines to decide (retries next beat, not latched) when the scan failed, so a
transient fs hiccup can never wrongly flip an existing legacy user. A missing
`luashitacast\` dir lists as `{}` (the popen fallback) â€” a real "no legacy data"
answer, exactly the fresh install.

**Ordering matters:** because firstRunInit runs at the top of `maintainStorage`
and writes the flag before the `if prof.nativeMode()` branch, a fresh install is
native by the time the same beat reaches the seeding fork â€” so `seedCharFolder`
(the only writer under `config\addons\luashitacast\`) is never reached, and NO
file is created in the LAC tree. The decision is install-wide (no character
needed), so it lands pre-login on frame one.

**The LAC-alive polite ask, once per session.** `profiles.shouldAskUnloadLac`
is a pure latch: fed the live "is LuaAshitacast alive?" reading, it returns true
the first time that is true and then stays false for the session. Detection
(`dlac.lua` `lacAlive()`, best-effort) is the equipengine coexistence tripwire
having fired OR a legacy-home `modestate.lua` written in the last ~15s (a dlac
engine hosted inside LAC stamped it â€” native mode writes only the native home).
The ask names the exact command (`/addon unload luashitacast`); the tripwire
remains the hard backstop, so a detection miss only means the loud DISARMED line
arrives instead of the polite one.

**Setup goes native.** Under the flag, `setupui.migrateCurrentJob` routes to the
new `setup.setupNative`: ensure storage + seed the gear inventory + the four
base sets + starter triggers, all mode-aware (they resolve to
`config\addons\dlac\`), never clobbering an existing file â€” and writing **zero**
`<JOB>.lua`/shim/backup files (ruling 3: what is never written needs no backup).
The legacy migration writer (`migrateToCleanProfiles`) now refuses under the
native flag as a defense-in-depth guard, so no stray caller can breach the rule.
The GUI follows: `setup.needsSetup` keys the red Setup button on storage
existence (not the absent shim) in native mode, the Setup plan popup shows a
native-worded plan (no shim, no backup, no luashitacast writes), and the legacy
"not on the clean standard" migration nag stays silent under the flag. Job-file
imports (Sets "Copy from", Groups "Scan my Lua", the `backups\pre-profiles\`
corpus) keep reading the LAC tree READ-ONLY in both modes â€” untouched.

**Why no `dispatch.M.VERSION` bump:** `profiles.lua` is a seeded file and its
bytes changed, but the new functions are dormant inside LAC's state (called only
from the addon state's `dlac.lua`), so the engine's equipping behavior is
byte-identical â€” the staleness handshake has nothing to announce.

**Tests:** NO1â€“NO19 â€” the decision matrix, the once-per-session gate (fire â†’
latch â†’ reset re-arms), and the native Setup path (capture every write, assert
zero land under `luashitacast\` / on the `<JOB>.lua` shim / in `backups\`, with
a legacy contrast that still writes the shim). 2671â†’2690 checks, 225 smoke,
green Windows Lua + WSL lua5.4.

**Deferred / next (this arc):** the legacy-mode nudge banner (Phase C); Trigger
Monitor's native feed; augment-string pins; maxmp tick+offset persistence. FIELD
CONFIRM pending (Henrik, issue #87): a simulated fresh install (rename/park the
config dirs) boots native, asks about LAC if loaded, and Setup produces a
playable character with zero LAC-tree writes.

## Lockstyle executor polish: apply()'s result is bookkeeping's gate (2026-07-23, feature/native-engine, addon 2026.07.23za, issue #88)

The two review nits recorded on PR #86 (and #83), landed once #87's PR (#89) was
in and the dlac.lua collision cleared.

**`_applyDirect` conditions its bookkeeping on the executor's result.**
`lockstyleapply.apply()` returns `{ ok, ... } | { ok = false, why }`
SYNCHRONOUSLY, but the GUI Apply button's call site (`feature/lockstyle.lua`
`M._applyDirect`) used to note `lastBox` and arm the zone guard
UNCONDITIONALLY â€” before the call, inside a `pcall` that swallowed the return.
So a refused apply (an empty box, an inject failure) still taught keep-on-sub a
box the server never got and armed the guard around a style that never went out.
Now the note+arm ride `res.ok`: on refusal neither fires, and the reason (which
the executor already emits to chat) is also surfaced in the window's `_status`
line â€” a failed button apply is visible in the GUI, not only in chat. A
SUCCESSFUL apply is byte-identical to before: the same order (note `lastBox`,
then arm) with the same effect, because the executor reads `data`, never
`lastBox` or the guard, so moving the two below the call cannot change a good
apply. The executor-unavailable branch (`_laok` false) and a pcall'd executor
error are refusals too, each named in `_status`. Tests LAD0â€“12 drive
`_applyDirect` with a STUB executor so the `ok` flag is controlled rather than
derived from headless inject quirks; LAP + LGF stay green (LGF runs the whole
chain on the legacy queue path â€” `nativeArmed()` is false headless â€” so it never
touched `_applyDirect` and could not regress).

**`feature/lockstyleapply` joins dlac.lua's load-loop ledger.** The executor is
the one lockstyle module whose silent absence breaks Apply, yet it rode in only
transitively (required inside `feature/lockstyle`, guarded, `_laok`), so
`/dl check`'s module census could not name a broken or half-synced copy of it.
It now sits beside `feature\lockstyle` in the load loop, counted like its
siblings â€” a corrupt copy shows up as a NAMED failure in the census
(`check.lua` reads the ledger's `total`/`failed` dynamically, so nothing pins
the count). Bumped `addon.version` to `2026.07.23za` (the letters ran out at
`z`; `za` sorts after). No `dispatch.M.VERSION` bump: the touched files
(`dlac.lua`, `feature/lockstyle.lua`) are addon-only, not seeded â€” the engine's
equipping behavior is unchanged, so the staleness handshake has nothing to say.

**Tests:** 2690â†’2703 checks, 225 smoke, green lua5.4. FIELD CONFIRM pending
(Henrik): a button apply of an empty/unwearable box shows the `_status` refusal
and does NOT arm the guard; a good apply is unchanged; `/dl check` counts
lockstyleapply and names a corrupted copy.

## Onboarding v2: Setup is now the migration wizard; fresh installs auto-setup with zero ceremony (2026-07-23, feature/native-engine, addon 2026.07.23zb, issue #91)

**Henrik's ruling (same evening #87 landed):** Setup exists for exactly ONE
reason now â€” migrating a current *legacy* dlac user to native. New players get
the native engine automatically, with zero ceremony. This refines ADR 0015
ruling 4 (which #87 implemented as a fresh-install *boot* â€” flag auto-written)
by removing the remaining ceremony, and implements the Phase-C migration nudge
banner early. Recorded as the ADR 0015 addendum; architecture.md's Onboarding
section rewritten to "Onboarding v2".

**Fresh installs auto-setup at the login/job beat.** `setupui.autoSetupNative`
runs from `dlac.lua` `maintainStorage` in the native branch: when this
character+job's baseline is missing it seeds it silently â€” storage, gear
inventory, the four base sets, starter triggers (the existing `setupNative`
content, per job, idempotent, never clobbering) â€” apart from ONE friendly
chat/status line the first time anything lands. No Setup button, no popup, no
Commit for a new user, ever. A later login on a NEW job auto-seeds that job's
starters the same way (gear.lua is shared, not rewritten). The gates that
mattered: **never in legacy mode** (the very first check); **never before
`firstRunInit` resolves** â€” `maintainStorage` now captures its return and bails
on `nil` (couldn't decide yet), so auto-setup can't run against an unresolved
first-run; **never for a not-ready job** â€” `jobFile()` returns nil until
`GetMainJob` settles, so the id-0 `NON` login state (hard rule 11) seeds
nothing. Completeness is `nativeBaselineComplete` (storage + gear.lua + this
job's sets + this job's triggers), read through the same deps the seeders write
through so there's no torn view between write and verify. **Failure is a line,
not a ceremony:** if the baseline never lands (disk error), it names itself in
status/chat ONCE (a per-job `_autoWarned` throttle) and keeps retrying quietly â€”
it is never escalated into the Setup box. The self-healing shape: no success
latch â€” a complete baseline returns `'complete'` silently every beat (four cheap
reads), so a deleted file re-seeds on its own; only the failure *notice* is
latched, and it clears on the next success.

**The Setup button + popup become THE migration box.** `needsSetup` v2:
native â†’ always false (auto-setup owns fresh installs, nothing to migrate);
legacy with dlac data â†’ true (`setupui.hasDlacData` â€” the storage pointer, or a
pre-storage-move user's bare gear.lua). For that one user the red button is the
standing nudge (present all session until they flip), and the popup is a
three-part migration box â€” what you should do (migrate, then unload LAC + drop
it from autoload) / what Commit will do (copy ALL dlac data to
`config\addons\dlac\`, COPY-ONLY, flip-back-any-time, then write the flag) / why
(one engine must own your gear) â€” closing on the hard rule stated
verbatim-clear: **"It's either LAC or DLAC â€” never both at once. Once migrated,
do NOT run LuaAshitacast."** Commit is `setupui.migrateToNative`, the GUI twin of
`/dl engine native on`: `engineMigrateStorage` (copy-only) then
`setNativeMode(true)`, then the unload/reload checklist â€” and it refuses under
native (nothing to migrate). A flag-write failure after a good copy is reported
without leaving the player mid-migration: their legacy tree is byte-for-byte
untouched, so they lost nothing.

**What retired from the UI, what stayed in the code.** The legacy clean-shim /
ffxilac / per-job-plan Setup modes are gone from the button handler and the
popup (a legacy user's answer to ANY setup state is now "migrate to native" â€” a
broken shim is irrelevant the moment they flip). The in-window warning banner
rewords from "X.lua is NOT set up for dlac" to the migration nudge. The
underlying legacy writers â€” `migrateToCleanProfiles`, `migrateCurrentJob`,
`setupNative`, `jobSetupState` â€” stay in the code untouched: Phase D deletes
them, and `setupNative`'s seed helpers are the auto-setup content source
meanwhile.

**Tests:** NO20â€“NO42 (23 checks) drive it all against a nameâ†’content virtual
disk â€” the needsSetup matrix, auto-setup seeding + idempotence + zero-clobber +
zero-`luashitacast\`-writes + the new-job case + the not-ready-job gate + the
persistent-failure line, and the migration Commit's captured call sequence
(`migrate,flag:true`) + copy-only + checklist + native-refusal. 2703â†’2726
checks, 225 smoke, green lua5.4. No `dispatch.M.VERSION` bump: the touched files
(`ui/setupui.lua`, `ui/gearui.lua`, `dlac.lua`) are addon-only, not seeded â€” the
engine's equipping behavior is unchanged. `addon.version` â†’ `2026.07.23zb`.

**FIELD CONFIRM pending (Henrik):** a fresh-install sim logs into playable with
zero interaction; his real (already-native) install boots unchanged (no auto-setup
line on a set-up job); a legacy-mode boot (flag off) with dlac data shows the
migration box and Commit migrates copy-only.

## The button says what it does: Setup -> Migrate (2026-07-23, feature/native-engine, addon 2026.07.23zc)

**Henrik's ruling**, straight from his first field poke at Onboarding v2 (he
renamed only `config\addons\dlac\` -- the native home -- and the detector
correctly read his still-populated `luashitacast\<char>\dlac\` legacy tree as
"existing user, never auto-flip", test NO5 live in the field): *"For those like
me who has dlac profiles under config luashitacast, show a MIGRATE button (not
Setup) explaining what needs to be done, why and how."* The button only ever
shows for exactly that user (needsSetup v2: native -> never, legacy-with-data ->
migration offered), so the label now says its one job: **Migrate** (width 56 ->
84 per the themed-font law, ~9.5px/char + 16 or it clips). The legacy banner and
the docs sweep follow ("click the red Migrate button"); the box itself already
explained what/why/how (the three parts + the hard rule + the
files-stay-importable line). No logic changed; no dispatch.M.VERSION bump
(addon-only strings). The true fresh-install sim, for the record: rename BOTH
`config\addons\dlac\` AND `config\addons\luashitacast\` (a never-started-dlac
player has neither), unload luashitacast, reload dlac.

## The self-manufactured-evidence bug: an undecided boot must stay inert (2026-07-23, feature/native-engine, addon 2026.07.23zd)

**Field, Henrik's fresh-install sim round 2** (both dlac folders renamed --
config\addons\dlac\ AND the luashitacast\<char>\dlac\ legacy data): the Migrate
button appeared anyway. His diagnosis, verbatim-right: *"he is creating files
the moment it launches under the lac engine, then it detects the very same
files which makes him think that there is legacy."* The mechanics: whichever
first domino fell (in-game `ashita.fs.get_dir` returns NIL for a MISSING
directory -- the same shape as an API failure, while the headless popen
fallback returns {} so the suite masked it; or the flag write failing into a
directory io.open cannot create), every path funneled into the same hole --
`maintainStorage`'s undecided case fell through to `seedCharFolder()`, the
LEGACY seeder, the login gear scan wrote gear.lua into the legacy home, and
the NEXT beat's scan read dlac's own droppings as "existing legacy user".
Permanently: the files persist across reloads.

**The fix, defense in depth:** (1) **undecided holds EVERYTHING** --
maintainStorage now resolves `firstRunInit` first and returns INERT on nil: no
native branch, no legacy seeding, no writer of any kind until the decision
lands (it retries on the same watch; a held beat costs nothing). (2) **a
missing root is a definite answer** -- `legacyDataPresent` disambiguates a nil
root listing by listing the PARENT (config\addons\): luashitacast\ absent
there = the fresh install, scanned=true; present-but-unlistable or
parent-unlistable = genuinely can't tell. Seams `M._listDirs` /
`M._legacyProbe` make the matrix headless. (3) **the flag write grows a
belt** -- setNativeMode retries through shell mkdir when io.open fails
(io.open never creates directories; a fresh install has no
config\addons\dlac\ yet). (4) **the decision is LOUD** -- one boot line names
the action and its evidence ("fresh install -> NATIVE engine armed" /
"legacy dlac data found (Char_1234) -> staying LEGACY, the Migrate button is
the way over"), and both failure modes warn ONCE ("deciding nothing, WRITING
nothing, retrying") -- silence has no author; the next field round names its
own domino in chat.

**Tests NO43-NO49c** (2726 -> 2743 + 225 smoke, green Windows lua + WSL
lua5.4): the parent-listing disambiguation (missing/present/unlistable), the
evidence third return, the undecided nil+warn-once+never-latch contract, the
write-fail retry into resolution, and the loud lines' content. No
dispatch.M.VERSION bump (addon-only). Henrik's poisoned test env: the buggy
boot RECREATED luashitacast\<char>\dlac\ folders -- delete those (junk from
the bug; the real data is in his renamed folders) before re-testing.

## The onboarding goes quiet: a working boot says nothing (2026-07-23, feature/native-engine, addon 2026.07.23ze)

**Henrik's ruling, on field-confirming the fresh-install sim ("Works
perfectly"):** remove the debug texts -- the general player must not be told
that it is a first run, that the native engine is in use, or that gear needs
scanning (the inventory auto-syncs from bags; the instruction was wrong
anyway). Removed: the first-run decision lines (fresh -> "NATIVE engine
armed", legacy -> "staying LEGACY...") and autoSetupNative's success notice
("dlac is ready... Scan your gear"). The legacy nudge lives ONLY in the GUI
(banner + red Migrate button); a fresh install experiences nothing at all --
things just work. **The FAILURE warns stay** (undecided-scan, flag-write-fail,
seed-fail -- each once): they are invisible to a healthy install by
construction, and removing them would re-blind the next field case (silence
has no author -- for failures). Tests NO48d/NO49b now pin the SILENCE of both
resolutions. 2743 -> 2742 checks (the loud-line pins became silence pins
each), 225 smoke, green both loops.

## GRADUATION DAY: the native engine reaches main (2026-07-23)

**Henrik's call, after field-verifying both onboarding scenarios himself
("first time and LAC DLAC legacy"):** ready for main. Phase C of ADR 0015
executed the same day it was written -- `feature/native-engine`
fast-forwarded onto main (`d0736a0..4ae8665`, a strict-ancestor merge, no
conflicts by construction). **Main's freeze is over; main is the development
line again.** The graduation carries the whole native era in one motion: the
absorption (equipcore / equipengine / nativedata, dispatch v111-v119), the
storage home + Engine flag, the lockstyle pivot's completion (every apply
path addon-resident), native-first onboarding v2 (born-native fresh installs,
silent auto-setup, the Migrate button + box), ADR 0014 + 0015, and the whole
test growth (2742 + 225, green on all three loops -- the main push also ran
the first full CI over the branch-era work, since direct branch pushes never
triggered it). Legacy mode rides along as the flag-off fallback, formally in
its SUNSET window: the roster is native (Henrik daily, the friend confirmed),
the Migrate button is the standing nudge for any returning legacy-data user.
Remaining on the books: the sunset window itself, then the Phase D deletion
party -- issue #84 is its lockstyle line-item (never dispatch before Phase D).
The branch stays on origin as history, awaiting Henrik's delete.

## The great cleanup: zero hanging anything (2026-07-23, post-graduation)

**Henrik's rule:** no hanging issues or PRs now that the native branch is
main. Executed: #88 closed (shipped in PR #90 -- the PR just lacked the
auto-close keyword; a recurring pipeline gotcha), #84 closed as PARKED (the
Phase D lockstyle line-item -- ADR 0015's Phase D section is the deletion
list of record; reopen/refile when the sunset ends). Tracker: 0 open issues,
0 open PRs. Origin: NINE merged branches deleted (the graduated
feature/native-engine, five agent PR branches, three Gear Oracle stragglers)
-- main is the only remote branch. Local: seven merged branches + one stale
worktree removed (each verified in-main first); survivors are deliberate --
feature/autoacc (GM approval pending, the ONE live pre-native artifact,
never delete/push) plus storage-move + hidden-features (superseded,
Henrik's to delete). Confirmed in passing: the whole maxmp boot saga
(v112-v119) rode the graduation -- main's dispatch reads M.VERSION = 119.

## Session "E-Box Restock â€” the reusable E-Box client" (07-23 â†’ 07-24)

**Theme:** a grill-with-docs feature for Henrik â€” keep chosen items topped up from the
Crystal-Warrior **Ephemeral Box**, near a box, on a click â€” and, on Henrik's call, carve
out a REUSABLE E-Box client FIRST ("we will probably make many more, good idea").

**Design (grilled, R1-R11):** two lists that combine â€” a **Character** list (staples:
food, silent oil, prism powder, tools) âˆª the **current-Job** list (job consumables:
RNG/COR ammo, DRG angons); a same-item Job **Target** OVERRIDES the character baseline
(specificity). Per-item Target ("keep N"); fetch the **Shortfall** = Target âˆ’ on-hand.
On-hand = the FIELD bags {Inventory 0, Satchel 5, Sack 6, Case 7} (Henrik: "usable in the
field"); room = free Inventory(0) slots. **The load-bearing ruling â€” slot-loss safety:**
the E-Box withdraw lands each stack in a FRESH inventory slot (per item AND per stack â€”
24 fire crystal @ stack 12 = 2 slots), never merging into an existing partial on arrival,
and the box does NOT protect you: too few slots = LOST items. So a fetch costs
âŒˆfetch/stackSizeâŒ‰ slots and must NEVER over-draw; under space pressure => greedy partial,
job-first, remainder reported. A floating nudge near a box (hover = plan, left = Fetch all,
right = open panel). 100% CW-only â€” invisible AND inert off-CW at every surface.

**Architecture (ADR 0016):** exactly ONE 0x1A4 client, `feature/eboxclient.lua`, because
0x1A4 is a party line and the server-load NFR (Henrik: operators care) needs coalescing +
throttle to be STRUCTURAL, not per-feature â€” a shared multi-category counts cache,
one-request-in-flight, a global min-gap, per-category stale windows, a near-box gate (query
ONLY near a box). The shipped AutoAmmo E-Box code (`eboxammo`) was FOLDED onto the client as
a thin category-15 adapter (public surface unchanged, so `ammoui` needed no edit; its own
packet handler removed so the two features never race). Every future E-Box feature is a
CONSUMER, never a second client â€” it's in architecture.md's Central-services table.

**Landed (main `975896a..b2fab33`, addon.version 2026.07.24b):** `feature/eboxclient` (EBC*
tests) Â· `feature/restockwatch` (config + the pure `_merge` union/override + `plan`
slot-budget; RS* tests) Â· the `eboxammo` fold (EB* reworked to adapter-parity) Â·
`ui/restockui` panel wired into `ui/automationsui` (CW-gated row + detail arm) Â· a GUI
layout pass (wider number columns for 10000+, "keep"â†’"Target", type-only input, no clipping)
Â· the floating nudge (`M.nudge` + a gearui d3d_present hook + `gearui.openAutomation` +
`/dl restock`) using Henrik's crate art (`assets/ebox.png`) Â· the CW-gate closed on the
command too. Design doc `docs/design/ebox-restock.md`, ADR 0016, CONTEXT.md glossary
(E-Box / E-Box client / E-Box Restock). 2801 headless checks green (Windows lua + WSL lua5.4).

**Field-confirmed (Henrik, 07-24):** AutoAmmo parity after the fold ("Works"); the panel +
planner + Fetch all + E-Box detection ("fetch all also works, as well as the E-box
detection"); the nudge ("Works perfectly and looks awesome"). One field-test-only assumption
stands: withdrawals land in Inventory(0).

**Ops note (the parallel-session hazard, lived):** built entirely alongside a parallel
chocobo-digging session (`feature/probe-dig`) that repeatedly FLIPPED the shared checkout
between branches â€” a `git checkout` round-trip briefly showed pre-fold content and tripped
the "modified on disk" reminders (a false "everything reverted" scare, resolved by reading
the reflog: all commits were safe on main). Lesson reaffirmed: on a shared checkout,
`git status` / `git branch` before every edit, stage ONLY your own paths, and commit promptly.
## Chocobo: the fourth idle-gear sibling (2026-07-23, issue #95, engine v120)

**The gear half of the Chocobo automation** (parent PRD #93; docs/design/chocobo-gear.md),
built as a fourth sibling to craft/HELM/fishing but the SIMPLEST of the four: no target, no
category, no packet protocol, no proximity, no bar. Turning it on equips your best
**riding-time gear** (idle-only) and the panel reports the total riding time = `30 + summed
ChocoboRidingTime` minutes (the server computes duration as `1800 + mod*60` seconds at whistle
time). The set is the six slots **Main/Neck/Body/Hands/Legs/Feet**, scored per-slot best-first
by the catalog's `ChocoboRidingTime` (already a shipped stat -- no data table, no generator);
the **Chocobo Wand is included in Main** even though it takes the weapon slot, with a panel note
to equip the set before whistling. Same shape as the siblings: `feature/chocowatch.lua` writes
`<char>\dlac\chocostate.lua { enabled, at }` (session-only `enabled`, off at login); the engine
overlays `dlac:AutoChoco` on Default only, standing aside Engaged/Dead; the manifest gained a
`choco` block (AUTO_FMT 14 -> 15) and `dispatch.M.VERSION` moved 119 -> 120.

**The floor-invariant bug it surfaced.** Chocobo registers a `Chocobo` Arbiter claim (default
rank below Fishing, above the Triggers floor). Adding a NEW known row to `ARB_ORDER_DEFAULT`
exposed a latent bug in `M.arbOrder`: the append-missing pass walked an existing arbstate file's
rows first (which end in `Triggers`, the floor) and then appended the missing known row --
landing Chocobo AFTER `Triggers`. A claimant below the floor never wins a slot the idle set
already dresses, so every existing player's Chocobo would have equipped nothing. Fixed by
pinning the `Triggers` floor LAST unconditionally in `arbOrder` (and the arbwatch fallback) --
a floor invariant that is correct regardless and lets any future claimant be added cleanly.
Tests AR/AB updated for the 9-row order; the `rank 8` -> `rank 9` /dl-why lines followed.
New tests CH1-15 (engine overlay), S139e-n (chocoui/chocowatch load + the reference-set 84-min
total), S179b-d (the manifest choco block); the autogear golden gained the `choco` block +
fmtver 15 (regenerated, reviewed). 2757 + 238 green both loops. **Player-facing names ("Chocobo",
"Total riding time", the note) are the issue's own wording, pending the maintainer's sign-off.**

## Chocobo: dig rank + guide scaffold (2026-07-23, issue #97)

**The dig half's foundation** (parent PRD #93; docs/design/chocobo-dig.md "The rank
model + guide scaffold"): the dig-rank model both search tabs will read, plus the guide
panel scaffold â€” the live moon/day/weather header and the general dig-success line â€” hung
below the existing riding-gear section. Not the tabs themselves, and not the timing
auto-detect (that later slice is gated on the `/probe dig` calibration from #96).

**The rank is masked, so it is assembled from three stacked sources, only one exact.**
`GetCraftSkill(11)` returns the server's `0xFFFF` sentinel forever (confirmed by `/probe
dig`), so `feature/digrank.lua` (a PURE, headless-tested brain) resolves the rank from:
a **manual** dropdown seed; a one-way **ratchet** floor (`>= from digs`) raised whenever an
`Obtained: <item>` chat line maps â€” via the shipped `digdata` â€” to a dig-rank requirement
above it, never lowered; and a live **server** read that stays silent under the mask but
would win, labelled `reported by server`, if a build ever unmasks index 59. Only the server
source carries `exact = true`. `chocowatch` owns the glue â€” the persisted `rankManual` /
`rankFloor` in `chocostate.lua` (they survive relog, unlike the session-only `enabled`), the
throttled skill read, and an always-on `text_in` hook (the rank baseline is independent of
the riding-gear toggle).

**The "never lie" rule got its one home.** `digrank.gate(req, rankState)` returns `ok` /
`locked` / `dimmed`: an over-rank item is HARD-locked only against an EXACT rank, and merely
DIMMED against a manual/ratchet estimate. That is the single seam the by-item / by-area tabs
will call for every row, and the reason a scaffold shipped before real zone data can be
trusted not to mislead.

**The scaffold degrades honestly.** `feature/vanamoon.lua` computes moon phase from the
Vana'diel day (84-day cycle, illumination 0 New â†’ 100 Full); `chocoui.clock()` reads day +
weather from `nativedata` and the moon from vanamoon, each guarded so a failed weather scan
shows "unavailable" without taking the header down. The general dig-success line uses a new
`digcalc.averageSuccess` (mean combined success across enabled zones) â€” nil while `zones` is
empty, so the panel says "run gen_digdata.py" rather than print a fake 0. No `dispatch.M.VERSION`
bump: the engine reads only `enabled`/`at` from `chocostate.lua`, and the added rank fields do
not change seeded-file behaviour. New tests DR1â€“44 + gate DR40aâ€“f + VM1â€“10 (digrank/vanamoon
pure math), DR41â€“44 (averageSuccess), S139oâ€“s (the headless scaffold seams). 2878 + 243 green.

**Flagged for the maintainer.** (1) `vanamoon.OFFSET` (the community-standard epoch 26) wants
a one-time field cross-check against the in-game moon; if the ore-gate percent must be
server-exact, swap the linear curve for the 84-entry LSB moon table (isolated in vanamoon).
(2) Every new player-facing string â€” the rank ladder labels, the source labels, the header /
note wording â€” is proposed, pending row-by-row sign-off.

## Chocobo: By-item tab (2026-07-24, issue #99)

**The second dig-guide tab** (parent PRD #93; docs/design/chocobo-dig.md "The By-item tab"):
a fuzzy item search â†’ the matching diggable items â†’ the selected item's every zone + pool
with rank + the two live odds, greyed by the SAME `digrank.gate` rule the by-area tab uses,
plus the item â†” area cross-link. It reuses the by-area row/odds rendering and adds **no new
odds math** â€” two pure `digcalc` seams feed it.

`digcalc.itemIndex()` is the fuzzy-search source: every unique pool item (deduped by id, its
`minRank` the lowest requirement across the zones it drops in) PLUS the conditional
crystals/clusters/rocks/ores **synthesised** from the `cond` rule tables (8 each = 32 entries)
so "Fire Crystal" / "Chunk of Fire Ore" are searchable even though they live in no static
pool. `digcalc.itemSources(entry, rank, mu, clock)` prices the selected item's every source:
a pool item's rows carry `{ zoneId, zoneName, pool, req, onHit, perDig, locked }` (sorted by
â‘¡ per-dig descending, the by-area order); a conditional item's rows carry the per-zone
`{ condKind, chance, minRank, condition, clockActive, rankOk, active }` â€” crystals/rocks span
every enabled zone (`allZones`), ores only the 9 ore zones. Both are PURE (the clock is
passed in) and fail soft. `chocoui.itemList`/`itemRows` wrap them and stamp `digrank.gate`.

**Two things worth remembering.** (1) An item can be BOTH a static pool drop AND a conditional
â€” Fire Crystal is listed in some zones' pools *and* is the Fire-weather conditional â€” so the
index carries a DISTINCT entry for each, keyed `pool:<id>` vs `condKind:element`, never by name
(a name-keyed lookup collided in the first test pass and masked the conditional entry). (2) The
cross-link reuses the `uihost.selectTab` idiom on this panel's OWN tab bar: a zone click sets
the by-area state and requests a one-shot forced `By area` selection via a probe-guarded 3-arg
`BeginTabItem` (`ImGuiTabItemFlags_SetSelected`), so a binding without the flag just drops the
jump instead of crashing (hard rule 2). All-zone conditionals show a note rather than 26
identical clickable rows; ores list their 9 specific zones as cross-link buttons.

No `dispatch.M.VERSION` bump (digcalc/chocoui are addon-state only; the engine reads just
`enabled`/`at` from `chocostate.lua`). New tests BI1â€“BI27 (the two pure seams) + S139zâ€“S139aa4
(the composed seams) + the render-balance section now driving the By-item tab with the search
filled. 2937 + 259 green. **Flagged:** the new player-facing strings (the `By item` tab name,
the `Item:` / `needs X` / `Conditional drop` / `Diggable in â€¦` labels) are proposed, pending
the maintainer's row-by-row sign-off with the rest of the guide's wording.

## Chocobo: dig feature field-hardening â€” GUI polish + the item-ratchet fix (2026-07-24, PRs #112â€“#119)

The whole PRD #93 was shipped; this block is Henrik field-testing it and me hardening what
broke in-game. Three threads:

**Timing auto-detect â€” round â†’ floor.** The first pass inverted the zone-inâ†’first-dig delay
with `round`, but lag only ever makes a dig land LATER, never earlier. A lagged Expert dig at
11â€“14s rounded DOWN to Veteran. Fixed to a **floor bracket** `clamp(12 âˆ’ floor(t/5))`: each 5s
rung reads as its FASTEST rank (10â€“14.9s â†’ Expert). Henrik confirmed by reset + dig. A secret
`/dl choco reset` (rank back to Amateur) exists for exactly this re-testing.

**GUI polish â†’ the panel-text standard.** Henrik: the panels have "WAY too much text, hard to
use." New house rule (now `docs`-wide as panels are touched): **underline the key label and put
the explanation in a HOVER**, never an inline paragraph; cut obvious mechanics entirely. Built
`uistyle.helpLabel(im, text, tip, col)` (PR #115) â€” an underlined "link" (guarded draw-list)
whose tip shows on hover, taking the caller's imgui so it stays binding-agnostic + headless
(US1â€“6). The riding-gear + dig-guide panels were rebuilt onto it; the search moved to the TOP
as two buttons (**Area** / **Item**) opening their own windows (in an applicable digging zone
Area opens on your current zone), with itemâ†’area cross-nav and a back step â€” scrolling to search
at the bottom was the complaint.

**The item ratchet was deaf (the long one).** Henrik: reset, dug items above Amateur, rank
didn't move. Two wrong cuts before the fix:
- I assumed the dig-obtained line doesn't reach `text_in` and hooked a **packet** â€”
  `messageSpecial` â†’ `0x02A` TALKNUMWORK, item id at raw offset `0x08` (a first draft even had
  the wrong packet, `0x02D`; an adversarial review caught it). It didn't fix it (PR #118).
- Henrik pointed at the **hgather** digging addon (`Ashita/addons/hgather`, working). It reads
  dug items straight off `text_in` after `string.lower()`:
  `string.match(message, "obtained: (.*).")` â€” so the line **is** ordinary chat; the packet hunt
  was the wrong channel. Our `parseObtained` matched `[Oo]btained:` (only the leading `O`
  case-flexed), so the real line's casing/prefix slipped past â€” and an unclassified dig is
  neither `obtained` NOR a completed dig, so ONE miss silenced BOTH the ratchet and the timing
  read on every item dig. Fixed to match `obtained:` **case-insensitively**, name sliced from the
  original for display case (PR #119, `DR21f`â€“`DR21i`). The names were never wrong â€” the data
  holds the full forms ("Chunk of Gold Ore"/737 etc.); Henrik's "gold ore" was shorthand. The
  packet path stays as a gated, fail-safe, idempotent second source.

**Key decision / durable lesson:** when a working addon already handles the event you're
reverse-engineering, read it before theorising from server source â€” hgather answered in one grep
what two packet guesses did not. And match chat-tag text case-insensitively (lower a copy);
a fixed-case Lua pattern silently misses real messages. **All PRD #93 slices are now
field-confirmed working in-game.** Known gap: conditional crystals/rocks/ores are synthesised
(no static pool row) so a dug conditional doesn't ratchet yet â€” a harmless under-claim, follow-up.
`addon.version` 2026.07.24j; `run_tests` 3044 + `smoke_ui` 284 green (Windows lua 5.4.6 + WSL
lua5.4).

## Idle hobbies: one shared bar, one active at a time, one Auto HELM switch (2026-07-24, ADR 0017)

**FIELD-CONFIRMED 2026-07-24 (Henrik), merged to `dev` (PR #123).** In-game: the
shared hobby bar and its selector, the active-tab mark + lock-while-active, the
floating badge, and Auto-HELM-as-the-one-switch all work as intended.

**The ask (Henrik):** only one of **Craft / HELM / Fishing / Chocobo** idle should
run at a time; arming one should stand the others down; a floating point should
name the active one and offer to turn it off; when nothing is armed, the badge
disappears.

**The tension, surfaced before building.** These four *co-claim* by deliberate
design â€” ADR 0012's Amendment (step 1.5, above) removed the pre-Arbiter
"newest-armed exclusivity" and recorded it as a **dead end**. So the request looked
like a reversal of a documented ruling. It is not â€” the dead end was a **claim-side**
rule that reached into `M.dispatch` and silenced a peer's *slots* at dispatch time
(the AR10 PUP case: arming HELM yanked the fishing rod out of Range). What Henrik
asked for sits at a different seam entirely.

**The seam (why it is not the dead end).** Exclusivity lives at the **enable
toggle**, not the claim. A tiny coordinator, `feature/idleexcl.lua`, is called from
each watcher's `setEnabled(true)` (and helm's `setAutoHelm(true)`). Because only one
hobby is ever *armed*, the Arbiter never sees a conflict among the four â€” the engine
is untouched, and AR8/AR9/AR10 (which stub state files and never call `setEnabled`)
stay green unchanged. The enable seam is the one choke point every surface funnels
through â€” bar, panel pill, Automations row, quick-menu flip, `/dl` command â€” so
hooking it there caught all of them without touching a single UI file.

**Two rounds, and the model Henrik settled on: lock-while-active, not auto-disarm.**
Round 1 shipped auto-disarm (arming one stood the others down). Henrik refined it to
**lock-while-active**: arming a second hobby while one is active is **refused**
(`guardActivate` returns false + a one-line hint), never a silent takeover. You turn
the running hobby off, then arm the next. `idleexcl` went from `onActivated` (disarm
the peers) to `canActivate`/`guardActivate` (refuse the arm).

**One shared hobby bar (`ui/hobbybar.lua`).** Round 1 kept the three separate bar
windows; round 2 unified them (Henrik: "the same window shared between them all, so
you can easily switch"). The three bar bodies were extracted verbatim into
`<bar>.renderContent(availW)` (their own `d3d_present` windows deleted); one window
with a `Craft | HELM | Fishing | Chocobo` selector draws the selected one. Chocobo â€”
which never had a bar â€” got a minimal tab. The **active hobby's tab is marked** (green
+ trailing `*`, Henrik's ask) and while a hobby runs the selector **locks** to it
(other tabs dim, un-clickable) â€” the UI mirror of the enable-layer refusal. A pure
`toggleVisible` on the header button (vs the hobby-specific `toggle`) so the bar can
always be dismissed even while locked.

**One HELM switch: Auto HELM.** HELM had two toggles â€” manual "Set HELM Idle"
(always-on while idle) and "Auto HELM" (equips near a Point). Henrik: "confusing to
have two, and Auto works best." Manual idle was removed from every surface (panel,
quick menu, bar); Auto HELM is the sole switch and `idleexcl`'s HELM member keys on
`isAutoHelm`. The manual `setEnabled` primitive stays in the engine (unwired) so
nothing downstream breaks. Trade taken deliberately: HELM gear now equips only near a
gathering Point, never "always on regardless of location".

**The badge (`ui/idlefloat.lua`) stays** â€” names the one active hobby with an Off
button when the bar is closed; self-gates on `idleexcl.getActive()`, so visibility is
derived (position persists via uiflags `ifx/ify`, visibility never does).

**Consequence, taken deliberately.** The AR10 combination â€” HELM's armor *and* a
fishing rod in Range at once â€” is no longer expressible, because Fishing and HELM
can't both be armed. That is the point: these are competing hobbies now, made
transparent by the bar's active mark and the badge. The claim-side dead end stays
dead; this revises only the UX convenience ADR 0012 had accepted.

**Key decision / durable lesson:** re-introducing a removed behaviour is safe when it
lands at a *different seam* than the one that failed â€” here the enable toggle
(features decide what's armed) vs. the claim layer (the engine decides who wears each
slot). Also: unify sibling windows by extracting each one's body to
`renderContent(availW)` and giving one shell the chrome + a selector â€” the shared
`onOffSwitch` pill already proved the bars were the same shape. And the new
`hobbybar` got an `HB*` render-stack-balance smoke (the floatgear S50 lesson: a
selector's PushStyleColor/PopStyleColor mismatch is a silent client crash).

New `feature/idleexcl.lua`, `ui/idlefloat.lua`, `ui/hobbybar.lua` (all on the
source-scan roster); `craftbar`/`helmbar`/`fishbar` reduced to `renderContent`.
`addon.version` 2026.07.24m; `run_tests` 3081 + `smoke_ui` 296 green (Windows lua
5.4.6 + WSL lua5.4). IE\* (lock/HELM-auto) + HB\* (render balance) checks.

## weatherMatch trigger condition (2026-07-24, ADR 0018, engine v121)

**Theme:** a new trigger flag `weatherMatch` â€” true when the action's element equals
the **current weather** element â€” built grill-with-docs, the first feature under the
new branch model (`feature/weather-match-condition` off `dev` off `main`).

**Landed:** `weatherMatch` (Precast + Midcast, tier 30, true/false polarity).
`weatherMatchesAction` (dispatch.lua) reads `gData.GetEnvironment().WeatherElement`
(cached on `ctx.wel`); nil action-element / Non-Elemental / unreadable weather matches
NEITHER polarity. **DISTINCT from `dayWeatherBonus`** (the obi's signed day+weather net
WITH opposition) â€” this is plain weather equality, no day, no opposition. The env read
is **storm-aware**: `GetEnvironment().WeatherElement` already overrides zone weather with
the player's own storm buffs (`nativedata.lua`, storm ids 178-185 single / 589-596
double â†’ all 8 elements), so a Scholar's own Firestormâ†’Fire nuke trips it for free. The
buff gate (e.g. Celerity/Alacrity, whose cast-time bonus is **weather-only** â€” no day,
no opposition) is left to the player to compose via existing `buff` conditions. WM1-21
green Win + WSL.

## Release: idle-hobby + weatherMatch promoted to main; first full `feature â†’ dev â†’ main` cycle (2026-07-24)

**Theme:** the branch model ([[HANDOFF]] hard rules) went live end-to-end. Two
field-confirmed features rode the chain to a stable `main`, and origin was cleaned up.

**Landed:**
- **idle-hobby** merged `feature/idle-hobby-exclusion â†’ dev` (PR #123, merge `3465d68`),
  then `dev â†’ main` (ff) at Henrik's go-ahead after in-game confirmation.
- **weatherMatch** was still only on its own branch (never on `dev`). Merged
  `feature/weather-match-condition â†’ dev` (merge `5379884`) â€” one conflict, the
  `dlac.lua` version line (`m` idle-hobby / `n` weatherMatch) **resolved to `2026.07.24o`**
  so the combined build is identifiable â€” then `dev â†’ main` (ff).
- **Result:** `origin/main` == `origin/dev` == **`5379884`**, `addon.version`
  **2026.07.24o**, combined **3102 run_tests + 296 smoke_ui** green (Windows + WSL).
- **Git cleanup:** 14 merged-PR remote branches pruned (the chocobo/dig/ebox #101-#121
  set + idle-hobby #123); origin now holds exactly `main` + `dev`. Local parked branches
  `feature/autoacc` (GM pending) and `feature/storage-move` kept, never merged.

**Durable lesson:** the model's promotions are Henrik's call, one at a time, each after a
field check. A feature that "should be on dev" may not be â€” verify with
`git log dev..feature/x` before assuming `dev â†’ main` carries it (weatherMatch was NOT on
dev when its `dev == main` looked done).

## Header Menu + Settings, and the Mode library (2026-07-24 â†’ 07-25, ADR 0019)

A `/grill-with-docs` session on four Henrik asks. Two shipped, one was corrected mid-grill,
one was researched and deliberately parked.

**The branch model changed first.** The morning's `main â†’ dev â†’ feature/<slug>` rule lasted
half a day. A branch checked out in the working tree cannot be checked out anywhere else, and
several Claude sessions plus Henrik share ONE checkout â€” so feature branches made the sessions
fight over the tree. The chain is now just `main â†’ dev`, everything commits on `dev` directly,
and Henrik accepted the cost explicitly: **`dev` promotes as a whole or not at all.** Cloud
agent runs keep their own branches (they clone their own workspace and cannot collide).

**Header Menu + Settings.** The header was eight right-aligned buttons; it became Profiles
(left) and Menu + Migrate (right). Lockstyle / Macro book / Hobby bar / Teleports / Level
moved into a Menu popup along with a new Settings panel and a debug-only developer section.
**"Reload LAC" was deleted outright**, not relocated â€” legacy LAC is no longer a design
consideration, and both of its red-arm sites in setupui are legacy-only, so under the native
engine the button could never go red. The one thing kept OUT of the menu is the in-flight
ABORT: transient state must not hide behind a click, which is the same reasoning that killed
Reload LAC. Settings gave the three `/dl`-command-only flags (autosync, view_ids, debug) their
first visible home, and added *Open the dlac window* â€” one setting with three values rather
than two booleans, because "off but also on job change" is a combination someone would tick.

**A recurring bug class, three times in one session.** Lua resolves an unknown name to a
GLOBAL, which is valid syntax, loads fine, and only errors when the line actually RUNS. It bit
via an invented `helpLine()` helper, and nearly again where `renderModeBox` (defined above the
Mode-library code) would have resolved `mlCapture` to a nil global. The existing smoke suite
could not catch either, because it only *load*-tests UI modules. Hence **smoke section MLU**,
which drives the real render path against a stub imgui â€” mutation-verified. When touching a
large UI chunk, dumping `_ENV` references with `luac -l -l` is a cheap way to see every global
a file actually touches.

**The Mode library (ADR 0019)** gave Modes the Blueprint treatment: a per-character
`modes.lua` outside Profiles, stamped onto whichever job you are on, shareable as text. The
design decision worth remembering is that a `Modes` section is a **map keyed by name**, so
stamping an existing name is an overwrite, not a duplicate â€” hence Append (default, merges,
can never strand a reference) vs Overwrite (routed through a pre-commit reference window).

**Recon corrected the ADR twice, and both would have shipped a broken feature.** (1) The
cascade needs TWO ref-walkers: trigger conditions and set-entry gates are separate stores with
separate files and serializers, and a dead gate on the Sets tab renders *byte-identical* to a
live-but-inactive one, so a half-cascade would never have been noticed. (2) The ADR claimed a
stranded value "makes the engine complain on every dispatch" â€” false on both counts; that line
is in the `/dl mode` command handler, and the real consequence is **silence**. A cycle also
re-seats itself on the commit's trigger reload, so only a demotion to toggle needs an explicit
clear. Lesson: an ADR written during design is a hypothesis about the code until someone reads
the code.

**Also fixed while building:** Append would delete a cycle's values when a toggle was stamped
onto it â€” violating its one guarantee. And `modeSetRefs`, the half of the cascade that DELETES
gear rows, was a gearui chunk-local with no headless coverage; its decision logic moved to
`modeslibrary.gateRefsInSet` (tests MG*), with gearui now bailing entirely rather than
half-running if the walker is unavailable.

**Parked, with the research recorded:** the NIN Daken/Sange/Yoru Shuriken work
(`docs/design/auto-ammo.md` Â§8) â€” Henrik's call, it needs a real NIN to field test. It uncovered
two live bugs on main in the process (the WS-ammo leak at Preshot, and Special-vs-trigger having
no safe configuration), both documented there rather than fixed blind.

## Session "/dl naked" (2026-07-25, on `dev` â€” engine v122, addon 2026.07.25f)

**Theme:** Henrik asked for LuaAshitacast's `/lac naked` â€” *"Be sure to use the claim arbiter,
maybe use locks?"*. The arbiter half was right; the locks half was the interesting question,
and the answer is no. Recorded as [ADR 0021](adr/0021-naked-is-a-claim.md).

**The argument against locks was already in the codebase, written for pins.** `pinOverlay`'s
header explains why a pin is an overlay and not a `/dl lock`: *a lock only makes the engine
ignore the slot, so anything else that strips the piece wins â€” and the state leaks when a
session ends abnormally.* Naked is that argument with the sign flipped. Concretely, a lock
**cannot undress you** â€” `equipResolved`'s lock branch writes `W()[slot] = nil`, never a value,
so it only ever *withholds*. A lock-based naked is therefore strip-once-plus-fence, and the
fence is the weak half: `M.locks = {}` is re-executed by every engine **self-swap** (the 2s
content check that carries a `git pull` into the running engine), Pins outrank Locks and punch
straight through, and three unrelated buttons release it. Arming it would also destroy the
player's own locks â€” the Incursion-T3 state `/dl lock set` exists for.

**So naked is a Claim, and the payoff is bigger than avoiding those bugs.** Because the claim
is recomputed every dispatch, every way the server can refuse a strip â€” dead or in a cutscene,
mid-ranged-attack, the level-sync settle holding the weapon slots â€” **heals on the next pass**
instead of leaking a dressed slot forever. And precedence becomes the player's for free: at
rank 1 it beats everything, and *"naked except my pins"* is a **drag** in Claim Priority, not a
code path. That is ADR 0012's promise (a new claimant = one rank row + one claim table) actually
paying out; nothing in the engine grew an arm.

**Two traps, both of which would have shipped silently.**

1. **A new rank row must not be APPENDED.** `arbOrder` restored missing rows at the bottom,
   which is correct only for a row that belongs there (Chocobo, v120). Every character who has
   ever opened the Priority section has an `arbstate.lua` listing the rows that existed *then*,
   so **every** new claimant arrives missing from real files â€” and appended, Naked would have
   ranked 9th, under Locks, losing every slot it exists to win, for everyone except a fresh
   character. Fixed with one positional law (insert before the first present row that outranks
   it) that subsumes the old append, the Chocobo case and the Triggers-last floor pin, rather
   than the per-row exception table this was heading toward.
2. **The claim must use PROPER-CASE slot keys.** `equipcore.SLOT_ID` is case-sensitive and
   LuaAshitacast's `GetEquipSlot` is not â€” so a lowercase claim works in LAC and strips
   *nothing* natively. Broken only in the mode that actually ships.

**The optimization that is actually a correctness bug:** claiming only the slots that currently
hold something. It looks free (it would also stop LAC re-scanning the bags every pass, since
`FlagEquippedItems` can never mark a set containing a `remove` as satisfied). But the apply loop
walks rank **low to high**, so an unclaimed slot keeps whatever a *lower*-ranked layer wrote into
the buffer that pass â€” drop the empty slots and a MaxMP battery lands in every slot the previous
dispatch just cleared. The claim is always all 16.

**Lifetime turned out to be one line plus a guard, and the obvious homes were both wrong.**
`M.nakedArmed = (M.nakedArmed == true)` â€” the `M._loadStamp` idiom â€” because `M` is `rawget(_G,
'__dlacEngineRoot') or {}`: the same table across a self-swap, a fresh one in a new Lua state.
So the flag survives a `git pull` and dies at Reload LAC. **It does NOT die at a relog**, which
the first draft of the ADR asserted it did: an Ashita addon survives a logout (pinwatch's header
already says so, which is why pins re-key on the character dir) and LAC never clears
`package.loaded` either, so neither engine gets a new state when you change characters â€” and
re-keying on charDir would not help, since a same-character relog gives the same dir. The tick
disarms on the character-select read (`GetMainJob()` nil/0) instead â€” and on a **job change**
too, once Henrik ruled it should not survive one (main job only, the same signal the maxmp drop
already used). Worth remembering as a general trap: **"a fresh Lua state" and "a new session"
are not the same event in Ashita** â€” an addon survives a logout, so any module-level flag needs
an explicit disarm rather than relying on state teardown.

**Henrik's rulings on the behaviour, after the build:** no persistence through a logout, no
persistence through a job change, and the TP wipe is *acceptable* because the command is
deliberate â€” so nothing is built around it. He also noted, fairly, that these were his calls to
make and should have been asked before the build rather than presented after it. The rejected homes are worth remembering: `M.modes` would collide with a
user-defined Mode named `naked`, re-gate their Dynamic sets on every toggle, and inherit
`loadModeState`'s restore window â€” whose only relog protection is the documented
`GetMainJob() == 0` race, i.e. a coin flip on whether you log in naked. A Statefile would have
been strictly worse (it persists across everything).

**No dispatch is kicked on arm/release.** The 0.4s tick is the only Default entry point carrying
the zoning, player-action, pet-action and sync-settle gates; a command-path dispatch would fire
a full re-equip inside a cast or mid-zone to save 400ms, against a claim that is standing anyway.

**M.dispatch had been called ZERO times by the test suite** â€” every existing test drives a pure
seam beneath it, so the wiring *between* the seams was covered by nothing, and an out-of-scope
local in Lua is not an error but a silent nil global. Naked is the cheapest possible driver for
it (flag on, nothing else armed â†’ all 16 removes must still reach the equip door), so NK26 now
executes the real `M.dispatch` end to end and asserts no local leaked to `_G`. Mutation-verified
both ways.

**The smoke harness was lying about the Equipped tab.** Its `renderEquippedTab` drives are
`pcall`'d without checking the result, and the render had been dying partway through on a
`gearfmt` helper whose captured imgui stub lacked `PushTextWrapPos` â€” the earlier checks passed
because they only read side effects from *before* the throw. Fixed so the render completes, and
the new `NKU*` checks assert the pcall result, which is the only thing that catches the
nil-global class in that file (mutation-verified: renaming `S.setEngineNaked` fails NKU3/NKU3b).

**Three field notes that are the server's doing, not dlac's:** unequipping a weapon **zeroes
your TP** and drops Aftermath (Main/Sub/Range with no incoming item; the instrument exemption
cannot apply to an unequip); **Free equip / `/lac disable` silently defeats naked in legacy
mode**, because LAC's `PrepareEquip` drops the unequip for any `gState.Disabled` slot â€” hence
the warning and the disabled switch; and a **lockstyle applied while naked bakes permanent
nudity** into every unnamed visual slot (unnamed slots freeze to `equippedId`, which is 0, and
style 0 renders empty), so `/dl ls apply` is refused while stripped.

**Found, deliberately NOT fixed** (so a regression has one suspect, per ADR 0012's own migration
ruling): `/dl lock set` is broken in **native** mode. Its `rawget(_G,'gEquip')` bracket is nil in
the addon state, so the equip falls through to the unbracketed path and writes into
`equipengine`'s buffer â€” which only `fireEvent` flushes, and `fireEvent` opens by clearing it.
The set evaporates on the next tick. Its own commit.

**Implementation review found two more that would have shipped.** (1) The lockstyle refusal was
written into the *engine's* apply half â€” which `dispatch.lua`'s `/dl ls` branch pins behind
`if not inLac() then return; end`, i.e. **dead code in native mode**, the mode that ships. The
door that actually runs is the addon-resident `lockstyle._applyDirect`, which every scripted
apply funnels into â€” town transitions, OnLoad restore, keep-on-subjob, all with no user action.
(2) The relog gap above. Both were found by reading the *callers* of the guarded function rather
than the function; the lesson is the same one twice â€” **guarding the door you happened to be
looking at is not guarding the feature.**

**Two testing notes worth carrying forward.** `M.dispatch` had never been executed by the suite,
and naked is the cheapest possible driver for it (flag on, nothing else armed â†’ all 16 removes
must still reach the equip door), so NK26 now runs it end to end and asserts no local leaked to
`_G`. And a "test seam" that the production code calls as a **file-local** is not a seam at all:
`_applyDirect` had to be changed to call `M._nakedArmed()` before NK29 could stub it â€”
mutation-verified in both directions, which is the only way to know a new test can fail.

## Session "a locked set is a claim" (2026-07-26, on `dev` â€” engine v124, addon 2026.07.26c)

**Theme:** the bug the naked session found and deliberately left ("its own commit") turned out
not to want a fix. It wanted deleting. Recorded as
[ADR 0022](adr/0022-locked-set-is-a-claim.md).

**Why it was invisible, which matters more than the bug.** `/dl lock set` was inert in native
mode: `rawget(_G,'gEquip')` is nil in the addon state, so the equip fell to the unbracketed path
and `equipengine`'s next `bufferClear` wiped it â€” then it locked all 16 slots onto whatever you
were wearing and printed success. Two things hid it. First, **three other unbracketed
`M.dispatch('Default')` calls in the same file have the identical flaw and are harmless** â€”
`installSets` twice and `/dl mode` â€” because Default is idempotent and re-fires every 0.4s, so
the next tick heals them. `/dl lock set` was the one site where that is structurally impossible:
the locks it installed were exactly what stopped the next dispatch from equipping. Second,
**every `/dl` subcommand was tested by grepping `dispatch.lua` for its own name** (NK23 says so
outright: the handler only registers inside `engineActive()`, false headlessly, "so the whitelist
cannot be driven â€” pin it as SOURCE instead"). The command was present, spelled right, and
whitelisted. So the first commit was a test harness, not a fix: arm the native flag, re-load
dispatch, capture the registered handler, and call `/dl` commands with the game closed.

**The design was Henrik's, and it went somewhere I did not propose.** I offered a new `Held`
Arbiter row at rank 2. He pushed back on the premise â€” *"I am personally also a bit confused to
why we aren't simply using lock when it would do what we needed, why we must create new
categories for every function"* â€” and he was right: to a player "lock" is one word, and the
Priority panel's tooltip already described `/dl lock`, the Equipped tab and the Sets tab as one
row. So it rides the **existing Locks row**. `arbResolve` already returned "slot â†’ item **or**
LOCK_HELD", so the row carries real item names for held slots and the veto sentinel for plainly
locked ones; the only new machinery is an `applyClaim['Locks']` closure, which a veto never
needed. **One thing genuinely cannot be a lock and is worth not re-deriving**: a lock cannot put
gear on. `equipResolved` writes `W()[slot] = nil` and never a value. That is why the old command
had to equip first, and why the hold has to be a claim internally even though it is a lock to the
player.

**I then proposed moving `Locks` above `Pins` and was overruled, correctly.** Henrik had said
"whatever happens, that slot is locked (besides naked)", which is not what the default order
does â€” `layerRespectsLocks` is false for Pins too. His ruling: *"Pins needs to be above locks,
cause pins are always on demand and is universally understood to be there when needed."* So
`ARB_ORDER_DEFAULT` is untouched, and this change alters no precedence at all â€” which also
avoided a split rollout, since `arbOrder` keeps the user's order for any row their `arbstate.lua`
already lists, so a new default would only have reached players who never opened that panel.

**Frozen at arm, and the distinction that makes it safe.** *"Once you lock, it shall be constant,
like with naked. Even if you lock a set then change it, it should not change what you wear."*
Freezing means the **instruction**, never the outcome: `dlac:` markers collapse to concrete
entries once, so a locked obi cannot follow the weather â€” but the claim still re-**locates** those
names in your bags every dispatch, because freezing container+index would strand the hold the
first time a bag shuffled, which is strip-once-with-no-retry again. His ruling also deleted three
consequences I had listed for a live re-read (no store lookup per dispatch, no "the set stopped
resolving" drop path, no live-edit surprise) and collapsed the fill policy out of the hot path
entirely: all four commands became four *builders* producing one identical claim shape.

**A missing piece leaves its slot LOOSE, not empty.** *"That's better than an empty slot, is it
not?"* â€” yes, and it corrected a sloppy claim of mine in the same breath: I had said a loose slot
means the engine fights the server, which is wrong. Inside Incursion the server refuses every
equip regardless; outside it refuses none. What is true is narrower and pre-existing: any equip
the server silently drops is re-proposed next dispatch, because `planSet` compares against what is
*worn*.

**One lifetime rule, added after the fact.** *"I don't want locks to outlive a relog, it should
not outlive a main job change nor a log. It should not be saved. Same with naked."* Naked and a
locked set already behaved that way; plain slot locks did not, **and only by accident** â€” nothing
ever watched them, so they rode straight through character select. Before this session an engine
self-swap happened to wipe them, which *looked* like a lifetime rule and was really a bug (a
`git pull` unlocking your gear mid-Incursion). Fixing that accident in its own commit is what left
the real gap visible. `M.nakedWorldWatch` became `M.worldWatch` (old name kept as an alias â€” the
seeded LAC-side engine calls it) and now drops all three.

**A field report that was not a bug, worth carrying.** *"I can lock the DT set on Mindie, on WHM,
but doesn't feel like he releases it."* Cause: a leftover test trigger on idle re-equipping DT.
The generic lesson is that **a hold that looks stuck is indistinguishable from a trigger
re-equipping the same gear** â€” check the Triggers tab before the lock; `/dl why` names the winner.
The diagnosis question that would have split it in one line was "does the Sets tab button say
`Unlock` or `Equip & Lock`?", because in native mode there is no hot-swap (`trySelfSwap` is
`inLac()`-gated), so stale code was the other live hypothesis.

**And the tooltips were wrong in a way worth naming.** *"There is TOOOOO much text and description
straight out of this conversationâ€¦ this is minimalistic and every word matters."* Correct: I had
pasted the design reasoning into the hover. Everything cut had a home already â€” precedence is
Claim Priority, release is the Equipped tab, the missing-piece list is said in chat at the moment
it matters. The Sets tab button also became a **Strict / Loose** popup rather than firing strict
blind, which gave `set-loose` its first GUI home. That popup is the least-covered thing in the
change: the Sets tab render has no smoke drive, so `LSP*` pins it as *source*, which can only
prove the `OpenPopup`/`BeginPopup` ids agree â€” the failure that would otherwise register a click,
open nothing, and log nothing.

**Testing note worth carrying forward.** Every new check in this session was mutation-verified in
both directions, and it paid twice: reverting the dispatch bail guard fails six checks (the NK26
lesson â€” a lone claim with no triggers is exactly the path a bail guard swallows), and one of my
own assertions was simply wrong. I claimed modes survive a self-swap on the module table; they do
not. They are reset by the same re-execution and heal from the `modestate` mirror on load. Locks
never could â€” `__locks` is display-only and deliberately never restored â€” which is precisely why
their fix had to live on the table instead of in the mirror.

## Session "the hobby bar reaches the searches" (2026-07-27, on `dev` â€” addon 2026.07.27a)

**The ask, and what it actually was.** Henrik, pasting a note he could no longer see:
*"In the hobby bar, the fishing menuâ€¦ most things are available just fine in the hobby bar,
except for fishing, but we don't want to overdo it. Please add a button to open the fish
automation directly from the fish tab in hobby. Please do the same with fishing."* Fishing
twice â€” the second was Chocobo, which the code could have guessed: those are exactly the two
tabs whose bodies admitted the real controls lived elsewhere (Chocobo printed *"Dig rank,
guide and by-item search: Automations > Chocobo"* in grey; Fishing's target line was a label
whose tooltip said to go to the panel). Craft and HELM are self-sufficient in the bar.

Then the ask grew, and the growth was the interesting part: *"technically if we could open up
a menu to search for target fish from the hobby bar, reuse that search body windowâ€¦ maybe
problematic to use same windows that spawn from different places?"*

**The answer to that worry, which is now a written invariant.** It lands on the *draw*, never
the *opener*:

> Any surface may OPEN a floating window; exactly one place may DRAW it.

Two `imgui.Begin()` calls on one window name in a frame do not error â€” ImGui **appends** the
second body into the same window. Content renders twice, ids collide, a shared InputText
buffer gets written twice a frame. Silent, and it looks like a UI bug rather than a crash
(the floatgear S50 class). So openers set a module-owned flag and never render; gearui's
`d3d_present` is the single draw site, sitting *above* its `M.visible` return so every one of
these windows outlives the main box. Written into architecture.md; **Floating window**,
**Panel** and **Hobby bar** went into CONTEXT.md, which had no UI vocabulary at all â€” which
is precisely why the request needed three rounds of grilling to pin down.

**Chocobo cost almost nothing** because 07-24 had already done the hard part: the Area/Item
dig searches were floating windows, opened by two panel buttons that did nothing but set
flags. Those bodies became `chocoui.openAreaSearch` / `openItemSearch`, the panel now calls
them, and so does the bar â€” one behaviour for both surfaces rather than a copy-paste of "land
on the zone you're standing in, and close the other window".

**Fishing was a real extraction.** `TARGET FISH` was ~180 lines inline at line 376 of a
663-line panel â€” buried in exactly the way the Chocobo search had been fixed for. It moved to
`fishui.renderTargetBody`, wrapped by `fishui.renderSearch`
(`Fishing -- Target fish###dlac_fish_target`, 760Ã—520). The extraction was clean because
`sel` â€” the query buffer, the viewed fish, the expanded-spots flag â€” was referenced *only*
inside that block; nothing above or below it touched the picker's state. The body re-derives
db / owned counts / skill / worn Fish+ instead of inheriting the panel's locals, so it has one
contract for every caller.

**Three design calls worth keeping.** The bar's target name **is** the button rather than
gaining a labelled one beside it â€” the rod and bait names one row below have worked that way
since field round 5, so the tab gained zero widgets, which is the least "overdone" reading of
the request. The panel's section was **replaced**, not duplicated: two live copies would have
put one `sel.q` buffer behind two InputTexts. And the fish panel finally uses the shared
`craftbar.onOffSwitch` pill â€” it was the only one of six panels with a hand-rolled text
switch, and the comment above it named the reason (*"label shortened so the row survives Make
target + target + Clear"*), a workaround for the very row that just left.

**What the tests caught, and what they now cover.** The first build failed `HB3.choco` â€”
7c's stub imgui had no `SmallButton`, which is the section doing its job. More importantly,
`fishbar.renderContent` and the whole target body had **never been executed by any test**: 7c
stubs the bar with a no-op and section 7 only reaches fishui's pure status half. That is the
craftbar lesson of 7d, repeated on a second file. New smoke `FS1-FS19` drive the real window
and the real bar â€” including the wire that matters, that clicking the target name reaches the
opener, and that `no target fish` is clickable too (or a fresh character has no way in).

**Not field-tested.** Two things only live play can answer: whether 760Ã—520 gives the spot
list enough room (its bait column sits at `availW * 0.55`, ~50px tighter than the panel gave
it), and whether three pills â€” bar, window, panel â€” read as convenient or as clutter.

### Addendum, same day â€” tab art (`2026.07.27b`)

Henrik: *"Are you able to remove the text for all the tab titles, so we can replace them
with 30x30 pixel icons instead? Are you able to use this picture for chocobo digging?"* â€”
with one chocobo image attached. `assets/` had eight craft glyphs and four HELM glyphs but
no single Craft, HELM or Fishing icon, so the honest answer was *yes, and here is the gap:
you have art for one tab of four*. His call: **new art for all four, one at a time** â€”
*"I just want to see how one of them would look with that art, I'll give you more for the
other tabs later once I see."*

So the mechanism is built to accept art incrementally: a tab with
`assets\hobby\<Name>.png` draws as a 64px icon, a tab without keeps its **text button**.
Dropping `Craft.png` / `HELM.png` / `Fishing.png` in beside `Chocobo.png` converts them
with no code change. That fallback is also the old menuui rule â€” a texture that fails to
load must leave a labelled button, never a mystery 30px hole.

**Two things colour cannot do once a tab is art.** The text tabs carry both *selected* and
*armed* in the button colour; tinting art recolours the art (a green wash turns a yellow
chocobo olive), and recognising the icon is the entire point. So selection rides
**brightness** â€” the craft-glyph idiom â€” and armed rides a literal **green frame** drawn on
the window draw list. The frame colour is `0xFF00CC00`, which reads green whichever byte
order the binding packs, so the armed marker cannot come out red on a different imgui build.

**The asset.** 1408Ã—768 RGBA with a genuinely transparent background, art occupying
551Ã—634; styled as pixel art but gradient-shaded inside the blocks, so it downsamples
smoothly rather than going to mush. Cropped to the art, centred in a square with a 6%
margin (never distorted), LANCZOS to **128Ã—128**, drawn at 64. Shipping double the draw
size puts the GPU on mip level 1 â€” a clean 2:1 box filter, as sharp as shipping 64 â€” and
leaves headroom to grow the tabs again without regenerating every file. (The first cut was
64 drawn at 30, matching the 40Ã—40 craft/HELM glyphs; Henrik wanted them at least twice as
big, so both numbers doubled -- and the tab gap went 4px â†’ 6px, because the armed frame is
drawn 2px outside the icon and would otherwise nearly touch its neighbour's art.)

**Testing note.** Headless there is no d3d, so `filetex.handle` always returns nil and every
tab takes the text path â€” the icon branch would have shipped with zero coverage while the
suite stayed green. `HB15-HB19` stub the loader so exactly ONE tab has art, which is both
the real shipping state and the mixed row most likely to break. Both new behaviours were
mutation-verified: disabling the icon path fails three checks, removing only the armed
frame fails exactly one. The stub's own first cut had the classic bug it exists to catch â€”
`btns` captured by a closure declared above it, a silent nil global â€” and it failed
loudly rather than hiding.

**Craft.png, and the alpha lesson (`2026.07.27d`).** The second piece of art arrived on a
white page rather than a transparent one â€” *"I haven't cleaned it up as much but I think you
may be able to do it?"* The naive fix, keying out white, would have **punched holes in the
eyes**: this chocobo has white sclera and white highlights on its metal, and a colour key
cannot tell those from the page. So the background is removed by a **flood fill from the
image borders** â€” only white *connected to the edge* is background, and anything the dark
outline encloses survives. 812,033 pixels went; 3,700 near-white pixels were kept because
they were enclosed. The fill threshold is deliberately generous (bright AND unsaturated), so
the anti-aliased fringe between page and outline goes with it: at 128px a hair of erosion is
invisible, whereas a white halo on the bar's dark background is not.

Worth a number for next time: measuring the mean min-channel of the partial-alpha edge
pixels catches a halo objectively â€” the chocobo reads 22.6, the smith 88.3, and the
difference is genuine light-grey metal (hammer, chainmail, anvil) rather than a fringe, which
the zoomed composite on a dark background confirmed. Do both: the number tells you where to
look, the composite tells you whether it matters.

**The full set, and what a flattened preview costs (`2026.07.27e`).** The remaining three
arrived twice: first as screenshots of a transparency preview â€” **checkerboard baked into
the pixels**, alpha 255 everywhere â€” and then, after I said so, on white pages. Both were
processed and compared at 128px on the bar's dark background, best-of-each kept.

White won for **Fishing** and **Digging**: crisper line, hook and float, cleaner dirt
specks. The checkerboard version won for **HELM**, and the reason is worth keeping. The
miner's lamp beam was *semi-transparent* in the original, so on the checkerboard it carried
the checker pattern straight through it â€” visibly mottled at zoom. But that same modulation
is a **signal**: build the checker grid (period measured at 22px, tones 211/241), compare
the two parities in a local window, and any pixel where they still differ is either
background or something translucent over it. Opaque art modulates by ~0 whatever its colour,
so the pickaxe, the eye whites and the fishing float were never at risk. Flood that from the
borders and the beam comes off cleanly. On the white page the same beam is just an opaque
cream blob no colour threshold could separate from the art â€” tried at four saturation
windows, it survived all of them.

So: **a flattened checkerboard preview is harder to key than a white page, but it encodes
which pixels were translucent â€” and sometimes that is exactly what you need.**

**Hover text.** Henrik: *"Just show simple terms. Crafting / HELM / Fishing / Digging."*
The three-branch tooltip (which hobby is armed, which to turn off first) is gone: the green
frame says the former, and the pill that actually refuses says the latter in chat at the
moment you try it. A hover on a picture only has to answer "what is this?". `TABS` now
separates `n` (the player-facing word) from `img` (the asset basename) â€” the art is a
digging chocobo, so `Chocobo.png` is the right file name while "Digging" is the right word.
`HB20` pins the exact four strings, because that is the kind of text that grows a sentence
back.

**Field verdicts, and one question that only looked answered.** Two of the three open
questions came back the same day: three pills â€” bar, window, panel â€” is *"Perfection"*,
and the armed green frame *"Looks great"*, so the two calls that had no precedent to lean
on (a switch on three surfaces; a frame instead of a colour, once colour belongs to the
art) are both settled in favour of what shipped.

The third did not, and the way it failed is the useful part. Asked whether the target
window's 760Ã—520 default gave the spot list enough room, the answer was *"if you're talking
about the icons, looks great!"* â€” the icons were on screen, the window never had been. Three
"looks great"s in a row is exactly the shape a false confirmation takes: the verdicts are
genuine, but they answer the surface in front of the player, not the one in the question. So
it stays recorded as UNSEEN rather than confirmed. A question that names a surface the
player has not opened cannot be answered by looking at the one they have â€” and the fix is to
say how to reach it, not to ask again.

**The window landed, and the field found something older (`2026.07.27f`).** The target
window came back approved â€” *"very satisfied with how it opens a new window and search for
the fish, instead of having to do it solely WITHIN the fish automation menu"* â€” and the
760Ã—520 default drew no complaint, so the width worry closes unchanged. What the run
surfaced was not in the new work at all: *"I cannot target the end result without clicking
on the bait, I would like to be able to click on the whole row. But that has been there
since start, I just haven't complained about it yet."*

He was right. The spot row rendered `[ISOLATED] | place | bait` but only the **bait cell**
was a Selectable â€” a ~6-character hit box at 55% across a row you read left-to-right, so
the most natural click, on the place name, did nothing at all. It shipped that way with the
original fishing feature and survived five field rounds unreported, because the person who
built it knew where to click.

The fix is the shape `automationsui.autoRow` has always used: a full-width Selectable
FIRST, then every column drawn over it with an **absolute** `SameLine` â€” absolute because
`SameLine(0)` means "after the previous item", which for a full-width Selectable is off the
right edge. The three per-cell tooltips (rivals / bait+affinity / monster) merge into one
row hover, since there is now one item to hover.

Worth carrying: **a hit target smaller than the row it belongs to is invisible to whoever
built it.** No test could have caught this one either â€” the old test clicked the bait
Selectable and passed. `FS9b/FS9c` now assert the row's hit target is a bare `##isorow`
and that no bait-labelled Selectable remains, which is a claim about the SHAPE of the
interaction rather than about whether a click works.

## Session "the Xvs field day: three engine-era fixes, born-native, purge Phase 1" (2026-07-27, dev â†’ main e6ea704, then dev â€” addon 2026.07.27g â†’ j, engine v129 â†’ v131)

**Theme:** Henrik's friend (Xvs) updates dlac and *nothing equips at all* â€” the GUI sees
every set, the engine sees none. One field day later: two ancient onboarding traps and a
load-order contract from the LAC era are dead, users are born native unconditionally
(ADR 0025), and the LuaShitacast purge (Henrik's ruling) has its plan and its first
executed phase.

**Landed (promoted to `main` the same evening, `e6ea704`, field-confirmed by Xvs â€”
"Everything is working perfectly now"):**

- **v130 â€” the native flatten no longer waits for the GUI.** Every dispatch utils lookup
  read `package.loaded['dlac\utils']` bare ("loaded first in the LAC state" â€” the job
  shim's first require). The native state has no shim and *nothing* loads utils at boot:
  installs refused `flatten produced no sets (world not settled)` every 0.4s forever, the
  refusal nil'd `M._nativeSets` (GUI fine â€” it reads files; `/dl lock set` finds nothing;
  zero equips), and a session healed only when a gearui picker's own lazy
  `pcall(require)` happened to run. Hence the field shape "DRK works, BLU/COR don't":
  per-SESSION, not per-job â€” a reload broke DRK too. Mindie's own mpwarm.txt opens with
  the same wall every boot, healed in ~1.6s by GUI habit â€” the "~2s of designed boot
  refusals" lore was this bug all along. Fix: `utilsModule()` lazy require at all five
  sites (cycle-safe both states). Tests RQU0-2 drive the real `/dl sets reload` through
  the boot shape. Diagnosis method worth keeping: zip the user's whole char home and
  replay the exact engine path headless with the run_tests stubs â€” clean run = the
  runtime differs, not the data.
- **2026.07.27h â€” dataDir holds while the first run is undecided.** Xvs's *clean*
  reinstall (both config trees deleted) still got "migrate to native": the 07-23 fix held
  maintainStorage's own writers, but `profiles.dataDir` kept composing the legacy home
  during the undecided window, so the login gear scan planted `gear.lua` under
  `luashitacast\` and the next beat read dlac's own file back as legacy evidence â€”
  manufactured evidence, round two. dataDir now answers nil until firstRunInit latches
  (addon state only: the LAC state's presence IS the legacy verdict).
- **2026.07.27i â€” ADR 0025, born native, always.** Henrik: "users start in native mode by
  default, regardless if there are dlac files under luashitacast conf." Flag absent â†’
  `write-native` unconditionally; the boot never scans for legacy data (the can't-tell
  limbo is unreachable); an explicit flag on disk stays honored â€” `/dl engine native off`
  is the only road to legacy; flag-less legacy data becomes a migration source
  (engineAutoMigrate carries it in). Supersedes ADR 0015's "never auto-flip" for
  flag-less users.
- **The WS-menu mystery closed as a side effect.** The 07-26 diagnosis stands (server
  0x0AC rebuilds the ability/WS tables on Main/Sub/Range changes and latent flips; an
  open menu dies in the rebuild) â€” what the sick engine changed was the COLLISION RATE:
  store dying/reinstalling all session = full re-equip volleys at arbitrary moments.
  Healthy engine, narrow swaps, no noticeable collisions. Field: gone.

**Landed (on `dev`, addon 2026.07.27j / engine v131 â€” Henrik field-running it now):**

- **The LuaShitacast purge: plan + Phase 1** (`docs/design/lac-purge-plan.md`; Henrik's
  ruling with the keep-list "import from the job files, group (table) and static set
  import"). Phase 1 executed: **nothing in dlac writes under
  `config\addons\luashitacast\` anymore.** The 5s seeder, the shim writer (recognizers
  stay), Setup's job-file writes (both modes), `PROFILE_TEMPLATE.lua`, the LAC-alive
  polite ask, and the *entire* engine self-swap (`swapWanted`, `trySelfSwap`, the
  `__dlacEngineRoot` handshake) are deleted. `M.migrate` (kept, Henrik's call) now leaves
  originals in place â€” inert, importable, no shim rewrite, no mixed-tree write. The
  "`M.x = {}` at file scope is wiped by every self-swap" hazard class is extinct; X0 pins
  that a set `__dlacEngineRoot` is ignored.

**Key decisions:** bare `package.loaded` lookups are load-order contracts â€” grep for them
first when something "works in one state, dies in the other"; a per-job-looking field
report can be per-session (ask "does a reload break the working job?"); legacy evidence
demoted from verdict to migration source; Setup writes no job files in either mode;
migrate carriers stay, `/dl engine` goes status-only in Phase 2, the engine flag retires
in place in Phase 2.

**Worth carrying:** dlac manufactured its own legacy evidence TWICE through two different
doors (the seeder 07-23, the gear scan via dataDir 07-27) â€” when a verdict can be decided
by files your own writers create, the verdict is wrong by construction; ADR 0025 removed
the verdict rather than guarding a third door. And the accidental medic pattern: a lazy
`pcall(require)` in a GUI picker was silently repairing every session that touched the
right tab, which made a total engine failure look like a flaky per-job bug for days.

**Pinned next (the coming days):** field-confirm + promote the Phase 1 batch (27j); then
purge Phase 2 â€” legacy MODE dies (the dispatch diet: 16 `inLac` sites, 44
`gProfile`/`gFunc` refs, `/dl engine` status-only, flag retired in place, dataDir loses
its legacy branch) on its own quiet day; Phase 3 native-aware surfaces (#131 dies, every
"Reload LAC" string dies); Phase 4 keep-list hardening (allowlist grep test + a field
round importing all three ways); Phase 5 docs sweep. The full roadmap with per-phase
detail lives in `docs/design/lac-purge-plan.md` and HANDOFF "What's left" item 0.

## Session "the purge, all the way down" (2026-07-27 late, on `dev` â€” addon 2026.07.27j â†’ l, engine v131 â†’ v133)

**Theme:** Henrik: *"Can't you just go all the way to phase 5, I really just want this
to die."* All five purge phases executed in one sitting, suite-gated, phase-sized
commits (`e478817`, `8b5e8fd`, `58c75e0` + docs).

**Landed:** Phase 1 â€” the seeder, shim writer, Setup's job-file writes, the LAC-alive
ask and the ENTIRE engine self-swap (with the `__dlacEngineRoot` handshake and the
"`M.x = {}` wiped by self-swap" hazard class). Phase 2 â€” legacy MODE whole:
`nativeMode()` constant true, flag retired in place, first-run machinery deleted,
`inLac()` + the gProfile/gFunc world out of dispatch (âˆ’1063 lines), `/dl engine`
status-only, end-to-end rigs re-pointed at the native equip door. Phase 3 â€” `/dl check`
and debug.lua read the NATIVE home (**#131 closed**: the reader finally reads where the
writer writes), every "Reload LAC" string became `/dl reload` or died, the last LAC
resurrection (`/dl profile migrate go` queueing `/addon reload luashitacast`) died,
legacy job files are READ-ONLY. Phase 4 â€” every module-local legacy path fallback died
(gearimport Ã—2, gearexport, augments, statefile, gearui Ã—2, debug); the PRG1/2
allowlist guard pins that a `\luashitacast` string literal exists ONLY in the
keep-list readers (profiles, setmanager, lockstyle, macrobook, gearoptim) â€” it caught
three stragglers on its first run. Phase 5 â€” dlac.lua's header, HANDOFF's mental model
and hard rule 4, architecture.md's purge banner.

**Worth carrying:** the literal-form discriminator â€” in source bytes a PATH STRING
carries `\` while a comment carries `\`, so a guard scanning for `\luashitacast`
polices code without tripping on history. And the guard-first payoff: write the
allowlist test BEFORE declaring a sweep done; it found what three grep passes missed.

**Awaiting:** Henrik's field beat on `27l` (equips, a commit, `/dl check`, `/dl engine`,
and the three-way import round), then promotion. Suites at 3815 + 584, green on both
interpreters, at every phase boundary.


## Session "the level decides which rung" (2026-07-27, on `dev` â€” addon 2026.07.27l â†’ o, engine v133 â†’ v134)

**Theme:** Henrik, on his DRK: *"even though I made a list of bolts on autoammo and
enabled it is not equipping automatically... When I went from level 50+ to 8 it didn't
equip any bolt, then I leveled up to 10 it did not equip blind bolt."* AutoAmmo's
ladder knew what the WEAPON could fire (v128) and nothing about what the PLAYER could
wear. Grilled to a design, built in three commits (`41432db`, `401a6bb`, `4d6bb12`),
field-confirmed the same day.

**Diagnosed from artifacts, not theory.** His live `ammostate.lua` held Acid Bolt 15 /
Blind Bolt 10 / Crossbow Bolt 1, best-first â€” exactly what the panel's own *Sort by
level* button produces â€” and his DRK sets carried a real Range ladder, so a crossbow
WAS worn and v128's no-weapon gate never fired. Three of the four inputs were right;
the fourth was never asked for.

**THE LAW THIS PAID FOR, and it is not AutoAmmo-specific:** *an overlay collapses a
ladder to ONE name before the equip layer ever sees it.* A set hands `equipcore` a slot
with candidates and its level walk picks a rung; an overlay hands over
`{ Ammo = "Acid Bolt" }` and there is no rung 2. So any gate an overlay does not apply
ITSELF becomes a total, silent failure downstream â€” no fallback, no message, no trace.

**The trap that nearly shipped a dead fix.** The first design said read `MainJobSync`.
Henrik tests with the **level override** (`/dl set level main N`), which is honoured by
the set flatten, the virtual-slot resolver, gearoptim and gearui â€” but NOT by
`equipengine`, whose `snap.level` reads live memory. Reading `MainJobSync` would have
"fixed" the bug while still ignoring the override, i.e. the report, unfixed. He caught
it with one sentence: *"When I use my level override feature, it doesn't automatically
equip blind bolt."* The authority already existed: `dispatch.playerLevel(ctx)`.
**The division worth keeping â€” `playerLevel` is what dlac gears you AT (choice);
`equipcore`'s level is a legality gate against the real game (permission). A chooser
reads the chooser's level.** Its corollary explains why the failure looked different
under an override than under a cap: with a real level of 50+ nothing downstream refuses,
so the WRONG bolt equips happily; under a cap the same wrong pick dies one step later
and quieter. Same bug, two exits.

**Landed:** a fourth gate mirroring `equipcore.checkUsable` (level + Jobs mask) read off
the live client resource for an item already counted in the bags, unknown never
disqualifying (the `pairsWith` three-valued law) and a level `<= 0` treated as the v49
not-ready read; the Default arm re-judging what is WORN â€” empty slot, over-level, or
ours-and-no-longer-best â€” while anything worn that is not on the list stays untouchable
(the guard that keeps a Midshot set's trinket alive; owning the slot outright is ADR
0010's flap through a third door); `syncHold` parking the pick at Default only, because
protection must never be suspended on an action event, and an override deliberately
never arming it; four return values from `resolveAmmoPlan` so **stock talks and level
does not**, edge-triggered on a change of cause rather than a timer. Then the CW E-Box
side removed whole (Henrik: *"we have E-box restocker now which is better"*) â€”
`feature/eboxammo.lua` deleted, the panel left with no gamemode awareness at all, and
the `/dl ebox` entity probe moved to `eboxtrace` as **`/dl debug ebox scan`** rather than
dying with it. Finally the panel: a red `Lv` column when a rung is out of reach, and the
row actually in your Ammo slot rendering green â€” the v128 tab law, green = live fact.

**Worth carrying:** `helmwatch.playerLevel` had the level-aware ladder right from the
start â€” AutoAmmo was the one gear picker that never got it, so *check the siblings before
assuming a gap is universal*. And the AU harness had to start RECORDING `TextColored`
instead of no-op'ing it: **a stub that throws away colour cannot see a feature that
speaks in colour**, the craftbar trap in a new costume.

**Status:** field-confirmed by Henrik the same day â€” *"it works now"* â€” and queued for
promotion. Suites 3821 + 593, green on both interpreters.

## Session "the slot that was never missing" (2026-07-27, on `dev` â€” addon 2026.07.27o â†’ p)

**Theme:** Henrik asked a bookkeeping question â€” *"we have a feature where if we equip a
tunic that takes up the headslot, it ignores to equip the headslotâ€¦ there are more items
like this, for different slots. How do you propose we keep track of all of these
different iterations of 'uses two slots'? Kupo suit, decennial coat, decennial hose."*
The answer turned out to be **there is nothing to keep track of**, and the work was
proving that and then fixing the two things that actually were missing.

**The diagnosis.** `RSlot` is the server's `item_equipment.rslot` â€” a 16-bit "removed
slot" mask â€” mirrored per item in `catalog.lua` since v43, stamped into `gear.lua` by the
scan, backfilled by `/dl fix`, and consumed **generically** by `dispatch.reservedDrops`.
Vermillion Cloak is not special-cased anywhere; it carries `RSlot = 16` and the engine
does the rest. So the premise of the question â€” a growing list of hand-maintained special
cases â€” never existed.

Verified instead of asserted: `catalog.lua` diffed by id against the local server clone's
`sql/item_equipment.sql` gave **383 items with a non-zero rslot, 383 present in the
catalog with the identical value, 0 missing, 0 mismatched, 0 absent entirely**. The only
four divergences are Ammo trinkets/shuriken, which is `effectiveRSlot`'s deliberate ADR
0010 completion. All three items Henrik named were already right: Kupo Suit â†’ Legs
(`128`), Decennial Coat â†’ Hands (`64`), Decennial Hose â†’ Feet (`256`). And the space is
much smaller than "all these different iterations" suggests â€” **nine distinct masks**:
Range 131, Hands 74, Feet 71, Head 52, Ammo 35, Legs 11, Hands+Feet 4, Hands+Legs+Feet 3,
Head+Hands 2. `reservedDrops` has walked arbitrary multi-bit masks in a fixed slot order
since v43, so nothing about a suit that eats three slots is new work.

**Landed (the two real gaps).** *Visibility:* the drop was completely silent â€” which is
precisely why a correct feature reads as a bug. `renderItemTooltip` now prints *"Takes
Head â€” that slot stays empty while this is worn"* on the ONE hover card every equipment
surface shares, and the Sets builder previews the conflict before dispatch ever runs it:
the reserved tile goes dark red, its hover names the reserver, and a single line under
the grid lists the slots. Two new seams exist so the GUI owns **neither** rule â€”
`dispatch.rslotText` (bit â†’ slot name, because the engine owns the vocabulary it owns the
behaviour of) and `gearimport.rslotFor` (the mask by id, the *same* resolver the scan
stamps `gear.lua` with, ADR 0010 completion included). The preview itself calls
`reservedDrops`, the equip-time pass, with no `worn` argument: the builder shows the SET,
not the character. *Drift:* `apicrawl.py` now prints an **RSlot audit** on every rebuild
(`--rslot-audit` reports without writing), naming each item that gained, lost or changed
a reservation.

**Worth carrying:**
- **`rslotlook` is not `rslot`.** A Kupo Suit *looks* like it covers hands, legs and feet
  (`rslotlook=448`) but only **Legs** is actually blocked (`rslot=128`). Anyone "fixing"
  this class of item by eye from the in-game model would stamp the wrong mask on the
  whole family. We mirror `rslot` and ignore `rslotlook` â€” deliberately.
- **A silent safety warning is the worst failure mode there is.** `rsv.dropsIn` runs
  inside a render `pcall` (a warning must never crash a frame), so a typo in it fails
  *quietly* and the builder simply stops warning â€” invisible by definition, because the
  feature's normal state is "says nothing". That is why `rsv` is exported through
  `host.provide` rather than kept private: smoke drives it against the real catalog
  (S16aâ€“p), so a dead resolver is a red test instead of a permanent quiet nothing.
- **The audit direction that matters is the LOSS.** An item *gaining* a reservation is
  loud in play. An item *losing* one is silent, and `/dl fix` will dutifully retract that
  stamp from every player's `gear.lua`. The audit prints the retraction consequence on
  that line for exactly this reason.
- The question was bookkeeping; the answer was arithmetic already in the repo. **Check
  what the data says before designing a registry for it** â€” the diff took minutes and
  deleted the entire proposed feature.

**Status:** on `dev`, **not** in the merge queue â€” Henrik has not field-tested it yet.
Suites 3836 + 609 (AK23â€“33, TR4câ€“e, S16aâ€“p added), green on Windows lua and WSL lua5.4.

## Session "the wishlist: intentions and facts" (2026-07-27, on `dev` â€” addon 2026.07.27p â†’ q, ADR 0026)

Henrik, in one message: *"add 'Show gear I don't own' like with lockstyle in all
equipmentâ€¦ right click and add pieces to wish listâ€¦ also have this when building sets, so
you can add stuff you don't have (it won't try to use em, but if you get it, it's
preemptively there, right?)"* Grilled to a shared design first (`/grill-with-docs`,
eleven questions), then built.

### The three things the code already knew

Reading before designing changed the shape of all three asks:

1. **"Show gear I don't own" already existed in All Equipment** â€” as `ui.showAll`, moved
   into Menu > Settings on 07-24 and renamed *"Show all equipment"*, where it read as a
   preference and nobody found it. So the ask was **discoverability**, not a feature: the
   tick is now on the tab too, bound to the same flag, and both places use the lockstyle
   wording. One setting, two surfaces.
2. **The engine already did what he hoped it did.** *"it won't try to use em, but if you
   get it, it's preemptively there, right?"* â€” right. `BuildDynamicSets` resolves a set
   entry by NAME against `gear.lua`; a miss is skipped at flatten time, so an unowned
   piece cannot shadow a lower-level piece you own, and it starts being worn the day it
   lands in your bags with nothing to change. The only thing wrong was the *noise*.
3. **There was a trap sitting directly in the path.** The API drops the possessive
   apostrophe: the Catalog says `Arhats Gi` where the client says `Arhat's Gi`. Sets
   resolve by name. So a wishlisted piece would have failed to resolve **on the very day
   you finally got it** â€” the one moment the feature exists for. This is the same trap
   the lockstyle picker refuses to save into (07-15); it just reappeared somewhere the
   refusal was not an option.

### Henrik's two rulings

The first design made set links **derived** â€” scan the sets, show what's there, nothing
to go stale. He rejected it: *"When I add something to a wish list, even from sets, add
the item to the wish list as its own entity, being able to exist on its own. Then connect
the set / sets that want it."*

That is the better model, and it unlocks something the derived version could not: you can
wishlist a piece **for** WHM/Idle without stuffing it into the set at all. The set stays
clean; the intention is recorded. It also creates the disagreement the derived design
existed to prevent â€” so the answer is to keep both halves and never derive one from the
other:

> **The stored half is an intention. The computed half is a fact. They are allowed to
> disagree, and where they do is exactly where the Apply button belongs.**

A link is written down and never revoked by dlac. Whether the piece is *in* that set is
re-read from the set files. Ownership follows the same rule in the other direction â€” never
stored, always read from the bags by Id, so selling a piece silently returns it to wanted.
Nothing needs reconciling because nothing derived is kept.

Second ruling, on set totals: *"set totals should only count towards the gear you own. If
you want to rebuild according to new pieces, we already have a simple 'Auto Build all'
button that should suffice."* A "what-if" toggle was on the table and he killed it â€” the
existing button already answers that question.

### What the set files did NOT get

The one warning left over was `warnMissingGear` calling a deliberate entry a typo on every
commit. Two ways out: mark it in the file (`{ gear = 'X', wish = true }`) or teach the
engine to ask. He picked the second â€” *"b, keep set files clean"* â€” so the format players
share, hand-edit and round-trip is untouched, and the engine reads `wishlist.lua` beside
`pinstate.lua`. A name that is neither resolvable **nor** wishlisted still warns, and the
suppression fails toward warning: no file, no character, a parse error, all answer false.

### The bug found on the way

`recordPath` builds a set entry's Lua expression from `rec.Key` â€” and **catalog records
carry a `Key` exactly like owned ones do** (it is `catalog.lua`'s table key). So the first
unowned piece committed to a set would have rendered `gear.Body.Dalmatica`: an expression
that evaluates to `nil` in the set file, taking the entry with it, silently. Unowned
pieces now serialize as a quoted **name** â€” the form `resolveGearName` resolves, and the
form that keeps working forever once you own the thing.

### Durable

- **A feature can be a naming problem.** Ask 1 needed one checkbox and two label changes;
  the capability had shipped three days earlier under a name that hid it. Read before
  building â€” half this session's work was already written.
- **`pcall(require, 'x')` binds the ERROR STRING, not nil.** `gearfmt` does this, so
  `fmt.textWrapped` indexes a *string* when imgui is absent and throws a "field is nil"
  error that reads nothing like a missing module. Latent for months; the Wishlist window
  is simply the first thing in `smoke_ui` to call it. Modules that use `try()` (which
  returns nil properly) are fine.
- **The apostrophe fix went in as a FALLBACK layer, not a replacement.** Every plain
  lowercase key is indexed first and a stripped key added only where nothing sits, so
  exact-lowercase always wins and no lookup that resolves today can start resolving
  differently. U7 pins that; a blanket normalization would have been a silent behaviour
  change across every set on disk.
- **The 200-local cap bites test files too** (hard rule 1). The new WL section broke
  `run_tests.lua`'s main chunk; scoping it in `do â€¦ end` is the fix.

**Watch in the field:** `Wishlist â–¸ â†’ Add for â–¸ â†’ row` is **one level deeper** than any
cascade proven in this binding (floatgear proved one, 07-15). `hasMenu` is probed and a
flat drill-down fallback exists, but this one wants eyes in-game.

### The field rounds

**Round 1** answered the one thing the suite could not: *"The extra level worked cascade
menu wiseâ€¦ It looks great! I can also add the stuff to sets if I press add, also works!"*
So **two-level imgui cascades ARE supported in this binding** â€” floatgear had only ever
proven one, which is why the drill-down fallback exists and why this was flagged as the
open risk. `popup â†’ BeginMenu â†’ BeginMenu â†’ MenuItem` is now a known-good shape for any
future context menu, and the fallback stays as insurance rather than as a live path.

What he flagged instead was layout, and it was one mistake made in five places: hardcoded
pixel columns in a window whose content is **player-named**. `SAM / Tp_Default` printed
straight through the status beside it (`SameLine(140)`), and both filter combos clipped to
`All joâ–¼` / `All sloâ–¼`. Every column now derives from the widest string it will actually
draw â€” the link column off the *same* `linkLabel()` the row prints, so the width and the
text can never be computed differently.

**Round 2** â€” *"`<JOB>` / `<SET>` still need more space, give it twice the space as it
has, so we can handle longer set names"* â€” is the more interesting correction, because
measuring was already *correct*. A column fitted to the current entry is the right width
for that entry and the wrong width for the next one: it moves under you every time you
select a different row, and a set name longer than today's has nowhere to go. Reserving
beats fitting when the content is not yours to predict. Now `2Ã—` the widest label on a
180 floor, capped at 360 so the status and its buttons cannot leave the window.

- **A stub that answers a CONSTANT cannot test a measurement.** `smoke_ui` was green
  straight through the column bug because its `CalcTextSize` returned 10 for every string.
  Section 6b's stub is proportional (~10px/char) now, and S92fâ€“S92m pin the label/column
  pair against Henrik's exact reported string. Same shape as the `pcall(require)` trap
  above: a stub too obliging to fail hides the thing it was added to guard.
- **A nil check is NOT redundant with a pcall around an imgui call.**
  `pcall(imgui.CalcTextSize, s)` on a nil `imgui` throws while *evaluating the argument*,
  before pcall ever runs.

**Status:** on `dev`, **FIELD-CONFIRMED** across both rounds (*"It looks good and
works."*) and **in the merge queue**. Addon `27q` â†’ `27s`. Suites 3875 + 692 (WL1â€“WL34,
U4â€“U7, S60â€“S95, S150â€“S163 added), green on Windows lua and WSL lua5.4.

## Session "am I dominant in both pieces?" (2026-07-27, on `dev` â€” addon 2026.07.27t, engine v134 â†’ v135)

**Theme:** the reserved-slot feature was correct and still visibly broken, twice, in
opposite directions â€” and the fix was not in the reserve rule at all.

**The two field cases.** Hunklor SAM: Movement(25) `Body = Kupo Suit` (reserves Legs)
over Idle(20) `Legs = Amir Dirs`. It flapped Kupo Suit â†” Amir Dirs continuously while
running. Mindie SCH: Idle(20) `Body = Royal Cloak` (reserves Head) under Movement(25)
`Head = <piece>` â€” the headpiece could never land, however high its priority. Henrik:
*"So to me it looks like it's locking the head piece as long as royal cloak stays on.
This is the wrong logic."*

**Two wrong diagnoses first, both killed by evidence â€” worth recording.** (1) A repro
against Hunklor's real `gear.lua` showed `Legs=RESERVED by Kupo Suit (kept as worn)` and
the Legs dropped: the manifest, the mask and the pass were all fine. So the flap "had to
be" `moving` flickering â€” the detector has a thin 0.1s margin over the dispatch tick.
Henrik's `/dl why` screenshot printed `moving=true`, and that was that. (2) The same
screenshot showed `Legs<-Idle` surviving into the slot list with no RESERVED note, which
read as "the drop never fires live" â€” but that block is the **Arbiter's claim
attribution**, which runs separately from the post-passes. Nearly a second confident
wrong answer off a truncated screenshot. *Read what a trace is actually printing before
concluding from what it does not print.*

**The real root cause.** `dispatch.lua`'s overlay loop applies each matching rule's set
through its **own** `equipResolved` (`equipSetByName` resolves *and* equips, per rule).
So `reservedDrops` only ever sees one rule's set. Idle resolved alone â†’ nothing reserves
â†’ Amir Dirs equipped. Movement resolved alone â†’ `{Body}` only, no Legs to drop â†’ suit
equipped, server stripped the legs. Both every dispatch. The merged view existed a few
lines away as `floorTbl` â€” but only `if retrace`, i.e. purely to draw `/dl why`. The
equip path never had it. Henrik named it before the code did: *"I think the problem lies
in the overlying eye."*

**Henrik's ruling, built as stated.** A piece that reserves other slots is a **candidate
only while the claim wanting it is dominant over every slot it takes** â€” *"am I dominant
in both pieces according to you? If not, this piece is not a candidate."* Dominant â†’ it
wins its slot and **claims** the reserved ones, left empty (the server clears them
natively). Beaten â†’ **ineligible**, its own slot unwritten. `M.reserveFloor` +
`M.reserveVerdict` are pure; the engine builds the floor before the first write and
retires it right after the trigger loop.

**Worth carrying:**
- **A correct rule fed the wrong input looks exactly like a wrong rule.** Three separate
  investigations (data, mask, pass) all came back clean while the feature was plainly
  broken, because none of them asked *what is this function being handed*. The repro that
  "proved" the engine right had constructed the merged plan by hand â€” the one thing the
  engine never does.
- **Both directions or it isn't the rule.** The SAM case alone is fixable by suppressing
  the reserved slot; the SCH case alone by ignoring the worn reserver. Only dominance
  produces both, which is why AKD1â€“12 test them side by side.
- **Order inside the verdict is load-bearing**: dominance must resolve *before* anything
  is suppressed (a piece judged ineligible is not worn, so it reserves nothing), and a
  claimed slot must not claim further.
- **The AutoAmmo rung-2 trap is general.** *"Go for the next available piece"* is not
  buildable today because `BuildDynamicSets` collapses each slot's list to one name before
  the engine sees it â€” the same collapse that made the AutoAmmo ladder fail silently. An
  ineligible piece leaves its slot unwritten instead. Carrying alternates is the follow-up.

**Status:** on `dev`, **FIELD-CONFIRMED** by Henrik the same day â€” *"It works now."* â€” and
queued for promotion. Suites 3901 + 692, green on Windows lua and WSL lua5.4. Both real cases also driven end-to-end
against the actual `gear.lua` files of both characters.

## Session "minimizing the hobby bar ate the other windows" (2026-07-27u)

**Theme:** a one-line ImGui misuse, four days old, that only showed itself when Henrik
finally minimized the window it lived in.

**Reported:** *"if I open the Hobby Bar, then minimize it, our floating icon for DLAC /
Teleports disappear when I click itâ€¦ the moment I unminimize the hobby bar, I can see the
menu flash up and disappear real quick."* Then, unprompted: `/dl ui` was **also** up and
invisible, and something invisible was refusing his clicks on the hobby bar's title bar.

**The discriminators, all from Henrik in one message.** Minimizing the main window,
Lockstyle or the Wishlist does nothing. **Closing** the hobby bar does nothing. Expanding
it brings everything back with no further click. So: not popups, not window order, not
the float â€” the *collapsed hobby bar* specifically. His `/dl metrics` screenshots pinned
the rest: ImGui **1.81**, `Popups (0)` after the click (so `OpenPopup` never even ran),
`NavWindow: '##dlac_tpfloat'` with a live `NavId` (so the mouse-**down** registered and
the mouse-**up** frame never drew the button), and `11 active windows (10 visible)` in
every shot while ~48 vertices vanished â€” a window still active, still counted as
rendered, drawing nothing.

**Root cause â€” the LAW, worth carrying.** `ui/hobbybar.lua` opened with
`imgui.SetNextWindowSize({0,0}, ImGuiCond_Always)` every frame, right before an
`AlwaysAutoResize` `Begin`. A zero component makes ImGui's `SetWindowSize` set
`AutoFitFramesX/Y = 2` â€” *"submit the body anyway, I still need to measure it"* â€” and
`ImGuiCond_Always` re-armed those counters on every single frame, so they never reached
zero. ImGui's own rule is

    skip_items = (Collapsed or not Active or Hidden) and AutoFitFrames <= 0

so a **collapsed** hobby bar kept returning `true` from `Begin()` and kept drawing its
whole body into a title-bar-sized window, forever. Every other dlac window collapses
normally, which is exactly why this one was the only trigger. Focus decided *who* got
eaten: `FocusWindow` moves a window's draw list to the display front â€” i.e. **behind**
this one in emission order â€” so clicking the Teleports float, or opening `/dl ui`, put it
there. Closing the bar was always safe: a window that is never begun cannot leak.

**Fix:** delete the line. `AlwaysAutoResize` already sizes the window to its content
every frame; the call was redundant from the day the bar shipped (`92e1fb2`, 07-24).
`HB21` pins it â€” the smoke stub records every size requested and asserts none is zero.
Mutation-verified: re-add the line and HB21 fails.

**Worth carrying:**
- **`SetNextWindowSize` with a zero component is not "auto-size", it is "keep measuring".**
  With `ImGuiCond_Always` it is a permanent instruction, and it silently defeats *collapse*
  â€” a state most windows are never tested in.
- **Two symptoms, one window.** "The float dies" and "`/dl ui` is invisible" looked like
  two bugs and named one cause. The second report is what killed every theory built around
  the Teleports popup.
- **The metrics window is the artifact.** `active` vs `visible` counts plus the vertex
  delta said *active, rendered, drawing nothing* â€” which no amount of reading the addon's
  own Lua could have said.

**Status:** on `dev` (`ad476ea`, addon `27u`), **FIELD-CONFIRMED** by Henrik the same day
â€” *"it works now :)"* â€” and then **ACCEPTED** by him for promotion: *"Document this as an
accepted fix and put it as an accepted part of the dev â†’ main merge in the future."* The
next dev â†’ main merge carries it without a fresh go-ahead (HANDOFF's queue marks it âœ…).
Suites 3901 + 693, green on Windows lua and WSL lua5.4.

## Session "an import should be able to land verbatim" (2026-07-27w)

**Theme:** the first feature dlac has taken from a **second player's** field report â€” and
a behavior that was correct-by-design in only half the cases it ran in.

**Reported**, by a friend of Henrik's who runs dlac and had been round-tripping his own
profiles to compare them against what dlac would pick: *"I'm importing dlac how I want
them, and it's just changing it every time."* With a theory attached, and a good one:
*"If I'm on the job, and profile that I am importing it to, it will auto refresh stats
based on weight. If I'm not on the job it doesn't."* That is exactly the shape of
`gearui`'s `afterImport` hook â€” it refuses when the import lands outside the current
character's active profile, or under a job you are not on, because the candidate pools
(owned gear, job/level usability) are the current job's. He had reverse-engineered the
guard from the outside, from behavior alone.

He also arrived with a **patch**, written with his own Claude: `sf.flags.autoBuildOnImport`
+ `/dl autobuildimport`, defaulted on, persisted through `uiflags.lua`. The reasoning and
the seams were right and are what shipped. The two files themselves were not usable â€”
his gearui.lua is a **pre-purge** copy (it still calls `/lac equip`, still composes the
legacy `luashitacast\<Char>_<id>\` path by hand, and predates the Wishlist and the
reserved-slot work), so applying them would have reverted five sessions. Ported by hand
onto current `dev` instead. *Worth stating plainly: the patch was read, not run.*

**Why he was right, in dlac's own terms.** The hook exists because an export ships sets
as **EMPTY shells** â€” names, no gear â€” on the theory that gear rarely aligns between
characters, so the receiver's own gear should fill them. But the export form has had a
**"Set equipment"** tick since the selective export landed (07-19): when it is on, the
exact gear ladders travel verbatim. In that case the post-import re-solve overwrites
precisely what the exporter chose to send, and no amount of re-exporting can show you
what you actually shipped. The premise in the hook's own comment ("the exported shells
are EMPTY on purpose") is simply false for that path.

**Landed:**
- **`sf.flags.autobuildimport`** in `gear/syncflags.lua`, saved and loaded with the rest
  of `uiflags.lua`. **Default on**, and an **absent key reads as on** â€” every uiflags.lua
  written before today lacks it, and those installs must not have their imports change
  behavior because they updated. Read everywhere as `~= false` for the same reason.
- **The gate in `afterImport`**, checked **last** â€” after the wrong-profile and wrong-job
  guards. Order is deliberate: turning the setting off must never change *which* reason
  you are told, or "it didn't build" stops being diagnosable.
- **Two surfaces, one flag:** `/dl autobuildimport [on|off]` (bare = toggle, the
  `/dl autosync` shape) and **Menu > Settings > "Auto-build sets on import"**. The
  Settings checkbox is the house surface for a Setting (ADR 0019); the command is what
  the reporter was told to type, so it works.
- **The status line says which happened.** Off, the import reports that the sets landed
  exactly as exported and points at Auto-Build All on the Sets tab.
- **Tests:** `UIF6a` / `UIF18a` round-trip and load the key, `UIF21a` pins the absent-key
  default at **on** (the one that would silently change everyone's behavior if it broke),
  and `UIF21b/21c` pin at the SOURCE that the hook reads the flag and reads it before it
  builds â€” the hook needs imgui and a logged-in character, so a source pin is the honest
  alternative to no coverage at all. `MN12a` counts nine Settings checkboxes.

**Worth carrying:**
- **A default is only as good as the premise under it.** This one was written for the
  empty-shell path and then ran on every path, including the one it destroys. The tick
  that made it wrong shipped eight days later than the hook and nothing connected them.
- **Second-hand field reports arrive with the guard already reverse-engineered.** He
  named the exact two conditions the hook checks without ever seeing it. When a report
  describes behavior that precisely, spend the time to find the code it describes.
- **A patch from another install is EVIDENCE, not a diff.** Version-drift makes an
  attractive-looking file a revert in disguise; read it for reasoning and re-derive.

**Left open â€” a real product question, deliberately not decided here.** dlac knows, at
import time, whether the payload's sets carry gear or are shells. The case for making
that the *default* discriminator â€” re-solve shells, respect gear that travelled â€” is
strong, and would fix the reporter's complaint with no setting to find. The case against
is that the tick was the **exporter's** choice, and a receiver who owns none of that gear
is better served by the re-solve. That is a behavior call for Henrik, and the setting
delivers his friend's ask either way.

**Status:** on `dev`, addon `27u` â†’ **`27w`** (`27v` belongs to a parallel session's
uncommitted engine work in this shared checkout), engine unchanged. Suites **3906 + 693**,
green on Windows lua and WSL lua5.4. **Awaiting field test** â€” by the reporter, who has
the round-trip that found it.

### Follow-on, same session â€” the last legacy fallback under the flag (`27y`)

Henrik, reading the above: *"Has this been set up with the purge in mind? So we don't add
legacy crap towards LAC?"* The new code adds none â€” grepping the commit for
`luashitacast`, `/lac `, `GetInstallPath` and hand-composed `<Char>_<id>` paths returns
nothing, and `PRG1` passes. **His friend's patch was the legacy crap**, which is the point
worth keeping: applying it would have reintroduced `/lac equip`, a hand-composed
`config\addons\luashitacast\%s_%u\dlac\gear.lua`, and a hand-composed `charBase` in place
of the delegation to `profiles.charBase` â€” while deleting **299 lines** of Wishlist and
reserved-slot work. `PRG1` would have caught two of those three; nothing would have caught
the deletions.

But the question found a real leftover in the chain the new flag rides. Three functions
still ended in a `charBase() .. 'dlac\'` fallback from the engine-flag era:
`gearui.dataDir`, `gearui.charRoot`, `syncflags.uiFlagsPath`. **All three were
unreachable**, and provably so: `profiles.dataDir` (â†’ `nativeCharBase`) and
`profiles.charBase` are the same `charFolder()` behind two different roots, so they go nil
together and non-nil together. The fallback could only fire in a world where they diverge
â€” and in *that* world it would have pointed dlac's own writes at the read-only import
tree. `uiflags.lua` (which now carries the import setting) was the one with a player-facing
consequence: a Setting written into `luashitacast\` would never be read back.

Deleted, all three, returning `nil` â€” the answer every caller already handles as "not
logged in yet, retry next frame". **`NE30`** pins the nil-together invariant the deletion
rests on: no identity â†’ both nil; identity â†’ both answer. **Mutation-verified** â€” make
`charBase` fall back to a placeholder folder and `NE30b` fails, naming the
`luashitacast\Ghost_1\` path it would have used.

**Worth carrying:** *unreachable* and *harmless* are different claims. This code could not
run, but it encoded a rule the purge deleted â€” "when the native home has no answer, use
LAC's" â€” and the next person to touch path resolution would have read it as current. Dead
code is documentation that nobody proofreads.

**Status:** on `dev`, addon `27x` â†’ **`27y`**, engine untouched. Suites **3947 + 693**,
green on Windows lua and WSL lua5.4.

## Session "the earring that could never equip" (2026-07-28, on `dev` â€” addon 2026.07.28a â†’ b)

Henrik came back with the MaxMP oddity he'd flagged during the stage 6 field round â€” the
mode never equipped Outlaws Earring â€” and he came back with the diagnosis, not just the
symptom. He had already run the experiment: remove Outlaws Earring from the idle set's
Ear2 ladder, re-plan, and it equips fine. His read: the pair-position rule was treating
**every earring documented in the idle set** as position-anchored, "even if they are not
used" â€” and his ruling: only the **currently chosen** pair pieces should anchor; the rest
are floating.

The code agreed with him on every point. The fmt 13 pair-home harvest
(`automationsui`'s manifest builder) read the **authored** sets file
(`prof.readSetsFile`) and homed every entry of every Ear/Ring slot list. That was
faithful to the original ruling ("a piece the idle set lists under Ear2 is an ear2
piece, full stop") â€” but the ruling predates ADR 0027's slot LADDERS. Once a slot
became a level-graded list, "lists under Ear2" started matching gear documented only
as leveling rungs. Henrik's Ear2 ladder holds Loquacious (Lv75, MP 30) with Outlaws
(Lv50, MP 15) as the rung to grow through â€” at 75 the flatten picks Loquacious and
Outlaws is dead weight in the authored list.

The kill chain was arithmetic, and it's worth spelling out because *nothing errored*:
both earrings homed to ear2, so ear2's battery ladder was [Loquacious 30, Outlaws 15]
and ear1's ladder had **no MP earrings at all** â€” no ear1 band can ever build. Ear2's
band takes the ladder TOP (one band per slot, v92) â€” Loquacious â€” against the potency
point, which is *also* Loquacious (it's the set's own pick, and `mpLowMap` reads the
**flattened** store). Top mp âˆ’ low = 0, and `mpbands.build` drops zero-diff bands. No
band on ear2 either. Outlaws, mp 15 against a 30-MP potency point, was invisible from
every direction. Remove the rung and it floats to the emptier ear1 ladder: top 15
against a 0-MP ear1 potency point = a 15-MP band that fires. His experiment was the
whole proof; the catalog stats matched it line for line.

The asymmetry is the actual lesson: the LOW side of the band (potency point) always
read the **flattened** set â€” the chosen pick at the live level â€” while the HOME side
read the **authored** rungs. Two sides of the same band disagreeing about what "the
set's piece" means. The fix makes both sides read the same world: a new
`dispatch.flattenedSet(name)` accessor (the top-level store entry, one chosen piece
per slot; statics included, they were born flat) and the harvest homes only those
picks. Deliberately NOT `candidatesFor` + a head-pick â€” that would have been a fourth
copy of "the pick" (the stage 5 lesson about the `bestByLevel` twin). The flatten
already computed it; read it.

What survives unchanged: the chosen pieces still never plan across the pair (Loquacious
stays in ear2 â€” the churn rule that started all of this, v83/v93, is untouched), dup
twins still ride both ladders, and the sticky apply veto still kills any transient
tug. Boot warm-up degrades gracefully: no flatten yet â†’ no homes this pass â†’ the
constant rescans (login, job change, any inventory change) re-home within a beat.

**Status:** on `dev`, addon `2026.07.28a` â†’ **`2026.07.28b`**, engine untouched (the
manifest builder + one dispatch accessor). Tests `FS*` pin the seam. Suites **4078 +
693**, green on Windows lua and WSL lua5.4. **FIELD-CONFIRMED the same day** â€” Henrik
restored the rung and re-planned: *"Now it works!"* Documenting leveling gear costs
nothing again, which was the point. In the merge queue (hard rule 14).

## Session "a dynamic set in an old file is an FFXI-LAC set" (2026-07-28, on `dev` â€” addon 2026.07.28c â†’ d)

Henrik, on the Sets tab's **Manageâ€¦ â†’ Copy from**: *"when you wanna copy old statics, I
want it to enable copying old FFXI-LAC Dynamic sets. So when it sees a dynamic set, it's
old FFXI-lacâ€¦ If set names collide, prioritize the dynamic ones."* The purge made the
LuaAshitacast tree read-only import territory, not deleted â€” and the import door was
only half open: a legacy `<JOB>.lua` and its pre-profiles backup carry **two** kinds of
source side by side, LAC's statics at the root and dlac's OWN `sets.Dynamic` block from
before profile storage existed, and only the statics were ever listed. The reader had
even said so out loud since the migration landed â€” *"the pre-migration backup: statics
only, never Dynamic (reading it again would resurrect deleted sets)"*. That fear was
right about the **sets root** and wrong about the **picker**: the danger was a deleted
set looking *live*, not a deleted set being *offerable*. So the block is harvested into
its own list (`profilesets.lacSetNames` / `getLacSets`) that never touches the root â€”
`liveSetNames` stays exactly the trigger-target authority it was (`PSL7/8`).

One exception falls out of the same rule: the **unmigrated** character, whose job file
IS the live Dynamic source. There the same block is already the set list, so offering it
would list every set twice â€” the harvest skips an *adopted* block (`PSL1/2`). The
collision rule is Henrik's, one line, in the pure layer: `setimport.mergeLegacySources`
merges statics and old dynamics into one name-sorted column, dynamics claim their names
first, so a set that grew from a static into a Dynamic set imports as what it *became*
(`AQ*`). The first cut of the column presented that split as one blue heading with dim
`Dynamic` / `Static` sub-headers, and Henrik bounced it immediately â€” *"Static atm is
greyed out like dynamic, so it's hard to noticeâ€¦ even I got confused"*. It ships as TWO
headings in the same list-header blue, **Old FFXI-LAC sets** above **Old Static Sets**,
each naming what its rows ARE; an empty group draws no heading. Dim is for things you
may ignore, and a group label is never one of them. The import itself reuses the pinned `importStaticSet` transform â€” but **not**
its not-best-first warning: that divergence (ADR 0008, dlac takes the highest item-Level
rung where LAC took the first in the list) is a LuaAshitacast-static fact. An old dlac
Dynamic set was always read by the highest-Level rule, so importing one reproduces
exactly what it did, and a warning there would be noise about nothing.

**Two live bugs surfaced from reading the real files before shipping** (artifacts first,
not theory). *One:* `profiles.backupPath` composes off the native home only, but a
character migrated in the LAC-tree era left its pre-profiles originals under
`luashitacast\<char>\backups\pre-profiles\` â€” and its live job file is a shim. Copy-from
had therefore been listing **nothing at all** for such a character: 5 SAM + 10 WAR
statics on this very install, invisible. New `profiles.legacyBackupPath` (allowlisted
door, PRG1) adds that home as a second read tier. *Two:* the sets sandbox handed legacy
files the **real** gear table, so one unowned weapon category â€” `gear.Main.Club` on a
character who never scanned a club â€” nil-indexed the whole chunk away and took every
static in the file with it, silently. It now hands them `profiles._wrapGear`, the same
missing-safe read proxy the profile sets loader has always used (present tables pass
through by identity; absent ones read nil / an empty category).

**Status:** on `dev`, addon `2026.07.28c` â†’ **`2026.07.28d`**, engine untouched (GUI +
readers only). Tests `AQ*` (the merge rule) and `PSL*` (the reader, all three storage
shapes). Suites **4114 + 693**, green on Windows lua and WSL lua5.4. Driven headlessly
against this install's real files first: BLU surfaces 8 old FFXI-LAC dynamic sets
(`Pollen`, `BlueMagic`, `Requiescat` exist *nowhere else* today), and importing `Idle`
resolves 15 slots of ordered candidates. **FIELD-CONFIRMED the same day** â€” *"looks good
and works"* â€” and **ACCEPTED** for the next promotion (*"have it ready to merge to
main"*); it sits in the merge queue with `4d9d7f0` (Scroll Lock), which `dev`'s
whole-or-not promotion carries along. One judgment call left standing, deliberately: on a
job whose pre-profiles backup was migrated whole, the FFXI-LAC list repeats names you
already have live (WHM lists 19). That is honest â€” they are the pre-migration *versions*,
and the "New set(s)" path lands them as `_Copy` â€” but if it ever reads as noise, hiding
names that already exist live is a one-line filter.

---

## 2026-07-28 â€” "table index is nil": the file that told us its own shape, and we did not listen

The second field report from Henrik's friend (`Abraxis_42505`), one screenshot:

```
[dlac] commit ABORTED: would error on load: ...\Abraxis_42505\gear.lua.tmp:9765:
table index is nil. backup: ...\backups\gear_20260728_111330.lua
```

He was on a **new dlac install** and *"can't get all the gear in"*. Auto-sync retried on
its own, so the line kept coming back.

**The artifacts settled it in minutes, and the first theory was wrong.** He sent
`gear.lua` plus fourteen backups. All fifteen were **byte-identical** (md5 `861d7c6fâ€¦`,
261,341 bytes) â€” proof the rails held: `safewrite.replaceLua` validates *before* it
touches the live file, so nothing was ever written, and each aborted commit had simply
backed the same file up again. The standing hypothesis walking in was that his `gear.lua`
was already corrupt and `dlac.lua`'s boot preload was silently falling back to the empty
template. **It was not.** His file runs clean â€” 691 entries â€” and it is internally
consistent:

```
Main  categories=12   Range categories=8   Ammo categories=3   (everything else flat)
```

It is a legacy LuAshitacast file: it nests **Ammo** by weapon category
(`Archery`/`Marksmanship`/`Throwing`), and its own trailer declares exactly that â€”
`if slotName == "Main" or slotName == "Range" or slotName == "Ammo" then`. Which slots
nest is **a property of the file**, written down in the file, and dlac never read it:

```lua
local WEAPON_SLOTS = { Main = true, Range = true };   -- category-nested slots (Ammo is flat)
```

So `spliceStaging` filed new ammo flat and dropped it in right after `    Ammo = {` â€” as
a **sibling of the category tables**. Reproduced against his real file with one item:

```
 3355|     Ammo = {
 3356|         SilverArrow = {        <-- inserted here
 3357|             Name = "Silver Arrow",
 3362|         },
 3363|         Archery = {            <-- where it needed to go
```

That text **parses**, which is why the parse check waved it through. Then the trailer
descends three levels into `Ammo`, reaches `SilverArrow`'s own fields, and evaluates
`("Silver Arrow").Name` â€” indexing a string is legal and yields nil â€” so
`NameToObject[nil] = â€¦` â†’ **table index is nil**, blamed on the trailer. His 9765 checks
out exactly: his trailer's weapon-branch assignment sits at line 8880 and his staging
batch added 885 lines. 8880 + 885 = 9765.

And because commit is **all-or-nothing**, one bad ammo entry blocked *every* slot. The
batch re-staged on the next auto-sync and aborted again â€” fifteen identical backups in
ninety minutes, and not one item in.

### The rule that came out of it

**A file's shape is data, not an assumption.** `gear.lua` carries its own nesting rule in
its own trailer; any writer that splices into it has to *read* that, or it is guessing
about someone else's file. New `slotShapes(lines)` decides per slot from the text â€” an
8-space child carrying its own `Name = "â€¦"` is an ENTRY, one holding only deeper tables
is a CATEGORY (a multi-line `Stats = {}` block does not fake a category, `GS3`) â€” and a
disagreement now **aborts naming the slot** instead of writing a file that cannot load:

```
[dlac] commit ABORTED: gear.lua shape conflict -- Ammo is nested by category here,
dlac writes it flat.
[dlac] nothing written. Delete gear.lua and let /dl scan rebuild it, or reshape by hand.
```

### Two more, from the same family: readers that disagree with the file

**The error named the trailer, never the cause.** `gear = {â€¦}` is fully built before the
trailer runs, so even a trailer blow-up leaves the table sitting there â€” `gearProblems`
now walks it and reports `gear.Ammo is category-nested (Archery, Marksmanship, Throwing)
but SilverArrow sits directly under it (line 3356) -- wrong depth` instead of a line
number ~6400 lines away. It is deliberately shape-**agnostic**: it flags a slot that
*mixes* entries with categories, a child that is neither, an entry with no `Name` â€” never
"you nested a slot we write flat", because that is the file's business. A category is
identified structurally (a table with no `Name` that *holds* named tables), not by
head-count, so one new entry beside three categories and thirty beside three read the
same way round (`SH12-17`).

**And a latent one, found while fixing the first.** `parseGearEntries` (fix/dedupe/prune)
tolerated a trailing `-- comment` on a header â€” pinned by test `D`, after 25 hand-
annotated entries went invisible to `/dl prune` in the field. But `parseStaging` and
`indexGear` carried their own stricter `= {%s*$` patterns. A commented **category** header
was therefore invisible to `indexGear` alone, so commit "created" a section that already
existed; Lua's last-key-wins threw the new block away; and commit **reported success while
the items silently never landed** â€” so they scanned as new again forever, the file growing
by a dead duplicate block each pass. Demonstrated before the fix:

```
B. category header has a trailing comment
    inserted=2 created=[Main.Sword]   reachable Main.Sword entries: 1  [Old Sword]
```

All three commit-side readers now share `hdrAt`/`closeAt` with `parseGearEntries`
(`SH18-20`).

### Silence, twice

`dlac.lua`'s boot preload and `gearui.refreshGear` both swallowed an unloadable
`gear.lua` and carried on with the bundled empty template: the GUI shows no gear, every
scan calls every item new, and nothing anywhere says a real inventory is on disk one bad
entry away. Both say so now. That failure mode did *not* fire here â€” but it is precisely
the shape of the theory that cost the first half hour, and it was one `pcall` away from
being true.

Suites **4134 + 693**, Windows and WSL lua5.4. Tests `SH1-20`. Henrik's remedy for the
friend is the blunt one, and the right one: delete `gear.lua` and let `/dl scan` rebuild
it in dlac's own shape.

### The same day, the follow-up question that found the real entry point

Henrik, on reading the diagnosis: *"how can a LEGACY LAC gear.lua come here? He installed
DLAC just now, and we purged most connections to it yesterday."*

Fair question, and the answer was not the migration. **dlac put it there itself.**
`setupui.seedGearFile` â€” the fresh-install auto-setup (`autoSetupNative`, issue #91) â€”
seeded a new character's gear inventory by *preferring* an existing
`<charBase>\ffxi-lac\gear.lua`, falling back to the bundled empty template only when there
wasn't one. Its own comment said why: *"a returning player keeps their scanned
inventory."* So:

```
config\addons\luashitacast\Abraxis_42505\ffxi-lac\gear.lua
   -> config\addons\dlac\Abraxis_42505\gear.lua      (verbatim, on first login)
```

Not a purge leak. The purge killed the `luashitacast\` **engine** coupling; `charBase()`
survived deliberately as the importers' read-only door, and `ffxi-lac\` is a folder inside
that tree. A kept feature, firing as designed.

**Why it could never reproduce on Henrik's machine.** His own `ffxi-lac\gear.lua` (Mindie,
10,907 lines) is a *newer generation* of the same file:

| | Mindie's | Abraxis's |
|---|---|---|
| Ammo | **flat** | nested by category |
| trailer | `Main or Range` | `Main or Range or **Ammo**` |
| `Id =` fields | 697 | **0** |

FFXI-LAC itself moved to flat Ammo and started stamping `Id` at some point; dlac inherited
the new shape, and the seeder copied files of the old one without looking.

**The ruling** (Henrik): *"Drop the ffxi-lac preference, ALWAYS handle your own gear
locally in DLAC. ONLY FFXI-LAC integration we should have, is SOLELY on importing dynamic
gear, which has been solved by another agent."*

The courtesy was worth less than it looked even when the shapes matched. A seeded
ffxi-lac file has **no `Id`** on any entry â€” and `RSlot` and the Range/Ammo `Pair` key are
both looked up BY id, so reserved-slot conflict handling and ammo pairing were dead for
every item in it. Its `Stats` blocks are inert (dlac derives stats from the catalog by
id). And its contents are a *catalogue* â€” Abraxis's carries transcription comments like
`-- *** NEW CATSEYEXI AMMO (None specifically listed on the page) ***` and
`Jobs = {"All Jobs"}`, which is not even dlac's sentinel (`"All"`) â€” not the player's
bags. `/dl scan` rebuilds the lot correctly, from the real bags, in seconds. A head start
that is wrong in three dimensions is not a head start.

`seedGearFile` now always copies dlac's own bundled template. Guard `SH21` fails if any
core file reads a **path** out of the ffxi-lac tree again; `SH22` pins the door that must
survive â€” the **content** sniff (`text:find('ffxi-lac')` â†’ `st = 'ffxilac'`) that routes an
old profile into the sets migration. The guard was negative-tested against the pre-change
file: it flags the old `seedGearFile` and passes the new one. Prose mentions of ffxi-lac
are deliberately untouched â€” this is a path guard, not a word ban.

*(Housekeeping in the same commit: this session's `GS1-20` were renamed `SH1-20`. A
parallel session landed its own `GS.` block â€” the groups auto-import scanner â€” and two
blocks answering to `GS1` makes a failure line meaningless. Committed work renames itself;
in-flight work is left alone.)*

## Session "three faults, one sentence" (2026-07-28, on `dev` â€” addon 2026.07.28m â†’ n)

The second tester tried to import his SCH **Cure** set with the day's new FFXI-LAC column
and got *"Created 0 new sets â€” nothing created, 1 skipped: no owned/known gear."* Henrik
sent the file. It has **three** independent faults, and dlac answered all three with that
one sentence â€” which is hard rule 12 in its purest form.

**1. The file does not parse.** Line 266 ends `gear.Back.MistSilkCape` with no comma, so
line 267 is a syntax error (`'}' expected (to close '{' at line 265)`). `loadfile` returns
nil, `sandboxSets` returns nil, and the reader shrugged: an unreadable legacy file and an
absent one were the same silence. Now they are not â€” `sandboxSets` distinguishes "not
there" (nothing to say) from "there and will not parse", and `legacyDiag()` carries the
file name plus **the parser's own message** into the Copy-from popup in red. His evening
becomes a ten-second fix.

**2. `require("ffxi-lac\gear")`** â€” dlac's own library under dlac's former name. No such
module on a dlac install, so the soft require handed back the STUB, whose `__index`
returns itself: every `gear.Main.Club.MapleWand` in the file became the stub object. The
sets listed perfectly (the block's KEYS are real) and every entry resolved to nothing.
Worse, the stub reached `string.lower(ref.Name)` as a *table*, and that error â€” caught by
the outer pcall â€” discarded the whole set. Module names are aliased onto dlac's now, so
the file resolves against **this character's** inventory. Measured on his file with a real
gear.lua: from 0 usable entries to `Head`, `Body`, `Hands`, `Legs`, `Feet`, `Back`,
`Waist`, `Ring1`, `Ring2`, `Ear1`, `Sub` all landing.

**3. `gear.Ammo.Throwing.MorionTathlum`** â€” the pre-flat Ammo shape. Against today's flat
`gear.Ammo` that is `nil.MorionTathlum`, an error that takes the file with it; and where
the old `_wrapGear` answered `nil` instead, the hole **truncated the `ipairs` walk** and
silently dropped every candidate after it (60 entries â†’ 10 on a foreign inventory). The
importer now reads through `legacyGear`, whose **MISSING sentinel** answers any key at any
depth and is skipped by the resolver â€” Henrik's ruling, verbatim: *"If pieces don't exist,
just skip them and move on like he doesn't have it."* A missing piece keeps its place in
the list instead of ending it.

Two hardening moves ride along, both the same lesson at a different layer: `resolveSetItem`
reads `Name`/`Id` **typed** rather than merely non-nil (a sentinel answers every key with
something), and `importStaticSet` guards each candidate with its own pcall, so a resolver
that throws costs one entry instead of a set. `SH21`, landed hours earlier by the parallel
session, is respected in the letter and the spirit: this renames a MODULE and never opens
a file in that tree â€” the prefix is written as a character class so a path guard reading
literals can't mistake it, exactly the convention PRG1 comments already use.

**Status:** on `dev`, addon **`2026.07.28n`**, engine untouched. Tests `PSM0-PSM14` drive a
fixture shaped like his file â€” old require name, nested Ammo, a missing comma â€” and pin
the whole chain: the alias resolves, an unknown piece keeps its slot and is skipped, the
import lands what he HAS, a throwing resolver costs one candidate, and the unparsable file
reports itself while an absent one stays quiet. The section installs a `setfenv` polyfill
so 5.4 exercises the LuaJIT sandbox path that all of this lives in â€” untested until now.
Suites **4198 + 707**. **Promoted to main the same hour, deliberately un-field-confirmed**
(Henrik: *"push to main so he can test"*) â€” the tester cannot re-test the thing that broke
for him until it is on main, so the usual field-confirm-then-promote order is inverted on
purpose here, and the merge queue records that. **FIELD-CONFIRMED within the hour: "it
works."**

One correction to the story, and it matters for the next legacy file: the missing comma was
**not** rot in an ancient file â€” it was a fresh hand edit. He had pulled an even-older
aug-suffixed entry (`MistSilkCapeAug`, from a generation of the format that baked the
augment into the key) out of that list and not put the comma back. So a legacy job file is
not a fossil to be read once; it is a file people still edit, with the ordinary consequence.
That is the whole argument for the red parse line: the failure mode isn't exotic decay, it's
a Tuesday.

## Session "the Ventures rings" (2026-07-28, on `dev`)

Henrik, with two wiki links: the Gear Helpers â†’ **Crafting Gear** panel needs the EXP
Ventures exchange in it â€” Craftkeeper's Ring 1,000, Artificer's Ring 1,000, Craftmaster's
Ring 2,000 â€” and the note that Craftmaster's Ring upgrades to **+1** through Synergy.

**The rings were never invisible to the ENGINE â€” only to the player.** All four are in the
catalog with their synth mods (`SynthMaterialLoss` / `SynthSuccessRate` / `SynthHQRate` 1
and 2), and the craft ladders are data-driven off exactly those stats, so an owned
Craftmaster's Ring has been getting equipped on the `hq` goal all along. What the panel
showed was guild torques, guild rings and four universals â€” nothing that mentions Populox.
So a player reading the panel to answer *"what should I go get?"* was told to grind eight
guilds and never told about a 2,000-point ring that beats most of them.

**Where they went.** The matrix is three columns (Torques | Rings | Universals) at a fixed
`colW` pitch. The Ventures pieces are rings, but they went in the **third** column, under
its own `Ventures` divider â€” because the useful part is the *price*, a per-row tag has to
fit, and only the rightmost column has nothing to its right to collide with. Midras's Helm
+1 moved out of the plain universals list into the same block: it is the same Populox
exchange at 3,000, and one home per item beats two. Craftmaster's Ring +1 closes the block
tagged `synergy`.

**The prose is hovers, not paragraphs** (the 07-24 panel-text standard): the `Ventures`
label carries where Populox stands (Upper Jeuno I-11) and the point that these carry a flat
synth mod, so unlike guild gear they count for *every* craft. Each price tag carries its own
hover. The `Torques` and `Rings` column headers became help labels too, since the Artisan's
+1 halves come off the same furnace â€” one string, re-worded for the Rings column by gsub, so
the two can never drift apart.

**One real bug fell out of listing them.** `CRAFT_UI.level()` â€” the coverage light on the
Gear Helpers row â€” only counted guild torques/rings. A character whose only craft gear was a
Craftmaster's Ring read **"nothing applicable"** while the ladder was busy equipping it.
Populox rings now count as level 1 alongside guild gear, and the level-1 label changed from
"craft-specific gear" to "basic craft gear", which is what it now means.

**Sources, and one discrepancy worth recording.** Costs and the furnace recipe are the
CatsEyeXI wiki (`Content/Ventures`, `Systems/Synergy`); the mods are the server's own
`item_mods.sql` (28585/28586/28587). CatsEyeXI never implemented the synergy minigame â€”
you trade to the furnace in Port Jeuno; there is no skill, fewell or rank check, and the
+1 wants 3x Guild Token. **The local server clone still calls id 26171 `rufescent_ring`;
the shipped catalog (scraped from the live API) calls it Craftmasters Ring +1 with
`SynthHQRate` 2, and the wiki agrees with the catalog.** The clone is simply behind the
live server on this item â€” worth remembering the next time the clone and the catalog
disagree about a custom item: recency, not authority, is usually the difference.

**Status:** **ON MAIN** (promoted the same hour on Henrik's *"push to main"*, deliberately
ahead of its field round â€” the second such inversion today, and a cheaper one: no scoring
change, so the worst case is a panel column reading wrong). Addon **`2026.07.28o`**, engine untouched â€” display and one coverage
light, no scoring change. New smoke section `CV0-CV14` drives the **real** craft detail view
against a stub imgui: the view had no render coverage at all (section 8 only exercised the
manifest ladders) and `renderTab` swallows render errors in a pcall, so a typo'd upvalue
would have blanked the panel in-game and passed every load test. It asserts the rows, the
prices, the hovers and both coverage-light states. Suites **4198 + 726**.

**Known, not changed:** Craftkeeper's Ring scores only on the `nq` goal â€” `SynthMaterialLoss`
is read into `nqScore` and nowhere else, so it can never be picked for `hq` or `skillup` even
when the slot is empty. Arguably material loss helps every goal. That is a *scoring* change
(it moves what the engine equips), so it waits on Henrik rather than riding a display commit.

## Session "the bag you are carrying is not somewhere else" (2026-07-28, on `dev` â€” addon `2026.07.28p`)

Henrik, from the field: the E-Box Restock **yellow** icon *"is showing itself if we have items
in our field containers (mog sack, mog case and mog satchel). This is wrong. It should only
show if the item is in mog house containers, such as mog locker, storage etc."*

**The premise was wrong, not the code.** Three days earlier (v2 grill C2) the icon was
specified as *"you own these â€” just not in Inventory"*, counting Satchel/Sack/Case as places
you cannot use an item from. Mechanically true; in play, false â€” those bags are **on your
person**, one drag away, and the game will happily let you fix that yourself in the field. So
the icon lit up about stock already in the player's pocket, and its click spent **box** stock
buying duplicates of it (the deliberate over-draw, hover-explained, that C2 signed off on).
The stock that genuinely cannot answer a shortfall out here is what sits at the **Mog House**:
Safe (1), Storage (2), Locker (4), Safe 2 (9) â€” you cannot reach any of it until you go home,
which is exactly when the box is the only fix.

**What changed.** `rw.otherBagNeed`/`needsOtherBag` â†’ **`homeStockNeed`/`needsHomeStock`**, ctx
`{ inv, other }` â†’ `{ held, stored }`. `held` is now *green's own on-hand* â€” Inventory +
Satchel + Sack + Case + what your quivers hold â€” so a Mog Case copy silences yellow exactly the
way it already silenced green. `stored` is a second bag pass over the Mog House containers
(`restockui.homeScan`, the field scan refactored into a shared `scanBags`; quivers are **not**
unpacked there â€” a pouch in the Safe is stock you cannot reach either, and this icon reports
*where things are*, not what they would be worth once opened).

**The over-draw died with the premise.** Yellow now plans on green's arithmetic, restricted to
the flagged items, because there is no longer a reachable copy to double up on. What keeps it
from being a second green button: **it does not require the box to stock the item**, so it
fires precisely when green is silent â€” *"the box can't help and yours are at home"* is the most
useful sentence this icon ever says, and the dimmed-button path already had the words for it.

**Wardrobes are not Mog House bags here.** They hold gear only, and gear in a wardrobe is
equippable where you stand â€” the opposite of the thing being flagged. Temporary (3) is out for
the same reason in reverse: event items are not stock. That the ruling *is* a bag split, and a
split that will be tempting to widen later, is why `restockui._HOME_BAGS` / `._FIELD_BAGS` are
test seams and **RS9h** asserts the two lists are disjoint and that 5/6/7 are on the carried
side. RS9e pins the reported bug directly: a Mog Case copy is held, so it never raises the
icon. RS9f pins the new distinctness: an empty box still raises it (`plan.badge == 0`, one
`homeStockNeed` row).

**Same session, second ruling: the add-picker stops asking you to walk over** (`2026.07.28q`).
Henrik: *"Trove can always search items when out in the field, maybe we should remove that
distance limitation as well for search only."* He is right, and the sibling proves it â€”
`trove/plugins/ebox.lua` has **no distance or zone check on any 0x1A4 action**; it sends
SEARCH, GET_SUMMARY, GET_CATEGORY and WITHDRAW whenever its window is open. So the server
answers a search wherever you stand, and the near-box rule on *ours* was dlac's invention, not
the protocol's. [[sibling-addons-signature-authority]] again: the answer was on disk.

Worth being precise about what the 07-20 field round actually established, because the doc
line read broader than the evidence: *"the box range is 5 yalms"* was measured on **fetching**
(the buttons go dead-red beyond it). Nothing was ever tested about search. The picker's gate
was inherited from the fetch gate by proximity of code, not of reasoning.

The NFR is untouched, and it is worth saying why rather than asserting it: the rule this
client exists to serve is *don't put traffic on the wire that nobody asked for*. A search is
one packet **per explicit click**, still behind one-in-flight and `MIN_GAP`. What stays
near-box is exactly the traffic with no click behind it â€” `verifyCategories`, the automatic
counting â€” plus withdrawals, which Henrik scoped out himself ("for search only"). The panel's
proximity line now says what it really means (*"get within 5 to fetch"*), and `/dl debug
ebox`'s *"too far to query"* became *"too far to fetch or count"* â€” a readout that overstates
a gate teaches the wrong model to whoever reads it next. `EBC21d` pins the decision headlessly:
`nearBox()` false, `search()` still returns true.

**Deferred, and now narrower:** C2's option (b) â€” *moving* items instead of buying more â€” only
ever applied to the field-bag case this revision retires. If the 0x029 move path ever lands it
belongs in the panel as a convenience, not on this icon. Suites **4201 + 726**, both runtimes.
Not yet field-tested: the icon's whole trigger now depends on Mog House containers being
readable from memory while you stand in the field. `gear/gearcheck.lua` has warned *"it is in
Mog Safe"* during play since the native era, so the reads are proven â€” but proven for gear in
the Safe, not for a Locker on this server; Henrik confirms it at a box.

## Session "the Status column becomes a switch" (2026-07-28, on `dev` â€” addon `2026.07.28u`)

Henrik, going down the Gear Helpers list row by row: Elemental Staff, Elemental Obi, Oneiros
Grip and E-Box Restock are *"fine, don't touch"* â€” Crafting, Gathering, Fishing and Chocobo
each get **"an on or off slider (same as hobby, only one can be active)"**.

The four he named are exactly `idleexcl.MEMBERS`, which is the whole reason the ruling is
coherent rather than cosmetic: those four rows describe something you **arm**, and the other
five describe something that is either always available (a slot rule waiting for its `dlac:`
entry) or switched somewhere else. A column that says *"FULL KIT -- awesome"* answers "how good
is my gear", which the row's **name colour** already answers on the same line. It never
answered "is it running right now" â€” and for an armed hobby that is the only question the list
view is asked.

**Nothing new was invented to do it.** The pill is `craftbar.onOffSwitch` (its sixth surface),
and the switch behind it is the watcher's own `setEnabled` / `setAutoHelm` reached through a new
`idleexcl.setOn(key, on)`. That indirection is the point: `idleexcl` already owned *which four*
and *how each stands down* (`disable()`, HELM clearing both flags), but could only ever disarm â€”
the arming half lived scattered in each caller. `setOn` completes the table with `enable()` and
routes through the watcher, so `guardActivate` still refuses a second hobby, in chat, from
inside the watcher. The list surface has **no lock logic of its own**; it returns the state it
did not reach and the pill snaps back. Lock-while-active, never auto-disarm (ADR 0017), holds
unchanged â€” and the hover names the blocker *before* the click, which the bar could not do
because it only ever shows one hobby at a time.

**Where the coverage sentence went.** Into the pill's hover (`Your gear: FULL KIT -- awesome
(HELM+3, Surv+8).`) â€” the panel-text standard, and the detail view is still one click away.
The row name keeps its coverage ramp, so the green-to-red glance survives.

**The one real trap was ImGui, not product.** These rows are drawn as a full-width `Selectable`
with the three columns painted on top by `SameLine` â€” so the switch would have sat *inside*
another item's hit box, and ImGui gives an earlier item's `HoveredId` right of way unless the
row calls `SetItemAllowOverlap` (which `profilesmenu` feature-detects precisely because not
every binding exposes it). Rather than depend on that, a pill row **ends its click target at
570** and the switch starts at 580: the two hit boxes never share a pixel, so there is no
overlap to resolve and no API to detect. `HP8`/`HP9` pin the widths.

The list view had **zero** render coverage before this â€” `renderTab` pcalls `renderAutomations`,
so a silent nil global here blanks the entire tab in the field while every load test stays
green (hard rule 8, the fault this project keeps re-learning). `HP0`â€“`HP16` now drive the real
render against a stub imgui: which rows got a pill and which kept their sentence, that ON
follows the *armed* hobby rather than the row's own coverage, that the coverage line survived
into the hover, and that a click reaches `setOn` with the right key and direction. `IE7*` pins
`setOn` headlessly, including the two things a careless dispatcher gets wrong: HELM must arm
**Auto HELM** and not the unwired manual idle flag, and an arm refused by the lock must report
`false`. Suites **4218 + 751**, both runtimes.

**Field round, same day.** Henrik: *"the on and off syncs to hobby bar as well, so seems to be
the same listener."* Confirmed â€” and worth naming precisely, because the mechanism is the
opposite of a listener. Nothing subscribes to anything: every surface **re-reads the watcher's
live in-memory state each frame** (`idleexcl.getActive()` â†’ `craftwatch.enabled` /
`helmwatch.autoHelm` / â€¦, one module instance per addon state), so the bar, the badge, the
detail panels and now the list are all views of the same variable and *cannot* drift. That is
the same lesson [[ebox-v2-arithmetic-model]] paid for in the other direction â€” the read that
looks redundant is what heals a wrong belief. The rule for the next hobby surface: read live,
never cache an armed flag.

## Session "Arbiter: preserve unknown Claim Priority rows" (2026-07-29, issue #136)

**Theme:** the Claim Priority order file was silently deleting rank rows it did not
recognize. `arbOrder` (the live view) drops any unknown name â€” correct for the
arbitration walk and the Priority tab (no ghost rows, resolution unchanged) â€” but that
same drop ran again at WRITE time: `arbwatch.setOrder` sanitized before serializing, so
the next drag/save rebuilt the file from known claimants only. An uninstalled module's
claimant, a future claimant, or a hand-added row lost the player's drag position forever.

**Landed:** a second, WRITE view â€” `arbiter.arbOrderPersist(newOrder, rawSt)` (pure;
re-exported as `dispatch.arbOrderPersist`, mirrored in `arbwatch.persist` with the same
keep-in-step discipline as `sanitize`, NK25c). The known rows are ordered by `arbOrder`
(so a drag, restore-at-default and the ceiling/floor invariants all still hold); each
unknown row is woven back ANCHORED to the known row it followed in the raw file, so it
keeps its place relative to the rows around it across any number of reorders. `setOrder`
now reads the raw (unsanitized) file â€” new `readRawState` seam, shared with `M.order` â€”
and persists through `persist` instead of `sanitize`.

**Why anchoring, not an absolute index:** a drag operates on the known-only live list, so
the writer has to re-place the unknown against a list the unknown was never in. Anchoring
to the preceding known row keeps the row "in the same gap between claimants" no matter how
the knowns reshuffle around it. Front-anchored unknowns (no known predecessor) sit right
under the Disabled ceiling; the ceiling/floor are re-pinned last, so a hand-mangled file
that put an unknown at an extreme can never displace either invariant.

**Reclaim-on-return falls out for free:** once the identity is a KNOWN claimant, `arbOrder`
finds the row LISTED in the file and honors its saved position over the default â€” the same
restore-at-default law (v122), read the other way. No new code; ARP5 pins it.

**Engine behavior is unchanged**, so `dispatch.M.VERSION` is NOT bumped: `arbOrderPersist`
is called only by the addon-side writer, never in the equip/dispatch path, and the arbstate
file format (`return { order = {...} }`) is untouched â€” it may just carry more names now,
which the engine already drops on read. Tests ARP1â€“6 (engine seam), AB8â€“8e (writer seam +
on-disk round-trip), NK25c (fallback mirror). Suites **4237 + 755**, lua5.4.

## Session "Action sequencer + JobHelper row + Reward now" (issue #138, PRD #135)

**Theme:** make the CONTEXT.md **Action sequence** real, demoable by the BST Panel's
**"Reward now"** button. Builds on the #137 Job helper module system (both on `dev`).

**Landed (four pure cores + live glue, all headless-tested at their seams):**
- `feature/actionseq.lua` â€” the singleton Action sequencer. `request/tick/arbitrateRequests`
  drive `claiming â†’ firing â†’ released` / `refused` / `aborted` against an injected io
  (`worn/blocker/fire/release/emit`). Never-fire-bare (the command fires ONLY after every
  needed slot verifies worn, and exactly once via the `_fired` latch); a definitive blocker
  on a needed slot refuses loudly; the gear never landing inside the timeout aborts; success
  is silent; one sequence live at a time (a started one is never preempted; simultaneous
  contenders resolve by module order). Live `pump()` (wired in `dlac.lua` d3d_present) reads
  worn via `dispatch.wornName`, blockers via `disabledOn`/`isLockedSlot`, fires the chat
  command, releases via `dispatch.kickDefault` (the next arbitration restores gear). Tests AS*.
- `feature/recast.lua` â€” the ability recast READINESS service (the Central-services gap).
  `readyFor/rewardReady` â€” reader injected, UNKNOWN reads READY (the courtesy gate; the
  sequencer's own verify is the real safety net). Reward = ability 103; the recast-timer slot
  is ported from the Pup-Helper reference and FLAGGED for field verification. Tests RC*.
- `feature/petfood.lua` â€” the eight-tier pet-food **Ladder** (`pick`): highest tier first,
  gated by equip level and equippable-bag stock; carrying none is a loud refusal. Tier data
  is local (the catalog ships only six of eight â€” Gamma/Epsilon absent). Tests PF*.
- The `JobHelper` claimant row. `arbiter.placeJobHelper` weaves it into the live rank order
  directly below its anchor (default Locks) â€” deliberately NOT in `ARB_ORDER_DEFAULT`,
  because its Claim Priority position is per JOB (`jobhelpers.rankAnchorFor/setRankAnchor/
  placedOrder/moveRankRow`, stored in a new `rank = {[JOB]=row}` config block). A CLAIMANTS
  row reading `actionseq` rides the standing rank walk; `dispatch.jobHelperPlace` runs it
  every Default and for `/dl prio`; the row hides with zero modules. Rendered "Job helper"
  via `claimantLabel`. Tests JHR*/JHW* + the CR* registry pins updated (JobHelper is the one
  per-job "extra" not in the global default order).
- `jobhelpers/bst/init.lua` â€” the "Reward now" button: pick food, overlay an optional Reward
  set, open the sequence, gray while Reward is down; main-job + module-activity gates apply.

**Why the per-job placement is not in the global arbstate:** the row's position must be
per job while every other claimant is global, so it is placed live (`placeJobHelper`) on top
of the sanitized global order rather than persisted into it â€” which also makes "preserved
positions stay dormant with zero modules" fall out of the config store for free, mirroring
the #136 unknown-row preservation slice.

**Engine behavior:** a new claimant row + a new sig leg (APPENDED, so the nine existing legs
stay byte-identical and no live session retraces until a sequence claims). `dispatch.M.VERSION`
was bumped 154 â†’ **155** at the merge (the new claimant row IS a handshake change).
Both suites green (**4332 + 789**, lua5.4). Player-facing strings and the
Reward command token await the maintainer's sign-off and a field round.

## Session "BST Fight: the engage/target edge service + the three-way switch" (issue #139, PRD #135)

**Theme:** the first Job-helper behavior that acts on its OWN signal instead of a button â€”
and the central service that supplies the signal. Builds on #137 (module system) and #138
(Action sequencer + the `JobHelper` claimant row), both on `dev`.

**Landed:**
- `feature/engagewatch.lua` â€” the **engage/target edge** central service (new row in the
  architecture doc's Central-services table). ONE decoder for both battle edges off the
  outgoing action packet: `0x01A` category `0x02` = **engage**, category `0x0F` = **retarget**
  (what auto-target rolling to the next mob sends). The entity comes from the PACKET
  (UniqueNo u32 @0x04, ActIndex u16 @0x08) and travels with the edge; a **per-target**
  5-second debounce means the same entity notifies at most once a window while a different
  one notifies immediately. Subscribers are pcall'd. Tests EDG* replay both packet kinds byte
  for byte through the pure decode and drive the debounce at the pump seam.
- `jobhelpers/bst/fight.lua` â€” the three-way **Fight** switch: Off / When I attack (engage
  edges only) / Follow my target (both). `decide(edge, state)` is pure â€” edge + state in,
  command decision out â€” so every acceptance criterion is a headless check (BFT*).
- `jobhelpers/bst/config.lua` â€” the BST Helper's OWN per-character settings file
  (`<char>\dlac\jobhelper-bst.lua`, `fmt`-versioned, declared keys only, written on mutation
  only), the PRD's "one config file per module". Fight defaults **off**.

**The three things worth not re-deriving:**

1. **Capture the entity, do not re-read it.** `/pet "Fight" <t>` is the only chat command that
   can name an arbitrary monster, and `<t>` resolves at EXECUTION time â€” one more auto-target
   roll and the pet goes at the wrong mob. So the packet's entity is confirmed against the live
   target before the command is issued, and a positive mismatch cancels the send. An
   *unreadable* target does not cancel it: a read we cannot make must not silently disable the
   whole feature. The three states (confirmed / contradicted / unknown) are the point; collapsing
   them to a boolean loses either the safety or the feature.
2. **Two gates read UNKNOWN as no, one reads it as yes â€” deliberately.** `active` (the module
   activity predicate) and `hasPet` must be positively true, which is the opposite of dlac's
   standing buff-cache discipline ("an unknown read must not flip behavior"). That discipline is
   about GEAR, where the unknown-reads-as-no branch is the one that changes what you wear; here
   the unknown-reads-as-yes branch is the one that ISSUES A COMMAND, and AC4 is literal â€” no pet
   means no command is ever issued, not "a command the client refuses". `targetOk` keeps the
   original discipline, because there the unknown branch is the passive one.
3. **Heel needed no code, and that is the design working.** Nothing polls pet status, nothing
   repeats, nothing retries a refused send: every send traces to one packet the player's own
   client sent. So a pulled-back pet stays back until the next real edge, and "fire-and-forget"
   and "no pet-idle gate" (both PRD requirements) turn out to be the same property stated twice.
   A "pet is idle, nudge it" beat would break all three at once.

**Threading:** the `packet_out` handler decodes three integers and appends to a capped queue â€”
nothing else. The debounce, the entity-name read and every subscriber callback run on the MAIN
thread in `pump()`, wired into `dlac.lua`'s `d3d_present` beside the sequencer's. That is the
chocowatch rule, and the dlacprobe crash is why it exists.

**On "extract the existing inert reference implementation":** the field-proven decode of these
two edges is `accwatch.lua`'s `/dl acc` engage watch â€” *"Every engage (0x01A action 0x02) AND
battle-target switch (action 0x0F, auto-target)"* â€” live on the parked `feature/autoacc` branch
pending GM approval, with an inert byte-identical dev copy at `share/mob-stats/accwatch.lua`
(reference only, never loaded; the decode here was verified against it at review). `engagewatch`
is the one LIVE shared implementation; when autoacc lands it subscribes here instead of carrying
a second copy, and the module header, the Central-services row and this entry all say so.

**Chat stays silent.** Fight fires on every pull, so a line per pull is noise, not news; the
Panel reports the last decision instead ("sent your pet at Nursery Nazuna", "in town", "no pet
out"). A refusal here costs nothing, unlike Reward's â€” which is why Reward is loud and this is
not.

Both suites green (**4429 + 793**, lua5.4). Player-facing strings (**Fight**, *Off* / *When I
attack* / *Follow my target*) and the exact `/pet "Fight"` command spelling on CatsEyeXI await
the maintainer's sign-off and a field round.

## dayMatch trigger condition (2026-07-29, ADR 0029, engine v156)

**Theme:** the environment vocabulary gets its missing third. Henrik, field: *"We currently
have dayWeatherBonus and weatherMatch as conditions in precast and midcast. But we need one
for dayMatch as well. There are items that give you bonus solely if the day match what you're
casting."*

**Landed:** `dayMatch` (Precast + Midcast, tier 30, true/false polarity) â€” true when the
action's element equals TODAY's day element. `dayMatchesAction` (dispatch.lua) reads
`gData.GetEnvironment().DayElement` â€” the SAME field `netForElement` already scores for the
obi, so the net's day half and this condition can never disagree â€” cached on `ctx.del`, the
`ctx.wel` pattern. No action element / Non-Elemental / unreadable day matches NEITHER
polarity (never fires blind). GUI: a third flag in the Precast/Midcast builder under
`weatherMatch`, its own colour in the rule boxes (a warm rose â€” the environment trio must not
read as one colour), and all three hints now cross-reference each other so the menu itself
steers you to the right one.

**Why a third condition and not a mode of `dayWeatherBonus`:** ADR 0018's both-directions
proof, re-run on the day axis. For a Fire spell â€” on **Firesday in Water (opposing) weather**
the net is +1 âˆ’1 = 0, so `dayWeatherBonus` stays quiet while a day-only item IS paying out
(under-fires); on **Earthsday in Fire weather** the net is +1, so `dayWeatherBonus` fires while
the item is dark (over-fires). `weatherMatch` has no day term at all â€” wrong axis outright.
Only the plain day equality tracks when a day-only bonus is live. DM14â€“DM17 pin exactly that
independence, in both directions, against both neighbours.

**The asymmetry worth remembering:** there is **no "clear day."** All eight weekdays carry an
element (`WeekDayElement` / `WEEK_DAY_ELEMENT`, Fire..Dark), so a day we can read is always a
real match or a real non-match and only a broken read is unknown â€” where weather has a genuine
`None` (Clear / Sunshine / Clouds / Fog) that `weatherMatch` has to treat as a real non-match.
Day is also **not** storm-aware: the weather read folds a Scholar's own storm over the zone,
but nothing in the game changes the day, so `DayElement` is the plain calendar read.

**Deliberately NOT claimed:** unlike ADR 0018, this one is not pinned to a named server
mechanic â€” the CatsEyeXI source is not on this machine and no specific item was named. It
ships as a calendar primitive ("the day element equals the spell's element"), true regardless
of which item motivated it; pinning one item's exact gate (day only, or day-or-weather the way
the retail obi tooltip reads?) is a follow-up that changes what a player **composes**, not what
this condition means.

`addon.version` 2026.07.29h; DM1â€“DM24 green, both suites **4455 + 793** (Windows lua 5.4).
Note for the record: the working tree was shared with a live session mid-round on
`engagewatch`, so the run counts include its two new EDG checks.
## Session "BST auto-Reward: the pet vitals service + the threshold" (issue #140, PRD #135)

**Theme:** the second standing Job-helper behavior, the first that SPENDS AN ITEM, and the
central service that supplies its signal. Builds on #137 (module system), #138 (Action
sequencer + the "Reward now" button) and #139 (the Fight switch), all on `dev`.

**Landed:**
- `feature/petvitals.lua` â€” the **pet vitals** central service (new row in the architecture
  doc's Central-services table). One question â€” presence / HP% / TP / name â€” published to
  subscribers once per dispatch beat by `pump()` and answered on demand by `get()`.
- `jobhelpers/bst/reward.lua` â€” the **Reward rule** AND the act. `decide(vitals, state)` is
  pure, so the threshold, the lockout and every gate are headless checks (BRW*).
- `jobhelpers/bst/config.lua` â€” three new rows: `rewardArmed` (default **off**),
  `rewardThreshold` (default **50**) and `rewardSet`.
- The Panel's Reward section gains the rule switch and the pet-HP% slider; the "Reward now"
  button stays exactly where it was.

**The five things worth not re-deriving:**

1. **The rule is a second REQUESTER, not a second implementation.** The act â€” pick the food
   off the Ladder, overlay the optional Reward set, open ONE Action sequence â€” moved out of
   the button's click handler into `reward.request(id)`, and both callers land there. So the
   acceptance criterion "identical refusal behavior to the button" is a property of the code
   rather than of two test suites agreeing with each other, and BRW62â€“BRW66 prove it by
   comparing the two paths' requests claim-for-claim. A copy would have passed its own tests
   and drifted on the first change.
2. **A central service must not be born as the second implementation of its own answer.**
   dlac already had exactly one pet reader â€” `gData.GetPet()`, the LAC-parity provider in
   `feature/nativedata` that the ENGINE reads every dispatch for the pet trigger conditions
   (v63). `petvitals` consumes it; it does not open a second `GetPetTargetIndex` /
   `GetHPPercent` pair. And the Fight switch's own raw pair â€” written in #139, before there
   was anywhere else to ask â€” was deleted in the same commit, the same move `engagewatch`
   made for the edge decode.
3. **Presence is two-state on purpose, and that is not a shortcut.** `gData.GetPet()` answers
   nil for both "no pet" and "the read failed", and the two are deliberately NOT separated:
   every consumer of this service issues a command or spends an item, and #139 already ruled
   that a read we cannot make is not permission to do either. The individual vitals stay
   nil-able, because there the honest answer IS available â€” a present pet whose HP could not
   be read is reported, never guessed at, and `decide` refuses on it (`no-hp`). Guessing a
   pet's HP is how a Reward gets fired at a healthy pet.
4. **The lockout is armed by ATTEMPTS, and two holds are deliberately not attempts.** A rule
   reads a STATE, and a state persists â€” a pet under the threshold is still under it on the
   next beat â€” so without a lockout one hurt pet becomes a stream of commands and a stream of
   chat lines. One attempt per window gives "at most one refusal line per window" for free.
   But "a sequence is already running" and "Reward is still on cooldown" attempted nothing,
   so neither burns the window: the moment the recast returns, the held Reward goes (BRW84).
   The recast hold is also **silent** â€” the button it mirrors is greyed out and says nothing,
   so "identical to the button" means saying nothing here too. That is what stops Reward's
   ~90-second recast from becoming three refusal lines a minute, which a naive "every hold is
   a refusal" reading would have shipped.
5. **The food ladder was reading the wrong level.** Carried over from the #138 merge review:
   `petfood` gated on raw `MainJobLevel`, making it the one picker in dlac that ignores
   `/dl set level main` â€” and under LEVEL SYNC it would pick a tier above the cap, have the
   equip refused, and end in a contained verify TIMEOUT instead of correctly falling a rung.
   It now reads the override first and `MainJobSync` second, exactly as `dispatch`'s
   `playerLevel`, `utils.determineLevels` and the Ammo panel's `gearLevel` do. PF7â€“PF12; the
   house law is the AutoAmmo v134 lesson, stated a third time.

**The one design call that is not in the issue text: the rule ships OFF.** The issue names a
slider defaulting to 50 and no switch, but `jobhelpers/bst/config.lua` already carries the law
that produced Fight's default â€” *"this module ISSUES COMMANDS, so a freshly installed helper
must never start driving the pet on its own"* â€” and this rule additionally EATS a player's
food. So the switch is new and defaults off, and 50 is the slider's resting position rather
than an arming decision. Flagged for the maintainer in the PR: overruling it is one default.

**Threading and cost.** `petvitals.pump()` rides `dlac.lua`'s `d3d_present` beside the
sequencer's and the edge service's, throttles itself to `TICK_S` = 0.4s (the engine's own
dispatch beat), and **does not read the world at all while nothing is subscribed** â€” so the
service is free on every job that is not BST. `get()` has no cache and reads now, so no caller
can be handed a record older than its own question. The service also joined the load array,
not just the pcall'd pump: the #139 review lesson is that a module only ever required inside a
per-frame pcall fails silently forever and is invisible to `/dl check`.

Both suites green (**4572 + 798**, lua5.4). No seeded file changed, so `dispatch.M.VERSION` is
untouched. Player-facing strings (**"Reward my pet when it drops low"**, *below N% pet HP*),
the 30-second lockout, and the ships-off default await the maintainer's sign-off and a field
round; pet TP is published but nothing consumes it yet, and its scale is unverified against
the live server.

## Session "Fight goes poll-driven" (2026-07-29, field round 2, addon 2026.07.29j)

**Theme:** the edge-driven Fight failed its second live round -- after the (target,kind)
debounce fix, the captured-entity confirm still refused every send. Henrik: "can you look
at the pup-helper addon, see how he handles it? I think he has it all covered."

**Landed:** `bst\fight.lua` REWRITTEN on the field-proven POLL shape (Pup-Helper's, and
the GearSwap BST convention -- pet-handling reference section 4.2): every pet-vitals beat
(0.4s), a PURE `pollDecide` asks "engaged + pet idle + target?" and issues `/pet "Fight"
<t>` through the central door. The pet-idle gate is the spam brake AND the retry -- a
refused command leaves the pet idle so the next beat tries again; a command that took
makes the pet non-idle and the issuing stops. `follow` re-sends a FIGHTING pet when the
POLLED target changes (works for hand-sent pets too). Restraint: RETRY_S = 2 per target,
MAX_TRIES = 3 per (engagement, target), then a visible `capped` Panel reason that names
the command-wording suspicion -- the remaining unknown if the field round still fails.
`petvitals.fromPet` now carries `status` verbatim (the idle gate consumes the service --
no second status read). engagewatch stays a central service (subscriber-less until
autoacc lands). Edge-driven `decide`/`targetConfirms`/`onEdge` died with their tests;
BFT1-30 pin the poll core + the beat glue (nil-override trap: `{k=nil}` is an EMPTY
constructor -- unreadable-state cases are literal states).

## Session "the maintainer day: options, layout, the promotion" (2026-07-29 evening, 29l-29o -> main)

The same day the agents built PRD #135, the maintainer session field-shepherded it. What the
agents did not write down lands here.

**Respect Heel became an option (29l, Henrik: "Make it an option so player gets to decide"):**
the poll rewrite had softened Heel (an idle pet kept being re-sent up to the cap); the fix is a
TOOK latch -- our send is observed to TAKE (the pet went non-idle after it), so idle-again at
the same target can only mean the player pulled it back -- behind a checkbox, default ON.

**The layout went job-first (29m, Henrik: "jobhelpers/bst/bst-helper/ since bst-helper is the
module of bst"):** the loader scans two levels, identity = the MODULE folder name (unique
addon-wide, duplicates refused loudly), the job folder only says where a module FILES. ADR 0028
amended. Module settings survived (the module's own config file is name-keyed).

**"Send when" became an option (29n):** drawn (engage) vs first swing -- engagewatch gained the
0x028 melee-round watch (actor @0x05, type bits at byte 10 -- the parse0x28 twin), network
thread stashes, pump compares against my id on the main thread, every engage edge resets.

**The promotion (evening, Henrik's "Once done, push to main"):** first staged on a `promo-main`
branch, which Henrik REJECTED as a third wheel ("I want a dev and a main") -- the pattern that
stuck: tie the promotion merge knot ON local main and hand Henrik `! git push origin main` (the
permission layer refuses Claude a main push in any form; the human presses the button). Landed
as `56221c1`, main content-identical to dev, the honest FIELD-CONFIRMED vs HEADLESS-ONLY ledger
in `c07f7ae`'s message.

**Two paid lessons, recorded so they stay paid.** (1) THE SHARED CHECKOUT SMUGGLE: a parallel
session's in-progress day-match tests rode a wholesale `git add tests/run_tests.lua` into 29g --
tests without their engine half, so every fresh checkout crashed while the dirty tree ran green
(the implementation sat uncommitted BESIDE the smuggled tests). Evicted (`47b7b20`); at the
day-match merge the eviction then outvoted their tests from the merge BASE and silently deleted
them again -- the suite TOTAL was the tell (restored verbatim, `54dc778`). Diff the staged copy
of any shared file before committing; treat a totals shortfall as a lost hunk. (2) THE
DEPLOYMENT GAP: the game plays the MAIN CHECKOUT's working tree -- worktree merges pushed to
origin/dev reach the field only when the checkout pulls, and a parallel session's dirty files
block that pull. A whole Fight field round was voided testing stale code. The load beacon
(debug\load-report.txt) is the one-line proof of what the game actually loaded; read it before
any "reload and retest" ask.

## Session "the percent sign that printed a pointer" (2026-07-30, `2026.07.30a`)

One screenshot, one caption, one durable client fact. Henrik, on the BST Helper's Reward
section: *"I don't know what value that is, seems like mumbo jumbo hex data."* The caption
beside the threshold slider read **`below 51F4A60263et HP`**.

**THE FACT, and it belongs on the same shelf as "a state never hears its own QueueCommand":
every imgui TEXT call is a `printf` FORMAT string** --
`Text`, `TextColored`, `TextDisabled`, `SetTooltip`, `LabelText`, `BulletText`. So a `%` in
the *text* is a **conversion**, not a percent sign. `string.format('below %d%% pet HP', 51)`
produced the perfectly correct Lua string `below 51% pet HP`, and ImGui then read its `% p`
as the **`%p` pointer conversion**: it printed a heap address (`51F4A60263`) and ate the `p`,
leaving `et HP`. Nothing was corrupt and no value was wrong -- the string was interpreted
one layer further down than its author expected.

**Why it was panelkit and only panelkit.** Ten UI modules already carry a private
`local function esc(s) return (tostring(s):gsub('%%','%%%%')); end` -- ammoui, automationsui,
arbmonui, chocoui, fishui, helmui, triggersui, restockui, jobhelpersui, gearfmt. The trap was
known; the brand-new Panel kit (`ui\panelkit.lua`, written the night before) simply shipped
without the copy, and it is the ONE module through which every Job helper's text now flows.
The fix puts the escape at the kit's funnels rather than at the call sites: `M.text` (behind
`dim`/`ok`/`warn`/`err`), `M.disabled`, `M.header` (label *and* hover -- `uistyle.helpLabel`
draws and tooltips RAW), and `tipOn`. A module author writing "below 50%" in words cannot hit
it now, which is the only version of this fix that survives the next author.

**The `bind()` trap that came with it.** `panelkit.bind(im)` builds the bound kit by *walking
`M`* and wrapping every function with the handle pre-applied -- deliberately, so a widget
added later cannot be forgotten. `esc` takes **no handle**, so the wrapper would have made
`ctx.ui.esc(s)` escape *a table address* and silently return garbage. `NOT_BOUND` (`bind`,
`esc`) is now the list of things carried over as they are; PK19b pins it. Any future
handle-less helper in that file needs the same row.

**Henrik's ruling on the caption itself: delete it** (*"That is not really relevant text IMO
can prolly be removed"*). The slider already renders `51%` inside itself, and `ui.ruleStatus`
states the meaning a line below (`Armed: below 51% pet HP.`), so the caption was a third
copy of one number. Deleted -- and this is the shape of most panel-text rulings on this
project: the surface that already answers the question keeps the answer.

**Two latent siblings died with it**, both in the same Panel and both invisible in the
screenshot only because the character was in town: `Armed: below 51% pet HP.` (the status
line, drawn the moment the rule *is* acting) and `Pet: <name> at 51% HP.`. They are fixed by
the funnel, not by editing their strings.

**What is NOT a format string, so nobody escapes twice:** `Button`, `Selectable`, `BeginCombo`
and the other *label* parameters. `ui\fishbar.riskTag` builds `lose 30%, snap 12%` and feeds
it to a `Selectable` -- correct as it stands.

**The blind spot, stated plainly because it is structural:** `tests\smoke_ui.lua` renders
every tab against a **stub** imgui that records strings and does not printf, so this whole
class of bug is invisible to it -- exactly like the 300px width clipping the same kit paid for
a day earlier. The escaping law is the guard; the field screenshot is the test. PK21-24 pin
the escape at the four seams (status text, the last line, disabled text, tooltip).

Recorded where authors will meet it: the `esc` block and the docblock lesson list in
`ui\panelkit.lua`, the Central-services row in architecture.md, and §6.9 of the authoring
guide (*"If you ever call `ctx.imgui.Text*` yourself, escaping is yours -- use
`ctx.ui.esc(s)`"*).

**Provenance, because the tree was not clean and then it moved under us.** This session opened
on a working tree carrying the whole **Job helper module API v2** train uncommitted from the
previous evening (`feature\modapi.lua`, `feature\modcfg.lua`, `feature\combat.lua`,
`ui\panelkit.lua`, `docs\templates\example-helper\`, BST's four files rewritten onto them,
`bst-helper\config.lua` deleted, the authoring guide rewritten for `api = 2`, ~2.5k lines) --
green on both interpreters, wired into `dlac.lua`'s load list and the Central-services table,
and *running on Henrik's client* (the screenshot that opened this session is the api-2 Panel),
but never committed and never version-bumped. So the fix was written into files that belonged
to a train still in flight, and while this entry was being written **that train's own session
committed** -- `f8df96b`, 03:42, `feat(jobhelpers)!: the module API` -- **sweeping this fix, its
tests, its guide bullet, its architecture row and this history entry into its commit**, along
with the `2026.07.30a` bump (the train had none of its own; there is no `29p`). The first sign
was a `git add` that staged nothing and a `git status` down to one file.

**THE PROMOTION PATTERN NARROWED, and this is an ops fact worth more than the fix.** Yesterday's
pattern was *"tie the promotion merge knot ON local main, hand Henrik `! git push origin main`"*.
Tried here, the permission classifier refused `git merge --no-ff dev` **while on main** -- so it
is not only the push that is his: **`main` cannot be written by Claude at all, locally included.**
What a handover session can do is everything up to the boundary -- commit, push `dev`, empty the
queue, and pre-write the promotion message where his merge can read it (`.git/PROMOTE_MSG`,
untracked by construction) -- and then hand over ONE command block:
`git checkout main; git merge --no-ff dev -F .git/PROMOTE_MSG; git push origin main; git checkout dev`.
The trailing `checkout dev` is load-bearing: the game plays this checkout's working tree, so a
checkout left on `main` is yesterday's deployment gap wearing a different hat. (Learned the hard
way in the same minute: the blocked merge had already switched the checkout to `main`, which
silently made Henrik's client hold `56221c1`'s files until it was switched back.)

**THIRD instance of the shared-checkout lesson in two days, and the first BENIGN one** -- worth
recording precisely because it went well, since the rule is about verification, not blame. What
made it benign was checking rather than assuming, in both directions: every edit was confirmed
present *in HEAD* (`git show HEAD:<file>` per file, not `git status`, which reads clean either
way -- a wholesale re-Write of a shared file by the other session would ALSO read clean), and
both suites were re-run against the committed tree (**4960 + 817**). Neither "it was swept, so
it is lost" nor "it committed, so it is fine" is a safe default. **One real cost survives:** the
commit SUBJECT names only the api-2 train, so `git log --grep` will never find the percent fix
-- this entry and the HANDOFF queue entry are its only pointers, which is why both name the
hash. The uncommitted `tests\fixtures\keepflow\...\lspreview.lua` line-ending change was left
out of everything, as before: provenance still unknown, content still identical.

## Session "the tab that never moved" (2026-07-30, E-Box Restock in the quick menu)

Two things landed: the **E-Box Restock row in the Teleports quick menu** (above the Hobby
bar, Crystal Warriors only, wearing the nudge's own crate icon), and — because that row
immediately demonstrated it — the fix for **`uihost.selectTab`, which had never worked**.

**The field report.** Henrik: *"if I push a button that should take me to the correct page,
but not on the correct tab… I click e-box restock in teleport menu, in the gear helper tab it
directs me to the correct menu, but when I open the GUI, I am still on the job helpers tab.
So I think there's a step missing here (this goes for many other things as well)."* The
"many other things" is right: **every** cross-link went through the same seam —
`gearui.openAutomation` (the Teleports row, the hobby bars' "open my panel", the restock
nudge's right-click, `/dl restock`). All of them set the correct detail view and left the tab
bar exactly where it was.

**Why it failed, and why nobody noticed for weeks.** `host.selectTab(label)` armed a
one-shot; the next `renderTabs` pass handed `ImGuiTabItemFlags_SetSelected` to that label's
`BeginTabItem` and forgot. But **ImGui applies a forced selection at the NEXT frame's
`TabBarLayout`** — on the pass that carries the flag, `BeginTabItem` still returns false
because the tab is still closed. So the one-shot had nothing to observe: *honoured* and
*ignored* produced byte-identical behaviour on the only pass it looked at (hard rule 12,
again). A second defect hid inside the first: the flagged branch tested `o == true`, throwing
away a truthy non-boolean return. When the forced tab IS the open one, that skips the content
**and `EndTabItem`** — an unbalanced tab item, tearing the very bar it was steering. The
headless drive reproduces it exactly: `unclosed: got 1, want 0`.

**The fix: hold the request until it takes.** `selectTab` now records a request that rides
every `renderTabs` pass until that tab is observed OPEN, then clears at once (holding it one
pass longer would refuse the player's next click). The budget counts **passes, not frames**,
so a jump asked for while the main window is shut waits for it to open instead of expiring
unseen. `host.pendingTab()` reports what it is trying to reach.

**What is still unproven, and what we did about it.** The SDK header on disk
(`plugins\sdk\imgui.h`) settles the C++ side — `BeginTabItem(const char*, bool* p_open = nullptr,
ImGuiTabItemFlags flags = 0)`, `ImGuiTabItemFlags_SetSelected = 1 << 1` — but **nothing on
disk shows how Ashita's hand-written Lua binding maps `bool*`**. Every sibling addon calls the
plain `(label, nil)` form; the one that passes flags (`ventures`) would look identical to a
player whether its flag lands or is dropped, so it is not evidence. The host therefore tries
the header's shape first and the fold-away `(label, flags)` shape after, and if neither has
taken within ~30 passes it **says so in chat, naming the tab**. A binding that ignores the
flag can no longer look like nothing happened.

**Tests.** smoke_ui `TAB1`–`TAB17` drive a fresh uihost against three stub bindings — working,
fold-away, and flag-blind — with a stub that models ImGui's real semantics (selection lands at
the next layout; an opened tab item must be ended). Verified failing against the old code
before the fix: `TAB5/6/7/11/12`. run_tests `SET55`–`SET59` were rewritten for the new quick
row: the source parse now reads each `renderQuickWindowRow` call as its own segment, understands
the `icon, fn` opt-out (art that is not key-named, an action menuui does not own), pins the
order `restock,hobbybar,lockstyle`, and pins the CW gate on the row it guards. Suites
**5141 + 859**, both interpreters.

**Round two: the chat line appeared.** Henrik ran it and got exactly the give-up line —
*"could not switch to the Gear Helpers tab -- this build's imgui ignored the tab-selection
flag."* Both argument shapes, full budget, nothing. **So this install's Lua binding does not
carry `ImGuiTabItemFlags_SetSelected` through to ImGui at all**, and the diagnostic did its
one job: an invisible failure became a one-line answer in a single round.

**The fix that does not ask.** Three rungs now, cheapest first. (1) `(label, {true}, flags)`
— p_open as a **table**, which is the shape `imgui.Begin` demonstrably honours in this very
addon (gearui's own window passes `isOpen` as a table and its X works), so it is the best
remaining guess at how the binding wants a `bool*`. (2) `(label, nil, flags)`, the header's
own signature — disproven here, kept because a correct binding lands the jump with no
artifact. (3) **THE REBUILD**, which needs no binding cooperation: a tab bar ImGui has never
seen has no selection and adopts the **first tab submitted to it**, so `host.tabBarId` hands
gearui a new bar ID and the wanted tab is submitted first until it opens. `gearui` must ASK
for that ID — hardcoding `'##ffxilac_tabs'` again would silently disable rung 3, so smoke_ui
`TAB25` pins the call. Cost: one frame with the tabs reordered and the body empty, and one
abandoned ImGuiTabBar per jump. That is the price of a jump that works.

**One ordering detail worth keeping.** The rebuild is armed at the END of a pass, never at
the start. Deciding it up front bumps the generation on the very pass a working flag lands —
and the next pass would then hand gearui a bar ImGui has never seen, throwing the selection
away again. Two of the four stub bindings (`TABLE`, `NILP`) exist to hold that line: they
assert the bar ID is **unchanged** when a flag rung takes.

**Tests.** smoke_ui `TAB1`–`TAB25`, four stub bindings — table-p_open, nil-p_open,
flag-blind (this install), and flag-blind-*and*-adopt-blind (the paranoid case, where even
the rebuild fails and the only honest move is the chat line). The stub models ImGui properly:
a bar is identified by the ID passed to BeginTabBar, an unseen ID resets the selection, a
flag lands at the NEXT layout, and a bar with nothing selected adopts index 0. Each rung was
verified to be load-bearing by disabling it and watching the right checks fail
(`TAB5/6/7/11/12` for the truthiness fix, `TAB15/16/17/20` for the rebuild). Suites
**5141 + 867**, both interpreters.

**Owed:** one click — open the Teleports menu on a CW character and click E-Box Restock from
another tab. Rung 3 is arithmetic on ImGui's own documented behaviour, but "a bar with nothing
selected adopts the first tab" is read from the API's behaviour, not from source we have on
disk (only `plugins\sdk\imgui.h`, the interface header, ships here). If it is wrong the
symptom is specific and loud: an empty tab body until you click a tab, plus the chat line.

### Postscript: where the api-2 train actually went (recorded 2026-07-30, at the promotion)

The promotion that carried this work — `1551faa` — found `main` sitting at `56221c1`, the
07-29 state. So the **Job helper module API v2 train (`f8df96b`, `2026.07.30a`) had never
reached main at all**: not by PR #150, not by the command block. The HANDOFF queue had been
emptied for it on the belief that one of the two routes would complete, and neither did, so
for a day the record said *promoted* while git said otherwise — the precise unanswerability
hard rule 14 exists to prevent, and the second time in three days it has bitten. The Module
API, `modcfg`, `combat`, the Panel kit, ADR 0031 and the percent fix all went to main **here**,
alongside the BST train and this session's work. PR #150 reads MERGED because its commits
reached `main` by the other route and GitHub closed it behind them.

**The rule that survives:** empty the queue *in the merge commit*, never in anticipation of one.

## Session "the Cloak that was worth two slots" (2026-07-31, `2026.07.31e`)

**The field report.** Henrik, building a set with MP and Refresh weighted: *"it doesn't take
into consideration that Royal Cloak / Vermillion cloak, that takes up more than one slot,
should count as removing the head slot if so. So when I built a set earlier where I
prioritized MP and refresh, it actually prefered royal cloak over dalmatica. Even though
dalmatica + bard head would give more refresh."*

**What was actually wrong.** Nothing was missing from the DATA and nothing was wrong in the
ENGINE. `catalog.lua` carries `RSlot = 16` on both Cloaks, `gearimport` stamps it into
`gear.lua`, `arbiter.reservedDrops` drops the reserved slot at equip time, and the Sets
builder even draws a red **RESERVED** box on the head tile with the reserver named in the
hover. Everything downstream of the decision knew. The **decision** did not:
`gearoptim.optimizePicks` — the joint, set-level pick both Auto-build and `/dl best` run
through — had no notion of reservation at all. It scored the Cloak in Body and a hat in
Head and added them together, so the Cloak was credited a slot it eats. Royal Cloak
(MP+20, Refresh+1) beat Dalmatica (Refresh+1) on the Body line, and the Refresh head rode
along on top of it *for free*. Dalmatica + hat never got compared against it, because the
comparison never existed.

**The shape of the fix.** `optimizePicks` takes an injected `opts.reserves(ref) -> mask`,
exactly like `opts.conflict` and `opts.effects` — no reservation lookup in the optimizer, no
second copy of the bit vocabulary (that stays `arbiter.RSLOT_ORDER`, required guarded; absent
module = a reservation-blind optimizer, its old behaviour byte for byte). Only labels the
solve is actually filling can be reserved: a Cloak costs nothing when Head is not in the
build-slot grid.

**Why a hill climb needed a second mechanism.** Placing a reserver is easy — `placeEv` evicts
the picks it eats, and the loss lands in `totalScore` — but the climb can never *leave* one.
The head slot is empty precisely BECAUSE the Cloak is worn, so swapping the Cloak out reads
as a pure loss and Dalmatica-plus-a-hat is never seen. That is the same trap the ADR 0011
set-seeded restarts exist for, one level up, and it gets the same answer: solve the whole
thing once per **reservation regime** (nothing reserving; everything on the table; each
`(label, mask)` regime alone when there is more than one) and keep the best total. The
no-reserver regime runs FIRST, so an exact tie fills the slot instead of eating it.

**Three consequences, all of them the same law arriving somewhere it hadn't.**
- **The dynamic ladder.** `levelLadder` learned `opts.emptyFrom`: the joint rule with nothing
  to hand over TO. Below the reserver's own level the slot is yours and the rungs stay; from
  it up every rung closes and *nothing* is appended. Emitted with explicit windows, never
  through `emitLadder`'s classic shortcut — a window-less chain's top rung is open-ended by
  definition, which is the one thing this ladder must not be.
- **Set totals.** `workingComposition` now drops what `arbiter.reservedDrops` will drop, so
  the numbers and the red box on the grid finally say the same thing. It also feeds
  `workingWeightedScore` — the objective Auto-build is judged against — so the panel's score
  and the optimizer's are one number again (design #6).
- **`/dl best`** prints the emptied slot with `-- taken by <piece>` instead of leaving a hole.

**Deliberately NOT changed.** `buildMaxStatSet` (`/dl best <stat>`) stays reservation-blind
for the same reason ADR 0011 left it set-blind: "the most Accuracy in this one slot" is a
per-slot question. And a slot **unchecked in the build-slot grid** is invisible to the solve,
so a preserved head row can still be eaten by a newly chosen Cloak — the red box says so, and
the alternative is the optimizer reaching into slots the mask told it not to touch.

**Tests.** run_tests `HR1`–`HR8` (the field case at 200 vs the blind 220, the reserver
winning on merit and naming itself, an unbuilt slot costing nothing, the tie rule, the
`Ammo`-sorts-before-`Range` direction through a boomerang, a 3-bit suit mask, and a gear-set
bonus that can never be completed THROUGH the slot its own piece reserves) and `LL8`–`LL10`
for `emptyFrom`. smoke_ui `S16q`–`S16u` drives the whole live chain — real catalog → real
`gearimport.rslotFor` → `rsv.maskOf` → `optimizePicks` — and pins blind-picks-the-Cloak
against wired-picks-Dalmatica side by side, so the wiring cannot rot into a no-op. Suites
**5343 + 913**.

**Owed:** one field round. Build the MP/Refresh set again and confirm Dalmatica + the head
now wins, and that a genuinely-better Cloak still shows an empty Head rather than a hat the
engine throws away.

## Session "the pair law moves to the Arbiter" (2026-08-01, engine v159, `2026.08.01d`)

**Theme:** a Range/Ammo flap Henrik hit on DRK72 Mindie -- *"it is trying to both equip
Arcane Arbalest in Range, and Cinderstone in Ammo back and forth, I thought we had that
rule set in place so higher level in non interoperable range <-> ammo combos would win.
In this case cinderstone"*.

**The Level rule was fine.** The diagnosis, from the live files before a line was changed:
ADR 0010's pair law ran on ONE RESOLVED TABLE while a dispatch's plan is MERGED ACROSS
TABLES. His DRK triggers fire two rules on one condition -- `{ status='Idle' } -> 'Idle'`
(Range ladder + `Ammo = Cinderstone`) and `{ status='Idle' } -> 'Weapons'` (Range ladder,
NO Ammo). `Idle` judged the pair correctly (Cinderstone Lv60 beats Arcane Arbalest Lv50 ->
Range dropped). `Weapons`, naming Range and no Ammo, asked the OTHER question --
`trinketWornDisplace` -- and wrote `Ammo='remove'` for a crossbow the same dispatch had
already decided not to equip. Merged last-writer-wins, the stick came off; next dispatch,
Ammo empty, nothing to displace, Idle's Cinderstone survived the merge and went back ON.
Off, on, off, on, one server round trip per second, forever.

**Method note worth keeping:** the whole thing was settled headlessly in minutes by
driving the REAL pure functions (`reserveFloor` / `reserveVerdict` / `trinketRangeDrop` /
`trinketWornDisplace`) with values read straight out of `Mindie_29909/gear.lua` and
`profiles/Default/{sets,triggers}/DRK.lua` -- artifacts first, then theory. The same script
re-run after the fix is the proof it settles on frame 1. Two hypotheses died on contact
with it: a `/dl fix` Pair backfill (his gear.lua carries `Pair` on only 8 of ~1400 records)
changes NOTHING here, and swapping the two trigger lines only masks it.

**Henrik's call:** *"Maybe it's better to move this rule into the arbiter, since it gets
the full picture from all the sets?"* Right, and for a reason no per-table patch reaches:
*"is a ranged piece coming in?"* is a question about the FINAL PLAN, and one table is not
the final plan.

**Landed:**
- **`arbiter.pairVerdict`** judges the MERGED FLOOR -- every matching set AND every built
  claim at its rank row -- ONCE per dispatch; `trinket-vs-ranged` stops deciding and starts
  applying. Free consequence: with the Ammo rule enabled it now arbitrates the BOLT that
  will actually be worn against the crossbow, not the Cinderstone the floor named under it.
- **It runs FIRST inside `reserveResolve`** (before availability, dominance, the fall) and
  DELETES the loser from the floor -- which makes ADR 0010's adjacency law literal and stops
  the two verdicts contradicting each other: a Lv75 crossbow WINS the Level contest while
  `reserveVerdict`'s tie-favours-the-reserver rule would suppress Range for a Lv60 stick,
  leaving the plan holding neither.
- **Suppressed, never ineligible.** An ineligible piece falls; the next crossbow down
  conflicts with the same stick, so a fall would walk the whole ladder and re-derive the
  flap (ADR 0027's asymmetry).
- **One implementation** -- `pairVerdict` shapes the floor into a plan and calls the two
  existing functions, which stay as the DIRECT-caller fallback exactly as `reservedDrops`
  does. `popt` omitted = byte-identical to before (test PV12).
- **Its own verdict in both renderers** (`/dl why <slot>`, Arbiter Monitor cell + hover),
  naming which of the three laws answered. Never folded into "reserved": a bolt and a bow
  are two ordinary pieces, and "RESERVED by" sends the reader hunting a piece that is not
  there.
- **Set totals count what will be WORN** (*"consider so that the total stats are reflected
  correctly"*). The Sets tab reads the same law through `dispatch.pairVerdict`; the old
  preview called `reservedDrops` alone, which drops Range whenever ANY stat stick sits in
  Ammo -- so a Lv75 crossbow beside a Lv60 Cinderstone read as "no weapon" in the numbers
  while the engine equipped the weapon. `gearimport.pairFor` is exported for it, the twin
  of `rslotFor` and for the same reason (a pre-v128 gear.lua carries no `Pair`, and reading
  the owned record would show a bolt and a bow as a fine couple).

Tests PV1-PV12. Suites **5439 + 925**.

**Then Henrik cut the migration question off at the root.** Asked what everyone ELSE does
about the missing `Pair` stamps -- run `/dl fix`? -- his answer was *"I feel like this
information should be documented in the catalog maybe? Instead of personal gear"* and *"It's
not like my personal Arcane arbalest can behave differently in this aspect as anyone
else's."*

Right, and it retires the migration entirely (engine v160, `2026.08.01e`). `RSlot`
(`item_equipment.rslot`) and `Pair` (`item_weapon` skill:subskill) are facts about the ITEM.
They lived in each player's gear.lua only because the equip-time engine ran in LAC's OWN Lua
state and could not reach a 5MB table -- **the purge ended that**: one state, and dlac.lua
preloads gearimport + gearui at addon load, so the catalog is already resident in the state
dispatch runs in. (catalogindex's "the equip-time engine never loads the catalog" header was
a two-state-era artifact; corrected in place. Worth remembering as a class: a design
boundary can outlive the constraint that created it, and the comment defending it is the
last thing to notice.)

- **`dispatch.recordRSlot(rec, cat)` / `recordPair(rec, cat)`** read the stamp as a CACHE and
  fall back to the catalog by id, through `gearimport.rslotFor` / `pairFor` -- readers that
  already existed, already lazy, already cached, already applying `effectiveRSlot`.
- The stamp still WINS when present (a hand edit is honoured); `ANIMATOR_FED` sits ABOVE the
  fallback because it is a statement about the item and must veto BOTH sources; unknown
  never constrains, on any of the five ways a lookup can come back empty.
- **What it fixes for everyone, on the addon update alone, no file rewritten and no command
  run:** a gear.lua older than `Pair` (v128) was running the pair law on the RSlot bit alone
  -- a gun and a crossbow both just "Marksmanship" -- and one older than `RSlot` (v43) had
  ADR 0010 FULLY BLIND: no bit, no pair key, so a stat stick and a ranged weapon were never
  in conflict at all and flapped exactly as they did on 2026-07-19. A catalog correction now
  reaches every player with the next update.

Verified against the shipped catalog (14,705 items indexed) with an ENTIRELY unstamped
manifest: Cinderstone -> effectiveRSlot 4 + Pair 0:0, Arcane Arbalest -> Pair 26:0, and all
four pair cases (Level contest both directions, bolt-vs-bow mismatch, worn displace) resolve
correctly. Tests CF1-CF6. Suites **5455 + 925**.

**FIELD-CONFIRMED** the same day, on the reported case exactly -- Henrik, on Mindie DRK72:
*"it is not flapping between arcane arbalest and cinderstone now, so seems to work!"* The
whole train (v159's merged-floor verdict + v160's catalog-sourced item facts) went in
untested-in-game and landed first time; the headless repro built from his live files before
any code changed is what made that safe, and re-running it after the fix is what predicted
it. Two secondary surfaces are still unobserved and are render-only paths over the same
record: the `/dl why ammo` / `/dl why range` verdict lines, and the Sets tab showing the
Range tile with the PAIR sentence rather than the reservation one.

**Then the screenshot caught the blemish** (engine v161, `2026.08.01f`). `/dl why range`
printed BOTH `nobody claimed it (kept as worn).` AND `held EMPTY: Arcane Arbalest and
Cinderstone cannot coexist -- kept Cinderstone, the higher Level.` -- two sentences
disagreeing about one slot, and "kept as worn" is the weaker truth besides: when a stat
stick holds Range the SERVER empties it, so the slot is not merely unwritten.

The no-contest line is NOT a verdict -- it is what a renderer says when the contest was
EMPTY -- and a slot the arbitration REFUSED has an empty contest BY CONSTRUCTION, because
the refused piece never reaches `floorTbl`/`arbExplain` and `ops` comes back nil. The first
four verdict channels (`rep` / `fall.dead` / `inel` / `sup`) never exposed this because each
only ever fires on a slot that HAD a contest. The pair verdict is the first that can fire on
a slot NOTHING CLAIMED -- which is how a five-week-old invariant broke the week a fifth
channel arrived.

`arbiter.slotVerdict` is now the ONE walk (`fell -> dead -> ineligible -> reserved ->
pair`, most specific refusal first) that all three renderers ask before falling back to the
no-contest line. Henrik: *"document this properly since we'll probably be touching it
again"* -- so **docs/design/two-way-arbiter.md gains §11, THE RENDERING CONTRACT**: the
three renderers and what each shows, the channel table with the sentence each earns, the
ONE-ANSWER-PER-SLOT invariant with the screenshot that proved it needed stating, five rules
for the sixth channel, and a where-the-pieces-live table. Tests RV1-RV9. Suites **5472 +
925**.

The generalizable bit, and the reason it is written down rather than fixed quietly: **an
invariant that three renderers keep by coincidence is not an invariant.** Four channels had
held it for five weeks without anyone stating it, because all four happened to fire only on
slots that had a contest. The fifth did not, and nothing in the code said what the rule was.

**Field-confirmed the same evening** -- Henrik, after a Reload LAC: *"when issuing /dl why on
range, it does no longer in fact, say 'nobody claimed it (kept as worn)'"*. Both chat
surfaces of the pair verdict are now confirmed on the character rather than only headlessly;
the Sets tab's red Range tile is the one surface still unseen.

**And a standing rule was set in the same breath:** *"When I say merge, treat it as an
accept. But you are right not to assume otherwise since I haven't told you."* An instruction
to merge CARRIES the acceptance of everything riding that promotion -- `dev` promotes
whole-or-not, so there is nothing left to ask about -- and asking a second time is the
mistake. The other half of the rule is unchanged and is why the exchange happened at all:
only Henrik grants acceptance, so it is never inferred from a field confirmation, from
"works", or from a session's own read that something looks ready. Recorded in hard rule 14
and in the "Ready to merge" preamble, both of which a future session reads before promoting.
This also closes the 2026-07-30 note that the permission classifier refused Claude the main
merge AND the push: the gate opened 2026-08-01 (*"I should've added the rights to let you
push now"*), `ff92f4e` was the first promotion Claude ran end to end, and the old one-command
handover block is now the fallback for a refusal rather than the standing procedure. The
`git checkout dev` at the end of it stays load-bearing either way -- the game plays this
checkout's working tree.

## Auto-build stays in the field on request; Auto-Build All asks first (2026-08-01)

Two Sets-tab requests from Henrik in one breath, both about leeway rather than mechanics
(`2026.08.01h`). No engine change: this is entirely GUI + one Setting.

**"Only use available gear out in the field, or all containers."** Auto-build's candidate
pools come from `candidatesForSlot`, which filters `buildOwned()` by slot, job/level
usability and `owned.haveInBags` -- *owned anywhere*, which is right for a curated gear
library and right for a set you mean to wear later. It is wrong for the player standing in
a zone who wants the answer to be wearable now: ADR 0005's split means a Mog Safe piece is
Owned and not Available, the panel paints it red, and the engine falls past it at equip
time (the `2026.08.01b` arbiter refusal). So the pool is now a Setting.

**"Auto-build with gear in storage"** (Menu > Settings) / `/dl buildstored [on|off]`,
`sf.flags.buildstored`, persisted in `uiflags.lua`, **default on** -- absent key reads as
on, the fourth time that rule has earned its keep (`UIF21a3`). Off narrows every pool
`autoBuild` builds to pieces `ownedcache.isStored` says are not parked: Inventory + the 8
Mog Wardrobes.

Three placement decisions are the whole content of the change:

- **The filter sits in `autoBuild`, not in `candidatesForSlot`.** That function is shared
  with the `+ Add` picker, which must keep offering everything you own (ADR 0026, and the
  Sub HARD RULE that has been reverted three times). Narrowing there would have narrowed
  the picker too, silently. `UIF22b` pins that `candidatesForSlot` never learns the flag.
- **It reads `ownedcache.isStored`** -- the same fact that paints those rows red and the
  same one the arbiter's availability refusal rides -- so the colour, the pool and the
  engine's fall can never disagree about what "in storage" means. It fails to *nothing
  stored* on an empty scan, so char select and headless are a no-op rather than a set that
  suddenly builds empty.
- **It narrows the POOL and nothing else.** No set is rewritten, slots outside the build
  mask keep exactly what they have, and a slot whose whole pool went to storage is simply
  left unfilled -- which is the honest answer to "build me something I can wear".

Worth stating because a future session will read hard rule 6 and reach for the revert:
this IS set building consulting a live bag fact, deliberately, at the player's request,
opt-in, and default-off. The rule ("sets are plans; the engine decides at equip time")
still describes the default behavior exactly. Both the code comment and the Setting's
hover say so.

**Auto-Build All takes two clicks now.** *"It can be highly impacting accidentally
pressing it, so let's give some leeway just in case."* -- and he is right: the button
re-solves AND commits every weighted set of the current job, backing each one up, in one
gesture, sitting one row below Commit. The first click arms it (red, label flips to
**"Sure?"**, status line says what it will do); the second builds; the arm expires after
~5 seconds so a stray click never leaves a live trigger under the cursor. Deliberately not
the copy-confirm POPUP pattern: a whole-job action has nothing to name in a dialog, and
click-twice keeps the deliberate path one gesture longer instead of two windows deep. The
button width is fixed at 150 because the two labels differ in length and an auto-width
button would shuffle the controls row as it flipped.

Both live inside imgui-only draw paths the suites cannot enter, so both are pinned at the
source in the UIF section (`UIF22`-`UIF23a`), the technique the `autobuildimport` gate
established. One CRLF lesson came with it: a source pin ending in `.-\nend\n` passes under
Windows Lua (which strips the `\r` on a text-mode read) and fails under WSL's (which does
not) -- pin to the first column-0 `end` and take no trailing newline. Suites **5480 +
925**, both interpreters.

**Field-confirmed the same day**, both halves in one look -- Henrik: *"Works in field,
thank you, both settings and the auto build."* Promoted to main in the same message
(`36da078`), the "merge IS an accept" rule from earlier the same day doing what it was
written for: the field confirmation and the instruction arrived together, so there was
nothing left to ask. The Setting's own hover and the "Sure?" flip are the two surfaces that
had never been seen outside a source pin, and both read right in game.

## Session "does it send constant packets?" (2026-08-02, `2026.08.02` + `2026.08.02a`)

**Theme:** a field question that had a code answer, turned into a readout — and then the
readout turned out to be billing dlac for the player's own traffic.

Henrik asked from inside an Incursion, level-synced, using only sets: *"Does this addon
send or receive many packets to and from the server? ... does it send constant packets to
have things equipped or only once?"*

**The answer, traced rather than recalled.** Only on a real difference. `bufferFlush` bails
at `plan.satisfied` (`feature/equipengine.lua`), so the 0.4 s Default tick resolves a plan
~2.5×/s and sends **nothing** while what you want is what you wear. Equips are edge-driven,
not a heartbeat. Two things fell out of the same trace and are recorded so they are not
re-derived:

- **Level sync cannot produce a strip/re-equip loop**, because both sides use the *real*
  job level. `AllowSyncEquip = true` reads `GetJobLevel(mainJob)`; the server's check is
  `getReqLvl() > (DISABLE_GEAR_SCALING ? GetMLevel() : jobs.job[MJob])` with
  `DISABLE_GEAR_SCALING = false` on CatsEyeXI (`charutils.cpp:2306`,
  `settings/default/map.lua:100`). Client and server agree, so no equip is refused and
  nothing retries. The sync landing itself arms the 1 s settle hold, then one re-dress.
- **The `share/mob-stats/accwatch.lua` `/check` spammer (0x0DD) is reference-only** and
  never loaded — worth knowing before someone greps for send sites and panics.

**But a code answer is a claim.** So `/dl sends` (`feature/sendlog.lua`): total, per packet
id, per **cause**, plus a ring of recent sends with ages; chat shows the last 8, the file
(`debug\dlac-sends-<Char>.txt`) all 24. Zero sends prints as `NOTHING sent` *and says why
that is expected* — absence-is-the-diagnosis, the property every debug artifact here
carries.

**Why it lives in dlac and not dlacprobe**, which was the one call worth making
deliberately (the standing rule sends probes to dlacprobe): a dlacprobe `packet_out`
observer sees anonymous injected bytes and cannot tell ours from another addon's, let alone
name the dispatch point behind them. **Only the send site knows why it sent, and the why is
the entire diagnostic value.** That is the sentence to reuse the next time a diagnostic sits
on the boundary. `fireEvent` now stashes the dispatch point so `bufferFlush` can stamp it —
which is what makes a flap legible: one burst named `Default` is a re-dress, `Default`
repeating at 0.4 s is a fight.

**The invariant, pinned as source (SND12):** every `AddOutgoingPacket` in the shipped tree
sits beside a `sendlog.note()`. Five chokepoints carry all of them. A new send site without
a note fails the suite, because an uncounted send is the only way this readout could lie —
and it would lie in the direction that matters ("dlac sent nothing" when it did).

**A single-state report wore a false accusation.** `debug.lua`'s `_mergeSections` read a nil
engine half as `ENGINE HALF MISSING -- LuaAshitacast is not running the dlac engine. That IS
the diagnosis.` True when a half was expected; a libel when there was never one to expect.
`NO_ENGINE_HALF` now separates "never expected" from "expected and absent", nil keeping its
old meaning (DBF9). The purge left one state, so more reports will want this.

**Then the follow-up that mattered more than the feature.** Henrik: *"What does 'reinject
(your own action, passed through)' mean?"* — and explaining it exposed the readout billing
him wrong. A re-injected `0x01A`/`0x037` is **his** packet: the engine blocks it so gear can
land ahead of it, then returns it byte-identical. One in, one out. It is dlac's
`AddOutgoingPacket` call, so the invariant counts it — but it is not traffic dlac *added*,
and one lumped total made a busy caster read as a chatty addon. The counter now splits own
from passed-through, **quotes the rate on dlac's own count only**, marks the affected ids
(wholly or partially), and prints the same "dlac itself sent NOTHING" verdict whenever
`own == 0` — which is the shape a real casting session actually takes, and the honest answer
to the question that started all this. The flag rides in the **data** (`note(id, why,
pass)`), not in the wording of the cause: identity in the data, label at the render seam,
the same shape the GM-naming fix established.

**The lesson with the longest legs is about the guard, not the feature.** SND12 failed on
its own documentation — a plain `AddOutgoingPacket` substring matched the comment explaining
the send sites. It matches an *invocation* now (`AddOutgoingPacket%s*%(`), and the test says
why in its own comment. A pin that trips on the prose describing it teaches the next person
to weaken it, and a weakened pin is worse than none: it still reads like a guarantee.

Suites **5652** then **5662**, both interpreters. Promoted the same session (`5cf4455`),
**never field-confirmed** — the round it owes is one glance, `/dl sends` after an Incursion
stretch, and because it is a readout a wrong answer costs a re-read rather than gear.



## Session "I meant the job" (2026-08-02, `2026.08.02c` + `2026.08.02d`)

**Theme:** the ask named the wrong axis, and building it is what revealed which one he meant.

*"Can you make a copy to... button by all the trigger rules? I know we have blue prints, but
would be nice if that would open up a window where you can mark all or any of the dlac
profiles you want to copy that trigger rule to."* Built exactly that. Then: *"All right, I am
in the wrong here. What did we call the job profiles again? I don't mean the actual character
profiles, I meant the job. I want to be able to copy the rule between the jobs."*

The word he was reaching for is **Job entry** — one job's slice inside a Profile, the term
CONTEXT.md coined precisely because "job profile" collides with both Profile and
LuaAshitacast's own "profile". The vocabulary earned its keep here: with the term named, the
misunderstanding closed in one sentence.

**The correction cost one round, and the reason is worth keeping.** A trigger file is
addressed by TWO coordinates -- `profiles\<Prof>\triggers\<JOB>.lua` -- and a copy varies one
of them. The classifier ("what would landing this rule THERE do?"), the writer, the backup
ladder and the receipt never cared WHICH: they take a (profile, job) pair. So the job axis was
a second call site and an `order` argument, not a rewrite. **When a feature's core is written
against the coordinate rather than against the surface, a wrong-axis ask is cheap to correct.**
The window now carries both lists -- Jobs first (the ask), profiles below -- each with its own
All, None and Copy, deliberately never sharing a button: one "copy everything ticked" control
across two axes is a crossed-receipt bug waiting to be written.

**Why this is not a Blueprint, stated properly this time.** A Blueprint stamps onto the ONE
job you are standing in. Putting a rule on five jobs means five job changes. That is the gap,
and it is structural rather than cosmetic -- which is also why the copy still travels AS a
Blueprint entry internally (capture, detach, identical-rule, stamp, all pinned by TGB\*): the
shared road is what guarantees a copied rule is byte-identical to a stamped one.

**The one design ruling of the round is about the All button.** He asked for "one button to
select all jobs" AND for "where it also checks if it has a similar rule already" -- and those
two pull against each other, because All across 21 jobs is exactly where a silent duplicate
would go unnoticed. So **All ticks only what does not already hold the rule**; a duplicate row
stays tickable by hand, in gold, saying it adds a second. Warn-but-allow (the Blueprint
double-stamp law) survives; warn-but-do-it-for-you does not.

**Two guards on the destructive half**, both loud: a target whose trigger file does not parse
is refused rather than serialized over, and a target whose timestamped safety backup cannot be
written is refused too -- the profiles-deleter house rule, applied where it was newly earned.
The receipt leads with the coordinate it varied, which a first draft got wrong: it hung the
"(WHM Midcast)" tail off the *Copied to* clause, so a copy where EVERY destination failed
named no axis at all -- exactly the moment "which list did I just fire?" matters (RC34b).

Suites **5707** and **977**, both interpreters, plus a scratch end-to-end against real files
on the job axis: a job entry with existing rules kept them (and its Modes and Groups) and
gained the copy, an empty job got a file, the job being played was never written, and a second
pass ticked only the two jobs that did not already have it.

**Same session, two more passes.** He asked for a *setting* called "Include set if not
present", then immediately narrowed it: *"This should be a mark in the actual copy window, not
a setting under the settings menu."* That is the right line and worth having in writing --
dlac's **Setting** is a preference about the CHARACTER (uiflags.lua, remembered, listed in
Menu > Settings). This one is a property of the copy you are making right now, so it is a tick
in the window and nothing is remembered. The distinction is not pedantry: a remembered switch
would silently apply to a copy made a week later.

It brings the rule's SET along when the destination job lacks it, through a new
`setmanager.copySetText` -- a **verbatim block move**, which is the one design decision in it.
Re-rendering the set through `renderSetLines` would round-trip every entry through the WRITER's
vocabulary, so an entry shape it does not know (or a comment the player wrote inside the block)
would be quietly rewritten on the way. A copy must move what is actually there. It refuses a
name the destination already holds -- "if not present" is the whole contract -- and sets follow
only a rule that actually LANDED, because bringing gear to a job whose trigger file we just
refused to touch would leave a set for a rule that is not there. A set that could not follow is
named in the receipt: a rule reported as copied while the set it points at stayed behind is the
exact dud the tick exists to prevent.

And: *"Please remove all the text above the job list, it's bloating."* Gone -- title, subtitle,
the rule's canonical text, the uncommitted-edits banner. The window now opens straight onto the
job ticks. He clicked a button on a specific rule; he knows which rule it is and what a job
list is for. What survives above the list is the error line, which only exists when something
is actually wrong. This is the **panel-text standard** applied late rather than early: label
the control, explain on hover, never paragraph at the player -- and the honest lesson is that
the paragraphs went in because writing them felt like being thorough.

Suites **5723** and **981**, both interpreters, and the scratch end-to-end re-run with sets: a
destination job that had its own sets file gained the set beside its existing ones (comment and
`{ gear = ..., minLevel = 30 }` shape intact, backup taken), a job with no sets file at all got
one, and the source job was never touched.

**Field round, same session.** *"Tested it out, document, commit, merge, push to origin main"*
-- so the whole train (`2026.08.02b`–`d`) went to main **field-confirmed**, which the two 08-02
promotions before it were not. Two things stay honestly uncovered by that pass and are recorded
rather than quietly folded in: the refusal paths (a destination trigger file that will not
parse; a safety backup that cannot be written) cannot be produced in a normal session, so they
remain suite-only -- and they are precisely what makes the destructive half safe; and the
PROFILE axis, which he never asked for and which survives only because it was already built and
costs one separated list. If it is still unused a week from now, delete it: an axis nobody uses
is a second thing to keep correct.

## Session "the banner that ran off the edge" (2026-08-02, `2026.08.02e`)

**Theme:** *"On my Mindie DRG, I have two sets missing. Resting and Movement. The message is
way too long and isn't word wrapped... So I was thinking, maybe shorten it up."* Then his own
mock: `[!] 2 trigger target set(s) missing from this profile: Movement, Resting -- [Create?]`
*"and it will create two empty profiles with those sets and commit. Easily guide the player to
do the right thing."*

**The message got short and gained a button.** It used to say the count, the names, the
consequence, the marker AND the cure -- unwrapped, off the panel edge. Now it is
`[!] 2 set(s) missing: Movement, Resting` with a **Create** beside it, and the consequence
lives in the hover. Long lists name six and count the rest; Create still takes all of them,
because it operates on the list, not the label. This is the **panel-text standard** applied at
the moment it is cheapest to obey -- when the paragraph can be replaced by the action it was
describing. The honest reading of the old line is that it explained the fix at length instead
of offering it.

Create writes each name as an **empty set** through the ordinary `setmanager.commitSet` rails
(parse-check, one backup per set) and then one `/dl sets reload` for the batch, as
`deps.createEmptySets` on the table gearui already hands triggersui. An empty set is a
legitimate set here and always has been -- the Sets tab commits one on purpose -- so the rule
stops being a dead end today and the gear can arrive later.

**The design ruling is his second message**, and it is the part worth keeping: *"if we have
trigger rules that match the base rules but point to other sets, don't tell them to create
them, since there are obviously sets with other names doing the base thing we're after."* So
the banner now hides a missing name whose **conditions are already covered** -- another rule,
same handler, same condition signature, landing on a set that exists (or on a direct `equip`).
Keep `moving = true -> Speed` and nothing nags about `Movement` any more. The signature is
condition IDENTITY, not resemblance: `when` + the `whenAny` legs + the `cases` legs, each
sorted so authoring order and `pairs()` cannot decide it, raw keys so a PRETTY_KEY label
cannot either. A rule with an extra condition is a different rule and still reports.

Two things it deliberately does NOT do. The per-row `[missing]` marker is **not** suppressed --
that is a fact about one rule and stays true; the banner is the "you must act" signal, and a
covered condition has nothing to act on. And a multi-set rule's own absent member (`-> Tp_Default
+ Haste`, no Haste) still reports: the rule is not covering itself, and the overlay it asked
for cannot happen.

Suites **5735** and **989**, both interpreters. `_missingSetNames` is a pure exported seam
(TGM0-11: the starter four, coverage, per-handler scoping, an `equip` anchor, the
narrower-rule case, order-independence, the multi-set member). The smoke half pins the seam
BETWEEN the files -- `deps.createEmptySets` named on both ends, plus the button id and the
absence of the old paragraph -- because a renamed deps key is not an error in Lua, it is a
button that does nothing, silently.

**Field round, same session.** *"Field tested, works perfect, merge, push to origin main"* --
so it went to main **field-confirmed**, built and promoted inside one session. His pass covered
the banner, the Create click and the created sets on the DRG that started it. The one thing it
could not cover is the commit-failure path (`N FAILED`): `setmanager.commitSet` refuses only on
a torn or unwritable sets file, which cannot be produced in a normal session -- suite and source
only, and recorded rather than quietly counted as confirmed.

The lesson to carry, since the ask was phrased as a text problem: what actually shortened the
message was **giving the player the fix instead of describing it**. Every clause that came out
of the line was explaining a repair the button now performs. When a warning is long, the first
question is whether it is long because it is doing the user's work in prose.

## Session "one file to send" (2026-08-02, `2026.08.03a` — `/dl report`, the support recorder)

**The ask, looking forward rather than at a bug:** *"We have the Arbiter Monitor now, I also
believe this addon will be approved. So was thinking, what if we add a debug tool in the
arbiter monitor? Once the user base grows, I want people to enable the debug, where we get as
much information as possible that is generated into a log file... their whole dlac profile that
is active + gear, sets, triggers, everything. Then generate a debug log for as long as it is
active (max 5 minutes). Then he should be able to send those files to me so I can feed you the
data so you can help troubleshoot."*

So the consumer of this artifact is **known and unusual**: Henrik reads it, then feeds it to a
model. That single fact decided most of the design, and it is the part worth keeping.

**Five calls, each with a field reason.**

1. **Pre-roll.** Nobody starts recording before the bug; they start after they saw it. dispatch
   already holds 50 decisions and 32 actions, sendlog 24 sends, always. So a capture's first act
   is to dump those rings as `PRE-ROLL`. Free — no new standing cost — and it is the single
   thing that makes the tool work the way players actually behave.
2. **Stream, don't buffer.** `feature/debug.lua`'s own header records the failure mode: `/dl
   debug ebox` threw and Ashita unloaded dlac mid-session. If the thing being chased is a crash,
   a write-at-the-end design loses exactly the run that mattered. Batches append to
   `dlac-capture-<Char>.log` as they happen; a dead client still leaves the log.
3. **Scoped for the reader.** The budget is CONTEXT, not disk. Mindie's real `gear.lua` is
   **264 KB** (~70k tokens) of bag index, and almost none of it bears on any given bug — so gear
   ships as a **digest** of the items the window actually named, each with live "is it in an
   equippable bag" beside it, which is precisely the fact an `unavail` fall turns on. The active
   job's sets + triggers ride verbatim (~44 KB). Everything else is in a **manifest** with its
   size, so a wrongly-scoped digest costs one follow-up instead of a lost session. `/dl report
   full` widens to the whole tree.
4. **The mark.** In a five-minute log the expensive step is finding the moment. `/dl mark <note>`
   goes on a macro palette and works mid-fight; the Monitor's `[Mark]` button is the alt-tab
   version. Marks land in the timeline *and* in a list above the log.
5. **Overwrite**, per the 07-23 file rule: support wants THE latest, and a player who ran it
   twice meant the second one.

**Where it lives.** `feature/report.lua` owns the recorder; the Arbiter Monitor holds *a* button.
The capture spans far more than the arbiter (sends, health, config, chat), and a second
implementation living inside a renderer is how two surfaces drift apart. Same shape as the
integration-surface ruling: one record, several renderers — this is the fourth renderer of the
decision ring, beside `/dl why`, the Monitor hover and the stream, and it says the same
sentences on purpose (`fell:`, `it reserves X -- owned above`, `not in a bag you can equip
from`). RPT6c pins that wording as a test, because a player quoting one channel and support
reading another must be looking at the same words.

**Privacy is stated, not enforced** (the no-gating rule). The only chat captured is dlac's own
`[dlac] ` output, filtered at the `text_in` seam — no tells, no party chat — and the header
paragraph says what the file holds and that nothing leaves the machine on its own.

**Two small seams grew elsewhere.** `sendlog.observer` (one line, pcall'd — an observer must not
break the thing it observes) so the log carries every send *with the cause the send site knew*;
and `check.gather()` split out of `check.report()` so the report can put the same health readout
at the top without capturing `print`.

**Three bugs the build found, all in what the file SAYS rather than what it does.** The summary
counted 0 decisions over a log visibly containing one (pre-roll was uncounted — a reader who
catches that stops trusting every other number, correctly). It said "1 decisions" and "1 chat
lines look". And text-mode append against a binary read left **17 stray CRs** in a file whose
whole job is to be read by someone else's tools.

Suites **5836** and **999**, both interpreters. The pure seams carry the clamp, the parse pair,
the decision renderer's vocabulary, the digest scope and the budget walk; RPT20-25 drive the
**whole assembly** against an in-memory tree through the new `M._fs` seam, because the
interesting failures here are about which files were chosen and what the report says about the
ones it left out — not about `io.open`. The no-silent-caps law is four of those checks: every
exclusion is a named line with a reason, since a truncated bundle that reads as complete is the
one failure mode that costs an entire support round.

Format pinned in `docs/reference/report-format.md` — written for whoever reads a report next,
model or human, so nobody re-derives the layout from the bytes.

### Field round 1, same day — "I can mark the same event several times" (`2026.08.03b`)

Henrik ran a report and came back with the one thing a build session cannot see: *"what I can
see is that I can mark the same event several times. So if I have marked an event, the button
should change to de-mark and remove it."*

He is right, and the cost is precisely aimed: the mark list is the **reader's index** into a
five-minute log, so a doubled entry spends the one thing marks exist to buy. Two clicks — or one
macro pressed twice, which is the ordinary case — produced two rows pointing at the same instant.

**The fix needed a definition of "event", and the addon already had one:** the decision the ring
is newest on. One record per dispatch whose outcome moved — that IS a moment. So a mark now
binds to `st.lastSeq`. Mark again before a new decision lands and it REPLACES (latest words
win); mark after one and it is a new moment, so it appends. The Monitor's control follows: the
note field becomes the mark's text and the button becomes **[Un-mark]**. A report with no
decisions at all is one long moment, which is correct — the gear never moved, and that is the
thing being reported.

Two rulings inside the small change:

- **The log is append-only and is never rewritten.** A replace appends `MARK REPLACED … (was: …)`
  and a removal appends `MARK REMOVED (was …)`. The player changing their mind is itself part of
  the timeline; only the summary INDEX is deduplicated. Nothing the player typed is ever lost,
  including the note a replace superseded.
- **Un-mark refuses once the moment has moved on** (RPT30). It may only take back the current
  moment's mark — reaching backwards would let one button delete evidence the player set against
  a different event, which is the only way this control could destroy something.

Free ride, and the reason the seq was worth storing: every summary row now reads `at decision
#N`, which turns a mark into a **jump** to the log block headed `#N` — the decision the player
was looking at when they said those words.

Suites **5858** and **1003**. The mark semantics are driven against a stubbed ring (RPT26-32:
add, replace, un-mark, the new-moment append, the evidence rule, the append-only timeline, and
the summary link), and the smoke half renders BOTH button states, checking that a marked moment
offers `Un-mark` and does not also offer a second `Mark`. `flush` moved onto the `M._fs` seam so
the timeline is assertable at all — the first attempt tested `st.q`, which `pump()` drains.

### Field round 2 — reading the first real report back (`2026.08.03c`)

*"Check the report."* He sent the actual artifact from his DRG session. It worked — 46 KB,
every section intact, and the **pre-roll caught decision `#1` twenty-six seconds before he
pressed record**, which was the design's central bet paying off on the first real run. Reading
it back found four things, and the two that matter were not cosmetic.

**1. `(kept)` was telling a lie that only shows up in this renderer.** Each weaponskill block
read `(7 slots changed)` over seven rows saying `(kept)` — two statements that cannot both be
true. The ring counts a slot as changed when it *left* the plan, and the renderer, finding no
item and no winner, fell through to the Monitor's word for "nobody claimed it". In the Monitor's
4x4 grid, where all sixteen slots are drawn, `(kept)` reads fine; here, where only changed slots
print, it was actively misleading. Now `(left as worn)`, with the header carrying `0 placed, 7
left as worn` — and the breakdown appears only when the two numbers differ, so ordinary blocks
stay one line. The first cut of the fix repeated three lines of prose per dropped slot and spent
**21 lines** on one weaponskill; it says it once per block now. Counted through the same
`_isDropped` the rows use, so header and rows cannot disagree.

**2. The digest's scope had a blind spot, and it hid the actual answer.** He was **DRG26** under
level sync, and every piece in his `Ws_Default` is level 33-75 (Peacock Charm 33, Virtuoso Belt
54, Jaridah Khud 55, Fotia Gorget 72, Brutal Earring 75). So every weaponskill silently wore TP
gear — correct engine behaviour, and *exactly* the thing a player files as "my WS set doesn't
work". The report could not say it: the level filter runs at **flatten time**, before any ladder
exists, so there is no refusal to record and no rung to strike through, and a digest scoped to
"what the window named" cannot see gear that never got that far.

Fixed by scoping a SECOND list off the bundled sets file — which is in the report anyway — and
flagging anything above the level dlac was *deciding under* (read off the records, so a lapsed
sync cannot rewrite the answer). Set files reference gear as Lua paths, and the identifier is
not the name (`gear.Head.Faceguard_1` is "Faceguard +1"), so each path is walked against the
real gear table, exactly as the file itself does at load — depth-agnostic, so Main/Range's extra
weapon-category level needs no special case. Re-run against his real 777-entry `gear.lua`, the
report now names all **38** pieces his DRG sets ask for that DRG26 cannot wear.

**3. The health section accused a healthy engine.** `check._lines` line 5 tells the reader a
`[dlac] check (engine): alive` line must accompany the readout and that its absence IS the
diagnosis. True in chat, where dispatch prints it from its own branch — and impossible in the
file, which carries the addon half only. Every report ever written would have failed that test.
The file now states its own equivalent from the engine file version and the modestate stamp,
which is a stronger check than a printed line: agreement proves an armed engine of the right
version, disagreement names which side is behind.

**4.** `SEND 0x01A  passed through (your own action)  (your own packet, passed through)` — the
same fact twice, which makes a reader look for the difference between them.

Suites **5886** and **1003**. The lesson worth keeping is about #2: the artifact was scoped to
*what happened*, and the answer lived in *what was asked for and never happened*. A digest built
from observed events cannot explain an absence of events — and an absence of events is what a
support report is usually about.

### Field round 3 — the full report, and the block that said nothing (`2026.08.03d`)

He ran `/dl report full` on a fresh DRG2. First finding was about the *build*, not the code: the
header read `dlac 2026.08.03a`, so the addon state in game was the one loaded before the fixes —
`/addon reload dlac` is now part of asking for a report, because a player testing the old build
looks exactly like a fix that did not work.

**`full` itself is confirmed:** 93 files, **zero dropped**, raw `gear.lua` (264,111 bytes) whole,
736 KB / 22k lines. The per-file cap lifts as designed.

**Six of 37 decision blocks were EMPTY** — a header, a `under:` line, nothing else. The ring
appends only when the fingerprint moves, and the fingerprint is *items plus winners*, so a
zero-change record is one where a slot changed **hands**. The renderer had no notion of that and
printed the bare header, which teaches a reader to skim past records that by definition are
saying something happened. You could see the symptom in the same log: `Main Harpoon` appeared
four times with `<- Triggers (rank 13)` and three times completely bare, seconds apart.

Blocks now carry `claim moved: Triggers -> (nobody)`, derived by comparing consecutive records
(the ring does not store it, and consecutive is the only comparison that means anything — the
ring appends on change, so record N-1 IS the state N moved away from). **A decision block can no
longer be empty**: failing both tests prints "this should not be possible", which is a finding
rather than a shrug.

Two things the build got wrong on the way, both caught by replaying his actual records:

- **No predecessor is not "everything changed hands."** The first cut treated every winner in
  the first record as a fresh shift and printed sixteen redundant lines over rows that already
  said the same thing. The first block of a capture has nothing to compare against, so it shows
  no shifts.
- **`(the item did not change)` was ASSERTED, not checked** — and printed over a slot that had
  gone from nothing to Emperor Hairpin, because it trusted the record's `changed` map to be
  complete. Verified now; when the item moved too, the block shows the transition and adds
  `NOTE: the record did not list this slot as changed`. That note should never fire in the
  field, which makes it a tripwire on the ring.

**Also fixed.** `contest.src` is on every record and the report was throwing it away — it only
ever surfaced inside a `ladder (Name):` line, so a decision that resolved no ladder never named
the set it came from, which is exactly the decision you want the set for. Blocks carry `sets:`
now. And the summary's `0 actions` read as "you did nothing" over a log plainly containing a
weaponskill: the counter only ever tallied the ANCHORS (actions that moved no gear, because one
that moved gear is already a decision block), so the label says which.

**One latent bug, found while checking the mechanism rather than by symptom.**
`dispatch.decisionFp` lowercases every slot key; the `changed` computation twelve lines below
compared **raw** keys — two computations of "did this move?" disagreeing about what a slot IS,
the exact class `findCI` exists to prevent. It is not what caused the empty blocks. But on the
day one producer emits `Main` where the last pass emitted `main`, the fingerprint would
correctly say nothing moved while `changed` counted TWO phantom changes, and every renderer of
that record would have shown both. Both sides are case-insensitive now.

Suites **5911** and **1003**. The habit worth keeping from this round: *replay the real records
through the new code*. Both build mistakes above were invisible to the unit tests, which used
fixtures shaped the way I expected records to look; his actual sequence had a slot with no
predecessor and a `changed` map that did not cover a moving slot, and both fell out immediately.

### Field round 4 — the report is good, and it found two engine oddities (`2026.08.03e`)

First normal report off the current build (`2026.08.03d`), 47.7 KB. Everything built over the
last three rounds is confirmed working in the field: `sets:` on every block, the engine-version
note in health, the relabelled action counter, the digest's two lists with `ABOVE YOUR LEVEL
(10)` against a DRG that levelled 9 → 10 mid-window, and — the one that mattered — the
zero-change block, which now reads:

```
[17:53:58] #4 Default -- status=Idle moving=true   (0 slots changed)
    Ear1    Optical Earring    claim moved: (nobody) -> Triggers   (the item did not change)
```

So the tool stopped being the thing under investigation. **What it then surfaced is about the
engine, and neither could be diagnosed from the artifact, so this round is two more renderer
fixes aimed squarely at them.**

**(i) An item with no owner.** `Ear1` carried Optical Earring in the plan while
`contest.explain` named nobody for the slot — the two halves of one record disagreeing about
who decided it, which is the invariant ADR 0027 holds. It rendered as an ordinary row, because
a missing winner simply printed nothing. Now `<- NO CLAIMANT RECORDED (the plan has it, the
contest names nobody)`. The shape is suggestive: the slot became newly eligible on the level-up
(Optical Earring is Lv10, he crossed 9 → 10), landed in the plan that beat, and acquired its
claimant **two dispatches later** — which is what generated the zero-change record at #4. The
same shape explains the six empty blocks of the previous round.

**(ii) A slot reported changed that did not change.** `#3` said `2 slots changed` and showed
Main and Sub carrying exactly what `#2` had. The row printed only the NEW item, so a record
claiming a slot moved to the piece it already had was indistinguishable from a real change.
Blocks now carry `was:` for slots the record calls changed — the core question of a decision
log, and the report could not answer it — and when the previous item is identical the line says
`SAME ITEM, yet the record lists this slot as changed`. Replaying his real `#1`–`#4` shows Main
and Sub flagged in **both** `#2` and `#3`, so it is a pattern rather than an incident, and both
slots come from the `Weapons` set.

`changed` is display-only (arbmonui's bright cells, this report), so neither oddity moves gear
— but they inflate every count a reader trusts, and they are now labelled instead of invisible.
**Not chased into dispatch this round**: that is an engine investigation with its own field
cost, and the tooling had to be able to state the problem first.

Suites **5920** and **1003**. The rule that keeps paying: `was:` prints ONLY for slots the
record calls changed. Printing it everywhere would invent an event out of a slot that merely
held, which is the same class of lie the `(kept)` row told two rounds ago.

### The engine half — a record's contest now explains that record's plan (engine v163, `2026.08.03f`)

Henrik: *"Go ahead and implement that."* So the two oddities the report surfaced were traced into
`dispatch` rather than described. **One was a real bug with a single root cause. The other was
not a bug at all, and my previous entry overstated it — corrected below.**

**THE BUG.** `contest` was built only on a **retrace** and otherwise reused from the previous
trace (`old.contest`). And the retrace signature covers matched rules + cases, locks, claimant
legs, the sets-store revision and the rank order — **not the player's LEVEL**. So levelling
changes which candidates a set resolves to while the signature holds: the plan moves, the
explanation does not, and the ring appends a record whose two halves disagree about who decided
a slot. Both symptoms fall out of that one fact — `Ear1` carrying Optical Earring (Lv10) in the
plan with the contest naming nobody, and the claimant arriving two dispatches later as a
zero-change record. It also explains the six empty blocks of the round before.

Fixed in two places. `slotSrc`/`floorTbl` are now collected on **every** pass: they were gated
`retrace and {} or nil`, sharing one `if retrace` with the `/dl why` **line formatting** — and
the formatting is the half that costs (a `string.format` per rule), while filling two small
tables is nothing beside the `equipSetByName` that already ran. With the attribution always
present the contest became rebuildable at all, so it is re-explained whenever
`M._planOutrunsContest` says the plan named a slot the explanation cannot account for, or
swapped the item inside one it covers (the item half matters precisely because the *level* is
not in the signature).

**The test is deliberately ONE-WAY**, and that is the ruling worth keeping: a contest naming
**more** than the plan is ordinary and must not rebuild. A lock, or the level-sync weapon hold,
takes a slot out of the plan while the claim on it stands — two questions answered correctly.
Rebuilding on that would re-explain on every held beat.

**THE CORRECTION.** The previous entry called "Main and Sub reported changed while carrying the
same items" a pattern *confirmed from his artifact*. It was not: that output came from my own
**replay fixture**, which had assumed both plans carried Main. The real cause is the level-sync
weapon hold (v56) doing exactly its job — `ctx.syncHold` nils Main/Sub/Range, so they leave the
plan and return, and the ring correctly records both moves. What made it look wrong was a
**renderer** ambiguity: when the plan did not name a slot, the row printed the *winner's* item,
formatted identically to a piece that had actually gone on. That single ambiguity is why two
unrelated things were both undiagnosable. A slot the plan skipped now reads `(not placed)` with
the claim and the likely hold named underneath.

Suites **5938** and **1003**. `PO8` asserts the invariant over every record the suite's real
dispatches build — though it is honest to record that it does **not** prove the fix: disabling
the rebuild leaves it green, because the suite never produces a non-retrace pass whose plan
moved. It is a guard against regression, and the proof stays the field round.

Two lessons. **A signature that gates an explanation must cover everything the explanation
depends on** — the level was missing, and nothing said so for four days because the explanation
was only ever read by a hover nobody was staring at. And: *reading the artifact is the test*.
Every defect in this train came from reading a report end to end, never from the suites.

## Session "several pins on one hat slot" (2026-08-03, `2026.08.03h` — the floating armory menu)

**Theme:** three field asks against the floating equipment window, all of them about the
right-click PIN menu rather than the window.

**1. Only what you can wear at that moment.** The list was gated on job and level already
(the Gear Oracle's `canWear`, through `candidatesForSlot`) — the missing half was the
BAGS. `candidatesForSlot` gates ownership on *owned anywhere*, which is right for a set
builder and wrong here: a pin equips, so a piece in a Mog Locker was offered, pinned, and
then did nothing. It reads as a broken pin, not as a misplaced item. Fixed by asking
`gearui`'s `avail.have` — the same function the Sets tab previews the engine's own refusal
with, so the menu and the engine cannot drift. Three-valued for the reason it is
three-valued there: only a definite `false` hides a row, because an empty bag scan means
"the scan has not answered yet", and hiding on *don't know* would empty the menu at exactly
the moment you opened it.

**2. Icons.** `ui\itemicons.renderIcon` per row, on the candidate rows and on the pinned
ones. Nothing new: the same call `equippedui` has made since July, drawn from the record's
own `Id`.

**3. Several pins on one slot.** The ask: *"I want Optical Hat on Tp_Default, but Walahra
Turban on Movement."* A slot's value becomes a LIST of `{ item, scope }` entries.

The part worth keeping is that **the tie-break was borrowed, not invented**. An overlay is
an equip table and a slot wears one thing, so a dispatch where two pinned triggers both
matched has to pick. `dispatch._pinRank` scores an entry by the index of the **last hit it
names** — and `hits` is already sorted ascending by priority and applied last-writer-wins
(ADR 0003). So the pin belonging to the trigger that would have won the slot anyway is the
pin that wins it, and nothing new had to be decided about rule precedence. `'All'` scores
0, the weakest claim there is, which falls out of the same idea: "always" is the least
specific thing a pin can say. That single number is why an All pin sitting under scoped
siblings behaves as a *fallback* rather than a competitor, with no special case anywhere.

On the way in the rules are Henrik's, verbatim: `'All'` replaces the slot whole; a scoped
pin replaces only the pins already holding one of the SAME triggers (one item per trigger
per slot). Clearing now has all three scopes and each has its own row — this pin, this
slot, everything.

**A one-pin slot still serializes byte for byte as it always did.** The list shape appears
only where a second pin actually exists. That was not politeness toward the file format: an
older seeded engine copy reads a single-entry slot unchanged, so the common case never
touches the new path in either state. Both states read the shape through the same walk
(`pinwatch.entriesOf` / `dispatch._pinEntriesOf`), spelled twice on purpose — the engine
runs in the other Lua state and must never depend on an addon-state module being loaded.

**The 200-local ceiling bit again, immediately.** Two new chunk locals in `dispatch.lua`'s
main chunk and it stopped compiling — `too many local variables` at line 7510, nowhere near
the edit. Both helpers went onto `M` instead, where they wanted to be anyway (test seams).
Worth restating because the error points at the *end* of the chunk, not at the addition.

Also: the grid paints a scoped-only pin a different colour from an All pin. Red used to
mean "this piece is stuck on"; with conditional pins it stopped being true, and the colour
is the only thing a chrome-less window can say without being opened.

**Tests:** `AL42`–`AL58` (engine: the list shape, rank ordering, All-as-fallback, ties,
every tolerated shape), `AM17`–`AM51` (pinwatch: the replace rules, per-pin removal, the
two file shapes round-tripped through the engine's own reader, counts), and a new smoke
section `FGP1`–`FGP18` that renders the popup OPEN against a real candidate pool and reads
back the labels — section 6 proves the window cannot corrupt ImGui's stacks but stubs every
row away, and all three asks are about the rows. Suites **5990** and **1046**.

**Note for the record:** the `dispatch.lua` half of this landed inside commit `df77475`,
which belongs to a parallel session — a shared-checkout sweep, not a decision. The change
itself is unaffected.

## Session "grow with the text" (2026-08-03, `2026.08.03j` — the pin popup's width)

Henrik, on the round above: *"Can you make the right click menu automatically grow in size
with the text? I think it's doing that, but only based on equip names and not the pin
list."*

The read was exactly right and the cause is one line. Both lists live inside the *same*
auto-sizing popup — `BeginPopup` forces `AlwaysAutoResize`, so the only thing that can stop
it growing is the constraint, and the constraint was a flat `{380, 460}`. An item name is
~20 characters and never comes near 380, so the candidate list looked like it grew freely.
A pinned row is a name **and** a trigger, sails past it, and a clamped auto-resize window
has exactly one move left: clip. Same window, same mechanism, two very different-looking
behaviours, from one number that was fine until the rows got longer.

So the ceiling became a measurement (`popupMaxW`): the widest pinned row, and — because
only the longest *name* can be the widest candidate row — one `CalcTextSize` for the whole
item list however long it is. Measured **unfiltered**, deliberately: a width that holds
still while you type is worth more than one that shaves pixels per keystroke.

Three details worth keeping. The measurement runs in `M.render` **before** `BeginPopup`,
not from last frame's content, because a constraint is consumed by the next window and a
width one frame behind resizes visibly every time the list changes — so the rows are built
once, measured, and handed down to `renderPinMenu` rather than built twice. It only runs
while the menu is up (`_openFor` covers the opening frame, `_popupUp` every frame after),
so a shut menu costs nothing. And `MAX_W` stays a real limit: a rule with six conditions
can produce a scope line wide enough to cross the screen, and past that point the honest
answer is a scrollbar, not a window you cannot see around.

The pinned rows also lost their 34-character truncation — the popup is now sized to that
exact string, and cutting the line *and* widening the window for it would be two answers to
one question. The half being cut was the trigger, which is the only thing telling one
pinned row from the next. Trigger choices gained a `short` spelling (event + conditions, no
` -> SetName`) for the rows; the tooltip keeps the long one, where there is no width to
fight over.

**Tests:** smoke `FGP19`–`FGP22` drive `CalcTextSize` per-character and read the constraint
back — floor with nothing pinned, wider with pins, wider still with a longer trigger,
clamped at the ceiling. Suites **5990** and **1052**.

## Session "beside the menu, not on top of it" (2026-08-03, `2026.08.03k` — item facts in the pin menu)

Henrik: *"Can you also make it so it shows the stats of the item as well? Have it be
somewhere where it doesn't clip into the right click menu or cover it."*

The constraint is the whole design. **A tooltip cannot do this job** — it follows the
cursor, and the cursor is on the menu, so every stat line would land on the rows you are
trying to read. So it is a window of dlac's own, placed against the popup's rect.

**Which side is not a preference, it is a deduction.** The scope cascade opens to the
RIGHT, so the left is the one side the menu chain can never grow into. When the popup is
hard against the left edge of the screen there is no left, and the panel drops UNDERNEATH
it instead — a submenu is drawn beside its parent *row*, so below the whole popup is still
clear of it. The rect comes from `GetWindowPos`/`GetWindowSize` read from *inside* the
popup, the only place ImGui will tell you, and both it and the hovered record are filled
during the popup and read after it closes in the same frame, so neither can go stale.

**The card is not a second card.** `gearui.renderItemTooltip` grew a third argument,
`bare`, that skips its `BeginTooltip`/`EndTooltip` — same stats, DMG/Delay, set-bonus
ladder, where every copy is stored, your augments, jobs. A third argument rather than a
split-out helper because that chunk is at the 200-local ceiling and one more
`local function` will not compile. The point is that the day someone adds a line to the
hover card, this panel gets it too instead of quietly falling behind.

**The hover signal is `BeginMenu`'s return, not `IsItemHovered`.** A submenu in a popup
opens on hover and stays open while you are inside it, so "this cascade is open" *is* "this
is the item I am looking at" — and it keeps the facts up while you travel across to pick a
trigger, which a hover test on the parent row drops the moment the cursor leaves it.

**The `or 0` law bit again, and the test is why it was caught.** `FGP28` asks whether the
panel carries `NoMouseInputs`, and it failed: the ImGui flag globals do not exist headless,
so `(ImGuiWindowFlags_NoInputs or 0)` was plain `0`. In the game the constant exists and it
would have worked — but that is exactly the trap `HOVER_FLAGS` has a comment about at the
top of the same file, and it bites harder here: `or 0` does not *degrade* this panel, it
hands the panel the mouse the MENU needed, and the failure reads as "the right-click menu
randomly stops responding", which is nobody's idea of a missing constant. Real bit values
now, spelled as the three individual input bits rather than their union so each has one.

**Tests:** smoke `FGP23`–`FGP31` — nothing hovered draws nothing, hovering opens the panel
for the item actually hovered, the card is asked for frameless, it lands clear to the left,
it drops below when there is no left, it cannot catch the mouse, and every window opened in
the frame is closed. Suites **5990** and **1061**.

## Session "the cascade was eating the screen" (2026-08-03, `2026.08.03l`)

Four field screenshots of the pin menu in each screen corner, and they answered more than
the question asked of them. The item-facts panel was being *sliced* — three rows of Bunzi's
Robe's six visible, the rest painted over by the scope cascade.

**The first finding is a hard ImGui rule, not a placement bug.** A plain `Begin()` window is
always drawn under any open popup or menu, whatever order it is created in. So no amount of
moving the panel fixes it: anywhere the cascade reaches, the panel loses. (Two ways above
it exist and are written down for when they are needed: `SetNextWindowPos` +
`BeginTooltip`, because tooltips are the one window class that renders over popups and
setting the position first suppresses the mouse-follow; or `GetForegroundDrawList`, which
draws over everything but is raw shapes and would fork the card. Neither is used yet.)

**The second finding is that no placement rule could have worked anyway.** Measured off the
screenshots: popup ~245px, cascade ~750px, on a ~1130px client. The menu chain was ~1000 of
1130 pixels wide and full height. There was no 360px gap anywhere — not beside it, not above
it, not below it. Henrik's own arithmetic (panel rows + 1, and "this would only fit if my
mouse were on the FIFTH equipment") arrives at the same wall from the other direction.

So the fix is the cause, not the symptom: **the cascade got smaller.**

Rows now spell the SET instead of the conditions — `Midcast  -> Enfeebling_White` in place
of `Midcast  magicType = White Magic, skill = Enfeebling Magic  -> Enfeebling_White`. A
third of the width for the same identification.

**But the conditions could not simply be dropped, and the screenshot is what proved it.**
That job carries two Default rules both reading `status = Idle`, one feeding the Idle set
and one feeding Weapon: drop the *set* and they are the same row twice, drop the
*conditions* and they stay distinct. The set name is the half that identifies a rule to a
person. So the rule is: compact by default, and any label that would appear **twice** falls
back to the full line — the only case that needed the width to begin with. Both duplicates
fall back, not just the second; one explained row beside one unexplained row reads worse
than two long ones. `floatgear.disambiguate` is pure and exported, because the point of it
is a guarantee (no two rows read alike) and a guarantee wants a test.

**And the cascade is height-capped now**, so a job with thirty triggers scrolls instead of
running off the bottom of the screen. Through `SetNextWindowSizeConstraints` before
`BeginMenu`, never a `BeginChild` — a child window inside the menu chain is exactly what
tore the whole popup down back in July, and the constraint is the mechanism the parent popup
already uses. Height only: capping the width would re-clip the rows the compact spelling
just fixed. The catch is that a constraint no submenu consumed stays armed and lands on the
next `Begin` **anywhere** — including another addon's window — so the loop ends by setting
a 100000x100000 constraint, which constrains nothing. ImGui offers no other way to take one
back.

**Tests:** smoke `FGP32`–`FGP40` — unique rows stay short, a duplicated compact label sends
*both* rows back to the full line, an unaffected row beside them stays short, no two rows
read alike afterwards, every cascade is capped before it opens, the leftover is neutralised,
and the popup's own measured cap is untouched by any of it. Suites **5990** and **1070**.

**Owed in the field:** that a size-constrained submenu actually scrolls in this ImGui build,
and that the popup still survives moving the mouse across items with the constraint armed.

## Session "inside the window, not beside it" (2026-08-03, `2026.08.03m`)

Henrik, after the two failed placements: *"Have the status window integrated in the right
click window. Look at the biggest height from a piece, and widest width (can be different
pieces), adapt the main right click window after that (so it doesn't move around every time
you scroll around on gear). That way, it doesn't have to adapt as an outside window to other
two windows."*

That dissolves the problem rather than solving it. **Nothing inside a window can be covered
by that window's own menus** — no side to choose, no rect to dodge, no z-order to lose. The
two earlier shapes both failed for reasons that are now written into the file header so
nobody re-tries them: a tooltip follows the cursor and the cursor is on the menu; a window
of our own is *always* drawn under an open popup in ImGui, whatever order it is created in.

**The reservation forced a rewrite of the card, and this is the real lesson.** You cannot
measure a card without drawing it. `gearui.renderItemTooltip` renders straight to ImGui, so
asking "how tall is the tallest piece in this pool" is not a question it can answer — and
that question is the whole feature. So the block builds its lines as **data first**
(`factsLines` returns `{col, text}`), and the same builder that draws one piece can be asked
how many lines thirty of them would take. The one-round-old `bare` argument on
`renderItemTooltip` went back out with it rather than sit there unused.

It is also deliberately **bounded**: every open-ended part of the full card (the set-bonus
ladder, the partner-piece list, every owned copy's augments) is absent, because a card that
can run twenty lines cannot have space reserved for it without eating the popup. Wrapping is
**character-based, not pixel-based** — the count has to be identical in the measuring pass
and the drawing pass, and a proportional font measured per-fragment is not.

Height is reserved for the pool's tallest piece and padded with a `Dummy`; the **width needs
no equivalent** because the lines wrap to the width the item rows already settled, so the
block cannot widen the popup at all. Two of Henrik's asks, one mechanism each.

**One consequence had to be paid for.** Adding ~8 lines to the popup pushes a full slot's
gear past the 460px height cap, the popup grows a scrollbar, and the first thing to scroll
out of sight is the block — which would make integrating it pointless. So the item list now
gets what is *left* of the cap: `rowCap` from the measured line height, the pinned rows and
the reserved block. The overflow was always counted rather than hidden ("+N more — type to
narrow"); this only makes the counting start sooner. It depends on the pool's tallest card,
never the hovered one, so the row count does not shift while you read.

The block shows **last frame's** hover — it is drawn above the list, and the hover is
discovered while drawing the list below it. Same trade the Equipped tab's compare panel has
always made, and invisible at 60fps.

**A test-only bug worth recording**, because it is the kind that hides: deleting the old
panel's checks left `Sx.renderItemTooltip = keptTip` behind with `keptTip` no longer
declared. In Lua that reads as a nil global, so the line *nulled the service* for every
later section — and the suite stayed green, because nothing downstream happened to call it.
Found by grepping the removed names rather than by a red test.

**Tests:** smoke `FGP23`–`FGP29` — no second window is opened at all, every window that is
gets closed, the line builder yields data, it wraps to a width, the reserved height is the
pool's tallest piece and not the hovered one, the answer does not depend on pool order, and
an empty pool still reserves its prompt line. Suites **5990** and **1068**.

## Session "width buys height" (2026-08-03, `2026.08.03n`)

Henrik, on the integrated facts block: *"make it WIDER to adapt as well, so we get more
space for gear."*

The block wrapped to whatever width the item ROWS had already settled — so a slot full of
short names left it at the 250px floor, a long stat line wrapped into four, and the
reservation ate four lines of the height cap that the gear list wanted. **Width buys
height**, and that is the whole reason it is worth spending: a popup 200px wider turns that
four-line wrap into two, the reservation shrinks by two, and those two lines go straight
back to the list under the cap.

So the facts get a **vote** on the width, cast as *"the widest line any piece in this pool
would draw unwrapped"* — the width at which the block needs no wrapping at all. A vote and
not a demand: it is one input beside the item rows and the pinned rows, and the result is
clamped like all of them. A block that only needed 80 more pixels gets them and gets a line
of gear back for them; a stat line longer than the screen asks and is told no.

**The ceiling is now the screen, not a constant.** 720 as the base, but never more than
about 55% of `GetIO().DisplaySize.x` — a popup wider than half the display leaves its own
cascade nowhere to open, and on Henrik's ~1130px client that is a real limit rather than a
theoretical one. `DisplaySize` is the single screen fact the binding exposes and this is
what it is for.

**One thing had to change in the block to make the vote honest.** The job list is
slash-joined with no spaces, so it is a single token: `wrapTo` could never break it, and it
sat there widening the popup with no fallback if the width was refused. It is truncated to
the wrap budget now — it still *asks* for its full width (the measurement runs unwrapped),
this only bounds what happens when the answer is no. Same shape as the augment and Held
lines, which had it from the start.

**Tests:** smoke `FGP30`–`FGP34` — a wider wrap needs fewer reserved lines, a short name
with short facts leaves the popup at the floor, a long facts line widens it with that same
short name, and a small display clamps the ceiling below what the facts asked for. Suites
**5990** and **1073**.

## Session "a max is not a width" (2026-08-03, `2026.08.03o`)

Henrik restated the requirement plainly: *"Go through all the pieces one by one. Have a
variable for max seen height. One variable for max seen width. Then set the window width
according to max width we saw on a gear piece, as well as reserve the max height seen above
the item list. This way, the window will remain static and not adapt its size for every
item."*

Checking that against the code found the measurements all present and correct — and the last
step missing, which is the only step that shows. **A popup is `AlwaysAutoResize`, so a MAX
constraint is not a width.** The window still shrank to whatever it happened to be drawing,
and since the facts block draws a different piece every time the cursor moves, it breathed
in and out under the mouse. Every number was right; nothing was being *told* to hold.

`min.x == max.x` pins it. The height deliberately stays a range: the block is padded to its
reservation, so the content there is identical every frame and a cap is the useful thing to
say about it.

Worth writing down as a rule, because it is not obvious and it cost a round: **with
`AlwaysAutoResize`, a size constraint whose min and max differ is a permission, not an
instruction.** If a window must not move, the two have to meet.

**And "all the pieces" turned out to be more pieces than the pool holds.** A pinned piece is
not necessarily a candidate — the bag gate drops a piece you pinned this morning once it
moves to a Mog Safe, while its pinned ROW stays in the menu. Hovering that row drew a card
nobody had measured, so the window jumped for exactly the people who have moved gear since
pinning it: rare, invisible in testing, and precisely the failure the reservation exists to
prevent. The measurement pool is candidates **plus** pinned pieces now.

**Tests:** smoke `FGP35`–`FGP37` — the width is pinned rather than capped, the height stays
a range, and a pinned piece that is not in the pool still widens the popup. Suites **5990**
and **1076**.

## Session "the shorter hat was taller" (2026-08-03, `2026.08.03p`)

Henrik: *"When I compare hovering Bunzi's Hat (5 rows) and Windfall Hat (4 rows), the height
changes. The height INCREASES with Windfall Hat, even though it has fewer rows. Can this be
explained?"*

It can, and it is one line of ImGui semantics. **The cursor advances by `item height +
ItemSpacing.y` after EVERY item.** The block drew its real lines as text and then padded the
remainder with a single `Dummy` of the leftover height — so:

* a piece at the maximum drew 5 text items and paid 5 gaps;
* a piece one line short drew 4 text items **plus a Dummy**, which is 6 items and 6 gaps.

The shorter piece was taller by exactly one `ItemSpacing.y`, and only pieces that needed
padding paid it — which is why it read as "the height increases with the smaller hat"
instead of as a constant offset. Every measurement upstream was correct; the reservation
arithmetic was right; the padding widget was the whole bug.

Padding with the **same widget the content uses** deletes the arithmetic rather than fixing
it: N lines is N lines whichever of them carry text. (An empty string still advances a full
line — ImGui gives zero-length text the font's line height.)

The general form, worth keeping: **when you reserve space by padding, pad with the same
item type you are padding around.** Any other filler brings its own box model, and the
difference shows up as a drift proportional to how much padding was needed — which looks
like anything except a spacing bug.

**Tests:** smoke `FGP41`–`FGP44` count line ITEMS rather than pixels (the stub has no
layout): the tallest piece fills the reservation exactly, a shorter piece emits the same
number of lines, an empty hover does too, and no `Dummy` is emitted at all. Plus `FGP40b`,
which asserts the two sample pieces differ in natural height — without it the whole group
would pass while never exercising the padding. Suites **5990** and **1081**.

## Session "a scrollbar for one row" (2026-08-03, `2026.08.03q`)

Henrik, with arrows drawn on the screenshot: the cascade scrolls (fine, sixteen triggers),
but the main popup had a scrollbar too — *"barely any, it is just outside the main window.
If it was just a little bit higher the scroll would not be needed."* The `+5 more — type to
narrow` footer sat half-clipped under it.

**The list came out about one row over the cap.** The row budget subtracted an *estimate* of
the chrome above it — `(5 + maxLines) * lineH + #held * rowH` — and that estimate was around
two lines short. A search box is a framed widget and taller than a text line, separators
carry their own spacing, and the guessed constant covered neither. Two lines short of the
cap is not a layout problem, it is a scrollbar for a sliver.

**It is measured now.** By the time the list starts, everything above it has already been
submitted, so *the cursor's own travel is the chrome* — one `GetCursorScreenPos` at the top
of the popup, one where the list begins, and the difference is exact for the header, the
move row, the search box, every pinned row, the reserved facts block and every separator
between them, with nothing to keep in step when any of those change. The only allowance left
is the footer, which has not been drawn yet: three lines covers its separator, its line and
the window's bottom padding.

The rule this is the second instance of: **when the thing you need is already on screen,
read it — do not model it.** The width stopped being a constant two rounds ago for the same
reason.

**And the cap takes what the screen offers.** 460 was a constant that looked reasonable on
one machine; it is 560 now, clamped to 85% of `GetIO().DisplaySize.y`. Height is the axis a
player has most of, and the popup was leaving it on the table.

**Tests:** `_rowBudget` is pure, so smoke `FGP45`–`FGP50` drive the arithmetic directly —
taller chrome leaves fewer rows, the footer is subtracted, a taller cap buys rows back, a
cramped popup keeps a floor of four, a zero row height is refused rather than dividing, and
the exact floor case is pinned (560 − 200 − 51 = 309, 309/24 = **12** rows, not 13 — a
rounded-up row is the whole bug). `FGP51`–`FGP52` cover the screen-aware cap. Suites **5990**
and **1089**.

## Session "what is in the wardrobe that nothing asks for" (2026-08-03, `2026.08.03r`)

Henrik: *"Mog Wardrobe space is limited and very important, it would be nice to know which
pieces you have in mog wardrobes that are actively not being used at all, so you can maybe
put them in another container with less value, like mog safe, locker etc."*

**It is `gear/gearcheck.lua` read backwards.** Gearcheck starts from the sets your triggers
use and asks whether every piece is equippable right now; `/dl unused` starts from the BAG
and asks whether anything references the piece at all — across every profile and every job
entry, dormant archives included. Every step was existing machinery: `listProfileFilesAt`
for the entries, `profiles.readSetsFile` to sandbox-load a set file against the real gear
table (so `gear.Head.Faceguard_1` arrives as the record with its Id — no text parsing), and
`gearimport.ownedSplit().where` for the live per-container counts. The wardrobes are
`gearoracle.equipBags()` minus Inventory, so the bag list is still stated in exactly one
place (GRD3).

**The interesting half was deciding what "used" means**, and all four calls are Henrik's:

1. **A set no rule points at is its own answer.** He has 63 of them across 257 sets — spare
   idle variants, a `Ws_Default` on a job whose Weaponskill handler has no rules. Their
   pieces get a section of their own and are never called unused.
2. **A lockstyle piece does not need a wardrobe.** Henrik: *"you can lockstyle to pieces
   that are on mog house etc."* Confirmed in the server source — but in **two halves, and
   collapsing them into one is exactly the mistake this entry exists to prevent.**
   `c2s/0x053_lockstyle.cpp` (`Set`) stores the id after checking only that it is real
   equipment that fits the slot: no ownership, no container. That is the half I read first,
   and I wrote *"never reads ownership or container"* into four files off it. The gate is
   one call further on: `charutils.cpp UpdateArmorStyle` renders only when
   `HasItem(PChar, id)` **and** `canEquipItemOnAnyJob`, and `HasItem` walks **every**
   container (`0..MAX_CONTAINER_ID`). So the container is genuinely irrelevant — Mog Safe,
   Locker, Storage all keep the look — while **still owning the piece is not**: sell it and
   the slot renders empty. Caught by an 18-day-old memory note ([[lockstyle-server-rules]])
   that already had the right sentence in it; the wording was corrected in the same session,
   one commit after the promotion. **A handler that accepts a value is not the code that
   uses it — read to the consumer before claiming what is not checked.**
   Lockstyle-only pieces are reported as MOVEABLE (61 of them on his character), with the
   window saying *move them anywhere, but keep them*.
3. **Helper picks count as use, named by helper** — the MaxMP ladder, auto-staff/obi/grip,
   craft, HELM, fishing, chocobo, the per-job ammo lists, the rod and bait, and a job
   helper's pinned item (BST's `resummonJug`). dlac equips these with no set naming them.
4. **...but the manifest's `mp` / `rf` / `mv` tables do NOT.** They are name→value stat
   caches the ladders score with, not pick lists; `mpBest` is the pick list. Counting a
   cache as use would mark every refresh piece you own as used and quietly gut the report.

**Two set names are claimed by CONFIG rather than by a rule**, and both would otherwise
read as orphans: `autogear.mpPairIdle` (the set the MaxMP ladder pairs into) and a job
helper's `summonSet` (BST's `Chr_Swap`). They are promoted to live with the reason saying
who asked. `M.HELPER_PINS` is the declared list — a new helper with pins adds a row.

**Every exclusion is a line in the file**, per the no-silent-caps law: the stat caches, the
consumable surfaces (restock staples, food) a wardrobe cannot hold anyway, session-only
pins, and other characters' profiles.

The window (`ui/unusedui.lua`) shows the LAST SAVED report with a Refresh button — Henrik's
shape, because a walk over every profile plus a bag pass is not a per-frame read — so the
report is written to `<char>\unusedreport.lua` and survives a reload. Its `Begin`/`End` and
`BeginChild`/`EndChild` are paired **around a pcall**: a throw in the body costs one frame of
content and says so, instead of unbalancing the ImGui stack for every surface drawn after it.

**Tests:** `UNU1`–`UNU10d` drive the pure walkers (all four authored entry shapes, list-form
`set` refs, the three buckets and their precedence, the helper reasons, the stat-cache
exclusion, the capped why-list) and `build()` end to end over the injected seam, including
that a Mog Safe item never reaches the report. Smoke `UW1`–`UW6` execute the window in all
three states and assert the rows actually reached the screen. Verified additionally against
Henrik's real on-disk tree headlessly: 25 job entries, 257 sets, 194 triggered / 63 not,
84 lockstyle pieces, 426 referenced ids. Suites **6035** and **1108**.

**Iteration 1 by agreement.** Henrik, accepting it for main the same day: *"this is just a
first iteration, we will most likely work on this more and combine features, especially when
/ if storage move is accepted."* The pairing he means is `docs/design/storage-move.md` — the
right-click **Move To →** research from 07-10 (feasible, fully server-validated, never
built). Today the audit only tells you; with that, a flagged row could move itself out of the
wardrobe. The row shape was left ready for it (id + container + copy count), and the rule for
whoever extends this is: a new "what asks for an item" source joins `M.collect`'s three
buckets or `M.HELPER_PINS` — never a second walk over the profiles.

## Session "two knives and an invisible animator" (2026-08-03, `2026.08.03t`, engine v164)

Two bugs out of one support report (`/dl report`, Coffeepoo — a second field tester, not
Henrik). Both had the same shape underneath: **a fact that changes was cached in a file
that never gets rewritten.** Neither was findable from the symptom; both fell out of
reading the artifact.

**One: two Bone Knives +1, and only the Main hand got one.** The report's decision #25
named `Main  Bone Knife +1` with a ladder, and `Sub  (left as worn)` with no ladder line at
all — zero candidates survived. Dual Wield was up (he could equip the off-hand *by hand*),
the set was right, and the level gates were right; the refusal was ours.
`utils.subSlotAllowed`'s same-name case wants proof of a second copy (`twoCopies`, the flag
that replaced the legacy `InBothHands` on 07-13), and it takes the best of `ctx.copies` and
the record's `Count`. The flatten passed **no `copies`** — only `ui\gearui` ever did — so at
equip time the sole evidence was the `Count` stamp, which `renderEntry` writes once, at
first index, when the scan happened to see two. And nothing can refresh it: `M.sync`/
`M.stage` are add-only (an already-`Known` item is skipped) and `/dl fix` backfills catalog
facts, which ownership correctly is not. **Buy the twin after the first was indexed and
dlac could never learn about it** — the only route back was a hand edit, and Henrik's own
file had exactly that.

Fixed by reading the bags, which is the 2026-08-01 Pair/RSlot ruling applied to the one
fact that really is per-player: `dispatch.M.bagCopies` over the existing per-second cache
(equip-eligible containers, worn pieces included — they still sit in their wardrobe slot),
consumed by `utils.slotLadder` through `M.dispatchModule`. Three properties kept
deliberately: the read only ever **adds** evidence (best-of, so a stamped `Count` still
wins and nothing that pairs today stops pairing), an unreadable scan **falls back to the
stamp** rather than demoting gear, and the lookup happens **only when the two names match**,
so the ordinary off-hand costs nothing. Tests `LD6c`–`LD6h`.

**Two: the base Animator never appeared anywhere** — not in the picker, not in a ladder.
Henrik had hit this himself and half-remembered fixing it; he had, in `Mindie_29909\gear.lua`,
**by hand** (the entry carries a `Stats = {}` block no writer in the tree emits). The code
hole was untouched and identical for everyone. `resolveItem` bucketed skill-0 Range items
with `res.Jobs == PUP_ONLY_MASK` — an **exact mask test** — and Animator 17859 is an
ALL-JOBS item on this server (`sql/item_equipment.sql`: jobs 4194303; catalog: `Jobs =
{"All"}`). No bucket meant `renderEntry` returned nil, which meant the piece was never
written to gear.lua at all. Every *other* animator is PUP-only and indexed fine, which is
precisely why it read as one broken item instead of a broken rule; the same hole swallowed
Soultrapper, Soultrapper 2000, Fiendtrapper, Soulgauger SGR-1 and Marvelous Cheer.

`gearimport.rangeCategory` now buckets by **what the piece is**: `0:10`/`0:11` is the
animator subskill (an item fact — the same key the server pairs oils on) → `PUP`, the
PUP-only mask still answers when no catalog supplies a Pair, and anything else skill-0
lands in `Misc` rather than nowhere. It can never return nil (`E29i` asserts that over the
whole skill × job grid), because nil means invisible. A bucket at all — rather than the
catalog's flat-at-the-slot shape that `E27c` pins — because gear.lua's own `NameToObject`
trailer walks Main/Range as *strictly* two levels and a flat entry there dies on
`NameToObject[nil]`: **the user file cannot hold what the catalog can.** `SH10c`–`SH10f`
pin that a file with no such bucket gets one created rather than a silent `notfound`, so
the fix actually lands on the next sync with no migration and no `/dl` command to run.

**And the reason nobody reported either for months.** `M.stage` printed its `! skipped`
lines only when `not quiet` — and `M.sync` stages *quiet*, so on the one path every player
is actually on, an item dlac could not index disappeared with no error anywhere. `/dl scan`
even **lists** it (the skip happens later, at serialize time), so it read as found and then
never landed. Those lines now print regardless of quiet, once per name per Lua state — a
skipped item is never `Known` and so returns on every scan, and turning the warning into a
spam loop would be the same silence by another route.

**Tests:** `LD6c`–`LD6h`, `E29`–`E29i`, `SH10c`–`SH10f`. Suite **6054**.
