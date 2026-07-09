#!/usr/bin/env python3
"""
dlac apiscan -- pull CORRECT item stats/jobs from the CatsEyeXI live API and
reconcile them into gear.lua. Run this yourself whenever you add new gear; no
agent, no manual editing.

  python apiscan.py            # DRY RUN: show what would change (no writes)
  python apiscan.py --apply    # backup gear.lua, then apply the changes

How it works: for every `Id = N` in gear.lua it reads the item from
https://catseyexi.com/api/item/<N> (cached under tools/api_cache/, so a re-run
only fetches items you haven't seen). It then, per item:
  * sets Jobs + Level from the live server,
  * sets/corrects the base stats it manages (DEF, HP, MP, the 6 attributes,
    Accuracy/Attack/Ranged*/Magic*, Haste, Refresh, etc.),
  * REMOVES managed stats the live item doesn't have (retail pollution),
  * PRESERVES anything it doesn't manage -- special effects like
    Automaton={Refresh}, IronSkin, skills, resistances, and your comments.
Stats are the augment-free base (your personal augments stay out of gear.lua).

Typical flow for a NEW item: /fl scan -> /fl stage -> /fl commit (adds it with
its Id), then `python apiscan.py --apply`, then /fl r in game.

Deps: Python 3 only. (luaparser, if installed, adds an extra validation pass.)
The API rate-limits to ~30 requests/window, so the FIRST run over many uncached
items is slow (~1/sec); after that it's instant.
"""
import re, os, sys, json, time, shutil, urllib.request, urllib.error

HERE     = os.path.dirname(os.path.abspath(__file__))
FFXILAC  = os.path.dirname(HERE)                       # tools/ lives under dlac/
PROFILE  = os.path.dirname(FFXILAC)                    # ...<Name>_<Id>/
GEAR     = os.path.join(FFXILAC, 'gear.lua')
CACHE    = os.path.join(HERE, 'api_cache')
MODMAP   = os.path.join(HERE, 'modifier_map.lua')
BACKUPS  = os.path.join(PROFILE, 'backups')
API_URL  = 'https://catseyexi.com/api/item/%d'
APPLY    = '--apply' in sys.argv

os.makedirs(CACHE, exist_ok=True)

# --- modid -> ModName (from the bundled modifier map) -----------------------
_MOD = {}
if os.path.exists(MODMAP):
    for mid, nm in re.findall(r'\[(\d+)\]\s*=\s*"([^"]+)"', open(MODMAP, encoding='utf-8', errors='replace').read()):
        _MOD[int(mid)] = nm
def modname(mid): return _MOD.get(int(mid))

# ModName -> canonical gear.lua key. Only these are "managed" (set/removed from
# the API); every other stat on an entry is left exactly as you wrote it.
CORE = {'DEF':'DEF','HP':'HP','MP':'MP','HPP':'HPP','MPP':'MPP','STR':'STR','DEX':'DEX','VIT':'VIT','AGI':'AGI','INT':'INT','MND':'MND','CHR':'CHR',
'EVA':'Evasion','MEVA':'MagicEvasion','MDEF':'MagicDefenseBonus','ACC':'Accuracy','ATT':'Attack','RACC':'RangedAccuracy','RATT':'RangedAttack',
'MACC':'MagicAccuracy','MATT':'MagicAttackBonus','ENMITY':'Enmity','STORETP':'StoreTP','SUBTLE_BLOW':'SubtleBlow',
'DOUBLE_ATTACK':'DoubleAttack','TRIPLE_ATTACK':'TripleAttack','CRITHITRATE':'CriticalHitRate','REFRESH':'Refresh','REGEN':'Regen',
'FASTCAST':'FastCast','CURE_POTENCY':'CurePotency','CONSERVE_MP':'ConserveMP','COUNTER':'Counter','DUAL_WIELD':'DualWield',
'MPHEAL':'HMP','HPHEAL':'HHP','MOVE_SPEED_GEAR_BONUS':'MovementSpeed'}
MANAGED = set(CORE.values()) | {'Haste'}
ORDER = ['DEF','HP','HPP','MP','MPP','STR','DEX','VIT','AGI','INT','MND','CHR','Accuracy','Attack','RangedAccuracy','RangedAttack','MagicAccuracy','MagicAttackBonus','Evasion','MagicEvasion','MagicDefenseBonus','Haste','StoreTP','Enmity','SubtleBlow','DoubleAttack','TripleAttack','CriticalHitRate','Refresh','Regen','FastCast','CurePotency','ConserveMP','Counter','DualWield','HMP','HHP','MovementSpeed']
OI = {k: i for i, k in enumerate(ORDER)}
JOB0 = ['WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN']

