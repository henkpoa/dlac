-- Run from the addon root: lua tests/ascensionxi_catalog.lua
-- Mount and flatten through the same runtime seam used by the pack gate.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel == nil then return nil; end
    return loadfile((rel:gsub('\\', '/')) .. '.lua');
end);
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
assert(sp.active() == 'ascensionxi');
local ci = require('dlac\\gear\\catalogindex');
local sd = dofile('gear/statdefs.lua');
local function item(id)
    return assert(ci.rawById(id), 'missing item ' .. tostring(id));
end

for id = 26547, 26563 do assert(item(id).Name ~= ''); end
assert(item(26549).Name == 'Rabbit Charm +1');
assert(item(26549).Stats.TreasureHunter == 1);
assert(item(27556).Name == 'Anchor Ring' and item(27556).Level == 15);
assert(item(14375).Level == 1 and item(14375).Stats.DEF == 2);
assert(item(26552).Stats.MiningExtraRoll == 40);
assert(item(26552).Stats.HelmBreakReduction == 10);
assert(item(26550).Stats.MiningExtraRoll == 10);
assert(item(26550).Stats.HelmBreakReduction == 5);
assert(item(13809).Stats.FishingSkill == 2 and item(13809).Stats.DEF == 2);
assert(item(26558).Stats.FishingSkill == 2);
assert(item(19788).Level == 75 and item(19788).Stats.DMG == 32);
assert(item(10792).Stats.CursnaReceived == 15);
assert(item(10577).Stats.ResistSilence == 1);
for _, key in ipairs({ 'HarvestingExtraRoll', 'LoggingExtraRoll', 'MiningExtraRoll', 'ExcavationExtraRoll' }) do
    assert(sd.byKey[key] and sd.get(key).percent == true);
end
assert(sd.get('HelmBreakReduction').percent ~= true);
assert(sd.get('HelmBreakReduction').lowerBetter ~= true);
print('OK -- AscensionXI custom catalog names, eligibility, stats and display units');
