--[[
    ascensionxi/telemetry/wire -- the bytes of AscensionXI's combat telemetry
    (0x1E0 ops 0xC0-0xCF), pure: no Ashita, no state. The contract is section 4
    of the server's documentation/custom/autoacc-backend-research.md, with the
    partition at 0xC0 (documentation/custom/combat-telemetry.md); the server's
    codec is modules/custom/lua/combat_telemetry_wire.lua. Both reproduce the
    research's wire-vectors.md byte for byte (tests/ascensionxi_telemetry_wire.lua
    here).

    Little-endian, offsets 0-based into the payload (the bytes after the 8-byte
    envelope). Every payload starts with the 12-byte telemetry header:
      0 u8 Proto   1 u8 Result (reply) or Lane (push)   2 u16 Len
      4 u32 Session   8 u32 Nonce (request, reply) or Rev (push)
    Runs on LuaJIT and Lua 5.4: no bit library, no integer operators.
]]--

local M = {};

local unpack = table.unpack or unpack;

M.PKT = 0x1E0;
M.OP_FIRST, M.OP_LAST = 0xC0, 0xCF;
M.op = { HELLO = 0xC0, WATCH = 0xC1, PLAN = 0xC2, RESYNC = 0xC3, STOP = 0xC4, QUERY = 0xC5,
         SNAPSHOT = 0xC8, PLAN_RESULT = 0xC9 };
M.PROTO, M.TH_SIZE, M.MAX_PAYLOAD = 1, 12, 500;

M.status = { OK = 0, BAD_OP = 1, MALFORMED = 2, BUSY = 3, UNAVAILABLE = 5, PROTO_UNSUPPORTED = 6 };
M.result = { OK = 0, NO_SESSION = 1, STALE_GEN = 2, BAD_LANE = 3, LIMIT = 4, PLAN_INVALID = 5, NOT_CAPABLE = 6 };
M.cap = { SNAPSHOT = 0x01, PREVIEW_LANE = 0x02, PLAN = 0x04, PDIF = 0x08, TARGET_ATTRS = 0x10,
          QUERY = 0x20, FOLLOW = 0x40 };
M.CLIENT_CAPS = 0x01 + 0x02 + 0x10 + 0x20 + 0x40;   -- everything a slice-1 server offers

M.laneState = { IDLE = 0, LIVE = 1, TARGET_NOT_FOUND = 2, TARGET_GONE = 3, OUT_OF_RANGE = 4,
                SUSPENDED = 5, NOT_PERMITTED = 6, UNSUPPORTED = 7 };
M.context = { MELEE_MAIN = 0, MELEE_SUB = 1, KICK = 2, RANGED = 3 };
M.applicability = { APPLICABLE = 0, NO_WEAPON = 1, NOT_AVAILABLE = 2, OUT_OF_RANGE = 3,
                    TARGET_INVALID = 4, UNSUPPORTED = 5 };
M.watchFlag = { WANT_PDIF = 0x01, WANT_TARGET_ATTRS = 0x02, FOLLOW = 0x04 };
M.resyncMode = { RENEW = 0, REPUBLISH = 1 };
M.stopFlag = { END_SESSION = 0x01 };
M.snapFlag = { FIRST = 0x01, RESYNC = 0x02, TIME_VARYING = 0x04, FOLLOW = 0x08, GEAR_REFILL = 0x10,
               NEW_OUTFIT = 0x20 };
M.ctxFlag = { AT_CAP = 0x01, AT_FLOOR = 0x02, LEVEL_PENALTY = 0x08, TIME_VARYING = 0x10,
              CONTEXTUAL_EXCEPTIONS = 0x20, POLICY_ADJUSTED = 0x40, TWO_HANDED = 0x80 };
M.valid = { TARGET_ID = 0x01, PLAYER_CORE = 0x02, PLAYER_INPUTS = 0x04, TARGET_CORE = 0x08,
            TARGET_ATTRS = 0x10, DISTANCE = 0x40 };

M.HELLO_REQUEST, M.HELLO_REPLY = 24, 48;
M.WATCH_REQUEST, M.WATCH_REPLY = 32, 28;
M.RESYNC_REQUEST, M.RESYNC_REPLY = 16, 36;
M.STOP_SIZE = 16;
M.SNAPSHOT_FIXED, M.CONTEXT_SIZE = 136, 24;
M.VALID_FOR_STATIC = 0xFFFF;

M.GEAR_INPUTS = { 'dex', 'agi', 'accMod', 'raccMod', 'twoHandAccMod', 'wsAccMod' };
M.PLAYER_INPUTS = { 'enlightAcc', 'tandemAcc', 'meritAcc', 'foodAccPct', 'foodAccCap', 'flashPenalty',
                    'rangedAccBonus', 'foodRaccPct', 'foodRaccCap', 'flourishAcc' };
