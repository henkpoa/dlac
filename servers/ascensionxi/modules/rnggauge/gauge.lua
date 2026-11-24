-- Server deadlines drive the display. Never infer a cooldown from item delay
-- or an outgoing /ra, which may be rejected or cancelled.
local wire = require('dlac\\servers\\ascensionxi\\modules\\rnggauge\\wire');
local M = { SETTLE = 3, REPLY_WAIT = 5, BACKOFF = { 5, 15, 60 } };
M._clock = os.clock;
M._send = function() return false; end;
M._direct = function() end;
M._received = function() end;
M._abandon = function() end;
M._notePush = function() end;
M._player = function() return nil; end;
M._shown = function() return true; end;
local seq = 0;
local sub, pending, sentAt, due, misses, dormant, state, stateAt, context, zoning, demo;

local function clear()
    if pending then M._abandon(wire.op.SUBSCRIBE, pending); end
    sub, pending, state, stateAt = nil, nil, nil, nil;
end
function M.reset()
    clear(); due, misses, dormant, context, zoning, demo = M._clock(), 0, false, nil, false, false;
end
M.reset();
local function stop()
    if sub == 'live' or pending then
        seq = seq % 255 + 1;
        M._direct(wire.subscribe(seq, false));
    end
    clear();
end
function M.zoneOut() clear(); zoning = true; end
function M.zoneIn() clear(); zoning = false; due = M._clock() + M.SETTLE; misses = 0; end
function M.unload() stop(); end
function M.isRng(p) return p and p.job == wire.JOB_RNG and (p.level or 0) >= 20 and p.alive ~= false; end
function M.pump()
    local now, p = M._clock(), M._player();
    local key = p and tostring(p.id or '') .. ':' .. tostring(p.job) .. ':' .. tostring(p.level) .. ':' .. tostring(p.alive) or '';
    if context ~= key then
        stop(); context = key; due = math.max(due or 0, now + M.SETTLE);
    end
    if zoning or demo or not M._shown() or not M.isRng(p) then
        if sub or pending then stop(); end
        return;
    end
    if dormant then return; end
    if pending then
        if now - sentAt < M.REPLY_WAIT then return; end
        clear(); misses = misses + 1;
        if not M.BACKOFF[misses] then dormant = true; return; end
        due = now + M.BACKOFF[misses];
    end
    if sub or now < (due or 0) then return; end
    seq = seq % 255 + 1;
    if M._send(wire.subscribe(seq, true)) then
        sub, pending, sentAt = 'pending', seq, now;
    end
end
function M.onFrame(f)
    if not f or not wire.ours(f.op) or zoning or demo then return; end
    if f.op == wire.op.SUBSCRIBE then
        if f.seq ~= pending then return; end
        M._received(f.op, f.seq); pending = nil;
        if f.status == wire.status.BUSY then sub, due = nil, M._clock() + 2; return; end
        if f.status ~= wire.status.OK then clear(); dormant = true; return; end
        local s = wire.state(f.payload);
        if not s then clear(); due = M._clock() + 5; return; end
        sub, misses = 'live', 0;
        state, stateAt = s, M._clock();
    elseif sub == 'live' then
        M._notePush(f.op, 'rng gauge');
        if f.status ~= wire.status.OK then return; end
        local s = wire.state(f.payload);
        if not s or (state and not wire.newer(s.rev, state.rev)) then return; end
        state, stateAt = s, M._clock();
    end
end
function M.setDemo(on)
    stop(); demo = on == true; due = M._clock();
end
function M.demoOn() return demo; end
function M.view()
    local now = M._clock();
    if not M._shown() or zoning then return nil; end
    if demo then
        local t = now % 8;
        return { phase = t < 2 and 1 or t < 6 and 2 or 0,
            progress = t < 2 and 0 or math.min(1, (t - 2) / 4),
            remaining = t >= 2 and t < 6 and 6 - t or 0,
            flash = t >= 6 and t < 6.6 and 1 - (t - 6) / 0.6 or 0, now = now };
    end
    if not M.isRng(M._player()) or sub ~= 'live' or not state or not state.enabled then return nil; end
    local age = math.max(0, now - stateAt);
    local left = math.max(0, state.remaining / 1000 - age);
    -- An aim never turns into a full bar on a guessed timer. Wait for resolution.
    local phase = state.phase == 1 and 1 or left > 0 and 2 or 0;
    local fullAt = stateAt + state.remaining / 1000;
    return { phase = phase, remaining = phase == 2 and left or 0,
        progress = phase == 1 and 0 or state.total > 0 and 1 - left * 1000 / state.total or 1,
        flash = state.phase == 2 and phase == 0 and math.max(0, 1 - (now - fullAt) / 0.6) or 0,
        now = now };
end
function M.debugState() return { sub = sub, dormant = dormant, state = state, pendingSeq = pending }; end
return M;
