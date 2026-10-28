import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/settings/harmony_share_preference_keys.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_local_name.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 隔离设置持久化与窗口路由，不初始化音视频服务或 App 窗口。
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
        expect(args['method'], 'change_harmony_share_local_name');
        await main
            .read(appSettingsProvider.notifier)
            .setHarmonyShareLocalName(args['arguments'] as String);
      } else {
        expect(args['method'], 'update_harmony_share_local_name');
        await child
            .read(appSettingsProvider.notifier)
            .setHarmonyShareLocalName(
              args['arguments'] as String,
              broadcast: false,
            );
      }
      return null;
    });
  });
  tearDown(() {
    HarmonyShareService.instance.busy = false;
    main.dispose();
    child.dispose();
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
    SharedPreferences.setMockInitialValues({});
  });

  test('主子窗口名称双向同步只由主窗口写盘，copyWith 保留名称', () async {
    expect(main.read(appSettingsProvider).harmonyShareLocalName, 'AnyDeck');
    await main
        .read(appSettingsProvider.notifier)
        .setHarmonyShareLocalName('测试 Mac');
    expect(store.writes, 1);
    expect(child.read(appSettingsProvider).harmonyShareLocalName, '测试 Mac');
    await child
        .read(appSettingsProvider.notifier)
        .setHarmonyShareLocalName('👩‍💻 Mac');
    expect(store.writes, 2);
    expect(main.read(appSettingsProvider).harmonyShareLocalName, '👩‍💻 Mac');
    expect(child.read(appSettingsProvider).harmonyShareLocalName, '👩‍💻 Mac');
    expect(HarmonyShareService.instance.localName, '👩‍💻 Mac');
    expect(await ShareLocalName.resolve(), '👩‍💻 Mac');
    expect(
      main
          .read(appSettingsProvider)
          .copyWith(language: AppLanguage.en)
          .harmonyShareLocalName,
      '👩‍💻 Mac',
    );
    expect(calls.map((c) => c['method']), [
      'update_harmony_share_local_name',
      'change_harmony_share_local_name',
      'update_harmony_share_local_name',
    ]);
    await child.read(appSettingsProvider.notifier).setHarmonyShareLocalName(
      '迟到旧名称', broadcast: false,
    );
    expect(child.read(appSettingsProvider).harmonyShareLocalName, '👩‍💻 Mac');
    expect(store.writes, 2);
  });

  test('子窗口请求在主窗口传输期间被拒绝，不写盘或改变任何窗口', () async {
    HarmonyShareService.instance.busy = true;
    await expectLater(
      child.read(appSettingsProvider.notifier).setHarmonyShareLocalName('新名称'),
      throwsA(isA<WindowChannelException>()),
    );
    expect(store.writes, 0);
    expect(main.read(appSettingsProvider).harmonyShareLocalName, 'AnyDeck');
    expect(child.read(appSettingsProvider).harmonyShareLocalName, 'AnyDeck');
    expect(await ShareLocalName.resolve(), 'AnyDeck');
  });

  for (final throws in [false, true]) {
    test('名称写入${throws ? "异常" : "失败"}恢复缓存与显示，且不广播成功', () async {
      await main
          .read(appSettingsProvider.notifier)
          .setHarmonyShareLocalName('旧名称');
      calls.clear();
      store.fail = !throws;
      store.throwFailure = throws;
      await expectLater(
        main.read(appSettingsProvider.notifier).setHarmonyShareLocalName('新名称'),
        throwsStateError,
      );
      expect(main.read(appSettingsProvider).harmonyShareLocalName, '旧名称');
      expect(child.read(appSettingsProvider).harmonyShareLocalName, '旧名称');
      expect(HarmonyShareService.instance.localName, '旧名称');
      expect(HarmonyShareService.instance.configuring, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(HarmonySharePreferenceKeys.localName), '旧名称');
      expect(await ShareLocalName.resolve(), '旧名称');
      expect(calls, isEmpty);
    });
  }
}
