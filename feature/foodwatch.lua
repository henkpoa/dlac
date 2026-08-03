--[[
    dlac/feature/foodwatch.lua -- what you last ate, and one click to eat it again.

    Two halves, and the first one is the whole design problem:

    WHAT MAKES AN ITEM FOOD. Two answers, and it takes BOTH:

        an outgoing item use (OUT 0x037) is the INTENT -- which item,
        the FOOD effect moving right after is the PROOF -- that it was food,
        data\fooddb.lua is the SERVER'S OWN ANSWER -- whether it can be.

    The third line arrived on 2026-08-03 and it is new. dlac used to stand on
    the first two alone, on the reasoning that nothing client-side can tell a
    Mithkabob from a Potion (both "usable items"; the Catalog is gear-only) and
    that a Potion cannot move the FOOD effect, so the effect moving was proof
    enough. The field disproved it: a zone reload moves that effect too, and
    Henrik's history came back carrying an Instant Warp and a Flask of Echo
    Drops, both used seconds after a zone, both wearing the remaining time of a
    real meal that was still running underneath them (see M._known).

    So the catalog now VOUCHES. It is generated from the server's own predicate
    (scripts\items\*.lua calling xi.itemUtils.foodOnItemCheck -- 783 of them on
    stable), which makes it the same authority the effect is, only readable
    BEFORE the fact instead of after. Two things it does that the effect cannot:

        IT PICKS. Eat a Pork Cutlet, quaff a potion two seconds later, and the
        FOOD effect lands while the potion is the newest thing you used. One
        pending slot hands the credit to the potion; the table lets dlac keep
        the Cutlet and reach past it (M._choose).
        IT WAITS. An item the table has never heard of is still learned -- that
        is how a food the server adds tomorrow works with no shipped update --
        but only from an effect that APPEARED out of nothing, well clear of a
        zone. Nothing is vouching for it but the effect, so the effect has to be
        unambiguous.

    What the table must never become is the ONLY answer. The day it goes stale
    is the day it starts calling a real food a potion, and the learned path is
    what makes that a delay rather than a wall.

    "MOVING", precisely -- the part that eating over a live food breaks. The
    effect being PRESENT is not the signal: re-eating while food is up never
    flickers the icon, so presence alone would miss exactly the case a player
    hits most. The signal is the effect's EXPIRY changing, read from
    GetStatusTimers() alongside GetBuffs() -- the two arrays pair by index (the
    `timers` addon's read, field-proven on this client).

    -- 2026-08-03: compared for inequality NO LONGER. That was the second half
    of the bug above. Food is PAUSED while a zone loads, so the server hands
    back an expiry pushed forward by however long the load took -- +2s and +6s
    in Henrik's two bad rows -- and a bare `~=` reads that drift as a meal. A
    real re-eat cannot be subtle: the shortest food in the game runs 30 seconds,
    so the jump has to clear M.REEAT_JUMP to count. Still no epoch and no wrap
    math; a delta outside the sane band simply answers no.

    -- 2026-08-01: the raw value IS decoded now (M._remaining), but only to
    answer "how much of this meal have you spent", never to draw a countdown --
    how long is left stays the buff-timer addons' display. See M.status.

    -- 2026-08-01, from the field: that premise is a RETAIL one and does not hold
    here. CatsEyeXI REFUSES an item use while the FOOD effect is up (Henrik: "You
    can never eat over something in this game, server prevents you to"), so the
    absent -> present edge is the primary path and the expiry comparison is
    insurance for the one case still reachable -- a food wearing off and being
    re-eaten inside the same 250ms poll gap, where the absent state is never
    sampled.

    -- 2026-08-03: "cannot fire wrongly" stood here for two days and was wrong.
    It fired twice in the field, and the refusal above is what turns the wreck
    into a rule: an item use the server ACCEPTED while food was up is impossible,
    so an effect that has more time left than the item you just used could ever
    grant belongs to an EARLIER meal. That is one comparison against the
    catalogue's book duration (doubled, because xi.mod.FOOD_DURATION exists) and
    it closes the last hole -- a use the server refused mid-zone, landing beside
    the old meal reappearing.

    THE HISTORY is per character and persists (<char>\dlac\foodhistory.lua), most
    recent first, unique by item id. Henrik's ruling (2026-07-30): dlac is always
    loaded, so if the FOOD effect is still up when you log in it is -- to a near
    certainty -- the last food this file recorded. That is why `current` NAMES a
    food off the history whenever the effect is up, instead of reporting a bare
    "food active" that helps nobody.

    THE MENU rows are "the three most recent foods you are CARRYING" -- it walks
    past a food you have run out of to the next one you still have, rather than
    showing a dead row (M.MENU_N / M._pick). Inventory only, because /item reads
    nowhere else.

    THREADING. The packet handler does the one read it cannot defer -- the item
    id, while the stack still exists; the last item of a stack is gone by the
    next frame -- and NOTHING else: no chat, no disk (the synthrun/chocowatch
    law). Naming the item, the history, the file write and every chat line
    happen on the frame tick.

    WHAT THE FOOD DOES (2026-08-01) is the second question, and the game refuses
    to answer it: the FOOD status icon is GENERIC. Eat, log out, forget, log back
    in, and nothing on screen says which food you are under. dlac knows -- so
    M.statsFor pairs the history with data\fooddb.lua (the server's own item
    scripts, shipped).

    Pure seams for the headless suite (tests FW*): _parseItemUse, _step, _choose,
    _known, _bookDur, _sweep, _remember, _pick, _serialize, _fromRaw, _fmtAgo,
    _fmtDur, _descLines. They
    take plain values and return plain values -- no imgui, no Ashita, no disk.
    M.pump and M.statsFor take their live reads as a table they CALL, and the
    suite drives them with its own, so the live path cannot rot green underneath
    a passing test.
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
-- How many foods the history keeps. Deeper than the three the menu shows on
-- purpose: the menu walks PAST foods you have run out of, and can only do that
-- while there is something behind them.
M.CAP     = 10;
M.MENU_N  = 3;
-- Seconds an item use stays attributable to a FOOD change. Eating lands well
-- inside a second; the window only has to outlast a stutter, and nothing else
-- can move that effect, so it is generous rather than tight.
M.WINDOW  = 8.0;
-- How far the expiry has to jump FORWARD before it counts as a second meal
-- rather than the clock being re-based under us. A zone reload drifted Henrik's
-- by +2s and +6s; the shortest food on the server (id 5165) runs 30. Anything in
-- between is a coin toss dlac declines to call, and calling it wrong writes a
-- wrong row to disk while calling it "no" merely misses a re-eat that the
-- server will not let you perform anyway.
M.REEAT_JUMP = 15;
-- Seconds after a zone-in during which an UNCATALOGUED item cannot be believed.
-- Only the unknown path waits this out: a zone replays the whole status array
-- and there is no second opinion to weigh it against. A catalogued food skips
-- this entirely, so "zone in, eat" keeps working the way it always has.
M.ZONE_SETTLE = 15.0;
-- Inventory. /item refuses every other container, so a food in the satchel is
-- not a food you can eat (useitem's scroll path draws the same line).
M.BAG     = 0;

-- THE STATUS-TIMER DECODE (2026-08-01). A raw GetStatusTimers value is the
-- effect's expiry in SIXTIETHS OF A SECOND since the Vana'diel epoch, in a
-- uint32 that wraps roughly every 2.3 years -- hence the re-add loop, which is
-- undoing ~10 wraps in 2026. Ported by hand from the two sibling addons that
-- already carry it (`timers\helpers.lua`, `statustimers\party.lua`), which agree
-- line for line.
--
-- Those two read the CLIENT's own UTC stamp out of memory behind a signature
-- scan. dlac uses os.time() instead: no sig to break on a client patch, and it
-- verified against Henrik's own recorded meals to within the poll interval
-- (Hobgoblin Pie decoded to 3598s against its 3600s server script). The cost is
-- that a machine clock badly out of step with the client's would skew this --
-- which is why every consumer treats an out-of-range answer as UNKNOWN.
M.VANA_EPOCH = 0x3C307D70;
M.INFINITE   = 0x7FFFFFFF;   -- the client's "permanent effect" marker
-- No food in the game lasts a day. A decode that says otherwise is a decode that
-- went wrong, and an unknown is always better than a confident wrong number.
M.MAX_FOOD   = 86400;

-- The on-disk format. 2 since 2026-08-03: rows written before it predate the
-- catalogue veto, so a fmt-1 file gets swept once on load (M._sweep).
M.FMT = 2;

M.history = {};          -- most recent first: { id, name, at, n, expiry }
M._pending = nil;        -- the last outgoing item use: { id, at } (packet thread)
M._pendingFood = nil;    -- ...and the last one the CATALOGUE calls food (tick)
M._state  = { food = nil };   -- what the last poll saw: { present, expiry }
M._zonedAt = nil;        -- os.clock() of the last zone-in (packet thread)

-- The menu's one-second bag cache. Declared HERE, above every function that
-- touches it: a local declared below its reader is a silent nil GLOBAL, and the
-- reader that invalidates this one (M.pump, so a food you just ate shows up
-- without a stale second) sits above M.menu.
local _menuAt, _menuRows = 0, nil;

-- The shipped food table, required ONCE. Declared HERE, above M._known and
-- M.statsFor both, for the same reason as the cache above it: a local declared
-- below its reader is a silent nil GLOBAL, and _known is read from M.pump near
-- the top of the file while statsFor sits near the bottom.
local _db, _dbTried = nil, false;
local function fooddb()
    if not _dbTried then
        _dbTried = true;
        local ok, t = pcall(require, 'dlac\\data\\fooddb');
        if ok and type(t) == 'table' and type(t.foods) == 'table' then _db = t.foods; end
    end
    return _db;
end

-- ---------------------------------------------------------------------------
-- Pure seams
-- ---------------------------------------------------------------------------

-- Is this item one of the server's foods?  true / false / NIL, and the nil is
-- the important one: it means the table could not be read at all, and a missing
-- shipped file must not silently turn every food in the game into a non-food.
--
-- The table is generated from scripts\items\*.lua calling
-- xi.itemUtils.foodOnItemCheck -- the server's own predicate, not a guess about
-- what looks edible -- so a `false` here is the same authority that would have
-- refused to grant the effect. A `true` is not proof you ATE it (the server can
-- still refuse the use); it only means the item is capable of being a meal, and
-- the effect edge is what says one happened.
function M._known(id)
    local db = fooddb();
    if type(db) ~= 'table' then return nil; end
    return db[tonumber(id) or -1] ~= nil;
end

-- The catalogue's BOOK duration for a food, in seconds, or nil. Book value, so
-- it is only ever used as a CEILING (M._step doubles it for xi.mod.FOOD_DURATION
-- before comparing) -- never as the length of a meal, which is measured.
function M._bookDur(id)
    local db = fooddb();
    if type(db) ~= 'table' then return nil; end
    local e = db[tonumber(id) or -1];
    return (type(e) == 'table') and tonumber(e.d) or nil;
end

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
--   env     -- what is known about the pending item, from outside this seam:
--                known   = the catalogue vouches for it (M._known). Only `true`
--                          is load-bearing: `false` and `nil` both mean "no
--                          vouch" and take the same conservative path, because
--                          a food added after the table was generated and a
--                          thing that is not food are indistinguishable here.
--                book    = catalogued duration in seconds | nil  (M._bookDur)
--                left    = seconds still on the effect this poll | nil
--                zonedAt = clock of the last zone-in | nil
--              absent entirely = "nothing is known", the pre-2026-08-03 path.
-- Returns the pending use to record, or nil.
--
-- An UNREADABLE poll changes nothing at all -- it must not blank the last known
-- state, because "was absent, now present" is one of the two things that count
-- as movement and a dropped read would manufacture it.
function M._step(state, now, food, pending, env)
    if type(state) ~= 'table' then return nil; end
    if type(food) ~= 'table' then return nil; end
    local prev = state.food;
    state.food = food;
    if food.present ~= true then return nil; end
    if type(pending) ~= 'table' or pending.id == nil then return nil; end
    if (tonumber(now) or 0) - (tonumber(pending.at) or 0) > M.WINDOW then return nil; end

    -- STEP 1 -- did the effect move at all? Either edge counts: it was not up a
    -- moment ago, or its expiry jumped FAR enough forward to be a second meal
    -- rather than a zone re-basing the clock. Expiries we cannot read answer
    -- "no" rather than "maybe": without the timer array a re-eat is genuinely
    -- unknowable, and inventing it would put the wrong item in the history. The
    -- upper bound makes the uint32 wrap harmless -- a wrapped delta lands
    -- outside the band and is simply not movement.
    local appeared = (type(prev) ~= 'table' or prev.present ~= true);
    local moved = appeared;
    if not moved and food.expiry ~= nil and prev.expiry ~= nil then
        local d = food.expiry - prev.expiry;
        moved = (d > M.REEAT_JUMP * 60) and (d <= M.MAX_FOOD * 60);
    end
    if not moved then return nil; end

    env = (type(env) == 'table') and env or {};

    -- STEP 2 -- a meal cannot be longer than the food that bought it. More time
    -- left than this item can grant (doubled, for xi.mod.FOOD_DURATION under
    -- Sigil or Sanction) means the effect on screen belongs to an EARLIER meal
    -- that has merely reappeared -- which is exactly what a use the server
    -- REFUSED looks like from here, since food was already up when you tried.
    -- The slack absorbs the poll interval and the os.time() decode.
    local book, left = tonumber(env.book), tonumber(env.left);
    -- A decode outside the sane band is an UNKNOWN, never a veto. M._remaining
    -- leans on os.time() against the client's own clock, and a machine clock out
    -- of step produces a wild number rather than a wrong-looking small one --
    -- which would otherwise refuse a perfectly real meal every single time.
    if left ~= nil and (left <= 0 or left > M.MAX_FOOD) then left = nil; end
    if book ~= nil and left ~= nil and left > book * 2 + 60 then return nil; end

    -- STEP 3 -- an item the catalogue vouches for is done here. Everything below
    -- applies only to an item it has never heard of, which is either a food the
    -- server added after the table was generated or something that is not food
    -- at all -- and from inside this function those two look identical.
    if env.known == true then return pending; end

    -- The effect has to be CLEAN, then, because nothing but the effect is
    -- speaking for this item.
    --
    -- Not a re-eat: pushing an expiry out is the ambiguous edge, and reading it
    -- as a brand-new food dlac has never seen is a guess on top of a guess.
    if not appeared then return nil; end
    -- And not during a zone. The status array replays on the far side of a
    -- loading screen with its expiries pushed forward by however long the load
    -- took, so the effect "appearing" there means nothing. A food the table does
    -- know skips this (step 3), so "zone in, eat" keeps working; an unknown one
    -- eaten in the window is simply learned the next time it is eaten.
    local z = tonumber(env.zonedAt);
    if z ~= nil and (tonumber(now) or 0) - z < M.ZONE_SETTLE then return nil; end

    return pending;
end

-- WHICH item use the effect edge belongs to. Two candidates, because the newest
-- use is not always the right one: eat a Pork Cutlet and quaff a potion two
-- seconds later and the potion is what a single `_pending` slot would be holding
-- when the FOOD effect lands a moment after that. A use the CATALOGUE calls food
-- outranks a bare newest-use, which is the whole point of having the table --
-- it can pick the right item out of a burst, not just refuse the wrong one.
-- Either candidate still has to be inside the window to count at all.
function M._choose(pending, pendingFood, now)
    now = tonumber(now) or 0;
    local function live(u)
        if type(u) ~= 'table' or u.id == nil then return nil; end
        if now - (tonumber(u.at) or 0) > M.WINDOW then return nil; end
        return u;
    end
    return live(pendingFood) or live(pending);
end

-- The one-time sweep of a pre-catalogue history file (fmt 1). Those rows were
-- recorded when the effect moving was the ONLY test, so they can contain things
-- that were never food -- Henrik's carried an Instant Warp and a Flask of Echo
-- Drops. A row the table does not list is dropped; a row it cannot answer for at
-- all (isFood returning nil -- the shipped file unreadable) is KEPT.
--
-- Note this is STRICTER than detection, deliberately. M._step treats "not in the
-- table" as merely unvouched, because a food added tomorrow looks exactly like
-- that. Here the row is already known to have come from the version that got
-- this wrong, so absence is evidence rather than silence -- and the cost of
-- being wrong is one re-eat to learn it back, against a permanent wrong row.
--
-- Rows written at fmt 2 are never swept: they either passed the veto or carry
-- `learned`, and re-judging them every load would delete a genuine custom food
-- the day the shipped table goes stale.
-- Returns the list and how many rows it dropped.
function M._sweep(list, fmt, isFood)
    list = (type(list) == 'table') and list or {};
    if (tonumber(fmt) or 1) >= M.FMT then return list, 0; end
    if type(isFood) ~= 'function' then return list, 0; end
    local dropped = 0;
    for i = #list, 1, -1 do
        local e = list[i];
        if type(e) == 'table' and e.learned ~= true and isFood(e.id) == false then
            table.remove(list, i);
            dropped = dropped + 1;
        end
    end
    return list, dropped;
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
                            expiry = tonumber(entry.expiry) or nil,
                            -- The MEASURED full duration of this meal, not the
                            -- food's book value: xi.mod.FOOD_DURATION (Sigil,
                            -- Sanction) doubles it, so the only honest number is
                            -- the one read off the effect at the moment it landed.
                            dur = tonumber(entry.dur) or nil,
                            -- Recorded WITHOUT the catalogue vouching for it --
                            -- a food the shipped table has never heard of. The
                            -- flag is what stops a later sweep from deleting it.
                            learned = (entry.learned == true) or nil });
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
        string.format('    fmt = %d,', M.FMT),
        '    foods = {',
    };
    for _, e in ipairs((type(list) == 'table') and list or {}) do
        if type(e) == 'table' and tonumber(e.id) and type(e.name) == 'string' then
            L[#L + 1] = string.format(
                '        { id = %d, name = %q, at = %d, n = %d, expiry = %d, dur = %d%s },',
                tonumber(e.id), e.name, tonumber(e.at) or 0, tonumber(e.n) or 1,
                tonumber(e.expiry) or 0, tonumber(e.dur) or 0,
                (e.learned == true) and ', learned = true' or '');
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
                              expiry = (tonumber(e.expiry) or 0) > 0 and tonumber(e.expiry) or nil,
                              -- Absent in rows written before 2026-08-01: those
                              -- fall back to wall-clock until re-eaten.
                              dur = (tonumber(e.dur) or 0) > 0 and tonumber(e.dur) or nil,
                              learned = (e.learned == true) or nil };
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

