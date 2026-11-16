#!/bin/bash
set -euo pipefail

# 显式 Debug 验收可跳过私有组件；其他配置不能绕过锁定制品校验。
if [ "${ANYDECK_SKIP_SHARE_CORE:-}" = "1" ]; then
  if [ "${CONFIGURATION:-}" != "Debug" ]; then
    echo "error: ANYDECK_SKIP_SHARE_CORE=1 is only allowed for Debug validation builds" >&2
    exit 1
  fi
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
