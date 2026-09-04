--[[
    dlac.lua — Ashita v4 addon entry point. dlac IS the equip engine: it reads
    player + inventory through AshitaCore and equips via its own authentic
    0x050/0x051 packets (feature\equipengine + dispatch.lua). The name is
    history — "dynamic LuaAshitacast" absorbed its host (ADR 0015) and the
    LuaShitacast purge (docs/design/lac-purge-plan.md) removed the last of it:
    one Lua state, one engine, one storage home (config\addons\dlac\<char>\).
    Old luashitacast\ trees are read-only IMPORT territory (Sets tab static /
    group imports; login auto-migration copies data in, never touches it).

    The library modules use the "dlac\\X" require prefix: <install>/addons/?.lua
    is appended to package.path, so require("dlac\\X") resolves to
    addons/dlac/X.lua. X carries the folder — require("dlac\\ui\\gearui") lands
    on addons/dlac/ui/gearui.lua. The five root files (utils, dispatch, chatfmt,
    profiles, gear) stay flat: require("dlac\\utils") is published API. GUI in
    ui\, data in data\, gear machinery in gear\, features in feature\, lib\.
]]--

addon.name    = 'dlac';
addon.author  = 'Mindie';
addon.version = '2026.09.04a';  -- date of the last shipped change (Ashita prints it at
                                -- load) -- bump alongside every commit that changes behavior
                                -- (03f = engine v163: the contest explains its own plan;
                                --  03g = one floating tray: Teleports + the E-Box crates;
                                --  03h = the pin menu: wearable-now only, icons, and
                                --  several pins on one slot;
                                --  03i = the tray is a COLUMN, top to bottom;
                                --  03j = the pin popup's width is MEASURED;
                                --  03k = item facts beside the pin menu;
                                --  03l = the pin cascade is compact + scrolls;
                                --  03m = item facts INSIDE the pin popup;
                                --  03n = the facts get a vote on the WIDTH;
                                --  03o = that width is PINNED, so the popup is static;
                                --  03p = the facts pad with LINES, not a Dummy;
                                --  03q = the pin popup's row budget is MEASURED;
                                --  03r = /dl unused: the wardrobe audit -- what is
                                --  in a Mog Wardrobe that nothing asks for;
                                --  03s = ...and the lockstyle advice says the whole
                                --  truth: move it anywhere, but keep owning it;
                                --  03t = engine v164: two of one weapon pair by
                                --  what is in your BAGS, not by a stamp written
                                --  once -- and the skill-0 Range families
                                --  (animators, soultrappers) get indexed at all,
                                --  loudly when they cannot be;
                                --  03w = the food register stops believing a
                                --  zone: an Instant Warp used seconds after a
                                --  loading screen was being recorded as a meal,
                                --  so the shipped food table now vouches for
                                --  what you ate and a pre-catalogue history
                                --  file heals itself on load;
                                --  03x = engine v166: MODE LOCKS -- while a mode
                                --  is active, the slots it locks come from ONE
                                --  named set and no trigger rule can move them,
                                --  and two modes locking one slot are FIRST
                                --  COME, FIRST SERVE -- the one that took it
                                --  holds it, the rest queue;
                                --  03y = engine v167: ...and that queue is
                                --  visible where you actually are -- a 'q' on
                                --  the Arbiter Monitor cell and an
                                --  '(n queued)' count on the Trigger Monitor,
                                --  both carrying who waits in the hover;
                                --  03z = /dl nm: which NMs are in this zone,
                                --  what pops them, and a ready-to-paste
                                --  FilterScan filter over the placeholder
                                --  spawn points -- straight from the server's
                                --  own phList, no camping notes required;
                                --  03za = your craft skills, under the glyphs
                                --  on the hobby bar -- and BLUE when they are
                                --  capped, read off the server's own blue-text
                                --  bit, so the bar says what the skills menu
                                --  says;
                                --  03zb = ...and under the Automations panel's
                                --  craft glyphs too, from the same shared cell;
                                --  04a = THE NM COMPENDIUM: /dl nm grew the real
                                --  disfavour curve (the 5% was never flat), live
                                --  drop tables with tiers and group shares, a
                                --  Treasure Hunter verdict per drop, passive
                                --  placeholder-round tracking counted by INDEX
                                --  and shown as a floor that goes stale rather
                                --  than a prediction -- and a window that
                                --  searches all of it by name, area or drop;
                                --  04b = ...and it has a door: an NM Compendium
                                --  row in the header menu, between Teleports and
                                --  Wishlist, opening the SAME window as
                                --  "/dl nm window" through the one entry point;
                                --  05a = THE SEED FAILURE NAMES ITSELF: the three
                                --  baseline seeders return a reason instead of a
                                --  bare false, the gate check says WHICH of the
                                --  four files is missing and where, the load
                                --  ledger probes the spine it never covered
                                --  (dispatch first -- every other require of it
                                --  is call-time under pcall, so it could fail in
                                --  total silence), and /dl check carries the
                                --  whole verdict for /dl report to ship;
                                --  05b = THE LEGACY-FALLBACK SWEEP: eight dead
                                --  `charBase() .. 'dlac\' ` compositions removed
                                --  across six files, setActive stops creating a
                                --  folder under luashitacast\, and the /dl debug
                                --  handoff readers lose a `dlac\` segment the
                                --  writer dropped at the purge -- so an engine
                                --  half can actually merge into a report again;
                                --  05c = the trigger `mode` condition is a
                                --  PICKER: the modes this job defines, a cycle
                                --  offering one entry per value, instead of a
                                --  name you had to spell right from memory;
                                --  05d = ...and a mode reference that no longer
                                --  resolves says so -- [missing mode] on the
                                --  rule and a banner over the tab, the same
                                --  pair a missing group has always had, because
                                --  a rule gated on a mode that does not exist
                                --  matches nothing and used to do it silently;
                                --  05e = AutoAmmo says a stock-out ONCE PER
                                --  ZONE: a weaponskill between shots walks a
                                --  different ladder, and the old latch read
                                --  that as the condition clearing -- so one
                                --  empty stack announced itself every few
                                --  seconds all fight;
                                --  05f = /dl giftbox: open every Goblin/Grand
                                --  Giftbox in your inventory, smallest first,
                                --  stopping before your bag is too full to
                                --  hold the next payout -- and paced by each
                                --  box's own count dropping, never by a
                                --  guessed delay;
                                --  05g = ...and the giftboxes get an icon in
                                --  the floating tray, under the E-Box crates,
                                --  drawn as the box's OWN in-game art -- plus
                                --  a longer beat between opens, because the
                                --  first field run met lag;
                                --  06a = Brigand's Eyepatch joins Other
                                --  Teleports, under the Tidal Talisman: a
                                --  head-slot Teleport (Norg) whose use delay
                                --  is 15s, not the family's 30 -- and it
                                --  stays visible to set building, being real
                                --  fishing gear;
                                --  06b = ...and it displays in the fishing
                                --  panel too -- the undisplayed ruling rested
                                --  on "nothing in-game mentions them", and a
                                --  player turned up holding one;
                                --  06d = ...in its OWN Crooked Jones row, not
                                --  the Mariners column: it is bought with
                                --  DOUBLOONS in Norg, a third fishing
                                --  currency, and the id that sits beside the
                                --  venture block never meant otherwise;
                                --  06f = the whole Sinister Stash is on the
                                --  fishing panel -- seven rows with prices,
                                --  three of which own no catalog id and say
                                --  so by drawing no icon -- and the Expert
                                --  Angler tooltip both stops calling the
                                --  Eyepatch venture gear AND gets its percent
                                --  signs back: SetTooltip is printf, and the
                                --  bare '%' had been eating the character
                                --  after it since the note shipped;
                                --  06g = ...and the Stash rows get their art:
                                --  the Chart and the Hook by LIVE item id
                                --  (9426 / 9420 -- ids the catalog does not
                                --  carry and the public server clone gives to
                                --  other items entirely), the Red Crab Mount
                                --  from assets\redcrab.png, because a mount
                                --  is not an item to have an id at all;
                                --  06h = /dl giftbox grows two more families:
                                --  the Goblin Gatherbox and the Tiny/Timeworn/
                                --  Titanic Tackleboxes open in the same run,
                                --  same space gate, same count-drop pacing --
                                --  the command answers to /dl box(es) too, and
                                --  every line it prints now says "box"; and its
                                --  tray icon stops being CW-only -- it is a
                                --  PLACE gate now, at an E-Box for a Crystal
                                --  Warrior, in town for everyone else;
                                --  06j = the Red Crab Mount's icon is real:
                                --  the 32x32 anti-aliased crab of the six
                                --  Henrik sent, because the row draws at 18px
                                --  beside game item icons that are themselves
                                --  32x32 downscaled -- the pixel-art variants
                                --  are one 16px sprite upscaled and shimmer
                                --  at any non-integer size;
                                --  06k = the Mamool Ja, Lamia and Troll Troves
                                --  join /dl giftbox -- and reading the live
                                --  item table to add them showed the four
                                --  giftbox rungs have NEVER matched: the game
                                --  calls them Gob. Giftbox (sm/md/lg/gr), so
                                --  the substring caught them while the ladder
                                --  ranked all four unknown and opened the
                                --  GRAND first, the reverse of the rule;
                                --  06l = BROWSE ANOTHER JOB: a job picker at the
                                --  top of the Gear window points the editors --
                                --  Sets, Triggers, Groups, Modes, Blueprints,
                                --  Weights -- at another job's files, as if you
                                --  were on it at level 75. Editing only: nothing
                                --  equips, and the Equipped tab says so rather
                                --  than guessing a worn set it cannot know;
                                --  06m = troves confirmed opening in game, so
                                --  the beat between opens comes down 1.2s ->
                                --  1.0s (Henrik's fourth field call on that
                                --  number);
                                --  06n = ...and the trove names are confirmed
                                --  against the CLIENT at last, off a log line
                                --  rather than the server table: "Mindie uses
                                --  a Troll trove", "Lift uses a Mamool Ja
                                --  trove" -- word for word what the ladder
                                --  already carried. A Halvung rung that 06m
                                --  added on a misremembered name comes back
                                --  out; it had opened fine either way, which
                                --  is the whole lesson -- the substring opens
                                --  boxes, the ladder only orders them, so
                                --  "it worked" can never confirm a name);
                                --  06o = three work blocks land together: equip
                                --  packets get their own module (feature\
                                --  gearpackets) with the batch question settled
                                --  at the send site; the slot the SERVER holds
                                --  shut is struck out wherever gear is drawn
                                --  (the tab, the floating window, the pin menu)
                                --  from ONE shared reader; and copying a rule to
                                --  a job dlac has never used INSTANTIATES that
                                --  job entry first, instead of writing a rule
                                --  into a file with nothing to target;
                                --  07a = SERVER-AGNOSTIC RENDERING + SURFACES:
                                --  lib\imguicompat wraps the three imgui calls
                                --  whose shapes changed in the newer Ashita
                                --  binding (BeginChild's border bool ->
                                --  ImGuiChildFlags; ImageButton/Image), keyed
                                --  on the BINDING so old builds run untouched;
                                --  and lib\featuregate gates tabs + menu rows
                                --  per server pack (servers\<id>\features.lua)
                                --  with per-character overrides under Menu >
                                --  Settings > Features -- AscensionXI ships
                                --  gear-only: Equipped, All Equipment, Sets,
                                --  Triggers;
                                --  07b = GEAR VAULT slice 1 (AscensionXI only):
                                --  the 0x1E0 wire client + the read-only
                                --  vault mirror as a pack module -- vaulted
                                --  gear is OWNED (never available), prune is
                                --  vault-safe, /dl vault answers; design in
                                --  docs/design/gear-vault-integration.md;
                                --  07c = the server RENAMED: the Vanaheim
                                --  pack is now servers\ascensionxi\ --
                                --  same pack, new id/name, and the
                                --  per-install flag config\addons\dlac\
                                --  server.lua must now read
                                --  return { server = 'ascensionxi' };
                                --  30a = THE SERVER IS ASKED, NEVER ASSUMED
                                --  (the brother's first install mounted cexi
                                --  silently): no flag file -> detection off
                                --  the Ashita boot config (servers\<id>\
                                --  detect.lua -- only cexi ships one), and
                                --  failing that a first-run chooser window
                                --  writes the flag (also Menu > Settings >
                                --  Server). Index order never chooses again.
                                --  Base tabs reordered (Gear Vault > Sets >
                                --  Triggers > All Equipment > Equipped, via
                                --  uihost.TAB_RANK); Gear Vault tab reworked:
                                --  options behind a cog, wardrobe wording
                                --  (no "shelf"), the city gate is a calm
                                --  notice in the field instead of a full-
                                --  wardrobe complaint, and the additions
                                --  engine obeys the VAULT LAW -- only gear
                                --  the vault holds is ever pushed into a
                                --  layout, never bag/unowned gear;
                                --  30b = Henrik's same-day field round: the
                                --  tab ORDER is folded into the bar's ID
                                --  (this ImGui build keeps a known bar's
                                --  tab order, and its context outlives an
                                --  /addon reload -- only a new ID reorders);
                                --  [wanted] tags + Store-wanted CUT (the
                                --  player curates); vault-row button is
                                --  'Add to Mog Wardrobe'; the header's
                                --  'N pieces stored' sentence becomes the
                                --  Vault (N) sub-tab count, fresh = silent;
                                --  30c = the module list is a CODE fact:
                                --  hand-maintained servers\<id>\modules.lua
                                --  outranks the GENERATED manifest.modules
                                --  (gen_pack.py once emitted {} and the
                                --  Gear Vault silently never loaded -- the
                                --  brother's install, again); /dl check +
                                --  pack_lint print the list and its source)
addon.desc    = 'Gear sets, triggers and live stats with level scaling -- dlac equips your gear itself.';

-- Load BEACON ('/dl check' field round, 2026-07-23): written by PLAIN io at
-- the very top of load, before anything else can fail. Its absence after an
-- /addon reload = THIS file did not execute (load error -- Ashita prints it
-- in red -- or a different install); its version line names the code that
-- DID load; the module loop appends its ledger at the bottom of the file.
-- It also exercises the exact write path the debug reports use.
pcall(function()
    local p = AshitaCore:GetInstallPath() .. 'addons\\dlac\\debug\\';
    if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(p); end
    local f = io.open(p .. 'load-report.txt', 'w');
    if f ~= nil then
        f:write(('dlac %s loading at %s\n'):format(addon.version, os.date('%Y-%m-%d %H:%M:%S')));
        f:close();
    end
end);

require('common');

-- Resolve the profile-style "dlac\\X" requires to addons/dlac/X.lua in the addon state.
pcall(function()
    package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';
end);

-- THE IMGUI-BINDING SEAM: newer Ashita builds ship ImGui 1.90+, where
-- BeginChild's border bool became ImGuiChildFlags and ImageButton/Image
-- changed shape -- every dlac call site speaks the OLD shapes. Detect the
-- binding once and wrap the three entries so both builds render; on the old
-- binding this wraps nothing at all. Must run before the first frame -- see
-- lib\imguicompat.lua for the whole story.
pcall(function()
    require('dlac\\lib\\imguicompat').install();
end);

-- THE SERVER SEAM (ADR 0035): discover the shipped server packs, pick the
-- active one, and mount its data files into the virtual dlac\data\ namespace
-- -- BEFORE anything can require data. Every later pcall(require,
-- 'dlac\\data\\X') resolves through the active pack, or degrades exactly as
-- a missing file always has. A failure here means NO pack: neutral defaults,
-- capabilities off, and /dl check says so.
pcall(function()
    require('dlac\\gear\\serverpack').init();
end);

-- Load THIS character's gear from their config folder, so the GUI shows your
-- real gear instead of the bundled empty template. Preloads package.loaded so every
-- module's require("dlac\\gear") returns it. Falls back to the template if none found.
-- Candidate order: the native home (config\addons\dlac\<char>\ -- live when the
-- native-engine flag is on), then the legacy LuaAshitacast homes.
pcall(function()
    local party = AshitaCore:GetMemoryManager():GetParty();
    local name  = party:GetMemberName(0);
    local id    = party:GetMemberServerId(0);
    if name == nil or name == '' or id == nil then return; end
    local candidates = {};
    pcall(function()
        local prof = require('dlac\\profiles');
        local d = prof.dataDir();
        if d ~= nil then candidates[#candidates + 1] = d .. 'gear.lua'; end
    end);
    -- (The legacy-home candidates died in the purge: the boot reads only the
    -- native home; old trees are the IMPORTERS' territory, and auto-migration
    -- carries a straggler's gear.lua in before this matters.)
    for _, p in ipairs(candidates) do
        local present = false;
        local fh = io.open(p, 'r'); if fh ~= nil then present = true; fh:close(); end
        local chunk, lerr = loadfile(p);
        if chunk ~= nil then
            local ok, g = pcall(chunk);
            if ok and type(g) == 'table' then
                package.loaded['dlac\\gear'] = g;   -- routine: no chat line (see the banner)
                break;
            end
            -- A gear.lua that EXISTS but won't load used to fall through in
            -- silence, leaving the bundled empty template in package.loaded: the
            -- GUI shows no gear, every scan calls every item new, and nothing
            -- anywhere says a real inventory is sitting on disk one bad entry
            -- away. Never silent again.
            print('[dlac] gear.lua exists but failed to load: ' .. tostring(g));
            print('[dlac] running on an EMPTY inventory -- /dl commit names the entry at fault.');
        elseif present then
            print('[dlac] gear.lua will not parse: ' .. tostring(lerr));
            print('[dlac] running on an EMPTY inventory until it does.');
        end
    end
end);

-- (The LEGACY SEEDER lived here until the LuaShitacast purge, Phase 1 -- it
-- copied utils/dispatch/chatfmt/profiles.lua + a gear template into
-- config\addons\luashitacast\<char>\dlac\ every 5s so LAC's state could
-- require them. Nothing writes under luashitacast\ anymore: that tree is
-- read-only import/migration territory. See docs/design/lac-purge-plan.md.)

-- The storage watch: the addon loads at Ashita boot -- BEFORE login -- so the
-- gear preload above finds no character; the ~5s watch below retries FOREVER.
-- Its whole job now is the native home: the first-run decision, the one-time
-- auto-migration of legacy data INTO config\addons\dlac\<char>\ (copy only,
-- legacy files stay put), and the fresh-job auto-setup. (The LAC seeding half
-- and the LAC-alive polite ask died in the purge, Phase 1; the coexistence
-- tripwire in equipengine remains the hard backstop against a foreign engine.)
local function maintainStorage()
    -- Native, always (purge Phase 2): no first-run decision, no flag, no
    -- undecided state -- the manufactured-evidence bug family (07-23, 07-27)
    -- is structurally gone. The beat carries legacy data INTO the native home
    -- (engineAutoMigrate -- copy-only, Henrik's keep) and auto-creates a
    -- fresh job's baseline.
    pcall(function()
        local prof = require('dlac\\profiles');
        prof.engineAutoMigrate(print);
        -- FRESH-INSTALL AUTO-SETUP (issue #91): silently create this
        -- character+job's baseline when it is missing -- storage, gear
        -- inventory, base sets, starter triggers -- so a new player never
        -- touches Setup. No-ops until gearui has configured setupui and for
        -- a not-ready job; a disk failure names itself and retries. See
        -- setupui.autoSetupNative for the full gate list.
        pcall(function()
            local setup = require('dlac\\ui\\setupui');
            if type(setup.autoSetupNative) == 'function' then setup.autoSetupNative(); end
        end);
    end);
end
maintainStorage();
local _seedAt = 0;
ashita.events.register('d3d_present', 'dlac-seed-watch', function()
    -- Session-only reset for the bar-LESS Chocobo sibling: the craft/helm/fish
    -- switches get reset for free because their floating bar calls isEnabled()
    -- (-> loadState) every frame; chocoui has no bar, so a stale enabled=true from
    -- last session would let the ENGINE glue riding gear on at login before any
    -- loadState runs. Force it here (idempotent -- self-limits via chocowatch's
    -- _stateLoaded once charDir() is available), OUTSIDE the 5s throttle so it
    -- lands on the first post-login frame, before the engine's first Default read.
    pcall(function()
        local cw = require('dlac\\feature\\chocowatch');
        if type(cw) ~= 'table' then return; end
        if type(cw.loadState) == 'function' then cw.loadState(); end
        -- Drain any dig-obtained item ids the 0x02D packet handler stashed on the
        -- network thread -- ratchet + save + announce here on the MAIN thread.
        if type(cw.pumpObtains) == 'function' then cw.pumpObtains(); end
    end);
    -- The server-pack modules' beat (ADR 0035; the prestige mirror's old
    -- seat, 2026-08-10, now generic): every mounted module's pump, contained.
    -- Main thread only (the chocowatch rule); a no-op with nothing mounted.
    pcall(function()
        local sm = require('dlac\\feature\\servermods');
        if type(sm) == 'table' and type(sm.pump) == 'function' then sm.pump(); end
    end);
    -- The Action sequencer's frame pump (issue #138): advance any live sequence
    -- (verify worn -> fire -> release) against the live gear/command io. A no-op
    -- when idle; contained, so a bad frame never breaks present.
    pcall(function()
        local aseq = require('dlac\\feature\\actionseq');
        if type(aseq) == 'table' and type(aseq.pump) == 'function' then aseq.pump(); end
    end);
    -- The external-claim mailbox's frame pump (2026-08-01): expire lapsed leases,
    -- tell their holders, die with the world. Pumped from HERE, not from a
    -- d3d_present handler of its own, for the actionseq reason AND one of its
    -- own: the engine requires this module lazily, on the first dispatch, so a
    -- self-registered listener would not exist until dlac had already equipped
    -- something -- and an addon that claimed before that would be answered by
    -- nobody. Required here, it is listening from the first frame.
    pcall(function()
        local ex = require('dlac\\feature\\extclaim');
        if type(ex) == 'table' and type(ex._pump) == 'function' then ex._pump(); end
    end);
    -- The engage/target edge service's frame pump (issue #139): the packet_out
    -- handler stashes decoded edges on the NETWORK thread and does nothing else;
    -- this drains them HERE -- debounce, entity name, subscriber callbacks -- so
    -- no chat/IO/entity read ever runs on the packet thread (the chocowatch
    -- rule). A no-op when the queue is empty.
    pcall(function()
        local ew = require('dlac\\feature\\engagewatch');
        if type(ew) == 'table' and type(ew.pump) == 'function' then ew.pump(); end
    end);
    -- The combat state service's beat (feature\combat): engaged / target /
    -- targetChanged / first-swing, published to subscribers once per dispatch
    -- beat. It runs AFTER engagewatch's pump on purpose -- the edges that pump
    -- accepted are what answer `targetChanged` authoritatively this beat. Reads
    -- nothing at all while nothing is subscribed, so it is free on every job that
    -- has no combat helper installed.
    pcall(function()
        local cbt = require('dlac\\feature\\combat');
        if type(cbt) == 'table' and type(cbt.pump) == 'function' then cbt.pump(); end
    end);
    -- The pet vitals service's beat (issue #140): publish presence / HP% / TP /
    -- name to its subscribers once per dispatch beat, so a Job helper's rule
    -- (BST's Reward threshold) sees the same pet the engine does. The service
    -- throttles itself to TICK_S and does not read the world at all while
    -- nothing is subscribed, so this call is free on every other job.
    pcall(function()
        local pv = require('dlac\\feature\\petvitals');
        if type(pv) == 'table' and type(pv.pump) == 'function' then pv.pump(); end
    end);
    -- Job-helper keybinds (2026-07-30): a helper's key exists while you are on
    -- its job with its pill on, so the group is re-synced on a beat rather than
    -- installed once -- there is no job-change event to hang it on, and the
    -- registry leaves an unchanged bind completely alone. Throttled to 1s
    -- inside, and free on a character with no module declaring a key.
    pcall(function()
        local jh = require('dlac\\feature\\jobhelpers');
        if type(jh) == 'table' and type(jh.pumpBinds) == 'function' then jh.pumpBinds(); end
    end);
    if os.clock() < _seedAt then return; end
    _seedAt = os.clock() + 5.0;
    maintainStorage();
end);

-- LuaAshitacast supplies gData inside a profile; a standalone addon doesn't.
-- Provide the shim from feature\nativedata -- FULL LAC-parity providers
-- (player/action/pet/environment/equipment, sig-scan weather + vanatime),
-- which the native engine's dispatch reads and which upgrade the GUI's old
-- zero-stubs (live day/weather for the optimizer bonus) for free. Falls back
-- to a minimal stub if nativedata cannot load. Only defined when the real
-- gData is absent (i.e. always, in the addon state).
if rawget(_G, 'gData') == nil then
    local installed = false;
    pcall(function()
        local nd = require('dlac\\feature\\nativedata');
        local t = nd.build();
        if type(t) == 'table' and type(t.GetPlayer) == 'function' then
            _G.gData = t;
            installed = true;
        end
    end);
    if not installed then
        local JOB = { [1]='WAR',[2]='MNK',[3]='WHM',[4]='BLM',[5]='RDM',[6]='THF',[7]='PLD',[8]='DRK',
                      [9]='BST',[10]='BRD',[11]='RNG',[12]='SAM',[13]='NIN',[14]='DRG',[15]='SMN',[16]='BLU',
                      [17]='COR',[18]='PUP',[19]='DNC',[20]='SCH',[21]='GEO',[22]='RUN' };
        _G.gData = {
            GetPlayer = function()
                local t = { MainJob='?', MainJobSync=0, SubJob=nil, SubJobSync=0, Status=0, IsMoving=false };
                pcall(function()
                    local p = AshitaCore:GetMemoryManager():GetPlayer();
                    if p == nil then return; end
                    t.MainJob      = JOB[p:GetMainJob()] or '?';
                    t.MainJobSync  = p:GetMainJobLevel() or 0;
                    t.SubJob       = JOB[p:GetSubJob()];
                    t.SubJobSync   = p:GetSubJobLevel() or 0;
                    t.MainJobLevel = t.MainJobSync;
                    t.SubJobLevel  = t.SubJobSync;
                end);
                return t;
            end,
            GetWeather             = function() return 0; end,   -- best-effort (optimizer day/weather bonus)
            GetDay                 = function() return 0; end,
            GetElementalOpposition = function() return nil; end,
            GetAugment             = function() return nil; end,
        };
    end
    -- routine (always the case in addon mode): no chat line
end

-- Load the library. Each module registers its own /dl command(s); gearui also registers
-- the GUI render hook. Guarded so one module failing can't take the addon down.
-- Paths are folder-qualified (see the LAYOUT note at the top of this file): only the
-- seeded engine sits flat at the addon root, everything else lives under ui\ / gear\ /
-- feature\. Built by concat, so these names are invisible to a literal require() grep.
-- Module-load LEDGER: every require result of this loop, recorded for
-- '/dl check' (its "modules: N/M loaded" line + issue verdict -- a corrupt or
-- half-synced tree shows up as NAMED failures instead of one scrolled-away
-- chat line). Stashed under a virtual package name so feature\check.lua can
-- read it at command time (the gear-preload package.loaded precedent -- no
-- such file exists on disk, and none may be created).
local ledger = { total = 0, failed = {} };
package.loaded['dlac\\loadledger'] = ledger;
local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
ledger.total = ledger.total + 1;
if not _cfok then ledger.failed[#ledger.failed + 1] = { mod = 'chatfmt', err = tostring(_cfmt) }; end
for _, mod in ipairs({ 'gear', 'feature\\augments', 'gear\\gearoptim', 'gear\\gearimport',
                       'gear\\gearexport', 'gear\\unusedgear',
                       'feature\\useitem', 'feature\\craftwatch',
                       'feature\\synthrun',
                       'ui\\craftbar', 'feature\\helmwatch', 'ui\\helmbar',
                       'feature\\fishwatch', 'ui\\fishbar', 'feature\\chocowatch',
                       'feature\\meritwatch',
                       'feature\\integration', 'feature\\foodwatch',
                       -- (prestigewatch and giftbox left this list for the CEXI
                       -- server pack, ADR 0035 -- servers\cexi\modules\, mounted
                       -- by feature\servermods below.)
                       'feature\\engagewatch', 'feature\\petvitals', 'feature\\combat',
                       'feature\\sendlog', 'feature\\check', 'feature\\debug', 'feature\\report',
                       -- nmtrack AFTER nmlookup: it requires the lookup module at
                       -- load for the disfavour curve, the shipped table and the
                       -- pop kind (the reverse edge is call-time only, so there
                       -- is no cycle -- see the header of either file). nmloot
                       -- (the drop readout) has no load-time edge in either
                       -- direction -- nmlookup reaches it at call time -- so its
                       -- place in this list is only where it reads best.
                       'feature\\nmlookup', 'feature\\nmtrack', 'feature\\nmloot',
                       'feature\\lockstyle',
                       'feature\\lockstyleapply', 'feature\\equipengine',
                       'feature\\engine', 'ui\\gearui',
                       -- jobbrowse is reached through gearui's (and equippedui's)
                       -- guarded try(), so a broken one costs the job picker in
                       -- SILENCE while the ledger still reads "0 failed" -- the
                       -- documented blind spot. Named here so it cannot.
                       'ui\\jobbrowse',
                       'ui\\panelkit', 'feature\\keybinds', 'feature\\modcfg',
                       -- gearpackets AFTER modcfg: it opens a settings store at
                       -- first use. equipengine reaches it at CALL time (it loads
                       -- earlier), so there is no cycle and no load-order trap.
                       'feature\\gearpackets', 'feature\\modapi',
                       'feature\\jobhelpers', 'ui\\jobhelpersui' }) do
    local ok, err = pcall(require, 'dlac\\' .. mod);
    ledger.total = ledger.total + 1;
    if not ok then
        ledger.failed[#ledger.failed + 1] = { mod = mod, err = tostring(err) };
        local m = string.format('failed to load %s: %s', mod, tostring(err));
        if _cfok then _cfmt.err(m); else print('[dlac] ' .. m); end
    end
end

-- Native-engine augment pins: hand the CatsEyeXI private-augment signature
-- reader to the equip engine. INJECTED, never require'd from there --
-- equipengine must stay loadable in the LAC state, where feature\augments
-- cannot (the augmentStringsOf pattern). Without this line an AugKey-pinned
-- set entry (augment-split gear.lua records) would never find its item.
pcall(function()
    local eng = require('dlac\\feature\\equipengine');
    local aug = require('dlac\\feature\\augments');
    if type(aug.signature) == 'function' then eng.augmentKeyOf = aug.signature; end
end);

-- Job helper modules (issue #137): now that the UI host and main GUI are up, scan
-- addons\dlac\jobhelpers\ for drop-in module folders. The loader feeds the SAME
-- ledger (so /dl check counts them and names any failures), contains a wrong-api /
-- throwing / malformed folder to one loud line, then the Job Helpers tab registers
-- to the right of Gear Helpers -- but ONLY when at least one module loaded.
pcall(function()
    local jh = require('dlac\\feature\\jobhelpers');
    local host = require('dlac\\ui\\uihost');
    -- shared services handed to each module's init(deps) hook.
    local deps = { host = host, jobhelpers = jh };
    jh.load(deps);
    local jhui = require('dlac\\ui\\jobhelpersui');
    if type(jhui.init) == 'function' then jhui.init(deps); end
    if type(jhui.maybeRegister) == 'function' then jhui.maybeRegister(host); end
end);

-- Server-pack modules (ADR 0035): mount the active pack's modules\ folders --
-- the code that only exists because THIS server exists (on CEXI: game modes,
-- prestige, the 0x1A4 E-Box family, gift boxes). After the UI host and main
-- GUI so their tray/helper/quick-menu registrations land on live surfaces;
-- failures feed the same ledger under 'server:<name>'.
pcall(function()
    local sm = require('dlac\\feature\\servermods');
    local host = require('dlac\\ui\\uihost');
    sm.load({ host = host });
end);

-- SPINE PROBE (2026-08-05, the field case that bought it): the loop above is an
-- explicit list, and the modules it does NOT name are exactly the ones nothing
-- else can report on. dispatch is the worst of them -- every require of it in
-- the tree is call-time and inside a pcall (gearoracle, gearui, lockstyle,
-- modapi, actionseq), so a dispatch that will not load produces no ledger entry,
-- no chat line and no red text: a friend's clean install lost its starter
-- trigger file to exactly that, and the beacon said "0 failed" the whole time.
-- These are loaded LAST and only if something has not already pulled them in,
-- so the probe cannot change what loads for anyone whose install is healthy --
-- it only makes an existing failure speak. Namespaced `spine:` in the ledger so
-- /dl check can tell a probe result from a load-loop result.
for _, mod in ipairs({ 'dispatch', 'profiles', 'ui\\setupui', 'ui\\triggersui',
                       'gear\\triggermodel', 'ui\\uihost' }) do
    local ok, err = pcall(require, 'dlac\\' .. mod);
    ledger.total = ledger.total + 1;
    if not ok then
        ledger.failed[#ledger.failed + 1] = { mod = 'spine:' .. mod, err = tostring(err) };
        local m = string.format('failed to load %s: %s', mod, tostring(err));
        if _cfok then _cfmt.err(m); else print('[dlac] ' .. m); end
    end
end

-- The beacon's second half: the ledger, appended once the loop is done. A
-- module failure is now readable OFF DISK (addons\dlac\debug\load-report.txt)
-- even when its chat line scrolled away or chat itself is the broken thing.
pcall(function()
    local f = io.open(AshitaCore:GetInstallPath() .. 'addons\\dlac\\debug\\load-report.txt', 'a');
    if f ~= nil then
        f:write(('modules: %d total, %d failed\n'):format(ledger.total, #ledger.failed));
        for _, e in ipairs(ledger.failed) do
            f:write(('FAILED %s: %s\n'):format(tostring(e.mod), tostring(e.err)));
        end
        f:write('load complete\n');
        f:close();
    end
end);

-- GUI keybind: CTRL+K toggles the window. Claimed through the ONE registry
-- (feature\keybinds) like every other bind dlac issues, so it shows up in
-- '/dl binds' and a mode or a Job helper reaching for ^k is refused and told
-- who has it, rather than silently stealing the window's own key. Released on
-- unload -- together with everything else the registry holds -- so no bind
-- outlives the addon.
pcall(function()
    local kb = require('dlac\\feature\\keybinds');
    kb.register('dlac:ui', '^k', '/dl ui', 'dlac window');
end);
ashita.events.register('unload', 'dlac-unbind', function()
    pcall(function() require('dlac\\feature\\keybinds').releaseAll(); end);
end);

-- No load banner (inform by printing as little as possible): Ashita itself
-- reports the addon load, and the /bind above already echoes the CTRL+K bind.
