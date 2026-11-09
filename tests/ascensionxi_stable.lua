-- Run from a clean DLAC checkout: lua tests/ascensionxi_stable.lua
-- No server checkout, installed addon or player configuration is required.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local mounted = {};
for _, name in ipairs(sp.modules()) do mounted[name] = true; end
assert(mounted.stable and mounted.gearvault and mounted.pldgauge and mounted.telemetry);
local catalog = require('dlac\\servers\\ascensionxi\\modules\\stable\\catalog');
assert(#catalog == 67);
for _, entry in ipairs(catalog) do
    assert(entry.name and #entry.moves > 0 and entry.catchMinLevel <= entry.catchMaxLevel);
    for _, suffix in ipairs({ '', '-shiny' }) do
        local f = assert(io.open('servers/ascensionxi/assets/stable/' .. entry.key .. suffix .. '.png', 'rb'));
        assert(f:read(8) == '\137PNG\13\10\26\10'); f:close();
    end
end
local handlers, tab = {}, nil;
ashita = { events = { register = function(_, name, fn) handlers[name] = fn; end } };
package.loaded.imgui = {};
package.loaded['dlac\\ui\\filetex'] = {};
package.loaded['dlac\\ui\\uihost'] = { register = function(spec) tab = spec.tabs[1]; end };
local job, now, sends = 1, 10, {};
AshitaCore = { GetMemoryManager = function() return { GetPlayer = function() return {
    GetMainJob = function() return job; end,
}; end }; end };
local transport = require('dlac\\servers\\ascensionxi\\transport');
transport._clock = function() return now; end;
transport._send = function(packet) sends[#sends + 1] = packet; return true; end;
local stable = require('dlac\\servers\\ascensionxi\\modules\\stable\\init');
assert(tab == nil, 'Stable is hidden off main-job BST');
assert(handlers.dlac_bst_stable and handlers.dlac_bst_ready_gauge);
stable.pump(); handlers.dlac_bst_ready_gauge();
assert(#sends == 0 and stable._cooldownView() == nil, 'non-BST must not poll or draw');
job = 9; now = 13; stable.pump();
assert(tab.label == 'Stable' and type(tab.render) == 'function');
assert(#sends == 1 and sends[1][5] == 0xF6, 'BST must use the real shared transport');
local op, seq = sends[1][5], sends[1][6];
handlers.dlac_bst_stable({ id = 0x00B });
now = 17; stable.pump();
assert(#sends == 1 and stable._cooldownView() == nil, 'zone-out must suspend requests and clear the gauge');
handlers.dlac_bst_stable({ id = 0x00A });
now = 21; stable.pump();
assert(#sends == 2 and sends[2][5] == 0xF6, 'zone-in must resume through the transport');
handlers.dlac_bst_stable({ id = 0x00B });
job = 1; handlers.dlac_bst_stable({ id = 0x00A }); now = 25; stable.pump();
assert(#sends == 2, 'changing jobs must stop gauge requests');
print('Stable clean-install checks passed: pack mount, 67 entries, 134 PNGs, UI registration, real transport and job/zone lifecycle.');
