-- Headless tests for the profile-side rebuild engine (utils.lua).
-- Run from the dlac addon root:   lua tests\run_tests.lua
-- No Ashita required: gData / AshitaCore / ashita are stubbed below.

-- ---------------------------------------------------------------------------
-- environment stubs (must exist BEFORE utils.lua loads)
-- ---------------------------------------------------------------------------
package.loaded['dlac\\gear'] = { NameToObject = {} };   -- utils requires dlac\gear at load
ashita = { events = { register = function() end } };    -- utils registers /dl at load

local TEST_PLAYER = nil;                                -- set per test
gData = { GetPlayer = function() return TEST_PLAYER; end };

-- AshitaCore stub: controls the Dual Wield trait bit (HasAbility(1554)) and records
-- the id actually asked for, so a wrong trait id fails the test.
local lastAbilityId = nil;
local function ashitaWithDW(hasDW)
    local p = {
        GetMainJob = function(self) return 7; end,      -- any valid 1..22 job id
        HasAbility = function(self, id) lastAbilityId = id; return hasDW; end,
    };
    return { GetMemoryManager = function(self) return { GetPlayer = function(self) return p; end }; end };
end

AshitaCore = nil;
-- The REAL dispatch engine, loaded headlessly BEFORE utils so utils captures it as
-- M.dispatchModule: BuildDynamicSets consults dispatch.modeActive for mode-gated
-- set entries (section G drives dispatch.M.modes directly).
local dispatchM = dofile('dispatch.lua');
package.loaded['dlac\\dispatch'] = dispatchM;
local utils = dofile('utils.lua');

-- ---------------------------------------------------------------------------
-- tiny runner
-- ---------------------------------------------------------------------------
local failures, count = {}, 0;
local function check(name, got, want)
    count = count + 1;
    if got ~= want then
        failures[#failures + 1] = string.format('%s: got %s, want %s', name, tostring(got), tostring(want));
    end
end

-- ---------------------------------------------------------------------------
-- fixtures
-- ---------------------------------------------------------------------------
local sword1H  = { Name = 'Joyeuse',       Level = 72, OneHanded = true,  Type = 'Sword'  };
local dagger1H = { Name = 'Kris',          Level = 71, OneHanded = true,  Type = 'Dagger' };
local shield   = { Name = 'GenbusShield',  Level = 70, OneHanded = false, Type = 'Shield' };
local grip     = { Name = 'PoleGrip',      Level = 71, OneHanded = false, Type = 'Grip'   };
local gsword2H = { Name = 'Ragnarok',      Level = 73, OneHanded = false, Type = 'Great Sword' };
local twinKris = { Name = 'Kris',          Level = 71, OneHanded = true,  Type = 'Dagger', InBothHands = true };

-- catalog-vocabulary records (imported gear: shields AND grips say Type="Sub";
-- weapons carry a skill name + OneHanded)
local catShield = { Name = 'Jennet Shield', Level = 38, Type = 'Sub' };
local catGrip   = { Name = 'Ariesian Grip', Level = 60, Type = 'Sub' };
local catAxe1H  = { Name = 'Kriegsbeil',    Level = 70, Type = 'Axe', OneHanded = true };

-- ---------------------------------------------------------------------------
-- A. subSlotAllowed -- the shared Sub-slot pairing rule
--
--    HARD RULE (Henrik, 2026-07-12; reverted THREE times before this -- if one
--    of these checks is in your way, you are about to revert it a fourth time.
--    STOP and read docs/adr/0006-builder-plans-engine-decides.md, addendum):
--    building=true (composing a set) offers EVERY Sub-capable item -- shield,
--    grip, one-hander -- regardless of Main pick, DW trait, or any live state.
--    Only physical impossibility excludes: 2H in Sub; same-name without a
--    provable second copy. Equip-time (building absent): DW/pairing decides.
-- ---------------------------------------------------------------------------
check('A0 subSlotAllowed exported', type(utils.subSlotAllowed), 'function');
if type(utils.subSlotAllowed) == 'function' then
    local f = utils.subSlotAllowed;
    -- HARD RULE regression guards -- building never adapts to Main/DW:
    check('A1 HARD RULE build: 1H+1H, no DW -> offered',      f(sword1H, dagger1H, { building = true             }), true);
    check('A5 HARD RULE build: 1H even with 2H main planned', f(sword1H, gsword2H, { dw = true, building = true  }), true);
    check('A7 HARD RULE build: grip even with 1H main',       f(grip,    dagger1H, { dw = true, building = true  }), true);
    check('A11 HARD RULE build: no Main planned -> still offered', f(sword1H, nil,  { dw = true, building = true  }), true);
    check('A14 HARD RULE build: catalog grip, 1H main',       f(catGrip, catAxe1H, { dw = true, building = true  }), true);
    check('A16 HARD RULE build: catalog 1H weapon',           f(catAxe1H, dagger1H, { building = true            }), true);
    -- building-time exclusions are PHYSICAL only:
    check('A12 build: 2H sub weapon never',  f(gsword2H, dagger1H, { dw = true, building = true }), false);
    check('A8 same name: InBothHands',       f(twinKris, twinKris, { building = true            }), true);
    check('A9 same name: two copies',        f(dagger1H, dagger1H, { building = true, copies = 2 }), true);
    check('A10 same name: single copy',      f(dagger1H, dagger1H, { building = true, copies = 1 }), false);
    -- equip-time (building absent) stays strictly gated -- the ENGINE's call:
    check('A2 equip: 1H+1H, no DW',          f(sword1H, dagger1H, {           }), false);
    check('A3 equip: 1H+1H, DW',             f(sword1H, dagger1H, { dw = true }), true);
    check('A4 equip: 2H main, grip ok',      f(grip,    gsword2H, { dw = true }), true);
    check('A5b equip: 2H main, 1H never',    f(sword1H, gsword2H, { dw = true }), false);
    check('A6 equip: 1H main, shield always', f(shield, dagger1H, {           }), true);
    check('A7b equip: 1H main, grip never',  f(grip,    dagger1H, { dw = true }), false);
    check('A11b equip: no main -> no sub',   f(sword1H, nil,      { dw = true }), false);
    check('A13 equip: catalog shield, 1H main', f(catShield, catAxe1H, {      }), true);
    check('A14b equip: catalog grip, 1H main',  f(catGrip, catAxe1H, { dw = true }), false);
    check('A15 equip: catalog grip, 2H main',   f(catGrip, gsword2H, {        }), true);
    check('A17 classifySub exported',        type(utils.classifySub), 'function');
end

-- ---------------------------------------------------------------------------
-- B. isDualWieldAvailable -- the memory trait bit (1554) is authoritative
-- ---------------------------------------------------------------------------
AshitaCore = ashitaWithDW(true);
check('B1 memory bit true -> true',  utils.isDualWieldAvailable('WAR', 75, 'WHM', 37), true);
check('B2 asks for trait id 1554',   lastAbilityId, 1554);
AshitaCore = ashitaWithDW(false);
-- CatsEyeXI truth: memory answer must WIN over the legacy THF>=20 table
check('B3 memory bit false beats legacy THF row', utils.isDualWieldAvailable('THF', 75, 'WHM', 37), false);
AshitaCore = nil;   -- memory unavailable -> legacy fallback
check('B4 fallback: /NIN37 -> true', utils.isDualWieldAvailable('WAR', 75, 'NIN', 37), true);
check('B5 fallback: /WHM37 -> false', utils.isDualWieldAvailable('WAR', 75, 'WHM', 37), false);

-- ---------------------------------------------------------------------------
-- C. BuildDynamicSets -- equip-time: DW decides, the list's shield is the fallback.
--    Also locks the Main-before-Sub resolution order (pairs() order must not matter).
-- ---------------------------------------------------------------------------
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };

