-- Filter once per changed snapshot/search, then visit only the viewport's rows.
local M = {};
local last, visible, names = {}, {}, {};
function M.cards(catalog, state, search, form, ownership)
    if last.catalog == catalog and last.state == state and last.search == search and
        last.form == form and last.ownership == ownership then return visible; end
    if last.catalog ~= catalog then
        names = {};
        for id, entry in ipairs(catalog) do names[id] = (entry.name .. ' ' .. entry.family):lower(); end
    end
    last = { catalog = catalog, state = state, search = search, form = form, ownership = ownership };
    visible = {};
    local needle = search:lower();
    for id = 2, #catalog * 2 + 1 do
        local pet, shiny = state.owned[id], id % 2 == 1;
        local showForm = form == 'all' and (not shiny or pet or ownership == 'missing') or
            form == 'shiny' and shiny or form == 'regular' and not shiny;
        local showOwnership = ownership == 'all' or ownership == 'owned' and pet or ownership == 'missing' and not pet;
        if showForm and showOwnership and
            (names[math.floor(id / 2)] .. ' ' .. (pet and pet.name or ''):lower()):find(needle, 1, true) then
            visible[#visible + 1] = id;
        end
    end
    return visible;
end

function M.rows(count, columns, height, scroll, viewport, origin)
    local total = math.ceil(count / columns);
    local first = math.min(total, math.max(0, math.floor((scroll - origin) / height)));
    local lastRow = math.min(total, math.ceil((scroll - origin + viewport) / height) + 1);
    return math.min(first, total), math.max(first, lastRow), total;
end
return M;
