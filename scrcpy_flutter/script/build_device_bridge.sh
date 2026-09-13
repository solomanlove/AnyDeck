#!/bin/bash
set -euo pipefail

# 独立 Rust 底层，无第三方 crate。Xcode 自动调用；不启动应用或访问设备。
BRIDGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CARGO_BIN="${CARGO:-$(command -v cargo || true)}"
if [ -z "$CARGO_BIN" ]; then
  for BRIDGE_CARGO in "$HOME/.cargo/bin/cargo" /opt/homebrew/bin/cargo /usr/local/bin/cargo; do
    if [ -x "$BRIDGE_CARGO" ]; then CARGO_BIN="$BRIDGE_CARGO"; break; fi
  done
fi
if [ -z "$CARGO_BIN" ]; then echo "Rust cargo is required to build the device bridge" >&2; exit 1; fi
BRIDGE_MANIFEST="$BRIDGE_ROOT/rust/device_bridge/Cargo.toml"
BRIDGE_OUTPUT="$BRIDGE_ROOT/macos/Libs/libanydeck_device_bridge.dylib"
BRIDGE_ARCHS="${ARCHS:-$(uname -m)}"
BRIDGE_TARGET_DIR="${TARGET_TEMP_DIR:-$BRIDGE_ROOT/rust/device_bridge/target}/device-bridge"
BRIDGE_LIBRARIES=()
export MACOSX_DEPLOYMENT_TARGET=11.0
for BRIDGE_ARCH in $BRIDGE_ARCHS; do
  case "$BRIDGE_ARCH" in
    arm64) BRIDGE_TARGET=aarch64-apple-darwin ;;
    x86_64) BRIDGE_TARGET=x86_64-apple-darwin ;;
    *) echo "Unsupported Rust bridge architecture: $BRIDGE_ARCH" >&2; exit 1 ;;
  esac
  "$CARGO_BIN" build --offline --locked --release --manifest-path "$BRIDGE_MANIFEST" \
    --target "$BRIDGE_TARGET" --target-dir "$BRIDGE_TARGET_DIR"
  BRIDGE_LIBRARIES+=("$BRIDGE_TARGET_DIR/$BRIDGE_TARGET/release/libanydeck_device_bridge.dylib")
done
mkdir -p "$(dirname "$BRIDGE_OUTPUT")"
lipo -create "${BRIDGE_LIBRARIES[@]}" -output "$BRIDGE_OUTPUT"
install_name_tool -id '@rpath/libanydeck_device_bridge.dylib' "$BRIDGE_OUTPUT"
codesign --force --sign - "$BRIDGE_OUTPUT"
