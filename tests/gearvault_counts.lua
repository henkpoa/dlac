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
wire.noteZoneIn();
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
