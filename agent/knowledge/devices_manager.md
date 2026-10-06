# Device Manager Identifier Principles (设备管理唯一标识判断机制)

在 AdbManage (AnyDeck) 项目中，对于已连接设备的唯一性判断、去重归并以及底层命令操作，分别通过以下几个核心字段和逻辑实现。

---

## 1. 核心字段与定义

### 1.1 `id` 字段 (底层连接与操作标识)
* **类属性**：`AdbDevice.id` 与 `RegisteredDevice.id`
* **值来源**：来源于运行 `adb devices -l` 命令行输出的第一列。
  * **USB 物理连接**：通常为设备的**硬件序列号 (Serial Number)**（例如：`9889db434c44454d4f`）。
  * **TCP/IP 无线连接**：通常为 **`IP:Port`** 格式（例如：`192.168.1.100:5555`）。
* **作用**：
  * **命令执行**：由于 ADB 命令行需要通过 `-s <id>` 来指定特定的设备实例，因此所有底层的 Shell 操作（如投屏、安装应用、发送 keyevent）最终都由 `id` 字段来路由。
  * **状态表示**：每个 `id` 对应 adb runtime 探测到的一个具体连接实体。

### 1.2 `serial` 字段 (物理设备唯一标识)
* **类属性**：`RegisteredDevice.serial`
* **值来源**：系统会对在线设备自动发起 Shell 请求，按顺序尝试通过以下系统属性或命令拉取真实的**硬件序列号**：
  1. `getprop ro.serialno`
  2. `getprop ro.boot.serialno`
  3. `adb get-serialno` (兜底)
* **作用**：
  * **物理去重**：由于同一台手机可能同时通过 USB 和网络无线连接到电脑，产生两个不同的 `id`，系统会将这二者依据相同的 `serial` 聚合在一起，避免界面重复展示。

---

## 2. 核心业务机制

### 2.1 同一物理设备的分组与去重逻辑
在全局设备注册表更新时，[`DeviceRegistryNotifier._mergeDevices`](file:///Users/shijie/Documents/AdbManage/lib/core/providers/app_providers.dart#L1454) 会对候选的在线/历史离线设备进行合并：
```dart
// 按硬件序列号进行分组
final groups = <String, List<RegisteredDevice>>{};
for (final candidate in allCandidates) {
  final serial = _serialMap[candidate.id] ?? candidate.id;
  groups.putIfAbsent(serial, () => []).add(candidate);
}
```
* **归并与合并**：对于属于同一个 `serial` 组的多个设备实例，系统会根据 **在线优先、USB 优先** 的排序规则筛选出最佳候选（Best Choice），以此代表该设备展现在界面上。
* **数据融合**：代表物理设备的对象会融合同一 `serial` 组下所有的属性，包含 customName（别名）、在线 connections 列表等。

### 2.2 全局关联查询逻辑
当上层模块需要判定设备是否为当前所选，或者判断其 Android 系统版本、SDK 能力时，系统通过组合多重条件以容错：
```dart
final deviceAndroidVersionProvider = Provider.autoDispose
    .family<String?, String>((ref, deviceId) {
      final devices = ref.watch(deviceRegistryProvider);
      for (final device in devices) {
        if (device.id == deviceId ||
            device.serial == deviceId ||
            device.connections.contains(deviceId)) {
          return device.androidVersion;
        }
      }
      return null;
    });
```
如上所示，匹配一个设备的 `deviceId` 时，会通过 `id`、`serial` 以及无线/USB 双通道对应的 `connections` 列表三个维度交叉比对。

### 2.3 ADB 与 HDC 同地址时的路由判定

`HdcService.listDevices()` 仅接收状态明确为 `Connected` 的 HDC 目标。`hdc list targets -v` 中的 `Unknown`、`Offline` 不代表可用的鸿蒙设备，不能因此对该地址执行 `hdc -t <id> shell`；只有详细列表命令不可用时才回退到无状态列表。

`DeviceRegistryNotifier._mergeDevices()` 对相同 `id` 的活动设备先按在线状态去重；双方状态相同时，ADB 记录优先于 HDC 记录。去重结果同时用于设备展示、型号与产品缓存、序列号及版本拉取，防止 Android 的 `IP:Port` 被 HDC 记录覆盖后错误走 Harmony 命令。

回归：`flutter test test/harmony_device_serial_merge_test.dart` 覆盖 HDC `Unknown` 过滤和 ADB/HDC 同地址路由。手工验收可同时观察 `adb devices -l`、`hdc list targets -v` 与控制台日志：当 Android 地址仅在 HDC 中呈 `Unknown` 时，不应再出现针对该地址的 `hdc -t ... shell`。普通 HDC 全局设备扫描仍会执行。

### 2.4 HDC 瞬态错误与设备信息缓存清洗

HDC 在通信通道仍建立中时可能以退出码 `0` 输出 `[E0...]`、`The communication channel is being established` 或 `Please wait for several seconds`。`HdcService.run()` 与 Rust `HarmonyDriver` 必须把这些 stdout 文本转换为失败结果，设备列表解析也必须过滤同类提示，禁止将其当作 serial、model 或在线 target。

`HdcServiceDeviceInfo.isGenericOrInvalidModel()` 集中识别通用 HarmonyOS 占位名称及常见错误文本；设备注册表初始化时会清理已被错误提示污染的型号缓存。只有系统版本与真实型号均已获取时才把该设备记为已完成补全，否则保持后续异步重试，且不得用无效结果覆盖现有版本缓存。

回归：`test/harmony_device_serial_merge_test.dart` 覆盖通信通道提示过滤、有效型号保留、展示名称回退与历史污染缓存清理。按仓库规则未启动桌面项目；HDC 首次握手后的自动重试节奏和真机 UI 展示仍需手工验收。

### 2.5 iOS 列表型号与系统版本

`IosDeviceService` 对 Rust DAL 和 go-ios CLI 的设备列表共用解析逻辑，使用 `IosDeviceIdentity` 将 `ProductType` 转换为已核对的型号名称。目前复用 `IosModelSpec` 的 `iPhone8,1 → iPhone 6s` 映射，其他型号保留硬件标识，不将系统名称 `ProductName: iPhone OS` 当作机型。带 `level` 的日志即使包含 UDID 也不能生成设备记录。

`ProductVersion` 作为实际版本号存入 `AdbDevice.product` 和 `devices.products`；`DeviceRegistryMerger` 将其填入列表共用的 `RegisteredDevice.androidVersion` 字段，显示为 `iOS 15.8.8`。当前发现版本优先于历史缓存，空值或 `iOS` 占位值不覆盖已知版本。离线记录和旧版 `iPhone OS (iPhone8,1)` 缓存也能直接显示型号与版本，用户别名仍优先，不依赖打开概览页面。

注册表补全元数据时跳过 iOS，不再对 UDID 发起 Android ADB 探测。此变更不增加 CLI 轮询、不修改投屏会话、UI 样式或多窗口设置协议。

验证：`test/ios_device_service_test.dart`、`test/ios_device_registry_test.dart` 覆盖 Rust/CLI 字段、日志过滤、未知型号、首次连接、旧缓存、别名、重连版本更新、缺失版本和重新加载；与 IP、Harmony 合并回归共 27 项通过，定向 `flutter analyze` 无问题。2026-10-06 真机只读 `ios list --details` 确认返回 `iPhone8,1 / 15.8.8`；未启动桌面应用，列表实际渲染仍待手工验收。
