#!/usr/bin/env python3
"""使用本机 Android SDK 构建 AnyDeck 折叠屏 Helper，不安装或启动设备程序。"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
               or Path.home() / "Library/Android/sdk")
    java_home = os.environ.get("JAVA_HOME")
    javac = Path(java_home) / "bin/javac" if java_home else Path(shutil.which("javac") or "javac")
    build_tools = sdk / "build-tools/36.0.0"
    android_jar = sdk / "platforms/android-36/android.jar"
    output = root / "assets/android/foldable-screen-helper.jar"
    source = root / "tool/foldable_screen_helper/src"
    environment = dict(os.environ)
    if java_home:
        environment["JAVA_HOME"] = java_home

    def run(*args):
        subprocess.run([str(arg) for arg in args], check=True, env=environment, timeout=120)

    with tempfile.TemporaryDirectory(prefix="anydeck-foldable-") as temporary:
        work = Path(temporary)
        classes = work / "classes"
        dex = work / "dex"
        classes.mkdir()
        dex.mkdir()
        run(javac, "--release", "8", "-classpath", android_jar,
            "-encoding", "UTF-8", "-d", classes, *sorted(source.rglob("*.java")))
        run(build_tools / "d8", "--min-api", "31", "--lib", android_jar,
            "--output", dex, *sorted(classes.rglob("*.class")))
        # 固定 ZIP 元信息，使同一源码重复构建时产物稳定，便于校验与缓存。
        entry = zipfile.ZipInfo("classes.dex", date_time=(2026, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output, "w") as archive:
            archive.writestr(entry, (dex / "classes.dex").read_bytes())
    print(f"Helper: {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
