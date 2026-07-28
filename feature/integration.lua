--[[
    dlac/feature/integration.lua -- the Integration surface, push half + the
    worn query (docs/design/integration-surface.md; consumer contract in
    docs/reference/integration-guide.md). 2026-07-28.

    An ADDON-SIDE OBSERVER over the engine's decision ring (dispatch v152,
    M.getDecisions) -- the engine equips gear and reports on its own equipping,
    nothing else (ADR 0014); this module reads the record and never derives.
    Off by default behind a SESSION switch (/dl stream on|off + a Menu row):
    never written to disk, dies when the world stays gone longer than a zone
    can explain (the worldWatch law, read through the engine's one read-only
    seam -- never a second timer with a second number). A job change does NOT
    stop the stream: a job change is data, not a reason to stop talking.

    Transport (probed 2026-07-28, evprobe + dlacprobe): SEND must be a byte
    table (RaiseEvent refuses strings); the RECEIVER gets the bytes already
    reassembled as a STRING under `e.data` (`e.size` = length; `e` is
    userdata, so consumers read named fields, never iterate). Payload is Lua
    source ('return { ... }') -- both ends are Lua, and adding a field can
    never break a reader.

    v1 surface: the `worn` kind (one envelope per decision-ring record --
    which already IS "only push changes"), a snapshot envelope on enable
    (section 6.5), and the `worn` query (the consumer's bootstrap + re-sync).
    The switch gates EVERYTHING on the channel, queries included: off means
    dlac is silent here. Later slices: the `dispatch` anchor, invalidate,
    confirm, the remaining queries.
]]--

local M = {};

local _dok, dsp = pcall(require, 'dlac\\dispatch');
local hasDispatch = _dok and type(dsp) == 'table';

M.on = false;          -- THE session switch (never persisted)
M._lastSeq = 0;        -- newest ring seq already emitted

-- ---------------------------------------------------------------------------
-- Serialization: table -> Lua source. Deterministic (array part first, then
-- sorted keys) so tests can compare; depth-capped defensively -- the record
-- carries no cycles. Exported for tests (IN*).
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
-- Live: RaiseEvent takes the byte table (strings are refused -- probed).
M._raise = function(name, bytesTbl)
    AshitaCore:GetPluginManager():RaiseEvent(name, bytesTbl);
end

local function emit(name, tbl)
    local ok, src = pcall(function() return 'return ' .. ser(tbl); end);
    if not ok then return false; end
    local sent = pcall(function() M._raise(name, toBytes(src)); end);
    return sent;
end

-- ---------------------------------------------------------------------------
-- Envelope construction (design section 5; v1 scope = worn + ctx + totals +
-- metadata -- Henrik's "give him everything that is worn and total stats").
-- ---------------------------------------------------------------------------
local function services()
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

-- Totals through the one evaluator door (gearoracle.setStats ->
-- geareffects.comboStats), exactly the Equipped panel's fold: composition of
-- owned/catalog RECORDS by name, level from the record's ctx.
local function foldTotals(plan, level)
    local S = services();
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

-- One `worn` envelope from a decision-ring record (or a record-shaped table).
local function buildWorn(rec, snapshot, source, dropped)
    local c = rec.ctx or {};
    local nm, cid = charIdentity();
    local env = {
        v = 1, seq = rec.seq or M._lastSeq, kind = 'worn', dropped = dropped or 0,
        at = rec.at, source = source or 'plan', snapshot = snapshot == true,
        char = nm, charId = cid,
        dlac = (type(addon) == 'table') and addon.version or nil,
        engine = hasDispatch and dsp.VERSION or nil,
        event = rec.event, action = c.action,
        actionId = c.actionId, actionCategory = c.actionCategory,
        targetIndex = c.targetIndex,
        job = c.job, jobLevel = c.jobLevel, sub = c.sub, subLevel = c.subLevel,
        nChanged = rec.nChanged,
        ctx = c,
        worn = {},
    };
    local S = services();
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

-- At rest -- no decision yet this session -- the snapshot falls back to the
-- client's worn memory (source = 'worn': the MORE accurate answer at rest,
-- with no provenance to give). Through gearui's services doors; nil headless
-- or pre-login.
local function wornMemoryEnvelope()
    local S = services();
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
    return buildWorn({ seq = M._lastSeq, at = os.time(), plan = plan, ctx = c, nChanged = 0 },
                     true, 'worn', 0);
