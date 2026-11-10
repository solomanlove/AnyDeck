#!/usr/bin/env python3
"""修复本机 Flutter Debug 目标选择；备份并直接重建工具，不升级 SDK/dependencies。"""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess

SOURCE = 'packages/flutter_tools/lib/src/macos/build_macos.dart'
ORIGINAL = """    // Debug builds default to current host architecture
    destination = 'platform=${XcodeSdk.MacOSX.displayName},arch=$hostArch';
    archs = null;"""
PATCHED = """    // AnyDeck compatibility: arm64e hosts may not expose an arm64 destination.
    destination = XcodeSdk.MacOSX.genericPlatform;
    archs = hostArch;"""


def transform(text, restore=False):
    """只替换已知 Debug 分支，未知版本拒绝修改，保留所有其它代码。"""
    old, new = (PATCHED, ORIGINAL) if restore else (ORIGINAL, PATCHED)
    if text.count(old) == 1 and new not in text:
        return text.replace(old, new, 1)
    if text.count(new) == 1 and old not in text:
        return text
    raise ValueError('Flutter Debug 分支与已知版本不匹配，未修改 SDK')


def apply(sdk, restore=False):
    sdk = Path(sdk).resolve(strict=True)
    source = sdk / SOURCE
    original = source.read_text()
    replacement = transform(original, restore)
    cache = sdk / 'bin/cache'
    dart = cache / 'dart-sdk/bin/dart'
    packages = sdk / 'packages/flutter_tools/.dart_tool/package_config.json'
    snapshot = cache / 'flutter_tools.snapshot'
    if not dart.is_file() or not packages.is_file() or not snapshot.is_file():
        raise ValueError('Flutter 工具缓存不完整，请先初始化 SDK')
    backup = cache / 'anydeck_macos_debug_backup'
    backup.mkdir(exist_ok=True)
    digest = hashlib.sha256(original.encode()).hexdigest()[:16]
    backup_source = backup / f'{digest}.dart'
    if not backup_source.exists():
        backup_source.write_text(original)
    if not (backup / 'flutter_tools.snapshot').exists():
        shutil.copy2(snapshot, backup / 'flutter_tools.snapshot')
    temporary = cache / 'flutter_tools.anydeck.snapshot'
    source.write_text(replacement)
    try:
        # 使用已有 package_config 直接编译，不触发 flutter bootstrap/pub upgrade。
        subprocess.run([
            str(dart), '--verbosity=error', f'--snapshot={temporary}',
            '--snapshot-kind=app-jit', f'--packages={packages}',
            '--no-enable-mirrors', str(sdk / 'packages/flutter_tools/bin/flutter_tools.dart'),
        ], cwd=sdk, check=True, timeout=120)
        temporary.replace(snapshot)
    except BaseException:
        source.write_text(original)
        raise
    finally:
        temporary.unlink(missing_ok=True)
    return backup


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, help='默认使用 PATH 中 flutter 所属的 SDK')
    parser.add_argument('--restore', action='store_true', help='恢复原 Debug 分支并重建工具')
    args = parser.parse_args()
    executable = shutil.which('flutter')
    sdk = args.sdk or (Path(executable).resolve().parents[1] if executable else None)
    if sdk is None:
        parser.error('找不到 Flutter，请使用 --sdk 指定')
    backup = apply(sdk, args.restore)
    print(f'Flutter macOS Debug 兼容修复已{"恢复" if args.restore else "应用"}；备份：{backup}')
