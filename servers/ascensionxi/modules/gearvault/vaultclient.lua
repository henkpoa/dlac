--[[
    ascensionxi/gearvault/vaultclient.lua -- THE one client for AscensionXI's Gear
    Vault wire (slice 1 of docs/design/gear-vault-integration.md: the wire +
    the mirror, READ-ONLY -- HELLO and LIST only; no write op exists in this
    file yet by design).

    The protocol is the 0x1E0 channel's vault partition (ops 0x40-0x7F),
    whose byte layouts are recorded in the design doc and owned server-side
    by the ascensionxi repo's modules/custom/lua/gear_vault.lua. The eboxclient
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
    LIST2 = 0x46, LAYOUT_LIST2 = 0x47, LAYOUT_SET2 = 0x48,
    INSTANCE_LOOKUP = 0x49, LOST_LIST = 0x4A,
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
    NOT_ATTUNED       = 7,   -- The Deeper Room not finished: no vault for this character (D14)
};

M.FLAG_MORE = 1;

-- The attunement quest, named where the player reads it (statusLine, the
-- tab, the one login line). The server's gate is the quest's completion
-- and nothing else (gear_vault.lua isAttuned -> xi.axq.isComplete).
M.ATTUNE_QUEST = 'The Deeper Room';
M.ATTUNE_HINT  = 'the Hollow One in your starting city, level 5, after The Hollow Room';
M.ATTUNE_WIKI  = 'https://www.ascensionffxi.com/wiki/The_Deeper_Room';

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
M.SETTLE_LAYOUT  = 0.25;  -- coalesce an inventory burst before reading its layout
M.MAX_LAYOUT_WAIT = 1.0;  -- continuous inventory traffic cannot keep deferring the ask
M.RECHECK_UNATTUNED = 300; -- an un-attuned character re-asks this rarely (one HELLO)

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
    local instances = u16(payload, 2) % 2 == 1;
    if instances and #payload < 20 then return nil; end
    return {
        instances = instances, revision = instances and u32(payload, 12) or nil,
        atomicInstanceAdd = instances and math.floor(u16(payload, 2) / 2) % 2 == 1,
        maxList2 = u8(payload, 16), maxLayoutList2 = u8(payload, 17),
        maxLookup = u8(payload, 18), maxLostList = u8(payload, 19),
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

-- DEPOSIT S2C: { u16 Count; u16 DuplicateLocation; N x { u8 Container; u8 Slot; u16 Code;
-- u32 RowId } }.
-- Location is 1=vault, 2=equipped, 3=wardrobe for a single duplicate;
-- zero for older servers and batches. Entry shape and result codes are unchanged.
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
            duplicateLocation = (count == 1) and u16(payload, 2) or 0,
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
    INSTANCE_LOST = 17, INSTANCE_OUTSIDE = 18, ALREADY_BOUND = 19,
};

M.ZERO24 = string.rep('\0', 24);

-- LAYOUT_SET C2S: { u8 Job (0 = my main); u8 Verb (0 add / 1 remove / 2 pin);
-- u16 ItemNo; u16 Count; u8 Hint; u8 Pinned; u8 IdentityExtra[24] }. One
-- entry per frame by protocol; batches ride the queue with distinct Seqs.
M.verb = { ADD = 0, REMOVE = 1, PIN = 2, BIND = 3 };

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
    unattuned = false,   -- server answered NOT_ATTUNED: no vault for THIS character until the quest
    pending  = nil,      -- { kind='probe'|'sync-hello'|'sync-list', op, seq,
                         --   frame, sentAt, retries, cursor }
    seq      = 0,        -- last Seq used (wraps at 255)
    lastSend = 0,
    staleAt  = nil,      -- _clock() time a sync may begin (nil = fresh, no work)
    giveups  = 0,
    rowsAcc  = nil,      -- accumulating LIST pages
    lastJob  = nil,      -- main-job edge detector (pump-fed)
    saidProto = false,
    trace    = {},       -- the evidence ring: lastSent / lastRecv / why (traceLine)
};

-- The client's own evidence (2026-09-08, Henrik's prod field report: "stale
-- -- 0 pieces mirrored (0 rows)" with NO failed syncs -- a readout that two
-- silent paths share, a refused status and an unparseable HELLO -- and the
-- client could not say which). Every send, every inbound frame and every
-- quiet outcome leaves a note; /dl vault prints them. Names, never numbers.
local function opName(op)
    for k, v in pairs(M.op) do if v == op then return k; end end
    return string.format('op 0x%02X', tonumber(op) or 0);
end
local function statusName(s)
    for k, v in pairs(M.status) do if v == s then return k; end end
    return 'status ' .. tostring(s);
end
local function noteWhy(why, now)
    st.trace.why   = why;
    st.trace.whyAt = now;
end

local function nextSeq()
    st.seq = (st.seq + 1) % 256;
    return st.seq;
end

