# 设备墙、列表与全局服务诊断

## 业务目标与交互

- 设备管理采用手机样式设备墙，132px 手机宽度、9:18.5 比例；列表保留一键切换。
- 工具栏依次为全部/在线/离线、自适应搜索、视图切换、批量管理。默认不显示多选。
- 搜索和状态筛选与视图独立；进入批量管理才显示勾选，切视图/筛选保留选择，退出清空。
- 全选只作用于当前可见且可选的设备；工具栏说明筛选隐藏的已选数量。
- 点击设备名称进入设备工作台；更多和右键复用同一设备能力策略，保留截图、调试、投屏、编辑、共享及无线连接。
- 本机 IP、复制和网络详情在整个工作区底部常驻；右侧提供“服务与诊断”。控制台展开不覆盖状态栏。
- 开发者页的原三平台工具诊断改为复用全局诊断入口；开发者测试、日志、缓存等其他内容保留。
- 设备管理 Shell 的中性亮暗底色统一在 `app/theme/device_workspace_theme.dart`，保留用户主色和字体；其他工具页恢复原主题。
- 搜索框默认 36px / 8px 圆角，使用剩余宽度；320px 大字号连接按钮收为带 Tooltip 的图标，避免挤压标题。

## 架构与状态

| 范围 | 实现位置 | 职责 |
| --- | --- | --- |
| 页面状态 | `features/devices/dashboard_devices_panel.dart` | 搜索、状态筛选、视图及批量模式 |
| 工具栏 | `features/devices/widgets/device_list_filters.dart` | 宽度自适应、筛选和切换回调 |
| 手机展示 | `device_wall_card.dart` / `device_wall_phone.dart` | 纯展示，真实截图或品牌封面，不创建模拟屏幕 |
| 表格/设备墙 | `dashboard_devices_rows.dart` / `dashboard_devices_wall.dart` | 共用身份、IP、主操作、菜单及注册表勾选 |
| 静态封面 | `controller/device_screen_preview_controller.dart` | 用户主动采集，按 Android/HarmonyOS/iOS 路由 |
| 全局底栏 | `widgets/host_network_footer.dart` / `overview/dashboard_shell.dart` | 复用主机网络 Provider，位于 ConsoleDock 外侧 |
| 诊断快照 | `features/diagnostics/controller/service_diagnostics_controller.dart` | 单轮检查、防重复、失败隔离及检查时间 |
| 诊断探针 | `service_diagnostic_checks.dart` / `service_session_checks.dart` | 复用服务和原生状态，不成为采集或重连拥有者 |
| 诊断模型 | `core/diagnostics/service_diagnostic.dart` | 稳定服务标识、状态、原因、影响、建议及技术详情 |
| 短进程 | `core/process/bounded_process.dart` | 参数列表、安全执行、输出上限与超时回收 |

所有路径相对 `lib/`。无新增 package、无新窗口、无跨 Isolate 设置广播。

设备卡片仅读取缓存概览，不为整墙重复拉取完整硬件信息。墙和列表均使用 builder 按需创建。
封面仅从“获取屏幕预览”主动请求，不启动实时投屏或自动截图。采集期间临时 keepAlive；
完成后保留一分钟以支持快速切视图，无订阅且过期后释放截图；销毁取消定时器。
原有批量动作按进度、录屏、计划模型和计划对话框拆分，保留命令实现，文件不超过 500 行。

## 服务检查与真实边界

| 服务 | 检查证据 |
| --- | --- |
| ADB / HDC / go-ios | 实际可执行路径与版本命令；组件就绪不宣称已有设备会话 |
| 投屏引擎 | macOS Rust 符号、内置 server 资源；其他桌面平台 scrcpy 版本 |
| AirPlay / DLNA | 当前接收服务快照、错误与已启用服务监听端口 |
| 文件互传 | 编译开关、Share Core hello 能力握手及当前发现/收发状态 |
| AI MCP | 服务快照、错误和正在使用的监听端口 |
| 虚拟摄像头 | 原生 status：支持、安装、批准、重启、就绪、推流与错误 |
| 局域网设备共享 | 已存在服务初始化及共享/加入会话 |
| 系统通知与消息转发 | 现有转发会话错误与系统通知只读授权状态 |
| 摄像头/麦克风/音频/剪贴板辅助会话 | 当前窗口已经创建的 Provider；不创建新采集或轮询 |

