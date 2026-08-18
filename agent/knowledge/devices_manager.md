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
