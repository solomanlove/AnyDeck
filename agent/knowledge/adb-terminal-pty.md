# 终端 PTY 与 root 提示符

## 问题与目标

MIX3 的 `/sbin/su` 在普通管道中可以成功进入 root shell，但不输出新的提示符。
旧终端 UI 固定拼接 `设备名:/ $`，导致提权后仍显示 `$`，看起来像 `su` 未执行。
不能根据用户输入了 `su` 或 `exit` 推断权限，应保留设备真实的 shell 回显。

## 实现与范围

- `lib/core/terminal/adb_terminal_session.dart`：新建和重连均使用 `adb -s <deviceId> shell -tt`。Dart `Process.start` 的 stdin 是管道，单个 `-t` 不保证申请 PTY。
- PTY 返回真实提示符、命令回显和命令输出；发送命令只更新历史，不再添加本地输入行，避免重复回显。没有额外注入 `id`、`pwd` 或后台轮询命令。
- `lib/features/terminal/terminal_tab.dart`：移除输入框及历史行中硬编码的设备名、目录和 `$`。输入框仅显示中性标记 `›`，真实 `$ / #` 和目录显示在上方设备输出中；同一行追加提示符时也触发滚动。
- `lib/core/terminal/terminal_newline_normalizer.dart`：按流隔离回车状态，将 CR、CRLF、MIX3 的 CRCRLF 统一为 LF；支持跨数据块换行，不等待完整行，提示符可立即显示。
- 保留 1500 行输出上限、命令历史、原有明暗主题和进程关闭机制。无新依赖、全局 Provider 或跨窗口通信变更，不涉及投屏。

## 行为边界

- 这是按行显示的交互控制台，并非完整 VT 终端模拟器；不保证 `vim` 等全屏应用布局。
- PTY 合并远端 stdout/stderr；远端错误按设备输出显示，ADB 客户端自身 stderr 仍独立接收。
- `su` 被拒绝、不存在或执行 `su -c id` 时，显示实际返回结果，不会自行把提示符切为 `#`。
- 设备自定义 PS1 或关闭回显时同样遵循设备行为；root 判定仍可用 `id` 的 `uid=0(root)` 确认。
- 已经打开的旧管道会话需要关闭后新建，才能采用 PTY。

## 验证与回归

1. `flutter analyze`：检查类型与编译问题。
2. `flutter test test/terminal_newline_normalizer_test.dart`：覆盖 MIX3 回显、任意拆包、无换行提示符、中文、空行和多会话状态隔离。
3. MIX3 只读 ADB 验证：`su` → `id` → `cd /data/local/tmp` → `exit` → `id`，确认 `#`、root 身份、目录和 `$` 的往返；退出后关闭测试会话。
4. 未 root 设备：`su` 失败时保留错误和普通 shell 提示符。
5. UI 手动回归：新建 / 重连、上下键历史、明暗主题、长日志、设备断连；确认无重复输入、无额外空白行、提示符可见。默认不启动项目，UI 回归留待用户运行验证。

### 本次验证记录

- 4 项换行回归测试通过；本次 4 个 Dart 文件的定向 `flutter analyze` 无问题。
- MIX3 的 PTY 回显已确认 root、目录切换及退出 root 的往返；未 root 的 pudding 返回 `su: inaccessible or not found`，`id` 仍为 shell。
- 全仓 `flutter analyze` 未通过：本次未修改的 `test/apps_tab_filter_test.dart` 存在必填参数缺失和未定义引用，另外有其他模块的既有警告与提示。未扩大修改范围。
- 未启动 Flutter 项目，UI 手动回归尚未执行。
