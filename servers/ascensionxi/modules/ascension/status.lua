--[[
    ascensionxi/ascension/status -- the character's per-job ascension counts,
    read from the server on 0x1E0 op 0xA0 (ascensionxi repo,
    documentation/custom/lockstyle-vault-ascension.md). Owns ops 0xA0-0xAF.

        status.tiers() -> { WAR = n, MNK = n, ... } once answered, else nil

    Served to core as the 'prestige' service, which gear\jobgate folds over the
    raw job levels: a job with an ascension reads as level 75, exactly the
    server's lockstyle rule. Unknown (nil) degrades to the raw levels -- too
    tight at worst, never wrongly open.

    Asked SETTLE seconds after each zone-in, at once when a job's level drops
    (ascending takes the job back to level 1), and every REFRESH seconds so a
    GM's !ascension shows without zoning. A server without the op answers
    BAD_OP and the client goes quiet until the next reload.
]]--

local M = { PKT = 0x1E0, OP = 0xA0, SETTLE = 5, RETRY = 5, REFRESH = 60, BACKOFF = 30, LEVEL_CHECK = 1 };

-- The server's job id order (WAR = 1): the order of the reply's count bytes.
M.JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG',
           'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };

M._clock  = os.clock;
M._send   = nil;   -- (packet) -> false when the shared channel is busy
M._levels = nil;   -- () -> { abbr -> raw level } or nil

local tiers, pending, due, dormant, charId, levels, levelsAt, inGame;
local attempts = 0;
local token = os.time() % 0xFFFFFFFF;

local function u16(data, offset)
    return data:byte(offset + 1) + data:byte(offset + 2) * 256;
end
local function u32(data, offset)
    return u16(data, offset) + u16(data, offset + 2) * 65536;
end

-- A zone-in (0x00A) for character id: ask again once the zone settles. The
-- counts survive a zone; they are dropped only when another character logs in.
function M.zoneIn(id)
    if id ~= charId then tiers = nil; end
    charId = id;
    pending, levels, attempts = nil, nil, 0;
    due = M._clock() + M.SETTLE;
end

-- A zone-out (0x00B): nothing is asked until the next zone-in.
function M.zoneOut()
    pending, due = nil, nil;
end

-- Addon load: ask once the character is in game.
function M.reset()
    tiers, pending, dormant, charId, levels, levelsAt, inGame = nil, nil, false, nil, nil, nil, false;
    attempts = 0;
    due = M._clock();
end

function M.tiers() return tiers; end

-- Reads the raw job levels at most once a second. Returns whether the
-- character is in game (any level above zero: pre-login and mid-zone read
-- all zeros) and whether any job's level fell since the last reading.
local function readLevels(now)
    if type(M._levels) ~= 'function' then return true, false; end
    if levelsAt ~= nil and now - levelsAt < M.LEVEL_CHECK then return inGame, false; end
    levelsAt = now;
    local ok, current = pcall(M._levels);
    inGame = false;
    if ok and type(current) == 'table' then
        for _, lv in pairs(current) do
            if (tonumber(lv) or 0) > 0 then inGame = true; break; end
        end
    end
    if not inGame then return false, false; end
    local dropped = false;
    if levels ~= nil then
        for ab, lv in pairs(current) do
            if (tonumber(lv) or 0) < (tonumber(levels[ab]) or 0) then dropped = true; end
        end
    end
    levels = current;
    return true, dropped;
end

function M.touch()
    local now = M._clock();
    if dormant or due == nil or type(M._send) ~= 'function' then return; end
    local ready, dropped = readLevels(now);
    if not ready or (now < due and not dropped) then return; end
    if pending and attempts >= 2 then pending = nil; end
    if not pending then attempts = 0; end
    -- Retry an unanswered request with its original token; a later reply to
    -- an older token is ignored.
    local nextToken = pending or ((token + 1) % 0x100000000);
    local packet = { 0, 0, 0, 0, M.OP, nextToken % 256, 0, 0, 1, 0, 0, 0 };
    for i = 0, 3 do packet[13 + i] = math.floor(nextToken / (256 ^ i)) % 256; end
    local ok, sent = pcall(M._send, packet);
    if not ok or sent == false then
        due = now + 0.35;   -- shared channel busy: retry on a later touch
        return;
    end
    token, pending = nextToken, nextToken;
    attempts = attempts + 1;
    due = now + M.RETRY;
end

-- One inbound 0x1E0. Returns true when the frame is ours (the caller blocks
-- it: the retail client has no handler for the channel).
function M.onPacket(data)
    if type(data) ~= 'string' or #data < 8 then return false; end
    local op, seq, code, flags = data:byte(5, 8);
    if op < 0xA0 or op > 0xAF then return false; end
    if M._received then M._received(op, seq); end
    if op ~= M.OP or pending == nil or seq ~= pending % 256 then return true; end
    if code == 1 or code == 6 then   -- BAD_OP / PROTO_UNSUPPORTED: no such op here
        dormant, pending, tiers = true, nil, nil;
        return true;
    end
    if code ~= 0 then
        pending = nil;
        due = M._clock() + (code == 3 and M.RETRY or M.BACKOFF);
        return true;
    end
    -- Ashita hands over a 512-byte buffer; the header's size field (four-byte
    -- words above the nine-bit id) says how much of it is the 40-byte frame.
    local wireSize = math.floor(u16(data, 0) / 512) * 4;
    if wireSize ~= 40 or #data < wireSize or flags ~= 0 or u16(data, 8) ~= 1 or u16(data, 10) ~= #M.JOBS
        or u32(data, 12) ~= pending then return true; end
    local out = {};
    for i, ab in ipairs(M.JOBS) do out[ab] = data:byte(16 + i); end
    tiers = out;
    pending = nil;
    due = M._clock() + M.REFRESH;
    return true;
end

return M;
