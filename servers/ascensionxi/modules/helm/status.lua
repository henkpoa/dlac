-- Silent, self-only HELM snapshot. Owns only ops 0x80-0x8F on 0x1E0;
-- void storage and gear vault keep their existing partitions.
local skills = require('dlac\\servers\\ascensionxi\\modules\\helm\\skills');
local M = { PKT = 0x1E0, OP = 0x80, POLL_SECONDS = 5 };
M._clock = os.clock;
M._send = nil;
local balance, pending, due, dormant;
local attempts = 0;
local token = os.time() % 0xFFFFFFFF;

local function u16(data, offset)
    return data:byte(offset + 1) + data:byte(offset + 2) * 256;
end
local function u32(data, offset)
    return u16(data, offset) + u16(data, offset + 2) * 65536;
end

function M.reset(settle)
    balance, pending, dormant = nil, nil, false;
    attempts = 0;
    due = M._clock() + (settle and 5 or 0);
    skills.reset();
    -- Keep token monotonic across zone/character resets, rejecting late replies.
end

function M.value() return balance; end

function M.touch()
    local now = M._clock();
    if dormant or now < (due or 0) or type(M._send) ~= 'function' then return; end
    if pending and attempts >= 2 then pending = nil; end
    if not pending then attempts = 0; end
    -- Retry an unanswered poll with its original token. Do not replace the
    -- outstanding request while a shared-channel denial delays the retry.
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

function M.onPacket(data)
    if type(data) ~= 'string' or #data < 8 then return false; end
    local op, seq, status, flags = data:byte(5, 8);
    if op < 0x80 or op > 0x8F then return false; end
    if M._received then M._received(op, seq); end
    -- Block our partition even when late/malformed: the retail client has
    -- no handler for it. Never consume another addon's storage replies.
    if op ~= M.OP or pending == nil or seq ~= pending % 256 then return true; end
    if status == 1 or status == 6 then
        dormant, pending, balance = true, nil, nil;
        skills.reset();
        return true;
    end
    if status ~= 0 then
        pending = nil;
        balance = nil;
        skills.reset();
        due = M._clock() + (status == 3 and M.POLL_SECONDS or 30);
        return true;
    end
    -- Ashita exposes a 512-byte backing buffer, even for a 28-byte reply.
    -- The transport header stores the wire length in four-byte words above
    -- the nine-bit opcode. Validate that length, and require enough bytes.
    local wireSize = math.floor(u16(data, 0) / 512) * 4;
    if wireSize ~= 28 or #data < wireSize or flags ~= 0 or u16(data, 8) ~= 1 or u16(data, 10) ~= 0
        or u32(data, 12) ~= pending then return true; end
    local values = {};
    for i, category in ipairs({ 'Harvesting', 'Excavation', 'Logging', 'Mining' }) do
        local raw = u16(data, 18 + i * 2);
        if raw > 1000 then return true; end
        values[category] = raw / 10;
    end
    balance = u32(data, 16);
    skills.set(values);
    pending = nil;
    return true;
end

return M;
