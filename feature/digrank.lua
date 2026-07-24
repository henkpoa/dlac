-- digrank.lua -- PURE chocobo dig-rank logic (no Ashita, no imgui). The rank
-- half of the digging guide (issue #97, PRD #93, docs/design/chocobo-dig.md):
-- the dig rank is masked out of the client entirely, so dlac assembles it from
-- three stacked sources and labels each one honestly.
--
--   manual  -- a rank the player picks in the guide (the seed, persisted).
--   ratchet -- a one-way floor raised whenever you dig an item that needs a
--              higher rank than assumed ("Obtained: <item>" -> its requirement).
--   server  -- a live GetCraftSkill(11) read; the server blanks the digging
--              skill to 0xFFFF, so this is nil forever UNLESS a build unmasks it,
--              in which case it is the exact truth and wins.
--
-- Only the server source is EXACT; manual and ratchet are estimates (the ratchet
-- is a proven lower bound -- "you are AT LEAST this rank"). The consumer (the
-- tab views) hard-locks over-rank items only against an exact rank and merely
-- dims them against an estimate, so the UI never claims something is impossible
-- when it might not be.
--
-- Everything here is a pure function of its arguments (the digdata table is
-- passed in, never required) so it is headless-testable -- see tests DR* in
-- tests/run_tests.lua. chocowatch owns the Ashita glue (the live skill read, the
-- chat hook, persistence); this module is the brain.
--
-- Lua 5.1 / LuaJIT compatible (no bit library, no 5.3 operators).

local M = {};

-- The dig-rank ladder is 0..10 (Amateur .. Expert -- the CatsEye craftRank range
-- for Digging), matching the server's first-dig zone cooldown
-- clamp(60 - 5*rank, 10, 60) seconds: Amateur(0)=60s .. Adept(8)=20s,
-- Veteran(9)=15s, Expert(10)=10s (the 10s floor makes rank 10 the effective
-- max). The authoritative labels live in data/digdata.lua `ranks`; this is the
-- fail-soft fallback for when that table is absent.
M.MIN_RANK, M.MAX_RANK = 0, 10;
M.RANKS = {
    [0] = 'Amateur', [1] = 'Recruit', [2] = 'Initiate', [3] = 'Novice',
    [4] = 'Apprentice', [5] = 'Journeyman', [6] = 'Craftsman', [7] = 'Artisan',
    [8] = 'Adept', [9] = 'Veteran', [10] = 'Expert',
};

-- The server's mask sentinel: GetCraftSkill(11) returns 0xFFFF for the blanked
-- digging skill, decoding to skill 255 / rank 31 (see dlacprobe/dig.lua, #96).
M.MASK_WORD = 0xFFFF;

-- The three source keys and their honest one-word display labels (issue #97 AC:
-- "manual / >= from digs / reported by server").
M.SOURCE_LABEL = {
    manual  = 'manual',
    ratchet = '>= from digs',
    server  = 'reported by server',
};

-- Clamp any value to the 0..10 ladder; a nil / non-number floors to Amateur (0).
function M.clamp(r)
    local v = tonumber(r);
    if v == nil then return M.MIN_RANK; end
    v = math.floor(v + 0.5);
    if v < M.MIN_RANK then return M.MIN_RANK; end
    if v > M.MAX_RANK then return M.MAX_RANK; end
    return v;
end

-- The rank label for an index: the passed-in ladder (digdata.ranks) wins, then
-- the fallback above, then a plain "rank N".
function M.label(rank, ranks)
    local r = M.clamp(rank);
    if type(ranks) == 'table' and ranks[r] ~= nil then return tostring(ranks[r]); end
    if M.RANKS[r] ~= nil then return M.RANKS[r]; end
    return 'rank ' .. r;
end

-- The ratchet: a NEW floor is the higher of the current floor and the just-dug
-- requirement, clamped. One-way BY CONSTRUCTION -- a lower requirement (a lucky
-- low-rank find) never lowers the floor. `req` nil (a non-diggable "Obtained:"
-- line) leaves the floor untouched.
function M.ratchet(floor, req)
    local f = M.clamp(floor);
    local r = tonumber(req);
    if r == nil then return f; end
    r = M.clamp(r);
    return (r > f) and r or f;
end

-- Interpret a live GetCraftSkill(11) raw word into an exact dig rank, or nil when
-- the read is masked / not a real dig rank. The decode matches the probe
-- (dlacprobe/dig.lua P.decodeSkillWord): the rank is the low 5 bits (raw % 32).
-- A masked read (0xFFFF -> rank 31) and any out-of-ladder value both yield nil,
-- so a masked build never mistakes the sentinel for a real rank.
function M.serverRank(rawWord)
    local v = tonumber(rawWord);
    if v == nil then return nil; end
    if v == M.MASK_WORD then return nil; end
    local rank = v % 32;
    if rank < M.MIN_RANK or rank > M.MAX_RANK then return nil; end
    return rank;
end

-- Strip FFXI inline chat control/colour codes from a chat string. A live dig
-- line can wrap the item in colour tags -- 0x1E / 0x1F followed by a one-byte
-- palette index -- or carry stray control bytes; the shipped data names are
-- plain ASCII, so a code-laden capture would BOTH fail the rank lookup (the
-- ratchet silently never fires) and print garbage in the "raised by digging X"
-- line. Remove the 2-byte colour tags first, then any residual control byte
-- (incl. a lone 0x7F). LuaJIT/5.1-compatible patterns.
local function stripCodes(s)
    if type(s) ~= 'string' then return s; end
    s = s:gsub('[\30\31].', '');   -- colour tag (0x1E/0x1F) + its 1-byte param
    s = s:gsub('%c', '');          -- any other control byte
    return s;
end
M._stripCodes = stripCodes;   -- test seam

-- Normalise an item name for a case/space/period-insensitive compare (the chat
-- line may arrive as "Obtained: Handful of Wind Crystals." with the period, and
-- may carry inline colour codes -- stripped here so the compare is code-blind).
local function norm(s)
    if type(s) ~= 'string' then return ''; end
    s = stripCodes(s):lower():gsub('%.%s*$', ''):gsub('^%s+', ''):gsub('%s+$', '');
    return s;
end
M._norm = norm;   -- test seam

-- Parse a dig "Obtained: <item>" chat line -> the item name (trimmed of a
-- trailing period), or nil for any other line. Colour/control codes are stripped
-- off the whole line FIRST so the name is clean wherever the codes sit (around
-- the name or after the period). Same shape the probe and the hgather addon key
-- off (issue #97: "the same channel hgather uses").
function M.parseObtained(line)
    if type(line) ~= 'string' then return nil; end
    line = stripCodes(line);
    local item = line:match('[Oo]btained:%s*(.-)%.?%s*$');
    if item == nil or item == '' then return nil; end
    return item;
end

-- Look an obtained item up in the shipped dig data and return its dig-rank
-- REQUIREMENT -- the MINIMUM requirement across every zone/pool it drops from
-- (the easiest source gates the ratchet: a pull proves you can dig it where it
-- is cheapest). nil = the item is not diggable in the data, so it never
-- ratchets. Fail-soft: a nil db (data absent) yields nil. `db` is passed in
-- (never required) so this stays pure.
function M.itemRequirement(name, db)
    if db == nil or type(db.zones) ~= 'table' then return nil; end
    local want = norm(name);
    if want == '' then return nil; end
    local best = nil;
    for _, z in pairs(db.zones) do
        for _, list in pairs((type(z) == 'table' and z.pools) or {}) do
            for _, it in ipairs(list) do
                if norm(it.n) == want then
                    local req = M.clamp(it.rank);
                    if best == nil or req < best then best = req; end
                end
            end
        end
    end
    return best;
end

-- Resolve the effective rank from the three stacked sources. `server` is the
-- exact rank (nil unless a build unmasked it); `floor` is the ratchet floor;
-- `manual` is the player's dropdown seed. Precedence: server (exact) beats a
-- ratchet floor above the manual pick beats the manual pick.
--
-- Returns { rank, source, exact, label, sourceLabel }:
--   rank        -- the 0..10 effective rank the guide uses.
--   source      -- 'server' | 'ratchet' | 'manual'.
--   exact       -- true ONLY for a server (measured) rank; false for estimates.
--   label       -- the rank's ladder label (via ranks).
--   sourceLabel -- the honest one-word source label (SOURCE_LABEL[source]).
function M.resolve(manual, floor, server, ranks)
    local m = M.clamp(manual);
    local f = M.clamp(floor);
    local rank, source;
    if server ~= nil then
        rank, source = M.clamp(server), 'server';
    elseif f > m then
        rank, source = f, 'ratchet';
    else
        rank, source = m, 'manual';
    end
    return {
        rank = rank,
        source = source,
        exact = (source == 'server'),
        label = M.label(rank, ranks),
        sourceLabel = M.SOURCE_LABEL[source],
    };
end

-- The grey-out verdict for an item of dig-rank requirement `req` given a resolved
-- rank state (or a bare rank number). This is the ONE place the "never lie" rule
-- lives (issue #97): an over-rank item is HARD-locked only against a measured
-- EXACT rank; against an estimate it is merely DIMMED (the panel adds the "needs
-- X, you're at least Y" reason). Returns:
--   'ok'     -- reachable (requirement <= rank).
--   'locked' -- over an exact rank (truly unreachable -- hard grey).
--   'dimmed' -- over an estimate (maybe reachable -- soft grey with a reason).
function M.gate(req, rankState)
    local r = tonumber(req);
    local rank = (type(rankState) == 'table') and M.clamp(rankState.rank) or M.clamp(rankState);
    if r == nil or r <= rank then return 'ok'; end
    local exact = (type(rankState) == 'table') and (rankState.exact == true);
    return exact and 'locked' or 'dimmed';
end

-- ---------------------------------------------------------------------------
-- Timing-based rank detection (issue #100). The rank is masked, but the server
-- gates the FIRST dig after a zone-in until clamp(60 - 5*rank, 10, 60) seconds
-- (logic.lua checkDiggingCooldowns), so the delay from the zone-in to the first
-- COMPLETED dig reveals the exact rank. Cooldown-rejected digs cost no Gysahl
-- Green, so it is observable for free. dlac watches it passively (chocowatch);
-- these are the pure helpers. Skill never deranks, so the caller feeds the read
-- into the one-way ratchet floor and stops once it reaches MAX_RANK.
-- ---------------------------------------------------------------------------

-- Classify a dig chat line -> (tag, item), tag one of
-- 'obtained' | 'nothing' | 'ease' | 'wait', or nil for a non-dig line.
--   obtained -> a completed dig that yielded an item (item name captured)
--   nothing  -> a completed dig that found nothing (the cooldown HAD elapsed)
--   ease     -> a completed dig phrased "with ease"
--   wait     -> a free cooldown reject (dug too soon; no green spent)
-- 'obtained'/'nothing'/'ease' are COMPLETED digs (see M.isCompletedDig) -- their
-- delay since zone-in feeds the timing read. Mirrors the field-proven probe
-- classifier (dlacprobe/dig.lua P.classifyDigText, issue #96).
function M.classifyDigLine(line)
    if type(line) ~= 'string' then return nil; end
    local s = line:lower();
    if s:find('wait', 1, true) and (s:find('longer', 1, true) or s:find('little while', 1, true)) then
        return 'wait';
    end
    local item = M.parseObtained(line);
    if item ~= nil then return 'obtained', item; end
    if s:find('with ease', 1, true) then return 'ease'; end
    if s:find('find nothing', 1, true) then return 'nothing'; end
    return nil;
end

-- Is this tag a completed dig (the cooldown had elapsed) vs a free reject / non-
-- dig line? Only completed digs carry a usable first-dig timing.
function M.isCompletedDig(tag)
    return tag == 'obtained' or tag == 'nothing' or tag == 'ease';
end

-- Invert a first-dig delay (seconds from zone-in to the first COMPLETED dig)
-- into the dig rank. The server gates the first dig until clamp(60 - 5*rank, 10,
-- 60)s, and network lag + spam-reaction only ever make the OBSERVED dig LATER
-- than the true cooldown, never earlier. So FLOOR the delay into its 5s rung
-- (rank = the largest rung <= threshold) -- never ROUND, which would drop a
-- lagged Expert into Veteran (Henrik, field 2026-07-24: 10s Expert measured
-- ~13s rounded down to Veteran). Brackets: 10-14.99s -> Expert(10), 15-19.99 ->
-- Veteran(9), 20-24.99 -> Adept(8) ... 55-59.99 -> Recruit(1), 60+ -> Amateur(0).
-- rank = 12 - floor(t/5), clamped: a sub-10s read (rare, low lag) still floors to
-- Expert; a very late dig reads a low rank and, being a ratchet input, never
-- lowers anything. The only failure mode is under-reading by one rung per full
-- 5s of lag -- harmless (never over-claims). nil for a non-number / <=0 delay.
function M.rankFromZoneTiming(threshold)
    local t = tonumber(threshold);
    if t == nil or t <= 0 then return nil; end
    return M.clamp(12 - math.floor(t / 5));
end

return M;
