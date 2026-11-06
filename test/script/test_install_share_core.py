"""构建制品检查必须在修改 App 前拦截篡改与错误架构。"""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

from script.install_share_core import CODE_FILES, MANIFEST_PATH, ROOT, install, load_archive


class ShareCoreInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "AnyDeck.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        self.files = {name: name.encode() for name in
                      ("anydeck-share-core", "anydeck-dfile", "share-discovery", "libcrypto.3.dylib", "libssl.3.dylib")}
        self.manifest = {"schema": 1, "ipc_version": 1, "architecture": "arm64",
                         "core_version": "0.1.0", "capabilities": {"send": False},
                         "files": {name: hashlib.sha256(data).hexdigest()
                                   for name, data in self.files.items()}}

    def archive(self):
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as bundle:
            for name, data in self.files.items():
                bundle.writestr(name, data)
            bundle.writestr("manifest.json", json.dumps(self.manifest))
        return output.getvalue()

    def locked_archive(self):
        data = self.archive()
        lock = {"ipc_version": 1, "artifacts": {"arm64": {
            "sha256": hashlib.sha256(data).hexdigest(),
            "path": "artifacts/core.zip"}}}
        return data, lock

    def test_installs_exact_verified_members(self):
        data = self.archive()
        lock = {"ipc_version": 1, "artifacts": {"arm64": {
            "sha256": hashlib.sha256(data).hexdigest()}}}
        install(data, self.app, lock, "arm64")
        self.assertEqual((self.app / "Contents/MacOS/ShareCore/anydeck-share-core").read_bytes(),
                         b"anydeck-share-core")

    def test_rejects_previous_ipc_before_installing(self):
        self.manifest["ipc_version"] = 2
        data = self.archive()
        lock = {"ipc_version": 3, "artifacts": {"arm64": {
            "sha256": hashlib.sha256(data).hexdigest()}}}
        with self.assertRaises(ValueError):
            install(data, self.app, lock, "arm64")
        self.assertFalse((self.app / "Contents/MacOS/ShareCore").exists())

    def test_rejects_modified_archive_before_creating_directory(self):
        data = self.archive()
        lock = {"ipc_version": 1, "artifacts": {"arm64": {"sha256": "0" * 64}}}
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            install(data, self.app, lock, "arm64")
        self.assertFalse((self.app / "Contents/MacOS/ShareCore").exists())

    def test_incremental_install_keeps_identical_files(self):
        data, lock = self.locked_archive()
        install(data, self.app, lock, "arm64")
        core = self.app / "Contents/MacOS/ShareCore/anydeck-share-core"
        before = core.stat()
        install(data, self.app, lock, "arm64", replace=True)
        self.assertEqual(core.stat().st_ino, before.st_ino)
        self.assertEqual(core.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertEqual(core.parent.stat().st_mode & 0o777, 0o755)

    def test_default_install_still_refuses_existing_directory(self):
        data, lock = self.locked_archive()
        install(data, self.app, lock, "arm64")
        with self.assertRaisesRegex(ValueError, "fresh"):
            install(data, self.app, lock, "arm64")

    def test_incremental_install_repairs_corruption_and_removes_old_members(self):
        data, lock = self.locked_archive()
        install(data, self.app, lock, "arm64")
        destination = self.app / "Contents/MacOS/ShareCore"
        (destination / "anydeck-share-core").write_bytes(b"broken")
        (destination / "obsolete-helper").write_bytes(b"old")
        install(data, self.app, lock, "arm64", replace=True)
        self.assertEqual({p.name for p in destination.iterdir()}, CODE_FILES)
        self.assertEqual((destination / "anydeck-share-core").read_bytes(), b"anydeck-share-core")

    def test_incremental_install_restores_executable_permission(self):
        data, lock = self.locked_archive()
        install(data, self.app, lock, "arm64")
        core = self.app / "Contents/MacOS/ShareCore/anydeck-share-core"
        core.chmod(0o644)
        install(data, self.app, lock, "arm64", replace=True)
        self.assertTrue(os.access(core, os.X_OK))

    def test_invalid_replacement_preserves_existing_component(self):
        data, lock = self.locked_archive()
        install(data, self.app, lock, "arm64")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            install(data + b"tampered", self.app, lock, "arm64", replace=True)
        self.assertEqual((self.app / MANIFEST_PATH).read_text(),
                         json.dumps(self.manifest))

    def test_failed_publication_rolls_back_previous_component(self):
        data, lock = self.locked_archive()
        destination = self.app / "Contents/MacOS/ShareCore"
        destination.mkdir()
        (destination / "old").write_bytes(b"previous")
        original_rename = Path.rename

        def fail_publication(source, target):
            if source.name.startswith(".ShareCore-") and not source.name.endswith("-previous"):
                raise OSError("publish failed")
            return original_rename(source, target)

        with patch.object(Path, "rename", autospec=True, side_effect=fail_publication):
            with self.assertRaisesRegex(OSError, "publish failed"):
                install(data, self.app, lock, "arm64", replace=True)
        self.assertEqual((destination / "old").read_bytes(), b"previous")
        self.assertEqual([p.name for p in destination.parent.iterdir()], ["ShareCore"])

    def test_failed_metadata_publication_rolls_back_code_and_preserves_manifest(self):
        data, lock = self.locked_archive()
        install(data, self.app, lock, "arm64")
        core = self.app / "Contents/MacOS/ShareCore/anydeck-share-core"
        core.write_bytes(b"previous")
        original = (self.app / MANIFEST_PATH).read_bytes()
        with patch.object(Path, "replace", side_effect=OSError("metadata failed")):
            with self.assertRaisesRegex(OSError, "metadata failed"):
                install(data, self.app, lock, "arm64", replace=True)
        self.assertEqual(core.read_bytes(), b"previous")
        self.assertEqual((self.app / MANIFEST_PATH).read_bytes(), original)
        self.assertEqual([p.name for p in (self.app / MANIFEST_PATH).parent.iterdir()], ["manifest.json"])

    def test_incremental_install_migrates_previous_manifest_layout(self):
        data, lock = self.locked_archive()
        destination = self.app / "Contents/MacOS/ShareCore"
        destination.mkdir()
        (destination / "manifest.json").write_text("old layout")
        install(data, self.app, lock, "arm64", replace=True)
        self.assertEqual({p.name for p in destination.iterdir()}, CODE_FILES)
        self.assertEqual(json.loads((self.app / MANIFEST_PATH).read_text()), self.manifest)

    def test_refuses_symlink_destination(self):
        data, lock = self.locked_archive()
        outside = Path(self.temporary.name) / "outside"
        outside.mkdir()
        (self.app / "Contents/MacOS/ShareCore").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "regular"):
            install(data, self.app, lock, "arm64", replace=True)
        self.assertEqual(list(outside.iterdir()), [])

    def test_rejects_duplicate_zip_members(self):
        data, lock = self.locked_archive()
        output = io.BytesIO(data)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(output, "a") as bundle:
                bundle.writestr("manifest.json", json.dumps(self.manifest))
        data = output.getvalue()
        lock["artifacts"]["arm64"]["sha256"] = hashlib.sha256(data).hexdigest()
        with self.assertRaisesRegex(ValueError, "contents"):
            install(data, self.app, lock, "arm64")

    def test_rejects_member_hash_mismatch_before_installing(self):
        self.files["anydeck-share-core"] = b"tampered member"
        data, lock = self.locked_archive()
        with self.assertRaisesRegex(ValueError, "member SHA-256"):
            install(data, self.app, lock, "arm64")
        self.assertFalse((self.app / "Contents/MacOS/ShareCore").exists())

    def test_rejects_wrong_manifest_architecture(self):
        self.manifest["architecture"] = "x86_64"
        data, lock = self.locked_archive()
        with self.assertRaisesRegex(ValueError, "manifest"):
            install(data, self.app, lock, "arm64")
        self.assertFalse((self.app / "Contents/MacOS/ShareCore").exists())

    def build_workspace(self):
        """用离线小制品运行真实构建入口，包含带空格的 Xcode 产物路径。"""
        data, lock = self.locked_archive()
        root = Path(self.temporary.name) / "Workspace With Spaces"
        (root / "script").mkdir(parents=True)
        for name in ("install_share_core.py", "embed_share_core.sh"):
            shutil.copyfile(ROOT / "script" / name, root / "script" / name)
        (root / "script/share_core.lock.json").write_text(json.dumps(lock))
        sibling = root.parent / "AnyDeck-Share-Core/artifacts/core.zip"
        sibling.parent.mkdir(parents=True)
        sibling.write_bytes(data)
        return root, data, lock

    def run_build(self, root, configuration="Debug", architecture="arm64", archive=None):
        product = root / "Build Products" / configuration
        (product / "AnyDeck.app/Contents/MacOS").mkdir(parents=True, exist_ok=True)
        env = {key: value for key, value in os.environ.items()
               if key not in ("ANYDECK_SHARE_CORE", "ANYDECK_SHARE_CORE_ARCHIVE")}
        # 旧 opt-in 值不再决定是否带组件。
        env.update(TARGET_BUILD_DIR=str(product), WRAPPER_NAME="AnyDeck.app",
                   CONFIGURATION=configuration, ARCHS=architecture, ANYDECK_SHARE_CORE="0")
        if archive is not None:
            env["ANYDECK_SHARE_CORE_ARCHIVE"] = str(archive)
        return subprocess.run(["/bin/bash", str(root / "script/embed_share_core.sh")],
                              env=env, capture_output=True, text=True, timeout=15), product

    def test_debug_and_release_build_entry_install_without_opt_in(self):
        root, _, _ = self.build_workspace()
        for configuration in ("Debug", "Release"):
            with self.subTest(configuration=configuration):
                result, product = self.run_build(root, configuration)
                self.assertEqual(result.returncode, 0, result.stderr)
                core = product / "AnyDeck.app/Contents/MacOS/ShareCore/anydeck-share-core"
                self.assertEqual(core.read_bytes(), b"anydeck-share-core")
                again, _ = self.run_build(root, configuration)
                self.assertEqual(again.returncode, 0, again.stderr)

    def test_build_fails_for_invalid_explicit_archive(self):
        root, _, _ = self.build_workspace()
        invalid = root / "invalid.zip"
        invalid.write_bytes(b"tampered")
        result, product = self.run_build(root, archive=invalid)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA-256 mismatch", result.stderr)
        self.assertFalse((product / "AnyDeck.app/Contents/MacOS/ShareCore").exists())

    def test_build_refuses_unpinned_target_and_universal_architectures(self):
        root, _, _ = self.build_workspace()
        for architecture in ("x86_64", "arm64 x86_64"):
            with self.subTest(architecture=architecture):
                result, product = self.run_build(root, architecture=architecture)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("architecture", result.stderr)
                self.assertFalse((product / "AnyDeck.app/Contents/MacOS/ShareCore").exists())

    def test_archive_cache_works_without_private_checkout_or_network(self):
        root, data, lock = self.build_workspace()
        with patch("script.install_share_core.fetch_archive") as fetch:
            self.assertEqual(load_archive(lock, "arm64", root=root), data)
            shutil.rmtree(root.parent / "AnyDeck-Share-Core")
            self.assertEqual(load_archive(lock, "arm64", root=root), data)
            fetch.assert_not_called()

    def test_invalid_cache_is_repaired_from_verified_sibling(self):
        root, data, lock = self.build_workspace()
        cache = root / "build/share_core" / (lock["artifacts"]["arm64"]["sha256"] + ".zip")
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b"corrupted")
        with patch("script.install_share_core.fetch_archive") as fetch:
            self.assertEqual(load_archive(lock, "arm64", root=root), data)
            fetch.assert_not_called()
        self.assertEqual(cache.read_bytes(), data)

    def test_absent_local_artifact_fetches_pinned_archive_once(self):
        root, data, lock = self.build_workspace()
        shutil.rmtree(root.parent / "AnyDeck-Share-Core")
        with patch("script.install_share_core.fetch_archive", return_value=data) as fetch:
            self.assertEqual(load_archive(lock, "arm64", root=root), data)
            self.assertEqual(load_archive(lock, "arm64", root=root), data)
            fetch.assert_called_once_with(lock, "arm64")

    def test_wrong_remote_artifact_is_never_cached(self):
        root, _, lock = self.build_workspace()
        shutil.rmtree(root.parent / "AnyDeck-Share-Core")
        with patch("script.install_share_core.fetch_archive", return_value=b"wrong"):
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                load_archive(lock, "arm64", root=root)
        self.assertFalse((root / "build/share_core").exists())


if __name__ == "__main__":
    unittest.main()
