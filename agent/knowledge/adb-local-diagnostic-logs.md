# AnyDeck 控制台与本地诊断日志

## 业务目标与入口

- 排查 AnyDeck 自身的运行错误、异常堆栈和 ADB/HDC 命令失败。
- 控制台新增“仅关键日志（警告 / 错误）”，可与关键词搜索叠加；隐藏心跳不会隐藏 W/E/F 级别的轮询失败。
- 开发者选项 → 本地日志与故障排查 → 抓取本地日志，选择位置保存 `.log` 文件。控制台复用相同按钮。
- 无需连接手机；导出包含保留的历史会话。控制台实时列表展示当前会话，历史文件通过导出查看。
- 此功能采集桌面 App 日志；手机日志继续使用 Logcat Tab。

## 实现与职责

| 文件 | 职责 |
| --- | --- |
| `lib/core/logging/app_log_recorder.dart` | Isolate 内启动期采集、完整时间戳、窗口来源、脱敏与有界历史 |
| `lib/core/logging/app_log_capture.dart` | `debugPrint`、`FlutterError.onError`、`PlatformDispatcher.onError` 捕获及子窗口订阅预热 |
| `lib/core/logging/local_log_store.dart` | 串行异步写入、轮转、历史清理、磁盘失败隔离 |
| `lib/core/logging/log_service.dart` | 保持现有命令日志接口；各窗口日志汇总、150ms 批处理和控制台广播 |
| `lib/core/logging/local_log_export.dart` | 保存位置选择、导出互斥、多窗口刷盘、容量受限的诊断快照 |
| `lib/app/widget/local_log_capture_button.dart` | 共享导出按钮、取消、成功、部分成功与失败反馈 |
| `lib/features/developer/widget/developer_local_logs_card.dart` | 调试页入口，复用现有卡片样式 |
| `lib/app/window/console/console_window_panel.dart` | 关键日志筛选、日期与多行堆栈展示、导出入口 |

没有引入新依赖。复用 `path_provider`、`file_selector`、Riverpod 与 `desktop_multi_window`。

`main()` 使用 `runZonedGuarded` 包裹启动过程，Binding 与 `runApp` 在同一个 Zone 中创建。未处理异步异常记录 E 级别与堆栈，保留 stderr 输出。Flutter / Platform 原错误处理器继续调用。已捕获并使用 `debugPrint` 输出的故障，按常见错误 / 警告关键词推断级别；此推断可能产生误判。

## 容量与生命周期

- 各 Isolate 在 Application Support 的 `logs/` 目录内独立写入 `anydeck_<pid>_<main或window_id>.log`，避免多个窗口竞争一个文件。
- 每个文件约 2 MiB，轮转为 `.previous.log`，每个来源最多保存两份。主窗口启动时保留最近 40 个文件，跳过当前 PID 的文件；本次运行继续创建的窗口文件不受该启动清理数量限制。
- 内存历史和跨窗口待处理队列各最多 1000 条；消息主体最多 8000 字符。磁盘队列最多 256 条，溢出有缺失计数与日志提示。
- 普通日志约 500ms 批量落盘，E/F 级日志请求立即刷盘；写入使用异步 File IO。进程强制终止或 native crash 时，仍可能丢失尚未完成的写入。
- 控制台沿用 `ListView.builder` 虚拟列表。日志通信不逐条枚举窗口，改为批量更新。
- 清空控制台仅清理当前显示，不删除磁盘中的故障记录。

## 跨窗口协议

- 沿用主窗口 `any_deck/console_logs` 单向通道和子窗口 `SubWindowMethodDispatcher`。
- 子窗口 → 主窗口：`log_batch_from_sub`，参数为 `List<String>`。
- 主窗口 → 控制台：`log_batch`，参数为 `List<String>`。
- `get_history` 返回包含待处理队列的快照；与实时记录按完整日志去重，限制为 1000 条。
- 保留 `log` / `log_from_sub` 兼容入口及 `clear` / `clear_from_sub`。
- `flush_local_logs` 请求窗口刷盘并返回是否可用且未丢失记录；主窗口通过汇总通道，子窗口通过 window controller 调用。
- 窗口枚举和通信使用 2 秒超时。关闭窗口、脚本直启缺少主窗口时保留本地日志，不把通信失败再次打印到日志，避免反馈循环。

## 导出和数据边界

- 导出按钮打开保存对话框期间即禁用；取消不报错。
- 导出前请求其他窗口刷盘，再刷新本窗口。按修改时间从新到旧读取保留文件，逐文件流式写入，固定每次读取范围。
- 日志正文读取预算为 20 MiB，单文件最多读取尾部 2 MiB；报告头、文件分隔和状态文字不计入正文预算。UTF-8 尾部截断使用容错解码。
- 无本地文件或磁盘写入发生缺失时，追加预算内的当前内存日志。
- 包含时间、构建版本环境值与操作系统信息。构建时未提供版本环境值则为 `unknown`，不伪造版本。
- 窗口不可用、文件读取失败、缓冲丢失或达到截断条件时，结果标记 `PARTIAL`，UI 给出部分成功提示；保存位置不可写则报失败。
- 禁止将导出目标指向受管理日志目录（包含已有软链接目标），防止覆盖采集源文件。
- 常见 Authorization / Token / API Key / Password / Cookie 值在进入内存与磁盘前脱敏。自由文本仍可能含设备标识、路径或业务数据，UI 提醒分享前检查。
- 不包含未转发给 Dart 的 Rust / Swift / Flutter Engine 原生 stderr、系统 native crash report、任意后台 Isolate 或普通 `print` 输出。日志中不存在的历史异常无法补采。

## 验证与回归

2026-10-04 定向验证：22 项测试通过，以下目标范围静态分析通过（No issues found）。

```bash
flutter test --no-pub test/local_logging_test.dart test/console_diagnostics_test.dart test/developer_mode_test.dart
flutter analyze --no-pub lib/core/logging lib/main.dart lib/app/window/console/console_window_panel.dart lib/app/widget/local_log_capture_button.dart lib/features/developer/widget/developer_local_logs_card.dart lib/features/developer/widget/developer_tools_section.dart lib/app/l10n/app_localized_values.dart lib/app/l10n/tables/app_l10n_local_logs.dart test/local_logging_test.dart test/console_diagnostics_test.dart
```

自动覆盖：凭据及含空格值脱敏、多行堆栈、严重级别、内存上限、并发刷盘顺序、轮转后重新读取、队列溢出、磁盘失败恢复、历史清理、原异常处理器保留、清空不删文件、历史会话导出、部分结果、源文件保护、控制台心跳与关键日志筛选，以及调试卡片中英文和明暗主题。

待桌面手工验证：

1. 打开主窗口、控制台和投屏窗口；制造命令失败，确认控制台收到窗口来源与错误堆栈。
2. 在主窗口和控制台分别导出，检查正在运行的其他窗口是否完成刷盘。
3. 退出后重新启动，通过导出确认仍包含保留的上一会话记录。
4. 验证系统保存对话框取消、重复点击、只读目标目录与保存路径含中文。
5. 验证投屏期间无明显日志广播导致的卡顿，主题与语言切换正确。

未启动桌面 App，未进行 native crash、真机投屏或真实多 Engine 通道验收；自动测试中的窗口通道使用 mock。
