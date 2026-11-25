# Android 内存页大小

在 AnyDeck 设备管理中打开 Android 设备的「概览」。「系统与网络」卡片的「内核版本」下方显示「内存页大小」，用于确认设备本次启动采用的分页规格。

## 数据链路

- `DeviceInfoService.loadOverview()` 在现有基础信息分组 Shell 中执行 `getconf PAGE_SIZE`。后续命令照常执行，缺少该命令只影响页大小字段。
- `DeviceOverview.pageSizeBytes` 记录 `4096` 或 `16384`。未采集、意外输出和旧缓存缺字段时读为 `null`，显示「未知」。复用概览的刷新与离线缓存，离线已知值代表最后一次采集结果。
- `_systemNetworkItems()` 沿用系统与网络卡片的详情行和本地化。Android 真机和模拟器适用，iOS 与 HarmonyOS 概览隐藏该行。

## 验证

- `test/device_overview_test.dart` 覆盖两种页大小、刷新旧缓存、离线回退，以及缺失或异常输出对其他字段的隔离。
- `test/overview_custom_os_test.dart` 覆盖中英文、宽窄布局、明暗主题、未知文案、行位置和平台隔离。
- 小米 MIX 3 和 Android 模拟器分别执行实际概览分组 Shell，得到 `4096` 和 `16384`，Shell 均以状态码 `0` 退出。
- 手动验收时，可在桌面端打开对应设备的概览并点击刷新，再执行以下命令核对显示值。

```bash
adb -s <设备序列号> shell getconf PAGE_SIZE
```

[Android 官方页大小文档](https://developer.android.com/guide/practices/page-sizes)
