# 鸿蒙互联分阶段实施与验收

更新日期：2026-10-28。主仓仅 UI、通用 IPC 和制品锁；协议实现与测试保留私有仓。

| 阶段 | 状态 | 交付与验收 |
| --- | --- | --- |
| 1 UI | 实施中 | 按已确认原型拆分发现舞台、本机身份、设备卡片、连接引导、发送/来件面板；zh/en、明暗主题、无手机、失败态测试与视觉检查 |
| 2 大文件 | 待实施 | 审计长度/偏移/内存/超时/临时目录；版本化 IPC、真实进度与取消；10/100 MiB 及更大合成样本双向 hash 验证，按证据声明能力 |
| 3 多文件 | 待实施 | 队列、文件级与任务级进度、失败与取消隔离 |
| 4 完整体验 | 待实施 | 系统通知、完整持久化记录、打开路径/重试、设置与发布回归 |

## 当前证据与边界

- 开始时主仓 `fdf5ba03b3061b8d6efd829eb06bb770f9574aa6` 与私有仓工作树均干净。
- 原有真实双向测试只覆盖前一包小文件；最终自广播修复后的包未复验；不得当作本轮结果。
- 当前限制仍是单个普通非空文件 ≤1 MiB。UI 不伪造传输进度，不扩大核心能力声明。
- 本轮浏览器拒绝 `file:` 原型地址（URL policy）。已读取 HTML/CSS/JS，原型实际渲染对照仍待完成；不绕过策略。Flutter UI 可通过 Widget 渲染截图独立验证。

## 阶段 1 验收记录

- UI 结构已落地：发现舞台、本机身份、设备卡片、连接指引、最近路径区、共用收发确认面板；无设备/关闭/失败/忙碌态分别呈现。
- `flutter test --no-pub test/features/harmony_share_dashboard_tab_test.dart test/core/nearby_share/`：14 项通过。
- `flutter test --no-pub test/features/harmony_share_visual_test.dart`（带截图与本机字体 dart-define）：2 项通过；Light/Dark 的空态、附近设备和来件截图共 6 张，位于 `/tmp/anydeck-harmony-ui/`，已视觉检查。
- targeted `flutter analyze --no-pub`：无问题。
- 自动测试首次暴露测试宿主缺失 Material zh delegate 及布局宽度收缩问题，均已修复；截图使用 MaterialIcons 字体避免占位方框。
- 待验收：原 HTML 实际渲染对照、运行 App 拖放/主窗口来件与真实双向复验。此批不宣称阶段 1 全部验收完成。

UI 变更不触及投屏、HDC/ADB 或私有协议；接收服务继续由主窗口持有，页面销毁只解除 UI 监听。
