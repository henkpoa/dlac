--[[
    ascensionxi/telemetry/formula -- AscensionXI's hit-rate composition, the
    one dlac mirrors (server research section 1.8). Pure.

    The server publishes every input, and the live result next to them, so a
    frame checks this copy: composing a frame's live totals must give its
    LiveAcc and ThresholdBp exactly (check()). A projected outfit then swaps
    in its own gear-movable inputs (compose(frame, ctx, inputs)).

      melee  : getACC  = max(0, base + min(trunc(base x FoodAccPct / 100), FoodAccCap))
               base    = AccFromSkill(skill) + floor(DEX x mult) + (2H ? TwoHandAccMod : 0)
                         + AccMod + Enlight + Tandem + Merit
      ranged : getRACC = max(1, base + min(trunc((100 + FoodRaccPct x base) / 100), FoodRaccCap))
               base    = AccFromSkill(skill) + RaccMod + RangedAccBonus + floor(AGI x mult)
               (the +100 inside the division is the server's own quirk: kept)
      both   : eff = getACC + PolicyAccBonus - FlashPenalty + LevelCorrection
               rate = clamp((75 + (eff - TargetEVA) / 2) / 100, floor, cap)
               threshold = trunc(rate x 100), in doubles, as the server converts it
]]--

local M = {};

-- 1:1 to 200, then 0.9, 0.8 and 0.9 a point, each segment floored.
function M.accFromSkill(skill)
    skill = tonumber(skill) or 0;
    if skill > 600 then return math.floor((skill - 600) * 0.9) + 540; end
    if skill > 400 then return math.floor((skill - 400) * 0.8) + 380; end
    if skill > 200 then return math.floor((skill - 200) * 0.9) + 200; end
    return skill;
end

local function truncDiv(n, d)
    local q = math.floor(math.abs(n) / d);
    return (n >= 0) and q or -q;
end
M.truncDiv = truncDiv;

local function twoHanded(ctx) return (ctx.flags or 0) % 256 >= 128; end

-- The accessor (getACC or getRACC) for a context. v holds the gear-movable
-- inputs to use (dex, agi, accMod, raccMod, twoHandAccMod, skill); anything
-- absent is taken live from the frame.
function M.accessor(frame, ctx, v)
    v = v or {};
    local function pick(name) local x = v[name]; if x == nil then x = frame[name .. 'Live']; end return x or 0; end
    local skill = v.skill or ctx.skillLive or 0;
    local mult = (ctx.statMultMilli or 750);
    if ctx.kind == 3 then
        local base = M.accFromSkill(skill) + pick('raccMod') + (frame.rangedAccBonus or 0)
            + math.floor(pick('agi') * mult / 1000);
        return math.max(1, base + math.min(truncDiv(100 + (frame.foodRaccPct or 0) * base, 100), frame.foodRaccCap or 0));
    end
    local base = M.accFromSkill(skill) + math.floor(pick('dex') * mult / 1000)
        + (twoHanded(ctx) and pick('twoHandAccMod') or 0) + pick('accMod')
        + (frame.enlightAcc or 0) + (frame.tandemAcc or 0) + (frame.meritAcc or 0);
    return math.max(0, base + math.min(truncDiv(base * (frame.foodAccPct or 0), 100), frame.foodAccCap or 0));
end

-- The effective ACC the rate is taken from; bonus is added the way the live
-- function adds its bonus argument (weapon skills: +100, WSACC, ...).
function M.effective(frame, ctx, acc, bonus)
    return acc + (ctx.policyAcc or 0) + (bonus or 0) - (frame.flashPenalty or 0) + (ctx.levelCorrection or 0);
end

function M.rate(ctx, effective)
    local floor, cap = (ctx.floorBp or 0) / 10000, (ctx.capBp or 0) / 10000;
    local raw = (75 + (effective - (ctx.targetEva or 0)) / 2) / 100;
    if raw < floor then raw = floor; end
    if raw > cap then raw = cap; end
    return raw;
end

-- The integer percent the attack rolls against, as basis points.
function M.thresholdBp(ctx, effective)
    return math.floor(M.rate(ctx, effective) * 100) * 100;
end

function M.capThresholdBp(ctx)
    return math.floor((ctx.capBp or 0) / 10000 * 100) * 100;
end

-- The smallest extra ACC that reaches the cap threshold (negative: what can
-- be given up). The linear answer, nudged once each way through the real
-- truncation.
function M.accToCap(ctx, effective)
    local capBp = M.capThresholdBp(ctx);
    local delta = 2 * (capBp / 100 - 75) - (effective - (ctx.targetEva or 0));
    if M.thresholdBp(ctx, effective + delta - 1) >= capBp then
        delta = delta - 1;
    elseif M.thresholdBp(ctx, effective + delta) < capBp then
        delta = delta + 1;
    end
    return delta;
end

-- Composes a context from inputs v: accessor, effective ACC, threshold.
function M.compose(frame, ctx, v, bonus)
    local acc = M.accessor(frame, ctx, v);
    local eff = M.effective(frame, ctx, acc, bonus);
    return acc, eff, M.thresholdBp(ctx, eff);
end

-- The formula check on a frame's own live totals: nil when every applicable
-- context reproduces LiveAcc and ThresholdBp, else a reason.
function M.check(frame)
    for _, ctx in ipairs(frame.contexts or {}) do
        if ctx.applicability == 0 then
            local acc, _, threshold = M.compose(frame, ctx);
            if acc ~= ctx.liveAcc then
                return ('ctx %d accuracy %d, the server says %d'):format(ctx.kind, acc, ctx.liveAcc);
            end
            if threshold ~= ctx.thresholdBp then
                return ('ctx %d threshold %d, the server says %d'):format(ctx.kind, threshold, ctx.thresholdBp);
            end
        end
    end
    return nil;
end

return M;