local function freshSets()
    return { Dynamic = { TP = {
        Sub  = { shield, sword1H },   -- Sub listed BEFORE Main on purpose (order lock)
        Main = { dagger1H },
    } } };
end

AshitaCore = ashitaWithDW(true);
local sDW = utils.BuildDynamicSets(freshSets());
check('C1 DW on: main resolves',   sDW.TP and sDW.TP.Main, 'Kris');
check('C2 DW on: weapon offhand',  sDW.TP and sDW.TP.Sub,  'Joyeuse');

AshitaCore = ashitaWithDW(false);
local sNo = utils.BuildDynamicSets(freshSets());
check('C3 no DW: shield fallback', sNo.TP and sNo.TP.Sub,  'GenbusShield');

-- catalog-vocabulary records resolve the same way (Type="Sub" shield fallback)
local function catSets()
    return { Dynamic = { WS = { Main = { catAxe1H }, Sub = { catShield, sword1H } } } };
end
AshitaCore = ashitaWithDW(false);
local sCat = utils.BuildDynamicSets(catSets());
check('C4 no DW: catalog shield fallback', sCat.WS and sCat.WS.Sub, 'Jennet Shield');
AshitaCore = ashitaWithDW(true);
sCat = utils.BuildDynamicSets(catSets());
check('C5 DW on: weapon beats catalog shield', sCat.WS and sCat.WS.Sub, 'Joyeuse');

-- ---------------------------------------------------------------------------
-- D. gearimport parser -- prune/fix/dedupe must see entries whose header line
--    carries a trailing "-- comment" (hand-annotated legacy entries). Field-
--    verified: 25 such entries in a real gear.lua were invisible to /dl prune.
-- ---------------------------------------------------------------------------
local gearimport = dofile('gearimport.lua');
local fixtureGear = table.concat({
    'gear = {',
    '    Main = {',
    '        Sword = { -- category comment',
    '            CleanSword = {',
    '                Name = "Clean Sword",',
    '            },',
    '            NotedSword = { -- legacy note',
    '                Name = "Noted Sword",',
    '            },',
    '        },',
    '    },',
    '    Body = {',
    '        CleanBody = {',
    '            Name = "Clean Body",',
    '            Jobs = {"WAR", "THF"},',
    '        },',
    '        NotedBody = { -- Mtl. style/annotated',
    '            Name = "Noted Body",',
    '        }, -- trailing close comment',
    '    },',
    '};',
}, '\n');
-- empty owned list -> every entry the parser SEES must be reported for removal
local _, dRep, dTotal = gearimport.computePrune(fixtureGear, {});
check('D1 all 4 entries visible to prune', dTotal, 4);
local dSeen = {};
for _, r in ipairs(dRep) do dSeen[tostring(r.parent) .. '.' .. tostring(r.key)] = true; end
check('D2 comment-header weapon entry seen', dSeen['Main.Sword.NotedSword'], true);
check('D3 comment-header flat entry seen',   dSeen['Body.NotedBody'], true);
check('D4 owned name still kept', select(3, gearimport.computePrune(fixtureGear,
    { { Name = 'Noted Body' }, { Name = 'Clean Sword' }, { Name = 'Noted Sword' }, { Name = 'Clean Body' } })), 0);

