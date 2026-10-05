-- lua tests/ascensionxi_autoacc.lua   (from the dlac repo root)
-- AutoAcc v1 on AscensionXI: the local model and the decision
-- (servers/ascensionxi/modules/telemetry/autoacc.lua) on the server's own
-- vectors. TV-05 is a THF 75 / DNC 37 against a level 78 mob wearing Peacock
-- Amulet, Toreador's Ring and Hydra Mittens; TV-06 is the frame after
-- Toreador's Ring went for Rajas Ring (tests/fixtures/ascensionxi/).
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);

local pass, fail = 0, 0;
local function check(name, got, want)
    if got == want then pass = pass + 1; return; end
    fail = fail + 1;
    print(('FAIL %s: got %s, want %s'):format(name, tostring(got), tostring(want)));
end

local wire = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\wire');
local aa = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\autoacc');

local function readVectors(path)
    local f = assert(io.open(path, 'rb')); local text = f:read('*a'); f:close();
    local out, cur, inBlock, hex = {}, nil, false, {};
    for line in text:gmatch('[^\n]*') do
        line = line:gsub('\r$', '');
        local name = line:match('^### (TV%-[%w]+)');
        if name then cur = name;
        elseif cur and line == '```' then
            if inBlock then out[cur] = table.concat(hex); cur, inBlock, hex = nil, false, {}; else inBlock = true; end
        elseif inBlock then for b in line:sub(7):gmatch('%x%x') do hex[#hex + 1] = string.char(tonumber(b, 16)); end end
    end
    return out;
end
local V = readVectors('tests/fixtures/ascensionxi/telemetry-wire-vectors.md');
-- A frame as the client hands it over: decoded, with its comparison key.
local function frameOf(name)
    local payload = wire.incoming(V[name]).payload;
    local f = assert(wire.decodeSnapshot(payload));
    f.key = wire.snapshotKey(payload);
    return f;
end

-- The items of the vectors with their real catalog stats.
local CATALOG = {
    [16460] = { Id = 16460, Name = 'Kris', Level = 1, Stats = {} },
    [16536] = { Id = 16536, Name = 'Iron Sword', Level = 1, Stats = {} },
    [17152] = { Id = 17152, Name = 'Shortbow', Level = 1, Stats = {} },
    [17318] = { Id = 17318, Name = 'Wooden Arrow', Level = 1, Stats = {} },
    [14925] = { Id = 14925, Name = 'Hydra Mittens', Level = 70, Stats = {} },
    [15515] = { Id = 15515, Name = 'Peacock Amulet', Level = 33, Stats = { Accuracy = 10, RangedAccuracy = 10 } },
    [14674] = { Id = 14674, Name = "Toreador's Ring", Level = 57, Stats = { Accuracy = 7, HP = 10 } },
    [13465] = { Id = 13465, Name = 'Brass Ring', Level = 7, Stats = {} },
    [15543] = { Id = 15543, Name = 'Rajas Ring', Level = 30, Stats = { DEX = 2, STR = 2 } },
    [13061] = { Id = 13061, Name = 'Spike Necklace', Level = 21, Stats = { DEX = 3, STR = 3 } },
    [14800] = { Id = 14800, Name = 'Tidal Talisman', Level = 30, Stats = {} },
};
local BY_NAME = {};
for id, rec in pairs(CATALOG) do BY_NAME[string.lower(rec.Name)] = id; end
local DATA = {
    levelscaling = { [15543] = { { stat = 'DEX', add = 1, from = 45 }, { stat = 'DEX', add = 1, from = 60 },
                                 { stat = 'DEX', add = 1, from = 75 } } },
    latentstats = { [14800] = { { stat = 'Accuracy', add = 5, cond = 'WEAPON_DRAWN', param = 0 } } },
    gearsets = {},
    itemscripts = { [14925] = 'enchant' },
};

local time = 0;
local worn = {};
local player = { mainJob = 6, mainLevel = 75, subJob = 19, subLevel = 37, buffs = { [251] = true }, target = 0x010680A5 };
aa._clock = function() return time; end;
aa._worn = function() return worn; end;
aa._player = function()
    local copy = {};
    for k, v in pairs(player) do copy[k] = v; end
    copy.buffs = {}; for id in pairs(player.buffs) do copy.buffs[id] = true; end
    return copy;
end;
aa._record = function(id) return CATALOG[id]; end;
aa._idOf = function(name) return BY_NAME[string.lower(name)]; end;
aa._data = function() return DATA; end;

local function wearTV05()
    worn = { [0] = { 0, 5, 16460 }, [1] = { 8, 3, 16536 }, [2] = { 8, 4, 17152 }, [3] = { 0, 6, 17318 },
             [6] = { 8, 9, 14925 }, [9] = { 8, 10, 15515 }, [13] = { 8, 11, 14674 }, [14] = { 0, 7, 13465 } };
end

-- The frame with the off hand context not applicable: a main-hand-only fight.
local function mainOnly(f)
    for _, c in ipairs(f.contexts) do if c.kind == wire.context.MELEE_SUB then c.applicability = wire.applicability.NOT_AVAILABLE; end end
    return f;
end

local RING = { slot = 'Ring1', typed = "Toreador's Ring", fallback = 'Rajas Ring', prio = 1 };
local function plan(over)
    local p = { Ring1 = "Toreador's Ring", Neck = 'Peacock Amulet' };
    for k, v in pairs(over or {}) do p[k] = v; end
    return p;
end

local function fresh()
    aa.reset(); time = time + 10; wearTV05();
    player.target, player.mainLevel = 0x010680A5, 75;
    player.buffs = { [251] = true };
end

-- AA-01: the TV-05 -> TV-06 release: Toreador's Ring gives way to Rajas Ring,
-- the main hand stays at the cap (AccToCap -11 -> -7).
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
check('AA-01 the frame is usable', aa.report().usable, true);
local d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-01 released', d.release.Ring1, 'Rajas Ring');
check('AA-01 main hand AccToCap after', d.metrics[1].accToCap, -7);
check('AA-01 the why', d.why.Ring1, 'released for Rajas Ring');

-- AA-02: with the off hand protected (TV-05 as published, off hand at 70 %)
-- the full set misses the cap: nothing is released.
fresh();
aa.noteFrame(frameOf('TV-05'));
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-02 nothing released', d.release.Ring1, nil);
check('AA-02 why', d.why.Ring1, 'the full set does not reach the cap');

-- AA-03: removal priority. With 11 ACC to spare, Peacock Amulet (prio 5, ACC
-- 10, for Spike Necklace's DEX+3: net -8) goes first and leaves 3; Toreador's
-- Ring (prio 1, ACC 7, for a plain Brass Ring) is then needed for the cap.
-- (With Rajas Ring as its fallback the pair lands exactly on the cap, gap 40.)
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
d = aa.decide({ plan = plan(), event = 'Default', candidates = {
    { slot = 'Ring1', typed = "Toreador's Ring", fallback = 'Brass Ring', prio = 1 },
    { slot = 'Neck', typed = 'Peacock Amulet', fallback = 'Spike Necklace', prio = 5 } } });
check('AA-03 the higher priority goes', d.release.Neck, 'Spike Necklace');
check('AA-03 the lower is kept', d.release.Ring1, nil);
check('AA-03 why kept', d.why.Ring1, 'needed for the cap');
d = aa.decide({ plan = plan(), event = 'Default', candidates = {
    RING, { slot = 'Neck', typed = 'Peacock Amulet', fallback = 'Spike Necklace', prio = 5 } } });
check('AA-03 exactly at the cap is enough', d.release.Ring1, 'Rajas Ring');

-- AA-04: the formula check. A frame whose numbers do not compose decides nothing.
fresh();
local bad = mainOnly(frameOf('TV-05'));
bad.contexts[1].liveAcc = bad.contexts[1].liveAcc + 1;
aa.noteFrame(bad);
check('AA-04 unusable', aa.report().usable, false);
check('AA-04 says the formula', aa.report().why:find('formula check', 1, true) ~= nil, true);
check('AA-04 holds', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1, nil);

-- AA-05: the gear check. A wrong catalog row is caught, its pieces go
-- unverified, and a later good frame clears them.
fresh();
CATALOG[14674].Stats.Accuracy = 8;
aa._state().vectors = {};
aa.noteFrame(mainOnly(frameOf('TV-05')));
check('AA-05 unusable', aa.report().gearOk, false);
check('AA-05 the ring is unverified', aa.report().unverified[14674] ~= nil, true);
CATALOG[14674].Stats.Accuracy = 7;
aa._state().vectors = {};
aa.noteFrame(mainOnly(frameOf('TV-05')));
check('AA-05 a matching frame verifies it again', aa.report().unverified[14674], nil);
check('AA-05 usable again', aa.report().usable, true);

-- AA-06: inside an Onslaught run nothing is decided.
fresh();
local run = mainOnly(frameOf('TV-05'));
run.snapFlags = run.snapFlags + wire.snapFlag.GEAR_REFILL;
aa.noteFrame(run);
check('AA-06 GEAR_REFILL holds', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1, nil);

-- AA-07: a used enchantment is never released (Hydra Mittens, hands bit).
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
d = aa.decide({ plan = plan({ Hands = 'Hydra Mittens' }), event = 'Default',
    candidates = { { slot = 'Hands', typed = 'Hydra Mittens', fallback = 'Brass Ring', prio = 9 } } });
check('AA-07 kept', d.release.Hands, nil);
check('AA-07 why', d.why.Hands, 'its enchantment would be lost');

-- AA-08: conservative triggers hold every piece until the next frame. (The
-- player read is reused for PLAYER_EVERY, so each change gets its moment.)
local function heldBy(mutate, label)
    fresh();
    aa.noteFrame(mainOnly(frameOf('TV-05')));
    mutate();
    time = time + 0.2;
    local x = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
    check('AA-08 ' .. label .. ' holds', x.release.Ring1, nil);
    check('AA-08 ' .. label .. ' says so', (x.why.Ring1 or ''):find('held until the next frame', 1, true) ~= nil, true);
end
heldBy(function() player.target = 0x01068001; end, 'a new target');
heldBy(function() player.mainLevel = 74; end, 'a level change');
heldBy(function() player.buffs[146] = true; end, 'Accuracy Down');
heldBy(function() player.buffs[251] = nil; end, 'food wearing off');
-- and the next frame lifts it
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
player.buffs[251] = nil;
aa.noteFrame(mainOnly(frameOf('TV-05')));
check('AA-08 the next frame decides again', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1,
    'Rajas Ring');

-- AA-09: unmodelled pieces stay: a fallback with an accuracy latent, and an
-- augmented copy.
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
d = aa.decide({ plan = plan(), event = 'Default',
    candidates = { { slot = 'Ring1', typed = "Toreador's Ring", fallback = 'Tidal Talisman', prio = 1 } } });
check('AA-09 a latent fallback is kept out', d.release.Ring1, nil);
check('AA-09 why', (d.why.Ring1 or ''):find('accuracy latent', 1, true) ~= nil, true);
fresh();
worn[13][4] = true; -- the worn Toreador's Ring is an augmented copy
aa.noteFrame(mainOnly(frameOf('TV-05')));
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default', augmented = { Ring1 = true } });
check('AA-09 an augmented piece stays', d.release.Ring1, nil);

-- AA-10: only the standing Default set releases, also when the weapon
-- skill's plan is the standing set's (the memo keeps the two apart).
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
check('AA-10 a weapon skill keeps its pieces', aa.decide({ plan = plan(), candidates = { RING }, event = 'Weaponskill' }).release.Ring1, nil);
check('AA-10 the standing set after it releases', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1, 'Rajas Ring');
check('AA-10 and the weapon skill after that still keeps them', aa.decide({ plan = plan(), candidates = { RING }, event = 'Weaponskill' }).release.Ring1, nil);

-- AA-11: a frame naming an outfit dlac never saw is not used.
fresh();
local stranger = mainOnly(frameOf('TV-05'));
stranger.equipRev = 0x12345678;
aa.noteFrame(stranger);
check('AA-11 unknown outfit', aa.report().usable, false);

-- AA-12: weapon slots stay in v1.
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
d = aa.decide({ plan = plan({ Main = 'Kris' }), event = 'Default',
    candidates = { { slot = 'Main', typed = 'Kris', fallback = 'Iron Sword', prio = 9 } } });
check('AA-12 Main kept', d.release.Main, nil);
check('AA-12 why', d.why.Main, 'weapon slots stay');

-- AA-13: a frame taken in an older outfit of the ring still decides: TV-05
-- arrives after the player already wore the released outfit.
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
worn[13] = { 8, 12, 15543 };   -- Rajas Ring on now
time = time + 1; aa.pump();
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-13 the ring of outfits keeps the frame usable', d.release.Ring1, 'Rajas Ring');

-- AA-14: TV-06 (taken in the released outfit) checks too, with Rajas Ring's
-- level latents inside R.
fresh();
worn[13] = { 8, 12, 15543 };
local tv06 = mainOnly(frameOf('TV-06'));
aa.noteFrame(tv06);
check('AA-14 TV-06 passes the gear check', aa.report().gearOk, true);
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-14 the decision from TV-06 agrees', d.release.Ring1, 'Rajas Ring');

-- AA-15: the same request twice is one decision (memoised); a new frame is not.
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
local first = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
local again = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-15 memoised', again, first);
local rev = aa.revision();
aa.noteFrame(mainOnly(frameOf('TV-05')));
check('AA-15 a frame moves the revision', aa.revision() ~= rev, true);
check('AA-15 a new decision', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }) ~= first, true);

