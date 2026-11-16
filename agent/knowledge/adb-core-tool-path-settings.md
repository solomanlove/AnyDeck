# AnyDeck 核心依赖路径设置

## 使用入口与目标

2026-11-16：在「设置 → 核心依赖」统一管理 ADB、HDC、iOS（go-ios）、scrcpy、Android Emulator、avdmanager 和 iproxy。设备管理标题栏原有文件夹菜单移除，原来的三平台「打开目录」「打开终端」功能迁入对应工具的设置 Card。

每个工具可以手动填写或选择可执行文件，保存后显示当前解析路径，也可以恢复默认。文件选择只修改草稿，点击保存才生效；目录和终端操作使用已保存的配置。分类和全局搜索都可以定位工具及其操作，中英文、明暗 Theme 和窄窗口复用同一套控件。

## 数据与实现边界

| 入口 | 职责 |
| --- | --- |
| `lib/core/process/tool_path_settings.dart` | 可配置工具集合、路径校验、Preference key 和启动加载 |
| `lib/core/process/tool_path_resolver.dart` | 用户覆盖、应用下载注册、既有 SDK / 常见安装位置、PATH 的统一解析 |
| `lib/app/settings/app_settings_tool_paths.dart` | `setToolPath` 保存、重置、更新状态与跨窗口同步 |
| `lib/features/overview/settings/tool_path_settings_catalog.dart` | 设置分类、检索元数据与 Provider 连接 |
| `lib/features/overview/widget/tool_path_setting_field.dart` | 输入、文件选择、错误展示与操作防重 |
| `lib/features/devices/controller/platform_tools_controller.dart` | 复用现有宿主目录、终端能力和本地化反馈 |

没有新增依赖。`AppSettings.toolPaths` 持有用户覆盖映射；每个工具分别保存到 `settings.toolPath.<tool>`，避免不同窗口修改不同工具时覆盖整份 Map。空字符串删除对应键并恢复自动解析，应用自动下载的注册路径仍保留。`ios` 与 `go-ios` 共用 `ios` 设置项。

保存时先校验路径，再写入 Preference，写成功后才更新当前 Isolate 和 UI。只接受现有普通文件的绝对路径；POSIX 通过 `access(X_OK)` 检查当前用户的实际执行权限，Windows 检查可执行扩展名。相对路径、目录、缺失文件或不可执行文件均不覆盖原配置。不运行用户选中的程序做版本探测，CLI 路径独立传给既有进程封装；工具终端的初始化脚本按对应平台转义路径。

自定义路径一旦保存便保持显式优先；文件后来被移动或删除时，命令和打开目录操作明确报错，不悄悄切换到另一套工具。PATH 定位不启动 Shell，可将已安装在 PATH 中的工具解析为绝对路径供目录操作使用。

## 启动、多窗口与执行机制

每个 Engine 的 `main` 在创建服务前调用 `loadToolPathSettings`，设置 Controller 同样加载路径到 `AppSettings`。保存沿用既有设置广播：

```text
method: update_tool_path
arguments: {tool: adb | hdc | ios | ..., path: <absolute-path-or-empty>}
```

修改窗口写入持久化并向主窗口及其他已打开的子窗口同步。接收端等待本地设置加载完成，只应用单工具快照，不重复写 Preference，也不再次广播。沿用真实窗口 ID 和 `SubWindowMethodDispatcher`，不假设主窗口编号。

ADB、HDC、go-ios、scrcpy、Emulator、avdmanager、iproxy 和 Remote HDC Server 默认在后续启动命令时读取最新路径；显式构造注入仍保持固定，方便测试和专用调用。配置变化不销毁服务 Provider，不中断投屏、日志和转发进程。已运行的会话需要重新连接；设备管理保留的服务重启入口可用于需要重启服务的情况。

HDC 自定义路径存在时，设备发现和 Shell 绕过使用固定环境的 Rust HDC DAL，统一走当前配置 CLI；批量 HarmonyOS 脚本也统一交给 `HdcService.shell` 决定执行通道。iOS 自定义路径存在时，设备发现走对应 go-ios。默认配置的原生通道保留。

## 回归与验收边界

- 核心单元测试覆盖保存、重置、启动重载、无效输入、含空格与中文路径、既有服务读取新配置、真实假 CLI 执行、PATH 定位、主窗口广播、子窗口上送与接收端不重复落盘。
- Widget 测试覆盖真实目录搜索、Provider / Preference 保存、非法路径保持旧值、恢复默认，以及中英文 × Light/Dark × 窄窗口、选择取消、操作防重与目录/终端入口。
- Dashboard 回归检查旧目录菜单移除、八类设置切换与原有设置操作；目录 Controller 测试检查三平台的目录和终端路由、文件被删除、系统失败和异常反馈；批量脚本验证通过统一 HDC 服务执行。
- 本次不启动桌面 App。系统文件选择器、Finder / Explorer / Terminal、多 Engine 原生广播和真实设备工具兼容性仍属于人工验收；自动测试使用隔离的系统接口与临时 CLI，不等同于真机验收。

新增文件均小于 500 行；存量超限文件仅做与路径生效和旧入口移除直接相关的局部修改，不附带无关拆分或格式化。

### 本次验证结果

15 个相关测试文件共 86 项通过：

