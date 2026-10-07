import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/widgets.dart';

import 'ios_wda_host.dart';

/// 单接收方通道：所有窗口共享主引擎的 WDA 会话，不共享 Flutter Texture。
class IosControlGateway {
  static const _channel = WindowMethodChannel(
    'anydeck/ios_control',
    mode: ChannelMode.unidirectional,
  );
  static IosWdaHost? _host;
  static AppLifecycleListener? _lifecycle;

  static Future<void> initializeHost() async {
    _host = IosWdaHost();
    _lifecycle ??= AppLifecycleListener(
      onExitRequested: () async {
        await closeHost();
        return AppExitResponse.exit;
      },
    );
    await _channel.setMethodCallHandler((call) async {
      try {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        return {
          'ok': true,
          'value': await _host!.execute(
            args.remove('udid') as String,
            call.method,
            args,
          ),
        };
      } catch (error) {
        return {'ok': false, 'error': error.toString()};
      }
    });
  }

  static Future<Map<String, dynamic>> call(
    String udid,
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (_host != null) return _host!.execute(udid, action, args);
    final result = await _channel.invokeMethod<dynamic>(action, {
      'udid': udid,
      ...args,
    });
    if (result is! Map || result['ok'] != true) {
      throw StateError(
        '${result is Map ? result['error'] : 'iosWdaUnavailable'}',
      );
    }
    return Map<String, dynamic>.from(result['value'] as Map);
  }

  static Future<void> closeHost() async => _host?.close();
}
