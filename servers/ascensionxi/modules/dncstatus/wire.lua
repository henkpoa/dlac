--[[
    ascensionxi/dncstatus/wire -- the bytes of the Dancer's slot on
    AscensionXI's job gauge channel (0x1E0 ops 0xD0-0xDF), pure: no Ashita,
    no state. The server's codec is modules/custom/lua/job_gauge_wire.lua in
    the ascensionxi repo; the contract is documentation/custom/dnc-status.md
    there. A shared 28-byte vector is pinned in both suites.

    The partition is shared by job: the slot is op % 8. Slot 0 is the White
    Mage flower gauge (0xD0, 0xD8; whmgauge/wire.lua), slot 1 is the Dancer
    (0xD1, 0xD9). Each module reads only its own slot's ops.

    Why a channel at all: three things a Dancer wants to see live only on the
    server. Perpetual Step's memory is the buff's power, which the client
    never gets; the Dazes on a monster are invisible to the client; and the
    prices and caps are the server's tuning. What the client CAN see it reads
    itself and never asks for: its job, level and TP, the Perpetual Step buff
    and its timer, the Unbroken Rhythm stack icons and their timer, Trance.

    Packet budget (the AutoAcc lesson): one request per zone, only while the
    main job is Dancer and a dlac surface is showing the status. The server
    pushes only when something drawn changes: the memory, the battle target,
    a Daze's level, or a Daze's end moving by 2 s or more. The client counts
    the seconds down itself.

    Envelope (every 0x1E0 here): 4-byte packet header, then
      4 u8 op   5 u8 seq   6 u8 status   7 u8 flags   8.. payload
    Little-endian, offsets 0-based into the payload.

    0xD1 SUBSCRIBE  client -> server, payload 4 bytes:
         0 u8 proto (1)   1 u8 mode (1 subscribe, 0 stop)   2 u16 0
    0xD1 reply      server -> client, same seq, status 0 = OK, payload = STATE.
         BUSY (3): more than one subscribe a second; ask again shortly.
         A server without the slot answers BAD_OP (1), UNAVAILABLE (5) or
         nothing.
    0xD9 STATE      server -> client push, seq 0, payload = STATE.

    STATE, 28 bytes:
         0 u8  proto (1)          1 u8 job (19 = DNC)
         2 u16 memory             Perpetual Step's power: 4 bits per Step,
                                  Quickstep lowest (0 = no buff)
         4 u16 target             the battle target's entity index while
                                  engaged to a live monster, else 0
         6 u8  level x4           the Daze of each Step on that target
        10 u16 seconds x4         whole seconds left of each Daze, rounded up,
                                  when the frame was built
        18 u16 price x3           Unbroken Rhythm TP for the 1st, 2nd and 3rd
                                  stack (the 3rd is also the refresh at 3)
        24 u8  base levels        what Perpetual Step applies with no stacks
        25 u8  levels per stack   what each Unbroken Rhythm stack adds
        26 u16 rev                (wraps; a push older than the last is ignored)
    The Step order everywhere: Quickstep, Box Step, Stutter Step, Feather Step.
]]--

local M = {};

M.PKT = 0x1E0;
M.OP_FIRST, M.OP_LAST = 0xD0, 0xDF;
M.SLOT = 1;
M.op = { SUBSCRIBE = 0xD1, STATE = 0xD9 };
M.PROTO = 1;
M.STATE_SIZE = 28;
M.JOB_DNC = 19;
M.status = { OK = 0, BAD_OP = 1, MALFORMED = 2, BUSY = 3, UNAVAILABLE = 5 };
M.STEPS = { 'Quickstep', 'Box Step', 'Stutter Step', 'Feather Step' };

local function u16(s, o)
    local a, b = s:byte(o + 1, o + 2);
    return (a or 0) + (b or 0) * 256;
end
M.u16 = u16;

-- Is this 0x1E0 op one of ours (slot 1 of the job gauge partition)?
function M.ours(op)
    return type(op) == 'number' and op >= M.OP_FIRST and op <= M.OP_LAST and op % 8 == M.SLOT;
end

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

-- The four Step levels packed in a Perpetual Step power, Quickstep first.
function M.memoryLevels(power)
    power = math.floor(tonumber(power) or 0);
    local out = {};
    for i = 1, 4 do
        out[i] = power % 16;
        power = math.floor(power / 16);
    end
    return out;
end

-- A STATE payload as a table, or nil (short, or a protocol this client does
-- not read). Levels are clamped to 0-15, so a bad byte can never show as a
-- Step level no Dancer can reach.
function M.state(p)
    if type(p) ~= 'string' or #p < M.STATE_SIZE then return nil; end
    if p:byte(1) ~= M.PROTO then return nil; end
    local levels, seconds = {}, {};
    for i = 1, 4 do
        local l = p:byte(6 + i) or 0;
        levels[i] = (l <= 15) and l or 15;
        seconds[i] = (levels[i] > 0) and u16(p, 8 + 2 * i) or 0;
    end
    local memory = u16(p, 2);
    return {
        job      = p:byte(2),
        memory   = memory,
        memoryLevels = M.memoryLevels(memory),
        target   = u16(p, 4),
        levels   = levels,
        seconds  = seconds,
        prices   = { u16(p, 18), u16(p, 20), u16(p, 22) },
        base     = p:byte(25) or 0,
        perStack = p:byte(26) or 0,
        rev      = u16(p, 26),
    };
end

-- The same STATE as the server builds it (tests and the demo).
function M.encodeState(s)
    local function b(v) v = math.floor(tonumber(v) or 0); if v < 0 then v = 0; end
        if v > 255 then v = 255; end; return string.char(v); end
    local function w(v) v = math.floor(tonumber(v) or 0); if v < 0 then v = 0; end
        v = v % 65536; return string.char(v % 256, math.floor(v / 256)); end
    local l, sec, pr = s.levels or {}, s.seconds or {}, s.prices or {};
    return b(M.PROTO) .. b(s.job or M.JOB_DNC) .. w(s.memory) .. w(s.target)
        .. b(l[1]) .. b(l[2]) .. b(l[3]) .. b(l[4])
        .. w(sec[1]) .. w(sec[2]) .. w(sec[3]) .. w(sec[4])
        .. w(pr[1]) .. w(pr[2]) .. w(pr[3])
        .. b(s.base) .. b(s.perStack) .. w(s.rev);
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
