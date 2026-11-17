import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/devices/widgets/device_wall_card.dart';
import 'package:any_deck/features/devices/widgets/host_network_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

/// 使用真实 Dashboard 的视图与选择链路，避免通过独立 Widget 代替集成行为。
class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [
    RegisteredDevice(
      id: 'workspace-alpha',
      serial: 'workspace-alpha',
      model: 'Alpha Phone',
      androidVersion: 'Android 15',
      status: 'device',
      isOnline: true,
    ),
    RegisteredDevice(
      id: 'workspace-beta',
      serial: 'workspace-beta',
      model: 'Beta Phone',
      androidVersion: 'Android 13',
      status: 'offline',
      isOnline: false,
    ),
  ];

  // 注册表探测已被桩替换，勾选仍发布同一设备集合供真实 UI 订阅。
  @override
  void toggleCheck(String id) {
    state = [
      for (final device in state)
        if (device.id == id)
          device.copyWith(isChecked: !device.isChecked)
        else
          device,
    ];
  }
}

class _HostNetwork extends HostNetworkNotifier {
  @override
  Future<HostNetworkInfo> build() async => const HostNetworkInfo(
    wifiStatus: HostWifiStatus.connected,
    ssid: 'AnyDeck-QA',
    address: HostNetworkAddress('en0', '192.168.1.100'),
    isWifiAddress: true,
  );
}

class _Ios extends IosDeviceService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
}

class _ReadyAdb extends AdbEnvironmentNotifier {
  @override
  AdbEnvironmentInfo build() =>
      const AdbEnvironmentInfo(status: AdbEnvironmentStatus.ready);

  @override
  Future<void> checkAndPromptIfNeeded(BuildContext context) async {}
}

