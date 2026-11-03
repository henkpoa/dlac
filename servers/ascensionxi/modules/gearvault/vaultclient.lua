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
    "box is a number we already know" law, adapted). The vault only changes
    IN A CITY (Henrik, 2026-09-30: "there should not be any gear vault
    events when outside the city") -- deposits and withdrawals at a Gear
    Vault counter, live layout edits in a city or the Mog House, the job
    change in the Mog House -- plus the server's own zone-in tidy. So:

      * full sync (HELLO + LIST pages) at first readiness, as soon as a MAIN
        JOB change is seen (the server applied the swap BEFORE it sent the
        job packets -- the reply order is FIFO), after our own writes, after
        a counter trade or an outgoing `!vault`, and on manual refresh;
      * a server PUSH (op CHANGED, negotiated in HELLO, kept for the whole
        session) names every change we did not make ourselves -- counter
        trades, chat verbs, the job-change and zone-in applies -- the
        moment it lands;
      * a ZONE LINE CHANGES NOTHING (Henrik, 2026-10-01): every view
        survives it, nothing is sent until the new zone's inventory is
        loaded, and the inventory re-send is not movement. Only against a
        server without pushes does arriving in a city cost one cheap HELLO
        probe (count + revision). Out in the field the client holds still --
        nothing there can change the vault. A LOGIN (not a zone line: no
        0x00B ZONECHANGE came first) costs one probe, which renews the
        subscription the server dropped at its game-in;
      * gear swaps refresh NOTHING (an equip flips a lock flag in a bag
        slot; only a slot whose ITEM changed invalidates what it touches).

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

    Group Ironman's SHARED VAULT (ops 0x60-0x6F, the section of that name
    below) rides this same client: one request in flight, the same pacing,
    and PUT / TAKE are writes, so their retries keep the seq inside the
    server's replay window. A shelf answer never changes the vault's own
    state.
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
    CHANGED = 0x4B,       -- S2C push only (seq 0): the server says what changed
    -- Group Ironman's Shared Vault (capability SHELF; server
    -- group_ironman_vault.lua): the group's shelf of gear.
    SV_LIST = 0x60, SV_PUT = 0x61, SV_TAKE = 0x62, SV_MEMBERS = 0x63,
    SV_CHANGED = 0x6F,    -- S2C push only (seq 0): the shelf or your group changed
};

-- HELLO capability bits. The reply's u16 @2 is the server's; the request's
-- u16 @2 is ours (an older server ignores it). A bit is used only when BOTH
-- sides set it -- a new dlac never sends an op or flag the server did not
-- advertise (an unknown op answers BAD_OP, which sends the client dormant).
M.cap =
{
    INSTANCES  = 1,   -- ops 0x46-0x4A (persistent instance ids)
    ATOMIC_ADD = 2,   -- selector-0 ADD stores pin/hint in one request
    PUSH       = 4,   -- CHANGED pushes to a subscribed client
    STREAM     = 8,   -- list reads answer up to N frames per request
    EXP_BAND_STATUS = 16, -- read-only recharge preflight, op 0x4C
    SHELF      = 32,  -- the Shared Vault, ops 0x60-0x6F; HELLO appends the group's ids
};
M.CLIENT_CAP_PUSH       = 1;   -- request word bit 0: subscribe me to CHANGED pushes
M.CLIENT_CAP_SHELF_PUSH = 2;   -- request word bit 1: ...and to SV_CHANGED (an older server ignores it)
M.CLIENT_CAPS = M.CLIENT_CAP_PUSH + M.CLIENT_CAP_SHELF_PUSH;

-- CHANGED scope bits (u16 @0 of the push payload).
M.change =
{
    VAULT    = 1,     -- vault rows moved (deposit, withdraw, apply, reward)
    LAYOUT   = 2,     -- layout rows changed for the jobs in the job mask
    APPLIED  = 4,     -- an apply finished (job change, zone-in, deposit, edit)
    LOST     = 8,     -- instances were lost / replaced / pruned
    ATTUNE   = 16,    -- attunement changed (The Deeper Room finished)
    CAPACITY = 32,    -- a wardrobe grew
};

M.STREAM_FRAMES = 8;  -- frames per streamed list request (the server caps too)

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

M.FLAG_MORE    = 1;   -- another page exists past this reply (ask again with the cursor)
M.FLAG_STALE   = 2;   -- INSTANCE_LOOKUP only: the request's revision is stale
M.FLAG_FOLLOWS = 4;   -- STREAM only: another frame of THIS reply follows

-- The attunement quest, named where the player reads it (statusLine, the
-- tab, the one login line). The server's gate is the quest's completion
-- and nothing else (gear_vault.lua isAttuned -> xi.axq.isComplete).
M.ATTUNE_QUEST = 'The Deeper Room';
M.ATTUNE_HINT  = 'the Hollow One in your starting city, level 5, after The Hollow Room';
M.ATTUNE_WIKI  = 'https://www.ascensionffxi.com/wiki/The_Deeper_Room';

-- Pacing. A WRITE's retries stay inside the server's 5 s replay window
-- (kept per map process, os.time granularity), so a retried frame is answered
-- from the ring and never re-executed: sends at 0, 1.5 and 3.0 s. A READ is
-- harmless to repeat but costs the server a whole page walk, so it waits
-- longer before assuming the frame was lost -- the field logs caught 71 reads
-- whose every copy was answered, late and together (2026-09-30).
M.SEND_TIMEOUT   = 1.5;   -- a write: seconds before re-sending the SAME Seq
M.MAX_RETRIES    = 2;     -- a write: then the outcome is unknown -> resync
-- No write retry leaves later than this after the write's FIRST send: past
-- the server's replay window a retry is a new request and runs again. The
-- retries are timed inside it, but the shared gate can hold one (another
-- producer, another addon's 0x1E0 -- FOREIGN_GAP, 2026.10.01c -- or a frame
-- stall). Nexus keeps the same deadline (RETRY_DEADLINE 3.5 s).
M.WRITE_DEADLINE = 3.5;
M.READ_TIMEOUT   = 2.5;   -- a read: seconds of silence before re-sending
M.READ_RETRIES   = 3;     -- a read: then give up and back off
M.MIN_GAP        = 0.1;   -- between two of OUR sends (the transport gates replies)
M.GIVEUP_BACKOFF = 10;    -- seconds before a failed or refused sync may try again
M.SETTLE_JOB     = 1.0;   -- after the main job is seen changed (the apply ran first)
M.ZONE_LOAD_TIMEOUT = 30.0; -- a zone-in whose inventory load is never seen to end ends its wait here
M.ZONE_LINE_MAX  = 60.0;  -- a zone-out whose zone-in is later than this was not a zone line
M.SETTLE_TIDY    = 3.0;   -- a server without pushes: probe after its zone-in tidy (2 s timer)
M.SETTLE_CHAT    = 3.0;   -- after an outgoing !vault or a counter trade (no push)
M.SETTLE_EDIT    = 0.3;   -- after our own write: coalesce a run of edits into one read
M.SETTLE_PUSH    = 0.2;   -- coalesce a burst of pushes into one read
M.SETTLE_LAYOUT  = 0.25;  -- coalesce an inventory burst before reading its layout
M.MAX_LAYOUT_WAIT = 1.0;  -- continuous inventory traffic cannot keep deferring the ask
M.RECHECK_UNATTUNED = 300; -- an un-attuned character re-asks this rarely (one HELLO)
M.LOGIN_ARM      = 0.5;   -- first readiness -> login sync
M.MAX_DEPOSIT    = 62;    -- entries per DEPOSIT: a longer ack does not fit one frame

