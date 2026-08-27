--[[
    dlac/gear/serverpack.lua -- THE server seam (ADR 0035, supersedes 0001).

    Everything true of a PARTICULAR server lives in a server pack
    (servers\<id>\ + manifest.lua); everything that wants to know about the
    server asks HERE. No other module may read a manifest, compose a
    servers\ require path, or hardcode a server fact that has a manifest home.

    What this module owns:

    * DISCOVERY -- servers\index.lua names the shipped packs (a tracked file,
      not a directory scan: adding a pack is a commit, and a static index
      works identically headless). Each id's manifest is pcall-required;
      a pack whose manifest is missing or malformed simply is not a pack.

    * SELECTION -- one pack present: it is active, no configuration exists
      (the one-install-one-server rule). Several packs: the per-install flag
      file config\addons\dlac\server.lua (`return { server = '<id>' }` --
      the engine-flag pattern) chooses; without it the index's first pack
      wins LOUDLY. No login-time detection: the pack is the declaration.

    * THE VIRTUAL DATA NAMESPACE -- `dlac\data\<file>` remains the require
      vocabulary the whole tree speaks, but no data\ directory exists:
      init() mounts one package.preload entry per file the active manifest
      lists, each resolving to servers\<id>\data\<file>.lua. A file the
      manifest does not list does not resolve, and every existing
      pcall(require, 'dlac\\data\\X') degrades exactly as it always has.

    * QUESTIONS -- active()/name()/manifest() identity; maxLevel() (75 when
      no pack says otherwise); cap('<key>') (false unless declared -- a
      capability the pack does not declare DOES NOT EXIST); const('<key>')
      (nil unless carried); data('<file>') (table or nil, never an error).

    * SERVICES -- provide()/service(): the door a pack MODULE registers a
      live provider through (game-mode detection, prestige state), so core
      can ask a question whose answer only that server's module knows.
      service() of an unregistered name is nil; callers treat nil as
      UNKNOWN and keep their gates closed.

    Pure at load: no AshitaCore touch until init(), and init() itself is
    fully seam-injectable (_require / _configLoader / _emit) so the headless
    suite drives discovery, selection and mounting with no filesystem.
]]--

local M = {};

-- The default the whole addon was built against; a pack overrides via
-- manifest.maxLevel. (The eight historical hardcoded 75s route here.)
M.DEFAULT_MAX_LEVEL = 75;

-- ---------------------------------------------------------------------------
-- state + seams
-- ---------------------------------------------------------------------------
local state = {
    ready    = false,
    active   = nil,    -- pack id string, or nil (no pack: neutral defaults)
    manifest = nil,    -- the active pack's manifest table, or nil
    packs    = {},     -- { { id = ..., manifest = ... }, ... } discovery result
    mounted  = {},     -- the package.preload keys init() installed (for _reset)
};

local services = {};

-- seams (tests override; live code never does)
M._require      = require;
M._configLoader = nil;    -- function() -> table|nil; nil = read the real flag file

local function emit(msg)
    if type(M._emit) == 'function' then pcall(M._emit, msg); return; end
    local ok, cf = pcall(M._require, 'dlac\\chatfmt');
    if ok and type(cf) == 'table' and type(cf.warn) == 'function' then
        pcall(cf.warn, msg);
    else
        print('[dlac] ' .. tostring(msg));
    end
end

-- ---------------------------------------------------------------------------
-- discovery + selection internals
-- ---------------------------------------------------------------------------
local function loadIndex()
    local ok, idx = pcall(M._require, 'dlac\\servers\\index');
    if ok and type(idx) == 'table' then return idx; end
    return {};
end

local function loadManifest(id)
    if type(id) ~= 'string' or id == '' then return nil; end
    local ok, man = pcall(M._require, 'dlac\\servers\\' .. id .. '\\manifest');
    if ok and type(man) == 'table' then return man; end
    return nil;
end

-- The per-install choice: config\addons\dlac\server.lua -> { server = '<id>' }.
-- Only consulted when several packs ship; a broken or absent file reads as
-- "no choice" (the engine-flag failure discipline).
local function configuredId()
    if type(M._configLoader) == 'function' then
        local ok, t = pcall(M._configLoader);
        if ok and type(t) == 'table' and type(t.server) == 'string' then return t.server; end
        return nil;
    end
    local got = nil;
    pcall(function()
        local p = AshitaCore:GetInstallPath() .. 'config\\addons\\dlac\\server.lua';
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' and type(t.server) == 'string' then got = t.server; end
    end);
    return got;
end

