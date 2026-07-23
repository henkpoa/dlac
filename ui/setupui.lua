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

-- One-line bootstrap that puts the dlac addon library on the profile's package.path so
-- require("dlac\\utils") resolves to the addon. [[...]] keeps the backslashes literal.
local MIGRATE_BOOT = [[package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';  -- dlac: use the dlac addon library]];

-- Starter profile written when a job has no dlac profile yet. This mirrors LuaAshitacast's
-- own `/lac newlua` skeleton (OnLoad/AllowAddSet kept, so `/lac addset` works) and adds the
-- dlac wiring: the require, a Dynamic sets scaffold, `utils.rebuildSets(sets)` plus a
-- `utils.dispatch('<Handler>')` shim in every handler (ADR 0002). ALL equip logic is data
-- in <char>\dlac\triggers\<JOB>.lua -- Setup seeds it with the classic status rules
-- (Engaged/Resting/Movement/Idle) so a fresh profile behaves out of the box. Build sets in
-- the GUI (Sets tab); wire behavior in the Triggers tab (or edit the trigger file directly).
-- MIGRATE_BOOT is prepended when written so LAC can resolve require("dlac\\utils"). Inside
-- [[...]] the backslashes are literal on purpose.
local STARTER_PROFILE = [[
local profile = {};
local utils = require("dlac\\utils");   -- everything comes through this one require
local gear  = utils.gear;               -- the shared gear inventory
local sets = {
    Dynamic = {                         -- dlac: build these in the GUI (Sets tab); best-per-level is auto-picked
        Idle       = {},
        Tp_Default = {},
        Resting    = {},
        Movement   = {},
    },
};
profile.Sets = sets;

profile.Packer = {
};

profile.OnLoad = function()
    gSettings.AllowAddSet = true;
end

profile.OnUnload = function()
end

profile.HandleCommand = function(args)
end

-- All equip logic is data: utils.dispatch reads <char>\dlac\triggers\<JOB>.lua
-- (hot-reloaded -- edit triggers in the dlac GUI or the file; no /lac reload needed).
profile.HandleDefault = function()
    sets = utils.rebuildSets(sets);
    utils.dispatch('Default');
end

profile.HandleAbility     = function() utils.dispatch('Ability');     end
profile.HandleItem        = function() utils.dispatch('Item');        end
profile.HandlePrecast     = function() utils.dispatch('Precast');     end
profile.HandleMidcast     = function() utils.dispatch('Midcast');     end
profile.HandlePreshot     = function() utils.dispatch('Preshot');     end
profile.HandleMidshot     = function() utils.dispatch('Midshot');     end
profile.HandleWeaponskill = function() utils.dispatch('Weaponskill'); end

return profile;
]];

-- Seed <char>\dlac\triggers\<JOB>.lua with the classic status rules (never clobbers an
-- existing file). The starter text lives in dispatch.lua (single source of truth); the
-- addon-state copy of dispatch is inert but its exports are still readable. Returns true
-- when a file was written.
setup.seedTriggersFile = function(base, abbr)
    if D == nil then return false; end
    if base == nil or abbr == nil then return false; end
    -- the legacy tier lives in the data home (mode-aware, feature/native-engine)
    local ddir = (type(D.dataDir) == 'function') and D.dataDir() or nil;
    if ddir == nil then ddir = base .. 'dlac\\'; end
    local legacyTierPath = ddir .. 'triggers\\' .. abbr .. '.lua';
    local path = legacyTierPath;
    if D.readFileText(path) ~= nil then return false; end   -- user data: never overwrite
    -- Profile storage live? Seed INTO the active profile instead (and never
    -- clobber a file already there) -- same target the engine resolves.
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) == 'table' and prof.storageExists() then
            local pp = prof.triggersPath(abbr);
            if pp ~= nil then prof.ensureStorage(); path = pp; end
        end
    end);
    if D.readFileText(path) ~= nil then return false; end
    local ok, dsp = pcall(require, "dlac\\dispatch");
    if not ok or type(dsp) ~= 'table' or type(dsp.starterTriggersText) ~= 'string' then return false; end
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
    return D.writeFileText(path, dsp.starterTriggersText);
end

