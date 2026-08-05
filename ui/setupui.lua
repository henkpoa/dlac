--[[
    dlac/setupui.lua

    The Setup / migration machinery (clean-shim writer, starter profile,
    trigger-file seeding, per-job setup-state probe), extracted from gearui (the
    LuaJIT 200-local chunk cap). Pure logic -- the Setup BUTTON and its plan
    popup still render in gearui's header.

    gearui hands over its file/profile helpers ONCE via setup.configure{} right
    after they are defined (the profilesets.configure precedent):
        charBase, jobFile, readFileText, writeFileText,
        ui      -- gearui's live view-state table (the LAC-reload nag flags)
        status  -- setter for gearui's header status line (_augStatus)
]]--

local setup = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local setmgr = try("dlac\\gear\\setmanager");
local print = (function()
    local m = try('dlac\\chatfmt');
    return (m ~= nil and type(m.print) == 'function') and m.print or print;
end)();

local D = nil;   -- deps from gearui (configure below); every entry point no-ops until set
setup.configure = function(deps)
    if type(deps) == 'table' then D = deps; end
end

-- THE SETUP STANDARD (Henrik, 2026-07-17): the only job file dlac ever leaves
-- LIVE is the clean managed shim. An existing file -- ffxi-lac, hand-written
-- LAC, or an old in-place conversion -- is always backed up (verified) into
-- backups\pre-profiles\ and REPLACED by the shim; its old sets, _Priority
-- lists and group tables stay importable from the backup ("Copy from" in the
-- Sets tab, "Scan my Lua" in the Groups tab, lockstyle copy). Convert-in-place
-- (append dispatch shims, keep the old handler logic running underneath) died
-- here: two equip logics fighting in one file is unsupportable at install
-- scale -- see the sync-lag case that ended it.

-- Is the current job's <JOB>.lua on the dlac standard?
--   'ok'      -> the clean managed shim, handlers healthy (the ONLY good state)
--   'wired'   -> touches the dlac library but is NOT the clean shim (an old
--                in-place conversion / hand-wired file / edited shim) -> re-shim
--   'ffxilac' -> an ffxi-lac profile (migrate)
--   'none'    -> a custom/other profile (migrate)
--   'nofile' / 'nojob' -> no profile file / no job.
-- Cached per file; cleared after a Setup run (see below).
local SHIM_MARKER = '-- dlac profile shim';   -- profiles.SHIM_MARKER (kept in sync; stable forever)
local _setupState, _setupStateJob = nil, nil;
setup.jobSetupState = function()
    if D == nil then return 'nojob'; end
    local jf = D.jobFile();
    if jf == nil then return 'nojob'; end
    if _setupStateJob == jf and _setupState ~= nil then return _setupState; end
    local st;
    local text = D.readFileText(jf);
    if text == nil then st = 'nofile';
    elseif text:find(SHIM_MARKER, 1, true) then
        st = 'ok';
        -- shim health: every Handle* must exist and END with its dispatch call.
        -- A hand-edited shim that lost one is 'wired' -> Setup re-shims it.
        if setmgr ~= nil and type(setmgr.analyzeShims) == 'function' then
            local aok, a = pcall(setmgr.analyzeShims, text);
            if aok and type(a) == 'table' and a.healthy ~= true then st = 'wired'; end
        end
    elseif text:find([[dlac\\utils]], 1, true) then st = 'wired';
    elseif text:find('ffxi-lac', 1, true) then st = 'ffxilac';
    else st = 'none'; end
    _setupState, _setupStateJob = st, jf;
    return st;
end