-- ---------------------------------------------------------------------------
-- E. computeFixes metadata backfill -- the equip-time engine reads RAW gear.lua,
--    so /dl fix stamps Type / OneHanded from the catalog (weapons) and the
--    Shield/Grip label (Sub items). Must be idempotent.
-- ---------------------------------------------------------------------------
local eGear = table.concat({
    'gear = {',
    '    Main = {',
    '        Axe = {',
    '            Kriegsbeil = {',
    '                Name = "Kriegsbeil",',
    '                Level = 70,',
    '                Id = 17939,',
    '            },',
    '        },',
    '    },',
    '    Sub = {',
    '        JennetShield = {',
    '            Name = "Jennet Shield",',
    '            Level = 38,',
    '            Id = 12405,',
    '        },',
    '        AriesianGrip = {',
    '            Name = "Ariesian Grip",',
    '            Level = 60,',
    '            Id = 19042,',
    '        },',
    '    },',
    '};',
}, '\n');
local eMeta = {
    [17939] = { Type = 'Axe', OneHanded = true },
    [12405] = { Type = 'Sub' },
    [19042] = { Type = 'Sub' },
};
local eText, eRep = gearimport.computeFixes(eGear, {}, eMeta);
check('E1 weapon Type stamped',      eText:find('Type = "Axe"',     1, true) ~= nil, true);
check('E2 weapon OneHanded stamped', eText:find('OneHanded = true', 1, true) ~= nil, true);
check('E3 shield labeled Shield',    eText:find('Type = "Shield"',  1, true) ~= nil, true);
check('E4 grip labeled by name',     eText:find('Type = "Grip"',    1, true) ~= nil, true);
check('E5 result still parses',      (loadstring or load)(eText) ~= nil, true);
local _, eRep2 = gearimport.computeFixes(eText, {}, eMeta);
check('E6 idempotent second pass',   #eRep2.fixed, 0);

-- ---------------------------------------------------------------------------
-- F. setmanager shim analysis -- COMMENTED-OUT handlers ("-- profile.HandleX =
--    function()") are dead code: they must read as 'missing' (Setup creates
--    them), not 'unparsable' (Setup gave up with "no changes needed" while the
--    banner stayed red). Field case: Mindie's BLU.lua / COR.lua.
-- ---------------------------------------------------------------------------
local setmgr = dofile('setmanager.lua');
local fProfile = table.concat({
    'local profile = {};',
    'local utils = require("dlac\\\\utils");',
    '',
    '-- profile.HandleAbility = function()',
    '--     local ability = gData.GetAction();',
    '--     if ability.Name == \'Release\' then return end',
    '-- end',
    '',
    'profile.HandleDefault = function()',
    '    sets = utils.rebuildSets(sets);',
    '    utils.dispatch(\'Default\');',
    'end',
    '',
    'profile.HandleItem        = function() utils.dispatch(\'Item\');        end',
    'profile.HandlePrecast     = function() utils.dispatch(\'Precast\');     end',
    'profile.HandleMidcast     = function() utils.dispatch(\'Midcast\');     end',
    'profile.HandlePreshot     = function() utils.dispatch(\'Preshot\');     end',
    'profile.HandleMidshot     = function() utils.dispatch(\'Midshot\');     end',
    'profile.HandleWeaponskill = function() utils.dispatch(\'Weaponskill\'); end',
    '',
    'return profile;',
}, '\n');
local fA = setmgr.analyzeShims(fProfile);
check('F1 commented handler is missing, not unparsable', fA.handlers.Ability, 'missing');
check('F2 live handlers still ok', fA.handlers.Item, 'ok');
local fText, fRep = setmgr.repairShimsText(fProfile);
check('F3 repair creates the commented-out handler', fRep.created[1], 'Ability');
check('F4 repair emits no warnings', #fRep.warnings, 0);
check('F5 repaired text parses', (loadstring or load)(fText) ~= nil, true);
check('F6 repaired profile is healthy', setmgr.analyzeShims(fText).healthy, true);

-- ---------------------------------------------------------------------------
-- G. mode-gated set entries -- an entry with `mode = '...'` participates only
--    while that mode is active, and then OUTRANKS unconditional entries; the
--    wrapper merge must never mutate the shared gear record.
-- ---------------------------------------------------------------------------
check('G1 modeActive cycle hit',    dispatchM.modeActive('Weapon:Melee', { weapon = 'Melee' }), true);
check('G2 modeActive cycle miss',   dispatchM.modeActive('Weapon:Melee', { weapon = 'Ranged' }), false);
check('G3 modeActive toggle on',    dispatchM.modeActive('DT', { dt = true }), true);
check('G4 modeActive toggle off',   dispatchM.modeActive('DT', {}), false);
check('G5 modeActive bare cycle',   dispatchM.modeActive('Weapon', { weapon = 'Ranged' }), true);

TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
AshitaCore = ashitaWithDW(false);

local plainBody = { Name = 'PlainBody', Level = 50, Type = 'Body' };
local modeBody  = { Name = 'ModeBody',  Level = 40, Type = 'Body' };   -- lower level on purpose
local lateBody  = { Name = 'LateBody',  Level = 10, Type = 'Body' };
local function gatedSets()
    return { Dynamic = { TP = {
        Body = { plainBody, { gear = modeBody, mode = 'Weapon:Melee' } },
    } } };
end

dispatchM.modes = {};
local gOff = utils.BuildDynamicSets(gatedSets());
check('G6 mode off: unconditional wins', gOff.TP and gOff.TP.Body, 'PlainBody');

dispatchM.modes = { weapon = 'Melee' };
local gOn = utils.BuildDynamicSets(gatedSets());
check('G7 mode on: gated entry beats higher-level unconditional', gOn.TP and gOn.TP.Body, 'ModeBody');

dispatchM.modes = { weapon = 'Ranged' };
local gOther = utils.BuildDynamicSets(gatedSets());
check('G8 other cycle value: gated entry excluded', gOther.TP and gOther.TP.Body, 'PlainBody');

dispatchM.modes = { dt = true };
local gTog = utils.BuildDynamicSets({ Dynamic = { TP = {
    Body = { plainBody, { gear = modeBody, mode = 'DT' } },
} } });
check('G9 toggle mode gates too', gTog.TP and gTog.TP.Body, 'ModeBody');
dispatchM.modes = {};

check('G10 wrapper merge does not mutate the shared record', modeBody.mode, nil);

-- mode LISTS are OR: active while ANY entry matches
check('G13 list: second entry matches', dispatchM.modeActive({ 'Weapon:Melee', 'DT' }, { dt = true }), true);
check('G14 list: cycle value matches',  dispatchM.modeActive({ 'Weapon:Melee', 'Weapon:Ranged' }, { weapon = 'Ranged' }), true);
check('G15 list: none match',           dispatchM.modeActive({ 'Weapon:Melee', 'DT' }, {}), false);

dispatchM.modes = { weapon = 'Ranged' };
local gList = utils.BuildDynamicSets({ Dynamic = { TP = {
    Body = { plainBody, { gear = modeBody, mode = { 'Weapon:Melee', 'Weapon:Ranged' } } },
} } });
check('G16 engine honours mode lists', gList.TP and gList.TP.Body, 'ModeBody');
dispatchM.modes = {};
check('G17 list wrapper does not mutate the shared record', modeBody.mode, nil);

-- rebuildSets must re-flatten on a MODE change (not only level/sub-job) --
-- the field bug: rotating a cycle left the flattened sets stale forever.
TEST_PLAYER = { MainJob = 'RDM', SubJob = 'WHM', MainJobSync = 75, SubJobSync = 37 };
dispatchM.modes = {};
local sets20 = { Dynamic = { TP = {
    Body = { plainBody, { gear = modeBody, mode = 'DT' } },
} } };
sets20 = utils.rebuildSets(sets20);
check('G20 initial flatten picks unconditional', sets20.TP and sets20.TP.Body, 'PlainBody');
dispatchM.setMode('DT', true);              -- bumps modesRev via saveModeState
sets20 = utils.rebuildSets(sets20);         -- same level/SJ: old code skipped this
check('G21 mode flip re-flattens via modesRev', sets20.TP and sets20.TP.Body, 'ModeBody');
dispatchM.setMode('DT', false);
sets20 = utils.rebuildSets(sets20);
check('G22 flip back re-flattens again', sets20.TP and sets20.TP.Body, 'PlainBody');

-- serializer writes both gate forms
local serLines = table.concat(setmgr.renderSetLines('T', {
    { name = 'Body', items = {
        { path = 'gear.Body.A', mode = 'DT' },
        { path = 'gear.Body.B', mode = { 'Weapon:Melee', 'Weapon:Ranged' } },
    } },
}), '\n');
check('G18 serializes single gate',  serLines:find('mode = "DT"', 1, true) ~= nil, true);
check('G19 serializes gate list',    serLines:find('mode = { "Weapon:Melee", "Weapon:Ranged" }', 1, true) ~= nil, true);

-- min/maxLevel bounds through the same wrapper (the ffxi-lac semantics)
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 50, SubJobSync = 25 };
local gMin = utils.BuildDynamicSets({ Dynamic = { TP = {
    Body = { { gear = lateBody, minLevel = 60 }, { gear = plainBody, maxLevel = 55 } },
} } });
check('G11 minLevel bound excludes below', gMin.TP and gMin.TP.Body, 'PlainBody');
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 60, SubJobSync = 30 };
local gMax = utils.BuildDynamicSets({ Dynamic = { TP = {
    Body = { { gear = lateBody, minLevel = 60 }, { gear = plainBody, maxLevel = 55 } },
} } });
check('G12 past maxLevel: banded item takes over', gMax.TP and gMax.TP.Body, 'LateBody');

