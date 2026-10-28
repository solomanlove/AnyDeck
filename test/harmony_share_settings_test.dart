import 'dart:io';

import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/settings/harmony_share_preference_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 不启动全局原生音视频服务，仅验证实际设置方法与广播。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore(this.throwError) : super.empty();
  final bool throwError;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throwError) throw StateError('Synthetic disk failure');
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final broadcasts = <Map<dynamic, dynamic>>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    broadcasts.clear();
    messenger.setMockMethodCallHandler(
      windows,
      (call) async => call.method == 'getAllWindows'
          ? [
              {'windowId': 'other', 'windowArgument': '{"kind":"mirror"}'},
            ]
          : null,
    );
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'invokeMethod') broadcasts.add(call.arguments as Map);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
  });

  for (final windowId in ['', 'child']) {
    test('设置保存并沿用 ${windowId.isEmpty ? '主窗口' : '子窗口'} 广播通道', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(_Settings.new),
          windowIdProvider.overrideWithValue(windowId),
        ],
      );
      final root = await Directory.systemTemp.createTemp('share-settings-');
      try {
        final controller = container.read(appSettingsProvider.notifier);
        expect(
          container.read(appSettingsProvider).harmonyShareNotifications,
          isTrue,
        );
        expect(
          container.read(appSettingsProvider).harmonyShareReceiveDirectory,
          isEmpty,
        );
        await controller.setHarmonyShareNotifications(false);
        await controller.setHarmonyShareReceiveDirectory(root.path);
        final settings = container.read(appSettingsProvider);
        expect(settings.harmonyShareNotifications, isFalse);
        expect(settings.harmonyShareReceiveDirectory, root.path);
        expect(
          settings
              .copyWith(language: AppLanguage.en)
              .harmonyShareReceiveDirectory,
          root.path,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool(HarmonySharePreferenceKeys.notifications),
          isFalse,
        );
        expect(
          prefs.getString(HarmonySharePreferenceKeys.receiveDirectory),
          root.path,
        );
        expect(
          broadcasts
              .where((m) => m['method'] == 'update_harmony_share_directory')
              .every((m) => m['arguments'] == root.path),
          isTrue,
        );
        final targets = broadcasts.map((m) => m['channel']).toSet();
        expect(targets, contains('mixin.one/window_controller/other'));
        expect(targets.contains('any_deck/settings_main'), windowId.isNotEmpty);
        final count = broadcasts.length;
        await controller.setHarmonyShareNotifications(true, broadcast: false);
        expect(broadcasts.length, count);
        await expectLater(
          controller.setHarmonyShareReceiveDirectory('${root.path}/missing'),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          container.read(appSettingsProvider).harmonyShareReceiveDirectory,
          root.path,
        );
        await controller.setHarmonyShareReceiveDirectory('', broadcast: false);
        expect(
          container.read(appSettingsProvider).harmonyShareReceiveDirectory,
          isEmpty,
        );
        expect(await root.list().length, 0);
      } finally {
        container.dispose();
        await root.delete(recursive: true);
      }
    });
  }
  for (final throws in [false, true]) {
    test('设置写入${throws ? "异常" : "返回失败"}后状态与缓存均不保留未保存值', () async {
      SharedPreferencesStorePlatform.instance = _FailingStore(throws);
      final container = ProviderContainer(
        overrides: [appSettingsProvider.overrideWith(_Settings.new)],
      );
      final root = await Directory.systemTemp.createTemp(
        'share-settings-failure-',
      );
      try {
        final controller = container.read(appSettingsProvider.notifier);
        await expectLater(
          controller.setHarmonyShareNotifications(false, broadcast: false),
          throwsStateError,
        );
        await expectLater(
          controller.setHarmonyShareReceiveDirectory(
            root.path,
            broadcast: false,
          ),
          throwsStateError,
        );
        expect(
          container.read(appSettingsProvider).harmonyShareNotifications,
          isTrue,
        );
        expect(
          container.read(appSettingsProvider).harmonyShareReceiveDirectory,
          isEmpty,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(HarmonySharePreferenceKeys.notifications), isNull);
        expect(
          prefs.getString(HarmonySharePreferenceKeys.receiveDirectory),
          isNull,
        );
        expect(broadcasts, isEmpty);
      } finally {
        container.dispose();
        await root.delete(recursive: true);
        SharedPreferences.setMockInitialValues({});
      }
    });
  }
}