-- (MIGRATE_BOOT and STARTER_PROFILE -- the LAC job-file texts Setup used to
-- write -- died in the purge, Phase 1. Setup writes NO job files anymore: the
-- native engine never reads one, and nothing writes under luashitacast\. The
-- starter content lives on as profile-store seeds: seedSetsFile's four base
-- sets + seedTriggersFile's classic status rules below.)

-- Seed <char>\dlac\triggers\<JOB>.lua with the classic status rules (never clobbers an
-- existing file). The starter text lives in dispatch.lua (single source of truth); the
-- addon-state copy of dispatch is inert but its exports are still readable. Returns true
-- when a file was written.
-- Returns `written, reason`. A nil reason means nothing was wrong (the file was
-- already there); a STRING reason means the seed genuinely failed and names why
-- -- hard rule 12, and the field case that bought it (2026-08-05, a friend's
-- clean install: the trigger file never appeared and every bail-out here was a
-- bare `return false`, so four rounds of guessing could not tell a missing
-- dispatch from an unwritable directory).
setup.seedTriggersFile = function(base, abbr)
    if D == nil then return false, 'setup not configured (no deps)'; end
    if base == nil or abbr == nil then return false, 'no character/job yet'; end
    -- the legacy tier lives in the data home (mode-aware, feature/native-engine)
    local ddir = (type(D.dataDir) == 'function') and D.dataDir() or nil;
    if ddir == nil then ddir = base .. 'dlac\\'; end
    local legacyTierPath = ddir .. 'triggers\\' .. abbr .. '.lua';
    local path = legacyTierPath;
    if D.readFileText(path) ~= nil then return false, nil; end   -- user data: never overwrite
    -- Profile storage live? Seed INTO the active profile instead (and never
    -- clobber a file already there) -- same target the engine resolves.
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) == 'table' and prof.storageExists() then
            local pp = prof.triggersPath(abbr);
            if pp ~= nil then prof.ensureStorage(); path = pp; end
        end
    end);
    if D.readFileText(path) ~= nil then return false, nil; end
    -- The starter text lives on dispatch. dispatch is NOT in dlac.lua's load
    -- ledger and every other require of it is call-time under pcall, so a
    -- dispatch that will not load is invisible everywhere else: this is the one
    -- place that can name it. Split the two failures -- a load error and a
    -- version mismatch need different fixes.
    local ok, dsp = pcall(require, "dlac\\dispatch");
    if not ok then return false, 'dispatch module would not load: ' .. tostring(dsp); end
    if type(dsp) ~= 'table' then return false, 'dispatch module is not a table (got ' .. type(dsp) .. ')'; end
    if type(dsp.starterTriggersText) ~= 'string' then
        return false, 'dispatch has no starterTriggersText string (mismatched dispatch.lua?)';
    end
    -- Create the legacy dir only when the seed actually lands there (profile
    -- storage dirs come from ensureStorage) -- a fresh player owns zero
    -- legacy-layout files AND zero legacy-layout dirs (sim finding, 2026-07-17).
    if path == legacyTierPath then
        pcall(function()
            if ashita and ashita.fs and ashita.fs.create_directory then
                ashita.fs.create_directory(ddir .. 'triggers\\');
            end
        end);
    end
    if D.writeFileText(path, dsp.starterTriggersText) ~= true then
        return false, 'could not write ' .. path .. ' (does its folder exist?)';
    end
    return true, nil;
end

-- Seed the active profile's sets\<JOB>.lua with the four base sets the starter
-- trigger rules target (Idle / Tp_Default / Resting / Movement), EMPTY -- a
-- fresh job equips nothing yet, but the engine never complains about missing
-- trigger targets before the player builds anything (Henrik's field test,
-- 2026-07-17). Never clobbers an existing sets file; travels with
-- seedTriggersFile -- the starter rules and their targets arrive together.
-- Returns `written, reason` on the seedTriggersFile contract above: nil reason =
-- nothing wrong, a string = a real failure that names itself.
setup.seedSetsFile = function(base, abbr)
    if D == nil or base == nil or abbr == nil then return false, 'no character/job yet'; end
    local written, reason = false, nil;
    local ok, err = pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) ~= 'table' or type(prof.frameSetsText) ~= 'function' then
            reason = 'profiles module unavailable or has no frameSetsText'; return;
        end
        prof.ensureStorage();
        local pp = prof.setsPath(abbr);
        if pp == nil then reason = 'no sets path (not logged in?)'; return; end
        if D.readFileText(pp) ~= nil then return; end   -- user data: never overwrite
        local framed = prof.frameSetsText(prof.starterDynText);
        if (loadstring or load)(framed) == nil then reason = 'starter sets text would not parse'; return; end
        written = D.writeFileText(pp, framed) == true;
        if not written then reason = 'could not write ' .. pp .. ' (does its folder exist?)'; end
    end);
    if not ok and reason == nil then reason = 'threw: ' .. tostring(err); end
    return written, reason;
