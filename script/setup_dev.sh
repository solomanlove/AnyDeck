#!/bin/bash
# 新电脑准备入口；安装固定工具链并按锁文件获取依赖。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup_dev.py" "$@"
