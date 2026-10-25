--[[
    ascensionxi/pldgauge/gauge -- the Paladin Divine Guard gauge's client
    state, pure: every Ashita touch is an injected seam, so the suite drives
    it with a fake clock and fake frames (tests/ascensionxi_pldgauge.lua).

        gauge.pump()        once a frame: subscribes when it should
        gauge.onFrame(f)    a decoded frame of slot 2 (wire.incoming)
        gauge.view()        what the renderer draws, or nil (draw nothing)

    The server owns the points (five, or three from a server before the
    five-point gauge), the charge and the Palisade stack count; the client
    owns what it can see for itself -- its job, its level, the stance
    buffs (Divine Guard, Divine Fury) and the Palisade buff. The gauge shows
    only while the main job is PLD and a stance is up.

    Unlike the White Mage's flowers, the points carry over a stance swap
    (owner, 2026-10-24), so the server's points are drawn under either
    stance: there is no trust rule to wait out. Palisade is the exception
    the client can check for itself: its stacks count only while the client
    still sees the Palisade buff, so a Palisade that ran out, or was lost to
    death, empties the big shield at once without waiting for the server.

    It shows only once the server has sent a STATE, and never on a dormant
    channel: a server without the slot would otherwise draw an empty gauge
    for every Paladin.

    Requests: ONE subscribe per zone while the main job is PLD (the server
    forgets subscriptions at every zone-out, so nothing has to stop them),
    sent SETTLE seconds after the zone-in. A server without the slot answers
    BAD_OP or nothing; after BAD_OP the gauge asks no more this session, and
    silence backs off 5, 15, then 60 seconds before it stops asking for the
    session too.
]]--

local wire = require('dlac\\servers\\ascensionxi\\modules\\pldgauge\\wire');

local M = { SETTLE = 3, REPLY_WAIT = 5, BUSY_WAIT = 2, BACKOFF = { 5, 15, 60 }, BURST = 0.8, JOB_RECHECK = 1 };

-- Client buff (icon) ids: the server sends the stance with its own icon
-- records (ascensionxi pld_divine_guard.lua tuning.icon); Palisade keeps
-- retail's.
M.BUFF = { GUARD = 654, FURY = 655, PALISADE = 478 };

-- Seams (init.lua wires them; the suite replaces them).
M._clock    = os.clock;
M._send     = function() return false; end   -- (packet) -> true when it went out
M._received = function() return true; end    -- transport.received(op, seq)
M._abandon  = function() end                 -- transport.abandon(op, seq)
M._notePush = function() end                 -- transport.notePush(op, why)
M._direct   = function() end                 -- straight to the packet manager (unload)
M._player   = function() return nil; end     -- { job, level, buffs = { [id] = true } } or nil
M._shown    = function() return true; end    -- the player's show/hide choice

local sub, due, pendingSeq, pendingAt, misses, dormant;
local seq = 0;
local state, stateAt;     -- the last server STATE and when it landed
local gainedAt = {};      -- point slot -> when it lit (the burst)
local lastPoints = 0;
local demo = nil;         -- a demo source replaces the server while set

function M.reset()
    sub, due, pendingSeq, pendingAt, misses, dormant = nil, M._clock(), nil, nil, 0, false;
    state, stateAt, gainedAt, lastPoints = nil, nil, {}, 0;
end
M.reset();

local function isPld(p) return type(p) == 'table' and p.job == wire.JOB_PLD; end
M.isPld = isPld;

local function clientStance(p)
    if type(p) ~= 'table' or type(p.buffs) ~= 'table' then return wire.stance.NONE; end
    if p.buffs[M.BUFF.GUARD] then return wire.stance.GUARD; end
    if p.buffs[M.BUFF.FURY] then return wire.stance.FURY; end
    return wire.stance.NONE;
end

-- A zone-in (0x00A): subscribe again once the zone settles.
function M.zoneIn()
    if sub == 'pending' and pendingSeq ~= nil then pcall(M._abandon, wire.op.SUBSCRIBE, pendingSeq); end
    if not dormant then sub = nil; end
    pendingSeq, pendingAt, misses = nil, nil, 0;
    due = M._clock() + M.SETTLE;
end

-- A zone-out (0x00B): the server drops the subscription; ask nothing until
-- the next zone-in. The last state stays drawn until then.
function M.zoneOut()
    if sub == 'pending' and pendingSeq ~= nil then pcall(M._abandon, wire.op.SUBSCRIBE, pendingSeq); end
    if not dormant then sub = nil; end
    pendingSeq, pendingAt, due = nil, nil, nil;
end

local function apply(s)
    local now = M._clock();
    local was = lastPoints or 0;
    for i = was + 1, s.points do gainedAt[i] = now; end   -- each new point bursts
    lastPoints = s.points;
    state, stateAt = s, now;
end

