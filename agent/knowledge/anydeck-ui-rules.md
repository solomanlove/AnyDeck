# AnyDeck 桌面 UI 规则

适用于 AnyDeck 桌面端。全局主题沿用 [UI Theme 统一规范](../rules/60-ui-theme.md)，页面和组件的尺寸、配色及交互以各节注明的适用范围为准。文中的 `px` 均为 Flutter 逻辑像素。

## 水波纹与菜单

| 组件 | 形状与尺寸 | 实现与来源 |
| --- | --- | --- |
| 设备管理「全部分组」下拉菜单 | Hover 和按压水波纹铺满整行，由菜单 **12 px** 圆角外框裁切。首项**上圆下直**，中间项四角为直角，末项**上直下圆**。菜单外层内边距为 **0**，菜单项内仍保留 **水平 16 px、垂直 8 px**，分隔线两端各留 **6 px**。 | [DeviceGroupFilter](../../lib/features/devices/widgets/device_group_filter.dart)、[DeviceWorkspacePopupMenu](../../lib/features/devices/widgets/device_workspace_popup_menu.dart)，`11f54953` |
| 分组按钮和展开菜单 | 展开时以触发按钮的实际宽度为准，左右边缘齐平，窄窗换行和放大字号同样按实际布局计算。按钮和菜单项共用 **18 px** 图标、**10 px** 图文间距，菜单项最小高度 **40 px**。全部分组用打开的文件夹，平台分组用现有平台 Logo，自定义组用文件夹，选中勾放在右侧。 | [设备分组](adb-device-groups.md)，`712876d5`、`551c97a1` |
| 「连接设备」下拉菜单 | 与分组共用 **12 px** 外框、主题边框和轻阴影。菜单基础宽度 **240 px**，普通菜单项最小高度 **40 px**，默认外层留白 **6 px**。从按钮下方展开，右边缘对齐，窗口过窄时受安全边距约束。使用 Wi-Fi、链接、用户组图标，底部 USB 说明用分隔线与操作项隔开。 | [设备墙与诊断](adb-device-workspace-diagnostics.md)，`2cc2a4b2`、`01236c9f` |
| 设备列表操作列 | 共享、投屏、无线连接或断开、编辑使用 **4 px** 圆角矩形水波纹，图标四周保留 **8 px** 内边距。编辑图标与相邻投屏、连接图标共用主题主色。 | [设备身份与操作](adb-dashboard-device-identity.md)，`e80bcaca`、`1869edac`、`88670dc6` |
| 设置页下拉选择器 | 触发按钮的外框、Hover 和水波纹共用 **8 px** 圆角。用 `Material` / `Ink` 承载背景和点击反馈，分别给触发按钮与弹出的菜单设置形状。 | [设置分类与选择器](adb-settings-organization.md)，`e5bf3cd3` |
| Dashboard 公共标题栏图标操作 | `DashboardHeaderActionButton` 使用 **30 px** 图标、**48 × 48 px** 点击区域、**10 px** 圆角水波纹，前景色由所在工具栏决定。设备管理的「刷新」使用中性细描边圆角按钮，图标在左，文字在右。 | [标题栏统一](adb-dashboard-header-bar-unification.md)，`ba11d7c6`、`4484aeb4` |

## 背景与状态配色

| 区域或状态 | 规则 | 实现与来源 |
| --- | --- | --- |
| 主窗口左右分区 | 左侧导航用不透明中性色 `navigationSurface`，浅色 `#ECEEF2`，深色 `#282A31`。它与右侧工作区之间有独立的 **1 px** `VerticalDivider`，取工作区的 `outlineVariant`。 | [桌面工作区](adb-desktop-platform-chrome.md)，`22e3fc35` |
| 右侧全局状态栏 | 与一级标题栏共用 `DesktopWorkspaceSurface`。标签、本机 IP 和图标共用状态栏主题前景色。本机 IP 在左，「服务与诊断」在右，窄窗按可用空间换行。 | [状态栏实现](../../lib/features/devices/widgets/host_network_footer.dart)，`8f3f9a35`、`69fd1730` |
| 设备菜单 | 设备行右键操作、连接设备及分组菜单读取**设备工作区**的 `appColors.panelSurface`，浅色 `#FFFFFF`，深色 `#17181D`，关闭 Material 的 `surfaceTintColor` 着色。 | [设备工作区主题](../../lib/app/theme/device_workspace_theme.dart)、[设备右键菜单](adb-device-context-menu.md)，`01236c9f`、`84c8f9e1` |
| 设备筛选与批量管理 | 状态筛选、设备墙/列表切换、管理模式入口、批量选中的行和卡片、复选框及分组勾选使用中性灰。批量栏使用中性表面和正文色，删除使用 `error`。 | [批量管理工具栏](adb-device-batch-toolbar.md)，`34346cb6`、`808c8085` |
| 平台切换器 | 系统版本和模拟器管理复用 `PlatformVersionSwitcher`。选中项取当前主题的 `panelSurface`，浅色是白底，深色用对应面板底色。选中文字取 `ColorScheme.onSurface`。 | [模拟器管理](adb-emulator-management.md)，`e3433550` |
| 主题主色与业务状态色 | 主色设置默认绿色，另有蓝、紫、橙、粉、青。通用主操作、开关、侧栏选中态及投屏接收、AI MCP、模拟器管理的运行圆点随主色变化。MCP 的平台接入、安全及 Tools 开关共用样式。在线、成功、警告、危险、平台品牌及图表沿用各自业务语义色。概览电量和 Root 使用中性灰，满电状态省去「已充满」文字。 | [主题色设置](adb-theme-color-settings.md)、[主题实现](adb-ui-theme-system.md)，`36fbf1fd`、`1999d0b6`、`e71f4bc8`、`11682cbe`、`4a33146c` |
| 设备墙手机预览 | 截图居中等比铺满手机展示框，超出部分裁剪。等待截图、无截图、离线或解码失败时显示既有品牌 Logo，Samsung 等机型的品牌封面在明暗模式下均用白底 `#FFFFFF`，文字和手势条用深灰 `#616161`。 | [设备墙与诊断](adb-device-workspace-diagnostics.md)，`781c1303` |

