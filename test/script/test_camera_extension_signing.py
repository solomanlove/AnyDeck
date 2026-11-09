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

    def test_release_targets_accept_each_explicit_architecture(self):
        for architecture in ('arm64', 'x86_64'):
            arguments = ['-target', 'Runner', '-target', 'AnyDeckCameraExtension',
                         '-showBuildSettings', '-json', f'ARCHS={architecture}']
            targets = json.loads(self.xcodebuild('Release', arguments))
            for target in targets:
                self.assertEqual(target['buildSettings']['ARCHS'], architecture)
                self.assertEqual(target['buildSettings']['CODE_SIGN_IDENTITY'], '-')


if __name__ == "__main__":
    unittest.main()
