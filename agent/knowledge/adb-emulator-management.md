# Knowledge: adb-emulator-management（模拟器诊断与配置详情）

## 需求与入口

模拟器列表与设备管理为同级 Tab（索引 `-2`），主窗口使用 `EmulatorListPanel`，独立管理窗口已移除。本次解决启动失败停留在橙色状态、双击详情入口不明显、配置只有原始 key 的问题。

## 启动与失败状态

- `EmulatorService.startEmulator` 返回 `EmulatorProcess`，以参数数组执行 `emulator -avd <name>`，不再使用无法获取输出与退出码的 detached 模式。进程创建成功仅表示启动请求开始，不代表设备已上线。
- `emulator_process.dart` 持续排空 stdout/stderr，各保留末尾 16,384 个字符；允许非标准 UTF-8 输出。进程退出后最多等待 2 秒收集尾部日志，随后取消流订阅。stderr 优先提供诊断，错误仅写入本地状态。
- `emulatorLaunchProvider` 按 AVD 名称保存启动阶段、进程存活状态、错误语义、日志和退出码；进程创建异常、上线前退出（包括退出码 0）、非零退出均显示错误。正常上线后退出码 0 对应正常关闭。
- 默认等待 ADB 上线 2 分钟，超时显示“进程仍在运行，请检查模拟器窗口”。继续观察后续上线或退出，不贸然终止用户模拟器；进程仍存活时禁止重复启动、清除数据及删除。确认退出后可再次启动，重试清除上次错误。
- 启动期间显式订阅 `runningEmulatorsProvider`，不因 Tab 卸载或 Riverpod 暂停而漏掉上线结果；所有跟踪进程退出后释放该额外订阅；存活期间继续跟踪授权变化。销毁 Provider 时取消计时器、关闭订阅，并忽略后续退出回调。
- 列表以红色错误图标与错误摘要替换橙色启动状态。摘要优先匹配 ERROR/PANIC/FATAL/Missing/Failed 等行，点击错误图标查看和复制包含退出码的完整有界日志；缺失 system image 的原始报错可以直接查看。
- 不自动安装 system image、不修改 AVD 配置。错误状态属于当前窗口 Isolate；另一窗口不会自动同步该次启动日志。切换 Tab 不终止用户启动的模拟器。

## 详情与配置说明

- 每行新增 info 图标与中英文 Tooltip，点击图标和双击行共用原有配置详情回调。
- 配置名列使用“本地化名称 + 原始 key”两行展示，配置值及复制内容仍保持原值。搜索同时匹配本地化名称、原始 key 和 value。
- `app_l10n_emulator_config.dart` 集中维护中英文释义，覆盖截图中的 AvdId、PlayStore、ABI、分区、快照和常见硬件、屏幕、传感器配置；未收录的扩展 key 显示“其他配置项”并保留原始 key，不猜测含义。
- `dashboard_emulator_layout.dart` 收口原有完整页面样式，`dashboard_emulator_error.dart` 负责错误展示；面板、表格和新增文件均控制在 500 行内。明暗主题、原有操作及独立窗口布局沿用已有机制。

## 验证与回归

- `flutter test --no-pub test/emulator_process_test.dart test/emulator_launch_test.dart test/emulator_panel_test.dart`：13 项全部通过，覆盖脚本模拟缺失镜像、真实退出码、stdout 错误、有界输出、安全参数传递、进程创建异常、退出前未上线、超时、重复启动防护、超时后上线恢复、无页面监听时状态更新及销毁后回调。
- Widget 测试覆盖红色错误入口、可复制诊断、详情图标、原始 key、中文/key/value 搜索、未知配置兜底，以及英文暗色配置显示；中英文文案 key 集合一致。
- 定向静态检查仅保留原有 `emulator_service.dart` 中列表读取的 `unawaited_return_in_try_block` 和 `dashboard_screen.dart` 的 unused import 两项警告；本次未修改它们。
- 不启动桌面项目或真实 AVD。待人工验证：点击缺少镜像的 AVD，确认失败后红色错误及日志；修复镜像后重试，检查上线状态、切换 Tab、正常关闭；在主窗口/独立窗口检查详情图标、双击与明暗主题。

## 标题工具栏与 ADB 授权分流（2026-09-30）

