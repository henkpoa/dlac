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

function M.apply(rec, base, ctx)
    if not ctx or ctx.stanceSet ~= true or type(rec) ~= 'table' then return base; end
    if ctx.level and (rec.Level or 0) > ctx.level then return base; end
    local rows = data();
    local job = rows and rows[ctx.job];
    local deltas = job and job[rec.Id];
    if not deltas then return base; end
    local out = {};
    for k, v in pairs(base or {}) do out[k] = v; end
    for k, v in pairs(deltas) do out[k] = (out[k] or 0) + v; end
    return out;
end
return M;
