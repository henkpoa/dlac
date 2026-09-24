-- Void Restock plans against Inventory only. Unlisted items never enter a
-- deposit plan; a current-job entry overrides the character target, even at 0.
local M = {};
local function quantity(n)
    n = tonumber(n) or 0;
    if n ~= n or n == math.huge then return 0; end
    return math.max(0, math.min(65535, math.floor(n)));
end
function M.normalize(t)
    t = type(t) == 'table' and t or {};
    local function list(entries)
        local out, seen = {}, {};
        for _, e in ipairs(type(entries) == 'table' and entries or {}) do
            if type(e) == 'table' then
                local id = quantity(e.id);
                if id > 0 and id < 65535 and not seen[id] and type(e.name) == 'string' then
                    seen[id] = true;
                    out[#out + 1] = { id = id, name = e.name, target = quantity(e.target) };
                end
            end
        end
        return out;
    end
    local out = { character = list(t.character), jobs = {}, nudge = t.nudge ~= false };
    for job, entries in pairs(type(t.jobs) == 'table' and t.jobs or {}) do
        if type(job) == 'string' and job:match('^%u%u%u$') then out.jobs[job] = list(entries); end
    end
    return out;
end
function M.effective(config, job)
    local out, seen = {}, {};
    for _, list in ipairs({ config.jobs[job] or {}, config.character }) do
        for _, e in ipairs(list) do
            if not seen[e.id] then out[#out + 1] = e; seen[e.id] = true; end
        end
    end
    return out;
end
function M.plan(entries, inventory, balances, freeSlots, stackOf, canStore)
    local out = { fetch = {}, store = {} };
    local free = math.max(0, freeSlots or 0);
    for _, e in ipairs(entries) do
        local held, target = inventory[e.id] or 0, quantity(e.target);
        if held > target and (canStore == nil or canStore(e.id)) then
            out.store[#out.store + 1] = { id = e.id, qty = math.min(65535, held - target) };
        elseif held < target then
            local stack = math.max(1, quantity(stackOf(e.id)));
            local qty = math.min(target - held, balances[e.id] or 0, free * stack, 65535);
            if qty > 0 then
                out.fetch[#out.fetch + 1] = { id = e.id, qty = qty };
                free = free - math.ceil(qty / stack);
            end
        end
    end
    return out;
end
function M.serialize(config)
    config = M.normalize(config);
    local lines = { '-- Void Restock: inventory targets, character and job overrides.',
        'return { nudge = ' .. tostring(config.nudge) .. ',', 'character = {' };
    local function emit(entries)
        for _, e in ipairs(entries) do
            lines[#lines + 1] = string.format('  { id = %d, name = %q, target = %d },', e.id, e.name, e.target);
        end
    end
    emit(config.character);
    lines[#lines + 1] = '}, jobs = {';
    local jobs = {}; for job in pairs(config.jobs) do jobs[#jobs + 1] = job; end; table.sort(jobs);
    for _, job in ipairs(jobs) do
        lines[#lines + 1] = string.format('[%q] = {', job); emit(config.jobs[job]); lines[#lines + 1] = '},';
    end
    lines[#lines + 1] = '} };';
    return table.concat(lines, '\n') .. '\n';
end
return M;
