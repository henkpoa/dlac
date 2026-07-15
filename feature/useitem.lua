--[[
    dlac/useitem.lua

    Timed enchantment commands -- equip, wait out the equip delay, /item:
        /dl p              lock Ring2, equip the Provenance Ring, use it (panic escape).
        /dl w              same with the Warp Ring (shorter delay).
        /dl t <where>      lock Ear2, equip the matching teleport earring, use it.
                           <where> matches a destination or alias (norg, jeuno,
                           sandy, bastok...); an ambiguous query lists the options,
                           no argument lists every destination.
        /dl xp <ring>      lock Ring2, equip the matching EXPERIENCE ring, use it
                           (empress, emperor, resolution, chariot, kupofried,
                           allied, caliber, echad). Same countdown machinery; the
                           GUI menu lists only the ones you own.
        /dl p|w|t|xp off   cancel the pending use and release the slot.

    Readiness is read from the GAME, not guessed: an enchanted item's Extra data
    carries its last-use timestamp (offset 5) and -- for Flags == 5 equipment --
    the equip timestamp (offset 9), both against the client's UTC clock (the same
    state that turns the item blue in the menu). We poll the equipped slot and
    fire the moment the game says usable. The configured wait only remains as the
    FALLBACK when the clock or the item can't be read (then we fire blind on the
    timer, exactly the old behavior). Decode layout is tCrossBar's, via XIUI's
    itemrecast.lua -- both field-proven on this client. SE quirk (field-verified):
    the displayed 0 is still a live second, so we hold fire ~1.2s past it.

    Runs in the ADDON state: native /equip + /item bypass LuaAshitacast; the
    engine lock (/dl lock <slot>) stops dlac dispatch from swapping the piece back
    out mid-countdown, and /lac disable <slot> covers hand-written profile code.
]]--

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
local print = (_cfok and type(_cfmt) == 'table' and type(_cfmt.print) == 'function') and _cfmt.print or print;
local _stok, struct = pcall(require, 'struct');

local M = {};

local RINGS = {
    p = { name = 'Provenance Ring', slot = 'ring2', wait = 20 },   -- 15s equip delay + margin
    w = { name = 'Warp Ring',       slot = 'ring2', wait = 12 },   --  8s equip delay + margin
};

-- Teleport earrings (CatsEyeXI): 30s equip delay + margin, all worn in Ear2.
-- aliases are matched exact -> prefix -> substring; keep them lowercase.
local TELE_WAIT = 34;
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

