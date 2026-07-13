#!/usr/bin/env python3
"""acc_calc.py -- "how much ACC do I need vs <mob>?" from CatsEyeXI server source.

Layer 1 of the ACC-calculator spec (docs: claude chat 2026-07-11; field research
2026-07-13, memory/mob-eva-pipeline.md). Downloads the public server repo files
once into tools/cexi_cache/, parses the DATA from source (mob tables, job
grades, zone lists, mod ids, settings -- nothing data-like is hardcoded), and
applies the FORMULAS transcribed from src with file:line provenance. Each
transcribed formula has a drift sentinel: if the source line it came from
disappears from the repo, the tool warns instead of silently lying.

Usage:
    python acc_calc.py "bull dhalmel"                        # find mob, show EVA/ACC targets
    python acc_calc.py "bull dhalmel" --level 22 --player-level 15
    python acc_calc.py dhalmel                               # list all matches
    python acc_calc.py "bull dhalmel" --acc 57               # expected hit rate at that ACC
    python acc_calc.py --dump mobs.json [--zone buburimu]    # spec deliverable: mobs.json
    python acc_calc.py --families families.csv               # EVA table: every family x jobs, Lv 1-99
    python acc_calc.py --luadata ..\accdata.lua              # dlac's shipped lookup table (catalog model)
    python acc_calc.py ... --refresh                         # force re-download of sources

Not modeled: per-spawn script mods (onMobSpawn setMod), private-module HVNMs
(absent from the public repo -- that is what the widescan/action-packet layer
is for), and mob food/buffs.
"""

import argparse
import json
import math
import re
import struct
import sys
import urllib.request
from pathlib import Path

REPO = "https://raw.githubusercontent.com/CatsAndBoats/catseyexi/base/"
CACHE = Path(__file__).resolve().parent / "cexi_cache"

FILES = [
    "sql/mob_groups.sql",
    "sql/mob_pools.sql",
    "sql/mob_family_system.sql",
    "sql/mob_pool_mods.sql",
    "sql/zone_settings.sql",
    "sql/skill_ranks.sql",
    "sql/mob_spawn_mods.sql",          # optional: 404 tolerated
    "src/map/utils/mobutils.cpp",
    "src/map/entities/battleentity.cpp",
    "src/map/grades.cpp",
    "src/map/modifier.h",
    "scripts/data/level_correction.lua",
    "scripts/globals/combat/physical_hit_rate.lua",
    "settings/default/map.lua",
]

JOBS = "NON WAR MNK WHM BLM RDM THF PLD DRK BST BRD RNG SAM NIN DRG SMN BLU COR PUP DNC SCH GEO RUN".split()

# ---------------------------------------------------------------------------
# f32 helper: the server does this math in C++ float; 4.7f et al. are NOT the
# doubles Python uses, and floor() sits right on the boundary at some levels.
# ---------------------------------------------------------------------------
def f32(x):
    return struct.unpack("f", struct.pack("f", x))[0]


def fetch(rel, refresh=False):
    dst = CACHE / rel.replace("/", "_")
    if dst.exists() and not refresh:
        return dst.read_text(encoding="utf-8", errors="replace")
    CACHE.mkdir(parents=True, exist_ok=True)
    try:
        with urllib.request.urlopen(REPO + rel, timeout=30) as r:
            data = r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            dst.write_text("", encoding="utf-8")  # cache the absence
            return ""
        raise
    dst.write_text(data, encoding="utf-8")
    return data


# ---------------------------------------------------------------------------
# SQL parsing: column names from CREATE TABLE, values from INSERT lines.
# ---------------------------------------------------------------------------
def sql_columns(text, table):
    m = re.search(r"CREATE TABLE (?:IF NOT EXISTS )?`%s` \((.*?)\n\)" % table, text, re.S)
    if not m:
        return []
    return re.findall(r"^\s*`(\w+)`", m.group(1), re.M)


def sql_rows(text, table):
    for m in re.finditer(r"^INSERT INTO `%s` VALUES \((.*)\);\s*$" % table, text, re.M):
        yield split_values(m.group(1))


