--[[
    bludex/lib/setmodel.lua -- the set being edited and everything computable
    from it: point/MP totals, aggregated stat bonuses, and the trait ladder
    evaluation (the same math as the server's blueutils CalculateTraits: sum
    trait weights per category across set spells, highest tier with
    points <= total is active).

    Pure logic; no AshitaCore, no imgui. A "set" is { name = s, ids = {20} }
    with real spell ids (0 = empty slot).
]]--

local M = {};

function M.new(name)
    local ids = {};
    for i = 1, 20 do ids[i] = 0; end
    return { name = name or 'New Set', ids = ids };
end

function M.clone(set, name)
    local c = M.new(name or (set.name .. ' copy'));
    for i = 1, 20 do c.ids[i] = set.ids[i] or 0; end
    return c;
end

function M.count(set)
    local n = 0;
    for i = 1, 20 do if (set.ids[i] or 0) ~= 0 then n = n + 1; end end
    return n;
end

function M.contains(set, id)
    for i = 1, 20 do if set.ids[i] == id then return i; end end
    return nil;
end

function M.freeSlot(set)
    for i = 1, 20 do if (set.ids[i] or 0) == 0 then return i; end end
    return nil;
end

function M.usedPoints(set, book)
    local n = 0;
    for i = 1, 20 do
        local s = book.spells[set.ids[i] or 0];
        if s and s.setPoints then n = n + s.setPoints; end
    end
    return n;
end

function M.usedMP(set, book)
    local n = 0;
    for i = 1, 20 do
        local s = book.spells[set.ids[i] or 0];
        if s and s.mpCost then n = n + s.mpCost; end
    end
    return n;
end

-- Can this spell go into the set? Returns ok, reason.
function M.canAdd(set, id, book, budgetMax)
    local s = book.spells[id];
    if s == nil then return false, 'unknown spell'; end
    if not s.castable then return false, 'not castable at 75'; end
    if s.unbridled then return false, 'Unbridled spells cannot be set'; end
    if not book.learned(id) then return false, 'not learned'; end
    if s.setPoints == nil then return false, 'set cost unknown'; end
    if M.contains(set, id) then return false, 'already in set'; end
    if M.freeSlot(set) == nil then return false, 'no free slot'; end
    if budgetMax and budgetMax > 0
        and M.usedPoints(set, book) + s.setPoints > budgetMax then
        return false, 'over the point budget';
    end
    return true;
end

function M.add(set, id, book, budgetMax)
    local ok, reason = M.canAdd(set, id, book, budgetMax);
    if not ok then return false, reason; end
    set.ids[M.freeSlot(set)] = id;
    return true;
end

function M.removeSlot(set, i)
    if i >= 1 and i <= 20 then set.ids[i] = 0; end
end

function M.removeId(set, id)
    local i = M.contains(set, id);
    if i then set.ids[i] = 0; end
end

function M.clear(set)
    for i = 1, 20 do set.ids[i] = 0; end
end

-- The APPLY layout (field 2026-08-04: the game's own set list should read
-- in level order): the set's learned spells sorted ascending by spell level
-- (ties by id) into slots 1..n, zeros after. This is exactly what applyDiff
-- sends and what the Apply-dirty compare measures -- low spells sit in the
-- low slots a level-down spares.
function M.sortedLayout(ids, book)
    local pick = {};
    for i = 1, 20 do
        local id = ids[i] or 0;
        if id ~= 0 and book.spells[id] ~= nil and book.learned(id) then
            pick[#pick + 1] = id;
        end
    end
    table.sort(pick, function(a, b)
        local la = book.spells[a].level or 999;
        local lb = book.spells[b].level or 999;
        if la ~= lb then return la < lb; end
        return a < b;
    end);
    local T = {};
    for i = 1, 20 do T[i] = pick[i] or 0; end
    return T;
end

-- The server's set-slot count for a BLU level (blueutils GetTotalSlots):
-- 6 slots through level 10, +2 every 10 levels after, capped at 20.
function M.slotsAtLevel(level)
    if level == nil or level < 1 then return 0; end
    local n = math.floor((level - 1) / 10) * 2 + 6;
    if n < 6 then n = 6; end
    if n > 20 then n = 20; end
    return n;
end

-- 'DUAL_WIELD' -> 'Dual Wield', 'MND' stays 'MND' (<=4 chars = stat acronym)
function M.prettyStat(s)
    if #s <= 4 and not s:find('_') then return s; end
    return (s:lower():gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b)
        return a:upper() .. b;
    end));
end

-- Aggregate always-on stat bonuses from the set's spells:
-- returns sorted array of { stat = 'STR', value = 5 }.
function M.stats(set, book)
    local sum, order = {}, {};
    for i = 1, 20 do
        local s = book.spells[set.ids[i] or 0];
        if s and s.mods then
            for _, m in ipairs(s.mods) do
                if sum[m.stat] == nil then
                    sum[m.stat] = 0;
                    order[#order + 1] = m.stat;
                end
                sum[m.stat] = sum[m.stat] + m.value;
            end
        end
    end
    local out = {};
    for _, stat in ipairs(order) do
        if sum[stat] ~= 0 then out[#out + 1] = { stat = stat, value = sum[stat] }; end
    end
    return out;
end

-- Trait evaluation for the set. Returns sorted array of:
--   { cat, name, weight,           -- total weight the set feeds this category
--     tier,                        -- the active tier table or nil (below tier 1)
--     tierText,                    -- 'Dual Wield +10' style, or nil
--     nextPoints, nextText }       -- what the next tier needs, nil at cap
function M.traitEval(set, book)
    local weights, order = {}, {};
    for i = 1, 20 do
        local s = book.spells[set.ids[i] or 0];
        if s and s.trait then
            local c = s.trait.category;
            if weights[c] == nil then weights[c] = 0; order[#order + 1] = c; end
            weights[c] = weights[c] + (s.trait.weight or 0);
        end
    end
    local out = {};
    for _, cat in ipairs(order) do
        local info = book.traits.categories[cat];
        local total = weights[cat];
        local active, nextTier = nil, nil;
        if info then
            for _, tier in ipairs(info.tiers) do
                if total >= tier.points then
                    active = tier;
                elseif nextTier == nil then
                    nextTier = tier;
                end
            end
        end
        local function tierText(tier)
            if tier == nil then return nil; end
            local parts = {};
            for _, m in ipairs(tier.mods) do
                parts[#parts + 1] = ('%s %+d'):format(M.prettyStat(m.stat), m.value);
            end
            return table.concat(parts, ', ');
        end
        out[#out + 1] = {
            cat = cat,
            name = (info and info.name) or ('Trait ' .. cat),
            weight = total,
            tier = active,
            tierText = tierText(active),
            nextPoints = nextTier and nextTier.points or nil,
            nextText = tierText(nextTier),
        };
    end
    table.sort(out, function(a, b) return a.name < b.name; end);
    return out;
end

return M;
