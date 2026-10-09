#!/bin/bash
set -euo pipefail

# 设备桥接库构建脚本（Rust + UxPlay 协议核心 / VideoToolbox / ADB）
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CARGO_BIN="${CARGO:-$(command -v cargo || true)}"
if [ -z "$CARGO_BIN" ]; then
  for BRIDGE_CARGO in "$HOME/.cargo/bin/cargo" /opt/homebrew/bin/cargo /usr/local/bin/cargo; do
    if [ -x "$BRIDGE_CARGO" ]; then CARGO_BIN="$BRIDGE_CARGO"; break; fi
  done
fi
if [ -z "$CARGO_BIN" ]; then echo "Rust cargo is required to build the device bridge" >&2; exit 1; fi
BRIDGE_MANIFEST="$PROJECT_ROOT/rust/device_bridge/Cargo.toml"
BRIDGE_OUTPUT="$PROJECT_ROOT/macos/Libs/libanydeck_device_bridge.dylib"
BRIDGE_ARCHS="${ARCHS:-$(uname -m)}"
BRIDGE_TARGET_DIR="${TARGET_TEMP_DIR:-$PROJECT_ROOT/rust/device_bridge/target}/device-bridge"
BRIDGE_LIBRARIES=()
export MACOSX_DEPLOYMENT_TARGET=11.0
for BRIDGE_ARCH in $BRIDGE_ARCHS; do
  case "$BRIDGE_ARCH" in
    arm64) BRIDGE_TARGET=aarch64-apple-darwin ;;
    x86_64) BRIDGE_TARGET=x86_64-apple-darwin ;;
    *) echo "Unsupported Rust bridge architecture: $BRIDGE_ARCH" >&2; exit 1 ;;
  esac
  "$CARGO_BIN" build --release --manifest-path "$BRIDGE_MANIFEST" \
    --target "$BRIDGE_TARGET" --target-dir "$BRIDGE_TARGET_DIR"
  BRIDGE_LIBRARIES+=("$BRIDGE_TARGET_DIR/$BRIDGE_TARGET/release/libanydeck_device_bridge.dylib")
done
mkdir -p "$(dirname "$BRIDGE_OUTPUT")"
# 先签名临时文件再原子替换，避免覆盖仍被运行中 App mmap 的动态库。
BRIDGE_STAGED="$(mktemp "${BRIDGE_OUTPUT}.XXXXXX")"
trap 'rm -f "$BRIDGE_STAGED"' EXIT
lipo -create "${BRIDGE_LIBRARIES[@]}" -output "$BRIDGE_STAGED"
install_name_tool -id '@rpath/libanydeck_device_bridge.dylib' "$BRIDGE_STAGED"
chmod 755 "$BRIDGE_STAGED"
codesign --force --sign - "$BRIDGE_STAGED"
mv -f "$BRIDGE_STAGED" "$BRIDGE_OUTPUT"

# 更新已构建 App 的磁盘文件；已运行的进程必须重启才会加载新版本。
for BRIDGE_CONFIGURATION in Debug Release; do
  BRIDGE_FRAMEWORKS="$PROJECT_ROOT/build/macos/Build/Products/$BRIDGE_CONFIGURATION/AnyDeck.app/Contents/Frameworks"
  if [ -d "$BRIDGE_FRAMEWORKS" ]; then
    BRIDGE_STAGED="$(mktemp "$BRIDGE_FRAMEWORKS/libanydeck_device_bridge.dylib.XXXXXX")"
    cp -p "$BRIDGE_OUTPUT" "$BRIDGE_STAGED"
    mv -f "$BRIDGE_STAGED" "$BRIDGE_FRAMEWORKS/libanydeck_device_bridge.dylib"
  fi
done
