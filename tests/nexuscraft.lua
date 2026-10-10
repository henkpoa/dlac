-- Headless tests for the Nexus crafting-gear link: the recipe-wide pick
-- (feature/craftpick, NC*) and the conversation + lock (feature/nexuslink, NL*).
-- The engine's half (the Craft row reading the lock) is NX* in run_tests.lua.
-- Run from the addon root: lua tests/nexuscraft.lua
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
ashita = { events = { register = function() end } };

local pick = require('dlac\\feature\\craftpick');
local link = require('dlac\\feature\\nexuslink');

local count, failed = 0, 0;
local function check(name, got, want)
    count = count + 1;
    if got ~= want then
        failed = failed + 1;
        print(string.format('FAIL %s: got %s, want %s', name, tostring(got), tostring(want)));
    end
end

-- ---------------------------------------------------------------------------
-- Fixture gear: AscensionXI's real craft pieces (servers/ascensionxi catalog).
-- ---------------------------------------------------------------------------
local function item(name, slot, t)
    t = t or {};
    return { name = name, slot = slot, level = t.level or 1, n = t.n or 1, sk = t.sk or {},
             anti = t.anti or {}, sb = t.sb or {}, hqr = t.hqr or 0, succ = t.succ or 0,
             gain = t.gain or 0, mat = t.mat or 0, consv = t.consv or 0,
             twoHand = t.twoHand, shield = t.shield };
end
local ALL8 = function(n)
    local t = {};
    for _, c in ipairs(pick.CRAFTS) do t[c] = n; end
    return t;
end
local GEAR = {
    item('Artisan\'s Apron', 'body', { sk = ALL8(2) }),
    item('Blksmith. Smock', 'body', { sk = { Smithing = 1 } }),
    item('Carpenter\'s Apron', 'body', { sk = { Woodworking = 1 } }),
    item('Smithy\'s Torque', 'neck', { sk = { Smithing = 2 } }),
    item('Carver\'s Torque', 'neck', { sk = { Woodworking = 2 } }),
    item('Smithy\'s Mitts', 'hands', { sk = { Smithing = 1 } }),
    item('Carpenter\'s Gloves', 'hands', { sk = { Woodworking = 1 } }),
    item('Kupo Shield', 'sub', { sk = ALL8(1) }),
    item('Craftmaster\'s Ring', 'ring', { hqr = 1 }),
    item('Artificer\'s Ring', 'ring', { succ = 1 }),
    item('Craftkeeper\'s Ring', 'ring', { mat = 1 }),
    item('Smith\'s Ring', 'ring', { anti = { Smithing = 1 }, sb = { Smithing = 1 } }),
    item('Shaper\'s Shawl', 'back', { gain = 25 }),
    item('Orvail Ring', 'ring', { level = 99, hqr = 1, mat = 1, gain = 5, succ = 1 }),
};

-- NC1 one craft: every slot takes its best piece for that craft.
local p, info = pick.pick(GEAR, { Smithing = 30 }, { Smithing = 30 }, { goal = 'hq', level = 75 });
check('NC1 body: the all-craft apron (+2) beats the smock (+1)', p.Body, 'Artisan\'s Apron');
check('NC1b neck: the smithing torque', p.Neck, 'Smithy\'s Torque');
check('NC1c hands: the smithing mitts', p.Hands, 'Smithy\'s Mitts');
check('NC1d sub: the Kupo Shield', p.Sub, 'Kupo Shield');
check('NC1e margin counts every piece (+2 +2 +1 +1)', info.margins.Smithing, 6);
check('NC1f hq: Synth HQ ring first', p.Ring1, 'Craftmaster\'s Ring');
check('NC1g hq: then success', p.Ring2, 'Artificer\'s Ring');
check('NC1h hq: skill-up cape fills the back', p.Back, 'Shaper\'s Shawl');
check('NC1i a Lv99 ring is not worn at 75', p.Ring1 ~= 'Orvail Ring' and p.Ring2 ~= 'Orvail Ring', true);
check('NC1j ammo is never touched', p.Ammo, nil);
check('NC1k beaten pieces are never tried (smock under the apron): one combination', info.combos, 1);

