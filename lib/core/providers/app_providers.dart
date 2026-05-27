import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adb/adb_device.dart';
import '../adb/adb_service.dart';
import '../apps/adb_package.dart';
import '../apps/app_management_service.dart';
import '../device_actions/device_action_service.dart';
import '../files/file_manager_service.dart';
import '../files/remote_file.dart';
import '../logcat/logcat_controller.dart';
import '../logcat/logcat_state.dart';
import '../scrcpy/scrcpy_service.dart';
import '../scrcpy/scrcpy_session.dart';

final adbServiceProvider = Provider<AdbService>((ref) {
  return AdbService();
});

final deviceActionServiceProvider = Provider<DeviceActionService>((ref) {
  return DeviceActionService(ref.watch(adbServiceProvider));
});

final appManagementServiceProvider = Provider<AppManagementService>((ref) {
  return AppManagementService(ref.watch(adbServiceProvider));
});

final fileManagerServiceProvider = Provider<FileManagerService>((ref) {
  return FileManagerService(ref.watch(adbServiceProvider));
});

final scrcpyServiceProvider = Provider<ScrcpyService>((ref) {
  final service = ScrcpyService();
  ref.onDispose(service.stopAll);
  return service;
});

final devicesProvider = StreamProvider.autoDispose<List<AdbDevice>>((ref) {
  return ref.watch(adbServiceProvider).trackDevices();
});

final packagesProvider = FutureProvider.autoDispose
    .family<List<AdbPackage>, String>((ref, deviceId) {
      return ref.watch(appManagementServiceProvider).listPackages(deviceId);
    });

final remoteFilesProvider = FutureProvider.autoDispose
    .family<List<RemoteFile>, RemoteDirectoryRequest>((ref, request) {
      return ref
          .watch(fileManagerServiceProvider)
          .listFiles(request.deviceId, request.path);
    });

final remotePathProvider = NotifierProvider<RemotePathNotifier, String>(
  RemotePathNotifier.new,
);

final logcatControllerProvider =
    NotifierProvider<LogcatController, LogcatState>(LogcatController.new);

final selectedToolTabProvider = NotifierProvider<ToolTabNotifier, int>(
  ToolTabNotifier.new,
);

final selectedDeviceProvider =
    NotifierProvider<SelectedDeviceNotifier, AdbDevice?>(
      SelectedDeviceNotifier.new,
    );

final scrcpySessionsProvider =
    NotifierProvider<ScrcpySessionsNotifier, Map<String, ScrcpySession>>(
      ScrcpySessionsNotifier.new,
    );

class SelectedDeviceNotifier extends Notifier<AdbDevice?> {
  @override
  AdbDevice? build() => null;

  void select(AdbDevice device) {
    state = device;
  }

  void clear() {
    state = null;
  }
}

class ScrcpySessionsNotifier extends Notifier<Map<String, ScrcpySession>> {
  @override
  Map<String, ScrcpySession> build() => {};

  void add(ScrcpySession session) {
    state = {...state, session.id: session};
  }

  void removeAll(Iterable<String> sessionIds) {
    final next = Map<String, ScrcpySession>.of(state);
    for (final id in sessionIds) {
      next.remove(id);
    }
    state = next;
  }
}

class ToolTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    state = index;
  }
}

class RemotePathNotifier extends Notifier<String> {
  @override
  String build() => '/sdcard/';

  void open(String folderName) {
    state = _join(state, folderName);
  }

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

  void setPath(String path) {
    state = path.endsWith('/') ? path : '$path/';
  }

  String _join(String base, String child) {
    final normalizedBase = base.endsWith('/') ? base : '$base/';
    return '$normalizedBase$child/';
  }
}

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
