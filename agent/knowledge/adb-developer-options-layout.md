# AnyDeck 开发者页面头部布局

## 页面与导航

- `DeveloperOptionsScreen` 的窗口栏仅保留“设置”返回按钮，移除重复的开发者选项标题与分隔符；正文继续展示页面标题和诊断功能。
- `DeveloperWindowBar` 复用 `DesktopWorkspaceSurface` 和 `DesktopChromePolicy`，保留 macOS 原生按钮避让，返回按钮使用主题背景、边框与文字。窗口拖拽和双击手势仅作用于空白区域，避免延迟返回按钮的单击响应。
- `DeveloperPageHeader` 将开发者模式控制区放在正文介绍右侧。内容宽度不足 680px 时移到介绍下方；标题和徽章可换行。页面主体与原有诊断卡片保持同列对齐。

## 状态与边界

- `DeveloperModeControl` 仅订阅 `developerModeEnabled`，继续调用 `setDeveloperModeEnabled` 保存和广播。关闭后当前开发者页面保留，返回设置后入口按原逻辑隐藏，连续点击版本号激活的规则不变。
- 改动区域使用 Theme 的语义配色，并为页面介绍、徽章与关闭提示补齐中英文资源。没有新增 Preference key、设备命令或后台任务。
- 环境信息、连接诊断、日志与测试工具沿用现有实现；未扩展到其他卡片的样式或文案重构。

## 验证

- `test/developer_page_header_test.dart` 覆盖中英文、Light/Dark、360/900 宽度、标题栏内容、开关位置、开关持久化与返回设置行为。
- 关联回归使用 `test/developer_mode_test.dart` 验证默认关闭与连续点击版本号激活。
- 本轮 11 项相关测试通过，6 个目标的定向 `flutter analyze --no-pub` 无问题。
- 按仓库约定不启动桌面 App；Widget 测试与定向静态检查不替代真实窗口视觉验收。
