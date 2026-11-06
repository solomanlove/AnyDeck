"""使用本地最小签名包验证嵌套组件与调试权限，不启动 App。"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "requires macOS codesign")
class MacOSAppPolicyTests(unittest.TestCase):
    def test_resigning_preserves_debug_and_release_entitlements_and_runtime(self):
        with tempfile.TemporaryDirectory(prefix="anydeck-signing-") as temporary:
            for configuration, entitlement in (("Debug", "DebugProfile"), ("Release", "Release")):
                with self.subTest(configuration=configuration):
                    app = Path(temporary) / configuration / "AnyDeck.app"
                    executable = app / "Contents/MacOS/AnyDeck"
                    executable.parent.mkdir(parents=True)
                    shutil.copyfile("/usr/bin/true", executable)
                    executable.chmod(0o755)
                    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                        "CFBundleIdentifier": "com.github.anydeck",
                        "CFBundleExecutable": "AnyDeck", "CFBundlePackageType": "APPL"}))
                    nested = executable.parent / "ShareCore"
                    nested.mkdir()
                    shutil.copyfile(executable, nested / "anydeck-share-core")
                    (nested / "anydeck-share-core").chmod(0o755)
                    metadata = app / "Contents/Resources/ShareCore/manifest.json"
                    metadata.parent.mkdir(parents=True)
                    metadata.write_text('{"fixture": true}')
                    entitlements = ROOT / "macos/Runner" / (entitlement + ".entitlements")
                    subprocess.run(["codesign", "--force", "--sign", "-", str(nested / "anydeck-share-core")],
                                   check=True, capture_output=True, timeout=30)
                    helper_before = (nested / "anydeck-share-core").read_bytes()
                    subprocess.run(["codesign", "--force", "--options", "runtime",
                                    "--timestamp=none", "--sign", "-", "--entitlements",
                                    str(entitlements), str(app)], check=True, capture_output=True, timeout=30)
                    subprocess.run(["/bin/bash", str(ROOT / "script/fix_macos_app_policy.sh"), str(app)],
                                   check=True, capture_output=True, timeout=30)
                    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                                   check=True, capture_output=True, timeout=30)
                    actual = subprocess.check_output(["codesign", "-d", "--entitlements", ":-", str(app)],
                                                     stderr=subprocess.DEVNULL, timeout=15)
                    self.assertEqual(plistlib.loads(actual), plistlib.loads(entitlements.read_bytes()))
                    self.assertEqual((nested / "anydeck-share-core").read_bytes(), helper_before)
                    details = subprocess.run(["codesign", "-dv", str(app)], check=True,
                                             capture_output=True, text=True, timeout=15)
                    self.assertRegex(details.stderr, r"flags=0x[0-9a-f]+\([^)]*\bruntime\b")


if __name__ == "__main__":
    unittest.main()