# --- fetch (rate-limit aware, cached, resumable) ----------------------------
def fetch(iid):
    p = os.path.join(CACHE, '%d.json' % iid)
    if os.path.exists(p):
        return True
    req = urllib.request.Request(API_URL % iid, headers={'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json'})
    for _ in range(4):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                data = r.read(); json.loads(data)
                open(p, 'wb').write(data); time.sleep(1.1); return True
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(min(int(e.headers.get('Retry-After', '5')) + 1, 30)); continue
            if e.code == 404: return False
            time.sleep(3)
        except Exception:
            time.sleep(3)
    return False

def api_entry(iid):
    p = os.path.join(CACHE, '%d.json' % iid)
    if not os.path.exists(p): return None
    try: d = json.load(open(p, encoding='utf-8'))
    except Exception: return None
    it = d.get('item') or {}
    core = {}
    for m in (d.get('mods') or []):
        nm = modname(int(m['modid']))
        if nm is None: continue
        v = float(m['value'])
        if nm == 'HASTE_GEAR': core['Haste'] = float(round(v / 100.0))
        elif nm in CORE: core[CORE[nm]] = v
    mask = int(it.get('jobs', 0) or 0)
    js = [JOB0[b] for b in range(22) if mask & (1 << b)]
    jobs = '{"All"}' if (len(js) >= 22 or not js) else ('{' + ', '.join('"%s"' % j for j in js) + '}')
    lvl = it.get('level')
    return {'core': core, 'jobs': jobs, 'level': int(lvl) if lvl is not None else None}

def fmt(v): return str(int(v)) if float(v) == int(v) else ('%g' % v)

# --- parse gear.lua ---------------------------------------------------------
raw = open(GEAR, encoding='latin-1', newline='').read(); crlf = '\r\n' in raw; CR = '\r' if crlf else ''
lines = raw.split('\n')
def stg(l): return l.rstrip('\r')
WEAPON = {'Main', 'Range'}
ids = sorted(set(int(x) for x in re.findall(r'^\s+Id = (\d+)', raw, re.M)))

print('gear.lua items with an Id: %d' % len(ids))
missing = [i for i in ids if not os.path.exists(os.path.join(CACHE, '%d.json' % i))]
if missing:
    print('fetching %d item(s) not yet cached from the API (rate-limited ~1/sec)...' % len(missing))
    for n, i in enumerate(missing, 1):
        fetch(i)
        if n % 20 == 0: print('  %d/%d' % (n, len(missing)))
    print('  done.')

ents = []; curSlot = curCat = None; i = 0; N = len(lines)
while i < N:
    ln = stg(lines[i])
    m4 = re.match(r'^    ([A-Za-z0-9_]+) = \{$', ln); m8 = re.match(r'^        ([A-Za-z0-9_]+) = \{$', ln); m12 = re.match(r'^            ([A-Za-z0-9_]+) = \{$', ln)
    if m4: curSlot = m4.group(1); curCat = None; i += 1; continue
    if ln == '    },': curSlot = curCat = None; i += 1; continue
    if m8 and curSlot in WEAPON: curCat = m8.group(1); i += 1; continue
    if ln == '        },' and curSlot in WEAPON: curCat = None; i += 1; continue
    if m8 and curSlot: key, ind = m8.group(1), 8
    elif m12 and curSlot and curCat: key, ind = m12.group(1), 12
    else: i += 1; continue
    j = i + 1; cre = re.compile(r'^ {%d}\},$' % ind)
    eid = id_line = name_line = jobs_line = lvl_line = lvl_val = sclose = None
    jobs_multi = False; live = {}
    while j < N and not cre.match(stg(lines[j])):
        s = stg(lines[j])
        mid = re.match(r'^ {%d}Id = (\d+),' % (ind + 4), s)
        if mid: eid = int(mid.group(1)); id_line = j
        if re.match(r'^ {%d}Name = ' % (ind + 4), s) and name_line is None: name_line = j
        ml = re.match(r'^ {%d}Level = (-?\d+),' % (ind + 4), s)
        if ml: lvl_line = j; lvl_val = int(ml.group(1))
        jm = re.match(r'^ {%d}Jobs = ' % (ind + 4), s)
        if jm:
            jobs_line = j
            if not re.match(r'^\s*Jobs = \{[^}]*\},?\s*$', s): jobs_multi = True
        if re.match(r'^ {%d}Stats = \{$' % (ind + 4), s):
            k = j + 1; sc = re.compile(r'^ {%d}\},?$' % (ind + 4))
            while k < N and not sc.match(stg(lines[k])):
                mk = re.match(r'^ {%d}([A-Za-z0-9_]+) = (-?[0-9.]+),?\s*(--.*)?$' % (ind + 8), stg(lines[k]))
                if mk: live[mk.group(1)] = (k, float(mk.group(2)))
                k += 1
            sclose = k; j = k
        j += 1
    ents.append(dict(key=key, ind=ind, id=eid, id_line=id_line, name_line=name_line, jobs_line=jobs_line,
                     jobs_multi=jobs_multi, lvl_line=lvl_line, lvl_val=lvl_val, sclose=sclose, live=live))
    i = j + 1

