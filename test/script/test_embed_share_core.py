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

    def test_explicit_debug_skip_does_not_modify_existing_app(self):
        component = self.app / "Contents/MacOS/ShareCore/helper"
        component.parent.mkdir(parents=True)
        component.write_bytes(b"existing-artifact")
        before = (component.read_bytes(), component.stat().st_mtime_ns,
                  component.stat().st_mode)
        result = self.run_script(ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((component.read_bytes(), component.stat().st_mtime_ns,
                          component.stat().st_mode), before)
        self.assertEqual(list(component.parent.iterdir()), [component])
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

    def test_debug_skip_does_not_require_xcode_app_path(self):
        self.environment.pop("TARGET_BUILD_DIR")
        self.environment.pop("WRAPPER_NAME")
        result = self.run_script(ANYDECK_SKIP_SHARE_CORE="1", CONFIGURATION="Debug")
        self.assertEqual(result.returncode, 0, result.stderr)
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
