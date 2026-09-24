"""Print DLAC's Void Storage data from a pinned AXI membership manifest.

Usage: python scripts/export_void_storage.py C:/repos/ascensionxi [git-ref]
Review the output and update servers/ascensionxi/data/voidstorage.lua.
The server's generated manifest includes category seeds AND exceptions.
"""
import json
import re
import subprocess
import sys


def generate(repo, ref="origin/main"):
    def git(*args):
        return subprocess.check_output(["git", "-C", repo, *args], text=True, encoding="utf-8")

    sha = git("rev-parse", ref).strip()
    manifest = git("show", f"{sha}:documentation/custom/void-storage-membership.manifest")
    tiers = git("show", f"{sha}:modules/custom/lua/void_storage_data/tiers.lua")
    key_ids = dict(re.findall(r"xi.keyItem\.(VOID_TIER_\w+)\s*=\s*(\d+)", tiers))
    tier_info = {}
    for name, wire, ki, label in re.findall(
        r"(\w+)\s*=\s*\{\s*wireTier\s*=\s*(\d+),\s*keyItem\s*=\s*(nil|xi\.keyItem\.\w+),\s*label\s*=\s*'([^']+)'", tiers
    ):
        tier_info[name] = (int(wire), None if ki == "nil" else int(key_ids[ki.split(".")[-1]]), label)
    groups, seen = {}, set()
    for line in manifest.splitlines():
        if not re.match(r"^\d+\t", line):
            continue
        item, _, tier, *_ = line.split("\t")
        item = int(item)
        assert item not in seen and 0 < item <= 32767
        seen.add(item)
        wire, _, _ = tier_info[tier]
        groups.setdefault(wire, []).append(item)
    assert len(seen) == int(re.search(r"^@total (\d+)$", manifest, re.M)[1])
    lines = ["-- Generated from AXI's audited membership manifest; includes category exceptions.",
             "-- Regenerate: python scripts/export_void_storage.py <axi-checkout> <git-ref>",
             "return {", f"    source = {json.dumps(sha)},", "    tiers = {"]
    for wire, ki, label in sorted(set(tier_info.values())):
        if wire == 0:
            continue
        lines.append(f"        [{wire}] = {{ keyItem = {ki}, label = {json.dumps(label)} }},")
    lines.extend(["    },", "    itemsByTier = {"])
    for wire, ids in sorted(groups.items()):
        lines.append(f"        [{wire}] = {{")
        ids.sort()
        for start in range(0, len(ids), 16):
            lines.append("            " + ", ".join(map(str, ids[start:start + 16])) + ",")
        lines.append("        },")
    lines.extend(["    },", "};", ""])
    return "\n".join(lines)


if __name__ == "__main__":
    print(generate(*sys.argv[1:]), end="")