# --- reconcile --------------------------------------------------------------
repl = {}; delete = set(); ins = {}; commafix = set()
n_jobs = n_lvl = n_set = n_add = n_rm = n_ent = 0
def mark_comma_before(P):
    x = P - 1
    while x >= 0:
        s = stg(lines[x]).strip()
        if s == '' or s.startswith('--'): x -= 1; continue
        if s.endswith('{'): return
        commafix.add(x); return
for e in ents:
    if e['id'] is None: continue
    a = api_entry(e['id'])
    if a is None: continue
    touched = False
    if a['jobs'] is not None:
        newj = ' ' * (e['ind'] + 4) + 'Jobs = ' + a['jobs'] + ',' + CR
        if e['jobs_line'] is not None and not e['jobs_multi']:
            if stg(lines[e['jobs_line']]).strip() != ('Jobs = ' + a['jobs'] + ','):
                repl[e['jobs_line']] = newj; n_jobs += 1; touched = True
        elif e['jobs_line'] is None:
            anch = e['id_line'] if e['id_line'] is not None else e['name_line']
            if anch is not None: ins.setdefault(anch, []).append(newj); n_jobs += 1; touched = True
    if a['level'] is not None and e['lvl_line'] is not None and e['lvl_val'] != a['level']:
        repl[e['lvl_line']] = ' ' * (e['ind'] + 4) + 'Level = %d,' % a['level'] + CR; n_lvl += 1; touched = True
    core = a['core']; add = []
    for K, (li, old) in e['live'].items():
        if K in MANAGED:
            if K in core:
                if abs(core[K] - old) > 0.001:
                    repl[li] = re.sub(r'^(\s*[A-Za-z0-9_]+ = )(-?[0-9.]+)(,?)', lambda m: m.group(1) + fmt(core[K]) + m.group(3), lines[li], count=1); n_set += 1; touched = True
            else:
                delete.add(li); n_rm += 1; touched = True
    for K, v in core.items():
        if K not in e['live']: add.append((K, v)); n_add += 1; touched = True
    if add and e['sclose'] is not None:
        add.sort(key=lambda kv: OI.get(kv[0], 999))
        ins.setdefault(e['sclose'], []).extend(' ' * (e['ind'] + 8) + '%s = %s,' % (k, fmt(v)) + CR for k, v in add)
        mark_comma_before(e['sclose'])
    if touched: n_ent += 1

out = []
for idx, l in enumerate(lines):
    if idx in ins: out.extend(ins[idx])
    if idx in delete: continue
    line = l
    if idx in repl: line = repl[idx]
    if idx in commafix and idx not in delete:
        cr = '\r' if line.endswith('\r') else ''; body = line[:-1] if cr else line
        ci = body.find(' --'); code, cmt = (body[:ci], body[ci:]) if ci >= 0 else (body, '')
        code = code.rstrip()
        if not (code.endswith(',') or code.endswith('{')): line = code + ',' + cmt + cr
    out.append(line)
newtext = '\n'.join(out)

print('\n%s: %d jobs, %d levels, %d stats corrected, %d added, %d removed  (%d entries changed)'
      % ('WOULD CHANGE' if not APPLY else 'CHANGING', n_jobs, n_lvl, n_set, n_add, n_rm, n_ent))

# validate: luaparser if available, else brace balance
ok = True
try:
    from luaparser import ast as _ast; _ast.parse(newtext)
    print('validated with luaparser: OK')
except ImportError:
    if newtext.count('{') != newtext.count('}'):
        ok = False; print('!! brace mismatch -- refusing to write. (install luaparser for a stronger check.)')
    else:
        print('basic brace check: OK (install luaparser for a full syntax check)')
except Exception as ex:
    ok = False; print('!! syntax check FAILED, refusing to write: %s' % str(ex)[:120])

if not APPLY:
    print('\nDry run. Re-run with  --apply  to back up gear.lua and write these changes, then /fl r in game.')
elif not ok:
    print('\nNOT applied (validation failed).')
elif n_ent == 0:
    print('\nNothing to change -- gear.lua already matches the live API.')
else:
    os.makedirs(BACKUPS, exist_ok=True)
    # rotate: keep newest 20 apiscan backups
    baks = sorted(f for f in os.listdir(BACKUPS) if f.startswith('gear_pre-apiscan_'))
    for old in baks[:-19]:
        try: os.remove(os.path.join(BACKUPS, old))
        except OSError: pass
    from time import strftime, localtime
    bpath = os.path.join(BACKUPS, 'gear_pre-apiscan_%s.lua' % strftime('%Y%m%d_%H%M%S', localtime()))
    shutil.copy(GEAR, bpath)
    open(GEAR, 'w', encoding='latin-1', newline='').write(newtext)
    print('\nApplied. Backup: %s\nRun  /fl r  in game to load.' % bpath)
