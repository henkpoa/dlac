--[[
    dlac/useitem.lua

    Timed enchantment commands -- equip, wait out the equip delay, /item:
        /dl p              lock Ring2, equip the Provenance Ring, use it (panic escape).
        /dl w              same with the Warp Ring (shorter delay).
        /dl t <where>      lock Ear2, equip the matching teleport earring, use it.
                           <where> matches a destination or alias (norg, jeuno,
                           sandy, bastok...); an ambiguous query lists the options,
                           no argument lists every destination.
        /dl p|w|t off      cancel the pending use and release the slot.

    Runs in the ADDON state: native /equip + /item bypass LuaAshitacast; the
    engine lock (/dl lock <slot>) stops dlac dispatch from swapping the piece back
    out mid-countdown, and /lac disable <slot> covers hand-written profile code.
    Waits carry a safety margin over the in-game equip delay -- firing /item too
    early wastes the attempt, firing late costs nothing but nerves.
]]--

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
local print = (_cfok and type(_cfmt) == 'table' and type(_cfmt.print) == 'function') and _cfmt.print or print;

local M = {};

local RINGS = {
    p = { name = 'Provenance Ring', slot = 'ring2', wait = 18 },   -- 15s equip delay + margin
    w = { name = 'Warp Ring',       slot = 'ring2', wait = 10 },   --  8s equip delay + margin
};

-- Teleport earrings (CatsEyeXI): 30s equip delay + margin, all worn in Ear2.
-- aliases are matched exact -> prefix -> substring; keep them lowercase.
local TELE_WAIT = 32;
local TELEPORTS = {
    { name = 'Nashmau Earring',    dest = 'Nashmau',    aliases = { 'nashmau' } },
    { name = 'Norg Earring',       dest = 'Norg',       aliases = { 'norg' } },
    { name = 'Duchy Earring',      dest = 'Jeuno',      aliases = { 'jeuno', 'duchy' } },
    { name = 'Rabao Earring',      dest = 'Rabao',      aliases = { 'rabao' } },
    { name = 'Selbina Earring',    dest = 'Selbina',    aliases = { 'selbina' } },
    { name = 'Mhaura Earring',     dest = 'Mhaura',     aliases = { 'mhaura' } },
    { name = 'Kingdom Earring',    dest = "San d'Oria", aliases = { 'sandoria', 'sandy', 'sand', 'san', 'kingdom' } },
    { name = 'Federation Earring', dest = 'Windurst',   aliases = { 'windurst', 'windy', 'wind', 'federation' } },
    { name = 'Republic Earring',   dest = 'Bastok',     aliases = { 'bastok', 'republic' } },
};

local state = nil;   -- { name, slot, useAt, stage = 'wait'|'used', releaseAt }

local function queue(cmd)
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
end

local function release(slot)
    queue('/dl lock ' .. slot .. ' off');
    queue('/lac enable ' .. slot);
end

local function start(def, verb, cancelHint)
    if state ~= nil and state.slot ~= def.slot then
        release(state.slot);                           -- switching item type: free the old slot
    end
    queue('/dl lock ' .. def.slot .. ' on');
    queue('/lac disable ' .. def.slot);
    queue('/equip ' .. def.slot .. ' "' .. def.name .. '"');
    state = { name = def.name, slot = def.slot, useAt = os.clock() + def.wait, stage = 'wait' };
    print(string.format('[dlac] %s equipped in %s -- %s in %d seconds  (%s cancels)',
        def.name, def.slot, verb, def.wait, cancelHint));
end

local function cancel()
    if state == nil then print('[dlac] nothing pending.'); return; end
    print('[dlac] ' .. state.name .. ' use cancelled -- ' .. state.slot .. ' released.');
    local slot = state.slot;
    state = nil;
    release(slot);
end

-- Resolve a teleport query: exact alias, then alias/destination prefix, then
-- substring across alias/destination/item name. One hit = go; several = the
-- caller lists them; none = nil.
local function findTeleports(q)
    local exact, prefix, sub = {}, {}, {};
    for _, t in ipairs(TELEPORTS) do
        local hitE, hitP, hitS = false, false, false;
        local hay = { string.lower(t.dest), string.lower(t.name) };
        for _, a in ipairs(t.aliases) do hay[#hay + 1] = a; end
        for _, h in ipairs(hay) do
            if h == q then hitE = true; end
            if string.sub(h, 1, #q) == q then hitP = true; end
            if string.find(h, q, 1, true) ~= nil then hitS = true; end
        end
        if hitE then exact[#exact + 1] = t; end
        if hitP then prefix[#prefix + 1] = t; end
        if hitS then sub[#sub + 1] = t; end
    end
    if #exact > 0 then return exact; end
    if #prefix > 0 then return prefix; end
    return sub;
end

local function listTeleports(items)
    local parts = {};
    for _, t in ipairs(items) do parts[#parts + 1] = t.dest; end
    return table.concat(parts, ', ');
end

ashita.events.register('d3d_present', 'dlac-useitem-tick', function()
    if state == nil then return; end
    local now = os.clock();
    if state.stage == 'wait' and now >= state.useAt then
        queue('/item "' .. state.name .. '" <me>');
        print('[dlac] using ' .. state.name .. ' NOW.');
        state.stage = 'used';
        state.releaseAt = now + 3;                     -- give the use a moment, then unlock
    elseif state.stage == 'used' and now >= state.releaseAt then
        local slot = state.slot;
        state = nil;
        release(slot);
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
    if sub ~= 'p' and sub ~= 'w' and sub ~= 't' then return; end
    e.blocked = true;
    if args[2] == 'off' or args[2] == 'cancel' or args[2] == 'stop' then cancel(); return; end

    if sub == 't' then
        local q = table.concat(args, ' ', 2);
        if q == '' then
            print('[dlac] teleports: ' .. listTeleports(TELEPORTS) .. '   (/dl t <where>)');
            return;
        end
        local hits = findTeleports(q);
        if #hits == 0 then
            print('[dlac] no teleport matches "' .. q .. '" -- options: ' .. listTeleports(TELEPORTS));
        elseif #hits > 1 then
            print('[dlac] "' .. q .. '" is ambiguous -- did you mean: ' .. listTeleports(hits) .. '?');
        else
            local t = hits[1];
            start({ name = t.name, slot = 'ear2', wait = TELE_WAIT },
                'teleporting to ' .. t.dest, '/dl t off');
        end
        return;
    end

    start(RINGS[sub], 'using', '/dl ' .. sub .. ' off');
end);

return M;
