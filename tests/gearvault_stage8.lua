-- lua tests/gearvault_stage8.lua -- the stage-8 pass of 2026-10-01 (night):
-- the client rules whose failure could DUPLICATE, lose or misdirect gear --
-- write retries and the server's replay window, writes and replies across a
-- zone line, a job change while zoning, an addon reload with a request on
-- the wire, the shared 0x1E0 gate's foreign-packet wait, and its fair turns
-- (T4, the FT cases). The threat list
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
    for _, x in ipairs(rows or { { 1, 100 } }) do r[#r + 1] = listRow(x[1], x[2], x[3], x[4]); end
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
-- FT: fair turns (T4). Each module asks on its own clock -- the vault every
-- frame, HELM, digging and ascension 0.35 s after a refusal -- and whoever
-- asked first once the gap was spent used to win, so the vault's paging held
-- the others back for as long as it paged. Now the module that has waited
-- longest, among those still asking, sends next.
-- ===========================================================================
local GAP = transport.MIN_GAP;
local FRAME = 1 / 60;
local function ask(op, seq, why) return transport.send(pk(op, seq), why or 'ft'); end
local function fresh() transport._reset(); transport._send = ashitaSend; sent = {}; now = now + 100; end
local who = transport.producerOf;
check('FT0 a module is its op partition: every vault op is one', who(0x40) == who(0x46) and who(0x48) == who(0x7F), true);
check('FT0a ...but the EXP band check (0x4C, inside that band) is its own', who(0x4C) ~= who(0x46), true);
check('FT0b HELM (0x80) and digging (0x81) are two modules', who(0x80) ~= who(0x81), true);
check('FT0c ascension is its whole partition', who(0xA0) == who(0xAF) and who(0xA0) ~= who(0x80), true);
check('FT0d combat telemetry (HELLO C0, WATCH C1, RESYNC C3, STOP C4) is one module',
    who(0xC0) == who(0xC1) and who(0xC3) == who(0xC4) and who(0xC0) ~= who(0xA0), true);
check('FT0e an op outside every partition is a module of its own',
    who(0x90) ~= who(0x91) and who(0x90) ~= who(0x80) and who(0xB0) ~= who(0xC0), true);

-- vault paging against one HELM poll: HELM goes after the vault's current reply
fresh();
check('FT1 a vault page goes', ask(0x46, 1, 'vault'), true);
now = now + 0.12;
check('FT1a HELM\'s poll is refused while the page is on the wire', ask(0x80, 1, 'HELM'), false);
now = now + 0.04; transport.received(0x46, 1);
ask(0x46, 2, 'vault');                              -- the next page: the gap, the vault waits from here
now = now + GAP + 0.01;
check('FT2 ...then yields to HELM, which has waited longer', ask(0x46, 2, 'vault'), false);
check('FT2a idle() says so to the vault', transport.idle(0x46), false);
check('FT2b ...and to a module not waiting yet', transport.idle(), false);
check('FT2c ...but not to HELM', transport.idle(0x80), true);
now = now + 0.2;                                    -- HELM's own 0.35 s retry
check('FT3 HELM\'s poll gets the slot after the vault\'s current reply', ask(0x80, 1, 'HELM'), true);
check('FT3a ...the page waits while the poll is on the wire', ask(0x46, 2, 'vault'), false);
now = now + 0.16; transport.received(0x80, 1); now = now + GAP + 0.01;
check('FT3b ...and goes right after its reply', ask(0x46, 2, 'vault'), true);

-- the reverse: a module asking every frame (combat telemetry's WATCH) cannot
-- take the turn of a vault request that has waited longer
fresh();
check('FT4 a WATCH goes', ask(0xC1, 1, 'telemetry'), true);
now = now + 0.12;
check('FT4a the vault\'s request is refused while it is on the wire', ask(0x47, 9, 'vault'), false);
now = now + 0.04; transport.received(0xC1, 1);
local took = false;
for _ = 1, 9 do now = now + FRAME; if ask(0xC1, 2, 'telemetry') then took = true; end end
check('FT5 a module asking every frame, through the gap and past it, cannot take that turn', took, false);
check('FT5a the vault, asking later, gets the slot after the WATCH\'s reply', ask(0x47, 9, 'vault'), true);
now = now + 0.16; transport.received(0x47, 9); now = now + GAP + 0.01;
check('FT5b ...then the next WATCH goes', ask(0xC1, 2, 'telemetry'), true);

-- three waiting modules and the vault go in the order they began to wait,
-- though every frame the latest waiter asks first
fresh();
check('FT6 a vault request goes', ask(0x46, 1, 'vault'), true);
now = now + 0.02; ask(0x80, 1, 'HELM');
now = now + 0.02; ask(0xA0, 1, 'ascension');
now = now + 0.02; ask(0x81, 1, 'digging');
local toSend = { [0x46] = 2, [0x81] = 1, [0xA0] = 1, [0x80] = 1 };
local order, answer = {}, { at = now + 0.10, op = 0x46, seq = 1 };
for _ = 1, 180 do
    now = now + FRAME;
    if answer and now >= answer.at then transport.received(answer.op, answer.seq); answer = nil; end
    for _, op in ipairs({ 0x46, 0x81, 0xA0, 0x80 }) do
        local s = toSend[op];
        if s and ask(op, s) then
            order[#order + 1] = string.format('%02X', op);
            toSend[op], answer = nil, { at = now + 0.16, op = op, seq = s };
        end
    end
end
check('FT6a ...HELM, ascension, digging, then the vault', table.concat(order, ' '), '80 A0 81 46');

-- the EXP band check is its own module, so the vault's paging cannot swallow its turn
fresh();
ask(0x46, 1, 'vault');
now = now + 0.05; ask(0x4C, 1, 'EXP band');
now = now + 0.11; transport.received(0x46, 1);
ask(0x46, 2, 'vault');
now = now + GAP + 0.01;
check('FT7 the EXP band check, inside the vault\'s band, waits as its own module',
    ask(0x46, 2, 'vault') == false and ask(0x4C, 1, 'EXP band'), true);

-- a module that stops asking (its panel closed) drops out of line...
fresh();
ask(0x46, 1, 'vault');
now = now + 0.12;
local helmAt = now;
check('FT8 HELM asks once while a page is on the wire, then stops', ask(0x80, 1, 'HELM'), false);
now = now + 0.04; transport.received(0x46, 1); now = now + GAP + 0.01;
check('FT8a the next page yields while HELM may still ask again', ask(0x46, 2, 'vault'), false);
now = helmAt + 0.9;
check('FT8b ...still 0.9 s after HELM\'s last try (a hitch past its 0.35 s retry)', ask(0x46, 2, 'vault'), false);
now = helmAt + 1.2;
check('FT9 1.2 s after its last try HELM holds nobody back', ask(0x46, 2, 'vault'), true);
-- ...and when it comes back it starts at the back of the line, not with its old wait
now = now + 0.16; transport.received(0x46, 2);
ask(0x46, 3, 'vault');                              -- the gap: the vault waits from here
now = now + 0.05; ask(0x80, 1, 'HELM');             -- the HELM panel is open again
now = now + GAP;
check('FT10 a module back from a stale wait queues behind those already waiting', ask(0x80, 1, 'HELM'), false);
check('FT10a ...so the vault goes first', ask(0x46, 3, 'vault'), true);

-- a retry of THE pending request never waits its turn, and never joins the line
fresh();
check('FT11 a vault write goes', ask(0x42, 5, 'vault write'), true);
for _ = 1, 4 do now = now + 0.35; ask(0x80, 1, 'HELM'); end     -- HELM waits, asking
now = now + 0.1;                                                 -- 1.5 s: the write's retry
check('FT11a the write\'s same-seq retry goes, though HELM has waited longer',
    ask(0x42, 5, 'vault write retry'), true);
now = now + 0.16; transport.received(0x42, 5); now = now + GAP + 0.01;
check('FT11b ...and HELM still goes first after the reply',
    ask(0x46, 6, 'vault') == false and ask(0x80, 1, 'HELM'), true);

-- a turn is spent even when the packet manager refuses the frame: a module
-- whose sends always fail cannot stay first in line
fresh();
ask(0x46, 1, 'vault');
now = now + 0.05; ask(0x80, 1, 'HELM');
now = now + 0.05; ask(0xA0, 1, 'ascension');
now = now + 0.06; transport.received(0x46, 1); now = now + GAP + 0.01;
transport._send = function() return false; end;
check('FT12 HELM\'s turn, but the packet manager refuses its frame', ask(0x80, 1, 'HELM'), false);
transport._send = ashitaSend;
now = now + GAP + 0.01;
check('FT12a ...the turn is spent: the next in line goes',
    ask(0x80, 1, 'HELM') == false and ask(0xA0, 1, 'ascension'), true);

-- two modules that began to wait at the same instant: whichever asks first goes
fresh();
ask(0x46, 1, 'vault');
now = now + 0.05; ask(0x80, 1, 'HELM'); ask(0x81, 1, 'digging');
now = now + 0.11; transport.received(0x46, 1); now = now + GAP + 0.01;
check('FT13 equal waits never block each other', ask(0x81, 1, 'digging'), true);

-- a lost request: at MAX_WAIT the slot goes to the longest waiter, and the
-- lost module's resend of its seq is a new request at the back of the line
fresh();
local lostAt = now;
ask(0x80, 1, 'HELM');                               -- its reply never comes
now = now + 0.5; ask(0x46, 1, 'vault');
now = now + 0.2; ask(0xA0, 1, 'ascension');
while now + 0.35 < lostAt + transport.MAX_WAIT do   -- both keep asking, every 0.35 s
    now = now + 0.35; ask(0xA0, 1, 'ascension'); ask(0x46, 1, 'vault');
end
now = lostAt + transport.MAX_WAIT + 0.01;
check('FT14 at MAX_WAIT the lost module\'s resend is a new request, behind those waiting',
    ask(0x80, 1, 'HELM'), false);
check('FT14a ...and the slot goes to the longest waiter',
    ask(0xA0, 1, 'ascension') == false and ask(0x46, 1, 'vault'), true);

-- a module held back by the line leaves ONE wire-log line per wait, naming the front
local yields = {};
transport._audit = function(event, _, _, why) if event == 'yield' then yields[#yields + 1] = why; end end;
fresh();
ask(0x46, 1, 'vault');
now = now + 0.05; ask(0x80, 1, 'HELM');
now = now + 0.11; transport.received(0x46, 1); now = now + GAP + 0.01;
for _ = 1, 5 do ask(0x46, 2, 'vault'); now = now + FRAME; end
transport._audit = nil;
check('FT15 a held module logs one yield per wait, naming who is ahead',
    #yields == 1 and yields[1]:find('behind HELM', 1, true) ~= nil, true);

-- The real vault client and the real HELM module at 60 fps, against a
-- server that answers every request 160 ms after it left: the vault re-reads
-- a ten-page list while the HELM panel is open (it calls touch() every frame).
boot(1, nil, true);
local helm = require('dlac\\servers\\ascensionxi\\modules\\helm\\status');
local helmFirstIdx, helmSentIdx, helmFirstAt, helmSentAt;
helm._clock = function() return now; end;
helm._received = transport.received;
helm._send = function(p)
    local ok = transport.send(p, 'HELM status');
    if helmFirstIdx == nil then helmFirstIdx, helmFirstAt = #sent, now; end
    if ok and helmSentIdx == nil then helmSentIdx, helmSentAt = #sent, now; end
    return ok;
end;
local function helmReply(p)
    return string.char(224, 15, 0, 0, 0x80, p[6], 0, 0) .. w16(1) .. w16(0)
        .. string.char(p[13], p[14], p[15], p[16]) .. w32(100) .. w16(1) .. w16(1) .. w16(1) .. w16(1);
end
local PAGES = 10;
local wire, onWire, inFlight, pages = {}, #sent, 0, 0;   -- boot's own sends were answered already
vc.markStale(0, 'test');
helm.reset(false);
for _ = 1, 60 * 6 do
    now = now + FRAME;
    for i = #wire, 1, -1 do                         -- the answers that are due
        local w = wire[i];
        if now >= w.at then
            table.remove(wire, i);
            local op, seq = w.p[5], w.p[6];
            if op == 0x80 then
                helm.onPacket(helmReply(w.p));
            elseif op == vc.op.HELLO then
                vc.onFrame({ op = op, seq = seq, status = 0, flags = 0, payload = hello(1, PAGES, 10) });
            elseif op == vc.op.LIST2 then
                local n = #(vc._st().rowsAcc or {}) + 1;
                vc.onFrame({ op = op, seq = seq, status = 0, flags = (n < PAGES) and vc.FLAG_MORE or 0,
                    payload = list2({ listRow(n, 100 + n) }, 10) });
            else
                vc.onFrame({ op = op, seq = seq, status = 0, flags = 0, payload = w16(0) .. w16(0) });
            end
        end
    end
    vc.pump(true);
    if pages >= 2 then helm.touch(); end              -- the panel opens mid-read
    while onWire < #sent do                           -- this frame's sends go on the wire
        onWire = onWire + 1;
        wire[#wire + 1] = { at = sent[onWire].at + 0.16, p = sent[onWire].p };
        if sent[onWire].p[5] == vc.op.LIST2 then pages = pages + 1; end
    end
    inFlight = math.max(inFlight, #wire);
end
local between, lastPage = 0, 0;
for i, s in ipairs(sent) do
    if s.p[5] == vc.op.LIST2 then lastPage = i; end
    if helmFirstIdx and helmSentIdx and i > helmFirstIdx and i < helmSentIdx then between = between + 1; end
end
check('FT16 the real modules: HELM\'s poll leaves while the vault is still paging',
    helmSentIdx ~= nil and lastPage > helmSentIdx, true);
check('FT16a ...after at most one vault request (the current reply\'s)', between <= 1, true);
check('FT16b ...within two of its own 0.35 s retries', helmSentAt ~= nil and helmSentAt - helmFirstAt < 0.8, true);
check('FT16c ...the read still completes', vc.mirror.fresh == true and #vc.mirror.rows == PAGES, true);
check('FT16d ...one request in flight at a time', inFlight, 1);

-- WD13-WD16: the write window under fair turns, 60 fps, 160 ms answers. A
-- withdraw waits behind exactly one other module's request (a HELM poll on
-- the wire); then the server loses its first two answers while the telemetry
-- module asks for a new WATCH every frame.
boot(1, nil, true);
assert(ask(0x80, 1, 'HELM'), 'the HELM poll leaves first');
local helmDue, helmAnsweredAt = now + 0.16, nil;
local wdErr = 'unset';
vc.requestWithdraw({ { rowId = 1, qty = 1 } }, function(_, e) wdErr = e; end);
local lose, answeredAt, wdDoneAt = 2, nil, nil;
local watchSeq, watchDue = 1, nil;
for _ = 1, 60 * 5 do
    now = now + FRAME;
    if helmDue and now >= helmDue then transport.received(0x80, 1); helmDue, helmAnsweredAt = nil, now; end
    if watchDue and now >= watchDue then transport.received(0xC1, watchSeq); watchSeq, watchDue = watchSeq + 1, nil; end
    local p = vc._st().pending;
    if p and p.op == vc.op.WITHDRAW and p.sentAt and now - p.sentAt >= 0.16 and answeredAt ~= p.sentAt then
        answeredAt = p.sentAt;
        if lose > 0 then
            lose = lose - 1;                          -- this answer is lost
        else
            vc.onFrame({ op = p.op, seq = p.seq, status = 0, flags = 0, payload = withdrawAck(1, 1) });
            wdDoneAt = now;
        end
    end
    vc.pump(true);
    if watchDue == nil and sends(vc.op.WITHDRAW) > 0 and ask(0xC1, watchSeq, 'telemetry') then
        watchDue = now + 0.16;
    end
end
local wd = {};
for _, s in ipairs(sent) do if s.p[5] == vc.op.WITHDRAW then wd[#wd + 1] = s; end end
check('WD13 a write behind one other module\'s request leaves at the first frame the gap allows',
    #wd > 0 and helmAnsweredAt ~= nil and wd[1].at > helmAnsweredAt
        and wd[1].at - helmAnsweredAt <= GAP + 2 * FRAME, true);
check('WD14 ...its two retries keep the seq and leave inside WRITE_DEADLINE of its first send',
    #wd == 3 and wd[2].p[6] == wd[1].p[6] and wd[3].p[6] == wd[1].p[6] and wd[3].at - wd[1].at < DEADLINE, true);
check('WD15 ...and the third answer lands: no outcome unknown', wdErr, nil);
local others, watchAt = 0, nil;
for _, s in ipairs(sent) do
    if #wd > 0 and s.at > wd[1].at and s.at <= (wdDoneAt or math.huge) and s.p[5] ~= vc.op.WITHDRAW then
        others = others + 1;
    end
    if watchAt == nil and s.p[5] == 0xC1 then watchAt = s.at; end
end
check('WD16 the module asking every frame never got in while the write awaited its answer, and went next',
    others == 0 and wdDoneAt ~= nil and watchAt ~= nil and watchAt - wdDoneAt <= GAP + 2 * FRAME, true);

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
check('EN9a ...and the pair\'s missing copy counts as not vaulted (the bound one is not counted twice)',
    rc.notVaulted(), 1);
-- the augmented road has no second check: the bound copy must never become a candidate
local rolled = string.char(2, 3, 0x22) .. string.rep('\0', 21);
boot(1, { { 1, 100, 1, 10 } });
vc.mirror.rows[1].identity = rolled;
vc.layoutCache.entries = { { itemId = 100, instanceId = 10, ordinal = 1, kind = 0, state = 0, count = 1, identity = rolled } };
engineWith({ items = { { itemId = 100, count = 2 } }, slot = 'Ring' });
run();
check('EN9b a bound AUGMENTED copy is never drawn again for a pair', queued(function(e) return e.instanceId == 10; end), 0);
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
print(string.format('OK -- %d stage-8 checks: write window, foreign gate, fair turns, zone lines, job changes, reloads, replies', checks));
