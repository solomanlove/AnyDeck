import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'embedded_scrcpy_service.dart';
import 'rust_device_session.dart';

/// 页面会话边界，测试可替换且不访问真实传感器。
abstract class AuxiliaryBackend {
  Future<void> start();
  Stream<String> get clipboard;
  Future<void> get exited;
  Future<void> mute(bool muted);
  Future<void> refresh();
  void cancel();
  Future<void> stop();
}

final auxiliaryBackendFactoryProvider =
    Provider<AuxiliaryBackend Function(String, bool)>((ref) {
      final adb = ref.watch(adbServiceProvider);
      final service = ref.watch(embeddedScrcpyServiceProvider);
      return (deviceId, microphone) => RustAuxiliaryBackend(
        RustDeviceSession(
          adb: adb.executable,
          deviceId: deviceId,
          resolveJar: service.extractScrcpyServerJar,
          kind: microphone ? 1 : 2,
        ),
      );
    });

/// 仅读写 FFI 会话状态，麦克风和剪贴板底层均在 Rust。
class RustAuxiliaryBackend implements AuxiliaryBackend {
  RustAuxiliaryBackend(this.session);
  final RustDeviceSession session;
  @override
  Future<void> start() => session.start();
  @override
  Stream<String> get clipboard => session.clipboard;
  @override
  Future<void> get exited => session.exited;
  @override
  Future<void> mute(bool muted) async => session.mute(muted);
  @override
  Future<void> refresh() async => session.refresh();
  @override
  void cancel() => session.cancel();
  @override
  Future<void> stop() => session.stop();
}