def split_values(s):
    out, buf, i, in_q = [], [], 0, False
    while i < len(s):
        c = s[i]
        if in_q:
            if c == "\\" and i + 1 < len(s):
                buf.append(s[i + 1]); i += 2; continue
            if c == "'":
                if i + 1 < len(s) and s[i + 1] == "'":
                    buf.append("'"); i += 2; continue
                in_q = False
            else:
                buf.append(c)
        elif c == "'":
            in_q = True
        elif c == ",":
            out.append("".join(buf).strip()); buf = []
        else:
            buf.append(c)
        i += 1
    out.append("".join(buf).strip())
    return out


def norm_zone(name):
    return re.sub(r"[^A-Z0-9]+", "_", name.replace("'", "").upper()).strip("_")


def norm_mob(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


# ---------------------------------------------------------------------------
# Drift sentinels: literal source lines each transcribed formula came from.
# ---------------------------------------------------------------------------
SENTINELS = {
    "src/map/utils/mobutils.cpp": [
        "153 + (lvl - 50) * 5.0f",            # GetBaseDefEva >50 A       (mobutils.cpp:267)
        "5 + (lvl - 1) * 2.8f",               # GetBaseDefEva <=50 C      (mobutils.cpp:287)
        "(5 + ((lvl - 1) * 50) / 100); // A", # GetBaseToRank             (mobutils.cpp:309)
        "return 2; // B+, B, B-",             # JobSkillRankToBaseEvaRank (mobutils.cpp:1244)
        "JobSkillRankToBaseEvaRank(mJob, sJob)",  # EVA uses job ranks    (mobutils.cpp:913)
        "stat / (4.5f - 0.15f * (level - 26))",   # GetSubJobStats C      (mobutils.cpp:381)
    ],
    "src/map/entities/battleentity.cpp": [
        "evasion = m_modStat[Mod::EVA];",     # mobs: EVA mod is the base (battleentity.cpp:1490)
        "evasion += AGI() / 2;",              # +AGI/2 for everyone       (battleentity.cpp:1503)
    ],
    "scripts/globals/combat/physical_hit_rate.lua": [
        "local hitrate = (75 + hitdiff) / 100",   # base 75, /2 slope
        "utils.clamp(hitrate, 0.2, hitRateCap)",  # floor 20, cap 99/95
    ],
}


def check_sentinels(sources):
    warns = []
    for rel, needles in SENTINELS.items():
        for n in needles:
            if n not in sources[rel]:
                warns.append("DRIFT: %r no longer in %s -- re-verify the formula!" % (n, rel))
    return warns


# ---------------------------------------------------------------------------
# Formulas transcribed from source (see sentinel for provenance).
# ---------------------------------------------------------------------------
def get_base_def_eva(lvl, rank):
    # mobutils.cpp:254 GetBaseDefEva
    hi = {1: (153, 5.0), 2: (147, 4.9), 3: (142, 4.8), 4: (136, 4.7), 5: (126, 4.5)}
    lo = {1: (6, 3.0), 2: (5, 2.9), 3: (5, 2.8), 4: (4, 2.7), 5: (4, 2.5)}
    base, slope = (hi if lvl > 50 else lo)[rank]
    d = lvl - 50 if lvl > 50 else lvl - 1
    return math.floor(f32(base + f32(f32(d) * f32(slope))))


def get_base_to_rank(rank, lvl):
    # mobutils.cpp:304 GetBaseToRank (integer division, matches C++)
    tab = {1: (5, 50), 2: (4, 45), 3: (4, 40), 4: (3, 35), 5: (3, 30), 6: (2, 25), 7: (2, 20)}
    if rank not in tab:
        return 0
    base, slope = tab[rank]
    return base + ((lvl - 1) * slope) // 100


# GetSubJobStats (mobutils.cpp:332): per rank, list of (max_level, base, coeff,
# offset, floor_clamp) for divisor = base - coeff*(level-offset); clamp only <=30.
SUBJOB = {
    1: [(30, 4.0, 0.225, 30, 2), (40, 3.25, 0.073, 30, None), (46, 2.55, 0.001, 41, None), (999, 2.7, 0.001, 45, None)],
    2: [(30, 3.1, 0.075, 32, 2), (40, 3.1, 0.075, 32, None), (45, 2.5, 0.025, 40, None), (999, 2.35, 0.04, 44, None)],
    3: [(30, 4.5, 0.15, 26, 2), (40, 3.28, 0.001, 30, None), (45, 2.6, 0.025, 40, None), (999, 2.1, 0.2, 49, None)],
    4: [(30, 5.0, 0.05, 21, 1), (40, 3.2, 0.001, 29, None), (45, 3.5, 0.08, 32, None), (999, 3.25, 0.045, 32, None)],
    5: [(30, 3.8, 0.1, 32, 1), (40, 3.8, 0.15, 32, None), (45, 2.7, 0.075, 40, None), (999, 2.7, 0.05, 45, None)],
    6: [(30, 4.0, 0.15, 35, 1), (40, 4.0, 0.15, 30, None), (46, 3.0, 0.1125, 40, None), (999, 3.0, 0.07, 40, None)],
    7: [(30, 4.0, 0.15, 35, 1), (40, 4.0, 0.2, 31, None), (46, 2.5, 0.09, 40, None), (999, 2.5, None, None, None)],  # last: stat/2
}


def get_sub_job_stats(rank, level, stat):
    if rank not in SUBJOB:
        return stat // 2  # default branch (mobutils.cpp:473)
    for max_lvl, base, coeff, offset, clamp in SUBJOB[rank]:
        if level <= max_lvl:
            if coeff is None:  # rank G, level >46: stat / 2 (float floor)
                return math.floor(f32(stat / 2.0))
            div = f32(f32(base) - f32(f32(coeff) * f32(level - offset)))
            v = math.floor(f32(stat / div))
            return max(v, clamp) if clamp is not None else v
    return stat // 2


def eva_rank_from_jobs(mjob, sjob, eva_skill_ranks):
    # mobutils.cpp:1229 JobSkillRankToBaseEvaRank -- best (numeric min) of both
    r = min(eva_skill_ranks.get(mjob, 0), eva_skill_ranks.get(sjob, 0))
    if r in (1, 2):
        return 1
    if r in (3, 4, 5):
        return 2
    if r in (6, 7, 8):
        return 3
    if r == 9:
        return 4
    if r == 10:
        return 5
    return 3  # C++ fallback path (invalid/NON job)


# ---------------------------------------------------------------------------
# Load everything
# ---------------------------------------------------------------------------
class Db:
    pass


def load(refresh=False):
    src = {rel: fetch(rel, refresh) for rel in FILES}
    db = Db()
    db.warns = check_sentinels(src)

    t = src["sql/zone_settings.sql"]
    cols = sql_columns(t, "zone_settings")
    zid_i, name_i = cols.index("zoneid"), cols.index("name")
    db.zones = {int(r[zid_i]): r[name_i] for r in sql_rows(t, "zone_settings")}

    t = src["sql/mob_pools.sql"]
    cols = sql_columns(t, "mob_pools")
    ix = {c: cols.index(c) for c in ("poolid", "name", "familyid", "mJob", "sJob", "mobType")}
    db.pools = {int(r[ix["poolid"]]): dict(name=r[ix["name"]], family=int(r[ix["familyid"]]),
                                           mjob=int(r[ix["mJob"]]), sjob=int(r[ix["sJob"]]),
                                           mobtype=int(r[ix["mobType"]]))
                for r in sql_rows(t, "mob_pools")}

    t = src["sql/mob_family_system.sql"]
    cols = sql_columns(t, "mob_family_system")
    ix = {c: cols.index(c) for c in ("familyID", "family", "AGI")}
    db.families = {int(r[ix["familyID"]]): dict(name=r[ix["family"]], agi=int(r[ix["AGI"]]))
                   for r in sql_rows(t, "mob_family_system")}

    t = src["sql/mob_groups.sql"]
    cols = sql_columns(t, "mob_groups")
    ix = {c: cols.index(c) for c in ("poolid", "zoneid", "name", "minLevel", "maxLevel")}
    db.groups = [dict(pool=int(r[ix["poolid"]]), zone=int(r[ix["zoneid"]]), name=r[ix["name"]],
                      lo=int(r[ix["minLevel"]]), hi=int(r[ix["maxLevel"]]))
                 for r in sql_rows(t, "mob_groups")]

    # evasion skill rank per job (skill_ranks: one row per skill, job columns)
    t = src["sql/skill_ranks.sql"]
    cols = sql_columns(t, "skill_ranks")
    db.eva_skill_ranks = {}
    for r in sql_rows(t, "skill_ranks"):
        if r[cols.index("name")].lower() == "evasion":
            for j in range(1, 23):
                db.eva_skill_ranks[j] = int(r[cols.index(JOBS[j].lower())])
    if not db.eva_skill_ranks:
        db.warns.append("DRIFT: no 'evasion' row in skill_ranks.sql")

    # AGI grade per job from grades.cpp JobGrades (column 5 = AGI)
    m = re.search(r"JobGrades\s*=\s*\{\s*\{(.*?)\}\s*\};", src["src/map/grades.cpp"], re.S)
    db.job_agi_grade = {}
    if m:
        for j, row in enumerate(re.findall(r"\{([\d\s,]+)\}", m.group(1))):
            db.job_agi_grade[j] = int(row.split(",")[5])
    if len(db.job_agi_grade) < 23:
        db.warns.append("DRIFT: JobGrades parse got %d rows (want 23)" % len(db.job_agi_grade))

    # Mod::EVA numeric id from modifier.h -> flat EVA mods per pool
    m = re.search(r"^\s*EVA\s*=\s*(\d+)", src["src/map/modifier.h"], re.M)
    eva_mod_id = int(m.group(1)) if m else -1
    if eva_mod_id < 0:
        db.warns.append("DRIFT: Mod::EVA id not found in modifier.h")
    db.pool_eva_mod = {}
    t = src["sql/mob_pool_mods.sql"]
    cols = sql_columns(t, "mob_pool_mods")
    if cols:
        ix = {c: cols.index(c) for c in cols}
        for r in sql_rows(t, "mob_pool_mods"):
            if int(r[ix["modid"]]) == eva_mod_id and int(r[ix.get("is_mob_mod", 0)] or 0) == 0:
                pid = int(r[ix["poolid"]])
                db.pool_eva_mod[pid] = db.pool_eva_mod.get(pid, 0) + int(r[ix["value"]])

    # zone lists parsed FROM source: sub-job-stat zones + level-corrected zones
    m = re.search(r"bool CheckSubJobZone.*?\n\}", src["src/map/utils/mobutils.cpp"], re.S)
    db.subjob_zones = set(re.findall(r"ZONE_([A-Z0-9_]+)", m.group(0))) if m else set()
    db.corrected_zones = set(re.findall(r"xi\.zone\.([A-Z0-9_]+)", src["scripts/data/level_correction.lua"]))
    if not db.subjob_zones or not db.corrected_zones:
        db.warns.append("DRIFT: zone list parse came up empty")

    # level-correction sign for the PC-vs-higher-mob branch, detected from source.
    # 'acc - dlvl * 4' (dlvl = attacker - target < 0) => +4 ACC/level fighting up.
    # That IS the CatsEyeXI standard (Henrik ruling 2026-07-14; the code comment
    # saying "Penalty" is stale). Detection is kept as a drift ALARM only.
    lua = src["scripts/globals/combat/physical_hit_rate.lua"]
    m = re.search(r"attacker:isPC\(\) and attacker:getMainLvl\(\) < target:getMainLvl\(\).*?acc = acc ([+-]) dlvl \* 4", lua, re.S)
    db.pc_corr_sign = m.group(1) if m else None
    if db.pc_corr_sign is None:
        db.warns.append("DRIFT: PC level-correction branch not found in physical_hit_rate.lua")

    # stat multipliers from default settings (live server may override privately)
    def setting(name):
        m = re.search(r"%s\s*=\s*([\d.]+)" % name, src["settings/default/map.lua"])
        return float(m.group(1)) if m else 1.0
    db.mob_mult = setting("MOB_STAT_MULTIPLIER")
    db.nm_mult = setting("NM_STAT_MULTIPLIER")
    return db


# ---------------------------------------------------------------------------
# The actual computation
# ---------------------------------------------------------------------------
def eva_core(db, level, mjob, sjob, fam_agi, subjob_zone, flat=0, is_nm=False):
    rank = eva_rank_from_jobs(mjob, sjob, db.eva_skill_ranks)
    base = get_base_def_eva(level, rank) + flat
    fagi = get_base_to_rank(fam_agi, level)
    magi = get_base_to_rank(db.job_agi_grade.get(mjob, 0), level)
    sagi_full = get_base_to_rank(db.job_agi_grade.get(sjob, 0), level)
    if subjob_zone and level < 50:
        sagi = get_sub_job_stats(db.job_agi_grade.get(sjob, 0), level, sagi_full)
    else:
        sagi = sagi_full // 2
    agi = int((fagi + magi + sagi) * (db.nm_mult if is_nm else db.mob_mult))
    return dict(eva=base + agi // 2, base=base, agi=agi, rank="ABCDE"[rank - 1],
                fagi=fagi, magi=magi, sagi=sagi, is_nm=is_nm, subjob_zone=subjob_zone)


def mob_eva(db, level, pool_id, zone_id):
    p = db.pools[pool_id]
    fam = db.families.get(p["family"], {"name": "?", "agi": 0})  # familyid 0 = event/placeholder
    return eva_core(db, level, p["mjob"], p["sjob"], fam["agi"],
                    subjob_zone=norm_zone(db.zones.get(zone_id, "")) in db.subjob_zones,
                    flat=db.pool_eva_mod.get(pool_id, 0),
                    is_nm=bool(p["mobtype"] & 0x02))  # MOBTYPE_NOTORIOUS


def correction(db, zone_id, player_lvl, mob_lvl):
    """Returns (acc offset applied by the server, note). Positive = helps you."""
    if norm_zone(db.zones.get(zone_id, "")) not in db.corrected_zones:
        return 0, "zone not level-corrected"
    if player_lvl is None or player_lvl >= mob_lvl:
        return 0, "no correction (not below mob level)" if player_lvl else "give --player-level for correction"
    d = mob_lvl - player_lvl
    if db.pc_corr_sign == "-":
        # CatsEyeXI standard (Henrik ruling 2026-07-14): fighting up GRANTS 4 ACC/level.
        return 4 * d, "+%d ACC from level correction (you are %d below the mob)" % (4 * d, d)
    return -4 * d, "-%d ACC penalty -- UPSTREAM SIGN FLIPPED vs the 2026-07-14 ruling; re-verify tools!" % (4 * d)


def acc_report(db, g, level, player_lvl, acc):
    e = mob_eva(db, level, g["pool"], g["zone"])
    corr, corr_note = correction(db, g["zone"], player_lvl, level)
    lines = []
    lines.append("  Lv %d: EVA %d  (base %d rank %s%s + AGI %d/2 [f%d+m%d+s%d])%s" % (
        level, e["eva"], e["base"], e["rank"],
        "+mods" if db.pool_eva_mod.get(g["pool"]) else "",
        e["agi"], e["fagi"], e["magi"], e["sagi"], "  [NM]" if e["is_nm"] else ""))
    for label, cap in (("1H/H2H cap 99%", 99), ("2H/off/ranged cap 95%", 95)):
        need_eff = e["eva"] + 2 * (cap - 75)
        need = need_eff - corr
        extra = "" if corr == 0 else " -> %d with level corr" % need
        lines.append("    ACC to cap %-22s %d%s" % (label + ":", need_eff, extra))
    lines.append("    level corr: %s" % corr_note)
    lines.append("    /check flips: High Eva < %d | neutral %d-%d | Low Eva >= %d" % (
        e["eva"] - 30, e["eva"] - 30, e["eva"] + 9, e["eva"] + 10))
    if acc is not None:
        hr = 75 + (acc + corr - e["eva"]) / 2.0
        hr = max(20.0, min(99.0, hr))
        lines.append("    at ACC %d: ~%.1f%% hit rate (mainhand)" % (acc, hr))
    return "\n".join(lines)


def dump(db, path, zone_filter):
    out = {}
    for g in db.groups:
        zname = db.zones.get(g["zone"], "zone_%d" % g["zone"])
        if zone_filter and zone_filter not in zname.lower():
            continue
        p = db.pools.get(g["pool"])
        if not p:
            continue
        lo, hi = mob_eva(db, g["lo"], g["pool"], g["zone"]), mob_eva(db, g["hi"], g["pool"], g["zone"])
        key = "%s/%s" % (zname, g["name"])
        out.setdefault(key, []).append(dict(
            zone=zname, name=g["name"], min_level=g["lo"], max_level=g["hi"],
            family=db.families.get(p["family"], {"name": "?"})["name"], mjob=JOBS[p["mjob"]], sjob=JOBS[p["sjob"]],
            is_nm=lo["is_nm"], eva_min=lo["eva"], eva_max=hi["eva"],
            acc_cap_1h=[lo["eva"] + 48, hi["eva"] + 48], acc_cap_2h=[lo["eva"] + 40, hi["eva"] + 40],
            level_corrected_zone=norm_zone(zname) in db.corrected_zones))
    Path(path).write_text(json.dumps(out, indent=1, sort_keys=True), encoding="utf-8")
    print("wrote %d mobs -> %s" % (len(out), path))


def dump_families(db, path):
    """One row per (family, mJob/sJob) combo that actually occurs in mob_pools,
    with EVA at every level 1-99. Computed with the plain sub-job halving
    (non-original-zone rule); mobs in original/RoZ outdoor zones can differ by
    ~+-2 EVA below Lv50 -- use the per-mob query for exact numbers. ACC to cap:
    +48 for 1H/H2H (99%), +40 for 2H/offhand/ranged (95%). Flat pool EVA mods
    and NM multipliers are per-mob, not per-family, so they are not in here."""
    import csv
    combos = {}
    for p in db.pools.values():
        if p["family"] in db.families:
            combos[(p["family"], p["mjob"], p["sjob"])] = combos.get((p["family"], p["mjob"], p["sjob"]), 0) + 1
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["family", "agi_rank", "mjob", "sjob", "eva_rank", "pools"]
                   + ["L%d" % l for l in range(1, 100)])
        for (fid, mj, sj), n in sorted(combos.items(),
                                       key=lambda kv: (db.families[kv[0][0]]["name"], kv[0][1], kv[0][2])):
            fam = db.families[fid]
            evas = [eva_core(db, lvl, mj, sj, fam["agi"], subjob_zone=False) for lvl in range(1, 100)]
            w.writerow([fam["name"], "ABCDEFG"[fam["agi"] - 1] if 1 <= fam["agi"] <= 7 else fam["agi"],
                        JOBS[mj], JOBS[sj], evas[0]["rank"], n] + [e["eva"] for e in evas])
    print("wrote %d family/job rows x Lv1-99 -> %s" % (len(combos), path))


