# 设备墙、列表与全局服务诊断

## 业务目标与交互

- 设备管理采用手机样式设备墙，120px 手机宽度、9:18.5 比例；列表保留一键切换。
- 工具栏依次为全部/在线/离线、自适应搜索、视图切换、批量管理。默认不显示多选。
- 搜索和状态筛选与视图独立；进入批量管理才显示勾选，切视图/筛选保留选择，退出清空。
- 全选只作用于当前可见且可选的设备；工具栏说明筛选隐藏的已选数量。
- 设备墙中，点击在线设备的“进入工作区”、手机预览或名称，均进入该设备的概览。仅有 AirPlay 会话的卡片没有设备工作区，主操作仍打开该会话。离线卡片提供重连或启动模拟器。
- 更多和右键复用同一设备能力策略，提供截图、调试、投屏、编辑、共享及无线连接。
- 本机 IP、复制和网络详情在整个工作区底部常驻；右侧提供“服务与诊断”。控制台展开不覆盖状态栏。
- 开发者页的原三平台工具诊断改为复用全局诊断入口；开发者测试、日志、缓存等其他内容保留。
- 设备管理右侧工作区的中性亮暗底色统一在 `app/theme/device_workspace_theme.dart`，保留用户主色和字体；左侧栏与其他工具页使用原应用主题。
- 搜索框默认 36px / 8px 圆角，使用剩余宽度；320px 大字号连接按钮收为带 Tooltip 的图标，避免挤压标题。

## 架构与状态

| 范围 | 实现位置 | 职责 |
| --- | --- | --- |
| 页面状态 | `features/devices/dashboard_devices_panel.dart` | 搜索、状态筛选、视图及批量模式 |
| 工具栏 | `features/devices/widgets/device_list_filters.dart` | 宽度自适应、筛选和切换回调 |
| 手机展示 | `device_wall_card.dart` / `device_wall_phone.dart` | 纯展示，真实截图或品牌封面，不创建模拟屏幕 |
| 表格/设备墙 | `dashboard_devices_rows.dart` / `dashboard_devices_wall.dart` | 共用身份、IP、工作区路由、菜单及注册表勾选 |
| 静态封面 | `controller/device_screen_preview_controller.dart` | 可见墙自动采集与手动刷新，按 Android/HarmonyOS/iOS 路由 |
| 自动预览 | `widgets/device_screen_preview.dart` / `controller/device_screen_preview_queue.dart` | 可见卡片生命周期、最多两路截图并发及隐藏任务撤回 |
| 全局底栏 | `widgets/host_network_footer.dart` / `overview/dashboard_shell.dart` | 复用主机网络 Provider，位于 ConsoleDock 外侧 |
| 诊断快照 | `features/diagnostics/controller/service_diagnostics_controller.dart` | 单轮检查、防重复、失败隔离及检查时间 |
| 诊断探针 | `service_diagnostic_checks.dart` / `service_session_checks.dart` | 复用服务和原生状态，不成为采集或重连拥有者 |
| 诊断模型 | `core/diagnostics/service_diagnostic.dart` | 稳定服务标识、状态、原因、影响、建议及技术详情 |
| 短进程 | `core/process/bounded_process.dart` | 参数列表、安全执行、输出上限与超时回收 |

所有路径相对 `lib/`。无新增 package、无新窗口、无跨 Isolate 设置广播。

设备卡片仅读取缓存概览，不为整墙重复拉取完整硬件信息。墙和列表均使用 builder 按需创建。
在线手机进入可见设备墙、重新上线、返回设备墙或主动刷新时自动获取当前真实屏幕截图。
截图为单次快照，不启动实时投屏或周期轮询；列表及隐藏 Route 不新增截图请求。
全窗口最多两个截图任务，排队任务随卡片离开而撤回，已开始任务直到平台命令实际结束才释放槽。
采集结束一分钟后释放 keepAlive；无订阅时自动清理，隐藏页面仍被订阅时不强制清缓存。
返回墙会更新，采集中重复刷新最多补一轮，不无限堆积。
自动 iOS 预览复用既有截图底座但禁用开发者镜像自动下载/挂载；手动截图保持原恢复逻辑。
HDC 截图收发按请求使用独立临时目录与远端文件名，finally 清理，避免并发串图和删除竞争。
截图失败在卡片内提示重试，不弹出逐台错误通知。取图期间仍可进入设备工作区。
原有批量动作按进度、录屏、计划模型和计划对话框拆分，保留命令实现，文件不超过 500 行。

