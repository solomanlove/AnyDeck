#!/usr/bin/env python3
"""显式指定设备和状态后，验证 AnyDeck 手动请求在 EOF/心跳超时后恢复自动。"""

import argparse
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import threading
import time


REMOTE_JAR = "/data/local/tmp/anydeck-foldable-screen-helper.jar"
ENTRY_POINT = "com.anydeck.helper.FoldableScreenHelper"


def snapshot(adb):
    """只读状态；所有权格式未知时拒绝执行真机测试。"""
    result = subprocess.run(adb + ["shell", "dumpsys", "device_state"],
                            check=True, capture_output=True, text=True, timeout=15)
    output = result.stdout
    states = {}
    for key in ["Committed", "Base"]:
        match = re.search(r"m" + key + r"State=Optional\[DeviceState\{identifier=(\d+)", output)
        if match is None:
            raise AssertionError(f"无法读取 {key} state")
        states[key.lower()] = int(match.group(1))
    active = re.search(r"Override Request active:\s*(true|false)", output)
    if active is None:
        raise AssertionError("无法识别 override 所有权")
    states["active"] = active.group(1) == "true"
    owner = re.search(r"Request:\s*mPid=(\d+)", output)
    states["pid"] = int(owner.group(1)) if owner else None
    states["override_empty"] = "mOverrideState=Optional.empty" in output
    states["pending_empty"] = "mPendingState=Optional.empty" in output
    return states


def await_snapshot(adb, predicate, timeout=6):
    deadline = time.monotonic() + timeout
    latest = None
    while time.monotonic() < deadline:
        latest = snapshot(adb)
        if predicate(latest):
            return latest
        time.sleep(0.2)
    raise AssertionError(f"设备状态未在 {timeout}s 内收敛: {latest}")


def automatic(state):
    return (not state["active"] and state["override_empty"] and state["pending_empty"]
            and state["committed"] == state["base"])


class HelperSession:
    """仅当前测试进程持有的 stdin 负责清理，不使用全局 cmd reset。"""

    def __init__(self, adb):
        self.messages = queue.Queue()
        self.errors = []
        self.sequence = 0
        self.process = subprocess.Popen(
            adb + ["shell", f"CLASSPATH={REMOTE_JAR}", "app_process", "/", ENTRY_POINT],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1)
        self.reader = threading.Thread(target=self.read_stdout, daemon=True)
        self.stderr_reader = threading.Thread(target=self.read_stderr, daemon=True)
        self.reader.start()
        self.stderr_reader.start()
        try:
            ready = self.messages.get(timeout=6)
            if not ready.get("ready"):
                raise AssertionError(f"Helper 启动失败: {ready}")
            self.pid = ready["pid"]
        except Exception:
            self.cleanup()
            raise

    def read_stdout(self):
        for line in self.process.stdout:
            try:
                self.messages.put(json.loads(line))
            except ValueError:
                self.messages.put({"protocol_error": line.strip()})

    def read_stderr(self):
        for line in self.process.stderr:
            self.errors.append(line.strip())
            if len(self.errors) > 30:
                self.errors.pop(0)

    def command(self, name, **parameters):
        self.sequence += 1
        message = dict(parameters, id=self.sequence, command=name)
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            reply = self.messages.get(timeout=max(0.01, deadline - time.monotonic()))
            if reply.get("id") != self.sequence:
                continue
            if not reply.get("ok"):
                raise AssertionError(f"Helper 命令失败: {reply}")
            return reply
        raise AssertionError("Helper 响应超时")

    def eof(self):
        if self.process.stdin and not self.process.stdin.closed:
            self.process.stdin.close()

    def cleanup(self):
        self.eof()
        try:
            self.process.wait(timeout=6)
        except subprocess.TimeoutExpired:
            # 仅终止本地 adb，设备 Helper 仍可通过 EOF 或自身 watchdog 释放请求。
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        self.reader.join(timeout=1)
        self.stderr_reader.join(timeout=1)


def verify_cleanup(adb, target, mode):
    initial = snapshot(adb)
    if not automatic(initial):
        raise AssertionError(f"测试前设备已有 override 或状态未稳定，拒绝操作: {initial}")
    if target == initial["base"]:
        raise AssertionError("测试目标必须与当前 base 不同，确保验证真实屏幕切换")
    session = HelperSession(adb)
    try:
        session.command("state", state=target)
        held = await_snapshot(adb, lambda value: value["active"]
                              and value["pid"] == session.pid and value["committed"] == target)
        if not session.command("ping").get("ownsRequest"):
            raise AssertionError("Helper 未持有刚提交的请求")
        started = time.monotonic()
        if mode == "EOF":
            session.eof()
            exit_code = session.process.wait(timeout=6)
        else:
            # stdin 保持打开，主动停止心跳，确保由设备侧 12 秒 watchdog 完成恢复。
            exit_code = session.process.wait(timeout=16)
        elapsed = time.monotonic() - started
        if exit_code != 0:
            raise AssertionError(f"Helper 非正常退出: {exit_code}, {session.errors}")
        if mode == "watchdog" and elapsed < 10.5:
            raise AssertionError(f"watchdog 过早退出: {elapsed:.1f}s")
        restored = await_snapshot(adb, automatic)
        current = subprocess.run(adb + ["shell", "cmd", "device_state", "state"],
                                 check=True, capture_output=True, text=True, timeout=15)
        if "Override state:" in current.stdout:
            raise AssertionError(f"cmd state 仍报告 override: {current.stdout}")
        print(f"PASS {mode}: held state={held['committed']}, pid={session.pid}; "
              f"exit={exit_code} after {elapsed:.1f}s; "
              f"committed=base={restored['base']}, override=none", flush=True)
        print(current.stdout.strip(), flush=True)
    finally:
        session.cleanup()
        # 即使测试断言失败，也等待自身 EOF/watchdog 清理并核实，不调用全局 reset。
        await_snapshot(adb, automatic, timeout=16)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="显式选择 adb 设备；不提供时不连接或修改任何手机")
    parser.add_argument("--state", type=int, help="显式指定已验证的目标状态编号，例如三星外屏 0")
    parser.add_argument("--adb", help="adb 可执行文件路径")
    args = parser.parse_args()
    if not args.device:
        print("SKIP: 必须显式传入 --device 和 --state 才会执行真机切屏验证。")
        return
    if args.state is None or args.state < 0:
        parser.error("真机验证必须显式提供非负 --state 编号")
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
               or Path.home() / "Library/Android/sdk")
    executable = args.adb or shutil.which("adb") or str(sdk / "platform-tools/adb")
    adb = [executable, "-s", args.device]
    if not automatic(snapshot(adb)):
        raise AssertionError("设备存在外部 override 或状态未稳定，拒绝 push/切屏")
    root = Path(__file__).resolve().parents[2]
    subprocess.run(adb + ["push", str(root / "assets/android/foldable-screen-helper.jar"),
                         REMOTE_JAR], check=True, timeout=15)
    for mode in ["EOF", "watchdog"]:
        verify_cleanup(adb, args.state, mode)


if __name__ == "__main__":
    main()