- 移除设备管理页面右上角的模拟器窗口按钮，以左侧同级 Tab 为主入口；已有系统菜单独立窗口处理保留。
- 模拟器页标题改为 72 高度，主窗口不预留独立窗口交通灯空间；独立 macOS 窗口单独保留顶部拖拽区域。加入名称/规格搜索，窄窗口将工具栏移到第二行并允许水平滚动。
- 主操作显示启动、重连 ADB、关闭、刷新；更多菜单提供冷启动、打开目录、清空数据和删除，沿用清空/删除确认流程。关闭需要确认，重连和关闭请求期间禁用重复操作。
- `EmulatorConnectionService.inspect` 只对 `emulator-*` 查询 `adb -s <serial> emu avd name`，包含 unauthorized/offline；在线设备在 console 名称查询失败时才使用 getprop 回退。不得再以 shell 可用作为识别模拟器进程的前提。
- `emulatorConnectionsProvider` 保留完整 ADB transport 状态，`runningEmulatorsProvider` 仅投影可调试的在线设备。进程仍存活但 ADB 未授权/离线/超时显示连接提示及授权指引；已授权的实时连接优先于旧失败记录。进程真正异常退出仍显示红色失败。
- 重连只执行 `adb -s <serial> reconnect`，不使用影响全部设备的 `reconnect offline`，也不删除 adbkey 或重启全局 server。关闭执行 `adb -s <serial> emu kill`。命令入口拒绝非模拟器 serial。
- 启动前使用应用注入的 `AdbService` 执行 `start-server`，保留用户的 server/key 环境；从绝对 emulator 路径及 platform-tools 目录确认 SDK 后，显式传入 ANDROID_HOME、ANDROID_SDK_ROOT 和 AVD 目录。缺失 system image 仍需要安装对应镜像，不将补齐环境变量视为镜像修复。
- 冷启动仅添加 `-no-snapshot-load`，不清空用户数据或删除快照。若仍 unauthorized，需要在模拟器中允许 USB 调试；关闭后冷启动可排除旧快照状态，但不承诺自动授予授权。
- 源码依据：[ADB reconnect 实现](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/commandline.cpp)、[ADB console 实现](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/android15-qpr2-s8-release/client/console.cpp)、[官方调试授权说明](https://developer.android.com/tools/adb)。
- 验证：`emulator_process_test.dart`、`emulator_launch_test.dart`、`emulator_connection_test.dart`、`emulator_panel_test.dart` 共 20 项通过；覆盖 SDK 环境、冷启动、不误伤物理设备、unauthorized 状态恢复、ADB transport 消失时仍保留进程运行提示、诊断和工具栏。定向 analyze 仅有上述两项原有警告，`git diff --check` 通过。
- 本次只读检查时 `adb devices -l` 为空，未发现运行中的 qemu/emulator 进程，因此未进行真实授权重连验证；未启动桌面项目或模拟器，也未改动本机密钥。

## 三平台模拟器界面统一（2026-10-13）

- Android、HarmonyOS DevEco 与 iOS Simulator 统一采用分段平台选择、48px 表头、56px 数据行、交替行底色及主题色选中态；颜色优先取 `ColorScheme`，保留平台状态业务色。
- Android 工具栏与另外两端统一为“启动 / 停止 / 弹出独立窗口 / 刷新 / 更多”，停止操作沿用原有 `adb -s <serial> emu kill` 和确认流程；移除工具栏中的 ADB 重连入口，不改动底层定向重连能力。
- 模拟器名称搜索在有内容时显示清除按钮；清除后立即同步过滤状态。进程 Tab 将 DEBUG 作为搜索框固定快捷项，不写入普通历史，选择后切到全部进程并按 `AdbPackage.debuggable` 精确过滤；网页筛选框移除前缀图标并保留水平内边距。
- 本次仅调整既有页面的展示与筛选交互，不新增 ADB/HDC/xcrun 命令，不改变模拟器启动、关闭或数据清理的底层执行方式。

## 2026-10-28 管理入口收口

模拟器管理仅保留主窗口 `/emulators`，移除独立管理窗口、弹出按钮、macOS Window 菜单及系统托盘的管理入口。`EmulatorListPanel(isFullPage: true)` 显示完整页；默认模式仍支持可折叠卡片。管理布局不再预留独立窗口交通灯区域；各平台启动、停止、详情和运行画面保持原有行为。历史章节中的独立管理窗口说明已失效。

## 平台 Tab 复用系统版本切换器（2026-11-07）

- 需求：模拟器管理右上角 Android / HarmonyOS / iOS Tab 与系统版本页的 `PlatformVersionSwitcher` 保持一致。
- `EmulatorPlatformTabs` 直接组合 `PlatformVersionSwitcher`，复用其图标、间距、圆角、边框、分割线、选中态与 hover 动画；不再单独维护 Cupertino 分段控件及重复样式。
- 适配层通过穷举 `switch` 在 `EmulatorPlatform` 与 `PlatformDistributionType` 之间双向转换，不依赖枚举顺序。现有参数及回调类型保持兼容，选中状态仍由 `_EmulatorPageLayout` 持有，三平台页面路由与启动/停止逻辑不变。
- 本次不修改系统版本切换器本身，不新增 Theme 色值、文案、依赖、Provider 或后台命令。
- `emulator_platform_tabs_test.dart` 在 Light/Dark 下分别从三种初始平台开始验证，覆盖共享控件装配、三平台回调与父级状态更新，并在 650 px 标题栏中检查布局异常；回归 `platform_version_distribution_test.dart` 与 `emulator_panel_test.dart`。
- 验证结果：`flutter test --no-pub test/emulator_platform_tabs_test.dart test/platform_version_distribution_test.dart test/emulator_panel_test.dart` 共 20 项通过；`dart analyze lib/features/devices/widgets/emulator_platform_tabs.dart test/emulator_platform_tabs_test.dart` 无问题；`git diff --check` 通过。
- 不启动桌面 App 或真实模拟器；真实窗口中的视觉与 hover 体验仍需手工验收。

## Android 模拟器搜索框高度对齐（2026-11-16）

- 需求：Android 模拟器管理的搜索框与设备管理搜索框等高。原搜索框使用默认 48px 图标约束，比设备搜索框的 40px 更高。
- 实现：`AppThemeSizes.searchFieldContentPadding` 统一水平 12px、垂直 10px 内边距，`searchFieldIconConstraints` 统一 40×40 最小图标区域；设备搜索框原有尺寸值迁入这两个常量，视觉不变。`dashboard_emulator_layout.dart` 复用相同尺寸与 `bodyMedium` 字体，清除按钮使用 `VisualDensity.compact`，避免输入后重新撑高。
- 边界：保留搜索框宽度、圆角、颜色、搜索与清除回调；不固定整体高度，放大字体时自然增高。不新增文案、Provider、后台命令或跨窗口协议，不修改模拟器启动、投屏或另外两平台的搜索框。
- 自动验证：`flutter --no-version-check test --no-pub test/emulator_search_fields_test.dart test/emulator_panel_test.dart test/device_list_filters_test.dart`，19 项全部通过。新增用例直接比较两处实际 Widget 高度，覆盖中英文、Light/Dark、1200/620px 窗口、1.6 倍文字，以及空输入、聚焦输入和清除后高度；标准文字下验证高度为 40px，并保留圆角检查。
- 静态验证：4 个修改 Dart 文件定向 `flutter analyze --no-pub --no-fatal-infos` 无 error / warning，仅有当前 SDK 的 5 项 Flutter UI / 本地化 API 弃用 info；`git diff --check` 通过。未启动桌面 App 或真实模拟器，实际窗口视觉待运行包验收。

## 三平台模拟器搜索框等高（2026-11-16）

- HarmonyOS DevEco 与 iOS 搜索框接入相同的 `AppThemeSizes.searchFieldContentPadding`、`searchFieldIconConstraints` 和 `bodyMedium` 字体，清除按钮统一使用 `VisualDensity.compact`。三平台在标准文字下均为 40px，放大字体时自然增高。
- 保留各平台搜索、清除、输入宽度、圆角及模拟器操作，不新增文案、后台命令或 Provider。此次仅扩展搜索框尺寸配置。
- `emulator_search_fields_test.dart` 将原有等高用例参数化为 Android / HarmonyOS / iOS，与实际设备搜索框比较高度；覆盖中英文环境、Light/Dark、1200/620px 窗口、1.6 倍文字，以及输入前、输入后和清除后的状态。DevEco / iOS 原有搜索结果与清除交互用例继续保留。
- 验证：`flutter --no-version-check test --no-pub test/emulator_search_fields_test.dart test/emulator_panel_test.dart test/device_list_filters_test.dart` 共 27 项通过；3 个修改 Dart 文件定向 `flutter analyze --no-pub --no-fatal-infos` 无 error / warning，仅有 7 项 SDK 弃用 info；`git diff --check` 通过。未启动桌面 App 或真实模拟器。

## Android 模拟器表格随窗口缩放（2026-11-19）

- 表头和数据行共用六列权重，按侧栏右侧的实际可用宽度分配。单元格左右各留 6 个逻辑像素，名称列保留状态与详情入口，长文本可悬停查看。
- `emulator_panel_test.dart` 在侧栏占用 180 个逻辑像素的布局下连续缩放窗口，覆盖 520、620、920、1400 四种表格宽度，验证六列同步收窄、首尾贴合边界、数据与表头对齐，以及详情图标可点击。

## 平台切换选中项使用白底（2026-11-19）

- 共享 `PlatformVersionSwitcher` 的选中背景改为 `AppThemeColors.panelSurface`，浅色模式为白色，深色模式使用对应面板底色；选中文字改为 `ColorScheme.onSurface`，不再使用主色容器配色。模拟器管理与系统版本页同步生效，平台品牌图标和切换回调沿用原实现。
- `emulator_platform_tabs_test.dart` 覆盖三平台初始状态及逐项切换，并使用绿色、蓝色、粉色主题验证白底与主色无关；深浅主题均检查选中文字对比度不低于 4.5，未选中项保持透明。
- 3 份相关测试共 21 项通过；全仓静态分析无 error，5 项既有 warning 保持不变，`git diff --check` 通过。未新增依赖、Provider、文案或后台命令，未启动完整 App 或真实模拟器。

## 模拟器管理侧栏运行圆点

- `anyEmulatorRunningProvider` 汇总 Android、HarmonyOS 和 iOS 的运行状态。任一平台有运行实例即显示圆点，最后一个实例退出后隐藏。侧栏复用投屏接收和 AI MCP 的 `_RailButton`、主题主色及本地化提示。页面选中态仍由当前 Route 对应的 Tab 决定。
- Android 复用设备发现流中的 `emulator-<port>` ADB transport，包含未授权或暂时离线的实例。HarmonyOS 复用同一发现流，旧版以 HDC 的 `emulator-<port>` 标识识别，现代版本只对已连接的本地回环目标执行 `param get | grep hvd`，确认 `ohos.qemu.hvd.name` 后显示圆点。连续连接复用确认结果，普通真机和目录中的离线配置不会触发圆点。参见[华为模拟器 HDC 参数文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-video/)和[旧版模拟器 HDC 示例](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs-V2/faq-local-emulator-0000001162764909-V2/)。
- iOS 在 macOS 上用有超时和输出上限的 `xcrun simctl list --json devices booted` 检查已启动实例。侧栏入口订阅时立即读取，此后每 5 秒串行刷新，释放订阅后停止轮询。切换内容页或模拟器平台 Tab 时，全局侧栏显示的状态保持独立。此功能不涉及投屏协议、窗口通信、模拟器启停或配置写入。
- 自动回归使用设备发现、HDC 和 iOS Simulator 数据替身，检查三平台分别启停、多个实例、最后一个实例退出、排除真机、显示与页面选中解耦、深浅主题和主题色切换、宽窄侧栏及订阅释放。实际桌面窗口仍需用三平台模拟器启停确认，HarmonyOS 的运行识别依赖已连接到 HDC 的模拟器。
- 独立工作树中 57 项定向测试通过。恢复旧侧栏后，模拟 Android 启动的圆点断言按预期失败。全仓静态分析无 error，保留 5 项既有 warning。使用 `simctl` 只读确认了本机无运行实例时的返回结构。
- 主窗口 Widget 测试的公共环境与独立夹具统一隔离宿主机模拟器探测，防止真实命令的超时计时器跨出 FakeAsync 测试生命周期。补齐后重跑受影响的 10 个测试文件，93 项全部通过。
