--[[
    dlac/jobhelpers/bst/config.lua -- the BST Helper's OWN per-character settings
    file (issue #139, PRD #135: "one per-character statefile-shaped config file
    per module, format-versioned, sections created only on mutation").

        <char>\dlac\jobhelper-bst.lua   ->   { fmt = 1, fight = 'follow' }

    Deliberately NOT the shared <char>\dlac\jobhelpers.lua that feature\jobhelpers
    owns: that file holds the FRAMEWORK's state (each module's pill, the per-job
    section order, the Claim Priority anchor) and is written by the loader. A
    module's own BEHAVIOR settings belong to the module -- one file per module is
    what makes a module a separable unit of install and of server approval.

    Storage policy is the ammo-config / jobhelpers precedent, not the gear.lua
    ladder: a plain write with a tolerant reader, and a torn or older file is
    normalized away rather than repaired. Nothing here is engine-seeded, so no
    dispatch.M.VERSION involvement. Written on MUTATION only -- a character who
    never touches the Fight switch never grows the file.

    Keys are declared (M.KEYS) and anything else on disk is dropped, so a future
    slice's key (the Reward threshold, the resummon jug) is one row here and an
    unknown key from a NEWER dlac cannot survive into an older one silently.

    Pure at load; every require / file touch is call-time under pcall, so the
    module loads in the headless suite with no character and no disk.
]]--

local M = {};

M.FILE = 'jobhelper-bst.lua';
M.FMT  = 1;

-- The settings this module persists, and their types. Fight came with #139;
-- the three Reward rows with #140; resummon adds its own when that slice lands.
M.KEYS = {
    fight           = 'string',     -- 'off' | 'attack' | 'follow' (see fight.lua)
    fightHeel       = 'boolean',    -- respect Heel: a send that TOOK is never re-sent (fight.lua)
    rewardArmed     = 'boolean',    -- the automatic Reward rule switch (reward.lua)
    rewardThreshold = 'number',     -- pet HP%; the rule fires strictly below it
    rewardSet       = 'string',     -- the optional Reward set by name; '' = food only
};

-- Defaults for an absent key. The two switches default OFF: this module ISSUES
-- COMMANDS -- and the Reward rule additionally SPENDS AN ITEM -- so a freshly
-- installed helper must never start driving the pet or eating a player's food on
-- its own. The player arms them, unlike the row pill (default on, and it only
-- un-silences). The threshold's default is the PRD's 50; it is the slider's
-- resting position, not an arming decision.
M.DEFAULTS = {
    fight           = 'off',
    fightHeel       = true,         -- respecting the player's own pet command is the
                                    -- polite default (Henrik's option ruling, 2026-07-29)
    rewardArmed     = false,
    rewardThreshold = 50,
    -- rewardSet has no default: absent means "food only" (see reward.setName).
};

-- The <char>\dlac\ dir resolver (lib\statefile -> profiles.dataDir). Injectable
-- as a whole so headless tests point it at a scratch dir; nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
M._charDir = (_sfok and type(_sfile) == 'table' and type(_sfile.charDir) == 'function')
    and _sfile.charDir or function() return nil; end;

local _cfg    = nil;     -- the loaded settings table
local _cfgFor = nil;     -- the <char>\dlac\ dir _cfg was loaded for

local function cfgPath()
    local dir = M._charDir();
    if dir == nil then return nil; end
    return dir .. M.FILE;
end

-- Serialize to the file format. Pure (table in, text out) so the format is
-- testable with no character and no disk. Keys are emitted SORTED so an
-- unchanged config re-serializes byte-identical.
function M._serialize(cfg)
    cfg = (type(cfg) == 'table') and cfg or {};
    local keys = {};
    for k in pairs(cfg) do
        if M.KEYS[k] ~= nil and type(cfg[k]) == M.KEYS[k] then keys[#keys + 1] = k; end
    end
    table.sort(keys);
    local out = { 'return {\n', string.format('    fmt = %d,\n', M.FMT) };
    for _, k in ipairs(keys) do
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
-- Anything else -- a key from a newer dlac, a hand-edit, a torn write -- is
-- dropped, and the caller then sees the default.
function M._normalize(t)
    local cfg = { fmt = M.FMT };
    if type(t) ~= 'table' then return cfg; end
    for k, want in pairs(M.KEYS) do
        if type(t[k]) == want then cfg[k] = t[k]; end
    end
    return cfg;
end

-- Load ONCE per character (re-keyed on the char dir, so a second login gets its
-- own file). Pre-login (nil dir) leaves _cfg nil and retries on the next call --
-- never caches the nil (the statefile rule).
local function load()
    local dir = M._charDir();
    if dir == nil then return nil; end
    if _cfgFor == dir and _cfg ~= nil then return _cfg; end
    _cfgFor = dir;
    local loaded = nil;
    pcall(function()
        local chunk = loadfile(dir .. M.FILE);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok then loaded = t; end
    end);
    _cfg = M._normalize(loaded);
    return _cfg;
end
M._load = load;   -- test seam

local function save()
    pcall(function()
        local p = cfgPath();
        if p == nil or _cfg == nil then return; end
        local f = io.open(p, 'wb');
        if f == nil then return; end
        f:write(M._serialize(_cfg));
        f:close();
    end);
end
M._save = save;   -- test seam

-- Read a setting. Falls back to M.DEFAULTS pre-login and for an unset key, so
-- callers never branch on "no file yet".
function M.get(key)
    if M.KEYS[key] == nil then return nil; end
    local cfg = load();
    -- Plain if, not `(cfg ~= nil) and cfg[key] or nil` -- the documented ternary
    -- trap. No key is a boolean today, but M.KEYS accepts them, and a stored
    -- `false` would come back as the DEFAULT under the `and/or` form.
    local v = nil;
    if cfg ~= nil then v = cfg[key]; end
    if v == nil then return M.DEFAULTS[key]; end
    return v;
end

-- Write a setting (mutation only: an unchanged value never touches the disk).
-- Returns true when the value is now in effect, false when it could not be
-- stored (pre-login, undeclared key, wrong type).
function M.set(key, value)
    local want = M.KEYS[key];
    if want == nil or type(value) ~= want then return false; end
    local cfg = load();
    if cfg == nil then return false; end       -- pre-login: nothing to write to
    if cfg[key] == value then return true; end
    cfg[key] = value;
    save();
    return true;
end

-- Drop the in-memory copy so the next read re-loads from disk (test seam; also
-- the honest answer to a character switch).
function M.forget()
    _cfg, _cfgFor = nil, nil;
end

return M;
