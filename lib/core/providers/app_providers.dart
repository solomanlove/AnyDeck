import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adb/adb_device.dart';
import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import '../apps/adb_package.dart';
import '../apps/app_management_service.dart';
import '../device_actions/device_action_service.dart';
import '../device_info/device_info_service.dart';
import '../device_info/device_overview.dart';
import '../files/file_manager_service.dart';
import '../files/remote_file.dart';
import '../logcat/logcat_controller.dart';
import '../logcat/logcat_state.dart';
import '../scrcpy/scrcpy_service.dart';
import '../scrcpy/scrcpy_session.dart';
import '../terminal/adb_terminal_session.dart';
import '../emulator/emulator_service.dart';

/// 所有命令型 provider 共享的 adb 服务实例。
final adbServiceProvider = Provider<AdbService>((ref) {
  return AdbService();
});

/// 设备操作门面，负责 key event、开关和 shell 读取。
final deviceActionServiceProvider = Provider<DeviceActionService>((ref) {
  return DeviceActionService(ref.watch(adbServiceProvider));
});

/// 应用管理门面，负责安装、卸载、启动和列表读取。
final appManagementServiceProvider = Provider<AppManagementService>((ref) {
  return AppManagementService(ref.watch(adbServiceProvider));
});

/// 远程文件管理门面，负责 adb push/pull 和目录列表。
final fileManagerServiceProvider = Provider<FileManagerService>((ref) {
  return FileManagerService(ref.watch(adbServiceProvider));
});

/// 只读设备概览服务。
final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return DeviceInfoService(ref.watch(adbServiceProvider));
});

/// scrcpy 进程管理器，provider 销毁时会停止所有会话。
final scrcpyServiceProvider = Provider<ScrcpyService>((ref) {
  final service = ScrcpyService();
  ref.onDispose(service.stopAll);
  return service;
});

/// 自动轮询的实时 adb 设备列表。
final devicesProvider = StreamProvider.autoDispose<List<AdbDevice>>((ref) {
  return ref.watch(adbServiceProvider).trackDevices();
});

/// 单台设备的已安装应用列表。
final packagesProvider = FutureProvider.autoDispose
    .family<List<AdbPackage>, String>((ref, deviceId) {
      return ref.watch(appManagementServiceProvider).listPackages(deviceId);
    });

/// 单台设备的手机信息概览。
final deviceOverviewProvider = StreamProvider.autoDispose
    .family<DeviceOverview, String>((ref, deviceId) async* {
      // 保持 Provider 活跃，防止 tab 切换时销毁重建导致重新 loading
      ref.keepAlive();

      final service = ref.watch(deviceInfoServiceProvider);

      // 1. 优先尝试从本地持久化缓存加载，以实现零延迟即时展示
      final cached = await service.loadFromCache(deviceId);
      if (cached != null) {
        yield cached;
      }

      // 2. 执行 ADB 查询获取最新设备信息并更新
      final fresh = await service.loadOverview(deviceId);
      yield fresh;
    });

/// 按设备和路径缓存的远程目录内容。
final remoteFilesProvider = FutureProvider.autoDispose
    .family<List<RemoteFile>, RemoteDirectoryRequest>((ref, request) {
      return ref
          .watch(fileManagerServiceProvider)
          .listFiles(request.deviceId, request.path);
    });

/// 文件浏览器当前远程路径。
final remotePathProvider = NotifierProvider<RemotePathNotifier, String>(
  RemotePathNotifier.new,
);

/// Logcat 进程控制器和可见日志状态。
final logcatControllerProvider =
    NotifierProvider<LogcatController, LogcatState>(LogcatController.new);

/// 当前选中的 dashboard 工具 tab 下标。
final selectedToolTabProvider = NotifierProvider<ToolTabNotifier, int>(
  ToolTabNotifier.new,
);

/// workspace 面板当前选中的 adb 设备。
final selectedDeviceProvider =
    NotifierProvider<SelectedDeviceNotifier, AdbDevice?>(
      SelectedDeviceNotifier.new,
    );

/// 以生成的 session id 为 key 的活跃 scrcpy 会话。
final scrcpySessionsProvider =
    NotifierProvider<ScrcpySessionsNotifier, Map<String, ScrcpySession>>(
      ScrcpySessionsNotifier.new,
    );

