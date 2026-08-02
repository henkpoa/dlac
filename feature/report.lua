--[[
    dlac/feature/report.lua -- /dl report: THE SUPPORT REPORT.

    Henrik, 2026-08-02: "once the user base grows, I want people to enable the
    debug, where we get as much information as possible generated into a log
    file... their whole dlac profile that is active + gear, sets, triggers,
    everything. Then a debug log for as long as it is active (max 5 minutes).
    Then he should send those files to me."

    ONE artifact, because a player who has to attach eight files attaches
    three. The recorder streams a live log to disk while it runs and the
    bundler folds that log, the config, the health readout and a gear digest
    into a single sendable .txt when it stops.

    FIVE DESIGN CALLS, each with a field reason:

    1. PRE-ROLL. Nobody starts recording BEFORE the bug -- they start after
       they saw it. dispatch already keeps 50 decisions and 32 actions in
       memory, and sendlog keeps 24 sends, all of them always-on. So the first
       thing a capture writes is those rings, marked PRE-ROLL. Free: no new
       standing cost, and "I hit record right after it happened" still lands
       the event.

    2. STREAM, DON'T BUFFER. feature/debug.lua's own header records the way
       this goes wrong: '/dl debug ebox' threw and Ashita unloaded dlac
       mid-session. If the thing being chased is a crash, a write-at-the-end
       design loses exactly the run that mattered. Every batch is appended to
       <debug>\dlac-capture-<Char>.log as it happens; a dead client still
       leaves that file behind.

    3. SCOPED FOR THE READER. The bundle is fed to an LLM, so its budget is
       CONTEXT, not disk. A real character's gear.lua is 264 KB of bag index
       (~70k tokens) and almost none of it bears on any given bug -- so gear
       ships as a DIGEST of the items actually named by the window, with live
       "is it in an equippable bag" beside each. The active job's sets and
       triggers ship verbatim (~44 KB). Everything else is listed in a
       MANIFEST with its size, so a wrongly-scoped digest costs one follow-up
       ("send me profiles\Default\sets\BLU.lua") instead of a lost session.
       '/dl report full' ships the whole profile tree and raw gear.lua for the
       cross-job cases. Nothing is ever dropped silently: every exclusion is a
       named line in the report.

    4. THE MARK. In a five-minute log the expensive step is finding the
       moment. '/dl mark <note>' goes on a macro palette and works mid-fight;
       the Arbiter Monitor's [Mark] button is the alt-tab version. Marks land
       in the timeline AND in a list at the top.

    5. OVERWRITE, per the file rule (debug.lua, 07-23): support wants THE
       latest, not an archive, and a player who ran it twice meant the second
       one. The header carries started/ended stamps so the run is never
       ambiguous.

    PRIVACY: the file carries character name + server id, inventory-derived
    gear facts and dlac settings. The only chat it captures is dlac's OWN
    '[dlac] ' output (text_in, prefix-filtered) -- never tells, never party
    chat. Stated in the UI and again at the top of the file. Visibility, not a
    gate (docs/adr: no protective gating).

    RENDERER, NOT DERIVER (the integration-surface ruling): every decision
    block here renders the stashed record -- contest, ladders, ctx were all
    captured at decision time. It is the FOURTH renderer of that one record,
    beside /dl why, the Arbiter Monitor and the stream, and it says the same
    things in the same words on purpose.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- ---------------------------------------------------------------------------
-- limits
-- ---------------------------------------------------------------------------

M.MIN_S = 60;            -- a shorter window than this catches nothing useful
M.MAX_S = 300;           -- Henrik's ceiling: five minutes
M.DEF_S = 300;

-- Context budget, not a disk budget (call 3). Scoped runs land ~100 KB; the
-- cap is the backstop for a character with an unusual profile.
M.BUDGET      = 768 * 1024;
M.BUDGET_FULL = 4 * 1024 * 1024;
-- Per-file ceiling for the opportunistic state files. The ACTIVE JOB's own
-- sets/triggers/lockstyles bypass it -- they are the point of the bundle, and
-- a 38 KB BLU.lua must never be the file that got skipped.
M.PERFILE     = 32 * 1024;

M.CHAT_CAP = 400;        -- captured [dlac] lines
M.MARK_CAP = 40;

-- Files in the character data home that are CODE (seeded engine copies and
-- legacy leftovers), not settings. Never bundled -- they are the addon tree,
-- which support already has, and they are enormous.
M.CODE_FILES = {
    ['dispatch.lua'] = true, ['utils.lua'] = true, ['profiles.lua'] = true,
    ['chatfmt.lua'] = true, ['gcinclude.lua'] = true, ['gcdisplay.lua'] = true,
    ['autogear.lua'] = true, ['gear.lua'] = true,
};

-- ---------------------------------------------------------------------------
-- pure seams (headless-tested, RPT*)
-- ---------------------------------------------------------------------------

-- Window length: clamped MIN..MAX, default DEF. Same shape as debug._dur, and
-- deliberately NOT the same numbers -- that one is a lockstyle capture.
function M._dur(word)
    local n = tonumber(word);
    if n == nil then return M.DEF_S; end
    return math.max(M.MIN_S, math.min(M.MAX_S, math.floor(n)));
end

-- raw (lowercased) -> the argument word ('' for a bare '/dl report'), or nil
-- when the command is not ours. Bare and argument forms matched SEPARATELY:
-- one combined pattern also swallows '/dl reportfoo', and a command that eats
-- its neighbours is worse than one that misses (sendlog._parse's law).
function M._parse(raw)
    raw = tostring(raw or '');
    if raw:match('^/dl%s+report%s*$') ~= nil or raw:match('^/dlac%s+report%s*$') ~= nil then
        return '';
    end
    return raw:match('^/dl%s+report%s+(.-)%s*$') or raw:match('^/dlac%s+report%s+(.-)%s*$');
end

-- '/dl mark <note>' -> the note ('' when bare), nil when not our command.
-- Case is PRESERVED: the note is the player's own words and goes in the file
-- as typed, so this takes the raw command, not the lowered one.
function M._markParse(raw)
    raw = tostring(raw or '');
    if raw:match('^/[Dd][Ll]%s+[Mm][Aa][Rr][Kk]%s*$') ~= nil
        or raw:match('^/[Dd][Ll][Aa][Cc]%s+[Mm][Aa][Rr][Kk]%s*$') ~= nil then
        return '';
    end
    return raw:match('^/[Dd][Ll]%s+[Mm][Aa][Rr][Kk]%s+(.-)%s*$')
        or raw:match('^/[Dd][Ll][Aa][Cc]%s+[Mm][Aa][Rr][Kk]%s+(.-)%s*$');
end

-- Filenames carry the character (support juggles several players' files);
-- debug._safeName's twin, kept local so this module stands alone headless.
function M._safeName(n)
    n = tostring(n or ''):gsub('%W', '');
    return (n ~= '') and n or 'unknown';
end

-- Seconds -> '4m10s' / '38s'. Report-readable, not precise.
function M._clock(s)
    s = math.floor(tonumber(s) or 0);
    if s < 0 then s = 0; end
    return string.format('%d:%02d', math.floor(s / 60), s % 60);
end

-- Strip a chat line to printable text (the petvitals/helmwatch cleanLine
-- idiom -- text_in carries the client's colour bytes inline).
function M._clean(msg)
    local s = tostring(msg or ''):gsub('[^\032-\126]+', ' ');
    return (s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''));
end

-- Is this chat line dlac's own output? The capture filter, and the whole of
-- the privacy promise: everything else the player sees stays unread.
function M._isOurs(line)
    return string.sub(tostring(line or ''), 1, 7) == '[dlac] ';
end

-- Case-insensitive slot lookup -- producers disagree on slot-key case, so
-- every record read goes through this (arbmonui's findCI, same law).
local function findCI(map, slotLower)
    if type(map) ~= 'table' then return nil; end
    for slot, v in pairs(map) do
        if string.lower(tostring(slot)) == slotLower then return v; end
    end
    return nil;
end
M._findCI = findCI;

-- The "decided under" line: the world at decision time, from the record's own
-- snapshot. Same bits as the Monitor's ctx line, one string.
function M._ctxLine(ctx)
    local c = ctx or {};
    local bits = {};
    if c.job ~= nil then
        local j = tostring(c.job) .. tostring(c.jobLevel or '');
        if c.sub ~= nil then j = j .. '/' .. tostring(c.sub) .. tostring(c.subLevel or ''); end
        bits[#bits + 1] = j;
    end
    if c.status ~= nil then
        bits[#bits + 1] = tostring(c.status) .. ((c.moving == true) and ' (moving)' or '');
    end
    if c.hpp ~= nil then bits[#bits + 1] = 'HP ' .. tostring(c.hpp) .. '%'; end
    if c.mpp ~= nil then bits[#bits + 1] = 'MP ' .. tostring(c.mpp) .. '%'; end
    if c.tp ~= nil then bits[#bits + 1] = 'TP ' .. tostring(c.tp); end
    if c.day ~= nil or c.weather ~= nil then
        bits[#bits + 1] = tostring(c.day or '?') .. ' day / ' .. tostring(c.weather or 'clear');
    end
    if c.moon ~= nil then bits[#bits + 1] = 'moon ' .. tostring(c.moon); end
    if c.pet ~= nil then
        bits[#bits + 1] = 'pet ' .. tostring(c.pet) .. ' (' .. tostring(c.petStatus) .. ')';
    end
    if type(c.modes) == 'table' and #c.modes > 0 then
        bits[#bits + 1] = 'modes: ' .. table.concat(c.modes, ', ');
    end
    if #bits == 0 then return nil; end
    return table.concat(bits, '  ');
end

-- The job + level a record was decided under, remembered on the capture so the
-- digest can flag gear above it. Taken from the RECORD rather than read live:
-- the question is what your level was while the thing went wrong, and a level
-- sync that lapsed before the report was written must not rewrite the answer.
function M._noteLevel(st, rec)
    local c = (type(rec) == 'table') and rec.ctx or nil;
    if type(c) ~= 'table' then return; end
    if c.job ~= nil then st.job = tostring(c.job); end
    if tonumber(c.jobLevel) ~= nil then st.level = tonumber(c.jobLevel); end
end

-- Every item NAME a decision record mentions -- the plan, the ladders it
-- walked, and every claimant's offer. This is the digest's scope: precisely
-- the items whose gear facts can explain what the record did.
function M._itemNames(rec, into)
    local out = into or {};
    if type(rec) ~= 'table' then return out; end
    local function add(v)
        if type(v) == 'string' and v ~= '' and v ~= 'remove' and v ~= 'ignore'
           and string.sub(v, 1, 1) ~= '(' then
            out[v] = true;
        end
    end
    for _, v in pairs(rec.plan or {}) do add(v); end
    for _, lad in pairs(rec.ladders or {}) do
        for _, n in ipairs((type(lad) == 'table' and lad.items) or {}) do add(n); end
    end
    local con = rec.contest;
    if type(con) == 'table' then
        for _, ops in pairs(con.explain or {}) do
            for _, op in ipairs(ops) do add(op.item); end
        end
        for _, v in pairs(con.rep or {}) do
            if type(v) == 'table' then add(v.from); add(v.to); end
        end
    end
    return out;
end

-- THE DROPPED SLOT (field, 2026-08-02). The ring counts a slot as CHANGED
-- when it was in the previous plan and is absent from this one -- so a
-- weaponskill whose set placed nothing produced seven rows reading "(kept)"
-- under a header saying seven slots changed, which is two statements that
-- cannot both be true. `(kept)` is the Monitor's word for "nobody claimed it",
-- and in a 4x4 grid showing all sixteen slots it reads fine; here, where only
-- the changed slots print, it was actively misleading. A slot that is changed,
-- has no plan entry and has no winner was not kept by consensus -- this
-- decision simply put nothing in it.
function M._isDropped(rec, slot)
    if type(rec) ~= 'table' then return false; end
    local ls = string.lower(tostring(slot));
    if findCI(rec.changed, ls) ~= true then return false; end
    if findCI(rec.plan, ls) ~= nil then return false; end
    local con = rec.contest;
    local ops = (type(con) == 'table') and findCI(con.explain, ls) or nil;
    return (ops == nil or ops[1] == nil);
end

-- One slot's story, as the report tells it. THE SAME VOCABULARY as the
-- Monitor's hover and /dl why -- "fell", "reserves", "not in a bag you can
-- equip from" -- because a player quoting one and support reading the other
-- must be looking at the same sentence. `label` maps a claimant identity to
-- its player-facing name (arbiter.claimantLabel); absent, the identity shows.
function M._slotLines(rec, slot, label, prev)
    label = label or tostring;
    local ls = string.lower(slot);
    local con = rec.contest;
    local ops = (type(con) == 'table') and findCI(con.explain, ls) or nil;
    local item = findCI(rec.plan, ls);
    local win = (ops ~= nil) and ops[1] or nil;
    local out = {};

    -- A CLAIMANT'S OFFER IS NOT A PLANNED ITEM (field, 2026-08-02). When the
    -- plan did not name the slot, the row used to print the winner's item --
    -- formatted identically to a piece that actually went on. That single
    -- ambiguity is why two separate oddities were undiagnosable from the
    -- artifact: a level-sync weapon hold removes Main from the plan while
    -- Triggers still claims it, and the row said "Main  Bronze Spear +1 <-
    -- Triggers" exactly as if it had been equipped. Sentinels ('(free equip)')
    -- keep reading as themselves -- they are not gear and never were.
    local dropped = M._isDropped(rec, slot);
    local offered = false;
    local shown = '(kept)';
    if item ~= nil and item ~= 'remove' then shown = tostring(item);
    elseif item == 'remove' then shown = '(removed)';
    elseif win ~= nil and string.sub(tostring(win.item), 1, 1) == '(' then
        shown = tostring(win.item);
    elseif win ~= nil then shown = '(not placed)'; offered = true;
    elseif dropped then shown = '(left as worn)'; end

    local head = string.format('    %-7s %-30s', slot, shown);
    if win ~= nil then
        head = head .. string.format(' <- %s (rank %s)', tostring(label(win.name)), tostring(win.rank or 0));
    elseif item ~= nil and item ~= 'remove' then
        -- AN ITEM WITH NO OWNER (field, 2026-08-02). The plan carries the
        -- piece and contest.explain has nobody for the slot -- so the two
        -- halves of one record disagree about who decided it, which is the
        -- invariant ADR 0027 exists to hold. Rendered bare it was
        -- indistinguishable from an ordinary row, and it is not ordinary:
        -- Ear1 landed Optical Earring this way on a level-up and only
        -- acquired its claimant two dispatches later.
        head = head .. ' <- NO CLAIMANT RECORDED (the plan has it, the contest names nobody)';
    end
    out[#out + 1] = (head:gsub('%s+$', ''));

    if offered then
        out[#out + 1] = string.format('            %s claimed this slot with %s, but the plan did not carry'
            .. ' it -- a hold (lock, or the level-sync weapon hold) keeps the slot as worn.',
            tostring(label(win.name)), tostring(win.item));
    end

    -- WHAT IT CHANGED FROM. The core question of a decision log, and the
    -- report could not answer it: a changed slot showed only its new item, so
    -- a record claiming a slot changed to the piece it already had read
    -- exactly like a real change. Only for slots the record CALLS changed --
    -- everything else did not, and saying "was:" there would invent an event.
    if type(prev) == 'table' and findCI(rec.changed, ls) == true then
        local was = findCI(prev.plan, ls);
        if was == item then
            out[#out + 1] = string.format('            was: %s -- SAME ITEM, yet the record lists this'
                .. ' slot as changed.', tostring(was or '(nothing)'));
        else
            out[#out + 1] = '            was: ' .. tostring(was or '(nothing worn from a set)');
        end
    end

    -- the losers, so "why did MY claim not win" is answerable
    if ops ~= nil and #ops > 1 then
        local rest = {};
        for i = 2, #ops do
            rest[#rest + 1] = string.format('%s:%s', tostring(label(ops[i].name)), tostring(ops[i].item));
        end
        out[#out + 1] = '            also asked: ' .. table.concat(rest, ', ');
    end

    if type(con) ~= 'table' then return out; end

    local rv = findCI(con.rep, ls);
    local iv = findCI(con.inel, ls);
    local sv = findCI(con.sup, ls);
    local fall = con.fall;
    local dv = (type(fall) == 'table') and findCI(fall.dead, ls) or nil;
    if rv ~= nil then
        if rv.why == 'unavail' then
            out[#out + 1] = string.format('            fell: %s -> %s (%s is not in a bag you can equip from)',
                tostring(rv.from), tostring(rv.to), tostring(rv.from));
        else
            out[#out + 1] = string.format('            fell: %s -> %s (it reserves %s -- owned above)',
                tostring(rv.from), tostring(rv.to), tostring(rv.by));
        end
    elseif dv ~= nil then
        out[#out + 1] = string.format('            UNAVAILABLE: %s is not in a bag you can equip from,'
            .. ' and nothing below it on the ladder is either -- kept as worn.', tostring(dv));
    elseif iv ~= nil then
        out[#out + 1] = string.format('            INELIGIBLE: it reserves %s, which a higher claim owns.', tostring(iv));
    elseif sv ~= nil then
        out[#out + 1] = string.format('            held EMPTY: reserved by %s (the server clears it).', tostring(sv));
    end

    local pv = con.pair;
    if pv ~= nil and string.lower(tostring(pv.slot)) == ls then
        if pv.remove == true then
            out[#out + 1] = string.format('            REMOVED: worn %s cannot sit beside %s -- the server'
                .. ' would strip the Range slot.', tostring(pv.loser), tostring(pv.keep));
        elseif pv.why == 'mismatch' then
            out[#out + 1] = string.format('            held EMPTY: %s cannot be fired by %s -- the ammo yields.',
                tostring(pv.loser), tostring(pv.keep));
        else
            out[#out + 1] = string.format('            held EMPTY: %s and %s cannot coexist, and %s is the'
                .. ' higher Level.', tostring(pv.loser), tostring(pv.keep), tostring(pv.keep));
        end
    end

    -- the whole ladder, each refused rung struck with its reason (the
    -- 2026-08-01 ruling: the survivor alone does not answer "why am I not
    -- wearing the piece I asked for")
    local whyOf = nil;
    local ref = (type(fall) == 'table') and findCI(fall.refused, ls) or nil;
    if type(ref) == 'table' then
        whyOf = {};
        for _, r in ipairs(ref) do whyOf[r.name] = r.why; end
    end
    local lad = findCI(rec.ladders, ls);
    if type(lad) == 'table' and type(lad.items) == 'table' and #lad.items > 0 then
        local names = {};
        for i, nm in ipairs(lad.items) do
            local w = whyOf ~= nil and whyOf[nm] or nil;
            local tag = '';
            if w == 'unavail' then tag = ' [x not in your bags]';
            elseif w == 'reserve' then tag = ' [x reserves a slot owned above]'; end
            names[#names + 1] = string.format('%d.%s%s', i, nm, tag);
        end
        out[#out + 1] = string.format('            ladder (%s): %s', tostring(lad.set),
            table.concat(names, '  '));
    end
    return out;
end

-- The game's own equip-screen order: two reports of the same bug diff cleanly.
M.SLOT_ORDER = { 'Main','Sub','Range','Ammo','Head','Neck','Ear1','Ear2',
                 'Body','Hands','Ring1','Ring2','Back','Waist','Legs','Feet' };

-- lowered slot -> the canonical spelling, so a shift line reads 'Main' whatever
-- case the producer used.
local CANON = {};
for _, s in ipairs(M.SLOT_ORDER) do CANON[string.lower(s)] = s; end

-- The winning claimant for one slot of one record, or nil.
local function winnerOf(rec, slotLower)
    local con = (type(rec) == 'table') and rec.contest or nil;
    local ops = (type(con) == 'table') and findCI(con.explain, slotLower) or nil;
    return (ops ~= nil and ops[1] ~= nil) and tostring(ops[1].name) or nil;
end

-- SLOTS THAT CHANGED HANDS while their item stayed put (field, 2026-08-02).
--
-- A record only lands on the ring when the FINGERPRINT moved, and the
-- fingerprint is items + winners. So a record with zero changed slots is one
-- where a WINNER moved -- and the block that printed nothing was hiding
-- exactly that. Six of 37 blocks in Henrik's full report were empty: a header,
-- a ctx line, and nothing, which teaches a reader to skim past records that by
-- definition are saying something happened.
--
-- Derived by comparing consecutive records rather than stored, because the ring
-- does not record it -- and consecutive is the only comparison that means
-- anything here: the ring appends on change, so record N-1 IS the state record
-- N moved away from.
function M._claimantShifts(prev, rec)
    -- NOTHING TO COMPARE AGAINST is not "everything changed hands". The first
    -- record of a capture has no predecessor, and treating every winner in it
    -- as a fresh shift printed a shift line for all sixteen slots on top of
    -- the rows that already said the same thing.
    if type(prev) ~= 'table' or type(prev.contest) ~= 'table' then return {}; end
    local slots, out = {}, {};
    for _, r in ipairs({ prev, rec or {} }) do
        local con = (type(r) == 'table') and r.contest or nil;
        for slot in pairs((type(con) == 'table') and con.explain or {}) do
            slots[string.lower(tostring(slot))] = true;
        end
    end
    local ordered = {};
    for s in pairs(slots) do ordered[#ordered + 1] = s; end
    table.sort(ordered);
    for _, ls in ipairs(ordered) do
        local a, b = winnerOf(prev, ls), winnerOf(rec, ls);
        if a ~= b then out[#out + 1] = { slot = ls, from = a, to = b }; end
    end
    return out;
end

-- One decision record -> its block. `slots` decides how much: 'changed' (the
-- default) prints only the slots that moved, 'all' prints the whole plan.
-- `prev` is the record before it on the ring, which is what makes a claimant
-- shift visible at all -- absent, the block degrades to the old behaviour
-- rather than lying.
function M._decLines(rec, label, slots, prev)
    if type(rec) ~= 'table' then return {}; end
    local out = {};
    -- How many of the changed slots were actually FILLED. The ring's own count
    -- includes slots that merely left the plan, so a decision that placed
    -- nothing still announces "7 slots changed" -- true by the ring's
    -- definition, and read by a human as "seven pieces moved". The breakdown
    -- appears only when they differ, so the ordinary line stays short.
    -- Counted through _isDropped, the SAME test the rows use, so the header's
    -- breakdown and the note can never disagree with what is printed below.
    local droppedN = 0;
    for slot in pairs(rec.changed or {}) do
        if M._isDropped(rec, slot) then droppedN = droppedN + 1; end
    end
    local n = rec.nChanged or 0;
    local placed = n - droppedN;
    local tail = string.format('(%d slot%s changed)', n, (n == 1) and '' or 's');
    if placed < n then
        tail = string.format('(%d slot%s changed -- %d placed, %d left as worn)',
            n, (n == 1) and '' or 's', placed, n - placed);
    end
    out[#out + 1] = string.format('[%s] #%s %s -- %s   %s',
        tostring(rec.time), tostring(rec.seq), tostring(rec.event),
        tostring(rec.action or ''), tail);
    local cl = M._ctxLine(rec.ctx);
    if cl ~= nil then out[#out + 1] = '      under: ' .. cl; end
    local buffs = (type(rec.ctx) == 'table') and rec.ctx.buffs or nil;
    if type(buffs) == 'table' and #buffs > 0 then
        out[#out + 1] = '      buffs: ' .. table.concat(buffs, ', ');
    end
    -- WHICH SETS PRODUCED THIS. contest.src is on every record already and the
    -- report was throwing it away -- it only ever surfaced inside a `ladder
    -- (Name):` line, so a decision that resolved no ladder never named the set
    -- it came from, which is precisely the decision you most want the set for.
    local srcs, nsrc = {}, 0;
    if type(rec.contest) == 'table' and type(rec.contest.src) == 'table' then
        for _, sn in pairs(rec.contest.src) do
            local s = tostring(sn);
            if not srcs[s] then srcs[s] = true; nsrc = nsrc + 1; end
        end
    end
    if nsrc > 0 then
        local names = {};
        for s in pairs(srcs) do names[#names + 1] = s; end
        table.sort(names);
        out[#out + 1] = '      sets: ' .. table.concat(names, ', ');
    end
    -- Said ONCE per block, not once per slot. The first cut repeated three
    -- lines of prose on every dropped slot: a seven-slot weaponskill spent
    -- twenty-one lines saying the same sentence, in a file whose whole
    -- premise is that it gets read start to finish. The engine filters a set
    -- entry at FLATTEN time -- before any ladder exists -- so a piece above
    -- your level leaves no refusal and no rung to strike through; naming both
    -- causes is the honest answer, and the digest's "sets ask for" list is
    -- where the reader confirms which one it was.
    if placed < n then
        out[#out + 1] = '      note: the (left as worn) slots below got nothing from this decision -- either';
        out[#out + 1] = '      its set does not name them, or nothing it names qualified (level, job, or you';
        out[#out + 1] = '      do not own it). What you had on stayed on. See the gear digest.';
    end
    local printed, rows = {}, 0;
    for _, slot in ipairs(M.SLOT_ORDER) do
        local ls = string.lower(slot);
        local touched = (slots == 'all')
            or (findCI(rec.changed, ls) == true)
            or (type(rec.contest) == 'table' and findCI(rec.contest.rep, ls) ~= nil)
            or (type(rec.contest) == 'table' and type(rec.contest.fall) == 'table'
                and findCI(rec.contest.fall.dead, ls) ~= nil);
        if touched then
            printed[ls] = true;
            for _, l in ipairs(M._slotLines(rec, slot, label, prev)) do out[#out + 1] = l; end
            rows = rows + 1;
        end
    end

    -- Slots whose OWNER moved while the item stayed -- the reason a
    -- zero-change record exists at all. Only those not already printed above:
    -- a slot whose item moved has its story told, and repeating it as a
    -- shift would double-count one event.
    for _, sh in ipairs(M._claimantShifts(prev, rec)) do
        if not printed[sh.slot] then
            local was, now = findCI(prev.plan, sh.slot), findCI(rec.plan, sh.slot);
            if was == now then
                out[#out + 1] = string.format('    %-7s %-30s claim moved: %s -> %s   (the item did not change)',
                    CANON[sh.slot] or sh.slot, tostring(now or '(kept)'),
                    (sh.from ~= nil) and tostring(label(sh.from)) or '(nobody)',
                    (sh.to ~= nil) and tostring(label(sh.to)) or '(nobody)');
            else
                -- The item moved too, and the record's own `changed` map did
                -- not say so. Never assert "the item did not change" without
                -- checking it -- the first cut did, and printed that sentence
                -- over a slot that had gone from nothing to Emperor Hairpin.
                -- Printed as the full slot story instead, and the disagreement
                -- is called out: a `changed` map that misses a real change is
                -- a finding about the ring, not a detail to smooth over.
                for _, l in ipairs(M._slotLines(rec, CANON[sh.slot] or sh.slot, label, prev)) do
                    out[#out + 1] = l;
                end
                out[#out + 1] = string.format('            claim moved: %s -> %s, and the item went %s -> %s',
                    (sh.from ~= nil) and tostring(label(sh.from)) or '(nobody)',
                    (sh.to ~= nil) and tostring(label(sh.to)) or '(nobody)',
                    tostring(was or '(nothing)'), tostring(now or '(nothing)'));
                out[#out + 1] = '            NOTE: the record did not list this slot as changed.';
            end
            rows = rows + 1;
        end
    end

    -- A DECISION BLOCK IS NEVER EMPTY. The ring appends only when the
    -- fingerprint moved, so a record that can show neither a changed slot nor
    -- a claimant shift is a record whose reason this renderer cannot see --
    -- and saying so is a finding, where printing a bare header taught the
    -- reader to skim.
    if rows == 0 then
        out[#out + 1] = '      recorded, but nothing here differs from the decision before it: no slot';
        out[#out + 1] = '      changed and no claimant changed hands. The ring appends only on a real';
        out[#out + 1] = '      difference, so this is worth reporting -- it should not be possible.';
    end
    return out;
end

-- The pass-through annotation on a send line, or ''. Suppressed when the send
-- site's own cause already says it: the field log read "SEND 0x01A  passed
-- through (your own action)  (your own packet, passed through)", the same fact
-- twice, which makes a reader look for the difference between them.
function M._passTag(why, pass)
    if pass ~= true then return ''; end
    if string.find(string.lower(tostring(why or '')), 'passed through', 1, true) ~= nil then
        return '';
    end
    return '  (your own packet, passed through)';
end

-- One action-feed stub -> one line. The anchor for "I did a thing and gear
-- did NOT move" -- the case with no decision to point at.
function M._actLine(stub)
    if type(stub) ~= 'table' then return nil; end
    local c = stub.ctx or {};
    local bits = {};
    if c.action ~= nil then bits[#bits + 1] = tostring(c.action); end
    if stub.decSeq ~= nil then bits[#bits + 1] = 'decision #' .. tostring(stub.decSeq);
    else bits[#bits + 1] = 'NO gear change'; end
    return string.format('[%s] action %s -- %s',
        os.date('%H:%M:%S', stub.at), tostring(stub.event), table.concat(bits, '  '));
end

-- Every item a SETS FILE references, resolved to display names.
--
-- The digest used to be scoped to what the window NAMED, and that has a blind
-- spot which cost a whole reading (field, 2026-08-02): gear that never reaches
-- a plan or a ladder leaves no trace -- and that is precisely the gear that
-- failed to qualify. A DRG26's whole Ws_Default was levels 33-75, so every
-- weaponskill silently wore TP gear, and nothing in the report could say so.
--
-- Set files reference gear as Lua paths (`gear.Head.JaridahKhud`), not names,
-- and the identifier is not the name (`gear.Head.Faceguard_1` is "Faceguard
-- +1"), so the reference is walked against the real gear table -- which is
-- exactly what the file itself does at load. Depth-agnostic: Main/Range nest
-- one level deeper by weapon category and need no special case. `gearTbl` is
-- injected, so this is pure.
function M._setItemNames(src, gearTbl, into)
    local out = into or {};
    if type(src) ~= 'string' or type(gearTbl) ~= 'table' then return out; end
    for ref in src:gmatch('gear%.[%w_%.]+') do
        local parts = {};
        for key in ref:gmatch('[%w_]+') do parts[#parts + 1] = key; end
        local node = gearTbl;
        for i = 2, #parts do                      -- parts[1] is the literal 'gear'
            if type(node) ~= 'table' then node = nil; break; end
            node = node[parts[i]];
        end
        if type(node) == 'table' and type(node.Name) == 'string' then out[node.Name] = true; end
    end
    return out;
end

-- The gear digest (call 3). `byName` is gear.lua's NameToObject; `haveFn`
-- answers "is it in a bag you can equip out of?" (dispatch's availability
-- read) and may be nil -- pre-login or headless, availability is simply not
-- claimed rather than guessed wrong. `level` is the job level OBSERVED during
-- the window: an entry above it is flagged, because that is the one refusal
-- the decision record can never carry (the filter runs at flatten time).
function M._digestLines(names, byName, haveFn, level)
    local sorted = {};
    for n in pairs(names or {}) do sorted[#sorted + 1] = n; end
    table.sort(sorted);
    local out, unknown = {}, {};
    for _, n in ipairs(sorted) do
        local rec = (type(byName) == 'table') and byName[n] or nil;
        if type(rec) ~= 'table' then
            unknown[#unknown + 1] = n;
        else
            local jobs = '?';
            if type(rec.Jobs) == 'table' then jobs = table.concat(rec.Jobs, ','); end
            local have = '';
            if haveFn ~= nil then
                local ok, v = pcall(haveFn, n);
                if ok and v == true then have = '  IN BAGS';
                elseif ok and v == false then have = '  NOT in an equippable bag';
                else have = '  (availability unknown)'; end
            end
            local extra = '';
            if rec.Augment ~= nil then extra = extra .. '  aug'; end
            if rec.RSlot ~= nil then extra = extra .. '  RSlot=' .. tostring(rec.RSlot); end
            -- THE FLATTEN-TIME REFUSAL, finally visible. Nothing in a decision
            -- record can say "this piece is above your level" -- the entry is
            -- gone before the contest starts -- so the digest says it instead.
            local lv, plv = tonumber(rec.Level), tonumber(level);
            if lv ~= nil and plv ~= nil and lv > plv then
                extra = extra .. string.format('  ABOVE YOUR LEVEL (%d)', plv);
            end
            out[#out + 1] = string.format('  %-32s id %-6s lv %-3s %s%s  jobs %s',
                n, tostring(rec.Id or '?'), tostring(rec.Level or '?'), have, extra, jobs);
        end
    end
    if #unknown > 0 then
        out[#out + 1] = '';
        out[#out + 1] = string.format('  %d name%s below is not in gear.lua at all -- it was asked for by a'
            .. ' set or a rule but never indexed (/dl scan -> /dl commit indexes your bags):',
            #unknown, (#unknown == 1) and '' or 's');
        for _, n in ipairs(unknown) do out[#out + 1] = '    ' .. n; end
    end
    if #out == 0 then out[#out + 1] = '  (no items were named during this window)'; end
    return out;
end

-- The budget walk (call 3, and the no-silent-caps law). `files` is an ordered
-- list of { path, label, size, always }; returns the ones that fit and the
-- ones that did not, each with a REASON that goes in the file.
function M._pick(files, budget, perFile)
    budget = tonumber(budget) or M.BUDGET;
    perFile = tonumber(perFile) or M.PERFILE;
    local taken, skipped, used = {}, {}, 0;
    for _, f in ipairs(files or {}) do
        local sz = tonumber(f.size) or 0;
        if not f.always and sz > perFile then
            skipped[#skipped + 1] = { label = f.label, size = sz,
                why = string.format('over the %d KB per-file cap', math.floor(perFile / 1024)) };
        elseif used + sz > budget then
            skipped[#skipped + 1] = { label = f.label, size = sz,
                why = string.format('the %d KB report budget was full', math.floor(budget / 1024)) };
        else
            used = used + sz;
            taken[#taken + 1] = f;
        end
    end
    return taken, skipped, used;
end

-- The manifest: everything that EXISTS, whether it was bundled or not, so a
-- wrongly-scoped digest costs one follow-up instead of a lost session.
function M._manifestLines(entries)
    local rows = {};
    for _, e in ipairs(entries or {}) do rows[#rows + 1] = e; end
    table.sort(rows, function(a, b) return tostring(a.label) < tostring(b.label); end);
    local out = {};
    for _, e in ipairs(rows) do
        out[#out + 1] = string.format('  %9s  %s%s', tostring(e.size or '?'), tostring(e.label),
            e.bundled and '   [bundled above]' or '');
    end
    if #out == 0 then out[#out + 1] = '  (the character data folder could not be listed)'; end
    return out;
end

-- The header block. Everything a reader needs before line 20: who, what
-- version, which window, which scope, and what is in the file.
function M._header(info)
    info = info or {};
    local bar = string.rep('=', 72);
    local out = {
        bar,
        string.format('dlac support report -- %s', tostring(info.char or 'unknown')),
        string.format('dlac %s   engine v%s   written %s',
            tostring(info.addonVer or '?'), tostring(info.engineVer or '?'),
            os.date('%Y-%m-%d %H:%M:%S', info.writtenAt)),
    };
    if info.startedAt ~= nil then
        out[#out + 1] = string.format('window %s -> %s  (%ds requested, %ds recorded)',
            os.date('%H:%M:%S', info.startedAt), os.date('%H:%M:%S', info.endedAt or info.startedAt),
            tonumber(info.requested) or 0, tonumber(info.recorded) or 0);
    end
    out[#out + 1] = string.format('scope: %s%s', info.full and 'FULL (whole profile tree + raw gear.lua)'
        or 'active job', (info.job ~= nil) and (' (' .. tostring(info.job) .. ')') or '');
    if info.stopReason ~= nil then
        out[#out + 1] = 'stopped: ' .. tostring(info.stopReason);
    end
    out[#out + 1] = string.rep('-', 72);
    out[#out + 1] = 'WHAT IS IN THIS FILE: your character name and server id, your dlac settings,';
    out[#out + 1] = 'gear sets and triggers, a digest of the gear involved, and a log of the';
    out[#out + 1] = 'decisions dlac made during the window. The only chat it contains is dlac\'s';
    out[#out + 1] = 'own [dlac] output -- no tells, no party chat, nothing anyone else said.';
    out[#out + 1] = 'Send it to the addon author. Nothing here is sent anywhere on its own.';
    out[#out + 1] = bar;
    return out;
end

-- The engine-liveness verdict, FOR THE FILE. `info` is check.gather()'s table:
-- fileV is the engine file this tree ships, stampV the version the engine
-- wrote into modestate the last time it loaded. Agreement proves an armed
-- engine of the right version far better than a chat line the report cannot
-- contain -- and disagreement names which side is behind, the same way
-- check._issues does.
function M._engineLines(info)
    info = info or {};
    local fv, sv = tonumber(info.fileV), tonumber(info.stampV);
    local out = { '' };
    out[#out + 1] = 'report note: the "[dlac] check (engine): alive" line named above is a CHAT-only';
    out[#out + 1] = 'line and can NEVER appear in this file -- do not read its absence as a dead';
    out[#out + 1] = 'engine. The file-based equivalent is the version pair:';
    if fv == nil or sv == nil then
        out[#out + 1] = string.format('  engine file v%s, modestate stamp %s -- INCONCLUSIVE.'
            .. ' A missing stamp means the engine has not loaded since this character last logged in.',
            tostring(info.fileV or '?'),
            (sv == nil) and 'NEVER WRITTEN' or ('v' .. tostring(info.stampV)));
    elseif fv == sv then
        out[#out + 1] = string.format('  engine file v%d, modestate stamp v%d -- AGREED, so the engine'
            .. ' is armed and current.', fv, sv);
    elseif sv < fv then
        out[#out + 1] = string.format('  engine file v%d, modestate stamp v%d -- the STAMP IS BEHIND:'
            .. ' the engine running is older than the tree on disk (/dl reload).', fv, sv);
    else
        out[#out + 1] = string.format('  engine file v%d, modestate stamp v%d -- the stamp is AHEAD:'
            .. ' this addon tree is stale (update dlac, then /addon reload dlac).', fv, sv);
    end
    return out;
end

-- The summary block: the window in numbers, then the marks. The first thing a
-- reader should look at, so it sits above the log.
--
-- The PRE-ROLL is counted APART from the window (2026-08-03). A summary that
-- said "0 decisions" over a log visibly containing one would make a reader
-- distrust the numbers -- and they would be right to: the pre-roll decisions
-- are real, they just happened before the button.
function M._summaryLines(st)
    st = st or {};
    local nm = #(st.marks or {});
    local function s(n) return (n == 1) and '' or 's'; end
    -- "0 actions" read as "you did nothing" over a log plainly containing a
    -- weaponskill (field, 2026-08-02). The counter only ever tallied the
    -- ANCHORS -- actions that moved no gear -- because an action that did move
    -- gear is already a decision block, and counting it twice would inflate
    -- the window. Correct by design, wrong by label; the label now says which.
    local out = {
        string.format('window %ds -- %d decision%s, %d send%s, %d dlac chat line%s, %d mark%s',
            tonumber(st.recorded) or 0, st.nDec or 0, s(st.nDec or 0),
            st.nSend or 0, s(st.nSend or 0), st.nChat or 0, s(st.nChat or 0), nm, s(nm)),
        string.format('%d action%s dispatched and moved NO gear (an action that moved gear is a'
            .. ' decision above, never counted twice).', st.nAct or 0, s(st.nAct or 0)),
    };
    if (st.nPre or 0) > 0 then
        out[#out + 1] = string.format('plus %d decision%s already in memory when recording started'
            .. ' -- the PRE-ROLL block at the top of the log.', st.nPre, s(st.nPre));
    end
    -- Spelled out rather than pluralized by rule: a support file that says
    -- "1 chat lines look" reads as a machine that is not paying attention,
    -- and this is the line most likely to be quoted back.
    if (st.nErr or 0) == 1 then
        out[#out + 1] = '1 of those chat lines looks like a FAILURE (failed/error/cannot) --'
            .. ' search the log for it first.';
    elseif (st.nErr or 0) > 1 then
        out[#out + 1] = string.format('%d of those chat lines look like FAILURES (failed/error/cannot) --'
            .. ' search the log for them first.', st.nErr);
    end
    if #(st.marks or {}) > 0 then
        out[#out + 1] = '';
        out[#out + 1] = 'marks (the player said something happened here):';
        for _, m in ipairs(st.marks) do
            -- The decision seq turns a mark into a JUMP: the log block headed
            -- #<seq> is the decision the player was looking at when they said
            -- this. Omitted when the ring was empty -- there is nothing to
            -- jump to, and printing "#0" would invite a search for it.
            out[#out + 1] = string.format('  +%-6s %-40s %s', M._clock(m.at),
                (m.note ~= '' and m.note ~= nil) and m.note or '(no note)',
                ((tonumber(m.seq) or 0) > 0) and ('at decision #' .. tostring(m.seq)) or '(no decision yet)');
        end
    else
        out[#out + 1] = 'no marks -- the player did not flag a moment (/dl mark <note> does that).';
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- live glue (Ashita only)
-- ---------------------------------------------------------------------------

local function clock()
    local t = 0;
    pcall(function() t = os.clock(); end);
    return t;
end

local function charName()
    local n = nil;
    pcall(function() n = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0); end);
    return M._safeName(n);
end

local function debugDir()
    local d = nil;
    pcall(function() d = AshitaCore:GetInstallPath() .. 'addons\\dlac\\debug\\'; end);
    return d;
end

-- THE FILE SEAM. Everything the bundler touches on disk goes through this one
-- table, so the whole assembly -- candidate picking, budget, fences, manifest
-- -- is drivable headless against an in-memory tree (tests RPT20+). The live
-- implementations are below; a test swaps the table and swaps it back.
--
-- Injected rather than stubbed at the io level because the interesting bugs
-- here are about WHICH files get chosen and what the file SAYS about the ones
-- it left out -- not about io.open.
M._fs = {};

function M._fs.read(p)
    if p == nil then return nil; end
    local f = io.open(p, 'rb'); if f == nil then return nil; end
    local d = f:read('*a'); f:close(); return d;
end

function M._fs.size(p)
    if p == nil then return nil; end
    local f = io.open(p, 'rb'); if f == nil then return nil; end
    local ok, n = pcall(function() return f:seek('end'); end);
    f:close();
    return ok and n or nil;
end

-- Directory listing, non-recursive, names only. profiles.lua's field-verified
-- get_dir semantics: the mask is a REGEX ('.*' -- never a Lua pattern), the
-- third argument means RECURSIVE, and files and directories come back MIXED.
function M._fs.list(path)
    local out = {};
    pcall(function()
        if not (ashita and ashita.fs and ashita.fs.get_dir) then return; end
        local ok, t = pcall(ashita.fs.get_dir, path, '.*', false);
        if ok and type(t) == 'table' then out = t; end
    end);
    return out;
end

-- The profiles module, as a seam for the same reason.
function M._fs.profiles() return try('dlac\\profiles'); end

local function readAll(p) return M._fs.read(p); end
local function fileSize(p) return M._fs.size(p); end

local function claimLabel(name)
    local arb = try('dlac\\gear\\arbiter');
    if arb == nil or type(arb.claimantLabel) ~= 'function' then return name; end
    local ok, s = pcall(arb.claimantLabel, name);
    return (ok and type(s) == 'string') and s or name;
end

-- ---------------------------------------------------------------------------
-- the recorder
-- ---------------------------------------------------------------------------

M.st = nil;          -- nil = not recording

local function logPath()
    local d = debugDir();
    return (d ~= nil) and (d .. 'dlac-capture-' .. charName() .. '.log') or nil;
end

-- Where the finished report lands, and the write itself -- both on the seam
-- so the assembly is drivable headless (M._fs).
function M._fs.out()
    local d = debugDir();
    return (d ~= nil) and (d .. 'dlac-report-' .. charName() .. '.txt') or nil;
end

function M._fs.write(path, text)
    local f = io.open(path, 'wb');
    if f == nil then error('cannot open for write: ' .. tostring(path), 0); end
    f:write(text); f:close();
end

-- BINARY append, not 'a'. Windows text mode rewrites every \n as \r\n, and the
-- log is truncated in 'wb' and read back in 'rb' -- so plain 'a' produced a
-- report with MIXED line endings, 17 stray CRs in a file whose whole job is to
-- be read by someone else's tools.
function M._fs.append(path, text)
    local f = io.open(path, 'ab');
    if f == nil then return; end
    f:write(text); f:close();
end

-- Append a batch to the live log. Opened/closed per batch on purpose (call 2):
-- a held handle loses its tail when the client dies, and batches are rare.
local function flush(st, lines)
    if st == nil or st.path == nil or #lines == 0 then return; end
    pcall(M._fs.append, st.path, table.concat(lines, '\n') .. '\n');
end

-- Queue a line into the pending batch (no IO on the calling thread).
local function q(line)
    local st = M.st;
    if st == nil then return; end
    st.q[#st.q + 1] = line;
end
M._q = q;

-- The PRE-ROLL (call 1): the rings that were already in memory when the
-- player hit record, so the minute BEFORE the button is in the file too.
local function preroll(st)
    local out = { '', '===== PRE-ROLL (already in memory when recording started) =====', '' };
    local dsp = try('dlac\\dispatch');
    local n = 0;
    if dsp ~= nil and type(dsp.getDecisions) == 'function' then
        local ok, ring = pcall(dsp.getDecisions);
        if ok and type(ring) == 'table' then
            for _, rec in ipairs(ring) do
                for _, l in ipairs(M._decLines(rec, claimLabel, nil, st.prevRec)) do out[#out + 1] = l; end
                out[#out + 1] = '';
                M._itemNames(rec, st.names);
                M._noteLevel(st, rec);
                st.lastSeq = math.max(st.lastSeq, tonumber(rec.seq) or 0);
                st.prevRec = rec;      -- the state THIS record moved away from
                n = n + 1;
            end
        end
    end
    st.nPre = n;
    if n == 0 then
        out[#out + 1] = '(no decisions were in memory -- dlac had not moved any gear yet this session)';
        out[#out + 1] = '';
    end
    if dsp ~= nil and type(dsp.getActions) == 'function' then
        local ok, acts = pcall(dsp.getActions);
        if ok and type(acts) == 'table' then
            for _, stub in ipairs(acts) do
                local l = M._actLine(stub);
                if l ~= nil then out[#out + 1] = l; end
                st.lastASeq = math.max(st.lastASeq, tonumber(stub.aseq) or 0);
            end
        end
    end
    local sl = try('dlac\\feature\\sendlog');
    if sl ~= nil and type(sl._recent) == 'function' then
        local ok, recent = pcall(sl._recent, sl.state);
        if ok and type(recent) == 'table' and #recent > 0 then
            out[#out + 1] = '';
            out[#out + 1] = 'recent sends before recording (newest first):';
            for _, r in ipairs(recent) do
                out[#out + 1] = string.format('  0x%03X  %s%s', tonumber(r.id) or 0,
                    tostring(r.why), M._passTag(r.why, r.pass));
            end
        end
    end
    out[#out + 1] = '';
    out[#out + 1] = '===== LIVE (recording from here) =====';
    out[#out + 1] = '';
    flush(st, out);
end

-- Everything new since the last beat: decisions, actions, and whatever the
-- packet/chat hooks queued.
local function pump()
    local st = M.st;
    if st == nil then return; end
    local dsp = try('dlac\\dispatch');
    if dsp ~= nil and type(dsp.getDecisions) == 'function' then
        pcall(function()
            for _, rec in ipairs(dsp.getDecisions() or {}) do
                local sq = tonumber(rec.seq) or 0;
                if sq > st.lastSeq then
                    st.lastSeq = sq;
                    st.nDec = st.nDec + 1;
                    M._itemNames(rec, st.names);
                    M._noteLevel(st, rec);
                    for _, l in ipairs(M._decLines(rec, claimLabel, nil, st.prevRec)) do q(l); end
                    st.prevRec = rec;
                    q('');
                end
            end
        end);
    end
    if dsp ~= nil and type(dsp.getActions) == 'function' then
        pcall(function()
            for _, stub in ipairs(dsp.getActions() or {}) do
                local sq = tonumber(stub.aseq) or 0;
                if sq > st.lastASeq then
                    st.lastASeq = sq;
                    -- Only the anchors the decision ring does NOT already
                    -- carry: an action that moved gear is in the block above,
                    -- and printing it twice makes the log look like it fired
                    -- twice (the one thing a timeline must never imply).
                    if stub.decSeq == nil then
                        st.nAct = st.nAct + 1;
                        local l = M._actLine(stub);
                        if l ~= nil then q(l); end
                    end
                end
            end
        end);
    end
    if #st.q > 0 then
        local batch = st.q;
        st.q = {};
        flush(st, batch);
    end
end

-- Start. `seconds` is already clamped by the caller's _dur; `full` widens the
-- bundle (call 3). Returns true, or false + the reason.
function M.start(seconds, full)
    if M.st ~= nil then return false, 'already recording'; end
    local p = logPath();
    if p == nil then return false, 'the install path is unavailable (not logged in?)'; end
    pcall(function()
        local d = debugDir();
        if d ~= nil and ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory(d);
        end
    end);
    local secs = M._dur(seconds);
    local st = {
        path = p, full = (full == true),
        startedAt = os.time(), startedClk = clock(), requested = secs,
        endsClk = clock() + secs,
        lastSeq = 0, lastASeq = 0, q = {}, marks = {}, names = {},
        nDec = 0, nAct = 0, nSend = 0, nChat = 0, nErr = 0,
        char = charName(),
    };
    -- Truncate: this run owns the file (the overwrite law, call 5).
    pcall(function()
        local f = io.open(p, 'wb');
        if f ~= nil then
            f:write(string.format('dlac capture -- %s -- started %s (window %ds)\n',
                st.char, os.date('%Y-%m-%d %H:%M:%S', st.startedAt), secs));
            f:close();
        end
    end);
    M.st = st;
    preroll(st);
    -- The send observer: sendlog knows the CAUSE of every packet, which is the
    -- entire diagnostic value (only the send site knows why it sent).
    pcall(function()
        local sl = require('dlac\\feature\\sendlog');
        sl.observer = function(id, why, pass)
            local s = M.st;
            if s == nil then return; end
            s.nSend = s.nSend + 1;
            q(string.format('[%s] SEND 0x%03X  %s%s', os.date('%H:%M:%S'), tonumber(id) or 0,
                tostring(why), M._passTag(why, pass)));
        end;
    end);
    return true;
end

-- Stop and write the report. `reason` goes in the header -- "the window
-- closed" and "the player stopped it" are different facts about the same file.
function M.stop(reason)
    local st = M.st;
    if st == nil then return nil, 'not recording'; end
    pump();
    M.st = nil;                       -- the observer sees nil and goes quiet
    pcall(function()
        local sl = require('dlac\\feature\\sendlog');
        sl.observer = nil;
    end);
    st.endedAt = os.time();
    st.recorded = math.floor(clock() - st.startedClk);
    st.stopReason = reason;
    return M._write(st);
end

-- ---------------------------------------------------------------------------
-- MARKS. A mark belongs to a MOMENT, and one moment gets one mark.
--
-- Field, 2026-08-02 (Henrik, running the first report): "I can mark the same
-- event several times. So if I have marked an event, the button should change
-- to de-mark and remove it." Two clicks on one moment produced two marks --
-- and a mark list is a reader's index into the log, so a doubled entry costs
-- exactly the thing marks exist to buy.
--
-- The moment is the DECISION the ring is newest on (`st.lastSeq`), which is
-- this addon's own word for "an event": one record per dispatch whose outcome
-- moved. Mark again on the same moment and it REPLACES -- latest words win.
-- Mark after a new decision landed and it is a new moment, so it appends. A
-- report with no decisions at all is one long moment, which is correct: the
-- gear never moved, and that IS the event being reported.
--
-- The LOG is append-only and never rewritten: an un-mark or a replace appends
-- its own line rather than erasing the first. The timeline records what the
-- player did, including changing their mind; only the mark LIST (the index)
-- is deduplicated.
-- ---------------------------------------------------------------------------

-- The mark on the CURRENT moment, or nil. The button reads this to decide
-- whether it offers Mark or Un-mark.
function M.markState()
    local st = M.st;
    if st == nil then return nil; end
    local last = st.marks[#st.marks];
    if last ~= nil and last.seq == st.lastSeq then return last; end
    return nil;
end

-- Returns ok, what -- 'added' | 'replaced' | 'cap'.
function M.mark(note)
    local st = M.st;
    if st == nil then return false, 'idle'; end
    local at = math.floor(clock() - st.startedClk);
    local text = tostring(note or '');
    local shown = (text ~= '') and text or '(no note)';
    local cur = M.markState();
    if cur ~= nil then
        local was = (cur.note ~= '') and cur.note or '(no note)';
        cur.note, cur.at = text, at;
        q(string.format('[%s] ***** MARK REPLACED +%s -- %s   (was: %s) *****',
            os.date('%H:%M:%S'), M._clock(at), shown, was));
        pump();
        return true, 'replaced';
    end
    if #st.marks >= M.MARK_CAP then return false, 'cap'; end
    st.marks[#st.marks + 1] = { at = at, note = text, seq = st.lastSeq };
    q(string.format('[%s] ***** MARK +%s -- %s *****', os.date('%H:%M:%S'), M._clock(at), shown));
    pump();                            -- a mark reaches disk immediately
    return true, 'added';
end

-- Remove the current moment's mark. Refuses when the moment has moved on --
-- an un-mark must never reach back and delete a mark the player set against a
-- DIFFERENT event, which is the one way this button could destroy evidence.
function M.unmark()
    local st = M.st;
    if st == nil then return false; end
    local cur = M.markState();
    if cur == nil then return false; end
    table.remove(st.marks);
    q(string.format('[%s] ***** MARK REMOVED (was +%s -- %s) *****', os.date('%H:%M:%S'),
        M._clock(cur.at), (cur.note ~= '') and cur.note or '(no note)'));
    pump();
    return true;
end

-- What the UI shows. nil when idle.
function M.status()
    local st = M.st;
    if st == nil then return nil; end
    local cur = M.markState();
    return {
        left = math.max(0, math.floor(st.endsClk - clock())),
        recorded = math.floor(clock() - st.startedClk),
        marks = #st.marks, decisions = st.nDec, full = st.full,
        marked = cur ~= nil, markNote = (cur ~= nil) and cur.note or nil,
    };
end

-- ---------------------------------------------------------------------------
-- the bundler
-- ---------------------------------------------------------------------------

-- Everything in the character data home, as manifest entries. Files only
-- (get_dir mixes directories in and does not say which -- profiles.lua's
-- field-verified semantics: mask '.*', never recurse, filter here).
local function listDir(path, prefix, out)
    local names = M._fs.list(path);
    for _, n in ipairs(names or {}) do
        if type(n) == 'string' and n ~= '.' and n ~= '..' then
            local sz = fileSize(path .. n);
            if sz ~= nil then
                out[#out + 1] = { label = prefix .. n, path = path .. n, size = sz };
            end
        end
    end
    return out;
end

-- The candidate list, in priority order: the active job's own data first (it
-- is the point of the bundle), then the small settings files, then -- when
-- FULL -- the rest of the profile tree and raw gear.lua.
function M._candidates(st)
    local prof = M._fs.profiles();
    local out, manifest = {}, {};
    if prof == nil then return out, manifest, nil, nil; end
    local dir = nil;
    pcall(function() dir = prof.dataDir(); end);
    if dir == nil then return out, manifest, nil, nil; end

    local job = nil;
    pcall(function() job = gData.GetPlayer().MainJob; end);
    if type(job) ~= 'string' or job == '' or job == '?' then job = nil; end
    local pname = nil;
    pcall(function() pname = prof.activeName(); end);

    -- manifest: the char root + the whole profile tree
    listDir(dir, '', manifest);
    local proot = nil;
    pcall(function() proot = prof.profilesRoot(); end);
    if proot ~= nil then
        local dirs = M._fs.list(proot) or {};
        for _, pn in ipairs(dirs) do
            if type(pn) == 'string' and pn ~= '.' and pn ~= '..' then
                for _, kind in ipairs(prof.KINDS or { 'sets', 'triggers', 'lockstyles' }) do
                    listDir(proot .. pn .. '\\' .. kind .. '\\',
                            'profiles\\' .. pn .. '\\' .. kind .. '\\', manifest);
                end
            end
        end
    end

    local seen = {};
    local function want(label, path, always)
        if path == nil or seen[label] then return; end
        local sz = fileSize(path);
        if sz == nil then return; end
        seen[label] = true;
        out[#out + 1] = { label = label, path = path, size = sz, always = always };
    end

    -- 1. the active job's trio -- ALWAYS, whatever their size
    if job ~= nil then
        pcall(function() want('profiles\\' .. tostring(pname) .. '\\sets\\' .. job .. '.lua',
                              prof.setsPath(job), true); end);
        pcall(function() want('profiles\\' .. tostring(pname) .. '\\triggers\\' .. job .. '.lua',
                              prof.triggersPath(job), true); end);
        pcall(function() want('profiles\\' .. tostring(pname) .. '\\lockstyles\\' .. job .. '.lua',
                              prof.lockstylesPath(job), true); end);
    end
    -- 2. every settings file in the char root that is not code
    for _, e in ipairs(manifest) do
        local base = e.label;
        if base:match('^[^\\]+%.lua$') ~= nil and not M.CODE_FILES[base] then
            want(base, e.path, false);
        end
    end
    -- 3. FULL: the rest of the profile tree, and raw gear.lua
    if st.full then
        for _, e in ipairs(manifest) do
            if e.label:match('^profiles\\') ~= nil then want(e.label, e.path, true); end
        end
        want('gear.lua', dir .. 'gear.lua', true);
    end
    return out, manifest, job, pname;
end

-- The one write. Returns the path, or nil + an error.
function M._write(st)
    local dsp = try('dlac\\dispatch');
    local info = {
        char = st.char, writtenAt = os.time(),
        startedAt = st.startedAt, endedAt = st.endedAt,
        requested = st.requested, recorded = st.recorded,
        full = st.full, stopReason = st.stopReason,
        engineVer = (dsp ~= nil) and dsp.VERSION or nil,
    };
    pcall(function() info.addonVer = addon ~= nil and addon.version or nil; end);

    local files, manifest, job, pname = M._candidates(st);
    info.job = job;
    local budget = st.full and M.BUDGET_FULL or M.BUDGET;
    -- FULL means full: the per-file cap is a SCOPING device for the default
    -- run, and leaving a 46 KB settings file out of a 4 MB bundle the player
    -- explicitly asked for would make "full" a word that is not true.
    local taken, skipped = M._pick(files, budget, st.full and budget or M.PERFILE);
    local bundled = {};
    for _, f in ipairs(taken) do bundled[f.label] = true; end
    for _, e in ipairs(manifest) do e.bundled = bundled[e.label] == true; end

    local L = {};
    local function add(t) for _, l in ipairs(t) do L[#L + 1] = l; end end
    -- Split file bytes into lines, tolerating ANY line ending. A player's
    -- settings file may well have been hand-edited in Notepad; the report is
    -- assembled with one convention regardless of what it swallowed.
    local function addBody(body)
        for line in tostring(body):gmatch('([^\n]*)\n?') do
            L[#L + 1] = (line:gsub('\r$', ''));
        end
    end
    local function section(name)
        L[#L + 1] = '';
        L[#L + 1] = '===== SECTION: ' .. name .. ' =====';
        L[#L + 1] = '';
    end

    add(M._header(info));

    section('health');
    -- The SAME readout /dl check prints, through check.gather + check._lines
    -- (one implementation, two doors). Guarded: a health probe that throws
    -- must not cost the whole report -- and its absence is itself a finding.
    local chk = try('dlac\\feature\\check');
    local got, hinfo = false, nil;
    if chk ~= nil and type(chk.gather) == 'function' and type(chk._lines) == 'function' then
        pcall(function()
            hinfo = chk.gather();
            local lines = chk._lines(hinfo);
            if type(lines) == 'table' and #lines > 0 then
                add(lines);
                got = true;
            end
        end);
    end
    if not got then
        L[#L + 1] = 'THE HEALTH READOUT COULD NOT BE GATHERED -- feature/check did not answer.';
        L[#L + 1] = 'That is itself a finding: this install\'s check module is missing or throwing.';
    else
        -- THE INSTRUCTION THAT CANNOT BE FOLLOWED HERE (field, 2026-08-02).
        -- The readout above tells the reader that a "[dlac] check (engine):
        -- alive" line must accompany it, and that its absence is the
        -- diagnosis. In chat that is true -- dispatch prints it from its own
        -- branch. In this FILE it can never appear: check._lines returns the
        -- addon half only. Left alone, every report accuses a healthy engine
        -- of being dead. So the file states its own equivalent, off the two
        -- version numbers, which is a stronger check than a printed line.
        add(M._engineLines(hinfo));
    end

    section('summary');
    add(M._summaryLines(st));

    section('config');
    if pname ~= nil then L[#L + 1] = 'active profile: ' .. tostring(pname); end
    if job ~= nil then L[#L + 1] = 'current job: ' .. tostring(job); end
    L[#L + 1] = '';
    local gearMod = try('dlac\\gear');
    local setNames = {};
    for _, f in ipairs(taken) do
        L[#L + 1] = string.format('===== FILE: %s (%d bytes) =====', f.label, f.size);
        local body = readAll(f.path);
        if body == nil then
            L[#L + 1] = '(could not be read)';
        else
            addBody(body);
            -- Every piece the bundled SETS ask for, whether or not the window
            -- ever got as far as considering it -- the digest's second list.
            if f.label:match('\\sets\\') ~= nil then
                pcall(M._setItemNames, body, gearMod, setNames);
            end
        end
        L[#L + 1] = '===== END FILE =====';
        L[#L + 1] = '';
    end
    if #skipped > 0 then
        L[#L + 1] = 'NOT BUNDLED (ask for any of these by name -- they exist on the player\'s disk):';
        for _, s in ipairs(skipped) do
            L[#L + 1] = string.format('  %s (%d bytes) -- %s', tostring(s.label), s.size or 0, tostring(s.why));
        end
        L[#L + 1] = '';
    end
    if not st.full then
        L[#L + 1] = 'Also left out ON PURPOSE, and why (all of it is in the manifest at the bottom):';
        L[#L + 1] = '  gear.lua -- the bag index, hundreds of KB. The gear digest below carries the'
                 .. ' items this window actually involved, with live bag availability.';
        L[#L + 1] = '  dispatch.lua / utils.lua / profiles.lua and friends -- seeded ENGINE CODE, not'
                 .. ' settings. Support already has the tree; the version is in the header.';
        L[#L + 1] = '  other jobs\' sets and triggers -- "/dl report full" bundles every job.';
        L[#L + 1] = '';
    end

    section('gear digest');
    local byName = (gearMod ~= nil) and gearMod.NameToObject or nil;
    local haveFn = nil;
    if dsp ~= nil and type(dsp._haveEquippable) == 'function' then haveFn = dsp._haveEquippable; end
    local lvl = tonumber(st.level);
    if lvl ~= nil then
        L[#L + 1] = string.format('levels below are checked against %s%d -- the job and level dlac was'
            .. ' DECIDING UNDER during the window (a level sync counts).', tostring(st.job or ''), lvl);
        L[#L + 1] = '';
    end
    L[#L + 1] = 'items this window actually involved:';
    add(M._digestLines(st.names, byName, haveFn, lvl));

    -- THE SECOND LIST is the one the first field report needed and could not
    -- have (2026-08-02). A DRG26 whose whole Ws_Default was levels 33-75 got
    -- weaponskills that silently wore TP gear: those pieces never reached a
    -- plan or a ladder, so the window named none of them and the digest --
    -- scoped to what the window named -- could not see them either. The gear a
    -- set ASKS for is exactly what has to be checked when a set does nothing.
    local rest = {};
    for n in pairs(setNames) do
        if st.names[n] ~= true then rest[n] = true; end
    end
    if next(rest) ~= nil then
        L[#L + 1] = '';
        L[#L + 1] = 'other gear your active job\'s sets ask for (never used this window) -- when a set';
        L[#L + 1] = 'appeared to do nothing, the reason is usually here:';
        add(M._digestLines(rest, byName, haveFn, lvl));
    end
    if st.full then
        L[#L + 1] = '';
        L[#L + 1] = 'scope FULL: raw gear.lua is bundled above -- everything you own is in it.';
    end

    section('log');
    local raw = readAll(st.path);
    if raw == nil then
        L[#L + 1] = string.format('(the live log at %s could not be read back -- it may still be on disk)',
            tostring(st.path));
    else
        addBody(raw);
    end

    section('manifest');
    L[#L + 1] = 'every dlac data file on this character, bundled or not (sizes in bytes):';
    L[#L + 1] = '';
    add(M._manifestLines(manifest));

    L[#L + 1] = '';
    L[#L + 1] = '===== END REPORT =====';

    local out = M._fs.out();
    if out == nil then return nil, 'the install path is unavailable'; end
    -- Failures print themselves: silence has no author, the very lesson the
    -- debug section exists to teach.
    local ok, err = pcall(M._fs.write, out, table.concat(L, '\n'));
    if not ok then
        pcall(function() print('[dlac] report: write FAILED -- ' .. tostring(err)); end);
        pcall(function() print('[dlac] report: the raw capture log is still at ' .. tostring(st.path)
            .. ' -- send that instead.'); end);
        return nil, 'write failed: ' .. tostring(err);
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------

-- dlac's OWN chat output (the privacy filter is the whole point -- see the
-- header). text_in is the established channel here (chocowatch, petvitals,
-- digrank); no IO on this handler, the pump does that.
ashita.events.register('text_in', 'dlac-report-chat', function(e)
    local st = M.st;
    if st == nil then return; end
    pcall(function()
        local line = M._clean(e.message);
        if not M._isOurs(line) then return; end
        -- The cap SAYS SO when it bites (no silent caps): a log that just
        -- stops carrying dlac's own output reads like dlac went quiet, which
        -- is a completely different diagnosis from "the reader stopped".
        if st.nChat >= M.CHAT_CAP then
            if not st.chatCapped then
                st.chatCapped = true;
                q(string.format('[%s] ***** %d dlac chat lines captured -- the cap; further lines'
                    .. ' are NOT in this log. dlac is still talking. *****',
                    os.date('%H:%M:%S'), M.CHAT_CAP));
            end
            return;
        end
        st.nChat = st.nChat + 1;
        local low = string.lower(line);
        if low:match('fail') or low:match('error') or low:match('cannot') or low:match('refus') then
            st.nErr = st.nErr + 1;
        end
        q('[' .. os.date('%H:%M:%S') .. '] ' .. line);
    end);
end);

local _beat = 0;
ashita.events.register('d3d_present', 'dlac-report-pump', function()
    local st = M.st;
    if st == nil then return; end
    if clock() >= st.endsClk then
        local p = M.stop('the window closed on its own');
        if p ~= nil then
            print('[dlac] report: window closed -- ' .. tostring(p));
            print('[dlac] report: send that ONE file. It is the whole picture.');
        end
        return;
    end
    if clock() < _beat then return; end
    _beat = clock() + 0.5;
    pcall(pump);
end);

-- A capture that dies with the client still leaves its .log (call 2); this
-- turns a clean unload into a finished report instead.
ashita.events.register('unload', 'dlac-report-unload', function()
    if M.st == nil then return; end
    pcall(M.stop, 'dlac was unloaded');
end);

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------

function M._usage()
    return 'report [seconds|full|stop]  -- record what dlac does, then write ONE sendable file.'
        .. ' Bare = ' .. tostring(M.DEF_S) .. 's (' .. tostring(M.MIN_S) .. '-' .. tostring(M.MAX_S) .. ');'
        .. ' full = bundle every job + raw gear.lua; stop = finish early.'
        .. ' While it runs, /dl mark <note> flags the moment it went wrong.';
end

ashita.events.register('command', 'dlac-report', function(e)
    local sub = M._parse(string.lower(e.command));
    if sub == nil then return; end
    e.blocked = true;
    -- The receipt: proof on disk that this state heard the command (the 07-23
    -- deaf-state case, in file form).
    pcall(function()
        local dbg = try('dlac\\feature\\debug');
        if dbg ~= nil and type(dbg.heard) == 'function' then dbg.heard('/dl report ' .. sub); end
    end);

    if sub == 'stop' then
        local p, err = M.stop('the player stopped it');
        if p == nil then
            print('[dlac] report: ' .. tostring(err) .. ' -- /dl report starts one.');
        else
            print('[dlac] report: stopped -- ' .. tostring(p));
            print('[dlac] report: send that ONE file. It is the whole picture.');
        end
        return;
    end
    if sub == 'help' or sub == '?' then print('[dlac] ' .. M._usage()); return; end

    local full = (sub == 'full');
    if sub ~= '' and not full and tonumber(sub) == nil then
        print('[dlac] ' .. M._usage());
        return;
    end
    local secs = M._dur((not full and sub ~= '') and sub or nil);
    local ok, err = M.start(secs, full);
    if not ok then
        print('[dlac] report: ' .. tostring(err) .. ' -- /dl report stop finishes it.');
        return;
    end
    print(string.format('[dlac] report: RECORDING for %ds%s. Do the thing that goes wrong,'
        .. ' and type /dl mark <note> the moment it does.', secs, full and ' (full bundle)' or ''));
    print('[dlac] report: it writes itself when the window closes -- /dl report stop finishes early.');
end);

ashita.events.register('command', 'dlac-report-mark', function(e)
    local note = M._markParse(e.command);
    if note == nil then return; end
    e.blocked = true;
    if M.st == nil then
        print('[dlac] mark: nothing is recording -- /dl report starts a capture first.');
        return;
    end
    local at = M._clock(math.floor(clock() - M.st.startedClk));
    local ok, what = M.mark(note);
    if ok and what == 'replaced' then
        -- Said out loud rather than silently doubled: a macro pressed twice is
        -- the ordinary case, and the player must know which of the two sets of
        -- words is the one in the file.
        print('[dlac] mark: this moment was already marked -- replaced its note (+' .. at .. ').');
    elseif ok then
        print('[dlac] mark: noted at +' .. at .. '.');
    else
        print('[dlac] mark: this capture already holds ' .. tostring(M.MARK_CAP) .. ' marks.');
    end
end);

return M;
