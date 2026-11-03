import 'package:any_deck/app/window/desktop_window_title_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('libmpv 视频子窗口将主题模式传给 macOS 标题栏', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('any_deck/window');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final modes = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setWindowAppearance');
      modes.add(call.arguments as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final mode in ThemeMode.values) {
      await DesktopWindowTitleService.setAppearance(mode);
    }
    expect(modes, ['system', 'light', 'dark']);
  });

  test('子窗口尚未关联原生窗口时允许首帧后重试', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('any_deck/window');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'no_window');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await DesktopWindowTitleService.setAppearance(ThemeMode.light);
  });
}