## 尺寸、对齐与滚动

| 区域 | 规则 | 实现与来源 |
| --- | --- | --- |
| Dashboard 一级标题栏 | 设备管理、模拟器管理、AI MCP、设置复用 `DashboardHeaderBar`。标准最小高度 **72 px**、水平留白 **28 px**、主标题 **20 px**、副标题 **13 px**、两行间距 **3 px**、操作间距 **8 px**。设备管理在 **490 px** 及以下的窄窗使用 **10 px** 水平留白及 **32 px** 顶部避让，大字号允许增高。 | [标题栏统一](adb-dashboard-header-bar-unification.md)，`eb8c55a1` |
| 主侧栏图标 | 展开和收起使用同样的图标尺寸。设备品牌图标 **36 × 36 px**，收起时设备入口点击区 **50 × 50 px**。导航、「更多功能」入口与底部工具图标 **24 × 24 px**，工具按钮高度 **44 px**，底部工具图标中心间距 **52 px**。「更多功能」菜单内图标 **20 × 20 px**。 | [设备身份与导航](adb-dashboard-device-identity.md)、[公共尺寸](../../lib/app/theme/app_theme_sizes.dart)，`b06149d0`、`320a0aac` |
| 设备与模拟器搜索框 | Android、HarmonyOS 和 iOS 模拟器搜索框与设备管理等高。标准字号下 **40 px**，内容内边距为 **水平 12 px、垂直 10 px**，搜索及清除图标按 **40 × 40 px** 最小区域布局。输入或清除时保持等高，放大字号可自然增高。设备管理搜索框随一行剩余宽度伸缩，窄窗按工具栏布局换行。 | [模拟器搜索](adb-emulator-management.md)、[公共尺寸](../../lib/app/theme/app_theme_sizes.dart)，`c88357e6`、`cfe39446` |
| 设备、应用和进程正文 | 表头、列表行、分隔线及适用的网格和设备墙贴齐右侧内容区，滚动视口底部接状态栏。应用、进程工具栏两侧保留 **16 px**，设备筛选工具栏随窗口采用 **8、12 或 16 px**。单元格仍保留内边距，窄窗下有宽列的进程表可以横向滚动。 | [应用与进程](adb-tabs-features-principles.md)、[设备批量栏](adb-device-batch-toolbar.md)，`6b73666a`、`a84feae4`、`142d6813`、`7360fcbb` |
| Android 模拟器表格 | 与 iOS 列表一样，表头紧接工具栏，背景和分隔线铺满内容区，表头和数据行内部左右各留 **28 px**。六列随可用宽度缩放，名称标题为状态圆点留出空间，其余标题与数据左对齐。表头和数据行内容各自在高度内垂直居中。 | [模拟器表格](adb-emulator-management.md) |
| Android、HarmonyOS、iOS 系统版本页 | 标准字号下正文可用宽度达到 **720 px** 时左右分栏，列表最多占 **40%**。更窄时列表在上、详情在下。正文和链接按栏宽自然换行，仅正文纵向滚动，标题、平台切换器及更新时间固定。详情里的文档链接去下划线，仍可打开，复制入口保留。 | [主窗口导航](adb-main-window-navigation.md)，`fef6c722`、`0dd86c92`、`921af5bb` |
| Android 控制页 | 快捷操作按「设备交互」「系统开关」「投屏与采集」分组并共用左边线。高级设置卡片可用宽度达到 **700 px** 时共用标签列，更窄时标签移到控件上方。自定义输入和各自的提交按钮一起换行，DPI 的减号、数值框和加号保持一组。电源区域按可用宽度排列一至三列。 | [控制 Tab](adb-tabs-features-principles.md)，`64f9c528` |

