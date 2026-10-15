-- Silent, self-only Fishing snapshot: Fishing points, the skill in tenths,
-- the Mog Wardrobe slots bought from Fennella and the guild rank. Op 0x83 in
-- the HELM partition (0x80-0x8F) on 0x1E0; wire contract in the server's
-- documentation/custom/dlac-fishing.md.
--
-- Asked when something can have changed it, not on a clock (the AXI packet
-- budget; docs/reference/ascensionxi-fishing.md): when a surface first shows
-- it, a second after each reel (a landed fish banks its points), a second
-- after an event option (Fennella's shelf), and otherwise once a minute while
-- a surface is up. Nothing is asked while no surface shows it.
local M = { PKT = 0x1E0, OP = 0x83, REFRESH_S = 60, AFTER_S = 1, SETTLE_S = 5,
            RETRY_S = 5, BUSY_S = 1.5, SEND_S = 0.35, OFF_S = 30 };
M._clock = os.clock;
M._send = nil;
local snapshot, pending, due, dormant, again;
local attempts = 0;
local token = (os.time() + 104729) % 0xFFFFFFFF;

local function u16(data, offset)
    return data:byte(offset + 1) + data:byte(offset + 2) * 256;
end
local function u32(data, offset)
    return u16(data, offset) + u16(data, offset + 2) * 65536;
end

function M.reset(settle)
    snapshot, pending, dormant, again = nil, nil, false, false;
    attempts = 0;
    due = M._clock() + (settle and M.SETTLE_S or 0);
    -- Keep token monotonic across zone/character resets, rejecting late replies.
end

-- { points, skill (tenths as a decimal), slots, rank } or nil until the
-- server has answered.
function M.value() return snapshot; end

-- Something the server counts may have changed: ask again `delay` seconds
-- from now, or sooner if a request was due anyway. A request already out
-- answers for before the change, so its reply schedules one more.
function M.markStale(delay)
    if dormant then return; end
    local at = M._clock() + (delay or M.AFTER_S);
    if due == nil or at < due then due = at; end
    if pending ~= nil then again = true; end
end

-- Called by every surface showing fishing points; asks only when due.
function M.touch()
    local now = M._clock();
    if dormant or now < (due or 0) or type(M._send) ~= 'function' then return; end
    if pending and attempts >= 2 then pending = nil; end
    if not pending then attempts = 0; end
    -- Retry an unanswered request with its original token.
    local nextToken = pending or ((token + 1) % 0x100000000);
    due = now + M.RETRY_S;
    local packet = { 0, 0, 0, 0, M.OP, nextToken % 256, 0, 0, 1, 0, 0, 0 };
    for i = 0, 3 do packet[13 + i] = math.floor(nextToken / (256 ^ i)) % 256; end
    local ok, sent = pcall(M._send, packet);
    if not ok or sent == false then
        due = now + M.SEND_S; -- shared channel busy: retry on a later touch
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
    if status == 3 then                  -- asked twice inside the server's second
        pending, due = nil, M._clock() + M.BUSY_S;
        return true;
    end
    if status ~= 0 then
        pending, snapshot = nil, nil;
        due = M._clock() + M.OFF_S;
        return true;
    end
    -- Ashita hands over a 512-byte buffer; the header carries the wire size.
    local wireSize = math.floor(u16(data, 0) / 512) * 4;
    if wireSize ~= 24 or #data < wireSize or flags ~= 0 or u16(data, 8) ~= 1 or u16(data, 10) ~= 0
        or u32(data, 12) ~= pending then return true; end
    local skill, slots, rank = u16(data, 20), data:byte(23), data:byte(24);
    if skill > 1100 or rank > 10 then return true; end
    snapshot = { points = u32(data, 16), skill = skill / 10, slots = slots, rank = rank };
    pending = nil;
    due = M._clock() + (again and M.AFTER_S or M.REFRESH_S);
    again = false;
    return true;
end

return M;
