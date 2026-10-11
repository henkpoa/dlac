--[[
    ascensionxi/dncstatus/status -- the Dancer status channel's client state,
    pure: every Ashita touch is an injected seam, so the suite drives it with
    a fake clock and fake frames (tests/ascensionxi_dncstatus.lua).

        status.want()        a surface is showing the status (call every frame)
        status.pump()        once a frame: subscribes when it should
        status.onFrame(f)    a decoded frame of slot 1 (wire.incoming)
        status.view()        what a surface draws, or nil plus why

    The server owns what only it knows: Perpetual Step's remembered levels,
    the Dazes on the battle target, and the prices and caps. The client owns
    what it can see: its job, level and TP, the Perpetual Step buff's timer,
    the Unbroken Rhythm stack icons and their timer, Trance. The view joins
    the two; the surface decides nothing.

    Requests: ONE subscribe per zone, only while the main job is Dancer AND a
    surface wants the status (want() within DEMAND seconds), so a Dancer who
    never opens it costs the server nothing. The server forgets the
    subscription at every zone-out. Silence backs off 5, 15, then 60
    seconds; BAD_OP, UNAVAILABLE or silence after that ends asking for the
    session. Nothing is drawn until the server has sent a state.
]]--

local wire = require('dlac\\servers\\ascensionxi\\modules\\dncstatus\\wire');

local M = { SETTLE = 3, REPLY_WAIT = 5, BUSY_WAIT = 2, BACKOFF = { 5, 15, 60 }, DEMAND = 2 };