M.TARGET_ATTRS = { 'str', 'dex', 'vit', 'agi', 'int', 'mnd', 'chr' };

-- ---------------------------------------------------------------------------
-- Bytes
-- ---------------------------------------------------------------------------

function M.hasBit(mask, bit) return (mask or 0) % (bit * 2) >= bit; end

function M.u8(s, o) return s:byte(o + 1) or 0; end
function M.u16(s, o)
    local a, b = s:byte(o + 1, o + 2);
    return (a or 0) + (b or 0) * 256;
end
function M.i16(s, o)
    local v = M.u16(s, o);
    return (v >= 32768) and (v - 65536) or v;
end
function M.u32(s, o) return M.u16(s, o) + M.u16(s, o + 2) * 65536; end

local function clampInt(v, lo, hi)
    v = math.floor(tonumber(v) or 0);
    if v < lo then return lo; end
    if v > hi then return hi; end
    return v;
end

function M.w8(v) return string.char(clampInt(v, 0, 255)); end
function M.w16(v)
    v = clampInt(v, 0, 0xFFFF);
    return string.char(v % 256, math.floor(v / 256));
end
function M.w32(v)
    v = clampInt(v, 0, 0xFFFFFFFF);
    local lo, hi = v % 65536, math.floor(v / 65536);
    return string.char(lo % 256, math.floor(lo / 256), hi % 256, math.floor(hi / 256));
end

-- ---------------------------------------------------------------------------
-- FNV-1a 32 in exact double arithmetic (the 32x24-bit product is taken in
-- two 16-bit halves so it never passes 2^53).
-- ---------------------------------------------------------------------------
local XOR = {};
for a = 0, 255 do
    local row = {};
    for b = 0, 255 do
        local r, bit, x, y = 0, 1, a, b;
        for _ = 1, 8 do
            if x % 2 ~= y % 2 then r = r + bit; end
            x, y, bit = math.floor(x / 2), math.floor(y / 2), bit * 2;
        end
        row[b] = r;
    end
    XOR[a] = row;
end

local FNV_OFFSET, FNV_PRIME = 0x811C9DC5, 0x01000193;

local function fnvStep(h, byte)
    local lo = h % 256;
    h = h - lo + XOR[lo][byte];
    local hl, hh = h % 65536, math.floor(h / 65536);
    return (hl * FNV_PRIME + (hh * FNV_PRIME % 65536) * 65536) % 4294967296;
end

function M.fnv1a32(data, h)
    h = h or FNV_OFFSET;
    for i = 1, #data do h = fnvStep(h, data:byte(i)); end
    return h;
end

-- The outfit hash the server publishes as EquipRev: FNV-1a over the 16 equip
-- slots in order, 8 bytes each (u8 container, u8 slot-in-container, u16 item
-- id, u32 identity 0). refs[0..15] = { container, slot, id } or nil/id 0.
function M.outfitHash(refs)
    local h = FNV_OFFSET;
    for equipSlot = 0, 15 do
        local r = refs[equipSlot];
        local c, s, id = 0, 0, 0;
        if type(r) == 'table' and (tonumber(r[3]) or 0) ~= 0 then c, s, id = r[1], r[2], r[3]; end
        h = fnvStep(h, c % 256);
        h = fnvStep(h, s % 256);
        h = fnvStep(h, id % 256);
        h = fnvStep(h, math.floor(id / 256) % 256);
        for _ = 1, 4 do h = fnvStep(h, 0); end
    end
    return h;
end

-- ---------------------------------------------------------------------------
-- The header, requests and replies
-- ---------------------------------------------------------------------------

function M.header(code, len, session, nonce)
    return string.char(M.PROTO, clampInt(code, 0, 255)) .. M.w16(len) .. M.w32(session) .. M.w32(nonce);
end

function M.readHeader(p)
    if type(p) ~= 'string' or #p < M.TH_SIZE then return nil; end
    return { proto = M.u8(p, 0), code = M.u8(p, 1), len = M.u16(p, 2), session = M.u32(p, 4), nonce = M.u32(p, 8) };
end

function M.encodeHello(r)
    return M.header(0, M.HELLO_REQUEST, 0, r.nonce) .. M.w16(r.protoMin or 1) .. M.w16(r.protoMax or 1)
        .. M.w32(r.caps or M.CLIENT_CAPS) .. M.w32(r.build or 0);
end

-- WATCH, and QUERY with lane 0xFF and generation 0.
function M.encodeWatch(r)
    return table.concat({
        M.header(0, M.WATCH_REQUEST, r.session, r.nonce),
        M.w8(r.lane or 0), M.w8(r.flags or 0), M.w16(r.contextMask or 0),
        M.w32(r.watchGen or 0), M.w32(r.targetId or 0), M.w16(r.targetIndex or 0), M.w16(0),
        M.w32(r.expectSpawnGen or 0),
    });
