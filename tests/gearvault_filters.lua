-- Run from the addon root: lua tests/gearvault_filters.lua
-- The Gear Vault tab's filters (ticket AXI-103): the rules in vaultfilters.lua
-- over invented records, the usage file remembering them, and the rules over
-- the REAL pack (catalog + data\hqpairs.lua) so the fixtures are not circular.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel == nil then return nil; end
    return loadfile((rel:gsub('\\', '/')) .. '.lua');
end);
local vf = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\vaultfilters');
local usage = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\usage');

local n = 0;
local function ok(cond, what)
    n = n + 1;
    assert(cond, what);
end

-- ---- cleaning: anything stored becomes a usable filter set ----------------
local d = vf.defaults(75);
ok(vf.activeCount(d, 75) == 0, 'the defaults filter nothing');
local c = vf.clean({ job = 1, hq = true, hobby = 'nonsense', lvMin = 90, lvMax = -4 }, 75);
ok(c.job == false and c.hq == true and c.hobby == 'show', 'only real values survive cleaning');
ok(c.lvMin == 1 and c.lvMax == 75, 'the level ends are clamped and put in order');
ok(vf.clean(nil, 50).lvMax == 50, 'no stored filters = the defaults at this server\'s cap');
ok(vf.activeCount({ job = true, hq = true, hobby = 'only', lvMin = 10, lvMax = 75 }, 75) == 4, 'four filters on');
ok(vf.activeCount({ job = false, hq = false, hobby = 'show', lvMin = 1, lvMax = 74 }, 75) == 1, 'a lowered top level counts');

-- ---- fixtures -------------------------------------------------------------
local R = {
    [1]  = { Slot = 'Body', Level = 59, Jobs = { 'WAR', 'PLD' }, Stats = { DEF = 40 } },   -- NQ body
    [2]  = { Slot = 'Body', Level = 59, Jobs = { 'WAR', 'PLD' }, Stats = { DEF = 46 } },   -- its HQ
    [3]  = { Slot = 'Ring', Level = 40, Jobs = { 'All' }, Stats = { STR = 2 } },           -- NQ ring
    [4]  = { Slot = 'Ring', Level = 40, Jobs = { 'All' }, Stats = { STR = 3 } },           -- its HQ
    [5]  = { Slot = 'Main', Category = 'Sword', OneHanded = true, Level = 30, Jobs = { 'WAR' }, Stats = {} },
    [6]  = { Slot = 'Main', Category = 'Sword', OneHanded = true, Level = 30, Jobs = { 'WAR' }, Stats = {} },
    [7]  = { Slot = 'Main', Category = 'Great Axe', OneHanded = false, Level = 30, Jobs = { 'WAR' }, Stats = {} },
    [8]  = { Slot = 'Main', Category = 'Great Axe', OneHanded = false, Level = 30, Jobs = { 'WAR' }, Stats = {} },
    [9]  = { Slot = 'Legs', Level = 1, Jobs = { 'All' }, Stats = { DEF = 1 } },            -- NQ, HQ asks Lv15
    [10] = { Slot = 'Legs', Level = 15, Jobs = { 'All' }, Stats = { DEF = 2 } },
    [11] = { Slot = 'Hands', Level = 50, Jobs = { 'WAR', 'THF' }, Stats = {} },            -- NQ, HQ drops THF
    [12] = { Slot = 'Hands', Level = 50, Jobs = { 'WAR' }, Stats = {} },
    [13] = { Slot = 'Ring', Level = 1, Jobs = { 'All' }, Stats = { SynthHQRate = 1 } },    -- a crafting ring
    [14] = { Slot = 'Body', Level = 1, Jobs = { 'All' }, Stats = { MiningExtraRoll = 40, DEF = 2 } },
    [15] = { Slot = 'Head', Level = 70, Jobs = { 'BLM' }, Stats = { INT = 5 } },
};
local better = { [1] = { 2 }, [3] = { 4 }, [5] = { 6 }, [7] = { 8 }, [9] = { 10 }, [11] = { 12 } };
local function row(id, extra)
    local e = { itemId = id, rec = R[id], name = 'item ' .. id };
    for k, v in pairs(extra or {}) do e[k] = v; end
    return e;
end
local function ctx(held, job)
    return { job = job or 'WAR', held = held or {}, better = better,
             recOf = function(id) return R[id]; end,
             augmented = function(e) return e.aug == true; end };
end
local function on(over)
    local f = vf.defaults(75);
    for k, v in pairs(over) do f[k] = v; end
    return f;
