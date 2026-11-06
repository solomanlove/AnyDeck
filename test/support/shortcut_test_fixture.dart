import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/window/window_shortcut_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隔离原生初始化，保留真实的设置更新、持久化和广播方法。
class ShortcutTestSettings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

/// 为快捷键测试提供真实本地化和主题，container 可在窗口之间隔离。
Widget shortcutTestApp({
  required ProviderContainer container,
  required Widget child,
  String language = 'zh',
  Brightness brightness = Brightness.light,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: child),
  ),
);

/// 发送真实修饰键按下 / 松开序列，供录入和运行时匹配测试共用。
Future<void> pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  List<LogicalKeyboardKey> modifiers = const [],
}) async {
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

/// 隔离窗口、托盘和持久化；可把子窗口请求交给真实的 Dart 主窗口 Handler。
class ShortcutPlatformMocks {
  final windowCalls = <String>[];
  final channelCalls = <Map<dynamic, dynamic>>[];
  final trayCalls = <MethodCall>[];
  bool forwardRequests = false;
  static const _windows = MethodChannel('mixin.one/desktop_multi_window');
  static const _channels = MethodChannel(
    'mixin.one/desktop_multi_window/channels',
  );
  static const _manager = MethodChannel('window_manager');
  static const _tray = MethodChannel('tray_manager');
  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void setUp() {
    SharedPreferences.setMockInitialValues({});
    windowCalls.clear();
    channelCalls.clear();
    trayCalls.clear();
    forwardRequests = false;
    _messenger.setMockMethodCallHandler(_manager, (call) async {
      windowCalls.add(call.method);
      return call.method.startsWith('is') ? false : null;
    });
    _messenger.setMockMethodCallHandler(_tray, (call) async {
      trayCalls.add(call);
      return null;
    });
    _messenger.setMockMethodCallHandler(
      _windows,
      (call) async => call.method == 'getAllWindows'
          ? [
              {'windowId': 'other', 'windowArgument': '{"kind":"mirror"}'},
            ]
          : null,
    );
    _messenger.setMockMethodCallHandler(_channels, (call) async {
      if (call.method == 'invokeMethod') {
        final data = call.arguments as Map;
        channelCalls.add(data);
        if (forwardRequests &&
            data['channel'] == WindowShortcutBridge.channelName) {
          return deliverWindowAction(data['arguments']);
        }
      }
      return null;
    });
  }

  Future<dynamic> deliverWindowAction(Object? action) async {
    final response = await _messenger.handlePlatformMessage(
      _channels.name,
      _channels.codec.encodeMethodCall(
        MethodCall('methodCall', {
          'channel': WindowShortcutBridge.channelName,
          'method': 'perform',
          'arguments': action,
        }),
      ),
      null,
    );
    return response == null ? null : _channels.codec.decodeEnvelope(response);
  }

  void tearDown() {
    for (final channel in [_windows, _channels, _manager, _tray]) {
      _messenger.setMockMethodCallHandler(channel, null);
    }
  }
}
