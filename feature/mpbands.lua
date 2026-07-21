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
-- The band ladder, MULTI-RUNG (v90 -- field round 9: "Bunzi's Hat should be
-- 2nd last, Healer's Bliaut +1 last"). A slot contributes ONE BAND PER
-- MEANINGFUL RUNG, not just its top battery:
--   slots = { { slot='body', low=29, lowRf=0,
--               rungs = { {name="Bunzi's Robe", mp=50, rf=0},
--                         {name="Hlr. Bliaut +1", mp=35, rf=2}, ... } }, ... }
-- Rungs are sanitized to a strictly-falling-MP, strictly-RISING-refresh
-- chain (at equal MP the higher-Refresh copy wins outright; a deeper rung
-- that adds no refresh over the one above is dominated -- stepping down to
-- it is never better than stepping straight to the potency piece). Each
-- adjacent pair becomes a band: wearing rung i INSTEAD OF rung i+1 (the
-- last rung bands against the potency point low/lowRf), with
--   diff    = mp_i - mp_next          (the max-MP this band holds)
--   rfDelta = rf_i - rf_next          (the refresh this band gains/costs)
-- Legacy single-battery inputs (s.high [+ s.rfDelta / s.refresh]) still
-- build the one band exactly as before.
--
-- ORDER ("Refresh > least mp diff"; refresh pieces release LAST and return
-- FIRST -- mp recovery is key): plain sort by rfDelta ASC, then diff ASC.
-- Refresh-COST bands (a flat-MP top-up displacing a refresh rung: Bunzi's
-- Robe over Hlr. Bliaut +1) float shallowest -- first out, last back;
-- plain bands run by smallest difference; refresh-GAIN bands sink by
-- MAGNITUDE -- +1 (Bunzi's Hat over a plain set piece) releases before +2
-- (Hlr. Bliaut +1), so the strongest refresh is the last thing to go and
-- the first thing back.
--
-- Each band carries Henrik's data points (lastMax/endMax and the offAt/onAt
-- triggers, tick-margined both directions); the offAt..onAt gap is exactly
-- `diff` wide -- churn is impossible by construction.
-- ---------------------------------------------------------------------------
function M.build(slots, total, tick)
    local bands = {};
    for _, s in ipairs(slots or {}) do
        if type(s) == 'table' and s.slot ~= nil then
            local low = tonumber(s.low) or 0;
            local lowRf = tonumber(s.lowRf) or 0;
            -- Normalize input to a rung chain (legacy single-battery accepted).
            local src = {};
            if type(s.rungs) == 'table' then
                for _, r in ipairs(s.rungs) do
                    if type(r) == 'table' and r.name ~= nil then
                        src[#src + 1] = { name = r.name, mp = tonumber(r.mp) or 0,
                                          rf = tonumber(r.rf) or 0 };
                    end
                end
            elseif s.high ~= nil then
                local rd = tonumber(s.rfDelta) or ((s.refresh == true) and 1 or 0);
                src[1] = { name = s.name, mp = tonumber(s.high) or 0, rf = lowRf + rd };
            end
            table.sort(src, function(a, b)
                if a.mp ~= b.mp then return a.mp > b.mp; end
                return a.rf > b.rf;
            end);
            -- Keep the top rung, then only rungs that BUY refresh on the way
            -- down; drop anything at-or-below the potency point.
            local chain = {};
            for _, r in ipairs(src) do
                if r.mp > low then
                    local prev = chain[#chain];
                    if prev == nil or (r.mp < prev.mp and r.rf > prev.rf) then
                        chain[#chain + 1] = r;
                    end
                end
            end
            for i, r in ipairs(chain) do
                local nxt = chain[i + 1];
                local underMp = (nxt ~= nil) and nxt.mp or low;
                local underRf = (nxt ~= nil) and nxt.rf or lowRf;
                local diff = r.mp - underMp;
                if diff > 0 then
                    bands[#bands + 1] = { slot = tostring(s.slot), name = r.name,
                                          under = (nxt ~= nil) and nxt.name or nil,
                                          low = underMp, high = r.mp, diff = diff,
                                          rfDelta = r.rf - underRf,
                                          refresh = (r.rf - underRf) > 0 };
                end
            end
        end
    end
    table.sort(bands, function(a, b)
        if a.rfDelta ~= b.rfDelta then return a.rfDelta < b.rfDelta; end
        if a.diff ~= b.diff then return a.diff < b.diff; end
        if a.slot ~= b.slot then return a.slot < b.slot; end
        return tostring(a.name) < tostring(b.name);
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
