--[[
    dlac/feature/modcfg.lua -- the MODULE SETTINGS STORE, provided by the
    framework instead of copied by every module.

    A Job helper declares WHAT it stores; this owns HOW:

        -- in init.lua's contract table
        config = {
            file     = 'jobhelper-bst.lua',        -- optional; default 'jobhelper-<id>.lua'
            keys     = { fight = 'string', rewardArmed = 'boolean', ... },
            defaults = { fight = 'off',    rewardArmed = false,     ... },
        },

    ...and the loader hands the module back a live store as `S.cfg`:

        S.cfg.get('fight')          -> the stored value, or the declared default
        S.cfg.set('fight', 'follow')-> true when it is now in effect
        S.cfg.forget()              -> drop the in-memory copy (character switch)
        S.cfg.path()                -> the file this store writes, or nil pre-login

    WHY THIS IS THE FRAMEWORK'S JOB. `jobhelpers/bst/bst-helper/config.lua` was
    193 lines, of which about forty were BST's (the key list and the defaults) and
    the rest was serialize / normalize / load-once / write-on-mutation -- the
    Statefile policy, which is identical for every module that will ever exist.
    The authoring guide's honest advice was "copy it", and copy-paste is a poor
    distribution mechanism for a policy: the next module inherits today's version
    of it forever, and a fix to the policy has to be applied N times by N authors.

    THE POLICY, once, here (the ammo-config / jobhelpers precedent -- a plain
    write with a tolerant reader, NOT the atomic gear.lua ladder):

      * FORMAT-VERSIONED (`fmt = 1`).
      * DECLARED KEYS OF THE DECLARED TYPE ONLY. Anything else on disk is dropped
        on the way in -- a hand-edit, a torn write, or a key from a NEWER dlac
        cannot survive silently into an older one.
      * WRITTEN ON MUTATION ONLY. A character who never touches a switch never
        grows the file, and an unchanged value never touches the disk.
      * LOADED ONCE PER CHARACTER, re-keyed on the character directory, so a
        second login gets its own file.
      * NEVER CACHES THE PRE-LOGIN NIL (hard rule 11). Before login the directory
        is unknown; the store serves declared defaults and retries the next call.
      * SORTED OUTPUT, so an unchanged config re-serializes byte-identical and a
        reader can skip the re-parse.
      * SCALARS ONLY -- string / number / boolean. A setting that wants a table is
        a setting that wants a design conversation, not a serializer.

    THE FILE IS THE MODULE'S OWN, and that is a separability requirement rather
    than a storage preference: one file per module is part of what makes a module
    removable, and therefore part of what makes it approvable on its own. The
    FRAMEWORK's file (<char>\dlac\jobhelpers.lua -- pills, section order, the
    Claim Priority anchor) is never touched from here.

    House shape: the two halves that decide the format -- `serialize` and
    `normalize` -- are PURE (spec + table in, text/table out), so the format is
    a headless check with no character and no disk (tests MC*). `open` closes over
    one store's state, so N modules get N independent stores from one policy.

    Pure at load; every require / file touch is call-time under pcall.
]]--

local M = {};

M.FMT = 1;

-- The value types a setting may have. Deliberately closed -- see the header.
M.TYPES = { string = true, number = true, boolean = true };

-- The <char>\dlac\ dir resolver (lib\statefile -> profiles.dataDir). Injectable
-- as a whole so headless tests point it at a scratch dir; nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
M._charDir = (_sfok and type(_sfile) == 'table' and type(_sfile.charDir) == 'function')
    and _sfile.charDir or function() return nil; end;

-- ---------------------------------------------------------------------------
-- validation -- the loader calls this, and refuses the module on a reason
-- ---------------------------------------------------------------------------
--
-- Returns true, or nil + a reason string suitable for the loud refusal line.
-- Strict on purpose: a settings declaration that does not say what it stores is
-- a contract violation, and it is far cheaper to hear about it at load than to
-- discover at runtime that a value never persisted.
function M.validate(spec)
    if type(spec) ~= 'table' then return nil, 'config is not a table'; end
    if type(spec.keys) ~= 'table' then return nil, 'config.keys is missing'; end
    local any = false;
    for k, t in pairs(spec.keys) do
        if type(k) ~= 'string' or k == '' then return nil, 'a config key is not a name'; end
        if M.TYPES[t] ~= true then
            return nil, string.format('config key %q declares type %s (want string/number/boolean)',
                tostring(k), tostring(t));
        end
        any = true;
    end
    if not any then return nil, 'config.keys is empty'; end
    if spec.defaults ~= nil and type(spec.defaults) ~= 'table' then
        return nil, 'config.defaults is not a table';
    end
    for k, v in pairs((type(spec.defaults) == 'table') and spec.defaults or {}) do
        if spec.keys[k] == nil then
            return nil, string.format('config.defaults names %q, which config.keys does not declare',
                tostring(k));
        end
        if type(v) ~= spec.keys[k] then
            return nil, string.format('config default for %q is a %s, declared %s',
                tostring(k), type(v), tostring(spec.keys[k]));
        end
    end
    if spec.file ~= nil and (type(spec.file) ~= 'string' or spec.file == '') then
        return nil, 'config.file is not a filename';
    end
    return true;
end

-- The filename a spec writes to. A module that does not name one gets
-- 'jobhelper-<id>.lua', which is unique because module ids are unique addon-wide.
function M.fileFor(id, spec)
    local f = (type(spec) == 'table') and spec.file or nil;
    if type(f) == 'string' and f ~= '' then return f; end
    return 'jobhelper-' .. tostring(id) .. '.lua';
