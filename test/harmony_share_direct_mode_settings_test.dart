import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/settings/harmony_share_preference_keys.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 隔离设置持久化与窗口通信，不启动真实 Core 或切换 Wi-Fi。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.empty();
  int writes = 0;
  bool fail = false;
  bool throwFailure = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (throwFailure) throw StateError('Synthetic disk failure');
    return fail ? false : super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer main;
  late ProviderContainer child;
  late _Store store;
  final calls = <Map<dynamic, dynamic>>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    calls.clear();
    main = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_Settings.new)],
    );
    child = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(_Settings.new),
        windowIdProvider.overrideWithValue('other'),
      ],
    );
    messenger.setMockMethodCallHandler(
      windows,
      (call) async => call.method == 'getAllWindows'
          ? [
              {'windowId': 'other', 'windowArgument': '{"kind":"mirror"}'},
            ]
          : null,
    );
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method != 'invokeMethod') return null;
      final args = call.arguments as Map;
      calls.add(args);
      if (args['channel'] == 'any_deck/settings_main') {
        expect(args['method'], 'change_harmony_share_direct_mode');
        await main
            .read(appSettingsProvider.notifier)
            .setHarmonyShareDirectMode(args['arguments'] as bool);
      } else {
        expect(args['method'], 'update_harmony_share_direct_mode');
        await child
            .read(appSettingsProvider.notifier)
            .setHarmonyShareDirectMode(
              args['arguments'] as bool,
              broadcast: false,
            );
      }
      return null;
    });
  });
  tearDown(() async {
    HarmonyShareService.instance.busy = false;
    await HarmonyShareService.instance.configureDirectMode(false, () async {});
    main.dispose();
    child.dispose();
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
    SharedPreferences.setMockInitialValues({});
  });

  test('默认LAN，主子窗口手动切换仅由主窗口保存并同步', () async {
    expect(main.read(appSettingsProvider).harmonyShareDirectMode, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        HarmonySharePreferenceKeys.directMode,
      ),
      isNull,
    );
    await main
        .read(appSettingsProvider.notifier)
        .setHarmonyShareDirectMode(true);
    expect(main.read(appSettingsProvider).harmonyShareDirectMode, isTrue);
    expect(child.read(appSettingsProvider).harmonyShareDirectMode, isTrue);
    expect(store.writes, 1);
    expect(HarmonyShareService.instance.directModeEnabled, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        HarmonySharePreferenceKeys.directMode,
      ),
      isTrue,
    );
    await child
        .read(appSettingsProvider.notifier)
        .setHarmonyShareDirectMode(false);
    expect(main.read(appSettingsProvider).harmonyShareDirectMode, isFalse);
    expect(child.read(appSettingsProvider).harmonyShareDirectMode, isFalse);
    expect(HarmonyShareService.instance.directModeEnabled, isFalse);
    expect(store.writes, 2);
    expect(calls.map((call) => call['method']), [
      'update_harmony_share_direct_mode',
      'change_harmony_share_direct_mode',
      'update_harmony_share_direct_mode',
    ]);
  });

  test('已有设置可重载，迟到广播不覆盖新值，copyWith保留模式', () async {
    await main
        .read(appSettingsProvider.notifier)
        .setHarmonyShareDirectMode(true);
    final reloaded = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_Settings.new)],
    );
    try {
      await reloaded
          .read(appSettingsProvider.notifier)
          .setHarmonyShareDirectMode(false, broadcast: false);
      expect(reloaded.read(appSettingsProvider).harmonyShareDirectMode, isTrue);
      expect(
        reloaded
            .read(appSettingsProvider)
            .copyWith(language: AppLanguage.en)
            .harmonyShareDirectMode,
        isTrue,
      );
      final count = calls.length;
      await child
          .read(appSettingsProvider.notifier)
          .setHarmonyShareDirectMode(false, broadcast: false);
      expect(child.read(appSettingsProvider).harmonyShareDirectMode, isTrue);
      expect(calls.length, count);
      expect(store.writes, 1);
    } finally {
      reloaded.dispose();
    }
  });

  test('传输期间拒绝跨窗口变更，不写盘或开启模式', () async {
    HarmonyShareService.instance.busy = true;
    await expectLater(
      child.read(appSettingsProvider.notifier).setHarmonyShareDirectMode(true),
      throwsA(isA<WindowChannelException>()),
    );
    expect(main.read(appSettingsProvider).harmonyShareDirectMode, isFalse);
    expect(child.read(appSettingsProvider).harmonyShareDirectMode, isFalse);
    expect(store.writes, 0);
  });

  for (final throws in [false, true]) {
    test('模式写入${throws ? "异常" : "失败"}不保留未保存值或广播成功', () async {
      store.fail = !throws;
      store.throwFailure = throws;
      await expectLater(
        main.read(appSettingsProvider.notifier).setHarmonyShareDirectMode(true),
        throwsStateError,
      );
      expect(main.read(appSettingsProvider).harmonyShareDirectMode, isFalse);
      expect(child.read(appSettingsProvider).harmonyShareDirectMode, isFalse);
      expect(HarmonyShareService.instance.directModeEnabled, isFalse);
      expect(HarmonyShareService.instance.configuring, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          HarmonySharePreferenceKeys.directMode,
        ),
        isNull,
      );
      expect(calls, isEmpty);
    });
  }
}
