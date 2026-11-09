-- Real AXI wire fixtures, real DLAC decoder/transport, fake client memory/view.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local fixtures = dofile('tests/fixtures/stable/server.lua');
local handlers, tab, context = {}, nil, nil;
local job, level, now, native, reads = 9, 75, 100, 60, 0;
ashita = { events = { register = function(_, name, fn) handlers[name] = fn; end } };
AshitaCore = { GetMemoryManager = function() return { GetPlayer = function() return {
    GetMainJob = function() return job; end, GetMainJobLevel = function() return level; end,
}; end }; end };
package.loaded.imgui = {};
package.loaded['dlac\\ui\\uihost'] = { register = function(spec) tab = spec.tabs[1]; end };
package.loaded['dlac\\servers\\ascensionxi\\modules\\stable\\view'] = {
    render = function(ctx) context = ctx; end, reset = function(keep) assert(keep); end,
};
local transport = require('dlac\\servers\\ascensionxi\\transport');
local sends, blocked = {}, false;
transport._clock = function() return now; end;
transport._audit = nil;
transport._send = function(packet)
    if blocked then return false; end
    sends[#sends + 1] = packet; return true;
end;
assert(transport.producerOf(0xF0) == 'stable' and transport.producerOf(0xFF) == 'stable');
local client = require('dlac\\servers\\ascensionxi\\modules\\stable\\init');
client._gauge._read = function() reads = reads + 1; return native; end;
local function pump(dt) now = now + (dt or 0); client.pump(); end
local function encode(bytes)
    local out = {}; for i, byte in ipairs(bytes) do out[i] = string.char(byte); end
    return table.concat(out);
end
local function frame(bytes, request)
    local data = encode(bytes);
    data = data:sub(1, 5) .. string.char(request[6]) .. data:sub(7);
    if bytes[7] == 0 then data = data:sub(1, 12) .. encode({request[13], request[14], request[15], request[16]}) .. data:sub(17); end
    return data;
end
local function receive(data)
    local e = { id = 0x1E0, size = #data, data_modified = data .. string.rep('\165', 512 - #data) };
    handlers.dlac_bst_stable(e); assert(e.blocked);
end
local function reply(example, request)
    for _, bytes in ipairs(example.frames) do receive(frame(bytes, request)); end
end
pump(); assert(#sends == 1 and sends[1][5] == 0xF6);
reply(fixtures.timing, sends[1]); pump();
assert(client._cooldownView().charges == 1);
local sentBefore, readBefore = #sends, reads;
for _ = 1, 216000 do pump(1 / 60); end
assert(#sends == sentBefore and reads == readBefore and client._cooldownView().charges == 3,
    'one idle hour must send no refreshes and read no recast slots');
native = 30.25; handlers.dlac_bst_stable({ id = 0x119 });
assert(reads == readBefore and client._cooldownView().charges == 3, 'packet callback must defer memory reads');
pump(); assert(reads == readBefore + 1 and client._cooldownView().charges == 1);
assert(#sends == sentBefore, 'native recast updates need no F6');
tab.render(); pump(1); local request = sends[#sends]; assert(request[5] == 0xF0);
local pages = fixtures.state.frames;
receive(frame(pages[1], request):sub(1, -5)); tab.render(); assert(context.state == nil, 'truncated page rejected');
local foreign = frame(pages[1], request);
foreign = foreign:sub(1, 12) .. string.rep('\255', 4) .. foreign:sub(17);
receive(foreign);
for i = #pages, 2, -1 do receive(frame(pages[i], request)); receive(frame(pages[i], request)); end
tab.render(); assert(context.state == nil, 'never publish incomplete or mismatched snapshots');
receive(frame(pages[1], request)); tab.render();
assert(context.state.revision == 9 and context.state.owned[135] and context.state.owned[3].dead);
assert(context.state.roster[1] == 2 and context.state.roster[2] == 3);
context.find(1); pump(1); request = sends[#sends]; assert(request[5] == 0xF4);
reply(fixtures.habitats, request); tab.render(); assert(context.habitats.rows[1]:find('East Ronfaure', 1, true));
-- Reopening refreshes once; consecutive rendered frames do not.
pump(1); pump(1); tab.render(); pump(1); request = sends[#sends]; assert(request[5] == 0xF0);
reply(fixtures.state, request); tab.render(); sentBefore = #sends;
for _ = 1, 60 do pump(1 / 60); tab.render(); end
assert(#sends == sentBefore);
-- A busy shared gate does not consume the response timeout before first send.
blocked = true; assert(client._request(0xF0));
for _ = 1, 15 do pump(1); tab.render(); end
assert(#sends == sentBefore and context.pending);
blocked = false; pump(1); assert(#sends == sentBefore + 1);
request = sends[#sends]; reply(fixtures.state, request); tab.render(); assert(not context.pending);
-- A disabled/older server gives an actionable response, not an endless retry.
for _, name in ipairs({'bad_request', 'bad_version', 'bad_job'}) do
    assert(client._request(0xF0)); pump(1); reply(fixtures[name], sends[#sends]); tab.render();
    assert(not context.pending and context.notice ~= 'Loading...');
end
assert(client._request(0xF0)); pump(1);
local badOp = frame(fixtures.bad_op.frames[1], sends[#sends]);
badOp = badOp:sub(1, 4) .. string.char(0xF0) .. badOp:sub(6); -- unknown F0 on an older generic dispatcher
receive(badOp); tab.render(); assert(context.notice == 'This server does not offer the Stable.');
handlers.dlac_bst_stable({ id = 0x08C }); pump(1); request = sends[#sends]; assert(request[5] == 0xF6);
level = 74; pump(1); local newer = sends[#sends];
reply(fixtures.timing, request); assert(client._cooldownView() == nil);
reply(fixtures.timing, newer); pump(); assert(client._cooldownView());
assert(client._request(0xF0)); handlers.dlac_bst_stable({ id = 0x00B }); sentBefore = #sends;
for _ = 1, 20 do pump(1); end
assert(#sends == sentBefore and tab == nil);
handlers.dlac_bst_stable({ id = 0x00A }); pump(1); assert(tab and #sends == sentBefore + 1);
job = 1; pump(); assert(tab == nil and client._cooldownView() == nil);
print('Stable protocol: real server fixtures, atomic paging, one idle hour, deferred native reads, tab reopen, blocked gate, statuses and zone/job lifecycle passed.');