end

function M.encodeResync(r)
    return M.header(0, M.RESYNC_REQUEST, r.session, r.nonce) .. M.w8(r.mode or 0) .. M.w8(r.laneMask or 0) .. M.w16(0);
end

function M.encodeStop(r)
    return M.header(0, M.STOP_SIZE, r.session, r.nonce) .. M.w8(r.laneMask or 0xFF) .. M.w8(r.flags or 0) .. M.w16(0);
end

-- Every reply decoder returns nil for a payload too short for its op; a
-- refusal that carries only the header decodes through readHeader.
function M.decodeHelloReply(p)
    local h = M.readHeader(p);
    if h == nil or h.len < M.HELLO_REPLY or #p < M.HELLO_REPLY then return nil; end
    h.result = h.code;
    h.protoMin, h.protoMax, h.agreedProto = M.u16(p, 12), M.u16(p, 14), M.u16(p, 16);
    h.leaseSeconds, h.caps, h.rulesRev, h.charId = M.u16(p, 18), M.u32(p, 20), M.u32(p, 24), M.u32(p, 28);
    h.maxLanes, h.maxContexts = M.u8(p, 32), M.u8(p, 33);
    h.minPushIntervalMs, h.maxPushBytes = M.u16(p, 36), M.u16(p, 38);
    h.contextKindsMask, h.renewAfterSeconds = M.u16(p, 40), M.u16(p, 46);
    return h;
end

function M.decodeWatchReply(p)
    local h = M.readHeader(p);
    if h == nil or h.len < M.WATCH_REPLY or #p < M.WATCH_REPLY then return nil; end
    h.result = h.code;
    h.lane, h.laneState, h.grantedContextMask = M.u8(p, 12), M.u8(p, 13), M.u16(p, 14);
    h.watchGen, h.boundSpawnGen, h.leaseSeconds, h.grantedFlags = M.u32(p, 16), M.u32(p, 20), M.u16(p, 24), M.u8(p, 26);
    return h;
end

function M.decodeResyncReply(p)
    local h = M.readHeader(p);
    if h == nil or h.len < M.RESYNC_REPLY or #p < M.RESYNC_REPLY then return nil; end
    h.result = h.code;
    h.leaseSeconds, h.laneMask = M.u16(p, 12), M.u8(p, 14);
    h.battleRev, h.previewRev = M.u32(p, 16), M.u32(p, 20);
    h.battleWatchGen, h.previewWatchGen = M.u32(p, 24), M.u32(p, 28);
    h.battleLaneState, h.previewLaneState = M.u8(p, 32), M.u8(p, 33);
    return h;
end

