-- lua tests/ascensionxi_divine_elements.lua   (from the dlac repo root)
-- The AscensionXI Paladin's Divine Elements helper: the element rules (the
-- server's own, pld_divine_fury.lua), the plan the window draws (what the
-- held elements give, what each level 2 property costs), when the window
-- shows, and that the module is a valid read-only helper the AscensionXI
-- pack lists.
-- Server contract: ascensionxi repo, documentation/custom/pld-divine-guard.md section 8.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);

local checks = 0;
local function check(cond, msg)
    checks = checks + 1;
    if not cond then error('FAIL: ' .. msg, 2); end
end

local function has(list, value)
    for _, v in ipairs(list) do if v == value then return true; end end
    return false;
end

local rules = require('dlac\\jobhelpers\\pld\\divine-elements\\rules');
local data  = require('dlac\\jobhelpers\\pld\\divine-elements\\data\\weaponskills');

-- ---------------------------------------------------------------------------
-- the rules (the server's pf.addedProperties)
-- ---------------------------------------------------------------------------
local added = rules.added({ 'Scission' }, { 'Dark' });
check(#added == 2 and added[1] == 'Gravitation' and added[2] == 'Compression',
      'Crescent Moon (Scission) + Dark adds Gravitation, then Compression');
added = rules.added({ 'Fragmentation' }, { 'Fire', 'Light' });
check(has(added, 'Fusion') and has(added, 'Liquefaction') and has(added, 'Transfixion'),
      'Spinning Slash + Fire + Light adds Fusion and both level 1s');
added = rules.added({ 'Fusion' }, { 'Earth', 'Dark' });
check(added[1] == 'Gravitation', 'the two elements pair with each other: Earth + Dark gives a Fusion weapon skill Gravitation');
added = rules.added({ 'Impaction', 'Detonation' }, {});
check(#added == 0, "a pair made only of the weapon skill's own properties adds nothing (True Strike)");
added = rules.added({ 'Scission' }, { 'Fire' });
check(#added == 1 and added[1] == 'Liquefaction', 'Fire pairs with nothing on Scission');
added = rules.added({ 'Light', 'Distortion' }, { 'Fire' });
check(has(added, 'Fusion'), "a level 3 property's four elements count too (Torcleaver + Fire: Fusion)");
check(rules.pairOf('Water', 'Ice') == 'Distortion' and rules.pairOf('Fire', 'Ice') == nil, 'pairs');

local held = rules.held({ [655] = true, [667] = true, [663] = true });
check(#held == 2 and held[1] == 'Earth' and held[2] == 'Dark', 'held elements read from icons 660-667, in element order');
check(rules.names({ 'A', 'B', 'C', 'D', 'E' }) == 'A, B, C (+2)', 'three names, then a count');

check(data.ws[53].name == 'Crescent Moon' and data.ws[53].sc[1] == 'Scission', 'the generated table has Crescent Moon');
check(data.ws[56].sc[1] == 'Fragmentation' and data.ws[56].sc[2] == 'Distortion',
      "Ground Strike's properties are the server's (Fragmentation, Distortion)");
check(data.ws[39] ~= nil and #data.ws[39].sc == 0, 'Spirits Within is listed with no properties (the elements give it some)');

-- ---------------------------------------------------------------------------
-- the plan
-- ---------------------------------------------------------------------------
local WS = {
    { name = 'Crescent Moon',  sc = { 'Scission' } },
    { name = 'Freezebite',     sc = { 'Induration', 'Detonation' } },
    { name = 'Power Slash',    sc = { 'Transfixion' } },
    { name = 'Spinning Slash', sc = { 'Fragmentation' } },
};
local function build(plan, prop)
    for _, b in ipairs(plan.builds) do if b.prop == prop then return b; end end
end
local function label(row)
    if row.kind == 'own' then return table.concat(row.skills, ',') .. ' own'; end
    if row.kind == 'any' then return 'any ' .. table.concat(row.elements, '+'); end
    return table.concat(row.skills, ',') .. ' + ' .. table.concat(row.elements, '+');
end
local function labels(b)
    local out = {};
    for i, row in ipairs(b.rows) do out[i] = label(row); end
    return table.concat(out, ' | ');
end

local plan = rules.plan({ weaponskills = WS, held = {}, level = 75, points = 3 });
check(#plan.gives == 0, 'holding nothing gives nothing');
check(#plan.builds == 4 and plan.builds[1].prop == 'Fusion' and plan.builds[4].prop == 'Distortion', 'four level 2 properties, in order');
check(labels(build(plan, 'Fusion')) == 'Power Slash + Fire | any Fire+Light', 'Fusion: Power Slash + Fire, then any + Fire + Light: ' .. labels(build(plan, 'Fusion')));
check(labels(build(plan, 'Fragmentation')) == 'Spinning Slash own | Freezebite + Lightning | any Wind+Lightning',
      'Fragmentation: Spinning Slash has it, Freezebite + Lightning, any + Wind + Lightning: ' .. labels(build(plan, 'Fragmentation')));
check(labels(build(plan, 'Gravitation')) == 'Crescent Moon + Dark | any Earth+Dark', 'Gravitation: ' .. labels(build(plan, 'Gravitation')));
check(labels(build(plan, 'Distortion')) == 'Freezebite + Water | any Ice+Water', 'Distortion: ' .. labels(build(plan, 'Distortion')));
local fusion = build(plan, 'Fusion');
check(fusion.rows[1].cost == 1 and fusion.rows[2].cost == 2 and fusion.rows[1].affordable and fusion.rows[2].affordable,
      'one element costs a point, two cost two, both within 3 points');

plan = rules.plan({ weaponskills = WS, held = { 'Dark' }, level = 75, points = 1 });
check(#plan.gives == 2, 'holding Dark: two answers');
check(plan.gives[1].skills[1] == 'Crescent Moon' and plan.gives[1].props[1] == 'Gravitation' and plan.gives[1].props[2] == 'Compression',
      'Crescent Moon carries Gravitation and Compression');
check(#plan.gives[2].skills == 3 and plan.gives[2].props[1] == 'Compression' and #plan.gives[2].props == 1,
      'the other three carry Compression only');
local grav = build(plan, 'Gravitation');
check(grav.rows[1].kind == 'ws' and grav.rows[1].ready and grav.rows[1].cost == 0, 'Crescent Moon + Dark is ready');
check(grav.rows[2].kind == 'any' and grav.rows[2].cost == 1 and not grav.rows[2].ready and grav.rows[2].affordable,
      'any + Earth + Dark costs one more point, and one point is enough');
fusion = build(plan, 'Fusion');
check(fusion.rows[2].kind == 'any' and fusion.rows[2].cost == 2 and not fusion.rows[2].affordable,
      'two points are dimmed with one');

plan = rules.plan({ weaponskills = WS, held = {}, level = 49, points = 5 });
for _, b in ipairs(plan.builds) do
    for _, row in ipairs(b.rows) do
        check(row.kind ~= 'any', 'below 50 there is no two-element row (' .. b.prop .. ')');
    end
end

plan = rules.plan({ weaponskills = WS, held = {}, level = 75 });
check(build(plan, 'Fusion').rows[2].affordable, 'with the points unknown nothing is dimmed');

-- ---------------------------------------------------------------------------
-- the module
-- ---------------------------------------------------------------------------
local jh = require('dlac\\feature\\jobhelpers');
local helper = require('dlac\\jobhelpers\\pld\\divine-elements\\init');
local rec = jh._validate('divine-elements', helper);
check(rec ~= nil and rec.servers ~= nil and rec.servers[1] == 'ascensionxi', 'a valid module, built for AscensionXI');
check(jh.forServer(rec.servers, 'ascensionxi') and not jh.forServer(rec.servers, 'cexi'), 'it loads on AscensionXI only');
check(type(helper.window) == 'function' and helper.commands == nil and helper.open == nil, 'a window and no actions: it never acts');
local features = dofile('servers/ascensionxi/features.lua');
check(features.jobhelpers['divine-elements'] == true, "the AscensionXI pack lists it");

local client = helper._client;
local state = { job = 7, buffs = { [655] = true }, listed = true };
client.read = function() return state; end;
client.weaponskills = function() return WS; end;
local gaugeView = { synced = true, points = 2 };
local cfgVals = {};
local S = {
    cfg = {
        get = function(k) if cfgVals[k] ~= nil then return cfgVals[k]; end return helper.config.defaults[k]; end,
        set = function(k, v) cfgVals[k] = v; return true; end,
    },
    server = { service = function(name) if name == 'pldGauge' then return { view = function() return gaugeView; end }; end end },
    player = { level = function() return 75; end },
};

local v, why = helper._view(S, 10);
check(v ~= nil and v.points == 2, 'in Divine Fury with the elements listed there is a plan, with the gauge points');
state.buffs = {};
helper._resetCache();
v, why = helper._view(S, 20);
check(v == nil and why == 'stance', 'no window outside Divine Fury');
state.buffs = { [655] = true };
state.listed = false;
v, why = helper._view(S, 30);
check(v == nil and why == 'level', 'none before level 15 lists the divine elements');
state.listed = true;
state.job = 1;
v, why = helper._view(S, 40);
check(v == nil and why == 'job', 'none on another job');
state.job = 7;
gaugeView = nil;
v = helper._view(S, 50);
check(v ~= nil and v.points == nil, 'with the gauge hidden the points are unknown, and the plan still shows');
gaugeView = { synced = true, points = 2 };

-- What the window draws.
local drawn = {};
local ui = {
    COL = { head = 'head', dim = 'dim', ok = 'ok', warn = 'warn', err = 'err', lit = 'lit' },
    text = function(col, s) drawn[#drawn + 1] = { col = col, s = s }; end,
    dim = function(s) drawn[#drawn + 1] = { col = 'dim', s = s }; end,
    err = function(s) drawn[#drawn + 1] = { col = 'err', s = s }; end,
    sameLine = function() end, space = function() end,
    section = function(_, _, body) body(); end,
    toggle = function() return nil; end,
};
local function shown(s, col)
    for _, d in ipairs(drawn) do
        if d.s == s and (col == nil or d.col == col) then return true; end
    end
    return false;
end
state.buffs = { [655] = true, [667] = true };
helper._resetCache();
helper._draw(ui, helper._view(S, 60));
check(shown('Divine Elements', 'head') and shown('2 points'), 'the title and the points');
check(shown('Holding Dark', 'ok'), 'what is held');
check(shown('  Crescent Moon:') and shown('Gravitation') and shown('Compression'), 'and what it gives Crescent Moon');
check(shown('  Crescent Moon + Dark', 'ok') and shown('ready'), 'a build already held reads ready, in green');
check(shown('  Any WS + Earth + Dark') and shown('1 point'), 'the two-element build costs one more point');
check(shown('  Spinning Slash') and shown('has it'), 'a weapon skill that has it of its own says so');

-- The window itself: shown in Divine Fury, gone when switched off.
local begins = 0;
local imguiStub = {
    SetNextWindowPos = function() end,
    Begin = function() begins = begins + 1; return true; end,
    End = function() end,
    GetWindowPos = function() return 60, 420; end,
};
package.loaded['dlac\\feature\\gamehud'] = { hidden = function() return false; end };
helper.window({ ui = ui, S = S, imgui = imguiStub });
check(begins == 1, 'the window opens in Divine Fury');
cfgVals.window = false;
helper.window({ ui = ui, S = S, imgui = imguiStub });
check(begins == 1, 'and not when switched off');
cfgVals.window = true;
state.buffs = {};
helper.window({ ui = ui, S = S, imgui = imguiStub });
check(begins == 1, 'and not outside Divine Fury');

print(string.format('ascensionxi_divine_elements: %d checks passed', checks));
