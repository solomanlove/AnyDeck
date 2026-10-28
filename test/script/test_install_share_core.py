"""构建制品检查必须在修改 App 前拦截篡改与错误架构。"""
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from script.install_share_core import install


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


if __name__ == "__main__":
    unittest.main()
