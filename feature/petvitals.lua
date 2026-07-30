--[[
    dlac/feature/petvitals.lua -- the PET VITALS service (issue #140, PRD #135).
    ONE question, in the Central-services shape:

        "Is a pet out right now, and how is it doing?"

        petvitals.get()               -> { present, hpp, tp, name, at }
        petvitals.subscribe(who, cb)  -> the same record, pushed each dispatch beat

    ...and, since issue #141, the classified PET-LOSS EDGE that rides the same
    beat -- "my pet is gone, and here is WHY":

        petvitals.classifyLoss(prev, cur, ctx)  -> the pure verdict
        petvitals.subscribeLoss(who, cb)        -> pushed the moment a pet is lost

    DEATH IS CONFIRMED, NEVER ASSUMED. That is the whole law of the edge, and it
    exists because its one consumer SPENDS A JUG. Three confirmations count, in
    strength order: the CORPSE (the pet's own index re-read by server id, at
    zero HP or a dead status -- see corpseVerdict, and note that on CatsEyeXI
    this is the ONLY one that fires for a jug pet), the pet-falls chat line
    (matched on `text_in`, the established text channel -- history.md's
    dig-obtained lesson: read the line the client already renders instead of
    hunting a packet for it), and, only when the corpse could not be read at
    all, a present -> absent transition after a LOW last-seen HP%. An observed
    outgoing Leave, zoning and logging out each SUPPRESS -- they are checked
    first, so a deliberate dismissal never reads as a death -- and so does a
    corpse read that finds the entity ALIVE. Everything else is `unknown`, which
    confirms nothing.

    JUG OR CHARM is answered by PROVENANCE first (what we watched you press:
    Call Beast / Bestial Loyalty / Charm, observed the same way as Leave) and by
    the consumer's injected name authority second. A custom jug this server
    ships and no roster describes is still yours by the first test.

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

-- "Low last-seen HP%": the ceiling under which a pet that VANISHES is taken to
-- have died without a chat line to say so. Deliberately generous-but-low -- a
-- jug pet dies from a bar that was falling, and a pet dismissed at 30% is a
-- player pulling it out of a fight it was losing, which must NOT read as a
-- death. FLAGGED for the field round: this number is the one knob between "the
-- resummon missed a death" and "the resummon burned a jug on a Leave".
M.LOW_HP_PCT = 25;

-- How long (seconds) an observed signal -- a falls line, an outgoing Leave --
-- stays relevant to a loss. The vitals beat is 0.4s and the client's own
-- message/entity ordering is not guaranteed, so the window is wide enough that
-- the line and the vanish are never split by a stutter, and short enough that
-- last pull's death cannot explain this pull's missing pet.
M.SIGNAL_TTL_S = 8.0;

-- The pet-falls chat text, lowercased. FLAGGED for field verification (the
-- PRD's own field-verify list names "the exact pet-falls message wording"):
-- the phrase is matched case-insensitively as a SUBSTRING and the subject is
-- read off the front, so a wording that differs only in punctuation or address
-- still matches, and a wording that differs in the verb does not -- in which
-- case the low-HP transition still confirms the death and only the loud,
-- immediate path is lost.
M.FALLS_TEXT = 'falls to the ground';

-- Subjects that mean "my pet" when the falls line does not name it. A server
-- that writes "Your pet falls to the ground." is still understood.
M.FALLS_SELF = { ['your pet'] = true, ['pet'] = true };

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
    -- IDENTITY (2026-07-30). The server id and the target index of the pet while
    -- it is alive -- which is what makes the death witness below possible: when
    -- the pet vanishes we go back and read THAT index, and the id says whether
    -- what we find is still the same entity. Both nil-able like every other
    -- vital: a pet whose identity could not be read is reported honestly.
    return { present = true, hpp = hpp, tp = tonumber(pet.TP), name = name, status = status,
             id = tonumber(pet.Id), index = tonumber(pet.Index) };
end

-- ---------------------------------------------------------------------------
-- the DEATH WITNESS -- the corpse at the remembered index (issue: the Resummon
-- rule never fired in the field, 2026-07-30)
-- ---------------------------------------------------------------------------
--
-- WHY THIS EXISTS, from the server's own source: a jug pet's death is SILENT.
-- CMobEntity::Die pushes the falls message (src/map/entities/mobentity.cpp),
-- but a jug pet is a CPetEntity and CPetEntity::Die (petentity.cpp) pushes NO
-- battle message at all -- it clears the AI stack, holds the death state 2500ms
-- and detaches. So FALLS_TEXT below can never match for a pet on this server,
-- and the low-HP fallback misses every pet killed from above 25%: between them
-- that is a death proof that proves nothing, which is exactly what the field
-- reported.
--
-- What DOES witness it is the corpse. `gData.GetPet()` refuses an HPP-0 pet (the
-- dead-pet-is-no-pet law, and right for consumers), so the service goes around
-- it: the last present beat remembers the pet's index and server id, and when
-- presence drops we read that index RAW. Same id, zero HP or a dead status =
-- this pet died, by identity, with no name and no chat line involved -- so a
-- custom jug the roster has never heard of resummons like any other.
--
-- FIELD-CONFIRMED 2026-07-30 (dlacprobe 2.5 `/probe pet`, a SheepFamiliar killed
-- by a Gigas's Leech, entity polled 20x/s). Three numbers, all of them better
-- than this was designed against:
--   * the flip is INSTANT. The last attached read was `hpp=1 status=Idle`; on the
--     same 50ms poll, reading the index directly already gave `hpp=0
--     status=Dead(3)` -- +1ms. There is no window in which the corpse still
--     reads alive, so the `false` verdict cannot misfire on a death.
--   * the corpse PERSISTS. Same index, same server id, 0 HP, for the full 15s
--     the probe watched -- it never despawned inside the window, against the
--     ~2.5s the server's own `Internal_Die(2500ms)` suggested. A 0.4s beat gets
--     ~37 looks at it, not the ~6 budgeted.
--   * the death is TOTALLY SILENT. Not one `falls to the ground`, `is defeated`
--     or 0x029 battle message in the whole run -- exactly what CPetEntity::Die
--     predicts. The only line after the death is the mob still swinging at the
--     corpse.
--
-- RAW status values. nativedata resolves its table at index+1, so its two 'Dead'
-- entries ([3] and [4]) are raw 2 and 3 here. Read raw on purpose: this is the
-- one place in dlac that must not depend on a display string. The field read is
-- **3**; 2 is kept because the resolver names both, and the HP test catches it
-- either way.
M.DEAD_STATUS = { [2] = true, [3] = true };

-- The verdict, PURE: the remembered id and whatever the entity read answered.
--   true  = the same entity is still there and it is dead
--   false = the same entity is there and POSITIVELY ALIVE (an unattached pet --
--           a charm break, a dismissal we did not observe -- never a death)
--   nil   = cannot tell (no read, or the corpse already despawned and the index
--           reads as somebody else), which confirms nothing and lets the other
--           proofs speak
function M.corpseVerdict(prevId, ent)
    if type(ent) ~= 'table' then return nil; end
    local want = tonumber(prevId);
    local id   = tonumber(ent.id);
    if want == nil or want == 0 or id == nil or id == 0 then return nil; end
    if id ~= want then return nil; end            -- despawned / index recycled
    local hpp = tonumber(ent.hpp);
    if hpp ~= nil and hpp <= 0 then return true; end
    if M.DEAD_STATUS[tonumber(ent.status)] == true then return true; end
    if hpp ~= nil and hpp > 0 then return false; end
    return nil;
end

-- ---------------------------------------------------------------------------
-- the PET-LOSS EDGE, pure half (issue #141)
-- ---------------------------------------------------------------------------

-- Trim + collapse a display name the way every entity read in dlac does (NULs,
-- padding, the leading article a message adds).
local function normName(s)
    if type(s) ~= 'string' then return nil; end
    s = (s:gsub('%z', ''):gsub('^%s+', ''):gsub('%s+$', ''));
    if s == '' then return nil; end
    return s;
end

-- Strip a rendered chat line down to printable text (the helmwatch cleanLine
-- idiom). A `text_in` message carries the client's colour/format control bytes
-- inline, and they sit exactly where a name does -- so the substring match
-- would still hit while the SUBJECT slice came back with control bytes stuck to
-- it and matched no pet name at all.
local function cleanLine(msg)
    local s = tostring(msg or ''):gsub('[^\032-\126]+', ' ');
    return (s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''));
end
M._cleanLine = cleanLine;   -- test seam

-- The SUBJECT of a pet-falls chat line, or nil when the line is not one.
-- Returns '' when the line matches but names nobody. Matched lowercased and
-- SLICED FROM THE CLEANED ORIGINAL, the digrank lesson (a fixed-case Lua
-- pattern silently misses real messages; the display case is still the
-- server's).
function M.fallsSubject(line)
    if type(line) ~= 'string' then return nil; end
    local clean = cleanLine(line);
    local at = string.lower(clean):find(M.FALLS_TEXT, 1, true);
    if at == nil then return nil; end
    local head = (clean:sub(1, at - 1):gsub('%s+$', ''));
    -- "The Forest Hare falls..." / "Hare Familiar falls..." -- the article is
    -- the message's, never part of a name.
    head = (head:gsub('^[Tt]he%s+', ''));
    return head;
end

-- Is this chat line MY pet falling? `petName` is the last-seen pet name; nil
-- means "we never read a name", and then any falls line whose subject names
-- nobody in particular (the FALLS_SELF forms) still counts. A line naming some
-- OTHER entity -- the mob you just killed -- never does, which is the whole
-- reason the subject is read at all.
function M.isPetFalls(line, petName)
    local subj = M.fallsSubject(line);
    if subj == nil then return false; end
    local ls = string.lower(subj);
    if M.FALLS_SELF[ls] == true then return true; end
    local pn = normName(petName);
    if pn == nil then return false; end
    return ls == string.lower(pn);
end

-- THE classification. PURE: the last PRESENT vitals record, the current record
-- and a context table in; the verdict out. No AshitaCore, no clock, no state --
-- every rule below is a headless check (PVL*).
--
-- ctx = {
--   corpse   = <true|false|nil>,   -- the DEATH WITNESS (M.corpseVerdict): the
--                                  -- remembered index re-read by id
--   falls    = <true | <subject string> | nil>,  -- a pet-falls line inside the window
--   leave    = <true|false|nil>,   -- an outgoing Leave was OBSERVED
--   zoning   = <true|false|nil>,   -- the authoritative zoning probe
--   logout   = <true|false|nil>,   -- logging out
--   origin   = 'jug'|'charm'|nil,  -- what we watched you SUMMON it with
--   isJugPet = function(name) -> true|false|nil,  -- the caller's NAME authority
--   lowHp    = <number|nil>,       -- override M.LOW_HP_PCT
-- }
-- returns {
--   lost      = <bool>,            -- a pet that WAS out is not out now
--   kind      = 'death' | 'leave' | 'zone' | 'logout' | 'unknown' | 'none',
--   confirmed = <bool>,            -- death, and PROVEN so (never inferred)
--   how       = 'corpse' | 'falls' | 'low-hp' | nil,   -- which proof confirmed it
--   pet       = 'jug' | 'charm' | 'unknown',
--   name, hpp                      -- the pet as last seen
-- }
--
-- ORDER IS THE LAW. The three suppressors are checked BEFORE any death proof,
-- so a Leave pressed on a dying pet, or a zone line crossed mid-fight, can
-- never be read as a death -- the issue's "an observed outgoing Leave, zoning,
-- and logout each suppress", literally. Everything unproven is `unknown`, which
-- confirms nothing and lets no consumer act.
--
-- JUG vs CHARM is decided by NAME, through the caller's injected authority --
-- jug pets carry unique pet names, charmed ones keep their mob names. The
-- service deliberately does not own that list: it is the BST module's data
-- (jobhelpers\bst\jugs), and the next module's will be its own.
function M.classifyLoss(prev, cur, ctx)
    ctx = (type(ctx) == 'table') and ctx or {};
    local p = (type(prev) == 'table') and prev or nil;
    local c = (type(cur) == 'table') and cur or {};

    -- No pet was out, or one still is: there is no loss to classify.
    if p == nil or p.present ~= true then return { lost = false, kind = 'none', pet = 'unknown' }; end
    if c.present == true then return { lost = false, kind = 'none', pet = 'unknown' }; end

    local name = normName(p.name);
    local hpp  = tonumber(p.hpp);

    -- Which kind of pet was it?
    --
    -- PROVENANCE FIRST (2026-07-30): if we watched you press Call Beast or
    -- Bestial Loyalty and a pet appeared, that pet is a jug pet -- no list can
    -- be more authoritative about it than the summon itself, and this is what
    -- makes a CUSTOM jug (which this server advertises and no roster here
    -- describes) resummon like any other. Charm is the same statement in
    -- reverse. The NAME authority is the fallback, for the pet that was already
    -- out before dlac loaded.
    --
    -- Positive answers only, either way: an origin we did not see and an
    -- authority that cannot tell both leave this 'unknown', and an unknown pet
    -- is not a jug pet.
    local pet = 'unknown';
    if ctx.origin == 'jug' or ctx.origin == 'charm' then
        pet = ctx.origin;
    elseif type(ctx.isJugPet) == 'function' and name ~= nil then
        local ok, isJug = pcall(ctx.isJugPet, name);
        if ok then
            if isJug == true then pet = 'jug';
            elseif isJug == false then pet = 'charm'; end
        end
    end

    local out = { lost = true, confirmed = false, pet = pet, name = name, hpp = hpp };

    -- 1. The suppressors, in the order a player would read them.
    if ctx.zoning == true then out.kind = 'zone';   return out; end
    if ctx.logout == true then out.kind = 'logout'; return out; end
    if ctx.leave  == true then out.kind = 'leave';  return out; end

    -- 1b. The corpse says it is ALIVE. That is not a death and no other proof
    --     may override it: live memory outranks a chat line and a guess alike
    --     (hard rule 9). A pet still standing at its own index simply stopped
    --     being ours -- a charm break, a dismissal nobody observed.
    if ctx.corpse == false then out.kind = 'unknown'; return out; end

    -- 2. The proofs of death, strongest first.
    --
    --    THE CORPSE is the witness that actually works here: same entity, zero
    --    HP or a dead status, matched by ID. The falls line is kept because it
    --    costs nothing and is right wherever a server does send one -- but on
    --    CatsEyeXI a pet death is silent (see corpseVerdict's header), so it is
    --    no longer what this rule rests on. The low last-seen HP% is now a
    --    LAST resort, and only when the corpse could not be read at all: it is
    --    a guess, and a guess must never outvote a witness that is available.
    if ctx.corpse == true then
        out.kind, out.confirmed, out.how = 'death', true, 'corpse';
        return out;
    end
    if ctx.falls ~= nil and ctx.falls ~= false then
        out.kind, out.confirmed, out.how = 'death', true, 'falls';
        return out;
    end
    if ctx.corpse == nil and hpp ~= nil and hpp <= (tonumber(ctx.lowHp) or M.LOW_HP_PCT) then
        out.kind, out.confirmed, out.how = 'death', true, 'low-hp';
        return out;
    end

    -- 3. Gone, with nothing to say why. Confirms nothing.
    out.kind = 'unknown';
    return out;
end

-- A short human line for a loss edge -- the Panel's report, never chat (a loss
-- the module does not act on is not news). Pure.
local LOSS_TEXT = {
    ['zone']    = 'your pet was left behind by zoning',
    ['logout']  = 'your pet was dismissed by logging out',
    ['leave']   = 'you dismissed your pet with Leave',
    ['unknown'] = 'your pet went away and nothing confirmed a death',
};

function M.lossText(edge)
    if type(edge) ~= 'table' or edge.lost ~= true then return 'no pet loss yet'; end
    local who = edge.name or 'your pet';
    if edge.kind == 'death' then
        local how = 'it fell';
        if edge.how == 'corpse' then how = 'it went down where it stood'; end
        if edge.how == 'low-hp' then how = 'it vanished at ' .. tostring(edge.hpp or '?') .. '% HP'; end
        if edge.pet == 'charm' then return who .. ' (charmed) died -- ' .. how; end
        return who .. ' died -- ' .. how;
    end
    return LOSS_TEXT[edge.kind] or 'your pet is gone';
end

-- ---------------------------------------------------------------------------
-- the SIGNAL inbox -- what the world told us, with a shelf life
-- ---------------------------------------------------------------------------
--
-- Signals are noted by the live glue (a `text_in` falls line, an observed
-- outgoing Leave) and read by the classifier the moment a pet vanishes. Each
-- carries its own stamp and expires after SIGNAL_TTL_S, so nothing observed a
-- minute ago can explain a pet lost now.

local _sig = {};    -- kind -> { at = <sec>, name = <string|nil> }

-- Note a signal. `kind` is 'falls' or 'leave'; `name` rides along for 'falls'
-- (the subject the line named). Returns true when it was stored.
function M.noteSignal(kind, now, name)
    if type(kind) ~= 'string' or kind == '' then return false; end
    _sig[kind] = { at = tonumber(now) or M._now(), name = normName(name) };
    return true;
end

-- The signals still inside the TTL window at `now`, as the classifier's ctx
-- shape ({ falls = <name|true|nil>, leave = <true|nil> }). Expired entries are
-- dropped on the way past. A clock that went BACKWARDS keeps the signal rather
-- than expiring it (the engagewatch debounce rule).
function M.signals(now)
    now = tonumber(now) or M._now();
    local out = {};
    for kind, s in pairs(_sig) do
        local age = now - (tonumber(s.at) or 0);
        if age > M.SIGNAL_TTL_S then
            _sig[kind] = nil;
        else
            -- Plain if, never `s.name or true` -- a name of `false` is not a
            -- thing, but the ternary trap is a documented house bug.
            if s.name ~= nil then out[kind] = s.name; else out[kind] = true; end
        end
    end
    return out;
end

function M.clearSignals() _sig = {}; end

-- One rendered chat line -> a falls signal, when it is one. Runs on the MAIN
-- thread (`text_in`), so it may do real work. `petName` defaults to the last
-- PRESENT pet's name -- the line has to be about MY pet.
function M.onTextLine(line, now, petName)
    if petName == nil then
        local lp = M.lastPresent();
        if type(lp) == 'table' then petName = lp.name; end
    end
    if not M.isPetFalls(line, petName) then return false; end
    return M.noteSignal('falls', now, M.fallsSubject(line));
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

-- ONE entity, by target index, read RAW -- no dead-pet law, no pet attachment.
-- This is the death witness's read and the only one in the service that is
-- allowed to see a corpse: { id, hpp, status } or nil when it cannot read.
-- Status comes back as the raw number (see M.DEAD_STATUS).
M.reads.entity = function(index)
    local idx = tonumber(index);
    if idx == nil then return nil; end
    local t = nil;
    pcall(function()
        local em = AshitaCore:GetMemoryManager():GetEntity();
        if em == nil then return; end
        t = { id = em:GetServerId(idx), hpp = em:GetHPPercent(idx), status = em:GetStatus(idx) };
    end);
    return t;
end;

-- Am I ZONING right now? The authoritative probe is the dispatch / helmwatch /
-- jobhelpers one (GetIsZoning may answer bool OR number), with the gData Status
-- string as the second witness. nil = could not tell, which never suppresses --
-- an unreadable world does not manufacture a reason (the buff-cache discipline).
M.reads.zoning = function()
    local z = nil;
    pcall(function()
        local g = rawget(_G, 'gData');
        if type(g) == 'table' and type(g.GetPlayer) == 'function' then
            local p = g.GetPlayer();
            if type(p) == 'table' and p.Status == 'Zoning' then z = true; end
        end
    end);
    if z == true then return true; end
    pcall(function()
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        if pl == nil or pl.GetIsZoning == nil then return; end
        local v = pl:GetIsZoning();
        if v == true or (type(v) == 'number' and v ~= 0) then z = true;
        elseif v == false or (type(v) == 'number' and v == 0) then z = false; end
    end);
    return z;
end;

-- Am I LOGGING OUT? The PRIMARY witness is the zoning probe above -- the client
-- zones out to log out, so a logout is already a zone as far as a lost pet is
-- concerned. This is the explicit second one, and it is deliberately lopsided:
-- only the login status that CANNOT be a normal in-game state answers true, and
-- every other value answers nil = unknown.
--
-- The lopsidedness is the point (hard rules 2 and 12). The enum's in-game value
-- is not field-verified here, and a read that guessed it wrong the other way --
-- reporting "logging out" during ordinary play -- would suppress every death
-- and silently disable the whole Resummon rule, which is exactly the failure
-- that must not look like normal operation. Unknown suppresses nothing, and the
-- death still has to be PROVEN before anything acts.
M.LOGIN_NONE = 0;    -- "no session at all" -- unreachable while actually playing

M.reads.loggingOut = function()
    local out = nil;
    pcall(function()
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        if pl == nil or type(pl.GetLoginStatus) ~= 'function' then return; end
        local st = pl:GetLoginStatus();
        if type(st) ~= 'number' then return; end
        if st == M.LOGIN_NONE then out = true; end
    end);
    return out;
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

-- The loss edge's own state (issue #141).
local _lossSubs = {};    -- who -> cb
local _prev     = nil;   -- the last PRESENT vitals record (the loss edge's "before")
local _lastLoss = nil;   -- the last classified loss (what lastLoss() answers)
local _origin   = nil;   -- 'jug' | 'charm' | nil -- how the CURRENT pet got here

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

-- Subscribe to the classified PET-LOSS EDGE. Separate from the per-beat vitals
-- on purpose: a loss is an EVENT and the vitals are a state, and a consumer of
-- one is usually not a consumer of the other. cb(edge) is pcall'd, like the
-- beat's -- one throwing consumer never costs another its notification.
function M.subscribeLoss(who, cb)
    if type(who) ~= 'string' or who == '' then return false; end
    if type(cb) ~= 'function' then return false; end
    _lossSubs[who] = cb;
    return true;
end

function M.unsubscribeLoss(who)
    if type(who) ~= 'string' then return false; end
    _lossSubs[who] = nil;
    return true;
end

function M.lossSubscriberCount()
    local n = 0;
    for _ in pairs(_lossSubs) do n = n + 1; end
    return n;
end

-- The last PUBLISHED record, or nil before the first beat. Deliberately not the
-- answer to "how is my pet" -- that is get(), which reads the world now.
function M.last() return _last; end

-- The last record in which a pet WAS present -- the loss edge's "before", and
-- what a falls line is matched against. nil once a loss has been classified.
function M.lastPresent() return _prev; end

-- The last classified loss edge, or nil. The Panel reports it; nothing acts on
-- it twice (the edge is pushed once, when it happens).
function M.lastLoss() return _lastLoss; end

-- How the pet that is out RIGHT NOW got here ('jug' / 'charm'), or nil when we
-- did not see it summoned. Read-only; the classifier consumes it directly.
function M.origin() return _origin; end

-- Drop the published record (job change / logout / test reset). Subscribers
-- survive a reset(false); reset(true) drops them too.
function M.reset(dropSubs)
    _last, _lastAt = nil, nil;
    _prev, _lastLoss, _origin = nil, nil, nil;
    M.clearSignals();
    if dropSubs == true then _subs = {}; _lossSubs = {}; end
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

-- Advance the loss edge one beat. `v` is this beat's vitals record. A pet that
-- is out is simply REMEMBERED; a pet that was out and is not now is classified
-- ONCE, published to the loss subscribers, and forgotten -- so a long petless
-- stretch never re-fires the edge. Returns the edge, or nil when nothing was
-- lost this beat. `reads` overrides the world reads (tests); `isJugPet` comes
-- from M.lossCtx so the caller's name authority is injectable as a whole.
function M._advance(v, now, reads)
    if type(v) ~= 'table' then return nil; end
    if v.present == true then
        -- A pet that JUST appeared takes its provenance from what we watched
        -- you press. Keyed on the identity, not on presence: a pet swapped for
        -- another inside one beat is a new pet and must not inherit the old
        -- one's origin.
        local fresh = (_prev == nil);
        if not fresh and _prev.id ~= nil and v.id ~= nil and _prev.id ~= v.id then fresh = true; end
        if fresh then
            local sig = M.signals(now);
            if type(sig.summon) == 'string' then _origin = sig.summon; else _origin = nil; end
        end
        _prev = v;
        return nil;
    end
    if _prev == nil then return nil; end          -- nothing was out: no edge

    local r = (type(reads) == 'table') and reads or M.reads;
    local ctx = M.signals(now);
    ctx.isJugPet = M.lossCtx.isJugPet;
    ctx.origin   = _origin;

    -- THE DEATH WITNESS: go back and read the index the pet was at. Done HERE,
    -- on the same beat that saw the vanish, so the answer describes the same
    -- moment the loss does -- and it is READY by then: the field capture shows
    -- the entity reading 0 HP / Dead within a millisecond of the pet detaching,
    -- and still reading it 15 seconds later.
    if type(r.entity) == 'function' and _prev.index ~= nil then
        local ok, ent = pcall(r.entity, _prev.index);
        if ok then ctx.corpse = M.corpseVerdict(_prev.id, ent); end
    end
    if type(r.zoning) == 'function' then
        local ok, z = pcall(r.zoning);
        if ok then ctx.zoning = z; end
    end
    if type(r.loggingOut) == 'function' then
        local ok, lo = pcall(r.loggingOut);
        if ok then ctx.logout = lo; end
    end

    local edge = M.classifyLoss(_prev, v, ctx);
    edge.at = tonumber(now) or M._now();
    _prev, _lastLoss, _origin = nil, edge, nil;
    -- The signals explained THIS loss; they must not explain the next one too.
    M.clearSignals();
    for _, cb in pairs(_lossSubs) do pcall(cb, edge); end
    return edge;
end

-- The loss edge's injected NAME AUTHORITY: "is a pet with this name a jug pet?"
-- Set by the consumer that owns the list (the BST Helper points it at
-- jobhelpers\bst\jugs). Unset, it answers nil = cannot tell, and the classifier
-- reports pet = 'unknown', which is not a jug and lets nothing act.
M.lossCtx = { isJugPet = function() return nil; end };

-- One beat: read the vitals and push them to every subscriber, at most once per
-- TICK_S. Returns the published record, or nil when the beat was skipped (no
-- subscribers, or inside the throttle window). `now` and `reads` are the test
-- seams. A clock that went BACKWARDS publishes rather than muting for a whole
-- window (the engagewatch debounce rule).
--
-- "Nobody listening" now includes the LOSS subscribers (issue #141): a module
-- that only wants to hear about a dead pet still needs the world read, and the
-- beat is the only thing reading it.
function M.pump(now, reads)
    if M.subscriberCount() == 0 and M.lossSubscriberCount() == 0 then return nil; end
    now = tonumber(now) or M._now();
    if _lastAt ~= nil then
        local since = now - _lastAt;
        if since >= 0 and since < M.TICK_S then return nil; end
    end
    _lastAt = now;
    -- Resolve anything the packet thread stashed BEFORE the vitals are read, so
    -- a Leave observed in the same frame as the vanish is already a signal.
    M.drainCommands(now);
    local v = M.get(reads);
    v.at = now;
    _last = v;
    for _, cb in pairs(_subs) do pcall(cb, v); end
    M._advance(v, now, reads);
    return v;
end

-- ---------------------------------------------------------------------------
-- the LEAVE observation -- network thread stashes, main thread resolves
-- ---------------------------------------------------------------------------
--
-- An outgoing pet command is an ordinary job ability: the 0x01A action packet,
-- category 0x09 (dlac's own engine routes exactly that category as 'Ability' --
-- feature\equipengine.ACTION_ROUTES), with the ability id at 0x0C. This is NOT
-- a second reader of the two battle edges engagewatch owns (0x02 engage / 0x0F
-- retarget) -- it is a different category asked a different question, and the
-- categories do not overlap.
--
-- FLAGGED for the field round: that pet commands ride category 0x09 on
-- CatsEyeXI is the repo's own route table, not a live observation. It FAILS
-- SAFE either way -- an unobserved Leave leaves the death unproven (a dismissed
-- pet was almost never below LOW_HP_PCT), so the worst case is the loud, early
-- suppression is missed and the quiet one still holds.
M.PKT_ACTION  = 0x01A;
M.CAT_ABILITY = 0x09;

-- The ability the observation is looking for, matched case-insensitively by
-- NAME through the client's own resource tables -- live memory is the top data
-- authority (hard rule 9), and it means no recast/ability id is hardcoded here.
M.LEAVE_NAME = 'leave';

-- The abilities that give a pet its PROVENANCE. Watched the same way and for
-- the same reason as Leave: what you pressed is the most authoritative
-- statement available about what the pet that just appeared IS, and it is the
-- only one that holds for a custom jug no roster describes. Matched
-- case-insensitively by name through the client's own resources, so nothing
-- here hardcodes an ability id.
M.SUMMON_NAMES = {
    ['call beast']      = 'jug',
    ['bestial loyalty'] = 'jug',
    ['charm']           = 'charm',
};

local _cmdQueue = {};    -- { { id = <ability id>, at = <sec> }, .. } from the packet thread
local _nameMemo = {};    -- ability id -> lowercased name (or false when unresolvable)

M.CMD_QUEUE_MAX = 8;

-- Pure decode: the outgoing action packet's category + ability id, or nil when
-- it is not an ability. Bytes in, numbers out (the engagewatch shape).
function M.decodeCommand(data)
    if type(data) ~= 'string' or #data < 14 then return nil; end
    local function u16(off)
        local a = string.byte(data, off + 1) or 0;
        local b = string.byte(data, off + 2) or 0;
        return a + b * 256;
    end
    if u16(0x0A) ~= M.CAT_ABILITY then return nil; end
    return u16(0x0C);
end

-- Resolve an ability id to its lowercased name, memoized. Probes both binding
-- shapes this install might carry (the resource string table the buff pickers
-- use, and the object accessor) -- presence proves nothing, so neither is
-- assumed (hard rule 2). false = tried and could not.
M._abilityName = function(id)
    local nm = nil;
    pcall(function()
        local resx = AshitaCore:GetResourceManager();
        if resx == nil then return; end
        if type(resx.GetString) == 'function' then
            local s = resx:GetString('abilities.names', id);
            if type(s) == 'string' then nm = s; end
        end
        if nm == nil and type(resx.GetAbilityById) == 'function' then
            local ab = resx:GetAbilityById(id);
            if type(ab) == 'table' then
                if type(ab.Name) == 'table' then nm = ab.Name[1]; elseif type(ab.Name) == 'string' then nm = ab.Name; end
            end
        end
    end);
    if type(nm) ~= 'string' then return nil; end
    nm = (nm:gsub('%z', ''):gsub('%s+$', ''));
    if nm == '' then return nil; end
    return string.lower(nm);
end;

-- Bare read + append: the whole of the network-thread half (the chocowatch
-- rule). Deliberately UNSTAMPED -- the packet thread has no access to this
-- service's clock without a require, and a stamp taken from a DIFFERENT clock
-- (os.clock vs the cmdqueue frame counter) would make the signal TTL compare
-- two unrelated numbers. The drain, one beat later at most, stamps it.
-- Returns the stashed ability id, or nil.
function M.onCommandPacket(data)
    local id = M.decodeCommand(data);
    if id == nil or id <= 0 then return nil; end
    if #_cmdQueue >= M.CMD_QUEUE_MAX then table.remove(_cmdQueue, 1); end
    _cmdQueue[#_cmdQueue + 1] = { id = id };
    return id;
end

-- Drain the stash on the MAIN thread: resolve each id's name and note a 'leave'
-- signal for the one that matters, stamped with THIS service's clock. Returns
-- how many Leaves were observed. `now` / `resolver` are the test seams.
function M.drainCommands(now, resolver)
    if #_cmdQueue == 0 then return 0; end
    local q = _cmdQueue;
    _cmdQueue = {};
    local resolve = (type(resolver) == 'function') and resolver or M._abilityName;
    local at = tonumber(now) or M._now();
    local seen = 0;
    for _, c in ipairs(q) do
        local nm = _nameMemo[c.id];
        if nm == nil then
            nm = resolve(c.id);
            _nameMemo[c.id] = (nm ~= nil) and nm or false;
        end
        if nm == M.LEAVE_NAME then
            M.noteSignal('leave', at);
            seen = seen + 1;
        elseif nm ~= nil and nm ~= false and M.SUMMON_NAMES[nm] ~= nil then
            -- The pet that appears next is one you asked for, and we know which
            -- kind. Rides the same TTL as every other signal: a summon that
            -- produced no pet inside the window explains nothing later.
            M.noteSignal('summon', at, M.SUMMON_NAMES[nm]);
        end
    end
    return seen;
end

-- Drop the command stash + the name memo (test reset).
function M.resetCommands()
    _cmdQueue, _nameMemo = {}, {};
end

-- ---------------------------------------------------------------------------
-- Ashita glue, guarded (headless: nothing registers, the pure halves ARE the
-- module -- the engagewatch / chocowatch shape)
-- ---------------------------------------------------------------------------

pcall(function()
    -- The pet-falls line rides ORDINARY CHAT, so it is read where the client
    -- already rendered it (history.md, the dig-obtained lesson: two packet
    -- guesses lost to one `text_in` grep). Main thread, no IO, one substring
    -- test per line.
    ashita.events.register('text_in', 'dlac-petvitals-falls', function(e)
        pcall(function()
            local msg = e.message;
            if type(msg) ~= 'string' then return; end
            if _prev == nil then return; end      -- no pet out: nothing to be about
            M.onTextLine(msg);
        end);
    end);

    ashita.events.register('packet_out', 'dlac-petvitals-petcmd', function(e)
        if e.id ~= M.PKT_ACTION then return; end
        pcall(function() M.onCommandPacket(e.data); end);
    end);
end);

return M;
