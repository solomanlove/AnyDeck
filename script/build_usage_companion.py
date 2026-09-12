#!/usr/bin/env python3
"""使用本机 Android SDK 构建无第三方依赖的使用时长 APK，不安装或启动应用。"""

import os
from pathlib import Path
import subprocess
import tempfile
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    source = root / "tool/usage_companion"
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
               or Path.home() / "Library/Android/sdk")
    java = Path(os.environ.get("JAVA_HOME")
                or "/Applications/Android Studio.app/Contents/jbr/Contents/Home")
    build_tools = sdk / "build-tools" / "36.0.0"
    android_jar = sdk / "platforms/android-36/android.jar"
    output = root / "assets/android/usage_companion.apk"
    local = root / ".build/usage_companion"
    local.mkdir(parents=True, exist_ok=True)
    key = local / "development.keystore"
    environment = dict(os.environ, JAVA_HOME=str(java))

    def run(*args):
        subprocess.run([str(arg) for arg in args], check=True, env=environment, timeout=120)

    if not key.exists():
        # 开发签名只存于忽略目录；生产分发需独立、稳定保管签名材料。
        run(java / "bin/keytool", "-genkeypair", "-keystore", key,
            "-storepass", "android", "-keypass", "android", "-alias", "androiddebugkey",
            "-dname", "CN=AnyDeck Development", "-keyalg", "RSA", "-validity", "10000")
    with tempfile.TemporaryDirectory(prefix="build-", dir=local) as temporary:
        work = Path(temporary)
        generated = work / "generated"
        classes = work / "classes"
        dex = work / "dex"
        for directory in [generated, classes, dex]:
            directory.mkdir()
        run(build_tools / "aapt2", "compile", "--dir", source / "res", "-o", work / "res.zip")
        run(build_tools / "aapt2", "link", "-I", android_jar, "--manifest",
            source / "AndroidManifest.xml", "--java", generated,
            "-o", work / "unsigned.apk", work / "res.zip")
        files = sorted(source.rglob("*.java")) + sorted(generated.rglob("*.java"))
        run(java / "bin/javac", "--release", "8", "-classpath", android_jar,
            "-encoding", "UTF-8", "-d", classes, *files)
        run(build_tools / "d8", "--min-api", "26", "--lib", android_jar,
            "--output", dex, *sorted(classes.rglob("*.class")))
        with zipfile.ZipFile(work / "unsigned.apk", "a", zipfile.ZIP_DEFLATED) as archive:
            archive.write(dex / "classes.dex", "classes.dex")
        run(build_tools / "zipalign", "-f", "4", work / "unsigned.apk", work / "aligned.apk")
        run(build_tools / "apksigner", "sign", "--ks", key, "--ks-key-alias", "androiddebugkey",
            "--ks-pass", "pass:android", "--key-pass", "pass:android",
            "--v4-signing-enabled", "false",
            "--out", output, work / "aligned.apk")
        run(build_tools / "apksigner", "verify", output)
    print(f"APK: {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
