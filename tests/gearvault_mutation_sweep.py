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
TR = 'servers/ascensionxi/transport.lua'

SUITES = [
    ['tests/gearvault_live.lua'],
    ['tests/gearvault_instances.lua'],
    ['tests/gearvault_counts.lua'],
    ['tests/gearvault_sync.lua'],
    ['tests/gearvault_sync_probe.lua', '--budget'],
    ['tests/gearvault_augmented_draw.lua'],
    ['tests/gearvault_stage8.lua'],
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
     '    if last and now - last < M.MIN_GAP then return false; end\n    if not foreignQuiet(now) then return false; end\n    local op',
     '    if not foreignQuiet(now) then return false; end\n    local op'),
    ('T02', 'a foreign 0x1E0 holds send()', TR,
     '    if not foreignQuiet(now) then return false; end\n    local op, seq', '    local op, seq'),
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
     'elseif #adds < R.MAX_PUSH then', 'elseif true then'),
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
]

# Mutants that survive for a stated reason (equivalent, or not a defect).
ACCEPTED = {
    'V30': 'equivalent: a cut read keeps its staleAt (only a commit clears it), so the pump restarts it in full '
           'anyway; zoneFull only re-states that',
    'R23': 'equivalent for the wire: the later `mirror.fresh == false -> clean` gate stops every send; this gate '
           'only skips the not-vaulted / choose-a-copy bookkeeping for a stale mirror',
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
