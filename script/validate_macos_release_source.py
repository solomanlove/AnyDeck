#!/usr/bin/env python3
"""发布恢复时校验成功构建与目标 Tag 的来源一致性。"""
import json
import sys


def validate(run, commit):
    """只复用既有 macOS 发布流程在同一 commit 上的完整成功产物。"""
    if run.get('status') != 'completed' or run.get('conclusion') != 'success':
        raise ValueError('来源 Workflow 尚未完整成功')
    if run.get('head_sha') != commit:
        raise ValueError('来源 Workflow 与目标 Tag 的 commit 不一致')
    if run.get('path') != '.github/workflows/release-macos.yml':
        raise ValueError('来源不是 macOS 双架构构建 Workflow')
    if run.get('event') not in ('workflow_dispatch', 'push'):
        raise ValueError('不允许复用 PR 或其它事件的产物')


if __name__ == '__main__':
    validate(json.load(sys.stdin), sys.argv[1])
    print('来源 Workflow 完整成功，且与目标 Tag commit 一致')
