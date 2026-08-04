--[[
    dlac/feature/nmlookup.lua -- `/dl nm [name]`: which notorious monsters are
    in this zone, what pops them, and the FilterScan filter that shows only
    those spawn points.

    Henrik, 2026-08-03: "it's always annoying to find out PH IDs etc, also
    filterscan addon can track off of name and Index. It would be nice to give
    you an NM name, and you can look up the place holder IDs and even indexes
    if possible and give me a filterscan filter I can apply."

    WHAT MAKES THIS ANSWERABLE OFFLINE
    data/nmdata.lua (tools/gen_nmdata.py, from a local server clone) already
    holds the finished arithmetic: per zone, every NM and its placeholders as
    TARGET INDEXES. Index = mobid & 0xFFF -- the same value FilterScan derives
    from the zone NPC DAT (bit.band(id, 0x0FFF)), so the numbers here are the
    numbers it matches on. Nothing is computed from live memory except "which
    zone am I in", which comes from feature/location (the central service --
    memory: central-services, consume never re-derive).

    THE FILTER FilterScan's own rule (filterscan.lua, packet 0x00F4) is:
        n:find(v) or tidx == tonumber(v, 16) or v == tostring(tidx)
    -- a widescan row survives if ANY filter term matches its name as a Lua
    pattern, its index as HEX, or its index as DECIMAL. We emit plain decimal
    indexes: the PHs plus the NM itself, so the camp shows the moment it pops.
    Terms are OR-ed, so an unrelated row whose index happens to equal one of
    ours read as hex can also survive -- that only ever ADDS a row, it can
    never hide a placeholder, so it is left alone rather than papered over.

    MATCHING is deliberately forgiving (Henrik: "try to take the one that is
    closest resemblance"): exact, then prefix, then substring, then an edit
    distance. A weak best match is still shown, but labelled as a guess so a
    typo never silently answers about the wrong monster.

    Zone scope: the current zone first. If the name is not an NM here we say
    so and name the zone it IS in rather than dead-ending on "not found" --
    the indexes travel with you.

    THE BASE CHANCE IS NOT THE CHANCE (issue #152). CatsEyeXI runs DISFAVOUR
    -- bad-luck protection -- on lottery pops: the table's `c` is only the
    FLOOR, and every completed placeholder ROUND lifts it until a pop is
    guaranteed. Printing `c` alone read as a flat rate, which is the one way
    this command could mislead a camper in the direction that costs him hours.
    So the curve is stated instead of the floor -- see M.DISFAVOUR below.

    AND NOT EVERY NM IS A LOTTERY. `kind` is the server's own SPAWNTYPE: only
    "lottery" is the placeholder system. A "scripted" / "timed" / "weather" /
    "night" pop gets its own words and NO curve -- borrowing lottery language
    for an NM whose placeholders roll nothing is exactly the wasted camp this
    command exists to prevent.

    WHERE YOU ARE ON THE CURVE (issue #155) is feature\nmtrack's answer, not
    this module's: it counts the placeholder kills you personally witnessed --
    passively, by TARGET INDEX, never by name -- and this command renders what
    it has under the curve it already prints. The dependency runs ONE way at
    load (nmtrack requires this module for the curve, the table and the pop
    kind) and is reached back for at CALL time here, so there is no cycle.

    THE SAME ANSWERS IN A WINDOW (issue #156) are ui\nmui's job. This module
    grew the pure list side of it -- nameRows / areaRows / zoneChoices / rowNote
    -- rather than the window growing a second matcher: one forgiving-match
    implementation means a weak match is a guess on both surfaces and gibberish
    is refused on both. The load-time edge runs ONE way (the window requires
    this module) and `/dl nm window` reaches back for it at CALL time, so a
    build where the GUI failed to load loses the verb and nothing else.

    AND THE SAME QUESTION BACKWARDS (issue #157). "Who drops Leaping Boots?"
    is the Compendium's third filter mode, and it lives here -- M.dropRows --
    for the reason the other two do: it answers with NMs. The item half of it
    (item -> pools) is feature\nmloot's index; the matching is M.score, the one
    already above. Its floor is STRICTER than a name search's, and deliberately
    so: a typo about a monster should still find the monster, but a near-miss
    across 2183 item names is not a hedge, it is noise -- see M.ITEM_FLOOR.

    WHAT IT DROPS (issue #153) is feature\nmloot's answer, for the same reason:
    "how does it pop" and "is it worth popping" are two questions joined by one
    field -- the NM's `pool`, the server pool id that keys the generated drop
    table. It is reached at CALL time too, so a build where that module fails
    to load prints no drops section instead of taking this command down.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local _cfmt = try('dlac\\chatfmt');
local function sayMsg(s)  if _cfmt then _cfmt.msg(s)  else print('[dlac] ' .. tostring(s)); end end
local function sayGood(s) if _cfmt then _cfmt.good(s) else print('[dlac] ' .. tostring(s)); end end
local function sayWarn(s) if _cfmt then _cfmt.warn(s) else print('[dlac] ' .. tostring(s)); end end

-- The generated table. A missing/old file degrades the feature OFF rather
-- than erroring (the nativemp rule).
M.data = try('dlac\\data\\nmdata') or {};
-- Zone names come from the one zone table everything else uses.
local _zones = try('dlac\\data\\zones') or {};
-- Live zone id via the central location service; injectable for headless
-- tests (a FUNCTION, not a value -- memory: headless-tests-and-ffxi-lac).
local _loc = try('dlac\\feature\\location');
M.zoneReader = function()
    if _loc ~= nil and type(_loc.zoneId) == 'function' then return _loc.zoneId(); end
    return nil;
end;

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

function M.zoneName(zid)
    local z = _zones[zid];
    if type(z) == 'table' and type(z.n) == 'string' then return z.n; end
    return 'zone ' .. tostring(zid);
end

-- "354,355,356,357,358,359" -> "354-359"; keeps gaps ("73, 75-77").
local function runs(list)
    if list == nil or #list == 0 then return ''; end
    local s = {};
    for _, v in ipairs(list) do s[#s + 1] = v; end
    table.sort(s);
    local out, i = {}, 1;
    while i <= #s do
        local j = i;
        while j < #s and s[j + 1] == s[j] + 1 do j = j + 1; end
        if j > i then
            out[#out + 1] = string.format('%d-%d', s[i], s[j]);
        else
            out[#out + 1] = tostring(s[i]);
        end
        i = j + 1;
    end
    return table.concat(out, ', ');
end
M.runs = runs;

local function fmtDur(sec)
    sec = tonumber(sec) or 0;
    if sec >= 3600 then
        local h = sec / 3600;
        if h == math.floor(h) then return string.format('%dh', h); end
        return string.format('%.1fh', h);
    end
    if sec >= 60 then return string.format('%dm', math.floor(sec / 60)); end
    return string.format('%ds', sec);
end
M.fmtDur = fmtDur;

-- The placeholder respawn window as one string ("1h-24h", or "1h" when the
-- table gives a single figure). nil when the table does not carry one.
local function windowText(entry)
    if type(entry) ~= 'table' or type(entry.w) ~= 'table' or entry.w[1] == nil then return nil; end
    if entry.w[2] ~= nil and entry.w[2] ~= entry.w[1] then
        return fmtDur(entry.w[1]) .. '-' .. fmtDur(entry.w[2]);
    end
    return fmtDur(entry.w[1]);
end
M.windowText = windowText;

-- Percent for READING, not for arithmetic: one decimal below 10%, whole
-- percents above. Whole percents everywhere would round 6.6 and 9.5 into the
-- same "10%" and hide exactly the climb this readout exists to show.
local function pctText(p)
    p = tonumber(p);
    if p == nil then return '?'; end
    if p >= 99.95 then return '100%'; end
    if p < 10 then return string.format('%.1f%%', p); end
    return string.format('%d%%', math.floor(p + 0.5));
end
M.pctText = pctText;

-- ---------------------------------------------------------------------------
-- the disfavour curve -- HAND-CARRIED, and the tests are its source
-- ---------------------------------------------------------------------------
-- CatsEyeXI applies DISFAVOUR (bad-luck protection) to lottery pops. The base
-- chance is the floor; each completed placeholder ROUND -- every placeholder
-- killed once -- lifts it, and the climb goes near-vertical at the end:
--
--     rounds = phKills / phCount
--     chance = 100 / max( (100/base) - rounds * (1 - base/100) / 2 , 1 )
--
-- WHY THIS IS A CONSTANT AND NOT A LOOKUP. The mechanic exists in NO branch of
-- the public server repository -- verified across every branch, Lua and C++ --
-- because the module loader activates a `catseyexi` overlay directory that is
-- EMPTY there, so every server-specific change is invisible to a clone.
-- Absence from the clone is not evidence of absence on live (PRD #151,
-- "Provenance"). Scraping it was rejected for the same reason the drop tables
-- are not scraped from a wiki: a layout change would silently poison the odds.
-- So it is carried by hand, and the ANCHOR TESTS STAND IN FOR THE MISSING
-- SOURCE -- NM40* pins all four published anchors and NM41* pins the middle of
-- the curve, so a sign flip or a lost divisor cannot pass review.
--
-- The per-NM BASE (`c` in data/nmdata.lua) is the part that genuinely varies
-- and keeps coming from the generated table. Only the curve lives here.
M.DISFAVOUR = {
    source   = 'CatsEyeXI published disfavour documentation (bad-luck protection); ' ..
               'the mechanic lives in the private catseyexi overlay and is absent from every public branch',
    verified = '2026-08-03',
    formula  = 'chance = 100 / max((100/base) - rounds * (1 - base/100) / 2, 1)',
    -- Published with the mechanic; every one reproduced exactly by the formula.
    anchors  = {
        { base = 5,  rounds = 40 },
        { base = 10, rounds = 20 },
        { base = 15, rounds = 14 },
        { base = 20, rounds = 10 },
    },
};

-- The pop chance after `rounds` completed placeholder rounds, in percent.
-- nil when there is no base to build on -- the table has entries with
-- placeholders and no `c`, and a missing number is never guessed at.
function M.chanceAfter(base, rounds)
    base = tonumber(base);
    if base == nil or base <= 0 then return nil; end
    if base >= 100 then return 100; end
    rounds = tonumber(rounds) or 0;
    if rounds < 0 then rounds = 0; end
    local d = (100 / base) - rounds * (1 - base / 100) / 2;
    if d < 1 then d = 1; end                  -- the clamp: the curve stops at 100%
    return 100 / d;
end

-- How many completed rounds reach a guaranteed pop: the clamp above solved for
-- rounds, then rounded UP, because a fractional round is not something you can
-- kill. That rounding is why 15% publishes as 14 and not 13.33.
-- 0 means "already guaranteed on the first kill"; nil means "no base chance".
function M.roundsToGuaranteed(base)
    base = tonumber(base);
    if base == nil or base <= 0 then return nil; end
    if base >= 100 then return 0; end
    local raw = ((100 / base) - 1) / ((1 - base / 100) / 2);
    -- All four anchors divide EXACTLY in doubles; the epsilon only stops a base
    -- whose division lands on 40.000000000000007 from being reported as 41.
    return math.ceil(raw - 1e-9);
end

-- Three sample points on the way up, at quarters of the distance. This is the
-- part that shows the climb is real AND that it goes near-vertical at the end:
-- a 5% base reads 6.6% / 9.5% / 17% before the last quarter takes it to 100%.
-- -> { { rounds = n, chance = pct }, ... }; empty when the run is too short to
-- have a middle worth showing.
function M.curvePoints(base)
    local g = M.roundsToGuaranteed(base);
    if g == nil or g < 4 then return {}; end
    local out, seen = {}, {};
    for k = 1, 3 do
        local r = math.floor(g * k / 4 + 0.5);
        if r > 0 and r < g and not seen[r] then
            seen[r] = true;
            out[#out + 1] = { rounds = r, chance = M.chanceAfter(base, r) };
        end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- pop kind
-- ---------------------------------------------------------------------------
-- `kind` is the server's own SPAWNTYPE, decoded by the generator. Only
-- "lottery" is the placeholder system; the rest pop another way entirely and
-- must never borrow its language.
M.KIND_NOTE = {
    lottery  = 'placeholder kills roll for it',
    scripted = 'a pop item, a quest, or a forced spawn',
    timed    = 'it comes back on its own timer',
    weather  = 'it needs the right weather',
    night    = 'it only comes out at night',
};

-- The kinds an entry carries, as plain strings. An entry may carry more than
-- one; a table with no `kind` at all yields none.
function M.kinds(entry)
    local out = {};
    if type(entry) ~= 'table' or type(entry.kind) ~= 'table' then return out; end
    for _, k in ipairs(entry.kind) do
        if type(k) == 'string' and k ~= '' then out[#out + 1] = k; end
    end
    return out;
end

-- Does the disfavour curve apply at all?
-- A table with NO `kind` field is a pre-2026-08-03 data file, not a server
-- statement that this is not a lottery -- so an old table with placeholders
-- still gets the curve rather than silently losing it.
function M.isLottery(entry)
    if type(entry) ~= 'table' then return false; end
    local ks = M.kinds(entry);
    if #ks == 0 then
        return (type(entry.ph) == 'table' and #entry.ph > 0);
    end
    for _, k in ipairs(ks) do
        if k == 'lottery' then return true; end
    end
    return false;
end

-- "lottery", or "scripted + timed" for the entries carrying two. nil when the
-- table does not say.
function M.kindLabel(entry)
    local ks = M.kinds(entry);
    if #ks == 0 then return nil; end
    return table.concat(ks, ' + ');
end

-- The same thing in plain words, one clause per kind, with the group respawn
-- appended when the table carries one (only the timed-ish kinds do).
function M.kindNote(entry)
    local ks = M.kinds(entry);
    if #ks == 0 then return nil; end
    local parts = {};
    for _, k in ipairs(ks) do
        local note = M.KIND_NOTE[k];
        if note ~= nil then parts[#parts + 1] = note; end
    end
    if #parts == 0 then return nil; end
    local s = table.concat(parts, '; ');
    local rs = tonumber(entry.rs);
    if rs ~= nil then s = s .. ', respawn ' .. fmtDur(rs); end
    return s;
end

-- ---------------------------------------------------------------------------
-- fuzzy match
-- ---------------------------------------------------------------------------

local function norm(s)
    return (tostring(s or ''):lower():gsub('[^%a%d]', ''));
end

-- Classic Levenshtein, two-row. Names are short; this is not hot.
local function lev(a, b)
    local la, lb = #a, #b;
    if la == 0 then return lb; end
    if lb == 0 then return la; end
    local prev, cur = {}, {};
    for j = 0, lb do prev[j] = j; end
    for i = 1, la do
        cur[0] = i;
        local ca = a:byte(i);
        for j = 1, lb do
            local cost = (ca == b:byte(j)) and 0 or 1;
            local d = prev[j] + 1;
            local ins = cur[j - 1] + 1;
            if ins < d then d = ins; end
            local sub = prev[j - 1] + cost;
            if sub < d then d = sub; end
            cur[j] = d;
        end
        for j = 0, lb do prev[j] = cur[j]; end
    end
    return prev[lb];
end
M.lev = lev;

-- Higher is better. 0 means "no resemblance at all".
function M.score(query, name)
    local q, n = norm(query), norm(name);
    if q == '' or n == '' then return 0; end
    if q == n then return 1000; end
    if n:sub(1, #q) == q then return 900 - (#n - #q); end
    if n:find(q, 1, true) ~= nil then return 800 - (#n - #q); end
    -- every word of the query appears somewhere (handles "baldarich steel")
    local all, any = true, false;
    for w in tostring(query):lower():gmatch('[%a%d]+') do
        any = true;
        if n:find(w, 1, true) == nil then all = false; break; end
    end
    if any and all then return 700; end
    local d = lev(q, n);
    local longest = (#q > #n) and #q or #n;
    local sim = 1 - (d / longest);
    if sim < 0.5 then return 0; end            -- unrelated; don't guess wildly
    return math.floor(sim * 600);
end

-- The score a cross-zone answer must beat. Inside your zone a loose guess is
-- cheap (a handful of candidates, and you can see what is around you); across
-- all 221 zones a loose guess is just noise, so the whole-game fallback only
-- accepts a real name hit -- exact, prefix, substring, or every word present.
M.ANYWHERE_FLOOR = 700;

-- The score an ITEM name must beat to be treated as the thing the player asked
-- about, in the by-drop filter mode (issue #157). Deliberately the same figure
-- and the same reasoning as ANYWHERE_FLOOR: the drop table names 2183 distinct
-- items, and across a field that size an edit-distance guess is not a hedge, it
-- is noise -- "who drops Leaping Boots" answered with a list of NMs dropping
-- something spelled a bit like it is worse than being told nothing resembles
-- it. So only a real name hit counts: exact, prefix, substring, or every word
-- present. It is named separately from ANYWHERE_FLOOR because it answers a
-- different question, and one of the two may need to move without the other.
M.ITEM_FLOOR = 700;

-- Below this the name did not match, it merely RESEMBLED -- so the answer is
-- shown and labelled a guess rather than presented as the monster you asked
-- for. Named because chat and the Compendium window must hedge on the same
-- score: two thresholds is how one surface starts calling an answer exact
-- while the other calls it a guess, about the same NM, in the same session.
M.GUESS_FLOOR = 800;

-- Ties are common: Nyzul Isle and the Dynamis zones carry their own copies of
-- many NM names, and those copies are instanced pops with no placeholders.
-- When the score ties, prefer the entry that HAS placeholders -- that is the
-- open-world camp, and it is the only one this command can hand you a useful
-- filter for.
local function beats(s, e, bestS, bestE)
    if bestE == nil then return s > 0; end
    if s ~= bestS then return s > bestS; end
    local has  = (e.ph ~= nil and #e.ph > 0);
    local bhas = (bestE.ph ~= nil and #bestE.ph > 0);
    return has and not bhas;
end

-- Best entry for `query` within one zone. -> entry, score
function M.matchInZone(zid, query)
    local list = M.data[zid];
    if type(list) ~= 'table' then return nil, 0; end
    local best, bestScore = nil, 0;
    for _, e in ipairs(list) do
        local s = M.score(query, e.n);
        if beats(s, e, bestScore, best) then best, bestScore = e, s; end
    end
    return best, bestScore;
end

-- Every zone the table can answer for, ascending. `pairs()` order is undefined
-- (hard rule 8), and both the whole-game match and the window's area picker
-- walk this table -- so the order is fixed HERE, once, instead of in each
-- caller where one of them would eventually forget.
function M.zoneIds()
    local zids = {};
    for zid, list in pairs(M.data) do
        if type(list) == 'table' then zids[#zids + 1] = zid; end
    end
    table.sort(zids);
    return zids;
end

-- Best entry anywhere. -> entry, score, zoneId
-- Zone ids are walked in order so the answer never depends on hash order.
function M.matchAnywhere(query)
    local zids = M.zoneIds();
    local best, bestScore, bestZone = nil, 0, nil;
    for _, zid in ipairs(zids) do
        for _, e in ipairs(M.data[zid]) do
            local s = M.score(query, e.n);
            if beats(s, e, bestScore, best) then best, bestScore, bestZone = e, s, zid; end
        end
    end
    return best, bestScore, bestZone;
end

-- ---------------------------------------------------------------------------
-- the compendium list -- ONE list, several filter modes (issue #156, PRD #151)
-- ---------------------------------------------------------------------------
-- Every search here returns NMs, so one list serves all of them. That is the
-- whole reason the Compendium is one master-detail window where the dig search
-- needed two: its two searches return different KINDS of thing (items, zones),
-- and the cross-link between them needed a second window. Clicking a zone here
-- only re-filters the list you are already looking at.
--
-- These are PURE -- data in, plain rows out, no imgui. `ui\nmui` is a thin
-- renderer over them, and the chat command scores names through the same
-- M.score, so a matching rule can never mean two things on two surfaces.

-- feature\nmloot, reached at CALL time. Forward-declared here because the
-- by-drop filter mode below is written beside the other two and the accessor
-- itself belongs with the other call-time reaches, further down -- and a local
-- referenced before its declaration is a silent nil GLOBAL (hard rule 8).
local loot;

-- One row: the entry, the zone it lives in, and (for a name search) how well it
-- answered. `guess` is the weak-match verdict the chat readout hedges on,
-- decided in ONE place so the window cannot hedge differently.
local function makeRow(entry, zid, score)
    return {
        e     = entry,
        zid   = zid,
        n     = tostring(entry.n or '?'),
        score = score,
        guess = (score ~= nil) and (score < M.GUESS_FLOOR) or false,
        ph    = (type(entry.ph) == 'table') and #entry.ph or 0,
    };
end

-- Best first, and TOTALLY ordered: table.sort refuses a comparator that cannot
-- decide, and "score then placeholders" alone leaves whole blocks undecided at
-- 2000+ entries. Zone id then name finish the order, so the list a player sees
-- is the same list every time rather than one that reshuffles as they type.
local function rowOrder(a, b)
    if a.score ~= b.score then return (a.score or 0) > (b.score or 0); end
    -- The tie-break that matters: same score, and one of them HAS placeholders.
    -- Nyzul Isle and the Dynamis zones carry same-named instanced copies with
    -- none, and the open-world camp is the one the player means.
    local ah, bh = (a.ph > 0), (b.ph > 0);
    if ah ~= bh then return ah; end
    if a.zid ~= b.zid then return a.zid < b.zid; end
    return a.n < b.n;
end

-- Filter mode BY NAME: every NM whose name resembles `query`, best first.
-- Gibberish yields NOTHING rather than a list of things it is not -- M.score
-- answers 0 for a name with no resemblance, and a zero never becomes a row.
-- Weak rows are kept and flagged, never dropped: a typo must still find the
-- monster, it just may not claim to be sure.
-- -> rows, total  (rows is capped at `limit`; total is what matched)
function M.nameRows(query, limit)
    local out = {};
    query = tostring(query or '');
    if query:gsub('%s', '') == '' then return out, 0; end
    for _, zid in ipairs(M.zoneIds()) do
        for _, e in ipairs(M.data[zid]) do
            local s = M.score(query, e.n);
            if s > 0 then out[#out + 1] = makeRow(e, zid, s); end
        end
    end
    table.sort(out, rowOrder);
    local total = #out;
    limit = tonumber(limit);
    if limit ~= nil and limit > 0 then
        for i = total, limit + 1, -1 do out[i] = nil; end
    end
    return out, total;
end

-- Filter mode BY AREA: everything in one zone, the campable ones first. Same
-- grouping the chat list uses -- placeholders, then the rest, each block by
-- name -- because it is the same answer in a different shape.
function M.areaRows(zid)
    local out = {};
    local list = M.data[zid];
    if type(list) ~= 'table' then return out; end
    for _, e in ipairs(list) do out[#out + 1] = makeRow(e, zid, nil); end
    table.sort(out, function(a, b)
        local ah, bh = (a.ph > 0), (b.ph > 0);
        if ah ~= bh then return ah; end
        if a.n ~= b.n then return a.n < b.n; end
        -- A zone can list the same name twice (two spawn points, two entries).
        -- Their first NM index separates them, so the pair has an order instead
        -- of swapping places between frames.
        local ai = (type(a.e.nm) == 'table') and a.e.nm[1] or 0;
        local bi = (type(b.e.nm) == 'table') and b.e.nm[1] or 0;
        return (ai or 0) < (bi or 0);
    end);
    return out;
end

-- How many of an NM's matched drops a row names before it stops naming them.
-- A search for "boots" hits several items on one Abyssea NM, and a row that
-- reads as a paragraph is a row nobody scans.
M.DROP_NAMES = 3;

-- Filter mode BY DROP: every NM that drops the item you typed -- the reverse
-- lookup, and the one question the Compendium could not answer without leaving
-- the game. It runs the join backwards: the item names the drop table can
-- answer for -> the pools carrying them -> the NM entries carrying those pools.
--
-- ONLY A REAL NAME HIT COUNTS (M.ITEM_FLOOR). The by-name mode hedges a weak
-- match and labels it a guess, because there the player has one monster in mind
-- and a typo should still find it. Here they have an ITEM in mind out of 2183,
-- and a list of NMs dropping something spelled a bit like it does not answer
-- the question -- it buries it. So a weak resemblance yields nothing and the
-- window says nothing resembles it, which is an answer.
--
-- -> rows, total, items
--    rows  -- the NM rows, best first, capped at `limit`
--    total -- how many matched before the cap
--    items -- the item names the query hit, best first: what the list is OF
function M.dropRows(query, limit)
    local out, items = {}, {};
    query = tostring(query or '');
    if query:gsub('%s', '') == '' then return out, 0, items; end
    -- All three halves of the reverse index, checked together: this module
    -- reaches nmloot at call time, so "it loaded" is not the same as "it is the
    -- build that carries these" -- and a nil call here would take the window's
    -- whole frame rather than one filter mode.
    local lt = loot();
    if lt == nil or type(lt.namedItems) ~= 'function'
       or type(lt.poolsForItem) ~= 'function' or type(lt.poolsOf) ~= 'function' then
        return out, 0, items;
    end

    -- 1. Which items did they name? Scored through the SAME matcher the NM
    -- names go through -- there is one implementation of "does this resemble
    -- that" here, and a second one is how two surfaces start disagreeing.
    -- Declared on its own line, and that is not style: a local is not in scope
    -- inside its OWN declaration, so `local hits, ok = {}, pcall(function()
    -- ... hits ... end)` would have the closure writing to a nil global (hard
    -- rule 8, and it cost a debugging round here).
    local hits = {};
    local ok = pcall(function()
        for _, it in ipairs(lt.namedItems()) do
            local s = M.score(query, it.name);
            if s >= M.ITEM_FLOOR then
                hits[#hits + 1] = { id = it.id, name = it.name, score = s };
            end
        end
    end);
    if not ok or #hits == 0 then return out, 0, items; end

    -- 2. Which pools carry them. Walked in the hits' own (id-ascending) order,
    -- so the names a row lists are in the same order every time.
    local pool = {};
    for _, h in ipairs(hits) do
        for _, pid in ipairs(lt.poolsForItem(h.id)) do
            local b = pool[pid];
            if b == nil then b = { score = 0, names = {}, seen = {} }; pool[pid] = b; end
            if h.score > b.score then b.score = h.score; end
            if not b.seen[h.name] then
                b.seen[h.name] = true;
                b.names[#b.names + 1] = h.name;
            end
        end
    end

    -- 3. Which NMs carry those pools. An NM with several pools answers once.
    for _, zid in ipairs(M.zoneIds()) do
        for _, e in ipairs(M.data[zid]) do
            local best, names, seen = 0, {}, {};
            for _, pid in ipairs(lt.poolsOf(e)) do
                local b = pool[pid];
                if b ~= nil then
                    if b.score > best then best = b.score; end
                    for _, nm in ipairs(b.names) do
                        if not seen[nm] then seen[nm] = true; names[#names + 1] = nm; end
                    end
                end
            end
            if best > 0 then
                local row = makeRow(e, zid, best);
                -- NOT a guess, whatever the score: nothing about the MONSTER
                -- was guessed at. The table says this NM drops that item, and
                -- the score only measures how squarely the item was named.
                row.guess = false;
                row.drops = names;
                row.dropNote = names[1] or '';
                if #names > M.DROP_NAMES then
                    local shown = {};
                    for k = 1, M.DROP_NAMES do shown[k] = names[k]; end
                    row.dropNote = table.concat(shown, ', ')
                        .. string.format(' +%d more', #names - M.DROP_NAMES);
                elseif #names > 1 then
                    row.dropNote = table.concat(names, ', ');
                end
                out[#out + 1] = row;
            end
        end
    end
    table.sort(out, rowOrder);

    table.sort(hits, function(a, b)
        if a.score ~= b.score then return a.score > b.score; end
        return a.name < b.name;
    end);
    for _, h in ipairs(hits) do items[#items + 1] = h.name; end

    local total = #out;
    limit = tonumber(limit);
    if limit ~= nil and limit > 0 then
        for i = total, limit + 1, -1 do out[i] = nil; end
    end
    return out, total, items;
end

-- The zones the table can answer for, named and counted: the area picker's
-- whole source. Sorted by NAME, which is what the player reads -- zone id order
-- is the server's business, and it scatters neighbouring zones.
function M.zoneChoices()
    local out = {};
    for _, zid in ipairs(M.zoneIds()) do
        out[#out + 1] = { zid = zid, name = M.zoneName(zid), n = #M.data[zid] };
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name; end
        return a.zid < b.zid;
    end);
    return out;
end

-- The one line a list row carries beside the name: the placeholders you watch
-- when there are any, the pop kind when there are not. Deliberately carries NO
-- percentage -- the numbers belong on the detail card (#157), and every one of
-- them is a `%` that has to survive an ImGui format string.
function M.rowNote(entry)
    if type(entry) ~= 'table' then return ''; end
    local phcount = (type(entry.ph) == 'table') and #entry.ph or 0;
    if phcount > 0 then
        local s = string.format('%s x%d', tostring(entry.p or '?'), phcount);
        -- Placeholders the server does not roll a lottery on. Saying so on the
        -- row is the difference between a camp and a wasted evening.
        if not M.isLottery(entry) then s = s .. '  (not a lottery)'; end
        return s;
    end
    local k = M.kindLabel(entry);
    if k ~= nil then return k .. ' pop, no placeholders'; end
    return 'no placeholders';
end

-- ---------------------------------------------------------------------------
-- rendering
-- ---------------------------------------------------------------------------

-- The FilterScan argument: placeholders + the NM, decimal, comma separated.
function M.filterFor(entry)
    if type(entry) ~= 'table' then return nil; end
    local seen, all = {}, {};
    for _, t in ipairs({ entry.ph or {}, entry.nm or {} }) do
        for _, v in ipairs(t) do
            if not seen[v] then seen[v] = true; all[#all + 1] = v; end
        end
    end
    if #all == 0 then return nil; end
    table.sort(all);
    local parts = {};
    for _, v in ipairs(all) do parts[#parts + 1] = tostring(v); end
    return table.concat(parts, ',');
end

-- What pops this NM, in the player's words -- and, for a lottery, what the
-- chance actually DOES. At most three lines, and the extra two over the old
-- flat "5% per kill" are the whole point of the readout.
function M.popLines(entry)
    local out = {};
    if type(entry) ~= 'table' then return out; end
    local phcount = (type(entry.ph) == 'table') and #entry.ph or 0;
    local lottery = M.isLottery(entry);
    local label   = M.kindLabel(entry);

    -- The head line: the pop kind, plus the placeholders when there are any.
    local head;
    if phcount > 0 then
        head = string.format('  %s pop: %s x%d', label or 'placeholder',
            tostring(entry.p or '?'), phcount);
        local w = windowText(entry);
        if w ~= nil then head = head .. ', repop ' .. w; end
        -- Five entries in the shipped table carry placeholders AND a scripted
        -- spawn kind. The indexes are still where it comes from -- they stay in
        -- the filter -- but the server does not run the lottery on them, so
        -- saying so is the difference between a camp and a wasted evening.
        if not lottery then head = head .. ' -- not a lottery, so no disfavour curve'; end
    else
        head = string.format('  %s pop', label or 'unknown');
        if lottery then
            head = head .. ' -- placeholder-driven, but this table lists no placeholders for it';
        else
            local note = M.kindNote(entry);
            if note ~= nil then
                head = head .. ' -- ' .. note;
            else
                head = head .. ' -- the table does not say how, and lists no placeholders for it';
            end
        end
    end
    out[#out + 1] = head;

    if not lottery or phcount == 0 then return out; end

    -- The curve. A base we do not have is admitted, never invented.
    local base = tonumber(entry.c);
    local guaranteed = M.roundsToGuaranteed(base);
    if guaranteed == nil then
        out[#out + 1] = '  base chance is not in the table -- disfavour still climbs, but the numbers cannot be shown';
        return out;
    end
    if guaranteed <= 0 then
        out[#out + 1] = string.format('  %g%% base -- already a guaranteed pop on the first placeholder kill', base);
        return out;
    end
    local roundIs;
    if phcount == 1 then
        roundIs = 'a round = the one placeholder';
    elseif phcount == 2 then
        roundIs = 'a round = both placeholders';
    else
        roundIs = string.format('a round = all %d placeholders', phcount);
    end
    out[#out + 1] = string.format('  %g%% base, and not flat -- disfavour lifts it every round (%s)',
        base, roundIs);
    local parts = {};
    for _, p in ipairs(M.curvePoints(base)) do
        parts[#parts + 1] = string.format('%d rounds %s', p.rounds, pctText(p.chance));
    end
    local tail = string.format('%d rounds is a guaranteed pop', guaranteed);
    if #parts > 0 then
        out[#out + 1] = '  ' .. table.concat(parts, ', ') .. ' -- ' .. tail;
    else
        out[#out + 1] = '  ' .. tail;
    end
    return out;
end

-- The pop tracker (feature\nmtrack), reached at CALL time. It requires THIS
-- module at load for the curve and the table, so the load-time edge runs one
-- way only and this side must never capture it in an upvalue.
local function tracker()
    return try('dlac\\feature\\nmtrack');
end
M._tracker = tracker;   -- test seam

-- The drop readout (feature\nmloot), reached at CALL time for the same reason:
-- an absent or broken module must cost this command its drops section and
-- nothing else. Forward-declared up in the compendium-list section, which asks
-- it for the by-drop filter mode's reverse index.
loot = function()
    return try('dlac\\feature\\nmloot');
end
M._loot = loot;         -- test seam

-- The Compendium window (ui\nmui), reached at CALL time for the third time and
-- the same reason: the window requires THIS module at load for the table and
-- the matching, so the load-time edge runs one way only and a build where the
-- GUI failed to load must cost the `window` verb and nothing else.
local function windowUI()
    return try('dlac\\ui\\nmui');
end
M._windowUI = windowUI;   -- test seam

-- Open the NM Compendium on a search. Any surface may open a floating window;
-- exactly one site may draw it (gearui's d3d_present) -- this is an OPEN.
-- A name lands the window on that search; with nothing to search for it opens
-- on the zone you are standing in, because that is the case that should take no
-- input at all.
-- `zid` is optional: a caller that already read the zone (the command does)
-- passes it, and a caller that has no business reading it (the header menu)
-- leaves it out and gets the same answer. ONE entry point for every surface --
-- the menu row and `/dl nm window` must not be able to open different windows.
function M.openWindow(query, zid)
    if zid == nil then zid = M.zoneReader(); end
    local ui = windowUI();
    if ui == nil or type(ui.openName) ~= 'function' or ui.degraded == true then
        sayWarn('nm: the Compendium window is not available in this build -- '
            .. '"/dl nm <name>" answers the same questions in chat.');
        return false;
    end
    query = tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', '');
    local ok = pcall(function()
        if query ~= '' then ui.openName(query); else ui.openArea(zid); end
    end);
    if not ok then
        sayWarn('nm: the Compendium window could not be opened.');
        return false;
    end
    return true;
end

-- Lines describing one NM. `guess` marks a weak match; `th` is the Treasure
-- Hunter level the player asked to see drop rates at (nil = none asked for).
function M.describe(entry, zid, guess, th)
    local out = {};
    if type(entry) ~= 'table' then return out; end
    local where = M.zoneName(zid);
    out[#out + 1] = string.format('%s -- %s', entry.n, where);
    if guess then
        out[#out + 1] = '  (closest match to what you typed -- not an exact name)';
    end
    for _, line in ipairs(M.popLines(entry)) do out[#out + 1] = line; end
    -- Where YOU are on that curve, directly under what the curve does. Silent
    -- for anything the tracker has nothing to say about (a non-lottery pop, or
    -- a build where the module could not load).
    local trk = tracker();
    if trk ~= nil and type(trk.entryLines) == 'function' then
        local ok, lines = pcall(trk.entryLines, entry, zid);
        if ok and type(lines) == 'table' then
            for _, line in ipairs(lines) do out[#out + 1] = line; end
        end
    end
    local phcount = (type(entry.ph) == 'table') and #entry.ph or 0;
    if phcount > 0 then
        out[#out + 1] = string.format('  NM index %s  |  PH indexes %s',
            runs(entry.nm or {}), runs(entry.ph));
    else
        out[#out + 1] = string.format('  NM index %s', runs(entry.nm or {}));
    end
    local f = M.filterFor(entry);
    if f ~= nil then out[#out + 1] = '  /filterscan ' .. f; end
    -- What it gives, last: the indexes and the filter are what a camper acts on
    -- straight away, and the drop table is what decides whether to bother at
    -- all. An NM the table has nothing for says so there rather than leaving a
    -- silence that reads as "drops nothing".
    local lt = loot();
    if lt ~= nil and type(lt.lines) == 'function' then
        local ok, lines = pcall(lt.lines, entry, th);
        if ok and type(lines) == 'table' then
            for _, line in ipairs(lines) do out[#out + 1] = line; end
        end
    end
    return out;
end

-- Lines listing every NM in a zone.
function M.listLines(zid)
    local out = {};
    local list = M.data[zid];
    if type(list) ~= 'table' or #list == 0 then
        out[#out + 1] = string.format('%s: no notorious monsters in the table.', M.zoneName(zid));
        return out;
    end
    local withPh, without = {}, {};
    for _, e in ipairs(list) do
        if e.ph ~= nil and #e.ph > 0 then withPh[#withPh + 1] = e; else without[#without + 1] = e; end
    end
    out[#out + 1] = string.format('%s -- %d NM(s), %d with placeholders:',
        M.zoneName(zid), #list, #withPh);
    for _, e in ipairs(withPh) do
        out[#out + 1] = string.format('  %-26s PH %s x%d  (%s)',
            e.n, e.p or '?', #e.ph, runs(e.ph));
    end
    if #without > 0 then
        local names = {};
        for _, e in ipairs(without) do names[#names + 1] = e.n; end
        out[#out + 1] = '  no placeholders (pop item / timed / forced): ' .. table.concat(names, ', ');
    end
    out[#out + 1] = '  /dl nm <name> for one NM\'s indexes and a ready filter.';
    return out;
end

-- ---------------------------------------------------------------------------
-- /dl nm [name] [apply]
-- ---------------------------------------------------------------------------

function M.command(rest)
    rest = tostring(rest or ''):gsub('^%s+', ''):gsub('%s+$', '');

    if next(M.data) == nil then
        sayWarn('nm: data/nmdata.lua is missing or empty -- re-run tools/gen_nmdata.py.');
        return;
    end

    -- The trailing verbs, stripped in a LOOP so their order is the player's
    -- business and not this parser's: each pattern is anchored at the end, so
    -- one pass would only ever understand whichever verb was typed last.
    -- No NM in the shipped table is called "apply", "reset" or "counts", and
    -- none ends in "th <number>", so all of them read as verbs.
    local apply, reset, th, thAsked = false, false, nil, false;
    local moved = true;
    while moved do
        moved = false;
        -- `%s*` not `%s+` so a bare `/dl nm apply` is understood as the verb
        -- too, instead of being hunted for as an NM called "apply".
        local s = rest:gsub('%s*apply%s*$', '');
        if s ~= rest then apply = true; rest = s; moved = true; end
        -- `reset` drops the count for the NM named in front of it. The one
        -- manual door into the tracker -- staleness is sticky by design, so
        -- without it a camp resumed after a zone could never show a chance
        -- again.
        s = rest:gsub('%s*[Rr][Ee][Ss][Ee][Tt]%s*$', '');
        if s ~= rest then reset = true; rest = s; moved = true; end
        -- `th4` (issue #154): show every drop's rate at that Treasure Hunter
        -- level. The number is required -- a bare `th` is answered with the
        -- syntax rather than a level we picked for the player, because the
        -- whole readout would then be about gear they may not own.
        local lvl = rest:match('%s[Tt][Hh]%s*(%d+)%s*$') or rest:match('^[Tt][Hh]%s*(%d+)%s*$');
        if lvl ~= nil then
            th = tonumber(lvl);
            thAsked = true;
            rest = rest:gsub('%s*[Tt][Hh]%s*%d+%s*$', '');
            moved = true;
        elseif rest:match('%s[Tt][Hh]%s*$') ~= nil or rest:match('^[Tt][Hh]%s*$') ~= nil then
            thAsked = true;
            rest = rest:gsub('%s*[Tt][Hh]%s*$', '');
            moved = true;
        end
        rest = rest:gsub('%s+$', '');
    end
    if thAsked and th == nil then
        sayWarn('nm: say which TH level -- "/dl nm <name> th4" shows every drop at TH4 (0-14).');
    end
    -- Held to what the server's own table can answer for, and a clamp is said
    -- out loud: answering TH14 to someone who typed TH20 without saying so is
    -- answering a different question than the one asked.
    if th ~= nil then
        local lt = loot();
        if lt ~= nil and type(lt.clampTH) == 'function' then
            local lvl, clamped = lt.clampTH(th);
            if clamped then
                sayWarn(string.format('nm: TH runs 0-%d in the server\'s own table -- showing TH%d.',
                    lt.TH_MAX or 14, lvl));
            end
            th = lvl;
        end
    end

    local zid = M.zoneReader();

    -- `window` opens the Compendium instead of answering in chat, optionally
    -- on a name: `/dl nm window bonnacon`. A LEADING verb rather than a trailing
    -- one because everything after it is the search, and no NM in the shipped
    -- table is called "window" or "gui".
    local lead, tail = rest:match('^(%S+)%s*(.*)$');
    if lead ~= nil then
        local lv = lead:lower();
        if lv == 'window' or lv == 'win' or lv == 'gui' then
            -- The chat-only verbs do not travel into the window. Say so rather
            -- than eating the word (hard rule 12: a dropped instruction and an
            -- honoured one must not look the same).
            if apply or reset or th ~= nil then
                sayWarn('nm: "apply", "reset" and "th" answer in chat -- '
                    .. 'the window is opening without them.');
            end
            M.openWindow(tail, zid);
            return;
        end
    end

    -- Every camp you hold a count for. Deliberately zone-independent: the point
    -- of it is resuming a camp you started somewhere else.
    local verb = rest:lower();
    if verb == 'counts' or verb == 'count' then
        local trk = tracker();
        local lines = nil;
        if trk ~= nil and type(trk.countLines) == 'function' then
            local ok, l = pcall(trk.countLines);
            if ok then lines = l; end
        end
        if type(lines) ~= 'table' then
            sayWarn('nm: the pop tracker is not loaded.');
            return;
        end
        for i, line in ipairs(lines) do
            if i == 1 then sayGood(line); else sayMsg(line); end
        end
        return;
    end

    -- bare: list this zone
    if rest == '' then
        if zid == nil then
            sayWarn('nm: cannot read your zone right now -- try again once you are loaded in.');
            return;
        end
        local lines = M.listLines(zid);
        for i, line in ipairs(lines) do
            if i == 1 then sayGood(line); else sayMsg(line); end
        end
        -- Asked to apply, but a zone-wide list is not one camp. Say so rather
        -- than dropping the word on the floor.
        if apply then
            sayWarn('  nothing to apply -- name one NM: /dl nm <name> apply');
        end
        if reset then
            sayWarn('  nothing to reset -- name one NM: /dl nm <name> reset');
        end
        if th ~= nil then
            sayWarn('  nothing to show a TH rate for -- name one NM: /dl nm <name> th' .. tostring(th));
        end
        return;
    end

    -- named: this zone first, then anywhere
    local entry, score, foundZone = nil, 0, zid;
    if zid ~= nil then entry, score = M.matchInZone(zid, rest); end
    local elsewhereNote = nil;
    if entry == nil or score < M.ANYWHERE_FLOOR then
        local e2, s2, z2 = M.matchAnywhere(rest);
        if e2 ~= nil and s2 >= M.ANYWHERE_FLOOR and s2 > score then
            if zid ~= nil and z2 ~= zid then
                elsewhereNote = string.format('not in %s -- that one is in %s',
                    M.zoneName(zid), M.zoneName(z2));
            end
            entry, score, foundZone = e2, s2, z2;
        end
    end

    if entry == nil or score == 0 then
        sayWarn(string.format('nm: nothing resembling "%s" in the NM table.', rest));
        if zid ~= nil then sayMsg('  /dl nm  lists what is in this zone.'); end
        return;
    end

    if elsewhereNote ~= nil then sayWarn('nm: ' .. elsewhereNote); end

    -- Reset BEFORE the description, so what prints is the camp as it now
    -- stands rather than the count that was just dropped.
    if reset then
        local trk = tracker();
        local cleared = false;
        if trk ~= nil and type(trk.forget) == 'function' then
            local ok, done = pcall(trk.forget, foundZone, entry);
            cleared = (ok and done == true);
        end
        if cleared then
            sayGood(string.format('nm: %s count cleared -- counting starts over from your next placeholder kill.', entry.n));
        else
            sayWarn(string.format('nm: no count to clear for %s.', entry.n));
        end
    end

    local lines = M.describe(entry, foundZone, score < M.GUESS_FLOOR, th);
    for i, line in ipairs(lines) do
        if i == 1 then sayGood(line); else sayMsg(line); end
    end

    if apply then
        local f = M.filterFor(entry);
        if f == nil then
            sayWarn('  nothing to filter on for that one.');
        else
            local ok = pcall(function()
                AshitaCore:GetChatManager():QueueCommand(-1, '/filterscan ' .. f);
            end);
            if ok then
                sayGood('  applied (FilterScan must be loaded for this to bite).');
            else
                sayWarn('  could not send the command -- paste the line above instead.');
            end
        end
    end
end

ashita.events.register('command', 'dlac-nmlookup-cmd', function(e)
    pcall(function()
        local raw = tostring(e.command or '');
        local a, rest = raw:match('^/dl%s+(%S+)%s*(.*)$');
        if a == nil then a, rest = raw:match('^/dlac%s+(%S+)%s*(.*)$'); end
        if a == nil then return; end
        a = a:lower();
        if a ~= 'nm' and a ~= 'nms' and a ~= 'placeholder' and a ~= 'ph' then return; end
        e.blocked = true;
        M.command(rest);
    end);
end);

return M;
