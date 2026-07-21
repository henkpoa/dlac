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
-- The band ladder: ONE band per slot (v92 ruling -- field round 10). The
-- band is the slot's TOP battery (augments counted; at equal MP the
-- higher-Refresh copy wins) versus the POTENCY POINT low/lowRf -- the
-- piece the player's own sets put there. Equipping refresh gear is the
-- IDLE SET'S job, never the engine's: the engine only needs to be AWARE
-- of the refresh it would displace, and that awareness lives entirely in
-- the ordering. (The v90 multi-rung experiment -- the engine wearing
-- refresh mid-rungs itself -- is retired: besides overstepping the job,
-- wearing the mid-rungs depressed the pool below the top bands'
-- re-equip thresholds and the ladder deadlocked at max MP.)
--
--   slots = { { slot='body', low=31, lowRf=2,   -- idle wears Clr. Bliaut +1
--               rungs = { {name="Hlr. Bliaut +1", mp=53, rf=0}, ... } }, ... }
-- Legacy single-battery inputs (s.high [+ s.rfDelta / s.refresh]) build
-- the same one band.
--
-- ORDER ("Refresh > least mp diff"; refresh pieces release LAST and return
-- FIRST -- mp recovery is key): rfDelta ASC, then diff ASC, where rfDelta =
-- battery Refresh - potency Refresh. A refresh-COST band (Hlr. Bliaut +1
-- displacing the idle's Clr. Bliaut +1) floats shallowest -- the battery
-- is first out and last back, so the SET's refresh piece is back first and
-- out last; refresh-GAIN bands sink by magnitude.
--
-- Each band carries Henrik's data points (lastMax/endMax and the offAt/onAt
-- triggers). offAt = endMax - tick (an incoming tick can never be capped by
-- the swap). onAt = lastMax - tick, CLAMPED to endMax (v92): the raw
-- formula sits ABOVE the reachable pool whenever diff > tick -- recovery
-- can never reach it and the band never re-fires (field round 10: "not
-- switching away the refresh pieces even at max MP"). Clamped, a small-diff
-- band keeps the early re-equip (the next tick lands in its headroom) and a
-- big-diff band fires the moment the pool genuinely tops out. offAt <
-- onAt always (the gap is min(diff, tick) wide): churn stays impossible.
-- ---------------------------------------------------------------------------
function M.build(slots, total, tick)
    local bands = {};
    for _, s in ipairs(slots or {}) do
        if type(s) == 'table' and s.slot ~= nil then
            local low = tonumber(s.low) or 0;
            local lowRf = tonumber(s.lowRf) or 0;
            local top = nil;
            if type(s.rungs) == 'table' then
                for _, r in ipairs(s.rungs) do
                    if type(r) == 'table' and r.name ~= nil then
                        local mp = tonumber(r.mp) or 0;
                        local rf = tonumber(r.rf) or 0;
                        if top == nil or mp > top.mp or (mp == top.mp and rf > top.rf) then
                            top = { name = r.name, mp = mp, rf = rf };
                        end
                    end
                end
            elseif s.high ~= nil then
                local rd = tonumber(s.rfDelta) or ((s.refresh == true) and 1 or 0);
                top = { name = s.name, mp = tonumber(s.high) or 0, rf = lowRf + rd };
            end
            if top ~= nil and top.mp - low > 0 then
                bands[#bands + 1] = { slot = tostring(s.slot), name = top.name,
                                      low = low, high = top.mp, diff = top.mp - low,
                                      rfDelta = top.rf - lowRf,
                                      refresh = (top.rf - lowRf) > 0 };
            end
        end
    end
    table.sort(bands, function(a, b)
        if a.rfDelta ~= b.rfDelta then return a.rfDelta < b.rfDelta; end
        if a.diff ~= b.diff then return a.diff < b.diff; end
        return a.slot < b.slot;
    end);
    local last = tonumber(total) or 0;
    local t = tonumber(tick) or 0;
    for _, b in ipairs(bands) do
        b.lastMax = last;
        b.endMax  = last - b.diff;
        b.offAt   = b.endMax - t;
        b.onAt    = math.min(b.lastMax - t, b.endMax);   -- reachable, always
        last = b.endMax;
    end
    return bands;
end

-- ---------------------------------------------------------------------------
-- Target loadout: WHICH PIECE each banded slot should wear at this current
-- MP. wornOf(slot) -> the worn item name (the hysteresis state: inside a
-- band's dead zone the current state is kept, so the answer is a function
-- of (cur, worn), never of a live max read; cur unreadable = keep as-is).
-- Per band: ON at cur >= onAt, OFF at cur <= offAt, dead zone = ON iff the
-- worn piece IS this band's rung. Per slot the answer is the SHALLOWEST ON
-- band's rung (bands arrive shallow-first from build):
--   out[slot] = "Piece Name"  -> that rung belongs on
--   out[slot] = false         -> no rung is on: the set's piece belongs on
--   out[slot] absent          -> no band, the normal set machinery owns it
-- ---------------------------------------------------------------------------
function M.target(bands, cur, wornOf)
    local out = {};
    cur = tonumber(cur);
    for _, b in ipairs(bands or {}) do
        if out[b.slot] == nil then out[b.slot] = false; end
        if out[b.slot] == false then   -- no shallower rung claimed the slot yet
            local worn = (wornOf ~= nil) and wornOf(b.slot) or nil;
            local isOn = worn ~= nil and b.name ~= nil
                         and string.lower(tostring(worn)) == string.lower(tostring(b.name));
            local on;
            if cur == nil then on = isOn;
            elseif cur >= b.onAt then on = true;
            elseif cur <= b.offAt then on = false;
            else on = isOn; end
            if on then out[b.slot] = b.name; end
        end
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
-- The MARGIN floor (v95): the measurement is honest -- unbuffed gear refresh
-- really does tick +1..3 -- but a 1-MP margin makes hair-width hysteresis
-- (field: off<=1086 / on>=1087). tick() never answers below this; the
-- buckets keep the true readings.
M.MIN_TICK = 5;
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
    if m == nil then return M.DEFAULT_TICK; end
    return math.max(m, M.MIN_TICK);
end

function M.reset()
    M._rises = { stand = {}, rest = {} };
    M._lastCur = nil;
end

return M;
