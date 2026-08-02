--[[
    dlac/sendlog.lua -- /dl sends: WHAT DID DLAC PUT ON THE WIRE.

    The question that begat it (Henrik, 2026-08-01, mid-Incursion): "does it
    send constant packets to have things equipped or only once?" The code
    answer is "only on a real difference" -- bufferFlush bails at
    plan.satisfied, so a steady state sends nothing -- but a code answer is a
    claim, and the whole point of the debug\ file rule is that a claim you can
    read off disk beats a claim you have to trust.

    THIS IS A SELF-CHECK, NOT A PROBE (Henrik's 07-23 ruling, the same line
    that put /dl check in dlac and left packet forensics in dlacprobe). It
    counts dlac's OWN sends at the sites that make them. A dlacprobe
    packet_out observer would see anonymous injected bytes and could not tell
    ours from another addon's, let alone name the dispatch point that caused
    them -- only the send site knows WHY it sent, and the why is the entire
    diagnostic value. Nothing here reads the wire, hexdumps, or captures.

    THE INVARIANT: every AddOutgoingPacket call in the shipped tree is
    accompanied by a sendlog.note(). Five chokepoints carry all of them --
    equipengine's injectPacket (0x050/0x051 equips + 0x01A/0x037 re-injects),
    lockstyleapply's liveInject (0x053), craftwatch's guild-point poll
    (0x10F), eboxclient's sendRaw (0x1A4) and helmwatch's points poll
    (0x1A4). Test SND9 pins it as SOURCE: a new send site added without a
    note fails the suite rather than silently going uncounted, which is the
    one way this readout could ever lie.

    What a healthy Incursion run looks like (the shape the question wanted):
    a burst at the sync landing, then flat. What a FLAP looks like: the same
    cause repeating at the 0.4s Default tick, forever -- which the by-cause
    tally and the ring's timestamps show at a glance.
]]--

local M = {};

-- Last N sends kept with their cause. Small on purpose: the counters carry
-- the volume answer, the ring only has to show the SHAPE of recent traffic
-- (is it one burst, or is it every 0.4s?).
M.RING = 24;

-- ---------------------------------------------------------------------------
-- pure core (headless-tested, SND*)
-- ---------------------------------------------------------------------------

function M.newState(now)
    return { total = 0, passed = 0, byId = {}, passedById = {}, byWhy = {},
             ring = {}, ringN = 0, since = tonumber(now) or 0, lastAt = nil };
end

-- Record one send. `id` is the packet id, `why` the cause the SEND SITE knows
-- (a dispatch point, 'lockstyle apply'...). Pure: mutates and keeps `st`.
-- Unknown/absent arguments still count -- an uncounted send is the only real
-- failure mode here, so nothing is ever dropped for being malformed.
--
-- `pass` marks a PASS-THROUGH: a packet that is YOURS, which dlac blocked,
-- held while it dressed you, and put back on the wire byte-identical (the
-- 0x01A/0x037 re-injects). It is counted -- every AddOutgoingPacket is, that
-- is the invariant -- but it is not traffic dlac ADDED, and lumping it into
-- one total made the headline read higher than dlac's real contribution
-- (Henrik, 2026-08-02, reading the first version). The flag lives in the
-- DATA, not in the wording of `why`: the render seam decides how to say it.
function M._note(st, id, why, now, pass)
    if type(st) ~= 'table' then return; end
    id  = tonumber(id) or -1;
    why = (type(why) == 'string' and why ~= '') and why or 'unknown';
    now = tonumber(now) or 0;
    pass = (pass == true);
    st.total = (st.total or 0) + 1;
    st.byId[id]   = (st.byId[id] or 0) + 1;
    st.byWhy[why] = (st.byWhy[why] or 0) + 1;
    if pass then
        st.passed = (st.passed or 0) + 1;
        st.passedById[id] = (st.passedById[id] or 0) + 1;
    end
    st.lastAt = now;
    local n = (st.ringN or 0) + 1;
    st.ringN = n;
    st.ring[((n - 1) % M.RING) + 1] = { at = now, id = id, why = why, pass = pass };
end

-- What dlac itself put on the wire: everything that is not a pass-through.
function M._own(st)
    return math.max(0, (st.total or 0) - (st.passed or 0));
end

