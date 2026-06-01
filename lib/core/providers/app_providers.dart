import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adb/adb_device.dart';
import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import '../apps/adb_package.dart';
import '../apps/app_management_service.dart';
import '../apps/app_permission_service.dart';
import '../device_actions/device_action_service.dart';
import '../device_info/device_info_service.dart';
import '../device_info/device_overview.dart';
import '../emulator/android_emulator.dart';
import '../files/file_manager_service.dart';
import '../layout_inspector/layout_inspector_service.dart';
import '../files/remote_file.dart';
import '../logcat/logcat_controller.dart';
import '../logcat/logcat_state.dart';
import '../scrcpy/scrcpy_service.dart';
import '../scrcpy/scrcpy_session.dart';
import '../terminal/adb_terminal_session.dart';
import '../terminal/favorite_commands.dart';
import '../emulator/emulator_service.dart';
import '../process/host_platform_service.dart';
import '../process/process_service.dart';
import '../web_debug/webpage_target.dart';
import '../web_debug/web_debug_service.dart';

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

/// 应用权限管理门面，负责查询、授予和撤销应用权限。
final appPermissionServiceProvider = Provider<AppPermissionService>((ref) {
  return AppPermissionService(ref.watch(adbServiceProvider));
});

/// 远程文件管理门面，负责 adb push/pull 和目录列表。
final fileManagerServiceProvider = Provider<FileManagerService>((ref) {
  return FileManagerService(ref.watch(adbServiceProvider));
});

/// 只读设备概览服务。
final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return DeviceInfoService(ref.watch(adbServiceProvider));
});

/// 布局分析服务，负责抓取 `uiautomator` XML 和屏幕截图。
final layoutInspectorServiceProvider = Provider<LayoutInspectorService>((ref) {
  return LayoutInspectorService(ref.watch(adbServiceProvider));
});

/// scrcpy 进程管理器，provider 销毁时会停止所有会话。
final scrcpyServiceProvider = Provider<ScrcpyService>((ref) {
  final service = ScrcpyService();
  ref.onDispose(service.stopAll);
  return service;
});

/// 进程管理门面，负责查询和结束进程。
final processServiceProvider = Provider<ProcessService>((ref) {
  return ProcessService(ref.watch(adbServiceProvider));
});

/// 宿主机系统平台服务，负责处理与宿主机 OS 交互的操作。
final hostPlatformServiceProvider = Provider<HostPlatformService>((ref) {
  return HostPlatformService();
});

/// 单台设备的当前运行进程列表。
final processesProvider = FutureProvider.autoDispose
    .family<List<AdbProcess>, String>((ref, deviceId) {
      return ref.watch(processServiceProvider).getProcesses(deviceId);
    });

/// 网页调试服务。
final webDebugServiceProvider = Provider<WebDebugService>((ref) {
  return WebDebugService(ref.watch(adbServiceProvider));
});

/// 单台设备的运行网页调试目标列表。
final webTargetsProvider = FutureProvider.autoDispose
    .family<List<WebpageTarget>, String>((ref, deviceId) async {
      final service = ref.watch(webDebugServiceProvider);
      await Future<void>.delayed(Duration.zero);
      return service.scanTargets(deviceId);
    });

/// 选中的网页目标。
final selectedWebTargetProvider =
    NotifierProvider<SelectedWebTargetNotifier, WebpageTarget?>(
      SelectedWebTargetNotifier.new,
    );

class SelectedWebTargetNotifier extends Notifier<WebpageTarget?> {
  @override
  WebpageTarget? build() => null;

  @override
  set state(WebpageTarget? value) => super.state = value;
}

/// 是否使用本地调试器。
final useLocalDebuggerProvider =
    NotifierProvider<UseLocalDebuggerNotifier, bool>(
      UseLocalDebuggerNotifier.new,
    );

class UseLocalDebuggerNotifier extends Notifier<bool> {
  static const _key = 'web_debug.use_local_debugger';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    final next = !state;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, next);
  }
}

/// 自动轮询的实时 adb 设备列表。
final devicesProvider = StreamProvider.autoDispose<List<AdbDevice>>((ref) {
  return ref.watch(adbServiceProvider).trackDevices();
});

