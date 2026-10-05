-- lua tests/ascensionxi_telemetry_client.lua   (from the dlac repo root)
-- The AscensionXI combat telemetry client: the session and its battle lane,
-- the shared transport rules (T1-T3: matched replies only, pushes never touch
-- the slot, abandon between retries), retries and escalation, the push
-- rejection rules (server research 4.5), unload, and init.lua's tap, which
-- blocks the whole 0xC0-0xCF partition before anything decodes it.
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
local client = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\client');

-- A fake shared transport: records sends; the test answers or not.
local time = 100;
local sent, received, abandoned, direct = {}, {}, {}, {};
local busy = false;
local frames = {};
client._clock = function() return time; end;
client._send = function(p) if busy then return false; end sent[#sent + 1] = p; return true; end;
client._received = function(op, seq) received[#received + 1] = { op = op, seq = seq }; end;
client._abandon = function(op, seq) abandoned[#abandoned + 1] = { op = op, seq = seq }; end;
client._direct = function(p) direct[#direct + 1] = p; end;
client._charId = function() return 21828; end;
client._onFrame = function(f) frames[#frames + 1] = f; end;

-- CL-01..CL-12 run with a decision always wanted; CL-14 tests demand.
client.IDLE_AFTER = 1e9;
client.want();

local function lastSent() return sent[#sent]; end
local function payloadOf(p) local s = {}; for i = 9, #p do s[#s + 1] = string.char(p[i]); end return table.concat(s); end
local function opOf(p) return p[5]; end
local function seqOf(p) return p[6]; end
local function nonceOf(p) return wire.u32(payloadOf(p), 8); end

local function pumpFor(seconds)
    for _ = 1, math.floor(seconds * 20) do time = time + 0.05; client.pump(); end
end

-- Reply builders, mirroring the server's layouts (server research 4.3).
local function reply(op, seq, status, payload) return { op = op, seq = seq, status = status, flags = 0, payload = payload or '' }; end
local SESSION = 0x7A3F19C4;
local function helloReply(req, session, charId)
    local p = wire.header(0, 48, session, nonceOf(req)) .. wire.w16(1) .. wire.w16(1) .. wire.w16(1) .. wire.w16(45)
        .. wire.w32(0x73) .. wire.w32(0x9C41E27B) .. wire.w32(charId or 21828) .. string.char(2, 4, 0, 0)
        .. wire.w16(400) .. wire.w16(232) .. wire.w16(0x0F) .. wire.w16(0) .. wire.w16(0) .. wire.w16(15);
    return reply(wire.op.HELLO, seqOf(req), 0, p);
end
local function watchReply(req, result, watchGen, state)
    local p = wire.header(result or 0, 28, SESSION, nonceOf(req)) .. string.char(0, state or 1) .. wire.w16(0x0F)
        .. wire.w32(watchGen) .. wire.w32(7) .. wire.w16(45) .. string.char(4, 0);
    return reply(wire.op.WATCH, seqOf(req), 0, p);
end
local function resyncReply(req, battleRev, battleWatchGen, laneMask)
    local p = wire.header(0, 36, SESSION, nonceOf(req)) .. wire.w16(45) .. string.char(laneMask or 0, 0)
        .. wire.w32(battleRev) .. wire.w32(0) .. wire.w32(battleWatchGen) .. wire.w32(0) .. string.char(1, 0, 0, 0);
    return reply(wire.op.RESYNC, seqOf(req), 0, p);
end
local function snapshot(rev, watchGen, opts)
    opts = opts or {};
    local p = wire.header(0, 136, opts.session or SESSION, rev) .. wire.w32(watchGen) .. string.char(opts.state or 1, 0, 0, 0)
        .. string.rep('\0', 136 - 20);
    p = p:sub(1, 1) .. string.char(opts.lane or 0) .. p:sub(3);
    if opts.proto then p = string.char(opts.proto) .. p:sub(2); end
    return reply(wire.op.SNAPSHOT, 0, 0, p);
end

-- CL-01: zone in, settle, HELLO, then the FOLLOW WATCH.
client.reset();
client.zoneIn();
client.pump();
check('CL-01 nothing before the zone settles', #sent, 0);
pumpFor(client.SETTLE + 0.1);
check('CL-01 one HELLO', #sent, 1);
local hello = lastSent();
check('CL-01 HELLO op', opOf(hello), wire.op.HELLO);
check('CL-01 seq never 0', seqOf(hello) ~= 0, true);
check('CL-01 HELLO nonce nonzero', nonceOf(hello) ~= 0, true);
check('CL-01 HELLO session 0', wire.u32(payloadOf(hello), 4), 0);
check('CL-01 reply matched', client.onFrame(helloReply(hello, SESSION)), true);
check('CL-01 transport.received for the matched reply', #received, 1);
check('CL-01 live', client.state().phase, 'live');
pumpFor(0.1);
local watch = lastSent();
check('CL-01 WATCH op', opOf(watch), wire.op.WATCH);
local wp = payloadOf(watch);
check('CL-01 WATCH session', wire.u32(wp, 4), SESSION);
check('CL-01 WATCH lane 0', wire.u8(wp, 12), 0);
check('CL-01 WATCH FOLLOW', wire.u8(wp, 13), wire.watchFlag.FOLLOW);
check('CL-01 WATCH contexts', wire.u16(wp, 14), 0x000F);
check('CL-01 WATCH generation 1', wire.u32(wp, 16), 1);
check('CL-01 WATCH reply', client.onFrame(watchReply(watch, 0, 1)), true);
check('CL-01 confirmed', client.state().confirmed, 1);

-- CL-02: a reply with our op and seq but another Nonce is not ours, and
-- the request stays pending; a duplicate after the answer is not ours either.
local before = #received;
check('CL-02 a late duplicate is ignored', client.onFrame(watchReply(watch, 0, 1)), false);
pumpFor(15.1);   -- the lease renewal goes out and waits
local pendingRenew = lastSent();
check('CL-02 a renewal is pending', client.state().pending, 'renew');
local forged = resyncReply(pendingRenew, 1, 1, 0);
forged.payload = forged.payload:sub(1, 8) .. wire.w32(nonceOf(pendingRenew) + 1) .. forged.payload:sub(13);
check('CL-02 our op and seq, another Nonce', client.onFrame(forged), false);
check('CL-02 calls no received', #received, before);
check('CL-02 still pending', client.state().pending, 'renew');
check('CL-02 the real answer lands', client.onFrame(resyncReply(pendingRenew, 0, 1, 0)), true);

-- CL-03: pushes. The good one lands; each bad one is refused by its rule.
local beforePush = #received;
check('CL-03 accepted', client.onFrame(snapshot(1, 1)), true);
check('CL-03 handed on', #frames, 1);
check('CL-03 pushes never call received', #received, beforePush);
check('CL-03 old rev', client.onFrame(snapshot(1, 1)), false);
check('CL-03 other session', client.onFrame(snapshot(2, 1, { session = 0x11111111 })), false);
check('CL-03 stale WatchGen', client.onFrame(snapshot(2, 0)), false);
check('CL-03 preview lane', client.onFrame(snapshot(2, 1, { lane = 1 })), false);
check('CL-03 other proto', client.onFrame(snapshot(2, 1, { proto = 2 })), false);
local short = snapshot(2, 1); short.payload = short.payload:sub(1, 40);
check('CL-03 short', client.onFrame(short), false);
check('CL-03 gaps allowed', client.onFrame(snapshot(5, 1)), true);
local rej = client.state().stats.rejected;
check('CL-03 counted: rev', rej.rev, 1);
check('CL-03 counted: session', rej.session, 1);
check('CL-03 counted: watchGen', rej.watchGen, 1);

-- CL-04: the lease is renewed after RenewAfterSeconds of silence.
local n = #sent;
pumpFor(14.5);
check('CL-04 no renewal before 15 s', #sent, n);
pumpFor(1);
check('CL-04 a RESYNC renewal', opOf(lastSent()), wire.op.RESYNC);
check('CL-04 mode 0', wire.u8(payloadOf(lastSent()), 12), wire.resyncMode.RENEW);

-- CL-05: unanswered: same seq and Nonce again, the slot abandoned between,
-- then the escalation to HELLO.
local renew = lastSent();
pumpFor(client.RETRY + 0.1);
check('CL-05 retried', #sent, n + 2);
check('CL-05 same seq', seqOf(lastSent()), seqOf(renew));
check('CL-05 same nonce', nonceOf(lastSent()), nonceOf(renew));
check('CL-05 the slot was given back', #abandoned >= 1 and abandoned[#abandoned].seq == seqOf(renew), true);
pumpFor(client.RETRY + 0.1);
pumpFor(client.RETRY + 0.1);
check('CL-05 escalates to HELLO after three tries', opOf(lastSent()), wire.op.HELLO);

-- CL-06: a RESYNC that shows the WATCH never landed re-sends it; one that
-- shows a lost push asks for a republish.
client.onFrame(helloReply(lastSent(), SESSION));
pumpFor(0.1);
local w2 = lastSent();
check('CL-06 a new WATCH generation after the new session', wire.u32(payloadOf(w2), 16), 2);
client.onFrame(watchReply(w2, 0, 2));
client.onFrame(snapshot(1, 2));
pumpFor(15.1);
local r = lastSent();
client.onFrame(resyncReply(r, 3, 2, 0));
pumpFor(0.1);
check('CL-06 lost push: REPUBLISH', wire.u8(payloadOf(lastSent()), 12), wire.resyncMode.REPUBLISH);
client.onFrame(resyncReply(lastSent(), 3, 2, 1));
pumpFor(15.1);
client.onFrame(resyncReply(lastSent(), 1, 1, 0));
pumpFor(0.1);
check('CL-06 WATCH lost: re-sent', opOf(lastSent()), wire.op.WATCH);

-- CL-07: NO_SESSION sends the client back to HELLO.
local w3 = lastSent();
client.onFrame(reply(wire.op.WATCH, seqOf(w3), 0, wire.header(wire.result.NO_SESSION, 12, 0, nonceOf(w3))));
pumpFor(0.1);
check('CL-07 HELLO after NO_SESSION', opOf(lastSent()), wire.op.HELLO);

-- CL-08: a server without the route answers BAD_OP: the client goes quiet.
local h3 = lastSent();
client.onFrame(reply(wire.op.HELLO, seqOf(h3), wire.status.BAD_OP, ''));
check('CL-08 dormant', client.state().phase, 'dormant');
n = #sent;
pumpFor(60);
check('CL-08 and sends nothing', #sent, n);

-- CL-09: UNAVAILABLE (the route without the module) backs off and asks again.
client.reset(); client.zoneIn(); pumpFor(client.SETTLE + 0.1);
client.onFrame(reply(wire.op.HELLO, seqOf(lastSent()), wire.status.UNAVAILABLE, ''));
n = #sent;
pumpFor(client.BACKOFF - 1);
check('CL-09 quiet during the backoff', #sent, n);
pumpFor(2);
check('CL-09 HELLO after it', opOf(lastSent()), wire.op.HELLO);

-- CL-10: unload ends the session through no gate.
client.onFrame(helloReply(lastSent(), SESSION));
busy = true;
client.unload();
busy = false;
check('CL-10 one direct STOP', #direct, 1);
check('CL-10 op', direct[1][5], wire.op.STOP);
local sp = payloadOf(direct[1]);
check('CL-10 session', wire.u32(sp, 4), SESSION);
check('CL-10 all lanes', wire.u8(sp, 12), 0xFF);
check('CL-10 END_SESSION', wire.u8(sp, 13), wire.stopFlag.END_SESSION);

-- CL-11: HELLO from another character's answer is ignored.
client.reset(); client.zoneIn(); pumpFor(client.SETTLE + 0.1);
client.onFrame(helloReply(lastSent(), SESSION, 999));
check('CL-11 not live on a stranger', client.state().phase ~= 'live', true);

-- CL-12: a busy shared channel delays, never drops, the request.
client.reset(); client.zoneIn(); busy = true; n = #sent;
pumpFor(client.SETTLE + 1);
check('CL-12 nothing while busy', #sent, n);
busy = false; pumpFor(0.1);
check('CL-12 sent once free', opOf(lastSent()), wire.op.HELLO);

-- CL-06b: an unanswered WATCH asks what landed (RESYNC) after three tries.
do
    client.reset(); client.zoneIn(); pumpFor(client.SETTLE + 0.1);
    client.onFrame(helloReply(lastSent(), SESSION));
    pumpFor(0.1);
    check('CL-06b a WATCH went', opOf(lastSent()), wire.op.WATCH);
    pumpFor(3 * client.RETRY + 0.5);
    check('CL-06b escalated to RESYNC', opOf(lastSent()), wire.op.RESYNC);
    check('CL-06b mode 0', wire.u8(payloadOf(lastSent()), 12), wire.resyncMode.RENEW);
end

-- CL-14: the session follows demand. Nothing goes before AutoAcc asks for a
-- decision; a question starts the session; IDLE_AFTER without one ends it
-- with STOP; an escalation never revives a session nothing wants.
do
    client.IDLE_AFTER = 10;
    client._unwant();
    client.reset(); client.zoneIn();
    local n0 = #sent;
    pumpFor(client.SETTLE + 5);
    check('CL-14 no HELLO before AutoAcc asks', #sent, n0);
    check('CL-14 and says why', client.state().why, 'waiting for an AutoAcc piece');
    check('CL-14 not wanted', client.state().wanted, false);
    client.want();
    pumpFor(0.1);
    check('CL-14 a question starts the session', opOf(lastSent()), wire.op.HELLO);
    client.onFrame(helloReply(lastSent(), SESSION));
    pumpFor(0.1);
    local w = lastSent();
    check('CL-14 then the WATCH', opOf(w), wire.op.WATCH);
    client.onFrame(watchReply(w, 0, wire.u32(payloadOf(w), 16)));
    pumpFor(client.IDLE_AFTER - 1);
    check('CL-14 still live inside IDLE_AFTER', client.state().phase, 'live');
    pumpFor(1.1);
    local stop = lastSent();
    check('CL-14 an idle session ends with STOP', opOf(stop), wire.op.STOP);
    check('CL-14 END_SESSION', wire.u8(payloadOf(stop), 13), wire.stopFlag.END_SESSION);
    check('CL-14 the session is gone', client.state().session, 0);
    check('CL-14 waiting again', client.state().phase, 'settling');
    client.onFrame(reply(wire.op.STOP, seqOf(stop), 0, wire.header(0, 12, SESSION, nonceOf(stop))));
    local n1, changes = #sent, 0;
    client._onState = function() changes = changes + 1; end;
    pumpFor(5);
    client._onState = nil;
    check('CL-14 quiet while nothing asks', #sent, n1);
    check('CL-14 and waiting changes nothing frame to frame', changes, 0);
    client.want();
    pumpFor(0.1);
    local h2 = lastSent();
    check('CL-14 the next question says HELLO again', opOf(h2), wire.op.HELLO);
    client._unwant();
    pumpFor(3 * client.RETRY + 0.5);
    check('CL-14 an unanswered HELLO does not loop once unwanted', client.state().phase, 'settling');
    local n2 = #sent;
    pumpFor(5);
    check('CL-14 and stays quiet', #sent, n2);
    client.IDLE_AFTER = 1e9; client.want();
end

-- CL-15: AutoAcc's questions. 'republish' is a RESYNC mode 1 for the battle
-- lane, 'renew' a mode 0; nothing goes without a live session.
do
    client.reset();
    check('CL-15 no session, no question', client.ask('republish'), false);
    client.zoneIn(); pumpFor(client.SETTLE + 0.1);
    client.onFrame(helloReply(lastSent(), SESSION));
    pumpFor(0.1);
    local w = lastSent();
    client.onFrame(watchReply(w, 0, wire.u32(payloadOf(w), 16)));
    check('CL-15 asked', client.ask('republish'), true);
    pumpFor(0.1);
    local r = lastSent();
    check('CL-15 a RESYNC', opOf(r), wire.op.RESYNC);
    check('CL-15 mode REPUBLISH', wire.u8(payloadOf(r), 12), wire.resyncMode.REPUBLISH);
    check('CL-15 the battle lane', wire.u8(payloadOf(r), 13), 0x01);
    client.onFrame(resyncReply(r, 0, wire.u32(payloadOf(w), 16), 1));
    check('CL-15 renew asked', client.ask('renew'), true);
    pumpFor(0.1);
    check('CL-15 mode RENEW', wire.u8(payloadOf(lastSent()), 12), wire.resyncMode.RENEW);
    check('CL-15 nothing else is a question', client.ask('hello'), false);
end

-- CL-16: an accepted push carries its comparison key.
do
    local before = #frames;
    local gen = client.state().watchGen;
    client.onFrame(snapshot(client.state().lastRev + 1, gen));
    check('CL-16 handed on', #frames, before + 1);
    check('CL-16 with its key', frames[#frames].key, wire.snapshotKey(snapshot(1, gen).payload));
end

-- CL-13: init.lua's tap blocks every frame of the partition, malformed and
-- unknown ops too, and leaves the other partitions alone.
local handlers = {};
ashita = { events = { register = function(_, name, fn) handlers[name] = fn; end } };
AshitaCore = { GetPacketManager = function() return { AddOutgoingPacket = function() end }; end };
package.loaded['dlac\\servers\\ascensionxi\\transport'] = {
    _clock = function() return time; end, send = function() return true; end,
    received = function() end, abandon = function() end,
};
local init = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\init');
local tap = assert(handlers.dlac_axi_combat_telemetry, 'the tap is registered');
local function frameOf(op, seq, len)
    local body = string.char(op, seq, 0, 0) .. string.rep('\0', len or 0);
    local words = math.floor((4 + #body + 3) / 4);
    local s = wire.w16(words * 512 + 0x1E0) .. wire.w16(0) .. body;
    return s .. string.rep('\0', words * 4 - #s);
end
for _, op in ipairs({ 0xC0, 0xC1, 0xC3, 0xC6, 0xC8, 0xCF }) do
    local e = { id = 0x1E0, data = frameOf(op, 0, op == 0xC6 and 0 or 12) };
    tap(e);
    check(('CL-13 blocks op %02X'):format(op), e.blocked, true);
end
local e = { id = 0x1E0, data = frameOf(0xC8, 0, 2) };
tap(e);
check('CL-13 blocks a malformed push', e.blocked, true);
for _, op in ipairs({ 0x40, 0x90, 0xA0, 0xB0, 0xB1, 0xBF, 0xD0 }) do
    local other = { id = 0x1E0, data = frameOf(op, 1, 12) };
    tap(other);
    check(('CL-13 leaves op %02X'):format(op), other.blocked, nil);
end
check('CL-13 the unload hook', type(handlers.dlac_axi_combat_telemetry_unload), 'function');
check('CL-13 a pump', type(init.pump), 'function');

print(('ascensionxi_telemetry_client: %d passed, %d failed'):format(pass, fail));
if fail > 0 then os.exit(1); end