-- NC2 weakest first: Smithing is 5 under, Woodworking 20 over -> every
-- one-craft slot goes to Smithing.
p, info = pick.pick(GEAR, { Smithing = 30, Woodworking = 40 }, { Smithing = 25, Woodworking = 60 },
    { goal = 'hq', level = 75 });
check('NC2 neck goes to the weakest craft', p.Neck, 'Smithy\'s Torque');
check('NC2b hands too', p.Hands, 'Smithy\'s Mitts');
check('NC2c weakest is Smithing', info.weakest, 'Smithing');
check('NC2d Smithing margin: -5 +2 +2 +1 +1', info.margins.Smithing, 1);

-- NC3 once the weakest catches up, the pieces split.
p, info = pick.pick(GEAR, { Smithing = 30, Woodworking = 30 }, { Smithing = 29, Woodworking = 30 },
    { goal = 'hq', level = 75 });
-- Base -1 / 0; apron +2 and shield +1 both; torques +2 to one, mitts/gloves +1
-- to one. Best floor: Smithing torque (+2) and Woodworking gloves (+1): 4 / 4.
check('NC3 the weakest gets the torque', p.Neck, 'Smithy\'s Torque');
check('NC3b the other craft gets the hands slot', p.Hands, 'Carpenter\'s Gloves');
check('NC3c both end level', info.margins.Smithing .. '/' .. info.margins.Woodworking, '4/4');

-- NC4 every combination is tried, not one slot at a time: slot A offers +2 to
-- X or +1/+1, slot B only +2 to X. Filling X first in A would strand Y.
local TRAP = {
    item('X Hat', 'head', { sk = { Smithing = 2 } }),
    item('XY Hat', 'head', { sk = { Smithing = 1, Woodworking = 1 } }),
    item('X Torque', 'neck', { sk = { Smithing = 2 } }),
};
p, info = pick.pick(TRAP, { Smithing = 10, Woodworking = 10 }, { Smithing = 10, Woodworking = 10 }, {});
check('NC4 the shared hat goes on so the other craft is not stranded', p.Head, 'XY Hat');
check('NC4b the torque still goes on', p.Neck, 'X Torque');
check('NC4c floor 1 instead of 0', info.margins.Woodworking, 1);

-- NC5 the greedy fallback (too many combinations) still raises the weakest.
local savedLimit = pick.COMBO_LIMIT;
pick.COMBO_LIMIT = 0;
p, info = pick.pick(GEAR, { Smithing = 30, Woodworking = 40 }, { Smithing = 25, Woodworking = 60 },
    { goal = 'hq', level = 75 });
check('NC5 greedy marks itself', info.greedy, true);
check('NC5b greedy gives the weakest the torque', p.Neck, 'Smithy\'s Torque');
check('NC5c greedy floor matches the full search here', info.margins.Smithing, 1);
pick.COMBO_LIMIT = savedLimit;

-- NC6 goals for the free slots.
p = pick.pick(GEAR, { Smithing = 30 }, { Smithing = 30 }, { goal = 'nq', level = 75 });
check('NC6 nq: the HQ-blocking ring for the recipe\'s craft', p.Ring1, 'Smith\'s Ring');
p = pick.pick(GEAR, { Smithing = 30 }, { Smithing = 30 }, { goal = 'hq', level = 75 });
check('NC6b hq: never the HQ-blocking ring', p.Ring1 ~= 'Smith\'s Ring' and p.Ring2 ~= 'Smith\'s Ring', true);
p = pick.pick(GEAR, { Woodworking = 30 }, { Woodworking = 30 }, { goal = 'nq', level = 75 });
check('NC6c nq: a ring that blocks another craft does nothing here', p.Ring1 ~= 'Smith\'s Ring', true);
p = pick.pick({ item('Smith\'s Ring', 'ring', { anti = { Smithing = 1 }, sb = { Smithing = 1 } }) },
    { Smithing = 30 }, { Smithing = 30 }, { goal = 'hq' });
