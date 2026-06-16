#!/bin/bash
# 直接运行可以生成 IDE 运行入口并启动投屏子窗口。
# 可选参数：--device-id, --device-name, --title, --resolution, --new-display, --start-app, --window-id, --app, --output, --idea-run-config, --run-config-name, --generate-only, -h, --help

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

show_usage() {
  echo "=========================================="
  echo "使用方法 (Usage):"
  echo "  $0 [--device-id <serial>] [options]"
  echo ""
  echo "设备选择 (Device):"
  echo "  --device-id <serial>       ADB 设备 ID。未传入时，脚本会先执行 adb devices -l。"
  echo "                             只有 1 台在线设备时直接启动，多台时手动选择。"
  echo ""
  echo "可选参数 (Options):"
  echo "  --device-name <name>       投屏窗口内显示的设备名称，默认等于 device-id。"
  echo "  --title <title>            原生窗口标题，默认等于 device-name。"
  echo "  --resolution <WxH>         设备或虚拟副屏分辨率，用于计算初始窗口尺寸。"
  echo "  --new-display <WxH>        scrcpy 虚拟副屏参数，对应项目参数 newDisplay。"
  echo "  --start-app <package>      虚拟副屏启动 App 包名，对应项目参数 startApp。"
  echo "  --window-id <id>           子窗口 ID，默认自动生成。"
  echo "  --app <path>               .app 包或可执行文件路径，默认自动查找 Products/AnyDeck.app。"
  echo "  --output <path>            显式生成启动文件或 Run Configuration 的路径。"
  echo "  --idea-run-config          生成 Android Studio/IntelliJ Flutter Run Configuration。"
  echo "  --run-config-name <name>   Run Configuration 显示名称，默认 Debug - 投屏子窗口。"
  echo "  --generate-only            只打印启动参数；与 --output 组合时才生成启动文件。"
  echo "  -h, --help                 显示此帮助。"
  echo ""
  echo "示例 (Examples):"
  echo "  $0"
  echo "  $0 --device-id emulator-5554 --device-name Pixel_8 --resolution 1080x2400"
  echo "  $0 --idea-run-config      # 只生成 IDE 运行入口，不启动投屏"
  echo "  $0 --device-id R5CN --device-name 微信 --new-display 1080x1920 --start-app com.tencent.mm"
  echo "=========================================="
}

