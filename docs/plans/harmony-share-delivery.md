# 鸿蒙互联分阶段实施与验收

更新日期：2026-10-28。主仓仅 UI、通用 IPC 和制品锁；协议实现与测试保留私有仓。

| 阶段 | 状态 | 交付与验收 |
| --- | --- | --- |
| 1 UI | 实施中 | 按已确认原型拆分发现舞台、本机身份、设备卡片、连接引导、发送/来件面板；zh/en、明暗主题、无手机、失败态测试与视觉检查 |
| 2 大文件 | 离线链路已实现，真机待验收 | 审计长度/偏移/内存/超时/临时目录；版本化 IPC、真实进度与取消；10/100 MiB 及更大合成样本双向 hash 验证，按证据声明能力 |
| 3 多文件 | 发送队列已实现，原生批量收发与真机待完成 | 队列、文件级与任务级进度、失败与取消隔离 |
| 4 完整体验 | 待实施 | 系统通知、完整持久化记录、打开路径/重试、设置与发布回归 |

## 当前证据与边界

- 开始时主仓 `fdf5ba03b3061b8d6efd829eb06bb770f9574aa6` 与私有仓工作树均干净。
- 原有真实双向测试只覆盖前一包小文件；最终自广播修复后的包未复验；不得当作本轮结果。
- 起始基线是单个普通非空文件 ≤1 MiB；阶段 2 已扩展至实验单文件 1 GiB。阶段 3 当前支持 1–100 文件发送队列，仍逐项建立核心会话；手机原生批量接收未发布。
- 本轮浏览器拒绝 `file:` 原型地址（URL policy）。已读取 HTML/CSS/JS，原型实际渲染对照仍待完成；不绕过策略。Flutter UI 可通过 Widget 渲染截图独立验证。

## 阶段 1 验收记录

- UI 结构已落地：发现舞台、本机身份、设备卡片、连接指引、最近路径区、共用收发确认面板；无设备/关闭/失败/忙碌态分别呈现。
- `flutter test --no-pub test/features/harmony_share_dashboard_tab_test.dart test/core/nearby_share/`：14 项通过。
- `flutter test --no-pub test/features/harmony_share_visual_test.dart`（带截图与本机字体 dart-define）：2 项通过；Light/Dark 的空态、附近设备和来件截图共 6 张，位于 `/tmp/anydeck-harmony-ui/`，已视觉检查。
- targeted `flutter analyze --no-pub`：无问题。
- 自动测试首次暴露测试宿主缺失 Material zh delegate 及布局宽度收缩问题，均已修复；截图使用 MaterialIcons 字体避免占位方框。
- 待验收：原 HTML 实际渲染对照、运行 App 拖放/主窗口来件与真实双向复验。此批不宣称阶段 1 全部验收完成。

UI 变更不触及投屏、HDC/ADB 或私有协议；接收服务继续由主窗口持有，页面销毁只解除 UI 监听。

## 阶段 2 离线交付记录

- 私有 Core `0.2.0` / IPC `2`：commit `21d8bee605793b6183e4f91233c95028df4942d9`；主仓仅更新通用 IPC、UI 与二进制锁。生产 `send/receive=false` 保持不变。
- 实验最大单文件 1 GiB、最长 30 分钟，实际字节进度与取消已接入。发现窗口与传输期限分离，接收期间不再被 125 秒发现 watchdog 回收；准备期间点击取消也会阻止稍后开始发送。
- 离线加密 DFile 双进程：10 / 100 / 512 MiB / 1 GiB 全部完成，双向进度单调且有最终字节值，SHA-256 一致；最终复验 1 GiB 约 10.20 秒，单进程采样峰值 RSS 183,664 KiB。此速度是 loopback 测试数据，不代表手机 Wi-Fi 速度。
- 私有 Rust 18 unit + 4 integration、Swift 11、Python 43 通过；DFile 基础 5 通过 / 1 可选 LAN 未运行；大文件压力测试 4 个样本均通过。
- 主仓 focused Flutter tests 24 项通过，涵盖 IPC、取消、非法进度、最终事件与百分比区分、大文件接收跨 125 秒和早期取消；安装器 Python tests 3 项通过，包含旧 IPC 拦截。targeted analyze 无问题。
- 用户明确暂不方便真机操作，先完成离线验证。**未完成**新包手机双向大文件、拒绝/手机取消/断网/磁盘满及最终 hash 验收，不宣称完整生态链路或生产兼容性通过。
- 私有制品 SHA-256：`106026e891b971c8c004c37a9b67213fe2a43cc087a688ba7ec37970b623a119`。本轮构建通过 `ANYDECK_SHARE_CORE_ARCHIVE` 使用本地已锁定 zip；私有新 commit 未推送，默认远端拉取需待私有 commit 发布。
- 新包位置：`/tmp/anydeck-harmony-large-offline/Products/AnyDeck.app`。Release 构建成功；`codesign --verify --deep --strict`、包内全部成员 SHA-256、IPC 2 / Core 0.2.0 握手通过。没有启动或停止原有 AnyDeck 实例。

