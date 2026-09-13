# Knowledge: adb-dashboard-device-identity (Dashboard 设备身份入口)

## 目标

Dashboard 左侧导航顶部统一承担 App/设备身份入口：未选择设备时展示 App logo 与应用名称；选择设备后展示对应品牌 logo、设备名称及 USB/Wi-Fi 连接方式。

## 交互与数据边界

1. 左侧身份区的点击逻辑将 `selectedToolTabProvider` 切换为 `-1`，清空 `selectedDeviceProvider` 并返回设备管理页面；设备管理页面统一展示 App logo 与应用名称 AnyDeck，侧边栏仅展示【设备管理】Tab，收起特定手机下的 Tab。
2. 品牌 logo 通过 `deviceOverviewProvider(deviceId)` 的 `brand`、`manufacturer` 和 `BrandLogoHelper` 解析：优先使用品牌图标，未命中时使用制造商图标，均未命中则展示通用手机图标；设备名称与连接方式以 `deviceRegistryProvider` 中匹配的 `RegisteredDevice` 为准。
3. 未授权或离线设备继续使用外框状态色，但品牌 logo 始终保持原始颜色与不透明度，避免 Apple、Huawei 等白底 JPEG 素材灰化后失真；音频转发状态点仍按 SDK 与设置展示。
4. 设备工具页不再渲染独立的顶部 `_SelectedDeviceHeader`，也不提供右上角叉号清空设备；切换设备统一返回设备管理列表操作。
5. 窄侧栏只显示当前身份 logo，宽侧栏同时显示设备名称和连接方式，避免影响工具项的自适应折叠规则。

## 影响边界

- 调整主窗口 Dashboard 身份展示及其概览字段，不改变 ADB 命令、设备选择、投屏进程或多窗口 MethodChannel。
- 明暗主题颜色从 `ThemeData.colorScheme` 获取；USB/Wi-Fi 为协议名，不新增 l10n 文案。

## 内容区 Material 绘制层级（2026-09-14）

- 应用详情组件列表的 `ListTile` 带长按复制操作。原 `_WechatStyleShell` 的玻璃背景 `Container` 位于列表与最近的 `Material` 之间，其 `DecoratedBox` 会遮挡列表底色和水波纹，触发 `ListTile background color or ink splashes may be invisible`。
- `lib/features/overview/dashboard_shell.dart` 在背景容器内、内容 `Column` 外统一增加 `Material(type: MaterialType.transparency)`，让各 Tab 的列表共用背景上方的绘制层，保留原有明暗主题背景色、左边框、模糊与内容间距。
- 此次只调整主窗口内容区绘制层级，无新增依赖、可见文案、Provider、ADB 命令或跨窗口通信，长按复制回调保持原样。
- 验证：`flutter analyze --no-pub lib/features/overview/dashboard_shell.dart` 与 `git diff --check` 通过；全仓 `flutter analyze --no-pub` 仍有 53 项无关现有诊断，主要错误来自 `test/apps_tab_filter_test.dart` 的旧构造参数与缺失测试桩，本次修改文件无诊断。
- 手动回归：在明暗主题下打开应用详情组件列表，滚动并长按复制名称，确认无上述断言、交互反馈可见且复制正常；切换其他列表 Tab，检查玻璃背景和左边框。本次未启动桌面项目，实际画面与交互待手动验证。

## 品牌与制造商兜底（2026-09-14）

- `DeviceInfoService` 复用已有整批 `getprop` 结果，分别读取 `ro.product.brand` / `ro.product.vendor.brand` 与 `ro.product.manufacturer` / `ro.product.vendor.manufacturer`，不增加 ADB 查询或后台进程。
- `DeviceOverview.manufacturer` 参与 `toJson`、`fromJson` 和 `copyWith`；旧缓存缺少字段时取 `-`，沿现有 Provider 的“缓存先展示、在线再查询”流程补齐，离线恢复保留两个原始字段。
- `BrandLogoHelper.getBrandLogoAsset(brand, manufacturer: manufacturer)` 集中处理展示回退，不用制造商覆盖原始品牌，也不新增 `Meitu → Xiaomi` 的全局别名。
- MI CC 9 Meitu Edition 已实测返回 `brand=Meitu`、`manufacturer=Xiaomi`：当前没有美图图标时使用小米 logo，概览品牌继续显示 `Meitu`。其他美图设备若制造商也为 `Meitu`，继续使用通用图标。
- 已识别品牌优先于制造商，例如 `Google / Samsung` 仍使用 Google 图标；图标归类不参与 SDK、ROM 或投屏能力判断。
- 本次修改涉及概览数据模型、采集、共享图标 helper 与侧栏调用，不新增依赖、Provider、MethodChannel、可见文案或主题样式。

### 验证与回归

- 定向测试：`flutter test test/brand_logo_helper_test.dart test/device_overview_test.dart`，10 项全部通过，覆盖品牌优先、制造商兜底、大小写/空值、旧缓存补齐、离线恢复、序列化与 `copyWith`。
- 静态检查：本次 6 个 Dart 文件定向 `flutter analyze` 通过；全仓 `flutter analyze` 有 53 项无关现有问题，包括 `apps_tab_filter_test.dart` 的旧构造参数及缺失测试桩，以及其他模块的 warning/info，本次修改文件无诊断。
- 手动回归：更新应用后选择美图版手机，等待概览刷新，检查侧栏小米 logo 与概览 `Meitu` 同时保留；切换 Tab、断线后恢复缓存，并检查普通 Xiaomi、Apple、HUAWEI 图标及明暗主题。
- 验证边界：ADB 属性已真机读取；桌面应用不启动，实际侧栏渲染与交互仍需手动回归。
