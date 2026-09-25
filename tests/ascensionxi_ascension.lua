-- lua tests/ascensionxi_ascension.lua   (from the dlac repo root)
-- The AscensionXI ascension module: the 0x1E0 op 0xA0 client, and the fold
-- that makes an ascended job count as level 75 for the lockstyle picker.
-- Server contract: ascensionxi repo, documentation/custom/lockstyle-vault-ascension.md.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();

local list = sp.modules();
local mounted = false;
for _, name in ipairs(list) do if name == 'ascension' then mounted = true; end end
assert(mounted, 'the AscensionXI pack mounts the ascension module');

local handlers = {};
ashita = { events = { register = function(_, name, callback) handlers[name] = callback; end } };
local mod = require('dlac\\servers\\ascensionxi\\modules\\ascension\\init');
local status = require('dlac\\servers\\ascensionxi\\modules\\ascension\\status');
local jobgate = require('dlac\\gear\\jobgate');
local oracle = require('dlac\\gear\\gearoracle');
assert(sp.service('prestige') == status, 'the module provides the prestige service jobgate folds');
assert(type(mod.pump) == 'function', 'the module hands its beat to the servermods pump');

local time, sent, request = 0, 0, nil;
local raw = { WAR = 0, MNK = 0, WHM = 0 };
status._clock = function() return time; end;
status._send = function(packet) request = packet; sent = sent + 1; return true; end;
status._levels = function() return raw; end;
jobgate.reader = function() return raw; end;
local receive = assert(handlers.dlac_axi_ascension_status);

local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function tokenOf(req)
    local out = {}; for i = 13, 16 do out[#out + 1] = string.char(req[i]); end
    return table.concat(out);
end
-- A reply frame: 0x1E0, 40 bytes on the wire (size field 10 words).
local function frame(req, counts, code, opts)
    opts = opts or {};
    local body = {};
    for job = 1, 22 do body[job] = string.char(counts[job] or 0); end
    return string.char(0xE0, opts.sizeWords or 0x15) .. '\0\0'
        .. string.char(opts.op or 0xA0, req[6], code or 0, 0)
        .. p16(1) .. p16(opts.jobs or 22) .. (opts.token or tokenOf(req))
        .. table.concat(body) .. p16(0);
end
local function deliver(data, expectBlocked)
    local e = { id = 0x1E0, data = data };
    receive(e);
    assert((e.blocked == true) == expectBlocked, 'blocked flag for ' .. #data .. '-byte frame');
end
local function pad(s) return s .. string.rep('\0', 512 - #s); end
local function zoneIn(id)
    receive({ id = 0x00A, data = '\0\0\0\0' .. string.char(id % 256, math.floor(id / 256) % 256, 0, 0) });
end
local WAR75 = { Jobs = { 'WAR' }, Level = 75 };

-- Pre-login: every job reads zero, so nothing is sent.
status.reset();
mod.pump(); time = 2; mod.pump();
assert(sent == 0, 'no request before the character is in game');

-- Login (0x00A): asked once the zone settles, then quiet while outstanding.
zoneIn(7);
raw = { WAR = 1, MNK = 0, WHM = 10 };
time = 6; mod.pump(); assert(sent == 0, 'nothing asked while the login zone settles');
time = 7; mod.pump(); mod.pump();
assert(sent == 1 and #request == 16 and request[5] == 0xA0 and request[9] == 1, 'one request, op 0xA0, protocol 1');
assert(jobgate.levels().WAR == 1, 'before the answer the raw level stands');
assert(not oracle.anyJobCanWear(WAR75, jobgate.levels()), 'and the level 75 piece is hidden');

-- Malformed and stale answers are consumed but change nothing.
local first = request;
local good = frame(request, { [1] = 1 });
deliver(good:sub(1, 39), true);
assert(status.tiers() == nil, 'truncated frame rejected');
deliver(pad(frame(request, { [1] = 1 }, 0, { sizeWords = 0x13 })), true);
assert(status.tiers() == nil, 'wrong declared size rejected');
deliver(pad(frame(request, { [1] = 1 }, 0, { jobs = 21 })), true);
assert(status.tiers() == nil, 'wrong job count rejected');
deliver(pad(frame(request, { [1] = 1 }, 0, { token = '\1\2\3\4' })), true);
assert(status.tiers() == nil, 'wrong token rejected');
deliver('\0\0\0\0' .. string.char(0x80, 1, 0, 0), false);
deliver('\0\0\0\0' .. string.char(0x40, 1, 0, 0), false);
deliver('', false);

-- The answer: Warrior has ascended once.
deliver(pad(good), true);
assert(status.tiers().WAR == 1 and status.tiers().WHM == 0, 'counts by job');
local lv = jobgate.levels();
assert(lv.WAR == 75 and lv.WHM == 10 and lv.MNK == 0, 'an ascended job reads as 75; the others are raw');
assert(oracle.anyJobCanWear(WAR75, lv), 'the level 75 Warrior piece is offered');
assert(not oracle.anyJobCanWear({ Jobs = { 'MNK' }, Level = 10 }, lv), 'an unascended job keeps its level');

-- Quiet until the refresh.
time = 66; mod.pump(); assert(sent == 1);
time = 67; mod.pump(); assert(sent == 2, 'refreshed after 60 seconds');
deliver(pad(frame(request, { [1] = 2 })), true);
assert(status.tiers().WAR == 2);

-- A job's level dropping (an ascension) asks at once.
raw = { WAR = 75, MNK = 0, WHM = 10 };
time = 68; mod.pump(); assert(sent == 2, 'a level rise asks nothing');
raw = { WAR = 1, MNK = 0, WHM = 10 };
time = 69; mod.pump(); assert(sent == 3, 'a level drop asks at once');
deliver(pad(frame(request, { [1] = 3 })), true);
assert(status.tiers().WAR == 3);

-- BUSY retries after five seconds; a lost answer retries at the same pace.
time = 130; mod.pump(); assert(sent == 4);
deliver(pad(frame(request, {}, 3)), true);
assert(status.tiers().WAR == 3, 'BUSY keeps the counts');
time = 134; mod.pump(); assert(sent == 4);
time = 135; mod.pump(); assert(sent == 5);
time = 140; mod.pump(); assert(sent == 6, 'unanswered request retries');
deliver(pad(frame(first, { [1] = 9 })), true);
assert(status.tiers().WAR == 3, 'a reply to an old token is ignored');

-- Zoning: the same character keeps its counts and asks after the settle.
deliver(pad(frame(request, { [1] = 3 })), true);
zoneIn(7);
time = 141; mod.pump(); assert(sent == 6, 'nothing asked while the zone settles');
assert(status.tiers().WAR == 3);
time = 146; mod.pump(); assert(sent == 7, 'asked once the zone settled');
deliver(pad(frame(request, { [1] = 3 })), true);
zoneIn(7);
assert(status.tiers().WAR == 3, 'same character keeps its counts across a zone');
zoneIn(8);
assert(status.tiers() == nil, 'another character starts with no counts');
assert(jobgate.levels().WAR == 1, 'and the raw levels stand');
receive({ id = 0x00B });
time = 400; mod.pump(); assert(sent == 7, 'nothing asked between zone-out and zone-in');

-- A server without the op answers BAD_OP: the client goes quiet.
zoneIn(8);
time = 406; mod.pump(); assert(sent == 8);
deliver(pad(frame(request, {}, 1)), true);
assert(status.tiers() == nil);
time = 1000; mod.pump(); zoneIn(8); time = 1010; mod.pump();
assert(sent == 8, 'dormant after BAD_OP');

print('AscensionXI ascension tests passed');
