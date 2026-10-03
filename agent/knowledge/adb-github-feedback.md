# GitHub Issues 意见反馈

## 业务目标与入口

- 设置 → 关于与支持 → 意见反馈。
- 支持「报告问题」「功能建议」，预览正文后打开默认浏览器，由用户在 GitHub 补充标题和详情、登录并提交。
- 「查看已有反馈」打开 `https://github.com/solomanlove/AnyDeck/issues`；「复制链接」可在浏览器启动失败时手动继续。
- 无后端、无 API Token、无新增插件依赖。没有设备连接时也可使用。

## 架构与改动范围

| 文件 | 职责 |
| --- | --- |
| `lib/features/feedback/widget/settings_feedback_entry.dart` | 设置页独立入口 |
| `lib/features/feedback/widget/github_feedback_dialog.dart` | 类型切换、预览、打开及复制反馈状态 |
| `lib/features/feedback/model/github_feedback.dart` | 仓库地址、正文组装和 URL 编码 |
| `lib/core/process/host_platform_service.dart` | 默认浏览器启动，复用既有 HostPlatformService Provider |
| `lib/app/l10n/tables/app_l10n_feedback.dart` | 中英文 UI 和正文模板 |
| `.github/ISSUE_TEMPLATE/` | 网页端问题报告和功能建议模板 |
| `test/github_feedback_test.dart` | URI 与 Widget 流程验证 |

## 核心设计与边界

1. `Uri.https` 构造 `/issues/new?title=...&body=...`，不附加要求额外权限的 labels/assignees，也不依赖远端 template 参数。网页模板尚未合入默认分支时，App 仍能带正文打开新 Issue。
2. 系统仅预填 `Platform.operatingSystem`，系统版本、AnyDeck 版本、设备型号和连接方式由用户在 GitHub 补充。当前设置页版本为硬编码，因此反馈不复用该值，以免未来版本变更时带入错误信息。
3. 不采集设备序列号、IP、日志、账号、通知内容；附件由用户脱敏后手动添加。URL 内容进入浏览器前可完整预览。
4. 主窗口内普通 Dialog，使用当前 Localizations 和 Theme，无新 Provider、持久化或跨 Isolate 通信。无需启动 ADB/HDC、设备轮询或投屏进程。
5. macOS 使用 `open`，Windows 使用 `rundll32.exe url.dll,FileProtocolHandler`，Linux 使用 `xdg-open`。独立参数传递，不经 Shell 拼接；仅接受含 host 的 HTTP(S) URI。
6. 浏览器启动器等待上限 15 秒，超时先终止、2 秒后强制终止；stdout/stderr 消费后丢弃、最终取消订阅。弹窗关闭后的完成回调由 mounted 防护。
7. 打开期间禁用重复操作；失败时保留弹窗并复制最近失败的目标链接。进程返回成功仅表示已请求打开浏览器，不代表网络可达或 Issue 已提交。
8. `.github/ISSUE_TEMPLATE/*.md` 需推送并合入默认分支后才成为线上可选模板；本次不推送、不创建测试 Issue。

协议参考：[GitHub 新建 Issue URL 参数](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue#creating-an-issue-from-a-url-query)。

## 五项影响评估

- 投屏：无会话、触控、音频或息屏逻辑改动。
- 国际化：中文、英文同时补齐，通过统一字符串表聚合。
- 主题：入口、预览和状态提示全部读取当前 Theme。
- 性能：仅用户操作时启动系统链接处理器，无常驻任务和设备查询。
- 安全：无凭据、无自动上传、无 Shell 字符串执行；明确公开反馈和隐私提示。

## 验证与回归

自动验证：

```bash
flutter test --no-pub test/github_feedback_test.dart
flutter analyze --no-pub lib/features/feedback lib/core/process/host_platform_service.dart lib/app/l10n/app_localized_values.dart lib/app/l10n/tables/app_l10n_feedback.dart test/github_feedback_test.dart
git diff --check
```

- 2026-10-03：5 项测试通过，覆盖中文/特殊字符编码、正文 URL 长度、非 HTTP(S) 链接拒绝、中英文与明暗主题下类型切换、防重复打开、启动失败提示和复制链接。
- 上述反馈模块、宿主机服务、国际化与测试文件的定向分析通过（No issues found）；`git diff --check` 通过。
- 包含 Dashboard 的定向分析仅报告既有 `dashboard_screen.dart` 未使用 `liquid_glass_background.dart` import；本次保留无关代码。
- GitHub REST 只读查询确认目标仓库公开、`has_issues: true`、默认分支 `main`。
- 未启动 App，未进行真实浏览器登录/提交、Windows/Linux 桌面验证。

后续手动验收：

1. 无设备连接时进入设置，切换中英文、明暗主题，确认弹窗可滚动且操作可见。
2. 两种反馈分别跳转，确认中文正文及换行保留、标题前缀正确；在 GitHub 编辑标题、环境信息并按需提交。
3. 查看已有反馈应打开列表，启动器失败时复制的应为对应目标链接；网络失败由浏览器呈现。
4. 连续点击只启动一次；等待期间关闭弹窗应无 disposed Widget 异常。
5. 三个平台分别验证默认浏览器打开；受限网络下验证复制链接和手动访问路径。

后续若增加版本读取，应使用真实运行包版本；若增加本地自由输入，应针对 URL 长度增加完整正文复制兜底。