-- ---------------------------------------------------------------------------
-- H. set-level optimization under caps (gearoptim.optimizePicks) -- greedy
--    per-slot picking overspends capped stats; the optimizer must give cap
--    budget to the piece that brings the most ALONGSIDE it, prefer EMPTY on
--    ties, and respect paired-slot conflicts.
-- ---------------------------------------------------------------------------
local optim = dofile('gearoptim.lua');
local W = {
    Haste      = { perUnit = 100, cap = 5 },
    SwordSkill = { perUnit = 2 },
    Accuracy   = { perUnit = 3 },
};
-- Henrik's field case: a haste-only head wins per-item, but the feet already
-- cap haste AND bring skill/acc -- the head must yield to the accuracy hat.
local hasteHat  = { stats = { Haste = 5 },                                ref = 'HasteHat'  };
local statHat   = { stats = { Accuracy = 5 },                             ref = 'StatHat'   };
local greatFeet = { stats = { Haste = 5, SwordSkill = 7, Accuracy = 5 },  ref = 'GreatFeet' };
local weakFeet  = { stats = { Accuracy = 2 },                             ref = 'WeakFeet'  };
local h1 = optim.optimizePicks({ Head = { hasteHat, statHat }, Feet = { greatFeet, weakFeet } }, W);
check('H1 feet take the cap with company', h1.picks.Feet ~= nil and 'GreatFeet',
      h1.picks.Feet ~= nil and ({ greatFeet, weakFeet })[h1.picks.Feet].ref);
check('H2 head yields the cap to real value', h1.picks.Head ~= nil and ({ hasteHat, statHat })[h1.picks.Head].ref, 'StatHat');
check('H3 capped set total', h1.total, 100 * 5 + 2 * 7 + 3 * (5 + 5));

-- empty preferred: a slot with only unweighted (or cap-redundant) gear stays home
local junk = { stats = { VIT = 9 }, ref = 'Junk' };
local h2 = optim.optimizePicks({ Head = { junk }, Feet = { greatFeet } }, W);
check('H4 unweighted slot stays empty', h2.picks.Head, nil);
local h3 = optim.optimizePicks({ Head = { hasteHat }, Feet = { greatFeet } }, W);
check('H5 cap-redundant slot stays empty', h3.picks.Head, nil);

-- paired-slot conflict: one physical copy cannot fill both rings
local ring = { stats = { Accuracy = 5 }, ref = 'OnlyRing' };
local h4 = optim.optimizePicks({ Ring1 = { ring }, Ring2 = { ring } }, W,
    { conflict = function(a, b) return a == b; end });
local filled = 0;
if h4.picks.Ring1 ~= nil then filled = filled + 1; end
if h4.picks.Ring2 ~= nil then filled = filled + 1; end
check('H6 one copy fills only one paired slot', filled, 1);

