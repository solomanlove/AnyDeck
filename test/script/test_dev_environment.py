"""验证多机工具链选择、版本漂移拒绝与初始化边界，不安装或编译项目。"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'script'))
import dev_environment as dev
import setup_dev


class DevEnvironmentTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='anydeck environment ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.sdk = self.root / '.fvm/flutter_sdk'
        (self.sdk / 'bin').mkdir(parents=True)
        (self.sdk / 'bin/flutter').touch()
        (self.root / 'pubspec.lock').write_text('url: "https://pub.dev"\n')
        self.cargo = self.root / 'rust toolchain/bin/cargo'
        self.pins = dict(flutter='3.50.0', rust='1.95.0', cocoapods='1.16.2', bundler='2.6.9')
        self.flutter = dict(frameworkVersion='3.50.0', channel='stable', dartSdkVersion='3.14.0')
        for replacement in (patch.object(dev, 'ROOT', self.root),
                            patch.object(dev, 'versions', return_value=self.pins),
                            patch.object(dev, 'cargo_path', return_value=self.cargo),
                            patch.object(dev.shutil, 'which', return_value=None)):
            replacement.start()
            self.addCleanup(replacement.stop)

    def test_environment_overrides_legacy_cargo_and_flutter_paths(self):
        with patch.dict(os.environ, {'CARGO': '/old/ide-wrapper', 'RUSTUP_TOOLCHAIN': 'nightly',
                                     'PUB_HOSTED_URL': 'https://personal.invalid',
                                     'CARGO_NET_OFFLINE': 'true'}):
            env = dev.environment()
        self.assertEqual(env['CARGO'], str(self.cargo))
        self.assertEqual(env['RUSTC'], str(self.cargo.with_name('rustc')))
        self.assertEqual(env['RUSTUP_TOOLCHAIN'], '1.95.0')
        self.assertEqual(env['FLUTTER_BIN'], str(self.sdk / 'bin/flutter'))
        self.assertEqual(env['PUB_HOSTED_URL'], 'https://pub.dev')
        self.assertEqual(env['BUNDLE_FROZEN'], 'true')
        self.assertNotIn('CARGO_NET_OFFLINE', env)
        self.assertEqual(env['PATH'].split(os.pathsep)[:2],
                         [str(self.sdk / 'bin'), str(self.cargo.parent)])

    def test_missing_project_sdk_does_not_fall_back_to_global_flutter(self):
        (self.sdk / 'bin/flutter').unlink()
        with self.assertRaisesRegex(ValueError, 'setup_dev.sh'):
            dev.environment()

    def test_hosted_source_follows_repository_lock(self):
        (self.root / 'pubspec.lock').write_text('url: "https://pub.flutter-io.cn"\n')
        self.assertEqual(dev.environment()['PUB_HOSTED_URL'], 'https://pub.flutter-io.cn')

    def test_mixed_hosted_sources_are_rejected(self):
        (self.root / 'pubspec.lock').write_text('url: "https://a.test"\nurl: "https://b.test"\n')
        with self.assertRaisesRegex(ValueError, 'hosted'):
            dev.environment()

    def test_flutter_wrong_version_or_channel_is_rejected(self):
        for actual in ({**self.flutter, 'channel': 'beta'},
                       {**self.flutter, 'frameworkVersion': '3.47.2'}):
            with self.subTest(actual=actual), patch.object(dev, 'run', return_value=json.dumps(actual)):
                with self.assertRaisesRegex(ValueError, 'stable 3.50.0'):
                    dev.verify_flutter(dev.environment())

    def test_unmanaged_flutter_patch_is_rejected(self):
        with patch.object(dev, 'run', side_effect=[json.dumps(self.flutter), 'build_macos.dart']):
            with self.assertRaisesRegex(ValueError, '工具补丁'):
                dev.verify_flutter(dev.environment())

    def test_clean_pinned_sdk_is_accepted(self):
        with patch.object(dev, 'run', side_effect=[json.dumps(self.flutter), '']):
            self.assertEqual(dev.verify_flutter(dev.environment()), self.flutter)

    def test_rust_drift_is_rejected_before_native_checks(self):
        with patch.object(dev, 'verify_flutter', return_value=self.flutter), \
                patch.object(dev, 'run', return_value='cargo 1.96.0 (future)'), \
                self.assertRaisesRegex(ValueError, 'cargo 版本不一致'):
            dev.check()

    def test_check_rejects_missing_dependency_lock(self):
        with patch.object(dev, 'verify_flutter', return_value=self.flutter), \
                patch.object(dev, 'run', side_effect=['cargo 1.95.0', 'rustc 1.95.0']), \
                patch.object(dev.sys, 'platform', 'linux'), \
                self.assertRaisesRegex(ValueError, 'Cargo.lock'):
            dev.check()

    def test_versions_are_read_from_authoritative_files(self):
        (self.root / '.fvmrc').write_text('{"flutter":"8.0.0"}')
        (self.root / 'rust-toolchain.toml').write_text('[toolchain]\nchannel = "2.0.0"\n')
        (self.root / 'Gemfile').write_text('gem "cocoapods", "9.0.0"\n')
        (self.root / 'Gemfile.lock').write_text('BUNDLED WITH\n   7.0.0\n')
        # 使用独立模块以避开本类针对实际环境的版本 mock。
        spec = importlib.util.spec_from_file_location('isolated_dev', ROOT / 'script/dev_environment.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.versions(self.root),
                         dict(flutter='8.0.0', rust='2.0.0', cocoapods='9.0.0', bundler='7.0.0'))

    def test_missing_rust_target_is_rejected(self):
        with patch.object(dev, 'verify_flutter', return_value=self.flutter), \
                patch.object(dev, 'rustup_path', return_value='/rustup'), \
                patch.object(dev.platform, 'machine', return_value='arm64'), \
                patch.dict(os.environ, {'ANYDECK_TARGET_ARCH': 'arm64'}), \
                patch.object(dev, 'run', side_effect=['cargo 1.95.0', 'rustc 1.95.0',
                                                     'x86_64-apple-darwin']), \
                patch.object(dev.sys, 'platform', 'darwin'), \
                self.assertRaisesRegex(ValueError, 'aarch64-apple-darwin'):
            dev.check()

    def test_cocoapods_drift_is_rejected(self):
        with patch.object(dev, 'verify_flutter', return_value=self.flutter), \
                patch.object(dev, 'rustup_path', return_value='/rustup'), \
                patch.dict(os.environ, {'ANYDECK_TARGET_ARCH': 'arm64'}), \
                patch.object(dev, 'run', side_effect=['cargo 1.95.0', 'rustc 1.95.0',
                                                     'aarch64-apple-darwin', '', '1.17.0']), \
                patch.object(dev.sys, 'platform', 'darwin'), \
                self.assertRaisesRegex(ValueError, 'CocoaPods 版本不一致'):
            dev.check()


class DevEntryTests(unittest.TestCase):
    def test_initializer_installs_pods_from_macos_directory_with_deployment_lock(self):
        pins = dict(flutter='3.50.0', rust='1.95.0', bundler='2.6.9')
        with patch.object(setup_dev.sys, 'platform', 'darwin'), \
                patch.object(setup_dev.platform, 'machine', return_value='arm64'), \
                patch.dict(os.environ, {'ANYDECK_TARGET_ARCH': 'arm64'}), \
                patch.object(setup_dev.shutil, 'which', return_value='/installed/tool'), \
                patch.object(setup_dev, 'rustup_path', return_value='/rustup'), \
                patch.object(setup_dev, 'versions', return_value=pins), \
                patch.object(setup_dev, 'run', return_value='/installed'), \
                patch.object(setup_dev, 'environment', return_value={
                    'FLUTTER_BIN': '/sdk/flutter', 'CARGO': '/rust/cargo'}), \
                patch.object(setup_dev, 'prepare_macos_config'), \
                patch.object(setup_dev, 'verify_flutter'), patch.object(setup_dev, 'check'), \
                patch.object(setup_dev, 'execute') as execute:
            setup_dev.setup(skip_native=True)
        pods = [call for call in execute.call_args_list if 'pod' in call.args[0]]
        self.assertEqual(len(pods), 1)
        self.assertEqual(pods[0].args[0][-3:], ['pod', 'install', '--deployment'])
        self.assertEqual(pods[0].kwargs['cwd'], ROOT / 'macos')

    def test_flutter_configuration_cannot_silently_rewrite_pod_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lock = root / 'macos/Podfile.lock'
            lock.parent.mkdir()
            lock.write_bytes(b'original locked dependencies')
            with patch.object(setup_dev, 'ROOT', root), \
                    patch.object(setup_dev, 'execute', side_effect=lambda *args: lock.write_bytes(b'updated')), \
                    self.assertRaisesRegex(ValueError, '已恢复'):
                setup_dev.prepare_macos_config({'FLUTTER_BIN': '/sdk/flutter'})
            self.assertEqual(lock.read_bytes(), b'original locked dependencies')

    def test_flutter_configuration_uses_pinned_pods_instead_of_global_pod(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lock = root / 'macos/Podfile.lock'
            lock.parent.mkdir()
            lock.write_bytes(b'locked')
            env = {'FLUTTER_BIN': '/sdk/flutter'}
            with patch.object(setup_dev, 'ROOT', root), \
                    patch.object(setup_dev, 'versions', return_value={'bundler': '2.6.9'}), \
                    patch.object(setup_dev, 'execute') as execute:
                setup_dev.prepare_macos_config(env)
            execute.assert_called_once_with(
                ['bundle', '_2.6.9_', 'exec', '/sdk/flutter', 'build', 'macos',
                 '--debug', '--config-only', '--no-pub'], env)

    def test_ide_replaces_legacy_environment_and_preserves_custom_options(self):
        import configure_flutter_ide
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            configs = root / '.idea/runConfigurations'
            configs.mkdir(parents=True)
            original = '''<component><configuration><option name="additionalArgs" value="--custom" />
<option name="envs"><entry key="CARGO" value="/old/wrapper" />
<entry key="CARGO_NET_OFFLINE" value="true" /><entry key="USER_OPTION" value="keep" />
</option></configuration></component>'''
            for name in ('AnyDeck.xml', 'AnyDeck_No_Share_Core.xml'):
                (configs / name).write_text(original)
            with patch.object(setup_dev, 'ROOT', root), \
                    patch.object(configure_flutter_ide, 'configure'), \
                    patch.object(setup_dev, 'versions', return_value={'bundler': '2.6.9'}), \
                    patch.object(setup_dev, 'run', return_value='CARGO=/pinned/cargo\nSECRET=hidden\n'):
                setup_dev.configure_ide({})
            for file in configs.iterdir():
                config = ET.parse(file).getroot().find('configuration')
                self.assertEqual(config.find("option[@name='additionalArgs']").get('value'), '--custom')
                entries = {e.get('key'): e.get('value') for e in config.findall("option[@name='envs']/entry")}
                self.assertEqual(entries, {'CARGO': '/pinned/cargo', 'USER_OPTION': 'keep'})

    def test_shell_entry_points_propagate_arguments_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix='anydeck entry ') as temporary:
            root = Path(temporary)
            scripts = root / 'script'
            scripts.mkdir()
            for name in ('dev_exec.sh', 'check_env.sh', 'setup_dev.sh'):
                (scripts / name).write_bytes((ROOT / 'script' / name).read_bytes())
            spy = 'import json,sys\nprint(json.dumps(sys.argv[1:]))\nsys.exit(17)\n'
            for name in ('dev_environment.py', 'setup_dev.py'):
                (scripts / name).write_text(spy)
            for entry, expected in (
                ('dev_exec.sh', ['exec', 'argument with spaces']),
                ('check_env.sh', ['check', 'argument with spaces']),
                ('setup_dev.sh', ['argument with spaces']),
            ):
                with self.subTest(entry=entry):
                    result = subprocess.run(['bash', str(scripts / entry), 'argument with spaces'],
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 17)
                    self.assertEqual(json.loads(result.stdout), expected)

    def test_macos_exec_wraps_flutter_in_pinned_bundler(self):
        with patch.object(dev.sys, 'argv', ['dev_environment.py', 'exec', 'flutter', 'analyze']), \
                patch.object(dev, 'environment', return_value={'PATH': '/locked'}), \
                patch.object(dev, 'verify_flutter'), patch.object(dev.os, 'chdir'), \
                patch.object(dev.sys, 'platform', 'darwin'), patch.object(dev, 'versions',
                            return_value={'bundler': '2.6.9'}), patch.object(dev.os, 'execvpe') as execute:
            dev.main()
        execute.assert_called_once_with('bundle', ['bundle', '_2.6.9_', 'exec', 'flutter', 'analyze'],
                                        {'PATH': '/locked'})

    def test_initializer_rejects_unsupported_host_before_installing(self):
        with patch.object(setup_dev.sys, 'platform', 'linux'), \
                patch.object(setup_dev, 'execute') as execute, \
                self.assertRaisesRegex(ValueError, 'macOS'):
            setup_dev.setup()
        execute.assert_not_called()


if __name__ == '__main__':
    unittest.main()
