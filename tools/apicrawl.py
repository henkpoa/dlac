#!/usr/bin/env python3
"""
dlac apicrawl -- crawl the CatsEyeXI live API to build the FULL equipment
catalog (catalog.lua), which powers the GUI's "All Equipment" tab. Everything
comes from the API by item id: display name, level, jobs, slot, stats, dmg/delay.

It is RESUMABLE and RATE-LIMITED, so you populate slowly but surely: run it,
stop it whenever (Ctrl+C), run it again -- it only fetches ids it hasn't cached,
then rebuilds catalog.lua from everything cached so far. No agent, no tokens.

  python apicrawl.py                  # crawl ids 1..32000 (skips cached), rebuild catalog
  python apicrawl.py --from 27000 --to 29500
  python apicrawl.py --max 500        # fetch at most 500 new ids this run, then rebuild
  python apicrawl.py --build-only     # don't fetch; just rebuild catalog.lua from the cache

The API allows ~30 requests/window, so fetching new ids runs ~1/sec. A full
1..32000 sweep is a few hours total -- do it in chunks with --max or --from/--to,
or just leave it running. Non-equipment (consumables etc.) is skipped.
Deps: Python 3 only.
"""
import re, os, sys, json, time, urllib.request, urllib.error

HERE    = os.path.dirname(os.path.abspath(__file__))
FFXILAC = os.path.dirname(HERE)
CATALOG = os.path.join(FFXILAC, 'catalog.lua')
CACHE   = os.path.join(HERE, 'api_cache')
MODMAP  = os.path.join(HERE, 'modifier_map.lua')
API_URL = 'https://catseyexi.com/api/item/%d'
os.makedirs(CACHE, exist_ok=True)

def arg(flag, default):
    return int(sys.argv[sys.argv.index(flag) + 1]) if flag in sys.argv else default
FRM = arg('--from', 1); TO = arg('--to', 32000); MAX = arg('--max', 10 ** 9)
BUILD_ONLY = '--build-only' in sys.argv

_MOD = {}
if os.path.exists(MODMAP):
    for mid, nm in re.findall(r'\[(\d+)\]\s*=\s*"([^"]+)"', open(MODMAP, encoding='utf-8', errors='replace').read()):
        _MOD[int(mid)] = nm
CORE = {'DEF':'DEF','HP':'HP','MP':'MP','HPP':'HPP','MPP':'MPP','STR':'STR','DEX':'DEX','VIT':'VIT','AGI':'AGI','INT':'INT','MND':'MND','CHR':'CHR',
'EVA':'Evasion','MEVA':'MagicEvasion','MDEF':'MagicDefenseBonus','ACC':'Accuracy','ATT':'Attack','RACC':'RangedAccuracy','RATT':'RangedAttack',
'MACC':'MagicAccuracy','MATT':'MagicAttackBonus','ENMITY':'Enmity','STORETP':'StoreTP','SUBTLE_BLOW':'SubtleBlow',
'DOUBLE_ATTACK':'DoubleAttack','TRIPLE_ATTACK':'TripleAttack','CRITHITRATE':'CriticalHitRate','REFRESH':'Refresh','REGEN':'Regen',
'FASTCAST':'FastCast','CURE_POTENCY':'CurePotency','CONSERVE_MP':'ConserveMP','COUNTER':'Counter','DUAL_WIELD':'DualWield',
'MPHEAL':'HMP','HPHEAL':'HHP','MOVE_SPEED_GEAR_BONUS':'MovementSpeed','SPELLINTERRUPT':'SpellInterruptionRateDown'}
SORD = ['DMG','Delay','DEF','HP','HPP','MP','MPP','STR','DEX','VIT','AGI','INT','MND','CHR','Accuracy','Attack','RangedAccuracy','RangedAttack','MagicAccuracy','MagicAttackBonus','Evasion','MagicEvasion','MagicDefenseBonus','Haste','StoreTP','Enmity','SubtleBlow','DoubleAttack','TripleAttack','CriticalHitRate','Refresh','Regen','FastCast','SpellInterruptionRateDown','CurePotency','ConserveMP','Counter','DualWield','HMP','HHP','MovementSpeed']
SI = {k: i for i, k in enumerate(SORD)}
JOB0 = ['WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN']
SLOT_BITS = [(0x1,'Main'),(0x2,'Sub'),(0x4,'Range'),(0x8,'Ammo'),(0x10,'Head'),(0x20,'Body'),(0x40,'Hands'),(0x80,'Legs'),(0x100,'Feet'),(0x200,'Neck'),(0x400,'Waist'),(0x800,'Ear'),(0x1000,'Ear'),(0x2000,'Ring'),(0x4000,'Ring'),(0x8000,'Back')]
SKILL_CAT = {1:'HandToHand',2:'Dagger',3:'Sword',4:'GreatSword',5:'Axe',6:'GreatAxe',7:'Scythe',8:'Polearm',9:'Katana',10:'GreatKatana',11:'Club',12:'Staff',25:'Archery',26:'Marksmanship',27:'Throwing',41:'StringInstrument',42:'WindInstrument',45:'Handbell',48:'FishingRod'}
ONE = {'Sword','Dagger','Axe','Club','Katana','HandToHand'}
SLOT_ORDER = ['Main','Sub','Range','Ammo','Head','Neck','Ear','Body','Hands','Ring','Back','Waist','Legs','Feet']
CAT_ORDER = ['HandToHand','Dagger','Sword','GreatSword','Axe','GreatAxe','Scythe','Polearm','Katana','GreatKatana','Club','Staff','Archery','Marksmanship','Throwing','StringInstrument','WindInstrument','Handbell','FishingRod']

