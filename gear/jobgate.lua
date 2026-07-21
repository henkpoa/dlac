--[[
    dlac/gear/jobgate.lua -- "can ANY of my jobs wear this?" the addon-side mirror
    of the server's canEquipItemOnAnyJob (charutils.cpp:2582): a lockstyle piece
    renders only if ONE of your jobs, at its CURRENT level, meets the item's job +
    required level. Reading the current level (GetJobLevel) makes this
    PRESTIGE-CORRECT by construction -- it is the same jobs.job[i] the server gate
    reads, so whatever prestige sets a job's level to, the two agree.

        jobgate.canEquip(rec, jobLevels)  -> can any job in jobLevels wear rec?
        jobgate.levels()                  -> { abbr -> level } live, or nil (unreadable)

    Callers FAIL OPEN on a nil levels read (offer everything, pre-login) -- never
    fail closed (the Save-gate lesson: a fail-closed gate bricked Save). dispatch's
    _lsStyleGate is the ENGINE-side mirror of the same one server rule; this is the
    addon-side twin (the two Lua states can't share a require).
]]--

local M = {};

-- Job index -> abbr, the client's job order for GetJobLevel(i). Mirrors LS_JOBS
-- in dispatch.lua.
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

-- Live job levels { abbr -> level }, or nil when unreadable (pre-login, headless)
-- -> callers FAIL OPEN. Injectable for headless tests.
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

function M.levels() return M.reader(); end

return M;
