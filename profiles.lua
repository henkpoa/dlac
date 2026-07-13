--[[
    dlac/profiles.lua -- the profile storage layer.

    A PROFILE is a named bundle of dlac-owned per-job data:
        <char>\dlac\profiles\<Name>\sets\<JOB>.lua      committed Dynamic sets
        <char>\dlac\profiles\<Name>\triggers\<JOB>.lua  trigger rules
    The ACTIVE pointer lives in <char>\dlac\profile.lua (return { active = 'Name' }).
    LAC keeps auto-loading <JOB>.lua on a job change -- that file is (or becomes) a
    thin shim; the ENGINE resolves "active profile + current job" and installs the
    right data. So the profile picks the FOLDER and the job picks the FILE in it.

    Compatibility rule (one rule, everywhere):
      * READS  fall back per file: profile path first, else the legacy location
        (sets.Dynamic inside <JOB>.lua; dlac\triggers\<JOB>.lua). Unmigrated
        characters behave exactly as before.
      * WRITES always land in profile storage (creating 'Default' on first use).
        dlac never writes a <JOB>.lua again -- except the one-time opt-in
        migration, which backs the file up first and says so loudly.

    This module is loaded from BOTH Lua states (it is seeded to <char>\dlac\ next
    to utils/dispatch by dlac.lua), and headlessly by tests\run_tests.lua -- so
    every AshitaCore / fs touch happens at CALL time behind pcall, never at load.
]]--

local M = {};

M.JOBS = { 'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG',
           'SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN' };

-- ---------------------------------------------------------------------------
-- paths
-- ---------------------------------------------------------------------------

-- LuaAshitacast's gState inside a profile, else the party manager (addon state).
-- Returns <install>\config\addons\luashitacast\<Name>_<id>\, or nil pre-login.
local function charBase()
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
    if name == nil or id == nil then return nil; end
    return string.format('%sconfig\\addons\\luashitacast\\%s_%u\\', AshitaCore:GetInstallPath(), name, id);
end
M.charBase = charBase;

function M.pointerPath()
    local b = charBase(); return b and (b .. 'dlac\\profile.lua') or nil;
end
function M.profilesRoot()
    local b = charBase(); return b and (b .. 'dlac\\profiles\\') or nil;
end
function M.profileDir(name)
    local r = M.profilesRoot(); return r and (r .. name .. '\\') or nil;
end
function M.setsPath(job, name)
    local d = M.profileDir(name or M.activeName()); return d and (d .. 'sets\\' .. job .. '.lua') or nil;
end
function M.triggersPath(job, name)
    local d = M.profileDir(name or M.activeName()); return d and (d .. 'triggers\\' .. job .. '.lua') or nil;
end
function M.legacyTriggersPath(job)
    local b = charBase(); return b and (b .. 'dlac\\triggers\\' .. job .. '.lua') or nil;
end
function M.jobFilePath(job)
    local b = charBase(); return b and (b .. job .. '.lua') or nil;
end
-- The migration backup home. backups\ is the established dlac backup dir
-- (setmanager rotation, gearimport); pre-profiles\ holds the ORIGINALS --
-- written once, never overwritten, and the Sets tab's "Copy from static"
-- keeps reading statics out of them forever.
function M.backupPath(job)
    local b = charBase(); return b and (b .. 'backups\\pre-profiles\\' .. job .. '.lua') or nil;
end
function M.triggerBackupPath(job)
    local b = charBase(); return b and (b .. 'backups\\pre-profiles\\triggers\\' .. job .. '.lua') or nil;
end

local function readFile(p)
    if p == nil then return nil; end
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end
local function writeFile(p, t)
    if p == nil then return false; end
    local f = io.open(p, 'w'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end
M._readFile = readFile;

local function ensureDir(p)
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(p); end
    end);
end

-- Create the whole storage skeleton for a profile (+ the pointer if absent, so
-- storageExists() flips true the moment anything profile-shaped is created).
function M.ensureStorage(name)
    name = name or M.activeName();
    local b = charBase(); if b == nil then return false; end
    ensureDir(b .. 'dlac\\');
    ensureDir(b .. 'dlac\\profiles\\');
    ensureDir(b .. 'dlac\\profiles\\' .. name .. '\\');
    ensureDir(b .. 'dlac\\profiles\\' .. name .. '\\sets\\');
    ensureDir(b .. 'dlac\\profiles\\' .. name .. '\\triggers\\');
    if readFile(M.pointerPath()) == nil then M.setActive(name); end
    return true;
