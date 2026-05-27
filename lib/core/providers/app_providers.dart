import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adb/adb_device.dart';
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
final deviceOverviewProvider = FutureProvider.autoDispose
    .family<DeviceOverview, String>((ref, deviceId) {
      return ref.watch(deviceInfoServiceProvider).loadOverview(deviceId);
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
