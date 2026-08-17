#!/bin/bash
set -e

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR/.."

cd "$PROJECT_DIR/rust"

# 导出手动指定的 FFmpeg 头文件与 AnyDeck 本地内置的动态库路径，确保 Rust 静态库与 App 运行时的 ABI 完全一致
export FFMPEG_INCLUDE_DIR="/opt/homebrew/opt/ffmpeg/include"
export FFMPEG_LIB_DIR="$PROJECT_DIR/macos/Libs"
export MACOSX_DEPLOYMENT_TARGET="11.0"

# 修复 macOS bindgen 编译时的 Clang 路径问题，指向正确的 macOS SDK 和我们的自定义占位头文件目录
SDK_PATH=$(xcrun --show-sdk-path)
export BINDGEN_EXTRA_CLANG_ARGS="-isysroot $SDK_PATH -I$PROJECT_DIR/rust/include -I/opt/homebrew/opt/ffmpeg/include"

echo "[build_rust] Building Rust library with local Libs to prevent ABI mismatch..."
echo "FFMPEG_INCLUDE_DIR: $FFMPEG_INCLUDE_DIR"
echo "FFMPEG_LIB_DIR: $FFMPEG_LIB_DIR"

# 确保 Libs 目录存在
mkdir -p "$PROJECT_DIR/macos/Libs"

# 默认编译当前架构
cargo build --release

# 拷贝静态库到 macos/Libs
if [ -f "target/release/librust_scrcpy.a" ]; then
    cp "target/release/librust_scrcpy.a" "$PROJECT_DIR/macos/Libs/librust_scrcpy.a"
    echo "[build_rust] Successfully copied librust_scrcpy.a to macos/Libs"
else
    echo "[build_rust] Error: librust_scrcpy.a not found!"
    exit 1
fi
