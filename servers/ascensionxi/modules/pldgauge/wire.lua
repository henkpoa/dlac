--[[
    ascensionxi/pldgauge/wire -- the bytes of the Paladin's slot on
    AscensionXI's job gauge channel (0x1E0 ops 0xD0-0xDF), pure: no Ashita,
    no state. The server's codec is modules/custom/lua/job_gauge_wire.lua in
    the ascensionxi repo; the contract is documentation/custom/
    pld-divine-guard.md there. A shared 14-byte vector is pinned in both
    suites.

    The partition is shared by job: the slot is op % 8. Slot 0 is the White
    Mage flower gauge (whmgauge/wire.lua), slot 1 the Dancer status
    (dncstatus/wire.lua), slot 2 the Paladin (0xD2, 0xDA). Each module reads
    only its own slot's ops.

    Why a channel at all: the Paladin's points live only on the server. The
    client never learns that a hit it took was blocked, nor how many
    Palisade stacks the buff holds (the client gets buff icons, never their
    power). What the client CAN see it reads itself and never asks for: its
    job and level, the Divine Guard and Divine Fury buffs and the Palisade
    buff.

    Packet budget (the AutoAcc lesson): one request per zone while the main
    job is Paladin, and pushes only when something drawn changes (the
    server coalesces them to one within 250 ms).

    Envelope (every 0x1E0 here): 4-byte packet header, then
      4 u8 op   5 u8 seq   6 u8 status   7 u8 flags   8.. payload
    Little-endian, offsets 0-based into the payload.

    0xD2 SUBSCRIBE  client -> server, payload 4 bytes:
         0 u8 proto (1)   1 u8 mode (1 subscribe, 0 stop)   2 u16 0
    0xD2 reply      server -> client, same seq, status 0 = OK, payload = STATE.
         BUSY (3): more than one subscribe a second; ask again shortly.
         A server without the slot answers BAD_OP (1), UNAVAILABLE (5) or
         nothing.
    0xDA STATE      server -> client push, seq 0, payload = STATE.

    STATE, 14 bytes:
         0 u8 proto (1)        1 u8 job (7 = PLD)
         2 u8 stance (0 none, 1 Divine Guard, 2 Divine Fury)
         3 u8 points (0-3)
         4 u8 palisade         the Palisade buff's stacks (0-30)
         5 u8 palisade max     (30)
         6 u8 flags            7 u8 0
         8 u16 charge         10 u16 threshold   (blocks fill the bar toward a point)
        12 u16 rev            (wraps; a push older than the last one is ignored)
]]--

local M = {};

M.PKT = 0x1E0;
M.OP_FIRST, M.OP_LAST = 0xD0, 0xDF;
M.op = { SUBSCRIBE = 0xD2, STATE = 0xDA };
M.PROTO = 1;
M.STATE_SIZE = 14;
M.JOB_PLD = 7;
M.MAX_POINTS = 3;
M.PALISADE_MAX = 30;   -- what a server that sends 0 for the cap means
M.stance = { NONE = 0, GUARD = 1, FURY = 2 };
M.status = { OK = 0, BAD_OP = 1, MALFORMED = 2, BUSY = 3, UNAVAILABLE = 5 };
M.flag = {
    CAPPED = 0x01,   -- three points and a full bar: blocks fill nothing until one is spent
};

local function u16(s, o)
    local a, b = s:byte(o + 1, o + 2);
    return (a or 0) + (b or 0) * 256;
end
M.u16 = u16;

function M.hasFlag(flags, bit) return (flags or 0) % (bit * 2) >= bit; end

-- Is `op` this slot's?
function M.ours(op) return op == M.op.SUBSCRIBE or op == M.op.STATE; end

-- The byte table AddOutgoingPacket takes (first four bytes left for Ashita).
function M.subscribe(seq, on)
    return { 0, 0, 0, 0, M.op.SUBSCRIBE, seq % 256, 0, 0, M.PROTO, on and 1 or 0, 0, 0 };
end

-- { op, seq, status, flags, payload } of an incoming 0x1E0 string, or nil.
function M.incoming(data)
    if type(data) ~= 'string' or #data < 8 then return nil; end
    local size = math.floor(u16(data, 0) / 512) * 4;
    if size < 8 or size > #data then size = #data; end
    return { op = data:byte(5), seq = data:byte(6), status = data:byte(7), flags = data:byte(8),
             payload = data:sub(9, size) };
end

-- A STATE payload as a table, or nil (short, or a protocol this client
-- does not read). Every field is clamped, so a bad byte can never draw a
-- fourth point or a stack count the art has no room for.
function M.state(p)
    if type(p) ~= 'string' or #p < M.STATE_SIZE then return nil; end
    if p:byte(1) ~= M.PROTO then return nil; end
    local st = p:byte(3) or 0;
    if st > 2 then st = 0; end
    local points = p:byte(4) or 0;
    if points > M.MAX_POINTS then points = M.MAX_POINTS; end
    local cap = p:byte(6) or 0;
    if cap == 0 or cap > 99 then cap = M.PALISADE_MAX; end
    local stacks = p:byte(5) or 0;
    if stacks > cap then stacks = cap; end
    return {
        job         = p:byte(2),
        stance      = st,
        points      = points,
        palisade    = stacks,
        palisadeMax = cap,
        flags       = p:byte(7) or 0,
        charge      = u16(p, 8),
        threshold   = u16(p, 10),
        rev         = u16(p, 12),
    };
end

-- The same STATE as the server builds it (tests and the demo).
function M.encodeState(s)
    local function b(v) v = math.floor(tonumber(v) or 0); if v < 0 then v = 0; end; return string.char(math.min(255, v)); end
    local function w(v) v = math.floor(tonumber(v) or 0); if v < 0 then v = 0; end
        v = v % 65536; return string.char(v % 256, math.floor(v / 256)); end
    return b(M.PROTO) .. b(s.job or M.JOB_PLD) .. b(s.stance) .. b(s.points)
        .. b(s.palisade) .. b(s.palisadeMax) .. b(s.flags) .. b(0)
        .. w(s.charge) .. w(s.threshold) .. w(s.rev);
end

-- A whole server frame, as Ashita would hand it over (tests).
function M.s2cFrame(op, seq, status, payload)
    local body = string.char(op, seq % 256, status or 0, 0) .. (payload or '');
    local words = math.floor((4 + #body + 3) / 4);
    local size = words * 512 + M.PKT;
    local frame = string.char(size % 256, math.floor(size / 256) % 256, 0, 0) .. body;
    return frame .. string.rep('\0', words * 4 - #frame);
end

-- Is rev `a` newer than `b`, across the 16-bit wrap?
function M.newer(a, b)
    if b == nil then return true; end
    local d = (a - b) % 65536;
    return d ~= 0 and d < 32768;
end

return M;
