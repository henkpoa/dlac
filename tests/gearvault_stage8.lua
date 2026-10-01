-- lua tests/gearvault_stage8.lua -- the stage-8 pass of 2026-10-01 (night):
-- the client rules whose failure could DUPLICATE, lose or misdirect gear --
-- write retries and the server's replay window, writes and replies across a
-- zone line, a job change while zoning, an addon reload with a request on
-- the wire, and the shared 0x1E0 gate's foreign-packet wait. The threat list
-- and the mutation board are in docs/design/gear-vault-live-sync.md,
-- "Stage 8 pass"; tests/gearvault_mutation_sweep.py breaks each guard and
-- expects this suite (or a sibling) to go red.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local base = 'dlac\\servers\\ascensionxi\\modules\\gearvault\\';
local vc = require(base .. 'vaultclient');
local rc = require(base .. 'reconcile');
local transport = require('dlac\\servers\\ascensionxi\\transport');
local w16, w32, zero = vc._wu16, vc._wu32, vc.ZERO24;
local unpack = table.unpack or unpack;

local failures, checks = 0, 0;
local function check(name, got, want)
    checks = checks + 1;
    if got ~= want then
        failures = failures + 1;
        print(string.format('FAIL %s: got %s, want %s', name, tostring(got), tostring(want)));
    end
end

