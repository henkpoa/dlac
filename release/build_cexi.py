"""Build the public CatsEyeXI distribution from a committed shared-code revision.

No working-tree files, private branches, config, or maintainer tools are packaged.
The projection deliberately fails when a source boundary changes: review the
public feature exclusions before adapting it to a new source layout.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIRS = {"assets", "feature", "gear", "jobhelpers", "lib", "ui"}
ROOT_FILES = {
    "chatfmt.lua", "dispatch.lua", "dlac.lua", "gear.lua", "profiles.lua",
    "utils.lua", "LICENSE",
}
OMIT = {
    "feature/synthrun.lua",
    "servers/cexi/modules/ebox/restockui.lua",
    "servers/cexi/modules/ebox/restockwatch.lua",
    "servers/cexi/modules/ebox/eboxtrace.lua",
}
PRIVATE_NAMES = {"accwatch.lua", "accdata.lua", "gearmove.lua"}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"CEXI release boundary changed: {old[:100]!r}")
    return source.replace(old, new, 1)


def replace_between(source, start, end, replacement=""):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError(f"CEXI release boundaries changed: {start!r} / {end!r}")
    a, b = source.index(start), source.index(end)
    if b <= a:
        raise ValueError("CEXI release boundaries out of order")
    return source[:a] + replacement + source[b:]


def public_craftbar(source):
    source = replace_between(source, "--[[", "local M = {};",
        "-- Public CEXI craft bar: equipment, goals, skills and passive recipe display.\n\n")
    source = replace_between(source, "-- Repeat-synth row.", "-- Craft glyph textures")
    source = replace_between(source, "    -- Wait-timer buffer.", "    -- Row 1, centered:")
    source = replace_between(source, "    -- Row 2, centered:", "    local ls =",
        "    -- Crafting goals; the player starts synthesis through the game.\n")
    source = replace_between(source, "    -- Last Synth is MEASURED,", "    local goal =",
        "    centerNext(availW, goalW + 6 + 62 + 4 + 62 + 4 + 86);\n")
    source = replace_between(source, "    imgui.SameLine(0, 12);\n    -- Last Synth / Stop,",
        "        imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Last synth:');",
        "    -- Passive observation of the player's most recent synthesis.\n    do\n")
    for forbidden in ("/lastsynth", "synthrun", "##cblast", "##cbrep", "##cbwait", "QueueCommand"):
        if forbidden in source:
            raise ValueError(f"Craft action survived CEXI projection: {forbidden}")
    return source


# Keep the old import path so Giftbox and an older modules.lua override remain
# safe. This replacement contains no storage protocol or event registration.
PROXIMITY = """-- Public CEXI: passive E-Box proximity for Giftbox only.
local M = {};
local ok, ew = pcall(require, 'dlac\\\\lib\\\\entwatch');
function M.boxDistance()
    if not ok or type(ew) ~= 'table' then return nil; end
    ew.watch('eboxclient', 'Ephemeral Box');
    return (ew.nearest('Ephemeral Box'));
end
function M.nearBox()
    local distance = M.boxDistance();
    return distance ~= nil and distance <= 5;
end
return M;
"""

README = """# DLAC for CatsEyeXI

This public CEXI package includes only the CatsEyeXI server pack. Crafting gear,
craft goals, skill information and passive last-recipe information remain.
E-Box Restock, Last Synth action buttons (including repeats), auto-acc and storage
move are not included. Giftbox retains passive Ephemeral Box proximity detection.

## Install or update

1. Unload DLAC in Ashita: `/addon unload dlac`.
2. For an existing installation, back up and replace the entire `addons/dlac`
   folder. Do not extract over an older folder: that leaves removed modules behind.
3. Extract this ZIP into `Ashita/addons`, producing `addons/dlac/dlac.lua`.
4. Leave `config/addons/dlac` and `config/addons/luashitacast` untouched; those
   contain your character settings and profiles.
5. Load DLAC: `/addon load dlac`.

Download the named CEXI ZIP, not GitHub's automatic source-code archive, which
contains the shared multi-server source. RELEASE.json records the source commit
and hashes of every packaged file. This package selects CatsEyeXI automatically.
"""


def project(files):
    # Refuse private inputs outright, even though the allowlist would omit some.
    private = [p for p in files if Path(p).name in PRIVATE_NAMES]
    if private:
        raise ValueError(f"Refusing to package private feature source: {private}")
    out = {
        p: data for p, data in files.items()
        if p not in OMIT and (p in ROOT_FILES or
            p.split('/')[0] in RUNTIME_DIRS or
            (p.startswith('servers/cexi/') and p.endswith('.lua')))
    }

    def edit(path, fn):
        out[path] = fn(out[path].decode('utf-8').replace('\r\n', '\n')).encode('utf-8')

    edit('ui/craftbar.lua', public_craftbar)
    edit('dlac.lua', lambda s: replace_once(s, "                       'feature\\\\synthrun',\n", ''))
    edit('servers/cexi/manifest.lua', lambda s: replace_once(replace_once(
        replace_once(s, "        ebox      = true,   -- Ephemeral Box store (Crystal Warriors)\n", ''),
        "modules = { 'gamemode', 'prestige', 'ebox', 'giftbox' }",
        "modules = { 'gamemode', 'prestige', 'giftbox' }"),
        "    const = {\n", "    const = {\n        synthRepeat = false, -- public CEXI release policy\n"))
    edit('servers/cexi/manifest.lua', lambda s: replace_between(s,
        "    -- The pack's modules", "    modules =",
        "    -- Public CEXI modules; E-Box Restock is not distributed.\n"))
    out['servers/index.lua'] = b"-- Dedicated public CatsEyeXI distribution.\nreturn { 'cexi' };\n"
    out['servers/cexi/modules/ebox/init.lua'] = (
        b"-- Public CEXI: an old module override must not restore Restock.\nreturn {};\n")
    out['servers/cexi/modules/ebox/eboxclient.lua'] = PROXIMITY.encode('utf-8')
    out['README.md'] = README.encode('utf-8')
    return out


def build(ref, output):
    commit = git('rev-parse', '--verify', ref + '^{commit}').decode().strip()
    # git archive honors EOL conversion; pin it so a Windows maintainer and
    # the Linux release job package the same bytes from the same Git blobs.
    archive = git('-c', 'core.autocrlf=false', '-c', 'core.eol=lf',
                  'archive', '--format=zip', commit)
    with zipfile.ZipFile(io.BytesIO(archive)) as source:
        files = {i.filename: source.read(i) for i in source.infolist() if not i.is_dir()}
    files = project(files)
    manifest = {
        'distribution': 'cexi-public', 'source_commit': commit,
        'builder_sha256': hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest(),
        'excluded_features': ['ebox-restock', 'last-synth-actions', 'auto-acc', 'storage-move'],
        'sha256': {p: hashlib.sha256(data).hexdigest() for p, data in sorted(files.items())},
    }
    files['RELEASE.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation: never overwrite a previously built release.
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as target:
        for path, data in sorted(files.items()):
            info = zipfile.ZipInfo('dlac/' + path, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            target.writestr(info, data)
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + '.sha256').write_text(
        f'{checksum}  {output.name}\n', encoding='utf-8')
    print(f'{output}: {len(files)} files, source {commit}, SHA-256 {checksum}')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', default='HEAD', help='Committed shared-source revision (default: HEAD)')
    parser.add_argument('--output', required=True, help='New output ZIP path')
    args = parser.parse_args()
    build(args.ref, args.output)