end

-- ---------------------------------------------------------------------------
-- active profile pointer
-- ---------------------------------------------------------------------------

-- Profile names travel through chat commands and become folder names: keep them
-- to one word of [A-Za-z0-9_-]. Returns the name or nil.
function M.sanitizeName(name)
    if type(name) ~= 'string' then return nil; end
    return name:match('^[%w_%-]+$');
end

-- Throttled to one disk read per second (the lock-mirror pattern): the OTHER Lua
-- state may rewrite the pointer at any time, so a plain cache would go stale.
local _act = { at = -1, name = nil };
function M.activeName()
    local now = os.time();
    if _act.at == now and _act.name ~= nil then return _act.name; end
    _act.at = now;
    local nm = 'Default';
    pcall(function()
        local chunk = loadfile(M.pointerPath());
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' and M.sanitizeName(t.active) then nm = t.active; end
    end);
    _act.name = nm;
    return nm;
end
function M.invalidate() _act.at = -1; _act.name = nil; end

function M.setActive(name)
    name = M.sanitizeName(name);
    if name == nil then return false, 'bad profile name (letters/digits/_/- only)'; end
    local p = M.pointerPath();
    if p == nil then return false, 'not logged in'; end
    local b = charBase();
    ensureDir(b .. 'dlac\\');
    local ok = writeFile(p, string.format(
        '-- dlac active profile pointer -- written by /dl profile use (hand edits are fine).\nreturn { active = %q };\n', name));
    M.invalidate();
    return ok, ok and nil or ('could not write ' .. p);
end

-- Storage exists iff the pointer file does. Every creator (ensureStorage, migrate,
-- first commit) writes the pointer, so this stays a single deterministic signal.
-- A hand-dropped profiles\ folder becomes live via /dl profile use <name>.
function M.storageExists()
    return readFile(M.pointerPath()) ~= nil;
end

-- ashita.fs.get_dir FIELD SEMANTICS (screenshot-verified 2026-07-13): the mask
-- is a REGEX, not a Lua pattern -- '.*%.lua' matches NOTHING (the '%' is
-- literal), which is why profile file lists came back empty; and the third
-- argument means RECURSIVE -- true returns relative paths of files AND
-- directories ('Default\sets\BLU.lua'), which is how the whole subtree got
-- listed as "profiles". So: always mask '.*', never recurse, filter Lua-side.
local function rawList(path)
    if path == nil then return nil; end
    local out = nil;
    pcall(function()
        if not (ashita and ashita.fs and ashita.fs.get_dir) then return; end
        local ok, t = pcall(ashita.fs.get_dir, path, '.*', false);
        if ok and type(t) == 'table' then out = t; end
    end);
    return out;
end

