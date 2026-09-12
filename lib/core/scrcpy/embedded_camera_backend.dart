import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';

import 'embedded_scrcpy_service.dart';
import 'scrcpy_camera_options.dart';

/// 可替换的内嵌摄像头会话边界，测试不调用真实传感器或启动外部窗口。
abstract class CameraBackend {
  Future<int> start();
  Future<Map<String, int>?> videoSize();
  Future<int> get exited;
  void cancel();
  Future<void> stop();
}

final cameraBackendFactoryProvider =
    Provider<CameraBackend Function(String, bool)>((ref) {
      final service = ref.watch(embeddedScrcpyServiceProvider);
      return (deviceId, front) => EmbeddedCameraBackend(
        service,
        ScrcpyCameraOptions(deviceId: deviceId, front: front),
        deviceId,
      );
    });

/// 复用内嵌服务推送、转发、原生解码及纹理注册，摄像头使用独立会话名。
class EmbeddedCameraBackend implements CameraBackend {
  EmbeddedCameraBackend(this.service, this.options, this.deviceId);
  final EmbeddedScrcpyService service;
  final ScrcpyCameraOptions options;
  final String deviceId;
  Future<int>? _starting;

  @override
  Future<int> start() {
    if (!Platform.isMacOS) {
      throw const CameraPreviewException('cameraPlatformRequired');
    }
    return _starting = service.start(deviceId: deviceId, camera: options);
  }

  @override
  Future<Map<String, int>?> videoSize() =>
      ScrcpyFlutter.getVideoSize(deviceId: options.sessionId);

  @override
  Future<int> get exited =>
      service.getServerProcess(options.sessionId)?.exitCode ?? Future.value(-1);

  @override
  void cancel() => options.cancel();

  @override
  Future<void> stop() async {
    cancel();
    await service.stop(options.sessionId);
    // 关闭页面发生在启动途中时，启动结束后再次清理，防止迟到纹理泄漏。
    try {
      await _starting;
    } catch (_) {}
    await service.stop(options.sessionId);
    await options.removeForward?.call();
  }
}