## 入口、文案和反馈

- **设备管理**。列表和设备墙支持一键切换，默认隐藏复选框，进入批量管理才显示。列表的批量栏原位替换表头、满宽居左，窄窗保留单行并允许横向滚动。「退出管理」恢复表头并清空选择。设备名称及手机预览进入设备工作区，独立投屏图标直接投屏。离线但已确认身份的本机 Android AVD 可从设备管理点「启动」，留在当前页并显示启动中或失败反馈。设备标签在列表中靠近名称，在设备墙中位于名称下方。系统版本完整展示，USB、TCP/IP、Wi-Fi 使用短文案并在连接列横向同排。已确认属于同一 AVD 的记录合并，编辑弹窗底部展示端口连接历史、起止时间和时长。 [设备墙与诊断](adb-device-workspace-diagnostics.md)、[模拟器管理](adb-emulator-management.md)，`6b46e11a`、`da0fb770`、`5ec63303`、`95c6e8bf`、`fd586a7e`、`0aeb6daa`。
- **侧栏导航**。设备工作区顶部、设备名称上方显示「返回设备管理」。收起侧栏后显示返回箭头，悬停提供同名 Tooltip。服务运行圆点独立于页面选中态，任一平台模拟器运行时展示同款圆点，悬停按平台显示动态数量，多平台分行。全部退出后收起圆点和提示。 [主窗口导航](adb-main-window-navigation.md)、[模拟器管理](adb-emulator-management.md)，`7b40ab3b`、`5e78f488`。
- **前台窗口弹窗**。控制页与 Android 投屏使用相同样式，正文居中展示可选择、复制的 `包名/完整 Activity 类名`，长类名换行后仍居中。「关闭」置于正文下方居中。 [控制 Tab](adb-tabs-features-principles.md)，`f50c46c6`、`79767af8`。
- **服务与诊断和核心依赖**。点击服务名称或状态后单独检测并展开该项，右侧箭头只控制展开和收起。「检查全部」统一检测，单项复测保留其他结果。核心依赖缺失时用黄色「未检测到工具」标识，目录与目录终端按钮置灰，路径检测通过后恢复。鸿蒙连接引导给 Command Line Tools 和 DevEco Studio 各提供独立下载入口。 [设备墙与诊断](adb-device-workspace-diagnostics.md)、[核心依赖设置](adb-core-tool-path-settings.md)，`3789d317`、`e7358494`、`a25f3dc4`、`cda7cbad`。
- **控制台**。HDC 或 go-ios 未安装或不可执行时，后台设备发现跳过相应查询，控制台不会反复显示这些查询命令和启动失败日志。工具可用时继续展示实际查询错误。 [本地诊断日志](adb-local-diagnostic-logs.md)，`b0f744d1`。
- **共享 Wi-Fi 授权**。自动准备共享缺少可确认的 Wi-Fi SSID 时，入口文案用「授权读取 Wi-Fi SSID」，明确这是授权动作。 [局域网设备共享](adb-lan-device-sharing.md)，`b78da683`。
- **投屏折叠屏按钮**。支持的设备默认自动切换，点击切换内外屏，长按恢复自动。图标、自动角标和 Tooltip 反映已确认的状态，切换中禁用重复操作。不支持的设备隐藏入口。 [折叠屏切换](adb-foldable-screen-switching.md)，`71547b6`、`3236773`。

## 回归检查

- 菜单检查浅色和深色下的 Hover 与按压像素、首中末项裁切、展开边缘和按钮对齐，以及放大字号、窄窗下的图文布局。 [分组菜单测试](../../test/device_group_filter_test.dart)、[连接菜单测试](../../test/device_connection_menu_test.dart)、[设备操作测试](../../test/device_list_action_buttons_test.dart)。
- 主题检查切换主色后的通用交互和中性区域、右侧底栏及侧栏分区。核对实际绘制的背景、文字、图标及选中态。 [Dashboard 响应式测试](../../test/dashboard_device_responsive_test.dart)、[主窗口导航测试](../../test/dashboard_shell_navigation_test.dart)、[批量栏测试](../../test/device_batch_toolbar_test.dart)。
- 布局检查中英文、长文本、宽窄窗口和放大字号下的高度、溢出、换行或指定区域滚动。验证入口可读且仍可点按。 [模拟器搜索测试](../../test/emulator_search_fields_test.dart)、[系统版本布局测试](../../test/platform_version_distribution_layout_test.dart)、[Android 控制页布局测试](../../test/android_control_layout_test.dart)。

## 尚待确认的尺寸

「调整设备管理工具栏布局」会话有一条缩小截图中开关、保持颜色的要求。该轮附件未能读取，目标控件和具体尺寸待确认。MCP 开关统一样式见上文主题配色规则。
