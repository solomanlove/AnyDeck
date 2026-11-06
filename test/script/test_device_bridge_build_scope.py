"""Xcode 构建原生库时不能改写其它配置已经签名的 App。"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class DeviceBridgeBuildScopeTests(unittest.TestCase):
    def test_xcode_build_only_produces_library_without_replacing_other_apps(self):
        with tempfile.TemporaryDirectory(prefix="anydeck-build-scope-") as temporary:
            root = Path(temporary)
            (root / "script").mkdir()
            shutil.copyfile(ROOT / "script/build_device_bridge.sh", root / "script/build_device_bridge.sh")
            tools = root / "fake-tools"
            tools.mkdir()
            # 仅模拟编译与签名命令；仍执行真实脚本的文件发布与配置选择逻辑。
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
                "codesign": "#!/bin/bash\nexit 0\n",
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
                       ARCHS="arm64", TARGET_TEMP_DIR=str(root / "temporary"),
                       TARGET_BUILD_DIR=str(root / "build/macos/Build/Products/Release"))
            subprocess.run(["/bin/bash", str(root / "script/build_device_bridge.sh")], env=env,
                           check=True, capture_output=True, timeout=15)
            self.assertEqual((root / "macos/Libs/libanydeck_device_bridge.dylib").read_bytes(), b"new")
            for library, original in artifacts:
                self.assertEqual(library.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
