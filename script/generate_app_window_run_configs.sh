#!/bin/bash
# 生成 AdbManage App 子窗口的 Android Studio/IntelliJ Flutter Run Configuration。

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
RUN_CONFIG_DIR="$PROJECT_ROOT/.idea/runConfigurations"

show_usage() {
  echo "=========================================="
  echo "使用方法 (Usage):"
  echo "  $0 [options]"
  echo ""
  echo "选项说明 (Options):"
  echo "  --output-dir <path>        Run Configuration 输出目录，默认 .idea/runConfigurations。"
  echo "  -h, --help                 显示此帮助并退出。"
  echo ""
  echo "生成内容:"
  echo "模拟器子窗口 -> type=emulator_manager"
  echo "控制台子窗口 -> type=console"
  echo "=========================================="
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      RUN_CONFIG_DIR="$2"
      shift 2
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

if [[ "$RUN_CONFIG_DIR" != /* ]]; then
  RUN_CONFIG_DIR="$PROJECT_ROOT/$RUN_CONFIG_DIR"
fi

mkdir -p "$RUN_CONFIG_DIR"

python3 - "$RUN_CONFIG_DIR" <<'PY'
import os
import sys
from urllib.parse import quote
from xml.sax.saxutils import escape

output_dir = sys.argv[1]

configs = [
    {
        "file": "emulator_window.xml",
        "name": "模拟器子窗口",
        "window_id": "debug_emulator_window",
        "params": {
            "type": "emulator_manager",
            "_windowTitle": "模拟器管理",
        },
    },
    {
        "file": "console_window.xml",
        "name": "控制台子窗口",
        "window_id": "debug_console_window",
        "params": {
            "type": "console",
            "_windowTitle": "控制台",
        },
    },
]


def build_argument(params):
    return "&".join(
        f"{quote(key, safe='')}={quote(value, safe='')}"
        for key, value in params.items()
    )


def build_xml(config):
    argument = build_argument(config["params"])
    additional_args = (
        f"--dart-entrypoint-args multi_window "
        f"--dart-entrypoint-args {config['window_id']} "
        f"--dart-entrypoint-args {argument}"
    )
    return f"""<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="{escape(config['name'])}" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="additionalArgs" value="{escape(additional_args)}" />
    <option name="filePath" value="$PROJECT_DIR$/lib/main.dart" />
    <method v="2" />
  </configuration>
</component>
"""


print("==========================================")
print("开始生成 App 子窗口 Run Configuration")
for config in configs:
    path = os.path.join(output_dir, config["file"])
    with open(path, "w", encoding="utf-8") as file:
        file.write(build_xml(config))
    print(f"{config['name']}: {path}")
print("==========================================")
PY