/// 单台设备的已安装应用列表。
final packagesProvider = NotifierProvider.autoDispose
    .family<PackagesNotifier, AsyncValue<List<AdbPackage>>, String>(
      PackagesNotifier.new,
    );

class PackagesNotifier extends Notifier<AsyncValue<List<AdbPackage>>> {
  final String deviceId;
  PackagesNotifier(this.deviceId);

  @override
  AsyncValue<List<AdbPackage>> build() {
    _load();
    return const AsyncValue.loading();
  }

  Future<void> _load() async {
    var isDisposed = false;
    ref.onDispose(() => isDisposed = true);

    try {
      final service = ref.read(appManagementServiceProvider);
      final initialPackages = await service.listPackages(deviceId);
      if (isDisposed) return;
      state = AsyncValue.data(initialPackages);

      await for (final updatedPackages in service.enrichPackagesWithIconsProgressive(deviceId, initialPackages)) {
        if (isDisposed) return;
        state = AsyncValue.data(updatedPackages);
      }
    } catch (err, stack) {
      if (!isDisposed) {
        state = AsyncValue.error(err, stack);
      }
    }
  }
}

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

/// 单台设备的 adb shell 是否拥有 root 权限。
final isDeviceRootProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, deviceId) async {
      final adb = ref.watch(adbServiceProvider);
      try {
        final result = await adb.shell(deviceId, 'id');
        if (result.isSuccess) {
          return result.stdout.contains('uid=0');
        }
      } catch (_) {}
      return false;
    });

