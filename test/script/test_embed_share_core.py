"""真实执行构建阶段，确保仅显式 Debug 验收可跳过私有制品安装。"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "script/embed_share_core.sh"


class EmbedShareCoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="anydeck-share-skip-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.app = self.directory / "AnyDeck.app"
        self.calls = self.directory / "python-calls.txt"
        binary = self.directory / "bin"
        binary.mkdir()
        python = binary / "python3"
        python.write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$@" > "$ANYDECK_SHARE_TEST_CALL_LOG"\n'
            'exit "${ANYDECK_SHARE_TEST_EXIT:-0}"\n'
        )
        python.chmod(0o755)
        self.environment = dict(os.environ)
        for name in ("ANYDECK_SKIP_SHARE_CORE", "CONFIGURATION", "ANYDECK_SHARE_CORE_ARCHIVE"):
            self.environment.pop(name, None)
        self.environment.update({
            "PATH": f"{binary}:{self.environment.get('PATH', '')}",
            "ANYDECK_SHARE_TEST_CALL_LOG": str(self.calls),
            "TARGET_BUILD_DIR": str(self.directory),
            "WRAPPER_NAME": "AnyDeck.app",
            "ARCHS": "arm64",
        })

    def run_script(self, **environment):
        return subprocess.run(
            ["/bin/bash", str(SCRIPT)],
            env={**self.environment, **environment},
            text=True,
            capture_output=True,
            timeout=5,
        )

    def test_explicit_debug_skip_does_not_create_app_or_invoke_installer(self):
        result = self.run_script(ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Share Core is skipped", result.stdout)
        self.assertFalse(self.app.exists())
        self.assertFalse(self.calls.exists())

    def test_explicit_debug_skip_removes_only_target_app_share_core(self):
        component = self.app / "Contents/MacOS/ShareCore/helper"
        component.parent.mkdir(parents=True)
        component.write_bytes(b"existing-artifact")
        metadata = self.app / "Contents/Resources/ShareCore/manifest.json"
        metadata.parent.mkdir(parents=True)
        metadata.write_text('{"old": true}')
        runner = self.app / "Contents/MacOS/AnyDeck"
        runner.write_bytes(b"keep-runner")
        other = self.directory / "Other.app/Contents/MacOS/ShareCore/helper"
        other.parent.mkdir(parents=True)
        other.write_bytes(b"keep-other-app")
        result = self.run_script(
            ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug",
            ANYDECK_SHARE_CORE_ARCHIVE="/missing/private-artifact.zip",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(component.parent.exists())
        self.assertFalse(metadata.parent.exists())
        self.assertEqual(runner.read_bytes(), b"keep-runner")
        self.assertEqual(other.read_bytes(), b"keep-other-app")
        self.assertFalse(self.calls.exists())

    def test_debug_skip_without_share_core_directories_is_idempotent(self):
        runner = self.app / "Contents/MacOS/AnyDeck"
        runner.parent.mkdir(parents=True)
        runner.write_bytes(b"keep-runner")
        for _ in range(2):
            result = self.run_script(ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(runner.read_bytes(), b"keep-runner")
        self.assertFalse((self.app / "Contents/Resources").exists())
        self.assertFalse(self.calls.exists())

    def test_skip_rejects_release_profile_missing_and_unknown_configuration(self):
        for configuration in ("Release", "Profile", None, "debug", "Other"):
            with self.subTest(configuration=configuration):
                environment = {"ANYDECK_SKIP_SHARE_CORE": "1"}
                if configuration is not None:
                    environment["CONFIGURATION"] = configuration
                result = self.run_script(**environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("only allowed for Debug", result.stderr)
                self.assertFalse(self.app.exists())
                self.assertFalse(self.calls.exists())

    def test_debug_skip_rejects_missing_or_unsafe_xcode_app_path(self):
        for values in (
            {"TARGET_BUILD_DIR": ""}, {"TARGET_BUILD_DIR": "/"},
            {"TARGET_BUILD_DIR": "////"}, {"TARGET_BUILD_DIR": "relative/build"},
            {"TARGET_BUILD_DIR": str(self.directory / "..")},
            {"WRAPPER_NAME": ""}, {"WRAPPER_NAME": "../Other.app"},
            {"WRAPPER_NAME": "/Other.app"}, {"WRAPPER_NAME": ".app"},
            {"WRAPPER_NAME": "AnyDeck"},
        ):
            with self.subTest(values=values):
                result = self.run_script(
                    ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug", **values)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Share Core cleanup requires", result.stderr)
                self.assertFalse(self.app.exists())
        self.assertFalse(self.calls.exists())

    def test_debug_skip_accepts_missing_build_directory_without_creating_it(self):
        missing = self.directory / "missing/build"
        result = self.run_script(
            ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug",
            TARGET_BUILD_DIR=str(missing),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(missing.exists())
        self.assertFalse(self.calls.exists())

    def test_debug_skip_rejects_symlinked_parent_without_deleting_any_component(self):
        for relative in ("", "Contents", "Contents/MacOS", "Contents/Resources"):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory(
                dir=self.directory, prefix="parents-") as temporary:
                build = Path(temporary)
                app = build / "AnyDeck.app"
                link = app / relative if relative else app
                link.parent.mkdir(parents=True, exist_ok=True)
                outside = build / "outside"
                outside.mkdir()
                marker = outside / "keep.txt"
                marker.write_bytes(b"keep-outside")
                link.symlink_to(outside, target_is_directory=True)
                result = self.run_script(
                    ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug",
                    TARGET_BUILD_DIR=str(build),
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("regular app parent directories", result.stderr)
                self.assertEqual(marker.read_bytes(), b"keep-outside")
                self.assertTrue(link.is_symlink())
        self.assertFalse(self.calls.exists())

    def test_debug_skip_unlinks_component_symlink_without_following_it(self):
        outside = self.directory / "outside"
        outside.mkdir()
        marker = outside / "helper"
        marker.write_bytes(b"keep-outside")
        links = [self.app / "Contents" / name / "ShareCore"
                 for name in ("MacOS", "Resources")]
        for link in links:
            link.parent.mkdir(parents=True)
            link.symlink_to(outside, target_is_directory=True)
        result = self.run_script(ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(marker.read_bytes(), b"keep-outside")
        self.assertTrue(all(not link.exists() and not link.is_symlink() for link in links))
        self.assertFalse(self.calls.exists())

    def test_default_configurations_keep_locked_installer_and_propagate_failure(self):
        for configuration in ("Debug", "Release", "Profile", None):
            with self.subTest(configuration=configuration):
                environment = {"ANYDECK_SHARE_TEST_EXIT": "7"}
                if configuration is not None:
                    environment["CONFIGURATION"] = configuration
                result = self.run_script(**environment)
                self.assertEqual(result.returncode, 7)
                self.assertEqual(self.calls.read_text().splitlines(), [
                    str(ROOT / "script/install_share_core.py"),
                    "--app", str(self.app), "--architecture", "arm64", "--replace",
                ])
                self.assertFalse(self.app.exists())

    def test_non_explicit_skip_value_keeps_installer_and_archive_argument(self):
        result = self.run_script(
            ANYDECK_SKIP_SHARE_CORE="0", CONFIGURATION="Debug",
            ANYDECK_SHARE_CORE_ARCHIVE="/tmp/pinned-core.zip",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines()[-2:], [
            "--archive", "/tmp/pinned-core.zip",
        ])


if __name__ == "__main__":
    unittest.main()
