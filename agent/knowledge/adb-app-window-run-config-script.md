# App 子窗口 Run Configuration 生成脚本

## 背景

`script/generate_app_window_run_configs.sh` 用于生成 AdbManage App 非投屏子窗口的 Android Studio / IntelliJ Flutter Run Configuration。该脚本只写入 `.idea/runConfigurations/`，不启动 App、不依赖 ADB。

## 生成文件

| 文件 | IDE 显示名称 | 子窗口参数 |
| --- | --- | --- |
| `.idea/runConfigurations/debug_emulator_window.xml` | `模拟器子窗口` | `type=emulator_manager` |
| `.idea/runConfigurations/debug_console_window.xml` | `控制台子窗口` | `type=console` |

## 参数机制

两个配置都通过 Flutter 的 `--dart-entrypoint-args` 调用 `lib/main.dart` 的多窗口入口：

```bash
--dart-entrypoint-args multi_window
--dart-entrypoint-args <windowId>
--dart-entrypoint-args type=<sub_window_type>
```

`lib/main.dart` 会把非 `mirror`、非 `console` 的类型交给 `EmulatorManagerWindowApp`，但模拟器管理窗口的业务类型应保持为 `emulator_manager`，与主窗口菜单和 `createAdbManageWindow()` 的参数一致。

## 使用方式

```bash
./script/generate_app_window_run_configs.sh
```

如果要输出到其他目录：

```bash
./script/generate_app_window_run_configs.sh --output-dir /tmp/runConfigurations
```