```bash
flutter --no-version-check test --no-pub \
  test/tool_path_settings_test.dart \
  test/tool_path_setting_field_test.dart \
  test/platform_tool_directory_actions_test.dart \
  test/batch_script_tool_path_test.dart \
  test/app_settings_test.dart test/settings_review_test.dart \
  test/adb_service_test.dart test/ios_command_service_test.dart \
  test/ios_device_service_test.dart test/emulator_launch_test.dart \
  test/device_list_context_menu_test.dart \
  test/dashboard_shell_navigation_test.dart test/settings_workspace_test.dart \
  test/menu_corner_indicator_test.dart test/service_restart_menu_button_test.dart
git diff --check
```

完整 `flutter analyze --no-pub --no-fatal-infos` 无 error；仓库原有 5 条 warning 和 SDK 等 info 保留，其中改动文件内仅 `EmulatorService.listEmulators` 原有的 `unawaited_return_in_try_block` warning。改动文件定向 analyze 使用 `--no-fatal-infos --no-fatal-warnings` 通过，无新增 error / warning；新 Dart 文件格式检查通过。没有为清理历史诊断修改无关代码。

## 2026-11-16 执行链复审与修复

复审发现并修复以下遗漏：

| 问题 | 修复与回归 |
| --- | --- |
| Android 批量脚本直接走 Rust Direct Socket，绕过新 ADB | 自定义 ADB 时走 `AdbService.shell`；成功返回的 DAL stub 验证原生调用次数为 0，并检查真实临时 CLI 参数 |
| 外部 scrcpy 会自行查找旧 ADB | 每次启动默认传入当前解析的 `ADB` 环境变量，保留显式参数优先级；同一服务连续替换两次的 fake CLI 均读取新值 |
| iOS 目录只解析 ios，可能与 go-ios 回退不一致 | 设置显示、目录和终端统一使用实际命令服务的 `executable` |
| 只切换终端目录仍会运行 PATH 或 alias 中的旧工具 | 新增 `ToolTerminalLauncher`，初始化工作目录、PATH 和准确文件别名；`ios` / `go-ios` 同时绑定，支持改名文件及含空格、引号的路径 |
| 系统启动器非零退出仍提示成功 | 目录和终端检查启动器退出码，短命启动器超时 TERM / KILL 回收；Linux / Explorer 长驻进程交接后继续排空双流，不误关用户窗口 |
| 一个子窗口不可用会阻断后续窗口广播 | 主窗口上送、逐窗口调用独立捕获异常，均有 15 秒上限，失败后继续同步其他窗口 |
| 新子 Engine 建立 Preference 缓存后漏收初始化广播 | 加载时 `reload()`；设置通道就绪后从主窗口拉取 `resolve_tool_paths` 完整快照，并以每工具 revision 保留请求期间收到的实时更新 |
| 任意执行位不等于当前用户能执行 | POSIX 校验和 PATH 查找复用 `access(X_OK)`；`chmod 001` 不再覆盖旧可用路径 |

工具终端仅初始化 Shell，不自动执行所选 CLI。macOS 使用临时 `.command` 文稿通过既有 `open -a Terminal` 打开，随后进入 bash；Linux 使用 `x-terminal-emulator -e /bin/bash`；Windows 通过编码的 PowerShell 启动 cmd，设置 UTF-8 代码页，并以终端独立环境变量间接绑定 doskey，避免中文乱码或 `$1` / `$T` / `%` 路径片段进入宏语法。临时配置由新 Shell 读取后自行清理，启动失败则立即删除，不修改用户的 Shell 配置文件。

验证使用临时 CLI、真实隔离 bash、可注入宿主启动器与独立 DAL stub，不启动桌面 App，不连接真机。Windows 启动参数和脚本转义由计划测试覆盖，真实 Windows Terminal / cmd 行为仍需 Windows 环境验收；运行中的设备会话仍按原有约定重新连接后使用新路径。

### 复审验证结果

22 个相关测试文件共 **142 项通过**；对改动 Dart 文件执行 `flutter analyze --no-pub --no-fatal-infos` 通过，无 error / warning，仅保留 SDK Material / Cupertino 弃用 info。新增 Dart 文件格式检查、文件行数检查及 `git diff --check` 通过。

本轮新增 `tool_path_window_sync_test.dart`、`host_platform_launcher_test.dart`、`tool_terminal_launcher_test.dart` 和 `scrcpy_tool_path_test.dart`，并扩展原路径、批量脚本与目录测试。综合回归同时覆盖既有 Dashboard、设置搜索、快捷键、接收名称、设备菜单、ADB / iOS 命令与模拟器启动。

额外以“原生必然成功”的专用 stub 重跑批量脚本及外部 scrcpy 共 3 项，通过以下 macOS 命令复现；断言自定义 ADB 时原生调用次数为 0，不依赖原生通道失败再回退：

```bash
clang -dynamiclib test/fixtures/tool_path_dal_stub.c -o /tmp/anydeck_tool_path_audit_stub.dylib
ANYDECK_DEVICE_BRIDGE=/tmp/anydeck_tool_path_audit_stub.dylib \
ANYDECK_TOOL_PATH_DAL_STUB=1 \
flutter --no-version-check test --no-pub \
  test/batch_script_tool_path_test.dart test/scrcpy_tool_path_test.dart
```
