--[[
    dlac/feature/nmloot.lua -- what an NM drops, read out under `/dl nm <name>`.

    Issue #153, PRD #151: "It shows nothing about drops, so the question 'is
    this NM even worth camping' cannot be answered inside the game."

    WHY A SEPARATE MODULE FROM nmlookup. Placeholders answer "how does it pop";
    drops answer "is it worth popping". They join on ONE field and share no
    arithmetic, and the drop maths (group shares, tier names, the item-name
    resolve) is worth its own test surface. nmlookup reaches this module at
    CALL time, exactly like the tracker, so a build where this file fails to
    load prints no drops section instead of taking `/dl nm` down with it.
    The file is called `nmloot` and NOT `nmdrops` on purpose: `dlac\data\nmdrops`
    is the generated TABLE, and hard rule 13 is a list of hours lost to a module
    whose name near-missed a data file's (lockstyle/lockstyles, macrobook/
    macrobooks). One name, one thing.

    THE TABLE. data/nmdrops.lua is GENERATED from the CatsEyeXI LIVE API
    (/api/mob/<poolid>) -- 973 pools, 5372 rows, keyed by SERVER POOL ID, and
    joined to an NM through its `pool` field. The clone is NOT the source and
    must never be read for this: its module loader mounts a `catseyexi` overlay
    that is EMPTY in the public repo, so live differs in both item and rate
    (Mee Deggi gives Ochiudo's Kote at 10%; the clone says Ochimusha Kote at
    5%). Per row: `i` item id, `r` rate, `t` drop type (absent/0 normal,
    1 grouped, 2 steal, 4 despoil), `g` group id and `gr` group rate on
    grouped rows only.

    THREE PROPERTIES OF THE DATA ARE LOAD-BEARING, and every one of them is a
    way this readout could lie:

    1. A GROUPED ROW'S `r` IS A WEIGHT, NOT A PERCENTAGE. The group rolls ONCE
       at `gr`, then exactly ONE item inside it wins by weight. 2009 of the
       5372 rows are grouped, so rendering `r` as a percent would misstate more
       than a third of the table -- and would tell a camper Ochiudo's Kote is a
       10% drop because `r = 100` happens to look like a percent. Those two
       readings coincide there BY ACCIDENT (its group is `gr = 1000`, so the
       group always drops and 100/(900+100) really is 10%); they do not
       coincide in general. Groups are therefore rendered AS groups -- "one of
       these: A 90%, B 10%" -- and the percentage beside a member is its share
       of the group, never a chance per kill.

    2. DUPLICATE ROWS ARE REAL. Leaping Lizzy (pool 2384) lists item 926 at
       r = 240 and AGAIN at r = 150. Two independent rolls, and both are shown.
       Deduping them would quietly halve what the player is told to expect,
       which is why the section head says "rolls" and not "items".

    3. STEAL (t=2) AND DESPOIL (t=4) ARE NOT KILL LOOT. They get their own
       section, because listing them as drops tells a player to expect
       something a kill will never give. Most carry `r = 0` -- the API states
       no rate for them -- and a zero is left unsaid rather than printed as
       "0%", which would read as "impossible" instead of "not stated".

    WHERE ONE GROUP ENDS AND THE NEXT BEGINS is decided by a RUN over the rows
    in table order, in one sentence: a grouped row continues the current group
    while its `g` AND `gr` both match the last GROUPED row, and opens a new one
    otherwise. Rows that are not grouped are passed over rather than closing
    the run, so the rule needs no special case for the steal rows that trail
    most pools -- and the shipped table has no ungrouped row sitting inside a
    group run for that choice to matter to.

    The data forces the `gr` half of it. Pool 245 lists group 1 four times at
    `gr = 1000` and then the SAME four items as group 1 again at `gr = 100`;
    86 rows across a handful of pools carry a group id whose group rate changes
    under it. Keying on `g` alone would have to throw one of the two rates away
    -- a silent loss, and the second roll with it -- while the run rule keeps
    both and reads them as what they plainly are: two rolls of the same set at
    two different rates, the group-level form of property 2 above. Rows of one
    run are contiguous in all 973 pools, so this never splits a group the table
    meant as one.

    ITEM NAMES ARE NOT IN THE TABLE, ON PURPOSE. They come from the client's
    own item resources so they always match what the client calls them --
    resolved LAZILY, one id at a time, never at load: a name table built at
    load would run before the player is logged in, and the client would answer
    with nothing. Only a SUCCESSFUL resolve is remembered (ADR 0007: a
    not-ready read is not an answer, and a latch makes one bad read permanent),
    so an id asked for too early answers properly the next time it is asked.
    An id that will not resolve renders AS AN ID -- it never vanishes, because
    a missing row is indistinguishable from a table that never had it.

    RATES ARE THE SERVER'S OWN EIGHT NAMED TIERS (1000 always, 240 very common,
    150 common, 100 uncommon, 50 rare, 10 very rare, 5 super rare, 1 ultra
    rare), so that is the vocabulary shown beside the percentage rather than
    one invented here. 1215 rows carry a rate that is NOT one of the eight;
    those are still valid weights and show a percentage with NO tier name,
    because snapping 250 to "very common" would be inventing a fact.

    TREASURE HUNTER (issue #154) IS A BRACKET LOOKUP, NOT A MULTIPLIER, and
    that is the whole reason this can be answered at all: the rate selects a
    RARITY BRACKET and the TH level selects the value INSIDE that bracket, so
    the exact rate at any TH level is computable rather than folklore. The
    table and the lookup are ported verbatim from the server's own drop roll --
    see M.TH_TABLE below, whose rows are TH 0-14 and whose columns are the
    seven brackets.

    THE UNITS ARE THE TRAP. The lookup works out of 10000 and the caller hands
    it `DropRate * 10`, so a stored `r = 150` enters as 1500 and comes back
    4500 at TH4 -- 45%. Every entry point here takes the STORED rate (out of
    1000, the units the rest of this file speaks) and does the times-ten
    itself, so no caller has to remember which scale it is holding.

    FOUR RULES, EACH ONE A WAY A TH READOUT COULD LIE:

    1. For an UNGROUPED row, TH applies to that row's own rate.
    2. For a GROUPED row, TH applies to the GROUP's rate (`gr`) only.
    3. TH NEVER touches which member of a group wins -- that is a pure weighted
       roll on `r`, so the shares this file already prints are untouched by it
       and still sum the same after TH is applied to the group rate.
    4. A rate already at 10000 SHORT-CIRCUITS unchanged, so TH is worth exactly
       nothing on a group that always drops. That is the verdict the feature
       exists for: Ochiudo's Kote sits at a 10% share inside a `gr = 1000`
       group, and no amount of TH moves it -- saying so in WORDS is what saves
       a player a gear set, which an unchanged number never would.

    THE SAME TABLE READ BACKWARDS (issue #157) is what answers "who drops
    Leaping Boots?" -- the Compendium's third filter mode. The join above runs
    NM -> pool -> rows; the reverse index runs item -> pools, and `nmlookup`
    walks the NM table for the entries carrying one of them. It is an INDEX and
    not a search: the drop table cannot change while the client runs, so the id
    half is built once. The NAME half is not part of it, for the same reason
    names are resolved lazily above -- it is retried while any id is still
    unresolved and frozen the moment every one of them answers.

    A CONSEQUENCE WORTH KNOWING BEFORE IT SURPRISES YOU: because the rate only
    SELECTS a bracket, a rate that is not one of the eight tiers does not read
    back as itself. The bracket floors are the tiers times ten (2400, 1500,
    1000, 500, 100, 50, 0), so at TH0 a tier rate is its own value -- 150 in,
    15% out -- while an off-tier rate reads at its bracket's value instead:
    the 68 shipped rows at `gr = 750` sit in the top (very common) bracket, so
    they read 24% at TH0 and 64% at TH4. That is the lookup, not a bug here,
    and the line says so rather than letting it read as "TH lowered my rate".
    Flagged for a ruling in the PR for #154.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- The generated table. A missing or old file degrades the section OFF rather
-- than erroring (the nativemp rule) -- and says so, rather than reading as
-- "this NM drops nothing" (hard rule 12: a total failure and a real absence
-- must not look identical).
M.data = try('dlac\\data\\nmdrops') or {};

-- ---------------------------------------------------------------------------
-- the server's drop types
-- ---------------------------------------------------------------------------
M.T_NORMAL  = 0;
M.T_GROUP   = 1;
M.T_STEAL   = 2;
M.T_DESPOIL = 4;

-- How a row that a kill will never give you is reached. Anything the table
-- starts carrying that this build does not know is named by its raw type and
-- kept OUT of the kill-loot list: promising a drop we cannot vouch for is the
-- expensive direction to be wrong in.
function M.takeLabel(t)
    t = tonumber(t) or 0;
    if t == M.T_STEAL   then return 'Steal';   end
    if t == M.T_DESPOIL then return 'Despoil'; end
    return 'drop type ' .. tostring(t);
end

-- ---------------------------------------------------------------------------
-- rates and tiers
-- ---------------------------------------------------------------------------
-- The server's own eight, out of 1000. This table is the whole vocabulary:
-- a rate that is not a key here has no tier name and must not be given one.
M.TIERS = {
    [1000] = 'always',
    [240]  = 'very common',
    [150]  = 'common',
    [100]  = 'uncommon',
    [50]   = 'rare',
    [10]   = 'very rare',
    [5]    = 'super rare',
    [1]    = 'ultra rare',
};

-- The tier name for a rate, or nil when the rate is not one of the eight.
function M.tierName(rate)
    return M.TIERS[tonumber(rate) or -1];
end

-- Rates are out of 1000.
function M.pctOf(rate)
    local r = tonumber(rate);
    if r == nil then return nil; end
    return r / 10;
end

-- Percent for READING. Whole percents at 10% and up; below that the decimals
-- are the whole point (0.5% and 0.1% are two different tiers), and a trailing
-- ".0" is noise, so "rare (5%)" reads the way the game says it rather than
-- "rare (5.0%)".
local function pctText(p)
    p = tonumber(p);
    if p == nil then return '?'; end
    if p >= 99.95 then return '100%'; end
    if p >= 10 then return string.format('%d%%', math.floor(p + 0.5)); end
    local s = string.format((p >= 1) and '%.1f' or '%.2f', p);
    if s:find('%.') ~= nil then
        s = s:gsub('0+$', '');
        s = s:gsub('%.$', '');
    end
    -- A real share that rounds to nothing is said as "smaller than we print",
    -- never as "0%" -- which reads as "impossible".
    if p > 0 and (tonumber(s) or 0) == 0 then return '<0.01%'; end
    return s .. '%';
end
M.pctText = pctText;

-- "common (15%)" for one of the eight, "25%" for anything else. nil when
-- there is no rate to state at all (the r = 0 steal rows).
function M.rateText(rate)
    local r = tonumber(rate);
    if r == nil or r <= 0 then return nil; end
    local t = M.tierName(r);
    if t ~= nil then return string.format('%s (%s)', t, pctText(M.pctOf(r))); end
    return pctText(M.pctOf(r));
end

-- ---------------------------------------------------------------------------
-- Treasure Hunter -- the server's own bracket lookup, ported
-- ---------------------------------------------------------------------------
-- Rows are TH level 0-14; columns are the seven rarity brackets in order
-- (very common, common, uncommon, rare, very rare, super rare, ultra rare).
-- Verbatim from the server -- including the 6666 on row 5, which is left as it
-- is found rather than tidied into 6650: this table is a copy, not a design.
M.TH_TABLE = {
    [0]  = { 2400, 1500, 1000,  500,  100,  50,  10 },
    [1]  = { 4800, 3000, 1200,  600,  150,  75,  20 },
    [2]  = { 5600, 4000, 1500,  700,  200, 100,  30 },
    [3]  = { 6000, 4250, 1650,  750,  225, 120,  35 },
    [4]  = { 6400, 4500, 1800,  800,  250, 140,  40 },
    [5]  = { 6666, 4750, 1900,  850,  300, 160,  45 },
    [6]  = { 6800, 5000, 2000,  900,  350, 180,  50 },
    [7]  = { 6900, 5250, 2100,  950,  400, 200,  60 },
    [8]  = { 7050, 5500, 2250, 1050,  475, 230,  70 },
    [9]  = { 7200, 5750, 2400, 1150,  550, 260,  80 },
    [10] = { 7350, 6000, 2650, 1250,  650, 300,  90 },
    [11] = { 7400, 6250, 2800, 1350,  750, 350, 100 },
    [12] = { 7600, 6500, 2950, 1550,  825, 400, 115 },
    [13] = { 7800, 6750, 3100, 1750,  900, 450, 130 },
    [14] = { 8000, 7000, 3250, 2000, 1000, 500, 150 },
};

M.TH_MAX  = 14;      -- the last row; the server clamps to it
M.TH_FULL = 10000;   -- the units the lookup works in (a stored rate times ten)

-- The bracket a rate falls in is the FIRST of these it is >=. They are the
-- eight named tiers times ten with `always` dropped off the top, which is why
-- the bracket a drop sits in is the tier name this file already prints beside
-- it -- no second vocabulary had to be invented for the columns.
M.TH_BRACKETS = { 2400, 1500, 1000, 500, 100, 50, 0 };
M.TH_BRACKET_TIER = {
    'very common', 'common', 'uncommon', 'rare', 'very rare', 'super rare', 'ultra rare',
};

-- The TH level, held to what the table can answer for. Returns the clamped
-- level AND whether it had to move, so a caller can say what it did rather
-- than silently answering a different question than it was asked.
function M.clampTH(level)
    local n = tonumber(level);
    if n == nil then return 0, false; end
    n = math.floor(n);
    if n < 0 then return 0, true; end
    if n > M.TH_MAX then return M.TH_MAX, true; end
    return n, false;
end

-- Which bracket a rate (out of 10000) sits in: the first threshold it reaches.
function M.thBracket(rate)
    local r = tonumber(rate) or 0;
    for i = 1, #M.TH_BRACKETS do
        if r >= M.TH_BRACKETS[i] then return i; end
    end
    return #M.TH_BRACKETS;
end

-- The server's getDropRate, out of 10000 in and out of 10000 back. The two
-- short-circuits are the whole reason the verdict is worth printing: a rate
-- already at 10000 comes back unchanged whatever the TH level, and so does a
-- rate of nothing.
function M.thRate(level, rate)
    local lvl = M.clampTH(level);
    local r = math.floor(tonumber(rate) or 0);
    if r < 0 then r = 0; end
    if r > M.TH_FULL then r = M.TH_FULL; end
    if r == M.TH_FULL then return M.TH_FULL; end
    if r == 0 then return 0; end
    local row = M.TH_TABLE[lvl];
    if type(row) ~= 'table' then return r; end
    return row[M.thBracket(r)] or r;
end

-- The same thing for the units the rest of this file speaks: a STORED rate
-- (out of 1000) in, a percentage out. The times-ten the server's caller does
-- lives here so no caller of this module has to hold two scales at once.
-- nil when there is no rate to raise at all.
function M.thPct(level, stored)
    local r = tonumber(stored);
    if r == nil or r <= 0 then return nil; end
    return M.thRate(level, r * 10) / 100;
end

-- Can ANY amount of TH move this rate? Only the two short-circuits say no --
-- every column of the table rises with the level, so a rate that is neither
-- already 100% nor absent always has somewhere to go.
function M.thHelps(stored)
    local r = tonumber(stored);
    if r == nil or r <= 0 then return false; end
    return (r * 10) < M.TH_FULL;
end

-- The rate TH is applied to for one roll (see M.rolls): an ungrouped row's OWN
-- rate, and a group's GROUP rate. NEVER a member's weight -- rule 3 in the
-- header: TH does not touch the roll that picks the winner inside a group.
function M.rollRate(block)
    if type(block) ~= 'table' then return nil; end
    if block.kind == 'group' then return tonumber(block.gr); end
    if type(block.row) == 'table' then return tonumber(block.row.r); end
    return nil;
end

-- What TH does to one roll, in the words its line will carry.
-- -> helps (boolean), text (string)
-- The `no gain` half is the point of the feature: a number that did not move
-- is indistinguishable from a number nobody applied TH to, so the reason is
-- said out loud instead.
function M.thVerdict(stored, level, isGroup)
    local lvl = M.clampTH(level);
    local r = tonumber(stored);
    if r == nil or r <= 0 then
        return false, 'nothing to raise -- the table states no rate for this roll';
    end
    if not M.thHelps(r) then
        if isGroup then
            return false, 'no gain -- the group already drops every time, and TH never picks which item in it wins';
        end
        return false, 'no gain -- it already drops every time';
    end
    local at  = M.thPct(lvl, r);
    local txt = pctText(at);
    -- An off-tier rate reads at its BRACKET's value, which can be below the
    -- rate the table states (75% sits in the top bracket: 24% at TH0, 64% at
    -- TH4). Left unsaid it reads as "TH lowered my drop rate", which is the
    -- one thing this line must never be taken for.
    local stated = M.pctOf(r);
    if stated ~= nil and at + 1e-9 < stated then
        return true, txt .. ' -- the stated rate only picks the bracket';
    end
    return true, txt;
end

-- ---------------------------------------------------------------------------
-- item names -- lazily, from the client's own resources
-- ---------------------------------------------------------------------------
M._names = {};

-- The one live read in this module. Called through M so the headless tests can
-- override it (the helmwatch seam rule).
function M._clientName(id)
    local n = nil;
    pcall(function()
        local res = AshitaCore:GetResourceManager():GetItemById(id);
        if res ~= nil and res.Name ~= nil then n = res.Name[1]; end
    end);
    if type(n) ~= 'string' or n == '' then return nil; end
    return n;
end

-- The client's name for an item id, or the id itself. Only a HIT is cached:
-- a miss is "the client could not answer yet", not "there is no such item",
-- and caching it would latch a pre-login read forever (ADR 0007).
function M.itemName(id)
    local n = tonumber(id);
    if n == nil then return 'item #?'; end
    local hit = M._names[n];
    if hit ~= nil then return hit; end
    local name = M._clientName(n);
    if name == nil then return 'item #' .. tostring(n); end
    M._names[n] = name;
    return name;
end

-- ---------------------------------------------------------------------------
-- the join
-- ---------------------------------------------------------------------------

-- The pool ids one NM entry carries, in table order and de-duplicated. An NM
-- may carry several pools (16 shipped entries do, up to nine); each is a mob
-- template with its own droplist. The same pool id listed twice is one
-- droplist, not two -- so pool ids, and only pool ids, are de-duplicated.
-- A single `pool = 500` and a `pool = { 500 }` are the same statement.
function M.poolsOf(entry)
    local out = {};
    if type(entry) ~= 'table' then return out; end
    local pools = entry.pool;
    if type(pools) == 'number' then pools = { pools }; end
    if type(pools) ~= 'table' then return out; end
    local seen = {};
    for _, p in ipairs(pools) do
        local id = tonumber(p);
        if id ~= nil and not seen[id] then
            seen[id] = true;
            out[#out + 1] = id;
        end
    end
    return out;
end

-- Every drop row for an NM, in table order, with duplicates intact. Several
-- pools CONCATENATE their rows -- see M.poolsOf for why that is one droplist
-- per pool and not one per mention.
function M.rowsFor(entry)
    local out = {};
    if type(M.data) ~= 'table' then return out; end
    for _, id in ipairs(M.poolsOf(entry)) do
        local list = M.data[id];
        if type(list) == 'table' then
            for _, r in ipairs(list) do
                if type(r) == 'table' then out[#out + 1] = r; end
            end
        end
    end
    return out;
end

-- Does this entry carry a pool id at all? A pre-2026-08-03 data file does not,
-- and that is "cannot look it up", never "it drops nothing".
function M.hasPool(entry)
    if type(entry) ~= 'table' then return false; end
    if type(entry.pool) == 'number' then return true; end
    return type(entry.pool) == 'table' and #entry.pool > 0;
end

-- ---------------------------------------------------------------------------
-- the reverse index -- "who drops Leaping Boots?" (issue #157)
-- ---------------------------------------------------------------------------
-- The join above runs NM -> pool -> rows. The by-drop filter mode runs it
-- BACKWARDS -- item -> pools, and then nmlookup walks the NM table for the
-- entries carrying one of them. That direction is an INDEX, not a search: the
-- drop table does not change while the client runs, so it is built once.
--
-- Item names deliberately are NOT part of that index. They come from the
-- client's own resources, one id at a time, and before the player is logged in
-- the client answers with nothing (ADR 0007) -- so the id half is permanent and
-- the name half is retried until it resolves.

local _pools = nil;      -- [itemId] = { poolId, ... }, ascending
local _ids   = nil;      -- every item id in the table, ascending

local function buildIndex()
    if _pools ~= nil then return; end
    _pools, _ids = {}, {};
    if type(M.data) ~= 'table' then return; end
    -- pairs() order is undefined (hard rule 8) and this index is walked to
    -- build a list a player reads, so the pool ids are sorted FIRST and the
    -- index is filled in that order. Otherwise two runs of the same search
    -- could list the same NMs in two different orders.
    local pids = {};
    for pid, list in pairs(M.data) do
        if type(list) == 'table' and tonumber(pid) ~= nil then pids[#pids + 1] = tonumber(pid); end
    end
    table.sort(pids);
    for _, pid in ipairs(pids) do
        -- The key was read back as a NUMBER above, so a table keyed by strings
        -- would index to nothing here. The shipped table is numeric-keyed; this
        -- guard is what keeps a hand-made one from erroring instead of saying
        -- it has nothing.
        for _, r in ipairs((type(M.data[pid]) == 'table') and M.data[pid] or {}) do
            local id = (type(r) == 'table') and tonumber(r.i) or nil;
            if id ~= nil then
                local into = _pools[id];
                if into == nil then
                    _pools[id] = { pid };
                    _ids[#_ids + 1] = id;
                elseif into[#into] ~= pid then
                    -- Duplicate rows in one pool are two independent ROLLS and
                    -- both matter to the drops readout -- but to "who drops
                    -- this" one pool is one answer, so only the pool is kept.
                    into[#into + 1] = pid;
                end
            end
        end
    end
    table.sort(_ids);
end

-- Every item id the drop table carries, ascending. Pure, and built once.
function M.itemIds()
    buildIndex();
    return _ids;
end

-- Which pools drop this item. {} for an id the table does not carry.
function M.poolsForItem(id)
    buildIndex();
    local n = tonumber(id);
    if n == nil then return {}; end
    return _pools[n] or {};
end

-- How long to wait before asking the client again about the ids it could not
-- name. Pre-login it can name NONE of them, and re-asking 2183 times per
-- keystroke is the difference between a search box and a stutter.
M.NAME_RETRY_S = 2.0;

local _named   = nil;    -- { { id = n, name = s }, ... }, id-ascending
local _missing = 0;      -- ids the client could not answer for last build
local _namedAt = -1e9;   -- os.clock() of that build

-- Every drop-table item the client can NAME, id-ascending: the whole source
-- for a by-drop search. A miss is never cached (ADR 0007 -- "cannot tell yet"
-- is not "no such item"), so the list is rebuilt while any id is still
-- unresolved and frozen the moment they all are.
function M.namedItems()
    if _named ~= nil and _missing == 0 then return _named; end
    local now = 0;
    pcall(function() now = os.clock(); end);
    if _named ~= nil and (now - _namedAt) < M.NAME_RETRY_S then return _named; end
    _namedAt = now;
    local out, miss = {}, 0;
    for _, id in ipairs(M.itemIds()) do
        local name = M._names[id];
        if name == nil then
            name = M._clientName(id);
            if name ~= nil then M._names[id] = name; end
        end
        if name ~= nil then
            out[#out + 1] = { id = id, name = name };
        else
            miss = miss + 1;
        end
    end
    _named, _missing = out, miss;
    return _named;
end

-- How many of the table's items the client has managed to name so far. CHEAP
-- and side-effect free -- it never triggers a resolve -- so a caller can ask
-- "did the client know anything when that answered?" without paying for the
-- sweep again. Zero means the answer above was "nothing", not "nothing drops
-- that", and those two must not be cached alike (ADR 0007).
function M.namedCount()
    return (_named ~= nil) and #_named or 0;
end

-- Drop every cached index. The data table is swapped under this module by the
-- tests and by nothing else in the game; without this a fixture would answer
-- out of the shipped table's index.
function M._resetIndex()
    _pools, _ids, _named, _missing, _namedAt = nil, nil, nil, 0, -1e9;
end

-- ---------------------------------------------------------------------------
-- rolls
-- ---------------------------------------------------------------------------
-- Rows in, ROLLS out: kill loot as a list of blocks, each one an independent
-- roll, plus the rows a kill will never give. See the header for why a group
-- is a RUN over (g, gr) and not a lookup by group id.
--   kill = { { kind = 'item', row = r },
--            { kind = 'group', g = n, gr = n, weight = n, rows = { ... } }, ... }
--   take = { { row = r, how = 'Steal' }, ... }
function M.rolls(rows)
    local kill, take = {}, {};
    local cur = nil;      -- the last group block opened; ungrouped rows pass it by
    for _, r in ipairs(rows or {}) do
        local t = tonumber(r.t) or M.T_NORMAL;
        if t == M.T_GROUP then
            if cur ~= nil and cur.g == r.g and cur.gr == r.gr then
                cur.rows[#cur.rows + 1] = r;
                cur.weight = cur.weight + (tonumber(r.r) or 0);
            else
                cur = { kind = 'group', g = r.g, gr = tonumber(r.gr),
                        weight = tonumber(r.r) or 0, rows = { r } };
                kill[#kill + 1] = cur;
            end
        elseif t == M.T_NORMAL then
            kill[#kill + 1] = { kind = 'item', row = r };
        else
            -- Steal, Despoil, or a type this build has never seen. None of them
            -- are kill loot, so none of them may reach the drops list.
            take[#take + 1] = { row = r, how = M.takeLabel(t) };
        end
    end
    return kill, take;
end

-- One item's share of its group, in percent. nil when the group carries no
-- weight at all -- a share of nothing is not a number, and is not guessed at.
function M.shareOf(block, row)
    if type(block) ~= 'table' or type(row) ~= 'table' then return nil; end
    local w = tonumber(block.weight);
    if w == nil or w <= 0 then return nil; end
    return (tonumber(row.r) or 0) / w * 100;
end

-- ---------------------------------------------------------------------------
-- rendering
-- ---------------------------------------------------------------------------
-- Chat is not a window: the biggest shipped pool holds 100 rows and one group
-- of 36, which nobody wants a hundred lines of. Members are PACKED onto shared
-- lines under a width budget, and the two caps below are the backstop. Both
-- say out loud what they left out -- a silent cap reads as "that is all of it",
-- which is the one thing a drop readout must never imply.
-- Sized against the shipped table rather than guessed: the deepest NM in it
-- (Jormungand) rolls 28 times, so MAX_ROLLS never fires today and is purely a
-- backstop against a future table; MAX_GROUP does fire, on the 26 groups with
-- more than twelve members, where the alternative was three 36-item groups
-- costing twenty-four lines on one Abyssea NM.
M.WRAP      = 108;   -- characters before a packed line wraps
M.MAX_GROUP = 12;    -- members shown inside one group
M.MAX_ROLLS = 32;    -- rolls shown in the kill-loot section

local function pack(head, parts, cont, width)
    width = width or M.WRAP;
    if #parts == 0 then return { head }; end
    local out, cur, first = {}, head, true;
    for _, p in ipairs(parts) do
        if first then
            cur = cur .. ' ' .. p;
            first = false;
        elseif (#cur + #p + 2) > width then
            out[#out + 1] = cur .. ',';
            cur = cont .. p;
        else
            cur = cur .. ', ' .. p;
        end
    end
    out[#out + 1] = cur;
    return out;
end
M._pack = pack;

-- What a chosen TH level does to one roll, hung off the end of its line.
-- Empty when no level was asked for: TH figures are opt-in, so the default
-- readout is the one #153 shipped plus a single verdict line.
local function thTail(stored, th, isGroup)
    if th == nil then return ''; end
    local _, txt = M.thVerdict(stored, th, isGroup);
    return string.format('  |  TH%d %s', M.clampTH(th), txt);
end

-- One ungrouped roll: the item and what the server calls its rate.
local function itemLine(row, indent, th)
    local txt = M.rateText(row.r);
    if txt == nil then return indent .. M.itemName(row.i) .. thTail(row.r, th, false); end
    return string.format('%s%s -- %s%s', indent, M.itemName(row.i), txt, thTail(row.r, th, false));
end

-- One grouped roll. A group of ONE is rendered as a plain drop at the GROUP's
-- rate, because that is exactly its chance -- there is nothing for it to be
-- "one of", and 22 shipped groups are that shape.
local function groupLines(block, indent, cont, th)
    local n = #block.rows;
    if n == 1 then
        local only = block.rows[1];
        local txt = M.rateText(block.gr);
        -- TH still applies to the GROUP's rate here, not the member's weight:
        -- rendering a group of one as a plain drop is a presentation choice and
        -- must not become an arithmetic one.
        local tail = thTail(block.gr, th, false);
        if txt == nil then return { indent .. M.itemName(only.i) .. tail }; end
        return { string.format('%s%s -- %s%s', indent, M.itemName(only.i), txt, tail) };
    end
    local shown = (n > M.MAX_GROUP) and M.MAX_GROUP or n;
    local parts = {};
    for k = 1, shown do
        local row = block.rows[k];
        local share = M.shareOf(block, row);
        if share == nil then
            parts[#parts + 1] = M.itemName(row.i);
        else
            parts[#parts + 1] = string.format('%s %s', M.itemName(row.i), pctText(share));
        end
    end
    if shown < n then
        local rest = 0;
        for k = shown + 1, n do rest = rest + (tonumber(block.rows[k].r) or 0); end
        local restShare = M.shareOf(block, { r = rest });
        if restShare == nil then
            parts[#parts + 1] = string.format('+%d more', n - shown);
        else
            parts[#parts + 1] = string.format('+%d more sharing %s', n - shown, pctText(restShare));
        end
    end
    local rate = M.rateText(block.gr) or 'rate not stated';
    local lines = pack(string.format('%sone of these, %s:', indent, rate), parts, cont);
    -- A real group gets its TH verdict on its OWN line rather than hung off the
    -- head, because the head is where the members are packed and the verdict is
    -- the half of this that a player acts on. It talks about the GROUP's roll
    -- and says the shares are untouched, so the two numbers on screen -- the
    -- group's rate and each member's share -- cannot be read as one.
    if th ~= nil then
        local helps, txt = M.thVerdict(block.gr, th, true);
        if helps then
            -- A semicolon, not a second dash: the verdict text may already
            -- carry a `-- ...` clause of its own.
            lines[#lines + 1] = string.format('%sTH%d: the group rolls at %s; the shares above are unchanged',
                cont, M.clampTH(th), txt);
        else
            lines[#lines + 1] = string.format('%sTH%d: %s', cont, M.clampTH(th), txt);
        end
    end
    return lines;
end

-- The whole NM's TH verdict, as one line. It is printed WITHOUT a level being
-- asked for, because "do not bother bringing TH here" is the answer a player
-- needs before they know to ask -- and withheld once a level IS asked and every
-- roll climbs, where the per-line figures already say it better.
-- -> a line, or nil
local function thSummaryLine(kill, th, name)
    local rolls, helped, capped, unrated, grouped = 0, 0, 0, 0, false;
    for _, b in ipairs(kill or {}) do
        rolls = rolls + 1;
        if b.kind == 'group' and #b.rows > 1 then grouped = true; end
        local rate = M.rollRate(b);
        if M.thHelps(rate) then
            helped = helped + 1;
        elseif (tonumber(rate) or 0) > 0 then
            capped = capped + 1;
        else
            unrated = unrated + 1;
        end
    end
    if rolls == 0 then return nil; end

    if helped == 0 then
        local why;
        if unrated == 0 then
            why = (rolls == 1) and 'that roll already drops every time'
                                or 'every roll here already drops every time';
        elseif capped == 0 then
            why = 'the table states no rate for any of these rolls';
        else
            why = 'no roll here can be lifted at any TH level';
        end
        if grouped then
            why = why .. ', and TH never picks which item inside a group wins';
        end
        return '  TH: nothing to gain here -- ' .. why .. '.';
    end

    local how;
    if helped == rolls then
        how = (rolls == 1) and 'that roll climbs with it' or 'every roll here climbs with it';
    else
        how = string.format('%d of %d rolls climb with it', helped, rolls);
    end

    if th == nil then
        return string.format('  TH: %s -- "/dl nm %s th4" for the rate at any TH level (0-%d).',
            how, name or '<name>', M.TH_MAX);
    end
    -- A level was asked for: every roll now carries its own number, so the only
    -- thing left to say is which of them no TH level will ever move -- and that
    -- claim is about TH itself, not about the level asked for, so it does not
    -- wear one.
    if helped == rolls then return nil; end
    local stuck = rolls - helped;
    local why;
    if unrated == 0 then
        why = (stuck == 1) and 'it already drops every time' or 'they already drop every time';
    elseif capped == 0 then
        why = 'the table states no rate for ' .. ((stuck == 1) and 'it' or 'them');
    else
        why = 'either they already drop every time or the table states no rate for them';
    end
    return string.format('  TH: %d of the %d rolls above cannot be lifted by any TH level -- %s.',
        stuck, rolls, why);
end

-- The whole drops readout for one NM, ready for nmlookup to print. Pure apart
-- from the item-name resolve. `th` is the TH level the player asked to see the
-- rates at; nil means they asked for none, and then only the one-line verdict
-- is added -- a TH figure on every line of every lookup is noise for the four
-- jobs in five that cannot bring any.
function M.lines(entry, th)
    local out = {};
    if type(entry) ~= 'table' then return out; end
    if th ~= nil then th = M.clampTH(th); end

    -- Three absences, and they must not look alike.
    if type(M.data) ~= 'table' or next(M.data) == nil then
        out[#out + 1] = '  drops: the drop table (data/nmdrops.lua) is missing or empty.';
        return out;
    end
    if not M.hasPool(entry) then
        out[#out + 1] = '  drops: this NM table carries no pool id, so its drops cannot be looked up -- the data file predates them.';
        return out;
    end
    local rows = M.rowsFor(entry);
    if #rows == 0 then
        out[#out + 1] = '  drops: nothing in the drop table for this one.';
        return out;
    end

    local kill, take = M.rolls(rows);
    local indent, cont = '    ', '      ';

    if #kill > 0 then
        local grouped = false;
        for _, b in ipairs(kill) do
            if b.kind == 'group' and #b.rows > 1 then grouped = true; end
        end
        -- "rolls, each rolled on its own" is what tells a reader why the same
        -- item can appear twice. With one roll there is nothing to separate.
        if #kill == 1 then
            out[#out + 1] = '  drops -- 1 roll:';
        else
            out[#out + 1] = string.format('  drops -- %d rolls, each rolled on its own:', #kill);
        end
        if grouped then
            out[#out + 1] = '  (a group rolls once, then ONE item in it wins by weight -- the % is that item\'s share of the group)';
        end
        -- The mental model, said once, and only when TH figures are on screen
        -- to need it: without it a rate that reads lower than the table's own
        -- (an off-tier rate at its bracket's value) looks like a bug.
        if th ~= nil then
            out[#out + 1] = '  (TH is a lookup, not a multiplier -- the rate picks a rarity bracket, the TH level picks the value in it)';
        end
        local shown = (#kill > M.MAX_ROLLS) and M.MAX_ROLLS or #kill;
        for k = 1, shown do
            local b = kill[k];
            if b.kind == 'group' then
                for _, line in ipairs(groupLines(b, indent, cont, th)) do out[#out + 1] = line; end
            else
                out[#out + 1] = itemLine(b.row, indent, th);
            end
        end
        if shown < #kill then
            out[#out + 1] = string.format('%s... and %d more %s not shown -- the chat readout stops at %d.',
                indent, #kill - shown, (#kill - shown == 1) and 'roll' or 'rolls', M.MAX_ROLLS);
        end
        local verdict = thSummaryLine(kill, th, entry.n);
        if verdict ~= nil then out[#out + 1] = verdict; end
    else
        -- Five shipped pools are Steal and Despoil and nothing else. Printing
        -- only the section below would leave the drops question unanswered,
        -- and a silence reads as "we did not look" (hard rule 12).
        out[#out + 1] = '  drops: nothing a kill gives -- this one only has what is below.';
    end

    if #take > 0 then
        local hows, seen = {}, {};
        for _, tk in ipairs(take) do
            if not seen[tk.how] then seen[tk.how] = true; hows[#hows + 1] = tk.how; end
        end
        out[#out + 1] = string.format('  not kill loot -- %s only, a kill never gives these:',
            table.concat(hows, ' / '));
        -- No TH figures down here, and that absence is stated rather than left
        -- to be read as "TH does nothing for these" (hard rule 12). The bracket
        -- lookup ported above is the KILL's drop roll; what Steal and Despoil
        -- roll is a different question this module has no server data for.
        if th ~= nil then
            out[#out + 1] = '  (no TH figures here -- the lookup above is the kill\'s drop roll, which is not where these come from)';
        end
        for _, tk in ipairs(take) do
            local txt = M.rateText(tk.row.r);
            if txt == nil then
                out[#out + 1] = string.format('%s%s (%s)', indent, M.itemName(tk.row.i), tk.how);
            else
                out[#out + 1] = string.format('%s%s (%s) -- %s', indent, M.itemName(tk.row.i), tk.how, txt);
            end
        end
    end

    return out;
end

return M;