## 紧凑布局与品牌资源

- 页头复用一级页面公共标题栏：默认字号最小高度 72px、左右留白 28px；内容仍保留紧凑布局，左右留白 16px（中窄窗口 12px，手机窗口 8px），顶部留白 10–12px。
- 列表行最小 60px、上下内边距 7px；连接方式横向单行显示所有在线 USB / TCP/IP / Wi-Fi 通道，按可见设备的实际通道组合统一列宽（最小 80px），Tooltip 和读屏保留完整状态。系统版本独立列为 160px，长版本与窄屏行内版本均完整换行，不省略 API 信息。
- 列表恢复原 `DeviceStatusAvatar`；`cacheOnly: true` 仅读取缓存品牌，避免为整个设备列表触发完整硬件探测，其他调用方默认行为不变。
- 手机墙复用 `BrandLogoHelper` 与原品牌资源；截图成功后名称旁仍保留品牌 Logo，未取到画面时用原 Logo 封面。
- 手机外框宽 120px，单卡基础宽 148px，卡片内间距收紧；操作点击区保留 40px，窄窗口与放大字体仍按内容适配。

### 截图居中铺满与品牌封面白底（2026-11-17）

- `DeviceWallPhone` 的真实截图统一使用 `BoxFit.cover` 与 `Alignment.center`，等比缩放后居中裁剪超出的部分，消除截图比例与手机屏幕不一致时的留白；保留圆角裁剪、`cacheWidth` 和 `gaplessPlayback`。
- Samsung、小米、Huawei/HONOR、Apple 及默认品牌封面共用 `AppPalette.deviceBrandCoverBackground` 白底，与 Logo 自带白底一致；等待截图、无截图、离线和解码失败均复用同一封面。
- 封面文字与手势条使用 `AppPalette.deviceBrandCoverForeground` 深灰色，保证 Light/Dark 下的白底文字可读；手机外框和卡片其他区域继续使用 Theme。
- 修改仅涉及公共展示组件与品牌配色，不新增文案、Provider、设备命令或窗口通信；离线时仍不展示历史截图。
- 回归入口为 `test/device_wall_phone_test.dart`，配合既有卡片、响应式、工作区和连接文案测试；人工检查不同比例截图居中裁剪，以及切换主题后 Samsung 等白底 Logo 与封面是否融合。按项目约定不启动完整 App。
- 验证结果：5 份相关测试共 63 项全部通过，包含新增 7 项实际绘制回归；定向 analyze 无 error / warning，仅保留当前 SDK 的 3 项 Material 导入弃用 info。Dart 格式检查与 `git diff --check` 通过。

### 设备墙状态文案精简

- 顶部连接方式复用 `DeviceConnectionKind.shortLabelKey`，与列表一致显示 `USB`、`TCP/IP`、`Wi-Fi`、`AirPlay`，多个通道以 ` · ` 连接。离线及未知状态继续使用原状态文案。
- `DeviceWallCard.statusDescription` 保存 `fullLabelKey` 生成的完整说明，仅用于 Tooltip 和读屏；可见状态不再附带“已连接”“连接”等重复描述。
- 离线手机封面不再显示“通过 USB 或无线连接”，`DeviceWallPhone` 不构建底部提示的 `Positioned` 区域；保留品牌、设备未连接状态、底部手势条及重连操作。在线截图等待或失败时的封面提示继续保留。
- 仅调整展示层，无新增设备探测、CLI、依赖、Provider 或窗口同步。中英文、主题色、截图与设备操作继续复用现有实现。
- `device_connection_status_labels_test.dart` 通过真实 Dashboard 验证 Android 三通道、Harmony USB/TCP、iOS USB/网络和离线状态的可见短名、Tooltip 与读屏；`device_wall_card_test.dart` 验证离线提示区整体移除及手机外观保留。
- 本次 7 份相关测试共 88 项通过；全仓静态分析无 error，保留 5 项既有 warning。未启动 App 或验证真机。

