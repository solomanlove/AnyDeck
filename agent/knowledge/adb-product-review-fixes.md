# AnyDeck 产品体验问题修复（2026-10-31）

依据 2026-10-30 黑盒体验表 AD-001～AD-013 修改。表中的锁屏、HDC 无目标与服务发现无响应属于验收环境记录，不据此修改产品功能。

## AD-001、AD-013：手动连接表单

- 旧弹窗在 `showDialog` 返回后立即释放 `TextEditingController`，退出动画期间输入框可能仍引用该控制器；地址也未校验。新 `TcpipConnectionDialog` 由 State 持有控制器，随 Route 卸载释放。
- 统一校验 IP/主机名和 1～65535 端口，省略端口默认 5555；无效输入留在表单内，不调用连接服务。连接中禁用提交，失败保留输入、显示错误并允许重试，关闭后晚到结果不再访问界面。
- 不预填一个看似真实的地址；示例只放在 hint 中。先展示输入与准备提示，Android、HarmonyOS 和排障指南分别折叠。指南与新提示均提供中英文并使用当前 Theme。
- 保留现有 `connectNetworkDevice` 的 ADB/HDC 连接、注册表刷新和命令超时机制；不新增后台进程、多窗口广播或投屏参数修改。

### 验证与交接

- `flutter test --no-pub test/tcpip_connection_dialog_test.dart`：7 项通过，覆盖非法地址、有效输入、中文/英文、明暗主题、退出动画、失败后重试入口、防重复和关闭后的迟到错误。
- 定向 `flutter analyze --no-pub`：无新增诊断。共享入口保留两个既有 `unused_element`（`_restartAdbServer`、`_openLocalTerminal`），HEAD 中也只有声明，无关代码未改动。
- 未启动项目或操作真机。需在运行包复核 `invalid:abc` 就地报错、有效地址失败后重试，以及现有投屏不受弹窗退出影响。自动测试不能代替 Release/真机验收。

## AD-002、AD-007：MCP 数据可信度

- `get_device_detail` 保留旧详情字段，新增 `connectionState`、`dataSource`（live/cache/unavailable）、`collectedAt`、`checkedAt`、`stale`；实时失败同时返回 `readError`。Android 失败后通过有界 `get-state` 查询当前连接状态，无法判断时为 unknown；无缓存不生成虚构详情。
- `DeviceInfoService.loadOverview` 增加 `allowCachedFallback`，UI 默认行为不变，MCP 禁止静默回退。缓存沿用原键与扁平结构，仅真实采集写 UTC 时间；历史缓存及未提供采集时间的写入返回 null。iOS 部分读取标 partial，全部失败不冒充 live，连接状态无法确认时为 unknown。
- 电池保留原字段/raw，增加 normalized：百分比、摄氏温度、电压 V、充放电与健康枚举，rawUnits 明确十分之一℃与 mV；缺失和非法数值为 null，未知枚举为 unknown。Android 枚举依据 [BatteryManager](https://developer.android.com/reference/android/os/BatteryManager)。
- 验证：MCP 新增 8 项测试；与设备概览/MCP 协议回归共 26 项通过，5 个相关文件定向 analyze 无诊断。覆盖旧缓存离线、实时采集后断线、无缓存、transport 在线但采集失败、默认 UI 回退兼容、负温度及非法电池值。未连接真机或重启运行中的 MCP 服务。

## AD-003～AD-006：系统版本资料可读性

- 共享 `VersionContentViewport` 为主窗口三平台内容提供足够排版宽度；窄窗口显示常驻水平滚动条与“版本列表 / 查看详情”两端跳转，原列表选择和详情复制继续可用。控制器随页面卸载释放。
- HarmonyOS 将建议文字和复制配置分开。`compatibleSdkVersion` 使用确定的整数 API（20 或该条目更低 API），UI 明确标为“需按项目调整”的示例，不能直接覆盖项目已有 products。未做 DevEco 编译验收。
- Android 17 删除过期预测和未核验的特性描述，按 [官方获取页面](https://developer.android.com/about/versions/17/get) 与 [target API 37 行为变更](https://developer.android.com/about/versions/17/behavior-changes-17) 更新为可获取系统镜像、RemoteViews 内存限制、MessageQueue 与 LAN 权限摘要。核验日期 2026-10-31；分布快照仍为 2026-10-13，独立窗口不再把当天日期伪装为统计更新。
- iOS 按来源、采样日期、统计对象分卡呈现，移除混用比例轴。旧条目缺少采样日期时标记“未记录”，第三方样本范围未核验时明确显示，保留原始比例不合计。
- 验证：新增视口/配置/时效检查，并运行三平台复制、导航及版本模型回归，共 25 项通过；相关文件 analyze 无诊断。覆盖 820×780 内容区域（1100 主窗口扣除侧栏）、624×400 与低高度、中英文/明暗主题。未启动 App；真实桌面滚轮、触控板与 Release 包阅读体验仍需验收。
