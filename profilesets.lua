--[[
    dlac/profilesets.lua -- read the loaded profile's `sets` table (Sets tab data source).

    Split out of gearui.lua: LuaJIT caps a chunk at 200 local variables, and gearui's
    main chunk was already at it -- cohesive helpers get their own module from now on.

    gearui injects its file helper once via M.configure{ jobFile } and then reads
    sets through getSetsRoot / getDynamicSets / dynamicSetNames / staticSetNames.
    diag() surfaces the last load diagnostic; invalidate() drops the cached sets
    (after a commit/delete) so the next read re-parses the source files.

    Profile storage layer (profiles.lua): the Dynamic sets come from the ACTIVE
    profile's sets\<JOB>.lua when it exists, else (legacy) from sandbox-running
    <JOB>.lua. STATIC sets are listed from <JOB>.lua AND from the pre-migration
    backup (backups\pre-profiles\<JOB>.lua) -- that is what keeps "Copy from
    static" working forever after a migration cleans the job file.
]]--

local M = {};

-- Injected by gearui (M.configure): jobFile() -> <JOB>.lua path, abbr (or nil, nil).
local deps = nil;
function M.configure(d) deps = d; end

local _pok, _prof = pcall(require, 'dlac\\profiles');
_pok = _pok and type(_prof) == 'table';

-- Sandbox-run a profile-shaped file and return its `sets` table (nil, why on
-- failure). dispatch.lua's hardened readJobSets env: side-effect globals are
-- stubbed (the addon state has the REAL AshitaCore -- running someone's OnLoad
-- must not queue commands), the STUB survives string-building (the dlac boot
-- line concatenates AshitaCore:GetInstallPath()), and `require` is soft -- a
-- backup file's require('gcinclude') degrades to the STUB instead of erroring
-- the whole chunk away.
local function sandboxSets(path)
    if path == nil then return nil, 'no path'; end
    local chunk = loadfile(path);
    if chunk == nil then return nil, 'could not open ' .. path; end
    local STUB; STUB = setmetatable({}, {
        __index = function() return STUB; end,
        __call = function() return STUB; end,
        __concat = function() return ''; end,
        __tostring = function() return ''; end,
    });
    local BLOCK = { gFunc = true, gState = true, gEquip = true, gSetDisplay = true, gProfile = true,
                    gSettings = true, AshitaCore = true, ashita = true, print = true, coroutine = true,
                    package = true };
    local softRequire = function(m)
        local ok, r = pcall(require, m);
        if ok and r ~= nil then return r; end
        return STUB;
    end
    local env = setmetatable({ require = softRequire }, {
        __index = function(_, k)
            if BLOCK[k] then return STUB; end
            local g = rawget(_G, k);
            if g ~= nil then return g; end
            return STUB;
        end,
        __newindex = function(t, k, v) rawset(t, k, v); end,
    });
    if setfenv ~= nil then setfenv(chunk, env); end   -- LuaJIT (Ashita)
    local ok, ret = pcall(chunk);                     -- profiles end with `return profile`
    local s = nil;
    if ok and type(ret) == 'table' and type(ret.Sets) == 'table' then s = ret.Sets;
    elseif type(rawget(env, 'sets')) == 'table' then s = rawget(env, 'sets'); end
    if type(s) ~= 'table' then
        return nil, 'ran ' .. path .. ' but found no sets' .. (ok and '' or (' -- error: ' .. tostring(ret)));
    end
    return s, nil;
end