Future<ProviderContainer> _pumpDashboard(
  WidgetTester tester, {
  String language = 'zh',
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      adbServiceProvider.overrideWithValue(FakeAdbService()),
      iosDeviceServiceProvider.overrideWithValue(_Ios()),
      discoveredDevicesProvider.overrideWith((ref) => Stream.value([])),
      deviceRegistryProvider.overrideWith(_Registry.new),
      for (final id in ['workspace-alpha', 'workspace-beta'])
        cachedDeviceOverviewProvider(id).overrideWith(
          (ref) async => DeviceOverview.fromJson({
            'name': id.endsWith('alpha') ? 'Alpha Phone' : 'Beta Phone',
            'brand': 'Android',
          }),
        ),
      hostNetworkProvider.overrideWith(_HostNetwork.new),
      adbEnvironmentProvider.overrideWith(_ReadyAdb.new),
      emulatorListProvider.overrideWith((ref) async => []),
      emulatorConnectionsProvider.overrideWith((ref) async => {}),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(appRouterProvider),
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildAppTheme(brightness),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  setUp(
    () => messenger.setMockMethodCallHandler(
      windows,
      (call) async => call.method == 'getAllWindows' ? <Object>[] : null,
    ),
  );
  tearDown(() => messenger.setMockMethodCallHandler(windows, null));

  testWidgets('默认手机墙和列表无多选，视图切换保留搜索和离线筛选', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpDashboard(tester);
    expect(find.byType(DeviceWallCard), findsNWidgets(2));
    expect(find.byType(Checkbox), findsNothing);
    expect(
      find.byKey(const ValueKey('device-row-workspace-alpha')),
      findsNothing,
    );
    final search = find.byKey(const Key('deviceListSearch'));
    await tester.enterText(search, 'beta');
    await tester.tap(find.byKey(const Key('deviceFilter-offline')));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceWallCard), findsOneWidget);
    expect(
      tester.widget<DeviceWallCard>(find.byType(DeviceWallCard)).name,
      'Beta Phone',
    );
    await tester.tap(find.byKey(const Key('deviceView-list')));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceWallCard), findsNothing);
    expect(
      find.byKey(const ValueKey('device-row-workspace-beta')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('device-row-workspace-alpha')),
      findsNothing,
    );
    expect(tester.widget<TextField>(search).controller!.text, 'beta');
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byKey(const Key('deviceView-wall')));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceWallCard), findsOneWidget);
    expect(
      tester.widget<DeviceWallCard>(find.byType(DeviceWallCard)).online,
      isFalse,
    );
    expect(tester.widget<TextField>(search).controller!.text, 'beta');
    await tester.tap(find.byKey(const ValueKey('services-diagnostics-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('services-diagnostics-panel')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('services-diagnostics-panel')),
      findsNothing,
    );
    expect(tester.widget<TextField>(search).controller!.text, 'beta');
    expect(find.byType(DeviceWallCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量勾选跨视图筛选保留，退出批量清空注册表并隐藏多选', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await _pumpDashboard(tester);
    await tester.tap(find.byKey(const Key('deviceView-list')));
    await tester.tap(find.byKey(const Key('deviceBatchManage')));
    await tester.pumpAndSettle();
    final beta = find.byKey(const ValueKey('device-row-workspace-beta'));
    await tester.tap(
      find.descendant(of: beta, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(
      container
          .read(deviceRegistryProvider)
          .singleWhere((device) => device.id == 'workspace-beta')
          .isChecked,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('deviceView-wall')));
    await tester.pumpAndSettle();
    final betaCard = find.byKey(const ValueKey('device-wall-workspace-beta'));
    expect(tester.widget<DeviceWallCard>(betaCard).selected, isTrue);
    await tester.tap(find.byKey(const Key('deviceFilter-online')));
    await tester.enterText(find.byKey(const Key('deviceListSearch')), 'alpha');
    await tester.pumpAndSettle();
    expect(find.byType(DeviceWallCard), findsOneWidget);
    expect(find.textContaining('其中 1 台不在当前结果中'), findsOneWidget);
    expect(
      container.read(deviceRegistryProvider).where((d) => d.isChecked).length,
      1,
    );
    await tester.tap(find.byKey(const Key('deviceBatchManage')));
    await tester.pumpAndSettle();
    expect(
      container.read(deviceRegistryProvider).every((d) => !d.isChecked),
      isTrue,
    );
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byKey(const Key('deviceView-list')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('device-row-workspace-alpha')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('device-row-workspace-beta')),
      findsNothing,
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('deviceListSearch')))
          .controller!
          .text,
      'alpha',
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('底栏在视图、页面和控制台切换后持续可见 $language $brightness', (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = await _pumpDashboard(
          tester,
          language: language,
          brightness: brightness,
        );
        final l10n = AppLocalizations(Locale(language));
        final ip = find.textContaining('192.168.1.100');
        expect(ip, findsOneWidget);
        final baseTheme = buildAppTheme(brightness);
        final deviceTheme = Theme.of(tester.element(find.byType(HostNetworkFooter)));
        // 设备管理使用原型中性底色，同时保留用户选择的主色。
        expect(deviceTheme.colorScheme.primary, baseTheme.colorScheme.primary);
        expect(deviceTheme.colorScheme.surface,
            brightness == Brightness.dark ? const Color(0xff17181d) : Colors.white);
        final initialFooter = tester.getRect(find.byType(HostNetworkFooter));
        await tester.tap(find.byTooltip(l10n.t('console')));
        await tester.pumpAndSettle();
        final console = tester.getRect(
          find.byKey(const Key('consoleDockPanel')),
        );
        final footer = tester.getRect(find.byType(HostNetworkFooter));
        expect(footer.bottom, closeTo(initialFooter.bottom, 0.1));
        expect(console.bottom, lessThanOrEqualTo(footer.top));
        expect(ip.hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(const Key('deviceView-list')));
        await tester.pumpAndSettle();
        expect(ip.hitTestable(), findsOneWidget);
        container.read(appRouterProvider).goNamed(AppRouteNames.emulators);
        await tester.pumpAndSettle();
        expect(ip.hitTestable(), findsOneWidget);
        // 离开设备管理后恢复原应用主题，局部配色不泄漏到其他工具。
        expect(Theme.of(tester.element(find.byType(HostNetworkFooter))).colorScheme,
            baseTheme.colorScheme);
        expect(find.byKey(const Key('consoleDockPanel')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
