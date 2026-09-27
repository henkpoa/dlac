-- lua tests/restock_notice.lua (from the repo root)
table.insert(package.searchers, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local sp = require('dlac\\gear\\serverpack');
for _, server in ipairs({ 'ascensionxi', 'cexi' }) do
    sp._reset();
    sp._configLoader = function() return { server = server }; end;
    sp.init();
    local found = false;
    for _, name in ipairs(sp.modules()) do
        if name == 'restocknotice' then found = true; end
        if server == 'ascensionxi' then assert(name ~= 'voidrestock', 'retired module stays unmounted'); end
    end
    assert(found == (server == 'ascensionxi'), 'notice is AscensionXI-only');
end

local handler, messages = nil, {};
ashita = { events = { register = function(kind, _, callback)
    assert(kind == 'command', 'notice must not register packet handlers');
    assert(handler == nil, 'one command registration');
    handler = callback;
end } };
package.loaded['dlac\\chatfmt'] = { print = function(text) messages[#messages + 1] = text; end };
local mod = require('dlac\\servers\\ascensionxi\\modules\\restocknotice\\init');
assert(mod.pump == nil, 'notice has no background work');
assert(type(handler) == 'function');
for _, command in ipairs({ '/dl restock', '/DL RESTOCK', '/dl  restock  ' }) do
    local e = { command = command };
    local before = #messages;
    handler(e);
    assert(e.blocked == true and #messages == before + 1, 'exactly one line and command consumed');
    assert(messages[#messages] == 'Void Restock moved to Nexus: /nexus restock (fetch, store or stop).');
end
for _, command in ipairs({ '', '/dl restocking', '/dl restock fetch', '/nexus restock', '!void', '/dl vault' }) do
    local e, before = { command = command }, #messages;
    handler(e);
    assert(e.blocked == nil and #messages == before, 'unrelated commands are untouched');
end
handler({});
print('AscensionXI restock notice: PASS');