end

-- Seed the data home's gear.lua (the gear inventory) from dlac's OWN bundled
-- template, always. Never clobbers an existing file. The home is mode-aware
-- (feature/native-engine) via D.dataDir.
--
-- It used to PREFER an existing `ffxi-lac\gear.lua` on the LAC char base, to
-- let a returning player keep their scanned inventory. Henrik's ruling,
-- 2026-07-28, after that seeding cost a new player his whole gear import:
-- **dlac handles its own gear locally; the only FFXI-LAC integration is the
-- Dynamic sets import.** The courtesy was never worth it -- a seeded ffxi-lac
-- file is a foreign artifact dlac cannot safely extend:
--   * it can be an OLDER ffxi-lac generation that nests Ammo by category and
--     says so in its own trailer. dlac writes Ammo flat, so commit spliced the
--     new entry in at the wrong depth -- a file that parses and then dies in
--     the trailer (fixed separately, gearimport slotShapes / `2026.07.28e`).
--   * it carries no Id (older generations never stamped one), and RSlot and
--     the Range/Ammo Pair key are looked up BY Id -- so reserved-slot conflicts
--     and ammo pairing were dead for every entry in it.
--   * its Stats blocks are inert (dlac derives stats from the catalog by Id),
--     and its contents are a catalogue, not the player's bags.
-- `/dl scan` rebuilds all of it correctly from the real bags in seconds, which
-- is strictly better than anything the copy could give. The empty template is
-- enough for the profile to load and for Scan/Commit to populate.
-- Returns `written, reason` on the seedTriggersFile contract above.
local function seedGearFile(base)
    local ddir = (type(D.dataDir) == 'function') and D.dataDir() or nil;
    if ddir == nil then ddir = base .. 'dlac\\'; end
    pcall(function() os.execute('mkdir "' .. ddir:gsub('\\+$', '') .. '" 2>nul'); end);
    if D.readFileText(ddir .. 'gear.lua') ~= nil then return false, nil; end
    -- The template ships in the addon folder. A nil read here means the install
    -- is not where we think it is (extracted nested, or the folder renamed) --
    -- name the path we looked at, because that is the whole diagnosis.
    local tpl = AshitaCore:GetInstallPath() .. 'addons\\dlac\\gear.lua';
    local src = D.readFileText(tpl);
    if src == nil then return false, 'bundled gear template missing: ' .. tpl; end
    if D.writeFileText(ddir .. 'gear.lua', src) ~= true then
        return false, 'could not write ' .. ddir .. 'gear.lua (does its folder exist?)';
    end
    return true, nil;
end

-- The ONE migration path (the standard, see the header): every non-shim
-- <JOB>.lua on the character is verified into backups\pre-profiles\ and
-- rewritten as the clean shim (profiles.migrate -- Dynamic sets travel
-- verbatim, legacy trigger files move into the profile, a re-migrated file
-- never overwrites its first backup). Then every job gets its gear inventory
-- and starter triggers seeded (never clobbering), profilesets drops its cache
-- so "Copy from" sees the fresh backups, and LuaAshitacast reloads so the
-- shims go live. One Commit ends with the whole character on the standard.
-- Is the Native engine armed (ADR 0015)? Under native there is no <JOB>.lua
-- shim to write and nothing under LuaAshitacast's tree to back up -- Setup takes
-- the setupNative path instead of any of the legacy migration writers.
setup.isNative = function()
    local on = false;
    pcall(function()
        local p = require('dlac\\profiles');
        if type(p) == 'table' and type(p.nativeMode) == 'function' then on = p.nativeMode() == true; end
    end);
    return on;
