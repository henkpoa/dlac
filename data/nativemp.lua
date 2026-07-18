--[[
    dlac/data/nativemp.lua -- native (naked, meritless) max MP of a character.
    THE server formula, ported verbatim from the CatsEyeXI server repo
    (stable branch, fetched 2026-07-18): src/map/utils/charutils.cpp
    CalculateStats() MP section + src/map/grades.cpp tables. stable = the live
    branch; base is stale (memory: catseyexi-not-lsb).

        nativemp.get(race, mjob, mlvl, sjob, slvl [, meritMP])
            -> integer MP, or nil on unusable input (nil never means 0 MP --
               a WAR/NIN really is 0)
        nativemp.self([meritMP])
            -> MP for the local player from live reads, nil when unreadable

    Server shape (PLAYER_MP_MULTIPLIER=1.0 and SJ_MP_DIVISOR=2.0 on CatsEyeXI,
    settings/default/map.lua; final value truncates to int like the (int16)
    cast):
        upTo60 = min(mlvl,60)-1        over60 = max(mlvl-60,0)
        race : base + perLvl*upTo60 + over60rate*over60      (main job has MP)
               (base + perLvl*(slvl-1)) / 2                  (main 0 MP, sub has)
        main : base + perLvl*upTo60 + over60rate*over60      (0 when no grade)
        sub  : (base + perLvl*(slvl-1)) / 2                  (0 when no grade)
        MP   = floor(race + main + sub + meritMP)
    Merits are NOT native: CatsEyeXI raises Max MP merits to 15 levels x 10 MP
    (sql/merits.sql id 66) -- pass the character's merit MP if you want the
    on-screen naked number. Field pin 2026-07-18: Mindie Hume WHM75/SCH37
    reads 724 naked = 614 formula + 110 merit (11/15 levels).

    Race here is the LOOK race (GRAP_LIST id 1..8) -- exactly what the server
    switches on (PChar->look.race). Cosmetic client mods (sexchange,
    singlerace) repaint that id locally and would fool self(); dlac does not
    carry those, so the read is trusted.
]]--

local M = {};

-- MP growth per grade rank (grades.cpp MPScale): base, per level up to 60,
-- per level over 60. Rank 1..7 = A..G. Note D-G GAIN rate after 60 -- the
-- retail curve steepens for weak pools.
M.SCALE = {
    [1] = { 16, 6,   4 },   -- A
    [2] = { 14, 5,   4 },   -- B
    [3] = { 12, 4,   4 },   -- C
    [4] = { 10, 3,   4 },   -- D
    [5] = {  8, 2,   3 },   -- E
    [6] = {  6, 1,   2 },   -- F
    [7] = {  4, 0.5, 1 },   -- G
};

-- Race MP grade by CLIENT race id (look id; both sexes share a row --
-- charutils folds HumeMale/HumeFemale to one grade line).
M.RACE_GRADE = {
    [1] = 4, [2] = 4,   -- Hume    D
    [3] = 5, [4] = 5,   -- Elvaan  E
    [5] = 1, [6] = 1,   -- Tarutaru A
    [7] = 4,            -- Mithra  D
    [8] = 7,            -- Galka   G
};

-- Job MP grade by job id (grades.cpp JobGrades column 1); absent/0 = the job
-- carries no MP pool at all.
M.JOB_GRADE = {
    [3]  = 3,   -- WHM C
    [4]  = 2,   -- BLM B
    [5]  = 4,   -- RDM D
    [7]  = 6,   -- PLD F
    [8]  = 6,   -- DRK F
    [15] = 1,   -- SMN A
    [16] = 4,   -- BLU D
    [20] = 4,   -- SCH D
    [21] = 2,   -- GEO B
    [22] = 6,   -- RUN F
};

M.SJ_MP_DIVISOR       = 2;      -- settings map.SJ_MP_DIVISOR (retail half)
M.MERIT_MP_PER_LEVEL  = 10;     -- merits.sql id 66 value
M.MERIT_MP_CAP_LEVELS = 15;     -- CatsEyeXI-raised cap (retail was 8)

local function pool(grade, upTo60, over60)
    local s = M.SCALE[grade];
    if s == nil then return 0; end
    return s[1] + s[2] * upTo60 + s[3] * over60;
end

-- Native max MP. race = look id 1..8 (unknown ids fall back to Hume like the
-- server's default case), mjob/sjob = job ids 1..22, slvl 0/nil = no subjob.
-- meritMP (optional) is added AFTER the formula, matching the server.
function M.get(race, mjob, mlvl, sjob, slvl, meritMP)
    mlvl = tonumber(mlvl);
    if type(race) ~= 'number' or type(mjob) ~= 'number' or mlvl == nil or mlvl < 1 then
        return nil;
    end
    slvl = tonumber(slvl) or 0;

    local rg = M.RACE_GRADE[race] or M.RACE_GRADE[1];
    local mg = M.JOB_GRADE[mjob] or 0;
    local sg = (slvl > 0) and (M.JOB_GRADE[sjob] or 0) or 0;

    local upTo60 = (mlvl < 60) and (mlvl - 1) or 59;
    local over60 = (mlvl < 60) and 0 or (mlvl - 60);

    local raceStat = 0;
    if mg == 0 then
        -- main job has no pool: the race contributes at the SUBJOB's level,
        -- halved (this is why NIN/WHM has any MP at all)
        if sg ~= 0 then
            raceStat = pool(rg, slvl - 1, 0) / M.SJ_MP_DIVISOR;
        end
    else
        raceStat = pool(rg, upTo60, over60);
    end

    local jobStat  = (mg ~= 0) and pool(mg, upTo60, over60) or 0;
    local sJobStat = (sg ~= 0) and (pool(sg, slvl - 1, 0) / M.SJ_MP_DIVISOR) or 0;

    return math.floor(raceStat + jobStat + sJobStat + (tonumber(meritMP) or 0));
end

-- Live readers, injectable for headless tests (gamemode.lua pattern). All
-- nil out on failure -- self() answers nil for "unknown", never a guess.
M.selfIndex = function()
    local idx = nil;
    pcall(function()
        idx = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    end);
    if idx == 0 then idx = nil; end
    return idx;
end;

M.readRace = function(idx)
    local r = nil;
    pcall(function()
        r = AshitaCore:GetMemoryManager():GetEntity():GetRace(idx);
    end);
    return r;
end;

M.readJobs = function()
    local mj, ml, sj, sl = nil, nil, nil, nil;
    pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer();
        mj = p:GetMainJob();
        ml = p:GetMainJobLevel();    -- the SYNCED level when level sync is on,
        sj = p:GetSubJob();          -- which is also the level the server
        sl = p:GetSubJobLevel();     -- recalculates the pool at
    end);
    return mj, ml, sj, sl;
end;

-- Native MP of the local player, or nil when any read fails (headless, zoning,
-- login settle). meritMP is the caller's to supply -- the client only learns
-- merit allocations when the merit menu opens, so dlac cannot read it here.
function M.self(meritMP)
    local idx = M.selfIndex();
    if idx == nil then return nil; end
    local race = M.readRace(idx);
    local mj, ml, sj, sl = M.readJobs();
    if type(race) ~= 'number' or race < 1 or (mj or 0) == 0 or (ml or 0) == 0 then
        return nil;
    end
    return M.get(race, mj, ml, sj, sl, meritMP);
end

return M;
