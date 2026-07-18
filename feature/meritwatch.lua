--[[
    dlac/meritwatch.lua -- passive Max MP merit learner (s2c 0x08C).

    Can merits be read from memory? NO -- Ashita's IPlayer exposes only the
    unspent pool (GetMeritPoints/Max), never per-category allocations. And
    there is NO request packet to inject either: the merit system is
    PUSH-ONLY (XiPackets 0x008C -- the client wipes its merit cache at every
    zone and the server re-populates at zone-in; c2s 0x0BE validates Kind to
    {spend, EXP/Limit flip} only, and the 0x061 status bundle carries just
    the point pool). The allocations ride GP_SERV_COMMAND_MERIT (0x08C,
    stable packets/s2c/0x08c_merit.h):

        u16 merit_count; u16 pad; { u16 id; u8 next; u8 count; } x N

    So dlac listens, and the pushes come by themselves: the full list at
    EVERY ZONE-IN (CatsEyeXI sends all entries, zero-counts included -- the
    5x61 full-form), plus a single-entry update on every merit raise/lower.
    mpMerits (merits.sql id 66 'max_mp') teaches itself into the autogear
    manifest at the first zone after this ships and re-syncs forever after;
    respeccing Max MP mid-session re-aims the Oneiros threshold live.
    Removal edge (XiPackets): downgrading a merit's LAST point flags the
    entry by setting the index's low bit (66 -> 67) -- parsed as count 0.

    The manifest write goes through automationsui.setMpMerits -- the same
    clamp (0..10, merit.cpp cap[75]) and autoCommit hot-reload the manual
    input uses; the input stays as the fallback until the first zone/menu.
]]--

local M = {};

M.MERIT_MAX_MP_ID = 66;   -- merits.sql id 66 'max_mp'
M.learned = nil;          -- session mirror: last count seen on the wire (UI hint)

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

-- Pure parser: 0x08C wire data (header included) -> the max_mp COUNT, or nil
-- when the packet carries no max_mp entry (single-update packets for other
-- merits). Bounds-checked per entry: a short/legacy packet can never
-- over-read. Merit ids are even on the wire; an ODD id is the full-removal
-- flag (id|1, XiPackets usage 3) -- that merit is back to 0 points.
function M.parse08C(data)
    if type(data) ~= 'string' or #data < 0x0C then return nil; end
    local n = (string.byte(data, 0x04 + 1) or 0) + (string.byte(data, 0x05 + 1) or 0) * 256;
    local found = nil;
    for i = 0, n - 1 do
        local off = 0x08 + i * 4;                       -- {id u16 LE, next u8, count u8}
        if off + 4 > #data then break; end
        local id = (string.byte(data, off + 1) or 0) + (string.byte(data, off + 2) or 0) * 256;
        local removed = (id % 2 == 1);
        if removed then id = id - 1; end
        if id == M.MERIT_MAX_MP_ID then
            found = removed and 0 or (string.byte(data, off + 4) or 0);
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
            say(string.format('Max MP merits learned: %d (Oneiros threshold re-aimed).', n));
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