end

setup.migrateToCleanProfiles = function()
    if D == nil then return; end
    -- Native mode NEVER writes a <JOB>.lua/shim/backup (ADR 0015 rulings 3+4).
    -- This is the legacy migration writer; refuse it under the native flag so no
    -- caller (a stray /dl profile migrate) can breach the rule.
    if setup.isNative() then
        D.status('Setup: native engine is on -- dlac equips gear itself, so there is no job file to migrate. Use the Setup button (native path) if storage is missing.');
        return;
    end
    local ui = D.ui;
    local base = D.charBase();
    if base == nil then D.status('Setup: log in first (no character folder).'); return; end
    local prof = try('dlac\\profiles');
    if prof == nil then D.status('Setup: profiles module unavailable.'); return; end
    seedGearFile(base);
    local done, _, failed = prof.migrate(true, function(s) pcall(print, s); end);
    for _, job in ipairs(prof.JOBS or {}) do
        if D.readFileText(base .. job .. '.lua') ~= nil then
            setup.seedSetsFile(base, job);       -- no-op for migrated jobs (their sets file exists)
            setup.seedTriggersFile(base, job);
        end
    end
    pcall(function() require('dlac\\gear\\profilesets').invalidate(); end);
    _setupState = nil;
    if (failed or 0) > 0 then
        D.status(string.format('Setup: %d job file(s) FAILED to migrate -- details in chat; a failed job\'s original stays fully in charge. %d migrated.',
            failed, done or 0));
        return;
    end
    if (done or 0) > 0 then
        local msg = string.format('Migrated %d job file(s) of data into the profile store -- originals untouched, backups in backups\\pre-profiles\\ (details in chat). Old sets: Sets tab "Copy from". Old group tables: Triggers tab, Groups, "Scan my Lua".', done);
        D.status(msg);
        pcall(function() print('[dlac] ' .. msg); end);
    else
        D.status('Setup: nothing to migrate -- every job file is already the clean shim.');
    end
end

-- Set up the current job's <JOB>.lua for dlac.
--   'ok'      -> healthy shim (still seeds a missing trigger file, then reports).
--   'nofile'  -> initialize from scratch: write the clean shim, create storage.
--   anything else -> the standard migration (migrateToCleanProfiles above).
-- Also seeds <char>\dlac\gear.lua and a starter triggers\<JOB>.lua so the
-- dispatch shims have data to act on (ADR 0002).
-- The NATIVE Setup path (ADR 0015 rulings 3+4): produce a playable install
-- without a single write under config\addons\luashitacast\. Storage + gear
-- inventory + starter sets/triggers only -- no <JOB>.lua shim, no migration, no
-- backup (what is never written needs none). Everything it seeds is mode-aware
-- (dataDir / profile storage resolve to dlac's own root under the flag) and
-- never clobbers an existing file, so it is safe to re-run. Job-file imports
-- (Sets "Copy from", Groups "Scan my Lua", the pre-profiles corpus) keep reading
-- the LAC tree READ-ONLY in both modes -- untouched here.
setup.setupNative = function(base, abbr)
    if D == nil then return; end
    if base == nil or abbr == nil then D.status('Setup: log in first (no character/job).'); return; end
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) == 'table' and type(prof.ensureStorage) == 'function' then prof.ensureStorage(); end
    end);
    seedGearFile(base);   -- writes the data home (native root under the flag), not the LAC tree
    local seededSets = setup.seedSetsFile(base, abbr);
    local seededTrig = setup.seedTriggersFile(base, abbr);
    if seededSets or seededTrig then pcall(function() require('dlac\\gear\\profilesets').invalidate(); end); end
    _setupState = nil;
    local msg = abbr .. ': native setup complete -- storage and starter sets/triggers are in place under '
        .. 'config\\addons\\dlac\\. dlac equips your gear directly; no LuaAshitacast profile is needed and '
        .. 'no job file was written. Scan your gear, then build sets in the Sets tab.';
    D.status(msg);
    pcall(function() print('[dlac] ' .. msg); end);
