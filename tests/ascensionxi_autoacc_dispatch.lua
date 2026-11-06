-- lua tests/ascensionxi_autoacc_dispatch.lua   (from the dlac repo root)
-- AutoAcc at the engine's single send (dispatch.lua v170): with an 'autoacc'
-- service every typed piece is planned on, each slot's last writer decides
-- whether the slot carries an AutoAcc candidate, and the send asks the
-- service once on the composed outfit. Without the service the dormant
-- foundation is untouched (tests AC* in run_tests.lua).

-- The run_tests.lua environment, the part dispatch.lua needs.
package.loaded['dlac\\gear'] = { NameToObject = {} };
ashita = { events = { register = function() end } };
package.loaded['dlac\\gear\\gathering'] = dofile('gear/gathering.lua');
package.loaded['dlac\\profiles'] = dofile('profiles.lua');
package.loaded['dlac\\gear\\nativemp'] = dofile('gear/nativemp.lua');
package.loaded['dlac\\data\\zones'] = dofile('servers/cexi/data/zones.lua');
package.loaded['dlac\\feature\\mpbands'] = dofile('feature/mpbands.lua');
package.loaded['dlac\\feature\\location'] = dofile('feature/location.lua');
package.loaded['dlac\\gear\\jobgate'] = dofile('gear/jobgate.lua');
package.loaded['dlac\\gear\\gearrecord'] = dofile('gear/gearrecord.lua');
package.loaded['dlac\\lib\\safewrite'] = dofile('lib/safewrite.lua');
package.loaded['dlac\\gear\\catalogindex'] = dofile('gear/catalogindex.lua');
package.loaded['dlac\\gear\\gearoracle'] = dofile('gear/gearoracle.lua');
package.loaded['dlac\\lib\\statefile'] = dofile('lib/statefile.lua');
package.loaded['dlac\\feature\\wishlist'] = dofile('feature/wishlist.lua');
package.loaded['dlac\\gear\\arbiter'] = dofile('gear/arbiter.lua');
local sp = dofile('gear/serverpack.lua');
sp._require = function(name)
    local rel = tostring(name):match('^dlac\\servers\\(.+)$');
    if rel == nil or rel:find('\\data\\', 1, true) ~= nil then error('headless: ' .. tostring(name)); end
    return dofile('servers/' .. (rel:gsub('\\', '/')) .. '.lua');
end;
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
package.loaded['dlac\\gear\\serverpack'] = sp;

local TEST_PLAYER = { MainJob = 'THF', MainJobLevel = 75, SubJob = 'DNC', SubJobLevel = 37,
                      MainJobSync = 75, SubJobSync = 37, Status = 'Engaged', IsMoving = false };
gData = { GetPlayer = function() return TEST_PLAYER; end };
AshitaCore = nil;

local dispatchM = dofile('dispatch.lua');
package.loaded['dlac\\dispatch'] = dispatchM;

local pass, fail = 0, 0;
local function check(name, got, want)
    if got == want then pass = pass + 1; return; end
    fail = fail + 1;
    print(('FAIL %s: got %s, want %s'):format(name, tostring(got), tostring(want)));
end

local RING = "dlac:AutoAcc:2:7:Toreador's Ring|Rajas Ring";
local NECK = 'dlac:AutoAcc:5:10:Peacock Amulet|Spike Necklace';

-- AAD-01: without a service the dormant foundation answers as always.
dispatchM._accReset();
dispatchM._accStateOverride = nil;
local pick, meta = dispatchM._accResolveSet({ Ring1 = RING });
check('AAD-01 no service: the piece is worn', pick and pick.Ring1, "Toreador's Ring");
check('AAD-01 and no candidate travels', meta, nil);
check('AAD-01 the revision leg is empty', dispatchM._autoAccRev(), '');

