-- lua tests/gearvault_live.lua -- the 2026-09-30 live-sync round
-- (docs/design/gear-vault-live-sync.md): the staleness bugs the audit
-- reproduced, the city rule, pushes, streamed reads, and the write-retry
-- laws that keep a lost frame from ever becoming a second operation.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local base = 'dlac\\servers\\ascensionxi\\modules\\gearvault\\';
local vc = require(base .. 'vaultclient');
local rc = require(base .. 'reconcile');
local w16, w32, zero = vc._wu16, vc._wu32, vc.ZERO24;

local failures, checks = 0, 0;
local function check(name, got, want)
    checks = checks + 1;
    if got ~= want then
        failures = failures + 1;
        print(string.format('FAIL %s: got %s, want %s', name, tostring(got), tostring(want)));
    end
end

local now, sent = 1000, {};
vc._clock = function() return now; end;
vc._send = function(p) sent[#sent + 1] = p; return true; end;
vc._say = function() end;
local zone = { v = nil };          -- the vault-zone prediction (nil = unknown)
vc._vaultZone = function() return zone.v; end;
local function tick(dt) now = now + (dt or 0.2); vc.pump(true); end
local function last() return sent[#sent]; end
local function frame(status, flags, payload)
    local p = assert(vc._st().pending, 'expected a pending request');
    return vc.onFrame({ op = p.op, seq = p.seq, status = status or 0, flags = flags or 0, payload = payload or '' });
end
local function reply(payload, flags)
    frame(0, flags, payload);
    local p = vc._st().pending;
    if p and p.sentAt == nil then tick(); end
end
-- HELLO: proto 1, caps, count, v1 limits, revision, v2 limits
local function hello(caps, count, rev)
    return w16(1) .. w16(caps) .. w32(count or 0) .. string.char(15, 62, 62, 0) .. w32(rev or 10)
        .. string.char(13, 12, 41, 30);
end
local function listRow(rowId, item, inst) return w32(rowId) .. w16(item) .. w16(1) .. w32(inst or rowId) .. zero; end
local function list2(rows, rev) return w16(#rows) .. w16(0) .. w32(rev or 10) .. table.concat(rows); end
local function layoutRow(ord, item, inst)
    return w16(ord) .. w16(item) .. w16(1) .. string.char(0, 0) .. w32(inst or 0)
        .. string.char(0, 1, 8, ord) .. zero;
end
local function layout2(rows, rev) return w16(#rows) .. w16(0) .. w32(rev or 10) .. table.concat(rows); end
local function pushFrame(scope, rev, jobs, count, pulled, evicted)
    return { op = vc.op.CHANGED, seq = 0, status = 0, flags = 0,
             payload = w16(scope) .. w16(0) .. w32(rev or 10) .. w32(jobs or 0) .. w32(count or 0)
                 .. w16(pulled or 0) .. w16(evicted or 0) .. w32(1) };
end

-- A synced instance-mode client: HELLO (caps given), 1 vault row, empty layout.
local function boot(caps, rows)
    vc._reset(); rc._reset(); sent = {}; now = now + 100; zone.v = nil;
    vc.noteJob(1); vc.refresh(); tick();
    assert(last()[5] == vc.op.HELLO, 'boot opens with HELLO');
    reply(hello(caps or 1, #(rows or { 1 }), 10));
    assert(vc._st().pending and vc._st().pending.op == vc.op.LIST2, 'boot lists');
    local r = {};
    for _, x in ipairs(rows or { { 1, 100 } }) do r[#r + 1] = listRow(x[1], x[2]); end
    reply(list2(r, 10));
    vc.requestLayout(0); tick();
    assert(vc._st().pending and vc._st().pending.op == vc.op.LAYOUT_LIST2, 'boot reads the layout');
    reply(layout2({}, 10));
    tick();
    if vc._st().pending and vc._st().pending.op == vc.op.LOST_LIST then reply(w16(0) .. w16(0)); end
    assert(vc.mirror.fresh and vc.layoutCache.fresh, 'boot ends fresh');
end

-- ---- the HELLO request carries our caps; the reply's caps negotiate ----
boot(1 + 4 + 8);
check('LV1 HELLO asks for pushes (request word @2)', (function()
    local p = vc.helloPayload(); return p:byte(3) + p:byte(4) * 256;
end)(), vc.CLIENT_CAPS);
check('LV2 push negotiated', vc.limits.push, true);
check('LV3 stream negotiated', vc.limits.stream, true);
check('LV4 subscribed after HELLO', vc.live(), true);
check('LV5 an old server reads neither', (function()
    local h = vc.parseHello(hello(1, 0, 10)); return (h.push or false) or (h.stream or false);
end)(), false);

-- ---- seq: never 0 (pushes own it), seedable ----
vc.seedSeq(254);
check('LV6 seq wraps past 255 to 1, never 0', (function()
    local s = {};
    for i = 1, 3 do vc.requestLayout(0); vc.invalidateLayout(); tick(); s[i] = last()[6]; reply(layout2({}, 10)); end
    return s[1] == 255 and s[2] == 1 and s[3] == 2;
end)(), true);

-- ---- A: Sync cuts through a backoff ----
boot(1);
vc.markStale(0, 'test'); tick();
frame(vc.status.BUSY);                    -- refused: backoff
check('LV10 a refused sync backs off', vc._st().staleAt > now + 5, true);
local before = #sent;
vc.refresh(); tick();
check('LV11 Sync sends NOW, over the backoff', #sent == before + 1 and last()[5] == vc.op.HELLO, true);

-- ---- B: a reason that lands while a read is in flight is not lost ----
boot(1);
vc.markStale(0, 'test'); tick();
check('LV12 a sync is on the wire', last()[5], vc.op.HELLO);
reply(hello(1, 1, 11));                   -- -> LIST2
vc.noteJob(3);                            -- the job changes mid-read
reply(list2({ listRow(1, 100) }, 11));
check('LV13 the pre-change read does not certify the mirror', vc.mirror.fresh, false);
before = #sent;
for _ = 1, 10 do tick(0.2); if vc._st().pending and vc._st().pending.op == vc.op.LAYOUT_LIST2 then reply(layout2({}, 11)); end end
check('LV14 ...and a follow-up read runs', (function()
    for i = before + 1, #sent do if sent[i][5] == vc.op.HELLO then return true; end end
    return false;
end)(), true);

-- ---- C: a job change never re-syncs as a count-only probe ----
boot(1);
vc.noteZoneIn();
vc.noteJob(5);
check('LV15 a job change clears probe mode', vc._st().probeOnly == true, false);

-- ---- D2: the probe compares the revision the rows were LISTED at ----
boot(1);                                  -- listed at revision 10
vc.noteRevision(14);                      -- a layout page / lookup moved the running revision
vc.noteZoneIn(); now = now + vc.SETTLE_ZONE_OLD + 0.1; vc.pump(true);
check('LV16 the probe HELLO leaves', last()[5], vc.op.HELLO);
reply(hello(1, 1, 14));                   -- same count, revision 14 (count-neutral change)
check('LV17 a moved revision escalates to a full LIST', vc._st().pending ~= nil and vc._st().pending.op, vc.op.LIST2);

-- ---- the field holds still; a city probes (Henrik 2026-09-30) ----
boot(1);
zone.v = false;                           -- landed in the field
vc.noteZoneIn(); before = #sent;
for _ = 1, 40 do tick(0.25); end
check('LV20 no probe in the field', #sent, before);
check('LV21 ...the mirror stays trusted', vc.mirror.fresh, true);
local okInv = vc.noteInventory(0x020, string.rep('\0', 12) .. w16(100) .. string.char(8, 1, 0) .. string.rep('\0', 24));
check('LV22 a field bag move forgets its slot only', okInv, true);
check('LV23 ...and never re-reads the layout in the field', vc.layoutCache.fresh, true);
zone.v = true;                            -- walked into a city
vc.noteZoneIn(); now = now + vc.SETTLE_ZONE_OLD + 0.1; vc.pump(true);
check('LV24 a city probes', last()[5], vc.op.HELLO);

-- ---- gear swaps are not inventory changes ----
boot(1);
vc.layoutCache.entries = { { ordinal = 1, itemId = 555, instanceId = 7, kind = 0, state = 1 } };
vc._readSlot = function(c, s) return (c == 8 and s == 3) and 555 or 0; end;
local lockOnly = string.rep('\0', 4) .. w32(1) .. w16(555) .. string.char(8, 3, 5);   -- 0x01F, same item, lock flag
check('LV25 an equip lock flag changes nothing', vc.noteInventory(0x01F, lockOnly), false);
check('LV26 ...the layout stays fresh', vc.layoutCache.fresh, true);
local moved = string.rep('\0', 4) .. w32(1) .. w16(0) .. string.char(8, 3, 0);        -- 0x01F, slot emptied
check('LV27 a laid-out piece leaving its slot counts', vc.noteInventory(0x01F, moved), true);
check('LV28 ...and re-reads the layout', vc.layoutCache.fresh, false);
vc._readSlot = nil;

-- ---- pushes: T2, and what each scope asks for ----
boot(1 + 4);
local transport = require('dlac\\servers\\ascensionxi\\transport');
transport._reset(); transport._audit = nil;
transport._clock = function() return now; end;
transport._send = function() return true; end;
vc._received = transport.received; vc._abandon = transport.abandon; vc._notePush = transport.notePush;
vc.noteVaultChat();                       -- a guess: resync in SETTLE_CHAT
local guessAt = vc._st().staleAt;
check('LV30 a push is ours and blocked', vc.onFrame(pushFrame(vc.change.VAULT, 12, 0, 2)), true);
check('LV31 ...it pulls the read EARLIER than the guess', vc._st().staleAt < guessAt, true);
assert(transport.send({ 0,0,0,0,0x80,9 }, 'HELM'));
vc.onFrame(pushFrame(vc.change.VAULT, 12, 0, 2));
check('LV32 a push never answers the pending request (T2)', transport.send({ 0,0,0,0,0x40,10 }, 'vault'), false);
transport._reset();
vc._received, vc._abandon, vc._notePush = nil, nil, nil;
boot(1 + 4);
vc.onFrame(pushFrame(vc.change.LAYOUT, 10, 2 ^ 1));
check('LV33 a LAYOUT push for my job re-reads the layout', vc._st().layoutWant ~= nil and not vc.layoutCache.fresh, true);
boot(1 + 4);
vc.onFrame(pushFrame(vc.change.LAYOUT, 10, 2 ^ 7));
check('LV34 ...another job\'s leaves mine alone', vc.layoutCache.fresh, true);
boot(1 + 4);
vc.onFrame(pushFrame(vc.change.APPLIED, 10, 0, 1, 2, 1));
check('LV35 an apply that moved copies re-reads both', vc.mirror.fresh == false and not vc.layoutCache.fresh, true);
boot(1 + 4);
vc.onFrame(pushFrame(vc.change.APPLIED, 10, 0, 1, 0, 0));
check('LV35a an apply that moved nothing (most zone lines) changes neither view',
    vc.mirror.fresh == true and vc.layoutCache.fresh == true, true);
boot(1 + 4);
vc.onFrame(pushFrame(vc.change.LOST, 10));
check('LV36 a LOST push re-reads the lost list', vc._st().lostWant, true);
-- unattuned: ATTUNE pulls the re-check to now
vc._reset(); sent = {}; vc.noteJob(1); vc.refresh(); tick();
frame(vc.status.NOT_ATTUNED);
check('LV37 un-attuned', vc.state(), 'unattuned');
vc.onFrame(pushFrame(vc.change.ATTUNE, 0));
before = #sent; tick();
check('LV38 ATTUNE asks right away', #sent == before + 1 and last()[5] == vc.op.HELLO, true);

-- ---- streamed reads: one request, many frames, duplicates skipped ----
boot(1 + 8);
vc.markStale(0, 'test'); tick();
reply(hello(1 + 8, 3, 20));
local listReq = last();
check('LV40 a streamed LIST2 carries flags + frame count', #listReq >= 14 and listReq[13] == 1 and listReq[14] == vc.STREAM_FRAMES, true);
frame(0, vc.FLAG_FOLLOWS, list2({ listRow(1, 100), listRow(2, 101) }, 20));
check('LV41 a FOLLOWS frame keeps the request open', vc._st().pending ~= nil, true);
frame(0, vc.FLAG_FOLLOWS, list2({ listRow(1, 100), listRow(2, 101) }, 20));   -- a retry's duplicate
frame(0, 0, list2({ listRow(3, 102) }, 20));
check('LV42 one request, three rows, no duplicates', #vc.mirror.rows == 3 and vc.mirror.fresh, true);
local listSends = 0;
for _, p in ipairs(sent) do if p[5] == vc.op.LIST2 then listSends = listSends + 1; end end
check('LV43 ...on one LIST2 request', listSends, 2);   -- boot's + this one

-- ---- the layout read no longer restarts under churn ----
boot(1);
vc.requestLayout(0); vc.invalidateLayout(); tick();
frame(0, vc.FLAG_MORE, layout2({ layoutRow(1, 300, 9) }, 10));
vc.invalidateLayout(vc.SETTLE_LAYOUT);   -- churn while the pages are on the wire
tick();
check('LV44 the chain continues to its end', last()[5], vc.op.LAYOUT_LIST2);
reply(layout2({ layoutRow(2, 301, 10) }, 10));
check('LV45 the snapshot is shown, marked stale, and asked once more',
    #vc.layoutCache.entries == 2 and vc.layoutCache.fresh == false and vc._st().layoutWant ~= nil, true);

-- ---- the lost list follows the revision, not bag churn ----
boot(1);
vc.lost = { entries = {}, fresh = true, revision = vc.revision };
vc.invalidateInstances();
check('LV46 bag churn does not re-read the lost list', vc.requestLost() and vc._st().lostWant == nil, true);

-- ---- writes: same seq, inside the replay window, never re-sent after ----
boot(1);
local werr;
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function(_, e) werr = e; end);
tick();
local wseq, first = last()[6], #sent;
local sendsAt = { now };
for _ = 1, 20 do tick(0.25); if #sent > first + #sendsAt - 1 and sent[#sent][5] == vc.op.WITHDRAW then sendsAt[#sendsAt + 1] = now; end end
local writes, sameSeq = 0, true;
for i = first, #sent do
    if sent[i][5] == vc.op.WITHDRAW then writes = writes + 1; if sent[i][6] ~= wseq then sameSeq = false; end end
end
check('LV50 a lost write is sent 1 + MAX_RETRIES times', writes, 1 + vc.MAX_RETRIES);
check('LV51 ...always with the SAME seq', sameSeq, true);
check('LV52 ...the last retry inside the 5 s replay window', vc.SEND_TIMEOUT * vc.MAX_RETRIES < 4.0, true);
check('LV53 ...then outcome unknown', werr, 'timeout');
check('LV54 ...and a re-read, never a fresh-seq resend', vc.mirror.fresh, false);

-- a write on the wire at a zone line is never retried into another process
boot(1);
werr = nil;
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function(_, e) werr = e; end);
tick();
local zseq = last()[6];
vc.noteZoneIn();
for _ = 1, 20 do tick(0.3); end
local resent = false;
for _, p in ipairs(sent) do if p[5] == vc.op.WITHDRAW and p[6] == zseq and p ~= sent[#sent] then end end
local count = 0;
for _, p in ipairs(sent) do if p[5] == vc.op.WITHDRAW then count = count + 1; end end
check('LV55 a write lost at a zone line is reported, not re-sent', werr == 'timeout' and count == 1, true);

-- ---- deposits: one ack frame's worth, and the layout only when it names them ----
boot(1);
check('LV60 depositCap never above 62', vc.depositCap(), 62);
local many = {};
for i = 1, 63 do many[i] = { container = 0, slot = i }; end
check('LV61 a 63-entry deposit is refused client-side', vc.requestDeposit(many, function() end), false);
vc.layoutCache.entries = { { ordinal = 1, itemId = 555, instanceId = 7, kind = 0, state = 1 } };
vc._readSlot = function(c, s) return (s == 1) and 777 or 555; end;
vc.requestDeposit({ { container = 0, slot = 1 } }, function() end); tick();
reply(w16(1) .. w16(0) .. string.char(0, 1) .. w16(0) .. w32(50));
check('LV62 a stored piece the layout does not name leaves it fresh', vc.layoutCache.fresh, true);
vc.requestDeposit({ { container = 0, slot = 2 } }, function() end);
for _ = 1, 30 do
    local p = vc._st().pending;
    if p and p.op == vc.op.DEPOSIT then break; end
    if p and p.op == vc.op.HELLO then reply(hello(1, 2, 10)); elseif p and p.op == vc.op.LIST2 then reply(list2({ listRow(1, 100), listRow(50, 777) }, 10));
    elseif p and p.op == vc.op.LOST_LIST then reply(w16(0) .. w16(0)); else tick(); end
end
reply(w16(1) .. w16(0) .. string.char(0, 2) .. w16(0) .. w32(51));
check('LV63 a stored piece the layout names marks the layout stale', vc.layoutCache.fresh, false);
vc._readSlot = nil;

-- ---- the counter trade (the audit's top staleness bug) ----
boot(1);
vc.noteCounterTrade();
before = #sent;
now = now + vc.SETTLE_CHAT + 0.1; vc.pump(true);
check('LV65 a counter trade re-reads the vault', #sent == before + 1 and last()[5] == vc.op.HELLO, true);

-- ---- readouts ----
boot(1);
check('LV70 a quiet client has no activity', vc.activity(), nil);
check('LV71 ...and no health complaint', vc.health(), nil);
vc.requestLayoutSet({ verb = vc.verb.PIN, instanceId = 1, itemId = 100, pinned = true }, function() end);
check('LV72 queued edits read "edits"', vc.activity(), 'edits');
check('LV73 an in-flight lookup is not "syncing"', (function()
    vc.cancelLayoutSets();
    vc.limits.maxLookup = 41;
    vc.requestLookup({ { container = 8, slot = 1 } }, function() end); tick(); tick(); tick();
    return vc.state();
end)(), 'fresh');

-- ---- character switch ----
boot(1);
vc.resetCharacter();
check('LV75 a new character starts empty', #vc.mirror.rows == 0 and vc.mirror.stamp == nil, true);

-- ---- the layout engine: kicks, the city, the push key ----
local derived = { { itemId = 100, count = 1 } };
local city = { v = true };
local said = {};
local function engine()
    rc._reset();
    rc.configure({ vc = vc, clock = function() return now; end, mainJob = function() return 1; end,
        browsing = function() return false; end, setsRoot = function() return {}; end,
        triggers = function() return {}; end, resolve = function() return nil; end,
        derive = { derive = function() return { items = derived, hash = 'h', cleanupSafe = false, referencedIds = {} }; end },
        lookupById = function() return { Slot = 'Body' }; end, say = function(m) said[#said + 1] = m; end,
        capacity = function() return 0; end, inCity = function() return city.v; end,
        inTown = function() return city.v; end });
end
boot(1, { { 1, 100 } });
engine();
rc._st().lastBeat = now;                  -- a run just happened
check('LV80 a quiet engine waits for its beat', rc.tick(), 'idle');
rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01;
check('LV81 a kick runs it at once', rc.tick(), 'pushed:1');
-- F: a refused add is tried again after RETRY (not parked forever)
tick(); frame(0, 0, w16(vc.code.BUSY) .. w16(0) .. w32(10));
vc.layoutCache.fresh = true;
rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01;
check('LV82 the same refused add is not re-sent at once', rc.tick(), 'clean');
now = now + rc.RETRY + 0.1; rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01;
check('LV83 ...but is after RETRY', rc.tick(), 'pushed:1');
tick(); frame(0, 0, w16(vc.code.OK) .. w16(0) .. w32(10));
-- the field holds the adds (Henrik 2026-09-30); the city sends them
boot(1, { { 1, 100 } });
engine(); city.v = false;
rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01;
check('LV84 in the field the adds wait, unsent', rc.tick(), 'waiting-city');
check('LV85 ...the badge says so', rc.cityBlocked(), true);
check('LV86 ...nothing queued', #(vc._st().layoutSetQ or {}), 0);
for _ = 1, 3 do now = now + rc.BEAT + 0.1; rc.tick(); end
check('LV87 ...and no re-spam while standing there', #(vc._st().layoutSetQ or {}), 0);
city.v = true; rc.zoneArmed(); now = now + rc.KICK_SETTLE + 0.01;
check('LV88 arriving in a city sends them', rc.tick(), 'pushed:1');
tick(); frame(0, 0, w16(vc.code.OK) .. w16(0) .. w32(10));
-- a zone read that lags the zone line's kick never strands the adds
boot(1, { { 1, 100 } });
engine(); city.v = false;
rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01; rc.tick();
rc.zoneArmed(); now = now + rc.KICK_SETTLE + 0.01;
check('LV88b the kick still reads the old zone', rc.tick(), 'waiting-city');
city.v = true; now = now + rc.BEAT + 0.1;
check('LV88c ...the next quiet beat, in the city, sends them', rc.tick(), 'pushed:1');
-- E: the badge clears when nothing waits any more
tick(); frame(0, 0, w16(vc.code.OK) .. w16(0) .. w32(10));
derived = {};
vc.layoutCache.fresh = true; rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01;
check('LV89 nothing to add -> clean', rc.tick(), 'clean');
check('LV90 ...and the city badge is gone', rc.cityBlocked(), false);
-- 'asked-layout' does not spend the run: the layout's commit runs it
derived = { { itemId = 100, count = 1 } };
boot(1, { { 1, 100 } });
engine();
vc.invalidateLayout();
rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01;
check('LV91 a stale layout is asked for', rc.tick(), 'asked-layout');
tick(); reply(layout2({}, 10));
check('LV92 ...and the engine runs as soon as it lands', rc.tick(), 'pushed:1');

-- ---- the Ashita glue (init.lua needs a mounted pack to load, so the
-- contracts are pinned as text -- honest pins of behaviour tested above) ----
do
    local f = io.open('servers/ascensionxi/modules/gearvault/init.lua', 'r');
    local src = (f ~= nil) and f:read('*a') or '';
    if f ~= nil then f:close(); end
    check('LV95 a trade to a "Gear Vault" counter is watched (0x036, index @0x3A)',
        src:find("register('packet_out', 'dlac_gearvault_trade'", 1, true) ~= nil
        and src:find('0x036', 1, true) ~= nil and src:find("== 'Gear Vault'", 1, true) ~= nil
        and src:find('vc.noteCounterTrade()', 1, true) ~= nil, true);
    check('LV96 inventory packets go through the narrow rule, not a global wipe',
        src:find('vc.noteInventory', 1, true) ~= nil
        and src:find('vc.invalidateInstances();\n            if vc.instanceMode() then vc.invalidateLayout', 1, true) == nil, true);
    check('LV97 the vault zone is the city predicate or a counter town',
        src:find('loc.inCity()', 1, true) ~= nil and src:find('vc._vaultZone', 1, true) ~= nil, true);
    check('LV98 a mirror commit kicks the engine and bumps ownership',
        src:find("pcall(rec.kick, 'vault')", 1, true) ~= nil
        and src:find('bumpGeneration()', 1, true) ~= nil, true);
end

if failures > 0 then
    print(string.format('FAIL -- %d of %d checks failed', failures, checks));
    os.exit(1);
end
print(string.format('OK -- %d live-sync checks: city rule, pushes, streams, staleness fixes, write laws', checks));
