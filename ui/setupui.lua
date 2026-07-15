--[[
    dlac/setupui.lua

    The Setup / migration machinery (convert-in-place writer, starter profile,
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

-- Is the current job's <JOB>.lua already wired for dlac?
--   'ok'      -> requires the dlac library AND every handler ends in utils.dispatch (healthy)
--   'shims'   -> requires the library but one or more handlers lack the dispatch shim
--   'ffxilac' -> still an ffxi-lac profile (needs conversion)
--   'none'    -> a custom/other profile (needs in-place conversion -- logic is KEPT)
--   'nofile' / 'nojob' -> no profile file / no job.
-- Cached per file; cleared after a Setup run (see below).
local _setupState, _setupStateJob = nil, nil;
setup.jobSetupState = function()
    if D == nil then return 'nojob'; end
    local jf = D.jobFile();
    if jf == nil then return 'nojob'; end
    if _setupStateJob == jf and _setupState ~= nil then return _setupState; end
    local st;
    local text = D.readFileText(jf);
    if text == nil then st = 'nofile';
    elseif text:find([[dlac\\utils]], 1, true) then
        st = 'ok';
        -- per-handler shim health: every Handle* must exist and END with its dispatch call
        if setmgr ~= nil and type(setmgr.analyzeShims) == 'function' then
            local aok, a = pcall(setmgr.analyzeShims, text);
            if aok and type(a) == 'table' and a.healthy ~= true then st = 'shims'; end
        end
    elseif text:find('ffxi-lac', 1, true) then st = 'ffxilac';
    else st = 'none'; end
    _setupState, _setupStateJob = st, jf;
    return st;
end

-- One-line bootstrap that puts the dlac addon library on the profile's package.path so
-- require("dlac\\utils") resolves to the addon. [[...]] keeps the backslashes literal.
local MIGRATE_BOOT = [[package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';  -- dlac: use the dlac addon library]];

-- Transform ffxi-lac profile text -> dlac: repoint requires/loadfile + add the addon lib
-- to package.path (idempotent). Returns the new text.
setup.migrateJobText = function(text)
    local out = (text:gsub('ffxi%-lac', 'dlac'));
    if not out:find([[addons\\?.lua]], 1, true) then out = MIGRATE_BOOT .. '\n' .. out; end
    return out;
end

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
    local path = base .. 'dlac\\triggers\\' .. abbr .. '.lua';
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
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory(base .. 'dlac\\triggers\\');
        end
    end);
    return D.writeFileText(path, dsp.starterTriggersText);
end

-- Set up the current job's <JOB>.lua for dlac. Convert-IN-PLACE policy: an existing
-- profile's own logic is NEVER removed or replaced -- Setup only adds the dlac require,
-- appends `utils.dispatch('<H>')` at the END of each existing handler (their code runs
-- first; dlac overlays last), and creates the handlers they don't have. Idempotent:
-- clicking Setup on a healthy profile changes nothing.
--   'ok'      -> healthy (still seeds a missing trigger file, then reports).
--   'shims'   -> dlac profile missing shims -> repair (setmanager.repairShims).
--   'ffxilac' -> repoint requires at dlac (backup .flbak), then repair shims.
--   'none'    -> custom profile: backup .flbak, add bootstrap+require, repair shims.
--   'nofile'  -> initialize from scratch: write the self-contained dlac starter.
-- Also seeds <char>\dlac\ with a gear.lua (from an existing ffxi-lac folder, else the
-- bundled empty template) and a starter triggers\<JOB>.lua so the dispatch shims have
-- data to act on (ADR 0002).
setup.migrateCurrentJob = function()
    if D == nil then return; end
    local ui = D.ui;
    local base = D.charBase();
    if base == nil then D.status('Setup: log in first (no character folder).'); return; end
    local jf, abbr = D.jobFile();
    if jf == nil then D.status('Setup: unknown job.'); return; end
    local state = setup.jobSetupState();

    if state == 'ok' then
        local seeded = setup.seedTriggersFile(base, abbr);
        D.status(abbr .. '.lua is already set up for dlac.'
            .. (seeded and ('  Seeded starter triggers\\' .. abbr .. '.lua.') or ''));
        return;
    end

    -- seed <char>\dlac\ from an existing ffxi-lac setup, if present (never clobbered)
    pcall(function() os.execute('mkdir "' .. base .. 'dlac" 2>nul'); end);
    for _, f in ipairs({ 'gear.lua', 'gcinclude.lua', 'gcdisplay.lua' }) do
        if D.readFileText(base .. 'dlac\\' .. f) == nil then
            local src = D.readFileText(base .. 'ffxi-lac\\' .. f);
            if src ~= nil then D.writeFileText(base .. 'dlac\\' .. f, src); end
        end
    end
    -- fresh users have no ffxi-lac to copy: seed an empty gear.lua from the bundled template
    -- so the profile loads and Scan/Commit can populate it.
    if D.readFileText(base .. 'dlac\\gear.lua') == nil then
        local tmpl = D.readFileText(AshitaCore:GetInstallPath() .. 'addons\\dlac\\gear.lua');
        if tmpl ~= nil then D.writeFileText(base .. 'dlac\\gear.lua', tmpl); end
    end
    -- Fresh job: create profile storage BEFORE the trigger seed, so the starter
    -- triggers land INSIDE the profile (field case: run 1 of the fresh-start
    -- test seeded them into the legacy dlac\triggers\ because storage did not
    -- exist yet at this point -- reads fall back so it worked, but a brand-new
    -- player should own zero legacy-layout files).
    if state == 'nofile' then
        pcall(function() local p = require('dlac\\profiles'); if type(p) == 'table' then p.ensureStorage(); end end);
    end
    -- and the starter trigger file, so the profile's dispatch shims equip out of the box.
    setup.seedTriggersFile(base, abbr);

    if state == 'nofile' then
        -- Nothing to convert: NEW players go profile-native from minute one --
        -- the job file is the managed shim, storage is created, and every set/
        -- trigger they ever build lands under dlac\profiles\. They never own a
        -- legacy-style file at all. Falls back to the embedded starter only if
        -- profiles.lua is somehow unavailable.
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
        return;
    end

    -- Existing profile ('ffxilac' | 'none' | 'shims'): convert in place.
    if state == 'ffxilac' or state == 'none' then
        local text = D.readFileText(jf);
        if text == nil then D.status('Setup: could not read ' .. jf); return; end
        D.writeFileText(jf .. '.flbak', text);   -- one-time backup of the pre-dlac original
        if state == 'ffxilac' then
            text = setup.migrateJobText(text);   -- repoint ffxi-lac requires (adds the bootstrap)
        elseif not text:find([[addons\\?.lua]], 1, true) then
            text = MIGRATE_BOOT .. '\n' .. text;   -- make require("dlac\\...") resolvable
        end
        if not D.writeFileText(jf, text) then D.status('Setup: could not write ' .. jf); return; end
    end

    -- Append the dispatch shims (creates missing handlers; adds the require if absent).
    -- setmanager parse-checks and keeps its own rotated backup; aborts untouched on failure.
    local okr, report, bpath = false, 'setmanager unavailable', nil;
    if setmgr ~= nil and type(setmgr.repairShims) == 'function' then
        local pok = pcall(function() okr, report, bpath = setmgr.repairShims(abbr); end);
        if not pok then okr, report = false, 'internal error'; end
    end
    _setupState = nil;
    if okr ~= true then
        D.status(string.format('Setup: shim wiring failed (%s). Your original is safe (%s.lua.flbak / backups).',
            tostring(report), abbr));
        return;
    end
    local parts, warns = {}, {};
    if type(report) == 'table' then
        if report.requireAdded         then parts[#parts + 1] = 'require added'; end
        if #(report.created or {}) > 0 then parts[#parts + 1] = 'created ' .. table.concat(report.created, '/'); end
        if #(report.appended or {}) > 0 then parts[#parts + 1] = 'shimmed ' .. table.concat(report.appended, '/'); end
        if #(report.moved or {}) > 0   then parts[#parts + 1] = 'moved ' .. table.concat(report.moved, '/'); end
        warns = report.warnings or {};
        for _, w in ipairs(warns) do pcall(function() print('[dlac] setup: ' .. w); end); end
    end
    if #parts == 0 and #warns > 0 then
        -- Nothing auto-fixable: saying "no changes needed" while the shim banner
        -- stays red reads as a contradiction -- surface the blockers instead.
        local msg = string.format('Setup could not auto-fix %s.lua: %s', abbr, table.concat(warns, '; '));
        D.status(msg);
        pcall(function() print('[dlac] ' .. msg); end);
        return;
    end
    local msg = string.format(
        'Set up %s.lua in place (%s). Your own handler logic was kept -- dlac dispatch runs last. Reload LuaAshitacast to apply.',
        abbr, (#parts > 0) and table.concat(parts, ', ') or 'no changes needed');
    D.status(msg);
    if #parts > 0 then ui._lacReloadNeed, ui._lacReloadStamp0 = true, ui._lacStamp; end   -- red until the reload lands
    pcall(function() print('[dlac] ' .. msg); end);
end

return setup;
