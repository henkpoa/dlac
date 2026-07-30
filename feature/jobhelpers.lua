--[[
    dlac/feature/jobhelpers.lua -- the Job helper module system (issue #137,
    PRD #135). Revives the parked plugin-folder design (integration-surface
    doc section 10) as FIRST-PARTY modules.

    A Job helper is a drop-in FOLDER under its JOB's directory (never a loose
    file): addons\dlac\jobhelpers\<job>\<module>\ -- Henrik's layout ruling
    2026-07-29, "bst-helper is the module OF bst": the job folder groups, each
    module under it is its own separable folder. The <module>\init.lua returns
    a contract table:

        return {
            api    = 2,                       -- must equal M.API or it is refused
            label  = 'BST Helper',            -- player-facing display label
            jobs   = { 'BST' },               -- declared main jobs (non-empty)
            config = { keys = {}, defaults = {} },  -- optional; the framework stores it
            init   = function(S) end,         -- optional; the module API in
            panel  = function(ctx) end,       -- required; renders the Panel
            status = function(ctx) end,       -- optional; extra row-status draw
        }

    `S` (feature\modapi) is the SUPPORTED surface -- identity, the one clock, the
    services, the act door, the settings store, the widget kit -- built per module
    by the loader. It is not a sandbox (ADR 0028 settled that: visibility and
    contracts, not walls); a module can still require anything. It is the part
    that is documented, versioned and will keep working.

    IDENTITY is the MODULE folder name, never a self-declared id: the folder is
    the unit of server approval (Pup-Helper precedent), so the name on disk is
    the authority. A module carrying its own `id` cannot masquerade as another.
    Names are unique addon-wide (a duplicate under a second job folder is
    refused loudly); the JOB folder only says where the module FILES -- the
    contract's `jobs` list is what decides where it acts and shows, and a
    multi-job module simply files under its primary job.

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
--
-- The version lives in feature\modapi now, because what a module actually
-- depends on is the SERVICE SURFACE, not the shape of this one table -- api 1's
-- gate could only say "your table has the right keys", which was never the thing
-- that broke. It is re-exported here so the loader's own refusal line and the
-- registry keep reading `jobhelpers.API`.
--
--   1 -> init(deps) with { host, jobhelpers }; every other service reached by
--        hardcoded require path, and every module carrying its own copy of the
--        clock, the loud-line emitter, the activity block and the config store.
--   2 -> init(S): the curated module API (feature\modapi), an optional declared
--        `config` block the framework stores for you (feature\modcfg), and the
--        Panel widget kit on ctx.ui (ui\panelkit).
local _maok, _mapi = pcall(require, 'dlac\\feature\\modapi');
M.API = (_maok and type(_mapi) == 'table' and tonumber(_mapi.API)) or 2;

-- Loaded modules, in registration order (= the order the loader saw them =
-- alphabetical by folder, since the scan sorts). Each entry:
--   { id    = <module folder -- the identity>,
--     job   = <job folder it filed under>,
--     label, jobs = {..},
--     mod   = <the contract table it returned>,
--     cfg   = <its settings store, or nil>,
--     S     = <its module API table> }
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
    -- rank = { [JOB] = <anchor row name> } -- the JobHelper Claim Priority
    -- position, per job (issue #138). Written on mutation only, like `order`.
    local rjobs = {};
    for job in pairs(type(cfg.rank) == 'table' and cfg.rank or {}) do rjobs[#rjobs + 1] = job; end
    table.sort(rjobs);
    out[#out + 1] = '    rank = {\n';
    for _, job in ipairs(rjobs) do
        local anchor = cfg.rank[job];
        if type(anchor) == 'string' and anchor ~= '' then
            out[#out + 1] = string.format('        [%q] = %q,\n', tostring(job), anchor);
        end
    end
    out[#out + 1] = '    },\n';
    out[#out + 1] = '}\n';
    return table.concat(out);
end

-- Normalize a table read off disk into the live shape, tolerating a torn or
-- older file (drop-on-corrupt / self-heal, the watcher-statefile policy).
local function normalizeCfg(t)
    local cfg = { fmt = 1, enabled = {}, order = {}, rank = {} };
    if type(t) ~= 'table' then return cfg; end
    if type(t.rank) == 'table' then
        for job, anchor in pairs(t.rank) do
            if type(job) == 'string' and type(anchor) == 'string' and anchor ~= '' then
                cfg.rank[job] = anchor;
            end
        end
    end
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
-- the JobHelper CLAIM PRIORITY position -- remembered PER JOB (issue #138)
-- ---------------------------------------------------------------------------
--
-- Unlike the global Claim Priority order (arbstate), the JobHelper row's rank
-- position is per job. It is stored as the ANCHOR row it sits directly below
-- (robust to other rows moving), default 'Locks' -- above every standing Gear
-- helper, below Locks/Naked/Free equip. Dragging writes the current job's anchor
-- ONLY; jobs never dragged keep the default; a stored anchor stays dormant while
-- no modules are installed and takes effect again the moment one exists
-- (consistent with the unknown-row preservation slice, #136).

local DEFAULT_ANCHOR = 'Locks';

-- The arbiter's placement law, lazily (it owns placeJobHelper + the identity).
local function arbiterMod()
    local a = nil;
    pcall(function() a = require('dlac\\gear\\arbiter'); end);
    return (type(a) == 'table') and a or nil;
end

-- The saved anchor for a job, or the default. nil job -> default.
function M.rankAnchorFor(job)
    if type(job) ~= 'string' or job == '' then return DEFAULT_ANCHOR; end
    local cfg = loadCfg();
    local a = (cfg ~= nil and type(cfg.rank) == 'table') and cfg.rank[job] or nil;
    return (type(a) == 'string' and a ~= '') and a or DEFAULT_ANCHOR;
end

-- Persist the JobHelper anchor for a job (mutation only: a job's rank entry is
-- created the first time that job drags the row). Dropping to the default clears
-- the entry, so "jobs never moved keep the default" stays literally true.
function M.setRankAnchor(job, anchor)
    if type(job) ~= 'string' or job == '' then return false; end
    if type(anchor) ~= 'string' or anchor == '' then return false; end
    local cfg = loadCfg();
    if cfg == nil then return false; end               -- pre-login: nothing to write to
    if cfg.rank[job] == anchor then return true; end   -- no change
    if anchor == DEFAULT_ANCHOR then
        if cfg.rank[job] == nil then return true; end  -- already default
        cfg.rank[job] = nil;
    else
        cfg.rank[job] = anchor;
    end
    saveCfg();
    return true;
end

-- The live rank order with the JobHelper row woven in at THIS job's position, or
-- the base order UNCHANGED when no modules are installed (the row hides). Pure
-- of engine state; `baseOrder` is the sanitized global order (no JobHelper).
function M.placedOrder(baseOrder, job)
    if type(baseOrder) ~= 'table' then return baseOrder; end
    if M.count() < 1 then return baseOrder; end        -- zero modules: row hidden
    local arb = arbiterMod();
    if arb == nil or type(arb.placeJobHelper) ~= 'function' then return baseOrder; end
    return arb.placeJobHelper(baseOrder, M.rankAnchorFor(job));
end

-- Move the JobHelper row one step within a job's CURRENT placed order (dir -1 up
-- / +1 down), persist the new anchor for THAT job, and return the new placed
-- order (or nil on a no-op / illegal move). The ceiling (Disabled) and floor
-- (Triggers) are never crossed; only the JobHelper anchor is written -- the
-- global arbstate is untouched.
function M.moveRankRow(placedOrder, job, dir)
    if type(placedOrder) ~= 'table' then return nil; end
    if type(job) ~= 'string' or job == '' then return nil; end
    local jhName = 'JobHelper';
    local arb = arbiterMod();
    if arb ~= nil and type(arb.JOBHELPER) == 'string' then jhName = arb.JOBHELPER; end
    local from = nil;
    for i, n in ipairs(placedOrder) do if n == jhName then from = i; break; end end
    if from == nil then return nil; end
    local to = from + (dir < 0 and -1 or 1);
    if to < 1 or to > #placedOrder then return nil; end
    if placedOrder[to] == 'Disabled' or placedOrder[to] == 'Triggers' then return nil; end
    local out = {};
    for i, v in ipairs(placedOrder) do out[i] = v; end
    out[from], out[to] = out[to], out[from];
    local anchor = (to > 1) and out[to - 1] or DEFAULT_ANCHOR;   -- the row now above JobHelper
    M.setRankAnchor(job, anchor);
    return out;
end

-- ---------------------------------------------------------------------------
-- the module-activity predicate (future features consult this too)
-- ---------------------------------------------------------------------------
--
-- PURE core: given a module and injected live reads, decide whether the module
-- is acting and, if not, WHY -- in the fixed precedence the row shows:
--   off  (pill)  ->  wrong main job  ->  zoning  ->  dead  ->  town  ->  active
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
    -- The optional `config` block (api 2): the module declares its keys and their
    -- types, the framework owns the file format. Refused LOUDLY on a bad shape
    -- rather than silently dropping writes -- a settings declaration that does not
    -- say what it stores is far cheaper to hear about at load than to discover in
    -- the field when a value turns out never to have persisted.
    if mod.config ~= nil then
        local mc = nil;
        pcall(function() mc = require('dlac\\feature\\modcfg'); end);
        if type(mc) == 'table' and type(mc.validate) == 'function' then
            local ok, reason = mc.validate(mod.config);
            if ok ~= true then return nil, tostring(reason or 'bad config block'); end
        end
    end
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

-- Build the module API table handed to a module's init hook, and exposed to its
-- Panel as ctx.S. One per module, closed over that module's identity, so a module
-- can neither declare its own id nor ask a question as somebody else. Injectable
-- so the loader fixtures drive init with a stub surface.
M._buildApi = function(rec)
    local api = nil;
    pcall(function()
        local ma = require('dlac\\feature\\modapi');
        if type(ma) == 'table' and type(ma.build) == 'function' then api = ma.build(rec); end
    end);
    return api;
end

-- Open a module's declared settings store (nil when it declared no `config`).
-- The module owns the keys; feature\modcfg owns the format.
M._openCfg = function(rec)
    if type(rec) ~= 'table' or type(rec.mod) ~= 'table' or rec.mod.config == nil then return nil; end
    local store = nil;
    pcall(function()
        local mc = require('dlac\\feature\\modcfg');
        if type(mc) == 'table' and type(mc.open) == 'function' then
            store = mc.open(rec.id, rec.mod.config);
        end
    end);
    return store;
end

-- Drop every subscription a module opened through its API table. There is no
-- hot-unplug today (an Ashita reload takes the whole Lua state with it), so this
-- exists for the reload path, the tests, and the day a module can be turned off
-- for real rather than only gated.
function M.unload(id)
    local n = 0;
    pcall(function()
        local ma = require('dlac\\feature\\modapi');
        if type(ma) == 'table' and type(ma.dropAll) == 'function' then n = ma.dropAll(id); end
    end);
    return n;
end

-- The loader CORE. opts = {
--   names      = { <folder>, .. }         -- candidate module folders (sorted)
--   loadModule = function(id) -> ok, modOrErr   -- require the folder's init
--   host       = <ui\uihost>              -- carried on the module API table
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
                    -- Everything the framework knows about this module and the
                    -- module cannot know about itself: the job folder it filed
                    -- under, the UI host, its settings store, and the API table
                    -- built from all three. The ID especially -- api 1 had the
                    -- record in hand right here and passed only `deps`, so every
                    -- module hardcoded its own folder name as a fallback in every
                    -- file that ran without a render ctx.
                    rec.job  = M._jobOf[id];
                    rec.host = (type(opts.deps) == 'table' and opts.deps.host) or opts.host;
                    rec.cfg  = M._openCfg(rec);
                    rec.S    = M._buildApi(rec);

                    -- init is the module's own code: contain a throw here too.
                    local iok, ierr = true, nil;
                    if type(rec.mod.init) == 'function' then
                        iok, ierr = pcall(rec.mod.init, rec.S);
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

-- List one directory's FOLDER names. get_dir mixes files and dirs and does not
-- say which, so a name carrying a '.' (a loose file's extension) is skipped --
-- the profiles._listDirs precedent, mask '.*' never recursive.
local function listDirs(dir)
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

-- List candidate modules, TWO levels deep (Henrik's layout ruling 2026-07-29:
-- `jobhelpers\<job>\<module>\` -- "bst-helper is the module OF bst", so the
-- job folder groups and each module under it is its own separable folder =
-- its own approval unit). Returns { { id = <module folder>, job = <job
-- folder> }, ... } sorted by job then id. The job folder is only WHERE a
-- module FILES; the contract's declared `jobs` list stays what decides where
-- it acts and shows -- a multi-job module lives under its primary job's
-- folder. Injectable so headless tests feed a synthetic listing.
M._listModules = function()
    local root = jobhelpersDir();
    if root == nil then return {}; end
    local out = {};
    for _, job in ipairs(listDirs(root)) do
        for _, id in ipairs(listDirs(root .. job .. '\\')) do
            out[#out + 1] = { id = id, job = job };
        end
    end
    return out;
end

-- id -> job-folder map for the require path (filled by M.load from the scan;
-- a test that drives _requireModule directly can seed it).
M._jobOf = {};

-- Require a module folder's entry (jobhelpers\<job>\<id>\init.lua). Returns
-- ok, table | ok=false, err. Injectable so headless tests bypass the require.
M._requireModule = function(id)
    local job = M._jobOf[id];
    if type(job) ~= 'string' or job == '' then
        return false, 'no job folder recorded for this module';
    end
    return pcall(require, 'dlac\\jobhelpers\\' .. job .. '\\' .. id .. '\\init');
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
    -- The two-level scan, deduped: a module NAME is the identity, so the same
    -- name under two job folders is a collision -- the first (job-sorted) wins
    -- and the second is refused loudly, exactly like any other bad module.
    local names, jobOf = {}, {};
    for _, c in ipairs(M._listModules()) do
        if jobOf[c.id] ~= nil then
            fail(ledger, emit, c.job .. '\\' .. c.id,
                 string.format('duplicate module name (already loaded from %s\\)', jobOf[c.id]));
        else
            jobOf[c.id] = c.job;
            names[#names + 1] = c.id;
        end
    end
    M._jobOf = jobOf;
    return M.loadAll({
        names      = names,
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

-- A module's ACTION-SEQUENCE priority: its position in the CURRENT job's
-- section, as a number where higher wins a simultaneous contention
-- (actionseq.arbitrateRequests). Top-of-section is highest, so the order is
-- (count - index + 1); an unknown module, an unreadable job or a headless
-- caller all answer 1.
--
-- It lives here, not in a module, because it is a fact about the MODULE and its
-- section -- not about whichever of the module's rules happens to be asking.
-- BST's Reward and Resummon share one answer by construction.
function M.sectionOrder(id)
    local order = 1;
    pcall(function()
        local job = nil;
        pcall(function() job = gData.GetPlayer().MainJob; end);
        if type(job) ~= 'string' or job == '' or job == '?' then return; end
        local ids = M.idsForJob(job);
        for i, n in ipairs(ids) do
            if n == id then order = (#ids - i + 1); return; end
        end
    end);
    return order;
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