-- AA-16: the HP clamp. A release that lowers max HP while an HP-latent
-- accuracy piece is worn could flip that latent: kept.
fresh();
DATA.latentstats[16536] = { { stat = 'Accuracy', add = 5, cond = 'HP_UNDER_PERCENT', param = 75 } };
aa._state().vectors = {};
aa.noteFrame(mainOnly(frameOf('TV-05')));
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-16 kept', d.release.Ring1, nil);
check('AA-16 why', d.why.Ring1, 'it lowers max HP while an HP latent is worn');
DATA.latentstats[16536] = nil;

-- AA-17: the margin. The release leaves the main hand 7 ACC over the cap
-- (AccToCap -7); with MARGIN 8 that is not enough, and the ring stays.
fresh();
aa.MARGIN = 8;
aa.noteFrame(mainOnly(frameOf('TV-05')));
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-17 a margin can keep the piece', d.release.Ring1, nil);
aa.MARGIN = 0;

-- AA-18: an empty candidate list costs nothing and decides nothing.
check('AA-18 no candidates', next(aa.decide({ plan = plan(), candidates = {}, event = 'Default' }).release), nil);

-- AA-19: a frame of the same key in an outfit dlac never saw (a weapon
-- skill's, worn for a moment) costs the standing set nothing: the Default
-- basis still decides.
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
local ws = mainOnly(frameOf('TV-05'));
ws.equipRev, ws.rev = 0x0BADBEEF, ws.rev + 1;
aa.noteFrame(ws);
check('AA-19 the WS frame is no basis', aa.report().why, 'the frame names an outfit dlac did not see');
check('AA-19 the Default basis stays', aa.report().bases, 1);
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-19 still released', d.release.Ring1, 'Rajas Ring');

-- AA-20: a new key in an unseen outfit starts over; dlac asks once for a
-- frame in the outfit worn now, and that answer decides.
fresh();
local asked = {};
aa._ask = function(kind) asked[#asked + 1] = kind; return true; end;
aa.noteFrame(mainOnly(frameOf('TV-05')));
local moved = mainOnly(frameOf('TV-05'));
moved.key, moved.equipRev = moved.key .. 'x', 0x0BADBEEF;
aa.noteFrame(moved);
check('AA-20 a new key starts over', aa.report().bases, 0);
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-20 holds', d.release.Ring1, nil);
check('AA-20 asks for the worn outfit', asked[1], 'republish');
aa.decide({ plan = plan(), event = 'Default',
    candidates = { { slot = 'Ring1', typed = "Toreador's Ring", fallback = 'Rajas Ring', prio = 2 } } });
check('AA-20 once per outfit', #asked, 1);
time = time + aa.ASK_AGAIN + 1;
aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-20 again after ASK_AGAIN (the answer may be lost)', #asked, 2);
local answer = mainOnly(frameOf('TV-05'));
answer.key = moved.key;
aa.noteFrame(answer);
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-20 the answer decides', d.release.Ring1, 'Rajas Ring');
aa._ask = nil;

-- AA-21: with two bases, the newest (TV-06, the Rajas Ring outfit) cannot
-- speak for the Toreador's Ring plan once Rajas Ring is unmodelled, so the
-- older one (TV-05) does, and the candidate is judged on its own.
fresh();
local five = mainOnly(frameOf('TV-05'));
aa.noteFrame(five);
worn[13] = { 8, 12, 15543 }; time = time + 1;
local six = mainOnly(frameOf('TV-06'));
six.key = aa._state().key;   -- as if only the outfit had moved
aa.noteFrame(six);
check('AA-21 two bases', aa.report().bases, 2);
DATA.itemscripts[15543] = 'script';
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-21 the older basis spoke', aa.report().basis, five);
check('AA-21 the fallback judged on its own', d.why.Ring1, 'an equip script dlac does not model');
DATA.itemscripts[15543] = nil;
d = aa.decide({ plan = plan(), event = 'Default',   -- another request: the memo does not answer
    candidates = { { slot = 'Ring1', typed = "Toreador's Ring", fallback = 'Rajas Ring', prio = 2 } } });
check('AA-21 the newest speaks when it can', aa.report().basis, six);
check('AA-21 and agrees', d.release.Ring1, 'Rajas Ring');

-- AA-22: losing an effect that adds no accuracy keeps the decision; losing a
-- listed one holds until a frame, or LOSS_SETTLE without one, after which it
-- is let go and dlac asks what landed.
fresh();
player.buffs[40] = true;     -- Protect
player.buffs[199] = true;    -- Madrigal
aa.noteFrame(mainOnly(frameOf('TV-05')));
player.buffs[40] = nil; time = time + 0.2;
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-22 Protect wearing off keeps the decision', d.release.Ring1, 'Rajas Ring');
asked = {};
aa._ask = function(kind) asked[#asked + 1] = kind; return true; end;
player.buffs[199] = nil; time = time + 0.2;
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-22 Madrigal wearing off holds', d.release.Ring1, nil);
check('AA-22 and says so', d.why.Ring1, 'held until the next frame: an accuracy effect wore off');
time = time + aa.LOSS_SETTLE - 0.5;
check('AA-22 still held inside LOSS_SETTLE', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1, nil);
time = time + 0.6;
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-22 let go when no frame came', d.release.Ring1, 'Rajas Ring');
check('AA-22 and asked what landed', asked[1], 'renew');
time = time + 0.2;
check('AA-22 settled', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1, 'Rajas Ring');
aa._ask = nil;

-- AA-23: a gained accuracy debuff holds for as long as it is up.
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
player.buffs[5] = true; time = time + 0.2;
check('AA-23 Blindness holds', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1, nil);
time = time + 30;
check('AA-23 and the settle timer never lets it go', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1, nil);
player.buffs[5] = nil; time = time + 0.2;
check('AA-23 it wearing off lifts it', aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' }).release.Ring1, 'Rajas Ring');

-- AA-24: demand. Nothing samples the worn outfit until a decision is asked
-- for; then decide() tells the client, and IDLE_AFTER later it stops.
fresh();
local reads, wants = 0, 0;
local realWorn = aa._worn;
aa._worn = function() reads = reads + 1; return worn; end;
for _ = 1, 10 do time = time + 0.3; aa.pump(); end
check('AA-24 no decision wanted, no reads', reads, 0);
aa._want = function() wants = wants + 1; end;
aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-24 a decision tells the client', wants, 1);
check('AA-24 the readout says wanted', aa.report().wanted, true);
reads = 0;
for _ = 1, 10 do time = time + 0.3; aa.pump(); end
check('AA-24 then the outfit is sampled', reads, 10);
time = time + aa.IDLE_AFTER;
reads = 0; aa.pump();
check('AA-24 and IDLE_AFTER later it is not', reads, 0);
aa._worn, aa._want = realWorn, nil;

-- AA-25: an Onslaught frame marks no piece unverified (its gear stats are
-- refilled, so the gear check cannot speak).
fresh();
CATALOG[14674].Stats.Accuracy = 8;
aa._state().vectors = {};
local refill = mainOnly(frameOf('TV-05'));
refill.snapFlags = refill.snapFlags + wire.snapFlag.GEAR_REFILL;
aa.noteFrame(refill);
check('AA-25 no piece marked', aa.report().unverified[14674], nil);
check('AA-25 and says why', aa.report().why, 'inside an Onslaught run');
CATALOG[14674].Stats.Accuracy = 7;
aa._state().vectors = {};

-- AA-26: a mismatch beside a verified basis marks only the pieces that
-- differ from it.
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
worn[13] = { 8, 12, 15543 }; time = time + 1;
CATALOG[15543].Stats.DEX = 3;   -- dlac's Rajas Ring row is wrong
aa._state().vectors = {};
local wrong = mainOnly(frameOf('TV-06'));
wrong.key = aa._state().key;
aa.noteFrame(wrong);
check('AA-26 the mismatch', aa.report().gearOk, false);
check('AA-26 Rajas Ring is unverified', aa.report().unverified[15543] ~= nil, true);
check('AA-26 a piece both outfits share is not', aa.report().unverified[15515], nil);
check('AA-26 the basis stays', aa.report().bases, 1);
CATALOG[15543].Stats.DEX = 2;
aa._state().vectors = {};

-- AA-27: a formula failure drops every basis of the key, and dlac asks for a
-- frame in the worn outfit when the failing one was taken in another.
fresh();
asked = {};
aa._ask = function(kind) asked[#asked + 1] = kind; return true; end;
aa.noteFrame(mainOnly(frameOf('TV-05')));
local broken = mainOnly(frameOf('TV-05'));
broken.contexts[1].liveAcc = broken.contexts[1].liveAcc + 1;
broken.equipRev = 0x0BADBEEF;
aa.noteFrame(broken);
check('AA-27 no basis left', aa.report().bases, 0);
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-27 holds on the formula', (d.why.Ring1 or ''):find('formula check', 1, true) ~= nil, true);
check('AA-27 asks for the worn outfit', asked[1], 'republish');
local inWorn = mainOnly(frameOf('TV-05'));
inWorn.contexts[1].liveAcc = inWorn.contexts[1].liveAcc + 1;
inWorn.key = broken.key .. 'y';   -- a new key, taken in the outfit worn now
aa.noteFrame(inWorn);
aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-27 a failing frame of the worn outfit asks nothing more', #asked, 1);
aa._ask = nil;

-- AA-28: the player read is reused for PLAYER_EVERY (two reads per
-- dispatch and the readout's every frame cost one).
fresh();
aa.noteFrame(mainOnly(frameOf('TV-05')));
local playerReads = 0;
local realPlayer = aa._player;
aa._player = function() playerReads = playerReads + 1; return realPlayer(); end;
time = time + 0.2;
aa.revision(); aa.revision(); aa.report();
check('AA-28 one read inside PLAYER_EVERY', playerReads, 1);
time = time + 0.2;
aa.revision();
check('AA-28 a new one after it', playerReads, 2);
aa._player = realPlayer;

-- AA-29..AA-33: the prediction check. TV-05's release of Toreador's Ring for
-- Rajas Ring predicts each hand in the new outfit; TV-06 is the server's frame
-- for that outfit, so the vectors' own projection must come back "matched".
local function contextOf(frame, kind)
    for _, c in ipairs(frame.contexts) do if c.kind == kind then return c; end end
    return nil;
end
local function released()
    fresh();
    aa.noteFrame(mainOnly(frameOf('TV-05')));
    return aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
end
local function wearRajas() worn[13] = { 8, 12, 15543 }; time = time + 1; end

d = released();
check('AA-29 released', d.release.Ring1, 'Rajas Ring');
check('AA-29 a prediction waits', aa.report().prediction.verdict, 'waiting');
wearRajas();
local six = mainOnly(frameOf('TV-06'));
aa.noteFrame(six);
local pr = aa.report().prediction;
check('AA-29 the server measured it: matched', pr.verdict, 'matched');
local mainRow = pr.rows[wire.context.MELEE_MAIN];
check('AA-29 the predicted ACC is the server\'s', mainRow.acc, contextOf(six, wire.context.MELEE_MAIN).liveAcc);
check('AA-29 the measured ACC', mainRow.measuredAcc, contextOf(six, wire.context.MELEE_MAIN).liveAcc);
check('AA-29 the predicted hit rate is the server\'s', mainRow.threshold, contextOf(six, wire.context.MELEE_MAIN).thresholdBp);
check('AA-29 measured: 7 spare', mainRow.measuredToCap, -7);
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-29 a matched release goes on releasing', d.release.Ring1, 'Rajas Ring');
check('AA-29 and keeps its verdict', aa.report().prediction.verdict, 'matched');

-- AA-30: a wrong model (Rajas Ring's level latents doubled in dlac's data):
-- the release still goes, the server's frame disagrees, and both rings stay
-- on from then on.
local savedRows = DATA.levelscaling[15543];
DATA.levelscaling[15543] = { { stat = 'DEX', add = 2, from = 45 }, { stat = 'DEX', add = 2, from = 60 },
                             { stat = 'DEX', add = 2, from = 75 } };
d = released();
check('AA-30 the wrong model releases', d.release.Ring1, 'Rajas Ring');
wearRajas();
aa.noteFrame(mainOnly(frameOf('TV-06')));
pr = aa.report().prediction;
check('AA-30 the server disagrees', pr.verdict, 'mismatch');
check('AA-30 Rajas Ring is kept on', aa.report().mispredicted[15543] ~= nil, true);
check('AA-30 so is Toreador\'s Ring', aa.report().mispredicted[14674] ~= nil, true);
worn[13] = { 8, 11, 14674 }; time = time + 1;
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-30 no second release', d.release.Ring1, nil);
check('AA-30 and says why', d.why.Ring1, 'a release of it was predicted wrongly');
DATA.levelscaling[15543] = savedRows;

-- AA-31: something besides the gear changed before the server measured the
-- new outfit (the monster levelled): not checked, nothing marked.
d = released();
wearRajas();
local moved = mainOnly(frameOf('TV-06'));
moved.targetLevel = moved.targetLevel + 1;
aa.noteFrame(moved);
check('AA-31 not checked', aa.report().prediction.verdict, 'not checked');
check('AA-31 nothing marked', next(aa.report().mispredicted), nil);

-- AA-32: the pieces go back on before the server measures: not checked.
d = released();
aa.MARGIN = 100;
d = aa.decide({ plan = plan(), event = 'Default',
    candidates = { { slot = 'Ring1', typed = "Toreador's Ring", fallback = 'Rajas Ring', prio = 2 } } });
check('AA-32 nothing released now', d.release.Ring1, nil);
check('AA-32 the waiting prediction retires', aa.report().prediction.verdict, 'not checked');
aa.MARGIN = 0;

-- AA-34: a weapon skill between the release and the server's frame retires
-- the prediction; the standing set's next decision re-arms it, and the
-- frame still checks it.
d = released();
aa.decide({ plan = plan(), candidates = { RING }, event = 'Weaponskill' });
check('AA-34 the weapon skill retires it', aa.report().prediction.verdict, 'not checked');
d = aa.decide({ plan = plan(), candidates = { RING }, event = 'Default' });
check('AA-34 the standing set re-arms it', aa.report().prediction.verdict, 'waiting');
wearRajas();
aa.noteFrame(mainOnly(frameOf('TV-06')));
check('AA-34 and the frame checks it', aa.report().prediction.verdict, 'matched');

-- AA-33: a zone change forgets the session's verdicts.
aa.report().mispredicted[15543] = 'a release predicted wrongly';
aa.zoneChange();
check('AA-33 zoning clears the marks', next(aa.report().mispredicted), nil);
check('AA-33 and the prediction', aa.report().prediction, nil);

print(('ascensionxi_autoacc: %d passed, %d failed'):format(pass, fail));
if fail > 0 then os.exit(1); end