def slot_name(mask):
    for bit, nm in SLOT_BITS:
        if int(mask or 0) & bit: return nm
    return None
def fmt(v): return str(int(v)) if float(v) == int(v) else ('%g' % v)
def esc(s): return s.replace('\\', '\\\\').replace('"', '\\"')
def makeKey(name):
    s = name.replace("'", "").replace(chr(0x2019), ""); suf = ''
    m = re.search(r'([+-])(\d+)\b', s)
    if m: suf = '_' + m.group(2); s = re.sub(r'[+-]\d+', '', s)
    return ''.join(w[0].upper() + w[1:] for w in re.findall(r'[A-Za-z0-9]+', s)) + suf

def cache_path(iid): return os.path.join(CACHE, '%d.json' % iid)
def fetch(iid):
    p = cache_path(iid)
    if os.path.exists(p): return 'cached'
    req = urllib.request.Request(API_URL % iid, headers={'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json'})
    for _ in range(4):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                data = r.read(); json.loads(data)
                open(p, 'wb').write(data); time.sleep(1.05); return 'ok'
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(min(int(e.headers.get('Retry-After', '5')) + 1, 30)); continue
            if e.code == 404:
                open(p, 'w', encoding='utf-8').write('{"notfound":true}'); return '404'
            time.sleep(2)
        except Exception:
            time.sleep(2)
    return 'fail'

# ---- crawl ----
# Which ids to sync: the bundled equipment_ids.txt (every equipment id from the
# server's item_equipment table) -- so we only hit the API for real gear. Pass
# --range to sweep FRM..TO by brute force instead.
IDFILE = os.path.join(HERE, 'equipment_ids.txt')
if os.path.exists(IDFILE) and '--range' not in sys.argv:
    allids = [i for i in (int(x) for x in open(IDFILE).read().split() if x.strip()) if FRM <= i <= TO]
    src = '%d equipment ids (equipment_ids.txt)' % len(allids)
else:
    allids = list(range(FRM, TO + 1)); src = 'brute-force range %d..%d' % (FRM, TO)

if not BUILD_ONLY:
    remaining = [i for i in allids if not os.path.exists(cache_path(i))]
    todo = remaining[:MAX]
    print('sync source: %s | %d still uncached | fetching up to %d this run (~1/sec, Ctrl+C ok -- resumable)'
          % (src, len(remaining), len(todo)))
    got = 0
    for n, iid in enumerate(todo, 1):
        r = fetch(iid)
        if r == 'ok': got += 1
        if n % 50 == 0: print('  %d/%d this run (%d new items)' % (n, len(todo), got))
    print('  fetched %d new this run; %d equipment ids still to go (re-run to continue).' % (got, len(remaining) - len(todo)))

# ---- build catalog.lua from all cached equippable items ----
print('building catalog.lua from cache...')
tree = {}; usedkeys = {}; total = 0; scanned = 0
def add(slot, cat, key, iid, rec):
    ns = (slot, cat); usedkeys.setdefault(ns, {}); base = key; n = 2
    while key in usedkeys[ns]: key = '%s_%d' % (base, n); n += 1
    usedkeys[ns][key] = True
    tree.setdefault(slot, {}).setdefault(cat, []).append((key, iid, rec))

