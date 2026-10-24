--[[
    ascensionxi/pldgauge/demo -- /dl gauge demo on a Paladin: a scripted
    40-second loop that plays the gauge through every state with no server
    behind it, so the art can be judged before the server half is deployed.
    Pure: at(now) answers what the gauge would show at that moment.

      0-28 s   Divine Guard: blocks fill five points (half a point a block),
               Palisade spends all five (+5%, the big shield counts up), a
               Shield Bash interrupt adds a point, the points fill again, and
               with all five held the bar turns MP blue (OVERFLOW).
     28-40 s   Divine Fury: the points carried over show as crossed great
               swords; two are spent.
]]--

local M = { LOOP = 40, MAX = 5 };

local function guard(e)
    local st = { stance = 1, points = 0, palisade = 0, palisadeMax = 30, flags = 0, maxPoints = M.MAX,
                 charge = 0, threshold = 100 };
    local function fill(from, start)   -- a block every 0.8 s from `start`
        local blocks = math.max(0, math.floor((e - start) / 0.8));
        local made = math.min(M.MAX - from, math.floor(blocks / 2));
        st.points = from + made;
        st.charge = (st.points < M.MAX) and (blocks % 2) * 50 or 0;
    end
    fill(0, 0);                                                -- 0-8 s: five points
    if e >= 9 then st.points, st.charge, st.palisade = 0, 0, 5; end      -- Palisade: all five for +5%
    if e >= 11 then st.points = 1; end                         -- Shield Bash interrupt: a whole point
    if e >= 12 then fill(1, 12); st.palisade = 5; end          -- 12-18.4 s: back to five
    if e >= 19 then                                            -- every point held: the bar makes MP
        st.points, st.flags = M.MAX, 0x01;
        st.charge = math.floor(((e - 19) % 1.6) / 1.6 * 2) * 50;
    end
    return st, true;
end

local function fury(e)
    local st = { stance = 2, points = M.MAX, palisade = 0, palisadeMax = 30, flags = 0x01, maxPoints = M.MAX,
                 charge = 0, threshold = 100 };
    if e >= 6 then st.points, st.flags = M.MAX - 2, 0; end
    return st, false;
end

-- now -> { state, stance, palisadeUp, level }
function M.make(clock)
    local start = clock();
    local src = {};
    function src.at(now)
        local e = (now - start) % M.LOOP;
        local st, palisadeUp;
        if e < 28 then st, palisadeUp = guard(e); else st, palisadeUp = fury(e - 28); end
        -- Rev = which tenth-second step: a new rev only when something moved.
        st.rev = math.floor(e * 10) % 65536;
        st.job = 7;
        return { state = st, stance = st.stance, palisadeUp = palisadeUp, level = 75 };
    end
    return src;
end

return M;
