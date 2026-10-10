--[[
    ascensionxi/whmgauge/wire -- the bytes of AscensionXI's job gauge channel
    (0x1E0 ops 0xD0-0xDF), pure: no Ashita, no state. The server's codec is
    modules/custom/lua/job_gauge_wire.lua in the ascensionxi repo; the
    contract is documentation/custom/whm-flower-gauge.md there.

    The partition is shared by job (slot = op % 8): this is slot 0. Slot 1
    (0xD1, 0xD9) is the Dancer status (dncstatus/wire.lua); gauge.onFrame
    reads only the two ops below, so its frames never reach the gauge.

    Why a channel at all: the gauge's numbers live only on the server. The
    client never sees a Regen tick land on someone outside its party, and the
    server decides every flower anyway, because it applies them. What the
    client CAN see it reads itself and never asks for: its job and level,
    the Afflatus buffs (417 Solace, 418 Misery), Divine Seal (78) and Divine
    Seal's recast. So the frames carry only what the server alone knows.

    Packet budget (the AutoAcc lesson): one request per zone while the main
    job is WHM, and pushes only when something the gauge DRAWS changes. The
    server rounds the charge to twentieths before it compares, and holds
    charge-only changes to one frame a second. Flower, stance and flag
    changes go at once.

    Envelope (every 0x1E0 here): 4-byte packet header, then
      4 u8 op   5 u8 seq   6 u8 status   7 u8 flags   8.. payload
    Little-endian, offsets 0-based into the payload.

    0xD0 SUBSCRIBE  client -> server, payload 4 bytes:
         0 u8 proto (1)   1 u8 mode (1 subscribe, 0 stop)   2 u16 0
    0xD0 reply      server -> client, same seq, status 0 = OK, payload = STATE.
         BUSY (3): more than one subscribe a second; ask again shortly.
         A server without the channel answers nothing, BAD_OP (1) or
         UNAVAILABLE (5).
    0xD8 STATE      server -> client push, seq 0, payload = STATE.

    STATE, 16 bytes:
         0 u8 proto (1)        1 u8 job (3 = WHM)
         2 u8 stance (0 none, 1 Afflatus Solace, 2 Afflatus Misery)
         3 u8 tier             the flower tier your next charge makes (0-3)
         4 u8 flower 1 tier    5 u8 flower 2 tier    6 u8 flower 3 tier
         7 u8 flags            8 u8 boost tier (a flower spent, waiting)
         9 u8 0
        10 u16 charge         12 u16 threshold
        14 u16 rev            (wraps; a push older than the last one is ignored)
    Charge and threshold are in the stance's own unit: HP of Regen healing
    under Solace, TP from melee rounds on Judged monsters under Misery.
]]--

local M = {};

M.PKT = 0x1E0;
M.OP_FIRST, M.OP_LAST = 0xD0, 0xDF;
M.op = { SUBSCRIBE = 0xD0, STATE = 0xD8 };
M.PROTO = 1;
M.STATE_SIZE = 16;
M.JOB_WHM = 3;
M.stance = { NONE = 0, SOLACE = 1, MISERY = 2 };
M.status = { OK = 0, BAD_OP = 1, MALFORMED = 2, BUSY = 3, UNAVAILABLE = 5 };
M.flag = {
    DARK_BANISH = 0x01,   -- Misery: Banish converted to dark
    BOOST       = 0x02,   -- a flower was spent; the next Regen / Banish carries it
    CAPPED      = 0x04,   -- three flowers held and none can be upgraded: charge waits
    SEAL_READY  = 0x08,   -- the server's word that Divine Seal is up (the client reads the recast too)
};

local function u16(s, o)
    local a, b = s:byte(o + 1, o + 2);
    return (a or 0) + (b or 0) * 256;
end
M.u16 = u16;

function M.hasFlag(flags, bit) return (flags or 0) % (bit * 2) >= bit; end

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
-- does not read). Tiers are clamped to 0-3, so a bad byte can never index
-- past the art.
function M.state(p)
    if type(p) ~= 'string' or #p < M.STATE_SIZE then return nil; end
    if p:byte(1) ~= M.PROTO then return nil; end
    local function tier(o)
        local t = p:byte(o + 1) or 0;
        return (t >= 0 and t <= 3) and t or 0;
    end
    local st = p:byte(3) or 0;
    if st > 2 then st = 0; end
    return {
        job       = p:byte(2),
        stance    = st,
        tier      = tier(3),
        flowers   = { tier(4), tier(5), tier(6) },
        flags     = p:byte(8) or 0,
        boost     = tier(8),
        charge    = u16(p, 10),
        threshold = u16(p, 12),
        rev       = u16(p, 14),
    };
end

-- The same STATE as the server builds it (tests and the demo).
function M.encodeState(s)
    local function b(v) v = math.floor(tonumber(v) or 0); if v < 0 then v = 0; end; return string.char(v % 256); end
    local function w(v) v = math.floor(tonumber(v) or 0); if v < 0 then v = 0; end
        v = v % 65536; return string.char(v % 256, math.floor(v / 256)); end
    local f = s.flowers or {};
    return b(M.PROTO) .. b(s.job or M.JOB_WHM) .. b(s.stance) .. b(s.tier)
        .. b(f[1]) .. b(f[2]) .. b(f[3]) .. b(s.flags) .. b(s.boost) .. b(0)
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
