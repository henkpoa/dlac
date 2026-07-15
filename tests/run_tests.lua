-- Headless tests for the profile-side rebuild engine (utils.lua).
-- Run from the dlac addon root:   lua tests\run_tests.lua
-- No Ashita required: gData / AshitaCore / ashita are stubbed below.

-- ---------------------------------------------------------------------------
-- environment stubs (must exist BEFORE utils.lua loads)
-- ---------------------------------------------------------------------------
package.loaded['dlac\\gear'] = { NameToObject = {} };   -- utils requires dlac\gear at load
ashita = { events = { register = function() end } };    -- utils registers /dl at load
package.loaded['dlac\\profiles'] = dofile('profiles.lua');   -- dispatch/setmanager require it (guarded)

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
local twinKris = { Name = 'Kris',          Level = 71, OneHanded = true,  Type = 'Dagger', Count = 2 };

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
    check('A8 same name: file Count >= 2',   f(twinKris, twinKris, { building = true            }), true);
    check('A8b equip: file Count enables same-name DW', f(twinKris, twinKris, { dw = true       }), true);
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
-- MANUAL model (Henrik): craftwatch just holds state (craft/goal/switch);
-- the ENGINE overlays the gear (dispatch.craftOverlay). No commands here.
-- saveCraftState no-ops without a live client, so we assert state only.
craftwatch.goal = 'hq';
craftwatch.selectCraft('Alchemy');
check('T15 selectCraft sets active',  craftwatch.getCraft(), 'Alchemy');
check('T16 select does NOT enable',   craftwatch.isEnabled(), false);
craftwatch.setEnabled(true);
check('T17 switch turns on',          craftwatch.isEnabled(), true);
craftwatch.setGoal('nq');
check('T18 goal stored',              craftwatch.getGoal(), 'nq');
craftwatch.onSynth(4096, { 1165, 1165 }, 20);   -- detection: info only, no state change
check('T19 detection keeps active',   craftwatch.getCraft(), 'Alchemy');
craftwatch.setEnabled(false);
check('T20 switch off',               craftwatch.isEnabled(), false);
craftwatch.goal = 'hq';

-- Engine overlay: dispatch resolves the craft gear per slot from the manifest
-- + goal (the same resolveVirtual path the addon preview uses).
dispatchM._autoOverride = { craft = {
    neck = { Alchemy = { hq = { { name = 'Artisan\'s Torque', score = 20, level = 1 } } } },
    ring1 = { Alchemy = { hq = { { name = 'Craftmaster\'s Ring', score = 5, level = 1 } } } },
} };
local ov = dispatchM._craftOverlayFor({ craft = 'Alchemy', goal = 'hq', enabled = true }, { player = { MainJobSync = 75 } });
check('T21 overlay resolves neck',    ov and ov.Neck, 'Artisan\'s Torque');
check('T22 overlay resolves ring1',   ov and ov.Ring1, 'Craftmaster\'s Ring');
local ovOff = dispatchM._craftOverlayFor({ craft = 'Alchemy', goal = 'hq', enabled = false }, { player = { MainJobSync = 75 } });
check('T23 disabled -> no overlay',   ovOff, nil);
local ovNoCraft = dispatchM._craftOverlayFor({ craft = '', goal = 'hq', enabled = true }, { player = { MainJobSync = 75 } });
check('T24 no craft -> no overlay',   ovNoCraft, nil);
dispatchM._autoOverride = nil;

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

-- Guild points from s2c 0x113 -- verify the byte offsets against Henrik's
-- in-game currency menu values. int32 LE at absolute e.data offsets.
local function i32(v) return string.char(v % 256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/16777216)%256); end
-- header(4) + PacketData: pad to fishing@0x20, then the 8 craft int32s.
local gpPkt = string.rep('\0', 0x20)   -- header + conquest/seals/... up to fishing
    .. i32(1111)      -- 0x20 fishing (ignored)
    .. i32(2555)      -- 0x24 woodworking
    .. i32(6536)      -- 0x28 smithing
    .. i32(10990)     -- 0x2C goldsmithing
    .. i32(540)       -- 0x30 weaving/clothcraft
    .. i32(23539)     -- 0x34 leathercraft
    .. i32(0)         -- 0x38 bonecraft
    .. i32(75200)     -- 0x3C alchemy
    .. i32(4325);     -- 0x40 cooking
craftwatch.onCurrencyPacket(gpPkt);
check('T27 gp woodworking',  craftwatch.guildPointsFor('Woodworking'), 2555);
check('T28 gp goldsmithing', craftwatch.guildPointsFor('Goldsmithing'), 10990);
check('T29 gp clothcraft(weaving)', craftwatch.guildPointsFor('Clothcraft'), 540);
check('T30 gp alchemy',      craftwatch.guildPointsFor('Alchemy'), 75200);
check('T31 gp cooking',      craftwatch.guildPointsFor('Cooking'), 4325);
check('T32 gp bonecraft zero', craftwatch.guildPointsFor('Bonecraft'), 0);
check('T33 gpReady', craftwatch.gpReady(), true);