## 后续批次

1. 完成阶段 1 原型实际渲染对照与运行包拖放视觉验收；保留未验收标记。
2. 阶段 3 先做发送多选/队列与任务进度；多文件接收需私有核心支持，不用单文件循环冒充原生批量 offer。
3. 阶段 4 完成持久化记录与通知、路径操作/重试/设置；再补齐真机与发布前回归。

本轮曾因磁盘空间不足中断一轮验证；只清理本轮已停止合成样本的临时目录后，串行重跑压力测试和 Flutter 验证通过。启动/停止竞态新增独立回归用例，避免异步启动迟到后残留接收进程。

最终 Widget 截图已按 IPC 2 / 1 GiB 文案重新导出，视觉布局测试 2 项通过；截图路径仍为 `/tmp/anydeck-harmony-ui/`。

## 阶段 3 第一批：多文件发送队列（2026-10-28）

- 点击设备支持多选，Finder 可一次拖入多个文件到对应头像或唯一设备中央区域；同一选择统一确认后发送，确认页展示数量、总大小与文件摘要。一次最多 100 个文件、单个最大 1 GiB；目录、链接、空文件、超界选择拒绝，重复路径去重。
- `ShareSendSelection` 只读取元数据；队列开始每项前复核文件类型、大小与修改时间。`HarmonyShareSendQueue` 负责串行状态机，UI、拖放样式与队列数据分文件。
- 每项保留 queued / preparing / transferring / succeeded / failed / cancelled，支持取消排队项、取消当前项和取消所有剩余项。单项失败继续下一项；100% 字节仍等待核心最终结果，迟到取消不覆盖核心成功。
- 面板展示总处理数量、成功/失败/取消数量、实际累计字节与各文件进度/失败原因；列表有界滚动，100 项不一次撑开。整个 batch 期间暂停接收，完成后恢复一次；页面退出只移除 UI 监听。
- 自动验证：40 项 focused Flutter tests 通过，targeted analyze 无问题；覆盖严格串行、失败隔离、取消/重复取消、迟到回调、错误进度、队列重用、文件变化与选择边界、整批接收互斥、多文件拖入、目标歧义、zh/en、Light/Dark 和窄窗口。
- 视觉检查：`/tmp/anydeck-harmony-queue-ui/queue-light.png`、`queue-dark.png` 已检查；这是 Widget 离线渲染，不是真机传输截图。新增拖放高亮复用 feature 内薄组件；现有 ADB 上传覆盖层与其 Provider 耦合，不接入鸿蒙互联。
- **范围边界**：当前是多文件发送队列，每个文件仍需要手机确认。私有 IPC 与协议本批未修改，仍拒绝原生多文件来件；不得描述为“原生批量收发已完成”。持续队列添加、速度/剩余时间和完整持久化记录仍需继续。
- 手机操作按用户要求暂缓。新 Release 包 `/tmp/anydeck-harmony-queue-offline/Products/AnyDeck.app` 构建成功；`codesign --verify --deep --strict`、包内成员 SHA-256 与 IPC 2 握手通过。原有 AnyDeck 不启动、不终止。
