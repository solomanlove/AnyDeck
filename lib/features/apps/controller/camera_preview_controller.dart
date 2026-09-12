import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/embedded_camera_backend.dart';
import '../../../core/scrcpy/scrcpy_camera_options.dart';

final cameraPreviewProvider = NotifierProvider.autoDispose
    .family<CameraPreviewController, CameraPreviewState, String>(
      CameraPreviewController.new,
    );

/// 预览状态不写入持久化存储，重新打开页面不会自动启动摄像头。
class CameraPreviewState {
  const CameraPreviewState({
    this.front = false,
    this.busy = false,
    this.textureId,
    this.width = 0,
    this.height = 0,
    this.messageKey,
  });
  final bool front;
  final bool busy;
  final int? textureId;
  final int width;
  final int height;
  final String? messageKey;
}

/// 手动预览的生命周期：停止、断线、切页和销毁均取消当前独立会话。
class CameraPreviewController extends Notifier<CameraPreviewState> {
  CameraPreviewController(this.deviceId);
  final String deviceId;
  CameraBackend? _backend;
  Timer? _sizeTimer;
  int _revision = 0;

  @override
  CameraPreviewState build() {
    ref.listen(deviceOnlineProvider(deviceId), (previous, next) {
      if (!next && _backend != null) unawaited(stop('cameraDisconnected'));
    });
    ref.onDispose(() {
      _revision++;
      _sizeTimer?.cancel();
      final backend = _backend;
      backend?.cancel();
      if (backend != null) unawaited(backend.stop().catchError((Object _) {}));
    });
    return const CameraPreviewState();
  }

  void selectFront(bool front) {
    if (state.busy || _backend != null) return;
    state = CameraPreviewState(front: front);
  }

  bool _current(int revision) => ref.mounted && revision == _revision;

  Future<void> start() async {
    if (state.busy || _backend != null) return;
    if (!ref.read(deviceOnlineProvider(deviceId))) {
      state = CameraPreviewState(
        front: state.front,
        messageKey: 'cameraDisconnected',
      );
      return;
    }
    final revision = ++_revision;
    final front = state.front;
    state = CameraPreviewState(
      front: front,
      busy: true,
      messageKey: 'cameraStarting',
    );
    try {
      final backend = ref.read(cameraBackendFactoryProvider)(deviceId, front);
      _backend = backend;
      final texture = await backend.start();
      if (!_current(revision)) {
        await backend.stop();
        return;
      }
      state = CameraPreviewState(
        front: front,
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
                front: front,
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

  Future<void> stop([String message = 'cameraStopped']) async {
    if (state.messageKey == 'cameraStopping') return;
    final revision = ++_revision;
    _sizeTimer?.cancel();
    _sizeTimer = null;
    final backend = _backend;
    _backend = null;
    backend?.cancel();
    final front = state.front;
    state = CameraPreviewState(
      front: front,
      busy: true,
      messageKey: 'cameraStopping',
    );
    try {
      await backend?.stop();
    } catch (_) {
      message = 'cameraStopFailed';
    }
    if (_current(revision)) {
      state = CameraPreviewState(front: front, messageKey: message);
    }
  }
}
