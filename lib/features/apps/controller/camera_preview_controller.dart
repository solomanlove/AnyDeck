import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/embedded_camera_backend.dart';
import '../../../core/scrcpy/scrcpy_camera_options.dart';

final cameraPreviewProvider = NotifierProvider.autoDispose
    .family<CameraPreviewController, CameraPreviewState, String>(
      CameraPreviewController.new,
    );

/// 摄像头预览模式：后置、前置、前后双摄
enum CameraPreviewMode {
  back,
  front,
  dual,
}

/// 预览状态不写入持久化存储，重新打开页面不会自动启动摄像头。
class CameraPreviewState {
  CameraPreviewState({
    CameraPreviewMode? mode,
    bool? front,
    this.busy = false,
    this.textureId,
    this.width = 0,
    this.height = 0,
    this.frontTextureId,
    this.frontWidth = 0,
    this.frontHeight = 0,
    this.messageKey,
  }) : mode = mode ?? (front == true ? CameraPreviewMode.front : CameraPreviewMode.back);

  final CameraPreviewMode mode;
  final bool busy;

  /// 后置镜头（或单镜头模式下当前镜头）纹理及尺寸
  final int? textureId;
  final int width;
  final int height;

  /// 前后双摄模式下的前置镜头纹理及尺寸
  final int? frontTextureId;
  final int frontWidth;
  final int frontHeight;

  final String? messageKey;

  /// 兼容旧属性：是否为前置单镜头
  bool get front => mode == CameraPreviewMode.front;

  /// 当前是否正在推流（单摄或双摄任一纹理有效）
  bool get isStreaming => textureId != null || frontTextureId != null;
}

/// 手动预览的生命周期：停止、断线、切页和销毁均取消当前独立会话。
class CameraPreviewController extends Notifier<CameraPreviewState> {
  CameraPreviewController(this.deviceId);
  final String deviceId;
  CameraBackend? _backend;
  CameraBackend? _frontBackend;
  Timer? _sizeTimer;
  int _revision = 0;

  @override
  CameraPreviewState build() {
    ref.listen(deviceOnlineProvider(deviceId), (previous, next) {
      if (!next && (_backend != null || _frontBackend != null)) {
        unawaited(stop('cameraDisconnected'));
      }
    });
    ref.onDispose(() {
      _revision++;
      _sizeTimer?.cancel();
      final backend = _backend;
      final frontBackend = _frontBackend;
      backend?.cancel();
      frontBackend?.cancel();
      if (backend != null) unawaited(backend.stop().catchError((Object _) {}));
      if (frontBackend != null) unawaited(frontBackend.stop().catchError((Object _) {}));
    });
    return CameraPreviewState();
  }

  void selectMode(CameraPreviewMode mode) {
    if (state.busy || _backend != null || _frontBackend != null) return;
    state = CameraPreviewState(mode: mode);
  }

  void selectFront(bool front) {
    selectMode(front ? CameraPreviewMode.front : CameraPreviewMode.back);
  }

  bool _current(int revision) => ref.mounted && revision == _revision;

  Future<void> start() async {
    if (state.busy || _backend != null || _frontBackend != null) return;
    if (!ref.read(deviceOnlineProvider(deviceId))) {
      state = CameraPreviewState(
        mode: state.mode,
        messageKey: 'cameraDisconnected',
      );
      return;
    }
    final revision = ++_revision;
    final mode = state.mode;
    state = CameraPreviewState(
      mode: mode,
      busy: true,
      messageKey: 'cameraStarting',
    );
    if (mode == CameraPreviewMode.dual) {
      await _startDual(revision);
    } else {
      await _startSingle(revision, mode);
    }
  }

