--[[
    dlac/feature/jobhelpers.lua -- the Job helper module system (issue #137,
    PRD #135). Revives the parked plugin-folder design (integration-surface
    doc section 10) as FIRST-PARTY modules.

    A Job helper is a drop-in FOLDER under addons\dlac\jobhelpers\ (never a
    loose file). Its <name>\init.lua returns a contract table:

        return {
            api    = 1,                       -- must equal M.API or it is refused
            label  = 'BST Helper',            -- player-facing display label
            jobs   = { 'BST' },               -- declared main jobs (non-empty)
            init   = function(deps) end,      -- optional; shared services in
            panel  = function(ctx) end,       -- required; renders the Panel
            status = function(ctx) end,       -- optional; extra row-status draw
        }

    IDENTITY is the FOLDER NAME, never a self-declared id: the folder is the
    unit of server approval (Pup-Helper precedent), so the name on disk is the
    authority. A module carrying its own `id` cannot masquerade as another.

    Containment is the whole point (hard rules 6, 12): a wrong `api`, a folder
    whose init.lua is missing/malformed, or a module whose init THROWS gets ONE
    loud chat line and is dropped -- never a crash, never collateral damage to
    the other modules or the tab. Failures feed the SAME load ledger dlac.lua
    stashes (package.loaded['dlac\\loadledger']) so `/dl check` counts modules
    honestly and names the failures.

    The house shape: the loader CORE (M.loadAll) takes injected seams -- the
    directory scan, the per-module loader, the ledger, the emitter -- so the
    good / wrong-api / throwing fixtures drive it headlessly with no filesystem
    (tests JH*). The live glue (M.load) wires the real scan + require + chatfmt.

    Pure definitions at load; every AshitaCore/require touch is call-time under
    pcall, so the module loads freely in both Lua states and the headless suite.
]]--

local M = {};

-- The module contract version. A module's `api` must equal this exactly; a
-- mismatch is a LOUD refusal (a module built for an older/newer dlac fails
-- visibly instead of misbehaving quietly -- PRD user story 9). Bump on any
-- breaking change to the contract.
M.API = 1;

-- Loaded modules, in registration order (= the order the loader saw them =
-- alphabetical by folder, since the scan sorts). Each entry:
--   { id = <folder>, label, jobs = {..}, mod = <contract table> }
M.modules = {};

-- ---------------------------------------------------------------------------
-- the config store (per-character, statefile-shaped) -- see lib/statefile
-- ---------------------------------------------------------------------------
--
-- ONE per-character file, <char>\dlac\jobhelpers.lua, format-versioned, holding
-- exactly the two things #137 persists across reloads:
--   enabled = { [id] = bool }         -- the row pill / master switch (default ON)
--   order   = { [JOB] = { id, .. } }  -- the per-job section drag order
-- "sections written on mutation only": a job's order list is created the first
-- time that section is reordered; toggling a pill only touches enabled[id].
-- (A module's own BEHAVIOR settings -- BST's threshold, fight switch -- get
-- their own per-module statefile when those slices land; #137 ships only the
-- pill + order, which this shared file holds. Plain write + tolerant reader,
-- the ammowatch/restock precedent, NOT the atomic gear.lua ladder.)

local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
-- The <char>\dlac\ dir resolver (lib\statefile -> profiles.dataDir). Injectable
-- as a whole so headless config tests point it at a scratch dir; nil pre-login.
M._charDir = (_sfok and type(_sfile) == 'table' and type(_sfile.charDir) == 'function')
    and _sfile.charDir or function() return nil; end;

local _cfg = nil;        -- the loaded config table (fmt/enabled/order)
local _cfgFor = nil;     -- the <char>\dlac\ dir _cfg was loaded for

local function cfgPath()
    local dir = M._charDir();
    return dir and (dir .. 'jobhelpers.lua') or nil;
end

