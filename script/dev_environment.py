#!/usr/bin/env python3
"""读取仓库版本约束，为 CLI、IDE 与 CI 提供同一工具链环境。"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(arguments, *, env=None, cwd=ROOT):
    """短查询有超时，失败直接暴露命令诊断，不隐式切换工具链。"""
    return subprocess.check_output(
        [str(arg) for arg in arguments], cwd=cwd, env=env,
        text=True, stderr=subprocess.PIPE, timeout=60).strip()


def versions(root=ROOT):
    """各工具的权威配置只保存一份，CI 不另外硬编码版本。"""
    flutter = json.loads((root / '.fvmrc').read_text())['flutter']
    rust = re.search(r'^channel\s*=\s*"([^"]+)"',
                     (root / 'rust-toolchain.toml').read_text(), re.M)[1]
    pods = re.search(r'gem "cocoapods", "([^"]+)"', (root / 'Gemfile').read_text())[1]
    bundler = re.search(r'BUNDLED WITH\s+([\d.]+)', (root / 'Gemfile.lock').read_text())[1]
    return dict(flutter=flutter, rust=rust, cocoapods=pods, bundler=bundler)


def rustup_path():
    """优先使用用户目录中的 rustup，拒绝把 Homebrew cargo 当作版本管理器。"""
    local = Path.home() / '.cargo/bin/rustup'
    executable = str(local) if local.is_file() else shutil.which('rustup')
    if not executable and shutil.which('brew'):
        candidate = Path(run(['brew', '--prefix'])) / 'opt/rustup/bin/rustup'
        if candidate.is_file():
            executable = str(candidate)
    if not executable:
        raise ValueError('缺少 rustup，请执行 ./script/setup_dev.sh')
    return executable


def cargo_path():
    return Path(run([rustup_path(), 'which', '--toolchain', versions()['rust'], 'cargo']))


def environment():
    """显式选择 SDK 和 Rust，避免 GUI 继承旧 PATH 或个人 CARGO wrapper。"""
    sdk = ROOT / '.fvm/flutter_sdk'
    if not (sdk / 'bin/flutter').is_file():
        raise ValueError('缺少 .fvm/flutter_sdk，请执行 ./script/setup_dev.sh')
    cargo = cargo_path()
    env = dict(os.environ)
    paths = [str(sdk / 'bin'), str(cargo.parent)]
    if sys.platform == 'darwin' and shutil.which('brew'):
        ruby_bin = Path(run(['brew', '--prefix', 'ruby'])) / 'bin'
        if ruby_bin.is_dir():
            paths.append(str(ruby_bin))
    env.update(PATH=os.pathsep.join(paths + [env.get('PATH', '')]),
               CARGO=str(cargo), RUSTC=str(cargo.with_name('rustc')),
               RUSTUP_TOOLCHAIN=versions()['rust'],
               FLUTTER_BIN=str(sdk / 'bin/flutter'), BUNDLE_GEMFILE=str(ROOT / 'Gemfile'),
               BUNDLE_FROZEN='true')
    # 使用锁文件中的 hosted 源，避免 pub get 因个人镜像设置改写依赖锁。
    hosts = set(re.findall(r'url: "([^"]+)"', (ROOT / 'pubspec.lock').read_text()))
    if len(hosts) != 1:
        raise ValueError('pubspec.lock 必须只有一个 hosted 源，请先明确依赖源')
    env['PUB_HOSTED_URL'] = hosts.pop()
    # 离线模式属于单机偏好，新电脑初始化不能继承旧 IDE 的离线开关。
    env.pop('CARGO_NET_OFFLINE', None)
    return env


def verify_flutter(env):
    actual = json.loads(run([env['FLUTTER_BIN'], '--version', '--machine'], env=env))
    expected = versions()['flutter']
    if actual['frameworkVersion'] != expected or actual['channel'] != 'stable':
        raise ValueError(f'Flutter 必须为 stable {expected}，实际为 '
                         f"{actual['channel']} {actual['frameworkVersion']}")
    # 新基线使用官方原始 SDK；历史 3.47.2 Debug 补丁不能静默带入。
    changed = run(['git', '-C', str(ROOT / '.fvm/flutter_sdk'), 'diff', 'HEAD', '--name-only',
                   '--', 'packages/flutter_tools', 'bin/internal'], env=env)
    if changed:
        raise ValueError(f'Flutter SDK 含未管理的工具补丁：{changed}')
    return actual


def check(require_share_core=False):
    """默认只读检查；--share-core 可获取锁定制品，不构建或启动 App。"""
    env = environment()
    expected = versions()
    flutter = verify_flutter(env)
    print(f"Flutter stable {flutter['frameworkVersion']} / Dart {flutter['dartSdkVersion']}")
    for tool in ('cargo', 'rustc'):
        actual = run([env['CARGO'] if tool == 'cargo' else env['RUSTC'], '--version'], env=env)
        if actual.split()[1] != expected['rust']:
            raise ValueError(f'{tool} 版本不一致：{actual}')
        print(actual)
    arch = os.environ.get('ANYDECK_TARGET_ARCH', platform.machine())
    targets = {'arm64': 'aarch64-apple-darwin', 'arm64e': 'aarch64-apple-darwin',
               'x86_64': 'x86_64-apple-darwin'}
    if sys.platform == 'darwin':
        if arch not in targets:
            raise ValueError(f'不支持的 macOS 目标架构：{arch}')
        installed = run([rustup_path(), 'target', 'list', '--installed',
                         '--toolchain', expected['rust']], env=env).splitlines()
        if targets[arch] not in installed:
            raise ValueError(f'缺少 Rust target：{targets[arch]}')
        bundle = ['bundle', f"_{expected['bundler']}_"]
        run(bundle + ['check'], env=env)
        pods = run(bundle + ['exec', 'pod', '--version'], env=env)
        if pods != expected['cocoapods']:
            raise ValueError(f'CocoaPods 版本不一致：{pods}')
        run(bundle + ['exec', 'ruby', '-e', "require 'cfpropertylist'; require 'kconv'"], env=env)
        print(f'CocoaPods {pods} / Bundler {expected["bundler"]}')
        print(run(['xcodebuild', '-version'], env=env))
        run(['xcrun', '--find', 'clang'], env=env)
        for package in ('openssl', 'libplist-2.0'):
            prefix = run(['brew', '--prefix'], env=env)
            pkg_env = dict(env, PKG_CONFIG_PATH=os.pathsep.join([
                f'{prefix}/opt/openssl@3/lib/pkgconfig',
                f'{prefix}/opt/libplist/lib/pkgconfig', env.get('PKG_CONFIG_PATH', '')]))
            minimum = '3.0' if package == 'openssl' else '2.3'
            run(['pkg-config', f'--atleast-version={minimum}', package], env=pkg_env)
            print(f'{package} {run(["pkg-config", "--modversion", package], env=pkg_env)}')
    for name in ('pubspec.lock', 'rust/device_bridge/Cargo.lock',
                 'rust/apk_inspector/Cargo.lock', 'macos/Podfile.lock'):
        if not (ROOT / name).is_file():
            raise ValueError(f'缺少依赖锁：{name}')
    if require_share_core:
        from install_share_core import load_archive
        lock = json.loads((ROOT / 'script/share_core.lock.json').read_text())
        load_archive(lock, 'arm64' if arch == 'arm64e' else arch)
        print('Share Core 固定版本制品校验通过')
    else:
        print('Share Core 未检查；完整 Release 请另执行 --share-core（可能下载制品）')
    print('AnyDeck 开发环境检查通过')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('check', 'exec', 'cargo-path', 'versions'))
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == 'versions':
        print(json.dumps(versions()))
    elif args.action == 'cargo-path':
        print(cargo_path())
    elif args.action == 'check':
        if args.arguments not in ([], ['--share-core']):
            parser.error('check 仅支持 --share-core')
        check(bool(args.arguments))
    else:
        if not args.arguments:
            parser.error('exec 需要命令和参数')
        env = environment()
        verify_flutter(env)
        command = args.arguments
        if sys.platform == 'darwin':
            command = ['bundle', f"_{versions()['bundler']}_", 'exec', *command]
        os.chdir(ROOT)
        os.execvpe(command[0], command, env)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'error: {error}', file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr or '', file=sys.stderr)
        sys.exit(1)