-- Client status icons (AscensionXI's DATs): Perpetual Step shows Ternary
-- Flourish's record 472; Unbroken Rhythm swaps three numbered records as its
-- stacks change (server dnc_unbroken_rhythm.lua, ur.tuning.icons).
M.BUFF = { PERPETUAL_STEP = 472, TRANCE = 376 };
M.RHYTHM_ICON = { [624] = 1, [634] = 2, [635] = 3 };
M.MAX_STACKS = 3;
M.LEVEL = 30;   -- Perpetual Step and Unbroken Rhythm: main Dancer 30

-- Seams (init.lua wires them; the suite replaces them).
M._clock      = os.clock;
M._send       = function() return false; end   -- (packet) -> true when it went out
M._received   = function() return true; end    -- transport.received(op, seq)
M._abandon    = function() end                 -- transport.abandon(op, seq)
M._notePush   = function() end                 -- transport.notePush(op, why)
M._direct     = function() end                 -- straight to the packet manager (unload)
-- { job, level, tp, buffs = { [id] = true }, timers = { [id] = seconds } } or nil
M._player     = function() return nil; end
M._entityName = function() return nil; end     -- (entity index) -> name or nil

local sub, due, pendingSeq, pendingAt, misses, dormant, wantedAt;
local seq = 0;
local state, stateAt;     -- the last server STATE and when it landed

function M.reset()
    sub, due, pendingSeq, pendingAt, misses, dormant = nil, M._clock(), nil, nil, 0, false;
    wantedAt, state, stateAt = nil, nil, nil;
end
M.reset();

local function isDnc(p) return type(p) == 'table' and p.job == wire.JOB_DNC; end

-- A surface is showing the status: keep (or start) the subscription.
function M.want() wantedAt = M._clock(); end

local function wanted(now)
    return wantedAt ~= nil and now - wantedAt <= M.DEMAND;
end

-- A zone-in (0x00A): subscribe again once the zone settles, if still wanted.
-- The last state is the old zone's battle target: drop it.
function M.zoneIn()
    if sub == 'pending' and pendingSeq ~= nil then pcall(M._abandon, wire.op.SUBSCRIBE, pendingSeq); end
    if not dormant then sub = nil; end
    pendingSeq, pendingAt, misses = nil, nil, 0;
    state, stateAt = nil, nil;
    due = M._clock() + M.SETTLE;
end

-- A zone-out (0x00B): the server drops the subscription; ask nothing until
-- the next zone-in.
function M.zoneOut()
    if sub == 'pending' and pendingSeq ~= nil then pcall(M._abandon, wire.op.SUBSCRIBE, pendingSeq); end
    if not dormant then sub = nil; end
    pendingSeq, pendingAt, due = nil, nil, nil;
end

local function apply(s)
    state, stateAt = s, M._clock();
end

-- Once a frame.
function M.pump()
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
    if not wanted(now) then return; end
    if not isDnc(M._player()) then return; end
    seq = (seq % 255) + 1;
    local ok, went = pcall(M._send, wire.subscribe(seq, true));
    if ok and went == true then
        sub, pendingSeq, pendingAt = 'pending', seq, now;
    end
end

-- A decoded frame of the partition. Only slot 1's ops are ours; the White
-- Mage gauge reads slot 0 from the same partition.
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
        pcall(M._notePush, f.op, 'dnc status');
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

-- What a surface draws, or nil and why: 'job' (not a main Dancer),
-- 'unsupported' (the server has no Dancer slot) or 'waiting' (no state yet).
--
-- view = {
--   level, tp, trance, stacks,
--   cap,        -- the most levels Perpetual Step applies now (nil under Trance: all)
--   learnt,     -- level 30 or more: Perpetual Step and Unbroken Rhythm exist
--   memory  = { steps = { { name, level, applies } }, remaining } or nil,
--   rhythm  = { stacks, max, remaining, cost, refresh, short },
--   target  = { index, name, steps = { { name, level, remaining } } } or nil,
-- }
function M.view()
    local p = M._player();
    if not isDnc(p) then return nil, 'job'; end
    if dormant then return nil, 'unsupported'; end
    if state == nil then return nil, 'waiting'; end
    local now = M._clock();
    local buffs = type(p.buffs) == 'table' and p.buffs or {};
    local timers = type(p.timers) == 'table' and p.timers or {};
    local level = tonumber(p.level) or 0;

    local stacks, rhythmLeft = 0, nil;
    for icon, n in pairs(M.RHYTHM_ICON) do
        if buffs[icon] and n > stacks then stacks, rhythmLeft = n, timers[icon]; end
    end
    local trance = buffs[M.BUFF.TRANCE] == true;
    local cap = nil;
    if not trance then cap = state.base + state.perStack * stacks; end

    local v = { level = level, tp = tonumber(p.tp), trance = trance, stacks = stacks,
                cap = cap, learnt = level >= M.LEVEL, target = nil, memory = nil };

    -- The memory: its levels are the server's. Presence follows the server
    -- too (the power is 0 without the buff), so a renumbered client icon
    -- costs only the timer, never the steps.
    if state.memory > 0 then
        local steps = {};
        for i, name in ipairs(wire.STEPS) do
            local lv = state.memoryLevels[i] or 0;
            if lv > 0 then
                steps[#steps + 1] = { name = name, level = lv, applies = cap and math.min(lv, cap) or lv };
            end
        end
        v.memory = { steps = steps, remaining = timers[M.BUFF.PERPETUAL_STEP] };
    end

    local cost = state.prices[math.min(stacks + 1, M.MAX_STACKS)];
    if cost == 0 then cost = nil; end
    v.rhythm = { stacks = stacks, max = M.MAX_STACKS, remaining = rhythmLeft, cost = cost,
                 refresh = stacks >= M.MAX_STACKS,
                 short = (cost ~= nil and v.tp ~= nil and v.tp < cost) };

    -- The Dazes: counted down here from the frame's seconds; one that runs
    -- out leaves the list before the server's push confirms it.
    if state.target ~= 0 then
        local elapsed = math.max(0, now - (stateAt or now));
        local steps = {};
        for i, name in ipairs(wire.STEPS) do
            local lv = state.levels[i];
            local left = state.seconds[i] - elapsed;
            if lv > 0 and left > 0 then
                steps[#steps + 1] = { name = name, level = lv, remaining = math.ceil(left) };
            end
        end
        local okName, name = pcall(M._entityName, state.target);
        v.target = { index = state.target, name = okName and name or nil, steps = steps };
    end
    return v;
end

-- For /dl dnc and the suite.
function M.debugState()
    return { sub = sub, dormant = dormant, misses = misses, pendingSeq = pendingSeq, state = state,
             wanted = wanted(M._clock()) };
end

return M;