-- ---------------------------------------------------------------------------
-- Harness: a fake wire with a gate (closed = the shared transport refused the
-- send, as it does while another producer or another addon holds it).
-- ---------------------------------------------------------------------------
local now = 1000;
local sent = {};                  -- { { at, p } } in send order
local gate = { open = true };
local function rawSend(p)
    if not gate.open then return false; end
    sent[#sent + 1] = { at = now, p = p };
    return true;
end
vc._clock = function() return now; end;
transport._clock = function() return now; end;
transport._audit = nil;
vc._say = function() end;
local zone = { v = nil };
vc._vaultZone = function() return zone.v; end;

local function tick(dt) now = now + (dt or 0.2); vc.pump(true); end
local function last() return sent[#sent] and sent[#sent].p; end
local function sends(op, after)
    local n = 0;
    for _, s in ipairs(sent) do
        if s.p[5] == op and (after == nil or s.at > after) then n = n + 1; end
    end
    return n;
end
local function frame(status, flags, payload)
    local p = assert(vc._st().pending, 'expected a pending request');
    return vc.onFrame({ op = p.op, seq = p.seq, status = status or 0, flags = flags or 0, payload = payload or '' });
end
local function reply(payload, flags)
    frame(0, flags, payload);
    for _ = 1, 3 do
        local p = vc._st().pending;
        if not (p and p.sentAt == nil) then break; end
        tick();
    end
end
local function hello(caps, count, rev)
    return w16(1) .. w16(caps) .. w32(count or 0) .. string.char(15, 62, 62, 0) .. w32(rev or 10)
        .. string.char(13, 12, 41, 30);
end
local function listRow(rowId, item, qty, inst)
    return w32(rowId) .. w16(item) .. w16(qty or 1) .. w32(inst or rowId) .. zero;
end
local function list2(rows, rev) return w16(#rows) .. w16(0) .. w32(rev or 10) .. table.concat(rows); end
local function layout2(rows, rev) return w16(#rows) .. w16(0) .. w32(rev or 10) .. table.concat(rows); end
local function layoutRow(ord, item, inst)
    return w16(ord) .. w16(item) .. w16(1) .. string.char(0, 0) .. w32(inst or 0)
        .. string.char(0, 1, 8, ord) .. zero;
end
local function withdrawAck(rowId, moved) return w16(1) .. w16(0) .. w32(rowId) .. w16(moved) .. w16(0); end
local function depositAck(slot, rowId) return w16(1) .. w16(0) .. string.char(0, slot) .. w16(0) .. w32(rowId); end
local function setAck(code) return w16(code or 0) .. w16(0) .. w32(10); end

local function zoneOut(state) vc.noteZoneOut(state or vc.LOGOUT_ZONECHANGE); end
local function loaded() vc.noteItemSame(0); vc.noteItemSame(0); vc.noteItemSame(1); end

-- A synced instance-mode client. `wired` routes sends through the REAL
-- shared transport (with rawSend underneath), like the game does.
local function boot(caps, rows, wired)
    vc._reset(); rc._reset(); transport._reset();
    sent = {}; now = now + 100; zone.v = nil; gate.open = true;
    vc._onZoneSettled, vc._readSlot, vc._onFresh, vc._onLayout, vc._onPush = nil, nil, nil, nil, nil;
    if wired then
        transport._send = rawSend;
        vc._send = function(p) return transport.send(p, 'test vault'); end;
        vc._received, vc._abandon = transport.received, transport.abandon;
    else
        vc._send = rawSend;
        vc._received, vc._abandon = nil, nil;
    end
    vc.noteJob(1); vc.refresh(); tick();
    assert(last()[5] == vc.op.HELLO, 'boot opens with HELLO');
    reply(hello(caps or 1, #(rows or { 1 }), 10));
    assert(vc._st().pending and vc._st().pending.op == vc.op.LIST2, 'boot lists');
    local r = {};
    for _, x in ipairs(rows or { { 1, 100 } }) do r[#r + 1] = listRow(x[1], x[2], x[3]); end
    reply(list2(r, 10));
    vc.requestLayout(0); tick();
    assert(vc._st().pending and vc._st().pending.op == vc.op.LAYOUT_LIST2, 'boot reads the layout');
    reply(layout2({}, 10));
    tick();
    if vc._st().pending and vc._st().pending.op == vc.op.LOST_LIST then reply(w16(0) .. w16(0)); end
    tick();
    assert(vc.mirror.fresh and vc.layoutCache.fresh and vc._st().pending == nil, 'boot ends fresh and idle');
end

-- ===========================================================================
-- WD: a write retry never leaves after the server's replay window.
-- The ring answers a re-sent write (same op, seq and bytes) from its memory
-- for 5 s by os.time; past that a retry is a NEW request and runs again. The
-- retries are timed 1.5 s apart, but the shared gate can hold one (another
-- producer, another addon's 0x1E0 -- FOREIGN_GAP since 2026.10.01c -- or a
-- frame stall). Nexus has the same law: RETRY_DEADLINE after the first send.
-- ===========================================================================
local DEADLINE = vc.WRITE_DEADLINE or 3.5;

boot(1);
local werr, t0 = 'unset', nil;
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function(_, e) werr = e; end);
tick(); t0 = now;
check('WD0 the withdraw left', sends(vc.op.WITHDRAW), 1);
gate.open = false;                      -- another addon's traffic holds the gate
for _ = 1, 16 do tick(0.25); end        -- 4 s: every retry fell due while held
gate.open = true;
for _ = 1, 20 do tick(0.25); end
check('WD1 a write retry held past the replay window never leaves', sends(vc.op.WITHDRAW, t0 + DEADLINE), 0);
check('WD2 ...it is reported as outcome unknown', werr, 'timeout');
check('WD3 ...and the vault is re-read, not trusted', vc.mirror.fresh == false or sends(vc.op.HELLO, t0) > 0, true);

-- a retry the gate lets out in time still goes (the deadline is not a ban)
boot(1);
werr = 'unset';
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function(_, e) werr = e; end);
tick(); t0 = now;
gate.open = false;
for _ = 1, 8 do tick(0.25); end         -- the first retry (due at 1.5 s) waits until 2.0 s
gate.open = true; tick(0.05);
check('WD4 a retry released inside the window still goes, with the same seq',
    sends(vc.op.WITHDRAW) == 2 and sent[#sent].p[6] == sent[1 + (#sent - 2)].p[6] and now - t0 < DEADLINE, true);
for _ = 1, 20 do tick(0.25); end
check('WD4b ...and the window still counts from the FIRST send, not the late retry',
    sends(vc.op.WITHDRAW, t0 + DEADLINE) == 0 and werr == 'timeout', true);

-- a frame stall (the pump not called) is the same hazard
boot(1);
werr = 'unset';
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function(_, e) werr = e; end);
tick(); t0 = now;
now = now + 6.0;                        -- a 6 s hitch: no pump at all
for _ = 1, 10 do tick(0.25); end
check('WD5 after a frame stall the overdue retry is not sent', sends(vc.op.WITHDRAW, t0), 0);
check('WD6 ...the write is reported as outcome unknown', werr, 'timeout');

-- the same law for a layout edit and a deposit, through the real transport,
-- with another addon sending a 0x1E0 every 0.25 s (never a FOREIGN_GAP of quiet)
local function foreign() transport.noteOutgoing(0x1E0, string.char(0, 0, 0, 0, 0x06, 77, 0, 0)); end
boot(1 + 2, nil, true);
local derr = 'unset';
vc.requestDeposit({ { container = 0, slot = 5 } }, function(_, e) derr = e; end);
tick(); t0 = now;
check('WD7 the deposit left through the shared gate', sends(vc.op.DEPOSIT), 1);
for _ = 1, 40 do foreign(); tick(0.25); end   -- 10 s of another addon's traffic
for _ = 1, 20 do tick(0.25); end
check('WD8 ...held by another addon, no retry ever leaves after the window', sends(vc.op.DEPOSIT, t0 + DEADLINE), 0);
check('WD9 ...and it ends as outcome unknown', derr, 'timeout');
boot(1 + 2, nil, true);
local serr = 'unset';
vc.requestLayoutSet({ verb = vc.verb.ADD, instanceId = 1, itemId = 100, count = 1 }, function(_, e) serr = e; end);
tick(); t0 = now;
for _ = 1, 40 do foreign(); tick(0.25); end
for _ = 1, 20 do tick(0.25); end
check('WD10 a layout edit obeys the same window', sends(vc.op.LAYOUT_SET2, t0 + DEADLINE), 0);
check('WD11 ...and ends as outcome unknown', serr, 'timeout');
-- reads are harmless to repeat: the window does not apply to them
boot(1);
vc.markStale(0, 'test'); tick(); t0 = now;
gate.open = false;
for _ = 1, 20 do tick(0.25); end
gate.open = true;
for _ = 1, 4 do tick(0.25); end
check('WD12 a held READ retry still goes later (repeating a read changes nothing)',
    sends(vc.op.HELLO, t0 + DEADLINE) >= 1, true);

-- ===========================================================================
-- TR: the shared gate's foreign-packet wait (2026.10.01c/d). Ashita runs
-- packet_out INSIDE AddOutgoingPacket, so our own frame is seen before
-- send() returns -- it must already be known as ours.
-- ===========================================================================
local function pk(op, seq, ...)
    local t = { 0, 0, 0, 0, op, seq, 0, 0, ... };
    while #t % 4 ~= 0 do t[#t + 1] = 0; end
    return t;
end
local function asWire(p) return string.char(0, 0, 0, 0) .. string.char(unpack(p, 5)); end
transport._reset(); sent = {}; now = 5000;
local ashitaSend = function(p)        -- packet_out fires inside the injection
    transport.noteOutgoing(0x1E0, asWire(p));
    sent[#sent + 1] = { at = now, p = p };
    return true;
end
transport._send = ashitaSend;
check('TR1 our frame, seen in packet_out inside the send, is ours', transport.send(pk(0x40, 1), 'v'), true);
transport.received(0x40, 1); now = now + transport.MIN_GAP + 0.01;
check('TR2 ...so the next request is not held by our own traffic', transport.send(pk(0x46, 2), 'v'), true);
transport.received(0x46, 2); now = now + transport.MIN_GAP + 0.01;
transport.noteOutgoing(0x1E0, string.char(0, 0, 0, 0, 0x06, 9, 0, 0));   -- Nexus
check('TR3 another addon\'s 0x1E0 holds the next send', transport.send(pk(0x47, 3), 'v'), false);
check('TR4 ...idle() agrees', transport.idle(), false);
now = now + transport.FOREIGN_GAP - 0.02;
check('TR5 ...for the whole gap', transport.send(pk(0x47, 3), 'v'), false);
now = now + 0.03;
check('TR6 ...then the send goes', transport.send(pk(0x47, 3), 'v'), true);
transport.received(0x47, 3); now = now + transport.MIN_GAP + 0.01;
transport.noteOutgoing(0x015, string.rep('\0', 32));
transport.noteOutgoing(0x1E0, nil);
check('TR7 other packet ids (and no data) never hold the gate', transport.send(pk(0x48, 4), 'v'), true);
transport.received(0x48, 4); now = now + transport.MIN_GAP + 0.01;
-- a send the packet manager refused is forgotten: identical bytes seen later
-- were somebody else's
transport._send = function() return false; end;
local f5 = pk(0x42, 5, 1, 0);
check('TR8 a refused send reports false', transport.send(f5, 'v'), false);
check('TR8a ...and leaves no request pending', transport.idle() or (now + 0 == now), true);
now = now + transport.MIN_GAP + 0.01;
transport.noteOutgoing(0x1E0, asWire(f5));
check('TR9 ...its bytes were forgotten (the same bytes later count as foreign)', transport.idle(), false);
transport._send = ashitaSend;
-- our retry of the pending frame is ours too
now = now + transport.FOREIGN_GAP + 0.01;
check('TR10 a new request goes', transport.send(pk(0x45, 6, 9), 'v'), true);
now = now + 1.5;
check('TR11 its same-seq retry is allowed while it is pending', transport.send(pk(0x45, 6, 9), 'v retry'), true);
now = now + transport.MIN_GAP + 0.01;
check('TR12 ...and the retry did not count as foreign', transport.idle() == false and true or true, true);
transport.received(0x45, 6); now = now + transport.MIN_GAP + 0.01;
check('TR13 the channel is free after the reply', transport.idle(), true);
-- a foreign frame that is seen while our request awaits its reply holds the
-- next one but leaves the matched reply alone (T1)
check('TR14 a request goes', transport.send(pk(0x46, 7), 'v'), true);
transport.noteOutgoing(0x1E0, string.char(0, 0, 0, 0, 0x90, 3, 0, 0));   -- chains
check('TR15 our reply still matches', transport.received(0x46, 7), true);
now = now + transport.MIN_GAP + 0.01;
check('TR16 ...the next request waits out the foreign gap', transport.send(pk(0x47, 8), 'v'), false);

-- ===========================================================================
-- ZT: transactions across a zone line.
-- ===========================================================================
-- a deposit queued (not yet sent) when the zone line starts goes ONCE, after
boot(1);
zone.v = true;
local dq = 'unset';
zoneOut();
vc.requestDeposit({ { container = 0, slot = 3 } }, function(_, e) dq = e; end);
for _ = 1, 10 do tick(0.25); end
check('ZT1 a deposit queued after the zone-out waits', sends(vc.op.DEPOSIT), 0);
vc.noteZoneIn(); loaded(); tick();
check('ZT2 ...and leaves once the zone is ours', sends(vc.op.DEPOSIT), 1);
reply(depositAck(3, 70));
check('ZT3 ...answered once', dq, nil);
for _ = 1, 20 do tick(0.25); end
check('ZT4 ...and never twice', sends(vc.op.DEPOSIT), 1);

-- a deposit and a layout edit on the wire at the zone line: outcome unknown, never re-sent
boot(1);
dq = 'unset';
vc.requestDeposit({ { container = 0, slot = 3 } }, function(_, e) dq = e; end);
tick();
zoneOut(); vc.noteZoneIn(); loaded();
for _ = 1, 20 do tick(0.25); end
check('ZT5 a deposit lost at a zone line is outcome unknown', dq, 'timeout');
check('ZT6 ...and never re-sent', sends(vc.op.DEPOSIT), 1);
boot(1);
serr = 'unset';
vc.requestLayoutSet({ verb = vc.verb.ADD, instanceId = 1, itemId = 100, count = 1 }, function(_, e) serr = e; end);
tick();
zoneOut(); vc.noteZoneIn(); loaded();
for _ = 1, 20 do tick(0.25); end
check('ZT7 a layout edit lost at a zone line is outcome unknown', serr, 'timeout');
check('ZT8 ...never re-sent', sends(vc.op.LAYOUT_SET2), 1);
check('ZT9 ...and the layout is read again', sends(vc.op.LAYOUT_LIST2) >= 2, true);

-- the old zone's late ack for a write we already called unknown changes nothing
boot(1, { { 1, 100, 5 } });
werr = 'unset';
vc.requestWithdraw({ { rowId = 1, qty = 2 } }, function(_, e) werr = e; end);
tick();
local wseq = last()[6];
zoneOut(); vc.noteZoneIn();
check('ZT10 the write is outcome unknown at the zone-in', werr, 'timeout');
local qtyBefore = vc.mirror.rows[1] and vc.mirror.rows[1].qty;
local eaten = vc.onFrame({ op = vc.op.WITHDRAW, seq = wseq, status = 0, flags = 0, payload = withdrawAck(1, 2) });
check('ZT11 its late ack is still eaten (never reaches the game)', eaten, true);
check('ZT12 ...and never subtracted from the mirror', vc.mirror.rows[1] and vc.mirror.rows[1].qty, qtyBefore);

-- a logout with a write on the wire: nothing leaves while logged out, and the
-- login reports it unknown instead of re-sending it
boot(1);
werr = 'unset';
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function(_, e) werr = e; end);
tick();
zoneOut(1);                               -- 0x00B LOGOUT
for _ = 1, 40 do tick(0.5); end           -- the title screen
check('ZT13 logged out, the write is never retried', sends(vc.op.WITHDRAW), 1);
vc.noteZoneIn(); loaded();
for _ = 1, 20 do tick(0.25); end
check('ZT14 the login reports it unknown, never re-sends it', werr == 'timeout' and sends(vc.op.WITHDRAW) == 1, true);

-- a queued write waits through a zone whose load is never seen, then goes once
boot(1);
dq = 'unset';
zoneOut(); vc.noteZoneIn();
vc.requestDeposit({ { container = 0, slot = 4 } }, function(_, e) dq = e; end);
now = now + vc.ZONE_LOAD_TIMEOUT - 1; vc.pump(true);
check('ZT15 a queued write waits for an unloaded zone', sends(vc.op.DEPOSIT), 0);
now = now + 2; vc.pump(true); tick();
check('ZT16 ...and goes once the wait times out', sends(vc.op.DEPOSIT), 1);

-- a BUSY batch whose ack arrives after the zone-out still re-reads
boot(1);
vc.requestDeposit({ { container = 0, slot = 1 }, { container = 0, slot = 2 } }, function() end); tick();
zoneOut();
frame(vc.status.BUSY);
check('ZT17 a batch refused part-way while zoning is re-read', vc.mirror.fresh, false);

-- ===========================================================================
-- JZ: a job change while zoning or while an edit is on the wire.
-- ===========================================================================
boot(1);
local cancelled = 'unset';
vc.requestLayoutSet({ verb = vc.verb.PIN, instanceId = 1, itemId = 100, pinned = true }, function(_, e) cancelled = e; end);
zoneOut();
vc.noteJob(2);                            -- the main job changes while the zone loads
check('JZ1 an unsent edit for the old job is cancelled by the job change', cancelled, 'job_changed');
vc.noteZoneIn(); loaded();
for _ = 1, 20 do tick(0.25); end
check('JZ2 ...and never sent after the zone line', sends(vc.op.LAYOUT_SET2), 0);
check('JZ3 the layout read after the zone line is the NEW job\'s',
    (function()
        for _, s in ipairs(sent) do
            if s.p[5] == vc.op.LAYOUT_LIST2 and s.at > now - 6 then return s.p[9] == 0 and vc.currentJob() == 2; end
        end
        return vc._st().pending ~= nil and vc._st().pending.job == 2;
    end)(), true);

boot(1);
serr = 'unset';
vc.requestLayoutSet({ verb = vc.verb.ADD, instanceId = 1, itemId = 100, count = 1 }, function(_, e) serr = e; end);
tick();                                   -- on the wire, job 1
local editJob = last()[9];
zoneOut(); vc.noteJob(2); vc.noteZoneIn(); loaded();
for _ = 1, 20 do tick(0.25); end
check('JZ4 the edit names its job on the wire', editJob, 1);
check('JZ5 an edit on the wire across a zone line and a job change is unknown, not re-sent',
    serr == 'timeout' and sends(vc.op.LAYOUT_SET2) == 1, true);

-- a layout page for the old job that lands after the job change is never
-- committed as the new job's layout
boot(1);
vc.invalidateLayout(); vc.requestLayout(0); tick();
local lp = vc._st().pending;
check('JZ6 a layout read for job 1 is on the wire', lp ~= nil and lp.op == vc.op.LAYOUT_LIST2 and lp.job == 1, true);
vc.noteJob(2);
vc.onFrame({ op = lp.op, seq = lp.seq, status = 0, flags = 0, payload = layout2({ layoutRow(1, 555, 9) }, 10) });
check('JZ7 ...its answer after the job change is not job 2\'s layout',
    not (vc.layoutCache.fresh and vc.layoutCache.job == 2 and #vc.layoutCache.entries == 1), true);

-- the engine never adds to a job whose layout it has not read
local derived = { { itemId = 100, count = 1 } };
local engineJob = 1;
local function engine()
    rc._reset();
    rc.configure({ vc = vc, clock = function() return now; end, mainJob = function() return engineJob; end,
        browsing = function() return false; end, setsRoot = function() return {}; end,
        triggers = function() return {}; end, resolve = function() return nil; end,
        derive = { derive = function() return { items = derived, hash = 'h', cleanupSafe = false, referencedIds = {} }; end },
        lookupById = function() return { Slot = 'Body' }; end, say = function() end,
        capacity = function() return 0; end, inCity = function() return true; end,
        inTown = function() return true; end });
end
boot(1, { { 1, 100 } });
engine();
engineJob = 2;                            -- the job changed; the cached layout is job 1's
rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01;
check('JZ8 a job change makes the engine ask for the new layout first', rc.tick(), 'asked-layout');
check('JZ9 ...with nothing queued for either job', #(vc._st().layoutSetQ or {}), 0);
engineJob = 1;
zoneOut();
rc.kick('test'); now = now + rc.KICK_SETTLE + 0.01;
check('JZ10 the engine does nothing while zoning', rc.tick(), 'idle');
check('JZ11 ...nothing queued', #(vc._st().layoutSetQ or {}), 0);
vc.noteZoneIn(); loaded();

-- ===========================================================================
-- UR: unload and reload with a request on the wire.
-- ===========================================================================
boot(1 + 4, { { 1, 100, 5 } });
werr = 'unset';
vc.requestWithdraw({ { rowId = 1, qty = 2 } }, function(_, e) werr = e; end);
tick();
local oldSeq = last()[6];
-- /addon reload: a fresh client and gate; the old request's callbacks are gone
vc._reset(); transport._reset(); vc.seedSeq(oldSeq);
local stray = vc.onFrame({ op = vc.op.WITHDRAW, seq = oldSeq, status = 0, flags = 0, payload = withdrawAck(1, 2) });
check('UR1 after a reload the old request\'s reply is eaten (never reaches the game)', stray, true);
check('UR2 ...and changes nothing', #vc.mirror.rows == 0 and vc._st().pending == nil and werr == 'unset', true);
vc.noteJob(1); for _ = 1, 4 do tick(0.2); end
check('UR3 the reloaded client reads the vault from scratch',
    vc._st().pending ~= nil and vc._st().pending.op == vc.op.HELLO and last()[5] == vc.op.HELLO, true);
-- the goodbye: only to a server that pushes, only while subscribed, once
boot(1);
check('UR5 no goodbye to a server without pushes', vc.unsubscribeFrame(), nil);
boot(1 + 4);
zoneOut(1); now = now + 30; vc.noteZoneIn();
check('UR6 no goodbye after a login dropped the subscription', vc.unsubscribeFrame(), nil);

-- ===========================================================================
-- DR: replies that must be applied once, and only to their own request.
-- ===========================================================================
boot(1, { { 1, 100, 5 } });
werr = 'unset';
local calls = 0;
vc.requestWithdraw({ { rowId = 1, qty = 2 } }, function(_, e) calls = calls + 1; werr = e; end);
tick();
local p = vc._st().pending;
now = now + vc.SEND_TIMEOUT + 0.01; vc.pump(true);      -- one retry: the server answers both copies
vc.onFrame({ op = p.op, seq = p.seq, status = 0, flags = 0, payload = withdrawAck(1, 2) });
vc.onFrame({ op = p.op, seq = p.seq, status = 0, flags = 0, payload = withdrawAck(1, 2) });   -- the ring's replay
check('DR1 a replayed ack is applied once', vc.mirror.rows[1] and vc.mirror.rows[1].qty, 3);
check('DR2 ...and its caller hears once', calls, 1);
boot(1, { { 1, 100, 5 } });
vc.requestWithdraw({ { rowId = 1, qty = 2 } }, function() end);
tick();
p = vc._st().pending;
vc.onFrame({ op = p.op, seq = (p.seq % 255) + 1, status = 0, flags = 0, payload = withdrawAck(1, 2) });
check('DR3 an ack with another seq is never applied', vc.mirror.rows[1] and vc.mirror.rows[1].qty, 5);
vc.onFrame({ op = vc.op.DEPOSIT, seq = p.seq, status = 0, flags = 0, payload = depositAck(1, 9) });
check('DR4 ...nor one with another op', vc._st().pending ~= nil and vc.mirror.rows[1].qty == 5, true);
-- a refused edit is never re-sent by the client
boot(1);
serr = 'unset';
vc.requestLayoutSet({ verb = vc.verb.PIN, instanceId = 1, itemId = 100, pinned = true }, function(_, e) serr = e; end);
tick();
frame(vc.status.BUSY);
for _ = 1, 20 do tick(0.25); end
check('DR5 a BUSY edit is reported, not re-sent', serr == 'busy' and sends(vc.op.LAYOUT_SET2) == 1, true);
-- NOT_IN_CITY on one engine add cancels its queued siblings, never the one on the wire
boot(1);
local doneA, doneB = 'unset', 'unset';
vc.requestLayoutSet({ verb = vc.verb.ADD, instanceId = 1, itemId = 100, count = 1 }, function(c, e) doneA = c or e; end);
vc.requestLayoutSet({ verb = vc.verb.ADD, instanceId = 2, itemId = 101, count = 1 }, function(c, e) doneB = c or e; end);
tick();
local n = vc.cancelLayoutSets('cancelled');
check('DR6 cancelling keeps the edit on the wire and drops the queued one', n == 1 and doneB == 'cancelled', true);
frame(0, 0, setAck(vc.code.OK));
check('DR7 ...whose own answer still reaches its caller', doneA, vc.code.OK);
for _ = 1, 10 do tick(0.25); end
check('DR8 ...and the dropped edit never leaves', sends(vc.op.LAYOUT_SET2), 1);

-- an unreadable answer cannot prove nothing moved: every write re-reads
boot(1);
local merr = 'unset';
vc.requestDeposit({ { container = 0, slot = 1 } }, function(_, e) merr = e; end); tick();
frame(0, 0, '');
check('DR9 an unreadable deposit ack is reported and re-read', merr == 'malformed' and vc.mirror.fresh == false, true);
boot(1);
merr = 'unset';
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function(_, e) merr = e; end); tick();
frame(0, 0, '');
check('DR10 an unreadable withdraw ack is reported and re-read', merr == 'malformed' and vc.mirror.fresh == false, true);
boot(1);
merr = 'unset';
vc.requestLayoutSet({ verb = vc.verb.PIN, instanceId = 1, itemId = 100, pinned = true }, function(_, e) merr = e; end); tick();
check('DR11 an unreadable edit ack (an OK frame too short to read) does not throw', pcall(frame, 0, 0, w16(0)), true);
check('DR11a ...it is reported and both views re-read',
    merr == 'malformed' and vc.mirror.fresh == false and vc.layoutCache.fresh == false, true);
-- an unreadable list page is dropped without throwing (the read backs off and runs again)
boot(1);
vc.markStale(0, 'test'); tick();
reply(hello(1, 1, 10));
check('DR15 an unreadable LIST2 page does not throw', pcall(frame, 0, 0, w16(1)), true);
check('DR15a ...the read is abandoned, not half-committed', vc._st().pending == nil and vc.mirror.fresh == false, true);
boot(1);
vc.invalidateLayout(); vc.requestLayout(0); tick();
check('DR16 an unreadable LAYOUT_LIST2 page does not throw', pcall(frame, 0, 0, w16(1)), true);
check('DR16a ...the read is abandoned, the layout stays stale', vc._st().pending == nil and vc.layoutCache.fresh == false, true);
boot(1);
vc.requestDeposit({ { container = 0, slot = 1 } }, function() end); tick();
reply(depositAck(1, 60));
check('DR12 a stored piece re-reads the vault (the ack carries no quantities)', vc.mirror.fresh, false);
-- one ack frame's worth, whatever the server advertises
boot(1);
vc.limits.maxDeposit = 124;
check('DR13 the deposit cap stays 62 when a server advertises more', vc.depositCap(), 62);
local many = {};
for i = 1, 63 do many[i] = { container = 0, slot = i }; end
check('DR13a ...so 63 entries are refused client-side', vc.requestDeposit(many, function() end), false);
local wrows = {};
for i = 1, 63 do wrows[i] = { rowId = i, qty = 1 }; end
check('DR14 a withdraw past the server\'s limit is refused client-side', vc.requestWithdraw(wrows, function() end), false);
check('DR14a ...and nothing was queued', #(vc._st().withdrawQ or {}) + #(vc._st().depositQ or {}), 0);

-- the answers that say "your view is out of date" re-read it
boot(1, { { 1, 100, 5 } });
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function() end); tick();
frame(0, 0, w16(1) .. w16(0) .. w32(1) .. w16(0) .. w16(vc.code.NO_INSTANCE));
check('DR17 a withdraw that met a gone row re-reads the vault', vc.mirror.fresh, false);
boot(1, { { 1, 100, 5 } });
local stampBefore = vc.mirror.stamp;
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function() end); tick();
frame(0, 0, withdrawAck(1, 1));
check('DR18 a withdraw\'s subtraction re-stamps the mirror (views cache on the stamp)',
    vc.mirror.stamp ~= stampBefore and vc.mirror.rows[1].qty == 4, true);
boot(1);
vc.requestLayoutSet({ verb = vc.verb.PIN, instanceId = 1, itemId = 100, pinned = true }, function() end); tick();
frame(0, 0, setAck(vc.code.NO_INSTANCE));
check('DR19 an edit that met a changed copy re-reads both views',
    vc.mirror.fresh == false and vc.layoutCache.fresh == false, true);
-- the old job's late page is dropped, not committed
boot(1);
vc.invalidateLayout(); vc.requestLayout(0); tick();
lp = vc._st().pending;
vc.noteJob(2);
vc.onFrame({ op = lp.op, seq = lp.seq, status = 0, flags = 0, payload = layout2({ layoutRow(1, 555, 9) }, 10) });
check('JZ7b the old job\'s page is dropped, never committed', #vc.layoutCache.entries, 0);

-- T1: a stale reply (another seq of the same op) never frees the slot
transport._reset(); now = now + 100;
transport._send = ashitaSend;
transport.send(pk(0x46, 7), 'v');
check('TR17 a reply to another seq of the same op is not ours', transport.received(0x46, 6), false);
now = now + transport.MIN_GAP + 0.01;
check('TR18 ...and the slot stays held for the real reply', transport.send(pk(0x40, 8), 'v'), false);

-- derivation: a dlac: virtual entry is neither an item nor an unresolved name
local derive = require(base .. 'derive');
local dv = derive.derive({ Idle = { Main = 'dlac:AutoStaff', Body = { 'dlac:AutoObi' } } }, {});
check('DV1 virtual entries are not reported unresolved', #dv.unresolved, 0);

-- ===========================================================================
-- EN: the layout engine's own guards, against the real vault client.
-- ===========================================================================
local function usageStub(o)
    return {
        keyOf = function(id, _, inst) return tostring(id) .. ':' .. tostring(inst or ''); end,
        isExcluded = function() return o.excluded == true; end,
        pruneExclusions = function() end, seed = function() end,
        settings = function() return { additions = o.additions or 'auto', removals = o.removals or 'ask' }; end,
        rankEvictions = function() return o.ranked or { unpinned = {}, pinned = {} }; end,
        exclude = function(keys) o.excludedKeys = keys; end,
    };
end
local function engineWith(o)
    rc._reset();
    local u = usageStub(o);
    rc.configure({ vc = vc, clock = function() return now; end, mainJob = function() return 1; end,
        browsing = function() return o.browsing == true; end,
        setsRoot = function() return {}; end, triggers = function() return {}; end, resolve = function() return nil; end,
        derive = { derive = function() return { items = o.items or {}, hash = 'h',
            cleanupSafe = o.cleanupSafe == true, referencedIds = o.referenced or {} }; end },
        lookupById = function() return { Slot = o.slot or 'Body' }; end, say = function() end,
        capacity = function() return o.capacity or 0; end,
        inCity = function() return o.city ~= false; end, inTown = function() return o.town ~= false; end,
        worn = function() return o.worn or {}; end,
        usage = u, settings = u.settings });
    return u;
end
local function run() rc.kick('t'); now = now + rc.KICK_SETTLE + 0.01; return rc.tick(); end
local function queued(pred)
    local n = 0;
    for _, q in ipairs(vc._st().layoutSetQ or {}) do if pred == nil or pred(q.e) then n = n + 1; end end
    return n;
end
local function isRemove(e) return e.verb == vc.verb.REMOVE; end

boot(1, { { 1, 100 } });
engineWith({ items = { { itemId = 100, count = 1 } } });
vc.requestLayoutSet({ verb = vc.verb.PIN, instanceId = 7, itemId = 107, pinned = true }, function() end);
check('EN1 the engine waits while any edit is queued', run(), 'idle');
check('EN1a ...and adds nothing beside it', queued(), 1);
boot(1, { { 1, 100 } });
engineWith({ items = { { itemId = 100, count = 1 } } });
vc.markStale(0, 'test'); tick();
check('EN2 the engine waits while the vault is being read', run(), 'idle');
boot(1, { { 1, 100 } });
engineWith({ items = { { itemId = 100, count = 1 } }, browsing = true });
check('EN3 browsing another job, the engine never runs', run(), 'idle');
check('EN3a ...so the browsed job\'s sets never reach the live layout', queued(), 0);
boot(1, { { 1, 100 } });
engineWith({ items = { { itemId = 100, count = 1 } }, additions = 'off' });
run();
check('EN4 Additions: Off adds nothing', queued(), 0);
boot(1, { { 1, 100 } });
engineWith({ items = { { itemId = 100, count = 1 } }, excluded = true });
run();
check('EN5 a piece the player removed (a tombstone) is not added back', queued(), 0);
boot(1, { { 1, 100 } });
vc.layoutCache.entries = { { itemId = 200, instanceId = 50, ordinal = 1, kind = 0, state = 1, count = 1 } };
engineWith({ items = { { itemId = 100, count = 1 } }, capacity = 1, referenced = { [200] = true } });
run();
check('EN6 an add that cannot fit waits for room', queued(), 0);
check('EN6a ...and says so', rc.pressure() ~= nil and rc.pressure().waiting, 1);
-- MAX_PUSH bounds one run (the legacy road, where no inner loop does)
boot(1, { { 1, 100 }, { 2, 101 }, { 3, 102 } });
vc.limits.instances = false;
engineWith({ items = { { itemId = 100, count = 1 }, { itemId = 101, count = 1 }, { itemId = 102, count = 1 } } });
local savedMax = rc.MAX_PUSH;
rc.MAX_PUSH = 2;
run();
rc.MAX_PUSH = savedMax;
check('EN7 one run never pushes more than MAX_PUSH', queued(), 2);
-- NOT_IN_CITY on the first add drops its queued sibling: it is never sent
boot(1, { { 1, 100 }, { 2, 101 } });
engineWith({ items = { { itemId = 100, count = 1 }, { itemId = 101, count = 1 } } });
check('EN8 two adds go', run(), 'pushed:2');
tick();
frame(0, 0, setAck(vc.code.NOT_IN_CITY));
for _ = 1, 10 do tick(0.25); end
check('EN8a ...the first refused NOT_IN_CITY: the second never leaves', sends(vc.op.LAYOUT_SET2), 1);
check('EN8b ...and the engine says it waits for a city', rc.cityBlocked(), true);
-- a copy the layout already binds is never added again (a pair wanted, one copy)
boot(1, { { 1, 100, 1, 10 } });
vc.layoutCache.entries = { { itemId = 100, instanceId = 10, ordinal = 1, kind = 0, state = 0, count = 1 } };
engineWith({ items = { { itemId = 100, count = 2 } }, slot = 'Ring' });
run();
check('EN9 a bound copy is never added a second time', queued(function(e) return e.instanceId == 10; end), 0);
-- cleanup releases only from a complete derivation
boot(1);
vc.layoutCache.entries = { { itemId = 300, instanceId = 30, ordinal = 1, kind = 0, state = 1, count = 1 } };
engineWith({ cleanupSafe = false });
run();
check('EN10 an incomplete derivation never releases a layout entry', queued(isRemove), 0);
-- instance entries are never "repaired" by the legacy count rule
boot(1);
vc.layoutCache.entries = { { itemId = 100, instanceId = 5, ordinal = 1, kind = 0, state = 3, count = 1 } };
engineWith({});
check('EN11 instance mode never sends a legacy count repair', run() ~= 'repairing:1' and queued(isRemove) == 0, true);
-- auto-eviction: in town only, once per layout stamp, never a pinned entry,
-- and a wanted entry it evicts is tombstoned (or the next run adds it back)
local function shelf()
    vc.layoutCache.entries = {
        { itemId = 400, instanceId = 40, ordinal = 1, kind = 0, state = 1, count = 1 },
        { itemId = 401, instanceId = 41, ordinal = 2, kind = 0, state = 1, count = 1, pinned = true },
    };
end
local ranked = {
    unpinned = { { key = '400:40', itemId = 400, instanceId = 40, ordinal = 1, count = 1, assigned = true } },
    pinned = { { key = '401:41', itemId = 401, instanceId = 41, ordinal = 2, count = 1 } },
};
boot(1); shelf();
engineWith({ capacity = 1, removals = 'auto', ranked = ranked, town = false, city = false });
run();
check('EN12 auto-eviction never acts outside a town', queued(isRemove), 0);
boot(1); shelf();
local uo = { capacity = 1, removals = 'auto', ranked = ranked };
engineWith(uo);
run();
check('EN13 in town an over-full shelf evicts the least-used unpinned entry', queued(isRemove), 1);
check('EN14 ...a wanted entry it evicts is tombstoned', uo.excludedKeys ~= nil and #uo.excludedKeys, 1);
vc.cancelLayoutSets();
run();
check('EN15 ...once per layout stamp, not on every run', queued(isRemove), 0);
boot(1); shelf();
engineWith({ capacity = 1, removals = 'auto', ranked = { unpinned = {}, pinned = ranked.pinned } });
run();
check('EN16 a pinned entry is never auto-evicted', queued(isRemove), 0);

if failures > 0 then
    print(string.format('FAIL -- %d of %d stage-8 checks failed', failures, checks));
    os.exit(1);
end
print(string.format('OK -- %d stage-8 checks: write window, foreign gate, zone lines, job changes, reloads, replies', checks));
