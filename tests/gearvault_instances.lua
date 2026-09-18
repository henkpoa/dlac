-- lua tests/gearvault_instances.lua -- real codecs, queue, reconciliation.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local base = 'dlac\\servers\\ascensionxi\\modules\\gearvault\\';
local vc = require(base .. 'vaultclient');
local counts = require(base .. 'layoutcounts');
local usage = require(base .. 'usage');
local rc = require(base .. 'reconcile');
local w16, w32, zero = vc._wu16, vc._wu32, vc.ZERO24;
local now, sent = 100, {};
vc._clock = function() return now; end;
vc._send = function(p) sent[#sent + 1] = p; end;
vc._say = function() end;
local function tick() now = now + 1; vc.pump(true); end
local function reply(payload, flags, status, hold)
    local p = assert(vc._st().pending, 'expected a pending request');
    vc.onFrame({ op = p.op, seq = p.seq, status = status or 0, flags = flags or 0, payload = payload });
    if not hold and vc._st().pending and vc._st().pending.sentAt == nil then tick(); end
end
local function listRow(id, item, extra)
    return w32(id + 1000) .. w16(item) .. w16(1) .. w32(id) .. (extra or zero);
end
local function layoutRow(ordinal, id, item, kind, state, count, extra)
    return w16(ordinal) .. w16(item) .. w16(count or 1) .. string.char(0, 0) .. w32(id)
        .. string.char(kind or 0, state or 1, 8, ordinal) .. (extra or zero);
end
local function header(n, rev) return w16(n) .. w16(0) .. w32(rev or 10); end
local function fresh()
    vc._reset(); sent = {}; vc.noteJob(1); vc.refresh(); tick();
    assert(sent[#sent][5] == vc.op.HELLO);
    reply(w16(1) .. w16(1) .. w32(1) .. string.char(15, 124, 62, 0) .. w32(10) .. string.char(13, 12, 41, 30));
    assert(vc.instanceMode() and sent[#sent][5] == vc.op.LIST2);
    reply(header(1) .. listRow(11, 100));
    vc.requestLayout(0); tick();
    assert(sent[#sent][5] == vc.op.LAYOUT_LIST2);
    reply(header(1) .. layoutRow(1, 10, 100));
    assert(vc.layoutCache.entries[1].instanceId == 10);
    tick(); assert(sent[#sent][5] == vc.op.LOST_LIST); reply(w16(0) .. w16(0));
end

-- Fast local replies must not bypass pacing at HELLO -> LIST transitions.
vc._reset(); vc.refresh(); tick();
local sentBeforeReply = #sent;
reply(w16(1) .. w16(1) .. w32(1) .. string.char(15,124,62,0) .. w32(10) .. string.char(13,12,41,30), 0, 0, true);
assert(#sent == sentBeforeReply, 'HELLO reply must queue LIST2, not send another packet in the same instant');

assert(vc.parseHello(w16(1) .. w16(1) .. string.rep('\0', 8)) == nil, 'truncated v2 HELLO must not enable instances');
assert(not vc.parseHello(w16(1) .. w16(0) .. string.rep('\0', 8)).instances);
assert(vc.parseList2(header(1) .. 'short') == nil);
assert(vc.parseLayout2(header(1) .. 'short') == nil);
assert(vc.parseLookup(header(42) .. string.rep('\0', 42 * 12)) == nil);
assert(vc.parseLost(w16(1) .. w16(0)) == nil);
assert(counts.count({ kind = 2, state = 2, count = 9 }) == 0);
assert(counts.count({ kind = 1, count = 99 }) == 1);
assert(counts.count({ instanceId = 9, count = 99 }) == 1);
assert(usage.keyOf(100, zero, 11) == usage.keyOf(100, string.rep('\7', 24), 11));
assert(usage.keyOf(100, zero, 11) ~= usage.keyOf(100, zero, 12));

fresh();
assert(vc.mirror.counts[100] == 1, 'ownership stays item-id based');
vc.requestLayoutSet({ itemId = 100, instanceId = 11, verb = vc.verb.ADD }); tick();
local p = vc._st().pending.frame;
assert(p[5] == vc.op.LAYOUT_SET2 and p[11] == 0, 'manual instance add uses selector 0');
assert(vc._u32(string.char(table.unpack(p)), 18) == 11);
local seq = p[6]; now = now + 2; vc.pump(true);
assert(sent[#sent][6] == seq, 'write retry must preserve sequence');
reply(w16(0) .. w16(1) .. w32(11) .. w32(11));
assert(not vc.mirror.fresh and not vc.layoutCache.fresh);

fresh();
vc.requestLayoutSet({ itemId = 100, ordinal = 7, instanceId = 11, verb = vc.verb.BIND }); tick();
p = vc._st().pending.frame;
assert(p[10] == 3 and p[11] == 2 and p[23] == 7, 'bind identifies both ordinal and physical copy');
reply(w16(19) .. w16(0) .. w32(10));
vc.requestLayoutSet({ itemId = 100, ordinal = 8, verb = vc.verb.REMOVE }); tick();
assert(vc._st().pending.frame[11] == 2, 'legacy dismiss is by ordinal');
reply(w16(0) .. w16(0) .. w32(10));

fresh(); local completed = 0;
local function done() completed = completed + 1; end
vc.requestLayoutSet({ itemId = 100, instanceId = 11, verb = vc.verb.ADD }, done);
vc.requestLayoutSet({ itemId = 100, instanceId = 12, verb = vc.verb.ADD }, done);
tick(); vc.noteJob(2);
assert(completed == 1 and #vc._st().layoutSetQ == 1, 'job change drains queued callbacks, retaining the in-flight request');
assert(vc._st().pending.frame[9] == 1, 'the sent edit must retain the originating job');
reply(w16(0) .. w16(1) .. w32(11) .. w32(11));
assert(completed == 2 and not vc.layoutBusy(), 'job change cannot strand reconciliation in flight');

-- A stale lookup never publishes identities, even when memory looks identical.
fresh(); local result, err;
vc._readSlot = function() return 100; end;
assert(vc.requestLookup({ { container = 8, slot = 1 } }, function(r, e) result, err = r, e; end));
tick(); reply(header(0, 11), 2);
assert(result == nil and #vc._st().lookupQ == 1);
tick(); tick();
local mapping = string.char(8, 1) .. w16(100) .. w32(10) .. string.char(1, 0) .. w16(0);
reply(header(1, 11) .. mapping);
assert(result and result[1].instanceId == 10 and not err);
assert(vc.instanceAt(8, 1, 100).instanceId == 10);
vc.invalidateInstances();
assert(vc.instanceAt(8, 1, 100) == nil, 'item packet invalidates previously accepted cache');
tick(); tick(); vc.invalidateInstances(); reply(header(1, 11) .. mapping);
assert(vc._st().instanceCache['8:1'] == nil, 'an in-flight reply racing a packet is discarded');
tick(); tick(); reply(header(0, 12), 2);
tick(); tick(); reply(header(0, 13), 2);
assert(#vc._st().lookupQ == 0, 'three raced attempts defer further lookup');

-- Different revisions across pages cannot create a mixed mirror.
fresh(); vc.refresh(); tick();
reply(w16(1) .. w16(1) .. w32(14) .. string.char(15,124,62,0) .. w32(10) .. string.char(13,12,41,30));
reply(header(1, 10) .. listRow(12, 100), 1);
reply(header(1, 11) .. listRow(13, 100));
assert(not vc.mirror.fresh and vc.mirror.rows[1].instanceId == 11);

-- The old server must continue to receive only v1 operations.
vc._reset(); vc.refresh(); tick();
reply(w16(1) .. w16(0) .. w32(0) .. string.char(15,124,62,0));
assert(sent[#sent][5] == vc.op.LIST and not vc.instanceMode()); reply(w16(0) .. w16(0));
assert(not vc.requestLookup({ { container = 8, slot = 1 } }));

-- Reconcile the actual reported pattern: mutable ring bytes do not create
-- a second reservation; review rows cannot be bypassed by automatic adds.
local queue = {};
local mock = { ZERO24 = zero, code = vc.code, verb = vc.verb, instanceMode = function() return true; end,
    state = function() return 'fresh'; end, layoutBusy = function() return false; end,
    requestLayoutSet = function(e) queue[#queue + 1] = e; return true; end,
    layoutCache = { fresh = true, job = 1, stamp = 1, entries = {
        { itemId = 100, instanceId = 10, kind = 0, count = 1, identity = string.rep('\1', 24) },
        { itemId = 200, ordinal = 2, kind = 2, state = 2, count = 0, identity = zero },
    } },
    mirror = { fresh = true, stamp = 1, counts = { [100] = 1, [200] = 1 }, rows = {
        { itemId = 100, instanceId = 10, qty = 1, identity = string.rep('\2', 24) },
        { itemId = 200, instanceId = 20, qty = 1, identity = zero },
    } },
};
local desired = { { itemId = 100, count = 1 }, { itemId = 200, count = 1 } };
rc._reset(); rc.configure({ vc = mock, clock = function() return now; end, mainJob = function() return 1; end,
    setsRoot = function() return {}; end, triggers = function() return {}; end,
    derive = { derive = function() return { items = desired, hash = 'fixture' }; end },
    lookupById = function() return { Slot = 'Ring' }; end,
    capacity = function() return 3; end, usage = usage, inTown = function() return true; end });
rc.tick(); assert(#queue == 0 and rc.freeSlots() == 2);
mock.layoutCache.entries = { mock.layoutCache.entries[1] }; mock.layoutCache.stamp = 2;
mock.mirror.rows[1].instanceId = 11; mock.mirror.rows[1].identity = zero;
desired = { { itemId = 100, count = 2 } };
now = now + 20; rc.tick();
assert(#queue == 1 and queue[1].instanceId == 11 and queue[1].count == 1, 'pair adds only the unbound copy');
print('OK -- instance protocol, movement races, legacy fallback and reconciliation');

-- The tab may fetch a v1 layout before HELLO. Negotiation MUST replace it,
-- otherwise the UI never gets state/location and cannot show In bags.
vc._reset(); vc.noteJob(1); vc.requestLayout(0); tick();
assert(vc._st().pending.op == vc.op.LAYOUT_LIST);
reply(w16(0) .. w16(0));
assert(vc.layoutCache.fresh);
vc.refresh(); tick(); tick();
reply(w16(1) .. w16(1) .. w32(0) .. string.char(15,124,62,0) .. w32(10) .. string.char(13,12,41,30));
assert(not vc.layoutCache.fresh and vc._st().layoutWant, 'HELLO retires pre-negotiation layout');
reply(header(0)); tick();
assert(vc._st().pending.op == vc.op.LAYOUT_LIST2);
reply(header(1) .. layoutRow(9, 55, 100, 0, 2));
assert(vc.layoutCache.entries[1].state == 2, 'refreshed row carries outside state');

local derive = require(base .. 'derive');
local sets = { Dynamic = { Idle = { Head = { { gear = { Id = 100, Name = 'Augmented', AugKey = '1:5' }, minLevel = 5 } } } } };
local triggers = { Default = { { equip = { Body = { Id = 200, Name = 'Trigger gear' } } } } };
local d = derive.derive(sets, triggers);
assert(d.cleanupSafe and d.referencedIds[100] and d.referencedIds[200], 'augmented and inline trigger references protect gear');
local resolved = derive.derive({ Idle = { Head = 'Named gear' } },
    { Default = { { equip = { Body = 'Named augment' } } } },
    function(name) return { id = name == 'Named gear' and 300 or 400, aug = name == 'Named augment' }; end);
assert(resolved.cleanupSafe and resolved.referencedIds[300] and resolved.referencedIds[400],
    'resolved string names protect both normal and augmented copies');
assert(not derive.derive({ Dynamic = { Idle = { Head = { 'dlac:AutoRefresh' } } } }, {}).cleanupSafe);
assert(not derive.derive({ Idle = { Head = 'Unresolved' } }, {}).cleanupSafe);
assert(not derive.derive(nil, {}).cleanupSafe and not derive.derive({}, nil).cleanupSafe);
local missing = {}; setmetatable(missing, { __index = function() return missing; end });
assert(not derive.derive({ Dynamic = { Idle = { Head = { missing } } } }, {}).cleanupSafe);

local rows = {};
for i = 1, 7 do rows[i] = { itemId = i * 100, instanceId = i, ordinal = i, kind = 0, state = 1, count = 1, identity = zero }; end
rows[3].pinned = true; rows[5].state = 2; rows[6].kind = 2;
mock.layoutCache = { entries = rows, stamp = 10, fresh = true, job = 1 };
mock.mirror = { rows = {}, counts = {}, fresh = true, stamp = 10 };
mock.requestLayout = function() end;
queue = {}; local town = true;
local deps = { vc = mock, clock = function() return now; end, mainJob = function() return 1; end,
    setsRoot = function() return sets; end, triggers = function() return triggers; end, derive = derive,
    inTown = function() return town; end, worn = function() return { ['i:4'] = true }; end,
    capacity = function() return 80; end };
rc._reset(); rc.configure(deps); town = false; now = now + 20; rc.tick(); assert(#queue == 0);
town = true; now = now + 20; rc.tick();
assert(#queue == 1 and queue[1].instanceId == 7 and queue[1].job == 1 and queue[1].verb == vc.verb.REMOVE,
    'cleanup removes only unused unpinned unworn rows, preserving outside and review assignments');
assert(rc.retireBlocked(200) and not rc.retireBlocked(700), 'direct triggers block explicit retirement');
triggers = { Default = { { equip = { Body = 'Named trigger gear' } } } };
deps.resolve = function() return { id = 700 }; end;
assert(rc.retireBlocked(700), 'resolved trigger strings block retirement too');
print('OK -- pre-HELLO layout refresh and unused-gear safeguards');

local sm = require('dlac\\gear\\setmanager');
local generic = { Id = 100, Name = 'Hat' };
local roll = { Id = 100, Name = 'Hat', AugKey = '1:5' };
local other = { Id = 100, Name = 'Hat', AugKey = '2:5' };
local source = { Head = { generic, { gear = roll, minLevel = 5 }, other } };
local working = { Head = { { rec = roll }, { rec = roll, minLevel = 5 }, { rec = other } } };
assert(sm.removeItemCandidates(working, source, 100, '1:5', function() return true; end));
assert(#working.Head == 1 and working.Head[1].rec == other, 'remove generic and matching augment only');
working = { Head = { { rec = generic }, { rec = roll } } };
local changed, why = sm.removeItemCandidates(working, { Head = { generic, other } }, 100, '', function() return true; end);
assert(changed == nil and why == 'unavailable augmented copy' and #working.Head == 2,
    'unavailable retained roll blocks the edit before mutating any candidates');

fresh();
local depositError;
vc.requestDeposit({ { container = 0, slot = 1, expectedInstanceId = 10 } }, function(_, e) depositError = e; end);
vc.invalidateInstances(); tick();
assert(depositError == 'location_changed' and #vc._st().depositQ == 0,
    'retirement never deposits from a slot invalidated while queued');
print('OK -- augment-preserving set edits and verified deposits');

-- Run real vault transitions against the shared gate with immediate replies.
-- HELM competes for exactly the same opcode budget. No read, page, write or
-- timeout retry may bypass it, and waiting for the gate is not a timeout.
local transport = require('dlac\\servers\\ascensionxi\\transport');
local helm = require('dlac\\servers\\ascensionxi\\modules\\helm\\status');
local transmissions = {};
now = 1000; transport._clock = function() return now; end;
transport._reset();
transport._send = function(packet) transmissions[#transmissions + 1] = { at = now, packet = packet }; return true; end;
vc._send = function(packet) return transport.send(packet, 'test vault'); end;
vc._received = transport.received;
transport._audit = nil;
helm._clock = function() return now; end;
helm._send = function(packet) return transport.send(packet, 'test HELM'); end;
vc._reset(); vc.noteJob(1); vc.refresh(); vc.pump(true);
local hello = w16(1) .. w16(1) .. w32(2) .. string.char(15,124,62,0) .. w32(10) .. string.char(13,12,41,30);
reply(hello, 0, 0, true);
assert(#transmissions == 1 and vc._st().pending.sentAt == nil);
helm.reset(); helm.touch(); assert(#transmissions == 1);
now = now + 0.1; vc.pump(true); assert(#transmissions == 1);
now = now + 0.26; helm.touch(); assert(#transmissions == 2 and transmissions[2].packet[5] == 0x80);
vc.pump(true); assert(vc._st().pending.sentAt == nil and vc._st().pending.retries == 0);
transport.received(0x80, transmissions[2].packet[6]);
now = now + 0.36; vc.pump(true);
assert(transmissions[3].packet[5] == vc.op.LIST2);
reply(header(1) .. listRow(10, 100), 1, 0, true);
assert(#transmissions == 3);
now = now + 0.36; vc.pump(true); reply(header(1) .. listRow(11, 100), 0, 0, true);
now = now + 0.36; vc.pump(true);
assert(vc._st().pending.op == vc.op.LAYOUT_LIST2);
reply(header(1) .. layoutRow(1, 10, 100), 1, 0, true);
local beforePage = #transmissions; vc.pump(true); assert(#transmissions == beforePage);
now = now + 0.36; vc.pump(true); reply(header(1) .. layoutRow(2, 11, 100), 0, 0, true);
now = now + 0.36; vc.pump(true);
assert(vc._st().pending.op == vc.op.LOST_LIST);
reply(w16(1) .. w16(0) .. w32(90) .. w16(300) .. string.char(1, 0) .. w32(0) .. w32(0), 1, 0, true);
beforePage = #transmissions; vc.pump(true); assert(#transmissions == beforePage);
now = now + 0.36; vc.pump(true); reply(w16(0) .. w16(0), 0, 0, true);
vc.requestLayoutSet({ verb = vc.verb.PIN, instanceId = 10, itemId = 100, pinned = true });
now = now + 0.36; vc.pump(true);
local writeSeq = vc._st().pending.seq;
now = now + vc.SEND_TIMEOUT + 0.01; vc.pump(true);
assert(vc._st().pending.seq == writeSeq and vc._st().pending.retries == 1, 'dropped write retry preserves its sequence');
reply(w16(0) .. w16(1) .. w32(10) .. w32(10), 0, 0, true);
for i = 2, #transmissions do
    assert(transmissions[i].at - transmissions[i - 1].at >= 0.35, 'every actual 0x1E0 send observes shared gap');
end
-- If another producer takes the channel, a prepared but unsent write must
-- still be cancelled on a job edge; it has not entered the replay contract.
now = now + 0.36; assert(transport.send({ 0,0,0,0,0x80 }, 'test HELM'));
vc.requestLayoutSet({ verb = vc.verb.REMOVE, instanceId = 10, itemId = 100 });
vc.pump(true); assert(vc._st().pending and not vc._st().pending.sentAt);
local beforeCancel = #transmissions;
vc.noteJob(2); now = now + 0.36; vc.pump(true);
assert(#transmissions == beforeCancel, 'job change cancels writes still waiting for shared pacing');
print('OK -- shared 350ms pacing for HELLO, pages, HELM, writes and same-sequence retries');

-- Injection calls can sit in Ashita's outgoing queue. A second producer
-- must wait for the server's reply, not just for an injection-time interval.
transport._reset(); transmissions = {}; now = 2000;
assert(transport.send({0,0,0,0,0x80,1}, 'HELM'));
now = now + 0.4;
assert(not transport.send({0,0,0,0,0x40,2}, 'vault'),
    'do not queue another producer while the previous request could still be buffered');
now = now + 0.6; transport.received(0x80, 1);
assert(not transport.send({0,0,0,0,0x40,2}, 'vault'), 'reply arrival starts the cooldown');
now = now + 0.1;
assert(not transport.send({0,0,0,0,0x40,2}, 'vault'), '100ms alone is still within client cooldown');
now = now + 0.26; assert(transport.send({0,0,0,0,0x40,2}, 'vault'));
now = now + 1.5; assert(transport.send({0,0,0,0,0x40,2}, 'vault retry'), 'same-sequence retry is allowed');
now = now + 0.4; assert(not transport.send({0,0,0,0,0x80,3}, 'HELM'));
now = now + transport.MAX_WAIT; assert(transport.send({0,0,0,0,0x80,3}, 'HELM'), 'lost peer cannot stall channel forever');
print('OK -- cross-producer reply serialization and post-reply cooldown');
