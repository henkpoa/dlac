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
local gathering = require('dlac\\gear\\gathering');
assert(gathering.enabled());
local _, byId = ci.flat();
local sets = {
    { ids = { 14374, 14817, 14297, 14176, 26550 }, roll = 50, reduction = 25, chance = 25 },
    { ids = { 14375, 14818, 14298, 14177, 26551 }, roll = 100, reduction = 50, chance = 0 },
    { ids = { 26552, 26553, 26554, 26555, 26556 }, roll = 200, reduction = 50, chance = 0 },
};
local owned = {};
for _, set in ipairs(sets) do
    local records = {};
    for _, id in ipairs(set.ids) do
        records[#records + 1] = assert(byId[id]);
        owned[#owned + 1] = byId[id];
    end
    for _, category in ipairs(gathering.categories) do
        local b = gathering.bonuses(gathering.preview(gathering.build(records), category, 1));
        assert(b.extraRoll == set.roll and b.breakReduction == set.reduction and b.breakChance == set.chance,
            category .. ' full-set bonus mismatch');
    end
end
local best = gathering.preview(gathering.build(owned), 'Excavation', 1);
assert(best.Head.name == 'Worker Cap +1');
assert(best.Body.name == 'Worker Tunica +1');
assert(gathering.bonuses(best).breakProof);

-- Import through the real bag/vault scan and serialize the result. The
-- reporter's resource-derived fields were Body/Lv127/20 jobs even though
-- this pack already carried the correct Neck/Lv7/All record.
package.loaded['dlac\\gear'] = { NameToObject = {} };
ashita = { events = { register = function() end } };
bit = {
    band = function(a, b)
        local out, place = 0, 1;
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then out = out + place; end
            a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2;
        end
        return out;
    end,
    rshift = function(a, n) return math.floor(a / 2 ^ n); end,
};
local resources = {
    [26549] = { Name = { 'Rabbit Charm +1' }, LogNameSingular = { 'rabbit charm +1' },
        Slots = 0x20, Level = 127, Jobs = 0x1FFFFE, Flags = 0xC800 },
    [26550] = { Name = { 'Field Cap' }, Slots = 0x20, Level = 127, Jobs = 0x1FFFFE },
    [27556] = { Name = { 'Anchor Ring' }, Slots = 0x6000, Level = 1, Jobs = 0x7FFFFE },
    [13112] = { Name = { 'Rabbit Charm' }, Slots = 0x200, Level = 7, Jobs = 0x7FFFFE },
    [16714] = { Name = { 'Neckchopper' }, Slots = 3, Level = 127, Jobs = 2,
        Skill = 2, Damage = 1, Delay = 1 },
    [17389] = { Name = { 'Bamboo Fish. Rod' }, Slots = 0x20, Level = 127, Jobs = 2, Skill = 0 },
    [17859] = { Name = { 'Animator' }, Slots = 0x4, Level = 1, Jobs = 0x7FFFFE, Skill = 0 },
    [65534] = { Name = { 'Uncatalogued Boots' }, Slots = 0x100, Level = 12, Jobs = 2 },
    [65533] = { Name = { 'Not Gear' }, Slots = 0, Level = 0 },
};
local extra = string.rep('\0', 24);
local bag = { { Id = 26549, Extra = extra } };
local vault = {};
sp.provide('gearvault', { rows = function() return vault; end });
AshitaCore = {
    GetMemoryManager = function() return { GetInventory = function() return {
        GetContainerCountMax = function(_, cid) return cid == 0 and #bag or 0; end,
        GetContainerItem = function(_, cid, idx) return cid == 0 and bag[idx] or nil; end,
    }; end }; end,
    GetResourceManager = function() return {
        GetItemById = function(_, id) return resources[id]; end,
    }; end,
};
gData = { GetAugment = function(entry)
    assert(entry.Extra == extra, 'scan must preserve instance extra bytes');
    return { Type = 'Augmented', Augs = { { Stat = 'DEX', Value = 1 } } };
end };
local gi = require('dlac\\gear\\gearimport');
local function saved(rec)
    local e = assert(gi.renderEntry(rec));
    local t = assert((loadstring or load)('return { ' .. e.lua .. ' }'))();
    return t[e.key], table.concat(e.path, '.');
end
local function charm(rec, source)
    assert(rec and rec.Id == 26549, source .. ': missing charm');
    assert(rec.Slot == 'Neck', source .. ': Rabbit Charm +1 imported as ' .. tostring(rec.Slot));
    assert(rec.Level == 7, source .. ': expected Lv7, got ' .. tostring(rec.Level));
    assert(rec.Slots == 0x200 and rec.Jobs == 0x7FFFFE, source .. ': wrong equipment masks');
    assert(rec.Name == 'Rabbit Charm +1' and rec.FullName == 'rabbit charm +1');
    assert(rec.Flags == 0xC800 and rec.Augment.Augs[1].Value == 1);
    local r, path = saved(rec);
    assert(path == 'Neck' and r.Level == 7 and r.Jobs[1] == 'All' and #r.Jobs == 1,
        source .. ': serialized gear must use catalog eligibility');
end
charm(gi.scan({ 0 })[1], 'bag');
bag = {};
vault = { { itemId = 26549, qty = 1, identity = extra } };
charm(gi.scan()[1], 'vault');
assert(#gi.scan({ 0 }) == 0, 'explicit bag scan must still exclude vault rows');

-- A catalogued custom item can occupy a resource slot marked non-equippable.
resources[26549].Slots = 0;
charm(gi.scan()[1], 'zero-slot resource');
resources[26549].Slots = 0x20;
vault = {};
for _, id in ipairs({ 26550, 27556, 13112, 65534, 65533 }) do
    bag = { { Id = id, Extra = extra } };
    local found = gi.scan({ 0 });
    if id == 65533 then
        assert(#found == 0, 'non-equipment absent from catalog must stay excluded');
    else
        local r, path = saved(assert(found[1]));
        if id == 26550 then
            assert(path == 'Head' and r.Level == 1 and #r.Jobs == 1 and r.Jobs[1] == 'All',
                'Field Cap must import as Head/Lv1/All, not the Body/Lv127 placeholder');
            assert(found[1].Slots == 0x10);
        elseif id == 27556 then
            assert(path == 'Ring' and r.Level == 15, 'Anchor Ring must import the server level');
            assert(found[1].Slots == 0x6000, 'retain combined ring slot mask');
        elseif id == 13112 then
            assert(path == 'Neck' and #r.Jobs == 1 and r.Jobs[1] == 'THF',
                'catalog job subsets must use client job-bit numbering');
        else
            assert(path == 'Feet' and r.Level == 12 and #r.Jobs == 1 and r.Jobs[1] == 'WAR',
                'unknown items must retain resource metadata');
        end
    end
end

-- Slot corrections must retain the nested gear.lua shape and weapon pairing
-- facts. The catalog also permits flat, skill-0 Range records (animators).
for _, case in ipairs({
    { id = 16714, path = 'Main.GreatAxe', type = 'GreatAxe', oneHanded = false },
    { id = 17389, path = 'Range.FishingRod', type = 'FishingRod' },
    { id = 17859, path = 'Range.PUP', type = 'PUP' },
}) do
    bag = { { Id = case.id, Extra = extra } };
    local rec = gi.scan({ 0 })[1];
    local r, path = saved(assert(rec));
    assert(path == case.path and r.Type == case.type, 'wrong nested import for ' .. case.id);
    assert(r.OneHanded == case.oneHanded, 'wrong handedness for ' .. case.id);
    if case.id == 16714 then assert(rec.Slots == 3, 'retain matching Main/Sub resource mask'); end
end

-- No catalog: the original resource import remains usable.
local realFlat = ci.flat;
ci.flat = function() return {}, {}, {}; end;
bag = { { Id = 26549, Extra = extra } };
local fallback = gi.scan({ 0 })[1];
assert(fallback.Slot == 'Body' and fallback.Level == 127 and fallback.Jobs == 0x1FFFFE);
ci.flat = realFlat;
print('OK -- AscensionXI custom catalog names, eligibility, stats and display units');
