-- Run from the addon root: lua tests/ascensionxi_guild_headgear.lua
-- The generated catalog must produce the same crafting bonuses as the server.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);

local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local _, byId = require('dlac\\gear\\catalogindex').flat();
local pick = require('dlac\\feature\\craftpick');
local pieces = {
    { 26576, 14830, 'Woodworking' }, { 26577, 14831, 'Smithing' },
    { 26578, 14832, 'Leathercraft' }, { 26579, 17058, 'Alchemy' },
};
local all = { 26570, 26571, 26574, 26573, 13945, 13946, 13947, 13948 };

local function owned(ids)
    local result = {};
    for _, id in ipairs(ids) do
        local rec = assert(byId[id], 'missing catalog record ' .. id);
        local skills = {};
        for _, craft in ipairs(pick.CRAFTS) do skills[craft] = rec.Stats[craft .. 'Skill'] or 0; end
        result[#result + 1] = { name = rec.Name, slot = string.lower(rec.Slot),
            level = rec.Level, n = 1, sk = skills, shield = rec.Slot == 'Sub' };
    end
    return result;
end

for _, piece in ipairs(pieces) do
    local new, old, craft = piece[1], piece[2], piece[3];
    assert(byId[new].Slot == 'Head');
    assert(byId[new].Stats[craft .. 'Skill'] == 1);
    assert(not byId[old].Stats[craft .. 'Skill'], 'retired skill must not inflate the planner');
    local chosen, info = pick.pick(owned({ new, old }), { [craft] = 50 }, { [craft] = 50 }, { level = 1 });
    assert(chosen.Head == byId[new].Name);
    assert(info.margins[craft] == 1);
    all[#all + 1], all[#all + 2] = new, old;
end

for _, craft in ipairs(pick.CRAFTS) do
    local chosen, info = pick.pick(owned(all), { [craft] = 50 }, { [craft] = 50 }, { level = 1 });
    assert(chosen.Head == "Artisan's Hat");
    assert(chosen.Hands == nil and chosen.Main == nil, 'retired pieces must not be selected');
    assert(info.margins[craft] == 10, craft .. ' must stay at +10');
end
print('OK -- four guild replacements and all eight completed crafting sets agree with the server');