check('NC6f hq: an HQ-blocking ring is left off even when it is the only ring', p.Ring1, nil);
p = pick.pick({ item('Odd Smock', 'body', { sk = { Smithing = 3 }, anti = { Smithing = 1 } }),
                item('Plain Smock', 'body', { sk = { Smithing = 1 } }) },
    { Smithing = 30 }, { Smithing = 30 }, { goal = 'hq' });
check('NC6g hq: skill gear that blocks HQ loses to weaker gear that does not', p.Body, 'Plain Smock');
p = pick.pick(GEAR, { Smithing = 30 }, { Smithing = 30 }, { goal = 'skillup', level = 99 });
check('NC6d skillup at 99: the skill-up ring first', p.Ring1, 'Orvail Ring');
check('NC6e skillup: the skill-up cape', p.Back, 'Shaper\'s Shawl');

-- NC7 a ring owned once fills one ring slot; owned twice, both.
local RINGS = { item('Craftmaster\'s Ring', 'ring', { hqr = 1 }) };
p = pick.pick(RINGS, { Cooking = 5 }, {}, {});
check('NC7 one copy, one slot', (p.Ring1 ~= nil and 1 or 0) + (p.Ring2 ~= nil and 1 or 0), 1);
RINGS[1].n = 2;
p = pick.pick(RINGS, { Cooking = 5 }, {}, {});
check('NC7b two copies, both slots', p.Ring1 == 'Craftmaster\'s Ring' and p.Ring2 == 'Craftmaster\'s Ring', true);

-- NC8 skill rings (paired slots in the skill pass) respect copies too.
local SKR = { item('Smith Band', 'ring', { sk = { Smithing = 1 } }) };
p, info = pick.pick(SKR, { Smithing = 10 }, { Smithing = 10 }, {});
check('NC8 one copy of a skill ring counts once', info.margins.Smithing, 1);
SKR[1].n = 2;
p, info = pick.pick(SKR, { Smithing = 10 }, { Smithing = 10 }, {});
check('NC8b two copies count twice', info.margins.Smithing, 2);

-- NC9 edges.
p, info = pick.pick(GEAR, {}, {}, {});
check('NC9 no craft named: nothing picked', next(p), nil);
p, info = pick.pick(GEAR, { Smithing = 30 }, {}, { level = 75 });
check('NC9b an unreadable skill counts as at the recipe level', info.margins.Smithing, 6);
p = pick.pick({ item('Odd', 'pocket', { sk = { Smithing = 5 } }), { slot = 'neck' } }, { Smithing = 1 }, {}, {});
check('NC9c unknown slots and nameless rows are skipped', next(p), nil);
p = pick.pick(GEAR, { Bonecraft = 10 }, { Bonecraft = 10 }, { goal = 'hq', level = 75 });
check('NC9d a craft with only all-craft gear still gets it', p.Body, 'Artisan\'s Apron');
check('NC9e and a one-craft piece for another craft stays off', p.Neck, nil);

check('NC10 samePicks: same pieces, any case', pick.samePicks({ Body = 'A' }, { Body = 'a' }), true);
check('NC10b an extra slot differs', pick.samePicks({ Body = 'A' }, { Body = 'A', Neck = 'B' }), false);
check('NC10c a different piece differs', pick.samePicks({ Body = 'A' }, { Body = 'B' }), false);

-- NC11 the answer never depends on input order.
local rev = {};
for i = #GEAR, 1, -1 do rev[#rev + 1] = GEAR[i]; end
local a = pick.pick(GEAR, { Smithing = 30, Woodworking = 30 }, { Smithing = 29, Woodworking = 30 }, { level = 75 });
local b = pick.pick(rev, { Smithing = 30, Woodworking = 30 }, { Smithing = 29, Woodworking = 30 }, { level = 75 });
check('NC11 same picks whatever the row order', pick.samePicks(a, b), true);

