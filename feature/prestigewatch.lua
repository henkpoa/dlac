--[[
    dlac/prestigewatch.lua -- the CatsEyeXI PRESTIGE mirror (2026-08-10).

    WHY THIS EXISTS: a field report -- a prestiged PLD typed "valor" into the
    lockstyle Head picker and was told nothing in the game matches. Prestige
    (CatsEyeXI custom: reset a job to Lv1 for a permanent bonus, tiers 1-5)
    WAIVES gear level requirements on that job server-side, but every dlac
    mirror of canEquipItemOnAnyJob read GetJobLevel alone, so the post-reset
    level slammed the gate shut. jobgate folds the tiers this module learns
    into its levels() read (a prestiged job reports effective level 75); this
    module's whole job is knowing the tiers.

    THE WIRE (sibling authority: trove/plugins/profile.lua + utils/packet.lua
    -- Trove's Profile window shows these same stars): custom packet 0x1A4,
    both directions. Request: 64 zero bytes, action 17 (GET_PLUGIN_DATA) at
    offset 0x04, pluginId 1 at offset 0x06. Reply: action 17 at 0x04, pluginId
    1 at 0x05, then the PRESTIGE TIERS -- one byte per job, jobs 1..22 in
    client order (WAR..RUN, jobgate.JOBS) -- at offsets 0x06..0x1B. (The same
    blob carries craft skills / isCW / per-job EXP beyond 0x1B; not read here.)
    0x1A4 is addon-only wire: the real client must never see it, so the
    packet_in handler sets e.blocked -- exactly what Trove does. Listening is
    PASSIVE too: a reply Trove requested teaches us just the same.

    The server side lives in the hidden cexi submodules; the public clone's
    `prestige` field (char_points / 0x113) is base-LSB Monstrosity currency --
    a false friend, nothing to do with this system.

    HENRIK'S LAW (2026-08-10): prestige can NEVER be lost. So the persisted
    file is a floor, merge is a per-job MAX, and nothing ever invalidates it --
    a stale read can only be too LOW (gate too tight until the next reply),
    never wrongly open.

    THREADING (the chocowatch rule): the packet_in handler only parses and
    STASHES on the network thread -- no chat, no IO. M.pump() (dlac's
    seed-watch, main thread) drains the stash, merges, persists to
    <char>\dlac\prestige.lua and sends the request -- once per zone-in, a
    couple of retries, then quiet. Pure helpers are headless-testable; every
    Ashita touch is guarded at call time.
]]--

local M = {};

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

-- <char>\dlac\ dir: the one addon-side copy (lib\statefile). nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;
M._charDir = charDir;   -- test seam

-- Job index -> abbr: jobgate.JOBS is the one home (the wire's 1..22 order IS
-- that list). No local copy -- a drifted twin here would mislabel every tier.
local _jgok, _jobgate = pcall(require, 'dlac\\gear\\jobgate');
_jgok = _jgok and type(_jobgate) == 'table' and type(_jobgate.JOBS) == 'table';

M.PACKET_ID = 0x1A4;   -- Trove's custom channel, both directions
M.ACTION    = 17;      -- C2S GET_PLUGIN_DATA / S2C PLUGIN_DATA
M.PLUGIN_ID = 1;       -- the Profile blob (prestige + crafts + exp)

-- ---------------------------------------------------------------------------
-- State. _arr is the merged truth as a 1..22 array (nil until anything is
-- known); the abbr view is built on demand (M.tiers). _wire is the network-
-- thread stash the pump drains.
-- ---------------------------------------------------------------------------
M._arr       = nil;    -- [1..22] = tier, merged (persisted floor + wire)
M._loadedFor = nil;    -- the charDir the state was loaded for (char-switch guard)
M._wire      = {};     -- parsed arrays awaiting the main-thread pump
M._gotReply  = false;  -- a reply landed since the last (re)quest cycle
M._tries     = 0;      -- requests sent this cycle (cap 3, then quiet)
M._nextReqAt = 0;      -- os.clock() gate for the next request

-- ---------------------------------------------------------------------------
-- Pure core (headless-tested, PW section).
-- ---------------------------------------------------------------------------

-- 0x1A4 wire data (header included) -> tiers array [1..22], or nil when the
-- packet is not a pluginId-1 PLUGIN_DATA reply (other Trove traffic, short
-- packet). Offsets are 0-based wire positions; string.byte is 1-based.
function M.parse1A4(data)
    if type(data) ~= 'string' or #data < 0x1C then return nil; end
    if string.byte(data, 0x04 + 1) ~= M.ACTION then return nil; end
    if string.byte(data, 0x05 + 1) ~= M.PLUGIN_ID then return nil; end
    local t = {};
    for i = 1, 22 do
        t[i] = string.byte(data, 0x06 + (i - 1) + 1) or 0;
    end
    return t;
end

-- Monotonic merge (Henrik's law: prestige is never lost): per job the MAX of
-- the known floor and the wire read. Returns (merged, changed).
function M._merge(old, wire)
    local out, changed = {}, false;
    for i = 1, 22 do
        local a = tonumber(type(old) == 'table' and old[i] or nil) or 0;
        local b = tonumber(type(wire) == 'table' and wire[i] or nil) or 0;
        out[i] = (a >= b) and a or b;
        if out[i] ~= a then changed = true; end
    end
    return out, changed;
end

-- The request bytes (pure): 64 zeros, action at wire offset 0x04 (table index
-- 5), pluginId at 0x06 (index 7) -- byte-for-byte Trove's requestData.
function M._requestPacket()
    local p = {};
    for i = 1, 64 do p[i] = 0; end
    p[5] = M.ACTION;
    p[7] = M.PLUGIN_ID;
    return p;
end

-- The persisted form: a plain 22-number array literal.
function M._serialize(arr)
    local n = {};
    for i = 1, 22 do n[i] = tostring(tonumber(type(arr) == 'table' and arr[i] or nil) or 0); end
    return 'return { ' .. table.concat(n, ', ') .. ' }\n';
end

-- ---------------------------------------------------------------------------
-- The consumer view: { abbr -> tier } for the jobs with any prestige, or nil
-- when nothing is known yet (jobgate's fold is then a no-op -- the gate
-- behaves exactly as before this module existed).
-- ---------------------------------------------------------------------------
function M.tiers()
    if type(M._arr) ~= 'table' or not _jgok then return nil; end
    local out = {};
    for i, ab in ipairs(_jobgate.JOBS) do
        local v = tonumber(M._arr[i]) or 0;
        if v > 0 then out[ab] = v; end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- Persistence (<char>\dlac\prestige.lua) + the char-switch guard: addons
-- survive logout, so a different character logging in must NOT inherit the
-- previous one's tiers (an equip gate wrongly opened). Keyed on charDir.
-- ---------------------------------------------------------------------------
local function statePath(dir) return dir and (dir .. 'prestige.lua') or nil; end

local function saveState()
    pcall(function()
        local p = statePath(M._loadedFor);
        if p == nil or M._arr == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(M._serialize(M._arr));
        f:close();
    end);
end
M._saveState = saveState;   -- test seam

function M.loadState()
    local dir = charDir();
    if dir == nil or dir == M._loadedFor then return; end
    -- New character (or first login): drop the old identity's tiers wholesale
    -- and start a fresh request cycle. The persisted floor is per-char by path.
    M._loadedFor = dir;
    M._arr       = nil;
    M._gotReply  = false;
    M._tries     = 0;
    M._nextReqAt = os.clock() + 3.0;   -- give the zone-in a beat before asking
    pcall(function()
        local chunk = loadfile(statePath(dir));
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then M._arr = (M._merge(nil, t)); end
    end);
end

-- ---------------------------------------------------------------------------
-- The main-thread beat (dlac's seed-watch): drain, merge, persist, request.
-- ---------------------------------------------------------------------------
local function sendRequest()
    pcall(function()
        AshitaCore:GetPacketManager():AddOutgoingPacket(M.PACKET_ID, M._requestPacket());
    end);
end

function M.pump()
    M.loadState();
    if M._loadedFor == nil then return; end   -- pre-login: retry next beat
    if #M._wire > 0 then
        local changed = false;
        for _, arr in ipairs(M._wire) do
            local merged, ch = M._merge(M._arr, arr);
            M._arr = merged;
            changed = changed or ch;
            M._gotReply = true;
        end
        M._wire = {};
        if changed then saveState(); end
    end
    if not M._gotReply and M._tries < 3 and os.clock() >= M._nextReqAt then
        M._tries    = M._tries + 1;
        M._nextReqAt = os.clock() + 10.0;
        sendRequest();
    end
end

-- ---------------------------------------------------------------------------
-- Ashita glue (guarded -- headless suites load everything above freely).
-- ---------------------------------------------------------------------------
if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac-prestigewatch-in', function(e)
        -- Zone-in: start one fresh request cycle (a prestige taken mid-session
        -- is learned at the next zone instead of the next logon). Bare flag
        -- writes -- packet-thread safe.
        if e.id == 0x00A then
            M._gotReply  = false;
            M._tries     = 0;
            M._nextReqAt = os.clock() + 5.0;
            return;
        end
        if e.id ~= M.PACKET_ID then return; end
        -- Addon-only wire: the real client must never see 0x1A4 (Trove blocks
        -- it too; the flag hides it from the CLIENT, never from other addons).
        e.blocked = true;
        local arr = M.parse1A4(e.data);
        if arr ~= nil then M._wire[#M._wire + 1] = arr; end
        -- parse + stash only -- no chat, no IO on the packet thread (the
        -- chocowatch rule).
    end);

    -- /dl prestige -- HIDDEN diagnostic (not in any help list): what the mirror
    -- knows, where it came from, and a forced re-ask (the mid-session prestige
    -- path when you don't feel like zoning).
    ashita.events.register('command', 'dlac-prestigewatch-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local a = raw:match('^/dl%s+(%S+)') or raw:match('^/dlac%s+(%S+)');
            if a ~= 'prestige' then return; end
            e.blocked = true;
            local t = M.tiers();
            if t == nil or next(t) == nil then
                say('Prestige -- none known' .. (M._gotReply and ' (server replied: no prestiged jobs)' or ' yet') .. '.');
            else
                local parts = {};
                if _jgok then
                    for _, ab in ipairs(_jobgate.JOBS) do
                        if t[ab] ~= nil then parts[#parts + 1] = string.format('%s %d', ab, t[ab]); end
                    end
                end
                say('Prestige -- ' .. table.concat(parts, ', ')
                    .. (M._gotReply and ' (wire this session)' or ' (persisted floor; no reply yet)') .. '.');
            end
            M._gotReply  = false;
            M._tries     = 0;
            M._nextReqAt = 0;   -- the next pump beat re-asks immediately
            say('Asked the server for a fresh read.');
        end);
    end);
end

return M;
