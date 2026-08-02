--[[
    dlac/dispatch.lua — the trigger dispatch engine.
    Design: docs/design/trigger-system.md  (ADR 0002 data-driven dispatch,
    ADR 0003 overlay semantics, ADR 0004 automations land here in M2).

    Runs inside LuaAshitacast's Lua state: profiles call utils.dispatch('<Handler>')
    as the LAST line of each Handle* function, and this module reads the per-job
    trigger data file, matches the live action/player against each rule's `when`,
    and EquipSets every match in ascending priority (later overlays earlier per slot).

    Trigger file:  <char>\dlac\profiles\<active>\triggers\<JOB>.lua, falling back
    to the legacy <char>\dlac\triggers\<JOB>.lua   (a `return {...}` module)
        <Handler> = { { when = { <conditions> }, set = 'SetName' | equip = { Waist = 'Karin Obi' },
                        priority = <optional> }, ... }
    Hot-reloaded: the file is re-checked at most once per second (content compare),
    so a GUI commit or hand edit applies on the next action — no /lac reload.

    The dlac ADDON's Lua state also requires this module (through utils); there it is
    inert — no gFunc means no command handler, no mode state, and dispatch() no-ops.

    Commands (LAC state only; prefix /dl or /dlac):
        /dl mode <name> [on|off|toggle]   flip a mode flag (session-only; no args lists)
        /dl why                            trace of the last dispatch per handler
        /dl triggers reload|init|path      force re-read / seed a starter file / show path
        /dl sets reload                    hot-swap the committed sets (no LAC reload)
        /dl profile [use|new|clone|migrate]  the profile storage layer (profiles.lua)

    Every gData / gFunc / io read is pcall-guarded: a broken trigger file or a nil
    manager can never take down a cast or profile loading (it just no-ops + reports).
]]--

-- (The __dlacEngineRoot hot-swap handshake lived here until the purge, Phase 1
-- -- it let the LAC-state self-swap re-execute this file into the same module
-- table. The self-swap died with the seeder; a plain require owns the table.)
local M = {};

-- LAC-LOAD generation stamp: `or` keeps it across engine SELF-swaps (same module
-- table, same Lua state) but a Reload LAC builds a fresh state -> fresh stamp.
-- Mirrored into modestate.lua, it is exactly the "has LAC actually been
-- reloaded?" signal the GUI's red Reload-LAC button watches -- including
-- reloads the user runs by command. (os.clock() disambiguates two loads
-- inside the same os.time() second.)
M._loadStamp = M._loadStamp or string.format('%d:%.3f', os.time(), os.clock());

-- Engine version handshake: bump on EVERY behavioral change to this file. The
-- LAC-state copy stamps its version into the modestate mirror; the GUI compares
-- against the addon-state copy and shows "Reload LAC" when LAC is running stale
-- code. From v32 the engine self-swaps when the seeded file's version moves, so
-- the banner should only persist when a swap FAILED (or pre-v32 code is live).
M.VERSION = 163;  -- 163: A RECORD'S CONTEST EXPLAINS THAT RECORD'S PLAN (field report 3, 2026-08-02). The structured contest was built ONLY on a retrace and reused from the previous trace otherwise -- and the retrace signature covers matched rules, locks, claim legs, the sets revision and the rank order, but NOT the player's LEVEL. So levelling changes which candidates a set resolves to while the signature holds: the plan moves, the explanation does not, and the decision ring appends a record whose two halves disagree about who decided a slot. Henrik's report showed both symptoms at once -- Ear1 carrying Optical Earring in the plan with the contest naming nobody for the slot (Lv10 gear, crossed 9 -> 10 mid-window), and the claimant then arriving TWO DISPATCHES LATER as a record with zero changed slots, which is what produced six empty blocks in the previous report. Fixed in two places: slotSrc/floorTbl are collected on EVERY pass (they shared one `if retrace` with the /dl why LINE FORMATTING, which is the half that actually costs a string.format per rule; filling two small tables is nothing beside the equipSetByName that already ran), and the contest is re-explained when M._planOutrunsContest says the plan named a slot the explanation cannot account for, or swapped the item inside one it covers. The test is deliberately ONE-WAY: a contest naming MORE than the plan is ordinary and must not rebuild -- a lock or the level-sync weapon hold takes a slot out of the plan while the claim on it stands, which is two questions answered correctly, not staleness (field: Main/Sub leaving the plan across the same level-up while Triggers still claimed them). Sentinels, 'remove' and the LOCK_HELD sentinel are exempt from the item half: a claim that defends or empties a slot never claimed to name the worn item. Tests PO1-PO13, and PO8 asserts the invariant over every record the suite's real dispatches build. Reading a report is what found this -- an artifact nobody reads is an artifact nobody has tested.
                  -- 162: EXTERNAL CLAIMS -- the write half of the Integration surface (feature\extclaim, docs\reference\integration-guide.md section 7). A SEPARATE ADDON, in its own Lua state and not a dlac module, files a Claim over Ashita's plugin_event bus and the Arbiter settles it like any other claimant. The whole feature is one sentence -- an external claim is an ordinary Claim that happened to arrive over the wire -- and the size of the change is the evidence: one rank row ('External', shipped directly above the Triggers floor, which is the rank the plugin design already ruled for a third party), one CLAIMANTS row, one signature leg, one mailbox module. Everything a player expects (contested slots, the Locks veto, the Disabled ceiling, /dl why attribution, the Arbiter Monitor, the Claim Priority drag) falls out of the registry for free -- ADR 0012's promise, collected. THE THREE LAWS THAT ARE NEW, because everything else is inherited: (1) PUSH, NEVER PULL -- dlac asks nobody anything mid-decision and waits for nobody; a claim is a standing table read from cache like AutoAmmo's, so a third party's Lua is never on the equip path and its crash cannot become dlac's gear bug (the one-directional dependency ruling, kept literal). The cost, stated: a REACTIVE external claim is one action late. (2) EVERY CLAIM IS A LEASE -- every in-state claimant dies when dlac dies and an external one does not, so a claim carries a TTL (10s default, 300 max) and must be renewed; an addon that crashes or forgets must not leave gear stuck with nobody to blame. Not a permission wall -- the holder can VANISH, which is a different problem from the holder misbehaving. (3) CLAIM, NEVER COMMIT -- session-only, no writer for sets/triggers/modes/lockstyle, unchanged from the existing ruling. The switch is /dl claims (+ a Menu > Settings row), a SIBLING of /dl stream and deliberately not the same one: reading your gear and dressing you are different consents, and a misbehaving claimant has to be killable without also killing a parser's feed. The trap worth naming for whoever adds the next claimant of any kind: the CLAIMANT_SIG_ORDER leg. A claim that changes without moving the retrace signature never re-dispatches -- it sits in the mailbox looking accepted, reaches no slot, and the failure is invisible from both sides of the wire (test EX16f exists to fail loudly instead). Tests EX1-EX16.
                  -- 161: ONE ANSWER PER SLOT -- the rendering contract, stated (docs/design/two-way-arbiter.md §11). Henrik's screenshot of the v159 pair verdict: `/dl why range` printed BOTH "nobody claimed it (kept as worn)." AND "held EMPTY: Arcane Arbalest and Cinderstone cannot coexist -- kept Cinderstone, the higher Level." -- two sentences disagreeing about one slot, and "kept as worn" is the weaker truth besides (when a stat stick holds Range the SERVER empties it; the slot is not merely unwritten). The no-contest line is NOT a verdict -- it is what a renderer says when the contest was EMPTY -- and a slot the arbitration REFUSED has an empty contest BY CONSTRUCTION, because the refused piece never reaches floorTbl/arbExplain, so `ops` comes back nil. The first four verdict channels (rep / fall.dead / inel / sup) never exposed this because each only ever fires on a slot that HAD a contest; the pair verdict is the first that can fire on a slot nothing claimed. arbiter.slotVerdict is now the ONE walk -- rep -> dead -> ineligible -> reserved -> pair, most specific refusal first -- that every renderer asks before falling back to the no-contest line, so /dl why, the Monitor cell and the Monitor hover cannot drift apart about which channel speaks. §11 writes down the whole contract for the sixth channel: add it to slotVerdict in order, give it its OWN sentence (never fold a new verdict into an existing one because the consequence matches -- the pair law is not "reserved"), name which leg answered when it has several, update all three renderers, and make sure a suppressing pass cannot double-report. Tests RV1-RV9.
                  -- 128: 128: AutoAmmo asks what is in RANGE before it picks (field, Henrik 2026-07-26: "AutoAmmo does NOT dictate if it's bolt, arrows or what not that gets equipped. That is 100% decided on what gets put in ranged"). resolveAmmoPlan was type-BLIND -- it took the first `ranged`-flagged entry with stock, so a bolt above your arrows won with a bow equipped -- and the panel's Bullets/Bolts/Arrows selector never constrained it (categoryOf is a VIEW, stored nowhere). The cost was not a wasted swap: charutils.cpp EquipItem STRIPS THE OTHER SLOT on an incompatible Range/Ammo pair, so the bolt took the bow off, the trigger re-equipped it, and the two flapped forever -- ADR 0010's failure through the skill/subskill door instead of the rslot one. New pure M.pairsWith over a "<skill>:<subskill>" key (26:1 gun/bullet, 26:0 crossbow/bolt, 26:2 culverin/shell, 27:0 boomerang/pebble, 27:3 shuriken, 0:10 Animator/oil), three-valued so an unknown pair degrades to today's behaviour instead of switching AutoAmmo off; ARCHERY is exempt from the subskill half exactly as the server writes it (Shortbow 25:0 and Longbow 25:4 share arrows). Range is never written -- AutoAmmo only ever READS it. Two rulings, both Henrik's: no ranged weapon worn = do nothing at all (safe -- with Range empty the server refuses the shot, so nothing can be consumed), and a weapon worn with nothing in the list able to pair = hold, never force a mismatch in. THROWING with an empty Range (a NIN's shuriken, CanUseRangedAttack's `|| PAmmo->isThrowing()`) is the ONE known exception and stays parked behind the §8 NIN field tests. The key rides the manifest like RSlot (gearimport stamps Pair from the catalog's new field); worn Range falls back to the client resource's Skill when the manifest predates it, so the update alone separates bow/gun/throwing for everyone and a manifest refresh upgrades it to gun-vs-crossbow. Tests PW1-PW14, AM40-AM58.
                  -- 127: trigger CASES, the schema backbone (issue #126, slice 2/5; ADR 0023) -- rules gain an optional `cases` list (a second `&`/`|` tier: op + the same two legs a body has), evaluated by matches()/matchedCase() over a factored legMatches so both tiers share one code path; normalize validates + drops empty cases + strips the always-true `hasCases` version guard; auto-priority + ruleLabel span every leg of every case (case-LESS rules match/label/serialize byte-for-byte as before -- pinned). serializeTriggers is oldest-form-first (a `| case` of only `&` rows -> a whenAny multi-entry; only `&` cases and `| cases` with internal OR use the new list) and stamps the guard so OLDER engines drop the rule with the standard warn instead of misreading it. Seeded-file bump: normalize + matches run engine-side (hard rule 4). Tests CX1-CX35, MC19-23. (PR #132 shipped as v126/2026.07.26c off a pre-97f1edc dev; renumbered at merge.)
                  -- 126: the /dl why trace can no longer outlive the sets store it described (field, Mindie 2026-07-26 01:31): the retrace sig now carries the store REVISION (M.modesRev -- bumped by every install and re-flatten, 5668/5714), so lines built against the empty boot-window store ("[NOT FOUND in profile Sets]", true for ~2s of designed install refusals) die the moment the install lands, instead of printing with a fresh timestamp for the rest of the session while equips worked fine. The v118 law applied to the trace: THE INSTALL INVALIDATES THE BELIEF. Display only, no equip change. Tests TRC0-TRC3 (the trace-vs-store contract, driven through the real command handler + dispatch like CMD).
                  -- 125: trigger CASES, read-side (issue #125, slice 1/5) -- /dl why now NAMES the matched case of a case-bearing rule ('[via together-block]' / '[via standalone ...]' / '[via case a & b]'), mirroring matches() with the engine's own MATCHERS. Display only: a case-less rule (no `|` leg) traces byte-for-byte as before, so this is invisible to the 99%. Seeded-file bump because the trace is built engine-side during dispatch (hard rule 4). No schema change, no equip change. Tests CS1-CS10 (the PR shipped these as MC1-MC10 off a stale origin/dev; renamed at merge -- the dead-mode sweep suite owns the MC range, and 123/124 were taken by the lock-lifetime work).
                  -- 124: ONE LIFETIME RULE for every way of deliberately holding gear still (Henrik, 2026-07-26: "I don't want locks to outlive a relog, it should not outlive a main job change nor a log"). M.nakedWorldWatch is now M.worldWatch (old name kept as an alias -- the seeded LAC-side engine and NK28 call it) and clears SLOT LOCKS as well as the strip and a locked set: main job change, or the character-select read. Slot locks were the odd one out only by accident -- nothing ever watched them, so they rode through character select (an Ashita addon survives a logout and LAC never clears package.loaded), and the pre-v123 self-swap wipe LOOKED like a lifetime rule while really being a bug (a git pull unlocking your gear mid-Incursion). Fixing that accident left the real gap plain. None of the three is written to disk: all are mirrored to modestate (__locks / __naked / __held) inside the reserved __ namespace loadModeState skips, so a mirror can never restore one. The job-change drop is announced per kind; leaving the world stays silent. Tests LS14k-LS14s.
                  -- 123: `/dl lock set ...` is a FROZEN CLAIM on the Locks row (ADR 0022), not equip-once-then-lock-16-slots. The old command was broken in NATIVE mode and could not be seen: its rawget(_G,'gEquip') bracket is nil in the addon state, so the resolved set fell to the unbracketed path, landed in equipengine's buffer, and the next fireEvent's bufferClear wiped it -- then setLock('all', true) locked all 16 slots onto whatever you were wearing and printed success. As a Claim there is no command-path equip left to bracket wrongly: M.dispatch is already bracketed by the native engine, and the claim re-applies every dispatch so anything the server refused heals on the next pass (ADR 0021 rule 3). FOUR command words, ONE claim shape, differing only in what fills a slot the set does not name: /dl lock set (held EMPTY), set-loose (left available), set-snapshot (held as worn), set-current (all 16 as worn, no set name). M.buildLockedClaim is the pure builder; the three impure seams (resolve/locate/wornOf) are injected, so every branch is driven headless. FROZEN AT ARM: dlac: markers are collapsed to concrete entries once, so a locked obi cannot follow the weather -- but the names are re-LOCATED in your bags every dispatch, because freezing container+index would strand the hold on the first bag shuffle. A named piece that is not on you leaves THAT SLOT LOOSE (available) rather than empty, and is reported by name and container from a live all-bags scan. It rides the EXISTING Locks row -- no new rank row, no new player concept -- so precedence is unchanged: Naked and Pins punch through a lock, nothing else does. Arming no longer clears the player's own locks: layerRespectsLocks('Locks') is false on its own row, so the hold punches through M.locks and a stale lock can never strip a slot out of it. Both dispatch bail guards now let a lone hold through (the NK26 lesson). Lifetime shares nakedWorldWatch -- self-swap survives, job change and logout drop it, never written to disk. Released by /dl lock all off AND /dl lock set off; /dl lock with no arguments prints state plus every variant. Mirrored to modestate as __held. Sets tab's Equip & Lock is now a plain action (nothing locks 16 slots, so its toggle had no counter left); the Equipped tab owns the state and the set-current switch. Tests LS1-LS20, CMD10-CMD15, LSU1-LSU4.
                  -- 122: /dl naked + /dl dress (ADR 0021) -- the strip is a CLAIM, not a lock. A new 'Naked' Arbiter row, FIRST by default, claims all 16 slots with the 'remove' literal both engines already speak (LAC MakeItemTable -> Index 0; equipcore normalizeEntry/planSet), so it is recomputed and re-applied on EVERY dispatch instead of stripping once and fencing: nothing re-dresses you, and a strip the server refuses (dead, cutscene, mid-ranged-attack, level-sync settle) lands on the next pass instead of leaking a dressed slot forever. Explicitly NOT the /dl lock route -- a lock only WITHHOLDS (it cannot take a piece off), it is wiped by every engine self-swap, Pins punch through it, and three unrelated buttons release it; arming it would also destroy the player's own locks. Total nudity is the default and the rank list is the exception mechanism: drag Pins or Locks above Naked for "naked except those". Flag is M.nakedArmed, carried across a self-swap by the M._loadStamp idiom and gone in a fresh Lua state, so a git pull cannot re-dress you. A relog does NOT make a fresh Lua state (an Ashita addon survives a logout -- pinwatch's header records it -- and LAC never clears package.loaded), so nakedWorldWatch disarms on the character-select read, and on a JOB CHANGE too (Henrik's ruling; main job only, announced); mirrored to modestate as __naked (display only, never restored). arbOrder now restores a MISSING known row AT ITS DEFAULT POSITION instead of appending -- appended, Naked would have shipped at rank 9 for every character with an existing arbstate file and lost every slot it exists to win. The naked layer voids ctx.pinReserved when it outranks Pins (a reserver about to be stripped must not keep a neighbour dressed) via save/nil/restore, never a ctx copy. /dl ls apply is refused while naked (unnamed slots would be styled permanently EMPTY). Tests NK1-NK26, NKU1-NKU4.
                  -- 121: weatherMatch trigger condition (feature/weather-match-condition, grill-with-docs 07-24) -- a spell-handler flag, true when the CURRENT weather's element equals the action's element. weatherMatchesAction reads the SAME gData.GetEnvironment().WeatherElement the obi uses (storm-aware: a Scholar's own Firestorm etc. overrides zone weather, so it counts). DISTINCT from dayWeatherBonus (the signed day+weather net with opposition): weatherMatch is a plain weather-element equality -- no day, no opposition -- verified as CatsEyeXI's ALACRITY_CELERITY_EFFECT (Celerity/Alacrity cast-time) gate. Precast+Midcast, tier 30, true/false polarity; unreadable weather or no action element matches NEITHER (never fires blind). Tests WM1-WM21.
                  -- 120: Chocobo riding-gear automation (issue #95, docs/design/chocobo-gear.md) -- a fourth idle-only sibling: ensureChocoState/chocoStateActive/chocoOverlayFor, the dlac:AutoChoco resolveVirtual branch (manifest `choco` per-slot best-first ladders, Main/Neck/Body/Hands/Legs/Feet, scored by ChocoboRidingTime, the Chocobo Wand included in Main), a 'Chocobo' Arbiter claim row (default rank below Fishing, above the Triggers floor), and arbOrder now pins the Triggers floor last so a new claimant appended to an existing arbstate file never sinks below it.
                  -- 119: field-CONFIRMED close of the maxmp boot saga (Henrik's trace showed the designed boot: 12 install refusals holding the door ~4.5s of hollow flattens, then the REAL world's first appearance earns the first-ever belief -- no wrong ladder was ever displayable) + Henrik's debug-folder rule: per-char debug artifacts live in <data home>\debug\ (the warm trace moves to debug\mpwarm.txt and sweeps its old root-level file; the LAC-bridge handoff files stay put -- paired-reader protocol, leaving with LAC).
                  -- 118: A HOLLOW INSTALL IS NOT AN INSTALL + the install invalidates the belief (round 5b -- the warm trace's first catch, one reload after shipping). Henrik's debug-mpwarm.txt line 16: 'BELIEVED setN=0 flat=0' at :12 behind a '20 set(s) installed' print at :10 -- the install-time flatten yielded ZERO sets (the fresh utils state's first level read wasn't settled), that hollow-but-stable world earned belief, and the belief CACHE (keyed by time, not world) survived the real store arriving at ~:14 -- serving the :16/:18/:21 bad plans until the 10s TTL expired at :22. Three closures: (1) installSets refuses a flatten that yields 0 sets when the raw Dynamic has real entries -- store left absent, latch retries next tick (genuinely empty starter profiles still pass: their zero is the truth); (2) BOTH install branches wipe the LOW-map cache + earned signature -- a belief can never outlive the world it was earned against; (3) the flatten counts ride the signature (f/h fields), so store identity changes can never share a sig. The trace stays -- it earned its keep in one reload.
                  -- 117: THE WARM TRACE + the gear ordering gate (round 5 -- the round the guessing stops). Henrik's capture beat v116's axiom: the wrong world held IDENTICAL for 3+ seconds (two matching bad renders), so it agreed with itself and was believed -- stable-wrong states exist (a flatten over a not-yet-live input is hollow STABLY, not transiently), and no proxy or self-agreement can see through one from the inside. Two moves. (1) debug-mpwarm.txt: every full LOW-map compute writes one row -- latch verdict (attest-failed/new-sig/young/BELIEVED), rules/sets attestation detail (incl. WHICH trigger path resolved and parse errors), rule/set counts, nonzero-low count, gear NameToObject count, manifest mp count, flattened/hollow set counts -- fresh file per session, 150-row cap; the next wrong ladder is a movie with named stages, not a screenshot. (2) The native identity latch defers install/flatten until the gear world is live (NameToObject non-empty) -- the one KNOWN stable-hollow producer, killed by ordering rather than gating; skip never latches, the tick retries.
                  -- 116: THE STABILITY LATCH (round 4 -- "it fixed itself after a bit, so its initial plan is wrong"). Henrik's capture showed the v114/v115 gate FIRING correctly at first ask, then PASSING six seconds later with the world still wrong (lows 0, tags gone, phantom ammo band; healed ~30s later): every proxy attestation can be lied to one level deeper during the boot storm -- a trigger path resolved to the LEGACY tier reads as legitimately trigger-less, a first flatten can leave set names whose tables are still hollow. End of proxy whack-a-mole: the LOW map now attests ITSELF. A ready compute is believed (and cached) only after two computes >= 2s apart produce the IDENTICAL world signature (sorted lows+refresh baselines + rule/set counts). Until agreement: nil ladder, batteries hold worn, /dl plan says warming up. Consults ride the 0.4s Default tick so belief lands ~2.4s after the world truly settles; the steady state re-agrees instantly across cache expiries (the signature persists). Plus the rules-side twin of v115's sets rule: rules nil while a profile trigger file EXISTS = mid-resolution, unready. Both modes.
                  -- 115: the gate covers LAC mode too (Henrik's attribution note, round 3b: "I think this was the case earlier as well, not due to the migration"). He is right, and the mechanism is the same staged boot: after a /lac load / job change, gProfile.Sets exists but its Dynamic is the shim's EMPTY SCAFFOLD until the profile auto-install latch fires on the engine tick -- so v114's sets~=nil readiness read hollow-but-present as ready and the LAC-mode glimpse (which the maxmp v76-v94 saga likely brushed against) stayed possible. Unified rule, both modes: Dynamic empty while a profile sets file EXISTS for the current job = install pending = UNREADY (statics-only characters have no profile file and stay ready; unreadable job falls under the existing path gate). The v114 comment claiming LAC never races is corrected.
                  -- 114: THE READINESS GATE (native field round 3 -- Henrik's plan captures + his spec made law). His two /dl plan screenshots proved the boot glimpse exactly: seconds after a reload the ladder rendered with every low 0, every refresh tag gone (pure diff+alphabetical order, Bliaut dead last) and a PHANTOM ammo band (Talon Tathlum's diff stopped reading 0) -- then self-corrected. Cause family: mpBands built eagerly during the boot storm from whichever input lost its race (trigger rules resolving, the store's first flatten, per-second identity caches), and the 10s LOW-map TTL amplified one bad glimpse (v113's store-only guard missed every variant where the store existed but another input didn't). The law, Henrik's own framing: the band ORDER is a PURE FUNCTION of manifest + sets + rules -- three deterministic files -- and current MP only picks the position on the ladder. So mpBands now refuses to build until the world is attested: mpLowMap returns a READY flag (trigger world resolved -- rules loaded OR path resolved with the file legitimately absent -- AND a sets source present), unready results are never cached, and native mode additionally requires the store to hold at least one flattened set. Unready = nil = the live overlay holds worn gear and /dl plan says it is warming up. LAC mode is ready from the first dispatch (gProfile + rules precede any dispatch), so nothing changes there. Enable timing now provably cannot change the order -- only the per-session warm-up (offset at first true-full, measured ticks) remains, and persisting those is the standing offer.
                  -- 113: the maxmp boot-cache guard (native field round 2, the self-healing glimpse). Henrik saw the refresh body released FIRST right after boarding v112, then the order corrected itself with no code change: the LOW map had computed -- and CACHED for its 10s TTL -- an answer from before the tick's identity latch populated M._nativeSets, so every named set was invisible and lowRf/rfDelta sorted the bands wrong until the TTL lapsed. The cache no longer latches a result computed while the native store is absent (serve once, recompute next consult). LAC-state behavior untouched (the guard is not-inLac-gated).
                  -- 112: NATIVE FIELD ROUND 1 -- maxmp made whole (Henrik, 07-23 evening: "maxMP acting super weird" in native mode; the automation with the deepest LAC-state plumbing had exactly two native holes + one adjacent). (1) The banded ladder's OBSERVER (v88: measured MP ticks "fed by the 0.4s engine tick") only ran in the LAC tail the native branch returns before -- no observations, no measured tick, nonsense hysteresis; the native Default drive now feeds _mpb.observe identically (same zoning gate, same placement). (2) mpLowMap read gProfile.Sets DIRECTLY (predates the M._nativeSets seam), so every named set's potency point was invisible natively -- the LOW map saw only inline equips and the band thresholds were fiction; it now falls back to the native store like equipSetByName does. (3) The '/dl mode' flip re-flatten had the same direct read -- mode-gated entries natively stayed stale until a level/subjob change; now the native store re-flattens on the flip too.
                  -- 111: THE NATIVE BACKEND (feature/native-engine step 5). The addon-state copy of this module -- inert since v1 -- becomes the ACTIVE engine when the native flag is armed: engineActive() widens every inLac() gate that is an ENGINE concern (dispatch entry, the machinery block, mode state, the tick, the command surface, the /dl prio + plan printers), while LAC-BRIDGE machinery stays inLac()-pinned (self-swap, handoff/request files, the HandleEquipEvent wrap, lockstyle engine halves -- the #80 move owns native lockstyle). One equip seam: engineEquipSet routes resolved sets to gFunc.EquipSet (LAC) or equipengine's buffer (native). The gProfile gap closes with M._nativeSets -- the native sets store: readSetsSource + installSets install the active profile's job sets into it (the tick's NATIVE identity latch reloads on job/profile change), utils.rebuildSets re-flattens it on the shim's own cadence (every Default + modesRev), equipSetByName/ammoPlannedByHits/lock-set consult it after gProfile. The native Default drive rides the same tick with the same zoning guards. Flag off = byte-identical LAC-state behavior (twins parity pinned).
                  -- 110: THE STORAGE-HOME SEAM (feature/native-engine step 1). charDir() now resolves through profiles.dataDir() -- the one mode-aware storage authority -- so when the native-engine flag (config\addons\dlac\engine.lua) is on, the engine's mode state / trigger reads / debug handoffs all live under dlac's OWN config root (config\addons\dlac\<char>\) instead of piggybacking on LuaAshitacast's tree. Flag off (the default, and the shipped state until the native engine lands) = byte-identical path behavior. The inline composition stays as the no-profiles fallback.
                  -- 109: THE APPLY RIDES THE REQUEST FILE -- the friend's original bug, mechanically closed. "Everything works but lockstyle" (his 07-23 report, pre-update) is exactly the chain law's shadow: every automation rides LAC's internal handler flow, but lockstyle apply was the ONE player feature whose trigger crossed the COMMAND BUS ('/dl ls apply' queued by the GUI button/pumps or hand-typed) -- and on his load order the command died at dlac's own blocking handlers before LAC's engine received it (preview addon-local = fine; apply = silence). Now: lockstyle's queueCmd wrapper AND its typed-apply observation both write 'apply [box]' into debug-request.txt; the request watch runs engineApplyHalf -- the apply branch's body, extracted (one implementation, two doors, like check/ls) -- within ~1s when the command path is idle. All four order/hearing quadrants land exactly ONE apply (8s idle gate; last-writer-wins on the request file degrades a sub-second apply BURST to its last entry in the starved case only -- town/keep flows re-assert, acceptable). M._reqSpec (pure) parses the spec line.
                  -- 108: SYMMETRIC command handoff -- the starvation pair closed from both ends. Field 07-23, one day, both directions: Henrik's /addon reload cycles left the ADDON state deaf to typed /dl (engine heard, addon inert -- v107's watch cured that side); the friend's reload order starved the ENGINE (addon heard /dl check, receipt written, clean shim + current seeded copies + v107 modestate stamp -- and the report said ENGINE HALF MISSING because check.lua's own e.blocked halted the command before LAC's state received it). Ashita propagation law, now field-established from both sides: e.blocked stops LATER addons in the chain from receiving the command, and reload order IS chain order. Cure: whichever state hears, the other completes via file -- the addon writes debug-request.txt (stamp + 'check'/'ls <dur>'); this tick watches it (M._reqFire, twin of the addon's M._watchFire, 8s idle gate) and runs the same engine halves the command branches use (engineCheckHalf/engineLsHalf, one implementation two doors). Also v108: gearui's dev-buttons toggle no longer swallows '/dl debug <topic>' (the 07-23 namespace collision -- the friend's 'debug ls' flipped the Scan/Stage buttons); the toggle keeps bare/on/off only.
                  -- 107: the debug-ls WINDOW-OPEN marker handoff (debug-ls-open.txt, stamp + 'dur N', written at command time). Field 2026-07-23, Mindie: the dlac ADDON state provably never received typed /dl commands (load beacon clean, 18/18 modules, handlers registered) while THIS state heard every one (handoffs 11:22/11:23) -- so feature/debug.lua now FOLLOWS the engine's handoff stamps as a command-event fallback, and the ls capture window needs this marker to synchronize (the full ls handoff only lands at window END). The engine is the command receiver of record; the addon state is a subscriber.
                  -- 106: THE CAPTURE WINDOW (Henrik: "have it run at least 30 seconds when you issue dl debug ls... so you can capture all the events"). '/dl debug ls [seconds]' (30-120 clamp, default 45; the number arg means SECONDS now -- the niche box-pick override is gone, the dry run reads the MARKED box like the GUI button) prints the snapshot then opens a window in BOTH states off the same command: the engine's apply branch notes every receipt/refusal/send into M._lsDbg.log (M._lsDbgNote, 200-entry cap), the dispatch tick flushes the handoff at window end (M._lsDbgFlushLines, pure -- snapshot + '-- captured events --' timeline), and the addon side (lockstyle capture API + queueCmd/guard/packet hooks; feature/debug.lua delays its merge to end + 4s) writes the ONE report file with both timelines. The player clicks Apply DURING the window; the file shows the click leaving the addon ('queued: /dl ls apply'), arriving at the engine ('apply received'), and its outcome ('SENT box N' / the refusal) -- or which hop went silent.
                  -- 105: DEBUG REPORTS BECOME FILES + the send witnesses (Henrik's file rule: "all things that are considered debugs should generate text files that can be easily transferable so we can help debug"). The two halves live in two Lua states with no shared memory, so the transfer file is assembled by HANDOFF: the 'debug'/'check' branches write their lines to <char>\dlac\debug-<topic>-engine.txt (first line = os.time() stamp, lines bare) in the same command frame; feature/debug.lua's deliver tick reads the handoff ~1.2s later, judges freshness by the stamp (FRESH_S 10s) and writes ONE addons\dlac\debug\<base>-<Char>.txt -- a MISSING or STALE engine half is written into the file in those words, so the artifact carries the absence-is-the-diagnosis property. Plus the "is it actually SENDING?" witnesses: the apply branch stamps M._lsLastSend at its AddOutgoingPacket (sender-side truth, reported by debug ls as 'last REAL apply this engine session'), and the addon guard's packet_out handler keeps a 3-deep 0x053 observation log (lockstyle M._outLine -- reports what it SAW, promises nothing about injected-packet visibility).
                  -- 104: THE /dl debug SECTION, engine half (Henrik: "make a proper dl debug section... dl debug ls (please also accept dl debug lockstyle)"). feature/debug.lua (addon state) routes topics and owns the usage line; here one 'debug' branch answers KNOWN topics only. Topic 'ls'/'lockstyle': the apply pipeline as a DRY RUN -- the engine re-reads the boxes file (path printed, MISSING/no-PARSE called out), picks the box exactly like apply ('/dl debug ls <box>'), resolves every name through the SAME resolvers (M._lsResolvers, hoisted verbatim out of the apply branch -- one pair, two commands) and predicts the server's silent job gate -- then prints what WOULD happen (M._lsDebugReport, pure, tests DBG*) instead of sending. Companion addon half: lockstyle.M.debugLines() (boxes file/tier, marked box, UNSAVED-edits warning, v47 gate verdict, keep/town/guard state) -- '/dl ls state' now prints that same report (one readout, two names).
                  -- 103: /dl check -- the wiring-health readout's ENGINE half (Henrik's 2026-07-23 ruling: self-checks that answer "is dlac doing what it should?" belong IN dlac; probe-level capture stays in dlacprobe). Field case: a friend's laptop synced the ADDON tree but LAC never loaded the engine -- GUI + lockstyle preview (addon state) worked, '/dl ls apply' fell into a void with no output at all, and silence has no author. The engine cannot report its own absence, so feature/check.lua (the addon state, which always hears a typed /dl) prints the wiring readout -- addon + engine-file versions, seeded-copy byte-compare, the job file's shim state, the modestate __version handshake -- and names the ONE line the engine must add to it: this branch's '[dlac] check (engine): alive -- vN, job, profile'. A MISSING engine line is itself the verdict. Whitelist + branch added together (the v46 instdiag lesson).
                  -- 102: CONTENT-KEYED self-swap (field friction 2026-07-22, Henrik: "during engine change the hot reload doesn't always work -- I've had to reload LAC manually"). The self-swap trigger was the parsed M.VERSION number alone, so any engine edit under the SAME version -- the normal shape of mid-round field debugging -- never swapped; only a manual Reload LAC picked it up. Now the tick compares the seeded file's BYTES against the bytes the running engine was loaded from (M._swapSourceRaw, initialized from the first readable tick, updated on every successful swap), with the version compare kept as a secondary trigger that self-heals a stale baseline. The decision is a pure seam, M.swapWanted (tests SW*): unreadable/foreign/failed-before bytes skip, version difference swaps, nil baseline captures, byte difference swaps. Companion dlac.lua change (2026.07.22i): the seeder writes only files whose bytes CHANGED and re-runs every 5s (dlac-seed-watch), so a bare `git pull` now propagates addon -> seeded copy -> running LAC engine with no manual step; the swap chat line names a same-version swap explicitly.
                  -- 101: STALE Range-bit stamps distrusted (field case 2026-07-22, Mindie PUP: a MANUALLY equipped Automat. Oil +2 was displaced from Ammo every Default dispatch beside the idle set's Animator). The ADR 0010 trinket completion had wrongly stamped RSlot=4 on the Animator-fed oils in gear.lua (server truth: item_weapon subskill 10 == every Animator, so charutils' Range/Ammo compat check KEEPS oil + Animator together -- the census over item_equipment x item_weapon shows the oils are the ONLY such paired class). The completion is fixed addon-side (gearrecord.ANIMATOR_FED) and /dl fix retracts the stale line -- but the ENGINE must not require a migration step: M.recordRSlot is now the one reader of a manifest record's RSlot and ignores the stamp for the pinned oil ids, so every user is healed by the addon update alone (dispatch.lua re-seeds every load). Tests TR16*/TR17 (guard + twin parity), TB8* (end-to-end: worn oil survives the Animator plan).
                  -- 100: THE ARBITER, step 4 (ADR 0012) -- COLLAPSE HARDCODED ARMS; /dl why NAMES CLAIMANTS. The registry is now the SINGLE precedence authority: MaxMP registers a proper CLAIM (mpClaimFor -> claims['MaxMP'] = its battery targets), so ctx.mpCeded derives from that one registry and the woven rank-consult scaffolding is retired -- only MaxMP's EQUIP stays woven (hold/release/upgrade/sticky/movement-yield are within-set resolution, deliberately outside the Arbiter). /dl why gains a per-slot CLAIMANT ATTRIBUTION block: the pure resolve (M.arbExplain / M.arbWhyLines) runs over the SAME claims + rank + floor the live overlay applied and names every contested slot's winner + rank -- 'Ammo: AutoAmmo (rank 3) over MaxMP (rank 4)', veto slots read 'stopped by Locks', floor-only slots 'Triggers (floor)'. The Claim record shape is documented at the registry (arbExplain header) + architecture.md: a new claimant (AutoAcc next) joins as ONE rank row + ONE claim table, no new arm. Holds + within-set resolution (sync settle, PetAction, AutoStaff/AutoObi, ADR 0010) unchanged. Tests AR11/AR12 (whole-path order pinning + /dl why attribution, headless).
                  -- 99: THE ARBITER, step 3 (ADR 0012) -- LOCKS BECOME THE DRAGGABLE VETO ROW. The lock veto is no longer an absolute per-slot strip inside every equipResolved: it is a RANK position. A claimant ranked ABOVE Locks punches through a locked slot; one ranked BELOW it stops. The engine's separate lock special-casing is retired -- the hidden "pins never check locks" rule and the unconditional first-arm strip are gone, replaced by the registry law: each claim layer's equipResolved is told whether to respect locks (rank below Locks) or punch through (above), and woven MaxMP consults its OWN rank vs Locks (ctx.mpRespectLocks) for the band build AND the mp-stage placement (the old hardcoded M.locks skips now derive from rank). Default order Pins > Locks > ... preserves today's field behavior: pins punch through locks, every other claimant + the Triggers floor stop at them. Locks at TOP = absolute veto including pins; dragged lower = everyone above punches through, everyone below stops. Pure resolve model M.arbResolve gains the Locks veto (M.LOCK_HELD sentinel + M.arbLockClaim); /dl lock + Equip & Lock user-facing behavior unchanged. Tests LV* (position semantics + the equipResolved/mpBands wiring).
                  -- 98: THE ARBITER, step 1.5 (ADR 0012 amendment) -- activities CO-CLAIM. The newest-armed (`at` stamp) exclusivity among Craft/HELM/Fishing is retired: each armed activity now claims whenever its own gates hold, all three may co-claim in one dispatch, and the rank-ordered apply loop settles every contested slot PER SLOT (arming an activity no longer stands the others down whole). The field case (PUP): idle floor Range = Animator; Fishing armed -> rod in Range; HELM also armed wins only its seven armor slots (HELM never claims weapons/Range/rings/Ammo), so the rod stays in Range until Fishing itself disarms. Each feature's own gates are UNCHANGED (HELM/Fishing Engaged/Dead stand-asides + Default-only, Craft Default-only, AutoAmmo's stand-down while fishing is live, MaxMP's rank consult). /dl prio now shows every concurrent claimant ON.
                  -- 97: THE ARBITER, step 1 (ADR 0012). One data-driven claim registry orders every Claim's application -- the hardcoded craft > HELM > fish > AutoAmmo > pin overlay sequence at the bottom of M.dispatch is gone, replaced by a single rank-ordered loop (applied LOW->HIGH so higher rank wins the slot, over the Trigger floor). The rank is one strict draggable list per character, persisted as the `arbstate` Statefile (hand-editable this step; the GUI writer is step 2; hot-reloaded on the 1s throttle, torn/missing = built-in default). Default order: Pins > Locks (veto placeholder, semantics unchanged) > AutoAmmo > MaxMP > Craft > HELM > Fishing > Triggers floor -- reproduces today's winners with ONE deliberate change: AutoAmmo's named projectile beats a MaxMP battery in Ammo. MaxMP stays WOVEN through the resolves (not a discrete overlay) but consults the rank via ctx.mpCeded: it never contests a slot won by a claimant ranked above it (so Ammo is ceded to AutoAmmo; batteries still override Craft/HELM/Fishing armor, both ranked below). Pure resolve core M.arbResolve / M.arbOrder / M.arbCededAbove (tests AR*); read-only /dl prio prints the live rank + per-claimant claim status. All claim-side conditions untouched (newest-armed craft/HELM/fish exclusivity, AutoAmmo's fishing stand-down, MaxMP 'remove'-respect / movement yield / sticky pairs / stage-eligibility).
                  -- 96: MOVEMENT YIELD (panel setting, manifest fmt 14 -- mpMoveYield + the mv map): while MOVING, a set piece carrying Movement+ beats the battery in its slot even at max MP (field ask: Pegasus Collar over the neck battery on BRD; the movement trigger set's piece flows, the battery steps aside, and stopping resumes the band plan untouched). The check is the FIRST arm of the per-slot MP branch -- before target logic, after the v91 'remove' skip -- and reads the same ctx.player.IsMoving the `moving` trigger matcher uses. Off by default; the MaxMP panel checkbox persists it inside the manifest like the pair override. /dl why notes it as MP-MOVE.
                  -- 95: the refresh BASELINE is the POTENTIAL refresh (field round 13: Clr. Bliaut +1 displaced by Hlr. Bliaut +1 at MP ~800, plan row 12 'body (0->53)' with NO [refresh-cost] tags anywhere). lowRf was the min-MP piece's refresh -- which reads 0 the moment ANY combat/precast set writes the slot with potency gear, so every refresh-cost delta vanished, the Hlr band sorted deep-and-plain and its clamped on-trigger landed mid-pool. Now lowRf = the MOST refresh any trigger-reachable set puts in the slot ("you should be aware that there is a POTENTIAL refresh piece there" -- the round-10 ruling verbatim); the MP low stays the minimum (the true potency point). Plus mpbands.MIN_TICK = 5: the measured tick is honest (unbuffed gear refresh really ticks +1..3) but a 1-MP margin makes hair-width hysteresis (off<=1086/on>=1087) -- the margin floors at 5, the buckets keep the true readings. Not the pair-homes change: that stays ear/ring-only.
                  -- 94: sticky pairs check BOTH claims (field: Loquac. still moved ear2 -> ear1 ONCE, no bounce). Root cause found OUTSIDE the engine: Henrik's gear.lua has NO LoquaciousEarring entry, so his Idle Ear2 ladder's gear.Ear.LoquaciousEarring reference is silently nil (nil list entries VANISH -- no warning possible) and the SET equips Outlaw's into ear2, displacing the earring to the bag; the band then legitimately picked the freed 30-MP battery for ear1. Engine hardening shipped anyway: mpStickyPairs consulted `plan or worn`, so a sibling plan naming a DIFFERENT piece shadowed the worn claim -- both claims veto independently now (MSS5). The data fix is Henrik's side: /dl sync to index the earring, then the set holds it in ear2 and the plan-claim pins it forever.
                  -- 93: STICKY paired slots (field: Loquacious Earring bounced ear2 <-> ear1). The v83 pick veto reads WORN state, which lags ~a dispatch behind LAC's swaps -- so the band pulled the earring toward its ladder home (ear1) whenever the read went stale, and the idle set planted it back (ear2), forever. M.mpStickyPairs (tests MSS*) closes it at the APPLY site: a battery candidate whose piece is already claimed by the sibling ear/ring -- in THIS dispatch's resolved PLAN (cannot lag) or on the body -- never writes; genuine duplicates stay exempt (mpPairSkip: dup-owned items ride both paired ladders). MP earrings and rings never relocate across their pair once set; /dl why notes the skip as MP-PAIR sticky.
                  -- 92: ONE band per slot + reachable on-triggers (field round 10, Henrik's RULING: "to get refresh in is NOT YOUR JOB -- that is the idle set's job... be aware there is a potential refresh piece there and adapt accordingly"). The v90 multi-rung experiment is retired: the engine wore refresh mid-rungs itself (overstepping the job) AND wearing them depressed the pool below the top bands' re-equip thresholds -- the ladder deadlocked, batteries never displaced the refresh pieces even at max MP. Now: the band = the slot's TOP battery (augs counted, equal-MP ties prefer the refresh copy) vs the POTENCY POINT (the sets' own piece, lowRf-aware); refresh awareness lives ONLY in the order (rfDelta ASC then diff ASC -- the battery over the idle's refresh piece is first off/last on, so the idle's Clr. Bliaut +1 returns FIRST, Bunzi's Hat second). And onAt clamps to endMax: the raw lastMax - tick sits above the reachable pool whenever diff > tick (Hlr-over-Clr diff 22 > 15 could never re-fire); clamped, small diffs keep the early re-equip, big diffs fire the moment the pool tops out; the hysteresis gap stays min(diff, tick) wide. Tests MB13* rewritten.
                  -- 91: the fishing overlay claims Ammo WITH the rod, bait or no bait (Henrik's field case: fishing enabled with no bait in the bags -> the idle set's stat-stick trinket re-planned into Ammo every Default frame beside the rod, the server stripped the rod (ADR 0010), the overlay re-equipped it, forever -- the v78 within-set scope ruling means nothing in the IDLE set's own resolve stops a trinket next to a merely-WORN rod, and trinketWornDisplace judges worn gear only, so a plan-borne trinket kept arriving). fishOverlayFor now writes Ammo = bait or 'remove' whenever it writes Range; and the maxmp per-slot branch skips an explicit 'remove' plan (a deliberate empty-the-slot claim -- fishing's rod guard, AutoAmmo's sweep -- must not have a battery held against it). Tests F68-F71.
                  -- 90: MULTI-RUNG bands (field round 9; names CORRECTED 9b: last out/first back = Clr. Bliaut +1 (Refresh 1 native + 1 aug = 2), then Bunzi's Hat (+1) -- and with augs ALWAYS in the totals, Hlr. Bliaut +1 at 35+18=53 MP TOPS the body ladder while Bunzi's Robe 50 is DOMINATED, pruned, never worn). One band per meaningful rung -- rungs sanitized to falling MP / rising Refresh (dominated rungs pruned), each adjacent pair banded with its own diff and rfDelta, the last rung banding against the potency point. Order = ONE rule: rfDelta ASC then diff ASC -- refresh-cost top-ups (Hlr. Bliaut +1 over Clr. Bliaut +1, Erudite Cap over Bunzi's Hat) come off FIRST and return LAST; refresh-gain bands sink by magnitude (+1 before +2). target() answers the PIECE NAME per slot (shallowest ON band's rung) or false; M.mpRungs supersedes single-pick (mpBestPick = rungs[1] shim); M.mpBandFind serves notes/plan. Tests MB13*, S169b-e (the augment fold end-to-end).
                  -- 89: augments counted + SIGNED refresh delta (field round 8, Henrik: "include augments as with gearwatch" / "refresh pieces release last, return first -- mp recovery is key"). The manifest folds each owned copy's private-augment MP and Refresh into mp/rf (augments.ownedAugStats, fmtver 12 -- Cleric's Bliaut +1 = Refresh 1 native + 1 augmented = 2), and the band order runs on rfDelta = battery Refresh - potency Refresh: positive sinks DEEP (refresh battery back first as MP recovers), NEGATIVE floats SHALLOWEST (a flat-MP battery that would COST refresh -- Bunzi's Robe over Cleric's +1 -- comes off first and returns last, keeping the refresh piece worn through the spend). /dl plan tags [refresh] / [refresh-cost]. Tests MB12*.
                  -- 88: maxmp v2 -- THE BANDED LADDER (Henrik's 2026-07-21 redesign, docs/design/maxmp-mode.md "v2"; feature/mpbands.lua is the pure core, tests MB*). Dynamic per-dispatch marginal decisions retired: M.mpBands precomputes per-slot bands (LOW = least MP across trigger-reachable sets, HIGH = the pair-veto-aware battery pick via the shared M.mpBestPick) chained into absolute thresholds -- unequip at endMax - tick, re-equip EARLY at lastMax - tick so the next recovery tick lands into the headroom; smallest difference releases first EXCEPT refresh batteries sink deep ("Refresh > least mp diff", manifest fmtver 11 carries rf); hysteresis is each band's own width, so the 15s cooldown is gone. CURRENT MP is the only live input (the one read that never lies); the TOTAL anchor is nativemp base + merits + worn MP, offset-corrected at any true-full MP%. Ticks are MEASURED (median of observed rises, standing/resting buckets, fed by the 0.4s engine tick), never modeled from traits. Batch swaps: every eligible ON-candidate lands in one dispatch through the v78 RSlot guard. v76-v87's pure rules stay exported for compatibility.
                  -- 87: the equip-release OSCILLATION killed (field round 7 debug log: batteries climbed, alternated with their set pieces, cascaded back to idle gear, "back to 975 again"). Two causes, both from an unreliable GetMPMax: (a) FALSE FULL -- a stale-low max made curMP >= maxMP fire below a genuinely full pool, over-equipping batteries into headroom that instantly read as spent; (b) BOUNDARY DUMPS -- a fresh battery sits exactly on the hold boundary, so a few MP of max error released it immediately, dropped max, flipped the next boundary, cascade. Fix: M.mpPoolFull (tests MF*) -- the floored party MP% reads 100 ONLY at cur == max, so fullness is now exact and every equip gate uses it (cur >= max survives just as the no-percent fallback); M.mpReconcileMax (v86) goes LOW-biased -- below full, GetMPMax is ignored outright and max = ceil(cur*100/(mpp+1)), the window's low edge: an under-estimate can only over-hold (release needs surplus + at most ~1% extra spend), never dump a battery early.
                  -- 86: max-MP read RECONCILED against the party MP percent (M.mpReconcileMax, tests MR*). Field round 6's real cause -- not the full-pool gate: Ashita's GetMPMax() went stale across the BLU/WHM gear churn (engine read 975/1052, the client bar said 975/975), so curMP >= maxMP never fired (dead ladder) and small-delta holds read as spent (the "de-equips at times" report). The party MP% rides the same packet family as current MP: mpp >= 100 pins max = cur EXACTLY, otherwise max clamps into [cur*100/(mpp+1), cur*100/mpp]; unreadable cur/mpp degrade to the raw read. playerMP() is the single consumer -- gates, holds, and /dl plan all heal at once.
                  -- 85: /dl plan applies the paired-slot veto (v83's rule) -- the plan advertised 'ear1: Loquac. Earring +20 gain' while the live engine vetoes that pick (single copy worn in ear2), so the overview promised an equip that never happens. The plan's pick now walks the ladder past pair-vetoed rungs exactly like the engine (falls to the next wearable rung, tags the row '[pair: X worn in ear2]'; a slot whose every rung is vetoed says so; dup-owned stays advertised). Tests MPS8*. Display only -- dispatch rules untouched.
                  -- 84: inTown condition -- am I standing in a town? A true/false gate off data/zones.lua's curated town set (server CITY zonetype + Nashmau, minus combat-staging CITY zones; generated by tools/gen_zones.py from zone_settings.sql on the stable branch). Live read GetParty():GetMemberZone(0), memoized on ctx like targetSelf/buffs -- an unknown zone (failed/headless read, or the demo zone 0) matches NEITHER polarity, so a bad read never fires blind. Tier 95 (a LOCATION gate, deliberate like a player-state one): a town show-off set overlays the plain Idle set, while an explicit mode still wins. GUI: an inTown flag on the Default handler. Field case: idle in town -> show off your gear.
                  -- 83: paired-slot veto -- a battery already WORN in the sibling ear/ring is the SAME physical item, and equipping it "here" made LAC unequip it over there (UnequipConflicts) and shuffle it across, leaving the sibling empty (field: resting WHM, Loquacious Earring hopped ear2 -> ear1, ear2 left bare; the resting set names no earrings at all -- the uncovered pass drove the churn, net MP zero). M.mpPairSkip (pure, tests MPS*) vetoes such candidates at all three collection sites (hold-upgrade, covered upgrade, uncovered); genuine duplicates are EXEMPT -- the manifest lists dup-owned items in both paired ladders (owned counts), so "the sibling's own ladder also names it" = a second copy exists and the pick proceeds (2x Astral Ring).
                  -- 82: Iridescence universals LADDER -- the manifest's new `universals` array (fmtver 10: EVERY owned universal, preference-ordered by the GUI -- tier desc, job-specific over the Chatoyant/Iridal fallbacks; catalog-verified tiers, +3 now exists: Inanna/Keraunos/Gridarvor/Laevateinn/Tupsimati) replaces the single `universal` read when present: resolveStaff takes the FIRST rung usable at the live level, so a level-synced character falls through a parked Lv75 Inanna to Foreshadow +1 Lv50 instead of losing the universal outright (Incursion syncs); the tier contest vs the elemental staff is unchanged (ties still go universal). virtualMinLevel considers every rung -- the set marker becomes a rung at the LOWEST universal's level. Old manifests (single `universal` / legacy string) read exactly as before.
                  -- 81: `target` condition -- WHO the action is aimed at; v1 vocabulary: 'Self' (Henrik's case: waltz potency reads the TARGET's VIT beside your CHR, so a self-waltz wants a VIT+CHR set while waltzing someone else keeps the plain CHR set). Live read: gData.GetActionTarget().Index (LAC stores the outgoing action packet's target index for Spell/Ability/Item/WS/Ranged before Precast fires) vs my own party index, once per dispatch (ctx.targetSelf, tri-state -- unknown matches NOTHING, the buff-cache rule, so Default-handler rules and failed reads never fire a target rule). Tier 55: a self-refined rule overlays its base rule (name 50, contains 40, group 45) with no hand priority, under the Automations band (60). GUI: a `target` dropdown on Precast/Midcast/Ability, one value today, built to grow. /dl why tags a self-aimed action '@self'.
                  -- 80: a HELD battery still upgrades at a FULL pool. Field round 4 froze with 7 positive-gain batteries queued at 1040/1040: the MP-HOLD branch fires for any worn piece with surplus over the set piece and used to swallow the upgrade check entirely -- a worn SMALL battery (Curate's Earring 10) blocked its own upgrade (Loquac. Earring 30) forever; only slots already wearing their top pick ever equipped. The hold branch now collects the upgrade candidate too (same full-pool gate, cooldown, and mp-stage one-per-dispatch pick; the atomic swap keeps current MP intact, so the hold's no-waste guarantee holds). /dl why shows the winner slot as MP-HOLD + MP-EQUIP together: held from the SET piece, upgraded by the stage.
                  -- 79: /dl plan -- the maxmp battery plan as chat lines (kept OFF the Automations tab per the hidden ruling). Per slot: the live pick (mpPick at the current level), its MP, WORN/gain-vs-worn/LOCKED status and the full ladder with above-level rungs tagged (LvNN); rows sorted biggest gain first = the equip order at a full pool; header restates the two staging rules; footer flags the stale-manifest tell (a listed piece not in Inventory/Wardrobes). Pure assembly M.mpPlanLines (tests MPL*), inputs injected; the command glue gFunc-gates like /dl ls (one state, one printer). Engine dispatch rules untouched.
                  -- 78: ADR 0010 scoped WITHIN the set (Henrik's ruling; field: worn Rimestone Lv60 kept a Lv20 Rouser out of Range). The keep-higher-Level contest still arbitrates a Range+Ammo pair the PLAN names, but a merely-WORN trinket no longer defends Range from outside it -- the engine DISPLACES it (Ammo='remove', LAC's native unequip; equipping the weapon alone would just be server-stripped, the original flap) unless Ammo is locked or pin-reserved. And MP-EQUIP never stages a battery whose RSlot reserves an occupied slot (planned or worn) -- a doomed biggest-gain pick would also win the one-per-dispatch stage forever and starve every other battery. Pure rules M.trinketWornDisplace / M.mpStageEligible (tests TR11-15, MS9-10, TB*).
                  -- 77: MP-RELEASE names the INCOMING piece -- 'Hands=MP-RELEASE Oracle's Gloves -> Blessed Mitts +1 (+7 MP surplus spent)'. Field round 1 of v76: a release re-decided identically for 8+ seconds with the worn piece unmoved -- the swap-back never landed, and because the stalled slot keeps the smallest surplus it BLOCKS the whole release queue behind it. Root cause NOT yet found (wardrobe availability was a dead lead -- the server enables all wardrobe flags; Henrik confirms no unavailable gear). The named target turns any future stall into a checkable fact instead of a guess. BuildDynamicSets checks level only (no ownership/bag check) -- a plan can name stored/unowned/bazaared gear; parked in docs/design/maxmp-mode.md.
                  -- 76: maxmp STAGED -- at most ONE battery moves per dispatch (field report: the mode read as an on/off switch, everything on / everything off in one dispatch). Release: smallest surplus first (the big battery stays on longest, per the original spec) -- the all-at-once release was also an accounting bug: N same-dispatch releases drop max MP by the SUM of surpluses while each per-slot hold justified only its own, and the server clamp (cur = min(cur, newMax)) ate the difference; a single smallest-surplus release is clamp-free by construction. Equip: biggest gain first at a full pool; the full-pool gate then paces the ladder (the next battery waits until recovery refills the last one's headroom). Pure choosers M.mpStageRelease/M.mpStageEquip (tests MS*); post-pass 'mp-equip-uncovered' renamed 'mp-stage' (PL2) -- it now owns BOTH the single release and the single equip across covered + uncovered slots.
                  -- 75: /dl lock set <name> -- the Sets tab's "Equip & Lock" (Incursion T3: the server locks your equipment on entry). Wears the COMMITTED set once -- bracketed ClearBuffer/ProcessBuffer, the PetAction tick's lesson, or the equips evaporate -- then locks ALL 16 slots so the engine stops proposing swaps the server would refuse; stale locks are cleared first so the set lands whole. Release: /dl lock all off (or the Sets tab's Unlock). Dispatch rules untouched.
                  -- 74: AutoAmmo per-job config (ammostate fmt 2) -- every job carries its OWN priority list + persisted on/off (field round 2: "all jobs can't use all ammos"); the overlay resolves against as.jobs[<main job>]'s section, legacy fmt-1 files (top-level ammo list + jobs map) keep working unchanged until the GUI migrates them. Decision rules untouched.
                  -- 73: AutoAmmo -- the Ammo-slot automation (docs/design/auto-ammo.md). ammostate.lua (GUI-written) + an overlay on EVERY event: count-verified picks per context (ranged / consuming-WS / the three free magical WS 217,218,220 / Quick Draw / Unlimited Shot 115), special ammo swept off wherever a shot could consume it, ladder ends in a literal 'remove' (LAC's native unequip; an empty gun is server-blocked, so the shot refuses instead of eating the bullet). New engine capabilities: the first LAC-state bag counter (per-second cache, fresh on action events) and the 'remove' plan. Pure core M.resolveAmmoPlan (tests AM*).
                  -- 72: serializeTriggers keeps BARE mode definitions -- `[name] = {}` (no bind, no values) is emitted instead of dropped, so a plain UI-created toggle survives the commit round-trip and stays in the Modes list (triggermodel.fromRaw keeps the empty def too; tests TM20-22). Rule matching, resolve order and every other engine path untouched.
                  -- 71: equipResolved's resolve order becomes DATA -- the five whole-table post-passes (mp-equip-uncovered, craft-sub-guard, sync-hold-ammo, trinket-vs-ranged, reserved-drops) are named entries run in M._postPassOrder, so the trinket-BEFORE-reserved constraint (ADR 0010) and every future overlay's place in line are one visible, test-pinned list (PL*) instead of prose; the per-slot chain keeps its elseif precedence (locks > sync-hold > pin-reserved > AutoAcc > virtuals > MP), now named; the copy-on-write dance and note building are written once (W/note) instead of eleven times. Behavior bit-identical -- the H/AK/TR/LS/MC sections are the net.
                  -- 70: the statefile seam gets ONE reader -- ensureStateFile behind the auto/acc/craft/helm/fish/pin caches (six near-identical clones collapsed; charDir gains the _charDirOverride seam so the file-driven surface finally runs headless, tests SF*). POLICY unified on the pin reader's v44 field lesson: a torn/corrupt state write now DROPS that state everywhere -- craft/helm/fish/auto used to keep the LAST GOOD table forever on a parse failure (raw already held the corrupt text, so the raw-compare short-circuited and even the watcher's clear could not unstick it -- a stale craft overlay glued on was one torn write away). The next good write self-heals; triggers deliberately keep their own keep-previous-and-say-so loader (hand-edited file).
                  -- 69: obi + Oneiros virtual decisions extracted PURE (resolveObi / resolveOneiros, the resolveStaff shape): the rims in resolveVirtual only read env/nativemp/vitals, the decisions take data in -- behavior bit-identical, but the two field-calibrated gates (positive day/weather sign; MP <= floor(base*50/100), boundary inclusive) are finally pinned headless (tests VG*). One /dl why nuance: with the grip unowned AND nativemp missing (broken install), the reason now reads module-unavailable first.
                  -- 68: the AutoOneiros marker is a Lv75 rung UNCONDITIONALLY -- the grip is one fixed Lv75 item, so virtualMinLevel answers 75 even when the manifest has not learned it yet (no more Lv0 always-adopt wildcard on a stale manifest); gearui's + Add stamps the virtual rec Level 75 so the set editor shows the truth.
                  -- 67: Oneiros latent percent FIELD-PINNED at 50 -- Henrik measured the live break with refresh ticks: MP 357 = last point the grip's +1 ticks, 358 = gone, and 357 is EXACTLY 50.0% of maxmp 714 (confirming the denominator AND the inclusive <= boundary in one shot; 75% of anything plausible = 535-543, 50% of the displayed 724 = 362 -- nothing else fits). The public repo's item_latents row says param 75, so live diverges from the sql seed: docs/server-questions.md #6. Threshold is now floor(base * 50/100); if the team ever answers "75 is right, the DB was stale", this one line re-aims.
                  -- 66: Oneiros merit clamp field-corrected -- Henrik's menu reads 10/10: merit.cpp caps usable merits at cap[mlvl] (10 at Lv75; the merits.sql upgrade=15 headroom needs Lv80+, unreachable here), so the resolver clamps mpMerits to 0..10. His naked 724 fully decomposed: 614 formula + 100 merits + 10 SCH-sub Max MP Boost (traits.sql trait 8 job 20 Lv30, Mod::BASE_MP 1096) -- and BASE_MP rides health.MODMP (UpdateHealth, the DISPLAYED max) while the latent divides by health.MAXMP (CalculateStats only), so the trait does NOT move the threshold: his true line is floor(714*0.75) = 535, and the detail view now warns against tuning merits to make base match the naked screen number.
                  -- 65: Auto Oneiros Grip (dlac:AutoOneiros, Sub) -- equips the grip while its latent is LIVE: current MP <= 75% of the BASE pool. Server truth (stable latent_effect_container.cpp): MP_UNDER_PERCENT divides health.mp by health.maxmp = CalculateStats' race/job/sub formula + merit MP, NO gear -- so the threshold is floor((nativemp.self + 10*mpMerits) * 0.75), recomputed live per resolve (job change / level sync re-aim it). Manifest carries {oneiros = {name, level}} + mpMerits (the one number the client can't read passively -- Automations tab input, cap 15 on CatsEyeXI); virtualMinLevel answers the grip's level so the flatten skips the rung under Lv75; utils' flatten treats the marker as a GRIP for Sub pairing (2H main only).
                  -- 64: Fishing overlay (docs/design/fishing-gear.md) -- the craft/HELM systems' third sibling. fishstate.lua {enabled,at,target,rod,bait} read like helmstate (enabled = the manual "Set Fish Idle" pill, session-only addon-side); dlac:AutoFish resolves the manifest's fish ladders (armor + Main -- Halieutica is a Main-slot fishing weapon, craft precedent for weapon slots; a Main swap costs TP, accepted while idle-fishing); Range/Ammo come STRAIGHT from the state file (rod + bait are target-fish-specific picks fishwatch pre-resolves and keeps owned-valid on its bag heartbeat -- the engine wears names, never chooses). Same Default-only gate + Engaged/Dead stand-aside as HELM (v61 law); bait re-equip after a stack empties is free (the overlay re-asserts the name every dispatch, LAC pulls the next stack). Arbitration generalizes v59: craft/helm/fish -- newest `at` stamp wins whole, ties keep the older system (craft > helm > fish), pins still beat everything.
                  -- 63: Pet conditions v1 (research: docs/reference/pet-handling-other-luas.md) -- pet = true/false (a LIVING pet exists: gData.GetPet() is nil petless AND at pet HPP 0, so a dead pet reads as none), petStatus (the pet's own Idle/Engaged -- status + petStatus spells the player x pet 2x2, incl. the classic "master idle while the pet fights"), petName (identity -- avatar/spirit perpetuation gear; Henrik: essential for SMN). ctx.pet read once per dispatch beside ctx.player; petStatus/petName IMPLY existence (never match petless). Tiers: pet 22 / petStatus 23 sit between status (20) and moving (25) so a pet-refined rule outranks its base status rule with no hand priority and Movement still overlays; petName 50 = the exact-name (identity) tier.
                  -- 62: virtual markers carry a LADDER LEVEL -- M.virtualMinLevel(marker) = the lowest level among the manifest items the marker can resolve to (AutoStaff/AutoIridescence: universal + per-element staves; AutoObi: obis; nil for craft/helm/acc and legacy name-only shapes). BuildDynamicSets skips a marker below that level so the flattened Main shows the item actually worn (Henrik's field case: a leveling WHM's set showed dlac:AutoIridescence "at Lv0" while wearing Pilgrim's Wand -- the marker now reads as a Lv51 rung, his Chatoyant Staff); the Sets tab displays the derived level and only shows the marker as the current pick once it's reachable. nil keeps the old always-adopt behavior everywhere.
                  -- 61: HELM overlay stands aside in combat -- field report: "Default" is NOT "idle" (HandleDefault runs every frame, engaged gear resolves inside it too), so the overlay was pinning over combat gear. helmOverlayFor now returns nil while ctx.player.Status is Engaged or Dead (the same Status string the trigger matchers read); 'Event' deliberately stays dressed -- the HELM animation itself reads as an event, and dropping there would churn every swing. Henrik: you HELM in dangerous places -- aggro means FIGHT.
                  -- 60: Auto HELM (helmstate auto/autoUntil) -- the helm overlay is active when the manual idle switch is ON, or when auto is armed AND a detection hold is running (helmwatch re-arms autoUntil on every 0x034 Point result; expiry is checked live per dispatch, so normal idle gear returns ~60s after the last swing with no file write needed). Same Default-only gate, same slots, same arbitration.
                  -- 59: HELM overlay (docs/design/helm-gear.md) -- helmstate.lua {gather,enabled,at} read like craftstate; dlac:AutoHelm resolves the manifest's fmtver-7 helm ladders (armor+neck+waist ONLY -- never weapons: tools are inventory items and idle weapon swaps burn TP); overlay gated to Default exactly like craft (idle-only is the FEATURE here, Henrik's hard requirement). Craft-vs-helm arbitration: both switches on -> the newer `at` stamp wins whole (the watchers already exclude each other addon-side; this is the engine-native backstop -- no cross-module requires, no cycles).
                  -- 58: monitor stream is frame-paced -- fired lines buffer in _monQ and the tick's frame pass streams ONE '/dlacmonev' per frame. Two commands queued in the same frame cross the command bus in REVERSE order (field case: the monitor showed every cast's Precast ABOVE its Midcast -- the engine equipped in the right order all along, only the display lied). Ring, file mirror and monitor untouched.
                  -- 57: settle window 3s -> 1s (Henrik's ruling: 3 felt long). Semantics unchanged: the window is stability-since-LAST-change, every flip re-arms it, so staged transitions stay covered; 1s only outlasts the gap after the final flip. Raise M.SYNC_SETTLE_S first if a sync ever eats TP again.
                  -- 56: Level-sync settle hold -- a MainJobSync jump on the SAME job (a level sync landing: Incursion boss pop, party re-sync) arms a ~3s hold: every dispatch keeps Main/Sub/Range as worn (ctx.syncHold, the pinReserved pattern; a Range-reserving stat-stick Ammo holds WITH the Range it reserves, or the server would strip the worn ranged weapon -- ADR 0010), and HandleDefault is gated whole for legacy profiles via M.defaultGateHold (pet hold + sync hold), consulted AT CALL TIME by a thin generational wrap shell (WRAP_GEN) so the gate itself hot-swaps live. Tracker parked on M (survives self-swap mid-hold). Job changes and first reads adopt instantly -- no hold. Pure rule: M.syncSettleStep (LS tests). Root cause of the field report "popping an Incursion boss sometimes zeroes saved TP": a mid-transition level reading resolving a different Main.
                  -- 55: Trigger-monitor feed -- a 5-entry ring of fired-rule lines (updated on every retrace: Default only when its matched-rule set changes, action events always). Each new line STREAMS to the addon state as a blocked '/dlacmonev' command (the /bind queue precedent -- the live channel two Lua states share) AND flushes coalesced to firedstate.lua (reload bootstrap + fallback). Display only; the engine never reads it back.
                  -- 54: Player conditions v2 (Henrik's morning revision) -- canonical keys playerHPBelow/Above, playerHPPercentBelow/Above, playerMPBelow/Above, playerMPPercentBelow/Above (raw AND percent variants; v53 hpBelow/... spellings stay as hidden percent aliases), plus whenAny OR groups: a rule matches when ALL `when` conditions hold OR ANY whenAny entry holds; an OR-only rule is not always-on. ruleLabel/defaultPriority take whenAny.
                  -- 53: Player conditions v1 -- hpBelow/hpAbove, mpBelow/mpAbove, tpBelow/tpAbove (strict compares vs gData vitals) and buff/buffNot (active status effect by name or id; per-dispatch buff cache; unreadable state matches NEITHER polarity). Tier 95, just under mode.
                  -- 52: trinket vs ranged weapon (ADR 0010) -- a stat stick reserves the Range slot server-side, so the engine keeps the higher-Level of {trinket, ranged weapon} and drops the other (no flap); trinket RSlot completed in gearimport. 51: Trigger Groups (G1) -- new `group` matcher (specificity tier 45) + Groups section load/serialize (ADR 0009). 50: the v46-49 /dl instdiag diagnostic is out (field-confirmed on both characters); the fix it found stays -- M.jobReady + the job-keyed latch. See ADR 0007
                  -- 49: THE LOGIN BUG. At login GetMainJob() reads 0 (=None), which gData stringifies to "NON" -- not '' and not '?', so the auto-install took it for a real job, found no sets\NON.lua, installed nothing and LATCHED for the session: every trigger then matched and silently equipped nothing (v35 skips a missing set in silence). Fixed at both ends -- M.jobReady rejects a not-ready job, and the latch records WHICH job it answered for, so a settling read re-fires the guard
                  -- 44: PINNED slots -- pinstate.lua forces a named item into a slot at TOP priority (above the craft overlay), scoped to All or to named triggers; the engine WEARS the pin, so nothing removes it
                  -- 43: reserved slots (RSlot) resolved at equip time -- a Body that takes Head away (Ryl.Ftm. Tunic) drops the reserved slot instead of flapping with the server forever; worn pieces reserve too
-- 42: lockstyle apply builds the 0x053 itself (server reads ItemNo+EquipKind only -- bags never scanned; all 9 slots sent, unnamed frozen to worn gear); preview = locally injected GRAP_LIST 0x051; the v39 equip-preview overlay (lspreview.lua reader) is gone from the engine
                  -- 41: lockstyle boxes live in the JOB ENTRY (profiles\<Name>\lockstyles\<JOB>.lua; reads fall back v40 profile file, then global)
                  -- 35: matched-but-missing set no longer chat-warns (Triggers tab shows it in red)
                  -- 34: modestate __loadstamp -- the GUI's red Reload-LAC button watches it clear
                  -- 33: profile storage layer (dlac\profiles\<name>\; auto-install on load/job change; /dl profile)
                  -- 32: engine self-swap (dispatch.lua hot-reloads like the trigger file)
                  -- 31: craft-gear OVERLAY on Default (engine equips craft gear; craftstate.lua)
                  -- 30: AutoCraft goal reads manifest craftGoal (single silent variable, no mode)

-- Colored [dlac] chat output (chatfmt); plain print when unavailable. The shadowed
-- `print` re-heads "[dlac] ..."-prefixed lines with the colored header.
local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local print = (_cfok and type(_cfmt.print) == 'function') and _cfmt.print or print;
local function printwarn(s) if _cfok then _cfmt.warn(s); else print('[dlac] ' .. s); end end
local function printerr(s)  if _cfok then _cfmt.err(s);  else print('[dlac] ' .. s); end end

-- The profile storage layer (profiles.lua, seeded next to this file). Guarded:
-- a stale char folder without it degrades to the legacy layout everywhere.
local _pok, _prof = pcall(require, 'dlac\\profiles');
_pok = _pok and type(_prof) == 'table';

-- Native-MP calculator (data/nativemp.lua): the server's base-pool formula.
-- The Oneiros resolver aims its latent threshold with it at resolve time.
local _nmok, _nmp = pcall(require, 'dlac\\data\\nativemp');
if not (_nmok and type(_nmp) == 'table') then _nmp = nil; end

-- The banded-ladder core (maxmp v2, engine v88) -- pure module, guarded like
-- nativemp: absent means the maxmp mode reports no data instead of erroring.
local _mbok, _mpb = pcall(require, 'dlac\\feature\\mpbands');
if not (_mbok and type(_mpb) == 'table') then _mpb = nil; end

-- Zone table (data/zones.lua): the curated town set behind the inTown condition
-- (v84). town = server CITY zonetype + Nashmau, minus combat-staging CITY zones
-- (see tools/gen_zones.py). A missing/old file just means inTown never matches
-- (graceful degrade, the nativemp rule). Flattened to a zid -> true lookup once.
local TOWN = {};
do
    local _zok, _zones = pcall(require, 'dlac\\data\\zones');
    if _zok and type(_zones) == 'table' then
        for zid, z in pairs(_zones) do
            if type(z) == 'table' and z.town then TOWN[zid] = true; end
        end
    end
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
M.modes = {};   -- mode state: lower(name) -> true (toggle) or 'Value' (cycle).
                -- DLAC-OWNED: written to modestate.lua on every change and read BACK
                -- when the engine loads, so flags survive a Reload LAC exactly like
                -- they survive a dlac reload -- ONE lifetime rule instead of two
                -- Lua-state lifetimes. maxmp drops itself on a job change (tick).
M.modesRev = 0; -- bumped on every mode change: utils.rebuildSets re-flattens the
                -- Dynamic sets when it moves (mode-gated entries pick differently).
-- Session-only SLOT LOCKS: lower(lac slot name) -> true. Locks are the draggable
-- VETO ROW in the Arbiter rank (ADR 0012, step 3): a locked slot is stripped from
-- every layer ranked BELOW the Locks row (the Triggers floor + any claimant under
-- it), while a claimant ranked ABOVE it (Pins, by default) punches through.
-- /dl lock drives it; the Equipped tab's "Lock when equipped" sends that command.
-- Mirrored to modestate.lua (__locks) for GUI display, never restored from disk.
--
-- `or {}`, NOT `= {}`. This used to be a plain reset, which made an engine
-- SELF-SWAP -- the 2s content check that carries a `git pull` or a reseed into the
-- running engine -- silently unlock all sixteen slots mid-session. Nobody asked for
-- it and nothing announced it beyond a parenthetical in the swap line. ADR 0021
-- called the leak out while rejecting a lock-based naked ("M.locks is wiped by
-- every engine self-swap... a background reseed would silently re-dress you"), and
-- ADR 0022 put a LOCKED SET on this same row -- so half the row surviving a reseed
-- while the other half evaporated was the last reason to leave it.
--
-- A LAC reload still clears them: that is a fresh Lua state, so M itself is new and
-- the field is nil. Locks remain session-only and are still never read back from
-- the mirror.
--
-- WHAT DOES end them (v124, Henrik: "I don't want locks to outlive a relog, it
-- should not outlive a main job change nor a log"): M.worldWatch, the same watch
-- that drops the strip and a locked set. Removing the self-swap wipe above took
-- away an accident that LOOKED like a lifetime rule; this is the real one, and it
-- is now the same rule for all three ways of deliberately holding gear still.
M.locks = M.locks or {};

-- DISABLED SLOTS (ADR 0024) -- "dlac, hands off". `/dl disable <slot|all>`, the
-- native-era answer to /lac disable. NOT a lock and NOT a claim to dress: a lock
-- is a VETO INSIDE the rank walk (a claimant above it punches through), and this
-- has to hold against every rank there is, the strip included. So it is the
-- CEILING -- the mirror of the Triggers floor -- and it is enforced at the write
-- seam rather than in the walk: engineEquipSet drops these slots from every set
-- that leaves, so no layer, no post-pass and no future caller can reach them.
--
-- `or {}`, not `= {}`, for M.locks's reason one step stronger: an engine
-- SELF-SWAP (the 2s content check -- a git pull, a reseed) must not silently hand
-- your slots back to the engine while you are mid-swap in the gear menu. A fresh
-- Lua state starts enabled (M is new). Lifetime is otherwise M.worldWatch's, the
-- one Henrik gave all three holds on 2026-07-26: a main job change or leaving the
-- world releases it, and it is never written to disk.
M.disabledSlots = M.disabledSlots or {};

-- NAKED (ADR 0021): the strip flag. `= (M.nakedArmed == true)` -- the M._loadStamp
-- idiom at the top of this file, and deliberately NOT `M.nakedArmed = false` the way
-- M.locks is wiped above. The difference IS the feature: an engine SELF-SWAP (the 2s
-- content check -- a git pull, a reseed) re-executes this file against the SAME module
-- table, so the flag reads itself back and survives. A background reseed silently
-- re-dressing you is the hazard that rules out every other home for this state.
--
-- A FRESH LUA STATE (Reload LAC, /addon reload) starts you dressed, because M is new
-- and the field is nil. A RELOG DOES NOT -- an Ashita addon survives a logout (see
-- pinwatch.loadPinState's header, which re-keys pins on the character dir for exactly
-- this reason) and LuaAshitacast never clears package.loaded either, so neither engine
-- gets a new state when you change characters. That gap is closed by the tick, which
-- disarms on the character-select read (GetMainJob() == 0) -- the one place that sees
-- you leave the world. Logging in naked is the worst outcome this feature has; it is
-- handled there, not here.
--
-- Mirrored to modestate.lua as __naked for the GUI (the __locks contract: display
-- only, in the reserved __ namespace loadModeState skips, so it is never restored
-- from disk and can never collide with a user-defined Mode named "naked").
M.nakedArmed = (M.nakedArmed == true);

-- LOCKED SET (ADR 0022): what `/dl lock set ...` froze, or nil. Self-swap
-- survival is the same idiom as nakedArmed above and the reason is one step more
-- urgent: a git pull firing the 2s content check mid-Incursion must not hand
-- your gear back. Deliberately NOT reset the way M.locks is wiped two blocks up
-- -- the two halves of the Locks row have different lifetimes ON PURPOSE, a
-- lock being an incidental "right now" decision and a locked set a deliberate
-- typed one. A fresh Lua state starts unlocked (M is new, the field is nil); a
-- RELOG does not, so nakedWorldWatch drops it on the character-select read for
-- exactly the reasons it drops the strip. Mirrored to modestate as __held.
M.lockedSet = M.lockedSet;

local saveModeState;   -- defined in the mode section below; used by the trigger loader

-- The 16 lac slot names (also the /dl lock vocabulary; 'all' fans out to every one).
-- THE ARBITER MODULE (ADR 0027, stage 3): the pure decision core, extracted
-- to gearrbiter.lua -- the slot + rank vocabulary, the reservation family,
-- the resolve/explain family and arbitrate(). Hard require on purpose:
-- without it there is no decider, and failing loud beats deciding wrong (the
-- test harnesses seed package.loaded before loading this file). Every old
-- M.* seam is re-exported below, so callers and tests keep their doors.
local ARB = require('dlac\\gear\\arbiter');

local LAC_SLOTS = ARB.LAC_SLOTS;
local LAC_SLOT_OK = {};
for _, s in ipairs(LAC_SLOTS) do LAC_SLOT_OK[s] = true; end

-- The same 16 in the EQUIP vocabulary's proper case. Not interchangeable with
-- LAC_SLOTS above: gear\equipcore.lua's SLOT_ID map is case-SENSITIVE (the native
-- engine's equipSet and planSet both key through it), while LuaAshitacast's
-- gData.GetEquipSlot is case-insensitive. A claim written in lock-case would
-- therefore work in LAC and silently strip NOTHING natively -- the worst kind of
-- divergence, because the mode that ships today is the one that breaks. Test NK3
-- pins the case; NK1 pins the two lists to the same 16 slots.
local LAC_SLOTS_CANON = ARB.LAC_SLOTS_CANON;
M._lacSlotsCanon = LAC_SLOTS_CANON;

-- PetAction is DLAC-SYNTHESIZED. No LuaAshitacast version calls a pet handler:
-- the upstream tutorial's HandlePetAction is a DIY pattern ("this function will
-- not be called by LuaAshitacast, you'll have to call it yourself" -- profiles
-- were meant to poll gData.GetPetAction from HandleDefault). The engine tick IS
-- that pattern, centralized: it dispatches once per pet-action start.
local EVENTS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot', 'PetAction' };
local EVENT_CANON = {};
for _, e in ipairs(EVENTS) do EVENT_CANON[string.lower(e)] = e; end
M.EVENTS = EVENTS;
function M.canonEvent(e) return EVENT_CANON[string.lower(tostring(e))]; end

-- "NON" IS NOT A JOB, and this is the check that says so. Field-caught 07-15
-- (Hunklor, /dl instdiag):
--     latches=tick 1: job=NON hasSets=false | tick 17: job=SAM hasSets=true
-- gData resolves the main job through the resource manager --
-- GetString('jobs.names_abbr', GetMainJob()) -- so at login, when the player block
-- is not ready yet, GetMainJob() reads 0 (= None) and that stringifies to "NON".
-- "NON" is neither '' nor '?', so a guard testing only those took it for a real
-- job: the profile auto-install went looking for sets\NON.lua, found nothing,
-- installed nothing, and LATCHED -- permanently, because the latch did not record
-- which job it had answered for. The read settles ~6.4s later (16 ticks) and
-- nobody looks again: you play a whole session on an empty .Dynamic with every
-- trigger silently equipping nothing. Nobody has a NON.lua, so this bit every
-- migrated character equally.
--
-- Gate on the ID, not the string -- 0 is the authoritative "not ready" signal, and
-- readJobSets already did exactly this. The name check stays as belt-and-braces:
-- the id and the resolved string come from two different reads.
function M.jobReady(jobId, jobName)
    if jobId == nil or jobId == 0 then return false; end
    if type(jobName) ~= 'string' then return false; end
    if jobName == '' or jobName == '?' or jobName == 'NON' then return false; end
    return true;
end

local _trig  = { path = nil, raw = nil, rules = nil, lastCheck = -1, err = nil };
local _boundKeys = {};   -- bind key -> queued /bind command (the degraded twin path below)

-- Install this job's mode keybinds AS A GROUP, through the one registry
-- (feature\keybinds -- Henrik 2026-07-30: "if a bind exists, it needs to be
-- able to tell where and with what and block them from binding over it").
--
-- The registry buys three things this loader could never do alone: a key held
-- by another feature is REFUSED and named instead of silently stolen; the
-- previous job's mode binds are RELEASED (nothing here ever unbound one, so
-- they used to outlive their job); and an unchanged bind is left completely
-- alone, which is the /bind-storm guard this loader grew in the field -- it
-- re-parses on every '/dl triggers reload', and the automations rescan pings
-- one after every inventory sync.
--
-- Entries are sorted before they go in: `pairs` over the mode table has no
-- order, and two modes contending for one key must resolve the same way twice.
-- The degraded path (the seeded engine twin, headless) keeps the old dedupe
-- map, so a copy that cannot reach the registry still binds exactly as before.
local function installModeBinds(entries)
    table.sort(entries, function(a, b) return a.owner < b.owner; end);
    local kb = nil;
    pcall(function() kb = require('dlac\\feature\\keybinds'); end);
    if type(kb) == 'table' and type(kb.syncGroup) == 'function' then
        pcall(function() kb.syncGroup('mode:', entries); end);
        return;
    end
    for _, e in ipairs(entries) do
        local bindCmd = ('/bind %s %s'):format(e.key, e.command);
        if _boundKeys[e.key] ~= bindCmd then
            _boundKeys[e.key] = bindCmd;
            pcall(function() AshitaCore:GetChatManager():QueueCommand(-1, bindCmd); end);
        end
    end
end
local _trace = {};   -- event -> { time, action, sig, lines = {...} }
-- The DECISION RING (v152, the Arbiter Monitor's history): every dispatch whose
-- OUTCOME moved -- the resolved items, or any slot's winning claimant -- appends
-- ONE record; an identical outcome appends nothing (Henrik: "only push changes,
-- no need to flood with the same data needlessly"). Newest LAST.
local _decisions = {};
local _decSeq = 0;
M.DECISION_CAP = 50;
-- The ACTION FEED (v154, the stream's anchor signal): every non-Default
-- dispatch appends one stub -- fine-grained, unlike the 1-second _trace stamp
-- -- so the observer can tell "an action dispatched and changed nothing"
-- (anchor) from silence. decSeq links a stub to the decision it produced,
-- when it produced one.
local _actions = {};
local _actSeq = 0;
M.ACTION_CAP = 32;
-- Trigger-monitor feed (v55): the last 5 fired-rule lines, newest first. The
-- ring updates on every CHANGE of what fired (retrace); the tick flushes it to
-- firedstate.lua (GUI display only) at most once per pass, so Precast/Midcast
-- bursts cost one write, not three.
local _fired = {};
local _firedDirty = false;
local _monQ = {};   -- fired lines awaiting the live stream -- drained ONE per frame (v58)
local saveFiredState;   -- defined with the mode-state block below (needs charDir/writeFile)

-- (inLac() died in the purge, Phase 2: there is no LuaAshitacast-hosted copy
-- of this module anymore -- the addon state is the engine, the only one.)

-- NATIVE ENGINE (feature/native-engine, v111): when the native flag is on,
-- the ADDON-state copy of this module -- inert since v1 -- becomes the ACTIVE
-- engine: feature\equipengine supplies the timing service LuaAshitacast used
-- to (block action -> Precast -> re-inject -> Midcast) and the equip door
-- (equipSet -> the per-event buffer -> gear\equipcore -> 0x050/0x051).
-- Returns the ARMED equipengine or nil; never arms inside LAC's state
-- (equipengine itself refuses there -- two interceptors is the hazard the
-- tripwire exists for).
local function nativeEngine()
    local ok, eng = pcall(require, 'dlac\\feature\\equipengine');
    if not ok or type(eng) ~= 'table' or type(eng.nativeOn) ~= 'function' then return nil; end
    local ok2, on = pcall(eng.nativeOn);
    if not ok2 or on ~= true then return nil; end
    return eng;
end

-- "Is THIS copy the active engine?" -- when the native engine is armed (the
-- tripwire can disarm it). The dispatch entry, the outer machinery block and
-- the command printers all gate on this.
local function engineActive() return nativeEngine() ~= nil; end

-- Drop every DISABLED slot from a resolved set (ADR 0024). Returns the set
-- unchanged when nothing is disabled -- the overwhelmingly common case pays one
-- `next()` -- and a filtered COPY otherwise, so a caller's table is never mutated
-- (the dispatch hands the same tables to /dl why attribution afterwards).
--
-- Case-insensitive on purpose: the vocabulary arrives in BOTH cases here. Sets
-- and claims are canonical ('Main'), /dl lock and this command speak lac-case
-- ('main'), and gear\equipcore's SLOT_ID map is case-SENSITIVE -- so comparing
-- raw keys would disable a slot in one engine and silently miss it in the other,
-- which is exactly the divergence NK3 exists to catch. Keys starting `__` are
-- set metadata, never slots, and pass through untouched.
local function stripDisabled(set)
    if type(set) ~= 'table' then return set; end
    if next(M.disabledSlots) == nil then return set; end
    local out, hit = nil, false;
    for k in pairs(set) do
        local ks = tostring(k);
        if string.sub(ks, 1, 2) ~= '__' and M.disabledSlots[string.lower(ks)] == true then
            if not hit then
                hit, out = true, {};
                for k2, v2 in pairs(set) do out[k2] = v2; end
            end
            out[k] = nil;
        end
    end
    return hit and out or set;
end
M._stripDisabled = stripDisabled;   -- test seam (DS*)

-- The one equip write seam: LAC state -> gFunc.EquipSet; native -> the
-- equipengine buffer (flushed by its fireEvent, ClearBuffer/ProcessBuffer
-- parity). Every resolved set leaves through here.
--
-- AND SO THE DISABLED FILTER LIVES HERE (ADR 0024), not in the rank walk. Putting
-- it in equipResolved's per-slot chain would have been the obvious home and is
-- not enough: the whole-table post-passes that run AFTER that chain write slots
-- the set never named (a MaxMP battery, trinket-vs-ranged's worn-Ammo
-- displace), so a disabled slot nil'd early can be put straight back a few lines
-- later. One filter on the way out covers the chain, every post-pass, and any
-- caller this seam grows later -- which is what "dlac does not touch that slot"
-- has to mean to be worth typing.
local function engineEquipSet(set)
    set = stripDisabled(set);
    local eng = nativeEngine();
    if eng ~= nil then
        pcall(eng.equipSet, set);
    end
    -- (engine unarmed -- tripwire -- equips nothing: the gFunc.EquipSet route
    -- died in the purge, Phase 2, with the LAC-hosted engine.)
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function ci(a, b)   -- case-insensitive string equality (nil-safe)
    return type(a) == 'string' and type(b) == 'string' and string.lower(a) == string.lower(b);
end

local function readFile(p)
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end
local function writeFile(p, t)
    local f = io.open(p, 'w'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end

-- The dlac data dir: profiles.dataDir() -- the ONE storage-home authority
-- (v110: it is mode-aware, so the native-engine config move under
-- config\addons\dlac\ carries this whole file with it). The inline composition
-- below is only the fallback for a stale char folder missing profiles.lua --
-- and that fallback IS the legacy home (a folder that old predates the move).
local function charDir()
    if M._charDirOverride ~= nil then return M._charDirOverride; end   -- headless test seam
    if _pok and type(_prof.dataDir) == 'function' then
        local ok, d = pcall(_prof.dataDir);
        if ok and d ~= nil then return d; end
    end
    local name, id;
    if gState ~= nil and gState.PlayerName ~= nil and gState.PlayerId ~= nil then
        name, id = gState.PlayerName, gState.PlayerId;
    else
        pcall(function()
            local party = AshitaCore:GetMemoryManager():GetParty();
            name = party:GetMemberName(0);
            id   = party:GetMemberServerId(0);
            if name == '' then name = nil; end
        end);
    end
    -- (purge Phase 3: no legacy-path fallback -- profiles.dataDir is the one
    -- authority, and composing a luashitacast path here would resurrect it.)
    return nil;
end

-- ---------------------------------------------------------------------------
-- '/dl debug' engine plumbing (v105 handoff, v106 capture window).
-- The addon state assembles the transferable report file but cannot see THIS
-- state -- engine halves land in <char>\dlac\debug-<topic>-engine.txt, first
-- line an os.time() stamp the merger uses to judge freshness, lines BARE (the
-- file's '== engine half ==' section heads them).
-- ---------------------------------------------------------------------------
local function writeDebugHandoff(name, lines)
    pcall(function()
        local dir = charDir();
        if dir == nil then return; end
        local f = io.open(dir .. name, 'wb');
        if f == nil then return; end
        f:write(tostring(os.time()) .. '\n' .. table.concat(lines, '\n') .. '\n');
        f:close();
    end);
end

-- The capture window (v106, Henrik: "let it run for 30-60 seconds... so you
-- can capture all the events"): '/dl debug ls [seconds]' opens it in BOTH
-- states (same command, same clamp -- twin constants, addon twin in
-- feature/debug.lua M._dur); while open, the apply branch notes every
-- receipt/refusal/send into the timeline; the dispatch tick flushes the
-- handoff at window end (snapshot + timeline), and the addon's merger reads
-- it ~4s after that.
-- (The two-state COMMAND BRIDGE died in the purge, Phase 2: M._lsDbg,
-- _lsDbgNote, _reqFire, _reqSpec, _lsDbgFlushLines, the request-file watch
-- and the engine lockstyle halves all existed to cross from the addon state
-- into LuaAshitacast's -- one state now, one door. feature\lockstyleapply
-- owns the native apply with its own byte-for-byte pure core.)

-- ---------------------------------------------------------------------------
-- Cached per-character state-file reader -- the ONE implementation behind the
-- auto/acc/craft/helm/fish/pin caches (the GUI->engine statefile handoff, v70;
-- they were six near-identical clones and had already drifted). Throttle: one
-- disk check per second; missing file = state off (nil); pre-login (no char
-- dir) keeps whatever is cached. POLICY, unified from the pin reader's field
-- lesson (v44): a torn/corrupt write DROPS the state -- cache.raw is already
-- the corrupt text, so keeping the last good table would glue it on forever
-- (the raw-compare short-circuits every later call and nothing could clear
-- it, not even the watcher's clear-on-load). The next good write self-heals.
-- The TRIGGER file deliberately does NOT ride this: it is hand-editable, so
-- mid-typo it keeps the previous rules and says so (ensureLoaded below).
-- ---------------------------------------------------------------------------
local function ensureStateFile(cache, filename)
    local now = os.time();
    if now == cache.lastCheck then return cache.data; end
    cache.lastCheck = now;
    local dir = charDir();
    if dir == nil then return cache.data; end
    local raw = readFile(dir .. filename);
    if raw == nil then cache.raw, cache.data = nil, nil; return nil; end
    if raw == cache.raw then return cache.data; end
    cache.raw = raw;
    local chunk = (loadstring or load)(raw, '@' .. filename);
    if chunk == nil then cache.data = nil; return nil; end
    local ok, t = pcall(chunk);
    if ok and type(t) == 'table' then cache.data = t; else cache.data = nil; end
    return cache.data;
end
M._ensureStateFile = ensureStateFile;   -- headless seam: the corrupt-drop policy pinned once (SF*)

-- The CURRENT main job's trigger file, profile-aware. Reads fall back per file:
-- the active profile's triggers\<JOB>.lua when it exists, else the legacy
-- dlac\triggers\<JOB>.lua; when NEITHER exists yet, the path where writes should
-- land (profile storage once it exists, legacy before). nil pre-login.
local function triggersPath()
    local dir = charDir();
    if dir == nil then return nil; end
    local job;
    pcall(function() job = gData.GetPlayer().MainJob; end);
    if type(job) ~= 'string' or job == '' or job == '?' then return nil; end
    local lp = dir .. 'triggers\\' .. job .. '.lua';
    if _pok then
        local pp = _prof.triggersPath(job);
        if pp ~= nil then
            if readFile(pp) ~= nil then return pp; end
            if readFile(lp) ~= nil then return lp; end
            return _prof.storageExists() and pp or lp;
        end
    end
    return lp;
end
M.triggersPath = triggersPath;

-- ---------------------------------------------------------------------------
-- Matchers (v1 condition vocabulary — design doc table). Keyed by lowercased
-- condition name; each takes (value, ctx) and must return true to pass. All the
-- conditions in one `when` AND together; separate Triggers overlay (ADR 0003).
-- ---------------------------------------------------------------------------

-- Day/weather opposition: the element that BEATS yours penalizes your spell on its
-- day / in its weather (Fire<Water<Thunder<Earth<Wind<Ice<Fire; Light<->Dark).
-- LAC has no gData.GetElementalOpposition, so we carry the wheel ourselves.
local OPPOSED = {
    fire = 'Water', ice = 'Fire', wind = 'Ice', earth = 'Wind',
    thunder = 'Earth', water = 'Thunder', light = 'Dark', dark = 'Light',
};

-- Net day+weather sign for one element: +1 per matching day/weather, -1 per opposing
-- one. Also powers the /dl env diagnostic.
local function netForElement(el)
    local n = 0;
    if type(el) ~= 'string' then return n; end
    local opp = OPPOSED[string.lower(el)];
    pcall(function()
        local env = gData.GetEnvironment();
        if env == nil then return; end
        if ci(env.DayElement, el)      then n = n + 1;
        elseif ci(env.DayElement, opp) then n = n - 1; end
        if ci(env.WeatherElement, el)      then n = n + 1;
        elseif ci(env.WeatherElement, opp) then n = n - 1; end
    end);
    return n;
end

-- The current action's net sign, cached on ctx (computed at most once per dispatch).
local function netDayWeather(ctx)
    if ctx.dw ~= nil then return ctx.dw; end
    ctx.dw = netForElement(ctx.action and ctx.action.Element);
    return ctx.dw;
end

-- Does the current WEATHER's element equal the action's element? A plain match --
-- NOT the day+weather net above. Reads the SAME env the obi uses
-- (gData.GetEnvironment().WeatherElement), which already folds a Scholar's own
-- storm buff over the zone weather (Firestorm etc.), so a self-storm counts --
-- exactly what CatsEyeXI's ALACRITY_CELERITY_EFFECT gate keys on. The weather
-- element is read once and cached on ctx.wel. Returns true (match), false (a real
-- non-match, incl. clear/'None' weather), or nil when there is no action element
-- (Default / Non-Elemental) or the weather is unreadable -- nil makes the matcher
-- fire on NEITHER polarity, never blind.
local function weatherMatchesAction(ctx)
    local el = ctx.action and ctx.action.Element;
    if type(el) ~= 'string' or ci(el, 'Non-Elemental') then return nil; end
    if ctx.wel == nil then
        local w = '';
        pcall(function()
            local env = gData.GetEnvironment();
            if env ~= nil and type(env.WeatherElement) == 'string' then w = env.WeatherElement; end
        end);
        ctx.wel = w;   -- cached once per dispatch; '' = unreadable
    end
    if ctx.wel == '' then return nil; end
    return ci(ctx.wel, el);
end

-- Does the current DAY's element equal the action's element? The obi's positive
-- DAY term standing alone -- no weather, no opposition (that whole sum is
-- dayWeatherBonus). Gear that pays out on the day ALONE (the Vana'diel weekday
-- latents) is tracked by neither the net nor weatherMatch, so it gets its own
-- primitive. Unlike weather there is no "clear day": every one of the eight
-- weekdays carries an element (Firesday..Darksday), so a day we can READ is
-- always a real element and only a failed read is unknown. The day element is
-- read once and cached on ctx.del ("day element", the ctx.wel pattern). Returns
-- true (match), false (a real non-match), or nil when there is no action element
-- (Default / Non-Elemental) or the day is unreadable -- nil makes the matcher
-- fire on NEITHER polarity, never blind.
local function dayMatchesAction(ctx)
    local el = ctx.action and ctx.action.Element;
    if type(el) ~= 'string' or ci(el, 'Non-Elemental') then return nil; end
    if ctx.del == nil then
        local d = '';
        pcall(function()
            local env = gData.GetEnvironment();
            if env ~= nil and type(env.DayElement) == 'string' then d = env.DayElement; end
        end);
        ctx.del = d;   -- cached once per dispatch; '' = unreadable
    end
    if ctx.del == '' then return nil; end
    return ci(ctx.del, el);
end

-- Debuff song families (Bard Song + one of these words in the name = Debuff;
-- any other Bard Song = Buff). Extend as CatsEyeXI adds custom songs.
local DEBUFF_SONGS = { 'requiem', 'lullaby', 'elegy', 'finale', 'threnody', 'virelai', 'nocturne' };

local function nameContains(ctx, word)
    local nm = ctx.action and ctx.action.Name;
    if type(nm) ~= 'string' or type(word) ~= 'string' then return false; end
    return string.find(string.lower(nm), string.lower(word), 1, true) ~= nil;
end

-- Public mode-condition check, shared by the trigger matcher AND set-entry gating
-- (utils.BuildDynamicSets: per-item `mode = '...'` wrappers). 'Weapon:Melee' -> the
-- cycle mode holds that value; a bare name -> toggle ON (or any cycle value).
-- A LIST of conditions is OR: active while ANY entry matches (two values of one
-- cycle can never be active together, so OR is the only coherent list reading).
-- `modes` defaults to the live session state; the GUI passes the modestate.lua
-- mirror instead (it lives in a different Lua state).
function M.modeActive(cond, modes)
    modes = modes or M.modes;
    if type(cond) == 'table' then
        for _, c in ipairs(cond) do
            if M.modeActive(c, modes) then return true; end
        end
        return false;
    end
    local s = tostring(cond);
    local p = string.find(s, ':', 1, true);
    if p ~= nil then
        local cur = modes[string.lower(string.sub(s, 1, p - 1))];
        return type(cur) == 'string' and ci(cur, string.sub(s, p + 1));
    end
    return modes[string.lower(s)] ~= nil;
end

-- Public group-condition check (ADR 0009), the group analogue of M.modeActive.
-- A Group is a named, untyped list of action names stored per Job entry beside
-- Modes; the condition fires when the current action's name is a member of the
-- named group. `cond` may be a single group name or a LIST of names (OR) --
-- exactly the one-of semantics `mode` has. Both group names and member names
-- match case-insensitively. `groups` defaults to the loaded job's Groups
-- (`_trig.groups`, raw `{ Name = { 'Action', ... } }`); tests pass one explicit.
function M.groupMatch(cond, actionName, groups)
    groups = groups or _trig.groups;
    if type(cond) == 'table' then
        for _, c in ipairs(cond) do
            if M.groupMatch(c, actionName, groups) then return true; end
        end
        return false;
    end
    if type(groups) ~= 'table' or type(actionName) ~= 'string' then return false; end
    for name, members in pairs(groups) do
        if ci(name, cond) and type(members) == 'table' then
            for _, m in ipairs(members) do
                if ci(m, actionName) then return true; end
            end
        end
    end
    return false;
end

-- ---------------------------------------------------------------------------
-- Player-state gates (v53): live vitals + active status effects, so a trigger
-- can say "this set only below 50% HP" or "only while Sleep is on me". Vitals
-- come off ctx.player (gData.GetPlayer: HPP / MPP / TP); buffs come from a
-- per-dispatch cache built from the client's own buff array + string table --
-- ONE read per dispatch no matter how many rules gate on buffs. Strict
-- compares; unreadable state never matches EITHER polarity (buff and buffNot
-- both stay quiet on a failed read), so a bad read can't flap gear.
-- ---------------------------------------------------------------------------
local function playerNum(ctx, field)
    if ctx.player == nil then return nil; end
    return tonumber(ctx.player[field]);
end

-- The ACTIVE-BUFF set for this dispatch: { [lower(name)] = true, [id] = true }.
-- Tests inject ctx.buffs directly; live it is built once and memoized on ctx.
-- Returns nil when the read fails (pre-login, headless) = "unknown".
local function activeBuffs(ctx)
    if ctx.buffs ~= nil then return ctx.buffs; end
    local set = nil;
    pcall(function()
        local buffs = AshitaCore:GetMemoryManager():GetPlayer():GetBuffs();
        local resx  = AshitaCore:GetResourceManager();
        local s = {};
        for _, id in pairs(buffs) do
            id = tonumber(id);
            if id ~= nil and id > 0 and id < 1000 then
                s[id] = true;
                local nm = resx:GetString('buffs.names', id);
                if type(nm) == 'string' then
                    nm = string.gsub(nm, '%z+$', '');
                    if #nm > 0 then s[string.lower(nm)] = true; end
                end
            end
        end
        set = s;
    end);
    ctx.buffs = set;   -- nil stays nil -> retried next dispatch
    return set;
end

local function buffActive(ctx, v)
    local set = activeBuffs(ctx);
    if set == nil then return nil; end            -- unknown, deliberately not false
    local id = tonumber(v);
    if id ~= nil then return set[id] == true; end
    return set[string.lower(tostring(v))] == true;
end

-- Is the current action aimed at ME? (v81.) Tri-state, memoized on ctx: true /
-- false, or nil = unknown (no action in flight -- the Default handler -- or a
-- failed read), and unknown matches NOTHING, so a bad read can never flap gear
-- (the buff-cache rule). Tests inject ctx.targetSelf; live it compares the
-- action target's entity index (LAC keeps the outgoing action packet's target
-- index on PlayerAction for Spell/Ability/Item/WS/Ranged, set before Precast)
-- against my own party index -- one read per dispatch.
local function targetIsSelf(ctx)
    if ctx.targetSelf ~= nil then return ctx.targetSelf; end
    local r = nil;
    pcall(function()
        local tgt = gData.GetActionTarget();
        if tgt == nil or tonumber(tgt.Index) == nil then return; end
        local me = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
        if tonumber(me) == nil or tonumber(me) == 0 then return; end
        r = (tonumber(tgt.Index) == tonumber(me));
    end);
    ctx.targetSelf = r;   -- nil stays nil -> retried next matcher call
    return r;
end

-- The zone id I'm standing in (v84), memoized on ctx like targetSelf. nil =
-- unknown (a failed read, or headless) and unknown matches NEITHER inTown
-- polarity, so a bad read never flaps gear (the buff-cache rule). Zone 0 is the
-- demo stub, never a real player location, so it also reads as unknown. Tests
-- inject ctx.zone directly; live it is one party-memory read per dispatch.
local function zoneOf(ctx)
    if ctx.zone ~= nil then return ctx.zone; end
    local z = nil;
    pcall(function()
        z = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    end);
    if type(z) ~= 'number' or z == 0 then z = nil; end
    ctx.zone = z;   -- nil stays nil -> retried next matcher call
    return z;
end

-- Threshold matcher factory: one field off ctx.player, strict compare, junk
-- or unreadable values never match.
local function numGate(field, below)
    return function(v, ctx)
        local n, t = tonumber(v), playerNum(ctx, field);
        if n == nil or t == nil then return false; end
        if below then return t < n; end
        return t > n;
    end
end

local MATCHERS = {
    any             = function() return true; end,
    status          = function(v, ctx) return ctx.player ~= nil and ci(ctx.player.Status, v); end,
    moving          = function(v, ctx) return ctx.player ~= nil and ((ctx.player.IsMoving == true) == (v == true)); end,
    mode            = function(v) return M.modeActive(v); end,
    name            = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Name, v); end,
    contains        = function(v, ctx) return nameContains(ctx, v); end,   -- substring: 'Madrigal' hits Blade+Sword
    family          = function(v, ctx) return nameContains(ctx, v); end,   -- legacy alias of contains
    group           = function(v, ctx) return ctx.action ~= nil and M.groupMatch(v, ctx.action.Name); end,
    skill           = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Skill, v); end,
    magictype       = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Type, v); end,
    abilitytype     = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Type, v); end,
    element         = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Element, v); end,
    dayweatherbonus = function(v, ctx)
        if v == true  then return netDayWeather(ctx) > 0;  end
        if v == false then return netDayWeather(ctx) <= 0; end
        return netDayWeather(ctx) >= (tonumber(v) or 1);
    end,
    -- Weather-element MATCH (not the day+weather net above): the current weather's
    -- element equals the action's element. Reads the same env the obi does, so a
    -- Scholar's own storm counts. v=true requires a match, v=false requires a real
    -- non-match; unknown weather / no action element matches NEITHER (nil result).
    weathermatch = function(v, ctx)
        local m = weatherMatchesAction(ctx);
        if m == nil then return false; end
        return m == (v == true);
    end,
    -- Day-element MATCH (v156), weatherMatch's sibling: the CURRENT day's element
    -- equals the action's element. The obi's day term alone -- no weather, no
    -- opposition -- for gear whose bonus keys on the day and nothing else.
    -- v=true requires a match, v=false requires a real non-match; unknown day /
    -- no action element matches NEITHER (nil result).
    daymatch = function(v, ctx)
        local m = dayMatchesAction(ctx);
        if m == nil then return false; end
        return m == (v == true);
    end,
    songtype        = function(v, ctx)
        if ctx.action == nil or not ci(ctx.action.Type, 'Bard Song') then return false; end
        local debuff = false;
        for _, w in ipairs(DEBUFF_SONGS) do
            if nameContains(ctx, w) then debuff = true; break; end
        end
        if ci(v, 'Debuff') then return debuff; end
        if ci(v, 'Buff')   then return not debuff; end
        return false;
    end,
    -- Player-state gates (v54 canonical spellings -- the GUI's cascading Player
    -- menu). Thresholds are STRICT compares (Below = <, Above = >); Percent
    -- variants read the 0-100 percent, plain variants the raw value. buff /
    -- buffNot take a status-effect NAME (case-insensitive; "Sleep", "Refresh")
    -- or a numeric buff id.
    playerhpbelow        = numGate('HP',  true),
    playerhpabove        = numGate('HP',  false),
    playerhppercentbelow = numGate('HPP', true),
    playerhppercentabove = numGate('HPP', false),
    playermpbelow        = numGate('MP',  true),
    playermpabove        = numGate('MP',  false),
    playermppercentbelow = numGate('MPP', true),
    playermppercentabove = numGate('MPP', false),
    tpbelow = numGate('TP', true),
    tpabove = numGate('TP', false),
    -- v53 spellings (percent semantics): hidden aliases so day-one files load.
    hpbelow = numGate('HPP', true),  hpabove = numGate('HPP', false),
    mpbelow = numGate('MPP', true),  mpabove = numGate('MPP', false),
    buff    = function(v, ctx) return buffActive(ctx, v) == true; end,
    buffnot = function(v, ctx) return buffActive(ctx, v) == false; end,
    -- Pet conditions (v63): ctx.pet is gData.GetPet() -- nil with NO pet and
    -- when the pet's HPP is 0, so a dead pet reads as none (pet = false fires).
    -- petStatus/petName IMPLY existence: petStatus = 'Idle' must never match a
    -- petless job. Status strings are LAC's EntityStatus (Idle/Engaged/...).
    pet       = function(v, ctx) return (ctx.pet ~= nil) == (v == true); end,
    petstatus = function(v, ctx) return ctx.pet ~= nil and ci(ctx.pet.Status, v); end,
    petname   = function(v, ctx) return ctx.pet ~= nil and ci(ctx.pet.Name, v); end,
    -- Target condition (v81): WHO the action is aimed at. Vocabulary is a
    -- closed list the GUI mirrors as a dropdown -- v1: 'Self' (the action
    -- targets YOU; Henrik's case: a self-waltz wants VIT+CHR together, since
    -- waltz potency reads the TARGET's VIT beside your CHR -- waltzing someone
    -- else keeps the plain CHR set). Unknown target or unknown value matches
    -- nothing: a target-refined rule never fires blind.
    target = function(v, ctx)
        local slf = targetIsSelf(ctx);
        if slf == nil then return false; end
        if ci(v, 'Self') then return slf; end
        return false;
    end,
    -- inTown (v84): am I standing in a town? true = in a town (show off your
    -- gear while idle), false = NOT in a town (a "field idle" set). Town = the
    -- curated set in data/zones.lua (server CITY zonetype + Nashmau, minus
    -- combat-staging CITY zones). An unknown zone matches NEITHER polarity, so
    -- an inTown rule never fires blind (the target rule's discipline).
    intown = function(v, ctx)
        local z = zoneOf(ctx);
        if z == nil then return false; end
        return (TOWN[z] == true) == (v == true);
    end,
    -- Trigger-cases version guard (issue #126): stamped into the BODY of any rule
    -- serialized WITH a `cases` list. Always true, bottom tier -- it never changes
    -- whether a rule fires or what priority it gets. Its whole job is that an
    -- OLDER engine (git-pull skew, a shared file) sees an unknown condition key
    -- and drops the entire rule with the standard chat warn, instead of silently
    -- evaluating case 1 alone (the project law: refuse a rule you can't fully
    -- evaluate). This engine knows the key, so normalize STRIPS it on load -- it
    -- is a serialization artifact, never a real body condition.
    hascases = function() return true; end,
};
M._matchers = MATCHERS;   -- headless test seam (the _autoOverride idiom)

-- The lowercased guard key + its pretty spelling. One definition so normalize,
-- the serializer and the label all agree. PLAYER-VISIBLE (it lands in the
-- hand-editable trigger file) -- flagged in the PR for the maintainer's sign-off.
local CASES_GUARD = 'hascases';
M.CASES_GUARD = CASES_GUARD;

-- Specificity tier per condition -> the DEFAULT priority when a rule sets none
-- (ADR 0003). A rule's default is the MAX tier among its conditions ("the most
-- specific field governs"): skill+name defaults like a name rule. `moving` sits
-- above the statuses so Movement overlays Idle when both match (idle + moving).
-- Band 60 is reserved for Automations (M2, ADR 0004).
local TIER = {
    any = 10,
    status = 20, skill = 20, abilitytype = 20,
    -- Pet conditions (v63) sit between status and moving: a pet-refined rule
    -- ({status,pet} -> 22, petStatus -> 23) outranks its base status rule with
    -- no hand priority, and Movement still overlays a pet idle set. petName is
    -- identity -> the exact-name tier (50, next to `name` below).
    pet = 22, petstatus = 23,
    moving = 25,
    magictype = 30, element = 30, songtype = 30, dayweatherbonus = 30, weathermatch = 30,
    daymatch = 30,
    contains = 40, family = 40,
    group = 45,   -- baseline for many spells that share gear; a per-spell `name` (50) overrides it, and it beats contains/skill (ADR 0009)
    name = 50, petname = 50,
    -- target (v81) refines the exact action -- 'Curing Waltz III on MYSELF' is
    -- more specific than the name rule it rides on, so it overlays name (50)
    -- with no hand priority and still sits under the Automations band (60).
    target = 55,
    -- Player-state gates sit just under mode: "low HP" is nearly as deliberate
    -- as a hand toggle, and a mode-gated rule still edges it when both match.
    -- (hpbelow/... are the v53 alias spellings, kept loadable.)
    playerhpbelow = 95, playerhpabove = 95, playerhppercentbelow = 95, playerhppercentabove = 95,
    playermpbelow = 95, playermpabove = 95, playermppercentbelow = 95, playermppercentabove = 95,
    hpbelow = 95, hpabove = 95, mpbelow = 95, mpabove = 95,
    tpbelow = 95, tpabove = 95, buff = 95, buffnot = 95,
    -- inTown (v84) is a LOCATION gate, deliberate like a player-state one: a
    -- town show-off set should decisively overlay the plain Idle set, while an
    -- explicit mode still wins. Same 95 band.
    intown = 95,
    mode = 100,
    -- The cases guard sits at the BOTTOM tier (the specificity floor is 10, so a
    -- value at/under it can never become a rule's max) -- "the guard never moves
    -- auto-priority" (issue #126). It is stripped on load anyway; the tier only
    -- has to exist so normalize accepts the key instead of dropping the rule.
    hascases = 10,
};

-- Display-case spelling per (lowercased) condition key -- what the serializer writes
-- and the GUI shows. Matching is case-insensitive either way.
local PRETTY_KEY = {
    any = 'any', status = 'status', moving = 'moving', mode = 'mode',
    skill = 'skill', magictype = 'magicType', abilitytype = 'abilityType',
    element = 'element', songtype = 'songType', contains = 'contains',
    family = 'family', name = 'name', dayweatherbonus = 'dayWeatherBonus',
    weathermatch = 'weatherMatch', daymatch = 'dayMatch',
    group = 'group',
    hpbelow = 'hpBelow', hpabove = 'hpAbove', mpbelow = 'mpBelow',
    mpabove = 'mpAbove', tpbelow = 'tpBelow', tpabove = 'tpAbove',
    buff = 'buff', buffnot = 'buffNot',
    pet = 'pet', petstatus = 'petStatus', petname = 'petName',
    target = 'target', intown = 'inTown',
    playerhpbelow = 'playerHPBelow', playerhpabove = 'playerHPAbove',
    playerhppercentbelow = 'playerHPPercentBelow', playerhppercentabove = 'playerHPPercentAbove',
    playermpbelow = 'playerMPBelow', playermpabove = 'playerMPAbove',
    playermppercentbelow = 'playerMPPercentBelow', playermppercentabove = 'playerMPPercentAbove',
    hascases = 'hasCases',
};
M.PRETTY_KEY = PRETTY_KEY;

-- The default priority a rule with this `when` would get (specificity, ADR 0003).
-- Exposed so the GUI can show the effective number next to an "auto" priority.
-- cases (issue #126): the optional second tier. Each case is
-- { op = '&' | '|', when = { &-leg }, whenAny = { { |-entry }, ... } } -- the
-- SAME two legs a rule body has. Auto-priority is the max tier over EVERY leg of
-- EVERY case (the guard, tier 10, never wins).
function M.defaultPriority(when, whenAny, cases)
    local p = 10;
    local function scan(t)
        for k in pairs(t or {}) do
            local tt = TIER[string.lower(tostring(k))];
            if tt ~= nil and tt > p then p = tt; end
        end
    end
    if type(when) == 'table' then scan(when); end
    for _, e in ipairs(whenAny or {}) do
        if type(e) == 'table' then scan(e); end
    end
    for _, c in ipairs(cases or {}) do
        if type(c) == 'table' then
            scan(c.when);
            for _, e in ipairs(c.whenAny or {}) do
                if type(e) == 'table' then scan(e); end
            end
        end
    end
    return p;
end

-- ---------------------------------------------------------------------------
-- Trigger file: load, validate, normalize. Kept rules carry lowercased condition
-- keys, a resolved priority, their file order (tie-break), and a display label.
-- ---------------------------------------------------------------------------
-- The display label for a rule's conditions ("name=slow ii", "skill=singing",
-- "any"). ONE definition, used by normalize here AND by the GUI when it builds
-- pin scope keys -- the two Lua states must spell a label identically or a
-- scoped pin would never match. A condition value may be a LIST (when.mode can
-- hold several modes), and tostring() on a table yields its ADDRESS: different
-- in each state, and different again after every reload. Serialize lists by
-- value instead, sorted, so the label is stable everywhere.
local function condVal(v)
    if type(v) ~= 'table' then return tostring(v); end
    local parts = {};
    for _, x in ipairs(v) do parts[#parts + 1] = tostring(x); end
    table.sort(parts);
    return table.concat(parts, ',');
end
-- One tier's label: the `&` leg (sorted, joined '+', or 'any') then the `|` leg
-- entries (each sorted, joined '+') after '|', sorted. This IS the historical
-- ruleLabel over one { when, whenAny } pair -- factored so a case reuses it.
local function legLabel(when, whenAny)
    local parts = {};
    for k, v in pairs(when or {}) do
        parts[#parts + 1] = string.lower(tostring(k)) .. '=' .. condVal(v);
    end
    table.sort(parts);
    local base = (#parts > 0) and table.concat(parts, '+') or 'any';
    -- v54 OR entries ride the label after '|' -- sorted, so both states spell
    -- it identically; a rule WITHOUT whenAny labels exactly as before (pin
    -- scope keys from older sessions keep matching).
    local ors = {};
    for _, e in ipairs(whenAny or {}) do
        local ep = {};
        for k, v in pairs(e) do ep[#ep + 1] = string.lower(tostring(k)) .. '=' .. condVal(v); end
        table.sort(ep);
        if #ep > 0 then ors[#ors + 1] = table.concat(ep, '+'); end
    end
    table.sort(ors);
    if #ors > 0 then base = base .. '|' .. table.concat(ors, '|'); end
    return base;
end
function M.ruleLabel(when, whenAny, cases)
    local s = legLabel(when, whenAny);
    -- Cases (issue #126) extend the label deterministically: each case as
    -- '<op>(<its leg label>)', sorted. A case-LESS rule (cases nil/empty) skips
    -- this entirely, so its label is BYTE-FOR-BYTE what it was before -- existing
    -- pin scope keys keep matching (PRD story 19).
    if type(cases) == 'table' and #cases > 0 then
        local cls = {};
        for _, c in ipairs(cases) do
            cls[#cls + 1] = tostring(c.op) .. '(' .. legLabel(c.when, c.whenAny) .. ')';
        end
        table.sort(cls);
        s = s .. '#' .. table.concat(cls, '#');
    end
    return s;
end

local function normalize(t)
    local out, warns = {}, {};
    for k, v in pairs(t) do
        local ev = EVENT_CANON[string.lower(tostring(k))];
        if ev == nil then
            local lk = string.lower(tostring(k));
            if lk ~= 'setoptions' and lk ~= 'modes' and lk ~= 'groups' then   -- sibling sections, not handlers
                warns[#warns + 1] = string.format('unknown handler section %q (expected %s or Modes)',
                    tostring(k), table.concat(EVENTS, '/'));
            end
        elseif type(v) == 'table' then
            local list = out[ev] or {};
            for i, r in ipairs(v) do
                if type(r) ~= 'table' or type(r.when) ~= 'table'
                   or (r.set == nil and type(r.equip) ~= 'table') then
                    warns[#warns + 1] = string.format('%s rule %d: malformed (needs when = {...} plus set= or equip=)', ev, i);
                else
                    local when, dead = {}, false;
                    for ck, cv in pairs(r.when) do
                        local lk = string.lower(tostring(ck));
                        if lk == CASES_GUARD then
                            -- the cases version guard: known, engine-managed, NOT a
                            -- real body condition -- stripped so it never pollutes the
                            -- label or the /dl why trace (issue #126).
                        elseif TIER[lk] == nil then
                            warns[#warns + 1] = string.format('%s rule %d: unknown condition %q — rule dropped', ev, i, tostring(ck));
                            dead = true;
                            break;
                        else
                            when[lk] = cv;
                        end
                    end
                    -- v54 OR group: whenAny = { { cond = val, ... }, ... } -- ANY
                    -- entry whose conditions ALL hold matches the rule, independent
                    -- of the & leg. Unknown keys drop the rule, exactly like `when`
                    -- (never a silent no-op).
                    local whenAny = nil;
                    local rawAny = r.whenAny or r.whenany;
                    if not dead and type(rawAny) == 'table' then
                        for ei, entry in ipairs(rawAny) do
                            if type(entry) ~= 'table' then
                                warns[#warns + 1] = string.format('%s rule %d: whenAny entry %d is not a table — rule dropped', ev, i, ei);
                                dead = true; break;
                            end
                            local ne = {};
                            for ck, cv in pairs(entry) do
                                local lk = string.lower(tostring(ck));
                                if TIER[lk] == nil then
                                    warns[#warns + 1] = string.format('%s rule %d: unknown condition %q in whenAny — rule dropped', ev, i, tostring(ck));
                                    dead = true; break;
                                end
                                ne[lk] = cv;
                            end
                            if dead then break; end
                            if next(ne) ~= nil then
                                whenAny = whenAny or {};
                                whenAny[#whenAny + 1] = ne;
                            end
                        end
                    end
                    -- Cases (issue #126): the optional second tier. Each entry is
                    -- { op = '&' | '|', when = { &-leg }, whenAny = { |-entries } }
                    -- -- the SAME two legs a body has, validated by the SAME
                    -- registry gate (an unknown key anywhere kills the whole rule,
                    -- exactly as a body leg does). Cases cannot contain cases (hard
                    -- one-tier cap): a nested `cases` field is simply ignored. Empty
                    -- cases are dropped.
                    local cases = nil;
                    if not dead and type(r.cases) == 'table' then
                        for ci, c in ipairs(r.cases) do
                            if type(c) ~= 'table' then
                                warns[#warns + 1] = string.format('%s rule %d: case %d is not a table — rule dropped', ev, i, ci);
                                dead = true; break;
                            end
                            local op = (c.op == '|' or c.operator == '|') and '|'
                                    or ((c.op == '&' or c.operator == '&') and '&' or nil);
                            if op == nil then
                                warns[#warns + 1] = string.format("%s rule %d: case %d needs op = '&' or '|' — rule dropped", ev, i, ci);
                                dead = true; break;
                            end
                            local cw = {};
                            for ck, cv in pairs(c.when or {}) do
                                local lk = string.lower(tostring(ck));
                                if lk == CASES_GUARD then       -- stray guard inside a case: ignore
                                elseif TIER[lk] == nil then
                                    warns[#warns + 1] = string.format('%s rule %d: unknown condition %q in a case — rule dropped', ev, i, tostring(ck));
                                    dead = true; break;
                                else cw[lk] = cv; end
                            end
                            if dead then break; end
                            local cwAny = nil;
                            if type(c.whenAny or c.whenany) == 'table' then
                                for ei, entry in ipairs(c.whenAny or c.whenany) do
                                    if type(entry) ~= 'table' then
                                        warns[#warns + 1] = string.format('%s rule %d: case %d whenAny entry %d is not a table — rule dropped', ev, i, ci, ei);
                                        dead = true; break;
                                    end
                                    local ne = {};
                                    for ck, cv in pairs(entry) do
                                        local lk = string.lower(tostring(ck));
                                        if lk == CASES_GUARD then
                                        elseif TIER[lk] == nil then
                                            warns[#warns + 1] = string.format('%s rule %d: unknown condition %q in a case — rule dropped', ev, i, tostring(ck));
                                            dead = true; break;
                                        else ne[lk] = cv; end
                                    end
                                    if dead then break; end
                                    if next(ne) ~= nil then cwAny = cwAny or {}; cwAny[#cwAny + 1] = ne; end
                                end
                                if dead then break; end
                            end
                            -- an emptied case is dropped (no & leg and no | leg)
                            if next(cw) ~= nil or (cwAny ~= nil and #cwAny > 0) then
                                cases = cases or {};
                                cases[#cases + 1] = { op = op, when = cw, whenAny = cwAny };
                            end
                        end
                    end
                    if not dead then
                        -- auto-priority = max tier over EVERY leg of EVERY case (the
                        -- guard, tier 10, never wins). One source of truth with the
                        -- editor's chip: both call M.defaultPriority.
                        local prio = tonumber(r.priority) or M.defaultPriority(when, whenAny, cases);
                        -- set = 'Name' or an ORDERED list { 'Base', 'Overlay' } --
                        -- normalized to a `sets` array either way.
                        local sets = nil;
                        if type(r.set) == 'table' then
                            for _, sn in ipairs(r.set) do
                                if type(sn) == 'string' and sn ~= '' then
                                    sets = sets or {};
                                    sets[#sets + 1] = sn;
                                end
                            end
                        elseif r.set ~= nil then
                            sets = { tostring(r.set) };
                        end
                        list[#list + 1] = {
                            when    = when,
                            whenAny = whenAny,
                            cases   = cases,
                            sets    = sets,
                            equip   = (type(r.equip) == 'table') and r.equip or nil,
                            prio    = prio,
                            ord     = #list + 1,
                            label   = M.ruleLabel(when, whenAny, cases),
                        };
                    end
                end
            end
            out[ev] = list;
        end
    end
    return out, warns;
end
M._normalize = normalize;   -- headless test seam (the _matchers idiom)

-- Load (or re-load) the current job's trigger file. Throttled to one content check
-- per second; between checks the cached rules are used, so per-frame dispatch never
-- touches the disk. On a parse/run error the PREVIOUS good rules are kept and the
-- error is printed once (per content change) + surfaced in /dl why.
local function ensureLoaded()
    local now = os.time();
    if _trig.rules ~= nil and now == _trig.lastCheck then return _trig.rules; end
    _trig.lastCheck = now;

    local path = triggersPath();
    if path == nil then return _trig.rules; end
    if path ~= _trig.path then   -- job change / first resolve -> drop the cache
        _trig.path, _trig.raw, _trig.rules, _trig.err = path, nil, nil, nil;
    end

    local raw = readFile(path);
    if raw == nil then           -- no trigger file (yet) -> nothing to dispatch
        _trig.raw, _trig.rules, _trig.err = nil, nil, nil;
        return nil;
    end
    if raw == _trig.raw then return _trig.rules; end
    _trig.raw = raw;

    local chunk, cerr = (loadstring or load)(raw, '@' .. path);
    if chunk == nil then
        _trig.err = 'trigger file does not parse: ' .. tostring(cerr);
        printerr(_trig.err .. '  (keeping the previous rules)');
        return _trig.rules;
    end
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' then
        _trig.err = 'trigger file did not return a table' .. (ok and '' or (': ' .. tostring(t)));
        printerr(_trig.err .. '  (keeping the previous rules)');
        return _trig.rules;
    end

    local rules, warns = normalize(t);
    _trig.rules, _trig.err = rules, nil;
    -- Modes section: cycle-mode definitions + optional keybinds.
    --   Modes = { Weapon = { values = { 'Melee', 'Ranged', 'Caster' }, bind = '^F3' },
    --             DT = { bind = 'F9' } }          (array shorthand = values)
    _trig.modeDefs = {};
    local md = t.Modes or t.modes;
    if type(md) == 'table' then
        for nm, def in pairs(md) do
            if type(nm) == 'string' and type(def) == 'table' then
                local values = nil;
                local src = (type(def.values) == 'table') and def.values or def;
                for _, v in ipairs(src) do
                    if type(v) == 'string' then values = values or {}; values[#values + 1] = v; end
                end
                _trig.modeDefs[string.lower(nm)] = {
                    name = nm, values = values,
                    bind = (type(def.bind) == 'string') and def.bind or nil,
                };
            end
        end
    end
    -- Groups section (ADR 0009): a named, untyped list of action names per Job
    -- entry, beside Modes. Matched by the `group` condition. Stored raw
    -- ({ Name = { 'Action', ... } }); M.groupMatch does the case-insensitive
    -- membership test. Sanitized to string names -> string-member arrays.
    _trig.groups = {};
    local gr = t.Groups or t.groups;
    if type(gr) == 'table' then
        for nm, mem in pairs(gr) do
            if type(nm) == 'string' and type(mem) == 'table' then
                local members = {};
                for _, a in ipairs(mem) do
                    if type(a) == 'string' and a ~= '' then members[#members + 1] = a; end
                end
                _trig.groups[nm] = members;
            end
        end
    end
    -- A cycle mode ALWAYS has a value: default to its first on load / new definition.
    local modeBinds = {};
    for ln, def in pairs(_trig.modeDefs) do
        if def.values ~= nil then
            local cur = M.modes[ln];
            local valid = false;
            if type(cur) == 'string' then
                for _, v in ipairs(def.values) do
                    if ci(v, cur) then valid = true; break; end
                end
            end
            if not valid then M.modes[ln] = def.values[1]; end
        end
        -- GUI-managed keybind: collected here so profiles need no OnLoad bind
        -- code, and INSTALLED as a whole group below.
        if def.bind ~= nil then
            modeBinds[#modeBinds + 1] = {
                owner   = 'mode:' .. ln,
                key     = def.bind,
                command = string.format('/dl mode %s', def.name),
                label   = 'Mode: ' .. tostring(def.name),
            };
        end
    end
    installModeBinds(modeBinds);
    -- NO stale-value purge here (v16 had one; field-FALSIFIED on WHM): mode
    -- DEFINITIONS are per-job trigger data but their VALUES are session-global
    -- by design -- "WHM Weapons" is defined in BRD's file and gates WHM's sets,
    -- so a job change must not clear it. A DELETED mode still dies: the GUI's
    -- delete flow queues '/dl mode <name> off' after its commit.
    pcall(saveModeState);
    for _, w in ipairs(warns) do printwarn('triggers: ' .. w); end
    -- Successful loads are SILENT on purpose: this runs on every profile load /
    -- zone / GUI edit, and the per-load "triggers loaded: N rule(s)" line was
    -- pure chat noise. Errors and warnings above still speak up.
    return _trig.rules;
end

-- ---------------------------------------------------------------------------
-- Automations (ADR 0004): auto elemental staff / auto obi, priority band 60.
-- The GUI derives a per-character manifest (<char>\dlac\autogear.lua) from your
-- bags -- option toggles + the best owned staff/obi per element + whether you own
-- an Iridescence weapon -- and this engine hot-reloads it like the trigger file.
-- v1 Iridescence rule: OWNING one disables staff swapping entirely (it lives in
-- your sets already); obis are independent and stay governed by day/weather.
-- ---------------------------------------------------------------------------
local _auto = { raw = nil, data = nil, lastCheck = -1 };

local function ensureAutoLoaded()
    if M._autoOverride ~= nil then return M._autoOverride; end   -- headless test seam
    local before = _auto.data;
    local t = ensureStateFile(_auto, 'autogear.lua');
    -- Old boolean-format manifest: we can't know the universal weapon's name, so
    -- staff swapping stays suppressed. Tell the player how to fix it (once per change).
    if t ~= nil and t ~= before and t.universal == nil and t.iridescence == true then
        printwarn('autogear.lua is an old format (staff swapping is OFF) -- open the GUI\'s Gear Helpers tab (the manifest self-heals on render).');
    end
    return t;
end

-- Virtual slot entries ("slot functions", ADR 0004 4th revision): a set slot may
-- hold a marker string instead of an item -- 'dlac:AutoStaff' (Main) equips the best
-- Iridescence staff for this cast, 'dlac:AutoObi' (Waist) the matching elemental obi
-- on a positive day/weather sign. Resolved HERE at equip time from the autogear
-- manifest; an unresolvable marker DROPS its slot, so LAC leaves what you're wearing.

-- The character's current effective level (honours the /dl set level main override).
-- Unknown -> 75, so a missing player read never blocks resolution.
local function playerLevel(ctx)
    local sl = rawget(_G, 'staticMainLevel');
    if type(sl) == 'number' and sl > 0 then return sl; end
    local lv = ctx.player and ctx.player.MainJobSync;
    if type(lv) == 'number' and lv > 0 then return lv; end
    return 75;
end

-- A manifest entry is usable when its recorded level fits the character. Entries
-- without a level (legacy manifests) count as usable -- Rescan adds levels.
local function usableAt(entryLevel, lvl)
    return entryLevel == nil or (tonumber(entryLevel) or 0) <= lvl;
end

-- Best staff by tiered Iridescence (CatsEyeXI): per-element staves carry it for their
-- own element only (NQ +1 / HQ +2); universal weapons for every element, +1..+3
-- (catalog tiers: Iridal/Ephemeron +1; Chatoyant/Foreshadow +1/Claritas/Izuna... +2;
-- Inanna/Keraunos/Gridarvor and the Lv75 relic staves +3). Higher tier wins; ties go
-- to the universal (no cross-element swapping, and it needs no element at all).
-- LEVEL-GATED: anything above the character's current level is not a candidate at all.
local function resolveStaff(a, el, lvl)
    if a.iridescence == true then return nil; end   -- legacy boolean manifest: suppress (Rescan regenerates)
    local uniName, uniTier = nil, 0;
    -- v82 ladder: `universals` is preference-ordered by the GUI (tier desc,
    -- job-specific first) -- the first rung usable at the LIVE level wins, so a
    -- level-synced character falls through to a lower rung it can still wear.
    if type(a.universals) == 'table' then
        for _, u in ipairs(a.universals) do
            if type(u) == 'table' and type(u.name) == 'string' and usableAt(u.level, lvl) then
                uniName, uniTier = u.name, tonumber(u.tier) or 1;
                break;
            end
        end
    end
    if uniName == nil then
        if type(a.universal) == 'table' and type(a.universal.name) == 'string'
           and usableAt(a.universal.level, lvl) then
            uniName, uniTier = a.universal.name, tonumber(a.universal.tier) or 1;
        elseif type(a.iridescence) == 'string' then    -- legacy manifest: name, assume +2
            uniName, uniTier = a.iridescence, 2;
        end
    end
    local elName, elTier = nil, 0;
    if el ~= nil and type(a.staff) == 'table' then
        local s = a.staff[el];
        if type(s) == 'table' and type(s.name) == 'string' and usableAt(s.level, lvl) then
            elName, elTier = s.name, tonumber(s.tier) or 1;
        elseif type(s) == 'string' then                -- legacy manifest: best-owned name
            elName, elTier = s, 2;
        end
    end
    if uniName ~= nil and uniTier >= elTier then return uniName; end
    return elName;
end

-- Obi pick, the PURE half (mirrors resolveStaff; tests VG*): elemental obi for
-- this element first, else the universal (Hachirin-no-obi -- on CatsEyeXI the
-- only one), both level-gated; equip only on a positive net day/weather sign
-- for the SPELL's element ("the moment it's positive, it's better", ADR 0004).
-- `net` is the caller's day/weather read -- no gData in here.
local function resolveObi(a, el, lvl, net)
    if el == nil then return nil, 'no element'; end
    local nm, olvl = nil, nil;
    local o = (type(a.obi) == 'table') and a.obi[el] or nil;
    if type(o) == 'table' and type(o.name) == 'string' then nm, olvl = o.name, o.level;
    elseif type(o) == 'string' then nm = o; end     -- legacy manifest: name only
    if nm ~= nil and not usableAt(olvl, lvl) then nm, olvl = nil, nil; end
    if nm == nil then
        local u = a.obiUniversal;
        if type(u) == 'table' and type(u.name) == 'string' and usableAt(u.level, lvl) then
            nm = u.name;
        end
    end
    if nm == nil then return nil, 'no usable obi for ' .. el .. ' at Lv' .. lvl; end
    if (tonumber(net) or 0) <= 0 then return nil, 'day/weather not positive'; end
    return nm;
end

-- Oneiros gate, the PURE half (tests VG*): the FIELD-PINNED latent rule. thr =
-- floor(base * 50/100) -- 50 is live truth (v67; the repo sql's 75 is not what
-- runs, docs/server-questions.md #6) -- and the boundary is INCLUSIVE: cur ==
-- thr still resolves (Mindie: refresh ticks at MP 357 of base 714, gone at
-- 358). `base`/`cur` are the caller's nativemp + vitals reads -- no gData here,
-- so the threshold rule the field calibration paid for is pinned headless.
local function resolveOneiros(g, lvl, base, cur)
    if type(g) ~= 'table' or type(g.name) ~= 'string' then
        return nil, 'Oneiros Grip not owned (the Gear Helpers tab rescans itself)';
    end
    if not usableAt(g.level, lvl) then
        return nil, string.format('under level for %s (Lv%d)', g.name, tonumber(g.level) or 0);
    end
    if base == nil then return nil, 'native MP unreadable (login settle?)'; end
    if base <= 0 then return nil, 'no native MP pool on this job'; end
    local thr = math.floor(base * 50 / 100);   -- 50 = live truth (v67); repo sql says 75
    if cur == nil then return nil, 'current MP unreadable'; end
    if cur > thr then
        -- percent-free wording on purpose: /dl why reasons may render
        -- through imgui's printf-style Text calls
        return nil, string.format('MP %d above the latent threshold %d (half of base %d)', cur, thr, base);
    end
    return g.name;
end

-- Marker -> item name for this cast, or nil + reason (for /dl why).
-- `slot` (the set's slot key, e.g. 'Neck'/'Ring1') is needed by per-slot
-- markers (dlac:AutoCraft); staff/obi ignore it (Main/Waist by convention).
-- `all` (ADR 0027 stage 4, claim-side ladders): when a table is passed, the
-- chain-walking families (craft/HELM/fish/choco) COLLECT every usable rung
-- into it instead of stopping at the first -- the same walk, the same gates,
-- one code path (never a twin) -- and still return the head. The single-item
-- families (staff/obi/oneiros) ignore it: a one-rung ladder has no tail.
local function resolveVirtual(marker, ctx, slot, all)
    local a = ensureAutoLoaded();
    if a == nil then return nil, 'no autogear manifest (open the Gear Helpers tab -- it rescans itself)'; end
    local el = ctx.action and ctx.action.Element;
    if type(el) ~= 'string' or ci(el, 'Non-Elemental') then el = nil; end
    local lvl = playerLevel(ctx);
    local mk = string.lower(tostring(marker));
    -- canonical new names + the original spellings (existing sets keep working)
    if mk == 'dlac:autoiridescence' then mk = 'dlac:autostaff'; end
    if mk == 'dlac:elementalobi'    then mk = 'dlac:autoobi';   end
    if mk == 'dlac:autocraft' then
        -- Craft automation (docs/design/craft-automation.md): the manifest's
        -- craft section holds per-slot ladders per craft and goal. The ACTIVE
        -- craft is the dlac-owned 'craft' cycle value -- published by
        -- craftwatch on synth detection (or manually: /dl mode craft Alchemy);
        -- ctx.craftOverride lets the addon-side equip path resolve before the
        -- command-bus mode write lands. Goal: 'craftgoal' mode, 'nq' or 'hq'
        -- (default hq). Per Henrik: gear STAYS ON when the mode clears --
        -- the next ordinary trigger event redresses you (no flashing).
        local craftV = ctx.craftOverride or M.modes['craft'];
        if type(craftV) ~= 'string' then return nil, 'craft mode off (/dl mode craft <Skill>)'; end
        local goal = 'hq';                             -- goals: hq (default) / nq / skillup
        -- ONE goal variable (Henrik): the manifest's craftGoal field, written
        -- silently by the GUI picker and hot-reloaded here -- the mode system
        -- is no longer consulted (its narration spammed chat and desynced
        -- between the two Lua states).
        local g = ctx.goalOverride or a.craftGoal;
        if type(g) == 'string' then
            local lg = string.lower(g);
            if lg == 'nq' or lg == 'skillup' then goal = lg; end
        end
        local slotKey = string.lower(tostring(slot or ''));
        local bySlot = (type(a.craft) == 'table') and a.craft[slotKey] or nil;
        local perCraft = nil;
        if type(bySlot) == 'table' then
            perCraft = bySlot[craftV];
            if perCraft == nil then                      -- tolerate caps drift in the mode value
                for k, v in pairs(bySlot) do
                    if ci(tostring(k), tostring(craftV)) then perCraft = v; break; end
                end
            end
        end
        -- Strictly per-goal: hq gear under an nq goal (or vice versa) would
        -- FIGHT the goal, so a missing ladder is unresolved, not substituted.
        local chain = (type(perCraft) == 'table') and perCraft[goal] or nil;
        if type(chain) ~= 'table' then
            return nil, string.format('no %s craft gear for %s (%s)', slotKey, tostring(craftV), goal);
        end
        for _, r in ipairs(chain) do                     -- ladder is best-first
            if type(r) == 'table' and type(r.name) == 'string' and usableAt(r.level, lvl) then
                if all == nil then return r.name; end
                all[#all + 1] = r.name;
            end
        end
        if all ~= nil and all[1] ~= nil then return all[1]; end
        return nil, string.format('no usable %s rung at Lv%d', slotKey, lvl);
    end
    if mk == 'dlac:autohelm' then
        -- HELM automation (docs/design/helm-gear.md): manifest `helm` block =
        -- per-slot best-first ladders (score = Surveyor-major, HELM-minor) +
        -- the semantic hat map (hats[category] -- WHICH category a hat doubles
        -- is not a catalog stat). Head: the active category's hat first; any
        -- other owned hat still carries Surveyor, so the generic head ladder
        -- is the fallback rather than an empty slot.
        local gv = ctx.gatherOverride;
        if type(gv) ~= 'string' or gv == '' then return nil, 'no gather category (HELM bar)'; end
        local h = (type(a.helm) == 'table') and a.helm or nil;
        if h == nil then return nil, 'no helm gear data (open the Gear Helpers tab -- it rescans itself)'; end
        local slotKey = string.lower(tostring(slot or ''));
        if slotKey == 'head' and type(h.hats) == 'table' then
            local hat = h.hats[gv];
            if hat == nil then                           -- tolerate caps drift
                for k, v in pairs(h.hats) do
                    if ci(tostring(k), tostring(gv)) then hat = v; break; end
                end
            end
            if type(hat) == 'table' and type(hat.name) == 'string' and usableAt(hat.level, lvl) then
                if all == nil then return hat.name; end
                all[#all + 1] = hat.name;   -- the hat leads; the generic chain follows as fallback rungs
            end
        end
        local chain = h[slotKey];
        if type(chain) ~= 'table' then
            return nil, string.format('no %s helm gear owned', slotKey);
        end
        for _, r in ipairs(chain) do                     -- ladder is best-first
            if type(r) == 'table' and type(r.name) == 'string' and usableAt(r.level, lvl) then
                if all == nil then return r.name; end
                all[#all + 1] = r.name;
            end
        end
        if all ~= nil and all[1] ~= nil then return all[1]; end
        return nil, string.format('no usable %s rung at Lv%d', slotKey, lvl);
    end
    if mk == 'dlac:autofish' then
        -- Fishing automation (docs/design/fishing-gear.md): manifest `fish`
        -- block = per-slot best-first ladders (score = FishingSkill-major,
        -- the CatsEyeXI Expert Angler cx-mods as tiebreakers).
        -- No category, no hat map: fishing is one activity. Range/Ammo never
        -- resolve here -- rod and bait are target-specific state-file picks.
        local f = (type(a.fish) == 'table') and a.fish or nil;
        if f == nil then return nil, 'no fishing gear data (open the Gear Helpers tab -- it rescans itself)'; end
        local slotKey = string.lower(tostring(slot or ''));
        local chain = f[slotKey];
        if type(chain) ~= 'table' then
            return nil, string.format('no %s fishing gear owned', slotKey);
        end
        for _, r in ipairs(chain) do                     -- ladder is best-first
            if type(r) == 'table' and type(r.name) == 'string' and usableAt(r.level, lvl) then
                if all == nil then return r.name; end
                all[#all + 1] = r.name;
            end
        end
        if all ~= nil and all[1] ~= nil then return all[1]; end
        return nil, string.format('no usable %s rung at Lv%d', slotKey, lvl);
    end
    if mk == 'dlac:autochoco' then
        -- Chocobo riding-gear automation (docs/design/chocobo-gear.md): manifest
        -- `choco` block = per-slot best-first ladders (score = ChocoboRidingTime).
        -- One activity, no category, no target -- the fixed "best riding-time
        -- set". Slots Main/Neck/Body/Hands/Legs/Feet only (the Chocobo Wand is a
        -- Main-slot weapon and IS included -- riding-time totals beat the TP a
        -- swap costs while idle before a whistle).
        local c = (type(a.choco) == 'table') and a.choco or nil;
        if c == nil then return nil, 'no chocobo gear data (open the Gear Helpers tab -- it rescans itself)'; end
        local slotKey = string.lower(tostring(slot or ''));
        local chain = c[slotKey];
        if type(chain) ~= 'table' then
            return nil, string.format('no %s chocobo gear owned', slotKey);
        end
        for _, r in ipairs(chain) do                     -- ladder is best-first
            if type(r) == 'table' and type(r.name) == 'string' and usableAt(r.level, lvl) then
                if all == nil then return r.name; end
                all[#all + 1] = r.name;
            end
        end
        if all ~= nil and all[1] ~= nil then return all[1]; end
        return nil, string.format('no usable %s rung at Lv%d', slotKey, lvl);
    end
    if mk == 'dlac:autooneiros' then
        -- Oneiros Grip (Sub): latent 'Refresh +1' while current MP is at or
        -- below 50% of the BASE pool. Denominator (stable branch
        -- latent_effect_container.cpp): MP_UNDER_PERCENT divides health.mp by
        -- health.maxmp = CalculateStats' race/job/sub formula + merit MP --
        -- gear, traits and food are NOT in it. The threshold recomputes per
        -- resolve from live race/job/levels (nativemp) plus the merit levels
        -- saved on the Automations tab, so a job change or level sync re-aims
        -- it by itself. This rim only READS (nativemp + vitals); the field-
        -- pinned rule itself is pure resolveOneiros above (tests VG*).
        if _nmp == nil or type(_nmp.self) ~= 'function' then
            return nil, 'nativemp module unavailable';
        end
        -- Max MP merit = 10 MP/level, USABLE count capped by merit.cpp's
        -- cap[mlvl] = 10 at Lv75 (the sql's 15 headroom needs Lv80+; this
        -- resolver only runs at 75 -- the grip's own level gate).
        local meritLv = math.floor(tonumber(a.mpMerits) or 0);
        if meritLv < 0 then meritLv = 0; elseif meritLv > 10 then meritLv = 10; end
        local base = _nmp.self(meritLv * 10);
        local cur = nil;   -- gData vitals read inline (playerMP is declared later in the file)
        pcall(function() cur = tonumber(gData.GetPlayer().MP); end);
        return resolveOneiros(a.oneiros, lvl, base, cur);
    end
    if mk == 'dlac:autostaff' then
        local nm = resolveStaff(a, el, lvl);
        if nm == nil then
            return nil, (el == nil) and 'no usable universal staff (elementless action)'
                                     or ('no usable staff for ' .. el .. ' at Lv' .. lvl);
        end
        return nm;
    end
    if mk == 'dlac:autoobi' then
        -- The rim only reads the environment; the pick + the positive-sign
        -- gate are pure resolveObi above (tests VG*).
        return resolveObi(a, el, lvl, netDayWeather(ctx));
    end
    return nil, 'unknown marker';
end
M._resolveVirtual = resolveVirtual;   -- addon-side craft equip + headless tests
M._resolveObi = resolveObi;           -- pure decision seams (the _resolveVirtual idiom):
M._resolveOneiros = resolveOneiros;   -- the field-calibrated gates, pinned headless (VG*)

-- The level a virtual marker becomes USABLE at: the lowest level among the
-- manifest items it can resolve to. A marker is a ladder RUNG at this level,
-- not a Lv0 wildcard (Henrik 2026-07-17: AutoIridescence with Chatoyant Staff
-- as best owned = a Lv51 rung -- below 51 the set's real weapon owns the slot).
-- BuildDynamicSets consults this to skip an unreachable marker at flatten time;
-- the Sets tab shows it as the marker's level. Returns nil for "no answer" (no
-- manifest, legacy name-only shapes, or the craft/helm/acc families whose
-- ladders carry their own fallbacks) -- callers keep the old always-adopt
-- behavior on nil, so this can only ever REMOVE a marker that cannot resolve.
function M.virtualMinLevel(marker)
    local a = ensureAutoLoaded();
    if a == nil then return nil; end
    local mk = string.lower(tostring(marker or ''));
    local bar = string.find(mk, '|', 1, true);          -- tolerate 'marker|fallback'
    if bar ~= nil then mk = string.sub(mk, 1, bar - 1); end
    if mk == 'dlac:autoiridescence' then mk = 'dlac:autostaff'; end
    if mk == 'dlac:elementalobi'    then mk = 'dlac:autoobi';   end
    local best = nil;
    local function consider(e)
        if type(e) ~= 'table' or type(e.name) ~= 'string' then return; end
        local lv = tonumber(e.level);
        if lv ~= nil and (best == nil or lv < best) then best = lv; end
    end
    if mk == 'dlac:autostaff' then
        consider(a.universal);
        if type(a.universals) == 'table' then           -- v82 ladder: EVERY rung counts --
            for _, u in ipairs(a.universals) do consider(u); end   -- the marker adopts at the lowest
        end
        if type(a.staff) == 'table' then
            for _, s in pairs(a.staff) do consider(s); end
        end
        return best;
    end
    if mk == 'dlac:autoobi' then
        consider(a.obiUniversal);
        if type(a.obi) == 'table' then
            for _, o in pairs(a.obi) do consider(o); end
        end
        return best;
    end
    if mk == 'dlac:autooneiros' then
        consider(a.oneiros);   -- the grip's own level (75): below it the marker is not a rung
        -- Oneiros Grip is ONE fixed Lv75 item, so the rung is a constant of
        -- the marker itself -- a manifest that has not learned the grip yet
        -- must not degrade it to a Lv0 always-adopt wildcard (Henrik).
        return best or 75;
    end
    return nil;
end

-- Equip a set table, resolving virtual entries and honouring SLOT LOCKS. Sets that
-- need neither pass through untouched (zero copies); otherwise a shallow copy carries
-- the changes. BuildDynamicSets encodes the slot's regular best-by-level pick as a
-- fallback ('dlac:AutoStaff|Maple Wand'): an unresolvable virtual equips the fallback
-- -- so being under-leveled for every iridescence weapon / obi never blocks the slot
-- -- and only with no fallback at all is the slot dropped (LAC leaves what's worn).
-- LOCKED slots (/dl lock, the Equipped tab's "Lock when equipped") are stripped
-- outright: the engine never sends gear into them, so a manual equip stays put.
-- Returns a trace note ('' when nothing was virtual/locked).
-- ---------------------------------------------------------------------------
-- Max-MP hold (mode 'maxmp'): keep a worn piece while swapping it out would
-- WASTE unspent MP. Generic and slot-local: however the MP gear got on (resting
-- set, trigger, manual equip), it stays until the player has spent the surplus
-- its MP grants over the incoming piece; then the slot releases naturally.
-- Weapons are exempt (Main/Sub/Range swaps are TP-sensitive). Piece MP values
-- ride the autogear manifest (the engine never loads the catalog); the worn
-- item is read from equipment memory. Design: docs/design/maxmp-mode.md.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- THE central equip-eligibility check. Wearability is MAIN job only (field-
-- verified on CatsEyeXI: RDM/WHM cannot wear Hlr. Bliaut +1 -- ADR/history) and
-- the level gate is the main level. Every consumer -- gearui pickers, gearoptim,
-- the automation manifests -- delegates here; utils re-exports it for profiles.
-- ---------------------------------------------------------------------------
function M.jobCanEquip(jobs, job)
    if jobs == nil then return true; end               -- no restriction
    if type(jobs) ~= 'table' or #jobs == 0 then return true; end
    for _, j in ipairs(jobs) do
        if j == 'All' then return true; end
        if job ~= nil and job ~= '' and j == job then return true; end
    end
    return false;
end

function M.canWear(rec, job, level)
    if type(rec) ~= 'table' then return false; end
    if (tonumber(rec.Level) or 0) > (tonumber(level) or 0) then return false; end
    return M.jobCanEquip(rec.Jobs, job);
end

local MP_HOLD_EXEMPT = { main = true, sub = true, range = true };
local SLOT_EQUIP_ID = { main = 0, sub = 1, range = 2, ammo = 3, head = 4, body = 5,
                        hands = 6, legs = 7, feet = 8, neck = 9, waist = 10,
                        ear1 = 11, ear2 = 12, ring1 = 13, ring2 = 14, back = 15 };

-- The pure rule (headless-tested): hold while current MP is AT OR ABOVE what the
-- pool would hold with the incoming piece worn instead. The boundary is >= on
-- purpose: a battery equipped at a FULL pool sits exactly on it (cur == newMax -
-- delta), and releasing there would drop the piece before any recovery landed.
-- Release requires spending strictly past the surplus.
function M.mpHoldNeeded(wornMP, targetMP, curMP, maxMP)
    local delta = (wornMP or 0) - (targetMP or 0);
    if delta <= 0 then return false; end
    return (curMP or 0) >= (maxMP or 0) - delta;
end

-- Pick the battery to wear from a manifest ladder (sorted best-first). Rungs
-- exist because rung 1 may be gear the character has yet to grow into -- the
-- pick is the best rung wearable at the CURRENT level. A legacy single-entry
-- manifest counts as a one-rung ladder.
function M.mpPick(cands, level)
    if type(cands) ~= 'table' then return nil; end
    if cands.name ~= nil then cands = { cands }; end   -- legacy fmtver-1 shape
    for _, c in ipairs(cands) do
        if type(c) == 'table' and type(c.name) == 'string'
           and (tonumber(c.level) or 0) <= (tonumber(level) or 0) then
            return c;
        end
    end
    return nil;
end

-- Staged battery movement (v76): at most ONE battery moves per dispatch, and
-- these pure choosers pick which (headless tests MS*). Release: the SMALLEST
-- surplus goes first -- the highest-MP battery stays on longest (the original
-- spec) and any single eligible release is clamp-free by construction
-- (eligibility means its own surplus is already spent). Simultaneous releases
-- were the field bug: each per-slot hold justifies removing only ITS piece, so
-- N same-dispatch releases dropped max MP by the SUM of surpluses and the
-- server clamp (cur = min(cur, newMax)) ate the difference. Ties break on the
-- slot name so pairs() collection order can never flip the pick.
function M.mpStageRelease(cands)
    if type(cands) ~= 'table' then return nil; end
    local best = nil;
    for _, c in ipairs(cands) do
        if type(c) == 'table'
           and (best == nil
                or (c.surplus or 0) < (best.surplus or 0)
                or ((c.surplus or 0) == (best.surplus or 0)
                    and tostring(c.slot) < tostring(best.slot))) then
            best = c;
        end
    end
    return best;
end

-- Equip: the BIGGEST gain first ("find the piece with the highest MP"). The
-- full-pool gate does the pacing: the next battery only becomes a candidate
-- again once recovery has refilled the headroom the last one opened.
function M.mpStageEquip(cands)
    if type(cands) ~= 'table' then return nil; end
    local best = nil;
    for _, c in ipairs(cands) do
        if type(c) == 'table'
           and (best == nil
                or (c.gain or 0) > (best.gain or 0)
                or ((c.gain or 0) == (best.gain or 0)
                    and tostring(c.slot) < tostring(best.slot))) then
            best = c;
        end
    end
    return best;
end

-- Max-MP reconciliation (v86, LOW-biased v87 -- tests MR*). Ashita's
-- GetMPMax() is UNRELIABLE across gear churn on this server: round 6 read
-- 975/1052 vs a 975/975 bar (dead full gate), and round 7's oscillation
-- log proved the other direction -- a fresh battery sits EXACTLY on the
-- hold boundary, so a few MP of max-read error dumps it right back off,
-- max drops, the next boundary flips, and the whole ladder cascades to
-- idle gear ("back to 975 again"). Below a full pool GetMPMax is now
-- ignored outright: max = the LOW edge of the party-MP%-pinned window,
-- ceil(cur*100/(mpp+1)) -- an UNDER-estimate can only over-hold a battery
-- (release needs spending its surplus plus at most ~1% extra), never dump
-- it early. mpp >= 100 pins max = cur exactly (floored percent reads 100
-- ONLY at cur == max). cur/mpp unreadable: the raw read, old behavior.
function M.mpReconcileMax(cur, max, mpp)
    cur, max, mpp = tonumber(cur), tonumber(max), tonumber(mpp);
    if cur == nil or mpp == nil then return max; end
    if mpp >= 100 then return cur; end
    if mpp <= 0 or cur <= 0 then return max; end
    return math.ceil(cur * 100 / (mpp + 1));
end

-- The full-pool signal (v87, pure -- tests MF*). Equips must fire ONLY at a
-- genuinely full pool, and the floored party MP% IS that signal: 100 happens
-- exactly when cur == max, no arithmetic, no staleness. The old cur >= max
-- compare survives solely as the fallback when the percent is unreadable --
-- round 7's field log showed it firing on a stale-low max ("false full"),
-- over-equipping batteries into a pool that was never actually full and
-- arming the release cascade.
function M.mpPoolFull(cur, max, mpp)
    mpp = tonumber(mpp);
    if mpp ~= nil then return mpp >= 100; end
    cur, max = tonumber(cur), tonumber(max);
    return cur ~= nil and max ~= nil and cur >= max;
end

-- Paired slots (ears/rings, v83): a battery already WORN in the SIBLING slot
-- is the SAME physical item -- equipping it "here" would make LAC unequip it
-- over there (UnequipConflicts) and shuffle it across, leaving a hole (field:
-- resting WHM, Loquacious Earring hopped ear2 -> ear1 with ear2 left empty;
-- net MP zero, pure churn). The one exception is a genuine duplicate: the
-- manifest lists dup-owned items in BOTH paired ladders (owned counts;
-- ladders are disjoint otherwise), so "the sibling's own ladder also names
-- it" = a second copy exists and the pick may proceed (2x Astral Ring).
-- Pure rule, headless tests MPS*.
M.MP_PAIR = { ear1 = 'ear2', ear2 = 'ear1', ring1 = 'ring2', ring2 = 'ring1' };
function M.mpPairSkip(name, sibWorn, sibLadder)
    if name == nil or sibWorn == nil then return false; end
    if string.lower(tostring(sibWorn)) ~= string.lower(tostring(name)) then return false; end
    if type(sibLadder) == 'table' then
        if sibLadder.name ~= nil then sibLadder = { sibLadder }; end   -- legacy single-entry shape
        for _, r in ipairs(sibLadder) do
            if type(r) == 'table' and type(r.name) == 'string'
               and string.lower(r.name) == string.lower(tostring(name)) then
                return false;   -- dup-owned: the sibling wears the OTHER copy
            end
        end
    end
    return true;
end

-- The band plan as chat lines (/dl plan v2, engine v88): the plan and the
-- BEHAVIOR are the same artifact -- the formatter renders the exact band
-- context M.mpBands hands the dispatch pass, so what prints is what runs.
-- PURE formatter (tests MPL*): mpCtx injected, wornOf(lslot) -> worn name.
-- Rows print in RELEASE order (top comes off first as MP is spent; the
-- bottom -- big batteries and refresh pieces -- returns first as MP
-- recovers, before the pool is full, so recovery ticks land in headroom).
function M.mpPlanLines(mpCtx, wornOf)
    if mpCtx == nil or type(mpCtx.bands) ~= 'table' then
        return { 'maxmp plan: no battery data yet -- right after a reload this means the world is still loading (ask again in a few seconds); otherwise open the Gear Helpers tab (the manifest self-heals) or relog.' };
    end
    local lines = {};
    lines[1] = string.format('maxmp band plan -- MP %s of %s (every battery worn), recovery tick %s%s. Spending releases TOP-DOWN at off<=; recovery re-equips BOTTOM-UP at on>= (early on purpose: the next tick lands in the headroom).',
        tostring(mpCtx.cur), tostring(mpCtx.total), tostring(mpCtx.tick),
        mpCtx.resting and ' (resting)' or '');
    for i, b in ipairs(mpCtx.bands) do
        local worn = (wornOf ~= nil) and wornOf(b.slot) or nil;
        local isOn = worn ~= nil and b.name ~= nil
                     and string.lower(worn) == string.lower(b.name);
        -- Zone from cur vs THIS band's thresholds (the resolved target can't
        -- tell a dead-zone keep from a threshold-ON -- both read true).
        local cur, state = tonumber(mpCtx.cur), nil;
        if cur == nil then state = isOn and 'holding (no MP read)' or 'off';
        elseif cur >= (b.onAt or 0) then state = isOn and 'ON (worn)' or 'ON (equipping)';
        elseif cur <= (b.offAt or 0) then state = isOn and 'RELEASING' or 'off';
        else state = isOn and 'holding (dead zone)' or 'off (dead zone)'; end
        local rtag = '';
        if (tonumber(b.rfDelta) or 0) > 0 then rtag = ' [refresh]';
        elseif (tonumber(b.rfDelta) or 0) < 0 then rtag = ' [refresh-cost]'; end
        lines[#lines + 1] = string.format('%d. %s: %s (%d->%d, diff %d)%s   off<=%d  on>=%d   -- %s',
            i, b.slot, tostring(b.name), b.low or 0, b.high or 0, b.diff or 0,
            rtag, b.offAt or 0, b.onAt or 0, state);
    end
    if #mpCtx.bands == 0 then
        lines[#lines + 1] = '(no bands: every trigger set already wears its slot\'s best battery, or no batteries are owned)';
    end
    lines[#lines + 1] = 'Main/Sub/Range exempt (TP preservation); locked slots get no band. A state that never changes while MP moves = that piece may be unequippable (LAC drops those silently) -- check its bag.';
    return lines;
end

-- ---------------------------------------------------------------------------
-- Level-sync settle hold (v56). When a level sync lands (Incursion boss pop,
-- party re-sync), MainJobSync jumps -- and for the next frames the reading and
-- the server's own gear re-staging are mid-flight. A dispatch that trusts the
-- new number immediately can resolve a DIFFERENT weapon (level ladders,
-- virtuals, rebuilt dynamic sets) and a Main swap zeroes saved TP (field
-- report: popping an Incursion boss ate the TP held for it). The rule: a level
-- reading that JUST changed is not trusted yet -- weapon slots hold as worn
-- until it has been stable for SYNC_SETTLE_S. Stateless beyond one tracker
-- (last job/level + a clock stamp), re-stepped on every consult. A JOB change
-- adopts instantly (re-gearing a new job must not wait) and so does the first
-- good read after load; not-ready readings (level 0, job '?'/'NON' -- the v49
-- login shapes) never touch the tracker, so a flaky read can't arm or drop it.
-- ---------------------------------------------------------------------------
-- 1.0s (Henrik, v57: 3 felt long). The window is stability-since-LAST-change --
-- every level flip inside it re-arms, so a staged server transition stays
-- covered however long it drags; 1s only has to outlast the gap AFTER the
-- final flip, where resolution is already correct. First lever to pull if a
-- sync ever eats TP again: raise this number.
M.SYNC_SETTLE_S = 1.0;
local WEAPON_SLOTS = { main = true, sub = true, range = true };
-- Parked on the shared module table (the M._loadStamp pattern): an engine
-- self-swap re-executes this file mid-session, and a fresh tracker would adopt
-- a mid-transition level as "first read" -- dropping a live hold exactly when
-- it matters. A real Reload LAC builds a fresh module table and starts clean.
M._syncSt = M._syncSt or { job = nil, lv = nil, holdUntil = 0 };

-- The pure rule (headless-tested): step the tracker with the current reading,
-- answer whether the hold is active at `now`. Mutates and keeps `st`.
function M.syncSettleStep(st, job, lv, now)
    if type(lv) == 'number' and lv > 0
       and type(job) == 'string' and job ~= '' and job ~= '?' and job ~= 'NON' then
        if st.lv == nil or st.job ~= job then
            st.job, st.lv, st.holdUntil = job, lv, 0;   -- first read / job change: adopt, no hold
        elseif lv ~= st.lv then
            st.lv = lv;                                  -- same job, level jumped: a sync landed
            st.holdUntil = now + (tonumber(M.SYNC_SETTLE_S) or 1);
        end
    end
    return now < (tonumber(st.holdUntil) or 0);
end

-- Live consult: reads the player itself, so ANY caller (the dispatch pass, the
-- HandleDefault wrap) keeps the one tracker fresh. Never throws.
function M.syncSettleHold()
    local job, lv = nil, nil;
    pcall(function()
        local p = gData.GetPlayer();
        if p ~= nil then job, lv = p.MainJob, tonumber(p.MainJobSync); end
    end);
    return M.syncSettleStep(M._syncSt, job, lv, os.clock());
end

-- The whole HandleDefault gate (pet hold + sync settle), as a function ON M so
-- the installed HandleEquipEvent wrap consults it AT CALL TIME -- an engine
-- self-swap refreshes this logic with NO wrap reinstall. Never throws.
function M.defaultGateHold()
    local held = false;
    pcall(function()
        -- While the PET's action is in flight, HOLD Default: a hand-written
        -- profile equips sets.Idle unconditionally and would stomp the
        -- PetAction gear (upstream parity; the Completion clock is the backstop).
        local st = rawget(_G, 'gState');
        local pa = (st ~= nil) and st.PetAction or nil;
        if pa ~= nil and (pa.Completion == nil or os.clock() < pa.Completion) then
            held = true;
            return;
        end
        -- Level-sync settle (v56): while the level reading is fresh off a jump,
        -- Default must not equip AT ALL -- a legacy profile's direct
        -- gFunc.EquipSet (and a transient-level rebuildSets) would ride the
        -- wrong level straight into a weapon swap (TP -> 0). Action events
        -- keep flowing; the engine weapon-holds those via ctx.syncHold.
        if M.syncSettleHold() then held = true; end
    end);
    return held;
end

-- Non-weapon slots MP-EQUIP may write even when the dispatched set doesn't
-- address them (lowercase key -> canonical LAC set key).
local MP_SLOT_CANON = { ammo = 'Ammo', head = 'Head', neck = 'Neck', ear1 = 'Ear1',
                        ear2 = 'Ear2', body = 'Body', hands = 'Hands', ring1 = 'Ring1',
                        ring2 = 'Ring2', back = 'Back', waist = 'Waist', legs = 'Legs',
                        feet = 'Feet' };

-- Decode a packed GetEquippedItem Index -> container, slot (high byte = container,
-- low byte = slot). The seeded engine's TWIN of gearoracle.decodeIndex -- ADR 0002
-- keeps a copy here because the engine cannot require addon-folder modules. The
-- arithmetic is byte-for-byte the oracle's; tests/run_tests.lua (section OR) pins
-- them together and NAMES this twin on any drift.
function M.decodeEquipIndex(index)
    return math.floor(index / 256) % 256, index % 256;
end

-- The client resource for whatever is worn in a slot, or nil. ONE memory walk
-- that every worn-item reader shares (name, level); wornPair does the same walk
-- for the pair key. Never throws.
local function wornResOf(slotKey)
    local res = nil;
    pcall(function()
        local id = SLOT_EQUIP_ID[string.lower(tostring(slotKey))];
        if id == nil then return; end
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local eitem = inv:GetEquippedItem(id);
        if eitem == nil or eitem.Index == 0 then return; end
        local item = inv:GetContainerItem(M.decodeEquipIndex(eitem.Index));
        if item == nil or item.Id == nil or item.Id == 0 then return; end
        res = AshitaCore:GetResourceManager():GetItemById(item.Id);
    end);
    return res;
end

-- Exactly ONE return value, deliberately: `return planned[ls], wornItemName(ls)`
-- (v94, :3890) would splat a second one into its caller's result list.
local function wornItemName(slotKey)
    local res = wornResOf(slotKey);
    if res ~= nil and res.Name ~= nil then return res.Name[1]; end
    return nil;
end

-- Public worn-name read (issue #138). The Action sequencer verifies its claim
-- landed by reading what is WORN through this door -- the engine's own twin of
-- the oracle's wornItem (the sequencer lives in feature/, one require away).
function M.wornName(slotKey) return wornItemName(slotKey); end

local function playerMP()
    local cur, max, mpp = nil, nil, nil;
    pcall(function() cur = gData.GetPlayer().MP; end);
    pcall(function() max = AshitaCore:GetMemoryManager():GetPlayer():GetMPMax(); end);
    -- Same packet family as cur (data.lua reads both off the party) -- the
    -- live anchor; GetMPMax is fallback-only below full (v86/v87, see
    -- M.mpReconcileMax / M.mpPoolFull).
    pcall(function() mpp = AshitaCore:GetMemoryManager():GetParty():GetMemberMPPercent(0); end);
    return tonumber(cur), M.mpReconcileMax(cur, max, mpp), M.mpPoolFull(cur, max, mpp);
end

-- ---------------------------------------------------------------------------
-- MaxMP v2 -- the banded ladder (engine v88; feature/mpbands.lua is the pure
-- core, docs/design/maxmp-mode.md "v2" is the spec). The v1 per-dispatch
-- marginal decisions (equip at full, hold at a boundary, release past a
-- surplus -- v76..v87) are retired: their pure rules stay exported for
-- compatibility, but the engine now walks a PRECOMPUTED threshold ladder
-- where current MP is the only live input. The v1 15s cooldown is gone too:
-- each band's dead zone is its own hysteresis.
-- ---------------------------------------------------------------------------

-- The LOW map: per slot, the LEAST MP any trigger-reachable set puts there
-- (the "potency point" -- what the slot drops to when its battery releases).
-- Scans every rule's named sets (through the live gProfile) and inline equip
-- tables; dlac: virtuals count their fallback piece. TTL-cached 10s -- set
-- and trigger edits are picked up within a beat, no invalidation plumbing.
local _mpLow = { at = 0, map = nil, rf = nil };
-- The maxmp WARM TRACE (v117, Henrik's debug-file rule applied to this fight):
-- every full LOW-map compute -- boot storm, belief, steady-state expiries --
-- appends one line to <data home>\debug-mpwarm.txt (fresh file per session,
-- capped), so the next wrong ladder is a MOVIE with named stages instead of a
-- screenshot. Read it bottom-up: the last lines before 'believed' name what
-- the world looked like when the ladder was trusted.
-- Debug artifacts live in <data home>\debug\ (Henrik's folder rule,
-- 2026-07-23: "keep debugs in a separate debug folder") -- the addon-tree
-- reports (feature\debug.lua, the load beacon) already comply; per-char
-- debug files land here. The LAC-bridge handoff files (debug-request /
-- debug-*-engine) stay at the char root untouched: their paired readers are
-- field-proven bridge protocol, and the whole family leaves with LAC.
local _mpWarm = { n = 0, opened = false };
local function mpWarmNote(line)
    if _mpWarm.n >= 150 then return; end
    _mpWarm.n = _mpWarm.n + 1;
    pcall(function()
        local dir = charDir();
        if dir == nil then return; end
        if not _mpWarm.opened then
            pcall(function()
                if ashita and ashita.fs and ashita.fs.create_directory then
                    ashita.fs.create_directory(dir .. 'debug\\');
                end
            end);
            pcall(os.remove, dir .. 'debug-mpwarm.txt');   -- sweep the pre-rule location
        end
        local f = io.open(dir .. 'debug\\mpwarm.txt', _mpWarm.opened and 'a' or 'w');
        if f == nil then return; end
        _mpWarm.opened = true;
        f:write(string.format('%s %7.2f  %s\n', os.date('%H:%M:%S'), os.clock(), line));
        f:close();
    end);
end
M._mpWarmNote = mpWarmNote;

local function mpLowMap(mpMap, rfMap)
    -- cache hits are always READY results (unready is never cached below)
    if _mpLow.map ~= nil and os.time() < _mpLow.at then return _mpLow.map, _mpLow.rf, true; end
    _mpLow.at = os.time() + 10;
    local low, lowRf = {}, {};
    local _mpLowReady = false;
    local _ruleN, _setN = 0, 0;   -- world-signature inputs (v116)
    local _rulesState, _setsState = '?', '?';   -- warm-trace attestation detail (v117)
    local function scanSet(set)
        if type(set) ~= 'table' then return; end
        for slot, v in pairs(set) do
            local lslot = string.lower(tostring(slot));
            if not MP_HOLD_EXEMPT[lslot] then
                local nm = nil;
                if type(v) == 'string' then nm = v;
                elseif type(v) == 'table' and type(v.Name) == 'string' then nm = v.Name; end
                if nm ~= nil and string.lower(string.sub(nm, 1, 5)) == 'dlac:' then
                    local p = string.find(nm, '|', 1, true);
                    nm = (p ~= nil) and string.sub(nm, p + 1) or nil;
                end
                if nm ~= nil then
                    local k = string.lower(nm);
                    local mp = mpMap[k] or 0;
                    local rfv = (rfMap ~= nil) and (rfMap[k] or 0) or 0;
                    if low[lslot] == nil or mp < low[lslot] then
                        low[lslot] = mp;
                    end
                    -- The refresh baseline is the POTENTIAL refresh -- the MOST
                    -- any trigger-reachable set puts in the slot (Henrik's
                    -- round-10 words verbatim; v95). It was the min-MP piece's
                    -- refresh before, which reads 0 the moment any combat set
                    -- writes the slot with potency gear -- every [refresh-cost]
                    -- tag vanished and the Hlr.-over-Clr. band sorted deep and
                    -- plain, firing at MP ~800 (field round 13).
                    if rfv > (lowRf[lslot] or 0) then lowRf[lslot] = rfv; end
                end
            end
        end
    end
    pcall(function()
        local rules = ensureLoaded();
        local sets = M._nativeSets;   -- the one sets store (purge Phase 2)
        -- ready = the trigger WORLD resolved (rules loaded, or the path
        -- resolved and the file is legitimately absent -- a trigger-less job
        -- is ready with empty rules) AND a sets source existed.
        _mpLowReady = ((rules ~= nil or _trig.path ~= nil) and sets ~= nil);
        _rulesState = (rules ~= nil) and 'ok'
            or (_trig.path ~= nil and 'nil(path=' .. tostring(_trig.path):match('([^\\]+)$') .. (_trig.err ~= nil and ',ERR' or '') .. ')' or 'path-nil');
        _setsState = (sets == nil) and 'nil' or 'ok';
        -- Henrik's field note (round 3b): the empty glimpse PREDATES native.
        -- LAC mode stages its boot the same way -- the profile auto-install
        -- latch fills Dynamic on the tick AFTER a /lac load / job change, so
        -- the live Dynamic can be an empty scaffold while the profile sets
        -- file exists. That window is UNREADY in both modes: install pending.
        -- (Statics-only characters have no profile file -- they stay ready.)
        if _mpLowReady and type(sets) == 'table' then
            local dyn = sets.Dynamic;
            if type(dyn) == 'table' and next(dyn) == nil then
                local job = nil;
                pcall(function() job = gData.GetPlayer().MainJob; end);
                if type(job) == 'string' and job ~= '?' and job ~= ''
                   and _pok and type(_prof.hasSetsFile) == 'function' then
                    local has = false;
                    pcall(function() has = _prof.hasSetsFile(job) == true; end);
                    if has then _mpLowReady = false; _setsState = 'dyn-empty+file'; end
                end
            end
        end
        -- the rules-side twin (v116): rules nil while a profile trigger file
        -- EXISTS for this job = the trigger world is mid-resolution (the
        -- legacy-path boot window), not legitimately trigger-less.
        if _mpLowReady and rules == nil then
            local job = nil;
            pcall(function() job = gData.GetPlayer().MainJob; end);
            if type(job) == 'string' and job ~= '?' and job ~= ''
               and _pok and type(_prof.hasTriggersFile) == 'function' then
                local has = false;
                pcall(function() has = _prof.hasTriggersFile(job) == true; end);
                if has then _mpLowReady = false; _rulesState = 'nil+file-exists'; end
            end
        end
        for _, list in pairs(rules or {}) do
            for _, r in ipairs(list) do
                _ruleN = _ruleN + 1;
                if r.equip ~= nil then scanSet(r.equip); end
                for _, sn in ipairs(r.sets or {}) do
                    if sets ~= nil and type(sets[sn]) == 'table' then
                        _setN = _setN + 1;
                        scanSet(sets[sn]);
                    end
                end
            end
        end
    end);
    -- READINESS (v114) + THE STABILITY LATCH (v116). The v114/v115 proxy
    -- attestations (rules resolved, sets present, Dynamic installed) each got
    -- lied to one level deeper during the boot storm (Henrik's round-4
    -- capture: the gate fired, then PASSED six seconds later with lows still
    -- 0 -- a resolved-but-legacy trigger path reads as "legitimately
    -- trigger-less", a first flatten can leave hollow set tables). So the
    -- result now attests ITSELF: a ready answer is only believed -- and only
    -- cached -- once two computes >= 2s apart produce the IDENTICAL world
    -- signature (lows + refresh baselines + rule/set counts). A converging
    -- world disagrees with itself; a settled one agrees. Consults ride the
    -- 0.4s Default tick, so belief lands ~2.4s after the world settles --
    -- and a mid-session set edit earns the same 2s re-agreement blip
    -- (batteries hold worn through it, by design).
    local sigParts = {};
    for k, v in pairs(low) do
        sigParts[#sigParts + 1] = k .. '=' .. tostring(v) .. ':' .. tostring(lowRf[k] or 0);
    end
    table.sort(sigParts);
    -- flatten counts ride the signature too (v118 belt): a store identity
    -- change (0 flats -> 20 flats) can never share a signature with its
    -- predecessor even when the scanned lows happen to match.
    local _flatN, _hollowN = 0, 0;
    pcall(function()
        local src = M._nativeSets;
        if type(src) == 'table' then
            for k, v in pairs(src) do
                if k ~= 'Dynamic' and type(v) == 'table' then
                    _flatN = _flatN + 1;
                    if next(v) == nil then _hollowN = _hollowN + 1; end
                end
            end
        end
    end);
    local sig = table.concat(sigParts, ',') .. '|r' .. tostring(_ruleN) .. '|s' .. tostring(_setN)
        .. '|f' .. tostring(_flatN) .. '|h' .. tostring(_hollowN);
    local latchState = 'attest-failed';
    if _mpLowReady then
        local nowc = os.clock();
        if sig ~= _mpLow.sig then
            _mpLow.sig, _mpLow.sigAt = sig, nowc;   -- first sight of this world: sample again
            _mpLowReady = false;
            latchState = 'new-sig';
        elseif (nowc - (_mpLow.sigAt or 0)) < 2.0 then
            _mpLowReady = false;                     -- agreed, but not for 2s yet
            latchState = 'young';
        else
            latchState = 'BELIEVED';
        end
    end
    -- the warm-trace line: the whole world in one row
    pcall(function()
        local lowsNZ = 0;
        for _, v in pairs(low) do if (tonumber(v) or 0) > 0 then lowsNZ = lowsNZ + 1; end end
        local gearN = 0;
        pcall(function()
            local g = package.loaded['dlac\\gear'];
            if type(g) == 'table' and type(g.NameToObject) == 'table' then
                for _ in pairs(g.NameToObject) do gearN = gearN + 1; end
            end
        end);
        local mpN = 0;
        for _ in pairs(mpMap or {}) do mpN = mpN + 1; end
        mpWarmNote(string.format('%s  rules=%s sets=%s ruleN=%d setN=%d lowsNZ=%d gearN=%d mpN=%d flat=%d hollow=%d',
            latchState, _rulesState, _setsState, _ruleN, _setN, lowsNZ, gearN, mpN, _flatN, _hollowN));
    end);
    if not _mpLowReady then
        _mpLow.at = 0;   -- never cache an unbelieved answer
    end
    _mpLow.map, _mpLow.rf = low, lowRf;
    return low, lowRf, _mpLowReady;
end

-- Every wearable, non-pair-vetoed rung of a slot's battery ladder (v90) --
-- the multi-rung band builder wants them ALL (a refresh mid-rung like
-- Bunzi's Hat is its own band; field round 9). The ONE resolver the engine,
-- the band builder and /dl plan share, so what is planned is what equips.
function M.mpRungs(mpBest, lslot, level, wornOf)
    if type(mpBest) ~= 'table' then return nil; end
    local cands = mpBest[lslot];
    if type(cands) ~= 'table' then return nil; end
    local list = (cands.name ~= nil) and { cands } or cands;
    local sib = M.MP_PAIR[lslot];
    local out = nil;
    for _, r in ipairs(list) do
        if type(r) == 'table' and type(r.name) == 'string'
           and (tonumber(r.level) or 0) <= (tonumber(level) or 0) then
            if sib == nil or wornOf == nil
               or not M.mpPairSkip(r.name, wornOf(sib), mpBest[sib]) then
                out = out or {};
                out[#out + 1] = r;
            end
        end
    end
    return out;
end

-- The single best rung (compat shim over mpRungs -- tests MPS8*).
function M.mpBestPick(mpBest, lslot, level, wornOf)
    local rungs = M.mpRungs(mpBest, lslot, level, wornOf);
    return (rungs ~= nil) and rungs[1] or nil;
end

-- The live band context: everything the dispatch pass AND /dl plan need,
-- built from the manifest + the trigger sets + current MP in one place.
-- TOTAL anchor: predicted worn-loadout max (nativemp base + auto-learned
-- merits + every worn piece's manifest MP) corrected by ONE offset learned
-- whenever the party MP% reads a true full (the maxmp~=modmp lesson: never
-- trust computed absolutes alone); plus the un-worn batteries' headroom.
-- Fallback chain: no base -> the low-biased live read; no manifest/module ->
-- nil (the caller warns once). Returns { bands, bandOf, target, hi, cur,
-- total, tick, low, resting, mpMap }.
function M.mpBands(ctx)
    -- One dispatch samples ONE moment (the fold's purity ruling): the claim
    -- build, the row apply and the mp-hold constraint all see the same bands.
    if type(ctx) == 'table' and ctx._mpBandsMemo ~= nil then return ctx._mpBandsMemo; end
    if _mpb == nil then return nil; end
    local a = ensureAutoLoaded();
    if a == nil or type(a.mp) ~= 'table' or type(a.mpBest) ~= 'table' then return nil; end
    local mpMap, mpBest = a.mp, a.mpBest;
    local rfMap = (type(a.rf) == 'table') and a.rf or {};
    local cur, maxLo, full = playerMP();
    local lvl = playerLevel(ctx or {});
    local low, lowRf, lowReady = mpLowMap(mpMap, rfMap);
    -- READINESS GATE (v114; widened v115): no ladder from a half-loaded
    -- world -- the order is a pure function of manifest + sets + rules
    -- (Henrik's spec), so until all three are attested this answers nil: the
    -- live overlay holds worn gear untouched and /dl plan says it is warming
    -- up. BOTH modes stage their boot (the install latch fills Dynamic on a
    -- tick after load) -- Henrik's field note: the glimpse predates native,
    -- LAC mode raced identically all along.
    if not lowReady then return nil; end
    do
        local s = M._nativeSets;
        local any = false;
        if type(s) == 'table' then
            for k in pairs(s) do
                if k ~= 'Dynamic' then any = true; break; end
            end
        end
        if not any then return nil; end   -- store present but no flattened sets yet
    end
    local resting = false;
    pcall(function()
        local st = (ctx ~= nil and ctx.player ~= nil) and ctx.player.Status or gData.GetPlayer().Status;
        resting = (st == 'Resting');
    end);
    local hi, slots, sumHead = {}, {}, 0;
    -- Locks veto by RANK (ADR 0012, step 3): MaxMP builds a band on a locked slot
    -- ONLY when it is ranked ABOVE Locks (it punches through). The rank is read
    -- straight off ctx.rankOf (set before the claim builds -- the FOLD, stage 6);
    -- nil ctx (/dl plan, tests) = respect locks (the pre-step-3 behavior). The
    -- consult stays HERE and not just in the delivery: a locked slot's rungs
    -- must leave the threshold math too, or the bands drift from what can dress.
    local mpRespectsLocks = true;
    if type(ctx) == 'table' and type(ctx.rankOf) == 'table' then
        local rm, rl = ctx.rankOf['MaxMP'], ctx.rankOf['Locks'];
        if rm ~= nil and rl ~= nil and rm < rl then mpRespectsLocks = false; end
    end
    for lslot in pairs(MP_SLOT_CANON) do
        if not mpRespectsLocks or M.locks[lslot] ~= true then
            -- ALL wearable rungs (v90): each refresh mid-rung becomes its own
            -- band, so Bunzi's Hat and Hlr. Bliaut +1 hold their late-order
            -- places instead of being invisible under the top pick. Refresh
            -- rides each rung (augments counted, fmtver 12).
            local rungs = M.mpRungs(mpBest, lslot, lvl, wornItemName);
            if rungs ~= nil and rungs[1] ~= nil then
                local rr = {};
                for _, r in ipairs(rungs) do
                    rr[#rr + 1] = { name = r.name, mp = r.mp or 0,
                                    rf = tonumber(r.rf) or rfMap[string.lower(r.name)] or 0 };
                end
                hi[lslot] = { name = rungs[1].name, mp = rungs[1].mp or 0 };
                slots[#slots + 1] = { slot = lslot, rungs = rr,
                                      low = low[lslot] or 0,
                                      lowRf = lowRf[lslot] or 0 };
                local w = wornItemName(lslot);
                local wmp = (w ~= nil) and (mpMap[string.lower(w)] or 0) or 0;
                sumHead = sumHead + math.max(0, (rungs[1].mp or 0) - wmp);
            end
        end
    end
    local predWorn = nil;
    if _nmp ~= nil and type(_nmp.self) == 'function' then
        local meritLv = math.floor(tonumber(a.mpMerits) or 0);
        if meritLv < 0 then meritLv = 0; elseif meritLv > 10 then meritLv = 10; end
        local okb, b = pcall(_nmp.self, meritLv * 10);
        if okb and tonumber(b) ~= nil then
            predWorn = tonumber(b);
            for lslot in pairs(SLOT_EQUIP_ID) do
                local w = wornItemName(lslot);
                if w ~= nil then predWorn = predWorn + (mpMap[string.lower(w)] or 0); end
            end
        end
    end
    local wornMax;
    if full and cur ~= nil then
        wornMax = cur;                       -- MPP == 100: the worn max, exact
        if predWorn ~= nil then M._mpOffset = cur - predWorn; end
    elseif predWorn ~= nil then
        wornMax = predWorn + (tonumber(M._mpOffset) or 0);
    else
        wornMax = maxLo;                     -- degraded: the low-biased read
    end
    if wornMax == nil then return nil; end
    local tick = _mpb.tick(resting);
    local bands = _mpb.build(slots, wornMax + sumHead, tick);
    local target = _mpb.target(bands, cur, wornItemName);
    -- Movement yield (v96): the setting + the movement map ride the manifest;
    -- moving comes from the same ctx read the `moving` trigger matcher uses.
    local moving = false;
    pcall(function()
        moving = (ctx ~= nil and ctx.player ~= nil) and (ctx.player.IsMoving == true)
                 or (gData.GetPlayer().IsMoving == true);
    end);
    local mpc = { bands = bands, target = target, hi = hi,
             cur = cur, total = wornMax + sumHead, tick = tick, low = low,
             resting = resting, mpMap = mpMap, mpBest = mpBest,
             moveYield = (a.mpMoveYield == true),
             mvMap = (type(a.mv) == 'table') and a.mv or {},
             moving = moving };
    if type(ctx) == 'table' then ctx._mpBandsMemo = mpc; end
    return mpc;
end

-- STICKY paired slots (v93, Henrik's ruling: "MP earrings and rings...
-- don't move positions once set"). A candidate whose piece is already
-- CLAIMED by the sibling ear/ring never writes here -- claimOf(sib)
-- answers this dispatch's PLAN first, then the worn state. The v83 pick
-- veto reads only worn state, which lags ~a dispatch behind LAC's swaps;
-- the PLAN cannot lag, so the tug that bounced Loquacious between ears
-- (the set planting it in ear2 while the band pulled it toward its
-- ladder home in ear1) dies at the apply site. Genuine duplicates stay
-- exempt via mpPairSkip (dup-owned items ride BOTH paired ladders).
-- claimsOf(sib) answers BOTH claims -- the sibling's planned piece and its
-- worn piece -- and EITHER vetoes (v94: `plan or worn` shadowed the worn
-- claim whenever the plan named a different piece, so a set displacing the
-- earring from ear2 left the worn signal unread and the band relocated it).
-- Returns kept-candidates, sticky-skipped { c, sib, claimed }.
function M.mpStickyPairs(cands, claimsOf, mpBest)
    local keep, moved = {}, nil;
    for _, c in ipairs(cands or {}) do
        local sib = M.MP_PAIR[c.lslot];
        local hit = nil;
        if sib ~= nil and claimsOf ~= nil then
            local p, w = claimsOf(sib);
            local lad = (mpBest ~= nil) and mpBest[sib] or nil;
            if p ~= nil and M.mpPairSkip(c.name, p, lad) then hit = p;
            elseif w ~= nil and M.mpPairSkip(c.name, w, lad) then hit = w; end
        end
        if hit ~= nil then
            moved = moved or {};
            moved[#moved + 1] = { c = c, sib = sib, claimed = hit };
        else
            keep[#keep + 1] = c;
        end
    end
    return keep, moved;
end

-- The band a (slot, piece) pair belongs to -- notes and the plan look
-- thresholds up by name now that a slot can carry several bands (v90).
function M.mpBandFind(bands, lslot, name)
    for _, b in ipairs(bands or {}) do
        if b.slot == lslot and b.name ~= nil and name ~= nil
           and string.lower(tostring(b.name)) == string.lower(tostring(name)) then
            return b;
        end
    end
    return nil;
end

-- ---------------------------------------------------------------------------
-- Open-menu name (diagnostic, shown by /dl env). Standard FFXiMain menu
-- pattern, tCrossBar/HXUI lineage. NOTE: a v14 build PAUSED swaps while the
-- equipment screen was open, on the retail ghost-gear lore -- field-FALSIFIED
-- on CatsEyeXI (/lac equip works fine with the window up; the menu lock is
-- client-side and injected packets bypass it). The real "stops working in the
-- equipment window" cause was dispatch starvation: LAC only parses
-- HandleDefault while OUTGOING packets flow -- fixed by the engine tick (see
-- the d3d_present registration in the command section).
-- ---------------------------------------------------------------------------
local pGameMenu = nil;
pcall(function()
    pGameMenu = ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0);
end);

local function menuName()
    local nm = '';
    pcall(function()
        if pGameMenu == nil or pGameMenu == 0 then return; end
        local sub = ashita.memory.read_uint32(pGameMenu);
        if sub == nil or sub == 0 then return; end
        local val = ashita.memory.read_uint32(sub);
        if val == nil or val == 0 then return; end
        local hdr = ashita.memory.read_uint32(val + 4);
        if hdr == nil or hdr == 0 then return; end
        local s = ashita.memory.read_string(hdr + 0x46, 16);
        if type(s) == 'string' then nm = (string.gsub(s, '\x00', '')); end
    end);
    return nm;
end
M.menuName = menuName;   -- craftwatch reads it to equip while the synth window is OPEN
                         -- (before you confirm -- injected equips bypass the menu lock)

-- ---------------------------------------------------------------------------
-- Type automation: AutoAcc (Henrik 2026-07-14). Set entries typed AutoAcc
-- flatten to 'dlac:AutoAcc:<prio>:<acc>:<Name>|<fallback>' (utils.BuildDynamicSets).
-- accwatch (addon state) measures the cap gap per engage and publishes it to
-- <char>\dlac\accstate.lua; THIS state hot-reads it and, while the player is
-- OVER the hit cap, RELEASES AutoAcc pieces -- highest removal priority first,
-- only while the piece's baked ACC fits inside the measured surplus -- wearing
-- the slot's fallback (its normal best pick) instead. Feedback loop: the next
-- engage measures ACC with the released pieces off, so the budget rebuilds as
-- measured surplus + sum(released accs) and the decision self-corrects (harder
-- mob -> the pieces come back on). Invalid/stale/missing state (unknown mob,
-- watch off, no measurement yet) -> every AutoAcc piece stays worn: the set
-- behaves exactly as if nothing were typed.
-- NOTE (main): the WRITER (accwatch.lua + accdata.lua) ships on
-- feature/autoacc pending GM approval -- on main nothing writes accstate.lua,
-- so this machinery is dormant foundation: markers always resolve to "worn".
-- ---------------------------------------------------------------------------
local _accfile = { raw = nil, data = nil, lastCheck = -1 };
local ACC_STALE_S = 900;   -- measurements older than 15 min are not acted on

local function ensureAccState()
    if M._accStateOverride ~= nil then return M._accStateOverride; end   -- headless test seam
    return ensureStateFile(_accfile, 'accstate.lua');
end

-- 'dlac:AutoAcc:<prio>:<acc>:<Name>' -> prio, acc, name (nil unless it parses).
-- The name is the LAST field on purpose: item names never need escaping then.
local function parseAccMarker(mk)
    if type(mk) ~= 'string' then return nil; end
    if string.lower(string.sub(mk, 1, 13)) ~= 'dlac:autoacc:' then return nil; end
    local prio, acc, name = string.match(string.sub(mk, 14), '^(%-?%d+):(%-?%d+):(.+)$');
    if name == nil then return nil; end
    return tonumber(prio), tonumber(acc), name;
end
M._parseAccMarker = parseAccMarker;   -- headless tests

M._accRemoved = {};    -- lower(name) -> baked ACC of every piece currently RELEASED
local _accSeq = nil;   -- last accstate.seq folded into the budget
local _accBudget = 0;  -- the all-worn surplus, frozen once per measurement

-- The pure removal rule (headless-tested): given one set's candidates and the
-- frozen budget, release by DESCENDING removal priority while the baked ACC
-- fits. A candidate with no fallback or no ACC is never released (nothing
-- better to wear / nothing to gain). Ties break on higher acc, then slot name
-- -- deterministic, so every dispatch of a fight agrees with the last one.
function M._accDecide(cands, budget)
    local order = {};
    for i, c in ipairs(cands) do order[i] = c; end
    table.sort(order, function(a, b)
        if (a.prio or 0) ~= (b.prio or 0) then return (a.prio or 0) > (b.prio or 0); end
        if (a.acc or 0) ~= (b.acc or 0) then return (a.acc or 0) > (b.acc or 0); end
        return tostring(a.slot) < tostring(b.slot);
    end);
    local pick, released = {}, {};
    local b = budget;
    for _, c in ipairs(order) do
        if c.fallback ~= nil and (c.acc or 0) > 0 and c.acc <= b then
            pick[c.slot] = c.fallback;
            released[string.lower(c.name)] = c.acc;
            b = b - c.acc;
        else
            pick[c.slot] = c.name;
        end
    end
    return pick, released;
end

-- Decisions for one set table: { [slot] = item name } covering every AutoAcc
-- marker in it (the piece itself, or its fallback when released); nil when the
-- set carries none. Locked slots are skipped (the lock branch strips them).
local function accResolveSet(s)
    local cands = nil;
    for slot, v in pairs(s) do
        if type(v) == 'string' and M.locks[string.lower(tostring(slot))] ~= true then
            local marker, fallback = v, nil;
            local p = string.find(v, '|', 1, true);
            if p ~= nil then marker, fallback = string.sub(v, 1, p - 1), string.sub(v, p + 1); end
            local prio, acc, name = parseAccMarker(marker);
            if name ~= nil then
                cands = cands or {};
                cands[#cands + 1] = { slot = slot, prio = prio or 1, acc = acc or 0,
                                      name = name, fallback = fallback };
            end
        end
    end
    if cands == nil then return nil; end
    local st = ensureAccState();
    local usable = type(st) == 'table' and st.valid == true
               and type(st.capGap) == 'number'
               and (tonumber(st.at) == nil or os.time() - st.at < ACC_STALE_S);
    if not usable then
        -- No trustworthy measurement -> AutoAcc stands down: wear every piece.
        local pick = {};
        for _, c in ipairs(cands) do
            pick[c.slot] = c.name;
            M._accRemoved[string.lower(c.name)] = nil;
        end
        return pick;
    end
    if st.seq ~= _accSeq then
        -- Fresh measurement: rebuild the budget ONCE per seq. capGap was
        -- measured with the currently-released pieces OFF, so the all-worn
        -- surplus is the measured surplus plus everything already released.
        _accSeq = st.seq;
        local sum = 0;
        for _, a in pairs(M._accRemoved) do sum = sum + a; end
        _accBudget = -(tonumber(st.capGap) or 0) + sum;
    end
    local pick, released = M._accDecide(cands, _accBudget);
    for _, c in ipairs(cands) do
        M._accRemoved[string.lower(c.name)] = released[string.lower(c.name)];
    end
    return pick;
end
M._accResolveSet = accResolveSet;   -- headless tests
function M._accReset()              -- headless tests: fresh-session state
    M._accRemoved = {}; _accSeq = nil; _accBudget = 0;
end

-- ---------------------------------------------------------------------------
-- Reserved slots (RSlot) -- MOVED to gearrbiter.lua (ADR 0027, stage 3):
-- the bit-order vocabulary, rslotText, reservedDrops, the v135 dominance
-- verdict (reserveFloor/reserveVerdict) and the stage-2 fall (reserveResolve)
-- live there now, verbatim. The aliases + re-exports below keep every
-- internal caller, GUI reader and test seam on its old door.
-- ---------------------------------------------------------------------------
local RSLOT_ORDER = ARB.RSLOT_ORDER;
local hasBit = ARB.hasBit;
M.rslotText      = ARB.rslotText;
M.reservedDrops  = ARB.reservedDrops;
M.reserveFloor   = ARB.reserveFloor;
M.reserveVerdict = ARB.reserveVerdict;
M.reserveResolve = ARB.reserveResolve;

-- (The Range/Ammo PAIR LAW -- trinketRangeDrop + trinketWornDisplace, ADR
--  0010's decision rules verbatim -- MOVED to gearrbiter.lua, the
--  pair-law migration step of ADR 0027 stage 3. Re-exported here, so the
--  trinket-vs-ranged post-pass and the TB* tests keep their doors.)
M.trinketRangeDrop    = ARB.trinketRangeDrop;
M.trinketWornDisplace = ARB.trinketWornDisplace;
-- The two above asked ONCE, of the merged floor (v159) -- the door the GUI's
-- Set totals read through, so the numbers and the engine cannot drift.
M.pairVerdict         = ARB.pairVerdict;
-- Which verdict speaks for a slot, in the renderers' own order -- the ONE
-- ANSWER PER SLOT rule every renderer asks (two-way-arbiter.md §11).
M.slotVerdict         = ARB.slotVerdict;


-- (splitPair / SKILL_ARCHERY / pairsWith -- the PAIR LAW's core -- moved to
--  gearrbiter.lua with the trinket family. Re-exported: resolveAmmoPlan
--  and the tests keep their doors.)
M._splitPair    = ARB._splitPair;
M.SKILL_ARCHERY = ARB.SKILL_ARCHERY;
M.pairsWith     = ARB.pairsWith;

-- The same scope ruling from the OTHER side: MP-EQUIP is an outside-the-set
-- writer, so a battery whose RSlot reserves an OCCUPIED slot never stages (a
-- Rimestone landing in Ammo makes the server strip the planned or worn
-- instrument out of Range). Filtering the candidates -- rather than letting
-- trinket-vs-ranged drop the piece afterwards -- keeps the ONE staged equip
-- per dispatch meaningful: a doomed biggest-gain pick would win the stage
-- every full-pool dispatch and starve every other slot's battery forever.
--   occupantFn(lslot) -- what the slot holds if this dispatch leaves it alone:
--                        the plan's name for it, else the worn piece ('remove'
--                        counts as free).
-- Returns kept, skipped; skipped entries are { c = cand, blocking = lslot }.
function M.mpStageEligible(cands, occupantFn, rslotFn)
    if type(cands) ~= 'table' then return cands, nil; end
    local keep, skipped = {}, nil;
    for _, c in ipairs(cands) do
        local mask = tonumber(rslotFn(c.name)) or 0;
        local blocking = nil;
        if mask > 0 then
            for _, e in ipairs(RSLOT_ORDER) do
                local ls = string.lower(e[2]);
                if ls ~= tostring(c.lslot) and hasBit(mask, e[1]) then
                    local occ = occupantFn(ls);
                    if type(occ) == 'string' and occ ~= 'remove' then
                        blocking = ls;
                        break;
                    end
                end
            end
        end
        if blocking == nil then
            keep[#keep + 1] = c;
        else
            skipped = skipped or {};
            skipped[#skipped + 1] = { c = c, blocking = blocking };
        end
    end
    return keep, skipped;
end

-- Animator-fed ammo: the four Automaton Oils. item_weapon gives them subskill 10,
-- the subskill of every Animator, so the server KEEPS oil + Animator together --
-- never a Range reservation, whatever the gear.lua stamp says (files written
-- before 2026.07.22g carry a wrongly-completed RSlot=4, and the engine must not
-- displace a manually equipped oil on the strength of it). Engine-owned mirror
-- of gearrecord.ANIMATOR_FED (the seeded state cannot require addon modules);
-- test TR17 pins the two id-sets equal.
local ANIMATOR_FED = { [18731] = true, [18732] = true, [18733] = true, [19185] = true };

-- The RSlot a manifest record is TRUSTED for -- the stale-stamp guard lives here,
-- the one place record RSlot enters the engine. `cat(rec, which)` is the OPTIONAL
-- catalog reader (see catalogFact below): with no stamp on the record, the item's
-- own fact answers. Injected rather than reached for, so this stays pure and the
-- suite can drive both halves with no catalog on disk. Omitted = the pre-v160
-- behaviour exactly. The ANIMATOR_FED exemption is deliberately ABOVE the
-- fallback: it is a statement about the ITEM, so it must veto both sources.
-- Pure (tests TR16*, CF*).
function M.recordRSlot(rec, cat)
    if type(rec) ~= 'table' then return nil; end
    if ANIMATOR_FED[rec.Id] == true then return nil; end
    local m = tonumber(rec.RSlot);
    if m ~= nil then return m; end
    if type(cat) ~= 'function' then return nil; end
    local ok, v = pcall(cat, rec, 'rslot');
    return ok and tonumber(v) or nil;
end

-- The Range/Ammo pair key a record is trusted for -- recordRSlot's twin, same
-- precedence (stamp, then the item's own fact) and the same injected reader.
-- Pure (tests CF*).
function M.recordPair(rec, cat)
    if type(rec) ~= 'table' then return nil; end
    if type(rec.Pair) == 'string' and rec.Pair ~= '' then return rec.Pair; end
    if type(cat) ~= 'function' then return nil; end
    local ok, v = pcall(cat, rec, 'pair');
    if not ok or type(v) ~= 'string' or v == '' then return nil; end
    return v;
end

-- ---------------------------------------------------------------------------
-- THE ITEM FACTS COME FROM THE CATALOG (Henrik, 2026-08-01, on being told the
-- Pair stamp needed a `/dl fix` to reach existing files): "I feel like this
-- information should be documented in the catalog maybe? Instead of personal
-- gear... It's not like my personal Arcane arbalest can behave differently in
-- this aspect as anyone else's."
--
-- Exactly right, and it retires a whole class of bug. RSlot and Pair are facts
-- about the ITEM -- item_equipment.rslot and item_weapon skill/subskill, the
-- same for every copy in the world -- not facts about your copy. They were
-- stamped into each player's gear.lua only because the equip-time engine used
-- to run in LAC's OWN Lua state, which could not reach the 5MB catalog. THE
-- PURGE ENDED THAT: there is one state now, and dlac.lua preloads gearimport
-- and gearui at addon load, so the catalog is already resident in the very
-- state this runs in. (catalogindex's header still says "the equip-time engine
-- never loads the catalog" -- that sentence is a two-state-era artifact.)
--
-- So the manifest stamp becomes a CACHE, not the source of truth: read the
-- stamp, fall back to the catalog by id. What that fixes, for everybody, on the
-- addon update alone and with no file rewritten and no command to run:
--   * every gear.lua written before Pair existed (v128) was silently running
--     the pair law on the RSlot bit alone -- a gun and a crossbow were both
--     just "Marksmanship";
--   * every gear.lua written before RSlot existed (v43) had ADR 0010 fully
--     BLIND -- no bit, no pair key, so a stat stick and a ranged weapon were
--     never in conflict at all and flapped exactly as they did in 2026-07-19;
--   * a catalog correction now reaches every player with the next addon
--     update, instead of waiting for each of them to run `/dl fix`.
-- The stamp still WINS when present, so a stamped file behaves identically and
-- a hand-edited stamp is still honoured. gearimport owns both catalog readers
-- already (lazy, cached, guarded) and rslotFor applies effectiveRSlot -- which
-- is why Cinderstone gets its Range bit here even though the catalog row is one
-- of the crawl's gaps.
-- ---------------------------------------------------------------------------
local _gimpMod = nil;
local function catalogFact(rec, which)
    if type(rec) ~= 'table' or rec.Id == nil then return nil; end
    if _gimpMod == nil then
        _gimpMod = false;
        pcall(function() _gimpMod = require('dlac\\gear\\gearimport') or false; end);
    end
    if _gimpMod == false then return nil; end
    local fn = (which == 'pair') and _gimpMod.pairFor or _gimpMod.rslotFor;
    if type(fn) ~= 'function' then return nil; end
    local ok, v = pcall(fn, rec.Id);
    return ok and v or nil;
end

-- RSlot by item name: the manifest stamp, else the catalog. Resolved lazily and
-- guarded at every step -- no manifest, no catalog, no Id, or an item the crawl
-- never saw all answer nil, which every consumer reads as "no reservation", so
-- the engine degrades to exactly what it did before rather than misfiring.
local _gearMod = nil;
local function rslotOf(name)
    if _gearMod == nil then
        _gearMod = false;
        pcall(function() _gearMod = require('dlac\\gear') or false; end);
    end
    local m = nil;
    pcall(function()
        local rec = _gearMod and _gearMod.NameToObject and _gearMod.NameToObject[name] or nil;
        if rec ~= nil then m = M.recordRSlot(rec, catalogFact); end
    end);
    return m;
end
M._rslotOf = rslotOf;   -- test seam

-- Range/Ammo pair key by item name: the manifest stamp, else the catalog.
-- nil means "nothing can answer" -- an item the crawl never saw, an uncrawled
-- custom, or a slot that has no pairing at all. NEVER "pairs with nothing":
-- pairsWith is three-valued precisely so an unknown constrains nothing.
local function pairOf(name)
    if _gearMod == nil then
        _gearMod = false;
        pcall(function() _gearMod = require('dlac\\gear') or false; end);
    end
    local p = nil;
    pcall(function()
        local rec = _gearMod and _gearMod.NameToObject and _gearMod.NameToObject[name] or nil;
        if rec ~= nil then p = M.recordPair(rec, catalogFact); end
    end);
    return p;
end
M._pairOf = pairOf;   -- test seam

-- The pair key of what is WORN in a slot, best available answer:
--   1. the manifest's Pair       -- exact, carries subskill
--   2. the client resource Skill -- "26", subskill unknown (pairsWith reads that as
--                                   "cannot prove a mismatch", i.e. skill-level only)
--   3. nil                       -- nothing worn, or nothing known
-- Step 2 is what makes this fix reach EVERY player on the update alone: a manifest
-- written before Pair existed still separates a bow from a gun from a throwing weapon,
-- which is the whole headline bug. Refreshing the manifest upgrades it to telling a
-- gun from a crossbow. Returns (pair, name) -- callers want both and this decodes once.
local function wornPair(slotKey)
    local nm, pair = nil, nil;
    pcall(function()
        local id = SLOT_EQUIP_ID[string.lower(tostring(slotKey))];
        if id == nil then return; end
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local eitem = inv:GetEquippedItem(id);
        if eitem == nil or eitem.Index == 0 then return; end
        local item = inv:GetContainerItem(M.decodeEquipIndex(eitem.Index));
        if item == nil or item.Id == nil or item.Id == 0 then return; end
        local res = AshitaCore:GetResourceManager():GetItemById(item.Id);
        if res == nil then return; end
        if res.Name ~= nil then nm = res.Name[1]; end
        if nm ~= nil then pair = pairOf(nm); end
        if pair == nil then
            local sk = tonumber(res.Skill);
            -- Skill 0 is "no weapon skill" (pet food, stat sticks, Animators): it is a
            -- real value the manifest can pair on, but as a RESOURCE fallback it is
            -- indistinguishable from "this resource has no skill field", so it stays
            -- unknown rather than asserting a 0:? match.
            if sk ~= nil and sk > 0 then pair = tostring(sk); end
        end
    end);
    return pair, nm;
end
M._wornPair = wornPair;   -- test seam

-- Item Level by name, from the same gear manifest -- the tiebreak for the trinket/ranged
-- conflict. Guarded like rslotOf; a missing manifest reads as nil (-> 0 at the call site).
local function levelOf(name)
    if _gearMod == nil then
        _gearMod = false;
        pcall(function() _gearMod = require('dlac\\gear') or false; end);
    end
    local lv = nil;
    pcall(function()
        local rec = _gearMod and _gearMod.NameToObject and _gearMod.NameToObject[name] or nil;
        if rec ~= nil then lv = tonumber(rec.Level); end
    end);
    return lv;
end

-- The whole-table resolve order is DATA (v71): after the per-slot chain, these
-- five post-passes run in exactly this sequence -- reordering this list IS the
-- behavioral change, and the constraints that used to live only in prose are
-- adjacency here:
--   * trinket-vs-ranged MUST precede reserved-drops (ADR 0010: the loser must
--     never get to reserve anything, or the result flaps instead of settling);
--   * every post-pass judges the CURRENT names (pairs(out or s)): a slot an
--     earlier pass HELD (nil in out) is invisible to later passes, on purpose
--     (LS12: a held Range keeps its trinket judgement consistent).
-- The next overlay/post-rule gets an entry here, nowhere else. Tests PL* pin
-- this list as data.
local POST_ORDER = { 'mp-hold', 'craft-sub-guard', 'sync-hold-ammo',
                     'trinket-vs-ranged', 'reserved-drops' };
M._postPassOrder = POST_ORDER;

-- ---------------------------------------------------------------------------
-- The Arbiter's RANK VOCABULARY -- MOVED to gearrbiter.lua (ADR 0027,
-- stage 3): ARB_ORDER_DEFAULT, the pinned ceiling/floor rows, arbOrder (the
-- restore-at-default-position law, v122), the LOCK_HELD veto sentinel and
-- arbLockClaim live there now, verbatim. Re-exports keep the old doors --
-- LOCK_HELD keeps its IDENTITY (comparers rely on it being one object).
-- ---------------------------------------------------------------------------
M._arbDefaultOrder = ARB.ARB_ORDER_DEFAULT;
M._arbPinnedRows   = ARB.ARB_PINNED;
M.arbOrder     = ARB.arbOrder;
M.arbOrderPersist = ARB.arbOrderPersist;   -- the WRITE view (issue #136): keeps unknown rows
M.LOCK_HELD    = ARB.LOCK_HELD;
M.arbLockClaim = ARB.arbLockClaim;

-- ---------------------------------------------------------------------------
-- DISABLED SLOTS (ADR 0024) -- `/dl disable`, the ceiling.
--
-- What /lac disable is for, in the native era: hand a slot back to the player so
-- they can equip by hand and have it STAY. dlac had no equivalent -- the Equipped
-- tab's "Free equip" fires /lac disable, which under the native engine talks to a
-- LuaAshitacast that is no longer doing the equipping, so it did nothing at all.
--
-- Three things it deliberately is NOT:
--
--   * not a LOCK. A lock is a veto INSIDE the rank walk: a claimant ranked above
--     Locks punches straight through it (that punch-through is the Priority
--     list's whole promise, ADR 0012 step 3). "Do not touch this slot" cannot be
--     expressed by a thing that four other rows are allowed to overrule.
--   * not a CLAIM to dress. Every other row wins a slot in order to PUT SOMETHING
--     THERE -- even Naked, whose 'remove' is an instruction to strip. This one
--     wins a slot in order to write nothing, so it has no applyClaim equip and
--     could not have one: there is no item, and no unequip either.
--   * not gState.Disabled. That is LAC-only and sits BELOW the engine (issue #58,
--     a standing dlac ruling). This lives at dlac's own write seam, so it works
--     identically in both engines and nothing underneath it is fenced off.
--
-- So it is the CEILING: pinned above every row, undraggable, enforced in
-- engineEquipSet. It is registered as a claim ONLY so /dl why and the Priority
-- panel can name it -- a slot that silently stops responding, with nothing
-- anywhere to say why, is the failure this surface must not have.
-- ---------------------------------------------------------------------------

-- The claim value for a disabled slot -- "dlac writes nothing here". Distinct
-- from M.LOCK_HELD on purpose: a lock says "keep what is worn" and can be
-- overruled by rank; this says "not mine" and cannot.
M.DISABLED_FREE = setmetatable({}, { __tostring = function() return 'FREE-EQUIP'; end });

-- Is any slot disabled? (any == nil) -- or is THIS one? Slot names are lac-case.
function M.disabledOn(slot)
    if slot == nil then return next(M.disabledSlots) ~= nil; end
    return M.disabledSlots[string.lower(tostring(slot))] == true;
end

-- 'hands' -> 'Hands' for a chat line. The canon list is the display vocabulary
-- (Ring1, Ear2), so this is a lookup rather than a first-letter upper.
local SLOT_LABEL = {};
for i, s in ipairs(LAC_SLOTS) do SLOT_LABEL[s] = LAC_SLOTS_CANON[i]; end
function M.slotLabel(slot)
    slot = string.lower(tostring(slot or ''));
    return SLOT_LABEL[slot] or slot;
end

-- The disabled slots, sorted, in canonical LAC order (the /dl why + chat lists).
function M.disabledList()
    local out = {};
    for _, s in ipairs(LAC_SLOTS) do
        if M.disabledSlots[s] == true then out[#out + 1] = s; end
    end
    return out;
end

-- The Disabled claim for the Arbiter: { [Slot] = DISABLED_FREE } in the equip
-- vocabulary's proper case (what arbExplain displays), or nil when none. Unlike
-- Naked this claims ONLY the disabled slots -- claiming all 16 would be a lie in
-- /dl why, and there is no apply loop here for it to matter to.
function M.disabledClaim()
    if next(M.disabledSlots) == nil then return nil; end
    local out = nil;
    for i, s in ipairs(LAC_SLOTS) do
        if M.disabledSlots[s] == true then
            out = out or {};
            out[LAC_SLOTS_CANON[i]] = M.DISABLED_FREE;
        end
    end
    return out;
end

-- Flip a slot's disable. slot: one of LAC_SLOTS or 'all'; state nil = toggle.
-- Deliberately shaped like M.setLock -- same vocabulary, same 'all' fan-out, same
-- nil-for-unknown-slot -- because to a player these are two settings on one row
-- of the same gear menu, and a surface that behaves differently for no reason is
-- a bug even when every branch is correct. Returns the new state (for 'all': the
-- state applied), or nil for an unknown slot name.
--
-- No dispatch is kicked, for ADR 0021's reason: the 0.4s tick is the only Default
-- entry point carrying the zoning / player-action / sync-settle gates. Disabling
-- needs no pass at all (it only ever withholds), and ENabling lands on the next
-- one.
function M.setDisabled(slot, state)
    slot = string.lower(tostring(slot or ''));
    if slot == 'all' then
        if state == nil then state = (next(M.disabledSlots) == nil); end   -- toggle: all on if none on
        for _, s in ipairs(LAC_SLOTS) do M.disabledSlots[s] = (state == true) or nil; end
        if saveModeState ~= nil then pcall(saveModeState); end
        return state == true;
    end
    if not LAC_SLOT_OK[slot] then return nil; end
    if state == nil then state = not (M.disabledSlots[slot] == true); end
    M.disabledSlots[slot] = (state == true) or nil;
    if saveModeState ~= nil then pcall(saveModeState); end
    return M.disabledSlots[slot] == true;
end

-- ---------------------------------------------------------------------------
-- NAKED (ADR 0021) -- the strip, expressed as an ordinary Claim.
--
-- /lac naked is `for i=1,16 do gEquip.UnequipSlot(i); gState.Disabled[i]=true end`:
-- strip once, then fence the slots below the engine. dlac does the opposite --
-- it CLAIMS every slot with LAC's own unequip literal and lets the Arbiter apply
-- that claim on every dispatch. The difference is not stylistic:
--
--   * a lock (or a Disabled fence) only WITHHOLDS -- it deletes the slot from a
--     layer's plan (see the strip in equipResolved). It cannot take a piece OFF.
--     A lock-based naked is therefore strip-once + fence, and the fence is the
--     weak half: M.locks is wiped by every engine self-swap, Pins outrank Locks
--     by default and punch straight through, and three unrelated buttons
--     (/dl lock all off, the Sets tab's Unlock, unchecking Free equip) release
--     it. Worse, arming it would destroy the player's OWN locks. This is the
--     pinwatch argument (see pinOverlay's header) with the sign flipped;
--   * a claim is recomputed and re-applied EVERY dispatch, so every way the
--     server can refuse a strip -- dead or in a cutscene (the packet handler's
--     isNormalStatus gate), mid-ranged-attack (Range/Ammo silently ignored),
--     the level-sync settle holding the weapon slots -- heals itself on the next
--     pass instead of leaking a dressed slot forever;
--   * and precedence becomes the player's, for free. At rank 1 Naked outranks
--     everything, pins included. Drag Pins (or Locks) above it in Automations >
--     Claim Priority and you get "naked EXCEPT those" with no code at all.
--
-- The claim value is the literal 'remove', which BOTH engines already speak:
-- LuaAshitacast's MakeItemTable maps it to Index 0, and gear\equipcore.lua's
-- normalizeEntry/planSet do the same for the native engine. One table, one code
-- path, no per-mode arm.
-- ---------------------------------------------------------------------------

-- Is the strip armed? The ONE reader -- M.dispatch, /dl prio, /dl why, the
-- command branch and the GUI mirror all ask here, so "what naked means" is
-- never spelled twice.
function M.nakedOn() return M.nakedArmed == true; end

-- The Naked claim: every slot, emptied. A FRESH table per call -- the caller
-- hands it to the Arbiter, which keeps it for /dl why attribution.
--
-- Always all 16, even when you are already bare. The tempting optimization --
-- claim only the slots that currently hold something -- is a correctness bug:
-- the apply loop walks rank LOW to HIGH, so an unclaimed slot keeps whatever a
-- LOWER-ranked layer wrote into the buffer this pass. Drop the empty slots and a
-- MaxMP battery (or a pin, or the idle set) lands in every slot the previous
-- dispatch just cleared, one layer below a claimant that was supposed to own it.
function M.nakedClaim()
    local out = {};
    for _, s in ipairs(LAC_SLOTS_CANON) do out[s] = 'remove'; end
    return out;
end

-- (nakedVoidsPinReserve RETIRED, step-1 cleanup 2026-07-27: the pin-reserved
--  hold it existed to void is itself retired -- a dominant pin reserver now
--  suppresses slots through the cross-rank verdict (ARK4), where Naked
--  outranking Pins beats the reservation by ROW, no dance required.)

-- LEAVING THE WORLD DISARMS THE STRIP. Driven from the tick's job read, every
-- frame. This is the guard that makes "you can never log in naked" true, and it
-- has to exist because the flag's home does NOT die on a relog:
--
--   an Ashita addon SURVIVES A LOGOUT -- pinwatch's loadPinState header states it
--   as a known fact, and re-keying pins on the character dir is its answer. So in
--   native mode the addon state (and its require-cached dispatch) rides straight
--   through character select; in legacy mode LuaAshitacast never clears
--   package.loaded either. Neither engine gets a fresh Lua state. And pinwatch's
--   charDir re-key would not close it here anyway: a SAME-character relog yields
--   the same dir.
--
-- `job` nil or 0 is the character-select read -- the same "not in the world"
-- signal loadModeState already refuses to restore across. The login settle also
-- reads 0 for its first ~6s (the documented GetMainJob race), which is harmless:
-- clearing spuriously leaves you DRESSED, and at login that is what we want.
--
-- A JOB CHANGE ALSO DISARMS (Henrik, 2026-07-25), the maxmp drop's rule right
-- below this in the tick: changing job is a fresh loadout, and standing there
-- naked on the new job with nothing on screen to explain it is the same bad
-- outcome as the relog case. Main job only -- GetMainJob is what the tick reads,
-- so a SUBJOB swap does not drop it (identical to maxmp).
--
-- This only ever CLEARS, never arms. Returns 'world' | 'job' | nil -- what
-- cleared it, so the caller can say so (tests NK28).
--
-- ADR 0022 SHARES THIS WATCH, and v124 gives it ALL THREE ways the player can
-- deliberately hold gear still: the strip, a locked set, and plain slot locks.
-- One lifetime rule, Henrik's (2026-07-26): "I don't want locks to outlive a
-- relog, it should not outlive a main job change nor a log."
--
-- Slot locks were the odd one out, and only by accident. Nothing ever watched
-- them, so they rode straight through character select -- an Ashita addon
-- survives a logout and LuaAshitacast never clears package.loaded, so the module
-- table lives on. Before v123 an engine self-swap happened to wipe them, which
-- looked like a lifetime rule and was really a bug (a git pull unlocking your
-- gear mid-Incursion); fixing that removed the accident and left the gap plain.
--
-- None of the three is written to disk. All three are mirrored to modestate for
-- the GUI (__locks / __naked / __held) inside the reserved __ namespace that
-- loadModeState skips, so a mirror can never restore one.
--
-- This only ever CLEARS, never arms. Second return value names what was dropped
-- so the caller can say the right sentence; the first return stays
-- 'world' | 'job' | nil exactly as NK28 pins it.
-- ZONES SURVIVE (Henrik, 2026-07-27, pre-promotion: "I want /dl locks and
-- /dl naked to persist through zones"). The world read goes 0/nil during a
-- ZONE LOAD exactly as it does at character select, so absence alone no
-- longer drops anything -- only OUTLASTING a zone does:
--   'job'   -- the world is live and the main job changed (as before). The
--             relog-to-another-job case the old immediate drop caught is
--             still caught: the tick's _tickJob latch advances only on LIVE
--             reads, so a return from absence is judged against the job you
--             LEFT with;
--   'world' -- the world has been gone longer than WORLD_GONE_S. A zone load
--             never plausibly crosses it; sitting at character select does.
--             A same-job relog that beats the window survives -- the price
--             of zone persistence, and the kinder failure of the two.
-- `now` is injectable for the NK28/LS14/DS13 checks; callers omit it.
local WORLD_GONE_S = 60;
function M.worldWatch(job, prevJob, now)
    local nLocks, nDis = 0, 0;
    for _ in pairs(M.locks) do nLocks = nLocks + 1; end
    -- DISABLED SLOTS ride the same watch (ADR 0024). Same rule for the same
    -- reason: a slot dlac has stopped equipping into, on a job whose loadout you
    -- never disabled anything on, with nothing on screen to explain it, is the
    -- relog failure in a smaller box -- and it is meaner here than for the strip,
    -- because a naked player knows instantly and this one just finds one slot
    -- quietly not swapping.
    for _ in pairs(M.disabledSlots) do nDis = nDis + 1; end
    now = tonumber(now) or os.clock();
    -- Absence bookkeeping runs even UNARMED (v153): the Integration stream's
    -- lifetime reads the same timestamp through worldAbsentOutlasted below --
    -- one law, one number, one home (never a second timer). The armed bail
    -- stays exactly where it was for everything that DROPS.
    if job == nil or job == 0 then
        if M._worldGoneAt == nil then M._worldGoneAt = now; end
    else
        M._worldGoneAt = nil;
    end
    if not M.nakedArmed and not M.lockedSetOn() and nLocks == 0 and nDis == 0 then return nil; end
    local why = nil;
    if job == nil or job == 0 then
        if (now - M._worldGoneAt) >= WORLD_GONE_S then why = 'world'; end
    else
        if prevJob ~= nil and prevJob ~= 0 and job ~= prevJob then why = 'job'; end
    end
    if why == nil then return nil; end
    M._worldGoneAt = nil;
    local dropped = { naked = (M.nakedArmed == true), locked = M.lockedSetLabel(),
                      locks = nLocks, disabled = nDis };
    -- In place, never `M.locks = {}`: the table's identity is held elsewhere.
    for k in pairs(M.locks) do M.locks[k] = nil; end
    for k in pairs(M.disabledSlots) do M.disabledSlots[k] = nil; end
    M.lockedSet  = nil;
    M.nakedArmed = false;
    if saveModeState ~= nil then pcall(saveModeState); end
    return why, dropped;
end
-- The pre-v124 name, kept because it is what the seeded LAC-side engine and the
-- NK28 checks call. Same function, wider job.
M.nakedWorldWatch = M.worldWatch;

-- Read-only (v153): has the world been gone longer than a zone can explain?
-- The Integration stream's lifetime gate (integration-surface design, section
-- 3) -- the same law, constant and timestamp as the holds' watch above, read
-- without behavior. A job change deliberately does NOT show here: a job
-- change is data the stream's consumer wants, not a reason to stop talking.
function M.worldAbsentOutlasted(now)
    now = tonumber(now) or os.clock();
    return M._worldGoneAt ~= nil and (now - M._worldGoneAt) >= WORLD_GONE_S;
end

-- Arm/disarm the strip. The ONE door: the command branch and the GUI both come
-- through here. No dispatch is kicked -- the 0.4s tick is the only Default entry
-- point that carries the zoning / player-action / pet-action / sync-settle gates,
-- and a command-path dispatch that skipped them would fire a full re-equip inside
-- a cast or mid-zone for the sake of 400ms. The claim is standing; it lands on the
-- next pass by construction. Returns the new state.
function M.setNaked(on)
    on = (on == true);
    M.nakedArmed = on;
    -- Mirror __naked for the GUI UNCONDITIONALLY, even when nothing changed. An
    -- early return here would strand a stale mirror: quit the client while naked
    -- and the next launch is genuinely dressed, but the file still says true, so
    -- the GUI draws the red NAKED button and clicking it -- setNaked(false) on an
    -- already-false flag -- would write nothing and never clear it.
    if saveModeState ~= nil then pcall(saveModeState); end
    return on;
end

-- ---------------------------------------------------------------------------
-- LOCKED SET (ADR 0022) -- `/dl lock set ...` as a FROZEN Claim on the Locks row.
--
-- It used to be `equip once, then M.setLock('all', true)`. Three things were
-- wrong with that, and the first one shipped broken:
--
--   * the one-shot equip was bracketed with rawget(_G,'gEquip'), which is nil in
--     the ADDON state -- so in NATIVE mode the resolved set fell to the
--     unbracketed path, landed in equipengine's buffer, and the next fireEvent's
--     bufferClear wiped it. The command then locked all 16 slots onto whatever
--     you happened to be wearing and printed success;
--   * locking all 16 destroyed the player's OWN locks (it had to clear them
--     first, or they would strip slots out of that very equip) -- ADR 0021
--     already listed this as a rejected alternative, naming this command as the
--     state it would damage;
--   * and a lock CANNOT PUT GEAR ON. It only deletes a slot from a layer's plan
--     (the strip in equipResolved). So the equip half had no way to retry.
--
-- As a Claim all three vanish: the claim is applied INSIDE M.dispatch, which the
-- native engine already brackets, so there is no command-path equip left to get
-- wrong; the player's locks are untouched and merely outranked while held; and
-- the claim is re-applied every dispatch, so anything the server refused heals
-- on the next pass -- ADR 0021 rule 3, which is the whole reason Naked works.
--
-- It rides the EXISTING Locks row rather than adding one (Henrik, 2026-07-26:
-- "conveying it as one layer in the claimant arbiter but then having it use
-- /dl lock as the lock layer does in the arbiter is confusing"). One word, one
-- row, one drag target. arbResolve already returns "slot -> item OR LOCK_HELD",
-- so the row carries real item names for held slots and the veto sentinel for
-- plainly-locked ones. Precedence is unchanged: Naked and Pins punch through a
-- locked slot, nothing else does.
--
-- FROZEN AT ARM, not live (Henrik: "Once you lock, it shall be constant, like
-- with naked. Even if you lock a set then change it, it should not change what
-- you wear"). Frozen means the INSTRUCTION, never the outcome: dlac: markers are
-- collapsed to concrete names once, here, so a weather change cannot swap your
-- obi while locked -- but the claim still re-LOCATES those names in your bags
-- every dispatch, because freezing container+index would strand the hold the
-- first time a bag shuffled, which is strip-once with no retry again.
-- ---------------------------------------------------------------------------

-- 'remove' and 'displaced' are the equip vocabulary's LITERALS, not item names:
-- both engines map them to an index (0 and -1), so they can never be "missing
-- from your bags" and must skip the locate check below.
local EQUIP_LITERAL = { remove = true, displaced = true };

-- The name of a set entry -- a plain string, or a table with .Name (an augment
-- or Bag spec). nil for anything else.
local function setEntryName(v)
    if type(v) == 'string' then return v; end
    if type(v) == 'table' and type(v.Name) == 'string' then return v.Name; end
    return nil;
end
M._setEntryName = setEntryName;

-- Build the frozen claim. ONE shape for all four commands -- they differ only in
-- `fill`, which decides what happens to a slot the set does NOT name:
--
--   'remove' -> held EMPTY   (/dl lock set          -- strict)
--    nil     -> left alone   (/dl lock set-loose    -- available to other claimants)
--   'worn'   -> held as worn (/dl lock set-snapshot, and /dl lock set-current
--                             with no set at all)
--
-- Henrik's words for the two: "Strict = hard reserve EVERYTHING, even empty
-- slots. Loose = reserve ONLY the slots that have anything on them, the rest
-- gets free use for any other claimants."
--
-- A slot the set DOES name but that we cannot fill right now -- the piece is in
-- a Satchel or on a mule, or a dlac: marker will not answer -- is NOT held. It
-- goes loose and is reported by name and location ("that's better than an empty
-- slot"). It stays loose: the claim is frozen, so moving the item into your bags
-- mid-run does not re-join it to the hold. Lock again to pick it up.
--
-- Pure. `resolve`, `locate` and `wornOf` are injected, so the tests drive every
-- branch with no Ashita, no bags and no game.
function M.buildLockedClaim(setTbl, fill, resolve, locate, wornOf)
    local claim, missing, n = {}, {}, 0;
    for _, slot in ipairs(LAC_SLOTS_CANON) do
        local named = nil;
        if type(setTbl) == 'table' then
            named = setTbl[slot];
            if named == nil then                      -- sets may be authored in any case
                local want = string.lower(slot);
                for k, v in pairs(setTbl) do
                    if type(k) == 'string' and string.lower(k) == want then named = v; break; end
                end
            end
        end
        if named ~= nil then
            local nm    = setEntryName(named);
            local entry = named;
            if type(nm) == 'string' and string.sub(string.lower(nm), 1, 5) == 'dlac:' then
                entry = (resolve ~= nil) and resolve(named, slot) or nil;   -- collapse the virtual
            end
            local en = setEntryName(entry);
            if entry == nil or en == nil then
                -- a marker with no answer at this moment (no manifest yet, craft
                -- mode off, an obi whose element is not up): name the marker.
                missing[#missing + 1] = { slot = slot, item = nm or '?', where = nil };
            elseif string.lower(en) == 'ignore' then
                -- 'ignore' is the set author saying "this slot is not mine".
                -- Leave it available -- and do NOT report it: nothing is missing.
            elseif EQUIP_LITERAL[string.lower(en)] then
                claim[slot] = entry; n = n + 1;
            else
                local here, where = true, nil;
                if locate ~= nil then here, where = locate(entry, slot); end
                if here then
                    claim[slot] = entry; n = n + 1;
                else
                    missing[#missing + 1] = { slot = slot, item = en, where = where };
                end
            end
        elseif fill == 'worn' then
            -- An empty slot snapshots as EMPTY: "locks whatever you have on you
            -- for the moment, STRICTLY" -- and what you have there is nothing.
            local w = (wornOf ~= nil) and wornOf(slot) or nil;
            claim[slot] = (w ~= nil) and w or 'remove';
            n = n + 1;
        elseif fill == 'remove' then
            claim[slot] = 'remove';
            n = n + 1;
        end
    end
    return claim, missing, n;
end

-- The four command words -> the fill they mean. Data, so the command branch,
-- the no-argument help and the tests all read the same list (LS1 pins it).
local LOCKSET_MODES = {
    ['set']          = { fill = 'remove', needsName = true,
                         blurb = 'wear that set and LOCK it. Slots it does not name are held EMPTY.' },
    ['set-loose']    = { fill = nil,      needsName = true,
                         blurb = 'wear and lock it; slots it does not name stay available to everything else' },
    ['set-snapshot'] = { fill = 'worn',   needsName = true,
                         blurb = 'wear and lock it; slots it does not name are held exactly as worn RIGHT NOW' },
    ['set-current']  = { fill = 'worn',   needsName = false,
                         blurb = 'lock exactly what you are wearing right now, all 16 slots' },
};
M._lockSetModes = LOCKSET_MODES;
local LOCKSET_ORDER = { 'set', 'set-loose', 'set-snapshot', 'set-current' };
M._lockSetOrder = LOCKSET_ORDER;

-- Is a set locked? The ONE reader -- M.dispatch, /dl why, /dl prio, the command
-- branch and the GUI mirror all ask here.
function M.lockedSetOn() return type(M.lockedSet) == 'table' and type(M.lockedSet.claim) == 'table'; end

-- What to call it in chat and in the GUI. set-current has no set name.
function M.lockedSetLabel()
    if not M.lockedSetOn() then return nil; end
    return M.lockedSet.name or 'your gear as it was';
end

-- The claim the Arbiter applies. A FRESH copy per call: the Arbiter keeps the
-- table for /dl why attribution, and the apply path is free to write into what
-- it is handed -- neither may reach back into what the player locked.
function M.lockedSetClaim()
    if not M.lockedSetOn() then return nil; end
    local out = {};
    for k, v in pairs(M.lockedSet.claim) do out[k] = v; end
    if next(out) == nil then return nil; end
    return out;
end

function M.setLockedSet(rec)
    M.lockedSet = (type(rec) == 'table') and rec or nil;
    if saveModeState ~= nil then pcall(saveModeState); end
    return M.lockedSet;
end

-- Release. Returns the label that WAS held (nil if nothing was), so every caller
-- says the same thing without asking twice.
function M.clearLockedSet()
    local had = M.lockedSetLabel();
    M.lockedSet = nil;
    if had ~= nil and saveModeState ~= nil then pcall(saveModeState); end
    return had;
end

-- (The Arbiter's resolve/explain family -- arbResolve, arbCededAbove,
--  arbExplain + the claim-record recipe, arbWhyLines -- MOVED to
--  gearrbiter.lua, ADR 0027 stage 3. Re-exported verbatim.)
M.arbResolve    = ARB.arbResolve;
M.arbCededAbove = ARB.arbCededAbove;
M.arbExplain    = ARB.arbExplain;
M.arbWhyLines   = ARB.arbWhyLines;

-- MaxMP's CLAIM table (ADR 0012, step 4; delivery FOLDED, ADR 0027 stage 6):
-- canonical slot -> the rung name the banded ladder wants ON, for every slot
-- mpBands targets a battery. This is the MaxMP row's `claim` builder: the
-- arbiter ranks it, /dl why attributes it, and the row's apply dresses what
-- survives the gates. nil when maxmp is off or the manifest has no bands.
-- ctx.rankOf is already set (the rank order hoists above the build pass), so
-- the band build's lock consult agrees with the apply's respect('MaxMP').
local function mpClaimFor(ctx)
    if M.modes['maxmp'] == nil then return nil; end
    local mc = M.mpBands(ctx);
    if type(mc) ~= 'table' or type(mc.target) ~= 'table' then return nil; end
    local out = nil;
    for lslot, want in pairs(mc.target) do
        if type(want) == 'string' then
            local canon = MP_SLOT_CANON[lslot];
            if canon ~= nil then
                out = out or {};
                out[canon] = want;
            end
        end
    end
    return out;
end

-- respectLocks (ADR 0012, step 3): does THIS layer stop at a locked slot? A
-- claim layer ranked BELOW Locks respects them (the veto stops it); one ranked
-- ABOVE punches through (the strip is skipped for its slots). nil == true, so
-- every pre-step-3 caller (the Triggers floor, the immediate-equip paths, the
-- headless tests) keeps the old absolute-veto behavior. The dispatch apply loop
-- passes the per-claimant answer plus WHO is asking (`who`), so the mp-hold
-- constraint can stand down for a claimant ranked at or above MaxMP.
local function equipResolved(s, ctx, respectLocks, who)
    if respectLocks == nil then respectLocks = true; end
    local out, notes = nil, nil;
    -- Copy-on-write + note, written ONCE (every branch used to repeat both).
    -- nil-ing a slot in `out` HOLDS it: the engine says nothing for that slot,
    -- LAC leaves what you are wearing, and later passes' pairs() walks skip it.
    local function W()
        if out == nil then
            out = {};
            for k2, v2 in pairs(s) do out[k2] = v2; end
        end
        return out;
    end
    local function note(f, ...)
        notes = notes or {};
        notes[#notes + 1] = string.format(f, ...);
    end
    local anyLocks = (next(M.locks) ~= nil);
    -- (The pin-reserved hold retired from this chain, step-1 cleanup
    --  2026-07-27: the v43 flap it guarded is the cross-rank verdict's job
    --  now -- a dominant pin reserver suppresses the set's slot before any
    --  pass writes it.)
    -- Max-MP context (v88, the banded ladder): M.mpBands precomputes the whole
    -- plan -- bands, thresholds, the target loadout -- from the manifest, the
    -- trigger sets and CURRENT MP (the only live number; docs/design v2),
    -- memoized on ctx so one dispatch samples one moment. Since the FOLD
    -- (stage 6) the battery EQUIP lives on the MaxMP registry row; this pass
    -- keeps only the mp-hold CONSTRAINT below -- a worn battery outside any
    -- band target holds against an MP-lighter incoming piece.
    local mpCtx, mpMap = nil, nil;
    if M.modes['maxmp'] ~= nil then
        mpCtx = M.mpBands(ctx);
        if mpCtx ~= nil then
            mpMap = mpCtx.mpMap;
        elseif not M._mpWarned then
            -- The mode is ON but there is no battery data (or no mpbands
            -- module): say so ONCE instead of silently doing nothing.
            M._mpWarned = true;
            print('[dlac] maxmp is ON but the gear manifest has no MP data yet -- open the Gear Helpers tab (it self-heals) or relog, then act again.');
        end
    end
    -- AutoAcc (Type automation) decisions for this set; nil when it carries no
    -- dlac:AutoAcc markers. Resolved before the generic virtual branch below.
    local accPick = accResolveSet(s);
    -- Per-slot precedence chain -- FIRST claim wins a slot (the elseif IS the
    -- priority): locks > sync-hold weapons > AutoAcc > dlac: virtuals >
    -- MP hold/upgrade. (pin-reserved retired to the cross-rank verdict.)
    for slot, v in pairs(s) do
        if respectLocks and anyLocks and M.locks[string.lower(tostring(slot))] == true then
            W()[slot] = nil;                           -- locked: the engine leaves it alone
            note('%s=LOCKED (kept as worn)', tostring(slot));
        elseif ctx ~= nil and ctx.syncHold == true and WEAPON_SLOTS[string.lower(tostring(slot))] then
            -- MUST sit above the AutoAcc and dlac: branches: a virtual marker in a
            -- weapon slot has to be held UNRESOLVED (resolving it at the transient
            -- level IS the bug this hold exists for -- LS tests pin the order).
            W()[slot] = nil;               -- level reading is settling: weapons stay as worn
            note('%s=SYNC-HOLD (level just changed; kept as worn)', tostring(slot));
        elseif accPick ~= nil and accPick[slot] ~= nil then
            W()[slot] = accPick[slot];
            local mkOnly = v;
            local pb = string.find(v, '|', 1, true);
            if pb ~= nil then mkOnly = string.sub(v, 1, pb - 1); end
            local _, cacc, cname = parseAccMarker(mkOnly);
            if cname ~= nil and accPick[slot] ~= cname then
                note('AutoAcc=%s RELEASED (acc+%d redundant) -> %s',
                    cname, cacc or 0, accPick[slot]);
            else
                note('AutoAcc=%s', tostring(accPick[slot]));
            end
        elseif type(v) == 'string' and string.lower(string.sub(v, 1, 5)) == 'dlac:' then
            local marker, fallback = v, nil;
            local p = string.find(v, '|', 1, true);
            if p ~= nil then marker, fallback = string.sub(v, 1, p - 1), string.sub(v, p + 1); end
            local nm, why = resolveVirtual(marker, ctx, slot);
            W()[slot] = nm or fallback;                -- nil fallback drops the slot
            if nm ~= nil then
                note('%s=%s', marker, nm);
            elseif fallback ~= nil then
                note('%s=fallback %s (%s)', marker, fallback, tostring(why));
            else
                note('%s=skipped (%s)', marker, tostring(why));
            end
        end
    end
    -- (The woven per-slot MP branch lived at the end of this chain until the
    --  FOLD, ADR 0027 stage 6: MaxMP now dresses as an ordinary claimant --
    --  its apply on the CLAIMANTS row -- and the no-band worn-protect is the
    --  mp-hold pass below.)
    -- The five whole-table post-passes, run in POST_ORDER (the data above).
    local PASS = {
        -- THE MP-HOLD CONSTRAINT (the FOLD, ADR 0027 stage 6 -- ratified
        -- item 3): the old no-band worn-protect, now a named constraint. A
        -- slot no band governs, whose worn piece carries MORE MP than the
        -- incoming one, holds -- spend the surplus first (ruling 1, the
        -- founding spec). Weapons exempt; explicit 'remove' respected;
        -- locked slots are already held by the chain; and the pass runs only
        -- for the floor and claimants BELOW MaxMP's rank (who + ctx.rankOf)
        -- -- a claim ABOVE MaxMP outranks the hold exactly as it outranks
        -- the battery (ceding is apply order now). tgt == false still notes
        -- the release for /dl why continuity.
        ['mp-hold'] = function()
            if mpCtx == nil then return; end
            if type(ctx) == 'table' and type(ctx.rankOf) == 'table' and who ~= nil then
                local rw, rm = ctx.rankOf[who], ctx.rankOf['MaxMP'];
                if rw ~= nil and rm ~= nil and rw <= rm then return; end
            end
            for slot, v in pairs(out or s) do
                if type(v) == 'string' and string.lower(v) ~= 'remove'
                   and not MP_HOLD_EXEMPT[string.lower(tostring(slot))] then
                    local lslot = string.lower(tostring(slot));
                    local worn = wornItemName(slot);
                    local wornMP = (worn ~= nil) and (mpMap[string.lower(worn)] or 0) or 0;
                    local tgtMP  = mpMap[string.lower(v)] or 0;
                    local tgt = mpCtx.target[lslot];
                    if tgt == nil and M.locks[lslot] ~= true then
                        if worn ~= nil and wornMP > tgtMP and string.lower(worn) ~= string.lower(v) then
                            W()[slot] = nil;
                            note('%s=MP-HOLD %s (+%d MP)', tostring(slot), worn, wornMP - tgtMP);
                        end
                    elseif tgt == false then
                        if worn ~= nil and wornMP > tgtMP and string.lower(worn) ~= string.lower(v) then
                            note('%s=MP-RELEASE %s -> %s', tostring(slot), worn, tostring(v));
                        end
                    end
                end
            end
        end,
        -- Craft Sub guard: hold a Main that pairs badly with the craft overlay's
        -- Sub (see craftMainGuard). On the FINAL names so it also covers a Main
        -- that a virtual (dlac:AutoStaff) or AutoAcc resolved above.
        ['craft-sub-guard'] = function()
            if ctx == nil or ctx.craftMainGuard == nil then return; end
            for slot, v in pairs(out or s) do
                if string.lower(tostring(slot)) == 'main' and type(v) == 'string'
                   and ctx.craftMainGuard(v) then
                    W()[slot] = nil;
                    note('Main=%s HELD (pairs badly with the craft Sub)', tostring(v));
                    break;
                end
            end
        end,
        -- Sync-hold companion rule: with Range HELD out of the plan above, a
        -- stat-stick Ammo (RSlot reserves Range, ADR 0010) must hold too --
        -- trinket-vs-ranged judges only the plan, so the trinket would sail
        -- through, land, and the SERVER would strip the worn ranged weapon: a
        -- Range unequip during the very window the hold keeps weapons stable.
        -- Fired ammo (arrows/bolts: no Range bit) keeps dispatching (LS12).
        ['sync-hold-ammo'] = function()
            if ctx == nil or ctx.syncHold ~= true then return; end
            for slot, v in pairs(out or s) do
                if string.lower(tostring(slot)) == 'ammo' and type(v) == 'string'
                   and hasBit(tonumber(rslotOf(v)) or 0, 0x0004) then
                    W()[slot] = nil;
                    note('%s=SYNC-HOLD (%s reserves Range; kept as worn)', tostring(slot), tostring(v));
                    break;
                end
            end
        end,
        -- Trinket vs ranged weapon (ADR 0010): a stat stick reserves the Range
        -- slot server-side, so the two can't coexist -- keep the higher-Level
        -- one and drop the other. BEFORE reserved-drops (POST_ORDER adjacency),
        -- so the loser can't go on to reserve anything and it settles.
        ['trinket-vs-ranged'] = function()
            -- THE PAIR VERDICT, APPLIED (v159). Under a dispatch the arbiter
            -- already judged the MERGED floor -- every set this event matched
            -- plus every built claim, in one view -- so this pass carries the
            -- answer out instead of making a new one per table. That is the
            -- whole fix for the DRK flap: the old per-table call could not see
            -- that a SIBLING rule spoke for Ammo, so an Ammo-less weapons set
            -- displaced a stat stick for a crossbow the dispatch was never
            -- going to equip (arbiter.pairVerdict carries the full case).
            -- Direct callers -- immediate equips, headless suites -- have no
            -- verdict and keep the single-table law below, byte-identical.
            if ctx ~= nil and ctx.reserveGlobal == true then
                local pv = ctx.reservePair;
                if pv == nil then return; end
                local cur, want = out or s, string.lower(tostring(pv.slot));
                if pv.remove == true then
                    -- The displace rides the table that brings the ranged
                    -- piece, exactly as it always did -- writing it from a
                    -- table that names no Range would put an unexplained
                    -- 'remove' in a plan that has no weapon to protect.
                    for slot, v in pairs(cur) do
                        if string.lower(tostring(slot)) == 'range'
                           and type(v) == 'string' and v ~= 'remove' then
                            W()['Ammo'] = 'remove';
                            note('Ammo=remove (worn %s yields Range to the set\'s %s)',
                                tostring(pv.loser), tostring(pv.keep));
                            break;
                        end
                    end
                    return;
                end
                for slot in pairs(cur) do
                    if string.lower(tostring(slot)) == want then
                        W()[slot] = nil;
                        -- Name the REASON (the v128 rule): reading "stat stick"
                        -- over a bolt-vs-bow drop sends the next reader hunting
                        -- for a trinket that is not there.
                        if pv.why == 'mismatch' then
                            note('%s=dropped (%s cannot be fired by %s -- the server would strip a slot)',
                                tostring(slot), tostring(pv.loser), tostring(pv.keep));
                        else
                            note('%s=dropped (stat stick vs ranged weapon; kept %s)',
                                tostring(slot), tostring(pv.keep));
                        end
                        break;
                    end
                end
                return;
            end
            local tdKey, tdWinner, tdWhy = M.trinketRangeDrop(out or s, rslotOf, levelOf, pairOf);
            if tdKey ~= nil then
                W()[tdKey] = nil;
                -- Name the REASON: "stat stick vs ranged weapon" was the only conflict
                -- this pass could find before v128, and reading it over a bolt-vs-bow
                -- drop would send the next reader hunting for a trinket that is not there.
                if tdWhy == 'mismatch' then
                    note('%s=dropped (%s cannot be fired by %s -- the server would strip a slot)',
                        tostring(tdKey), tostring((out or s)[tdKey]), tostring(tdWinner));
                else
                    note('%s=dropped (stat stick vs ranged weapon; kept %s)', tostring(tdKey), tostring(tdWinner));
                end
            end
            -- Scope ruling: the Level contest above is WITHIN-SET only. A worn
            -- trinket the plan never named must not keep the set's ranged piece
            -- out (the server would strip the weapon while the trinket sits) --
            -- displace it: Ammo='remove' rides the same EquipSet. Locked Ammo
            -- stays the user's explicit word, so no displace (a pin's Ammo is
            -- safe by overlay order: the pin's own pass writes after this).
            if M.locks['ammo'] ~= true then
                local wornAmmo = wornItemName('Ammo');
                local dk, incoming = M.trinketWornDisplace(out or s, wornAmmo, rslotOf, pairOf);
                if dk ~= nil then
                    W()[dk] = 'remove';
                    note('%s=remove (worn %s yields Range to the set\'s %s)',
                        tostring(dk), tostring(wornAmmo), tostring(incoming));
                end
            end
        end,
        -- Reserved-slot pass (see RSLOT_ORDER). LAST, on the FINAL names: only
        -- here are the overlay, the virtuals, AutoAcc and MP-EQUIP all resolved.
        -- It has to be here rather than at build time -- two individually legal
        -- sets can overlay into an illegal pair (a Body from one trigger, a Head
        -- from another), and MP-EQUIP writes slots no set ever named. A set is a
        -- plan; conflicts are the engine's call (ADR 0006).
        ['reserved-drops'] = function()
            local cur = out or s;
            -- The merged-floor VERDICT wins whenever this dispatch built one
            -- (v135). It is the only view that can see another rule's claim on a
            -- reserved slot, which is the whole point: judging one set at a time
            -- cannot tell "Idle's cloak reserves Head" from "a HIGHER-priority
            -- rule owns Head, so the cloak is not a candidate at all".
            local sup  = (ctx ~= nil) and ctx.reserveSuppressed  or nil;
            local inel = (ctx ~= nil) and ctx.reserveIneligible or nil;
            local rep  = (ctx ~= nil) and ctx.reserveReplace    or nil;
            -- THE GLOBAL VERDICT (ADR 0027 stage 4): when this dispatch ran
            -- the cross-rank verdict, it is the ONE reservation authority for
            -- every pass -- floor and claims alike -- so the single-set + worn
            -- fallback below never runs for them. Worn pieces are NOT claims
            -- (the Mindie ruling, ratified item 2): a worn reserver nothing
            -- re-claims defends nothing, and the server displaces it when the
            -- winner lands. Direct callers (no dispatch, no flag) keep the old
            -- judgement -- worn arm included -- untouched.
            if (ctx ~= nil and ctx.reserveGlobal == true) or sup ~= nil or inel ~= nil or rep ~= nil then
                -- Gathered before writing: W() may hand back a COPY, so mutating
                -- while walking `cur` would drop edits on the floor.
                local kill = nil;
                for slot in pairs(cur) do
                    if string.sub(tostring(slot), 1, 2) ~= '__' then
                        if rep ~= nil and rep[slot] ~= nil and cur[slot] == rep[slot].from then
                            -- THE FALL (ADR 0027 stage 2): this pass is the
                            -- refused piece's own writer -- swap in the rung
                            -- that passed the re-run verdict. A DIFFERENT
                            -- writer's item in the same slot flows through
                            -- untouched; the overlay order settles it, as ever.
                            kill = kill or {};
                            kill[slot] = { 'FELL', rep[slot] };
                        elseif inel ~= nil and inel[slot] ~= nil then
                            kill = kill or {};
                            kill[slot] = { 'INELIGIBLE', inel[slot] };
                        elseif sup ~= nil and sup[slot] ~= nil then
                            kill = kill or {};
                            kill[slot] = { 'RESERVED', sup[slot] };
                        end
                    end
                end
                if kill ~= nil then
                    for slot, k in pairs(kill) do
                        if k[1] == 'FELL' then
                            W()[slot] = k[2].to;
                            -- Two refusals reach this one writer, and the line
                            -- has to say which: "reserves Head" printed about a
                            -- piece sitting in the Mog Safe sends you hunting
                            -- the wrong bug.
                            if k[2].why == 'unavail' then
                                note('%s=%s fell -> %s (not in an equippable bag)',
                                    tostring(slot), tostring(k[2].from), tostring(k[2].to));
                            else
                                note('%s=%s fell -> %s (reserves %s -- owned above)',
                                    tostring(slot), tostring(k[2].from), tostring(k[2].to), tostring(k[2].by));
                            end
                        elseif k[1] == 'INELIGIBLE' then
                            W()[slot] = nil;
                            note('%s=INELIGIBLE (it reserves %s, which a higher claim owns)',
                                tostring(slot), tostring(k[2]));
                        else
                            W()[slot] = nil;
                            note('%s=RESERVED by %s (claimed empty)', tostring(slot), tostring(k[2]));
                        end
                    end
                end
                return;
            end
            -- No global verdict (a DIRECT caller only, since stage 4 --
            -- immediate equips, headless tests): the single-set + worn view,
            -- byte-identical to pre-v135 behaviour.
            local drops = M.reservedDrops(cur, rslotOf, wornItemName);
            if drops ~= nil then
                for slot, by in pairs(drops) do
                    W()[slot] = nil;
                    note('%s=RESERVED by %s (kept as worn)', tostring(slot), tostring(by));
                end
            end
        end,
    };
    for _, nm in ipairs(POST_ORDER) do PASS[nm](); end
    -- ONE PLAN, ONE SEND (ADR 0027, stage 3's last slice). During a dispatch
    -- the resolved table MERGES into ctx.planOut -- last-writer-wins, the
    -- same order the equipengine buffer used to accumulate N separate sends
    -- in, so the final map is identical by construction -- and M.dispatch
    -- sends ONCE at the end: the engine finally sees the whole intent as one
    -- set (a better satisfied-check, fewer packets), and the buffer stops
    -- being the hidden merger. A held slot (nil'd above) is simply absent
    -- and keeps its keep-worn meaning. Direct callers -- immediate equips,
    -- tests -- carry no collector and send immediately, exactly as before.
    local fin = out or s;
    if type(ctx) == 'table' and type(ctx.planOut) == 'table' then
        for slot, v in pairs(fin) do
            if string.sub(tostring(slot), 1, 2) ~= '__' then ctx.planOut[slot] = v; end
        end
    else
        engineEquipSet(fin);
    end
    local note = '';
    if notes ~= nil then
        table.sort(notes);
        note = '  [' .. table.concat(notes, ', ') .. ']';
    end
    return note, (out or s);   -- the table actually equipped (for slot attribution)
end
M._equipResolved = equipResolved;   -- test seam (craft Sub guard post-pass)

-- Flip a slot lock. slot: one of LAC_SLOTS or 'all'; state nil = toggle. Returns the
-- new state (for 'all': the state applied), or nil for an unknown slot name.
function M.setLock(slot, state)
    slot = string.lower(tostring(slot or ''));
    if slot == 'all' then
        if state == nil then state = (next(M.locks) == nil); end   -- toggle: all on if none on
        for _, s in ipairs(LAC_SLOTS) do M.locks[s] = (state == true) or nil; end
        saveModeState();
        return state == true;
    end
    if not LAC_SLOT_OK[slot] then return nil; end
    if state == nil then state = not (M.locks[slot] == true); end
    M.locks[slot] = (state == true) or nil;
    saveModeState();
    return M.locks[slot] == true;
end

-- Is a slot held by the plain slot-lock veto? (issue #138 -- the Action
-- sequencer names a lock as a definitive blocker for its refusal line.)
function M.isLockedSlot(slot) return M.locks[string.lower(tostring(slot or ''))] == true; end

-- Kick one Default dispatch (issue #138). A transient claim releasing wants the
-- restore NOW rather than on the next 0.4s tick; this is the same explicit
-- re-dispatch a mode flip / sets install already does. Guarded: the standing
-- tick is the fallback, so a failure here just costs the release one tick.
function M.kickDefault() pcall(function() M.dispatch('Default'); end); end

-- Force a re-read on the next dispatch (the GUI pings /dl triggers reload on commit).
-- Clears only the content caches (triggers + autogear) -- current rules stay live as
-- the fallback, so a forced reload of a broken file degrades exactly like an organic
-- one (keep + report).
function M.reloadTriggers()
    _trig.raw, _trig.lastCheck = nil, -1;
    _auto.raw, _auto.lastCheck = nil, -1;
    _accfile.raw, _accfile.lastCheck = nil, -1;
end

-- ---------------------------------------------------------------------------
-- Dispatch
-- ---------------------------------------------------------------------------
local function buildCtx(event)
    local ctx = { event = event };
    pcall(function() ctx.player = gData.GetPlayer(); end);
    -- v63: the pet beside the player -- nil petless AND when the pet is dead
    -- (GetPet's own rule). Read once per dispatch so every rule in one pass
    -- judges the same pet.
    pcall(function() ctx.pet = gData.GetPet(); end);
    if event == 'PetAction' then
        -- the PET's action (Blood Pact / Ready move / pet spell) -- same shape
        -- as GetAction (Name/Skill/Element/Type), so the matchers just work
        pcall(function() ctx.action = gData.GetPetAction(); end);
    elseif event ~= 'Default' then
        pcall(function() ctx.action = gData.GetAction(); end);
    end
    return ctx;
end

-- ONE tier's evaluation: (ALL of `when`) OR (ANY whenAny entry) -- the historical
-- rule matcher over a single { when, whenAny } pair. The sentence at tier 1. An
-- empty `when` with NO whenAny is the trivial 'any' match (returns andOk = true);
-- an OR-only leg (empty `when` WITH whenAny) is NOT always-on -- only the | side
-- counts. Factored out so a body AND every case reuse the exact same code path.
local function legMatches(when, whenAny, ctx)
    local andOk, nAnd = true, 0;
    for lk, cv in pairs(when or {}) do
        nAnd = nAnd + 1;
        local f = MATCHERS[lk];
        if f == nil or not f(cv, ctx) then andOk = false; break; end
    end
    if whenAny == nil then return andOk; end
    if nAnd > 0 and andOk then return true; end
    for _, entry in ipairs(whenAny) do
        local ok = true;
        for lk, cv in pairs(entry) do
            local f = MATCHERS[lk];
            if f == nil or not f(cv, ctx) then ok = false; break; end
        end
        if ok then return true; end
    end
    return false;
end
M._legMatches = legMatches;   -- headless test seam

local function matches(rule, ctx)
    -- A case-LESS rule keeps the original semantics EXACTLY -- one legMatches over
    -- the body, byte-for-byte the pre-cases path (pinned invariant, issue #126).
    if rule.cases == nil then return legMatches(rule.when, rule.whenAny, ctx); end
    -- Tier 2 (issue #126). ONE sentence, true at both tiers: `&` things bind into
    -- one together-block; each `|` thing stands alone; fire if the together-block
    -- holds, or any `|` thing does. At the rule tier the `&` members are the
    -- body's `&` leg + every `& case`; the standalone `|` things are the body's
    -- whenAny entries + every `| case`. The empty-together-block law generalizes:
    -- with NO `&` member (empty body leg and no `& case`) the together-block is
    -- never a hit -- only the `|` things count (OR-only is never always-on).
    local andOk, nAnd = true, 0;
    for lk, cv in pairs(rule.when or {}) do
        nAnd = nAnd + 1;
        local f = MATCHERS[lk];
        if f == nil or not f(cv, ctx) then andOk = false; break; end
    end
    for _, c in ipairs(rule.cases) do
        if c.op == '&' then
            nAnd = nAnd + 1;
            if andOk and not legMatches(c.when, c.whenAny, ctx) then andOk = false; end
        end
    end
    if nAnd > 0 and andOk then return true; end
    for _, entry in ipairs(rule.whenAny or {}) do
        local ok = true;
        for lk, cv in pairs(entry) do
            local f = MATCHERS[lk];
            if f == nil or not f(cv, ctx) then ok = false; break; end
        end
        if ok then return true; end
    end
    for _, c in ipairs(rule.cases) do
        if c.op == '|' and legMatches(c.when, c.whenAny, ctx) then return true; end
    end
    return false;
end
M._matches = matches;   -- headless test seam (the _matchers idiom)

-- Trigger cases (issue #125): the display vocabulary over the EXISTING schema.
-- The rule body is CASE 1 -- the "together-block" (its `&` leg). Each whenAny
-- entry is a "standalone alternative": a single-condition entry is a plain `|`
-- condition; a multi-condition entry (AND-within-OR) is a "| case". No schema
-- change -- these are just names for what the engine already evaluates.
--
-- caseDesc: the /dl why name for a matched whenAny entry. One condition reads
-- 'standalone <k=v>'; several read 'case <a & b>' (the AND-within-OR shape).
-- Keys are already lowercased by normalize; condVal serializes list values by
-- value (the ruleLabel rule) so the name is stable across states.
local function caseDesc(entry)
    local parts = {};
    for k, v in pairs(entry) do
        parts[#parts + 1] = string.lower(tostring(k)) .. ((v == true) and '' or ('=' .. condVal(v)));
    end
    table.sort(parts);
    if #parts <= 1 then return 'standalone ' .. (parts[1] or '?'); end
    return 'case ' .. table.concat(parts, ' & ');
end

-- The /dl why name for a whole `| case` from the cases list (issue #126): its
-- `&` leg conditions, then its internal `|` alternatives in parentheses --
-- 'case a & b' or 'case a & (x | y)'. Deterministic (sorted) and stable across
-- Lua states (condVal serializes list values by value, the ruleLabel rule).
local function caseLegDesc(c)
    local parts = {};
    for k, v in pairs(c.when or {}) do
        parts[#parts + 1] = string.lower(tostring(k)) .. ((v == true) and '' or ('=' .. condVal(v)));
    end
    table.sort(parts);
    local ors = {};
    for _, e in ipairs(c.whenAny or {}) do
        local ep = {};
        for k, v in pairs(e) do ep[#ep + 1] = string.lower(tostring(k)) .. ((v == true) and '' or ('=' .. condVal(v))); end
        table.sort(ep);
        if #ep > 0 then ors[#ors + 1] = (#ep > 1) and ('(' .. table.concat(ep, ' & ') .. ')') or ep[1]; end
    end
    table.sort(ors);
    if #ors > 0 then parts[#parts + 1] = '(' .. table.concat(ors, ' | ') .. ')'; end
    return 'case ' .. table.concat(parts, ' & ');
end

-- Which case carried a (possibly multi-case) rule -- for /dl why. Returns nil
-- when the rule has NO `|` leg AND no cases (a single-case rule names nothing:
-- /dl why reads byte-for-byte as before). Otherwise mirrors matches() EXACTLY --
-- the same MATCHERS, never a re-implementation: the together-block wins when it
-- holds (a NON-empty `&` member set, every one true -- the OR-only law), else the
-- FIRST standalone / `| case` that holds (file order, the engine's order).
function M.matchedCase(rule, ctx)
    if rule.whenAny == nil and (rule.cases == nil or #rule.cases == 0) then return nil; end
    local andOk, nAnd = true, 0;
    for lk, cv in pairs(rule.when or {}) do
        nAnd = nAnd + 1;
        local f = MATCHERS[lk];
        if f == nil or not f(cv, ctx) then andOk = false; break; end
    end
    for _, c in ipairs(rule.cases or {}) do
        if c.op == '&' then
            nAnd = nAnd + 1;
            if andOk and not legMatches(c.when, c.whenAny, ctx) then andOk = false; end
        end
    end
    if nAnd > 0 and andOk then return 'together-block'; end
    for _, entry in ipairs(rule.whenAny or {}) do
        local ok = true;
        for lk, cv in pairs(entry) do
            local f = MATCHERS[lk];
            if f == nil or not f(cv, ctx) then ok = false; break; end
        end
        if ok then return caseDesc(entry); end
    end
    for _, c in ipairs(rule.cases or {}) do
        if c.op == '|' and legMatches(c.when, c.whenAny, ctx) then return caseLegDesc(c); end
    end
    return nil;
end

-- One-line description of the acted-on thing, for /dl why.
local function actionLabel(ctx)
    local a = ctx.action;
    if a ~= nil then
        local bits = {};
        for _, k in ipairs({ 'Skill', 'Type', 'Element' }) do
            if type(a[k]) == 'string' then bits[#bits + 1] = a[k]; end
        end
        local tail = (#bits > 0) and (' [' .. table.concat(bits, '/') .. ']') or '';
        -- v81: a self-aimed action reads '@self' -- the checkable fact behind
        -- "why didn't my target=Self rule fire". Unknown target stays silent.
        if targetIsSelf(ctx) == true then tail = tail .. ' @self'; end
        return string.format('%q%s', tostring(a.Name), tail);
    end
    if ctx.player ~= nil then
        local s = string.format('status=%s moving=%s', tostring(ctx.player.Status), tostring(ctx.player.IsMoving));
        if ctx.pet ~= nil then   -- v63: the pet reads into /dl why too
            s = s .. string.format(' pet=%s(%s)', tostring(ctx.pet.Name), tostring(ctx.pet.Status));
        end
        return s;
    end
    return '?';
end

-- ---------------------------------------------------------------------------
-- The DECISION RING (v152) -- the record the Arbiter Monitor (and later the
-- integration stream) renders. ONE record per dispatch whose outcome moved;
-- the renderers read it, never re-derive (mpBands' law: never render a rival).
-- ---------------------------------------------------------------------------

-- A plan entry's display name: set/claim tables carry strings or Name-wrapped
-- entries; the 'remove' literal stays itself (renderers word it).
local function entryName(v)
    if type(v) == 'table' then return tostring(v.Name or v[1] or '?'); end
    return tostring(v);
end

-- ctx.planOut -> { Slot = 'Item Name' }, control keys skipped (the merge
-- site's own __ rule).
local function planNames(plan)
    local out = {};
    for slot, v in pairs(plan or {}) do
        if string.sub(tostring(slot), 1, 2) ~= '__' then out[slot] = entryName(v); end
    end
    return out;
end

-- The OUTCOME fingerprint: resolved items + each slot's winning claimant,
-- case-insensitive slot keys, sorted. Two dispatches with the same fingerprint
-- are the same decision as far as the ring is concerned. Pure (tests DR*).
function M.decisionFp(plan, explain)
    local rows = {};
    for slot, item in pairs(plan or {}) do
        rows[#rows + 1] = string.lower(tostring(slot)) .. '=' .. tostring(item);
    end
    table.sort(rows);
    local wins = {};
    for slot, ops in pairs(explain or {}) do
        local w = ops[1];
        if w ~= nil then
            wins[#wins + 1] = string.lower(tostring(slot)) .. '<' .. tostring(w.name);
        end
    end
    table.sort(wins);
    return table.concat(rows, '|') .. '||' .. table.concat(wins, '|');
end

-- Does the plan name a slot this contest cannot account for? Pure (tests DR*).
--
-- The one-way test is deliberate. Plan-without-explanation is the fault: the
-- record would claim a piece went on with nobody having decided it. The
-- REVERSE -- a contest naming a slot the plan does not carry -- is ordinary
-- and must not trigger a rebuild: a lock or the level-sync weapon hold removes
-- a slot from the plan while the claim on it stands, which is two different
-- questions answered correctly (field, 2026-08-02: Main/Sub leaving the plan
-- across a 9 -> 10 level-up while Triggers still claimed them).
--
-- A missing contest with a non-empty plan outruns by definition; two empties
-- do not.
--
-- WHY THE ITEM IS CHECKED TOO. The retrace signature covers matched rules,
-- locks, claim legs, the sets revision and the rank order -- it does NOT cover
-- the player's LEVEL. So levelling changes which candidates a set resolves to
-- while the signature holds: the plan gains a slot (caught by the coverage
-- test) or simply swaps the item in one it already had, and a coverage-only
-- test would keep the older explanation naming the older piece. Sentinels and
-- 'remove' are exempt -- a claim that defends a slot or empties it was never
-- claiming to name the worn item.
function M._planOutrunsContest(planSnap, contest)
    if type(planSnap) ~= 'table' or next(planSnap) == nil then return false; end
    local exp = (type(contest) == 'table') and contest.explain or nil;
    if type(exp) ~= 'table' then return true; end
    local won = {};
    for slot, ops in pairs(exp) do
        if type(ops) == 'table' and ops[1] ~= nil then
            won[string.lower(tostring(slot))] = ops[1].item;
        end
    end
    for slot, item in pairs(planSnap) do
        local w = won[string.lower(tostring(slot))];
        if w == nil then return true; end
        if type(w) == 'string' and string.sub(w, 1, 1) ~= '('
           and item ~= 'remove' and w ~= item then
            return true;
        end
    end
    return false;
end

-- The world at decision time, defensively read -- a pinned old record must
-- still say what it was decided UNDER (a weatherMatch why is incomplete
-- without the weather). Headless/pre-login reads just omit fields.
local function ctxSnapshot(ctx)
    local s = {};
    pcall(function()
        local p = ctx.player;
        if p ~= nil then
            s.job, s.sub = p.MainJob, p.SubJob;
            s.jobLevel, s.subLevel = p.MainJobSync, p.SubJobSync;
            s.hpp, s.mpp, s.tp = p.HPP, p.MPP, p.TP;
            s.status, s.moving = p.Status, p.IsMoving;
        end
    end);
    pcall(function()
        local env = gData.GetEnvironment();
        if env ~= nil then
            s.day, s.weather = env.DayElement, env.WeatherElement;
            s.moon = env.MoonPhase;
        end
    end);
    pcall(function()
        if ctx.pet ~= nil then s.pet = tostring(ctx.pet.Name); s.petStatus = tostring(ctx.pet.Status); end
    end);
    pcall(function() s.modes = M.activeModes(); end);
    pcall(function()
        local b = activeBuffs(ctx);
        if b ~= nil then
            local names = {};
            for k in pairs(b) do
                if type(k) == 'string' then names[#names + 1] = k; end
            end
            table.sort(names);
            s.buffs = names;
        end
    end);
    if ctx.action ~= nil then
        pcall(function() s.action = tostring(ctx.action.Name); end);
        -- THE JOIN KEY (integration design 5.1): the engine decoded the blocked
        -- outgoing 0x01A before this dispatch ran, so the record can carry the
        -- same numeric id the incoming 0x028 answers with. nil for Default and
        -- for actions without one; the consumer's recipe stays search-backwards.
        pcall(function()
            s.actionId = tonumber(ctx.action.actionId) or tonumber(ctx.action.Id);
            s.actionCategory = tonumber(ctx.action.category);
            s.targetIndex = tonumber(ctx.action.target);
        end);
    end
    return s;
end

-- Append-on-change, the ring's one law. Ladders ride the record AT APPEND so a
-- pinned old decision renders the rungs as they were ASKED, not as they are
-- now; ctx/ladders are built only on append (appends are rare -- the frame
-- path pays one fingerprint + compare).
local function recordDecision(event, ctx, planSnap, contest)
    if next(planSnap) == nil then return; end            -- nothing resolved: no decision
    local fp = M.decisionFp(planSnap, contest ~= nil and contest.explain or nil);
    local last = _decisions[#_decisions];
    if last ~= nil and last.fp == fp then return; end    -- same outcome: push nothing
    -- CASE-INSENSITIVE, like the fingerprint above (2026-08-02). decisionFp
    -- lowercases every slot key; this comparison used the RAW ones -- two
    -- computations of "did this move?" disagreeing about what a slot IS, which
    -- is the exact class findCI exists to prevent. Producers do disagree on
    -- slot-key case, and on the day one emitted 'Main' where the last pass
    -- emitted 'main', the fingerprint would correctly say nothing moved while
    -- this counted TWO phantom changes -- one added, one dropped -- and every
    -- renderer of the record would have shown both.
    local lastLow = {};
    if last ~= nil then
        for slot, item in pairs(last.plan) do lastLow[string.lower(tostring(slot))] = item; end
    end
    local nowLow = {};
    for slot, item in pairs(planSnap) do nowLow[string.lower(tostring(slot))] = item; end
    local changed, n = {}, 0;
    for slot, item in pairs(planSnap) do
        if last == nil or lastLow[string.lower(tostring(slot))] ~= item then
            changed[slot] = true; n = n + 1;
        end
    end
    if last ~= nil then
        for slot in pairs(last.plan) do
            if nowLow[string.lower(tostring(slot))] == nil then changed[slot] = true; n = n + 1; end
        end
    end
    local ladders = nil;
    if contest ~= nil and type(contest.src) == 'table' then
        ladders = {};
        for slot, sn in pairs(contest.src) do
            pcall(function()
                local lad = M.candidatesFor(sn, slot);
                if lad ~= nil and type(lad.items) == 'table' and #lad.items > 0 then
                    local names = {};
                    for _, r in ipairs(lad.items) do names[#names + 1] = r.name; end
                    ladders[slot] = { set = sn, items = names };
                end
            end);
        end
    end
    -- THE RECEIPT WINS. contest.asked holds the ladders the arbitration was
    -- actually handed (vLadderOf's note-taking): it covers CLAIMANT ladders,
    -- which the derivation above cannot see at all -- contest.src is written
    -- only by the trigger floor -- and where both have an answer the recorded
    -- one is the truthful one, because the derivation re-asks later and can
    -- come back different (a bag moved, the level changed) than the list the
    -- decision was made from. The derivation stays for the slots that never
    -- needed a ladder: nothing was refused there, so nobody asked, so there is
    -- no receipt to keep.
    if contest ~= nil and type(contest.asked) == 'table' then
        ladders = ladders or {};
        for slot, lad in pairs(contest.asked) do ladders[slot] = lad; end
    end
    if ladders ~= nil and next(ladders) == nil then ladders = nil; end
    _decSeq = _decSeq + 1;
    _decisions[#_decisions + 1] = {
        seq = _decSeq, time = os.date('%H:%M:%S'), at = os.time(),
        event = event, action = actionLabel(ctx),
        plan = planSnap, contest = contest, ladders = ladders,
        ctx = ctxSnapshot(ctx), changed = changed, nChanged = n, fp = fp,
    };
    while #_decisions > M.DECISION_CAP do table.remove(_decisions, 1); end
    return _decSeq;   -- v154: the action feed links its stub to this decision
end
M._recordDecision = recordDecision;   -- headless test seam (DR*)

-- The action feed's writer (v154). Non-Default events only -- the anchor is a
-- per-ACTION statement; the idle tick's changes already speak through the
-- decision ring. `clk` is os.clock: the fine-grained stamp the 1-second trace
-- time cannot provide (two casts inside a second stay two stubs).
local function recordAction(event, ctx, decSeq)
    if event == 'Default' then return; end
    _actSeq = _actSeq + 1;
    _actions[#_actions + 1] = {
        aseq = _actSeq, at = os.time(), clk = os.clock(),
        event = event, decSeq = decSeq, ctx = ctxSnapshot(ctx),
    };
    while #_actions > M.ACTION_CAP do table.remove(_actions, 1); end
end
M._recordAction = recordAction;   -- headless test seam (IN*)

-- Read-only, the observer's second feed (v154).
function M.getActions() return _actions; end

-- NATIVE sets store (v111): the gProfile.Sets equivalent when this copy IS
-- the engine -- { Dynamic = <profile file data>, <FlattenedName> = <set>, ... },
-- installed by installSets and re-flattened by utils.rebuildSets on the same
-- signals a shim would see (level/subjob/mode changes). nil until the native
-- identity latch (the tick) loads the current job's profile sets.
M._nativeSets = M._nativeSets or nil;

-- The LADDER a set slot would flatten from, ON DEMAND (ADR 0027, stage 1).
-- Reads the authored Dynamic store -- the ladders never left memory; the
-- flatten only ever discarded them logically -- and answers with the SAME
-- context the last flatten used (utils._lastFlattenCtx), so a ladder and the
-- flattened pick it accompanies cannot disagree about level or Dual Wield.
-- Memoized per utils' ladder epoch (bumped by every rebuild; level/subjob/
-- mode changes and installs already re-flatten on the right signals), so a
-- per-frame consumer pays a table lookup. No consumer yet: stage 2 (an
-- INELIGIBLE reserver falls to its next rung) is the first. Tests LD10*.
function M.candidatesFor(setName, slotName)
    if type(M._nativeSets) ~= 'table' then return nil; end
    local dyn = M._nativeSets.Dynamic;
    local st = (type(dyn) == 'table') and dyn[setName] or nil;
    if type(st) ~= 'table' then return nil; end
    -- (the utilsModule() helper is defined further down the file -- inline
    --  the same lazy, cycle-safe lookup here rather than depend on order)
    local u = package.loaded['dlac\\utils'];
    if u == nil then
        local ok, req = pcall(require, 'dlac\\utils');
        if ok and type(req) == 'table' then u = req; end
    end
    if u == nil or type(u.slotLadder) ~= 'function' then return nil; end
    local rev = tonumber(u._laddersRev) or 0;
    local memo = M._ladderMemo;
    if memo == nil or memo.rev ~= rev then
        memo = { rev = rev, by = {} };
        M._ladderMemo = memo;
    end
    local key = tostring(setName) .. '\031' .. tostring(slotName);
    local hit = memo.by[key];
    if hit ~= nil then return hit.ladder; end
    local cctx = u._lastFlattenCtx;
    if cctx == nil then
        -- No flatten has stamped a context in THIS utils state (a reload can
        -- wipe utils while the flattened store survives) -- derive one the
        -- way BuildDynamicSets would, or answer nil pre-login.
        pcall(function()
            local player = gData.GetPlayer();
            if player == nil then return; end
            local mjL, sjL = u.determineLevels();
            cctx = { mjLevel = mjL,
                     isDW = u.isDualWieldAvailable(player.MainJob, mjL, player.SubJob, sjL) };
        end);
    end
    if cctx == nil then return nil; end
    -- Sub pairing judges against THIS set's flattened Main -- derived from
    -- the Main ladder exactly as the flatten derives it (memo-backed).
    local mainObj = nil;
    if tostring(slotName) ~= 'Main' and st.Main ~= nil then
        local mlad = M.candidatesFor(setName, 'Main');
        if mlad ~= nil and type(u.flattenHead) == 'function' then
            local _, mo = u.flattenHead(mlad, 'Main');
            mainObj = mo;
        end
    end
    local lad = u.slotLadder(st[slotName], slotName, mainObj, cctx);
    memo.by[key] = { ladder = lad };
    return lad;
end

-- A set's FLATTENED table by name -- the store's top-level entry, one CHOSEN
-- piece per slot at the live level (statics included; they were born flat).
-- nil until the flatten lands. Consumer: the manifest's pair-home harvest
-- (field 2026-07-28, the Outlaws Earring round): homing every AUTHORED rung
-- froze unchosen leveling rungs to their documented ear/ring and exiled them
-- from the sibling's ladder -- a Lv50 rung under a Lv75 pick could never
-- battery anywhere (its own slot's band read diff 0: the top IS the potency
-- point). Only the flatten's picks anchor pair positions; the unchosen rungs
-- float. Tests FS*.
function M.flattenedSet(name)
    local s = (type(M._nativeSets) == 'table') and M._nativeSets[name] or nil;
    return (type(s) == 'table') and s or nil;
end

local function equipSetByName(name, ctx)
    local s;
    if type(M._nativeSets) == 'table' then
        s = M._nativeSets[name];   -- the sets store (flattened names live top-level)
    end
    if type(s) ~= 'table' then
        -- A trigger MATCHED but its target set is absent from this job's profile
        -- (field case: a Midshot rule pointing at a set never committed on WAR --
        -- the silent skip cost an hour of ghost-hunting). NO chat warn (Henrik:
        -- inform by printing as little as possible) -- the visibility lives in
        -- the Triggers tab now: a red banner + per-row [missing] markers against
        -- profilesets.liveSetNames. The skip itself stays traced in /dl why.
        return false, '', nil;
    end
    local note, tbl = equipResolved(s, ctx);
    return true, note, tbl;
end

local function inlineSummary(equip)
    local parts = {};
    for slot, item in pairs(equip) do parts[#parts + 1] = tostring(slot) .. '=' .. tostring(item); end
    table.sort(parts);
    return table.concat(parts, ', ');
end

-- The engine entry point. Never throws; a failure inside just skips this dispatch.
-- ---------------------------------------------------------------------------
-- Craft-gear overlay (Henrik's design: don't fight the engine, BE the engine).
-- craftwatch (addon state) writes <char>\dlac\craftstate.lua {craft,goal,enabled};
-- when enabled, the engine overlays the resolved craft gear on TOP of whatever
-- Default equipped -- so the craft pieces are simply what the engine wears, and
-- nothing reverts them. Disable -> no overlay -> normal Default returns.
-- ---------------------------------------------------------------------------
local _craft = { raw = nil, data = nil, lastCheck = -1 };
local function ensureCraftState() return ensureStateFile(_craft, 'craftstate.lua'); end

-- Proper-case slot keys for gFunc.EquipSet (resolveVirtual lowercases for the
-- manifest lookup). Ammo excluded: crafting never wants an ammo swap.
local CRAFT_OVERLAY_SLOTS = { 'Main', 'Sub', 'Range', 'Head', 'Neck', 'Ear1', 'Ear2',
                             'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' };

-- The craft equip table for a given craft-state, or nil when off. Split out so
-- tests can pass an explicit state instead of the on-disk file.
local function craftOverlayFor(cs, ctx)
    if type(cs) ~= 'table' or cs.enabled ~= true
       or type(cs.craft) ~= 'string' or cs.craft == '' then return nil; end
    local goal = (cs.goal == 'nq' or cs.goal == 'skillup') and cs.goal or 'hq';
    local equip = nil;
    for _, slot in ipairs(CRAFT_OVERLAY_SLOTS) do
        local nm = resolveVirtual('dlac:AutoCraft', { craftOverride = cs.craft, goalOverride = goal }, slot);
        if type(nm) == 'string' then equip = equip or {}; equip[slot] = nm; end
    end
    return equip;
end
M._craftOverlayFor = craftOverlayFor;   -- test seam

-- ---------------------------------------------------------------------------
-- HELM overlay (v59) -- the craft overlay's gathering twin. helmwatch writes
-- <char>\dlac\helmstate.lua { gather, enabled, at }; when enabled, the engine
-- overlays the resolved HELM gear on Default ONLY (idle-only is the feature:
-- gathering gear must never ride into an action event). Armor + neck + waist
-- only -- HELM tools live in inventory, and an idle weapon swap eats TP.
-- ---------------------------------------------------------------------------
local _helm = { raw = nil, data = nil, lastCheck = -1 };
local function ensureHelmState() return ensureStateFile(_helm, 'helmstate.lua'); end

local HELM_OVERLAY_SLOTS = { 'Head', 'Neck', 'Body', 'Hands', 'Waist', 'Legs', 'Feet' };

-- Is this helm-state wearing gear RIGHT NOW? Two ways in (v60): the manual
-- "Set HELM Idle" switch (enabled), or "Auto HELM" armed with a live
-- detection hold (auto + autoUntil in the future -- helmwatch re-arms it on
-- every 0x034 Point result, so expiry simply means you stopped gathering).
local function helmStateActive(hs)
    if type(hs) ~= 'table' or type(hs.gather) ~= 'string' or hs.gather == '' then return false; end
    if hs.enabled == true then return true; end
    return hs.auto == true and os.time() < (tonumber(hs.autoUntil) or 0);
end
M._helmStateActive = helmStateActive;   -- test seam

-- The HELM equip table for a given helm-state, or nil when off. Split out so
-- tests can pass an explicit state instead of the on-disk file.
local function helmOverlayFor(hs, ctx)
    if not helmStateActive(hs) then return nil; end
    -- IDLE gear only (v61): "Default" is not "idle" -- HandleDefault runs
    -- every frame, combat included, so the status has to gate here. Engaged
    -- or Dead -> stand aside, combat gear wins. 'Event' stays dressed: the
    -- HELM animation itself is an event, dropping there would churn per swing.
    if type(ctx) == 'table' and type(ctx.player) == 'table' then
        local st = tostring(ctx.player.Status or '');
        if ci(st, 'Engaged') or ci(st, 'Dead') then return nil; end
    end
    local equip = nil;
    -- ctx.player rides along so the ladder's level gate sees the REAL level
    -- (the craft overlay's inner ctx drops it and defaults to 75 -- harmless
    -- there, but Field Torque/Rope are Lv65: an underleveled overlay pick
    -- would flap against the client forever).
    local inner = { gatherOverride = hs.gather, player = (type(ctx) == 'table') and ctx.player or nil };
    for _, slot in ipairs(HELM_OVERLAY_SLOTS) do
        local nm = resolveVirtual('dlac:AutoHelm', inner, slot);
        if type(nm) == 'string' then equip = equip or {}; equip[slot] = nm; end
    end
    return equip;
end
M._helmOverlayFor = helmOverlayFor;   -- test seam

-- ---------------------------------------------------------------------------
-- Fishing overlay (v64) -- the third sibling (docs/design/fishing-gear.md).
-- fishwatch writes <char>\dlac\fishstate.lua { enabled, at, target, rod,
-- bait }; when enabled, the engine overlays fishing gear on Default only,
-- standing aside in combat exactly like HELM. Range (rod) and Ammo (bait)
-- come straight from the state file -- they are TARGET-FISH-specific picks
-- the addon resolves (server break math + ownership) and keeps current on
-- its bag heartbeat; armor and Main ride the manifest fish ladders. A rod
-- with no bait still CLAIMS Ammo ('remove', v91): the slot belongs to the
-- overlay whenever the rod is out, or an idle set's trinket flaps it. Main is
-- included on the craft precedent (Halieutica is a Main-slot fishing
-- weapon); the ladder only ever holds fishing Mains, so everyone else
-- never sees a weapon swap.
-- ---------------------------------------------------------------------------
local _fish = { raw = nil, data = nil, lastCheck = -1 };
local function ensureFishState() return ensureStateFile(_fish, 'fishstate.lua'); end

-- Ladder-resolved slots. Range/Ammo are handled separately from the state
-- file; Sub is never touched (nothing fishing-related exists there).
local FISH_LADDER_SLOTS = { 'Main', 'Head', 'Neck', 'Body', 'Hands',
                            'Ring1', 'Ring2', 'Waist', 'Legs', 'Feet' };

local function fishStateActive(fs)
    return type(fs) == 'table' and fs.enabled == true;
end
M._fishStateActive = fishStateActive;   -- test seam

local function fishOverlayFor(fs, ctx)
    if not fishStateActive(fs) then return nil; end
    -- Same idle law as HELM (v61): Default runs every frame, so Engaged or
    -- Dead stand aside. The fishing animations themselves (56-62) never
    -- reach LAC as a Status string, so no extra case is needed -- while the
    -- rod is out the player reads as idle and the overlay stays dressed.
    if type(ctx) == 'table' and type(ctx.player) == 'table' then
        local st = tostring(ctx.player.Status or '');
        if ci(st, 'Engaged') or ci(st, 'Dead') then return nil; end
    end
    local equip = nil;
    if type(fs.rod) == 'string' and fs.rod ~= '' then
        equip = equip or {}; equip.Range = fs.rod;
    end
    if type(fs.bait) == 'string' and fs.bait ~= '' then
        equip = equip or {}; equip.Ammo = fs.bait;
    elseif equip ~= nil and equip.Range ~= nil then
        -- No bait resolved: the rod still brings an Ammo claim -- 'remove',
        -- LAC's native unequip (Henrik, 2026-07-21). Left unclaimed, an idle
        -- set's stat-stick trinket re-plans into Ammo every Default frame
        -- beside the rod, the server strips the rod (ADR 0010), the overlay
        -- re-equips it, and the two flap forever; trinketWornDisplace can't
        -- settle it because the trinket keeps arriving from INSIDE a plan.
        -- Claiming the slot means the overlay (applied above the sets)
        -- overwrites that plan every frame, so it settles rod-on, ammo-empty.
        equip.Ammo = 'remove';
    end
    -- ctx.player rides along so the ladder's level gate sees the REAL level
    -- (the helm overlay's lesson -- Angler's Tunica is Lv15, Angler's Ring 75).
    local inner = { player = (type(ctx) == 'table') and ctx.player or nil };
    for _, slot in ipairs(FISH_LADDER_SLOTS) do
        local nm = resolveVirtual('dlac:AutoFish', inner, slot);
        if type(nm) == 'string' then equip = equip or {}; equip[slot] = nm; end
    end
    return equip;
end
M._fishOverlayFor = fishOverlayFor;   -- test seam

-- ---------------------------------------------------------------------------
-- Chocobo overlay (v120) -- the fourth sibling (docs/design/chocobo-gear.md).
-- chocowatch writes <char>\dlac\chocostate.lua { enabled, at }; when enabled,
-- the engine overlays the best owned riding-time gear on Default only, standing
-- aside in combat exactly like HELM/Fishing. There is no category, no target
-- and no Range/Ammo -- one fixed "best riding-time set" resolved through the
-- manifest choco ladders. Main IS included (the Chocobo Wand): the ladder only
-- ever holds riding gear, so a character without any never sees a Main swap.
-- ---------------------------------------------------------------------------
local _choco = { raw = nil, data = nil, lastCheck = -1 };
local function ensureChocoState() return ensureStateFile(_choco, 'chocostate.lua'); end

-- Slots the Chocobo set dresses: Main/Neck/Body/Hands/Legs/Feet (issue #95).
-- Ring/Waist/Head/Back/Ear are never touched -- the reference riding set has no
-- pieces there and an idle swap in an unrelated slot would just churn gear.
local CHOCO_OVERLAY_SLOTS = { 'Main', 'Neck', 'Body', 'Hands', 'Legs', 'Feet' };

local function chocoStateActive(cs)
    return type(cs) == 'table' and cs.enabled == true;
end
M._chocoStateActive = chocoStateActive;   -- test seam

local function chocoOverlayFor(cs, ctx)
    if not chocoStateActive(cs) then return nil; end
    -- Same idle law as HELM/Fishing (v61): Default runs every frame, so Engaged
    -- or Dead stand aside -- riding gear is for standing around before a
    -- whistle, never for combat.
    if type(ctx) == 'table' and type(ctx.player) == 'table' then
        local st = tostring(ctx.player.Status or '');
        if ci(st, 'Engaged') or ci(st, 'Dead') then return nil; end
    end
    local equip = nil;
    -- ctx.player rides along so the ladder's level gate sees the REAL level
    -- (the HELM/Fishing lesson; riding gear is nearly all Lv1 but the pattern
    -- stays uniform).
    local inner = { player = (type(ctx) == 'table') and ctx.player or nil };
    for _, slot in ipairs(CHOCO_OVERLAY_SLOTS) do
        local nm = resolveVirtual('dlac:AutoChoco', inner, slot);
        if type(nm) == 'string' then equip = equip or {}; equip[slot] = nm; end
    end
    return equip;
end
M._chocoOverlayFor = chocoOverlayFor;   -- test seam

-- (There was a craftOverlay(ctx) wrapper here that paired ensureCraftState with
-- craftOverlayFor. M.dispatch now reads the state itself -- it has to decide
-- whether there is anything to do BEFORE building the context -- so the wrapper
-- would just be a second, hidden read of the same cache.)

-- ---------------------------------------------------------------------------
-- AutoAmmo (v73; per-job fmt 2 in v74) -- the Ammo-slot automation
-- (docs/design/auto-ammo.md). ammowatch (addon state) writes
-- <char>\dlac\ammostate.lua -- fmt 2 gives EVERY JOB its own section
-- (list + persisted on/off; "all jobs can't use all ammos"):
--
--     return { fmt = 2, jobs = {
--       ["RNG"] = { enabled = true, at = <stamp>,
--         ammo = {  -- array order = fallback priority
--           { name = "Bronze Bullet", id = 21306, type = "Marksmanship",
--             ranged = true, ws = false, special = false },
--           { name = "Animikii Bullet", id = 21334, type = "Marksmanship",
--             ranged = false, ws = false,
--             special = { unlimited = true, quickdraw = true, freews = true } },
--         } } } }
--
-- (Legacy fmt 1 -- a top-level ammo list + a jobs BOOLEAN map -- still
-- resolves: the whole table is the cfg and resolveAmmoPlan's map gate does
-- the job check. The GUI migrates the file to fmt 2 on its first load.)
--
-- Unlike craft/HELM/fish this overlay is NOT Default-only: it owns the Ammo
-- slot on the shooting events (Preshot/Midshot/Weaponskill/Ability) and runs a
-- protection sweep on Default. The engine plans only ammo it has just COUNTED
-- in the equippable bags -- LuaAshitacast has no fallback (a set naming an
-- unowned ammo silently equips nothing, which is exactly how a stranded Rare/Ex
-- bullet gets eaten) -- and the ladder ends in a literal 'remove': LAC's
-- first-class unequip (MakeItemTable: 'remove' -> Index 0). An empty gun is
-- BLOCKED server-side (range_state.cpp CanUseRangedAttack), so emptying the
-- slot converts "waste the bullet" into "the shot refuses".
--
-- Server truth the tables encode (public stable branch; §0 of the design doc;
-- live field tests are the promotion gate): ammo is consumed by normal ranged
-- attacks and by PHYSICAL ranged WS only. The three MAGICAL ranged WS --
-- Trueflight 217, Leaden Salute 218, Wildfire 220 -- route through
-- doMagicWeaponskill, which has no ammo code at all: they read the worn ammo's
-- stats but never decrement it. Quick Draw consumes an elemental/Trump card
-- from inventory, never the worn bullet -- but HARD-REQUIRES a Marksmanship
-- ammo equipped (error 216 otherwise), so equipping the special here also
-- un-blocks QD when the slot ran empty. Unlimited Shot = effect id 115.
-- ---------------------------------------------------------------------------
local AMMO_WS_FREE    = { [217] = true, [218] = true, [220] = true };
local AMMO_WS_CONSUME = {   -- every physical Archery(25)/Marksmanship(26) WS in weapon_skills.sql
    [192] = true, [193] = true, [194] = true, [196] = true, [197] = true,
    [198] = true, [199] = true, [200] = true, [201] = true, [203] = true,
    [208] = true, [209] = true, [210] = true, [212] = true, [213] = true,
    [214] = true, [215] = true, [216] = true, [219] = true, [221] = true,
};
-- Quick Draw arrives as HandleAbility; LAC types it 'Quick Draw' off recast
-- timer 195 -- the name set is the belt-and-braces fallback.
local AMMO_QD_NAMES = { ['fire shot'] = true, ['ice shot'] = true, ['wind shot'] = true,
                        ['earth shot'] = true, ['thunder shot'] = true, ['water shot'] = true,
                        ['light shot'] = true, ['dark shot'] = true };
M._ammoWs = { free = AMMO_WS_FREE, consume = AMMO_WS_CONSUME, qd = AMMO_QD_NAMES };   -- test seam

-- Catalog AmmoType -> server weapon skill. The coarse half of a pair key, and the
-- fallback when an ammostate entry predates the Pair stamp: it still separates arrows
-- (25) from bolts-and-bullets (26) from throwables (27), which is most of the bug.
-- It CANNOT separate a bolt from a bullet -- both are Marksmanship -- so an entry that
-- lands here pairs with any 26 weapon until the GUI restamps it. Deliberately the same
-- vocabulary apicrawl's AMMO_SKILL emits.
local AMMO_TYPE_SKILL = { Archery = 25, Marksmanship = 26, Throwing = 27, FishingRod = 48 };
M._ammoTypeSkill = AMMO_TYPE_SKILL;   -- test seam

local _ammoSt = { raw = nil, data = nil, lastCheck = -1 };
local function ensureAmmoState() return ensureStateFile(_ammoSt, 'ammostate.lua'); end

local function ammoStateOn(as)
    if type(as) ~= 'table' then return false; end
    if type(as.ammo) == 'table' then   -- legacy fmt 1: one list + jobs map
        return as.enabled == true and #as.ammo > 0;
    end
    if type(as.jobs) == 'table' then   -- fmt 2: per-job sections
        for _, s in pairs(as.jobs) do
            if type(s) == 'table' and s.enabled == true
               and type(s.ammo) == 'table' and #s.ammo > 0 then
                return true;
            end
        end
    end
    return false;
end
M._ammoStateOn = ammoStateOn;   -- test seam

-- The /dl prio line for AutoAmmo, JOB-AWARE (Henrik's stage-0 field report,
-- 2026-07-27: the file-level ammoStateOn read said ON on a job with no setup
-- -- true of the FILE, wrong about the job you are on; ammoStateOn itself
-- stays file-level on purpose, it feeds the dispatch bail where "some job
-- claims" is the right question). ON when THIS job's setup claims: a fmt-2
-- section that is enabled with a non-empty ladder, or a fmt-1 list whose
-- jobs gate allows the job (resolveAmmoPlan's gate, mirrored: no map = every
-- job). Otherwise off -- naming the jobs that DO have it set up, so "why
-- does it say off" and "why did it say ON" both answer themselves. nil job
-- (not logged in / headless) falls back to the file-level answer rather than
-- inventing a job.
local function ammoJobLine(as, job)
    local ON = 'ON (claims Ammo on shooting events)';
    if type(as) ~= 'table' then return 'off'; end
    if job == nil then return ammoStateOn(as) and ON or 'off'; end
    local others = {};
    if type(as.ammo) == 'table' then       -- legacy fmt 1: one list + a jobs gate map
        if as.enabled == true and #as.ammo > 0 then
            if type(as.jobs) ~= 'table' or as.jobs[job] == true then return ON; end
            for j, v in pairs(as.jobs) do
                if v == true and j ~= job then others[#others + 1] = tostring(j); end
            end
        end
    elseif type(as.jobs) == 'table' then   -- fmt 2: per-job sections
        local s = as.jobs[job];
        if type(s) == 'table' and s.enabled == true
           and type(s.ammo) == 'table' and #s.ammo > 0 then
            return ON;
        end
        for j, sec in pairs(as.jobs) do
            if j ~= job and type(sec) == 'table' and sec.enabled == true
               and type(sec.ammo) == 'table' and #sec.ammo > 0 then
                others[#others + 1] = tostring(j);
            end
        end
    end
    if #others == 0 then return 'off'; end
    table.sort(others);
    return 'off (this job -- set up on ' .. table.concat(others, ', ') .. ')';
end
M._ammoJobLine = ammoJobLine;   -- test seam (CR10*)

-- The LAC state's first bag counter (the LocateItems pattern, engine-side).
-- Equippable containers only; id -> summed Count, plus lowered-name -> count
-- via a session-memoized id -> name table (resources are immutable). Cached
-- per second for the every-frame Default dispatch; `fresh` forces a rescan --
-- the action events use it, because the one moment staleness can hurt is a
-- Preshot planning a replacement that was JUST consumed (a stale count would
-- no-op LAC and leave the special bullet in the slot for the shot to eat).
-- Inventory (0) + the 8 Wardrobes: the seeded engine's equip-eligible bag list.
-- The TWIN of gearoracle.equipBags (ADR 0002: the engine can't require the addon
-- oracle). Byte-for-byte the oracle's list; the OR-section parity pins compare them
-- element-for-element and name this twin on drift.
local AMMO_BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 };
M.AMMO_BAGS = AMMO_BAGS;
local _bagCache = { at = -1, byId = nil, byName = nil };
local _itemNmMemo = {};
local function bagCounts(fresh)
    local now = os.time();
    if not fresh and _bagCache.byId ~= nil and _bagCache.at == now then
        return _bagCache.byId, _bagCache.byName;
    end
    local byId, byName = nil, nil;
    pcall(function()
        local inv  = AshitaCore:GetMemoryManager():GetInventory();
        local resx = AshitaCore:GetResourceManager();
        local bi, bn = {}, {};
        for _, cid in ipairs(AMMO_BAGS) do
            local max = inv:GetContainerCountMax(cid);
            if max ~= nil and max > 0 then
                for idx = 1, max do
                    local it = inv:GetContainerItem(cid, idx);
                    if it ~= nil and it.Id ~= nil and it.Id > 0 and it.Id ~= 65535 then
                        local n = tonumber(it.Count) or 0;
                        if n > 0 then
                            bi[it.Id] = (bi[it.Id] or 0) + n;
                            local nm = _itemNmMemo[it.Id];
                            if nm == nil then
                                local res = resx:GetItemById(it.Id);
                                if res ~= nil and res.Name ~= nil and res.Name[1] ~= nil then
                                    nm = string.lower(res.Name[1]);
                                else
                                    nm = '';
                                end
                                _itemNmMemo[it.Id] = nm;
                            end
                            if nm ~= '' then bn[nm] = (bn[nm] or 0) + n; end
                        end
                    end
                end
            end
        end
        byId, byName = bi, bn;
    end);
    if byId ~= nil then
        _bagCache.at, _bagCache.byId, _bagCache.byName = now, byId, byName;
    end
    return _bagCache.byId, _bagCache.byName;
end

-- ---------------------------------------------------------------------------
-- THE ARBITER'S AVAILABILITY READ (Henrik, 2026-08-01). The impure half of
-- gear\arbiter availVerdict: "is this name in a bag I can equip out of?"
-- ---------------------------------------------------------------------------
-- bagCounts above already IS that scan -- equip-eligible containers only
-- (AMMO_BAGS, the twin of gearoracle.equipBags), summed per lowered name,
-- cached per second. This just gives it the three-valued shape the arbiter
-- wants, and owns the sentinel vocabulary the arbiter deliberately does not
-- know about.
--
-- nil (never refuse) for every name that is not a bag item: the 'remove' /
-- 'ignore' literals, the dlac: markers (resolved to a real name long before
-- this), and the parenthesised placeholders the merged floor carries for the
-- Locks / Disabled defence rows ('(free equip)'), which exist only inside that
-- merge and must never be treated as gear that went missing.
--
-- ...and nil for a bag map that is EMPTY, not just one that is missing. A live
-- character always has something in Inventory or a Wardrobe (you are wearing
-- it), so an empty map means the scan ran before the inventory was there --
-- char select, mid-zone, mid-load. Reading that as "you own none of it" would
-- refuse all sixteen slots at exactly the moments dlac must sit still.
-- ownedcache states the same law for the same reason: a failed lookup must
-- never take a feature away.
local _availAlias = { src = nil, map = nil };
local function haveEquippable(name)
    if type(name) ~= 'string' or name == '' then return nil; end
    local low = string.lower(name);
    if low == 'remove' or low == 'ignore' then return nil; end
    if string.sub(low, 1, 5) == 'dlac:' then return nil; end
    if string.sub(low, 1, 1) == '(' then return nil; end
    local _, byName = bagCounts();
    if type(byName) ~= 'table' or next(byName) == nil then return nil; end
    if (byName[low] or 0) > 0 then return true; end
    -- Apostrophe-tolerant second look, the same law utils.resolveGearName runs
    -- on: the two spellings in this project come from two sources that
    -- disagree -- the client says "Arhat's Gi", anything sourced from the
    -- CatsEyeXI catalog says "Arhats Gi". A name that only differs by the
    -- possessive must never read as a piece you do not own, because that would
    -- silently demote gear you are holding. Aliased lazily and memoized on the
    -- bag map's IDENTITY: bagCounts builds a fresh table every refresh, so this
    -- rebuilds exactly when the counts do.
    local stripped = (string.gsub(low, "'", ""));
    if stripped ~= low then
        if _availAlias.src ~= byName then
            local m = {};
            for k, v in pairs(byName) do
                local s = (string.gsub(k, "'", ""));
                if m[s] == nil then m[s] = v; end
            end
            _availAlias.src, _availAlias.map = byName, m;
        end
        if (_availAlias.map[stripped] or 0) > 0 then return true; end
    end
    return false;
end
M._haveEquippable = haveEquippable;   -- test seam (UA*)

-- The WEARABILITY half of the same resource, by item id (v134). equipcore gates
-- an equip on `level < item.Level` and `Jobs & 2^job` (gear\equipcore checkUsable);
-- the ammo ladder has to ask that same question ONE STEP EARLIER, while a rejected
-- entry can still fall through to the next rung instead of collapsing the whole
-- ladder to a name nothing will accept. Memoized per id exactly like the name
-- table above (resources are immutable) -- and since a candidate only reaches this
-- gate after it has been COUNTED in the bags, the resource is always there to read.
-- A read that answers nothing is not cached, so a not-ready resource manager
-- retries instead of poisoning the id forever.
local _itemGateMemo = {};
local function itemGate(id)
    id = tonumber(id);
    if id == nil or id <= 0 then return nil, nil; end
    local g = _itemGateMemo[id];
    if g == nil then
        g = {};
        pcall(function()
            local res = AshitaCore:GetResourceManager():GetItemById(id);
            if res ~= nil then g.lv, g.jobs = tonumber(res.Level), tonumber(res.Jobs); end
        end);
        if g.lv ~= nil or g.jobs ~= nil then _itemGateMemo[id] = g; end
    end
    return g.lv, g.jobs;
end
M._itemGate = itemGate;   -- test seam

-- The NUMERIC main job, for the Jobs bitmask (the abbreviation the rest of the
-- engine passes around cannot index a mask). nil when not ready -- and nil means
-- "do not job-gate", never "nothing fits", per the ADR 0007 not-ready rule.
local function mainJobId()
    local j = nil;
    pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    j = tonumber(j);
    if j == nil or j <= 0 then return nil; end
    return j;
end

-- ---------------------------------------------------------------------------
-- LOCKED SET, the live half (ADR 0022): the three impure seams
-- M.buildLockedClaim takes. This runs ONCE, when you type the command -- never
-- per dispatch. Everything after arming is table lookups.
-- ---------------------------------------------------------------------------

-- Container id -> display name, so a missing piece can be reported as "in your
-- Mog Satchel" rather than just "not on you". A TWIN of the list ui\fishui.lua
-- draws: ADR 0002 keeps the engine from requiring an addon module, and the
-- addon's own answer to this question (ownedcache.whereText) is a CACHE, so it
-- can be stale at the one moment this has to be right -- the Incursion entrance.
local CONTAINER_NAMES = { [0] = 'Inventory', 'Mog Safe', 'Storage', 'Temporary',
                          'Mog Locker', 'Mog Satchel', 'Mog Sack', 'Mog Case',
                          'Wardrobe', 'Mog Safe 2', 'Wardrobe 2', 'Wardrobe 3',
                          'Wardrobe 4', 'Wardrobe 5', 'Wardrobe 6', 'Wardrobe 7',
                          'Wardrobe 8' };
M._containerNames = CONTAINER_NAMES;

-- Where is it parked? Searches only the containers you CANNOT equip out of --
-- the equip-eligible ones (AMMO_BAGS) were already checked and came back empty.
-- nil means nowhere this character can see it: a mule, or sold.
local function lockedWhereIs(lowerName)
    local where = nil;
    pcall(function()
        local inv  = AshitaCore:GetMemoryManager():GetInventory();
        local resx = AshitaCore:GetResourceManager();
        local skip = {};
        for _, cid in ipairs(AMMO_BAGS) do skip[cid] = true; end
        for cid = 0, 16 do
            if not skip[cid] then
                local max = inv:GetContainerCountMax(cid) or 0;
                for idx = 1, max do
                    local it = inv:GetContainerItem(cid, idx);
                    if it ~= nil and it.Id ~= nil and it.Id > 0 and it.Id ~= 65535 then
                        local res = resx:GetItemById(it.Id);
                        local nm  = (res ~= nil and res.Name ~= nil) and res.Name[1] or nil;
                        if type(nm) == 'string' and string.lower(nm) == lowerName then
                            where = CONTAINER_NAMES[cid] or ('container ' .. tostring(cid));
                            return;
                        end
                    end
                end
            end
        end
    end);
    return where;
end

-- Arm: resolve the set ONCE -- dlac: markers collapsed to concrete names,
-- missing pieces found and located -- and freeze the result. `name` is nil for
-- set-current. Returns the stored record.
local function armLockedSet(setTbl, mode, name)
    local spec = LOCKSET_MODES[mode];
    if spec == nil then return nil; end
    local ctx = buildCtx('Default');
    ctx.syncHold = M.syncSettleHold();
    local _, byName = bagCounts(true);   -- fresh: a deliberate command, once
    local function resolve(v, slot)
        local nm = nil;
        pcall(function() nm = resolveVirtual(setEntryName(v), ctx, slot); end);
        return nm;
    end
    local function locate(entry)
        local nm = setEntryName(entry);
        if nm == nil then return false, nil; end
        local low = string.lower(nm);
        if byName ~= nil and (byName[low] or 0) > 0 then return true, nil; end
        return false, lockedWhereIs(low);
    end
    local claim, missing, n = M.buildLockedClaim(setTbl, spec.fill, resolve, locate, wornItemName);
    return M.setLockedSet({ name = name, mode = mode, claim = claim, n = n, missing = missing });
end

-- The PURE decision (tests AM*): everything read from `cfg` (the state file
-- table) and `f` (the facts the impure wrapper gathered). Returns
-- FOUR values: plan, why, code, chat.
--   plan -- name | 'remove' | nil (hold)
--   why  -- prose for /dl why's note channel
--   code -- machine-readable cause: 'pick' | 'level' | 'stockout' | 'protect' | 'hold'
--   chat -- the ready-to-print line, or nil for "say nothing" (v134)
-- The code exists because the two causes are announced differently: running out
-- of ammo prints, changing rung because your level moved does not. Keeping that
-- as DATA rather than string-matching the prose is what lets the rim print
-- edge-triggered on a change of cause.
--
-- STRICTNESS RULES, in the scope guard's words: special ammo is never planned
-- where a shot could consume it; a window opens only on an AFFIRMATIVE fact
-- (f.unlimited == nil is "unknown" and opens nothing); with a special worn and
-- nothing enabled in stock, the answer is 'remove', because an empty slot
-- refuses the shot server-side.
--
--   f = { event, job, wsId, abilityType, abilityName, unlimited,
--         worn (name|nil), count = function(entry) -> n,
--         rangeWorn (name|nil: what is in the Range slot right now),
--         rangePair (string|nil: its "<skill>:<subskill>" key -- see M.pairsWith),
--         plannedAmmo (bool: this dispatch's rules planned an ammo they own),
--         fishing (bool),
--         -- v134, the level half:
--         level (number|nil: the level to GEAR AT -- playerLevel, so the
--                /dl set level main override wins; nil = do not level-gate),
--         jobId (number|nil: main job id for the Jobs bitmask; nil = no job gate),
--         gate  (function(entry) -> level, jobsMask -- the resource seam),
--         wornLevel (number|nil: the level of what is worn in Ammo right now),
--         syncHold (bool: a level reading just jumped and has not settled) }
--
-- THE RANGE SLOT DECIDES THE AMMO TYPE (Henrik, 2026-07-26). AutoAmmo never writes
-- Range -- that slot belongs to your sets and triggers, full stop -- it only ever asks
-- what is in it and offers ammo that can actually pair. Two rules fall out, both his
-- words: with no ranged weapon worn AutoAmmo "waits and does nothing", and with one
-- worn but nothing in the list able to pair with it, AutoAmmo "should ignore it"
-- rather than force a mismatch in. Before this the picks were type-BLIND, so a bolt
-- sitting above your arrows won with a bow equipped -- and the server answered that by
-- stripping the bow (M.pairsWith).
function M.resolveAmmoPlan(cfg, f)
    if type(cfg) ~= 'table' or cfg.enabled ~= true
       or type(cfg.ammo) ~= 'table' or #cfg.ammo == 0 then
        return nil;
    end
    f = (type(f) == 'table') and f or {};
    -- Jobs gate: the map holds main-job abbreviations the user ticked. A
    -- not-ready job ('NON', '?', nil) is simply never in the map -- the ADR
    -- 0007 rule (gate on what you accept, never enumerate the bad values).
    if type(cfg.jobs) == 'table' then
        if f.job == nil or cfg.jobs[f.job] ~= true then return nil; end
    end
    -- No ranged weapon worn => do nothing at all, on every event. Henrik's ruling, and
    -- the server agrees it is safe: with Range empty a bullet, bolt or arrow cannot be
    -- fired (range_state.cpp CanUseRangedAttack needs a ranged weapon), ranged WS and
    -- Quick Draw both need one too -- so there is no shot to dress for and nothing to
    -- protect a special from. THE ONE EXCEPTION, deliberately not built: THROWING ammo
    -- IS firable with Range empty (CanUseRangedAttack's `|| PAmmo->isThrowing()`), which
    -- is how a NIN throws shuriken. That is the "throwing may be an exception" Henrik
    -- flagged, and it stays parked behind the §8 NIN field tests -- do not widen this
    -- gate until a real ninja has answered them.
    if f.rangeWorn == nil then return nil; end
    local list = cfg.ammo;
    local wornL = (type(f.worn) == 'string') and string.lower(f.worn) or nil;
    local wornE = nil;
    if wornL ~= nil then
        for _, e in ipairs(list) do
            if type(e) == 'table' and type(e.name) == 'string'
               and string.lower(e.name) == wornL then wornE = e; break; end
        end
    end
    local function stocked(e)
        if type(f.count) ~= 'function' then return false; end   -- no counter = no picks (protection still runs)
        local ok, n = pcall(f.count, e);
        return ok and (tonumber(n) or 0) >= 1;
    end
    -- CAN this entry pair with what is in Range? The same graceful ladder the worn side
    -- uses (wornPair): the entry's own Pair when the GUI stamped one, else the skill
    -- implied by its AmmoType -- so an ammostate.lua written before Pair existed still
    -- keeps arrows out of a gun without the player re-adding a thing.
    local function entryPair(e)
        if type(e.pair) == 'string' and e.pair ~= '' then return e.pair; end
        local sk = AMMO_TYPE_SKILL[tostring(e.type or '')];
        return (sk ~= nil) and tostring(sk) or nil;
    end
    -- Only a PROVEN mismatch disqualifies (pairsWith nil = unknown = keep). An unknown
    -- pair must never silently empty someone's list -- that would turn a missing data
    -- field into "AutoAmmo stopped working".
    local function fits(e)
        if f.rangePair == nil then return true; end
        return M.pairsWith(f.rangePair, entryPair(e)) ~= false;
    end
    -- CAN the character wear this AT ALL right now (v134)? The fourth gate, and the
    -- one the ladder spent its first six weeks without: the level and the job. Both
    -- come off f.gate (the live client resource for an item already counted in the
    -- bags, falling back to the entry's stored level) and both mirror
    -- equipcore.checkUsable exactly -- `level < item.Level`, `Jobs & 2^job`.
    -- UNKNOWN NEVER DISQUALIFIES, the same three-valued discipline pairsWith uses:
    -- a missing data field must not read as "AutoAmmo stopped working".
    -- A level of 0 (or below) is NOT a level -- it is the v49 not-ready reading,
    -- and gating on it would skip the entire list. Gate on what you accept.
    local myLevel = tonumber(f.level);
    if myLevel ~= nil and myLevel <= 0 then myLevel = nil; end
    local function wearable(e)
        if type(f.gate) ~= 'function' then return true; end
        local ok, lv, jm = pcall(f.gate, e);
        if not ok then return true; end
        if myLevel ~= nil and lv ~= nil and myLevel < lv then return false; end
        if f.jobId ~= nil and jm ~= nil
           and math.floor(jm / (2 ^ f.jobId)) % 2 ~= 1 then return false; end
        return true;
    end
    -- The protection sweep answers ONE question: could the next shot eat this? A
    -- special the equipped weapon cannot even fire is in no danger -- the server has
    -- already stripped one of the two -- so emptying the slot for it would be pure
    -- churn AND would break the "nothing in the list pairs, so ignore it" ruling.
    -- An UNKNOWN pair still protects: never weaken a safeguard on missing data.
    local wornSpecial = (wornE ~= nil and type(wornE.special) == 'table' and fits(wornE));
    -- ONE walk down the player's order, THREE reports (v134):
    --   win -- the first entry through all four gates: flag, pair, level/job, stock
    --   dry -- the topmost entry that was right in every way EXCEPT stock (this is
    --          what the stock-out chat line names: "X is out -- loading Y")
    --   low -- entries skipped for level/job (/dl why names them; never printed)
    -- The order is always the PLAYER'S. Every gate only ever removes candidates --
    -- none of them reorders, which is why "Sort by level" stays meaningful.
    local function pick(want)
        local win, dry, low = nil, nil, nil;
        for _, e in ipairs(list) do
            if type(e) == 'table' and want(e) and fits(e) then
                if not wearable(e) then
                    low = low or {};
                    low[#low + 1] = tostring(e.name);
                elseif not stocked(e) then
                    if dry == nil then dry = tostring(e.name); end
                else
                    win = e;
                    break;
                end
            end
        end
        return win, dry, low;
    end
    local function plain(e) return type(e.special) ~= 'table'; end
    local function firstRanged()
        return pick(function(e) return e.ranged == true and plain(e); end);
    end
    local function firstWs()
        return pick(function(e) return e.ws == true and plain(e); end);
    end
    local function firstSpecial(beh, needType)
        return pick(function(e)
            return type(e.special) == 'table' and e.special[beh] == true
                   and (needType == nil or e.type == needType);
        end);
    end
    -- The prose for /dl why, the machine-readable cause, and the chat line (nil =
    -- say nothing). Henrik's split, verbatim: "If you run out of ammo, do a print
    -- to notify the player [...] but no prints should be necessary for ammo change
    -- due to level change." So STOCK talks and LEVEL does not, and that distinction
    -- has to survive as data -- the rim prints on the code, not on the prose.
    local function note(base, dry, low, winner)
        local why, code, chat = base, 'pick', nil;
        if dry ~= nil then
            code = 'stockout';
            if winner ~= nil then
                why  = string.format('%s: %s is out -- loading %s', base, dry, winner);
                chat = string.format('%s is out -- loading %s.', dry, winner);
            else
                why  = string.format('%s: %s is out, nothing else stocked', base, dry);
                chat = 'no enabled ammo left in your bags.';
            end
        end
        if low ~= nil and #low > 0 then
            why = why .. string.format(' (%s need a higher level)', table.concat(low, ', '));
            if code == 'pick' then code = 'level'; end
        end
        return why, code, chat;
    end
    local ev = tostring(f.event or '');

    if ev == 'Preshot' or ev == 'Midshot' then
        if f.unlimited == true then
            local sp = firstSpecial('unlimited');
            if sp ~= nil then return sp.name, 'Unlimited Shot window', 'pick'; end
        end
        local r, dry, low = firstRanged();
        local why, code, chat = note('ranged pick', dry, low, (r ~= nil) and r.name or nil);
        if r ~= nil then return r.name, why, code, chat; end
        if wornSpecial then
            return 'remove', 'no enabled ammo in bags -- protecting ' .. wornE.name, 'protect', chat;
        end
        -- nothing to load, nothing to protect: the server refuses the empty shot.
        -- The chat still rides out -- an empty ladder at the moment you shoot is
        -- exactly when silence costs a field round.
        return nil, why, code, chat;
    end

    if ev == 'Weaponskill' then
        local id = tonumber(f.wsId);
        if id ~= nil and AMMO_WS_FREE[id] then
            -- No consumption possible: wear the best thing for the WS. Nothing can
            -- run out here, so there is nothing to announce.
            local sp = firstSpecial('freews');
            if sp ~= nil then return sp.name, 'free-WS window', 'pick'; end
            local w = firstWs();
            if w ~= nil then return w.name, 'WS pick (free WS)', 'pick'; end
            local r = firstRanged();
            if r ~= nil then return r.name, 'ranged pick (free WS)', 'pick'; end
            return nil;
        end
        if id ~= nil and AMMO_WS_CONSUME[id] then
            local w, dry, low = firstWs();
            local why, code, chat = note('WS pick', dry, low, (w ~= nil) and w.name or nil);
            if w ~= nil then return w.name, why, code, chat; end
            if wornSpecial then
                local r = firstRanged();
                if r ~= nil then return r.name, 'no WS ammo -- protecting ' .. wornE.name, 'protect', chat; end
                return 'remove', 'no enabled ammo in bags -- protecting ' .. wornE.name, 'protect', chat;
            end
            return nil, why, code, chat;
        end
        return nil;   -- melee (or unknown) WS: attack.slot = MAIN, ammo untouched
    end

    if ev == 'Ability' then
        local isQD = (f.abilityType == 'Quick Draw');
        if not isQD and type(f.abilityName) == 'string'
           and AMMO_QD_NAMES[string.lower(f.abilityName)] then isQD = true; end
        if isQD then
            -- QD requires a Marksmanship ammo worn -- never offer it an arrow.
            local sp = firstSpecial('quickdraw', 'Marksmanship');
            if sp ~= nil then return sp.name, 'Quick Draw window', 'pick'; end
        end
        return nil;
    end

    if ev == 'Default' then
        -- A level reading that JUST changed is not trusted yet (v56). The weapon
        -- slots have held on this since the Incursion TP bug; Ammo joins them the
        -- moment the LEVEL becomes an input to its pick. Default only: the action
        -- events must never suspend the special-ammo protection, and churn from a
        -- half-settled reading can only happen on this ~0.4s tick anyway.
        -- A level OVERRIDE never arms this -- syncSettleStep tracks MainJobSync,
        -- which /dl set level main does not move. That is deliberate: typing a
        -- level has nothing in flight to settle (auto-ammo.md Section 10.5).
        if f.syncHold == true then return nil, 'level reading is settling', 'hold'; end
        if f.fishing == true then return nil; end   -- the fish overlay owns Ammo (bait) at Default
        if f.unlimited == true then
            -- Pre-load (and keep) the Unlimited Shot special while the buff is
            -- up -- an active plan, so a TP set's generic bullet can't strip
            -- the bullet you popped the ability FOR.
            local sp = firstSpecial('unlimited');
            if sp ~= nil then return sp.name, 'Unlimited Shot window', 'pick'; end
        end
        if wornSpecial then
            -- Window closed: sweep it off. This deliberately beats a set that
            -- plans the special itself -- the contract is that special ammo is
            -- never LEFT equipped where the next shot could eat it.
            local r = firstRanged();
            if r ~= nil then return r.name, 'sweep -- protecting ' .. wornE.name, 'protect'; end
            return 'remove', 'sweep -- no enabled ammo, protecting ' .. wornE.name, 'protect';
        end
        if f.plannedAmmo == true then return nil; end  -- sets planned an ammo they own: theirs
        -- v134: RE-JUDGE WHAT IS WORN, not just an empty slot. Three ways in --
        --   * the slot is empty                         (the original reload)
        --   * the worn ammo is over-level               (nobody could have chosen
        --     it at this level, so it is not a choice to respect)
        --   * the worn ammo is OURS and no longer best  (the ladder moved: a level
        --     went up, a stack ran dry, a weapon changed)
        -- Anything else worn is a set's or the player's own and is UNTOUCHABLE.
        -- That guard is the whole safety story: a Midshot set's Cinderstone must
        -- survive every idle tick, and owning the slot outright would be ADR 0010's
        -- keep-both-flaps-forever arriving through a third door.
        local r, dry, low = firstRanged();
        local why, code, chat = note('ranged pick', dry, low, (r ~= nil) and r.name or nil);
        if r == nil then return nil, why, code, chat; end
        if wornL == nil then return r.name, why .. ' (slot ran empty)', code, chat; end
        local wl = tonumber(f.wornLevel);
        if myLevel ~= nil and wl ~= nil and myLevel < wl then
            return r.name,
                   string.format('%s (%s cannot be worn at level %d)', why, tostring(f.worn), myLevel),
                   (code == 'pick') and 'level' or code, chat;
        end
        if wornE ~= nil then return r.name, why .. ' (better rung available)', code, chat; end
        return nil;
    end

    return nil;   -- Precast/Midcast/Item/PetAction: never ours
end

-- What did this dispatch's matched rules plan for Ammo? Read-only walk of the
-- SORTED hits (last writer wins, the overlay law). A 'dlac:' marker counts as
-- planned (another automation owns the slot); a plain name/table counts only
-- if the player actually stocks it -- a planned-but-unowned ammo is LAC's
-- silent no-op, i.e. exactly the hole AutoAmmo exists to fill.
local function ammoPlannedByHits(hits)
    local plan = nil;
    for _, r in ipairs(hits or {}) do
        if r.equip ~= nil and r.equip.Ammo ~= nil then
            plan = r.equip.Ammo;
        elseif r.sets ~= nil then
            for _, sn in ipairs(r.sets) do
                pcall(function()
                    local sets = M._nativeSets;   -- the one sets store
                    if type(sets) == 'table' and type(sets[sn]) == 'table' and sets[sn].Ammo ~= nil then
                        plan = sets[sn].Ammo;
                    end
                end);
            end
        end
    end
    if plan == nil then return false; end
    local nm = nil;
    if type(plan) == 'table' then nm = plan.Name;
    elseif type(plan) == 'string' then
        if string.lower(string.sub(plan, 1, 5)) == 'dlac:' then return true; end
        nm = plan;
    end
    if type(nm) ~= 'string' or nm == '' then return false; end
    local _, byName = bagCounts(false);
    return byName ~= nil and (byName[string.lower(nm)] or 0) >= 1;
end

-- The impure rim: gather facts, ask the pure rule, shape the overlay table.
local function ammoOverlayFor(as, ctx, event, hits, fishOn)
    if not ammoStateOn(as) then return nil; end
    local job = nil;
    if type(ctx) == 'table' and type(ctx.player) == 'table' then
        job = ctx.player.MainJob;
    end
    -- fmt 2: this job's OWN section is the whole config (no section = this
    -- job never set AutoAmmo up = do nothing). Legacy fmt 1 keeps the whole
    -- table as cfg; resolveAmmoPlan's jobs-map gate does the job check there.
    local cfg = as;
    if type(as.ammo) ~= 'table' and type(as.jobs) == 'table' then
        cfg = (job ~= nil) and as.jobs[job] or nil;
        if type(cfg) ~= 'table' or cfg.enabled ~= true
           or type(cfg.ammo) ~= 'table' or #cfg.ammo == 0 then
            return nil;
        end
    end
    -- Fresh bag scan on action events (see bagCounts); cached on Default.
    local isAction = (event ~= 'Default');
    local byId, byName = bagCounts(isAction);
    -- What is in Range decides which ammo may be offered at all. Read LIVE, every
    -- dispatch: the whole point is that swapping your bow for a gun re-aims AutoAmmo
    -- on the next pass with nobody touching a setting.
    local rangePair, rangeWorn = wornPair('Range');
    -- One walk for the worn Ammo: its name AND its level (v134 needs both, and the
    -- level is how "what you are wearing is over your level now" gets noticed).
    local ammoRes  = wornResOf('Ammo');
    local wornName = (ammoRes ~= nil and ammoRes.Name ~= nil) and ammoRes.Name[1] or nil;
    local f = {
        event   = event,
        job     = job,
        worn    = wornName,
        wornLevel = (ammoRes ~= nil) and tonumber(ammoRes.Level) or nil,
        rangeWorn = rangeWorn,
        rangePair = rangePair,
        fishing = (fishOn == true),
        unlimited = buffActive(ctx, 115),   -- EFFECT_UNLIMITED_SHOT
        -- THE LEVEL WE GEAR AT, not the one the server would permit (v134). This is
        -- playerLevel, so `/dl set level main N` wins here exactly as it wins in the
        -- set flatten (utils.determineLevels) and the virtual slot entries -- reading
        -- MainJobSync straight would have left AutoAmmo the last picker in dlac that
        -- ignores the override, which IS the reported bug. equipcore's own level is a
        -- legality gate against the real game; this one is the CHOICE.
        level   = playerLevel(ctx),
        jobId   = mainJobId(),
        gate    = function(e)
            if type(e) ~= 'table' then return nil, nil; end
            local lv, jm = itemGate(e.id);
            -- Stored level as the fallback: an entry whose id the resource manager
            -- cannot answer for still gets judged (auto-ammo.md Section 10.3 ladder).
            if lv == nil then lv = tonumber(e.level); end
            return lv, jm;
        end,
        syncHold = (type(ctx) == 'table' and ctx.syncHold == true),
        count   = function(e)
            if type(e) ~= 'table' then return 0; end
            local n = (byId ~= nil and tonumber(e.id) ~= nil) and byId[tonumber(e.id)] or nil;
            if n == nil and byName ~= nil and type(e.name) == 'string' then
                n = byName[string.lower(e.name)];
            end
            return n or 0;
        end,
    };
    if event == 'Weaponskill' and type(ctx) == 'table' and type(ctx.action) == 'table' then
        f.wsId = tonumber(ctx.action.Id);
    elseif event == 'Ability' and type(ctx) == 'table' and type(ctx.action) == 'table' then
        f.abilityType = ctx.action.Type;
        f.abilityName = ctx.action.Name;
    elseif event == 'Default' then
        f.plannedAmmo = ammoPlannedByHits(hits);
    end
    local plan, why, code, chat = M.resolveAmmoPlan(cfg, f);
    -- STOCK talks, LEVEL does not (Henrik, v134). Edge-triggered on a change of
    -- cause, NOT on a timer: the engine re-plans every ~0.4s, so a remembered
    -- last-cause is the only thing between one empty stack and a scrolling chat
    -- log. Runs BEFORE the no-plan/no-churn returns below, because the loudest
    -- case of all -- the ladder ran dry and there is nothing to plan -- exits there.
    if code == 'stockout' and type(chat) == 'string' then
        if M._ammoLastCause ~= chat then
            M._ammoLastCause = chat;
            pcall(function() print('[dlac] Ammo: ' .. chat); end);
        end
    elseif code ~= 'hold' then
        M._ammoLastCause = nil;   -- the condition cleared: the next one speaks again
    end
    if plan == nil then return nil; end
    -- Already wearing the plan: hold (no churn, no trace noise). 'remove' with
    -- an empty slot is the same no-op.
    local wornL = (type(f.worn) == 'string') and string.lower(f.worn) or nil;
    if plan == 'remove' then
        if wornL == nil then return nil; end
    elseif wornL ~= nil and string.lower(plan) == wornL then
        return nil;
    end
    -- Loudness (hard rule 12): protection actions PRINT (throttled per cause) --
    -- an emptied slot mid-fight with no line is indistinguishable from a bug.
    if plan == 'remove' then
        local now = os.time();
        if now >= (tonumber(M._ammoWarnAt) or 0) then
            M._ammoWarnAt = now + 10;
            pcall(function() print('[dlac] Ammo: ' .. tostring(why) .. ' -- Ammo slot emptied.'); end);
        end
    end
    return { Ammo = plan }, why;
end
M._ammoOverlayFor = ammoOverlayFor;   -- test seam

-- ---------------------------------------------------------------------------
-- PINNED slots (v44) -- "equip item, lock slot so nothing removes it" (Henrik).
-- Same shape as the craft overlay, and for the same reason: don't fight the
-- engine, BE the engine. pinwatch (addon state) writes <char>\dlac\pinstate.lua
--
--     return { Ring1 = { item = "Rajas Ring", scope = "All" },
--              Head  = { item = "Uk'uxkaj Cap", scope = { "Fast Cast" } } }
--
-- and the engine WEARS those names at top priority -- above the craft overlay,
-- on EVERY event, not just Default (a pin that lost its slot mid-cast would not
-- be a pin). Unpin -> no overlay -> the normal set returns on the next dispatch.
--
-- Deliberately NOT the /dl lock route: a lock only makes the engine ignore the
-- slot, so anything else that strips the piece wins and the state leaks when a
-- session ends abnormally. A pin is recomputed from the file every dispatch --
-- nothing to restore, nothing to leak.
--
-- `scope` is "All" (every dispatch) or a list of trigger LABELS: the pin then
-- applies only on a dispatch where one of those triggers actually matched.
-- ---------------------------------------------------------------------------
local _pin = { raw = nil, data = nil, lastCheck = -1 };
-- (The corrupt-write DROP that used to be special-cased here is now the shared
-- ensureStateFile policy -- this reader is where the field lesson came from.)
local function ensurePinState() return ensureStateFile(_pin, 'pinstate.lua'); end

-- The Arbiter's rank Statefile (ADR 0012). Same policy as every other state
-- file: a hand-edited reorder applies on the next dispatch (1s throttle), a
-- torn/missing write drops to nil and M.arbOrder falls back to the built-in
-- default. `return { order = { 'Pins', 'Locks', 'AutoAmmo', ... } }`.
local _arb = { raw = nil, data = nil, lastCheck = -1 };
local function ensureArbState() return ensureStateFile(_arb, 'arbstate.lua'); end

-- Scope entries are "<Event>|<rule label>" -- the rule label ALONE is ambiguous
-- ('any' is the label of every unconditional rule, so a Precast 'any' and a
-- Midcast 'any' would be indistinguishable and one pin would silently cover
-- both). M.pinScopeKey is the single place that spelling is defined; the GUI
-- builds its menu entries with the same function, so the two states can never
-- drift on the format.
function M.pinScopeKey(event, label) return tostring(event) .. '|' .. tostring(label); end

-- How strongly does this pin's scope cover THIS dispatch? nil = not at all;
-- 0 = "All" (or a missing scope -- a hand-written file), which covers every
-- dispatch and is therefore the weakest claim there is; n > 0 = the index of
-- the LAST hit in this dispatch's hit list that the pin names.
--
-- An unknown key simply never matches: a pin scoped to a trigger you later
-- edited or deleted goes QUIET rather than falling back to forcing gear on
-- every dispatch.
--
-- The index is what settles a slot carrying several pins, and it settles it the
-- way the rest of the engine already settles a slot: `hits` is sorted ascending
-- by priority and applied last-writer-wins (ADR 0003), so the pin belonging to
-- the trigger that would have won the slot anyway is the pin that wins it.
local function pinRank(scope, hits, event)
    if scope == nil or scope == 'All' then return 0; end
    if type(scope) ~= 'table' then return nil; end
    local best = nil;
    for i, r in ipairs(hits or {}) do
        for _, want in ipairs(scope) do
            if M.pinScopeKey(event, r.label) == want then best = i; end
        end
    end
    return best;
end
M._pinRank = pinRank;   -- test seam

-- Does this pin's scope cover this dispatch at all? (pinRank's yes/no face --
-- the question every caller but the multi-pin walk below is actually asking.)
local function pinInScope(scope, hits, event)
    return pinRank(scope, hits, event) ~= nil;
end
M._pinInScope = pinInScope;   -- test seam

-- The pins on ONE slot, whatever shape the file wrote them in: a bare name, one
-- { item, scope } entry, or a LIST of entries (2026-08-03: several pins on one
-- slot -- Optical Hat on TP_Default, Walahra Turban on Movement). pinwatch owns
-- the writer half and its entriesOf is the same reader; this one is spelled out
-- here rather than required because the engine runs in the OTHER Lua state and
-- must never depend on an addon-state module being loaded.
local function pinEntriesOf(p)
    if type(p) == 'string' then return { { item = p, scope = 'All' } }; end
    if type(p) ~= 'table' then return {}; end
    if type(p.item) == 'string' then return { p }; end
    local out = {};
    for _, e in ipairs(p) do
        if type(e) == 'string' then out[#out + 1] = { item = e, scope = 'All' };
        elseif type(e) == 'table' and type(e.item) == 'string' then out[#out + 1] = e; end
    end
    return out;
end
M._pinEntriesOf = pinEntriesOf;   -- test seam

-- The pin equip table for a given pin-state, or nil when nothing is in scope.
-- Split out so tests can pass an explicit state instead of the on-disk file.
--
-- ONE name per slot comes out of here, always: the overlay is an equip table
-- and a slot wears one thing. When a slot carries several pins the highest
-- rank wins (see pinRank), and an exact tie -- two pins on the SAME trigger,
-- which the GUI will not create but a hand-edited file can -- goes to the one
-- written LAST, matching both the file's own set order and the engine's
-- last-writer-wins rule everywhere else.
local function pinOverlayFor(ps, hits, event)
    if type(ps) ~= 'table' then return nil; end
    local equip = nil;
    for slot, p in pairs(ps) do
        local bestName, bestRank = nil, nil;
        for _, e in ipairs(pinEntriesOf(p)) do
            local name = e.item;
            if type(name) == 'string' and name ~= '' then
                local rank = pinRank(e.scope, hits, event);
                if rank ~= nil and (bestRank == nil or rank >= bestRank) then
                    bestRank, bestName = rank, name;
                end
            end
        end
        if bestName ~= nil then
            equip = equip or {};
            equip[slot] = bestName;
        end
    end
    return equip;
end
M._pinOverlayFor = pinOverlayFor;   -- test seam

-- Slots the PINNED pieces take away while worn (their RSlot mask), as
-- { [lowercase slot] = <the pinned item that reserves it> }, or nil.
--
-- Why this is not reservedDrops' job: that pass judges ONE table at a time, on
-- its final names. The pin lands in its OWN equipResolved, so when the set's
-- pass runs, nothing tells it that the pin's Ryl.Ftm. Tunic is about to reserve
-- the Head it just equipped -- and the pin's own pass cannot drop a Head its
-- table never named. The set would re-equip Head every frame and the server
-- would strip it every frame: the v43 flap, reached through the overlay. So the
-- reservation becomes a stateless HOLD instead (the ratified pattern), computed
-- fresh each dispatch and gone the moment the pin is.
--
-- A pin never reserves ANOTHER pin's slot: you asked for both, so both land and
-- the server arbitrates -- exactly as it would for a set naming an illegal pair.
-- (pinReservedSlots RETIRED here, step-1 cleanup 2026-07-27: the hold the
--  doc above describes is the cross-rank verdict's one general rule now --
--  ARK4 pins it -- so the bespoke mechanism and its naked-voids counterpart
--  are gone whole. Mechanisms #3 and #9 of the ADR 0027 inventory: closed.)

-- utils, lazily. Every lookup below used to read package.loaded bare -- "loaded
-- first in the LAC state" (the job shim's own first line is require dlac\utils).
-- The NATIVE state has no shim: nothing loads utils at boot, the lookups read
-- nil, the flatten silently never ran, and every install refused as "world not
-- settled" -- until a GUI picker's own lazy pcall(require) happened to run
-- (Xvs field case, 2026-07-27: sessions healed by opening the right tab, so it
-- read as per-JOB breakage in the field). Require-at-call is cycle-safe in both
-- states: in LAC utils is loaded long before any dispatch runs; natively utils'
-- own require('dlac\\dispatch') hits package.loaded and binds THIS instance,
-- so modesRev stays visible to rebuildSets.
local function utilsModule()
    local u = package.loaded['dlac\\utils'];
    if u ~= nil then return u; end
    local ok, req = pcall(require, 'dlac\\utils');
    if ok and type(req) == 'table' then return req; end
    return nil;
end

-- Craft Sub-vs-Main guard (Henrik, field case: the overlay's Kupo Shield vs a
-- scythe in the Default set). When the overlay owns SUB but brings no MAIN, a
-- set Main that cannot PAIR with that Sub (2H/H2H vs a shield -- utils'
-- subSlotAllowed, the shared pairing rule, decides) must be HELD out of the
-- dispatch: equipping it knocks the craft Sub off and the two slots then knock
-- each other off on every pass. equipResolved applies the hold, so it is
-- stateless -- the moment the overlay clears, Main dispatches normally again;
-- nothing to re-enable, nothing to leak if a craft ends abnormally. (The
-- '/lac disable main' route is a known dead end: it blocks /lac equip and
-- somebody has to remember the re-enable.)
-- Returns guard(mainName) -> true when that Main must be held, or nil when the
-- overlay shape needs no guard / utils is not loaded in this state.
local function craftMainGuard(cEquip)
    if cEquip == nil or cEquip.Sub == nil or cEquip.Main ~= nil then return nil; end
    local g = nil;
    pcall(function()
        local u = utilsModule();
        if type(u) ~= 'table' or u.resolveGearName == nil or u.subSlotAllowed == nil then return; end
        local subRec = u.resolveGearName(cEquip.Sub);
        if type(subRec) ~= 'table' then return; end
        g = function(mainName)
            local mrec = u.resolveGearName(mainName);
            if type(mrec) ~= 'table' then return false; end   -- unknown name: leave it alone
            return u.subSlotAllowed(subRec, mrec, {}) ~= true;
        end
    end);
    return g;
end
M._craftMainGuard = craftMainGuard;   -- test seam

-- (v39's equip-based preview plan lived here until v42: the engine wore the
-- working lockstyle via a Default overlay. Gone whole -- the preview paints
-- the LOOK now (feature/lookpreview.lua) and never touches gear. lockstyle.lua
-- still one-shot retires stale lspreview.lua files for anyone whose LAC state
-- runs an older seeded copy of this file.)

-- ---------------------------------------------------------------------------
-- Lockstyle APPLY, engine-built (v42). gFunc.LockStyle scanned your bags to
-- fill container/index fields and silently no-op'd when its scan came up empty
-- -- but the SERVER never reads those fields. Its handler (CatsEyeXI
-- src/map/packets/c2s/0x053_lockstyle.cpp, read 2026-07-15) takes ItemNo +
-- EquipKind per entry and validates only that the item exists in the item DB
-- and fits the slot. Ownership and job are judged later, at style-resolution
-- (charutils.cpp UpdateArmorStyle / hasValidStyle):
--   * HasItem(char, id)          -- owned in ANY container, Mog Safe included
--   * canEquipItemOnAnyJob(char) -- SOME job of yours, at its CURRENT level,
--                                   could equip it; on failure the armor slot
--                                   silently KEEPS ITS OLD STYLE
--   * weapon slots additionally need the equipped weapon's category to match
-- styleItems also PERSIST server-side per slot: a packet that omits a slot
-- leaves whatever an earlier apply put there (cross-box bleed). So a box is
-- only authoritative if we send all nine visual slots every time -- named ones
-- by id, 'remove' as 0 (style 0 renders the slot EMPTY; that is the server's
-- own semantics, matching the GUI's 'hide'), and unnamed ones frozen to the
-- currently equipped item, so "no pick" means "look like what I actually wear"
-- instead of naked or stale.
-- ---------------------------------------------------------------------------
local LS_KINDS = { { k = 0, s = 'Main' },  { k = 1, s = 'Sub' },  { k = 2, s = 'Range' },
                   { k = 3, s = 'Ammo' },  { k = 4, s = 'Head' }, { k = 5, s = 'Body' },
                   { k = 6, s = 'Hands' }, { k = 7, s = 'Legs' }, { k = 8, s = 'Feet' } };
local LS_JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG',
                  'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
M._LS_JOBS = LS_JOBS;

-- Mirror of the server's canEquipItemOnAnyJob: true when ANY of the character's
-- jobs (jobLevels: abbr -> level) meets the item's job+level requirement.
-- Unknown records pass -- this only predicts; the server decides.
function M._lsStyleGate(rec, jobLevels)
    if type(rec) ~= 'table' then return true; end
    local req = tonumber(rec.Level) or 0;
    if type(rec.Jobs) ~= 'table' or #rec.Jobs == 0 then return true; end
    for _, j in ipairs(rec.Jobs) do
        if j == 'All' then
            for _, l in pairs(jobLevels or {}) do
                if (tonumber(l) or 0) >= req then return true; end
            end
            return false;
        end
        if (tonumber((jobLevels or {})[j]) or 0) >= req then return true; end
    end
    return false;
end

-- The 0x053 bytes (pure -- headless-tested). resolveId(name) -> item id or nil;
-- equippedId(slot) -> the worn item's id (freeze-current for unnamed slots).
-- Returns the packet plus what happened per slot.
function M._lockstylePacket(set, resolveId, equippedId)
    local pkt = {};
    for i = 1, 136 do pkt[i] = 0; end
    pkt[1] = 0x53; pkt[2] = 0x88;   -- header u16 = id | (size/2) << 9
    pkt[5] = 9;                     -- Count: all visual slots, every time
    pkt[6] = 3;                     -- Mode: Set
    pkt[7] = 1;                     -- Flags (what the client sends)
    local sent, frozen, missing = {}, {}, {};
    for n, e in ipairs(LS_KINDS) do
        local o = 0x08 + (n - 1) * 8;   -- lockstyleitem_t: ItemIndex, EquipKind,
        pkt[o + 2] = e.k;               -- Category, pad, ItemNo u16 -- index and
                                        -- category are ignored server-side
        local nm = (type(set) == 'table') and set[e.s] or nil;
        local id = 0;
        if type(nm) == 'string' and nm ~= '' and nm ~= 'remove' then
            id = tonumber(resolveId ~= nil and resolveId(nm) or nil) or 0;
            if id > 0 then sent[e.s] = nm; else missing[#missing + 1] = nm; end
        elseif nm == nil then
            id = tonumber(equippedId ~= nil and equippedId(e.s) or nil) or 0;
            if id > 0 then frozen[e.s] = id; end
        end
        pkt[o + 5] = id % 256;
        pkt[o + 6] = math.floor(id / 256) % 256;
    end
    return pkt, { sent = sent, frozen = frozen, missing = missing };
end

-- Lockstyle box selection (pure -- headless-tested): parsed lockstyles.lua
-- table + optional box number -> (slot->name table, box name, box index), or
-- (nil, why). Explicit n wins; else the file's marked box (active); else 1.
-- Only string values ride: gFunc.LockStyle itself filters non-visual slots
-- and understands the literal 'remove' (lockstyle the slot EMPTY).
function M._lockstyleFrom(t, n)
    if type(t) ~= 'table' or type(t.slots) ~= 'table' then return nil, 'no lockstyle sets saved yet'; end
    n = tonumber(n) or tonumber(t.active) or 1;
    local e = t.slots[n];
    if type(e) ~= 'table' or type(e.set) ~= 'table' then return nil, string.format('lockstyle box %d is empty', n); end
    local out, any = {}, false;
    for slot, v in pairs(e.set) do
        if type(v) == 'string' and v ~= '' then out[slot] = v; any = true; end
    end
    if not any then return nil, string.format('lockstyle box %d has no items', n); end
    return out, ((type(e.name) == 'string' and e.name ~= '') and e.name or ('box ' .. n)), n;
end

-- The lockstyle name/slot resolvers -- ONE pair, two commands ('/dl ls apply'
-- sends, '/dl debug ls' dry-runs; v104 hoisted them out of the apply branch):
-- name -> item id via the char's REAL gear.lua reverse map (the boxes' names
-- came from it) with a resource-manager fallback; slot -> the worn item's id
-- (freeze-current for unnamed slots).
function M._lsResolvers(gr)
    local function resolveId(name)
        local id = nil;
        pcall(function()
            local rec = gr and gr.NameToObject and gr.NameToObject[name] or nil;
            if rec ~= nil then id = tonumber(rec.Id); end
        end);
        if id == nil then
            pcall(function()
                local r = AshitaCore:GetResourceManager():GetItemByName(name, 2)
                       or AshitaCore:GetResourceManager():GetItemByName(name, 0);
                if r ~= nil then id = tonumber(r.Id); end
            end);
        end
        return id;
    end
    local function equippedId(slot)
        local id = nil;
        pcall(function()
            local eq = gData.GetEquipment();
            local it = eq ~= nil and eq[slot] or nil;
            if it ~= nil and it.Item ~= nil then id = tonumber(it.Item.Id); end
        end);
        return id;
    end
    return resolveId, equippedId;
end

-- '/dl debug ls', the engine report (pure with injected resolvers -- tests
-- DBG*): the APPLY PIPELINE AS A DRY RUN. Same box pick (_lockstyleFrom),
-- same packet build (_lockstylePacket), same job-gate prediction -- but the
-- result is lines, not a send. gateFail(name) -> true when the server's
-- silent canEquipItemOnAnyJob gate would keep the old look for that piece.
function M._lsDebugReport(t, n, resolveId, equippedId, gateFail)
    local set, why, box = M._lockstyleFrom(t, n);
    if set == nil then return { 'apply would refuse: ' .. tostring(why) }; end
    local _, r = M._lockstylePacket(set, resolveId, equippedId);
    local sent, frozen = 0, 0;
    for _ in pairs(r.sent) do sent = sent + 1; end
    for _ in pairs(r.frozen) do frozen = frozen + 1; end
    local L = { string.format('box %d "%s": %d slot%s would style, %d frozen to worn gear',
        box, tostring(why), sent, (sent == 1) and '' or 's', frozen) };
    if #r.missing > 0 then
        L[#L + 1] = 'unresolvable name(s) -> slot shows EMPTY: ' .. table.concat(r.missing, ', ');
    end
    local gated = {};
    for slot, nm in pairs(r.sent) do
        if gateFail ~= nil and gateFail(nm) then gated[#gated + 1] = slot .. '=' .. nm; end
    end
    table.sort(gated);
    if #gated > 0 then
        L[#L + 1] = 'server job-gate would KEEP OLD LOOK on: ' .. table.concat(gated, ', ');
    end
    L[#L + 1] = 'DRY RUN -- nothing was sent (/dl ls apply sends).';
    return L;
end

-- ---------------------------------------------------------------------------
-- THE CLAIMANT REGISTRY (ADR 0027, stage 0 -- v136). One row per Arbiter rank
-- row except the Triggers floor. M.dispatch's ensure/active pass, both bail
-- guards, the claims map, the retrace-signature legs, the rank-walk applies
-- and /dl prio's status lines all ITERATE THIS TABLE -- the six hand-copied
-- shapes they replace were the "15 hunks per claimant" the 2026-07-25
-- architecture review measured, three of which failed SILENTLY when forgotten
-- (a missed bail term was a claimant that never dispatched; a missed
-- signature leg was a stale /dl why). Zero behavior change: every row body is
-- the old inline block moved verbatim behind a field, and tests CR* pin the
-- registry's shape as data.
--
-- The row contract (a NEW claimant = one row here + one ARB_ORDER_DEFAULT
-- rank row + the arbwatch UI list; the recipe at arbExplain agrees):
--   name         -- the rank-row name (ADR 0012 vocabulary)
--   ensure(ev)   -- the state read, event gating baked in; nil = stateless
--   active(st)   -- claims this dispatch? (feeds bail #1 where bail1 = true)
--   claim(st, on, env) -> equip[, extra]
--                -- the claim table; env = { ctx, event, hits, fishOn }.
--                   Every row builds here since the FOLD (stage 6) -- the
--                   rank order is already on ctx.rankOf when builders run.
--   bail1/bail2  -- participates in the two bail guards. Disabled and MaxMP
--                   are ABSENT by design: free equip or a bare mode is not a
--                   reason to dispatch.
--   sig(equip, on) -> string  -- the retrace-signature leg ('' = quiet).
--                   Locks has NONE (pre-registry parity: the locked set never
--                   had a leg; the lock LIST is hashed separately upstream).
--   apply(env)   -- the rank-walk application + its /dl why line; nil =
--                   registered for attribution/ceding only (MaxMP: the equip
--                   stays WOVEN in equipResolved until stage 6).
--   prioStatus() -> string    -- the /dl prio row text, self-ensuring (the
--                   same reads M.dispatch does, now in one place).
-- ---------------------------------------------------------------------------
local function claimantSigLeg(equip)   -- the generic leg: sorted slot=item
    if equip == nil then return ''; end
    local ks = {};
    for slot, item in pairs(equip) do ks[#ks + 1] = tostring(slot) .. '=' .. tostring(item); end
    table.sort(ks);
    return table.concat(ks, ',');
end

-- craft/HELM/fishing/chocobo share one apply shape: resolve the overlay at the
-- row's lock-respect, then trace the SLOT LIST (not the items -- pre-registry
-- parity, the four hand-built closures printed keys only).
local function overlayApply(name, label)
    return function(env)
        equipResolved(env.built[name], env.ctx, env.respect(name), name);
        if env.retrace then
            local ks = {};
            for slot in pairs(env.built[name]) do ks[#ks + 1] = tostring(slot); end
            table.sort(ks);
            env.lines[#env.lines + 1] = label .. table.concat(ks, ', ');
        end
    end
end

-- A claimant's LADDER for one slot (ADR 0027 stage 4, claim-side ladders):
-- the resolver's own chain walk in collect mode -- same gates, same order,
-- one code path. nil when the chain is empty or the family has no ladder.
local function chainLadder(marker, vctx, slot)
    local all = {};
    resolveVirtual(marker, vctx, slot, all);
    if all[1] == nil then return nil; end
    local items = {};
    for _, n in ipairs(all) do items[#items + 1] = { name = n }; end
    return { items = items };
end

local function pinStateOn(ps) return type(ps) == 'table' and next(ps) ~= nil; end
local function craftStateOn(cs)
    return type(cs) == 'table' and cs.enabled == true
       and type(cs.craft) == 'string' and cs.craft ~= '';
end

-- The Action sequencer (issue #138), lazily -- it lives in feature/ (one require
-- away) and the JobHelper row reads its live claim/active/status through here.
-- Cycle-safe: the require runs at dispatch time, never at load.
local function actionseqMod()
    local m = nil;
    pcall(function() m = require('dlac\\feature\\actionseq'); end);
    return (type(m) == 'table') and m or nil;
end

-- The EXTERNAL CLAIMS mailbox (2026-08-01), lazily and for the same reason: it
-- lives in feature/ and must never be required at load. It holds standing claims
-- filed by OTHER ADDONS over plugin_event; this row reads them exactly like the
-- Craft row reads a statefile -- no waiting, no round trip, no third-party code
-- anywhere near the equip path.
-- pcall(require, ...) rather than pcall(function() ... end): this is asked TWICE
-- on every dispatch (the ensure pass and the build pass) and Default dispatches
-- constantly, so the closure the wrapper form allocates is pure per-frame
-- garbage for no gain. Same guarantees, same nil-on-failure.
local function extclaimMod()
    local ok, m = pcall(require, 'dlac\\feature\\extclaim');
    return (ok and type(m) == 'table') and m or nil;
end

-- WHO BEAT THE EXTERNAL CLAIM, per slot. Pure, and separate from the apply for
-- two reasons: it is the only thing on this feature an external addon cannot
-- work out for itself, and buried inside the apply it sat downstream of
-- equipResolved -- so a bad frame in the equip path would silently cost the
-- report as well as the gear.
--
-- MATCHES SLOT KEYS CASE-INSENSITIVELY, which is the whole subtlety. arbExplain
-- states the reason and this is the same join: THE PRODUCERS DISAGREE ON CASE --
-- overlay tables use proper-case LAC keys, the Locks veto rides M.locks
-- (lowercased), and a pin table or a locked set carries whatever case its source
-- wrote. A case-SENSITIVE compare does not report a wrong winner, it reports NO
-- winner -- so the addon is told it still holds a slot something else took,
-- silently, and only for the claimants that spell slots the other way.
--
--   mine    -- the External claim table (its casing is what comes back)
--   builtAll-- every claimant's built claim table, by claimant name
--   rankOf  -- claimant -> rank index (SMALLER is stronger)
-- Returns { [MySlotKey] = <winning claimant identity> }; empty when nothing
-- above touched a claimed slot. The STRONGEST claimant above wins the report
-- when several name one slot -- the same "first opinion top-down" the rank walk
-- itself uses, so the sentence the addon reads matches what actually dressed the
-- slot. Tests EX24*.
function M.externalLost(mine, builtAll, rankOf)
    local lost = {};
    if type(mine) ~= 'table' or type(builtAll) ~= 'table' or type(rankOf) ~= 'table' then
        return lost;
    end
    local myRank = rankOf['External'];
    if myRank == nil then return lost; end
    local key = {};                                  -- lowercase slot -> my display key
    for sl in pairs(mine) do key[string.lower(tostring(sl))] = sl; end
    local lostRank = {};
    for nm, eqt in pairs(builtAll) do
        local r = rankOf[nm];
        if r ~= nil and r < myRank and type(eqt) == 'table' then
            for sl in pairs(eqt) do
                local k = key[string.lower(tostring(sl))];
                if k ~= nil and (lostRank[k] == nil or r < lostRank[k]) then
                    lost[k], lostRank[k] = nm, r;
                end
            end
        end
    end
    return lost;
end

-- Weave the per-job JobHelper row into the live rank order (issue #138). A no-op
-- with zero modules installed (the row hides), and otherwise inserts JobHelper
-- at the current job's remembered position -- default directly below Locks. Pure
-- of engine state beyond the current job read; jobhelpers.placedOrder owns the
-- placement + the per-job store. Lazily required, cycle-safe.
local function jobHelperPlace(order)
    local placed = order;
    pcall(function()
        local jh = require('dlac\\feature\\jobhelpers');
        if type(jh.placedOrder) ~= 'function' then return; end
        local job = nil;
        pcall(function() job = gData.GetPlayer().MainJob; end);
        local p = jh.placedOrder(order, job);
        if type(p) == 'table' and #p > 0 then placed = p; end
    end);
    return placed;
end

local CLAIMANTS = {
    -- Pins apply on EVERY event (a pin that lost its slot mid-cast would not
    -- be a pin). The claim is built even when the state is empty -- scoped
    -- pins decide inside pinOverlayFor against the dispatch's hits.
    { name = 'Pins',
      ensure = function() return ensurePinState(); end,
      active = pinStateOn,
      bail1 = true, bail2 = true,
      claim = function(st, on, env) return pinOverlayFor(st, env.hits, env.event); end,
      sig = claimantSigLeg,
      apply = function(env)
          equipResolved(env.built['Pins'], env.ctx, env.respect('Pins'), 'Pins');
          if env.retrace then
              local ks = {};
              for slot, item in pairs(env.built['Pins']) do ks[#ks + 1] = tostring(slot) .. '=' .. tostring(item); end
              table.sort(ks);
              env.lines[#env.lines + 1] = 'PINNED  ->  ' .. table.concat(ks, ', ');
          end
      end,
      prioStatus = function() return pinStateOn(ensurePinState()) and 'ON (armed)' or 'off'; end },
    -- Craft overlay applies on Default even with NO trigger match ("a plain
    -- profile still gets craft gear") -- one Claim among the co-claiming
    -- activities (ADR 0012 amendment, step 1.5): every armed activity claims
    -- whenever its own gates hold -- all of them may claim in one dispatch --
    -- and the Arbiter's rank settles every contested slot, per slot. The
    -- newest-armed (`at` stamp) exclusivity that stood the others down WHOLE
    -- is retired: it was the pre-Arbiter conflict resolver, redundant once
    -- rank arbitrates and actively defeating per-slot composition (the PUP
    -- field case: arming HELM must not pull a fishing rod out of Range that
    -- HELM never claims). Each feature's own gates are untouched (idle-only
    -- stand-asides, Default-only application); arming never switches
    -- activities.
    { name = 'Craft',
      ensure = function(ev) return (ev == 'Default') and ensureCraftState() or nil; end,
      active = craftStateOn,
      bail1 = true, bail2 = true,
      claim = function(st, on, env) return on and craftOverlayFor(st, env.ctx) or nil; end,
      -- Claim-side ladder (ADR 0027 stage 4): the craft chain in collect
      -- mode, same overrides as craftOverlayFor. No craft item carries an
      -- RSlot today -- this is future-proofing: the day one does, a beaten
      -- craft piece FALLS down its chain instead of dying.
      rladder = function(slot, st)
          if not craftStateOn(st) then return nil; end
          local goal = (st.goal == 'nq' or st.goal == 'skillup') and st.goal or 'hq';
          return chainLadder('dlac:AutoCraft', { craftOverride = st.craft, goalOverride = goal }, slot);
      end,
      sig = claimantSigLeg,
      apply = overlayApply('Craft', 'craft gear (overlay)  ->  '),
      prioStatus = function() return craftStateOn(ensureCraftState()) and 'ON (armed)' or 'off'; end },
    -- HELM overlay: same law, its own Claim (co-claims since step 1.5).
    { name = 'HELM',
      ensure = function(ev) return (ev == 'Default') and ensureHelmState() or nil; end,
      active = helmStateActive,
      bail1 = true, bail2 = true,
      claim = function(st, on, env) return on and helmOverlayFor(st, env.ctx) or nil; end,
      -- The HELM chain in collect mode, mirroring helmOverlayFor's inner ctx
      -- (hs.gather is the active category; the hat leads, the generic chain
      -- follows as fallback rungs).
      rladder = function(slot, st, ctx)
          if not helmStateActive(st) then return nil; end
          return chainLadder('dlac:AutoHelm',
              { gatherOverride = st.gather, player = (type(ctx) == 'table') and ctx.player or nil }, slot);
      end,
      sig = claimantSigLeg,
      apply = overlayApply('HELM', 'HELM gear (overlay)  ->  '),
      prioStatus = function() return helmStateActive(ensureHelmState()) and 'ON (armed)' or 'off'; end },
    -- Fishing overlay: same law, its own Claim (v64; co-claims since step 1.5).
    { name = 'Fishing',
      ensure = function(ev) return (ev == 'Default') and ensureFishState() or nil; end,
      active = fishStateActive,
      bail1 = true, bail2 = true,
      claim = function(st, on, env) return on and fishOverlayFor(st, env.ctx) or nil; end,
      -- (Rod/bait are statefile picks, not chain resolves -- the ladder
      --  covers the armor chain only, which is all a fall could ever ask.)
      rladder = function(slot, st, ctx) return chainLadder('dlac:AutoFish', ctx, slot); end,
      sig = claimantSigLeg,
      apply = overlayApply('Fishing', 'fishing gear (overlay)  ->  '),
      prioStatus = function() return fishStateActive(ensureFishState()) and 'ON (armed)' or 'off'; end },
    -- Chocobo overlay: same law, its own Claim (v120; co-claims with the rest).
    { name = 'Chocobo',
      ensure = function(ev) return (ev == 'Default') and ensureChocoState() or nil; end,
      active = chocoStateActive,
      bail1 = true, bail2 = true,
      claim = function(st, on, env) return on and chocoOverlayFor(st, env.ctx) or nil; end,
      rladder = function(slot, st, ctx) return chainLadder('dlac:AutoChoco', ctx, slot); end,
      sig = claimantSigLeg,
      apply = overlayApply('Chocobo', 'chocobo gear (overlay)  ->  '),
      prioStatus = function() return chocoStateActive(ensureChocoState()) and 'ON (armed)' or 'off'; end },
    -- AutoAmmo is NOT Default-gated: it owns the Ammo slot on the shooting
    -- events and only sweeps on Default. Its Default arm stands down whenever
    -- the fishing overlay is live (bait owns the slot -- env.fishOn), and none
    -- of craft/HELM/fish touch Ammo anywhere else (excluded by design). The
    -- claim is applied below the pin, above everything else naming Ammo (v73).
    { name = 'AutoAmmo',
      ensure = function() return ensureAmmoState(); end,
      active = ammoStateOn,
      bail1 = true, bail2 = true,
      claim = function(st, on, env)
          if not on then return nil; end
          return ammoOverlayFor(st, env.ctx, env.event, env.hits, env.fishOn);
      end,
      sig = function(equip) return (equip ~= nil) and ('Ammo=' .. tostring(equip.Ammo)) or ''; end,
      apply = function(env)
          equipResolved(env.built['AutoAmmo'], env.ctx, env.respect('AutoAmmo'), 'AutoAmmo');
          if env.retrace then
              -- label on the left (the player's word), identity in the lookups
              env.lines[#env.lines + 1] = string.format('%s  ->  Ammo=%s  (%s)',
                  ARB.claimantLabel('AutoAmmo'),
                  tostring(env.built['AutoAmmo'].Ammo), tostring(env.bx['AutoAmmo']));
          end
      end,
      -- Job-aware since v137 (the stage-0 field report): the FILE being armed
      -- for some job is not the same fact as THIS job claiming.
      prioStatus = function()
          local job = nil;
          pcall(function() job = gData.GetPlayer().MainJob; end);
          if type(job) ~= 'string' or job == '' or job == '?' then job = nil; end
          return ammoJobLine(ensureAmmoState(), job);
      end },
    -- NAKED (ADR 0021) claims on EVERY event, like Pins: a strip that let go
    -- during a cast would not be a strip. Naked with no triggers, no pins and
    -- nothing armed is the whole point -- hence bail1. Registered like any
    -- other claimant (one rank row, one claim table, no new arm), so woven
    -- MaxMP cedes all 16 slots to it for free.
    { name = 'Naked',
      active = function() return M.nakedOn(); end,
      bail1 = true, bail2 = true,
      claim = function(st, on)
          if not on then return nil; end
          return M.nakedClaim();
      end,
      sig = function(_, on) return on and 'NAKED' or ''; end,
      apply = function(env)
          -- (The pinReserved void dance retired with the belt itself, step-1
          --  cleanup 2026-07-27: pins-vs-naked is the verdict's ordinary
          --  strength contest now -- pins above Naked keep their slots and
          --  reservations by ROW, pins below lose them, one rule.)
          equipResolved(env.built['Naked'], env.ctx, env.respect('Naked'), 'Naked');
          if env.retrace then
              env.lines[#env.lines + 1] = 'NAKED  ->  all 16 slots emptied';
          end
      end,
      prioStatus = function() return M.nakedOn() and 'ON (claims ALL 16 slots empty -- /dl dress releases)' or 'off'; end },
    -- THE LOCKED SET rides the Locks row (ADR 0022) rather than adding a row
    -- of its own: to the player "lock" is one word and one drag target. The
    -- row carries BOTH kinds of opinion -- real item names for slots a locked
    -- set holds (this claim), and the M.LOCK_HELD veto sentinel for slots a
    -- plain /dl lock froze (merged into whyClaims at attribution time). It
    -- claims on EVERY event, for Naked's reason: a hold that let go during a
    -- cast would not be a hold (the Incursion case the command exists for).
    { name = 'Locks',
      active = function() return M.lockedSetOn(); end,
      bail1 = true, bail2 = true,
      claim = function(st, on)
          if not on then return nil; end
          return M.lockedSetClaim();
      end,
      -- sig: NONE (pre-registry parity -- the locked set never had a leg).
      apply = function(env)
          -- env.respect('Locks') asks `rank > lockRank` about its OWN row, so
          -- it is false and the hold punches through M.locks. That is why
          -- arming no longer has to clear the player's locks first: a stale
          -- lock can never strip a slot out of the hold that outranks it, and
          -- it is still sitting there untouched when the hold is released.
          equipResolved(env.built['Locks'], env.ctx, env.respect('Locks'), 'Locks');
          if env.retrace then
              local nHeld = 0;
              for _ in pairs(env.built['Locks']) do nHeld = nHeld + 1; end
              env.lines[#env.lines + 1] = string.format('LOCKED SET "%s"  ->  %d slot(s) held',
                  tostring(M.lockedSetLabel() or '?'), nHeld);
          end
      end,
      -- The /dl prio line reports the lock VETO (M.locks), not the locked set
      -- -- the row's other opinion; both die on job change/logout (v124).
      prioStatus = function()
          return (next(M.locks) ~= nil) and 'ON (veto -- claims above punch through, below stop)'
                                        or 'off (veto -- no slots locked)';
      end },
    -- The DISABLED ceiling (ADR 0024) registers for ATTRIBUTION ONLY -- the
    -- one claimant that equips nothing. Its apply carries NO equipResolved
    -- call, deliberately: the ceiling withholds, and withholding is done at
    -- the write seam (engineEquipSet), above every post-pass. Registering
    -- buys that /dl why sees it -- a disabled slot's contest names the
    -- ceiling as winner instead of an unexplained no-op -- and the trace-only
    -- apply exists because an inert slot with no line anywhere explaining it
    -- is this feature's whole failure mode.
    { name = 'Disabled',
      claim = function() return M.disabledClaim(); end,
      -- Disabling or re-enabling a slot changes the answer /dl why gives, so
      -- it has to move the signature -- 'off:'-prefixed, so it can never
      -- collide with a lock on the same slot name (both lists are lac-case).
      sig = function()
          local dk = M.disabledList();
          return (#dk > 0) and ('off:' .. table.concat(dk, ',')) or '';
      end,
      apply = function(env)
          if env.retrace then
              env.lines[#env.lines + 1] = 'FREE EQUIP  ->  ' .. table.concat(M.disabledList(), ', ')
                  .. '  (dlac writes nothing to these; equip them yourself)';
          end
      end,
      prioStatus = function()
          local dzList = M.disabledList();
          return (#dzList > 0)
              and string.format('ON (ceiling -- dlac writes nothing to %s; /dl enable all releases)',
                  table.concat(dzList, ', '))
              or 'off (ceiling -- no slots disabled)';
      end },
    -- JOBHELPER (issue #138) -- the ONE shared row every Job helper's Action
    -- sequence rides. Its position is per-job (woven in by jobHelperPlace, not in
    -- ARB_ORDER_DEFAULT), but the row itself is an ordinary claimant: while a
    -- sequence is claiming/firing it claims the request's slots, and the standing
    -- rank walk decides every contest -- a senior holder wins its slot and the
    -- sequencer refuses. Claims on EVERY event (like Pins/Naked): a claim that
    -- let go mid-cast would defeat the whole verify-worn contract. bail1/bail2 so
    -- a lone Reward-now with nothing else armed still dispatches.
    { name = 'JobHelper',
      active = function() local m = actionseqMod(); return m ~= nil and m.active() == true; end,
      bail1 = true, bail2 = true,
      claim = function(st, on)
          if not on then return nil; end
          local m = actionseqMod();
          return m and m.claim() or nil;
      end,
      sig = claimantSigLeg,
      apply = function(env)
          local built = env.built['JobHelper'];
          if built == nil then return; end
          equipResolved(built, env.ctx, env.respect('JobHelper'), 'JobHelper');
          if env.retrace then
              local ks = {};
              for slot, item in pairs(built) do ks[#ks + 1] = tostring(slot) .. '=' .. tostring(item); end
              table.sort(ks);
              env.lines[#env.lines + 1] = 'JOB HELPER  ->  ' .. table.concat(ks, ', ');
          end
      end,
      prioStatus = function()
          local m = actionseqMod();
          return (m ~= nil) and m.statusText() or 'idle';
      end },
    -- EXTERNAL (2026-08-01) -- the ONE shared row every OTHER ADDON's claim
    -- rides, and an ordinary claimant in every other respect. Its table arrived
    -- over plugin_event and was merged by feature\extclaim; from here down
    -- nothing knows or cares that it came from another Lua state. Claims on
    -- EVERY event, like Pins and Naked: a claim that let go mid-cast would not
    -- be a claim, and an external addon holding gear through a weaponskill is
    -- the whole use case. bail1/bail2 so an external claim with no triggers and
    -- nothing else armed still dispatches -- the Naked precedent.
    { name = 'External',
      active = function() local m = extclaimMod(); return m ~= nil and m.active() == true; end,
      bail1 = true, bail2 = true,
      claim = function(st, on)
          if not on then return nil; end
          local m = extclaimMod();
          return m and m.claim() or nil;
      end,
      sig = claimantSigLeg,
      apply = function(env)
          local built = env.built['External'];
          if built == nil then return; end
          -- THE VERDICT REPORT, taken BEFORE the equip. An external addon can
          -- see what it was GIVEN (the worn stream) but never why a slot it
          -- asked for did not arrive, and guessing produces exactly the
          -- confidently-wrong behavior the read half's correlation rule exists
          -- to prevent -- so this must not sit downstream of the equip path,
          -- where a bad frame would cost the explanation as well as the gear.
          -- Rows ranked ABOVE this one have BUILT their claims (the build pass
          -- completes before any apply) and have not applied yet, so this is the
          -- same same-dispatch view MaxMP's gates use: the plan is the only
          -- lag-free claim signal.
          local ctx2 = env.ctx;
          local lost = M.externalLost(built, env.built,
              (type(ctx2) == 'table') and ctx2.rankOf or nil);
          pcall(function()
              local m = extclaimMod();
              if m ~= nil then m.noteVerdict(lost); end
          end);
          equipResolved(built, env.ctx, env.respect('External'), 'External');
          if env.retrace then
              local ks = {};
              for slot, item in pairs(built) do
                  ks[#ks + 1] = tostring(slot) .. '=' .. tostring(item)
                      .. ((lost[slot] ~= nil) and (' [lost to ' .. tostring(lost[slot]) .. ']') or '');
              end
              table.sort(ks);
              env.lines[#env.lines + 1] = 'OTHER ADDONS  ->  ' .. table.concat(ks, ', ');
          end
      end,
      prioStatus = function()
          local m = extclaimMod();
          return (m ~= nil) and m.statusText() or 'off';
      end },
    -- MaxMP, FOLDED (ADR 0027 stage 6, Henrik's item-3 ruling: "the Arbiter
    -- is the aware one"). The bands still decide WHEN (mpBands, pure) and
    -- the resolvers WHAT (mpRungs/mpBestPick, pure); this row is the
    -- DELIVERY: its claim is the band targets (mpClaimFor), and its apply
    -- filters them through the four gates against THIS dispatch's plan --
    -- ctx.planOut, the lag-free claim signal the failure museum demanded --
    -- then dresses at its rank like every other claimant. Ceding is apply
    -- order; lock-respect is the ordinary respect('MaxMP'); the no-band
    -- worn-protect is the mp-hold constraint in POST_ORDER.
    { name = 'MaxMP',
      claim = function(st, on, env) return mpClaimFor(env.ctx); end,
      sig = claimantSigLeg,
      apply = function(env)
          local mc = env.built['MaxMP'];
          local ctx2 = env.ctx;
          local mpc = M.mpBands(ctx2);
          if mc == nil or mpc == nil then return; end
          -- THE SAME-DISPATCH VIEW (failure museum #9: the plan is the only
          -- lag-free claim signal). `planned` is everything merged below this
          -- rank (the floor + weaker rows, already applied); `above` is the
          -- strongest claim per slot from rows ranked ABOVE MaxMP, which have
          -- NOT applied yet -- the weave ran inside their equipResolved calls
          -- and saw their tables live, so the gates keep that sight.
          local planned = {};
          for slot, v in pairs((type(ctx2) == 'table' and type(ctx2.planOut) == 'table') and ctx2.planOut or {}) do
              if type(v) == 'string' then planned[string.lower(tostring(slot))] = v; end
          end
          local above, aboveRank = {}, {};
          local myRank = (type(ctx2) == 'table' and type(ctx2.rankOf) == 'table') and ctx2.rankOf['MaxMP'] or nil;
          if myRank ~= nil then
              for nm, eqt in pairs(env.built or {}) do
                  local r = ctx2.rankOf[nm];
                  if r ~= nil and r < myRank and type(eqt) == 'table' then
                      for sl, it in pairs(eqt) do
                          if type(it) == 'string' then
                              local ls2 = string.lower(tostring(sl));
                              if aboveRank[ls2] == nil or r < aboveRank[ls2] then
                                  above[ls2], aboveRank[ls2] = it, r;
                              end
                          end
                      end
                  end
              end
          end
          local function viewOf(ls) return above[ls] or planned[ls]; end
          local gnotes, cand = {}, {};
          for slot, name in pairs(mc) do
              local ls = string.lower(tostring(slot));
              local pv = planned[ls];
              if pv == 'remove' then
                  -- v91: an explicit empty-the-slot claim beats a battery.
                  gnotes[#gnotes + 1] = string.format('%s: remove respected', ls);
              elseif mpc.moveYield and mpc.moving and pv ~= nil
                 and (mpc.mvMap[string.lower(pv)] or 0) > 0 then
                  -- movement yield (v96): the plan's Movement+ piece flows.
                  gnotes[#gnotes + 1] = string.format('%s: MP-MOVE %s stays', ls, pv);
              else
                  cand[#cand + 1] = { slot = slot, lslot = ls, name = name };
              end
          end
          -- sticky pairs (v93/v94): the claim view + worn veto INDEPENDENTLY
          -- (failure museum #7).
          local sticky;
          cand, sticky = M.mpStickyPairs(cand, function(ls)
              return viewOf(ls), wornItemName(ls);
          end, mpc.mpBest);
          if sticky ~= nil then
              for _, sk in ipairs(sticky) do
                  gnotes[#gnotes + 1] = string.format('%s: MP-PAIR %s stays in %s',
                      tostring(sk.c.lslot), tostring(sk.c.name), tostring(sk.sib));
              end
          end
          -- RSlot eligibility (v78): a battery reserving an occupied slot never stages.
          local eligible, skipped = M.mpStageEligible(cand, function(ls)
              return viewOf(ls) or wornItemName(ls);
          end, rslotOf);
          if skipped ~= nil then
              for _, sk in ipairs(skipped) do
                  gnotes[#gnotes + 1] = string.format('%s: MP-SKIP %s (reserves occupied %s)',
                      tostring(sk.c.lslot), tostring(sk.c.name), tostring(sk.blocking));
              end
          end
          local eq = nil;
          for _, up in ipairs(eligible or {}) do eq = eq or {}; eq[up.slot] = up.name; end
          if eq ~= nil then equipResolved(eq, ctx2, env.respect('MaxMP'), 'MaxMP'); end
          if env.retrace then
              local ks = {};
              for slot, nm in pairs(eq or {}) do ks[#ks + 1] = tostring(slot) .. '=' .. tostring(nm); end
              table.sort(ks);
              env.lines[#env.lines + 1] = 'MaxMP (batteries)  ->  '
                  .. ((#ks > 0) and table.concat(ks, ', ') or '(all gated)')
                  .. ((#gnotes > 0) and ('  [' .. table.concat(gnotes, '; ') .. ']') or '');
          end
      end,
      prioStatus = function() return (M.modes['maxmp'] ~= nil) and 'ON (claims batteries; slots won above it stand down)' or 'off'; end },
};

-- The retrace-signature leg order: the exact byte order of the hand-built
-- concat this replaces (c|p|h|f|ch|a|m|n|dz), so a live session does not
-- retrace once on upgrade. Reordering is harmless but must be done ON PURPOSE
-- -- CR2 pins it.
-- JobHelper APPENDED (issue #138): a new leg at the end leaves the nine existing
-- legs byte-identical, so an install with no sequence live never retraces on
-- upgrade -- its leg is '' until a sequence claims.
-- External APPENDED for the same reason JobHelper was: a new leg at the end
-- leaves every existing leg byte-identical, so nobody retraces on upgrade -- and
-- the leg matters more here than anywhere. An external claim that changes
-- without moving the signature is a claim dlac never re-dispatches: it would sit
-- in the mailbox looking accepted and never reach a slot, and the failure is
-- completely silent from both sides of the wire.
local CLAIMANT_SIG_ORDER = { 'Craft', 'Pins', 'HELM', 'Fishing', 'Chocobo',
                             'AutoAmmo', 'MaxMP', 'Naked', 'Disabled', 'JobHelper',
                             'External' };
local CLAIMANT_BY = {};
for _, row in ipairs(CLAIMANTS) do CLAIMANT_BY[row.name] = row; end
M._claimants = CLAIMANTS;                    -- test seams (CR*)
M._claimantSigOrder = CLAIMANT_SIG_ORDER;

function M.dispatch(event)
    if not engineActive() then return; end
    pcall(function()
        event = EVENT_CANON[string.lower(tostring(event))] or event;
        -- While the PET's action is in flight, HOLD Default: the pet gear a
        -- PetAction rule equipped must survive until the action completes
        -- (upstream parity -- LAC clears gState.PetAction on the completion
        -- packet; the Completion timestamp is the backstop). Petless: no effect.
        -- Native mode reads the same fact from equipengine's state.
        if event == 'Default' then
            local held = false;
            pcall(function()
                local st = rawget(_G, 'gState');
                local pa = (st ~= nil) and st.PetAction or nil;
                if pa == nil then
                    local eng = nativeEngine();
                    pa = (eng ~= nil) and eng.state.petAction or nil;
                end
                if pa ~= nil and (pa.Completion == nil or os.clock() < pa.Completion) then held = true; end
            end);
            if held then return; end
            -- NATIVE re-flatten (v111): the shim called utils.rebuildSets on
            -- every HandleDefault so level/subjob/mode changes re-pick ladder
            -- rungs; the native store rides the same cadence (cheap no-op when
            -- nothing changed -- checkRebuildNeeded's own latch).
            if type(M._nativeSets) == 'table' then
                pcall(function()
                    local u = utilsModule();
                    if u ~= nil and type(u.rebuildSets) == 'function' then
                        M._nativeSets = u.rebuildSets(M._nativeSets) or M._nativeSets;
                    end
                end);
            end
        end
        local rules = ensureLoaded();
        local list = rules and rules[event] or nil;
        local hasRules = (list ~= nil and #list > 0);

        -- THE CLAIMANT REGISTRY PASS (ADR 0027, stage 0). One ensure/active
        -- walk over CLAIMANTS replaces the eight hand-wired state blocks; each
        -- row's event gating (craft/HELM/fish/choco are Default-only; Pins,
        -- AutoAmmo, Naked and the locked set claim on EVERY event) is baked
        -- into its ensure/active fields, comments included. Reads stay the
        -- 1/sec-throttled cached ones, so this is as cheap as the blocks it
        -- replaced on the Default dispatch that runs every frame.
        --
        -- Bail only when there is genuinely NOTHING to do. This used to return
        -- on the rule list alone -- which quietly made the overlays dead on any
        -- event the profile has no rules for ("a plain profile still gets craft
        -- gear"; an "All" pin has to hold on a profile with no triggers at all;
        -- naked/locked with nothing else armed is the whole point, and bailing
        -- past the hold is exactly how NK26 found the strip could not fire) --
        -- so every bail1 row is consulted HERE, ahead of the early return.
        -- Disabled and MaxMP carry no bail1 BY DESIGN: free equip or a bare
        -- mode alone is not a reason to dispatch.
        local cState, cOn = {}, {};
        for _, row in ipairs(CLAIMANTS) do
            if row.ensure ~= nil then cState[row.name] = row.ensure(event); end
            cOn[row.name] = (row.active ~= nil) and (row.active(cState[row.name]) == true) or false;
        end
        local anyClaimant = false;
        for _, row in ipairs(CLAIMANTS) do
            if row.bail1 == true and cOn[row.name] then anyClaimant = true; break; end
        end
        if not hasRules and not anyClaimant then return; end

        local ctx = buildCtx(event);
        -- Level-sync settle (v56): computed ONCE per dispatch and ridden by every
        -- equipResolved below (rule hits, craft overlay, pin overlay) -- the
        -- pinReserved pattern. While it holds, weapon slots stay as worn.
        ctx.syncHold = M.syncSettleHold();
        -- ONE PLAN, ONE SEND (stage 3's last slice): every equipResolved pass
        -- below merges here instead of sending; the single send is after the
        -- apply walk.
        ctx.planOut = {};
        local hits = {};
        if hasRules then
            for _, r in ipairs(list) do
                if matches(r, ctx) then hits[#hits + 1] = r; end
            end
        end
        -- Sorted HERE (was just before application): the AutoAmmo overlay's
        -- planned-Ammo walk needs the same last-writer-wins order the
        -- application loop uses. Ascending priority, file order on ties
        -- (ADR 0003).
        table.sort(hits, function(a, b)
            if a.prio ~= b.prio then return a.prio < b.prio; end
            return a.ord < b.ord;
        end);

        -- THE CLAIM BUILD PASS (ADR 0027, stage 0): every row's claim table in
        -- one registry walk -- craft/HELM/fish/choco overlays, the pin table
        -- (scoped pins read `hits`, sorted above), AutoAmmo's plan (its row
        -- reads env.fishOn -- bait owns the slot), naked, the locked set and
        -- the disabled ceiling. Build order between rows is free (each builder
        -- reads only its own state + env; verified for stage 0) -- but the
        -- INTER-claim wiring below stays after the whole pass, exactly where
        -- it ran before.
        -- THE RANK ORDER COMES FIRST (the FOLD, stage 6): the live arbiter
        -- order is read BEFORE any claim builds, so every builder -- MaxMP's
        -- band context included (its lock consult is rank-aware via
        -- ctx.rankOf) -- sees the same precedence the applies below run
        -- under. Locks are the VETO ROW (ADR 0012, step 3): a claimant ABOVE
        -- the row punches through a locked slot, one BELOW stops;
        -- layerRespectsLocks answers per claimant, and the Triggers floor is
        -- always last, so it always respects.
        local arbOrder = jobHelperPlace(M.arbOrder(ensureArbState()));   -- issue #138
        local rankOf = {};
        for i, n in ipairs(arbOrder) do rankOf[n] = i; end
        local lockRank = rankOf['Locks'] or 0;
        local function layerRespectsLocks(name)
            local r = rankOf[name];
            return r == nil or r > lockRank;   -- below Locks (or unknown) => respect
        end
        ctx.rankOf = rankOf;   -- band build, mp-hold + the row applies read this

        local built, bx = {}, {};   -- claim tables + builder extras (AutoAmmo's why)
        local benv = { ctx = ctx, event = event, hits = hits, fishOn = cOn['Fishing'] };
        for _, row in ipairs(CLAIMANTS) do
            if row.claim ~= nil then
                built[row.name], bx[row.name] = row.claim(cState[row.name], cOn[row.name], benv);
            end
        end
        local cEquip, pEquip = built['Craft'], built['Pins'];

        -- (ctx.pinReserved RETIRED, step-1 cleanup 2026-07-27: a pinned
        --  reserver's hold is the cross-rank verdict's job now -- its claim
        --  enters the merged floor at the Pins row and SUPPRESSES the slots
        --  it reserves by the one general rule, ARK4. The belt rode as a
        --  redundant second copy since v141; the general rule has its field
        --  rounds, so the belt comes off.)

        -- Pin beats craft (it is applied after it), so a craft Sub that cannot
        -- pair with a PINNED Main has to go: left in, craft would re-equip it
        -- every pass and the pinned Main would knock it straight off again --
        -- the v37 flap seen from the other side.
        if pEquip ~= nil and pEquip.Main ~= nil and cEquip ~= nil and cEquip.Sub ~= nil then
            local pg = craftMainGuard({ Sub = cEquip.Sub });
            if pg ~= nil and pg(pEquip.Main) then cEquip.Sub = nil; end
        end

        -- The Sub-vs-Main guard (v37). A PINNED Sub with no pinned Main must
        -- survive everything BELOW it -- the set's Main and the craft overlay's
        -- alike -- so the pin becomes the guard's source in that case; otherwise
        -- the craft overlay keeps it exactly as before. Stateless either way:
        -- unpin, and the held Main dispatches normally on the next pass.
        local guardSrc = (pEquip ~= nil and pEquip.Sub ~= nil and pEquip.Main == nil)
                         and pEquip or cEquip;
        ctx.craftMainGuard = (guardSrc ~= nil) and craftMainGuard(guardSrc) or nil;

        -- THE ARBITER (ADR 0012, steps 1 + 4). One data-driven registry orders
        -- every Claim's application: the built claims are collected as a map
        -- and applied below in RANK order -- the hardcoded craft/HELM/fish/
        -- ammo/pin sequence is gone. Every claim the build pass produced
        -- joins, MaxMP's included (the FOLD, stage 6): its batteries build in
        -- the registry pass like every other row, ceding is nothing but apply
        -- order -- rows above apply later and overwrite, Locks strip via
        -- respect('MaxMP'), the Disabled ceiling filters at the write seam --
        -- and ctx.mpCeded/ctx.mpRespectLocks are RETIRED.
        local claims = {};
        for _, row in ipairs(CLAIMANTS) do
            if built[row.name] ~= nil then claims[row.name] = built[row.name]; end
        end

        -- Nothing matched and nothing built: the second bail, registry-driven
        -- (bail2 rows only -- Disabled and MaxMP deliberately keep out of it,
        -- exactly as they keep out of bail #1).
        local anyBuilt = false;
        for _, row in ipairs(CLAIMANTS) do
            if row.bail2 == true and built[row.name] ~= nil then anyBuilt = true; break; end
        end
        if #hits == 0 and not anyBuilt then
            if event ~= 'Default' then   -- Default runs every frame; only action events trace a miss
                _trace[event] = { time = os.date('%H:%M:%S'), action = actionLabel(ctx),
                                  sig = '', lines = { '(no trigger matched)' } };
                -- The action feed still stubs it (v154): "seen, decided
                -- nothing" is exactly what an anchor exists to say.
                recordAction(event, ctx, nil);
            end
            return;
        end

        -- (hits already sorted above -- the AutoAmmo walk needed the order.)

        -- Equip every hit. Trace strings are rebuilt only when the matched-rule
        -- signature changes (Default dispatches per frame -- keep the GC quiet).
        local sig = {};
        -- Which case each hit matched (issue #125): folded into the retrace
        -- signature so a rule that stays a hit but switches cases (together-block
        -- one dispatch, a `| case` the next) re-traces and /dl why re-names it.
        -- nil for a case-less rule -> sig is byte-identical to before.
        local hitCase = {};
        for hi, r in ipairs(hits) do
            local mc = M.matchedCase(r, ctx);
            hitCase[hi] = mc;
            sig[#sig + 1] = mc and (tostring(r.ord) .. '@' .. mc) or tostring(r.ord);
        end
        local lk = {};
        for s in pairs(M.locks) do lk[#lk + 1] = s; end   -- lock changes must retrace too
        table.sort(lk);
        -- Claimant retrace legs (ADR 0027, stage 0): one row.sig each, joined
        -- in CLAIMANT_SIG_ORDER -- the exact byte order of the nine hand-built
        -- legs this replaces (craft|pins|HELM|fishing|chocobo|ammo|mp|naked|
        -- disabled), so a live session does not retrace once on upgrade. Any
        -- claim's change must retrace: that is what a leg IS.
        local legs = {};
        for _, lnm in ipairs(CLAIMANT_SIG_ORDER) do
            local lrow = CLAIMANT_BY[lnm];
            legs[#legs + 1] = (lrow ~= nil and lrow.sig ~= nil) and lrow.sig(built[lnm], cOn[lnm]) or '';
        end
        -- The SETS-STORE REVISION must retrace too (field, 2026-07-26): every
        -- install and re-flatten bumps M.modesRev, and trace lines resolve set
        -- names against that store -- lines built against an empty boot-window
        -- store printed "[NOT FOUND in profile Sets]" with a fresh timestamp
        -- for a whole session after the install landed. The v118 law, applied
        -- to the trace: THE INSTALL INVALIDATES THE BELIEF. Tests TRC1-TRC3.
        -- The RANK ORDER is a sig leg too (v152): a dragged row flips winners
        -- with no rule or claim moving -- without this leg /dl why kept the old
        -- attribution until something else changed, and the decision ring
        -- missed a winner change under identical items.
        sig = event .. ':' .. table.concat(sig, ',') .. '|' .. table.concat(lk, ',')
              .. '|' .. table.concat(legs, '|') .. '|sr' .. tostring(M.modesRev or 0)
              .. '|ao' .. table.concat(arbOrder, ',');
        local old = _trace[event];
        local retrace = (old == nil) or (old.sig ~= sig) or (event ~= 'Default');
        local lines = retrace and {} or old.lines;

        -- Trigger-monitor feed (v55): one ring entry per CHANGE of what fired
        -- (retrace is exactly that signal -- Default only when its matched-rule
        -- set moves, action events every time).
        if retrace and #hits > 0 then
            local mp = {};
            for _, r in ipairs(hits) do
                local dst;
                if r.sets ~= nil then dst = table.concat(r.sets, '+');
                elseif r.equip ~= nil then dst = 'inline equip';
                else dst = '?'; end
                mp[#mp + 1] = r.label .. ' -> ' .. dst;
            end
            table.insert(_fired, 1, os.date('%H:%M:%S') .. '  ' .. event .. '   ' .. table.concat(mp, '   ||   '));
            while #_fired > 5 do table.remove(_fired); end
            _firedDirty = true;
            -- Event push: STREAM the new line to the addon state's monitor over
            -- the command bus -- the one live channel two Lua states share (the
            -- mode-keybind /bind precedent). Fires only on retrace, so a rule
            -- matching again unchanged never re-sends. The firedstate.lua file
            -- stays as the reload bootstrap + fallback. NOT QueueCommand'd here:
            -- two commands queued in the SAME frame arrive at the addon in
            -- REVERSE order (Henrik's field report -- every cast showed Precast
            -- above Midcast, both stamped the same second), so lines land in
            -- _monQ and the frame tick streams them one per frame -- the
            -- cmdqueue.lua frame-spacing precedent, engine-side (v58).
            local line = string.gsub(_fired[1], '%c', ' ');
            if #line > 180 then line = string.sub(line, 1, 180); end
            _monQ[#_monQ + 1] = line;
        end

        -- Apply in order, attributing each SLOT to its final writer -- with partial
        -- sets (weapon-only, DT-only, ...) this is what proves the overlay: every
        -- slot lists the rule that actually owns it this dispatch. floorTbl also
        -- collects the merged trigger-overlay result (last-writer-wins, the same
        -- order): it is the FLOOR the claims dress over, fed to the Arbiter's
        -- attribution below (ADR 0012, step 4).
        -- ALWAYS COLLECTED (2026-08-02, field report 3). These were gathered
        -- only on a retrace, which made the contest un-rebuildable on any
        -- other pass -- and a dispatch whose PLAN moved without the trace
        -- signature moving then attached the PREVIOUS plan's explanation to a
        -- new ring record. The gate was sharing one `if retrace` with the
        -- /dl why LINE FORMATTING, which is the part that actually costs
        -- (a string.format per rule); filling these two is a handful of table
        -- writes next to the equipSetByName that already ran. Split, so the
        -- expensive half stays gated and the attribution is always there.
        local slotSrc, floorTbl = {}, {};

        -- THE OVERLYING EYE (v135, Henrik's word for it) -- since stage 4 the
        -- CROSS-RANK verdict (ADR 0027 item 2, ratified). Merge every matching
        -- rule's set AND every built claim BEFORE a single slot is written, so
        -- the reserve rule can be asked the only question that matters: for
        -- this piece, am I dominant in ALL the slots it takes -- judged by
        -- STRENGTH (rank outright across rows; trigger priority within the
        -- floor; ties favor the reserver; ord excluded). The v135 scoping --
        -- floor-only, cleared before the claims applied -- retired with the
        -- two-orderings problem it existed for: rows make the contests
        -- comparable. The stage-2 FALL rides along: an ineligible floor piece
        -- falls down its source ladder (candidatesFor) and the survivor lands
        -- via ctx.reserveReplace in its own writer's pass.
        --
        -- Henrik's craft-bench acceptance case (2026-07-27): the Royal Cloak
        -- no longer beats the Craft claim's Midras's Helm +1 -- the cloak's
        -- floor claim is INELIGIBLE against Craft's rank and falls down Idle's
        -- ladder, and a merely-WORN reserver defends nothing at all (worn
        -- pieces are not claims -- the Mindie ruling generalized; the server
        -- displaces a beaten worn reserver the moment the winner lands).
        do
            local entries = {};
            local floorRow = rankOf['Triggers'];
            -- A LOCK-VETOED CLAIM IS NO CLAIM AT ALL (Henrik's field case,
            -- 2026-07-27 late: locked EMPTY Head + worn Royal Cloak + a
            -- Movement rule claiming Head -- the verdict ruled the cloak
            -- ineligible against a Kabuto the lock then vetoed at the equip
            -- chain, so the cloak fell for a hat that never landed). A claim
            -- from a row that RESPECTS locks can never land in a locked slot,
            -- so it must not count in the verdict either: strip locked slots
            -- from those rows' entries (copy, never mutate -- the tables are
            -- the live sets/claims). Punch-through rows (above Locks) keep
            -- theirs: those claims WILL land. Zero cost with no locks set.
            local anyLk = (next(M.locks) ~= nil);
            local function minusLocked(set)
                if not anyLk then return set; end
                local out, changed = {}, false;
                for slot, v in pairs(set) do
                    if M.locks[string.lower(tostring(slot))] == true then
                        changed = true;
                    else
                        out[slot] = v;
                    end
                end
                if not changed then return set; end
                return out;
            end
            for _, r in ipairs(hits) do
                if r.sets ~= nil then
                    for _, sn in ipairs(r.sets) do
                        local st = (type(M._nativeSets) == 'table') and M._nativeSets[sn] or nil;
                        if type(st) == 'table' then
                            entries[#entries + 1] = { prio = r.prio, row = floorRow, set = minusLocked(st), src = sn };
                        end
                    end
                elseif r.equip ~= nil then
                    -- src nil on purpose: an inline equip is one candidate by
                    -- nature -- there is no ladder to fall down.
                    entries[#entries + 1] = { prio = r.prio, row = floorRow, set = minusLocked(r.equip) };
                end
            end
            -- The claims join in APPLY order (lowest rank first -- the
            -- reserveFloor law), so the merged winner per slot is the
            -- strongest writer: exactly what will be worn. Sentinel-valued
            -- claims (the plain-lock veto, the Disabled ceiling) are not merge
            -- candidates yet -- a reserver bulldozing a locked/free slot keeps
            -- today's behavior; that closure is a later slice. Claim pieces
            -- carry no ladder yet (src nil): an ineligible claim piece is
            -- killed exactly as v135 killed floor pieces; claim-side ladders
            -- (AutoAmmo's rungs, the hobby manifest chains) are stage 4's
            -- second slice.
            local CANON_OF = {};
            for ci, cs in ipairs(LAC_SLOTS) do CANON_OF[cs] = LAC_SLOTS_CANON[ci]; end
            for i = #arbOrder, 1, -1 do
                local cn = arbOrder[i];
                if claims[cn] ~= nil and cn ~= 'Triggers' then
                    -- Rows below Locks respect the veto, so their locked-slot
                    -- claims are dead and stripped here too; rows above punch
                    -- through and keep theirs (layerRespectsLocks, step 3).
                    local ctbl = claims[cn];
                    if layerRespectsLocks(cn) then ctbl = minusLocked(ctbl); end
                    -- Claim-side ladders (stage 4): a row with an rladder gets
                    -- a '\031'-prefixed src -- the control char cannot collide
                    -- with a user's set name -- so a beaten claim piece falls
                    -- down its own resolver chain exactly as a floor piece
                    -- falls down candidatesFor.
                    local crow = CLAIMANT_BY[cn];
                    entries[#entries + 1] = { prio = 0, row = rankOf[cn], set = ctbl,
                        src = (crow ~= nil and crow.rladder ~= nil) and ('\031' .. cn) or nil };
                end
                -- SENTINEL DEFENSE ROWS (stage 4, slice 2 -- the ratified
                -- "free consequence": a reserving piece can no longer
                -- bulldoze a locked or free-equip slot). The lock veto and
                -- the Disabled ceiling join the verdict as DEFENDERS:
                -- placeholder names that never equip (they exist only in
                -- this merge) and never reserve (no manifest entry -> mask
                -- 0), but STAND at their rows -- a reserver whose target is
                -- held here is beaten by rank and falls, exactly like any
                -- other lost contest. Appended in the same rank walk, so a
                -- claim ABOVE Locks still overwrites the placeholder in the
                -- merge: the punch-through law is untouched. Keys are
                -- canonicalized -- the floor merge is raw-key, and a
                -- lac-case 'head' next to a canonical 'Head' would split the
                -- slot in two.
                if cn == 'Locks' and next(M.locks) ~= nil then
                    -- A LOCKED SLOT ENTERS THE VERDICT AS THE PIECE IT FROZE
                    -- (Henrik's two same-evening field cases, 2026-07-27).
                    -- Not a '(locked)' placeholder: the WORN NAME, at the
                    -- Locks row -- because a lock-frozen piece is physical
                    -- reality in both directions. It DEFENDS its slot (a
                    -- reserver targeting it is beaten by Locks' rank and
                    -- falls -- the v142 case), and its own RESERVATIONS
                    -- COUNT as a dominant reserver (his locked-cloak case:
                    -- locking Body with the Royal Cloak worn froze the cloak
                    -- -- so Idle's Head piece must stay suppressed, not land
                    -- and have the server displace the very piece the lock
                    -- promised to keep). An EMPTY locked slot contributes
                    -- nothing (his first refinement: freezing "empty" is
                    -- exactly what a reservation preserves, so an outside
                    -- reserver may land). The ceiling below stays
                    -- UNCONDITIONAL on purpose: free equip promises the
                    -- FUTURE hand-equip stays, empty or not.
                    local held = nil;
                    for ls in pairs(M.locks) do
                        local canon = CANON_OF[ls] or ls;
                        local wn = wornItemName(canon);
                        if wn ~= nil then
                            held = held or {};
                            held[canon] = wn;
                        end
                    end
                    if held ~= nil then
                        entries[#entries + 1] = { prio = 0, row = rankOf[cn], set = held };
                    end
                elseif cn == 'Disabled' then
                    local dz = M.disabledList();
                    if #dz > 0 then
                        local free = {};
                        for _, ls in ipairs(dz) do free[CANON_OF[ls] or ls] = '(free equip)'; end
                        entries[#entries + 1] = { prio = 0, row = rankOf[cn], set = free };
                    end
                end
            end
            -- THE RECEIPT (2026-08-01). vLadderOf is the ONE door every ladder
            -- passes through on its way to the arbiter -- floor sets one side,
            -- claimant rladders the other -- so noting each one down HERE
            -- captures all of them without this code ever having to know who
            -- the suppliers are.
            --
            -- It replaces a re-derivation: recordDecision used to rebuild the
            -- rung list AFTERWARDS from contest.src, which only the trigger
            -- floor writes -- so a Craft/HELM/Fishing/Chocobo fall had no rungs
            -- to show at all, and even the floor's own list was asked a second
            -- time, later, and could answer differently (a bag moved, the level
            -- changed) than the list the decision was actually made from. The
            -- ladder that decided is the ladder you read -- the same law the
            -- trace already runs on.
            --
            -- Free by construction: only ladders the fall ALREADY fetched are
            -- recorded. Nothing is fetched to fill this in -- the arbiter asks
            -- for a ladder only when it has to refuse something, and that
            -- laziness is why a quiet dispatch costs nothing. Slots that never
            -- needed one keep the append-time derivation as their fallback.
            local asked = {};
            local function vLadderOf(src, slot)
                local lad, label = nil, tostring(src);
                local cn2 = string.match(tostring(src), '^\031(.+)$');
                if cn2 ~= nil then
                    -- A claimant is named to a human here (GM naming ruling):
                    -- identity in, label out, through the one map.
                    label = ARB.claimantLabel(cn2);
                    local r2 = CLAIMANT_BY[cn2];
                    if r2 ~= nil and r2.rladder ~= nil then
                        local ok2, got = pcall(r2.rladder, slot, cState[cn2], ctx);
                        if ok2 then lad = got; end
                    end
                else
                    lad = M.candidatesFor(src, slot);
                end
                if type(lad) == 'table' and type(lad.items) == 'table' then
                    local names = {};
                    for _, r in ipairs(lad.items) do
                        if type(r) == 'table' and type(r.name) == 'string' then
                            names[#names + 1] = r.name;
                        end
                    end
                    if names[1] ~= nil then asked[slot] = { set = label, items = names }; end
                end
                return lad;
            end
            -- The Range/Ammo PAIR arrives here too (v159): the arbiter judges
            -- the merged floor, and the trinket-vs-ranged pass below stops
            -- deciding and starts applying. levelOf / pairOf are the same two
            -- readers the per-table law already used -- threaded in rather than
            -- re-derived, so there is still exactly ONE Level rule and ONE pair
            -- rule in the addon. A LOCKED Ammo slot passes wornAmmo = nil: the
            -- lock is the user's explicit word, and the old pass guarded the
            -- displace on it in exactly this spot.
            local wAmmo = nil;
            if M.locks['ammo'] ~= true then wAmmo = wornItemName('Ammo'); end
            ctx.reserveSuppressed, ctx.reserveIneligible, ctx.reserveReplace,
            ctx.reserveFall, ctx.reservePair =
                M.reserveResolve(entries, rslotOf, vLadderOf, haveEquippable,
                                 { level = levelOf, pair = pairOf, wornAmmo = wAmmo });
            ctx.reserveAsked = (next(asked) ~= nil) and asked or nil;
            -- The flag the equip chain keys the one-authority rule on: while
            -- it is set, NO dispatch pass (floor or claim) runs the
            -- single-set + worn fallback -- this verdict already judged
            -- everything, claim tables included.
            ctx.reserveGlobal = true;
        end

        for hi, r in ipairs(hits) do
            -- The winning case, named for /dl why (issue #125): '[via <case>]'
            -- rides right after the rule label. A case-less rule has no `|` leg,
            -- so mc is nil and the line reads exactly as before.
            local mc = hitCase[hi];
            local via = mc and (' [via ' .. mc .. ']') or '';
            if r.sets ~= nil then
                -- A rule may wear SEVERAL sets: applied IN ORDER, later overlaying
                -- earlier per slot -- the same law as between rules ("cast Madrigal
                -- -> the WindSkill base, then the Madrigal overlay on top").
                for si, sn in ipairs(r.sets) do
                    local found, note, tbl = equipSetByName(sn, ctx);
                    if retrace then
                        lines[#lines + 1] = string.format('%s%s  ->  set %s%s  (prio %d)%s%s',
                            r.label, via, sn, (#r.sets > 1) and string.format(' [%d/%d]', si, #r.sets) or '',
                            r.prio, found and '' or '  [NOT FOUND in profile Sets]', note or '');
                    end
                    -- attribution: every pass (see the slotSrc/floorTbl note)
                    if type(tbl) == 'table' then
                        for slot, item in pairs(tbl) do
                            if string.sub(tostring(slot), 1, 2) ~= '__' then
                                slotSrc[slot] = sn; floorTbl[slot] = item;
                            end
                        end
                    end
                end
            elseif r.equip ~= nil then
                local note, tbl = equipResolved(r.equip, ctx);
                if retrace then
                    lines[#lines + 1] = string.format('%s%s  ->  equip { %s }  (prio %d)%s',
                        r.label, via, inlineSummary(r.equip), r.prio, note or '');
                end
                if type(tbl) == 'table' then
                    for slot, item in pairs(tbl) do
                        if string.sub(tostring(slot), 1, 2) ~= '__' then
                            slotSrc[slot] = r.label; floorTbl[slot] = item;
                        end
                    end
                end
            end
        end
        -- (Stage 4: the verdict no longer retires here -- it is the ONE
        --  reservation authority and rides through the claim applies below,
        --  clearing after the arbitration's plan has been executed.)

        -- Apply every Claim in RANK order (ADR 0012). Overlay last-writer-wins,
        -- so higher rank must be applied LAST -- the loop walks the rank order
        -- LOW to HIGH (reverse), each active claimant overwriting the ones
        -- below it, above the Trigger floor already applied. This one loop
        -- replaces the old hardcoded craft > HELM > fish > AutoAmmo > pin
        -- sequence; MaxMP applies here too since the FOLD (stage 6) -- its
        -- batteries are a row like any other. Locks are the VETO ROW (step 3):
        -- each claim layer is told whether to respect the lock (rank below Locks)
        -- or punch through it (above) via layerRespectsLocks -- no discrete Locks
        -- overlay here. Each claimant keeps its own trace line for /dl why.
        -- (ADR 0027 stage 0: the apply bodies live on the CLAIMANTS rows; this
        -- walk just calls them in rank order.)
        local aenv = { built = built, bx = bx, ctx = ctx, retrace = retrace,
                       lines = lines, respect = layerRespectsLocks, rankOf = rankOf };
        -- THE ARBITRATION (ADR 0027, stage 3, first slice): the apply order is
        -- the arbiter's answer, not an inline walk -- M.dispatch executes the
        -- plan. Later slices grow the plan into per-slot contests + the trace;
        -- stage 4 hands it the ladders.
        local plan = ARB.arbitrate({ order = arbOrder, claims = claims });
        for _, name in ipairs(plan.applies) do
            local row = CLAIMANT_BY[name];
            if row ~= nil and row.apply ~= nil then row.apply(aenv); end
        end
        -- The dispatch's verdict retires HERE (stage 4): it was the one
        -- reservation authority for the floor AND every claim pass above.
        -- Captured into locals first: /dl why <slot> (ADR 0027 item 4)
        -- renders the contest from what actually decided.
        local vSup, vInel, vRep = ctx.reserveSuppressed, ctx.reserveIneligible, ctx.reserveReplace;
        local vFall, vAsked, vPair = ctx.reserveFall, ctx.reserveAsked, ctx.reservePair;
        ctx.reserveSuppressed, ctx.reserveIneligible, ctx.reserveReplace = nil, nil, nil;
        ctx.reserveFall, ctx.reserveAsked, ctx.reservePair = nil, nil, nil;
        ctx.reserveGlobal = nil;
        -- The DECISION RING's plan snapshot (v152): the arbitration's answer as
        -- display names, taken BEFORE the send retires ctx.planOut. The plan is
        -- the only correct source at decision time -- worn memory still shows
        -- the PREVIOUS composition here (the integration design's ordering trap).
        local planSnap = planNames(ctx.planOut);
        -- THE ONE SEND: the whole dispatch leaves as a single set.
        if next(ctx.planOut) ~= nil then engineEquipSet(ctx.planOut); end
        ctx.planOut = nil;

        if retrace and #hits > 1 then                    -- who won each slot (overlap visibility)
            local parts = {};
            for slot, src in pairs(slotSrc) do parts[#parts + 1] = tostring(slot) .. '<-' .. tostring(src); end
            if #parts > 0 then
                table.sort(parts);
                lines[#lines + 1] = 'slots: ' .. table.concat(parts, ', ');
            end
        end

        -- Per-slot CLAIMANT attribution (ADR 0012, step 4). Run the Arbiter's pure
        -- resolve over the SAME claims + rank + floor the live overlay just applied
        -- and name every contested slot's winner + rank in /dl why -- veto slots
        -- read 'stopped by Locks', floor-only slots read 'Triggers (floor)'. The
        -- registry is the single precedence authority, so the resolve that decides
        -- also explains; the order-pinning tests (AR*/LV*) drive the same seam.
        -- Locks join here as the veto claim (M.locks -> arbLockClaim); the live
        -- equip already honoured them via layerRespectsLocks.
        -- A RECORD'S CONTEST MUST EXPLAIN THAT RECORD'S PLAN (field report 3,
        -- 2026-08-02). The contest was rebuilt only on a retrace and reused
        -- from the previous trace otherwise -- so a Default dispatch whose
        -- PLAN moved while the trace signature held carried the OLDER plan's
        -- explanation into a new ring record. Henrik's report showed both
        -- halves of that: Ear1 sat in the plan with the contest naming nobody
        -- for the slot (a piece that became eligible on a level-up), and the
        -- claimant then appeared two dispatches later as a record with zero
        -- changed slots. Re-explained below when the plan outruns it.
        local whyClaims = nil;
        local function claimsView()
            if whyClaims ~= nil then return whyClaims; end
            whyClaims = {};
            for k, v in pairs(claims) do whyClaims[k] = v; end
            -- The Locks ROW carries two kinds of opinion since ADR 0022: real
            -- item names from a locked set, and the LOCK_HELD veto sentinel for
            -- slots a plain /dl lock froze. MERGE rather than assign -- assigning
            -- would erase whichever of the two /dl why was asked about second.
            -- The held entries go in first and keep their proper case (which is
            -- what arbExplain prefers for display); a sentinel is added only for
            -- a slot the hold does not already name.
            local lockClaim = M.arbLockClaim(M.locks);
            if next(lockClaim) ~= nil or whyClaims['Locks'] ~= nil then
                local merged, seenLower = {}, {};
                for slot, v in pairs(whyClaims['Locks'] or {}) do
                    merged[slot] = v;
                    seenLower[string.lower(tostring(slot))] = true;
                end
                for slot, v in pairs(lockClaim) do
                    if not seenLower[string.lower(tostring(slot))] then merged[slot] = v; end
                end
                whyClaims['Locks'] = merged;
            end
            return whyClaims;
        end
        -- The STRUCTURED contest, stashed for /dl why <slot> (ADR 0027 item 4,
        -- ratified): the same explain that attributed, the verdict's word on
        -- each slot (fell / ineligible / held empty) and each slot's source
        -- set -- depth on demand, rendered later from what actually decided,
        -- never re-decided.
        local function buildContest()
            return { explain = M.arbExplain(claimsView(), arbOrder, floorTbl),
                     order = arbOrder, sup = vSup, inel = vInel, rep = vRep,
                     fall = vFall, asked = vAsked, pair = vPair,
                     src = slotSrc };
        end

        local contest = (not retrace and old ~= nil) and old.contest or nil;
        if retrace then
            local why = M.arbWhyLines(claimsView(), arbOrder, floorTbl);
            if #why > 0 then
                lines[#lines + 1] = 'claimants (rank order, highest wins):';
                for _, wl in ipairs(why) do lines[#lines + 1] = '  ' .. wl; end
            end
            contest = buildContest();
        elseif M._planOutrunsContest(planSnap, contest) then
            -- The plan named a slot this explanation cannot account for, so
            -- the explanation is out of date rather than merely terse.
            -- Re-explaining costs one arbExplain on the rare pass where it
            -- happens, and buys a record whose two halves agree.
            contest = buildContest();
        end

        _trace[event] = { time = os.date('%H:%M:%S'), action = actionLabel(ctx), sig = sig,
                          lines = lines, contest = contest };
        -- The DECISION RING (v152): append only when the outcome moved. The
        -- action feed (v154) stubs every non-Default dispatch either way --
        -- the stream's anchor for actions that changed nothing.
        local decSeq = recordDecision(event, ctx, planSnap, contest);
        recordAction(event, ctx, decSeq);
    end);
end

-- Trace access for /dl why and (later) the GUI "Explain last action" view.
function M.getTrace() return _trace; end

-- The decision ring, read-only: the Arbiter Monitor's feed (and later the
-- integration stream's). Newest LAST; records are never mutated after append.
function M.getDecisions() return _decisions; end

-- ---------------------------------------------------------------------------
-- Trigger file read/write for the GUI (the format lives HERE, next to the parser).
-- The GUI edits a plain rule table and serializeTriggers turns it back into the
-- canonical file text; readTriggersRaw hands the GUI the current file's table.
-- ---------------------------------------------------------------------------

-- Raw (un-normalized) rule table from a trigger file path: table | nil, err.
function M.readTriggersRaw(path)
    if path == nil then return nil, 'no path'; end
    local raw = readFile(path);
    if raw == nil then return nil, 'no file'; end
    local chunk, cerr = (loadstring or load)(raw, '@' .. path);
    if chunk == nil then return nil, 'does not parse: ' .. tostring(cerr); end
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' then
        return nil, 'did not return a table' .. (ok and '' or (': ' .. tostring(t)));
    end
    return t;
end

local function luaValue(v)
    if type(v) == 'string' then return string.format('%q', v); end
    return tostring(v);
end

-- A condition value may be a single scalar OR a LIST (OR): `mode` and `group`
-- both accept `{ 'A', 'B' }`. Serialize a list as `{ "A", "B" }` (order kept),
-- so list conditions round-trip instead of stringifying to a table address.
local function condLiteral(v)
    if type(v) ~= 'table' then return luaValue(v); end
    local q = {};
    for _, x in ipairs(v) do q[#q + 1] = luaValue(x); end
    return '{ ' .. table.concat(q, ', ') .. ' }';
end

-- One condition map -> a sorted "prettyKey = literal" list. Skips the cases
-- guard ALWAYS (it is re-stamped by the caller, never doubled). Shared by every
-- leg the trigger serializer emits (body, whenAny entries, cases). Mirrored in
-- blueprintsmodel.emitRule -- the two are a parity-pinned pair (issue #126).
local function serCondList(map)
    local c = {};
    for k, v in pairs(map or {}) do
        local lk = string.lower(tostring(k));
        if lk ~= CASES_GUARD then
            c[#c + 1] = (PRETTY_KEY[lk] or tostring(k)) .. ' = ' .. condLiteral(v);
        end
    end
    table.sort(c);
    return c;
end

-- The canonical `whenAny`/`cases` split for a rule (issue #126, "oldest-form-
-- first"): a `| case` whose ONLY content is `&` conditions serializes as a plain
-- multi-condition `whenAny` entry -- the EXISTING schema, so every addon version
-- ever shipped evaluates it. Only `&` cases and `| cases` with an internal `|`
-- leg use the new `cases` list. Returns (anyEntries, caseList): anyEntries are
-- condition MAPS (the body's whenAny + downgraded | cases); caseList are the
-- surviving { op, when, whenAny } cases. Mirrored in blueprintsmodel.
local function splitCases(r)
    local anyEntries = {};
    for _, e in ipairs(r.whenAny or {}) do anyEntries[#anyEntries + 1] = e; end
    local caseList = {};
    for _, c in ipairs(r.cases or {}) do
        if type(c) == 'table' then
            if c.op == '|' and (c.whenAny == nil or #c.whenAny == 0) then
                anyEntries[#anyEntries + 1] = c.when or {};
            else
                caseList[#caseList + 1] = c;
            end
        end
    end
    return anyEntries, caseList;
end

-- data = { [Handler] = { { when = {k=v}, set='X' | equip={Slot='Item'}, priority=n? }, ... } }
-- Handlers emit in canonical order; conditions in sorted display-case spelling.
-- Deterministic output -> clean diffs; comments are NOT preserved (GUI-owned file).
function M.serializeTriggers(data)
    local L = {
        '-- dlac triggers -- written by the dlac GUI (Triggers tab); safe to hand-edit,',
        '-- but the GUI rewrites this file on Commit (comments are not preserved).',
        '-- Hot-reloaded: changes apply on the next action, no /lac reload needed.',
        '-- Format & conditions: docs/design/trigger-system.md in the dlac addon.',
        'return {',
    };
    for _, ev in ipairs(EVENTS) do
        local list = (type(data) == 'table') and data[ev] or nil;
        if type(list) == 'table' and #list > 0 then
            L[#L + 1] = '    ' .. ev .. ' = {';
            for _, r in ipairs(list) do
                -- Cases (issue #126): a `| case` with only `&` conditions folds
                -- back into the whenAny leg (oldest form); `&` cases and `| cases`
                -- with internal `|` stay in the cases list. A non-empty cases list
                -- means the rule gets the version guard stamped in its body.
                local anyEntries, caseList = splitCases(r);
                local conds = serCondList(r.when);
                if #caseList > 0 then conds[#conds + 1] = (PRETTY_KEY[CASES_GUARD] or 'hasCases') .. ' = true'; end
                table.sort(conds);
                -- v54 OR group: entry order preserved as authored (a list, not a
                -- map), each entry's own conditions sorted like `when`.
                local anyStr = '';
                if #anyEntries > 0 then
                    local groups = {};
                    for _, entry in ipairs(anyEntries) do
                        groups[#groups + 1] = '{ ' .. table.concat(serCondList(entry), ', ') .. ' }';
                    end
                    anyStr = ', whenAny = { ' .. table.concat(groups, ', ') .. ' }';
                end
                -- cases list: each { op = "&"/"|", when = {...}, whenAny = {...}? }
                local casesStr = '';
                if #caseList > 0 then
                    local cs = {};
                    for _, c in ipairs(caseList) do
                        local cAny = '';
                        if type(c.whenAny) == 'table' and #c.whenAny > 0 then
                            local g = {};
                            for _, e in ipairs(c.whenAny) do
                                g[#g + 1] = '{ ' .. table.concat(serCondList(e), ', ') .. ' }';
                            end
                            cAny = ', whenAny = { ' .. table.concat(g, ', ') .. ' }';
                        end
                        cs[#cs + 1] = string.format('{ op = %q, when = { %s }%s }',
                            tostring(c.op), table.concat(serCondList(c.when), ', '), cAny);
                    end
                    casesStr = ', cases = { ' .. table.concat(cs, ', ') .. ' }';
                end
                local action;
                if type(r.set) == 'table' then          -- ordered multi-set rule
                    local q = {};
                    for _, sn in ipairs(r.set) do q[#q + 1] = luaValue(tostring(sn)); end
                    action = 'set = { ' .. table.concat(q, ', ') .. ' }';
                elseif r.set ~= nil then
                    action = 'set = ' .. luaValue(tostring(r.set));
                else
                    local slots = {};
                    for slot, item in pairs(r.equip or {}) do
                        slots[#slots + 1] = tostring(slot) .. ' = ' .. luaValue(tostring(item));
                    end
                    table.sort(slots);
                    action = 'equip = { ' .. table.concat(slots, ', ') .. ' }';
                end
                local prio = (tonumber(r.priority) ~= nil) and (', priority = ' .. tostring(r.priority)) or '';
                L[#L + 1] = string.format('        { when = { %s }%s%s, %s%s },',
                    table.concat(conds, ', '), anyStr, casesStr, action, prio);
            end
            L[#L + 1] = '    },';
        end
    end
    -- Modes section (cycle definitions + keybinds) -- carried through serialization so
    -- a Commit never wipes it (sibling of the handler sections, like the rules).
    local md = (type(data) == 'table') and (data.Modes or data.modes) or nil;
    if type(md) == 'table' then
        local names = {};
        for nm, def in pairs(md) do
            if type(nm) == 'string' and type(def) == 'table' then names[#names + 1] = nm; end
        end
        table.sort(names);
        if #names > 0 then
            L[#L + 1] = '    Modes = {';
            for _, nm in ipairs(names) do
                local def = md[nm];
                local bits = {};
                local src = (type(def.values) == 'table') and def.values or def;
                local vals = {};
                for _, v in ipairs(src) do
                    if type(v) == 'string' then vals[#vals + 1] = string.format('%q', v); end
                end
                if #vals > 0 then bits[#bits + 1] = 'values = { ' .. table.concat(vals, ', ') .. ' }'; end
                if type(def.bind) == 'string' then bits[#bits + 1] = string.format('bind = %q', def.bind); end
                if #bits > 0 then
                    L[#L + 1] = string.format('        [%q] = { %s },', nm, table.concat(bits, ', '));
                else
                    -- a bare toggle (no bind, no values) is still a definition:
                    -- dropping it made a plain UI-created toggle vanish from
                    -- the Modes list on the next load (2026-07-20)
                    L[#L + 1] = string.format('        [%q] = {},', nm);
                end
            end
            L[#L + 1] = '    },';
        end
    end
    -- Groups section (ADR 0009) -- carried through serialization so a Commit
    -- never wipes it (sibling of the handler sections, like Modes). Group names
    -- sorted for a stable diff; member order preserved as the player authored it.
    local gr = (type(data) == 'table') and (data.Groups or data.groups) or nil;
    if type(gr) == 'table' then
        local names = {};
        for nm, mem in pairs(gr) do
            if type(nm) == 'string' and type(mem) == 'table' then names[#names + 1] = nm; end
        end
        table.sort(names);
        if #names > 0 then
            L[#L + 1] = '    Groups = {';
            for _, nm in ipairs(names) do
                local q = {};
                for _, a in ipairs(gr[nm]) do
                    if type(a) == 'string' then q[#q + 1] = string.format('%q', a); end
                end
                L[#L + 1] = string.format('        [%q] = { %s },', nm, table.concat(q, ', '));
            end
            L[#L + 1] = '    },';
        end
    end
    L[#L + 1] = '};';
    L[#L + 1] = '';
    return table.concat(L, '\n');
end

-- ---------------------------------------------------------------------------
-- Mode state, DLAC-OWNED. modestate.lua is written on every change (the GUI --
-- a different Lua state -- reads it for display) and read BACK by
-- loadModeState when the engine loads, so a Reload LAC no longer silently
-- wipes flags a dlac reload would have kept. Slot locks stay session-only
-- (mirrored for display, never restored -- a lock is a "right now" decision).
-- ---------------------------------------------------------------------------
saveModeState = function()
    M.modesRev = (M.modesRev or 0) + 1;   -- BEFORE the guarded write: the rebuild
                                          -- signal must fire even if the mirror can't
    pcall(function()
        local dir = charDir();
        if dir == nil then return; end
        local parts = { string.format('["__version"] = %d,', M.VERSION) };   -- engine handshake
        pcall(function()   -- which job these flags belong to: another job never inherits them
            parts[#parts + 1] = string.format('["__job"] = %d,',
                AshitaCore:GetMemoryManager():GetPlayer():GetMainJob() or 0);
        end);
        parts[#parts + 1] = string.format('["__at"] = %d,', os.time());   -- freshness (restore window)
        parts[#parts + 1] = string.format('["__loadstamp"] = %q,', tostring(M._loadStamp));   -- LAC-load generation
        local lk = {};
        for s in pairs(M.locks) do lk[#lk + 1] = string.format('[%q] = true,', s); end
        table.sort(lk);
        parts[#parts + 1] = '["__locks"] = { ' .. table.concat(lk, ' ') .. ' },';   -- slot locks
        -- Disabled slots (ADR 0024), display only on the same __ contract. The
        -- Equipped tab's Free equip switch and the Priority panel's ceiling row
        -- both read it; loadModeState skips the __ namespace, so it can never be
        -- restored from disk -- logging in with three slots silently inert is
        -- this feature's version of ADR 0021's worst outcome.
        local dz = {};
        for _, s in ipairs(M.disabledList()) do dz[#dz + 1] = string.format('[%q] = true,', s); end
        parts[#parts + 1] = '["__disabled"] = { ' .. table.concat(dz, ' ') .. ' },';
        parts[#parts + 1] = string.format('["__naked"] = %s,', tostring(M.nakedArmed == true));   -- the strip (ADR 0021), display only
        -- The locked set (ADR 0022), display only on the same __ contract. The
        -- Equipped tab owns the state readout; the Sets tab's Equip & Lock button
        -- reads it too, because there is no longer any lock COUNT for it to test
        -- (it used to flip to Unlock at 16 locked slots -- nothing locks 16 now).
        if M.lockedSetOn() then
            parts[#parts + 1] = string.format('["__held"] = { name = %q, mode = %q, n = %d },',
                tostring(M.lockedSetLabel()), tostring(M.lockedSet.mode), tonumber(M.lockedSet.n) or 0);
        end
        for m, v in pairs(M.modes) do
            if v == true then parts[#parts + 1] = string.format('[%q] = true,', m);
            elseif type(v) == 'string' then parts[#parts + 1] = string.format('[%q] = %q,', m, v); end
        end
        table.sort(parts);
        writeFile(dir .. 'modestate.lua',
            '-- dlac mode state (dlac-owned; read back on engine load, GUI reads for display)\nreturn { '
            .. table.concat(parts, ' ') .. ' }\n');
    end);
end

-- Trigger-monitor mirror (v55): display-only, never read back by the engine.
-- Its own small file, NOT modestate -- fired lines change per action and must
-- not bump modesRev (the GUI mode-button rebuild signal) or ride the restore
-- path.
saveFiredState = function()
    pcall(function()
        local dir = charDir();
        if dir == nil then return; end
        local q = {};
        for _, s in ipairs(_fired) do q[#q + 1] = string.format('%q,', s); end
        writeFile(dir .. 'firedstate.lua',
            '-- dlac fired-trigger mirror (GUI display only)\nreturn { '
            .. table.concat(q, ' ') .. ' }\n');
    end);
end

local function loadModeState()
    pcall(function()
        local dir = charDir();
        if dir == nil then return; end
        local chunk = loadfile(dir .. 'modestate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if not ok or type(t) ~= 'table' then return; end
        -- Flags are restored only for the job that set them (the __job stamp) and
        -- only when RECENT (an hour) -- healing a mid-session Reload LAC without
        -- resurrecting last Tuesday's DT-mode at login. Anything else starts clean.
        local jid = nil;
        pcall(function() jid = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
        if type(t.__job) ~= 'number' or jid == nil or jid == 0 or t.__job ~= jid then return; end
        if type(t.__at) ~= 'number' or os.time() - t.__at > 3600 then return; end
        for k, v in pairs(t) do
            local ks = tostring(k);
            if string.sub(ks, 1, 2) ~= '__' and (v == true or type(v) == 'string') then
                M.modes[string.lower(ks)] = v;   -- cycle values re-validate on trigger load
            end
        end
    end);
end

-- Toggle modes flip true/off. CYCLE modes (defined in the trigger file's Modes section)
-- always hold one of their values: no arg -> advance to the next value (wrapping);
-- a string arg -> jump straight to that value (case-insensitive). Returns the new state.
function M.setMode(name, state)
    if type(name) ~= 'string' or name == '' then return false; end
    local ln = string.lower(name);
    local def = _trig.modeDefs and _trig.modeDefs[ln] or nil;
    if def ~= nil and def.values ~= nil then
        local cur, curIdx = M.modes[ln], 0;
        for i, v in ipairs(def.values) do
            if type(cur) == 'string' and ci(v, cur) then curIdx = i; break; end
        end
        if type(state) == 'string' then                -- jump to a named value
            for _, v in ipairs(def.values) do
                if ci(v, state) then M.modes[ln] = v; saveModeState(); return v; end
            end
            return M.modes[ln];                        -- unknown value: unchanged
        end
        local nxt = def.values[(curIdx % #def.values) + 1];
        M.modes[ln] = nxt;
        saveModeState();
        return nxt;
    end
    -- No LOCAL definition below here (definitions are per-job trigger data;
    -- VALUES are session-global). An explicit value jump works from any job --
    -- the command layer already peeled off on/off/toggle, so a string is
    -- always an intended cycle value: trust it.
    if type(state) == 'string' then
        M.modes[ln] = state;
        saveModeState();
        return state;
    end
    -- And a bare flip must not toggle-corrupt a cycle VALUE defined elsewhere
    -- into a boolean (field case: ^F6 "WHM Weapons" -- defined in BRD's
    -- triggers -- pressed on WHM would kill every WHM set gated on it).
    if state == nil and type(M.modes[ln]) == 'string' then
        print(string.format('[dlac] mode "%s" holds cycle value "%s" but THIS job\'s triggers don\'t define the cycle -- jump directly (/dl mode %s <value>), define it here (Triggers > Modes), or /dl mode %s off.',
            name, M.modes[ln], name, name));
        return M.modes[ln];
    end
    if state == nil then state = not (M.modes[ln] == true); end   -- toggle
    M.modes[ln] = (state == true) or nil;
    saveModeState();
    return M.modes[ln] == true;
end

function M.activeModes()
    local out = {};
    for m, v in pairs(M.modes) do
        out[#out + 1] = (v == true) and m or (m .. '=' .. tostring(v));
    end
    table.sort(out);
    return out;
end

-- ---------------------------------------------------------------------------
-- Starter trigger file (also written by the GUI Setup button via M.starterTriggersText).
-- Mirrors the classic HandleDefault branching so a fresh profile behaves out of the box.
-- ---------------------------------------------------------------------------
M.starterTriggersText = [[
-- dlac triggers -- written by dlac (Setup / the Triggers tab); safe to hand-edit.
-- Hot-reloaded: edits apply on the next action. No /lac reload needed.
--
-- Shape:  <Handler> = { { when = { <conditions> }, set = 'SetName', priority = n }, ... }
--         action is  set = 'Name'  (a set in your <JOB>.lua)  or  equip = { Waist = 'Karin Obi' }.
-- Handlers:   Default, Precast, Midcast, Ability, Item, Weaponskill, Preshot, Midshot,
--             PetAction (fires when YOUR PET starts an action -- Blood Pact / Ready move /
--             pet spell; your gear holds until it completes. dlac provides this event itself).
-- Conditions: status/moving/mode | pet (true/false), petStatus, petName (YOUR pet: a dead
--             pet counts as NO pet; petStatus/petName never match petless -- so
--             status = 'Idle' + petStatus = 'Engaged' is "master idle, pet fighting")
--             | any/skill/magicType/element/songType/family/name
--             | environment, three DIFFERENT tests: dayWeatherBonus (the obi's signed
--             day+weather net, with the opposing element as a minus), weatherMatch (the
--             spell's element == the CURRENT weather element -- your own storm counts),
--             dayMatch (the spell's element == TODAY's day element -- no weather)
--             | abilityType | target ('Self': the action is aimed at YOU -- a self-waltz
--             can wear VIT+CHR while waltzing someone else keeps the plain CHR set)
--             | player state: playerHPBelow/Above, playerHPPercentBelow/Above,
--             playerMPBelow/Above, playerMPPercentBelow/Above, tpBelow/tpAbove (raw TP),
--             buff/buffNot (active status effect, name or id).
--             All conditions in one `when` must hold; every matching rule
--             applies, lowest priority first (later overlays earlier per slot).
-- OR groups:  whenAny = { { buff = "Sleep" }, { buff = "Lullaby" } } -- the rule matches
--             when ALL `when` conditions hold OR ANY whenAny entry holds.
-- Priority defaults by specificity: any 10 < status/skill 20 < pet 22/petStatus 23 < moving 25
--             < class/element 30 < family 40 < exact name/petName 50 < target 55
--             < player state 95 < mode 100.  See docs/design/trigger-system.md.
return {
    Default = {
        { when = { status = 'Engaged' }, set = 'Tp_Default' },
        { when = { status = 'Resting' }, set = 'Resting' },
        { when = { moving = true },      set = 'Movement' },
        { when = { status = 'Idle' },    set = 'Idle' },
    },
};
]];

-- Write the starter file for the current job if none exists. Returns ok, message.
function M.initTriggers()
    local dir = charDir();
    local path = triggersPath();
    if dir == nil or path == nil then return false, 'not logged in (no character/job).'; end
    if readFile(path) ~= nil then return false, 'already exists: ' .. path; end
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory(dir .. 'triggers\\');
        end
    end);
    if _pok and _prof.storageExists() then pcall(function() _prof.ensureStorage(); end); end
    if not writeFile(path, M.starterTriggersText) then return false, 'could not write ' .. path; end
    M.reloadTriggers();
    return true, 'wrote starter triggers: ' .. path;
end

-- Re-read the current job's <JOB>.lua SANDBOXED and return its `sets` table --
-- the '/dl sets reload' hot-swap's reader. The sandbox is profilesets.lua's
-- field-proven trick, hardened for THIS Lua state: here the real gFunc/gState/
-- AshitaCore exist, so they (and other side-effect globals) are explicitly
-- stubbed -- re-running the profile must not equip, bind, queue or print.
-- Gear refs resolve through the real require, so the fresh entries point into
-- the same gear tables the old ones did.
-- The sets source: the active profile's sets\<JOB>.lua, the only source
-- (purge Phase 2 -- the legacy job-file sandbox reader died; old <JOB>.lua
-- files are the GUI importers' territory, and setmanager imports a job
-- file's whole Dynamic block when the profile file is first created).
-- Third return names the source for chat lines.
local function readSetsSource()
    if not _pok then return nil, 'profiles.lua unavailable'; end
    local job = nil;
    pcall(function() job = gData.GetPlayer().MainJob; end);
    if type(job) ~= 'string' or job == '' or job == '?' then return nil, 'job unknown'; end
    if not _prof.hasSetsFile(job) then
        return nil, 'no profile sets file for ' .. job .. ' yet (build sets in the Sets tab)';
    end
    local dyn, derr = _prof.readSetsFile(job);
    if dyn == nil then return nil, derr; end
    return { Dynamic = dyn }, nil, 'profile';
end

-- Install a fresh Sets table into the live gProfile -- the '/dl sets reload'
-- hot-swap core, shared with the profile auto-install and '/dl profile use':
-- kill flattened outputs of dynamic sets that no longer exist, swap .Dynamic in
-- place (gProfile.Sets is a live table in THIS state -- no LAC reload needed),
-- re-flatten, re-dispatch Default. Returns true, setCount | false, why.
local function installSets(fresh)
    do
        -- The module-level store (v111). Flow: drop dead flattened names,
        -- swap Dynamic, re-flatten, re-dispatch. (The gProfile twin died in
        -- the purge, Phase 2.)
        if nativeEngine() ~= nil then
            local store = (type(M._nativeSets) == 'table') and M._nativeSets or { Dynamic = {} };
            if type(store.Dynamic) == 'table' then
                for name in pairs(store.Dynamic) do
                    if fresh.Dynamic[name] == nil then store[name] = nil; end
                end
            end
            store.Dynamic = fresh.Dynamic;
            M.modesRev = (M.modesRev or 0) + 1;
            pcall(function()
                local u = utilsModule();
                if u ~= nil and type(u.rebuildSets) == 'function' then store = u.rebuildSets(store) or store; end
            end);
            -- A HOLLOW INSTALL IS NOT AN INSTALL (v118, warm-trace line 16:
            -- 'BELIEVED setN=0 flat=0' behind a '20 set(s) installed' print).
            -- If the raw Dynamic carries real entries but the flatten yielded
            -- ZERO sets, the world it flattened against was not settled (the
            -- fresh utils state's first level read) -- refuse, leave the store
            -- absent so readiness keeps failing, and let the latch retry next
            -- tick. Genuinely empty profiles (starter sets, no entries) pass:
            -- their zero flats are the truth, not a symptom.
            local rawEntries, flats = 0, 0;
            for _, set in pairs(fresh.Dynamic) do
                if type(set) == 'table' and next(set) ~= nil then rawEntries = rawEntries + 1; end
            end
            for k, v in pairs(store) do
                if k ~= 'Dynamic' and type(v) == 'table' then flats = flats + 1; end
            end
            if rawEntries > 0 and flats == 0 then
                M._nativeSets = nil;
                if type(M._mpWarmNote) == 'function' then
                    M._mpWarmNote(string.format('install REFUSED: %d raw set(s) flattened to none (world not settled) -- retrying', rawEntries));
                end
                return false, 'flatten produced no sets (world not settled)';
            end
            M._nativeSets = store;
            -- THE INSTALL INVALIDATES THE BELIEF (v118): the sets world just
            -- changed identity -- any LOW-map belief earned against the old
            -- (or absent) world dies with it; the 2s agreement re-earns
            -- against THIS world.
            _mpLow.at, _mpLow.sig, _mpLow.sigAt = 0, nil, nil;
            pcall(function() M.dispatch('Default'); end);
            local n = 0;
            for _ in pairs(fresh.Dynamic) do n = n + 1; end
            return true, n;
        end
        return false, 'engine not armed (tripwire?)';
    end
end

-- (warnShadowedStatics died in the purge, Phase 2: it compared the incoming
-- Dynamic against gProfile's file-authored statics, and there is no loaded
-- job-file profile anymore -- statics live in old files the importers read.)

-- ---------------------------------------------------------------------------
-- Commands: /dl mode | why | triggers | sets reload   (registered in the LAC
-- state only, where the mode flags and traces live; the addon copy is silent).
-- ---------------------------------------------------------------------------
local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'   or string.sub(raw, 1, 4) == '/dl '   then return 5; end
    return nil;
end

-- (M.swapWanted -- the content-keyed self-swap decision, tests SW* -- died in
-- the purge, Phase 1, together with trySelfSwap below: with the LAC seeder
-- gone there is no seeded file to watch, and a leftover swap could only ever
-- DOWNGRADE a running engine to frozen seed bytes.)

-- The engine machinery block: mode state, the Default tick and the command
-- surface -- live when the engine is armed. (The LAC-bridge machinery that
-- used to live alongside -- self-swap, handoff/request files, the
-- HandleEquipEvent wrap, lockstyle engine halves -- died in the purge,
-- Phase 1-2: it existed to cross two Lua states, and there is one.)
if engineActive() then
    loadModeState();        -- dlac-owned flags: restore (same job only) BEFORE the first mirror
    pcall(saveModeState);   -- then mirror whatever we start with for the GUI

    -- Native wiring: equipengine fires the dispatch points; every handler
    -- name it emits (ACTION_ROUTES rows + 'Default'/'Item') canonicalizes
    -- through EVENT_CANON exactly like a shim call would.
    do
        local eng = nativeEngine();
        if eng ~= nil then
            eng.onEvent = function(name) M.dispatch(name); end
        end
    end

    -- LAC only parses HandleDefault while OUTGOING packets flow (packethandlers.lua
    -- drives it from HandleOutgoingPacket) -- stand still with a menu open and the
    -- dispatches starve, which read as "maxmp stops the moment the equipment window
    -- opens" (the window itself blocks nothing: field-verified, /lac equip works
    -- with it up). Drive the SAME flow on a throttled frame tick so Default
    -- dispatching is packet-independent. The tick also watches the main job: a job
    -- change drops maxmp immediately, before it can battery the new job's gear.
    -- Upstream parity for LEGACY profiles too: HandleDefault must not run AT
    -- ALL while the pet's action is in flight (field case: Yinyang Robe in
    -- Idle.Body erased the pact piece the moment it was worn) or while a level
    -- sync is settling (v56). The engine-side holds only cover dlac
    -- dispatches, so LAC's own entry point is wrapped; the tick's calls flow
    -- through it as well. The wrap is a THIN shell: the actual decision is
    -- M.defaultGateHold, looked up at CALL time, so a self-swap refreshes the
    -- gate logic with no reinstall. WRAP_GEN guards the shell's install: it
    -- only bumps when the shell's own body changes shape (gen 2 = delegate to
    -- defaultGateHold; gen "nil + _dlacPetHold" = the v55 pet-only closure).
    -- A pre-gen wrap hid its original, so it BECOMES the preserved original
    -- once -- its inner pet check is idempotent under the gate's, and wrap
    -- depth stops at 2 because _dlacOrigHEE is reused by every later gen.
    -- (The gState.HandleEquipEvent wrap -- WRAP_GEN, the LAC entry-point
    -- gate -- died in the purge, Phase 2: the engine-side holds cover every
    -- dispatch, and there is no LAC entry point left to wrap.)

    -- (The ENGINE SELF-SWAP -- trySelfSwap, the ~2s content watch that carried
    -- a git pull through the seeded copy into LuaAshitacast's running state --
    -- died in the purge, Phase 1, with the seeder that fed it. The addon state
    -- requires this file from the addon folder; /dl reload or /addon reload
    -- dlac is the one update hop left, and it is a real reload.)

    -- Registrations are unregister-first: replace-deterministic whatever
    -- Ashita's same-alias behavior is (pcall: on the FIRST load there is
    -- nothing to unregister). The v108 request-file second door died in the
    -- purge, Phase 2 -- the typed /dl arrives HERE, the one state.
    local function engineCheckHalf()
        local job, sj = '?', nil;
        pcall(function()
            local p = gData.GetPlayer();
            job = p.MainJob or '?';
            sj = p.SubJob;
        end);
        local prof = nil;
        pcall(function() prof = _pok and _prof.activeName() or nil; end);
        local line = string.format('check (engine): alive -- v%d, job %s%s, profile %s.',
            M.VERSION, tostring(job),
            (type(sj) == 'string' and sj ~= '') and ('/' .. sj) or '',
            (prof ~= nil) and ('"' .. tostring(prof) .. '"') or '(legacy storage)');
        print('[dlac] ' .. line);
        writeDebugHandoff('debug-check-engine.txt', { line });
    end


    pcall(function() ashita.events.unregister('d3d_present', 'dlac-dispatch-tick'); end);
    local _tickAt, _tickJob, _tickPet = 0, nil, nil;
    local _natJob, _natAct = nil, nil;   -- identity latch (v111): job + profile the sets store answers for
    -- The JOB is part of the identity -- see M.jobReady / ADR 0007. (v46-v49 carried
    -- a /dl instdiag dump and tick counters here; it is what found the bug and it is
    -- in git history -- cb2fbe2..40288e3 -- if this class of thing ever returns.)
    ashita.events.register('d3d_present', 'dlac-dispatch-tick', function()
        pcall(function()
            -- Monitor stream drain: ONE line per frame, AHEAD of the 0.4s
            -- throttle. Same-frame QueueCommand pairs cross the bus reversed
            -- (v58); a frame apart they arrive in order, and a Precast/Midcast
            -- burst still lands within ~2 frames.
            if _monQ[1] ~= nil then
                local line = table.remove(_monQ, 1);
                pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dlacmonev ' .. line); end);
            end
            if os.clock() < _tickAt then return; end
            _tickAt = os.clock() + 0.4;
                                                 -- (the addon state reloads whole via /addon reload)
            -- (The v106/v108 window-flush + request-file watches died in the
            -- purge, Phase 2 -- two-state machinery, one state left.)
            local j = nil;
            pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
            -- Leaving the world OR changing job disarms the strip (ADR 0021).
            -- Reads _tickJob BEFORE the block below advances it.
            local _wwWhy, _wwDropped = M.worldWatch(j, _tickJob);
            if _wwWhy == 'job' and _wwDropped ~= nil then
                -- Announced on a JOB change only: leaving the world is silent
                -- because nobody is there to read it (ADR 0021, and 0022 shares
                -- the watch). All three can drop in the same pass.
                if _wwDropped.naked then
                    print('[dlac] naked: off (job changed) -- your gear comes back on the next pass.');
                end
                if _wwDropped.locked ~= nil then
                    print(string.format('[dlac] lock set: released "%s" (job changed) -- a locked set belongs to the job that locked it.',
                        tostring(_wwDropped.locked)));
                end
                if (_wwDropped.locks or 0) > 0 then
                    print(string.format('[dlac] slot locks: released %d (job changed) -- a lock belongs to the job that set it.',
                        _wwDropped.locks));
                end
                if (_wwDropped.disabled or 0) > 0 then
                    print(string.format('[dlac] free equip: off, %d slot(s) re-enabled (job changed) -- dlac is dressing them again.',
                        _wwDropped.disabled));
                end
            end
            if j ~= nil and j ~= 0 then
                if _tickJob ~= nil and j ~= _tickJob and M.modes['maxmp'] ~= nil then
                    M.modes['maxmp'] = nil;
                    saveModeState();
                    print('[dlac] maxmp: off (job changed).');
                end
                _tickJob = j;
            end
            -- NATIVE Default drive (v111): the same starvation fix the LAC
            -- tick below exists for -- outgoing packets pause when nothing
            -- moves, so Default must also ride the frame clock. Same zoning
            -- guard, same idle-only gate (equipengine's own chunk pump covers
            -- the packet-flow case; fireEvent dedupes nothing, dispatch's
            -- retrace gate keeps repeat parses cheap).
            do
                local eng = nativeEngine();
                -- Identity latch: job or active-profile change reloads the
                -- profile sets into the store.
                if eng ~= nil then
                    local job = nil;
                    pcall(function() job = gData.GetPlayer().MainJob; end);
                    local act = _pok and _prof.activeName() or nil;
                    if M.jobReady(j, job) and (job ~= _natJob or act ~= _natAct) then
                        -- ORDERING GATE (v117): never install/flatten before the
                        -- GEAR world is live -- a flatten over an empty gear
                        -- table produces stably-hollow sets (names present,
                        -- tables empty), the one wrong state no readiness proxy
                        -- or stability latch can see through. Skip WITHOUT
                        -- latching: the tick retries every 0.4s until gear.lua
                        -- is genuinely loaded. (A truly gear-less fresh
                        -- character has nothing to flatten anyway; the latch
                        -- lands right after their first Scan/Commit.)
                        local gearReady = false;
                        pcall(function()
                            local g = package.loaded['dlac\\gear'];
                            gearReady = type(g) == 'table' and type(g.NameToObject) == 'table'
                                        and next(g.NameToObject) ~= nil;
                        end);
                        if not gearReady then
                            if type(M._mpWarmNote) == 'function' then M._mpWarmNote('latch: gear world not live yet -- install deferred'); end
                        else
                        local fresh = select(1, readSetsSource());
                        if fresh ~= nil and type(fresh.Dynamic) == 'table' then
                            M._nativeSets = nil;   -- a fresh job: never carry the old job's flatten
                            local okI, n = installSets(fresh);
                            if okI == true then
                                _natJob, _natAct = job, act;
                                print(string.format('[dlac] native engine: %d set(s) installed for %s%s.',
                                    n, tostring(job), (act ~= nil) and (' (profile ' .. act .. ')') or ''));
                            end
                        else
                            _natJob, _natAct = job, act;   -- legacy/no file: latch anyway, retry on next change
                        end
                        end
                    end
                end
                if eng ~= nil and eng.state.action == nil then
                    local zoning = false;
                    pcall(function()
                        local pl = AshitaCore:GetMemoryManager():GetPlayer();
                        if pl ~= nil and pl.GetIsZoning ~= nil then
                            local z = pl:GetIsZoning();
                            if z == true or (type(z) == 'number' and z ~= 0) then zoning = true; end
                        end
                    end);
                    if not zoning then
                        local probe = nil;
                        pcall(function() probe = AshitaCore:GetMemoryManager():GetInventory():GetEquippedItem(0); end);
                        if probe == nil then zoning = true; end
                    end
                    if not zoning then
                        -- The maxmp OBSERVER rides the native tick exactly like
                        -- the LAC tail below: measured MP ticks are the banded
                        -- ladder's live input (v88 -- "fed by the 0.4s engine
                        -- tick"). v112: its absence here was Henrik's first
                        -- native field bug -- no observations, no measured
                        -- tick, nonsense hysteresis.
                        if _mpb ~= nil then
                            pcall(function()
                                local p = gData.GetPlayer();
                                _mpb.observe(tonumber(p.MP), p.Status == 'Resting');
                            end);
                        end
                        eng.fireEvent('Default', 'auto');
                    end
                end
            end
            -- Coalesced trigger-monitor flush: whatever fired since the last
            -- pass lands in firedstate.lua as ONE write.
            if _firedDirty and saveFiredState ~= nil then
                _firedDirty = false;
                saveFiredState();
            end
        end);
    end);

    pcall(function() ashita.events.unregister('command', 'dlac-dispatch'); end);
    ashita.events.register('command', 'dlac-dispatch', function(e)
        local start = argStart(string.lower(e.command));
        if start == nil then return; end
        local args = {};
        for a in string.gmatch(string.sub(e.command, start), '%S+') do args[#args + 1] = a; end
        local sub = args[1] and string.lower(args[1]) or nil;
        -- WHITELIST FIRST, branch second: a new subcommand needs adding HERE as well as
        -- below, or it returns in silence and looks like the command does not exist
        -- (v46's /dl instdiag, an hour lost to exactly this).
        if sub ~= 'mode' and sub ~= 'why' and sub ~= 'triggers' and sub ~= 'env' and sub ~= 'lock' and sub ~= 'sets' and sub ~= 'profile' and sub ~= 'ls' and sub ~= 'plan' and sub ~= 'prio' and sub ~= 'check' and sub ~= 'debug' and sub ~= 'naked' and sub ~= 'dress' and sub ~= 'disable' and sub ~= 'enable' and sub ~= 'stream' and sub ~= 'claims' then return; end
        e.blocked = true;

        if sub == 'claims' then
            -- The Integration surface's WRITE switch (feature\extclaim) -- the
            -- sibling of /dl stream, deliberately NOT the same switch: reading
            -- your gear and dressing you are different consents, and a
            -- misbehaving claimant has to be killable without also killing a
            -- parser's feed. ROUTING only, exactly like stream.
            pcall(function() require('dlac\\feature\\extclaim').command(args); end);
            return;
        end

        if sub == 'stream' then
            -- The Integration surface's Session switch (docs/design/
            -- integration-surface.md section 3). ROUTING only: the observer
            -- lives addon-side (feature\integration) -- the engine equips and
            -- explains its own equipping, it does not export (ADR 0014).
            pcall(function() require('dlac\\feature\\integration').command(args); end);
            return;
        end

        -- ('debug' stays whitelisted so feature\debug.lua -- the one printer
        -- for topics and usage -- owns the whole surface; the LAC-pinned
        -- engine half of '/dl debug ls' died in the purge, Phase 2.)

        if sub == 'check' then
            -- /dl check, engine half (v103; feature/check.lua owns the addon
            -- half). Liveness + identity only; deep state stays in dlacprobe
            -- (Henrik's 07-23 ruling).
            engineCheckHalf();
            return;
        end

        if sub == 'prio' then
            -- The Arbiter's live rank + per-claimant claim status (ADR 0012).
            -- Read-only -- the tracer's demo surface until the GUI Priority
            -- section lands (step 2). Printer gate: the ACTIVE engine's state
            -- only (LAC state, or the native-armed addon state -- v111; two
            -- states never print twice: native arms only with LAC absent).
            if not engineActive() then return; end
            local order = jobHelperPlace(M.arbOrder(ensureArbState()));   -- issue #138
            -- Live claim status per claimant: the registry rows' own
            -- prioStatus (ADR 0027 stage 0 -- the same reads M.dispatch does,
            -- no longer a hand-kept twin of them). Co-claim (ADR 0012
            -- amendment): every armed activity claims; rank settles
            -- overlapping slots -- the status shows all concurrent claimants
            -- ON, no newest-armed exclusivity.
            local status = { Triggers = 'floor (always on)' };
            for _, row in ipairs(CLAIMANTS) do
                if row.prioStatus ~= nil then status[row.name] = row.prioStatus(); end
            end
            print('[dlac] Claim priority (arbstate rank, highest first):');
            for i, name in ipairs(order) do
                -- The player reads the LABEL (ARB.claimantLabel -- the same map
                -- the Priority list and the Arbiter Monitor use); `name` stays
                -- the identity that keys status and arbstate's saved order.
                print(string.format('    %d. %-9s %s', i, ARB.claimantLabel(name), status[name] or '?'));
            end
            return;
        end

        if sub == 'plan' then
            -- The maxmp band plan (v88): renders the SAME context the dispatch
            -- pass runs, so what prints is what happens. Printer gate: the
            -- ACTIVE engine's state (v111 -- LAC state, or native-armed addon).
            if not engineActive() then return; end
            local pl = nil;
            pcall(function() pl = gData.GetPlayer(); end);
            local lines = M.mpPlanLines(M.mpBands({ player = pl }), wornItemName);
            print('[dlac] ' .. lines[1]);
            for i = 2, #lines do print('    ' .. lines[i]); end
            return;
        end

        -- ('ls' stays whitelisted so feature\lockstyle + lockstyleapply own
        -- the whole surface; the LAC-pinned engine apply branch died in the
        -- purge, Phase 2.)

        if sub == 'sets' then
            if string.lower(tostring(args[2] or '')) ~= 'reload' then
                print('[dlac] usage: /dl sets reload   (hot-swap the committed sets, no LAC reload)');
                return;
            end
            -- Hot-swap the PLAN without a LAC reload. gProfile.Sets is just a live
            -- table in THIS Lua state -- "Reload LAC" was only ever about the FILE
            -- changing under it (field insight: ffxi-lac loops that mutated set
            -- objects took effect immediately). A Commit rewrites the profile sets
            -- file (or, legacy, <JOB>.lua); re-read and install (installSets).
            local fresh, ferr, src = readSetsSource();
            if fresh == nil or type(fresh.Dynamic) ~= 'table' then
                print('[dlac] sets hot-swap failed (' .. tostring(ferr) .. ').');
                return;
            end
            local okI, n = installSets(fresh);
            if okI ~= true then print('[dlac] sets reload: ' .. tostring(n)); return; end
            print(string.format('[dlac] sets hot-swapped (%d dynamic set(s)%s) -- live now.',
                n, (src == 'profile' and _pok) and (' from profile "' .. _prof.activeName() .. '"') or ''));
            return;
        end

        if sub == 'profile' then   -- the profile storage layer (profiles.lua)
            if not _pok then
                print('[dlac] profile: profiles.lua is missing from <char>\\dlac\\ -- reload the dlac addon to reseed it.');
                return;
            end
            local a2 = args[2] and string.lower(args[2]) or nil;
            local job = nil;
            pcall(function() job = gData.GetPlayer().MainJob; end);
            if type(job) ~= 'string' or job == '' or job == '?' then job = nil; end

            if a2 == nil or a2 == 'status' or a2 == 'list' then
                local act = _prof.activeName();
                print('[dlac] active profile: ' .. act
                    .. (_prof.storageExists() and '' or '   (no profile storage yet -- legacy layout; see /dl profile migrate)'));
                if job ~= nil then
                    print(string.format('[dlac]   %s sets:     %s', job,
                        _prof.hasSetsFile(job) and tostring(_prof.setsPath(job)) or ('legacy (' .. job .. '.lua sets.Dynamic)')));
                    print(string.format('[dlac]   %s triggers: %s', job, tostring(triggersPath())));
                end
                local names = _prof.listProfiles();
                if names ~= nil and #names > 0 then print('[dlac]   profiles on disk: ' .. table.concat(names, ', ')); end
                print('[dlac] usage: /dl profile use <name> | new <name> | clone <newname> | migrate [go]');
                return;
            end

            if a2 == 'use' and args[3] ~= nil then
                local nm = _prof.sanitizeName(args[3]);
                if nm == nil then print('[dlac] profile use: bad name (letters/digits/_/- only).'); return; end
                local okA, aerr = _prof.setActive(nm);
                if not okA then print('[dlac] profile use: ' .. tostring(aerr)); return; end
                _prof.ensureStorage(nm);
                M.reloadTriggers();   -- trigger path changed -> re-read now, not in 1s
                local fresh = select(1, readSetsSource());
                if fresh ~= nil and type(fresh.Dynamic) == 'table' then

                    local okI, n = installSets(fresh);
                    if okI == true then
                        print(string.format('[dlac] profile "%s" active -- %d dynamic set(s) installed, triggers reloaded. No LAC reload needed.', nm, n));
                    else
                        print(string.format('[dlac] profile "%s" active -- sets install: %s', nm, tostring(n)));
                    end
                else
                    print(string.format('[dlac] profile "%s" active -- no sets for this job yet (build them in the Sets tab).', nm));
                end
                return;
            end

            if a2 == 'new' and args[3] ~= nil then
                local nm = _prof.sanitizeName(args[3]);
                if nm == nil then print('[dlac] profile new: bad name (letters/digits/_/- only).'); return; end
                _prof.ensureStorage(nm);
                print(string.format('[dlac] profile "%s" created (empty). Activate it with: /dl profile use %s', nm, nm));
                return;
            end

            if a2 == 'clone' and args[3] ~= nil then
                local src = _prof.activeName();
                local n, cerr = _prof.cloneProfile(src, args[3]);
                if n == nil then print('[dlac] profile clone: ' .. tostring(cerr)); return; end
                print(string.format('[dlac] cloned "%s" -> "%s" (%d file(s)). Activate with: /dl profile use %s', src, args[3], n, tostring(args[3])));
                return;
            end

            if a2 == 'migrate' then
                local go = args[3] ~= nil and string.lower(args[3]) == 'go';
                _prof.migrate(go, print);
                -- (No reload of anything: originals stay in place, the
                -- profile store is live on the next dispatch -- purge P3.)
                return;
            end

            print('[dlac] usage: /dl profile [status] | use <name> | new <name> | clone <newname> | migrate [go]');
            return;
        end

        if sub == 'disable' or sub == 'enable' then   -- free equip (ADR 0024): the ceiling
            -- /lac disable's grammar, deliberately: bare = all 16, a slot name =
            -- that one, and `enable` is the release. Never a toggle -- typing
            -- "disable" must not be the thing that re-enables a slot, which is
            -- /dl naked's rule and the same trap.
            local a2 = args[2] and string.lower(args[2]) or nil;
            local a3 = args[3] and string.lower(args[3]) or nil;
            local want, target = (sub == 'disable'), a2;
            if sub == 'disable' and a2 == 'off' then     -- /dl disable off == /dl enable all
                want, target = false, a3;
            elseif a3 == 'off' then                      -- /dl disable head off
                want = false;
            elseif a3 == 'on' then
                want = true;
            end
            target = target or 'all';
            if target ~= 'all' and not LAC_SLOT_OK[target] then
                print(string.format('[dlac] "%s" is not a slot', tostring(target)));
                return;
            end
            -- ONE LINE, always (Henrik, 2026-07-26: "please remove all the text").
            -- Everything the paragraph used to say has a better home: precedence
            -- is Claim Priority, the state readout is /dl prio, and what actually
            -- happened to a slot is /dl why. A chat line is for the ACK.
            local before = #M.disabledList();
            M.setDisabled(target, want);
            local now = M.disabledList();
            local label = (target == 'all') and 'All slots' or M.slotLabel(target);
            if want then
                print(string.format('[dlac] %s disabled - enable by /dlac enable%s',
                    label, (target == 'all') and '' or (' ' .. target)));
            elseif before == 0 then
                print('[dlac] Nothing was disabled');
            elseif #now == 0 then
                print(string.format('[dlac] %s enabled', label));
            else
                print(string.format('[dlac] %s enabled - still disabled: %s', label, table.concat(now, ', ')));
            end
            return;
        end

        if sub == 'naked' or sub == 'dress' then   -- the strip (ADR 0021): a Claim, not a lock
            local a2 = args[2] and string.lower(args[2]) or nil;
            local want;
            -- Bare '/dl naked' ARMS. Never a toggle: typing the word "naked" must
            -- not be the thing that dresses you.
            if sub == 'dress' then want = false;
            elseif a2 == 'off' then want = false;
            elseif a2 == 'toggle' then want = not M.nakedOn();
            else want = true; end
            local was = M.nakedOn();
            M.setNaked(want);
            if want and was then
                print('[dlac] already naked.  Release: /dl dress  (or /dl naked off)');
                return;
            end
            if not want then
                if not was then
                    print('[dlac] not naked -- nothing to undo.   (/dl naked strips every slot)');
                else
                    print('[dlac] dressed -- your triggers and automations own your gear again.');
                    print('[dlac]   Only the slots your sets and automations actually NAME come back; anything you');
                    print('[dlac]   had put on by hand (a ring, a trinket in Ammo) you re-equip yourself.');
                end
                return;
            end
            print('[dlac] NAKED -- every slot emptied and HELD empty, on every dispatch.');
            print('[dlac]   Release: /dl dress (or /dl naked off, or the Equipped tab).');
            print('[dlac]   Drops by itself on a job change, a logout, or a Reload LAC.');
            -- The other half of ADR 0022's "arm freely in either order": the hold
            -- stays armed underneath and genuinely tries every pass -- the
            -- Arbiter is what blocks it -- so it resumes the moment you dress.
            if M.lockedSetOn() then
                print(string.format('[dlac]   A set is LOCKED ("%s") -- it stays locked and resumes when you /dl dress.',
                    tostring(M.lockedSetLabel())));
            end
            -- Taking a weapon off is a server-side TP wipe. Say it once, up front:
            -- discovering it after a WS window is a bad way to learn.
            print('[dlac]   Taking a weapon off zeroes your TP and drops Aftermath -- that is the server, not dlac.');
            -- Anything ranked ABOVE Naked keeps its slots. Name it rather than let
            -- the player wonder why a pinned ring is still on.
            local ord = M.arbOrder(ensureArbState());
            local above = {};
            for _, n in ipairs(ord) do
                if n == 'Naked' then break; end
                -- MaxMP is the one row that CANNOT except itself. Every other
                -- claimant has an apply on its CLAIMANTS row, so a higher rank
                -- simply applies later and wins; MaxMP's equip stays WOVEN inside
                -- equipResolved, and both of its write points skip a 'remove'
                -- entry outright -- so dragging it above Naked cedes the slots
                -- but still equips nothing. Naming it here would promise an
                -- exception that does not happen.
                -- 'Disabled' is skipped for a different reason than MaxMP's: it
                -- is not a rank the player can reorder, so listing it under
                -- "Claim Priority reorders them" would point at a drag that does
                -- not exist. It gets its own line below, and only when it is ON.
                -- display list: labels, not identities (ARB.claimantLabel)
                if n ~= 'Triggers' and n ~= 'MaxMP' and n ~= 'Disabled' then above[#above + 1] = ARB.claimantLabel(n); end
            end
            if #above > 0 then
                print(string.format('[dlac]   %s rank ABOVE Naked, so their slots stay dressed. Gear Helpers > Claim Priority reorders them.',
                    table.concat(above, ', ')));
            end
            -- Free equip (ADR 0024) is the ceiling, so a disabled slot keeps its
            -- piece on through the strip. One line -- "I went naked and my hands
            -- are still on" otherwise costs a /dl why to answer.
            local dzNow = M.disabledList();
            if #dzNow > 0 then
                print(string.format('[dlac]   Free equip is on - %s stay dressed (/dlac enable all)',
                    table.concat(dzNow, ', ')));
            end
            -- THE ONE WAY NAKED SILENTLY DOES NOTHING. LuaAshitacast's own
            -- /lac disable (the Equipped tab's "Free equip") sets gState.Disabled,
            -- and LAC's PrepareEquip drops every UNEQUIP for a disabled slot -- so
            -- a fully armed strip produces zero packets and zero complaints. Two
            -- switches that both read as "stop my gear moving", one silently
            -- beating the other, is worth a line every time.
            local nDis = 0;
            pcall(function()
                local st = rawget(_G, 'gState');
                if st == nil or type(st.Disabled) ~= 'table' then return; end
                for i = 1, 16 do if st.Disabled[i] == true then nDis = nDis + 1; end end
            end);
            if nDis > 0 then
                print(string.format('[dlac]   WARNING: %d slot(s) are DISABLED in LuaAshitacast (/lac disable -- the Equipped tab\'s'
                    .. ' "Free equip"). LAC refuses to unequip a disabled slot, so those will NOT come off.'
                    .. ' Run /lac enable (or uncheck Free equip) first.', nDis));
            end
            return;
        end

        if sub == 'lock' then   -- slot locks (the veto) + the locked set (ADR 0022)
            local slot = args[2] and string.lower(args[2]) or nil;
            if slot == nil then
                -- Both halves of the row, then every variant and what it does.
                -- Henrik asked for this print by name: four commands that differ
                -- only in which slots they freeze are unguessable otherwise.
                local out = {};
                for s in pairs(M.locks) do out[#out + 1] = s; end
                table.sort(out);
                print('[dlac] locked slots: ' .. ((#out > 0) and table.concat(out, ', ') or '(none)'));
                if M.lockedSetOn() then
                    print(string.format('[dlac] locked set:   "%s" (%s) -- %d slot(s) held, re-applied every dispatch',
                        tostring(M.lockedSetLabel()), tostring(M.lockedSet.mode), tonumber(M.lockedSet.n) or 0));
                else
                    print('[dlac] locked set:   (none)');
                end
                print(string.format('[dlac] %-32s -- %s', '/dl lock <slot|all> [on|off]',
                    'the engine stops equipping into that slot; it keeps whatever is worn'));
                for _, w in ipairs(LOCKSET_ORDER) do
                    local spec = LOCKSET_MODES[w];
                    print(string.format('[dlac] %-32s -- %s',
                        '/dl lock ' .. w .. (spec.needsName and ' <set>' or ''), spec.blurb));
                end
                print(string.format('[dlac] %-32s -- %s', '/dl lock set off',
                    'release the locked set   (/dl lock all off releases the slot locks with it)'));
                return;
            end

            -- THE LOCKED SET (ADR 0022). Four command words, one claim: they
            -- differ only in LOCKSET_MODES[word].fill -- what happens to a slot
            -- the set does not name. Nothing here equips: arming freezes a claim
            -- and the Arbiter applies it on the next dispatch, ~0.4s away. That
            -- is the whole fix for the native bug this replaced -- there is no
            -- command-path equip left to bracket wrongly.
            local spec = LOCKSET_MODES[slot];
            if spec ~= nil then
                local a3 = args[3] and string.lower(args[3]) or nil;
                if a3 == 'off' then          -- 'off' beats a set literally named "off"
                    local had = M.clearLockedSet();
                    if had == nil then
                        print('[dlac] no set is locked -- nothing to release.   (/dl lock lists every variant)');
                    else
                        print(string.format('[dlac] lock set: released "%s" -- your triggers and automations own those slots again.', had));
                    end
                    return;
                end
                local nm, s = nil, nil;
                if spec.needsName then
                    nm = (args[3] ~= nil) and table.concat(args, ' ', 3) or nil;
                    if nm == nil then
                        print(string.format('[dlac] usage: /dl lock %s <name> -- %s', slot, spec.blurb));
                        print('[dlac]   Release: /dl lock set off (or /dl lock all off).  /dl lock lists every variant.');
                        return;
                    end
                    pcall(function()
                        if type(M._nativeSets) == 'table' then s = M._nativeSets[nm]; end   -- the one sets store
                    end);
                    -- Refuse BEFORE touching anything: a failed name must not
                    -- leave the player half-locked with nothing equipped.
                    if type(s) ~= 'table' then
                        print(string.format('[dlac] lock set: no committed set named "%s" for this job (names are case-sensitive; Commit it in the Sets tab first).', nm));
                        return;
                    end
                end
                local rec = armLockedSet(s, slot, nm);
                if rec == nil then
                    print('[dlac] lock set: could not read your gear just now -- try again in a moment.');
                    return;
                end
                print(string.format('[dlac] LOCKED to "%s" -- %d slot(s) held, re-applied on every dispatch.',
                    tostring(M.lockedSetLabel()), tonumber(rec.n) or 0));
                local miss = rec.missing or {};
                if #miss > 0 then
                    -- Henrik's ruling: lock to the best of our abilities, then say
                    -- which pieces were not on you AND where they are -- those
                    -- slots go LOOSE (available), because an available slot beats
                    -- an empty one. This is the last moment the player can fix it.
                    print(string.format('[dlac]   %d piece(s) are NOT on you -- those slots are LOOSE (normal gear swaps continue there):', #miss));
                    for _, m in ipairs(miss) do
                        print(string.format('[dlac]     %-6s %-26s %s', tostring(m.slot), tostring(m.item),
                            (m.where ~= nil) and ('-- in your ' .. m.where) or '-- not found anywhere'));
                    end
                    print('[dlac]   Move them to Inventory or a Wardrobe and lock again to hold those slots too.');
                end
                print('[dlac]   Release: /dl lock set off  (or /dl lock all off).');
                -- Anything ranked ABOVE the Locks row can still move its slots.
                -- Same courtesy /dl naked pays; MaxMP is omitted for the same
                -- reason it is there (its equip is woven, so it cedes but never
                -- dresses). Naked gets its own line below when it is actually on.
                local ord, above = M.arbOrder(ensureArbState()), {};
                for _, n in ipairs(ord) do
                    if n == 'Locks' then break; end
                    if n ~= 'Triggers' and n ~= 'MaxMP' and n ~= 'Naked' then above[#above + 1] = ARB.claimantLabel(n); end
                end
                if #above > 0 then
                    print(string.format('[dlac]   %s rank ABOVE a lock, so they can still change their slots. Gear Helpers > Claim Priority reorders them.',
                        table.concat(above, ', ')));
                end
                if M.nakedOn() then
                    print('[dlac]   NAKED outranks a locked set -- nothing will be worn until you /dl dress.');
                end
                return;
            end

            local a3 = args[3] and string.lower(args[3]) or nil;
            local state = nil;                       -- default: toggle
            if a3 == 'on' then state = true; elseif a3 == 'off' then state = false; end
            local res = M.setLock(slot, state);
            if res == nil then
                print('[dlac] unknown slot: ' .. slot .. '  (main/sub/range/ammo/head/neck/ear1/ear2/body/hands/ring1/ring2/back/waist/legs/feet or all)');
                return;
            end
            print(string.format('[dlac] lock %s %s -- the engine %s equip into %s',
                slot, res and 'ON' or 'OFF', res and 'will NOT' or 'may again',
                (slot == 'all') and 'any slot' or ('the ' .. slot .. ' slot')));
            -- `/dl lock all off` is the UNIVERSAL release (Henrik, 2026-07-26:
            -- from the player's side "lock" is one word, so turning it all off
            -- must let go of everything the word covers). /dl lock set off stays
            -- the narrow door for releasing only the set.
            if slot == 'all' and res == false then
                local had = M.clearLockedSet();
                if had ~= nil then
                    print(string.format('[dlac]   ...and released the locked set "%s".', had));
                end
            end
            return;
        end

        if sub == 'env' then   -- day/weather as the engine sees it (the obi's decision input)
            local env = nil;
            pcall(function() env = gData.GetEnvironment(); end);
            if env == nil then print('[dlac] env unavailable (not logged in?).'); return; end
            print(string.format('[dlac] day: %s (element %s)   weather: %s (element %s)',
                tostring(env.Day), tostring(env.DayElement), tostring(env.Weather), tostring(env.WeatherElement)));
            local parts = {};
            for _, el in ipairs({ 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark' }) do
                local n = netForElement(el);
                if n ~= 0 then parts[#parts + 1] = string.format('%s %+d', el, n); end
            end
            print('[dlac] net signs: ' .. ((#parts > 0) and table.concat(parts, ', ') or '(all neutral)')
                .. '   -- dlac:AutoObi equips only when its spell\'s element is positive');
            local mn = menuName();
            print('[dlac] open menu: ' .. ((mn ~= '') and ('"' .. mn .. '"') or '(none)'));
            return;
        end

        if sub == 'mode' then
            if args[2] == nil then
                local act = M.activeModes();
                print('[dlac] active modes: ' .. ((#act > 0) and table.concat(act, ', ') or '(none)')
                    .. '   (/dl mode <name> [on|off|toggle])');
                return;
            end
            ensureLoaded();                          -- cycle definitions live in the trigger file
            -- Mode names may contain SPACES ("WHM Weapons"). Resolve by longest
            -- arg-join that names a KNOWN mode (definition or live flag); whatever
            -- follows is the state. Unknown names: a trailing on/off/toggle splits
            -- off, otherwise the whole tail is the (new toggle's) name.
            local function knownMode(nm)
                local lnm = string.lower(nm);
                return (_trig.modeDefs ~= nil and _trig.modeDefs[lnm] ~= nil) or (M.modes[lnm] ~= nil);
            end
            local name, stateStr = nil, nil;
            for cut = #args, 2, -1 do
                local cand = table.concat(args, ' ', 2, cut);
                if knownMode(cand) then
                    name = cand;
                    if cut < #args then stateStr = table.concat(args, ' ', cut + 1); end
                    break;
                end
            end
            if name == nil then
                local last = string.lower(args[#args]);
                if #args > 2 and (last == 'on' or last == 'off' or last == 'toggle') then
                    name, stateStr = table.concat(args, ' ', 2, #args - 1), last;
                else
                    name = table.concat(args, ' ', 2);
                end
            end
            local state = nil;                       -- default: toggle / cycle to next
            if stateStr ~= nil then
                local l3 = string.lower(stateStr);
                if l3 == 'on' then state = true;
                elseif l3 == 'off' then state = false;
                elseif l3 == 'toggle' then state = nil;
                else state = stateStr; end           -- cycle mode: jump straight to this value
            end
            local ln = string.lower(name);
            local before = M.modes[ln];
            local res = M.setMode(name, state);
            if res ~= before then
                -- Make the flip visible NOW instead of at the next game event:
                -- re-flatten the Dynamic sets (mode-gated entries pick differently)
                -- and re-run the Default dispatch so the equip follows the mode.
                pcall(function()
                    local u = utilsModule();
                    if u == nil or type(u.rebuildSets) ~= 'function' then return; end
                    if type(M._nativeSets) == 'table' then
                        M._nativeSets = u.rebuildSets(M._nativeSets) or M._nativeSets;
                    end
                end);
                pcall(function() M.dispatch('Default'); end);
            end
            local function disp(v)
                if v == true then return 'ON'; end
                if v == nil or v == false then return 'off'; end
                return tostring(v);
            end
            local def = _trig.modeDefs and _trig.modeDefs[ln] or nil;
            local shown = (def ~= nil and def.name) or name;
            print(string.format('[dlac] %s: %s -> %s', shown, disp(before), disp(res)));
            return;
        end

        if sub == 'why' then
            -- /dl why <slot> (ADR 0027 item 4, ratified 2026-07-27): the FULL
            -- contest for ONE slot -- every claimant in rank order, the
            -- verdict's word (fell / ineligible / held empty) with its
            -- reason, and the floor ladder behind the slot. Depth on demand:
            -- the bare command below keeps its one-screen budget untouched.
            local wslot = args[2] and string.lower(args[2]) or nil;
            if wslot ~= nil and LAC_SLOT_OK[wslot] then
                local best, bestEv = nil, nil;
                for _, ev in ipairs(EVENTS) do
                    local tr = _trace[ev];
                    if tr ~= nil and tr.contest ~= nil
                       and (best == nil or tostring(tr.time) >= tostring(best.time)) then
                        best, bestEv = tr, ev;
                    end
                end
                if best == nil then
                    print('[dlac] why ' .. wslot .. ': no contest recorded yet (act once, then ask again).');
                    return;
                end
                local c = best.contest;
                local function findCI(map)
                    if type(map) ~= 'table' then return nil, nil; end
                    for slot, v in pairs(map) do
                        if string.lower(tostring(slot)) == wslot then return v, slot; end
                    end
                    return nil, nil;
                end
                local ops, dispSlot = findCI(c.explain);
                print(string.format('[dlac] %s -- the %s contest (%s):',
                    tostring(dispSlot or wslot), tostring(bestEv), tostring(best.time)));
                -- ONE ANSWER PER SLOT (2026-08-01, Henrik's screenshot of the
                -- v159 pair verdict). "nobody claimed it (kept as worn)" is the
                -- NO-CONTEST line, and a slot the arbitration REFUSED has no
                -- contest by construction -- the refused piece never reaches
                -- floorTbl, so ops comes back nil and this branch fired above
                -- the verdict that explains the slot:
                --     nobody claimed it (kept as worn).
                --     held EMPTY: Arcane Arbalest and Cinderstone cannot coexist
                -- Two sentences, disagreeing about the same slot. "kept as worn"
                -- is also the weaker truth: when a stat stick holds Range, the
                -- SERVER empties it -- the slot is not merely unwritten. So the
                -- no-contest line stands down whenever a verdict below will
                -- speak. See docs/design/two-way-arbiter.md §11 for the full
                -- rendering contract this is one half of (the Monitor's hover
                -- carries the same guard, for the same reason).
                if ops == nil and M.slotVerdict(c, dispSlot or wslot) == nil then
                    print('    nobody claimed it (kept as worn).');
                elseif ops ~= nil then
                    for i, op in ipairs(ops) do
                        local item = (op.item == M.LOCK_HELD) and 'LOCK-HELD (keep worn)' or tostring(op.item);
                        print(string.format('    %d. %s (rank %d): %s%s',
                            i, tostring(ARB.claimantLabel(op.name)), op.rank or 0, item, (i == 1) and '   <- winner' or ''));
                    end
                end
                local rv = findCI(c.rep);
                local iv = findCI(c.inel);
                local sv = findCI(c.sup);
                local dv = findCI(c.fall ~= nil and c.fall.dead or nil);
                if rv ~= nil then
                    if rv.why == 'unavail' then
                        print(string.format('    fell: %s -> %s (%s is not in a bag you can equip from)',
                            tostring(rv.from), tostring(rv.to), tostring(rv.from)));
                    else
                        print(string.format('    fell: %s -> %s (it reserves %s -- owned above)',
                            tostring(rv.from), tostring(rv.to), tostring(rv.by)));
                    end
                elseif dv ~= nil then
                    print(string.format('    UNAVAILABLE: %s is not in a bag you can equip from, and nothing below it on the ladder is either (kept as worn).',
                        tostring(dv)));
                elseif iv ~= nil then
                    print(string.format('    INELIGIBLE: it reserves %s, which a higher claim owns (no rung to fall to).',
                        tostring(iv)));
                elseif sv ~= nil then
                    print(string.format('    held EMPTY: reserved by %s (the server clears it while that is worn).',
                        tostring(sv)));
                end
                -- The PAIR verdict (v159), its own line: Range and Ammo lose
                -- their slot to a law no other slot is subject to, and folding
                -- it into "reserved" would print the wrong sentence for the
                -- half of it that has no reservation in it at all (a bolt and a
                -- bow are two ordinary pieces).
                local pv = c.pair;
                if pv ~= nil and string.lower(tostring(pv.slot)) == string.lower(tostring(dispSlot or wslot)) then
                    if pv.remove == true then
                        print(string.format('    REMOVED: worn %s cannot sit beside %s -- the server would strip the Range slot.',
                            tostring(pv.loser), tostring(pv.keep)));
                    elseif pv.why == 'mismatch' then
                        print(string.format('    held EMPTY: %s cannot be fired by %s, so the ammo yields (Range is never forced off).',
                            tostring(pv.loser), tostring(pv.keep)));
                    else
                        print(string.format('    held EMPTY: %s and %s cannot coexist -- kept %s, the higher Level.',
                            tostring(pv.loser), tostring(pv.keep), tostring(pv.keep)));
                    end
                end
                -- The ladder: the RECEIPT first (what the arbitration was
                -- actually handed -- and the only thing that can answer for a
                -- claimant's ladder at all), the re-derivation second, for the
                -- slots nothing was refused in. Same law the Monitor renders
                -- by: one record, three renderers.
                local rcpt = findCI(c.asked);
                local srcName = findCI(c.src);
                local ladName, ladItems = nil, nil;
                if type(rcpt) == 'table' and type(rcpt.items) == 'table' and rcpt.items[1] ~= nil then
                    ladName, ladItems = rcpt.set, rcpt.items;
                elseif srcName ~= nil then
                    local lad = M.candidatesFor(srcName, dispSlot or wslot);
                    if lad ~= nil and type(lad.items) == 'table' and #lad.items > 0 then
                        ladName, ladItems = srcName, {};
                        for _, r in ipairs(lad.items) do ladItems[#ladItems + 1] = r.name; end
                    end
                end
                if ladItems ~= nil then
                    -- The whole ladder with each REFUSED rung marked and told
                    -- apart (Henrik's ruling): the survivor alone does not
                    -- answer "why am I not wearing what I asked for" -- the
                    -- rungs it walked past, and what stopped each one, is the
                    -- answer.
                    local ref = findCI(c.fall ~= nil and c.fall.refused or nil);
                    local whyOf = {};
                    if type(ref) == 'table' then
                        for _, r in ipairs(ref) do whyOf[r.name] = r.why; end
                    end
                    local names = {};
                    for _, nm in ipairs(ladItems) do
                        local w = whyOf[nm];
                        local tag = '';
                        if w == 'unavail' then tag = ' [x not in your bags]';
                        elseif w == 'reserve' then tag = ' [x reserves a slot owned above]'; end
                        names[#names + 1] = nm .. tag;
                    end
                    print(string.format('    ladder (%s): %s', tostring(ladName), table.concat(names, ' > ')));
                end
                return;
            elseif wslot ~= nil then
                print('[dlac] why: unknown slot "' .. tostring(args[2]) .. '" (main, sub, range, ammo, head, body, ...).');
                return;
            end
            local any = false;
            for _, ev in ipairs(EVENTS) do
                local tr = _trace[ev];
                if tr ~= nil then
                    any = true;
                    print(string.format('[dlac] %s  (%s)  %s', ev, tr.time, tr.action or ''));
                    for _, l in ipairs(tr.lines) do print('    ' .. l); end
                end
            end
            if _trig.err ~= nil then print('[dlac] trigger file error: ' .. _trig.err); end
            if not any then print('[dlac] why: nothing dispatched yet (do something, then ask again).'); end
            return;
        end

        -- sub == 'triggers'
        local a2 = args[2] and string.lower(args[2]) or nil;
        if a2 == 'reload' then
            M.reloadTriggers();
            -- silent: the GUI queues this after trigger edits; the re-read is
            -- automatic on the next action either way (errors still print).
        elseif a2 == 'init' then
            local ok, msg = M.initTriggers();
            print('[dlac] triggers init: ' .. tostring(msg));
        else
            print('[dlac] triggers file: ' .. tostring(triggersPath())
                .. ((_trig.err ~= nil) and ('   [error: ' .. _trig.err .. ']') or ''));
            print('[dlac] usage: /dl triggers reload | init | path');
        end
    end);
end

return M;
