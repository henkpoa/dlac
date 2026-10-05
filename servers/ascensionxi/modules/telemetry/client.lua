--[[
    ascensionxi/telemetry/client -- the combat telemetry wire client (server
    research section 4; ops 0xC0-0xCF). It keeps one session and one battle
    lane that FOLLOWs the player's server-side battle target, and hands every
    accepted SNAPSHOT to the AutoAcc model and the readout.

    Rules it keeps (the T-rules of docs/design/ascensionxi-combat-telemetry-autoacc.md):
      * requests go through the shared 0x1E0 transport, one at a time; only a
        matched reply calls transport.received;
      * pushes (SNAPSHOT, seq 0) never touch the transport: they are checked
        and land in the latest-frame slot (T2);
      * an unanswered request is re-sent with the same seq and Nonce every
        RETRY seconds, the transport slot freed in between (T3); WATCH then
        escalates to RESYNC, RESYNC to HELLO;
      * the whole partition is blocked before decoding (T7, in init.lua);
      * nonces are seeded per addon instance (T8); telemetry refuses to run on
        the one-second os.time fallback clock (T6).

    A push is accepted only when, in order: it decodes, Proto is agreed,
    Session is current, the lane is the battle lane, WatchGen is the latest
    intention, Rev is newer, and a LIVE frame names the client's own battle
    target (research 4.5).

    The session follows demand: no HELLO goes until AutoAcc asks for a
    decision (want()), and IDLE_AFTER seconds without a question end it with
    STOP, so a player without AutoAcc pieces costs the server nothing.
]]--

local wire = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\wire');

local M = {
    SETTLE   = 3,      -- seconds after zone-in before the HELLO
    RETRY    = 1.5,    -- an unanswered request goes again this often
    TRIES    = 3,      -- sends of one request before it escalates
    BUSY_WAIT = 1.2,   -- the server's per-second request budgets
    BACKOFF  = 30,     -- after UNAVAILABLE (route without the module)
    CONTEXTS = 0x000F, -- main, off hand, kick, ranged
    IDLE_AFTER = 300,  -- seconds without an AutoAcc question before the session ends
};

M._clock    = os.clock; -- replaced by the transport's wall clock
M._send     = nil;      -- (packet) -> false when the shared channel is busy
M._received = nil;      -- (op, seq): a matched reply
M._abandon  = nil;      -- (op, seq): give the shared slot back
M._direct   = nil;      -- (packet): bypasses the gate (the unload STOP)
M._charId   = nil;      -- () -> the character's server id, or nil
M._battleTarget = nil;  -- () -> the server id of the player's battle target, or nil
M._onFrame  = nil;      -- (frame) after a SNAPSHOT is accepted
M._onState  = nil;      -- () after the session or lane state changed

local st;               -- every field below; reset() builds it
local seqCounter, nonceCounter;
local wantedAt = nil;   -- the last AutoAcc question; outlives reset() and zoning

local function now() return M._clock(); end

-- AutoAcc asks for a decision: the session is wanted.
function M.want() wantedAt = now(); end

local function wanted(t) return wantedAt ~= nil and t - wantedAt < M.IDLE_AFTER; end

-- T8: nonces from the wall clock and this instance's own address, never
-- from math.random (dlac does not seed it, so a reload would repeat them).
local function seedCounters()
    local t = now();
    local seed = tostring(math.floor(t * 1000)) .. tostring({}) .. tostring(seedCounters);
    nonceCounter = wire.fnv1a32(seed);
    seqCounter = math.floor(t * 31) % 254;
end

local function nextNonce()
    nonceCounter = (nonceCounter * 69069 + 1) % 4294967296;
    if nonceCounter == 0 then nonceCounter = 1; end
    return nonceCounter;
end

local function nextSeq()
    seqCounter = seqCounter % 254 + 1;   -- 1..255, never 0: seq 0 is a push
    return seqCounter;
end

local function changed()
    if type(M._onState) == 'function' then pcall(M._onState); end
end

