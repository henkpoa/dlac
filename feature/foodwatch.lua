--[[
    dlac/feature/foodwatch.lua -- what you last ate, and one click to eat it again.

    Two halves, and the first one is the whole design problem:

    WHAT MAKES AN ITEM FOOD. Nothing the client can read. The item resource calls
    a Mithkabob and a Potion the same thing (a usable item), and the Catalog is
    gear-only. The server's definition is the one that exists: eating grants the
    FOOD status effect (`xi.effect.FOOD`, 251 -- 787 item scripts carry it on
    CatsEyeXI stable), and that effect IS observable from here. So dlac ships no
    food list and guesses nothing:

        an outgoing item use (OUT 0x037) is the INTENT -- which item,
        the FOOD effect moving right after is the PROOF -- that it was food.

    A food dlac has never seen is learned the first time you eat it (custom
    server foods included), and a Potion can never be mistaken for one because
    a Potion does not move that effect.

    "MOVING", precisely -- the part that eating over a live food breaks. The
    effect being PRESENT is not the signal: re-eating while food is up never
    flickers the icon, so presence alone would miss exactly the case a player
    hits most. The signal is the effect's EXPIRY changing, read from
    GetStatusTimers() alongside GetBuffs() -- the two arrays pair by index (the
    `timers` addon's read, field-proven on this client). Raw values, compared for
    INEQUALITY only: no clock arithmetic to get wrong, no epoch, no wrap. How
    long is left is a question the buff-timer addons already answer, and this
    module deliberately does not re-answer it.

    THE HISTORY is per character and persists (<char>\dlac\foodhistory.lua), most
    recent first, unique by item id. Henrik's ruling (2026-07-30): dlac is always
    loaded, so if the FOOD effect is still up when you log in it is -- to a near
    certainty -- the last food this file recorded. That is why `current` NAMES a
    food off the history whenever the effect is up, instead of reporting a bare
    "food active" that helps nobody.

    THE MENU rows are "the two most recent foods you are CARRYING" -- it walks
    past a food you have run out of to the next one you still have, rather than
    showing a dead row (M.MENU_N / M._pick). Inventory only, because /item reads
    nowhere else.

    THREADING. The packet handler does the one read it cannot defer -- the item
    id, while the stack still exists; the last item of a stack is gone by the
    next frame -- and NOTHING else: no chat, no disk (the synthrun/chocowatch
    law). Naming the item, the history, the file write and every chat line
    happen on the frame tick.

    Pure seams for the headless suite (tests FW*): _parseItemUse, _step,
    _remember, _pick, _serialize, _fromRaw, _fmtAgo. They take plain values and
    return plain values -- no imgui, no Ashita, no disk. M.pump takes its live
    reads as a table it CALLS, and the suite drives that same pump with its own,
    so the live path cannot rot green underneath a passing test.
]]--

local M = {};

M.VERSION = 1;

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local _cfmt  = try('dlac\\chatfmt');
local say    = (_cfmt ~= nil and type(_cfmt.print) == 'function') and _cfmt.print or print;
local _sfile = try('dlac\\lib\\statefile');
local _safe  = try('dlac\\lib\\safewrite');

-- xi.effect.FOOD. The one server fact this module stands on.
M.FOOD_EFFECT = 251;
-- How many foods the history keeps. Deeper than the two the menu shows on
-- purpose: the menu walks PAST foods you have run out of, and can only do that
-- while there is something behind them.
M.CAP     = 10;
M.MENU_N  = 2;
-- Seconds an item use stays attributable to a FOOD change. Eating lands well
-- inside a second; the window only has to outlast a stutter, and nothing else
-- can move that effect, so it is generous rather than tight.
M.WINDOW  = 8.0;
-- Inventory. /item refuses every other container, so a food in the satchel is
-- not a food you can eat (useitem's scroll path draws the same line).
M.BAG     = 0;

M.history = {};          -- most recent first: { id, name, at, n, expiry }
M._pending = nil;        -- the last outgoing item use: { id, at } (packet thread)
M._state  = { food = nil };   -- what the last poll saw: { present, expiry }

-- The menu's one-second bag cache. Declared HERE, above every function that
-- touches it: a local declared below its reader is a silent nil GLOBAL, and the
-- reader that invalidates this one (M.pump, so a food you just ate shows up
-- without a stale second) sits above M.menu.
local _menuAt, _menuRows = 0, nil;

-- ---------------------------------------------------------------------------
-- Pure seams
-- ---------------------------------------------------------------------------

-- OUT 0x037 (item use) -> the two fields that name the item: its index within a
-- container, and the container. TWIN of feature\equipengine.parseItemUse (the
-- engine blocks and re-injects the same packet) -- change one, change the other.
-- Offsets are packet-relative and 0-based; Lua strings are 1-based, hence the +1.
function M._parseItemUse(data)
    if type(data) ~= 'string' or #data < 0x11 then return nil; end
    return {
        itemIndex = string.byte(data, 0x0E + 1),
        container = string.byte(data, 0x10 + 1),
    };
end

-- THE decision: did that item use just prove itself food?
--   state   -- carries { food } across calls; this call's read replaces it
--   now     -- monotonic seconds (the caller's clock)
--   food    -- this poll: { present = bool, expiry = number|nil }, nil = unreadable
--   pending -- the outgoing use: { id, at } | nil
-- Returns the pending use to record, or nil.
--
-- An UNREADABLE poll changes nothing at all -- it must not blank the last known
-- state, because "was absent, now present" is one of the two things that count
-- as movement and a dropped read would manufacture it.
function M._step(state, now, food, pending)
    if type(state) ~= 'table' then return nil; end
    if type(food) ~= 'table' then return nil; end
    local prev = state.food;
    state.food = food;
    if food.present ~= true then return nil; end
    if type(pending) ~= 'table' or pending.id == nil then return nil; end
    if (tonumber(now) or 0) - (tonumber(pending.at) or 0) > M.WINDOW then return nil; end
    -- Movement is either edge: the effect was not up a moment ago, or its expiry
    -- has been pushed out (re-eating over a live food, which never flickers).
    -- Expiries we cannot read answer "no" rather than "maybe": without the timer
    -- array a re-eat is genuinely unknowable, and inventing it would put the
    -- wrong item in the history.
    if type(prev) ~= 'table' or prev.present ~= true then return pending; end
    if food.expiry ~= nil and prev.expiry ~= nil and food.expiry ~= prev.expiry then
        return pending;
    end
    return nil;
end

-- MRU insert, unique by item id: eating something you already have a row for
-- moves that row to the front and counts the meal, it never makes a second row.
-- Trims to cap. Mutates and returns the list.
function M._remember(list, entry, cap)
    list = (type(list) == 'table') and list or {};
    if type(entry) ~= 'table' or entry.id == nil or type(entry.name) ~= 'string' then
        return list;
    end
    cap = tonumber(cap) or M.CAP;
    local n = 1;
    for i = #list, 1, -1 do
        local e = list[i];
        if type(e) ~= 'table' or e.id == nil then
            table.remove(list, i);
        elseif e.id == entry.id then
            n = (tonumber(e.n) or 0) + 1;
            table.remove(list, i);
        end
    end
    table.insert(list, 1, { id = entry.id, name = entry.name,
                            at = tonumber(entry.at) or 0, n = n,
                            expiry = tonumber(entry.expiry) or nil });
    for i = #list, cap + 1, -1 do table.remove(list, i); end
    return list;
end

-- The menu's rows: the n most recent foods you are CARRYING. countOf(entry)
-- answers how many are in Inventory; a zero walks on to the next entry rather
-- than ending the list, which is the whole reason the history is deeper than n.
function M._pick(list, countOf, n)
    local out = {};
    n = tonumber(n) or M.MENU_N;
    for _, e in ipairs((type(list) == 'table') and list or {}) do
        if #out >= n then break; end
        local c = 0;
        if type(countOf) == 'function' then c = tonumber(countOf(e)) or 0; end
        if c > 0 and type(e.name) == 'string' and e.name ~= '' then
            out[#out + 1] = { id = e.id, name = e.name, at = tonumber(e.at) or 0,
                              n = tonumber(e.n) or 1, count = c,
                              cmd = '/item "' .. e.name .. '" <me>' };
        end
    end
    return out;
end

-- Stable, ordered output: a history with nothing changed is byte-identical, so
-- the file only churns when a meal actually happened.
function M._serialize(list)
    local L = {
        '-- dlac food history -- what this character ate, most recent first.',
        '-- Written by dlac (feature\\foodwatch); safe to delete, never hand-edited.',
        'return {',
        '    fmt = 1,',
        '    foods = {',
    };
    for _, e in ipairs((type(list) == 'table') and list or {}) do
        if type(e) == 'table' and tonumber(e.id) and type(e.name) == 'string' then
            L[#L + 1] = string.format(
                '        { id = %d, name = %q, at = %d, n = %d, expiry = %d },',
                tonumber(e.id), e.name, tonumber(e.at) or 0, tonumber(e.n) or 1,
                tonumber(e.expiry) or 0);
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '}';
    return table.concat(L, '\n') .. '\n';
end

-- Parsed file -> the shape the rest of this module assumes. Anything malformed
-- is DROPPED: a half-understood row would put a name we cannot /item into a
-- menu that eats things.
function M._fromRaw(t)
    local out = {};
    if type(t) ~= 'table' or type(t.foods) ~= 'table' then return out; end
    for _, e in ipairs(t.foods) do
        if type(e) == 'table' and tonumber(e.id) and type(e.name) == 'string' and e.name ~= '' then
            out[#out + 1] = { id = tonumber(e.id), name = e.name,
                              at = tonumber(e.at) or 0, n = tonumber(e.n) or 1,
                              expiry = (tonumber(e.expiry) or 0) > 0 and tonumber(e.expiry) or nil };
        end
    end
    for i = #out, M.CAP + 1, -1 do table.remove(out, i); end
    return out;
end

function M._fmtAgo(sec)
    sec = tonumber(sec) or 0;
    if sec < 0 then sec = 0; end
    if sec < 90      then return string.format('%ds ago', math.floor(sec)); end
    if sec < 5400    then return string.format('%dm ago', math.floor(sec / 60 + 0.5)); end
    if sec < 172800  then return string.format('%dh ago', math.floor(sec / 3600 + 0.5)); end
    return string.format('%dd ago', math.floor(sec / 86400 + 0.5));
end

-- ---------------------------------------------------------------------------
-- Disk
-- ---------------------------------------------------------------------------

function M.path()
    local dir = (_sfile ~= nil) and _sfile.charDir() or nil;
    return dir and (dir .. 'foodhistory.lua') or nil;
end

local _loadedFrom = nil;   -- the path M.history mirrors (nil = never loaded)

-- Read once per path. The path CHANGES with the character and the active
-- Profile, so it is the key rather than a one-shot flag: switching profile must
-- pick up that profile's history, not keep the old one in memory.
function M.load()
    local p = M.path();
    if p == nil then return M.history; end        -- pre-login: retry next beat
    if _loadedFrom == p then return M.history; end
    _loadedFrom = p;
    M.history = {};
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then M.history = M._fromRaw(t); end
    end);
    return M.history;
end

function M.save()
    local p = M.path();
    if p == nil then return false; end
    local text = M._serialize(M.history);
    local ok = false;
    if _safe ~= nil and type(_safe.replaceLua) == 'function' then
        ok = _safe.replaceLua(p, text) and true or false;
    end
    if not ok then
        pcall(function()
            local f = io.open(p, 'w');
            if f == nil then return; end
            f:write(text); f:close();
            ok = true;
        end);
    end
    return ok;
end

-- ---------------------------------------------------------------------------
-- Live reads. FUNCTIONS, and M.pump calls every one of them -- the headless
-- suite drives the same pump with its own table, so a pump that stopped asking
-- would fail there instead of passing while the live path sits dead.
-- ---------------------------------------------------------------------------
M.reads = {
    clock = function() return os.clock(); end,
    stamp = function() return os.time(); end,

    -- The FOOD effect right now: presence, plus the raw expiry the timer array
    -- carries beside it. The two arrays pair BY INDEX; iterating from 0 covers
    -- either binding base without caring which one this Ashita hands back.
    food = function()
        local out = nil;
        pcall(function()
            local p = AshitaCore:GetMemoryManager():GetPlayer();
            if p == nil then return; end
            local ids = p:GetBuffs();
            if ids == nil then return; end
            local ts = nil;
            pcall(function() ts = p:GetStatusTimers(); end);
            local present, expiry = false, nil;
            for i = 0, 32 do
                if ids[i] == M.FOOD_EFFECT then
                    present = true;
                    if ts ~= nil and ts[i] ~= nil then expiry = tonumber(ts[i]); end
                end
            end
            out = { present = present, expiry = expiry };
        end);
        return out;
    end,

    -- The client's own name for the item -- the exact string /item needs.
    nameOf = function(id)
        local nm = nil;
        pcall(function()
            local r = AshitaCore:GetResourceManager():GetItemById(id);
            if r ~= nil and r.Name ~= nil then nm = r.Name[1]; end
        end);
        return nm;
    end,

    save = function() return M.save(); end,
};

-- One beat: poll the effect, and record the pending item use if that effect
-- just moved. Returns the recorded entry, or nil.
function M.pump(reads)
    reads = (type(reads) == 'table') and reads or M.reads;
    M.load();
    local hit = M._step(M._state, reads.clock(), reads.food(), M._pending);
    if hit == nil then return nil; end
    M._pending = nil;                              -- consumed either way below
    local name = reads.nameOf(hit.id);
    if type(name) ~= 'string' or name == '' then return nil; end
    local e = { id = hit.id, name = name, at = reads.stamp(),
                expiry = (type(M._state.food) == 'table') and M._state.food.expiry or nil };
    M._remember(M.history, e, M.CAP);
    _menuRows = nil;                               -- the row you just earned, this frame
    reads.save();
    return M.history[1];
end

-- ---------------------------------------------------------------------------
-- What the GUI and the command ask
-- ---------------------------------------------------------------------------

-- The menu rows, with live Inventory counts. One bag scan a second -- the popup
-- asks every frame.
function M.menu()
    if _menuRows ~= nil and os.clock() < _menuAt then return _menuRows; end
    _menuAt = os.clock() + 1.0;
    M.load();
    local counts = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local max = inv:GetContainerCountMax(M.BAG) or 0;
        for i = 1, max do
            local it = inv:GetContainerItem(M.BAG, i);
            if it ~= nil and it.Id ~= nil and it.Id > 0 and (it.Count or 0) > 0 then
                counts[it.Id] = (counts[it.Id] or 0) + it.Count;
            end
        end
    end);
    _menuRows = M._pick(M.history, function(e) return counts[e.id] or 0; end, M.MENU_N);
    return _menuRows;
end

-- active  -- is the FOOD effect up at all
-- current -- WHICH food that is: the newest history row, because dlac was
--            running when it was eaten (Henrik's ruling). nil = the effect is
--            up but this character has never eaten anything on dlac's watch.
-- recent  -- the whole history, most recent first
function M.status()
    M.load();
    local f = M._state.food;
    local active = (type(f) == 'table' and f.present == true);
    return {
        active  = active,
        current = (active and M.history[1] ~= nil) and M.history[1] or nil,
        recent  = M.history,
    };
end

function M.forget()
    M.load();
    local n = #M.history;
    M.history = {};
    M.save();
    _menuRows = nil;
    return n;
end

-- ---------------------------------------------------------------------------
-- Live wiring
-- ---------------------------------------------------------------------------

-- OUT 0x037: stash WHICH item, and nothing else. This runs on the network
-- thread, so the one read that cannot wait (the id -- the last item of a stack
-- is gone by the next frame) happens here and the rest happens on the tick.
-- Injected copies count: the native engine blocks this packet and re-injects
-- it, and another addon's item use arrives injected too -- taking the latest
-- either way costs nothing (the same id twice is the same pending use).
ashita.events.register('packet_out', 'dlac-foodwatch-out', function(e)
    if e.id ~= 0x37 then return; end
    local u = M._parseItemUse(e.data);
    if u == nil then return; end
    local id = nil;
    pcall(function()
        local it = AshitaCore:GetMemoryManager():GetInventory()
            :GetContainerItem(u.container, u.itemIndex);
        if it ~= nil and it.Id ~= nil and it.Id > 0 then id = it.Id; end
    end);
    if id ~= nil then M._pending = { id = id, at = os.clock() }; end
end);

local _nextPoll = 0;
ashita.events.register('d3d_present', 'dlac-foodwatch-tick', function()
    local now = os.clock();
    if now < _nextPoll then return; end
    _nextPoll = now + 0.25;
    pcall(M.pump);
end);

-- ---------------------------------------------------------------------------
-- /dl food
-- ---------------------------------------------------------------------------
local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'   or string.sub(raw, 1, 4)  == '/dl '   then return 5; end
    return nil;
end

ashita.events.register('command', 'dlac-foodwatch', function(e)
    local raw = string.lower(e.command);
    local s = argStart(raw);
    if s == nil then return; end
    local args = {};
    for a in string.gmatch(string.sub(raw, s), '[^%s]+') do args[#args + 1] = a; end
    if args[1] ~= 'food' then return; end
    e.blocked = true;

    if args[2] == 'forget' or args[2] == 'clear' then
        local n = M.forget();
        say(string.format('food history cleared (%d %s forgotten).', n,
            (n == 1) and 'food' or 'foods'));
        return;
    end

    local rows = M.menu() or {};
    local pick = tonumber(args[2]);
    if pick ~= nil then
        local r = rows[pick];
        if r == nil then
            -- Hard rule 12: a no-op says which of the two things went wrong.
            if #rows == 0 then
                say('nothing to eat -- no food you have eaten before is in your Inventory.');
            else
                say(string.format('there is no food %d -- you have %d listed.', pick, #rows));
            end
            return;
        end
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, r.cmd); end);
        say('eating ' .. r.name .. '.');
        return;
    end

    local st = M.status();
    if st.active and st.current ~= nil then
        local when = (tonumber(st.current.at) or 0) > 0
            and (' (eaten ' .. M._fmtAgo(os.time() - st.current.at) .. ')') or '';
        say('under ' .. st.current.name .. when .. '.');
    elseif st.active then
        say('a food effect is up, but nothing was eaten while dlac was watching.');
    else
        say('no food effect.');
    end
    if #st.recent == 0 then
        say('  nothing eaten yet -- eat something and it is remembered here.');
        return;
    end
    for i, r in ipairs(rows) do
        say(string.format('  %d. %s  x%d in Inventory   (/dl food %d)', i, r.name, r.count, i));
    end
    if #rows == 0 then
        say('  none of the ' .. #st.recent .. ' foods you have eaten are in your Inventory.');
    elseif #st.recent > #rows then
        say(string.format('  (%d more you have eaten before are not in your Inventory.)',
            #st.recent - #rows));
    end
end);

-- Test seam: drop every cached fact so a suite can point the module at a fresh
-- fixture without a process restart.
function M._reset()
    M.history, M._pending, M._state = {}, nil, { food = nil };
    _loadedFrom, _menuRows, _menuAt = nil, nil, 0;
end

return M;
