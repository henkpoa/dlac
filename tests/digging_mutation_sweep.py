"""Mutation sweep for the AscensionXI Digging tab (docs/reference/ascensionxi-
digging.md, "Mutation sweep"): the dig mover, the 0x81 status client, the
rank and weather changes and the panel. Every guard is broken once, the
digging suites run, and at least one must go red. The file is always
restored from the bytes it read.

    python tests/digging_mutation_sweep.py --server <ascensionxi checkout>
    python tests/digging_mutation_sweep.py D07 S04 --server ...     only these

Run from the repo root on a clean tree (it refuses otherwise). Lua 5.4 as
`lua` (or set LUA=lua5.4). --server is the AscensionXI checkout for
tests/ascensionxi_digging.lua's companion half (the server's 0x81 endpoint
answering this client); without it that half is skipped. Prints a markdown
board and exits 1 when a mutant survives, cannot be applied or breaks the
file's syntax -- unless it is listed in ACCEPTED with the reason it is not a
defect.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.gettempdir()) / 'dlac-digging-mutation-sweep.json'
LUA = os.environ.get('LUA', 'lua')

DS = 'feature/digstorage.lua'
ST = 'servers/ascensionxi/modules/digging/status.lua'
IN = 'servers/ascensionxi/modules/digging/init.lua'
HM = 'servers/ascensionxi/modules/helm/status.lua'
CW = 'feature/chocowatch.lua'
DC = 'feature/digcalc.lua'
CU = 'ui/chocoui.lua'
HB = 'ui/hobbybar.lua'
FT = 'servers/ascensionxi/features.lua'
MO = 'servers/ascensionxi/modules.lua'
DL = 'dlac.lua'

# id, guard, file, old, new
M = [
    # ---- the dig mover: what counts as dug ----
    ('D01', 'only our dig action (0x11) counts', DS,
     '    if id ~= 0x01A or #data < 12 or u16(data, 10) ~= M.DIG_ACTION then return; end',
     '    if id ~= 0x01A or #data < 12 then return; end'),
    ('D02', 'no destination: digs are not tracked', DS,
     '        if not enabled() or stopped then return; end', '        if stopped then return; end'),
    ('D03', 'a stopped mover tracks nothing', DS,
     '        if not enabled() or stopped then return; end', '        if not enabled() then return; end'),
    ('D04', 'a dig counts only with ITEM_SAME and our animation', DS,
     '        if capture.itemSame and capture.dug then finish(); end',
     '        if capture.itemSame or capture.dug then finish(); end'),
    ('D05', 'only our own dig animation', DS,
     'u32(data, 4) == D.playerId() then', 'true then'),
    ('D06', 'dug greens are never counted', DS,
     'if it.id > 0 and not seen[it.id] and not M.KEEP[it.id] then', 'if it.id > 0 and not seen[it.id] then'),
    ('D07', 'a move landing mid-dig is added back', DS,
     ' + (capture.movedOut[it.id] or 0);', ';'),
    ('D08', 'an unanswered dig expires', DS,
     '            if now - capture.at >= M.CAPTURE_S then capture = nil; end',
     '            if false then capture = nil; end'),
    # ---- the dig mover: what moves, and when ----
    ('D09', 'stock carried in stays (never more than digs added)', DS,
     '                if it.id == id and it.flags == 0 and it.count > 0 and it.count <= owed\n',
     '                if it.id == id and it.flags == 0 and it.count > 0\n'),
    ('D10', 'partial stacks wait for a pause', DS,
     '                    and (flush or it.count >= stack) and not D.equipped(slot) then',
     '                    and not D.equipped(slot) then'),
    ('D11', 'the pause is six seconds', DS, 'FLUSH_S = 6,', 'FLUSH_S = 1,'),
    ('D12', 'units used by hand leave the count', DS,
     '            if held < owed then owed = held; self.owed[id] = held > 0 and held or nil; end',
     '            if false then end'),
    ('D13', 'an equipped item stays', DS,
     '                    and (flush or it.count >= stack) and not D.equipped(slot) then',
     '                    and (flush or it.count >= stack) then'),
    ('D14', 'a locked stack stays', DS,
     '                if it.id == id and it.flags == 0 and it.count > 0 and it.count <= owed\n',
     '                if it.id == id and it.count > 0 and it.count <= owed\n'),
    ('D15', 'moves wait for a quiet inventory', DS,
     'if now < nextAt or now - lastInventory < M.QUIET_S or not D.ready() then return; end',
     'if now < nextAt or not D.ready() then return; end'),
    ('D16', 'moves wait until the player is ready', DS,
     'if now < nextAt or now - lastInventory < M.QUIET_S or not D.ready() then return; end',
     'if now < nextAt or now - lastInventory < M.QUIET_S then return; end'),
    # ---- the dig mover: where, and failures ----
    ('D17', 'a full Mog Case: the Satchel next', DS,
     'for _, cid in ipairs({ 7, 5 }) do', 'for _, cid in ipairs({ 7 }) do'),
    ('D18', 'a whole stack merges into a destination stack with room', DS,
     '            if other.id == id and other.flags == 0 and other.count > 0 and other.count < stack then',
     '            if false then'),
    ('D19', 'only what fits counts as moved', DS,
     'return b, i, math.min(count, stack - other.count);', 'return b, i, count;'),
    ('D20', 'no room: retry after a second', DS,
     '            nextAt = now + 1;', '            nextAt = now + 60;'),
    ('D21', 'a failed send stops the mover', DS,
     '                    if not D.send(p) then', '                    if not D.send(p) and false then'),
    ('D22', 'an unconfirmed move stops the mover and forgets', DS,
     '                flight, capture, stopped = nil, nil, true;\n                self.owed = {};',
     '                flight = nil;'),
    ('D23', 'a zone line keeps the counts and drops what is in flight', DS,
     '        if id == 0x00A or id == 0x00B then self.zoned(); return; end\n', ''),
    ('D24', 'both switches off forgets the counts', DS,
     '        if not enabled() then self.owed = {}; end\n', ''),
    ('D25', 'moves wait for the zone to settle', DS,
     'if now < nextAt or now < holdUntil or', 'if now < nextAt or'),
    ('D26', 'a move cut off by a zone line counts as done', DS,
     '            self.owed[flight.id] = left > 0 and left or nil;\n        end\n        capture, flight = nil, nil;',
     '        end\n        capture, flight = nil, nil;'),
    ('D27', 'a stack with room in any selected bag before a free slot', DS,
     '    for _, b in ipairs(bags) do\n        for i = 1, b.bag.max do\n            local other = item(b.bag, i);\n'
     '            if other.id == id and other.flags == 0',
     '    for _, b in ipairs({ bags[1] }) do\n        for i = 1, b.bag.max do\n            local other = item(b.bag, i);\n'
     '            if other.id == id and other.flags == 0'),
    # ---- the 0x81 status client ----
    ('S01', 'a reply must declare 36 bytes', ST,
     '    if wireSize ~= 36 or #data < wireSize or flags ~= 0', '    if #data < wireSize or flags ~= 0'),
    ('S02', 'a truncated reply is refused', ST,
     '    if wireSize ~= 36 or #data < wireSize or flags ~= 0', '    if wireSize ~= 36 or flags ~= 0'),
    ('S03', 'the reply version must be 1', ST,
     'or u16(data, 8) ~= 1 or u16(data, 10) ~= 0', 'or u16(data, 10) ~= 0'),
    ('S04', 'the token must be ours', ST,
     '        or u32(data, 12) ~= pending then return true; end', '        then return true; end'),
    ('S05', 'skill over 100 is refused', ST,
     '    if skill > 1000 or rank > 10 then return true; end', '    if rank > 10 then return true; end'),
    ('S06', 'rank over Expert is refused', ST,
     '    if skill > 1000 or rank > 10 then return true; end', '    if skill > 1000 then return true; end'),
    ('S07', 'BAD_OP (an older server) stops asking', ST,
     '    if status == 1 or status == 6 then', '    if status == 6 then'),
    ('S08', 'UNAVAILABLE backs off 30 s', ST,
     '(status == 3 and M.POLL_SECONDS or 30)', 'M.POLL_SECONDS'),
    ('S09', 'a poll every five seconds', ST, 'POLL_SECONDS = 5', 'POLL_SECONDS = 4'),
    ('S10', 'the refill counts down between polls', ST,
     'refillIn = function() return math.max(0, refill - (M._clock() - at)); end,',
     'refillIn = function() return refill; end,'),
    ('S11', 'after a zone, wait five seconds before asking', ST,
     '    due = M._clock() + (settle and 5 or 0);', '    due = M._clock();'),
    ('S12', 'only op 0x81 is ours', ST,
     '    if op ~= M.OP then return false; end', '    if op < 0x80 or op > 0x8F then return false; end'),
    ('S13', 'the access bit is read', ST,
     'voidAccess = data:byte(28) % 2 == 1,', 'voidAccess = true,'),
    ('S14', 'an unanswered request is given up after two sends', ST,
     '    if pending and attempts >= 2 then pending = nil; end\n', ''),
    ('S15', 'a busy channel retries soon', ST, 'due = now + 0.35;', 'due = now + 30;'),
    ('I01', 'zoning clears the snapshot', IN,
     '        if e.id == 0x00A or e.id == 0x00B then status.reset(true); return; end\n', ''),
    ('I02', 'our reply is kept from the client', IN,
     'if e.id == status.PKT and status.onPacket(e.data) then e.blocked = true; end',
     'if e.id == status.PKT then status.onPacket(e.data); end'),
    ('I03', 'the service says its rank is exact', IN, '    exactRank = true,', '    exactRank = false,'),
    ('H01', 'the HELM client marks only its own op received', HM,
     '    if op == M.OP and M._received then M._received(op, seq); end',
     '    if M._received then M._received(op, seq); end'),
    # ---- rank: the server's, not guessed ----
    ('C01', 'the server rank wins', CW,
     '    if svc ~= nil then\n        local rank = nil;', '    if false then\n        local rank = nil;'),
    ('C02', 'no first-dig timing guess with the service', CW,
     '    if not _drok or M._rankMaxed() or packDigging() ~= nil then return false; end',
     '    if not _drok or M._rankMaxed() then return false; end'),
    ('C03', 'no item-name ratchet with the service', CW,
     'function M.recordObtained(name)\n    if not _drok or packDigging() ~= nil then return false; end',
     'function M.recordObtained(name)\n    if not _drok then return false; end'),
    ('C04', 'no item-id ratchet with the service', CW,
     'function M.recordObtainedById(id, zoneId)\n    if not _drok or packDigging() ~= nil then return false; end',
     'function M.recordObtainedById(id, zoneId)\n    if not _drok then return false; end'),
    # ---- the move switches ----
    ('C05', 'the switches are read back', CW,
     '                M.moveCase, M.moveSatchel = t.moveCase == true, t.moveSatchel == true;\n', ''),
    ('C06', 'the switches are saved', CW,
     '            tostring(M.moveCase == true), tostring(M.moveSatchel == true)));',
     "            'false', 'false'));"),
    ('C07', 'container 7 is the Case, 5 the Satchel', CW,
     '    if cid == 7 then M.moveCase = on == true;\n    elseif cid == 5 then M.moveSatchel = on == true;',
     '    if cid == 7 then M.moveSatchel = on == true;\n    elseif cid == 5 then M.moveCase = on == true;'),
    ('C08', 'a switch change resumes the mover', CW,
     "    pcall(function() require('dlac\\\\feature\\\\digstorage').live.changed(); end);\n", ''),
    # ---- the dig guide: AscensionXI's ore weather ----
    ('G01', 'ores under any elemental weather', DC,
     '    if ores.anyElementalWeather then return weatherElement ~= nil; end\n', ''),
    ('G02', 'no ore without elemental weather', DC,
     'return weatherElement ~= nil; end', 'return true; end'),
    ('G03', 'the condition names the weather rule', DC,
     "return ores.anyElementalWeather and 'any elemental weather' or 'matching weather';",
     "return 'matching weather';"),
    ('G04', 'the area odds use the weather rule', DC,
     '        local weatherOK = oreWeatherOK(or_, el, wel);',
     '        local weatherOK = (not or_.requiresElementalWeather) or (el ~= nil and wel == el);'),
    ('G05', 'the item search uses the weather rule', DC,
     '        local weatherOK = oreWeatherOK(or_, del, wel);',
     '        local weatherOK = (not or_.requiresElementalWeather) or (del ~= nil and wel == del);'),
    # ---- the panel and the bar ----
    ('U01', 'durations show hours', CU,
     "    if h > 0 then return string.format('%dh %dm', h, m); end",
     "    if h > 1 then return string.format('%dh %dm', h, m); end"),
    ('U02', 'no stored count without Void Storage', CU,
     '    if snap.voidAccess then\n        lines[3]', '    if true then\n        lines[3]'),
    ('U03', 'an unread inventory shows ?', CU,
     "local held = inventoryGreens ~= nil and tostring(inventoryGreens) or '?';",
     'local held = tostring(inventoryGreens);'),
    ('U04', 'the panel shows the server status, not the rank picker', CU,
     '    if M.packDigging() ~= nil then\n        -- The server reports skill and rank',
     '    if false then\n        -- The server reports skill and rank'),
    ('U05', 'no service: no switches', CU,
     "    if M.packDigging() == nil then return; end\n    local cwok", '    local cwok'),
    ('U06', 'the waiting count is shown', CU,
     '        if waiting > 0 then', '        if false then'),
    ('U07', 'the panel counts only Gysahl Greens', CU,
     '            if it and it.Id == M.GREENS_ID then n = n + (it.Count or 0); end',
     '            if it then n = n + (it.Count or 0); end'),
    ('B01', 'the bar shows the digging block on a digging server', HB,
     "local serverDigging = cu ~= nil and type(cu.packDigging) == 'function' and cu.packDigging() ~= nil;",
     'local serverDigging = false;'),
    # ---- wiring ----
    ('F01', 'Chocobo is enabled for AscensionXI', FT,
     'helpers = { helm = true, choco = true },', 'helpers = { helm = true },'),
    ('F02', 'the digging module is loaded', MO,
     "return { 'gearvault', 'helm', 'digging', 'ascension', 'restocknotice' };",
     "return { 'gearvault', 'helm', 'ascension', 'restocknotice' };"),
    ('F03', 'the dig mover is loaded', DL,
     r"'feature\\chocowatch', 'feature\\digstorage',", r"'feature\\chocowatch',"),
]

# Mutants that survive for a stated reason (equivalent, or not a defect).
ACCEPTED = {
    'D02': 'equivalent: with no destination on, tick() resets the mover every 0.1 s, so a dig tracked '
           'then is dropped before anything can move it',
    'H01': 'equivalent: transport.received frees only the pending (op, seq); the digging module reports '
           'its own 0x81 replies, so a second report of the same frame finds it answered and only adds '
           'an audit line',
}


def suites(server):
    out = [['tests/digstorage.lua'],
           ['tests/ascensionxi_digging.lua'] + ([server] if server else []),
           ['tests/ascensionxi_digging_ui.lua'],
           ['tests/ascensionxi_helm.lua'],
           ['tests/smoke_ui.lua'],
           ['tests/run_tests.lua']]
    return out


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True)


def clean():
    return git('status', '--porcelain', '--untracked-files=no').stdout.strip() == ''


def run_suites(all_suites):
    failed = []
    for s in all_suites:
        r = subprocess.run([LUA, *s], cwd=ROOT, capture_output=True, text=True, timeout=600)
        if r.returncode != 0:
            failed.append(Path(s[0]).stem)
    return failed


def parses(path):
    r = subprocess.run([LUA, '-e', "assert(loadfile('%s'))" % path], cwd=ROOT, capture_output=True, text=True)
    return r.returncode == 0


def main(argv):
    server = None
    if '--server' in argv:
        server = argv[argv.index('--server') + 1]
    only = [a for a in argv if not a.startswith('--') and a != server]
    if not clean():
        print('refusing to start: the tree has uncommitted changes (git status --porcelain).')
        return 2
    all_suites = suites(server)
    base = run_suites(all_suites)
    if base:
        print('refusing to start: the unmutated tree already fails: ' + ', '.join(base))
        return 2
    results = []
    for mid, guard, path, old, new in M:
        if only and mid not in only:
            continue
        f = ROOT / path
        data = f.read_bytes()
        nl = b'\r\n' if b'\r\n' in data else b'\n'
        o, n = old.encode().replace(b'\n', nl), new.encode().replace(b'\n', nl)
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
                    failed = run_suites(all_suites)
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
