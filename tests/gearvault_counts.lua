-- Run from the addon root: lua tests/gearvault_counts.lua
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local rc = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\reconcile');
local wire = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\vaultclient');
local usage = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\usage');
local time, queue, wanted, town, asked = 100, {}, {}, true, false;
local records = { [100] = { Slot = 'Body' }, [200] = { Slot = 'Ring' },
    [300] = { Slot = 'Feet' } };
local vc = { ZERO24 = wire.ZERO24, verb = wire.verb, code = wire.code,
    state = function() return 'fresh'; end,
    layoutCache = { job = 1, fresh = true, stamp = 1, entries = {} },
    mirror = { fresh = true, stamp = 1, counts = {} },
    requestLayoutSet = function(e, done) queue[#queue + 1] = { e = e, done = done }; return true; end,
    requestLayout = function() asked = true; end,
    layoutBusy = function() return #queue > 0; end,
};
local function entry(id, count, pinned)
    return { ordinal = id, itemId = id, count = count, identity = wire.ZERO24, pinned = pinned == true };
end
local function reset(entries, items, vault)
    rc._reset(); queue = {}; asked = false; time = time + 100;
    vc.layoutCache = { job = 1, fresh = true, stamp = time, entries = entries };
    vc.mirror.counts = vault or {}; wanted = items or {}; town = true;
end
rc.configure({ vc = vc, clock = function() return time; end, mainJob = function() return 1; end,
    setsRoot = function() return {}; end, triggers = function() return {}; end,
    derive = { derive = function() return { items = wanted, hash = 'fixture' }; end },
    lookupById = function(id) return records[id]; end,
    capacity = function() return 23; end, usage = usage,
    settings = function() return { additions = 'on', removals = 'ask' }; end,
    inTown = function() return town; end,
});

-- Raising a ring pair from one to two must ADD one, since the server adds
-- the wire count to the existing row rather than replacing it.
reset({ entry(200, 1) }, { { itemId = 200, count = 2 } }, { [200] = 1 });
assert(rc.tick() == 'pushed:1');
assert(queue[1].e.count == 1, 'pair upgrade must send delta 1, not total 2');

-- The screenshot: 19 real equipment slots, but repeated clicks have raised
-- two single-slot layout rows by six, creating a false 25/23 pressure verdict.
local entries = { entry(100, 6, true), entry(300, 2) };
for id = 401, 417 do records[id] = { Slot = 'Head' }; entries[#entries + 1] = entry(id, 1); end
reset(entries);
rc.tick();
assert(#queue == 2, 'inflated legacy counts must be corrected');
assert(rc.pressure() == nil and rc.freeSlots() == 4, '19/23 must have four free slots and no full warning');
for _, req in ipairs(queue) do
    assert(req.e.verb == vc.verb.REMOVE and req.e.count > 0, 'repair decrements only the excess');
    for _, e in ipairs(entries) do
        if e.itemId == req.e.itemId then
            e.count = e.count - req.e.count;
            assert(e.count == 1, 'repair must retain the wanted entry');
        end
    end
    req.done(vc.code.OK);
end
assert(entries[1].pinned, 'count repair must preserve the pin');
assert(asked, 'correction must re-read the server layout');
queue = {}; vc.layoutCache.fresh = true; vc.layoutCache.stamp = time + 1; time = time + rc.BEAT + 1;
assert(rc.tick() == 'clean' and #queue == 0, 'repaired layout must settle without more writes');

reset({ entry(200, 2) }); rc.tick();
assert(#queue == 0 and rc.freeSlots() == 21, 'legitimate pairs remain two slots');
reset({ entry(100, 6) }); town = false; rc.tick();
assert(#queue == 0 and rc.freeSlots() == 22, 'field correction waits for town without phantom pressure');
town = true; rc.zoneArmed(); time = time + rc.BEAT + 1; rc.tick();
assert(#queue == 1, 'correction resumes on reaching town');

-- The real wire client must invalidate BOTH views before notifying callers:
-- active layout edits transfer items, so an old vault row is not reusable.
wire._reset();
wire._clock = function() return time; end;
local sent;
wire._send = function(p) sent = p; end;
wire.noteJob(1);
wire.mirror.fresh = true; wire.mirror.stamp = time;
wire.layoutCache = { job = 1, fresh = true, stamp = time, entries = {} };
local called = false;
wire.requestLayoutSet({ job = 0, verb = wire.verb.ADD, itemId = 100, count = 1 }, function(code)
    called = code == wire.code.OK;
    assert(not wire.mirror.fresh and not wire.layoutCache.fresh, 'callback must see invalidated views');
end);
assert(wire.layoutBusy());
wire.pump(true);
assert(sent[5] == wire.op.LAYOUT_SET);
wire.onFrame({ op = wire.op.LAYOUT_SET, seq = sent[6], status = 0, flags = 0,
    payload = wire._wu16(wire.code.OK) .. wire._wu16(0) });
assert(called and not wire.layoutBusy() and not wire.mirror.fresh and not wire.layoutCache.fresh);

-- Manual additions reserve only the edited item while both views catch up.
local function manualState(id)
    return wire.layoutAddState(id, wire.ZERO24);
end
assert(manualState(100).pending, 'the added item stays locked after its acknowledgement');
assert(manualState(200).ready, 'another item must remain addable during sync');
wire.requestLayoutSet({ job = 0, verb = wire.verb.ADD, itemId = 200, count = 1 });
assert(manualState(200).pending, 'the second queued item must also lock');
assert(manualState(300).reserved == 2, 'queued additions must reserve wardrobe capacity');
assert(manualState(300).ready, 'a third item must remain addable');
assert(not wire.layoutAddState(200, string.rep('\7', 24)).pending,
    'different augmented copies must have independent locks');
time = time + 10;
wire.pump(true);
assert(sent[5] == wire.op.LAYOUT_SET, 'the next queued addition precedes background sync');
wire.onFrame({ op = wire.op.LAYOUT_SET, seq = sent[6], status = 0, flags = 0,
    payload = wire._wu16(wire.code.OK) .. wire._wu16(0) });
wire.layoutCache.fresh = true;
assert(manualState(100).pending and manualState(200).pending,
    'refreshing only the layout must not release item locks');
assert(manualState(300).reserved == 2, 'acknowledgements retain capacity reservations');
wire.noteCounterTrade();   -- (a zone line is not one: it moves nothing -- 2026-10-01)
assert(not manualState(300).ready, 'external changes must invalidate the batch snapshot');
wire.cancelLayoutSets();
wire.mirror.fresh = true; wire.layoutCache.fresh = true;
assert(not manualState(100).pending and manualState(100).reserved == 0,
    'a complete refresh releases reservations');

-- A stale mirror cannot supply a new copy to automatic pair upgrades.
reset({ entry(200, 1) }, { { itemId = 200, count = 2 } }, { [200] = 1 });
vc.mirror.fresh = false; rc.tick();
assert(#queue == 0, 'stale vault stock must not produce another increment');
vc.mirror.fresh = true; time = time + rc.BEAT + 1; rc.tick();
assert(#queue == 1 and queue[1].e.count == 1, 'fresh stock can supply the missing copy');

print('OK -- gear vault additive edits and inflated layout recovery');

-- henkpoa/dlac#230, the reported shape: 65 wardrobe slots, a 65-entry THF
-- layout of which 3 are copies in the bags (kind 0, state 2), and 2 set
-- pieces waiting in the vault. The bag entries keep their slots (nothing is
-- added), the verdict names them, and they rank first for removal. The WAR
-- shape (65 on the wardrobes + 3 in the bags + 1 in the vault = 69) is the
-- "over" case of the same verdict, and Removals: Auto takes the bag entries
-- first.
local ZERO = wire.ZERO24;
local function inst(i, itemId, state, loc)
    return { ordinal = i, itemId = itemId, instanceId = 5000 + i, count = 1, kind = 0,
             state = state, location = loc, identity = ZERO };
end
local liftItems = { { itemId = 3001, count = 1 }, { itemId = 3002, count = 1 } };
for i = 1, 3 do liftItems[#liftItems + 1] = { itemId = 2000 + i, count = 1 }; end   -- the sets still name them
local ivc = { ZERO24 = ZERO, verb = wire.verb, code = wire.code,
    instanceMode = function() return true; end,
    state = function() return 'fresh'; end,
    mirror = { fresh = true, stamp = 1, counts = {}, rows = {
        { rowId = 1, itemId = 3001, instanceId = 7001, qty = 1, identity = ZERO },
        { rowId = 2, itemId = 3002, instanceId = 7002, qty = 1, identity = ZERO } } },
    requestLayoutSet = function(e, done) queue[#queue + 1] = { e = e, done = done }; return true; end,
    requestLayout = function() end,
    layoutBusy = function() return false; end,
};
local removals = 'ask';
local function liftTick(entries)
    rc._reset(); usage._reset(); queue = {}; time = time + 100;
    ivc.layoutCache = { job = 6, fresh = true, stamp = time, entries = entries };
    rc.configure({ vc = ivc, clock = function() return time; end, mainJob = function() return 6; end,
        setsRoot = function() return {}; end, triggers = function() return {}; end,
        derive = { derive = function() return { items = liftItems, hash = 'lift' }; end },
        lookupById = function() return nil; end,
        capacity = function() return 65; end, usage = usage,
        settings = function() return { additions = 'auto', removals = removals }; end,
        inTown = function() return true; end,
        worn = function() return { [2002] = true }; end,   -- one bag piece is worn from the bags
    });
    return rc.tick();
end

local lift = {};
for i = 1, 62 do lift[i] = inst(i, 1000 + i, 1, 8); end
for i = 1, 3 do lift[62 + i] = inst(62 + i, 2000 + i, 2, 0); end
liftTick(lift);
local p = rc.pressure();
assert(#queue == 0, 'the bag entries keep their slots: nothing is added');
assert(p ~= nil and p.over == 0 and p.waiting == 2, 'two set pieces wait for room');
assert(p.units == 65 and p.capacity == 65, 'the verdict carries the layout size and the capacity');
assert(#p.bagHeld == 3 and p.bagHeld[1].itemId == 2001 and p.bagHeld[3].itemId == 2003,
    'the verdict names the three bag entries');
for i = 1, 3 do
    assert(p.candidates[i].bagHeld and p.candidates[i].itemId > 2000 and p.candidates[i].itemId < 2004,
        'the bag entries rank first for removal, the worn one included');
end
assert(not p.candidates[4].bagHeld and p.candidates[4].itemId < 2000, 'then the wardrobe entries');

local war = {};
for i = 1, 65 do war[i] = inst(i, 1000 + i, 1, 8); end
for i = 1, 3 do war[65 + i] = inst(65 + i, 2000 + i, 2, 0); end
war[69] = inst(69, 3001, 0, 0); war[69].instanceId = 7001;   -- in the layout, still in the vault
liftTick(war);
p = rc.pressure();
assert(p ~= nil and p.over == 4 and p.units == 69 and #p.bagHeld == 3, 'WAR: 69 for 65, three of them in the bags');
removals = 'auto';
liftTick(war);
assert(#queue == 4, 'Removals: Auto frees exactly the overflow');
for i = 1, 3 do
    assert(queue[i].e.verb == wire.verb.REMOVE and queue[i].e.instanceId == 5065 + i,
        'Removals: Auto takes the bag entries first');
end
assert(queue[4].e.instanceId < 5066, '...then a wardrobe entry');
assert(usage.isExcluded(usage.keyOf(2001, nil)), 'an evicted set-wanted bag entry is benched');
-- everything on the wardrobes pinned and one bag piece pinned: Auto takes the
-- two it may, and the verdict names only the bag piece still holding a slot
for i = 1, 65 do war[i].pinned = true; end
war[68].pinned = true; war[69].pinned = true;
liftTick(war);
p = rc.pressure();
assert(#queue == 2 and p ~= nil and p.over == 2 and p.units == 67, 'Auto frees what it may');
assert(#p.bagHeld == 1 and p.bagHeld[1].itemId == 2003, 'only the pinned bag entry is still named');
removals = 'ask';

print('OK -- bag copies keep their slots, are named, and go first (#230)');