### 全局底栏背景与标题栏统一（2026-11-19）

- `HostNetworkFooter` 复用一级标题栏的 `DesktopWorkspaceSurface`，移除原 `ColorScheme.surface` 实色底，避免底栏被种子主色染色。macOS 共用透明度和模糊材质，Windows/Linux 共用主题实色表面。
- 底栏仍由主窗口 Shell 唯一挂载，设备管理、模拟器管理、设置及其他右侧页面均自动使用同一规则；原有顶部边框、高度、内边距、IP 复制、网络详情与服务诊断交互保持原实现。
- `dashboard_surface_expectations.dart` 增加真实绘制像素比较，验证标题栏与底栏背景一致；响应式集成测试显式覆盖 macOS、中英文、明暗主题，并在设备页、设置页和模拟器页间切换。修复前 macOS 底栏像素与标题栏不一致的用例失败。
- 毛玻璃采样的相邻内容不同，像素比较允许最多两个色阶的合成差异，并同时检查底栏实际复用公共背景组件。5 份相关测试共 50 项通过，覆盖底栏复制、网络详情、权限、窄屏和控制台切换；全仓静态分析无 error，保留 5 项既有 warning，`git diff --check` 通过。
- 无新增依赖、Provider、持久化或窗口通信；未启动完整 App。

### 全局底栏文字与图标同色（2026-11-19）

- `HostNetworkFooter` 统一使用当前主题的 `ColorScheme.onSurfaceVariant`：普通文字、可选择 IP 地址、电脑图标、复制、网络详情箭头、窄屏控制台以及诊断入口均使用同一前景色；静态图标通过局部 `IconTheme` 继承，按钮通过已有样式传入。
- `ServicesDiagnosticsButton.foregroundColor` 可选覆盖文字、图标和加载指示器，底栏显式传入统一颜色；其他调用方沿用原默认值。缺少地址时复制按钮仍禁用并弱化，问题计数徽标继续保留错误语义色。
- 新增 `host_network_footer_style_test.dart`，读取最终 `RichText` 与 `EditableText` 样式，覆盖明暗主题、普通与设备工作区主题、320px/1200px、中英文、检查中、错误徽标及禁用复制；使用内存网络和诊断快照，不执行实际探针。
- 5 份相关测试共 64 项通过，包含网络交互、诊断弹窗、页面切换及标题栏/底栏背景回归；全仓静态分析无 error，5 项既有 warning 保持不变，`git diff --check` 通过；未启动完整 App，无新增依赖或窗口通信。

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

点击服务名称或状态检查该项并展开结果，右侧箭头单独控制详情。“检查全部”执行十二项检查。
单项复测保留其他服务最近一次的结果。同一服务已有探针在执行时复用该次请求，
不同服务可同时检查。部分完成时显示已检查项数与总数，最近检查时间取最近一次完成的时间。

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
- `device_screen_preview_controller_test.dart`：三平台路由、可见生命周期、防重复、有界并发、异常重试和销毁隔离。
- `dashboard_device_list_density_test.dart`：原品牌资源、紧凑连接方式及列表行、缓存读取边界。
- `hdc_screenshot_concurrency_test.dart`：并行截图隔离、接收失败清理及 snapshot_display 回退。
- `ios_screenshot_capture_test.dart`：手动镜像恢复、自动预览不挂载及同设备并发合并。
- `device_context_action_test.dart` / `device_list_context_menu_test.dart`：能力限制、菜单打开后断线/删除、真实操作路由。
- `device_subnet_warning_test.dart`：地址复制、网络详情、显式权限/刷新、不自动轮询及大字号。
- `service_diagnostics_test.dart` / `service_diagnostic_probes_test.dart`：单项复测与全量并发去重、部分结果摘要、详情展开、超时回收、状态分类、真实适配器、可选构建和中英明暗布局。
- 同时回归现有模拟器搜索、Shell 导航、控制台、开发者页面和设备主题测试。

