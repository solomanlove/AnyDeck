part of 'embedded_scrcpy_service.dart';

// Riverpod Provider definitions
final embeddedScrcpyServiceProvider = Provider<EmbeddedScrcpyService>((ref) {
  final adbService = ref.watch(adbServiceProvider);
  final service = EmbeddedScrcpyService(adbService);
  ref.onDispose(service.stopAll);
  return service;
});

class ActiveEmbeddedMirrorNotifier extends Notifier<int?> {
  ActiveEmbeddedMirrorNotifier(this.deviceId);

  final String deviceId;
  int _generation = 0;
  Future<void>? _starting;
  Future<void>? _stopping;

  @override
  int? build() {
    // Keep provider alive so session state is preserved when UI rebuilds or switch tabs
    ref.keepAlive();
    ref.onDispose(() => _generation++);
    final textureId = ref.watch(embeddedScrcpyServiceProvider).getTextureId(deviceId);
    if (textureId != null) {
      // 避免在 build 中直接修改 state 或进行副作用，使用 microtask 延迟注册进程监听
      Future.microtask(() => _listenToProcessExit(textureId));
    }
    return textureId;
  }

  void _listenToProcessExit(int textureId) {
    if (!ref.mounted) return;
    final generation = _generation;
    final service = ref.read(embeddedScrcpyServiceProvider);
    final process = service.getServerProcess(deviceId);
    process?.exitCode.then((code) async {
      // 如果当前的投屏状态依然是这个 textureId，且进程已退出，说明是连接断开，自动执行清理
      if (ref.mounted && generation == _generation && state == textureId) {
        final stopping = service.stop(deviceId);
        _stopping = stopping;
        state = null;
        ref.read(screenPowerOffProvider(deviceId).notifier).setOff(false);
        // 立即通知窗口查询新通道；下一次启动仍须等待旧会话清理完成。
        ref.read(mirrorDisconnectedProvider(deviceId).notifier).disconnected();
        try {
          await stopping;
        } finally {
          if (identical(_stopping, stopping)) _stopping = null;
        }
      }
    });
  }

  Future<void> toggleMirroring({
    String? newDisplay,
    String? startApp,
    bool initiallyMuted = false,
  }) async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await forceStop();
    } else {
      await _start(newDisplay, startApp, initiallyMuted);
    }
  }

  Future<void> restartMirroring({
    String? newDisplay,
    String? startApp,
    bool initiallyMuted = false,
  }) async {
    final wasActive = ref.read(embeddedScrcpyServiceProvider).isActive(deviceId);
    await forceStop();
    if (wasActive) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (!ref.mounted) return;
    await _start(newDisplay, startApp, initiallyMuted);
  }

  /// 合并并发启动；停止时用 generation 废弃迟到的会话，避免恢复窗口关闭后泄漏。
  Future<void> _start(
    String? newDisplay,
    String? startApp,
    bool initiallyMuted,
  ) {
    if (_starting != null) return _starting!;
    final generation = ++_generation;
    final service = ref.read(embeddedScrcpyServiceProvider);
    final operation = _startOnce(
      service,
      generation,
      newDisplay,
      startApp,
      initiallyMuted,
    );
    _starting = operation;
    return operation.whenComplete(() => _starting = null);
  }

  Future<void> _startOnce(
    EmbeddedScrcpyService service,
    int generation,
    String? newDisplay,
    String? startApp,
    bool initiallyMuted,
  ) async {
    try {
      final textureId = await service.start(
        deviceId: deviceId,
        newDisplay: newDisplay,
        startApp: startApp,
        initiallyMuted: initiallyMuted,
      );
      if (!ref.mounted || generation != _generation) {
        await service.stop(deviceId);
        return;
      }
      state = textureId;
      _listenToProcessExit(textureId);
    } catch (e) {
      if (ref.mounted && generation == _generation) {
        state = null;
        ref.read(mirrorDisconnectedProvider(deviceId).notifier).disconnected();
      }
      rethrow;
    }
  }

  Future<void> forceStop() async {
    ++_generation;
    final service = ref.read(embeddedScrcpyServiceProvider);
    // 先使退出回调失效；主动停止和刷新不应触发自动换线。
    try {
      await _starting;
    } catch (_) {}
    // await 同时避开 Widget.dispose 的同步构建阶段，避免在卸载时通知 Provider。
    if (ref.mounted) state = null;
    await _stopping;
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
    }
    if (ref.mounted) {
      ref.read(screenPowerOffProvider(deviceId).notifier).setOff(false);
    }
  }
}

final activeEmbeddedMirrorProvider =
    NotifierProvider.family<ActiveEmbeddedMirrorNotifier, int?, String>(
      ActiveEmbeddedMirrorNotifier.new,
    );

/// 仅异常断线/启动失败递增；与主动停止后的空 Texture 状态分开。
class MirrorDisconnectedNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void disconnected() => state++;
}

final mirrorDisconnectedProvider =
    NotifierProvider.family<MirrorDisconnectedNotifier, int, String>(
      (_) => MirrorDisconnectedNotifier(),
    );