-- Last Synth observation: onSynth must retain crystal + ingredients (they
-- label the craft bar's "Last synth:" line; /lastsynth itself is the GAME'S
-- native command -- dlac never intercepts or re-sends, so no slot/packet
-- machinery exists to test since c38c2ff's successor).
local curT = craftwatch.onSynth(4096, { 1165, 1165 }, 40);
check('T34 current keeps crystal', curT.crystal, 4096);
check('T35 current keeps ings order', curT.ings[1] == 1165 and #curT.ings == 2, true);

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
-- X. engine self-swap handshake (dispatch.lua hot-reload, v32). Re-executing
--    dispatch.lua with _G.__dlacEngineRoot set must populate THAT table --
--    identity preserved, so utils' captured reference and the profiles' shims
--    run the new code with no re-require -- and the swapper's version-parse
--    must find the real assignment (a reformat of the M.VERSION line would
--    kill the swap SILENTLY otherwise).
-- ---------------------------------------------------------------------------
local root = { VERSION = -1, dispatch = 'stale sentinel', leftover = 'kept' };
_G.__dlacEngineRoot = root;
local swapped = dofile('dispatch.lua');
_G.__dlacEngineRoot = nil;
check('X1 swap populates the handed-over root table', rawequal(swapped, root), true);
check('X2 stale fields are overwritten with live code', type(root.dispatch), 'function');
check('X3 version claimed on the root', root.VERSION, dispatchM.VERSION);
local fresh = dofile('dispatch.lua');
check('X4 normal load (no handshake) stays a fresh table', rawequal(fresh, root), false);
local fh = io.open('dispatch.lua', 'r');
local rawSrc = fh:read('*a'); fh:close();
check('X5 swapper version-parse finds the assignment',
    tonumber(string.match(rawSrc, 'M%.VERSION%s*=%s*(%d+)')), dispatchM.VERSION);

-- ---------------------------------------------------------------------------
-- Y. profile storage layer (profiles.lua, v33): the pure text machinery, and
--    headless safety (every fs/Ashita touch is call-time + guarded, so nil
--    answers -- never errors -- before login). The extract -> frame -> extract
--    round trip IS the migration's "your dynamic sets survive byte-for-byte"
--    guarantee; the splice checks pin that setmanager's scanners keep working
--    on the profile sets file unchanged.
-- ---------------------------------------------------------------------------
local profilesM = package.loaded['dlac\\profiles'];

check('Y1 loads headlessly', type(profilesM), 'table');
check('Y2 sanitize: ok name', profilesM.sanitizeName('My_Profile-2'), 'My_Profile-2');
check('Y3 sanitize: rejects spaces', profilesM.sanitizeName('two words'), nil);
check('Y4 sanitize: rejects path tricks', profilesM.sanitizeName('..\\evil'), nil);
check('Y5 headless: setsPath is nil pre-login', profilesM.setsPath('WAR'), nil);
check('Y6 headless: readSetsFile refuses politely', (select(2, profilesM.readSetsFile('WAR'))), 'not logged in');
check('Y7 headless: cloneProfile refuses politely', (select(2, profilesM.cloneProfile('A', 'B'))), 'not logged in');

-- a realistic job file: nested braces, a brace inside a comment, a brace inside
-- a string, mode/minLevel wrappers, virtual slot entries, static siblings.
local JOBFILE = [[
local profile = {};
local utils = require("dlac\utils");
local gear  = utils.gear;
local sets = {
    Dynamic = {
        Idle = {
            Head = {
                gear.Head.PoetsCirclet,
                { gear = gear.Head.WlkChapeau, minLevel = 60 },  -- gated { brace in comment
            },
            Body = { 'dlac:AutoStaff', gear.Body.Doublet_1 },
        },
        Tp_Default = {
            Main = { { gear = gear.Main.Club.MapleWand_1, mode = "Weapon:Melee}" } },
        },
    },
    Idle = { Head = "Poet's Circlet" },
    Precast = { Body = 'Doublet' },
};
profile.Sets = sets;
profile.HandleDefault = function() sets = utils.rebuildSets(sets); utils.dispatch('Default'); end
return profile;
]];

local dynText, dynErr = profilesM.extractDynamicText(JOBFILE);
check('Y8 extract finds the block', dynErr, nil);
check('Y9 extract starts at the keyword', dynText ~= nil and dynText:sub(1, 7), 'Dynamic');
check('Y10 extract keeps every set', dynText ~= nil and dynText:find('Tp_Default', 1, true) ~= nil, true);
check('Y11 extract stops at the block (statics excluded)', dynText ~= nil and dynText:find('Precast', 1, true), nil);
check('Y12 extract is verbatim (a substring of the source)', dynText ~= nil and JOBFILE:find(dynText, 1, true) ~= nil, true);
check('Y13 no block -> nil + why', (select(2, profilesM.extractDynamicText('local x = 1;'))), 'no sets.Dynamic block');

-- frame it into a profile sets file, run it, and extract it back out.
local function loadWithEnv(text, env)
    if setfenv ~= nil then
        local c = (loadstring or load)(text);
        if c == nil then return nil; end
        setfenv(c, env);
        return c;
    end
    return load(text, 'framed', 't', env);
end
local STUBG; STUBG = setmetatable({}, { __index = function() return STUBG; end });

local framed = profilesM.frameSetsText(dynText);
check('Y14 framed file parses', (loadstring or load)(framed) ~= nil, true);
check('Y15 frame -> extract round trip is byte-identical', profilesM.extractDynamicText(framed), dynText);
local fchunk = loadWithEnv(framed, setmetatable({ gear = STUBG }, { __index = _G }));
local fok, fsets = pcall(fchunk);
check('Y16 framed file runs', fok, true);
check('Y17 framed Dynamic has both sets', fok and type(fsets) == 'table' and type(fsets.Dynamic) == 'table'
    and fsets.Dynamic.Idle ~= nil and fsets.Dynamic.Tp_Default ~= nil, true);

local emptyFramed = profilesM.frameSetsText(nil);
local echunk = loadWithEnv(emptyFramed, setmetatable({ gear = STUBG }, { __index = _G }));
local eok, esets = pcall(echunk);
check('Y18 empty frame runs with an empty Dynamic', eok and type(esets) == 'table'
    and type(esets.Dynamic) == 'table' and next(esets.Dynamic) == nil, true);

-- setmanager's scanners work on the framed file UNCHANGED (commit/delete land
-- in profile storage now -- this is the compatibility that makes that free).
local spliced, saction = setmgrT.spliceSet(framed, 'Resting', {
    { name = 'Head', items = { { path = 'gear.Head.PoetsCirclet' } } },
});
check('Y19 splice into framed file', saction, 'inserted');
check('Y20 spliced framed file still parses', (loadstring or load)(spliced or '') ~= nil, true);
local deleted, daction = setmgrT.deleteSetText(spliced, 'Idle');
check('Y21 delete from framed file', daction, 'deleted');
local dchunk = loadWithEnv(deleted, setmetatable({ gear = STUBG }, { __index = _G }));
local dok, dsets = pcall(dchunk);
check('Y22 delete removed only the target set', dok and dsets.Dynamic.Idle == nil
    and dsets.Dynamic.Tp_Default ~= nil and dsets.Dynamic.Resting ~= nil, true);

-- the clean shim
check('Y23 shim parses', (loadstring or load)(profilesM.shimFileText()) ~= nil, true);
check('Y24 shim recognized', profilesM.isCleanShim(profilesM.shimFileText()), true);
check('Y25 a real profile is NOT a shim', profilesM.isCleanShim(JOBFILE), false);

-- the migration planner (pure): shims and backed-up jobs are never touched,
-- Dynamic blocks travel verbatim, an existing profile sets file is never
-- overwritten by an import.
local plan = profilesM.planMigration({
    { job = 'WAR', text = JOBFILE, hasBackup = false, hasProfileSets = false, hasLegacyTrig = true,  hasProfileTrig = false },
    { job = 'WHM', text = profilesM.shimFileText(), hasBackup = false, hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'BLM', text = JOBFILE, hasBackup = true,  hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'RDM', text = 'local x = 1; return x;', hasBackup = false, hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'THF', text = JOBFILE, hasBackup = false, hasProfileSets = true,  hasLegacyTrig = false, hasProfileTrig = false },
});
check('Y26 plan: real profile migrates', plan[1].action, 'migrate');
check('Y27 plan: Dynamic block travels verbatim', plan[1].dynText, dynText);
check('Y28 plan: clean shim skipped', plan[2].action, 'skip');
check('Y29 plan: existing backup means hands off', plan[3].action, 'skip');
check('Y30 plan: no Dynamic block -> empty store, still migrates', plan[4].action == 'migrate' and plan[4].dynText == nil, true);
check('Y31 plan: existing profile sets file is never re-imported over', plan[5].action == 'migrate' and plan[5].dynText == nil, true);

-- missing-gear-safe sets loading (profile sharing): a reader who doesn't own
-- referenced items gets ladder HOLES (nil), a missing weapon CATEGORY resolves
-- through an empty table instead of erroring the whole file away, and items
-- the reader DOES own come back as the REAL records (identity-shared).
do
    local myGear = { Main = { Sword = { Joyeuse = { Name = 'Joyeuse' } } }, Sub = {}, Head = { Cap = { Name = 'Cap' } } };
    local g = profilesM._wrapGear(myGear);
    check('Y38 owned item is the REAL record', rawequal(g.Head.Cap, myGear.Head.Cap), true);
    check('Y39 unowned item -> nil ladder hole', g.Head.Crown, nil);
    check('Y40 missing weapon CATEGORY does not error', (pcall(function() return g.Main.Club.MapleWand_1; end)) and (g.Main.Club.MapleWand_1 == nil), true);
    check('Y41 flat Sub: missing item is nil, not a table', g.Sub.Pelte, nil);
    check('Y42 owned nested item is the REAL record', rawequal(g.Main.Sword.Joyeuse, myGear.Main.Sword.Joyeuse), true);
end

-- per-job export/import: the %q-encoded payload round trip must be byte-exact
-- (quotes, newlines, long-bracket sequences and all), and damaged/foreign
-- files must be rejected, never half-imported.
do
    local setsBlob = 'local sets = {\n    Dynamic = {\n        Idle = { Head = { gear.Head.X } },  -- "quoted" and ]==] tricky\n    },\n};\nreturn sets;\n';
    local trigBlob = 'return {\n    Default = { { when = { status = "Engaged" }, set = \'Tp_Default\' } },\n};\n';
    local ex = profilesM.buildExportText('BLU', 'Default', 'Mindie', setsBlob, trigBlob);
    local meta, perr = profilesM.parseExportText(ex);
    check('Y43 export parses back', perr, nil);
    check('Y44 export meta survives', meta ~= nil and meta.job == 'BLU' and meta.profile == 'Default' and meta.from == 'Mindie', true);
    check('Y45 sets payload is byte-exact', meta ~= nil and meta.sets, setsBlob);
    check('Y46 triggers payload is byte-exact', meta ~= nil and meta.triggers, trigBlob);
    check('Y47 sets-only export is valid', (profilesM.parseExportText(profilesM.buildExportText('WHM', 'P', 'X', setsBlob, nil))) ~= nil, true);
    check('Y48 foreign lua file rejected', (select(2, profilesM.parseExportText('return { some = "table" };'))), 'not a dlac job export');
    check('Y49 garbage rejected', (select(2, profilesM.parseExportText('this is not lua {'))), 'file does not parse');
    check('Y50 headless: importJobFile refuses politely', (select(2, profilesM.importJobFile('somefile', 'Other_1', 'Default', 'BLU'))), 'not available');
    check('Y51 headless: listExports is nil, never an error', profilesM.listExports(), nil);
end

-- lockstyle path resolution (v40, per-profile boxes): headless = pre-login,
-- every path is nil and the read resolver answers nil instead of erroring.
check('Y52 headless: lockstylesPath is nil pre-login', profilesM.lockstylesPath(), nil);
check('Y53 headless: legacyLockstylesPath is nil pre-login', profilesM.legacyLockstylesPath(), nil);
check('Y54 headless: readLockstylesPath is nil, never an error', profilesM.readLockstylesPath(), nil);

-- cross-character browsing/import: headless-safe (no AshitaCore -> nil answers).
check('Y34 headless: importProfile refuses politely', (select(2, profilesM.importProfile('Other_1', 'Default', 'New'))), 'not logged in');
check('Y35 headless: importProfile still validates the name first', (select(2, profilesM.importProfile('Other_1', 'Default', 'bad name'))), 'bad target name (letters/digits/_/- only)');
check('Y36 headless: listCharFolders is nil, never an error', (profilesM.listCharFolders()), nil);
check('Y37 headless: profileJobsAt empty, never an error', #profilesM.profileJobsAt('Other_1', 'Default'), 0);

-- headless migrate: refuses politely, touches nothing, never errors.
local said = {};
local mdone, mskip, mfail = profilesM.migrate(false, function(s) said[#said + 1] = s; end);
check('Y32 headless migrate is a safe no-op', mdone == 0 and mskip == 0 and mfail == 0, true);
check('Y33 headless migrate says why', #said > 0 and said[1]:find('log in first', 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- Z. gear export (/dl export -> gearexport.json for external tools, e.g. the
--    friend's damage simulator). The pure builders: JSON encoding (escaping,
--    scalar arrays inline, sorted object keys, integer formatting) and the
--    export walk (armor slots hold records DIRECTLY, weapon slots hold TYPE
--    BUCKETS -- both shapes; catalog gap-fill with owned-override precedence;
--    augments attached by id).
-- ---------------------------------------------------------------------------
local gx = dofile('gearexport.lua');
check('Z1 json escapes quotes/backslash/newline', gx.jsonEncode('a"b\\c\n'), '"a\\"b\\\\c\\n"');
check('Z2 scalar array stays inline', gx.jsonEncode({ 1, -5, 'x', true }), '[1, -5, "x", true]');
check('Z3 object keys sorted', gx.jsonEncode({ b = 1, a = 2 }), '{\n  "a": 2,\n  "b": 1\n}');
check('Z4 integers never get a decimal point', gx.jsonEncode(276.0), '276');

local zGear = {
    Main = { Axe = { K = { Name = 'Kriegsbeil', Id = 1, Level = 70, Jobs = { 'WAR' },
                           Type = 'Axe', OneHanded = true, Stats = { DMG = 3, Delay = 276 } } } },
    Head = { H = { Name = 'Brass Cap', Id = 2, Level = 11, Jobs = { 'WAR', 'MNK' } },
             Z = { Name = 'Aketon', Id = 3, Level = 50, Jobs = { 'WAR' } } },
    NameToObject = { Kriegsbeil = { Name = 'SHOULD NOT APPEAR', Id = 99 } },
};
local zCat  = { [1] = { Stats = { DMG = 99, ACC = 5 } }, [2] = { Stats = { DEF = 4 }, Type = 'Armor' } };
local zAugs = { [1] = { 'STR+1, DEX+1' } };
local zAugStats = { [1] = { STR = 1, DEX = 1 } };
local zCounts = { [1] = 2 };   -- owned-anywhere map: two Kriegsbeil, nothing else in bags
local zExp = gx.buildExport(zGear, zCat, zAugs, zAugStats, zCounts, { character = 'Testy' });
check('Z5 both category shapes walked', zExp.itemCount, 3);
check('Z6 slot order: Main before Head', zExp.items[1].name, 'Kriegsbeil');
check('Z7 within a slot: sorted by name', zExp.items[2].name, 'Aketon');
check('Z8 owned stat overrides catalog', zExp.items[1].stats.DMG, 3);
check('Z9 catalog fills the gaps (same record)', zExp.items[1].stats.ACC, 5);
check('Z10 catalog stats for a bare record', zExp.items[3].stats.DEF, 4);
check('Z11 catalog type backfill', zExp.items[3].type, 'Armor');
check('Z12 augments attach by id', zExp.items[1].augments[1], 'STR+1, DEX+1');
check('Z13 augment stat deltas attach by id', zExp.items[1].augmentStats.STR, 1);
check('Z14 no augments -> key omitted', zExp.items[2].augments, nil);
check('Z15 meta lands at the root', zExp.character, 'Testy');
check('Z16 copy count attaches by id', zExp.items[1].count, 2);
check('Z17 scanned map, missing id -> count 0 (not owned now)', zExp.items[2].count, 0);
local zExpNC = gx.buildExport(zGear, zCat, nil, nil, nil, {});
check('Z18 no scan -> count omitted (unknown is not 0)', zExpNC.items[1].count, nil);
local zJson = gx.jsonEncode(zExp);
check('Z19 full export encodes with the format marker',
    string.find(zJson, '"format": "dlac-gear-export"', 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- AC. AutoAcc type automation -- entries typed autoType='AutoAcc' flatten to a
--     budgeted marker 'dlac:AutoAcc:<prio>:<acc>:<Name>|<fallback>' (utils);
--     the engine releases them against the cap surplus accwatch publishes to
--     accstate.lua (dispatch._accResolveSet). The WRITER (accwatch) ships on
--     feature/autoacc pending GM approval -- these tests cover main's dormant
--     foundation, which the branch relies on. Rules under test (Henrik
--     2026-07-14): fallback = the slot's normal pick; two typed candidates ->
--     the higher-leveled item wins; release order = removePrio desc, only as
--     far as the surplus covers; invalid/stale/missing measurement -> pieces
--     stay worn ("handle the equipment as per usual"); the budget folds
--     already-released pieces back in, so a re-measure never flaps.
-- ---------------------------------------------------------------------------
do
    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
    AshitaCore = ashitaWithDW(true);
    local peacock = { Name = 'Peacock Charm',    Level = 33 };
    local spike   = { Name = 'Spike Necklace',   Level = 20 };
    local chiv    = { Name = 'Chivalrous Chain', Level = 60 };

    -- flatten: typed entry -> marker half, the slot's normal pick -> fallback
    local acSets = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { spike, { gear = peacock, autoType = 'AutoAcc', removePrio = 3, acc = 10 } },
    } } });
    check('AC1 marker + fallback', acSets.TP and acSets.TP.Neck,
        'dlac:AutoAcc:3:10:Peacock Charm|Spike Necklace');

    local acTwo = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { spike,
                 { gear = peacock, autoType = 'AutoAcc', removePrio = 3, acc = 10 },
                 { gear = chiv,    autoType = 'AutoAcc', removePrio = 5, acc = 8 } },
    } } });
    check('AC2 higher-leveled candidate wins the slot', acTwo.TP and acTwo.TP.Neck,
        'dlac:AutoAcc:5:8:Chivalrous Chain|Spike Necklace');

    local acBare = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { { gear = peacock, autoType = 'AutoAcc', removePrio = 3, acc = 10 } },
    } } });
    check('AC3 no fallback -> bare marker', acBare.TP and acBare.TP.Neck,
        'dlac:AutoAcc:3:10:Peacock Charm');

    local acDef = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { { gear = peacock, autoType = 'AutoAcc' } },
    } } });
    check('AC4 defaults: prio 1, acc 0', acDef.TP and acDef.TP.Neck,
        'dlac:AutoAcc:1:0:Peacock Charm');

    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 20, SubJobSync = 10 };
    local acOver = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { spike, { gear = peacock, autoType = 'AutoAcc', removePrio = 3, acc = 10 } },
    } } });
    check('AC5 under-leveled candidate: plain fallback, no marker',
        acOver.TP and acOver.TP.Neck, 'Spike Necklace');
    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };

    -- marker parser (name deliberately LAST so any item name survives)
    local pr, ac, nm = dispatchM._parseAccMarker('dlac:AutoAcc:3:10:Peacock Charm');
    check('AC6 marker parses prio', pr, 3);
    check('AC7 marker parses acc', ac, 10);
    check('AC8 marker parses name', nm, 'Peacock Charm');
    check('AC9 other virtuals do not parse', dispatchM._parseAccMarker('dlac:AutoObi'), nil);

    -- engine decisions, driven through the accstate test seam
    local SNECK = { Neck = 'dlac:AutoAcc:3:10:Peacock Charm|Spike Necklace' };
    dispatchM._accReset();
    dispatchM._accStateOverride = nil;
    local r = dispatchM._accResolveSet(SNECK);
    check('AC10 no measurement -> piece worn', r and r.Neck, 'Peacock Charm');

    dispatchM._accStateOverride = { seq = 1, valid = true, capGap = -10 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC11 over cap by its acc -> released to fallback', r and r.Neck, 'Spike Necklace');

    -- next engage measures with the charm OFF (capGap 0); the budget folds the
    -- released 10 back in, so the decision holds instead of flapping
    dispatchM._accStateOverride = { seq = 2, valid = true, capGap = 0 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC12 stable across the re-measure', r and r.Neck, 'Spike Necklace');

    dispatchM._accStateOverride = { seq = 3, valid = true, capGap = 4 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC13 harder mob -> piece comes back', r and r.Neck, 'Peacock Charm');

    dispatchM._accReset();
    dispatchM._accStateOverride = { seq = 4, valid = true, capGap = -8 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC14 surplus below the acc -> worn', r and r.Neck, 'Peacock Charm');

    -- removal priority: HIGHER released first; the leftover budget is not
    -- enough for the second candidate
    local two = {
        Neck  = 'dlac:AutoAcc:3:10:Peacock Charm|Spike Necklace',
        Ring1 = 'dlac:AutoAcc:9:6:Woodsman Ring|Courage Ring',
    };
    dispatchM._accReset();
    dispatchM._accStateOverride = { seq = 5, valid = true, capGap = -12 };
    r = dispatchM._accResolveSet(two);
    check('AC15 higher removePrio released first', r and r.Ring1, 'Courage Ring');
    check('AC16 leftover budget too small -> worn', r and r.Neck, 'Peacock Charm');

    -- generous surplus (measured with the ring already off) -> both released
    dispatchM._accStateOverride = { seq = 6, valid = true, capGap = -20 };
    r = dispatchM._accResolveSet(two);
    check('AC17a both fit: neck released', r and r.Neck, 'Spike Necklace');
    check('AC17b both fit: ring released', r and r.Ring1, 'Courage Ring');

    -- unknown mob / no calc -> valid=false: worn as usual, release state wiped
    dispatchM._accStateOverride = { seq = 7, valid = false, capGap = 0 };
    r = dispatchM._accResolveSet(two);
    check('AC18a invalid -> neck worn as usual', r and r.Neck, 'Peacock Charm');
    check('AC18b invalid -> ring worn as usual', r and r.Ring1, 'Woodsman Ring');

    dispatchM._accStateOverride = { seq = 8, valid = true, capGap = -20, at = os.time() - 3600 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC19 stale measurement (>15 min) -> worn', r and r.Neck, 'Peacock Charm');

    dispatchM._accReset();
    dispatchM._accStateOverride = { seq = 9, valid = true, capGap = -50 };
    r = dispatchM._accResolveSet({ Neck = 'dlac:AutoAcc:3:10:Peacock Charm' });
    check('AC20 no fallback -> never released', r and r.Neck, 'Peacock Charm');

    r = dispatchM._accResolveSet({ Neck = 'dlac:AutoAcc:3:0:Peacock Charm|Spike Necklace' });
    check('AC21 zero acc -> never released', r and r.Neck, 'Peacock Charm');

    check('AC22 set without markers -> nil (no decisions)',
        dispatchM._accResolveSet({ Neck = 'Spike Necklace' }), nil);

    -- serializer: the wrapper carries the type fields through a Commit
    local acSer = table.concat(setmgr.renderSetLines('T', {
        { name = 'Neck', items = {
            { path = 'gear.Neck.PeacockCharm', autoType = 'AutoAcc', removePrio = 3, acc = 10 },
        } },
    }), '\n');
    check('AC23 serializes autoType', acSer:find('autoType = "AutoAcc"', 1, true) ~= nil, true);
    check('AC24 serializes removePrio + acc', acSer:find('removePrio = 3, acc = 10', 1, true) ~= nil, true);

    dispatchM._accStateOverride = nil;
    dispatchM._accReset();
end

-- (The accwatch custom-mob family tests -- section AD -- live on
--  feature/autoacc with accwatch.lua/accdata.lua, pending GM approval.)

-- ---------------------------------------------------------------------------
-- AE. per-set stat-weight memory (gearoptim.bindSetWeights) -- every set owns
--     its weights; the first bind SEEDS from the shared table; switching sets
--     never carries another set's edits along (Henrik's isolation rule).
--     Headless: weightsPath() is nil, so persistence no-ops and this is all
--     in-memory binding semantics.
-- ---------------------------------------------------------------------------
optim.setWeight('Accuracy', 20, 60);                        -- nothing bound: edits the shared table
check('AE1 shared holds the edit', optim.getWeights()['Accuracy'].perUnit, 20);
check('AE2 nothing bound yet', optim.weightsBoundTo(), nil);
check('AE3 first bind reports a change', optim.bindSetWeights('DRK', 'Midshort'), true);
check('AE4 first bind seeds from shared', optim.getWeights()['Accuracy'].perUnit, 20);
optim.setWeight('STR', 5);                                  -- edits now belong to the BOUND set
optim.setWeight('Accuracy', 99);
check('AE5 rebind of the same key is a no-op', optim.bindSetWeights('DRK', 'Midshort'), false);
optim.bindSetWeights('DRK', 'Tp_Default');
check('AE6 second set seeds from SHARED, not the last-used set', optim.getWeights()['Accuracy'].perUnit, 20);
check('AE7 second set did not inherit the STR edit', optim.getWeights()['STR'], nil);
optim.bindSetWeights('DRK', 'Midshort');
check('AE8 re-selecting a set gets its own edits back', optim.getWeights()['Accuracy'].perUnit, 99);
check('AE9 ...including added stats', optim.getWeights()['STR'].perUnit, 5);
check('AE10 unbinding returns the shared table', (optim.bindSetWeights(nil, nil) == true)
    and optim.getWeights()['Accuracy'].perUnit, 20);
check('AE11 shared never saw the set edits', optim.getWeights()['STR'], nil);
check('AE12 pre-login job "?" never creates a binding', optim.bindSetWeights('?', 'AnySet'), false);
check('AE13 ...and stays on shared', optim.weightsBoundTo(), nil);
optim.bindSetWeights('DRK', 'Midshort');
check('AE14 score() follows the binding', optim.score({ Accuracy = 1 }), 99);
optim.bindSetWeights(nil, nil);
check('AE15 score() follows the shared table back', optim.score({ Accuracy = 1 }), 20);
optim.clearWeight('Accuracy');                              -- leave the shared table as found

-- ---------------------------------------------------------------------------
-- AF. craft Sub-vs-Main guard (dispatch.craftMainGuard + the equipResolved
--     post-pass) -- while the craft overlay owns Sub with no Main of its own,
--     a set Main that can't PAIR with that Sub (subSlotAllowed) is HELD out of
--     the dispatch (field case: Kupo Shield vs a scythe knocking each other
--     off every pass). Stateless: overlay gone -> Main dispatches again.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\utils'] = utils;   -- the guard resolves pairing through utils
local gearT = package.loaded['dlac\\gear'];
gearT.NameToObject['Kupo Shield']  = { Name = 'Kupo Shield',  Type = 'Sub' };   -- catalog vocab: Sub + name -> Shield
gearT.NameToObject['Death Scythe'] = { Name = 'Death Scythe', Type = 'Great Scythe', OneHanded = false };
gearT.NameToObject['Parry Knife']  = { Name = 'Parry Knife',  Type = 'Dagger', OneHanded = true };
gearT.NameToObject['Cat Baghnakhs'] = { Name = 'Cat Baghnakhs', Type = 'Hand-to-Hand' };   -- H2H: no OneHanded flag
utils._resetNameIndex();

local guard = dispatchM._craftMainGuard({ Sub = 'Kupo Shield', Hands = 'Weaver Gloves' });
check('AF1 guard built when the overlay has Sub but no Main', guard ~= nil, true);
check('AF2 a 2H Main is held', guard('Death Scythe'), true);
check('AF3 a 1H Main pairs fine and passes', guard('Parry Knife'), false);
check('AF4 an H2H Main is held', guard('Cat Baghnakhs'), true);
check('AF5 an unknown Main name is left alone', guard('Mystery Club'), false);
check('AF6 no guard when the overlay brings its own Main',
    dispatchM._craftMainGuard({ Sub = 'Kupo Shield', Main = 'Parry Knife' }), nil);
check('AF7 no guard when the overlay has no Sub',
    dispatchM._craftMainGuard({ Hands = 'Weaver Gloves' }), nil);

-- the equipResolved post-pass: the offending Main is dropped, everything else kept
local afNote, afTbl = dispatchM._equipResolved({ Main = 'Death Scythe', Body = 'Weaver Apron' },
    { craftMainGuard = guard });
check('AF8 offending Main held out of the equip', afTbl.Main, nil);
check('AF9 the rest of the set is untouched', afTbl.Body, 'Weaver Apron');
check('AF10 the hold is traced for /dl why', string.find(afNote, 'HELD', 1, true) ~= nil, true);
local _, afTbl2 = dispatchM._equipResolved({ Main = 'Parry Knife' }, { craftMainGuard = guard });
check('AF11 a pairable Main equips normally', afTbl2.Main, 'Parry Knife');
local _, afTbl3 = dispatchM._equipResolved({ Main = 'Death Scythe' }, {});
check('AF12 no guard, no hold (craft off)', afTbl3.Main, 'Death Scythe');

-- ---------------------------------------------------------------------------
-- AG. lockstyle sets -- dispatch._lockstyleFrom picks the box and reduces it
--     to what gFunc.LockStyle takes; lockstyle.lua's serializer round-trips.
-- ---------------------------------------------------------------------------
local lsT = {
    active = 2,
    onload = { DRK = 2 },
    slots = {
        [1] = { name = 'AF Glam', set = { Main = 'Kris', Head = 'Ducal Guard\'s Ribbon', Body = 'remove' } },
        [2] = { name = '',        set = { Body = 'Weaver Apron' } },
        [3] = { name = 'Broken',  set = { Head = 42, Body = '' } },   -- nothing usable
    },
};
local g1, n1, b1 = dispatchM._lockstyleFrom(lsT, 1);
check('AG1 explicit box wins', b1, 1);
check('AG2 slot names ride', g1.Main, 'Kris');
check('AG3 the remove literal rides too', g1.Body, 'remove');
check('AG4 box name returned', n1, 'AF Glam');
local g2, n2, b2 = dispatchM._lockstyleFrom(lsT, nil);
check('AG5 no box arg -> the marked (active) box', b2, 2);
check('AG6 unnamed box falls back to "box N"', n2, 'box 2');
check('AG7 non-string and empty values are dropped', (dispatchM._lockstyleFrom(lsT, 3)), nil);
check('AG8 empty box says so', select(2, dispatchM._lockstyleFrom(lsT, 9)), 'lockstyle box 9 is empty');
check('AG9 no file/table says so', select(2, dispatchM._lockstyleFrom(nil)), 'no lockstyle sets saved yet');

-- serializer round-trip (lockstyle.lua is addon-state UI but its serializer is pure)
local lockstyleM = dofile('lockstyle.lua');
local lsText = lockstyleM._serialize(lsT);
local lsChunk = (loadstring or load)(lsText);
check('AG10 serialized file parses', lsChunk ~= nil, true);
local lsBack = lsChunk();
check('AG11 active survives', lsBack.active, 2);
check('AG12 onload survives', lsBack.onload.DRK, 2);
check('AG13 set entries survive', lsBack.slots[1].set.Main, 'Kris');
check('AG14 quoting survives an apostrophe', lsBack.slots[1].set.Head, 'Ducal Guard\'s Ribbon');
check('AG15 round-trip feeds _lockstyleFrom', (dispatchM._lockstyleFrom(lsBack, 1)).Main, 'Kris');

-- preview plan (v39): the engine wears ONLY the lockstyle while enabled
local pv = dispatchM._lsPreviewPlan({ enabled = true, set = {
    Main = 'Kris', Body = 'remove', Head = 'Ducal Guard\'s Ribbon', Neck = 'Spike Necklace', Hands = '' } });
check('AG16 preview equips the visual picks', pv.equip.Main, 'Kris');
check('AG17 remove/empty/non-visual values are not equipped',
    pv.equip.Body == nil and pv.equip.Neck == nil and pv.equip.Hands == nil, true);
local nk = {};
for _, i in ipairs(pv.naked) do nk[i] = true; end
check('AG18 uncovered slots strip (Sub, Body-via-remove, Back)', nk[2] == true and nk[6] == true and nk[16] == true, true);
check('AG19 covered slots do NOT strip', nk[1] or nk[5], nil);
check('AG20 disabled file -> no plan', dispatchM._lsPreviewPlan({ enabled = false, set = { Main = 'Kris' } }), nil);

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
