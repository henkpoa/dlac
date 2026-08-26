--[[
    vanaheim/gearvault/vaultclient.lua -- THE one client for Vanaheim's Gear
    Vault wire (slice 1 of docs/design/gear-vault-integration.md: the wire +
    the mirror, READ-ONLY -- HELLO and LIST only; no write op exists in this
    file yet by design).

    The protocol is the 0x1E0 channel's vault partition (ops 0x40-0x7F),
    whose byte layouts are recorded in the design doc and owned server-side
    by the vanaheim repo's modules/custom/lua/gear_vault.lua. The eboxclient
    discipline applies wholesale: ONE module speaks the wire, plain
    string.byte byte-math so every path runs headless, one request in
    flight, a global min-gap, and consumers read the shared mirror -- never
    a second speaker.

    THE MIRROR IS REFRESHED ON REASON, NEVER ON A CLOCK (the E-Box
    "box is a number we already know" law, adapted): the vault can only
    change through our own ops (none in slice 1), the job-change swap, a
    `!vault` chat command, or the website while we play. So:

      * full sync (HELLO + LIST pages) at first readiness, after a MAIN JOB
        change settles (the swap stream is ~3-4 s), after an outgoing
        `!vault` mutation settles, and on manual refresh;
      * a cheap HELLO probe on zone-in settle -- its VaultCount doubles as
        the dirty check: disagree with the mirror and the probe escalates
        to a full sync, agree and the mirror is re-stamped fresh;
      * ordinary looting refreshes NOTHING (a loot cannot change the vault).

    Retries re-send the SAME Seq: the server's replay ring answers a
    retried mutating frame with the SAME reply, so a lost frame can never
    double an op -- and for the read ops here a re-ask is harmless anyway.
    A BAD_OP answer means this server has no vault (the pre-vault
    dispatcher answered exactly that for the whole partition): the client
    goes DORMANT for the session, silently -- absence of a server feature
    is not an error. PROTO_UNSUPPORTED goes dormant too, with one loud
    line, because that one is actionable (update dlac).

    Everything time-flavoured runs on injectable seams (M._clock, M._send)
    so the headless suite drives the whole state machine with no Ashita.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- Wire constants (the design doc's table; the server's gv.* twins)
-- ---------------------------------------------------------------------------
M.PKT   = 0x1E0;
M.PROTO = 1;

M.op =
{
    HELLO       = 0x40,
    LIST        = 0x41,
    DEPOSIT     = 0x42,   -- slice 4 (not sent from this slice)
    WITHDRAW    = 0x43,   -- slice 2 (not sent from this slice)
    LAYOUT_LIST = 0x44,   -- slice 2
    LAYOUT_SET  = 0x45,   -- slice 3
};

M.status =
{
    OK                = 0,
    BAD_OP            = 1,
    MALFORMED         = 2,
    BUSY              = 3,
    TOO_FAR           = 4,
    UNAVAILABLE       = 5,
    PROTO_UNSUPPORTED = 6,
};

M.FLAG_MORE = 1;

-- Pacing. SEND_TIMEOUT must clear the server's frame turnaround with room;
-- retries stay under the 5 s replay window so a retried frame is answered
-- from the ring, never re-executed.
M.SEND_TIMEOUT   = 1.5;   -- seconds before re-sending the SAME Seq
M.MAX_RETRIES    = 3;     -- then give up: stale mirror + a long backoff
M.MIN_GAP        = 0.35;  -- between any two sends (party-line courtesy)
M.GIVEUP_BACKOFF = 30;    -- seconds before a failed sync may try again
M.SETTLE_JOB     = 6.0;   -- job-change swap stream settle (~3-4 s + slack)
M.SETTLE_ZONE    = 5.0;   -- zone-in flood settle before the probe
M.SETTLE_CHAT    = 3.0;   -- after an outgoing !vault mutation

-- ---------------------------------------------------------------------------
-- Injectable seams (production wiring in init.lua; tests replace)
-- ---------------------------------------------------------------------------
M._clock  = os.clock;
M._send   = nil;    -- function(byteTable) -> boolean; nil = frames go nowhere
M._onFresh = nil;   -- called after every mirror commit (glue: ownedcache reset)
M._say     = nil;   -- one-line chat sink (glue: chatfmt); nil = print

local function say(msg)
    if type(M._say) == 'function' then pcall(M._say, msg); return; end
    print('[dlac] ' .. tostring(msg));
end

-- ---------------------------------------------------------------------------
-- Byte codec -- plain string byte-math, 1-indexed Lua strings, 0-indexed
-- protocol offsets (the eboxclient idiom).
-- ---------------------------------------------------------------------------
local function u8(data, off)  return string.byte(data, off + 1) or 0; end
local function u16(data, off) return u8(data, off) + u8(data, off + 1) * 256; end
local function u32(data, off)
    return u16(data, off) + u16(data, off + 2) * 65536;
end

local function wu16(v)
    v = math.max(0, math.min(math.floor(v or 0), 0xFFFF));
    return string.char(v % 256, math.floor(v / 256) % 256);
end

local function wu32(v)
    v = math.max(0, math.min(math.floor(v or 0), 0xFFFFFFFF));
    return string.char(
        v % 256,
        math.floor(v / 256) % 256,
        math.floor(v / 65536) % 256,
        math.floor(v / 16777216) % 256);
end

M._u8, M._u16, M._u32, M._wu16, M._wu32 = u8, u16, u32, wu16, wu32;

-- A C2S frame as the byte TABLE AddOutgoingPacket takes: 4 header bytes the
-- packet manager owns (left 0), Op @4, Seq @5, two must-be-zero bytes,
-- payload from @8 -- padded to a 4-byte boundary (FFXI frames are
-- 2-byte-unit sized; 4 keeps us aligned like every sibling packet).
function M.buildFrame(op, seq, payload)
    payload = payload or '';
    local p = {};
    for i = 1, 8 do p[i] = 0; end
    p[5] = op % 256;
    p[6] = seq % 256;
    for i = 1, #payload do p[8 + i] = string.byte(payload, i); end
    while (#p % 4) ~= 0 do p[#p + 1] = 0; end
    return p;
end

-- One inbound 0x1E0, header included: -> { op, seq, status, flags, payload }
-- or nil when it cannot be the envelope.
function M.parseFrame(data)
    if type(data) ~= 'string' or #data < 8 then return nil; end
    return {
        op      = u8(data, 4),
        seq     = u8(data, 5),
        status  = u8(data, 6),
        flags   = u8(data, 7),
        payload = data:sub(9),
    };
end

function M.helloPayload()
    return wu16(M.PROTO) .. wu16(0);
end

function M.listPayload(afterRowId)
    return wu32(afterRowId or 0);
end

-- HELLO S2C: { proto, vaultCount, maxList, maxDeposit, maxWithdraw } or nil.
function M.parseHello(payload)
    if type(payload) ~= 'string' or #payload < 12 then return nil; end
    return {
        proto       = u16(payload, 0),
        vaultCount  = u32(payload, 4),
        maxList     = u8(payload, 8),
        maxDeposit  = u8(payload, 9),
        maxWithdraw = u8(payload, 10),
    };
end

-- LIST S2C chunk: { entries = { { rowId, itemId, qty, identity(24 raw
-- bytes) } ... } } or nil on a malformed chunk. Truncated entry lists are
-- refused whole -- a half-read row must never enter the mirror.
function M.parseListChunk(payload)
    if type(payload) ~= 'string' or #payload < 4 then return nil; end
    local count = u16(payload, 0);
    if #payload < 4 + count * 32 then return nil; end
    local entries = {};
    for i = 0, count - 1 do
        local off = 4 + i * 32;
        entries[#entries + 1] = {
            rowId    = u32(payload, off),
            itemId   = u16(payload, off + 4),
            qty      = u16(payload, off + 6),
            identity = payload:sub(off + 9, off + 32),
        };
    end
    return { entries = entries };
end

-- ---------------------------------------------------------------------------
-- The mirror -- what consumers read (through the serverpack service, never
-- by requiring this file from core).
-- ---------------------------------------------------------------------------
M.mirror =
{
    fresh      = false,
    rows       = {},     -- { { rowId, itemId, qty, identity } ... } FIFO
    counts     = {},     -- itemId -> total quantity
    vaultCount = nil,    -- HELLO's figure (nil until first answer)
    stamp      = nil,    -- _clock() of the last commit
};

M.limits = nil;          -- HELLO's { maxList, maxDeposit, maxWithdraw }

-- ---------------------------------------------------------------------------
-- Client state
-- ---------------------------------------------------------------------------
local st =
{
    dormant  = false,    -- server has no vault / proto refused: sleep for the session
    pending  = nil,      -- { kind='probe'|'sync-hello'|'sync-list', op, seq,
                         --   frame, sentAt, retries, cursor }
    seq      = 0,        -- last Seq used (wraps at 255)
    lastSend = 0,
    staleAt  = nil,      -- _clock() time a sync may begin (nil = fresh, no work)
    giveups  = 0,
    rowsAcc  = nil,      -- accumulating LIST pages
    lastJob  = nil,      -- main-job edge detector (pump-fed)
    saidProto = false,
};

local function nextSeq()
    st.seq = (st.seq + 1) % 256;
    return st.seq;
end

local function sendPending(now)
    st.pending.sentAt = now;
    st.lastSend = now;
    if type(M._send) == 'function' then pcall(M._send, st.pending.frame); end
end

local function beginOp(kind, op, payload, now, cursor)
    local seq = nextSeq();
    st.pending = {
        kind = kind, op = op, seq = seq, cursor = cursor,
        frame = M.buildFrame(op, seq, payload),
        retries = 0,
    };
    sendPending(now);
end

local function commitMirror(now)
    local rows = st.rowsAcc or {};
    local counts = {};
    for _, r in ipairs(rows) do
        counts[r.itemId] = (counts[r.itemId] or 0) + math.max(1, r.qty);
    end
    M.mirror.rows   = rows;
    M.mirror.counts = counts;
    M.mirror.fresh  = true;
    M.mirror.stamp  = now;
    st.rowsAcc = nil;
    st.staleAt = nil;
    st.giveups = 0;
    if type(M._onFresh) == 'function' then pcall(M._onFresh); end
end

local function goDormant(loud)
    st.dormant = true;
    st.pending = nil;
    st.rowsAcc = nil;
    if loud and not st.saidProto then
        st.saidProto = true;
        say('gear vault: this dlac speaks protocol ' .. tostring(M.PROTO)
            .. ' but the server wants newer -- update dlac to use the vault.');
    end
end

-- Mark the mirror stale; a sync may start once `settle` seconds have
-- passed (floods settle first). Keeps the old rows for display fallback --
-- fresh=false is the honesty bit.
function M.markStale(settle, why)
    if st.dormant then return; end
    local at = M._clock() + (settle or 0);
    if st.staleAt == nil or at > st.staleAt then st.staleAt = at; end
    M.mirror.fresh = false;
end

-- Manual refresh (the service verb; also `/dl vault sync`).
function M.refresh()
    st.giveups = 0;
    M.markStale(0, 'manual');
end

-- The main-job edge: a change means the server is (about to be) streaming
-- the swap -- resync after it settles. Fed by pump so headless tests drive
-- it directly.
function M.noteJob(job)
    if type(job) ~= 'number' or job == 0 then return; end
    if st.lastJob ~= nil and job ~= st.lastJob then
        M.markStale(M.SETTLE_JOB, 'job change');
    end
    st.lastJob = job;
end

function M.noteZoneIn()
    -- Cheap probe once the zone-in flood settles: HELLO's VaultCount is the
    -- dirty check (website / offline edits surface here).
    if st.dormant then return; end
    M.markStale(M.SETTLE_ZONE, 'zone-in');
    st.probeOnly = true;
end

function M.noteVaultChat()
    -- An outgoing `!vault ...` may mutate the store; resync after it lands.
    M.markStale(M.SETTLE_CHAT, 'chat');
    st.probeOnly = false;
end

-- ---------------------------------------------------------------------------
-- The frame pump. `ready` = a real character is known (job id ~= 0). All
-- pacing lives here; callers just call it every frame.
-- ---------------------------------------------------------------------------
function M.pump(ready)
    if st.dormant or not ready then return; end
    local now = M._clock();

    -- First readiness of the session (addon load mid-session included, where
    -- no zone-in packet will ever arrive): arm the login sync.
    if M.mirror.stamp == nil and st.staleAt == nil and st.pending == nil then
        st.staleAt = now + 2.0;
    end

    if st.pending ~= nil then
        if now - st.pending.sentAt >= M.SEND_TIMEOUT then
            if st.pending.retries >= M.MAX_RETRIES then
                -- Lost cause for now: stale mirror, long backoff, ONE quiet
                -- state (no chat spam -- /dl vault says it when asked).
                st.pending = nil;
                st.rowsAcc = nil;
                st.giveups = st.giveups + 1;
                st.staleAt = now + M.GIVEUP_BACKOFF;
                M.mirror.fresh = false;
            else
                st.pending.retries = st.pending.retries + 1;
                sendPending(now);   -- SAME Seq: the replay ring makes this safe
            end
        end
        return;
    end

    if st.staleAt == nil or now < st.staleAt then return; end
    if now - st.lastSend < M.MIN_GAP then return; end

    -- A sync (or a probe) always starts at HELLO: proto check + the count.
    beginOp(st.probeOnly and 'probe' or 'sync-hello', M.op.HELLO, M.helloPayload(), now);
end

-- One parsed inbound frame. Returns true when it was OURS (glue blocks it).
function M.onFrame(f)
    if f == nil or type(f.op) ~= 'number' then return false; end
    if f.op < M.op.HELLO or f.op > 0x7F then return false; end
    local p = st.pending;
    if p == nil or f.op ~= p.op or f.seq ~= p.seq then
        return true;   -- ours by partition, but not the answer we await (late dupe): eat it
    end

    local now = M._clock();

    if f.status == M.status.BAD_OP then
        goDormant(false);            -- no vault on this server: sleep silently
        return true;
    end
    if f.status == M.status.PROTO_UNSUPPORTED then
        goDormant(true);
        return true;
    end
    if f.status ~= M.status.OK then
        -- BUSY / UNAVAILABLE / MALFORMED: not a dead server, just not now.
        st.pending = nil;
        st.rowsAcc = nil;
        st.staleAt = now + M.GIVEUP_BACKOFF;
        M.mirror.fresh = false;
        return true;
    end

    if p.op == M.op.HELLO then
        local h = M.parseHello(f.payload);
        st.pending = nil;
        if h == nil then
            st.staleAt = now + M.GIVEUP_BACKOFF;
            return true;
        end
        M.limits = { maxList = h.maxList, maxDeposit = h.maxDeposit, maxWithdraw = h.maxWithdraw };
        M.mirror.vaultCount = h.vaultCount;
        local rowsHeld = #M.mirror.rows;
        if p.kind == 'probe' and M.mirror.stamp ~= nil and h.vaultCount == rowsHeld then
            -- The count agrees with what we hold: the probe re-stamps fresh
            -- and the LIST pages stay unspent.
            M.mirror.fresh = true;
            M.mirror.stamp = now;
            st.staleAt = nil;
            st.probeOnly = false;
            return true;
        end
        st.probeOnly = false;
        st.rowsAcc = {};
        beginOp('sync-list', M.op.LIST, M.listPayload(0), now, 0);
        return true;
    end

    if p.op == M.op.LIST then
        local chunk = M.parseListChunk(f.payload);
        st.pending = nil;
        if chunk == nil then
            st.rowsAcc = nil;
            st.staleAt = now + M.GIVEUP_BACKOFF;
            return true;
        end
        local last = p.cursor;
        for _, e in ipairs(chunk.entries) do
            st.rowsAcc[#st.rowsAcc + 1] = e;
            if e.rowId > last then last = e.rowId; end
        end
        if f.flags % 2 == M.FLAG_MORE then
            beginOp('sync-list', M.op.LIST, M.listPayload(last), now, last);
        else
            M.mirror.vaultCount = #st.rowsAcc;   -- LIST is now the fresher truth
            commitMirror(now);
        end
        return true;
    end

    return true;
end

-- ---------------------------------------------------------------------------
-- Readouts (the service surface + /dl vault)
-- ---------------------------------------------------------------------------
function M.state()
    if st.dormant then return 'dormant'; end
    if st.pending ~= nil then return 'syncing'; end
    if M.mirror.fresh then return 'fresh'; end
    return 'stale';
end

function M.statusLine()
    local s = M.state();
    if s == 'dormant' then
        return 'gear vault: not available on this server (or the addon was refused).';
    end
    local n = 0;
    for _, r in ipairs(M.mirror.rows) do n = n + math.max(1, r.qty); end
    return string.format('gear vault: %s -- %d instance%s mirrored (%d row%s)%s.',
        s, n, (n == 1) and '' or 's', #M.mirror.rows, (#M.mirror.rows == 1) and '' or 's',
        (st.giveups > 0) and (' -- ' .. st.giveups .. ' failed sync(s), retrying') or '');
end

-- test seam
function M._reset()
    M.mirror = { fresh = false, rows = {}, counts = {}, vaultCount = nil, stamp = nil };
    M.limits = nil;
    st = { dormant = false, pending = nil, seq = 0, lastSend = 0, staleAt = nil,
           giveups = 0, rowsAcc = nil, lastJob = nil, saidProto = false };
end

function M._st() return st; end

return M;
