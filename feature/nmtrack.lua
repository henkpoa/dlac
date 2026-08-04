--[[
    dlac/feature/nmtrack.lua -- PASSIVE POP TRACKING: the placeholder rounds you
    have personally witnessed, and an honest refusal to guess at the rest
    (issue #155, PRD #151).

    `/dl nm <name>` already states the DISFAVOUR curve (issue #152): the base
    chance, that it is not flat, and how many placeholder ROUNDS reach a
    guaranteed pop. What it could not say is where on that curve YOU are. This
    module counts, so it can.

    AUTOMATIC, WITH NOTHING TO ARM. There is no such thing as an accidental
    placeholder kill, and the failure mode of an opt-in tracker is losing the
    data the player sat down to collect. Nothing here has a switch.

    COUNTED BY TARGET INDEX, NEVER BY NAME. Uleguerand Range holds ten Buffalo;
    only six of them (354-359) are Bonnacon's placeholders. A name-based counter
    would credit the other four -- kills that never rolled -- and the count would
    read HIGH, which is the one direction this feature must never be wrong in.
    So a kill counts only when the dying entity's target index is one of that
    NM's placeholder indexes. The one place a NAME is allowed to answer is the NM
    ITSELF (below), where a false positive can only RESET a count -- never
    inflate one.

    TWO OBSERVATIONS ALREADY IN THE ADDON, JOINED. Neither answers alone:

        feature\engagewatch  -- the ENGAGE/TARGET EDGE service knows the INDEX
                                of everything you attacked, taken from the
                                packet (issue #139).
        text_in              -- the death line names WHAT died, and nothing
                                else (the channel petvitals reads for the pet
                                falls line -- read what the client already
                                rendered, never hunt a packet for it).

    A death line is matched against the newest engaged target carrying that name,
    which is then CONSUMED -- so one engagement can credit at most one kill, and
    a second Buffalo dying elsewhere cannot borrow yours. The error that leaves
    is an UNDER-count (a placeholder killed by someone else, or pulled with magic
    and never engaged, is never seen), and that is the safe direction: the count
    is a floor and says so.

    A ROUND IS NOT A KILL. `rounds = phKills / phCount` -- for Bonnacon six kills
    make ONE round. Feeding raw kills to the curve would overstate the odds six
    times over. The curve itself is NOT re-derived here: chanceAfter /
    roundsToGuaranteed live in feature\nmlookup with their source, their
    verification date and the anchor tests that stand in for the missing server
    source (NM40*/NM41*), and this module consumes them.

    THE HONESTY RULES, which are the point of the slice:

      * THE COUNT IS A FLOOR. The server's counter is zone-wide and SHARED --
        every other player's placeholder kills raise it invisibly -- so what one
        client witnessed can only ever be at or below the truth. It is labelled
        as a floor everywhere it is rendered.
      * A BREAK IN OBSERVATION MAKES IT STALE: zoning, a relog or a reload, or an
        age past the NM's own cooldown ceiling. A stale record shows the raw
        count and WHEN it was last vouched for, and renders NO PERCENTAGE. The
        error a stale count makes runs in the optimistic direction -- someone
        else popping and killing the NM while you were away leaves your number
        high, so the readout would cheerfully say "nearly guaranteed" while you
        stand at the base rate. A number nobody can stand behind is worse than no
        number.
      * STALENESS IS STICKY. Later kills still raise the raw count (they were
        witnessed), but nothing re-vouches for the break -- only evidence of a
        pop (which zeroes the count) or an explicit `/dl nm <name> reset` starts
        a clean one.
      * EVIDENCE OF A POP RESETS IT. Seeing the NM alive (you engaged it) or
        seeing it die both mean the server's counter already fired, so ours goes
        back to zero.
      * KILLS THAT CANNOT ROLL ARE NOT COUNTED. Inside the post-kill COOLDOWN, or
        while the NM is PRIMED (you have seen it up and not seen it die), the
        server rolls nothing at all -- so those kills are tallied separately as
        wasted effort instead of being sold back as progress.

    PURE CORE, THIN FEED (PRD #151's architecture). reduce / status / lines /
    classify / rollState / deathName take plain values and answer with plain
    values -- no Ashita, no imgui, no disk -- and the tests drive those (NT*).
    The live half is two guarded registrations and one frame pump, and M.pump
    takes its live reads as a table it CALLS, so the suite drives the same code
    the game does.

    PERSISTED PER CHARACTER through the addon-side state-file facility the other
    passive watchers use (lib\statefile.charDir + lib\safewrite), at
    <char>\dlac\nmcounts.lua -- so a long camp survives a reload. Every record
    read back off disk is stale by definition: dlac was not watching between the
    write and the read.
]]--

local M = {};

M.VERSION = 1;
-- On-disk format. Bump only when a reader must behave differently, never for a
-- field a missing-value default already covers.
M.FMT = 1;

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- The lookup module is the authority for the CURVE (M.chanceAfter /
-- M.roundsToGuaranteed / M.DISFAVOUR), for the shipped TABLE (M.data) and for
-- the pop KIND (M.isLottery). Required at load: the dependency runs this way
-- only, and nmlookup reaches back for the rendered lines at CALL time, so there
-- is no load-time cycle.
local _nm    = try('dlac\\feature\\nmlookup');
local _loc   = try('dlac\\feature\\location');
local _sfile = try('dlac\\lib\\statefile');
local _safe  = try('dlac\\lib\\safewrite');

-- ---------------------------------------------------------------------------
-- constants -- every one of them a judgement, so each says why
-- ---------------------------------------------------------------------------

-- How long an engaged target stays creditable. A placeholder fight is seconds;
-- this only has to outlast a long one. Past it, a mob you engaged and walked
-- away from can no longer be credited by a death line that names its family.
M.TARGET_TTL_S = 600;

-- How many engaged targets are remembered at once. A camp is a handful of spawn
-- points; the ring exists because your client sends the RETARGET packet for the
-- next mob before the death line for the last one is rendered, so "the target I
-- am fighting" is not one slot.
M.RING = 8;

-- How long "you saw it alive" is allowed to mean "it is up". Nothing tells us an
-- NM someone else killed has died, so the claim expires rather than standing
-- forever -- past this the record simply stops claiming to know.
M.PRIMED_TTL_S = 1800;

-- The staleness ceiling for an NM whose table row carries no repop window. The
-- real ceiling is the NM's own (`w[2]`); this is only the fallback, and it is
-- the longest window the shipped table carries.
M.CEILING_S = 86400;

-- The frame pump's own throttle. Zoning and ageing do not need frame
-- resolution; a queued kill or edge bypasses this and lands the same frame.
M.TICK_S = 5.0;

-- How many camps the file keeps. Deep enough that a player working several
-- camps never loses one, bounded so a wandering character cannot grow it.
M.CAP = 40;

-- The two shapes the client renders when something dies. Matched as plain
-- substrings on the CLEANED line, never as fixed-case patterns (the digrank
-- lesson -- a case-locked pattern silently misses real messages).
--   "The Buffalo falls to the ground."   -- what you were fighting died
--   "Mindie defeats the Buffalo."        -- a party member landed the blow
-- A player being KO'd renders the FIRST shape too, with a player name in it --
-- harmless here, because a name only ever credits a kill after it has matched
-- something you engaged AND that target's index has matched a placeholder.
M.DEATH_FALLS   = 'falls to the ground';
M.DEATH_DEFEATS = 'defeats ';

-- Why a record went stale, in the player's words.
M.WHY_TEXT = {
    zone  = 'you left the zone',
    relog = 'dlac was not watching -- a relog or a reload',
    age   = 'it sat longer than this NM can hold a cooldown',
};

-- ---------------------------------------------------------------------------
-- small pure helpers
-- ---------------------------------------------------------------------------

-- A text_in line carries the client's colour/format control bytes inline, and
-- they sit exactly where a name does (the petvitals idiom -- a substring match
-- would still hit while the sliced-out name came back with control bytes stuck
-- to it and matched nothing).
local function cleanLine(msg)
    local s = tostring(msg or ''):gsub('[^\032-\126]+', ' ');
    return (s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''));
end
M._cleanLine = cleanLine;

-- "12m ago" (the foodwatch shape). Coarse on purpose: this is a readout, and a
-- count vouched for "43m ago" says everything "43m 12s ago" would.
local function agoText(sec)
    sec = tonumber(sec) or 0;
    if sec < 0 then sec = 0; end
    if sec < 90     then return string.format('%ds ago', math.floor(sec)); end
    if sec < 5400   then return string.format('%dm ago', math.floor(sec / 60 + 0.5)); end
    if sec < 172800 then return string.format('%dh ago', math.floor(sec / 3600 + 0.5)); end
    return string.format('%dd ago', math.floor(sec / 86400 + 0.5));
end
M.agoText = agoText;

-- Rounds for READING: a whole number stays whole, anything else keeps one
-- decimal. "2.3 rounds" is the honest shape of 14 kills over 6 placeholders.
local function roundsText(r)
    r = tonumber(r) or 0;
    if r == math.floor(r) then return string.format('%d', math.floor(r)); end
    return string.format('%.1f', r);
end
M.roundsText = roundsText;

local function plural(n, word)
    if n == 1 then return word; end
    return word .. 's';
end

local function lower(s)
    if type(s) ~= 'string' then return nil; end
    return s:lower();
end

-- How many placeholders this NM has. 0 when the table lists none.
function M.phCount(entry)
    if type(entry) ~= 'table' or type(entry.ph) ~= 'table' then return 0; end
    return #entry.ph;
end

-- Does the disfavour curve apply at all? Delegated to the lookup module, which
-- owns the `kind` rules; the fallback is its own pre-`kind` rule, so a data file
-- older than the kind field still tracks rather than going quiet.
function M.isLottery(entry)
    if _nm ~= nil and type(_nm.isLottery) == 'function' then return _nm.isLottery(entry); end
    return M.phCount(entry) > 0;
end

-- "1h-24h", or nil when the table carries no window.
function M.windowText(entry)
    if _nm ~= nil and type(_nm.windowText) == 'function' then return _nm.windowText(entry); end
    return nil;
end

-- The SHORTEST the post-kill cooldown can be -- the only part of it that is
-- certain. nil when the table gives no window, and then nothing is claimed.
function M.cooldownMin(entry)
    if type(entry) ~= 'table' or type(entry.w) ~= 'table' then return nil; end
    return tonumber(entry.w[1]);
end

-- The LONGEST it can be, which is also how old a count may get before nobody
-- can stand behind it: past the NM's own ceiling the camp may have popped, been
-- killed and re-armed without you.
function M.ceilingFor(entry)
    if type(entry) == 'table' and type(entry.w) == 'table' then
        local hi = tonumber(entry.w[2]) or tonumber(entry.w[1]);
        if hi ~= nil and hi > 0 then return hi; end
    end
    return M.CEILING_S;
end

-- The record key. Per (zone, NM name): the same NM name exists in several zones,
-- and a count belongs to the camp you stood in.
function M.campKey(zid, entry)
    local n = (type(entry) == 'table') and entry.n or entry;
    if type(n) ~= 'string' or n == '' then return nil; end
    return string.format('z%s|%s', tostring(zid), n);
end

-- Every NM row for a zone, or {}.
function M.campsIn(data, zid)
    if type(data) ~= 'table' or zid == nil then return {}; end
    local list = data[zid];
    if type(list) ~= 'table' then return {}; end
    return list;
end

-- The table row a stored record belongs to, or nil when the data no longer
-- carries it (a regenerated table that dropped an NM must not error).
function M.campFor(data, rec)
    if type(rec) ~= 'table' then return nil; end
    for _, e in ipairs(M.campsIn(data, rec.zone)) do
        if type(e) == 'table' and e.n == rec.nm then return e; end
    end
    return nil;
end

-- ---------------------------------------------------------------------------
-- classify -- the rule the whole feature stands on
-- ---------------------------------------------------------------------------
--
-- Which camp does this entity belong to, and as what? -> entry, 'nm' | 'ph'
--
-- INDEX IS THE AUTHORITY. Ten same-named Buffalo in one zone, six of them
-- placeholders, is exactly the case this exists for: a placeholder is a SPAWN
-- POINT, not a name.
--
-- A NAME answers for the NM alone, and only when the index did not. That
-- asymmetry is deliberate and it is about the direction of the error: a wrong
-- placeholder match INFLATES a count (the failure this feature exists to
-- prevent), while a wrong NM match only RESETS one -- it can cost you a count
-- you had, never hand you one you did not earn.
function M.classify(camps, index, name)
    if type(camps) ~= 'table' then return nil, nil; end
    local idx  = tonumber(index);
    local want = lower(name);
    if idx ~= nil then
        -- Pass 1: the NM itself, by index. First, because pop evidence outranks
        -- a placeholder kill if one entity ever answers both.
        for _, e in ipairs(camps) do
            if type(e) == 'table' and type(e.nm) == 'table' then
                for _, v in ipairs(e.nm) do
                    if tonumber(v) == idx then return e, 'nm'; end
                end
            end
        end
        -- Pass 2: a placeholder, BY INDEX ONLY.
        for _, e in ipairs(camps) do
            if type(e) == 'table' and type(e.ph) == 'table' then
                for _, v in ipairs(e.ph) do
                    if tonumber(v) == idx then return e, 'ph'; end
                end
            end
        end
    end
    -- Pass 3: the NM by NAME, and only now that the index has had both its
    -- chances -- so a placeholder can never be reached this way even when its
    -- display name collides with some other camp's NM.
    if want ~= nil and want ~= '' then
        for _, e in ipairs(camps) do
            if type(e) == 'table' and lower(e.n) == want then return e, 'nm'; end
        end
    end
    return nil, nil;
end

-- ---------------------------------------------------------------------------
-- can a placeholder kill roll at all right now?
-- ---------------------------------------------------------------------------
--
-- Two states from the server's own gates (PRD #151), both additive to the
-- curve, and both meaning the same thing to a camper: killing placeholders is
-- wasted effort right now.
--
--   'primed'   -- you have seen the NM alive and not seen it die. While it is
--                 spawned or queued the server skips the roll entirely.
--   'cooldown' -- you saw it die, and less time has passed than the SHORTEST
--                 cooldown it can draw. Nothing rolls inside that.
--
-- Between the shortest and the longest cooldown nothing is certain, so nothing
-- is claimed: the state is 'ok' with `hedge` true, which the readout says out
-- loud rather than quietly counting as if it knew.
-- -> state, hedge
function M.rollState(rec, entry, now)
    now = tonumber(now) or 0;
    if type(rec) ~= 'table' then return 'ok', false; end
    local sawAt = tonumber(rec.sawAt) or 0;
    local age   = now - sawAt;
    if rec.saw == 'alive' then
        -- A break in observation kills the claim: you cannot say a monster is
        -- still up after you stopped watching it.
        if rec.stale ~= true and age >= 0 and age <= M.PRIMED_TTL_S then return 'primed', false; end
        return 'ok', false;
    end
    if rec.saw == 'dead' then
        local lo = M.cooldownMin(entry);
        if lo ~= nil and age >= 0 and age < lo then return 'cooldown', false; end
        if age >= 0 and age < M.ceilingFor(entry) then return 'ok', true; end
    end
    return 'ok', false;
end

-- ---------------------------------------------------------------------------
-- THE REDUCER -- events and state in, new state out
-- ---------------------------------------------------------------------------
--
--   state = { [campKey] = record }
--   ev    = { kind = 'kill' | 'sight' | 'zone' | 'relog' | 'tick',
--             index = <target index>, name = <string>, at = <epoch sec> }
--   ctx   = { data = <the nmdata table>, zone = <zone id>, now = <epoch sec> }
--
-- Pure: the input state is never mutated -- the answer is a new table sharing
-- every record the event did not touch. -> state, changed
--
-- A record:
--   { zone, nm, kills, void, ph, at, since, stale, why, saw, sawAt }
--     kills -- placeholder kills witnessed that COULD roll
--     void  -- kills witnessed while nothing could roll (wasted effort)
--     at    -- when the count was last vouched for
--     saw   -- the last pop evidence: 'alive' (you engaged it) or 'dead'

local function copyState(state)
    local out = {};
    if type(state) == 'table' then
        for k, v in pairs(state) do out[k] = v; end
    end
    return out;
end

local function copyRec(rec)
    local out = {};
    for k, v in pairs(rec) do out[k] = v; end
    return out;
end

local function newRec(zid, entry, now)
    return { zone = zid, nm = entry.n, kills = 0, void = 0,
             ph = M.phCount(entry), at = now, since = now };
end
M._newRec = newRec;

function M.reduce(state, ev, ctx)
    local out = copyState(state);
    if type(ev) ~= 'table' then return out, false; end
    ctx = (type(ctx) == 'table') and ctx or {};
    local now  = tonumber(ev.at) or tonumber(ctx.now) or 0;
    local kind = ev.kind;

    -- A BREAK IN OBSERVATION. Every live record goes stale and keeps its raw
    -- count: the number is still what you witnessed, it just stops being
    -- something anyone can stand behind.
    if kind == 'zone' or kind == 'relog' then
        local why, changed = kind, false;
        for k, rec in pairs(out) do
            if type(rec) == 'table' and rec.stale ~= true then
                local r = copyRec(rec);
                r.stale, r.why = true, why;
                out[k] = r;
                changed = true;
            end
        end
        return out, changed;
    end

    -- AGE. Past the NM's own cooldown ceiling the camp may have popped, been
    -- killed and re-armed without you -- the count cannot be vouched for.
    if kind == 'tick' then
        local changed = false;
        for k, rec in pairs(out) do
            if type(rec) == 'table' and rec.stale ~= true then
                local ceiling = M.ceilingFor(M.campFor(ctx.data, rec));
                if (now - (tonumber(rec.at) or 0)) > ceiling then
                    local r = copyRec(rec);
                    r.stale, r.why = true, 'age';
                    out[k] = r;
                    changed = true;
                end
            end
        end
        return out, changed;
    end

    if kind ~= 'kill' and kind ~= 'sight' then return out, false; end

    -- A zone we could not read is not a zone we may guess at: an unattributable
    -- kill is dropped rather than credited to the last camp we knew.
    local camps = M.campsIn(ctx.data, ctx.zone);
    if #camps == 0 then return out, false; end
    local entry, role = M.classify(camps, ev.index, ev.name);
    if entry == nil then return out, false; end
    local key = M.campKey(ctx.zone, entry);
    if key == nil then return out, false; end

    -- EVIDENCE OF A POP. Alive or dead, the server's counter has already fired,
    -- so ours goes back to zero -- and the record is freshly vouched for, which
    -- is the one thing that clears staleness without a player asking.
    if role == 'nm' then
        local r = copyRec(out[key] or newRec(ctx.zone, entry, now));
        r.kills, r.void = 0, 0;
        r.stale, r.why  = nil, nil;
        r.ph            = M.phCount(entry);
        r.at, r.since   = now, now;
        r.saw           = (kind == 'kill') and 'dead' or 'alive';
        r.sawAt         = now;
        out[key] = r;
        return out, true;
    end

    -- A placeholder. Engaging one is not news; only its death is.
    if kind ~= 'kill' then return out, false; end
    -- Only a lottery rolls. A `scripted` NM's placeholders roll nothing, so a
    -- count here would invent a curve the server does not run.
    if not M.isLottery(entry) then return out, false; end

    local r = copyRec(out[key] or newRec(ctx.zone, entry, now));
    local roll = M.rollState(r, entry, now);
    r.ph = M.phCount(entry);
    if roll == 'ok' then
        r.kills = (tonumber(r.kills) or 0) + 1;
        r.at    = now;                    -- witnessed, and it counted
    else
        -- Wasted effort, kept as its own number. Counting it would sell back
        -- progress the server never made, and `at` must not move: nothing
        -- vouched for the count.
        r.void = (tonumber(r.void) or 0) + 1;
    end
    out[key] = r;
    return out, true;
end

-- ---------------------------------------------------------------------------
-- status -- one record, read as plain values
-- ---------------------------------------------------------------------------
--
-- THE ONE RULE THAT MATTERS: a stale record has NO chance. Not a hedged one,
-- not a greyed-out one -- nil. Everything downstream renders what it is given.
function M.status(rec, entry, now)
    now = tonumber(now) or 0;
    local base = nil;
    if type(entry) == 'table' then base = tonumber(entry.c); end
    local out = {
        kills = 0, void = 0, rounds = 0,
        ph = M.phCount(entry), base = base,
        chance = nil, guaranteed = nil, roundsLeft = nil, killsLeft = nil,
        stale = false, why = nil, roll = 'ok', hedge = false,
        at = nil, ago = nil, since = nil, saw = nil, sawAgo = nil,
        lottery = M.isLottery(entry),
    };
    if _nm ~= nil and type(_nm.roundsToGuaranteed) == 'function' then
        out.guaranteed = _nm.roundsToGuaranteed(base);
    end
    if type(rec) ~= 'table' then return out; end

    out.kills = tonumber(rec.kills) or 0;
    out.void  = tonumber(rec.void) or 0;
    if out.ph <= 0 then out.ph = tonumber(rec.ph) or 0; end
    out.stale = (rec.stale == true);
    out.why   = rec.why;
    out.at    = tonumber(rec.at);
    out.since = tonumber(rec.since);
    if out.at ~= nil then out.ago = now - out.at; end
    out.saw = rec.saw;
    if rec.sawAt ~= nil then out.sawAgo = now - (tonumber(rec.sawAt) or 0); end
    out.roll, out.hedge = M.rollState(rec, entry, now);

    -- A round is not a kill: for Bonnacon six kills make one round.
    if out.ph > 0 then out.rounds = out.kills / out.ph; end

    if out.guaranteed ~= nil then
        local left = out.guaranteed - out.rounds;
        if left < 0 then left = 0; end
        out.roundsLeft = left;
        if out.ph > 0 then out.killsLeft = math.ceil(left * out.ph - 1e-9); end
    end

    -- The percentage, and the one place it is withheld.
    if not out.stale and _nm ~= nil and type(_nm.chanceAfter) == 'function' then
        out.chance = _nm.chanceAfter(base, out.rounds);
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- lines -- what a camper reads
-- ---------------------------------------------------------------------------
--
-- Pure: a record and a table row in, chat lines out. Appended by nmlookup under
-- the curve it already prints, because "where you are on it" belongs beside
-- "what it does".
function M.lines(rec, entry, now)
    local out = {};
    if type(entry) ~= 'table' then return out; end
    -- No lottery, no rounds to count: a scripted pop borrowing this language is
    -- the wasted camp `/dl nm` exists to prevent.
    if not M.isLottery(entry) or M.phCount(entry) <= 0 then return out; end
    now = tonumber(now) or 0;

    if type(rec) ~= 'table' then
        out[#out + 1] = '  no count here yet -- placeholder kills count themselves, with nothing to arm.';
        return out;
    end

    local st = M.status(rec, entry, now);

    -- 1. Can a kill even roll right now?
    local w = M.windowText(entry);
    if st.roll == 'primed' then
        out[#out + 1] = string.format(
            '  kills cannot roll right now -- you saw it alive %s, and nothing rolls while it is up or queued.',
            agoText(st.sawAgo));
    elseif st.roll == 'cooldown' then
        out[#out + 1] = string.format(
            '  kills cannot roll right now -- you saw it die %s, and its post-kill cooldown runs %s.',
            agoText(st.sawAgo), w or 'up to a day');
    elseif st.hedge then
        out[#out + 1] = string.format(
            '  you saw it die %s -- its cooldown runs %s, so kills since then may not have rolled.',
            agoText(st.sawAgo), w or 'up to a day');
    end

    -- 2. The count itself.
    if st.stale then
        out[#out + 1] = string.format(
            '  your count: %d %s, last vouched for %s -- STALE (%s), so no chance is shown: it may have popped while you were not watching.',
            st.kills, plural(st.kills, 'placeholder kill'), agoText(st.ago),
            M.WHY_TEXT[st.why] or 'observation broke');
    elseif st.kills > 0 then
        local head = string.format('  your count: %d %s = %s %s',
            st.kills, plural(st.kills, 'placeholder kill'),
            roundsText(st.rounds), plural(st.rounds, 'round'));
        if st.chance ~= nil and st.guaranteed ~= nil and _nm ~= nil then
            out[#out + 1] = string.format('%s -- %s now, %s %s (%d %s) to a guaranteed pop.',
                head, _nm.pctText(st.chance), roundsText(st.roundsLeft),
                plural(st.roundsLeft, 'round'), st.killsLeft or 0,
                plural(st.killsLeft or 0, 'kill'));
        else
            out[#out + 1] = head ..
                ' -- the table carries no base chance for this one, so no percentage can be worked out.';
        end
    elseif st.saw == nil then
        out[#out + 1] = '  no count here yet -- placeholder kills count themselves, with nothing to arm.';
    else
        out[#out + 1] = '  your count: 0 -- it started over when you last saw the NM itself.';
    end

    -- 3. Wasted effort, kept honest and separate.
    if st.void > 0 then
        out[#out + 1] = string.format('  %d further %s landed while nothing could roll -- not counted.',
            st.void, plural(st.void, 'kill'));
    end

    -- 4. The floor. Said every time a number is shown, because the number is
    -- worth less than the caveat to anyone camping a contested spawn.
    if st.kills > 0 then
        out[#out + 1] = '  a FLOOR, never the server\'s own number -- its counter is zone-wide and shared, and other players\' placeholder kills are invisible to you.';
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- the death line
-- ---------------------------------------------------------------------------
--
-- -> the NAME of what died, or nil. Never an index: the line does not carry one,
-- which is exactly why this half is joined to the engage edge.
function M.deathName(line)
    if type(line) ~= 'string' then return nil; end
    local clean = cleanLine(line);
    local low   = clean:lower();

    local at = low:find(M.DEATH_FALLS, 1, true);
    if at ~= nil then
        local head = clean:sub(1, at - 1):gsub('%s+$', '');
        head = head:gsub('^[Tt]he%s+', '');       -- the article is the message's
        if head == '' then return nil; end
        return head;
    end

    at = low:find(M.DEATH_DEFEATS, 1, true);
    if at ~= nil then
        local tail = clean:sub(at + #M.DEATH_DEFEATS);
        tail = tail:gsub('^[Tt]he%s+', '');
        tail = tail:gsub('%s*%.%s*$', ''):gsub('%s+$', '');
        if tail == '' then return nil; end
        return tail;
    end
    return nil;
end

-- ---------------------------------------------------------------------------
-- disk -- the passive-watcher shape (foodwatch's, path truth from lib\statefile)
-- ---------------------------------------------------------------------------

M.state = {};             -- [campKey] = record
M._loadedFrom = nil;      -- the path M.state mirrors (nil = never loaded)

function M.path()
    local dir = (_sfile ~= nil) and _sfile.charDir() or nil;
    if dir == nil then return nil; end
    return dir .. 'nmcounts.lua';
end

-- Newest-vouched first, capped. Deterministic: a tie breaks on the key, so the
-- file is byte-stable when nothing changed.
local function ordered(state)
    local keys = {};
    for k, rec in pairs((type(state) == 'table') and state or {}) do
        if type(rec) == 'table' and type(rec.nm) == 'string' then keys[#keys + 1] = k; end
    end
    table.sort(keys, function(a, b)
        local ra, rb = state[a], state[b];
        local ta, tb = tonumber(ra.at) or 0, tonumber(rb.at) or 0;
        if ta ~= tb then return ta > tb; end
        return a < b;
    end);
    return keys;
end
M._ordered = ordered;

function M._serialize(state)
    local L = {
        '-- dlac NM pop counts -- the placeholder kills this character personally',
        '-- witnessed, per camp, and when each count was last vouched for.',
        '-- Written by dlac (feature\\nmtrack); safe to delete, never hand-edited.',
        'return {',
        string.format('    fmt = %d,', M.FMT),
        '    camps = {',
    };
    local keys = ordered(state);
    for i, k in ipairs(keys) do
        if i > M.CAP then break; end
        local r = state[k];
        local extra = '';
        if r.stale == true then
            extra = string.format(', stale = true, why = %q', tostring(r.why or 'relog'));
        end
        if r.saw ~= nil then
            extra = extra .. string.format(', saw = %q, sawAt = %d',
                tostring(r.saw), math.floor(tonumber(r.sawAt) or 0));
        end
        L[#L + 1] = string.format(
            '        { zone = %d, nm = %q, kills = %d, void = %d, ph = %d, at = %d, since = %d%s },',
            math.floor(tonumber(r.zone) or 0), tostring(r.nm),
            math.floor(tonumber(r.kills) or 0), math.floor(tonumber(r.void) or 0),
            math.floor(tonumber(r.ph) or 0), math.floor(tonumber(r.at) or 0),
            math.floor(tonumber(r.since) or 0), extra);
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '}';
    return table.concat(L, '\n') .. '\n';
end

-- Parsed file -> the shape the rest of this module assumes. A malformed row is
-- DROPPED rather than half-read: a count nobody can key to a camp is noise.
function M._fromRaw(t)
    local out = {};
    if type(t) ~= 'table' or type(t.camps) ~= 'table' then return out; end
    for _, r in ipairs(t.camps) do
        if type(r) == 'table' and tonumber(r.zone) ~= nil
           and type(r.nm) == 'string' and r.nm ~= '' then
            local key = M.campKey(tonumber(r.zone), r.nm);
            if key ~= nil then
                out[key] = {
                    zone  = tonumber(r.zone),
                    nm    = r.nm,
                    kills = math.max(0, math.floor(tonumber(r.kills) or 0)),
                    void  = math.max(0, math.floor(tonumber(r.void) or 0)),
                    ph    = math.max(0, math.floor(tonumber(r.ph) or 0)),
                    at    = tonumber(r.at) or 0,
                    since = tonumber(r.since) or tonumber(r.at) or 0,
                    stale = (r.stale == true) or nil,
                    why   = (r.stale == true) and tostring(r.why or 'relog') or nil,
                    saw   = (r.saw == 'alive' or r.saw == 'dead') and r.saw or nil,
                    sawAt = tonumber(r.sawAt) or nil,
                };
            end
        end
    end
    return out;
end

-- Read once per path. The path CHANGES with the character and the active
-- Profile, so it is the key rather than a one-shot flag (the foodwatch rule).
--
-- EVERYTHING READ BACK IS STALE. dlac was not watching between the write and
-- this read -- a relog, a client restart, an `/addon reload`, a profile switch
-- all look identical from here, and every one of them is a break in observation.
-- The COUNT survives (that is the point of persisting it); what does not survive
-- is the right to render a percentage off it.
function M.load()
    local p = M.path();
    if p == nil then return M.state; end          -- pre-login: retry next beat
    if M._loadedFrom == p then return M.state; end
    M._loadedFrom = p;
    local disk = {};
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then disk = M._fromRaw(t); end
    end);
    local now = 0;
    pcall(function() now = M.reads.now() or 0; end);
    disk = M.reduce(disk, { kind = 'relog', at = now }, {});
    -- Anything already in memory was witnessed by THIS session and outranks the
    -- file: the path is unreadable for the first moments after login, and a kill
    -- landing in that window must not be thrown away by the first successful
    -- read. It also keeps its freshness -- the relog above marked what came off
    -- disk, not what we watched happen.
    for k, rec in pairs(M.state) do disk[k] = rec; end
    M.state = disk;
    return M.state;
end

-- The house write ladder: temp -> parse -> atomic swap, with a plain write as
-- the last resort so a count is never lost to a missing library.
function M.save()
    local p = M.path();
    if p == nil then return false; end
    local text = M._serialize(M.state);
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
-- what the command asks
-- ---------------------------------------------------------------------------

-- The record for one camp, or nil. Loads on first ask.
function M.record(zid, entry)
    M.load();
    local key = M.campKey(zid, entry);
    if key == nil then return nil; end
    return M.state[key];
end

-- The tracking lines for one NM, ready to print.
function M.entryLines(entry, zid, now)
    now = tonumber(now);
    if now == nil then pcall(function() now = M.reads.now(); end); end
    return M.lines(M.record(zid, entry), entry, now or 0);
end

-- Drop one camp's count. The one manual door: a stale count is sticky by design
-- (nothing can re-vouch for a break), so without this a camp resumed after a
-- zone could never show a percentage again.
function M.forget(zid, entry)
    M.load();
    local key = M.campKey(zid, entry);
    if key == nil or M.state[key] == nil then return false; end
    local out = copyState(M.state);
    out[key] = nil;
    M.state = out;
    M.save();
    return true;
end

-- Every camp holding a count, newest first: "which camps am I part-way through?"
function M.countLines(now)
    M.load();
    now = tonumber(now);
    if now == nil then pcall(function() now = M.reads.now(); end); end
    now = now or 0;
    local data = {};
    pcall(function() data = M.reads.data() or {}; end);
    local out, keys = {}, ordered(M.state);
    if #keys == 0 then
        out[#out + 1] = 'no NM counts yet -- placeholder kills count themselves while you camp.';
        -- ...and if they are NOT counting themselves, this is the line that says
        -- where the chain broke, instead of leaving "nothing happened" and "the
        -- death line is worded differently on this server" looking identical
        -- (hard rule 12). Both halves have to be seen for a kill to count.
        out[#out + 1] = string.format('  seen so far -- last engaged: %s; last death line: %s',
            M._seenTargetText(now), M._seenDeathText(now));
        return out;
    end
    out[#out + 1] = 'your NM counts -- only what you personally witnessed, so every one is a floor:';
    for _, k in ipairs(keys) do
        local rec   = M.state[k];
        local entry = M.campFor(data, rec);
        local st    = M.status(rec, entry, now);
        local where = tostring(rec.zone);
        if _nm ~= nil and type(_nm.zoneName) == 'function' then where = _nm.zoneName(rec.zone); end
        local tail;
        if st.stale then
            tail = string.format('%d kills, %s -- STALE (%s), no chance shown',
                st.kills, agoText(st.ago), M.WHY_TEXT[st.why] or 'observation broke');
        elseif st.roll == 'primed' then
            tail = string.format('%d kills -- you saw it alive %s, kills cannot roll',
                st.kills, agoText(st.sawAgo));
        elseif st.roll == 'cooldown' then
            tail = string.format('%d kills -- you saw it die %s, kills cannot roll yet',
                st.kills, agoText(st.sawAgo));
        elseif st.chance ~= nil and _nm ~= nil then
            tail = string.format('%d kills = %s %s, %s now',
                st.kills, roundsText(st.rounds), plural(st.rounds, 'round'),
                _nm.pctText(st.chance));
        else
            tail = string.format('%d kills = %s %s', st.kills,
                roundsText(st.rounds), plural(st.rounds, 'round'));
        end
        out[#out + 1] = string.format('  %-22s %-20s %s', rec.nm, where, tail);
    end
    out[#out + 1] = '  /dl nm <name> for one camp; /dl nm <name> reset clears its count.';
    return out;
end

-- ---------------------------------------------------------------------------
-- the live feed -- two observations in, events out
-- ---------------------------------------------------------------------------

local _ring   = {};    -- engaged targets, newest last: { index, name, at }
local _deaths = {};    -- names the death channel handed us: { name, at }
local _sights = {};    -- engage edges waiting to be attributed: { index, name, at }
local _zone   = nil;   -- the last zone we could read
local _next   = 0;     -- the pump throttle
-- The two halves, last seen. DIAGNOSTIC ONLY -- never read by the reducer, and
-- the reason they exist is that a kill needs BOTH, so "nothing counted" has two
-- very different causes and they must not look alike (hard rule 12).
local _sawTarget = nil;   -- { index, name, at }
local _sawDeath  = nil;   -- { name, at }

function M._seenTargetText(now)
    if _sawTarget == nil then return 'nothing yet'; end
    return string.format('"%s" index %d, %s', tostring(_sawTarget.name or '?'),
        math.floor(tonumber(_sawTarget.index) or 0),
        agoText((tonumber(now) or 0) - (tonumber(_sawTarget.at) or 0)));
end

function M._seenDeathText(now)
    if _sawDeath == nil then return 'nothing yet'; end
    return string.format('"%s", %s', tostring(_sawDeath.name or '?'),
        agoText((tonumber(now) or 0) - (tonumber(_sawDeath.at) or 0)));
end

-- Live reads, called (never captured) so the headless suite can drive the same
-- pump the game does.
M.reads = {
    now  = function() return os.time(); end,
    zone = function()
        if _loc ~= nil and type(_loc.zoneId) == 'function' then return _loc.zoneId(); end
        return nil;
    end,
    data = function()
        if _nm ~= nil and type(_nm.data) == 'table' then return _nm.data; end
        return {};
    end,
    save = function() return M.save(); end,
};

-- Drop the live feed's own working state (the engagewatch reset shape: job
-- change, logout, a test starting over). It touches NO counts -- `M.forget` is
-- the one thing that drops one of those.
function M.reset()
    _ring, _deaths, _sights, _zone, _next = {}, {}, {}, nil, 0;
    _sawTarget, _sawDeath = nil, nil;
end

-- An accepted engage/target edge: remember WHICH entity, because the death line
-- will not say. Also queued as a sighting -- engaging the NM itself is evidence
-- it popped.
function M.onEdge(edge, now)
    if type(edge) ~= 'table' then return nil; end
    local idx = tonumber(edge.index);
    if idx == nil or idx <= 0 then return nil; end
    if now == nil then pcall(function() now = M.reads.now(); end); end
    now = tonumber(now) or 0;
    local t = { index = idx, name = edge.name, at = now };
    if #_ring >= M.RING then table.remove(_ring, 1); end
    _ring[#_ring + 1] = t;
    if #_sights >= M.RING then table.remove(_sights, 1); end
    _sights[#_sights + 1] = t;
    _sawTarget = t;
    return t;
end

-- A rendered death line. Parsed and stashed; the correlation and the disk write
-- happen on the frame pump.
function M.onDeathLine(line, now)
    local name = M.deathName(line);
    if name == nil or name == '' then return nil; end
    if now == nil then pcall(function() now = M.reads.now(); end); end
    if #_deaths >= M.RING then table.remove(_deaths, 1); end
    local d = { name = name, at = tonumber(now) or 0 };
    _deaths[#_deaths + 1] = d;
    _sawDeath = d;
    return name;
end

-- The OLDEST engaged target carrying this name, CONSUMED. One engagement can
-- credit at most one kill, so a same-named mob dying elsewhere can never borrow
-- yours -- and if the ring has nobody, the caller falls back to a name-only
-- event, which only the NM branch of classify can answer.
--
-- OLDEST, NOT NEWEST, and this is not a detail: auto-target rolls onto the next
-- mob the moment the last one dies, so by the time the death line is rendered
-- the ring already holds BOTH -- the one that died and the one you are now
-- facing. Newest-first would credit the kill to the mob still standing, which at
-- a camp of ten same-named Buffalo means crediting a spawn point that never
-- died. Oldest-first is also simply the order things die in: you engage them one
-- after another and they fall in the same order.
function M._credit(name, now)
    local want = lower(name);
    if want == nil or want == '' then return nil; end
    now = tonumber(now) or 0;
    for i = 1, #_ring do
        local t = _ring[i];
        if lower(t.name) == want and (now - (tonumber(t.at) or 0)) <= M.TARGET_TTL_S then
            table.remove(_ring, i);
            return t;
        end
    end
    return nil;
end

local function pruneRing(now)
    for i = #_ring, 1, -1 do
        if (now - (tonumber(_ring[i].at) or 0)) > M.TARGET_TTL_S then table.remove(_ring, i); end
    end
end

-- One beat: attribute what was observed, age what was not. Returns true when the
-- state moved (which is also when it is written).
function M.pump(reads)
    reads = (type(reads) == 'table') and reads or M.reads;
    local busy = (#_deaths > 0) or (#_sights > 0);
    if not busy then
        local c = os.clock();
        if c < _next then return false; end
        _next = c + M.TICK_S;
    end

    local now = tonumber(reads.now());
    if now == nil then return false; end
    M.load();
    local zone = reads.zone();
    local ctx  = { data = reads.data(), zone = zone, now = now };
    local changed = false;

    -- 1. A zone change is a break in observation. Only a change between two
    -- KNOWN zones counts: the read goes nil during a load exactly as it does at
    -- character select, and a failed read is not an event.
    if zone ~= nil and _zone ~= nil and zone ~= _zone then
        local s, c = M.reduce(M.state, { kind = 'zone', at = now }, ctx);
        M.state, changed = s, changed or c;
    end
    if zone ~= nil then _zone = zone; end

    -- 2. Sightings first, deaths second -- an engage always precedes the kill it
    -- leads to, so this is chronological order.
    if #_sights > 0 then
        local q = _sights; _sights = {};
        for _, t in ipairs(q) do
            local s, c = M.reduce(M.state,
                { kind = 'sight', index = t.index, name = t.name, at = t.at }, ctx);
            M.state, changed = s, changed or c;
        end
    end

    -- 3. Deaths, joined to the index of the thing you were fighting.
    if #_deaths > 0 then
        local q = _deaths; _deaths = {};
        for _, d in ipairs(q) do
            local t = M._credit(d.name, d.at);
            local ev;
            if t ~= nil then
                ev = { kind = 'kill', index = t.index, name = t.name, at = d.at };
            else
                -- Nothing you engaged: the name alone can still answer for the
                -- NM ITSELF, which is evidence of a pop and can only reset.
                ev = { kind = 'kill', index = nil, name = d.name, at = d.at };
            end
            local s, c = M.reduce(M.state, ev, ctx);
            M.state, changed = s, changed or c;
        end
    end

    -- 4. Age.
    local s, c = M.reduce(M.state, { kind = 'tick', at = now }, ctx);
    M.state, changed = s, changed or c;

    pruneRing(now);
    if changed then reads.save(); end
    return changed;
end

-- ---------------------------------------------------------------------------
-- Ashita glue, guarded (headless: nothing registers, the pure halves ARE the
-- module -- the engagewatch/chocowatch shape)
-- ---------------------------------------------------------------------------

pcall(function()
    -- The engage/target edge service (issue #139) is the ONE place the index of
    -- what you attacked is decoded; this subscribes rather than opening a second
    -- packet handler. Its own pump runs earlier in the same frame.
    local ew = require('dlac\\feature\\engagewatch');
    if type(ew) == 'table' and type(ew.subscribe) == 'function' then
        ew.subscribe('dlac-nmtrack', function(edge) M.onEdge(edge); end);
    end
end);

pcall(function()
    -- The death channel. Main thread, one substring test, no disk: the
    -- correlation and the file write are the pump's.
    ashita.events.register('text_in', 'dlac-nmtrack-death', function(e)
        pcall(function() M.onDeathLine(e.message); end);
    end);
end);

pcall(function()
    ashita.events.register('d3d_present', 'dlac-nmtrack-tick', function()
        pcall(M.pump);
    end);
end);

return M;