select_adb_device() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "错误：未找到 adb，请先配置 Android SDK platform-tools 到 PATH。"
    exit 1
  fi

  local ids=()
  local labels=()
  local adb_output=""
  if ! adb_output="$(adb devices -l 2>&1)"; then
    echo "错误：执行 adb devices -l 失败。"
    echo "$adb_output"
    exit 1
  fi

  local line=""
  while IFS= read -r line; do
    if [[ "$line" == "List of devices attached"* || -z "$line" ]]; then
      continue
    fi
    local device_id
    local state
    device_id="$(printf '%s' "$line" | awk '{print $1}')"
    state="$(printf '%s' "$line" | awk '{print $2}')"
    if [[ "$state" == "device" ]]; then
      ids+=("$device_id")
      labels+=("$line")
    fi
  done <<< "$adb_output"

  if [[ ${#ids[@]} -eq 0 ]]; then
    echo "错误：未发现已连接且状态为 device 的 ADB 设备。"
    echo "可先执行：adb devices"
    exit 1
  fi

  if [[ ${#ids[@]} -eq 1 ]]; then
    DEVICE_ID="${ids[0]}"
    echo "检测到 1 台在线设备，直接使用: ${labels[0]}"
    return
  fi

  echo "=========================================="
  echo "请选择要启动投屏子窗口的设备："
  local i
  for ((i = 0; i < ${#ids[@]}; i++)); do
    echo "  $((i + 1)). ${labels[$i]}"
  done
  echo "=========================================="

  local choice=""
  while true; do
    read -r -p "输入序号 [1-${#ids[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ids[@]} )); then
      DEVICE_ID="${ids[$((choice - 1))]}"
      return
    fi
    echo "输入无效，请重新选择。"
  done
}

generate_idea_run_config() {
  local output_path="$1"
  local output_dir
  output_dir="$(dirname "$output_path")"
  mkdir -p "$output_dir"

  python3 - "$WINDOW_ID" "$DEVICE_ID" "$DEVICE_NAME" "$WINDOW_TITLE" "$NEW_DISPLAY" "$START_APP" "$RUN_CONFIG_NAME" "$output_path" <<'PY'
import sys
from urllib.parse import quote
from xml.sax.saxutils import escape

window_id, device_id, device_name, title, new_display, start_app, config_name, output_path = sys.argv[1:]

params = {
    "type": "mirror",
    "deviceId": device_id,
    "deviceName": device_name,
    "_windowTitle": title,
}
if new_display:
    params["newDisplay"] = new_display
if start_app:
    params["startApp"] = start_app

argument = "&".join(
    f"{quote(key, safe='')}={quote(value, safe='')}" for key, value in params.items()
)
additional_args = (
    f"--dart-entrypoint-args multi_window "
    f"--dart-entrypoint-args {window_id} "
    f"--dart-entrypoint-args {argument}"
)

content = f"""<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="{escape(config_name)}" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="additionalArgs" value="{escape(additional_args)}" />
    <option name="filePath" value="$PROJECT_DIR$/lib/main.dart" />
    <method v="2" />
  </configuration>
</component>
"""

with open(output_path, "w", encoding="utf-8") as file:
    file.write(content)

print("==========================================")
print("Flutter Run Configuration 已生成")
print(f"Config: {output_path}")
print(f"Name: {config_name}")
print(f"Window ID: {window_id}")
print(f"Arguments: {argument}")
print("==========================================")
PY
}

DEVICE_ID=""
DEVICE_NAME=""
WINDOW_TITLE=""
RESOLUTION=""
NEW_DISPLAY=""
START_APP=""
WINDOW_ID=""
APP_PATH=""
OUTPUT_PATH=""
RUN_AFTER_GENERATE=true
IDEA_RUN_CONFIG=false
RUN_CONFIG_NAME="Debug - 投屏子窗口"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-id)
      DEVICE_ID="$2"
      shift 2
      ;;
    --device-name)
      DEVICE_NAME="$2"
      shift 2
      ;;
    --title)
      WINDOW_TITLE="$2"
      shift 2
      ;;
    --resolution)
      RESOLUTION="$2"
      shift 2
      ;;
    --new-display)
      NEW_DISPLAY="$2"
      shift 2
      ;;
    --start-app)
      START_APP="$2"
      shift 2
      ;;
    --window-id)
      WINDOW_ID="$2"
      shift 2
      ;;
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --idea-run-config)
      IDEA_RUN_CONFIG=true
      RUN_AFTER_GENERATE=false
      shift
      ;;
    --run-config-name)
      RUN_CONFIG_NAME="$2"
      shift 2
      ;;
    --generate-only)
      RUN_AFTER_GENERATE=false
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "错误：未知参数 $1"
      show_usage
      exit 1
      ;;
  esac
done

if [[ -z "$DEVICE_ID" ]]; then
  select_adb_device
fi

if [[ -z "$DEVICE_NAME" ]]; then
  DEVICE_NAME="$DEVICE_ID"
fi

if [[ -z "$WINDOW_TITLE" ]]; then
  WINDOW_TITLE="$DEVICE_NAME"
fi

if [[ -z "$WINDOW_ID" ]]; then
  WINDOW_ID="script_mirror_$(date +%s)"
fi

if [[ -z "$RESOLUTION" && -n "$NEW_DISPLAY" ]]; then
  RESOLUTION="$NEW_DISPLAY"
fi

if [[ "$IDEA_RUN_CONFIG" == true ]]; then
  if [[ -z "$OUTPUT_PATH" ]]; then
    OUTPUT_PATH="$PROJECT_ROOT/.idea/runConfigurations/debug_mirror_window.xml"
  fi
  generate_idea_run_config "$OUTPUT_PATH"
  exit 0
fi

generate_idea_run_config "$PROJECT_ROOT/.idea/runConfigurations/debug_mirror_window.xml"

if [[ -z "$APP_PATH" ]]; then
  if [[ -d "$PROJECT_ROOT/Products/AnyDeck.app" ]]; then
    APP_PATH="$PROJECT_ROOT/Products/AnyDeck.app"
  elif [[ -d "$PROJECT_ROOT/build/macos/Build/Products/Release/AnyDeck.app" ]]; then
    APP_PATH="$PROJECT_ROOT/build/macos/Build/Products/Release/AnyDeck.app"
  else
    echo "错误：未找到 AnyDeck.app，请先构建，或通过 --app 指定 .app/可执行文件路径。"
    exit 1
  fi