end

-- Is this character+job's native baseline all in place on disk? Storage +
-- gear inventory + THIS job's starter sets + THIS job's starter triggers. The
-- auto-setup guard (below) and its success check both ask this: a fresh player
-- is incomplete (seed it), an established one is complete (stay silent), and a
-- brand-new job on an old character is incomplete for its own sets/triggers
-- only. Reads through the same deps the seeders write through, so what it sees
-- is exactly what they just wrote (no torn view between write and verify).
-- Returns `complete, missing` -- missing names the FIRST unmet gate and the path
-- it looked at, so a failure is one line instead of an investigation. The four
-- gates are checked in creation order, which is also the order they depend on
-- each other, so the first miss is the real one.
setup.nativeBaselineComplete = function(abbr)
    if D == nil then return false, 'setup not configured (no deps)'; end
    if abbr == nil then return false, 'no job yet'; end
    local complete, missing = false, nil;
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) ~= 'table' then missing = 'profiles module unavailable'; return; end
        if type(prof.storageExists) == 'function' and prof.storageExists() ~= true then
            local pp = (type(prof.pointerPath) == 'function') and prof.pointerPath() or nil;
            missing = 'storage pointer ' .. tostring(pp); return;
        end
        local ddir = (type(D.dataDir) == 'function') and D.dataDir() or nil;
        if ddir == nil then missing = 'no data home (not logged in?)'; return; end
        if D.readFileText(ddir .. 'gear.lua') == nil then missing = 'gear inventory ' .. ddir .. 'gear.lua'; return; end
        local sp = (type(prof.setsPath) == 'function') and prof.setsPath(abbr) or nil;
        if sp == nil then missing = 'no sets path for ' .. abbr; return; end
        if D.readFileText(sp) == nil then missing = 'sets file ' .. sp; return; end
        -- TRIGGERS ARE TWO-TIER, and this check must agree with the RESOLVERS.
        -- seedTriggersFile bails with "user data: never overwrite" when the
        -- LEGACY TIER file exists, and triggersui.trigFilePath / the engine both
        -- fall back to that tier -- so a legacy-tier file is LIVE and the
        -- baseline really is complete. Accepting only the profile tier here made
        -- the two halves disagree forever (2026-08-05, a migrated character):
        -- engineAutoMigrate copies config\addons\luashitacast\<char>\dlac\ whole
        -- into the native home, which lands the old triggers\<JOB>.lua at
        -- exactly the legacy tier -- so the seeder saw a file and refused, this
        -- check saw none and warned, and it retried every beat for good.
        local tp = (type(prof.triggersPath) == 'function') and prof.triggersPath(abbr) or nil;
        if tp == nil then missing = 'no triggers path for ' .. abbr; return; end
        if D.readFileText(tp) == nil then
            local lt = (type(prof.legacyTriggersPath) == 'function') and prof.legacyTriggersPath(abbr) or nil;
            if lt ~= nil and D.readFileText(lt) ~= nil then complete = true; return; end
        end
        if D.readFileText(tp) == nil then missing = 'triggers file ' .. tp .. ' (and no legacy-tier file either)'; return; end
        complete = true;
    end);
    return complete, missing;
end

