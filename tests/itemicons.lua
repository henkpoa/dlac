-- Run from the addon root: lua tests/itemicons.lua
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local active, assetPresent = 'ascensionxi', true;
local resourceReads, images, releases = {}, {}, 0;
local texture = { Release = function() releases = releases + 1; end };
package.loaded['dlac\\gear\\serverpack'] = { active = function() return active; end };
package.loaded['dlac\\ui\\filetex'] = { packHandle = function(pack, name)
    assert(pack == 'ascensionxi');
    local id = tonumber(name:match('^items/(%d+)$'));
    assert(id, 'use the pack-declared artwork');
    return assetPresent and id or nil;
end };
package.loaded.imgui = { Image = function(h) images[#images + 1] = h; end,
    SameLine = function() end, Dummy = function() end };
package.loaded.ffi = { cdef = function() end, new = function() return {}; end,
    cast = function(kind, v) return kind == 'uint32_t' and 42 or v; end,
    gc = function() end, C = { S_OK = 0,
        D3DXCreateTextureFromFileInMemoryEx = function(...)
            local args = {...}; args[15][0] = texture; return 0;
        end } };
package.loaded.d3d8 = { get_device = function() return {}; end,
    gc_safe_release = function(t) return t; end };
AshitaCore = { GetResourceManager = function() return {
    GetItemById = function(_, id)
        resourceReads[#resourceReads + 1] = id;
        return { ImageSize = 1, Bitmap = 'retail placeholder' };
    end,
}; end };
local icons = dofile('ui/itemicons.lua');
assert(icons.handleOf(26549) == 26549, 'Rabbit Charm +1 must use the staging charm artwork, not the gray retail placeholder');
icons.renderIcon(26549, 18);
assert(images[1] == 26549 and #resourceReads == 0, 'rows and equipped grid share the override');
assert(icons.handleOf(26550) == 26550, 'Field Cap must use its custom artwork too');
icons.renderIcon(26550, 18);
assert(images[2] == 26550 and #resourceReads == 0, 'Field Cap must not load the gray placeholder');
local catalog = dofile('gear/catalogindex.lua');
local _, byId = catalog.flatten(dofile('servers/ascensionxi/data/catalog.lua'));
for id, asset in pairs(dofile('servers/ascensionxi/itemicons.lua')) do
    assert(byId[id], 'generated artwork must belong to the pack catalog');
    assert(icons.handleOf(id) == id, 'every generated override must reach the shared icon service');
    local f = assert(io.open('servers/ascensionxi/assets/' .. asset .. '.png', 'rb'), 'missing generated artwork');
    local header = f:read(24); f:close();
    assert(header:sub(1, 8) == '\137PNG\r\n\26\n', 'override must be a PNG');
    assert(header:sub(17, 24) == '\0\0\0\32\0\0\0\32', 'item artwork must be 32x32');
end
assert(icons.handleOf(13112) == 42 and resourceReads[1] == 13112, 'ordinary items keep client icons');
icons.release(); assert(releases == 1, 'only release textures owned by itemicons');
assetPresent = false;
assert(icons.handleOf(26549) == 42, 'missing pack artwork falls back to the client');
icons.release();
assetPresent, active = true, 'cexi';
icons = dofile('ui/itemicons.lua');
assert(icons.handleOf(26549) == 42, 'AscensionXI artwork must not leak to other packs');
assert(icons.handleOf(nil) == nil and icons.handleOf(0) == nil);

-- Verify the real loader uses the pack folder, so copying a generated pack
-- cannot leave its artwork behind in a different addon directory.
local paths = {};
AshitaCore.GetInstallPath = function() return 'C:/Ashita/'; end;
package.loaded.ffi.C.D3DXCreateTextureFromFileA = function(_, path, ptr)
    paths[#paths + 1] = path; ptr[0] = texture; return 0;
end;
local filetex = dofile('ui/filetex.lua');
assert(filetex.packHandle('ascensionxi', 'items/26550') == 42);
assert(paths[1] == 'C:/Ashita/addons\\dlac\\servers\\ascensionxi\\assets\\items/26550.png');
assert(filetex.handle('menu') == 42);
assert(paths[2] == 'C:/Ashita/addons\\dlac\\assets\\menu.png');
filetex.packHandle('ascensionxi', 'items/26550');
assert(#paths == 2, 'pack textures are cached too');
print('OK -- pack item icons, shared rendering, fallback and texture ownership');
