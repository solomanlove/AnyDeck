#!/bin/bash
# 校验完整 App 后生成保留符号链接和执行权限的 ZIP、DMG 与校验清单。
set -euo pipefail

RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_APP="${1:?Usage: package_macos_release.sh path/to/AnyDeck.app output_directory}"
RELEASE_OUTPUT="${2:?Missing output directory}"
RELEASE_ARCH="${3:-$(uname -m)}"
case "$RELEASE_ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $RELEASE_ARCH" >&2; exit 1 ;; esac
RELEASE_NAME="AnyDeck-macOS-$RELEASE_ARCH"
python3 "$RELEASE_ROOT/script/verify_macos_release.py" "$RELEASE_APP" --arch "$RELEASE_ARCH"
mkdir -p "$RELEASE_OUTPUT"
RELEASE_OUTPUT="$(cd "$RELEASE_OUTPUT" && pwd)"
RELEASE_STAGE="$(mktemp -d)"
trap 'rm -rf "$RELEASE_STAGE"' EXIT

ditto "$RELEASE_APP" "$RELEASE_STAGE/AnyDeck.app"
ln -s /Applications "$RELEASE_STAGE/Applications"
cp "$RELEASE_ROOT/agent/distribution/INSTALL-macOS.md" "$RELEASE_STAGE/INSTALL-macOS.md"
cp "$RELEASE_STAGE/INSTALL-macOS.md" "$RELEASE_OUTPUT/INSTALL-macOS.md"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_STAGE/AnyDeck.app" "$RELEASE_OUTPUT/$RELEASE_NAME.zip"
hdiutil create -ov -format UDZO -volname AnyDeck -srcfolder "$RELEASE_STAGE" "$RELEASE_OUTPUT/$RELEASE_NAME.dmg"
(
  cd "$RELEASE_OUTPUT"
  shasum -a 256 "$RELEASE_NAME.dmg" "$RELEASE_NAME.zip" INSTALL-macOS.md > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)
