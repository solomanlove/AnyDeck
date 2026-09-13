#!/bin/bash
set -e

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR/.."

cd "$PROJECT_DIR/rust"

export MACOSX_DEPLOYMENT_TARGET="11.0"

echo "[build_rust] Building pure Rust VideoToolbox & AudioQueue library..."

# 确保 Libs 目录存在
mkdir -p "$PROJECT_DIR/macos/Libs"

# 编译当前架构 release 静态库
cargo build --release

# 拷贝静态库到 macos/Libs
if [ -f "target/release/librust_scrcpy.a" ]; then
    cp "target/release/librust_scrcpy.a" "$PROJECT_DIR/macos/Libs/librust_scrcpy.a"
    echo "[build_rust] Successfully copied librust_scrcpy.a to macos/Libs"
else
    echo "[build_rust] Error: librust_scrcpy.a not found!"
    exit 1
fi