end

-- ---------------------------------------------------------------------------
-- the pure format halves
-- ---------------------------------------------------------------------------

-- Serialize a settings table to the file format. Keys are emitted SORTED, and
-- only declared keys of the declared type are emitted at all.
function M.serialize(spec, cfg)
    local keys = (type(spec) == 'table' and type(spec.keys) == 'table') and spec.keys or {};
    cfg = (type(cfg) == 'table') and cfg or {};
    local names = {};
    for k in pairs(cfg) do
        if keys[k] ~= nil and type(cfg[k]) == keys[k] then names[#names + 1] = k; end
    end
    table.sort(names);
    local out = { 'return {\n', string.format('    fmt = %d,\n', M.FMT) };
    for _, k in ipairs(names) do
        local v = cfg[k];
        if type(v) == 'string' then
            out[#out + 1] = string.format('    [%q] = %q,\n', k, v);
        elseif type(v) == 'number' then
            out[#out + 1] = string.format('    [%q] = %s,\n', k, tostring(v));
        elseif type(v) == 'boolean' then
            out[#out + 1] = string.format('    [%q] = %s,\n', k, v and 'true' or 'false');
        end
    end
    out[#out + 1] = '}\n';
    return table.concat(out);
end

-- Normalize a table read off disk: declared keys of the declared type only.
-- Anything else -- a newer dlac's key, a hand-edit, a torn write -- is dropped,
-- and the caller then sees the declared default.
function M.normalize(spec, t)
    local keys = (type(spec) == 'table' and type(spec.keys) == 'table') and spec.keys or {};
    local cfg = { fmt = M.FMT };
    if type(t) ~= 'table' then return cfg; end
    for k, want in pairs(keys) do
        if type(t[k]) == want then cfg[k] = t[k]; end
    end
    return cfg;
end

-- ---------------------------------------------------------------------------
-- open -- one independent store per module
-- ---------------------------------------------------------------------------
--
-- `spec` is the module's declared config table; `id` is its identity (the folder
-- name), used for the default filename. `charDir` overrides the directory
-- resolver for this store alone (tests). Returns the store table.
--
-- A store is closures over ITS OWN state, so two modules never share a cache,
-- and a test can open a scratch store without disturbing the live one.
function M.open(id, spec, charDir)
    spec = (type(spec) == 'table') and spec or { keys = {} };
    local defaults = (type(spec.defaults) == 'table') and spec.defaults or {};
    local file     = M.fileFor(id, spec);
    local dirOf    = (type(charDir) == 'function') and charDir or function() return M._charDir(); end;

    local _cfg    = nil;    -- the loaded settings table
    local _cfgFor = nil;    -- the <char>\dlac\ dir _cfg was loaded for

    local store = {};

    -- The file this store writes, or nil pre-login.
    function store.path()
        local dir = dirOf();
        if type(dir) ~= 'string' or dir == '' then return nil; end
        return dir .. file;
    end

    -- Load once per character. Pre-login (nil dir) leaves _cfg nil and retries on
    -- the next call -- never caches the nil.
    local function load()
        local dir = dirOf();
        if type(dir) ~= 'string' or dir == '' then return nil; end
        if _cfgFor == dir and _cfg ~= nil then return _cfg; end
        _cfgFor = dir;
        local loaded = nil;
        pcall(function()
            local chunk = loadfile(dir .. file);
            if chunk == nil then return; end
            local ok, t = pcall(chunk);
            if ok then loaded = t; end
        end);
        _cfg = M.normalize(spec, loaded);
        return _cfg;
    end
    store._load = load;   -- test seam

    local function save()
        pcall(function()
            local p = store.path();
            if p == nil or _cfg == nil then return; end
            local f = io.open(p, 'wb');
            if f == nil then return; end
            f:write(M.serialize(spec, _cfg));
            f:close();
        end);
    end
    store._save = save;   -- test seam

    -- Read a setting. Falls back to the declared default pre-login and for an
    -- unset key, so callers never branch on "no file yet".
    function store.get(key)
        if spec.keys[key] == nil then return nil; end
        local cfg = load();
        -- Plain if, not `(cfg ~= nil) and cfg[key] or nil` -- the documented
        -- ternary trap. A stored `false` would come back as the DEFAULT under the
        -- and/or form, and boolean settings are the common case here.
        local v = nil;
        if cfg ~= nil then v = cfg[key]; end
        if v == nil then return defaults[key]; end
        return v;
    end

    -- Write a setting (mutation only). Returns true when the value is now in
    -- effect, false when it could not be stored (pre-login, undeclared key,
    -- wrong type).
    function store.set(key, value)
        local want = spec.keys[key];
        if want == nil or type(value) ~= want then return false; end
        local cfg = load();
        if cfg == nil then return false; end        -- pre-login: nothing to write to
        if cfg[key] == value then return true; end  -- unchanged: no write
        cfg[key] = value;
        save();
        return true;
    end

    -- Drop the in-memory copy so the next read re-loads from disk (test seam;
    -- also the honest answer to a character switch).
    function store.forget()
        _cfg, _cfgFor = nil, nil;
    end

    -- What this store declares (a Panel that wants to enumerate its own keys, and
    -- the tests).
    function store.keys()    return spec.keys; end
    function store.defaults() return defaults; end

    return store;
end

return M;