-- The SNAPSHOT push (and QUERY's reply): nil and a reason when it does not
-- hold together.
function M.decodeSnapshot(p)
    local h = M.readHeader(p);
    if h == nil or h.len < M.SNAPSHOT_FIXED or h.len > #p or h.len > M.MAX_PAYLOAD or h.len % 4 ~= 0 then
        return nil, 'length';
    end
    local s = {
        proto = h.proto, lane = h.code, len = h.len, session = h.session, rev = h.nonce,
        watchGen = M.u32(p, 12), laneState = M.u8(p, 16), stateReason = M.u8(p, 17),
        contextCount = M.u8(p, 18), snapFlags = M.u8(p, 19), validMask = M.u32(p, 20),
        equipRev = M.u32(p, 24), rulesRev = M.u32(p, 28), sampleMs = M.u32(p, 32),
        validForMs = M.u16(p, 36), zoneId = M.u16(p, 38), targetId = M.u32(p, 40),
        targetIndex = M.u16(p, 44), targetKind = M.u8(p, 46), targetFlags = M.u8(p, 47),
        spawnGen = M.u32(p, 48), distanceDeci = M.u16(p, 52), flashRemainingMs = M.u16(p, 54),
        mainJob = M.u8(p, 56), mainLevel = M.u8(p, 57), subJob = M.u8(p, 58), subLevel = M.u8(p, 59),
        enchantedSlotMask = M.u16(p, 60), latentActiveMask = M.u16(p, 62), targetLevel = M.u8(p, 64),
        targetDef = M.u16(p, 66), targetEva = M.u16(p, 68), targetAtt = M.u16(p, 70), targetAcc = M.u16(p, 72),
        baseMaxHp = M.u16(p, 132), baseMaxMp = M.u16(p, 134), targetAttrs = {}, contexts = {},
    };
    for i, name in ipairs(M.TARGET_ATTRS) do s.targetAttrs[name] = M.u16(p, 72 + i * 2); end
    for i, name in ipairs(M.GEAR_INPUTS) do
        s[name .. 'R'] = M.i16(p, 84 + i * 4);
        s[name .. 'Live'] = M.i16(p, 86 + i * 4);
    end
    for i, name in ipairs(M.PLAYER_INPUTS) do s[name] = M.i16(p, 110 + i * 2); end
    if h.len < M.SNAPSHOT_FIXED + M.CONTEXT_SIZE * s.contextCount then return nil, 'contexts'; end
    for i = 1, s.contextCount do
        local o = M.SNAPSHOT_FIXED + (i - 1) * M.CONTEXT_SIZE;
        s.contexts[i] = {
            kind = M.u8(p, o), applicability = M.u8(p, o + 1), skillType = M.u8(p, o + 2), flags = M.u8(p, o + 3),
            skillR = M.u16(p, o + 4), skillLive = M.u16(p, o + 6), statMultMilli = M.u16(p, o + 8),
            policyAcc = M.i16(p, o + 10), levelCorrection = M.i16(p, o + 12), targetEva = M.u16(p, o + 14),
            liveAcc = M.u16(p, o + 16), thresholdBp = M.u16(p, o + 18), floorBp = M.u16(p, o + 20),
            capBp = M.u16(p, o + 22),
        };
    end
    return s;
end

-- The comparison key of a SNAPSHOT (research 4.4), as the server keeps it:
-- the payload without what moves on its own (Rev, SampleMs, ValidForMs,
-- DistanceDeci, FlashRemainingMs), what is informational (TargetFlags, every
-- CtxFlags), what moves with gear (EquipRev, LatentActiveMask, every live
-- half, each context's live skill, LiveAcc and ThresholdBp) and the FIRST,
-- RESYNC and NEW_OUTFIT bits. Two frames with one key differ only in the
-- outfit: the server sent the second because that outfit was new.
local KEPT = { { 0, 8 }, { 12, 19 }, { 20, 24 }, { 28, 32 }, { 38, 47 }, { 48, 52 }, { 56, 62 }, { 64, 90 },
               { 92, 94 }, { 96, 98 }, { 100, 102 }, { 104, 106 }, { 108, 110 }, { 112, 136 } };
local CONTEXT_KEPT = { { 0, 3 }, { 4, 6 }, { 8, 16 }, { 20, 24 } };

function M.snapshotKey(p)
    local h = M.readHeader(p);
    if h == nil or h.len < M.SNAPSHOT_FIXED or h.len > #p then return nil; end
    local parts = {};
    for _, r in ipairs(KEPT) do parts[#parts + 1] = p:sub(r[1] + 1, r[2]); end
    local flags = M.u8(p, 19);
    for _, bit in ipairs({ M.snapFlag.FIRST, M.snapFlag.RESYNC, M.snapFlag.NEW_OUTFIT }) do
        if M.hasBit(flags, bit) then flags = flags - bit; end
    end
    parts[#parts + 1] = string.char(flags);
    for i = 0, M.u8(p, 18) - 1 do
        local o = M.SNAPSHOT_FIXED + i * M.CONTEXT_SIZE;
        if o + M.CONTEXT_SIZE > h.len then return nil; end
        for _, r in ipairs(CONTEXT_KEPT) do parts[#parts + 1] = p:sub(o + r[1] + 1, o + r[2]); end
    end
    return table.concat(parts);
end

-- ---------------------------------------------------------------------------
-- Frames. An outgoing frame is the byte table AddOutgoingPacket takes, its
-- first four bytes left 0 for Ashita to fill; an incoming one is the string
-- Ashita hands over (512 bytes, the real length in the header's size field).
-- ---------------------------------------------------------------------------

function M.outgoing(op, seq, payload)
    local t = { 0, 0, 0, 0, op, seq, 0, 0 };
    for i = 1, #payload do t[8 + i] = payload:byte(i); end
    while #t % 4 ~= 0 do t[#t + 1] = 0; end
    return t;
end

-- { op, seq, status, flags, payload } of an incoming 0x1E0 string, or nil.
function M.incoming(data)
    if type(data) ~= 'string' or #data < 8 then return nil; end
    local size = math.floor(M.u16(data, 0) / 512) * 4;
    if size < 8 or size > #data then size = #data; end
    return { op = data:byte(5), seq = data:byte(6), status = data:byte(7), flags = data:byte(8),
             payload = data:sub(9, size) };
end

-- The same frame as the server sends it (tests and the readout's dumps).
function M.s2cFrame(op, seq, status, flags, payload)
    local body = string.char(op, seq, status, flags) .. payload;
    local words = math.floor((4 + #body + 3) / 4);
    local frame = M.w16(words * 512 + M.PKT) .. M.w16(0) .. body;
    return frame .. string.rep('\0', words * 4 - #frame);
end

function M.bytesOf(t) return string.char(unpack(t)); end

return M;
