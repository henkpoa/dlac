"""Mutation sweep for the AscensionXI DNC Status (docs/design/dnc-status.md):
the slot-1 codec, the client state and its view, the Job helper's window and
Panel, the loader's `servers` and pack-list rules, and the shared gate's
producer name. Every guard is broken once, tests/ascensionxi_dncstatus.lua
and tests/run_tests.lua run, and at least one must go red. The file is always
restored from the bytes it read.

    python tests/dncstatus_mutation_sweep.py            every mutant
    python tests/dncstatus_mutation_sweep.py D07 H03    only these

Run from the repo root on a clean tree, with Lua 5.4 as `lua`. Exits 1 when a
mutant survives or its pattern no longer matches exactly once.
"""
import subprocess, sys, pathlib

ROOT = pathlib.Path('.')
ST = 'servers/ascensionxi/modules/dncstatus/status.lua'
WI = 'servers/ascensionxi/modules/dncstatus/wire.lua'
HE = 'jobhelpers/dnc/dnc-status/init.lua'
JH = 'feature/jobhelpers.lua'
TR = 'servers/ascensionxi/transport.lua'
FG = 'lib/featuregate.lua'

M = [
    ('D01 no demand gate', ST, "    if not wanted(now) then return; end\n", ""),
    ('D02 any job subscribes', ST, "    if not isDnc(M._player()) then return; end\n", ""),
    ('D03 any seq answers', ST, "        if f.seq ~= pendingSeq then return; end\n", ""),
    ('D04 BUSY goes dormant', ST, "        if f.status == wire.status.BUSY then", "        if false then"),
    ('D05 a refusal keeps asking', ST, "            dormant, sub = true, 'dormant';   -- a server", "            sub = nil;   -- a server"),
    ('D06 older pushes applied', ST, "        if state ~= nil and not wire.newer(s.rev, state.rev) then return; end\n", ""),
    ('D07 zone keeps the old state', ST, "    pendingSeq, pendingAt, misses = nil, nil, 0;\n    state, stateAt = nil, nil;\n", "    pendingSeq, pendingAt, misses = nil, nil, 0;\n"),
    ('D08 no cap on the memory', ST, "applies = cap and math.min(lv, cap) or lv", "applies = lv"),
    ('D09 Trance capped', ST, "    if not trance then cap = state.base + state.perStack * stacks; end", "    cap = state.base + state.perStack * stacks;"),
    ('D10 price of the current stack', ST, "state.prices[math.min(stacks + 1, M.MAX_STACKS)]", "state.prices[math.max(stacks, 1)]"),
    ('D11 short never flagged', ST, "short = (cost ~= nil and v.tp ~= nil and v.tp < cost)", "short = false"),
    ('D12 run-out Dazes kept', ST, "if lv > 0 and left > 0 then", "if lv > 0 then"),
    ('D13 no countdown', ST, "local left = state.seconds[i] - elapsed;", "local left = state.seconds[i];"),
    ('D14 memory needs the icon', ST, "    if state.memory > 0 then", "    if state.memory > 0 and buffs[M.BUFF.PERPETUAL_STEP] then"),
    ('D15 below 30 learnt', ST, "learnt = level >= M.LEVEL", "learnt = true"),
    ('D16 slot ignored', WI, "and op % 8 == M.SLOT", ""),
    ('D17 level not clamped', WI, "levels[i] = (l <= 15) and l or 15;", "levels[i] = l;"),
    ('D18 unload sends no stop', ST, "        pcall(M._direct, wire.subscribe(seq, false));\n", ""),
    ('D19 BUSY retried at once', ST, "            sub, due = nil, M._clock() + M.BUSY_WAIT;", "            sub, due = nil, M._clock();"),
    ('D20 silence never dormant', ST, "        if wait == nil then dormant, sub, due = true, 'dormant', nil; return; end", "        if wait == nil then wait = 60; end"),
    ('H01 window in town', HE, "(full or v.memory ~= nil)", "true"),
    ('H02 window switch ignored', HE, "        if not enabled(S, 'window') or not anySection(S) then return; end", "        if not anySection(S) then return; end"),
    ('H03 HUD ignored', HE, "        if hidden then return; end\n", ""),
    ('H04 lock ignored', HE, "        if enabled(S, 'locked') then fl = fl + flag('ImGuiWindowFlags_NoMove'); end\n", ""),
    ('H05 demand with every section off', HE, "        if not enabled(S, 'window') or not anySection(S) then return; end", "        if not enabled(S, 'window') then return; end"),
    ('H06 section switch ignored', HE, "    if enabled(S, 'targetEffects') and (full or v.target ~= nil) then", "    if (full or v.target ~= nil) then"),
    ('H07 no servers list', HE, "    servers = { 'ascensionxi' },\n", ""),
    ('H08 short price not orange', HE, "r.short and ui.COL.warn or ui.COL.dim", "ui.COL.dim"),
    ('H09 no applies note', HE, "        if st.applies < st.level then note", "        if false then note"),
    ('J01 servers ignored', JH, "                elseif not M.forServer(rec.servers, opts.server) then", "                elseif false then"),
    ('J02 no server admits all', JH, "    if servers == nil then return true; end\n    for _, s in ipairs(servers) do", "    if servers == nil or active == nil then return true; end\n    for _, s in ipairs(servers) do"),
    ('J03 bad servers accepted', JH, "        if type(mod.servers) ~= 'table' or #mod.servers == 0 then\n            return nil, 'servers is not a list of server pack ids';\n        end", "        if type(mod.servers) ~= 'table' then return { id = id, label = mod.label, jobs = jobs, mod = mod }; end"),
    ('T01 slot 1 is the WHM producer', TR, "return (op % 8 == 1) and 'dnc status' or 'whm gauge'", "return 'whm gauge'"),
    ('G01 Job helper list ignored', FG, "    return type(approved) ~= 'table' or approved[id] == true;", "    return true;"),
]

SUITES = [['lua', 'tests/ascensionxi_dncstatus.lua'], ['lua', 'tests/run_tests.lua']]

def run():
    for cmd in SUITES:
        r = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
        if r.returncode != 0 or 'FAIL' in r.stdout:
            return False, cmd[1]
    return True, None

only = sys.argv[1:]
caught = missed = 0
for mid, path, old, new in M:
    if only and mid.split()[0] not in only:
        continue
    p = ROOT / path
    raw = p.read_bytes()
    crlf = b'\r\n' in raw
    text = raw.decode('utf-8')
    o, n = old, new
    if crlf:
        o, n = old.replace('\n', '\r\n'), new.replace('\n', '\r\n')
    if text.count(o) != 1:
        print(f'{mid}: PATTERN NOT FOUND ONCE ({text.count(o)})')
        missed += 1
        continue
    p.write_bytes(text.replace(o, n).encode('utf-8'))
    try:
        ok, where = run()
    finally:
        p.write_bytes(raw)
    if ok:
        print(f'{mid}: SURVIVED')
        missed += 1
    else:
        print(f'{mid}: caught by {where}')
        caught += 1
print(f'{caught} caught, {missed} survived or missing')
sys.exit(1 if missed else 0)
