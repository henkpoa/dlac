-- lua tests/gearvault_sync.lua -- sync consumers share work without losing changes.
local vc = dofile('servers/ascensionxi/modules/gearvault/vaultclient.lua');
local w16, w32 = vc._wu16, vc._wu32;
local now, sent = 100, {};
vc._clock = function() return now; end;
vc._send = function(p) sent[#sent + 1] = p; return true; end;
vc._say = function() end;
vc._readSlot = function(_, slot) return 1000 + slot; end;
local function tick() now = now + 0.4; vc.pump(true); end
local function reply(payload, flags)
    local p = assert(sent[#sent]);
    assert(vc.onFrame({ op = p[5], seq = p[6], status = 0, flags = flags or 0, payload = payload }));
end
local function header(n, rev) return w16(n) .. w16(0) .. w32(rev or 10); end
local function setup()
    vc._reset(); sent = {}; now = now + 10; vc.noteJob(1);
    vc.limits = { instances = true, maxLookup = 3 }; vc.revision = 10;
    vc.mirror.fresh = true; vc.mirror.stamp = now;
end
local function lookupReply()
    local p = sent[#sent]; assert(p[5] == vc.op.INSTANCE_LOOKUP);
    local raw = string.char(table.unpack(p));
    local n = vc._u16(raw, 12);
    local out = { header(n) };
    for i = 0, n - 1 do
        local cid, slot = vc._u8(raw, 16 + i * 4), vc._u8(raw, 17 + i * 4);
        out[#out + 1] = string.char(cid, slot) .. w16(1000 + slot) .. w32(2000 + slot) .. string.char(1, 0) .. w16(0);
    end
    reply(table.concat(out)); return n;
end

setup();
for slot = 1, 7 do
    assert(vc.instanceAt(8, slot, 1000 + slot) == nil);
    vc.instanceAt(8, slot, 1000 + slot); -- a second consumer must share the demand
end
tick(); assert(lookupReply() == 3);
tick(); assert(lookupReply() == 3);
tick(); assert(lookupReply() == 1);
assert(#sent == 3, 'lookups split only at the negotiated limit');
for slot = 1, 7 do assert(vc.instanceAt(8, slot, 1000 + slot).instanceId == 2000 + slot); end

setup();
vc.instanceAt(8, 1, 1001); vc.instanceAt(8, 2, 1002); tick();
vc.instanceAt(8, 3, 1003); -- cannot extend the in-flight snapshot
vc.invalidateInstances(); lookupReply();
assert(vc.instanceAt(8, 1, 1001) == nil, 'a raced batch publishes no mappings');
tick(); tick(); assert(lookupReply() == 2);
tick(); assert(lookupReply() == 1);
assert(vc.instanceAt(8, 1, 1001).instanceId == 2001);
assert(vc.instanceAt(8, 3, 1003).instanceId == 2003);

setup();
local done = 0;
vc.requestLookup({ { container = 8, slot = 1 } }, function(rows, err)
    assert(not err and #rows == 1 and rows[1].slot == 1); done = done + 1;
end);
vc.instanceAt(8, 2, 1002); tick(); assert(lookupReply() == 1);
tick(); assert(lookupReply() == 1); assert(done == 1, 'explicit batch callbacks keep their own result shape');
print('OK -- lookup batching, negotiated caps, shared consumers and movement races');

setup(); vc.requestLayout(0); tick();
vc.requestLayout(1); vc.requestLayout(0); -- UI and reconciler while the same read is in flight
reply(header(0));
tick();
assert(sent[#sent][5] == vc.op.LOST_LIST, 'duplicate consumers must not queue another layout read');
reply(w16(0) .. w16(0)); tick();
assert(#sent == 2 and vc.layoutCache.fresh);
print('OK -- equivalent in-flight layout requests coalesce');

vc.requestLayout(0); tick(); reply(header(0)); tick();
assert(#sent == 3, 'unchanged layout refresh does not re-read the same tombstones');

setup(); vc.requestLayout(0); tick();
vc.noteVaultChat(); -- the chat command may have changed the layout after the read began
vc.requestLayout(0); reply(header(0));
assert(not vc.layoutCache.fresh, 'an invalidated response cannot certify the layout as fresh');
tick(); assert(sent[#sent][5] == vc.op.LAYOUT_LIST2);
reply(header(0)); assert(vc.layoutCache.fresh);

setup(); vc.requestLayout(0); tick();
local row = w16(1) .. w16(100) .. w16(1) .. string.char(0, 0) .. w32(20)
    .. string.char(0, 1, 8, 1) .. vc.ZERO24;
reply(header(1) .. row, 1); tick();
vc.invalidateLayout(vc.SETTLE_LAYOUT); vc.requestLayout(0);
reply(header(0)); assert(not vc.layoutCache.fresh, 'a change during pagination rejects the whole snapshot');
tick(); reply(header(0)); assert(vc.layoutCache.fresh and #vc.layoutCache.entries == 0);

setup();
for _ = 1, 4 do
    vc.invalidateLayout(vc.SETTLE_LAYOUT); vc.requestLayout(0);
    now = now + 0.05; vc.pump(true);
end
assert(#sent == 0, 'one packet burst settles before requesting layout');
tick(); assert(#sent == 1 and sent[1][5] == vc.op.LAYOUT_LIST2);
reply(header(0)); tick(); reply(w16(0) .. w16(0)); tick(); assert(#sent == 2);

setup();
for _ = 1, 21 do
    vc.invalidateLayout(vc.SETTLE_LAYOUT); vc.requestLayout(0);
    now = now + 0.05; vc.pump(true);
end
assert(#sent >= 1, 'continuous packet traffic cannot defer the first ask indefinitely');
print('OK -- chat/inventory invalidation, pagination and bounded burst settling');

setup(); vc.requestLayout(0); vc.noteJob(2); tick();
assert(sent[1][9] == 0 or sent[1][9] == 2, 'queued current-job requests must not pin the previous job');
reply(header(0)); assert(vc.layoutCache.job == 2 and vc.layoutCache.fresh);

setup(); vc.requestLayout(0); tick(); vc.noteJob(2); reply(header(0));
assert(not vc.layoutCache.fresh); tick();
assert(#sent == 2 and (sent[2][9] == 0 or sent[2][9] == 2), 'an old-job reply schedules the new layout without a UI poll');

setup();
local send = vc._send; vc._send = function() return false; end;
vc.requestLayout(0); tick(); vc.noteJob(2); vc._send = send; tick();
assert(#sent == 1 and (sent[1][9] == 0 or sent[1][9] == 2), 'job changes cancel paced-but-unsent old-job reads');
print('OK -- queued, in-flight and transport-blocked job transitions');

local function pinnedAdd(capabilities, instanceId, selector, status)
    setup();
    vc.limits = assert(vc.parseHello(w16(1) .. w16(capabilities) .. w32(0)
        .. string.char(15, 124, 62, 0) .. w32(10) .. string.char(13, 12, 41, 30)));
    local completed, result = 0, nil;
    vc.requestLayoutSet({ verb = vc.verb.ADD, itemId = 100, instanceId = instanceId,
        selector = selector, pinned = true }, function(code)
        completed = completed + 1; result = code;
    end);
    tick();
    local raw = string.char(table.unpack(sent[#sent]));
    assert(vc._u8(raw, 12) == 1, 'ADD carries the requested pin');
    reply(w16(status or 0) .. w16(1) .. w32(10) .. w32(instanceId or 0));
    local atomic = capabilities == 3 and (instanceId or 0) > 0 and selector ~= 1;
    if not atomic and (status or 0) == 0 then
        assert(completed == 0, 'legacy pinned ADD is incomplete until PIN succeeds');
        tick(); assert(sent[#sent][10] == vc.verb.PIN, 'old servers and identity adds retain PIN fallback');
        reply(w16(0) .. w16(1) .. w32(10) .. w32(instanceId or 0));
    end
    assert(completed == 1 and result == (status or 0));
    assert(#sent == ((atomic or (status or 0) ~= 0) and 1 or 2));
end
pinnedAdd(1, 42);
pinnedAdd(3, 42);
pinnedAdd(3, 0, 1);
pinnedAdd(3, 42, nil, vc.code.NOT_IN_CITY);

setup(); vc.limits = { instances = false };
local completed, result = 0, nil;
vc.requestLayoutSet({ verb = vc.verb.ADD, itemId = 100, pinned = true }, function(code)
    completed = completed + 1; result = code;
end);
tick(); assert(sent[1][5] == vc.op.LAYOUT_SET);
reply(w16(vc.code.PARTIAL) .. w16(0)); assert(completed == 0);
tick(); assert(sent[2][10] == vc.verb.PIN);
reply(w16(0) .. w16(0));
assert(completed == 1 and result == vc.code.PARTIAL, 'v1 fallback preserves a partial ADD result');
print('OK -- negotiated atomic pinned ADD and legacy fallback');
