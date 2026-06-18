#!/bin/bash
 # 使用示例 (Examples): 打开终端，导航到项目根目录，执行以下命令
 #  1. 默认构建并复制到项目根目录下的 Products/ 文件夹中:
 #     ./script/build_macos.sh
 #  2. 构建并复制到桌面 (Products/ 文件夹中):
 #     ./script/build_macos.sh ~/Desktop

# 确保脚本在遇到错误时立即退出
set -e

# 获取当前脚本所在目录及项目根目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# 显示使用方法的函数
show_usage() {
  echo "=========================================="
  echo "使用方法 (Usage):"
  echo "  $0 [options] [target_directory]"
  echo ""
  echo "参数说明 (Arguments):"
  echo "  target_directory   可选。指定存放 Products 文件夹的父级目录。"
  echo "                     若未指定，默认使用项目根目录 ($PROJECT_ROOT)。"
  echo ""
  echo "选项说明 (Options):"
  echo "  -h, --help         显示此使用方法并退出。"
  echo ""
  echo "使用示例 (Examples):"
  echo "  1. 默认构建并复制到项目根目录下的 Products/ 文件夹中:"
  echo "     $0"
  echo "  2. 构建并复制到桌面 (Products/ 文件夹中):"
  echo "     $0 ~/Desktop"
  echo "=========================================="
  exit 0
}

# 检查是否请求帮助信息
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_usage
fi

# 切换到项目根目录
cd "$PROJECT_ROOT"

# 解析目标目录（通过参数传入，如果未指定则默认使用项目根目录）
TARGET_DIR="${1:-$PROJECT_ROOT}"

# 如果目标路径是相对路径，转换为绝对路径
if [[ ! "$TARGET_DIR" = /* ]]; then
  TARGET_DIR="$(pwd)/$TARGET_DIR"
fi

# 输出的 Products 文件夹路径
PRODUCT_DEST_DIR="$TARGET_DIR/Products"

echo "=========================================="
echo "开始构建 macOS Release 版本..."
echo "=========================================="

# 运行 Flutter 构建命令
flutter build macos --release

echo "=========================================="
echo "构建成功！正在定位生成的 .app 包..."
echo "=========================================="

# 在编译输出目录中查找 .app 包
APP_PATH=$(find build/macos/Build/Products/Release -name "*.app" -maxdepth 1 | head -n 1)

if [ -z "$APP_PATH" ]; then
  echo "错误：未能在 build/macos/Build/Products/Release 目录下找到 .app 包。"
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")
echo "找到应用包: $APP_NAME"
echo "源路径: $APP_PATH"

"$SCRIPT_DIR/fix_macos_app_policy.sh" "$APP_PATH"

# 创建目标的 Products 目录
mkdir -p "$PRODUCT_DEST_DIR"

# 复制生成的包到指定的 Products 文件夹中
# 如果已存在同名文件夹则先删除，避免 cp 嵌套复制
if [ -d "$PRODUCT_DEST_DIR/$APP_NAME" ]; then
  echo "正在清理已存在的目标文件: $PRODUCT_DEST_DIR/$APP_NAME"
  rm -rf "$PRODUCT_DEST_DIR/$APP_NAME"
fi

echo "正在复制到: $PRODUCT_DEST_DIR/"
cp -R "$APP_PATH" "$PRODUCT_DEST_DIR/"
"$SCRIPT_DIR/fix_macos_app_policy.sh" "$PRODUCT_DEST_DIR/$APP_NAME"

echo "=========================================="
echo "打包与分发完成！"
echo "应用包路径: $PRODUCT_DEST_DIR/$APP_NAME"
echo "=========================================="
