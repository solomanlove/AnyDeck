import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 在独立 Flutter 窗口中使用内置 libmpv；媒体 URL 只通过窗口通道传递。
class DlnaFallbackPlayer {
  DlnaFallbackPlayer({required this.onStopped, required this.onFailed});

  final void Function() onStopped;
  final void Function(String) onFailed;
  static const _events = WindowMethodChannel(
    'any_deck/dlna_fallback_events',
    mode: ChannelMode.unidirectional,
  );
  WindowController? _window;
  bool _registered = false;

  bool get isActive => _window != null;

  Future<bool> open(
    String url, {
    required String title,
    required double volume,
    required bool muted,
  }) async {
    await stop();
    if (!_registered) {
      await _events.setMethodCallHandler(_handleEvent);
      _registered = true;
    }
    final window = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({'type': 'dlna_player'}),
      ),
    );
    try {
      var ready = false;
      for (var attempt = 0; attempt < 12; attempt++) {
        try {
          ready =
              await window
                  .invokeMethod<bool>('isFlutterReady')
                  .timeout(const Duration(seconds: 1)) ==
              true;
          if (ready) break;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!ready) throw StateError('DLNA fallback window did not start');
      _window = window;
      final opened = await window
          .invokeMethod<bool>('dlnaOpen', {
            'url': url,
            'title': title,
            'volume': volume,
            'muted': muted,
          })
          .timeout(const Duration(seconds: 25));
      if (opened != true) {
        throw StateError('libmpv did not render a video frame');
      }
      return true;
    } catch (error) {
      debugPrint('[DLNA] libmpv fallback failed: $error');
      if (_window?.windowId == window.windowId) _window = null;
      try {
        await window.invokeMethod<void>('dlnaStop');
      } catch (_) {}
      return false;
    }
  }

  Future<dynamic> _handleEvent(MethodCall call) async {
    final data = call.arguments;
    if (data is! Map || data['windowId'] != _window?.windowId) return null;
    if (call.method == 'stopped') {
      _window = null;
      onStopped();
    } else if (call.method == 'failed') {
      _window = null;
      onFailed('${data['detail'] ?? 'libmpv playback failed'}');
    }
    return null;
  }

  Future<T?> invoke<T>(String method, [Object? arguments]) async {
    final window = _window;
    if (window == null) return null;
    try {
      return await window
          .invokeMethod<T>(method, arguments)
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('[DLNA] libmpv control failed: $error');
      _window = null;
      unawaited(window.invokeMethod<void>('dlnaStop').catchError((_) {}));
      onStopped();
      return null;
    }
  }

  Future<void> stop() async {
    final window = _window;
    _window = null;
    if (window == null) return;
    try {
      await window.hide();
      await window
          .invokeMethod<void>('dlnaStop')
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('[DLNA] libmpv stop failed: $error');
    }
  }
}
