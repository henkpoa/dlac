table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local base = 'dlac\\servers\\ascensionxi\\modules\\gearvault\\';
local vc, rc, usage = require(base .. 'vaultclient'), require(base .. 'reconcile'), require(base .. 'usage');
local e = { itemId = 12568, instanceId = 99, identity = string.rep('\1', 24), qty = 1 };
usage._reset();
for job = 1, 22 do usage.queueManual(job, e); end
local saved = assert((loadstring or load)(usage._serialize()))();
usage._reset(); usage._apply(saved);
assert(usage.manualFor(22)[usage.keyOf(e.itemId, nil, 99)].identity == e.identity);
local queue, cap, now = {}, 1, 100;
local mock = { ZERO24 = vc.ZERO24, code = vc.code, verb = vc.verb,
    instanceMode = function() return true; end, state = function() return 'fresh'; end,
    layoutBusy = function() return false; end, requestLayout = function() end,
    requestLayoutSet = function(edit) queue[#queue + 1] = edit; return true; end,
    layoutCache = { fresh = true, job = 1, stamp = 1, entries = {
        { itemId = 123, instanceId = 1, count = 1, pinned = true, kind = 0, state = 1 } } },
    mirror = { fresh = true, rows = { e }, counts = {} },
};
local function tick()
    rc._reset(); queue = {}; now = now + 20;
    rc.configure({ vc = mock, clock = function() return now; end, mainJob = function() return 1; end,
        setsRoot = function() return {}; end, triggers = function() return {}; end,
        derive = require(base .. 'derive'), usage = usage,
        settings = function() return { additions = 'off', removals = 'ask' }; end,
        capacity = function() return cap; end, inTown = function() return true; end,
        worn = function() return {}; end });
    return rc.tick();
end
tick();
assert(#queue == 0 and rc.pressure().waiting == 1, 'full wardrobe waits without sending');
cap = 2; tick();
assert(#queue == 1 and queue[1].instanceId == 99 and queue[1].pinned, 'manual copy adds pinned even with auto additions off');
mock.layoutCache.entries[2] = { itemId = e.itemId, instanceId = 99, identity = e.identity,
    count = 1, pinned = false, kind = 0, state = 1 };
tick();
assert(#queue == 1 and queue[1].verb == vc.verb.PIN, 'existing copy gets pinned, never duplicated or retired');
mock.layoutCache.entries[2].pinned = true;
tick();
assert(#queue == 0 and next(usage.manualFor(1)) == nil, 'fulfilled request is forgotten');
assert(next(usage.manualFor(2)) ~= nil, 'other jobs keep pending requests');
usage.resetCharacter(); assert(next(usage.manualFor(2)) == nil);
print('OK -- persistent all-job requests, full wardrobes, exact copies and pinning');
