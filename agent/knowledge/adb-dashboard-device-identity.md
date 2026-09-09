# Knowledge: adb-dashboard-device-identity (Dashboard 设备身份入口)

## 目标

Dashboard 左侧导航顶部统一承担 App/设备身份入口：未选择设备时展示 App logo 与应用名称；选择设备后展示对应品牌 logo、设备名称及 USB/Wi-Fi 连接方式。

## 交互与数据边界

1. 左侧身份区的点击逻辑将 `selectedToolTabProvider` 切换为 `-1`，清空 `selectedDeviceProvider` 并返回设备管理页面；设备管理页面统一展示 App logo 与应用名称 AnyDeck，侧边栏仅展示【设备管理】Tab，收起特定手机下的 Tab。
2. 品牌 logo 通过 `deviceOverviewProvider(deviceId)` 的 `brand` 和 `BrandLogoHelper` 解析；设备名称与连接方式以 `deviceRegistryProvider` 中匹配的 `RegisteredDevice` 为准。
3. 未授权或离线设备继续使用外框状态色，但品牌 logo 始终保持原始颜色与不透明度，避免 Apple、Huawei 等白底 JPEG 素材灰化后失真；音频转发状态点仍按 SDK 与设置展示。
4. 设备工具页不再渲染独立的顶部 `_SelectedDeviceHeader`，也不提供右上角叉号清空设备；切换设备统一返回设备管理列表操作。
5. 窄侧栏只显示当前身份 logo，宽侧栏同时显示设备名称和连接方式，避免影响工具项的自适应折叠规则。

## 影响边界

- 仅调整主窗口 Dashboard 布局，不修改 ADB 查询、设备选择、投屏进程或多窗口 MethodChannel。
- 明暗主题颜色从 `ThemeData.colorScheme` 获取；USB/Wi-Fi 为协议名，不新增 l10n 文案。
