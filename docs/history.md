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
eight-era-elemental-obi assumption; **`BeginPopupContextItem`** in this ImGui binding
(two failed rounds → Trove-style `[mv]` left-click button — but see the CORRECTION
below: right-click ITSELF works, this entry used to say "right-click context menus"
and was wrong); LAC memory MH flag as a
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
rounds)". That is **false and it nearly killed this feature** — the first design round
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

What actually failed twice was **`BeginPopupContextItem`** specifically — not RMB
delivery. `IsMouseClicked(1)` + `IsItemHovered()` feeding the ordinary
`OpenPopup`/`BeginPopup` pair is field-confirmed. The `[mv]` button survives on that
branch only as "Trigger 2 (guaranteed)", and `moveButton`'s comment there still claims
RMB is unreliable — stale, contradicted by the function right below it. Dead-ends
entry corrected. **Lesson: record the API that failed, not the gesture you gave up on.**

### The pin, and why it is not a lock

Henrik's ask was literally "lock the slot" and dlac already has `/dl lock` — but that
word is taken, and it means close to the OPPOSITE: `M.locks` makes the engine *ignore*
a slot. A lock is passive (anything else that strips the piece wins) and it LEAKS —
history: *"engine-owned slot locks (LAC forgets `/lac disable` on reload)"*. So the
outcome he described is delivered by the craft-overlay pattern instead: the engine
**wears** the pinned item at top priority every dispatch. Nothing can remove it,
nothing to restore, nothing to leak. He named it **Pin**; "lock" keeps its old meaning.

### Landed

- **dispatch v44**: `ensurePinState` (clone of `ensureCraftState` — 1/sec throttle,
  raw-text compare), `pinOverlayFor(ps, hits, event)`, applied as the LAST
  `equipResolved` of the dispatch — above the craft overlay, on **every event** (a pin
  that lost its slot mid-cast would not be a pin) and with zero trigger hits.
- **Scope.** `scope = 'All'` or a list of `"<Event>|<rule label>"` keys
  (`M.pinScopeKey`). Label alone is ambiguous — `any` is the label of EVERY
  unconditional rule, so a Precast `any` and a Midcast `any` are indistinguishable and
  one pin would silently cover both. An unknown key goes **quiet** rather than
  falling back to "All" (a pin on a trigger you later edited must not start forcing
  gear everywhere).
- **`M.ruleLabel(when)` — new, and a real bug fix.** normalize built the label with
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
- **`ui/floatgear.lua`** (uihost module, hard rule 1 — gearui gained no locals): the
  4x4 window via the shared `S.renderSlotGrid`, so icons and the full hover tooltip
  can never drift from the Equipped tab's. Toggle + position persist via uiflags
  (`gearfloat`/`gfx`/`gfy`, the `tpfloat` precedent). Pinned slot = **red box**.
- `renderSlotGrid` grew two optional hooks: `opts.boxColorOf(sl)` and
  `opts.onRightClick(label)`. The grid only REPORTS the RMB — it lives inside its own
  `BeginChild` and OpenPopup/BeginPopup must share a window scope, so floatgear raises
  a flag and opens the popup at its own level.
- Tests: **AL** (pin overlay, scope, ruleLabel, guards, the RSlot flap) + **AM**
  (pinwatch round-trip through the engine's own reader, adversarial names). 426 -> 490
  green; smoke_ui 49 -> 53 (S14-17 prove floatgear actually loaded — gearui requires it
  inside a pcall that only PRINTS on failure, so without those checks a broken module
  would sail through as a silent no-op window).

### Three bugs an adversarial review pass caught AFTER the tests were green

Worth recording because all three were invisible to 471 passing checks:

1. **The v43 flap, reached through the overlay.** `reservedDrops` judges ONE table at a
   time, on its final names — but the pin lands in its OWN `equipResolved`. So the SET's
   pass never learned that the pinned Ryl.Ftm. Tunic was about to reserve the Head it
   was equipping, and the pin's pass couldn't drop a Head its table never named. Set
   equips Head → pin equips Tunic → server strips Head → forever. Craft has the same
   hole but its catalog is narrow; **a pin is any item you own — including the Tunic,
   the exact item that motivated v43.** Fixed with `pinReservedSlots` + `ctx.pinReserved`,
   a stateless hold in `equipResolved` (the ratified pattern) rather than widening
   `reservedDrops`. Tests AL34-41.
2. **Both overlays were dead whenever the event had no rules.** `if list == nil or
   #list == 0 then return; end` fired BEFORE the overlays were consulted, so an "All"
   pin did nothing on a profile with no triggers — and the craft overlay's own comment
   ("a plain profile still gets craft gear") had been **false since v31**. M.dispatch now
   decides whether there is anything to do from rules + pins + craft together, ahead of
   the early return, using the already-throttled cached reads.
3. **A corrupt pinstate.lua kept the LAST GOOD pins forever.** `_pin.raw = raw` is
   assigned before the parse, so on a syntax error the raw-compare short-circuited every
   later call and stale pins stayed glued on with nothing able to clear them — including
   pinwatch's clear-on-load. `ensureCraftState` still has the identical shape (v31).

Also from that pass: `fmt.esc` was being applied to Selectable/MenuItem labels — esc
doubles `%` for imgui's FORMATTING calls (Text/TextColored) only, so escaping a
non-format label renders a literal `%%`. Nothing else in dlac escapes a Selectable
label; matched.

### Traps found while building

- **The clear must reach DISK, not just the table.** Pins are session-only (craftwatch's
  rule: no gear glued on at login from last Tuesday). But the ENGINE reads pinstate.lua
  from LAC's own state on its own schedule — clearing only the addon-side table would
  leave a stale file dressing you at login with nothing aware of it. `loadPinState`
  writes the empty file, and it is pumped from gearui's `d3d_present` **whether or not
  the window is open** — it is the only thing that clears it.
- **`tests\run_tests.lua` hit the 200-local cap too** (it is one ~1800-line main chunk;
  482 checks got it there). A `do ... end` block does NOT help — its locals share the
  enclosing chunk's budget. New sections are `(function() ... end)()`, which gets its
  own 200; that is also the cheapest fix when an older `do` section tips it over.
- `subFilter(cands, mainRec, job, level, building)` — the 2nd arg is the Main RECORD,
  not the job. Gating the pin menu's Sub by the worn Main is correct and NOT a breach
  of the Sub HARD RULE: that rule protects the BUILDER's Sub picker (sets are plans);
  a pin equips immediately, like the Alternatives list, which gates too (ADR 0006).
- `BeginMenu`/`EndMenu` are in the SDK and their symbols are in Addons.dll, but NOTHING
  in the whole install calls them from Lua — and presence proves nothing
  (`BeginPopupContextItem` is bound too, and broken). floatgear probes
  `type(imgui.BeginMenu) == 'function'` at load: bound -> the cascade Henrik asked for;
  not bound -> the same choices as an in-place drill-down (gearmove's quantity-chooser
  pattern, proven). **Unverified live — first thing to check in-game.**

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
base+model — `0x2000+59` for Body). Rings/necks/ears/backs/waists have **no model at all**
(`Model = nil` in the catalog — "no look slot", not "unknown"), so the tooltip says
`none (no look)` rather than `0`.

