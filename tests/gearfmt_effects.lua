-- Run from the addon root: lua tests/gearfmt_effects.lua
local fmt = dofile('gear/gearfmt.lua');
local catalog = dofile('servers/ascensionxi/data/catalog.lua');
local function find(t, id)
    if t.Id == id then return t; end
    for _, v in pairs(t) do
        if type(v) == 'table' then
            local found = find(v, id);
            if found then return found; end
        end
    end
end
AshitaCore = { GetResourceManager = function()
    return { GetString = function(_, category, id)
        assert(category == 'buffs.names');
        return ({ [5] = 'Blind', [3] = 'Poison' })[id];
    end };
end };
local blind = assert(find(catalog, 18150));
local line = fmt.fullStatList(blind.Stats);
assert(line == 'Additional effect: Blind', line);
fmt.configure({ effStats = function(rec) return rec.Stats; end });
local summary = fmt.statSummary(blind, 75);
assert(summary:find('Additional effect: Blind', 1, true), summary);
assert(not summary:find('ITEM_', 1, true), summary);
assert(blind.Stats.ITEM_ADDEFFECT_CHANCE == 100, 'formatter mutated catalog');
assert(fmt.fullStatList({ Accuracy = 5, ITEM_ADDEFFECT_TYPE = 2,
    ITEM_ADDEFFECT_STATUS = 3 }) == 'Accuracy+5 Additional effect: Poison');
assert(fmt.fullStatList({ ITEM_ADDEFFECT_TYPE = 5, ITEM_SUBEFFECT = 1 })
    == 'Additional effect: HP drain');
AshitaCore = nil;
assert(fmt.fullStatList({ ITEM_ADDEFFECT_TYPE = 2, ITEM_ADDEFFECT_STATUS = 999 })
    == 'Additional effect: Status ailment');
assert(fmt.fullStatList({ ITEM_ADDEFFECT_SCRIPTED = 1 })
    == 'Additional effect: Special effect');
assert(fmt.fullStatList({ Accuracy = 5 }) == 'Accuracy+5');
print('OK -- readable additional effects');
