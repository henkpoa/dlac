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

-- LAYOUT_LIST C2S: { u8 Job (0 = my main); u8 Rsvd; u16 AfterOrdinal }.
function M.layoutPayload(job, afterOrdinal)
    return string.char((job or 0) % 256, 0) .. wu16(afterOrdinal or 0);
end

-- LAYOUT_LIST S2C chunk: 32-byte entries { u16 Ordinal; u16 ItemNo; u16
-- Count; u8 Hint (0 = none); u8 Pinned; u8 IdentityExtra[24] }.
function M.parseLayoutChunk(payload)
    if type(payload) ~= 'string' or #payload < 4 then return nil; end
    local count = u16(payload, 0);
    if #payload < 4 + count * 32 then return nil; end
    local entries = {};
    for i = 0, count - 1 do
        local off = 4 + i * 32;
        local hint = u8(payload, off + 6);
        entries[#entries + 1] = {
            ordinal  = u16(payload, off),
            itemId   = u16(payload, off + 2),
            count    = u16(payload, off + 4),
            hint     = (hint ~= 0) and hint or nil,
            pinned   = u8(payload, off + 7) ~= 0,
            identity = payload:sub(off + 9, off + 32),
        };
    end
    return { entries = entries };
end

-- DEPOSIT C2S: { u16 Count; u16 Rsvd; N x { u8 Container; u8 Slot; u16 Rsvd } }.
function M.depositPayload(entries)
    local parts = { wu16(#entries), wu16(0) };
    for _, e in ipairs(entries) do
        parts[#parts + 1] = string.char((e.container or 0) % 256, (e.slot or 0) % 256) .. wu16(0);
    end
    return table.concat(parts);
end

-- DEPOSIT S2C: { u16 Count; u16 Rsvd; N x { u8 Container; u8 Slot; u16 Code;
-- u32 RowId } }.
function M.parseDepositAck(payload)
    if type(payload) ~= 'string' or #payload < 4 then return nil; end
    local count = u16(payload, 0);
    if #payload < 4 + count * 8 then return nil; end
    local entries = {};
    for i = 0, count - 1 do
        local off = 4 + i * 8;
        entries[#entries + 1] = {
            container = u8(payload, off),
            slot      = u8(payload, off + 1),
            code      = u16(payload, off + 2),
            rowId     = u32(payload, off + 4),
        };
    end
    return { entries = entries };
end

-- WITHDRAW C2S: { u16 Count; u16 Rsvd; N x { u32 RowId; u16 Qty; u16 Rsvd } }.
function M.withdrawPayload(entries)
    local parts = { wu16(#entries), wu16(0) };
    for _, e in ipairs(entries) do
        parts[#parts + 1] = wu32(e.rowId);
        parts[#parts + 1] = wu16(math.max(1, e.qty or 1));
        parts[#parts + 1] = wu16(0);
    end
    return table.concat(parts);
end

-- WITHDRAW S2C: { u16 Count; u16 Rsvd; N x { u32 RowId; u16 Moved; u16 Code } }.
function M.parseWithdrawAck(payload)
    if type(payload) ~= 'string' or #payload < 4 then return nil; end
    local count = u16(payload, 0);
    if #payload < 4 + count * 8 then return nil; end
    local entries = {};
    for i = 0, count - 1 do
        local off = 4 + i * 8;
        entries[#entries + 1] = {
            rowId = u32(payload, off),
            moved = u16(payload, off + 4),
            code  = u16(payload, off + 6),
        };
    end
    return { entries = entries };
end

-- The per-entry GearVaultCode words the client meets.
M.code =
{
    OK = 0, PARTIAL = 1, NOTHING_TO_DO = 2, NOT_ELIGIBLE = 3, ITEM_BUSY = 4,
    NO_INSTANCE = 5, INVENTORY_FULL = 6, RARE_HELD = 7, BUSY = 8, STORE_ERROR = 9,
    DUPLICATE = 10, TOO_FAR = 11, NOT_IN_CITY = 12, UNKNOWN_ITEM = 13,
    AMBIGUOUS_NAME = 14, NOT_IN_LAYOUT = 15,
};

M.ZERO24 = string.rep('\0', 24);

-- LAYOUT_SET C2S: { u8 Job (0 = my main); u8 Verb (0 add / 1 remove / 2 pin);
-- u16 ItemNo; u16 Count; u8 Hint; u8 Pinned; u8 IdentityExtra[24] }. One
-- entry per frame by protocol; batches ride the queue with distinct Seqs.
M.verb = { ADD = 0, REMOVE = 1, PIN = 2 };

function M.layoutSetPayload(e)
    local id24 = e.identity;
    if type(id24) ~= 'string' or #id24 < 24 then
        id24 = (type(id24) == 'string') and (id24 .. string.rep('\0', 24 - #id24)) or M.ZERO24;
    else
        id24 = id24:sub(1, 24);
    end
    return string.char((e.job or 0) % 256, (e.verb or 0) % 256)
        .. wu16(e.itemId or 0) .. wu16(e.count or 1)
        .. string.char((e.hint or 0) % 256, e.pinned and 1 or 0)
        .. id24;
end

-- LAYOUT_SET S2C: { u16 Code; u16 Rsvd }.
function M.parseLayoutSetAck(payload)
    if type(payload) ~= 'string' or #payload < 2 then return nil; end
    return { code = u16(payload, 0) };
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

-- The CURRENT job's layout as the server holds it (slice 2, read-only view):
-- committed whole from LAYOUT_LIST pages, exactly like the mirror. `job` is
-- the job the entries belong to (an ask with 0 resolves to the main job we
-- last saw). Invalidated by a job change or a `!vault` command.
M.layoutCache = { job = nil, entries = {}, fresh = false, stamp = nil };

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
        M.layoutCache.fresh = false;   -- "the current job's layout" is a different job's now
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
    -- An outgoing `!vault ...` may mutate the store OR a layout; resync after
    -- it lands.
    M.markStale(M.SETTLE_CHAT, 'chat');
    M.layoutCache.fresh = false;
    st.probeOnly = false;
end

-- Ask for a job's layout (0 = my main job). The tab calls this; pages ride
-- the same one-in-flight machinery as everything else.
function M.requestLayout(job)
    if st.dormant then return false; end
    st.layoutWant = { job = job or 0 };
    return true;
end

-- Queue a withdraw (slice 2's one write verb). entries = { { rowId, qty } ... },
-- at most limits.maxWithdraw of them; onDone(ackEntries, err) fires exactly
-- once -- ackEntries nil with err = 'too_far' | 'busy' | 'unavailable' |
-- 'timeout' | 'malformed' when the frame as a whole was refused or lost.
-- Retries re-send the SAME Seq (the server's replay ring answers a retried
-- frame from the ring); an exhausted retry NEVER re-queues with a fresh Seq
-- -- the outcome is unknown, so the mirror resyncs instead.
function M.requestWithdraw(entries, onDone)
    if st.dormant or type(entries) ~= 'table' or #entries == 0 then return false; end
    local cap = (M.limits ~= nil and M.limits.maxWithdraw) or 62;
    if #entries > cap then return false; end
    st.withdrawQ = st.withdrawQ or {};
    st.withdrawQ[#st.withdrawQ + 1] = { entries = entries, onDone = onDone };
    return true;
end

-- Queue a deposit (the Inventory sub-tab's Store / Store all). entries =
-- { { container, slot } ... }, at most limits.maxDeposit; onDone(ackEntries,
-- err) fires once. Same mutating-op laws as withdraw. A successful run marks
-- the mirror stale (0s) rather than doing arithmetic: the ack carries no
-- quantities, and one LIST after a Warden stop is cheap.
function M.requestDeposit(entries, onDone)
    if st.dormant or type(entries) ~= 'table' or #entries == 0 then return false; end
    local cap = (M.limits ~= nil and M.limits.maxDeposit) or 124;
    if #entries > cap then return false; end
    st.depositQ = st.depositQ or {};
    st.depositQ[#st.depositQ + 1] = { entries = entries, onDone = onDone };
    return true;
end

-- Queue one layout edit (slice 3). e = { job (0 = my main), verb (M.verb.*),
-- itemId, count, hint, pinned, identity (24 raw bytes; nil = zero blob) };
-- onDone(code, err) fires once -- code from the ack (NOT_IN_CITY included),
-- or nil with err on a refused/lost frame. Same mutating-op laws as
-- withdraw: same-Seq retries only, exhaustion reports and never re-sends.
function M.requestLayoutSet(e, onDone)
    if st.dormant or type(e) ~= 'table' or type(e.itemId) ~= 'number' then return false; end
    st.layoutSetQ = st.layoutSetQ or {};
    st.layoutSetQ[#st.layoutSetQ + 1] = { e = e, onDone = onDone };
    return true;
end

-- Drop every QUEUED layout edit (the in-flight one, if any, still answers).
-- The reconcile engine calls this the moment one add refuses NOT_IN_CITY:
-- every sibling targets the same job, so the rest would only spam refusals.
function M.cancelLayoutSets()
    local n = #(st.layoutSetQ or {});
    -- keep index 1 when it is the in-flight request's backing entry
    if st.pending ~= nil and st.pending.op == M.op.LAYOUT_SET and n > 0 then
        st.layoutSetQ = { st.layoutSetQ[1] };
        return n - 1;
    end
    st.layoutSetQ = {};
    return n;
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
                local dead = st.pending;
                st.pending = nil;
                if dead.op == M.op.WITHDRAW or dead.op == M.op.DEPOSIT then
                    -- The outcome is UNKNOWN (it may have executed and the
                    -- reply died). Never re-send with a fresh Seq -- that is
                    -- how a lost frame becomes a double op. Report, and let
                    -- a full resync reveal the truth.
                    local q = (dead.op == M.op.WITHDRAW) and st.withdrawQ or st.depositQ;
                    local req = table.remove(q or {}, 1);
                    if req ~= nil and type(req.onDone) == 'function' then
                        pcall(req.onDone, nil, 'timeout');
                    end
                    M.markStale(0, 'write timeout');
                elseif dead.op == M.op.LAYOUT_SET then
                    -- Same mutating-op law: report, drop, and let the layout
                    -- re-ask reveal what actually landed.
                    local req = table.remove(st.layoutSetQ or {}, 1);
                    if req ~= nil and type(req.onDone) == 'function' then
                        pcall(req.onDone, nil, 'timeout');
                    end
                    M.layoutCache.fresh = false;
                elseif dead.op == M.op.LAYOUT_LIST then
                    st.layoutAcc = nil;   -- the tab just shows stale and re-asks
                else
                    -- Lost sync: stale mirror, long backoff, ONE quiet state
                    -- (no chat spam -- /dl vault says it when asked).
                    st.rowsAcc = nil;
                    st.giveups = st.giveups + 1;
                    st.staleAt = now + M.GIVEUP_BACKOFF;
                    M.mirror.fresh = false;
                end
            else
                st.pending.retries = st.pending.retries + 1;
                sendPending(now);   -- SAME Seq: the replay ring makes this safe
            end
        end
        return;
    end

    if now - st.lastSend < M.MIN_GAP then return; end

    -- Send priority: the write verbs a player is waiting on, then a layout
    -- ask, then the background mirror sync.
    if st.withdrawQ ~= nil and st.withdrawQ[1] ~= nil then
        beginOp('withdraw', M.op.WITHDRAW, M.withdrawPayload(st.withdrawQ[1].entries), now);
        return;
    end
    if st.depositQ ~= nil and st.depositQ[1] ~= nil then
        beginOp('deposit', M.op.DEPOSIT, M.depositPayload(st.depositQ[1].entries), now);
        return;
    end
    if st.layoutSetQ ~= nil and st.layoutSetQ[1] ~= nil then
        beginOp('layoutset', M.op.LAYOUT_SET, M.layoutSetPayload(st.layoutSetQ[1].e), now);
        return;
    end
    if st.layoutWant ~= nil then
        local want = st.layoutWant;
        st.layoutWant = nil;
        st.layoutAcc = {};
        beginOp('layout', M.op.LAYOUT_LIST, M.layoutPayload(want.job, 0), now, 0);
        st.pending.job = want.job;
        return;
    end

    if st.staleAt == nil or now < st.staleAt then return; end

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
        -- BUSY / TOO_FAR / UNAVAILABLE / MALFORMED: not a dead server, just
        -- not now -- and each op kind fails toward its own consumer.
        st.pending = nil;
        if p.op == M.op.WITHDRAW or p.op == M.op.DEPOSIT then
            local q = (p.op == M.op.WITHDRAW) and st.withdrawQ or st.depositQ;
            local req = table.remove(q or {}, 1);
            if req ~= nil and type(req.onDone) == 'function' then
                local word = (f.status == M.status.TOO_FAR and 'too_far')
                    or (f.status == M.status.BUSY and 'busy') or 'unavailable';
                pcall(req.onDone, nil, word);
            end
            return true;   -- a refused write moved nothing: the mirror stands
        end
        if p.op == M.op.LAYOUT_SET then
            local req = table.remove(st.layoutSetQ or {}, 1);
            if req ~= nil and type(req.onDone) == 'function' then
                local word = (f.status == M.status.TOO_FAR and 'too_far')
                    or (f.status == M.status.BUSY and 'busy') or 'unavailable';
                pcall(req.onDone, nil, word);
            end
            return true;
        end
        if p.op == M.op.LAYOUT_LIST then
            st.layoutAcc = nil;
            return true;
        end
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

    if p.op == M.op.LAYOUT_LIST then
        local chunk = M.parseLayoutChunk(f.payload);
        st.pending = nil;
        if chunk == nil then
            st.layoutAcc = nil;
            return true;
        end
        local last = p.cursor or 0;
        for _, e in ipairs(chunk.entries) do
            st.layoutAcc[#st.layoutAcc + 1] = e;
            if e.ordinal > last then last = e.ordinal; end
        end
        if f.flags % 2 == M.FLAG_MORE then
            beginOp('layout', M.op.LAYOUT_LIST, M.layoutPayload(p.job, last), now, last);
            st.pending.job = p.job;
        else
            M.layoutCache = {
                job     = (p.job ~= nil and p.job ~= 0) and p.job or st.lastJob,
                entries = st.layoutAcc,
                fresh   = true,
                stamp   = now,
            };
            st.layoutAcc = nil;
        end
        return true;
    end

    if p.op == M.op.LAYOUT_SET then
        local ack = M.parseLayoutSetAck(f.payload);
        st.pending = nil;
        local req = table.remove(st.layoutSetQ or {}, 1);
        if req ~= nil and type(req.onDone) == 'function' then
            if ack == nil then
                pcall(req.onDone, nil, 'malformed');
            else
                pcall(req.onDone, ack.code, nil);
            end
        end
        -- An accepted edit changed the server's layout: the cached view is
        -- behind until the next LAYOUT_LIST (the caller batches the re-ask).
        if ack ~= nil and ack.code == M.code.OK then
            M.layoutCache.fresh = false;
        end
        return true;
    end

    if p.op == M.op.DEPOSIT then
        local ack = M.parseDepositAck(f.payload);
        st.pending = nil;
        local req = table.remove(st.depositQ or {}, 1);
        if ack == nil then
            if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, nil, 'malformed'); end
            return true;
        end
        -- Anything stored changed the vault: one LIST resync is the honest
        -- (and cheap -- you are standing at a Warden) way to fold it in.
        for _, e in ipairs(ack.entries) do
            if e.code == M.code.OK or e.code == M.code.PARTIAL then
                M.markStale(0, 'deposit');
                break;
            end
        end
        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, ack.entries, nil); end
        return true;
    end

    if p.op == M.op.WITHDRAW then
        local ack = M.parseWithdrawAck(f.payload);
        st.pending = nil;
        local req = table.remove(st.withdrawQ or {}, 1);
        if ack == nil then
            if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, nil, 'malformed'); end
            return true;
        end
        -- SUBTRACTION, the E-Box law: we sent the rows, the ack says what
        -- moved, so the mirror is arithmetic -- no re-LIST. A NO_INSTANCE
        -- answer means the mirror believed a row the vault no longer holds:
        -- that one forces the honest resync.
        local goneRow = false;
        for _, e in ipairs(ack.entries) do
            if e.moved > 0 then
                for i, row in ipairs(M.mirror.rows) do
                    if row.rowId == e.rowId then
                        row.qty = row.qty - e.moved;
                        if row.qty <= 0 then table.remove(M.mirror.rows, i); end
                        break;
                    end
                end
            end
            if e.code == M.code.NO_INSTANCE then goneRow = true; end
        end
        local counts = {};
        for _, r in ipairs(M.mirror.rows) do
            counts[r.itemId] = (counts[r.itemId] or 0) + math.max(1, r.qty);
        end
        M.mirror.counts = counts;
        M.mirror.vaultCount = #M.mirror.rows;
        if type(M._onFresh) == 'function' then pcall(M._onFresh); end
        if goneRow then M.markStale(0, 'withdraw met a gone row'); end
        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, ack.entries, nil); end
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
    M.layoutCache = { job = nil, entries = {}, fresh = false, stamp = nil };
    M.limits = nil;
    st = { dormant = false, pending = nil, seq = 0, lastSend = 0, staleAt = nil,
           giveups = 0, rowsAcc = nil, lastJob = nil, saidProto = false };
end

function M._st() return st; end

return M;
