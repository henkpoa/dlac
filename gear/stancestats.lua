-- Explicit set-planning assumption; never inferred from current player buffs.
-- Pack-owned data keeps stance rules out of the shared scoring machinery.
local M = {};
local cachedPack, cachedData;
local function data()
    local pack = require('dlac\\gear\\serverpack');
    local id = pack.active();
    if id == nil then return nil; end
    if cachedPack ~= id then
        cachedPack = id;
        local ok, rows = pcall(require, 'dlac\\servers\\' .. id .. '\\stances');
        cachedData = ok and type(rows) == 'table' and rows or {};
    end
    return cachedData;
end

-- The Set Type ids that plan with a stance, in menu order. gear\gearoptim's
-- STANCE_TYPES must hold exactly these (tests/stance_sets.lua).
M.TYPES = { 'composure', 'stance', 'divineguard', 'divinefury' };

-- The job's table for a stance type ('stance' when nil), or nil.
local function stanceOf(job, typeId)
    local rows = data();
    local t = rows and rows[job];
    t = type(t) == 'table' and t[typeId or 'stance'] or nil;
    return type(t) == 'table' and t or nil;
end

-- The stance's name as the Set Type menu shows it ('Duelist Stance',
-- 'Composure'), or nil when the pack has no gear for it on that job.
function M.label(job, typeId)
    local t = stanceOf(job, typeId);
    return (t ~= nil and type(t.label) == 'string') and t.label or nil;
end

-- Every stance bonus the pack gives this piece, as { { label, stats } }:
-- jobs in name order, each job's stances in TYPES (menu) order. The hover
-- card lists them whatever set or job is in view; apply() is what counts them.
function M.bonusesOf(rec)
    local out = {};
    local rows = data();
    if type(rec) ~= 'table' or rec.Id == nil or type(rows) ~= 'table' then return out; end
    local jobs = {};
    for job in pairs(rows) do jobs[#jobs + 1] = job; end
    table.sort(jobs);
    for _, job in ipairs(jobs) do
        for _, typeId in ipairs(M.TYPES) do
            local t = stanceOf(job, typeId);
            local deltas = t and t[rec.Id];
            if type(deltas) == 'table' then
                out[#out + 1] = { label = M.label(job, typeId) or typeId, stats = deltas };
            end
        end
    end
    return out;
end

function M.apply(rec, base, ctx)
    if not ctx or ctx.stanceSet ~= true or type(rec) ~= 'table' then return base; end
    if ctx.level and (rec.Level or 0) > ctx.level then return base; end
    local t = stanceOf(ctx.job, ctx.stanceType);
    local deltas = t and t[rec.Id];
    if not deltas then return base; end
    local out = {};
    for k, v in pairs(base or {}) do out[k] = v; end
    for k, v in pairs(deltas) do out[k] = (out[k] or 0) + v; end
    return out;
end
return M;
