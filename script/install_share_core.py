#!/usr/bin/env python3
"""仅解压已锁定的私有二进制制品到AnyDeck.app，不检出协议源码。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "script/share_core.lock.json"
FILES = {"anydeck-share-core", "anydeck-dfile", "share-discovery", "share-network", "libcrypto.3.dylib", "libssl.3.dylib", "manifest.json"}
CODE_FILES = FILES - {"manifest.json"}
MANIFEST_PATH = "Contents/Resources/ShareCore/manifest.json"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def fetch_archive(lock, architecture):
    """固定commit并仅从私有Git读取指定artifact blob；不写入AnyDeck仓库。"""
    with tempfile.TemporaryDirectory(prefix="anydeck-share-fetch-") as temporary:
        subprocess.run(["git", "clone", "--quiet", "--filter=blob:none", "--no-checkout",
                        lock["repository"], temporary], check=True, timeout=120)
        actual = subprocess.check_output(["git", "-C", temporary, "rev-parse", "HEAD"],
                                         text=True, timeout=15).strip()
        if actual != lock["commit"]:
            # 只从该仓库取固定对象；不可隐式升级到最新版本。
            subprocess.run(["git", "-C", temporary, "fetch", "--quiet", "origin", lock["commit"]],
                           check=True, timeout=120)
        return subprocess.check_output(["git", "-C", temporary, "show",
                                        lock["commit"] + ":" + lock["artifacts"][architecture]["path"]],
                                       timeout=60)


def load_archive(lock, architecture, archive=None, root=ROOT):
    """优先复用已校验缓存/相邻私有制品；首次缺失时按固定 commit 获取。"""
    artifact = lock["artifacts"][architecture]
    expected = artifact["sha256"]
    cache = root / "build/share_core" / (expected + ".zip")
    sibling = root.parent / "AnyDeck-Share-Core" / artifact["path"]
    data = None
    if archive is not None:
        data = archive.read_bytes()
        if sha256(data) != expected:
            raise ValueError("private artifact SHA-256 mismatch")
    else:
        for candidate in (cache, sibling):
            if candidate.is_file():
                candidate_data = candidate.read_bytes()
                if sha256(candidate_data) == expected:
                    data = candidate_data
                    break
        if data is None:
            data = fetch_archive(lock, architecture)
            if sha256(data) != expected:
                raise ValueError("private artifact SHA-256 mismatch")
    if not cache.is_file() or sha256(cache.read_bytes()) != expected:
        cache.parent.mkdir(parents=True, exist_ok=True)
        # 并行构建只发布完整缓存，读者仍独立检查 SHA-256。
        with tempfile.NamedTemporaryFile(dir=cache.parent, delete=False) as staged:
            temporary = Path(staged.name)
            try:
                staged.write(data)
                staged.close()
                temporary.replace(cache)
            finally:
                temporary.unlink(missing_ok=True)
    return data


def install(archive, app, lock, architecture, replace=False):
    """先完整校验再安装；构建模式可原子更新已有组件并在发布失败时回滚。"""
    expected = lock["artifacts"][architecture]["sha256"]
    if sha256(archive) != expected:
        raise ValueError("private artifact SHA-256 mismatch")
    with zipfile.ZipFile(__import__("io").BytesIO(archive)) as bundle:
        if (set(bundle.namelist()) != FILES or len(bundle.namelist()) != len(FILES)
                or sum(info.file_size for info in bundle.infolist()) > 16 * 1024 * 1024):
            raise ValueError("unexpected artifact contents")
        manifest = json.loads(bundle.read("manifest.json"))
        if manifest.get("schema") != 1 or manifest.get("ipc_version") != lock["ipc_version"] or manifest.get("architecture") != architecture:
            raise ValueError("incompatible artifact manifest")
        if set(manifest.get("files", {})) != CODE_FILES:
            raise ValueError("invalid artifact file list")
        for name in CODE_FILES:
            if sha256(bundle.read(name)) != manifest["files"][name]:
                raise ValueError("artifact member SHA-256 mismatch")
        parent = app / "Contents/MacOS"
        destination = parent / "ShareCore"
        metadata = app / MANIFEST_PATH
        if not parent.is_dir() or destination.is_symlink():
            raise ValueError("expected AnyDeck.app bundle with a regular ShareCore directory")
        if any(path.is_symlink() for path in (metadata, metadata.parent, metadata.parent.parent)):
            raise ValueError("expected regular ShareCore metadata path")
        if destination.exists() and (not replace or not destination.is_dir()):
            raise ValueError("expected fresh AnyDeck.app bundle")
        if (destination.exists() and {p.name for p in destination.iterdir()} == CODE_FILES
                and metadata.is_file() and metadata.read_bytes() == bundle.read("manifest.json")):
            if all((destination / name).is_file() and not (destination / name).is_symlink()
                   and (destination / name).read_bytes() == bundle.read(name)
                   and os.access(destination / name, os.X_OK) for name in CODE_FILES):
                return manifest
        staging = Path(tempfile.mkdtemp(prefix=".ShareCore-", dir=parent))
        backup = None
        staged_metadata = None
        try:
            for name in CODE_FILES:
                member = staging / name
                member.write_bytes(bundle.read(name))
                member.chmod(0o755)
            staging.chmod(0o755)
            # manifest 属于资源，不能放在 MacOS 嵌套代码目录中触发额外重签。
            metadata.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=metadata.parent, delete=False) as staged:
                staged_metadata = Path(staged.name)
                staged.write(bundle.read("manifest.json"))
            staged_metadata.chmod(0o644)
            if destination.exists():
                backup = staging.with_name(staging.name + "-previous")
                destination.rename(backup)
            published = False
            try:
                staging.rename(destination)
                published = True
                staged_metadata.replace(metadata)
            except BaseException:
                if published:
                    shutil.rmtree(destination)
                if backup is not None:
                    backup.rename(destination)
                raise
            if backup is not None:
                shutil.rmtree(backup)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
            if staged_metadata is not None:
                staged_metadata.unlink(missing_ok=True)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--archive", type=Path, help="已有的私有artifact zip；省略则复用校验缓存或获取锁定制品")
    parser.add_argument("--architecture", default=platform.machine(), help="目标架构，不能用宿主架构替代交叉构建目标")
    parser.add_argument("--replace", action="store_true", help="供增量构建校验并原子更新包内组件")
    args = parser.parse_args()
    architecture = args.architecture
    lock = json.loads(LOCK.read_text())
    if architecture not in lock["artifacts"]:
        parser.error(f"no pinned Share Core artifact for {architecture}")
    try:
        archive = load_archive(lock, architecture, args.archive)
        manifest = install(archive, args.app, lock, architecture, replace=args.replace)
    except (OSError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"error: Share Core installation failed: {error}\n"
                    "Provide access to the pinned private artifact or set ANYDECK_SHARE_CORE_ARCHIVE.\n")
    print(json.dumps({"event": "share_core_installed", "architecture": architecture,
                      "core_version": manifest["core_version"], "capabilities": manifest["capabilities"]}))


if __name__ == "__main__":
    main()
