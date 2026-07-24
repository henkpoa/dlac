-- vanamoon.lua -- PURE Vana'diel moon-phase math (no Ashita, no imgui). The
-- digging guide's live clock header (issue #97, PRD #93) needs the moon phase
-- for two things: the header label the player reads, and the moon multiplier the
-- odds engine (digcalc) prices with. Moon and day are pure functions of the
-- Vana'diel day number; the live day comes from nativedata.timestamp() at render
-- time, weather is read separately (client-observed, degrades gracefully).
--
-- The moon runs an 84-Vana'diel-day cycle. age = (day + OFFSET) % 84, and the
-- illumination PERCENT rises 0 -> 100 over the first half (New -> Full) then
-- falls back over the second (Full -> New); waxing while age < 42, waning after.
-- This is the community-standard linear model used by the Windower / Ashita
-- vana-time addons.
--
-- The epoch OFFSET is derived from the CatsEyeXI server's moon::get_phase
-- (src/common/vana_time.h): daysmod = (day + 26) % 84, with daysmod 0 = 100%
-- Full (waning side) and daysmod 42 = 0% New. vanamoon's internal age curve
-- peaks (Full) at age 42, so OFFSET = 68 (= 26 + 42) realigns it onto the
-- server curve -- both the percent AND the waxing/waning direction then match
-- the server exactly (tests VM11-VM14 pin concrete day numbers against it).
--
-- Lua 5.1 / LuaJIT compatible.

local M = {};

M.CYCLE  = 84;   -- Vana'diel days per lunar cycle
M.OFFSET = 68;   -- epoch alignment: 26 (server daysmod) + 42 (Full-peak) -- see above
local HALF = M.CYCLE / 2;   -- 42: the Full-Moon midpoint

-- Moon age within the cycle (0 = New, 42 = Full) for an absolute Vana'diel day
-- number, or nil for a bad/absent input (a failed clock read degrades to "no
-- moon", never a wrong one).
function M.age(day)
    local d = tonumber(day);
    if d == nil then return nil; end
    return (math.floor(d) + M.OFFSET) % M.CYCLE;
end

-- Illumination percent (0 = New, 100 = Full), rounded, or nil on a bad input.
function M.percent(day)
    local a = M.age(day);
    if a == nil then return nil; end
    local p = (a <= HALF) and (a / HALF) or ((M.CYCLE - a) / HALF);
    return math.floor(p * 100 + 0.5);
end

-- true = waxing (New -> Full), false = waning (Full -> New), nil on bad input.
function M.waxing(day)
    local a = M.age(day);
    if a == nil then return nil; end
    return a < HALF;
end

-- The moon phase NAME from percent + direction. New/Full at the extremes, the
-- quarters at the 50% mark, crescent/gibbous between -- the standard 8 names.
function M.name(day)
    local p = M.percent(day);
    if p == nil then return nil; end
    if p <= 5  then return 'New Moon';  end
    if p >= 95 then return 'Full Moon'; end
    local wax = M.waxing(day);
    if p >= 45 and p <= 55 then return wax and 'First Quarter' or 'Last Quarter'; end
    if wax then return (p < 50) and 'Waxing Crescent' or 'Waxing Gibbous'; end
    return (p > 50) and 'Waning Gibbous' or 'Waning Crescent';
end

-- Everything in one call: { age, percent, waxing, name } or nil on a bad input.
function M.phase(day)
    local a = M.age(day);
    if a == nil then return nil; end
    return {
        age     = a,
        percent = M.percent(day),
        waxing  = M.waxing(day),
        name    = M.name(day),
    };
end

return M;
