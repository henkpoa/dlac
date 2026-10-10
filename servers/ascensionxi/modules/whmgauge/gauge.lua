--[[
    ascensionxi/whmgauge/gauge -- the White Mage flower gauge's client state,
    pure: every Ashita touch is an injected seam, so the suite drives it with
    a fake clock and fake frames (tests/ascensionxi_whmgauge.lua).

        gauge.pump()        once a frame: subscribes when it should
        gauge.onFrame(f)    a decoded 0xD0-0xDF frame (wire.incoming)
        gauge.view()        what the renderer draws, or nil (draw nothing)

    The server owns the flowers and the charge; the client owns what it can
    see for itself -- its job, its level, the Afflatus buffs, Divine Seal and
    its recast. The gauge shows only while the main job is WHM and one of the
    two stances is up, and it trusts the server's flowers only when the
    server's stance matches the buff the client sees, so a stance switch
    draws an empty gauge at once instead of the withered flowers.

    Requests: ONE subscribe per zone while the main job is WHM (the server
    forgets subscriptions at every zone-out, so nothing has to stop them),
    sent SETTLE seconds after the zone-in. A server without the channel
    answers BAD_OP or nothing; after BAD_OP the gauge asks no more this
    session, and silence backs off 5, 15, then 60 seconds before it stops
    asking for the session too.
]]--

local wire = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\wire');

local M = { SETTLE = 3, REPLY_WAIT = 5, BUSY_WAIT = 2, BACKOFF = { 5, 15, 60 }, BURST = 0.8 };

M.BUFF = { SOLACE = 417, MISERY = 418, DIVINE_SEAL = 78 };
M.DIVINE_SEAL_LEVEL = 15;

-- Seams (init.lua wires them; the suite replaces them).
M._clock    = os.clock;
M._send     = function() return false; end   -- (packet) -> true when it went out
M._received = function() return true; end    -- transport.received(op, seq)
M._abandon  = function() end                 -- transport.abandon(op, seq)
M._notePush = function() end                 -- transport.notePush(op, why)
M._direct   = function() end                 -- straight to the packet manager (unload)
M._player   = function() return nil; end     -- { job, level, buffs = { [id] = true } } or nil
M._seal     = function() return nil; end     -- Divine Seal recast seconds (0 = up), nil unknown
M._shown    = function() return true; end    -- the player's show/hide choice

local sub, due, pendingSeq, pendingAt, misses, dormant;
local seq = 0;
local state, stateAt;     -- the last server STATE and when it landed
local gainedAt = {};      -- flower slot -> when it lit (the burst)
local lastFlowers = { 0, 0, 0 };
local demo = nil;         -- a demo source replaces the server while set

function M.reset()
    sub, due, pendingSeq, pendingAt, misses, dormant = nil, M._clock(), nil, nil, 0, false;
    state, stateAt, gainedAt, lastFlowers = nil, nil, {}, { 0, 0, 0 };
end
M.reset();

local function isWhm(p) return type(p) == 'table' and p.job == wire.JOB_WHM; end

local function clientStance(p)
    if type(p) ~= 'table' or type(p.buffs) ~= 'table' then return wire.stance.NONE; end
    if p.buffs[M.BUFF.SOLACE] then return wire.stance.SOLACE; end
    if p.buffs[M.BUFF.MISERY] then return wire.stance.MISERY; end
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
    for i = 1, 3 do
        local was, is = lastFlowers[i] or 0, s.flowers[i] or 0;
        if is > was then gainedAt[i] = now; end   -- lit or upgraded: burst
        lastFlowers[i] = is;
    end
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
    if not isWhm(p) then return; end
    seq = (seq % 255) + 1;
    local ok, went = pcall(M._send, wire.subscribe(seq, true));
    if ok and went == true then
        sub, pendingSeq, pendingAt = 'pending', seq, now;
    end
end

-- A decoded frame of the partition.
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
            dormant, sub = true, 'dormant';   -- a server without the channel: no more asking
            return;
        end
        sub, misses = 'live', 0;
        local s = wire.state(f.payload);
        if s ~= nil then apply(s); end
        return;
    end
    if f.op == wire.op.STATE then
        pcall(M._notePush, f.op, 'whm gauge');
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

-- The demo: a source table with :at(now) -> state, client stance and seal.
function M.setDemo(src)
    demo = src;
    gainedAt, lastFlowers = {}, { 0, 0, 0 };
    if src == nil then state, stateAt = nil, nil; end
end
function M.demoOn() return demo ~= nil; end

-- What the renderer draws, or nil. Plain data: the renderer decides nothing.
function M.view()
    local now = M._clock();
    local p, stance, seal, sealActive, level;
    if demo ~= nil then
        local d = demo.at(now);
        if d == nil then return nil; end
        if d.state ~= nil and (state == nil or d.state.rev ~= state.rev) then apply(d.state); end
        stance, seal, sealActive, level = d.stance, d.seal, d.sealActive, d.level or 75;
    else
        if not M._shown() then return nil; end
        p = M._player();
        if not isWhm(p) then return nil; end
        stance = clientStance(p);
        level = tonumber(p.level) or 0;
        sealActive = type(p.buffs) == 'table' and p.buffs[M.BUFF.DIVINE_SEAL] == true;
        local ok, rem = pcall(M._seal);
        seal = ok and rem or nil;
    end
    if stance == wire.stance.NONE then return nil; end

    -- The server's flowers count only for the stance it says they belong to.
    local s = state;
    local trusted = s ~= nil and s.stance == stance;
    local v = {
        stance    = stance,
        level     = level,
        synced    = trusted,
        live      = sub == 'live' or demo ~= nil,
        tier      = trusted and s.tier or 0,
        flowers   = trusted and { s.flowers[1], s.flowers[2], s.flowers[3] } or { 0, 0, 0 },
        charge    = trusted and s.charge or 0,
        threshold = trusted and s.threshold or 0,
        boost     = trusted and s.boost or 0,
        boosting  = trusted and wire.hasFlag(s.flags, wire.flag.BOOST),
        dark      = trusted and wire.hasFlag(s.flags, wire.flag.DARK_BANISH),
        capped    = trusted and wire.hasFlag(s.flags, wire.flag.CAPPED),
        burst     = {},
        now       = now,
    };
    v.progress = (v.threshold > 0) and math.max(0, math.min(1, v.charge / v.threshold)) or 0;
    for i = 1, 3 do
        local at = gainedAt[i];
        if trusted and at ~= nil and now - at < M.BURST then v.burst[i] = (now - at) / M.BURST; end
    end
    if stance == wire.stance.SOLACE and level >= M.DIVINE_SEAL_LEVEL then
        local serverReady = trusted and wire.hasFlag(s.flags, wire.flag.SEAL_READY);
        v.seal = {
            remaining = seal,                       -- nil = the client could not read it
            ready     = (seal ~= nil and seal <= 0) or (seal == nil and serverReady),
            active    = sealActive == true,
        };
    end
    return v;
end

-- For /dl gauge status and the suite.
function M.debugState()
    return { sub = sub, dormant = dormant, misses = misses, pendingSeq = pendingSeq, state = state };
end

return M;
