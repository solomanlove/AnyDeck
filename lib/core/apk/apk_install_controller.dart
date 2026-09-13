import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'apk_window_client.dart';
import 'local_apk_info.dart';

/// 安装 UI 状态与主窗口任务结果分离，成功目标不随设备下拉框改变。
class ApkInstallState {
  const ApkInstallState({
    this.selected,
    this.busy = false,
    this.installedSerial,
    this.error,
    this.warning,
  });
  final String? selected;
  final bool busy;
  final String? installedSerial;
  final String? error;
  final String? warning;
}

final apkInstallProvider = NotifierProvider.autoDispose
    .family<ApkInstallController, ApkInstallState, String>(
      ApkInstallController.new,
    );

class ApkInstallController extends Notifier<ApkInstallState> {
  ApkInstallController(this.mainWindowId);
  final String mainWindowId;
  @override
  ApkInstallState build() => const ApkInstallState();

  void select(String? serial) {
    if (state.busy) return;
    state = ApkInstallState(
      selected: serial,
      installedSerial: state.installedSerial,
    );
  }

  Future<void> install(String path, String serial, LocalApkInfo info) async {
    if (state.busy) return;
    state = ApkInstallState(selected: serial, busy: true);
    try {
      final result = await ApkWindowClient(mainWindowId).call('apk_install', {
        'requestId': '$path:${DateTime.now().microsecondsSinceEpoch}',
        'serial': serial,
        'path': path,
        'packageName': info.packageName,
        'size': info.data['size'],
        'modified': info.data['modified'],
      });
      if (!ref.mounted) return;
      state = ApkInstallState(
        selected: serial,
        installedSerial: result['success'] == true ? serial : null,
        error: result['error'] as String?,
        warning: result['warning'] as String?,
      );
    } catch (error) {
      if (ref.mounted) {
        state = ApkInstallState(selected: serial, error: error.toString());
      }
    }
  }

  Future<void> showInstalled(String packageName) async {
    final previous = state;
    if (previous.installedSerial == null || previous.busy) return;
    state = ApkInstallState(
      selected: previous.selected,
      busy: true,
      installedSerial: previous.installedSerial,
    );
    String? error;
    try {
      final result = await ApkWindowClient(mainWindowId).call(
        'apk_show_installed',
        {'serial': previous.installedSerial, 'packageName': packageName},
      );
      error = result['error'] as String?;
    } catch (e) {
      error = e.toString();
    }
    if (ref.mounted) {
      state = ApkInstallState(
        selected: previous.selected,
        installedSerial: previous.installedSerial,
        error: error,
      );
    }
  }
}

/// 单设备默认选中；多设备仅跟随有效的显式选择或主窗口选择。
String? chooseApkDevice(
  List<Map<String, dynamic>> rows,
  String? selected,
  String? preferred,
) {
  final online = rows
      .where((d) => d['online'] == true)
      .map((d) => d['id'] as String)
      .toList();
  if (selected != null) return online.contains(selected) ? selected : null;
  if (preferred != null && online.contains(preferred)) return preferred;
  return online.length == 1 ? online.single : null;
}