end

-- ---- job ------------------------------------------------------------------
ok(vf.shows(row(1), on({ job = true }), ctx()), 'a WAR piece shows for WAR');
ok(not vf.shows(row(15), on({ job = true }), ctx()), 'a BLM-only piece is hidden for WAR');
ok(vf.shows(row(3), on({ job = true }), ctx()), 'an All Jobs piece shows for every job');
ok(vf.shows(row(15), on({ job = true }), ctx({}, 'BLM')), 'and the same piece shows for BLM');
ok(vf.shows(row(15), on({ job = true }), { held = {}, recOf = function() end }), 'an unknown job hides nothing');
ok(vf.wearableBy({ Jobs = { WAR = 1 } }, 'WAR') and not vf.wearableBy({ Jobs = { WAR = 1 } }, 'BLM'),
    'a keyed job table reads the same as a list');

-- ---- level ----------------------------------------------------------------
ok(vf.shows(row(1), on({ lvMin = 59, lvMax = 59 }), ctx()), 'the ends of the range are inside it');
ok(not vf.shows(row(1), on({ lvMax = 58 }), ctx()), 'above the top level is hidden');
ok(not vf.shows(row(13), on({ lvMin = 2 }), ctx()), 'below the bottom level is hidden');

-- ---- crafting and gathering gear ------------------------------------------
ok(vf.isHobby(R[13]) and vf.isHobby(R[14]) and not vf.isHobby(R[1]), 'a hobby stat makes hobby gear');
for _, key in ipairs({ 'WoodworkingSkill', 'CookingSkill', 'FishingSkill', 'SynthSuccessRate', 'SynthSuccessAlchemy',
    'SynthNQOnly', 'AntiHQSmithing', 'HELM', 'HelmBreakReduction', 'LoggingExtraRoll', 'DigRareAbility', 'Surveyor' }) do
    ok(vf.isHobbyStat(key), key .. ' is a crafting or gathering stat');
end
for _, key in ipairs({ 'PhantomRoll', 'AlliesRollBonus', 'ConserveMP', 'DEF', 'HealingMagicSkill', 'Recycle' }) do
    ok(not vf.isHobbyStat(key), key .. ' is combat, not a hobby stat');
end
ok(not vf.shows(row(13), on({ hobby = 'hide' }), ctx()), 'Hide takes the crafting ring away');
ok(vf.shows(row(1), on({ hobby = 'hide' }), ctx()), 'Hide leaves combat gear');
ok(vf.shows(row(14), on({ hobby = 'only' }), ctx()) and not vf.shows(row(1), on({ hobby = 'only' }), ctx()),
    'Only keeps the gathering body and drops the rest');

-- ---- high quality ---------------------------------------------------------
local hq = on({ hq = true });
ok(vf.shows(row(1), hq, ctx({})), 'an NQ with no HQ in the vault shows');
ok(not vf.shows(row(1), hq, ctx({ [2] = 1 })), 'one HQ body hides the NQ body');
ok(vf.shows(row(2), hq, ctx({ [1] = 3, [2] = 1 })), 'the HQ itself always shows');
ok(vf.shows(row(3), hq, ctx({ [4] = 1 })), 'ONE HQ ring leaves the NQ ring: the pair can be worn together');
ok(not vf.shows(row(3), hq, ctx({ [4] = 2 })), 'TWO HQ rings hide the NQ ring');
ok(vf.shows(row(5), hq, ctx({ [6] = 1 })) and not vf.shows(row(5), hq, ctx({ [6] = 2 })),
    'a one-handed weapon follows the two-copy rule');
ok(not vf.shows(row(7), hq, ctx({ [8] = 1 })), 'a two-handed weapon needs one HQ');
ok(vf.shows(row(9), hq, ctx({ [10] = 1 })), 'an HQ that asks for a higher level hides nothing');
ok(vf.shows(row(11), hq, ctx({ [12] = 1 })), 'an HQ that fewer jobs can wear hides nothing');
ok(vf.shows(row(1, { aug = true }), hq, ctx({ [2] = 1 })), 'an augmented NQ is never hidden');
ok(vf.shows(row(1), hq, { held = { [2] = 1 }, recOf = function(id) return R[id]; end }), 'no HQ table = nothing hidden');
ok(vf.shows({ itemId = 999, name = '#999' }, on({ job = true, hq = true, hobby = 'only', lvMin = 70 }), ctx()),
    'a row with no record always shows');

