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
FILES = {"anydeck-share-core", "anydeck-dfile", "libcrypto.3.dylib", "libssl.3.dylib", "manifest.json"}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def fetch_archive(lock, architecture):
    """固定commit并仅从私有Git读取指定artifact blob；不写入AnyDeck仓库。"""
    with tempfile.TemporaryDirectory(prefix="anydeck-share-fetch-") as temporary:
        subprocess.run(["git", "clone", "--quiet", "--filter=blob:none", "--no-checkout",
                        lock["repository"], temporary], check=True, timeout=120)
        actual = subprocess.check_output(["git", "-C", temporary, "rev-parse", "HEAD"], text=True).strip()
        if actual != lock["commit"]:
            # 只从该仓库取固定对象；不可隐式升级到最新版本。
            subprocess.run(["git", "-C", temporary, "fetch", "--quiet", "origin", lock["commit"]],
                           check=True, timeout=120)
        return subprocess.check_output(["git", "-C", temporary, "show",
                                        lock["commit"] + ":" + lock["artifacts"][architecture]["path"]],
                                       timeout=60)


def install(archive, app, lock, architecture):
    expected = lock["artifacts"][architecture]["sha256"]
    if sha256(archive) != expected:
        raise ValueError("private artifact SHA-256 mismatch")
    with zipfile.ZipFile(__import__("io").BytesIO(archive)) as bundle:
        if set(bundle.namelist()) != FILES or sum(info.file_size for info in bundle.infolist()) > 16 * 1024 * 1024:
            raise ValueError("unexpected artifact contents")
        manifest = json.loads(bundle.read("manifest.json"))
        if manifest.get("schema") != 1 or manifest.get("ipc_version") != lock["ipc_version"] or manifest.get("architecture") != architecture:
            raise ValueError("incompatible artifact manifest")
        if set(manifest.get("files", {})) != FILES - {"manifest.json"}:
            raise ValueError("invalid artifact file list")
        for name in FILES - {"manifest.json"}:
            if sha256(bundle.read(name)) != manifest["files"][name]:
                raise ValueError("artifact member SHA-256 mismatch")
        parent = app / "Contents/MacOS"
        if not parent.is_dir() or (parent / "ShareCore").exists():
            raise ValueError("expected fresh AnyDeck.app bundle")
        staging = parent / (".ShareCore-" + str(os.getpid()))
        staging.mkdir(mode=0o700)
        try:
            for name in FILES:
                destination = staging / name
                destination.write_bytes(bundle.read(name))
                destination.chmod(0o644 if name == "manifest.json" else 0o755)
            staging.rename(parent / "ShareCore")
        except BaseException:
            shutil.rmtree(staging)
            raise
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--archive", type=Path, help="已有的私有artifact zip；省略则按lock从Git读取")
    args = parser.parse_args()
    architecture = platform.machine()
    lock = json.loads(LOCK.read_text())
    if architecture not in lock["artifacts"]:
        parser.error(f"no pinned Share Core artifact for {architecture}")
    archive = args.archive.read_bytes() if args.archive else fetch_archive(lock, architecture)
    manifest = install(archive, args.app, lock, architecture)
    print(json.dumps({"event": "share_core_installed", "architecture": architecture,
                      "core_version": manifest["core_version"], "capabilities": manifest["capabilities"]}))


if __name__ == "__main__":
    main()
