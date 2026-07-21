--[[
    mpbands -- the banded-ladder core for the maxmp mode (v2 design, Henrik
    2026-07-21; docs/design/maxmp-mode.md "v2 -- the BANDED LADDER").

    The v1 engine decided each slot per dispatch against LIVE max-MP reads --
    and this client cannot provide an accurate max during gear churn (stale
    GetMPMax both directions, MP% only ±1%), which produced false-full
    over-equips, boundary dumps and a full equip<->release oscillation
    (engine v86/v87 history). Here the whole plan is PRECOMPUTED as absolute
    current-MP thresholds and the only live input is current MP -- the one
    read that is always right. Hysteresis is structural (each band's dead
    zone is its own MP difference wide), batch swaps are safe (the tick
    margin is baked into both thresholds), and a battery re-equips EARLY so
    the next recovery tick lands into its headroom.

    PURE where it counts: build/target take plain data and are headless-
    tested (MB*). The module also carries the measured-tick state
    (observe/tick) fed by the engine's 0.4s tick -- "measure, don't model":
    CatsEyeXI's hMP/refresh numbers are custom, so the margins come from
    watching the actual MP rises, with DEFAULT_TICK as the pre-measurement
    stand-in (Henrik's real endgame refresh number).
]]

local M = {};

-- ---------------------------------------------------------------------------
-- The band ladder. slots = { { slot='feet', name='Oracle\'s Pigaches',
-- low=5, high=15 }, ... } -- low = the LEAST slot MP across every set a
-- trigger rule can equip (the potency point), high = the battery. total =
-- max MP with EVERY battery worn (anchor-corrected by the caller). tick =
-- the recovery margin for the current state (standing refresh vs resting).
--
-- Returns bands ordered smallest difference first (= first OUT to potency,
-- the lowest-hanging fruit; the big battery releases last) -- EXCEPT that a
-- band whose battery carries REFRESH the potency piece lacks (s.refresh)
-- outranks the diff order entirely and sinks to the DEEP end of the ladder:
-- released last while spending, back on FIRST as MP recovers, so recovery
-- accelerates as early as possible (Henrik's 2026-07-21 night addendum:
-- "Refresh > least mp diff"). Each band carries Henrik's data points:
--   diff     = high - low
--   lastMax  = max MP while this piece (and everything after it) is worn
--   endMax   = max MP once this piece is out (= the next band's lastMax)
--   offAt    = UNEQUIP trigger: cur <= endMax - tick (an incoming tick can
--              never be capped by the swap)
--   onAt     = RE-EQUIP trigger: cur >= lastMax - tick (the piece goes back
--              on BEFORE full, so the next tick lands into its headroom)
-- The offAt..onAt gap is exactly `diff` wide: churn is impossible by
-- construction. A slot whose difference is <= 0 (the set's own piece is the
-- battery, or better) gets NO band -- the set already handles it.
-- ---------------------------------------------------------------------------
function M.build(slots, total, tick)
    local bands = {};
    for _, s in ipairs(slots or {}) do
        if type(s) == 'table' and s.slot ~= nil then
            local diff = (tonumber(s.high) or 0) - (tonumber(s.low) or 0);
            if diff > 0 then
                bands[#bands + 1] = { slot = tostring(s.slot), name = s.name,
                                      low = tonumber(s.low) or 0,
                                      high = tonumber(s.high) or 0, diff = diff,
                                      refresh = (s.refresh == true) };
            end
        end
    end
    table.sort(bands, function(a, b)
        if a.refresh ~= b.refresh then return not a.refresh; end   -- refresh sinks deep
        if a.diff ~= b.diff then return a.diff < b.diff; end
        return a.slot < b.slot;
    end);
    local last = tonumber(total) or 0;
    local t = tonumber(tick) or 0;
    for _, b in ipairs(bands) do
        b.lastMax = last;
        b.endMax  = last - b.diff;
        b.offAt   = b.endMax - t;
        b.onAt    = b.lastMax - t;
        last = b.endMax;
    end
    return bands;
end

-- ---------------------------------------------------------------------------
-- Target loadout: which batteries SHOULD be worn at this current MP. isOn
-- answers "is this band's piece worn right now" -- inside a band's dead zone
-- the current state is kept (the structural hysteresis), so the answer is a
-- function of (cur, worn state), never of a live max read. cur unreadable =
-- keep everything as it is (a bad read never moves gear -- the house rule).
-- Returns { [slot] = true|false } -- true: the battery belongs on; false:
-- the set's piece belongs on; absent: no band, the engine leaves the slot
-- to the normal set machinery.
-- ---------------------------------------------------------------------------
function M.target(bands, cur, isOn)
    local out = {};
    cur = tonumber(cur);
    for _, b in ipairs(bands or {}) do
        local worn = (isOn ~= nil) and (isOn(b.slot) == true) or false;
        if cur == nil then out[b.slot] = worn;
        elseif cur >= b.onAt then out[b.slot] = true;
        elseif cur <= b.offAt then out[b.slot] = false;
        else out[b.slot] = worn; end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- Tick measurement. The engine's 0.4s tick feeds every current-MP reading
-- through observe(); upward jumps between consecutive readings are recovery
-- ticks (refresh standing; refresh + hMP resting -- resting rises land in
-- their own bucket). Junk filter: only rises in (0, MAX_RISE] count (zone
-- heals, items and percent-pool jumps are not ticks). tick() answers the
-- MEDIAN of the last few rises for the state, falling back stand -> rest ->
-- DEFAULT_TICK, so the margins self-calibrate within seconds of play and
-- never depend on trait tables (CatsEyeXI's are custom).
-- ---------------------------------------------------------------------------
M.DEFAULT_TICK = 15;   -- Henrik's real endgame refresh; the pre-measurement stand-in
M.MAX_RISE = 150;
local KEEP = 5;

M._rises = M._rises or { stand = {}, rest = {} };
M._lastCur = M._lastCur or nil;

function M.observe(cur, resting)
    cur = tonumber(cur);
    if cur == nil then M._lastCur = nil; return; end
    local prev = M._lastCur;
    M._lastCur = cur;
    if prev == nil then return; end
    local delta = cur - prev;
    if delta <= 0 or delta > M.MAX_RISE then return; end
    local bucket = resting and M._rises.rest or M._rises.stand;
    bucket[#bucket + 1] = delta;
    if #bucket > KEEP then table.remove(bucket, 1); end
end

local function median(list)
    if list == nil or #list == 0 then return nil; end
    local c = {};
    for i, v in ipairs(list) do c[i] = v; end
    table.sort(c);
    return c[math.ceil(#c / 2)];
end

function M.tick(resting)
    local m;
    if resting then m = median(M._rises.rest) or median(M._rises.stand);
    else m = median(M._rises.stand); end
    return m or M.DEFAULT_TICK;
end

function M.reset()
    M._rises = { stand = {}, rest = {} };
    M._lastCur = nil;
end

return M;