-- A food's FULL duration. Rounded to the minute BEFORE it is split, because a
-- MEASURED duration lands a second or two under the round number (the poll runs
-- every 250ms and the read costs what it costs) and "360 min" is not an answer.
function M._fmtDur(sec)
    sec = tonumber(sec) or 0;
    if sec <= 0 then return nil; end
    local mins = math.floor(sec / 60 + 0.5);
    if mins < 60 then return string.format('%d min', mins); end
    local h, m = math.floor(mins / 60), mins % 60;
    if m == 0 then return string.format('%d hr', h); end
    return string.format('%d hr %d min', h, m);
end

-- Time REMAINING, phrased for the panel. Deliberately not _fmtDur: a length
-- rounds to the nearest minute happily, a countdown must not round 20 seconds up
-- to "1 min" and needs something to say at zero. The "~" is honest rather than
-- decorative -- the decode leans on os.time() against the client's own clock,
-- and the poll runs every 250ms, so this is an estimate and says so.
function M._fmtLeft(sec)
    sec = tonumber(sec);
    if sec == nil then return nil; end
    if sec <= 0 then return 'expiring now'; end
    if sec < 60 then return 'under a minute left'; end
    return '~' .. M._fmtDur(sec) .. ' left';
end

-- Raw status timer -> SECONDS REMAINING, or nil when it cannot be believed.
--   raw -- the value paired with this effect in GetStatusTimers()
--   utc -- real-world epoch seconds (os.time())
-- The re-add loop undoes the uint32 wraps between the Vana'diel epoch and now;
-- it is bounded so a garbage input cannot spin (the sibling addons' is not).
function M._remaining(raw, utc)
    raw = tonumber(raw); utc = tonumber(utc);
    if raw == nil or utc == nil or raw == M.INFINITE then return nil; end
    local real = raw - (utc - M.VANA_EPOCH) * 60;
    local guard = 0;
    while real < -2147483648 and guard < 64 do
        real = real + 0xFFFFFFFF;
        guard = guard + 1;
    end
    if real < 1 then return 0; end
    return math.ceil(real / 60);
end

-- The client's own item Description -> effect lines. The FALLBACK source, for
-- the handful of foods whose server script carries no English header. Retail DAT
-- text: it cannot know a CatsEyeXI rebalance, which is exactly why it is second
-- and not first. Descriptions are one blob with embedded newlines and the odd
-- control byte; the first line is usually the effect-duration banner and is kept
-- (it says the same thing the header's duration does).
function M._descLines(text)
    local out = {};
    if type(text) ~= 'string' then return out; end
    text = text:gsub('[%z\1-\8\11\12\14-\31]', '\n');
    for line in (text .. '\n'):gmatch('([^\r\n]*)[\r\n]') do
        line = line:gsub('^%s+', ''):gsub('%s+$', '');
        if line ~= '' then out[#out + 1] = line; end
    end
    return out;
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
    local fmt = M.FMT;
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then
            M.history = M._fromRaw(t);
            fmt = tonumber(t.fmt) or 1;
        end
    end);
    -- Heal a pre-catalogue file in place, once. Nobody should have to run a
    -- migration to get rid of a row dlac itself wrote wrongly, and
    -- `/dl food forget` is the wrong tool for it -- clearing the junk that way
    -- takes every real meal with it.
    local _, dropped = M._sweep(M.history, fmt, M._known);
    if dropped > 0 or fmt < M.FMT then M.save(); end
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

    -- The client's own description blob for an item. Only consulted when the
    -- shipped table has nothing (M.statsFor).
    describe = function(id)
        local d = nil;
        pcall(function()
            local r = AshitaCore:GetResourceManager():GetItemById(id);
            if r ~= nil and r.Description ~= nil then d = r.Description[1]; end
        end);
        return d;
    end,

    save = function() return M.save(); end,
};

-- One beat: poll the effect, and record the pending item use if that effect
-- just moved. Returns the recorded entry, or nil.
function M.pump(reads)
    reads = (type(reads) == 'table') and reads or M.reads;
    M.load();
    local now  = reads.clock();
    local f    = reads.food();
    -- Classify the newest use HERE rather than in the packet handler: M._known
    -- can require() the shipped table on its first call, and disk I/O on the
    -- network thread is the one thing that handler is not allowed to do. A use
    -- the catalogue calls food is remembered in its own slot so a later
    -- non-food use cannot displace it (M._choose).
    if type(M._pending) == 'table' and M._pending.id ~= nil
       and M._known(M._pending.id) == true then
        M._pendingFood = M._pending;
    end
    local pend = M._choose(M._pending, M._pendingFood, now);
    -- Everything _step needs to weigh this item, gathered HERE so that seam
    -- stays pure and the suite can put it in any state it likes. Only built when
    -- there is something to weigh -- no pending use, no catalogue lookup and no
    -- os.time() call on a beat that cannot record anything anyway.
    local env = nil;
    if type(pend) == 'table' and pend.id ~= nil then
        env = {
            known   = M._known(pend.id),
            book    = M._bookDur(pend.id),
            left    = (type(f) == 'table') and M._remaining(f.expiry, reads.stamp()) or nil,
            zonedAt = M._zonedAt,
        };
    end
    local hit = M._step(M._state, now, f, pend, env);
    if hit == nil then return nil; end
    M._pending, M._pendingFood = nil, nil;         -- consumed either way below
    local name = reads.nameOf(hit.id);
    if type(name) ~= 'string' or name == '' then return nil; end
    local e = { id = hit.id, name = name, at = reads.stamp(),
                expiry = (type(M._state.food) == 'table') and M._state.food.expiry or nil,
                -- Learned the old way: the catalogue could not vouch for it, the
                -- effect edge did. Marked so the sweep never second-guesses it.
                learned = (env ~= nil and env.known ~= true) or nil };
    -- MEASURE the meal's real duration, here and nowhere else: what is left the
    -- instant it lands IS its full length. The food's book value cannot be used
    -- for this -- xi.mod.FOOD_DURATION (Sigil, Sanction) grants +100%, so the
    -- same Pork Cutlet runs 3 hours or 6 depending on what you were under when
    -- you ate it. An answer outside the sane band is dropped rather than stored:
    -- a missing duration falls back to wall-clock, a wrong one would lie forever.
    e.dur = M._remaining(e.expiry, e.at);
    if e.dur ~= nil and (e.dur <= 0 or e.dur > M.MAX_FOOD) then e.dur = nil; end
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

-- ---------------------------------------------------------------------------
-- WHAT A FOOD DOES (2026-08-01)
--
-- The problem is the game's, not dlac's: FFXI's food status icon is GENERIC. It
-- says you are under food and never which one, so after "eat, log out, forget,
-- log back in" there is no way to find out what you are getting. dlac already
-- knows what you ate; this is what lets it say what that food does.
--
-- Two sources, in this order: the server's own item script (authority -- it is
-- where the mods actually live) then the client's item Description (retail DAT
-- text, so it cannot know a CatsEyeXI rebalance; it exists to cover the ~13
-- foods whose script carries no English header). Neither answering is a nil,
-- and the caller simply draws no stats.
--
-- The same table also VETOES detection (M._known) -- it is read here for what a
-- food does and there for whether it is one at all.
-- ---------------------------------------------------------------------------

