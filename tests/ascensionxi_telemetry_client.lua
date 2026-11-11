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
-- then the escalation to HELLO, after the backoff (2026-11-09).
local renew = lastSent();
pumpFor(client.RETRY + 0.1);
check('CL-05 retried', #sent, n + 2);
check('CL-05 same seq', seqOf(lastSent()), seqOf(renew));
check('CL-05 same nonce', nonceOf(lastSent()), nonceOf(renew));
check('CL-05 the slot was given back', #abandoned >= 1 and abandoned[#abandoned].seq == seqOf(renew), true);
pumpFor(client.RETRY + 0.1);
pumpFor(client.RETRY + 0.1);
check('CL-05 three tries, then no HELLO at once', opOf(lastSent()), wire.op.RESYNC);
check('CL-05 the box hears the server is not answering', client.state().retrying, true);
pumpFor(client.HELLO_BACKOFF + 0.1);
check('CL-05 escalates to HELLO after the backoff', opOf(lastSent()), wire.op.HELLO);

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

-- CL-07: NO_SESSION sends the client back to HELLO, through the backoff like
-- every automatic HELLO; it is an answer, so the box does not call the
-- server silent.
local w3 = lastSent();
client.onFrame(reply(wire.op.WATCH, seqOf(w3), 0, wire.header(wire.result.NO_SESSION, 12, 0, nonceOf(w3))));
pumpFor(0.1);
check('CL-07 no HELLO at once', opOf(lastSent()), wire.op.WATCH);
check('CL-07 an answer: not "not answering"', client.state().retrying, false);
pumpFor(client.HELLO_BACKOFF);
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

-- CL-11: HELLO from another character's answer is a failed round: never
-- live on it, and never stuck on it either (2026-11-09: it used to leave the
-- client in 'hello' with nothing queued until the next zone change).
client.reset(); client.zoneIn(); pumpFor(client.SETTLE + 0.1);
client.onFrame(helloReply(lastSent(), SESSION, 999));
check('CL-11 not live on a stranger', client.state().phase ~= 'live', true);
local n11 = #sent;
pumpFor(client.HELLO_BACKOFF - 0.2);
check('CL-11 quiet during the backoff', #sent, n11);
check('CL-11 the box hears the server is not answering', client.state().retrying, true);
pumpFor(0.4);
check('CL-11 then HELLO again, not stuck', #sent == n11 + 1 and opOf(lastSent()) == wire.op.HELLO, true);
client.onFrame(helloReply(lastSent(), SESSION));
check('CL-11 our own answer: live', client.state().phase, 'live');
check('CL-11 and the backoff starts over', client.state().failures, 0);
check('CL-11 and the box is told', client.state().retrying, false);

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
    check('CL-14 unwanted, a failed round is not called the server\'s', client.state().retrying, false);
    pumpFor(client.HELLO_BACKOFF);
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

-- CL-27: the shared transport writes a module's own line (no frame) as a
-- 'note' at seq 0, through the same batched wire log.
do
    local t = dofile('servers/ascensionxi/transport.lua');
    local got = nil;
    t._audit = function(event, op, seq, why) got = { event = event, op = op, seq = seq, why = why }; end;
    t.note(wire.op.HELLO, 'combat telemetry: a line');
    check('CL-27 a note', got and got.event, 'note');
    check('CL-27 under its op', got and got.op, wire.op.HELLO);
    check('CL-27 seq 0', got and got.seq, 0);
    check('CL-27 the text', got and got.why, 'combat telemetry: a line');
end

-- CL-13: init.lua's tap blocks every frame of the partition, malformed and
-- unknown ops too, and leaves the other partitions alone.
local handlers = {};
ashita = { events = { register = function(_, name, fn) handlers[name] = fn; end } };
AshitaCore = { GetPacketManager = function() return { AddOutgoingPacket = function() end }; end };
local wireNotes = {};
package.loaded['dlac\\servers\\ascensionxi\\transport'] = {
    _clock = function() return time; end, send = function() return true; end,
    received = function() end, abandon = function() end,
    note = function(op, why) wireNotes[#wireNotes + 1] = { op = op, why = why }; end,
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

-- CL-13b (2026-11-09): init.lua's seams for the start without a zone-in. In
-- game = a main job and an id, and not mid-zone by the packets (a 0x00B
-- until its 0x00A) or by GetIsZoning; the id is the zone-in packet's, and
-- the party's own entry's before one; the client's lines reach the wire log.
do
    local job, serverId, isZoning = 0, 21828, false;
    AshitaCore = {
        GetPacketManager = function() return { AddOutgoingPacket = function() end }; end,
        GetMemoryManager = function() return {
            GetPlayer = function() return {
                GetMainJob = function() return job; end,
                GetIsZoning = function() return isZoning; end,
            }; end,
            GetParty = function() return { GetMemberServerId = function() return serverId; end }; end,
        }; end,
    };
    check('CL-13b before login (main job 0): not in game', client._inGame(), false);
    job = 1;
    check('CL-13b a main job and an id: in game', client._inGame(), true);
    check('CL-13b no zone-in yet: the party\'s id', client._charId(), 21828);
    serverId = 0;
    check('CL-13b no id: not in game', client._inGame(), false);
    check('CL-13b and no id to check a reply against', client._charId(), nil);
    serverId = 21828;
    isZoning = 1;
    check('CL-13b GetIsZoning (a number): not in game', client._inGame(), false);
    isZoning = true;
    check('CL-13b GetIsZoning (a bool): not in game', client._inGame(), false);
    isZoning = false;
    tap({ id = 0x00B, data = string.rep('\0', 32) });
    check('CL-13b between a 0x00B and its 0x00A: not in game', client._inGame(), false);
    tap({ id = 0x00A, data = string.rep('\0', 4) .. wire.w32(4321) .. string.rep('\0', 24) });
    check('CL-13b after the 0x00A: in game again', client._inGame(), true);
    check('CL-13b the zone-in packet\'s id wins', client._charId(), 4321);
    client._note('a line');
    check('CL-13b a client line reaches the wire log', wireNotes[#wireNotes] and wireNotes[#wireNotes].why,
        'combat telemetry: a line');
    check('CL-13b under the telemetry partition\'s op', wireNotes[#wireNotes] and wireNotes[#wireNotes].op, wire.op.HELLO);
end

-- CL-17: /dl accuracy and /dl autoacc both toggle the box, and an open box
-- keeps the session wanted through the client.
local monitor = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\monitor');
local cmd = assert(handlers.dlac_axi_autoacc_cmd, 'the command is registered');
monitor.visible = false;
local e1 = { command = '/dl accuracy' };
cmd(e1);
check('CL-17 /dl accuracy opens the box', monitor.visible, true);
check('CL-17 and is ours', e1.blocked, true);
cmd({ command = '/dl autoacc' });
check('CL-17 /dl autoacc closes it again', monitor.visible, false);
local e3 = { command = '/dl accuracyx' };
cmd(e3);
check('CL-17 another word is not ours', e3.blocked, nil);
check('CL-17 the box wants the session (and the cursor\'s monster) through the client', monitor._want, client.wantTarget);
check('CL-17 a ranged decision asks the client for the cursor\'s monster',
    require('dlac\\servers\\ascensionxi\\modules\\telemetry\\autoacc')._wantTarget, client.wantTarget);

-- CL-18: the pack mounts the module, and the Gear Helpers row is on.
local modules = dofile('servers/ascensionxi/modules.lua');
local mounted = false;
for _, name in ipairs(modules) do if name == 'telemetry' then mounted = true; end end
check('CL-18 the pack mounts telemetry', mounted, true);
check('CL-18 the AutoAcc helper row is enabled', dofile('servers/ascensionxi/features.lua').helpers.autoacc, true);

-- CL-19 (2026-11-06, the Ranger release): not engaged, the server has no
-- battle target; while ranged decisions are wanted the lane is bound to the
-- cursor's monster (a WATCH without FOLLOW), and engaging -- or no monster
-- on the cursor -- goes back to FOLLOW. Each change is one new WatchGen.
local engagedNow, cursor = true, { id = 0x01000ABC, index = 188 };
-- CL-13 ran init.lua, which put the real transport's seams in: the fakes again.
client._clock = function() return time; end;
client._send = function(p) if busy then return false; end sent[#sent + 1] = p; return true; end;
client._received = function(op, seq) received[#received + 1] = { op = op, seq = seq }; end;
client._abandon = function(op, seq) abandoned[#abandoned + 1] = { op = op, seq = seq }; end;
client._charId = function() return 21828; end;
client._onFrame = function(f) frames[#frames + 1] = f; end;
busy = false;
client._engaged = function() return engagedNow; end;
client._cursorTarget = function() return cursor; end;
client._battleTarget = nil;
client.IDLE_AFTER = 1e9;
client._unwant();
client.want();
client.reset();
client.zoneIn();
pumpFor(client.SETTLE + 0.1);
client.onFrame(helloReply(lastSent(), SESSION));
pumpFor(0.1);
local w19 = lastSent();
check('CL-19 a FOLLOW WATCH first', wire.u8(payloadOf(w19), 13), wire.watchFlag.FOLLOW);
client.onFrame(watchReply(w19, 0, wire.u32(payloadOf(w19), 16)));
local gen0 = client.state().watchGen;
engagedNow = false;
pumpFor(1);
check('CL-19 not engaged, no ranged question: still FOLLOW', client.state().watchGen, gen0);
check('CL-19 and nothing bound', client.state().bound, nil);
engagedNow = true;
client.wantTarget();
pumpFor(1);
check('CL-19 engaged, a ranged question changes nothing', client.state().watchGen, gen0);
engagedNow = false;
pumpFor(0.5);
local wb = lastSent();
local wbp = payloadOf(wb);
check('CL-19 not engaged: a WATCH', opOf(wb), wire.op.WATCH);
check('CL-19 without FOLLOW', wire.u8(wbp, 13), 0);
check('CL-19 naming the cursor\'s monster', wire.u32(wbp, 20), cursor.id);
check('CL-19 and its index', wire.u16(wbp, 24), cursor.index);
check('CL-19 a new generation', wire.u32(wbp, 16), gen0 + 1);
check('CL-19 bound', client.state().bound and client.state().bound.id, cursor.id);
client.onFrame(watchReply(wb, 0, gen0 + 1));
local function aimed(rev, gen, id)
    local s = snapshot(rev, gen);
    s.payload = s.payload:sub(1, 40) .. wire.w32(id) .. s.payload:sub(45);
    return s;
end
local rev19 = client.state().lastRev;
check('CL-19 a push for another monster is refused', client.onFrame(aimed(rev19 + 1, gen0 + 1, 0x01000DEF)), false);
check('CL-19 counted as target', client.state().stats.rejected.target, 1);
check('CL-19 the bound monster\'s push lands', client.onFrame(aimed(rev19 + 2, gen0 + 1, cursor.id)), true);
local nSent = #sent;
pumpFor(1);
check('CL-19 the same monster asks nothing again', #sent, nSent);
cursor = { id = 0x01000DEF, index = 201 };
pumpFor(0.5);
check('CL-19 another monster on the cursor: rebound', wire.u32(payloadOf(lastSent()), 20), cursor.id);
check('CL-19 a generation further', client.state().watchGen, gen0 + 2);
client.onFrame(watchReply(lastSent(), 0, gen0 + 2));
cursor = nil;
pumpFor(0.5);
check('CL-19 no monster on the cursor: FOLLOW again', wire.u8(payloadOf(lastSent()), 13), wire.watchFlag.FOLLOW);
check('CL-19 and no target in it', wire.u32(payloadOf(lastSent()), 20), 0);
client.onFrame(watchReply(lastSent(), 0, gen0 + 3));
cursor = { id = 0x01000ABC, index = 188 };
pumpFor(0.5);
check('CL-19 a monster again: bound again', client.state().bound and client.state().bound.id, cursor.id);
client.onFrame(watchReply(lastSent(), 0, gen0 + 4));
engagedNow = true;
pumpFor(0.5);
check('CL-19 engaging goes back to FOLLOW', wire.u8(payloadOf(lastSent()), 13), wire.watchFlag.FOLLOW);
check('CL-19 unbound', client.state().bound, nil);
client.onFrame(watchReply(lastSent(), 0, gen0 + 5));
engagedNow = nil;
client.wantTarget();
pumpFor(0.5);
check('CL-19 an unreadable status binds nothing', client.state().bound, nil);
engagedNow = false;
client._unwant();
client.want();
pumpFor(0.5);
check('CL-19 the ranged question expired: nothing binds', client.state().bound, nil);
client._engaged, client._cursorTarget = nil, nil;

-- CL-20..CL-26 (2026-11-09, a prod report: the box said "Starting" for a
-- whole session). The client started only on a zone-in packet, so a dlac
-- that loaded after it never sent a HELLO; and a server that did not
-- answer got one every RETRY, without end.
local inGameNow, notes = true, {};
client._inGame = function() return inGameNow; end;
client._note = function(text) notes[#notes + 1] = text; end;
client._charId = function() return 21828; end;
client.IDLE_AFTER = 1e9;
local function hellosSince(from)
    local c = 0;
    for i = from + 1, #sent do if opOf(sent[i]) == wire.op.HELLO then c = c + 1; end end
    return c;
end
local function noteHas(fragment)
    for _, s in ipairs(notes) do if s:find(fragment, 1, true) then return true; end end
    return false;
end

-- CL-20: loaded in game: once something asks, the client settles as after a
-- zone-in and HELLOs, with no zone-in at all; the start is in the wire log.
do
    client._unwant();
    client.reset();   -- as dlac loads: no zone edge seen
    local n0 = #sent;
    pumpFor(5);
    check('CL-20 nothing while nothing asks', #sent, n0);
    check('CL-20 still off', client.state().phase, 'off');
    client.want();
    pumpFor(client.SETTLE - 0.2);
    check('CL-20 it settles first, as after a zone-in', #sent, n0);
    pumpFor(0.4);
    check('CL-20 one HELLO, no zone-in needed', #sent, n0 + 1);
    check('CL-20 a HELLO', opOf(lastSent()), wire.op.HELLO);
    check('CL-20 the start is in the wire log', noteHas('no zone-in since dlac loaded'), true);
    client.onFrame(helloReply(lastSent(), SESSION));
    check('CL-20 live', client.state().phase, 'live');
end

-- CL-21: loaded before login (main job 0): nothing until the 0x00A, then
-- exactly one HELLO.
do
    inGameNow = false;
    client.reset();
    local n0 = #sent;
    pumpFor(10);
    check('CL-21 before login: nothing', #sent, n0);
    check('CL-21 off', client.state().phase, 'off');
    client.zoneIn();   -- the login's 0x00A; memory reads a job after it
    inGameNow = true;
    pumpFor(client.SETTLE + 0.1);
    check('CL-21 the zone-in: one HELLO', hellosSince(n0), 1);
    client.onFrame(helloReply(lastSent(), SESSION));
    pumpFor(5);
    check('CL-21 and only one', hellosSince(n0), 1);
end

-- CL-22: loaded in game, then a 0x00A (a late load right at login): one
-- session at a time; the zone-in replaces the start as it replaces a session.
do
    client.reset();
    pumpFor(client.SETTLE + 0.1);
    local h = lastSent();
    check('CL-22 the start\'s HELLO', opOf(h), wire.op.HELLO);
    local n0 = #sent;
    client.zoneIn();
    check('CL-22 the zone-in takes over', client.state().phase, 'settling');
    check('CL-22 the start\'s HELLO is forgotten', client.state().pending, nil);
    check('CL-22 a late answer to it is not ours', client.onFrame(helloReply(h, SESSION)), false);
    pumpFor(client.SETTLE + 0.1);
    check('CL-22 one HELLO for the zone-in', hellosSince(n0), 1);
    client.onFrame(helloReply(lastSent(), SESSION));
    pumpFor(0.1);
    client.onFrame(watchReply(lastSent(), 0, client.state().watchGen));
    pumpFor(10);
    check('CL-22 one session: no second HELLO', hellosSince(n0), 1);
    check('CL-22 live', client.state().phase, 'live');
end

-- CL-23: a zone line that begins before anything asks (a 0x00B, no 0x00A
-- yet) leaves the start to its 0x00A: nothing goes in between.
do
    client._unwant();
    client.reset();
    client.zoneOut();
    client.want();
    local n0 = #sent;
    pumpFor(10);
    check('CL-23 no start between a 0x00B and its 0x00A', #sent, n0);
    check('CL-23 off', client.state().phase, 'off');
    client.zoneIn();
    pumpFor(client.SETTLE + 0.1);
    check('CL-23 the 0x00A starts it', hellosSince(n0), 1);
end

-- CL-24: a server that never answers, ten minutes with the box open (it
-- wants the session every frame): rounds of TRIES HELLOs, each round
-- waiting 5, 10, 20, 40, then 60 s; at most TRIES a minute once capped;
-- the box hears it; each backoff is one line in the wire log.
local roundStarts, roundSizes;
local function silentFor(seconds)
    roundStarts, roundSizes = {}, {};
    local n0, lastSeq = #sent, nil;
    local sendTimes = {};
    for _ = 1, math.floor(seconds * 20) do
        time = time + 0.05;
        client.want();
        client.pump();
        while n0 < #sent do
            n0 = n0 + 1;
            if opOf(sent[n0]) == wire.op.HELLO then
                sendTimes[#sendTimes + 1] = time;
                if seqOf(sent[n0]) ~= lastSeq then
                    roundStarts[#roundStarts + 1] = time;
                    roundSizes[#roundSizes + 1] = 0;
                    lastSeq = seqOf(sent[n0]);
                end
                roundSizes[#roundSizes] = roundSizes[#roundSizes] + 1;
            end
        end
    end
    return sendTimes;
end
do
    client.reset();
    notes = {};
    local t0 = time;
    local times = silentFor(600);
    check('CL-24 at most 40 HELLOs in ten minutes (about 400 before)', #times <= 40, true);
    check('CL-24 and it keeps asking', #times >= 30, true);
    check('CL-24 the first one after SETTLE', math.abs(times[1] - t0 - client.SETTLE) < 0.2, true);
    local gaps = { 5, 10, 20, 40, 60, 60, 60 };
    for i, wait in ipairs(gaps) do
        local gap = roundStarts[i + 1] and (roundStarts[i + 1] - roundStarts[i]) or -1;
        check(('CL-24 round %d waits %d s'):format(i + 1, wait),
            math.abs(gap - (client.TRIES * client.RETRY + wait)) < 0.3, true);
    end
    local allFull = true;
    for i = 1, #roundSizes - 1 do if roundSizes[i] ~= client.TRIES then allFull = false; end end
    check('CL-24 each round is TRIES sends of one HELLO', allFull, true);
    local worst = 0;
    for i = 1, #times do
        local c = 0;
        for j = i, #times do if times[j] - times[i] < 60 then c = c + 1; end end
        if times[i] - t0 > 180 and c > worst then worst = c; end
    end
    check('CL-24 capped: at most TRIES HELLOs in any minute', worst <= client.TRIES, true);
    check('CL-24 the box hears it', client.state().retrying, true);
    check('CL-24 the backoff is in the wire log', noteHas('no answer: HELLO again in 5 s') and noteHas('HELLO again in 60 s'), true);
    -- An accepted reply resets it: the next silence starts at 5 s again.
    for _ = 1, 20 * (client.HELLO_BACKOFF_MAX + 10) do
        if client.state().pending == 'hello' then break; end
        time = time + 0.05; client.pump();
    end
    client.onFrame(helloReply(lastSent(), SESSION));
    check('CL-24 an answer: live', client.state().phase, 'live');
    check('CL-24 and the count starts over', client.state().failures, 0);
    check('CL-24 and the box is told', client.state().retrying, false);
    pumpFor(0.1);
    client.onFrame(watchReply(lastSent(), 0, client.state().watchGen));
    -- Silent again: the lease renewal goes unanswered, then the HELLO waits 5 s.
    times = silentFor(15 + client.TRIES * client.RETRY + client.HELLO_BACKOFF + 1);
    check('CL-24 silent again: one HELLO, after 5 s', #times, 1);
end

-- CL-25: a zone-in starts the backoff over (demand never does): after a long
-- silence, the zone-in's HELLO goes after SETTLE and its next round waits 5 s.
do
    client.reset();
    silentFor(300);
    check('CL-25 the backoff is long by now', client.state().failures >= 5, true);
    client.zoneIn();
    check('CL-25 the zone-in starts over', client.state().failures, 0);
    check('CL-25 and is not "not answering" yet', client.state().retrying, false);
    silentFor(client.SETTLE + 2 * client.TRIES * client.RETRY + client.HELLO_BACKOFF + 0.5);
    check('CL-25 its first round after SETTLE, the next after 5 s', #roundStarts, 2);
end

-- CL-26: UNAVAILABLE keeps its own 30 s, and the box says the server is not
-- answering all through it, the next HELLO included; unwanted, it does not.
do
    client.reset(); client.zoneIn(); pumpFor(client.SETTLE + 0.1);
    client.onFrame(reply(wire.op.HELLO, seqOf(lastSent()), wire.status.UNAVAILABLE, ''));
    check('CL-26 the box hears it', client.state().retrying, true);
    check('CL-26 the backoff is in the wire log', noteHas('unavailable: HELLO again in 30 s'), true);
    pumpFor(client.BACKOFF + 0.5);
    check('CL-26 the HELLO after it', opOf(lastSent()), wire.op.HELLO);
    check('CL-26 still not answering while it waits', client.state().retrying, true);
    client._unwant();
    check('CL-26 unwanted: the box does not say so', client.state().retrying, false);
    client.want();
end

-- CL-07b: NO_SESSION on a RESYNC waits the backoff too.
do
    client.reset(); client.zoneIn(); pumpFor(client.SETTLE + 0.1);
    client.onFrame(helloReply(lastSent(), SESSION));
    pumpFor(0.1);
    client.onFrame(watchReply(lastSent(), 0, client.state().watchGen));
    pumpFor(15.1);
    local r = lastSent();
    check('CL-07b a renewal', opOf(r), wire.op.RESYNC);
    client.onFrame(reply(wire.op.RESYNC, seqOf(r), 0, wire.header(wire.result.NO_SESSION, 12, 0, nonceOf(r))));
    pumpFor(0.1);
    check('CL-07b no HELLO at once', opOf(lastSent()), wire.op.RESYNC);
    pumpFor(client.HELLO_BACKOFF);
    check('CL-07b HELLO after the backoff', opOf(lastSent()), wire.op.HELLO);
end

print(('ascensionxi_telemetry_client: %d passed, %d failed'):format(pass, fail));
if fail > 0 then os.exit(1); end