-- same-NAME duplicates (legacy gear.lua double entries) are ONE physical item:
-- the name-aware conflict must keep them out of both paired slots (the field
-- bug: two Jalzahn's Rings suggested from one owned ring)
local dupA = { stats = { Accuracy = 6 }, ref = { Name = "Jalzahn's Ring", Id = 901 } };
local dupB = { stats = { Accuracy = 6 }, ref = { Name = "Jalzahn's Ring" } };        -- legacy: no Id
local h4b = optim.optimizePicks({ Ring1 = { dupA }, Ring2 = { dupB } },
    { Accuracy = { perUnit = 3 } },
    { conflict = function(a, b)
        return a == b or (a.Id ~= nil and a.Id == b.Id)
            or string.lower(tostring(a.Name or '?')) == string.lower(tostring(b.Name or '??'));
    end });
local dupFilled = 0;
if h4b.picks.Ring1 ~= nil then dupFilled = dupFilled + 1; end
if h4b.picks.Ring2 ~= nil then dupFilled = dupFilled + 1; end
check('H6b same-name duplicate fills only one slot', dupFilled, 1);

-- baseStats background: an already-chosen set consumes the cap
local h5 = optim.optimizePicks({ Head = { hasteHat } }, W, { baseStats = { { Haste = 5 } } });
check('H7 background consumes the cap', h5.picks.Head, nil);

-- negative-good stats still score as goodness under caps
local WD = { DT = { perUnit = 10, cap = 10 } };
local dtA = { stats = { DT = -8 }, ref = 'A' };
local dtB = { stats = { DT = -8 }, ref = 'B' };
local h6 = optim.optimizePicks({ Body = { dtA }, Legs = { dtB } }, WD);
check('H8 DT capped as goodness', h6.total, 10 * 10);

-- ---------------------------------------------------------------------------
-- I. max-MP hold rule (dispatch.mpHoldNeeded) -- keep a worn MP piece while
--    swapping it out would waste unspent MP; release once it's spent.
--    Field spec: +50 MP head vs +5 MP incoming -> release after 45 MP spent.
-- ---------------------------------------------------------------------------
check('I1 full pool holds',           dispatchM.mpHoldNeeded(50, 5, 1000, 1000), true);
check('I2 one MP unspent still holds', dispatchM.mpHoldNeeded(50, 5, 956, 1000), true);
-- >= boundary on purpose: a battery equipped at a FULL pool sits exactly here
-- (cur == newMax - delta); releasing would drop it before any recovery landed
check('I3 exact boundary still holds', dispatchM.mpHoldNeeded(50, 5, 955, 1000), true);
check('I3b spent past the surplus releases', dispatchM.mpHoldNeeded(50, 5, 954, 1000), false);
check('I4 well spent releases',       dispatchM.mpHoldNeeded(50, 5, 700, 1000), false);
check('I5 incoming has more MP: never hold', dispatchM.mpHoldNeeded(5, 50, 1000, 1000), false);
check('I6 equal MP: never hold',      dispatchM.mpHoldNeeded(30, 30, 1000, 1000), false);
check('I7 nil-safe',                  dispatchM.mpHoldNeeded(nil, nil, nil, nil), false);

-- ---------------------------------------------------------------------------
-- J. THE central equip-eligibility rule (dispatch.jobCanEquip / canWear):
--    main job only (sub NEVER widens -- field-verified), level gated on main.
--    gearui, gearoptim and the automation manifests all delegate here.
-- ---------------------------------------------------------------------------
check('J1 no restriction wears',   dispatchM.jobCanEquip(nil, 'RDM'), true);
check('J2 All wears',              dispatchM.jobCanEquip({ 'All' }, 'RDM'), true);
check('J3 main job listed wears',  dispatchM.jobCanEquip({ 'WHM', 'RDM' }, 'RDM'), true);
check('J4 other job never wears',  dispatchM.jobCanEquip({ 'WHM' }, 'RDM'), false);
check('J5 canWear level gate',     dispatchM.canWear({ Jobs = { 'RDM' }, Level = 74 }, 'RDM', 73), false);
check('J6 canWear at level',       dispatchM.canWear({ Jobs = { 'RDM' }, Level = 74 }, 'RDM', 74), true);
check('J7 canWear wrong job',      dispatchM.canWear({ Jobs = { 'WHM' }, Level = 10 }, 'RDM', 75), false);

-- ---------------------------------------------------------------------------
-- K. max-MP battery pick (dispatch.mpPick): the manifest carries a LADDER per
--    slot (best first, may include gear to grow into); the engine wears the
--    best rung wearable at the LIVE level. Field case: Bunzi's Robe (99) in
--    rung 1 must not block a level-74 RDM from the level-59 rung below it.
-- ---------------------------------------------------------------------------
local ladder = { { name = 'Bunzi\'s Robe', mp = 50, level = 99 },
                 { name = 'Vermillion Cloak', mp = 30, level = 59 },
                 { name = 'Baron\'s Saio', mp = 10, level = 20 } };
check('K1 top rung at level',      dispatchM.mpPick(ladder, 99).name, 'Bunzi\'s Robe');
check('K2 fallback below level',   dispatchM.mpPick(ladder, 74).name, 'Vermillion Cloak');
check('K3 deep fallback',          dispatchM.mpPick(ladder, 30).name, 'Baron\'s Saio');
check('K4 nothing wearable',       dispatchM.mpPick(ladder, 10), nil);
check('K5 legacy single entry',    dispatchM.mpPick({ name = 'Astral Ring', mp = 25, level = 10 }, 74).name, 'Astral Ring');
check('K6 legacy entry too high',  dispatchM.mpPick({ name = 'X', mp = 1, level = 99 }, 74), nil);
check('K7 nil-safe',               dispatchM.mpPick(nil, 74), nil);

-- ---------------------------------------------------------------------------
-- L. THE central stats-at-level resolver (levelstats.effective), against the
--    REAL generated scaling data: Tamas Ring is MP 15 on paper, 29 at Lv74,
--    30 fully scaled (Lv75). Every section -- gearui display/scoring, gearoptim
--    ranking, the automation manifests -- resolves item stats through this one
--    function, so no section values a scaling item at its base stats.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\levelscaling'] = dofile('levelscaling.lua');
local lstats = dofile('levelstats.lua');
local tamas = { Name = 'Tamas Ring', Id = 15545, Level = 30,
                Stats = { MP = 15, INT = 2, MND = 2, Enmity = -3 } };
check('L1 Tamas MP at Lv74',       lstats.effective(tamas, 74).MP, 29);
check('L2 Tamas MP fully scaled',  lstats.effective(tamas, 75).MP, 30);
check('L3 base table never mutated', tamas.Stats.MP, 15);
check('L4 non-scaling passthrough', lstats.effective({ Id = 13548, Stats = { ConvertHPtoMP = 25 } }, 74).ConvertHPtoMP, 25);
check('L5 nil level = base stats', lstats.effective(tamas, nil).MP, 15);
check('L6 nil-safe',               lstats.effective(nil, 74), nil);

-- ---------------------------------------------------------------------------
-- M. cross-job cycle values. Mode DEFINITIONS are per-job trigger data; VALUES
--    are session-global (field case: "WHM Weapons" is defined in BRD's file and
--    gates WHM's sets). With no local definition: an explicit value jump works,
--    a bare flip must NOT toggle-corrupt the string into a boolean, off clears.
-- ---------------------------------------------------------------------------
check('M1 value jump without local def', dispatchM.setMode('WHM Weapons', 'DivinitySolo'), 'DivinitySolo');
check('M2 bare flip keeps the value',    dispatchM.setMode('WHM Weapons'), 'DivinitySolo');
check('M3 gated condition still true',   dispatchM.modeActive('WHM Weapons:DivinitySolo'), true);
check('M4 off still clears',             dispatchM.setMode('WHM Weapons', false), false);
check('M5 cleared for conditions',       dispatchM.modeActive('WHM Weapons:DivinitySolo'), false);

-- ---------------------------------------------------------------------------
-- N. mode-gated VIRTUAL slot entries. The Sets tab commits a gated virtual in
--    wrapper form ({ gear = 'dlac:AutoIridescence', mode = 'Weapon:Caster' });
--    only bare-string virtuals were recognised, so the gated marker flattened
--    to NOTHING (field case: WHM's Caster weapon cycle equipped no staff).
-- ---------------------------------------------------------------------------
AshitaCore = ashitaWithDW(true);
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
local function weaponSets()
    return { Dynamic = { Weapon = { Main = {
        { gear = 'dlac:AutoIridescence', mode = 'Weapon:Caster' },
        { gear = dagger1H, mode = 'Weapon:SoloKC' },
    } } } };
end
dispatchM.setMode('Weapon', 'Caster');            -- def-less value jump (section M)
local sV = utils.BuildDynamicSets(weaponSets());
check('N1 active gated virtual flattens', sV.Weapon and sV.Weapon.Main, 'dlac:AutoIridescence');
dispatchM.setMode('Weapon', 'SoloKC');
sV = utils.BuildDynamicSets(weaponSets());
check('N2 other value: the gated item wins', sV.Weapon and sV.Weapon.Main, 'Kris');
dispatchM.setMode('Weapon', false);
sV = utils.BuildDynamicSets(weaponSets());
check('N3 no value at all: slot left alone', sV.Weapon and sV.Weapon.Main, nil);

-- ---------------------------------------------------------------------------
-- P. a Main STAFF MARKER pairs like a two-handed staff: the grip that belongs
--    with it is a legal Sub (field case: Weapon:Caster grip sat unequipped
--    under dlac:AutoIridescence because currentMain stayed nil).
-- ---------------------------------------------------------------------------
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
AshitaCore = ashitaWithDW(false);
dispatchM.setMode('Weapon', 'Caster');
local vg = { Dynamic = { WV = {
    Main = { { gear = 'dlac:AutoIridescence', mode = 'Weapon:Caster' } },
    Sub  = { { gear = grip, mode = 'Weapon:Caster' } },
} } };
local sVG = utils.BuildDynamicSets(vg);
check('P1 marker main flattens',          sVG.WV and sVG.WV.Main, 'dlac:AutoIridescence');
check('P2 grip legal under the marker',   sVG.WV and sVG.WV.Sub, 'PoleGrip');
dispatchM.setMode('Weapon', false);

-- ---------------------------------------------------------------------------
-- Q. an explicitly RANGED entry owns its window: Garrison Tunica +1 ranged
--    20-51 must beat the higher-level unbounded Druid's Robe at 50 -- and hand
--    the slot back once the window closes.
-- ---------------------------------------------------------------------------
AshitaCore = ashitaWithDW(true);
local function rangedSets()
    return { Dynamic = { QT = { Body = {
        { Name = 'DruidsRobe', Level = 48 },
        { gear = { Name = 'GarrisonTunica', Level = 20 }, minLevel = 20, maxLevel = 51 },
    } } } };
end
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 50, SubJobSync = 25 };
local sQ = utils.BuildDynamicSets(rangedSets());
check('Q1 live range beats a higher unbounded item', sQ.QT and sQ.QT.Body, 'GarrisonTunica');
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 52, SubJobSync = 25 };
sQ = utils.BuildDynamicSets(rangedSets());
check('Q2 window closed: the unbounded item resumes', sQ.QT and sQ.QT.Body, 'DruidsRobe');
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 19, SubJobSync = 25 };
sQ = utils.BuildDynamicSets(rangedSets());
check('Q3 below the window: nothing forced', sQ.QT and sQ.QT.Body, nil);