-- { lines = { 'HP +40', ... }, dur = 10800, src = 'server'|'client' } or nil.
-- Lines are COPIED: the table behind them is the shared require'd one, and a
-- caller that trimmed it in place would corrupt every later read.
function M.statsFor(id, reads)
    reads = (type(reads) == 'table') and reads or M.reads;
    id = tonumber(id);
    if id == nil then return nil; end

    local e = nil;
    local db = fooddb();
    if type(db) == 'table' then e = db[id]; end
    local dur = (type(e) == 'table') and tonumber(e.d) or nil;

    if type(e) == 'table' and type(e.s) == 'table' and #e.s > 0 then
        local out = {};
        for i = 1, #e.s do out[i] = e.s[i]; end
        return { lines = out, dur = dur, src = 'server' };
    end

    local lines = M._descLines(reads.describe(id));
    if #lines > 0 then return { lines = lines, dur = dur, src = 'client' }; end
    return nil;
end

-- active  -- is the FOOD effect up at all
-- current -- WHICH food that is: the newest history row, because dlac was
--            running when it was eaten (Henrik's ruling). nil = the effect is
--            up but this character has never eaten anything on dlac's watch.
-- recent  -- the whole history, most recent first
-- dur     -- the MEASURED full length of the meal that is up
-- left    -- seconds still on it, decoded from the live timer
-- used    -- seconds of it you have actually spent = dur - left
--
-- WHY `used` IS NOT `os.time() - at` (Henrik, 2026-08-01: "the food duration
-- doesn't go down when you're logged out"). Food is paused while you are
-- offline, so wall-clock elapsed drifts from the truth by the whole length of
-- every logout -- eat, play ten minutes, sleep, and dlac would have called it
-- "eaten 8h ago" on a food with most of its time left. The server sends the real
-- remaining time at login, so reading it back is exact and needs no bookkeeping:
-- no accumulator to tick, nothing written every few seconds, and nothing to
-- drift when the addon reloads or the game crashes. dur/left/used are all nil
-- when they cannot be known, and every caller falls back to wall-clock there.
function M.status(reads)
    reads = (type(reads) == 'table') and reads or M.reads;
    M.load();
    local f = M._state.food;
    local active = (type(f) == 'table' and f.present == true);
    local cur = (active and M.history[1] ~= nil) and M.history[1] or nil;
    local dur, left, used = nil, nil, nil;
    if active then
        left = M._remaining(f.expiry, reads.stamp());
        dur  = (cur ~= nil) and tonumber(cur.dur) or nil;
        if left ~= nil and dur ~= nil then
            used = dur - left;
            -- Longer than the meal, or negative: the pairing or the clock is off,
            -- so say nothing rather than something wrong.
            if used < 0 or used > dur then used = nil; end
        end
    end
    return {
        active  = active,
        current = cur,
        recent  = M.history,
        dur     = dur,
        left    = left,
        used    = used,
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

-- IN 0x00A: zone-in. Two bare writes, no chat and no disk -- this is the network
-- thread (the same law the handler above obeys, and chocowatch's zone stamp).
--
-- The stamp is what STEP 4 of M._step waits out. The clear is the other half and
-- matters just as much: an item use fired before the loading screen has no
-- business being attributed to an effect that reappears after it. Henrik used a
-- Scroll of Instant Warp seconds after zoning, which is precisely the sequence
-- both lines exist to break -- and a warp scroll is a zone, so this fires for
-- the scroll's OWN arrival as well.
ashita.events.register('packet_in', 'dlac-foodwatch-zonein', function(e)
    if e.id == 0x00A then
        M._zonedAt = os.clock();
        M._pending, M._pendingFood = nil, nil;
    end
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
        -- `used` is time spent UNDER the food; the wall-clock fallback is only
        -- for rows recorded before the duration was measured. They differ by
        -- every logout you have taken since.
        local when = '';
        if st.used ~= nil then
            when = ' (eaten ' .. M._fmtAgo(st.used) .. ')';
        elseif (tonumber(st.current.at) or 0) > 0 then
            when = ' (eaten ' .. M._fmtAgo(os.time() - st.current.at) .. ')';
        end
        local left = M._fmtLeft(st.left);
        say('under ' .. st.current.name .. when
            .. ((left ~= nil) and (' -- ' .. left) or '') .. '.');
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
    M._pendingFood, M._zonedAt = nil, nil;
    _loadedFrom, _menuRows, _menuAt = nil, nil, 0;
    -- The stats table too: it is required ONCE and cached, so a suite that
    -- injects its own package.loaded['dlac\\data\\fooddb'] after the first
    -- statsFor call would otherwise keep reading the real shipped one.
    _db, _dbTried = nil, false;
end

return M;
