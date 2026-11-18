#!/usr/bin/env python3
"""准备 AnyDeck 工具链；不升级业务依赖，不构建或启动 App。"""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

from dev_environment import ROOT, check, environment, run, rustup_path, verify_flutter, versions


def execute(arguments, env=None, cwd=ROOT):
    """安装过程显示进度；为网络或工具挂起设置总体上限。"""
    print('+ ' + ' '.join(map(str, arguments)), flush=True)
    subprocess.run(list(map(str, arguments)), cwd=cwd, env=env, check=True, timeout=1800)


def configure_ide(env):
    """保留用户运行参数，只替换本次统一的工具链环境与 SDK 路径。"""
    from configure_flutter_ide import configure
    configure(ROOT, ROOT / '.fvm/flutter_sdk')
    bundled = run(['bundle', f"_{versions()['bundler']}_", 'exec', 'env'], env=env)
    allowed = {'PATH', 'CARGO', 'RUSTC', 'RUSTUP_TOOLCHAIN', 'PUB_HOSTED_URL',
               'BUNDLE_GEMFILE', 'BUNDLE_BIN_PATH', 'BUNDLE_PATH', 'BUNDLE_FROZEN',
               'RUBYOPT', 'GEM_HOME', 'GEM_PATH'}
    values = dict(line.split('=', 1) for line in bundled.splitlines()
                  if '=' in line and line.split('=', 1)[0] in allowed)
    for name in ('AnyDeck.xml', 'AnyDeck_No_Share_Core.xml'):
        file = ROOT / '.idea/runConfigurations' / name
        tree = ET.parse(file)
        config = tree.getroot().find('configuration')
        option = config.find("option[@name='envs']")
        if option is None:
            option = ET.SubElement(config, 'option', {'name': 'envs'})
        for entry in list(option):
            if entry.get('key') in allowed | {'CARGO_NET_OFFLINE'}:
                option.remove(entry)
        for key, value in sorted(values.items()):
            ET.SubElement(option, 'entry', {'key': key, 'value': value})
        file.write_text(ET.tostring(tree.getroot(), encoding='unicode') + '\n')


def prepare_macos_config(env):
    """刷新旧 SDK 的 xcconfig/SPM 引用；Flutter 不得静默改写依赖锁。"""
    lock = ROOT / 'macos/Podfile.lock'
    original = lock.read_bytes()
    try:
        execute(['bundle', f"_{versions()['bundler']}_", 'exec', env['FLUTTER_BIN'],
                 'build', 'macos', '--debug', '--config-only', '--no-pub'], env)
    finally:
        if not lock.is_file() or lock.read_bytes() != original:
            lock.write_bytes(original)
            raise ValueError('Flutter 配置准备改变了 Podfile.lock，已恢复；请单独审核原生依赖迁移')


def setup(skip_native=False, ide=False):
    if sys.platform != 'darwin':
        raise ValueError('当前初始化入口支持 macOS；其他平台尚未验证')
    if not shutil.which('brew'):
        raise ValueError('请先安装 Homebrew 与完整 Xcode')
    run(['xcodebuild', '-version'])
    if not skip_native:
        execute(['brew', 'bundle', '--file', ROOT / 'Brewfile'])
    # 不覆盖 Homebrew Rust，不更改 shell 配置；通过 rustup 定位独立 toolchain。
    try:
        rustup_path()
    except ValueError:
        execute(['brew', 'install', 'rustup'])
    pinned = versions()
    execute([rustup_path(), 'toolchain', 'install', pinned['rust'], '--profile', 'minimal',
             '--component', 'rustfmt,clippy'])
    arch = os.environ.get('ANYDECK_TARGET_ARCH', platform.machine())
    target = {'arm64': 'aarch64-apple-darwin', 'arm64e': 'aarch64-apple-darwin',
              'x86_64': 'x86_64-apple-darwin'}.get(arch)
    if target is None:
        raise ValueError(f'不支持的目标架构：{arch}')
    execute([rustup_path(), 'target', 'add', target, '--toolchain', pinned['rust']])
    if not shutil.which('fvm'):
        raise ValueError('请先安装 FVM：https://fvm.app/documentation/getting-started/installation')
    execute(['fvm', 'install', pinned['flutter'], '--skip-pub-get'])
    execute(['fvm', 'use', pinned['flutter'], '--force', '--skip-pub-get'])
    ruby_bin = Path(run(['brew', '--prefix', 'ruby'])) / 'bin'
    if not (ruby_bin / 'ruby').is_file():
        execute(['brew', 'install', 'ruby'])
    gem_env = dict(os.environ, PATH=f'{ruby_bin}{os.pathsep}{os.environ.get("PATH", "")}')
    try:
        run(['bundle', f"_{pinned['bundler']}_", '--version'], env=gem_env)
    except (OSError, subprocess.CalledProcessError):
        execute(['gem', 'install', 'bundler', '-v', pinned['bundler'], '--no-document'], gem_env)
    env = environment()
    verify_flutter(env)
    bundle = ['bundle', f"_{pinned['bundler']}_"]
    execute(bundle + ['config', 'set', '--local', 'path', 'vendor/bundle'], env)
    # frozen 禁止初始化时静默改动团队锁定的 gem 版本。
    try:
        run(bundle + ['check'], env=env)
    except subprocess.CalledProcessError:
        execute(bundle + ['install'], env)
    execute([env['FLUTTER_BIN'], 'config', '--no-enable-macos-arm64-only'], env)
    execute([env['FLUTTER_BIN'], 'pub', 'get', '--enforce-lockfile'], env)
    prepare_macos_config(env)
    for crate in ('device_bridge', 'apk_inspector'):
        execute([env['CARGO'], 'fetch', '--locked', '--target', target,
                 '--manifest-path', ROOT / 'rust' / crate / 'Cargo.toml'], env)
    # --deployment 确保不把单机 CocoaPods 差异写回已提交的 Podfile.lock。
    execute(bundle + ['exec', 'pod', 'install', '--deployment'], env, cwd=ROOT / 'macos')
    if ide:
        configure_ide(env)
    check()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-native', action='store_true', help='复用已安装的 Homebrew 原生依赖')
    parser.add_argument('--ide', action='store_true', help='更新本机 Android Studio 运行配置')
    args = parser.parse_args()
    try:
        setup(args.skip_native, args.ide)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'初始化失败：{error}\n')


if __name__ == '__main__':
    main()