for f in os.listdir(CACHE):
    if not f.endswith('.json'): continue
    try: d = json.load(open(os.path.join(CACHE, f), encoding='utf-8'))
    except Exception: continue
    if d.get('notfound'): continue
    it = d.get('item')
    if not it: continue
    scanned += 1
    slot = slot_name(it.get('slot'))
    if slot is None: continue                      # not equippable -> skip
    name = it.get('name')
    if not name: continue
    w = d.get('weapon') if isinstance(d.get('weapon'), dict) else None
    cat = None
    if slot in ('Main', 'Range') and w: cat = SKILL_CAT.get(int(w.get('skill') or 0))
    if slot == 'Ammo': cat = None
    core = {}
    for m in (d.get('mods') or []):
        nm = _MOD.get(int(m['modid']))
        if nm is None: continue
        v = float(m['value'])
        if nm == 'HASTE_GEAR': core['Haste'] = round(v / 100.0)
        elif nm in CORE: core[CORE[nm]] = int(v) if v == int(v) else v
    mask = int(it.get('jobs', 0) or 0)
    js = [JOB0[b] for b in range(22) if mask & (1 << b)]
    jobs = '{"All"}' if (len(js) >= 22 or not js) else ('{' + ', '.join('"%s"' % j for j in js) + '}')
    rec = {'name': name, 'slot': slot, 'cat': cat, 'level': it.get('level') or 0, 'jobs': jobs, 'core': core,
           'dmg': (w.get('dmg') if w else None), 'delay': (w.get('delay') if w else None)}
    add(slot, cat if slot in ('Main', 'Range') else None, makeKey(name), int(it.get('itemid') or it.get('itemId')), rec)
    total += 1

def render(key, iid, rec, ind):
    p = ' ' * ind; q = ' ' * (ind + 4); r = ' ' * (ind + 8)
    ktok = key if re.match(r'^[A-Za-z_]\w*$', key) else '["%s"]' % key   # quote keys that aren't valid Lua identifiers (e.g. digit-leading)
    L = ['%s%s = {' % (p, ktok), '%sName = "%s",' % (q, esc(rec['name'])), '%sLevel = %d,' % (q, int(rec['level'])),
         '%sId = %d,' % (q, iid), '%sJobs = %s,' % (q, rec['jobs'])]
    slot, cat = rec['slot'], rec['cat']
    if slot == 'Main' and cat: L.append('%sOneHanded = %s,' % (q, 'true' if cat in ONE else 'false')); L.append('%sType = "%s",' % (q, cat))
    elif slot == 'Range' and cat: L.append('%sType = "%s",' % (q, cat))
    elif slot == 'Ammo': L.append('%sType = "Ammo",' % q)
    else: L.append('%sType = "%s",' % (q, slot))
    st = {}
    if rec['dmg'] and float(rec['dmg']) > 0: st['DMG'] = int(rec['dmg'])
    if rec['delay'] and float(rec['delay']) > 0: st['Delay'] = int(rec['delay'])
    st.update(rec['core'])
    L.append('%sStats = {' % q)
    for sk in sorted(st, key=lambda x: SI.get(x, 999)): L.append('%s%s = %s,' % (r, sk, fmt(st[sk])))
    L.append('%s}' % q); L.append('%s},' % p)
    return L

CR = '\r\n'
out = ['-- catalog.lua -- full CatsEyeXI equipment reference (crawled from the live API).',
       '-- Rebuild/extend with: python tools/apicrawl.py', 'return {']
for slot in SLOT_ORDER:
    if slot not in tree: continue
    out.append('    %s = {' % slot)
    cats = tree[slot]
    if slot in ('Main', 'Range'):
        for cat in sorted([c for c in cats if c is not None], key=lambda c: CAT_ORDER.index(c) if c in CAT_ORDER else 99):
            out.append('        %s = {' % cat)
            for key, iid, rec in sorted(cats[cat], key=lambda x: x[0]): out.extend(render(key, iid, rec, 12))
            out.append('        },')
    else:
        for key, iid, rec in sorted(cats.get(None, []), key=lambda x: x[0]): out.extend(render(key, iid, rec, 8))
    out.append('    },')
out.append('}')
text = CR.join(out) + CR
if text.count('{') != text.count('}'):
    print('!! brace mismatch, not writing'); sys.exit(1)
open(CATALOG, 'w', encoding='latin-1', newline='').write(text)
cached_total = len([f for f in os.listdir(CACHE) if f.endswith('.json')])
print('cache: %d ids seen | equippable items in catalog: %d | wrote catalog.lua (%d bytes)' % (cached_total, total, len(text)))
print('Re-run to fetch more (it resumes). When done, /fl r in game to load the bigger catalog.')
