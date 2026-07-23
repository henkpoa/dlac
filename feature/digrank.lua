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

-- The dig-rank ladder is 0..8 (Amateur .. Adept), matching the server's
-- first-dig timing bracket (60 - 5*rank seconds). The authoritative labels live
-- in data/digdata.lua `ranks`; this is the fail-soft fallback for when that
-- table is absent. PROPOSED player-facing names -- pending maintainer sign-off.
M.MIN_RANK, M.MAX_RANK = 0, 8;
M.RANKS = {
    [0] = 'Amateur', [1] = 'Recruit', [2] = 'Initiate', [3] = 'Novice',
    [4] = 'Apprentice', [5] = 'Journeyman', [6] = 'Craftsman', [7] = 'Artisan',
    [8] = 'Adept',
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

-- Clamp any value to the 0..8 ladder; a nil / non-number floors to Amateur (0).
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

-- Normalise an item name for a case/space/period-insensitive compare (the chat
-- line may arrive as "Obtained: Handful of Wind Crystals." with the period).
local function norm(s)
    if type(s) ~= 'string' then return ''; end
    s = s:lower():gsub('%.%s*$', ''):gsub('^%s+', ''):gsub('%s+$', '');
    return s;
end
M._norm = norm;   -- test seam

-- Parse a dig "Obtained: <item>" chat line -> the item name (trimmed of a
-- trailing period), or nil for any other line. Same shape the probe and the
-- hgather addon key off (issue #97: "the same channel hgather uses").
function M.parseObtained(line)
    if type(line) ~= 'string' then return nil; end
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
--   rank        -- the 0..8 effective rank the guide uses.
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

return M;
