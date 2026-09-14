-- Run from the addon root: lua tests/custom_equipment.lua
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
ashita = { events = { register = function() end } };
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local sent = {};
local worn = false;
local resource = { Name = { 'Rabbit Charm +1' }, Level = 127,
    Jobs = 0x1FFFFE, Slots = 0x20, Flags = 0x8800 };
local inventory = {
    GetEquippedItem = function(_, slot) return { Index = worn and slot == 9 and 1 or 0 }; end,
    GetContainerCountMax = function(_, bag) return bag == 0 and 1 or 0; end,
    GetContainerItem = function(_, bag, index)
        if bag == 0 and index == 1 then return { Id = 26549, Count = 1, Flags = 0 }; end
    end,
};
local resources = { GetItemById = function() return resource; end };
local player = {
    GetMainJob = function() return 1; end,
    GetMainJobLevel = function() return 20; end,
    GetJobLevel = function() return 20; end,
};
AshitaCore = {
    GetMemoryManager = function() return {
        GetInventory = function() return inventory; end,
        GetPlayer = function() return player; end,
    }; end,
    GetResourceManager = function() return resources; end,
    GetPacketManager = function() return {
        AddOutgoingPacket = function(_, id, bytes) sent[#sent + 1] = { id = id, bytes = bytes }; end,
    }; end,
};
local engine = require('dlac\\feature\\equipengine');
engine.equipSet({ Neck = 'Rabbit Charm +1' });
engine.bufferFlush('single');
assert(#sent == 1, 'Rabbit Charm +1: repaired Neck/Lv7 set must send an equip for WAR20 despite Body/Lv127 resources');
assert(sent[1].id == 0x50);
assert(sent[1].bytes[5] == 1 and sent[1].bytes[6] == 9 and sent[1].bytes[7] == 0,
    'equip must target the Neck slot and the actual inventory instance');
local trust = assert(engine.currentEquipView(10));
assert(trust.Level == 7 and trust.Slots == 512 and trust.Jobs == 8388606);
engine.equipSet({ Neck = 'Rabbit Charm +1' }); engine.bufferFlush('single');
assert(#sent == 1, 'corrected trust view must prevent repeated equips');
worn = true;
engine = dofile('feature/equipengine.lua'); -- fresh engine, no trust window
local live = assert(engine.currentEquipView(10));
assert(live.Level == 7 and live.Slots == 512 and live.Jobs == 8388606);
engine.equipSet({ Neck = 'Rabbit Charm +1' }); engine.bufferFlush('single');
assert(#sent == 1, 'corrected live worn view must prevent repeated equips');
assert(resource.Level == 127 and resource.Slots == 32, 'never mutate Ashita resources');

-- The existing gates still apply after catalog metadata is resolved.
worn = false;
player.GetMainJobLevel = function() return 6; end;
player.GetJobLevel = player.GetMainJobLevel;
engine = dofile('feature/equipengine.lua');
engine.equipSet({ Neck = 'Rabbit Charm +1' }); engine.bufferFlush('single');
assert(#sent == 1, 'level 6 cannot equip the level 7 charm');
player.GetMainJobLevel = function() return 20; end;
player.GetJobLevel = player.GetMainJobLevel;
engine.state.disabled[10] = true;
engine.equipSet({ Neck = 'Rabbit Charm +1' }); engine.bufferFlush('single');
assert(#sent == 1, 'disabled slot must remain disabled');
engine.state.disabled[10] = nil;
engine.state.encumbered[10] = true;
engine.equipSet({ Neck = 'Rabbit Charm +1' }); engine.bufferFlush('single');
assert(#sent == 1, 'encumbered slot must remain blocked');

local records = require('dlac\\gear\\gearrecord');
local eq = require('dlac\\gear\\equipcore');
local facts = records.equipMetadata({ Slot = 'Neck', Level = 7, Jobs = { 'THF' } }, resource);
facts.ResFlags = resource.Flags;
assert(not eq.checkUsable(facts, 1, 20) and eq.checkUsable(facts, 6, 7), 'catalog job gate');
local unknown = records.equipMetadata(nil, resource);
assert(unknown.Level == 127 and unknown.Slots == 32 and unknown.Jobs == resource.Jobs);
assert(records.equipMetadata({ Slot = 'Main' }, { Slots = 3 }).Slots == 3);
assert(records.equipMetadata({ Slot = 'Ring' }, { Slots = 24576 }).Slots == 24576);

local ci = require('dlac\\gear\\catalogindex');
local realFlat = ci.flat;
ci.flat = function() return {}, {}; end;
engine = dofile('feature/equipengine.lua');
engine.equipSet({ Neck = 'Rabbit Charm +1' }); engine.bufferFlush('single');
assert(#sent == 1, 'without a catalog, the original resource level and slot gates still apply');
worn = true;
assert(engine.currentEquipView(10).Level == 127, 'catalog-less worn view retains resource facts');
worn = false;
ci.flat = realFlat;
resource.Flags = 0;
engine.equipSet({ Neck = 'Rabbit Charm +1' }); engine.bufferFlush('single');
assert(#sent == 1, 'catalog correction must not override the resource equippable flag');
resource.Flags = 0x8800;

-- A second custom ID uses the same path, without any per-item engine rule.
local originalItem = inventory.GetContainerItem;
inventory.GetContainerCountMax = function(_, bag) return bag == 0 and 2 or 0; end;
inventory.GetContainerItem = function(self, bag, index)
    if bag == 0 and index == 2 then return { Id = 26550, Count = 1, Flags = 0 }; end
    return originalItem(self, bag, index);
end;
local capResource = { Name = { 'Field Cap' }, Level = 127,
    Slots = 32, Jobs = 0x1FFFFE, Flags = 0xF852 };
resources.GetItemById = function(_, id) return id == 26550 and capResource or resource; end;
engine = dofile('feature/equipengine.lua');
engine.equipSet({ Head = 'Field Cap' }); engine.bufferFlush('single');
assert(#sent == 2 and sent[2].bytes[5] == 2 and sent[2].bytes[6] == 4,
    'Field Cap must equip in Head through the same catalog rule');
assert(engine.currentEquipView(5).Level == 1);

-- Drive the actual Sets picker with repaired ownership and live bag counts.
package.loaded['bit'] = { band = function(a,b) return a & b; end,
    bor = function(a,b) return a | b; end, rshift = function(a,b) return a >> b; end,
    lshift = function(a,b) return a << b; end, bnot = function(a) return ~a; end };
local charm = { Name = 'Rabbit Charm +1', Id = 26549, Level = 7, Jobs = { 'All' } };
local cap = { Name = 'Field Cap', Id = 26550, Level = 1, Jobs = { 'All' } };
package.loaded['dlac\\gear'] = { Neck = { RabbitCharm_1 = charm },
    Head = { FieldCap = cap }, NameToObject = { ['Rabbit Charm +1'] = charm, ['Field Cap'] = cap } };
require('dlac\\ui\\gearui');
local host = require('dlac\\ui\\uihost');
local deps = host.services;
local found = false;
for _, rec in ipairs(deps.candidatesForSlot('Neck', 'WAR', 20)) do
    if rec.Id == 26549 then found = true; end
end
assert(found, 'repaired Rabbit Charm +1 must appear in the WAR20 Neck picker');
found = false;
for _, rec in ipairs(deps.candidatesForSlot('Head', 'WAR', 20)) do
    if rec.Id == 26550 then found = true; end
end
assert(found, 'repaired Field Cap must appear in the WAR20 Head picker');
print('OK -- custom equipment through the native snapshot and equip pipeline');