-- FRESH-INSTALL AUTO-SETUP (ADR 0015 ruling 4 refined; issue #91). Under the
-- native flag, silently create this character+job's baseline the moment it is
-- missing -- storage, gear inventory, the four base sets, starter triggers (the
-- setupNative content, per job, idempotent, never clobbering) -- so a new player
-- never touches Setup. Called on the login/job beat (dlac.lua maintainStorage).
-- HARD GATES: never for a not-ready job (D.jobFile() returns nil until
-- GetMainJob settles -- hard rule 11, so id-0 'NON' never seeds). A persistent
-- disk failure NAMES itself once and is retried next beat -- it is never
-- ceremonialized into the Setup box. (The legacy-mode and firstRunInit gates
-- died in the purge, Phase 2: every boot is native and decided.)
-- Returns 'seeded' | 'complete' | 'failed' | 'idle' (for the caller + tests).
setup._autoWarned = {};   -- per-job failure-notice throttle (cleared on success)
-- The last seed failure, kept for the artifacts: { job, missing, why, at }.
-- Chat scrolls and the player sends a report, not a screenshot -- so the reason
-- has to survive somewhere /dl check and /dl report can read it. nil = healthy.
setup.lastSeedFail = nil;
setup.autoSetupNative = function()
    if D == nil then return 'idle'; end
    if not setup.isNative() then return 'idle'; end          -- auto-setup NEVER fires in legacy mode
    local base = D.charBase();
    if base == nil then return 'idle'; end                   -- not logged in yet -- retry next beat
    local _, abbr = D.jobFile();
    if abbr == nil then return 'idle'; end                   -- job not ready (id 0 at login) -- retry
    if setup.nativeBaselineComplete(abbr) then
        setup._autoWarned[abbr] = nil;
        return 'complete';                                   -- already set up -- silent (installs boot unchanged)
    end
    -- Missing -> seed it. Every helper checks-then-writes, so this is safe to run
    -- every beat and re-run after a partial failure; nothing is ever overwritten.
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) == 'table' and type(prof.ensureStorage) == 'function' then prof.ensureStorage(); end
    end);
    local _, gearWhy = seedGearFile(base);
    local _, setsWhy = setup.seedSetsFile(base, abbr);
    local _, trigWhy = setup.seedTriggersFile(base, abbr);
    pcall(function() require('dlac\\gear\\profilesets').invalidate(); end);
    _setupState = nil;
    local done, missing = setup.nativeBaselineComplete(abbr);
    if not done then
        -- Every seeder that failed for a REAL reason gets a clause. The gate
        -- says WHAT is missing, the seeder says WHY it could not make it -- the
        -- two halves that used to be a four-round conversation.
        local why = {};
        if gearWhy ~= nil then why[#why + 1] = 'gear: ' .. gearWhy; end
        if setsWhy ~= nil then why[#why + 1] = 'sets: ' .. setsWhy; end
        if trigWhy ~= nil then why[#why + 1] = 'triggers: ' .. trigWhy; end
        setup.lastSeedFail = {   -- read by feature\check (so /dl check and /dl report carry it)
            job = abbr, missing = missing, why = why, at = os.date('%Y-%m-%d %H:%M:%S'),
        };
        if not setup._autoWarned[abbr] then
            setup._autoWarned[abbr] = true;   -- one loud line, then keep retrying quietly
            local m = abbr .. ': dlac could not create its native starter files under config\\addons\\dlac\\ '
                .. '-- missing ' .. tostring(missing or '(unknown)')
                .. (#why > 0 and ('; ' .. table.concat(why, '; ')) or '')
                .. ' -- it will keep trying (/dl check has the detail).';
            D.status(m);
            pcall(function() print('[dlac] ' .. m); end);
        end
        return 'failed';
    end
    setup.lastSeedFail = nil;
    setup._autoWarned[abbr] = nil;
    -- A successful seed is SILENT (Henrik, 07-23, post-field-confirm: the
    -- player is not told about first runs, engines, or scanning -- the gear
    -- inventory auto-syncs from bags and everything just works). Only the
    -- failure above speaks, once, because a broken seed must name itself.
    return 'seeded';
end

-- Does this character have dlac data worth migrating? The storage pointer is the
-- primary signal (every creator writes it); a pre-storage-move legacy user with
-- only a scanned gear.lua still counts. Read through the current-mode data home.
setup.hasDlacData = function()
    local has = false;
    pcall(function()
        local p = require('dlac\\profiles');
        if type(p) == 'table' and type(p.storageExists) == 'function' and p.storageExists() == true then has = true; end
    end);
    if has then return true; end
    if D ~= nil and type(D.dataDir) == 'function' then
        local d = D.dataDir();
        if d ~= nil and D.readFileText(d .. 'gear.lua') ~= nil then return true; end
    end
    return false;
end

-- (THE MIGRATION COMMIT died in the purge, Phase 2: there is no engine flip
-- left to commit. Storage migration is AUTOMATIC on login (engineAutoMigrate,
-- copy-only) and `/dl engine migrate` re-runs the copy by hand -- both kept,
-- Henrik's call. This stub answers any surface still wired to the old button.)
setup.migrateToNative = function()
    if D == nil then return; end
    D.status('Migration is automatic now: legacy data is copied to config\\addons\\dlac\\ at login (nothing under luashitacast\\ is ever changed). /dl engine migrate re-runs the copy by hand.');
end

-- Does this character still need the Migrate button (issue #91 -- needsSetup v2;
-- renamed from 'Setup' by Henrik's 07-23 ruling -- migration is its one job)?
-- NATIVE: always false -- fresh installs are auto-set-up and there is nothing to
-- migrate. LEGACY: true iff the character has dlac data, meaning "migration
-- offered" -- the red Migrate button is then the standing nudge (present all
-- session) and the popup is the migration box. A legacy session with no dlac
-- data has nothing to migrate (and never happens for a fresh install -- those
-- are born native).
setup.needsSetup = function()
    if setup.isNative() then return false; end
    return setup.hasDlacData();
end

setup.migrateCurrentJob = function()
    if D == nil then return; end
    local ui = D.ui;
    local base = D.charBase();
    if base == nil then D.status('Setup: log in first (no character folder).'); return; end
    local jf, abbr = D.jobFile();
    if jf == nil then D.status('Setup: unknown job.'); return; end
    -- NATIVE (ADR 0015): dlac equips gear itself -- no shim, no migration, no
    -- backup. The legacy path below is unchanged for flag-off users.
    if setup.isNative() then return setup.setupNative(base, abbr); end
    local state = setup.jobSetupState();

    if state == 'ok' then
        local seededSets = setup.seedSetsFile(base, abbr);
        local seeded = setup.seedTriggersFile(base, abbr);
        if seededSets or seeded then pcall(function() require('dlac\\gear\\profilesets').invalidate(); end); end
        D.status(abbr .. '.lua is already set up for dlac.'
            .. (seededSets and '  Seeded the four empty base sets.' or '')
            .. (seeded and ('  Seeded starter triggers\\' .. abbr .. '.lua.') or ''));
        return;
    end
    if state ~= 'nofile' then
        -- An existing file NEVER stays live, whatever is in it (the standard).
        return setup.migrateToCleanProfiles();
    end

    seedGearFile(base);
    -- Fresh job: create profile storage BEFORE the trigger seed, so the starter
    -- triggers land INSIDE the profile (field case: run 1 of the fresh-start
    -- test seeded them into the legacy dlac\triggers\ because storage did not
    -- exist yet at this point -- reads fall back so it worked, but a brand-new
    -- player should own zero legacy-layout files).
    pcall(function() local p = require('dlac\\profiles'); if type(p) == 'table' then p.ensureStorage(); end end);
    -- the four empty base sets + the starter trigger file that targets them, so
    -- the profile's dispatch shims run out of the box without a single complaint.
    setup.seedSetsFile(base, abbr);
    setup.seedTriggersFile(base, abbr);
    pcall(function() require('dlac\\gear\\profilesets').invalidate(); end);

    -- NEW players go profile-native from minute one -- storage created, base
    -- sets + starter triggers seeded above, every set/trigger they ever build
    -- lands under profiles\. NO job file is written (purge Phase 1: the native
    -- engine never reads one, and nothing writes under luashitacast\ -- the
    -- LAC-era Setup used to place the managed shim here).
    _setupState = nil;
    local msg = string.format('%s ready -- storage, base sets and starter triggers created.', abbr);
    D.status(msg);
    pcall(function() print('[dlac] ' .. msg); end);
end

return setup;
