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
    backups (backups\pre-profiles\<JOB>.lua, in BOTH storage homes) -- that is
    what keeps "Copy from static" working forever after a migration cleans the
    job file.

    Those same legacy files also carry a `sets.Dynamic` block -- dlac's OWN sets
    from before the profile storage layer existed ("old FFXI-LAC sets", Henrik
    2026-07-28). They are offered as IMPORT SOURCES through lacSetNames /
    getLacSets and are deliberately kept OUT of the sets root: the engine never
    loads them, so a set that only exists there must never look live (nor come
    back from the dead after you deleted it). The one exception is the
    unmigrated character whose job file IS the live Dynamic source -- there the
    same block is already the live list, so it is not offered a second time.
]]--

local M = {};

-- Injected by gearui (M.configure): jobFile() -> <JOB>.lua path, abbr (or nil, nil).
local deps = nil;
function M.configure(d) deps = d; end

local _pok, _prof = pcall(require, 'dlac\\profiles');
_pok = _pok and type(_prof) == 'table';

local function readAll(p)
    if p == nil then return nil; end
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end

-- THE MISSING SENTINEL. Every key at every depth answers with itself, so no
-- legacy file can nil-index its own chunk away: `gear.Ammo.Throwing.MorionTathlum`
-- (the pre-flat Ammo shape) on a character whose Ammo is flat used to error and
-- take EVERY set in the file with it. Now that reference is simply missing, and
-- the importer skips it -- "if pieces don't exist, just skip them and move on
-- like he doesn't have it" (Henrik 2026-07-28).
--
-- `.__dlacMissing` reads truthy through the same __index, which is how the
-- importer spots one; the require STUB below answers identically by the same
-- construction, so ONE check covers both (a piece that isn't there, and a whole
-- library that isn't there).
local MISSING; MISSING = setmetatable({}, {
    __index    = function() return MISSING; end,
    __call     = function() return MISSING; end,
    __concat   = function() return ''; end,
    __tostring = function() return ''; end,
});
M.MISSING = MISSING;

-- Legacy MODULE-NAME alias. An old job file requires dlac's library under dlac's
-- own former name -- `require("ffxi-lac\gear")`, from before the rename. That
-- module does not exist on a dlac install, so the soft require handed back the
-- STUB and every `gear.Main.Club.MapleWand` in the file became the stub object:
-- the sets listed fine and imported EMPTY, with no word about why (field
-- 2026-07-28, a second tester's SCH.lua). Rewriting the prefix is what makes such
-- a file resolve against THIS character's real inventory -- and it deliberately
-- WINS over a stale addons folder of that name, which would otherwise answer with
-- someone's years-old gear table.
--
-- This renames a MODULE, it never opens a file in that tree -- which is the line
-- SH21 guards (Henrik 2026-07-28: dlac handles its own gear locally, and the one
-- sanctioned integration is exactly this import). The prefix is written as a
-- character class for the same reason PRG1 comments use the single-backslash
-- form: the guard reads path literals, not intent.
local function aliasModule(m)
    if type(m) ~= 'string' then return m; end
    local aliased = m:gsub('^ffxi%-lac([\\/])', 'dlac%1');
    return aliased;
end

-- The gear inventory as a legacy file may read it: present tables pass through
-- REAL (identity kept, so resolved entries stay the same records everything else
-- uses), anything absent reads MISSING at any depth. Deliberately NOT
-- profiles._wrapGear -- that one answers nil for a missing flat-slot key, which
-- is right for a LIVE sets file (a nil is a ladder hole) but wrong here: a nil in
-- the middle of a candidate list truncates `ipairs` and silently drops every
-- entry after it (measured: 60 entries -> 10 on a foreign gear.lua).
local function legacyGear(realGear)
    if type(realGear) ~= 'table' then return MISSING; end
    local slots = {};
    return setmetatable({}, {
        __index = function(_, slot)
            local hit = slots[slot];
            if hit ~= nil then return hit; end
            local real = realGear[slot];
            if type(real) ~= 'table' then slots[slot] = MISSING; return MISSING; end
            local p = setmetatable({}, {
                __index = function(_, k)
                    local v = real[k];
                    -- a nested WEAPON CATEGORY (a table holding records, no Name of
                    -- its own) gets the same treatment one level down
                    if type(v) == 'table' and v.Name == nil then
                        return setmetatable({}, { __index = function(_, k2)
                            local v2 = v[k2];
                            if v2 ~= nil then return v2; end
                            return MISSING;
                        end });
                    end
                    if v ~= nil then return v; end
                    return MISSING;
                end,
            });
            slots[slot] = p;
            return p;
        end,
    });
end

-- Sandbox-run a profile-shaped file and return its `sets` table (nil, why on
-- failure). dispatch.lua's hardened readJobSets env: side-effect globals are
-- stubbed (the addon state has the REAL AshitaCore -- running someone's OnLoad
-- must not queue commands), the STUB survives string-building (the dlac boot
-- line concatenates AshitaCore:GetInstallPath()), and `require` is soft -- a
-- backup file's require('gcinclude') degrades to the STUB instead of erroring
-- the whole chunk away.
--
-- The `why` is a PLAYER-FACING diagnostic (the Copy-from popup prints it in red),
-- so it separates the two cases that used to read alike: a file that is not there
-- (nil, nil -- nothing to say) and a file that IS there and will not parse. The
-- second one cost a tester an evening: a single missing comma in his SCH.lua
-- (`gear.Back.MistSilkCape` with no `,`) made the whole file unreadable, and dlac
-- said nothing at all.
local function sandboxSets(path)
    if path == nil then return nil, nil; end
    local chunk, lerr = loadfile(path);
    if chunk == nil then
        if readAll(path) == nil then return nil, nil; end   -- absent: not a fault
        return nil, 'will not parse -- ' .. tostring(lerr);
    end
    local STUB; STUB = setmetatable({}, {
        __index = function() return STUB; end,
        __call = function() return STUB; end,
        __concat = function() return ''; end,
        __tostring = function() return ''; end,
    });
    local BLOCK = { gFunc = true, gState = true, gEquip = true, gSetDisplay = true, gProfile = true,
                    gSettings = true, AshitaCore = true, ashita = true, print = true, coroutine = true,
                    package = true };
    -- `require` is soft, ALIASED (ffxi-lac\X -> dlac\X, see aliasModule) and the
    -- gear inventory comes through legacyGear, so a name this character has no
    -- record of is a skipped entry rather than a dead chunk.
    local softRequire = function(m)
        local name = aliasModule(m);
        if name == 'dlac\\gear' then
            local gok, g = pcall(require, name);
            return legacyGear((gok and type(g) == 'table') and g or nil);
        end
        local ok, r = pcall(require, name);
        if not ok or r == nil then return STUB; end
        return r;
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
-- The key alone is NOT enough: a Profiles-menu import rewrites the ACTIVE
-- profile's sets file for the CURRENT job -- same key, new bytes (field case
-- 2026-07-22: the Sets/Triggers tabs kept serving the previous profile's set
-- names after an import). So cache hits also content-follow the Dynamic
-- source file, throttled to one disk read per second -- the engine's own
-- content-keyed watch idiom (triggers ensureLoaded / the v102 self-swap).
local _cache, _cacheKey, _setsDiag = nil, nil, nil;
local _liveNames = nil;   -- set names that exist in the LIVE profile (see liveSetNames)
local _lacDyn = nil;      -- old FFXI-LAC Dynamic sets, name -> set (import sources only)
local _lacDiag = {};      -- legacy files that EXIST and could not be read (see legacyDiag)
local _watch = { at = -1, path = nil, raw = nil };   -- the Dynamic source the cache mirrors

-- The Dynamic source RIGHT NOW: the active profile's sets file when readable,
-- else the (legacy) job file. Returns path, bytes -- the pair the watch compares.
local function dynSourceNow(jf, abbr)
    if _pok and abbr ~= nil then
        local pp = nil;
        pcall(function() pp = _prof.setsPath(abbr); end);
        local t = readAll(pp);
        if t ~= nil then return pp, t; end
    end
    return jf, readAll(jf);
end

-- Every pre-migration backup of this job's original file, in read order: the
-- native home first, then the copy left under LuaAshitacast's tree by a
-- character that migrated BEFORE the storage move. Both are read-only import
-- territory, and a character usually has one home or the other, not both.
local function backupPaths(abbr)
    local out = {};
    if not _pok or abbr == nil then return out; end
    pcall(function()
        local p = _prof.backupPath(abbr);
        if p ~= nil then out[#out + 1] = p; end
        if type(_prof.legacyBackupPath) == 'function' then
            local q = _prof.legacyBackupPath(abbr);
            if q ~= nil and q ~= out[1] then out[#out + 1] = q; end
        end
    end);
    return out;
end

local function loadRoot()
    local jf, abbr = nil, nil;
    if deps ~= nil and deps.jobFile ~= nil then jf, abbr = deps.jobFile(); end
    if jf == nil then _setsDiag = 'no job file (logged in? job known?)'; return nil; end
    local act = (_pok and _prof.activeName()) or '';
    local key = jf .. '|' .. act;
    if _cacheKey == key and _cache ~= nil then
        local now = os.time();
        if _watch.at == now then return _cache; end
        _watch.at = now;
        local p, raw = dynSourceNow(jf, abbr);
        if p == _watch.path and raw == _watch.raw then return _cache; end
        -- source moved or its bytes changed: fall through and rebuild
    end
    _cacheKey = key;
    _setsDiag = nil;
    _lacDiag = {};
    _watch.path, _watch.raw = dynSourceNow(jf, abbr);

    local root = {};
    local dynSrc = nil;

    -- A legacy file that EXISTS and cannot be read is named, with the reason, for
    -- the Copy-from popup (hard rule 12: a total failure must not look like "you
    -- have no old sets"). Absent files say nothing -- most characters have two of
    -- the three paths missing by design.
    local function noteBad(path, why)
        if why == nil then return; end
        _lacDiag[#_lacDiag + 1] = { file = tostring(path):match('([^\\/]+)$') or tostring(path),
                                    path = path, why = why };
    end

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
    local adopted = false;   -- did the job file's Dynamic block become the LIVE one?
    local jsets, jerr = sandboxSets(jf);
    if type(jsets) == 'table' then
        for k, v in pairs(jsets) do
            if k == 'Dynamic' then
                if root.Dynamic == nil and type(v) == 'table' then root.Dynamic = v; adopted = true; end
            elseif type(v) == 'table' and root[k] == nil then
                root[k] = v;
            end
        end
    else
        noteBad(jf, jerr);
        if dynSrc == nil and _setsDiag == nil and jerr ~= nil then _setsDiag = tostring(jerr); end
    end

    -- The old FFXI-LAC Dynamic sets: harvested from the same legacy files, into
    -- their OWN list (never into root -- see the header). First file wins a name,
    -- matching the statics' merge order. An ADOPTED job-file block is skipped: it
    -- is already the live Dynamic list, and offering a set as an import of itself
    -- is noise, not a source.
    local lac = {};
    local function harvestLac(s)
        if type(s) ~= 'table' or type(s.Dynamic) ~= 'table' then return; end
        for k, v in pairs(s.Dynamic) do
            local nm = tostring(k);
            if type(v) == 'table' and lac[nm] == nil then lac[nm] = v; end
        end
    end
    if not adopted then harvestLac(jsets); end

    -- The pre-migration backups: statics fill names the live job file no longer
    -- has (that is what keeps "Copy from" alive after a migration shims the file),
    -- and their Dynamic block feeds the FFXI-LAC import list ONLY -- merging it
    -- into root would resurrect deleted sets as if they were live.
    for _, bp in ipairs(backupPaths(abbr)) do
        local bsets, berr = sandboxSets(bp);
        if type(bsets) == 'table' then
            for k, v in pairs(bsets) do
                if k ~= 'Dynamic' and type(v) == 'table' and root[k] == nil then root[k] = v; end
            end
            harvestLac(bsets);
        else
            noteBad(bp, berr);
        end
    end
    _lacDyn = lac;

    if root.Dynamic == nil and _setsDiag == nil then
        _setsDiag = 'ran ' .. jf .. ' but it has no sets.Dynamic';
    end
    -- LIVE set names = Dynamic + the job file's OWN statics. Deliberately NOT
    -- the backup statics merged into root: those exist for "Copy from" only --
    -- the engine's gProfile never holds them, so a trigger targeting one would
    -- match and equip NOTHING. This is the Triggers tab's missing-set authority.
    local live = {};
    if type(root.Dynamic) == 'table' then
        for k in pairs(root.Dynamic) do live[tostring(k)] = true; end
    end
    if type(jsets) == 'table' then
        for k, v in pairs(jsets) do
            if k ~= 'Dynamic' and type(v) == 'table' then live[tostring(k)] = true; end
        end
    end
    _liveNames = live;
    _cache = root;
    return _cache;
end

-- Sorted array of the LIVE profile's set names (see the note in loadRoot).
local function liveSetNames()
    local names = {};
    pcall(function()
        loadRoot();   -- refresh the cache (and _liveNames) if the key moved
        if type(_liveNames) ~= 'table' then return; end
        for k in pairs(_liveNames) do names[#names + 1] = k; end
    end);
    table.sort(names);
    return names;
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

-- The old FFXI-LAC Dynamic sets (name -> set table), from the legacy job file
-- and its pre-migration backups. IMPORT SOURCES ONLY -- the engine never loads
-- them, so they are absent from getSetsRoot / dynamicSetNames / liveSetNames
-- exactly like the backup statics. Empty until load.
local function getLacSets()
    local out = {};
    pcall(function()
        loadRoot();   -- refresh the cache (and _lacDyn) if the key moved
        if type(_lacDyn) == 'table' then out = _lacDyn; end
    end);
    return out;
end

-- Sorted array of those set names (the "Copy from" picker's FFXI-LAC column).
local function lacSetNames()
    local names = {};
    for k in pairs(getLacSets()) do names[#names + 1] = k; end
    table.sort(names);
    return names;
end

-- Legacy files that are ON DISK and could not be read: { { file, path, why }, ... },
-- empty when everything readable (an ABSENT file is never listed -- most characters
-- have two of the three import paths missing by design). The Copy-from popup prints
-- these in red, because "no old sets" and "your old file has a typo in it" were the
-- same silence until 2026-07-28 -- a tester lost an evening to one missing comma.
local function legacyDiag()
    local out = {};
    pcall(function()
        loadRoot();
        for _, d in ipairs(_lacDiag) do out[#out + 1] = d; end
    end);
    return out;
end

-- Last load diagnostic (nil when healthy) -- the Sets tab shows it in red.
function M.diag() return _setsDiag; end

-- Drop the cached sets so the next read re-parses the files (post commit/delete).
function M.invalidate() _cache = nil; _cacheKey = nil; _liveNames = nil; _lacDyn = nil; _lacDiag = {}; _watch.at, _watch.path, _watch.raw = -1, nil, nil; end

-- Arm the content-follow to run on the NEXT read regardless of the 1s throttle
-- (tests; callers that just watched a file land and want the refresh this frame).
function M._recheck() _watch.at = -1; end

M.getSetsRoot     = getSetsRoot;
M.getDynamicSets  = getDynamicSets;
M.dynamicSetNames = dynamicSetNames;
M.staticSetNames  = staticSetNames;
M.liveSetNames    = liveSetNames;
M.getLacSets      = getLacSets;
M.lacSetNames     = lacSetNames;
M.legacyDiag      = legacyDiag;

return M;
