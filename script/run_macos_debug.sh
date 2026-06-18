#!/bin/bash
# macOS Debug 启动入口：先构建，再清理 system policy 属性，最后复用构建产物运行。

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
APP_PATH="$PROJECT_ROOT/build/macos/Build/Products/Debug/AnyDeck.app"

cd "$PROJECT_ROOT"

flutter build macos --debug
"$SCRIPT_DIR/fix_macos_app_policy.sh" "$APP_PATH"
flutter run -d macos --debug --no-build
