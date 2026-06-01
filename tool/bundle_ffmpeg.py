#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import subprocess
import sys

# 定位 Homebrew prefix，兼容 Apple Silicon 和 Intel Mac。
BREW_PREFIX = "/opt/homebrew"
if not os.path.exists(BREW_PREFIX) and os.path.exists("/usr/local/opt/ffmpeg"):
    BREW_PREFIX = "/usr/local"

print(f"Using Homebrew prefix: {BREW_PREFIX}")

REPO_ROOT = Path(__file__).resolve().parents[1]
DEST_DIR = REPO_ROOT / "scrcpy_flutter" / "macos" / "Libs"
os.makedirs(DEST_DIR, exist_ok=True)

SEEDS = [
    f"{BREW_PREFIX}/opt/ffmpeg/lib/libavcodec.dylib",
    f"{BREW_PREFIX}/opt/ffmpeg/lib/libavformat.dylib",
    f"{BREW_PREFIX}/opt/ffmpeg/lib/libavutil.dylib",
    f"{BREW_PREFIX}/opt/ffmpeg/lib/libswscale.dylib",
    f"{BREW_PREFIX}/opt/ffmpeg/lib/libswresample.dylib",
]

def get_deps(path):
    res = subprocess.run(["otool", "-L", path], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Warning: Failed to otool {path}", file=sys.stderr)
        return []
    deps = []
    lines = res.stdout.splitlines()
    if len(lines) > 1:
        for line in lines[1:]:
            parts = line.strip().split()
            if not parts:
                continue
            dep = parts[0]
            if dep.startswith(BREW_PREFIX):
                deps.append(dep)
    return deps

todo = list(SEEDS)
copied_reals = {}          # real_path -> real_basename
real_paths_by_name = {}    # real_basename -> real_path
aliases_to_create = {}     # alias_basename -> target_basename

# Step 1: 递归解析并复制真实 dylib 文件。
while todo:
    curr = todo.pop(0)
    if not os.path.exists(curr) and not os.path.islink(curr):
        print(f"Warning: Seed/dependency path does not exist: {curr}", file=sys.stderr)
        continue

    # Walk symlink chain to recreate symlinks
    p = curr
    while os.path.islink(p):
        link_name = os.path.basename(p)
        target = os.readlink(p)
        target_abs = os.path.normpath(os.path.join(os.path.dirname(p), target))
        target_name = os.path.basename(target_abs)
        aliases_to_create[link_name] = target_name
        p = target_abs

    real_path = os.path.realpath(curr)
    real_name = os.path.basename(real_path)

    if real_path not in copied_reals:
        copied_reals[real_path] = real_name
        real_paths_by_name[real_name] = real_path
        dest_path = DEST_DIR / real_name
        if not os.path.exists(dest_path):
            print(f"Copying {real_path} -> {dest_path}")
            shutil.copy2(real_path, dest_path)
            os.chmod(dest_path, 0o755)

        # Enqueue dependencies
        deps = get_deps(real_path)
        for dep in deps:
            todo.append(dep)

# Step 2: 创建 ABI 别名文件。
#
# CocoaPods 的 vendored_libraries 在 macOS app 打包时不会稳定保留 symlink。
# FFmpeg dylib 之间依赖的是 @rpath/libavutil.60.dylib 这类 ABI 名称，
# 所以这里把别名做成真实文件副本，避免 dyld 启动阶段找不到库。
for alias_name, target_name in aliases_to_create.items():
    alias_path = DEST_DIR / alias_name
    target_path = DEST_DIR / target_name
    if not target_path.exists():
        print(
            f"Warning: Alias target does not exist: {alias_path} -> {target_name}",
            file=sys.stderr,
        )
        continue
    if alias_path.exists() or alias_path.is_symlink():
        alias_path.unlink()
    print(f"Creating dylib alias copy: {alias_path} -> {target_name}")
    shutil.copy2(target_path, alias_path)
    os.chmod(alias_path, 0o755)

def rewrite_install_names(dest_path, dylib_name, source_path):
    print(f"Setting ID: {dest_path} -> @rpath/{dylib_name}")
    subprocess.run(
        ["install_name_tool", "-id", f"@rpath/{dylib_name}", dest_path],
        check=True,
    )

    deps = get_deps(source_path)
    for dep in deps:
        dep_basename = os.path.basename(dep)
        print(f"  Changing dependency: {dep} -> @rpath/{dep_basename} in {dylib_name}")
        subprocess.run(
            ["install_name_tool", "-change", dep, f"@rpath/{dep_basename}", dest_path],
            check=True,
        )


# Step 3: 使用 install_name_tool 更新真实 dylib 的 ID 和依赖路径。
for real_path, real_name in copied_reals.items():
    dest_path = DEST_DIR / real_name
    rewrite_install_names(dest_path, real_name, real_path)

# Step 4: 同步更新别名副本，避免干净环境首次打包时残留 Homebrew 绝对路径。
for alias_name, target_name in aliases_to_create.items():
    real_path = real_paths_by_name.get(target_name)
    if real_path is None:
        continue
    alias_path = DEST_DIR / alias_name
    if alias_path.exists():
        rewrite_install_names(alias_path, alias_name, real_path)

print("FFmpeg libraries bundling completed successfully!")
