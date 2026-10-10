--[[
    ascensionxi/whmgauge/demo -- /dl gauge demo: a scripted 48-second loop
    that plays the gauge through every state with no server behind it, so
    the art can be judged before the server half is deployed. Pure: at(now)
    answers what the gauge would show at that moment.

      0-24 s   Solace: three flowers fill (small, medium, large), one is
               spent (x2.5 on the next Regen), Divine Seal goes up, is
               used, then recasts.
     24-48 s   Misery: two flowers, Banish turns dark, the charge makes
               a third flower, then waits full while capped.
]]--

local M = { LOOP = 48 };

local function solace(e)
    local st = { stance = 1, tier = 3, flowers = { 0, 0, 0 }, flags = 0, boost = 0, threshold = 280 };
    local seal = { 0, false };   -- remaining, active
    local fills = { 1, 2, 3 };   -- the tier each fill made (the player levelled between them)
    local made = math.min(3, math.floor(e / 4));
    for i = 1, made do st.flowers[i] = fills[i]; end
    if made < 3 then st.charge = math.floor(280 * ((e % 4) / 4)); else st.charge = 0; end
    if e >= 14 then st.flowers = { 1, 2, 0 }; st.flags = 0x02; st.boost = 3; st.charge = math.floor(280 * math.min(1, (e - 14) / 8)); end
    if e >= 16 and e < 19 then seal = { 0, true }; end
    if e >= 19 then seal = { 120 - (e - 19) * 20, false }; end
    if made >= 3 and e < 14 then st.flags = 0; end
    return st, seal;
end

local function misery(e)
    local st = { stance = 2, tier = 3, flowers = { 0, 0, 0 }, flags = 0, boost = 0, threshold = 500 };
    local made = math.min(2, math.floor(e / 5));
    for i = 1, made do st.flowers[i] = 3; end
    st.charge = (made < 2) and math.floor(500 * ((e % 5) / 5)) or math.floor(500 * math.min(1, (e - 10) / 4));
    if e >= 8 then st.flags = st.flags + 0x01; end            -- Banish converted to dark
    if e >= 14 then st.flowers[3] = 3; st.charge = math.floor(500 * math.min(1, (e - 14) / 2)); end   -- the third flower; the charge fills again
    if e >= 16 then st.flags = st.flags + 0x04; end           -- capped: the charge waits
    return st;
end

-- now -> { state, stance, seal, sealActive, level }
function M.make(clock)
    local start = clock();
    local src = {};
    function src.at(now)
        local e = (now - start) % M.LOOP;
        local st, seal, sealActive;
        if e < 24 then
            local s;
            st, s = solace(e);
            seal, sealActive = s[1], s[2];
        else
            st = misery(e - 24);
        end
        -- Rev = which tenth-second step: a new rev only when something moved.
        st.rev = math.floor(e * 10) % 65536;
        st.job = 3;
        return { state = st, stance = st.stance, seal = seal, sealActive = sealActive, level = 75 };
    end
    return src;
end

return M;
