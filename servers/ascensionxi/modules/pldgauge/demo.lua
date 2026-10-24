--[[
    ascensionxi/pldgauge/demo -- /dl gauge demo on a Paladin: a scripted
    40-second loop that plays the gauge through every state with no server
    behind it, so the art can be judged before the server half is deployed.
    Pure: at(now) answers what the gauge would show at that moment.

      0-26 s   Divine Guard: blocks fill three points, two are spent on
               Palisade (the big shield counts up), a Shield Bash interrupt
               adds a point, then the bar fills behind three points and
               waits, capped.
     26-40 s   Divine Fury: the points carried over show as crossed great
               swords; one is spent.
]]--

local M = { LOOP = 40 };

local function guard(e)
    local st = { stance = 1, points = 0, palisade = 0, palisadeMax = 30, flags = 0, charge = 0, threshold = 100 };
    local blocks = math.floor(e / 1.2);                 -- a block every 1.2 s
    local made = math.min(3, math.floor(blocks / 2));
    st.points = made;
    st.charge = (made < 3) and (blocks % 2) * 50 or 0;
    if e >= 8 then st.points, st.palisade = made - 1, 11; end   -- Palisade spends a point
    if e >= 10 then st.points, st.palisade = math.max(0, made - 2), 12; end
    if e >= 13 then st.points = st.points + 1; end            -- Shield Bash interrupt: a whole point
    if e >= 16 then st.points, st.charge = 3, math.floor(100 * math.min(1, (e - 16) / 5)); end
    if e >= 21 then st.flags = 0x01; st.charge = 100; end     -- capped: the bar waits
    return st, true;
end

local function fury(e)
    local st = { stance = 2, points = 3, palisade = 0, palisadeMax = 30, flags = 0, charge = 0, threshold = 100 };
    if e >= 6 then st.points = 2; end
    return st, false;
end

-- now -> { state, stance, palisadeUp, level }
function M.make(clock)
    local start = clock();
    local src = {};
    function src.at(now)
        local e = (now - start) % M.LOOP;
        local st, palisadeUp;
        if e < 26 then st, palisadeUp = guard(e); else st, palisadeUp = fury(e - 26); end
        -- Rev = which tenth-second step: a new rev only when something moved.
        st.rev = math.floor(e * 10) % 65536;
        st.job = 7;
        return { state = st, stance = st.stance, palisadeUp = palisadeUp, level = 75 };
    end
    return src;
end

return M;
