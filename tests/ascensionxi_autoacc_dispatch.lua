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

-- AAD-08: the wiring at the one send and the retrace leg (source pins).
local f = assert(io.open('dispatch.lua', 'rb')); local src = f:read('*a'); f:close();
local applyAt = src:find('local accOut = M._autoAccApply(event, ctx);', 1, true);
local sendAt = src:find('if next(ctx.planOut) ~= nil then engineEquipSet(ctx.planOut); end', 1, true);
check('AAD-08 the send asks first', applyAt ~= nil and sendAt ~= nil and applyAt < sendAt, true);
check('AAD-08 the plan snapshot is taken before the release',
    src:find('local planSnap = planNames(ctx.planOut);', 1, true) < applyAt, true);
check('AAD-08 the newest retrace leg', src:find("'|aa' .. M._autoAccRev()", 1, true) ~= nil, true);
check('AAD-08 the collector is born with the plan', src:find('ctx.planAcc = {};', 1, true) ~= nil, true);

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
