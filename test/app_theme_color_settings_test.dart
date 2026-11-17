import 'dart:async';

import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shortcut_test_fixture.dart';

/// 保留真实启动加载与设置 Handler，隔离接收名称的网络探测。
class _LoadedSettings extends AppSettingsController {
  @override
  Future<void> ensureReceiverNames() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = ShortcutPlatformMocks();
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(platform.setUp);
  tearDown(platform.tearDown);

  /// 等待真实异步加载产生状态，避免固定延时或绕过 Preference 读取。
  Future<ProviderContainer> loadedScope() async {
    final scope = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_LoadedSettings.new)],
    );
    addTearDown(scope.dispose);
    final loaded = Completer<void>();
    scope.listen(appSettingsProvider, (_, _) {
      if (!loaded.isCompleted) loaded.complete();
    });
    await loaded.future.timeout(const Duration(seconds: 5));
    return scope;
  }

  Future<void> receiveColor(Object? value) async {
    final response = await messenger.handlePlatformMessage(
      channels.name,
      channels.codec.encodeMethodCall(
        MethodCall('methodCall', {
          'channel': 'any_deck/settings_main',
          'method': 'update_theme_color',
          'arguments': value,
        }),
      ),
      null,
    );
    if (response != null) channels.codec.decodeEnvelope(response);
  }

  test('默认沿用绿色，copyWith 修改主题色并保留外观模式和其他设置', () {
    const original = AppSettings(
      themeMode: ThemeMode.dark,
      scrcpyAlwaysOnTop: false,
    );
    expect(original.themeColor, AppThemeColor.green);
    final changed = original.copyWith(themeColor: AppThemeColor.purple);
    expect(changed.themeColor, AppThemeColor.purple);
    expect(changed.themeMode, ThemeMode.dark);
    expect(changed.scrcpyAlwaysOnTop, isFalse);
    expect(
      changed.copyWith(themeMode: ThemeMode.light).themeColor,
      AppThemeColor.purple,
    );
  });

  test('主题色名称往返转换，缺失和无效值回退绿色', () {
    for (final color in AppThemeColor.values) {
      expect(AppThemeColor.fromName(color.name), color);
    }
    for (final name in [null, '', 'invalid', 'BLUE', '#09c47c']) {
      expect(AppThemeColor.fromName(name), AppThemeColor.green);
    }
    expect(
      AppThemeColor.values.map((color) => color.color).toSet(),
      hasLength(AppThemeColor.values.length),
    );
  });

  for (final color in AppThemeColor.values) {
    test('启动读取已保存的 ${color.name} 主题色', () async {
      SharedPreferences.setMockInitialValues({
        'settings.themeColor': color.name,
        'settings.themeMode': 'dark',
      });
      final scope = await loadedScope();
      expect(scope.read(appSettingsProvider).themeColor, color);
      expect(scope.read(appSettingsProvider).themeMode, ThemeMode.dark);
    });
  }

  for (final stored in [null, 'obsolete-color']) {
    test('启动时主题色配置 $stored 安全回退绿色', () async {
      SharedPreferences.setMockInitialValues({'settings.themeColor': ?stored});
      final scope = await loadedScope();
      expect(scope.read(appSettingsProvider).themeColor, AppThemeColor.green);
    });
  }

  test('主题色保存后重新创建设置仍保留选择，切换外观不改变主题色', () async {
    final first = await loadedScope();
    final controller = first.read(appSettingsProvider.notifier);
    await controller.setThemeColor(AppThemeColor.teal, broadcast: false);
    await controller.setThemeMode(ThemeMode.dark, broadcast: false);
    expect(first.read(appSettingsProvider).themeColor, AppThemeColor.teal);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings.themeColor'), 'teal');
    final restored = await loadedScope();
    expect(restored.read(appSettingsProvider).themeColor, AppThemeColor.teal);
    expect(restored.read(appSettingsProvider).themeMode, ThemeMode.dark);
  });

  test('启动加载期间修改主题色会等待加载，不被旧配置覆盖', () async {
    SharedPreferences.setMockInitialValues({'settings.themeColor': 'purple'});
    final scope = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_LoadedSettings.new)],
    );
    addTearDown(scope.dispose);
    await scope
        .read(appSettingsProvider.notifier)
        .setThemeColor(AppThemeColor.blue, broadcast: false);
    expect(scope.read(appSettingsProvider).themeColor, AppThemeColor.blue);
    expect(
      (await SharedPreferences.getInstance()).getString('settings.themeColor'),
      'blue',
    );
  });

  for (final windowId in ['', 'child']) {
    test('${windowId.isEmpty ? '主' : '子'}窗口修改主题色后持久化并同步其他窗口', () async {
      final scope = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(ShortcutTestSettings.new),
          windowIdProvider.overrideWithValue(windowId),
        ],
      );
      addTearDown(scope.dispose);
      final controller = scope.read(appSettingsProvider.notifier);
      await controller.setThemeColor(AppThemeColor.blue);
      expect(scope.read(appSettingsProvider).themeColor, AppThemeColor.blue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'settings.themeColor',
        ),
        'blue',
      );
      final updates = platform.channelCalls
          .where((call) => call['method'] == 'update_theme_color')
          .toList();
      expect(updates, hasLength(windowId.isEmpty ? 1 : 2));
      expect(updates.map((call) => call['arguments']), everyElement('blue'));
      if (windowId.isNotEmpty) {
        expect(updates.first['channel'], 'any_deck/settings_main');
      }
      expect(updates.last['channel'], 'mixin.one/window_controller/other');
      platform.channelCalls.clear();
      await controller.setThemeColor(AppThemeColor.orange, broadcast: false);
      expect(platform.channelCalls, isEmpty);
      expect(scope.read(appSettingsProvider).themeColor, AppThemeColor.orange);
    });
  }

  test('真实设置通道收到主题色后更新状态且不会循环广播', () async {
    SharedPreferences.setMockInitialValues({'settings.themeColor': 'purple'});
    final scope = await loadedScope();
    platform.channelCalls.clear();
    await receiveColor('pink');
    expect(scope.read(appSettingsProvider).themeColor, AppThemeColor.pink);
    expect(platform.channelCalls, isEmpty);
    await receiveColor('green');
    expect(scope.read(appSettingsProvider).themeColor, AppThemeColor.green);
    expect(platform.channelCalls, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString('settings.themeColor'),
      'purple',
    );
  });

  test('主题色通道忽略类型错误和未知色值，保留当前主题及持久化配置', () async {
    SharedPreferences.setMockInitialValues({'settings.themeColor': 'purple'});
    final scope = await loadedScope();
    platform.channelCalls.clear();
    for (final value in [null, true, 42, <String, String>{}, 'unknown']) {
      await receiveColor(value);
      expect(scope.read(appSettingsProvider).themeColor, AppThemeColor.purple);
    }
    expect(platform.channelCalls, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString('settings.themeColor'),
      'purple',
    );
  });

  test('子窗口修改通过真实主窗口 Handler 同步，接收端不再次广播', () async {
    final main = await loadedScope();
    final child = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(ShortcutTestSettings.new),
        windowIdProvider.overrideWithValue('child'),
      ],
    );
    addTearDown(child.dispose);
    final updates = <Map<dynamic, dynamic>>[];
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method != 'invokeMethod') return null;
      final data = call.arguments as Map;
      if (data['method'] != 'update_theme_color') return null;
      updates.add(data);
      if (data['channel'] == 'any_deck/settings_main') {
        await receiveColor(data['arguments']);
      }
      return null;
    });
    await child
        .read(appSettingsProvider.notifier)
        .setThemeColor(AppThemeColor.orange);
    expect(child.read(appSettingsProvider).themeColor, AppThemeColor.orange);
    expect(main.read(appSettingsProvider).themeColor, AppThemeColor.orange);
    expect(updates, hasLength(2));
  });
}