验证命令使用 `flutter test --no-pub`，避免依赖解析混入无关 lockfile 改动；静态分析同样使用 `--no-pub`。
仓库当前 Flutter SDK 对现有 Material/Cupertino 导入产生 deprecation info；全库既有五项 warning 位于
`emulator_service.dart`、`file_preview_controller.dart`、`dashboard_overview_components.dart` 和
`dashboard_common.dart`，本次不改动这些不相关逻辑。变更文件要求无编译错误或新增 warning。

2026-11-17 首轮落地回归：18 份测试文件、143 项全部通过；全库 analyze 无 error，保留上述既有 warning。
另外扩展执行 `device_theme_color_test.dart` 时，139 项通过、2 项失败：该文件仍要求电量与 Root
使用绿色，而 HEAD 的 `11682cbe` 与主题知识库第 9 节已明确改为中性灰。
本次未改动这些生产或旧测试文件；现有 `overview_status_chips_test.dart` 的 8 项灰色规范回归通过。
实际 Widget 的手机墙、列表和右下角诊断面板已经截图核对；没有通过截图伪造真实设备服务状态。

首轮人工/硬件边界：未运行完整 App，未自动开启用户电脑服务或连接真实手机。
最终设备端触控、USB 权限、AirPlay/DLNA 实际播放和跨窗口活动会话须在对应设备条件下验证，
诊断面板不会以组件就绪替代这些功能验收。

后续紧凑布局迭代已使用现有 `AdbService.captureScreenshot` 从当前已连接的 Mi MIX 3 与荣耀手机
获取可解码 PNG（包含折叠屏当前显示屏选择）；通过 Widget 截图核对真实手机画面在设备墙中的展示。
未启动完整 App，HDC/iOS 自动预览在本轮仅做自动化边界验证。