-- Build the merged sets root for the CURRENT job + ACTIVE profile:
--   .Dynamic       profile sets file first, else the job file's block (legacy)
--   .<StaticName>  from the live job file, then the pre-profiles backup fills
--                  names the live file no longer has (post-migration statics).
-- Cached per (job file, active profile); invalidate() drops it after a commit.
local _cache, _cacheKey, _setsDiag = nil, nil, nil;
local function loadRoot()
    local jf, abbr = nil, nil;
    if deps ~= nil and deps.jobFile ~= nil then jf, abbr = deps.jobFile(); end
    if jf == nil then _setsDiag = 'no job file (logged in? job known?)'; return nil; end
    local act = (_pok and _prof.activeName()) or '';
    local key = jf .. '|' .. act;
    if _cacheKey == key and _cache ~= nil then return _cache; end
    _cacheKey = key;
    _setsDiag = nil;

    local root = {};
    local dynSrc = nil;

    -- Dynamic: profile storage first.
    if _pok and abbr ~= nil and _prof.hasSetsFile(abbr) then
        local dyn, derr = _prof.readSetsFile(abbr);
        if type(dyn) == 'table' then
            root.Dynamic = dyn;
            dynSrc = 'profile';
        else
            _setsDiag = tostring(derr);
        end
    end

    -- The live job file: legacy Dynamic (when no profile file) + its statics.
    local jsets, jerr = sandboxSets(jf);
    if type(jsets) == 'table' then
        for k, v in pairs(jsets) do
            if k == 'Dynamic' then
                if root.Dynamic == nil and type(v) == 'table' then root.Dynamic = v; end
            elseif type(v) == 'table' and root[k] == nil then
                root[k] = v;
            end
        end
    elseif dynSrc == nil and _setsDiag == nil then
        _setsDiag = tostring(jerr);
    end

    -- The pre-migration backup: statics only, never Dynamic (its Dynamic block
    -- was imported into the profile at migration time -- reading it again would
    -- resurrect deleted sets).
    if _pok and abbr ~= nil then
        local bsets = sandboxSets(_prof.backupPath(abbr));
        if type(bsets) == 'table' then
            for k, v in pairs(bsets) do
                if k ~= 'Dynamic' and type(v) == 'table' and root[k] == nil then root[k] = v; end
            end
        end
    end

    if root.Dynamic == nil and _setsDiag == nil then
        _setsDiag = 'ran ' .. jf .. ' but it has no sets.Dynamic';
    end
    _cache = root;
    return _cache;
end

local function getSetsRoot()
    -- LAC-state conveniences kept for safety (the addon state has neither).
    local prof = rawget(_G, 'gProfile');
    if type(prof) == 'table' and type(prof.Sets) == 'table' then return prof.Sets; end
    local s = rawget(_G, 'sets');
    if type(s) == 'table' then return s; end
    return loadRoot();
end

-- The .Dynamic sub-table specifically (the only sets we build/commit).
local function getDynamicSets()
    local S = getSetsRoot();
    if type(S) == 'table' and type(S.Dynamic) == 'table' then return S.Dynamic; end
    return nil;
end

-- Names of the dynamic sets (the only sets we edit). Guarded: nil until profile load.
local function dynamicSetNames()
    local names = {};
    pcall(function()
        local dyn = getDynamicSets();
        if type(dyn) ~= 'table' then return; end
        for k, v in pairs(dyn) do
            if type(v) == 'table' then names[#names + 1] = tostring(k); end
        end
    end);
    table.sort(names);
    return names;
end

-- Names of the NON-Dynamic sibling sets (static / flattened sets like Idle,
-- Precast, Cure, ...) -- from the live job file AND the pre-profiles backup.
-- These are the migration sources the "Copy from" helper can seed a Dynamic
-- set from. Excludes 'Dynamic' itself. Guarded: empty until load.
local function staticSetNames()
    local names = {};
    pcall(function()
        local S = getSetsRoot();
        if type(S) ~= 'table' then return; end
        for k, v in pairs(S) do
            if k ~= 'Dynamic' and type(v) == 'table' then names[#names + 1] = tostring(k); end
        end
    end);
    table.sort(names);
    return names;
end

-- Last load diagnostic (nil when healthy) -- the Sets tab shows it in red.
function M.diag() return _setsDiag; end

-- Drop the cached sets so the next read re-parses the files (post commit/delete).
function M.invalidate() _cache = nil; _cacheKey = nil; end

M.getSetsRoot     = getSetsRoot;
M.getDynamicSets  = getDynamicSets;
M.dynamicSetNames = dynamicSetNames;
M.staticSetNames  = staticSetNames;

return M;
