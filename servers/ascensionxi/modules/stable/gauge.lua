-- Native slot 102 supplies the running timer. F6 supplies the merit period once
-- per zone, job/level change or merit update. No periodic requests or slot scans.
local M = {};
M._clock = os.clock;
M._read = function() return nil; end;
local job, level, zoning, dirty, needed = nil, nil, false, true, true;
local period, remaining, readAt, lastF6, f6At;
local generation = 0;

function M.context(nextJob, nextLevel)
    if nextJob == job and nextLevel == level then return false; end
    job, level = nextJob, nextLevel;
    period, remaining, lastF6 = nil, nil, nil;
    dirty, needed = true, true;
    generation = generation + 1;
    return true;
end

function M.zone(out)
    zoning = out;
    period, remaining, lastF6 = nil, nil, nil;
    dirty, needed = true, true;
    generation = generation + 1;
end

function M.recastChanged() dirty = true; end
function M.periodChanged() needed = true; generation = generation + 1; end
function M.needsPeriod() return not zoning and job == 9 and needed; end
function M.requested() needed = false; return generation; end
function M.accept(ms, periodMs, epoch)
    if epoch ~= generation or zoning or job ~= 9 then return false; end
    period, lastF6, f6At = periodMs / 1000, ms / 1000, M._clock();
    dirty = true;
    return true;
end

function M.pump()
    if zoning or job ~= 9 or not dirty then return; end
    dirty = false;
    local ok, value = pcall(M._read);
    remaining = ok and type(value) == 'number' and value >= 0 and value or nil;
    readAt = M._clock();
end

function M.view()
    if zoning or job ~= 9 or not period or remaining == nil then return nil; end
    local now = M._clock();
    local left = math.max(0, remaining - (now - readAt));
    local missing = math.min(3, math.ceil(left / period));
    return { charges = 3 - missing, nextSeconds = missing > 0 and left - (missing - 1) * period or 0,
        periodSeconds = period, time = now };
end

function M.status()
    local now = M._clock();
    return { native = remaining and math.max(0, remaining - (now - readAt)),
        wire = lastF6 and math.max(0, lastF6 - (now - f6At)), period = period,
        job = job, level = level, zoning = zoning, needed = needed };
end

return M;
