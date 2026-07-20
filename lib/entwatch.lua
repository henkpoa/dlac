--[[
    dlac/lib/entwatch.lua -- the CENTRAL entity watcher (Henrik, field round 6:
    "a point that scans all loaded entities, where you can apply for things you
    look for and who is looking for it, [and that] keeps track of the current
    distances to the active monitored entities").

    One shared sweep instead of every feature growing its own scan -- and ONE
    home for the idioms that cost AutoAmmo two field rounds of always-red
    buttons (and gearmove a field round before that):

      * IEntity::GetRawEntity for existence -- luashitacast's CheckForNomad
        calls a NONEXISTENT GetEntity(i): dead code, never copy it.
      * RenderFlags0 bit 0x200 = rendered, read as signed u32 (+2^32 fix),
        required before trusting a distance -- unrendered slots carry stale
        garbage.
      * GetName returns TRAILING-WHITESPACE names: every compare is trimmed +
        case-insensitive.
      * GetDistance is SQUARED (the distance addon's convention); yalms out.
      * The WHOLE array 0x000-0x8FF: CatsEyeXI's custom NPCs (E-Boxes) are
        DYNAMIC entities (live sample 17737730 = zone 234, index 0x802) --
        a statics-only sweep can never see them.

    Model: consumers SUBSCRIBE -- watch(who, name [, cb]) -- and read back
    through nearest()/matches(). Two cadences: a FULL name sweep every
    SWEEP_S (spawn/despawn discovery, one pass serving every active watch)
    and a fast DIST_S refresh of already-matched indices (each re-verifies
    its name -- entity slots get REUSED; a failed verify drops the index and
    the next sweep re-finds it). A watch with a callback is standing interest
    (cb fires on every match-SET change); a callback-less watch only costs
    sweeps while somebody actually polled within IDLE_S -- an idle client
    with subscriptions nobody reads does zero work.

    Everything is probe-injected and runs headless (tests EW*); the Ashita
    tick + reads live at the bottom, guarded.
]]--

local M = {};

M.SWEEP_S = 2.0;    -- full-array name sweep cadence (discovery)
M.DIST_S  = 0.25;   -- tracked-index distance refresh cadence
M.IDLE_S  = 15;     -- a polled (callback-less) watch sleeps this long after its last ask

-- lower(trimmed name) -> { subs = { who -> cb|true }, matches = { idx ->
-- distSq }, lastAsk, lastSweep, lastDist }
local _reg = {};

function M._now() return os.clock(); end   -- injectable (headless tests)

local function keyOf(name)
    local k = string.lower(tostring(name or ''):gsub('%s+$', ''));
    return (k ~= '') and k or nil;
end

local function entryOf(name, create)
    local key = keyOf(name);
    if key == nil then return nil; end
    local e = _reg[key];
    if e == nil and create then
        e = { subs = {}, matches = {}, lastAsk = -1e9, lastSweep = -1e9, lastDist = -1e9 };
        _reg[key] = e;
    end
    return e, key;
end

-- Subscribe: `who` names the consumer (so a module's watches can be dropped
-- wholesale), `name` is the entity display name, `cb(matches)` is optional --
-- fired (pcall'd) whenever the match SET changes (spawn/despawn/slot moved),
-- with the same sorted array matches() returns.
function M.watch(who, name, cb)
    if type(who) ~= 'string' or who == '' then return false; end
    local e = entryOf(name, true);
    if e == nil then return false; end
    e.subs[who] = (type(cb) == 'function') and cb or true;
    return true;
end

-- Drop `who`'s watch on `name`, or ALL of `who`'s watches when name is nil.
-- The last subscriber leaving tears the entry down (no orphan sweeps).
function M.unwatch(who, name)
    if name ~= nil then
        local e, key = entryOf(name, false);
        if e ~= nil then
            e.subs[who] = nil;
            if next(e.subs) == nil then _reg[key] = nil; end
        end
        return;
    end
    for key, e in pairs(_reg) do
        e.subs[who] = nil;
        if next(e.subs) == nil then _reg[key] = nil; end
    end
end

-- Force the next tick's sweep for `name` (cache-bust; eboxammo's rescan).
function M.poke(name)
    local e = entryOf(name, false);
    if e ~= nil then e.lastSweep, e.lastDist = -1e9, -1e9; end
end

local function activeAt(e, now)
    if next(e.subs) == nil then return false; end
    for _, cb in pairs(e.subs) do
        if type(cb) == 'function' then return true; end   -- standing interest
    end
    return (now - e.lastAsk) <= M.IDLE_S;                 -- polled: demand-windowed
end

-- Sorted snapshot of an entry's matches (what callbacks receive).
local function snapOf(e)
    local snap = {};
    for idx, d in pairs(e.matches) do
        snap[#snap + 1] = { idx = idx, dist = math.sqrt(d), distSq = d };
    end
    table.sort(snap, function(a, b) return a.distSq < b.distSq; end);
    return snap;
end

local function fireCbs(e)
    local snap = nil;
    for _, cb in pairs(e.subs) do
        if type(cb) == 'function' then
            snap = snap or snapOf(e);
            pcall(cb, snap);
        end
    end
end

-- Sorted snapshot: { { idx, dist (yalms), distSq }, ... } nearest-first.
function M.matches(name)
    local e = entryOf(name, false);
    local out = {};
    if e == nil then return out; end
    e.lastAsk = M._now();
    for idx, d in pairs(e.matches) do
        out[#out + 1] = { idx = idx, dist = math.sqrt(d), distSq = d };
    end
    table.sort(out, function(a, b) return a.distSq < b.distSq; end);
    return out;
end

-- Nearest match: dist (yalms), idx -- or nil when none is currently tracked.
-- Also marks live demand (the polled-watch activity window).
function M.nearest(name)
    local e = entryOf(name, false);
    if e == nil then return nil; end
    e.lastAsk = M._now();
    local best, bi = nil, nil;
    for idx, d in pairs(e.matches) do
        if best == nil or d < best then best, bi = d, idx; end
    end
    if best == nil then return nil; end
    return math.sqrt(best), bi;
end

-- ---------------------------------------------------------------------------
-- The two passes, pure (probe = { present(idx) -> exists AND rendered,
-- name(idx) -> string|nil, distSq(idx) -> number|nil }).
-- ---------------------------------------------------------------------------

-- ONE full pass serving every due watch. Returns true when a sweep ran.
function M._sweep(probe, now)
    local due = nil;
    for key, e in pairs(_reg) do
        if activeAt(e, now) and (now - e.lastSweep) >= M.SWEEP_S then
            due = due or {};
            due[key] = {};
        end
    end
    if due == nil then return false; end
    for idx = 0, 2303 do   -- 0x000-0x8FF: statics AND dynamics (see header)
        if probe.present(idx) == true then
            local nm = keyOf(probe.name(idx));
            local f = (nm ~= nil) and due[nm] or nil;
            if f ~= nil then
                local d = probe.distSq(idx);
                if type(d) == 'number' and d >= 0 then f[idx] = d; end
            end
        end
    end
    for key, f in pairs(due) do
        local e = _reg[key];
        e.lastSweep = now;
        local changed = false;
        for idx in pairs(f) do
            if e.matches[idx] == nil then changed = true; break; end
        end
        if not changed then
            for idx in pairs(e.matches) do
                if f[idx] == nil then changed = true; break; end
            end
        end
        e.matches = f;
        if changed then fireCbs(e); end
    end
    return true;
end

-- Fast refresh of tracked indices: distance updates between sweeps, name
-- RE-VERIFIED per index (slot reuse would otherwise track a stranger). An
-- eviction here CHANGES the match set, so it notifies like a sweep would --
-- otherwise a despawn between sweeps would never fire (the next sweep
-- compares against the already-evicted set and sees no change).
function M._refresh(probe, now)
    for key, e in pairs(_reg) do
        if activeAt(e, now) and next(e.matches) ~= nil and (now - e.lastDist) >= M.DIST_S then
            e.lastDist = now;
            local evicted = false;
            for idx in pairs(e.matches) do
                local ok = (probe.present(idx) == true) and (keyOf(probe.name(idx)) == key);
                if ok then
                    local d = probe.distSq(idx);
                    if type(d) == 'number' and d >= 0 then e.matches[idx] = d; end
                else
                    e.matches[idx] = nil;   -- gone or reused; the sweep re-finds
                    evicted = true;
                end
            end
            if evicted then fireCbs(e); end
        end
    end
end

-- Registry introspection for diagnostics (/dl ebox prints through this).
function M.debugState()
    local out = {};
    for key, e in pairs(_reg) do
        local subs = {};
        for who in pairs(e.subs) do subs[#subs + 1] = who; end
        table.sort(subs);
        local n = 0;
        for _ in pairs(e.matches) do n = n + 1; end
        out[#out + 1] = { name = key, subs = table.concat(subs, ','), matches = n,
                          active = activeAt(e, M._now()) };
    end
    table.sort(out, function(a, b) return a.name < b.name; end);
    return out;
end

-- ---------------------------------------------------------------------------
-- Ashita glue, guarded (headless: nothing registers, the pure halves are the
-- module). The probe is built once -- the entity manager pointer is stable.
-- ---------------------------------------------------------------------------
local _probe = nil;
local function liveProbe()
    if _probe ~= nil then return _probe; end
    local em = AshitaCore:GetMemoryManager():GetEntity();
    _probe = {
        present = function(idx)
            local ok = false;
            pcall(function()
                if em:GetRawEntity(idx) == nil then return; end
                local rf = em:GetRenderFlags0(idx) or 0;
                if rf < 0 then rf = rf + 4294967296; end     -- signed u32 -> unsigned
                ok = (math.floor(rf / 0x200) % 2) == 1;      -- bit 0x200: rendered
            end);
            return ok;
        end,
        name = function(idx)
            local n = nil;
            pcall(function() n = em:GetName(idx); end);
            return n;
        end,
        distSq = function(idx)
            local d = nil;
            pcall(function() d = em:GetDistance(idx); end);
            return d;
        end,
    };
    return _probe;
end

pcall(function()
    ashita.events.register('d3d_present', 'dlac_entwatch_tick', function()
        pcall(function()
            if next(_reg) == nil then return; end   -- nobody watching: zero work
            local now = M._now();
            local probe = liveProbe();
            M._refresh(probe, now);
            M._sweep(probe, now);
        end);
    end);
end);

return M;
