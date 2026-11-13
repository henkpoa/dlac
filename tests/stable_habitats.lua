table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
package.loaded.imgui = {};
package.loaded['dlac\\ui\\filetex'] = {};
local view = require('dlac\\servers\\ascensionxi\\modules\\stable\\view');
local a = {view.parseHabitat('East Ronfaure|Wild Rabbit|1|1|50|60')};
assert(a[1] == 'East Ronfaure' and a[6] == '60' and a[7] == '');
local b = {view.parseHabitat('Psoxja|Diremite|43|45|2|300|Beaucedine F-7 entrance; uncapped tower.')};
assert(b[3] == '43' and b[4] == '45' and b[5] == '2' and b[7]:find('F-7', 1, true));
assert(not view.parseHabitat('Zone|Mob|1|2|3|60|note|extra'));
assert(not view.parseHabitat('Zone|Mob|1|2|3|60garbage'));
assert(not view.parseHabitat('Zone|Mob|one|2|3|60'));
assert(not view.parseHabitat(nil));
print('AXI catch habitats: legacy rows, entrance notes and malformed rows passed.');
