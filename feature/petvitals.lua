--[[
    dlac/feature/petvitals.lua -- the PET VITALS service (issue #140, PRD #135).
    ONE question, in the Central-services shape:

        "Is a pet out right now, and how is it doing?"

        petvitals.get()               -> { present, hpp, tp, name, at }
        petvitals.subscribe(who, cb)  -> the same record, pushed each dispatch beat

    THE LAW IT CARRIES: **dead pet = no pet.** A pet at 0 HP% is not a pet any
    consumer may act on -- the same rule `gData.GetPet()` has always encoded
    (nativedata: pet index 0 OR pet HPP 0 -> nil), stated once more here because
    `fromPet` is also fed hand-built records by the tests.

    THE ONE READ IS `gData.GetPet()`. dlac already has exactly one pet reader --
    the LAC-parity provider in `feature\nativedata` that the ENGINE reads every
    dispatch for the pet trigger conditions (engine v63) -- so this service
    CONSUMES it rather than opening a second `GetPetTargetIndex` / `GetHPPercent`
    pair. A central service whose whole point is "never re-derive" must not start
    life as the second implementation of its own answer.

    PRESENT IS TWO-STATE, ON PURPOSE. `gData.GetPet()` answers nil for BOTH "no
    pet" and "the read could not be made", and the two are deliberately NOT
    separated here: every consumer of this service ISSUES A COMMAND or SPENDS AN
    ITEM off the answer, and for those an unreadable pet must decide exactly the
    way an absent one does (the Fight switch's `hasPet` rule, #139 -- a read we
    cannot make is not permission to act). `hpp`/`tp`/`name` are individually
    nil-able for the same reason: a present pet whose HP could not be read is
    reported honestly instead of guessed at.

    THE CADENCE. `pump()` (dlac.lua's `d3d_present`) publishes to subscribers at
    most once per `TICK_S` -- 0.4s, the engine's own dispatch beat, which is what
    the PRD means by "pet presence, HP%, TP and name each dispatch". It polls
    only while somebody is subscribed; the Panel and any one-off caller ask
    `get()` directly and never wait for a beat. There is no cache: `get()` reads
    the world every time, so a caller can never be handed a vitals record older
    than its own question.

    House shape: a PURE core -- `fromPet(pet)` takes a pet record and answers
    with no AshitaCore -- so the one-question tests (PV*) drive every state
    headlessly; the live read and the frame pump are the thin glue.

    Pure at load; every gData / require touch is call-time under pcall.
]]--

local M = {};

-- The publish cadence, seconds. The engine's Default dispatch runs every 0.4s
-- and reads the pet for its own trigger conditions; a vitals subscriber that
-- beat faster would be measuring the same memory twice for no one.
M.TICK_S = 0.4;

-- ---------------------------------------------------------------------------
-- the pure core -- a pet record in, the vitals answer out
-- ---------------------------------------------------------------------------
--
-- `pet` is a `gData.GetPet()` record (LAC parity: Distance / HPP / Id / Index /
-- Name / Status / TP) or nil. Returns the vitals record, always a table:
--   { present = true, hpp = <0-100|nil>, tp = <number|nil>, name = <string|nil> }
--   { present = false }                                   -- no pet, or unreadable
function M.fromPet(pet)
    if type(pet) ~= 'table' then return { present = false }; end
    local hpp = tonumber(pet.HPP);
    -- Dead pet = no pet. gData.GetPet already refuses an HPP-0 pet; a record
    -- built by hand (a test, a future reader) is held to the same law here.
    if hpp ~= nil and hpp <= 0 then return { present = false }; end
    -- GetName pads with whitespace / NULs (the entwatch idiom).
    local name = nil;
    if type(pet.Name) == 'string' then
        name = (pet.Name:gsub('%z', ''):gsub('%s+$', ''));
        if name == '' then name = nil; end
    end
    -- Status rides along verbatim ('Idle' / 'Engaged' / ...; nativedata resolves
    -- it): the Fight poll gates on pet-IDLE (2026-07-29 rewrite), and a consumer
    -- must not open a second status read beside this service.
    local status = nil;
    if type(pet.Status) == 'string' and pet.Status ~= '' then status = pet.Status; end
    return { present = true, hpp = hpp, tp = tonumber(pet.TP), name = name, status = status };
end

-- ---------------------------------------------------------------------------
-- live reads (injectable as a whole -- the fight.reads / location.reader shape)
-- ---------------------------------------------------------------------------

M.reads = {};

-- The one pet read: dlac's own gData provider. nil = no pet OR no read (see the
-- header -- the two are the same answer to every consumer of this service).
M.reads.pet = function()
    local pet = nil;
    pcall(function()
        local g = rawget(_G, 'gData');
        if type(g) ~= 'table' or type(g.GetPet) ~= 'function' then return; end
        pet = g.GetPet();
    end);
    if type(pet) ~= 'table' then return nil; end
    return pet;
end;

-- THE exported question. `reads` overrides the whole read table (tests).
function M.get(reads)
    local r = (type(reads) == 'table') and reads or M.reads;
    local pet = nil;
    if type(r.pet) == 'function' then
        local ok, p = pcall(r.pet);
        if ok then pet = p; end
    end
    return M.fromPet(pet);
end

-- ---------------------------------------------------------------------------
-- subscribers + the frame pump
-- ---------------------------------------------------------------------------

local _subs   = {};    -- who -> cb
local _last   = nil;   -- the last PUBLISHED record (what last() answers)
local _lastAt = nil;   -- when it was published (the throttle's clock)

-- Subscribe to the per-beat vitals. `who` names the consumer so a module can
-- drop its own subscription wholesale (the entwatch / engagewatch contract).
-- cb(vitals) is pcall'd -- one throwing consumer never costs another its beat.
function M.subscribe(who, cb)
    if type(who) ~= 'string' or who == '' then return false; end
    if type(cb) ~= 'function' then return false; end
    _subs[who] = cb;
    return true;
end

function M.unsubscribe(who)
    if type(who) ~= 'string' then return false; end
    _subs[who] = nil;
    return true;
end

function M.subscriberCount()
    local n = 0;
    for _ in pairs(_subs) do n = n + 1; end
    return n;
end

-- The last PUBLISHED record, or nil before the first beat. Deliberately not the
-- answer to "how is my pet" -- that is get(), which reads the world now.
function M.last() return _last; end

-- Drop the published record (job change / logout / test reset). Subscribers
-- survive a reset(false); reset(true) drops them too.
function M.reset(dropSubs)
    _last, _lastAt = nil, nil;
    if dropSubs == true then _subs = {}; end
end

-- A monotonic seconds clock -- the cmdqueue frame counter (the addon's steady
-- tick) falling back to os.clock. The actionseq twin; injectable for tests.
M._now = function()
    local t = nil;
    pcall(function()
        local cq = require('dlac\\lib\\cmdqueue');
        if type(cq) == 'table' and type(cq.frame) == 'function' then t = cq.frame() / 60.0; end
    end);
    if type(t) ~= 'number' then pcall(function() t = os.clock(); end); end
    return tonumber(t) or 0;
end;

-- One beat: read the vitals and push them to every subscriber, at most once per
-- TICK_S. Returns the published record, or nil when the beat was skipped (no
-- subscribers, or inside the throttle window). `now` and `reads` are the test
-- seams. A clock that went BACKWARDS publishes rather than muting for a whole
-- window (the engagewatch debounce rule).
function M.pump(now, reads)
    if M.subscriberCount() == 0 then return nil; end     -- nobody listening: no poll at all
    now = tonumber(now) or M._now();
    if _lastAt ~= nil then
        local since = now - _lastAt;
        if since >= 0 and since < M.TICK_S then return nil; end
    end
    _lastAt = now;
    local v = M.get(reads);
    v.at = now;
    _last = v;
    for _, cb in pairs(_subs) do pcall(cb, v); end
    return v;
end

return M;
