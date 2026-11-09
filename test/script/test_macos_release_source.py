"""发布恢复必须拒绝失败、来源错误或与 Tag 不一致的构建产物。"""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
from validate_macos_release_source import validate


class ReleaseSourceTests(unittest.TestCase):
    def setUp(self):
        self.run = {'status': 'completed', 'conclusion': 'success',
                    'head_sha': 'a' * 40, 'event': 'workflow_dispatch',
                    'path': '.github/workflows/release-macos.yml'}

    def test_successful_matching_build_is_accepted(self):
        validate(self.run, 'a' * 40)

    def test_wrong_commit_is_rejected(self):
        with self.assertRaises(ValueError):
            validate(self.run, 'b' * 40)

    def test_incomplete_or_failed_build_is_rejected(self):
        for changes in ({'status': 'in_progress'}, {'conclusion': 'failure'},
                        {'conclusion': 'cancelled'}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(self.run | changes, 'a' * 40)

    def test_untrusted_workflow_or_event_is_rejected(self):
        for changes in ({'path': '.github/workflows/other.yml'},
                        {'event': 'pull_request'}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(self.run | changes, 'a' * 40)
