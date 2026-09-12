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

  @override
  int? build() {
    // Keep provider alive so session state is preserved when UI rebuilds or switch tabs
    ref.keepAlive();
    final textureId = ref.watch(embeddedScrcpyServiceProvider).getTextureId(deviceId);
    if (textureId != null) {
      // 避免在 build 中直接修改 state 或进行副作用，使用 microtask 延迟注册进程监听
      Future.microtask(() => _listenToProcessExit(textureId));
    }
    return textureId;
  }

  void _listenToProcessExit(int textureId) {
    final service = ref.read(embeddedScrcpyServiceProvider);
    final process = service.getServerProcess(deviceId);
    process?.exitCode.then((code) {
      // 如果当前的投屏状态依然是这个 textureId，且进程已退出，说明是连接断开，自动执行清理
      if (state == textureId) {
        service.stop(deviceId);
        state = null;
      }
    });
  }

  Future<void> toggleMirroring({String? newDisplay, String? startApp}) async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      ref.read(screenPowerOffProvider(deviceId).notifier).setOff(false);
      state = null;
    } else {
      try {
        final textureId = await service.start(
          deviceId: deviceId,
          newDisplay: newDisplay,
          startApp: startApp,
        );
        state = textureId;
        _listenToProcessExit(textureId);
      } catch (e) {
        state = null;
        rethrow;
      }
    }
  }

  Future<void> restartMirroring({String? newDisplay, String? startApp}) async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      ref.read(screenPowerOffProvider(deviceId).notifier).setOff(false);
      state = null;
      // 稍作延迟确保资源完全释放
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    try {
      final textureId = await service.start(
        deviceId: deviceId,
        newDisplay: newDisplay,
        startApp: startApp,
      );
      state = textureId;
      _listenToProcessExit(textureId);
    } catch (e) {
      state = null;
      rethrow;
    }
  }

  Future<void> forceStop() async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      ref.read(screenPowerOffProvider(deviceId).notifier).setOff(false);
      state = null;
    }
  }
}

final activeEmbeddedMirrorProvider =
    NotifierProvider.family<ActiveEmbeddedMirrorNotifier, int?, String>(
      ActiveEmbeddedMirrorNotifier.new,
    );