-- ---------------------------------------------------------------------------
-- R. multi-set trigger rules round-trip: set = { 'Base', 'Overlay' } must
--    serialize as the ordered list (a wiped second set = a silently dead
--    overlay); a single set stays in the plain string form.
-- ---------------------------------------------------------------------------
local rtext = dispatchM.serializeTriggers({
    Midcast = {
        { when = { name = 'Madrigal' }, set = { 'WindSkill', 'Madrigal' } },
        { when = { skill = 'Singing' }, set = 'SongPotency' },
    },
});
check('R1 ordered list serialized',
    rtext:find([[set = { "WindSkill", "Madrigal" }]], 1, true) ~= nil, true);
check('R2 single set stays plain',
    rtext:find([[set = "SongPotency"]], 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- S. PetAction is a first-class trigger section (dlac-synthesized event: this
--    LAC build tracks the pet's action but never calls a profile handler).
-- ---------------------------------------------------------------------------
check('S1 event canon', dispatchM.canonEvent('petaction'), 'PetAction');
local stext = dispatchM.serializeTriggers({
    PetAction = { { when = { contains = 'Predator' }, set = 'PetWS' } },
});
check('S2 section serializes', stext:find('PetAction = {', 1, true) ~= nil, true);
check('S3 rule serializes', stext:find([[contains = "Predator"]], 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- T. craftwatch -- synth detection core (packet 0x096 decode + recipe lookup).
--    Layout per XiPackets GP_CLI_COMMAND_COMBINE_ASK: Crystal u16 @0x06,
--    Items u8 @0x09, ItemNo[8] u16 @0x0A.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\crafts'] = {
    ['4096:1165,1165'] = { skill = 'Alchemy', lv = 60 },
    ['4096:640,650']   = { skill = 'Smithing', lv = 10, desynth = true },
};
-- auto-equip deps, stubbed: a profile with a Craft_Alchemy set + a recording cmdqueue
local craftCmds = {};
package.loaded['dlac\\cmdqueue'] = {
    enqueue = function(delay, cmd) craftCmds[#craftCmds + 1] = cmd; end,
    frame = function() return 0; end, tick = function() end,
};
package.loaded['dlac\\profilesets'] = {
    getSetsRoot = function()
        return { Dynamic = {
            Craft_Alchemy = {
                Main  = 'Chemists Kukri',                       -- plain string
                Head  = { Name = 'Midrass Helm +1' },            -- record form
                Body  = { gear = 'Alchemists Smock', minLevel = 40 },  -- wrapper form
                Range = 'dlac:AutoStaff|Fallback',               -- virtual: must be skipped
            },
            Craft = { Neck = 'Artisans Torque' },                -- universal fallback set
        } };
    end,
};
local craftwatch = dofile('craftwatch.lua');

check('T1 key sorts ingredients', craftwatch.key(4096, { 650, 640 }), '4096:640,650');

-- synthetic 0x096: header(4) + HashNo + pad + crystal 4096 LE + idx + count 2
-- + ItemNo[8] (1165, 1165, zeroes) + TableNo[8]
local function u16le(v) return string.char(v % 256, math.floor(v / 256)); end
local pkt = string.char(0x96, 0x11, 0, 0)          -- header (id/size/sync -- unused by decode)
    .. string.char(0, 0)                            -- HashNo, padding
    .. u16le(4096) .. string.char(5)                -- Crystal, CrystalIdx
    .. string.char(2)                               -- Items = 2
    .. u16le(1165) .. u16le(1165) .. string.rep('\0', 12)  -- ItemNo[8]
    .. string.rep('\0', 8);                         -- TableNo[8]
local tcr, tings = craftwatch.decode(pkt);
check('T2 decode crystal', tcr, 4096);
check('T3 decode ingredient count', tings ~= nil and #tings or 0, 2);
check('T4 decode ingredient id', tings ~= nil and tings[1] or 0, 1165);
check('T5 lookup finds recipe', (craftwatch.lookup(4096, { 1165, 1165 }) or {}).skill, 'Alchemy');
check('T6 onSynth resolves craft', craftwatch.onSynth(4096, { 1165, 1165 }, 1).skill, 'Alchemy');
check('T7 onSynth desynth flag', craftwatch.onSynth(4096, { 650, 640 }, 2).desynth, true);
check('T8 unknown recipe fails soft', craftwatch.onSynth(4096, { 9999 }, 3).skill, 'unknown');
check('T9 malformed packet -> nil', craftwatch.decode('short'), nil);
check('T10 zero-ingredient packet -> nil',
    craftwatch.decode(string.char(0x96, 0x11, 0, 0, 0, 0) .. u16le(4096) .. string.char(5, 0) .. string.rep('\0', 24)), nil);

-- auto-equip: set entry resolution + the queued /lac commands
check('T11 entry: plain string',    craftwatch._entryName('Chemists Kukri'), 'Chemists Kukri');
check('T12 entry: virtual skipped', craftwatch._entryName('dlac:AutoStaff|Fallback'), nil);
check('T13 entry: record form',     craftwatch._entryName({ Name = 'X' }), 'X');
check('T14 entry: wrapper form',    craftwatch._entryName({ gear = 'Y', minLevel = 40 }), 'Y');
local function hasCmd(want)   -- craftCmds contains an exact command?
    for _, c in ipairs(craftCmds) do if c == want then return true; end end
    return false;
end
-- Craft gear must SURVIVE the engine, so each slot emits lock + disable +
-- native equip (returns the SLOT count, not the command count).
craftwatch._craftLocked = {}; craftCmds = {};
check('T15 equip returns slot count', craftwatch.equipCraftSet('Alchemy'), 3);
check('T16 locks the slot',           hasCmd('/dl lock main on'), true);
check('T16b native equip emitted',    hasCmd('/equip main "Chemists Kukri"'), true);
craftwatch._craftLocked = {}; craftCmds = {};
check('T17 fallback to Craft set',    craftwatch.equipCraftSet('Bonecraft'), 1);
check('T18 fallback equip command',   hasCmd('/equip neck "Artisans Torque"'), true);
-- MANUAL model (Henrik): you pick the craft, dlac equips it NOW. Detection
-- can't equip in time (0x096 is the first synth packet), so it's info only.
craftwatch._craftLocked = {}; craftCmds = {};
craftwatch.goal = 'hq';
craftwatch.selectCraft('Alchemy');
check('T19 selectCraft equips (locked)', hasCmd('/equip main "Chemists Kukri"'), true);
check('T19b selectCraft sets active',    craftwatch.getCraft(), 'Alchemy');
check('T19c selectCraft turns switch on', craftwatch.isEnabled(), true);
craftwatch._craftLocked = {}; craftCmds = {};
craftwatch.setGoal('nq');              -- re-equips the active craft under the new goal
check('T20 setGoal re-equips active',  #craftCmds > 0, true);
check('T20b goal stored',              craftwatch.getGoal(), 'nq');
craftCmds = {};
craftwatch.onSynth(4096, { 1165, 1165 }, 20);   -- detection: NO equip
check('T20c detection does not equip', #craftCmds, 0);
-- on/off switch: OFF releases locks; ON re-applies the active craft
craftwatch.enabled = false;
craftwatch._craftLocked = { main = true }; craftCmds = {};
craftwatch.setEnabled(false);          -- OFF: release the locked slot
check('T20d off releases locks',       hasCmd('/dl lock main off'), true);
craftwatch._craftLocked = {}; craftCmds = {};
craftwatch.setEnabled(true);           -- ON: equips the active craft
check('T20e enable equips active craft', hasCmd('/equip neck "Artisans Torque"') or #craftCmds > 0, true);
check('T20f enabled stored',           craftwatch.isEnabled(), true);
craftwatch.setEnabled(false);
craftwatch._craftLocked = {};
craftwatch.goal = 'hq';

-- 0x055 key item tracker (the SDK HasKeyItem memory read is dead on this
-- client -- craftwatch keeps its own bitfield from the packet stream).
-- Layout: u32 header | avail[0x40] | examined[0x40] | blockOffset | pad x3.
local function kiPacket(block, setBits)   -- setBits = { id, ... } within the block
    local avail = {};
    for i = 1, 0x40 do avail[i] = 0; end
    for _, id in ipairs(setBits) do
        local rel = id - block * 512;
        local x, y = math.floor(rel / 8), rel % 8;
        avail[x + 1] = avail[x + 1] + 2 ^ y;
    end
    local bytes = {};
    for i = 1, 0x40 do bytes[i] = string.char(avail[i]); end
    return string.char(0x55, 0x24, 0, 0) .. table.concat(bytes)
        .. string.rep('\0', 0x40) .. string.char(block) .. string.rep('\0', 3);
end
craftwatch.onKeyItemPacket(kiPacket(3, { 1988, 2044 }));   -- Carpenter + Culinarian
check('T21 ki bit -> owned',           craftwatch.hasKeyItem(2044), true);
check('T22 second ki bit -> owned',    craftwatch.hasKeyItem(1988), true);
check('T23 unset ki -> not owned',     craftwatch.hasKeyItem(2000), false);
check('T24 blocks counted',            craftwatch.kiBlocksSeen, 1);
craftwatch.onKeyItemPacket(kiPacket(3, { 1988 }));         -- resync without Culinarian
check('T25 cleared bit -> revoked',    craftwatch.hasKeyItem(2044), false);
check('T26 other block untouched',     craftwatch.hasKeyItem(1988), true);

-- ---------------------------------------------------------------------------
-- U. Set-entry name resolution -- case-insensitive fallback + quiet-once warn.
--    Field case (SMN "test" commit): static-migrated sets say "Solid wand" but
--    gear.lua's client name is "Solid Wand"; every rebuild flooded chat with
--    per-occurrence "Unable to find" lines and the entries flattened to nothing.
-- ---------------------------------------------------------------------------
TEST_PLAYER = { MainJob = 'SMN', SubJob = 'WHM', MainJobSync = 75, SubJobSync = 37 };
package.loaded['dlac\\gear'].NameToObject['Solid Wand'] =
    { Name = 'Solid Wand', Level = 20, Type = 'Club', OneHanded = true };
utils._resetNameIndex();
AshitaCore = ashitaWithDW(false);
local sCase = utils.BuildDynamicSets({ Dynamic = { Idle = { Main = { 'solid wand' } } } });
check('U1 case-insensitive name resolves', sCase.Idle and sCase.Idle.Main, 'Solid Wand');
local sWrap = utils.BuildDynamicSets({ Dynamic = { Idle = { Main = { { gear = 'SOLID WAND', minLevel = 10 } } } } });
check('U2 wrapper ref resolves case-blind', sWrap.Idle and sWrap.Idle.Main, 'Solid Wand');
local sMiss = utils.BuildDynamicSets({ Dynamic = { Idle = { Main = { 'No Such Item' } } } });
check('U3 missing name flattens empty, no error', sMiss.Idle and sMiss.Idle.Main, nil);

-- ---------------------------------------------------------------------------
-- T. deleteStaticSetText: removes a direct child of the sets ROOT (a legacy
--    static set), never the Dynamic block, never nested lookalikes.
-- ---------------------------------------------------------------------------
local setmgrT = dofile('setmanager.lua');
local statFix = table.concat({
    'local sets = {',
    '    Dynamic = {',
    '        TP = {',
    '            Main = { "A" },',
    '        },',
    '    },',
    '    Idle = {',
    '        Body = "X",',
    '        Sub = { "Y" },',
    '    },',
    '    Precast = { Head = "Z" },',
    '};',
    'profile = { Sets = sets };',
    'return profile;',
}, '\n');
local tOut, tAct = setmgrT.deleteStaticSetText(statFix, 'Idle');
check('T1 static deleted',        tAct, 'deleted static');
check('T2 block gone',            tOut ~= nil and tOut:find('Idle = {', 1, true), nil);
check('T3 Dynamic intact',        tOut ~= nil and tOut:find('TP = {', 1, true) ~= nil, true);
check('T4 sibling intact',        tOut ~= nil and tOut:find('Precast = {', 1, true) ~= nil, true);
check('T5 result parses',         tOut ~= nil and (loadstring or load)(tOut) ~= nil, true);
local _, tErr = setmgrT.deleteStaticSetText(statFix, 'Dynamic');
check('T6 Dynamic refused',       tErr, 'refusing to delete the Dynamic block');
local _, tErr2 = setmgrT.deleteStaticSetText(statFix, 'Sub');
check('T7 nested name never matches', tErr2 ~= nil and tErr2:find('no static set named', 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- V. dlac:AutoCraft resolution (craft automation, docs/design/craft-automation.md)
--    Per-slot manifest ladders, active craft from the 'craft' mode (or
--    ctx.craftOverride), goal from 'craftgoal' (hq default, STRICT per-goal --
--    no cross-goal substitution), level-gated best-first rungs.
-- ---------------------------------------------------------------------------
dispatchM._autoOverride = { craft = {
    neck = { Alchemy = {
        hq = { { name = 'Alchemists Torque', score = 30, level = 50 },
               { name = 'Artisans Torque',   score = 8,  level = 1 } },
        nq = { { name = 'Artisans Torque',   score = 8,  level = 1 } },
    } },
    ring1 = { Alchemy = {
        nq = { { name = 'Artisans Ring', score = 100, level = 45 } },
    } },
} };
local vctx = { player = { MainJobSync = 75 } };
dispatchM.modes['craft'] = 'Alchemy';
check('V1 hq default: best rung',   dispatchM._resolveVirtual('dlac:AutoCraft', vctx, 'Neck'), 'Alchemists Torque');
-- the goal is the manifest's ONE craftGoal field (no mode-system round-trip)
dispatchM._autoOverride.craftGoal = 'nq';
check('V2 nq goal picks nq ladder', dispatchM._resolveVirtual('dlac:AutoCraft', vctx, 'Neck'), 'Artisans Torque');
check('V3 nq ring1 ladder',         dispatchM._resolveVirtual('dlac:AutoCraft', vctx, 'Ring1'), 'Artisans Ring');
check('V4 STRICT per-goal: hq-only slot unresolved under nq',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 75 }, goalOverride = 'nq', craftOverride = 'Alchemy' }, 'Feet'), nil);
dispatchM._autoOverride.craftGoal = nil;
check('V5 level gate falls down the ladder',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 40 } }, 'Neck'), 'Artisans Torque');
dispatchM.modes['craft'] = nil;
check('V6 mode off -> unresolved',  dispatchM._resolveVirtual('dlac:AutoCraft', vctx, 'Neck'), nil);
check('V7 craftOverride resolves without the mode',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 75 }, craftOverride = 'Alchemy' }, 'Neck'), 'Alchemists Torque');
check('V8 slot without craft gear -> unresolved',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 75 }, craftOverride = 'Alchemy' }, 'Body'), nil);
-- third goal: skillup ladders resolve like the others (strictly per-goal)
dispatchM._autoOverride.craft.neck.Alchemy.skillup = { { name = 'Shapers Shawl', score = 250, level = 1 } };
check('V9 skillup goal picks skillup ladder',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 75 }, craftOverride = 'Alchemy', goalOverride = 'skillup' }, 'Neck'), 'Shapers Shawl');
dispatchM._autoOverride = nil;