def dump_luadata(db, path):
    """dlac's shipped mob table (catalog model: generated here, ships with the
    addon, the addon never fetches). Keyed by zone id, then by squashed mob
    name (lowercase alphanumerics only -- matches accwatch.lua's squash()).
    Entry: { minLv, maxLv, evaAtMin, evaAtMax, isNM, "Family MJOB/SJOB" }.
    EVA endpoints are zone-exact (sub-job-stats rule applied per zone).
    Same-name groups in one zone merge to the widest range."""
    squash = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
    zones = {}
    for g in db.groups:
        p = db.pools.get(g["pool"])
        if not p:
            continue
        lo, hi = mob_eva(db, g["lo"], g["pool"], g["zone"]), mob_eva(db, g["hi"], g["pool"], g["zone"])
        fam = db.families.get(p["family"], {"name": "?"})["name"]
        desc = "%s %s/%s" % (fam, JOBS[p["mjob"]], JOBS[p["sjob"]])
        e = zones.setdefault(g["zone"], {}).get(squash(g["name"]))
        if e is None:
            zones[g["zone"]][squash(g["name"])] = [g["lo"], g["hi"], lo["eva"], hi["eva"],
                                                   1 if lo["is_nm"] else 0, desc]
        else:
            e[0], e[1] = min(e[0], g["lo"]), max(e[1], g["hi"])
            e[2], e[3] = min(e[2], lo["eva"]), max(e[3], hi["eva"])
            e[4] = max(e[4], 1 if lo["is_nm"] else 0)
    corr = sorted(z for z, n in db.zones.items() if norm_zone(n) in db.corrected_zones)
    n = 0
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- accdata.lua -- GENERATED by tools/acc_calc.py --luadata; do not hand-edit.\n")
        f.write("-- Source: github.com/CatsAndBoats/catseyexi@base. Regenerate after server updates.\n")
        f.write("-- zones[zoneid][squashedname] = { minLv, maxLv, evaAtMin, evaAtMax, isNM, 'Family MJOB/SJOB' }\n")
        f.write("return {\ncorrected = {\n")
        f.write("".join("[%d]=true," % z for z in corr) + "\n},\nzones = {\n")
        for zid in sorted(zones):
            f.write("[%d]={ -- %s\n" % (zid, db.zones.get(zid, "?")))
            for k in sorted(zones[zid]):
                e = zones[zid][k]
                f.write('["%s"]={%d,%d,%d,%d,%d,"%s"},\n' % (k, e[0], e[1], e[2], e[3], e[4], e[5].replace('"', "")))
                n += 1
            f.write("},\n")
        f.write("},\n};\n")
    print("wrote %d mobs in %d zones -> %s" % (n, len(zones), path))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mob", nargs="?", help="mob name (substring, case/space-insensitive)")
    ap.add_argument("--zone", help="zone name substring filter")
    ap.add_argument("--level", type=int, help="mob level (default: both ends of spawn range)")
    ap.add_argument("--player-level", type=int, help="your level, for zone level correction")
    ap.add_argument("--acc", type=int, help="your current ACC: show expected hit rate")
    ap.add_argument("--dump", metavar="PATH", help="write mobs.json (optionally with --zone)")
    ap.add_argument("--families", metavar="PATH", help="write family x jobs EVA table Lv1-99 (csv)")
    ap.add_argument("--luadata", metavar="PATH", help="write dlac's accdata.lua lookup table")
    ap.add_argument("--refresh", action="store_true", help="re-download server sources")
    a = ap.parse_args()

    db = load(a.refresh)
    for w in db.warns:
        print("WARNING: %s" % w, file=sys.stderr)

    if a.dump:
        dump(db, a.dump, a.zone.lower() if a.zone else None)
        return
    if a.families:
        dump_families(db, a.families)
        return
    if a.luadata:
        dump_luadata(db, a.luadata)
        return
    if not a.mob:
        ap.error("give a mob name, --dump, --families, or --luadata")

    q = norm_mob(a.mob)
    hits = [g for g in db.groups if q in norm_mob(g["name"])
            and (not a.zone or a.zone.lower() in db.zones.get(g["zone"], "").lower())]
    if not hits:
        print("no mob matching %r%s" % (a.mob, " in zone ~%r" % a.zone if a.zone else ""))
        return
    if len(hits) > 8 and not a.level:
        print("%d matches -- narrow with --zone:" % len(hits))
        for g in hits:
            print("  %-24s %-28s Lv %d-%d" % (g["name"], db.zones.get(g["zone"], "?"), g["lo"], g["hi"]))
        return

    for g in hits:
        p = db.pools[g["pool"]]
        print("%s  (%s)  Lv %d-%d  %s/%s  family %s" % (
            g["name"], db.zones.get(g["zone"], "zone %d" % g["zone"]), g["lo"], g["hi"],
            JOBS[p["mjob"]], JOBS[p["sjob"]], db.families.get(p["family"], {"name": "?"})["name"]))
        levels = [a.level] if a.level else sorted({g["lo"], g["hi"]})
        for lvl in levels:
            if not (g["lo"] <= lvl <= g["hi"]):
                print("  (note: Lv %d outside spawn range %d-%d)" % (lvl, g["lo"], g["hi"]))
            print(acc_report(db, g, lvl, a.player_level, a.acc))
        print()


if __name__ == "__main__":
    main()
