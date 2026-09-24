-- lua tests/void_restock.lua -- headless planner, wire, controller and UI checks.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
ashita = { events = { register = function() end } };
local base = 'dlac\\servers\\ascensionxi\\modules\\voidrestock\\';
local model = require(base .. 'model');
local membership = require(base .. 'membership');
assert(membership.canStore(605, nil), 'HELM tool exception is base storage');
assert(not membership.canStore(50001, 127), 'non-member rejected even with every tier');
assert(not membership.canStore(17330, 1) and membership.canStore(17330, 33), 'ammo requires its KI tier');
assert(not membership.canStore(3757, 1) and membership.canStore(3757, 65), 'Onslaught overrides crafting category');
assert(membership.data.tiers[6].keyItem == 3590, 'current Onslaught KI');
for tier, info in pairs(membership.data.tiers) do
    local id = membership.data.itemsByTier[tier][1];
    assert(not membership.canStore(id, 1) and membership.canStore(id, 1 + 2 ^ tier), info.label);
end
local config = model.normalize({ character = {
    { id = 1, name = 'Oil', target = 12 }, { id = 2, name = 'Powder', target = 6 },
}, jobs = { NIN = { { id = 1, name = 'Oil', target = 24 }, { id = 3, name = 'Tool', target = 0 } } } });
local nin, war = model.effective(config, 'NIN'), model.effective(config, 'WAR');
assert(#nin == 3 and nin[1].target == 24 and nin[2].target == 0);
assert(#war == 2 and war[1].target == 12, 'other-job list must not participate');
local p = model.plan(nin, { [1] = 36, [2] = 1, [3] = 5, [99] = 999 }, { [2] = 20 }, 1, function() return 12; end);
assert(#p.store == 2 and p.store[1].id == 1 and p.store[1].qty == 12);
assert(p.store[2].id == 3 and p.store[2].qty == 5, 'zero target stores listed copies');
assert(#p.fetch == 1 and p.fetch[1].qty == 5);
assert(#model.plan(war, { [99] = 999 }, {}, 0, function() return 12; end).store == 0);
assert(#model.plan(nin, {}, { [1] = 999 }, 0, function() return 12; end).fetch == 0);
p = model.plan(nin, {}, { [1] = 999, [2] = 999 }, 1, function() return 12; end);
assert(#p.fetch == 1 and p.fetch[1].qty == 12, 'job first; fresh-slot budget clamps withdrawal');
local roundtrip = assert((loadstring or load)(model.serialize(config)))();
assert(roundtrip.jobs.NIN[1].target == 24 and #roundtrip.character == 2);
assert(#model.normalize({ character = { { id = 1, name = 'x', target = -1 }, { id = 1, name = 'x' } } }).character == 1);

local client = require(base .. 'client');
local now, packets, denied = 0, {}, false;
client._clock = function() return now; end;
client._received = function() end;
client._send = function(packet)
    if denied then return false; end
    packets[#packets + 1] = packet; return true;
end;
local function w16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function w32(n) return w16(n % 65536) .. w16(math.floor(n / 65536)); end
local function frame(req, payload, status, flags)
    local size = 8 + #payload;
    local data = w16(0x1E0 + math.ceil(size / 4) * 512) .. w16(0)
        .. string.char(req[5], req[6], status or 0, flags or 0) .. payload;
    return data .. string.rep('\0', (4 - #data % 4) % 4);
end
local function last() return packets[#packets]; end
local function hello()
    client.tick(); assert(last()[5] == 0);
    assert(client.onPacket(frame(last(), w16(1) .. w16(0) .. w32(1) .. string.char(61, 124) .. w16(0))));
end
local function page(rows, more)
    local req = last(); local data = w16(#rows) .. w16(0);
    for _, row in ipairs(rows) do data = data .. w16(row[1]) .. w16(0) .. w32(row[2]); end
    return client.onPacket(frame(req, data, 0, more and 1 or 0));
end
local function ready()
    client.reset(); assert(client.refresh()); hello(); client.tick();
    assert(last()[5] == 4); page({ { 1, 100 }, { 2, 200 } }); assert(client.fresh);
end
client.refresh(); denied = true; client.tick(); assert(#packets == 0 and client.busy());
denied = false; hello(); client.tick(); page({ { 1, 70000 } }, true);
assert(not client.fresh and client.counts[1] == nil, 'partial reads must not publish');
client.tick(); assert(last()[9] == 1, 'next page starts after the last id'); page({ { 2, 200 } });
assert(client.fresh and client.counts[1] == 70000, 'stored quantities are u32');
assert(not client.onPacket(frame({ [5] = 0x40, [6] = 1 }, '')), 'vault partition is untouched');
assert(not client.onPacket(frame({ [5] = 0x80, [6] = 1 }, '')), 'HELM partition is untouched');
local function ack(id, qty, moved, reason)
    return frame(last(), w16(1) .. w16(0) .. w32(0) .. w16(id) .. w16(qty) .. w16(moved) .. w16(reason or 0));
end
local result, calls = nil, 0;
assert(not client.move('store', 1, 0), 'zero-count sweep is unreachable');
assert(not client.move('store', 1, 65536), 'qty must fit u16');
assert(client.move('store', 1, 12, function(r) calls = calls + 1; result = r; end));
assert(last()[5] == 1 and last()[9] == 1 and last()[13] == 1 and last()[15] == 12);
local reply = ack(1, 12, 12);
client.onPacket(reply); client.onPacket(reply);
assert(result.moved == 12 and calls == 1 and client.counts[1] == 70012, 'duplicate ACK ignored');
client.move('fetch', 1, 12, function(r) result = r; end); client.onPacket(ack(1, 12, 3, 5));
assert(result.moved == 3 and result.reason == 5 and client.counts[1] == 70009);
local count = #packets;
client.move('fetch', 1, 1, function(r, err) result = err; end); now = now + 7; client.tick(); client.tick();
assert(#packets == count + 1 and not client.fresh and type(result) == 'string', 'timeout never repeats a move');
ready(); client.move('store', 1, 5); client.onPacket(ack(2, 5, 5));
assert(not client.fresh and not client.busy(), 'mismatched ACK cannot complete a move');
ready(); assert(client.tierMask == 1);
client.refresh(); client.tick(); assert(last()[5] == 0, 'refresh re-reads tier unlocks');
client.onPacket(frame(last(), w16(1) .. w16(0) .. w32(65) .. string.char(61, 124) .. w16(0)));
client.tick(); page({ { 1, 100 } }); assert(client.tierMask == 65, 'new Onslaught KI is reflected');
client.reset(); assert(client.tierMask == nil, 'tier permissions do not leak across characters');
client.reset(); client.refresh(); client.tick(); client.onPacket(frame(last(), '', 7));
assert(not client.fresh and client.message:find('unlocked'), 'attunement refusal surfaced');
client.reset(); client.refresh(); hello(); client.tick(); page({}, true);
assert(not client.busy() and not client.fresh, 'empty continuation cannot loop');
client.reset(); client.refresh(); hello(); client.tick(); page({ { 1, 4 } }, true); client.tick(); page({ { 1, 5 } });
assert(not client.fresh, 'non-advancing cursor rejected');

-- Real controller, injected world; no player files or packets are touched.
local restock = require(base .. 'restock');
local watcher = require('dlac\\lib\\entwatch');
local probeName, distance = 'Void Storage ', 9;
local probe = { present = function(i) return i == 0x802; end,
    name = function() return probeName; end, distSq = function() return distance; end };
restock.near(); watcher._sweep(probe, os.clock());
assert(restock.near(), 'live Void Storage portal must enable proximity and tray');
distance = 36; watcher._sweep(probe, os.clock() + 3);
assert(not restock.near(), 'portal beyond 5 yalms stays out of range');
probeName, distance = 'Void Coffer', 9; watcher._sweep(probe, os.clock() + 6);
assert(restock.near(), 'legacy Void Coffer still works');
probeName = 'Other Portal'; watcher._sweep(probe, os.clock() + 9);
assert(not restock.near(), 'unrelated portals never enable storage');
watcher.unwatch('voidrestock');
local realItem = restock.item;
local oldCore = AshitaCore;
AshitaCore = { GetResourceManager = function() return { GetItemById = function(_, id)
    return ({ [50001] = { Name = { 'Sword' }, Slots = 1, StackSize = 1 },
        [17330] = { Name = { 'Ammo' }, Slots = 8, StackSize = 99 },
        [605] = { Name = { 'Oil' }, Slots = 0, StackSize = 12 } })[id];
end, GetItemByName = function() return { Id = 50001 }; end }; end };
local resourceCore = AshitaCore;
assert(realItem(50001).restockable == false, 'gear pieces must not be restock candidates');
client.tierMask = 33;
assert(realItem(17330).restockable == true, 'unlocked ammo remains a restock candidate');
assert(realItem(605).restockable == true, 'base supplies remain restock candidates');
AshitaCore = oldCore;
local contextJob, nearby, inventory = 'NIN', false, { [1] = 36, [2] = 6, [3] = 5, [99] = 999 };
restock._context = function() return 'tests/fixtures/void-restock-no-character/', contextJob; end;
restock._clock = client._clock;
restock.near = function() return nearby; end;
restock.inventory = function() return inventory, 8; end;
restock.item = function(id) return { id = id, name = 'Item' .. id, stack = 12, restockable = true, storable = true }; end;
restock.syncContext(); restock.config = config; restock.tick();
nearby = true; restock.tick(); assert(client.busy(), 'coffer approach refreshes, never moves');
hello(); client.tick(); page({ { 1, 100 }, { 2, 200 } });
assert(restock.start('store')); restock.tick(); assert(last()[5] == 1 and last()[15] == 12);
local move = last(); client.onPacket(ack(1, 12, 12));
restock.tick(); assert(last() == move, 'wait for inventory packet before another item');
inventory[1] = 24; restock.tick(); assert(last()[13] == 3 and last()[15] == 5);
client.onPacket(ack(3, 5, 5)); inventory[3] = nil; restock.tick();
assert(not restock.busy() and restock.message:find('17 units stored'));
assert(inventory[99] == 999, 'unlisted copies remain untouched');
inventory[1] = 36; restock.start('store'); contextJob = 'WAR'; count = #packets; restock.tick();
assert(#packets == count and not restock.busy(), 'job change cancels queued deposits');
contextJob = 'NIN'; restock.tick(); restock.start('store'); restock.tick();
client.onPacket(ack(1, 12, 4, 3)); inventory[1] = 32; restock.tick();
assert(not restock.busy() and restock.message:find('4/12'), 'partial moves stop the run');
restock.start('store'); nearby = false; count = #packets; restock.tick();
assert(#packets == count and not restock.busy(), 'leaving coffer cancels unsent work');
nearby = true; restock.tick(); -- approach read
hello(); client.tick(); page({ { 1, 100 } });
restock.start('store'); restock.tick(); restock.stop(); client.onPacket(ack(1, 8, 8));
assert(not restock.start('store'), 'Stop does not bypass an in-flight inventory settlement');
inventory[1] = 24; restock.tick(); assert(not restock.busy());
inventory[1] = 36;
restock.start('store'); restock.zone(); count = #packets; nearby = false; restock.tick();
assert(#packets == count and not restock.busy(), 'zone cancels queued work');

-- Actual AXI helper registration and panel render with the headless binding.
local helpers, tray, handlers = {}, {}, {};
package.loaded['imgui'] = setmetatable({}, { __index = function(_, key)
    return function() if key == 'IsItemHovered' or key == 'IsMouseClicked' then return false; end end;
end });
package.loaded['dlac\\ui\\automationsui'] = { registerHelper = function(spec) helpers[#helpers + 1] = spec; end };
package.loaded['dlac\\ui\\tray'] = { register = function(spec) tray[#tray + 1] = spec; end };
ashita.events.register = function(_, name, callback) handlers[name] = callback; end;
require(base .. 'init');
assert(#helpers == 1 and helpers[1].row().name == 'Void Restock' and #tray == 1);
assert(dofile('servers/ascensionxi/features.lua').helpers.restock == true);
helpers[1].panel();
local opened;
package.loaded['dlac\\ui\\gearui'] = { openAutomation = function(key) opened = key; end };
local event = { command = '/dl restock' }; handlers.dlac_void_restock_cmd(event);
assert(event.blocked and opened == 'restock');
local ui = require(base .. 'ui');
local fixtureItem, oldCounts = restock.item, client.counts;
restock.item, AshitaCore = realItem, resourceCore;
client.counts, client.tierMask = { [50001] = 2, [17330] = 99 }, 33;
local picker = ui.candidates({ [50001] = 1, [605] = 12 }, '');
assert(#picker == 2 and picker[1].name == 'Ammo' and picker[2].name == 'Oil', 'all picker sources exclude gear');
assert(#ui.candidates({}, 'Sword') == 0, 'exact-name search cannot bypass the gear filter');
restock.config = model.normalize({ character = { { id = 605, name = 'Oil', target = 12 } } });
assert(#ui.candidates({ [605] = 12 }, '') == 1, 'listed character item disappears');
restock.config.jobs.NIN = { { id = 17330, name = 'Ammo', target = 99 } };
assert(#ui.candidates({ [605] = 12 }, '') == 0, 'listed job item disappears too');
restock.config = model.normalize({ character = { { id = 17330, name = 'Ammo', target = 99 } } });
client.tierMask = 1;
restock.inventory = function() return { [17330] = 120 }, 8; end;
assert(realItem(17330).restockable and not realItem(17330).storable, 'locked stored item is withdraw-only');
assert(#restock.plan().store == 0, 'locked tier never deposits surplus');
restock.inventory = function() return {}, 8; end;
assert(#restock.plan().fetch == 1, 'locked stored item remains withdrawable');
client.counts[17330] = nil;
assert(not realItem(17330).restockable, 'locked item with no stored balance is hidden');
restock.config = model.normalize({ character = { { id = 50001, name = 'Sword', target = 0 } } });
restock.inventory = function() return { [50001] = 1 }, 8; end;
assert(#restock.plan().store == 0, 'previously saved gear entries cannot be deposited');
restock.item, AshitaCore, client.counts = fixtureItem, oldCore, oldCounts;

-- Config isolation, old-list import, backup rotation and a failed write.
local safe = require('dlac\\lib\\safewrite');
local oldOpen, oldReplace = io.open, safe.replaceLua;
local files = { ['virtual/restock.lua'] = model.serialize(config) };
local denyWrite = false;
io.open = function(path)
    if files[path] then return { read = function() return files[path]; end, close = function() end }; end
end;
safe.replaceLua = function(path, text, opts)
    if denyWrite then return nil, 'test write failure'; end
    assert((loadstring or load)(text));
    if opts.validate then assert(opts.validate()); end
    files[path] = text; return true;
end;
restock._context = function() return 'virtual/', 'NIN'; end;
assert(restock.syncContext() and restock.config.jobs.NIN[1].target == 24, 'old lists import');
assert(restock.save(restock.config));
for i = 1, 7 do
    local changed = model.normalize(restock.config); changed.character[1].target = i;
    assert(restock.save(changed));
end
assert(files['virtual/backups/void-restock-5.lua'] and not files['virtual/backups/void-restock-6.lua']);
assert(files['virtual/restock.lua'] == model.serialize(config), 'legacy config is never changed');
local beforeFile, beforeConfig = files['virtual/void-restock.lua'], restock.config;
denyWrite = true; assert(not restock.save(config));
assert(files['virtual/void-restock.lua'] == beforeFile and restock.config == beforeConfig);
restock._context = function() return 'other-character/', 'WAR'; end;
assert(restock.syncContext() and #restock.config.character == 0, 'character settings never leak');
files['broken/void-restock.lua'] = 'this is not lua';
restock._context = function() return 'broken/', 'WAR'; end;
assert(not restock.syncContext() and not restock.save(config), 'malformed config is preserved');
io.open, safe.replaceLua = oldOpen, oldReplace;
print('Void Restock planner, protocol, controller and UI tests passed');
