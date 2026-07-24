--[[
    dlac/feature/restockwatch.lua -- E-Box Restock config + the pure planner
    (docs/design/ebox-restock.md; ADR 0016).

    The GUI's half of E-Box Restock: this module OWNS <char>\dlac\restock.lua and
    every mutation of it, and holds the two PURE cores the whole feature turns on
    (headless-tested, tests RS*):

      * _merge(character, jobList) -- the effective tracked set on a job =
        Character list UNION current-Job list, with a same-id Job entry
        OVERRIDING the Character one (specificity, R3b). Job entries come first
        (the plan fills them first under space pressure), then the character
        entries no job entry shadowed.

      * plan(entries, ctx) -- the slot-safety budget (R4b/R6). Fetchable =
        min(shortfall, in-box, room); a tracked item costs ceil(fetch/stackSize)
        FRESH Inventory slots (each withdrawn stack lands in its own slot and
        never merges into an existing partial on arrival -- Henrik's field law),
        so we NEVER over-draw. Greedy partial fill, job-first; the leftover is
        reported, not dropped. Output carries the flat WITHDRAW `pulls` list the
        eboxclient batch consumes, each packet <= a stack.

    No packets here (that is feature/eboxclient); no engine, no gear. Pure
    config + arithmetic, so the panel and the nudge share ONE answer.

    Storage is a plain per-character config -- NOT a cross-state Statefile: no
    engine ever reads it, so there is no hot-reload handshake, just load once and
    write through on edits (the ammowatch/fishwatch shape).
]]--

local M = {};

-- <char>\dlac\ dir (lib\statefile). nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;
M._charDir = charDir;   -- test seam

-- Live config (defaults are the born-on state: nudge on, quiet mode on).
M.master         = true;
M.showNudge      = true;
M.onlyWhenNeeded = true;
M.character      = {};   -- array of { id, name, ahCat, stack, target }
M.jobs           = {};   -- [JOB] = array of the same
local _stateLoaded = false;

local function statePath()
    local dir = charDir();
    return dir and (dir .. 'restock.lua') or nil;
end

-- ---------------------------------------------------------------------------
-- Pure readers / validation
-- ---------------------------------------------------------------------------
local function readList(lst)
    local out = {};
    if type(lst) ~= 'table' then return out; end
    for _, e in ipairs(lst) do
        if type(e) == 'table' and type(e.name) == 'string' and (tonumber(e.id) or 0) > 0 then
            out[#out + 1] = {
                id     = math.floor(tonumber(e.id)),
                name   = e.name,
                ahCat  = math.floor(tonumber(e.ahCat) or 0),
                stack  = math.max(1, math.floor(tonumber(e.stack) or 1)),
                target = math.max(0, math.floor(tonumber(e.target) or 0)),
            };
        end
    end
    return out;
end
M._readList = readList;

-- A loaded config table -> the normalized shape, defaults filled. Pure (RS*).
-- Settings default TRUE: only an explicit `false` on disk turns one off.
function M._fromTable(t)
    local out = { master = true, showNudge = true, onlyWhenNeeded = true,
                  character = {}, jobs = {} };
    if type(t) ~= 'table' then return out; end
    if t.master == false then out.master = false; end
    if t.showNudge == false then out.showNudge = false; end
    if t.onlyWhenNeeded == false then out.onlyWhenNeeded = false; end
    out.character = readList(t.character);
    if type(t.jobs) == 'table' then
        for j, lst in pairs(t.jobs) do
            if type(j) == 'string' then out.jobs[j] = readList(lst); end
        end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- Serializer, pure (RS*): stable multi-line output, %q for names.
-- ---------------------------------------------------------------------------
local function emitEntry(L, indent, e)
    L[#L + 1] = string.format(
        '%s{ id = %d, name = %q, ahCat = %d, stack = %d, target = %d },',
        indent, tonumber(e.id) or 0, tostring(e.name or ''),
        tonumber(e.ahCat) or 0, math.max(1, tonumber(e.stack) or 1),
        math.max(0, tonumber(e.target) or 0));
end

function M._serialize(cfg)
    cfg = cfg or {};
    local L = {
        '-- dlac E-Box Restock config -- written by the GUI (Automations > E-Box Restock).',
        '-- Per-character; NOT a Statefile (no engine reads it). See docs/design/ebox-restock.md.',
        'return {',
        '    fmt = 1,',
        string.format('    master = %s,', tostring(cfg.master ~= false)),
        string.format('    showNudge = %s,', tostring(cfg.showNudge ~= false)),
        string.format('    onlyWhenNeeded = %s,', tostring(cfg.onlyWhenNeeded ~= false)),
        '    -- Always-on staples (every job). id/name/ahCat/stack learned at',
        '    -- add-time from the box SEARCH row; target defaults to one stack.',
        '    character = {',
    };
    for _, e in ipairs(cfg.character or {}) do emitEntry(L, '        ', e); end
    L[#L + 1] = '    },';
    L[#L + 1] = '    -- Job-specific needs; a same-id entry overrides the character target.';
    L[#L + 1] = '    jobs = {';
    local jk = {};
    for j in pairs(cfg.jobs or {}) do if type(j) == 'string' then jk[#jk + 1] = j; end end
    table.sort(jk);
    for _, j in ipairs(jk) do
        L[#L + 1] = string.format('        [%q] = {', j);
        for _, e in ipairs(cfg.jobs[j] or {}) do emitEntry(L, '            ', e); end
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '}';
    return table.concat(L, '\n') .. '\n';
end

-- ---------------------------------------------------------------------------
-- Load / save
-- ---------------------------------------------------------------------------
local function applyConfig(c)
    M.master, M.showNudge, M.onlyWhenNeeded = c.master, c.showNudge, c.onlyWhenNeeded;
    M.character, M.jobs = c.character, c.jobs;
end

function M.loadState()
    if _stateLoaded then return; end
    local dir = charDir();
    if dir == nil then return; end   -- pre-login: retry next call
    _stateLoaded = true;
    pcall(function()
        local chunk = loadfile(dir .. 'restock.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then applyConfig(M._fromTable(t)); end
    end);
end

local function saveState()
    pcall(function()
        local p = statePath();
        if p == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(M._serialize({ master = M.master, showNudge = M.showNudge,
            onlyWhenNeeded = M.onlyWhenNeeded, character = M.character, jobs = M.jobs }));
        f:close();
    end);
end
M._saveState = saveState;   -- test seam

-- ---------------------------------------------------------------------------
-- THE effective list: Character UNION current-Job, job overrides on same id.
-- Job entries first (filled first under space pressure), then the character
-- entries no job entry shadowed. A shadowing job entry carries `shadow` = the
-- character baseline it overrode (the panel shows "(overrides baseline N)").
-- Pure (RS*).
-- ---------------------------------------------------------------------------
function M._merge(character, jobList)
    character, jobList = character or {}, jobList or {};
    local out, jobIds, charById = {}, {}, {};
    for _, e in ipairs(character) do charById[e.id] = e; end
    for _, e in ipairs(jobList) do
        jobIds[e.id] = true;
        local base = charById[e.id];
        out[#out + 1] = { id = e.id, name = e.name, ahCat = e.ahCat, stack = e.stack,
                          target = e.target, scope = 'job',
                          shadow = base and base.target or nil };
    end
    for _, e in ipairs(character) do
        if not jobIds[e.id] then
            out[#out + 1] = { id = e.id, name = e.name, ahCat = e.ahCat, stack = e.stack,
                              target = e.target, scope = 'character' };
        end
    end
    return out;
end

function M.effectiveList(job)
    return M._merge(M.character, (type(job) == 'string') and M.jobs[job] or nil);
end

-- The distinct ahCats spanned by an effective list -- what the client should
-- GET_CATEGORY (deduped) to learn every tracked item's box count.
function M.categoriesOf(entries)
    local seen, out = {}, {};
    for _, e in ipairs(entries or {}) do
        local c = tonumber(e.ahCat);
        if c ~= nil and c > 0 and not seen[c] then seen[c] = true; out[#out + 1] = c; end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- THE planner (docs/design/ebox-restock.md Section 3). ctx = {
--   onHand(id)->n, inBox(id)->n (0 when uncounted), stackOf(id)->n, freeSlots }.
-- Returns { fetches, pulls, remainder, freeLeft, badge }:
--   fetches   = { { id, name, scope, qty, slots, stack }, ... } (what a click pulls)
--   pulls     = flat { { id, qty<=stack }, ... } for eboxclient.withdrawBatch
--   remainder = { { id, name, want }, ... } deferred for lack of room
--   badge     = # entries with a box-fillable shortfall (want>0), SPACE-INDEPENDENT
-- Pure (RS*).
-- ---------------------------------------------------------------------------
function M.plan(entries, ctx)
    entries = entries or {};
    ctx = ctx or {};
    local onHand  = (type(ctx.onHand)  == 'function') and ctx.onHand  or function() return 0; end;
    local inBox   = (type(ctx.inBox)   == 'function') and ctx.inBox   or function() return 0; end;
    local stackOf = (type(ctx.stackOf) == 'function') and ctx.stackOf or function() return 1; end;
    local free = math.max(0, math.floor(tonumber(ctx.freeSlots) or 0));
    local fetches, pulls, remainder, badge = {}, {}, {}, 0;
    for _, e in ipairs(entries) do
        local s    = math.max(1, math.floor(tonumber(stackOf(e.id)) or 1));
        local have = math.max(0, math.floor(tonumber(onHand(e.id)) or 0));
        local box  = math.max(0, math.floor(tonumber(inBox(e.id)) or 0));
        local short = math.max(0, (math.floor(tonumber(e.target) or 0)) - have);
        local want = math.min(short, box);              -- box-fillable shortfall
        if want > 0 then
            badge = badge + 1;
            local fetch = math.min(want, free * s);     -- whole stacks until Inventory fills
            if fetch > 0 then
                local slots = math.ceil(fetch / s);
                free = free - slots;
                local rem = fetch;
                while rem > 0 do                          -- split into <= stack packets
                    local q = math.min(rem, s);
                    pulls[#pulls + 1] = { id = e.id, qty = q };
                    rem = rem - q;
                end
                fetches[#fetches + 1] = { id = e.id, name = e.name, scope = e.scope,
                                          qty = fetch, slots = slots, stack = s };
                if fetch < want then
                    remainder[#remainder + 1] = { id = e.id, name = e.name, want = want - fetch };
                end
            else
                remainder[#remainder + 1] = { id = e.id, name = e.name, want = want };
            end
        end
    end
    return { fetches = fetches, pulls = pulls, remainder = remainder,
             freeLeft = free, badge = badge };
end

-- "needed" for the nudge (R9): any box-fillable shortfall, space-independent.
function M.needsFetch(entries, ctx)
    return M.plan(entries, ctx).badge > 0;
end

-- ---------------------------------------------------------------------------
-- Mutators (write-through). scope = 'character' | 'job'; job required for 'job'.
-- ---------------------------------------------------------------------------
local function listFor(scope, job, create)
    if scope == 'character' then return M.character; end
    if scope == 'job' and type(job) == 'string' and job ~= '' then
        local l = M.jobs[job];
        if l == nil and create then l = {}; M.jobs[job] = l; end
        return l;
    end
    return nil;
end
M._listFor = listFor;   -- test seam

-- item: { id, name, ahCat, stack, target }. Deduped by id within the list.
function M.addItem(scope, job, item)
    if type(item) ~= 'table' or type(item.name) ~= 'string' or (tonumber(item.id) or 0) <= 0 then
        return false;
    end
    local l = listFor(scope, job, true);
    if l == nil then return false; end
    local id = math.floor(tonumber(item.id));
    for _, e in ipairs(l) do if e.id == id then return false; end end
    local stack = math.max(1, math.floor(tonumber(item.stack) or 1));
    l[#l + 1] = { id = id, name = item.name, ahCat = math.floor(tonumber(item.ahCat) or 0),
                  stack = stack,
                  target = (item.target ~= nil) and math.max(0, math.floor(tonumber(item.target) or 0)) or stack };
    saveState();
    return true;
end

function M.removeItem(scope, job, id)
    local l = listFor(scope, job, false);
    if l == nil then return false; end
    id = math.floor(tonumber(id) or 0);
    for i, e in ipairs(l) do
        if e.id == id then table.remove(l, i); saveState(); return true; end
    end
    return false;
end

function M.setTarget(scope, job, id, n)
    local l = listFor(scope, job, false);
    if l == nil then return false; end
    id = math.floor(tonumber(id) or 0);
    for _, e in ipairs(l) do
        if e.id == id then e.target = math.max(0, math.floor(tonumber(n) or 0)); saveState(); return true; end
    end
    return false;
end

function M.setMaster(on)         M.master = (on == true);         saveState(); end
function M.setShowNudge(on)      M.showNudge = (on == true);      saveState(); end
function M.setOnlyWhenNeeded(on) M.onlyWhenNeeded = (on == true); saveState(); end

return M;