状态区分未检查、检查中、运行中、已就绪、未启用、缺失、运行异常、待授权、
平台不支持和未知。仅缺失、异常、待授权计入需处理；问题优先，单项展开显示原因、影响、建议。
检查结果是带时间的快照，不代表其他窗口全部会话或设备端权限已经通过实测。
原生 Plugin 缺失、单项超时和 CLI 失败均保留独立结果，其他检查继续完成。
诊断不自动启停、安装、修复或请求权限；工具安装引导复用现有配置页面。

CLI 版本探测使用参数列表而非 Shell 字符串。输出每个管道最多 64KiB；默认四秒超时，
超时先 terminate，500ms 后仍未退出则 kill。每个服务检查整体上限十五秒。
技术错误通过日志脱敏再展示，不复制服务 Token 或其他凭据。

## 验证与回归

自动回归覆盖：

- `device_list_filters_test.dart`：中英、明暗、宽窄和字体缩放、自适应搜索。
- `dashboard_device_workspace_test.dart`：真实 Dashboard 的视图、筛选、批量、底栏和控制台。
- `dashboard_device_responsive_test.dart`：730/650/490 断点、窄屏双列、表格降级、批量禁右键与清筛选。
- `dashboard_device_reconnect_test.dart`：设备墙/列表的离线 HDC 与 iOS 入口，禁止误用 ADB 连接。
- `device_wall_card_test.dart`：手机比例、真实图像、离线封面、点击/选择隔离。
- `device_screen_preview_controller_test.dart`：三平台路由、无自动采集、防重复、异常重试和销毁隔离。
- `device_context_action_test.dart` / `device_list_context_menu_test.dart`：能力限制、菜单打开后断线/删除、真实操作路由。
- `device_subnet_warning_test.dart`：地址复制、网络详情、显式权限/刷新、不自动轮询及大字号。
- `service_diagnostics_test.dart` / `service_diagnostic_probes_test.dart`：防重复、超时回收、状态分类、真实适配器、可选构建和中英明暗布局。
- 同时回归现有模拟器搜索、Shell 导航、控制台、开发者页面和设备主题测试。

验证命令使用 `flutter test --no-pub`，避免依赖解析混入无关 lockfile 改动；静态分析同样使用 `--no-pub`。
仓库当前 Flutter SDK 对现有 Material/Cupertino 导入产生 deprecation info；全库既有五项 warning 位于
`emulator_service.dart`、`file_preview_controller.dart`、`dashboard_overview_components.dart` 和
`dashboard_common.dart`，本次不改动这些不相关逻辑。变更文件要求无编译错误或新增 warning。

2026-11-17 最终相关回归：18 份测试文件、143 项全部通过；全库 analyze 无 error，保留上述既有 warning。
另外扩展执行 `device_theme_color_test.dart` 时，139 项通过、2 项失败：该文件仍要求电量与 Root
使用绿色，而 HEAD 的 `11682cbe` 与主题知识库第 9 节已明确改为中性灰。
本次未改动这些生产或旧测试文件；现有 `overview_status_chips_test.dart` 的 8 项灰色规范回归通过。
实际 Widget 的手机墙、列表和右下角诊断面板已经截图核对；没有通过截图伪造真实设备服务状态。

人工/硬件边界：未为本任务运行完整 App，未自动开启用户电脑服务或连接真实手机。
最终设备端触控、USB 权限、AirPlay/DLNA 实际播放和跨窗口活动会话须在对应设备条件下验证，
诊断面板不会以组件就绪替代这些功能验收。
