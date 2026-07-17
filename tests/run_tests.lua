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
        Sword = { Offsword = { Name = 'Offjob Sword', Level = 75, Jobs = { 'DRK' } } },
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
                { Name = 'Kris',       Id = 16000, Level = 60, Slot = 'Main', Model = 7  },  -- other slot
                { Name = 'Gletis Crossbow', Id = 14003, Level = 99, Slot = 'Body' },         -- server junk: no Model
                { Name = 'Amini Bottillons +2', Id = 14004, Level = 99, Slot = 'Body', Model = 0 }, -- junk: Model 0
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

    -- Proximity anchor (Henrik's first-swing fix): target a Point within 6y
    -- -> gear on BEFORE the first trade; the anchor then outlives the target
    -- (HELMing clears it) and drops on distance/despawn. Probe-driven: the
    -- world state is a plain table the fake closures read.
    local world = { target = nil, ents = {} };   -- ents[idx] = { name, distSq }
    local probe = {
        target  = function() return world.target; end,
        present = function(idx) return world.ents[idx] ~= nil; end,
        name    = function(idx) local e = world.ents[idx]; return e and e.name or nil; end,
        distSq  = function(idx) local e = world.ents[idx]; return e and e.distSq or nil; end,
    };
    helmwatch.setAutoHelm(true);
    helmwatch.setProxRange(6);   -- pin the original 6y/8y geometry for H51-H64
    world.ents[400] = { name = 'Mining Point', distSq = 25 };      -- 5y
    world.target = 400;
    check('H51 target in range anchors',      helmwatch.proximityStep(probe), true);
    check('H52 anchor equips (hold live)',    helmwatch.autoActive(), true);
    check('H53 anchor selects category',      helmwatch.getGather(), 'Mining');
    world.target = nil;                                            -- HELMing cleared the target
    check('H54 anchor outlives the target',   helmwatch.proximityStep(probe), true);
    world.ents[400].distSq = 49;                                   -- 7y: inside leave hysteresis
    check('H55 hysteresis keeps it to 8y',    helmwatch.proximityStep(probe), true);
    world.ents[400].distSq = 100;                                  -- 10y: walked away
    check('H56 out of range drops anchor',    helmwatch.proximityStep(probe), false);
    world.ents[400].distSq = 25;                                   -- back in range, no target
    check('H57 no re-anchor without target',  helmwatch.proximityStep(probe), false);
    world.target = 400; world.ents[400] = nil;                     -- despawned mid-target
    check('H58 despawned target never anchors', helmwatch.proximityStep(probe), false);
    world.ents[401] = { name = 'Fantoccini', distSq = 4 };
    world.target = 401;
    check('H59 non-Point target ignored',     helmwatch.proximityStep(probe), false);
    world.ents[402] = { name = 'Logging Point', distSq = 100 };    -- 10y: too far to acquire
    world.target = 402;
    check('H60 in-name but out-of-enter-range', helmwatch.proximityStep(probe), false);
    -- a swing result re-seats the anchor even with no target at all
    helmwatch.onEventNum(evt, function(i) return (i == 319) and 'Logging Point' or nil; end);
    world.target = nil;
    world.ents[319] = { name = 'Logging Point', distSq = 9 };
    check('H61 swing result seeds the anchor', helmwatch.proximityStep(probe), true);
    check('H62 seeded anchor swaps category',  helmwatch.getGather(), 'Logging');
    world.ents[319] = nil;                                         -- point relocated
    check('H63 despawn drops the anchor',      helmwatch.proximityStep(probe), false);
    helmwatch.setAutoHelm(false);
    world.target = 400; world.ents[400] = { name = 'Mining Point', distSq = 25 };
    check('H64 disarmed: never anchors',       helmwatch.proximityStep(probe), false);

    -- Configurable detect range (Henrik: default 10 for macro-spam-at-range
    -- and lag; panel setting clamped 3..20, keep-wearing leash = range+2).
    check('H70 default range is 10',        helmwatch.PROX_DEFAULT, 10);
    helmwatch.setProxRange(25);
    check('H71 clamps high to 20',          helmwatch.proxEnter(), 20);
    helmwatch.setProxRange(1);
    check('H72 clamps low to 3',            helmwatch.proxEnter(), 3);
    helmwatch.setProxRange(10);
    helmwatch.setAutoHelm(true);
    world.ents[500] = { name = 'Harvesting Point', distSq = 81 };  -- 9y: outside 6, inside 10
    world.target = 500;
    check('H73 wider range acquires at 9y', helmwatch.proximityStep(probe), true);
    world.target = nil;
    world.ents[500].distSq = 143;                                  -- just inside the 12y leash
    check('H74 leash follows range (+2y)',  helmwatch.proximityStep(probe), true);
    world.ents[500].distSq = 145;                                  -- just past it
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
-- verdict
-- ---------------------------------------------------------------------------
if #failures == 0 then
    print(string.format('OK -- %d checks passed', count));
    os.exit(0);
end
print(string.format('FAIL -- %d of %d checks failed:', #failures, count));
for _, f in ipairs(failures) do print('  ' .. f); end
os.exit(1);