/// 保存当前选中的设备。
class SelectedDeviceNotifier extends Notifier<AdbDevice?> {
  @override
  AdbDevice? build() => null;

  /// 从左侧设备列表中选择设备。
  void select(AdbDevice device) {
    state = device;
  }

  /// 清空选择，使 workspace 不展示具体设备。
  void clear() {
    state = null;
  }
}

/// 在 Riverpod 状态中跟踪 scrcpy 会话，供 dashboard 渲染。
class ScrcpySessionsNotifier extends Notifier<Map<String, ScrcpySession>> {
  @override
  Map<String, ScrcpySession> build() => {};

  /// 添加新启动的 scrcpy 会话。
  void add(ScrcpySession session) {
    state = {...state, session.id: session};
  }

  /// 背后进程停止后移除对应会话。
  void removeAll(Iterable<String> sessionIds) {
    final next = Map<String, ScrcpySession>.of(state);
    for (final id in sessionIds) {
      next.remove(id);
    }
    state = next;
  }
}

/// 保存当前工具 tab，避免响应式布局重建时丢失选择。
class ToolTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// 按 TabBar 下标选择 tab。
  void select(int index) {
    state = index;
  }
}

/// 维护文件浏览器当前远程目录。
class RemotePathNotifier extends Notifier<String> {
  @override
  String build() => '/sdcard/';

  /// 打开当前路径下的子目录。
  void open(String folderName) {
    state = _join(state, folderName);
  }

  /// 返回父目录，但不离开 `/sdcard/` 根路径。
  void back() {
    if (state == '/sdcard/') {
      return;
    }
    final normalized = state.endsWith('/')
        ? state.substring(0, state.length - 1)
        : state;
    final parent = normalized.substring(0, normalized.lastIndexOf('/') + 1);
    state = parent.isEmpty ? '/sdcard/' : parent;
  }

  /// 替换当前路径，并规范化为斜杠结尾。
  void setPath(String path) {
    state = path.endsWith('/') ? path : '$path/';
  }

  /// 使用 Android 风格正斜杠拼接远程路径片段。
  String _join(String base, String child) {
    final normalizedBase = base.endsWith('/') ? base : '$base/';
    return '$normalizedBase$child/';
  }
}

/// 目录列表 FutureProvider family 使用的 key 对象。
class RemoteDirectoryRequest {
  const RemoteDirectoryRequest({required this.deviceId, required this.path});

  final String deviceId;
  final String path;

  @override
  bool operator ==(Object other) {
    return other is RemoteDirectoryRequest &&
        other.deviceId == deviceId &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(deviceId, path);
}

/// Combined device registry model.
class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    this.customName,
    required this.status,
    this.model,
    this.product,
    this.transportId,
    required this.isOnline,
    this.isChecked = false,
    this.connections = const [],
  });

  final String id;
  final String? customName;
  final String status;
  final String? model;
  final String? product;
  final String? transportId;
  final bool isOnline;
  final bool isChecked;
  final List<String> connections;

  bool get isNetwork => id.contains(':') || id.contains('.') || id == '127.0.0.1';

  String get displayName {
    if (customName != null && customName!.isNotEmpty) {
      return customName!;
    }
    if (model != null && model!.isNotEmpty) {
      return model!.replaceAll('_', ' ');
    }
    return id;
  }

  String get connectionMethodDisplay {
    final activeConns = connections.isEmpty ? [id] : connections;
    final displays = activeConns.map((connId) {
      if (connId.contains('_adb-tls-connect')) {
        return '无线 (mDNS)';
      } else if (connId.contains(':') || connId.contains('.') || connId == '127.0.0.1') {
        final ipPattern = RegExp(r'^(\d+\.\d+\.\d+\.\d+)(:\d+)?$');
        final match = ipPattern.firstMatch(connId);
        if (match != null) {
          return '无线 (${match.group(1)})';
        }
        return '无线 ($connId)';
      } else {
        return 'USB';
      }
    }).toSet().toList();
    return displays.join(' / ');
  }

  AdbDevice get toAdbDevice => AdbDevice(
        id: id,
        status: status,
        model: model,
        product: product,
        transportId: transportId,
      );

  RegisteredDevice copyWith({
    String? id,
    String? customName,
    String? status,
    String? model,
    String? product,
    String? transportId,
    bool? isOnline,
    bool? isChecked,
    List<String>? connections,
  }) {
    return RegisteredDevice(
      id: id ?? this.id,
      customName: customName ?? this.customName,
      status: status ?? this.status,
      model: model ?? this.model,
      product: product ?? this.product,
      transportId: transportId ?? this.transportId,
      isOnline: isOnline ?? this.isOnline,
      isChecked: isChecked ?? this.isChecked,
      connections: connections ?? this.connections,
    );
  }
}