-- ---------------------------------------------------------------------------
-- W. craftwatch tier / binding-craft calc: HQ tiers break at margins >11/31/51;
--    on subcraft recipes the SMALLEST margin binds (Henrik: enough clothcraft
--    but not bonecraft -> boost bonecraft).
-- ---------------------------------------------------------------------------
check('W1 tier 0 at margin 11',  craftwatch.tierOf(11), 0);
check('W2 tier 1 above 11',      craftwatch.tierOf(12), 1);
check('W3 tier 2 above 31',      craftwatch.tierOf(32), 2);
check('W4 tier 3 above 51',      craftwatch.tierOf(52), 3);
check('W5 nil margin -> nil',    craftwatch.tierOf(nil), nil);
local fakeSkill = function(cr) return ({ Clothcraft = 80, Bonecraft = 40 })[cr]; end
local bCr, bMg = craftwatch.bindingCraft({ Clothcraft = 60, Bonecraft = 35 }, fakeSkill);
check('W6 binding = smallest margin craft', bCr, 'Bonecraft');
check('W7 binding margin', bMg, 5);
check('W8 no skills -> nil', (craftwatch.bindingCraft(nil, fakeSkill)), nil);

-- ---------------------------------------------------------------------------
-- verdict
-- ---------------------------------------------------------------------------
if #failures == 0 then
    print(string.format('OK -- %d checks passed', count));
    os.exit(0);
end
print(string.format('FAIL -- %d of %d checks failed:', #failures, count));
for _, f in ipairs(failures) do print('  ' .. f); end
os.exit(1);
