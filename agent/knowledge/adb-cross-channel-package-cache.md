# Knowledge: adb-cross-channel-package-cache (Wi-Fi 与 USB 双通道应用缓存共享机制)

## 1. 现象与问题根因

在通过无线调试（Wi-Fi IP:Port）连接 Android 手机并获取应用列表后，插上 USB 数据线时，原先获取到的应用列表、中文标签及图标会全部丢失，界面直接报错或必须手动点击重新获取。

### 根因链条
1. **多连接代表选举切换**：`DeviceRegistryNotifier` 中检测到同一物理设备（相同 Hardware Serial）的 USB 连接上线后，因优先级规则设定为“在线优先，USB 优先于网络”，代表设备从 `IP:Port` 变更为 `USB Serial`。
2. **缓存 Key 寻址割裂**：`AppManagementService` 原先直接使用当前连接 endpoint 的 `deviceId`（如 `192.168.1.100:5555`）作为 SharedPreferences 的存储 Key（`apps.packages.v3.$deviceId`）与图标目录命名空间，切换到 USB Serial 后发生 Cache Miss。
3. **USB 插入瞬态未就绪**：USB 数据线插入时，Android 端通常经历 RSA 调试授权（`unauthorized`）或协议协商（`offline`）瞬态。原逻辑在缓存未命中时盲目执行 `pm list packages`，直接抛出 ADB 连接异常，使 Riverpod `packagesProvider` 落入 `AsyncValue.error`，彻底冲刷掉原有的展示内容。

---

## 2. 架构设计与实现

### 2.1 统一 Canonical Serial 与多通道 Fallback 寻址
- **设备规范身份映射**：在 `PackagesNotifier` 中，通过 `ref.read(deviceRegistryProvider)` 将当前 `deviceId` 解析为其物理设备的规范硬件序列号 `canonicalId`（`device.serial`）以及同设备的其他网络/USB 关联连接 `fallbackKeys`。
- **内存级缓存与同步直出**：`AppManagementService` 维护内存缓存 `_memoryCache`，并提供同步查询接口 `getCachedPackagesSync(deviceId, canonicalId: ..., fallbackKeys: ...)`。当 UI 在 Wi-Fi 与 USB 之间重定向时，`build()` 可在首帧**同步直接返回 `AsyncValue.data`**，完全消除白屏、Loading 旋转器或闪烁。
- **持久化回退与双向补齐**：`_loadPackageCache` 在当前 Key 未命中时，自动检索 `canonicalId` 与各 `fallbackKeys`。命中后自动在内存及持久化存储中补齐当前 `deviceId` 的副本。
- **图标文件目录复用**：`_localIconCacheDir` 优先以 `canonicalId ?? deviceId` 寻址，并在 `_pullIconIfNeeded` 中优先检索关联连接目录中已下载的同名图标，避免跨通道重复执行 `adb pull`。

### 2.2 通道就绪防护与现有数据保护
- **就绪检查**：在执行底层 `service.listPackages` 之前，先通过 `deviceOnlineProvider(deviceId)` 判断当前通道是否真正处于在线就绪状态。若处于未授权或握手瞬态，直接返回，不盲目触发命令。
- **数据保护**：若 `state.hasValue` 已经持有有效的应用列表，后台偶发握手错误（如 USB 插入时的端口重置）进行静默捕获，绝不将 UI 状态冲刷为 `AsyncValue.error`。

---

## 3. 影响边界与关键文件

1. **`lib/core/apps/app_management_service.dart`**：
   - 增加 `_memoryCache`、`getCachedPackagesSync`；
   - `_loadPackageCache`、`_savePackageCache`、`clearPackageCache`、`clearDeviceCache` 支持 `canonicalId` 与 `fallbackKeys`；
   - `_pullIconIfNeeded` 优先复用回退目录中已存在的图标文件。
2. **`lib/core/apps/package_refresh_runner.dart`**：
   - 构造参数及刷新流程透传 `canonicalId` 与 `fallbackKeys`，保证刷新完成落盘时双向同步。
3. **`lib/core/providers/app_providers.dart` (`PackagesNotifier`)**：
   - 解析 `_canonicalId` 与 `_fallbackKeys`；
   - `build()` 同步秒级直出内存数据；
   - `_load()` 增加通道就绪校验与 `state.hasValue` 异常容灾。
4. **`test/app_management_service_test.dart`**：
   - 增加无线切 USB 跨通道缓存共享与秒级同步命中单元测试用例。
