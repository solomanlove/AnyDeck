#!/bin/bash
# 独立 Debug 构建入口：不获取、编译或打包 Share Core 私有组件。
set -euo pipefail

if [ "$#" -gt 0 ]; then
  echo "用法：FLUTTER_BIN=<flutter路径> $0" >&2
  case "$1" in -h|--help) exit 0 ;; *) exit 2 ;; esac
fi

BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BUILD_ROOT"
export ANYDECK_SKIP_SHARE_CORE=1
"${FLUTTER_BIN:-flutter}" build macos --debug --no-pub \
  --dart-define=ANYDECK_ENABLE_SHARE_CORE=false

# 对最终包再次检查，避免增量构建残留旧的私有组件。
BUILD_APP="$BUILD_ROOT/build/macos/Build/Products/Debug/AnyDeck.app"
if [ ! -d "$BUILD_APP" ]; then
  echo "error: 未找到不含 Share Core 的 AnyDeck.app：$BUILD_APP" >&2
  exit 1
fi
for component in Contents/MacOS/ShareCore Contents/Resources/ShareCore; do
  if [ -e "$BUILD_APP/$component" ] || [ -L "$BUILD_APP/$component" ]; then
    echo "error: 构建包仍包含 Share Core：$component" >&2
    exit 1
  fi
done
echo "已构建不含 Share Core 的 Debug 包：$BUILD_APP"
