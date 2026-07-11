--[[
    dlac/useitem.lua

    Panic enchantment commands (shatter escapes and friends):
        /dl p          lock Ring2, equip the Provenance Ring, wait out its equip
                       delay, use it with /item, then release the slot.
        /dl w          same with the Warp Ring (shorter delay).
        /dl p off      cancel a pending use and release the slot (also: w off).

    Runs in the ADDON state: native /equip + /item bypass LuaAshitacast; the
    engine lock (/dl lock ring2) stops dlac dispatch from swapping the ring back
    out mid-countdown, and /lac disable ring2 covers hand-written profile code.
    Waits carry a safety margin over the in-game equip delay -- firing /item too
    early wastes the attempt, firing late costs nothing but nerves.
]]--

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
local print = (_cfok and type(_cfmt) == 'table' and type(_cfmt.print) == 'function') and _cfmt.print or print;

local M = {};

local SLOT = 'ring2';
local ITEMS = {
    p = { name = 'Provenance Ring', wait = 18 },   -- 15s equip delay + margin
    w = { name = 'Warp Ring',       wait = 10 },   --  8s equip delay + margin
};

local state = nil;   -- { name, useAt, stage = 'wait'|'used', releaseAt }

local function queue(cmd)
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
end

local function release()
    queue('/dl lock ' .. SLOT .. ' off');
    queue('/lac enable ' .. SLOT);
end

local function start(key)
    local def = ITEMS[key];
    if def == nil then return; end
    queue('/dl lock ' .. SLOT .. ' on');
    queue('/lac disable ' .. SLOT);
    queue('/equip ' .. SLOT .. ' "' .. def.name .. '"');
    state = { name = def.name, useAt = os.clock() + def.wait, stage = 'wait' };
    print(string.format('[dlac] %s equipped in %s -- using in %d seconds  (/dl %s off cancels)',
        def.name, SLOT, def.wait, key));
end

local function cancel()
    if state == nil then print('[dlac] nothing pending.'); return; end
    print('[dlac] ' .. state.name .. ' use cancelled -- ' .. SLOT .. ' released.');
    state = nil;
    release();
end

ashita.events.register('d3d_present', 'dlac-useitem-tick', function()
    if state == nil then return; end
    local now = os.clock();
    if state.stage == 'wait' and now >= state.useAt then
        queue('/item "' .. state.name .. '" <me>');
        print('[dlac] using ' .. state.name .. ' NOW.');
        state.stage = 'used';
        state.releaseAt = now + 3;                 -- give the use a moment, then unlock
    elseif state.stage == 'used' and now >= state.releaseAt then
        state = nil;
        release();
    end
end);

local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'   or string.sub(raw, 1, 4)  == '/dl '   then return 5; end
    return nil;
end

ashita.events.register('command', 'dlac-useitem', function(e)
    local raw = string.lower(e.command);
    local s = argStart(raw);
    if s == nil then return; end
    local args = {};
    for a in string.gmatch(string.sub(raw, s), '[^%s]+') do args[#args + 1] = a; end
    local sub = args[1];
    if sub ~= 'p' and sub ~= 'w' then return; end
    e.blocked = true;
    if args[2] == 'off' or args[2] == 'cancel' or args[2] == 'stop' then cancel(); return; end
    start(sub);
end);

return M;
