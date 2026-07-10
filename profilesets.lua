--[[
    dlac/profilesets.lua -- read the loaded profile's `sets` table (Sets tab data source).

    Split out of gearui.lua: LuaJIT caps a chunk at 200 local variables, and gearui's
    main chunk was already at it -- cohesive helpers get their own module from now on.

    gearui injects its file helper once via M.configure{ jobFile } and then reads
    sets through getSetsRoot / getDynamicSets / dynamicSetNames / staticSetNames.
    diag() surfaces the last load diagnostic; invalidate() drops the cached sets
    (after a commit/delete) so the next read re-parses the job file.
]]--

local M = {};

-- Injected by gearui (M.configure): jobFile() -> <JOB>.lua path, abbr (or nil, nil).
local deps = nil;
function M.configure(d) deps = d; end

-- The profile's raw `sets` table. LuAshitacast exposes the loaded profile as the
-- gProfile global, and gProfile.Sets IS the profile's `sets` table whether it was
-- declared local (BLM/BLU/BRD/COR/...) or global (SCH-style) -- BuildDynamicSets
-- mutates that table in place but leaves .Dynamic intact. Fall back to a global
-- `sets` if gProfile isn't reachable; nil until a profile is loaded.
-- Addon context has no gProfile. Read the current job's <JOB>.lua from disk and run it in
-- a sandbox (LuaAshitacast globals stubbed to a permissive no-op) to recover its `sets`
-- table -- its gear refs resolve against the same preloaded gear the GUI uses. Cached per
-- file; cleared on job change and after a commit/delete.
local _profileSets, _profileSetsKey, _setsDiag = nil, nil, nil;
local function loadProfileSets()
    local jf = (deps ~= nil and deps.jobFile ~= nil) and deps.jobFile() or nil;
    if jf == nil then _setsDiag = 'no job file (logged in? job known?)'; return nil; end
    if _profileSetsKey == jf and _profileSets ~= nil then return _profileSets; end
    _profileSetsKey = jf;
    local chunk = loadfile(jf);
    if chunk == nil then _setsDiag = 'could not open ' .. jf; _profileSets = nil; return nil; end
    local STUB; STUB = setmetatable({}, { __index = function() return STUB; end, __call = function() return STUB; end });
    local env = setmetatable({}, {
        __index    = function(_, k) local g = rawget(_G, k); if g ~= nil then return g; end return STUB; end,
        __newindex = function(t, k, v) rawset(t, k, v); end,
    });
    if setfenv ~= nil then setfenv(chunk, env); end   -- LuaJIT (Ashita)
    local ok, ret = pcall(chunk);                     -- profiles end with `return profile`
    -- Prefer the returned profile.Sets (works whether the profile used `local sets` or a
    -- global one); fall back to a global `sets` assigned into the sandbox env.
    local s = nil;
    if ok and type(ret) == 'table' and type(ret.Sets) == 'table' then s = ret.Sets;
    elseif type(rawget(env, 'sets')) == 'table' then s = rawget(env, 'sets'); end
    if type(s) == 'table' then
        _profileSets = s;
        _setsDiag = (type(s.Dynamic) == 'table') and nil or ('ran ' .. jf .. ' but it has no sets.Dynamic');
    else
        _profileSets = nil;
        _setsDiag = 'ran ' .. jf .. ' but found no sets' .. (ok and '' or (' -- error: ' .. tostring(ret)));
    end
    return _profileSets;
end

local function getSetsRoot()
    local prof = rawget(_G, 'gProfile');
    if type(prof) == 'table' and type(prof.Sets) == 'table' then return prof.Sets; end
    local s = rawget(_G, 'sets');
    if type(s) == 'table' then return s; end
    return loadProfileSets();   -- addon: parse the current job's <JOB>.lua on disk
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

-- Names of the profile's NON-Dynamic sibling sets (static / flattened sets like
-- Idle, Precast, Cure, ...). These are the migration sources the "Copy from" helper
-- can seed a Dynamic set from. Excludes 'Dynamic' itself. Guarded: nil until load.
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

-- Drop the cached sets so the next read re-parses the job file (post commit/delete).
function M.invalidate() _profileSets = nil; end

M.getSetsRoot     = getSetsRoot;
M.getDynamicSets  = getDynamicSets;
M.dynamicSetNames = dynamicSetNames;
M.staticSetNames  = staticSetNames;

return M;
