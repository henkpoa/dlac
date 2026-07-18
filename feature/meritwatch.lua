--[[
    dlac/meritwatch.lua -- passive Max MP merit learner (s2c 0x08C).

    Can merits be read from memory? NO -- Ashita's IPlayer exposes only the
    unspent pool (GetMeritPoints/Max), never per-category allocations. The
    allocations exist client-side only while the merit MENU is populated,
    and the server sends them in GP_SERV_COMMAND_MERIT (0x08C, stable
    packets/s2c/0x08c_merit.h):

        u16 merit_count; u16 pad; { u16 id; u8 next; u8 count; } x N

    The full list (5 packets x 61 entries) flows when the merit menu opens;
    a SINGLE-entry form flows on every merit raise/lower. So dlac listens:
    open the menu once, ever, and mpMerits (merits.sql id 66 'max_mp')
    teaches itself into the autogear manifest -- and respeccing Max MP while
    dlac runs re-aims the Oneiros threshold live. There is NO benign request
    packet to inject (c2s 0x0BE only spends points or flips EXP/Limit mode),
    so unlike the guild-point 0x10F self-request this stays listen-only.

    The manifest write goes through automationsui.setMpMerits -- the same
    clamp (0..10, merit.cpp cap[75]) and autoCommit hot-reload the manual
    input uses; the input stays as the fallback for characters whose menu
    has never been opened.
]]--

local M = {};

M.MERIT_MAX_MP_ID = 66;   -- merits.sql id 66 'max_mp'
M.learned = nil;          -- session mirror: last count seen on the wire (UI hint)

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

-- Pure parser: 0x08C wire data (header included) -> the max_mp COUNT, or nil
-- when the packet carries no max_mp entry (most of the 5 menu chunks won't).
-- Bounds-checked per entry: a short/legacy packet can never over-read.
function M.parse08C(data)
    if type(data) ~= 'string' or #data < 0x0C then return nil; end
    local n = (string.byte(data, 0x04 + 1) or 0) + (string.byte(data, 0x05 + 1) or 0) * 256;
    local found = nil;
    for i = 0, n - 1 do
        local off = 0x08 + i * 4;                       -- {id u16 LE, next u8, count u8}
        if off + 4 > #data then break; end
        local id = (string.byte(data, off + 1) or 0) + (string.byte(data, off + 2) or 0) * 256;
        if id == M.MERIT_MAX_MP_ID then
            found = string.byte(data, off + 4) or 0;
        end
    end
    return found;
end

-- One 0x08C landed: learn max_mp if present. Function-scoped require (the
-- helmui render-time pattern) keeps load order flat; setMpMerits is silent
-- and false when the value is already current.
function M.onMeritPacket(data)
    local n = M.parse08C(data);
    if n == nil then return; end
    M.learned = n;
    local ok, aui = pcall(require, 'dlac\\ui\\automationsui');
    if ok and type(aui) == 'table' and type(aui.setMpMerits) == 'function' then
        if aui.setMpMerits(n) then
            say(string.format('Max MP merits learned from the menu: %d (Oneiros threshold re-aimed).', n));
        end
    end
end

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac-meritwatch-in', function(e)
        if e.id ~= 0x08C then return; end
        pcall(function() M.onMeritPacket(e.data); end);
    end);
end

return M;