-- ---------------------------------------------------------------------------
-- init -- discover, select, mount. Idempotent; call once at boot, before any
-- module can require data. Headless harnesses call it after installing seams.
-- ---------------------------------------------------------------------------
function M.init()
    if state.ready then return; end

    local packs = {};
    for _, id in ipairs(loadIndex()) do
        local man = loadManifest(id);
        if man ~= nil then packs[#packs + 1] = { id = id, manifest = man }; end
    end
    state.packs = packs;

    local chosen = nil;
    local want = configuredId();
    if want ~= nil then
        for _, p in ipairs(packs) do
            if p.id == want then chosen = p; break; end
        end
        if chosen == nil then
            emit(("server config names pack '%s' but no such pack is installed -- falling back."):format(tostring(want)));
        end
    end
    if chosen == nil and #packs == 1 then chosen = packs[1]; end
    if chosen == nil and #packs > 1 then
        chosen = packs[1];
        emit(("several server packs installed and no choice made -- using '%s'. Write config\\addons\\dlac\\server.lua: return { server = '<id>' }"):format(chosen.id));
    end

    if chosen ~= nil then
        state.active   = chosen.id;
        state.manifest = chosen.manifest;
        local files = chosen.manifest.files;
        if type(files) == 'table' then
            for _, name in ipairs(files) do
                local key  = 'dlac\\data\\' .. name;
                local path = 'dlac\\servers\\' .. chosen.id .. '\\data\\' .. name;
                if package.loaded[key] == nil and package.preload[key] == nil then
                    package.preload[key] = function() return M._require(path); end;
                    state.mounted[#state.mounted + 1] = key;
                end
            end
        end
    end
    state.ready = true;
end

-- ---------------------------------------------------------------------------
-- questions
-- ---------------------------------------------------------------------------

-- The active pack id ('cexi', 'ascensionxi', ...) or nil when no pack is
-- installed. nil means NEUTRAL: caps all false, consts all nil, no data.
function M.active() return state.active; end

-- Player-facing server name, or nil. Callers wanting prose fall back
-- themselves ("this server") -- this module never invents a name.
function M.name()
    local m = state.manifest;
    if m ~= nil and type(m.name) == 'string' then return m.name; end
    return nil;
end

function M.manifest() return state.manifest; end

function M.maxLevel()
    local m = state.manifest;
    local n = (m ~= nil) and tonumber(m.maxLevel) or nil;
    return n or M.DEFAULT_MAX_LEVEL;
end

-- true ONLY when the active manifest declares caps.<key> = true.
function M.cap(key)
    local m = state.manifest;
    return (m ~= nil and type(m.caps) == 'table' and m.caps[key] == true) or false;
end

-- The manifest constant, or nil. Callers own their defaults (the historical
-- hardcoded value is the right fallback at every converted site).
function M.const(key)
    local m = state.manifest;
    if m ~= nil and type(m.const) == 'table' then return m.const[key]; end
    return nil;
end

-- The pack data file as a table, or nil -- never an error. Sugar over the
-- virtual namespace, for code written after ADR 0035; older sites keep
-- their own pcall(require, 'dlac\\data\\X') and get the same answer. Uses
-- the REAL require on purpose: the virtual namespace lives in
-- package.loaded/preload (mounted by init(), or preloaded by a harness),
-- and only real require consults those.
function M.data(name)
    local ok, t = pcall(require, 'dlac\\data\\' .. tostring(name));
    if ok and type(t) == 'table' then return t; end
    return nil;
end

-- The pack's hand-maintained SURFACE defaults (servers\<id>\features.lua) --
-- which dlac tabs / menu rows exist on this server out of the box. A separate
-- file from the GENERATED manifest on purpose: gen_pack tooling owns the
-- manifest and would clobber a hand edit. Optional: nil when the pack ships
-- none (or no pack is active), and callers read nil as "everything on".
-- Only an explicit false in the file disables a surface; lib\featuregate is
-- the one consumer and layers the character's own Settings overrides on top.
-- Memoized only once init() has run (a pre-init nil must not latch -- hard
-- rule 11's shape).
function M.features()
    if not state.ready or state.active == nil then return nil; end
    if state.featsRead then return state.feats; end
    state.featsRead = true;
    local ok, t = pcall(M._require, 'dlac\\servers\\' .. state.active .. '\\features');
    state.feats = (ok and type(t) == 'table') and t or nil;
    return state.feats;
end

-- Discovery readout for /dl check: { { id, name }, ... } in index order.
function M.installed()
    local out = {};
    for _, p in ipairs(state.packs) do
        local nm = (type(p.manifest) == 'table' and type(p.manifest.name) == 'string') and p.manifest.name or p.id;
        out[#out + 1] = { id = p.id, name = nm };
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- services -- a pack module's live providers
-- ---------------------------------------------------------------------------
function M.provide(name, impl)
    if type(name) ~= 'string' or name == '' then return; end
    services[name] = impl;
end

function M.service(name) return services[name]; end

-- ---------------------------------------------------------------------------
-- test seams
-- ---------------------------------------------------------------------------
function M._reset()
    for _, key in ipairs(state.mounted) do
        package.preload[key] = nil;
        package.loaded[key]  = nil;
    end
    state = { ready = false, active = nil, manifest = nil, packs = {}, mounted = {} };
    services = {};
end

function M._state() return state; end

return M;
