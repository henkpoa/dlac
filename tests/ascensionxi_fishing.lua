-- lua tests/ascensionxi_fishing.lua [companion-server-checkout]
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local handlers = {};
ashita = { events = { register = function(_, name, callback) handlers[name] = callback; end } };
local service = require('dlac\\servers\\ascensionxi\\modules\\fishing\\init');
assert(sp.service('fishing') == service and service.moveCatches == true, 'the pack provides the fishing service');
local status = service.status;
local time, sent, request = 0, 0;
status._clock = function() return time; end;
status._send = function(packet) request = packet; sent = sent + 1; return true; end;
local receive = assert(handlers.dlac_axi_fishing_status);
local outgoing = assert(handlers.dlac_axi_fishing_events);
local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536)); end
local function bytes(t, start)
    local out = {}; for i = start or 1, #t do out[#out + 1] = string.char(t[i]); end
    return table.concat(out);
end
-- s: { points, skill tenths, wardrobe slots, rank }
local function frame(req, s, code)
    return '\224\13\0\0' .. string.char(0x83, req[6], code or 0, 0)
        .. p16(1) .. p16(0) .. bytes(req, 13)
        .. p32(s[1]) .. p16(s[2]) .. string.char(s[3], s[4]);
end
local function deliver(data, expected)
    local e = { id = 0x1E0, data = data }; receive(e);
    assert((e.blocked == true) == expected, 'blocked flag');
end
local function fishing(mode)   -- our 0x110: UniqueNo, para, ActIndex, mode, pad, para2
    return string.rep('\0', 4) .. p32(99) .. p32(0) .. p16(1234) .. string.char(mode, 0) .. p32(0);
end
local SAMPLE = { 123456, 234, 2, 3 };   -- rank 3 is Novice