-- Experience bands/rings (Henrik): equip Ring2, wait out the equip delay, use
-- -- exactly the teleport machinery. `dest` doubles as the short label the
-- list/menu shows; bonus rides along for the menu label. Only OWNED ones
-- appear in the GUI menu (you can't have them all). Fallback wait = 10s equip
-- delay + margin; the game-clock poll fires at the true moment as always.
local XP_WAIT = 15;
local EXPRINGS = {
    { name = 'Empress Band',     dest = 'Empress',    bonus = '+50%',  aliases = { 'empress' } },
    { name = 'Emperor Band',     dest = 'Emperor',    bonus = '+50%',  aliases = { 'emperor' } },
    { name = 'Resolution Ring',  dest = 'Resolution', bonus = '+50%',  aliases = { 'resolution', 'reso' } },
    { name = 'Chariot Band',     dest = 'Chariot',    bonus = '+75%',  aliases = { 'chariot' } },
    { name = "Kupofried's Ring", dest = 'Kupofried',  bonus = '+100%', aliases = { 'kupofried', 'kupo' } },
    { name = 'Allied Ring',      dest = 'Allied',     bonus = '+150%', aliases = { 'allied' } },
    { name = 'Caliber Ring',     dest = 'Caliber',    bonus = '+150%', aliases = { 'caliber' } },
    { name = 'Echad Ring',       dest = 'Echad',      bonus = '+150%', aliases = { 'echad' } },
};

local SLOT_ID = { ring2 = 0x0E, ear2 = 0x0C };   -- native equip-slot indexes

-- Seconds to hold fire past the first measured remaining==0 (the SE quirk: the
-- displayed 0 is still a live second). 1.2 still fired early at times in the
-- field (Henrik, 07-14) -- 1.7 is that plus his requested half second.
local ZERO_HOLD = 1.7;

local state = nil;   -- { name, slot, useAt, stage, releaseAt, nextPoll, measured, zeroAt }

local function queue(cmd)
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
end

local function release(slot)
    queue('/dl lock ' .. slot .. ' off');
    queue('/lac enable ' .. slot);
end

-- ---------------------------------------------------------------------------
-- Game-clock readiness (tCrossBar / XIUI itemrecast decode).
-- ---------------------------------------------------------------------------
local VANA_OFFSET = 0x3C307D70;
local _timePtr = nil;
local function gameNow()
    if _timePtr == nil then
        pcall(function()
            local p = ashita.memory.find('FFXiMain.dll', 0,
                '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3', 0x02, 0);
            if p == 0 then return; end
            local ptr = ashita.memory.read_uint32(p);
            if ptr == 0 then return; end
            ptr = ashita.memory.read_uint32(ptr);
            if ptr ~= 0 then _timePtr = ptr; end
        end);
        if _timePtr == nil then return 0; end
    end
    local t = 0;
    pcall(function() t = ashita.memory.read_uint32(_timePtr + 0x0C) or 0; end);
    return t;
end

-- Remaining seconds until the item equipped in def.slot is usable.
-- Returns: seconds (0 = usable NOW), or nil when unreadable (slot empty / wrong
-- item still swapping in / clock unavailable) -- the caller falls back to the timer.
local function readiness(def)
    if not _stok then return nil; end
    local rem = nil;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local eitem = inv:GetEquippedItem(SLOT_ID[def.slot]);
        if eitem == nil or eitem.Index == 0 then return; end
        local cont = math.floor(eitem.Index / 256) % 256;
        local slotInCont = eitem.Index % 256;
        local item = inv:GetContainerItem(cont, slotInCont);
        if item == nil or item.Id == nil or item.Id == 0 then return; end
        local res = AshitaCore:GetResourceManager():GetItemById(item.Id);
        local nm = res ~= nil and res.Name ~= nil and res.Name[1] or nil;
        if nm == nil or string.lower(nm) ~= string.lower(def.name) then return; end
        local now = gameNow();
        if now == 0 then return; end
        local r = 0;
        if type(item.Extra) == 'string' and #item.Extra >= 12 then
            local useT = struct.unpack('I', item.Extra, 5) or 0;
            if useT > 0 then r = math.max(r, (useT + VANA_OFFSET) - now); end
            if item.Flags == 5 then                    -- enchanted equipment: equip delay
                local eqT = struct.unpack('I', item.Extra, 9) or 0;
                if eqT > 0 then r = math.max(r, (eqT + VANA_OFFSET) - now); end
            end
        end
        rem = r;
    end);
    return rem;
end

local function start(def, verb, cancelHint)
    if state ~= nil and state.slot ~= def.slot then
        release(state.slot);                           -- switching item type: free the old slot
    end
    queue('/dl lock ' .. def.slot .. ' on');
    queue('/lac disable ' .. def.slot);
    queue('/equip ' .. def.slot .. ' "' .. def.name .. '"');
    state = {
        name = def.name, slot = def.slot, stage = 'wait', verb = verb,
        cancel = cancelHint,                           -- the exact abort command (GUI stop button)
        useAt = os.clock() + def.wait,                 -- fallback timer only
        nextPoll = os.clock() + 1.0,                   -- give /equip a moment to land
        measured = false,
    };
    print(string.format('[dlac] %s equipped in %s -- %s when the game says ready (~%ds)  (%s cancels)',
        def.name, def.slot, verb, def.wait, cancelHint));
end

local function cancel()
    if state == nil then print('[dlac] nothing pending.'); return; end
    print('[dlac] ' .. state.name .. ' use cancelled -- ' .. state.slot .. ' released.');
    local slot = state.slot;
    state = nil;
    release(slot);
end

-- Resolve a query against a list (teleports or exp rings): exact alias, then
-- alias/destination prefix, then substring across alias/destination/item
-- name. One hit = go; several = the caller lists them; none = nil.
local function findTeleports(list, q)
    local exact, prefix, sub = {}, {}, {};
    for _, t in ipairs(list) do
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

local function fire()
    queue('/item "' .. state.name .. '" <me>');
    print('[dlac] using ' .. state.name .. ' NOW.');
    state.stage = 'used';
    state.releaseAt = os.clock() + 3;                  -- give the use a moment, then unlock
end

