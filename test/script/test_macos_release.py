"""用真实最小 Mach-O 包验证发布门禁与 ZIP/DMG，不启动 App。"""
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('release_verifier', ROOT / 'script/verify_macos_release.py')
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('clang'), 'requires macOS tools')
class MacOSReleaseTests(unittest.TestCase):
    def setUp(self):
        # Fixture 版本独立于触发 CI 的真实版本 Tag。
        environment = patch.dict(os.environ, {'GITHUB_REF_TYPE': 'branch'})
        environment.start()
        self.addCleanup(environment.stop)
        temporary = tempfile.TemporaryDirectory(prefix='anydeck-release-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.app = self.root / 'AnyDeck.app'
        source = self.root / 'main.c'
        source.write_text('int main(void) { return 0; }\n')
        self.binary = self.root / 'helper'
        self.run_command(['clang', '-arch', 'arm64', str(source), '-o', str(self.binary)])
        library = self.root / 'bridge.dylib'
        self.run_command(['clang', '-arch', 'arm64', '-dynamiclib', str(source),
                          '-Wl,-install_name,@rpath/libanydeck_device_bridge.dylib', '-o', str(library)])
        for name in VERIFIER.REQUIRED:
            target = self.app / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if name.endswith('.json'):
                target.write_text('{}')
            else:
                shutil.copyfile(library if name.endswith('.dylib') else self.binary, target)
                target.chmod(0o755)
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.github.anydeck.release-test',
            'CFBundleExecutable': 'AnyDeck', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '1.0.0'}))
        (self.app / 'Contents/Resources/fixture-link').symlink_to('ShareCore/manifest.json')
        self.sign()

    def run_command(self, arguments, **kwargs):
        return subprocess.run(arguments, check=True, capture_output=True, timeout=120, **kwargs)

    def sign(self):
        self.run_command(['codesign', '--force', '--deep', '--sign', '-', str(self.app)])

    def test_valid_bundle_and_version_tag(self):
        with patch.dict(os.environ, {'GITHUB_REF_TYPE': 'tag', 'GITHUB_REF_NAME': 'v1.0.0'}):
            VERIFIER.verify(self.app)

    def test_rejects_version_mismatch(self):
        with patch.dict(os.environ, {'GITHUB_REF_TYPE': 'tag', 'GITHUB_REF_NAME': 'v2.0.0'}):
            with self.assertRaisesRegex(ValueError, '不一致'):
                VERIFIER.verify(self.app)

    def test_rejects_missing_component(self):
        (self.app / 'Contents/Helpers/anydeck-apk-inspector').unlink()
        with self.assertRaisesRegex(ValueError, '缺少分发组件'):
            VERIFIER.verify(self.app)

    def test_rejects_tampered_signature(self):
        (self.app / 'Contents/Resources/ShareCore/manifest.json').write_text('{"changed": true}')
        with self.assertRaises(subprocess.CalledProcessError):
            VERIFIER.verify(self.app)

    def test_rejects_development_machine_library(self):
        library = self.app / 'Contents/Frameworks/libanydeck_device_bridge.dylib'
        self.run_command(['install_name_tool', '-id', '/opt/homebrew/lib/unbundled.dylib', str(library)])
        self.sign()
        with self.assertRaisesRegex(ValueError, '非便携动态库依赖'):
            VERIFIER.verify(self.app)

    def test_archives_preserve_signature_permissions_and_symlinks(self):
        output = self.root / 'release'
        self.run_command(['bash', str(ROOT / 'script/package_macos_release.sh'), str(self.app), str(output)])
        self.run_command(['shasum', '-a', '256', '-c', 'SHA256SUMS'], cwd=output)
        self.run_command(['hdiutil', 'verify', str(output / 'AnyDeck-macOS-arm64.dmg')])
        extracted = self.root / 'extracted'
        self.run_command(['ditto', '-x', '-k', str(output / 'AnyDeck-macOS-arm64.zip'), str(extracted)])
        app = extracted / 'AnyDeck.app'
        VERIFIER.verify(app)
        self.assertTrue((app / 'Contents/Resources/fixture-link').is_symlink())
        self.assertTrue(os.access(app / 'Contents/Helpers/anydeck-apk-inspector', os.X_OK))


if __name__ == '__main__':
    unittest.main()
