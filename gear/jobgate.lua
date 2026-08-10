--[[
    dlac/gear/jobgate.lua -- "can ANY of my jobs wear this?" the addon-side mirror
    of the server's canEquipItemOnAnyJob (charutils.cpp:2582): a lockstyle piece
    renders only if ONE of your jobs meets the item's job + required level.

        jobgate.canEquip(rec, jobLevels)  -> can any job in jobLevels wear rec?
        jobgate.levels()                  -> { abbr -> EFFECTIVE level } live, or nil
        jobgate.effectiveLevels(raw, pr)  -> the pure prestige fold (see below)

    PRESTIGE (learned the hard way, 2026-08-10): this header used to claim the
    GetJobLevel read was "prestige-correct by construction". WRONG -- it assumed
    prestige merely changes the level number. On CatsEyeXI, prestiging resets a
    job to Lv1 AND the server's gate waives gear level requirements on that job
    (hidden cexi submodules; field-proven by a prestiged PLD lockstyling Lv73
    Valor Coronet). So levels() folds the prestige tiers (feature\prestigewatch,
    the 0x1A4 mirror) over the raw read: a prestiged job reports effective level
    75 -- the item cap, so "report 75" and "waive the requirement" are the same
    rule. canEquip stays UNTOUCHED and pure: it is parity-pinned byte-identical
    to the engine twin (dispatch._lsStyleGate), and the fold happens where the
    LEVELS are produced, not where they are judged.

    Callers FAIL OPEN on a nil levels read (offer everything, pre-login) -- never
    fail closed (the Save-gate lesson: a fail-closed gate bricked Save). Unknown
    prestige (no reply yet) degrades to the raw read: too TIGHT at worst, never
    wrongly open -- and prestigewatch's persisted floor closes that window from
    the second logon onward.
]]--

local M = {};

-- Job index -> abbr, the client's job order for GetJobLevel(i). Mirrors LS_JOBS
-- in dispatch.lua. Also the wire order of prestigewatch's 0x1A4 tier bytes.
M.JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG',
           'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };

-- Pure: can ANY of the character's jobs (jobLevels: abbr -> level) wear rec at its
-- current level? Mirrors canEquipItemOnAnyJob. A record with no Jobs table can't
-- be predicted -- pass it (the server decides). 'All' => any job at level >= req.
function M.canEquip(rec, jobLevels)
    if type(rec) ~= 'table' then return true; end
    if type(rec.Jobs) ~= 'table' then return true; end
    local req = tonumber(rec.Level) or 0;
    jobLevels = jobLevels or {};
    for _, j in ipairs(rec.Jobs) do
        if j == 'All' then
            for _, l in pairs(jobLevels) do
                if (tonumber(l) or 0) >= req then return true; end
            end
            return false;
        end
        if (tonumber(jobLevels[j]) or 0) >= req then return true; end
    end
    return false;
end

-- Pure: fold prestige tiers over a raw level read. A prestiged job (tier >= 1)
-- reports 75 -- CatsEyeXI's gate waives level requirements on prestiged jobs,
-- and 75 is the item cap, so the two are equivalent. nil prestige (nothing
-- known) hands the raw table back untouched; nil raw stays nil (fail-open).
function M.effectiveLevels(raw, prestige)
    if type(raw) ~= 'table' or type(prestige) ~= 'table' then return raw; end
    local out = {};
    for ab, lv in pairs(raw) do out[ab] = lv; end
    for ab, tier in pairs(prestige) do
        if (tonumber(tier) or 0) > 0 and (tonumber(out[ab]) or 0) < 75 then out[ab] = 75; end
    end
    return out;
end

-- Live job levels { abbr -> level }, or nil when unreadable (pre-login, headless)
-- -> callers FAIL OPEN. Injectable for headless tests. RAW read -- the prestige
-- fold happens in levels(), so an injected reader is folded like the real one.
M.reader = function()
    local out = nil;
    pcall(function()
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        if pl == nil then return; end
        local t = {};
        for i, ab in ipairs(M.JOBS) do t[ab] = tonumber(pl:GetJobLevel(i)) or 0; end
        out = t;
    end);
    return out;
end;

-- The prestige read: { abbr -> tier } or nil. A FUNCTION seam (the injected-
-- reads law: stubs replace the function, values go stale). Call-time require
-- keeps load order flat (the meritwatch pattern) and headless suites inert.
M.prestige = function()
    local out = nil;
    pcall(function()
        local pw = require('dlac\\feature\\prestigewatch');
        if type(pw) == 'table' and type(pw.tiers) == 'function' then out = pw.tiers(); end
    end);
    return out;
end;

function M.levels()
    local raw = M.reader();
    if raw == nil then return nil; end
    return M.effectiveLevels(raw, M.prestige());
end

return M;
