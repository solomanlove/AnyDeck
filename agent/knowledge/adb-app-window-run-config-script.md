# App 子窗口 Run Configuration 生成脚本

## 背景

`script/generate_app_window_run_configs.sh` 用于生成 AnyDeck App 子窗口的 Android Studio / IntelliJ Flutter Run Configuration。该脚本只写入 `.idea/runConfigurations/`，不启动 App；投屏子窗口配置会读取 `adb devices -l` 中状态为 `device` 的在线设备。

## 生成文件

| 文件 | IDE 显示名称 | 子窗口参数 |
| --- | --- | --- |
| `.idea/runConfigurations/console_window.xml` | `控制台子窗口` | `type=console` |
| `.idea/runConfigurations/mirror_window_<serial>.xml` | `投屏子窗口 - <deviceName>` | `type=mirror&deviceId=<serial>` |

## 参数机制

所有配置都通过 Flutter 的 `--dart-entrypoint-args` 调用 `lib/main.dart` 的多窗口入口：

```bash
--dart-entrypoint-args multi_window
--dart-entrypoint-args <windowId>
--dart-entrypoint-args type=<sub_window_type>
```

`lib/main.dart` 按明确的子窗口类型分发。独立模拟器管理窗口已移除，未知类型不再回退到管理页。

投屏配置会为每台在线设备生成一个独立入口；如果没有在线设备，脚本仍会生成控制台窗口配置，并跳过投屏配置。

## 使用方式

```bash
./script/generate_app_window_run_configs.sh
```

如果要输出到其他目录：

```bash
./script/generate_app_window_run_configs.sh --output-dir /tmp/runConfigurations
```
