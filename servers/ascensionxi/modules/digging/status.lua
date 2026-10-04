-- Silent, self-only Chocobo Digging snapshot: what !digging shows plus the
-- Gysahl Greens stored in Void Storage. Op 0x81 in the HELM partition
-- (0x80-0x8F) on 0x1E0; wire contract in the server's
-- documentation/custom/chocobo-digging-hobby.md.
local M = { PKT = 0x1E0, OP = 0x81, POLL_SECONDS = 5 };
M._clock = os.clock;
M._send = nil;
local snapshot, pending, due, dormant;
local attempts = 0;
local token = (os.time() + 7919) % 0xFFFFFFFF;

local function u16(data, offset)
    return data:byte(offset + 1) + data:byte(offset + 2) * 256;
end
local function u32(data, offset)
    return u16(data, offset) + u16(data, offset + 2) * 65536;
end

function M.reset(settle)
    snapshot, pending, dormant = nil, nil, false;
    attempts = 0;
    due = M._clock() + (settle and 5 or 0);
end

-- { skill, rank, allowance, cap, credit, delay, voidAccess, storedGreens,
--   refillIn() } or nil until the server has answered.
function M.value() return snapshot; end

-- The server's dig rank (exact), or nil while unknown.
function M.rank() return snapshot and snapshot.rank or nil; end

-- Called by every surface showing digging data; polls while any is visible.
function M.touch()
    local now = M._clock();
    if dormant or now < (due or 0) or type(M._send) ~= 'function' then return; end
    if pending and attempts >= 2 then pending = nil; end
    if not pending then attempts = 0; end
    local nextToken = pending or ((token + 1) % 0x100000000);
    due = now + M.POLL_SECONDS;
    local packet = { 0, 0, 0, 0, M.OP, nextToken % 256, 0, 0, 1, 0, 0, 0 };
    for i = 0, 3 do packet[13 + i] = math.floor(nextToken / (256 ^ i)) % 256; end
    local ok, sent = pcall(M._send, packet);
    if not ok or sent == false then
        due = now + 0.35; -- shared channel busy: retry on a later touch
    else
        token, pending = nextToken, nextToken;
        attempts = attempts + 1;
    end
end

-- Our reply only; the HELM module blocks the rest of the partition.
function M.onPacket(data)
    if type(data) ~= 'string' or #data < 8 then return false; end
    local op, seq, status, flags = data:byte(5, 8);
    if op ~= M.OP then return false; end
    if M._received then M._received(op, seq); end
    if pending == nil or seq ~= pending % 256 then return true; end
    if status == 1 or status == 6 then   -- an older server: stop asking
        dormant, pending, snapshot = true, nil, nil;
        return true;
    end
    if status ~= 0 then
        pending, snapshot = nil, nil;
        due = M._clock() + (status == 3 and M.POLL_SECONDS or 30);
        return true;
    end
    -- Ashita hands over a 512-byte buffer; the header carries the wire size.
    local wireSize = math.floor(u16(data, 0) / 512) * 4;
    if wireSize ~= 36 or #data < wireSize or flags ~= 0 or u16(data, 8) ~= 1 or u16(data, 10) ~= 0
        or u32(data, 12) ~= pending then return true; end
    local skill, rank = u16(data, 16), data:byte(27);
    if skill > 1000 or rank > 10 then return true; end
    local at, refill = M._clock(), u32(data, 28);
    snapshot = {
        skill = skill / 10,
        rank = rank,
        allowance = u16(data, 18),
        cap = u16(data, 20),
        credit = u16(data, 22),
        delay = u16(data, 24),
        voidAccess = data:byte(28) % 2 == 1,
        storedGreens = u32(data, 32),
        refillIn = function() return math.max(0, refill - (M._clock() - at)); end,
    };
    pending = nil;
    return true;
end

return M;