-- Once a frame.
function M.pump()
    if demo ~= nil then return; end
    local now = M._clock();
    if sub == 'pending' then
        if now - (pendingAt or now) < M.REPLY_WAIT then return; end
        pcall(M._abandon, wire.op.SUBSCRIBE, pendingSeq);
        misses = misses + 1;
        sub, pendingSeq = nil, nil;
        local wait = M.BACKOFF[misses];
        if wait == nil then dormant, sub, due = true, 'dormant', nil; return; end   -- a silent server: stop asking
        due = now + wait;
        return;
    end
    if sub ~= nil or dormant or due == nil or now < due then return; end
    if not M._shown() then return; end
    local p = M._player();
    -- Not a PLD: look again in a second, not next frame.
    if not isPld(p) then due = now + M.JOB_RECHECK; return; end
    seq = (seq % 255) + 1;
    local ok, went = pcall(M._send, wire.subscribe(seq, true));
    if ok and went == true then
        sub, pendingSeq, pendingAt = 'pending', seq, now;
    end
end

-- A decoded frame of slot 2 (the init's tap passes nothing else, but other
-- ops are ignored here too).
function M.onFrame(f)
    if type(f) ~= 'table' then return; end
    if f.op == wire.op.SUBSCRIBE then
        if f.seq ~= pendingSeq then return; end
        pcall(M._received, f.op, f.seq);
        pendingSeq, pendingAt = nil, nil;
        if f.status == wire.status.BUSY then   -- throttled: ask again shortly
            sub, due = nil, M._clock() + M.BUSY_WAIT;
            return;
        end
        if f.status ~= wire.status.OK then
            dormant, sub = true, 'dormant';   -- a server without the slot: no more asking
            return;
        end
        sub, misses = 'live', 0;
        local s = wire.state(f.payload);
        if s ~= nil then apply(s); end
        return;
    end
    if f.op == wire.op.STATE then
        pcall(M._notePush, f.op, 'pld gauge');
        local s = wire.state(f.payload);
        if s == nil then return; end
        if state ~= nil and not wire.newer(s.rev, state.rev) then return; end
        apply(s);
    end
end

-- Unloading: tell the server to stop pushing frames nothing would block.
function M.unload()
    if sub == 'live' then
        seq = (seq % 255) + 1;
        pcall(M._direct, wire.subscribe(seq, false));
    end
    sub = nil;
end

-- The demo: a source table with :at(now) -> { state, stance, palisadeUp, level }.
-- Ending it drops the demo's state, so ask the server for its own again
-- (one subscribe; pushes come only on a change).
function M.setDemo(src)
    demo = src;
    gainedAt, lastPoints = {}, 0;
    if src == nil then
        state, stateAt = nil, nil;
        if not dormant and sub ~= 'pending' then sub, due = nil, M._clock(); end
    end
end
function M.demoOn() return demo ~= nil; end

-- What the renderer draws, or nil. Plain data: the renderer decides nothing.
function M.view()
    local now = M._clock();
    local stance, palisadeUp, level;
    if demo ~= nil then
        local d = demo.at(now);
        if d == nil then return nil; end
        if d.state ~= nil and (state == nil or d.state.rev ~= state.rev) then apply(d.state); end
        stance, palisadeUp, level = d.stance, d.palisadeUp ~= false, d.level or 75;
    else
        if not M._shown() or dormant or state == nil then return nil; end
        local p = M._player();
        if not isPld(p) then return nil; end
        stance = clientStance(p);
        level = tonumber(p.level) or 0;
        palisadeUp = type(p.buffs) == 'table' and p.buffs[M.BUFF.PALISADE] == true;
    end
    if stance == wire.stance.NONE then return nil; end

    local s = state;
    local v = {
        stance      = stance,
        level       = level,
        synced      = s ~= nil,
        agree       = s ~= nil and s.stance == stance,   -- the server has seen this stance too
        live        = sub == 'live' or demo ~= nil,
        points      = s and s.points or 0,
        maxPoints   = s and s.maxPoints or wire.POINTS_BEFORE_MAX,
        charge      = s and s.charge or 0,
        threshold   = s and s.threshold or 0,
        overflow    = s ~= nil and wire.hasFlag(s.flags, wire.flag.OVERFLOW),
        palisade    = (s ~= nil and palisadeUp) and s.palisade or 0,
        palisadeMax = s and s.palisadeMax or wire.PALISADE_MAX,
        burst       = {},
        now         = now,
    };
    v.progress = (v.threshold > 0) and math.max(0, math.min(1, v.charge / v.threshold)) or 0;
    for i = 1, v.maxPoints do
        local at = gainedAt[i];
        if at ~= nil and i <= v.points and now - at < M.BURST then v.burst[i] = (now - at) / M.BURST; end
    end
    return v;
end

-- For /dl gauge status and the suite.
function M.debugState()
    return { sub = sub, dormant = dormant, misses = misses, pendingSeq = pendingSeq, state = state };
end

return M;
