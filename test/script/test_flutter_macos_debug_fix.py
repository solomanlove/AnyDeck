"""验证 SDK 兼容修复可重复、可恢复，且失败时不覆盖原工具。"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
import fix_flutter_macos_debug as fix


class FlutterDebugFixTests(unittest.TestCase):
    def test_transform_preserves_other_branches_and_is_reversible(self):
        original = 'before\n' + fix.ORIGINAL + '\nrelease branch\n'
        patched = fix.transform(original)
        self.assertIn('destination = XcodeSdk.MacOSX.genericPlatform;', patched)
        self.assertIn('archs = hostArch;', patched)
        self.assertEqual(fix.transform(patched), patched)
        self.assertEqual(fix.transform(patched, restore=True), original)
        self.assertTrue(patched.startswith('before\n'))
        self.assertTrue(patched.endswith('\nrelease branch\n'))

    def test_unknown_or_ambiguous_source_is_rejected(self):
        for text in ('new SDK code', fix.ORIGINAL * 2, fix.ORIGINAL + fix.PATCHED):
            with self.subTest(text=text), self.assertRaises(ValueError):
                fix.transform(text)

    def sdk(self, root):
        source = root / fix.SOURCE
        source.parent.mkdir(parents=True)
        source.write_text(fix.ORIGINAL)
        for name, contents in (
            ('bin/cache/flutter_tools.snapshot', b'old snapshot'),
            ('bin/cache/dart-sdk/bin/dart', b'fixture'),
            ('packages/flutter_tools/.dart_tool/package_config.json', b'{}'),
            ('packages/flutter_tools/pubspec.lock', b'preserve user lock'),
            ('bin/cache/flutter_tools.stamp', b'preserve stamp'),
        ):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)
        return source

    def test_compiles_atomically_without_upgrading_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.sdk(root)
            def compiler(command, **kwargs):
                self.assertNotIn('pub', command)
                self.assertIn('--snapshot-kind=app-jit', command)
                (root / 'bin/cache/flutter_tools.anydeck.snapshot').write_bytes(b'new snapshot')
            with patch.object(fix.subprocess, 'run', side_effect=compiler):
                backup = fix.apply(root)
            self.assertEqual(source.read_text(), fix.PATCHED)
            self.assertEqual((root / 'bin/cache/flutter_tools.snapshot').read_bytes(), b'new snapshot')
            self.assertEqual((backup / 'flutter_tools.snapshot').read_bytes(), b'old snapshot')
            self.assertEqual((root / 'packages/flutter_tools/pubspec.lock').read_bytes(), b'preserve user lock')
            self.assertEqual((root / 'bin/cache/flutter_tools.stamp').read_bytes(), b'preserve stamp')

    def test_failed_compile_restores_source_and_preserves_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.sdk(root)
            with patch.object(fix.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, ['dart'])):
                with self.assertRaises(subprocess.CalledProcessError):
                    fix.apply(root)
            self.assertEqual(source.read_text(), fix.ORIGINAL)
            self.assertEqual((root / 'bin/cache/flutter_tools.snapshot').read_bytes(), b'old snapshot')
