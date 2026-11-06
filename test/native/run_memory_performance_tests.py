#!/usr/bin/env python3
"""编译并执行 Socket/Texture 原生单元测试，不构建或启动 AnyDeck 应用。"""
import glob
import pathlib
import platform
import shutil
import subprocess
import tempfile


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=120)
    print(result.stdout + result.stderr, end="")
    if result.returncode:
        raise SystemExit(result.returncode)


def main():
    repository = pathlib.Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="anydeck_native_perf_tests_") as temporary:
        output = pathlib.Path(temporary)
        socket_tests = output / "adb_socket_tests"
        run(["rustc", "--edition=2021", "--test",
             "rust/device_bridge/src/adb_socket.rs", "-o", str(socket_tests)], repository)
        run([str(socket_tests)], repository)
        if platform.system() != "Darwin":
            print("Texture 测试需要 macOS，已跳过 Swift 部分。")
            return
        flutter = shutil.which("flutter")
        if flutter is None:
            raise SystemExit("PATH 中缺少 Flutter SDK。")
        sdk = pathlib.Path(flutter).resolve().parents[1]
        candidates = glob.glob(str(sdk / "bin/cache/artifacts/engine/darwin-x64/"
                                  "FlutterMacOS.xcframework/*/FlutterMacOS.framework"))
        if not candidates:
            raise SystemExit("缺少 FlutterMacOS.framework，请先安装 macOS SDK artifacts。")
        framework_directory = str(pathlib.Path(candidates[0]).parent)
        texture_tests = output / "texture_tests"
        run(["swiftc", "-target", platform.machine() + "-apple-macos13.0",
             "-F", framework_directory, "-framework", "FlutterMacOS",
             "-Xlinker", "-rpath", "-Xlinker", framework_directory,
             "macos/Runner/RustTexturePlugin.swift", "test/native/texture_frame_gate_test.swift",
             "-o", str(texture_tests)], repository)
        run([str(texture_tests)], repository)


if __name__ == "__main__":
    main()
