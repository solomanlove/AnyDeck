import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../providers/app_providers.dart';
import 'rust_device_session.dart';

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
      final adb = ref.watch(adbServiceProvider);
      return (deviceId, front) => RustCameraBackend(
        RustDeviceSession(
          adb: adb.executable,
          deviceId: deviceId,
          resolveJar: service.extractScrcpyServerJar,
          kind: front ? 3 : 0,
        ),
      );
    });

/// 摄像头控制/ADB/解码在 Rust，Swift 仅为 Flutter 注册 CVPixelBuffer Texture。
class RustCameraBackend implements CameraBackend {
  RustCameraBackend(this.session);
  final RustDeviceSession session;
  static const _textures = MethodChannel('anydeck/rust_texture');
  static const _virtualCamera = MethodChannel('anydeck/virtual_camera');
  int? _texture;
  int? _previewLease;
  Future<int>? _starting;
  Future<void>? _stopping;
  bool _cancelled = false;

  @override
  Future<int> start() => _starting = _start();
  Future<int> _start() async {
    if (!Platform.isMacOS) {
      throw const CameraPreviewException('cameraPlatformRequired');
    }
    // 原生租约跨 Engine 防止本地预览和会议采集抢占同设备镜头。
    await _acquirePreview();
    if (_cancelled) throw const CameraPreviewException('cameraStopped');
    await session.start();
    if (_cancelled) throw const CameraPreviewException('cameraStopped');
    final registering = _textures.invokeMethod<int>('register', {
      'handle': session.handle,
    });
    unawaited(
      registering
          .then((texture) async {
            if (_cancelled && texture != null) {
              await _textures.invokeMethod<void>('unregister', {
                'textureId': texture,
              });
            }
          })
          .catchError((Object _) {}),
    );
    _texture = await registering.timeout(const Duration(seconds: 3));
    if (_texture == null) {
      throw const CameraPreviewException('cameraStartFailed');
    }
    return _texture!;
  }

  @override
  Future<Map<String, int>?> videoSize() async => session.videoSize();

  Future<void> _acquirePreview() async {
    var abandoned = false;
    final acquiring = _virtualCamera.invokeMethod<int>('acquirePreview', {
      'deviceId': session.deviceId,
    });
    unawaited(acquiring.then((token) async {
      if (abandoned && token != null) await _releasePreview(token);
    }).catchError((Object _) {}));
    try {
      _previewLease = await acquiring.timeout(const Duration(seconds: 3),
        onTimeout: () {
          abandoned = true;
          throw const CameraPreviewException('virtualCameraPreviewBlocked');
        });
    } on MissingPluginException {
      // 兼容尚未接入此原生插件的旧构建和假通道测试。
    } on PlatformException {
      throw const CameraPreviewException('virtualCameraPreviewBlocked');
    }
  }

  Future<void> _releasePreview(int token) async {
    try {
      await _virtualCamera.invokeMethod<void>('releasePreview', {'token': token})
          .timeout(const Duration(seconds: 3));
    } on MissingPluginException {
      // 旧插件无租约，真实 Engine 销毁路径由原生兜底释放。
    }
  }
  @override
  Future<int> get exited => session.exited.then((_) => 0);
  @override
  void cancel() {
    _cancelled = true;
    session.cancel();
  }

  @override
  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    cancel();
    try {
      await _starting;
    } catch (_) {}
    try {
      if (_texture != null) {
        await _textures
            .invokeMethod<void>('unregister', {'textureId': _texture})
            .timeout(const Duration(seconds: 3));
      }
    } finally {
      try {
        await session.stop();
      } finally {
        final lease = _previewLease;
        _previewLease = null;
        if (lease != null) await _releasePreview(lease);
      }
    }
  }
}
