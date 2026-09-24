-- Run from the addon root: lua tests/lockstyle_vault.lua
ashita = { events = { register = function() end } };
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local bag = { Name = 'Bag Cap', Id = 100, Level = 1 };
local vault = { Name = 'Vault Cap', Id = 200, Level = 1, AugKey = 'old-roll' };
local gone = { Name = 'Gone Cap', Id = 300, Level = 1 };
package.loaded['dlac\\gear'] = {
    Head = { bag, vault, gone },
    NameToObject = { [bag.Name] = bag, [vault.Name] = vault, [gone.Name] = gone },
};
local owned = require('dlac\\gear\\ownedcache');
local importer = require('dlac\\gear\\gearimport');
local ls = require('dlac\\feature\\lockstyle');
local split = { avail = { [100] = 1 }, total = { [100] = 1 }, where = {}, aug = {} };
importer.foldVault(split, { [200] = 1 });
owned._splitOverride = split;
ls.wire({ ownsLook = owned.haveAppearance,
    ownedById = function(id) return ({ [100] = bag, [200] = vault, [300] = gone })[id]; end,
    allEquip = function() return {
        { Name = bag.Name, Id = 100, Slot = 'Head', Model = 1 },
        { Name = vault.Name, Id = 200, Slot = 'Head', Model = 2 },
        { Name = gone.Name, Id = 300, Slot = 'Head', Model = 3 },
    }; end,
});
assert(dofile('servers/ascensionxi/features.lua').menu.lockstyle == true);
assert(#ls._listFor('Head', '') == 2, 'bag and vault pieces appear; removed piece does not');
assert(#ls._listFor('Head', 'vault') == 1, 'vault-only appearance is searchable');
assert(ls._nameOwned(vault.Name), 'vault-only appearance can be saved');
assert(ls._ownedRec({ Id = 200 }) == vault, 'catalog picks recognize vault ownership');
assert(not ls._nameOwned(gone.Name), 'saved gear membership is not ownership');
assert(ls._ownedRec({ Id = 300 }) == nil, 'removed catalog piece is preview-only');
assert(#ls._listFor('Head', '', true) == 3, 'unowned preview remains available');
assert(split.avail[200] == nil, 'appearance ownership does not make vault gear equippable');
assert(ls._nameOwned('remove'), 'empty appearance is always allowed');
split.total[200] = nil;
assert(not ls._nameOwned(vault.Name), 'vault removal updates save eligibility');
assert(#ls._listFor('Head', '') == 1, 'vault removal updates picker');
owned._splitOverride = { avail = {}, total = {} };
assert(ls._nameOwned(vault.Name), 'unknown ownership preserves startup fallback');
print('lockstyle vault tests passed');
