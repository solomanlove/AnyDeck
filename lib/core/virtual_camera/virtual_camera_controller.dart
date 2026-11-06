import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../scrcpy/embedded_scrcpy_service.dart';
import 'virtual_camera_state.dart';

/// 通道只传输状态和配置，视频像素始终留在 Rust/Swift。
final virtualCameraChannelProvider = Provider<MethodChannel>(
  (ref) => const MethodChannel('anydeck/virtual_camera'),
);
final virtualCameraHostProvider = Provider<bool>((ref) => Platform.isMacOS);

/// 复用现有 ADB 路径和 scrcpy 资源提取，便于测试替换环境依赖。
final virtualCameraPathsProvider =
    FutureProvider.autoDispose<Map<String, String>>(
      (ref) async => {
        'adbPath': ref.read(adbServiceProvider).executable,
        'jarPath': await ref
            .read(embeddedScrcpyServiceProvider)
            .extractScrcpyServerJar(),
      },
    );

final virtualCameraProvider =
    NotifierProvider.autoDispose<VirtualCameraController, VirtualCameraState>(
      VirtualCameraController.new,
    );

/// 可见页面每秒回读原生单例；销毁只停止轮询，不停掉会议摄像头。
class VirtualCameraController extends Notifier<VirtualCameraState> {
  Timer? _poll;
  bool _reading = false;
  int _revision = 0;
  final _cancelCalls = <void Function()>{};

  @override
  VirtualCameraState build() {
    final supported = ref.watch(virtualCameraHostProvider);
    if (supported) {
      unawaited(Future<void>.microtask(refresh));
      _poll = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(refresh());
      });
    }
    ref.onDispose(() {
      _revision++;
      _poll?.cancel();
      for (final cancel in _cancelCalls.toList()) {
        cancel();
      }
    });
    return const VirtualCameraState();
  }

  Future<VirtualCameraState> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) {
    final result = Completer<VirtualCameraState>();
    final timeout = Timer(const Duration(seconds: 5), () {
      if (!result.isCompleted) result.completeError(TimeoutException(method));
    });
    void cancel() {
      timeout.cancel();
      if (!result.isCompleted) {
        result.completeError(StateError('View disposed'));
      }
    }

    _cancelCalls.add(cancel);
    ref
        .read(virtualCameraChannelProvider)
        .invokeMapMethod<Object?, Object?>(method, arguments)
        .then(
          (value) {
            if (!result.isCompleted) {
              result.complete(VirtualCameraState.fromMap(value ?? const {}));
            }
          },
          onError: (Object error, StackTrace trace) {
            if (!result.isCompleted) result.completeError(error, trace);
          },
        );
    return result.future.whenComplete(() {
      timeout.cancel();
      _cancelCalls.remove(cancel);
    });
  }

  Future<void> refresh() async {
    if (!ref.mounted ||
        _reading ||
        state.busy ||
        !ref.read(virtualCameraHostProvider)) {
      return;
    }
    _reading = true;
    final revision = _revision;
    try {
      final next = await _call('status');
      if (ref.mounted && revision == _revision) state = next;
    } on MissingPluginException {
      if (ref.mounted && revision == _revision) {
        state = const VirtualCameraState();
      }
    } catch (_) {
      if (ref.mounted && revision == _revision) {
        state = state.withOperation(error: 'statusFailed');
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> activate() => _operation(() => _call('activate'));
  Future<void> deactivate() => _operation(() => _call('deactivate'));
  Future<void> disable() =>
      _operation(() => _call('configure', {'enabled': false}));

  /// 先释放本地预览，再交接镜头给原生全局会话；不允许两路抢占同一镜头。
  Future<void> enable({
    required String deviceId,
    required bool front,
    required Future<void> Function() stopPreview,
    required Map<String, String> labels,
  }) => _operation(() async {
    if (!state.ready) throw PlatformException(code: 'extensionNotReady');
    await stopPreview();
    if (!ref.mounted) throw StateError('View disposed');
    final paths = await ref.read(virtualCameraPathsProvider.future);
    if (!ref.mounted) throw StateError('View disposed');
    return _call('configure', {
      ...paths,
      'deviceId': deviceId,
      'front': front,
      'enabled': true,
      'labels': labels,
    });
  });

  Future<void> _operation(Future<VirtualCameraState> Function() action) async {
    if (state.busy) return;
    final revision = ++_revision;
    state = state.withOperation(busy: true);
    try {
      final next = await action();
      if (ref.mounted && revision == _revision) state = next;
    } catch (error) {
      if (ref.mounted && revision == _revision) {
        state = state.withOperation(
          error: error is PlatformException ? error.code : 'operationFailed',
        );
      }
    }
  }
}
