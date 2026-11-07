# 仪表盘一级模块标题与页面样式统一机制

## 1. 目标与背景

AnyDeck 的主窗口包含五个主要的一级功能模块/偏好页面：
- **设备管理 (`/devices`)**
- **模拟器管理 (`/emulators`)**
- **投屏接收 (`/receivers`)**
- **AI MCP (`/mcp`)**
- **设置 (`/settings`)**

在此次优化前，设备管理与模拟器管理在标题高度、边框分割和水平内边距（28px vs 20px）上存在不一致，而 AI MCP 和设置页面则没有统一的固定顶部标题栏，而是将自定义标题嵌入在可滚动的 Body 中（图标采用方形圆角、字体字号各异且随页面滚动被移出视野）。

本次优化通过抽象与收口统一的公共组件 `DashboardHeaderBar`，将四大功能模块的顶部标题栏规范、底部分割、原生窗口拖拽以及页面主体内边距彻底统一。

## 2. 核心架构与公共组件设计

### 2.1 公共组件 `DashboardHeaderBar`
文件路径：`lib/features/widgets/dashboard_header_bar.dart`

```dart
DashboardHeaderBar(
  title: context.l10n.t('...'),
  subtitle: context.l10n.t('...'),
  icon: CupertinoIcons....,
  trailing: const CustomTrailingWidget(), // 或 actions: [ ... ]
)
```

- **统一容器高度**：固定 72px 最小高度（`constraints: const BoxConstraints(minHeight: 72)`）。
- **统一内边距**：水平内边距规范为 `EdgeInsets.symmetric(horizontal: 28)`。
- **桌面背景与通透材质**：集成 `DesktopWorkspaceSurface`，并在底部渲染 `theme.colorScheme.outlineVariant` 细分割线，完美衔接左侧导航栏。
- **原生窗口拖拽**：外层包裹 `DragToMoveArea`，macOS / Windows / Linux 桌面端拖拽标题栏空白处可直接平移窗口。
- **标准标题与徽章**：内置 `DashboardHeaderTitle`，统一 48px 直径的主题色圆形图标徽章、20px 粗体主标题与 13px 柔和副标题。
- **灵活右侧区域**：支持 `trailing`（单个组件如平台切换 Tabs 或状态徽标）及 `actions`（动作按钮组），并在动作按钮间自动维护 8px 间隔。

### 2.2 四大模块适配方案

| 页面模块 | 标题文案与图标 | 右侧组件 (trailing / actions) | 页面内容区结构与内边距 |
| :--- | :--- | :--- | :--- |
| **设备管理** | `devices` / `Icons.devices_rounded` | TCP连接、无线配对、控制台、目录、重启、刷新等设备管理操作 | 下方铺满 `_DeviceListPanel` 设备表格 |
| **模拟器管理** | `emulators` / `CupertinoIcons.device_desktop` | `EmulatorPlatformTabs` 平台切换标签（Android / DevEco / iOS） | 搜索栏与工具栏内边距统一为 `fromLTRB(28, 12, 28, 12)`，与标题栏垂直对齐 |
| **投屏接收** | `receiverCenter` / `Icons.cast_connected_rounded` | 页面内 AirPlay 与 DLNA Card 分别管理服务，不在标题栏直接启停 | 内容区宽屏双列、窄屏单列，统一 28px 外边距 |
| **AI MCP** | `aiMcp` / `CupertinoIcons.sparkles` | `_McpServerStatusHeaderBadge` 实时服务运行与端口状态徽章 | 移除 Body 内嵌标题，`SingleChildScrollView(padding: (28, 20))`，卡片间距 16px |
| **设置** | `settings` / `CupertinoIcons.settings` | 保持清爽留空，支持灵活扩展 | 移除 Body 内嵌标题，`SingleChildScrollView(padding: (28, 24))`，居中最大宽度 860px |

## 3. 验收与回归标准

1. **静态代码分析**：执行 `dart analyze` 无报错，新增与重构代码完全符合 Dart 与 Flutter 规范。
2. **单元与渲染测试**：`test/dashboard_header_bar_test.dart` 自动化验证标题、副标题、图标、操作栏与状态徽章渲染；现有模拟器与 MCP 单元测试全部通过。
3. **视觉一致性**：四个顶级页面切换时，顶部标题栏高度、底边框对齐线、图标徽章圆角及文字垂直基线完全无抖动，桌面窗口拖拽平滑自然。

## 4. 设备管理工具栏按钮一致性（2026-11-07）

- **需求**：顶部“加入共享设备”入口与相邻操作统一大小、颜色和水波纹。此前该入口使用默认 `IconButton`，未设置其他操作已有的尺寸、前景色与圆角。
- **实现**：新增 `lib/features/widgets/dashboard_header_action_button.dart` 的 `DashboardHeaderActionButton`，由 `dashboard_header_bar.dart` 导出；共享设备、TCP 连接、无线配对与刷新共同复用。统一 30px 图标、48×48 点击区域与 10px 圆角 Material 交互反馈，颜色由调用方传入工具栏当前主题前景色。目录及服务菜单原有尺寸/圆角保持一致。
- **边界**：保留入口图标、Tooltip 本地化及所有回调；不改变设备共享协议、投屏、进程、Provider 或跨窗口通信，不增加后台工作。
- **自动验证**：`flutter test test/dashboard_header_bar_test.dart`（4 项）；Light/Dark 分别验证共享设备与连接按钮的实际尺寸、继承图标颜色/大小、InkResponse 圆角及非 NoSplash、点击回调。相关文件 `flutter analyze --no-pub` 通过。
- **人工回归**：在 Light/Dark/System 下对比共享设备、TCP、配对与刷新入口的默认、Hover、按下效果，并点击共享设备入口确认弹窗正常。未启动桌面 App，实际窗口视觉效果待人工验收。
