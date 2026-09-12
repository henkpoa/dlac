-- Numeric gathering rules declared by the active server pack.
local M = {};
M.categories = { 'Harvesting', 'Excavation', 'Logging', 'Mining' };
M.slots = { 'head', 'neck', 'body', 'hands', 'waist', 'legs', 'feet' };

function M.enabled()
    local ok, pack = pcall(require, 'dlac\\gear\\serverpack');
    return ok and pack.const('helmModel') == 'extra-rolls';
end

function M.build(candidates)
    local out = { model = 'extra-rolls', categories = {} };
    for _, category in ipairs(M.categories) do
        local bySlot = {};
        out.categories[category] = bySlot;
        for _, rec in ipairs(candidates) do
            local st = rec.Stats or {};
            local roll = tonumber(st[category .. 'ExtraRoll']) or 0;
            local reduction = tonumber(st.HelmBreakReduction) or 0;
            local slot = tostring(rec.Slot or ''):lower();
            local allowed = false;
            for _, s in ipairs(M.slots) do if s == slot then allowed = true; break; end end
            if allowed and (roll > 0 or reduction > 0) then
                bySlot[slot] = bySlot[slot] or {};
                table.insert(bySlot[slot], { name = rec.Name, level = rec.Level or 0,
                    roll = roll, reduction = reduction });
            end
        end
        for _, ladder in pairs(bySlot) do
            table.sort(ladder, function(a, b)
                if a.roll ~= b.roll then return a.roll > b.roll; end
                if a.reduction ~= b.reduction then return a.reduction > b.reduction; end
                if a.level ~= b.level then return a.level < b.level; end
                return a.name < b.name;
            end);
        end
    end
    return out;
end

function M.serialize(helm)
    local lines = { '    helm = { model = "extra-rolls", categories = {' };
    for _, category in ipairs(M.categories) do
        lines[#lines + 1] = '        ' .. category .. ' = {';
        for _, slot in ipairs(M.slots) do
            local ladder = helm.categories[category][slot];
            if ladder then
                local rungs = {};
                for _, rung in ipairs(ladder) do
                    rungs[#rungs + 1] = string.format('{ name = %q, level = %d, roll = %g, reduction = %g }',
                        rung.name, rung.level, rung.roll, rung.reduction);
                end
                lines[#lines + 1] = '            ' .. slot .. ' = { ' .. table.concat(rungs, ', ') .. ' },';
            end
        end
        lines[#lines + 1] = '        },';
    end
    lines[#lines + 1] = '    } },';
    return lines;
end

function M.preview(helm, category, level)
    if type(helm) ~= 'table' or helm.model ~= 'extra-rolls' or type(helm.categories) ~= 'table' then return nil; end
    local ladders = helm.categories[category];
    if type(ladders) ~= 'table' then return nil; end
    local out = {};
    for _, slot in ipairs(M.slots) do
        for _, rung in ipairs(ladders[slot] or {}) do
            if type(rung.name) == 'string' and (tonumber(rung.level) or 0) <= level then
                out[slot:gsub('^%l', string.upper)] = rung;
                break;
            end
        end
    end
    return out;
end

function M.bonuses(preview)
    if preview == nil then return nil; end
    local pack = require('dlac\\gear\\serverpack');
    local base = tonumber(pack.const('helmBreakBase'));
    if base == nil then return nil; end
    local out = { extraRoll = 0, breakReduction = 0 };
    for _, rung in pairs(preview) do
        out.extraRoll = out.extraRoll + (tonumber(rung.roll) or 0);
        out.breakReduction = out.breakReduction + (tonumber(rung.reduction) or 0);
    end
    out.breakChance = math.max(0, math.min(100, base - out.breakReduction));
    out.breakProof = out.breakChance == 0;
    return out;
end

function M.describe(bonuses)
    if bonuses == nil then return 'Open Gear Helpers to refresh gathering gear.'; end
    return string.format('Extra rolls +%g%%; tool break -%g pp; break on failed swing %g%%%s',
        bonuses.extraRoll, bonuses.breakReduction, bonuses.breakChance,
        bonuses.breakProof and ' (break-proof)' or '');
end

return M;
