#!/bin/bash
# 问题：ld: warning: building for macOS-11.0, but linking with dylib '@rpath/libx265.216.dylib' which was built for newer version 26.0
# 解决：将所有 .dylib 文件的 minos 版本设为 11.0，并使用 codesign 重新签名。
# 就执行以下脚本

# 确保脚本在遇到错误时立即退出
set -e

# 获取当前脚本所在目录及项目根目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
LIBS_DIR="$PROJECT_ROOT/scrcpy_flutter/macos/Libs"

echo "=========================================="
echo "开始修复 macOS 动态库版本限制警告..."
echo "Starting to fix macOS dylib version warning..."
echo "=========================================="

if [ ! -d "$LIBS_DIR" ]; then
  echo "错误：找不到动态库目录 $LIBS_DIR"
  echo "Error: Cannot find dynamic library directory at $LIBS_DIR"
  exit 1
fi

cd "$LIBS_DIR"

for f in *.dylib; do
  if [ -f "$f" ]; then
    echo "=========================================="
    echo "正在处理: $f"
    echo "Processing: $f"
    
    # 检查当前 minos 版本
    current_minos=$(otool -l "$f" | grep -A 3 "LC_BUILD_VERSION" | grep "minos" | awk '{print $2}' || echo "")
    
    if [ "$current_minos" = "11.0" ]; then
      echo "$f 的 minos 已经是 11.0，跳过处理。"
      echo "$f minos is already 11.0, skipping."
      continue
    fi
    
    # 备份原文件
    cp "$f" "$f.bak"
    
    # 修改 LC_BUILD_VERSION (platform 1 代表 macOS, minos 11.0, sdk 11.0)
    vtool -set-build-version 1 11.0 11.0 -output "$f" "$f.bak"
    
    # 删除备份
    rm "$f.bak"
    
    # 重新进行本地签名
    codesign --force --sign - "$f"
    
    echo "$f 修复成功！"
    echo "$f fixed successfully!"
  fi
done

echo "=========================================="
echo "修复完成！所有的 .dylib 文件的 minos 已设为 11.0。"
echo "Fix complete! All .dylib minos are set to 11.0."
echo "=========================================="
