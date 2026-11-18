#!/bin/bash
# 在仓库锁定的 Flutter、Rust 和 Bundler 环境中执行命令。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev_environment.py" exec "$@"
