table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local catalog = require('dlac\\servers\\ascensionxi\\modules\\stable\\catalog');
local state = { owned = {} };
for id = 2, 135 do state.owned[id] = { name = id == 2 and 'Flopsy' or '' }; end
local grid = require('dlac\\servers\\ascensionxi\\modules\\stable\\grid');
local cards = grid.cards(catalog, state, '', 'all', 'all'); assert(#cards == 134);
for _ = 1, 1000 do assert(grid.cards(catalog, state, '', 'all', 'all') == cards); end
local matched = grid.cards(catalog, state, 'flopSY', 'regular', 'owned'); assert(#matched == 1 and matched[1] == 2);
assert(#grid.cards(catalog, state, '', 'shiny', 'owned') == 67);
assert(#grid.cards(catalog, { owned = {} }, '', 'all', 'missing') == 134);
local first, last, total = grid.rows(134, 4, 250, 0, 500, 8);
assert(first == 0 and last == 3 and total == 34 and (last - first) * 4 == 12, 'only 12 viewport/overscan cards, not 134');
first, last = grid.rows(134, 4, 250, 8000, 500, 8);
assert(first == 31 and last == 34, 'the end of the collection remains reachable');
local bytes = 0;
local function u32be(s, index)
    local a, b, c, d = s:byte(index, index + 3); return ((a * 256 + b) * 256 + c) * 256 + d;
end
for _, entry in ipairs(catalog) do
    assert(entry.uv0 == nil and entry.uv1 == nil, 'cropped portraits must not be cropped twice');
    for _, suffix in ipairs({'', '-shiny'}) do
        local f = assert(io.open('servers/ascensionxi/assets/stable/' .. entry.key .. suffix .. '.png', 'rb'));
        local data = f:read('*a'); f:close(); bytes = bytes + #data;
        assert(u32be(data, 17) == 256 and u32be(data, 21) == 256);
    end
end
-- Exercise the actual deferred loader, including duplicate requests and object retention.
local loads, releases, handler = 0, 0, nil;
package.loaded.ffi = {
    cdef = function() end, new = function() return {}; end, cast = function(_, x) return x; end,
    C = { D3DXCreateTextureFromFileA = function(_, _, ptr) loads = loads + 1; ptr[0] = loads; return 0; end },
};
package.loaded.d3d8 = { get_device = function() return 1; end,
    gc_safe_release = function(tex) releases = releases + 1; return tex; end };
-- filetex is first required mid-draw, so it must register NO event handler:
-- an older Ashita (CatsEyeXI's) calls a nil and unloads dlac when a d3d_present
-- handler is added while d3d_present dispatches. dlac.lua's frame beat pumps it.
local registered = {};
ashita = { events = { register = function(evt, name) registered[#registered + 1] = evt .. '/' .. name; end } };
AshitaCore = { GetInstallPath = function() return 'test/'; end };
local textures = require('dlac\\ui\\filetex');
assert(#registered == 0, 'filetex registered ' .. table.concat(registered, ', ') .. ' on require');
handler = textures.pump;
local beat = assert(io.open('dlac.lua', 'rb')):read('*a');
assert(beat:find("require('dlac\\\\ui\\\\filetex').pump()", 1, true), "dlac.lua's frame beat must pump the texture queue");
for _ = 1, 2 do for id = 1, 134 do assert(textures.queuedPackHandle('ascensionxi', 'stable/' .. id) == nil); end end
assert(loads == 0, 'rendering must never synchronously load a collection texture');
for frame = 1, 67 do handler(); assert(loads == frame * 2); end
handler(); assert(loads == 134 and releases == 134, 'duplicates must not reload or release cached objects');
assert(textures.queuedPackHandle('ascensionxi', 'stable/1') == 1);
collectgarbage(); handler(); assert(loads == 134);
local cexi = textures.packHandle('cexi', 'existing-icon');
assert(cexi and loads == 135, 'existing synchronous pack textures still load immediately');
assert(textures.packHandle('cexi', 'existing-icon') == cexi and loads == 135);
local shared = textures.handle('existing-icon');
assert(shared and shared ~= cexi and loads == 136, 'shared and pack texture paths stay distinct');
handler(); assert(loads == 136, 'an empty queue adds no texture work');
print(string.format('Stable assets: cached filters, clipped rows, 134 cropped portraits (%.2f MiB), two loads/frame and texture retention passed.', bytes / 1048576));