紧凑布局迭代最终回归：16 份相关测试文件、138 项全部通过，覆盖三平台截图、队列与
可见生命周期、截图保存、菜单、列表密度、视图切换、批量、导航及网络底栏。
全库 `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 无 error，保留上述五项既有 warning。
另外用临时验证测试确认两台已连接 Android 手机的截图可解码，并生成实际 Widget 预览；
临时测试和真实手机图片不进入 Git。手工验收时可依次检查：进入墙、刷新当前画面、切列表后停止取图、
断线后恢复品牌封面、失败时显示重试提示，以及放大字体后连接列与主操作不溢出。


## 连接设备菜单与原型对齐

连接入口的外观独立在 `features/devices/widgets/device_connection_menu.dart`，由 Shell
传入原有 pair / tcp / share 回调；无线配对、IP 连接和共享加入仍打开既有对话框。
菜单按参考图显示 Wi-Fi、链接、用户组图标，底部用分隔线隔开不可点击的 USB 说明。
基础宽度 240px、选项最小高度 40px；放大字体时允许增宽和自然换行，并限制在窗口范围内。
菜单位于按钮下方，桌面右侧边缘与按钮对齐；窄屏由原生菜单保留安全边距。
表面、边框、阴影和文字使用现有 Theme；触发按钮的 Ink 与水波纹使用相同圆角。
新增“加入共享设备”专用双语文案，不修改共享页面的既有动作名称。

回归：`device_connection_menu_test.dart` 的 8 项中英/明暗/320px 大字号矩阵，
同时执行现有设备工作区、响应式布局和 Shell 导航测试，共 30 项全部通过。
检查三项回调、USB 提示不可操作、Escape/外部点击关闭、图标与文字对齐及菜单锚点。
变更文件 `flutter analyze --no-pub` 无 error/warning，仅有现有 SDK 弃用 info。
已导出完整 Dashboard 和局部菜单的亮暗 Widget 预览；导出时恢复真实阴影渲染，
避免 Widget test 默认以轮廓替代 elevation 阴影。没有启动完整 App 或执行连接命令。


## 恢复设备标签标识

设备分类标签继续读取 `RegisteredDevice.tags`，恢复列表名称旁展示；空间不足时随名称自然换行。
设备墙将同一组标签放在名称下方居中展示，不占用手机截图区域。无标签或仅有空白字符串时不预留标签空间。
两处复用 `widgets/device_tag_badge.dart` 的原淡底描边样式，颜色随主题主色，长标签单行省略并提供完整 Tooltip。
该组件只展示用户输入，不把“主力机”等自定义内容当作固定本地化文案，也不增加标签点击动作。
批量模式下点击标签继续选择所属设备；标签本身不新增动作，宿主原有设备信息与投屏入口保持原样。
标签编辑、持久化和搜索仍使用既有机制，本次只补齐显示。

标签恢复回归：设备墙 Card、设备列表密度、实际 Dashboard 工作区与响应式布局共 4 份测试、
35 项全部通过；覆盖单标签同排且列表仍为 60px、标签更新/替换/清空、视图同源、
空白过滤、窄屏大字号多标签、明暗主题和批量点击边界。测试中 updateTags 仅替换为内存发布桩，
不宣称重新验证既有持久化链路。变更文件 analyze 无 error/warning，仅有 SDK 既有弃用 info。
设备墙与列表已导出实际 Widget 标签预览；未启动完整 App 或新建设备连接。


## 标题栏与一级页面统一

设备管理不再自行绘制标题栏，直接复用 `DashboardHeaderBar`，与设置、模拟器等页面共用
72px 最小高度、28px 水平内边距、20px 主标题、13px 副标题、3px 标题间隔及 8px 动作间隔。
背景、分隔线和窗口拖拽也由公共组件提供；刷新与连接菜单的既有行为保持不变。
490px 及以下窗口保留 10px 水平留白和 32px 顶部原生按钮避让，大字号连接入口收为图标与 Tooltip，
公共副标题单行省略，标题栏允许按内容增高；设备列表与墙的紧凑间距不变。

回归覆盖完整 Dashboard 在中英、明暗主题下切换设备与设置页，直接比较标题栏边界及两行文字起点，
并验证动作组间距和垂直居中；320px / 1.6 倍字号验证标题、刷新与连接不重叠、避让和菜单可打开。
与公共标题栏、连接菜单、工作区及 Shell 导航合计 5 份测试、41 项全部通过。
定向 analyze 无 error/warning，仅有现有 SDK 弃用 info；已导出真实 Widget 预览，未启动完整 App。


## 恢复原左侧栏（2026-11-17）

所有管理页重新使用原有 `PrimaryRail`、`_RailIdentity`、`_RailButton` 和 `_DashboardRailFooter`，
删除改版后的 `_ManagementRail` 分支和独立文件，不保留两套侧栏外观。
恢复原品牌 Logo 与身份区、原平台图标、导航项圆角/字号/间距、选中态以及宿主系统的侧栏表面。
宽度不少于 1000px 时为原 180px 图文侧栏；更窄窗口为原 76px 图标侧栏，含 490px 以下窗口。
纵向空间不足时沿用原“更多工具”入口，不为恢复样式新增导航状态或后台任务。

Shell 为 `PrimaryRail` 单独提供原应用 Theme，设备页中性主题仍作用于右侧内容，避免改版底色影响侧栏。
导航沿用原回调，帮助中心、AI MCP、控制台与设置的底部顺序、接收/互传/MCP 服务点保留。
控制台切换继续保持设备与路由；最近统一的标题栏、设备墙/列表、标签和底部 IP/诊断入口沿用现状。

验证覆盖中英明暗、180px/76px 断点、低高度折叠菜单、服务标记与控制台交互，
完整 Dashboard 另检查侧栏恢复原 ColorScheme，并回归 320px / 1.6 倍字号的内容与连接菜单。
新增 `dashboard_restored_rail_test.dart` 的 26 项侧栏回归，连同设备响应式、工作区、全局导航、
服务导航、Shell 导航及桌面窗口共 7 份测试、85 项全部通过；定向静态分析无 error/warning，仅有现有 SDK 弃用 info。
实际 Widget 已导出原侧栏的列表和设备墙预览；未启动完整 App 或执行真机连接。


## 完整系统版本与并存连接通道（2026-11-17）

系统版本两处 Text 移除 ellipsis，不设置最大行数，窄屏移到名称下方时仍保留完整原文。
桌面独立列和表头共同使用 `_DeviceTableLayout.systemWidth = 160`，常规 Android 版本及 API 有足够空间，
较长厂商版本允许换行并自然增高设备行，不靠挤宽连接列解决内容截断。

`DeviceListPresentation.connections` 返回全部在线 `DeviceConnectionKind`，列表与设备墙共享通道集合。
最初的 `DeviceConnectionIndicators(showLabels: true)` 在原 80px 连接列纵向排列图标与 USB / TCP/IP / Wi-Fi 短名称（已由下述横排方案替代），
逐项 Tooltip 使用完整本地化说明，聚合 Semantics 包含所有通道；此模式继承父行点击以支持批量选择。
默认小图标模式继续用于原调用方；展示逻辑不改变注册表合并、连接优先级或实际命令使用的 transport。

在线设备的 connections 由原 merger 只保留在线候选，离线和未授权的历史地址不显示成活跃通道；
同类多个端点只生成一个标记。iOS 只依据 USB / Network 发现类型，未知类型显示未知连接；
Harmony 的 HDC 网络端口只计入 TCP，不重复当成 Android TLS 无线调试；共享设备只展示 TCP Bridge；
AirPlay 会话独立保留，不因有投屏会话而重新显示离线的 USB / 网络历史记录。

验证包括 USB+TCP+TLS、逐条断开、去重、离线历史门禁、三平台/共享/AirPlay 边界，
以及完整 Dashboard 中英明暗、80px 列宽、长版本和 320px / 1.6 倍字号的实际布局。
默认图标模式保留原 USB / AirPlay Tooltip；新增文案模式使用完整连接状态，避免影响其他既有入口。
导出的 Widget 预览使用测试设备快照演示多通道显示，不代表新建了这些连接；未启动完整 App。

本轮同步维护主题审计用例的改版入口：计划任务先进入显式批量管理，再打开批量操作菜单；
AirPlay 按设备墙/列表切换验证状态、当前主色与可用投屏菜单，移除改版前分辨率和旧徽章断言。
共享 fixture 与生产交互未因测试调整。

验证结果：8 份连接/列表/设备墙/工作区回归共 77 项、主题审计 12 项，合计 89 项通过；
另导出 Widget 预览 1 项通过。定向 `flutter analyze --no-pub --no-fatal-infos` 无 error / warning，
保留当前 Flutter SDK 对既有 Material / Cupertino / 本地化入口的弃用 info，不扩大为全库迁移。
所有新增或调整的 Dart 文件均低于 500 行；未运行完整 App，也未为演示主动建立设备连接。

## 连接状态横向单行（2026-11-17）

USB / TCP/IP / Wi-Fi 等真实通道改为一行并排，组间 6px，复用原 14px 图标、4px 图文间距及 11px 文案。
`DeviceConnectionIndicators.labelsWidth` 使用当前语言、Theme 字体、TextScaler 与 TextDirection 测量宽度，
TextPainter 及时 dispose；测量与绘制共用样式，不使用 IntrinsicWidth 或缩小字号。
设备列表只测量不同通道组合，取可见设备所需最大宽度加 12px 列间隔，最低 80px，表头与行共享预算。
因此单通道不预留三通道空间，多个在线通道也不会增加正常列表的行高。

窄窗口将状态放到设备信息下方、使用设备行的整个内容宽度；极窄或放大文字时只让状态区域横向滚动，
仍保留所有通道、原字号与单行排列。离线/未知状态可自然换行，默认图标模式维持原 Tooltip 和点击隔离。
横排模式继续保留每项完整 Tooltip、全部通道的聚合读屏语义及父行批量点击，不改变真实连接状态与投屏命令。

验证覆盖中英明暗、1.0 / 1.6 倍字号下的水平几何、三通道与单通道同高、动态列宽的紧凑边距、
80px 区域横向滚动与前后点击、长版本完整显示及 320px 窄屏；未启动完整 App。

本次横排验证：6 份相关 Widget 测试共 73 项通过，预览导出 1 项通过；定向静态检查无 error / warning，
仅保留 Flutter SDK 既有弃用 info。调整的 Dart 文件均低于 500 行，未建立新设备连接。
