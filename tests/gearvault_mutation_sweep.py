"""Mutation sweep for the Gear Vault client and the shared 0x1E0 gate
(docs/design/gear-vault-live-sync.md, "Stage 8 pass"). Every guard is broken
once, every Gear Vault suite runs, and at least one must go red. The file is
always restored.

    python tests/gearvault_mutation_sweep.py            every mutant (resumes)
    python tests/gearvault_mutation_sweep.py V07 T05    only these
    python tests/gearvault_mutation_sweep.py --fresh    forget earlier results

Run from the repo root on a clean tree (it refuses otherwise). Lua 5.4 as
`lua` (or set LUA=lua5.4). Results append to a JSONL in the temp directory,
so an interrupted run picks up where it stopped. Prints a markdown board and
exits 1 when a mutant survives, cannot be applied (the guard moved: re-read
it and update the pattern) or breaks the file's syntax -- unless the mutant
is listed in ACCEPTED with the reason it is not a defect.
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.gettempdir()) / 'dlac-gearvault-mutation-sweep.jsonl'
LUA = os.environ.get('LUA', 'lua')

GV = 'servers/ascensionxi/modules/gearvault/'
VC = GV + 'vaultclient.lua'
RC = GV + 'reconcile.lua'
DV = GV + 'derive.lua'
SV = GV + 'sharedvault.lua'
UI = GV + 'vaultui.lua'
IN = GV + 'init.lua'
TR = 'servers/ascensionxi/transport.lua'

SUITES = [
    ['tests/gearvault_live.lua'],
    ['tests/gearvault_instances.lua'],
    ['tests/gearvault_counts.lua'],
    ['tests/gearvault_sync.lua'],
    ['tests/gearvault_sync_probe.lua', '--budget'],
    ['tests/gearvault_augmented_draw.lua'],
    ['tests/gearvault_stage8.lua'],
    ['tests/gearvault_shared.lua'],
]
FULL = SUITES + [['tests/run_tests.lua']]

# id, guard, file, old, new[, suites]
M = [
    # ---- the vault client: seqs, retries, the replay window ----
    ('V01', 'a seq is never 0 (pushes own seq 0)', VC,
     'st.seq = (st.seq or 0) % 255 + 1;', 'st.seq = (st.seq or 0) % 256;'),
    ('V02', 'a DEPOSIT is a write (never re-run as a read)', VC,
     '[M.op.DEPOSIT] = true, [M.op.WITHDRAW] = true,', '[M.op.DEPOSIT] = false, [M.op.WITHDRAW] = true,'),
    ('V03', 'a WITHDRAW is a write', VC,
     '[M.op.DEPOSIT] = true, [M.op.WITHDRAW] = true,', '[M.op.DEPOSIT] = true, [M.op.WITHDRAW] = false,'),
    ('V04', 'a LAYOUT_SET2 is a write', VC,
     '[M.op.LAYOUT_SET2] = true };', '[M.op.LAYOUT_SET2] = false };'),
    ('V05', 'two write retries, no more', VC,
     'M.MAX_RETRIES    = 2;', 'M.MAX_RETRIES    = 4;'),
    ('V06', 'write retries 1.5 s apart (inside the window)', VC,
     'M.SEND_TIMEOUT   = 1.5;', 'M.SEND_TIMEOUT   = 3.0;'),
    ('V07', 'no write retry after WRITE_DEADLINE', VC,
     'local late = isWrite(p.op) and now - (p.firstSentAt or p.sentAt) >= M.WRITE_DEADLINE;',
     'local late = false;'),
    ('V08', 'the deadline counts from the FIRST send', VC,
     'st.pending.firstSentAt = st.pending.firstSentAt or now;', 'st.pending.firstSentAt = now;'),
    ('V09', 'a retry re-sends the SAME seq', VC,
     "sendPending(now, true);   -- SAME Seq",
     "st.pending.frame[6] = (st.pending.frame[6] % 255) + 1; sendPending(now, true);   -- SAME Seq"),
    ('V10', 'an unknown deposit/withdraw re-reads the vault', VC,
     "        M.markStale(0, why);\n        M.invalidateLayout();\n    else",
     "        M.invalidateLayout();\n    else"),
    ('V11', 'an unknown layout edit re-reads the layout', VC,
     "        M.markStale(M.SETTLE_EDIT, why);\n        M.invalidateLayout();\n        M.requestLayout(0);\n    end\nend",
     "        M.markStale(M.SETTLE_EDIT, why);\n        M.invalidateLayout();\n    end\nend"),
    ('V12', 'failWrite takes the request off its queue (no fresh-seq resend)', VC,
     "        local req = table.remove(q or {}, 1);\n        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, nil, 'timeout'); end",
     "        local req = (q or {})[1];\n        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, nil, 'timeout'); end"),
    ('V13', 'an exhausted write is failed, never re-queued', VC,
     "                if isWrite(p.op) then\n                    failWrite(p, 'write timeout');",
     "                if false then\n                    failWrite(p, 'write timeout');"),
    ('V14', 'the deposit slot guard (expectedInstanceId)', VC,
     'if not at or at.instanceId ~= e.expectedInstanceId or at.revision ~= M.revision then',
     'if false then'),
    # ---- zone lines ----
    ('V20', 'a write on the wire at the zone-in is failed, not retried', VC,
     '        if isWrite(p.op) then\n            -- the reply died with the old zone',
     '        if false then\n            -- the reply died with the old zone'),
    ('V21', '...and its pending slot is cleared', VC,
     "            st.pending = nil;\n            abandon(p);\n            failWrite(p, 'write lost at a zone line');",
     "            abandon(p);\n            failWrite(p, 'write lost at a zone line');"),
    ('V22', 'nothing leaves while zoning', VC,
     '    if st.zoning then\n        if st.zoneInAt ~= nil and now - st.zoneInAt >= M.ZONE_LOAD_TIMEOUT then',
     '    if false then\n        if st.zoneInAt ~= nil and now - st.zoneInAt >= M.ZONE_LOAD_TIMEOUT then'),
    ('V23', 'a zone whose load is never seen times out', VC,
     'now - st.zoneInAt >= M.ZONE_LOAD_TIMEOUT then', 'now - st.zoneInAt >= M.ZONE_LOAD_TIMEOUT * 100 then'),
    ('V24', 'a zone line ends after a RUN of >= 2 containers', VC,
     'if run >= 2 then zoneSettled(M._clock()); end', 'if run >= 1 then zoneSettled(M._clock()); end'),
    ('V25', 'nothing counts before the zone-in', VC,
     'if not st.zoning or st.zoneInAt == nil then return; end', 'if not st.zoning then return; end'),
    ('V26', 'a zone-in long after the zone-out is a login', VC,
     'and now - st.zoneOutAt <= M.ZONE_LINE_MAX;', 'and true;'),
    ('V27', 'only LogoutState 2 is a zone line', VC,
     'st.zoneLine = (state == M.LOGOUT_ZONECHANGE);', 'st.zoneLine = true;'),
    ('V28', 'a login drops the subscription', VC,
     "        st.subscribed = false;   -- the server's game-in forgot it\n", ''),
    ('V29', 'the zone-in re-send is not movement', VC,
     '    if st.zoning then return false; end\n    local cid, slot, newId, qty', '    local cid, slot, newId, qty'),
    ('V30', 'a read cut by the zone line runs again in full', VC,
     "            if p.kind == 'sync-hello' or p.kind == 'sync-list' then st.zoneFull = true; end\n", ''),
    ('V31', 'a copy whose slot changed while zoning is forgotten', VC,
     'if not ok or id ~= e.itemId then st.instanceCache[key] = nil; dropped = true; end', 'if false then end'),
    ('V32', 'no probe in the field', VC,
     'elseif not field and not M.live() then', 'elseif not M.live() then'),
    # ---- replies ----
    ('V40', 'a reply must match the pending SEQ', VC,
     'if p == nil or p.sentAt == nil or f.op ~= p.op or f.seq ~= p.seq then',
     'if p == nil or p.sentAt == nil or f.op ~= p.op then'),
    ('V41', 'a reply must match the pending OP', VC,
     'if p == nil or p.sentAt == nil or f.op ~= p.op or f.seq ~= p.seq then',
     'if p == nil or p.sentAt == nil or f.seq ~= p.seq then'),
    ('V42', 'a push (seq 0) is never a reply', VC,
     'if f.op == M.op.CHANGED and (f.seq or 0) == 0 then return onPush(f, now); end', ''),
    ('V43', 'a batch refused part-way re-reads', VC,
     'if f.status ~= M.status.TOO_FAR and f.status ~= M.status.MALFORMED then', 'if false then'),
    ('V44', 'TOO_FAR (decided at entry 1) leaves the mirror standing', VC,
     'if f.status ~= M.status.TOO_FAR and f.status ~= M.status.MALFORMED then',
     'if f.status ~= M.status.MALFORMED then'),
    ('V45', 'a withdraw ack subtracts exactly what moved', VC,
     'row.qty = row.qty - e.moved;', 'row.qty = row.qty - e.moved * 2;'),
    ('V46', 'an unreadable deposit ack re-reads', VC,
     "M.markStale(0, 'deposit malformed reply');", ''),
    ('V47', 'an unreadable withdraw ack re-reads', VC,
     "M.markStale(0, 'withdraw malformed reply');", ''),
    ('V48', 'an unreadable edit ack re-reads', VC,
     "M.markStale(M.SETTLE_EDIT, 'layout edit malformed reply');", ''),
    ('V49', 'a stored piece re-reads the vault', VC,
     "            M.markStale(0, 'deposit');\n", ''),
    ('V50', 'a withdraw that met a gone row re-reads', VC,
     "if goneRow then M.markStale(0, 'withdraw met a gone row');", "if false then M.markStale(0, 'withdraw met a gone row');"),
    ('V51', 'a subtraction re-stamps the mirror', VC,
     'if changed then M.mirror.stamp = M._clock(); end', ''),
    ('V52', 'an active-job edit re-reads the vault', VC,
     "if req ~= nil and req.e.verb ~= M.verb.PIN and active then", 'if false then'),
    ('V53', 'a changed-copy answer re-reads both views', VC,
     'ack.code == M.code.NO_INSTANCE or ack.code == M.code.NOT_IN_LAYOUT', 'ack.code == -1 or ack.code == -2'),
    ('V54', 'the probe compares the LISTED revision', VC,
     'and (not h.instances or M.mirror.revision == h.revision) then', 'then'),
    ('V55', 'a read that missed a reason does not certify the mirror', VC,
     'local current = (gen == nil) or (gen == st.mirrorGen);', 'local current = true;'),
    ('V56', 'pages at two revisions never mix', VC,
     'if st.rowsRev ~= nil and st.rowsRev ~= chunk.revision then', 'if false then'),
    ('V57', 'a re-delivered row is skipped by key', VC,
     'if e.rowId > accLast then st.rowsAcc[#st.rowsAcc + 1] = e; accLast = e.rowId; end',
     'st.rowsAcc[#st.rowsAcc + 1] = e; accLast = math.max(accLast, e.rowId);'),
    ('V58', 'a layout page for another job is never committed', VC,
     'if p.job ~= nil and p.job ~= 0 and p.job ~= st.lastJob then', 'if false then'),
    # ---- caps, goodbye, job edges ----
    ('V60', 'a deposit never exceeds one ack frame (62)', VC,
     'return math.max(1, math.min(cap, M.MAX_DEPOSIT));', 'return math.max(1, cap);'),
    ('V61', 'an oversized deposit is refused', VC,
     '    if #entries > M.depositCap() then return false; end\n', ''),
    ('V62', 'an oversized withdraw is refused', VC,
     '    if #entries > cap then return false; end\n', ''),
    ('V63', 'the goodbye only while subscribed', VC,
     '    if not M.live() then return nil; end\n    st.subscribed = false;', '    st.subscribed = false;'),
    ('V64', 'the goodbye is said once', VC,
     '    st.subscribed = false;\n    return M.buildFrame(M.op.HELLO, nextSeq(), wu16(M.PROTO) .. wu16(0));',
     '    return M.buildFrame(M.op.HELLO, nextSeq(), wu16(M.PROTO) .. wu16(0));'),
    ('V65', 'the goodbye unsubscribes (client caps 0)', VC,
     'nextSeq(), wu16(M.PROTO) .. wu16(0));', 'nextSeq(), wu16(M.PROTO) .. wu16(M.CLIENT_CAPS));'),
    ('V66', 'cancelling keeps the edit on the wire', VC,
     '        st.layoutSetQ = { st.layoutSetQ[1] };\n        first = 2;', '        st.layoutSetQ = {};\n        first = 1;'),
    ('V67', 'a job change cancels queued edits', VC,
     "        M.cancelLayoutSets('job_changed');\n", ''),
    ('V68', 'an edit names its job when queued', VC,
     'if (e.job or 0) == 0 and st.lastJob then e.job = st.lastJob; end', ''),
    ('V69', 'a counter trade re-reads', VC,
     "    M.markStale(M.SETTLE_CHAT, 'counter trade');\n", ''),
    ('V70', 'a VAULT push re-reads', VC,
     'if has(c.scope, M.change.VAULT) or shelved then', 'if false then'),
    ('V71', 'a LAYOUT push re-reads only my job', VC,
     'and has(c.jobs, 2 ^ job);', 'and true;'),
    ('V72', 'a LOST push re-reads the lost list', VC,
     'if has(c.scope, M.change.LOST) then', 'if false then'),
    ('V73', 'an unreadable edit ack is read as nil, not false', VC,
     'if p.op == M.op.LAYOUT_SET2 then ack = M.parseLayoutSet2Ack(f.payload); else ack = M.parseLayoutSetAck(f.payload); end',
     'ack = p.op == M.op.LAYOUT_SET2 and M.parseLayoutSet2Ack(f.payload) or (p.op == M.op.LAYOUT_SET and M.parseLayoutSetAck(f.payload));'),
    ('V74', 'an unreadable LIST2 page is read as nil, not false', VC,
     'if p.op == M.op.LIST2 then chunk = M.parseList2(f.payload); else chunk = M.parseListChunk(f.payload); end',
     'chunk = p.op == M.op.LIST2 and M.parseList2(f.payload) or (p.op == M.op.LIST and M.parseListChunk(f.payload));'),
    ('V75', 'an unreadable LAYOUT_LIST2 page is read as nil, not false', VC,
     'if p.op == M.op.LAYOUT_LIST2 then chunk = M.parseLayout2(f.payload); else chunk = M.parseLayoutChunk(f.payload); end',
     'chunk = p.op == M.op.LAYOUT_LIST2 and M.parseLayout2(f.payload) or (p.op == M.op.LAYOUT_LIST and M.parseLayoutChunk(f.payload));'),
    # ---- the shared gate ----
    ('T01', 'MIN_GAP after the last send / reply', TR,
     '    if last and now - last < M.MIN_GAP then return false; end\n    if not foreignQuiet(now) then return false; end\n    if pending then',
     '    if not foreignQuiet(now) then return false; end\n    if pending then'),
    ('T02', 'a foreign 0x1E0 holds send()', TR,
     '    if not foreignQuiet(now) then return false; end\n    if pending then', '    if pending then'),
    ('T03', 'a foreign 0x1E0 holds idle()', TR,
     '    if not foreignQuiet(now) then return false; end\n    return pending == nil', '    return pending == nil'),
    ('T04', 'only 0x1E0 counts as foreign', TR,
     "if id ~= 0x1E0 or type(data) ~= 'string' then return; end", "if type(data) ~= 'string' then return; end"),
    ('T05', 'our own frames are recognised', TR,
     '        if body:sub(1, #recent[i]) == recent[i] then return; end\n', ''),
    ('T06', 'our frame is remembered BEFORE the send (Ashita runs packet_out inside it)', TR,
     "    recent[#recent + 1] = string.char(unpack(packet, 5));\n    if #recent > 8 then table.remove(recent, 1); end\n    local sent, result = pcall(M._send, packet);\n    if not sent or result == false then table.remove(recent); return false; end",
     "    local sent, result = pcall(M._send, packet);\n    if not sent or result == false then return false; end\n    recent[#recent + 1] = string.char(unpack(packet, 5));\n    if #recent > 8 then table.remove(recent, 1); end"),
    ('T07', 'a refused send forgets its frame', TR,
     'if not sent or result == false then table.remove(recent); return false; end',
     'if not sent or result == false then return false; end'),
    ('T08', 'FOREIGN_GAP is a real wait', TR,
     'FOREIGN_GAP = 0.3', 'FOREIGN_GAP = 0.0'),
    ('T09', 'the memory of our frames is kept', TR,
     'if #recent > 8 then table.remove(recent, 1); end', 'if #recent > 0 then table.remove(recent, 1); end'),
    ('T10', 'T1: only the pending SEQ matches', TR,
     "    if pending and pending.op == op and pending.seq == seq then\n        audit('reply'",
     "    if pending and pending.op == op then\n        audit('reply'"),
    ('T11', 'MAX_WAIT frees a lost peer', TR,
     'if now - pending.at >= M.MAX_WAIT then', 'if false then'),
    ('T12', 'a same-seq retry passes the pending slot', TR,
     'elseif pending.op ~= op or pending.seq ~= seq then', 'elseif true then'),
    ('T13', 'T3: abandon frees the slot', TR,
     "    if pending and pending.op == op and pending.seq == seq then\n        audit('abandon'",
     "    if false then\n        audit('abandon'"),
    # ---- T4: fair turns, the longest-waiting module sends next ----
    ('T14', 'T4: a refused new request joins the line', TR,
     '    local turn = queue(op, seq, now);', '    local turn = nil;'),
    ('T15', 'T4: a retry of the pending request never waits its turn', TR,
     '    if pending ~= nil and pending.op == op and pending.seq == seq and now - pending.at < M.MAX_WAIT then\n'
     '        return nil;\n    end\n', ''),
    ('T16', 'T4: a module that stopped asking drops out of line', TR,
     'return turn.since ~= false and now - turn.at < M.STALE_WAIT;', 'return turn.since ~= false;'),
    ('T17', 'T4: a module back from a stale wait starts at the back', TR,
     '    if not live(turn, now) then turn.since, turn.said = now, false; end',
     '    if turn.since == false then turn.since, turn.said = now, false; end'),
    ('T18', 'T4: a granted turn leaves the line', TR,
     '        turn.since = false;\n    end\n    last = now;', '    end\n    last = now;'),
    ('T19', 'T4: the longest waiter goes first', TR,
     't.since < since and (front == nil or t.since < front.since)',
     't.since > since and (front == nil or t.since > front.since)'),
    ('T20', 'T4: equal waits never block each other', TR,
     't.since < since and', 't.since <= since and'),
    ('T21', 'T4: idle() honours the line', TR,
     '    if aheadOf(turn, since, now) ~= nil then return false; end\n', ''),
    ('T22', 'T4: one yield wire-log line per wait', TR,
     '                turn.said = true;\n', ''),
    ('T23', 'STALE_WAIT outlasts a hitch past a 0.35 s retry', TR,
     'STALE_WAIT = 1.0', 'STALE_WAIT = 0.5'),
    ('T24', 'STALE_WAIT is short: a module that stopped asking soon holds nobody', TR,
     'STALE_WAIT = 1.0', 'STALE_WAIT = 100'),
    ('T25', 'T4: a same-seq resend after MAX_WAIT is a new request', TR,
     ' and now - pending.at < M.MAX_WAIT then\n        return nil;', ' then\n        return nil;'),
    ('T26', 'T4: the EXP band check (0x4C) takes its own turns', TR,
     "    if op == 0x4C then return 'EXP band'; end\n", ''),
    ('T27', 'T4: HELM and digging take separate turns', TR,
     "if op == 0x81 then return 'digging'; end", "if op == 0x81 then return 'HELM'; end"),
    ('T28', 'T4: every vault op is one module', TR,
     "if op >= 0x40 and op <= 0x7F then return 'vault'; end", 'if op >= 0x40 and op <= 0x7F then return op; end'),
    ('T29', 'T4: ascension is one module', TR,
     "if op >= 0xA0 and op <= 0xAF then return 'ascension'; end", "if op == 0xA0 then return 'ascension'; end"),
    ('T30', 'T4: combat telemetry is one module', TR,
     "    if op >= 0xC0 and op <= 0xCF then return 'telemetry'; end\n", ''),
    ('T31', 'T4: an op outside every partition is a module of its own', TR,
     '    return op;\nend', "    return 'other';\nend"),
    # ---- the layout engine ----
    ('R01', 'nothing during a zone line', RC,
     "    if type(vc.zoning) == 'function' and vc.zoning() then return 'idle'; end", ''),
    ('R02', 'one run at a time (acks outstanding)', RC,
     "    if st.inFlight > 0 then return 'idle'; end", ''),
    ('R03', 'never while edits are queued', RC,
     "    if type(vc.layoutBusy) == 'function' and vc.layoutBusy() then return 'idle'; end", ''),
    ('R04', 'never while the vault is syncing / dormant', RC,
     "    if vs == 'dormant' or vs == 'syncing' or vs == 'unattuned' then return 'idle'; end", ''),
    ('R05', 'never while browsing another job', RC,
     "    if type(D.browsing) == 'function' and D.browsing() == true then return 'idle'; end", ''),
    ('R06', 'only against THIS job\'s layout', RC,
     'if not vc.layoutCache.fresh or vc.layoutCache.job ~= job then', 'if not vc.layoutCache.fresh then'),
    ('R07', 'only against a fresh layout', RC,
     'if not vc.layoutCache.fresh or vc.layoutCache.job ~= job then', 'if vc.layoutCache.job ~= job then'),
    ('R08', 'cleanup only in town', RC,
     "and type(D.inTown) == 'function' and D.inTown() == true and not cityHeld() then", 'then'),
    ('R09', 'cleanup only from a complete derivation', RC,
     "if instances and d.cleanupSafe and type(D.worn) == 'function'", "if instances and type(D.worn) == 'function'"),
    ('R10', 'cleanup never releases a pinned entry', RC,
     'if worn and not e.pinned and e.kind ~= 2', 'if worn and e.kind ~= 2'),
    ('R11', 'cleanup never releases a review row', RC,
     'if worn and not e.pinned and e.kind ~= 2', 'if worn and not e.pinned'),
    ('R12', 'cleanup never releases an outside copy', RC,
     'and (e.state == 0 or e.state == 1)', 'and true'),
    ('R13', 'cleanup never releases what the sets name', RC,
     'and not d.referencedIds[e.itemId] and not worn[e.itemId]', 'and not worn[e.itemId]'),
    ('R14', 'cleanup never releases a worn copy', RC,
     "and not worn['i:' .. tostring(e.instanceId)] then", 'then'),
    ('R15', 'a bound copy is never added twice', RC,
     '            if not bound[row.instanceId] then\n', '            if true then\n'),
    ('R16', 'plain copies only, as candidates', RC,
     'if row.identity == vc.ZERO24 or row.itemId == 27556 then', 'if true then'),
    ('R17', 'a plain-pinned entry never draws an augmented copy', RC,
     'if short <= 0 or rows == nil or it.plainOnly then return {}, false; end',
     'if short <= 0 or rows == nil then return {}, false; end'),
    ('R18', 'different rolls stay the player\'s pick', RC,
     'if #rows > short and rows[i].identity ~= rows[1].identity then return {}, true; end', ''),
    ('R19', 'review rows block automatic adds', RC,
     'if wantable > (c or 0) and not review[it.itemId] then', 'if wantable > (c or 0) then'),
    ('R20', 'a tombstone stops the add', RC,
     '                if not excluded then\n', '                if true then\n'),
    ('R21', 'an add that cannot fit waits', RC,
     'if capacity > 0 and units + need > capacity then', 'if false then'),
    ('R22', 'MAX_PUSH bounds a run', RC,
     'elseif #adds < R.MAX_PUSH then\n                        units = units + need;',
     'elseif true then\n                        units = units + need;'),
    ('R23', 'no adds from a stale mirror', RC,
     "if vc.mirror.fresh ~= false and not (D.settings ~= nil and D.settings().additions == 'off') then",
     "if not (D.settings ~= nil and D.settings().additions == 'off') then"),
    ('R24', 'Additions: Off adds nothing', RC,
     "if vc.mirror.fresh ~= false and not (D.settings ~= nil and D.settings().additions == 'off') then",
     'if vc.mirror.fresh ~= false then'),
    ('R25', 'the field holds the adds', RC,
     "    if cityHeld() then\n        st.pendingCity = true;\n        return 'waiting-city';\n    end\n", ''),
    ('R26', 'the same adds are not re-sent before RETRY', RC,
     "if pushKey == st.lastPushKey and now < (st.retryAt or 0) then return 'clean'; end", ''),
    ('R27', 'NOT_IN_CITY drops the queued siblings', RC,
     'st.inFlight = st.inFlight - vc.cancelLayoutSets();', 'st.inFlight = st.inFlight;'),
    ('R28', 'auto-eviction acts only in town', RC,
     "if mode == 'auto' and over > 0 and town and st.evictStamp ~= vc.layoutCache.stamp then",
     "if mode == 'auto' and over > 0 and st.evictStamp ~= vc.layoutCache.stamp then"),
    ('R29', 'auto-eviction once per layout stamp', RC,
     "if mode == 'auto' and over > 0 and town and st.evictStamp ~= vc.layoutCache.stamp then",
     "if mode == 'auto' and over > 0 and town then"),
    ('R30', 'auto-eviction never touches a pinned entry', RC,
     'for _, c in ipairs(ranked.unpinned) do', 'for _, c in ipairs(ranked.pinned) do'),
    ('R31', 'an auto-evicted wanted entry is tombstoned', RC,
     'if #tomb > 0 then pcall(D.usage.exclude, tomb); end', ''),
    ('R32', 'the vault law: never want more than the vault + layout hold', RC,
     'local wantable = math.min(want, plainHave + #augPick);', 'local wantable = want;'),
    ('R33', 'legacy repairs only off instance mode', RC,
     'if not instances and count < e.count then', 'if count < e.count then'),
    # ---- derivation ----
    ('D01', 'augment-pinned records are skipped', DV,
     '        elseif aug then\n            skippedAug = skippedAug + 1;', '        elseif false then\n            skippedAug = skippedAug + 1;',
     FULL),
    ('D02', 'a plain pin marks the item plainOnly', DV,
     '            if plain then e.plainOnly = true; end\n', '', FULL),
    ('D03', 'a plain pin is OR-ed into a shared key', DV,
     '    elseif r.plain then f.plain = true; end', '    end', FULL),
    ('D04', 'virtual dlac: entries contribute nothing', DV,
     "if v == '' or isVirtual(v) then return nil; end", "if v == '' then return nil; end", FULL),
    ('D05', 'an unresolved name makes cleanup unsafe', DV,
     'and #unresolved == 0', 'and true', FULL),
    ('D06', 'across sets the MAX wins, not the sum', DV,
     'if (global[name] or 0) < n then global[name] = n; end', 'global[name] = (global[name] or 0) + n;', FULL),
    # ---- the Shared Vault (Group Ironman, ops 0x60-0x6F; tests/gearvault_shared.lua) ----
    ('S01', 'SV_PUT is a write (its retries stay inside the replay window)', VC,
     '[M.op.SV_PUT] = true, [M.op.SV_TAKE] = true,', '[M.op.SV_PUT] = false, [M.op.SV_TAKE] = true,'),
    ('S02', 'SV_TAKE is a write', VC,
     '[M.op.SV_PUT] = true, [M.op.SV_TAKE] = true,', '[M.op.SV_PUT] = true, [M.op.SV_TAKE] = false,'),
    ('S03', 'the HELLO request subscribes to SV_CHANGED (word @2, bit 1)', VC,
     'M.CLIENT_CAPS = M.CLIENT_CAP_PUSH + M.CLIENT_CAP_SHELF_PUSH;', 'M.CLIENT_CAPS = M.CLIENT_CAP_PUSH;'),
    ('S04', 'the tab needs the SHELF capability', VC,
     'and M.limits.shelf == true and (st.svGroupId or 0) ~= 0;', 'and (st.svGroupId or 0) ~= 0;'),
    ('S05', 'the tab needs a group', VC,
     'and M.limits.shelf == true and (st.svGroupId or 0) ~= 0;', 'and M.limits.shelf == true;'),
    ('S06', 'SHELF without its tail offers no shelf', VC,
     'shelf      = has(caps, M.cap.SHELF) and shelfTail,', 'shelf      = has(caps, M.cap.SHELF),'),
    ('S07', 'InGroup 0 hides the tab', VC,
     'setShelfGroup(c.inGroup and c.groupId or 0, c.revision, c.count, now);',
     'setShelfGroup(c.groupId, c.revision, c.count, now);'),
    ('S08', 'a Rev equal to the last read\'s reads nothing', VC,
     'if shelfOpen(now) and M.shelf.readRev ~= rev then st.svListWant = true; end',
     'if shelfOpen(now) then st.svListWant = true; end'),
    ('S09', 'a push to a closed tab reads nothing (S9)', VC,
     'if shelfOpen(now) and M.shelf.readRev ~= rev then st.svListWant = true; end',
     'if M.shelf.readRev ~= rev then st.svListWant = true; end'),
    ('S10', 'another Rev reads the shelf while the tab is open', VC,
     'if shelfOpen(now) and M.shelf.readRev ~= rev then st.svListWant = true; end',
     'if false then st.svListWant = true; end'),
    ('S11', 'opening the tab reads the members and the shelf', VC,
     'if opened and M.shelfAvailable() then', 'if false then'),
    ('S12', 'an open tab is read once, not every frame (no clock)', VC,
     'local opened = not shelfOpen(now);', 'local opened = true;'),
    ('S13', 'a tab closed before its reads left drops them', VC,
     'if (st.svMembersWant or st.svListWant) and not (shelfOpen(now) and M.shelfAvailable()) then', 'if false then'),
    ('S14', 'one shelf write at a time (one piece per click)', VC,
     'function M.shelfBusy() return #(st.shelfWriteQ or {}) > 0; end', 'function M.shelfBusy() return false; end'),
    ('S15', 'the confirm flag is bit 0 of the flags byte', VC,
     'e.confirm and 1 or 0, 0);', '0, 0);'),
    ('S16', 'a shelf answer never reaches the vault\'s status handling', VC,
     'if p.op >= M.op.SV_LIST and p.op <= M.op.SV_CHANGED then return onShelfReply(p, f, now); end', ''),
    ('S17', 'a shelf read timeout never backs the vault off', VC,
     'elseif p.op == M.op.SV_LIST or p.op == M.op.SV_MEMBERS then', 'elseif false then'),
    ('S18', 'BAD_OP on a shelf op hides the shelf', VC,
     'st.svOff = true;   -- this server cannot serve the shelf', '--   -- this server cannot serve the shelf'),
    ('S19', 'a gate refusal (TOO_FAR) moved nothing: the vault stands', VC,
     'if f.status ~= M.status.TOO_FAR and f.status ~= M.status.NOT_ATTUNED and f.status ~= M.status.MALFORMED then',
     'if true then'),
    ('S20', 'any other refused write may have run: re-read both', VC,
     'if f.status ~= M.status.TOO_FAR and f.status ~= M.status.NOT_ATTUNED and f.status ~= M.status.MALFORMED then',
     'if false then'),
    ('S21', 'a lost shelf write is outcome unknown (its own branch)', VC,
     'if p.op == M.op.SV_PUT or p.op == M.op.SV_TAKE then shelfWriteLost(p, why); return; end', ''),
    ('S22', 'a lost shelf write re-reads the vault', VC,
     '    M.markStale(0, why);\n    M.invalidateLayout();   -- a confirmed share leaves',
     '    M.invalidateLayout();   -- a confirmed share leaves'),
    ('S23', 'a share takes its row out of the vault mirror at once', VC,
     'if req ~= nil and (req.vaultRowId or 0) > 0 then dropMirrorRow(req.vaultRowId); end', ''),
    ('S24', 'a share re-reads the vault', VC,
     "M.markStale(M.SETTLE_EDIT, 'shared a piece');", ''),
    ('S25', 'a share that left layouts or a wardrobe re-reads the layout', VC,
     'if #ack.jobs > 0 or ack.wardrobe then M.invalidateLayout(); end', ''),
    ('S26', 'a take re-reads the vault', VC,
     "M.markStale(M.SETTLE_EDIT, 'took a piece');", ''),
    ('S27', 'a take of a laid-out piece re-reads the layout', VC,
     'if req ~= nil and layoutNames(req.itemId) then M.invalidateLayout(); end', ''),
    ('S28', 'a take at Rev + 1 is our own change: no re-read', VC,
     'and held ~= nil and ack.revision == held + 1 then', 'and false then'),
    ('S29', 'a take while others moved re-reads the shelf', VC,
     'and held ~= nil and ack.revision == held + 1 then', 'and held ~= nil then'),
    ('S30', 'shelf pages at two Revs never mix', VC,
     'if st.svAccRev ~= nil and st.svAccRev ~= chunk.revision then', 'if false then'),
    ('S31', 'a re-delivered shelf row is skipped by RowId', VC,
     'if e.rowId > accLast then st.svAcc[#st.svAcc + 1] = e; accLast = e.rowId; end',
     'st.svAcc[#st.svAcc + 1] = e; accLast = math.max(accLast, e.rowId);'),
    ('S32', 'a newer Rev announced during the read reads once more', VC,
     'if st.svNoteGen ~= p.svGen and st.svKnownRev ~= nil and st.svKnownRev > M.shelf.readRev',
     'if false and st.svKnownRev ~= nil and st.svKnownRev > M.shelf.readRev'),
    ('S51', 'an announcement during a read waits for the read\'s answer', VC,
     "    if st.pending ~= nil and st.pending.kind == 'shelf-list' then return; end\n", ''),
    ('S52', 'only a NEWER announced Rev reads again after a read', VC,
     'st.svKnownRev > M.shelf.readRev', 'st.svKnownRev ~= M.shelf.readRev'),
    ('S33', 'SV_CHANGED is a push, never a reply', VC,
     'if f.op == M.op.SV_CHANGED and (f.seq or 0) == 0 then return onShelfPush(f, now); end', ''),
    ('S34', 'the HELLO tail tells the group and the shelf\'s Rev', VC,
     "noteShelfHello(h, now);           -- the group", "--noteShelfHello(h, now);         -- the group"),
    ('S35', 'MORE asks again after the last RowId', VC,
     "beginOp('shelf-list', M.op.SV_LIST, wu32(accLast) .. streamTail(), now, accLast);",
     "beginOp('shelf-list', M.op.SV_LIST, wu32(0) .. streamTail(), now, accLast);"),
    ('S36', 'a shelf read cut by a zone line runs again', VC,
     "if p.kind == 'shelf-list' or p.kind == 'shelf-members' then shelfReadCut(p); end", ''),
    ('S37', 'a sharer the member list cannot name asks for it again', VC,
     'if st.svNamesFor ~= M.shelf.readRev and shelfOpen(now) then', 'if false then'),
    ('S38', 'leaving the group cancels a share that has not left', VC,
     "if was ~= 0 then shelfCancelQueued('not_in_group'); shelfForget(); end", 'if was ~= 0 then shelfForget(); end'),
    ('S39', 'a share already on the wire keeps its answer', VC,
     'if p.sentAt ~= nil then keepFirst = true; else st.pending = nil; end', 'st.pending = nil;'),
    ('S40', 'the vault going un-attuned drains a queued share', VC,
     "    shelfDrain('not_attuned');\n", ''),
    ('S41', 'NOT_IN_GROUP on a share hides the tab', VC,
     "        elseif ack.code == M.giCode.NOT_IN_GROUP then\n            setShelfGroup(0, nil, nil, now);\n        end\n"
     "        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, ack, nil); end\n"
     "        return true;\n    end\n\n    if p.op == M.op.SV_TAKE then",
     "        end\n"
     "        if req ~= nil and type(req.onDone) == 'function' then pcall(req.onDone, ack, nil); end\n"
     "        return true;\n    end\n\n    if p.op == M.op.SV_TAKE then"),
    ('S42', 'NEEDS_CONFIRM asks instead of reporting', SV,
     'elseif ack.code == vc.giCode.NEEDS_CONFIRM and not confirm then', 'elseif false then'),
    ('S43', 'only a yes sends the share again', SV,
     'if c == nil or not agree then return false; end', 'if c == nil then return false; end'),
    ('S44', 'the yes carries the confirm flag', SV,
     'return put(c.target, true);', 'return put(c.target, false);'),
    ('S45', 'an unanswered question lapses', SV,
     'if c ~= nil and (M._clock() - c.at > M.CONFIRM_TTL or not vc.shelfAvailable()) then',
     'if c ~= nil and (not vc.shelfAvailable()) then'),
    ('S46', 'leaving the group drops the question', SV,
     'if c ~= nil and (M._clock() - c.at > M.CONFIRM_TTL or not vc.shelfAvailable()) then',
     'if c ~= nil and (M._clock() - c.at > M.CONFIRM_TTL) then'),
    ('S47', 'a stack never goes to the shelf (pieces only)', SV,
     'if (row.qty or 1) > 1 then', 'if false then'),
    ('S48', 'the tab hides when the shelf is not offered', UI,
     "if shelfOn and imgui.BeginTabItem(string.format('Shared Vault (%d)###gvtsv', svm.count())) then",
     "if imgui.BeginTabItem(string.format('Shared Vault (%d)###gvtsv', svm.count())) then"),
    ('S49', 'the Vault tab offers Share only in a group', UI,
     'if shelfOn and _vaultMenu ~= nil and (_vaultMenu.qty or 1) <= 1 then',
     'if _vaultMenu ~= nil and (_vaultMenu.qty or 1) <= 1 then'),
    ('S50', 'clicking away from the question is a no', UI,
     '        svm.confirm(false);   -- clicked away: that is a no\n', ''),
    # ---- the Shared Vault's exact behaviour: codecs, words, the tab and the glue (each turns at
    # ---- least one tests/gearvault_shared.lua check red that no guard above reaches) ----
    ('X01', 'SHELF never read', VC,
     'shelf      = has(caps, M.cap.SHELF) and shelfTail,',
     'shelf      = false,'),
    ('X02', 'GroupId at the wrong offset', VC,
     'groupId    = shelfTail and u32(payload, 20) or 0,',
     'groupId    = shelfTail and u32(payload, 24) or 0,'),
    ('X03', 'the Rev at the wrong offset', VC,
     'shelfRev   = shelfTail and u32(payload, 24) or nil,',
     'shelfRev   = shelfTail and u32(payload, 28) or nil,'),
    ('X04', 'the count at the wrong offset', VC,
     'shelfCount = shelfTail and u32(payload, 28) or nil,',
     'shelfCount = shelfTail and u32(payload, 24) or nil,'),
    ('X05', 'a vault field disturbed', VC,
     'maxLookup = u8(payload, 18), maxLostList = u8(payload, 19),',
     'maxLookup = u8(payload, 19), maxLostList = u8(payload, 19),'),
    ('X06', 'a short SHELF HELLO refused whole', VC,
     '    local shelfTail = #payload >= 32;',
     '    local shelfTail = #payload >= 32; if has(caps, M.cap.SHELF) and not shelfTail then return nil; end'),
    ('X07', 'a tail is a shelf without the SHELF bit', VC,
     'shelf      = has(caps, M.cap.SHELF) and shelfTail,',
     'shelf      = shelfTail,'),
    ('X08', 'the tail made optional, the group read from the vault fields', VC,
     '    local shelfTail = #payload >= 32;\n    return {\n        shelf      = has(caps, M.cap.SHELF) and shelfTail,\n        groupId    = shelfTail and u32(payload, 20) or 0,',
     '    local shelfTail = #payload >= 20;\n    return {\n        shelf      = has(caps, M.cap.SHELF) and shelfTail,\n        groupId    = shelfTail and u32(payload, 12) or 0,'),
    ('X09', 'the frame Rev at the wrong offset', VC,
     '    if n > M.SHELF_LIST_MAX or #payload < 8 + n * 40 then return nil; end\n    local out = { entries = {}, revision = u32(payload, 4) };',
     '    if n > M.SHELF_LIST_MAX or #payload < 8 + n * 40 then return nil; end\n    local out = { entries = {}, revision = u32(payload, 0) };'),
    ('X10', 'SharedBy at the wrong offset', VC,
     'instanceId = u32(payload, o + 8), sharedBy = u32(payload, o + 12), identity = payload:sub(o + 17, o + 40) };',
     'instanceId = u32(payload, o + 8), sharedBy = u32(payload, o + 8), identity = payload:sub(o + 17, o + 40) };'),
    ('X11', 'the identity blob one byte early', VC,
     'instanceId = u32(payload, o + 8), sharedBy = u32(payload, o + 12), identity = payload:sub(o + 17, o + 40) };',
     'instanceId = u32(payload, o + 8), sharedBy = u32(payload, o + 12), identity = payload:sub(o + 16, o + 39) };'),
    ('X12', 'a truncated SV_LIST frame read', VC,
     'if n > M.SHELF_LIST_MAX or #payload < 8 + n * 40 then return nil; end',
     'if n > M.SHELF_LIST_MAX then return nil; end'),
    ('X13', '13 rows a frame allowed', VC,
     'if n > M.SHELF_LIST_MAX or #payload < 8 + n * 40 then return nil; end',
     'if n > 13 or #payload < 8 + n * 40 then return nil; end'),
    ('X14', 'an empty frame refused', VC,
     "function M.parseShelfList(payload)\n    if type(payload) ~= 'string' or #payload < 8 then return nil; end",
     "function M.parseShelfList(payload)\n    if type(payload) ~= 'string' or #payload < 9 then return nil; end"),
    ('X15', 'VaultRowId as a u16', VC,
     '    return wu32(e.vaultRowId or 0)\n',
     '    return wu16(e.vaultRowId or 0) .. wu16(0)\n'),
    ('X16', 'Container and Slot swapped', VC,
     'string.char((e.container or 0) % 256, (e.slot or 0) % 256, e.confirm and 1 or 0, 0);',
     'string.char((e.slot or 0) % 256, (e.container or 0) % 256, e.confirm and 1 or 0, 0);'),
    ('X17', 'JobCount at the wrong offset', VC,
     '    local n = u8(payload, 2);',
     '    local n = u8(payload, 3);'),
    ('X18', 'the put Rev at the wrong offset', VC,
     'shelfRowId = u32(payload, 4), revision = u32(payload, 8), jobs = {} };',
     'shelfRowId = u32(payload, 4), revision = u32(payload, 4), jobs = {} };'),
    ('X19', 'a short job list read', VC,
     '    if #payload < 12 + n then return nil; end\n',
     ''),
    ('X20', 'the put answer length checks both wrong', VC,
     "function M.parseShelfPutAck(payload)\n    if type(payload) ~= 'string' or #payload < 12 then return nil; end\n    local n = u8(payload, 2);\n    if #payload < 12 + n then return nil; end",
     "function M.parseShelfPutAck(payload)\n    if type(payload) ~= 'string' then return nil; end\n    local n = u8(payload, 2);\n    if #payload < n then return nil; end"),
    ('X21', 'ShelfRowId as a u16', VC,
     'function M.shelfTakePayload(shelfRowId) return wu32(shelfRowId or 0); end',
     'function M.shelfTakePayload(shelfRowId) return wu16(shelfRowId or 0) .. wu16(0); end'),
    ('X22', 'the take VaultRowId at the wrong offset', VC,
     'return { code = u16(payload, 0), vaultRowId = u32(payload, 4), revision = u32(payload, 8) };',
     'return { code = u16(payload, 0), vaultRowId = u32(payload, 8), revision = u32(payload, 8) };'),
    ('X23', 'a short take answer read', VC,
     "function M.parseShelfTakeAck(payload)\n    if type(payload) ~= 'string' or #payload < 12 then return nil; end",
     "function M.parseShelfTakeAck(payload)\n    if type(payload) ~= 'string' then return nil; end"),
    ('X24', 'the leader at the wrong offset', VC,
     'local out = { groupId = u32(payload, 4), leader = u32(payload, 8), members = {} };',
     'local out = { groupId = u32(payload, 4), leader = u32(payload, 4), members = {} };'),
    ('X25', 'zero padding kept in names', VC,
     '        if z ~= nil then name = name:sub(1, z - 1); end\n',
     ''),
    ('X26', 'everyone active', VC,
     'active = has(flags, 1), leader = has(flags, 2), online = has(flags, 4) };',
     'active = true, leader = has(flags, 2), online = has(flags, 4) };'),
    ('X27', 'nobody online', VC,
     'active = has(flags, 1), leader = has(flags, 2), online = has(flags, 4) };',
     'active = has(flags, 1), leader = has(flags, 2), online = false };'),
    ('X28', 'a 16-byte name cut to 15', VC,
     '        local name = payload:sub(o + 9, o + 24);',
     '        local name = payload:sub(o + 9, o + 23);'),
    ('X29', 'a truncated member list read', VC,
     'if n > M.SHELF_MEMBERS_MAX or #payload < 12 + n * 24 then return nil; end',
     'if n > M.SHELF_MEMBERS_MAX then return nil; end'),
    ('X30', 'InGroup at the wrong offset', VC,
     'inGroup = u8(payload, 8) ~= 0, groupId = u32(payload, 12) };',
     'inGroup = u8(payload, 9) ~= 0, groupId = u32(payload, 12) };'),
    ('X31', 'a short push read', VC,
     "if type(payload) ~= 'string' or #payload < 16 then return nil; end",
     "if type(payload) ~= 'string' or #payload < 4 then return nil; end"),
    ('X32', 'the vault push bit dropped', VC,
     'M.CLIENT_CAPS = M.CLIENT_CAP_PUSH + M.CLIENT_CAP_SHELF_PUSH;',
     'M.CLIENT_CAPS = M.CLIENT_CAP_SHELF_PUSH;'),
    ('X33', 'SV_LIST counted as a write', VC,
     '[M.op.SV_PUT] = true, [M.op.SV_TAKE] = true,',
     '[M.op.SV_PUT] = true, [M.op.SV_TAKE] = true, [M.op.SV_LIST] = true,'),
    ('X34', 'the shelf ops their own module', TR,
     "if op >= 0x40 and op <= 0x7F then return 'vault'; end",
     "if op >= 0x40 and op <= 0x5F then return 'vault'; end"),
    ('X35', 'every seq the same', VC,
     'st.seq = (st.seq or 0) % 255 + 1;',
     'st.seq = 7;'),
    ('X36', 'the tab always open', VC,
     'return st.svViewAt ~= nil and (now or M._clock()) - st.svViewAt <= M.SHELF_VIEW_GAP;',
     'return true;'),
    ('X37', 'every read re-reads', VC,
     '        if st.svNoteGen ~= p.svGen and st.svKnownRev ~= nil and st.svKnownRev > M.shelf.readRev\n            and shelfOpen(now) then',
     '        if shelfOpen(now) then'),
    ('X38', 'our own take never drops its row', VC,
     'if req ~= nil and dropShelfRow(req.shelfRowId, now) and held ~= nil',
     'if req ~= nil and false and held ~= nil'),
    ('X39', 'a failed read asks again', VC,
     '    if p.op == M.op.SV_LIST then st.svAcc, st.svAccRev = nil, nil; end\n    st.svFailed = true;\nend',
     '    if p.op == M.op.SV_LIST then st.svAcc, st.svAccRev = nil, nil; end\n    st.svFailed = true; st.svListWant = true; st.svMembersWant = true;\nend'),
    ('X40', 'every share re-reads the layout', VC,
     'if #ack.jobs > 0 or ack.wardrobe then M.invalidateLayout(); end',
     'M.invalidateLayout();'),
    ('X41', 'a share re-reads the vault at once', VC,
     "M.markStale(M.SETTLE_EDIT, 'shared a piece');",
     "M.markStale(0, 'shared a piece');"),
    ('X42', 'a gone vault row not re-read', VC,
     "            M.markStale(0, 'shared vault: that vault row was gone');\n            st.probeOnly = false;\n",
     ''),
    ('X43', 'any non-question answer counted as a move', VC,
     '        if ack == nil then shelfWriteUnreadable(req, now); return true; end\n        if ack.code == M.giCode.OK then\n            -- the server deleted that vault row',
     '        if ack == nil then shelfWriteUnreadable(req, now); return true; end\n        if ack.code ~= M.giCode.NEEDS_CONFIRM then\n            -- the server deleted that vault row'),
    ('X44', 'an unreadable take answer trusted', VC,
     '        local ack = M.parseShelfTakeAck(f.payload);\n        if ack == nil then shelfWriteUnreadable(req, now); return true; end',
     "        local ack = M.parseShelfTakeAck(f.payload);\n        if ack == nil then if req and req.onDone then req.onDone(nil, 'malformed'); end return true; end"),
    ('X45', 'a push frees the gate', VC,
     "    if type(M._notePush) == 'function' then pcall(M._notePush, f.op, 'shared vault push'); end",
     "    if type(M._notePush) == 'function' then pcall(M._notePush, f.op, 'shared vault push'); end\n    if M._received and st.pending then M._received(st.pending.op, st.pending.seq); end"),
    ('X46', 'a push not blocked from the game', VC,
     '    setShelfGroup(c.inGroup and c.groupId or 0, c.revision, c.count, now);\n    return true;',
     '    setShelfGroup(c.inGroup and c.groupId or 0, c.revision, c.count, now);\n    return false;'),
    ('X47', 'an unreadable push not blocked', VC,
     "        noteWhy('ate an unreadable Shared Vault push', now);\n        return true;",
     "        noteWhy('ate an unreadable Shared Vault push', now);\n        return false;"),
    ('X48', 'the shelf counted as yours', VC,
     '        M.shelf.stamp = now;\n        st.svAcc, st.svAccRev, st.svFailed = nil, nil, nil;',
     "        M.shelf.stamp = now;\n        st.svAcc, st.svAccRev, st.svFailed = nil, nil, nil;\n        for _, r in ipairs(M.shelf.rows) do M.mirror.counts[r.itemId] = 1; end\n        if type(M._onFresh) == 'function' then pcall(M._onFresh); end"),
    ('X49', 'the caller of a share on the wire hears the cancel too', VC,
     'for i = (keepFirst and 2 or 1), #q do',
     'for i = 1, #q do'),
    ('X50', 'shelf writes wait for the tab', VC,
     '    if st.shelfWriteQ ~= nil and st.shelfWriteQ[1] ~= nil then\n        local req = st.shelfWriteQ[1];',
     '    if st.shelfWriteQ ~= nil and st.shelfWriteQ[1] ~= nil and shelfOpen(now) then\n        local req = st.shelfWriteQ[1];'),
    ('X51', 'a single piece refused as a stack', SV,
     'if (row.qty or 1) > 1 then',
     'if (row.qty or 1) >= 1 then'),
    ('X52', 'the first share sends the confirm flag', SV,
     'return put({ vaultRowId = row.rowId, itemId = row.itemId, name = nameOf(row) }, false);',
     'return put({ vaultRowId = row.rowId, itemId = row.itemId, name = nameOf(row) }, true);'),
    ('X53', 'NEEDS_CONFIRM answered by itself', SV,
     '            M._confirm = { target = t, jobs = ack.jobs or {}, wardrobe = ack.wardrobe == true,\n                           name = t.name, at = M._clock() };',
     '            put(t, true);'),
    ('X54', 'Cancel keeps the question', SV,
     '    local c = M.pendingConfirm();\n    M._confirm = nil;\n    if c == nil or not agree then return false; end',
     '    local c = M.pendingConfirm();\n    if c == nil or not agree then return false; end\n    M._confirm = nil;'),
    ('X55', 'one layout read as many', SV,
     "(n == 1) and '' or 's'",
     "'s'"),
    ('X56', 'the yes sends another row', SV,
     'return put(c.target, true);',
     'return put({ vaultRowId = (c.target.vaultRowId or 0) + 1, container = c.target.container, slot = c.target.slot, itemId = c.target.itemId, name = c.target.name }, true);'),
    ('X57', 'the success words', SV,
     "note(string.format('shared %s with your group', t.name));",
     "note(string.format('shared %s', t.name));"),
    ('X58', 'wardrobe shares refused', SV,
     "if type(piece) ~= 'table' or piece.container == nil or piece.slot == nil then return false; end",
     'if true then return false; end'),
    ('X59', 'the wardrobe question words', SV,
     "lines[#lines + 1] = 'It is in your Mog Wardrobe.';",
     "lines[#lines + 1] = 'It is in a wardrobe.';"),
    ('X60', 'the SHELF_CAP words', SV,
     "'the Shared Vault already holds as many of that piece as it can'",
     "'the shelf is full'"),
    ('X61', 'ITEM_BUSY has no words', SV,
     "    [vc.giCode.ITEM_BUSY]      = 'you cannot do that right now',\n",
     ''),
    ('X62', 'an unknown code says less', SV,
     "string.format('refused (code %s)', tostring(code))",
     "string.format('refused %s', tostring(code))"),
    ('X63', 'TOO_FAR says less', SV,
     "too_far      = 'stand at a Gear Vault to use the Shared Vault',",
     "too_far      = 'too far',"),
    ('X64', 'RARE_HELD words', SV,
     "'you already have one of that Rare piece'",
     "'Rare'"),
    ('X65', 'a refused take is not a complaint', SV,
     "note(name .. ': ' .. M.refusalWords(ack.code), true);",
     "note(name .. ': ' .. M.refusalWords(ack.code), false);"),
    ('X66', "a take's frame refusal read as a code", SV,
     "note(name .. ': ' .. M.errWords(err), true);",
     "note(name .. ': ' .. M.refusalWords(err), true);"),
    ('X67', 'jobs joined without and', SV,
     "' and ' .. names[#names]",
     "', ' .. names[#names]"),
    ('X68', 'the window errors in no group', UI,
     "local shelfOn = svm ~= nil and type(vc.shelfAvailable) == 'function' and vc.shelfAvailable();",
     'local shelfOn = svm.missing();'),
    ('X69', 'the shared tab item never ends', UI,
     '            renderSharedTab();\n            imgui.EndTabItem();',
     '            renderSharedTab();'),
    ('X70', 'the tab renamed', UI,
     "'Shared Vault (%d)###gvtsv'",
     "'Shared (%d)###gvtsv'"),
    ('X71', 'drawing the tab does not open it', UI,
     '        vc.noteShelfView();\n',
     ''),
    ('X72', 'no sharer shown', UI,
     '                        if e.sharer ~= nil then',
     '                        if false then'),
    ('X73', 'no member line', UI,
     "        if members ~= '' then\n            imgui.TextColored(cDIM, esc('Your group: ' .. members));",
     "        if false then\n            imgui.TextColored(cDIM, esc('Your group: ' .. members));"),
    ('X74', 'the Take button renamed', UI,
     "imgui.SmallButton('Take##gvst' ..",
     "imgui.SmallButton('Get##gvst' .."),
    ('X75', 'no hint where to share from', UI,
     "        imgui.TextColored(cDIM, 'To share a piece from your Gear Vault, right-click it in the Vault tab.');\n",
     ''),
    ('X76', 'shelf results never reach the tab line', UI,
     '    svm._note = function(text, isErr)\n        _lastMsg = { text = text, err = (isErr == true) };',
     '    svm._note = function(text, isErr)\n        _lastMsg = nil;'),
    ('X77', 'the shelf view never rebuilt', UI,
     'if _sView ~= nil and _sStamp == sh.stamp and _sMembers == sh.membersStamp then return _sView; end',
     'if _sView ~= nil then return _sView; end'),
    ('X78', 'the menu item renamed', UI,
     "if imgui.Selectable('Share with your group') then",
     "if imgui.Selectable('Share') then"),
    ('X79', 'the question opens another popup', UI,
     "        imgui.OpenPopup('##gv-share-confirm');",
     "        imgui.OpenPopup('##gv-share-confirm-x');"),
    ('X80', 'the wardrobe list renamed', UI,
     "'Share from your Mog Wardrobes (%d)###gvsvw'",
     "'Share from your wardrobes (%d)###gvsvw'"),
    ('X81', 'the wardrobe Share button renamed', UI,
     "imgui.SmallButton('Share##gvsw' ..",
     "imgui.SmallButton('Give##gvsw' .."),
    ('X82', '/dl vault without the shelf line', IN,
     '                local line = vc.shelfStatusLine();',
     '                local line = nil;'),
    ('X83', 'a character switch keeps the question', IN,
     "                pcall(function() require(base .. 'sharedvault')._reset(); end);\n",
     ''),
]

# Mutants that survive for a stated reason (equivalent, or not a defect).
ACCEPTED = {
    'V30': 'equivalent: a cut read keeps its staleAt (only a commit clears it), so the pump restarts it in full '
           'anyway; zoneFull only re-states that',
    'R23': 'equivalent for the wire: the later `mirror.fresh == false -> clean` gate stops every send; this gate '
           'only skips the not-vaulted / choose-a-copy bookkeeping for a stale mirror',
    'R02': 'equivalent with the real client: the engine\'s in-flight count is above 0 only while its edits sit '
           'in layoutSetQ, which the layoutBusy gate (R03, killed) already sees',
    'S09': 'equivalent: the pump drops every Shared Vault read wanted while its tab is closed (S13, killed), so '
           'this early check only saves setting the flag',
}


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True)


def clean():
    return git('status', '--porcelain', '--untracked-files=no').stdout.strip() == ''


def nl_of(data):
    return b'\r\n' if b'\r\n' in data else b'\n'


def key(m):
    return hashlib.sha1(repr(m[2:5]).encode()).hexdigest()[:12]


def run_suites(suites):
    failed = []
    for s in suites:
        r = subprocess.run([LUA, *s], cwd=ROOT, capture_output=True, text=True, timeout=600)
        if r.returncode != 0:
            failed.append(Path(s[0]).stem)
    return failed


def parses(path):
    r = subprocess.run([LUA, '-e', "assert(loadfile('%s'))" % path], cwd=ROOT, capture_output=True, text=True)
    return r.returncode == 0


def main(argv):
    fresh = '--fresh' in argv
    only = [a for a in argv if not a.startswith('--')]
    if not clean():
        print('refusing to start: the tree has uncommitted changes (git status --porcelain).')
        return 2
    base = run_suites(FULL)
    if base:
        print('refusing to start: the unmutated tree already fails: ' + ', '.join(base))
        return 2
    done = {}
    if OUT.exists() and not fresh:
        for line in OUT.read_text(encoding='utf-8').splitlines():
            r = json.loads(line)
            done[(r['id'], r['key'])] = r
    elif fresh and OUT.exists():
        OUT.unlink()
    results = []
    for m in M:
        mid, guard, path, old, new = m[:5]
        suites = m[5] if len(m) > 5 else SUITES
        if only and mid not in only:
            continue
        k = key(m)
        if (mid, k) in done:
            results.append(done[(mid, k)])
            continue
        f = ROOT / path
        data = f.read_bytes()
        nl = nl_of(data)
        o, n = old.encode().replace(b'\n', nl), new.encode().replace(b'\n', nl)
        rec = {'id': mid, 'key': k, 'guard': guard, 'file': path}
        t = time.time()
        if data.count(o) != 1:
            rec.update(result='not-applied', why='pattern found %d times' % data.count(o))
        else:
            f.write_bytes(data.replace(o, n))
            try:
                if not parses(path):
                    rec.update(result='invalid', why='the mutant does not parse')
                else:
                    failed = run_suites(suites)
                    rec.update(result='killed' if failed else 'survived', by=failed)
            finally:
                git('checkout', '--', path)
            if not clean():
                print('the tree did not restore after %s -- stopping.' % mid)
                return 2
        rec['secs'] = round(time.time() - t, 2)
        with OUT.open('a', encoding='utf-8') as out:
            out.write(json.dumps(rec) + '\n')
        results.append(rec)
        print('%s %-10s %s' % (mid, rec['result'], guard), flush=True)

    print('\n| Mutant | Guard | Result | Red suites |')
    print('|---|---|---|---|')
    bad = 0
    for r in results:
        res = r['result']
        if res != 'killed':
            if r['id'] in ACCEPTED:
                res = 'survived (accepted: %s)' % ACCEPTED[r['id']]
            else:
                bad += 1
        print('| %s | %s | %s | %s |' % (r['id'], r['guard'], res, ', '.join(r.get('by', [])) or r.get('why', '')))
    killed = sum(1 for r in results if r['result'] == 'killed')
    print('\n%d mutants, %d killed, %d accepted, %d open.' % (len(results), killed,
          sum(1 for r in results if r['result'] != 'killed' and r['id'] in ACCEPTED), bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