### view_ids

One flag, one line, no new surface. `sf.flags.viewids` (syncflags, beside `debug`/
`autosync`, persisted in `uiflags.lua`); `/dl view_ids [on|off]` is a toggle in gearui's
existing `dlac-ui` handler, cloned from `/dl debug`. The whole feature is a block at the
end of **`renderItemTooltip`** — which is *the* shared hover card, so "all equipment
hover" came free: Equipped, All Equipment, Sets, floatgear and the lockstyle picker all
render through it (that sharing is also why floatgear's tooltip can't drift). Model
resolves the way lockstyle's `modelOf` does — the record's own field, then the catalog
**by Id** — because an owned record only carries `Model` once the enrichment pass has run.

### "Show gear I don't own"

The preview injects your own 0x051 and never asks the server, so it can already render
anything in the game — the only thing standing between it and unowned gear was the
picker's source. So `listFor(slot, q, all)` grew a third arg: `all` sources gearui's flat
catalog list (already `.Slot`-carrying) instead of gear.lua. **`all` LIFTS the ownership
filter; it must never ADD one** — the AH HARD RULE (no job/level gate, ever) governs the
catalog list too. A 2-arg call stays owned-only and byte-identical; AH1-AH9 never moved.

**Save is the gate, not the list.** The server renders a style only if `HasItem` — a
piece you lack silently leaves the slot's OLD look in place (the "why is my lockstyle
stale" trap). So Save refuses while an unowned piece is in the working copy, and says
which slots. **Apply needed no gate of its own**: it reads the SAVED file, which an
ownership-gated Save can never have written. Note this is *not* the off-job case — an
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
- **The gate must fail OPEN.** First cut returned "unowned" whenever the lookup failed —
  and pre-login `gear.lua` is the bundled EMPTY template (dlac.lua preloads at Ashita
  boot; the real one swaps in on the first frame after login). That version bricked Save
  entirely. Now an absent/empty table means "can't tell → don't block", which is
  ownedcache's own rule ("a failed lookup must never take a feature away"). AN27/AN28.
  Choosing gear.lua membership over a live bag scan is the same instinct: gear.lua is
  add-only and a **superset** of what you hold, so nothing the owned picker would have
  offered can newly fail to save.
- **`Main` is 3749 catalog rows** (Body 1743, Head 1391; 14941 total) and every rendered
  row loads an icon texture. The All Equipment tab gets away with the full catalog only
  because its slot headers start COLLAPSED; the picker list renders immediately. Hence
  `BROWSE_CAP = 200`, highest-level-first so the cap keeps the good end — and it is
  announced ("... N more -- showing the 200 highest-level. Type above to narrow."), never
  silent. Cap applies to the catalog list only; the owned list is untouched.

The toggle sits in the picker popup rather than the window's button column: that list is
the only thing it changes, and it is where you notice the piece you want is missing. It
is sticky across opens but deliberately NOT persisted — it's a look-at-things mode, not a
setting. `all` is ANDed with `W.allEquip ~= nil` so it means "this list IS the catalog"
and unwired rows can't be painted as gear you don't own. Save is greyed + refuses with a
reason rather than `BeginDisabled` — that API is used nowhere in this install and hard
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

His instruction — *"check under tools, apiscrape or w/e ... you can use that to fetch data
and validate the source"* — is what settled it. `tools/api_cache/23363.json`, straight
from the server:

    "name": "Amini Bottillons +2",  "slot": 32,  "MId": 0,  "jobs": 0

Bottillons are BOOTS. The server says Body. **CatsEyeXI's `item_equipment` carries rows
for unimplemented items with default values, and the default `slot` is 32 — which decodes
to Body.** 259 such rows; **258 land in Body** (the 1 other is Main). Their names give the
game away: `Gletis Crossbow`, `Mpacas Bow`, `Pinaka`, `Earp`, `Loughnashade`, and the
entire **Amini/Boii `+2`/`+3` reforge tier** — a tier this server has not implemented.
All 190 distinct stub names are **orphans**: no proper row anywhere shares the name, so
they are not duplicates of real items. The crawler copied the server faithfully, we listed
it faithfully, and Body silently carried 258 foreign names.

**A second bug fell out of reading apicrawl.py:**

    jobs = '{"All"}' if (len(js) >= 22 or not js) else ...

`not js` — an EMPTY jobs mask was published as **`Jobs = {"All"}`**. Every stub row was
advertised as equippable by *every job*, the exact opposite of the truth. That is why the
junk never looked suspicious in the catalog: it claimed to be All Jobs gear.

Fixed in **both layers, because they fail independently**:

- **DATA** — apicrawl skips `jobs == 0` and prints the count (`skipped 259 unimplemented
  stub rows`); the `{"All"}` conflation is gone. Rebuild is surgical, verified by diffing
  old vs new: **REMOVED 258, ADDED 0, and Body is the only slot that moved** (1743 → 1485);
  all 258 removed were modelless. `tools/README.md` "The junk rows" is the runbook.
- **PICKER** — `hasLook(rec)` refuses any catalog row with no model. A lockstyle shows a
  MODEL; an item without one cannot be shown (lookpreview DROPS a modelless slot — the AI
  tests — and the server would render it EMPTY), so offering it is offering a no-op. This
  layer must hold on a dirty catalog too.

**`jobs==0` is the marker; `MId==0` is NOT** — and the difference is load-bearing.
`jobs==0` (259) is a strict subset of `MId==0` (1073). The other **814** are real,
equippable, wanted items that merely have no model (all the `Hexed` gear). Dropping those
from the catalog would strip their stats, and the catalog is where every owned item gets
its stats by id. So: the crawl keeps them (data), the look picker refuses them (UI). The
right filter differs by layer, which is exactly why the fix lives in both.

Not applied to the owned list: gear.lua is slotted from the CLIENT's own resource
(`gearimport.slotFromMask`), so it has no stub rows, and the AH HARD RULE says that list
filters on the search box and nothing else (AH6 pins a fixture carrying no Model at all).
The client resource stays the fallback answer if a wrong slot ever turns up on an item
that has real jobs — none did: a name sweep of all 1470 surviving Body pieces found zero
wrong-slot names.