end

-- ---------------------------------------------------------------------------
-- The pump: drain the ring FIFO each present frame -- never last-value-wins
-- (two decisions in one frame both go out, in order). A seq gap against what
-- we already emitted means the ring overflowed past us; the count rides the
-- next envelope's `dropped` (the consumer's re-pull signal).
-- ---------------------------------------------------------------------------
function M._pump()
    if not M.on then return; end
    local gone = false;
    pcall(function() gone = dsp.worldAbsentOutlasted() == true; end);
    if gone then
        -- the session ended (character select outlasts a zone load): the
        -- switch dies with it, silently -- the holds' own convention
        M.on = false;
        M._lastSeq = 0;
        return;
    end
    local ring = nil;
    pcall(function() ring = dsp.getDecisions(); end);
    if type(ring) ~= 'table' or #ring == 0 then return; end
    local firstIdx = nil;
    for i = 1, #ring do
        if (ring[i].seq or 0) > M._lastSeq then firstIdx = i; break; end
    end
    if firstIdx == nil then return; end
    local dropped = 0;
    if M._lastSeq > 0 and (ring[firstIdx].seq or 0) > M._lastSeq + 1 then
        dropped = ring[firstIdx].seq - M._lastSeq - 1;
    end
    for i = firstIdx, #ring do
        emit('dlac_worn', buildWorn(ring[i], false, 'plan', (i == firstIdx) and dropped or 0));
        M._lastSeq = ring[i].seq or M._lastSeq;
    end
end

-- ---------------------------------------------------------------------------
-- The switch. On-enable emits an immediate snapshot (section 6.5): the newest
-- decision when one exists, else the worn-memory read; nothing to say emits
-- nothing (the query remains the consumer's bootstrap).
-- ---------------------------------------------------------------------------
function M.setOn(v)
    v = (v == true);
    if v == M.on then return M.on; end
    M.on = v;
    if v then
        local ring = nil;
        pcall(function() ring = dsp.getDecisions(); end);
        local rec = (type(ring) == 'table') and ring[#ring] or nil;
        if rec ~= nil then
            emit('dlac_worn', buildWorn(rec, true, 'plan', 0));
            M._lastSeq = rec.seq or 0;
        else
            local env = wornMemoryEnvelope();
            if env ~= nil then emit('dlac_worn', env); end
        end
    else
        M._lastSeq = 0;
    end
    return M.on;
end

-- ---------------------------------------------------------------------------
-- The pull half, v1: the `worn` query alone (the consumer's bootstrap and its
-- only honest re-sync after a seq gap). Caller supplies the reply channel
-- (LAC's convention): 'dlac_query' -> { reply = 'x', what = 'worn' } answers
-- on 'x_r'. Gated on the same switch: off = silent, queries included.
-- ---------------------------------------------------------------------------
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
    if what == 'worn' then
        local ring = nil;
        pcall(function() ring = dsp.getDecisions(); end);
        local rec = (type(ring) == 'table') and ring[#ring] or nil;
        local env = (rec ~= nil) and buildWorn(rec, true, 'plan', 0) or wornMemoryEnvelope();
        if env == nil then
            emit(q.reply .. '_r', { v = 1, what = 'worn', err = 'nothing to report yet (no decision this session, not logged in)' });
        else
            emit(q.reply .. '_r', { v = 1, what = 'worn', rev = env.seq, data = env });
        end
    else
        emit(q.reply .. '_r', { v = 1, what = what, err = 'unknown what (v1 answers: worn)' });
    end
end

-- /dl stream on|off (bare = status). Routed here by dispatch's command
-- handler; acks are ONE line (the command-ack law).
function M.command(args)
    local a2 = args and args[2] and string.lower(args[2]) or nil;
    if a2 == 'on' then
        M.setOn(true);
        print('[dlac] stream ON (this session only -- dies on logout; other addons read dlac_worn / dlac_query).');
    elseif a2 == 'off' then
        M.setOn(false);
        print('[dlac] stream off.');
    else
        print(string.format('[dlac] stream: %s -- /dl stream on|off (session switch; emits gear decisions to other addons).',
            M.on and ('ON, last seq ' .. tostring(M._lastSeq)) or 'off'));
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
