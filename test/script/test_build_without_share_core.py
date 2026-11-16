"""验证独立构建入口固定 Debug 开关，并检查最终包不含私有组件。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildWithoutShareCoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='anydeck-no-share-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'AnyDeck with spaces'
        (self.root / 'script').mkdir(parents=True)
        self.script = self.root / 'script/build_macos_without_share_core.sh'
        shutil.copy2(ROOT / 'script/build_macos_without_share_core.sh', self.script)
        self.flutter = self.root / 'fake flutter'
        self.flutter.write_text(f'#!{sys.executable}\n' + '''import json, os, pathlib, sys
root = pathlib.Path.cwd()
(root / 'call.json').write_text(json.dumps({
    'args': sys.argv[1:], 'skip': os.environ.get('ANYDECK_SKIP_SHARE_CORE'),
}))
if os.environ.get('TEST_FLUTTER_EXIT'):
    sys.exit(int(os.environ['TEST_FLUTTER_EXIT']))
app = root / 'build/macos/Build/Products/Debug/AnyDeck.app'
app.mkdir(parents=True)
if os.environ.get('TEST_SHARE_COMPONENT'):
    (app / os.environ['TEST_SHARE_COMPONENT']).mkdir(parents=True)
''')
        self.flutter.chmod(0o755)

    def run_build(self, *arguments, **environment):
        return subprocess.run(
            ['/bin/bash', str(self.script), *arguments],
            env={**os.environ, 'FLUTTER_BIN': str(self.flutter), **environment},
            text=True, capture_output=True, timeout=5,
        )

    def test_debug_entry_forces_both_switches_and_accepts_space_in_path(self):
        result = self.run_build(ANYDECK_SKIP_SHARE_CORE='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        call = json.loads((self.root / 'call.json').read_text())
        self.assertEqual(call, {
            'args': ['build', 'macos', '--debug', '--no-pub',
                     '--dart-define=ANYDECK_ENABLE_SHARE_CORE=false'],
            'skip': '1',
        })
        self.assertIn('已构建不含 Share Core', result.stdout)

    def test_flutter_failure_is_propagated(self):
        result = self.run_build(TEST_FLUTTER_EXIT='17')
        self.assertEqual(result.returncode, 17)
        self.assertNotIn('已构建', result.stdout)

    def test_residual_native_or_metadata_component_is_rejected(self):
        for component in ('Contents/MacOS/ShareCore', 'Contents/Resources/ShareCore'):
            with self.subTest(component=component):
                result = self.run_build(TEST_SHARE_COMPONENT=component)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('仍包含 Share Core', result.stderr)
                shutil.rmtree(self.root / 'build')

    def test_mode_override_is_rejected_and_help_does_not_build(self):
        result = self.run_build('--release')
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.root / 'call.json').exists())
        result = self.run_build('--help')
        self.assertEqual(result.returncode, 0)
        self.assertFalse((self.root / 'call.json').exists())


if __name__ == '__main__':
    unittest.main()
