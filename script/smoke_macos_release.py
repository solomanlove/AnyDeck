#!/usr/bin/env python3
"""在对应架构 CI 验证 helper，可选检查 App 启动存活；不访问手机。"""
import json
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

app = Path(sys.argv[1]).resolve(strict=True)
expected_arch = sys.argv[2]
if platform.machine() != expected_arch:
    sys.exit('原生 smoke test 必须在对应架构的 Runner 上运行')

core = subprocess.run([str(app / 'Contents/MacOS/ShareCore/anydeck-share-core')],
                      input='{"version":3,"command":"hello"}\n', text=True,
                      capture_output=True, check=True, timeout=15)
hello = json.loads(core.stdout.strip())
if hello.get('event') != 'hello' or hello.get('version') != 3:
    sys.exit('Share Core IPC hello 验证失败')

fixture = Path(__file__).resolve().parents[1] / 'assets/android/usage_companion.apk'
apk = subprocess.run([str(app / 'Contents/Helpers/anydeck-apk-inspector'), str(fixture)],
                     text=True, capture_output=True, check=True, timeout=30)
if json.loads(apk.stdout).get('packageName') != 'com.adbmanage.companion':
    sys.exit('原生 APK helper 真实 APK 分析失败')
print(f'{expected_arch}: Share Core IPC hello 与真实 APK 分析通过')

if '--launch-app' in sys.argv[3:]:
    # 只启动本次产物；所有退出路径均回收进程，不使用机器上的其它 App。
    with tempfile.TemporaryFile(mode='w+b') as output:
        process = subprocess.Popen([str(app / 'Contents/MacOS/AnyDeck')],
                                   stdout=output, stderr=subprocess.STDOUT)
        try:
            try:
                code = process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                print(f'{expected_arch}: App 原生进程启动并保持运行 8 秒')
            else:
                output.seek(0)
                sys.exit(f'App 启动后提前退出（{code}）: {output.read().decode(errors="replace")[-4000:]}')
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
