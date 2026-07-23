-- digcalc.lua -- PURE chocobo-digging odds math + digdata queries (no Ashita,
-- no imgui). The brain of the digging guide (docs/design/chocobo-dig.md, PRD
-- #93 / issue #94): given the shipped dig data, a player's dig rank and the
-- current moon multiplier, it prices every pool -- the per-item qualify
-- probability, the pool success, the exact per-item per-dig probability (the
-- pick-one-of-pool step), and the two honest display values plus the combined
-- general dig-success figure. Everything here is headless-testable; the future
-- watcher/panel slices provide the live inputs (player rank, moon) and render.
--
-- The formula (PRD #93, encodes the decision precisely):
--   mu   = 1.5 - |moonPhase - 50| / 50           -- 0.5 best (new/full) .. 1.5 worst (half)
--   q_i  = min(1, weight_i / (1000 * mu))         -- qualify prob; 0 if rank < requirement_i
--   S    = 1 - PROD_i (1 - q_i)                    -- pool success (chance the pool yields something)
--   P_i  = q_i * INT_0^1 PROD_{j!=i}(1 - q_j + q_j*t) dt   -- exact E[1/(1+X_i)]
--   (1) On a hit = P_i / S                         -- sums to ~100% within a pool
--   (2) Per dig  = P_i                             -- sums to S
-- The polynomial integral is cheap for pool sizes <= ~10. v1 ignores the
-- DigRareAbility weight modifier (assumes standard gear) -- noted once in the
-- panel, not here.

local M = {};

-- ---------------------------------------------------------------------------
-- Database access. digdata ships with the addon (data/digdata.lua, generated
-- by tools/gen_digdata.py). Fail soft: a missing table disables the data-backed
-- queries, never errors -- the pure math below never touches it.
-- ---------------------------------------------------------------------------
local _db = nil;
function M.db()
    if _db == nil then
        local ok, d = pcall(require, 'dlac\\data\\digdata');
        _db = (ok and type(d) == 'table') and d or false;
    end
    return _db or nil;
end
function M._setDb(d) _db = d; end   -- test seam

-- The four dig pools, in the server's grant order. A single dig samples the
-- Treasure/Regular pool plus the always-granted Bore and Burrow pools (up to 3
-- items) -- the general dig-success line combines their S.
M.POOLS = { 'Treasure', 'Regular', 'Bore', 'Burrow' };

-- ---------------------------------------------------------------------------
-- The moon multiplier. moonPhase is the Vana'diel illumination percent (0 =
-- new, 100 = full, 50 = half). Best odds at new/full (mu 0.5), worst at half
-- (mu 1.5). Out-of-range input clamps to the [0,100] domain so a bad live read
-- degrades to a boundary value rather than a negative multiplier.
-- ---------------------------------------------------------------------------
function M.moonMult(moonPhase)
    local p = tonumber(moonPhase) or 50;
    if p < 0 then p = 0; elseif p > 100 then p = 100; end
    return 1.5 - math.abs(p - 50) / 50;
end

-- The qualify probability for one item at moon multiplier mu:
--   q = min(1, weight / (1000 * mu)).
-- A non-positive weight or mu yields 0 (an item that can never qualify).
function M.qualify(weight, mu)
    local w = tonumber(weight) or 0;
    local m = tonumber(mu) or 0;
    if w <= 0 or m <= 0 then return 0; end
    local q = w / (1000 * m);
    if q > 1 then return 1; end
    if q < 0 then return 0; end
    return q;
end

-- INT_0^1 PROD_j (a_j + b_j*t) dt over a list of linear factors {a, b}.
-- Multiply the factors into a polynomial (coefficient convolution), then
-- integrate term by term: INT_0^1 sum c_k t^k dt = sum c_k / (k+1). Degree is
-- one per factor, so this is O(n^2) in the pool size -- trivial for <= ~10.
local function integrateLinearProduct(factors)
    local coeffs = { 1 };            -- the constant polynomial 1
    for _, f in ipairs(factors) do
        local a, b = f[1], f[2];
        local next = {};
        for k = 0, #coeffs do next[k + 1] = 0; end   -- degree grows by 1
        for k = 1, #coeffs do
            local c = coeffs[k];
            next[k]     = next[k] + c * a;            -- t^(k-1) * a
            next[k + 1] = next[k + 1] + c * b;        -- t^(k-1) * b*t
        end
        coeffs = next;
    end
    local sum = 0;
    for k = 1, #coeffs do
        sum = sum + coeffs[k] / k;   -- coeffs[k] is the t^(k-1) term -> /((k-1)+1) = /k
    end
    return sum;
end

-- Price one pool for a player rank + moon multiplier. `pool` is a list of item
-- records { id, n, w, rank } (w = weight, rank = rank requirement; short keys,
-- see data/digdata.lua). Returns:
--   { items = { { id, n, w, rank, q, P, onHit, perDig, locked }, ... },
--     S = pool success, n = active-item count }
-- Items whose rank requirement exceeds playerRank are LOCKED: q = 0, P = 0, and
-- they fall out of every product cleanly (factor (1 - 0 + 0*t) = 1), so the
-- surviving items' shares reshape exactly.
function M.poolOdds(pool, playerRank, mu)
    pool = pool or {};
    local rank = tonumber(playerRank) or 0;
    local m = tonumber(mu);
    if m == nil then m = 1; end

    -- qualify probabilities (locked items -> 0)
    local qs = {};
    local items = {};
    for i, it in ipairs(pool) do
        local req = tonumber(it.rank) or 0;
        local locked = rank < req;
        local q = locked and 0 or M.qualify(it.w, m);
        qs[i] = q;
        items[i] = {
            id = it.id, n = it.n, w = it.w, rank = req,
            q = q, locked = locked,
        };
    end

    -- pool success S = 1 - PROD (1 - q)
    local prodMiss = 1;
    for _, q in ipairs(qs) do prodMiss = prodMiss * (1 - q); end
    local S = 1 - prodMiss;

    -- per-item P_i = q_i * INT_0^1 PROD_{j!=i}(1 - q_j + q_j*t) dt
    local activeCount = 0;
    for i, it in ipairs(items) do
        if qs[i] > 0 then activeCount = activeCount + 1; end
        local P;
        if qs[i] <= 0 then
            P = 0;
        else
            local factors = {};
            for j, qj in ipairs(qs) do
                if j ~= i then factors[#factors + 1] = { 1 - qj, qj }; end
            end
            P = qs[i] * integrateLinearProduct(factors);
        end
        it.P = P;
        it.perDig = P;                                  -- (2) absolute per-dig chance
        it.onHit = (S > 0) and (P / S) or 0;            -- (1) share of a successful pull
    end

    return { items = items, S = S, n = activeCount };
end

-- The combined general dig-success across a set of pools at one rank + moon:
-- each pool succeeds independently, so the chance a dig yields at least one item
-- is 1 - PROD_pools (1 - S_pool). `pools` is a list of pool item-lists.
function M.digSuccess(pools, playerRank, mu)
    local prodMiss = 1;
    for _, pool in ipairs(pools or {}) do
        local r = M.poolOdds(pool, playerRank, mu);
        prodMiss = prodMiss * (1 - r.S);
    end
    return 1 - prodMiss;
end

-- ---------------------------------------------------------------------------
-- Data-backed accessors over the shipped table. All fail soft (empty result
-- when digdata is absent).
-- ---------------------------------------------------------------------------

-- Every enabled zone id, sorted. Empty when the table is missing.
function M.zoneIds()
    local db = M.db(); if db == nil then return {}; end
    local out = {};
    for id in pairs(db.zones or {}) do out[#out + 1] = id; end
    table.sort(out);
    return out;
end

-- Every enabled zone as { { id, n }, ... }, sorted by NAME -- the by-area tab's
-- zone-picker source (issue #98). Empty when the table is missing (fail soft).
function M.zones()
    local db = M.db(); if db == nil then return {}; end
    local out = {};
    for id, z in pairs(db.zones or {}) do
        out[#out + 1] = { id = id, n = (type(z) == 'table' and z.n) or ('Zone ' .. tostring(id)) };
    end
    table.sort(out, function(a, b) return tostring(a.n) < tostring(b.n); end);
    return out;
end

-- Full odds for one zone at a rank + moon: every pool present in the zone,
-- priced. Returns { name, pools = { { pool = 'Treasure', odds = <poolOdds> } },
-- success = combined dig-success } or nil when the zone is unknown/absent.
function M.zoneOdds(zoneId, playerRank, mu)
    local db = M.db(); if db == nil then return nil; end
    local z = (db.zones or {})[zoneId];
    if z == nil then return nil; end
    local out = { name = z.n, pools = {} };
    local poolLists = {};
    for _, name in ipairs(M.POOLS) do
        local list = (z.pools or {})[name];
        if list ~= nil then
            out.pools[#out.pools + 1] = { pool = name, odds = M.poolOdds(list, playerRank, mu) };
            poolLists[#poolLists + 1] = list;
        end
    end
    out.success = M.digSuccess(poolLists, playerRank, mu);
    return out;
end

-- The general dig-success figure for the guide scaffold (issue #97): the TYPICAL
-- per-dig success across the enabled zones at one rank + moon -- the average of
-- every enabled zone's combined dig-success. A single honest number for "how
-- productive is digging right now for me", with no zone selected yet (the by-
-- area tab prices individual zones). Returns (avg, zoneCount), or nil when the
-- table carries no zones (pending gen_digdata.py) so the panel can say so
-- plainly rather than print a fake 0.
function M.averageSuccess(playerRank, mu)
    local db = M.db(); if db == nil then return nil; end
    local sum, n = 0, 0;
    for _, z in pairs(db.zones or {}) do
        local poolLists = {};
        for _, name in ipairs(M.POOLS) do
            local list = (type(z) == 'table' and z.pools or {})[name];
            if list ~= nil then poolLists[#poolLists + 1] = list; end
        end
        if #poolLists > 0 then
            sum = sum + M.digSuccess(poolLists, playerRank, mu);
            n = n + 1;
        end
    end
    if n == 0 then return nil; end
    return sum / n, n;
end

-- The conditional Regular-pool rule tables (weather crystals, day rocks/ores +
-- gates, the elemental-ore zone set). Returns db.cond or nil.
function M.conditionals()
    local db = M.db(); if db == nil then return nil; end
    return db.cond;
end

-- Element-name aliases. The live clock (nativedata) names the lightning element
-- "Thunder"; the conditional maps (digdata cond.*.byElement) key it "Lightning".
-- Normalise so a live weather/day element resolves against the maps either way,
-- and treat the non-elemental weathers ("None"/"Clear") as no element.
local ELEMENT_ALIAS = { Thunder = 'Lightning' };
local function normElement(e)
    if type(e) ~= 'string' or e == '' or e == 'None' or e == 'Clear' then return nil; end
    return ELEMENT_ALIAS[e] or e;
end
M._normElement = normElement;   -- test seam

-- The conditional Regular-pool drops resolved against the LIVE clock for one
-- zone: the current weather's crystal (or cluster on double weather), the
-- current day's rock, and -- in an elemental-ore zone only -- the current day's
-- ore under the full gate. Each row is flagged so the panel can mark it
-- active/inactive against the clock (issue #98) and grey it against the rank.
--
-- clock = { dayElement, weatherElement, doubleWeather, moonPercent } -- any
-- field may be nil (a missing read degrades that row to inactive, never errors).
-- playerRank is a plain rank number (the caller resolves the rank state).
-- Returns a list (crystal, then rock, then ore-if-ore-zone), each:
--   { kind, id, n, chance, minRank, element, condition,
--     clockActive,  -- the weather/day/moon condition is met right now
--     rankOk,       -- playerRank >= minRank
--     active }      -- clockActive AND rankOk -- diggable in this zone NOW
-- Fail soft: a nil cond table -> empty list.
function M.conditionalDrops(zoneId, playerRank, clock)
    local cond = M.conditionals();
    if cond == nil then return {}; end
    clock = clock or {};
    local rank = tonumber(playerRank) or 0;
    local out = {};

    -- crystal / cluster: the current weather's element (any digging zone).
    local cr = cond.crystals;
    if type(cr) == 'table' then
        local el = normElement(clock.weatherElement);
        local map = (el ~= nil and type(cr.byElement) == 'table') and cr.byElement[el] or nil;
        local dbl = (clock.doubleWeather == true);
        local minRank = tonumber(cr.minRank) or 0;
        out[#out + 1] = {
            kind = 'crystal',
            id = map and (dbl and map.cluster or map.crystal) or nil,
            n = el and (el .. (dbl and ' Cluster' or ' Crystal')) or 'Weather crystal',
            chance = cr.chance, minRank = minRank, element = el,
            condition = el and (el .. ' weather up') or 'any elemental weather up',
            clockActive = (el ~= nil), rankOk = (rank >= minRank),
            active = (el ~= nil) and (rank >= minRank),
        };
    end

    -- rock: the current day's element (any digging zone, rank >= Novice).
    local rk = cond.rocks;
    if type(rk) == 'table' then
        local el = normElement(clock.dayElement);
        local map = (el ~= nil and type(rk.byElement) == 'table') and rk.byElement[el] or nil;
        local minRank = tonumber(rk.minRank) or 0;
        out[#out + 1] = {
            kind = 'rock', id = map and map.id or nil,
            n = map and map.n or 'Day rock',
            chance = rk.chance, minRank = minRank, element = el,
            condition = el and (el .. "'s day") or "the day's element",
            clockActive = (el ~= nil), rankOk = (rank >= minRank),
            active = (el ~= nil) and (rank >= minRank),
        };
    end

    -- ore: the current day's element, ORE ZONES ONLY, under the full gate
    -- (rank >= Craftsman, matching elemental weather up, moon phase in-window).
    local or_ = cond.ores;
    if type(or_) == 'table' and type(or_.zones) == 'table' and or_.zones[zoneId] == true then
        local el  = normElement(clock.dayElement);
        local wel = normElement(clock.weatherElement);
        local map = (el ~= nil and type(or_.byElement) == 'table') and or_.byElement[el] or nil;
        local minRank = tonumber(or_.minRank) or 0;
        local win = (type(or_.moonPhaseWindow) == 'table') and or_.moonPhaseWindow or {};
        local mp = tonumber(clock.moonPercent);
        local weatherOK = (not or_.requiresElementalWeather) or (el ~= nil and wel == el);
        local moonOK = (mp ~= nil and win.min ~= nil and win.max ~= nil
                        and mp >= win.min and mp <= win.max);
        local clockActive = (el ~= nil) and weatherOK and moonOK;
        out[#out + 1] = {
            kind = 'ore', id = map and map.id or nil,
            n = map and map.n or 'Elemental ore',
            chance = or_.chance, minRank = minRank, element = el,
            condition = string.format('%s day + matching weather, moon %s-%s%%',
                el or 'matching', tostring(win.min or 0), tostring(win.max or 0)),
            clockActive = clockActive, rankOk = (rank >= minRank),
            active = clockActive and (rank >= minRank),
        };
    end

    return out;
end

return M;