-- ---------------------------------------------------------------------------
-- Injectable seams (production wiring in init.lua; tests replace)
-- ---------------------------------------------------------------------------
M._clock  = os.clock;
M._send   = nil;    -- function(byteTable) -> boolean; nil = frames go nowhere
M._onFresh = nil;   -- called after every mirror commit (glue: ownedcache reset)
M._onLayout = nil;  -- called after every layout commit (glue: the reconcile kick)
M._onPush  = nil;   -- called with (scope, jobs, cause) after a CHANGED push
M._say     = nil;   -- one-line chat sink (glue: chatfmt); nil = print
M._received = nil;  -- transport.received(op, seq): a frame in our band arrived
M._abandon  = nil;  -- transport.abandon(op, seq): we gave up on that request
M._notePush = nil;  -- transport.notePush(op, why): log a push (never a reply)
M._inCity   = nil;  -- () -> true | false | nil: is this zone a city (the server's predicate)?
M._vaultZone = nil; -- () -> true | false | nil: can the vault change here (a city, or a counter)?
M._onZoneSettled = nil; -- (field) after a zone line, once the new zone's inventory is loaded

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

-- Is bit `b` (a power of two) set in `mask`? Plain arithmetic: the suite runs
-- on Lua 5.4 and the game on LuaJIT, and they share no bit operator.
local function has(mask, b)
    return math.floor((mask or 0) / b) % 2 == 1;
end
M._has = has;

-- HELLO C2S: { u16 Proto; u16 ClientCaps } -- the caps word was reserved
-- (always 0) before 2026-09-30, and servers before then ignore it.
function M.helloPayload()
    return wu16(M.PROTO) .. wu16(M.CLIENT_CAPS);
end

-- A STREAM read asks for several frames in one reply: the classic cursor
-- payload plus { u8 Flags (bit 0 = stream); u8 MaxFrames }. Sent only to a
-- server that advertised STREAM; an older one would read just the cursor.
local function streamTail()
    if M.limits ~= nil and M.limits.stream then
        return string.char(1, M.STREAM_FRAMES);
    end
    return '';
end

function M.listPayload(afterRowId)
    return wu32(afterRowId or 0);
end

-- HELLO S2C: { proto, vaultCount, maxList, maxDeposit, maxWithdraw, caps... } or nil.
-- With SHELF, bytes 20..31 are { u32 GroupId (0 = not in a group); u32
-- VaultRev (the shelf's counter); u32 ShelfCount }. A reply too short for
-- them offers no shelf; the vault fields read as before either way.
function M.parseHello(payload)
    if type(payload) ~= 'string' or #payload < 12 then return nil; end
    local caps = u16(payload, 2);
    local instances = has(caps, M.cap.INSTANCES);
    if instances and #payload < 20 then return nil; end
    local shelfTail = #payload >= 32;
    return {
        shelf      = has(caps, M.cap.SHELF) and shelfTail,
        groupId    = shelfTail and u32(payload, 20) or 0,
        shelfRev   = shelfTail and u32(payload, 24) or nil,
        shelfCount = shelfTail and u32(payload, 28) or nil,
        caps = caps,
        instances = instances, revision = instances and u32(payload, 12) or nil,
        atomicInstanceAdd = instances and has(caps, M.cap.ATOMIC_ADD),
        push   = instances and has(caps, M.cap.PUSH),
        stream = instances and has(caps, M.cap.STREAM),
        expBandStatus = has(caps, M.cap.EXP_BAND_STATUS),
        maxList2 = u8(payload, 16), maxLayoutList2 = u8(payload, 17),
        maxLookup = u8(payload, 18), maxLostList = u8(payload, 19),
        proto       = u16(payload, 0),
        vaultCount  = u32(payload, 4),
        maxList     = u8(payload, 8),
        maxDeposit  = u8(payload, 9),
        maxWithdraw = u8(payload, 10),
    };
end

-- CHANGED S2C push (seq 0): { u16 Scope; u16 Cause; u32 Rev; u32 JobMask;
-- u32 VaultCount; u16 Pulled; u16 Evicted; u32 EventSeq } or nil.
function M.parseChanged(payload)
    if type(payload) ~= 'string' or #payload < 24 then return nil; end
    return {
        scope = u16(payload, 0), cause = u16(payload, 2), revision = u32(payload, 4),
        jobs = u32(payload, 8), vaultCount = u32(payload, 12),
        pulled = u16(payload, 16), evicted = u16(payload, 18), eventSeq = u32(payload, 20),
    };
end

-- Entries per DEPOSIT request: the server's advertised figure, never more
-- than one ack frame can carry (4 + 8 per entry <= 500 bytes -> 62).
function M.depositCap()
    local cap = (M.limits ~= nil and M.limits.maxDeposit) or M.MAX_DEPOSIT;
    return math.max(1, math.min(cap, M.MAX_DEPOSIT));
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
    revision   = nil,    -- the server revision these rows were LISTED at (the probe's baseline)
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
    mirrorGen = 0,       -- bumped by every reason to re-read; a read commits
                         -- "fresh" only when no reason arrived while it ran
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

-- 1..255, never 0: seq 0 belongs to server pushes, so a reply can never be
-- mistaken for one (and a push never for a reply).
local function nextSeq()
    st.seq = (st.seq or 0) % 255 + 1;
    return st.seq;
end

-- Start the seq anywhere (init seeds it per load): a reload that restarted at
-- 1 could re-send an identical write inside the server's replay window.
function M.seedSeq(n)
    st.seq = math.max(0, math.min(254, math.floor(tonumber(n) or 0)));
end

-- Retry policy per op: writes stay inside the replay window, reads wait longer.
-- The Shared Vault's PUT and TAKE are writes too: the server answers a
-- byte-identical retry from its own replay ring for 5 s, and only then.
local WRITE_OPS = nil;
local function isWrite(op)
    WRITE_OPS = WRITE_OPS or { [M.op.DEPOSIT] = true, [M.op.WITHDRAW] = true,
        [M.op.SV_PUT] = true, [M.op.SV_TAKE] = true,
        [M.op.LAYOUT_SET] = true, [M.op.LAYOUT_SET2] = true };
    return WRITE_OPS[op] == true;
end
M._isWrite = isWrite;

-- The Shared Vault's handlers (its section, below the instance protocol).
local shelfWriteLost, shelfReadCut, shelfReadGaveUp, shelfDrain, onShelfReply, onShelfPush, noteShelfHello;
local function timeoutOf(op) return isWrite(op) and M.SEND_TIMEOUT or M.READ_TIMEOUT; end
local function retriesOf(op) return isWrite(op) and M.MAX_RETRIES or M.READ_RETRIES; end

-- Tell the shared transport we will never send this request again (T3).
local function abandon(p)
    if p ~= nil and p.sentAt ~= nil and type(M._abandon) == 'function' then
        pcall(M._abandon, p.op, p.seq);
    end
end

-- A write whose outcome is UNKNOWN (retries spent, or its reply died at a
-- zone line): it may have executed. Never re-send it with a fresh Seq --
-- that is how a lost frame becomes a double op. Report it, and let a full
-- re-read of both views reveal what actually landed.
local function failWrite(p, why)
    st.probeOnly = false;
    if p.op == M.op.SV_PUT or p.op == M.op.SV_TAKE then shelfWriteLost(p, why); return; end
    if p.op == M.op.WITHDRAW or p.op == M.op.DEPOSIT then
        local q = (p.op == M.op.WITHDRAW) and st.withdrawQ or st.depositQ;
        local req = table.remove(q or {}, 1);
        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, nil, 'timeout'); end
        -- the VAULT view first (the rows that may have moved); the layout is
        -- marked stale too, and the mirror's commit kicks the layout engine,
        -- which asks for it
        M.markStale(0, why);
        M.invalidateLayout();
    else
        local req = table.remove(st.layoutSetQ or {}, 1);
        if req and M._audit then pcall(M._audit, 'timeout', req.e, p.seq, 'outcome-unknown'); end
        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, nil, 'timeout'); end
        M.markStale(M.SETTLE_EDIT, why);
        M.invalidateLayout();
        M.requestLayout(0);
    end
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
    st.pending.firstSentAt = st.pending.firstSentAt or now;
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

-- Commit the accumulated LIST pages. `gen` is the mirror generation the read
-- STARTED under: a reason to re-read that arrived while the pages were on the
-- wire (a job change, a push, a !vault) leaves the due time standing, so the
-- read that could not see it is followed by one that can (2026-09-30: a
-- finished read used to wipe such a request -- the job change went unseen).
local function commitMirror(now, gen, revision)
    local rows = st.rowsAcc or {};
    local counts = {};
    for _, r in ipairs(rows) do
        counts[r.itemId] = (counts[r.itemId] or 0) + math.max(1, r.qty);
    end
    local current = (gen == nil) or (gen == st.mirrorGen);
    M.mirror.rows   = rows;
    M.mirror.counts = counts;
    M.mirror.fresh  = current;
    M.mirror.stamp  = now;
    M.mirror.revision = revision;
    st.rowsAcc = nil;
    if current then st.staleAt = nil; end
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
    st.mirrorGen = (st.mirrorGen or 0) + 1;
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
    shelfDrain('not_attuned');
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

-- A reason the SERVER vouched for (a push: "this changed, and it is done"):
-- unlike markStale, which only ever slides the due time later (a debounce),
-- this pulls it EARLIER -- a fallback timer armed by a guess (a chat verb, a
-- counter trade) must not hold back the read the server just asked for.
local function dueSoon(settle, why)
    if st.dormant then return; end
    M.markStale(settle, why);
    local at = M._clock() + (settle or 0);
    if st.staleAt == nil or at < st.staleAt then st.staleAt = at; end
end

-- Can the vault change where we stand? false = the field (hold still), true =
-- a city or a counter zone, nil = unknown (act as if it can -- never guess
-- toward silence).
local function updateHold()
    local v = nil;
    if type(M._vaultZone) == 'function' then
        local ok, r = pcall(M._vaultZone);
        if ok then v = r; end
    end
    st.fieldHold = (v == false);
    return st.fieldHold;
end
function M.fieldHold() return st.fieldHold == true; end

-- Manual refresh (the service verb; also `/dl vault sync`): NOW, over any
-- backoff or settle, and always a full read -- the player asked
-- (2026-09-30: Sync used to wait out a 30 s backoff, and inside the zone-in
-- window it ran as a count-only probe).
function M.refresh()
    st.giveups = 0;
    st.probeOnly = false;
    M.markStale(0, 'manual');
    st.staleAt = M._clock();
end

-- The main-job edge. The server swapped the shelf INSIDE the job-change
-- request, before it sent the job packets that told us (FIFO), so the vault
-- is final by the time we see the new job: read soon, not after a 6 s guess.
-- Fed by pump so headless tests drive it directly.
function M.noteJob(job)
    if type(job) ~= 'number' or job == 0 then return; end
    if st.lastJob ~= nil and job ~= st.lastJob then
        M.invalidateInstances();
        M.cancelLayoutSets('job_changed');
        st.probeOnly = false;   -- a swap can be count-neutral: never a probe
        M.markStale(M.SETTLE_JOB, 'job change');
        st.jobChangedAt = M._clock();
        M.invalidateLayout();   -- the current job's layout is a different job's now
        if st.pending and st.pending.kind == 'layout' and st.pending.sentAt == nil then
            st.pending, st.layoutAcc = nil, nil;
        end
        st.lastJob = job;
        M.requestLayout(0);
        return;
    end
    st.lastJob = job;
end

-- A ZONE LINE CHANGES NOTHING (Henrik, 2026-10-01: "Can dlac cache between
-- zones? Nothing should happen during zoning"). Zoning moves no gear: every
-- view -- the vault rows, the layout, the slot -> copy identities, the lost
-- list -- survives it whole. From the zone-out (0x00B) until the new zone's
-- inventory has finished loading (see noteItemSame; a timeout if that is
-- never seen) the client sends nothing, and the inventory re-send that
-- refills the bags in between is not treated as movement. What COULD change
-- the vault across a zone line -- the server's own zone-in tidy -- arrives as
-- a CHANGED push (the subscription lasts the whole session on a server that
-- offers pushes); against an older server, arriving in a city probes once.
-- Every cached copy identity is still pinned to the revision it was read at,
-- so the first reply that carries a newer revision drops them all.
--
-- A LOGIN is not a zone line. The server sends 0x00B with LogoutState 2
-- (ZONECHANGE) before every zone line and 1 (LOGOUT) before a logout, and
-- nothing at all when the connection is lost -- so a zone-in counts as a
-- zone line only right after a ZONECHANGE. Anything else starts a session:
-- the server dropped the subscription at its game-in, and its login tidy
-- may move copies. The caches still stand (nothing moves while logged out);
-- one probe once the zone is loaded re-subscribes and compares the revision.
M.LOGOUT_ZONECHANGE = 2;   -- 0x00B LogoutState (byte 4) of a zone line

function M.noteZoneOut(state)
    if st.dormant then return; end
    st.zoning = true;
    st.zoneInAt, st.loadRun = nil, nil;
    st.probeAt, st.probeWhy = nil, nil;   -- the next zone decides its own
    st.zoneOutAt = M._clock();
    st.zoneLine = (state == M.LOGOUT_ZONECHANGE);
end

function M.noteZoneIn()
    if st.dormant then return; end
    local now = M._clock();
    local zoneLine = st.zoneLine == true and st.zoneOutAt ~= nil
        and now - st.zoneOutAt <= M.ZONE_LINE_MAX;
    st.zoneLine, st.zoneOutAt = nil, nil;
    st.zoning = true;
    st.zoneInAt, st.loadRun = now, 0;
    st.probeAt, st.probeWhy = nil, nil;
    if not zoneLine then
        st.subscribed = false;   -- the server's game-in forgot it
        st.zoneLogin = true;
    end
    -- a request on the wire across the zone line is lost with the old map
    -- server's entity
    local p = st.pending;
    if p ~= nil and p.sentAt ~= nil then
        if isWrite(p.op) then
            -- the reply died with the old zone; the ring there cannot answer a
            -- retry here -- the outcome is unknown, so report and re-read
            st.pending = nil;
            abandon(p);
            failWrite(p, 'write lost at a zone line');
        else
            st.pending = nil;
            abandon(p);
            st.rowsAcc, st.layoutAcc, st.lostAcc = nil, nil, nil;
            if p.kind == 'layout' then st.layoutWant = { job = 0 }; end
            if p.kind == 'lookup' and st.lookupQ and st.lookupQ[1] then st.lookupQ[1].attempts = 0; end
            if p.kind == 'lost' then st.lostWant = true; end
            if p.kind == 'sync-hello' or p.kind == 'sync-list' then st.zoneFull = true; end
            if p.kind == 'shelf-list' or p.kind == 'shelf-members' then shelfReadCut(p); end
        end
    end
end

-- A cheap check (HELLO: the count and the revision) in `settle` seconds.
-- Until it leaves, the rows stay fresh: it is a glance, not a doubt. A probe
-- never downgrades a full read: one owed NOW answers an immediate probe,
-- and a scheduled one (timed to follow the server's tidy) waits for it.
local function probeSoon(settle, why)
    if (settle or 0) > 0 then
        st.probeAt, st.probeWhy = M._clock() + settle, why;
        return;
    end
    if st.staleAt ~= nil and not st.probeOnly then return; end
    st.probeAt, st.probeWhy = nil, nil;
    M.markStale(0, why);
    st.probeOnly = true;
end

-- The bags hold the zone-in re-send now. The server's tidy can move a piece
-- while the zone still loads, and its packets were ignored with the re-send:
-- a pinned copy whose slot no longer holds its item is forgotten -- locally,
-- no traffic (a same-item swap moves the revision, which drops them all).
local function checkIdentities()
    if type(M._readSlot) ~= 'function' or st.instanceCache == nil then return; end
    local dropped = false;
    for key, e in pairs(st.instanceCache) do
        local ok, id = pcall(M._readSlot, e.container, e.slot);
        if not ok or id ~= e.itemId then st.instanceCache[key] = nil; dropped = true; end
    end
    if dropped then st.inventoryEpoch = (st.inventoryEpoch or 0) + 1; end
end

-- The zone is ours: the inventory finished loading (or the wait timed out).
local function zoneSettled(now)
    st.zoning = false;
    st.zoneInAt, st.loadRun = nil, nil;
    local cut, login = st.zoneFull == true, st.zoneLogin == true;
    st.zoneFull, st.zoneLogin = nil, nil;
    -- a session start, or a renewal a zone line cut short: the server
    -- pushes, but not to us
    local renew = login or (M.limits ~= nil and M.limits.push == true and not st.subscribed);
    local field = updateHold();
    checkIdentities();
    if cut then
        M.markStale(0, 'a read cut by the zone line');   -- finish what was asked, wherever we stand
        st.probeOnly = false;
    elseif st.unattuned then
        -- The Deeper Room is finished in a city: there, ask now instead of in
        -- five minutes (the server's ATTUNE push makes this moot when it lands;
        -- a login asks wherever it stands, which renews that push)
        if renew or not field then st.staleAt = math.min(st.staleAt or now, now); end
    elseif renew then
        -- wherever we stand: renew the subscription. A server that pushes
        -- reports its login tidy when that runs; one that cannot is probed
        -- after it.
        probeSoon((M.limits ~= nil and M.limits.push) and 0 or M.SETTLE_TIDY, login and 'login' or 'renew');
    elseif not field and not M.live() then
        -- a server without pushes cannot tell us about its zone-in tidy:
        -- one cheap probe once that has run
        probeSoon(M.SETTLE_TIDY, 'zone-in');
    end
    -- A login also asks for the layout once: an edit made while we were away
    -- (a GM, the website) moves no copy, so the revision need not show it.
    if login and not st.unattuned then M.invalidateLayout(); end
    if type(M._onZoneSettled) == 'function' then pcall(M._onZoneSettled, field); end
end

-- 0x01D (ITEM_SAME); byte 4 = State: 0 StillLoading (names one container),
-- 1 AllLoaded. The re-send after a zone-in names every container in one run
-- and then says AllLoaded; every other sender -- the vault's own tidy, a
-- swap's flush -- names ONE container per AllLoaded, and the server's
-- zone-in tidy can fire while the new zone is still loading. So the zone
-- line is over at the first AllLoaded after a run of two or more. Before
-- the zone-in nothing counts (a refresh at the old zone).
function M.noteItemSame(state)
    if not st.zoning or st.zoneInAt == nil then return; end
    if state == 0 then st.loadRun = (st.loadRun or 0) + 1; return; end
    if state ~= 1 then return; end
    local run = st.loadRun or 0;
    st.loadRun = 0;
    if run >= 2 then zoneSettled(M._clock()); end
end
function M.zoning() return st.zoning == true; end

function M.noteVaultChat()
    -- An outgoing `!vault ...` may mutate the store OR a layout; resync after
    -- it lands (a push, when negotiated, pulls this earlier).
    M.markStale(M.SETTLE_CHAT, 'chat');
    M.invalidateLayout();
    st.probeOnly = false;
end

-- A trade to a Gear Vault counter (the NPC's own suggestion: "trade it
-- gear"). The server deposits one tick later and applies what the layout
-- names; nothing about it arrives on 0x1E0 -- before pushes, dlac never
-- noticed until a zone or a manual Sync (2026-09-30 audit, bug 1).
function M.noteCounterTrade()
    M.markStale(M.SETTLE_CHAT, 'counter trade');
    M.invalidateLayout();
    st.probeOnly = false;
    st.fieldHold = false;
end

-- An inventory packet's slot facts: container, slot, item id (nil for
-- 0x01E, which carries none), quantity -- or nil for anything else.
function M.parseItemPacket(id, data)
    if type(data) ~= 'string' then return nil; end
    if id == 0x020 and #data >= 17 then
        return u8(data, 14), u8(data, 15), u16(data, 12), u32(data, 4);
    elseif id == 0x01F and #data >= 13 then
        return u8(data, 10), u8(data, 11), u16(data, 8), u32(data, 4);
    elseif id == 0x01E and #data >= 11 then
        return u8(data, 8), u8(data, 9), nil, u32(data, 4);
    end
    return nil;
end

local function layoutNames(itemId)
    if itemId == nil or itemId == 0 then return false; end
    local ids = M.layoutCache.ids;
    -- the id set is only trusted for the entries it was built from
    if ids ~= nil and M.layoutCache.idsOf == M.layoutCache.entries then return ids[itemId] == true; end
    for _, e in ipairs(M.layoutCache.entries or {}) do
        if e.itemId == itemId then return true; end
    end
    return false;
end

-- An inbound inventory packet, seen in packet_in BEFORE the client applies
-- it -- so the bag memory still shows the slot's OLD item. The field logs
-- (2026-09-30) put 34-58 % of all vault requests on the old rule, "any of
-- 0x01D-0x020 invalidates every slot and the layout": every gear swap sends
-- 0x01F to flip a lock flag, so combat re-read the layout, the lost list and
-- the worn slots on every 8 s beat. Now only a slot whose ITEM changed
-- forgets its copy, and only a move of an item the layout names re-reads the
-- layout -- in a city (out in the field the vault's side cannot move).
-- Returns true when the packet changed anything we track.
function M.noteInventory(id, data)
    -- the zone-in re-send refills the bags with what was there: no movement
    if st.zoning then return false; end
    local cid, slot, newId, qty = M.parseItemPacket(id, data);
    if cid == nil then return false; end
    local oldId = nil;
    if type(M._readSlot) == 'function' then
        local ok, v = pcall(M._readSlot, cid, slot);
        if ok then oldId = v; end
    end
    if id == 0x01F and newId ~= nil and oldId ~= nil and newId == oldId then
        return false;   -- a lock flag (equip / unequip) or a count: same item, same copy
    end
    if id == 0x01E then
        if (qty or 0) > 0 then return false; end   -- a stack count moved; the copy did not
        newId = 0;
    end
    local key = tostring(cid) .. ':' .. tostring(slot);
    if st.instanceCache ~= nil then st.instanceCache[key] = nil; end
    st.inventoryEpoch = (st.inventoryEpoch or 0) + 1;
    st.lookupAfter = (st.beat or 0) + 2;
    if M.instanceMode() and not st.fieldHold and (layoutNames(oldId) or layoutNames(newId)) then
        M.invalidateLayout(M.SETTLE_LAYOUT);
    end
    -- belt and braces for a swap stream that trails the job packets
    if st.jobChangedAt ~= nil and M._clock() - st.jobChangedAt < 10 then
        M.markStale(M.SETTLE_JOB, 'swap stream');
    end
    return true;
end

-- A different character logged in without an addon reload: nothing we hold
-- belongs to them (2026-09-30 audit, bug 10). Keeps the seams and the seq.
function M.resetCharacter()
    local seq = st.seq;
    M._reset();
    st.seq = seq;
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
    -- Never more than one ack frame can carry: the server advertised 124,
    -- but an ack past 62 entries does not fit 500 bytes, and the whole reply
    -- vanished while every deposit committed (2026-09-30 server audit).
    -- Callers split longer runs (vaultui.storeRows).
    if #entries > M.depositCap() then return false; end
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
    -- A new batch may start from the last KNOWN views of this job, not only
    -- from freshly re-read ones: a re-read in flight is not a reason to grey
    -- out every Add button (the server still validates each add). An open
    -- batch keeps its own snapshot and validity rules.
    local known = M.layoutCache.stamp ~= nil and M.layoutCache.job ~= nil
        and (st.lastJob == nil or M.layoutCache.job == st.lastJob) and M.mirror.stamp ~= nil;
    return {
        ready = not st.dormant and not st.unattuned and
            ((batch ~= nil and batch.valid) or
             (batch == nil and known and not M.layoutBusy())),
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
    -- any lookup SNAPSHOT (noteInventory reads only a slot's OLD item there).
    st.lookupAfter = (st.beat or 0) + 2;
end

function M.noteRevision(revision)
    if revision ~= nil and revision ~= M.revision then
        M.revision = revision;
        M.invalidateInstances();
    end
end

-- The lost list is the server's registry, and a loss moves the revision --
-- so the revision alone says when to re-read it. It used to key on the
-- client's inventory epoch too, which every gear swap bumped: 2,070 LOST
-- pages in the field logs, 79 % of them straight after a layout read.
function M.requestLost()
    if not M.instanceMode() then return false; end
    if M.lost.fresh and M.lost.revision == M.revision then return true; end
    local p = st.pending;
    if p and p.kind == 'lost' and p.lostRevision == M.revision then return true; end
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
-- THE SHARED VAULT (Group Ironman; server group_ironman_vault.lua, wire in
-- the ascensionxi repo's group-ironman-implementation.md, "The Shared Vault
-- (DLAC)"). A group's shelf of gear beside every member's own vault, in this
-- band's 0x60-0x6F. Offered when HELLO sets SHELF; shown only while the
-- character is in a group: HELLO's GroupId, or the last SV_CHANGED's InGroup
-- (decision S12 rule 7).
--
--   * It rides THIS client: one request in flight, the same gate and pacing.
--     PUT and TAKE are writes (isWrite): a retry keeps its seq inside the
--     server's replay window, and a lost answer is outcome unknown -- both
--     stores are re-read, the write is never re-sent with a fresh seq.
--   * One write at a time (S12 rule 8: one piece per click).
--   * The shelf is read when its tab opens and when the server says it moved
--     (an SV_CHANGED, a HELLO tail, our own write's answer) -- only while the
--     tab is open (S9), only when the Rev differs from the last read's, and
--     never on a clock.
--   * A shelf answer never changes the vault's own state: a refusal, a
--     timeout or an unreadable page costs the shelf, never the vault.
-- ---------------------------------------------------------------------------
M.SHELF_LIST_MAX    = 12;   -- 40-byte rows after an 8-byte header
M.SHELF_MEMBERS_MAX = 20;   -- 24-byte rows after a 12-byte header
M.SHELF_VIEW_GAP    = 1.0;  -- a Shared Vault tab not drawn for this long was closed

-- GroupIronmanCode: the per-move result word (u16 on the wire).
M.giCode =
{
    OK = 0, NOT_IN_GROUP = 1, EVER_GROUPED = 2, TOO_OLD = 3, NO_INVITE = 4, SAME_ACCOUNT = 5,
    NOT_IN_LEADERS_PARTY = 6, LEADER_OFFLINE = 7, GROUP_FULL = 8, NOT_LEADER = 9, NOT_A_MEMBER = 10,
    LEADER_PRESENT = 11, BUSY = 12, STORE_ERROR = 13, CLOSED = 14, SELF = 15, UNKNOWN_CHARACTER = 16,
    STAYS_WITH_YOU = 17, SHELF_CAP = 18, RARE_IN_STORE = 19, NEEDS_CONFIRM = 20, NOT_ELIGIBLE = 21,
    NO_ROW = 22, RARE_HELD = 23, DUPLICATE = 24, ITEM_BUSY = 25, TIER_LOCKED = 26, NOT_STORABLE = 27,
    NO_BALANCE = 28, INVENTORY_FULL = 29, NO_SEAL = 30, SCROLL_HELD = 31, ALREADY_INVITED = 32,
    ALREADY_MEMBER = 33, NOTHING_TO_DO = 34, PARTIAL = 35,
};

-- SV_LIST C2S: { u32 AfterRowId } + the stream tail. S2C frame: { u16 Count;
-- u16 Rsvd; u32 Rev; Count x 40: u32 RowId; u16 ItemNo; u16 Rsvd; u32
-- InstanceId; u32 SharedBy (a charid); u8 IdentityExtra[24] (the normalized
-- blob LIST2 sends) }. A truncated frame is refused whole.
function M.parseShelfList(payload)
    if type(payload) ~= 'string' or #payload < 8 then return nil; end
    local n = u16(payload, 0);
    if n > M.SHELF_LIST_MAX or #payload < 8 + n * 40 then return nil; end
    local out = { entries = {}, revision = u32(payload, 4) };
    for i = 0, n - 1 do
        local o = 8 + i * 40;
        out.entries[#out.entries + 1] = { rowId = u32(payload, o), itemId = u16(payload, o + 4),
            instanceId = u32(payload, o + 8), sharedBy = u32(payload, o + 12), identity = payload:sub(o + 17, o + 40) };
    end
    return out;
end

-- SV_PUT C2S: { u32 VaultRowId; u8 Container; u8 Slot; u8 Flags (bit 0 =
-- confirm); u8 Rsvd }. VaultRowId 0 names an unworn wardrobe piece by
-- (Container, Slot).
function M.shelfPutPayload(e)
    return wu32(e.vaultRowId or 0)
        .. string.char((e.container or 0) % 256, (e.slot or 0) % 256, e.confirm and 1 or 0, 0);
end

-- SV_PUT S2C: { u16 Code; u8 JobCount; u8 Wardrobe; u32 ShelfRowId; u32 Rev;
-- JobCount x u8 Job }. NEEDS_CONFIRM names the job layouts that hold the
-- piece; Wardrobe = 1 marks a wardrobe piece, which always asks once.
function M.parseShelfPutAck(payload)
    if type(payload) ~= 'string' or #payload < 12 then return nil; end
    local n = u8(payload, 2);
    if #payload < 12 + n then return nil; end
    local out = { code = u16(payload, 0), wardrobe = u8(payload, 3) ~= 0,
        shelfRowId = u32(payload, 4), revision = u32(payload, 8), jobs = {} };
    for i = 0, n - 1 do out.jobs[#out.jobs + 1] = u8(payload, 12 + i); end
    return out;
end

-- SV_TAKE C2S: { u32 ShelfRowId }. S2C: { u16 Code; u16 Rsvd; u32 VaultRowId; u32 Rev }.
function M.shelfTakePayload(shelfRowId) return wu32(shelfRowId or 0); end

function M.parseShelfTakeAck(payload)
    if type(payload) ~= 'string' or #payload < 12 then return nil; end
    return { code = u16(payload, 0), vaultRowId = u32(payload, 4), revision = u32(payload, 8) };
end

-- SV_MEMBERS S2C: { u16 Count; u16 Rsvd; u32 GroupId; u32 Leader; Count x 24:
-- u32 CharId; u8 Flags (bit 0 active, 1 leader, 2 online); u8 Rsvd[3]; char
-- Name[16] (zero-padded) }. Members who left are listed too, not active.
function M.parseShelfMembers(payload)
    if type(payload) ~= 'string' or #payload < 12 then return nil; end
    local n = u16(payload, 0);
    if n > M.SHELF_MEMBERS_MAX or #payload < 12 + n * 24 then return nil; end
    local out = { groupId = u32(payload, 4), leader = u32(payload, 8), members = {} };
    for i = 0, n - 1 do
        local o = 12 + i * 24;
        local flags = u8(payload, o + 4);
        local name = payload:sub(o + 9, o + 24);
        local z = name:find('\0', 1, true);
        if z ~= nil then name = name:sub(1, z - 1); end
        out.members[#out.members + 1] = { charId = u32(payload, o), name = name,
            active = has(flags, 1), leader = has(flags, 2), online = has(flags, 4) };
    end
    return out;
end

-- SV_CHANGED S2C push (seq 0): { u32 Rev; u32 ShelfCount; u8 InGroup; u8
-- Rsvd[3]; u32 GroupId }.
function M.parseShelfChanged(payload)
    if type(payload) ~= 'string' or #payload < 16 then return nil; end
    return { revision = u32(payload, 0), count = u32(payload, 4),
        inGroup = u8(payload, 8) ~= 0, groupId = u32(payload, 12) };
end

-- What the tab reads. rows: { rowId, itemId, instanceId, sharedBy, identity }
-- in RowId order; readRev: the Rev those rows were read at (nil = never read,
-- or no longer trusted); names: charid -> name, from SV_MEMBERS.
local function emptyShelf()
    return { rows = {}, stamp = nil, readRev = nil, count = nil,
             members = {}, names = {}, leader = nil, membersStamp = nil };
end
M.shelf = emptyShelf();

-- The tab draws itself only while this says so (S12 rule 7).
function M.shelfAvailable()
    return not st.dormant and not st.unattuned and not st.svOff and M.limits ~= nil
        and M.limits.shelf == true and (st.svGroupId or 0) ~= 0;
end

local function shelfOpen(now)
    return st.svViewAt ~= nil and (now or M._clock()) - st.svViewAt <= M.SHELF_VIEW_GAP;
end
function M.shelfOpen() return shelfOpen(M._clock()); end

-- The tab calls this on every frame it draws. Opening it reads the member
-- list and the shelf (S9: on open, never on a clock). Returns true on the
-- frame it opened.
function M.noteShelfView()
    local now = M._clock();
    local opened = not shelfOpen(now);
    st.svViewAt = now;
    if opened and M.shelfAvailable() then
        st.svMembersWant = true;
        st.svListWant = true;
    end
    return opened;
end

local function shelfForget()
    M.shelf = emptyShelf();
    st.svAcc, st.svAccRev, st.svListWant, st.svMembersWant = nil, nil, nil, nil;
    st.svKnownRev, st.svFailed, st.svNamesFor = nil, nil, nil;
end

-- Queued shelf writes that have not left never will; the one on the wire
-- still answers. onDone hears `why`.
local function shelfCancelQueued(why)
    local q = st.shelfWriteQ or {};
    local p = st.pending;
    local keepFirst = false;
    if p ~= nil and (p.op == M.op.SV_PUT or p.op == M.op.SV_TAKE) then
        if p.sentAt ~= nil then keepFirst = true; else st.pending = nil; end
    end
    st.shelfWriteQ = keepFirst and { q[1] } or {};
    for i = (keepFirst and 2 or 1), #q do
        if type(q[i].onDone) == 'function' then pcall(q[i].onDone, nil, why); end
    end
end

function shelfDrain(why)
    shelfCancelQueued(why);
    shelfForget();
end

-- The server says the shelf is at `rev`. Re-read only if that differs from
-- the last read's Rev, and only while the tab is open (the next open reads
-- anyway). While a read is on the wire its answer decides instead: it may
-- already show this Rev, or a later one (see the SV_LIST commit).
local function noteShelfRev(rev, now)
    st.svKnownRev = rev;
    st.svNoteGen = (st.svNoteGen or 0) + 1;
    if st.pending ~= nil and st.pending.kind == 'shelf-list' then return; end
    if shelfOpen(now) and M.shelf.readRev ~= rev then st.svListWant = true; end
end

-- Our view may be wrong (a write whose outcome is unknown, an answer that
-- says the row is gone): distrust it until the next read -- now, if the tab
-- is open.
local function shelfDoubt(now)
    M.shelf.readRev = nil;
    st.svKnownRev = nil;
    st.svNoteGen = (st.svNoteGen or 0) + 1;
    if shelfOpen(now) then st.svListWant = true; end
end

-- Where the server says the character stands: in group `groupId` (0 = in
-- none), its shelf at `rev` holding `count`. Leaving hides the tab and
-- forgets the shelf; a different group's shelf is not this one.
local function setShelfGroup(groupId, rev, count, now)
    groupId = groupId or 0;
    local was = st.svGroupId or 0;
    if groupId == 0 then
        st.svGroupId = 0;
        if was ~= 0 then shelfCancelQueued('not_in_group'); shelfForget(); end
        return;
    end
    if was ~= 0 and was ~= groupId then shelfForget(); end
    st.svGroupId = groupId;
    if count ~= nil then M.shelf.count = count; end
    if was ~= groupId and shelfOpen(now) then st.svMembersWant = true; end
    if rev ~= nil then noteShelfRev(rev, now); end
end

function noteShelfHello(h, now)
    if h.shelf then
        setShelfGroup(h.groupId, h.shelfRev, h.shelfCount, now);
    elseif (st.svGroupId or 0) ~= 0 then
        setShelfGroup(0, nil, nil, now);   -- this server offers no shelf (any more)
    end
end

-- SV_CHANGED. T2: never a reply, so it never touches the transport's
-- pending slot. Sent when the shelf moved past what this session was told,
-- when the character's group membership changed (InGroup 0: hide the tab),
-- and once after the character reaches a map process (a zone line, a login),
-- which does not know what the session was told. Its Rev is always the
-- shelf's current one.
function onShelfPush(f, now)
    if type(M._notePush) == 'function' then pcall(M._notePush, f.op, 'shared vault push'); end
    local c = (f.status == M.status.OK) and M.parseShelfChanged(f.payload) or nil;
    if c == nil then
        noteWhy('ate an unreadable Shared Vault push', now);
        return true;
    end
    st.svLastPush = { at = now, revision = c.revision, inGroup = c.inGroup };
    if st.dormant or st.unattuned or st.svOff then return true; end
    setShelfGroup(c.inGroup and c.groupId or 0, c.revision, c.count, now);
    return true;
end

-- One write at a time.
function M.shelfBusy() return #(st.shelfWriteQ or {}) > 0; end

-- For the tab's header: a read on its way, or the last one went unanswered.
function M.shelfReading()
    local k = st.pending and st.pending.kind;
    return k == 'shelf-list' or st.svListWant == true;
end
function M.shelfFailed() return st.svFailed == true; end

-- Share ONE piece: e = { vaultRowId = <own vault row>, itemId } or, for an
-- unworn piece in a Mog Wardrobe, { container, slot, itemId }. confirm =
-- true only on the resend after NEEDS_CONFIRM, once the player agreed.
-- onDone(ack, err) fires once: ack is parseShelfPutAck's table (its code a
-- GroupIronmanCode), or nil with err = 'too_far' | 'not_attuned' | 'busy' |
-- 'unavailable' | 'malformed' | 'timeout' | 'not_in_group' | ...
function M.requestShelfPut(e, onDone)
    if not M.shelfAvailable() or M.shelfBusy() or type(e) ~= 'table' then return false; end
    local rowId = math.max(0, math.floor(tonumber(e.vaultRowId) or 0));
    local container, slot = tonumber(e.container), tonumber(e.slot);
    if rowId == 0 and (container == nil or slot == nil) then return false; end
    st.shelfWriteQ = { {
        kind = 'shelf-put', op = M.op.SV_PUT, vaultRowId = rowId, itemId = e.itemId, onDone = onDone,
        payload = M.shelfPutPayload({ vaultRowId = rowId, container = (rowId == 0) and container or 0,
            slot = (rowId == 0) and slot or 0, confirm = e.confirm == true }),
    } };
    return true;
end

-- Take ONE piece from the shelf into the own vault: e = { shelfRowId, itemId }.
-- onDone(ack, err) as for a share (ack = parseShelfTakeAck's table).
function M.requestShelfTake(e, onDone)
    if not M.shelfAvailable() or M.shelfBusy() or type(e) ~= 'table' then return false; end
    local rowId = math.floor(tonumber(e.shelfRowId) or 0);
    if rowId <= 0 then return false; end
    st.shelfWriteQ = { {
        kind = 'shelf-take', op = M.op.SV_TAKE, shelfRowId = rowId, itemId = e.itemId, onDone = onDone,
        payload = M.shelfTakePayload(rowId),
    } };
    return true;
end

-- A row the server deleted: gone from the vault now (a withdraw's
-- subtraction; the re-read follows).
local function dropMirrorRow(rowId)
    for i, row in ipairs(M.mirror.rows) do
        if row.rowId == rowId then
            table.remove(M.mirror.rows, i);
            local counts = {};
            for _, r in ipairs(M.mirror.rows) do
                counts[r.itemId] = (counts[r.itemId] or 0) + math.max(1, r.qty);
            end
            M.mirror.counts = counts;
            M.mirror.vaultCount = #M.mirror.rows;
            M.mirror.stamp = M._clock();
            if type(M._onFresh) == 'function' then pcall(M._onFresh); end
            return true;
        end
    end
    return false;
end

local function dropShelfRow(rowId, now)
    for i, row in ipairs(M.shelf.rows) do
        if row.rowId == rowId then
            table.remove(M.shelf.rows, i);
            M.shelf.count = #M.shelf.rows;
            M.shelf.stamp = now;
            return true;
        end
    end
    return false;
end

-- A write whose answer never came (retries spent, or it died at a zone
-- line): it may have run. Both stores are re-read; it is never re-sent.
function shelfWriteLost(p, why)
    local req = table.remove(st.shelfWriteQ or {}, 1);
    if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, nil, 'timeout'); end
    M.markStale(0, why);
    M.invalidateLayout();   -- a confirmed share leaves the job layouts that named it
    shelfDoubt(M._clock());
end

-- A read whose answer never came: the tab says so, and the next open or
-- SV_CHANGED asks again (no retry on a clock).
function shelfReadGaveUp(p, now)
    noteWhy(string.format('%s (%s#%d) timed out: no reply after %d retries',
        p.kind, opName(p.op), p.seq, retriesOf(p.op)), now);
    if p.op == M.op.SV_LIST then st.svAcc, st.svAccRev = nil, nil; end
    st.svFailed = true;
end

-- A read on the wire at a zone line: asked again once the zone is ours, if
-- the tab is still open then.
function shelfReadCut(p)
    if p.op == M.op.SV_LIST then st.svAcc, st.svAccRev = nil, nil; st.svListWant = true; end
    if p.op == M.op.SV_MEMBERS then st.svMembersWant = true; end
end

local SHELF_STATUS_WORD = {
    [M.status.TOO_FAR] = 'too_far', [M.status.NOT_ATTUNED] = 'not_attuned',
    [M.status.BUSY] = 'busy', [M.status.MALFORMED] = 'malformed',
};

-- An unreadable answer to a write cannot prove nothing moved.
local function shelfWriteUnreadable(req, now)
    M.markStale(0, 'shared vault: unreadable write answer');
    st.probeOnly = false;
    M.invalidateLayout();
    shelfDoubt(now);
    if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, nil, 'malformed'); end
end

-- The answer to the pending Shared Vault request.
function onShelfReply(p, f, now)
    local write = (p.op == M.op.SV_PUT or p.op == M.op.SV_TAKE);
    if f.status ~= M.status.OK then
        st.pending = nil;
        noteWhy(string.format('%s (%s#%d) refused: %s', p.kind, opName(p.op), p.seq, statusName(f.status)), now);
        if f.status == M.status.BAD_OP or f.status == M.status.PROTO_UNSUPPORTED then
            st.svOff = true;   -- this server cannot serve the shelf after all: hidden for the session
        end
        if p.op == M.op.SV_LIST then st.svAcc, st.svAccRev = nil, nil; st.svFailed = true; end
        if write then
            local req = table.remove(st.shelfWriteQ or {}, 1);
            -- TOO_FAR, NOT_ATTUNED and MALFORMED are decided before anything
            -- moves. Anything else can follow a move that ran (the server's
            -- handler failed after it): re-read both stores.
            if f.status ~= M.status.TOO_FAR and f.status ~= M.status.NOT_ATTUNED and f.status ~= M.status.MALFORMED then
                M.markStale(0, 'shared vault write refused');
                st.probeOnly = false;
                M.invalidateLayout();
                shelfDoubt(now);
            end
            if req ~= nil and type(req.onDone) == 'function' then
                pcall(req.onDone, nil, SHELF_STATUS_WORD[f.status] or 'unavailable');
            end
        end
        if st.svOff then shelfDrain('unavailable'); end
        return true;
    end

    if p.op == M.op.SV_MEMBERS then
        st.pending = nil;
        local m = M.parseShelfMembers(f.payload);
        if m == nil then noteWhy('the Shared Vault member list did not parse', now); return true; end
        if p.svGroup ~= st.svGroupId then return true; end   -- the group changed meanwhile
        if m.groupId == 0 then setShelfGroup(0, nil, nil, now); return true; end   -- in no group after all
        local names = {};
        for _, e in ipairs(m.members) do names[e.charId] = e.name; end
        M.shelf.members, M.shelf.names, M.shelf.leader, M.shelf.membersStamp = m.members, names, m.leader, now;
        return true;
    end

    if p.op == M.op.SV_LIST then
        -- the vault's list shape: rows in ascending RowId, MORE = ask again
        -- past the last one, FOLLOWS = another frame of this reply is on its
        -- way; a retried request's duplicate rows are skipped by key
        local chunk = M.parseShelfList(f.payload);
        if chunk == nil or p.svGroup ~= st.svGroupId then
            st.pending = nil;
            st.svAcc, st.svAccRev = nil, nil;
            if chunk == nil then st.svFailed = true; noteWhy('a Shared Vault page did not parse', now); end
            return true;
        end
        if st.svAccRev ~= nil and st.svAccRev ~= chunk.revision then
            -- the shelf moved between our pages: read it again from the top
            st.pending = nil;
            st.svAcc, st.svAccRev = nil, nil;
            if shelfOpen(now) then st.svListWant = true; end
            return true;
        end
        st.svAccRev = chunk.revision;
        st.svAcc = st.svAcc or {};
        local accLast = p.accLast or p.cursor or 0;
        for _, e in ipairs(chunk.entries) do
            if e.rowId > accLast then st.svAcc[#st.svAcc + 1] = e; accLast = e.rowId; end
        end
        p.accLast = accLast;
        if has(f.flags, M.FLAG_FOLLOWS) then p.sentAt = now; return true; end
        st.pending = nil;
        if has(f.flags, M.FLAG_MORE) then
            if accLast <= (p.cursor or 0) then st.svAcc, st.svAccRev = nil, nil; return true; end
            beginOp('shelf-list', M.op.SV_LIST, wu32(accLast) .. streamTail(), now, accLast);
            st.pending.svGroup, st.pending.svGen = p.svGroup, p.svGen;
            return true;
        end
        M.shelf.rows = st.svAcc;
        M.shelf.readRev = st.svAccRev;
        M.shelf.count = #st.svAcc;
        M.shelf.stamp = now;
        st.svAcc, st.svAccRev, st.svFailed = nil, nil, nil;
        -- A Rev announced while the pages were on the wire: read once more
        -- only if it is NEWER than this answer (the counter only grows). The
        -- same Rev, or an older one the read already overtook, is covered.
        if st.svNoteGen ~= p.svGen and st.svKnownRev ~= nil and st.svKnownRev > M.shelf.readRev
            and shelfOpen(now) then
            st.svListWant = true;
        end
        -- a sharer the member list cannot name joined after it was read
        for _, r in ipairs(M.shelf.rows) do
            if (r.sharedBy or 0) ~= 0 and M.shelf.names[r.sharedBy] == nil then
                if st.svNamesFor ~= M.shelf.readRev and shelfOpen(now) then
                    st.svNamesFor = M.shelf.readRev;
                    st.svMembersWant = true;
                end
                break;
            end
        end
        return true;
    end

    if p.op == M.op.SV_PUT then
        st.pending = nil;
        local req = table.remove(st.shelfWriteQ or {}, 1);
        local ack = M.parseShelfPutAck(f.payload);
        if ack == nil then shelfWriteUnreadable(req, now); return true; end
        if ack.code == M.giCode.OK then
            -- the server deleted that vault row: gone now, and the vault is
            -- read again (it may have left a wardrobe, and the job layouts
            -- that named it)
            if req ~= nil and (req.vaultRowId or 0) > 0 then dropMirrorRow(req.vaultRowId); end
            M.markStale(M.SETTLE_EDIT, 'shared a piece');
            st.probeOnly = false;
            if #ack.jobs > 0 or ack.wardrobe then M.invalidateLayout(); end
            noteShelfRev(ack.revision, now);   -- the shelf holds a row we have not read
        elseif ack.code == M.giCode.NO_ROW then
            M.markStale(0, 'shared vault: that vault row was gone');
            st.probeOnly = false;
        elseif ack.code == M.giCode.NOT_IN_GROUP then
            setShelfGroup(0, nil, nil, now);
        end
        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, ack, nil); end
        return true;
    end

    if p.op == M.op.SV_TAKE then
        st.pending = nil;
        local req = table.remove(st.shelfWriteQ or {}, 1);
        local ack = M.parseShelfTakeAck(f.payload);
        if ack == nil then shelfWriteUnreadable(req, now); return true; end
        if ack.code == M.giCode.OK then
            -- a new row of our own vault: one LIST folds it in (a deposit's
            -- rule), and the server may move it on to a wardrobe when a
            -- layout names it -- the layout shows where each copy is
            M.markStale(M.SETTLE_EDIT, 'took a piece');
            st.probeOnly = false;
            if req ~= nil and layoutNames(req.itemId) then M.invalidateLayout(); end
            -- the shelf lost exactly this row: when nothing else moved since
            -- our read, what we hold IS the shelf at the new Rev
            local held = M.shelf.readRev;
            if req ~= nil and dropShelfRow(req.shelfRowId, now) and held ~= nil and ack.revision == held + 1 then
                M.shelf.readRev = ack.revision;
            end
            noteShelfRev(ack.revision, now);
        elseif ack.code == M.giCode.NO_ROW then
            shelfDoubt(now);   -- someone took it first: our shelf is out of date
        elseif ack.code == M.giCode.NOT_IN_GROUP then
            setShelfGroup(0, nil, nil, now);
        end
        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, ack, nil); end
        return true;
    end

    st.pending = nil;
    return true;
end

-- /dl vault's shelf line: nil when this server offers no shelf.
function M.shelfStatusLine()
    if M.limits == nil or not M.limits.shelf then return nil; end
    if st.svOff then return 'shared vault: this server refused it -- hidden for the session.'; end
    if (st.svGroupId or 0) == 0 then
        return 'shared vault: offered, but this character is in no group -- the tab stays hidden.';
    end
    local n = #(M.shelf.rows or {});
    local read = (M.shelf.stamp ~= nil)
        and string.format('%d piece%s read at revision %s', n, (n == 1) and '' or 's', tostring(M.shelf.readRev))
        or 'not read yet (it reads when its tab opens)';
    local behind = (st.svKnownRev ~= nil and st.svKnownRev ~= M.shelf.readRev)
        and (', the server is at revision ' .. tostring(st.svKnownRev)) or '';
    local push = (st.svLastPush ~= nil)
        and string.format(' -- last push %ds ago', math.max(0, math.floor(M._clock() - st.svLastPush.at))) or '';
    return string.format('shared vault: group %d -- %s%s%s%s.', st.svGroupId, read, behind, push,
        st.svFailed and ' -- the last read failed' or '');
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
    -- no zone-in packet will ever arrive): arm the login sync -- wherever we
    -- stand, since ownership reads the mirror in the field too.
    if M.mirror.stamp == nil and st.staleAt == nil and st.pending == nil then
        st.staleAt = now + M.LOGIN_ARM;
        updateHold();
    end
    -- Nothing leaves while zoning: from the zone-out until the new zone's
    -- inventory is loaded (or the wait times out). Asks made meanwhile wait.
    if st.zoning then
        if st.zoneInAt ~= nil and now - st.zoneInAt >= M.ZONE_LOAD_TIMEOUT then
            zoneSettled(now);
        else
            return;
        end
    end
    if st.probeAt ~= nil and now >= st.probeAt then probeSoon(0, st.probeWhy); end

    if st.pending ~= nil then
        local p = st.pending;
        if p.sentAt == nil then sendPending(now); return; end
        if now - p.sentAt >= timeoutOf(p.op) then
            local late = isWrite(p.op) and now - (p.firstSentAt or p.sentAt) >= M.WRITE_DEADLINE;
            if p.retries >= retriesOf(p.op) or late then
                st.pending = nil;
                abandon(p);   -- free the shared channel now, not after MAX_WAIT
                if isWrite(p.op) then
                    failWrite(p, 'write timeout');
                elseif p.op == M.op.INSTANCE_LOOKUP then
                    finishLookup(nil, 'timeout');
                elseif p.op == M.op.LOST_LIST then
                    st.lostAcc = nil;
                elseif p.op == M.op.SV_LIST or p.op == M.op.SV_MEMBERS then
                    shelfReadGaveUp(p, now);   -- the shelf's, never the vault's backoff
                elseif (p.op == M.op.LAYOUT_LIST or p.op == M.op.LAYOUT_LIST2) then
                    noteWhy('layout ask timed out (no reply after ' .. retriesOf(p.op) .. ' retries)', now);
                    st.layoutAcc = nil;   -- the tab just shows stale and re-asks
                else
                    -- Lost sync: stale mirror, a short backoff, ONE quiet state
                    -- (no chat spam -- /dl vault says it when asked).
                    noteWhy(string.format('%s (%s#%d) timed out: no reply after %d retries',
                        p.kind, opName(p.op), p.seq, retriesOf(p.op)), now);
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
        local req = st.depositQ[1];
        if req.itemIds == nil then
            -- what the bag slots hold as the deposit leaves: the ack names
            -- slots, not items, and says nothing of the apply that follows
            req.itemIds = {};
            for _, e in ipairs(req.entries) do
                local id = nil;
                if type(M._readSlot) == 'function' then
                    local ok, v = pcall(M._readSlot, e.container, e.slot);
                    if ok then id = v; end
                end
                req.itemIds[#req.itemIds + 1] = id;
            end
        end
        beginOp('deposit', M.op.DEPOSIT, M.depositPayload(req.entries), now);
        return;
    end
    if st.layoutSetQ ~= nil and st.layoutSetQ[1] ~= nil then
        local e = st.layoutSetQ[1].e;
        beginOp('layoutset', M.instanceMode() and M.op.LAYOUT_SET2 or M.op.LAYOUT_SET,
            M.instanceMode() and M.layoutSet2Payload(e) or M.layoutSetPayload(e), now);
        return;
    end
    -- The Shared Vault: its one write, then the reads its open tab asked for
    -- (a tab closed before they left drops them: the next open reads, S9).
    -- The member list goes first, so the rows can name who shared them.
    if st.shelfWriteQ ~= nil and st.shelfWriteQ[1] ~= nil then
        local req = st.shelfWriteQ[1];
        beginOp(req.kind, req.op, req.payload, now);
        return;
    end
    if (st.svMembersWant or st.svListWant) and not (shelfOpen(now) and M.shelfAvailable()) then
        st.svMembersWant, st.svListWant = nil, nil;
    end
    if st.svMembersWant then
        st.svMembersWant = nil;
        beginOp('shelf-members', M.op.SV_MEMBERS, wu32(0), now);
        st.pending.svGroup = st.svGroupId;
        return;
    end
    if st.svListWant then
        st.svListWant = nil;
        st.svAcc, st.svAccRev = {}, nil;
        beginOp('shelf-list', M.op.SV_LIST, wu32(0) .. streamTail(), now, 0);
        st.pending.svGroup, st.pending.svGen = st.svGroupId, st.svNoteGen;
        return;
    end
    -- A layout ask waits for HELLO: before it, the client cannot know the
    -- instance protocol, and the legacy page it would send was thrown away
    -- by the negotiation at every login (~100 wasted reads in the logs).
    if st.layoutWant ~= nil and M.limits ~= nil and now >= (st.layoutAfter or 0) then
        local want = st.layoutWant;
        st.layoutWant = nil;
        st.layoutAcc = {};
        st.layoutRev = nil;
        st.layoutDirtySince, st.layoutAfter = nil, nil;
        if M.instanceMode() then
            beginOp('layout', M.op.LAYOUT_LIST2, M.layoutPayload(want.job, 0) .. streamTail(), now, 0);
        else
            beginOp('layout', M.op.LAYOUT_LIST, M.layoutPayload(want.job, 0), now, 0);
        end
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
        beginOp('lost', M.op.LOST_LIST, wu32(0) .. streamTail(), now, 0);
        st.pending.lostRevision = M.revision;
        return;
    end
    if st.staleAt == nil or now < st.staleAt then return; end

    -- A sync (or a probe) always starts at HELLO: proto check + the count --
    -- and, since 2026-09-30, the push subscription (the server keeps it for
    -- the session). `gen` pins the reasons this read answers.
    beginOp(st.probeOnly and 'probe' or 'sync-hello', M.op.HELLO, M.helloPayload(), now);
    st.pending.gen = st.mirrorGen;
end

-- A CHANGED push. T2: it is never a reply, so it bypasses the transport's
-- pending slot and timing entirely (an unmatched frame restarted every
-- module's send gap until 2026-09-30). The server sends one after every
-- change a subscribed client did not make itself, coalesced per tick and
-- queued BEHIND the item packets of the change it names (FIFO): when it
-- lands, the bags already show the result, and the server is done.
local function onPush(f, now)
    if type(M._notePush) == 'function' then pcall(M._notePush, f.op, 'gear vault push'); end
    local c = (f.status == M.status.OK) and M.parseChanged(f.payload) or nil;
    if c == nil then
        noteWhy('ate an unreadable push', now);
        return true;
    end
    st.lastPush = { at = now, scope = c.scope, cause = c.cause, eventSeq = c.eventSeq };
    if st.dormant then return true; end
    if st.unattuned then
        -- The Deeper Room just finished: ask now instead of in five minutes.
        if has(c.scope, M.change.ATTUNE) then st.staleAt = now; end
        return true;
    end
    M.noteRevision(c.revision);
    local shelved = has(c.scope, M.change.APPLIED) and ((c.pulled or 0) + (c.evicted or 0)) > 0;
    if has(c.scope, M.change.VAULT) or shelved then
        st.probeOnly = false;
        dueSoon(M.SETTLE_PUSH, 'push');
    end
    local job = st.lastJob;
    local mine = has(c.scope, M.change.LAYOUT) and type(job) == 'number' and job > 0
        and has(c.jobs, 2 ^ job);
    if mine or shelved then
        -- entries changed, or copies moved (the layout shows where each is);
        -- an apply that moved nothing (most zone lines) changes neither view
        M.invalidateLayout(M.SETTLE_PUSH);
        M.requestLayout(0);
    end
    if has(c.scope, M.change.LOST) then
        M.lost.fresh = false;
        M.lost.revision = nil;   -- a prune can empty it without moving the revision
        M.requestLost();
    end
    if type(M._onPush) == 'function' then pcall(M._onPush, c.scope, c.jobs, c.cause); end
    return true;
end

-- One parsed inbound frame. Returns true when it was OURS (glue blocks it).
function M.onFrame(f)
    if f == nil or type(f.op) ~= 'number' then return false; end
    if f.op < M.op.HELLO or f.op > 0x7F then return false; end
    local now = M._clock();
    if f.op == M.op.CHANGED and (f.seq or 0) == 0 then return onPush(f, now); end
    if f.op == M.op.SV_CHANGED and (f.seq or 0) == 0 then return onShelfPush(f, now); end
    if M._received then M._received(f.op, f.seq); end
    st.trace.lastRecv = { op = f.op, seq = f.seq, status = f.status, len = #(f.payload or ''), at = now };
    local p = st.pending;
    if p == nil or p.sentAt == nil or f.op ~= p.op or f.seq ~= p.seq then
        noteWhy(string.format('ate a %s#%d we were not waiting for (late duplicate)', opName(f.op), f.seq), now);
        return true;   -- ours by partition, but not the answer we await (late dupe): eat it
    end
    -- A Shared Vault answer is the shelf's alone: whatever its status, it
    -- never sends the vault dormant, un-attuned or into its backoff.
    if p.op >= M.op.SV_LIST and p.op <= M.op.SV_CHANGED then return onShelfReply(p, f, now); end

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
            -- TOO_FAR is decided at the first entry: nothing moved, the
            -- mirror stands. BUSY / UNAVAILABLE can end a BATCH part-way --
            -- the server answers the whole frame with one status and the
            -- entries already moved lose their results -- so re-read.
            if f.status ~= M.status.TOO_FAR and f.status ~= M.status.MALFORMED then
                M.markStale(0, 'write refused part-way');
                st.probeOnly = false;
            end
            return true;
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
        st.staleAt = math.max(st.staleAt or 0, now + M.GIVEUP_BACKOFF);
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
            or has(f.flags, M.FLAG_STALE);
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

    -- The three list reads share one shape: rows in ascending key order,
    -- MORE = ask again past the last key, and (STREAM) FOLLOWS = another
    -- frame of this same reply is already on its way. A retried request can
    -- deliver a burst twice; a row at or below the last key taken is a
    -- duplicate and is skipped, so the accumulator never double-counts.
    if p.op == M.op.LOST_LIST then
        local chunk = M.parseLost(f.payload);
        if not chunk then st.pending = nil; st.lostAcc = nil; return true; end
        st.lostAcc = st.lostAcc or {};
        local accLast = p.accLast or p.cursor or 0;
        for _, e in ipairs(chunk.entries) do
            if e.instanceId > accLast then st.lostAcc[#st.lostAcc + 1] = e; accLast = e.instanceId; end
        end
        p.accLast = accLast;
        if has(f.flags, M.FLAG_FOLLOWS) then p.sentAt = now; return true; end
        st.pending = nil;
        if has(f.flags, M.FLAG_MORE) then
            if accLast <= (p.cursor or 0) then st.lostAcc = nil; return true; end
            beginOp('lost', M.op.LOST_LIST, wu32(accLast) .. streamTail(), now, accLast);
            st.pending.lostRevision = p.lostRevision;
        else
            if p.lostRevision ~= M.revision then
                st.lostAcc = nil; M.requestLost(); return true;
            end
            M.lost = { entries = st.lostAcc, fresh = true, revision = p.lostRevision };
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
        local modeChanged = M.instanceMode() ~= (h.instances == true);
        M.limits = h;
        st.subscribed = h.push == true;   -- the server keeps it until we log out
        noteShelfHello(h, now);           -- the group and its shelf's Rev, told to this session
        if modeChanged then
            -- A layout can arrive before the login HELLO. Its old rows lack
            -- instance/location fields even though the mirror is now v2.
            M.invalidateLayout();
            M.requestLayout(0);
        end
        M.noteRevision(h.revision);
        M.mirror.vaultCount = h.vaultCount;
        local rowsHeld = #M.mirror.rows;
        -- The probe compares against the revision these rows were LISTED at
        -- (2026-09-30 audit: it used the client's running revision, which
        -- layout pages and lookups advance, so a count-neutral change --
        -- k pieces in, k out -- slipped through as "unchanged").
        if p.kind == 'probe' and M.mirror.stamp ~= nil and h.vaultCount == rowsHeld
            and (not h.instances or M.mirror.revision == h.revision) then
            if p.gen == nil or p.gen == st.mirrorGen then
                M.mirror.fresh = true;
                M.mirror.stamp = now;
                st.staleAt = nil;
            end
            st.probeOnly = false;
            return true;
        end
        if p.kind == 'probe' and h.instances and M.layoutCache.revision ~= h.revision then
            -- copies moved since the layout was read: its locations may have too
            M.invalidateLayout();
            M.requestLayout(0);
        end
        st.probeOnly = false;
        st.rowsAcc = {}; st.rowsRev = nil;
        if M.instanceMode() then
            beginOp('sync-list', M.op.LIST2, M.listPayload(0) .. streamTail(), now, 0);
        else
            beginOp('sync-list', M.op.LIST, M.listPayload(0), now, 0);
        end
        st.pending.gen = p.gen;
        return true;
    end

    if p.op == M.op.LIST or p.op == M.op.LIST2 then
        local chunk;   -- if/else: `a and parse() or ...` turns a failed parse into false, not nil
        if p.op == M.op.LIST2 then chunk = M.parseList2(f.payload); else chunk = M.parseListChunk(f.payload); end
        if chunk == nil then
            st.pending = nil;
            st.rowsAcc = nil;
            st.staleAt = math.max(st.staleAt or 0, now + M.GIVEUP_BACKOFF);
            return true;
        end
        if chunk.revision ~= nil then
            M.noteRevision(chunk.revision);
            if st.rowsRev ~= nil and st.rowsRev ~= chunk.revision then
                -- the vault moved between our pages: start over shortly (never
                -- EARLIER than a settle someone else asked for)
                st.pending = nil; st.rowsAcc = nil;
                st.staleAt = math.max(st.staleAt or 0, now + 1);
                return true;
            end
            st.rowsRev = chunk.revision;
        end
        st.rowsAcc = st.rowsAcc or {};
        local accLast = p.accLast or p.cursor or 0;
        for _, e in ipairs(chunk.entries) do
            if e.rowId > accLast then st.rowsAcc[#st.rowsAcc + 1] = e; accLast = e.rowId; end
        end
        p.accLast = accLast;
        if has(f.flags, M.FLAG_FOLLOWS) then p.sentAt = now; return true; end
        st.pending = nil;
        if has(f.flags, M.FLAG_MORE) then
            if accLast <= (p.cursor or 0) then
                st.rowsAcc = nil; st.staleAt = math.max(st.staleAt or 0, now + M.GIVEUP_BACKOFF); return true;
            end
            beginOp('sync-list', p.op, M.listPayload(accLast) .. ((p.op == M.op.LIST2) and streamTail() or ''), now, accLast);
            st.pending.gen = p.gen;
        else
            M.mirror.vaultCount = #st.rowsAcc;   -- LIST is now the fresher truth
            commitMirror(now, p.gen, st.rowsRev or M.revision);
            if M.instanceMode() then M.requestLost(); end
        end
        return true;
    end

    if (p.op == M.op.LAYOUT_LIST or p.op == M.op.LAYOUT_LIST2) then
        local chunk;
        if p.op == M.op.LAYOUT_LIST2 then chunk = M.parseLayout2(f.payload); else chunk = M.parseLayoutChunk(f.payload); end
        if chunk == nil then
            st.pending = nil;
            st.layoutAcc = nil;
            return true;
        end
        if p.job ~= nil and p.job ~= 0 and p.job ~= st.lastJob then
            st.pending = nil;
            st.layoutAcc = nil; M.layoutCache.fresh = false; M.requestLayout(0); return true;
        end
        if chunk.revision ~= nil then
            M.noteRevision(chunk.revision);
            if st.layoutRev ~= nil and st.layoutRev ~= chunk.revision then
                st.pending = nil;
                st.layoutAcc = nil; M.layoutCache.fresh = false; M.requestLayout(0); return true;
            end
            st.layoutRev = chunk.revision;
        end
        st.layoutAcc = st.layoutAcc or {};
        local accLast = p.accLast or p.cursor or 0;
        for _, e in ipairs(chunk.entries) do
            if e.ordinal > accLast then st.layoutAcc[#st.layoutAcc + 1] = e; accLast = e.ordinal; end
        end
        p.accLast = accLast;
        if has(f.flags, M.FLAG_FOLLOWS) then p.sentAt = now; return true; end
        st.pending = nil;
        if has(f.flags, M.FLAG_MORE) then
            if accLast <= (p.cursor or 0) then st.layoutAcc = nil; return true; end
            beginOp('layout', p.op, M.layoutPayload(p.job, accLast) .. ((p.op == M.op.LAYOUT_LIST2) and streamTail() or ''), now, accLast);
            st.pending.job = p.job;
            st.pending.layoutEpoch = p.layoutEpoch;
        else
            -- A change noticed while the pages were on the wire (the epoch
            -- moved) no longer throws the read away: under steady inventory
            -- churn that restarted forever (runs of 24-30 pages in the field
            -- logs). The pages are one consistent server snapshot -- commit
            -- them for the eye, keep the view marked stale, read once more.
            local current = p.layoutEpoch == (st.layoutEpoch or 0);
            local ids = {};
            for _, e in ipairs(st.layoutAcc) do ids[e.itemId] = true; end
            M.layoutCache = {
                job      = (p.job ~= nil and p.job ~= 0) and p.job or st.lastJob,
                entries  = st.layoutAcc,
                fresh    = current,
                stamp    = now,
                revision = st.layoutRev,
                ids      = ids,
                idsOf    = st.layoutAcc,
            };
            st.layoutAcc = nil;
            if not current then M.requestLayout(0); end
            if M.instanceMode() then M.requestLost(); end
            if type(M._onLayout) == 'function' then pcall(M._onLayout); end
        end
        return true;
    end

    if (p.op == M.op.LAYOUT_SET or p.op == M.op.LAYOUT_SET2) then
        local ack;
        if p.op == M.op.LAYOUT_SET2 then ack = M.parseLayoutSet2Ack(f.payload); else ack = M.parseLayoutSetAck(f.payload); end
        if ack then M.noteRevision(ack.revision); end
        st.pending = nil;
        local req = table.remove(st.layoutSetQ or {}, 1);
        if req and M._audit then pcall(M._audit, 'reply', req.e, p.seq, ack and ack.code or 'malformed'); end
        local active = req ~= nil and ((req.e.job or 0) == 0 or req.e.job == st.lastJob);
        if ack == nil then
            -- An unreadable acknowledgement cannot prove the edit failed.
            -- Refresh both stores before offering another increment.
            M.invalidateLayout();
            M.requestLayout(0);
            M.markStale(M.SETTLE_EDIT, 'layout edit malformed reply');
            st.probeOnly = false;
        elseif ack.code == M.code.OK or ack.code == M.code.PARTIAL then
            M.invalidateLayout();
            M.requestLayout(0);   -- the view catches up now (a caller's ask coalesces)
            if req ~= nil and req.e.verb ~= M.verb.PIN and active then
                -- The server applied the active layout INSIDE this request and
                -- its item packets left before this ack (FIFO): the vault is
                -- final now. Read it as soon as the run of edits ends -- it
                -- was a fixed 6 s wait, most of every edit's 11 s median.
                M.markStale(M.SETTLE_EDIT, 'layout edit');
                st.probeOnly = false;
            end
        elseif ack.code == M.code.NO_INSTANCE or ack.code == M.code.NOT_IN_LAYOUT
            or ack.code == M.code.INSTANCE_LOST or ack.code == M.code.INSTANCE_OUTSIDE
            or ack.code == M.code.ALREADY_BOUND then
            -- the server says one of our views is out of date: re-read both
            M.invalidateLayout();
            M.requestLayout(0);
            M.markStale(M.SETTLE_EDIT, 'layout edit met a changed copy');
            st.probeOnly = false;
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
            -- an unreadable ack cannot prove nothing moved
            M.markStale(0, 'deposit malformed reply');
            st.probeOnly = false;
            return true;
        end
        -- Anything stored changed the vault: one LIST resync is the honest
        -- (and cheap -- you are standing at a Warden) way to fold it in. The
        -- server also applies what the layout NAMES right after a deposit
        -- (applyDepositedWants), so a stored piece the layout carries moves
        -- on to the shelf -- and the layout, which shows where each copy is,
        -- is read again. A piece the layout does not name leaves it alone.
        local stored, named = false, false;
        for i, e in ipairs(ack.entries) do
            if e.code == M.code.OK or e.code == M.code.PARTIAL then
                stored = true;
                local id = req ~= nil and req.itemIds ~= nil and req.itemIds[i] or nil;
                if id == nil or layoutNames(id) then named = true; end
            end
        end
        if stored then
            M.markStale(0, 'deposit');
            st.probeOnly = false;
            -- marked, not asked: the vault list goes first (it is what the
            -- player is looking at), and its commit kicks the layout engine,
            -- which asks for the stale layout itself
            if named and (M.layoutCache.entries ~= nil and #M.layoutCache.entries > 0) then
                M.invalidateLayout();
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
            M.markStale(0, 'withdraw malformed reply');
            st.probeOnly = false;
            return true;
        end
        -- SUBTRACTION, the E-Box law: we sent the rows, the ack says what
        -- moved, so the mirror is arithmetic -- no re-LIST. A NO_INSTANCE
        -- answer means the mirror believed a row the vault no longer holds:
        -- that one forces the honest resync.
        local goneRow, changed, laidOut = false, false, false;
        for _, e in ipairs(ack.entries) do
            if e.moved > 0 then
                changed = true;
                for i, row in ipairs(M.mirror.rows) do
                    if row.rowId == e.rowId then
                        -- a copy the layout names now sits in the bags: the
                        -- layout shows where each copy is, so it re-reads
                        if (row.instanceId or 0) > 0 then
                            for _, le in ipairs(M.layoutCache.entries or {}) do
                                if le.instanceId == row.instanceId then laidOut = true; break; end
                            end
                        end
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
        if goneRow then M.markStale(0, 'withdraw met a gone row'); st.probeOnly = false; end
        if laidOut then M.invalidateLayout(); M.requestLayout(0); end
        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, ack.entries, nil); end
        return true;
    end

    return true;
end

-- ---------------------------------------------------------------------------
-- Readouts (the service surface + /dl vault)
-- ---------------------------------------------------------------------------
-- 'syncing' means the MIRROR is being re-read (HELLO/LIST on the wire) --
-- not any op at all: a one-slot lookup or a lost-list page used to paint the
-- whole vault as syncing and hold the layout engine (2026-09-30).
function M.state()
    if st.dormant then return 'dormant'; end
    if st.unattuned then return 'unattuned'; end
    local k = st.pending and st.pending.kind;
    if k == 'probe' or k == 'sync-hello' or k == 'sync-list' then return 'syncing'; end
    if M.mirror.fresh then return 'fresh'; end
    return 'stale';
end

-- What real work is under way, for a calm one-word readout: 'vault' (the
-- vault list is being re-read), 'layout' (this job's layout is), 'edits'
-- (layout changes are going out), 'moving' (a store / withdraw), or nil. A
-- probe is a glance, not an update, and says nothing.
function M.activity()
    if st.dormant or st.unattuned then return nil; end
    local k = st.pending and st.pending.kind;
    if k == 'deposit' or k == 'withdraw' or #(st.depositQ or {}) > 0 or #(st.withdrawQ or {}) > 0 then
        return 'moving';
    end
    if k == 'layoutset' or #(st.layoutSetQ or {}) > 0 then return 'edits'; end
    if k == 'sync-hello' or k == 'sync-list' then return 'vault'; end
    if k == 'layout' or (st.layoutWant ~= nil and M.limits ~= nil) then return 'layout'; end
    if st.staleAt ~= nil and not st.probeOnly and M._clock() >= st.staleAt - 0.5 then return 'vault'; end
    return nil;
end

-- Is anything WRONG enough to show? nil = fine (fresh, or a routine re-read
-- under way), 'never' = no vault read has landed yet, 'failing' = reads are
-- failing and backing off (/dl vault says why).
function M.health()
    if st.dormant or st.unattuned then return nil; end
    if (st.giveups or 0) > 0 then return 'failing'; end
    if M.mirror.stamp == nil then return 'never'; end
    return nil;
end

-- Live updates: the server pushes changes to us (negotiated in HELLO; it lasts
-- the session -- zone lines keep it, a login renews it).
function M.live()
    return M.limits ~= nil and M.limits.push == true and st.subscribed == true;
end

-- The goodbye HELLO (client caps 0) the glue sends as the addon unloads: the
-- subscription lasts the session, so the server must hear that nothing is
-- left to block its frames from reaching the game. nil when not subscribed.
function M.unsubscribeFrame()
    if not M.live() then return nil; end
    st.subscribed = false;
    return M.buildFrame(M.op.HELLO, nextSeq(), wu16(M.PROTO) .. wu16(0));
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
    local pinMode = M.limits == nil and 'server support: unchecked'
        or (M.instanceMode() and M.limits.atomicInstanceAdd and 'pinned instance adds: one request')
        or 'pinned adds: ADD then PIN';
    local live = '';
    if M.limits ~= nil then
        live = ' -- live updates: ' .. ((not M.limits.push) and 'not offered by this server'
            or (st.subscribed and 'on' or (st.fieldHold and 'off in the field' or 'renewing')))
            .. (M.limits.stream and ', one-request reads' or '');
    end
    return string.format('gear vault: %s -- %d piece%s mirrored (%d row%s)%s%s -- %s%s.',
        s, n, (n == 1) and '' or 's', #M.mirror.rows, (#M.mirror.rows == 1) and '' or 's',
        (st.giveups > 0) and (' -- ' .. st.giveups .. ' failed sync(s), retrying') or '',
        M.instanceMode() and (' -- instances, revision ' .. tostring(M.revision)) or '', pinMode, live);
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
    if st.lastPush ~= nil then
        parts[#parts + 1] = string.format('last push %s (scope %d, cause %d)', ago(st.lastPush.at),
            st.lastPush.scope or 0, st.lastPush.cause or 0);
    end
    if st.dormant then
        parts[#parts + 1] = 'no retry (dormant)';
    elseif st.unattuned and st.pending == nil and st.staleAt ~= nil then
        parts[#parts + 1] = string.format('not attuned: next check in %ds', math.max(0, math.ceil(st.staleAt - now)));
    elseif st.pending ~= nil then
        parts[#parts + 1] = st.pending.sentAt == nil and 'queued for paced send' or 'awaiting a reply';
    elseif st.staleAt ~= nil then
        parts[#parts + 1] = string.format('next try in %ds', math.max(0, math.ceil(st.staleAt - now)));
    elseif st.fieldHold then
        parts[#parts + 1] = 'holding still in the field (the vault only changes in a city)';
    end
    return 'gear vault: ' .. table.concat(parts, ' | ') .. '.';
end

-- test seam
function M._reset()
    M.mirror = { fresh = false, rows = {}, counts = {}, vaultCount = nil, stamp = nil, revision = nil };
    M.layoutCache = { job = nil, entries = {}, fresh = false, stamp = nil };
    M.limits = nil; M.revision = nil; M.lost = { entries = {}, fresh = false };
    M.shelf = emptyShelf();
    st = { dormant = false, unattuned = false, pending = nil, seq = 0, lastSend = 0,
           staleAt = nil, mirrorGen = 0, giveups = 0, rowsAcc = nil, lastJob = nil,
           saidProto = false, trace = {}, subscribed = false, fieldHold = false };
end

function M._st() return st; end

return M;
