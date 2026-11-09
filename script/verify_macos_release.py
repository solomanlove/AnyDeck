#!/usr/bin/env python3
"""分发前验证 AnyDeck 架构、嵌套签名、必需组件及开发机动态库泄漏。"""
import os
from pathlib import Path
import plistlib
import subprocess
import sys

MACHO_MAGIC = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
               b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
REQUIRED = (
    'Contents/MacOS/AnyDeck',
    'Contents/Frameworks/libanydeck_device_bridge.dylib',
    'Contents/Helpers/anydeck-apk-inspector',
    'Contents/Resources/ShareCore/manifest.json',
    *('Contents/MacOS/ShareCore/' + name for name in (
        'anydeck-share-core', 'anydeck-dfile', 'share-discovery', 'share-network',
        'libcrypto.3.dylib', 'libssl.3.dylib')),
)


def verify(app):
    """失败即终止打包；只允许系统绝对链接和包内相对链接。"""
    app = app.resolve(strict=True)
    for name in REQUIRED:
        if not (app / name).is_file():
            raise ValueError(f'缺少分发组件: {name}')
    metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = metadata['CFBundleShortVersionString']
    tag = os.environ.get('GITHUB_REF_NAME', '')
    if os.environ.get('GITHUB_REF_TYPE') == 'tag' and tag != 'v' + version:
        raise ValueError(f'Tag {tag} 与 App 版本 v{version} 不一致')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.run(['codesign', '-dv', str(app)], capture_output=True,
                               text=True, check=True).stderr
    if 'Signature=adhoc' not in signature:
        raise ValueError('当前发布通道要求 ad-hoc 签名')
    binaries = 0
    for path in app.rglob('*'):
        if path.is_symlink():
            path.resolve(strict=True).relative_to(app)
            continue
        if not path.is_file():
            continue
        with path.open('rb') as stream:
            if stream.read(4) not in MACHO_MAGIC:
                continue
        binaries += 1
        subprocess.run(['lipo', str(path), '-verify_arch', 'arm64'], check=True)
        links = subprocess.check_output(['otool', '-L', str(path)], text=True)
        for line in links.splitlines():
            if not line.startswith('\t'):
                continue
            dependency = line.strip().split(' (', 1)[0]
            if not dependency.startswith(('@rpath/', '@loader_path/', '@executable_path/',
                                          '/System/Library/', '/usr/lib/')):
                raise ValueError(f'非便携动态库依赖: {path.name}: {dependency}')
            # Flutter 自带一些未使用的开发机 RPATH；检查实际引用能否在包内找到。
            if dependency.startswith('@rpath/'):
                relative = dependency.removeprefix('@rpath/')
                if not (app / 'Contents/Frameworks' / relative).is_file():
                    raise ValueError(f'未随包分发的 Framework: {path.name}: {dependency}')
            elif dependency.startswith(('@loader_path/', '@executable_path/')):
                # Share Core 是独立启动的 helper，其 executable_path 指向自己的目录。
                local_helper = path.is_relative_to(app / 'Contents/MacOS/ShareCore')
                base = path.parent if dependency.startswith('@loader_path/') or local_helper else app / 'Contents/MacOS'
                target = (base / dependency.split('/', 1)[1]).resolve(strict=True)
                target.relative_to(app)
    print(f'AnyDeck {version}: ad-hoc 签名、arm64 与 {binaries} 个 Mach-O 文件验证通过')


if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        sys.exit(f'发布验证失败: {error}')
