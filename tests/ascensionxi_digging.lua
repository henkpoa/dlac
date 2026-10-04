-- lua tests/ascensionxi_digging.lua [companion-server-checkout]
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local handlers = {};
ashita = { events = { register = function(_, name, callback) handlers[name] = callback; end } };
local service = require('dlac\\servers\\ascensionxi\\modules\\digging\\init');
assert(sp.service('digging') == service and service.exactRank and service.voidGreens);
local status = service.status;
local time, sent, request = 0, 0;
status._clock = function() return time; end;
status._send = function(packet) request = packet; sent = sent + 1; return true; end;
local receive = assert(handlers.dlac_axi_digging_status);
local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536)); end
local function bytes(t, start)
    local out = {}; for i = start or 1, #t do out[#out + 1] = string.char(t[i]); end
    return table.concat(out);
end
-- s: { skill, allowance, cap, credit, delay, rank, flags, refill, greens }
local function frame(req, s, code)
    return '\32\18\0\0' .. string.char(0x81, req[6], code or 0, 0)
        .. p16(1) .. p16(0) .. bytes(req, 13)
        .. p16(s[1]) .. p16(s[2]) .. p16(s[3]) .. p16(s[4]) .. p16(s[5])
        .. string.char(s[6], s[7]) .. p32(s[8]) .. p32(s[9]);
end
local function deliver(data, expected)
    local e = { id = 0x1E0, data = data }; receive(e);
    assert((e.blocked == true) == expected);
end
local SAMPLE = { 457, 123, 504, 72, 1, 4, 1, 3725, 70000 };

status.reset(); status.touch(); status.touch();
assert(sent == 1 and #request == 16 and request[5] == 0x81 and request[9] == 1);
local first = request;
local good = frame(request, SAMPLE);
assert(#good == 36);
deliver(good:sub(1, 35), true);
assert(status.value() == nil, 'truncated frame rejected');
deliver('\32\16' .. good:sub(3) .. string.rep('\0', 476), true);
assert(status.value() == nil, 'wrong declared wire size rejected');
deliver(good .. string.rep('\0', 512 - #good), true);
local v = status.value();
assert(v and v.skill == 45.7 and v.rank == 4 and status.rank() == 4, 'Ashita 512-byte buffer');
assert(v.allowance == 123 and v.cap == 504 and v.credit == 72 and v.delay == 1);
assert(v.voidAccess == true and v.storedGreens == 70000 and v.refillIn() == 3725);
time = 4; status.touch(); assert(sent == 1);
time = 5; status.touch(); assert(sent == 2);
assert(v.refillIn() == 3720, 'the refill counts down between polls');
deliver(frame(first, { 0, 0, 0, 0, 0, 0, 0, 0, 0 }), true);
assert(status.rank() == 4, 'late reply ignored');
deliver(frame(request, { 1001, 0, 0, 0, 0, 0, 0, 0, 0 }), true);
assert(status.rank() == 4, 'skill over 100 rejected');
deliver(frame(request, { 0, 0, 0, 0, 0, 11, 0, 0, 0 }), true);
assert(status.rank() == 4, 'rank over Expert rejected');
deliver(frame(request, { 0, 50, 350, 50, 5, 0, 0, 10, 0 }), true);
v = status.value();
assert(v.rank == 0 and v.allowance == 50 and v.voidAccess == false and v.storedGreens == 0);

-- Other partitions and the HELM op pass through untouched.
deliver('\0\0\0\0' .. string.char(0x80, 1, 0, 0), false);
deliver('\0\0\0\0' .. string.char(0x40, 1, 0, 0), false);
deliver('', false);

receive({ id = 0x00A });
assert(status.value() == nil and status.rank() == nil, 'zoning clears the snapshot');
status.touch(); assert(sent == 2, 'zone settle');
time = 40; status.touch(); assert(sent == 3);
deliver(frame(request, SAMPLE, 1), true);
time = 100; status.touch(); assert(sent == 3, 'an older server answers BAD_OP: stop asking');
status.reset(); status.touch(); assert(sent == 4);
deliver(frame(request, SAMPLE, 5), true);
time = 105; status.touch(); assert(sent == 4, 'unavailable backs off');
time = 130; status.touch(); assert(sent == 5);

if arg and arg[1] then
    local root, serverTime = arg[1], 1000;
    local vars, voidAccess = {}, true;
    local env = setmetatable({ xi = {
        item = setmetatable({ BUNCH_OF_GYSAHL_GREENS = 4545 }, { __index = function(_, key) return key; end }),
        skill = { DIG = 59 },
        chocoboDig = { fetchFatigue = function() return 0; end },
        voidStorage = { isAttuned = function() return voidAccess; end },
    }, VoidStoreBalance = function(_, itemId) return itemId == 4545 and 70000 or 0; end,
    GetSystemTime = function() return serverTime; end,
    NextJstDay = function() return serverTime + 3725; end }, { __index = _G });
    local function loadServer(path)
        local chunk = assert(loadfile(root .. '/' .. path, 't', env));
        if setfenv then setfenv(chunk, env); end
        return chunk();
    end
    env.require = function() end;
    env.Module = { new = function() return {}; end };
    loadServer('modules/custom/lua/chocobo_digging_allowance.lua');
    loadServer('modules/custom/lua/chocobo_digging_void_greens.lua');
    local endpoint = loadServer('modules/custom/lua/helm_status.lua');
    local player = {
        getLocalVar = function(_, name) return vars[name] or 0; end,
        setLocalVar = function(_, name, value) vars[name] = value; end,
        getCharVar = function() return 0; end,
        setCharVar = function() error('the status read must not save the character'); end,
        getCharSkillLevel = function() return 457; end,
        getSkillRank = function() return 4; end,
        getGMLevel = function() return 0; end,
        getID = function() return 21; end,
    };
    status.reset(); status.touch();
    local reply = endpoint.onPacket(player, 0x81, request[6], bytes(request, 9)).frames[1];
    assert(reply.status == 0 and #reply.payload == 28);
    deliver('\32\18\0\0' .. string.char(0x81, request[6], reply.status, reply.flags) .. reply.payload, true);
    v = status.value();
    -- A first read: the allowance starts at one day's credit, 50 + 45.7 * 10 / 20.
    assert(v.skill == 45.7 and v.rank == 4 and v.allowance == 72 and v.cap == 504 and v.credit == 72);
    assert(v.delay == 1 and v.voidAccess and v.storedGreens == 70000 and v.refillIn() == 3725);
    voidAccess = false; serverTime = serverTime + 1;
    status.touch(); time = time + 5; status.touch();
    reply = endpoint.onPacket(player, 0x81, request[6], bytes(request, 9)).frames[1];
    deliver('\32\18\0\0' .. string.char(0x81, request[6], reply.status, reply.flags) .. reply.payload, true);
    assert(status.value().voidAccess == false and status.value().storedGreens == 0,
        'no Void Storage access: no stored greens');
end
print('OK -- digging silent packet, server endpoint, polling and resets');