local function sendPending(now, retry)
    if now - st.lastSend < M.MIN_GAP then return false; end
    if not retry and st.pending.op == M.op.DEPOSIT then
        local req = st.depositQ and st.depositQ[1];
        for _, e in ipairs(req and req.entries or {}) do
            if e.expectedInstanceId then
                local at = (st.instanceCache or {})[tostring(e.container) .. ':' .. tostring(e.slot)];
                if not at or at.instanceId ~= e.expectedInstanceId or at.revision ~= M.revision then
                    st.pending = nil; table.remove(st.depositQ, 1);
                    if req.onDone then pcall(req.onDone, nil, 'location_changed'); end
                    return false;
                end
            end
        end
    end
    if type(M._send) == 'function' then
        local ok, sent = pcall(M._send, st.pending.frame);
        if not ok or sent == false then return false; end
    end
    if retry then st.pending.retries = st.pending.retries + 1; end
    st.pending.sentAt = now;
    st.lastSend = now;
    st.trace.lastSent = { kind = st.pending.kind, op = st.pending.op, seq = st.pending.seq,
                          at = now, retries = st.pending.retries };
    if st.pending.kind == 'layoutset' and M._audit then
        local req = st.layoutSetQ and st.layoutSetQ[1];
        if req then pcall(M._audit, 'send', req.e, st.pending.seq, st.pending.retries); end
    end
    return true;
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
    if st.layoutBatch ~= nil and why ~= 'layout edit' then
        st.layoutBatch.valid = false;
    end
    local at = M._clock() + (settle or 0);
    if st.unattuned then
        -- A reason (zone-in, job change, !vault, manual) PULLS the rare
        -- re-check forward: the quest may just have been finished.
        st.staleAt = at;
        return;
    end
    if st.staleAt == nil or at > st.staleAt then st.staleAt = at; end
    M.mirror.fresh = false;
end

-- The server said NOT_ATTUNED: The Deeper Room is not finished, so no
-- vault exists for this character (D14 -- every op, reads included, is
-- refused). Not dormant: the quest can be finished mid-session, so the
-- client goes quiet -- one HELLO per RECHECK_UNATTUNED, pulled forward by
-- the usual reasons -- instead of the 30 s failed-sync loop. Every queued
-- ask is drained toward its consumer with 'not_attuned', the mirror reads
-- as the truth (an empty vault); the tab and /dl vault say WHY.
local function goUnattuned(now)
    local first = not st.unattuned;
    st.unattuned = true;
    st.pending = nil;
    st.rowsAcc = nil;
    st.layoutAcc = nil;
    st.layoutWant = nil;
    st.probeOnly = false;
    for _, q in ipairs({ st.withdrawQ or {}, st.depositQ or {}, st.layoutSetQ or {}, st.lookupQ or {} }) do
        while q ~= nil and q[1] ~= nil do
            local req = table.remove(q, 1);
            if type(req.onDone) == 'function' then pcall(req.onDone, nil, 'not_attuned'); end
        end
    end
    M.mirror.rows = {};
    M.mirror.counts = {};
    M.mirror.vaultCount = 0;
    M.mirror.fresh = false;
    M.mirror.stamp = now;          -- not "never synced": pump must not re-arm the login sync
    M.layoutCache = { job = nil, entries = {}, fresh = false, stamp = nil };
    M.invalidateInstances();
    M.lost = { entries = {}, fresh = false };
    st.staleAt = now + M.RECHECK_UNATTUNED;
    if first and type(M._onFresh) == 'function' then pcall(M._onFresh); end
    -- No chat line here (Henrik, 2026-09-08: a first-time player should not
    -- be greeted by it -- "keep the spamming down"). The tab and /dl vault
    -- carry the quest; the one line that stays is the vault OPENING.
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
        M.invalidateInstances();
        M.cancelLayoutSets('job_changed');
        M.markStale(M.SETTLE_JOB, 'job change');
        M.invalidateLayout();   -- the current job's layout is a different job's now
        if st.pending and st.pending.kind == 'layout' and st.pending.sentAt == nil then
            st.pending, st.layoutAcc = nil, nil;
            st.layoutWant = { job = 0 };
        end
    end
    st.lastJob = job;
end

function M.noteZoneIn()
    M.invalidateInstances();
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
    M.invalidateLayout();
    st.probeOnly = false;
end

-- Ask for a job's layout (0 = my main job). The tab calls this; pages ride
-- the same one-in-flight machinery as everything else.
function M.requestLayout(job)
    if st.dormant or st.unattuned then return false; end   -- no layout exists to ask for
    job = job or 0;
    local target = job == 0 and (st.lastJob or 0) or job;
    local p = st.pending;
    if p and p.kind == 'layout' and p.job == target
        and p.layoutEpoch == (st.layoutEpoch or 0) then return true; end
    st.layoutWant = { job = job };
    return true;
end

-- Track changes separately from requests: UI/reconciler reads can share an
-- in-flight snapshot, but a later inventory or edit event cannot be lost.
function M.invalidateLayout(settle)
    M.layoutCache.fresh = false;
    st.layoutEpoch = (st.layoutEpoch or 0) + 1;
    if settle then
        local now = M._clock();
        st.layoutDirtySince = st.layoutDirtySince or now;
        st.layoutAfter = math.min(now + settle, st.layoutDirtySince + M.MAX_LAYOUT_WAIT);
    end
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
-- Keep a stable admission snapshot through a batch of edits. Only additions
-- reserve space: removals do not promise free slots until the server confirms
-- them in a fresh layout. Locks survive acknowledgements and cancelled edits
-- until BOTH views catch up; a job/zone/external mutation invalidates admission.
function M.layoutAddState(itemId, identity, instanceId)
    if not M.layoutBusy() and M.layoutCache.fresh and M.mirror.fresh then
        st.layoutBatch = nil;
    end
    local batch = st.layoutBatch;
    local key = M.entryKey({ itemId = itemId, identity = identity, instanceId = instanceId });
    return {
        ready = not st.dormant and not st.unattuned and
            ((batch ~= nil and batch.valid) or
             (batch == nil and M.layoutCache.fresh and M.mirror.fresh and not M.layoutBusy())),
        pending = batch ~= nil and batch.items[key] == true,
        reserved = batch and batch.reserved or 0,
        entries = batch and batch.entries or M.layoutCache.entries,
    };
