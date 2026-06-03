---
description: 命令行进程管理与终端数据流规范
globs:
  - "lib/core/adb/**/*.dart"
  - "lib/core/process/**/*.dart"
  - "lib/core/terminal/**/*.dart"
alwaysApply: false
---

# 命令行进程管理规范

1. **执行超时约束**
   - 任何执行外部命令（如 `adb`、`scrcpy` 等）的代码，默认应加上超时限制（通常为 15 秒）。
   - 如果发生超时，应当在捕获 `TimeoutException` 时主动调用 `process.kill()`。如果进程无响应，使用 `ProcessSignal.sigkill` 进行强制终止，并返回明确的超时错误说明，防止进程泄漏挂起系统。

2. **异步非阻塞**
   - 绝对不要在 Flutter UI 线程中同步执行耗时较长的命令行命令。
   - 使用 `Process.start` 启动后台进程，并通过 Stream 异步接收标准输出 (`stdout`) 和标准错误 (`stderr`)。
   - 对 `stdout` 和 `stderr` 流使用 `utf8.decoder` 转换，以支持中文字符的正常显示。

3. **安全参数转义**
   - 传入命令行的参数应作为 `List<String>` 列表传入 `Process.start`，而不是将它们拼接为单个长字符串并在 Shell 中执行，从而规避 Shell 注入风险和空格路径解析失败的问题。
   - 例如使用 `AdbService.shellArgs(deviceId, ['pm', 'list', 'packages'])` 而非拼接字符串。

4. **终端流处理与自动销毁**
   - 在 UI 模块中（如 ADB Terminal Tab 或 Logcat 日志控制台），当用户切出 Tab 或关闭对应页面时，必须监听 Lifecycle / Dispose，确保调用进程的 `kill()` 释放系统资源。
   - 避免日志数据积压导致内存溢出：如果是一个持续输出的 StreamProvider（如实时 Logcat），需要对缓存的日志列表长度做上限控制（如最多保留 1000 行），超出时丢弃旧日志。
