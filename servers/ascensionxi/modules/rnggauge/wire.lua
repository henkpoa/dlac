-- Ranger recovery, slot 3 of the AscensionXI job-gauge channel.
-- STATE: u8 proto/job/enabled/phase, u32 remaining/total ms, u16 revision.
local M = { PKT = 0x1E0, PROTO = 1, JOB_RNG = 11, STATE_SIZE = 14,
    op = { SUBSCRIBE = 0xD3, STATE = 0xDB },
    status = { OK = 0, BAD_OP = 1, MALFORMED = 2, BUSY = 3, UNAVAILABLE = 5 } };
local function u16(s, o) local a, b = s:byte(o + 1, o + 2); return (a or 0) + (b or 0) * 256; end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536; end
function M.ours(op) return op == M.op.SUBSCRIBE or op == M.op.STATE; end
function M.subscribe(seq, on)
    return { 0, 0, 0, 0, M.op.SUBSCRIBE, seq % 256, 0, 0, M.PROTO, on and 1 or 0, 0, 0 };
end
function M.incoming(data)
    if type(data) ~= 'string' or #data < 8 then return nil; end
    local size = math.floor(u16(data, 0) / 512) * 4;
    if size < 8 or size > #data then return nil; end
    return { op = data:byte(5), seq = data:byte(6), status = data:byte(7), payload = data:sub(9, size) };
end
function M.state(p)
    if type(p) ~= 'string' or #p < M.STATE_SIZE or p:byte(1) ~= M.PROTO or p:byte(2) ~= M.JOB_RNG then return nil; end
    if p:byte(3) > 1 or p:byte(4) > 2 then return nil; end
    local remaining, total = u32(p, 4), u32(p, 8);
    if remaining > total then return nil; end
    return { enabled = p:byte(3) == 1, phase = p:byte(4), remaining = remaining,
        total = total, rev = u16(p, 12) };
end
function M.encodeState(s)
    local function w(n) n = math.max(0, math.min(65535, math.floor(n or 0))); return string.char(n % 256, math.floor(n / 256)); end
    local function d(n) n = math.max(0, math.min(4294967295, math.floor(n or 0))); return w(n % 65536) .. w(math.floor(n / 65536)); end
    return string.char(M.PROTO, M.JOB_RNG, s.enabled and 1 or 0, s.phase or 0)
        .. d(s.remaining) .. d(s.total) .. w((s.rev or 0) % 65536);
end
function M.newer(a, b) local d = (a - b) % 65536; return d > 0 and d < 32768; end
return M;