end

-- Instance protocol, negotiated by HELLO bit 0. Never infer identity from
-- changing extra bytes. The legacy codecs above remain byte-for-byte usable.
function M.instanceMode() return M.limits ~= nil and M.limits.instances == true; end

function M.entryKey(e)
    if (e.instanceId or 0) > 0 then return 'i:' .. e.instanceId; end
    if e.kind == 2 then return 'legacy:' .. tostring(e.ordinal); end
    return tostring(e.itemId) .. ':' .. (e.identity or M.ZERO24);
end

function M.parseList2(payload)
    if type(payload) ~= 'string' or #payload < 8 then return nil; end
    local n = u16(payload, 0);
    if n > 13 or #payload < 8 + n * 36 then return nil; end
    local out = { entries = {}, revision = u32(payload, 4) };
    for i = 0, n - 1 do
        local o = 8 + i * 36;
        out.entries[#out.entries + 1] = { rowId = u32(payload, o), itemId = u16(payload, o + 4),
            qty = u16(payload, o + 6), instanceId = u32(payload, o + 8), identity = payload:sub(o + 13, o + 36) };
    end
    return out;
end

function M.parseLayout2(payload)
    if type(payload) ~= 'string' or #payload < 8 then return nil; end
    local n = u16(payload, 0);
    if n > 12 or #payload < 8 + n * 40 then return nil; end
    local out = { entries = {}, revision = u32(payload, 4) };
    for i = 0, n - 1 do
        local o = 8 + i * 40;
        out.entries[#out.entries + 1] = { ordinal = u16(payload, o), itemId = u16(payload, o + 2),
            count = u16(payload, o + 4), hint = u8(payload, o + 6), pinned = u8(payload, o + 7) ~= 0,
            instanceId = u32(payload, o + 8), kind = u8(payload, o + 12), state = u8(payload, o + 13),
            location = u8(payload, o + 14), slot = u8(payload, o + 15), identity = payload:sub(o + 17, o + 40) };
    end
    return out;
end

function M.layoutSet2Payload(e)
    local selector = e.selector;
    if selector == nil then
        selector = e.verb == M.verb.BIND and 2 or ((e.instanceId or 0) > 0 and 0 or (e.ordinal and 2 or 1));
    end
    local identity = ((e.identity or '') .. M.ZERO24):sub(1, 24);
    return string.char(e.job or 0, e.verb or 0, selector, e.hint or 0, e.pinned and 1 or 0, 0)
        .. wu16(e.itemId) .. wu16(e.count or 1) .. wu32(e.instanceId) .. wu16(e.ordinal) .. identity;
end

