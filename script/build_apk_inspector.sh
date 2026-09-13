#!/bin/bash
set -euo pipefail

# 构建独立 APK 检查器，嵌入应用后无需用户安装 Rust/SDK/Java。
APK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_CARGO="${CARGO:-$(command -v cargo || true)}"
if [ -z "$APK_CARGO" ] && [ -x "$HOME/.cargo/bin/cargo" ]; then APK_CARGO="$HOME/.cargo/bin/cargo"; fi
if [ -z "$APK_CARGO" ] && [ -x /opt/homebrew/bin/cargo ]; then APK_CARGO=/opt/homebrew/bin/cargo; fi
if [ -z "$APK_CARGO" ]; then echo "cargo is required to build the APK inspector" >&2; exit 1; fi
APK_TARGET_DIR="$APK_ROOT/build/apk_inspector"
APK_ARCHS="${ARCHS:-$(uname -m)}"
APK_BINARIES=()
export MACOSX_DEPLOYMENT_TARGET=11.0
for APK_ARCH in $APK_ARCHS; do
  case "$APK_ARCH" in
    arm64) APK_TARGET=aarch64-apple-darwin ;;
    x86_64) APK_TARGET=x86_64-apple-darwin ;;
    *) echo "Unsupported APK inspector architecture: $APK_ARCH" >&2; exit 1 ;;
  esac
  "$APK_CARGO" build --locked --release --manifest-path "$APK_ROOT/rust/apk_inspector/Cargo.toml" \
    --target "$APK_TARGET" --target-dir "$APK_TARGET_DIR"
  APK_BINARIES+=("$APK_TARGET_DIR/$APK_TARGET/release/anydeck-apk-inspector")
done
APK_BUNDLE="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
mkdir -p "$APK_BUNDLE/Contents/Helpers" "$APK_BUNDLE/Contents/Resources/apk-inspector-licenses"
lipo -create "${APK_BINARIES[@]}" -output "$APK_BUNDLE/Contents/Helpers/anydeck-apk-inspector"
chmod +x "$APK_BUNDLE/Contents/Helpers/anydeck-apk-inspector"
cp -R "$APK_ROOT/rust/apk_inspector/licenses/." "$APK_BUNDLE/Contents/Resources/apk-inspector-licenses/"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$APK_BUNDLE/Contents/Helpers/anydeck-apk-inspector"
