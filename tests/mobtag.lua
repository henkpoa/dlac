-- Run from the addon root: lua tests/mobtag.lua
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local handlers = {};
ashita = { events = { register = function(_, key, fn) handlers[key] = fn; end } };
local tag = require('dlac\\feature\\mobtag');
local count = 0;
local function eq(actual, expected, why)
    count = count + 1;
    assert(actual == expected, why .. ': got ' .. tostring(actual) .. ', expected ' .. tostring(expected));
end

-- Fixture writer uses absolute offsets from the packet specification, including
-- both optional-effect branches and their different field lengths.
local function packet(actor, category, targets)
    local bytes = {};
    for i = 1, 19 do bytes[i] = 0; end
    local function put(pos, size, value)
        for i = 0, size - 1 do
            local index = math.floor((pos + i) / 8) + 1;
            bytes[index] = (bytes[index] or 0) + (math.floor(value / 2 ^ i) % 2) * 2 ^ ((pos + i) % 8);
        end
    end
    put(40, 32, actor); put(72, 10, #targets); put(82, 4, category);
    local pos = 150;
    for _, target in ipairs(targets) do
        put(pos, 32, target.id); put(pos + 32, 4, #target.actions); pos = pos + 36;
        for _, a in ipairs(target.actions) do
            put(pos, 5, a.reaction or 8);
            put(pos + 27, 17, a.param or 0);
            put(pos + 44, 10, a.message); pos = pos + 85;
            put(pos, 1, a.added and 1 or 0); pos = pos + 1;
            if a.added then put(pos, 37, 1); pos = pos + 37; end
            put(pos, 1, a.spikes and 1 or 0); pos = pos + 1;
            if a.spikes then put(pos, 34, 1); pos = pos + 34; end
        end
    end
    local out = {};
    for i = 1, math.ceil(pos / 8) do out[i] = string.char(bytes[i] or 0); end
    return table.concat(out);
end
local function entityPacket(id, mask, hp, status)
    local b = {};
    for i = 1, 32 do b[i] = 0; end
    for i = 0, 3 do b[5 + i] = math.floor(id / 256 ^ i) % 256; end
    b[11], b[31], b[32] = mask, hp or 0, status or 0;
    local out = {}; for i, v in ipairs(b) do out[i] = string.char(v); end
    return table.concat(out);
end
local me, other, a, b = 1001, 1002, 17000001, 17000002;
local current, zone = a, 100;
tag.readIdentity = function() return me, zone; end;
local liveTarget = tag.readTarget;
tag.readTarget = function() return current; end;
local function send(message, category, actor, target)
    tag.onPacket(0x028, packet(actor or me, category or 1,
        { { id = target or a, actions = { { message = message } } } }));
end
local function fresh() tag.reset(); current = a; end

eq(tag.current(), false, 'fresh mob is untagged');
send(1, 1, other); eq(tag.current(), false, 'party member cannot tag for me');
send(1, 1, a, me); eq(tag.current(), false, 'aggro / being hit cannot tag');
for _, message in ipairs({15, 29, 30, 31, 70, 75, 85, 114, 153, 156, 158, 188, 189, 244, 282, 283, 284, 323, 324, 354, 355, 655, 999}) do
    send(message); eq(tag.current(), false, 'failed or unknown result ' .. message);
end
for _, category in ipairs({5, 7, 8, 9, 11, 12, 13}) do
    send(1, category); eq(tag.current(), false, 'non-player-completion category ' .. category);
end
for _, message in ipairs({7, 24, 102, 103, 230}) do
    send(message, 4); eq(tag.current(), false, 'healing/buff result ' .. message);
end
for _, pair in ipairs({{1,1}, {1,67}, {2,352}, {2,353}, {3,185}, {4,2}, {4,236}, {4,237}, {4,268}, {4,271}, {4,341}, {4,227}, {4,228}, {6,100}, {6,119}, {6,125}, {6,129}, {6,127}, {14,320}, {15,672}}) do
    fresh(); send(pair[2], pair[1]); eq(tag.current(), true, 'successful result ' .. pair[2]);
end
current = b; eq(tag.current(), false, 'different mob is untagged');
current = nil; eq(tag.current(), nil, 'no target is unknown');
current = a; eq(tag.current(), true, 'returning to tagged mob remembers it');
-- No outgoing engage/disengage packet may erase history.
tag.onPacket(0x01A, ''); eq(tag.current(), true, 'disengaging preserves tags');

fresh();
local aoe = packet(me, 4, {
    { id = a, actions = {{message=15, added=true, spikes=true}, {message=237}} },
    { id = b, actions = {{message=284}} },
    { id = b + 1, actions = {{message=267}} },
});
local decoded = tag.decodeAction(aoe);
eq(#decoded.targets, 2, 'AoE counts only successful targets');
eq(decoded.targets[1], a, 'second action can tag after first misses');
eq(decoded.targets[2], b + 1, 'optional effects do not shift later targets');
for n = 0, #aoe - 1 do
    eq(tag.decodeAction(aoe:sub(1, n)), nil, 'truncated action length ' .. n);
end
tag.onPacket(0x028, aoe); eq(tag.current(), true, 'AoE first target tagged');
current = b; eq(tag.current(), false, 'AoE resisted target stays untagged');
current = b + 1; eq(tag.current(), true, 'AoE secondary target tagged');
current = a;
tag.onPacket(0x00E, entityPacket(a, 1)); eq(tag.current(), true, 'position update zero HP ignored');
tag.onPacket(0x00E, entityPacket(b, 4, 0, 2)); eq(tag.current(), true, 'other mob death does not reset mine');
tag.onPacket(0x00E, entityPacket(a, 4, 0, 2)); eq(tag.current(), false, 'death clears same-id respawn');
send(237, 4); tag.onPacket(0x00E, entityPacket(a, 32));
eq(tag.current(), false, 'despawn clears tag in packet order');
tag.onPacket(0x00E, entityPacket(a, 32)); send(237, 4);
eq(tag.current(), true, 'new action after despawn belongs to new lifetime');
tag.onPacket(0x00A, ''); eq(tag.current(), false, 'zone-in clears history');
send(119, 6); tag.onPacket(0x00B, ''); eq(tag.current(), false, 'zone-out clears history');
send(119, 6); eq(tag.current(), true, 'ability tags before engaging');
zone = 101; eq(tag.current(), false, 'zone identity fallback resets');
send(119, 6); eq(tag.current(), true, 'tag before character change');
me = 1003; eq(tag.current(), false, 'character change clears history');
send(119, 6); eq(tag.current(), true, 'tag before lost player read');
tag.readIdentity = function() error('not logged in'); end;
eq(tag.current(), nil, 'unreadable player is unknown');
tag.readIdentity = function() return me, zone; end;
eq(tag.current(), false, 'logout discarded old tags');
handlers['dlac-mobtag-in']({id=0x028, data=packet(me, 1, {{id=a, actions={{message=1}}}}), injected=true});
eq(tag.current(), false, 'injected result ignored');
send(1); eq(tag.current(), true, 'tag before overflow');
for _ = 1, tag.QUEUE_MAX + 1 do tag.onPacket(0x00E, entityPacket(b, 1)); end
eq(tag.current(), false, 'queue overflow clears stale history');

-- Exercise the live entity reader with reused indexes and non-mob targets.
local sid, flags, hp, status, index = a, 16, 100, 1, 23;
AshitaCore = { GetMemoryManager = function() return {
    GetTarget = function() return {GetTargetIndex=function() return index; end}; end,
    GetEntity = function() return {
        GetServerId=function() return sid; end, GetSpawnFlags=function() return flags; end,
        GetHPPercent=function() return hp; end, GetStatus=function() return status; end,
    }; end,
}; end };
tag.readTarget = liveTarget;
send(1); eq(tag.current(), true, 'live reader resolves target server id');
sid = b; eq(tag.current(), false, 'reused entity index does not share tag');
flags = 1; eq(tag.current(), nil, 'player target is not a mob');
flags = 2; eq(tag.current(), nil, 'NPC target is not a mob');
flags = 16; hp = 0; eq(tag.current(), nil, 'dead target unknown');
hp = 100; index = 0; eq(tag.current(), nil, 'empty target unknown');
index = 23;

-- Run the real dispatch normalization, matchers, serializer and UI edit model
-- under both server packs. False must survive Commit and outrank engaged gear.
local sp = require('dlac\\gear\\serverpack');
local dispatch = require('dlac\\dispatch');
local model = require('dlac\\gear\\triggermodel');
for _, server in ipairs({'cexi', 'ascensionxi'}) do
    sp._configLoader = function() return {server=server}; end; sp.init();
    local raw = {Default = {
        {when={status='Engaged'}, set='TP'},
        {when={status='Engaged', mobTagged=false}, set='TH'},
    }};
    local roundtrip = assert(load(dispatch.serializeTriggers(model.fromRaw(raw, dispatch.canonEvent))))();
    eq(roundtrip.Default[2].when.mobTagged, false, server .. ' Commit preserves false');
    local rules, warnings = dispatch._normalize(roundtrip);
    eq(#warnings, 0, server .. ' condition recognized');
    eq(rules.Default[2].prio > rules.Default[1].prio, true, server .. ' TH overlays TP');
    eq(dispatch._matches(rules.Default[2], {player={Status='Engaged'}}), true, server .. ' live untagged mob matches');
    eq(dispatch._matches(rules.Default[2], {player={Status='Engaged'}, mobTagged=true}), false, server .. ' tagged mob stops overlay');
    eq(dispatch._matches(rules.Default[2], {player={Status='Idle'}, mobTagged=false}), false, server .. ' idle does not match');
    index = 0;
    eq(dispatch._matchers.mobtagged(false, {}), false, server .. ' no target matches neither polarity');
    eq(dispatch._matchers.mobtagged(true, {}), false, server .. ' no target true also fails');
    index = 23;
end
print(string.format('OK -- %d mob tag checks passed', count));
