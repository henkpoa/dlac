-- lua tests/ascensionxi_digging_ui.lua
-- The AscensionXI Digging surfaces: the pure status lines, the bar and panel
-- blocks under a recording imgui stub, and the rank the server reports.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local failures, checks = 0, 0;
local function check(name, got, want)
    checks = checks + 1;
    if got ~= want then
        failures = failures + 1;
        print(string.format('FAIL %s: got %s, want %s', name, tostring(got), tostring(want)));
    end
end

-- A permissive imgui that records what the blocks draw.
local texts, boxes = {}, {};
local IM = setmetatable({}, { __index = function() return function() return false; end; end });
IM.TextUnformatted = function(t) texts[#texts + 1] = tostring(t); end;
IM.TextColored = function(_, t) texts[#texts + 1] = tostring(t); end;
IM.Text = function(t) texts[#texts + 1] = tostring(t); end;
IM.Checkbox = function(label, value) boxes[#boxes + 1] = { label = label, value = value[1] }; return false; end;
package.loaded['imgui'] = IM;
package.loaded['dlac\\ui\\uistyle'] = { helpLabel = function(_, text) texts[#texts + 1] = text; end };

local sp = require('dlac\\gear\\serverpack');
local cu = require('dlac\\ui\\chocoui');
local ladder = require('dlac\\feature\\digrank').RANKS;

-- Pure lines.
check('DU1 duration hours', cu.duration(3725), '1h 2m');
check('DU2 duration minutes', cu.duration(125), '2m');
check('DU3 duration seconds', cu.duration(20), 'under a minute');
check('DU4 no snapshot yet', cu.digStatusLines(nil, ladder, 3), nil);
local snap = { skill = 45.7, rank = 4, allowance = 123, cap = 504, credit = 72, delay = 1,
    voidAccess = true, storedGreens = 70, refillIn = function() return 3725; end };
local lines = cu.digStatusLines(snap, ladder, 12);
check('DU5 skill line', lines[1], 'Skill 45.7 (Apprentice)  Dig delay 1s');
check('DU6 allowance line', lines[2], 'Allowance 123/504  +72 in 1h 2m');
check('DU7 greens with Void Storage', lines[3], 'Gysahl Greens 12 in inventory, 70 in Void Storage');
snap.voidAccess = false;
check('DU8 greens without Void Storage', cu.digStatusLines(snap, ladder, nil)[3], 'Gysahl Greens ? in inventory');
snap.voidAccess = true;

-- Without the pack service nothing is drawn: CatsEye keeps its own surfaces.
sp._reset();
check('DU9 no service', cu.packDigging(), nil);
texts, boxes = {}, {};
cu.renderDigStatus(); cu.renderMoveDestinations('bar');
check('DU10 nothing drawn without the service', #texts + #boxes, 0);
local function panelText()
    texts, boxes = {}, {};
    pcall(cu.render, {}, 600);
    return table.concat(texts, '\n');
end
check('DU10b without the service the panel keeps the rank picker',
    panelText():find('Set your dig rank', 1, true) ~= nil, true);

-- With the service: the status block and the two switches.
local touched, value = 0, nil;
sp.provide('digging', { exactRank = true, status = {
    touch = function() touched = touched + 1; end,
    value = function() return value; end,
    rank = function() return value and value.rank or nil; end,
} });
texts = {};
cu.renderDigStatus();
check('DU11 the status block polls', touched, 1);
check('DU12 waiting for the server', texts[1], 'Digging status: waiting for the server.');
value = snap;
texts = {};
cu.renderDigStatus();
check('DU13 three status lines', #texts, 3);
check('DU14 first line', texts[1], 'Skill 45.7 (Apprentice)  Dig delay 1s');
local shown = panelText();
check('DU14b the panel shows the server status, not the rank picker',
    shown:find('Skill 45.7', 1, true) ~= nil and shown:find('Set your dig rank', 1, true) == nil, true);

local moved = {};
package.loaded['dlac\\feature\\chocowatch'] = {
    moveCase = true, moveSatchel = false, loadState = function() end,
    setMoveDestination = function(cid, on) moved[#moved + 1] = cid .. '=' .. tostring(on); end,
};
package.loaded['dlac\\feature\\digstorage'] = { live = { status = 'Dug items moved.', waiting = function() return 3; end } };
texts, boxes = {}, {};
cu.renderMoveDestinations('bar');
check('DU15 two destinations', #boxes, 2);
check('DU16 Mog Case checked', boxes[1].label == 'Mog Case##digmovebar' and boxes[1].value, true);
check('DU17 Mog Satchel unchecked', boxes[2].label == 'Mog Satchel##digmovebar' and boxes[2].value, false);
check('DU18 mover status shown', texts[2], 'Dug items moved.');
check('DU19 waiting count shown', texts[3], '3 dug items waiting for a full stack or a pause.');
IM.Checkbox = function(label, value) if label:find('Satchel', 1, true) then value[1] = true; return true; end return false; end;
cu.renderMoveDestinations('panel');
check('DU20 a click sets the destination', moved[1], '5=true');

-- chocowatch reads the server's rank as exact and stops guessing. The ratchet
-- needs a dig table to read a find as a rank, so give it ours.
require('dlac\\feature\\digcalc')._setDb(dofile('servers/ascensionxi/data/digdata.lua'));
package.loaded['dlac\\feature\\chocowatch'] = nil;
local cw = require('dlac\\feature\\chocowatch');
check('DU21 server rank wins', cw.serverRankLive(), 4);
local rs = cw.rankState();
check('DU22 rank state exact', rs.exact and rs.rank, 4);
check('DU23 no timing guess with the service', cw.recordDigTiming(1), false);
check('DU24 no item ratchet with the service', cw.recordObtained('King Truffle'), false);
check('DU24b no item-id ratchet with the service', cw.recordObtainedById(4386, 2), false);
value = nil;
check('DU25 unknown until the server answers', cw.serverRankLive(), nil);
local service = sp.service('digging');
sp._reset();
check('DU25b without the service a find raises the rank', cw.recordObtained('King Truffle'), true);
sp.provide('digging', service);

-- The AscensionXI dig table drives the odds engine.
sp._reset();
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
package.loaded['dlac\\feature\\digcalc'] = nil;
local dc = require('dlac\\feature\\digcalc');
local db = dc.db();
check('DU26 AXI table loads', type(db) == 'table' and #dc.zones(), 26);
local listed = false;
for _, name in ipairs(sp.modules() or {}) do if name == 'digging' then listed = true; end end
check('DU26b the pack lists its digging module', listed, true);
local carpenters = dc.zoneOdds(2, 8, dc.moonMult(0));
check('DU27 King Truffle priced at Adept', carpenters ~= nil and carpenters.pools[1].pool, 'Treasure');
check('DU28 Burrow and Bore granted', db.zones[2].pools.Burrow ~= nil and db.zones[2].pools.Bore ~= nil, true);
-- La Theine (102) is an ore zone: Firesday ore under ANY elemental weather here.
local function ore(weather)
    for _, c in ipairs(dc.conditionalDrops(102, 6, { dayElement = 'Fire', weatherElement = weather, moonPercent = 10 })) do
        if c.kind == 'ore' then return c; end
    end
end
check('DU29 ore with the day\'s weather', ore('Fire').active, true);
check('DU30 ore with another element\'s weather', ore('Water').active, true);
check('DU31 no ore without elemental weather', ore('Clear').active, false);
check('DU32 the condition says so', ore('Water').condition, 'Fire day + any elemental weather, moon 7-21%');
local fireOre = nil;
for _, e in ipairs(dc.itemIndex()) do if e.n == 'Fire Ore' then fireOre = e; end end
check('DU33 ores searchable by client name', fireOre ~= nil, true);
local sources = dc.itemSources(fireOre, 6, 1, { dayElement = 'Fire', weatherElement = 'Water', moonPercent = 10 });
check('DU33b the item search takes any elemental weather too', sources ~= nil and sources.clockActive, true);

-- The move switches: 7 is the Mog Case, 5 the Satchel; saved per character,
-- read back, and a change wakes the mover.
local stateDir = (os.getenv('TEMP') or '.') .. '/dlac_digging_ui_';
os.remove(stateDir .. 'chocostate.lua');
package.loaded['dlac\\lib\\statefile'] = { charDir = function() return stateDir; end };
local woken = 0;
package.loaded['dlac\\feature\\digstorage'] = { live = { changed = function() woken = woken + 1; end } };
package.loaded['dlac\\feature\\chocowatch'] = nil;
cw = require('dlac\\feature\\chocowatch');
cw.setMoveDestination(5, true);
check('DU34 the Satchel is container 5', cw.moveSatchel == true and cw.moveCase == false, true);
check('DU35 a switch change wakes the mover', woken, 1);
package.loaded['dlac\\feature\\chocowatch'] = nil;
cw = require('dlac\\feature\\chocowatch');
cw.loadState();
check('DU36 the switches are saved and read back', cw.moveSatchel == true and cw.moveCase == false, true);
os.remove(stateDir .. 'chocostate.lua');
package.loaded['dlac\\lib\\statefile'] = nil;

-- The panel counts only Gysahl Greens in the inventory.
AshitaCore = { GetMemoryManager = function() return { GetInventory = function() return {
    GetContainerCountMax = function() return 3; end,
    GetContainerItem = function(_, _, slot)
        return ({ { Id = 4545, Count = 12 }, { Id = 4096, Count = 5 }, { Id = 4545, Count = 3 } })[slot];
    end,
}; end }; end };
check('DU37 inventory greens', cu.inventoryGreens(), 15);
AshitaCore = nil;

-- The addon loads the dig mover (dlac.lua's module list cannot run headless).
local entry = assert(io.open('dlac.lua', 'rb')):read('a');
check('DU38 dlac loads the dig mover', entry:find("'feature\\\\digstorage'", 1, true) ~= nil, true);

if failures > 0 then
    print(string.format('FAIL -- %d of %d checks failed', failures, checks));
    os.exit(1);
end
print(string.format('OK -- %d digging UI checks passed', checks));