-- The ring newest-first (at most RING entries, oldest dropped by the wrap).
function M._recent(st)
    local out = {};
    if type(st) ~= 'table' or type(st.ring) ~= 'table' then return out; end
    local n = st.ringN or 0;
    local count = (n < M.RING) and n or M.RING;
    for i = 0, count - 1 do
        out[#out + 1] = st.ring[(((n - 1 - i) % M.RING) + M.RING) % M.RING + 1];
    end
    return out;
end

-- Seconds -> '14m22s' / '8s' / '2h03m'. Field-readable, not precise.
function M._dur(s)
    s = math.floor(tonumber(s) or 0);
    if s < 0 then s = 0; end
    if s < 60 then return string.format('%ds', s); end
    if s < 3600 then return string.format('%dm%02ds', math.floor(s / 60), s % 60); end
    return string.format('%dh%02dm', math.floor(s / 3600), math.floor((s % 3600) / 60));
end

-- Descending count, name-tiebroken (a stable order: the same session prints
-- the same way twice, so two reports can be diffed). `passMap` optionally
-- annotates how much of each row was passed through -- silent when none was,
-- because most rows never are.
local function ranked(map, fmtKey, passMap)
    local rows = {};
    for k, v in pairs(map or {}) do rows[#rows + 1] = { k = k, n = v }; end
    table.sort(rows, function(a, b)
        if a.n ~= b.n then return a.n > b.n; end
        return fmtKey(a.k) < fmtKey(b.k);
    end);
    local parts = {};
    for _, r in ipairs(rows) do
        local p = (passMap ~= nil) and (passMap[r.k] or 0) or 0;
        local tag = '';
        if p >= r.n then tag = ' (passed through)';
        elseif p > 0 then tag = string.format(' (%d passed through)', p); end
        parts[#parts + 1] = string.format('%s x%d%s', fmtKey(r.k), r.n, tag);
    end
    return parts;
end

local function idName(id)
    id = tonumber(id) or -1;
    if id < 0 then return '(unknown)'; end
    return string.format('0x%03X', id);
end

-- st -> the readout lines (no '[dlac] ' prefix -- the caller adds it).
-- `ringMax` caps the recent-sends tail: chat passes a small number (a flap
-- would otherwise scroll the counters -- the part you came for -- off the
-- top), the FILE passes nil and gets the whole ring. Chat is a summary, the
-- artifact is the record.
function M._lines(st, now, ringMax)
    st = st or M.newState(0);
    now = tonumber(now) or 0;
    local elapsed = now - (tonumber(st.since) or 0);
    local L = {};
    local total = st.total or 0;

    if total == 0 then
        L[#L + 1] = string.format(
            'sends: NOTHING sent in %s -- dlac has put zero packets on the wire this session.',
            M._dur(elapsed));
        L[#L + 1] = 'sends: this is the expected steady state -- equips are edge-driven'
                 .. ' (the Default tick resolves a plan every 0.4s but sends only when a slot'
                 .. ' actually differs).';
        return L;
    end

    -- THE HEADLINE, split (Henrik, 2026-08-02). The rate is quoted on dlac's
    -- OWN sends, never the total: a busy caster would otherwise read as a
    -- chatty addon, when the only thing that grew was how much you acted.
    local own, passed = M._own(st), (st.passed or 0);
    local perMin = (elapsed > 1) and (own / (elapsed / 60)) or 0;
    local lastWord = (st.lastAt ~= nil) and M._dur(now - st.lastAt) or '?';
    if passed > 0 then
        L[#L + 1] = string.format(
            'sends: %d from dlac (%.1f/min) + %d of your own actions passed through = %d in %s'
            .. ' -- last one %s ago.',
            own, perMin, passed, total, M._dur(elapsed), lastWord);
    else
        L[#L + 1] = string.format('sends: %d from dlac (%.1f/min) in %s -- last one %s ago.',
            own, perMin, M._dur(elapsed), lastWord);
    end
    -- dlac added NOTHING and only your own actions went by: the same answer
    -- the zero case gives, and the shape a real session actually takes.
    if own == 0 then
        L[#L + 1] = 'sends: dlac itself sent NOTHING -- equips are edge-driven (the Default tick'
                 .. ' resolves a plan every 0.4s but sends only when a slot actually differs);'
                 .. ' a pass-through is your own packet, blocked while dlac dressed you and put'
                 .. ' back on the wire byte-identical.';
    end
    L[#L + 1] = 'sends: by packet -- ' .. table.concat(ranked(st.byId, idName, st.passedById), ', ');
    L[#L + 1] = 'sends: by cause -- ' .. table.concat(ranked(st.byWhy, tostring), ', ');

    local recent = M._recent(st);
    local shown = #recent;
    local cap = tonumber(ringMax);
    if cap ~= nil and cap < shown then shown = cap; end
    if shown > 0 then
        L[#L + 1] = string.format('sends: last %d (newest first, age at report time)%s:',
            shown,
            (shown < #recent) and string.format(' -- %d more in the report file', #recent - shown) or '');
        for i = 1, shown do
            local r = recent[i];
            L[#L + 1] = string.format('    -%-7s %s  %s',
                M._dur(now - (r.at or 0)), idName(r.id), tostring(r.why));
        end
    end
    return L;
end

-- ---------------------------------------------------------------------------
-- live state + the note() hot path
-- ---------------------------------------------------------------------------

local function clock()
    local t = 0;
    pcall(function() t = os.clock(); end);
    return t;
end

M.state = M.newState(clock());

-- An OPTIONAL second reader of the same notes (2026-08-03): /dl report's
-- recorder sets this while a capture is running, so the support log carries
-- every send WITH ITS CAUSE. It hangs off M.note rather than M._note because
-- the pure core is the tested one and must stay side-effect free; and it is
-- pcall'd for the same reason the counter is -- an observer must not be able
-- to break the thing it observes, still less the equip that caused the send.
M.observer = nil;

-- THE call every send site makes. Never throws (a counter must not be able to
-- break the thing it counts) and does no io -- a send is rare, but under a
-- flap this runs at the 0.4s tick, so it stays arithmetic.
-- `pass` = this is YOUR packet passing back through, not traffic dlac added.
function M.note(id, why, pass)
    local ok = pcall(M._note, M.state, id, why, clock(), pass);
    if M.observer ~= nil then pcall(M.observer, id, why, pass); end
    return ok;
end

function M.reset()
    M.state = M.newState(clock());
end

-- ---------------------------------------------------------------------------
-- the command
-- ---------------------------------------------------------------------------

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- How many recent sends the CHAT readout shows. The file gets all of them.
M.CHAT_RING = 8;

function M.report()
    local now = clock();
    for _, l in ipairs(M._lines(M.state, now, M.CHAT_RING)) do print('[dlac] ' .. l); end
    -- The file rule (Henrik 07-23): a debug run lands as ONE transferable
    -- .txt. No engine half to merge -- the purge left one state, and every
    -- send site lives in it, so deliver is called with no handoff name (which
    -- is why debug.lua grew NO_ENGINE_HALF: an absent half it never expected
    -- must not be reported as the diagnosis).
    local dbg = try('dlac\\feature\\debug');
    if dbg ~= nil and type(dbg.deliver) == 'function' then
        pcall(dbg.deliver, 'sends', 'dlac-sends', M._lines(M.state, now, nil), nil, { delay = 1.2 });
    end
end

-- raw (lowercased) -> the argument word ('' for a bare /dl sends), or nil
-- when the command is not ours. The bare and argument forms are matched
-- SEPARATELY on purpose: one combined `sends%s*(.-)` pattern also swallows
-- `/dl sendsfoo`, and a command that eats its neighbours is worse than one
-- that misses.
function M._parse(raw)
    raw = tostring(raw or '');
    if raw:match('^/dl%s+sends%s*$') ~= nil or raw:match('^/dlac%s+sends%s*$') ~= nil then
        return '';
    end
    return raw:match('^/dl%s+sends%s+(.-)%s*$') or raw:match('^/dlac%s+sends%s+(.-)%s*$');
end

ashita.events.register('command', 'dlac-sends', function(e)
    local sub = M._parse(string.lower(e.command));
    if sub == nil then return; end
    e.blocked = true;
    if sub == 'reset' then
        M.reset();
        print('[dlac] sends: counters reset -- the clock starts now.');
        return;
    end
    if sub ~= '' then
        print('[dlac] usage: /dl sends [reset]   what dlac has put on the wire this session');
        return;
    end
    M.report();
end);

return M;