-- Best-effort name listing (files and dirs MIXED -- get_dir does not say
-- which; callers filter by shape). Shell `dir /b /ad` fallback is dirs-only.
local function listDirs(path)
    if path == nil then return nil; end
    local out = rawList(path);
    if out ~= nil then
        local acc = {};
        for _, d in ipairs(out) do
            if type(d) == 'string' and d ~= '.' and d ~= '..' then acc[#acc + 1] = d; end
        end
        out = acc;
    else
        pcall(function()
            local p = io.popen('dir /b /ad "' .. path .. '" 2>nul');
            if p == nil then return; end
            local acc = {};
            for line in p:lines() do
                line = line:gsub('%s+$', '');
                if line ~= '' then acc[#acc + 1] = line; end
            end
            p:close();
            out = acc;
        end);
    end
    if out ~= nil then table.sort(out); end
    return out;
end

-- Best-effort *.lua basenames in a directory (get_dir file mode is the
-- field-proven setmanager pattern; `dir /b` popen fallback). nil when both
-- APIs fail; {} when the directory is empty/missing.
local function listLuaFiles(path)
    if path == nil then return nil; end
    local out = nil;
    do
        local raw = rawList(path);   -- mask must be '.*' (regex); filter here
        if raw ~= nil then
            out = {};
            for _, f in ipairs(raw) do
                if type(f) == 'string' then
                    local b = f:match('^(.+)%.lua$');
                    if b ~= nil then out[#out + 1] = b; end
                end
            end
        end
    end
    if out == nil then
        pcall(function()
            local p = io.popen('dir /b "' .. path .. '*.lua" 2>nul');
            if p == nil then return; end
            local acc = {};
            for line in p:lines() do
                local b = line:gsub('%s+$', ''):match('^(.+)%.lua$');
                if b ~= nil then acc[#acc + 1] = b; end
            end
            p:close();
            out = acc;
        end);
    end
    return out;
end

-- Best-effort list of THIS character's profile folder names (nil when no
-- listing API works -- callers should fall back to naming the active profile).
function M.listProfiles()
    return listDirs(M.profilesRoot());
end

-- ---------------------------------------------------------------------------
-- cross-character browsing + import (the Profiles menu)
--
-- Every character on the install has its own <Name>_<ServerId> folder under
-- config\addons\luashitacast\ -- that folder IS the account/character axis.
-- A dlac profile is just files, so import = copy a profile's per-job files
-- from another character's storage into this character's, under a new name.
-- ---------------------------------------------------------------------------

function M.lacRoot()
    local ok, p = pcall(function()
        return AshitaCore:GetInstallPath() .. 'config\\addons\\luashitacast\\';
    end);
    return ok and p or nil;
end

-- Character folders (<Name>_<Id>), current one first, rest alphabetical.
function M.listCharFolders()
    local root = M.lacRoot();
    local dirs = listDirs(root);
    if dirs == nil then return nil; end
    local cur = nil;
    pcall(function() local b = charBase(); if b ~= nil then cur = b:match('([^\\]+)\\$'); end end);
    local out = {};
    for _, d in ipairs(dirs) do
        if d:match('^%a+_%d+$') then   -- STRICTLY <CharName>_<ServerId>; nothing else qualifies
            if d == cur then table.insert(out, 1, d); else out[#out + 1] = d; end
        end
    end
    return out, cur;
end

function M.currentCharFolder()
    local b = charBase();
    return b and b:match('([^\\]+)\\$') or nil;
end

function M.profileDirAt(charFolder, name)
    local root = M.lacRoot();
    if root == nil or charFolder == nil or name == nil then return nil; end
    return root .. charFolder .. '\\dlac\\profiles\\' .. name .. '\\';
end

function M.listProfilesAt(charFolder)
    local root = M.lacRoot();
    if root == nil or charFolder == nil then return nil; end
    local names = listDirs(root .. charFolder .. '\\dlac\\profiles\\');
    if names == nil then return nil; end
    -- get_dir mixes files into the listing: only sanitize-clean names can be
    -- profile FOLDERS (a stray file has a dot; sanitize rejects it).
    local out = {};
    for _, n in ipairs(names) do
        if M.sanitizeName(n) ~= nil then out[#out + 1] = n; end
    end
    return out;
end

-- Which jobs a profile carries (deterministic 22-job probe, no listing API):
-- array of { job, sets = bool, trig = bool }, only jobs with at least one file.
function M.profileJobsAt(charFolder, name)
    local dir = M.profileDirAt(charFolder, name);
    if dir == nil then return {}; end
    local out = {};
    for _, job in ipairs(M.JOBS) do
        local s = readFile(dir .. 'sets\\' .. job .. '.lua') ~= nil;
        local t = readFile(dir .. 'triggers\\' .. job .. '.lua') ~= nil;
        if s or t then out[#out + 1] = { job = job, sets = s, trig = t }; end
    end
    return out;
end

-- Copy every per-job file from one profile dir to another. Never overwrites.
local function copyJobFiles(srcDir, dstDir)
    if srcDir == nil or dstDir == nil then return 0; end
    local copied = 0;
    for _, job in ipairs(M.JOBS) do
        for _, kind in ipairs({ 'sets', 'triggers' }) do
            local t = readFile(srcDir .. kind .. '\\' .. job .. '.lua');
            local dp = dstDir .. kind .. '\\' .. job .. '.lua';
            if t ~= nil and readFile(dp) == nil then
                if writeFile(dp, t) then copied = copied + 1; end
            end
        end
    end
    return copied;
end

-- Does this character's profile <name> already hold any files? (44-file probe.)
local function profileHasFiles(name)
    for _, job in ipairs(M.JOBS) do
        if M.hasSetsFile(job, name) or M.hasTriggersFile(job, name) then return true; end
    end
    return false;
end

-- Every set/trigger file a profile holds, by ACTUAL listing (not the 22-job
-- probe): includes dormant non-job-named files (e.g. a "BLU-old" archive), so
-- the browser shows what is really there. Array of { name, sets, trig },
-- known jobs first (JOBS order), the rest alphabetical.
local JOB_ORDER = {};
for i, j in ipairs(M.JOBS) do JOB_ORDER[j] = i; end
function M.listProfileFilesAt(charFolder, name)
    local dir = M.profileDirAt(charFolder, name);
    if dir == nil then return {}; end
    local map = {};
    for _, b in ipairs(listLuaFiles(dir .. 'sets\\') or {}) do
        map[b] = map[b] or { name = b }; map[b].sets = true;
    end
    for _, b in ipairs(listLuaFiles(dir .. 'triggers\\') or {}) do
        map[b] = map[b] or { name = b }; map[b].trig = true;
    end
    local out = {};
    for _, e in pairs(map) do out[#out + 1] = e; end
    table.sort(out, function(a, b)
        local ja, jb = JOB_ORDER[a.name], JOB_ORDER[b.name];
        if ja ~= nil and jb ~= nil then return ja < jb; end
        if ja ~= nil then return true; end
        if jb ~= nil then return false; end
        return a.name < b.name;
    end);
    return out;
end

function M.profileHasFilesAt(charFolder, name)
    return #M.listProfileFilesAt(charFolder, name) > 0;
end

-- Storage skeleton on an ARBITRARY character (clone-to target). Does NOT touch
-- their active pointer -- the profile goes live only when they `use` it.
local function ensureStorageAt(charFolder, name)
    local root = M.lacRoot();
    if root == nil or charFolder == nil or name == nil then return false; end
    local b = root .. charFolder .. '\\';
    ensureDir(b .. 'dlac\\');
    ensureDir(b .. 'dlac\\profiles\\');
    ensureDir(b .. 'dlac\\profiles\\' .. name .. '\\');
    ensureDir(b .. 'dlac\\profiles\\' .. name .. '\\sets\\');
    ensureDir(b .. 'dlac\\profiles\\' .. name .. '\\triggers\\');
    return true;
end

-- Clone a whole profile to any character (including this one, under a new
-- name). Refuses a destination that already has files. copiedCount | nil, why.
function M.cloneProfileTo(srcCharFolder, srcName, dstCharFolder, dstName)
    dstName = M.sanitizeName(dstName);
    if dstName == nil then return nil, 'bad target name (letters/digits/_/- only)'; end
    local srcDir = M.profileDirAt(srcCharFolder, srcName);
    local dstDir = M.profileDirAt(dstCharFolder, dstName);
    if srcDir == nil or dstDir == nil then return nil, 'bad source/destination'; end
    if srcCharFolder == dstCharFolder and srcName == dstName then return nil, 'source and destination are the same profile'; end
    if M.profileHasFilesAt(dstCharFolder, dstName) then
        return nil, 'name collision: "' .. dstName .. '" already has files on that character';
    end
    if not ensureStorageAt(dstCharFolder, dstName) then return nil, 'could not create storage'; end
    local n = 0;
    for _, e in ipairs(M.listProfileFilesAt(srcCharFolder, srcName)) do
        for _, kind in ipairs({ 'sets', 'triggers' }) do
            if (kind == 'sets' and e.sets) or (kind == 'triggers' and e.trig) then
                local t = readFile(srcDir .. kind .. '\\' .. e.name .. '.lua');
                local dp = dstDir .. kind .. '\\' .. e.name .. '.lua';
                if t ~= nil and readFile(dp) == nil and writeFile(dp, t) then n = n + 1; end
            end
        end
    end
    if n == 0 then return nil, 'nothing copied (source profile empty or unreadable)'; end
    return n, nil;
end

-- Is a per-job (or dormant) name taken inside a destination profile?
function M.jobNameTakenAt(charFolder, profName, name)
    local dir = M.profileDirAt(charFolder, profName);
    if dir == nil or name == nil then return false; end
    return readFile(dir .. 'sets\\' .. name .. '.lua') ~= nil
        or readFile(dir .. 'triggers\\' .. name .. '.lua') ~= nil;
end

-- Clone ONE job's data (sets + triggers) into any character/profile under
-- dstName. dstName must be a real job abbr to be LIVE there; any other
-- sanitized name is copied as a dormant archive (the engine only reads
-- <JOB>.lua). Refuses when dstName is taken. copiedCount | nil, why.
function M.copyJobTo(srcCharFolder, srcProf, job, dstCharFolder, dstProf, dstName)
    dstName = M.sanitizeName(dstName);
    if dstName == nil then return nil, 'bad name (letters/digits/_/- only)'; end
    dstProf = M.sanitizeName(dstProf);
    if dstProf == nil then return nil, 'bad profile name (letters/digits/_/- only)'; end
    local srcDir = M.profileDirAt(srcCharFolder, srcProf);
    local dstDir = M.profileDirAt(dstCharFolder, dstProf);
    if srcDir == nil or dstDir == nil then return nil, 'bad source/destination'; end
    if srcCharFolder == dstCharFolder and srcProf == dstProf and job == dstName then
        return nil, 'source and destination are the same file';
    end
    if M.jobNameTakenAt(dstCharFolder, dstProf, dstName) then
        return nil, 'name collision: "' .. dstName .. '" already exists in that profile';
    end
    if not ensureStorageAt(dstCharFolder, dstProf) then return nil, 'could not create storage'; end
    local n = 0;
    for _, kind in ipairs({ 'sets', 'triggers' }) do
        local t = readFile(srcDir .. kind .. '\\' .. job .. '.lua');
        if t ~= nil then
            local dp = dstDir .. kind .. '\\' .. dstName .. '.lua';
            if readFile(dp) == nil and writeFile(dp, t) then n = n + 1; end
        end
    end
    if n == 0 then return nil, 'nothing copied (no files for ' .. tostring(job) .. ')'; end
    return n, nil;
end

-- Rename one of THIS character's profiles (folder rename; repoints the active
-- pointer when the renamed profile is the active one). true | nil, why.
function M.renameProfile(oldName, newName)
    newName = M.sanitizeName(newName);
    if newName == nil then return nil, 'bad name (letters/digits/_/- only)'; end
    if oldName == newName then return nil, 'same name'; end
    local root = M.profilesRoot();
    if root == nil then return nil, 'not logged in'; end
    local cur = M.currentCharFolder();
    if M.profileHasFilesAt(cur, newName) then
        return nil, 'name collision: "' .. newName .. '" already has files';
    end
    local ok, oerr = os.rename(root .. oldName, root .. newName);
    if not ok then return nil, 'rename failed: ' .. tostring(oerr); end
    if M.activeName() == oldName then M.setActive(newName); end
    return true, nil;
end

-- Import another character's profile into THIS character under dstName.
-- Refuses to pour into a profile that already has files (no silent merges).
-- Returns copiedCount, nil | nil, why.
function M.importProfile(srcCharFolder, srcName, dstName)
    dstName = M.sanitizeName(dstName);
    if dstName == nil then return nil, 'bad target name (letters/digits/_/- only)'; end
    if charBase() == nil then return nil, 'not logged in'; end
    local srcDir = M.profileDirAt(srcCharFolder, srcName);
    if srcDir == nil then return nil, 'bad source'; end
    if profileHasFiles(dstName) then return nil, 'profile "' .. dstName .. '" already has files here -- pick another name'; end
    if not M.ensureStorage(dstName) then return nil, 'could not create storage'; end
    local n = copyJobFiles(srcDir, M.profileDir(dstName));
    if n == 0 then return nil, 'nothing copied (source profile empty or unreadable)'; end
    return n, nil;
end

-- Copy every per-job sets/triggers file from one profile to another (the
-- export/import primitive: a profile is just these files). Deterministic 22-job
-- probe -- no directory listing API needed. Never overwrites dst files.
function M.cloneProfile(src, dst)
    src, dst = M.sanitizeName(src), M.sanitizeName(dst);
    if src == nil or dst == nil then return nil, 'bad profile name'; end
    if not M.ensureStorage(dst) then return nil, 'not logged in'; end
    local copied = 0;
    for _, job in ipairs(M.JOBS) do
        for _, kind in ipairs({ 'sets', 'triggers' }) do
            local sp = M.profileDir(src) .. kind .. '\\' .. job .. '.lua';
            local dp = M.profileDir(dst) .. kind .. '\\' .. job .. '.lua';
            local t = readFile(sp);
            if t ~= nil and readFile(dp) == nil then
                if writeFile(dp, t) then copied = copied + 1; end
            end
        end
    end
    return copied, nil;
end

-- ---------------------------------------------------------------------------
-- the profile sets file
--
-- Same shape as the block dlac used to commit into <JOB>.lua, so setmanager's
-- field-proven spliceSet/deleteSetText scanners work on it UNCHANGED:
--     local sets = { Dynamic = { <Name> = { <Slot> = { entries } } } };
--     return sets;
-- ---------------------------------------------------------------------------

local SETS_HEADER = '-- dlac profile sets -- committed by the Sets tab; hand edits are fine.\n'
    .. '-- Loaded for the ACTIVE profile (dlac\\profile.lua); gear refs resolve via your gear.lua.\n';

-- Wrap a 'Dynamic = { ... }' block (extractDynamicText output, or a fresh empty
-- one) into a complete profile sets file. Pure text; offline-tested.
function M.frameSetsText(dynText)
    if type(dynText) ~= 'string' or dynText == '' then dynText = 'Dynamic = {\n    }'; end
    return SETS_HEADER .. 'local sets = {\n    ' .. dynText .. ',\n};\nreturn sets;\n';
end

-- Load the profile sets file and return its Dynamic table (name -> set), or
-- nil + why. `gear` is provided from THIS state's gear inventory, so entries
-- point into the same tables everything else uses (LAC state: <char>\dlac\
-- copy; addon state: the preloaded char gear; tests: the stub).
function M.readSetsFile(job, name)
    local p = M.setsPath(job, name);
    if p == nil then return nil, 'not logged in'; end
    local chunk = loadfile(p);
    if chunk == nil then return nil, 'no profile sets file'; end
    local gok, gearT = pcall(require, 'dlac\\gear');
    local env = setmetatable({ gear = (gok and type(gearT) == 'table') and gearT or {} },
                             { __index = function(_, k) return rawget(_G, k); end });
    if setfenv ~= nil then setfenv(chunk, env); end
    local ok, ret = pcall(chunk);
    local s = (ok and type(ret) == 'table') and ret or rawget(env, 'sets');
    if type(s) == 'table' and type(s.Dynamic) == 'table' then return s.Dynamic, nil; end
    return nil, ok and ('no Dynamic table in ' .. p) or ('error running ' .. p .. ': ' .. tostring(ret));
end

function M.hasSetsFile(job, name)
    return readFile(M.setsPath(job, name)) ~= nil;
end
function M.hasTriggersFile(job, name)
    return readFile(M.triggersPath(job, name)) ~= nil;
end

-- ---------------------------------------------------------------------------
-- pure text helpers (offline-tested)
-- ---------------------------------------------------------------------------

-- Brace-aware scanner: from the '{' at byte i, the matching '}' index, skipping
-- comments and strings. COPIED from setmanager.lua (addon-state module -- the
-- LAC state can't require it); keep the two in sync.
local function matchBrace(text, i)
    local n = #text; local depth = 0;
    while i <= n do
        local c = text:sub(i, i);
        if c == '-' and text:sub(i + 1, i + 1) == '-' then
            if text:sub(i + 2, i + 3) == '[[' then
                local e = text:find(']]', i + 4, true); i = e and e + 2 or n + 1;
            else
                local e = text:find('\n', i + 2, true); i = e or n + 1;
            end
        elseif c == '"' or c == "'" then
            local q = c; i = i + 1;
            while i <= n do
                local d = text:sub(i, i);
                if d == '\\' then i = i + 2;
                elseif d == q then i = i + 1; break;
                else i = i + 1; end
            end
        elseif c == '{' then depth = depth + 1; i = i + 1;
        elseif c == '}' then
            depth = depth - 1;
            if depth == 0 then return i; end
            i = i + 1;
        else i = i + 1; end
    end
    return nil;
end

-- The whole 'Dynamic = { ... }' block out of a job file, VERBATIM -- byte-for-byte
-- is the migration's "your dynamic sets survive" guarantee (comments, wrappers,
-- minLevel gates and all). nil + why when the file has no block.
function M.extractDynamicText(text)
    if type(text) ~= 'string' then return nil, 'no file text'; end
    local ds, de = text:find('Dynamic%s*=%s*{');
    if ds == nil then return nil, 'no sets.Dynamic block'; end
    local close = matchBrace(text, de);
    if close == nil then return nil, 'sets.Dynamic block is not closed'; end
    return text:sub(ds, close), nil;
end

-- ---------------------------------------------------------------------------
-- the clean job-file shim
-- ---------------------------------------------------------------------------

-- Marker line: migration and Setup recognize a shim by it and never touch the
-- file again. Keep the prefix stable forever; bump the (vN) on shape changes.
M.SHIM_MARKER = '-- dlac profile shim';

M.BOOT_LINE = [[package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';  -- dlac: use the dlac addon library]];

-- The shim body. Mirrors gearui's STARTER_PROFILE (OnLoad/Packer kept so
-- /lac addset still works) minus any set data: the engine installs the active
-- profile's sets over the empty scaffold at load / job change / profile switch.
local SHIM_BODY = [[
-- dlac profile shim (v1) -- managed by dlac. Do not keep data here:
--   sets     live in  <char>\dlac\profiles\<active>\sets\<JOB>.lua      (Sets tab)
--   triggers live in  <char>\dlac\profiles\<active>\triggers\<JOB>.lua  (Triggers tab)
-- Your original file (if you migrated) is in <char>\backups\pre-profiles\.
local profile = {};
local utils = require("dlac\\utils");   -- everything comes through this one require
local gear  = utils.gear;               -- the shared gear inventory
local sets = {
    Dynamic = {},                       -- filled by the engine from the active dlac profile
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

-- All equip logic is data: utils.dispatch reads the active profile's trigger file
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

function M.shimFileText()
    return M.BOOT_LINE .. '\n' .. SHIM_BODY;
end

function M.isCleanShim(text)
    return type(text) == 'string' and text:find(M.SHIM_MARKER, 1, true) ~= nil;
end

-- ---------------------------------------------------------------------------
-- migration
-- ---------------------------------------------------------------------------

-- Pure planner: given per-job facts, decide what would happen. files is a list of
--   { job, text, hasBackup, hasProfileSets, hasLegacyTrig, hasProfileTrig }
-- Returns a list of { job, action = 'skip'|'migrate', reason, dynText|nil, notes = {...} }.
function M.planMigration(files)
    local plan = {};
    for _, f in ipairs(files) do
        local e = { job = f.job, notes = {} };
        if M.isCleanShim(f.text) then
            e.action, e.reason = 'skip', 'already a clean dlac shim';
        elseif f.hasBackup then
            -- The first backup is the pre-profiles TRUTH (statics live there for
            -- Copy-from-static). Never overwrite it; never re-migrate over it.
            e.action, e.reason = 'skip', 'backup already exists (migrated before?) -- not touching';
        else
            e.action = 'migrate';
            local dyn, derr = M.extractDynamicText(f.text);
            if f.hasProfileSets then
                e.notes[#e.notes + 1] = 'profile sets file already exists -- kept as-is (job file\'s Dynamic block NOT imported over it)';
            elseif dyn ~= nil then
                e.dynText = dyn;
                e.notes[#e.notes + 1] = 'dynamic sets move into the profile verbatim';
            else
                e.notes[#e.notes + 1] = 'no dynamic sets to import (' .. tostring(derr) .. ') -- profile sets file starts empty';
            end
            if f.hasLegacyTrig and not f.hasProfileTrig then
                e.notes[#e.notes + 1] = 'trigger file moves into the profile (original kept in backups\\pre-profiles\\triggers\\)';
            elseif f.hasLegacyTrig and f.hasProfileTrig then
                e.notes[#e.notes + 1] = 'profile trigger file already exists -- legacy one left in place, IGNORED from now on';
            end
            e.notes[#e.notes + 1] = 'the job file is rewritten as a clean dlac shim (original -> backups\\pre-profiles\\)';
        end
        plan[#plan + 1] = e;
    end
    return plan;
end

-- Gather per-job facts from disk for every <JOB>.lua that exists.
local function migrationFacts(name)
    local files = {};
    for _, job in ipairs(M.JOBS) do
        local text = readFile(M.jobFilePath(job));
        if text ~= nil then
            files[#files + 1] = {
                job = job, text = text,
                hasBackup      = readFile(M.backupPath(job)) ~= nil,
                hasProfileSets = M.hasSetsFile(job, name),
                hasLegacyTrig  = readFile(M.legacyTriggersPath(job)) ~= nil,
                hasProfileTrig = M.hasTriggersFile(job, name),
            };
        end
    end
    return files;
end

-- The current plan against the real char folder, for DISPLAY (the GUI Setup
-- popup renders it before asking for a Commit). nil, why when not logged in.
function M.currentPlan(name)
    if charBase() == nil then return nil, 'not logged in'; end
    return M.planMigration(migrationFacts(name or 'Default'));
end

-- The migration itself. execute=false prints the full plan and touches NOTHING;
-- execute=true does the work file by file, each step verified before the next
-- (backup is read back and compared before the original is ever rewritten).
-- Returns migratedCount, skippedCount, failedCount.
function M.migrate(execute, say)
    say = say or print;
    local name = 'Default';   -- migration always lands in Default; switch/clone after
    if charBase() == nil then say('[dlac] profile migrate: log in first.'); return 0, 0, 0; end
    local files = migrationFacts(name);
    if #files == 0 then say('[dlac] profile migrate: no <JOB>.lua files found.'); return 0, 0, 0; end
    local plan = M.planMigration(files);

    if not execute then
        say('[dlac] profile migration PLAN (dry run -- nothing was touched):');
        for _, e in ipairs(plan) do
            if e.action == 'skip' then
                say(string.format('[dlac]   %s: skip -- %s', e.job, e.reason));
            else
                say(string.format('[dlac]   %s: migrate', e.job));
                for _, n in ipairs(e.notes) do say('[dlac]       - ' .. n); end
            end
        end
        say('[dlac] run  /dl profile migrate go  to execute. Every original lands in backups\\pre-profiles\\ first.');
        return 0, 0, 0;
    end

    M.ensureStorage(name);
    local b = charBase();
    ensureDir(b .. 'backups\\');
    ensureDir(b .. 'backups\\pre-profiles\\');
    ensureDir(b .. 'backups\\pre-profiles\\triggers\\');

    local done, skipped, failed = 0, 0, 0;
    for i, e in ipairs(plan) do
        local f = files[i];
        if e.action == 'skip' then
            skipped = skipped + 1;
            say(string.format('[dlac] %s: skipped -- %s', e.job, e.reason));
        else
            local okAll = true;
            -- 1) backup the original, read it back, compare. NOTHING is rewritten
            --    until this byte-identical copy is proven on disk.
            local bp = M.backupPath(e.job);
            if not writeFile(bp, f.text) or readFile(bp) ~= f.text then
                say(string.format('[dlac] %s: FAILED -- could not verify backup at %s; file untouched.', e.job, tostring(bp)));
                okAll = false;
            end
            -- 2) profile sets file (only when absent; verbatim Dynamic block).
            if okAll and not f.hasProfileSets then
                local framed = M.frameSetsText(e.dynText);
                local lok = (loadstring or load)(framed);
                if lok == nil then
                    say(string.format('[dlac] %s: FAILED -- framed sets file would not parse; file untouched (backup kept).', e.job));
                    okAll = false;
                elseif not writeFile(M.setsPath(e.job, name), framed) then
                    say(string.format('[dlac] %s: FAILED -- could not write profile sets file; job file untouched.', e.job));
                    okAll = false;
                end
            end
            -- 3) trigger file: copy -> verify -> backup -> remove legacy.
            if okAll and f.hasLegacyTrig and not f.hasProfileTrig then
                local ttext = readFile(M.legacyTriggersPath(e.job));
                if ttext ~= nil and writeFile(M.triggersPath(e.job, name), ttext)
                   and readFile(M.triggersPath(e.job, name)) == ttext
                   and writeFile(M.triggerBackupPath(e.job), ttext) then
                    pcall(os.remove, M.legacyTriggersPath(e.job));
                else
                    say(string.format('[dlac] %s: trigger move failed -- legacy trigger file left in place (still read as fallback).', e.job));
                end
            end
            -- 4) the job file becomes the clean shim. LAST, so any failure above
            --    leaves the original fully in charge.
            if okAll then
                if writeFile(M.jobFilePath(e.job), M.shimFileText()) then
                    done = done + 1;
                    say(string.format('[dlac] %s: MIGRATED -- original: backups\\pre-profiles\\%s.lua; sets: dlac\\profiles\\%s\\sets\\%s.lua; %s.lua is now a clean shim.',
                        e.job, e.job, name, e.job, e.job));
                else
                    failed = failed + 1;
                    say(string.format('[dlac] %s: FAILED -- could not rewrite %s.lua (backup + profile files are in place).', e.job, e.job));
                end
            else
                failed = failed + 1;
            end
        end
    end
    say(string.format('[dlac] profile migration done: %d migrated, %d skipped, %d failed. Statics from your old files stay available to "Copy from" via backups\\pre-profiles\\.',
        done, skipped, failed));
    return done, skipped, failed;
end

return M;
