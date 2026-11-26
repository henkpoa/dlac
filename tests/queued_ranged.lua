-- lua tests/queued_ranged.lua -- native packet lifecycle for delayed /ra.
package.loaded['dlac\\profiles'] = { nativeMode = function() return true; end };
local activePack = 'ascensionxi';
package.loaded['dlac\\gear\\serverpack'] = { active = function() return activePack; end };
local engine = dofile('feature/equipengine.lua');
local now, events, sent = 0, {}, 0;
os.clock = function() return now; end;
AshitaCore = {
    GetMemoryManager = function() return {
        GetParty = function() return { GetMemberServerId = function() return 1001; end }; end,
    }; end,
    GetPacketManager = function() return {
        AddOutgoingPacket = function() sent = sent + 1; end,
    }; end,
};
engine.fireEvent = function(name) events[#events + 1] = name; end;

local function packet(fields)
    local bytes = {};
    for i = 1, 40 do bytes[i] = 0; end
    for _, f in ipairs(fields) do
        for bit = 0, f[2] - 1 do
            local index = math.floor((f[1] + bit) / 8) + 1;
            bytes[index] = bytes[index] + math.floor(f[3] / 2^bit) % 2 * 2^((f[1] + bit) % 8);
        end
    end
    return string.char(unpack(bytes));
end
local function outgoing(category)
    engine.handleAction(packet({ { 8*8, 16, 42 }, { 10*8, 16, category } }));
end
local function incoming(category, parameter, actor)
    engine.handleIncoming({ id = 0x028, data = packet({
        { 5*8, 32, actor or 1001 }, { 10*8+2, 4, category }, { 10*8+6, 16, parameter or 0x6163 },
    }) });
end
local function expire()
    now = now + 20;
    engine.handleOutgoingChunk({ chunk_data = '' });
    assert(engine.state.action == nil, 'the ordinary fallback still expires');
end

outgoing(0x10);
assert(events[1] == 'Preshot' and events[2] == 'Midshot');
local request = engine.state.action;
expire();
incoming(12, nil, 2002);
assert(engine.state.action == nil, 'another actor cannot restore our gear');
local before = sent;
incoming(12);
assert(engine.state.action == request and request.Target == 42);
assert(request.Completion > now and events[#events] == 'Midshot');
assert(sent == before, 'native start must not inject another /ra');
assert(engine.state.rangedRequest == nil, 'consume the request only once');
local count = #events;
incoming(12);
assert(#events == count, 'duplicate start cannot repeat the restoration');
incoming(2);
assert(engine.state.action == nil, 'ranged finish releases Midshot');

for _, cancel in ipairs({
    function() incoming(12, 28787); end,
    function() incoming(6); end,
    function() outgoing(0x09); end,
    function() engine.handleItemUse(string.rep('\0', 40)); end,
    function() engine.handleIncoming({ id = 0x00A }); end,
    function() engine.handleIncoming({ id = 0x00B }); end,
}) do
    outgoing(0x10);
    cancel();
    assert(engine.state.rangedRequest == nil, 'cancellation discards old request context');
    count = #events;
    incoming(12);
    assert(#events == count, 'cancelled request must never restore Midshot');
end
print('Queued ranged lifecycle: passed');

-- A successor requested while the current shot aims must survive its result.
outgoing(0x10);
incoming(12);
outgoing(0x10);
local successor = engine.state.rangedRequest;
incoming(2);
assert(engine.state.action == successor and engine.state.rangedRequest == successor,
    'finishing the current shot must retain its queued successor');
expire();
incoming(12);
assert(engine.state.action == successor and events[#events] == 'Midshot');
incoming(2);
assert(engine.state.action == nil and engine.state.rangedRequest == nil);

outgoing(0x10);
incoming(12);
outgoing(0x10);
incoming(12, 28787);
assert(engine.state.action == nil and engine.state.rangedRequest == nil and not engine.state.rangedInFlight,
    'interrupting the active shot must discard its queued successor');
print('RA-to-RA gear lifecycle: passed');

-- CEXI, unknown and absent packs keep the pre-queue action lifecycle.
for _, pack in ipairs({ 'cexi', 'unknown', false }) do
    activePack = pack or nil;
    outgoing(0x10);
    local original = engine.state.action;
    count = #events;
    incoming(12);
    assert(engine.state.action == original and #events == count,
        'non-AXI native start must not redispatch Midshot or refresh its timer');
    assert(engine.state.rangedRequest == nil and not engine.state.rangedInFlight);
    engine.handleIncoming({ id = 0x00A });
    engine.handleIncoming({ id = 0x00B });
    assert(engine.state.action == original, 'non-AXI zoning keeps its original engine behavior');
    outgoing(0x10);
    incoming(2);
    assert(engine.state.action == nil, 'non-AXI finish must clear the action as before');
    outgoing(0x10);
    expire();
    count = #events;
    incoming(12);
    assert(engine.state.action == nil and #events == count, 'non-AXI expiry cannot restore old gear');
end

activePack = 'ascensionxi';
outgoing(0x10);
incoming(12);
outgoing(0x10);
activePack = 'cexi';
count = #events;
incoming(12);
assert(engine.state.rangedRequest == nil and not engine.state.rangedInFlight and #events == count,
    'switching away from AXI discards its pending context without redispatch');
incoming(2);
assert(engine.state.action == nil);
print('Queued ranged server-pack isolation: passed');