-- AAD-20 (v176): not engaged, the dormant path wears each armour slot's
-- fallback; weapon slots, other events, an engaged or unreadable player
-- keep the pieces on.
local KRIS = 'dlac:AutoAcc:1:5:Kris|Iron Sword';
local idleCtx = { event = 'Default', player = { Status = 'Idle' } };
pick = dispatchM._accResolveSet({ Ring1 = RING, Main = KRIS }, idleCtx);
check('AAD-20 not engaged: the fallback', pick.Ring1, 'Rajas Ring');
check('AAD-20 a weapon stays', pick.Main, 'Kris');
check('AAD-20 resting is not engaged either',
    dispatchM._accResolveSet({ Ring1 = RING }, { event = 'Default', player = { Status = 'Resting' } }).Ring1, 'Rajas Ring');
check('AAD-20 engaged: the piece',
    dispatchM._accResolveSet({ Ring1 = RING }, { event = 'Default', player = { Status = 'Engaged' } }).Ring1, "Toreador's Ring");
check('AAD-20 an unreadable status: the piece',
    dispatchM._accResolveSet({ Ring1 = RING }, { event = 'Default', player = {} }).Ring1, "Toreador's Ring");
check('AAD-20 a ranged shot is no standing set',
    dispatchM._accResolveSet({ Ring1 = RING }, { event = 'Midshot', player = { Status = 'Idle' } }).Ring1, "Toreador's Ring");
check('AAD-20 no fallback: the piece',
    dispatchM._accResolveSet({ Ring1 = "dlac:AutoAcc:2:7:Toreador's Ring" }, idleCtx).Ring1, "Toreador's Ring");

-- The fake provider records what the send asks.
local asked, answer = nil, nil;
local svc = {
    decide = function(req) asked = req; return answer or { release = {}, why = {} }; end,
    revision = function() return 'r7'; end,
};
sp.provide('autoacc', svc);

-- AAD-02: with the service every typed piece is planned on, and the
-- candidate carries its typed piece, fallback and removal priority.
pick, meta = dispatchM._accResolveSet({ Ring1 = RING, Neck = NECK, Body = 'Scorpion Harness' });
check('AAD-02 the ring stays on', pick.Ring1, "Toreador's Ring");
check('AAD-02 the neck stays on', pick.Neck, 'Peacock Amulet');
check('AAD-02 candidate typed', meta.Ring1.typed, "Toreador's Ring");
check('AAD-02 candidate fallback', meta.Ring1.fallback, 'Rajas Ring');
check('AAD-02 candidate priority', meta.Neck.prio, 5);
check('AAD-02 a plain slot is no candidate', meta.Body, nil);
check('AAD-02 the revision leg is the provider\'s', dispatchM._autoAccRev(), 'r7');

-- AAD-03: equipResolved carries candidates beside the plan; the slot's last
-- writer decides.
local ctx = { event = 'Default', planOut = {}, planAcc = {} };
dispatchM._equipResolved({ Ring1 = RING, Neck = NECK, Body = 'Scorpion Harness' }, ctx, true, 'test');
check('AAD-03 planned on', ctx.planOut.Ring1, "Toreador's Ring");
check('AAD-03 the candidate rides the plan', ctx.planAcc.Ring1 ~= nil, true);
dispatchM._equipResolved({ Ring1 = 'Sniper\'s Ring' }, ctx, true, 'a higher claim');
check('AAD-03 a later writer of the slot drops it', ctx.planAcc.Ring1, nil);
check('AAD-03 other candidates stay', ctx.planAcc.Neck ~= nil, true);
dispatchM._equipResolved({ Ring2 = 'Brass Ring' }, ctx, true, 'another slot');
check('AAD-03 writing another slot keeps them', ctx.planAcc.Neck ~= nil, true);