-- ---- a whole view: search and filters together, with the hidden count -----
local view = { grouped = {
    Body = { row(1), row(2), row(14) },
    Ring = { row(3), row(13) },
    Main = { _cats = { Sword = { row(5) }, ['Great Axe'] = { row(7), row(8) } } },
}, total = 8 };
local out = vf.apply(view, '', on({ hq = true, hobby = 'hide' }), ctx({ [2] = 1, [8] = 1 }));
ok(out.total == 4 and out.hidden == 4, 'four rows left, four held back');
ok(#out.grouped.Body == 1 and out.grouped.Body[1].itemId == 2, 'the HQ body is what is left of Body');
ok(#out.grouped.Ring == 1 and out.grouped.Ring[1].itemId == 3, 'the stat ring stays, the crafting ring goes');
ok(#out.grouped.Main._cats['Great Axe'] == 1 and #out.grouped.Main._cats.Sword == 1, 'weapon categories keep their shape');
ok(#view.grouped.Body == 3, 'the source view is not touched');
out = vf.apply(view, 'item 1', on({ hobby = 'hide' }), ctx());
ok(out.total == 1 and out.hidden == 2, 'hidden counts only rows the SEARCH would have shown (13 and 14)');
out = vf.apply(view, 'item 1', nil, ctx());
ok(out.total == 3 and out.hidden == 0, 'no filters = the plain name search');

-- ---- the usage file remembers them ----------------------------------------
usage._reset();
ok(usage.filters() == nil, 'nothing set = nothing stored');
ok(not usage.setFilters({ job = true }), 'a half-shaped table is refused');
ok(usage.setFilters({ job = true, hq = false, hobby = 'hide', lvMin = 10, lvMax = 60 }), 'a whole one is taken');
ok(usage._st().dirty == true, 'and marks the file for saving');
local saved = assert((loadstring or load)(usage._serialize()))();
usage._reset();
usage._apply(saved);
local back = vf.clean(usage.filters(), 75);
ok(back.job == true and back.hq == false and back.hobby == 'hide' and back.lvMin == 10 and back.lvMax == 60,
    'the filters come back as they were saved');
usage._reset();
usage._apply({ settings = { additions = 'off', removals = 'ask' } });
ok(usage.filters() == nil and usage.settings().additions == 'off', 'an older file without filters still loads');
usage._reset();

-- ---- the real pack --------------------------------------------------------
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local ci = require('dlac\\gear\\catalogindex');
local pairsHQ = dofile('servers/ascensionxi/data/hqpairs.lua');
local manifest = dofile('servers/ascensionxi/manifest.lua');
local count = 0;
for id, list in pairs(pairsHQ) do
    count = count + 1;
    assert(type(id) == 'number' and type(list) == 'table' and #list >= 1, 'hqpairs shape');
    for _, hi in ipairs(list) do assert(hi ~= id, 'a piece is never its own HQ'); end
end
ok(count == manifest.counts.hqpairs, 'the manifest counts the pairs the file holds');
local listed = false;
for _, f in ipairs(manifest.files) do if f == 'hqpairs' then listed = true; end end
ok(listed, 'the manifest lists hqpairs, or data\\hqpairs never resolves');
ok(pairsHQ[12555][1] == 13735, 'Haubergeon -> Haubergeon +1');
local function real(id) return assert(ci.rawById(id), 'missing item ' .. id); end
ok(real(12555).Name == 'Haubergeon' and real(13735).Name == 'Haubergeon +1', 'the ids are the pieces named');
local rctx = { job = 'WAR', held = { [13735] = 1 }, better = pairsHQ, recOf = ci.rawById };
local haub = { itemId = 12555, rec = { Slot = 'Body', Level = real(12555).Level, Jobs = real(12555).Jobs }, name = 'Haubergeon' };
ok(not vf.shows(haub, hq, rctx), 'owning Haubergeon +1 hides Haubergeon');
rctx.held = {};
ok(vf.shows(haub, hq, rctx), 'and without it Haubergeon shows');
ok(vf.isHobby(real(28586)), 'Craftmaster\'s Ring is crafting gear');
ok(vf.isHobby(real(26580)), 'Craftsman\'s Restraint is crafting gear');
ok(not vf.isHobby(real(13735)), 'Haubergeon +1 is not');
ok(not vf.wearableBy(real(13735), 'BLM') and vf.wearableBy(real(13735), 'WAR'), 'the real job list reads');

print(string.format('OK -- Gear Vault filters: %d checks', n));