/// Global device registry provider.
final deviceRegistryProvider =
    NotifierProvider<DeviceRegistryNotifier, List<RegisteredDevice>>(
  DeviceRegistryNotifier.new,
);

class DeviceRegistryNotifier extends Notifier<List<RegisteredDevice>> {
  static const _historyKey = 'devices.history';
  static const _aliasesKey = 'devices.aliases';

  List<String> _historyIds = [];
  Map<String, String> _aliases = {};
  Set<String> _checkedIds = {};
  Map<String, String> _serialMap = {};
  List<AdbDevice> _lastActiveDevices = [];
  final Set<String> _pendingFetchIds = {};
  bool _isDisposed = false;

  bool _isNetworkId(String id) {
    return id.contains(':') || id.contains('.') || id == '127.0.0.1';
  }

  String _getFallbackSerial(String id) {
    if (id.startsWith('adb-') && id.contains('._adb-tls-connect')) {
      final namePart = id.substring(4, id.indexOf('._adb-tls-connect'));
      if (namePart.contains('-')) {
        final lastIndex = namePart.lastIndexOf('-');
        return namePart.substring(0, lastIndex);
      }
      return namePart;
    }
    return id;
  }

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
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    final aliasesJson = prefs.getString(_aliasesKey);
    Map<String, String> aliases = {};
    if (aliasesJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(aliasesJson));
        aliases = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    _historyIds = history;
    _aliases = aliases;

    // 加载缓存的序列号映射
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    _lastActiveDevices = activeDevices;
    final allIds = {...history, ...activeDevices.map((d) => d.id)};
    final serialMap = <String, String>{};
    for (final id in allIds) {
      if (!_isNetworkId(id)) {
        serialMap[id] = id;
      } else {
        var serial = _getFallbackSerial(id);
        if (serial != id) {
          serialMap[id] = serial;
        }

        final jsonStr = prefs.getString('devices.overview.$id');
        if (jsonStr != null) {
          try {
            final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
            final cachedSerial = decoded['serial']?.toString();
            if (cachedSerial != null && cachedSerial.isNotEmpty && cachedSerial != '-') {
              serialMap[id] = cachedSerial;
            }
          } catch (_) {}
        }
      }
    }
    _serialMap = serialMap;

