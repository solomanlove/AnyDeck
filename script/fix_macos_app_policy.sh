#!/bin/bash
# 清理 macOS 调试/本地构建产物的来源策略属性，并重新进行本地签名。

set -e

APP_PATH="${1:-}"

if [ -z "$APP_PATH" ]; then
  echo "Usage: $0 <path-to-app>"
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Skip macOS app policy fix: app not found at $APP_PATH"
  exit 0
fi

echo "Fixing macOS app policy attributes: $APP_PATH"

# com.apple.provenance / quarantine 可能导致 dyld 拒绝加载 adhoc 签名 framework。
xattr -dr com.apple.provenance "$APP_PATH" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

# 清理扩展属性后重新签名，确保 FlutterMacOS.framework 与动态库仍满足本地调试签名要求。
codesign --force --deep --sign - "$APP_PATH"
