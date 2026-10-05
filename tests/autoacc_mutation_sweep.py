"""Mutation sweep for AutoAcc on AscensionXI and the accuracy box
(docs/design/ascensionxi-combat-telemetry-autoacc.md, "Mutation sweep"): the
telemetry codec, the session client, the formula copy, the AutoAcc model and
its prediction check, the engine's single-send integration, the box, the Gear
Rule combo, the flatten's gates and the pack wiring. Every guard is broken
once, the suites run, and at least one must go red. The file is always
restored from the bytes it read.

    python tests/autoacc_mutation_sweep.py              every mutant
    python tests/autoacc_mutation_sweep.py A07 C12      only these
    python tests/autoacc_mutation_sweep.py --check      do the patterns still apply?

Run from the repo root on a clean tree (it refuses otherwise). Lua 5.4 as
`lua` (or set LUA=...). The fast AutoAcc suites run first and a mutant stops
at the first suite that goes red, so only a mutant that survives them pays
for run_tests.lua and smoke_ui.lua. Prints a markdown board and exits 1 when
a mutant survives, cannot be applied or breaks the file's syntax -- unless
it is listed in ACCEPTED with the reason it is not a defect.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.gettempdir()) / 'dlac-autoacc-mutation-sweep.json'
LUA = os.environ.get('LUA', 'lua')

T = 'servers/ascensionxi/modules/telemetry/'
WI, CL, FO, AA, MO, IN = T + 'wire.lua', T + 'client.lua', T + 'formula.lua', T + 'autoacc.lua', T + 'monitor.lua', T + 'init.lua'
DS = 'dispatch.lua'
GU = 'ui/gearui.lua'
UT = 'utils.lua'
MD = 'servers/ascensionxi/modules.lua'
FT = 'servers/ascensionxi/features.lua'

# id, guard, file, old, new
M = [
    # ---- the codec ----
    ('W01', 'the live halves decode signed', WI,
     "s[name .. 'Live'] = M.i16(p, 86 + i * 4);", "s[name .. 'Live'] = M.u16(p, 86 + i * 4);"),
    ('W02', 'the outfit hash covers the slot index', WI, 'h = fnvStep(h, s % 256);', 'h = fnvStep(h, 0);'),
    ('W03', 'R stays in the comparison key', WI, '{ 56, 62 }, { 64, 90 },', '{ 56, 62 }, { 64, 88 },'),
    ('W04', 'the per-push flags leave the key', WI,
     '        if M.hasBit(flags, bit) then flags = flags - bit; end\n', ''),
    ('W05', 'a frame longer than its buffer is refused', WI,
     'h.len < M.SNAPSHOT_FIXED or h.len > #p or h.len > M.MAX_PAYLOAD', 'h.len < M.SNAPSHOT_FIXED or h.len > M.MAX_PAYLOAD'),
    ('W06', 'the frame size comes from its header, not the 512-byte buffer', WI,
     '    local size = math.floor(M.u16(data, 0) / 512) * 4;', '    local size = #data;'),

    # ---- the formula copy ----
    ('F01', 'the ranged food term keeps the server\'s +100', FO,
     'math.min(truncDiv(100 + (frame.foodRaccPct or 0) * base, 100)', 'math.min(truncDiv((frame.foodRaccPct or 0) * base, 100)'),
    ('F02', 'the threshold is truncated', FO,
     'return math.floor(M.rate(ctx, effective) * 100) * 100;', 'return math.floor(M.rate(ctx, effective) * 100 + 0.5) * 100;'),
    ('F03', 'skill past 200 counts 0.9 a point', FO,
     'if skill > 200 then return math.floor((skill - 200) * 0.9) + 200; end',
     'if skill > 200 then return math.floor((skill - 200) * 0.8) + 200; end'),
    ('F04', 'the level correction counts', FO,
     " - (frame.flashPenalty or 0) + (ctx.levelCorrection or 0);", " - (frame.flashPenalty or 0);"),

    # ---- the session client ----
    ('C01', 'an older Rev is refused', CL, "if s.rev <= st.lastRev then return reject('rev'); end", ''),
    ('C02', 'only the latest WatchGen is accepted', CL, "if s.watchGen ~= st.watchGen then return reject('watchGen'); end", ''),
    ('C03', 'only our Session', CL, "if st.session == 0 or s.session ~= st.session then return reject('session'); end", ''),
    ('C04', 'only the battle lane', CL, "if s.lane ~= 0 then return reject('lane'); end", ''),
    ('C05', 'only our protocol', CL, "if s.proto ~= wire.PROTO then return reject('proto'); end", ''),
    ('C06', 'a reply is ours only with our Nonce', CL, 'if h ~= nil and h.nonce ~= p.nonce then return false; end', ''),
    ('C07', 'the shared slot is given back between retries', CL,
     'if p.sentAt ~= nil and type(M._abandon) == \'function\' then pcall(M._abandon, p.op, p.seq); end', ''),
    ('C08', 'a lost WATCH asks what landed', CL, "if p.kind == 'watch' then queue('renew');", "if p.kind == 'watch' then queue('watch');"),
    ('C09', 'the session waits for an AutoAcc question', CL,
     "        if not wanted(t) then st.why = 'waiting for an AutoAcc piece'; return; end\n", ''),
    ('C10', 'an idle session ends with STOP', CL, "        if not wanted(t) then queue('stop'); end\n", ''),
    ('C11', 'an escalation never revives an unwanted session', CL,
     "        if kind == 'hello' and not wanted(t) then st.queued = nil; idle(); return; end\n", ''),
    ('C12', 'a push carries its comparison key', CL, '    s.key = wire.snapshotKey(f.payload);\n', ''),
    ('C13', 'questions need a live session', CL,
     "    if st.phase ~= 'live' or (kind ~= 'republish' and kind ~= 'renew') then return false; end",
     '    if false then return false; end'),
    ('C14', 'another character\'s HELLO answer is ignored', CL,
     "        if id ~= nil and h.charId ~= id then return; end   -- another character's answer\n", ''),
    ('C15', 'UNAVAILABLE backs off', CL,
     "st.phase, st.why, st.due = 'settling', 'unavailable', now() + M.BACKOFF;",
     "st.phase, st.why, st.due = 'settling', 'unavailable', now();"),
    ('C16', 'the lease is renewed after RenewAfter', CL,
     "        if st.queued == nil and st.lastTraffic ~= nil and t - st.lastTraffic >= st.renewAfter then queue('renew'); end\n", ''),
    ('C17', 'a lost push asks for a republish', CL, "        queue('republish');\n", ''),
    ('C18', 'BAD_OP: this server has no telemetry', CL,
     "        dormant(f.status == wire.status.BAD_OP and 'no telemetry on this server' or 'protocol mismatch');\n", ''),
    ('C19', 'the zone settles before the HELLO', CL,
     "    st.phase, st.due = 'settling', now() + M.SETTLE;", "    st.phase, st.due = 'settling', now();"),
    ('C20', 'unload sends STOP straight out', CL, '    pcall(M._direct, wire.outgoing(op, nextSeq(), payload));\n', ''),
    ('C21', 'a busy shared channel delays, never drops', CL,
     '            if not transmit(p) then p.sentAt = nil; end   -- busy: try on a later frame',
     '            transmit(p);'),

    # ---- the AutoAcc model: frames and bases ----
    ('A01', 'a formula failure drops the bases', AA,
     "    if bad ~= nil then st.why = 'formula check: ' .. bad; dropBases(); return; end",
     "    if bad ~= nil then st.why = 'formula check: ' .. bad; return; end"),
    ('A02', 'an Onslaught frame decides nothing', AA,
     "    if wire.hasBit(frame.snapFlags, wire.snapFlag.GEAR_REFILL) then st.why = 'inside an Onslaught run'; dropBases(); return; end\n", ''),
    ('A03', 'a new key starts over', AA, '    if frame.key == nil or frame.key ~= st.key then', '    if frame.key == nil then'),
    ('A04', 'a passing frame becomes a basis', AA, '    addBasis(frame, outfit);\n', ''),
    ('A05', 'a mismatch marks only the differing pieces', AA,
     '        if id ~= 0 and (ref == nil or ref.outfit.ids[slot] ~= id) then st.unverified[id] = why; end',
     '        if id ~= 0 then st.unverified[id] = why; end'),
    ('A06', 'the gear check compares live - R with dlac\'s sums', AA,
     "        if server ~= sums[k] then return false, ('%s: the server adds %d, dlac %d'):format(k, server, sums[k]); end\n", ''),
    ('A07', 'the newest basis that fits decides', AA, '    for i = #st.baseOrder, 1, -1 do', '    for i = 1, #st.baseOrder do'),
    ('A08', 'an older basis may decide', AA, '        if why == nil then return b; end', '        if why == nil and i == #st.baseOrder then return b; end'),
    ('A09', 'no republish for the outfit the newest frame already measured', AA,
     "    if latest.equipRev == wornHash or st.bases[wornHash] ~= nil or type(M._ask) ~= 'function' then return; end",
     "    if st.bases[wornHash] ~= nil or type(M._ask) ~= 'function' then return; end"),
    ('A10', 'a republish once per outfit', AA, '    if at ~= nil and t - at < M.ASK_AGAIN then return; end\n', ''),

    # ---- the AutoAcc model: triggers and demand ----
    ('A11', 'a new target holds', AA,
     "if p.target ~= nil and st.latest ~= nil and p.target ~= st.latest.targetId then return 'a new target'; end", ''),
    ('A12', 'a level or job change holds', AA,
     "        return 'a level or job change';", '        return nil;'),
    ('A13', 'a gained accuracy debuff holds', AA,
     "        if now[id] and not before[id] then return 'an accuracy debuff'; end\n", ''),
    ('A14', 'only losing an accuracy effect holds', AA,
     '        if not now[id] and M.ACC_EFFECTS[id] then lost = true; break; end',
     '        if not now[id] then lost = true; break; end'),
    ('A15', 'a listed loss holds until LOSS_SETTLE', AA,
     "    if t - st.effectsAt < M.LOSS_SETTLE then return 'an accuracy effect wore off'; end\n", ''),
    ('A16', 'a settled loss is let go', AA,
     '    for id in pairs(before) do if not now[id] then before[id] = nil; end end\n', ''),
    ('A17', 'a settled loss asks what landed', AA, "    if type(M._ask) == 'function' then pcall(M._ask, 'renew'); end\n", ''),
    ('A18', 'the outfit is sampled only while a decision is wanted', AA,
     '    if wanted(M._clock()) then rememberWorn(false); end', '    rememberWorn(false);'),
    ('A19', 'a decision tells the client it is wanted', AA, "    if type(M._want) == 'function' then pcall(M._want); end\n", ''),
    ('A20', 'the player read is reused for PLAYER_EVERY', AA,
     '    if not fresh and st.player ~= nil and st.playerAt ~= nil and t - st.playerAt < M.PLAYER_EVERY then',
     '    if false then'),

    # ---- the AutoAcc model: the decision ----
    ('A21', 'nothing is released unless the full set reaches the cap', AA,
     "    if not meets then return hold('the full set does not reach the cap'); end\n", ''),
    ('A22', 'a higher removal priority goes first', AA,
     'if (a.prio or 0) ~= (b.prio or 0) then return (a.prio or 0) > (b.prio or 0); end',
     'if (a.prio or 0) ~= (b.prio or 0) then return (a.prio or 0) < (b.prio or 0); end'),
    ('A23', 'a trigger holds every piece', AA, "    if trigger ~= nil then return hold('held until the next frame: ' .. trigger); end\n", ''),
    ('A24', 'the same question is one decision', AA, '    if st.memo ~= nil and st.memo.key == key then return st.memo.out; end\n', ''),
    ('A25', 'the memo keeps weapon skills and the standing set apart', AA,
     "    local key = planKey(req) .. '|' .. tostring(req.event) .. '|' .. tostring(st.rev)",
     "    local key = planKey(req) .. '|' .. tostring(st.rev)"),
    ('A26', 'only the standing Default set releases', AA,
     "    if req.event ~= nil and req.event ~= 'Default' then return hold('only the standing Default set releases'); end\n", ''),
    ('A27', 'weapon slots stay', AA, "        if slot == nil or slot < M.FIRST_ARMOUR then why = 'weapon slots stay';",
     "        if slot == nil then why = 'weapon slots stay';"),
    ('A28', 'a used enchantment stays', AA, '        elseif enchanted(slot, typedId) then', '        elseif false then'),
    ('A29', 'level latents are modelled', AA,
     'local on = (r.from ~= nil and level >= r.from) or (r.below ~= nil and level < r.below);', 'local on = false;'),
    ('A30', 'an accuracy latent is unmodelled', AA,
     "            if HIT_STATS[row.stat] then return 'an accuracy latent (' .. tostring(row.cond) .. ')'; end\n", ''),
    ('A31', 'an augmented copy is unmodelled', AA, "    if augmented then return 'augmented'; end\n", ''),
    ('A32', 'a piece covering another slot is unmodelled', AA, "    if v.rslot ~= nil and v.rslot ~= 0 then return 'it covers another slot'; end\n", ''),
    ('A33', 'an equip script dlac does not know is unmodelled', AA,
     "        return 'an equip script dlac does not model';", '        return nil;'),
    ('A34', 'an unverified piece stays', AA,
     "            if why == nil and (st.unverified[typedId] or st.unverified[fallbackId]) then why = 'unverified'; end\n", ''),
    ('A35', 'a release may not lower max HP under an HP latent', AA,
     "                why = 'it lowers max HP while an HP latent is worn';", '                why = nil;'),
    ('A36', 'a piece must still be the slot\'s to be released', AA,
     "        elseif typedId ~= accepted[slot] then why = 'the slot is not the piece';", '        elseif false then'),

    # ---- the prediction check ----
    ('P01', 'only an unchanged state can check a prediction', AA, '    if not sameState(pr.basis, frame) then', '    if false then'),
    ('P02', 'the prediction is compared with the server', AA,
     '            if row.acc ~= ctx.liveAcc or row.threshold ~= ctx.thresholdBp then ok = false; end\n', ''),
    ('P03', 'a wrong prediction keeps its pieces on', AA,
     "                if after ~= 0 then st.mispredicted[after] = 'a release predicted wrongly'; end\n", ''),
    ('P04', 'a mispredicted piece is not released again', AA,
     '            if why == nil and (st.mispredicted[typedId] or st.mispredicted[fallbackId]) then', '            if false then'),
    ('P05', 'a hold retires a waiting prediction', AA,
     "        for _, c in ipairs(cands) do out.why[c.slot] = why; end\n        retire('the pieces went back on before the server measured it');",
     '        for _, c in ipairs(cands) do out.why[c.slot] = why; end'),
    ('P06', 'the same release re-arms a retired prediction', AA, "            pr.verdict, pr.why = 'waiting', nil;", '            pr.why = nil;'),
    ('P07', 'only a frame of the predicted outfit measures it', AA,
     '    if outfit == nil or not sameIds(outfit.ids, pr.ids) then return; end', '    if outfit == nil then return; end'),
    ('P08', 'every passing frame is measured', AA, '    addBasis(frame, outfit);\n    measure(frame);', '    addBasis(frame, outfit);'),
    ('P09', 'zoning forgets the verdicts', AA, '    st.prediction, st.mispredicted = nil, {};\n', ''),

    # ---- the engine's single send ----
    ('D01', 'the slot\'s last writer decides whether it holds a candidate', DS,
     '                    ctx.planAcc[slot] = (meta ~= nil and name == meta.typed) and meta or nil;',
     '                    if meta ~= nil then ctx.planAcc[slot] = meta; end'),
    ('D02', 'Free-equip slots read as worn', DS,
     '    for slot, v in pairs(stripDisabled(ctx.planOut)) do', '    for slot, v in pairs(ctx.planOut) do'),
    ('D03', 'a release lands only where the slot still holds the piece', DS,
     '        if meta ~= nil and nameOf(ctx.planOut[slot]) == meta.typed then ctx.planOut[slot] = fallback; end',
     '        ctx.planOut[slot] = fallback;'),
    ('D04', 'with the provider every typed piece is planned on', DS,
     '    if M._autoAccService() ~= nil then\n        local pick, meta = {}, {};', '    if false then\n        local pick, meta = {}, {};'),
    ('D05', 'a locked slot is never offered', DS,
     '        if plan[slot] ~= nil and M.locks[string.lower(tostring(slot))] ~= true then',
     '        if plan[slot] ~= nil then'),
    ('D06', 'the provider\'s revision is a retrace leg', DS, "              .. '|aa' .. M._autoAccRev();", '              .. \'|aa\';'),

    # ---- the box ----
    ('U01', 'the box escapes its percents once', MO, "local function pct(bp) return ('%d%%'):format(math.floor((bp or 0) / 100)); end",
     "local function pct(bp) return ('%d%'):format(math.floor((bp or 0) / 100)); end"),
    ('U02', 'spare and needs are the right way round', MO, '            if toCap <= 0 then', '            if toCap >= 0 then'),
    ('U03', 'the cap starts at ACC + to-cap', MO,
     "                { ('%d'):format((ctx.liveAcc or 0) + toCap), col.USABLE },",
     "                { ('%d'):format((ctx.liveAcc or 0) - toCap), col.USABLE },"),
    ('U04', 'the row text is escaped', MO, '    return level, esc(text);', '    return level, text;'),
    ('U05', 'the decision rows follow the slot order', MO,
     '        if d.why[slot] ~= nil then row(slot, d.why[slot]); seen[slot] = true; end\n', ''),
    ('U06', 'a disarmed engine is named', MO, "    if not nativeOn() then return 0, 'off -- the engine is disarmed'; end\n", ''),
    ('U07', 'the panel opens the window', MO, '        M.visible = not M.visible;\n    end', '    end'),
    ('U08', 'an open box is demand', MO, "    if type(M._want) == 'function' then pcall(M._want); end\n", ''),
    ('U09', 'no table without a live frame', MO,
     '    if type(frame) ~= \'table\' or frame.laneState ~= wire.laneState.LIVE then', "    if type(frame) ~= 'table' then"),
    ('U10', 'kept-on counts the mispredicted pieces', MO,
     '    for id in pairs(r.mispredicted or {}) do count = count + 1;', '    for id in pairs({}) do count = count + 1;'),
    ('U11', 'a wrong prediction says so', MO,
     "    line(col, 'Prediction', good and ('matched the server for ' .. what)", "    line(col, 'Prediction', true and ('matched the server for ' .. what)"),

    # ---- the Gear Rule combo and the draw site ----
    ('G01', 'a typed piece keeps AutoAcc offered on any server', GU,
     "    if svc ~= nil or (type(it) == 'table' and it.autoType == 'AutoAcc') then", '    if svc ~= nil then'),
    ('G02', 'a set removal priority stays', GU,
     "        it.autoType, it.removePrio, it.dw = 'AutoAcc', it.removePrio or 1, nil;",
     "        it.autoType, it.removePrio, it.dw = 'AutoAcc', 1, nil;"),
    ('G03', 'the tip names a disarmed engine', GU,
     "               .. (native and '' or '\\n\\ndlac\\'s engine is disarmed this session, so AutoAcc decides nothing.') };",
     "               .. '' };"),
    ('G04', 'AutoAcc clears Dual Wield', GU,
     "        it.autoType, it.removePrio, it.dw = 'AutoAcc', it.removePrio or 1, nil;",
     "        it.autoType, it.removePrio = 'AutoAcc', it.removePrio or 1;"),

    # ---- the flatten's gates, before the AutoAcc split ----
    ('L01', 'an entry\'s max level applies to AutoAcc', UT, '            if mjLv > maxLevel then break; end\n', ''),
    ('L02', 'an entry\'s min level applies to AutoAcc', UT, '            if mjLv < minLevel then break; end\n', ''),
    ('L03', 'typed entries compete only among themselves', UT,
     '            if isAuto then\n                out.accs[#out.accs + 1] = {', '            if false then\n                out.accs[#out.accs + 1] = {'),

    # ---- the Ashita glue and the pack wiring ----
    ('I01', 'every frame of the partition is blocked', IN,
     '        e.blocked = true;\n        pcall(function() client.onFrame(wire.incoming(data)); end);',
     '        pcall(function() client.onFrame(wire.incoming(data)); end);'),
    ('I02', 'only the partition is blocked', IN,
     '        if op < wire.OP_FIRST or op > wire.OP_LAST then return; end', '        if op < wire.OP_FIRST then return; end'),
    ('I03', '/dl accuracy opens the box', IN,
     "        if word ~= 'accuracy' and word ~= 'autoacc' then return; end", "        if word ~= 'autoacc' then return; end"),
    ('I04', 'the box keeps the session wanted', IN,
     'monitor._client, monitor._autoacc, monitor._want = client, autoacc, client.want;',
     'monitor._client, monitor._autoacc = client, autoacc;'),
    ('I05', 'the pack mounts the telemetry module', MD, ", 'restocknotice', 'telemetry' }", ", 'restocknotice' }"),
    ('I06', 'the AutoAcc helper row is enabled on AscensionXI', FT, 'choco = true, autoacc = true },', 'choco = true },'),
]

# Mutants that survive for a stated reason (equivalent, or not a defect).
ACCEPTED = {
    'C21': 'equivalent: with the channel busy both versions send again on the next frame; the mutant '
           'only calls transport.abandon for a slot this request does not hold, which abandon ignores '
           '(it frees only its own op and seq)',
}

FAST = [['tests/ascensionxi_telemetry_wire.lua'], ['tests/ascensionxi_telemetry_client.lua'],
        ['tests/ascensionxi_autoacc.lua'], ['tests/ascensionxi_autoacc_dispatch.lua'],
        ['tests/ascensionxi_autoacc_ui.lua']]
SLOW = [['tests/pack_lint.lua', 'ascensionxi'], ['tests/smoke_ui.lua'], ['tests/run_tests.lua']]


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True)


def clean():
    return git('status', '--porcelain', '--untracked-files=no').stdout.strip() == ''


def first_red(stop_early=True):
    """The suites that go red, fast ones first; stops at the first unless told not to."""
    red = []
    for s in FAST + SLOW:
        r = subprocess.run([LUA, *s], cwd=ROOT, capture_output=True, text=True, timeout=900)
        if r.returncode != 0:
            red.append(Path(s[0]).stem)
            if stop_early:
                break
    return red


def parses(path):
    r = subprocess.run([LUA, '-e', "assert(loadfile('%s'))" % path], cwd=ROOT, capture_output=True, text=True)
    return r.returncode == 0


def encoded(data, text):
    nl = b'\r\n' if b'\r\n' in data else b'\n'
    return text.encode().replace(b'\n', nl)


def main(argv):
    if argv == ['--check']:
        broken = []
        for mid, _, path, old, _ in M:
            data = (ROOT / path).read_bytes()
            if data.count(encoded(data, old)) != 1:
                broken.append(mid)
        print('%d/%d patterns apply' % (len(M) - len(broken), len(M)), *broken)
        return 1 if broken else 0
    only = [a for a in argv if not a.startswith('--')]
    if not clean():
        print('refusing to start: the tree has uncommitted changes (git status --porcelain).')
        return 2
    base = first_red(stop_early=False)
    if base:
        print('refusing to start: the unmutated tree already fails: ' + ', '.join(base))
        return 2
    results = []
    for mid, guard, path, old, new in M:
        if only and mid not in only:
            continue
        f = ROOT / path
        data = f.read_bytes()
        o, n = encoded(data, old), encoded(data, new)
        rec = {'id': mid, 'guard': guard, 'file': path}
        t = time.time()
        if data.count(o) != 1:
            rec.update(result='not-applied', why='pattern found %d times' % data.count(o))
        else:
            f.write_bytes(data.replace(o, n))
            try:
                if not parses(path):
                    rec.update(result='invalid', why='the mutant does not parse')
                else:
                    failed = first_red()
                    rec.update(result='killed' if failed else 'survived', by=failed)
            finally:
                f.write_bytes(data)
            if f.read_bytes() != data or not clean():
                print('the tree did not restore after %s -- stopping.' % mid)
                return 2
        rec['secs'] = round(time.time() - t, 2)
        results.append(rec)
        OUT.write_text(json.dumps(results, indent=1))
        print('%s %-11s %s' % (mid, rec['result'], guard), flush=True)

    print('\n| Mutant | Guard | Result | Red suite |')
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