-- AAD-04: the send asks once, with the composed plan, and a release leaves
-- with the fallback.
answer = { release = { Neck = 'Spike Necklace' }, why = { Neck = 'released for Spike Necklace' } };
local res = dispatchM._autoAccApply('Default', ctx);
check('AAD-04 the service was asked', asked ~= nil, true);
check('AAD-04 with the event', asked.event, 'Default');
check('AAD-04 with the composed plan', asked.plan.Ring1, "Sniper's Ring");
check('AAD-04 one candidate', #asked.candidates, 1);
check('AAD-04 the candidate', asked.candidates[1].slot, 'Neck');
check('AAD-04 the fallback is sent', ctx.planOut.Neck, 'Spike Necklace');
check('AAD-04 the answer comes back', res, answer);
local lines = {};
dispatchM._autoAccLines(res, lines);
check('AAD-04 one trace line', lines[1], 'AutoAcc: Neck: released for Spike Necklace');

-- AAD-05: Free equip and locks keep their slots out of the question.
ctx = { event = 'Default', planOut = {}, planAcc = {} };
dispatchM._equipResolved({ Ring1 = RING, Neck = NECK }, ctx, true, 'test');
dispatchM.disabledSlots['neck'] = true;
asked = nil; answer = nil;
dispatchM._autoAccApply('Default', ctx);
check('AAD-05 a Free-equip slot is not offered', asked and #asked.candidates, 1);
check('AAD-05 the offered one', asked and asked.candidates[1].slot, 'Ring1');
check('AAD-05 nor named in the plan', asked and asked.plan.Neck, nil);
dispatchM.disabledSlots['neck'] = nil;
dispatchM.locks['ring1'] = true;
ctx = { event = 'Default', planOut = {}, planAcc = {} };
dispatchM._equipResolved({ Ring1 = RING }, ctx, true, 'test');
check('AAD-05 a locked slot carries no candidate', ctx.planAcc.Ring1, nil);
dispatchM.locks['ring1'] = nil;

-- AAD-06: a release never lands on a slot that no longer holds the piece.
ctx = { event = 'Default', planOut = {}, planAcc = {} };
dispatchM._equipResolved({ Ring1 = RING }, ctx, true, 'test');
answer = { release = { Ring1 = 'Rajas Ring', Neck = 'Spike Necklace' }, why = {} };
dispatchM._autoAccApply('Default', ctx);
check('AAD-06 the released ring', ctx.planOut.Ring1, 'Rajas Ring');
check('AAD-06 nothing invented for another slot', ctx.planOut.Neck, nil);

-- AAD-07: no candidates: the service is not asked at all.
ctx = { event = 'Default', planOut = { Body = 'Scorpion Harness' }, planAcc = {} };
asked = nil;
check('AAD-07 nothing to decide', dispatchM._autoAccApply('Default', ctx), nil);
check('AAD-07 not asked', asked, nil);

-- AAD-10: a slot locked after the plan was made is not offered either (the
-- send checks the locks again, whatever the plan carried).
ctx = { event = 'Default', planOut = { Ring1 = "Toreador's Ring" },
        planAcc = { Ring1 = { typed = "Toreador's Ring", fallback = 'Rajas Ring', prio = 2 } } };
dispatchM.locks['ring1'] = true;
asked = nil;
check('AAD-10 a locked slot: nothing to decide', dispatchM._autoAccApply('Default', ctx), nil);
check('AAD-10 the service is not asked', asked, nil);
check('AAD-10 and the piece stays', ctx.planOut.Ring1, "Toreador's Ring");
dispatchM.locks['ring1'] = nil;

-- AAD-11: v173, the Set Type at a weapon skill. A set's name rides its
-- candidates; the send asks each one's Set Type, and says whether the skill
-- is a ranged one.
local savedSets = dispatchM._nativeSets;
dispatchM._nativeSets = { ['WS Savage'] = { Ring1 = RING }, ['TP'] = { Neck = NECK } };
ctx = { event = 'Weaponskill', planOut = {}, planAcc = {}, player = TEST_PLAYER,
        action = { Name = 'Savage Blade', Id = 42 } };
dispatchM._equipSetByName('TP', ctx);
dispatchM._equipSetByName('WS Savage', ctx);
check('AAD-11 the candidate names its set', ctx.planAcc.Ring1 and ctx.planAcc.Ring1.set, 'WS Savage');
check('AAD-11 each its own', ctx.planAcc.Neck and ctx.planAcc.Neck.set, 'TP');
check('AAD-11 the name leaves ctx with the set', ctx.setName, nil);
local savedTypeOf = dispatchM._setTypeOf;
local typeAsked = {};
dispatchM._setTypeOf = function(set, c)
    typeAsked[#typeAsked + 1] = tostring(set) .. '@' .. tostring(c.player.MainJob);
    return (set == 'WS Savage') and 'ws1' or 'normal';
end;
asked, answer = nil, nil;
dispatchM._autoAccApply('Weaponskill', ctx);
local bySlot = {};
for _, c in ipairs(asked and asked.candidates or {}) do bySlot[c.slot] = c; end
check('AAD-11 the 1-Hit WS set\'s candidate', bySlot.Ring1 and bySlot.Ring1.setType, 'ws1');
check('AAD-11 the Normal set\'s', bySlot.Neck and bySlot.Neck.setType, 'normal');
table.sort(typeAsked);
check('AAD-11 asked by set name and main job', table.concat(typeAsked, ','), 'TP@THF,WS Savage@THF');
check('AAD-11 a melee weapon skill', asked and asked.rangedWs, false);
ctx.action = { Name = 'Sidewinder', Id = 196 };
dispatchM._autoAccApply('Weaponskill', ctx);
check('AAD-11 a ranged one is said', asked.rangedWs, true);
ctx.action = { Name = 'Leaden Salute', Id = 218 };
dispatchM._autoAccApply('Weaponskill', ctx);
check('AAD-11 a magical ranged one too', asked.rangedWs, true);
typeAsked = {};
dispatchM._autoAccApply('Default', ctx);
check('AAD-11 the standing set asks no Set Type', #typeAsked, 0);
check('AAD-11 and sends none', asked.candidates[1].setType, nil);
check('AAD-11 nor a ranged flag', asked.rangedWs, nil);
dispatchM._setTypeOf = savedTypeOf;
dispatchM._nativeSets = savedSets;
-- The real reader: gearoptim's store, asked with the main job; 'normal'
-- when there is no set name or no store.
check('AAD-11 no set name', dispatchM._setTypeOf(nil, ctx), 'normal');
check('AAD-11 no store', dispatchM._setTypeOf('WS Savage', ctx), 'normal');
package.loaded['dlac\\gear\\gearoptim'] = { setTypeOf = function(job, set) return job .. '|' .. set; end };
check('AAD-11 the store is asked', dispatchM._setTypeOf('WS Savage', ctx), 'THF|WS Savage');
package.loaded['dlac\\gear\\gearoptim'] = nil;

-- AAD-21 (v176): with the provider the candidates still travel when not
-- engaged, and the send tells it so (req.idle); engaged or unreadable, not.
ctx = { event = 'Default', planOut = {}, planAcc = {}, player = { Status = 'Idle' } };
dispatchM._equipResolved({ Ring1 = RING }, ctx, true, 'test');
check('AAD-21 the candidate travels', ctx.planAcc.Ring1 ~= nil, true);
asked, answer = nil, nil;
dispatchM._autoAccApply('Default', ctx);
check('AAD-21 not engaged is said', asked and asked.idle, true);
ctx.player.Status = 'Engaged';
dispatchM._autoAccApply('Default', ctx);
check('AAD-21 engaged is not', asked.idle, nil);
ctx.player = nil;
dispatchM._autoAccApply('Default', ctx);
check('AAD-21 nor is an unread player', asked.idle, nil);

-- AAD-22 (v176): a Midshot send carries the ranged switch and the shot's own
-- target; the standing set carries neither.
local savedRules = dispatchM._accRulesMod;
local RULES = { triggerRules = true, conditional = true, levelRange = false, rangedAttacks = true };
local rulesRev = 1;
dispatchM._accRulesMod = { get = function(k) return RULES[k]; end, rev = function() return rulesRev; end };
gData.GetActionTarget = function() return { Id = 0x010680A5, Index = 165 }; end;
ctx = { event = 'Midshot', planOut = {}, planAcc = {}, player = { Status = 'Idle' } };
dispatchM._equipResolved({ Ring1 = RING }, ctx, true, 'test');
asked = nil;
dispatchM._autoAccApply('Midshot', ctx);
check('AAD-22 a shot asks the provider', asked and asked.event, 'Midshot');
check('AAD-22 with the ranged switch', asked.allowRanged, true);
check('AAD-22 and the shot\'s target', asked.targetId, 0x010680A5);
check('AAD-22 a shot while not engaged is no idle standing set', asked.idle, nil);
RULES.rangedAttacks = false;
dispatchM._autoAccApply('Midshot', ctx);
check('AAD-22 the switch off is said', asked.allowRanged, false);
RULES.rangedAttacks = true;
ctx.event = 'Default';
dispatchM._autoAccApply('Default', ctx);
check('AAD-22 the standing set: no switch', asked.allowRanged, nil);
check('AAD-22 and no target', asked.targetId, nil);
gData.GetActionTarget = nil;
ctx.event = 'Weaponskill';
dispatchM._autoAccApply('Weaponskill', ctx);
check('AAD-22 no action target read: none sent', asked.targetId, nil);
check('AAD-22 the settings revision', dispatchM._accRulesRev(), '1');

-- AAD-23 (v176): "Trigger rules override AutoAcc" off. In the Trigger rules'
-- pass a later rule's piece becomes the AutoAcc piece's fallback; a claim
-- (after the pass) still replaces it; on, the rule's piece replaces it.
RULES.triggerRules = false;
ctx = { event = 'Default', planOut = {}, planAcc = {}, player = { Status = 'Engaged' }, floorPass = true };
dispatchM._equipResolved({ Ring1 = RING, Neck = NECK }, ctx, true, 'the TP set');
local SNIPER = { Name = "Sniper's Ring", AugKey = 'acc+3' };
dispatchM._equipResolved({ Ring1 = SNIPER }, ctx, true, 'a later rule');
check('AAD-23 the AutoAcc piece keeps the slot', ctx.planOut.Ring1, "Toreador's Ring");
check('AAD-23 the rule\'s piece is its fallback', ctx.planAcc.Ring1 and ctx.planAcc.Ring1.fallback, "Sniper's Ring");
answer = { release = { Ring1 = "Sniper's Ring" }, why = { Ring1 = "released for Sniper's Ring" } };
asked = nil;
dispatchM._autoAccApply('Default', ctx);
local offered = nil;
for _, c in ipairs(asked and asked.candidates or {}) do if c.slot == 'Ring1' then offered = c.fallback; end end
check('AAD-23 the provider is offered the rule\'s piece', offered, "Sniper's Ring");
check('AAD-23 a release wears it as the rule wrote it', ctx.planOut.Ring1, SNIPER);
ctx = { event = 'Default', planOut = {}, planAcc = {}, player = { Status = 'Engaged' }, floorPass = true };
dispatchM._equipResolved({ Ring1 = RING }, ctx, true, 'the TP set');
ctx.floorPass = nil;
dispatchM._equipResolved({ Ring1 = "Sniper's Ring" }, ctx, true, 'a claim');
check('AAD-23 a claim still replaces it', ctx.planOut.Ring1, "Sniper's Ring");
check('AAD-23 and drops the candidate', ctx.planAcc.Ring1, nil);
RULES.triggerRules = true;
ctx = { event = 'Default', planOut = {}, planAcc = {}, player = { Status = 'Engaged' }, floorPass = true };
dispatchM._equipResolved({ Ring1 = RING }, ctx, true, 'the TP set');
dispatchM._equipResolved({ Ring1 = "Sniper's Ring" }, ctx, true, 'a later rule');
check('AAD-23 on: the rule\'s piece replaces it', ctx.planOut.Ring1, "Sniper's Ring");
check('AAD-23 on: no candidate left', ctx.planAcc.Ring1, nil);
RULES.triggerRules = false;
ctx = { event = 'Default', planOut = {}, planAcc = {}, player = { Status = 'Engaged' }, floorPass = true };
dispatchM._equipResolved({ Ring1 = RING }, ctx, true, 'the TP set');
dispatchM._equipResolved({ Ring1 = "Toreador's Ring" }, ctx, true, 'a rule naming the piece itself');
check('AAD-23 a rule wearing the piece itself makes it plain', ctx.planAcc.Ring1, nil);
ctx = { event = 'Default', planOut = {}, planAcc = {}, player = { Status = 'Engaged' }, floorPass = true };
dispatchM._equipResolved({ Ring1 = "Sniper's Ring" }, ctx, true, 'an earlier rule');
dispatchM._equipResolved({ Ring1 = RING }, ctx, true, 'a later AutoAcc set');
check('AAD-23 a later AutoAcc piece is the last writer as ever', ctx.planOut.Ring1, "Toreador's Ring");
check('AAD-23 with its own fallback', ctx.planAcc.Ring1 and ctx.planAcc.Ring1.fallback, 'Rajas Ring');
RULES.triggerRules = true;
dispatchM._accRulesMod = savedRules;

-- AAD-24 (v176): without the settings module every switch answers its default.
dispatchM._accRulesMod = false;
check('AAD-24 trigger rules override by default', dispatchM._accRule('triggerRules'), true);
check('AAD-24 ranged shots on by default', dispatchM._accRule('rangedAttacks'), true);
check('AAD-24 level ranges do not', dispatchM._accRule('levelRange'), false);
check('AAD-24 no revision', dispatchM._accRulesRev(), '');
dispatchM._accRulesMod = savedRules;

-- AAD-08: the wiring at the one send and the retrace leg (source pins).
local f = assert(io.open('dispatch.lua', 'rb')); local src = f:read('*a'); f:close();
local applyAt = src:find('local accOut = M._autoAccApply(event, ctx);', 1, true);
local sendAt = src:find('if next(ctx.planOut) ~= nil then engineEquipSet(ctx.planOut); end', 1, true);
check('AAD-08 the send asks first', applyAt ~= nil and sendAt ~= nil and applyAt < sendAt, true);
check('AAD-08 the plan snapshot is taken before the release',
    src:find('local planSnap = planNames(ctx.planOut);', 1, true) < applyAt, true);
check('AAD-08 the newest retrace leg', src:find("'|aa' .. M._autoAccRev()", 1, true) ~= nil, true);
check('AAD-08 the collector is born with the plan', src:find('ctx.planAcc = {};', 1, true) ~= nil, true);
-- v176: the settings and the engaged state are retrace legs, and the Trigger
-- rules' pass is marked around the rule loop only.
check('AAD-08 the settings leg', src:find("'|ar' .. M._accRulesRev() .. '|ae' .. (M._accNotEngaged(ctx) and '1' or '0')", 1, true) ~= nil, true);
local passOn = src:find('ctx.floorPass = true;\n        for hi, r in ipairs(hits) do', 1, true)
    or src:find('ctx.floorPass = true;\r\n        for hi, r in ipairs(hits) do', 1, true);
local passOff = src:find('ctx.floorPass = nil;', 1, true);
local claimsAt = src:find('local plan = ARB.arbitrate({ order = arbOrder, claims = claims });', 1, true);
check('AAD-08 the rules\' pass opens at the rule loop', passOn ~= nil, true);
check('AAD-08 and closes before the claims apply', passOff ~= nil and claimsAt ~= nil and passOn < passOff and passOff < claimsAt, true);

-- AAD-09: a real Default dispatch with the provider present still runs.
local savedEng = package.loaded['dlac\\feature\\equipengine'];
local wrote = {};
package.loaded['dlac\\feature\\equipengine'] = {
    nativeOn = function() return true; end,
    equipSet = function(t) for k, v in pairs(t or {}) do wrote[k] = v; end end,
    state = { tripped = false },
};
_G.gState = { CurrentCall = 'N/A', Disabled = {} };
dispatchM.nakedArmed = true;
local ok, err = pcall(dispatchM.dispatch, 'Default');
check('AAD-09 the dispatch runs', ok, true);
if not ok then print('AAD-09: ' .. tostring(err)); end
check('AAD-09 and sends', wrote.Ring1, 'remove');
dispatchM.nakedArmed = false;
package.loaded['dlac\\feature\\equipengine'] = savedEng;

print(('ascensionxi_autoacc_dispatch: %d passed, %d failed'):format(pass, fail));
if fail > 0 then os.exit(1); end
