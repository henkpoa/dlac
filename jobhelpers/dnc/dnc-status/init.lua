-- Read-only DNC status from the active server pack's dncStatus service.

local _source = nil;

local function stepsText(steps)
    local parts = {};
    for _, step in ipairs(type(steps) == 'table' and steps or {}) do
        local name = tostring(step.name or 'Step');
        local level = tonumber(step.level) or 0;
        local remaining = tonumber(step.remaining);
        local part = string.format('%s %d', name, level);
        if remaining ~= nil and remaining > 0 then
            part = part .. string.format(' (%ds)', math.ceil(remaining));
        end
        parts[#parts + 1] = part;
    end
    return #parts > 0 and table.concat(parts, ', ') or 'none';
end

local function status()
    if type(_source) ~= 'table' or type(_source.status) ~= 'function' then return nil; end
    local ok, value = pcall(_source.status);
    return ok and type(value) == 'table' and value or nil;
end

return {
    api = 2,
    label = 'DNC Status',
    jobs = { 'DNC' },

    config = {
        file = 'jobhelper-dnc-status.lua',
        keys = {
            rememberedSteps = 'boolean',
            rhythm          = 'boolean',
            targetEffects   = 'boolean',
        },
        defaults = {
            rememberedSteps = true,
            rhythm          = true,
            targetEffects   = true,
        },
    },

    init = function(S)
        if type(S.server) == 'table' and type(S.server.service) == 'function' then
            _source = S.server.service('dncStatus');
        end
    end,

    panel = function(ctx)
        local ui, S = ctx.ui, ctx.S;
        if ui == nil or S == nil then return; end
        local cfg = S.cfg;
        local function enabled(key)
            return cfg ~= nil and cfg.get(key) == true;
        end
        local function toggle(key, label, tip)
            local nextValue = ui.toggle('dncstatus_' .. key, label, enabled(key), tip);
            if nextValue ~= nil and cfg ~= nil then cfg.set(key, nextValue); end
        end

        ui.section('DNC status', 'Choose which status details appear below.', function()
            toggle('rememberedSteps', 'Remembered steps', 'Show Perpetual Step memory reported by AXI.');
            toggle('rhythm', 'Unbroken Rhythm stacks and cost', 'Show the server-reported stack count and TP cost.');
            toggle('targetEffects', 'Perpetual Step on current target', 'Show the Steps and remaining duration on your current target.');
        end);

        local anyEnabled = enabled('rememberedSteps') or enabled('rhythm') or enabled('targetEffects');
        if anyEnabled and type(_source) == 'table' and type(_source.want) == 'function' then
            pcall(_source.want);
        end
        local data = status();
        if data == nil then
            ui.dim('Waiting for AXI DNC status telemetry.');
            return;
        end

        if enabled('rememberedSteps') then
            ui.section('Remembered steps', nil, function()
                local memory = data.memory;
                if type(memory) ~= 'table' then
                    ui.dim('No remembered steps.');
                    return;
                end
                ui.ok(stepsText(memory.steps));
                if tonumber(memory.remaining) ~= nil then
                    ui.dim(string.format('%ds remaining', math.max(0, math.ceil(memory.remaining))));
                end
            end);
        end

        if enabled('rhythm') then
            ui.section('Unbroken Rhythm', nil, function()
                local rhythm = type(data.rhythm) == 'table' and data.rhythm or {};
                local stacks = math.max(0, math.min(3, tonumber(rhythm.stacks) or 0));
                ui.text(ui.COL.ok, string.format('%d / 3 stacks', stacks));
                if tonumber(rhythm.cost) ~= nil then
                    ui.dim(string.format('%s: %d TP', stacks >= 3 and 'Refresh cost' or 'Next stack', rhythm.cost));
                else
                    ui.dim('TP cost unavailable.');
                end
            end);
        end

        if enabled('targetEffects') then
            ui.section('Current target', nil, function()
                local target = data.target;
                if type(target) ~= 'table' then
                    ui.dim('Target: none');
                    return;
                end
                ui.dim('Target: ' .. tostring(target.name or target.id or 'unknown'));
                ui.ok(stepsText(target.steps));
            end);
        end
    end,
};
