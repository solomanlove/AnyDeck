# 投屏子窗口启动文件生成脚本

## 背景

项目内投屏独立窗口通过 `multi_window <windowId> <json>` 启动，JSON 参数最终由 `lib/main.dart` 解析，并传入 `MirrorWindowApp`。为了便于在主窗口外快速复现投屏子窗口启动链路，`script/generate_mirror_window_launcher.sh` 可根据同一套参数直接启动投屏子窗口，也可以按需生成 IDE Run Configuration。

## 参数映射

| 脚本参数 | 子窗口 JSON 字段 | 说明 |
| --- | --- | --- |
| `--device-id` | `deviceId` | 必填，目标 ADB 设备 ID。 |
| `--device-name` | `deviceName` | 窗口内展示名称，默认等于 `deviceId`。 |
| `--title` | `_windowTitle` | 原生窗口标题，默认等于 `deviceName`。 |
| `--resolution` | `_windowFrame` | 用于按项目默认算法计算初始窗口尺寸。 |
| `--new-display` | `newDisplay` | 单 App 虚拟副屏分辨率。 |
| `--start-app` | `startApp` | 虚拟副屏启动的 App 包名。 |
| `--window-id` | `args[1]` | 子窗口 ID，默认自动生成 `script_mirror_<timestamp>`。 |

## 设备选择

如果没有传入 `--device-id`，脚本会先执行：

```bash
adb devices -l
```

然后只保留状态为 `device` 的已连接设备：如果只有 1 台在线设备，脚本会直接使用该设备并继续生成/启动；如果有多台在线设备，才展示列表让用户输入序号。`offline`、`unauthorized` 等状态不会进入可选列表，避免直接启动后连接失败。

## 使用方式

```bash
./script/generate_mirror_window_launcher.sh
```

也可以显式指定设备，跳过交互选择：

```bash
./script/generate_mirror_window_launcher.sh \
  --device-id emulator-5554 \
  --device-name Pixel_8 \
  --resolution 1080x2400
```

普通运行不会生成 `.command` 文件，但会先同步更新 `.idea/runConfigurations/debug_mirror_window.xml`，再直接调用 `AnyDeck.app/Contents/MacOS/AnyDeck`：

```bash
AnyDeck multi_window script_mirror_xxx '{"type":"mirror",...}'
```

如果需要生成 Android Studio / IntelliJ 的 Flutter Run Configuration：

```bash
./script/generate_mirror_window_launcher.sh --idea-run-config
```

默认写入 `.idea/runConfigurations/debug_mirror_window.xml`，IDE 顶部运行入口会出现 `Debug-投屏子窗口`。该模式只生成 XML，不会立即启动投屏窗口；需要运行时从 IDE 选择对应入口。

## 边界

- 脚本默认生成后立即启动投屏子窗口；调试或只想保留启动文件时使用 `--generate-only`。
- 普通运行不创建 `script/generated/`；只有显式传入 `--output <path>` 时才会生成启动文件。
- 每次普通运行都会同步更新 `.idea/runConfigurations/debug_mirror_window.xml`，方便在 Android Studio/IntelliJ 顶部运行入口直接选择。
- `--idea-run-config` 模式会生成 Flutter Run Configuration，并通过 `--dart-entrypoint-args multi_window ...` 传递子窗口参数。
- 默认优先查找 `Products/AnyDeck.app`，其次查找 `build/macos/Build/Products/Release/AnyDeck.app`；也可以通过 `--app` 显式指定 `.app` 或可执行文件。
- 生成物使用项目现有投屏子窗口参数，不引入新的 Flutter 参数协议。
- 脚本直启的投屏窗口不是由主窗口 `desktop_multi_window` 创建的，不能假定主窗口通信通道一定存在。日志上报、macOS 自定义窗口 channel 缺失时必须降级到本地记录或 `window_manager` 能力。
