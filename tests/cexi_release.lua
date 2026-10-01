-- Execute from an EXTRACTED CEXI ZIP, not the source checkout.
table.insert(package.searchers, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local function absent(path)
    local f = io.open(path, 'rb');
    if f then f:close(); error('Restricted file shipped: ' .. path); end
end
for _, p in ipairs({ 'feature/synthrun.lua', 'servers/cexi/modules/ebox/restockui.lua',
    'servers/cexi/modules/ebox/restockwatch.lua', 'servers/cexi/modules/ebox/eboxtrace.lua',
    'servers/ascensionxi/manifest.lua' }) do absent(p); end

-- A single installed pack must choose CEXI even with an old AXI config.
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
assert(sp.active() == 'cexi');
assert(not sp.cap('ebox'));
assert(sp.const('synthRepeat') == false);
for _, name in ipairs(sp.manifest().modules) do assert(name ~= 'ebox'); end
local originalRequire = require;
require = function(name) error('Inert E-Box entry loaded: ' .. name); end;
assert(next(dofile('servers/cexi/modules/ebox/init.lua')) == nil);
require = originalRequire;

-- Proximity uses the shared watcher and cannot issue a storage request.
local distance, watched = nil, 0;
package.loaded['dlac\\lib\\entwatch'] = {
    watch = function(who, name)
        assert(who == 'eboxclient' and name == 'Ephemeral Box'); watched = watched + 1;
    end,
    nearest = function(name) assert(name == 'Ephemeral Box'); return distance; end,
};
local ec = require('dlac\\servers\\cexi\\modules\\ebox\\eboxclient');
assert(ec.withdraw == nil and ec.withdrawBatch == nil and ec.search == nil);
assert(not ec.nearBox());
distance = 5; assert(ec.nearBox());
distance = 5.01; assert(not ec.nearBox());
assert(watched == 3);

-- Exercise the actual Giftbox place gate with the packaged proximity reader.
local mode, town, have = 'CW', false, true;
package.loaded['dlac\\servers\\cexi\\modules\\gamemode\\init'] = { get = function() return mode; end };
package.loaded['dlac\\feature\\location'] = { inTown = function() return town; end };
package.loaded['dlac\\servers\\cexi\\modules\\giftbox\\giftbox'] = {
    peek = function() return { have = have }; end,
};
package.loaded['dlac\\ui\\itemicons'] = {};
local gb = require('dlac\\servers\\cexi\\modules\\giftbox\\giftboxui');
distance = 5; assert(gb.trayWants());
distance = 6; assert(not gb.trayWants());
mode = 'ACE'; assert(not gb.trayWants());
town = true; assert(gb.trayWants());
have = false; assert(not gb.trayWants());

-- Draw the real packaged craft bar, clicking every button. No craft command
-- may be issued; gear selection and all three goal choices must remain.
local buttons, selected, goals, texts = {}, {}, {}, {};
local nop = function() end;
local IM = setmetatable({
    CalcTextSize = function(s) return #s * 8; end,
    IsItemHovered = function() return true; end,
    IsItemClicked = function() return false; end,
    GetCursorPosX = function() return 0; end,
    Button = function(label) buttons[#buttons + 1] = label; return true; end,
    TextColored = function(_, s) texts[#texts + 1] = s; end,
}, { __index = function() return nop; end });
package.loaded['imgui'] = IM;
package.loaded['dlac\\ui\\uistyle'] = {};
package.loaded['dlac\\ui\\panelkit'] = {};
package.loaded['dlac\\feature\\craftwatch'] = {
    getCraft = function() return 'Alchemy'; end,
    isEnabled = function() return true; end,
    setEnabled = nop,
    getGoal = function() return 'hq'; end,
    setGoal = function(g) goals[g] = true; end,
    selectCraft = function(c) selected[c] = true; end,
    lastSynth = function() return { name = 'Test Recipe', skill = 'Alchemy', lv = 10 }; end,
};
ImGuiCol_Button, ImGuiCol_Text = 1, 2;
AshitaCore = { GetChatManager = function() error('Craft bar accessed the command manager'); end };
local cb = require('dlac\\ui\\craftbar');
cb.renderContent(600);
assert(goals.hq and goals.nq and goals.skillup);
assert(selected.Alchemy and selected.Cooking);
assert(table.concat(texts, '|'):find('Test Recipe', 1, true));
for _, label in ipairs(buttons) do
    assert(not label:find('cblast', 1, true) and not label:find('cbrep', 1, true)
        and not label:find('cbwait', 1, true), 'Restricted button: ' .. label);
end
print('CEXI package: selection, exclusions, Giftbox proximity and craft UI passed.');
