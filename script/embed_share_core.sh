#!/bin/bash
set -euo pipefail

# 显式 Debug 验收可跳过私有组件；其他配置不能绕过锁定制品校验。
if [ "${ANYDECK_SKIP_SHARE_CORE:-}" = "1" ]; then
  if [ "${CONFIGURATION:-}" != "Debug" ]; then
    echo "error: ANYDECK_SKIP_SHARE_CORE=1 is only allowed for Debug validation builds" >&2
    exit 1
  fi
  # 只清理当前目标包，避免增量构建残留旧组件或误删其他构建产物。
  SHARE_BUILD_DIR="${TARGET_BUILD_DIR:-}"
  SHARE_WRAPPER="${WRAPPER_NAME:-}"
  while [ "${SHARE_BUILD_DIR%/}" != "$SHARE_BUILD_DIR" ]; do
    SHARE_BUILD_DIR="${SHARE_BUILD_DIR%/}"
  done
  case "$SHARE_BUILD_DIR" in
    /*) ;;
    *) echo "error: Share Core cleanup requires an absolute non-root TARGET_BUILD_DIR" >&2; exit 1 ;;
  esac
  case "$SHARE_BUILD_DIR/" in
    *'/../'*|*'/./'*) echo "error: Share Core cleanup requires a normalized TARGET_BUILD_DIR" >&2; exit 1 ;;
  esac
  case "$SHARE_WRAPPER" in
    ''|*/*|.app) echo "error: Share Core cleanup requires one app WRAPPER_NAME" >&2; exit 1 ;;
    *.app) ;;
    *) echo "error: Share Core cleanup requires one app WRAPPER_NAME" >&2; exit 1 ;;
  esac
  SHARE_APP="$SHARE_BUILD_DIR/$SHARE_WRAPPER"
  # 先验证全部父目录；ShareCore 自身若为链接，仅删除链接，不跟随目标。
  for SHARE_DIRECTORY in "$SHARE_BUILD_DIR" "$SHARE_APP" "$SHARE_APP/Contents" \
    "$SHARE_APP/Contents/MacOS" "$SHARE_APP/Contents/Resources"; do
    if [ -L "$SHARE_DIRECTORY" ] || { [ -e "$SHARE_DIRECTORY" ] && [ ! -d "$SHARE_DIRECTORY" ]; }; then
      echo "error: Share Core cleanup requires regular app parent directories" >&2
      exit 1
    fi
  done
  rm -rf -- "$SHARE_APP/Contents/MacOS/ShareCore" "$SHARE_APP/Contents/Resources/ShareCore"
  echo "warning: Share Core is skipped for this explicit Debug validation build"
  exit 0
fi

# Runner 的公共构建阶段：Debug/Profile/Release 均安装锁定组件，失败即终止构建。
SHARE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARE_APP="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
read -r -a SHARE_ARCHITECTURES <<< "${ARCHS:-$(uname -m)}"
if [ "${#SHARE_ARCHITECTURES[@]}" -ne 1 ]; then
  echo "error: Share Core requires one pinned target architecture; got: ${ARCHS:-}" >&2
  exit 1
fi
SHARE_ARGUMENTS=(--app "$SHARE_APP" --architecture "${SHARE_ARCHITECTURES[0]}" --replace)
if [ -n "${ANYDECK_SHARE_CORE_ARCHIVE:-}" ]; then
  SHARE_ARGUMENTS+=(--archive "$ANYDECK_SHARE_CORE_ARCHIVE")
fi
python3 "$SHARE_ROOT/script/install_share_core.py" "${SHARE_ARGUMENTS[@]}"
