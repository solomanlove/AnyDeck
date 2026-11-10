import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'embedded_scrcpy_service.dart';
import 'rust_host_recording.dart';

/// 无窗口电脑录制边界；stop 完成意味着 MP4 已收尾，失败必须抛出。
abstract class HostRecordingBackend {
  Future<void> start();
  Future<void> stop();
  void cancel();

  /// 异常结束返回错误，正常停止返回 null；不会产生无人处理的 Future error。
  Future<String?> get exited;
}

/// 两个录制入口共用工厂，测试可替换，不需要真实设备或 Rust 动态库。
final hostRecordingFactoryProvider =
    Provider<HostRecordingBackend Function(String, String)>((ref) {
      final adb = ref.watch(adbServiceProvider);
      final server = ref.watch(embeddedScrcpyServiceProvider);
      return (deviceId, path) => RustHostRecording(
        adb: adb.executable,
        deviceId: deviceId,
        path: path,
        resolveJar: server.extractScrcpyServerJar,
      );
    });
