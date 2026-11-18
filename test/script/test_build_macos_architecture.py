"""验证 Release 入口在不同宿主/显式目标下传递一致架构，不执行真实编译。"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildMacOSArchitectureTests(unittest.TestCase):
    def run_build(self, host, variables=None):
        temporary = tempfile.TemporaryDirectory(prefix='anydeck-release-arch-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        scripts = root / 'script'
        scripts.mkdir()
        shutil.copy2(ROOT / 'script/build_macos.sh', scripts / 'build_macos.sh')
        fixtures = {
            'script/fix_macos_app_policy.sh': '#!/bin/sh\nexit 0\n',
            'bin/uname': f'#!/bin/sh\nprintf "%s\\n" "{host}"\n',
            'bin/flutter': '''#!/bin/sh
printf '%s\\n' "$ANYDECK_TARGET_ARCH" "$FLUTTER_XCODE_ARCHS" "$*" > flutter-call.txt
mkdir -p build/macos/Build/Products/Release/AnyDeck.app
''',
        }
        for name, source in fixtures.items():
            file = root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(source)
            file.chmod(0o755)
        env = dict(os.environ)
        for name in ('ANYDECK_TARGET_ARCH', 'FLUTTER_XCODE_ARCHS'):
            env.pop(name, None)
        env.update(variables or {})
        env['FLUTTER_BIN'] = str(root / 'bin/flutter')
        env['PATH'] = f"{root / 'bin'}:{env['PATH']}"
        destination = root / 'output with spaces'
        result = subprocess.run(['/bin/bash', str(scripts / 'build_macos.sh'), str(destination)],
                                cwd=scripts, env=env, capture_output=True, text=True, timeout=15)
        return result, root, destination

    def test_default_host_is_normalized_and_forwarded_to_flutter_and_pods(self):
        for host, expected in (('arm64', 'arm64'), ('arm64e', 'arm64'), ('x86_64', 'x86_64')):
            with self.subTest(host=host):
                result, root, destination = self.run_build(host)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((root / 'flutter-call.txt').read_text().splitlines(),
                                 [expected, expected, 'build macos --release --no-pub'])
                self.assertTrue((destination / 'Products/AnyDeck.app').is_dir())

    def test_explicit_target_wins_and_flutter_override_remains_supported(self):
        for variables, expected in (
            ({'ANYDECK_TARGET_ARCH': 'x86_64', 'FLUTTER_XCODE_ARCHS': 'arm64'}, 'x86_64'),
            ({'FLUTTER_XCODE_ARCHS': 'x86_64'}, 'x86_64'),
            ({'ANYDECK_TARGET_ARCH': 'arm64e'}, 'arm64'),
        ):
            with self.subTest(variables=variables):
                result, root, _ = self.run_build('arm64e', variables)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((root / 'flutter-call.txt').read_text().splitlines()[:2],
                                 [expected, expected])

    def test_invalid_or_multiple_architectures_fail_before_build_and_copy(self):
        for target in ('riscv64', 'arm64 x86_64'):
            with self.subTest(target=target):
                result, root, destination = self.run_build('arm64', {'ANYDECK_TARGET_ARCH': target})
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / 'flutter-call.txt').exists())
                self.assertFalse(destination.exists())
