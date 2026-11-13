import 'dart:async';

import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/receiver/receiver_identity.dart';
import 'package:any_deck/core/receiver/receiver_name_probe.dart';
import 'package:any_deck/core/receiver/receiver_names.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只验证名称初始化与设置持久化，不初始化播放器或其他应用设置。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const identity = ReceiverIdentity(
    uuid: 'a7b2c300-0000-4000-8000-000000000001',
    computerName: '办公室 Mac',
  );
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
      windows,
      (call) async => call.method == 'getAllWindows' ? <Object>[] : null,
    );
    messenger.setMockMethodCallHandler(channels, (call) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
  });

  ProviderContainer container({
    ReceiverNameProbe? probe,
    Future<ReceiverIdentity>? ready,
  }) {
    final value = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(_Settings.new),
        receiverIdentityProvider.overrideWith(
          (ref) => ready ?? Future.value(identity),
        ),
        if (probe != null) receiverNameProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(value.dispose);
    return value;
  }

  test('名称初始化完成前提交自定义名不会被异步默认值覆盖，清空恢复本机名', () async {
    final ready = Completer<ReceiverIdentity>();
    final scope = container(ready: ready.future);
    final settings = scope.read(appSettingsProvider.notifier);
    final saving = settings.setAirplayServerName('自定义会议室');
    ready.complete(identity);
    await saving;
    expect(scope.read(appSettingsProvider).airplayServerName, '自定义会议室');
    await settings.setAirplayServerName('   ');
    expect(
      scope.read(appSettingsProvider).airplayServerName,
      'AnyDeck-办公室 Mac-AirPlay',
    );
    expect(
      scope.read(appSettingsProvider).defaultDlnaReceiverName,
      'AnyDeck-办公室 Mac-DLNA',
    );
  });

  test('检测重名后自动名固定追加短码，重启不再扫描或改变名称', () async {
    var probes = 0;
    final probe = ReceiverNameProbe(
      isMacOS: true,
      bonjourRunner: (_) async {
        probes++;
        return [
          '10:00:00.000 Add 2 4 local. _airplay._tcp. AnyDeck-办公室 Mac-AirPlay',
        ];
      },
    );
    final first = container(probe: probe);
    final actual = await first
        .read(appSettingsProvider.notifier)
        .receiverNameForStart('AirPlay');
    expect(actual, 'AnyDeck-办公室 Mac-A7B2C3-AirPlay');
    expect(first.read(appSettingsProvider).airplayServerName, actual);
    final second = container(probe: probe);
    expect(
      await second
          .read(appSettingsProvider.notifier)
          .receiverNameForStart('AirPlay'),
      actual,
    );
    expect(probes, 1);
  });

  test('自定义重名只调整广播名，保留设置与恢复默认入口', () async {
    SharedPreferences.setMockInitialValues({
      ReceiverNames.nameKey('AirPlay'): '会议室',
    });
    final scope = container(
      probe: ReceiverNameProbe(
        isMacOS: true,
        bonjourRunner: (_) async => [
          '10:00:00.000 Add 2 4 local. _airplay._tcp. 会议室',
        ],
      ),
    );
    expect(
      await scope
          .read(appSettingsProvider.notifier)
          .receiverNameForStart('AirPlay'),
      '会议室-A7B2C3',
    );
    expect(scope.read(appSettingsProvider).airplayServerName, '会议室');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ReceiverNames.nameKey('AirPlay')), '会议室');
  });

  test('异步注册回调升级稳定码后，默认名重启不降级且自定义名不被覆盖', () async {
    final first = container();
    final settings = first.read(appSettingsProvider.notifier);
    await settings.ensureReceiverNames();
    final original = first.read(appSettingsProvider).airplayServerName;
    final short = await settings.receiverNameFallbackForStart('AirPlay');
    await settings.recordReceiverNameConflict(
      'AirPlay',
      original,
      publishedName: short,
    );
    final longer = await settings.receiverNameFallbackForStart(
      'AirPlay',
      codeLength: 12,
    );
    await settings.recordReceiverNameConflict(
      'AirPlay',
      short,
      publishedName: longer,
    );
    expect(first.read(appSettingsProvider).airplayServerName, longer);
    final restarted = container();
    final next = restarted.read(appSettingsProvider.notifier);
    expect(await next.receiverNameForStart('AirPlay'), longer);
    expect(await next.receiverNameFallbackForStart('AirPlay'), longer);
    final full = await next.receiverNameFallbackForStart(
      'AirPlay',
      codeLength: 32,
    );
    await next.recordReceiverNameConflict(
      'AirPlay',
      short,
      publishedName: full,
    );
    final third = container();
    expect(
      await third
          .read(appSettingsProvider.notifier)
          .receiverNameForStart('AirPlay'),
      full,
    );

    await settings.setAirplayServerName('自定义会议室');
    final customFallback = await settings.receiverNameFallbackForStart(
      'AirPlay',
      codeLength: 12,
    );
    final customShort = await settings.receiverNameFallbackForStart('AirPlay');
    await settings.recordReceiverNameConflict(
      'AirPlay',
      customShort,
      publishedName: customFallback,
    );
    expect(first.read(appSettingsProvider).airplayServerName, '自定义会议室');
    expect(await settings.receiverNameForStart('AirPlay'), customFallback);
    final customRestart = container();
    expect(
      await customRestart
          .read(appSettingsProvider.notifier)
          .receiverNameForStart('AirPlay'),
      customFallback,
    );
  });

  test('启动前重新读取最终设置，探测过程中改名不启动过期名称', () async {
    final waiting = Completer<List<String>>();
    final scope = container(
      probe: ReceiverNameProbe(
        isMacOS: true,
        bonjourRunner: (_) => waiting.future,
      ),
    );
    final settings = scope.read(appSettingsProvider.notifier);
    await settings.ensureReceiverNames();
    final starting = settings.receiverNameForStart('AirPlay');
    await Future<void>.delayed(Duration.zero);
    await settings.setAirplayServerName('新会议室');
    waiting.complete([]);
    expect(await starting, '新会议室');
  });

  test('子窗口从主窗口读取默认名，名称修改由主窗口保存并返回快照', () async {
    final main = container();
    final controller = main.read(appSettingsProvider.notifier);
    await controller.ensureReceiverNames();
    Map<String, String> snapshot() {
      final value = main.read(appSettingsProvider);
      return {
        'airplay': value.airplayServerName,
        'dlna': value.dlnaServerName,
        'defaultAirplay': value.defaultAirplayReceiverName,
        'defaultDlna': value.defaultDlnaReceiverName,
      };
    }

    final methods = <String>[];
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method != 'invokeMethod') return null;
      final args = call.arguments as Map;
      final method = args['method'] as String;
      methods.add(method);
      if (method == 'change_receiver_name') {
        final value = args['arguments'] as Map;
        await controller.setAirplayServerName(value['value'] as String);
      }
      return snapshot();
    });
    final child = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(_Settings.new),
        windowIdProvider.overrideWithValue('mirror'),
        receiverIdentityProvider.overrideWith(
          (ref) => throw StateError('Main owns identity'),
        ),
      ],
    );
    addTearDown(child.dispose);
    final childController = child.read(appSettingsProvider.notifier);
    await childController.ensureReceiverNames();
    expect(
      child.read(appSettingsProvider).defaultAirplayReceiverName,
      'AnyDeck-办公室 Mac-AirPlay',
    );
    await childController.setAirplayServerName('子窗口会议室');
    expect(main.read(appSettingsProvider).airplayServerName, '子窗口会议室');
    expect(child.read(appSettingsProvider).airplayServerName, '子窗口会议室');
    expect(methods, ['resolve_receiver_names', 'change_receiver_name']);
  });
}
