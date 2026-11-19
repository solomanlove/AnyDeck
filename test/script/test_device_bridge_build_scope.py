"""Xcode 构建原生库时不能改写其它配置已经签名的 App。"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class DeviceBridgeBuildScopeTests(unittest.TestCase):
    def test_validates_signed_library_before_publishing_to_project_or_apps(self):
        with tempfile.TemporaryDirectory(prefix="anydeck-build-scope-") as temporary:
            root = Path(temporary)
            (root / "script").mkdir()
            shutil.copyfile(ROOT / "script/build_device_bridge.sh", root / "script/build_device_bridge.sh")
            tools = root / "fake-tools"
            tools.mkdir()
            # 模拟原生工具，按文件内容区分签名前后的产物；发布逻辑仍执行真实脚本。
            commands = {
                "cargo": '''#!/bin/bash
set -eu
while [ "$#" -gt 0 ]; do
  case "$1" in --target) arch="$2"; shift;; --target-dir) dest="$2"; shift;; esac
  shift
done
mkdir -p "$dest/$arch/release"
printf new > "$dest/$arch/release/libanydeck_device_bridge.dylib"
''',
                "lipo": '''#!/bin/bash
set -eu
input="$2"
while [ "$1" != "-output" ]; do shift; done
cp "$input" "$2"
''',
                "install_name_tool": "#!/bin/bash\nexit 0\n",
                "codesign": '#!/bin/bash\nprintf signed >> "${!#}"\n',
                "xcrun": '''#!/bin/bash
set -eu
[[ "$1" == dyld_info && "$2" == -validate_only && "$(cat "$3")" == newsigned ]] || exit 2
exit "$TEST_VALIDATION_EXIT"
''',
            }
            for name, source in commands.items():
                path = tools / name
                path.write_text(source)
                path.chmod(0o755)
            artifacts = []
            for configuration in ("Debug", "Release"):
                library = root / f"build/macos/Build/Products/{configuration}/AnyDeck.app/Contents/Frameworks/libanydeck_device_bridge.dylib"
                library.parent.mkdir(parents=True)
                library.write_bytes(configuration.encode())
                artifacts.append((library, library.read_bytes()))
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", CARGO=str(tools / "cargo"),
                       ARCHS="arm64", TARGET_TEMP_DIR=str(root / "temporary"), TEST_VALIDATION_EXIT="0",
                       TARGET_BUILD_DIR=str(root / "build/macos/Build/Products/Release"))
            build = ["/bin/bash", str(root / "script/build_device_bridge.sh")]
            success = subprocess.run(build, env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(success.returncode, 0, success.stderr)
            published = root / "macos/Libs/libanydeck_device_bridge.dylib"
            self.assertEqual(published.read_bytes(), b"newsigned")
            for library, original in artifacts:
                self.assertEqual(library.read_bytes(), original)

            # 独立构建若被 dyld 拒绝，项目库和已有 Debug、Release 包都应保留。
            published.write_bytes(b"previous")
            env.pop("TARGET_BUILD_DIR")
            env["TEST_VALIDATION_EXIT"] = "42"
            failed = subprocess.run(build, env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(failed.returncode, 42, failed.stderr)
            self.assertEqual(published.read_bytes(), b"previous")
            self.assertEqual(list(published.parent.iterdir()), [published])
            for library, original in artifacts:
                self.assertEqual(library.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
