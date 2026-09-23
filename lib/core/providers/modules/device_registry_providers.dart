import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../adb/adb_device.dart';
import '../../adb/adb_result.dart';
import '../../ios/ios_mirror_service.dart';
import 'dashboard_state_providers.dart';
import 'device_registry_actions.dart';
import 'device_registry_merger.dart';
import 'device_registry_probe_service.dart';
import 'device_registry_storage.dart';
import 'device_tracking_providers.dart';
import 'registered_device_model.dart';
import 'service_providers.dart';

part 'device_registry_item_actions.dart';

/// 全局设备注册表 Provider。
///
/// 维护当前所有已发现设备（在线与历史离线）、自定义别名、备注、标签及选中状态的响应式列表。
final deviceRegistryProvider =
    NotifierProvider<DeviceRegistryNotifier, List<RegisteredDevice>>(
      DeviceRegistryNotifier.new,
    );

/// 全局设备注册表控制器。
class DeviceRegistryNotifier extends Notifier<List<RegisteredDevice>>
    with DeviceRegistryItemActionsMixin {
  @override
  final DeviceRegistryStorage _storage = DeviceRegistryStorage();

  @override
  List<String> _historyIds = [];
  @override
  Map<String, String> _aliases = {};
  @override
  Map<String, String> _models = {};
  @override
  Map<String, String> _products = {};
  @override
  Map<String, String> _ipAddresses = {};
  @override
  Map<String, String> _androidVersions = {};
  @override
  Map<String, int> _sdkVersions = {};
  @override
  Map<String, String> _remarks = {};
  @override
  Map<String, List<String>> _tags = {};
  @override
  Set<String> _checkedIds = {};
  @override
  Map<String, String> _serialMap = {};
  @override
  List<AdbDevice> _lastActiveDevices = [];
  @override
  final Set<String> _pendingFetchIds = {};
  @override
  final Set<String> _attemptedFetchIds = {};
  bool _isDisposed = false;

  /// 获取设备已映射的物理硬件序列号，未映射时返回 null
  String? getSerial(String id) => _serialMap[id];

  @override
  List<RegisteredDevice> build() {
    ref.onDispose(() {
      _isDisposed = true;
    });

    final activeDevicesAsync = ref.watch(devicesProvider);
    final activeDevices = activeDevicesAsync.value ?? _lastActiveDevices;
    if (activeDevicesAsync.hasValue) {
      _lastActiveDevices = activeDevices;
    }

    _loadFromPrefs();

    return _mergeDevices(activeDevices);
  }

  Future<void> _loadFromPrefs() async {
    final activeDevices = _lastActiveDevices;
    final data = await _storage.loadFromPrefs(activeDevices);
    if (_isDisposed) return;

    _historyIds = data.historyIds;
    _aliases = data.aliases;
    _models = data.models;
    _products = data.products;
    _ipAddresses = data.ipAddresses;
    _androidVersions = data.androidVersions;
    _sdkVersions = data.sdkVersions;
    _remarks = data.remarks;
    _tags = data.tags;
    _serialMap = data.serialMap;

    state = _mergeDevices(activeDevices);
  }

  void _fetchAndCacheSerial(String id) {
    Future.microtask(() async {
      final activeDevs = ref.read(devicesProvider).value ?? _lastActiveDevices;
      final dev = activeDevs.firstWhere(
        (d) => d.id == id,
        orElse: () => AdbDevice(id: id, status: 'offline', model: '', product: ''),
      );

      if (dev.isHarmony) {
        _fetchAndCacheHarmony(id);
        return;
      }

      try {
        final adb = ref.read(adbServiceProvider);
        await DeviceRegistryProbeService.probeAndSyncAndroid(
          adb: adb,
          id: id,
          androidVersions: _androidVersions,
          sdkVersions: _sdkVersions,
          serialMap: _serialMap,
          ipAddresses: _ipAddresses,
          storage: _storage,
        );
      } finally {
        _pendingFetchIds.remove(id);
        _attemptedFetchIds.add(id);
        if (!_isDisposed) {
          final activeDevices =
              ref.read(devicesProvider).value ?? _lastActiveDevices;
          state = _mergeDevices(activeDevices);
        }
      }
    });
  }

  void _fetchAndCacheHarmony(String id) {
    Future.microtask(() async {
      bool hasValidInfo = false;
      try {
        final hdc = ref.read(hdcServiceProvider);
        hasValidInfo = await DeviceRegistryProbeService.probeAndSyncHarmony(
          hdc: hdc,
          id: id,
          serialMap: _serialMap,
          androidVersions: _androidVersions,
          sdkVersions: _sdkVersions,
          models: _models,
          products: _products,
          ipAddresses: _ipAddresses,
          storage: _storage,
        );
      } finally {
        _pendingFetchIds.remove(id);
        if (hasValidInfo) {
          _attemptedFetchIds.add(id);
        }
        if (!_isDisposed) {
          final activeDevices =
              ref.read(devicesProvider).value ?? _lastActiveDevices;
          state = _mergeDevices(activeDevices);
        }
      }
    });
  }

  @override
  List<RegisteredDevice> _mergeDevices(List<AdbDevice> activeDevices) {
    final activeMap = <String, AdbDevice>{};
    for (final device in activeDevices) {
      final existing = activeMap[device.id];
      if (existing == null ||
          (device.isOnline && !existing.isOnline) ||
          (device.isOnline == existing.isOnline &&
              existing.isHarmony &&
              !device.isHarmony)) {
        activeMap[device.id] = device;
      }
    }
    final resolvedActiveDevices = activeMap.values.toList();

    bool historyChanged = false;
    final nextHistory = List<String>.from(_historyIds);
    for (final device in resolvedActiveDevices) {
      if (!nextHistory.contains(device.id)) {
        nextHistory.add(device.id);
        historyChanged = true;
      }
    }
    if (historyChanged) {
      _historyIds = nextHistory;
      _storage.saveHistory(_historyIds);
    }

    bool modelsOrProductsChanged = false;
    for (final device in resolvedActiveDevices) {
      if (device.model != null &&
          device.model!.isNotEmpty &&
          !DeviceRegistryStorage.isGenericHarmonyModel(device.model)) {
        if (_models[device.id] != device.model) {
          _models[device.id] = device.model!;
          modelsOrProductsChanged = true;
        }
      }
      if (device.product != null && device.product!.isNotEmpty) {
        if (_products[device.id] != device.product) {
          _products[device.id] = device.product!;
          modelsOrProductsChanged = true;
        }
      }
    }
    if (modelsOrProductsChanged) {
      _storage.saveModelsAndProducts(_models, _products);
    }

    final activeIds = resolvedActiveDevices.map((d) => d.id).toSet();
    _attemptedFetchIds.removeWhere((id) => !activeIds.contains(id));

    for (final device in resolvedActiveDevices) {
      final hasSerial = _serialMap.containsKey(device.id);
      final isNet = DeviceRegistryStorage.isNetworkId(device.id);
      final hasIp =
          isNet ||
          (_ipAddresses.containsKey(device.id) &&
              _ipAddresses[device.id] != null &&
              _ipAddresses[device.id] != '-');
      final serial = _serialMap[device.id] ?? device.id;
      final hasAndroidVersion =
          _androidVersions.containsKey(device.id) ||
          _androidVersions.containsKey(serial);
      final hasSdkVersion =
          _sdkVersions.containsKey(device.id) ||
          _sdkVersions.containsKey(serial);
      final hasValidModel = _models.containsKey(device.id) &&
          !DeviceRegistryStorage.isGenericHarmonyModel(_models[device.id]);
      if (device.isOnline &&
          (!hasSerial || !hasIp || !hasAndroidVersion || !hasSdkVersion || !hasValidModel) &&
          !_pendingFetchIds.contains(device.id) &&
          !_attemptedFetchIds.contains(device.id)) {
        _pendingFetchIds.add(device.id);
        _fetchAndCacheSerial(device.id);
      }
    }

    return DeviceRegistryMerger.mergeDevices(
      activeDevices: resolvedActiveDevices,
      historyIds: _historyIds,
      aliases: _aliases,
      models: _models,
      products: _products,
      ipAddresses: _ipAddresses,
      androidVersions: _androidVersions,
      sdkVersions: _sdkVersions,
      remarks: _remarks,
      tags: _tags,
      checkedIds: _checkedIds,
      serialMap: _serialMap,
    );
  }

  /// 概览信息加载成功后触发同步更新设备注册表中的 Android 版本缓存并更新状态。
  void updateDeviceAndroidVersion(String id, String androidVersion) {
    if (androidVersion == '-' || androidVersion.isEmpty) return;

    final serial = _serialMap[id] ?? id;
    final currentVersion = _androidVersions[serial] ?? _androidVersions[id];
    final sdkVersion = DeviceRegistryStorage.parseSdkVersion(androidVersion);
    final currentSdk = _sdkVersions[serial] ?? _sdkVersions[id];
    if (currentVersion == androidVersion &&
        (sdkVersion == null || currentSdk == sdkVersion)) {
      return;
    }

    _androidVersions[id] = androidVersion;
    if (sdkVersion != null) {
      _sdkVersions[id] = sdkVersion;
    }
    if (serial != id) {
      _androidVersions[serial] = androidVersion;
      if (sdkVersion != null) {
        _sdkVersions[serial] = sdkVersion;
      }
    }

    _storage.saveAndroidVersions(_androidVersions, _sdkVersions);

    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 概览信息加载成功后触发同步更新设备注册表中的设备型号名称（供鸿蒙真实 marketing_name 回写）。
  void updateDeviceModel(String id, String modelName) {
    if (modelName.isEmpty || modelName == '-') return;
    if (DeviceRegistryStorage.isGenericHarmonyModel(modelName)) return;

    final current = _models[id];
    if (current == modelName) return;

    _models[id] = modelName;
    final serial = _serialMap[id] ?? id;
    if (serial != id) {
      _models[serial] = modelName;
    }

    _storage.saveModelsAndProducts(_models, _products);

    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 概览信息加载成功后触发同步更新设备注册表中的 IP 缓存并更新状态
  void updateDeviceIp(String id, String ip) {
    if (ip == '-' || ip.isEmpty) return;

    final currentIp = _ipAddresses[id];
    if (currentIp == ip) return;

    _ipAddresses[id] = ip;
    final serial = _serialMap[id] ?? id;
    if (serial != id) {
      _ipAddresses[serial] = ip;
    }

    _storage.saveIps(_ipAddresses);

    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 网络连接设备（ADB / HDC）
  Future<AdbResult> connectDevice(String address) async {
    final result = await DeviceRegistryActions.connectDevice(
      address: address,
      deviceActionService: ref.read(deviceActionServiceProvider),
      hdcService: ref.read(hdcServiceProvider),
    );
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  /// 断开网络设备连接
  Future<AdbResult> disconnectDevice(String address) async {
    final result = await DeviceRegistryActions.disconnectDevice(
      address: address,
      devices: state,
      deviceActionService: ref.read(deviceActionServiceProvider),
      hdcService: ref.read(hdcServiceProvider),
    );
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  /// 通过 TCP/IP 无线连接已连接 USB 的设备
  Future<AdbResult> connectWireless(
    String usbDeviceId,
    String ipAddress, [
    int port = 5555,
  ]) async {
    final result = await DeviceRegistryActions.connectWireless(
      usbDeviceId: usbDeviceId,
      ipAddress: ipAddress,
      port: port,
      devices: state,
      adbService: ref.read(adbServiceProvider),
      hdcService: ref.read(hdcServiceProvider),
    );
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  /// 主动刷新设备列表，并立即同步到设备注册表
  Future<AdbResult> refreshDevices() async {
    try {
      ref.read(adbHeartbeatControllerProvider).trigger();
      await _syncActiveDevices();
      return const AdbResult(
        exitCode: 0,
        stdout: 'Devices refreshed',
        stderr: '',
      );
    } on Object catch (error) {
      return AdbResult(exitCode: 1, stdout: '', stderr: error.toString());
    }
  }

  /// ADB 命令发现 transport 断开后，同步注册表与当前选中设备
  Future<void> syncAfterAdbResult(AdbResult result) async {
    if (!result.isDeviceDisconnected) {
      return;
    }

    await refreshDevices();

    final disconnectedDeviceId = result.disconnectedDeviceId;
    final selected = ref.read(selectedDeviceProvider);
    if (selected == null || selected.id != disconnectedDeviceId) {
      return;
    }

    for (final device in state) {
      if (device.id == selected.id) {
        ref.read(selectedDeviceProvider.notifier).select(device.toAdbDevice);
        return;
      }
    }
  }

  /// 重启 ADB 服务并刷新设备列表
  Future<AdbResult> restartAdb() async {
    final result = await ref.read(adbServiceProvider).restartServer();
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  Future<void> _refreshRegistryAfterAdbCommand() async {
    try {
      ref.read(adbHeartbeatControllerProvider).trigger();
      await _syncActiveDevices();
    } catch (_) {}
  }

  Future<void> _syncActiveDevices() async {
    _attemptedFetchIds.clear();
    final androidDevices = await ref.read(adbServiceProvider).listDevices();
    List<AdbDevice> iosDevices = [];
    try {
      iosDevices = await ref.read(iosDeviceServiceProvider).listDevices();
    } catch (_) {}
    List<AdbDevice> harmonyDevices = [];
    try {
      harmonyDevices = await ref.read(hdcServiceProvider).listDevices();
    } catch (_) {}
    final activeDevices = [...androidDevices, ...iosDevices, ...harmonyDevices];
    _lastActiveDevices = activeDevices;
    await _loadFromPrefs();
    state = _mergeDevices(activeDevices);
  }

  /// 使用配对码配对设备并自动发现端口连接
  Future<AdbResult> pairAndConnect(
    String hostWithPort,
    String pairingCode,
  ) async {
    final result = await DeviceRegistryActions.pairAndConnect(
      hostWithPort: hostWithPort,
      pairingCode: pairingCode,
      adbService: ref.read(adbServiceProvider),
      deviceActionService: ref.read(deviceActionServiceProvider),
      hdcService: ref.read(hdcServiceProvider),
    );
    await _refreshRegistryAfterAdbCommand();
    return result;
  }
}