Tests: AN9a-AN9g + S21-S25 (525 + 120). S21 pins the DATA and S22/S23 the PICKER; both
verified to bite — rebuilding the catalog with the stub skip disabled fails S21, and
removing `hasLook` fails S22/S23 and drags 'Amini Bottillons +2' to the TOP of the Body
list (AN9's failure text is the bug, reproduced).

## Session "NON is not a job" — the login that silently ate your sets (07-15, engine v49)

Henrik: *"Uuuh, I don't know exactly when, but either when we did the equipmon floating
box, earlier or later, my triggers don't work? Did something implement itself too hard?"*

Nothing did. The equipmon window was innocent, and the bug was **latent since the storage
move (v33, 07-13 13:55)** — 108 commits and two days earlier. Decision of record:
**ADR 0007**.

### The bug

At login the client's player block is not populated yet, so `GetMainJob()` returns **0**
(= None). gData resolves the main job through the resource manager —
`GetString('jobs.names_abbr', GetMainJob())` — and **0 stringifies to `"NON"`**. The
profile auto-install guarded with:

```lua
if type(job) == 'string' and job ~= '' and job ~= '?' then   -- "NON" sails through
```

So it took `"NON"` for a real job, went looking for `sets\NON.lua`, found nothing
(**nobody has one** — which is why it hit every migrated character identically), installed
nothing, and **LATCHED**: the latch keyed on `gProfile` + profile name and never recorded
*which job* it had answered for. ~6.4 s later (16 ticks) the read settles to the real job,
but `gProfile` has not changed, so the guard never re-fires.

Result: the whole session runs on the shim's empty `.Dynamic`. Every trigger matches and
equips **nothing**, in silence — `equipSetByName` skips a missing set without a word since
v35. `/lac set Idle` → *"Set not found: Idle"*.

### Why it hid for two days

Any **job change** or **Reload LAC** builds a fresh `gProfile` and installs correctly. Two
days of reloading and flipping jobs while building features never left it in the one state
that bites: **log in, play the same job, touch nothing**. Henrik only noticed once the
feature work settled down and he actually just *played*. His own words: *"I've been testing
and running around a lot and haven't really done much that would make me detect this issue."*

The storage move is what made it possible. **Pre-v33 the job file CONTAINED the sets**, so
LAC populated `gProfile.Sets.Dynamic` merely by loading it — no install, no tick, no race.
After v33 the job file is a 1770-byte shim with `Dynamic = {}` and the engine must fill it.

### Two wrong theories (both from reading code, not running it)

1. **Royal Cloak / RSlot (v43).** Confirmed `RSlot = 16` on the Royal Cloak in the live
   `gear.lua`, and it *is* in the WHM Idle Body ladder. Dead end: best-by-level picks
   `Clr. Bliaut +1` (60) over it (59), and reservedDrops only ever drops ONE slot — never
   "triggers don't work". Cost: an hour.
2. **The latch fires on an unanswerable `hasSetsFile` (v45).** Right about *the latch being
   the bug*, wrong about *why it latched*. Shipped v45 (`answerable = setsPath(job) ~= nil`)
   and it did **not** fix it — `setsPath` is non-nil the moment `charBase()` resolves, which
   is well before the job read settles. Kept anyway (it is a real second hole), but it was
   not this.

Both died to the same mistake: **reasoning about a timing bug from static reading.** The
answer only arrived when the engine printed its own state.

### What actually found it

Henrik: *"Look, ask me to do whatever helps you, it's better than guessing."* — then
`/dl instdiag` (temporary, v46–v48: tick counters + a latch log):

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
  **whitelist** of subcommands *before* the branches — adding a branch alone does nothing.
  Whitelist first, branch second.
- **The version must move or the instrument never loads.** `trySelfSwap` compares the
  seeded file's `M.VERSION` to the running one; a changed file at the same version is
  silently ignored. Same for the GUI's red Reload-LAC banner.

### The fix (v49) — both ends

- **`M.jobReady(jobId, jobName)`** rejects a not-ready job, gating on the **id** (0 is
  authoritative; `readJobSets` twenty lines away already did exactly this). The `"NON"`
  name check stays as belt-and-braces — id and string are two different reads.
- **The latch records the job it answered for**, so a settling read re-fires the guard.
  Defense in depth: `jobReady` stops the bogus resolve, the job-keyed latch stops any
  future wrong-job resolve from being permanent.

Tests 527 → 534 (Z1–Z7 pin `jobReady`, incl. **Z7: WAR (id 1) is a real job** — the fix
must not overreach; Y55–Y56 pin the `setsPath == nil` retry signal).

### Lessons

- **A guard that enumerates the bad values misses the one nobody thought of.** `''` and
  `'?'` were a blocklist; `"NON"` was a *valid string*. Gate on the signal the game uses
  for "not ready", not on the shape of the value.
- **The dangerous not-ready read is the one that returns a plausible value, not nil.**
  `charBase()` returns nil pre-login and every caller retries — that one never bit.
  `GetMainJob() == 0 → "NON"` returns *good-looking data*, and cost hours.
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
  `profiles.migrate` **does not install into the live `gProfile`** (it cannot — LAC is still
  running the old in-memory profile until a Reload LAC). His "same issue" was a
  half-migrated profile plus genuinely empty sets.
- **Migration carries `Dynamic` only, and that is by design.** His SAM was a hand-written
  legacy profile with *static* sets (`Idle`/`Tp`/`Ws_Default`/`Meditate`/`Transmog`), its own
  `HandleDefault`, gcinclude wiring and a `Packer` belt. `extractDynamicText` found no
  `Dynamic` block, so migration correctly wrote an empty one; the statics live on in
  `backups\pre-profiles\` for the Sets tab's "Copy from static". The shim does not carry
  hand-written logic — say so when someone migrates a rich profile.

### Confirmed + closed (07-15, engine v50)

Field-verified on **both** characters, each a fresh login touching nothing: Hunklor (SAM,
`latches=tick 1: job=NON ... | tick 17: job=SAM ...`, `Dynamic=1 flattened=1`) and then
Mindie (WHM) — Henrik: *"logged in on Mindie, worked."* Two characters, two profile
shapes, two jobs; that is the fix confirmed on the exact path that used to fail.

`/dl instdiag` and the tick counters are **stripped again in v50** — they were explicit
scaffolding, and dev diagnostics belong in dlacprobe (they live in `cb2fbe2..40288e3` if
this class ever returns). What stays is `M.jobReady` + the job-keyed latch, tests Z1–Z7,
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
  empty ("Select or create a set first, then copy into it") — the copy no longer invents
  a set. The New-box-rename path is gone; the flow is now *pick/create a set, then copy*.
- **Overwrite is confirmed.** A non-empty target opens a `BeginPopup` (not Modal, so
  click-away aborts — same reasoning as the Setup-plan popup): "Replace '<Set>' (N filled
  slots) with static '<Source>'?" Replace / Cancel / click-away. Nothing changes until
  Replace. The one-shot `ui._copyConfirmOpen` drives `OpenPopup` while the data in
  `ui._copyConfirm` persists for the popup's lifetime — calling `OpenPopup` every frame
  would defeat the click-away close.
- **Full-replace.** The target becomes the static's contents; slots the static doesn't
  define are cleared (`M.working = result.working`). An all-unowned copy that resolves to
  **nothing** is the one exception — it leaves the target untouched and says so loudly,
  rather than silently wiping the player's work (hard rule 12).
- **Order verbatim + best-first warning (ADR 0008).** Candidate order is carried as-is;
  dlac still equips the highest-item-Level candidate, which diverges from LAC's
  first-in-list only when a slot's order is **not** best-first (a lower-Level piece ranked
  above a higher one). Those slots get a per-slot chat warning naming the slot; a
  level-descending list imports silently.

### Where the logic lives

The pure transform is its own module, `gear/setimport.lua` —
`importStaticSet(staticSet, slotLabels, resolve) -> { working, notBestFirst, slotCount }`
— with the resolver **injected** (gearui passes `resolveSetItem`; the headless suite
passes a stub over owned records), which is what keeps it Ashita-free and testable. The
UI shell (refuse / confirm / warn) stays in gearui. Tests **AO0–AO23** pin the transform:
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
members = the key's string array. Builds on G1/G2's `groupsmodel` / `Groups` storage —
same file, same Commit.

### What landed

- **The pure transform is its own module, `gear/groupimport.lua`** —
  `parse(text) -> (groups | nil, errors[])`, plus `classify` (created vs collide, CI) and
  `apply` (write into the live map, overwriting under the existing stored spelling). No
  Ashita, no ImGui, no file I/O — the same shape as `setimport.lua`. Tests **TGI0–TGI33**
  pin it: the issue's own paste (T{...} + plain {...} mixed, trailing comma), the
  single-element `STR_VIT = T{'Quad. Continuum', }` -> `["Quad. Continuum"]` exactly, the
  whole `{ Key = {...} }` form, flat-only rejection (nested / non-string / named-field skips
  THAT key while the rest import), malformed input, a sandbox-blocked global, blank/nil
  input, and empty groups.
- **`T` is identity, sandboxed.** The text is evaluated in a minimal env — `T = function(t)
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
  its reason — no silent drop (hard rule 12). Commit still writes the file.
- **`InputTextMultiline` is probed, not assumed** (hard rule 2 — it is used nowhere else in
  this install). Present -> the paste box; absent -> a single-line box with a visible note
  (the parser is comma-separated, so one line still works) — a visible degrade, never a
  silent disable.

### Where it lives / what did NOT change

`renderGroupImport` is a `local` in `ui/triggersui.lua` (addon-state, 92 top-level locals —
well under the 200 cap; smoke_ui guards the load). State rides on the existing `groupUI`
table (no new UI-chunk pressure). **No seeded-file behaviour changed** — `groupimport.lua`
is never seeded, the trigger-file `Groups` format is exactly G2's, and the engine reads it
unchanged — so **no `dispatch.M.VERSION` bump**. Player-facing strings (the control label,
the preview/summary wording, the skip reasons) are **proposed for maintainer sign-off** in
the PR, not finalized.

## Session "searchable spell/ability browse-list" (2026-07-16, issue #26, G3)

Upgraded the Groups tab's member entry from typed-only to a **searchable, job-filtered
spell/ability browse-list with multi-mark** (PRD #21 stories 2/8/16/17/18; ADR 0009). The
same browse capability open issue #12 wants for ordinary `name` triggers, so it is built
once as a shared, coupling-free core.

### What landed

- **`gear/actionpicker.lua` — the pure core.** `buildList(job, spells, abilities)` returns
  the job's learnable spells + abilities as ONE combined, case-insensitively sorted list of
  `{ name, kind, level }` (kind = `'spell'`/`'ability'`), **ungated** — the level is display
  only (build-ahead, HARD RULE 6 / ADR 0006). The picker-DB tables are **injected** (the
  setimport resolver precedent) so it stays Ashita/imgui/file-IO-free. `parseQuery` +
  `matches` are the comma-separated, ALL-terms-substring search predicate — the item-search
  shape (gearui `parseSearch`/`itemSearchMatch`), minus the stat-alias canon (actions carry
  no stats). Never seeded into LAC. Tests **ACP0–ACP26**.
- **The Groups tab picker (triggersui).** Each group box gains a **Browse...** button that
  opens ONE shared popup retargeted per group via `groupUI.browseFor`. Search narrows the
  cached job list; each row is a **checkbox** mark (not a Selectable — the field-proven
  idiom keeps the popup open across marks without a DontClosePopups flag, mirroring gearui's
  weapon-type filter) + a `[S]`/`[A]` marker + name + dim `Lv`. **Add N marked** commits
  every mark through `gm.addMember` (case-insensitive dedup), then closes so the section
  status + member list show the result. Entries already in the group render dimmed with
  `(in group)` and no checkbox. The list is cached per job (`_listJob`) so the ~1000-row
  scan runs once per job, not per frame.
- **Free-name entry stays.** The typed input + `+ member` is untouched — the picker is only
  a faster path for the job's known actions; anything the data misses is still typeable.
- **Untyped, so twins are one mark.** A rare spell+ability sharing a name (e.g. BLU
  "Head Butt") lists as two rows, each labelled, but marking either sets the one
  name-keyed mark (a Group stores the bare name once). Widget IDs are keyed by row, not
  name, so the twin's two checkboxes never collide on the ImGui id stack.

### Where the logic lives

Pure transform + search: `gear/actionpicker.lua` (tests ACP*). UI shell (button, popup,
mark state, cache): `ui/triggersui.lua` `renderGroupBrowsePopup` + `renderGroupBox`, covered
by `smoke_ui`'s chunk load. Data: `data/spells.lua` / `data/abilities.lua` — issue #26 is
their FIRST consumer (#12 is the next adopter of the same seam).

No seeded-file behaviour changed (the group storage format is unchanged — still bare-name
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

- **`gear/groupscan.lua` — the pure scanner.** `scan(fileText) -> (candidates, notes)`. The
  player's group tables are usually `local`s (invisible to a sandbox-run env), so this is a TEXT
  scan: a `%b{}` walk pulls each top-level `[local] NAME = T?{...}` block (never descending, so a
  gear set's inner `['Idle'] = {...}` is not a top-level hit), evaluates its body in `groupimport`'s
  hardened sandbox, and classifies it — a flat string array → one candidate; a container of flat
  arrays → one candidate per inner key (the `BlueSpells` case); a gear set / settings block →
  skipped with a note. Comments are stripped first so a stray brace can't unbalance the walk;
  candidates are deduped case-insensitively and sorted. Tests **GS0–GS9**.
- **`groupimport` grew two exports** (`membersOf`, `evalTable`) so the flat-list heuristic and the
  safe eval live in ONE place instead of being re-implemented by the scanner.
- **Reads both files.** dlac's profile migration shims the live `<JOB>.lua`, so the real tables
  survive in `backups\pre-profiles\<JOB>.lua` — the scan reads the live file AND the backup and
  concatenates them.
- **The UI (`triggersui.renderGroupAutoImport`).** A `Scan my Lua file` button → a tick-list of
  candidates (name + member count), pre-ticked EXCEPT obvious config tables (`*Variant*`,
  `*Settings*`, `*Table`) so `IdleVariantTable`-style false positives don't import unless chosen,
  plus a dim "skipped N" note for the gear-set/settings blocks. Import reuses the SAME `classify` /
  overwrite-confirm / `apply` (and `applyImportPlan`) as the paste flow.

### Where it lives / what did NOT change

`renderGroupAutoImport` is a `local` in `ui/triggersui.lua` (addon-state; smoke_ui guards the load).
No seeded-file behaviour changed — `groupscan` is never seeded and the `Groups` storage format is
G2's, read by the engine unchanged — so **no `dispatch.M.VERSION` bump**. New player-facing strings
(the control label, `Scan my Lua file`, `Found N tables`, `Import N selected`, the skip notes) are
**proposed for maintainer sign-off** in the PR, not finalized.

## Session "conditional effects design + the night shift" (44212a0..dadd9a8, PR #45) — 2026-07-17

**Theme:** Henrik expanded the latent/set-bonus scope (optimizer + totals now IN), delegated
every open decision, and left the maintainer running overnight ("you are super, go by your
recommendations").

**Landed (day):** direct server-source re-verification of the conditional-effects research
(sparse clone: the gear_sets applier + latent_effect_container.cpp, which the original
research never opened) — found and FIXED the gen_levelscaling latent-id bug (52 is
WEATHER_ELEMENT, 50 is the real under-level latent; shipped data carried 57 weather rows as
bogus below-Lv entries and missed all 9 real ones — `44212a0`). Full design via judge-panel
workflow + source amendments: `docs/design/conditional-effects.md` (`d16449a`; all six
decisions resolved `d938f7c`). PRD #39 → issues #40–#44 (one per phase; #40 dispatched to
the cloud agent, #42 pre-carries agent:max). Generators built — `tools/modmap.py` shared
modId→stat bridge with the x100 scale traps, `gen_gearsets.py`, the latent router inside
`gen_levelscaling.py` (all disk-only; tools/ is gitignored) — and `data/gearsets.lua` +
`data/latentstats.lua` shipped (`4af3e5f`) so the cloud slices are pure addon work. Henrik
live-confirmed the Lava/Kusha de-equip drops ATT + ACC + DEF (the flat-set field check).

**Landed (night):** "Build as lv.75" defaults ON, deliberately session-only (`6577f68`).
Instant Warp scroll tops the Teleports menu — `/dl iw`, usable-item path (no equip/lock/
wait), stack count in the charges column; swept the parallel session's completed Chocobo
Whistle changeset along (`9e1df2e`). Per-set 4x4 build-slot grid replaces "Skip weapons":
the mask rides bindSetWeights (one binding, two payloads) and persists beside the weights
as slotsShared/slotsPerSet; AS1–AS20 (`ad79e61`). Player trigger conditions: hpBelow/
hpAbove, mpBelow/mpAbove (percent), tpBelow/tpAbove (raw TP), buff/buffNot (name or id) —
engine VERSION 53 with a per-dispatch buff cache and PM1–PM21 (`88bb3ba`); editor UI with
number thresholds + a searchable status-effect picker (`dadd9a8`). PR #45 (extras, for
morning review): live `[on now]`/`[off now]` markers on player-gated rules — evaluated by
the ENGINE's own matcher seam, never a re-implementation — and weights "copy from..."
(weights + slot marks together; AW1–AW11).

**Key decisions:** duplicate set pieces count TWICE (verified straight from the applier —
the design draft's "unverified, default once" was flipped); set piece counting is
level-sync-gated server-side and dlac mirrors it; 37 of 126 sets have ALTERNATE pieces
spanning weapon slots (weapon slots feed the optimizer via baseComposition); unreadable
player state matches NEITHER buff polarity (a failed read must never flap gear); the
build-as-75 off-state deliberately does NOT persist; main pushed (9 commits) so the extras
PR reviews cleanly and origin can't diverge under the incoming cloud-agent PRs.

## Session "level-sync settle hold" (after adaab2c, engine v56) — 2026-07-17

**Theme:** Henrik's field report — "in Incursion you are already level synced, then you pop
a boss, a new level sync is in place. That's when I lose TP" — diagnosed and fixed
engine-native.

**Root cause:** the engine trusts a just-changed MainJobSync reading immediately. A sync
landing makes level-driven resolution (virtuals, ladders, `utils.rebuildSets` re-flattens)
name a DIFFERENT Main at the transient level; one `gFunc.EquipSet` later the main weapon
swaps and saved TP zeroes. "Sometimes" = whether a dispatch frame lands inside the
transient window.

**Landed (dispatch.lua v56):** the level-sync settle hold, the ratified stateless-hold
pattern. Pure rule `M.syncSettleStep`: a level jump on the SAME job arms a ~3s hold
(`M.SYNC_SETTLE_S`); job changes and first reads adopt instantly; not-ready readings
(level 0, job '?'/'NON') never touch the tracker (parked on M — survives self-swap
mid-hold). While holding: every dispatch keeps Main/Sub/Range as worn (`ctx.syncHold`, the
pinReserved pattern — sits ABOVE the AutoAcc/virtual branches so markers hold UNRESOLVED),
a Range-reserving stat-stick Ammo holds WITH the Range it reserves (else the server strips
the worn ranged weapon — the ADR 0010 inversion the review caught), and HandleDefault is
gated whole for legacy profiles via `M.defaultGateHold`, consulted AT CALL TIME by a thin
generational wrap shell (`WRAP_GEN` + preserved `_dlacOrigHEE` original) so the gate
hot-swaps live — the old `_dlacPetHold` boolean guard would have left a v55→v56 hot-swap
without the gate until a full Reload LAC. Traced as `SYNC-HOLD` in /dl why. LS1–LS34
headless tests (929 total), including a real drive of the wrap shell over a v55-shaped
pre-wrap.

**Process note:** adversarial review workflow (4 lenses, refutation verify) confirmed 4
real defects in the first draft — trinket/Range inversion, the hot-swap wrap gap, the
tracker reset on self-swap, and mutation-tested coverage holes — all fixed before commit.

**Revision (same day, v57):** settle window 3s → 1s (Henrik: "3 sounds like a long time").
Safe because the window is stability-since-last-change — every flip re-arms it — so 1s only
has to outlast the quiet gap after the final flip. `M.SYNC_SETTLE_S` is the lever if a sync
ever eats TP again.

**Field confirmation (same day):** Henrik tested in Incursion — TP survived the boss pop.
Henrik's framing, adopted: this was a LAC-layer reflex ("LAC is too fast, dlac gives it
leeway"), not a dlac bug; plain-LAC users with level-dependent weapon rules remain exposed
by design. Full write-up with code context: `docs/design/sync-settle-hold.md`.

## Session "second ear starved by the weight ladder" (2026-07-17)

**Field case (Henrik, WHM):** Cure Potency + Cure Potency II weighted 10/pt; owning
Curates' Earring (Lv30) and Roundel Earring (Lv73) produced BOTH as Ear1 candidates
(rungs at 30 and 73) and left Ear2 empty — the pair never wore both, so the Curates'
potency was lost outright. Root cause in `autoBuild` (gearui): dynamic mode built
slot 1's full ladder first (every score-improving item lands there), then barred
slot 2 from everything in slot 1's list — correct for double-equip safety, but it
starves slot 2 whenever each upgrade beats the last. Same defect for rings.

**Fix:** paired slots (Ear1/Ear2, Ring1/Ring2) with both halves masked now ladder as
a PAIR via `gearoptim.pairLadders` — one running TOP-2 walk over the level-sorted
candidates; each upgrade lands in whichever chain holds the weaker top, so the two
flattens together wear the best two distinct pieces at EVERY level, with disjoint
chains by construction (no double-equip). Owned counts pass through: an Id owned 2+
may fill both slots. The joint optimizer's picks arrive as `pins` — a pin already
topping a chain claims it untouched (ears are interchangeable, matched as a set);
a leftover pin trims an unclaimed chain like the single-slot ladder cap and is
stripped from the other chain (single copy) to keep the pair disjoint. The old
block-filter remains for pairs whose partner is NOT being rebuilt (unmasked half,
non-dynamic modes). Also fixed en route: unmasked slots are preserved BEFORE the
build loop, so a rebuilt Ear2 sees a hand-pinned Ear1 regardless of slot order.
PL1–PL13 headless tests (942 total); pairLadders is pure — scores computed by the
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
an ordered stat list — top matters most — with an optional cap per row, up/down
reorder, and the same copy from.../save as... verbs against its OWN stores
("Saved Lists" + per-set lists; a point template and a priority list never
cross-load, per Henrik). Both tabs carry a **clear** button to the right of
"save as..."; clear snapshots first, so copy from... > revert undoes a mis-click.

**Implementation ruling:** priority scoring is dominance-DERIVED point weights
(bottom-up, one point of a higher rank outranks everything below it combined;
uncapped stats assumed ≤500 set-total), resolved behind `activeWeights()` — so
score/optimizePicks/pairLadders/Auto-build run untouched. Which mode builds a
set is per-binding state flipped by whichever editor's data you MUTATE — looking
at a tab never switches it (a banner on the inactive tab says which one builds).

**Bug fixed en route (Henrik):** new sets no longer seed their weights from the
shared table — that seeding is why every new set arrived with a mystery "STR 5"
(leftovers in his shared table). New bindings start BLANK for weights AND
priority lists; only the build-slot mask still seeds from shared (a blank mask
would read as a dead Auto-build button). Empty per-set tables are no longer
persisted or offered as copy sources. AE4/AE6 rewritten to pin the new ruling;
AP1–AP38 cover the priority mode (980 checks total).

**Round 3 (same day): the shared table is deleted.** Henrik asked what "shared
weights" even were; on hearing it (the pre-per-set single table, kept as the
no-set fallback / new-set seed / legacy-file landing spot) he ruled it a dead
concept — "we start blank, have weights per set and can save. Delete it."
Implementation: unbound, the actives alias read-only EMPTY sentinels; every
mutator (weights, priority, masks, copies, saves, modes) refuses with 'no set
selected'; the weights panel and `/dl weight` say "pick a set" instead of
editing a phantom table; the "(shared weights)"/"(shared list)" copy rows are
gone; build-slot masks seed from the fixed default. Persistence no longer
writes `shared`/`slotsShared`/`prioShared`/`mode`, and the loader DROPS those
sections from older files (pre-per-set flat files — which were only a shared
table — load as nothing). Also folded in: an x with a red second-click confirm
on every Saved Sets / Saved Lists row in the copy-from menus, so "save as..."
templates can finally be deleted. AE/AS/AW/AP rewritten for the unbound
semantics (987 checks).

## Session "HELM gear automation" (2026-07-17, engine v59, docs/design/helm-gear.md)

**Feature: the craft-gear system's gathering twin** for Harvesting / Excavation
/ Logging / Mining (fishing excluded on purpose — it gets its own automation
someday). Research fanned out three ways before a line was written: the dlac
craftgear map (the template), the trove + ventures addons (the 0x1A4 protocol),
and the public server fork + wiki (mechanics, IDs, prices).

**What research settled:**
- The catalog already carries machine-readable `Stats.HELM` and
  `Stats.Surveyor` — HELM ladders are stat-driven exactly like craft skill
  ladders. All item IDs verified catalog-vs-server-SQL (design doc table).
- **The "+5 removes breakage" math decoded**: every field/plain piece carries a
  +73 result mod = +7.3 on the break roll (`hobbies/helm/logic.lua`: break if
  `rand(1,100)+mod/10 <= 33`) — five pieces → min 37.5 → unbreakable. This also
  explains server-questions §2's mystery flat 73. Excavation's result mod
  (2006) is private-module-added and stays breakable — As Square Enix Intended.
- **Venture points**: no retail packet — but trove's custom 0x1A4
  request/response streams a server-authoritative Points list (group/label/
  value; DVP arrives as group `Ventures`). helmwatch speaks the protocol
  itself (GET_POINTS=8 / POINTS_ENTRY=7); whether the four HELM pools ride the
  stream is field-test #1 (`/dl helm points` dumps everything).
- **`!ventures` reply format is unknowable from source** (private submodules:
  modules/catseyexi, cexi-src — all 404). helmwatch watches outgoing 0x0B5 for
  a typed `!ventures`, opens a 6s capture on incoming 0x017, mirrors raw lines
  to `helmventures_capture.txt` (the data that will pin the real regexes) and
  keyword-buckets them per category for display meanwhile.
- **Category auto-detection is NOT a dead end** (Henrik suspected it was): the
  point NPCs are literally named `Mining Point` etc. — outgoing trade 0x036
  target index → entity name → category; with the bar ON the hat auto-follows.
- 0x1A3 (the `ventures` addon's packet) is the venture-NM daily rotation, NOT
  HELM — a different system wearing the same name.

**What shipped:** `feature/helmwatch.lua` (state owner: helmstate/venturepoints/
helmventures mirrors, 0x1A4 + 0x017 + 0x036 + 0x0B5 glue, `/dl helm`),
`ui/helmui.lua` (the Automations panel: Henrik's four-column progression matrix
— Field / Plain / Plain +1 / Hats — with the "you're awesome" green cascade
(better piece greens its ancestors) and a holy-light backlight on owned
top-tier pieces; category tabs with the new gold glyphs; VP + today's ventures
per tab), `ui/helmbar.lua` (floating bar: four glyphs + pill + VP/rating/
Surveyor status line), engine v59 (`dlac:AutoHelm`, helmstate read gated to
Default — IDLE-ONLY is the feature — armor+neck+waist only, never weapons;
craft-vs-helm both-on arbitration by newer `at` stamp), manifest fmtver 7
(helm ladders Surveyor-major + owned-hat map). Icons: Henrik's four SVGs
rasterized to `assets/helm/*.png` at the craft-glyph spec (40×40 alpha).
En route: helmOverlayFor passes ctx.player through to the ladder level gate —
the craft overlay's inner ctx drops it (harmless there, Lv65 Field Torque/Rope
would flap here). H1–H36 cover state rules, wire parsers, overlay resolution,
rating math (1023 checks).

**Field tests pending (dlacprobe / live):** §7 of the design doc — the 0x1A4
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
not gated (safe-zone activity). 1065 + 123 checks green; all §7 field tests closed
same-day.

## Session "virtual markers get a ladder level" (2026-07-17, engine v62)

Henrik's field report on his leveling Mindie WHM: the Sets tab showed
`dlac:AutoIridescence` as the Main pick "at level 0" while the character
actually wears Pilgrim's Wand — the marker was a Lv0 wildcard that shadowed
the real weapon ladder everywhere below the level of any owned iridescence
staff. His ruling: **a marker's level is the level of the item it resolves
to** (for him Chatoyant Staff, Lv51).

Implemented as `M.virtualMinLevel(marker)` (dispatch, v62): the LOWEST level
among the manifest items the marker can resolve to — AutoStaff/AutoIridescence
scan `universal` + per-element `staff`, AutoObi scans `obi` + `obiUniversal`;
craft/helm/acc families and legacy name-only shapes return nil ("no answer").
Consumers, all nil-safe (nil keeps the old always-adopt behavior, so the rule
can only ever REMOVE a marker that cannot resolve):

- **BuildDynamicSets** skips a virtual whose min level is above the main level
  — the flattened set then shows the real best-by-level item outright instead
  of `marker|fallback` (the engine's equip-time fallback made this invisible
  on the wire; the FLATTENED SET was what lied).
- **gearui resolveSetItem** stamps the derived level on virtual records
  (Lv51 in the ladder rows instead of 0), and **bestByLevel**'s
  virtual-takes-the-slot short-circuit now honours it, so the "current pick"
  highlight mirrors the new flatten exactly.

Tests VL1–VL7 (min-level derivation incl. the `marker|fallback` composite
form, flatten below/at the rung, legacy-manifest passthrough). 1078 + 125
green. Note: utils.lua changed too — a **Reload LAC** is needed for the
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

## Session "set bonuses land — display + optimizer" (2026-07-18)

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

**Feature: the third sibling** — Auto Fish Set beside Auto Craft Set and Auto HELM
Set (Henrik: "I am NOT out to automate fishing, I just want to streamline the
experience"). Research fanned out three ways before a line was written: the dlac
HELM/craft map (the template), the CatsEyeXI server source on GitHub (mechanics),
and the local catalog/api_cache (items).

**What research settled:**
- **Fishing on CatsEyeXI is stock-LSB C++** (`src/map/utils/fishingutils.cpp`,
  3,242 lines, an older snapshot: chart quests stripped, chest catching commented
  out) driven by public SQL — no hobbies/fishing dir, no Lua fishing scripts. The
  catch pools (zone+area → group → fish, gated HARD by `fishing_bait_affinity`:
  no row = that fish can never bite that bait) and the three reel-in fail rolls
  (lose :719 / line snap :784 / rod break :828) are all public, formula-exact.
  That makes **bait isolation** ("which bait+zone makes ONLY my fish bite")
  and **rod safety verdicts** computable offline — the two flagship asks.
- **The private overlay provably adds content on top**: custom mods 2004/2005
  (carriers: Ebisu =10, Ebisu +1 =15, Halieutica =50/5, Mariners pieces,
  Brigands Eyepatch; semantics NOT public — server-questions.md §4 stays open,
  the addon uses them as ladder tiebreakers only). **Halieutica 20945 is a
  Main-slot fishing weapon** (polearm-skill spear, Fish+2), not a rod. **The
  Mariners set is fishing's VP tier** — its ids interleave HELM's Plain block
  (25899/900, 25966/67, 25986/87, 26535/36 + Brigands Eyepatch 28443 as the
  hat analog).
- **Fishing VP was already streaming**: helmwatch's 0x1A4 parse stores every
  group/label and the field capture had confirmed a `Fishing` label back on
  07-17 — `pointsFor('Fishing')` worked before this session started. **Fishing
  guild GP sits at 0x113 offset 0x20**, one map entry away from craftwatch's
  GP_OFFSET (a run_tests fixture had it labeled "ignored" since the craft arc).
- Skill is `GetCraftSkill(0)` — the index craftwatch's map deliberately
  skipped. Effective skill = display skill + worn Mod::FISH; cap = (guild
  rank+1)×10, rank-ups at Thubu Parohren (Port Windurst), Expert = 110. Lu
  Shang's 10k-carp quest pair is active in public scripts; Ebisu acquisition is
  private.

**What shipped:** `tools/gen_fishdb.py` (fetches the nine fishing SQL tables,
CREATE TABLE-driven parsing, scans api_cache for mods 127/2004/2005) →
`data/fishdb.lua` (128 fish, 39 baits, 575 affinities, 20 rods, 95 zone pools,
259 fishable mobs, guild tables, gearBonus supplement; ~70 KB).
`feature/fishcalc.lua` — PURE math: the three fail formulas ported VERBATIM
(including the uint8 wrap on tooBig's over-skill rebate and tooSmall's guarded
subtraction — F11/F12 pin both), rod ranking, live isolation derivation,
mob-bite risk, search. `feature/fishwatch.lua` — state owner (fishstate.lua:
enabled session-only, target/rod/bait persist as CLIENT names), rod/bait
auto-pick + ~2s bag heartbeat re-pick (bait runs dry → next owned bait + chat
line), fishing-only !ventures 0x017 capture (format UNPINNED — raw mirror to
fishventures_capture.txt), `/dl fish` commands. `ui/fishui.lua` — the panel:
status line (skill/GP/VP), 4-column gear matrix (BASE / ANGLER'S / GUILD GP /
MARINERS VP + Halieutica), rod columns (standard/legendary), target-fish search
with ISOLATION-first spot×bait rows (mob ⚠, "items can always bite" footnote),
rod verdicts from the real math, per-container bait census, ventures, guild
corner; coverage/status sit ABOVE the imgui guard (headless-testable — helmui
improvement). `ui/fishbar.lua` — pill + target + rod/bait item icons (zero new
assets). Engine v64: `ensureFishState`/`fishOverlayFor` (Default-only,
Engaged/Dead stand-aside; Range/Ammo straight from state, armor + Main via the
manifest `fish` ladders — Main included on the CRAFT precedent because of
Halieutica), `dlac:AutoFish` in resolveVirtual, **three-way at-stamp
arbitration** (ties keep the older system: craft > helm > fish). triggersui:
AUTO_FMT 7→8 (fish ladders: FishingSkill-major, cx tiebreak, disjoint rings),
fifth Automations row + fishui delegation. craftwatch: GP_OFFSET gains
`Fishing = 0x20`.

**Tests:** F1-F69 (hand-derived server-math cases — the expectations carry a
"re-derive from the C++ before editing" warning — fishdb integrity, pick rules
incl. the Yew-over-Willow least-risk case, overlay resolution, GP 0x20) +
smoke S130-134 (headless loads; fishui.status callable without imgui).
1231 + 130 green. NOTE: the F-section itself rode into cd2381c via the
parallel session's staging — harmless overlap, this commit brings the modules
it exercises.

**Deliberately NOT done:** any automation of fishing (no casting, no 0x115
mini-game reads, no bite reactions — the server carries an anti-bot surface,
`GetRecentFishers()`/`[Fish]LastCastTime`, and the bright line stays bright).
Field tests pending: design doc §6 — `!ventures fishing` format pin, GP/VP
sanity, first live overlay run, custom-gear stat text.

**Field round 1 (same day, Henrik live):** the panel worked on contact — his
screenshot shows Lu Shang's SAFE verdicts and Giant Donko isolation rows.
Five fixes from the pass, plus one identification that closed a server
question: **the bg-wiki CatsEyeXI Ventures page lists "Expert Angler:
Fatigue Limit +10%, Golden Arrow Rate +1%" on Mariners Tunica/Boots — values
matching mods 2004/2005 in the live DB exactly (10/20 base/+1, 1/2), so
2004 = Fatigue Limit +%, 2005 = Golden Arrow Rate +%** (server-questions §4:
two of the three unknowns answered; 2017 remains). Panel rulings: glow is
MARINERS-ONLY (the real fishing end-game — Angler's/guild gear just green;
Expert Angler tooltips on the carrying pieces); Lu Shang's +1 / Ebisu +1 /
Halieutica / Brigands Eyepatch UNDISPLAYED (unmentioned in-game, look
unobtainable — data stays, autoPick honours an owned one); owning Lu
Shang's/Ebisu greens the whole standard rod ladder (the cascade); the buy
suggestion only appears when no owned rod is SAFE (and never suggests the
+1s); [ISOLATED] column widened 90→128 (themed-font clipping, the
button-width lesson again); the 10k-carp guild line hides once Lu Shang's is
owned. itemLine also inherited helmui's note-beats-tooltip order en route —
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

## Session "architecture review → refactor/deepening" (2026-07-18/19)

**Theme:** /improve-codebase-architecture over the whole addon (four explorer
walks: engine, GUI, gear data, test surface), then Henrik: *"You are the
maintainer, do it all, but keep it in a separate branch where we test each
step."* Eight deepening steps landed on `refactor/deepening`, one commit each,
suite-gated (1355 → 1508 headless checks + 170 smoke); engine v68 → v71.

**Landed (in order):**
1. `gear\triggermodel.lua` — the Triggers tab's raw→edit-model translation,
   pure (canonEvent injected, groupsmodel pattern). THE wipe contract (Commit
   serializes the whole model; an uncarried section is erased — shipped once)
   finally test-pinned: TM1-19.
2. `gear\gearrecord.lua` — the Owned-gear record rules in one home: canonType/
   healType (legacy-spelling heal), subTypeFromName, effectiveRSlot (ADR 0010),
   enrich/mergedStats precedence. Five stamp sites delegate; REC0-26 include a
   vocabulary-closure check (every filter bucket key canonizes to itself).
   Deliberate alignment: gearexport now heals drifted Types like the GUI.
3. `lib\safewrite.lua` — backup/tmp/validate/rename/restore written once
   (gearimport carried it twice, near-copies); profiles' deleters ride
   verifiedMove and REFUSE when the net is missing. setmanager's rotated
   policy deliberately stays its own (one adapter = hypothetical seam). SW0-14.
4. `gear\catalogindex.lua` — the one catalog walker: lazy load, rawIndex/
   rawById, flat browse copies, the generic flatten (gearui's flattenGear is a
   delegate; owned gear flattens through the same code). Engine still never
   loads the catalog. CI0-12.
5. ownedcache deepened (no parallel module — it already IS the ADR 0005 home):
   verdict(rec, usable) with stored>locked>ok precedence + whereText caption
   builder + _splitOverride = its first test reach ever (AV1-13). Noted, not
   changed: automationsui lights an owned-but-STORED staff green.
6. **v69** — obi + Oneiros decisions extracted pure (resolveObi /
   resolveOneiros, the resolveStaff shape); the two field-calibrated gates
   pinned headless (VG1-15, incl. the Mindie 714→357-inclusive boundary
   verbatim).
7. **v70** — the statefile seam: ensureStateFile behind the auto/acc/craft/
   helm/fish/pin caches (six near-identical clones that had DRIFTED); corrupt-
   write policy unified on pin's v44 DROP — craft/helm/fish/auto used to keep
   stale state glued on forever after a torn write. _charDirOverride runs the
   file-driven surface headless (SF0-9). Then `lib\statefile.lua` = the one
   addon-side charDir (four watcher copies deleted); watcher write sites
   deliberately untouched (3-line dances, churn > depth).
8. **v71** — equipResolved: the five whole-table post-passes are named entries
   run in M._postPassOrder (trinket-BEFORE-reserved is checkable adjacency,
   PL1-3); the per-slot chain keeps its elseif precedence, now named; copy-on-
   write + note built once. The review card's "11 uniform passes" sketch was
   wrong about the shape — the per-slot chain is correct as-is and stayed.

**Key decisions:** candidate 9 (watch-bar chassis) NOT built — its own deletion
test failed (deleting fishbar deletes a feature, not a coupling); revisit if a
fourth gear-system twin lands. The one deliberate behavior change on the
branch: statefile corrupt policy = DROP everywhere (+ gearexport's Type heal);
everything else bit-identical by test.

**Standing:** branch `refactor/deepening`, 10 commits, unmerged. Field-test the
engine steps (the Reload LAC banner will prompt — v71), then merge to main.
names; the +1 sets even mix "Marduks Jubbah +1" with "Mdk. Dastanas +1"), so
the all-pieces word-prefix never matched. setLabelOf rebuilt: majority
first-word family via a drift-tolerant stem (lowercase, punctuation out,
trailing s off), word-extension within the family ("Iron Ram set"), shared
quality mark kept visible ("Ares +1 set" distinct from base "Ares set"),
"+N" form deleted outright; fallback "N-piece set". setLabelOf exported as a
uihost service; smoke S41-S44 pin Ares/Ares+1/Mdk.+1 against the REAL catalog
plus a sweep: every one of the 126 labels is a pair or "... set", never an
HQ-item shape. 1234 + 135 green.

## Session "automationsui extraction — the migration completed" (2026-07-18, overnight)

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
dropped rather than carried. triggersui 3713 → 2609 lines, 30 top-level locals
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
