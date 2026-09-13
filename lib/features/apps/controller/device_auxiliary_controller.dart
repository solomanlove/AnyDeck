import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/auxiliary_backend.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';

/// 麦克风与剪贴板按设备及用途隔离，切页后自动停止。
typedef AuxiliaryKey = ({String deviceId, bool microphone});
final deviceAuxiliaryProvider = NotifierProvider.autoDispose
    .family<DeviceAuxiliaryController, DeviceAuxiliaryState, AuxiliaryKey>(
      DeviceAuxiliaryController.new,
    );

/// 仅保留最新剪贴板及接收时间，不持久化、不自动覆盖电脑剪贴板。
class DeviceAuxiliaryState {
  const DeviceAuxiliaryState({
    this.busy = false,
    this.active = false,
    this.muted = false,
    this.text,
    this.receivedAt,
    this.messageKey = 'auxIdle',
    this.failed = false,
  });
  final bool busy;
  final bool active;
  final bool muted;
  final String? text;
  final DateTime? receivedAt;
  final String messageKey;
  final bool failed;
}

/// 会话 revision 拦截迟到启动/事件，停止采集与监听静音采用不同操作。
class DeviceAuxiliaryController extends Notifier<DeviceAuxiliaryState> {
  DeviceAuxiliaryController(this.key);
  final AuxiliaryKey key;
  AuxiliaryBackend? _backend;
  StreamSubscription<String>? _subscription;
  Timer? _clipboardTimer;
  String? _pendingText;
  int _revision = 0;

  @override
  DeviceAuxiliaryState build() {
    ref.listen(deviceOnlineProvider(key.deviceId), (_, online) {
      if (!online && _backend != null) unawaited(stop('auxDisconnected', true));
    });
    ref.onDispose(() {
      _revision++;
      _clipboardTimer?.cancel();
      unawaited(_subscription?.cancel());
      _backend?.cancel();
      unawaited(_backend?.stop().catchError((Object _) {}));
    });
    return const DeviceAuxiliaryState();
  }

  bool _current(int revision) => ref.mounted && revision == _revision;

  Future<void> start() async {
    if (state.busy || _backend != null) return;
    final revision = ++_revision;
    state = const DeviceAuxiliaryState(busy: true, messageKey: 'auxStarting');
    try {
      if (!ref.read(deviceOnlineProvider(key.deviceId))) {
        throw StateError('offline');
      }
      final sdk = await ref.read(captureSdkProvider(key.deviceId).future);
      if (!_current(revision)) return;
      if (sdk == null ||
          sdk < (key.microphone ? 30 : 21) ||
          !ref.read(captureHostSupportedProvider)) {
        state = const DeviceAuxiliaryState(
          messageKey: 'auxUnsupported',
          failed: true,
        );
        return;
      }
      final backend = ref.read(auxiliaryBackendFactoryProvider)(
        key.deviceId,
        key.microphone,
      );
      _backend = backend;
      _subscription = backend.clipboard.listen((text) {
        if (!_current(revision)) return;
        _pendingText = text;
        // 高频复制仅每 100ms 展示最新值，文本大小由协议读取器限制。
        _clipboardTimer ??= Timer(const Duration(milliseconds: 100), () {
          _clipboardTimer = null;
          if (!_current(revision)) return;
          state = DeviceAuxiliaryState(
            active: true,
            text: _pendingText,
            receivedAt: DateTime.now(),
            messageKey: 'clipboardLive',
          );
        });
      });
      await backend.start();
      if (!_current(revision)) {
        await backend.stop();
        return;
      }
      state = DeviceAuxiliaryState(
        active: true,
        text: state.text,
        receivedAt: state.receivedAt,
        messageKey: key.microphone ? 'microphoneLive' : 'clipboardWaiting',
      );
      unawaited(
        backend.exited
            .then((_) async {
              if (_current(revision)) await stop('auxDisconnected', true);
            })
            .catchError((Object _) {}),
      );
    } catch (_) {
      if (_current(revision)) {
        await stop(
          key.microphone ? 'microphoneFailed' : 'clipboardFailed',
          true,
        );
      }
    }
  }

  Future<void> toggleMute() async {
    if (!state.active || state.busy || _backend == null) return;
    final revision = _revision;
    final muted = !state.muted;
    state = DeviceAuxiliaryState(
      active: true,
      busy: true,
      muted: state.muted,
      messageKey: state.messageKey,
    );
    try {
      await _backend!.mute(muted);
      if (_current(revision)) {
        state = DeviceAuxiliaryState(
          active: true,
          muted: muted,
          messageKey: muted ? 'microphoneMuted' : 'microphoneLive',
        );
      }
    } catch (_) {
      if (_current(revision)) await stop('microphoneFailed', true);
    }
  }

  Future<void> refresh() async {
    if (!state.active || state.busy || _backend == null) return;
    final revision = _revision;
    state = DeviceAuxiliaryState(
      active: true,
      busy: true,
      text: state.text,
      receivedAt: state.receivedAt,
      messageKey: 'clipboardWaiting',
    );
    try {
      await _backend!.refresh();
      if (_current(revision)) {
        state = DeviceAuxiliaryState(
          active: true,
          text: state.text,
          receivedAt: state.receivedAt,
          messageKey: 'clipboardWaiting',
        );
      }
    } catch (_) {
      if (_current(revision)) await stop('clipboardFailed', true);
    }
  }

  Future<void> stop([
    String message = 'auxStopped',
    bool failed = false,
  ]) async {
    if (state.messageKey == 'auxStopping') return;
    final revision = ++_revision;
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    _pendingText = null;
    final backend = _backend;
    _backend = null;
    backend?.cancel();
    state = const DeviceAuxiliaryState(busy: true, messageKey: 'auxStopping');
    try {
      await _subscription?.cancel();
      _subscription = null;
      await backend?.stop();
    } catch (_) {
      message = 'auxStopFailed';
      failed = true;
    }
    if (_current(revision)) {
      state = DeviceAuxiliaryState(messageKey: message, failed: failed);
    }
  }
}