ashita.events.register('d3d_present', 'dlac-useitem-tick', function()
    if state == nil then return; end
    local now = os.clock();
    if state.stage == 'wait' then
        if now >= (state.nextPoll or 0) then
            state.nextPoll = now + 0.25;
            local rem = readiness(state);
            if rem ~= nil then
                if not state.measured then
                    state.measured = true;
                    -- the game clock is now authoritative; announce if it disagrees
                    -- with the estimate by more than a couple of seconds
                    local est = state.useAt - now;
                    if math.abs(rem - est) > 2 then
                        print(string.format('[dlac] %s ready in %ds (game clock).', state.name, math.ceil(rem)));
                    end
                end
                if rem <= 0 then
                    -- SE quirk (field-verified): the displayed 0 is still a live
                    -- second -- the item only becomes usable ~1s after remaining
                    -- hits 0. Hold fire until ZERO_HOLD past the first measured 0
                    -- (1.2 fired early at times in the field -- Henrik, 07-14).
                    if state.zeroAt == nil then state.zeroAt = now; end
                    state.useAt = math.max(state.useAt, state.zeroAt + ZERO_HOLD);   -- keep the fallback honest too
                    if now >= state.zeroAt + ZERO_HOLD then fire(); end
                    return;
                end
                state.zeroAt = nil;                               -- bounced back above 0 (re-equip reset)
                state.useAt = math.max(state.useAt, now + rem);   -- keep the fallback honest
            end
        end
        -- Fallback: fire on the timer when the polls go dark (readiness never
        -- readable, or the item vanished mid-wait). useAt is pushed to the
        -- measured remaining on every good poll, so this can't fire early.
        if state.stage == 'wait' and now >= state.useAt then
            fire();
        end
    elseif state.stage == 'used' and now >= state.releaseAt then
        local slot = state.slot;
        state = nil;
        release(slot);
    end
end);

