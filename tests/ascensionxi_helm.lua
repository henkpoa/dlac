-- lua tests/ascensionxi_helm.lua [companion-server-checkout]
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local handlers = {};
ashita = { events = { register = function(_, name, callback) handlers[name] = callback; end } };
local service = require('dlac\\servers\\ascensionxi\\modules\\helm\\init');
local status, skills = service.points, service.skills;
local time, sent, request = 0, 0;
status._clock = function() return time; end;
status._send = function(packet) request = packet; sent = sent + 1; return true; end;
local receive = assert(handlers.dlac_axi_helm_points);
local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536)); end
local function bytes(t, start)
    local out = {}; for i = start or 1, #t do out[#out + 1] = string.char(t[i]); end
    return table.concat(out);
end
local function frame(req, points, raw, code)
    return '\224\15\0\0' .. string.char(0x80, req[6], code or 0, 0)
        .. p16(1) .. p16(0) .. bytes(req, 13) .. p32(points)
        .. p16(raw[1]) .. p16(raw[2]) .. p16(raw[3]) .. p16(raw[4]);
end
local function deliver(data, expected)
    local e = { id = 0x1E0, data = data }; receive(e);
    assert((e.blocked == true) == expected);
end
status.reset(); status.touch(); status.touch();
assert(sent == 1 and #request == 16 and request[5] == 0x80);
local first = request;
-- Live Ashita capture: a 28-byte wire frame is exposed as a 512-byte buffer.
local snapshot = frame(request, 738, { 200, 630, 1000, 169 });
deliver(snapshot:sub(1, 27), true);
assert(status.value() == nil, 'truncated wire frame rejected');
deliver('\224\13' .. snapshot:sub(3) .. string.rep('\0', 484), true);
assert(status.value() == nil, 'short declared wire length rejected despite backing buffer');
deliver('\224\17' .. snapshot:sub(3) .. string.rep('\0', 484), true);
assert(status.value() == nil, 'oversized declared wire length rejected');
deliver(snapshot .. string.rep('\0', 512 - #snapshot), true);
assert(status.value() == 738 and skills.value('Mining') == 16.9,
    'valid HELM reply in Ashita 512-byte buffer must populate points and skills');
assert(math.abs(skills.chance('Mining', 1) - 75.35) < 0.0001);
local chance, reason = skills.chance('Mining', 2);
assert(chance == nil and reason == 'locked');
assert(skills.chance('Harvesting', 1) == 80 and skills.chance('Harvesting', 2) == 50);
assert(skills.chance('Excavation', 4) == 54.5 and skills.chance('Logging', 5) == 80);
time = 4; status.touch(); assert(sent == 1);
time = 5; status.touch(); assert(sent == 2);
deliver(frame(first, 9999, { 0, 0, 0, 0 }), true);
assert(status.value() == 738, 'late snapshot ignored');
deliver(frame(request, 9999, { 1001, 0, 0, 0 }), true);
assert(status.value() == 738, 'invalid snapshot rejected atomically');
deliver(frame(request, 0, { 0, 0, 0, 0 }), true);
assert(status.value() == 0 and skills.value('Mining') == 0);
assert(skills.chance('Mining', 1) == 50);
deliver('\0\0\0\0' .. string.char(0x40, 1, 0, 0), false);
deliver('\0\0\0\0' .. string.char(0x00, 1, 0, 0), false);
deliver('', false);
receive({ id = 0x017, data = string.rep('\0', 23) .. 'HELM points: 9999.' });
assert(status.value() == 0, 'chat is not the addon transport');
receive({ id = 0x00A });
assert(status.value() == nil and skills.value('Mining') == nil);
status.touch(); assert(sent == 2, 'zone settle');
time = 10; status.touch(); assert(sent == 3);
deliver(frame(first, 9999, { 0, 0, 0, 0 }), true);
assert(status.value() == nil, 'old character snapshot ignored');
deliver(frame(request, 0, { 0, 0, 0, 0 }, 1), true);
time = 100; status.touch(); assert(sent == 3, 'no command fallback on old server');
status.reset(); status.touch(); assert(sent == 4);
deliver(frame(request, 0, { 0, 0, 0, 0 }, 3), true);
time = 104; status.touch(); assert(sent == 4);
time = 105; status.touch(); assert(sent == 5);
time = 110; status.touch(); assert(sent == 6, 'lost response retries at polling cadence');
local ci = require('dlac\\gear\\catalogindex');
assert(#service.rows == 5 and service.upgradeCost == 10000 and service.sharedGear);
for _, row in ipairs(service.rows) do
    assert(ci.rawById(row.fieldId).Name == row.field);
    assert(ci.rawById(row.workerId).Name == row.worker);
    assert(ci.rawById(row.reservedId).Name == row.reserved);
    assert(row.quest or row.cost == 2500);
end

if arg and arg[1] then
    local root, serverTime, nextRead = arg[1], 1000, 0;
    local env = setmetatable({ xi = {
        item = setmetatable({}, { __index = function(_, key) return key; end }),
        skill = { HARVESTING = 60, EXCAVATION = 61, LOGGING = 62, MINING = 63 },
        helm = { points = function() return 758; end },
    }, VoidStoreCode = setmetatable({}, { __index = function(_, key) return key; end }),
    VoidStoreStatus = { OK = 0, BAD_OP = 1, MALFORMED = 2, BUSY = 3, UNAVAILABLE = 5, PROTO_UNSUPPORTED = 6 },
    GetSystemTime = function() return serverTime; end }, { __index = _G });
    local function loadServer(path)
        local chunk = assert(loadfile(root .. '/' .. path, 't', env));
        if setfenv then setfenv(chunk, env); end
        return chunk();
    end
    local endpoint = loadServer('modules/custom/lua/helm_status.lua');
    env.require = function(name) assert(name == 'modules/custom/lua/helm_status'); return endpoint; end;
    loadServer('modules/custom/lua/void_storage.lua');
    local player = {
        getLocalVar = function() return nextRead; end,
        setLocalVar = function(_, _, v) nextRead = v; end,
        getCharSkillLevel = function(_, id) return ({ [60] = 200, [61] = 630, [62] = 1000, [63] = 169 })[id]; end,
    };
    status.reset(); status.touch();
    local payload = bytes(request, 9);
    local function ask(op, data) return env.xi.voidStorage.onPacket(player, op, request[6], data).frames[1]; end
    local reply = ask(0x80, payload);
    assert(reply.status == 0 and #reply.payload == 20);
    deliver('\224\15\0\0' .. string.char(0x80, request[6], reply.status, reply.flags) .. reply.payload, true);
    assert(status.value() == 758 and skills.value('Mining') == 16.9);
    assert(ask(0x80, payload).status == 3, 'server rate limit');
    assert(ask(0x80, '').status == 2 and ask(0x80, payload .. '\0').status == 2);
    assert(ask(0x80, p16(2) .. payload:sub(3)).status == 6);
    assert(ask(0x81, payload).status == 1 and ask(0x90, payload).status == 1);
    serverTime = serverTime + 1;
    assert(ask(0x80, payload).status == 0);
    env.xi.gearVault = { onPacket = function() return { frames = { { status = 77 } } }; end };
    assert(ask(0x40, '').status == 77, 'gear-vault routing preserved');
    local output, command = {}, nil;
    env.xi.msg = { channel = { SYSTEM_3 = 29 } };
    env.xi.module = { registerCommand = function(_, c) command = c; end };
    env.xi.fishingPoints = { points = function() return 42; end };
    env.xi.onslaught = { getOnslaughtPoints = function() return 7; end };
    loadServer('modules/custom/commands/points.lua');
    command.onTrigger({ printToPlayer = function(_, line) output[#output + 1] = line; end });
    assert(#output == 3 and output[1] == 'HELM points: 758.'
        and output[2] == 'Fishing points: 42.' and output[3] == 'Onslaught Points: 7.');
end
print('OK -- HELM silent packets, server routing, polling, skills and progression');