function M.reset()
    seedCounters();
    st = {
        phase     = 'off',    -- off | settling | hello | live | dormant
        due       = nil,      -- when the next HELLO may go
        why       = nil,      -- why the client is dormant or waiting
        session   = 0,
        caps      = 0,
        lease     = 45,
        renewAfter = 15,
        rulesRev  = 0,
        lastTraffic = nil,    -- the last accepted request (the lease renews on it)
        pending   = nil,      -- { op, seq, nonce, payload, sentAt, tries, kind }
        queued    = nil,      -- the next request wanted (latest intention wins)
        watchGen  = 0,        -- the battle lane's latest intention
        confirmed = 0,        -- the WatchGen the server acknowledged
        laneState = wire.laneState.IDLE,
        lastRev   = 0,
        frame     = nil,      -- the latest accepted battle-lane SNAPSHOT
        frameAt   = nil,
        stats     = { pushes = 0, accepted = 0, rejected = {}, sent = 0, retries = 0 },
    };
    changed();
end

M.reset();

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- A zone change ends the server's session with the character entity
-- (research 3.5): forget it, and HELLO again once the zone settles.
function M.zoneIn()
    if st.phase == 'dormant' and st.why ~= 'unavailable' then return; end
    local keep = st.stats;
    M.reset();
    st.stats = keep;
    st.phase, st.due = 'settling', now() + M.SETTLE;
    changed();
end

function M.zoneOut()
    if st.phase == 'dormant' then return; end
    st.phase, st.due, st.pending, st.queued, st.frame = 'off', nil, nil, nil, nil;
    st.session = 0;
    changed();
end

-- T6: one-second clock resolution would break every timer here.
function M.refuse(why)
    st.phase, st.why, st.pending, st.queued, st.frame = 'dormant', why, nil, nil, nil;
    changed();
end

local function dormant(why)
    M.refuse(why);
end

-- The STOP of an idle session left: wait for the next question.
local function idle()
    st.phase, st.why, st.due = 'settling', 'waiting for an AutoAcc piece', nil;
    st.session, st.frame, st.laneState = 0, nil, wire.laneState.IDLE;
    changed();
end

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

local function queue(kind)
    -- One queued request, the latest intention replacing an older one;
    -- STOP > WATCH > RESYNC.
    local rank = { stop = 3, hello = 2, watch = 2, republish = 1, renew = 0 };
    if st.queued == nil or (rank[kind] or 0) >= (rank[st.queued] or 0) then st.queued = kind; end
end

local function build(kind)
    local nonce = nextNonce();
    if kind == 'hello' then
        return wire.op.HELLO, wire.encodeHello({ nonce = nonce, caps = wire.CLIENT_CAPS, build = 20261005 }), nonce;
    elseif kind == 'watch' then
        return wire.op.WATCH, wire.encodeWatch({ session = st.session, nonce = nonce, lane = 0,
            flags = wire.watchFlag.FOLLOW, contextMask = M.CONTEXTS, watchGen = st.watchGen }), nonce;
    elseif kind == 'renew' or kind == 'republish' then
        return wire.op.RESYNC, wire.encodeResync({ session = st.session, nonce = nonce,
            mode = (kind == 'republish') and wire.resyncMode.REPUBLISH or wire.resyncMode.RENEW,
            laneMask = (kind == 'republish') and 0x01 or 0 }), nonce;
    elseif kind == 'stop' then
        return wire.op.STOP, wire.encodeStop({ session = st.session, nonce = nonce, laneMask = 0xFF,
            flags = wire.stopFlag.END_SESSION }), nonce;
    end
    return nil;
end

local function transmit(p)
    if type(M._send) ~= 'function' then return false; end
    local ok, sent = pcall(M._send, wire.outgoing(p.op, p.seq, p.payload));
    if not ok or sent == false then return false; end
    p.sentAt, p.tries = now(), (p.tries or 0) + 1;
    st.stats.sent = st.stats.sent + 1;
    return true;
end

local function startRequest(kind)
    local op, payload, nonce = build(kind);
    if op == nil then return false; end
    local p = { kind = kind, op = op, seq = nextSeq(), nonce = nonce, payload = payload, tries = 0 };
    if not transmit(p) then return false; end
    st.pending = p;
    return true;
end