-- One request, the HELM envelope with op 0x83.
status.reset(); status.touch(); status.touch();
assert(sent == 1 and #request == 16 and request[5] == 0x83 and request[9] == 1, 'one request, version 1');
local first = request;
local good = frame(request, SAMPLE);
assert(#good == 24);
deliver(good:sub(1, 23), true);
assert(status.value() == nil, 'truncated frame rejected');
deliver('\224\15' .. good:sub(3) .. string.rep('\0', 486), true);
assert(status.value() == nil, 'wrong declared wire size rejected');
deliver(good:sub(1, 8) .. p16(2) .. good:sub(11) .. string.rep('\0', 488), true);
assert(status.value() == nil, 'protocol version 2 rejected');
local other = {};
for i = 1, #request do other[i] = request[i]; end
other[13] = (other[13] + 1) % 256;
deliver(frame(other, SAMPLE), true);
assert(status.value() == nil, 'the same seq with another token rejected');
deliver(frame(request, { 1, 1101, 0, 0 }), true);
assert(status.value() == nil, 'a skill past 110.0 rejected');
deliver(frame(request, { 1, 100, 0, 11 }), true);
assert(status.value() == nil, 'a rank past Expert rejected');
deliver(good .. string.rep('\0', 512 - #good), true);
local v = status.value();
assert(v and v.points == 123456 and v.skill == 23.4 and v.slots == 2 and v.rank == 3, 'Ashita 512-byte buffer');
deliver(frame(first, { 9, 9, 9, 9 }), true);
assert(status.value().points == 123456, 'a late reply changes nothing');

-- No clock: after an answer the next ask is a minute away...
time = 30; status.touch(); assert(sent == 1, 'no poll inside the refresh window');
-- ...unless we reel in: a landed fish banks its points.
outgoing({ id = 0x110, data = fishing(2) });
time = 31.5; status.touch(); assert(sent == 1, 'a hook check changes nothing');
outgoing({ id = 0x110, data = fishing(3) });
time = 32; status.touch(); assert(sent == 1, 'asks a second after the reel, not at once');
time = 32.6; status.touch(); assert(sent == 2, 'the reel made the snapshot stale');
deliver(frame(request, { 123506, 235, 2, 3 }), true);
assert(status.value().points == 123506 and status.value().skill == 23.5);
-- An NPC menu choice (Fennella's shelf) does too.
time = 40; outgoing({ id = 0x05B, data = string.rep('\0', 20) });
time = 41.1; status.touch(); assert(sent == 3, 'an event option made it stale');
-- A reel while that request is out asks once more after its reply.
outgoing({ id = 0x110, data = fishing(3) });
deliver(frame(request, { 123506, 235, 2, 3 }), true);
time = 41.5; status.touch(); assert(sent == 3);
time = 42.2; status.touch(); assert(sent == 4, 'the pending reply answered for before the reel');
deliver(frame(request, { 123566, 236, 2, 3 }), true);
time = 101; status.touch(); assert(sent == 4);
time = 102.3; status.touch(); assert(sent == 5, 'the minute fallback while a surface shows it');

-- BUSY keeps the snapshot and asks again shortly; UNAVAILABLE drops it.
deliver(frame(request, SAMPLE, 3), true);
assert(status.value() ~= nil, 'BUSY keeps the last snapshot');
time = 103; status.touch(); assert(sent == 5);
time = 103.9; status.touch(); assert(sent == 6, 'BUSY retries after BUSY_S');
deliver(frame(request, SAMPLE, 5), true);
assert(status.value() == nil, 'UNAVAILABLE clears it');
time = 120; status.touch(); assert(sent == 6);
time = 134; status.touch(); assert(sent == 7, 'UNAVAILABLE backs off thirty seconds');
-- An unanswered request is sent twice with its token, then asked afresh.
local lost = request;
time = 139.1; status.touch(); assert(sent == 8 and request[13] == lost[13], 'retry keeps the token');
time = 144.2; status.touch(); assert(sent == 9 and request[13] ~= lost[13], 'then a new token');

-- Other ops pass by: this handler blocks only its own.
deliver('\0\0\0\0' .. string.char(0x80, 1, 0, 0), false);
deliver('\0\0\0\0' .. string.char(0x81, 1, 0, 0), false);
deliver('', false);
receive({ id = 0x017, data = string.rep('\0', 23) .. 'You earn 60 Fishing points.' });
-- A zone line clears the snapshot and waits for the zone to settle.
deliver(frame(request, SAMPLE), true);
receive({ id = 0x00B });
assert(status.value() == nil, 'zoning clears it');
status.touch(); assert(sent == 9, 'zone settle');
time = 150; status.touch(); assert(sent == 10);
-- An older server: BAD_OP stops every ask until a reset, reels included.
deliver(frame(request, SAMPLE, 1), true);
outgoing({ id = 0x110, data = fishing(3) });
time = 400; status.touch(); assert(sent == 10, 'no asking an old server');
status.reset(); status.touch(); assert(sent == 11);

-- The shared transport names the producer.
local transport = require('dlac\\servers\\ascensionxi\\transport');
assert(transport.producerOf(0x83) == 'fishing');

-- The pack's fishing tables and their rules.
local db = sp.data('fishdb');
assert(db ~= nil and db.rules ~= nil and db.rules.hookGate == 10 and db.rules.skillCap == 110, 'fishdb rules');
local manifest = dofile('servers/ascensionxi/manifest.lua');
local nFish = 0; for _ in pairs(db.fish) do nFish = nFish + 1; end
assert(nFish == manifest.counts.fishdb, 'the manifest count is the fish count');
assert(db.shop.gear[1].slot == 'Head' and db.shop.gear[1].id == 26557 and db.shop.gear[1].up == 26558,
    "Fennella's first row is the custom Fisherman's Cap, upgraded to the Angler's Cap");
assert(db.shop.gear[1].price == 5000 and db.shop.upgradeCost == 12000);
assert(db.gearBonus[26558].fish == 2 and db.gearBonus[26558].sl == 'Head');
assert(db.points.bands[1].points == 40 and db.points.bands[#db.points.bands].points == 80);

local fcalc = dofile('feature/fishcalc.lua');
package.loaded['dlac\\feature\\fishcalc'] = fcalc;
fcalc._setDb(db);
local carp = db.fish[4401];
assert(carp ~= nil and carp.sk == 11, 'Moat Carp');
assert(fcalc.canHook(carp, 1) and not fcalc.canHook(carp, 0), 'bites only up to effective + 10');
assert(fcalc.minSkillToHook(carp) == 1);
assert(fcalc.pointsFor(carp) == 40 and fcalc.pointsFor(db.fish[90]) == 0, 'junk pays nothing');
local up = fcalc.skillupFor(carp, 5, 0);
assert(up.gains and up.chance == 50 and up.ceiling == 10 and up.limit == 'guild', 'the guild cap binds first');
up = fcalc.skillupFor(carp, 5, 3);
assert(up.gains and up.ceiling == 11 and up.limit == 'fish');
up = fcalc.skillupFor(carp, 11, 3);
assert(not up.gains and up.chance == 0, 'no skill-ups once you reach the fish');
assert(fcalc.skillupFor(carp, 10.9, 3).gains, 'tenths still learn below the fish');
assert(fcalc.skillupFor(db.fish[4305], 95, 10).chance == 20, 'the top band');
-- AscensionXI #982: a skill-up is 0.1 to 0.4 from a fish at least 10 above
-- your base skill, else 0.1, and every award stops at the ceiling.
assert(db.rules.stepUpTo == 0.4 and db.rules.stepGap == 10, 'the pack carries the amount rule');
assert(fcalc.skillupFor(carp, 5, 3).stepMax == 0.1, 'a fish 6 above pays 0.1');
assert(fcalc.skillupFor(carp, 1, 3).stepMax == 0.4, 'exactly 10 above pays up to 0.4');
assert(fcalc.skillupFor(carp, 1.1, 3).stepMax == 0.1, '9.9 above pays 0.1');
up = fcalc.skillupFor(db.fish[4305], 39.8, 3);
assert(up.gains and up.ceiling == 40 and up.stepMax == 0.2, 'the guild cap clips the award to 0.2');
assert(fcalc.skillupFor(carp, 11, 3).stepMax == 0.1, 'nothing to learn, no bigger step');
local olderRules = {};
for k, v in pairs(db.rules) do olderRules[k] = v; end
olderRules.stepUpTo, olderRules.stepGap = nil, nil;
fcalc._setDb({ rules = olderRules });
up = fcalc.skillupFor(carp, 1, 3);
assert(up.gains and up.chance == 50 and up.stepMax == nil, 'a pack from before #982 says no amount');
fcalc._setDb(db);
-- Rivals that cannot bite at your skill are no rivals: some water reads
-- isolated at a low skill and crowded at a high one.
local changed = nil;
for fid, f in pairs(db.fish) do
    if (f.item or 0) == 0 and f.sk <= 10 then
        local low, high = fcalc.isolationFor(fid, 0), fcalc.isolationFor(fid, 200);
        for i, row in ipairs(low) do
            for _, other in ipairs(row.others) do
                assert(fcalc.canHook(db.fish[other], 0), 'a gated rival can bite');
            end
            if row.clean and not (high[i] and high[i].clean) then changed = fid; end
        end
    end
end
assert(changed ~= nil, 'the hook rule changes some water');
-- Without rules (CatsEye's fishdb) the old answers stand.
fcalc._setDb({ fish = { [1] = { sk = 150 } }, baits = {}, aff = {}, pools = {}, zones = {} });
assert(fcalc.canHook({ sk = 150 }, 50) and fcalc.minSkillToHook({ sk = 150 }) == nil
    and fcalc.skillupFor({ sk = 150 }, 50, 3) == nil and fcalc.pointsFor({ sk = 150 }) == nil);
fcalc._setDb(db);

-- The mover's live wiring: armed only by this service, catches from fishdb.
local tmp = 'tests/_axi_fishing_';
package.loaded['dlac\\lib\\statefile'] = { charDir = function() return tmp; end };
package.loaded['dlac\\feature\\fishwatch'] = nil;
local fw = require('dlac\\feature\\fishwatch');
local fs = require('dlac\\feature\\fishstorage');
local changes = 0;
local liveChanged = fs.live.changed;
fs.live.changed = function() changes = changes + 1; return liveChanged(); end;
assert(next(fs._options()) ~= nil and fs._options()[7] == false and fs._options()[5] == false);
assert(fs._options().trash == false, 'trash is off by default: fish only');
fw.setMoveDestination(7, true);
assert(fs._options()[7] == true and fs._options()[5] == false and changes == 1, 'the Case switch wakes the mover');
fw.setMoveDestination(5, true);
local saved = loadfile(tmp .. 'fishstate.lua')();
assert(saved.moveCase == true and saved.moveSatchel == true and saved.enabled == false, 'saved per character');
assert(saved.moveTrash == false);
fw.setMoveDestination(3, true);
assert(changes == 2, 'only the Case (7) and the Satchel (5)');
fw.setMoveTrash(true);
assert(fs._options().trash == true and changes == 3, 'the trash switch reaches the mover and wakes it');
assert(loadfile(tmp .. 'fishstate.lua')().moveTrash == true, 'the trash switch is saved per character');
fw.setMoveTrash(false);
assert(fs._options().trash == false and loadfile(tmp .. 'fishstate.lua')().moveTrash == false);
assert(fs._catchKind(4401) == 'fish', 'Moat Carp is a fish');
assert(fs._catchKind(90) == 'trash', 'the Rusty Bucket is trash (the server flags it as not a fish)');
for bait in pairs(db.baits) do assert(fs._catchKind(bait) == nil, 'bait is never a catch'); end
assert(fs._catchKind(489) == nil, "a broken rod is not a catch");
for id, f in pairs(db.fish) do
    if db.baits[id] == nil then
        assert(fs._catchKind(id) == ((f.item or 0) ~= 0 and 'trash' or 'fish'), 'the item flag decides');
    end
end
sp.provide('fishing', { status = status });
assert(next(fs._options()) == nil, 'a service without moveCatches arms nothing');
sp.provide('fishing', service);
os.remove(tmp .. 'fishstate.lua');

-- The pack loads it and the addon loads the mover.
local function read(path) local f = assert(io.open(path, 'rb')); local s = f:read('a'); f:close(); return s; end
assert(read('servers/ascensionxi/modules.lua'):find("'fishing'", 1, true), 'modules.lua lists fishing');
assert(dofile('servers/ascensionxi/features.lua').helpers.fish == true, 'the Fishing helper is on');
assert(read('dlac.lua'):find("'feature\\\\fishstorage'", 1, true), 'dlac.lua loads the mover');

if arg and arg[1] then
    -- The real server endpoint (helm_status.lua op 0x83) against this client.
    local root, serverTime, vars = arg[1], 1000, {};
    local env = setmetatable({ xi = {
        skill = { HARVESTING = 60, EXCAVATION = 61, LOGGING = 62, MINING = 63, DIG = 59, FISHING = 48,
                  WOODWORKING = 49, SMITHING = 50, GOLDSMITHING = 51, CLOTHCRAFT = 52,
                  LEATHERCRAFT = 53, BONECRAFT = 54, ALCHEMY = 55, COOKING = 56 },
        mod = setmetatable({}, { __index = function(_, key) return key; end }),
        settings = { map = { CRAFT_HQ_CHANCE_MULTIPLIER = 1.0 } },
        fishingPoints = { points = function() return 98765; end, wardrobeSlots = function() return 4; end },
    }, GetSystemTime = function() return serverTime; end }, { __index = _G });
    local chunk = assert(loadfile(root .. '/modules/custom/lua/helm_status.lua', 't', env));
    if setfenv then setfenv(chunk, env); end
    local endpoint = chunk();
    local player = {
        getLocalVar = function(_, name) return vars[name] or 0; end,
        setLocalVar = function(_, name, value) vars[name] = value; end,
        getCharSkillLevel = function(_, id) return id == 48 and 1037 or 0; end,
        getSkillRank = function(_, id) return id == 48 and 10 or 0; end,
        getMod = function() return 0; end,
    };
    status.reset(); time = time + 1; status.touch();
    local reply = endpoint.onPacket(player, 0x83, request[6], bytes(request, 9)).frames[1];
    assert(reply.status == 0 and #reply.payload == 16, 'the server answers op 0x83');
    deliver('\224\13\0\0' .. string.char(0x83, request[6], reply.status, reply.flags) .. reply.payload, true);
    v = status.value();
    assert(v.points == 98765 and v.skill == 103.7 and v.slots == 4 and v.rank == 10, 'decoded end to end');
    assert(endpoint.onPacket(player, 0x83, request[6], bytes(request, 9)).frames[1].status == 3, 'one a second');
end
print('OK -- fishing silent packet, reel/event refresh, rules, fishdb, the mover wiring and the server endpoint');