-- ---------------------------------------------------------------------------
-- Menu data for the GUI (gearui's "Teleports" header dropdown): the same items
-- the commands drive, with live bag state. One container scan per second (the
-- popup reads this every frame). Row: { name, label, cmd, id, owned, avail,
-- where, rem, charges, maxch } -- rem is the RECHARGE remaining (seconds) read
-- from the item's Extra use-timestamp, i.e. "out of charges" while > 0.
-- charges = enchantment charges left on the owned copy (Extra byte 2, same
-- field-proven extdata layout as the timestamps); maxch = the cap from the
-- item resource. charges is nil / maxch 0 when unowned or not charge-tracked.
-- ---------------------------------------------------------------------------
local MENU = {
    { name = 'Warp Ring',       label = 'Warp',        cmd = '/dl w' },
    { name = 'Provenance Ring', label = 'Provenance',  cmd = '/dl p' },
};
for _, t in ipairs(TELEPORTS) do
    MENU[#MENU + 1] = { name = t.name, label = t.dest, cmd = '/dl t ' .. t.aliases[1] };
end
-- Exp rings ride the same menu, marked xp: the GUI draws them in their own
-- section under the teleports, and menu() drops the UNOWNED ones entirely
-- (Henrik: you can't have them all -- listing eight "not owned" rows is noise).
-- label = the short name only (Henrik: no percentages in the first column;
-- the bonus still shows in the /dl xp chat line).
for _, x in ipairs(EXPRINGS) do
    MENU[#MENU + 1] = { name = x.name, label = x.dest,
                        cmd = '/dl xp ' .. x.aliases[1], xp = true };
end
local WANTED = {};
for _, m in ipairs(MENU) do WANTED[string.lower(m.name)] = true; end

-- The Teleports-menu name-set for OTHER modules: { lower(name) -> true } over
-- everything above (Warp/Provenance rings, teleport earrings, exp rings).
-- gearui's + Add picker hides these from set building by default -- utility
-- enchantments carry no combat stats and only bloat the Ear/Ring lists.
function M.menuNames() return WANTED; end

-- Containers the game lets you EQUIP from (inventory + wardrobes); anything
-- else is owned-but-stored -- the menu paints it red, as everywhere in dlac.
local EQUIP_BAGS = { [0] = true, [8] = true, [10] = true, [11] = true, [12] = true,
                     [13] = true, [14] = true, [15] = true, [16] = true };
local BAG_NAMES = { [0] = 'Inventory', [1] = 'Mog Safe', [2] = 'Storage', [3] = 'Temporary',
                    [4] = 'Mog Locker', [5] = 'Satchel', [6] = 'Sack', [7] = 'Case',
                    [8] = 'Wardrobe', [9] = 'Mog Safe 2', [10] = 'Wardrobe 2', [11] = 'Wardrobe 3',
                    [12] = 'Wardrobe 4', [13] = 'Wardrobe 5', [14] = 'Wardrobe 6',
                    [15] = 'Wardrobe 7', [16] = 'Wardrobe 8' };

-- The in-flight use, for the GUI: nil when idle, else { name, cancel, stage } --
-- the Teleports buttons turn into an ABORT control while this is set (clicking
-- queues .cancel, i.e. '/dl w|p|t off').
function M.pending()
    if state == nil then return nil; end
    return { name = state.name, cancel = state.cancel, stage = state.stage };
end

local _menuAt, _menuRows = 0, nil;
function M.menu()
    if _menuRows ~= nil and os.clock() < _menuAt then return _menuRows; end
    _menuAt = os.clock() + 1.0;
    local found = {};   -- lower(name) -> best instance { id, bag, avail, rem }
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local res = AshitaCore:GetResourceManager();
        local now = gameNow();
        for bag = 0, 16 do
            local max = inv:GetContainerCountMax(bag) or 0;
            for i = 1, max do
                local item = inv:GetContainerItem(bag, i);
                if item ~= nil and item.Id ~= nil and item.Id > 0 and (item.Count or 0) > 0 then
                    local r = res:GetItemById(item.Id);
                    local nm = (r ~= nil and r.Name ~= nil) and r.Name[1] or nil;
                    local key = (nm ~= nil) and string.lower(nm) or nil;
                    if key ~= nil and WANTED[key] then
                        local rem = 0;
                        if _stok and type(item.Extra) == 'string' and #item.Extra >= 8 and now ~= 0 then
                            local useT = struct.unpack('I', item.Extra, 5) or 0;
                            if useT > 0 then rem = math.max(0, (useT + VANA_OFFSET) - now); end
                        end
                        -- Enchantment charges left ride Extra byte 2; the cap comes
                        -- from the item resource. Own pcall: a missing binding must
                        -- not abort the whole scan.
                        local charges, maxch = nil, 0;
                        pcall(function() maxch = r.MaxCharges or 0; end);
                        if maxch > 0 and type(item.Extra) == 'string' and #item.Extra >= 2 then
                            charges = string.byte(item.Extra, 2);
                        end
                        local avail = (EQUIP_BAGS[bag] == true);
                        local cur = found[key];
                        -- prefer an available copy; among equals, the readiest one
                        if cur == nil or (avail and not cur.avail)
                           or (avail == cur.avail and rem < cur.rem) then
                            found[key] = { id = item.Id, bag = bag, avail = avail, rem = rem,
                                           charges = charges, maxch = maxch };
                        end
                    end
                end
            end
        end
    end);
    local rows = {};
    for _, m in ipairs(MENU) do
        local f = found[string.lower(m.name)];
        if f ~= nil or not m.xp then                   -- exp rings: owned only
            rows[#rows + 1] = {
                name = m.name, label = m.label, cmd = m.cmd, xp = m.xp,
                id = f and f.id or nil,
                owned = (f ~= nil),
                avail = (f ~= nil) and f.avail or false,
                where = f and (BAG_NAMES[f.bag] or ('bag ' .. tostring(f.bag))) or nil,
                rem = f and f.rem or 0,
                charges = f and f.charges or nil,
                maxch = f and f.maxch or 0,
            };
        end
    end
    _menuRows = rows;
    return rows;
end

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
    if sub ~= 'p' and sub ~= 'w' and sub ~= 't' and sub ~= 'xp' then return; end
    e.blocked = true;
    if args[2] == 'off' or args[2] == 'cancel' or args[2] == 'stop' then cancel(); return; end

    if sub == 't' then
        local q = table.concat(args, ' ', 2);
        if q == '' then
            print('[dlac] teleports: ' .. listTeleports(TELEPORTS) .. '   (/dl t <where>)');
            return;
        end
        local hits = findTeleports(TELEPORTS, q);
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

    if sub == 'xp' then
        local q = table.concat(args, ' ', 2);
        if q == '' then
            print('[dlac] exp rings: ' .. listTeleports(EXPRINGS) .. '   (/dl xp <ring>)');
            return;
        end
        local hits = findTeleports(EXPRINGS, q);
        if #hits == 0 then
            print('[dlac] no exp ring matches "' .. q .. '" -- options: ' .. listTeleports(EXPRINGS));
        elseif #hits > 1 then
            print('[dlac] "' .. q .. '" is ambiguous -- did you mean: ' .. listTeleports(hits) .. '?');
        else
            local x = hits[1];
            start({ name = x.name, slot = 'ring2', wait = XP_WAIT },
                'popping the ' .. x.bonus .. ' exp bonus', '/dl xp off');
        end
        return;
    end

    start(RINGS[sub], 'using', '/dl ' .. sub .. ' off');
end);

return M;
