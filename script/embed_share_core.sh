#!/bin/bash
set -euo pipefail

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
