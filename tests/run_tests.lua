-- Headless tests for the profile-side rebuild engine (utils.lua).
-- Run from the dlac addon root:   lua tests\run_tests.lua
-- No Ashita required: gData / AshitaCore / ashita are stubbed below.

-- ---------------------------------------------------------------------------
-- environment stubs (must exist BEFORE utils.lua loads)
-- ---------------------------------------------------------------------------
package.loaded['dlac\\gear'] = { NameToObject = {} };   -- utils requires dlac\gear at load
ashita = { events = { register = function() end } };    -- utils registers /dl at load
package.loaded['dlac\\profiles'] = dofile('profiles.lua');   -- dispatch/setmanager require it (guarded)
package.loaded['dlac\\data\\nativemp'] = dofile('data/nativemp.lua');   -- dispatch requires it (Oneiros resolver)
package.loaded['dlac\\data\\zones'] = dofile('data/zones.lua');   -- dispatch requires it (the inTown town set)
package.loaded['dlac\\feature\\mpbands'] = dofile('feature/mpbands.lua');   -- dispatch requires it (the banded ladder, maxmp v2)
package.loaded['dlac\\feature\\location'] = dofile('feature/location.lua');   -- lockstyle requires it (Disable-in-town)
package.loaded['dlac\\gear\\gearrecord'] = dofile('gear/gearrecord.lua');   -- record rules: gearimport/weaponfilter/gearexport require it
package.loaded['dlac\\lib\\safewrite'] = dofile('lib/safewrite.lua');   -- safe-replace ladder: gearimport requires it, profiles guards it
package.loaded['dlac\\gear\\catalogindex'] = dofile('gear/catalogindex.lua');   -- catalog walker: gearimport requires it (no catalog headless -> empty indexes)
package.loaded['dlac\\lib\\statefile'] = dofile('lib/statefile.lua');   -- addon-side charDir: the watchers require it (guarded)

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
local gearimport = dofile('gear/gearimport.lua');
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

-- RSlot backfill: the reserved-slot fact reaches an EXISTING gear.lua only through
-- /dl fix (the engine has no catalog to look it up in). Any slot, not just weapons.
local e2Gear = table.concat({
    'gear = {',
    '    Body = {',
    '        RylFtmTunic = {',
    '            Name = "Ryl.Ftm. Tunic",',
    '            Level = 10,',
    '            Id = 13718,',
    '        },',
    '        CottonDoublet = {',
    '            Name = "Cotton Doublet",',
    '            Level = 9,',
    '            Id = 12588,',
    '        },',
    '    },',
    '};',
}, '\n');
local e2Meta = { [13718] = { Type = 'Body', RSlot = 16 }, [12588] = { Type = 'Body' } };
local e2Text, e2Rep = gearimport.computeFixes(e2Gear, {}, e2Meta);
check('E7 RSlot stamped on a reserving Body', e2Text:find('RSlot = 16', 1, true) ~= nil, true);
check('E8 non-reserving items stay thin',     select(2, e2Text:gsub('RSlot', '')), 1);
check('E9 result still parses',               (loadstring or load)(e2Text) ~= nil, true);
local _, e2Rep2 = gearimport.computeFixes(e2Text, {}, e2Meta);
check('E10 RSlot backfill is idempotent',     #e2Rep2.fixed, 0);
check('E11 the backfill is reported',
    e2Rep.fixed[1] ~= nil and e2Rep.fixed[1]:find('RSlot', 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- F. setmanager shim analysis -- COMMENTED-OUT handlers ("-- profile.HandleX =
--    function()") are dead code: they must read as 'missing' (Setup creates
--    them), not 'unparsable' (Setup gave up with "no changes needed" while the
--    banner stayed red). Field case: Mindie's BLU.lua / COR.lua.
-- ---------------------------------------------------------------------------
local setmgr = dofile('gear/setmanager.lua');
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
local optim = dofile('gear/gearoptim.lua');
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
-- H9-H14. Range/Ammo are picked TOGETHER, never greedily per slot.
-- Field case (Henrik): Cinderstone / Morion Tathlum occupy the Ammo slot but can
-- be fired by nothing. The server adds the ammo's delay to ranged delay for TP
-- with no compatibility check (GetRangedWeaponDelay), so pairing one with a bow
-- silently costs its full 999. Ammo with no corresponding Range weapon -- unfirable,
-- Throwing (a Range weapon shadows it), or no owned weapon of its type -- must
-- leave Range EMPTY. Catalog AmmoType is the discriminator; absent = unfirable.
-- ---------------------------------------------------------------------------
do   -- scoped: the main chunk is near Lua's 200-local ceiling
local G = package.loaded['dlac\\gear'];
local function ammoSet(rangeTbl, ammoTbl)
    G.Range, G.Ammo = rangeTbl, ammoTbl;
    return optim.buildMaxStatSet('Accuracy', { job = 'WAR', level = 99 });
end
local function it(name, acc, extra)
    local e = { Name = name, Level = 1, Id = 0, Jobs = { 'All' }, Stats = { Accuracy = acc } };
    for k, v in pairs(extra or {}) do e[k] = v; end
    return e;
end
-- a bow that scores WELL and a stat stick that scores a little: greedy would take both
local bow   = it('Test Bow',    10, { Type = 'Archery' });
local arrow = it('Test Arrow',   1, { AmmoType = 'Archery' });
local stick = it('Cinderstone',  4);                              -- no AmmoType = unfirable

local r1 = ammoSet({ Archery = { bow } }, { stick = stick, arrow = arrow });
check('H9 bow keeps its matching ammo',      r1.slots.Ammo, 'Test Arrow');
check('H10 bow survives the pairing',        r1.slots.Range, 'Test Bow');

-- stat stick outscores the whole bow+arrow pair (4+10=14 vs 20) -> Range must empty out
local fatStick = it('Cinderstone', 20);
local r2 = ammoSet({ Archery = { bow } }, { stick = fatStick });
check('H11 unfirable ammo wins the pair',    r2.slots.Ammo, 'Cinderstone');
check('H12 ... and Range stays EMPTY',       r2.slots.Range, nil);

-- Throwing fires from the Ammo slot itself; any Range weapon shadows it
local shuriken = it('Test Shuriken', 20, { AmmoType = 'Throwing' });
local r3 = ammoSet({ Archery = { bow } }, { shuriken = shuriken });
check('H13 Throwing ammo empties Range',     r3.slots.Range, nil);

-- arrows whose bow is not owned: no corresponding Range weapon -> Range stays empty
local r4 = ammoSet({ Marksmanship = { it('Test Gun', 3, { Type = 'Marksmanship' }) } }, { arrow = it('Test Arrow', 20, { AmmoType = 'Archery' }) });
check('H14 ammo without its weapon empties Range', r4.slots.Range, nil);
G.Range, G.Ammo = nil, nil;
end

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
-- MS. staged battery movement (dispatch.mpStageRelease / mpStageEquip, engine
--     v76): at most ONE battery moves per dispatch. Release picks the SMALLEST
--     surplus (the big battery stays on longest; simultaneous releases were
--     the clamp bug -- N same-dispatch releases drop max MP by the SUM of
--     surpluses while each hold justified only its own). Equip picks the
--     BIGGEST gain. Both tie-break on the slot name so pairs() collection
--     order can never flip the pick.
-- ---------------------------------------------------------------------------
(function()
local relCands = { { slot = 'Body', surplus = 29 },
                   { slot = 'Ring1', surplus = 10 },
                   { slot = 'Head', surplus = 45 } };
check('MS1 release picks the smallest surplus', dispatchM.mpStageRelease(relCands).slot, 'Ring1');
check('MS2 release tie breaks on slot name',
    dispatchM.mpStageRelease({ { slot = 'Ring2', surplus = 10 }, { slot = 'Ring1', surplus = 10 } }).slot, 'Ring1');
check('MS3 single candidate wins',  dispatchM.mpStageRelease({ { slot = 'Neck', surplus = 5 } }).slot, 'Neck');
check('MS4 release empty -> none',  dispatchM.mpStageRelease({}), nil);
check('MS5 release nil-safe',       dispatchM.mpStageRelease(nil), nil);
local upCands = { { slot = 'Ring1', gain = 25 },
                  { slot = 'Body', gain = 50 },
                  { slot = 'Neck', gain = 5 } };
check('MS6 equip picks the biggest gain', dispatchM.mpStageEquip(upCands).slot, 'Body');
check('MS7 equip tie breaks on slot name',
    dispatchM.mpStageEquip({ { slot = 'Ear2', gain = 25 }, { slot = 'Ear1', gain = 25 } }).slot, 'Ear1');
check('MS8 equip nil-safe',         dispatchM.mpStageEquip(nil), nil);

-- v78 scope ruling: a battery whose RSlot reserves an OCCUPIED slot never
-- stages (it would shove the planned/worn piece off server-side) -- and
-- filtering it here keeps the one-per-dispatch stage from being starved by a
-- doomed biggest-gain pick.
local msOcc = function(ls) return ({ range = 'Rouser' })[ls]; end
local msRs  = function(n) return ({ Rimestone = 4 })[n]; end
local msKeep, msSkip = dispatchM.mpStageEligible(
    { { slot = 'Ammo', lslot = 'ammo', name = 'Rimestone', gain = 20 },
      { slot = 'Ring1', lslot = 'ring1', name = 'Astral Ring', gain = 15 } }, msOcc, msRs);
check('MS9 Range-reserving battery skipped when Range occupied', #msKeep, 1);
check('MS9b the survivor is the ring',           msKeep[1].name, 'Astral Ring');
check('MS9c skip reports the blocking slot',     msSkip[1].blocking, 'range');
check('MS10 free Range: the battery stages',
    #(dispatchM.mpStageEligible({ { slot = 'Ammo', lslot = 'ammo', name = 'Rimestone', gain = 20 } },
        function() return nil; end, msRs)), 1);
check('MS10b Range=remove counts as free',
    #(dispatchM.mpStageEligible({ { slot = 'Ammo', lslot = 'ammo', name = 'Rimestone', gain = 20 } },
        function(ls) return ({ range = 'remove' })[ls]; end, msRs)), 1);
check('MS10c nil-safe', dispatchM.mpStageEligible(nil, msOcc, msRs), nil);
end)();

-- ---------------------------------------------------------------------------
-- MPL. /dl plan v2 formatter (dispatch.mpPlanLines, engine v88) -- renders
--      the band context: rows in RELEASE order with off<=/on>= thresholds,
--      refresh tag, live state (ON worn / ON equipping / RELEASING / off /
--      holding); a missing context answers the self-heal hint.
-- ---------------------------------------------------------------------------
(function()
local mb = dofile('feature/mpbands.lua');
local bands = mb.build({
    { slot = 'feet', name = 'MP Boots', low = 5, high = 15 },
    { slot = 'body', name = 'Refresh Robe', low = 0, high = 30, refresh = true },
}, 1100, 15);
-- cur 1050: feet (off<=1075) is past its off threshold -> releasing/off;
-- body (refresh band: off<=1045, on>=1060 clamped) sits in its DEAD ZONE
-- -> holding.
local worn = function(sl) if sl == 'body' then return 'Refresh Robe'; end return nil; end
local mpCtx = {
    bands = bands, cur = 1050, total = 1100, tick = 15, resting = false,
    target = mb.target(bands, 1050, worn),
    hi = {}, mpMap = {},
};
local lines = dispatchM.mpPlanLines(mpCtx, worn);
check('MPL1 header carries cur/total/tick',
    string.find(lines[1], 'MP 1050 of 1100', 1, true) ~= nil
    and string.find(lines[1], 'tick 15', 1, true) ~= nil, true);
check('MPL2 release order: small diff row first',
    string.find(lines[2], '1. feet:', 1, true) ~= nil, true);
check('MPL2b refresh band sinks deep + tagged',
    string.find(lines[3], '2. body:', 1, true) ~= nil
    and string.find(lines[3], '[refresh]', 1, true) ~= nil, true);
check('MPL3 thresholds printed (worked example)',
    string.find(lines[2], 'off<=1075', 1, true) ~= nil
    and string.find(lines[2], 'on>=1085', 1, true) ~= nil, true);
check('MPL4 dead-zone worn battery reads holding',
    string.find(lines[3], 'holding', 1, true) ~= nil, true);
check('MPL5 dead-zone empty slot reads off',
    string.find(lines[2], '-- off', 1, true) ~= nil, true);
check('MPL6 no context -> self-heal hint',
    string.find(dispatchM.mpPlanLines(nil)[1], 'no battery data', 1, true) ~= nil, true);
end)();

-- ---------------------------------------------------------------------------
-- MPS. paired-slot veto (dispatch.mpPairSkip, engine v83) -- a battery worn
--      in the SIBLING ear/ring is the same physical item (equipping it here
--      would shuffle it across and leave a hole; field: Loquacious Earring
--      hopped ear2 -> ear1 on rest). Duplicates are exempt: the manifest
--      lists dup-owned items in BOTH paired ladders, so a sibling ladder
--      naming the item means a second copy exists.
-- ---------------------------------------------------------------------------
(function()
local sibLad = { { name = 'Outlaw\'s Earring', mp = 15, level = 60 },
                 { name = 'Morion Earring', mp = 4, level = 16 } };
check('MPS1 single copy worn in sibling -> veto',
    dispatchM.mpPairSkip('Loquac. Earring', 'Loquac. Earring', sibLad), true);
check('MPS2 case-insensitive match still vetoes',
    dispatchM.mpPairSkip('Loquac. Earring', 'loquac. earring', sibLad), true);
check('MPS3 dup-owned (sibling ladder lists it) -> allowed',
    dispatchM.mpPairSkip('Astral Ring', 'Astral Ring',
        { { name = 'Astral Ring', mp = 25, level = 10 } }), false);
check('MPS4 different item worn in sibling -> allowed',
    dispatchM.mpPairSkip('Loquac. Earring', 'Outlaw\'s Earring', sibLad), false);
check('MPS5 empty sibling slot -> allowed',
    dispatchM.mpPairSkip('Loquac. Earring', nil, sibLad), false);
check('MPS6 legacy single-entry sibling ladder shape',
    dispatchM.mpPairSkip('Astral Ring', 'Astral Ring',
        { name = 'Astral Ring', mp = 25, level = 10 }), false);
check('MPS7 nil ladder: worn in sibling still vetoes',
    dispatchM.mpPairSkip('Loquac. Earring', 'Loquac. Earring', nil), true);

-- MPS8+: THE shared battery resolver (dispatch.mpBestPick, engine v88) --
-- the engine, the band builder and /dl plan all pick through it, and it
-- applies the pair veto while walking the ladder (field: the plan once
-- advertised a +20 ear1 gain the engine would never equip).
local pBest = {
    ear1 = { { name = 'Loquac. Earring', mp = 30, level = 41 },
             { name = 'Curate\'s Earring', mp = 10, level = 21 } },
    ear2 = { { name = 'Outlaw\'s Earring', mp = 15, level = 60 } },
    ring1 = { { name = 'Astral Ring', mp = 25, level = 10 } },
    ring2 = { { name = 'Astral Ring', mp = 25, level = 10 } },
};
local pworn = function(l)
    if l == 'ear2' then return 'Loquac. Earring'; end
    if l == 'ring1' then return 'Astral Ring'; end
    return nil;
end
check('MPS8 pick falls past the vetoed rung',
    dispatchM.mpBestPick(pBest, 'ear1', 75, pworn).name, 'Curate\'s Earring');
check('MPS8b level gate still applies',
    dispatchM.mpBestPick(pBest, 'ear1', 20, pworn), nil);
-- ---------------------------------------------------------------------------
-- MR. max-MP reconciliation (dispatch.mpReconcileMax, engine v86): Ashita's
--     GetMPMax can go stale across gear/job churn (field: engine 975/1052 vs
--     bar 975/975 -- dead full-pool gate + early releases). The party MP%
--     (floored, same packet family as cur) pins true max in
--     [cur*100/(mpp+1), cur*100/mpp]; 100% pins it exactly.
-- ---------------------------------------------------------------------------
check('MR1 field pin: 100% pins max = cur', dispatchM.mpReconcileMax(975, 1052, 100), 975);
-- v87 LOW bias: below full GetMPMax is ignored outright -- an under-estimate
-- can only over-hold a battery, never dump it early (round 7's cascade).
check('MR2 below full: GetMPMax ignored, low edge wins', dispatchM.mpReconcileMax(975, 1000, 97), 995);
check('MR3 stale-high ignored the same way', dispatchM.mpReconcileMax(500, 1200, 50), 981);
check('MR4 stale-low ignored the same way',  dispatchM.mpReconcileMax(500, 700, 50), 981);
check('MR5 nil mpp: raw max unchanged',     dispatchM.mpReconcileMax(975, 1052, nil), 1052);
check('MR6 empty pool: raw max unchanged',  dispatchM.mpReconcileMax(0, 714, 0), 714);
check('MR7 nil max at 100% still pins',     dispatchM.mpReconcileMax(975, nil, 100), 975);
check('MR8 nil max mid-pool takes lo',      dispatchM.mpReconcileMax(500, nil, 50), 981);

-- MF. the exact full-pool signal (dispatch.mpPoolFull, v87): floored MP%
--     reads 100 ONLY at cur == max; cur >= max survives as the fallback when
--     the percent is unreadable (its stale-low false-full armed round 7).
check('MF1 100% = full',                    dispatchM.mpPoolFull(975, 975, 100), true);
check('MF2 99% never full (fresh battery)', dispatchM.mpPoolFull(975, 975, 99), false);
check('MF3 no percent: cur >= max fallback', dispatchM.mpPoolFull(975, 975, nil), true);
check('MF3b no percent, below max',         dispatchM.mpPoolFull(975, 1052, nil), false);
check('MF4 nil-safe',                       dispatchM.mpPoolFull(nil, nil, nil), false);

check('MPS8c dup-owned pick survives the veto',
    dispatchM.mpBestPick(pBest, 'ring2', 75, pworn).name, 'Astral Ring');
check('MPS8d nil-safe', dispatchM.mpBestPick(nil, 'ear1', 75, pworn), nil);

-- MSS. STICKY paired slots (dispatch.mpStickyPairs, engine v93): a battery
--      candidate whose piece the sibling ear/ring already claims -- in this
--      dispatch's PLAN or on the body -- never writes (field: Loquacious
--      bounced ear2 <-> ear1 between the set's plan and the band's ladder
--      home). Dup-owned items stay exempt (both paired ladders list them).
local claims = function(map) return function(ls) return map[ls]; end end
local kept, moved = dispatchM.mpStickyPairs(
    { { slot = 'Ear1', lslot = 'ear1', name = 'Loquac. Earring', gain = 20 },
      { slot = 'Neck', lslot = 'neck', name = 'Warloq\'s Locket', gain = 31 } },
    claims({ ear2 = 'Loquac. Earring' }), pBest);
check('MSS1 sibling-claimed piece never writes', #kept, 1);
check('MSS1b the survivor is the unpaired slot', kept[1].lslot, 'neck');
check('MSS1c the skip names the claim', moved[1].sib .. '/' .. moved[1].claimed,
    'ear2/Loquac. Earring');
check('MSS2 dup-owned pair still writes',
    #(dispatchM.mpStickyPairs(
        { { slot = 'Ring2', lslot = 'ring2', name = 'Astral Ring', gain = 25 } },
        claims({ ring1 = 'Astral Ring' }), pBest)), 1);
check('MSS3 unclaimed sibling: candidate passes',
    #(dispatchM.mpStickyPairs(
        { { slot = 'Ear1', lslot = 'ear1', name = 'Loquac. Earring', gain = 20 } },
        claims({ ear2 = 'Outlaw\'s Earring' }), pBest)), 1);
check('MSS4 nil-safe', #(dispatchM.mpStickyPairs(nil, nil, nil)), 0);
-- v94, the field hole: the sibling's PLAN names a different piece (the set
-- displacing the earring) while the WORN claim still holds it -- either
-- claim vetoes now; `plan or worn` used to shadow the worn signal.
check('MSS5 worn claim vetoes even when the plan differs',
    #(dispatchM.mpStickyPairs(
        { { slot = 'Ear1', lslot = 'ear1', name = 'Loquac. Earring', gain = 20 } },
        function(ls)
            if ls == 'ear2' then return 'Outlaw\'s Earring', 'Loquac. Earring'; end
        end, pBest)), 0);
end)();

-- ---------------------------------------------------------------------------
-- MB. the banded-ladder core (feature/mpbands.lua, maxmp v2 -- Henrik's
--     2026-07-21 design). Thresholds are precomputed absolute current-MP
--     numbers; current MP is the ONLY live input. MB1/MB5/MB6 pin Henrik's
--     worked example VERBATIM: total 1100, feet low 5 / high 15 (diff 10),
--     tick 15 -> unequip at 1075, re-equip at 1085.
-- ---------------------------------------------------------------------------
(function()
local mb = dofile('feature/mpbands.lua');
package.loaded['dlac\\feature\\mpbands'] = mb;

local ex = mb.build({ { slot = 'feet', name = 'MP Boots', low = 5, high = 15 } }, 1100, 15);
check('MB1 worked example: one band',      #ex, 1);
check('MB1b lastMax = total',              ex[1].lastMax, 1100);
check('MB1c endMax = total - diff',        ex[1].endMax, 1090);
check('MB1d unequip trigger (Henrik: 1075)', ex[1].offAt, 1075);
check('MB1e re-equip trigger (Henrik: 1085)', ex[1].onAt, 1085);

local three = mb.build({
    { slot = 'neck', name = 'Locket', low = 0, high = 45 },
    { slot = 'feet', name = 'Boots',  low = 5, high = 15 },
    { slot = 'ring', name = 'Ring',   low = 0, high = 25 },
}, 1100, 15);
check('MB2 smallest diff first',   three[1].slot .. '>' .. three[2].slot .. '>' .. three[3].slot, 'feet>ring>neck');
check('MB2b bands chain: lastMax', three[2].lastMax, 1090);
check('MB2c bands chain: deepest', three[3].endMax, 1020);
check('MB3 non-positive diff gets no band',
    #(mb.build({ { slot = 'body', low = 50, high = 50 }, { slot = 'head', low = 30, high = 20 } }, 1100, 15)), 0);
check('MB3b nil-safe build', #(mb.build(nil, nil, nil)), 0);

local wearing = function(name) return function() return name; end end
check('MB4 above onAt: the rung belongs on', mb.target(ex, 1085, wearing(nil)).feet, 'MP Boots');
check('MB5 at/below offAt: set piece belongs on', mb.target(ex, 1075, wearing('MP Boots')).feet, false);
check('MB6 dead zone keeps worn rung',  mb.target(ex, 1080, wearing('MP Boots')).feet, 'MP Boots');
check('MB6b dead zone keeps empty slot empty', mb.target(ex, 1080, wearing(nil)).feet, false);
check('MB7 unreadable cur keeps state', mb.target(ex, nil, wearing('MP Boots')).feet, 'MP Boots');
local plunge = mb.target(three, 900, wearing('x'));   -- big spell: BATCH release
check('MB8 batch release on a big drop', tostring(plunge.feet) .. ',' .. tostring(plunge.ring) .. ',' .. tostring(plunge.neck),
    'false,false,false');
local surge = mb.target(three, 1100, wearing(nil));  -- Sublimation pop: BATCH equip
check('MB8b batch equip on a big rise', tostring(surge.feet) .. ',' .. tostring(surge.ring) .. ',' .. tostring(surge.neck),
    'Boots,Ring,Locket');

mb.reset();
check('MB9 unmeasured tick = default', mb.tick(false), mb.DEFAULT_TICK);
mb.observe(900, false); mb.observe(912, false); mb.observe(912, false); mb.observe(927, false); mb.observe(939, false);
check('MB10 standing tick = median of rises', mb.tick(false), 12);
mb.observe(600, false);            -- a spell DROP is not a tick
mb.observe(1000, false);           -- a +400 zone/item jump is not a tick
check('MB10b drops and jumps ignored', mb.tick(false), 12);
mb.observe(500, true); mb.observe(535, true);
check('MB11 resting bucket separate', mb.tick(true), 35);
mb.reset();
mb.observe(900, false); mb.observe(910, false);
check('MB11b resting falls back to standing measure', mb.tick(true), 10);
mb.reset();
mb.observe(900, false); mb.observe(901, false); mb.observe(902, false);
check('MB11c margin floors at MIN_TICK (unbuffed +1 ticks are real but tiny)',
    mb.tick(false), mb.MIN_TICK);

-- MB12: the SIGNED refresh delta ("mp recovery is key", engine v89). Field
-- pin: Bunzi's Robe (flat 50 MP) over Cleric's Bliaut +1 (Refresh 2 with
-- augments) = rfDelta -2 -> that band floats SHALLOWEST (first out, last
-- back) even with the biggest diff, so the refresh piece stays worn through
-- the spend; a refresh-GAIN battery still sinks deepest.
local signed = mb.build({
    { slot = 'body', name = 'Bunzi\'s Robe',  low = 29, high = 50, rfDelta = -2 },
    { slot = 'feet', name = 'Boots',          low = 5,  high = 15 },
    { slot = 'neck', name = 'Refresh Torque', low = 0,  high = 10, rfDelta = 1 },
}, 1100, 15);
check('MB12 refresh-cost floats shallowest',  signed[1].slot, 'body');
check('MB12b plain diff order in the middle', signed[2].slot, 'feet');
check('MB12c refresh-gain sinks deepest',     signed[3].slot, 'neck');
check('MB12d legacy refresh=true alias sinks deep',
    mb.build({ { slot = 'a', low = 0, high = 10, refresh = true },
               { slot = 'b', low = 0, high = 5 } }, 100, 0)[2].slot, 'a');

-- MB13: ONE band per slot, the round-10 RULING: "to get refresh in is NOT
-- YOUR JOB -- that is the idle set's job... you should be aware there is a
-- potential refresh piece there and adapt accordingly." The engine's band
-- = the top battery (augs counted: Hlr. Bliaut +1 at 35+18=53 tops body)
-- vs the POTENCY POINT = the idle's own piece (Clr. Bliaut +1 rf2 body,
-- Bunzi's Hat rf1 head). Awareness = ordering only: the refresh-cost
-- bands float shallowest, so the idle's refresh pieces are back FIRST
-- (body then head) and displaced LAST.
local multi = mb.build({
    { slot = 'head', low = 25, lowRf = 1,   -- idle wears Bunzi's Hat (its job, not ours)
      rungs = { { name = 'Erudite Cap', mp = 30, rf = 0 },
                { name = 'Bunzi\'s Hat', mp = 25, rf = 1 } } },
    { slot = 'body', low = 31, lowRf = 2,   -- idle wears Clr. Bliaut +1
      rungs = { { name = 'Hlr. Bliaut +1', mp = 53, rf = 0 },
                { name = 'Bunzi\'s Robe', mp = 50, rf = 0 } } },
    { slot = 'feet', low = 5, lowRf = 0,
      rungs = { { name = 'Boots', mp = 15, rf = 0 } } },
}, 1100, 15);
local order = {};
for _, b in ipairs(multi) do order[#order + 1] = b.name; end
check('MB13 one band per slot, refresh-cost shallowest', table.concat(order, '>'),
    'Hlr. Bliaut +1>Erudite Cap>Boots');
check('MB13b the engine never wears the refresh piece (no Hat/Clr band)',
    (function()
        for _, b in ipairs(multi) do
            if b.name == 'Bunzi\'s Hat' or b.name == 'Clr. Bliaut +1' then return 'worn by engine'; end
        end
        return 'idle set\'s job';
    end)(), 'idle set\'s job');
-- REACHABILITY (the round-10 field bug: "not switching away the refresh
-- pieces even at max MP"): body diff 22 > tick 15, so the raw on-trigger
-- (lastMax - tick = 1085) sits ABOVE the reachable pool (endMax 1078) --
-- clamped to endMax it fires the moment the pool genuinely tops out.
check('MB13c big-diff on-trigger clamps reachable', multi[1].onAt, multi[1].endMax);
check('MB13d small-diff keeps the early trigger (worked example intact)',
    mb.build({ { slot = 'feet', low = 5, lowRf = 0,
        rungs = { { name = 'MP Boots', mp = 15, rf = 0 } } } }, 1100, 15)[1].onAt, 1085);
-- At the top the battery displaces the refresh set piece; spending brings
-- the refresh piece back FIRST (body band shallowest).
local wornTop = function(sl)
    if sl == 'body' then return 'Hlr. Bliaut +1'; end
    if sl == 'head' then return 'Erudite Cap'; end
    return nil;
end
check('MB13e at the top: the battery belongs on',
    mb.target(multi, 1078, wornTop).body, 'Hlr. Bliaut +1');
check('MB13f spending: the battery off first -> the idle refresh piece returns',
    mb.target(multi, 1060, wornTop).body, false);
-- At equal MP the higher-Refresh copy wins the pick.
check('MB13g equal-MP pick prefers the refresh copy',
    mb.build({ { slot = 'x', low = 0, lowRf = 0,
        rungs = { { name = 'Flat', mp = 30, rf = 0 },
                  { name = 'Rf Copy', mp = 30, rf = 1 } } } }, 100, 0)[1].name, 'Rf Copy');
end)();

-- ---------------------------------------------------------------------------
-- L. THE central stats-at-level resolver (levelstats.effective), against the
--    REAL generated scaling data: Tamas Ring is MP 15 on paper, 29 at Lv74,
--    30 fully scaled (Lv75). Every section -- gearui display/scoring, gearoptim
--    ranking, the automation manifests -- resolves item stats through this one
--    function, so no section values a scaling item at its base stats.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\data\\levelscaling'] = dofile('data/levelscaling.lua');
local lstats = dofile('data/levelstats.lua');
local tamas = { Name = 'Tamas Ring', Id = 15545, Level = 30,
                Stats = { MP = 15, INT = 2, MND = 2, Enmity = -3 } };
check('L1 Tamas MP at Lv74',       lstats.effective(tamas, 74).MP, 29);
check('L2 Tamas MP fully scaled',  lstats.effective(tamas, 75).MP, 30);
check('L3 base table never mutated', tamas.Stats.MP, 15);
check('L4 non-scaling passthrough', lstats.effective({ Id = 13548, Stats = { ConvertHPtoMP = 25 } }, 74).ConvertHPtoMP, 25);
check('L5 nil level = base stats', lstats.effective(tamas, nil).MP, 15);
check('L6 nil-safe',               lstats.effective(nil, 74), nil);
-- thresholds = the band edges levelLadder re-scores at (real generated data:
-- Garrison Tunica +1 changes once at 51; 13680 ramps DEF at every decade)
check('L7 thresholds: Garrison Tunica +1', table.concat(lstats.thresholds(26543), ','), '51');
check('L8 thresholds: DEF ramp item',      table.concat(lstats.thresholds(13680), ','), '30,40,50,60,70,80,90');
check('L9 thresholds: non-scaling = {}',   #lstats.thresholds(13548), 0);

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
-- VL. a virtual marker is a ladder RUNG at the level of the lowest item it can
--     resolve to (dispatch.virtualMinLevel; Henrik 2026-07-17: AutoIridescence
--     counted as Lv0 on a leveling WHM and shadowed the Pilgrim's Wand actually
--     worn -- with Chatoyant Staff as best owned it must read Lv51). Below that
--     level the flatten SKIPS the marker and the real best-by-level item owns
--     the slot; at/above it the marker|fallback composite returns. No manifest
--     answer (legacy boolean shape, craft family) -> nil -> old always-adopt.
-- ---------------------------------------------------------------------------
do
    dispatchM._autoOverride = {
        universal = { name = 'Chatoyant Staff', tier = 2, level = 51 },
        staff = { Fire = { name = 'Vulcans Staff', tier = 1, level = 51 } },
        obi = { Fire = { name = 'Karin Obi', level = 71 } },
    };
    check('VL1 staff marker min level',   dispatchM.virtualMinLevel('dlac:AutoIridescence'), 51);
    check('VL2 composite form tolerated', dispatchM.virtualMinLevel('dlac:AutoStaff|Pilgrims Wand'), 51);
    check('VL3 obi marker min level',     dispatchM.virtualMinLevel('dlac:AutoObi'), 71);
    check('VL4 craft marker: no answer',  dispatchM.virtualMinLevel('dlac:AutoCraft'), nil);

    local wand = { Name = 'Pilgrims Wand', Level = 7, OneHanded = true, Type = 'Club' };
    local function whmWeapon()
        return { Dynamic = { W = { Main = { 'dlac:AutoIridescence', wand } } } };
    end
    TEST_PLAYER = { MainJob = 'WHM', SubJob = 'BLM', MainJobSync = 40, SubJobSync = 20 };
    local sVL = utils.BuildDynamicSets(whmWeapon());
    check('VL5 below the rung: real item owns the slot', sVL.W and sVL.W.Main, 'Pilgrims Wand');
    TEST_PLAYER = { MainJob = 'WHM', SubJob = 'BLM', MainJobSync = 51, SubJobSync = 25 };
    sVL = utils.BuildDynamicSets(whmWeapon());
    check('VL6 at the rung: marker with fallback', sVL.W and sVL.W.Main, 'dlac:AutoIridescence|Pilgrims Wand');
    dispatchM._autoOverride = { iridescence = true };   -- legacy boolean manifest: no level info
    TEST_PLAYER = { MainJob = 'WHM', SubJob = 'BLM', MainJobSync = 40, SubJobSync = 20 };
    sVL = utils.BuildDynamicSets(whmWeapon());
    check('VL7 legacy manifest: old always-adopt behavior', sVL.W and sVL.W.Main, 'dlac:AutoIridescence|Pilgrims Wand');

    -- v82: the universals LADDER (manifest fmt 10). Preference-ordered by the
    -- GUI (tier desc, job-specific first); the engine takes the FIRST rung
    -- usable at the live level -- a level-synced character falls through a
    -- parked Inanna to Foreshadow +1 instead of losing the universal outright.
    -- virtualMinLevel answers the LOWEST rung: the marker adopts as early as
    -- the earliest universal, not only the top pick.
    local ladder = {
        { name = 'Inanna',        tier = 3, level = 75 },
        { name = 'Foreshadow +1', tier = 2, level = 50 },
    };
    dispatchM._autoOverride = { universals = ladder };
    check('VL8 ladder min level = lowest rung', dispatchM.virtualMinLevel('dlac:AutoIridescence'), 50);
    dispatchM._autoOverride = { universals = ladder,
        staff = { Fire = { name = 'Vulcans Staff', tier = 2, level = 40 } },
    };
    local function rs(lvl, el)
        return dispatchM._resolveVirtual('dlac:AutoStaff',
            { player = { MainJobSync = lvl }, action = (el ~= nil) and { Element = el } or nil });
    end
    check('VL9 top rung at level',                    rs(75), 'Inanna');
    check('VL10 synced under the top rung: falls through', rs(60), 'Foreshadow +1');
    check('VL11 tier tie vs elemental goes universal', rs(60, 'Fire'), 'Foreshadow +1');
    check('VL12 under every rung: elemental owns the cast', rs(45, 'Fire'), 'Vulcans Staff');
    check('VL13 under everything: no resolution',      rs(30, 'Fire'), nil);
    dispatchM._autoOverride = nil;
end

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
package.loaded['dlac\\data\\crafts'] = {
    ['4096:1165,1165'] = { skill = 'Alchemy', lv = 60 },
    ['4096:640,650']   = { skill = 'Smithing', lv = 10, desynth = true },
};
-- auto-equip deps, stubbed: a profile with a Craft_Alchemy set + a recording cmdqueue
local craftCmds = {};
package.loaded['dlac\\lib\\cmdqueue'] = {
    enqueue = function(delay, cmd) craftCmds[#craftCmds + 1] = cmd; end,
    frame = function() return 0; end, tick = function() end,
};
package.loaded['dlac\\gear\\profilesets'] = {
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
local craftwatch = dofile('feature/craftwatch.lua');

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
    .. i32(1111)      -- 0x20 fishing (parsed since the fishing system -- F-tests assert it)
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
local setmgrT = dofile('gear/setmanager.lua');
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

-- the starter sets scaffold (fresh Setup + a migration that found no Dynamic
-- block): frames, parses, and holds exactly the four EMPTY base sets the
-- starter triggers target -- a new job never complains out of the box.
do
    local sframed = profilesM.frameSetsText(profilesM.starterDynText);
    local schunk = loadWithEnv(sframed, setmetatable({ gear = STUBG }, { __index = _G }));
    local sok2, ssets = pcall(schunk);
    check('Y25b starter sets scaffold parses', sok2 and type(ssets) == 'table' and type(ssets.Dynamic) == 'table', true);
    check('Y25c scaffold = the four base sets, empty', sok2
        and type(ssets.Dynamic.Idle) == 'table' and next(ssets.Dynamic.Idle) == nil
        and type(ssets.Dynamic.Tp_Default) == 'table' and type(ssets.Dynamic.Resting) == 'table'
        and type(ssets.Dynamic.Movement) == 'table', true);
end

-- the migration planner (pure): ONLY a clean shim is ever skipped (THE SETUP
-- STANDARD, 2026-07-17 -- a file with logic in it never stays live), Dynamic
-- blocks travel verbatim, an existing profile sets file is never overwritten
-- by an import, and a first backup is never overwritten (reshim = stamped copy).
local plan = profilesM.planMigration({
    { job = 'WAR', text = JOBFILE, hasBackup = false, hasProfileSets = false, hasLegacyTrig = true,  hasProfileTrig = false },
    { job = 'WHM', text = profilesM.shimFileText(), hasBackup = false, hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'BLM', text = JOBFILE, hasBackup = true,  hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'RDM', text = 'local x = 1; return x;', hasBackup = false, hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'THF', text = JOBFILE, hasBackup = false, hasProfileSets = true,  hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'PLD', text = profilesM.shimFileText(), hasBackup = true, hasProfileSets = true, hasLegacyTrig = false, hasProfileTrig = false },
});
check('Y26 plan: real profile migrates', plan[1].action, 'migrate');
check('Y27 plan: Dynamic block travels verbatim', plan[1].dynText, dynText);
check('Y28 plan: clean shim skipped', plan[2].action, 'skip');
check('Y29 STANDARD: backed-up file with logic in it is re-shimmed, not skipped',
      plan[3].action == 'migrate' and plan[3].reshim == true, true);
check('Y30 plan: no Dynamic block -> empty store, still migrates', plan[4].action == 'migrate' and plan[4].dynText == nil, true);
check('Y31 plan: existing profile sets file is never re-imported over', plan[5].action == 'migrate' and plan[5].dynText == nil, true);
check('Y31b plan: a shim with a backup is left alone (nothing to do)', plan[6].action, 'skip');
-- SETUP HARD RULE: whatever the flag combination, a file whose text is NOT the
-- clean shim always migrates -- no input may leave old logic live. (The skip
-- for a clean shim is equally load-bearing: migration must be idempotent.)
do
    local inputs = {};
    local texts = { JOBFILE, 'return {};', profilesM.shimFileText() };
    for t = 1, #texts do for a = 0, 1 do for b = 0, 1 do for c = 0, 1 do for d = 0, 1 do
        inputs[#inputs + 1] = { job = 'J' .. #inputs, text = texts[t],
            hasBackup = a == 1, hasProfileSets = b == 1, hasLegacyTrig = c == 1, hasProfileTrig = d == 1 };
    end end end end end
    local p2 = profilesM.planMigration(inputs);
    local rule = true;
    for i, f in ipairs(inputs) do
        local want = profilesM.isCleanShim(f.text) and 'skip' or 'migrate';
        if p2[i].action ~= want then rule = false; end
    end
    check('Y31c SETUP HARD RULE: every non-shim file migrates; every clean shim skips (48 combos)', rule, true);
end

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

-- lockstyle path resolution (v41, per-job-entry boxes): headless = pre-login,
-- every path is nil and the read resolver answers nil instead of erroring.
check('Y52 headless: lockstylesPath is nil pre-login', profilesM.lockstylesPath('DRK'), nil);
check('Y53 headless: legacy lockstyle tiers are nil pre-login',
      profilesM.profileLockstylesPath() == nil and profilesM.legacyLockstylesPath() == nil, true);
check('Y54 headless: readLockstylesPath is nil, never an error', profilesM.readLockstylesPath('DRK'), nil);

-- v45: the profile auto-install (LAC tick) must not LATCH before it can tell
-- whether a job has a sets file, or a login-time miss is permanent for the whole
-- session (field case 07-15: WHM logged in with an empty .Dynamic, every trigger
-- silently equipping nothing). setsPath == nil pre-login IS that "can't tell yet"
-- signal, and hasSetsFile MUST answer false rather than throw -- if either ever
-- changes, the guard silently reverts to latching on an unanswered question.
check('Y55 headless: setsPath is nil pre-login (the auto-install retry signal)',
      profilesM.setsPath('WHM'), nil);
check('Y56 headless: hasSetsFile is false pre-login, never an error',
      profilesM.hasSetsFile('WHM'), false);

-- v49: "NON" is not a job. THE login bug (field-caught 07-15, /dl instdiag showed
-- `latches=tick 1: job=NON hasSets=false`): at login GetMainJob() reads 0 = None,
-- which gData stringifies via jobs.names_abbr to "NON" -- neither '' nor '?', so a
-- guard checking only those accepted it, found no sets\NON.lua, installed nothing
-- and latched for the whole session. If jobReady ever accepts NON or a 0 id again,
-- every migrated character silently plays with an empty .Dynamic.
check('Z1 jobReady rejects job id 0 (None -- player block not ready at login)',
      dispatchM.jobReady(0, 'NON'), false);
check('Z2 jobReady rejects the "NON" STRING even if an id came through',
      dispatchM.jobReady(1, 'NON'), false);
check('Z3 jobReady rejects nil id', dispatchM.jobReady(nil, 'SAM'), false);
check('Z4 jobReady rejects empty / unknown job names',
      dispatchM.jobReady(12, '') == false and dispatchM.jobReady(12, '?') == false, true);
check('Z5 jobReady rejects a nil name (gData not ready)', dispatchM.jobReady(12, nil), false);
check('Z6 jobReady ACCEPTS a real settled job', dispatchM.jobReady(12, 'SAM'), true);
check('Z7 jobReady accepts WAR (id 1) -- a real job, not the None sentinel',
      dispatchM.jobReady(1, 'WAR'), true);

-- job export carries the lockstyles payload (optional, still "job-export v1":
-- readers that predate the field ignore it; any single payload is a valid file).
do
    local lsBlob = 'return { active = 1, onload = {}, slots = {} };';
    local ex2 = profilesM.buildExportText('DRK', 'Default', 'Mindie', nil, nil, lsBlob);
    local meta2, perr2 = profilesM.parseExportText(ex2);
    check('Y55 lockstyles-only export is valid', perr2, nil);
    check('Y56 lockstyles payload round-trips verbatim', meta2 ~= nil and meta2.lockstyles, lsBlob);
end

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
local gx = dofile('gear/gearexport.lua');
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
--     its weights; a never-bound set starts BLANK; the SHARED (no-set) table
--     is a DEAD CONCEPT (Henrik 2026-07-17: "we start blank, have weights per
--     set and can save -- delete it"): unbound reads are empty, unbound edits
--     are refused, nothing unbound persists. Switching sets never carries
--     another set's edits along (Henrik's isolation rule). Headless:
--     weightsPath() is nil, so persistence no-ops here.
-- ---------------------------------------------------------------------------
check('AE1 unbound edit refused (the shared table is gone)', optim.setWeight('Accuracy', 20, 60), false);
check('AE2 nothing bound yet', optim.weightsBoundTo(), nil);
check('AE2b unbound weights read empty', next(optim.getWeights()), nil);
check('AE3 first bind reports a change', optim.bindSetWeights('DRK', 'Midshort'), true);
check('AE4 first bind starts BLANK', optim.getWeights()['Accuracy'], nil);
check('AE4b bound edits are accepted', optim.setWeight('STR', 5), true);
optim.setWeight('Accuracy', 99);
check('AE5 rebind of the same key is a no-op', optim.bindSetWeights('DRK', 'Midshort'), false);
optim.bindSetWeights('DRK', 'Tp_Default');
check('AE6 second set starts BLANK too (not the last-used set)', optim.getWeights()['Accuracy'], nil);
check('AE7 second set did not inherit the STR edit', optim.getWeights()['STR'], nil);
optim.bindSetWeights('DRK', 'Midshort');
check('AE8 re-selecting a set gets its own edits back', optim.getWeights()['Accuracy'].perUnit, 99);
check('AE9 ...including added stats', optim.getWeights()['STR'].perUnit, 5);
check('AE10 unbinding empties the active view', (optim.bindSetWeights(nil, nil) == true)
    and next(optim.getWeights()), nil);
check('AE11 ...and refuses edits again', optim.setWeight('VIT', 1), false);
check('AE12 pre-login job "?" never creates a binding', optim.bindSetWeights('?', 'AnySet'), false);
check('AE13 ...and stays unbound', optim.weightsBoundTo(), nil);
optim.bindSetWeights('DRK', 'Midshort');
check('AE14 score() follows the binding', optim.score({ Accuracy = 1 }), 99);
optim.bindSetWeights(nil, nil);
check('AE15 unbound score() is 0 (nothing is weighted)', optim.score({ Accuracy = 1 }), 0);

-- ---------------------------------------------------------------------------
-- AS. per-set build-slot mask (the weights window's 4x4 grid): which slots
--     Auto-build FILLS. Same per-set binding + gearweights.lua persistence as
--     the weights; a never-bound set starts from the FIXED default (weapons
--     unmarked -- the old Skip-weapons ON state); unbound the mask READS as
--     that default and refuses edits (no shared mask anymore).
-- ---------------------------------------------------------------------------
(function()
    optim.bindSetWeights(nil, nil);
    local dm = optim.getSlotMask();
    check('AS1 default: Main unmarked',  dm.Main,  nil);
    check('AS2 default: Sub unmarked',   dm.Sub,   nil);
    check('AS3 default: Range unmarked', dm.Range, nil);
    check('AS4 default: Ammo MARKED (ammo trinkets are real picks)', dm.Ammo, true);
    check('AS5 default: all 12 armor slots marked', (dm.Head and dm.Neck and dm.Ear1
        and dm.Ear2 and dm.Body and dm.Hands and dm.Ring1 and dm.Ring2 and dm.Back
        and dm.Waist and dm.Legs and dm.Feet) == true, true);
    check('AS6 unknown label rejected', (optim.setSlotEnabled('Helmet', true)), false);
    check('AS7 unbound mark edit refused (no shared mask)', optim.setSlotEnabled('Main', true), false);
    optim.bindSetWeights('DRK', 'GridSet');
    check('AS8 first bind starts from the DEFAULT mask', optim.getSlotMask().Main, nil);
    optim.setSlotEnabled('Main', true);
    optim.setSlotEnabled('Head', false);
    check('AS9 set edit sticks to the set', optim.getSlotMask().Head, nil);
    optim.bindSetWeights(nil, nil);
    check('AS10 unbound view is back on the pristine default', optim.getSlotMask().Head, true);
    check('AS11 ...Main included', optim.getSlotMask().Main, nil);
    optim.bindSetWeights('DRK', 'GridSet');
    check('AS12 re-selecting the set gets its marks back', optim.getSlotMask().Main, true);

    -- Round-trip through a real file (weightsPath overridden; headless it's nil).
    local _wp = optim.weightsPath;
    local _tmp = 'tests_tmp_gearweights.lua';
    optim.weightsPath = function() return _tmp; end
    optim.setWeight('Accuracy', 11);                        -- a bound edit rides along
    check('AS13 save writes the masks', optim.saveWeights(), true);
    optim.setSlotEnabled('Main', false);                    -- diverge memory from disk
    optim.setSlotEnabled('Head', true);
    check('AS14 load restores the per-set mask', (optim.loadWeights() == true)
        and optim.getSlotMask().Main, true);
    check('AS15 ...every saved mark', optim.getSlotMask().Head, nil);
    check('AS16 ...and the weights beside it', optim.getWeights()['Accuracy'].perUnit, 11);
    -- Legacy FLAT file: it was ONLY the dead shared table -- loads clean,
    -- contributes nothing.
    local f = io.open(_tmp, 'w');
    f:write('return { ["Accuracy"] = { perUnit = 7 } }\n');
    f:close();
    check('AS17 legacy flat file loads clean', optim.loadWeights(), true);
    check('AS18 legacy: dead shared content is DROPPED', optim.getWeights()['Accuracy'], nil);
    check('AS19 legacy: mask falls back to the default', optim.getSlotMask().Main, nil);
    check('AS20 legacy: ...armor still marked', optim.getSlotMask().Body, true);
    -- An old STRUCTURED file: its shared/slotsShared sections are ignored, the
    -- per-set payload survives.
    f = io.open(_tmp, 'w');
    f:write('return { shared = { ["Evasion"] = { perUnit = 9 } }, slotsShared = { "Main" },'
        .. ' perSet = { ["DRK|GridSet"] = { ["STR"] = { perUnit = 2 } } } }\n');
    f:close();
    check('AS21 old structured file loads clean', optim.loadWeights(), true);
    check('AS22 ...its per-set weights survive', optim.getWeights()['STR'].perUnit, 2);
    check('AS23 ...its shared section is dropped', optim.getWeights()['Evasion'], nil);
    os.remove(_tmp);
    optim.weightsPath = _wp;
    optim.bindSetWeights(nil, nil);
end)();

-- ---------------------------------------------------------------------------
-- AW. weights "copy from" (optim.copyWeightsFrom): copy another stored table's
--     weights + build-slot mask into the ACTIVE binding. Source untouched;
--     active-table identity preserved (they alias _shared/_perSet entries).
-- ---------------------------------------------------------------------------
(function()
    optim.bindSetWeights('DRK', 'CopySrc');
    optim.setWeight('Accuracy', 42, 60);
    optim.setSlotEnabled('Main', true);
    optim.bindSetWeights('DRK', 'CopyDst');
    optim.setWeight('STR', 3);
    check('AW1 dst starts with its own table',  optim.getWeights()['Accuracy'], nil);
    check('AW2 copy succeeds',                  optim.copyWeightsFrom('DRK|CopySrc'), true);
    check('AW3 weights copied',                 optim.getWeights()['Accuracy'].perUnit, 42);
    check('AW4 cap rides along',                optim.getWeights()['Accuracy'].cap, 60);
    check('AW5 dst extras cleared',             optim.getWeights()['STR'], nil);
    check('AW6 slot mask copied',               optim.getSlotMask().Main, true);
    optim.setWeight('Accuracy', 1);                          -- edit the COPY only
    optim.bindSetWeights('DRK', 'CopySrc');
    check('AW7 source untouched',               optim.getWeights()['Accuracy'].perUnit, 42);
    check('AW8 self-copy refused',              optim.copyWeightsFrom('DRK|CopySrc'), false);
    check('AW9 unknown source refused',         optim.copyWeightsFrom('DRK|NoSuch'), false);
    check('AW10 the dead shared source is refused', optim.copyWeightsFrom(nil), false);
    optim.bindSetWeights(nil, nil);
    check('AW11 unbound copy refused (nothing to copy into)', optim.copyWeightsFrom('DRK|CopySrc'), false);
end)();

-- ---------------------------------------------------------------------------
-- AWN. named weight profiles ("Saved Sets") + the copy-undo snapshot -- the
--      cascading copy-from menu's backend: save a tuning under a proper name,
--      copy it anywhere, revert a binding to its pre-first-copy state, and
--      round-trip the named store through gearweights.lua.
-- ---------------------------------------------------------------------------
(function()
    optim.bindSetWeights('DRK', 'CopySrc');
    check('AWN1 save named trims + succeeds', (optim.saveNamedWeights('  Awesome Melee  ')), true);
    check('AWN2 named key listed', optim.namedKeys()[1], 'Awesome Melee');
    optim.bindSetWeights('DRK', 'CopyDst');
    check('AWN3 copy from named', optim.copyWeightsFromNamed('Awesome Melee'), true);
    check('AWN4 named weights land', optim.getWeights()['Accuracy'].perUnit, 42);
    check('AWN5 named mask lands', optim.getSlotMask().Main, true);
    check('AWN6 revert restores the PRE-FIRST-COPY table',
        (optim.revertCopiedWeights() == true) and (optim.getWeights()['STR'] or {}).perUnit, 3);
    check('AWN7 unknown named refused', optim.copyWeightsFromNamed('NoSuch'), false);
    local _wp = optim.weightsPath;
    local _tmp = 'tests_tmp_gearweights2.lua';
    optim.weightsPath = function() return _tmp; end
    optim.saveWeights();
    optim.deleteNamedWeights('Awesome Melee');
    check('AWN8 delete named', #optim.namedKeys(), 0);
    check('AWN9 load restores named', (optim.loadWeights() == true) and optim.namedKeys()[1], 'Awesome Melee');
    check('AWN10 ...with its weights', optim.peekWeights('named', 'Awesome Melee')['Accuracy'].perUnit, 42);
    os.remove(_tmp);
    optim.weightsPath = _wp;
    optim.deleteNamedWeights('Awesome Melee');               -- leave the store clean
    optim.bindSetWeights(nil, nil);
end)();

-- ---------------------------------------------------------------------------
-- AP. priority-list mode (the "simple" weights, 2026-07-17) -- an ORDERED
--     stat list with optional caps. Scoring derives dominance weights (one
--     point of a higher stat outranks everything below it combined), so the
--     whole existing pipeline -- score, optimizePicks, Auto-build -- runs
--     unchanged. Own per-set + named stores (never mixes with point
--     templates); the MODE flips to whichever editor's data you mutate.
-- ---------------------------------------------------------------------------
(function()
    -- unbound: priority reads empty and refuses edits (no shared list)
    optim.bindSetWeights(nil, nil);
    check('AP1 unbound mode reads points', optim.weightsMode(), 'points');
    check('AP2 unbound prio list reads empty', #optim.getPrio(), 0);
    check('AP2b unbound prio edit refused', optim.prioAdd('Accuracy', 10), false);
    check('AP2c unbound mode set refused', optim.setWeightsMode('priority'), false);

    -- mode + derivation basics, on a bound set
    optim.bindSetWeights('DRK', 'PrioMain');
    check('AP3 add flips the mode', (optim.prioAdd('Accuracy', 10) == true) and optim.weightsMode(), 'priority');
    optim.prioAdd('STR');
    check('AP4 dup add refused', optim.prioAdd('Accuracy'), false);
    check('AP5 getWeights is now the DERIVED table', optim.getWeights()['STR'].perUnit, 1);
    check('AP6 higher rank dominates: 1 Accuracy beats 400 STR',
        optim.score({ Accuracy = 1 }) > optim.score({ STR = 400 }), true);
    check('AP7 the cap clamps per item', optim.score({ Accuracy = 50 }), optim.score({ Accuracy = 10 }));
    check('AP8 a points edit flips the mode back', (optim.setWeight('VIT', 2) == true) and optim.weightsMode(), 'points');
    check('AP9 ...and scoring follows', optim.score({ VIT = 1 }), 2);
    optim.clearWeight('VIT');
    optim.setWeightsMode('priority');
    check('AP10 explicit mode set works', optim.weightsMode(), 'priority');

    -- reorder + caps + remove
    optim.prioMove(2, -1);                 -- STR above Accuracy now
    check('AP11 move reorders', optim.getPrio()[1].stat, 'STR');
    check('AP12 dominance follows the order', optim.score({ STR = 1 }) > optim.score({ Accuracy = 10 }), true);
    optim.prioSetCap(1, 30);
    check('AP13 cap edit lands', optim.getPrio()[1].cap, 30);
    optim.prioSetCap(1, 0);
    check('AP14 cap 0 clears it', optim.getPrio()[1].cap, nil);
    check('AP15 remove drops the row', (optim.prioRemove(1) == true) and optim.getPrio()[1].stat, 'Accuracy');

    -- per-set isolation + blank seeding (the same rules the weights follow)
    optim.bindSetWeights('DRK', 'PrioSet');
    check('AP16 new binding starts with a blank list', #optim.getPrio(), 0);
    check('AP17 ...and points mode', optim.weightsMode(), 'points');
    optim.prioAdd('Evasion');
    optim.bindSetWeights('DRK', 'PrioMain');
    check('AP18 first set\'s list untouched by the other\'s edits', optim.getPrio()[1].stat, 'Accuracy');
    check('AP19 ...and keeps its own mode', optim.weightsMode(), 'priority');
    optim.bindSetWeights('DRK', 'PrioSet');
    check('AP20 re-selecting the set gets its list back', optim.getPrio()[1].stat, 'Evasion');
    check('AP21 ...and its mode', optim.weightsMode(), 'priority');

    -- named store ("Saved Lists") + copy + revert; separate from point saves
    check('AP22 save named list trims + succeeds', (optim.savePrioNamed('  Heal Prio  ')), true);
    check('AP23 named key listed', optim.prioNamedKeys()[1], 'Heal Prio');
    check('AP24 prio saves never appear among point templates', #optim.namedKeys(), 0);
    optim.bindSetWeights('DRK', 'PrioDst');
    optim.prioAdd('MND');
    check('AP25 copy from named replaces the list', (optim.copyPrioFromNamed('Heal Prio') == true)
        and optim.getPrio()[1].stat, 'Evasion');
    check('AP26 revert restores the pre-copy list', (optim.revertCopiedPrio() == true)
        and optim.getPrio()[1].stat, 'MND');
    check('AP27 unknown named refused', optim.copyPrioFromNamed('NoSuch'), false);
    check('AP28 copy from a per-set list', (optim.copyPrioFrom('DRK|PrioSet') == true)
        and optim.getPrio()[1].stat, 'Evasion');
    check('AP29 self-copy refused', optim.copyPrioFrom('DRK|PrioDst'), false);

    -- clear (snapshots like a copy, so revert works after a mis-click)
    optim.bindSetWeights('DRK', 'PrioSet');
    check('AP30 clear empties the list', (optim.prioClear() == true) and #optim.getPrio(), 0);
    check('AP31 revert brings a cleared list back', (optim.revertCopiedPrio() == true)
        and optim.getPrio()[1].stat, 'Evasion');

    -- the joint optimizer follows priority mode (weights=nil resolves through it)
    local res = optim.optimizePicks({
        Head = {
            { stats = { STR = 400 },   ref = 'strhat' },
            { stats = { Evasion = 1 }, ref = 'evahat' },
        },
    }, nil, {});
    check('AP32 optimizePicks obeys the priority order', res.picks.Head, 2);

    -- persistence round-trip (all prio sections + modes)
    local _wp = optim.weightsPath;
    local _tmp = 'tests_tmp_gearweights3.lua';
    optim.weightsPath = function() return _tmp; end
    check('AP33 save writes the prio sections', optim.saveWeights(), true);
    optim.prioClear();                      -- diverge memory from disk
    optim.deletePrioNamed('Heal Prio');
    optim.setWeightsMode('points');
    check('AP34 load restores the per-set list', (optim.loadWeights() == true)
        and optim.getPrio()[1].stat, 'Evasion');
    check('AP35 ...the mode', optim.weightsMode(), 'priority');
    check('AP36 ...and the named store', optim.peekPrio('named', 'Heal Prio')[1].stat, 'Evasion');
    -- a pre-priority file (no prio/mode sections) loads as all-points, empty lists
    local f = io.open(_tmp, 'w');
    f:write('return { perSet = { ["DRK|PrioSet"] = { ["MND"] = { perUnit = 4 } } } }\n');
    f:close();
    check('AP37 pre-priority file: points mode', (optim.loadWeights() == true) and optim.weightsMode(), 'points');
    check('AP38 pre-priority file: empty prio list', #optim.getPrio(), 0);
    os.remove(_tmp);
    optim.weightsPath = _wp;

    optim.bindSetWeights(nil, nil);                          -- leave the module unbound
end)();

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
-- LK. slot locks -- what the Sets tab's "Equip & Lock" (/dl lock set) rests on:
--     setLock('all') flips every slot, and equipResolved strips locked slots,
--     so the engine leaves server-locked (Incursion T3) gear alone.
-- ---------------------------------------------------------------------------
check('LK1 lock all reports ON', dispatchM.setLock('all', true), true);
local lkN = 0;
for _ in pairs(dispatchM.locks) do lkN = lkN + 1; end
check('LK2 all 16 slots locked', lkN, 16);
local lkNote, lkTbl = dispatchM._equipResolved({ Main = 'Death Scythe', Body = 'Weaver Apron' }, {});
check('LK3 a locked slot is stripped (kept as worn)', lkTbl.Main, nil);
check('LK4 every locked slot is stripped', lkTbl.Body, nil);
check('LK5 the strip is traced for /dl why', string.find(lkNote, 'LOCKED', 1, true) ~= nil, true);
check('LK6 unknown slot names refuse', dispatchM.setLock('incursion'), nil);
check('LK7 unlock all reports OFF', dispatchM.setLock('all', false), false);
check('LK8 no locks left behind', next(dispatchM.locks), nil);
local _, lkTbl2 = dispatchM._equipResolved({ Body = 'Weaver Apron' }, {});
check('LK9 an unlocked slot equips again', lkTbl2.Body, 'Weaver Apron');

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
local lockstyleM = dofile('feature/lockstyle.lua');
local lsText = lockstyleM._serialize(lsT);
local lsChunk = (loadstring or load)(lsText);
check('AG10 serialized file parses', lsChunk ~= nil, true);
local lsBack = lsChunk();
check('AG11 active survives', lsBack.active, 2);
check('AG12 onload survives', lsBack.onload.DRK, 2);
check('AG13 set entries survive', lsBack.slots[1].set.Main, 'Kris');
check('AG14 quoting survives an apostrophe', lsBack.slots[1].set.Head, 'Ducal Guard\'s Ribbon');
check('AG15 round-trip feeds _lockstyleFrom', (dispatchM._lockstyleFrom(lsBack, 1)).Main, 'Kris');
-- (AG16-AG20 tested the v39 equip-preview plan; removed with it in v42 --
--  the preview paints the LOOK now, see the AI section.)

-- onload is PER JOB ENTRY on save (v42): the v41 migration serialized the whole
-- v40 onload map into every job file it touched; those cross-job copies are
-- never read for the file's own job, but they RESURFACE through the fallback
-- tiers (a job with no entry falls back to a file whose onload names it --
-- field: DRG=1 from box-1 "test" leaked into every file). Saves scrub it.
check('AG16 _entryData exported', type(lockstyleM._entryData), 'function');
if type(lockstyleM._entryData) == 'function' then
    local ed = lockstyleM._entryData({ active = 3, slots = { [1] = { name = 'x', set = {} } },
                                       onload = { DRK = 3, DRG = 1, WHM = 2 } }, 'DRK');
    check('AG17 entry keeps its OWN onload binding', ed.onload.DRK, 3);
    check('AG18 entry drops other jobs\' bindings', ed.onload.DRG == nil and ed.onload.WHM == nil, true);
    check('AG19 boxes and active ride unchanged', ed.active == 3 and ed.slots[1].name == 'x', true);
    local ed2 = lockstyleM._entryData({ active = 1, slots = {}, onload = { DRG = 1 } }, 'DRK');
    check('AG20 no own binding -> empty onload', next(ed2.onload), nil);
end

-- ---------------------------------------------------------------------------
-- AH. lockstyle picker: you can lockstyle to ANYTHING you own
--
--    HARD RULE (Henrik, 2026-07-15): the picker offers EVERY item you own for
--    the slot -- wrong job AND under-level for your CURRENT job both included.
--    (Server precision, source read 07-15: the style renders when one of YOUR
--    jobs at its current level could wear the piece -- canEquipItemOnAnyJob;
--    the AJ section below mirrors that gate and the engine warns at apply.)
--    The PICKER still filters nothing: gear.lua (what you have) is already the
--    source. Do not reintroduce a jobOK/Level check, and do not dim or flag
--    off-job picks either: here an off-job lockstyle is ordinary, not an edge
--    case, and marking it would imply it might fail. Compare the A-series above:
--    the same "never gate the picker" ruling was reverted THREE times there.
--    This is CatsEyeXI, not retail/LSB -- do not port a retail rule back in.
-- ---------------------------------------------------------------------------
local savedGear = package.loaded['dlac\\gear'];
package.loaded['dlac\\gear'] = {
    NameToObject = {},
    Head = {
        Onjob     = { Name = 'Onjob Cap',     Level = 1,  Jobs = { 'WHM' } },
        Wrongjob  = { Name = 'Wrongjob Cap',  Level = 1,  Jobs = { 'BLM' } },
        Highlevel = { Name = 'Highlevel Cap', Level = 99, Jobs = { 'WHM' } },
        Wrongboth = { Name = 'Wrongboth Cap', Level = 99, Jobs = { 'BLM' } },
        Anyjob    = { Name = 'Anyjob Cap',    Level = 1,  Jobs = { 'All' } },
    },
    Main = {   -- Main/Range nest one level deeper, by skill category
        Sword      = { Offsword = { Name = 'Offjob Sword', Level = 75, Jobs = { 'DRK' }, OneHanded = true } },
        GreatSword = { Big      = { Name = 'Big Blade',    Level = 70, Jobs = { 'DRK' }, OneHanded = false } },
    },
    Sub = {
        Targe = { Name = 'Test Targe', Level = 30, Jobs = { 'All' } },
    },
};
-- lockstyle captures gear as a load-time upvalue, so the fixture only has to be
-- in place across the dofile; restoring right after keeps the other sections' gear
-- table (section G's 'Solid Wand' etc.) untouched.
local lockstyleM = dofile('feature/lockstyle.lua');
package.loaded['dlac\\gear'] = savedGear;

check('AH0 _listFor exported', type(lockstyleM._listFor), 'function');
if type(lockstyleM._listFor) == 'function' then
    local function offered(slot, q)
        local set = {};
        for _, rec in ipairs(lockstyleM._listFor(slot, q or '')) do set[rec.Name] = true; end
        return set;
    end
    local head = offered('Head');
    check('AH1 HARD RULE: wrong-job item offered',            head['Wrongjob Cap'],  true);
    check('AH2 HARD RULE: under-level item offered',          head['Highlevel Cap'], true);
    check('AH3 HARD RULE: wrong-job AND under-level offered', head['Wrongboth Cap'], true);
    check('AH4 on-job item still offered',                    head['Onjob Cap'],     true);
    check('AH5 All-jobs item still offered',                  head['Anyjob Cap'],    true);
    check('AH6 HARD RULE: nothing is filtered out',           #lockstyleM._listFor('Head', ''), 5);
    check('AH7 HARD RULE: wrong-job Main offered (nested by skill)',
        offered('Main')['Offjob Sword'], true);
    -- the ONLY thing that narrows the list is the search box:
    check('AH8 search still narrows by name', #lockstyleM._listFor('Head', 'wrongjob'), 1);
    check('AH9 unknown slot -> empty, no error', #lockstyleM._listFor('Nope', ''), 0);
    -- Sub lists dual-wield offhands (Henrik, 07-17): gear.Sub's shields/grips
    -- PLUS the 1H records under Main -- the set builder's Sub-pool regulation,
    -- no Dual Wield or pairing gate. 2H stays out (never Sub-capable).
    local sub = offered('Sub');
    check('AH10 native Sub item offered',                          sub['Test Targe'],   true);
    check('AH11 DUAL WIELD: a 1H weapon under Main offered in Sub', sub['Offjob Sword'], true);
    check('AH12 a 2H weapon is NOT offered in Sub',                sub['Big Blade'],    nil);
    check('AH13 Main list itself is unchanged (no Sub bleed-back)', offered('Main')['Test Targe'], nil);
end

-- ---------------------------------------------------------------------------
-- AI. lockstyle LOOK preview: entity look_t plan (v42)
--
--    The preview writes the player's look_t instead of equipping, because this
--    server lockstyles to anything you OWN (see AH) and LAC will never equip an
--    off-job piece to show it. Bases are the SDK's (plugins/sdk/ffxi/entity.h:
--    "Head Armor (Starts at 0x1000)" ... Ranged 0x8000); the stored value is
--    base + model id, so base alone = nothing in the slot.
-- ---------------------------------------------------------------------------
local lookM = dofile('feature/lookpreview.lua');
check('AI0 _plan exported', type(lookM._plan), 'function');
if type(lookM._plan) == 'function' then
    local MODELS = { ["Arhat's Gi"] = 13, ['Kris'] = 7, ['Warp Ring'] = 0, ['Buckler'] = 5, ['Shuriken'] = 9 };
    local function modelOf(n) return MODELS[n]; end
    local plan = lookM._plan;

    -- the eight slots FFXI renders, each on its own base:
    check('AI1 body -> 0x2000 + model', plan({ Body = "Arhat's Gi" }, modelOf).Body, 0x2000 + 13);
    check('AI2 main -> 0x6000 + model', plan({ Main = 'Kris' }, modelOf).Main, 0x6000 + 7);
    check('AI3 sub  -> 0x7000 + model', plan({ Sub = 'Buckler' }, modelOf).Sub, 0x7000 + 5);
    -- dlac says Range, look_t says Ranged:
    check('AI4 Range maps to the Ranged field', plan({ Range = 'Kris' }, modelOf).Ranged, 0x8000 + 7);
    check('AI5 Range does NOT create a Range field', plan({ Range = 'Kris' }, modelOf).Range, nil);

    -- HARD RULE (AH) in look form: an off-job piece plans exactly like any other.
    -- The old preview could not render this; that is why this module exists.
    check('AI6 off-job piece plans normally', plan({ Body = "Arhat's Gi" }, modelOf).Body, 0x2000 + 13);

    -- 'remove' = LAC's "show nothing in this slot" -> the bare base:
    check('AI7 remove -> bare base', plan({ Head = 'remove' }, modelOf).Head, 0x1000);

    -- no model id -> DROPPED, never zeroed. An accessory (Model absent in the
    -- catalog) must not blank a slot; Warp Ring is Model 0 and Ring has no field.
    check('AI8 unknown name is dropped', plan({ Body = 'No Such Item' }, modelOf).Body, nil);
    check('AI9 model 0 is dropped, not zeroed', plan({ Head = 'Warp Ring' }, modelOf).Head, nil);
    check('AI10 non-look slot (Neck) ignored', plan({ Neck = 'Kris' }, modelOf).Neck, nil);

    -- Ammo has no look_t field: a thrown weapon renders in Ranged, but only when
    -- no real ranged weapon claims the slot.
    check('AI11 Ammo fills Ranged when Range is empty', plan({ Ammo = 'Shuriken' }, modelOf).Ranged, 0x8000 + 9);
    check('AI12 a real Range weapon beats Ammo',
        plan({ Ammo = 'Shuriken', Range = 'Kris' }, modelOf).Ranged, 0x8000 + 7);

    -- shape / robustness:
    local full = plan({ Head = 'remove', Body = "Arhat's Gi", Main = 'Kris' }, modelOf);
    local n = 0; for _ in pairs(full) do n = n + 1; end
    check('AI13 plans only the named slots', n, 3);
    local e1 = 0; for _ in pairs(plan({}, modelOf)) do e1 = e1 + 1; end
    check('AI14 empty set -> empty plan', e1, 0);
    local e2 = 0; for _ in pairs(plan(nil, modelOf)) do e2 = e2 + 1; end
    check('AI15 nil set -> empty plan, no error', e2, 0);
    local e3 = 0; for _ in pairs(plan({ Body = 'Kris' }, nil)) do e3 = e3 + 1; end
    check('AI16 no resolver -> empty plan, no error', e3, 0);

    -- v42 round 2: the preview INJECTS the client's own appearance packet
    -- (GRAP_LIST 0x051) -- layout from the server source (0x051_grap_list.cpp):
    -- GrapIDTbl[0] = face | race<<8, then head..ranged as base+model u16s.
    check('AI17 _merged: plan wins over snapshot',
        lookM._merged({ Head = 0x1005, Body = 0x2007 }, { Body = 0x2063 }).Body, 0x2063);
    check('AI18 _merged: snapshot fills unplanned slots',
        lookM._merged({ Head = 0x1005, Body = 0x2007 }, { Body = 0x2063 }).Head, 0x1005);
    check('AI19 _merged: bare base where neither knows',
        lookM._merged({ Head = 0x1005 }, { Body = 0x2063 }).Main, 0x6000);
    local pk = lookM._packet51(7, 2, { Head = 0x1001, Body = 0x2002, Hands = 0x3003, Legs = 0x4004,
                                       Feet = 0x5005, Main = 0x6006, Sub = 0x7007, Ranged = 0x8008 });
    check('AI20 packet51: GRAP_LIST length (0x18)', #pk, 0x18);
    check('AI21 packet51: header id|size', pk[1] == 0x51 and pk[2] == 0x18, true);
    check('AI22 packet51: face and race bytes', pk[5] == 7 and pk[6] == 2, true);
    check('AI23 packet51: Head u16 LE at 0x06', pk[7] == 0x01 and pk[8] == 0x10, true);
    check('AI24 packet51: Ranged u16 LE at 0x14', pk[21] == 0x08 and pk[22] == 0x80, true);
end

-- ---------------------------------------------------------------------------
-- AJ. lockstyle APPLY: the engine-built 0x053 (v42)
--
--    The server (CatsEyeXI src/map/packets/c2s/0x053_lockstyle.cpp, read
--    2026-07-15) takes ItemNo + EquipKind per entry -- container/index are
--    ignored, so no bag scan belongs in the client. styleItems persist per
--    slot server-side, so a box is only authoritative if all 9 visual slots
--    ride in every packet: named -> id, 'remove' -> 0 (renders EMPTY), unnamed
--    -> the worn item's id (freeze-current). The style gate mirrors the
--    server's canEquipItemOnAnyJob: one of YOUR jobs, at its CURRENT level.
-- ---------------------------------------------------------------------------
check('AJ0 _lockstylePacket exported', type(dispatchM._lockstylePacket), 'function');
if type(dispatchM._lockstylePacket) == 'function' then
    local RES = { ["Arhat's Gi"] = 13795, ['Kris'] = 16450 };
    local eqf = function(slot) if slot == 'Main' then return 21639; end return nil; end
    local pkt, r = dispatchM._lockstylePacket(
        { Body = "Arhat's Gi", Head = 'remove', Legs = 'No Such' },
        function(n) return RES[n]; end, eqf);
    check('AJ1 wire length 0x88', #pkt, 136);
    check('AJ2 header id|size', pkt[1] == 0x53 and pkt[2] == 0x88, true);
    check('AJ3 Count: all 9 slots, always', pkt[5], 9);
    check('AJ4 Mode: Set', pkt[6], 3);
    check('AJ5 named piece: EquipKind + ItemNo LE',
        pkt[50] == 5 and pkt[53] == 227 and pkt[54] == 53, true);   -- Body=kind5, 13795=0x35E3
    check('AJ6 remove -> ItemNo 0 (slot renders EMPTY)',
        pkt[42] == 4 and pkt[45] == 0 and pkt[46] == 0, true);      -- Head=kind4
    check('AJ7 unnamed -> frozen to worn item',
        pkt[10] == 0 and pkt[13] == 135 and pkt[14] == 84, true);   -- Main=kind0, 21639=0x5487
    check('AJ8 frozen reported', r.frozen.Main, 21639);
    check('AJ9 unnamed with nothing worn -> 0', pkt[18] == 1 and pkt[21] == 0 and pkt[22] == 0, true);   -- Sub
    check('AJ10 unresolved name reported missing', r.missing[1], 'No Such');
    check('AJ11 unresolved name -> ItemNo 0', pkt[66] == 7 and pkt[69] == 0 and pkt[70] == 0, true);     -- Legs
    check('AJ12 sent reported', r.sent.Body, "Arhat's Gi");

    -- the server's silent job gate, mirrored (charutils.cpp canEquipItemOnAnyJob)
    local gate = dispatchM._lsStyleGate;
    check('AJ13 gate: no job high enough -> old look persists',
        gate({ Jobs = { 'MNK', 'SAM', 'NIN' }, Level = 64 }, { MNK = 52, SAM = 10, DRK = 75 }), false);
    check('AJ14 gate: ANY job at level passes (not just the current one)',
        gate({ Jobs = { 'MNK', 'SAM', 'NIN' }, Level = 64 }, { NIN = 64, DRK = 75 }), true);
    check('AJ15 gate: All-jobs item needs any job at level',
        gate({ Jobs = { 'All' }, Level = 50 }, { DRK = 75 }), true);
    check('AJ16 gate: All-jobs item above every level fails',
        gate({ Jobs = { 'All' }, Level = 99 }, { DRK = 75 }), false);
    check('AJ17 gate: unknown record passes (server decides)', gate(nil, {}), true);
    check('AJ18 gate: record without Jobs passes', gate({ Level = 99 }, {}), true);
end

-- ---------------------------------------------------------------------------
-- AK. reserved slots (dispatch.reservedDrops) -- an item's RSlot mask is the
--     server's item_equipment.rslot: the slots it TAKES AWAY while worn. The
--     Ryl.Ftm. Tunic (Body) reserves Head; equipping a head piece anyway makes
--     the server strip it and dlac re-equip it, forever. The reserver wins and
--     the reserved slot is dropped -- the only stable state.
-- ---------------------------------------------------------------------------
do
    local RS = { ['Ryl.Ftm. Tunic'] = 0x0010,     -- Body  -> Head
                 ['Wikyo Cloak']    = 0x0010,     -- Body  -> Head
                 ['Decennial Coat'] = 0x0040,     -- Body  -> Hands
                 ['Moogle Suit']    = 0x01C0,     -- Body  -> Hands + Legs + Feet
                 ['Marine Boxers']  = 0x0100,     -- Legs  -> Feet
                 ['Boomerang']      = 0x0008,     -- Range -> Ammo
                 ['Pet Food Alpha'] = 0x0004 };   -- Ammo  -> Range
    local function look(n) return RS[n]; end
    local function drops(set, worn) return dispatchM.reservedDrops(set, look, worn) or {}; end

    -- the reported bug
    local d = drops({ Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin', Legs = 'Cotton Brais' });
    check('AK1 a reserved Head is dropped',        d.Head, 'Ryl.Ftm. Tunic');
    check('AK2 the reserver itself is kept',       d.Body, nil);
    check('AK3 unrelated slots are untouched',     d.Legs, nil);

    check('AK4 no reserver -> nothing dropped',
        dispatchM.reservedDrops({ Body = 'Cotton Doublet', Head = 'Silver Hairpin' }, look), nil);
    check('AK5 reserver with the slot empty -> nothing dropped',
        dispatchM.reservedDrops({ Body = 'Ryl.Ftm. Tunic' }, look), nil);
    check('AK6 an unknown item reserves nothing',
        dispatchM.reservedDrops({ Body = 'Mystery Robe', Head = 'Silver Hairpin' }, look), nil);

    -- multi-bit masks
    local m = drops({ Body = 'Moogle Suit', Hands = 'G1', Legs = 'G2', Feet = 'G3', Head = 'G4' });
    check('AK7 every bit of the mask drops',  (m.Hands ~= nil and m.Legs ~= nil and m.Feet ~= nil), true);
    check('AK8 a bit NOT in the mask stays',  m.Head, nil);

    -- a dropped slot must not go on to reserve: Body takes Legs, so the Legs
    -- piece is never worn and its own claim on Feet must not fire.
    local c = drops({ Body = 'Moogle Suit', Legs = 'Marine Boxers', Feet = 'Leather Highboots' });
    check('AK9 chained: Legs dropped by Body',        c.Legs, 'Moogle Suit');
    check('AK10 chained: Feet dropped by Body, not by the dropped Legs', c.Feet, 'Moogle Suit');

    -- mutual reservation resolves deterministically by slot order, not pairs() luck
    local mut = drops({ Range = 'Boomerang', Ammo = 'Pet Food Alpha' });
    check('AK11 mutual: Range wins',  mut.Range, nil);
    check('AK12 mutual: Ammo dropped', mut.Ammo, 'Boomerang');
    check('AK13 arrows are not ammo-reserved', drops({ Range = 'Power Bow', Ammo = 'Iron Arrow' }).Ammo, nil);

    -- WORN pieces reserve too: the common case is a set that only writes Head
    -- while the Tunic is already on your back.
    local function wornTunic(slot) if slot == 'Body' then return 'Ryl.Ftm. Tunic'; end return nil; end
    check('AK14 a worn reserver drops the planned Head',
        drops({ Head = 'Silver Hairpin' }, wornTunic).Head, 'Ryl.Ftm. Tunic');
    check('AK15 a set that REPLACES the reserver keeps its Head',
        drops({ Head = 'Silver Hairpin', Body = 'Cotton Doublet' }, wornTunic).Head, nil);
    check('AK16 worn slots are never themselves dropped',
        drops({ Head = 'Silver Hairpin' }, wornTunic).Body, nil);
    check('AK17 a throwing worn() is survivable',
        dispatchM.reservedDrops({ Head = 'Silver Hairpin' }, look,
            function() error('no equipment'); end), nil);

    -- slot keys are matched case-insensitively; the dropped key keeps the set's case
    local lc = drops({ body = 'Ryl.Ftm. Tunic', head = 'Silver Hairpin' });
    check('AK18 lowercase set keys still resolve', lc.head, 'Ryl.Ftm. Tunic');

    -- the equipResolved post-pass end-to-end. First with a manifest that has no
    -- RSlot (every gear.lua written before v43): the engine must behave exactly as
    -- it did, or an un-fixed file would start losing slots.
    local gT = package.loaded['dlac\\gear'];
    gT.NameToObject['Ryl.Ftm. Tunic'] = { Name = 'Ryl.Ftm. Tunic', Type = 'Body' };
    gT.NameToObject['Silver Hairpin'] = { Name = 'Silver Hairpin', Type = 'Head' };
    local _, akTbl = dispatchM._equipResolved({ Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin' }, {});
    check('AK19 a manifest without RSlot leaves the engine unchanged', akTbl.Head, 'Silver Hairpin');

    -- now stamp RSlot, as the scan / `/dl fix` does -> the engine drops the Head.
    -- This is the wiring test: reservedDrops is pure, but rslotOf reads the real
    -- manifest, and that read is what actually has to work in LAC's state.
    gT.NameToObject['Ryl.Ftm. Tunic'].RSlot = 0x0010;
    local akNote, akTbl2 = dispatchM._equipResolved({ Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin' }, {});
    check('AK20 manifest RSlot -> reserved Head dropped', akTbl2.Head, nil);
    check('AK21 the reserver still equips',               akTbl2.Body, 'Ryl.Ftm. Tunic');
    check('AK22 the drop is traced for /dl why',
        string.find(akNote, 'RESERVED', 1, true) ~= nil, true);
end

-- ---------------------------------------------------------------------------
-- AL. PINNED slots (dispatch v44) -- "equip item, lock slot so nothing removes
--     equipped item" (Henrik). pinwatch writes pinstate.lua; the engine wears
--     the named item at TOP priority (above the craft overlay) on EVERY event.
--     scope = 'All' (every dispatch) or a list of "<Event>|<rule label>" keys.
--
--     NOTE: `(function() ... end)()`, not the `do ... end` the older sections
--     use. THIS FILE hit the same LuaJIT/Lua 200-local-per-chunk cap gearui did
--     -- it is one ~1800-line main chunk and a `do` block's locals share that
--     chunk's budget, so wrapping in `do` does not buy a single register. A
--     function body gets its OWN 200. Add new sections this way; it is also the
--     cheapest fix if an older `do` section ever tips the cap over.
-- ---------------------------------------------------------------------------
;(function()
    local PF = dispatchM._pinOverlayFor;

    -- scope 'All': applies with no triggers matched at all (a bare profile still
    -- has to honour a pin) and on every event, not just Default.
    local pAll = { Ring1 = { item = 'Rajas Ring', scope = 'All' } };
    check('AL1 All pin applies with zero hits',
        (PF(pAll, {}, 'Default') or {}).Ring1, 'Rajas Ring');
    check('AL2 All pin applies on a non-Default event',
        (PF(pAll, {}, 'Midcast') or {}).Ring1, 'Rajas Ring');

    -- no state / empty state -> nil (nil, not {}: dispatch tests `pEquip == nil`
    -- to decide whether it may bail out of the whole dispatch)
    check('AL3 no pin state -> nil overlay', PF(nil, {}, 'Default'), nil);
    check('AL4 empty pin state -> nil overlay', PF({}, {}, 'Default'), nil);

    -- scoped pins: only on a dispatch where THAT trigger matched
    local key = dispatchM.pinScopeKey('Midcast', 'name=slow ii');
    local pScoped = { Head = { item = 'Uk\'uxkaj Cap', scope = { key } } };
    local hitSlow  = { { label = 'name=slow ii' } };
    local hitOther = { { label = 'name=dia ii' } };
    check('AL5 scoped pin applies when its trigger matched',
        (PF(pScoped, hitSlow, 'Midcast') or {}).Head, 'Uk\'uxkaj Cap');
    check('AL6 scoped pin is silent when another trigger matched',
        PF(pScoped, hitOther, 'Midcast'), nil);
    check('AL7 scoped pin is silent with no hits at all',
        PF(pScoped, {}, 'Midcast'), nil);
    -- the reason scope keys carry the EVENT: 'any' is the label of every
    -- unconditional rule, so a Precast 'any' and a Midcast 'any' would be
    -- indistinguishable and one pin would silently cover both.
    check('AL8 scoped pin does not leak across events (same label, other event)',
        PF(pScoped, hitSlow, 'Precast'), nil);

    -- a pin scoped to a trigger that no longer exists goes QUIET rather than
    -- falling back to forcing gear on every dispatch
    local pGone = { Feet = { item = 'Herald\'s Gaiters', scope = { 'Midcast|name=deleted' } } };
    check('AL9 pin on a deleted trigger goes quiet', PF(pGone, hitSlow, 'Midcast'), nil);

    -- tolerated shapes: bare string, and a missing scope (hand-written file)
    check('AL10 bare-string pin is treated as All',
        (PF({ Back = 'Cape' }, {}, 'Default') or {}).Back, 'Cape');
    check('AL11 pin with no scope is treated as All',
        (PF({ Back = { item = 'Cape' } }, {}, 'Default') or {}).Back, 'Cape');
    check('AL12 empty item name is ignored',
        PF({ Back = { item = '', scope = 'All' } }, {}, 'Default'), nil);

    -- several slots at once; mixed scopes resolve independently
    local pMix = { Ring1 = { item = 'Rajas Ring', scope = 'All' },
                   Head  = { item = 'Uk\'uxkaj Cap', scope = { key } } };
    local mix = PF(pMix, hitSlow, 'Midcast') or {};
    check('AL13 mixed scopes: All applies',    mix.Ring1, 'Rajas Ring');
    check('AL14 mixed scopes: scoped applies', mix.Head, 'Uk\'uxkaj Cap');
    local mix2 = PF(pMix, {}, 'Default') or {};
    check('AL15 mixed scopes: All still applies out of scope', mix2.Ring1, 'Rajas Ring');
    check('AL16 mixed scopes: scoped drops out of scope',      mix2.Head, nil);

    -- pinScopeKey is the ONE spelling of a scope key: the GUI builds menu entries
    -- with it and the engine matches with it, so the two states cannot drift.
    check('AL17 pinScopeKey format', dispatchM.pinScopeKey('Midcast', 'name=slow ii'),
        'Midcast|name=slow ii');

    -- ruleLabel: shared by normalize (engine) and the pin menu (GUI). A condition
    -- value may be a LIST (when.mode holds several modes) and tostring() on a
    -- table yields an ADDRESS -- different in each Lua state and after every
    -- reload -- so a scoped pin could never match. Serialize lists by value.
    check('AL18 ruleLabel: no conditions -> any', dispatchM.ruleLabel({}), 'any');
    check('AL19 ruleLabel: single condition', dispatchM.ruleLabel({ name = 'Slow II' }), 'name=Slow II');
    check('AL20 ruleLabel: sorted + joined',
        dispatchM.ruleLabel({ skill = 'Enfeebling Magic', name = 'Slow II' }),
        'name=Slow II+skill=Enfeebling Magic');
    check('AL21 ruleLabel: list value is serialized BY VALUE, not by address',
        dispatchM.ruleLabel({ mode = { 'DT', 'Acc' } }), 'mode=Acc,DT');
    check('AL22 ruleLabel: two equal lists in DIFFERENT tables label identically',
        dispatchM.ruleLabel({ mode = { 'DT', 'Acc' } }) == dispatchM.ruleLabel({ mode = { 'Acc', 'DT' } }), true);
    check('AL23 ruleLabel: keys lowercased like normalize',
        dispatchM.ruleLabel({ Name = 'Slow II' }), 'name=Slow II');

    -- Sub-vs-Main, the pin side. A pinned Sub with no pinned Main is top
    -- priority and must survive the set's Main: without a guard the two knock
    -- each other off on every pass (the v37 flap, the reason craftMainGuard
    -- exists). The guard SOURCE is what dispatch picks; these check the shape
    -- dispatch feeds it and the resulting hold.
    local pinSubOnly = { Sub = 'Kupo Shield' };
    local pg = dispatchM._craftMainGuard(pinSubOnly);
    check('AL26 a pinned Sub with no pinned Main builds a guard', pg ~= nil, true);
    check('AL27 the guard holds a 2H set Main against a pinned Sub', pg('Death Scythe'), true);
    check('AL28 a 1H set Main pairs with a pinned Sub and passes', pg('Parry Knife'), false);
    check('AL29 no guard when the pin brings its own Main',
        dispatchM._craftMainGuard({ Sub = 'Kupo Shield', Main = 'Parry Knife' }), nil);
    local _, alHeld = dispatchM._equipResolved({ Main = 'Death Scythe', Body = 'Weaver Apron' },
        { craftMainGuard = pg });
    check('AL30 the set Main is held so the pinned Sub survives', alHeld.Main, nil);
    check('AL31 the rest of the set is untouched by the hold', alHeld.Body, 'Weaver Apron');

    -- The other side: a PINNED Main beats the craft overlay's Sub. dispatch drops
    -- the craft Sub when it cannot pair, or craft re-equips it every pass and the
    -- pinned Main knocks it off again. (Same guard function, asked in reverse.)
    local cg = dispatchM._craftMainGuard({ Sub = 'Kupo Shield' });
    check('AL32 a pinned 2H Main conflicts with the craft Sub', cg('Death Scythe'), true);
    check('AL33 a pinned 1H Main leaves the craft Sub alone', cg('Parry Knife'), false);

    -- A pin goes through equipResolved like any other set, so it inherits the
    -- reserved-slot pass: pinning a Body that reserves Head drops the Head.
    local gT = require('dlac\\gear');
    if type(gT) == 'table' and type(gT.NameToObject) == 'table'
       and gT.NameToObject['Ryl.Ftm. Tunic'] ~= nil then
        gT.NameToObject['Ryl.Ftm. Tunic'].RSlot = 0x0010;
        local _, alTbl = dispatchM._equipResolved(
            { Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin' }, {});
        check('AL24 a pinned reserver still drops the reserved slot', alTbl.Head, nil);
        check('AL25 the pinned reserver itself equips', alTbl.Body, 'Ryl.Ftm. Tunic');

        -- THE FLAP, through the overlay. reservedDrops judges ONE table at a
        -- time, and the pin lands in its OWN equipResolved -- so the SET's pass
        -- never learns the pinned Tunic is about to reserve the Head it is
        -- equipping, and the pin's pass cannot drop a Head its table never
        -- names. Without the hold: set equips Head, pin equips Tunic, server
        -- strips Head, forever ("it just flashes back and forth infinitely").
        -- (Nested do: this file's main chunk has its own 200-local ceiling.)
        do
            local res = dispatchM._pinReservedSlots({ Body = 'Ryl.Ftm. Tunic' });
            check('AL34 a pinned reserver reports its reserved slot',
                (res or {}).head, 'Ryl.Ftm. Tunic');
            check('AL35 it does not report slots it never reserves', (res or {}).legs, nil);
            -- the hold applied to the SET's pass: Head must not be equipped at all
            local nt, st = dispatchM._equipResolved(
                { Head = 'Silver Hairpin', Body = 'Cotton Doublet' },
                { pinReserved = res });
            check('AL36 the set never equips a slot a PIN reserves', st.Head, nil);
            check('AL37 the set keeps every other slot', st.Body, 'Cotton Doublet');
            check('AL38 the hold is traced for /dl why',
                string.find(nt or '', 'RESERVED by pinned', 1, true) ~= nil, true);
        end
        do
            -- no pins -> no hold -> the slot dispatches normally (stateless:
            -- unpin and Head comes straight back on the next pass)
            check('AL39 no pins -> nothing reserved', dispatchM._pinReservedSlots(nil), nil);
            local _, fr = dispatchM._equipResolved({ Head = 'Silver Hairpin' }, {});
            check('AL40 unpinned, the same Head equips again', fr.Head, 'Silver Hairpin');
            -- a pin never reserves ANOTHER pin's slot: you asked for both, both land
            local r2 = dispatchM._pinReservedSlots({ Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin' });
            check('AL41 a pin does not reserve a slot another pin owns', (r2 or {}).head, nil);
        end
    end
end)();

-- ---------------------------------------------------------------------------
-- AM. pinwatch (addon state) -- the writer half of the pin contract. Serializes
--     the table the engine's ensurePinState() loads back, so the two must agree
--     on the format exactly.
-- ---------------------------------------------------------------------------
;(function()
    -- dofile, not require: the harness has no addons/ on package.path (the
    -- dispatch/utils pattern above). serialize is pure -- charDir is pcall-guarded
    -- and just yields nil without AshitaCore, so nothing here touches disk.
    local pw = dofile('feature/pinwatch.lua');   -- forward slash: also loads on Linux CI

    local function roundTrip(pins)
        local text = pw.serialize(pins);
        local chunk = (loadstring or load)(text, '@pinstate.lua');
        if chunk == nil then return nil, text; end
        local ok, t = pcall(chunk);
        return (ok and t or nil), text;
    end

    -- empty -> a valid, loadable file (NOT an empty string: the engine loadstrings it)
    local e, eText = roundTrip({});
    check('AM1 empty pin table serializes to a loadable chunk', type(e), 'table');
    check('AM2 empty pin table has no entries', next(e or {}), nil);
    check('AM3 empty file is the canonical spelling', eText, 'return { }\n');

    -- All-scope round trip
    local r = roundTrip({ Ring1 = { item = 'Rajas Ring', scope = 'All' } });
    check('AM4 All pin round-trips: item', (r.Ring1 or {}).item, 'Rajas Ring');
    check('AM5 All pin round-trips: scope', (r.Ring1 or {}).scope, 'All');

    -- scoped round trip
    local r2 = roundTrip({ Head = { item = 'Uk\'uxkaj Cap', scope = { 'Midcast|name=slow ii' } } });
    check('AM6 scoped pin round-trips: item', (r2.Head or {}).item, 'Uk\'uxkaj Cap');
    check('AM7 scoped pin round-trips: scope is a list',
        type((r2.Head or {}).scope) == 'table' and (r2.Head or {}).scope[1], 'Midcast|name=slow ii');

    -- the serialized file must be exactly what the ENGINE accepts
    local eng = dispatchM._pinOverlayFor(r2, { { label = 'name=slow ii' } }, 'Midcast');
    check('AM8 the engine reads pinwatch output', (eng or {}).Head, 'Uk\'uxkaj Cap');

    -- names with quotes/backslashes must survive (%q) -- FFXI item names carry
    -- apostrophes routinely (Uk'uxkaj Cap, Herald's Gaiters)
    local r3 = roundTrip({ Feet = { item = 'Herald\'s Gaiters', scope = 'All' } });
    check('AM9 apostrophes survive serialization', (r3.Feet or {}).item, 'Herald\'s Gaiters');

    -- malformed entries are dropped, not written
    local r4 = roundTrip({ Bad = { scope = 'All' }, Good = { item = 'X', scope = 'All' } });
    check('AM10 entry with no item is dropped', r4.Bad, nil);
    check('AM11 the valid entry beside it survives', (r4.Good or {}).item, 'X');

    -- stable output: dispatch's reader content-compares the RAW TEXT before
    -- re-parsing, so an unstable key order would defeat that cache every second
    local a = pw.serialize({ Ring1 = { item = 'A', scope = 'All' }, Head = { item = 'B', scope = 'All' },
                             Feet = { item = 'C', scope = 'All' }, Back = { item = 'D', scope = 'All' } });
    local b = pw.serialize({ Back = { item = 'D', scope = 'All' }, Feet = { item = 'C', scope = 'All' },
                             Head = { item = 'B', scope = 'All' }, Ring1 = { item = 'A', scope = 'All' } });
    check('AM12 serialization is order-stable across pairs() luck', a, b);

    -- Adversarial names. The engine loads this file with loadstring: anything %q
    -- fails to escape is a syntax error there, and the pin silently never applies.
    for i, nm in ipairs({ 'Herald\'s Gaiters', 'A "quoted" Ring', 'Back\\slash',
                          'new\nline', 'tab\there', 'pct%20', 'brace}Cap',
                          'Uk\'uxkaj Cap' }) do
        local rt = roundTrip({ Head = { item = nm, scope = 'All' } });
        check('AM13.' .. i .. ' adversarial name round-trips: ' .. string.format('%q', nm),
            (rt or {}).Head and rt.Head.item, nm);
    end
    -- and the same through a scope key, which is also user-influenced text
    local rtk = roundTrip({ Head = { item = 'X', scope = { 'Midcast|name=a"b\'c' } } });
    check('AM14 adversarial scope key round-trips',
        ((rtk or {}).Head or {}).scope[1], 'Midcast|name=a"b\'c');

    -- Character switch. An Ashita addon survives a logout, so the session-only
    -- clear must be keyed on the CHARACTER, not a one-shot boolean -- otherwise
    -- the next character to log in keeps this table and never gets their own
    -- pinstate.lua cleared, and last session's pins force gear on them at login.
    -- (charDir is nil headlessly, so drive the guard through the seam directly.)
    check('AM15 loadPinState is a no-op before login (no character dir yet)',
        pcall(pw.loadPinState), true);
    pw.pins = { Head = { item = 'CharA Cap', scope = 'All' } };
    pw.loadPinState();          -- still pre-login: must NOT clear or write
    check('AM16 pre-login load leaves the table alone', (pw.pins.Head or {}).item, 'CharA Cap');
end)();

-- ---------------------------------------------------------------------------
-- AN. lockstyle "Show gear I don't own" -- preview anything, save only what you
--     own (Henrik, 2026-07-15).
--
--     The preview never asks the server (it injects your own 0x051), so it can
--     render any item in the game. The SERVER renders a style only if you have
--     the item -- so an unowned pick is preview-only and Save refuses it.
--
--     Two rules this section exists to hold down:
--     1. `all` LIFTS the ownership filter -- it must never ADD one. The AH HARD
--        RULE (no job/level gate, ever) applies to the catalog list too, and a
--        2-arg call must stay owned-only and byte-identical to before.
--     2. Ownership is decided BY ID, never by name. The API drops apostrophes,
--        so the catalog says "Arhats Gi" where gear.lua says "Arhat's Gi" --
--        a name compare would call an item you own unowned, and (worse) save a
--        name the engine cannot resolve at apply time.
-- ---------------------------------------------------------------------------
(function()
    local savedGear = package.loaded['dlac\\gear'];
    package.loaded['dlac\\gear'] = {
        NameToObject = { ["Arhat's Gi"] = { Name = "Arhat's Gi", Id = 14000, Level = 60 },
                         ['Plain Robe']  = { Name = 'Plain Robe',  Id = 14001, Level = 1  } },
        Body = { Arhat = { Name = "Arhat's Gi", Id = 14000, Level = 60 },
                 Plain = { Name = 'Plain Robe',  Id = 14001, Level = 1  } },
    };
    local ls = dofile('feature/lockstyle.lua');
    package.loaded['dlac\\gear'] = savedGear;

    -- The catalog as gearui hands it over: FLAT, .Slot-carrying, API spelling.
    -- 'Gletis Crossbow' is the REAL shape of CatsEyeXI's junk (verified against
    -- tools/api_cache): an unimplemented row the server reports as slot=32 Body
    -- with MId=0 and jobs=0. 258 of those sit in the Body bucket -- they are why
    -- browsing Body listed crossbows and boots. No Model => no look => not offered.
    ls.wire{
        allEquip = function()
            return {
                { Name = 'Arhats Gi',  Id = 14000, Level = 60, Slot = 'Body', Model = 59 },  -- owned, other spelling
                { Name = 'Plain Robe', Id = 14001, Level = 1,  Slot = 'Body', Model = 1  },  -- owned, same spelling
                { Name = 'Royal Robe', Id = 14002, Level = 75, Slot = 'Body', Model = 2  },  -- NOT owned
                { Name = 'Kris',       Id = 16000, Level = 60, Slot = 'Main', Model = 7, OneHanded = true },  -- other slot; 1H
                { Name = 'Gletis Crossbow', Id = 14003, Level = 99, Slot = 'Body' },         -- server junk: no Model
                { Name = 'Amini Bottillons +2', Id = 14004, Level = 99, Slot = 'Body', Model = 0 }, -- junk: Model 0
                { Name = 'Kite Shield', Id = 16001, Level = 10, Slot = 'Sub',  Model = 3 },  -- native Sub
                { Name = 'Great Blade', Id = 16002, Level = 50, Slot = 'Main', Model = 8, OneHanded = false }, -- 2H
            };
        end,
        ownedById = function(id)
            local g = { [14000] = { Name = "Arhat's Gi" }, [14001] = { Name = 'Plain Robe' } };
            return g[id];
        end,
    };

    local function names(list) local s = {}; for _, r in ipairs(list) do s[r.Name] = true; end return s; end

    -- 1. the default is untouched
    check('AN1 owned-only by default (2-arg call)', #ls._listFor('Body', ''), 2);
    check('AN2 owned-only never shows unowned gear', names(ls._listFor('Body', ''))['Royal Robe'], nil);

    -- 2. all=true lifts ownership and NOTHING else
    local all = ls._listFor('Body', '', true);
    check('AN3 all=true adds the unowned item',   names(all)['Royal Robe'], true);
    check('AN4 all=true keeps the owned ones',    names(all)['Plain Robe'], true);
    check('AN5 all=true filters by slot',         names(all)['Kris'],       nil);
    check('AN6 all=true is the whole slot',       #all, 3);
    check('AN7 HARD RULE: all=true adds no job/level gate -- Lv75 on a Lv1 fixture is offered',
        names(all)['Royal Robe'], true);
    check('AN8 search still narrows the catalog list', #ls._listFor('Body', 'royal', true), 1);
    check('AN9 all=true sorts highest level first (the browse cap keeps the good end)',
        all[1].Name, 'Royal Robe');

    -- The junk rows (Henrik, 07-15). The server's item DB defaults unimplemented
    -- items to slot=32/Body with MId=0, so the Body bucket collects crossbows and
    -- boots. A LOOK picker must not offer something with no look.
    check('AN9a server junk (no Model) is not offered -- the wrong-slot crossbow',
        names(all)['Gletis Crossbow'], nil);
    check('AN9b Model=0 is "no look" too, not a real model',
        names(all)['Amini Bottillons +2'], nil);
    check('AN9c the junk did not take the real body pieces with it', #all, 3);
    check('AN9d hasLook: a real model passes',       ls._hasLook({ Model = 59 }), true);
    check('AN9e hasLook: model 0 fails',             ls._hasLook({ Model = 0 }),  false);
    check('AN9f hasLook: absent model fails',        ls._hasLook({}),             false);
    -- HARD RULE: the look filter is for the CATALOG only. gear.lua carries no
    -- Model of its own (gearui back-fills it later), so filtering the owned list
    -- on it would empty the picker -- and AH6 pins "nothing is filtered out".
    check('AN9g HARD RULE: the owned list is NOT look-filtered (its entries have no Model)',
        #ls._listFor('Body', ''), 2);
    -- Dual wield rides the catalog list too (Henrik, 07-17): a Slot="Main" row
    -- with OneHanded=true belongs in the Sub browse; a 2H one never does.
    local subAll = ls._listFor('Sub', '', true);
    check('AN9h catalog Sub browse carries the native Sub item', names(subAll)['Kite Shield'], true);
    check('AN9i DUAL WIELD: a 1H Main-slot row is offered in Sub', names(subAll)['Kris'], true);
    check('AN9j a 2H Main-slot row is NOT offered in Sub', names(subAll)['Great Blade'], nil);
    check('AN9k the Sub browse is exactly those two', #subAll, 2);
    -- No gearui wire (load order: lockstyle loads first, and every W helper is
    -- optional-guarded) -- all=true must degrade to the owned list, never throw.
    -- Asserts the CONTRACT, not a count: the fixture here is the shared gear
    -- table other sections own, and its Body count is not this section's to pin.
    check('AN10 all=true with no wire degrades to owned, no error',
        (function()
            local m = dofile('feature/lockstyle.lua');
            local ok, r = pcall(m._listFor, 'Body', '', true);
            return ok and type(r) == 'table';
        end)(), true);

    -- 3. the Save gate
    check('AN11 owned name passes the gate',          ls._nameOwned("Arhat's Gi"), true);
    check('AN12 unowned name fails the gate',         ls._nameOwned('Royal Robe'), false);
    check('AN13 APOSTROPHE TRAP: the catalog spelling is NOT owned -- the picker must store YOUR name',
        ls._nameOwned('Arhats Gi'), false);
    check('AN14 "remove" is not an item -- never blocks a save', ls._nameOwned('remove'), true);
    check('AN15 empty/cleared slot never blocks a save',         ls._nameOwned(''),       true);
    check('AN16 nil never blocks a save',                        ls._nameOwned(nil),      true);

    check('AN17 a fully-owned set saves', #ls._unownedSlots({ Body = "Arhat's Gi", Head = 'remove' }), 0);
    local bad = ls._unownedSlots({ Body = 'Royal Robe', Head = 'Nonesuch Cap', Legs = 'Plain Robe' });
    check('AN18 unowned slots are reported', #bad, 2);
    check('AN19 unowned slots are sorted (stable warning text)', bad[1] .. ',' .. bad[2], 'Body,Head');
    check('AN20 an empty set saves', #ls._unownedSlots({}), 0);
    check('AN21 a nil set never errors',  #ls._unownedSlots(nil), 0);

    -- 4. the two rules meet: picking the owned item off the CATALOG list must
    --    store gear.lua's spelling, or the engine cannot resolve it at apply and
    --    the gate would reject an item you actually own. This is the bridge.
    local catRec = { Name = 'Arhats Gi', Id = 14000, Level = 60, Slot = 'Body' };   -- API spelling
    check('AN22 ownedRec finds your copy of a catalog row, by Id',
        (ls._ownedRec(catRec) or {}).Name, "Arhat's Gi");
    check('AN23 ownedRec returns nil for gear you do not own',
        ls._ownedRec({ Name = 'Royal Robe', Id = 14002 }), nil);
    check('AN24 THE BRIDGE: the name the picker stores is the name the gate accepts',
        ls._nameOwned((ls._ownedRec(catRec) or catRec).Name), true);
    check('AN25 without the bridge the same pick would be rejected (why AN24 matters)',
        ls._nameOwned(catRec.Name), false);
    check('AN26 ownedRec tolerates a row with no Id', ls._ownedRec({ Name = 'x' }), nil);

    -- 5. FAIL OPEN. The gate must never brick Save because a lookup failed --
    --    pre-login gear.lua is the bundled EMPTY template (dlac.lua preloads at
    --    Ashita boot, the real one swaps in on the first frame after login). A
    --    fail-closed gate would call every item unowned and refuse every save.
    local saved2 = package.loaded['dlac\\gear'];
    package.loaded['dlac\\gear'] = { NameToObject = {} };       -- the empty template
    local lsEmpty = dofile('feature/lockstyle.lua');
    package.loaded['dlac\\gear'] = saved2;
    check('AN27 FAIL OPEN: an empty gear table does not block a save',
        lsEmpty._nameOwned('Anything At All'), true);
    check('AN28 FAIL OPEN: nothing is reported unowned when we cannot tell',
        #lsEmpty._unownedSlots({ Body = 'Anything At All' }), 0);
end)();

-- ---------------------------------------------------------------------------
-- AO. setimport.importStaticSet -- the pure "Copy from static" transform (#15/ADR 0008)
--
--   Full-replace: only slots the static DEFINES (and that resolve to >=1 candidate)
--   appear in working; order carried verbatim; notBestFirst names slots whose candidate
--   order is not highest-item-Level first. Resolver is injected (owned records -> entry).
-- ---------------------------------------------------------------------------
(function()
    local simport = dofile('gear/setimport.lua');   -- forward slash: also loads on Linux CI
    check('AO0 importStaticSet exported', type(simport.importStaticSet), 'function');

    local SLOTS = { { label = 'Main' }, { label = 'Sub' }, { label = 'Head' },
                    { label = 'Body' }, { label = 'Hands' }, { label = 'Waist' } };

    -- Owned records (Name -> record), the only ones the resolver knows. A resolver over
    -- these mirrors gearui.resolveSetItem: a name not owned -> nil (dropped candidate);
    -- a dlac: string -> a virtual entry (Level 0, taken outright at equip).
    local OWNED = {
        ['warp cudgel']    = { Name = 'Warp Cudgel',    Level = 30 },
        ['yagrush']        = { Name = 'Yagrush',        Level = 75 },
        ['chatoyant staff']= { Name = 'Chatoyant Staff',Level = 70 },
        ['austere hat']    = { Name = 'Austere Hat',    Level = 60 },
        ['dalmatica']      = { Name = 'Dalmatica',      Level = 60 },
        ['errant houppe.'] = { Name = 'Errant Houppe.', Level = 71 },
    };
    local function resolve(elem)
        if type(elem) == 'string' then
            if string.lower(string.sub(elem, 1, 5)) == 'dlac:' then
                return { rec = { Name = elem, Level = 0, Virtual = true } };
            end
            local rec = OWNED[string.lower(elem)];
            return rec and { rec = rec } or nil;
        end
        if type(elem) == 'table' and type(elem.Name) == 'string' then
            local rec = OWNED[string.lower(elem.Name)];
            return rec and { rec = rec } or nil;
        end
        return nil;
    end

    -- 1. A plain static set: one element per slot -> one-candidate working lists, no
    --    warnings (a single candidate is trivially best-first).
    local plain = { Main = 'Yagrush', Head = 'Austere Hat', Body = 'Dalmatica',
                    NotASlot = 'ignored' };
    local r1 = simport.importStaticSet(plain, SLOTS, resolve);
    check('AO1 plain: slotCount', r1.slotCount, 3);
    check('AO2 plain: Main list len', #r1.working.Main, 1);
    check('AO3 plain: Main[1] name', r1.working.Main[1].rec.Name, 'Yagrush');
    check('AO4 plain: undefined slot cleared (Sub absent)', r1.working.Sub, nil);
    check('AO5 plain: no best-first warnings', #r1.notBestFirst, 0);

    -- 2. A level-descending _Priority list imports silently and keeps its order.
    local descending = { Main = { 'Yagrush', 'Chatoyant Staff', 'Warp Cudgel' } };
    local r2 = simport.importStaticSet(descending, SLOTS, resolve);
    check('AO6 descending: order verbatim [1]', r2.working.Main[1].rec.Name, 'Yagrush');
    check('AO7 descending: order verbatim [3]', r2.working.Main[3].rec.Name, 'Warp Cudgel');
    check('AO8 descending: no warning (best-first)', #r2.notBestFirst, 0);

    -- 3. A not-best-first list (a lower-Level piece ranked above a higher one) is named.
    local mixed = { Main = { 'Warp Cudgel', 'Yagrush' },   -- 30 then 75 -> NOT best-first
                    Body = { 'Dalmatica', 'Errant Houppe.' } }; -- 60 then 71 -> NOT best-first
    local r3 = simport.importStaticSet(mixed, SLOTS, resolve);
    check('AO9 mixed: order still verbatim', r3.working.Main[1].rec.Name, 'Warp Cudgel');
    check('AO10 mixed: two slots flagged', #r3.notBestFirst, 2);
    local flagged = {}; for _, l in ipairs(r3.notBestFirst) do flagged[l] = true; end
    check('AO11 mixed: Main flagged', flagged.Main, true);
    check('AO12 mixed: Body flagged', flagged.Body, true);

    -- 4. Equal Levels are a tie, not a divergence -> best-first, no warning.
    local tie = { Main = { { Name = 'Austere Hat' }, { Name = 'Dalmatica' } } };  -- both 60
    check('AO13 equal Levels are best-first', #(simport.importStaticSet(tie, SLOTS, resolve).notBestFirst), 0);

    -- 5. Unowned candidates drop; a slot with NO owned candidate never appears (and so
    --    is not counted) -- full-replace acts on what actually resolves.
    local partial = { Main = { 'Yagrush', 'Unowned Club', 'Warp Cudgel' },  -- drop the middle
                      Sub  = { 'Nothing Owned Here' } };                    -- 0 resolved -> absent
    local r5 = simport.importStaticSet(partial, SLOTS, resolve);
    check('AO14 partial: unowned dropped from list', #r5.working.Main, 2);
    check('AO15 partial: order after drop [2]', r5.working.Main[2].rec.Name, 'Warp Cudgel');
    check('AO16 partial: best-first is judged on the resolved remainder (75 then 30)', #r5.notBestFirst, 0);
    check('AO17 partial: all-unowned slot absent', r5.working.Sub, nil);
    check('AO18 partial: only the one resolvable slot counts', r5.slotCount, 1);

    -- 6. A virtual entry (dlac:AutoStaff) is skipped by the best-first check, not read as
    --    a Level-0 candidate that would falsely flag the slot.
    local virt = { Main = { 'dlac:AutoStaff', 'Yagrush' } };
    local r6 = simport.importStaticSet(virt, SLOTS, resolve);
    check('AO19 virtual carried as candidate', #r6.working.Main, 2);
    check('AO20 virtual does not trip best-first', #r6.notBestFirst, 0);

    -- 7. Degenerate inputs never error.
    check('AO21 nil static set -> 0 slots', simport.importStaticSet(nil, SLOTS, resolve).slotCount, 0);
    check('AO22 nil resolver -> 0 slots', simport.importStaticSet(plain, SLOTS, nil).slotCount, 0);
    check('AO23 isBestFirst on empty list', simport.isBestFirst({}), true);
end)();

-- ---------------------------------------------------------------------------
-- AP. weaponfilter -- the pure weapon-type picker filter (#16 F2a, PRD #14)
--
--   Two pure decisions the Add-item picker's weapon-type dropdown is a thin shell over:
--   presentBuckets (which type buckets are actually present in a slot's candidates, in
--   canonical order, no empty buckets) and visible (is a record shown under the marked
--   type set -- {} / nil = "All"). VIEW-ONLY: never eligibility (HARD RULE 6 / ADR 0006).
-- ---------------------------------------------------------------------------
(function()
    local wf = dofile('gear/weaponfilter.lua');   -- forward slash: also loads on Linux CI
    check('AP0 presentBuckets exported', type(wf.presentBuckets), 'function');
    check('AP1 visible exported',        type(wf.visible),        'function');

    -- Candidate pool for a Warrior Main: axes + great axes + a sword, unordered by type,
    -- with a duplicate type and a nil-Type oddball (a virtual entry has no Type).
    local cands = {
        { Name = 'Woodville Axe', Type = 'Axe' },
        { Name = 'Colossal Axe',  Type = 'GreatAxe' },
        { Name = 'Barbaroi Axe',  Type = 'Axe' },        -- duplicate bucket -> one option
        { Name = 'Fransisca',     Type = 'GreatAxe' },
        { Name = 'Firangi',       Type = 'Sword' },
        { Name = 'dlac:AutoCraft', Virtual = true },      -- no Type -> no bucket
    };

    -- 1. presentBuckets: only owned types, canonical order (Sword before Axe before
    --    GreatAxe), de-duplicated, no empty buckets, no bucket for the Type-less oddball.
    local buckets = wf.presentBuckets(cands, 'Main');
    check('AP2 three buckets present',        #buckets, 3);
    check('AP3 canonical order [1] Sword',    buckets[1].key, 'Sword');
    check('AP4 canonical order [2] Axe',      buckets[2].key, 'Axe');
    check('AP5 canonical order [3] GreatAxe', buckets[3].key, 'GreatAxe');
    check('AP6 player-facing label',          buckets[3].label, 'Great Axe');

    -- 2. Empty pool / unknown slot -> no options (dropdown hidden), never an error.
    check('AP7 empty pool -> no buckets',     #wf.presentBuckets({}, 'Main'), 0);
    check('AP8 unfilterable slot -> no buckets', #wf.presentBuckets(cands, 'Head'), 0);
    check('AP9 nil cands -> no buckets',      #wf.presentBuckets(nil, 'Main'), 0);

    -- 3. visible: {} / nil = "All" -> everything shows.
    check('AP10 empty marks = All (axe)',   wf.visible(cands[1], {}, 'Main'), true);
    check('AP11 nil marks = All (sword)',   wf.visible(cands[5], nil, 'Main'), true);

    -- 4. visible: a single marked type shows only that bucket.
    local onlyAxe = { Axe = true };
    check('AP12 marked Axe shows Axe',        wf.visible(cands[1], onlyAxe, 'Main'), true);
    check('AP13 marked Axe hides GreatAxe',   wf.visible(cands[2], onlyAxe, 'Main'), false);
    check('AP14 marked Axe hides Sword',      wf.visible(cands[5], onlyAxe, 'Main'), false);

    -- 5. Multi-pick: Axe + GreatAxe shows both, still hides Sword.
    local axes = { Axe = true, GreatAxe = true };
    check('AP15 multi shows Axe',      wf.visible(cands[1], axes, 'Main'), true);
    check('AP16 multi shows GreatAxe', wf.visible(cands[2], axes, 'Main'), true);
    check('AP17 multi hides Sword',    wf.visible(cands[5], axes, 'Main'), false);

    -- 6. A record with no bucket (virtual / Type-less) is hidden once ANY type is marked,
    --    but shows under "All".
    check('AP18 no-bucket hidden when narrowed', wf.visible(cands[6], onlyAxe, 'Main'), false);
    check('AP19 no-bucket shown under All',       wf.visible(cands[6], {}, 'Main'), true);

    -- 7. Unfilterable slot: a marked filter can't leak in (the predicate is All-open there
    --    only via empty marks; a non-empty mark on an unknown slot hides everything, which
    --    is moot because gearui never shows the dropdown for such a slot).
    check('AP20 bucketOf unknown slot -> nil', wf.bucketOf(cands[1], 'Head'), nil);
end)();

-- APL. weaponfilter legacy Type spellings (Henrik 2026-07-18: Mindie's Lv20
--   Savagery, Type = "Great Axe" WITH a space, vanished under the Great Axe
--   filter while name search found it). Early gear.lua vocabularies wrote
--   display forms; a scan never rewrites an existing entry, so real files mix
--   'Great Axe'/'GreatAxe', 'Hand-to-Hand'/'HandToHand', 'Wind Instrument',
--   bare 'String'... Buckets resolve through normalization (strip
--   non-alphanumerics + casefold + alias) so both spellings are ONE bucket.
-- ---------------------------------------------------------------------------
(function()
    local wf = dofile('gear/weaponfilter.lua');
    -- THE field case: a spaced-Type record is visible under its canonical mark
    check('APL1 Savagery: spaced Type buckets canonically',
        wf.bucketOf({ Name = 'Savagery', Type = 'Great Axe' }, 'Main'), 'GreatAxe');
    check('APL2 ...so the Great Axe mark shows it',
        wf.visible({ Name = 'Savagery', Type = 'Great Axe' }, { GreatAxe = true }, 'Main'), true);
    check('APL3 hyphen drift: Hand-to-Hand', wf.bucketOf({ Type = 'Hand-to-Hand' }, 'Main'), 'HandToHand');
    check('APL4 case drift alone heals too', wf.bucketOf({ Type = 'greataxe' }, 'Main'), 'GreatAxe');
    check('APL5 Range: spaced instrument', wf.bucketOf({ Type = 'Wind Instrument' }, 'Range'), 'WindInstrument');
    check('APL6 Range: legacy bare String aliases', wf.bucketOf({ Type = 'String' }, 'Range'), 'StringInstrument');
    check('APL7 Sub: one-hander with case drift', wf.bucketOf({ Type = 'sword' }, 'Sub'), 'Sword');
    check('APL8 unknown types still pass through', wf.bucketOf({ Type = 'Chainsaw' }, 'Main'), 'Chainsaw');
    -- both spellings in one pool -> ONE dropdown bucket, not two "Great Axe" twins
    local buckets = wf.presentBuckets({
        { Name = 'Savagery',     Type = 'Great Axe' },
        { Name = 'Colossal Axe', Type = 'GreatAxe'  },
    }, 'Main');
    check('APL9 mixed spellings merge to one bucket', #buckets, 1);
    check('APL10 ...the canonical one', buckets[1].key .. '/' .. buckets[1].label, 'GreatAxe/Great Axe');
end)();

-- AP2. weaponfilter Range + Ammo -- the F2b buckets (issue #17, PRD #14)
--
--   Range buckets off the catalog `Type`: Bows (Archery), Guns & Crossbows (Marksmanship
--   -- guns and crossbows folded together), Throwing, plus instruments / rod when owned.
--   Ammo buckets off `AmmoType`: Arrows (Archery), Bolts & Bullets (Marksmanship -- bolts
--   and bullets folded), Throwables (Throwing), and Trinkets (ammo with NO AmmoType, fired
--   by nothing -- Cinderstone, Morion Tathlum). View-only, same as Main (HARD RULE 6).
-- ---------------------------------------------------------------------------
(function()
    local wf = dofile('gear/weaponfilter.lua');

    -- 1. Range: a bow + a crossbow + a gun + a harp + a fishing rod, unordered, with a gun
    --    and a crossbow sharing the Marksmanship bucket (guns & crossbows folded together).
    local range = {
        { Name = 'Test Harp',      Type = 'StringInstrument' },
        { Name = 'Test Bow',       Type = 'Archery' },
        { Name = 'Test Crossbow',  Type = 'Marksmanship' },
        { Name = 'Test Gun',       Type = 'Marksmanship' },   -- same bucket as the crossbow
        { Name = 'Test Rod',       Type = 'FishingRod' },
    };
    local rb = wf.presentBuckets(range, 'Range');
    check('AP2-1 range: four buckets (gun+xbow fold)', #rb, 4);
    check('AP2-2 canonical order [1] Archery',   rb[1].key, 'Archery');
    check('AP2-3 Archery labelled Bows',         rb[1].label, 'Bows');
    check('AP2-4 canonical order [2] Marksmanship', rb[2].key, 'Marksmanship');
    check('AP2-5 Marksmanship label folds both', rb[2].label, 'Guns & Crossbows');
    check('AP2-6 instruments before the rod',    rb[3].key, 'StringInstrument');
    check('AP2-7 fishing rod its own bucket',    rb[4].key, 'FishingRod');
    -- Guns & Crossbows marked: shows both the gun and the crossbow, hides the bow.
    local onlyMarks = { Marksmanship = true };
    check('AP2-8 Marks shows crossbow',  wf.visible(range[3], onlyMarks, 'Range'), true);
    check('AP2-9 Marks shows gun',       wf.visible(range[4], onlyMarks, 'Range'), true);
    check('AP2-10 Marks hides bow',      wf.visible(range[2], onlyMarks, 'Range'), false);

    -- 2. Ammo: arrows + bolts + bullets + a throwable + two trinkets (no AmmoType). Bolts
    --    and bullets fold into one Marksmanship bucket; the trinkets are their own bucket
    --    and must NOT land under arrows / bolts / throwables.
    local ammo = {
        { Name = 'Test Bolt',       AmmoType = 'Marksmanship' },
        { Name = 'Test Arrow',      AmmoType = 'Archery' },
        { Name = 'Test Bullet',     AmmoType = 'Marksmanship' },   -- folds with the bolt
        { Name = 'Test Shuriken',   AmmoType = 'Throwing' },
        { Name = 'Cinderstone' },                                   -- no AmmoType = Trinket
        { Name = 'Morion Tathlum' },                                -- no AmmoType = Trinket
    };
    local ab = wf.presentBuckets(ammo, 'Ammo');
    check('AP2-11 ammo: four buckets (bolt+bullet fold)', #ab, 4);
    check('AP2-12 order [1] Arrows',          ab[1].label, 'Arrows');
    check('AP2-13 order [2] Bolts & Bullets', ab[2].label, 'Bolts & Bullets');
    check('AP2-14 order [3] Throwables',      ab[3].label, 'Throwables');
    check('AP2-15 order [4] Trinkets',        ab[4].label, 'Trinkets');
    -- The Trinket bucket key is the internal sentinel, never a real AmmoType.
    local trinketKey = ab[4].key;
    check('AP2-16 trinket bucketOf Cinderstone', wf.bucketOf(ammo[5], 'Ammo'), trinketKey);
    check('AP2-17 trinket key is not an AmmoType', ammo[1].AmmoType == trinketKey, false);
    -- Bolts & Bullets marked: shows bolt + bullet, hides arrows / throwables / trinkets.
    local onlyBolts = { [ab[2].key] = true };
    check('AP2-18 Marks shows bolt',    wf.visible(ammo[1], onlyBolts, 'Ammo'), true);
    check('AP2-19 Marks shows bullet',  wf.visible(ammo[3], onlyBolts, 'Ammo'), true);
    check('AP2-20 Marks hides arrow',   wf.visible(ammo[2], onlyBolts, 'Ammo'), false);
    check('AP2-21 Marks hides trinket', wf.visible(ammo[5], onlyBolts, 'Ammo'), false);
    -- Trinkets marked: the two sticks show, the fired ammo hides -- the AC's exclusion.
    local onlyTrinket = { [trinketKey] = true };
    check('AP2-22 Trinket shows Cinderstone',  wf.visible(ammo[5], onlyTrinket, 'Ammo'), true);
    check('AP2-23 Trinket shows Morion',       wf.visible(ammo[6], onlyTrinket, 'Ammo'), true);
    check('AP2-24 Trinket hides arrow',        wf.visible(ammo[2], onlyTrinket, 'Ammo'), false);
    check('AP2-25 Trinket hides bolt',         wf.visible(ammo[1], onlyTrinket, 'Ammo'), false);
    check('AP2-26 Trinket hides throwable',    wf.visible(ammo[4], onlyTrinket, 'Ammo'), false);

    -- 3. Present-only + All default carry over to the new slots.
    check('AP2-27 empty ammo pool -> no buckets', #wf.presentBuckets({}, 'Ammo'), 0);
    check('AP2-28 All default shows a trinket',   wf.visible(ammo[5], {}, 'Ammo'), true);
    check('AP2-29 arrows-only range pool -> one bucket',
        #wf.presentBuckets({ { Name = 'Bow', Type = 'Archery' } }, 'Range'), 1);
end)();

-- ---------------------------------------------------------------------------
-- TG. Trigger Groups (G1, ADR 0009): a named action-list matcher generalizing
--     modes. M.groupMatch mirrors M.modeActive's one-of (list = OR) semantics;
--     `group` is specificity tier 45 (below name 50, above contains 40); the
--     Groups section load->serialize is byte-stable beside Modes.
-- ---------------------------------------------------------------------------
(function()
    local groups = {
        StrBlue = { 'Hysteric Barrage', 'Quad. Continuum' },
        MndBlue = { 'Magic Hammer', 'Actinic Burst' },
    };
    -- membership
    check('TG1 member of group',        dispatchM.groupMatch('StrBlue', 'Hysteric Barrage', groups), true);
    check('TG2 non-member',             dispatchM.groupMatch('StrBlue', 'Magic Hammer', groups), false);
    check('TG3 group name CI',          dispatchM.groupMatch('strblue', 'Quad. Continuum', groups), true);
    check('TG4 member name CI',         dispatchM.groupMatch('StrBlue', 'hysteric barrage', groups), true);
    check('TG5 unknown group',          dispatchM.groupMatch('NoSuchGroup', 'Hysteric Barrage', groups), false);
    check('TG6 nil action name',        dispatchM.groupMatch('StrBlue', nil, groups), false);
    -- list value = OR (one-of), exactly like mode lists
    check('TG7 list: first group hits', dispatchM.groupMatch({ 'StrBlue', 'MndBlue' }, 'Hysteric Barrage', groups), true);
    check('TG8 list: second group hits',dispatchM.groupMatch({ 'StrBlue', 'MndBlue' }, 'Actinic Burst', groups), true);
    check('TG9 list: none match',       dispatchM.groupMatch({ 'StrBlue', 'MndBlue' }, 'Head Butt', groups), false);

    -- specificity tier 45: group is a baseline a per-spell `name` overrides, and
    -- it still beats contains / skill.
    check('TG10 group default priority', dispatchM.defaultPriority({ group = 'StrBlue' }), 45);
    check('TG11 name overrides group',   dispatchM.defaultPriority({ group = 'StrBlue', name = 'Quad. Continuum' }), 50);
    check('TG12 group beats contains',   dispatchM.defaultPriority({ group = 'StrBlue' }) > dispatchM.defaultPriority({ contains = 'Continuum' }), true);
    check('TG13 group beats skill',      dispatchM.defaultPriority({ group = 'StrBlue', skill = 'Blue Magic' }), 45);

    -- Groups section load -> serialize is byte-stable alongside Modes, and does
    -- not disturb the handler/mode sections.
    local data = {
        Midcast = {
            { when = { group = 'StrBlue' }, set = 'StrBluGear' },
            { when = { group = { 'StrBlue', 'MndBlue' } }, set = 'AnyBluGear' },
        },
        Modes  = { Weapon = { values = { 'Melee', 'Ranged' }, bind = '^F3' } },
        Groups = groups,
    };
    local text = dispatchM.serializeTriggers(data);
    check('TG14 group condition serialized', text:find('group = "StrBlue"', 1, true) ~= nil, true);
    check('TG15 group list serialized',      text:find('group = { "StrBlue", "MndBlue" }', 1, true) ~= nil, true);
    check('TG16 Groups section present',      text:find('Groups = {', 1, true) ~= nil, true);
    check('TG17 members preserved in order',  text:find('%["StrBlue"%] = { "Hysteric Barrage", "Quad. Continuum" }') ~= nil, true);
    check('TG18 Modes section still present', text:find('Modes = {', 1, true) ~= nil, true);
    -- load back and re-serialize: identical bytes (round-trip stable)
    local t2 = (loadstring or load)(text)();
    check('TG19 reloads to a table', type(t2), 'table');
    check('TG20 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
end)();

-- ---------------------------------------------------------------------------
-- TM. triggermodel.fromRaw -- the GUI-side raw->edit-model translation (moved
--     out of triggersui; pure, canonEvent injected). THE WIPE CONTRACT: Commit
--     serializes the WHOLE model, so every section serializeTriggers can emit
--     must survive fromRaw or the next Commit erases it (the SetOptions/Modes
--     lesson -- that bug shipped once). TM2 is the contract; the rest pin the
--     normalization the old in-triggersui copy never had a test for.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\gear\\groupsmodel'] = package.loaded['dlac\\gear\\groupsmodel'] or dofile('gear/groupsmodel.lua');
    local tmodel = dofile('gear/triggermodel.lua');

    -- A maximal file: every field + section the serializer can emit. Written by
    -- the real serializer, reloaded, translated, re-serialized -- byte-stable.
    local text = dispatchM.serializeTriggers({
        Precast = {
            { when = { skill = 'Enfeebling Magic' }, set = 'FastCast', priority = 12 },
        },
        Midcast = {
            { when = { name = 'Slow II' }, whenAny = { { mode = 'DT' }, { hpbelow = 50 } }, set = { 'MidA', 'MidB' } },
            { when = { group = 'StrBlue' }, equip = { Waist = 'Karin Obi', Head = 'Zha Xia Hat' } },
        },
        Modes  = { Weapon = { values = { 'Melee', 'Ranged' }, bind = '^F3' }, DT = { values = { 'On', 'Off' } } },
        Groups = { StrBlue = { 'Hysteric Barrage', 'Quad. Continuum' } },
    });
    local rawT = (loadstring or load)(text)();
    check('TM1 maximal fixture reloads', type(rawT), 'table');
    local model = tmodel.fromRaw(rawT, dispatchM.canonEvent);
    check('TM2 WIPE CONTRACT model round-trip byte-stable', dispatchM.serializeTriggers(model) == text, true);

    -- Normalization: condition keys lowercase, priority numeric, list shapes kept.
    check('TM3 when keys lowercased',      model.Precast[1].when.skill, 'Enfeebling Magic');
    check('TM4 priority numeric',          model.Precast[1].priority, 12);
    check('TM5 multi-set stays ordered',   model.Midcast[1].set[2], 'MidB');
    check('TM6 whenAny entries carried',   model.Midcast[1].whenAny[2].hpbelow, 50);
    check('TM7 equip payload carried',     model.Midcast[2].equip.Waist, 'Karin Obi');
    check('TM8 Modes carried',             model.Modes.Weapon.bind, '^F3');
    check('TM9 Groups carried',            model.Groups.StrBlue[2], 'Quad. Continuum');

    -- Handler keys canon through the INJECTED fn; unknown sections dropped.
    local m2 = tmodel.fromRaw({ midCAST = { { when = { name = 'X' }, set = 'S' } },
                                Junk    = { { when = {}, set = 'S' } } }, dispatchM.canonEvent);
    check('TM10 handler key canonicalized', type(m2.Midcast), 'table');
    check('TM11 unknown section dropped',   m2.Junk, nil);

    -- Malformed rules are skipped, never carried as garbage.
    local m3 = tmodel.fromRaw({ Midcast = { { set = 'NoWhen' }, { when = { name = 'Y' } }, 'junk' } }, dispatchM.canonEvent);
    check('TM12 malformed rules skipped', #m3.Midcast, 0);

    -- Legacy spellings: whenany, modes, bare mode-value arrays; 1-item set list collapses.
    local m4 = tmodel.fromRaw({ Midcast = { { when = { name = 'Z' }, whenany = { { mode = 'DT' } }, set = { 'OnlyOne' } } },
                                modes = { Idle = { 'On', 'Off' } } }, dispatchM.canonEvent);
    check('TM13 legacy whenany accepted',   m4.Midcast[1].whenAny[1].mode, 'DT');
    check('TM14 1-item set list collapses', m4.Midcast[1].set, 'OnlyOne');
    check('TM15 legacy bare modes array',   m4.Modes.Idle.values[2], 'Off');

    -- No canonEvent: handler sections unreachable, Modes/Groups still carried --
    -- the degraded no-dispatch behavior the Triggers tab always had.
    local m6 = tmodel.fromRaw({ Midcast = { { when = { name = 'X' }, set = 'S' } },
                                Modes = { A = { values = { 'B' } } },
                                Groups = { G = { 'x' } } }, nil);
    check('TM16 no-canon drops handlers', m6.Midcast, nil);
    check('TM17 no-canon keeps Modes',    m6.Modes.A.values[1], 'B');
    check('TM18 no-canon keeps Groups',   m6.Groups.G[1], 'x');
    check('TM19 non-table raw yields {}', next(tmodel.fromRaw(nil, dispatchM.canonEvent)), nil);

    -- Bare toggle definitions (2026-07-20, Mindie BLU): a toggle with no bind
    -- and no values is a REAL definition -- `[name] = {}` must survive the
    -- whole wipe contract, or a plain UI-created toggle vanishes from the
    -- Modes list on the next load.
    local tg = dispatchM.serializeTriggers({ Modes = { Stoneskin = {}, DT = { bind = 'F9' } } });
    check('TM20 bare toggle serialized', tg:find('["Stoneskin"] = {},', 1, true) ~= nil, true);
    local tgM = tmodel.fromRaw((loadstring or load)(tg)(), dispatchM.canonEvent);
    check('TM21 bare toggle survives fromRaw', type(tgM.Modes.Stoneskin) == 'table'
        and tgM.Modes.Stoneskin.values == nil and tgM.Modes.Stoneskin.bind == nil, true);
    check('TM22 bare toggle round-trip byte-stable', dispatchM.serializeTriggers(tgM) == tg, true);
end)();

-- ---------------------------------------------------------------------------
-- PM. Player-state trigger conditions (v53): hpBelow/hpAbove, mpBelow/mpAbove,
--     tpBelow/tpAbove (strict compares off ctx.player) and buff/buffNot (the
--     per-dispatch buff set; tests inject ctx.buffs -- the seam the matchers
--     read first). Unreadable state matches NEITHER polarity: a failed read
--     must never flap gear on OR off.
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local ctx = { player = { HPP = 40, MPP = 80, TP = 1200 } };
    check('PM1 hpBelow fires under the line',   mm.hpbelow(50, ctx), true);
    check('PM2 hpBelow strict at the line',     mm.hpbelow(40, ctx), false);
    check('PM3 hpAbove quiet under the line',   mm.hpabove(50, ctx), false);
    check('PM4 mpAbove fires over the line',    mm.mpabove(50, ctx), true);
    check('PM5 mpBelow quiet over the line',    mm.mpbelow(50, ctx), false);
    check('PM6 tpAbove fires at 1200 > 1000',   mm.tpabove(1000, ctx), true);
    check('PM7 tpBelow quiet at 1200',          mm.tpbelow(1000, ctx), false);
    check('PM8 string threshold coerces',       mm.hpbelow('50', ctx), true);
    check('PM9 nil player never matches',       mm.hpbelow(50, {}), false);
    check('PM10 junk threshold never matches',  mm.hpbelow('half', ctx), false);
    local bctx = { buffs = { sleep = true, [2] = true, refresh = true } };
    check('PM11 buff by name, case-insensitive', mm.buff('Sleep', bctx), true);
    check('PM12 buff by id',                     mm.buff(2, bctx), true);
    check('PM13 buff absent',                    mm.buff('Haste', bctx), false);
    check('PM14 buffNot fires when absent',      mm.buffnot('Haste', bctx), true);
    check('PM15 buffNot quiet when present',     mm.buffnot('Refresh', bctx), false);
    -- Unknown state: kill the game read entirely -- both polarities stay quiet.
    local savedAC = AshitaCore;
    AshitaCore = nil;
    local dead = {};
    check('PM16 unreadable buffs: buff quiet',    mm.buff('Sleep', dead), false);
    check('PM17 unreadable buffs: buffNot quiet', mm.buffnot('Sleep', dead), false);
    AshitaCore = savedAC;
    -- Tier + pretty-case + round-trip: the new keys are first-class vocabulary.
    check('PM18 default priority just under mode',
        dispatchM.defaultPriority({ hpbelow = 50, name = 'Cure IV' }), 95);
    local text = dispatchM.serializeTriggers({
        Default = { { when = { hpbelow = 50, buffnot = 'Refresh' }, set = 'LowHp' } },
    });
    check('PM19 pretty keys serialize', text:find('hpBelow = 50', 1, true) ~= nil, true);
    check('PM20 buffNot serializes',    text:find('buffNot = "Refresh"', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('PM21 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
end)();

-- ---------------------------------------------------------------------------
-- PN. Player conditions v54: canonical raw + percent keys (playerHPBelow/...)
--     and the whenAny OR group -- a rule matches when ALL `when` conditions
--     hold OR ANY whenAny entry holds; an OR-only rule is NOT always-on.
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local ctx = { player = { HP = 320, HPP = 40, MP = 90, MPP = 75, TP = 1200 } };
    check('PN1 raw HP below',            mm.playerhpbelow(500, ctx), true);
    check('PN2 raw HP not below',        mm.playerhpbelow(300, ctx), false);
    check('PN3 percent HP below',        mm.playerhppercentbelow(50, ctx), true);
    check('PN4 raw vs percent distinct', mm.playerhpabove(300, ctx) and not mm.playerhppercentabove(50, ctx), true);
    check('PN5 raw MP above',            mm.playermpabove(50, ctx), true);
    check('PN6 percent MP below quiet',  mm.playermppercentbelow(75, ctx), false);
    check('PN7 v53 alias still percent', mm.hpbelow(50, ctx), true);

    -- OR-group evaluation through the engine's own matches()
    local mt = dispatchM._matches;
    local bctx = { player = { HPP = 90 }, buffs = { sleep = true } };
    local r1 = { when = { hpbelow = 50 },
                 whenAny = { { buff = 'Lullaby' }, { buff = 'Sleep' } } };
    check('PN8 AND misses, OR hits -> match', mt(r1, bctx), true);
    local r2 = { when = { hpbelow = 95 },
                 whenAny = { { buff = 'Lullaby' } } };
    check('PN9 AND hits, OR misses -> match', mt(r2, bctx), true);
    local r3 = { when = { hpbelow = 50 },
                 whenAny = { { buff = 'Lullaby' } } };
    check('PN10 both legs miss -> no match', mt(r3, bctx), false);
    local r4 = { when = {}, whenAny = { { buff = 'Haste' } } };
    check('PN11 OR-only rule is NOT always-on', mt(r4, bctx), false);
    local r5 = { when = {}, whenAny = { { buff = 'Sleep' } } };
    check('PN12 OR-only rule fires on its hit', mt(r5, bctx), true);
    check('PN13 no whenAny keeps legacy any-shape', mt({ when = {} }, bctx), true);
    local r6 = { when = {}, whenAny = { { buff = 'Sleep', hpbelow = 50 } } };
    check('PN14 multi-key OR entry is AND within', mt(r6, bctx), false);

    -- normalize: whenAny parsed, priority from OR keys, label carries the OR leg
    local norm = dispatchM._normalize({
        Default = { { when = { status = 'Engaged' },
                      whenAny = { { buff = 'Sleep' }, { buff = 'Lullaby' } },
                      set = 'WakeUp' } },
    });
    local nr = norm.Default[1];
    check('PN15 whenAny normalized', #nr.whenAny, 2);
    check('PN16 OR keys raise the default priority', nr.prio, 95);
    check('PN17 label carries the OR leg',
        nr.label, 'status=Engaged|buff=Lullaby|buff=Sleep');
    local bad = select(2, dispatchM._normalize({
        Default = { { when = { any = true }, whenAny = { { nosuchcond = 1 } }, set = 'X' } },
    }));
    check('PN18 unknown OR key drops the rule with a warn', #bad >= 1, true);
    check('PN19 defaultPriority takes whenAny',
        dispatchM.defaultPriority({ status = 'Engaged' }, { { buff = 'Sleep' } }), 95);

    -- serializer: whenAny round-trip byte-stable, canonical pretty keys
    local text = dispatchM.serializeTriggers({
        Default = { { when = { playerhppercentbelow = 50 },
                      whenAny = { { buff = 'Lullaby' }, { buff = 'Sleep' } },
                      set = 'WakeUp' } },
    });
    check('PN20 canonical pretty key serializes',
        text:find('playerHPPercentBelow = 50', 1, true) ~= nil, true);
    check('PN21 whenAny serializes in author order',
        text:find('whenAny = { { buff = "Lullaby" }, { buff = "Sleep" } }', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('PN22 OR round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
end)();

-- ---------------------------------------------------------------------------
-- PT. Pet conditions (engine v63): pet / petStatus / petName off ctx.pet
--     (gData.GetPet() -- nil petless AND at pet HPP 0, so a dead pet reads as
--     NO pet: pet=false fires). petStatus/petName IMPLY existence -- they must
--     never match a petless job (petStatus='Idle' is not "no pet"). Tiers 22/23
--     sit between status (20) and moving (25): a pet-refined rule outranks its
--     base status rule with no hand priority; petName is identity (name tier).
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local petless = { player = { Status = 'Idle' } };
    local out = { player = { Status = 'Idle' },
                  pet = { Name = 'Garuda', Status = 'Engaged', HPP = 100, TP = 0 } };
    check('PT1 pet=true fires with a pet out',    mm.pet(true, out), true);
    check('PT2 pet=true quiet petless',           mm.pet(true, petless), false);
    check('PT3 pet=false fires petless',          mm.pet(false, petless), true);
    check('PT4 pet=false quiet with a pet out',   mm.pet(false, out), false);
    check('PT5 petStatus matches case-insensitively', mm.petstatus('engaged', out), true);
    check('PT6 petStatus wrong state quiet',      mm.petstatus('Idle', out), false);
    check('PT7 petStatus NEVER matches petless',  mm.petstatus('Idle', petless), false);
    check('PT8 petName matches case-insensitively', mm.petname('garuda', out), true);
    check('PT9 petName other pet quiet',          mm.petname('Carbuncle', out), false);
    check('PT10 petName petless quiet',           mm.petname('Garuda', petless), false);
    -- Tier ordering (the overlay ladder, no hand priorities anywhere):
    check('PT11 status+pet outranks bare status',
        dispatchM.defaultPriority({ status = 'Engaged', pet = true })
            > dispatchM.defaultPriority({ status = 'Engaged' }), true);
    check('PT12 petStatus outranks pet-exists',
        dispatchM.defaultPriority({ petstatus = 'Engaged' })
            > dispatchM.defaultPriority({ pet = true }), true);
    check('PT13 moving still overlays petStatus',
        dispatchM.defaultPriority({ moving = true })
            > dispatchM.defaultPriority({ petstatus = 'Engaged' }), true);
    check('PT14 petName sits at the name tier',
        dispatchM.defaultPriority({ petname = 'Garuda' }), 50);
    -- The player x pet 2x2 through the engine's own matches() -- the classic
    -- BST postures, incl. "master idle while the pet fights".
    local mt = dispatchM._matches;
    local r = { when = { status = 'Idle', petstatus = 'Engaged' } };
    check('PT15 idle + pet fighting fires',
        mt(r, { player = { Status = 'Idle' }, pet = { Status = 'Engaged' } }), true);
    check('PT16 same rule quiet when the pet idles',
        mt(r, { player = { Status = 'Idle' }, pet = { Status = 'Idle' } }), false);
    -- Serializer: pretty spellings round-trip byte-stable, pet = false included
    -- (false is a real value -- it must not vanish like nil).
    local text = dispatchM.serializeTriggers({
        Default = {
            { when = { status = 'Idle', petstatus = 'Engaged' }, set = 'Idle_PetFight' },
            { when = { pet = false }, set = 'NoPet' },
            { when = { petname = 'Carbuncle' }, set = 'Perp_Carby' },
        },
    });
    check('PT17 petStatus serializes pretty', text:find('petStatus = "Engaged"', 1, true) ~= nil, true);
    check('PT18 pet = false serializes',      text:find('pet = false', 1, true) ~= nil, true);
    check('PT19 petName serializes pretty',   text:find('petName = "Carbuncle"', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('PT20 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
    -- normalize: the new keys are first-class vocabulary, priorities derive.
    local norm = dispatchM._normalize({
        Default = { { when = { status = 'Idle', petStatus = 'Engaged' }, set = 'Idle_PetFight' } },
    });
    check('PT21 normalize keeps pet keys', norm.Default ~= nil and #norm.Default, 1);
    check('PT22 normalized prio = petStatus tier', norm.Default[1].prio, 23);
end)();

-- ---------------------------------------------------------------------------
-- TG. Target condition (engine v81): WHO the action is aimed at; v1 value
--     'Self'. ctx.targetSelf is the injected seam (live: GetActionTarget's
--     entity index vs my own party index, one read per dispatch); tri-state --
--     nil = unknown (Default handler, failed read) matches NOTHING, so a
--     target rule never fires blind. Tier 55: a self-refined rule overlays
--     its base name/contains/group rule with no hand priority, under the
--     Automations band (60).
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local selfCast  = { action = { Name = 'Curing Waltz III' }, targetSelf = true };
    local otherCast = { action = { Name = 'Curing Waltz III' }, targetSelf = false };
    local unknown   = { action = { Name = 'Curing Waltz III' } };   -- no seam, stub gData has no GetActionTarget
    check('TG1 target=Self fires on a self-cast',     mm.target('Self', selfCast), true);
    check('TG2 target=Self quiet on another target',  mm.target('Self', otherCast), false);
    check('TG3 target matches case-insensitively',    mm.target('self', selfCast), true);
    check('TG4 unknown target matches NOTHING',       mm.target('Self', unknown), false);
    check('TG5 unknown VALUE never matches',          mm.target('Enemy', selfCast), false);
    -- Tier ladder: the self-refinement overlays its base rule (name 50,
    -- contains 40) with no hand priority, and stays under player gates / mode.
    check('TG6 target sits at 55', dispatchM.defaultPriority({ target = 'Self' }), 55);
    check('TG7 name+target outranks bare name',
        dispatchM.defaultPriority({ name = 'Curing Waltz III', target = 'Self' })
            > dispatchM.defaultPriority({ name = 'Curing Waltz III' }), true);
    check('TG8 mode still outranks target',
        dispatchM.defaultPriority({ mode = 'DT' })
            > dispatchM.defaultPriority({ target = 'Self' }), true);
    -- Henrik's waltz pair through the engine's own matches(): the base rule
    -- fires either way, the Self rule only on the self-cast -- the overlay
    -- (55 > 40) puts VIT+CHR on top of the plain CHR set.
    local mt = dispatchM._matches;
    local base     = { when = { contains = 'Waltz' } };
    local selfRule = { when = { contains = 'Waltz', target = 'Self' } };
    check('TG9 base waltz rule fires on a self-cast', mt(base, selfCast), true);
    check('TG10 self rule fires on a self-cast',      mt(selfRule, selfCast), true);
    check('TG11 self rule quiet on another target',   mt(selfRule, otherCast), false);
    check('TG12 base rule still fires on others',     mt(base, otherCast), true);
    -- Serializer + normalize: first-class vocabulary, round-trips byte-stable.
    local text = dispatchM.serializeTriggers({
        Ability = { { when = { contains = 'Waltz', target = 'Self' }, set = 'Waltz_Self' } },
    });
    check('TG13 target serializes', text:find('target = "Self"', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('TG14 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
    local norm = dispatchM._normalize({
        Ability = { { when = { name = 'Curing Waltz III', target = 'Self' }, set = 'Waltz_Self' } },
    });
    check('TG15 normalize keeps target', norm.Ability ~= nil and #norm.Ability, 1);
    check('TG16 normalized prio = target tier', norm.Ability[1].prio, 55);
end)();

-- ---------------------------------------------------------------------------
-- IT. inTown condition (engine v84): am I standing in a town? Town = the
--     curated data/zones.lua set -- server CITY zonetype + Nashmau, minus
--     combat-staging CITY zones (tools/gen_zones.py). ctx.zone is the injected
--     seam (live: GetParty():GetMemberZone(0), one read/dispatch); an unknown
--     zone (nil) matches NEITHER polarity, so the rule never fires blind. Tier
--     95 (location gate): a town show-off set overlays the plain Idle set, under
--     mode. Loader lowercases inTown -> intown + TIER-validates it (IT21/IT22).
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local sandoria = { zone = 230 };   -- Southern San d'Oria: server CITY -> town
    local celennia = { zone = 284 };   -- Celennia Memorial Library: SoA zone, CITY -> town (the Wings-hub case)
    local nashmau  = { zone = 53  };   -- Nashmau: server types OUTDOORS -> town ONLY via the curated ADD
    local sealions = { zone = 32  };   -- Sealion's Den: server CITY, but curated-DROPPED (combat staging)
    local channel  = { zone = 1   };   -- Phanauet Channel: OUTDOORS, plainly not a town
    check('IT1 inTown=true fires in a city',           mm.intown(true,  sandoria), true);
    check('IT2 inTown=true fires in Celennia (Wings)', mm.intown(true,  celennia), true);
    check('IT3 curated ADD: Nashmau counts as town',   mm.intown(true,  nashmau),  true);
    check('IT4 curated DROP: Sealions Den not town',   mm.intown(true,  sealions), false);
    check('IT5 inTown=true quiet out in the field',    mm.intown(true,  channel),  false);
    check('IT6 inTown=false fires out in the field',   mm.intown(false, channel),  true);
    check('IT7 inTown=false quiet in a city',          mm.intown(false, sandoria), false);
    check('IT8 inTown=false quiet in Nashmau',         mm.intown(false, nashmau),  false);
    check('IT9 zone 0 (demo stub) is not a town',      mm.intown(true,  { zone = 0 }), false);
    -- Unknown zone (failed / headless read) matches NEITHER polarity. Force the
    -- live read to fail by nil-ing AshitaCore (harness idiom, ~line 116); restore.
    local savedAshita = AshitaCore;
    AshitaCore = nil;
    check('IT10 unknown zone quiet (inTown=true)',     mm.intown(true,  {}), false);
    check('IT11 unknown zone quiet (inTown=false)',    mm.intown(false, {}), false);
    AshitaCore = savedAshita;
    -- Tier ladder: the 95 location gate overlays the plain Idle set, under mode.
    check('IT12 inTown sits at 95', dispatchM.defaultPriority({ inTown = true }), 95);
    check('IT13 idle+inTown overlays plain idle',
        dispatchM.defaultPriority({ status = 'Idle', inTown = true })
            > dispatchM.defaultPriority({ status = 'Idle' }), true);
    check('IT14 mode still outranks inTown',
        dispatchM.defaultPriority({ mode = 'DT' })
            > dispatchM.defaultPriority({ inTown = true }), true);
    -- The headline scenario through the engine's own matches(): {Idle, inTown}
    -- fires standing in town, quiet in the field; the base idle rule fires both.
    -- (matches() sees post-load keys -> lowercase 'intown'.)
    local mt = dispatchM._matches;
    local base     = { when = { status = 'Idle' } };
    local townRule = { when = { status = 'Idle', intown = true } };
    local idleTown  = { player = { Status = 'Idle' }, zone = 230 };
    local idleField = { player = { Status = 'Idle' }, zone = 1 };
    check('IT15 base idle rule fires in town',       mt(base, idleTown),  true);
    check('IT16 town rule fires idle in town',       mt(townRule, idleTown),  true);
    check('IT17 town rule quiet idle in the field',  mt(townRule, idleField), false);
    check('IT18 base idle rule still fires in field',mt(base, idleField), true);
    -- First-class vocabulary: PRETTY-case inTown serializes + round-trips, and
    -- _normalize accepts it (loader lowercases + TIER-validates) at prio 95.
    local text = dispatchM.serializeTriggers({
        Default = { { when = { status = 'Idle', inTown = true }, set = 'ShowOff' } },
    });
    check('IT19 inTown serializes PRETTY-case', text:find('inTown', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('IT20 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
    local norm = dispatchM._normalize({
        Default = { { when = { status = 'Idle', inTown = true }, set = 'ShowOff' } },
    });
    check('IT21 normalize keeps inTown rule', norm.Default ~= nil and #norm.Default, 1);
    check('IT22 normalized prio = 95',        norm.Default[1].prio, 95);
end)();

-- ---------------------------------------------------------------------------
-- TGM. Trigger Groups model (G2, issue #25, ADR 0009): the pure GUI-side CRUD +
--      name / member validation the Groups tab drives (groupsmodel.lua). Group
--      names and member names compare case-insensitively (engine parity), an
--      empty member list is legal, and fromRaw sanitizes the file's Groups section
--      into the model so a Commit round-trips it (the SetOptions/Modes wipe lesson).
-- ---------------------------------------------------------------------------
(function()
    local gmod = dofile('gear/groupsmodel.lua');
    check('TGM0 module loads', type(gmod), 'table');

    -- fromRaw: sanitize + carry-through (name -> string-member array).
    local raw = { Groups = {
        StrBlue = { 'Hysteric Barrage', 'Quad. Continuum' },
        Empty   = {},                                  -- a group still being built (kept)
        Junk    = 'not a table',                       -- dropped
        [5]     = { 'x' },                             -- non-string name dropped
        Mixed   = { 'Ok', '', 42, 'Two' },             -- blanks / non-strings dropped
    } };
    local g = gmod.fromRaw(raw);
    check('TGM1 fromRaw StrBlue members',   #g.StrBlue, 2);
    check('TGM2 fromRaw keeps empty group', type(g.Empty), 'table');
    check('TGM3 fromRaw empty is empty',    #g.Empty, 0);
    check('TGM4 fromRaw drops non-table',   g.Junk, nil);
    check('TGM5 fromRaw drops bad members', #g.Mixed, 2);       -- 'Ok', 'Two'
    check('TGM6 fromRaw member order kept', g.StrBlue[1], 'Hysteric Barrage');
    check('TGM7 fromRaw lowercase key ok',  gmod.fromRaw({ groups = { A = { 'z' } } }).A ~= nil, true);
    check('TGM8 fromRaw no section -> {}',  next(gmod.fromRaw({})), nil);
    check('TGM9 fromRaw nil-safe',          type(gmod.fromRaw(nil)), 'table');

    -- names: case-insensitively sorted.
    local order = gmod.names({ beta = {}, Alpha = {}, gamma = {} });
    check('TGM10 names sorted CI', table.concat(order, ','), 'Alpha,beta,gamma');

    -- findName / hasGroup: case-insensitive, returns the STORED spelling.
    local gg = { StrBlue = { 'a' } };
    check('TGM11 findName CI',   gmod.findName(gg, 'strBLUE'), 'StrBlue');
    check('TGM12 findName miss', gmod.findName(gg, 'nope'), nil);
    check('TGM13 hasGroup CI',   gmod.hasGroup(gg, 'STRBLUE'), true);

    -- validateName: blank / duplicate rejected; rename may keep its own name.
    check('TGM14 validate blank',      (gmod.validateName({}, '   ')), false);
    check('TGM15 validate dup CI',     (gmod.validateName({ Cures = {} }, 'cures')), false);
    check('TGM16 validate ok',         (gmod.validateName({ Cures = {} }, 'Enfeebles')), true);
    check('TGM17 validate rename self', (gmod.validateName({ Cures = {} }, 'CURES', 'Cures')), true);

    -- add: creates an empty group; rejects a duplicate.
    local c = {};
    check('TGM18 add ok',        (gmod.add(c, ' STR Spells ')), true);
    check('TGM19 add trims key', c['STR Spells'] ~= nil, true);
    check('TGM20 add empty body', #c['STR Spells'], 0);
    check('TGM21 add dup fails',  (gmod.add(c, 'str spells')), false);

    -- addMember: trims, rejects blank + case-insensitive duplicate.
    check('TGM22 addMember ok',       (gmod.addMember(c, 'STR Spells', ' Head Butt ')), true);
    check('TGM23 addMember trimmed',  c['STR Spells'][1], 'Head Butt');
    check('TGM24 addMember dup CI',   (gmod.addMember(c, 'STR Spells', 'head butt')), false);
    check('TGM25 addMember blank',    (gmod.addMember(c, 'STR Spells', '  ')), false);
    check('TGM26 addMember no group', (gmod.addMember(c, 'Nope', 'x')), false);

    -- removeMember: case-insensitive; reports a miss.
    check('TGM27 removeMember CI',    (gmod.removeMember(c, 'STR Spells', 'HEAD BUTT')), true);
    check('TGM28 removeMember gone',  #c['STR Spells'], 0);
    check('TGM29 removeMember miss',  (gmod.removeMember(c, 'STR Spells', 'x')), false);

    -- rename: preserves members + order; rejects a collision.
    local r2 = { Old = { 'm1', 'm2' }, Other = {} };
    check('TGM30 rename ok',        (gmod.rename(r2, 'old', 'New')), true);
    check('TGM31 rename moved',     r2.Old, nil);
    check('TGM32 rename members',   #r2.New, 2);
    check('TGM33 rename order kept', r2.New[1], 'm1');
    check('TGM34 rename collision', (gmod.rename(r2, 'New', 'other')), false);
    check('TGM35 rename missing',   (gmod.rename(r2, 'ghost', 'x')), false);

    -- remove: deletes; reports a miss (a dangling reference is a Triggers-tab concern).
    check('TGM36 remove CI',   (gmod.remove(r2, 'new')), true);
    check('TGM37 remove gone', r2.New, nil);
    check('TGM38 remove miss', (gmod.remove(r2, 'nope')), false);
end)();

-- ---------------------------------------------------------------------------
-- TGI. Group import model (G4, issue #30, ADR 0009): the pure "Import Lua Table(s)"
--      transform (groupimport.lua). Parse pasted `Name = T{...}` assignments into a
--      name->members map + a skip-reason list; T is identity; flat-only (a nested /
--      non-string value skips THAT key while the rest import); malformed / hostile
--      input yields an error, never a crash or code execution (sandboxed). classify
--      splits created vs collide (CI), apply overwrites under the stored spelling.
-- ---------------------------------------------------------------------------
(function()
    local gimp = dofile('gear/groupimport.lua');   -- forward slash: also loads on Linux CI
    check('TGI0 module loads',       type(gimp),        'table');
    check('TGI0b parse exported',    type(gimp.parse),  'function');
    check('TGI0c classify exported', type(gimp.classify), 'function');
    check('TGI0d apply exported',    type(gimp.apply),  'function');

    -- 1. The issue's own example: bare lines, T{...} and plain {...} mixed, a trailing comma,
    --    a single-element group. One Group per top-level key; members = the key's string array.
    local paste = [[
STR_DEX = T{'Foot Kick', 'Wild Oats', 'Queasyshroom', 'Battle Dance', 'Feather Storm' },
STR_VIT = T{'Quad. Continuum', },
VIT     = {'Cannonball', 'Tail Slap', 'Body Slam', 'Grand Slam' },
Debuff  = T{'Filamented Hold', 'Cimicine Discharge', 'Demoralizing Roar' },
]];
    local g, errs = gimp.parse(paste);
    check('TGI1 four groups created',    (function() local n=0; for _ in pairs(g) do n=n+1 end return n; end)(), 4);
    check('TGI2 no skip errors',         #errs, 0);
    check('TGI3 T{...} members',         #g.STR_DEX, 5);
    check('TGI4 plain {...} members',    #g.VIT, 4);
    check('TGI5 member order kept',      g.STR_DEX[1], 'Foot Kick');
    -- The acceptance criterion, exactly: STR_VIT = T{'Quad. Continuum', } -> ["Quad. Continuum"].
    check('TGI6 single-elem + trailing comma len', #g.STR_VIT, 1);
    check('TGI7 single-elem value exact', g.STR_VIT[1], 'Quad. Continuum');

    -- 2. The whole `{ Key = {...}, ... }` table form parses the same as bare lines.
    local whole = gimp.parse("{ A = T{'x'}, B = {'y', 'z'} }");
    check('TGI8 whole-table A',  #whole.A, 1);
    check('TGI9 whole-table B',  #whole.B, 2);

    -- 3. Flat-only: a nested table, a named-field value, and a non-string element each skip THAT
    --    key with a reported reason -- the remaining keys still import (no all-or-nothing).
    local mixed, merr = gimp.parse(
        "Good = {'a','b'}, Nested = {'a', {'deep'}}, Nums = {'a', 42}, Mapish = {foo='bar'}");
    check('TGI10 good key imported',   #mixed.Good, 2);
    check('TGI11 nested key skipped',  mixed.Nested, nil);
    check('TGI12 nonstring key skipped', mixed.Nums, nil);
    check('TGI13 named-field skipped', mixed.Mapish, nil);
    check('TGI14 three skip reasons',  #merr, 3);
    check('TGI15 reason names the key', (merr[1]:find('Mapish', 1, true) ~= nil), true);  -- sorted -> Mapish first

    -- 4. Malformed input -> an error message, groups nil, NOT a crash.
    local bad, berr = gimp.parse("STR = T{ unterminated ");
    check('TGI16 malformed -> nil groups', bad, nil);
    check('TGI17 malformed -> one error',  #berr, 1);
    check('TGI18 malformed error worded',  (berr[1]:find('parse', 1, true) ~= nil), true);

    -- 5. Sandbox: a hostile paste referencing a blocked global (os) errors at eval -- os is nil in
    --    the env, so it is never called. groups nil, reported, nothing executed.
    local hostile, herr = gimp.parse("X = os.execute('echo pwned')");
    check('TGI19 sandbox blocks os',       hostile, nil);
    check('TGI20 sandbox reports, no run', (herr[1]:find('nil value', 1, true) ~= nil), true);

    -- 6. Empty / blank input -> a single guiding message, not a crash.
    check('TGI21 blank input -> nil',   gimp.parse('   '), nil);
    check('TGI22 nil input -> nil',     gimp.parse(nil), nil);

    -- 7. An empty group value is legal (a group you are still filling).
    local em = gimp.parse("Filling = {}, Full = {'a'}");
    check('TGI23 empty group kept',  type(em.Filling), 'table');
    check('TGI24 empty group empty', #em.Filling, 0);

    -- 8. classify: created vs collision (case-insensitive), each sorted.
    local existing = { STR_DEX = { 'old' }, Keep = { 'k' } };
    local imp = gimp.parse("str_dex = {'new1','new2'}, Fresh = {'z'}");
    local created, overwritten = gimp.classify(imp, existing);
    check('TGI25 created list',     table.concat(created, ','),     'Fresh');
    check('TGI26 overwritten CI',   table.concat(overwritten, ','), 'str_dex');

    -- 9. apply: overwrite replaces members under the EXISTING stored spelling; a new name is
    --    created; the summary counts created / updated / total members.
    local sum = gimp.apply(existing, imp);
    check('TGI27 apply created count', sum.created, 1);
    check('TGI28 apply updated count', sum.updated, 1);
    check('TGI29 apply member total',  sum.members, 3);
    check('TGI30 overwrite keeps stored key', existing.str_dex, nil);       -- not re-keyed
    check('TGI31 overwrite replaced members', table.concat(existing.STR_DEX, ','), 'new1,new2');
    check('TGI32 new group created',   existing.Fresh ~= nil, true);
    check('TGI33 untouched group kept', existing.Keep[1], 'k');
end)();

-- ---------------------------------------------------------------------------
-- ACP. actionpicker (G3, issue #26, ADR 0009): the pure searchable spell/ability
--      browse-list core -- the job-filtered list build + the search-match predicate
--      the Groups tab's browse picker drives (and issue #12's `name` picker later).
--      A combined, UNGATED list (build-ahead, HARD RULE 6); each entry says spell vs
--      ability. Data injected (setimport precedent); search mirrors item search.
-- ---------------------------------------------------------------------------
(function()
    local ap = dofile('gear/actionpicker.lua');   -- forward slash: also loads on Linux CI
    check('ACP0 module loads', type(ap), 'table');
    check('ACP1 buildList exported', type(ap.buildList), 'function');
    check('ACP2 matches exported',   type(ap.matches),   'function');

    -- Stub picker-DB rows: a BLU-usable spell + BLU-usable ability that collide on name
    -- (untyped group would list both, each labelled), a high-level BLU spell (ungated), a
    -- WHM-only spell (must NOT appear for BLU), and a shared spell (BLM + RDM).
    local spells = {
        { Name = 'Head Butt',  Jobs = { BLU = 46 }, Skill = 'Blue Magic' },   -- also an ability name
        { Name = 'Actinic Burst', Jobs = { BLU = 74 } },                       -- Lv74 -> still listed
        { Name = 'Cure',       Jobs = { WHM = 1, RDM = 3 } },                  -- no BLU
        { Name = 'Stone',      Jobs = { BLM = 1, RDM = 4 } },
        { Name = 'Stone II',   Jobs = { BLM = 26, RDM = 34 } },
    };
    local abilities = {
        { Name = 'Head Butt',  Jobs = { BLU = 46 } },                          -- ability twin
        { Name = 'Berserk',    Jobs = { WAR = 15 } },                          -- no BLU
        { Name = 'Azure Lore', Jobs = { BLU = 1 }, MainOnly = true, SP = true },
    };

    -- sorted: Actinic Burst (spell), Azure Lore (ability), Head Butt (ability), Head Butt (spell)
    local blu = ap.buildList('BLU', spells, abilities);
    check('ACP3 BLU list size (2 spells + 2 abilities)', #blu, 4);
    check('ACP4 sorted by name, case-insensitive [1]', blu[1].name, 'Actinic Burst');
    check('ACP5 [2] is Azure Lore', blu[2].name, 'Azure Lore');
    check('ACP6 name tie: ability sorts before spell [3]', blu[3].kind, 'ability');
    check('ACP7 ...its spell twin follows [4]',            blu[4].kind, 'spell');
    check('ACP8 both twins are "Head Butt"', blu[3].name == 'Head Butt' and blu[4].name == 'Head Butt', true);
    check('ACP9 carries the acquisition level for display', (function()
        for _, e in ipairs(blu) do if e.name == 'Actinic Burst' then return e.level; end end
    end)(), 74);
    check('ACP10 NOT level-gated: a Lv74 action is present at any player level', (function()
        for _, e in ipairs(blu) do if e.name == 'Actinic Burst' then return true; end end
        return false;
    end)(), true);
    check('ACP11 other jobs excluded (no Cure/Berserk for BLU)', (function()
        for _, e in ipairs(blu) do if e.name == 'Cure' or e.name == 'Berserk' then return e.name; end end
        return true;
    end)(), true);

    -- job matching is case-insensitive on the passed job; unknown / not-ready jobs -> {}
    check('ACP12 job passed lower-case still matches', #ap.buildList('blu', spells, abilities), 4);
    check('ACP13 unknown job -> empty', #ap.buildList('XYZ', spells, abilities), 0);
    check('ACP14 not-ready "NON" -> empty', #ap.buildList('NON', spells, abilities), 0);
    check('ACP15 nil job -> empty', #ap.buildList(nil, spells, abilities), 0);
    check('ACP16 missing data -> empty, no error', #ap.buildList('BLU', nil, nil), 0);

    -- a job with the shared spell picks it up under both callers
    local blm = ap.buildList('BLM', spells, abilities);
    check('ACP17 BLM sees its shared spells', #blm, 2);   -- Stone, Stone II

    -- search-match predicate: comma-separated, ALL terms substring, case-insensitive.
    local function q(s) return ap.parseQuery(s); end
    check('ACP18 empty query matches everything', ap.matches(blu[1], q('')), true);
    check('ACP19 single term narrows',    ap.matches({ name = 'Stone II' }, q('stone')), true);
    check('ACP20 case-insensitive',       ap.matches({ name = 'Stone II' }, q('STONE')), true);
    check('ACP21 non-match rejected',     ap.matches({ name = 'Stone' },    q('cure')),  false);
    check('ACP22 comma = AND (both needed)', ap.matches({ name = 'Stone II' }, q('stone, ii')), true);
    check('ACP23 comma AND: one term misses -> false', ap.matches({ name = 'Stone' }, q('stone, ii')), false);
    check('ACP24 bare-string entry accepted', ap.matches('Head Butt', q('butt')), true);
    check('ACP25 whitespace query = show all', ap.matches({ name = 'X' }, q('   ')), true);
    check('ACP26 parseQuery drops empty terms', #q('stone,,  , ii'), 2);
end)();

-- ---------------------------------------------------------------------------
-- AP3. weaponfilter Sub -- the F2c buckets (issue #18, PRD #14)
--
--   Sub buckets: Shield + Grip (both carry catalog Type="Sub"; grip-vs-shield splits by
--   name, "* Grip" / "* Strap") + the one-hander weapon types present in the pool (each
--   keeps its own weapon Type: Dagger / Sword / ...). Canonical order is Shield, Grip,
--   then the one-handers. VIEW-ONLY: the filter narrows what is shown, NEVER what the Sub
--   picker offers -- the A* HARD RULE tests (below) still gate eligibility (HARD RULE 6).
-- ---------------------------------------------------------------------------
(function()
    local wf = dofile('gear/weaponfilter.lua');

    -- A shield + a grip (Type="Sub", split by name) + a strap grip + two one-handers, plus a
    -- hand-authored Type="Shield" record (gear.lua writes the concrete type too). Unordered.
    local sub = {
        { Name = 'Test Sword',       Type = 'Sword',  OneHanded = true },   -- one-hander
        { Name = 'Koenig Shield',    Type = 'Sub' },                        -- catalog shield
        { Name = 'Tactician Grip',   Type = 'Sub' },                        -- name -> Grip
        { Name = 'Pole Strap',       Type = 'Sub' },                        -- strap -> Grip
        { Name = 'Test Dagger',      Type = 'Dagger', OneHanded = true },   -- one-hander
        { Name = 'Kaman Buckler',    Type = 'Shield' },                     -- hand-authored
    };
    local sb = wf.presentBuckets(sub, 'Sub');
    check('AP3-1 sub: four buckets present',   #sb, 4);
    check('AP3-2 canonical order [1] Shield',  sb[1].key, 'Shield');
    check('AP3-3 canonical order [2] Grip',    sb[2].key, 'Grip');
    check('AP3-4 one-handers after Shield/Grip [3] Dagger', sb[3].key, 'Dagger');
    check('AP3-5 canonical order [4] Sword',   sb[4].key, 'Sword');
    check('AP3-6 Shield labelled',             sb[1].label, 'Shield');
    check('AP3-7 Grip labelled',               sb[2].label, 'Grip');

    -- bucketOf: shields (catalog + hand-authored), grips (both spellings), one-handers.
    check('AP3-8 catalog shield -> Shield',    wf.bucketOf(sub[2], 'Sub'), 'Shield');
    check('AP3-9 authored shield -> Shield',   wf.bucketOf(sub[6], 'Sub'), 'Shield');
    check('AP3-10 "* Grip" -> Grip',           wf.bucketOf(sub[3], 'Sub'), 'Grip');
    check('AP3-11 "* Strap" -> Grip',          wf.bucketOf(sub[4], 'Sub'), 'Grip');
    check('AP3-12 one-hander keeps its Type',  wf.bucketOf(sub[1], 'Sub'), 'Sword');

    -- Shield marked: shows both shields, hides grips and one-handers.
    local onlyShield = { Shield = true };
    check('AP3-13 Shield shows catalog shield',  wf.visible(sub[2], onlyShield, 'Sub'), true);
    check('AP3-14 Shield shows authored shield', wf.visible(sub[6], onlyShield, 'Sub'), true);
    check('AP3-15 Shield hides grip',            wf.visible(sub[3], onlyShield, 'Sub'), false);
    check('AP3-16 Shield hides one-hander',      wf.visible(sub[1], onlyShield, 'Sub'), false);

    -- Grip marked: both grip spellings show, shields / one-handers hide.
    local onlyGrip = { Grip = true };
    check('AP3-17 Grip shows "* Grip"',   wf.visible(sub[3], onlyGrip, 'Sub'), true);
    check('AP3-18 Grip shows "* Strap"',  wf.visible(sub[4], onlyGrip, 'Sub'), true);
    check('AP3-19 Grip hides shield',     wf.visible(sub[2], onlyGrip, 'Sub'), false);
    check('AP3-20 Grip hides one-hander', wf.visible(sub[5], onlyGrip, 'Sub'), false);

    -- One-hander types stay distinct: Dagger marked shows only the dagger.
    local onlyDagger = { Dagger = true };
    check('AP3-21 Dagger shows the dagger',  wf.visible(sub[5], onlyDagger, 'Sub'), true);
    check('AP3-22 Dagger hides the sword',   wf.visible(sub[1], onlyDagger, 'Sub'), false);
    check('AP3-23 Dagger hides a shield',    wf.visible(sub[2], onlyDagger, 'Sub'), false);

    -- Multi-pick and All-default carry over.
    local shieldOrDagger = { Shield = true, Dagger = true };
    check('AP3-24 multi shows shield',    wf.visible(sub[2], shieldOrDagger, 'Sub'), true);
    check('AP3-25 multi shows dagger',    wf.visible(sub[5], shieldOrDagger, 'Sub'), true);
    check('AP3-26 multi hides sword',     wf.visible(sub[1], shieldOrDagger, 'Sub'), false);
    check('AP3-27 All default shows grip', wf.visible(sub[3], {}, 'Sub'), true);
    check('AP3-28 nil marks show one-hander', wf.visible(sub[1], nil, 'Sub'), true);

    -- Present-only: a shields-only pool offers exactly one bucket.
    check('AP3-29 shields-only pool -> one bucket',
        #wf.presentBuckets({ { Name = 'Buckler', Type = 'Shield' } }, 'Sub'), 1);
    -- Empty pool -> no buckets (never an empty dropdown).
    check('AP3-30 empty sub pool -> no buckets', #wf.presentBuckets({}, 'Sub'), 0);
end)();

-- ---------------------------------------------------------------------------
-- TR. Trinket vs ranged weapon (ADR 0010): a stat-stick ammo reserves the Range
--     slot server-side, so the two can't coexist (the client would flap re-equipping
--     the weapon the server keeps clearing). gearimport.effectiveRSlot completes the
--     trinket category (Ammo + no AmmoType -> the Range bit) so the WHOLE class is
--     marked in gear.lua; dispatch.trinketRangeDrop keeps the HIGHER-LEVEL of the two
--     and drops the other -- deterministic, so it settles instead of flapping.
-- ---------------------------------------------------------------------------
(function()
    -- trinket detection: Ammo with no AmmoType -> Range bit; fired ammo / explicit RSlot untouched
    local gimp = dofile('gear/gearimport.lua');
    check('TR0 effectiveRSlot exported', type(gimp.effectiveRSlot), 'function');
    check('TR1 trinket (Ammo, no AmmoType) -> Range bit', gimp.effectiveRSlot({ Type = 'Ammo', Id = 1 }), 4);
    check('TR2 fired ammo (has AmmoType) -> nil',          gimp.effectiveRSlot({ Type = 'Ammo', AmmoType = 'Archery' }), nil);
    check('TR3 explicit RSlot kept',                       gimp.effectiveRSlot({ Type = 'Ammo', RSlot = 8 }), 8);
    check('TR4 non-ammo -> nil',                           gimp.effectiveRSlot({ Type = 'Body' }), nil);

    -- the level tiebreak (dispatchM.trinketRangeDrop). rslot: only the stat sticks reserve Range.
    local rslot = function(n) return ({ Cinderstone = 4, Morion = 4 })[n]; end
    local level = function(n) return ({ Cinderstone = 60, Morion = 25, ['Power Bow'] = 75, ['Toy Bow'] = 10, ['Iron Arrow'] = 1 })[n]; end
    local function drop(set) return dispatchM.trinketRangeDrop(set, rslot, level); end

    local k, w = drop({ Range = 'Power Bow', Ammo = 'Cinderstone' });   -- bow 75 > stick 60
    check('TR5 bow higher -> drop the trinket',  k, 'Ammo');
    check('TR5b ... keeping the bow',            w, 'Power Bow');
    k, w = drop({ Range = 'Toy Bow', Ammo = 'Cinderstone' });           -- stick 60 > bow 10
    check('TR6 trinket higher -> drop the weapon', k, 'Range');
    check('TR6b ... keeping the trinket',          w, 'Cinderstone');
    check('TR7 bow + real arrow -> no drop', (drop({ Range = 'Power Bow', Ammo = 'Iron Arrow' })), nil);
    check('TR8 trinket alone -> no drop',    (drop({ Ammo = 'Cinderstone' })), nil);
    check('TR9 bow alone -> no drop',        (drop({ Range = 'Power Bow' })), nil);
    -- tie on level -> keep the trinket (drop Range), matching the server's own resolution
    local level2 = function(n) return ({ Cinderstone = 75, ['Power Bow'] = 75 })[n]; end
    check('TR10 tie -> keep the trinket, drop Range',
        dispatchM.trinketRangeDrop({ Range = 'Power Bow', Ammo = 'Cinderstone' }, rslot, level2), 'Range');

    -- Scope ruling (v78): the Level contest is WITHIN-SET only. A worn trinket
    -- OUTSIDE the plan is displaced (Ammo='remove') so the set's ranged piece
    -- can land -- Level never protects it from outside the pairing.
    local function disp(plan, worn) return dispatchM.trinketWornDisplace(plan, worn, rslot); end
    check('TR11 worn trinket vs set Range -> displace',      disp({ Range = 'Toy Bow' }, 'Cinderstone'), 'Ammo');
    check('TR11b Level does NOT protect a worn trinket',     disp({ Range = 'Toy Bow' }, 'Morion'), 'Ammo');
    local _, tr11in = disp({ Range = 'Toy Bow' }, 'Cinderstone');
    check('TR11c the incoming piece is named',               tr11in, 'Toy Bow');
    check('TR12 plan speaks for Ammo itself -> no displace', disp({ Range = 'Toy Bow', Ammo = 'Iron Arrow' }, 'Cinderstone'), nil);
    check('TR13 worn fired ammo -> no displace',             disp({ Range = 'Toy Bow' }, 'Iron Arrow'), nil);
    check('TR13b nothing worn -> no displace',               disp({ Range = 'Toy Bow' }, nil), nil);
    check('TR14 no Range in plan -> no displace',            disp({ Body = 'Gaudy Harness' }, 'Cinderstone'), nil);
    check('TR15 Range=remove is not incoming',               disp({ Range = 'remove' }, 'Cinderstone'), nil);
end)();

-- ---------------------------------------------------------------------------
-- TB. ADR 0010 scope ruling wired through equipResolved (v78): the field case
--     -- worn Rimestone Lv60 must not keep a set's Lv20 Rouser out of Range.
--     Worn ammo comes through the real wornItemName glue (AshitaCore stubbed);
--     RSlot/Level through the real gear-manifest delegates (NameToObject
--     stubbed, the LS20 technique). Locked Ammo keeps the OLD behavior: the
--     user's explicit word outranks the set, so the worn trinket still
--     reserves Range away (the server mirror stays intact).
-- ---------------------------------------------------------------------------
(function()
    local gearTB = package.loaded['dlac\\gear'];
    gearTB.NameToObject['Rimestone'] = { Name = 'Rimestone', RSlot = 4, Level = 60 };
    gearTB.NameToObject['Rouser']    = { Name = 'Rouser', Level = 20 };
    local savedAC = AshitaCore;
    -- Worn-gear stub: `name` sits in Ammo (equip id 3), every other slot empty.
    AshitaCore = {
        GetMemoryManager = function()
            return { GetInventory = function()
                return {
                    GetEquippedItem = function(self, id)
                        if id == 3 then return { Index = 1 }; end
                        return { Index = 0 };
                    end,
                    GetContainerItem = function(self, c, i) return { Id = 9001 }; end,
                };
            end };
        end,
        GetResourceManager = function()
            return { GetItemById = function(self, id) return { Name = { 'Rimestone' } }; end };
        end,
    };
    for k in pairs(dispatchM.locks) do dispatchM.locks[k] = nil; end
    dispatchM.modes['maxmp'] = nil;   -- the mp branch must not join this test

    -- the field case: set names Range only -> the worn trinket is displaced
    local tbNote, tbTbl = dispatchM._equipResolved({ Range = 'Rouser' }, {});
    check('TB1 set Range survives the worn trinket',  tbTbl.Range, 'Rouser');
    check('TB2 the worn trinket is displaced',        tbTbl.Ammo, 'remove');
    check('TB3 the displacement is traced',
        string.find(tbNote, 'yields Range', 1, true) ~= nil, true);

    -- locked Ammo: no displacement; the worn trinket reserves Range away
    dispatchM.locks['ammo'] = true;
    local _, tbLk = dispatchM._equipResolved({ Range = 'Rouser' }, {});
    check('TB4 locked Ammo: no displacement',              tbLk.Ammo, nil);
    check('TB5 locked Ammo: the worn trinket keeps Range', tbLk.Range, nil);
    dispatchM.locks['ammo'] = nil;

    -- the plan speaking for Ammo itself needs no displacement
    local _, tbAr = dispatchM._equipResolved({ Range = 'Rouser', Ammo = 'Iron Arrow' }, {});
    check('TB6 plan Ammo rides as-is', tbAr.Ammo, 'Iron Arrow');
    check('TB6b Range untouched',      tbAr.Range, 'Rouser');

    -- WITHIN-SET pairing unchanged: both named -> Level decides (ADR 0010)
    local _, tbIn = dispatchM._equipResolved({ Range = 'Rouser', Ammo = 'Rimestone' }, {});
    check('TB7 within-set: the higher-Level trinket still wins', tbIn.Ammo, 'Rimestone');
    check('TB7b ... and the set Range drops',                    tbIn.Range, nil);

    AshitaCore = savedAC;
    gearTB.NameToObject['Rimestone'] = nil;
    gearTB.NameToObject['Rouser'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- REC. gearrecord -- the Owned-gear record rules, ONE home (Type canon + legacy
--      heal, Shield/Grip by name, effectiveRSlot trinket completion, catalog
--      enrichment precedence). Every stamp site (renderEntry fresh write,
--      /dl fix backfill, gearui enrich, gearexport, the weapon-type filter)
--      resolves through these; TR0-TR4 above pin the gearimport delegate.
-- ---------------------------------------------------------------------------
(function()
    local grec = package.loaded['dlac\\gear\\gearrecord'];
    check('REC0 module seeded', type(grec), 'table');

    -- Type canon + heal
    check('REC1 spaced legacy heals',     grec.canonType('Great Axe'), 'GreatAxe');
    check('REC2 hyphenated legacy heals', grec.canonType('Hand-to-Hand'), 'HandToHand');
    check('REC3 bare String alias',       grec.canonType('String'), 'StringInstrument');
    check('REC4 unknown passes through',  grec.canonType('Oddball'), 'Oddball');
    check('REC5 healType absent takes catalog',        grec.healType(nil, 'GreatAxe'), 'GreatAxe');
    check('REC6 healType drift heals to catalog',      grec.healType('Great Axe', 'GreatAxe'), 'GreatAxe');
    check('REC7 healType exact keeps owned',           grec.healType('GreatAxe', 'GreatAxe'), 'GreatAxe');
    check('REC8 healType real difference keeps owned', grec.healType('Sword', 'Dagger'), 'Sword');

    -- weaponfilter's whole bucket vocabulary must resolve through the same canon
    -- (a key gearrecord did not know would silently stop healing that bucket).
    local wf = dofile('gear/weaponfilter.lua');
    for slot, cfg in pairs(wf.SLOTS) do
        for _, key in ipairs(cfg.order) do
            if key ~= '__trinket' then   -- presentation sentinel, not a Type
                check('REC9 vocabulary closure ' .. slot .. '/' .. key, grec.canonType(key), key);
            end
        end
    end

    -- Shield/Grip by name (GUI-side mirror of utils.classifySub)
    check('REC10 grip by name',  grec.subTypeFromName('Pole Grip'), 'Grip');
    check('REC11 strap by name', grec.subTypeFromName('Claymore Strap'), 'Grip');
    check('REC12 else shield',   grec.subTypeFromName("Genbu's Shield"), 'Shield');

    -- effectiveRSlot: the rule itself (TR1-TR4 pin the gearimport delegate)
    check('REC13 trinket completion',   grec.effectiveRSlot({ Type = 'Ammo' }), 4);
    check('REC14 explicit RSlot wins',  grec.effectiveRSlot({ Type = 'Ammo', RSlot = 8 }), 8);
    check('REC15 fired ammo untouched', grec.effectiveRSlot({ Type = 'Ammo', AmmoType = 'Archery' }), nil);

    -- enrich: owned overrides, catalog fills; legacy Type heals; Stats merge
    local rec = { Name = 'Savagery', Type = 'Great Axe', Stats = { STR = 2 } };
    local cat = { Name = 'Savagery', Type = 'GreatAxe', OneHanded = false, Model = 123,
                  Stats = { STR = 1, DEX = 3 } };
    grec.enrich(rec, cat);
    check('REC16 enrich heals legacy Type',         rec.Type, 'GreatAxe');
    check('REC17 enrich fills OneHanded',           rec.OneHanded, false);
    check('REC18 enrich fills Model',               rec.Model, 123);
    check('REC19 enrich merge: owned stat wins',    rec.Stats.STR, 2);
    check('REC20 enrich merge: catalog fills',      rec.Stats.DEX, 3);
    check('REC21 catalog Stats untouched by merge', cat.Stats.STR, 1);

    -- a statless record SHARES the catalog Stats table (the documented in-place
    -- semantics consumers' copy-on-write discipline depends on -- do not "fix")
    local thin = { Name = 'X' };
    grec.enrich(thin, cat);
    check('REC22 statless record shares catalog Stats table', thin.Stats == cat.Stats, true);

    -- mergedStats read-only (gearexport's precedence)
    local r2 = { Stats = { ACC = 5 } };
    local m = grec.mergedStats(r2, { Stats = { ACC = 1, EVA = 2 } });
    check('REC23 mergedStats owned wins',        m.ACC, 5);
    check('REC24 mergedStats catalog fills',     m.EVA, 2);
    check('REC25 mergedStats fresh table',       r2.Stats.EVA, nil);
    check('REC26 mergedStats both empty -> nil', grec.mergedStats({}, {}), nil);
end)();

-- ---------------------------------------------------------------------------
-- SW. lib\safewrite -- the safe file-replacement ladder, written once (both
--     gear.lua writers ride replaceLua; profiles' deleters ride verifiedMove).
--     Real files under tests\ (cwd = addon root), removed at section end.
-- ---------------------------------------------------------------------------
(function()
    local sw = package.loaded['dlac\\lib\\safewrite'];
    check('SW0 module seeded', type(sw), 'table');
    local base = 'tests\\';
    local target = base .. 'sw_target.lua';
    local function put(p, t) local f = io.open(p, 'w'); f:write(t); f:close(); end
    local function get(p) local f = io.open(p, 'r'); if f == nil then return nil; end local t = f:read('*a'); f:close(); return t; end

    -- happy path: replace lands, tmp gone
    put(target, 'return { old = true }\n');
    check('SW1 replace succeeds', sw.replaceLua(target, 'return { new = true }\n', { origText = 'return { old = true }\n' }), true);
    check('SW2 new content live', get(target), 'return { new = true }\n');
    check('SW3 tmp cleaned',      get(target .. '.tmp'), nil);

    -- parse failure: refused before anything is written
    check('SW4 bad text refused',  (sw.replaceLua(target, 'return {', {})), nil);
    check('SW5 target untouched',  get(target), 'return { new = true }\n');

    -- validator failure: tmp removed, target untouched, reason carried
    local ok2, err2 = sw.replaceLua(target, 'return { v = 2 }\n', {
        origText = get(target),
        validate = function() return nil, 'nope'; end });
    check('SW6 validator can refuse', ok2, nil);
    check('SW6b reason carried',      err2 ~= nil and err2:find('nope', 1, true) ~= nil, true);
    check('SW7 target untouched on validate fail', get(target), 'return { new = true }\n');
    check('SW8 tmp cleaned on validate fail',      get(target .. '.tmp'), nil);

    -- the validator receives the loaded (unrun) chunk -- the sandbox-run shape
    -- gearimport's gearLoadValidator uses
    local seen = nil;
    sw.replaceLua(target, 'return 42\n', { validate = function(chunk) seen = chunk(); return true; end });
    check('SW9 validator gets runnable chunk', seen, 42);
    check('SW9b validated write landed',       get(target), 'return 42\n');

    -- timestampBackup (ashita.fs absent headless -> guarded dir creation skipped)
    local bp = sw.timestampBackup(base, 'swb_', 'content');
    check('SW10 backup written', bp ~= nil and get(bp), 'content');

    -- verifiedMove: copy + read-back verify + remove; missing source flagged
    put(base .. 'sw_src.lua', 'MOVE ME');
    check('SW11 verified move ok', sw.verifiedMove(base .. 'sw_src.lua', base .. 'sw_dst.lua'), true);
    check('SW12 dst holds content', get(base .. 'sw_dst.lua'), 'MOVE ME');
    check('SW13 src removed',       get(base .. 'sw_src.lua'), nil);
    local m2, _, missing = sw.verifiedMove(base .. 'sw_missing.lua', base .. 'sw_dst2.lua');
    check('SW14 missing source flagged', (m2 == nil and missing == true), true);

    os.remove(target); if bp then os.remove(bp); end os.remove(base .. 'sw_dst.lua');
end)();

-- ---------------------------------------------------------------------------
-- CI. gear\catalogindex -- Catalog access, one walker (raw id index + the
--     flattened browse copies + the generic gear-shaped flattener). Fresh
--     dofile instances per case so the lazy-load cache starts clean.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\data\\catalog'] = {
        Head = { TestCap = { Id = 11, Name = 'Test Cap', Level = 10, Stats = { HP = 5 } } },
        Main = { Sword = { Wax = { Id = 22, Name = 'Wax Sword', Level = 1, Type = 'Sword', OneHanded = true } } },
        Ammo = { Stone = { Id = 33, Name = 'Cinder Test', Level = 60, Type = 'Ammo' } },
        NameToObject = { ['Test Cap'] = { Id = 999, Name = 'DECOY' } },   -- aliases: must be skipped
    };
    local ci = dofile('gear/catalogindex.lua');
    check('CI0 available with catalog seeded', ci.available(), true);
    local raw = ci.rawIndex();
    check('CI1 raw ids indexed',        raw[11].Name, 'Test Cap');
    check('CI2 NameToObject skipped',   raw[999], nil);
    check('CI3 nested weapon reached',  raw[22].Type, 'Sword');
    check('CI4 rawById',                ci.rawById(33).Name, 'Cinder Test');
    local list, byId, byName = ci.flat();
    check('CI5 flat copies carry Slot',        byId[11].Slot, 'Head');
    check('CI6 flat Category from nesting',    byId[22].Category, 'Sword');
    check('CI7 byName lowercased',             byName['wax sword'].Id, 22);
    check('CI8 flat records are COPIES',       byId[11] ~= raw[11], true);
    check('CI9 flatten generic over gear-shaped tables',
        (select(2, ci.flatten({ Head = { C = { Id = 7, Name = 'C' } } })))[7].Slot, 'Head');

    -- missing catalog degrades quietly (guarded callers behave as before)
    package.loaded['dlac\\data\\catalog'] = nil;
    local ci2 = dofile('gear/catalogindex.lua');
    check('CI10 unavailable without catalog', ci2.available(), false);
    check('CI11 rawIndex empty, not nil',     next(ci2.rawIndex()), nil);
    check('CI12 flat empty, not nil',         #(ci2.flat()), 0);
end)();

-- ---------------------------------------------------------------------------
-- AV. ownedcache -- the availability verdict (ADR 0005: Owned vs Available are
--     two facts; stored beats locked beats ok) + the whereText caption builder.
--     First test reach this module has ever had, via the _splitOverride seam.
-- ---------------------------------------------------------------------------
(function()
    local oc = dofile('gear/ownedcache.lua');
    oc._splitOverride = {
        avail = { [1] = 1, [3] = 2 },              -- id 1, 3 equippable now
        total = { [1] = 1, [2] = 1, [3] = 2 },     -- id 2 owned but parked
        where = { [2] = { [1] = 1, [4] = 2 } },    -- id 2: container 1 x1, container 4 x2
    };
    check('AV1 available -> ok',        oc.verdict({ Id = 1 }), 'ok');
    check('AV2 stored beats usable',    oc.verdict({ Id = 2 }, true), 'stored');
    check('AV3 stored beats locked',    oc.verdict({ Id = 2 }, false), 'stored');
    check('AV4 locked when not usable', oc.verdict({ Id = 1 }, false), 'locked');
    check('AV5 nil usable reads ok',    oc.verdict({ Id = 3 }), 'ok');
    check('AV6 unowned never stored',   oc.verdict({ Id = 99 }, true), 'ok');
    check('AV7 isStored fact',          oc.isStored({ Id = 2 }), true);
    check('AV8 haveInBags stored copy', oc.haveInBags({ Id = 2 }), true);
    check('AV9 haveInBags unowned',     oc.haveInBags({ Id = 99 }), false);

    -- whereText: sorted container names via gearimport.containerName (faked,
    -- restored -- keep the swap contained to this closure)
    local saved = package.loaded['dlac\\gear\\gearimport'];
    package.loaded['dlac\\gear\\gearimport'] = { containerName = function(cid) return 'C' .. cid; end };
    check('AV10 whereText sorted with counts', oc.whereText({ Id = 2 }), 'C1, C4 x2');
    package.loaded['dlac\\gear\\gearimport'] = saved;
    check('AV11 whereText unowned empty', oc.whereText({ Id = 99 }), '');

    -- the safe fallback (documented): an empty scan hides NOTHING -- availability
    -- is colour, ownership gates visibility, and no data means no gating
    local oc2 = dofile('gear/ownedcache.lua');
    oc2._splitOverride = { avail = {}, total = {} };
    check('AV12 empty scan: haveInBags stays true', oc2.haveInBags({ Id = 5 }), true);
    check('AV13 empty scan: nothing stored',        oc2.verdict({ Id = 5 }, true), 'ok');
end)();

-- ---------------------------------------------------------------------------
-- VG. Virtual-decision gates, pure halves (engine v69): resolveObi and
--     resolveOneiros mirror resolveStaff -- data in, decision out; the rims in
--     resolveVirtual only read env/nativemp/vitals. These were the ONLY two
--     virtual decisions no test could reach, and both carry field-calibrated
--     rules (positive day/weather sign; the Mindie-pinned 50% inclusive MP
--     boundary) that now cannot drift silently.
-- ---------------------------------------------------------------------------
(function()
    local ro = dispatchM._resolveObi;
    local a = { obi = { Fire = { name = 'Karin Obi', level = 71 },
                        Ice  = { name = 'Hyorin Obi', level = 71 } },
                obiUniversal = { name = 'Hachirin-no-obi', level = 61 } };
    check('VG1 elemental obi on positive sign', ro(a, 'Fire', 75, 1), 'Karin Obi');
    local n2, w2 = ro(a, 'Fire', 75, 0);
    check('VG2 zero sign refused',  n2, nil);
    check('VG2b reason',            w2, 'day/weather not positive');
    check('VG3 negative sign refused', (ro(a, 'Fire', 75, -1)), nil);
    check('VG4 under-level elemental falls to universal', ro(a, 'Ice', 70, 1), 'Hachirin-no-obi');
    check('VG5 no elemental -> universal', ro({ obi = {}, obiUniversal = { name = 'Hachirin-no-obi', level = 61 } }, 'Earth', 75, 2), 'Hachirin-no-obi');
    check('VG6 elementless action refused', select(2, ro(a, nil, 75, 1)), 'no element');
    check('VG7 legacy string obi shape', ro({ obi = { Wind = 'Furin Obi' } }, 'Wind', 75, 1), 'Furin Obi');
    check('VG8 nothing usable reason', select(2, ro({ obi = {} }, 'Dark', 75, 1)), 'no usable obi for Dark at Lv75');

    local rg = dispatchM._resolveOneiros;
    local g = { name = 'Oneiros Grip', level = 75 };
    -- THE field pin (Mindie 2026-07-18): base 714 -> threshold 357, equality ACTIVE.
    check('VG9 at the boundary the latent is LIVE', rg(g, 75, 714, 357), 'Oneiros Grip');
    local n10, w10 = rg(g, 75, 714, 358);
    check('VG10 one MP above -> refused', n10, nil);
    check('VG10b threshold spelled in the reason', w10, 'MP 358 above the latent threshold 357 (half of base 714)');
    check('VG11 not owned',      select(2, rg(nil, 75, 714, 100)), 'Oneiros Grip not owned (the Automations tab rescans itself)');
    check('VG12 under level',    select(2, rg(g, 74, 714, 100)), 'under level for Oneiros Grip (Lv75)');
    check('VG13 base unreadable', select(2, rg(g, 75, nil, 100)), 'native MP unreadable (login settle?)');
    check('VG14 no pool',        select(2, rg(g, 75, 0, 0)), 'no native MP pool on this job');
    check('VG15 cur unreadable', select(2, rg(g, 75, 714, nil)), 'current MP unreadable');
end)();

-- ---------------------------------------------------------------------------
-- SF. The statefile seam (engine v70): ONE cached reader (ensureStateFile)
--     behind the auto/acc/craft/helm/fish/pin caches -- they were six
--     near-identical clones and had drifted (pin dropped corrupt writes, the
--     others kept the last good table glued on forever). Policy pinned HERE,
--     once, for all of them; _charDirOverride makes the file-driven surface
--     run headless for the first time.
-- ---------------------------------------------------------------------------
(function()
    local esf = dispatchM._ensureStateFile;
    check('SF0 helper exported', type(esf), 'function');
    local function put(p, t) local f = io.open(p, 'w'); f:write(t); f:close(); end
    dispatchM._charDirOverride = 'tests\\';
    local cache = { raw = nil, data = nil, lastCheck = -1 };

    put('tests\\sf_state.lua', 'return { enabled = true, craft = "Alchemy" }');
    local d = esf(cache, 'sf_state.lua');
    check('SF1 file read + parsed', d ~= nil and d.craft, 'Alchemy');

    -- same-second throttle: a changed file is not re-read until the clock moves
    put('tests\\sf_state.lua', 'return { craft = "Smithing" }');
    cache.lastCheck = os.time();
    check('SF2 throttled within the second', esf(cache, 'sf_state.lua').craft, 'Alchemy');

    -- THE POLICY: corrupt write -> DROP (not last-good); re-reads stay dropped
    cache.lastCheck = -1;
    put('tests\\sf_state.lua', 'return {');
    check('SF3 corrupt write drops the state', esf(cache, 'sf_state.lua'), nil);
    cache.lastCheck = -1;
    check('SF4 corrupt stays dropped on re-read', esf(cache, 'sf_state.lua'), nil);

    -- the next good write self-heals
    cache.lastCheck = -1;
    put('tests\\sf_state.lua', 'return { craft = "Bonecraft" }');
    check('SF5 good write self-heals', esf(cache, 'sf_state.lua').craft, 'Bonecraft');

    -- a file that parses but ERRORS on run drops too
    cache.lastCheck = -1;
    put('tests\\sf_state.lua', 'error("boom")');
    check('SF6 run-error drops the state', esf(cache, 'sf_state.lua'), nil);

    -- missing file = state off
    cache.lastCheck = -1;
    os.remove('tests\\sf_state.lua');
    check('SF7 missing file = state off', esf(cache, 'sf_state.lua'), nil);

    -- pre-login (no char dir) keeps whatever is cached
    cache.lastCheck = -1; cache.data = { keep = true };
    dispatchM._charDirOverride = nil;
    check('SF8 no char dir keeps cache', esf(cache, 'sf_state.lua').keep, true);

    -- WIRING: with no test override, the auto manifest reads through the seam.
    -- The _auto singleton's 1s throttle may have been armed by an earlier
    -- section in this same second -- cross the boundary so the read is live.
    dispatchM._charDirOverride = 'tests\\';
    dispatchM._autoOverride = nil;
    put('tests\\autogear.lua', 'return { universal = { name = "Chatoyant Staff", tier = 2, level = 51 } }');
    local t0 = os.time(); repeat until os.time() ~= t0;
    check('SF9 resolveVirtual reads the manifest through the seam',
        dispatchM._resolveVirtual('dlac:AutoStaff', { player = { MainJobSync = 75 } }), 'Chatoyant Staff');
    os.remove('tests\\autogear.lua');
    dispatchM._charDirOverride = nil;
end)();

-- ---------------------------------------------------------------------------
-- PL. equipResolved's post-pass order is DATA (engine v71): the five
--     whole-table passes run in M._postPassOrder. A reorder must edit BOTH the
--     list and this pin -- which is the point: the ADR 0010 constraint
--     (trinket-vs-ranged strictly before reserved-drops, or the loser gets to
--     reserve and the result flaps) is now checkable instead of prose.
-- ---------------------------------------------------------------------------
(function()
    local po = dispatchM._postPassOrder;
    check('PL1 order exported', type(po), 'table');
    check('PL2 exact order', table.concat(po, '>'),
        'mp-stage>craft-sub-guard>sync-hold-ammo>trinket-vs-ranged>reserved-drops');
    local ti, ri = nil, nil;
    for i, nm in ipairs(po) do
        if nm == 'trinket-vs-ranged' then ti = i; end
        if nm == 'reserved-drops' then ri = i; end
    end
    check('PL3 ADR 0010: trinket strictly before reserved', ti ~= nil and ri ~= nil and ti < ri, true);
end)();

-- ---------------------------------------------------------------------------
-- GS. Groups auto-import scanner (Item 1): the pure `scan(fileText) -> candidates, notes`
--     transform (groupscan.lua). Text-scans a LuaAshitacast file for top-level
--     `[local] NAME = T?{...}` blocks and surfaces every group-shaped table (a flat string
--     array, or a container of them) as an import candidate, skipping gear sets / settings.
--     Reuses groupimport's sandbox eval + flat-list heuristic; hostile blocks error safely.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\gear\\groupimport'] = dofile('gear/groupimport.lua');
(function()
    local gscan = dofile('gear/groupscan.lua');
    check('GS0 module loads',  type(gscan),      'table');
    check('GS0b scan exported', type(gscan.scan), 'function');

    local sample = [[
-- my BLU setup { this comment has an unbalanced brace
local Settings = { TpVariant = 1, ATKCAP = false }
local IdleVariantTable = { [1] = 'Refresh/Regen', [2] = 'Learn' }
local BlueSpells = {
    STR_DEX = T{'Foot Kick', 'Wild Oats', 'Queasyshroom'},
    VIT     = {'Cannonball', 'Tail Slap'},
    Debuff  = T{'Filamented Hold',},
}
local sets = {
    ['Idle'] = { Ammo = 'Tiphia Sting', Head = 'Mirage Keffiyeh +1' },
    ['TP']   = { Main = 'Maple Sugar', Sub = { Name = 'X', Augment = {'a'} } },
}
local Evil = { bad = os.execute('rm -rf /') }
]];
    local cands, notes = gscan.scan(sample);
    local byName = {};
    for _, c in ipairs(cands) do byName[c.name] = c.members; end

    -- a container of flat lists expands to one candidate per inner key
    check('GS1 BlueSpells expands to its inner groups',
        (byName.STR_DEX ~= nil and byName.VIT ~= nil and byName.Debuff ~= nil), true);
    check('GS1b STR_DEX member count',  byName.STR_DEX and #byName.STR_DEX, 3);
    check('GS1c member order preserved', byName.STR_DEX and byName.STR_DEX[1], 'Foot Kick');
    check('GS1d single-elem + trailing comma', byName.Debuff and #byName.Debuff, 1);
    check('GS1e plain {...} parses too (no T)',  byName.VIT and #byName.VIT, 2);
    -- the container name itself is NOT a candidate (only its group-shaped children are)
    check('GS2 container name not a candidate', byName.BlueSpells, nil);
    -- gear sets are skipped, not mistaken for groups
    check('GS3 gear-set keys not candidates', (byName.Idle == nil and byName.TP == nil), true);
    -- a flat variant/config table IS surfaced (the player deselects it in the preview)
    check('GS4 flat variant table surfaced', byName.IdleVariantTable ~= nil, true);

    -- hostile / unreadable blocks are skipped SAFELY (os is nil in the sandbox -> eval errors,
    -- os.execute never runs) and named in the notes; gear sets are noted too.
    local noteText = table.concat(notes, ' | ');
    check('GS5 hostile os.execute block skipped safely', string.find(noteText, 'Evil', 1, true) ~= nil, true);
    check('GS6 gear-set block noted',                    string.find(noteText, 'sets', 1, true) ~= nil, true);

    -- the candidates feed groupimport.classify / apply verbatim (the reuse contract)
    local gimp = package.loaded['dlac\\gear\\groupimport'];
    local groupsMap = {};
    for _, c in ipairs(cands) do groupsMap[c.name] = c.members; end
    local _, overwritten = gimp.classify(groupsMap, { STR_DEX = { 'old' } });
    check('GS7 classify sees the STR_DEX collision',
        (function() for _, n in ipairs(overwritten) do if n == 'STR_DEX' then return true; end end return false; end)(), true);

    -- duplicate names collapse to one candidate (first spelling wins)
    local dup = gscan.scan("local A = T{'x'}\nlocal A = T{'y'}\n");
    check('GS8 duplicate names dedup to one', #dup, 1);
    -- nil / non-string input is safe
    local c9 = gscan.scan(nil);
    check('GS9 nil input -> no candidates', #c9, 0);
end)();

-- ---------------------------------------------------------------------------
-- LS. Level-sync settle hold (dispatch.syncSettleStep + the equipResolved
--     ctx.syncHold branch, v56): a level jump on the SAME job arms a short
--     (SYNC_SETTLE_S) weapon hold -- an Incursion boss pop re-syncing the
--     party must not swap
--     Main mid-transition and zero saved TP. Job changes and first reads adopt
--     instantly; not-ready readings (level 0, job '?'/'NON') never touch the
--     tracker. While the hold is live, ONLY Main/Sub/Range are kept as worn --
--     armor and Ammo (no TP cost) dispatch normally.
-- ---------------------------------------------------------------------------
(function()
    check('LS0 pure rule exported',    type(dispatchM.syncSettleStep), 'function');
    check('LS0b live consult exported', type(dispatchM.syncSettleHold), 'function');
    local W = dispatchM.SYNC_SETTLE_S;
    check('LS0c settle window is a positive number', type(W) == 'number' and W > 0, true);

    local st = { job = nil, lv = nil, holdUntil = 0 };
    check('LS1 first read adopts, no hold',   dispatchM.syncSettleStep(st, 'WAR', 75, 100.0), false);
    check('LS2 stable level stays free',      dispatchM.syncSettleStep(st, 'WAR', 75, 101.0), false);
    check('LS3 sync lands -> hold arms',      dispatchM.syncSettleStep(st, 'WAR', 60, 102.0), true);
    check('LS4 still holding inside window',  dispatchM.syncSettleStep(st, 'WAR', 60, 102.0 + W - 0.1), true);
    check('LS5 window passed -> released',    dispatchM.syncSettleStep(st, 'WAR', 60, 102.0 + W), false);
    -- a staged transition (server re-syncs in steps) keeps extending the window
    check('LS6 second sync re-arms',          dispatchM.syncSettleStep(st, 'WAR', 50, 110.0), true);
    check('LS6b next stage extends',          dispatchM.syncSettleStep(st, 'WAR', 55, 111.0), true);
    check('LS6c still live past the FIRST deadline', dispatchM.syncSettleStep(st, 'WAR', 55, 110.0 + W + 0.5), true);
    -- job change: adopt instantly AND drop any live hold (new job must re-gear now)
    dispatchM.syncSettleStep(st, 'WAR', 40, 120.0);   -- arm
    check('LS7 job change adopts instantly',  dispatchM.syncSettleStep(st, 'NIN', 37, 120.5), false);
    check('LS7b job change drops the hold',   st.holdUntil, 0);
    -- not-ready readings leave the tracker (and a live hold) untouched
    dispatchM.syncSettleStep(st, 'NIN', 30, 130.0);   -- arm
    check('LS8 level 0 ignored (hold stays)',  dispatchM.syncSettleStep(st, nil,  0,  130.5), true);
    check('LS8b NON job ignored (hold stays)', dispatchM.syncSettleStep(st, 'NON', 75, 130.6), true);
    check('LS8c "?" job ignored (hold stays)', dispatchM.syncSettleStep(st, '?',  75, 130.7), true);
    check('LS8d junk never adopted into the tracker', st.lv, 30);

    -- equipResolved rides ctx.syncHold: weapons held as worn, the rest dispatches
    local lsSet = { Main = 'Joyeuse', Sub = 'GenbusShield', Range = 'Power Bow',
                    Ammo = 'Tiphia Sting', Body = 'Gaudy Harness' };
    local lsNote, lsTbl = dispatchM._equipResolved(lsSet, { syncHold = true });
    check('LS9 Main held',   lsTbl.Main,  nil);
    check('LS10 Sub held',   lsTbl.Sub,   nil);
    check('LS11 Range held', lsTbl.Range, nil);
    check('LS12 Ammo NOT held (no TP cost)', lsTbl.Ammo, 'Tiphia Sting');
    check('LS13 armor unaffected',           lsTbl.Body, 'Gaudy Harness');
    check('LS14 the hold is traced for /dl why', string.find(lsNote, 'SYNC-HOLD', 1, true) ~= nil, true);
    local _, lsTbl2 = dispatchM._equipResolved(lsSet, { syncHold = false });
    check('LS15 no hold: weapons dispatch',  lsTbl2.Main, 'Joyeuse');
    local _, lsTbl3 = dispatchM._equipResolved(lsSet, {});
    check('LS16 absent flag: weapons dispatch (old ctx shape)', lsTbl3.Main, 'Joyeuse');

    -- ROOT CAUSE pin: a level-driven VIRTUAL in a weapon slot must be held
    -- UNRESOLVED -- resolving it at the transient level IS the field bug. This
    -- kills the "refactor the hold into a post-pass on final names" mutant:
    -- only the branch's position ABOVE the dlac: branch guarantees it.
    local lsV = { Main = 'dlac:AutoStaff|Fallback Staff', Sub = 'dlac:AutoGrip|Fallback Grip' };
    local lsVNote, lsVTbl = dispatchM._equipResolved(lsV, { syncHold = true });
    check('LS17 virtual Main held unresolved',  lsVTbl.Main, nil);
    check('LS17b virtual Sub held unresolved',  lsVTbl.Sub, nil);
    check('LS18 the hold is what got traced',   string.find(lsVNote, 'SYNC-HOLD', 1, true) ~= nil, true);
    check('LS18b no virtual resolution leaked', string.find(lsVNote, 'AutoStaff', 1, true), nil);
    local _, lsVFree = dispatchM._equipResolved(lsV, {});
    check('LS19 no hold: virtual resolves (fallback rides)', lsVFree.Main ~= nil, true);

    -- Sync-hold companion rule (ADR 0010): with Range held, a stat-stick Ammo
    -- whose RSlot reserves Range must hold too -- otherwise it lands and the
    -- SERVER strips the worn ranged weapon mid-window. Fired ammo (no Range
    -- bit, like LS12's recordless Tiphia Sting) keeps dispatching.
    local gearLS = package.loaded['dlac\\gear'];
    gearLS.NameToObject['Aureole'] = { Name = 'Aureole', RSlot = 0x0004 + 0x0008, Level = 70 };
    local lsTrink = { Range = 'Power Bow', Ammo = 'Aureole', Body = 'Gaudy Harness' };
    local lsTNote, lsTTbl = dispatchM._equipResolved(lsTrink, { syncHold = true });
    check('LS20 Range held',                    lsTTbl.Range, nil);
    check('LS20b Range-reserving Ammo held too', lsTTbl.Ammo, nil);
    check('LS20c armor still dispatches',        lsTTbl.Body, 'Gaudy Harness');
    check('LS20d companion hold traced',
        string.find(lsTNote, 'reserves Range', 1, true) ~= nil, true);
    -- no hold: ADR 0010 behavior unchanged (trinket vs ranged decided by Level)
    local _, lsTFree = dispatchM._equipResolved(lsTrink, {});
    check('LS21 no hold: trinket rule decides (higher Level wins)', lsTFree.Ammo, 'Aureole');
    check('LS21b no hold: the lower-Level ranged weapon dropped',   lsTFree.Range, nil);
    gearLS.NameToObject['Aureole'] = nil;

    -- The LIVE consult: the gData glue (field names, tonumber, pcall) and the
    -- shared tracker on M. Deterministic: arming and the truth test share one
    -- os.clock() read inside each call; the job change zeroes holdUntil.
    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
    dispatchM.syncSettleHold();                       -- first good read adopts silently
    check('LS22 live: stable reading, no hold',   dispatchM.syncSettleHold(), false);
    TEST_PLAYER.MainJobSync = 60;                     -- a level sync lands
    check('LS23 live: sync jump arms the hold',   dispatchM.syncSettleHold(), true);
    check('LS23b live: tracker parked on M (survives self-swap)',
        type(dispatchM._syncSt) == 'table' and dispatchM._syncSt.lv, 60);
    TEST_PLAYER.MainJob = 'NIN';                      -- job change adopts instantly
    check('LS24 live: job change drops the hold', dispatchM.syncSettleHold(), false);
    TEST_PLAYER = nil;                                -- not-ready read: tracker untouched
    check('LS25 live: nil player never arms',     dispatchM.syncSettleHold(), false);

    -- The Default gate (M.defaultGateHold): what the HandleEquipEvent wrap
    -- consults AT CALL TIME. Pet hold first, then the sync settle hold.
    TEST_PLAYER = { MainJob = 'BLM', SubJob = 'WHM', MainJobSync = 37, SubJobSync = 18 };
    dispatchM.syncSettleHold();                       -- job differs from LS24's NIN: adopt, no hold
    check('LS26 gate: idle -> not held',          dispatchM.defaultGateHold(), false);
    _G.gState = { PetAction = { Completion = os.clock() + 5 } };
    check('LS27 gate: pet action in flight -> held', dispatchM.defaultGateHold(), true);
    _G.gState.PetAction = nil;
    TEST_PLAYER.MainJobSync = 30;                     -- a sync lands (same job BLM)
    check('LS28 gate: sync settling -> held',     dispatchM.defaultGateHold(), true);
    TEST_PLAYER.MainJob = 'WAR';                      -- job change releases
    check('LS29 gate: job change releases',       dispatchM.defaultGateHold(), false);
    _G.gState = nil;

    -- The wrap SHELL, driven for real: a fresh engine load with gFunc + a stub
    -- gState installs the thin shell (WRAP_GEN); HandleDefault is gated while
    -- the fresh module's tracker is armed, Precast always flows. Also pins the
    -- generational re-install: a v55-shaped pre-wrap (_dlacPetHold=true, no
    -- _dlacWrapGen) must be wrapped OVER, not skipped -- the hot-swap gap.
    local reached = nil;
    local stStub = {
        HandleEquipEvent = function(ev, style) reached = ev; end,
        _dlacPetHold = true,                          -- the v55 boolean is already set
    };
    _G.gFunc, _G.gState = {}, stStub;
    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
    local freshM = dofile('dispatch.lua');
    check('LS30 shell installed OVER a v55-shaped wrap', stStub.HandleEquipEvent ~= nil
        and type(stStub._dlacWrapGen) == 'number', true);
    stStub.HandleEquipEvent('HandleDefault');         -- first pass adopts the level
    check('LS31 stable level: Default flows',     reached, 'HandleDefault');
    reached = nil;
    TEST_PLAYER.MainJobSync = 60;                     -- a sync lands
    stStub.HandleEquipEvent('HandleDefault');
    check('LS32 settling: Default gated',         reached, nil);
    stStub.HandleEquipEvent('HandlePrecast');
    check('LS33 settling: action events flow',    reached, 'HandlePrecast');
    freshM.SYNC_SETTLE_S = 0;                         -- release without sleeping
    reached = nil;
    TEST_PLAYER.MainJobSync = 50;                     -- re-arm under a 0s window
    stStub.HandleEquipEvent('HandleDefault');
    check('LS34 window over: Default flows again', reached, 'HandleDefault');
    _G.gFunc, _G.gState = nil, nil;
    TEST_PLAYER = nil;
end)();

-- ---------------------------------------------------------------------------
-- PL. paired-slot dynamic ladders (gearoptim.pairLadders) -- Ear/Ring pairs
--     ladder as one running TOP-2 walk so BOTH physical slots fill. Field case
--     (Henrik, 2026-07-17): under Cure Potency weights, Curates' Earring (30)
--     and Roundel Earring (73) both laddered onto Ear1 and Ear2 stayed empty --
--     the pair must wear both once both are owned. The scores here are the
--     caller's weighted scores at the build level; pairLadders is pure.
-- ---------------------------------------------------------------------------
(function()
    local optim = dofile('gear/gearoptim.lua');
    local function names(chain)
        local t = {};
        for _, c in ipairs(chain) do t[#t + 1] = tostring(c.name); end
        return table.concat(t, ',');
    end

    -- The field case: both earrings owned -> one per ear, not both on Ear1.
    local curates = { ref = 'C', name = "Curates' Earring", id = 1, level = 30, score = 30, copies = 1 };
    local roundel = { ref = 'R', name = 'Roundel Earring',  id = 2, level = 73, score = 50, copies = 1 };
    local c1, c2 = optim.pairLadders({ curates, roundel });
    check('PL1 field case: first ear keeps the early earring', names(c1), "Curates' Earring");
    check('PL2 field case: second ear gets the late earring',  names(c2), 'Roundel Earring');

    -- joint pins matching the chain tops (in either order -- the two physical
    -- slots are interchangeable) claim the chains untouched
    c1, c2 = optim.pairLadders({ curates, roundel }, { pins = { roundel, curates } });
    check('PL3 top pins claim chains untouched (1)', names(c1), "Curates' Earring");
    check('PL4 top pins claim chains untouched (2)', names(c2), 'Roundel Earring');

    -- a strictly-improving upgrade run ALTERNATES between the chains: at every
    -- level the two flattens together wear the best two owned pieces (the old
    -- shape put all four on slot 1 and starved slot 2 completely)
    local A = { ref = 'A', name = 'A', id = 11, level = 10, score = 5  };
    local B = { ref = 'B', name = 'B', id = 12, level = 20, score = 10 };
    local C = { ref = 'C', name = 'C', id = 13, level = 30, score = 12 };
    local D = { ref = 'D', name = 'D', id = 14, level = 40, score = 20 };
    c1, c2 = optim.pairLadders({ A, B, C, D });
    check('PL5 running top-2: chain 1', names(c1), 'A,C');
    check('PL6 running top-2: chain 2', names(c2), 'B,D');

    -- same-level pieces fill both slots at once
    local X = { ref = 'X', name = 'X', id = 51, level = 30, score = 20 };
    local Y = { ref = 'Y', name = 'Y', id = 52, level = 30, score = 15 };
    c1, c2 = optim.pairLadders({ Y, X });                     -- input order shuffled on purpose
    check('PL7 same-level pair fills both slots', names(c1) .. '|' .. names(c2), 'X|Y');

    -- a single copy never fills both slots ...
    local solo = { ref = 'S', name = 'Solo Ring', id = 21, level = 30, score = 40 };
    c1, c2 = optim.pairLadders({ solo });
    check('PL8 one copy -> one chain only', names(c1) .. '|' .. names(c2), 'Solo Ring|');

    -- ... but TWO owned copies do (Auto-build passes live owned counts)
    local twin = { ref = 'T', name = 'Twin Ring', id = 22, level = 30, score = 40, copies = 2 };
    c1, c2 = optim.pairLadders({ twin });
    check('PL9 two copies -> both chains', names(c1) .. '|' .. names(c2), 'Twin Ring|Twin Ring');

    -- same-NAME legacy duplicates are ONE physical item (optimizePicks' rule)
    local dupA = { ref = 'd1', name = "Jalzahn's Ring", id = 31, level = 50, score = 40 };
    local dupB = { ref = 'd2', name = "jalzahn's ring",           level = 50, score = 40 };
    c1, c2 = optim.pairLadders({ dupA, dupB });
    check('PL10 same-name duplicate fills one slot only', #c1 + #c2, 1);

    -- zero scorers are never kept (the seed-at-0 rule: no junk padding)
    c1, c2 = optim.pairLadders({ { ref = 'z', name = 'Junk', id = 41, level = 10, score = 0 } });
    check('PL11 zero score never padded', #c1 + #c2, 0);

    -- a leftover pin (not a chain top -- the cap optimizer preferred a lower
    -- piece) trims its chain like the single-slot ladder cap, and a single-copy
    -- pin is STRIPPED from the other chain -- leaving it would double-equip at
    -- the levels where both chains flatten to it
    c1, c2 = optim.pairLadders({ A, B, C, D }, { pins = { D, B } });
    check('PL12 leftover pin trims its chain',                 names(c1), 'A,B');
    check('PL13 single-copy pin stripped from the other chain', names(c2), 'D');
end)();

-- ---------------------------------------------------------------------------
-- LL. level-banded single-slot ladders (gearoptim.levelLadder) -- Auto-build
--     re-scores candidates at every band edge (adoption level + levelstats
--     thresholds) and emits between-level windows where value changes. Field
--     case (Henrik, 2026-07-19): Garrison Tunica +1's Refresh+1 dies past
--     Lv.50 -- its points must stop at 50 and the next body take over at 51.
--     Monotone slots must come back as the classic unranged chain (parity).
-- ---------------------------------------------------------------------------
(function()
    local optim = dofile('gear/gearoptim.lua');
    local function fmt(lad)
        local t = {};
        for _, e in ipairs(lad) do
            t[#t + 1] = tostring(e.ref) .. '[' .. tostring(e.minLevel or '') .. '-' .. tostring(e.maxLevel or '') .. ']';
        end
        return table.concat(t, ',');
    end
    local function ladder(items, scores, joint, cap)
        return optim.levelLadder(items, {
            cap = cap or 75,
            scoreAt = function(ref, L) return scores[ref](L); end,
            joint = joint,
        });
    end

    -- monotone upgrades: classic chain, zero windows -- today's output verbatim
    local lad = ladder(
        { { ref = 'A', level = 1 }, { ref = 'B', level = 20 } },
        { A = function() return 5; end, B = function() return 9; end });
    check('LL1 monotone slot keeps the classic unranged chain', fmt(lad), 'A[-],B[-]');

    -- THE tunica shape: A is worth 10 up to 50 then decays to 4; B (worth 6,
    -- wearable at 30) must own 51+ -- and A's window must CLOSE at 50 even
    -- though B's adoption level is lower than the handover level
    lad = ladder(
        { { ref = 'A', level = 20, breaks = { 51 } }, { ref = 'B', level = 30 } },
        { A = function(L) return (L < 51) and 10 or 4; end, B = function() return 6; end });
    check('LL2 decay closes the window and hands over', fmt(lad), 'A[-50],B[51-]');

    -- joint pick (set-level choice, per-item score irrelevant) trims exactly
    -- like the classic chain: lower rungs stay, output unranged (parity)
    lad = ladder(
        { { ref = 'A', level = 20 }, { ref = 'C', level = 40 } },
        { A = function() return 10; end, C = function() return 3; end }, 'C');
    check('LL3 joint trim stays classic', fmt(lad), 'A[-],C[-]');

    -- zero scorers are never kept (the seed-at-0 rule)
    lad = ladder({ { ref = 'Z', level = 10 } }, { Z = function() return 0; end });
    check('LL4 zero score never kept', fmt(lad), '');

    -- a `from` gainer can win, lose the middle, and win again: the SAME item
    -- appears twice with disjoint windows
    lad = ladder(
        { { ref = 'B', level = 10, breaks = { 40 } }, { ref = 'A', level = 30 } },
        { B = function(L) return (L < 40) and 2 or 9; end, A = function() return 5; end });
    check('LL5 regain emits the item twice with disjoint windows', fmt(lad), 'B[-29],A[30-39],B[40-]');

    -- a winner-less gap (everything scores 0 there) inherits the previous
    -- winner: unweighted stats still count, the slot is never bared
    lad = ladder(
        { { ref = 'A', level = 20, breaks = { 41 } }, { ref = 'B', level = 30, breaks = { 50 } } },
        { A = function(L) return (L < 41) and 10 or 0; end, B = function(L) return (L < 50) and 0 or 7; end });
    check('LL6 winner-less gap extends the previous winner', fmt(lad), 'A[-49],B[50-]');

    -- thresholds above the build cap are ignored: below it the tunica never
    -- decays, so the slot is a single classic entry
    lad = ladder(
        { { ref = 'A', level = 20, breaks = { 51 } }, { ref = 'B', level = 30 } },
        { A = function(L) return (L < 51) and 10 or 4; end, B = function() return 6; end },
        nil, 40);
    check('LL7 breaks beyond the cap are ignored', fmt(lad), 'A[-]');
end)();

-- ---------------------------------------------------------------------------
-- PLL. level-banded PAIR ladders (gearoptim.pairLevelLadders) -- the Ear/Ring
--      twin of levelLadder: at every band the pair wears the true top-2 by
--      score-at-that-level. Flat scores must reproduce pairLadders' chains
--      verbatim (PL5/6, PL12/13 parity); a decaying piece hands its slot over
--      at the breakpoint with a between-level window.
-- ---------------------------------------------------------------------------
(function()
    local optim = dofile('gear/gearoptim.lua');
    local function fmt(lad)
        local t = {};
        for _, e in ipairs(lad) do
            t[#t + 1] = tostring(e.ref) .. '[' .. tostring(e.minLevel or '') .. '-' .. tostring(e.maxLevel or '') .. ']';
        end
        return table.concat(t, ',');
    end
    local function pair(cands, scores, pins, cap)
        local cA, cB = optim.pairLevelLadders(cands, {
            cap = cap or 75,
            scoreAt = function(ref, L) return scores[ref](L); end,
            pins = pins,
        });
        return fmt(cA), fmt(cB);
    end
    local flat = {
        A = function() return 5; end,  B = function() return 10; end,
        C = function() return 12; end, D = function() return 20; end,
    };
    local A = { ref = 'A', name = 'A', id = 11, level = 10 };
    local B = { ref = 'B', name = 'B', id = 12, level = 20 };
    local C = { ref = 'C', name = 'C', id = 13, level = 30 };
    local D = { ref = 'D', name = 'D', id = 14, level = 40 };

    -- flat scores: byte-for-byte the classic running top-2 chains (PL5/6)
    local a, b = pair({ A, B, C, D }, flat);
    check('PLL1 flat scores keep pairLadders chains (1)', a, 'A[-],C[-]');
    check('PLL2 flat scores keep pairLadders chains (2)', b, 'B[-],D[-]');

    -- decay handover on a pair: E1 (Refresh-style, dies past 50) owns a slot to
    -- 50, then the SECOND-best remaining piece takes that slot with a window
    local E1 = { ref = 'E1', name = 'E1', id = 21, level = 20, breaks = { 51 } };
    local E2 = { ref = 'E2', name = 'E2', id = 22, level = 20 };
    local E3 = { ref = 'E3', name = 'E3', id = 23, level = 30 };
    a, b = pair({ E1, E2, E3 }, {
        E1 = function(L) return (L < 51) and 10 or 2; end,
        E2 = function() return 6; end,
        E3 = function() return 5; end,
    });
    check('PLL3 decaying piece hands its slot over at 51', a, 'E1[-50],E3[51-]');
    check('PLL4 partner slot undisturbed', b, 'E2[-]');

    -- one owned copy fills one slot; two copies fill both
    local S = { ref = 'S', name = 'Solo', id = 31, level = 30 };
    a, b = pair({ S }, { S = function() return 8; end });
    check('PLL5 one copy -> one chain only', a .. '|' .. b, 'S[-]|');
    local T = { ref = 'T', name = 'Twin', id = 32, level = 30, copies = 2 };
    a, b = pair({ T }, { T = function() return 8; end });
    check('PLL6 two copies -> both chains', a .. '|' .. b, 'T[-]|T[-]');

    -- pin reconciliation parity (PL12/13): a leftover pin trims its chain, a
    -- single-copy pin is swept from the other chain
    a, b = pair({ A, B, C, D }, flat, { D, B });
    check('PLL7 leftover pin trims its chain',                  a, 'A[-],B[-]');
    check('PLL8 single-copy pin swept from the other chain',    b, 'D[-]');

    -- zero scorers are never kept
    a, b = pair({ A }, { A = function() return 0; end });
    check('PLL9 zero score never kept', a .. '|' .. b, '|');
end)();

-- ---------------------------------------------------------------------------
-- HELM: helmwatch state + parsers + the engine's dlac:AutoHelm overlay (v59)
-- -- docs/design/helm-gear.md. Idle-only is STRUCTURAL (the overlay is only
-- consulted on Default, same gate as craft); these cover resolution + rules.
-- ---------------------------------------------------------------------------
(function()
    local helmwatch = dofile('feature/helmwatch.lua');

    -- state rules (the craftwatch model: select does not enable; fishing is
    -- deliberately not a category -- it gets its own automation someday)
    helmwatch.selectGather('Mining');
    check('H1 selectGather sets active',   helmwatch.getGather(), 'Mining');
    check('H2 select does NOT enable',     helmwatch.isEnabled(), false);
    helmwatch.selectGather('logging');
    check('H3 lowercase tolerated',        helmwatch.getGather(), 'Logging');
    helmwatch.selectGather('Fishing');
    check('H4 fishing rejected',           helmwatch.getGather(), 'Logging');
    helmwatch.setEnabled(true);
    check('H5 switch turns on',            helmwatch.isEnabled(), true);
    helmwatch.setEnabled(false);
    check('H6 switch off',                 helmwatch.isEnabled(), false);

    -- category from NPC name + the 0x034 result-event detect. The event bytes
    -- are the REAL Ghelsba Outpost capture (2026-07-17, Mindie's swing that
    -- chopped an Arrowwood Log): ActIndex 319 @0x28, zone 140 @0x2A.
    check('H7 Mining Point -> Mining',     helmwatch.gatherFromNpcName('Mining Point'), 'Mining');
    check('H8 Harvesting Point',           helmwatch.gatherFromNpcName('Harvesting Point'), 'Harvesting');
    check('H9 unrelated npc -> nil',       helmwatch.gatherFromNpcName('Goblin Miner'), nil);
    check('H10 nil npc -> nil',            helmwatch.gatherFromNpcName(nil), nil);
    local evt = string.char(0x34, 0x1A, 0x8D, 0x06, 0x3F, 0xC1, 0x08, 0x01, 0xB0, 0x02, 0, 0)
        .. string.rep('\0', 28)
        .. string.char(0x3F, 0x01, 0x8C, 0x00, 0x64, 0x00, 0x08, 0x00, 0x8C, 0x00, 0x00, 0x00);
    check('H10b result-event npc index (real capture)', helmwatch.eventNpcIndex(evt), 319);
    check('H10c short packet -> nil',      helmwatch.eventNpcIndex('short'), nil);
    helmwatch.onEventNum(evt, function(i) return (i == 319) and 'Logging Point' or nil; end);
    check('H10d detection from result event',
        helmwatch.lastDetect ~= nil and helmwatch.lastDetect.gather or nil, 'Logging');
    helmwatch.onEventNum(evt, function(i) return 'Fantoccini'; end);   -- ordinary NPC event
    check('H10e non-Point event leaves detect alone',
        helmwatch.lastDetect ~= nil and helmwatch.lastDetect.gather or nil, 'Logging');

    -- 0x1A4 POINTS_ENTRY wire format (trove protocol): group@0x08 (19b) |
    -- label@0x1C (23b) | i32 value@0x34; CLEAR/END_LIST commits the stream.
    local function zi32(v) return string.char(v % 256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/16777216)%256); end
    local function zfield(s, width) return s .. string.rep('\0', width - #s); end
    local function pointsEntry(group, label, value)
        return string.char(0xA4, 0, 0, 0) .. string.char(7) .. string.rep('\0', 3)
            .. zfield(group, 20) .. zfield(label, 24) .. zi32(value);
    end
    local endList = string.char(0xA4, 0, 0, 0) .. string.char(2) .. '\0';
    check('H11 entry consumed',  helmwatch.on1A4(pointsEntry('Ventures', 'Mining', 3200)), true);
    check('H12 no commit before END', helmwatch.pointsFor('Mining'), nil);
    helmwatch.on1A4(pointsEntry('Ventures', 'Harvesting', 150));
    helmwatch.on1A4(pointsEntry('Ventures', 'Dynamis', 999));
    check('H13 END commits stream', helmwatch.on1A4(endList), true);
    check('H14 exact label match',  helmwatch.pointsFor('Mining'), 3200);
    check('H15 second category',    helmwatch.pointsFor('Harvesting'), 150);
    check('H16 absent category',    helmwatch.pointsFor('Excavation'), nil);
    check('H17 pointsReady',        helmwatch.pointsReady(), true);

    -- !ventures reply parse -- format PINNED by field capture 2026-07-17:
    --   Mining: (Low) Ordelles Caves, (Mid) Garlaige Citadel [S], (High) Grauberg [S]
    local vg, vl = helmwatch.parseVentureLine(
        'Mining: (Low) Ordelles Caves, (Mid) Garlaige Citadel [S], (High) Grauberg [S]');
    check('H18 venture line category',  vg, 'Mining');
    check('H18b tier count',            vl ~= nil and #vl or 0, 3);
    check('H18c low tier',              vl ~= nil and vl[1], 'Low:  Ordelles Caves');
    check('H18d high tier keeps [S]',   vl ~= nil and vl[3], 'High: Grauberg [S]');
    local dg, dl = helmwatch.parseVentureLine('Harvesting: something the server changed');
    check('H19 drifted format keeps raw tail', dg, 'Harvesting');
    check('H19b drifted tail content',  dl ~= nil and dl[1], 'something the server changed');
    check('H20 party chatter -> nil',   helmwatch.parseVentureLine('do i go to M or go to J?'), nil);
    check('H20b unknown category -> nil', helmwatch.parseVentureLine('Fishing: (Low) Port Windurst'), nil);
    check('H21 control bytes scrubbed', helmwatch.cleanLine('a\1\2b  c\127'), 'a b c');
    check('H22 jst day rollover', helmwatch.jstDay(15 * 3600) - helmwatch.jstDay(0), 1);

    -- Engine overlay: dlac:AutoHelm resolves the manifest helm block -- the
    -- category hat first for Head (semantic map), the generic ladder as the
    -- fallback (another category's hat still carries Surveyor), best-first
    -- level-gated rungs everywhere else. Armor+neck+waist only by design.
    dispatchM._autoOverride = { helm = {
        hats = { Mining = { name = 'Miners Helmet', level = 1, surv = 1 } },
        head = { { name = 'Lumberjacks Beret', score = 10, level = 1, helm = 0, surv = 1 } },
        body = { { name = 'Plain Tunica +1', score = 21, level = 40, helm = 1, surv = 2 },
                 { name = 'Field Tunica',    score = 1,  level = 1,  helm = 1, surv = 0 } },
        neck = { { name = 'Field Torque',    score = 1,  level = 65, helm = 1, surv = 0 } },
    } };
    local hov = dispatchM._helmOverlayFor({ gather = 'Mining', enabled = true, at = 1 },
        { player = { MainJobSync = 75 } });
    check('H23 hat resolves for category',   hov and hov.Head, 'Miners Helmet');
    check('H24 body best rung',              hov and hov.Body, 'Plain Tunica +1');
    check('H25 neck usable at 75',           hov and hov.Neck, 'Field Torque');
    local hov2 = dispatchM._helmOverlayFor({ gather = 'Harvesting', enabled = true },
        { player = { MainJobSync = 75 } });
    check('H26 missing hat -> head ladder',  hov2 and hov2.Head, 'Lumberjacks Beret');
    local hov3 = dispatchM._helmOverlayFor({ gather = 'Mining', enabled = true },
        { player = { MainJobSync = 30 } });
    check('H27 underlevel rung falls through', hov3 and hov3.Body, 'Field Tunica');
    check('H28 underlevel neck -> slot empty', hov3 and hov3.Neck, nil);
    local hoff = dispatchM._helmOverlayFor({ gather = 'Mining', enabled = false },
        { player = { MainJobSync = 75 } });
    check('H29 disabled -> no overlay',      hoff, nil);
    local hnog = dispatchM._helmOverlayFor({ gather = '', enabled = true },
        { player = { MainJobSync = 75 } });
    check('H30 no category -> no overlay',   hnog, nil);
    dispatchM._autoOverride = nil;

    -- rating / preview (helmwatch reads the same manifest shape itself for
    -- the bar display: HELM sum over non-Head picks, >=5 = break-proof)
    helmwatch._setManifest({ helm = {
        hats  = { Mining = { name = 'Miners Helmet', level = 1, surv = 1 } },
        body  = { { name = 'Plain Tunica', score = 11, level = 30, helm = 1, surv = 1 } },
        hands = { { name = 'Field Gloves', score = 1,  level = 1,  helm = 1, surv = 0 } },
        neck  = { { name = 'Field Torque', score = 1,  level = 65, helm = 1, surv = 0 } },
        waist = { { name = 'Field Rope',   score = 1,  level = 65, helm = 1, surv = 0 } },
        legs  = { { name = 'Plain Hose',   score = 11, level = 30, helm = 1, surv = 1 } },
        feet  = { { name = 'Plain Boots',  score = 11, level = 30, helm = 1, surv = 1 } },
    } });
    local pv = helmwatch.preview('Mining', 75);
    check('H31 preview head is the hat',  pv.Head ~= nil and pv.Head.name, 'Miners Helmet');
    check('H32 preview body',             pv.Body ~= nil and pv.Body.name, 'Plain Tunica');
    local hr, hs, hbp = helmwatch.rating('Mining', 75);
    check('H33 rating sums HELM (no head)', hr, 6);
    check('H34 surveyor total',             hs, 4);
    check('H35 break-proof at >= 5',        hbp, true);
    local lr = select(1, helmwatch.rating('Mining', 20));
    check('H36 level gating trims rating',  lr, 1);

    -- Auto HELM (Henrik's split): the detection-armed temporary overlay.
    -- Default off; a Point result while armed opens a hold; the engine wears
    -- the gear only while the hold runs (idle switch stays independent).
    check('H37 auto default off',           helmwatch.isAutoHelm(), false);
    helmwatch.onEventNum(evt, function(i) return 'Logging Point'; end);
    check('H38 unarmed swing -> no hold',   helmwatch.autoActive(), false);
    helmwatch.setAutoHelm(true);
    check('H39 auto arms',                  helmwatch.isAutoHelm(), true);
    helmwatch.onEventNum(evt, function(i) return 'Logging Point'; end);
    check('H40 armed swing opens the hold', helmwatch.autoActive(), true);
    check('H41 armed swing sets category',  helmwatch.getGather(), 'Logging');
    helmwatch.setAutoHelm(false);
    check('H42 disarm ends the hold',       helmwatch.autoActive(), false);

    -- Engine: helmStateActive is the single truth for both ways in.
    local act = dispatchM._helmStateActive;
    check('H43 idle switch active',    act({ gather = 'Mining', enabled = true }), true);
    check('H44 auto + live hold',      act({ gather = 'Mining', enabled = false, auto = true, autoUntil = os.time() + 60 }), true);
    check('H45 auto + expired hold',   act({ gather = 'Mining', enabled = false, auto = true, autoUntil = os.time() - 1 }), false);
    check('H46 auto without hold',     act({ gather = 'Mining', enabled = false, auto = true }), false);
    check('H47 hold without auto',     act({ gather = 'Mining', enabled = false, autoUntil = os.time() + 60 }), false);
    check('H48 no category never active', act({ gather = '', enabled = true, auto = true, autoUntil = os.time() + 60 }), false);
    dispatchM._autoOverride = { helm = {
        body = { { name = 'Field Tunica', score = 1, level = 1, helm = 1, surv = 0 } },
    } };
    local aov = dispatchM._helmOverlayFor(
        { gather = 'Mining', enabled = false, auto = true, autoUntil = os.time() + 60 },
        { player = { MainJobSync = 75 } });
    check('H49 hold resolves the overlay',  aov and aov.Body, 'Field Tunica');
    local aoff = dispatchM._helmOverlayFor(
        { gather = 'Mining', enabled = false, auto = true, autoUntil = os.time() - 1 },
        { player = { MainJobSync = 75 } });
    check('H50 expired hold -> no overlay', aoff, nil);
    dispatchM._autoOverride = nil;

    -- Proximity hold via the CENTRAL entity watcher (entwatch migration --
    -- was the targeting anchor): Auto HELM tracks the four "* Point" names
    -- itself, so ANY point within range holds the gear on -- no targeting.
    -- The probe is the watcher seam: nearest('<Cat> Point') -> yalms | nil.
    local world = { points = {} };   -- ['Mining Point'] = nearest dist (yalms)
    local probe = { nearest = function(nm) return world.points[nm]; end };
    helmwatch.setAutoHelm(true);
    helmwatch.setProxRange(6);   -- pin the 6y/8y geometry for H51-H64
    world.points['Mining Point'] = 5;
    check('H51 point in range holds, no target', helmwatch.proximityStep(probe), true);
    check('H52 hold equips (live)',            helmwatch.autoActive(), true);
    check('H53 nearest point selects category', helmwatch.getGather(), 'Mining');
    world.points['Mining Point'] = 7;              -- inside the 8y leash
    check('H54 leash keeps the active category', helmwatch.proximityStep(probe), true);
    world.points['Mining Point'] = 10;             -- walked away
    check('H55 out of leash drops the hold',   helmwatch.proximityStep(probe), false);
    world.points['Mining Point'] = 5;              -- wandered back
    check('H56 re-acquires without any target', helmwatch.proximityStep(probe), true);
    world.points['Mining Point'] = nil;            -- mined out (despawn)...
    world.points['Logging Point'] = 1;             -- ...stacked twin on the spot
    check('H57 stacked spawn: hold survives',  helmwatch.proximityStep(probe), true);
    check('H58 and follows what is there',     helmwatch.getGather(), 'Logging');
    world.points['Logging Point'] = nil;
    world.points['Harvesting Point'] = 7;          -- leash range, but a SWITCH
    check('H59 category switch needs enter range', helmwatch.proximityStep(probe), false);
    world.points['Harvesting Point'] = nil;
    -- the swing result stays the category authority + latches the hold
    helmwatch.onEventNum(evt, function(i) return (i == 319) and 'Logging Point' or nil; end);
    check('H60 swing result opens the hold',   helmwatch.autoActive(), true);
    check('H61 swing result picks category',   helmwatch.getGather(), 'Logging');
    world.points['Logging Point'] = 7;             -- sweep caught up: leash applies
    check('H62 post-swing leash holds',        helmwatch.proximityStep(probe), true);
    world.points['Logging Point'] = nil;
    check('H63 all points gone -> hold drops', helmwatch.proximityStep(probe), false);
    helmwatch.setAutoHelm(false);
    world.points['Mining Point'] = 5;
    check('H64 disarmed: never holds',         helmwatch.proximityStep(probe), false);

    -- Configurable detect range (Henrik: default 10 for macro-spam-at-range
    -- and lag; panel setting clamped 3..20, keep-wearing leash = range+2).
    check('H70 default range is 10',        helmwatch.PROX_DEFAULT, 10);
    helmwatch.setProxRange(25);
    check('H71 clamps high to 20',          helmwatch.proxEnter(), 20);
    helmwatch.setProxRange(1);
    check('H72 clamps low to 3',            helmwatch.proxEnter(), 3);
    helmwatch.setProxRange(10);
    helmwatch.setAutoHelm(true);
    world.points = { ['Harvesting Point'] = 9 };   -- outside 6, inside 10
    check('H73 wider range acquires at 9y', helmwatch.proximityStep(probe), true);
    world.points['Harvesting Point'] = 11.9;       -- just inside the 12y leash
    check('H74 leash follows range (+2y)',  helmwatch.proximityStep(probe), true);
    world.points['Harvesting Point'] = 12.1;       -- just past it
    check('H75 past the leash drops',       helmwatch.proximityStep(probe), false);
    helmwatch.setAutoHelm(false);

    -- Combat gate (v61): "Default" is NOT "idle" -- HandleDefault runs every
    -- frame including combat, so the overlay itself must stand aside while
    -- Engaged/Dead. 'Event' stays dressed (the swing animation is an event).
    dispatchM._autoOverride = { helm = {
        body = { { name = 'Field Tunica', score = 1, level = 1, helm = 1, surv = 0 } },
    } };
    local hsOn = { gather = 'Mining', enabled = true };
    local function stCtx(st) return { player = { MainJobSync = 75, Status = st } }; end
    check('H65 engaged -> overlay stands aside', dispatchM._helmOverlayFor(hsOn, stCtx('Engaged')), nil);
    check('H66 dead -> stands aside', dispatchM._helmOverlayFor(hsOn, stCtx('Dead')), nil);
    local hIdle = dispatchM._helmOverlayFor(hsOn, stCtx('Idle'));
    check('H67 idle -> dressed',      hIdle and hIdle.Body, 'Field Tunica');
    local hEvt = dispatchM._helmOverlayFor(hsOn, stCtx('Event'));
    check('H68 event -> stays dressed (no per-swing churn)', hEvt and hEvt.Body, 'Field Tunica');
    local hNoP = dispatchM._helmOverlayFor(hsOn, { player = nil });
    check('H69 unreadable status -> dressed (idle assumption)', hNoP and hNoP.Body, 'Field Tunica');
    dispatchM._autoOverride = nil;
end)();

-- ---------------------------------------------------------------------------
-- GD. shipped conditional-effects data pins (data\gearsets.lua +
--     data\latentstats.lua) -- regeneration guards, the smoke_ui S21 style.
--     Shapes verified against the server source 2026-07-17 (design Appendix C).
-- ---------------------------------------------------------------------------
(function()
    local gsD = dofile('data/gearsets.lua');
    local nSets, nFlat, nTiered = 0, 0, 0;
    local census = {};
    local tierKeysOk, piecesOk = true, true;
    for _, e in pairs(gsD) do
        nSets = nSets + 1;
        local tn = 0;
        for c in pairs(e.tiers) do
            tn = tn + 1;
            if c < e.min or c > e.max then tierKeysOk = false; end
        end
        if tn == 1 then nFlat = nFlat + 1; else nTiered = nTiered + 1; end
        census[e.min .. '/' .. e.max] = (census[e.min .. '/' .. e.max] or 0) + 1;
        for _, pid in ipairs(e.pieces) do
            if type(pid) ~= 'number' or pid <= 0 then piecesOk = false; end
        end
    end
    check('GD1 126 gear sets ship', nSets, 126);
    check('GD2 flat/tiered split', nFlat .. '/' .. nTiered, '39/87');
    check('GD3 min/max shape census', (census['2/2'] or 0) .. ',' .. (census['2/4'] or 0) .. ','
        .. (census['2/5'] or 0) .. ',' .. (census['5/5'] or 0), '20,1,86,19');
    check('GD4 every tier key within [min,max]', tierKeysOk, true);
    check('GD5 every piece id is a positive number', piecesOk, true);
    local s70 = gsD[70];   -- Lava's + Kusha's, THE reference set
    check('GD6 [70] pieces', s70 ~= nil and (s70.pieces[1] .. ',' .. s70.pieces[2]), '15850,15851');
    check('GD7 [70] min/max', s70 ~= nil and (s70.min .. '/' .. s70.max), '2/2');
    check('GD8 [70] tier values', s70 ~= nil and (s70.tiers[2].Attack .. ',' .. s70.tiers[2].Accuracy
        .. ',' .. s70.tiers[2].DEF), '6,12,6');
    local s43 = gsD[43];   -- Paramount: alternates -- MORE pieces than the cap
    check('GD9 [43] alternate-piece shape (9 pieces, min2/max2)',
        s43 ~= nil and (#s43.pieces .. '/' .. s43.min .. '/' .. s43.max), '9/2/2');

    local lsD = dofile('data/latentstats.lua');
    local rows, items, levelLeak = 0, 0, false;
    for _, rr in pairs(lsD) do
        items = items + 1;
        for _, r in ipairs(rr) do
            rows = rows + 1;
            -- latent 50/51 rows belong to levelscaling.lua, NEVER here (the
            -- routing boundary -- gen_levelscaling.py's old latent-52 bug class)
            if r.cond == 'JOB_LEVEL_ABOVE' or r.cond == 'JOB_LEVEL_BELOW' then levelLeak = true; end
        end
    end
    -- windows re-pinned 2026-07-19: generator now unions the live API's per-item
    -- latents (tools/api_cache) with the repo SQL -- live-only content (the CEXI
    -- "+1" leveling line, Malphas set, ...) added ~470 rows.
    check('GD10 latentstats rows in range', rows >= 2100 and rows <= 2500, true);
    check('GD11 latentstats items in range', items >= 850 and items <= 980, true);
    check('GD12 zero level-latent rows leaked', levelLeak, false);
    local spot = lsD[11312];
    check('GD13 spot row 11312 (STR +5 while TP > 100)', spot ~= nil
        and (spot[1].stat .. '/' .. spot[1].add .. '/' .. spot[1].cond .. '/' .. spot[1].param),
        'STR/5/TP_OVER/100');
end)();

-- ---------------------------------------------------------------------------
-- GE. geareffects -- the pure set-bonus evaluator (conditional-effects P1).
--     Semantics pinned to the server applier: value-at-count replacement tiers,
--     tiers[min(count,max)] with nil below min, per-SLOT counting (duplicates
--     twice), and the level gate (a piece above ctx.level stops counting while
--     its stats still sum).
-- ---------------------------------------------------------------------------
(function()
    local gfe = dofile('gear/geareffects.lua');
    gfe.configure({ gearsets = {
        [1] = { pieces = { 1001, 1002 }, min = 2, max = 2,          -- the Lava/Kusha shape
                tiers = { [2] = { Attack = 6, Accuracy = 12, DEF = 6 } } },
        [2] = { pieces = { 1101, 1102, 1103, 1104, 1105 }, min = 2, max = 5,   -- Iron Ram shape
                tiers = { [2] = { FireMagicEva = 5 }, [3] = { FireMagicEva = 10 },
                          [4] = { FireMagicEva = 15 }, [5] = { FireMagicEva = 30 } } },
        [3] = { pieces = { 1201, 1202, 1203, 1204, 1205, 1206, 1207, 1208, 1209 },
                min = 2, max = 2, tiers = { [2] = { STR = 3 } } },  -- alternates (any 2 of 9)
        [4] = { pieces = { 1001, 1301 }, min = 2, max = 2,          -- 1001 is in TWO sets
                tiers = { [2] = { VIT = 2 } } },
        [5] = { pieces = { 1401, 1402, 1403, 1404, 1405 }, min = 5, max = 5,   -- the min-5 JSE shape
                tiers = { [5] = { Haste = 5 } } },
    } });
    local so = gfe.setsOf(1001);
    check('GE1 multi-set membership, sorted', so ~= nil and (#so .. ':' .. so[1] .. ',' .. so[2]), '2:1,4');
    check('GE2 non-member items return nil (zero-alloc)', gfe.setsOf(9999), nil);
    check('GE3 below min -> no tier', gfe.setTier(1, 1), nil);
    check('GE4 tier at count', gfe.setTier(1, 2).Accuracy, 12);
    check('GE5 count clamps at max', gfe.setTier(1, 5).Accuracy, 12);
    check('GE6 tier value is the TOTAL at that count (replacement)', gfe.setTier(2, 3).FireMagicEva, 10);

    local lava  = { Id = 1001, Name = 'Lava Ring',  Level = 30, Stats = { Accuracy = 5 } };
    local kusha = { Id = 1002, Name = 'Kusha Ring', Level = 30, Stats = { Attack = 2 } };
    local res = gfe.comboStats({ Ring1 = lava, Ring2 = kusha }, { level = 75 });
    check('GE7 combo folds item stats + bonus (Accuracy)', res.stats.Accuracy, 17);
    check('GE8 combo folds item stats + bonus (Attack)', res.stats.Attack, 8);
    check('GE9 bonus-only stat appears', res.stats.DEF, 6);
    local sb1, sb4;
    for _, sb in ipairs(res.setBonuses) do
        if sb.setId == 1 then sb1 = sb; end
        if sb.setId == 4 then sb4 = sb; end
    end
    check('GE10 active bonus row (count/tier/active)',
        sb1 ~= nil and (sb1.count .. '/' .. sb1.tier .. '/' .. tostring(sb1.active)), '2/2/true');
    check('GE11 partial set listed inactive (the "one more piece" row)',
        sb4 ~= nil and (sb4.count .. '/' .. tostring(sb4.active)), '1/false');

    -- per-SLOT counting: the SAME record in both ring slots counts twice
    local dup = gfe.comboStats({ Ring1 = lava, Ring2 = lava }, { level = 75 });
    local dupRow;
    for _, sb in ipairs(dup.setBonuses) do if sb.setId == 1 then dupRow = sb; end end
    check('GE12 duplicates count per slot (server-verified)',
        dupRow ~= nil and (dupRow.count .. '/' .. tostring(dupRow.active)), '2/true');

    -- level gate: an over-level piece stops COUNTING; its stats still sum
    local high = { Id = 1002, Name = 'Kusha Ring', Level = 70, Stats = { Attack = 2 } };
    local sync = gfe.comboStats({ Ring1 = lava, Ring2 = high }, { level = 50 });
    local syncRow;
    for _, sb in ipairs(sync.setBonuses) do if sb.setId == 1 then syncRow = sb; end end
    check('GE13 level-sync gate strips the count', syncRow ~= nil and syncRow.count, 1);
    check('GE14 ...but never the item stats', sync.stats.Attack, 2);
    local nilctx = gfe.comboStats({ Ring1 = lava, Ring2 = high }, nil);
    local nilRow;
    for _, sb in ipairs(nilctx.setBonuses) do if sb.setId == 1 then nilRow = sb; end end
    check('GE15 nil ctx -> no gate', nilRow ~= nil and nilRow.count, 2);

    -- alternates activate on ANY two pieces -- weapon+weapon included
    local alt = gfe.comboStats({
        Main = { Id = 1201, Name = 'Alt A', Level = 1, Stats = {} },
        Sub  = { Id = 1205, Name = 'Alt B', Level = 1, Stats = {} },
    }, { level = 75 });
    local altRow;
    for _, sb in ipairs(alt.setBonuses) do if sb.setId == 3 then altRow = sb; end end
    check('GE16 alternates: any 2 of 9 activates', altRow ~= nil and tostring(altRow.active) .. '/'
        .. tostring(alt.stats.STR), 'true/3');

    -- itemStats stays the zero-copy levelstats passthrough
    local plain = { Name = 'Plain Ring', Level = 1, Stats = { MND = 2 } };
    check('GE17 itemStats zero-copy passthrough', gfe.itemStats(plain, { level = 75 }) == plain.Stats, true);

    -- THE threshold rule (Henrik, 2026-07-18): below a set's minimum the bonus
    -- does not exist AT ALL -- no halves, no per-piece fractions. A min-5 set at
    -- four pieces grants nothing anywhere (display marks it inactive; totals and
    -- the optimizer see zero).
    check('GE19 min-5 set at 4 pieces: no tier at all', gfe.setTier(5, 4), nil);
    local function jse(n)
        local comp = {};
        for i = 1, n do
            comp['S' .. i] = { Id = 1400 + i, Name = 'JSE ' .. i, Level = 30, Stats = {} };
        end
        return gfe.comboStats(comp, { level = 75 });
    end
    local four, five = jse(4), jse(5);
    local fourRow, fiveRow;
    for _, sb in ipairs(four.setBonuses) do if sb.setId == 5 then fourRow = sb; end end
    for _, sb in ipairs(five.setBonuses) do if sb.setId == 5 then fiveRow = sb; end end
    check('GE20 four of five: zero bonus in totals, row inactive',
        tostring(four.stats.Haste) .. '/' .. tostring(fourRow ~= nil and fourRow.active), 'nil/false');
    check('GE21 all five: the full bonus, whole', five.stats.Haste .. '/' .. tostring(fiveRow.active), '5/true');

    -- augment fold (ctx.augStats = { itemId -> deltas }): the caller's private
    -- augments ride THE evaluator, so Set totals, the weighted score, and every
    -- future consumer read identical numbers (Henrik's field case: Refresh+1
    -- body native + Refresh+1 legs augment showed "+1" in Set totals while the
    -- score already counted +2).
    local body = { Id = 2001, Name = 'Refresh Body', Level = 40, Stats = { Refresh = 1 } };
    local legs = { Id = 2002, Name = 'Plain Legs',   Level = 40, Stats = {} };
    local augd = gfe.comboStats({ Body = body, Legs = legs },
        { level = 75, augStats = { [2002] = { Refresh = 1, Note = 'hq' } } });
    check('GE22 augStats folds private augment deltas (base+aug)', augd.stats.Refresh, 2);
    check('GE23 non-numeric augment values never leak into totals', augd.stats.Note, nil);
    local noaug = gfe.comboStats({ Body = body, Legs = legs }, { level = 75 });
    check('GE24 no augStats -> base only (back-compat)', noaug.stats.Refresh, 1);
    -- per-SLOT like everything else: the same augmented ring worn twice folds twice
    local dupA = gfe.comboStats({ Ring1 = lava, Ring2 = lava },
        { level = 75, augStats = { [1001] = { Accuracy = 3 } } });
    check('GE25 augment deltas count per SLOT (5+5 base, 12 set, 3+3 aug)', dupA.stats.Accuracy, 28);

    -- the REAL shipped data end-to-end: worn Lava's + Kusha's (ids 15850/15851)
    local gfe2 = dofile('gear/geareffects.lua');
    gfe2.configure({ gearsets = dofile('data/gearsets.lua') });
    local worn = gfe2.comboStats({
        Ring1 = { Id = 15850, Name = "Lava's Ring",  Level = 30, Stats = {} },
        Ring2 = { Id = 15851, Name = "Kusha's Ring", Level = 30, Stats = {} },
    }, { level = 75 });
    check('GE18 shipped data: Lava+Kusha bonus', (worn.stats.Attack or 0) .. '/'
        .. (worn.stats.Accuracy or 0) .. '/' .. (worn.stats.DEF or 0), '6/12/6');
end)();

-- ---------------------------------------------------------------------------
-- HB. optimizePicks gear-set crediting (conditional-effects P3, ADR 0011):
--     the bonus term inside the capped objective, incremental per-slot counts,
--     and the set-seeded restarts that find pairs single-slot climbing cannot.
-- ---------------------------------------------------------------------------
(function()
    -- synthetic effects seam (no geareffects needed: optimizePicks only sees fns)
    local SETS = {
        [1] = { pieces = { 101, 102 }, min = 2, max = 2, tiers = { [2] = { Accuracy = 12 } } },
        [2] = { pieces = { 201, 202, 203, 204, 205 }, min = 2, max = 5,
                tiers = { [2] = { Accuracy = 4 }, [3] = { Accuracy = 6 },
                          [4] = { Accuracy = 6 }, [5] = { Accuracy = 30 } } },
        [3] = { pieces = { 301, 302 }, min = 2, max = 2, tiers = { [2] = { Haste = 5 } } },
    };
    local BYITEM = {};
    for sid, e in pairs(SETS) do
        for _, pid in ipairs(e.pieces) do
            BYITEM[pid] = BYITEM[pid] or {};
            table.insert(BYITEM[pid], sid);
        end
    end
    local fx = {
        setsOf  = function(id) return BYITEM[id]; end,
        setTier = function(sid, c)
            local e = SETS[sid];
            if e == nil or c < e.min then return nil; end
            return e.tiers[math.min(c, e.max)];
        end,
    };
    local W3 = { Accuracy = { perUnit = 3 } };
    local function mk(id, name, stats) return { stats = stats, ref = { Id = id, Name = name } }; end

    -- HB1: the numeric objective pin (H3-style): both set rings placed, bonus in
    local p1, p2 = mk(101, 'SetRing A', { Accuracy = 2 }), mk(102, 'SetRing B', { Accuracy = 2 });
    local hb1 = optim.optimizePicks({ Ring1 = { p1 }, Ring2 = { p2 } }, W3, { effects = fx });
    check('HB1 bonus inside the objective', hb1.total, 3 * (2 + 2 + 12));

    -- HB2: pair discovery -- each piece is a solo LOSS vs its rival; only a
    -- seeded restart can enter the bonus
    local z1, z2 = mk(101, 'SetRing A', { Accuracy = 0 }), mk(102, 'SetRing B', { Accuracy = 0 });
    local rvA, rvB = mk(901, 'Rival A', { Accuracy = 5 }), mk(902, 'Rival B', { Accuracy = 5 });
    local hb2 = optim.optimizePicks({ Ring1 = { rvA, z1 }, Ring2 = { rvB, z2 } }, W3,
        { effects = fx, conflict = function(a, b) return a == b; end });
    check('HB2 seeded restart finds the pair', hb2.total, 3 * 12);
    check('HB2b ...both set pieces picked', tostring(hb2.picks.Ring1) .. ',' .. tostring(hb2.picks.Ring2), '2,2');

    -- HB3: a bonus that exactly offsets stays EMPTY (strict improvement + the
    -- EMPTY tie preference survive the bonus term); partner via baseComposition
    local neg = mk(101, 'SetRing A', { Accuracy = -12 });
    local hb3 = optim.optimizePicks({ Ring1 = { neg } }, W3,
        { effects = { setsOf = fx.setsOf, setTier = fx.setTier,
                      baseComposition = { { Id = 102, Name = 'SetRing B' } } } });
    check('HB3 exact offset keeps EMPTY', hb3.picks.Ring1, nil);

    -- HB4: one owned copy -- the conflict beats the set (count stays 1, no bonus)
    local cA, cB = mk(101, 'SetRing A', { Accuracy = 2 }), mk(101, 'SetRing A', { Accuracy = 2 });
    local oneCopy = function(a, b)
        if a == b or (a.Id ~= nil and a.Id == b.Id) then return true; end
        return false;
    end
    local hb4 = optim.optimizePicks({ Ring1 = { cA }, Ring2 = { cB } }, W3,
        { effects = fx, conflict = oneCopy });
    local filled4 = (hb4.picks.Ring1 and 1 or 0) + (hb4.picks.Ring2 and 1 or 0);
    check('HB4 conflict beats set: one slot, no bonus', filled4 .. '/' .. hb4.total, '1/' .. (3 * 2));
    -- HB4b: two owned copies -- per-slot counting credits the SAME item twice
    local hb4b = optim.optimizePicks({ Ring1 = { cA }, Ring2 = { cB } }, W3,
        { effects = fx, conflict = function() return false; end });
    check('HB4b two copies activate the set', hb4b.total, 3 * (2 + 2 + 12));

    -- HB5: seed eviction + monotone acceptance -- a dominated set dissolves back
    local i1, i2 = mk(911, 'Indep A', { Accuracy = 10 }), mk(912, 'Indep B', { Accuracy = 10 });
    local w1, w2 = mk(101, 'SetRing A', { Accuracy = 1 }), mk(102, 'SetRing B', { Accuracy = 1 });
    local hb5 = optim.optimizePicks({ Ring1 = { i1, w1 }, Ring2 = { i2, w2 } }, W3,
        { effects = { setsOf = fx.setsOf,
                      setTier = function(sid, c) return (sid == 1 and c >= 2) and { Accuracy = 5 } or nil; end },
          conflict = function(a, b) return a == b; end });
    check('HB5 dominated seed dissolves to the baseline', hb5.total, 3 * 20);
    check('HB5b independents kept', tostring(hb5.picks.Ring1) .. ',' .. tostring(hb5.picks.Ring2), '1,1');

    -- HB6: cap sharing -- a bonus above the cap adds nothing, so a cap-redundant
    -- set stays home (H5's analog through the bonus fold)
    local WH = { Haste = { perUnit = 100, cap = 5 } };
    local hHat = mk(920, 'Haste Hat', { Haste = 5 });
    local s1, s2 = mk(301, 'SetPiece A', { Haste = 0 }), mk(302, 'SetPiece B', { Haste = 0 });
    local hb6 = optim.optimizePicks({ Head = { hHat }, Ring1 = { s1 }, Ring2 = { s2 } }, WH, { effects = fx });
    check('HB6 capped bonus stays home', tostring(hb6.picks.Ring1) .. '/' .. hb6.total, 'nil/500');

    -- HB7: effects present but nothing set-carrying -> bit-identical totals
    local W = { Haste = { perUnit = 100, cap = 5 }, SwordSkill = { perUnit = 2 }, Accuracy = { perUnit = 3 } };
    local hasteHat  = { stats = { Haste = 5 },                               ref = 'HasteHat'  };
    local statHat   = { stats = { Accuracy = 5 },                            ref = 'StatHat'   };
    local greatFeet = { stats = { Haste = 5, SwordSkill = 7, Accuracy = 5 }, ref = 'GreatFeet' };
    local weakFeet  = { stats = { Accuracy = 2 },                            ref = 'WeakFeet'  };
    local hb7 = optim.optimizePicks({ Head = { hasteHat, statHat }, Feet = { greatFeet, weakFeet } }, W,
        { effects = fx });
    check('HB7 no set-carrying candidate: H3 total bit-identical', hb7.total, 100 * 5 + 2 * 7 + 3 * (5 + 5));

    -- HB8: tiered marginal -- 3 pieces credit tiers[3], the 4th enters only when
    -- its tier step pays (tiers[4]-tiers[3] = 0 here -> stays home)
    local t1, t2, t3 = mk(201, 'Tier A', { Accuracy = 1 }), mk(202, 'Tier B', { Accuracy = 1 }),
                       mk(203, 'Tier C', { Accuracy = 1 });
    local t4 = mk(204, 'Tier D', { Accuracy = 0 });
    local hb8 = optim.optimizePicks({ Ring1 = { t1 }, Ring2 = { t2 }, Neck = { t3 }, Head = { t4 } },
        W3, { effects = fx });
    check('HB8 three pieces credit tiers[3]', hb8.total, 3 * (3 + 6));
    check('HB8b zero-step 4th piece stays home', hb8.picks.Head, nil);
    -- ...and a PAYING tier step pulls the 4th piece in (private tier fn: step +14)
    local fx4 = { setsOf = fx.setsOf, setTier = function(sid, c)
        if sid ~= 2 or c < 2 then return nil; end
        return ({ [2] = { Accuracy = 4 }, [3] = { Accuracy = 6 }, [4] = { Accuracy = 20 } })[math.min(c, 4)];
    end };
    local hb8c = optim.optimizePicks({ Ring1 = { t1 }, Ring2 = { t2 }, Neck = { t3 }, Head = { t4 } },
        W3, { effects = fx4 });
    check('HB8c paying tier step pulls the 4th piece', hb8c.picks.Head ~= nil and hb8c.total, 3 * (3 + 20));

    -- HB9: baseComposition partner -- a lone worthless pool piece is credited
    -- the bonus its already-chosen partner completes (the Sub marginal case)
    local lone = mk(101, 'SetRing A', { Accuracy = 0 });
    local hb9 = optim.optimizePicks({ Ring1 = { lone } }, W3,
        { effects = { setsOf = fx.setsOf, setTier = fx.setTier,
                      baseComposition = { { Id = 102, Name = 'SetRing B' } } } });
    check('HB9 baseComposition partner credits the bonus',
        tostring(hb9.picks.Ring1) .. '/' .. hb9.total, '1/' .. (3 * 12));
end)();

-- ---------------------------------------------------------------------------
-- HB10+. buildBestSet through a geareffects-wired gearoptim instance: the
--        append-only pool augmentation + seeding, end to end -- and the greedy
--        Range/Ammo path staying set-blind (a bonus never legalizes a pairing).
-- ---------------------------------------------------------------------------
(function()
    local savedGfx = package.loaded['dlac\\gear\\geareffects'];
    local savedGear = package.loaded['dlac\\gear'];
    local gfe = dofile('gear/geareffects.lua');
    gfe.configure({ gearsets = {
        [7] = { pieces = { 610, 611 }, min = 2, max = 2, tiers = { [2] = { Accuracy = 50 } } },
        [8] = { pieces = { 601, 602 }, min = 2, max = 2, tiers = { [2] = { Accuracy = 99 } } },
    } });
    package.loaded['dlac\\gear\\geareffects'] = gfe;

    -- 21 Head fillers rank ABOVE the set piece, pushing it past the top-20
    -- prune: only the augmentation can put it in front of the optimizer.
    local G2 = { NameToObject = {}, Head = {}, Neck = {} };
    for i = 1, 21 do
        G2.Head['Filler ' .. i] = { Name = 'Filler ' .. string.char(64 + i), Level = 1, Id = 700 + i,
                                    Jobs = { 'All' }, Stats = { Accuracy = 4 + i } };
    end
    G2.Head['Set Sallet'] = { Name = 'Set Sallet', Level = 1, Id = 610, Jobs = { 'All' },
                              Stats = { Accuracy = 0 } };
    G2.Neck['Set Gorget'] = { Name = 'Set Gorget', Level = 1, Id = 611, Jobs = { 'All' },
                              Stats = { Accuracy = 0 } };
    package.loaded['dlac\\gear'] = G2;
    local optB = dofile('gear/gearoptim.lua');
    local hb11 = optB.buildBestSet({ job = 'WAR', level = 75, weights = { Accuracy = { perUnit = 3 } } });
    check('HB11 augmented pool + seeding win the set pair',
        tostring(hb11.slots.Head) .. '+' .. tostring(hb11.slots.Neck), 'Set Sallet+Set Gorget');
    check('HB11b whole-set total is the bonus', hb11.total, 3 * 50);

    -- HB10: the greedy single-stat path stays SET-BLIND (ADR 0011): an unfirable
    -- stat stick still wins the Ammo slot and Range still empties, set data or not
    local function it(name, acc, extra)
        local e = { Name = name, Level = 1, Id = 0, Jobs = { 'All' }, Stats = { Accuracy = acc } };
        for k, v in pairs(extra or {}) do e[k] = v; end
        return e;
    end
    G2.Range = { Archery = { it('Test Bow', 10, { Type = 'Archery', Id = 601 }) } };
    G2.Ammo  = { stick = it('Cinderstone', 20, { Id = 602 }) };
    local r = optB.buildMaxStatSet('Accuracy', { job = 'WAR', level = 99 });
    check('HB10 greedy path set-blind: unfirable ammo still wins', r.slots.Ammo, 'Cinderstone');
    check('HB10b ...and Range stays EMPTY despite the set', r.slots.Range, nil);

    package.loaded['dlac\\gear'] = savedGear;
    package.loaded['dlac\\gear\\geareffects'] = savedGfx;
end)();

-- ---------------------------------------------------------------------------
-- FISHING: fishcalc verdict math (server formulas, hand-computed cases) +
-- fishdb integrity + fishwatch state/pick rules + the engine's dlac:AutoFish
-- overlay (v64) -- docs/design/fishing-gear.md. The fail-chance expectations
-- below are derived BY HAND from fishingutils.cpp CalculateLoseChance :719 /
-- CalculateSnapChance :784 / CalculateBreakChance :828 -- if a port edit
-- moves one of these numbers, re-derive from the C++ before touching the test.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\data\\fishdb'] = dofile('data/fishdb.lua');
    local fcalc = dofile('feature/fishcalc.lua');
    package.loaded['dlac\\feature\\fishcalc'] = fcalc;

    -- pure verdict math on synthetic records (no db involved)
    local marlin  = { sk = 61, rank = 23, sz = 1 };
    local halcyon = { sz = 0, minR = 1, maxR = 18, brk = 1 };
    local ebisuR  = { sz = 0, minR = 1, maxR = 30, leg = 1 };
    local v = fcalc.verdictFor(marlin, halcyon, 50);
    check('F1 big fish, small rod: lose=toobig 50', v.lose .. '/' .. tostring(v.loseWhy), '50/toobig');
    check('F2 big fish, small rod: snap capped 55', v.snap, 55);
    check('F3 big fish, small rod: break 9',        v.brk, 9);
    v = fcalc.verdictFor(marlin, ebisuR, 50);
    check('F4 same fish on Ebisu: lose=lowskill 3', v.lose .. '/' .. tostring(v.loseWhy), '3/lowskill');
    check('F5 Ebisu: no snap',  v.snap, 0);
    check('F6 Ebisu never breaks', v.brk, 0);
    local legFish = { sk = 100, rank = 30, sz = 1, leg = 1 };
    local luShang = { sz = 0, minR = 1, maxR = 28, brk = 1, leg = 1 };
    v = fcalc.verdictFor(legFish, luShang, 100);
    check('F7 legendary on legendary rod at skill: SAFE', v.ok, true);
    v = fcalc.verdictFor(legFish, halcyon, 100);
    check('F8 legendary on normal rod: lose toobig', tostring(v.loseWhy), 'toobig');
    check('F9 legendary on normal rod: snap 55',     v.snap, 55);
    check('F10 legendary on normal rod: break 19',   v.brk, 19);
    -- the uint8-wrap quirk: over-skill "rebate" past zero wraps high -> 50
    v = fcalc.verdictFor({ sk = 5, rank = 10, sz = 1 }, { sz = 0, minR = 1, maxR = 5, brk = 1 }, 100);
    check('F11 toobig uint8 wrap clamps to 50', v.lose .. '/' .. tostring(v.loseWhy), '50/toobig');
    -- tooSmall has the guarded subtraction (source :753) -> floors at zero
    local largeRod = { sz = 1, minR = 8, maxR = 18, brk = 1 };
    v = fcalc.verdictFor({ sk = 5, rank = 1, sz = 0 }, largeRod, 100);
    check('F12 toosmall guarded to zero at high skill', v.lose, 0);
    v = fcalc.verdictFor({ sk = 5, rank = 1, sz = 0 }, largeRod, 30);
    check('F13 toosmall mid-skill', v.lose .. '/' .. tostring(v.loseWhy), '25/toosmall');
    v = fcalc.verdictFor({ sk = 99, rank = 1, sz = 0 }, { sz = 0, minR = 1, maxR = 5, brk = 1 }, 1);
    check('F14 lowskill capped at 55', v.lose .. '/' .. tostring(v.loseWhy), '55/lowskill');

    -- fishdb integrity (the shipped data the panel trusts)
    local db = fcalc.db();
    check('F15 fishdb loads through fishcalc', db ~= nil, true);
    local nFish = 0; for _ in pairs(db.fish) do nFish = nFish + 1; end
    local nRods = 0; for _ in pairs(db.rods) do nRods = nRods + 1; end
    local nBaits = 0; for _ in pairs(db.baits) do nBaits = nBaits + 1; end
    check('F16 fish table populated (>=120)', nFish >= 120, true);
    check('F17 all 20 public rods', nRods, 20);
    check('F18 all 39 baits', nBaits, 39);
    check('F19 Moat Carp', db.fish[4401] ~= nil and db.fish[4401].n, 'Moat Carp');
    check('F20 Moat Carp hook level', db.fish[4401].sk, 11);
    check('F21 Ebisu legendary + unbreakable', (db.rods[17011].leg or 0) == 1 and (db.rods[17011].brk or 0) == 0, true);
    check('F22 Lu Shang breaks to 489', db.rods[17386].brokenId, 489);
    check('F23 Little Worm hooks Moat Carp', db.aff[17396] ~= nil and db.aff[17396][4401] ~= nil, true);
    check('F24 search finds the carp', (fcalc.searchFish('moat')[1] or {}).id, 4401);
    check('F25 carp takes baits', #fcalc.baitsFor(4401) > 0, true);
    local iso = fcalc.isolationFor(4291);   -- Sandfish: the generator-verified case
    check('F26 sandfish has isolation rows', #iso > 0, true);
    check('F27 cleanest row first', iso[1].clean, true);
    check('F28 gearBonus: Ebisu cx4', (db.gearBonus[17011] or {}).cx4, 10);
    check('F29 gearBonus: Halieutica is a Main', (db.gearBonus[20945] or {}).sl, 'Main');
    check('F30 gearBonus: Eyepatch carries only cx', (db.gearBonus[28443] or {}).fish == nil
        and (db.gearBonus[28443] or {}).cx4 == 20, true);
    check('F31 guild rank 1 test fish is the carp', db.guild.rankFish[1], 4401);
    check('F32 eleven guild ranks', #db.guild.ranks, 11);
    -- a legendary fish exists and Ebisu beats a twig for it
    local legId = nil;
    for id, f in pairs(db.fish) do if (f.leg or 0) == 1 then legId = id; break; end end
    check('F33 a legendary fish ships', legId ~= nil, true);
    if legId ~= nil then
        local best = fcalc.bestOwnedRod(db.fish[legId], 100, { [17391] = true, [17011] = true });
        check('F34 legendary target -> Ebisu over Willow', best ~= nil and best.id, 17011);
    end
    check('F35 gearScore: verified Fish beats unverified cx', fcalc.gearScore(1, nil) > fcalc.gearScore(0, { cx4 = 50, cx5 = 5 }), true);

    -- fishwatch: state rules + rod/bait auto-pick (headless seams)
    local fw = dofile('feature/fishwatch.lua');
    check('F36 pill starts off', fw.isEnabled(), false);
    local lines = fw.parseVentureLine('Fishing: (Low) Selbina, (Mid) Qufim Island, (High) Sea of Shadows');
    check('F37 fishing venture line: 3 tiers', lines ~= nil and #lines or 0, 3);
    check('F37b low tier', lines ~= nil and lines[1], 'Low:  Selbina');
    check('F38 helm categories are not ours', fw.parseVentureLine('Mining: (Low) Ordelles Caves, (Mid) X, (High) Y'), nil);
    local drift = fw.parseVentureLine('Fishing: something new the server said');
    check('F39 drifted format keeps raw tail', drift ~= nil and drift[1], 'something new the server said');
    check('F40 chatter -> nil', fw.parseVentureLine('gone fishing brb'), nil);
    check('F41 jst rollover', fw.jstDay(15 * 3600) - fw.jstDay(0), 1);
    fw._clientName = function(id)
        return ({ [17390] = 'Yew Fishing Rod', [17391] = 'Willow Fish. Rod',
                  [17396] = 'Little Worm' })[id];
    end
    fw._ownedAvail = { [17391] = 1, [17390] = 1, [17396] = 99 };
    fw.setTarget(4401);
    local rid = select(1, fw.getRod());
    check('F42 target set', select(2, fw.getTarget()), 'Moat Carp');
    -- at skill 0 the Yew (durability 6) out-risks the Willow (5) on a rank-7
    -- carp: snap 8 vs 17 -- the verdict sort must prefer it
    check('F43 rod pick minimizes risk (Yew over Willow)', rid, 17390);
    check('F44 rod stamped with the CLIENT name', select(2, fw.getRod()), 'Yew Fishing Rod');
    check('F45 bait picked from owned affinity', select(1, fw.getBait()), 17396);
    -- explicit bait choice survives re-picks while stocked
    local carpBaits = fcalc.baitsFor(4401);
    local altBait = nil;
    for _, e in ipairs(carpBaits) do if e.id ~= 17396 then altBait = e.id; break; end end
    if altBait ~= nil then
        fw._ownedAvail[altBait] = 12;
        fw.setTarget(4401, altBait);
        check('F46 explicit bait honoured', select(1, fw.getBait()), altBait);
        fw.autoPick(true);
        check('F47 explicit bait survives autoPick(keep)', select(1, fw.getBait()), altBait);
        fw._ownedAvail[altBait] = nil;
    end
    -- THE ISOLATION RULE under the bag heartbeat: a rod-only loss must re-pick
    -- the ROD and leave the user's explicit (lower-power) isolation bait alone.
    -- revalidate passed keepBait=false, silently trading it up to the strongest
    -- stocked bait -- and saying nothing, because the bait announcement only
    -- fires when the BAIT stack emptied (review find, 2026-07-18).
    local topBait = (carpBaits[1] or {}).id;
    local lowBait = (carpBaits[#carpBaits] or {}).id;
    if lowBait ~= nil and topBait ~= nil and lowBait ~= topBait then
        fw._ownedAvail = { [17391] = 1, [17390] = 1, [topBait] = 50, [lowBait] = 12 };
        fw.setTarget(4401, lowBait);              -- the user's isolation pick
        fw.setEnabled(true);
        fw._ownedAvail[17390] = nil;              -- the worn Yew vanishes; Willow remains
        fw.revalidate();
        check('F47b rod-only heartbeat re-picks the rod', select(1, fw.getRod()), 17391);
        check('F47c ...and the explicit ISOLATION bait survives (never traded for power)',
            select(1, fw.getBait()), lowBait);
        fw.setEnabled(false);
        fw._ownedAvail = { [17391] = 1, [17390] = 1, [17396] = 99 };
        fw.setTarget(4401);                       -- re-arm the exhaustion flow below
    end
    fw.setEnabled(true);
    check('F48 pill on', fw.isEnabled(), true);
    fw._ownedAvail = { [17390] = 1 };   -- bait stack gone, rod still here
    fw.revalidate();
    check('F49 exhausted bait cleared (nothing suitable left)', select(1, fw.getBait()), nil);
    fw._ownedAvail = {};                -- rod gone too
    fw.revalidate();
    check('F50 vanished rod cleared', select(1, fw.getRod()), nil);
    fw.setEnabled(false);

    -- engine: fishStateActive + the dlac:AutoFish overlay
    local act = dispatchM._fishStateActive;
    check('F51 enabled state active', act({ enabled = true }), true);
    check('F52 disabled state inactive', act({ enabled = false }), false);
    check('F53 nil state inactive', act(nil), false);
    dispatchM._autoOverride = { fish = {
        main = { { name = 'Halieutica', score = 2105, level = 1, fish = 2 } },
        body = { { name = 'Anglers Tunica', score = 1000, level = 15, fish = 1 },
                 { name = 'Fsh. Tunica',    score = 1000, level = 1,  fish = 1 } },
        ring1 = { { name = 'Anglers Ring', score = 2000, level = 75, fish = 2 } },
    } };
    local fs = { enabled = true, at = 1, rod = 'Willow Fish. Rod', bait = 'Little Worm' };
    local fov = dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('F54 rod worn from state', fov and fov.Range, 'Willow Fish. Rod');
    check('F55 bait worn from state', fov and fov.Ammo, 'Little Worm');
    check('F56 Main ladder (Halieutica)', fov and fov.Main, 'Halieutica');
    check('F57 body best rung', fov and fov.Body, 'Anglers Tunica');
    check('F58 ring ladder', fov and fov.Ring1, 'Anglers Ring');
    local fovLow = dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 10, Status = 'Idle' } });
    check('F59 underlevel rung falls through', fovLow and fovLow.Body, 'Fsh. Tunica');
    check('F60 underlevel ring -> slot empty', fovLow and fovLow.Ring1, nil);
    check('F61 engaged -> stands aside', dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 75, Status = 'Engaged' } }), nil);
    check('F62 dead -> stands aside', dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 75, Status = 'Dead' } }), nil);
    local fovEvt = dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 75, Status = 'Event' } });
    check('F63 event stays dressed', fovEvt and fovEvt.Range, 'Willow Fish. Rod');
    check('F64 disabled -> no overlay', dispatchM._fishOverlayFor({ enabled = false, rod = 'X' }, { player = { MainJobSync = 75 } }), nil);
    local fsNoGear = { enabled = true };
    local fovNoRod = dispatchM._fishOverlayFor(fsNoGear, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('F65 no rod picked -> Range untouched, ladders still dress',
        (fovNoRod and fovNoRod.Range) == nil and (fovNoRod and fovNoRod.Body) ~= nil, true);
    -- v91: the rod brings an Ammo claim even with NO bait ('remove') -- an
    -- unclaimed Ammo lets an idle set's stat-stick trinket land beside the
    -- rod and the server strips the rod (ADR 0010), forever.
    local fsNoBait = { enabled = true, at = 1, rod = 'Willow Fish. Rod' };
    local fovNoBait = dispatchM._fishOverlayFor(fsNoBait, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('F68 rod with no bait -> Ammo claimed empty', fovNoBait and fovNoBait.Ammo, 'remove');
    check('F69 ... and the rod still equips', fovNoBait and fovNoBait.Range, 'Willow Fish. Rod');
    check('F70 no rod AND no bait -> Ammo left alone', fovNoRod and fovNoRod.Ammo, nil);
    local fsBaitOnly = { enabled = true, at = 1, bait = 'Little Worm' };
    local fovBaitOnly = dispatchM._fishOverlayFor(fsBaitOnly, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('F71 bait without a rod rides as itself', fovBaitOnly and fovBaitOnly.Ammo, 'Little Worm');
    check('F66 resolveVirtual dlac:AutoFish body', dispatchM._resolveVirtual('dlac:AutoFish',
        { player = { MainJobSync = 75 } }, 'Body'), 'Anglers Tunica');
    check('F67 resolveVirtual unknown fish slot -> nil', dispatchM._resolveVirtual('dlac:AutoFish',
        { player = { MainJobSync = 75 } }, 'Sub'), nil);
    dispatchM._autoOverride = nil;

    -- craftwatch: the fishing guild points offset (0x20) now parses
    local cw2 = dofile('feature/craftwatch.lua');
    local function fi32(v) return string.char(v % 256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/16777216)%256); end
    local pkt = string.rep('\0', 0x20) .. fi32(1111) .. fi32(2555) .. fi32(6536) .. fi32(10990)
        .. fi32(540) .. fi32(23539) .. fi32(0) .. fi32(75200) .. fi32(4325);
    cw2.onCurrencyPacket(pkt);
    check('F68 fishing GP parsed at 0x20', cw2.guildPointsFor('Fishing'), 1111);
    check('F69 craft offsets unmoved', cw2.guildPointsFor('Woodworking'), 2555);

    -- field round 5 (2026-07-18): the legendary tier, manual pins, and the
    -- upgrade heartbeat. Henrik's ruling: "Lu Shang's always beats base rods,
    -- Ebisu always beats Lu Shang's" -- and no pill toggle to get there.

    -- the live bug verbatim: Moat Carp at high skill is risk-0 on everything,
    -- and the old sort let Clothespole's raw attack outrank Lu Shang's
    local poleId = nil;
    for id, r in pairs(db.rods) do
        if (r.n or ''):lower() == 'clothespole' then poleId = id; break; end
    end
    check('F70 Clothespole ships', poleId ~= nil, true);
    if poleId ~= nil then
        local best5 = fcalc.bestOwnedRod(db.fish[4401], 100, { [poleId] = true, [17386] = true });
        check('F70b Lu Shang over Clothespole on the carp', best5 and best5.id, 17386);
    end
    local bestLeg = fcalc.bestOwnedRod(db.fish[4401], 100, { [17386] = true, [17011] = true });
    check('F71 Ebisu over Lu Shang', bestLeg and bestLeg.id, 17011);
    check('F72 legRank tiers ordered', fcalc.legRank(17011) > fcalc.legRank(17386)
        and fcalc.legRank(17386) > fcalc.legRank(17390), true);
    -- risk STILL beats the tier: a fish that would snap Lu Shang's gets the
    -- safe base rod recommended (the whole point of the verdict system)
    local realDb = db;
    fcalc._setDb({ fish = { [1] = { n = 'Brutus', sk = 10, rank = 40, sz = 1 } },
                   rods = { [17386] = { n = 'Lu', leg = 1, brk = 1, sz = 0, minR = 1, maxR = 28 },
                            [900] = { n = 'Big Safe Rod', sz = 1, minR = 1, maxR = 45, brk = 1 } },
                   baits = {}, aff = {}, pools = {}, zones = {}, mobs = {} });
    local rRisk = fcalc.rodsFor(fcalc.db().fish[1], 100, { [17386] = true, [900] = true });
    check('F73 risk beats the legendary tier', rRisk[1] and rRisk[1].id, 900);
    fcalc._setDb(realDb);

    -- manual pins (the fish bar dropdowns): a pin holds through the heartbeat,
    -- falls back to auto when the item vanishes, and target changes unpin
    fw._ownedAvail = { [17391] = 1, [17390] = 1, [17396] = 99 };
    fw.setTarget(4401);
    fw.setEnabled(true);
    check('F74 auto rod first (least-risk Yew)', select(1, fw.getRod()), 17390);
    fw.setRod(17391);                          -- the user says Willow
    check('F75 manual rod set + pinned', select(1, fw.getRod()) == 17391 and fw.rodPinned(), true);
    fw.revalidate();                           -- the beat must NOT trade it back
    check('F76 pinned rod survives the heartbeat', select(1, fw.getRod()), 17391);
    fw._ownedAvail[17391] = nil;               -- the pinned rod vanishes
    fw.revalidate();
    check('F77 vanished pin falls back to auto', select(1, fw.getRod()) == 17390 and not fw.rodPinned(), true);
    fw._ownedAvail = { [17391] = 1, [17396] = 99 };   -- Yew gone, only Willow
    fw.revalidate();
    check('F78 vanish still re-picks what exists', select(1, fw.getRod()), 17391);
    fw._ownedAvail[17390] = 1;                 -- the better (least-risk) Yew RETURNS
    fw.revalidate();                           -- no vanish, no toggle -- just the beat
    check('F79 better rod adopted on the beat (the Lu Shang bug)', select(1, fw.getRod()), 17390);
    fw.setRod(17391);                          -- pin Willow again...
    fw.setTarget(4401);                        -- ...then change target
    check('F80 target change unpins', fw.rodPinned(), false);
    -- pinned bait is absolute while stocked -- even off-affinity (the user
    -- may know something fishdb doesn't)
    local offBait = nil;
    for id in pairs(db.baits) do if (db.aff[id] or {})[4401] == nil then offBait = id; break; end end
    check('F81 an off-affinity bait exists', offBait ~= nil, true);
    if offBait ~= nil then
        fw._ownedAvail[offBait] = 3;
        fw.setBait(offBait);
        check('F81b off-affinity manual bait honoured', select(1, fw.getBait()), offBait);
        fw.revalidate();
        check('F82 pinned bait survives the heartbeat', select(1, fw.getBait()), offBait);
        fw.setBait(nil);
        check('F83 AUTO returns the affine pick', select(1, fw.getBait()), 17396);
        fw._ownedAvail[offBait] = nil;
    end
    fw.setEnabled(false);

    -- wornFishTotal moved into fishcalc (fishui + fishbar share it)
    fcalc._setDb({ gearBonus = { [1] = { sl = 'Body', fish = 2 }, [2] = { sl = 'Body', fish = 1 },
                                 [3] = { sl = 'Ring', fish = 1 }, [4] = { sl = 'Range', fish = 5 } },
                   fish = {}, rods = {}, baits = {}, aff = {}, pools = {} });
    check('F84 wornFishTotal: best body + doubled ring, rod excluded',
        fcalc.wornFishTotal({ [1] = 1, [2] = 1, [3] = 2, [4] = 1 }), 4);
    fcalc._setDb(realDb);
end)();

-- ---------------------------------------------------------------------------
-- section GM: game-mode icon detection (feature/gamemode.lua)
-- Field truth 2026-07-18 Tavnazian Safehold (dlacprobe ICON dump): crystal
-- players (UCW Mindie idx 1107, CW Skincrawler idx 1055) carry RenderFlags4
-- 0x1000; Wings (Askar idx 1029) carries 0x4000; ACE (Tcb idx 1074) neither.
-- ---------------------------------------------------------------------------
(function()
    local gamemode = dofile('feature/gamemode.lua');

    AshitaCore = nil;
    check('GM1 headless get -> nil', gamemode.get(), nil);

    -- fake entity table straight from the field capture
    local flagsByIdx = {
        [1107] = 0x40001000,    -- Mindie (UCW, local in the capture)
        [1055] = 0x40001000,    -- Skincrawler (CW)
        [1029] = 0x41004000,    -- Askar (Wings)
        [1074] = 0x41000000,    -- Tcb (ACE)
    };
    local function ashitaWithIcons(selfIdx)
        local em = {
            GetRawEntity    = function(self, i) if flagsByIdx[i] ~= nil then return {}; end return nil; end,
            GetRenderFlags4 = function(self, i) return flagsByIdx[i]; end,
        };
        local party = { GetMemberTargetIndex = function(self, n) return selfIdx; end };
        return { GetMemoryManager = function(self)
            return {
                GetEntity = function(self) return em; end,
                GetParty  = function(self) return party; end,
            };
        end };
    end

    AshitaCore = ashitaWithIcons(1107);
    check('GM2 self (UCW capture) -> CW', gamemode.get(), 'CW');
    check('GM3 remote CW by idx -> CW', gamemode.get(1055), 'CW');
    check('GM4 Wings by idx', gamemode.get(1029), 'Wings');
    check('GM5 ACE by idx', gamemode.get(1074), 'ACE');
    check('GM6 unrendered idx -> nil', gamemode.get(1500), nil);

    AshitaCore = ashitaWithIcons(0);        -- empty party slot: no self index
    check('GM7 no self index -> nil', gamemode.get(), nil);

    -- Ashita hands back SIGNED dwords: a sign-bit flags word must normalize
    flagsByIdx[1107] = 0xC0001000 - 4294967296;
    AshitaCore = ashitaWithIcons(1107);
    check('GM8 negative dword normalized -> CW', gamemode.get(), 'CW');

    AshitaCore = nil;
end)();

-- ---------------------------------------------------------------------------
-- section NMP: native max MP (data/nativemp.lua)
-- Server-formula port (charutils.cpp CalculateStats MP + grades.cpp, stable
-- branch 2026-07-18). Expectations are HAND-computed from the server tables,
-- not from the module -- a table typo fails here. Field pin, FULLY resolved
-- (Henrik 2026-07-18: menu reads 10/10): Mindie Hume WHM75/SCH37 shows 724
-- naked = 614 formula + 100 merits (10 x 10, merit.cpp cap[75]) + 10 SCH-sub
-- Max MP Boost -- the trait rides health.modmp (DISPLAY); health.maxmp = 714.
-- ---------------------------------------------------------------------------
(function()
    local nmp = dofile('data/nativemp.lua');
    local g = nmp.get;

    -- the field pin: race D 10+3*59+4*15=247, WHM C 12+4*59+4*15=308,
    -- sub SCH D (10+3*36)/2=59 -> 614; +100 merit = maxmp 714 (the latent
    -- denominator; the on-screen 724 adds the DISPLAY-side SCH trait)
    check('NMP1 field pin Hume WHM75/SCH37 base', g(1, 3, 75, 20, 37), 614);
    check('NMP2 field pin + 10 merit levels = maxmp 714', g(1, 3, 75, 20, 37, 100), 714);
    check('NMP3 Hume female = same row', g(2, 3, 75, 20, 37), 614);

    check('NMP4 Taru BLM75/WHM37 (430+369+78)', g(5, 4, 75, 3, 37), 877);
    check('NMP5 no pool anywhere: Galka WAR75/NIN37', g(8, 1, 75, 13, 37), 0);
    -- main without MP, sub with: race rides the SUB level, halved
    check('NMP6 Hume NIN75/WHM37 (59+0+78)', g(1, 13, 75, 3, 37), 137);
    -- Galka G-grade half-point rate: 48.5+95+97 = 240.5 truncates like (int16)
    check('NMP7 truncation: Galka DRK75/BLM37', g(8, 8, 75, 4, 37), 240);

    check('NMP8 under 60, no sub: Elvaan RDM50 (106+157)', g(3, 5, 50), 263);
    check('NMP9 over-60 kink: Hume WHM61 (191+252)', g(1, 3, 61), 443);
    check('NMP10 level 1 Hume WHM (10+12)', g(1, 3, 1), 22);
    check('NMP11 slvl 0 = subless: Hume WHM75 (247+308)', g(1, 3, 75, 20, 0), 555);

    check('NMP12 nil race -> nil', g(nil, 3, 75), nil);
    check('NMP13 nil level -> nil', g(1, 3, nil), nil);

    AshitaCore = nil;
    check('NMP14 headless self -> nil', nmp.self(), nil);

    -- live-read seam: Taru female BLM75/WHM37 through the stubbed managers
    local player = {
        GetMainJob      = function(self) return 4; end,
        GetMainJobLevel = function(self) return 75; end,
        GetSubJob       = function(self) return 3; end,
        GetSubJobLevel  = function(self) return 37; end,
    };
    local em    = { GetRace = function(self, i) return (i == 1234) and 6 or nil; end };
    local party = { GetMemberTargetIndex = function(self, n) return 1234; end };
    AshitaCore = { GetMemoryManager = function(self)
        return {
            GetEntity = function(self) return em; end,
            GetParty  = function(self) return party; end,
            GetPlayer = function(self) return player; end,
        };
    end };
    check('NMP15 self() live reads -> Taru BLM75/WHM37', nmp.self(), 877);
    check('NMP16 self(meritMP) forwards', nmp.self(110), 987);

    AshitaCore = nil;
end)();

-- ---------------------------------------------------------------------------
-- section AO: Auto Oneiros Grip (dlac:AutoOneiros, engine v67)
-- Denominator (stable latent_effect_container.cpp + item_latents 18811 =
-- latent id 4 MP_UNDER_PERCENT): health.maxmp = CalculateStats' race/job/sub
-- formula + merit MP, NO gear (weapon/grip MP and Max MP Boost traits ride
-- health.MODMP -- the display -- never the denominator; BG-wiki's retail
-- visible-gear rule is a DIFFERENT latent id, commented out here). The
-- PERCENT is field truth, not repo truth: Henrik's tick test broke at
-- MP 357/358 on maxmp 714 = exactly 50.0%, equality ACTIVE -- live runs 50
-- where the repo sql says 75 (docs/server-questions.md #6). Threshold =
-- floor(base * 0.50), boundary inclusive. Usable merits cap at merit.cpp
-- cap[75] = 10 -> the resolver clamps. Mindie's shape (Hume WHM75/SCH37,
-- 10/10 merits): maxmp 714 -> fires at MP <= 357; meritless 614 -> 307.
-- ---------------------------------------------------------------------------
(function()
    local nmpM = package.loaded['dlac\\data\\nativemp'];   -- THE instance dispatch captured
    local rv = dispatchM._resolveVirtual;
    local ctx75 = { player = { MainJobSync = 75 } };

    -- live-reader stubs: Mindie's shape -- Hume(1) WHM75/SCH37
    local oldIdx, oldRace, oldJobs = nmpM.selfIndex, nmpM.readRace, nmpM.readJobs;
    nmpM.selfIndex = function() return 42; end
    nmpM.readRace  = function(idx) return (idx == 42) and 1 or nil; end
    nmpM.readJobs  = function() return 3, 75, 20, 37; end

    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 }, mpMerits = 10 };

    TEST_PLAYER = { MP = 357 };
    check('AO1 field pin: MP 357 of maxmp 714 -> grip', rv('dlac:AutoOneiros', ctx75, 'Sub'), 'Oneiros Grip');
    TEST_PLAYER = { MP = 358 };
    local nm, why = rv('dlac:AutoOneiros', ctx75, 'Sub');
    check('AO2 field pin: 358 -> fallback', nm, nil);
    check('AO2b reason carries the threshold', string.find(tostring(why), '357', 1, true) ~= nil, true);
    -- over-cap merit input (sql headroom, hand-edited manifest): clamped to
    -- the usable 10 -- the threshold must NOT move
    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 }, mpMerits = 15 };
    TEST_PLAYER = { MP = 357 };
    check('AO2c merit clamp: 15 acts as 10', rv('dlac:AutoOneiros', ctx75, 'Sub'), 'Oneiros Grip');
    TEST_PLAYER = { MP = 358 };
    check('AO2d merit clamp: threshold unmoved', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 }, mpMerits = 0 };
    TEST_PLAYER = { MP = 307 };
    check('AO3 meritless base 614 -> fires at 307', rv('dlac:AutoOneiros', ctx75, 'Sub'), 'Oneiros Grip');
    TEST_PLAYER = { MP = 308 };
    check('AO4 meritless 308 stays off', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    -- second FIELD-VERIFIED shape (Henrik 2026-07-18, post-shutdown login):
    -- WHM75/BLM37, wire-learned 10 merits -> 652 + 100 = 752 -> aim 376,
    -- reported by /dl merits and MP-checked live. Pins the sub-swap re-aim.
    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 }, mpMerits = 10 };
    nmpM.readJobs = function() return 3, 75, 4, 37; end   -- WHM75/BLM37
    TEST_PLAYER = { MP = 376 };
    check('AO13 field pin 2: /BLM37 base 752 -> grip at 376', rv('dlac:AutoOneiros', ctx75, 'Sub'), 'Oneiros Grip');
    TEST_PLAYER = { MP = 377 };
    check('AO14 field pin 2: 377 -> fallback', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);
    nmpM.readJobs = function() return 3, 75, 20, 37; end  -- back to /SCH for anything below

    TEST_PLAYER = { MP = 100 };
    check('AO5 under the grip level -> unresolved',
        (rv('dlac:AutoOneiros', { player = { MainJobSync = 70 } }, 'Sub')), nil);

    dispatchM._autoOverride = { oneiros = false };
    check('AO6 not owned -> unresolved', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 } };
    nmpM.readRace = function() return 8; end               -- Galka...
    nmpM.readJobs = function() return 1, 75, 13, 37; end   -- ...WAR/NIN: no pool anywhere
    check('AO7 no native pool on this job -> unresolved', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    nmpM.selfIndex = function() return nil; end            -- self unreadable (login settle)
    check('AO8 native unreadable -> unresolved', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    -- the marker is a Lv75 ladder rung (the grip's level), composite form too
    check('AO9 virtualMinLevel = grip level', dispatchM.virtualMinLevel('dlac:AutoOneiros'), 75);
    check('AO10 composite form tolerated', dispatchM.virtualMinLevel('dlac:AutoOneiros|GenbusShield'), 75);
    -- the grip is one FIXED Lv75 item: a manifest that has not learned it yet
    -- still answers 75 -- never a Lv0 always-adopt wildcard (v68)
    dispatchM._autoOverride = {};
    check('AO10b unlearned manifest: still a Lv75 rung', dispatchM.virtualMinLevel('dlac:AutoOneiros'), 75);
    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 } };

    nmpM.selfIndex, nmpM.readRace, nmpM.readJobs = oldIdx, oldRace, oldJobs;

    -- flatten pairing: the marker IS a grip -- a 2H main composes it with the
    -- slot's regular grip as fallback (a shield would itself be illegal under
    -- a 2H, so it can't serve); a 1H main vetoes the marker outright and the
    -- shield wins the slot (shared subSlotAllowed rule both ways)
    TEST_PLAYER = { MainJob = 'WHM', SubJob = 'SCH', MainJobSync = 75, SubJobSync = 37 };
    AshitaCore = ashitaWithDW(false);
    local s2H = utils.BuildDynamicSets({ Dynamic = { TP = {
        Main = { gsword2H }, Sub = { 'dlac:AutoOneiros', grip } } } });
    check('AO11 2H main: marker + grip fallback', s2H.TP and s2H.TP.Sub, 'dlac:AutoOneiros|PoleGrip');
    local s1H = utils.BuildDynamicSets({ Dynamic = { TP = {
        Main = { dagger1H }, Sub = { 'dlac:AutoOneiros', shield } } } });
    check('AO12 1H main: marker vetoed, shield wins', s1H.TP and s1H.TP.Sub, 'GenbusShield');
    AshitaCore = nil;

    dispatchM._autoOverride = nil;
    TEST_PLAYER = nil;
end)();

-- ---------------------------------------------------------------------------
-- section MW: merit auto-learn (feature/meritwatch.lua, s2c 0x08C)
-- Layout from the server's own packets/s2c/0x08c_merit.h: u16 merit_count,
-- u16 pad, then {u16 id, u8 next, u8 count} entries -- full menu chunks AND
-- the single-entry spend update parse identically. max_mp = merits.sql 66.
-- ---------------------------------------------------------------------------
(function()
    local mw = dofile('feature/meritwatch.lua');
    local function pkt(count, entries)
        local t = { string.char(0x8C, 0x00, 0x00, 0x00, count % 256, math.floor(count / 256), 0, 0) };
        for _, e in ipairs(entries) do
            t[#t + 1] = string.char(e[1] % 256, math.floor(e[1] / 256) % 256, e[2], e[3]);
        end
        return table.concat(t);
    end
    check('MW1 full form: max_mp found', mw.parse08C(pkt(3, { { 64, 5, 8 }, { 66, 7, 10 }, { 128, 3, 5 } })), 10);
    check('MW2 single-update form', mw.parse08C(pkt(1, { { 66, 9, 7 } })), 7);
    check('MW3 chunk without max_mp -> nil', mw.parse08C(pkt(2, { { 64, 5, 8 }, { 68, 1, 3 } })), nil);
    check('MW4 truncated claim reads safely', mw.parse08C(pkt(5, { { 64, 5, 8 } })), nil);
    check('MW5 garbage -> nil', mw.parse08C('xx'), nil);
    -- XiPackets usage 3: the LAST point removed -> index arrives as id|1
    -- (67) and the merit is back to zero, whatever the count byte claims
    check('MW5b full removal: odd index 67 -> 0', mw.parse08C(pkt(1, { { 67, 0, 9 } })), 0);
    check('MW5c other merits removal flag ignored', mw.parse08C(pkt(1, { { 129, 0, 4 } })), nil);

    -- the write path: same instance meritwatch will require at packet time
    local aui = dofile('ui/automationsui.lua');
    package.loaded['dlac\\ui\\automationsui'] = aui;
    check('MW10 getter nil before any write', aui.getMpMerits(), nil);
    check('MW6 setMpMerits clamps 15 -> 10 + reports change', aui.setMpMerits(15), true);
    check('MW7 clamped value current: 10 = no change', aui.setMpMerits(10), false);
    check('MW11 getter reads the clamped value', aui.getMpMerits(), 10);
    mw.onMeritPacket(pkt(1, { { 66, 0, 4 } }));
    check('MW8 packet write landed (4 = no change now)', aui.setMpMerits(4), false);
    check('MW9 session mirror holds the wire count', mw.learned, 4);
    check('MW12 getter tracks the packet write', aui.getMpMerits(), 4);
    package.loaded['dlac\\ui\\automationsui'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- section MS: Sets-tab mode sections (gear/gearfmt.lua modeSections)
-- Henrik 2026-07-18: mode ladders (many Caster rungs + many Club rungs in one
-- Main list) drown the flat display. A mode gating 2+ rows earns a collapsed
-- section; a row whose EVERY gate is sectioned leaves the root; a row ungated
-- or alone on ANY gate stays in the root (and still shows under its sectioned
-- gates); an OR list means membership in every sectioned gate.
-- ---------------------------------------------------------------------------
(function()
    local gf = dofile('gear/gearfmt.lua');
    check('MS0 modeSections exported', type(gf.modeSections), 'function');
    local A = { rec = { Name = 'Yew Wand',      Level = 18 }, mode = 'Weapon:Caster' };
    local B = { rec = { Name = 'Chestnut Wand', Level = 30 }, mode = { 'Weapon:Caster', 'Weapon:Club' } };
    local C = { rec = { Name = 'Warp Cudgel',   Level = 51 }, mode = { 'weapon:club', 'DT' } };  -- spelling drift + a solo gate
    local D = { rec = { Name = 'Pilgrim Wand',  Level = 7  } };                                  -- ungated
    local E = { rec = { Name = 'Kraken Club',   Level = 63 }, mode = 'Solo:Only' };              -- solo gate only
    local root, secs = gf.modeSections({ A, B, C, D, E });
    local function has(list, x) for _, v in ipairs(list) do if v == x then return true; end end return false; end
    check('MS1 two sections form (caster, club)', #secs, 2);
    check('MS2 alpha order + first-seen spelling names', secs[1].name .. '/' .. secs[2].name, 'Weapon:Caster/Weapon:Club');
    check('MS3 caster section holds its two rows', has(secs[1].items, A) and has(secs[1].items, B), true);
    check('MS4 club groups case-insensitively (B + drifted C)', has(secs[2].items, B) and has(secs[2].items, C), true);
    check('MS5 ungated row stays in the root', has(root, D), true);
    check('MS6 solo-gated row stays in the root', has(root, E), true);
    check('MS7 fully-sectioned rows leave the root', has(root, A) or has(root, B), false);
    check('MS8 sectioned + solo gate -> root AND section', has(root, C) and has(secs[2].items, C), true);
    check('MS9 root keeps display order', root[1] == C and root[2] == D and root[3] == E, true);
    check('MS10 header ladder ascends', table.concat(secs[1].levels, ','), '18,30');
    check('MS11 ladder sorts across spelling drift', table.concat(secs[2].levels, ','), '30,51');
    -- a duplicated gate inside ONE row's OR list must not fake a 2-row section
    local F = { rec = { Name = 'X', Level = 5 }, mode = { 'Zerg', 'zerg' } };
    local r2, s2 = gf.modeSections({ F });
    check('MS12 dup gate in one row makes no section', #s2, 0);
    check('MS13 ...and that row stays in the root', r2[1], F);
    -- two rows at the SAME item level: one ladder entry, not two
    local G1 = { rec = { Name = 'G1', Level = 40 }, mode = 'M' };
    local G2 = { rec = { Name = 'G2', Level = 40 }, mode = 'M' };
    local r3, s3 = gf.modeSections({ G1, G2 });
    check('MS14 same-level rows dedup in the ladder', table.concat(s3[1].levels, ','), '40');
    check('MS15 ...and the root is empty (both rows sectioned)', #r3, 0);
    -- degenerate inputs stay safe
    local r4, s4 = gf.modeSections(nil);
    check('MS16 nil input -> empty root + no sections', #r4 + #s4, 0);

    -- stripGate: the section x removes ONE gate, never the row (Henrik
    -- 2026-07-18: Harpoon gated Base + Polearm lost the whole row to one x).
    check('MS17 stripGate exported', type(gf.stripGate), 'function');
    check('MS18 pair loses one -> the survivor as a plain string',
        gf.stripGate({ 'Weapon:Base', 'Weapon:Polearm' }, 'weapon:polearm'), 'Weapon:Base');
    check('MS19 sole gate strips to nil (row turns unconditional)',
        gf.stripGate('Weapon:Polearm', 'weapon:polearm'), nil);
    check('MS20 case-insensitive match', gf.stripGate('WEAPON:Polearm', 'weapon:polearm'), nil);
    local left = gf.stripGate({ 'A', 'B', 'C' }, 'b');
    check('MS21 three gates keep the other two, still a list',
        type(left) == 'table' and left[1] .. '/' .. left[2], 'A/C');
    check('MS22 unrelated key is a no-op', gf.stripGate('DT', 'weapon:polearm'), 'DT');
end)();

-- ---------------------------------------------------------------------------
-- section MC: dead mode-condition sweep (triggersui._modeCondRefs)
-- Henrik 2026-07-18: editing a cycle left nonexistent 'Name:Value' gates on
-- weapons/rules. The sweep takes a whole mode ('X' -> 'X' + every 'X:*') or
-- ONE value ('X:V', exact); v54 legs are honoured -- a rule fires on (ALL of
-- when) OR (ANY whenAny entry), so: a mode list loses just the dead name; a
-- leg whose mode list empties dies (an & leg collapses to OR-only, a | entry
-- is removed); a rule with no live leg is removed whole.
-- ---------------------------------------------------------------------------
(function()
    local tui = dofile('ui/triggersui.lua');
    check('MC0 sweep seam exported', type(tui._modeCondRefs), 'function');
    local f = tui._modeCondRefs;

    -- whole-mode target: bare gate, valued gate, list gate
    local d = { Default = {
        { when = { mode = 'Inc' },              set = 'A' },
        { when = { mode = 'Inc:Wpn' },          set = 'B' },
        { when = { mode = { 'Inc', 'DT' } },    set = 'C' },
        { when = { mode = 'DT' },               set = 'D' },
    } };
    local r = f(d, 'Inc', true);
    check('MC1 whole-mode: bare + valued gates removed, list trimmed', r.removedRules .. '/' .. r.editedRules, '2/1');
    check('MC2 survivors: trimmed rule + unrelated rule', #d.Default, 2);
    check('MC3 list gate collapses to the surviving mode (plain string)', d.Default[1].when.mode, 'DT');
    check('MC4 unrelated DT rule untouched', d.Default[2].set, 'D');

    -- value-level target: exact only -- sibling values and the BARE name survive
    d = { Default = {
        { when = { mode = 'Weapon:Club' },                     set = 'A' },
        { when = { mode = 'weapon:club' },                     set = 'B' },   -- case drift
        { when = { mode = 'Weapon:Caster' },                   set = 'C' },
        { when = { mode = 'Weapon' },                          set = 'D' },
        { when = { mode = { 'Weapon:Club', 'Weapon:Caster' }}, set = 'E' },
    } };
    r = f(d, 'Weapon:Club', true);
    check('MC5 value target: both spellings removed, list trimmed', r.removedRules .. '/' .. r.editedRules, '2/1');
    check('MC6 sibling value survives', d.Default[1].set, 'C');
    check('MC7 bare cycle gate survives a value removal', d.Default[2].set, 'D');
    check('MC8 trimmed list keeps the sibling', d.Default[3].when.mode, 'Weapon:Caster');

    -- load-bearing: the mode was one of several & conditions -> rule removed whole
    d = { Default = { { when = { mode = 'X', spell = 'Cure' }, set = 'A' } } };
    r = f(d, 'X', true);
    check('MC9 load-bearing & rule removed despite other conditions', #d.Default .. '/' .. r.removedRules, '0/1');

    -- v54 legs
    d = { Default = {
        { when = { spell = 'Cure' }, whenAny = { { mode = 'X' }, { buff = 'Sleep' } }, set = 'A' },
        { when = {},                 whenAny = { { mode = 'X' } },                     set = 'B' },
        { when = { mode = 'X' },     whenAny = { { buff = 'Sleep' } },                 set = 'C' },
        { when = { mode = 'X' },     whenAny = { { mode = 'X:1' } },                   set = 'D' },
        { when = { spell = 'Fire' }, whenAny = { { mode = 'X' } },                     set = 'E' },
        { when = {},                 whenAny = { { mode = { 'X', 'DT' } } },           set = 'F' },
    } };
    r = f(d, 'X', true);
    check('MC10 counts: OR-only + both-legs-dead removed, rest edited', r.removedRules .. '/' .. r.editedRules, '2/4');
    check('MC11 dead | entry removed, sibling entry stays', #d.Default[1].whenAny .. '/' .. tostring(d.Default[1].whenAny[1].buff), '1/Sleep');
    check('MC12 dead & leg collapses to OR-only (when emptied, | kept)',
        next(d.Default[2].when) == nil and d.Default[2].whenAny[1].buff, 'Sleep');
    check('MC13 emptied whenAny drops to nil, & leg carries on',
        d.Default[3].set == 'E' and d.Default[3].whenAny, nil);
    check('MC14 | entry mode list keeps its other mode', d.Default[4].whenAny[1].mode, 'DT');
    check('MC15 the removed rules are the right ones', (function()
        for _, rule in ipairs(d.Default) do
            if rule.set == 'B' or rule.set == 'D' then return rule.set; end
        end
        return true;
    end)(), true);

    -- report mode: counts without mutating
    d = { Default = {
        { when = { mode = 'X' }, set = 'A' },
        { when = { spell = 'Cure' }, whenAny = { { mode = 'X' } }, set = 'B' },
    } };
    r = f(d, 'X', false);
    check('MC16 report lists every referencing rule', #r.rules, 2);
    check('MC17 report mutates nothing', #d.Default == 2 and d.Default[1].when.mode .. '/' .. tostring(d.Default[2].whenAny[1].mode), 'X/X');
    check('MC18 near-name mode never matches (Incog vs Inc)',
        #f({ Default = { { when = { mode = 'Incog' }, set = 'A' } } }, 'Inc', false).rules, 0);

    -- RS: set-rename reference rewrite (2026-07-20, the Sets tab Rename).
    -- EXACT match only; string and multi-set list actions; every handler
    -- section including Default's mode overlays; equip rules untouched.
    check('RS0 rename seam exported', type(tui._renameSetRefsIn), 'function');
    local rd = {
        Default = {
            { when = { mode = 'DT' }, set = 'Idle' },
            { when = { mode = 'X' },  set = { 'Idle', 'Tp' } },
        },
        Midcast = {
            { when = { name = 'Cure' }, set = 'Idle' },
            { when = { name = 'Dia' },  set = 'idle' },   -- case drift = already broken; stays visibly broken
            { when = { group = 'G' },   equip = { Head = 'Hat' } },
        },
    };
    local rsn = tui._renameSetRefsIn(rd, 'Idle', 'Field');
    check('RS1 three rules rewritten', rsn, 3);
    check('RS2 string action follows', rd.Default[1].set, 'Field');
    check('RS3 list entry follows, sibling kept', rd.Default[2].set[1] .. '/' .. rd.Default[2].set[2], 'Field/Tp');
    check('RS4 other sections follow too', rd.Midcast[1].set, 'Field');
    check('RS5 case-drifted ref untouched', rd.Midcast[2].set, 'idle');
    check('RS6 equip rule untouched', rd.Midcast[3].equip.Head, 'Hat');
    check('RS7 no match = zero, nothing mutated', tui._renameSetRefsIn(rd, 'Nope', 'X'), 0);
end)();

-- ---------------------------------------------------------------------------
-- LOC. location service (v45) -- the central town/zone answer (feature/
--      location.lua) behind the lockstyle Disable-in-town option (and a future
--      home for the inTown read). Town membership is data/zones.lua's .town
--      flag; the live read is injectable (M.reader) and nils out on failure.
-- ---------------------------------------------------------------------------
(function()
    local loc = dofile('feature/location.lua');
    check('LOC0 module loads', type(loc), 'table');
    -- isTown: the curated town set (server CITY + Nashmau - combat zones).
    check('LOC1 isTown city (S. San dOria 230)',      loc.isTown(230), true);
    check('LOC2 isTown Nashmau 53 (curated ADD)',     loc.isTown(53), true);
    check('LOC3 isTown Celennia 284 (Wings hub)',     loc.isTown(284), true);
    check('LOC4 isTown Sealions Den 32 (curated DROP)', loc.isTown(32), false);
    check('LOC5 isTown field zone (Phanauet 1)',      loc.isTown(1), false);
    check('LOC6 isTown nil-safe',                     loc.isTown(nil), false);
    -- inTown() folds the live read through isTown; reader is the injected seam.
    loc.reader = function() return 230; end;
    check('LOC7 inTown true in a city', loc.inTown(), true);
    check('LOC8 zoneId reads the seam', loc.zoneId(), 230);
    loc.reader = function() return 1; end;
    check('LOC9 inTown false in the field', loc.inTown(), false);
    loc.reader = function() return nil; end;
    check('LOC10 inTown nil on unknown zone', loc.inTown(), nil);
    check('LOC11 zoneId nil on unknown', loc.zoneId(), nil);
end)();

-- ---------------------------------------------------------------------------
-- LG. lockstyle zone-in guard (v43) -- the pure decision half of the packet
--     watcher in feature\lockstyle.lua. Field-pinned 2026-07-19 (/probe ls):
--     the retail client re-asserts ITS private lockstyle flag to the server
--     after every zone-in -- CONTINUE when it thinks the lock is on, DISABLE
--     when it thinks it is off -- and dlac's injected SET never turns that
--     flag on, so the client killed our lockstyle ~0.6s after each zone-in.
--     The guard blocks exactly that DISABLE: in-window, lockstyle live, not
--     player-typed. Everything else must pass or retire the live flag.
-- ---------------------------------------------------------------------------
(function()
    local ls = dofile('feature/lockstyle.lua');
    check('LG0 _lsGuard exported', type(ls._lsGuard), 'function');
    if type(ls._lsGuard) ~= 'function' then return; end
    local f = ls._lsGuard;
    local FAR = -1e9;   -- "never happened" stamp
    -- mode, now, zoneInAt, active, userOffAt
    check('LG1 SET arms the guard',    f(3, 100, FAR, false, FAR), 'activate');
    check('LG2 native ENABLE adopts: guard arms, box memory must clear (worn gear stomped the box)',
        f(4, 100, FAR, false, FAR), 'adopt');
    check('LG3 THE BUG: in-window DISABLE while live -> blocked',
        f(0, 100.6, 100, true, FAR), 'block');
    check('LG4 late unasked DISABLE -> guard yields, keep memory survives',
        f(0, 111, 100, true, FAR), 'deactivate');
    check('LG5 window edge: 10s is already late', f(0, 110, 100, true, FAR), 'deactivate');
    check('LG6 in-window but nothing live -> pass through',
        f(0, 100.6, 100, false, FAR), 'deactivate');
    check('LG7 player typed /lockstyle off -> RETIRE, never blocked, box memory clears',
        f(0, 100.6, 100, true, 100.5), 'retire');
    check('LG7b typed off outside any window is still retire', f(0, 500, 100, false, 499), 'retire');
    check('LG8 stale intent stamp does not shield the auto-disable',
        f(0, 100.6, 100, true, 90), 'block');
    check('LG9 CONTINUE passes untouched', f(1, 100.6, 100, true, FAR), 'pass');
    check('LG10 QUERY passes untouched',   f(2, 100.6, 100, true, FAR), 'pass');
    check('LG11 garbage mode passes',      f(-1, 100.6, 100, true, FAR), 'pass');
    check('LG12 nil stamps never block an inactive guard', f(0, 5, nil, false, nil), 'deactivate');
    -- v45 disable-in-town: with suppressTown, dlac WANTS the lock off in a town,
    -- so ANY disable -> 'suppress' (let through, keep the box, book no keep-heal),
    -- EXCEPT a player-typed off, which still 'retire's (explicit intent wins).
    check('LG12a town-suppress: in-window disable is NOT blocked -> suppress',
        f(0, 100.6, 100, true, FAR, true), 'suppress');
    check('LG12b town-suppress: out-of-window disable -> suppress, not deactivate (no keep-heal)',
        f(0, 500, 100, false, FAR, true), 'suppress');
    check('LG12c town-suppress still yields to a typed /lockstyle off -> retire',
        f(0, 100.6, 100, true, 100.5, true), 'retire');
    check('LG12d suppressTown does not disturb SET', f(3, 100, FAR, false, FAR, true), 'activate');
    check('LG12e _wantTownOff = townOff AND inTown',   ls._wantTownOff(true, true), true);
    check('LG12f _wantTownOff false when not in town',  ls._wantTownOff(true, false), false);
    check('LG12g _wantTownOff false when option off',   ls._wantTownOff(false, true), false);
    check('LG12h _wantTownOff false on unknown (nil)',  ls._wantTownOff(true, nil), false);
    -- v46 town lockstyle pick: 'off' (disable-in-town) | a box number | nil.
    check('LG12i townPick nil when not in town',    ls._townPick(false, true, 5), nil);
    check('LG12j townPick off-mode is off',         ls._townPick(true, true, nil), 'off');
    check('LG12k townPick replace-mode = the box',  ls._townPick(true, nil, 5), 5);
    check('LG12l townPick None (no options) = nil', ls._townPick(true, nil, nil), nil);
    check('LG12m townPick off beats box (safety)',  ls._townPick(true, true, 5), 'off');
    check('LG12n townPick unknown zone (nil) = nil', ls._townPick(nil, nil, 5), nil);
    check('LG13 user-off stamp is exported for the command handler',
        type(ls._guardUserOff), 'function');

    -- v44 keep-on-subjob: the option's storage seams. The game clears style
    -- lock server-side on ANY job change (0x100 handler), so this one is a
    -- re-apply, not a block -- the pump half is live-only; the pure seams are
    -- the serializer, the loader default and the job-entry filter.
    local txt = ls._serialize({ active = 2, keepSub = true, onload = {}, slots = {} });
    check('LG14 serializer writes keepSub', txt:find('keepSub = true', 1, true) ~= nil, true);
    local back = (loadstring or load)(txt)();
    check('LG15 round-trip keeps it', back.keepSub, true);
    check('LG16 absent option is not written',
        ls._serialize({ active = 1, onload = {}, slots = {} }):find('keepSub = true', 1, true), nil);
    local ed = ls._entryData({ active = 1, slots = {}, onload = { DRK = 2 }, keepSub = true }, 'DRK');
    check('LG17 _entryData carries the option whole', ed.keepSub, true);
    check('LG18 _entryData without it stays absent',
        ls._entryData({ active = 1, slots = {}, onload = {} }, 'DRK').keepSub, nil);
    -- v46 townBox rides the same storage seams as keepSub/townOff.
    check('LG18a serializer writes townBox',
        ls._serialize({ active = 1, townBox = 7, onload = {}, slots = {} }):find('townBox = 7', 1, true) ~= nil, true);
    check('LG18b round-trip keeps townBox',
        ((loadstring or load)(ls._serialize({ active = 1, townBox = 7, onload = {}, slots = {} }))()).townBox, 7);
    check('LG18c _entryData carries townBox',
        ls._entryData({ active = 1, townBox = 7, slots = {}, onload = {} }).townBox, 7);
    check('LG18d absent townBox writes no field (header note aside)',
        ls._serialize({ active = 1, onload = {}, slots = {} }):find('townBox = %d'), nil);
    check('LG19 guard-arm (the subjob-flip window) exported for the pump',
        type(ls._guardArm), 'function');

    -- round 3: the 0x100 job-change packet is the keep trigger of record --
    -- it leaves BEFORE the client's DISABLE (field capture 07-19 11:27), so
    -- arming off it wins the race the memory poll lost. 0 = unchanged field.
    local k = ls._jobPktKind;
    check('LG20 _jobPktKind exported', type(k), 'function');
    if type(k) == 'function' then
        check('LG21 sub-only change (incl. re-selecting the same sub)', k(0, 5), 'sub');
        check('LG22 main change is not ours to keep', k(7, 0), 'main');
        check('LG23 main+sub together is still a main change', k(7, 5), 'main');
        check('LG24 nothing changed', k(0, 0), 'none');
        check('LG25 nil-safe', k(nil, nil), 'none');
    end

    -- round 6: the queue sites write the keep memory directly -- a command
    -- queued from the addon's own state never re-enters that state's command
    -- event (field: 'keep4: box -' after button applies), so the event
    -- observation covers only hand-typed applies.
    check('LG32 _noteApplied exported', type(ls._noteApplied), 'function');
    if type(ls._noteApplied) == 'function' then
        ls._noteApplied(9);
        check('LG33 the queue site writes what the readout reads', ls._lastBox(), 9);
        ls._noteApplied('nonsense');
        check('LG34 a non-number never corrupts the memory', ls._lastBox(), 9);
    end

    -- round 4: the unasked DISABLE itself books the heal (field 11:34 -- it
    -- precedes the 0x100 on the wire, so round 3's arm-first plan was
    -- backwards; the kill is the one event every capture shows).
    local h = ls._keepHeal;
    check('LG26 _keepHeal exported', type(h), 'function');
    if type(h) == 'function' then
        check('LG27 unasked disable + keep on + box remembered -> heal', h('deactivate', true, 7), true);
        check('LG28 player-meant retire never heals',   h('retire', true, 7), false);
        check('LG29 keep off -> no heal',               h('deactivate', false, 7), false);
        check('LG30 no box remembered -> no heal',      h('deactivate', true, nil), false);
        check('LG31 blocked disable needs no heal',     h('block', true, 7), false);
    end
end)();

-- ---------------------------------------------------------------------------
-- LGF. keep-on-subjob FULL FLOW -- the whole addon-state chain driven
--      headlessly through the REAL registered handlers, in the exact wire
--      order of the 11:34 field capture (client DISABLE first, 0x100 second,
--      player struct flips after). Born in field round 4: every pure seam
--      was green while the assembled chain sat unproven -- this is the
--      assembled chain. Fixture: tests\fixtures\keepflow (legacy-tier file,
--      box 3, keepSub on).
-- ---------------------------------------------------------------------------
(function()
    local savedReg, savedClock, savedCore = ashita.events.register, os.clock, AshitaCore;
    local savedProf = package.loaded['dlac\\profiles'];
    package.loaded['dlac\\profiles'] = nil;   -- force the legacy-tier read (restored below)

    local handlers, queued = {}, {};
    ashita.events.register = function(ev, nm, fn) handlers[ev .. '/' .. nm] = fn; end
    local t = { v = 100 };
    os.clock = function() return t.v; end
    local subId = 1;   -- WAR -> RDM at the "moogle"
    local ABBR = { [1] = 'WAR', [5] = 'RDM', [8] = 'DRK' };
    AshitaCore = {
        GetInstallPath = function() return 'tests\\fixtures\\keepflow\\'; end,
        GetMemoryManager = function()
            return {
                GetParty = function() return {
                    GetMemberName = function() return 'Testy'; end,
                    GetMemberServerId = function() return 1234; end,
                }; end,
                GetPlayer = function() return {
                    GetMainJob = function() return 8; end,
                    GetSubJob = function() return subId; end,
                }; end,
            };
        end,
        GetResourceManager = function()
            return { GetString = function(_, _, id) return ABBR[id]; end };
        end,
        GetChatManager = function()
            return { QueueCommand = function(_, _, c) queued[#queued + 1] = c; end };
        end,
    };

    local ls = dofile('feature/lockstyle.lua');
    local cmd, pout, pin = handlers['command/dlac-lockstyle'],
                           handlers['packet_out/dlac-lockstyle-pout'],
                           handlers['packet_in/dlac-lockstyle-pin'];
    check('LGF0 all three handlers registered', cmd ~= nil and pout ~= nil and pin ~= nil, true);
    if cmd == nil or pout == nil or pin == nil then
        ashita.events.register, os.clock, AshitaCore = savedReg, savedClock, savedCore;
        package.loaded['dlac\\profiles'] = savedProf;
        return;
    end
    local function pkt(id, bytes)
        local d = {};
        for i = 1, 136 do d[i] = string.char(0); end
        for off, v in pairs(bytes) do d[off] = string.char(v); end
        return { id = id, data = table.concat(d), blocked = false };
    end

    ls.pump(); t.v = 107; ls.pump();   -- login settle (6s grace resolves)

    -- apply box 3, engine SET follows
    cmd({ command = '/dl ls apply 3', blocked = false });
    pout(pkt(0x053, { [6] = 3 }));
    check('LGF1 apply remembered', ls._lastBox(), 3);
    check('LGF2 guard live after SET', ls._guardOn(), true);

    -- the moogle subjob switch, field wire order
    t.v = 200;
    local dis = pkt(0x053, { [6] = 0 });
    pout(dis);
    check('LGF3 pre-0x100 DISABLE passes (nothing armed yet)', dis.blocked, false);
    check('LGF4 ...but it books the heal', ls._healDue() ~= nil, true);
    pout(pkt(0x100, { [5] = 0, [6] = 5 }));   -- sub-only request
    check('LGF5 box memory survives the change', ls._lastBox(), 3);
    subId = 5;                                 -- player struct catches up
    t.v = 202; ls.pump();
    t.v = 210; ls.pump();
    check('LGF6 THE FEATURE: the heal re-applies the box', queued[#queued], '/dl ls apply 3');
    check('LGF7 heal timer consumed', ls._healDue(), nil);
    pout(pkt(0x053, { [6] = 3 }));             -- the healing SET goes out
    local straggler = pkt(0x053, { [6] = 0 });
    pout(straggler);
    check('LGF8 straggler DISABLE after the heal is swallowed (window armed)', straggler.blocked, true);

    -- main-job change cancels the keep
    t.v = 300;
    local dis2 = pkt(0x053, { [6] = 0 });
    pout(dis2);                                -- client reflex first, books a heal
    pout(pkt(0x100, { [5] = 5, [6] = 0 }));    -- ...then the MAIN change lands
    check('LGF9 main change forgets the box', ls._lastBox(), nil);
    check('LGF10 ...and cancels the booked heal', ls._healDue(), nil);

    -- typed /lockstyle off ends it for real
    t.v = 400;
    cmd({ command = '/dl ls apply 3', blocked = false });
    pout(pkt(0x053, { [6] = 3 }));
    cmd({ command = '/lockstyle off', blocked = false });
    local dis3 = pkt(0x053, { [6] = 0 });
    pout(dis3);
    check('LGF11 typed off is never blocked', dis3.blocked, false);
    check('LGF12 typed off forgets the box', ls._lastBox(), nil);
    check('LGF13 typed off books no heal', ls._healDue(), nil);

    ashita.events.register, os.clock, AshitaCore = savedReg, savedClock, savedCore;
    package.loaded['dlac\\profiles'] = savedProf;
end)();

-- ---------------------------------------------------------------------------
-- WI/SN. weights import (weightimport.parse/classify -> gearoptim.
-- importNamedWeights) and non-identifier set names through setmanager --
-- the Midcast_STR-VIT field bug: a dashed name must serialize bracket-quoted,
-- re-splice via the bracket form, and delete cleanly; identifiers stay bare.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\gear\\groupimport'] = package.loaded['dlac\\gear\\groupimport'] or dofile('gear/groupimport.lua');
    local wimpT = dofile('gear/weightimport.lua');

    local wprof, werr = wimpT.parse([[
        STR_DEX = T{ Accuracy = 12, Attack = { 10 }, STR = { perUnit = 10, cap = 60 }, BlueMagicSkill = { 3, 330 } },
        Debuff = { MACC = 12 },
        Bad1 = { 'Accuracy' },
        Bad2 = { Accuracy = 'twelve' },
        Empty = {},
        NotTable = 5,
    ]]);
    check('WI1 parse returns profiles', type(wprof) == 'table', true);
    check('WI2 bare number form', wprof.STR_DEX ~= nil and wprof.STR_DEX.Accuracy.perUnit, 12);
    check('WI3 array form, no cap', wprof.STR_DEX.Attack.perUnit == 10 and wprof.STR_DEX.Attack.cap == nil, true);
    check('WI4 explicit-field form keeps cap', wprof.STR_DEX.STR.cap, 60);
    check('WI5 array form keeps cap', wprof.STR_DEX.BlueMagicSkill.cap, 330);
    check('WI6 second profile lands', wprof.Debuff ~= nil and wprof.Debuff.MACC.perUnit, 12);
    check('WI7 list-entry profile skipped', wprof.Bad1, nil);
    check('WI8 bad stat value skips profile', wprof.Bad2, nil);
    check('WI9 empty profile skipped', wprof.Empty, nil);
    check('WI10 non-table value skipped', wprof.NotTable, nil);
    check('WI11 one skip reason per bad key', #werr, 4);
    local nilp = wimpT.parse('not lua at all }{');
    check('WI12 total parse failure returns nil', nilp, nil);

    local cre, ovr = wimpT.classify(wprof, { 'Debuff', 'SomethingElse' });
    check('WI13 classify created', table.concat(cre, ','), 'STR_DEX');
    check('WI14 classify overwritten (exact match)', table.concat(ovr, ','), 'Debuff');

    -- the applier: lands in the NAMED store, no set binding required
    local sum1 = optim.importNamedWeights({ STR_DEX = wprof.STR_DEX, Debuff = wprof.Debuff });
    check('WI15 import created 2', sum1.created, 2);
    check('WI16 named store readable', optim.peekWeights('named', 'Debuff').MACC.perUnit, 12);
    check('WI17 stat rows counted', sum1.stats, 5);
    local sum2 = optim.importNamedWeights({ Debuff = { INT = { perUnit = 10 } } });
    check('WI18 same name = update', sum2.updated, 1);
    check('WI19 update replaces, not merges', optim.peekWeights('named', 'Debuff').INT.perUnit == 10
        and optim.peekWeights('named', 'Debuff').MACC == nil, true);
    local inNamed = false;
    for _, n in ipairs(optim.namedKeys()) do if n == 'STR_DEX' then inNamed = true; end end
    check('WI20 imports list under Saved Sets', inNamed, true);

    -- non-identifier set names (setmanager)
    local sm = dofile('gear/setmanager.lua');
    check('SN1 identifier renders bare', sm.renderKey('Midcast_STRDEX'), 'Midcast_STRDEX');
    check('SN2 dash renders bracket-quoted', sm.renderKey('Midcast_STR-VIT'), '["Midcast_STR-VIT"]');
    check('SN3 keyword renders bracket-quoted', sm.renderKey('end'), '["end"]');
    check('SN4 leading digit renders bracket-quoted', sm.renderKey('2HSet'), '["2HSet"]');

    local base = 'local sets = {\n    Dynamic = {\n    },\n};\nreturn sets;\n';
    local STUB; STUB = setmetatable({}, { __index = function() return STUB; end });
    local t1, a1 = sm.spliceSet(base, 'Midcast_STR-VIT', {
        { name = 'Head', items = { { path = 'gear.Head.X' } } },
    });
    check('SN5 dashed name inserts', a1, 'inserted');
    check('SN6 dashed insert PARSES (the field bug)', (loadstring or load)(t1 or '') ~= nil, true);
    local t2, a2 = sm.spliceSet(t1, 'Midcast_STR-VIT', {
        { name = 'Body', items = { { path = 'gear.Body.Y' } } },
    });
    check('SN7 dashed re-splice replaces via the bracket form', a2, 'replaced');
    local _, ncopies = tostring(t2):gsub('Midcast_STR%-VIT', '');
    check('SN8 exactly one copy after replace', ncopies, 1);
    local c2 = loadWithEnv(t2, setmetatable({ gear = STUB }, { __index = _G }));
    local sok, sres = pcall(c2);
    check('SN9 dashed set reachable at runtime', sok and type(sres) == 'table'
        and type(sres.Dynamic['Midcast_STR-VIT']) == 'table', true);
    check('SN10 replace swapped the content', sok and sres.Dynamic['Midcast_STR-VIT'].Body ~= nil
        and sres.Dynamic['Midcast_STR-VIT'].Head == nil, true);
    local t3, a3 = sm.deleteSetText(t2, 'Midcast_STR-VIT');
    check('SN11 dashed delete', a3, 'deleted');
    check('SN12 delete removed it', tostring(t3):find('Midcast', 1, true), nil);
    local t4 = sm.spliceSet(base, 'Tp_Default', {
        { name = 'Head', items = { { path = 'gear.Head.X' } } },
    });
    check('SN13 identifier still renders bare', tostring(t4):find('        Tp_Default = {', 1, true) ~= nil, true);

    -- renameSetText (2026-07-20, the Sets tab Rename): re-key only, content
    -- untouched; a dashed new name bracket-quotes itself; unknown names and
    -- collisions refuse with the file untouched.
    local rt = sm.spliceSet(base, 'Idle', { { name = 'Head', items = { { path = 'gear.Head.X' } } } });
    rt = sm.spliceSet(rt, 'Tp', { { name = 'Body', items = { { path = 'gear.Body.Y' } } } });
    local rn, ra = sm.renameSetText(rt, 'Idle', 'Field');
    check('SN14 rename re-keys', ra, 'renamed');
    check('SN15 renamed text parses', (loadstring or load)(rn or '') ~= nil, true);
    check('SN16 old key gone, content kept', rn:find('Idle', 1, true) == nil
        and rn:find('gear.Head.X', 1, true) ~= nil, true);
    local rn2 = sm.renameSetText(rn, 'Field', 'STR-VIT');
    check('SN17 dashed new name bracket-quotes', tostring(rn2):find('["STR-VIT"] = {', 1, true) ~= nil, true);
    local _, rerr1 = sm.renameSetText(rn, 'Nope', 'X');
    check('SN18 unknown set refuses', tostring(rerr1):find('set not found', 1, true) ~= nil, true);
    local _, rerr2 = sm.renameSetText(rn, 'Field', 'Tp');
    check('SN19 collision refuses', tostring(rerr2):find('already exists', 1, true) ~= nil, true);

    -- priority-list twin: ordered parse, entry forms, order preserved
    local plists, perr = wimpT.parsePrio([[
        Debuff = { 'MACC', 'BlueMagicSkill', { 'INT', 60 } },
        Phys = T{ { stat = 'Accuracy' }, 'Attack' },
        BadEntry = { 'MACC', 5 },
        Mapish = { MACC = 1 },
        EmptyL = {},
    ]]);
    check('WP1 parsePrio returns lists', type(plists) == 'table', true);
    check('WP2 order preserved', plists.Debuff[1].stat == 'MACC' and plists.Debuff[2].stat == 'BlueMagicSkill'
        and plists.Debuff[3].stat == 'INT', true);
    check('WP3 pair-form cap lands', plists.Debuff[3].cap, 60);
    check('WP4 stat= form + bare string both work', plists.Phys[1].stat == 'Accuracy' and plists.Phys[2].stat == 'Attack', true);
    check('WP5 non-stat entry skips the list', plists.BadEntry, nil);
    check('WP6 named fields skip the list', plists.Mapish, nil);
    check('WP7 empty list skipped', plists.EmptyL, nil);
    check('WP8 one reason per bad key', #perr, 3);

    local psum = optim.importNamedPrio({ DebuffL = plists.Debuff });
    check('WP9 prio import created', psum.created, 1);
    check('WP10 rows counted', psum.stats, 3);
    local pn = false;
    for _, n in ipairs(optim.prioNamedKeys()) do if n == 'DebuffL' then pn = true; end end
    check('WP11 lands under Saved Lists', pn, true);
    local psum2 = optim.importNamedPrio({ DebuffL = { { stat = 'MND' } } });
    check('WP12 same name = update', psum2.updated, 1);

    -- export round trips: render -> matching parse -> identical data
    local namedFix = {
        ['STR_DEX']  = { Accuracy = { perUnit = 12 }, BlueMagicSkill = { perUnit = 3, cap = 40 } },
        ['Odd-Name'] = { MACC = { perUnit = 8 } },
    };
    local ptext = wimpT.renderPoints(namedFix);
    local back = wimpT.parse(ptext);
    check('WX1 points roundtrip: perUnit', back ~= nil and back.STR_DEX.Accuracy.perUnit, 12);
    check('WX2 points roundtrip: cap', back ~= nil and back.STR_DEX.BlueMagicSkill.cap, 40);
    check('WX3 points roundtrip: non-identifier profile name', back ~= nil and back['Odd-Name'] ~= nil
        and back['Odd-Name'].MACC.perUnit, 8);
    local prioFix = {
        ['DebuffL'] = { { stat = 'MACC' }, { stat = 'INT', cap = 60 } },
    };
    local prtext = wimpT.renderPrio(prioFix);
    local pback = wimpT.parsePrio(prtext);
    check('WX4 prio roundtrip: order survives', pback ~= nil and pback.DebuffL[1].stat == 'MACC'
        and pback.DebuffL[2].stat == 'INT', true);
    check('WX5 prio roundtrip: cap survives', pback ~= nil and pback.DebuffL[2].cap, 60);

    -- LOCAL (per-set) import (2026-07-20): ONE nameless table for the bound
    -- set. A single Name = wrapper is ignored; two+ named tables are refused
    -- (that shape belongs to the shared import); the appliers replace the
    -- BOUND set's tuning behind the copy-from revert snapshot and never touch
    -- the named stores.
    local lmap, lerr = wimpT.parseLocal('{ Accuracy = 12, Attack = 10, BlueMagicSkill = { 3, 40 } }');
    check('LW1 pure table parses clean', type(lmap) == 'table' and #lerr == 0, true);
    check('LW2 bare number row', lmap.Accuracy.perUnit, 12);
    check('LW3 capped pair row', lmap.BlueMagicSkill.perUnit == 3 and lmap.BlueMagicSkill.cap == 40, true);
    local wmap = wimpT.parseLocal('STR_DEX = { Accuracy = 12, STR = 10 },');
    check('LW4 single name wrapper ignored', wmap ~= nil and wmap.Accuracy.perUnit == 12
        and wmap.STR_DEX == nil, true);
    local two, twoErr = wimpT.parseLocal('A = { Accuracy = 12 },\nB = { Attack = 10 },');
    check('LW5 two named tables refused', two, nil);
    check('LW6 refusal names the rule', tostring(twoErr[1]):find('exactly ONE', 1, true) ~= nil, true);
    check('LW7 garbage refused', (wimpT.parseLocal('}{')), nil);

    local llist, llerr = wimpT.parsePrioLocal("{ 'MACC', 'BlueMagicSkill', { 'INT', 60 } }");
    check('LP1 pure list parses in order', #llerr == 0 and llist ~= nil and llist[1].stat == 'MACC'
        and llist[2].stat == 'BlueMagicSkill' and llist[3].stat == 'INT', true);
    check('LP2 pair cap lands', llist[3].cap, 60);
    local wlist = wimpT.parsePrioLocal("Debuff = { 'MACC', 'INT' },");
    check('LP3 single name wrapper ignored', wlist ~= nil and wlist[1].stat == 'MACC'
        and wlist[2].stat == 'INT', true);
    check('LP4 two named lists refused', (wimpT.parsePrioLocal("A = { 'MACC' }, B = { 'INT' },")), nil);

    optim.bindSetWeights('IMP', 'LocalSet');
    optim.setWeight('VIT', 5);
    local namedBefore = #optim.namedKeys();
    local okw, nw = optim.importSetWeights(lmap);
    check('LW8 set import applies', okw == true and nw, 3);
    local cur = optim.getPointWeights();
    check('LW9 replaces, not merges', cur.Accuracy ~= nil and cur.Accuracy.perUnit == 12
        and cur.VIT == nil, true);
    check('LW10 revert snapshot taken', optim.copyUndoAvailable(), true);
    check('LW11 mode lands on points', optim.weightsMode(), 'points');
    check('LW12 named store untouched', #optim.namedKeys(), namedBefore);

    local dupList = wimpT.parsePrioLocal("{ 'MACC', { 'INT', 60 }, 'MACC' }");
    local okp, np = optim.importSetPrio(dupList);
    check('LP5 set import applies + dedups', okp == true and np, 2);
    local plNow = optim.getPrio();
    check('LP6 order + cap survive', plNow[1].stat == 'MACC' and plNow[2].stat == 'INT'
        and plNow[2].cap == 60, true);
    check('LP7 mode lands on priority', optim.weightsMode(), 'priority');

    -- renameSetKey (2026-07-20, the Sets tab Rename): every per-set store and
    -- the live binding follow the new name; the actives keep working.
    check('RK1 rename returns true', optim.renameSetKey('IMP', 'LocalSet', 'LocalSet2'), true);
    check('RK2 binding follows', optim.weightsBoundTo(), 'IMP|LocalSet2');
    check('RK3 point weights ride along', optim.getPointWeights().Accuracy.perUnit, 12);
    check('RK4 old key gone from perSet', (function()
        for _, k in ipairs(optim.perSetKeys()) do if k == 'IMP|LocalSet' then return k; end end
        return nil;
    end)(), nil);
    check('RK5 prio list rides along', optim.getPrio()[1].stat, 'MACC');
    check('RK6 build mode rides along', optim.weightsMode(), 'priority');
end)();

-- ---------------------------------------------------------------------------
-- PX. selective profile export (gear/profileexport.lua + profiles weights key
-- + gearoptim per-job weights render/import) -- the export dialog's engine.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\gear\\setmanager'] = package.loaded['dlac\\gear\\setmanager'] or dofile('gear/setmanager.lua');
    package.loaded['dlac\\gear\\gearoptim'] = package.loaded['dlac\\gear\\gearoptim'] or optim;
    local pexp = dofile('gear/profileexport.lua');

    -- equipment strip: names (incl. a dashed one) survive as EMPTY shells
    local setsSrc = profilesM.frameSetsText('Dynamic = {\n'
        .. '        Idle = {\n            Head = {\n                {gear.Head.PoetsCirclet},\n            },\n        },\n'
        .. '        ["Midcast_STR-VIT"] = {\n            Body = {\n                {gear.Body.X},\n            },\n        },\n'
        .. '    }');
    local shell = pexp.stripEquipment(setsSrc);
    check('PX1 shells build', type(shell) == 'string', true);
    check('PX2 shells parse', (loadstring or load)(shell or '') ~= nil, true);
    local sc = loadWithEnv(shell or '', setmetatable({}, { __index = _G }));
    local sok, sres = pcall(sc);
    check('PX3 both names survive (dashed included)', sok and type(sres.Dynamic.Idle) == 'table'
        and type(sres.Dynamic['Midcast_STR-VIT']) == 'table', true);
    check('PX4 shells are EMPTY', sok and next(sres.Dynamic.Idle) == nil
        and next(sres.Dynamic['Midcast_STR-VIT']) == nil, true);
    check('PX5 no gear refs travel', (shell or ''):find('PoetsCirclet', 1, true), nil);

    -- triggers filter: sections drop independently; the ONE serializer round-trips
    local raw = {
        Midcast = { { when = { group = 'Debuff' }, set = 'Midcast_Debuff' } },
        Groups = { Debuff = { 'Sheep Song' } },
        Modes = { DT = { values = { 'On', 'Off' } } },
    };
    local outT = pexp.filterTriggersRaw(raw, { triggers = true }, dispatchM.canonEvent);
    check('PX6 triggers only', outT.Midcast ~= nil and outT.Groups == nil and outT.Modes == nil, true);
    local outG = pexp.filterTriggersRaw(raw, { groups = true, modes = true }, dispatchM.canonEvent);
    check('PX7 groups+modes only', outG.Midcast == nil and outG.Groups ~= nil and outG.Modes ~= nil, true);
    local ser = dispatchM.serializeTriggers(outG);
    local tok, tres = pcall((loadstring or load)(ser));
    check('PX8 filtered file parses', tok and type(tres) == 'table', true);
    check('PX9 filtered file: groups+modes, no rules', tok and tres.Midcast == nil
        and type(tres.Groups) == 'table' and tres.Groups.Debuff[1] == 'Sheep Song'
        and type(tres.Modes) == 'table' and tres.Modes.DT ~= nil, true);

    -- export format: the weights key rides job-export v1 and round-trips
    local ex = profilesM.buildExportText('BLU', 'Default', 'Mindie', 'return {};', nil, nil, '-- w\nreturn { perSet = {} };\n');
    local meta = profilesM.parseExportText(ex);
    check('PX10 weights key round-trips', meta ~= nil and type(meta.weights) == 'string', true);
    check('PX11 weights-only export is valid', (profilesM.parseExportText(
        profilesM.buildExportText('BLU', 'P', 'X', nil, nil, nil, 'return { perSet = {} };'))) ~= nil, true);

    -- per-job weights render/import (headless paths resolve nil -> LIVE stores)
    optim.bindSetWeights('BLU', 'PXSet');
    optim.setWeight('Accuracy', 12, 60);
    local wtext, wn = optim.renderJobWeightsTextAt('Whoever_1', 'BLU');
    check('PX12 render finds exactly the job\'s set', wn, 1);
    check('PX13 payload is gearweights-shaped', type(wtext) == 'string'
        and wtext:find('["BLU|PXSet"]', 1, true) ~= nil, true);
    local iN = optim.importJobWeightsTextAt('Whoever_1', wtext, 'BLU', 'BLU2');
    check('PX14 import re-keys to the imported job name', iN, 1);
    local got = optim._perSet['BLU2|PXSet'];
    check('PX15 imported weights land intact', got ~= nil and got.Accuracy ~= nil
        and got.Accuracy.perUnit == 12 and got.Accuracy.cap == 60, true);
    check('PX16 payload without the named job refuses',
        (select(2, optim.importJobWeightsTextAt('Whoever_1', wtext, 'DRK', 'DRK'))) ~= nil, true);
    -- Live-branch persist failures are LOUD (2026-07-20, the field case of a
    -- friend's weightless import): headless saveWeights cannot resolve a
    -- path, so the import must return its count PLUS the warning -- losing
    -- the merge silently on the next reload was the failure mode.
    local iN2, iWarn = optim.importJobWeightsTextAt('Whoever_1', wtext, 'BLU', 'BLU3');
    check('PX16b live merge still counts', iN2, 1);
    check('PX16c persist failure surfaces as a warning', type(iWarn) == 'string'
        and iWarn:find('saving gearweights', 1, true) ~= nil, true);
    optim.bindSetWeights(nil, nil);

    -- dependency analysis: what the data references (the form's gating input)
    local rawDeps = {
        Midcast = { { when = { group = 'Debuff' }, set = 'A' } },
        Precast = { { when = { name = 'Cure' }, whenAny = { { mode = 'DT' }, { status = 'Engaged' } }, set = 'B' } },
    };
    local refs = pexp.triggerRefs(rawDeps, dispatchM.canonEvent);
    check('PX17 group condition detected', refs.groups, true);
    check('PX18 mode condition detected inside whenAny', refs.modes, true);
    check('PX18b set action is a dependency', refs.sets, true);
    local refs2 = pexp.triggerRefs({ Midcast = { { when = { name = 'Cure' }, set = 'A' } } }, dispatchM.canonEvent);
    check('PX19 no group/mode refs when rules use neither', refs2.modes == false and refs2.groups == false, true);
    -- an EMPTY-condition rule still depends on its set; an inline-equip rule does not
    local refsE = pexp.triggerRefs({ Precast = { { when = {}, set = 'Cure_Fast' } } }, dispatchM.canonEvent);
    check('PX19b empty condition still needs its set', refsE.sets == true and refsE.modes == false and refsE.groups == false, true);
    local refsQ = pexp.triggerRefs({ Precast = { { when = { name = 'X' }, equip = { Head = 'Y' } } } }, dispatchM.canonEvent);
    check('PX19c inline-equip rule carries no set dep', refsQ.sets, false);
    local gated = profilesM.frameSetsText('Dynamic = {\n        Idle = {\n            Body = {\n                {gear.Body.X, mode = "DT"},\n            },\n        },\n    }');
    check('PX20 mode-gated gear detected', pexp.setsUseModes(gated), true);
    check('PX21 plain gear carries no mode dep', pexp.setsUseModes(setsSrc), false);
end)();

-- ---------------------------------------------------------------------------
-- AM. AutoAmmo (engine v73) -- the pure decision core M.resolveAmmoPlan
--     (docs/design/auto-ammo.md). The strictness contract pinned headless:
--     special ammo is never planned where a shot could consume it; windows
--     open only on AFFIRMATIVE facts (unlimited == nil is "unknown" and opens
--     nothing); picks are count-verified; with a special worn and nothing
--     enabled in stock the answer is 'remove' (an empty gun is server-blocked
--     -- the shot refuses instead of eating the bullet).
-- ---------------------------------------------------------------------------
(function()
    local rap = dispatchM.resolveAmmoPlan;
    local CFG = {
        enabled = true,
        jobs = { COR = true },
        ammo = {   -- array order = fallback priority
            { name = 'Bronze Bullet',   id = 1, type = 'Marksmanship', ranged = true,  ws = false, special = false },
            { name = 'Ruszor Bullet',   id = 2, type = 'Marksmanship', ranged = false, ws = true,  special = false },
            { name = 'Animikii Bullet', id = 3, type = 'Marksmanship', ranged = false, ws = false,
              special = { unlimited = true, quickdraw = true, freews = true } },
        },
    };
    -- facts builder: stock is id -> count; everything else overridable
    local function F(over, stock)
        local f = { event = 'Preshot', job = 'COR',
                    count = function(e) return (stock or { [1] = 12, [2] = 12, [3] = 1 })[e.id] or 0; end };
        for k, v in pairs(over or {}) do f[k] = v; end
        return f;
    end

    -- Preshot / Midshot (normal ranged attacks)
    check('AM1 Preshot picks the first ranged-enabled with stock', rap(CFG, F()), 'Bronze Bullet');
    check('AM2 Midshot same law', rap(CFG, F({ event = 'Midshot' })), 'Bronze Bullet');
    local p3, w3 = rap(CFG, F({ worn = 'Animikii Bullet' }, { [3] = 1 }));
    check('AM3 worn special + nothing stocked = remove', p3, 'remove');
    check('AM3b the reason names the protected bullet', (w3 or ''):find('Animikii Bullet', 1, true) ~= nil, true);
    check('AM4 worn normal + nothing stocked = hold (server refuses the empty shot)',
        rap(CFG, F({ worn = 'Bronze Bullet' }, { [3] = 1 })), nil);
    check('AM5 Unlimited Shot window opens the special', rap(CFG, F({ unlimited = true })), 'Animikii Bullet');
    check('AM5b unknown buff state opens NOTHING (affirmative-only)',
        rap(CFG, F({ unlimited = nil })), 'Bronze Bullet');
    check('AM6 US window but special unowned -> ranged pick',
        rap(CFG, F({ unlimited = true }, { [1] = 12 })), 'Bronze Bullet');
    local CFG2 = { enabled = true, ammo = {
        { name = 'Cheap A', id = 1, type = 'Marksmanship', ranged = true, ws = false, special = false },
        { name = 'Cheap B', id = 2, type = 'Marksmanship', ranged = true, ws = false, special = false },
    } };
    check('AM7 priority = list order: first out of stock falls to second',
        rap(CFG2, F(nil, { [2] = 5 })), 'Cheap B');

    -- Weaponskill: the three free magical ranged WS (217/218/220)
    check('AM8 Leaden Salute (218) opens the free-WS window',
        rap(CFG, F({ event = 'Weaponskill', wsId = 218 })), 'Animikii Bullet');
    local CFGnf = { enabled = true, jobs = { COR = true }, ammo = {
        { name = 'Bronze Bullet', id = 1, type = 'Marksmanship', ranged = true, ws = false, special = false },
        { name = 'Ruszor Bullet', id = 2, type = 'Marksmanship', ranged = false, ws = true, special = false },
        { name = 'Animikii Bullet', id = 3, type = 'Marksmanship', ranged = false, ws = false,
          special = { unlimited = true, quickdraw = true, freews = false } },
    } };
    check('AM8b freews unticked -> the WS pick instead',
        rap(CFGnf, F({ event = 'Weaponskill', wsId = 218 })), 'Ruszor Bullet');
    check('AM8c free WS with no special and no WS ammo -> ranged pick (nothing is consumed)',
        rap(CFGnf, F({ event = 'Weaponskill', wsId = 220 }, { [1] = 12 })), 'Bronze Bullet');

    -- Weaponskill: consuming physical ranged WS
    check('AM9 Last Stand (221) takes the WS pick',
        rap(CFG, F({ event = 'Weaponskill', wsId = 221 })), 'Ruszor Bullet');
    check('AM10 consuming WS, WS ammo dry, special worn -> falls to ranged',
        rap(CFG, F({ event = 'Weaponskill', wsId = 212, worn = 'Animikii Bullet' }, { [1] = 12, [3] = 1 })),
        'Bronze Bullet');
    check('AM10b consuming WS, everything dry, special worn -> remove',
        rap(CFG, F({ event = 'Weaponskill', wsId = 212, worn = 'Animikii Bullet' }, { [3] = 1 })),
        'remove');
    check('AM11 consuming WS, no WS ammo, worn normal -> hold',
        rap(CFG, F({ event = 'Weaponskill', wsId = 212, worn = 'Bronze Bullet' }, { [1] = 12 })), nil);
    check('AM12 melee/unknown WS never touches ammo, even with the special worn',
        rap(CFG, F({ event = 'Weaponskill', wsId = 33, worn = 'Animikii Bullet' })), nil);

    -- Ability: Quick Draw
    check('AM13 QD by LAC ability type', rap(CFG, F({ event = 'Ability', abilityType = 'Quick Draw' })), 'Animikii Bullet');
    check('AM13b QD by shot name (type fallback)',
        rap(CFG, F({ event = 'Ability', abilityName = 'Fire Shot' })), 'Animikii Bullet');
    local CFGarrow = { enabled = true, ammo = {
        { name = 'Wing Arrow', id = 9, type = 'Archery', ranged = false, ws = false,
          special = { quickdraw = true } },
    } };
    check('AM13c QD never offers a non-Marksmanship special (the server gate)',
        rap(CFGarrow, F({ event = 'Ability', abilityType = 'Quick Draw' }, { [9] = 99 })), nil);
    check('AM13d any other ability is not ours',
        rap(CFG, F({ event = 'Ability', abilityName = 'Provoke' })), nil);

    -- Default: the protection sweep + reload
    check('AM14 sweep: worn special outside every window -> ranged pick',
        rap(CFG, F({ event = 'Default', worn = 'Animikii Bullet' })), 'Bronze Bullet');
    check('AM14b sweep with nothing stocked -> remove',
        rap(CFG, F({ event = 'Default', worn = 'Animikii Bullet' }, { [3] = 1 })), 'remove');
    check('AM15 US window at Default pre-loads/keeps the special',
        rap(CFG, F({ event = 'Default', worn = 'Animikii Bullet', unlimited = true })), 'Animikii Bullet');
    check('AM16 fishing owns Ammo at Default -> stand down',
        rap(CFG, F({ event = 'Default', worn = 'Animikii Bullet', fishing = true })), nil);
    check('AM17 empty slot reloads the ranged pick (the marquee LAC fix)',
        rap(CFG, F({ event = 'Default' })), 'Bronze Bullet');
    check('AM17b sets planned an owned ammo -> theirs',
        rap(CFG, F({ event = 'Default', plannedAmmo = true })), nil);
    check('AM17c worn unconfigured trinket -> never touched',
        rap(CFG, F({ event = 'Default', worn = 'Tiphia Sting' })), nil);

    -- Gates
    check('AM18 jobs gate: unticked job does nothing', rap(CFG, F({ job = 'WHM' })), nil);
    check('AM18b not-ready job (nil) does nothing',   -- built by hand: pairs() skips a nil override
        rap(CFG, { event = 'Preshot', count = function() return 99; end }), nil);
    local CFGnojobs = { enabled = true, ammo = CFG.ammo };
    check('AM18c hand-written file without a jobs map is ungated', rap(CFGnojobs, F()), 'Bronze Bullet');
    check('AM19 disabled -> nil', rap({ enabled = false, ammo = CFG.ammo }, F()), nil);
    check('AM19b empty config -> nil', rap({ enabled = true, ammo = {} }, F()), nil);
    check('AM20 no counter: picks never fire but protection still does',
        rap(CFG, F({ worn = 'Animikii Bullet', count = false })), 'remove');
    check('AM20b no counter, nothing to protect -> hold',
        rap(CFG, F({ worn = 'Bronze Bullet', count = false })), nil);
    check('AM21 worn match is case-insensitive',
        rap(CFG, F({ event = 'Default', worn = 'ANIMIKII bullet' })), 'Bronze Bullet');

    -- The baked server-truth tables (seam _ammoWs): the three free ids and a
    -- consuming spot-check cannot drift silently.
    check('AM22 free set = Trueflight/Leaden/Wildfire',
        dispatchM._ammoWs.free[217] == true and dispatchM._ammoWs.free[218] == true
        and dispatchM._ammoWs.free[220] == true, true);
    check('AM22b free ids are not in the consuming set',
        dispatchM._ammoWs.consume[218], nil);
    check('AM22c Coronach consumes', dispatchM._ammoWs.consume[216], true);
    check('AM23 ammoStateOn wants enabled + a non-empty list',
        dispatchM._ammoStateOn({ enabled = true, ammo = CFG.ammo }), true);
    check('AM23b enabled with no list is OFF',
        dispatchM._ammoStateOn({ enabled = true, ammo = {} }), false);
end)();

-- ---------------------------------------------------------------------------
-- AW. ammowatch -- the GUI's half of AutoAmmo: the fmt-2 PER-JOB serializer
--     (round-trips through the engine's reader shape), the fmt-1 migration
--     (every ticked job gets its own copy; an unowned list becomes the
--     orphan the first job in adopts), and the mutator invariants (special
--     is exclusive; priority moves stay in bounds; jobs never cross-read).
--     Headless: charDir is nil, so every save is a silent no-op -- the
--     in-memory jobsData is what's under test.
-- ---------------------------------------------------------------------------
(function()
    local aw = dofile('feature/ammowatch.lua');   -- the harness has no addons/ on package.path

    local corSec = {
        enabled = true, at = 1753000000,
        ammo = {
            { name = 'Bronze Bullet', id = 21306, type = 'Marksmanship', level = 5, ranged = true, ws = false, special = false },
            { name = "Animikii Bullet", id = 21334, type = 'Marksmanship', level = 75, ranged = false, ws = false,
              special = { unlimited = true, quickdraw = true, freews = false } },
        },
    };
    local txt = aw._serialize({ COR = corSec, RNG = { enabled = false, at = 0, ammo = {} } });
    local back = (loadstring or load)(txt)();
    check('AW1 fmt 2 on the wire', back.fmt, 2);
    check('AW2 per-job enabled + at survive',
        back.jobs.COR.enabled == true and back.jobs.COR.at == 1753000000
        and back.jobs.RNG.enabled == false, true);
    check('AW4 entry order preserved', back.jobs.COR.ammo[1].name, 'Bronze Bullet');
    check('AW5 normal entry: special = false', back.jobs.COR.ammo[1].special, false);
    check('AW5b level survives', back.jobs.COR.ammo[2].level, 75);
    check('AW6 special table survives with only true bits',
        back.jobs.COR.ammo[2].special.unlimited == true and back.jobs.COR.ammo[2].special.quickdraw == true
        and back.jobs.COR.ammo[2].special.freews == nil, true);
    check('AW7 the engine gate accepts the round-trip', dispatchM._ammoStateOn(back), true);
    check('AW7b the engine gate refuses all-off sections',
        dispatchM._ammoStateOn({ fmt = 2, jobs = { RNG = { enabled = false, ammo = corSec.ammo } } }), false);
    check('AW7c the engine gate refuses an enabled EMPTY section',
        dispatchM._ammoStateOn({ fmt = 2, jobs = { RNG = { enabled = true, ammo = {} } } }), false);

    -- fmt-1 migration: every ticked job gets its OWN COPY; no ticked job = orphan
    local old = { enabled = true, at = 9, jobs = { COR = true, RNG = true, WAR = false },
                  ammo = { { name = 'Bullet', id = 1, type = 'Marksmanship', ranged = true, ws = false, special = false } } };
    local jd, orph = aw._migrate(old);
    check('AW18 fmt-1 ticked jobs each get a section',
        jd.COR ~= nil and jd.RNG ~= nil and jd.WAR == nil, true);
    check('AW18b sections carry the old switch + list',
        jd.COR.enabled == true and jd.COR.ammo[1].name == 'Bullet', true);
    check('AW18c no orphan when jobs were ticked', orph, nil);
    jd.COR.ammo[1].ranged = false;
    check('AW18d sections are COPIES (jobs diverge independently)', jd.RNG.ammo[1].ranged, true);
    local jd2, orph2 = aw._migrate({ enabled = true, jobs = {}, ammo = old.ammo });
    check('AW19 fmt-1 with no ticked job -> orphan (nothing lost)',
        next(jd2) == nil and orph2 ~= nil and orph2.ammo[1].name == 'Bullet', true);
    check('AW19b orphan comes back disarmed', orph2.enabled, false);
    aw.jobsData = {};
    aw._setOrphan(orph2);
    aw.selectJob('WAR');
    check('AW19c first job in adopts the orphan', aw.jobsData.WAR ~= nil and #aw.list == 1, true);

    -- mutators (in-memory; saves no-op headless) + per-job isolation
    aw.jobsData = {};
    aw.selectJob('COR');
    check('AW8 addAmmo', aw.addAmmo({ Name = 'Iron Bullet', Id = 21310, AmmoType = 'Marksmanship' }), true);
    check('AW8b dedup by name (ci)', aw.addAmmo({ Name = 'IRON bullet', Id = 21310, AmmoType = 'Marksmanship' }), false);
    aw.addAmmo({ Name = 'Bomb Core', Id = 5309, AmmoType = 'Throwing' });
    aw.setEnabled(true, 'COR');
    aw.selectJob('RNG');
    check('AW20 another job reads EMPTY and OFF (per-job isolation)',
        #aw.list == 0 and aw.enabled == false, true);
    aw.addAmmo({ Name = 'Wing Arrow', Id = 9000, AmmoType = 'Archery' });
    aw.selectJob('COR');
    check('AW20b the first job kept its own list and switch',
        #aw.list == 2 and aw.enabled == true and aw.list[1].name == 'Iron Bullet', true);
    check('AW20c jobSummary sees both jobs', #aw.jobSummary(), 2);
    aw.moveAmmo(2, -1);
    check('AW9 moveAmmo reorders', aw.list[1].name, 'Bomb Core');
    aw.moveAmmo(1, -1);
    check('AW9b out-of-bounds move is a no-op', aw.list[1].name, 'Bomb Core');
    aw.setFlag(1, 'ranged', true);
    check('AW10 setFlag ranged', aw.list[1].ranged, true);
    aw.setSpecial(1, true);
    check('AW11 special is exclusive: ranged cleared', aw.list[1].ranged, false);
    check('AW11b behaviours default off',
        aw.list[1].special.unlimited == false and aw.list[1].special.quickdraw == false, true);
    aw.setFlag(1, 'ranged', true);
    check('AW12 setFlag refused on a special entry', aw.list[1].ranged, false);
    aw.setBehaviour(1, 'freews', true);
    check('AW13 setBehaviour', aw.list[1].special.freews, true);
    aw.setBehaviour(1, 'nonsense', true);
    check('AW13b unknown behaviour refused', aw.list[1].special.nonsense, nil);
    aw.setSpecial(1, false);
    check('AW14 special off restores a normal entry', aw.list[1].special, false);
    aw.removeAmmo(1);
    check('AW15 removeAmmo', #aw.list == 1 and aw.list[1].name == 'Iron Bullet', true);

    -- EB. eboxammo -- the E-Box 0x1A4 client (trove's wire format, reimplemented;
    -- Crystal-Warrior-only consumer of gamemode.get). Parsing is string.byte so
    -- the whole wire path runs here; packets are built as synthetic strings.
    local eb = dofile('feature/eboxammo.lua');
    local function pk(bytes)
        local t = {};
        for off = 0, 63 do t[off + 1] = string.char(bytes[off] or 0); end
        return table.concat(t);
    end
    local function msgAt(t, off, s)
        for k = 1, #s do t[off + k - 1] = string.byte(s, k); end
        return t;
    end
    check('EB1 clamp: none in box -> 0', eb._clampQty(99, 0), 0);
    check('EB1b clamp to what the box holds', eb._clampQty(99, 12), 12);
    check('EB1c junk qty -> 0', eb._clampQty('x', 5), 0);
    check('EB1d floors fractions', eb._clampQty(3.7, 5), 3);

    check('EB2 ITEM outside our stream is not ours (trove\'s traffic)',
        eb._onPacket(pk({ [0x04] = 1, [0x08] = 10 })), false);
    eb._beginStream();
    check('EB3 CLEAR consumed while pending', eb._onPacket(pk({ [0x04] = 0 })), true);
    eb._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0C] = 200 }));   -- id 21302 x200
    eb._onPacket(pk({ [0x04] = 1, [0x08] = 0x56, [0x09] = 0x53, [0x0C] = 1 }));     -- id 21334 x1
    check('EB3b END_LIST from another source does not commit',
        eb._onPacket(pk({ [0x04] = 2, [0x05] = 3 })), false);
    check('EB3c END_LIST source 0 commits', eb._onPacket(pk({ [0x04] = 2, [0x05] = 0 })), true);
    check('EB3d counts committed', eb.counts[21302] == 200 and eb.counts[21334] == 1, true);
    check('EB4 stream closed: a late ITEM is not ours',
        eb._onPacket(pk({ [0x04] = 1, [0x08] = 10 })), false);

    eb.busy = true;
    check('EB5 ACK for someone else\'s action is not ours',
        eb._onPacket(pk({ [0x04] = 3, [0x05] = 15, [0x06] = 1 })), false);
    check('EB5b withdraw ACK success clears busy',
        eb._onPacket(pk({ [0x04] = 3, [0x05] = 2, [0x06] = 1 })), true);
    check('EB5c success status is not an error', eb.busy == false and eb.statusErr == false, true);
    eb.busy = true;
    eb._onPacket(pk(msgAt({ [0x04] = 3, [0x05] = 2, [0x06] = 0 }, 0x10, 'Inventory full.')));
    check('EB5d refusal carries the server\'s words', eb.status, 'Inventory full.');
    check('EB5e refusal is an error', eb.statusErr, true);
    check('EB5f ACK with nothing in flight is not ours',
        eb._onPacket(pk({ [0x04] = 3, [0x05] = 2, [0x06] = 1 })), false);

    check('EB6 unsolicited LOCKED is not ours (must not shut the panel)',
        eb._onPacket(pk({ [0x04] = 4, [0x05] = 1 })), false);
    eb._beginStream();
    eb._onPacket(pk({ [0x04] = 4, [0x05] = 1 }));
    check('EB6b LOCKED reason 1 while pending = not a Crystal Warrior', eb.lockedReason, 'cw');
    eb.lockedReason = nil;
    eb._beginStream();
    eb._onPacket(pk(msgAt({ [0x04] = 4, [0x05] = 2 }, 0x10, 'Locked.')));
    check('EB6c LOCKED reason 2 = box not unlocked', eb.lockedReason == 'locked' and eb.lockedMsg == 'Locked.', true);
    eb.lockedReason = nil;

    check('EB7 refresh refuses headless (not CW -- the affirmative-only gate)', eb.refresh(), false);
    check('EB7b withdraw refuses headless too', eb.withdraw(21334, 1), false);

    -- EW. lib/entwatch -- the CENTRAL entity watcher (field round 6; built
    -- from this feature's scan lessons, eboxammo is consumer #1). Injected
    -- probe + clock; the padded/cased names, index 0 and the 0x802 dynamic
    -- slot pin the field lessons (rounds 2-4: exact-name compare never
    -- matched GetName's trailing whitespace; the 0-1023 static sweep could
    -- never reach a dynamically spawned box) forever.
    local ew = dofile('lib/entwatch.lua');
    local ewNow = 1000;
    ew._now = function() return ewNow; end;
    local world = { [12]   = { name = 'Ephemeral Box   ', d2 = 100 },   -- padded: the live shape
                    [40]   = { name = 'EPHEMERAL box',    d2 = 25 },    -- case must not matter
                    [0]    = { name = 'Ephemeral Box',    d2 = 3600 },  -- slot 0 is scanned too
                    [2050] = { name = 'Ephemeral Box ',   d2 = 16 },    -- 0x802: the live dynamic slot
                    [77]   = { name = 'Nomad Moogle',     d2 = 4 } };
    local probe = {
        present = function(idx) return world[idx] ~= nil; end,
        name    = function(idx) return world[idx] and world[idx].name; end,
        distSq  = function(idx) return world[idx] and world[idx].d2; end,
    };
    check('EW1 nearest before any watch = nil', ew.nearest('Ephemeral Box'), nil);
    local cbN = {};
    check('EW2 watch registers', ew.watch('t_ebox', 'Ephemeral Box', function(m) cbN[#cbN + 1] = #m; end), true);
    check('EW2b a callback watch is active without polling', ew._sweep(probe, ewNow), true);
    check('EW2c the callback fired with the sorted match set', cbN[1], 4);
    local d1, i1 = ew.nearest('Ephemeral Box');
    check('EW3 nearest despite padding/case, in yalms', d1, 4.0);
    check('EW3b ...and it is the dynamic 0x802 slot', i1, 2050);
    local ms = ew.matches('Ephemeral Box');
    check('EW4 matches sorted nearest-first', ms[1].idx == 2050 and ms[#ms].idx == 0, true);
    check('EW5 sweep cadence: not due again yet', ew._sweep(probe, ewNow + 1), false);
    -- fast refresh: distance moves WITHOUT a sweep; slot reuse gets evicted
    world[2050].d2 = 9;
    world[40] = { name = 'Goblin Digger', d2 = 1 };   -- slot REUSED by a stranger
    ew._refresh(probe, ewNow + 1);
    check('EW6 tracked distance refreshed between sweeps', (ew.nearest('Ephemeral Box')), 3.0);
    check('EW6b reused slot evicted (name re-verified)', #ew.matches('Ephemeral Box'), 3);
    -- change detection: the next due sweep sees the same 3 -> no new callback
    ewNow = ewNow + 3;
    ew._sweep(probe, ewNow);
    check('EW7 unchanged match set fires no callback', #cbN, 2);   -- 1 initial + 1 for the eviction round
    ew._sweep(probe, ewNow + 3);
    check('EW7b (still none without a change)', #cbN, 2);
    -- demand window: a POLLED watch sleeps IDLE_S after its last ask
    ew.unwatch('t_ebox');
    check('EW8 last subscriber leaving tears the entry down', ew.nearest('Ephemeral Box'), nil);
    ew.watch('t_poll', 'Ephemeral Box');
    ewNow = ewNow + 100;                              -- stale ask: inactive
    check('EW8b idle polled watch sweeps nothing', ew._sweep(probe, ewNow), false);
    ew.nearest('Ephemeral Box');                      -- the ask IS the demand
    check('EW8c a fresh ask wakes it', ew._sweep(probe, ewNow), true);
    -- poke: cache-bust ahead of the cadence (the panel's rescan button)
    check('EW9 not due again', ew._sweep(probe, ewNow + 1), false);
    ew.poke('Ephemeral Box');
    check('EW9b poke forces the next sweep', ew._sweep(probe, ewNow + 1), true);
    ew.unwatch('t_poll');
    check('EW10 empty registry reports empty', #ew.debugState(), 0);

    check('EB9 box range is FIELD-PINNED at 5 yalms (Henrik 2026-07-20)', eb.BOX_RANGE, 5);
    check('EB10 boxDistance is headless-safe through the watcher', eb.boxDistance(), nil);

    -- level: persisted per entry (GUI sort data; the engine ignores it --
    -- the fmt-2 round-trip above pins the serializer side)
    aw.jobsData.COR.ammo = {};
    aw.selectJob('COR');
    aw.addAmmo({ Name = 'Lv-carrier', Id = 7, AmmoType = 'Marksmanship', Level = 40 });
    check('AW16 addAmmo stores the catalog level', aw.list[1].level, 40);

    -- Sort by level: DESC, stable on ties, catalog backfill for old entries
    aw.jobsData.COR.ammo = {
        { name = 'Old NoLv',  id = 1, type = 'Marksmanship', level = 0,  ranged = true, ws = false, special = false },
        { name = 'Mid A',     id = 2, type = 'Marksmanship', level = 50, ranged = true, ws = false, special = false },
        { name = 'Top',       id = 3, type = 'Marksmanship', level = 99, ranged = true, ws = false, special = false },
        { name = 'Mid B',     id = 4, type = 'Marksmanship', level = 50, ranged = true, ws = false, special = false },
    };
    aw.selectJob('COR');   -- re-point the proxy at the fresh table
    local changed = aw.sortByLevel(function(e) return (e.name == 'Old NoLv') and 75 or 0; end);
    check('AW17 sort reordered (and said so)', changed, true);
    check('AW17b highest first', aw.list[1].name, 'Top');
    check('AW17c backfilled level slots in by its looked-up value', aw.list[2].name, 'Old NoLv');
    check('AW17d the backfill is written onto the entry', aw.list[2].level, 75);
    check('AW17e ties keep their original order (stable)',
        aw.list[3].name == 'Mid A' and aw.list[4].name == 'Mid B', true);
    check('AW17f already-sorted list reports no change', aw.sortByLevel(nil), false);

    -- Categories (field round 5): DERIVED from AmmoType + name -- the catalog
    -- lumps bullets and bolts under Marksmanship, the name splits them.
    check('AW21 bullets by name', aw.categoryOf('Bronze Bullet', 'Marksmanship'), 'Bullets');
    check('AW21b bolts by name', aw.categoryOf('Bloody Bolt', 'Marksmanship'), 'Bolts');
    check('AW21c name match is ci', aw.categoryOf('SPARTAN BULLET', 'Marksmanship'), 'Bullets');
    check('AW21d archery = arrows regardless of name', aw.categoryOf('Kabura Arrow', 'Archery'), 'Arrows');
    check('AW21e throwing keeps its own bucket', aw.categoryOf('Fuma Shuriken', 'Throwing'), 'Throwing');
    check('AW21f unmatched marksmanship falls to Other', aw.categoryOf('Gold Quarrel', 'Marksmanship'), 'Other');
    check('AW21g trinket-ish types fall to Other', aw.categoryOf('Tiphia Sting', ''), 'Other');

    -- swapAmmo: the filtered view's move (non-adjacent underneath)
    aw.jobsData.COR.ammo = {
        { name = 'A', id = 1, type = 'Marksmanship', level = 1, ranged = true, ws = false, special = false },
        { name = 'B', id = 2, type = 'Archery',      level = 1, ranged = true, ws = false, special = false },
        { name = 'C', id = 3, type = 'Marksmanship', level = 1, ranged = true, ws = false, special = false },
    };
    aw.selectJob('COR');
    aw.swapAmmo(1, 3);
    check('AW22 swapAmmo swaps non-adjacent positions',
        aw.list[1].name == 'C' and aw.list[3].name == 'A' and aw.list[2].name == 'B', true);
    aw.swapAmmo(1, 9);
    check('AW22b out-of-bounds swap is a no-op', aw.list[1].name, 'C');
end)();

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