-- NC12 the all-craft pieces (AscensionXI's catalog numbers): they count for
-- every craft a recipe needs, and the better of a line wins.
local UNI = {
    item('Kupo Shield', 'sub', { sk = ALL8(1), shield = true }),
    item('Kupo Shield +1', 'sub', { sk = ALL8(2), shield = true }),
    item('Kupo Shield +2', 'sub', { sk = ALL8(3), shield = true }),
    item('Chef\'s Ecu', 'sub', { sk = { Cooking = 1 }, shield = true }),
    item('Artisan\'s Hat', 'head', { sk = ALL8(2) }),
    item('Chef\'s Hat', 'head', { sk = { Cooking = 1 } }),
    item('Artisan\'s Torque', 'neck', { sk = ALL8(3) }),
    item('Culin. Torque', 'neck', { sk = { Cooking = 2 } }),
    item('Artisan\'s Apron', 'body', { sk = ALL8(2) }),
    item('Culinarian\'s Smock', 'body', { sk = { Cooking = 1 } }),
    item('Caduceus', 'main', { sk = { Alchemy = 1 }, twoHand = false }),
};
p, info = pick.pick(UNI, { Cooking = 30 }, { Cooking = 30 }, { level = 75 });
check('NC12 the Kupo Shield +2 beats +1, the plain one and the craft\'s own ecu', p.Sub, 'Kupo Shield +2');
check('NC12b Artisan\'s Hat (+2) beats Chef\'s Hat (+1)', p.Head, 'Artisan\'s Hat');
check('NC12c Artisan\'s Torque (+3) beats the craft torque (+2)', p.Neck, 'Artisan\'s Torque');
check('NC12d Artisan\'s Apron (+2) beats the craft smock (+1)', p.Body, 'Artisan\'s Apron');
check('NC12e +3 +2 +3 +2', info.margins.Cooking, 10);
check('NC12f no cooking weapon: the main hand is left to the engine', p.Main, nil);
check('NC12g beaten pieces are never tried: one combination', info.combos, 1);
p, info = pick.pick(UNI, { Cooking = 30, Alchemy = 20 }, { Cooking = 30, Alchemy = 15 }, { level = 75 });
check('NC12h a subcraft recipe: the all-craft pieces count for both crafts',
    info.margins.Cooking .. '/' .. info.margins.Alchemy, '10/6');
check('NC12i and the alchemy club joins the shield (one-handed)', p.Main, 'Caduceus');

-- NC13 the hands never fight.
local HANDS = {
    item('Kupo Shield +2', 'sub', { sk = ALL8(3), shield = true }),
    item('Smithing Scythe', 'main', { sk = { Smithing = 9 }, twoHand = true }),
    item('Smithing Grip', 'sub', { sk = { Smithing = 9 }, shield = false }),
    item('Smithing Hammer', 'main', { sk = { Smithing = 1 }, twoHand = false }),
};
p = pick.pick(HANDS, { Smithing = 30 }, { Smithing = 30 }, {});
check('NC13 a two-handed craft weapon is never worn, however good', p.Main, 'Smithing Hammer');
check('NC13b a Sub that is not a shield is never worn', p.Sub, 'Kupo Shield +2');
p = pick.pick({ item('Smithing Scythe', 'main', { sk = { Smithing = 9 }, twoHand = true }) },
    { Smithing = 30 }, { Smithing = 30 }, {});
check('NC13c even when it is the only piece', p.Main, nil);
p = pick.pick({ item('Old Row Shield', 'sub', { sk = { Smithing = 2 } }) }, { Smithing = 30 }, { Smithing = 30 }, {});
check('NC13d a row written before the hands facts is still worn', p.Sub, 'Old Row Shield');

-- ---------------------------------------------------------------------------
-- NL. The conversation and the lock.
-- ---------------------------------------------------------------------------
local sent = {};
link._raise = function(name, bytes)
    local s = {};
    for i, v in ipairs(bytes) do s[i] = string.char(v); end
    sent[#sent + 1] = { name = name, msg = link.parse(table.concat(s)) };
end
local W = {
    follow = true, goal = 'hq', level = 75, job = 'WAR', status = 'Idle',
    skills = { Smithing = 25, Woodworking = 60 },
    worn = {}, pos = { x = 0, y = 0, z = 0, zone = 230 }, items = GEAR,
};
link._io = {
    follow   = function() return W.follow; end,
    goal     = function() return W.goal; end,
    level    = function() return W.level; end,
    job      = function() return W.job; end,
    status   = function() return W.status; end,
    skill    = function(c) return W.skills[c]; end,
    items    = function() return W.items; end,
    wornName = function(slot) return W.worn[slot]; end,
    position = function() return W.pos; end,
};
local function last() return sent[#sent] and sent[#sent].msg or nil; end
local function deliver(text, name)
    local bytes = text;
    link._onEvent({ name = name or 'nexus_craft', data = bytes });
end
local function wearAll()
    local st = link.lockState();
    for k, v in pairs(st and st.nexus or {}) do W.worn[k] = v; end
end

-- NL1 parse/format.
local m = link.parse('op=next;seq=4;crafts=Smithing:30,Woodworking:40');
check('NL1 parse reads op', m and m.op, 'next');
check('NL1b parse reads seq', m and m.seq, '4');
check('NL1c no op, no message', link.parse('seq=4'), nil);
check('NL1d not a string, no message', link.parse(42), nil);
check('NL1e format: op first, then sorted keys', link.format({ seq = 2, op = 'ready', state = 'worn' }),
    'op=ready;seq=2;state=worn');
check('NL1f format strips separators from values', link.format({ op = 'x', a = 'b;c=d' }), 'op=x;a=bcd');
local req = link.crafts('Smithing:30,woodworking:40,Dancing:5,Cooking:0,Alchemy:999');
check('NL1g crafts: names any case', req.Woodworking, 40);
check('NL1h crafts: unknown crafts and out-of-range levels dropped',
    (req.Dancing == nil and req.Cooking == nil and req.Alchemy == nil), true);
check('NL1i craftsText in craft order', link.craftsText({ Woodworking = 40, Smithing = 30 }),
    'Woodworking 40 + Smithing 30');

-- NL2 the first beat says hello; a hello is answered.
link._pump(0);
check('NL2 first beat says hello', last() and last().op, 'hello');
check('NL2b on the dlac event', sent[#sent].name, 'dlac_craft');
check('NL2c with follow on', last().follow, '1');
local n0 = #sent;
link._pump(0.01);
check('NL2d only once', #sent, n0);
deliver('op=hello');
link._pump(0.02);
check('NL2e a Nexus hello is answered', last() and last().op, 'hello');
deliver('op=next;seq=1;crafts=Smithing:30', 'some_other_addon');
link._pump(0.03);
check('NL2f another event name is ignored', link.lockState(), nil);

-- NL3 next: pick, lock, wait for the gear, then answer worn.
deliver('op=next;seq=1;crafts=Smithing:30,Woodworking:40;recipe=7;result=9');
link._pump(1.0);
local st = link.lockState();
check('NL3 a lock exists', type(st), 'table');
check('NL3b it is the Craft row shape', st and st.enabled == true and st.craft == 'Nexus', true);
check('NL3c the weakest craft got the torque', st and st.nexus.Neck, 'Smithy\'s Torque');
local before = #sent;
link._pump(1.1);
check('NL3d nothing answered while the gear is not on', #sent, before);
wearAll();
link._pump(1.2);
check('NL3e ready once worn', last() and last().op, 'ready');
check('NL3f for that synth', last().seq, '1');
check('NL3g state worn', last().state, 'worn');

-- NL4 the same pieces again (a new Nexus run): answered at once, lock kept.
deliver('op=next;seq=2;crafts=Smithing:30,Woodworking:40');
link._pump(60);
check('NL4 same recipe again: ready the same beat', last() and last().seq, '2');
check('NL4b worn', last().state, 'worn');
check('NL4c the lock table is the same one (no re-dress)', link.lockState(), st);
-- A different recipe with the same picks keeps the lock too.
deliver('op=next;seq=3;crafts=Smithing:31,Woodworking:41');
link._pump(61);
check('NL4d another recipe, same pieces: lock kept', link.lockState(), st);
check('NL4e and answered at once', last() and last().seq, '3');

-- NL5 different pieces: a new lock, a new wait.
W.worn = {};
deliver('op=next;seq=4;crafts=Cooking:10');
link._pump(70);
local st2 = link.lockState();
check('NL5 new pieces: a new lock', st2 ~= st and st2 ~= nil, true);
check('NL5b the cooking recipe keeps the all-craft apron', st2 and st2.nexus.Body, 'Artisan\'s Apron');
check('NL5c the smithing torque is gone', st2 and st2.nexus.Neck, nil);
before = #sent;
link._pump(71);
check('NL5d waiting', #sent, before);

-- NL6 a piece that never goes on: partial after CONFIRM_S, then at once.
W.worn = { Body = 'Artisan\'s Apron' };   -- the shield never lands (a Lock, say)
link._pump(70 + link.CONFIRM_S + 0.01);
check('NL6 partial after the wait', last() and last().state, 'partial');
check('NL6b for seq 4', last().seq, '4');
deliver('op=next;seq=5;crafts=Cooking:10');
link._pump(80);
check('NL6c settled lock: answered the same beat', last() and last().seq, '5');
check('NL6d still partial, no second wait', last().state, 'partial');

-- NL7 the lock ends when the player moves, and not on a small wobble.
W.pos = { x = 0.3, y = 0, z = 0, zone = 230 };
link._pump(81);
check('NL7 a 0.3 yalm wobble keeps the lock', link.lockState() ~= nil, true);
W.pos = { x = 1.0, y = 0, z = 0, zone = 230 };
link._pump(82);
check('NL7b a step ends it', link.lockState(), nil);
check('NL7c status says why', link.statusText():find('moved', 1, true) ~= nil, true);

-- NL8 zoning, engaging, dying and a job change end it too.
local function relock(seq, t)
    W.pos = { x = 0, y = 0, z = 0, zone = 230 };
    W.status, W.job = 'Idle', 'WAR';
    deliver('op=next;seq=' .. seq .. ';crafts=Smithing:30');
    link._pump(t);
    wearAll();
    link._pump(t + 0.5);
end
relock(10, 100);
check('NL8 relocked', link.lockState() ~= nil, true);
W.pos = { x = 0, y = 0, z = 0, zone = 231 };
link._pump(101);
check('NL8b zoning ends it', link.lockState(), nil);
relock(11, 110);
W.status = 'Engaged';
link._pump(111);
check('NL8c engaging ends it', link.lockState(), nil);
relock(12, 120);
W.status = 'Dead';
link._pump(121);
check('NL8d dying ends it', link.lockState(), nil);
relock(13, 130);
W.job = 'MNK';
link._pump(131);
check('NL8e a job change ends it', link.lockState(), nil);
relock(14, 140);
W.pos = nil;
link._pump(141);
check('NL8f an unreadable position (zoning) decides nothing yet', link.lockState() ~= nil, true);
W.pos = { x = 0, y = 0, z = 0, zone = 230 };

-- NL9 follow off: answered off, lock ended.
W.follow = false;
deliver('op=next;seq=20;crafts=Smithing:30');
link._pump(150);
check('NL9 follow off answers off', last() and last().state, 'off');
check('NL9b and ends the lock', link.lockState(), nil);
W.follow = true;

-- NL10 no gear for the recipe: none, lock ended.
W.items = {};
deliver('op=next;seq=21;crafts=Smithing:30');
link._pump(160);
check('NL10 no gear: none', last() and last().state, 'none');
check('NL10b no lock', link.lockState(), nil);
W.items = GEAR;
deliver('op=next;seq=22;crafts=Dancing:30');
link._pump(161);
check('NL10c no known craft: none', last() and last().state, 'none');

-- NL11 a newer synth replaces an unanswered one; a clear answers the waiting one.
W.worn = {};
deliver('op=next;seq=30;crafts=Woodworking:40');
link._pump(170);
deliver('op=next;seq=31;crafts=Woodworking:40');
link._pump(170.1);
local cleared30 = false;
for _, s in ipairs(sent) do
    if s.msg and s.msg.op == 'ready' and s.msg.seq == '30' and s.msg.state == 'cleared' then cleared30 = true; end
end
check('NL11 the older wait is answered cleared', cleared30, true);
link.clear('test');
check('NL11b clearing answers the waiting synth', last() and last().seq .. ':' .. last().state, '31:cleared');

-- NL12 the inbox holds INBOX_MAX messages between beats; the rest are dropped.
for i = 1, link.INBOX_MAX + 5 do deliver('op=hello'); end
check('NL12 the inbox is capped', #link._inbox, link.INBOX_MAX);
link._pump(180);
check('NL12b and drained by the beat', #link._inbox, 0);

-- NL13 status text.
link.clear('test');
link._lastNote = nil;
check('NL13 no lock yet', link.statusText(), 'no recipe from Nexus yet');
W.worn = {};
deliver('op=next;seq=40;crafts=Smithing:30,Woodworking:40');
link._pump(190);
check('NL13b a lock names its crafts (in craft order) and the weakest',
    link.statusText(), '7 pieces locked for Woodworking 40 + Smithing 30, weakest Smithing +1, until you move');
link.clear('test');

-- ---------------------------------------------------------------------------
-- NL14-NL22. The preview: what `next` would wear, as the change from what is
-- worn now, without equipping or locking anything.
-- ---------------------------------------------------------------------------
-- "Smithing:2,Woodworking:-1" -> { Smithing = 2, Woodworking = -1 }
local function deltas(text)
    local t = {};
    for c, n in tostring(text or ''):gmatch('([%a]+):(%-?%d+)') do t[c] = tonumber(n); end
    return t;
end
local function preview(seq, crafts, t)
    deliver('op=preview;seq=' .. seq .. ';crafts=' .. crafts .. ';recipe=1;result=2;desynth=0');
    link._pump(t);
    for i = #sent, 1, -1 do
        local m = sent[i].msg;
        if m and m.op == 'gear' then return m; end
    end
    return nil;
end
local function sortedPieces(text)
    local t = {};
    for name in tostring(text or ''):gmatch('[^|]+') do t[#t + 1] = name; end
    table.sort(t);
    return table.concat(t, '|');
end
link.clear('test');
W.follow, W.goal, W.items, W.worn = true, 'hq', GEAR, {};
W.skills = { Smithing = 25, Woodworking = 60 };

-- NL14 dlac's hello says it answers previews.
deliver('op=hello');
link._pump(300);
check('NL14 hello carries preview=1', last() and last().preview, '1');

-- NL15 a preview equips nothing, locks nothing and never answers ready.
local n15 = #sent;
local g = preview(50, 'Smithing:30', 301);
check('NL15 answered with gear', g and g.op, 'gear');
check('NL15b seq echoed', g and g.seq, '50');
check('NL15c answered in the same beat', #sent, n15 + 1);
check('NL15d no lock', link.lockState(), nil);
check('NL15e nothing waits', link._pending, nil);
deliver('op=next;seq=51;crafts=Cooking:10');
link._pump(302);
local st15 = link.lockState();
g = preview(52, 'Smithing:30', 302.1);
check('NL15f a preview leaves a standing lock alone', link.lockState(), st15);
check('NL15g and the synth waiting for it', link._pending and link._pending.seq, 51);
local readies = 0;
for i = n15 + 1, #sent do
    local m = sent[i].msg;
    if m and m.op == 'ready' then readies = readies + 1; end
end
check('NL15h no preview was answered ready', readies, 0);
link.clear('test');

-- NL16 the preview names exactly the pieces next would lock.
W.worn = {};
g = preview(53, 'Smithing:30,Woodworking:40', 303);
deliver('op=next;seq=54;crafts=Smithing:30,Woodworking:40');
link._pump(304);
local locked = {};
for _, name in pairs(link.lockState() and link.lockState().nexus or {}) do locked[#locked + 1] = name; end
table.sort(locked);
check('NL16 preview pieces = next picks', sortedPieces(g and g.pieces), table.concat(locked, '|'));
check('NL16b state pick', g and g.state, 'pick');
link.clear('test');

-- NL17 nothing worn: the whole pick counts. Apron +2 all, Kupo Shield +1 all,
-- Smithy's Torque +2 and Mitts +1, Craftmaster's Ring (HQ) and Artificer's
-- Ring (success).
W.worn = {};
g = preview(55, 'Smithing:30', 305);
local d = deltas(g and g.sk);
check('NL17 Smithing +6', d.Smithing, 6);
check('NL17b the all-craft pieces count for the other crafts too', d.Cooking, 3);
check('NL17c Synth HQ +1', g and g.hqr, '1');
check('NL17d success +1', g and g.succ, '1');
check('NL17e no HQ block', g and g.anti, '');
check('NL17f seven pieces to put on', select(2, (g and g.pieces or ''):gsub('|', '')) + 1, 7);

-- NL18 partly worn: a piece already on counts nothing; a replaced piece's
-- numbers come off.
W.worn = { Body = 'Artisan\'s Apron', Neck = 'Carver\'s Torque' };
g = preview(56, 'Smithing:30', 306);
d = deltas(g and g.sk);
check('NL18 Smithing: torque +2, mitts +1, shield +1', d.Smithing, 4);
check('NL18b Woodworking: the carver\'s torque comes off (-2), the shield adds 1', d.Woodworking, -1);
check('NL18c the worn apron is not named', (g and g.pieces or ''):find('Artisan', 1, true), nil);

-- NL19 all worn: nothing changes.
deliver('op=next;seq=57;crafts=Smithing:30');
link._pump(307);
wearAll();
g = preview(58, 'Smithing:30', 308);
check('NL19 all worn: no skill change', g and g.sk, '');
check('NL19b no HQ change', g and g.hqr, '0');
check('NL19c no success change', g and g.succ, '0');
check('NL19d no pieces', g and g.pieces, '');
check('NL19e still a pick', g and g.state, 'pick');
link.clear('test');

-- NL20 a worn HQ-blocking ring is replaced under the hq goal; the nq goal
-- puts one on (the preview follows the goal like next does).
W.worn = { Ring1 = 'Smith\'s Ring' };
g = preview(59, 'Smithing:30', 309);
check('NL20 the block comes off', g and g.anti, 'Smithing:-1');
W.worn, W.goal = {}, 'nq';
g = preview(60, 'Smithing:30', 310);
check('NL20b under nq the block goes on', g and g.anti, 'Smithing:1');
W.goal = 'hq';

-- NL21 off and none.
W.follow = false;
g = preview(61, 'Smithing:30', 311);
check('NL21 follow off: off', g and g.state, 'off');
check('NL21b off changes nothing', (g and g.sk or '') .. (g and g.anti or '') .. (g and g.pieces or ''), '');
check('NL21c off locks nothing', link.lockState(), nil);
W.follow = true;
W.items = {};
g = preview(62, 'Smithing:30', 312);
check('NL21d no gear: none', g and g.state, 'none');
W.items = GEAR;
g = preview(63, 'Dancing:30', 313);
check('NL21e no known craft: none', g and g.state, 'none');

-- NL22 a shield with no craft weapon takes a worn two-hander off; a worn
-- one-hander stays.
W.items = {
    item('Kupo Shield +2', 'sub', { sk = ALL8(3), shield = true }),
    item('Smithing Scythe', 'main', { sk = { Smithing = 9 }, twoHand = true }),
    item('High Hammer', 'main', { level = 99, sk = { Smithing = 2 }, twoHand = false }),
};
W.worn = { Main = 'Smithing Scythe' };
g = preview(64, 'Smithing:30', 314);
check('NL22 the scythe\'s +9 comes off with the shield\'s +3 on', deltas(g and g.sk).Smithing, -6);
W.worn = { Main = 'High Hammer' };
g = preview(65, 'Smithing:30', 315);
check('NL22b a one-handed Main stays on', deltas(g and g.sk).Smithing, 3);
W.items, W.worn = GEAR, {};

-- NL23 a preview without a number for seq is ignored.
local n23 = #sent;
deliver('op=preview;crafts=Smithing:30');
deliver('op=preview;seq=abc;crafts=Smithing:30');
link._pump(316);
check('NL23 malformed previews get no answer', #sent, n23);

print(string.format('%s -- %d checks, %d failed', failed == 0 and 'OK' or 'FAIL', count, failed));
if failed > 0 then os.exit(1); end
