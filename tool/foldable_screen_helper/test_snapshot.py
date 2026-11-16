#!/usr/bin/env python3
"""在 host JVM 校验设备 override 所有权解析，不连接手机或请求屏幕状态。"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class SnapshotTest(unittest.TestCase):
    def test_override_ownership_and_unknown_format(self):
        source = Path(__file__).parent / "src/com/anydeck/helper/FoldableStateSnapshot.java"
        program = r'''
package com.anydeck.helper;
public final class SnapshotTest {
    public static void main(String[] args) {
        assertSnapshot("Override Request active: false", false, -1);
        assertSnapshot("Override Request active: true\nRequest: mPid=123, mRequestedState=0",
                true, 123);
        assertSnapshot("mOverrideState=Optional.empty", false, -1);
        assertRejected("Override Request active: true");
        assertRejected("Override Request active: true\nmOverrideState=Optional.empty");
        assertRejected("Override Request active:   true\nmOverrideState=Optional.empty");
        assertRejected("Permission Denial: can't dump device_state");
        assertRejected("mOverrideState=Optional[DeviceState{identifier=0}]");
        assertRejected("");
    }
    private static void assertSnapshot(String text, boolean active, int pid) {
        FoldableStateSnapshot snapshot = FoldableStateSnapshot.parse(text);
        if (snapshot.active != active || snapshot.pid != pid) throw new AssertionError(text);
    }
    private static void assertRejected(String text) {
        try {
            FoldableStateSnapshot.parse(text);
            throw new AssertionError("Unknown ownership must be rejected: " + text);
        } catch (IllegalStateException expected) {
            if (!"override_owner_unreadable".equals(expected.getMessage())) {
                throw new AssertionError(expected);
            }
        }
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="anydeck-foldable-test-") as temporary:
            work = Path(temporary)
            test = work / "SnapshotTest.java"
            test.write_text(program, encoding="utf-8")
            subprocess.run([shutil.which("javac") or "javac", "--release", "8",
                            "-d", str(work), str(source), str(test)], check=True, timeout=30)
            subprocess.run([shutil.which("java") or "java", "-cp", str(work),
                            "com.anydeck.helper.SnapshotTest"], check=True, timeout=15)


if __name__ == "__main__":
    unittest.main()
