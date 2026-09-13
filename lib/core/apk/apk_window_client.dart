import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_apk_info.dart';
import 'local_apk_service.dart';

/// 子窗口通过主引擎分发器操作设备，避免跨 Isolate 写入应用缓存。
class ApkWindowClient {
  ApkWindowClient(this.mainWindowId);
  final String mainWindowId;
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final value = await WindowController.fromWindowId(
      mainWindowId,
    ).invokeMethod<dynamic>(method, args);
    return Map<String, dynamic>.from(value as Map);
  }
}

final localApkProvider = FutureProvider.autoDispose
    .family<LocalApkInfo, String>((ref, path) {
      final service = LocalApkService();
      ref.onDispose(service.dispose);
      return service.inspect(path);
    });

/// 生命周期跟随窗口；轮询只获取主窗口设备快照，不写入本地设备状态。
final apkDevicesProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async* {
      var active = true;
      ref.onDispose(() => active = false);
      final client = ApkWindowClient(id);
      while (active) {
        try {
          final snapshot = await client
              .call('apk_devices')
              .timeout(const Duration(seconds: 15));
          if (active) yield snapshot;
        } catch (error) {
          if (active) yield {'devices': <dynamic>[], 'error': error.toString()};
        }
        if (active) await Future<void>.delayed(const Duration(seconds: 3));
      }
    });
