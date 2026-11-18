#!/bin/bash
# Flutter 的统一 CLI 入口，自动把 CocoaPods 子进程限制在 Gemfile.lock 中。
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev_exec.sh" flutter "$@"
