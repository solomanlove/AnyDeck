"""验证 AnyDeck 本地构建与正式摄像头签名的权限隔离，不启动 App。"""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONFIGURATIONS = ("Debug", "Release", "Profile")
APP_GROUP = "group.com.github.anydeck.camera"
DEFAULT_EXTENSION_ID = "com.github.anydeck.camera-extension"


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcodebuild"),
                     "requires macOS Xcode")
class CameraExtensionSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="anydeck-camera-signing-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.build_root = Path(cls.temporary.name)

    def xcodebuild(self, configuration, arguments):
        # 只在临时目录生成验证产物，避免污染用户的构建目录或现有 App 签名。
        result = subprocess.run([
            "xcodebuild", "-project", str(ROOT / "macos/Runner.xcodeproj"),
            "-configuration", configuration, *arguments,
            f"SYMROOT={self.build_root / 'products'}",
            f"OBJROOT={self.build_root / 'objects'}",
        ], cwd=ROOT, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def signing_settings(self, configuration, camera=False):
        arguments = ["-target", "Runner", "-target", "AnyDeckCameraExtension",
                     "-showBuildSettings", "-json"]
        if camera:
            arguments.append("ANYDECK_CAMERA_ENTITLEMENTS_PREFIX=Camera")
        return {target["target"]: target["buildSettings"]
                for target in json.loads(self.xcodebuild(configuration, arguments))}

    def entitlements(self, settings):
        return plistlib.loads((ROOT / "macos" / settings["CODE_SIGN_ENTITLEMENTS"]).read_bytes())

    def test_local_configurations_keep_adhoc_signing_without_restricted_entitlements(self):
        for configuration in CONFIGURATIONS:
            with self.subTest(configuration=configuration):
                targets = self.signing_settings(configuration)
                for name, settings in targets.items():
                    with self.subTest(target=name):
                        self.assertEqual(settings["CODE_SIGNING_ALLOWED"], "YES")
                        self.assertEqual(settings["CODE_SIGN_IDENTITY"], "-")
                        entitlements = self.entitlements(settings)
                        self.assertNotIn("com.apple.security.application-groups", entitlements)
                        self.assertNotIn("com.apple.developer.system-extension.install", entitlements)
                self.assertTrue(self.entitlements(targets["AnyDeckCameraExtension"])
                                ["com.apple.security.app-sandbox"])

    def test_camera_configurations_preserve_install_and_shared_group_entitlements(self):
        for configuration in CONFIGURATIONS:
            with self.subTest(configuration=configuration):
                targets = self.signing_settings(configuration, camera=True)
                for settings in targets.values():
                    self.assertEqual(settings["CODE_SIGNING_ALLOWED"], "YES")
                    self.assertEqual(self.entitlements(settings)
                                     ["com.apple.security.application-groups"], [APP_GROUP])
                self.assertTrue(self.entitlements(targets["Runner"])
                                ["com.apple.developer.system-extension.install"])
                self.assertTrue(self.entitlements(targets["AnyDeckCameraExtension"])
                                ["com.apple.security.app-sandbox"])

    def test_extension_builds_and_verifies_with_default_local_signing(self):
        self.xcodebuild("Debug", ["-target", "AnyDeckCameraExtension", "build"])
        extension = (self.build_root / "products/Debug"
                     / "com.github.anydeck.camera-extension.systemextension")
        result = subprocess.run(["codesign", "--verify", "--strict", str(extension)],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(extension)],
                                capture_output=True, check=True, timeout=15)
        entitlements = plistlib.loads(actual.stdout)
        self.assertTrue(entitlements["com.apple.security.app-sandbox"])
        self.assertNotIn("com.apple.security.application-groups", entitlements)

    def test_extension_identifier_override_matches_host_configuration(self):
        host_info = plistlib.loads((ROOT / "macos/Runner/Info.plist").read_bytes())
        self.assertEqual(host_info['AnyDeckCameraExtensionBundleIdentifier'],
                         '$(ANYDECK_CAMERA_EXTENSION_BUNDLE_ID)')
        project = json.loads(subprocess.run([
            'plutil', '-convert', 'json', '-o', '-',
            str(ROOT / 'macos/Runner.xcodeproj/project.pbxproj'),
        ], capture_output=True, text=True, check=True, timeout=15).stdout)
        embed_phase = next(item for item in project['objects'].values()
                           if item.get('isa') == 'PBXCopyFilesBuildPhase'
                           and item.get('name') == 'Embed System Extensions')
        embed_file = project['objects'][embed_phase['files'][0]]
        embedded_product = project['objects'][embed_file['fileRef']]['path']
        for configuration in CONFIGURATIONS:
            for identifier in (DEFAULT_EXTENSION_ID, DEFAULT_EXTENSION_ID + '.testing'):
                with self.subTest(configuration=configuration, identifier=identifier):
                    arguments = ['-target', 'Runner', '-target', 'AnyDeckCameraExtension',
                                 '-showBuildSettings', '-json']
                    if identifier != DEFAULT_EXTENSION_ID:
                        arguments.append(f'ANYDECK_CAMERA_EXTENSION_BUNDLE_ID={identifier}')
                    targets = {item['target']: item['buildSettings']
                               for item in json.loads(self.xcodebuild(configuration, arguments))}
                    self.assertEqual(targets['Runner']['PRODUCT_BUNDLE_IDENTIFIER'], 'com.github.anydeck')
                    self.assertEqual(targets['Runner']['ANYDECK_CAMERA_EXTENSION_BUNDLE_ID'], identifier)
                    extension = targets['AnyDeckCameraExtension']
                    self.assertEqual(extension['PRODUCT_BUNDLE_IDENTIFIER'], identifier)
                    self.assertEqual(extension['FULL_PRODUCT_NAME'], identifier + '.systemextension')
                    self.assertEqual(embedded_product.replace('$(ANYDECK_CAMERA_EXTENSION_BUNDLE_ID)', identifier),
                                     extension['FULL_PRODUCT_NAME'])

    def test_extension_override_builds_with_matching_bundle_filename(self):
        identifier = DEFAULT_EXTENSION_ID + '.testing'
        self.xcodebuild('Debug', ['-target', 'AnyDeckCameraExtension', 'build',
                                f'ANYDECK_CAMERA_EXTENSION_BUNDLE_ID={identifier}'])
        extension = self.build_root / 'products/Debug' / (identifier + '.systemextension')
        info = plistlib.loads((extension / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIdentifier'], identifier)
        result = subprocess.run(['codesign', '--verify', '--strict', str(extension)],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_activation_contract_reads_extension_identifier_from_host_bundle(self):
        # 用最小宿主 Bundle 验证真实 Bundle.main 读取，不激活扩展或访问摄像头。
        executable = self.build_root / 'activation-contract'
        result = subprocess.run([
            'xcrun', 'swiftc', str(ROOT / 'macos/CameraShared/VirtualCameraContract.swift'),
            str(ROOT / 'macos/Runner/VirtualCamera/VirtualCameraActivation.swift'),
            str(ROOT / 'test/native/virtual_camera_activation_test.swift'),
            '-o', str(executable),
        ], capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for identifier in (DEFAULT_EXTENSION_ID, DEFAULT_EXTENSION_ID + '.testing'):
            with self.subTest(identifier=identifier):
                contents = self.build_root / (identifier + '.app') / 'Contents'
                binary = contents / 'MacOS/ActivationContract'
                binary.parent.mkdir(parents=True)
                shutil.copy2(executable, binary)
                (contents / 'Info.plist').write_bytes(plistlib.dumps({
                    'CFBundleIdentifier': 'com.github.anydeck.tests',
                    'CFBundleExecutable': binary.name,
                    'CFBundlePackageType': 'APPL',
                    'AnyDeckCameraExtensionBundleIdentifier': identifier,
                }))
                run = subprocess.run([str(binary), identifier], capture_output=True,
                                     text=True, timeout=15)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_release_targets_accept_each_explicit_architecture(self):
        for architecture in ('arm64', 'x86_64'):
            arguments = ['-target', 'Runner', '-target', 'AnyDeckCameraExtension',
                         '-showBuildSettings', '-json', f'ARCHS={architecture}']
            targets = json.loads(self.xcodebuild('Release', arguments))
            for target in targets:
                self.assertEqual(target['buildSettings']['ARCHS'], architecture)
                self.assertEqual(target['buildSettings']['CODE_SIGN_IDENTITY'], '-')

    def test_host_subarchitecture_does_not_leak_into_build_architecture(self):
        # 模拟 arm64e 宿主及 Intel，确保三个配置仍使用 Flutter/Rust 支持的架构。
        for configuration in CONFIGURATIONS:
            for native, architecture in (('arm64e', 'arm64'), ('arm64', 'arm64'), ('x86_64', 'x86_64')):
                with self.subTest(configuration=configuration, native=native):
                    arguments = ['-target', 'Runner', '-showBuildSettings', '-json',
                                 f'NATIVE_ARCH_ACTUAL={native}',
                                 f'NATIVE_ARCH_64_BIT={native}']
                    targets = json.loads(self.xcodebuild(configuration, arguments))
                    self.assertEqual(targets[0]['buildSettings']['ARCHS'], architecture)


if __name__ == "__main__":
    unittest.main()