-- Seed the active profile's sets\<JOB>.lua with the four base sets the starter
-- trigger rules target (Idle / Tp_Default / Resting / Movement), EMPTY -- a
-- fresh job equips nothing yet, but the engine never complains about missing
-- trigger targets before the player builds anything (Henrik's field test,
-- 2026-07-17). Never clobbers an existing sets file; travels with
-- seedTriggersFile -- the starter rules and their targets arrive together.
setup.seedSetsFile = function(base, abbr)
    if D == nil or base == nil or abbr == nil then return false; end
    local written = false;
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) ~= 'table' or type(prof.frameSetsText) ~= 'function' then return; end
        prof.ensureStorage();
        local pp = prof.setsPath(abbr);
        if pp == nil or D.readFileText(pp) ~= nil then return; end   -- user data: never overwrite
        local framed = prof.frameSetsText(prof.starterDynText);
        if (loadstring or load)(framed) ~= nil then written = D.writeFileText(pp, framed) == true; end
    end);
    return written;
end

-- Seed the data home's gear.lua (the gear inventory): copied from an existing
-- ffxi-lac\gear.lua when there is one (a returning player keeps their scanned
-- inventory), else the bundled empty template so the profile loads and
-- Scan/Commit can populate it. Never clobbers an existing file. The home is
-- mode-aware (feature/native-engine) via D.dataDir; the ffxi-lac source stays
-- on the LAC char base -- that is where a pre-migration profile ever lived.
local function seedGearFile(base)
    local ddir = (type(D.dataDir) == 'function') and D.dataDir() or nil;
    if ddir == nil then ddir = base .. 'dlac\\'; end
    pcall(function() os.execute('mkdir "' .. ddir:gsub('\\+$', '') .. '" 2>nul'); end);
    if D.readFileText(ddir .. 'gear.lua') ~= nil then return; end
    local src = D.readFileText(base .. 'ffxi-lac\\gear.lua');
    if src == nil then src = D.readFileText(AshitaCore:GetInstallPath() .. 'addons\\dlac\\gear.lua'); end
    if src ~= nil then D.writeFileText(ddir .. 'gear.lua', src); end
end

-- The ONE migration path (the standard, see the header): every non-shim
-- <JOB>.lua on the character is verified into backups\pre-profiles\ and
-- rewritten as the clean shim (profiles.migrate -- Dynamic sets travel
-- verbatim, legacy trigger files move into the profile, a re-migrated file
-- never overwrites its first backup). Then every job gets its gear inventory
-- and starter triggers seeded (never clobbering), profilesets drops its cache
-- so "Copy from" sees the fresh backups, and LuaAshitacast reloads so the
-- shims go live. One Commit ends with the whole character on the standard.
setup.migrateToCleanProfiles = function()
    if D == nil then return; end
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
        local msg = string.format('Moved %d job file(s) to the clean dlac standard -- originals in backups\\pre-profiles\\ (details in chat). Old sets: Sets tab "Copy from". Old group tables: Triggers tab, Groups, "Scan my Lua". Reloading LuaAshitacast...', done);
        D.status(msg);
        pcall(function() print('[dlac] ' .. msg); end);
        ui._lacReloadNeed, ui._lacReloadStamp0 = true, ui._lacStamp;   -- red until the auto-reload lands
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/addon reload luashitacast'); end);
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
setup.migrateCurrentJob = function()
    if D == nil then return; end
    local ui = D.ui;
    local base = D.charBase();
    if base == nil then D.status('Setup: log in first (no character folder).'); return; end
    local jf, abbr = D.jobFile();
    if jf == nil then D.status('Setup: unknown job.'); return; end
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

    -- NEW players go profile-native from minute one -- the job file is the
    -- managed shim, storage is created, and every set/trigger they ever build
    -- lands under dlac\profiles\. They never own a legacy-style file at all.
    -- Falls back to the embedded starter only if profiles.lua is unavailable.
    local starter = MIGRATE_BOOT .. '\n' .. STARTER_PROFILE;
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) == 'table' and type(prof.shimFileText) == 'function' then
            starter = prof.shimFileText();
            prof.ensureStorage();
        end
    end);
    if D.writeFileText(jf, starter) then
        _setupState = nil;
        local msg = string.format('Initialized a dlac %s.lua. Reload LuaAshitacast, then build sets and triggers in the GUI.', abbr);
        D.status(msg);
        ui._lacReloadNeed, ui._lacReloadStamp0 = true, ui._lacStamp;   -- red until the reload lands
        pcall(function() print('[dlac] ' .. msg); end);
    else
        D.status('Setup: could not write ' .. jf);
    end
end

return setup;