    state = _mergeDevices(activeDevices);
  }

  void _fetchAndCacheSerial(String id) {
    Future.microtask(() async {
      try {
        final adb = ref.read(adbServiceProvider);
        // Try shell getprop ro.serialno first as it returns the real hardware serial number for wireless/network devices.
        var result = await adb.shellArgs(id, ['getprop', 'ro.serialno']);
        if (_isDisposed) return;

        var serial = result.isSuccess ? result.stdout.trim() : '';
        if (serial.isEmpty || serial == 'unknown' || serial == '-') {
          final bootResult = await adb.shellArgs(id, ['getprop', 'ro.boot.serialno']);
          if (_isDisposed) return;
          serial = bootResult.isSuccess ? bootResult.stdout.trim() : '';
        }

        if (serial.isEmpty || serial == 'unknown' || serial == '-') {
          final getSerialResult = await adb.run(['-s', id, 'get-serialno']);
          if (_isDisposed) return;
          serial = getSerialResult.isSuccess ? getSerialResult.stdout.trim() : '';
        }

        if (serial.isNotEmpty && serial != 'unknown' && serial != '-') {
          _serialMap[id] = serial;

          final prefs = await SharedPreferences.getInstance();
          final cacheKey = 'devices.overview.$id';
          final existingJson = prefs.getString(cacheKey);
          DeviceOverview overview;
          if (existingJson != null) {
            try {
              final decoded = jsonDecode(existingJson) as Map<String, dynamic>;
              overview = DeviceOverview.fromJson(decoded).copyWith(serial: serial);
            } catch (_) {
              overview = DeviceOverview(
                name: id, brand: '-', model: '-', serial: serial,
                androidVersion: '-', kernelVersion: '-', processor: '-',
                storage: '-', memory: '-', physicalResolution: '-',
                resolution: '-', logicalDensity: '-', refreshRate: '-',
                fontScale: '-', wifi: '-', ipAddress: '-',
                macAddress: '-',
              );
            }
          } else {
            overview = DeviceOverview(
              name: id, brand: '-', model: '-', serial: serial,
              androidVersion: '-', kernelVersion: '-', processor: '-',
              storage: '-', memory: '-', physicalResolution: '-',
              resolution: '-', logicalDensity: '-', refreshRate: '-',
              fontScale: '-', wifi: '-', ipAddress: '-',
              macAddress: '-',
            );
          }
          await prefs.setString(cacheKey, jsonEncode(overview.toJson()));
        } else {
          _serialMap[id] = id;
        }
      } catch (_) {
        _serialMap[id] = id;
      } finally {
        _pendingFetchIds.remove(id);
        if (!_isDisposed) {
          final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
          state = _mergeDevices(activeDevices);
        }
      }
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _historyIds);
  }

  Future<void> _saveAliases() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aliasesKey, jsonEncode(_aliases));
  }

  List<RegisteredDevice> _mergeDevices(List<AdbDevice> activeDevices) {
    final activeMap = {for (final d in activeDevices) d.id: d};

    bool historyChanged = false;
    final nextHistory = List<String>.from(_historyIds);
    for (final device in activeDevices) {
      if (!nextHistory.contains(device.id)) {
        nextHistory.add(device.id);
        historyChanged = true;
      }
    }
    if (historyChanged) {
      _historyIds = nextHistory;
      _saveHistory();
    }

    // 触发获取新在线无线设备的序列号
    for (final device in activeDevices) {
      if (device.isOnline && !_serialMap.containsKey(device.id) && !_pendingFetchIds.contains(device.id)) {
        _pendingFetchIds.add(device.id);
        _fetchAndCacheSerial(device.id);
      }
    }

    final allCandidates = <RegisteredDevice>[];
    for (final id in _historyIds) {
      final active = activeMap[id];
      final customName = _aliases[id];
      final isChecked = _checkedIds.contains(id);

      if (active != null) {
        allCandidates.add(RegisteredDevice(
          id: id,
          customName: customName,
          status: active.status,
          model: active.model,
          product: active.product,
          transportId: active.transportId,
          isOnline: active.isOnline,
          isChecked: isChecked,
          connections: [id],
        ));
      } else {
        allCandidates.add(RegisteredDevice(
          id: id,
          customName: customName,
          status: 'offline',
          isOnline: false,
          isChecked: isChecked,
          connections: [id],
        ));
      }
    }

    // 按序列号分组
    final groups = <String, List<RegisteredDevice>>{};
    for (final candidate in allCandidates) {
      final serial = _serialMap[candidate.id] ?? candidate.id;
      groups.putIfAbsent(serial, () => []).add(candidate);
    }

    // 每个序列号只选出一个最佳候选做代表来进行去重
    final merged = <RegisteredDevice>[];
    groups.forEach((serial, candidates) {
      if (candidates.length == 1) {
        merged.add(candidates.first);
      } else {
        // 排序规则：在线优先，USB 优先
        candidates.sort((a, b) {
          if (a.isOnline && !b.isOnline) return -1;
          if (!a.isOnline && b.isOnline) return 1;

          final aIsUsb = !a.isNetwork;
          final bIsUsb = !b.isNetwork;
          if (aIsUsb && !bIsUsb) return -1;
          if (!aIsUsb && bIsUsb) return 1;

          return a.id.compareTo(b.id);
        });

        final best = candidates.first;
        final anyChecked = candidates.any((c) => c.isChecked);
        
        String? mergedCustomName;
        for (final c in candidates) {
          if (c.customName != null && c.customName!.isNotEmpty) {
            mergedCustomName = c.customName;
            break;
          }
        }

        // When the merged device is online, we filter the connection IDs to only active (online) connections.
        // Otherwise, we show all historical offline connections.
        final connectionIds = best.isOnline
            ? candidates.where((c) => c.isOnline).map((c) => c.id).toList()
            : candidates.map((c) => c.id).toList();

        merged.add(best.copyWith(
          isChecked: anyChecked,
          customName: mergedCustomName,
          connections: connectionIds,
        ));
      }
    });

    return merged;
  }

  Future<void> setAlias(String id, String alias) async {
    final serial = _serialMap[id] ?? id;
    final idsToAlias = _serialMap.entries
        .where((entry) => entry.value == serial)
        .map((entry) => entry.key)
        .toList();
    if (idsToAlias.isEmpty) {
      idsToAlias.add(id);
    }

    for (final aliasId in idsToAlias) {
      if (alias.trim().isEmpty) {
        _aliases.remove(aliasId);
      } else {
        _aliases[aliasId] = alias.trim();
      }
    }
    await _saveAliases();
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  Future<void> removeDevice(String id) {
    return _removeDevices({id});
  }

  Future<void> removeCheckedDevices() {
    final checkedDeviceIds = state
        .where((device) => device.isChecked)
        .map((device) => device.id)
        .toSet();
    return _removeDevices(checkedDeviceIds);
  }

  Future<void> _removeDevices(Set<String> ids) async {
    if (ids.isEmpty) {
      return;
    }

    final idsToRemove = <String>{};
    for (final id in ids) {
      final serial = _serialMap[id] ?? id;
      final sameSerialIds = _serialMap.entries
          .where((entry) => entry.value == serial)
          .map((entry) => entry.key)
          .toSet();
      if (sameSerialIds.isEmpty) {
        idsToRemove.add(id);
      } else {
        idsToRemove.addAll(sameSerialIds);
      }
    }

    for (final removeId in idsToRemove) {
      final isNetwork = removeId.contains(':') || removeId.contains('.') || removeId == '127.0.0.1';
      if (isNetwork) {
        await disconnectDevice(removeId);
      }

      final selected = ref.read(selectedDeviceProvider);
      if (selected != null && selected.id == removeId) {
        ref.read(selectedDeviceProvider.notifier).clear();
      }

      _historyIds.remove(removeId);
      _checkedIds.remove(removeId);
      _aliases.remove(removeId);
    }

    await _saveHistory();
    await _saveAliases();

    var activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    activeDevices = activeDevices.where((d) => !idsToRemove.contains(d.id)).toList();
    state = _mergeDevices(activeDevices);
  }

  void toggleCheck(String id) {
    final serial = _serialMap[id] ?? id;
    final idsToToggle = _serialMap.entries
        .where((entry) => entry.value == serial)
        .map((entry) => entry.key)
        .toSet();
    if (idsToToggle.isEmpty) {
      idsToToggle.add(id);
    }

    final isRepresentativeChecked = _checkedIds.contains(id);
    for (final toggleId in idsToToggle) {
      if (isRepresentativeChecked) {
        _checkedIds.remove(toggleId);
      } else {
        _checkedIds.add(toggleId);
      }
    }

    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  void toggleAll(bool checked) {
    if (checked) {
      final allRepresentedSerials = state.map((d) => _serialMap[d.id] ?? d.id).toSet();
      _checkedIds = _serialMap.entries
          .where((entry) => allRepresentedSerials.contains(entry.value))
          .map((entry) => entry.key)
          .toSet();
      for (final d in state) {
        _checkedIds.add(d.id);
      }
    } else {
      _checkedIds.clear();
    }
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  Future<AdbResult> connectDevice(String address) async {
    final result = await ref.read(deviceActionServiceProvider).connect(address);
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  Future<AdbResult> disconnectDevice(String address) async {
    final result = await ref.read(deviceActionServiceProvider).disconnect(address);
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  /// 主动刷新设备列表，并立即同步到设备注册表。
  Future<AdbResult> refreshDevices() async {
    try {
      await _syncActiveDevices();
      return const AdbResult(exitCode: 0, stdout: 'Devices refreshed', stderr: '');
    } on Object catch (error) {
      return AdbResult(exitCode: 1, stdout: '', stderr: error.toString());
    }
  }

  /// 重启 ADB 服务并刷新设备列表。
  Future<AdbResult> restartAdb() async {
    final result = await ref.read(adbServiceProvider).restartServer();
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  Future<void> _refreshRegistryAfterAdbCommand() async {
    try {
      await _syncActiveDevices();
    } catch (_) {}
  }

  Future<void> _syncActiveDevices() async {
    final activeDevices = await ref.read(adbServiceProvider).listDevices();
    _lastActiveDevices = activeDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 使用配对码配对设备并自动发现端口连接。
  Future<AdbResult> pairAndConnect(String hostWithPort, String pairingCode) async {
    final adb = ref.read(adbServiceProvider);
    
    // 1. 执行配对
    final pairResult = await adb.run(['pair', hostWithPort, pairingCode]);
    if (!pairResult.isSuccess) {
      return pairResult;
    }
    
    // 2. 配对成功后，尝试自动发现连接端口并连接
    final ip = hostWithPort.split(':').first;
    
    // 轮询 5 次尝试发现 _adb-tls-connect 服务
    String? connectAddress;
    for (int i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final servicesResult = await adb.run(['mdns', 'services']);
      if (servicesResult.isSuccess) {
        final lines = servicesResult.stdout.split('\n');
        for (final line in lines) {
          if (line.contains('_adb-tls-connect._tcp') && line.contains(ip)) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              connectAddress = parts[2].trim();
              break;
            }
          }
        }
      }
      if (connectAddress != null) {
        break;
      }
    }
    
    // 3. 执行连接
    final addressToConnect = connectAddress ?? '$ip:5555';
    final connectResult = await connectDevice(addressToConnect);
    
    return AdbResult(
      exitCode: connectResult.exitCode,
      stdout: 'Successfully paired to $hostWithPort. Connection result: ${connectResult.message}',
      stderr: connectResult.stderr,
    );
  }
}

/// 终端调试会话列表（按设备划分）
final adbTerminalProvider = NotifierProvider<AdbTerminalNotifier, AdbTerminalState>(
  AdbTerminalNotifier.new,
);

/// 收藏调试命令
final favoriteCommandsProvider = NotifierProvider<FavoriteCommandsNotifier, List<FavoriteCommand>>(
  FavoriteCommandsNotifier.new,
);

/// 模拟器底层服务实例。
final emulatorServiceProvider = Provider<EmulatorService>((ref) {
  return EmulatorService();
});

/// 可用 AVD 模拟器名称列表。
final emulatorListProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.watch(emulatorServiceProvider).listEmulators();
});

/// 正在启动的模拟器集合状态。
class StartingEmulatorsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void start(String name) {
    state = {...state, name};
  }

  void stopStarting(String name) {
    state = state.where((n) => n != name).toSet();
  }

  void setStarting(Set<String> next) {
    state = next;
  }
}

final startingEmulatorsProvider = NotifierProvider<StartingEmulatorsNotifier, Set<String>>(
  StartingEmulatorsNotifier.new,
);

/// 当前正在运行的模拟器，以 map 形式提供：AVD名称 -> 对应的设备ID。
final runningEmulatorsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final devicesAsync = ref.watch(devicesProvider);
  final devices = devicesAsync.value ?? [];
  final adb = ref.read(adbServiceProvider);
  final map = <String, String>{};

  for (final device in devices) {
    if (device.isOnline) {
      try {
        var result = await adb.shellArgs(device.id, ['getprop', 'ro.boot.qemu.avd_name']);
        var avdName = result.isSuccess ? result.stdout.trim() : '';
        if (avdName.isEmpty) {
          result = await adb.shellArgs(device.id, ['getprop', 'ro.kernel.qemu.avd_name']);
          avdName = result.isSuccess ? result.stdout.trim() : '';
        }
        
        if (avdName.isNotEmpty) {
          map[avdName] = device.id;
        }
      } catch (_) {}
    }
  }

  // 如果某些处于 starting 状态的模拟器已经在 running 映射中出现，将它们从 starting 状态移除。
  final startingNotifier = ref.read(startingEmulatorsProvider.notifier);
  final starting = ref.read(startingEmulatorsProvider);
  if (starting.isNotEmpty) {
    final nextStarting = Set<String>.from(starting);
    bool changed = false;
    for (final runningAvd in map.keys) {
      if (nextStarting.contains(runningAvd)) {
        nextStarting.remove(runningAvd);
        changed = true;
      }
    }
    if (changed) {
      Future.microtask(() {
        startingNotifier.setStarting(nextStarting);
      });
    }
  }

  return map;
});
