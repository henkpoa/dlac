-- Run from the addon root: lua tests/idle_weapon_report.lua
-- Abraxis's report selects the sickle but sends no equip on standing up.
-- Replay the native boundary to distinguish valid and stale client resources.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
ashita = { events = { register = function() end } };
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local resources = {
    [19977] = { Name = { 'Rekindled Sickle' }, Level = 10, Jobs = 16, Slots = 1, Flags = 0xF840 },
    [18610] = { Name = { 'Spiro Staff' }, Level = 29, Jobs = 16, Slots = 1, Flags = 0xF840 },
};
local sent, worn = {}, 1;
local inventory = {
    GetEquippedItem = function(_, slot) return { Index = slot == 0 and worn or 0 }; end,
    GetContainerCountMax = function(_, bag) return bag == 0 and 2 or 0; end,
    GetContainerItem = function(_, bag, index)
        if bag == 0 and (index == 1 or index == 2) then
            return { Id = index == 1 and 19977 or 18610, Count = 1, Flags = 0 };
        end
    end,
};
local player = { GetMainJob = function() return 4; end,
    GetMainJobLevel = function() return 75; end, GetJobLevel = function() return 75; end };
AshitaCore = {
    GetMemoryManager = function() return { GetInventory = function() return inventory; end,
        GetPlayer = function() return player; end }; end,
    GetResourceManager = function() return { GetItemById = function(_, id) return resources[id]; end }; end,
    GetPacketManager = function() return { AddOutgoingPacket = function(_, id, bytes)
        sent[#sent + 1] = { id = id, bytes = bytes };
    end }; end,
};
local function equip(name)
    -- Fresh engine bypasses the 0.2s trust window, as the report's four-second rest does.
    local engine = dofile('feature/equipengine.lua');
    sent = {};
    engine.equipSet({ Main = name }); engine.bufferFlush('single');
    return #sent;
end
assert(equip('Spiro Staff') == 1, 'resting must equip the staff');
worn = 2;
assert(equip('Rekindled Sickle') == 1, 'valid sickle resources must restore idle weapon');
assert(sent[1].id == 0x50 and sent[1].bytes[5] == 1 and sent[1].bytes[6] == 0);
resources[19977].Name[1] = '.';
assert(equip('Rekindled Sickle') == 0, 'placeholder name reproduces the missing idle equip');
resources[19977].Name[1] = 'Rekindled Sickle';
resources[19977].Flags = 0xF040;
resources[19977].Level = 255;
resources[19977].Jobs = 0;
resources[19977].Slots = 3;
assert(equip('Rekindled Sickle') == 1, 'Abraxis resource fixture: catalog equipment must restore the sickle');
assert(sent[1].bytes[5] == 1 and sent[1].bytes[6] == 0, 'restore the actual sickle in Main');
local engine = dofile('feature/equipengine.lua');
engine.equipSet({ Main = 'Rekindled Sickle' }); engine.bufferFlush('single');
assert(engine.currentEquipView(1).ResFlags == 0xF840, 'trust view uses corrected equip flag');
local count = #sent;
engine.equipSet({ Main = 'Rekindled Sickle' }); engine.bufferFlush('single');
assert(#sent == count, 'trust view prevents repeated equip');
worn = 1;
assert(equip('Rekindled Sickle') == 0, 'live worn view prevents repeated equip');
assert(resources[19977].Flags == 0xF040, 'shared client resource must remain untouched');
worn = 2;
player.GetMainJob = function() return 1; end;
assert(equip('Rekindled Sickle') == 0, 'catalog BLM job restriction still applies');
player.GetMainJob = function() return 4; end;
player.GetMainJobLevel = function() return 9; end;
player.GetJobLevel = player.GetMainJobLevel;
assert(equip('Rekindled Sickle') == 0, 'catalog level 10 restriction still applies');
player.GetMainJobLevel = function() return 75; end;
player.GetJobLevel = player.GetMainJobLevel;
local ci = require('dlac\\gear\\catalogindex');
local realFlat = ci.flat;
ci.flat = function() return {}, {}; end;
assert(equip('Rekindled Sickle') == 0, 'catalog-less resources retain their original gate');
ci.flat = realFlat;

local report = dofile('feature/report.lua');
local byName = { ['Rekindled Sickle'] = { Id = 19977, Level = 10, Jobs = { 'BLM' } } };
local function lines(resourceFn)
    return table.concat(report._digestLines({ ['Rekindled Sickle'] = true }, byName,
        function() return true; end, 75, resourceFn), '\n');
end
local out = lines(function(id) assert(id == 19977); return resources[id]; end);
assert(out:find('equippable=false', 1, true), 'support report must expose the native resource flag rejection');
resources[19977].Name[1] = '.';
out = lines(function(id) return resources[id]; end);
assert(out:find('NAME MISMATCH', 1, true), 'support report must expose the native resource name mismatch');
assert(out:find('IN BAGS', 1, true), 'resource diagnostics must coexist with ID-based ownership');
assert(lines(function() error('unavailable'); end):find('resource unavailable', 1, true));
assert(not lines(nil):find('resource', 1, true), 'legacy/headless caller remains supported');
print('OK -- idle weapon replay and resource diagnostics');
