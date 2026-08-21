import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 标识 Files Tab 当前选中的设备文件，避免不同设备或目录出现错误高亮。
class FileSelection {
  const FileSelection({required this.deviceId, required this.remotePath});

  final String deviceId;
  final String remotePath;

  bool matches(String targetDeviceId, String targetPath) {
    return deviceId == targetDeviceId && remotePath == targetPath;
  }
}

/// 管理 Files Tab 的单选状态；双击打开行为仍由现有文件导航链路处理。
class FileSelectionNotifier extends Notifier<FileSelection?> {
  @override
  FileSelection? build() => null;

  void select(String deviceId, String remotePath) {
    state = FileSelection(deviceId: deviceId, remotePath: remotePath);
  }

  void clear() {
    state = null;
  }
}

final fileSelectionProvider =
    NotifierProvider<FileSelectionNotifier, FileSelection?>(
      FileSelectionNotifier.new,
    );
