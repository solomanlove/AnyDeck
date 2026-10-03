# GitHub Issues 意见反馈

## 业务目标与入口

- 设置 → 关于与支持 → 意见反馈。
- 支持「报告问题」「功能建议」，在 App 内编辑标题和正文、自动补齐环境信息，再打开默认浏览器，由用户在 GitHub 登录、确认并提交。
- 「查看已有反馈」打开 `https://github.com/solomanlove/AnyDeck/issues`；短正文支持复制链接，长正文支持完整复制后在 GitHub 粘贴。
- 无后端、无 API Token、无新增插件依赖。没有设备连接时也可使用。

## 架构与改动范围

| 文件 | 职责 |
| --- | --- |
| `lib/features/feedback/widget/settings_feedback_entry.dart` | 设置页独立入口 |
| `lib/features/feedback/widget/github_feedback_dialog.dart` | 标题/正文编辑、类型切换、打开及复制反馈状态 |
| `lib/features/feedback/controller/feedback_draft_controller.dart` | 两类独立草稿、环境快照 Provider、编码长度检查与长正文处理 |
| `lib/features/feedback/model/feedback_environment.dart` | 电脑系统/架构、构建版本与已缓存设备信息格式化 |
| `lib/features/feedback/model/github_feedback.dart` | 仓库地址、正文组装和 URL 编码 |
| `lib/core/process/host_platform_service.dart` | 默认浏览器启动，复用既有 HostPlatformService Provider |
| `lib/app/l10n/tables/app_l10n_feedback.dart` | 中英文 UI 和正文模板 |
| `.github/ISSUE_TEMPLATE/` | 网页端问题报告和功能建议模板 |
| `test/github_feedback_test.dart` / `test/feedback_draft_controller_test.dart` | URI、草稿保留、环境字段与 Widget 流程验证 |

## 核心设计与边界

1. `Uri.https` 构造 `/issues/new?title=...&body=...`，不附加要求额外权限的 labels/assignees，也不依赖远端 template 参数。网页模板尚未合入默认分支时，App 仍能带正文打开新 Issue。
2. 电脑信息使用 `Platform.operatingSystem`、`Platform.operatingSystemVersion` 和 `Abi.current()`；App 版本使用编译期 `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`。已核对本机 Flutter 3.47.2 的 `flutter_command.dart`，工具链会从 build 参数或 pubspec 注入这两个值；未注入时明确显示未获取，不回退到硬编码版本。
   设备信息复用 `deviceRegistryProvider` 的型号/系统版本缓存：优先当前在线选中设备，无选择时仅自动使用唯一在线设备，多设备未选择、离线、缓存缺失时显示未获取。连接按当前通道区分 USB、网络和 Android Emulator；现有 iOS 缓存不足以判定连接方式时显示未获取。
3. 不采集设备序列号、IP、日志、账号、通知内容；附件由用户脱敏后手动添加。环境信息作为正文的一部分，可修改或删除；URL 内容进入浏览器前可完整编辑。
4. 主窗口内普通 Dialog，使用当前 Localizations 和 Theme，新增只读环境快照 Provider，不新增持久化或跨 Isolate 通信。反馈逻辑不额外发送 ADB/HDC 查询，复用设备注册表的既有发现与缓存机制。两类草稿分别持有 TextEditingController，首次打开时填入模板；切换类型保留草稿，切换主题或语言不覆盖已有输入，关闭时释放 Controller。
5. macOS 使用 `open`，Windows 使用 `rundll32.exe url.dll,FileProtocolHandler`，Linux 使用 `xdg-open`。独立参数传递，不经 Shell 拼接；仅接受含 host 的 HTTP(S) URI。
6. 浏览器启动器等待上限 15 秒，超时先终止、2 秒后强制终止；stdout/stderr 消费后丢弃、最终取消订阅。弹窗关闭后的完成回调由 mounted 防护。
7. 打开期间禁用重复操作；失败时保留弹窗并复制最近失败的目标链接。进程返回成功仅表示已请求打开浏览器，不代表网络可达或 Issue 已提交。
8. 标题不能为空，UI 限制为 200 个字符，发送时添加 Bug/Feature 前缀。按完整编码 URL 的长度判断：超过 6000 时不截断正文，而是先复制完整正文，再打开仅携带标题的 Issue 页面，提示用户粘贴；剪贴板失败时停止跳转。短正文仍通过 URL 自动预填。
9. `.github/ISSUE_TEMPLATE/*.md` 需推送并合入默认分支后才成为线上可选模板；本次不推送、不创建测试 Issue。

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
flutter test --no-pub test/github_feedback_test.dart test/feedback_draft_controller_test.dart
flutter analyze --no-pub lib/features/feedback lib/core/process/host_platform_service.dart lib/app/l10n/app_localized_values.dart lib/app/l10n/tables/app_l10n_feedback.dart test/github_feedback_test.dart test/feedback_draft_controller_test.dart
git diff --check
```

- 2026-10-03：11 项测试通过，覆盖标题/正文特殊字符编码、环境字段预填与敏感标识排除、在线设备/通道匹配、未知信息回退、两类草稿保留、非 HTTP(S) 链接拒绝、中英文与明暗主题、标题必填、防重复打开、失败后复制，以及长正文完整复制和剪贴板失败时停止跳转。
- 上述反馈模块、宿主机服务、国际化与测试文件的定向分析通过（No issues found）；`git diff --check` 通过。
- 包含 Dashboard 的定向分析仅报告既有 `dashboard_screen.dart` 未使用 `liquid_glass_background.dart` import；本次保留无关代码。
- GitHub REST 只读查询确认目标仓库公开、`has_issues: true`、默认分支 `main`。
- 未启动 App，未进行真实浏览器登录/提交、Windows/Linux 桌面验证。

后续手动验收：

1. 无设备连接时进入设置，切换中英文、明暗主题，确认弹窗可滚动且操作可见。
2. 编辑标题和正文，修改或删除环境段落，来回切换反馈类型，确认各自草稿保留；跳转后确认中文、换行和标题保留。
   使用单在线设备、多在线设备未选择、当前选择 USB/网络、无设备/离线等场景检查环境信息；读取不到的字段应为未获取，不应出现序列号/IP/别名。
3. 查看已有反馈应打开列表，启动器失败时复制的应为对应目标链接；网络失败由浏览器呈现。
4. 连续点击只启动一次；等待期间关闭弹窗应无 disposed Widget 异常。
5. 三个平台分别验证默认浏览器打开；受限网络下验证复制链接和手动访问路径。

6. 粘贴较长中文正文，确认提示长正文处理；跳转时剪贴板为完整正文、链接只携带标题；剪贴板失败时保留草稿且不打开浏览器。

环境字段取打开弹窗时的快照；需要更新设备环境时关闭并重新打开。未新增 App 版本插件，也未调整设置页已有的版本展示逻辑。