/// 离线设备的本地手机信息概览缓存。
final cachedDeviceOverviewProvider = FutureProvider.autoDispose
    .family<DeviceOverview?, String>((ref, deviceId) {
      return ref.watch(deviceInfoServiceProvider).loadFromCache(deviceId);
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

/// 文件浏览器高级导航状态。
final fileNavigationProvider =
    NotifierProvider<FileNavigationNotifier, FileNavigationState>(
      FileNavigationNotifier.new,
    );

/// 文件列表搜索过滤。
final fileFilterQueryProvider =
    NotifierProvider<FileFilterQueryNotifier, String>(
      FileFilterQueryNotifier.new,
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

/// 用户是否手动清空了选中的设备（例如点击了 logo）
final userClearedDeviceSelectionProvider =
    NotifierProvider<UserClearedDeviceSelectionNotifier, bool>(
      UserClearedDeviceSelectionNotifier.new,
    );

class UserClearedDeviceSelectionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

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
    final old = state;
    if (old != null && old.id != device.id) {
      ref.read(webDebugServiceProvider).removeForwards(old.id);
    }
    state = device;
  }

  /// 清空选择，使 workspace 不展示具体设备。
  void clear() {
    final old = state;
    if (old != null) {
      ref.read(webDebugServiceProvider).removeForwards(old.id);
    }
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

/// 文件导航状态。
class FileNavigationState {
  const FileNavigationState({
    required this.currentPath,
    required this.history,
    required this.historyIndex,
    this.isEditingPath = false,
    this.showHiddenFiles = false,
    this.isGridView = false,
    this.sortColumn = 'name',
    this.sortAscending = true,
  });

  final String currentPath;
  final List<String> history;
  final int historyIndex;
  final bool isEditingPath;
  final bool showHiddenFiles;
  final bool isGridView;
  final String sortColumn;
  final bool sortAscending;

  bool get canGoBack => historyIndex > 0;
  bool get canGoForward => historyIndex < history.length - 1;

  FileNavigationState copyWith({
    String? currentPath,
    List<String>? history,
    int? historyIndex,
    bool? isEditingPath,
    bool? showHiddenFiles,
    bool? isGridView,
    String? sortColumn,
    bool? sortAscending,
  }) {
    return FileNavigationState(
      currentPath: currentPath ?? this.currentPath,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      isEditingPath: isEditingPath ?? this.isEditingPath,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      isGridView: isGridView ?? this.isGridView,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}

/// 维护高级文件浏览器导航状态。
class FileNavigationNotifier extends Notifier<FileNavigationState> {
  @override
  FileNavigationState build() {
    const initialPath = '/';
    return const FileNavigationState(
      currentPath: initialPath,
      history: [initialPath],
      historyIndex: 0,
    );
  }

  void navigateTo(String path) {
    final normalized = _normalize(path);
    if (state.currentPath == normalized) return;

    final newHistory = state.history.sublist(0, state.historyIndex + 1);
    newHistory.add(normalized);

    state = state.copyWith(
      currentPath: normalized,
      history: newHistory,
      historyIndex: newHistory.length - 1,
      isEditingPath: false,
    );
  }

  void goBack() {
    if (!state.canGoBack) return;
    final newIndex = state.historyIndex - 1;
    state = state.copyWith(
      currentPath: state.history[newIndex],
      historyIndex: newIndex,
      isEditingPath: false,
    );
  }

  void goForward() {
    if (!state.canGoForward) return;
    final newIndex = state.historyIndex + 1;
    state = state.copyWith(
      currentPath: state.history[newIndex],
      historyIndex: newIndex,
      isEditingPath: false,
    );
  }

  void goUp() {
    final path = state.currentPath;
    if (path == '/') return;

    final normalized = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final lastSlash = normalized.lastIndexOf('/');
    final parent = lastSlash == 0
        ? '/'
        : normalized.substring(0, lastSlash + 1);

    navigateTo(parent);
  }

  void setEditingPath(bool editing) {
    state = state.copyWith(isEditingPath: editing);
  }

  void toggleShowHiddenFiles() {
    state = state.copyWith(showHiddenFiles: !state.showHiddenFiles);
  }

  void setGridView(bool gridView) {
    state = state.copyWith(isGridView: gridView);
  }

  void toggleSort(String column) {
    if (state.sortColumn == column) {
      state = state.copyWith(sortAscending: !state.sortAscending);
    } else {
      state = state.copyWith(sortColumn: column, sortAscending: true);
    }
  }

  void setSort(String column, bool ascending) {
    state = state.copyWith(sortColumn: column, sortAscending: ascending);
  }

  String _normalize(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) {
      p = '/$p';
    }
    return p.endsWith('/') ? p : '$p/';
  }
}

/// 维护文件浏览器当前远程目录（兼容层，桥接到 fileNavigationProvider）。
class RemotePathNotifier extends Notifier<String> {
  @override
  String build() {
    return ref.watch(fileNavigationProvider).currentPath;
  }

  /// 打开当前路径下的子目录。
  void open(String folderName) {
    ref
        .read(fileNavigationProvider.notifier)
        .navigateTo(_join(state, folderName));
  }

  /// 返回父目录。
  void back() {
    ref.read(fileNavigationProvider.notifier).goUp();
  }

  /// 替换当前路径。
  void setPath(String path) {
    ref.read(fileNavigationProvider.notifier).navigateTo(path);
  }

  String _join(String base, String child) {
    final normalizedBase = base.endsWith('/') ? base : '$base/';
    return '$normalizedBase$child/';
  }
}

/// 维护文件列表过滤查询。
class FileFilterQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
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
    this.serial,
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
  final String? serial;

  bool get isNetwork =>
      id.contains(':') || id.contains('.') || id == '127.0.0.1';

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
    final name = (model != null && model!.isNotEmpty)
        ? model!.replaceAll('_', ' ')
        : id;
    if (serial != null && serial!.isNotEmpty) {
      return '$name($serial)';
    }
    return name;
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
    String? serial,
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
      serial: serial ?? this.serial,
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
  static const _modelsKey = 'devices.models';
  static const _productsKey = 'devices.products';

  List<String> _historyIds = [];
  Map<String, String> _aliases = {};
  Map<String, String> _models = {};
  Map<String, String> _products = {};
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

    final modelsJson = prefs.getString(_modelsKey);
    Map<String, String> models = {};
    if (modelsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(modelsJson));
        models = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final productsJson = prefs.getString(_productsKey);
    Map<String, String> products = {};
    if (productsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(productsJson));
        products = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    _historyIds = history;
    _aliases = aliases;
    _models = models;
    _products = products;

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
            if (cachedSerial != null &&
                cachedSerial.isNotEmpty &&
                cachedSerial != '-') {
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
          final bootResult = await adb.shellArgs(id, [
            'getprop',
            'ro.boot.serialno',
          ]);
          if (_isDisposed) return;
          serial = bootResult.isSuccess ? bootResult.stdout.trim() : '';
        }

        if (serial.isEmpty || serial == 'unknown' || serial == '-') {
          final getSerialResult = await adb.run(['-s', id, 'get-serialno']);
          if (_isDisposed) return;
          serial = getSerialResult.isSuccess
              ? getSerialResult.stdout.trim()
              : '';
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
              overview = DeviceOverview.fromJson(
                decoded,
              ).copyWith(serial: serial);
            } catch (_) {
              overview = DeviceOverview(
                name: id,
                brand: '-',
                model: '-',
                serial: serial,
                androidId: '-',
                androidVersion: '-',
                kernelVersion: '-',
                processor: '-',
                storage: '-',
                memory: '-',
                physicalResolution: '-',
                resolution: '-',
                logicalDensity: '-',
                refreshRate: '-',
                fontScale: '-',
                wifi: '-',
                wifiEnabled: false,
                ipAddress: '-',
                macAddress: '-',
                airplaneModeEnabled: false,
                mobileDataEnabled: false,
                talkbackEnabled: false,
                windowAnimationScale: '1.0',
                transitionAnimationScale: '1.0',
                animatorDurationScale: '1.0',
                rawResolution: '-',
                hwuiProfile: 'false',
                showTouchesEnabled: false,
                pointerLocationEnabled: false,
                demoModeEnabled: false,
              );
            }
          } else {
            overview = DeviceOverview(
              name: id,
              brand: '-',
              model: '-',
              serial: serial,
              androidId: '-',
              androidVersion: '-',
              kernelVersion: '-',
              processor: '-',
              storage: '-',
              memory: '-',
              physicalResolution: '-',
              resolution: '-',
              logicalDensity: '-',
              refreshRate: '-',
              fontScale: '-',
              wifi: '-',
              wifiEnabled: false,
              ipAddress: '-',
              macAddress: '-',
              airplaneModeEnabled: false,
              mobileDataEnabled: false,
              talkbackEnabled: false,
              windowAnimationScale: '1.0',
              transitionAnimationScale: '1.0',
              animatorDurationScale: '1.0',
              rawResolution: '-',
              hwuiProfile: 'false',
              showTouchesEnabled: false,
              pointerLocationEnabled: false,
              demoModeEnabled: false,
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
          final activeDevices =
              ref.read(devicesProvider).value ?? _lastActiveDevices;
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

  Future<void> _saveModelsAndProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelsKey, jsonEncode(_models));
      await prefs.setString(_productsKey, jsonEncode(_products));
    } catch (_) {}
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

    // 缓存最新获取到的在线设备 model 和 product 信息
    bool modelsOrProductsChanged = false;
    for (final device in activeDevices) {
      if (device.model != null && device.model!.isNotEmpty) {
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
      _saveModelsAndProducts();
    }

    // 触发获取新在线无线设备的序列号
    for (final device in activeDevices) {
      if (device.isOnline &&
          !_serialMap.containsKey(device.id) &&
          !_pendingFetchIds.contains(device.id)) {
        _pendingFetchIds.add(device.id);
        _fetchAndCacheSerial(device.id);
      }
    }

    final allCandidates = <RegisteredDevice>[];
    for (final id in _historyIds) {
      final active = activeMap[id];
      final customName = _aliases[id];
      final isChecked = _checkedIds.contains(id);
      final serial = _serialMap[id] ?? id;
      final cachedModel = _models[id];
      final cachedProduct = _products[id];

      if (active != null) {
        allCandidates.add(
          RegisteredDevice(
            id: id,
            customName: customName,
            status: active.status,
            model: active.model ?? cachedModel,
            product: active.product ?? cachedProduct,
            transportId: active.transportId,
            isOnline: active.isOnline,
            isChecked: isChecked,
            connections: [id],
            serial: serial,
          ),
        );
      } else {
        allCandidates.add(
          RegisteredDevice(
            id: id,
            customName: customName,
            status: 'offline',
            model: cachedModel,
            product: cachedProduct,
            isOnline: false,
            isChecked: isChecked,
            connections: [id],
            serial: serial,
          ),
        );
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

        String? mergedModel = best.model;
        if (mergedModel == null || mergedModel.isEmpty) {
          for (final c in candidates) {
            if (c.model != null && c.model!.isNotEmpty) {
              mergedModel = c.model;
              break;
            }
          }
        }

        String? mergedProduct = best.product;
        if (mergedProduct == null || mergedProduct.isEmpty) {
          for (final c in candidates) {
            if (c.product != null && c.product!.isNotEmpty) {
              mergedProduct = c.product;
              break;
            }
          }
        }

        // When the merged device is online, we filter the connection IDs to only active (online) connections.
        // Otherwise, we show all historical offline connections.
        final connectionIds = best.isOnline
            ? candidates.where((c) => c.isOnline).map((c) => c.id).toList()
            : candidates.map((c) => c.id).toList();

        merged.add(
          best.copyWith(
            isChecked: anyChecked,
            customName: mergedCustomName,
            model: mergedModel,
            product: mergedProduct,
            connections: connectionIds,
            serial: serial,
          ),
        );
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
      final isNetwork =
          removeId.contains(':') ||
          removeId.contains('.') ||
          removeId == '127.0.0.1';
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
      _models.remove(removeId);
      _products.remove(removeId);
    }

    await _saveHistory();
    await _saveAliases();
    await _saveModelsAndProducts();

    var activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    activeDevices = activeDevices
        .where((d) => !idsToRemove.contains(d.id))
        .toList();
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
      final allRepresentedSerials = state
          .map((d) => _serialMap[d.id] ?? d.id)
          .toSet();
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
    final result = await ref
        .read(deviceActionServiceProvider)
        .disconnect(address);
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  /// 主动刷新设备列表，并立即同步到设备注册表。
  Future<AdbResult> refreshDevices() async {
    try {
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

  /// ADB 命令发现 transport 断开后，同步注册表与当前选中设备。
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
  Future<AdbResult> pairAndConnect(
    String hostWithPort,
    String pairingCode,
  ) async {
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
      stdout:
          'Successfully paired to $hostWithPort. Connection result: ${connectResult.message}',
      stderr: connectResult.stderr,
    );
  }
}

/// 终端调试会话列表（按设备划分）
final adbTerminalProvider =
    NotifierProvider<AdbTerminalNotifier, AdbTerminalState>(
      AdbTerminalNotifier.new,
    );

/// 收藏调试命令
final favoriteCommandsProvider =
    NotifierProvider<FavoriteCommandsNotifier, List<FavoriteCommand>>(
      FavoriteCommandsNotifier.new,
    );

/// 模拟器底层服务实例。
final emulatorServiceProvider = Provider<EmulatorService>((ref) {
  return EmulatorService(
    hostPlatformService: ref.watch(hostPlatformServiceProvider),
  );
});

/// 可用 AVD 模拟器配置列表。
final emulatorListProvider = FutureProvider.autoDispose<List<AndroidEmulator>>((
  ref,
) async {
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

final startingEmulatorsProvider =
    NotifierProvider<StartingEmulatorsNotifier, Set<String>>(
      StartingEmulatorsNotifier.new,
    );

/// 当前正在运行的模拟器，以 map 形式提供：AVD名称 -> 对应的设备ID。
final runningEmulatorsProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
      final devicesAsync = ref.watch(devicesProvider);
      final devices = devicesAsync.value ?? [];
      final adb = ref.read(adbServiceProvider);
      final map = <String, String>{};

      for (final device in devices) {
        if (device.isOnline) {
          try {
            var result = await adb.shellArgs(device.id, [
              'getprop',
              'ro.boot.qemu.avd_name',
            ]);
            var avdName = result.isSuccess ? result.stdout.trim() : '';
            if (avdName.isEmpty) {
              result = await adb.shellArgs(device.id, [
                'getprop',
                'ro.kernel.qemu.avd_name',
              ]);
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
