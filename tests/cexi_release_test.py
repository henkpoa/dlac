"""Build and exercise the actual public CEXI archive. Requires Python 3 and Lua 5.4."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_cexi', ROOT / 'release/build_cexi.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class CexiRelease(unittest.TestCase):
    def test_public_archive(self):
        lua = os.environ.get('LUA') or shutil.which('lua5.4') or shutil.which('lua')
        self.assertIsNotNone(lua, 'Install Lua 5.4 or set LUA to its executable')
        with tempfile.TemporaryDirectory(prefix='dlac-cexi-') as tmp:
            tmp = Path(tmp)
            first = builder.build('HEAD', tmp / 'first.zip')
            second = builder.build('HEAD', tmp / 'second.zip')
            self.assertEqual(first.read_bytes(), second.read_bytes(), 'Builds must be deterministic')
            with zipfile.ZipFile(first) as archive:
                names = set(archive.namelist())
                self.assertTrue(all(n.startswith('dlac/') for n in names))
                self.assertFalse(any('/ascensionxi/' in n or '/.git' in n for n in names))
                for path in builder.OMIT:
                    self.assertNotIn('dlac/' + path, names)
                self.assertIn('dlac/jobhelpers/blu/bludex/LICENSE', names)
                self.assertTrue(any('/bludex/icons/' in n for n in names))
                self.assertIn('dlac/servers/cexi/data/catalog.lua', names)
                manifest = json.loads(archive.read('dlac/RELEASE.json'))
                self.assertEqual(set(manifest['sha256']),
                    {n.removeprefix('dlac/') for n in names} - {'RELEASE.json'})
                for path, digest in manifest['sha256'].items():
                    self.assertEqual(hashlib.sha256(archive.read('dlac/' + path)).hexdigest(), digest)
                archive.extractall(tmp / 'unpacked')
            addon = tmp / 'unpacked/dlac'
            # Parse every shipped Lua file, without executing the addon/game hooks.
            filelist = tmp / 'lua-files.txt'
            filelist.write_text('\n'.join(p.relative_to(addon).as_posix()
                for p in addon.rglob('*.lua')), encoding='utf-8')
            syntax = tmp / 'syntax.lua'
            syntax.write_text("for p in io.lines(arg[1]) do assert(loadfile(p)); end\n", encoding='utf-8')
            subprocess.run([lua, str(syntax), str(filelist)], cwd=addon, check=True)
            subprocess.run([lua, str(ROOT / 'tests/cexi_release.lua')], cwd=addon, check=True)
            subprocess.run([lua, str(ROOT / 'tests/pack_lint.lua'), 'cexi'], cwd=addon, check=True)
            # Source data and unaffected engine files must be verbatim Git blobs.
            for path in ('dispatch.lua', 'servers/cexi/data/catalog.lua',
                         'servers/cexi/modules/giftbox/giftboxui.lua'):
                self.assertEqual((addon / path).read_bytes(), builder.git('show', 'HEAD:' + path))

    def test_private_source_refused(self):
        for path in ('accwatch.lua', 'feature/accwatch.lua', 'gear/gearmove.lua', 'accdata.lua'):
            with self.assertRaisesRegex(ValueError, 'private feature'):
                builder.project({path: b'private'})

    def test_changed_source_boundaries_fail(self):
        source = builder.git('show', 'HEAD:ui/craftbar.lua').decode('utf-8')
        with self.assertRaisesRegex(ValueError, 'boundaries changed'):
            builder.public_craftbar(source.replace('-- Repeat-synth row.', '-- Moved repeat row.'))


if __name__ == '__main__':
    unittest.main()