-- Serialize the config to its file format. Pure (table in, text out) so tests
-- check the format with no character or disk. Ids and jobs are emitted sorted
-- so an unchanged config re-serializes byte-identical (a stable file lets a
-- reader skip the re-parse).
function M._serialize(cfg)
    cfg = cfg or {};
    local out = { 'return {\n', '    fmt = 1,\n' };
    -- enabled = { [id] = bool }
    local ids = {};
    for id in pairs(type(cfg.enabled) == 'table' and cfg.enabled or {}) do ids[#ids + 1] = id; end
    table.sort(ids);
    out[#out + 1] = '    enabled = {\n';
    for _, id in ipairs(ids) do
        out[#out + 1] = string.format('        [%q] = %s,\n', tostring(id), cfg.enabled[id] and 'true' or 'false');
    end
    out[#out + 1] = '    },\n';
    -- order = { [JOB] = { id, .. } }
    local jobs = {};
    for job in pairs(type(cfg.order) == 'table' and cfg.order or {}) do jobs[#jobs + 1] = job; end
    table.sort(jobs);
    out[#out + 1] = '    order = {\n';
    for _, job in ipairs(jobs) do
        local list = cfg.order[job];
        if type(list) == 'table' and #list > 0 then
            local parts = {};
            for _, id in ipairs(list) do parts[#parts + 1] = string.format('%q', tostring(id)); end
            out[#out + 1] = string.format('        [%q] = { %s },\n', tostring(job), table.concat(parts, ', '));
        end
    end
    out[#out + 1] = '    },\n';
    out[#out + 1] = '}\n';
    return table.concat(out);
end

-- Normalize a table read off disk into the live shape, tolerating a torn or
-- older file (drop-on-corrupt / self-heal, the watcher-statefile policy).
local function normalizeCfg(t)
    local cfg = { fmt = 1, enabled = {}, order = {} };
    if type(t) ~= 'table' then return cfg; end
    if type(t.enabled) == 'table' then
        for id, v in pairs(t.enabled) do
            if type(id) == 'string' then cfg.enabled[id] = (v == true); end
        end
    end
    if type(t.order) == 'table' then
        for job, list in pairs(t.order) do
            if type(job) == 'string' and type(list) == 'table' then
                local acc, seen = {}, {};
                for _, id in ipairs(list) do
                    if type(id) == 'string' and not seen[id] then seen[id] = true; acc[#acc + 1] = id; end
                end
                if #acc > 0 then cfg.order[job] = acc; end
            end
        end
    end
    return cfg;
end
M._normalizeCfg = normalizeCfg;   -- test seam

-- Load the config ONCE per character (re-keyed on the char dir so a second
-- login gets its own file). Pre-login (nil dir) leaves _cfg nil and retries.
local function loadCfg()
    local dir = M._charDir();
    if dir == nil then return nil; end        -- pre-login: retry next call
    if _cfgFor == dir and _cfg ~= nil then return _cfg; end
    _cfgFor = dir;
    local loaded = nil;
    pcall(function()
        local chunk = loadfile(dir .. 'jobhelpers.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok then loaded = t; end
    end);
    _cfg = normalizeCfg(loaded);
    return _cfg;
end
M._loadCfg = loadCfg;   -- test seam

local function saveCfg()
    pcall(function()
        local p = cfgPath();
        if p == nil or _cfg == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(M._serialize(_cfg));
        f:close();
    end);
end
M._saveCfg = saveCfg;   -- test seam

-- Is a module's pill on? Default ON when the character has never toggled it
-- (a freshly dropped-in module runs; the player silences it, not arms it).
function M.isEnabled(id)
    local cfg = loadCfg();
    if cfg == nil then return true; end        -- pre-login: assume on for display
    local v = cfg.enabled[id];
    if v == nil then return true; end
    return v;
end

-- Flip / set the pill (the row master switch). Writes on mutation only.
function M.setEnabled(id, on)
    if type(id) ~= 'string' then return false; end
    local cfg = loadCfg();
    if cfg == nil then return false; end        -- pre-login: nothing to write to
    local want = (on == true);
    if (cfg.enabled[id] == nil and want == true) then return true; end  -- already default-on
    if cfg.enabled[id] == want then return true; end                    -- no change
    cfg.enabled[id] = want;
    saveCfg();
    return true;
end

-- ---------------------------------------------------------------------------
-- per-job section order (drag-reorder, remembered per job)
-- ---------------------------------------------------------------------------

-- The saved id order for a job, filtered to `presentIds` (a set of ids that
-- actually declare this job right now) and BACKFILLED with any present id the
-- saved list does not mention, appended in the caller's default order. So a
-- newly installed module joins the bottom of the section, an uninstalled one
-- silently drops from the walk, and the player's drag survives reloads.
function M.orderFor(job, defaultIds)
    defaultIds = defaultIds or {};
    local present = {};
    for _, id in ipairs(defaultIds) do present[id] = true; end
    local cfg = loadCfg();
    local saved = (cfg ~= nil and type(cfg.order[job]) == 'table') and cfg.order[job] or {};
    local out, seen = {}, {};
    for _, id in ipairs(saved) do
        if present[id] and not seen[id] then seen[id] = true; out[#out + 1] = id; end
    end
    for _, id in ipairs(defaultIds) do
        if not seen[id] then seen[id] = true; out[#out + 1] = id; end
    end
    return out;
end

-- Move the id at index `from` one step (dir -1 up / +1 down) within a job's
-- CURRENT resolved order, persist it, and return the new order (or nil if the
-- move is a no-op / out of range). Pure list math; the write is the only side
-- effect. Mirrors arbwatch.moveClaimant's one-step swap.
function M.moveInSection(job, defaultIds, from, dir)
    local order = M.orderFor(job, defaultIds);
    local to = from + (dir < 0 and -1 or 1);
    if from < 1 or from > #order or to < 1 or to > #order then return nil; end
    order[from], order[to] = order[to], order[from];
    local cfg = loadCfg();
    if cfg == nil then return nil; end          -- pre-login: cannot persist
    cfg.order[job] = order;                      -- the section is written now (mutation)
    saveCfg();
    return order;
end

-- ---------------------------------------------------------------------------
-- the module-activity predicate (future features consult this too)
-- ---------------------------------------------------------------------------
--
-- PURE core: given a module and injected live reads, decide whether the module
-- is acting and, if not, WHY -- in the fixed precedence the row shows:
--   off  (pill)  ->  wrong main job  ->  town  ->  dead  ->  zoning  ->  active
-- The pill (enabled) is checked FIRST because a silenced module has no reason
-- beyond "you turned it off". Unknown reads (nil job, nil inTown) never
-- manufacture a reason -- the module stays "active" on an unreadable world, the
-- buff-cache discipline (a bad read must not flip behavior).
--
-- reads = { enabled=bool, mainJob=<abbr|nil>, inTown=<bool|nil>,
--           dead=<bool|nil>, zoning=<bool|nil> }
-- returns { active = bool, reason = 'off'|'job'|'town'|'dead'|'zoning'|nil,
--           label = <short human string> }
local REASON_LABEL = {
    off    = 'Off',
    job    = 'Wrong job',
    town   = 'In town',
    dead   = 'Dead',
    zoning = 'Zoning',
};

function M.activityCore(mod, reads)
    reads = reads or {};
    if reads.enabled == false then
        return { active = false, reason = 'off', label = REASON_LABEL.off };
    end
    -- wrong main job: only when the job is KNOWN and not among the module's
    -- declared jobs. A module lists its jobs; current job absent = dormant.
    local mj = reads.mainJob;
    if type(mj) == 'string' and mj ~= '' and mj ~= '?' then
        local ok = false;
        for _, j in ipairs((type(mod) == 'table' and type(mod.jobs) == 'table') and mod.jobs or {}) do
            if j == mj then ok = true; break; end
        end
        if not ok then return { active = false, reason = 'job', label = REASON_LABEL.job }; end
    end
    if reads.zoning == true then return { active = false, reason = 'zoning', label = REASON_LABEL.zoning }; end
    if reads.dead   == true then return { active = false, reason = 'dead',   label = REASON_LABEL.dead   }; end
    if reads.inTown == true then return { active = false, reason = 'town',   label = REASON_LABEL.town   }; end
    return { active = true, reason = nil, label = 'Active' };
end

-- Live reads for the activity predicate, each guarded so a headless / pre-login
-- caller gets nils (unknown), never a crash. Injectable as a whole via
-- M.liveReads for tests; the tab passes the module's pill state in.
function M.liveReads(id)
    local reads = { enabled = M.isEnabled(id) };
    pcall(function()
        local p = gData and gData.GetPlayer and gData.GetPlayer() or nil;
        if type(p) == 'table' then
            reads.mainJob = p.MainJob;
            reads.dead    = (p.Status == 'Dead');
            if p.Status == 'Zoning' then reads.zoning = true; end
        end
    end);
    pcall(function()
        local loc = require('dlac\\feature\\location');
        if type(loc) == 'table' and type(loc.inTown) == 'function' then reads.inTown = loc.inTown(); end
    end);
    -- The authoritative zoning probe (dispatch/helmwatch precedent): GetIsZoning
    -- may return bool OR number.
    pcall(function()
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        if pl ~= nil and pl.GetIsZoning ~= nil then
            local z = pl:GetIsZoning();
            if z == true or (type(z) == 'number' and z ~= 0) then reads.zoning = true; end
        end
    end);
    return reads;
end

-- The one-question service: is this module (by id) acting, and if not why?
function M.activity(id)
    local mod = M.get(id);
    return M.activityCore(mod, M.liveReads(id));
end

-- ---------------------------------------------------------------------------
-- the loader
-- ---------------------------------------------------------------------------

-- Validate a loaded contract table. Returns nil, reason on a bad shape;
-- returns a normalized record on success. `id` is the folder name (authority).
function M._validate(id, mod)
    if type(mod) ~= 'table' then return nil, 'did not return a table'; end
    if mod.api ~= M.API then
        return nil, string.format('api %s, this dlac speaks api %d', tostring(mod.api), M.API);
    end
    if type(mod.label) ~= 'string' or mod.label == '' then return nil, 'missing display label'; end
    if type(mod.jobs) ~= 'table' or #mod.jobs == 0 then return nil, 'missing declared jobs list'; end
    local jobs = {};
    for _, j in ipairs(mod.jobs) do
        if type(j) ~= 'string' or j == '' then return nil, 'a declared job is not a job name'; end
        jobs[#jobs + 1] = j;
    end
    if type(mod.panel) ~= 'function' then return nil, 'missing panel render hook'; end
    if mod.init ~= nil and type(mod.init) ~= 'function' then return nil, 'init is not a function'; end
    if mod.status ~= nil and type(mod.status) ~= 'function' then return nil, 'status is not a function'; end
    return { id = id, label = mod.label, jobs = jobs, mod = mod };
end

-- Record a failure: one loud line + a ledger entry (mod = 'jobhelper:<id>')
-- so `/dl check` lists it among the load failures. Ledger + emit are injected
-- so the headless fixtures assert both.
local function fail(ledger, emit, id, reason)
    local line = string.format('Job helper %s refused: %s', tostring(id), tostring(reason));
    if type(emit) == 'function' then pcall(emit, line); end
    if type(ledger) == 'table' then
        ledger.total  = (tonumber(ledger.total) or 0) + 1;
        ledger.failed = type(ledger.failed) == 'table' and ledger.failed or {};
        ledger.failed[#ledger.failed + 1] = { mod = 'jobhelper:' .. tostring(id), err = tostring(reason) };
    end
end

-- The loader CORE. opts = {
--   names      = { <folder>, .. }         -- candidate module folders (sorted)
--   loadModule = function(id) -> ok, modOrErr   -- require the folder's init
--   deps       = <shared-services table handed to each module's init(deps)>
--   ledger     = <the load ledger table>
--   emit       = function(line)           -- one loud line per failure
-- }
-- Populates M.modules with the survivors, one ledger.total per candidate, and a
-- ledger.failed entry + loud line per refusal. Returns M.modules.
function M.loadAll(opts)
    opts = opts or {};
    M.modules = {};
    local ledger = opts.ledger;
    local emit   = opts.emit;
    local names  = type(opts.names) == 'table' and opts.names or {};
    for _, id in ipairs(names) do
        if type(id) ~= 'string' or id == '' then
            -- skip junk names silently (not a real candidate folder)
        else
            local ok, mod = true, nil;
            if type(opts.loadModule) == 'function' then
                ok, mod = opts.loadModule(id);
            else
                ok, mod = false, 'no loader';
            end
            if not ok then
                fail(ledger, emit, id, 'failed to load (' .. tostring(mod):gsub('%s+', ' '):sub(1, 90) .. ')');
            else
                local rec, reason = M._validate(id, mod);
                if rec == nil then
                    fail(ledger, emit, id, reason);
                else
                    -- init is the module's own code: contain a throw here too.
                    local iok, ierr = true, nil;
                    if type(rec.mod.init) == 'function' then
                        iok, ierr = pcall(rec.mod.init, opts.deps);
                    end
                    if not iok then
                        fail(ledger, emit, id, 'init threw (' .. tostring(ierr):gsub('%s+', ' '):sub(1, 90) .. ')');
                    else
                        if type(ledger) == 'table' then ledger.total = (tonumber(ledger.total) or 0) + 1; end
                        M.modules[#M.modules + 1] = rec;
                    end
                end
            end
        end
    end
    return M.modules;
end

-- ---------------------------------------------------------------------------
-- live glue (Ashita only) -- the default scan + require seams
-- ---------------------------------------------------------------------------

-- The jobhelpers directory: addons\dlac\jobhelpers\. nil headless.
local function jobhelpersDir()
    local dir = nil;
    pcall(function()
        dir = AshitaCore:GetInstallPath() .. 'addons\\dlac\\jobhelpers\\';
    end);
    return dir;
end

-- List candidate module folder names. Folders only: get_dir mixes files and
-- dirs and does not say which, so a name carrying a '.' (a loose file's
-- extension) is skipped -- a module is a FOLDER, never a loose file. Injectable
-- (the profiles._listDirs precedent) so headless tests feed a synthetic listing.
M._listModuleDirs = function()
    local dir = jobhelpersDir();
    if dir == nil then return {}; end
    local names = {};
    pcall(function()
        if not (ashita and ashita.fs and ashita.fs.get_dir) then return; end
        local ok, t = pcall(ashita.fs.get_dir, dir, '.*', false);
        if ok and type(t) == 'table' then
            for _, n in ipairs(t) do
                if type(n) == 'string' and n ~= '.' and n ~= '..' and not n:find('%.') then
                    names[#names + 1] = n;
                end
            end
        end
    end);
    table.sort(names);
    return names;
end

-- Require a module folder's entry (jobhelpers\<id>\init.lua). Returns ok, table
-- | ok=false, err. Injectable so headless tests bypass the require path.
M._requireModule = function(id)
    return pcall(require, 'dlac\\jobhelpers\\' .. id .. '\\init');
end

-- Run the loader against the real filesystem, wiring the load ledger and the
-- chatfmt emitter. Called by dlac.lua AFTER the UI host + main GUI are up so
-- shared services are populated. `deps` is the shared-services table handed to
-- each module's init hook.
function M.load(deps)
    local ledger = nil;
    pcall(function() ledger = require('dlac\\loadledger'); end);
    local emit = function(line) print('[dlac] ' .. line); end
    pcall(function()
        local cf = require('dlac\\chatfmt');
        if type(cf) == 'table' and type(cf.err) == 'function' then emit = cf.err; end
    end);
    return M.loadAll({
        names      = M._listModuleDirs(),
        loadModule = M._requireModule,
        deps       = deps,
        ledger     = ledger,
        emit       = emit,
    });
end

-- ---------------------------------------------------------------------------
-- registry queries (the tab consumes these)
-- ---------------------------------------------------------------------------

function M.count() return #M.modules; end

function M.list() return M.modules; end

function M.get(id)
    for _, rec in ipairs(M.modules) do
        if rec.id == id then return rec.mod; end
    end
    return nil;
end

function M.record(id)
    for _, rec in ipairs(M.modules) do
        if rec.id == id then return rec; end
    end
    return nil;
end

-- The sorted list of jobs that have at least one module (the section headers).
function M.jobs()
    local seen, out = {}, {};
    for _, rec in ipairs(M.modules) do
        for _, j in ipairs(rec.jobs) do
            if not seen[j] then seen[j] = true; out[#out + 1] = j; end
        end
    end
    table.sort(out);
    return out;
end

-- The module ids declaring `job`, in this character's remembered section order.
function M.idsForJob(job)
    local defaults = {};
    for _, rec in ipairs(M.modules) do
        for _, j in ipairs(rec.jobs) do
            if j == job then defaults[#defaults + 1] = rec.id; break; end
        end
    end
    return M.orderFor(job, defaults);
end

return M;