-- Called every frame (the servermods pump).
function M.pump()
    local t = now();
    if st.phase == 'dormant' or st.phase == 'off' then return; end

    -- A request in flight goes first, whatever the phase: an idle session's
    -- STOP still gets its retries.
    local p = st.pending;
    if p ~= nil then
        if p.sentAt ~= nil and t - p.sentAt < M.RETRY then return; end
        if p.sentAt ~= nil and type(M._abandon) == 'function' then pcall(M._abandon, p.op, p.seq); end
        if p.tries >= M.TRIES then
            -- Escalate: a lost WATCH asks what landed; a lost RESYNC or HELLO starts over.
            st.pending = nil;
            if p.kind == 'watch' then queue('renew');
            elseif p.kind == 'stop' then return;
            else st.phase = 'hello'; queue('hello'); end
        else
            st.stats.retries = st.stats.retries + 1;
            if not transmit(p) then p.sentAt = nil; end   -- busy: try on a later frame
            return;
        end
    end

    if st.phase == 'settling' then
        if st.due ~= nil and t < st.due then return; end
        if type(M._charId) == 'function' and M._charId() == nil then return; end   -- not in game yet
        if not wanted(t) then st.why = 'waiting for an AutoAcc piece'; return; end
        st.phase, st.why = 'hello', nil;
        queue('hello');
    end

    if st.due ~= nil and t < st.due then return; end
    if st.phase == 'live' then
        if not wanted(t) then queue('stop'); end
        if st.queued == nil and st.confirmed ~= st.watchGen then queue('watch'); end
        if st.queued == nil and st.lastTraffic ~= nil and t - st.lastTraffic >= st.renewAfter then queue('renew'); end
    end
    if st.queued ~= nil and (st.phase == 'live' or st.queued == 'hello') then
        local kind = st.queued;
        -- An escalation or NO_SESSION never revives a session nothing wants.
        if kind == 'hello' and not wanted(t) then st.queued = nil; idle(); return; end
        if startRequest(kind) then
            st.queued = nil;
            if kind == 'stop' then idle(); end
        end
    end
end

-- AutoAcc's two questions: 'republish' asks for a frame taken in the outfit
-- worn now, 'renew' asks what landed (a lost push then comes back as a
-- republish). False when there is no live session to ask.
function M.ask(kind)
    if st.phase ~= 'live' or (kind ~= 'republish' and kind ~= 'renew') then return false; end
    queue(kind);
    return true;
end

-- The addon unloads: end the session, through no gate (the frame must
-- leave now or never), so the server stops pushing (T7).
function M.unload()
    if st.session == 0 or type(M._direct) ~= 'function' then return; end
    local op, payload = build('stop');
    pcall(M._direct, wire.outgoing(op, nextSeq(), payload));
    st.session, st.phase = 0, 'off';
end

-- ---------------------------------------------------------------------------
-- Replies
-- ---------------------------------------------------------------------------

local function decodeReply(decoder, payload)
    local r = decoder(payload) or wire.readHeader(payload);
    if r ~= nil then r.result = r.code; end
    return r;
end

local function accepted()
    st.lastTraffic = now();
end

local function onHelloReply(f)
    if f.status == wire.status.BAD_OP or f.status == wire.status.PROTO_UNSUPPORTED then
        dormant(f.status == wire.status.BAD_OP and 'no telemetry on this server' or 'protocol mismatch');
        return;
    end
    if f.status == wire.status.UNAVAILABLE then
        st.phase, st.why, st.due = 'settling', 'unavailable', now() + M.BACKOFF;
        changed();
        return;
    end
    if f.status == wire.status.BUSY then
        st.due = now() + M.BUSY_WAIT;
        queue('hello');
        return;
    end
    local h = wire.decodeHelloReply(f.payload);
    if h == nil or f.status ~= wire.status.OK or h.session == 0 or h.agreedProto ~= wire.PROTO then
        dormant('bad HELLO reply');
        return;
    end
    if type(M._charId) == 'function' then
        local id = M._charId();
        if id ~= nil and h.charId ~= id then return; end   -- another character's answer
    end
    st.session, st.caps, st.rulesRev = h.session, h.caps, h.rulesRev;
    st.lease, st.renewAfter = h.leaseSeconds, h.renewAfterSeconds;
    st.phase, st.why, st.due = 'live', nil, nil;
    st.watchGen, st.confirmed, st.lastRev, st.frame = st.watchGen + 1, 0, 0, nil;
    accepted();
    if not wire.hasBit(h.caps, wire.cap.FOLLOW) then dormant('the server cannot follow a battle target'); return; end
    queue('watch');
    changed();
end