fi

if [[ "$APP_PATH" == *.app ]]; then
  APP_NAME="$(basename "$APP_PATH" .app)"
  APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_NAME"
else
  APP_EXECUTABLE="$APP_PATH"
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "错误：应用可执行文件不存在或不可执行: $APP_EXECUTABLE"
  exit 1
fi

ARGUMENT_JSON="$(python3 - "$WINDOW_ID" "$DEVICE_ID" "$DEVICE_NAME" "$WINDOW_TITLE" "$RESOLUTION" "$NEW_DISPLAY" "$START_APP" <<'PY'
import json
import re
import sys

window_id, device_id, device_name, title, resolution, new_display, start_app = sys.argv[1:]

DEFAULT_WIDTH = 480.0
DEFAULT_HEIGHT = 800.0
TOP_CHROME_HEIGHT = 58.0


def resolve_window_size(value):
    match = re.search(r"(\d+)\s*[xX]\s*(\d+)", value or "")
    if not match:
        return DEFAULT_WIDTH, DEFAULT_HEIGHT

    width = int(match.group(1))
    height = int(match.group(2))
    if width <= 0 or height <= 0:
        return DEFAULT_WIDTH, DEFAULT_HEIGHT

    ratio = width / height
    viewer_max_width = DEFAULT_WIDTH
    viewer_max_height = DEFAULT_HEIGHT - TOP_CHROME_HEIGHT
    container_ratio = viewer_max_width / viewer_max_height
    if container_ratio > ratio:
        viewer_height = viewer_max_height
        viewer_width = viewer_height * ratio
    else:
        viewer_width = viewer_max_width
        viewer_height = viewer_width / ratio

    return max(200.0, viewer_width), max(200.0, viewer_height + TOP_CHROME_HEIGHT)


frame_width, frame_height = resolve_window_size(resolution)
arguments = {
    "type": "mirror",
    "deviceId": device_id,
    "deviceName": device_name,
    "_windowFrame": {
        "left": 0.0,
        "top": 0.0,
        "width": frame_width,
        "height": frame_height,
    },
    "_windowTitle": title,
}
if new_display:
    arguments["newDisplay"] = new_display
if start_app:
    arguments["startApp"] = start_app

print(json.dumps(arguments, ensure_ascii=False, separators=(",", ":")))
PY
)"

if [[ -n "$OUTPUT_PATH" ]]; then
  OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
  mkdir -p "$OUTPUT_DIR"
  python3 - "$APP_EXECUTABLE" "$WINDOW_ID" "$ARGUMENT_JSON" "$OUTPUT_PATH" <<'PY'
import os
import shlex
import stat
import sys

app_executable, window_id, argument_json, output_path = sys.argv[1:]

content = f"""#!/bin/bash
# 自动生成的 AdbManage 投屏子窗口启动文件。

set -e

APP_EXECUTABLE={shlex.quote(app_executable)}
WINDOW_ID={shlex.quote(window_id)}
ARGUMENT_JSON=$(cat <<'JSON'
{argument_json}
JSON
)

exec "$APP_EXECUTABLE" multi_window "$WINDOW_ID" "$ARGUMENT_JSON"
"""

with open(output_path, "w", encoding="utf-8") as file:
    file.write(content)

current_mode = os.stat(output_path).st_mode
os.chmod(output_path, current_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

print("==========================================")
print("投屏子窗口启动文件已生成")
print(f"Launcher: {output_path}")
print(f"App: {app_executable}")
print(f"Window ID: {window_id}")
print(f"Arguments: {argument_json}")
print("==========================================")
PY
elif [[ "$RUN_AFTER_GENERATE" == false ]]; then
  echo "=========================================="
  echo "投屏子窗口启动参数"
  echo "App: $APP_EXECUTABLE"
  echo "Window ID: $WINDOW_ID"
  echo "Arguments: $ARGUMENT_JSON"
  echo "未生成启动文件。如需生成文件，请显式传入 --output <path>。"
  echo "=========================================="
  exit 0
fi

if [[ "$RUN_AFTER_GENERATE" == true ]]; then
  echo "正在启动投屏子窗口..."
  exec "$APP_EXECUTABLE" multi_window "$WINDOW_ID" "$ARGUMENT_JSON"
fi
