-- Real CEXI pack/module mounting with a headless client. Run from addon root.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
if not pcall(require, 'bit') then
    package.loaded.bit = assert(load([[
        return { band = function(a,b) return a & b end,
            bor = function(a,b) return a | b end,
            bxor = function(a,b) return a ~ b end,
            lshift = function(a,b) return a << b end,
            rshift = function(a,b) return a >> b end }
    ]]))();
end
local handlers, packets = {}, 0;
ashita = { events = { register = function(event, name, fn)
    handlers[event] = handlers[event] or {}; handlers[event][name] = fn;
end }, packet = { add_outgoing = function() packets = packets + 1; end } };
gData = { GetPlayer = function() return nil; end };
package.loaded.imgui = {};
local ledger = { total = 0, failed = {} };
package.loaded['dlac\\loadledger'] = ledger;
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'cexi' }; end;
sp.init();
assert(sp.active() == 'cexi');
assert(table.concat(sp.modules(), ',') == 'gamemode,prestige,ebox,giftbox');
local mods = require('dlac\\feature\\servermods');
mods.load();
assert(#ledger.failed == 0, ledger.failed[1] and ledger.failed[1].err);
assert(table.concat(mods.list(), ',') == 'gamemode,prestige,ebox,giftbox');
assert(not mods.get('stable') and not sp.service('bstGauge'));
for _ = 1, 60 do mods.pump(); end
assert(packets == 0, 'idle CEXI must not send AXI Stable queries');
for name in pairs(package.loaded) do
    assert(not name:find('dlac\\servers\\ascensionxi\\modules\\', 1, true),
        'CEXI loaded an AXI module: ' .. name);
end
assert(sp.data('catalog') == require('dlac\\servers\\cexi\\data\\catalog'));
assert(sp.data('petmods') == require('dlac\\servers\\cexi\\data\\petmods'));
local gate = require('dlac\\lib\\featuregate');
local function offersStable()
    for _, tab in ipairs(gate.tabOptions()) do if tab.key == 'stable' then return true; end end
    return false;
end
gate.set('tab', 'stable', true);
assert(not offersStable(), 'a saved override cannot expose an unsupported Settings control');
local stats = require('dlac\\gear\\statdefs');
assert(sp.statdefs() == nil and stats.get('BSTShinyChance').label == 'BSTShinyChance');
-- Reset models addon reload; live server selection deliberately reloads the addon.
sp._reset(); sp._configLoader = function() return { server = 'ascensionxi' }; end; sp.init();
assert(offersStable() and stats.get('BSTShinyChance').label == 'Shiny Chance Bonus');
sp._reset(); sp._configLoader = function() return { server = 'cexi' }; end; sp.init();
assert(not offersStable() and sp.statdefs() == nil);
assert(stats.get('BSTShinyChance').label == 'BSTShinyChance', 'pack stat cache must reset');
sp._reset(); sp._configLoader = function() return {}; end;
sp._bootReader = function() return {}; end; sp._emit = function() end; sp.init();
assert(sp.active() == nil and sp.needsChoice() and #sp.modules() == 0 and not offersStable());
local recast = require('dlac\\feature\\recast');
local jiffies = 91;
recast._recastMgr = function() return {
    GetAbilityTimerId = function(_, slot) return slot == 0 and 102 or 0; end,
    GetAbilityTimer = function() return jiffies; end,
}; end;
for _, value in ipairs({ 0, 1, 29, 30, 59, 60, 89, 90, 91, 1800 }) do
    jiffies = value;
    assert(recast.liveRemaining({ timerId = 102 }) == math.floor(value / 60 + 0.5));
    assert(recast.liveRemainingSeconds({ timerId = 102 }) == value / 60);
end
assert(recast.liveRemaining({ timerId = 999 }) == 0);
recast._recastMgr = function() return nil; end;
assert(recast.liveRemaining({ timerId = 102 }) == nil);
print('Server isolation: real CEXI modules/data, no AXI modules/packets/gauge/setting, stat reset, neutral selection and shared recast compatibility passed.');
