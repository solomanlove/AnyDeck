import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/ios/ios_mirror_service.dart';
import 'device_screen_preview_queue.dart';

/// 按设备保存真实静态截图；可见设备墙单次采集，不启动投屏或周期截图。
final deviceScreenPreviewProvider = AsyncNotifierProvider.autoDispose
    .family<DeviceScreenPreviewController, Uint8List?, String>(
      DeviceScreenPreviewController.new,
    );

/// UI 等待有界；实际命令的超时及进程回收仍由各平台截图服务负责。
final deviceScreenPreviewTimeoutProvider = Provider(
  (ref) => const Duration(seconds: 40),
);

/// 刷新当前可见的手机墙；列表和隐藏路由不新增截图请求。
void refreshVisibleDeviceScreenPreviews(WidgetRef ref) {
  for (final device in ref.read(deviceRegistryProvider)) {
    final provider = deviceScreenPreviewProvider(device.id);
    if (ref.read(provider.exists)) {
      ref.read(provider.notifier).refreshIfVisible();
    }
  }
}

class DeviceScreenPreviewController extends AsyncNotifier<Uint8List?> {
  DeviceScreenPreviewController(this.deviceId);

  final String deviceId;
  KeepAliveLink? _retained;
  Timer? _releaseTimer;
  Timer? _captureTimer;
  Completer<Uint8List?>? _uiCompletion;
  DeviceScreenPreviewRequest? _request;
  Future<void>? _pending;
  Uint8List? _lastBytes;
  var _visible = false;
  var _generation = 0;
  var _refreshAfterPending = false;
  var _automaticCapture = false;

  /// 更新期间继续展示最近一次真实快照；不将旧图冒充本轮采集成功。
  Uint8List? get cachedBytes => _lastBytes;

  @override
  Uint8List? build() {
    ref.onDispose(() {
      _releaseTimer?.cancel();
      _cancelUiWait();
      _request?.cancel();
    });
    return null;
  }

  /// 由可见卡片拥有生命周期；回墙重新取图，离开立即撤回尚未运行的任务。
  void setVisible(bool visible) {
    if (!ref.mounted || _visible == visible) return;
    _visible = visible;
    _generation++;
    if (visible) {
      refreshIfVisible();
    } else {
      _refreshAfterPending = false;
      _request?.cancel();
      if (_automaticCapture) _cancelUiWait();
    }
  }

  /// 显式刷新与回墙会更新缓存；已有命令完成后最多补一轮，不无限累积请求。
  void refreshIfVisible() {
    if (!ref.mounted || !_visible) return;
    if (_pending != null) {
      _refreshAfterPending = true;
    } else {
      unawaited(capture(automatic: true));
    }
  }

  /// 手动与自动截图共享队列及同设备互斥；自动 iOS 预览不下载或挂载镜像。
  Future<void> capture({bool automatic = false}) {
    if (_pending != null) return _pending!;
    if (!ref.mounted || _device == null || (automatic && !_visible)) {
      return Future.value();
    }
    final done = Completer<void>();
    _pending = done.future;
    _automaticCapture = automatic;
    _releaseTimer?.cancel();
    _retained ??= ref.keepAlive();
    final generation = _generation;
    state = const AsyncLoading();
    final queue = ref.read(deviceScreenPreviewQueueProvider);
    final request = queue.enqueue(
      () => _capture(generation, automatic),
      isCurrent: () =>
          ref.mounted &&
          _device != null &&
          (!automatic || (_visible && _generation == generation)),
    );
    _request = request;
    unawaited(_finish(request, done));
    return done.future;
  }

  RegisteredDevice? get _device => ref
      .read(deviceRegistryProvider)
      .where(
        (device) =>
            device.id == deviceId &&
            device.isOnline &&
            device.status == 'device' &&
            !device.id.startsWith('airplay-'),
      )
      .firstOrNull;

  Future<void> _capture(int generation, bool automatic) async {
    final device = _device;
    if (device == null) return;
    final command = device.isIos
        ? automatic
              ? ref
                    .read(iosCommandServiceProvider)
                    .capturePreviewScreenshot(device.id)
              : ref.read(iosCommandServiceProvider).captureScreenshot(device.id)
        : device.isHarmony
        ? ref
              .read(hdcServiceProvider)
              .captureScreenshot(
                device.id,
                timeout: const Duration(seconds: 10),
              )
        : ref
              .read(adbServiceProvider)
              .captureScreenshot(
                device.id,
                timeout: const Duration(seconds: 10),
              );
    // timeout 只结束 UI 等待，槽必须等平台命令真实退出，避免下一轮叠加进程。
    final settled = command.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      final bytes = await _waitForCommand(command);
      if (bytes != null && _canPublish(generation, automatic)) {
        _lastBytes = bytes;
        state = AsyncData(bytes);
      }
    } catch (error, stack) {
      if (_canPublish(generation, automatic)) {
        state = AsyncError(error, stack);
      }
    } finally {
      await settled;
    }
  }

  /// UI 等待的计时器归 Controller 所有，销毁或隐藏时立即清除。
  Future<Uint8List?> _waitForCommand(Future<Uint8List> command) async {
    final completion = Completer<Uint8List?>();
    _uiCompletion = completion;
    final timeout = ref.read(deviceScreenPreviewTimeoutProvider);
    _captureTimer = Timer(timeout, () {
      if (!completion.isCompleted) {
        completion.completeError(TimeoutException('Screen preview', timeout));
      }
    });
    unawaited(
      command.then(
        (bytes) {
          if (!completion.isCompleted) completion.complete(bytes);
        },
        onError: (Object error, StackTrace stack) {
          if (!completion.isCompleted) completion.completeError(error, stack);
        },
      ),
    );
    try {
      return await completion.future;
    } finally {
      _captureTimer?.cancel();
      _captureTimer = null;
      _uiCompletion = null;
    }
  }

  void _cancelUiWait() {
    _captureTimer?.cancel();
    final completion = _uiCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(null);
    }
  }

  bool _canPublish(int generation, bool automatic) =>
      ref.mounted &&
      _device != null &&
      (!automatic || (_visible && _generation == generation));

  Future<void> _finish(
    DeviceScreenPreviewRequest request,
    Completer<void> done,
  ) async {
    try {
      await request.future;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
    } finally {
      _request = null;
      _pending = null;
      done.complete();
      if (ref.mounted) {
        if (state.isLoading) state = AsyncData(_lastBytes);
        _releaseTimer = Timer(const Duration(minutes: 1), () {
          _retained?.close();
          _retained = null;
        });
        if (_visible && _refreshAfterPending) {
          _refreshAfterPending = false;
          unawaited(capture(automatic: true));
        }
      }
    }
  }
}