function M.parseLayoutSet2Ack(payload)
    if type(payload) ~= 'string' or #payload < 8 then return nil; end
    local n = u16(payload, 2);
    if n > 123 or #payload < 8 + n * 4 then return nil; end
    local out = { code = u16(payload, 0), revision = u32(payload, 4), affected = {} };
    for i = 0, n - 1 do out.affected[#out.affected + 1] = u32(payload, 8 + i * 4); end
    return out;
end

function M.lookupPayload(entries, revision)
    return wu32(revision) .. M.depositPayload(entries);
end

function M.parseLookup(payload)
    if type(payload) ~= 'string' or #payload < 8 then return nil; end
    local n = u16(payload, 0);
    if n > 41 or #payload < 8 + n * 12 then return nil; end
    local out = { entries = {}, revision = u32(payload, 4) };
    for i = 0, n - 1 do
        local o = 8 + i * 12;
        out.entries[#out.entries + 1] = { container = u8(payload, o), slot = u8(payload, o + 1),
            itemId = u16(payload, o + 2), instanceId = u32(payload, o + 4),
            state = u8(payload, o + 8), locked = u8(payload, o + 9) ~= 0 };
    end
    return out;
end

function M.parseLost(payload)
    if type(payload) ~= 'string' or #payload < 4 then return nil; end
    local n = u16(payload, 0);
    if n > 30 or #payload < 4 + n * 16 then return nil; end
    local out = { entries = {} };
    for i = 0, n - 1 do
        local o = 4 + i * 16;
        out.entries[#out.entries + 1] = { instanceId = u32(payload, o), itemId = u16(payload, o + 4),
            state = u8(payload, o + 6), replacedBy = u32(payload, o + 8), lostAt = u32(payload, o + 12) };
    end
    return out;
end

function M.requestLayoutSet(e, onDone)
    if st.dormant or type(e) ~= 'table' or type(e.itemId) ~= 'number' then return false; end
    local copy = {}; for k, v in pairs(e) do copy[k] = v; end; e = copy;
    if (e.job or 0) == 0 and st.lastJob then e.job = st.lastJob; end
    if not M.instanceMode() and (e.verb == M.verb.BIND or (e.instanceId or 0) > 0) then return false; end
    local atomicPin = M.instanceMode() and M.limits.atomicInstanceAdd
        and (e.instanceId or 0) > 0 and (e.selector == nil or e.selector == 0);
    if e.verb == M.verb.ADD and e.pinned and not atomicPin then
        local done = onDone;
        onDone = function(code, err, affected)
            if code == M.code.OK or code == M.code.PARTIAL then
                local pin = {}; for k, v in pairs(e) do pin[k] = v; end
                pin.verb = M.verb.PIN;
                -- The logical edit completes after both legacy operations.
                -- Preserve a partial ADD result even when PIN succeeds.
                local queued = M.requestLayoutSet(pin, function(pinCode, pinErr)
                    if done then
                        done(pinCode == M.code.OK and code or pinCode, pinErr, affected);
                    end
                end);
                if not queued and done then done(nil, 'unavailable'); end
            elseif done then done(code, err, affected); end
        end;
    end
    local admission = M.layoutAddState(e.itemId, e.identity, e.instanceId);
    if st.layoutBatch == nil and admission.ready then
        st.layoutBatch = { valid = true, entries = M.layoutCache.entries, items = {}, reserved = 0 };
    end
    local batch = st.layoutBatch;
    if batch ~= nil then
        batch.items[M.entryKey(e)] = true;
        if (e.job or 0) ~= 0 and e.job ~= st.lastJob then
            batch.valid = false;
        elseif e.verb == M.verb.ADD or e.verb == M.verb.BIND then
            batch.reserved = batch.reserved + (e.count or 1);
        end
    end
    st.layoutSetQ = st.layoutSetQ or {};
    st.layoutSetQ[#st.layoutSetQ + 1] = { e = e, onDone = onDone };
    return true;
end

-- The reconciler waits for every edit. Manual admission uses per-item locks
-- and reserved space from layoutAddState instead.
function M.layoutBusy()
    return #(st.layoutSetQ or {}) > 0;
end

-- Drop every QUEUED layout edit (the in-flight one, if any, still answers).
-- The reconcile engine calls this the moment one add refuses NOT_IN_CITY:
-- every sibling targets the same job, so the rest would only spam refusals.
function M.cancelLayoutSets(reason)
    local n = #(st.layoutSetQ or {});
    local old = st.layoutSetQ or {};
    local first = 1;
    -- keep index 1 when it is the in-flight request's backing entry
    if st.pending ~= nil and (st.pending.op == M.op.LAYOUT_SET or st.pending.op == M.op.LAYOUT_SET2)
        and st.pending.sentAt ~= nil and n > 0 then
        st.layoutSetQ = { st.layoutSetQ[1] };
        first = 2;
    else
        if st.pending and (st.pending.op == M.op.LAYOUT_SET or st.pending.op == M.op.LAYOUT_SET2) then st.pending = nil; end
        st.layoutSetQ = {};
    end
    if reason then
        for i = first, n do
            if type(old[i].onDone) == 'function' then pcall(old[i].onDone, nil, reason); end
        end
    end
    return n - first + 1;
end

function M.currentJob() return st.lastJob; end

M.lost = { entries = {}, fresh = false };

function M.invalidateInstances()
    st.instanceCache = {};
    st.inventoryEpoch = (st.inventoryEpoch or 0) + 1;
    -- Two present beats allow the game to apply inventory packets before
    -- any snapshot. No inventory memory is read inside packet_in.
    st.lookupAfter = (st.beat or 0) + 2;
end

function M.noteRevision(revision)
    if revision ~= nil and revision ~= M.revision then
        M.revision = revision;
        M.invalidateInstances();
    end
end

function M.requestLost()
    if not M.instanceMode() then return false; end
    if M.lost.fresh and M.lost.revision == M.revision
        and M.lost.epoch == (st.inventoryEpoch or 0) then return true; end
    local p = st.pending;
    if p and p.kind == 'lost' and p.lostRevision == M.revision
        and p.lostEpoch == (st.inventoryEpoch or 0) then return true; end
    st.lostWant = true; M.lost.fresh = false; return true;
end

local function queueLookup(entries, onDone)
    if not M.instanceMode() or st.dormant or st.unattuned or type(entries) ~= 'table'
        or #entries == 0 or #entries > math.min(41, M.limits.maxLookup) then return nil; end
    st.lookupQ = st.lookupQ or {};
    local copy = {};
    for _, e in ipairs(entries) do copy[#copy + 1] = { container = e.container, slot = e.slot }; end
    local req = { entries = copy, onDone = onDone, attempts = 0 };
    st.lookupQ[#st.lookupQ + 1] = req;
    return req;
end

function M.requestLookup(entries, onDone)
    return queueLookup(entries, onDone) ~= nil;
end

local function finishLookup(entries, err)
    local req = table.remove(st.lookupQ or {}, 1);
    if req and type(req.onDone) == 'function' then pcall(req.onDone, entries, err); end
end

-- Returns a verified mapping, or queues one read. Consumers must treat nil
-- as unknown, never fall back to matching extra bytes to a physical copy.
function M.instanceAt(container, slot, itemId)
    local key = tostring(container) .. ':' .. tostring(slot);
    local e = (st.instanceCache or {})[key];
    if e and e.itemId == itemId and e.revision == M.revision then return e; end
    st.lookupWaiting = st.lookupWaiting or {};
    if not st.lookupWaiting[key] and M._clock() >= (st.lookupRetryAt or 0) then
        local req = (st.lookupQ or {})[#(st.lookupQ or {})];
        -- Once snapshotted, a batch is immutable, including while the shared
        -- transport delays its send or a raced reply awaits another attempt.
        if req and req.automatic and req.attempts == 0
            and #req.entries < math.min(41, M.limits.maxLookup) then
            req.entries[#req.entries + 1] = { container = container, slot = slot };
        else
            req = queueLookup({ { container = container, slot = slot } }, function(_, err)
                for _, at in ipairs(req.entries) do
                    st.lookupWaiting[tostring(at.container) .. ':' .. tostring(at.slot)] = nil;
                end
                if err then st.lookupRetryAt = M._clock() + 2; end
            end);
            if req then req.automatic = true; end
        end
        if req then st.lookupWaiting[key] = true; end
    end
    return nil;
end

function M.bindingCandidates(itemId)
    local out, bound, seen = {}, {}, {};
    for _, e in ipairs(M.layoutCache.entries) do
        if (e.instanceId or 0) > 0 then bound[e.instanceId] = true; end
    end
    local function add(e, where)
        if e.itemId == itemId and (e.instanceId or 0) > 0 and not bound[e.instanceId] and not seen[e.instanceId] then
            seen[e.instanceId] = true;
            out[#out + 1] = { instanceId = e.instanceId, identity = e.identity, where = where };
        end
    end
    if M.mirror.fresh then for _, e in ipairs(M.mirror.rows) do add(e, 'Vault'); end end
    if M._shelfSlots then
        for _, e in ipairs(M._shelfSlots(itemId)) do
            local mapping = M.instanceAt(e.container, e.slot, itemId);
            if mapping and mapping.state == 1 then
                add({ itemId = itemId, instanceId = mapping.instanceId, identity = e.identity }, 'Wardrobe');
            end
        end
    end
    table.sort(out, function(a, b) return a.instanceId < b.instanceId; end);
    return out;
end

-- ---------------------------------------------------------------------------
-- The frame pump. `ready` = a real character is known (job id ~= 0). All
-- pacing lives here; callers just call it every frame.
-- ---------------------------------------------------------------------------
function M.pump(ready)
    if st.dormant or not ready then return; end
    st.beat = (st.beat or 0) + 1;
    local now = M._clock();

    -- First readiness of the session (addon load mid-session included, where
    -- no zone-in packet will ever arrive): arm the login sync.
    if M.mirror.stamp == nil and st.staleAt == nil and st.pending == nil then
        st.staleAt = now + 2.0;
    end

    if st.pending ~= nil then
        if st.pending.sentAt == nil then sendPending(now); return; end
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
                elseif (dead.op == M.op.LAYOUT_SET or dead.op == M.op.LAYOUT_SET2) then
                    -- Same mutating-op law: report, drop, and let the layout
                    -- re-ask reveal what actually landed.
                    local req = table.remove(st.layoutSetQ or {}, 1);
                    if req and M._audit then pcall(M._audit, 'timeout', req.e, dead.seq, 'outcome-unknown'); end
                    if req ~= nil and type(req.onDone) == 'function' then
                        pcall(req.onDone, nil, 'timeout');
                    end
                    M.invalidateLayout();
                    M.markStale(M.SETTLE_JOB, 'layout edit timeout');
                    st.probeOnly = false;
                elseif dead.op == M.op.INSTANCE_LOOKUP then
                    finishLookup(nil, 'timeout');
                elseif dead.op == M.op.LOST_LIST then
                    st.lostAcc = nil;
                elseif (dead.op == M.op.LAYOUT_LIST or dead.op == M.op.LAYOUT_LIST2) then
                    noteWhy('layout ask timed out (no reply after ' .. M.MAX_RETRIES .. ' retries)', now);
                    st.layoutAcc = nil;   -- the tab just shows stale and re-asks
                else
                    -- Lost sync: stale mirror, long backoff, ONE quiet state
                    -- (no chat spam -- /dl vault says it when asked).
                    noteWhy(string.format('%s (%s#%d) timed out: no reply after %d retries',
                        dead.kind, opName(dead.op), dead.seq, M.MAX_RETRIES), now);
                    st.rowsAcc = nil;
                    st.giveups = st.giveups + 1;
                    st.staleAt = now + M.GIVEUP_BACKOFF;
                    M.mirror.fresh = false;
                end
            else
                sendPending(now, true);   -- SAME Seq: the replay ring makes this safe
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
        local e = st.layoutSetQ[1].e;
        beginOp('layoutset', M.instanceMode() and M.op.LAYOUT_SET2 or M.op.LAYOUT_SET,
            M.instanceMode() and M.layoutSet2Payload(e) or M.layoutSetPayload(e), now);
        return;
    end
    if st.layoutWant ~= nil and now >= (st.layoutAfter or 0) then
        local want = st.layoutWant;
        st.layoutWant = nil;
        st.layoutAcc = {};
        st.layoutRev = nil;
        st.layoutDirtySince, st.layoutAfter = nil, nil;
        beginOp('layout', M.instanceMode() and M.op.LAYOUT_LIST2 or M.op.LAYOUT_LIST, M.layoutPayload(want.job, 0), now, 0);
        st.pending.job = want.job == 0 and (st.lastJob or 0) or want.job;
        st.pending.layoutEpoch = st.layoutEpoch or 0;
        return;
    end

    if M.instanceMode() and st.lookupQ and st.lookupQ[1] and st.beat >= (st.lookupAfter or 0) then
        local req = st.lookupQ[1];
        req.attempts = req.attempts + 1;
        req.snapshot = {};
        for i, e in ipairs(req.entries) do
            req.snapshot[i] = M._readSlot and M._readSlot(e.container, e.slot) or nil;
        end
        beginOp('lookup', M.op.INSTANCE_LOOKUP, M.lookupPayload(req.entries, M.revision), now);
        st.pending.revision = M.revision; st.pending.epoch = st.inventoryEpoch;
        return;
    end
    if M.instanceMode() and st.lostWant and M.mirror.fresh then
        st.lostWant = nil; st.lostAcc = {};
        beginOp('lost', M.op.LOST_LIST, wu32(0), now, 0);
        st.pending.lostRevision = M.revision;
        st.pending.lostEpoch = st.inventoryEpoch or 0;
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
    if M._received then M._received(f.op, f.seq); end
    local now = M._clock();
    st.trace.lastRecv = { op = f.op, seq = f.seq, status = f.status, len = #(f.payload or ''), at = now };
    local p = st.pending;
    if p == nil or p.sentAt == nil or f.op ~= p.op or f.seq ~= p.seq then
        noteWhy(string.format('ate a %s#%d we were not waiting for (late duplicate)', opName(f.op), f.seq), now);
        return true;   -- ours by partition, but not the answer we await (late dupe): eat it
    end

    if f.status == M.status.BAD_OP then
        noteWhy('server answered BAD_OP: no vault service here -- dormant for the session', now);
        goDormant(false);            -- no vault on this server: sleep silently
        return true;
    end
    if f.status == M.status.PROTO_UNSUPPORTED then
        noteWhy('server answered PROTO_UNSUPPORTED -- dormant for the session', now);
        goDormant(true);
        return true;
    end
    if f.status == M.status.NOT_ATTUNED then
        noteWhy(string.format('server answered NOT_ATTUNED: %s is not finished -- no vault for this character yet (re-check every %ds, or on zone/job/!vault/Sync)',
            M.ATTUNE_QUEST, M.RECHECK_UNATTUNED), now);
        goUnattuned(now);
        return true;
    end
    if st.unattuned and f.status == M.status.OK then
        -- The first OK after a refusal: the quest is done. Say so once and
        -- let the normal sync run below.
        st.unattuned = false;
        M.mirror.stamp = nil;
        noteWhy('server stopped refusing: attuned now -- syncing', now);
        say(string.format('gear vault: %s is finished -- the vault is open, syncing.', M.ATTUNE_QUEST));
    end
    if f.status ~= M.status.OK then
        -- BUSY / TOO_FAR / UNAVAILABLE / MALFORMED: not a dead server, just
        -- not now -- and each op kind fails toward its own consumer.
        noteWhy(string.format('%s (%s#%d) refused: %s', p.kind, opName(p.op), p.seq, statusName(f.status)), now);
        st.pending = nil;
        if p.op == M.op.INSTANCE_LOOKUP then finishLookup(nil, 'unavailable'); return true; end
        if p.op == M.op.LOST_LIST then st.lostAcc = nil; return true; end
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
        if (p.op == M.op.LAYOUT_SET or p.op == M.op.LAYOUT_SET2) then
            local req = table.remove(st.layoutSetQ or {}, 1);
            if req and M._audit then pcall(M._audit, 'refused', req.e, p.seq, f.status); end
            if req ~= nil and type(req.onDone) == 'function' then
                local word = (f.status == M.status.TOO_FAR and 'too_far')
                    or (f.status == M.status.BUSY and 'busy') or 'unavailable';
                pcall(req.onDone, nil, word);
            end
            return true;
        end
        if (p.op == M.op.LAYOUT_LIST or p.op == M.op.LAYOUT_LIST2) then
            st.layoutAcc = nil;
            return true;
        end
        st.rowsAcc = nil;
        st.staleAt = now + M.GIVEUP_BACKOFF;
        M.mirror.fresh = false;
        return true;
    end

    if p.op == M.op.INSTANCE_LOOKUP then
        st.pending = nil;
        local chunk = M.parseLookup(f.payload);
        local req = (st.lookupQ or {})[1];
        if not req then return true; end
        if not chunk then finishLookup(nil, 'malformed'); return true; end
        local raced = p.epoch ~= st.inventoryEpoch or p.revision ~= chunk.revision
            or math.floor((f.flags or 0) / 2) % 2 == 1;
        M.noteRevision(chunk.revision);
        if not raced and #chunk.entries ~= #req.entries then finishLookup(nil, 'malformed'); return true; end
        for i, e in ipairs(chunk.entries) do
            local asked = req.entries[i];
            if not asked or e.container ~= asked.container or e.slot ~= asked.slot then
                finishLookup(nil, 'malformed'); return true;
            end
            if M._readSlot and req.snapshot[i] ~= e.itemId then raced = true; end
        end
        if raced then
            st.lookupAfter = st.beat + 2;
            if req.attempts >= 3 then finishLookup(nil, 'stale'); end
            return true;
        end
        st.instanceCache = st.instanceCache or {};
        for _, e in ipairs(chunk.entries) do
            e.revision = chunk.revision;
            st.instanceCache[tostring(e.container) .. ':' .. tostring(e.slot)] = e;
        end
        finishLookup(chunk.entries); return true;
    end

    if p.op == M.op.LOST_LIST then
        st.pending = nil;
        local chunk = M.parseLost(f.payload);
        if not chunk then st.lostAcc = nil; return true; end
        local last = p.cursor or 0;
        for _, e in ipairs(chunk.entries) do
            st.lostAcc[#st.lostAcc + 1] = e;
            last = math.max(last, e.instanceId);
        end
        if (f.flags or 0) % 2 == 1 then
            if last <= (p.cursor or 0) then st.lostAcc = nil; return true; end
            beginOp('lost', M.op.LOST_LIST, wu32(last), now, last);
            st.pending.lostRevision, st.pending.lostEpoch = p.lostRevision, p.lostEpoch;
        else
            if p.lostRevision ~= M.revision or p.lostEpoch ~= (st.inventoryEpoch or 0) then
                st.lostAcc = nil; M.requestLost(); return true;
            end
            M.lost = { entries = st.lostAcc, fresh = true, revision = p.lostRevision, epoch = p.lostEpoch };
            st.lostAcc = nil;
            if M._onLost then pcall(M._onLost, M.lost.entries); end
        end
        return true;
    end

    if p.op == M.op.HELLO then
        local h = M.parseHello(f.payload);
        st.pending = nil;
        if h == nil then
            noteWhy(string.format('HELLO reply unreadable: %d-byte payload (need 12) -- a changed server shape?', #(f.payload or '')), now);
            st.staleAt = now + M.GIVEUP_BACKOFF;
            return true;
        end
        local oldRevision = M.revision;
        local modeChanged = M.instanceMode() ~= (h.instances == true);
        M.limits = h;
        if modeChanged then
            -- A layout can arrive before the login HELLO. Its old rows lack
            -- instance/location fields even though the mirror is now v2.
            M.invalidateLayout();
            M.requestLayout(0);
        end
        M.noteRevision(h.revision);
        M.mirror.vaultCount = h.vaultCount;
        local rowsHeld = #M.mirror.rows;
        if p.kind == 'probe' and M.mirror.stamp ~= nil and h.vaultCount == rowsHeld
            and (not h.instances or oldRevision == h.revision) then
            -- The count agrees with what we hold: the probe re-stamps fresh
            -- and the LIST pages stay unspent.
            M.mirror.fresh = true;
            M.mirror.stamp = now;
            st.staleAt = nil;
            st.probeOnly = false;
            return true;
        end
        st.probeOnly = false;
        st.rowsAcc = {}; st.rowsRev = nil;
        beginOp('sync-list', M.instanceMode() and M.op.LIST2 or M.op.LIST, M.listPayload(0), now, 0);
        return true;
    end

    if p.op == M.op.LIST or p.op == M.op.LIST2 then
        local chunk = p.op == M.op.LIST2 and M.parseList2(f.payload) or (p.op == M.op.LIST and M.parseListChunk(f.payload));
        st.pending = nil;
        if chunk == nil then
            st.rowsAcc = nil;
            st.staleAt = now + M.GIVEUP_BACKOFF;
            return true;
        end
        if chunk.revision ~= nil then
            M.noteRevision(chunk.revision);
            if st.rowsRev ~= nil and st.rowsRev ~= chunk.revision then
                st.rowsAcc = nil; st.staleAt = now + 1; return true;
            end
            st.rowsRev = chunk.revision;
        end
        local last = p.cursor or 0;
        for _, e in ipairs(chunk.entries) do
            st.rowsAcc[#st.rowsAcc + 1] = e;
            if e.rowId > last then last = e.rowId; end
        end
        if f.flags % 2 == M.FLAG_MORE then
            if last <= (p.cursor or 0) then st.rowsAcc = nil; st.staleAt = now + M.GIVEUP_BACKOFF; return true; end
            beginOp('sync-list', p.op, M.listPayload(last), now, last);
        else
            M.mirror.vaultCount = #st.rowsAcc;   -- LIST is now the fresher truth
            commitMirror(now);
            if M.instanceMode() then M.requestLost(); end
        end
        return true;
    end

    if (p.op == M.op.LAYOUT_LIST or p.op == M.op.LAYOUT_LIST2) then
        local chunk = p.op == M.op.LAYOUT_LIST2 and M.parseLayout2(f.payload) or (p.op == M.op.LAYOUT_LIST and M.parseLayoutChunk(f.payload));
        st.pending = nil;
        if chunk == nil then
            st.layoutAcc = nil;
            return true;
        end
        if p.job ~= nil and p.job ~= 0 and p.job ~= st.lastJob then
            st.layoutAcc = nil; M.layoutCache.fresh = false; M.requestLayout(0); return true;
        end
        if p.layoutEpoch ~= (st.layoutEpoch or 0) then
            st.layoutAcc = nil;
            M.requestLayout(p.job);
            return true;
        end
        if chunk.revision ~= nil then
            M.noteRevision(chunk.revision);
            if st.layoutRev ~= nil and st.layoutRev ~= chunk.revision then
                st.layoutAcc = nil; M.layoutCache.fresh = false; return true;
            end
            st.layoutRev = chunk.revision;
        end
        local last = p.cursor or 0;
        for _, e in ipairs(chunk.entries) do
            st.layoutAcc[#st.layoutAcc + 1] = e;
            if e.ordinal > last then last = e.ordinal; end
        end
        if f.flags % 2 == M.FLAG_MORE then
            if last <= (p.cursor or 0) then st.layoutAcc = nil; return true; end
            beginOp('layout', p.op, M.layoutPayload(p.job, last), now, last);
            st.pending.job = p.job;
            st.pending.layoutEpoch = p.layoutEpoch;
        else
            M.layoutCache = {
                job     = (p.job ~= nil and p.job ~= 0) and p.job or st.lastJob,
                entries = st.layoutAcc,
                fresh   = true,
                stamp   = now,
            };
            st.layoutAcc = nil;
            if M.instanceMode() then M.requestLost(); end
        end
        return true;
    end

    if (p.op == M.op.LAYOUT_SET or p.op == M.op.LAYOUT_SET2) then
        local ack = p.op == M.op.LAYOUT_SET2 and M.parseLayoutSet2Ack(f.payload) or (p.op == M.op.LAYOUT_SET and M.parseLayoutSetAck(f.payload));
        if ack then M.noteRevision(ack.revision); end
        st.pending = nil;
        local req = table.remove(st.layoutSetQ or {}, 1);
        if req and M._audit then pcall(M._audit, 'reply', req.e, p.seq, ack and ack.code or 'malformed'); end
        if ack == nil then
            -- An unreadable acknowledgement cannot prove the edit failed.
            -- Refresh both stores before offering another increment.
            M.invalidateLayout();
            M.requestLayout(0);
            M.markStale(M.SETTLE_JOB, 'layout edit malformed reply');
            st.probeOnly = false;
        end
        if ack ~= nil and (ack.code == M.code.OK or ack.code == M.code.PARTIAL) then
            M.invalidateLayout();
            if req ~= nil and req.e.verb ~= M.verb.PIN
                and ((req.e.job or 0) == 0 or req.e.job == st.lastJob) then
                -- Applying the active layout moves items between vault and
                -- wardrobes. The old LIST must not offer those copies again.
                M.markStale(M.SETTLE_JOB, 'layout edit');
                st.probeOnly = false;
            end
        end
        if req ~= nil and type(req.onDone) == 'function' then
            if ack == nil then
                pcall(req.onDone, nil, 'malformed');
            else
                pcall(req.onDone, ack.code, nil, ack.affected);
            end
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
        local goneRow, changed = false, false;
        for _, e in ipairs(ack.entries) do
            if e.moved > 0 then
                changed = true;
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
        -- The subtraction IS a commit, so it re-stamps like one. Views cache
        -- on the stamp (slice 2's vault list does), so a withdraw that left
        -- the stamp behind kept painting the row that had just gone, and the
        -- player had to press Sync by hand (Henrik, playtest 2026-08-26).
        if changed then M.mirror.stamp = M._clock(); end
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
    if st.unattuned then return 'unattuned'; end
    if st.pending ~= nil then return 'syncing'; end
    if M.mirror.fresh then return 'fresh'; end
    return 'stale';
end

function M.statusLine()
    local s = M.state();
    if s == 'dormant' then
        return 'gear vault: not available on this server (or the addon was refused).';
    end
    if s == 'unattuned' then
        return string.format('gear vault: not open for this character yet -- finish %s (%s) to attune.',
            M.ATTUNE_QUEST, M.ATTUNE_HINT);
    end
    local n = 0;
    for _, r in ipairs(M.mirror.rows) do n = n + math.max(1, r.qty); end
    return string.format('gear vault: %s -- %d piece%s mirrored (%d row%s)%s%s.',
        s, n, (n == 1) and '' or 's', #M.mirror.rows, (#M.mirror.rows == 1) and '' or 's',
        (st.giveups > 0) and (' -- ' .. st.giveups .. ' failed sync(s), retrying') or '',
        M.instanceMode() and (' -- instances, revision ' .. tostring(M.revision)) or '');
end

-- The evidence line (/dl vault's second line): what left, what came back,
-- what the client made of it, and when it will try again. Ages are whole
-- seconds against _clock; 'never' where nothing happened yet.
function M.traceLine()
    local now = M._clock();
    local function ago(at)
        if at == nil then return 'never'; end
        return string.format('%ds ago', math.max(0, math.floor(now - at)));
    end
    local tr = st.trace or {};
    local parts = {};
    if tr.lastSent ~= nil then
        parts[#parts + 1] = string.format('last sent %s#%d (%s%s) %s', opName(tr.lastSent.op), tr.lastSent.seq,
            tr.lastSent.kind, (tr.lastSent.retries or 0) > 0 and (', retry ' .. tr.lastSent.retries) or '',
            ago(tr.lastSent.at));
    else
        parts[#parts + 1] = 'nothing sent yet';
    end
    if tr.lastRecv ~= nil then
        parts[#parts + 1] = string.format('last reply %s#%d %s, %d-byte payload, %s', opName(tr.lastRecv.op),
            tr.lastRecv.seq, statusName(tr.lastRecv.status), tr.lastRecv.len, ago(tr.lastRecv.at));
    else
        parts[#parts + 1] = 'no reply ever seen';
    end
    if tr.why ~= nil then parts[#parts + 1] = 'outcome: ' .. tr.why; end
    if st.dormant then
        parts[#parts + 1] = 'no retry (dormant)';
    elseif st.unattuned and st.pending == nil and st.staleAt ~= nil then
        parts[#parts + 1] = string.format('not attuned: next check in %ds', math.max(0, math.ceil(st.staleAt - now)));
    elseif st.pending ~= nil then
        parts[#parts + 1] = st.pending.sentAt == nil and 'queued for paced send' or 'awaiting a reply';
    elseif st.staleAt ~= nil then
        parts[#parts + 1] = string.format('next try in %ds', math.max(0, math.ceil(st.staleAt - now)));
    end
    return 'gear vault: ' .. table.concat(parts, ' | ') .. '.';
end

-- test seam
function M._reset()
    M.mirror = { fresh = false, rows = {}, counts = {}, vaultCount = nil, stamp = nil };
    M.layoutCache = { job = nil, entries = {}, fresh = false, stamp = nil };
    M.limits = nil; M.revision = nil; M.lost = { entries = {}, fresh = false };
    st = { dormant = false, unattuned = false, pending = nil, seq = 0, lastSend = 0,
           staleAt = nil, giveups = 0, rowsAcc = nil, lastJob = nil, saidProto = false, trace = {} };
end

function M._st() return st; end

return M;
