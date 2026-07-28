--[[
    dlac/feature/integration.lua -- the Integration surface, COMPLETE v1
    (docs/design/integration-surface.md; consumer contract in
    docs/reference/integration-guide.md). 2026-07-28.

    An ADDON-SIDE OBSERVER over two engine feeds -- the decision ring (v152,
    M.getDecisions: outcomes that MOVED) and the action feed (v154,
    M.getActions: every non-Default dispatch, moved or not) -- plus watches
    and queries. The engine equips gear and reports on its own equipping,
    nothing else (ADR 0014); this module reads records and never derives.

    THE FOUR KINDS, one stream-side monotone `seq` across all of them (a gap
    in seq = the consumer lost something, whatever its kind):
      worn        a decision that moved the outcome -- items/totals/ctx, with
                  `decisionSeq` (the ring's own number) riding for debugging
      dispatch    the ANCHOR: an action dispatched and changed NOTHING --
                  metadata + join key + ctx, no items. One anchor per action:
                  worn when gear moved, dispatch when not, never both.
      invalidate  job or sets-store changed -- cached query answers are stale
      confirm     reality diverged from the newest plan after the round trip
                  (delta-only: a plan that landed whole emits nothing)

    Off by default behind a SESSION switch (/dl stream on|off + a Menu row):
    never written to disk, dies when world absence outlasts a zone
    (M.worldAbsentOutlasted -- the worldWatch law read-only), survives job
    changes (a job change is data: it emits `invalidate`).

    Transport (probed 2026-07-28): SEND a byte table (strings refused);
    the RECEIVER gets the bytes reassembled as a STRING under `e.data`
    (`e.size` = length; `e` is userdata -- named fields, never pairs).
]]--

local M = {};

local _dok, dsp = pcall(require, 'dlac\\dispatch');
local hasDispatch = _dok and type(dsp) == 'table';

M.on = false;            -- THE session switch (never persisted)
M._seq = 0;              -- stream-side envelope counter, all kinds
M._lastRingSeq = 0;      -- newest decision-ring seq already emitted
M._lastASeq = 0;         -- newest action-feed aseq already considered
M.CONFIRM_S = 0.8;       -- plan -> worn-read settle window (injectable in tests)
M._pending = nil;        -- the one scheduled confirm (newest worn wins)
M._watchJob = nil;       -- invalidate watches, baselined at setOn
M._watchSetsRev = nil;

-- ---------------------------------------------------------------------------
-- Serialization: table -> Lua source. Deterministic (array part first, then
-- sorted keys); depth-capped defensively. Exported for tests (IN*).
-- ---------------------------------------------------------------------------
local function ser(v, depth)
    depth = depth or 0;
    local t = type(v);
    if t == 'number' then
        return string.format('%.14g', v);
    elseif t == 'boolean' then
        return tostring(v);
    elseif t == 'string' then
        return string.format('%q', v);
    elseif t ~= 'table' or depth > 7 then
        return 'nil';
    end
    local out, inArray = {}, {};
    for i = 1, #v do
        out[#out + 1] = ser(v[i], depth + 1);
        inArray[i] = true;
    end
    local keys = {};
    for k in pairs(v) do
        if inArray[k] ~= true and (type(k) == 'string' or type(k) == 'number') then
            keys[#keys + 1] = k;
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b); end);
    for _, k in ipairs(keys) do
        local kk;
        if type(k) == 'string' and string.match(k, '^[%a_][%w_]*$') ~= nil then
            kk = k;
        else
            kk = '[' .. ser(k, depth + 1) .. ']';
        end
        out[#out + 1] = kk .. ' = ' .. ser(v[k], depth + 1);
    end
    return '{ ' .. table.concat(out, ', ') .. ' }';
end
M._ser = ser;

local function toBytes(s)
    local t = {};
    for i = 1, #s do t[i] = string.byte(s, i); end
    return t;
end

-- The one send door -- injectable so headless tests collect instead of raise.
M._raise = function(name, bytesTbl)
    AshitaCore:GetPluginManager():RaiseEvent(name, bytesTbl);
end

local function emit(name, tbl)
    local ok, src = pcall(function() return 'return ' .. ser(tbl); end);
    if not ok then return false; end
    return pcall(function() M._raise(name, toBytes(src)); end);
end

local function nextSeq()
    M._seq = M._seq + 1;
    return M._seq;
end

-- gearui's shared doors (lookups, worn reads) -- injectable for headless
-- tests; live it is uihost's services table (provided before first render).
M._services = function()
    local S = nil;
    pcall(function() S = require('dlac\\ui\\uihost').services; end);
    return S;
end

local function charIdentity()
    local nm, id = nil, nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        nm = party:GetMemberName(0);
        id = party:GetMemberServerId(0);
    end);
    return nm, id;
end

local function baseEnv(kind)
    local nm, cid = charIdentity();
    return {
        v = 1, kind = kind, at = os.time(),
        char = nm, charId = cid,
        dlac = (type(addon) == 'table') and addon.version or nil,
        engine = hasDispatch and dsp.VERSION or nil,
    };
end

-- ---------------------------------------------------------------------------
-- Envelope construction (v1 scope: worn + ctx + totals + metadata).
-- ---------------------------------------------------------------------------
local function foldTotals(plan, level)
    local S = M._services();
    local lk = (S ~= nil) and S.lookupByName or nil;
    if lk == nil then return nil, nil; end
    local comp = {};
    for slot, name in pairs(plan or {}) do
        if type(name) == 'string' and name ~= 'remove' then
            local ok, rec = pcall(lk, name);
            if ok and type(rec) == 'table' then comp[slot] = rec; end
        end
    end
    if next(comp) == nil then return nil, nil; end
    local stats, bonuses = nil, nil;
    pcall(function()
        local oracle = require('dlac\\gear\\gearoracle');
        local res = oracle.setStats(comp, { level = tonumber(level) });
        if type(res) == 'table' then
            stats = res.stats;
            bonuses = res.bonuses;
        end
    end);
    return stats, bonuses;
end

local function ctxIdentity(env, c)
    env.event = env.event or nil;
    env.action = c.action;
    env.actionId = c.actionId;
    env.actionCategory = c.actionCategory;
    env.targetIndex = c.targetIndex;
    env.job = c.job; env.jobLevel = c.jobLevel;
    env.sub = c.sub; env.subLevel = c.subLevel;
    env.ctx = c;
end

-- One `worn` envelope from a decision-ring record (or record-shaped table).
-- The caller stamps `seq` (live emission vs query-reply watermark differ).
local function buildWorn(rec, snapshot, source, dropped)
    local c = rec.ctx or {};
    local env = baseEnv('worn');
    env.at = rec.at or env.at;
    env.dropped = dropped or 0;
    env.source = source or 'plan';
    env.snapshot = snapshot == true;
    env.event = rec.event;
    ctxIdentity(env, c);
    env.decisionSeq = rec.seq;
    env.nChanged = rec.nChanged;
    env.worn = {};
    local S = M._services();
    local lk = (S ~= nil) and S.lookupByName or nil;
    for slot, name in pairs(rec.plan or {}) do
        local w = { name = name };
        if name == 'remove' then
            w.removed = true;
        elseif lk ~= nil then
            local ok, r = pcall(lk, name);
            if ok and type(r) == 'table' then
                w.id = r.Id; w.level = r.Level; w.type = r.Type;
            end
        end
        env.worn[slot] = w;
    end
    local stats, bonuses = foldTotals(rec.plan, c.jobLevel);
    if stats ~= nil then
        env.totals = stats;
        env.setBonus = bonuses;
    end
    return env;
end
M._buildWorn = buildWorn;   -- headless test seam (IN*)

-- The ANCHOR: an action stub that produced no decision (design 5, refined
-- 2026-07-28). Metadata + join key + ctx, no items -- its whole job is the
-- consumer's join ("seen, decided nothing, here was your TP").
local function buildAnchor(stub)
    local env = baseEnv('dispatch');
    env.at = stub.at or env.at;
    env.dropped = 0;
    env.source = 'plan';
    env.snapshot = false;
    env.event = stub.event;
    ctxIdentity(env, stub.ctx or {});
    return env;
end

-- At rest -- no decision yet this session -- a snapshot falls back to the
-- client's worn memory (source='worn': more accurate at rest, no provenance).
local function wornMemoryEnvelope()
    local S = M._services();
    if S == nil or S.EQUIP_SLOTS == nil or type(S.getEquippedId) ~= 'function' then return nil; end
    local plan = {};
    pcall(function()
        for _, sl in ipairs(S.EQUIP_SLOTS) do
            local id = S.getEquippedId(sl.equip);
            if id ~= nil then
                local rec = (type(S.lookupById) == 'function') and S.lookupById(id) or nil;
                local name = (type(rec) == 'table' and rec.Name)
                    or ((type(S.displayName) == 'function') and S.displayName(id)) or nil;
                if name ~= nil then plan[sl.label] = tostring(name); end
            end
        end
    end);
    if next(plan) == nil then return nil; end
    local c = {};
    pcall(function()
        local p = gData.GetPlayer();
        if p ~= nil then
            c.job, c.sub = p.MainJob, p.SubJob;
            c.jobLevel, c.subLevel = p.MainJobSync, p.SubJobSync;
        end
    end);
    return buildWorn({ seq = nil, at = os.time(), plan = plan, ctx = c, nChanged = 0 },
                     true, 'worn', 0);
end

-- ---------------------------------------------------------------------------
-- confirm: intent vs fact (design: delta-only -- a plan that landed whole
-- emits nothing; only the NEWEST worn is ever pending, older checks are moot).
-- ---------------------------------------------------------------------------
local function scheduleConfirm(rec, forSeq)
    M._pending = { plan = rec.plan, decisionSeq = rec.seq, forSeq = forSeq,
                   dueClk = os.clock() + (tonumber(M.CONFIRM_S) or 0.8) };
end

local function checkConfirm()
    local p = M._pending;
    if p == nil or os.clock() < p.dueClk then return; end
    M._pending = nil;
    local S = M._services();
    if S == nil or S.EQUIP_SLOTS == nil or type(S.getEquippedId) ~= 'function' then return; end
    local actual = {};
    local okRead = pcall(function()
        for _, sl in ipairs(S.EQUIP_SLOTS) do
            local id = S.getEquippedId(sl.equip);
            if id ~= nil then
                local rec = (type(S.lookupById) == 'function') and S.lookupById(id) or nil;
                local name = (type(rec) == 'table' and rec.Name)
                    or ((type(S.displayName) == 'function') and S.displayName(id)) or nil;
                if name ~= nil then actual[string.lower(sl.label)] = tostring(name); end
            end
        end
    end);
    if not okRead then return; end
    local delta = nil;
    for slot, planned in pairs(p.plan or {}) do
        local got = actual[string.lower(tostring(slot))];
        if planned == 'remove' then
            if got ~= nil then
                delta = delta or {};
                delta[slot] = { planned = 'remove', actual = got };
            end
        elseif got == nil or string.lower(got) ~= string.lower(tostring(planned)) then
            delta = delta or {};
            delta[slot] = { planned = planned, actual = got };
        end
    end
    if delta == nil then return; end            -- landed whole: silence is the report
    local env = baseEnv('confirm');
    env.seq = nextSeq();
    env.forSeq = p.forSeq;
    env.decisionSeq = p.decisionSeq;
    env.delta = delta;
    emit('dlac_confirm', env);
end

-- ---------------------------------------------------------------------------
-- invalidate: cached query answers went stale. v1 watches the two revs the
-- v1 queries lean on -- the sets store (M.modesRev: installs + re-flattens)
-- and the main job. Baselined at setOn so enabling never emits a phantom.
-- ---------------------------------------------------------------------------
local function currentJob()
    local j = nil;
    pcall(function()
        local p = gData.GetPlayer();
        if p ~= nil then j = p.MainJob; end
    end);
    return j;
end

local function checkInvalidate()
    local rev = hasDispatch and tonumber(dsp.modesRev) or nil;
    local job = currentJob();
    local changed = {};
    if M._watchSetsRev ~= nil and rev ~= nil and rev ~= M._watchSetsRev then
        changed[#changed + 1] = 'sets';
    end
    if M._watchJob ~= nil and job ~= nil and job ~= M._watchJob then
        changed[#changed + 1] = 'job';
    end
    if rev ~= nil then M._watchSetsRev = rev; end
    if job ~= nil then M._watchJob = job; end
    if #changed == 0 then return; end
    local env = baseEnv('invalidate');
    env.seq = nextSeq();
    env.changed = changed;
    env.rev = { sets = rev };
    env.job = job;
    emit('dlac_invalidate', env);
end

-- ---------------------------------------------------------------------------
-- The pump: one frame = the lifetime gate, then drain both feeds FIFO, then
-- the watches. Ordering across kinds is by `seq`; the contract joins by label
-- and seq, never by arrival order.
-- ---------------------------------------------------------------------------
function M._pump()
    if not M.on then return; end
    local gone = false;
    pcall(function() gone = dsp.worldAbsentOutlasted() == true; end);
    if gone then
        M.on = false;
        M._lastRingSeq = 0;
        M._lastASeq = 0;
        M._pending = nil;
        return;
    end
    -- worn: new decision-ring records
    local ring = nil;
    pcall(function() ring = dsp.getDecisions(); end);
    if type(ring) == 'table' and #ring > 0 then
        local firstIdx = nil;
        for i = 1, #ring do
            if (ring[i].seq or 0) > M._lastRingSeq then firstIdx = i; break; end
        end
        if firstIdx ~= nil then
            local dropped = 0;
            if M._lastRingSeq > 0 and (ring[firstIdx].seq or 0) > M._lastRingSeq + 1 then
                dropped = ring[firstIdx].seq - M._lastRingSeq - 1;
            end
            for i = firstIdx, #ring do
                local env = buildWorn(ring[i], false, 'plan', (i == firstIdx) and dropped or 0);
                env.seq = nextSeq();
                emit('dlac_worn', env);
                M._lastRingSeq = ring[i].seq or M._lastRingSeq;
                scheduleConfirm(ring[i], env.seq);
            end
        end
    end
    -- dispatch anchors: new action stubs that produced no decision
    local acts = nil;
    pcall(function() acts = dsp.getActions(); end);
    if type(acts) == 'table' and #acts > 0 then
        for i = 1, #acts do
            local a = acts[i];
            if (a.aseq or 0) > M._lastASeq then
                if a.decSeq == nil then
                    local env = buildAnchor(a);
                    env.seq = nextSeq();
                    emit('dlac_dispatch', env);
                end
                M._lastASeq = a.aseq or M._lastASeq;
            end
        end
    end
    checkInvalidate();
    checkConfirm();
end

-- ---------------------------------------------------------------------------
-- The switch. Enabling emits an immediate snapshot (6.5) and baselines every
-- feed and watch to NOW -- history is the query's job, not a replay's.
-- ---------------------------------------------------------------------------
function M.setOn(v)
    v = (v == true);
    if v == M.on then return M.on; end
    M.on = v;
    if v then
        local ring, acts = nil, nil;
        pcall(function() ring = dsp.getDecisions(); end);
        pcall(function() acts = dsp.getActions(); end);
        local rec = (type(ring) == 'table') and ring[#ring] or nil;
        if rec ~= nil then
            local env = buildWorn(rec, true, 'plan', 0);
            env.seq = nextSeq();
            emit('dlac_worn', env);
            M._lastRingSeq = rec.seq or 0;
        else
            local env = wornMemoryEnvelope();
            if env ~= nil then
                env.seq = nextSeq();
                emit('dlac_worn', env);
            end
        end
        local lastA = (type(acts) == 'table' and #acts > 0) and acts[#acts].aseq or 0;
        M._lastASeq = lastA or 0;
        M._watchSetsRev = hasDispatch and tonumber(dsp.modesRev) or nil;
        M._watchJob = currentJob();
        M._pending = nil;
    else
        M._lastRingSeq = 0;
        M._lastASeq = 0;
        M._pending = nil;
        M._watchSetsRev = nil;
        M._watchJob = nil;
    end
    return M.on;
end

-- ---------------------------------------------------------------------------
-- The pull half: five queries (design section 7), caller-supplied reply
-- channel ('dlac_query' -> { reply = 'x', what = ... } answers on 'x_r').
-- Gated on the same switch: off = silent, queries included. Unknown `what`
-- answers with err, never silence. Revs: sets rides M.modesRev; a worn
-- reply's rev is its seq watermark; gear/item/stats carry rev 0 in v1.
-- ---------------------------------------------------------------------------
local function entryName(v)
    if type(v) == 'table' then return tostring(v.Name or v[1] or '?'); end
    return tostring(v);
end

local function answerWorn(q)
    local ring = nil;
    pcall(function() ring = dsp.getDecisions(); end);
    local rec = (type(ring) == 'table') and ring[#ring] or nil;
    local env = (rec ~= nil) and buildWorn(rec, true, 'plan', 0) or wornMemoryEnvelope();
    if env == nil then
        return { v = 1, what = 'worn', err = 'nothing to report yet (no decision this session, not logged in)' };
    end
    env.seq = M._seq;   -- the CURRENT watermark: a reply is not a live event
    return { v = 1, what = 'worn', rev = env.seq, data = env };
end

local function answerStats(q)
    if type(q.comp) ~= 'table' or next(q.comp) == nil then
        return { v = 1, what = 'stats', err = 'send comp = { Slot = "Item Name", ... }' };
    end
    local level = tonumber(q.level);
    if level == nil then
        pcall(function()
            local p = gData.GetPlayer();
            if p ~= nil then level = tonumber(p.MainJobSync); end
        end);
    end
    local stats, bonuses = foldTotals(q.comp, level);
    if stats == nil then
        return { v = 1, what = 'stats', err = 'no item could be resolved (names must match the catalog/owned gear)' };
    end
    return { v = 1, what = 'stats', rev = 0,
             data = { totals = stats, setBonus = bonuses, level = level } };
end

local function answerSets(q)
    local store = hasDispatch and dsp._nativeSets or nil;
    if type(store) ~= 'table' then
        return { v = 1, what = 'sets', err = 'no sets loaded yet (log in / act once)' };
    end
    local rev = tonumber(dsp.modesRev) or 0;
    local wanted = (type(q.set) == 'string') and q.set or nil;
    if wanted == nil then
        local names = {};
        for k in pairs(store) do
            if type(k) == 'string' and k ~= 'Dynamic' and string.sub(k, 1, 2) ~= '__' then
                names[#names + 1] = k;
            end
        end
        table.sort(names);
        return { v = 1, what = 'sets', rev = rev, data = { job = currentJob(), names = names } };
    end
    local st = store[wanted];
    if type(st) ~= 'table' then
        return { v = 1, what = 'sets', rev = rev, err = 'no such set: ' .. wanted };
    end
    local S = M._services();
    local lk = (S ~= nil) and S.lookupByName or nil;
    local slots, plan = {}, {};
    for slot, v in pairs(st) do
        if string.sub(tostring(slot), 1, 2) ~= '__' then
            local nm = entryName(v);
            plan[slot] = nm;
            local w = { name = nm };
            if lk ~= nil then
                local ok, r = pcall(lk, nm);
                if ok and type(r) == 'table' then w.id = r.Id; w.level = r.Level; end
            end
            slots[slot] = w;
        end
    end
    local level = nil;
    pcall(function()
        local p = gData.GetPlayer();
        if p ~= nil then level = tonumber(p.MainJobSync); end
    end);
    local stats, bonuses = foldTotals(plan, level);
    return { v = 1, what = 'sets', rev = rev,
             data = { job = currentJob(), set = wanted, slots = slots,
                      totals = stats, setBonus = bonuses } };
end

local function answerGear(q)
    local G = nil;
    pcall(function() G = require('dlac\\gear'); end);
    local map = (type(G) == 'table') and G.NameToObject or nil;
    if type(map) ~= 'table' then
        return { v = 1, what = 'gear', err = 'no gear record loaded' };
    end
    local items = {};
    for name, e in pairs(map) do
        if type(e) == 'table' then
            items[#items + 1] = { name = name, id = e.Id, level = e.Level,
                                  type = e.Type, aug = e.Augment };
        end
    end
    table.sort(items, function(a, b) return tostring(a.name) < tostring(b.name); end);
    return { v = 1, what = 'gear', rev = 0, data = { count = #items, items = items } };
end

local function answerItem(q)
    local S = M._services();
    local rec = nil;
    if q.id ~= nil and S ~= nil and type(S.lookupById) == 'function' then
        pcall(function() rec = S.lookupById(tonumber(q.id)); end);
    end
    if rec == nil and type(q.name) == 'string' and S ~= nil and type(S.lookupByName) == 'function' then
        pcall(function() rec = S.lookupByName(q.name); end);
    end
    if type(rec) ~= 'table' then
        return { v = 1, what = 'item', err = 'not found (send id = <n> or name = "<item>")' };
    end
    local data = { id = rec.Id, name = rec.Name, level = rec.Level, type = rec.Type,
                   jobs = rec.Jobs, slot = rec.Slot, stats = rec.Stats, aug = rec.Augment };
    pcall(function()
        local oc = require('dlac\\gear\\ownedcache');
        if type(oc.verdict) == 'function' then data.owned = oc.verdict(rec); end
    end);
    return { v = 1, what = 'item', rev = 0, data = data };
end

function M._onEvent(e)
    if not M.on then return; end
    local name = nil;
    pcall(function() name = e.name; end);
    if tostring(name or '') ~= 'dlac_query' then return; end
    local raw = nil;
    pcall(function() raw = e.data; end);          -- a STRING on the receive side (probed)
    if type(raw) ~= 'string' or raw == '' then return; end
    local chunk = (loadstring or load)(raw);
    if chunk == nil then return; end
    local ok, q = pcall(chunk);
    if not ok or type(q) ~= 'table' or type(q.reply) ~= 'string' or q.reply == '' then return; end
    local what = tostring(q.what or '');
    local answer;
    if what == 'worn' then answer = answerWorn(q);
    elseif what == 'stats' then answer = answerStats(q);
    elseif what == 'sets' then answer = answerSets(q);
    elseif what == 'gear' then answer = answerGear(q);
    elseif what == 'item' then answer = answerItem(q);
    else
        answer = { v = 1, what = what, err = 'unknown what (v1 answers: worn, stats, sets, gear, item)' };
    end
    emit(q.reply .. '_r', answer);
end

-- /dl stream on|off (bare = status). Routed here by dispatch's command
-- handler; acks are ONE line (the command-ack law).
function M.command(args)
    local a2 = args and args[2] and string.lower(args[2]) or nil;
    if a2 == 'on' then
        M.setOn(true);
        print('[dlac] stream ON (this session only -- dies on logout; other addons read dlac_worn / dlac_dispatch / dlac_query).');
    elseif a2 == 'off' then
        M.setOn(false);
        print('[dlac] stream off.');
    else
        print(string.format('[dlac] stream: %s -- /dl stream on|off (session switch; emits gear decisions to other addons).',
            M.on and ('ON, seq ' .. tostring(M._seq)) or 'off'));
    end
end

-- Live registrations (headless: absent ashita just skips -- tests drive
-- M._pump / M._onEvent directly).
pcall(function()
    ashita.events.register('d3d_present', 'dlac_integration_pump', function()
        pcall(M._pump);
    end);
    ashita.events.register('plugin_event', 'dlac_integration', function(e)
        pcall(M._onEvent, e);
    end);
end);

return M;