  Future<void> _startSingle(int revision, CameraPreviewMode mode) async {
    final front = mode == CameraPreviewMode.front;
    try {
      final backend = ref.read(cameraBackendFactoryProvider)(deviceId, front);
      _backend = backend;
      final texture = await backend.start();
      if (!_current(revision)) {
        await backend.stop();
        return;
      }
      state = CameraPreviewState(
        mode: mode,
        busy: true,
        textureId: texture,
        messageKey: 'cameraWaitingFrame',
      );
      unawaited(
        backend.exited
            .then((_) async {
              if (_current(revision)) await stop('cameraDisconnected');
            })
            .catchError((Object _) {}),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 12));
      bool reading = false;
      Future<void> readSize() async {
        if (reading || !_current(revision)) return;
        reading = true;
        try {
          final size = await backend.videoSize().timeout(
            const Duration(seconds: 3),
          );
          if (!_current(revision)) return;
          final width = size?['width'] ?? 0;
          final height = size?['height'] ?? 0;
          if (width > 0 && height > 0) {
            if (state.busy || width != state.width || height != state.height) {
              state = CameraPreviewState(
                mode: mode,
                textureId: texture,
                width: width,
                height: height,
                messageKey: 'cameraLive',
              );
            }
          } else if (state.busy && DateTime.now().isAfter(deadline)) {
            await stop('cameraStartFailed');
          }
        } catch (_) {
          if (_current(revision)) await stop('cameraStartFailed');
        } finally {
          reading = false;
        }
      }

      _sizeTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(readSize()),
      );
      await readSize();
    } catch (error) {
      if (!_current(revision)) return;
      await stop(
        error is CameraPreviewException
            ? error.messageKey
            : 'cameraStartFailed',
      );
    }
  }

  Future<void> _startDual(int revision) async {
    try {
      final backBackend = ref.read(cameraBackendFactoryProvider)(deviceId, false);
      final frontBackend = ref.read(cameraBackendFactoryProvider)(deviceId, true);
      _backend = backBackend;
      _frontBackend = frontBackend;

      final results = await Future.wait([
        backBackend.start(),
        frontBackend.start(),
      ]);
      if (!_current(revision)) {
        await Future.wait([
          backBackend.stop(),
          frontBackend.stop(),
        ]);
        return;
      }
      final backTexture = results[0];
      final frontTexture = results[1];

      state = CameraPreviewState(
        mode: CameraPreviewMode.dual,
        busy: true,
        textureId: backTexture,
        frontTextureId: frontTexture,
        messageKey: 'cameraWaitingFrame',
      );

      unawaited(
        backBackend.exited
            .then((_) async {
              if (_current(revision)) await stop('cameraDisconnected');
            })
            .catchError((Object _) {}),
      );
      unawaited(
        frontBackend.exited
            .then((_) async {
              if (_current(revision)) await stop('cameraDisconnected');
            })
            .catchError((Object _) {}),
      );

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      bool reading = false;
      var backW = 0;
      var backH = 0;
      var frontW = 0;
      var frontH = 0;

      Future<void> readSize() async {
        if (reading || !_current(revision)) return;
        reading = true;
        try {
          final sizes = await Future.wait([
            backBackend.videoSize().timeout(const Duration(seconds: 3)),
            frontBackend.videoSize().timeout(const Duration(seconds: 3)),
          ]);
          if (!_current(revision)) return;
          final backSize = sizes[0];
          final frontSize = sizes[1];
          if ((backSize?['width'] ?? 0) > 0) {
            backW = backSize!['width']!;
            backH = backSize['height']!;
          }
          if ((frontSize?['width'] ?? 0) > 0) {
            frontW = frontSize!['width']!;
            frontH = frontSize['height']!;
          }

          final hasBack = backW > 0 && backH > 0;
          final hasFront = frontW > 0 && frontH > 0;

          if (hasBack || hasFront) {
            final changed = state.busy ||
                backW != state.width ||
                backH != state.height ||
                frontW != state.frontWidth ||
                frontH != state.frontHeight;
            if (changed) {
              state = CameraPreviewState(
                mode: CameraPreviewMode.dual,
                textureId: backTexture,
                width: backW,
                height: backH,
                frontTextureId: frontTexture,
                frontWidth: frontW,
                frontHeight: frontH,
                busy: !(hasBack && hasFront),
                messageKey: 'cameraLive',
              );
            }
          } else if (state.busy && DateTime.now().isAfter(deadline)) {
            await stop('cameraStartFailed');
          }
        } catch (_) {
          if (_current(revision)) await stop('cameraStartFailed');
        } finally {
          reading = false;
        }
      }

      _sizeTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(readSize()),
      );
      await readSize();
    } catch (error) {
      if (!_current(revision)) return;
      await stop(
        error is CameraPreviewException
            ? error.messageKey
            : 'cameraStartFailed',
      );
    }
  }

  Future<void> stop([String message = 'cameraStopped']) async {
    if (state.messageKey == 'cameraStopping') return;
    final revision = ++_revision;
    _sizeTimer?.cancel();
    _sizeTimer = null;
    final backend = _backend;
    final frontBackend = _frontBackend;
    _backend = null;
    _frontBackend = null;
    backend?.cancel();
    frontBackend?.cancel();
    final mode = state.mode;
    state = CameraPreviewState(
      mode: mode,
      busy: true,
      messageKey: 'cameraStopping',
    );
    try {
      await Future.wait([
        if (backend != null) backend.stop(),
        if (frontBackend != null) frontBackend.stop(),
      ]);
    } catch (_) {
      message = 'cameraStopFailed';
    }
    if (_current(revision)) {
      state = CameraPreviewState(mode: mode, messageKey: message);
    }
  }
}