local function onWatchReply(f)
    local r = decodeReply(wire.decodeWatchReply, f.payload);
    if f.status ~= wire.status.OK or r == nil then return; end
    if r.result == wire.result.NO_SESSION then st.phase = 'hello'; queue('hello'); return; end
    if r.result == wire.result.STALE_GEN then
        st.watchGen = math.max(st.watchGen, r.watchGen or 0) + 1;
        queue('watch');
        return;
    end
    if r.result == wire.result.OK then
        accepted();
        if r.watchGen == st.watchGen then st.confirmed = r.watchGen; st.laneState = r.laneState; end
        changed();
    end
end

local function onResyncReply(f)
    local r = decodeReply(wire.decodeResyncReply, f.payload);
    if f.status == wire.status.BUSY then st.due = now() + M.BUSY_WAIT; return; end
    if f.status ~= wire.status.OK or r == nil then return; end
    if r.result == wire.result.NO_SESSION then st.phase = 'hello'; queue('hello'); return; end
    if r.result ~= wire.result.OK then return; end
    accepted();
    if r.battleWatchGen ~= st.watchGen then
        -- The WATCH never landed (or an older one did): send the intention again.
        st.confirmed = r.battleWatchGen;
        if r.battleWatchGen > st.watchGen then st.watchGen = r.battleWatchGen + 1; end
        queue('watch');
    elseif r.battleRev > st.lastRev and r.laneMask == 0 then
        -- The FIFO puts every earlier push before this reply: a higher Rev
        -- means a push was lost or refused. Ask for a full one.
        queue('republish');
    end
end

-- ---------------------------------------------------------------------------
-- Pushes
-- ---------------------------------------------------------------------------

local function reject(why)
    st.stats.rejected[why] = (st.stats.rejected[why] or 0) + 1;
    return false;
end

local function onPush(f)
    st.stats.pushes = st.stats.pushes + 1;
    if f.status ~= wire.status.OK then return reject('status'); end
    local s = wire.decodeSnapshot(f.payload);
    if s == nil then return reject('length'); end
    if s.proto ~= wire.PROTO then return reject('proto'); end
    if st.session == 0 or s.session ~= st.session then return reject('session'); end
    if s.lane ~= 0 then return reject('lane'); end
    if s.watchGen ~= st.watchGen then return reject('watchGen'); end
    if s.rev <= st.lastRev then return reject('rev'); end
    if s.laneState == wire.laneState.LIVE and type(M._battleTarget) == 'function' then
        local target = M._battleTarget();
        if target ~= nil and target ~= s.targetId then return reject('target'); end
    end
    s.key = wire.snapshotKey(f.payload);
    st.lastRev, st.frame, st.frameAt, st.laneState = s.rev, s, now(), s.laneState;
    if st.confirmed ~= st.watchGen then st.confirmed = st.watchGen; end
    st.stats.accepted = st.stats.accepted + 1;
    if type(M._onFrame) == 'function' then pcall(M._onFrame, s); end
    changed();
    return true;
end

local replyHandlers = {
    [wire.op.HELLO] = onHelloReply,
    [wire.op.WATCH] = onWatchReply,
    [wire.op.RESYNC] = onResyncReply,
    [wire.op.STOP] = function() end,
};

-- One inbound frame of the partition (init.lua has already blocked it).
function M.onFrame(f)
    if f.op == wire.op.SNAPSHOT and f.seq == 0 then return onPush(f); end
    local p = st.pending;
    if p == nil or f.op ~= p.op or f.seq ~= p.seq then return false; end
    -- Our op and seq: the Nonce settles it (a refusal under 12 bytes has none).
    local h = wire.readHeader(f.payload);
    if h ~= nil and h.nonce ~= p.nonce then return false; end
    st.pending = nil;
    if type(M._received) == 'function' then pcall(M._received, f.op, f.seq); end
    local handler = replyHandlers[f.op];
    if handler ~= nil then handler(f); end
    return true;
end

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

-- The latest accepted battle-lane frame, and when it arrived.
function M.frame() return st.frame, st.frameAt; end

function M.state()
    return {
        phase = st.phase, why = st.why, session = st.session, laneState = st.laneState,
        watchGen = st.watchGen, confirmed = st.confirmed, lastRev = st.lastRev,
        pending = st.pending and st.pending.kind or nil, stats = st.stats,
        wanted = wanted(now()),
    };
end

-- test seams
function M._state() return st; end
function M._unwant() wantedAt = nil; end

return M;
