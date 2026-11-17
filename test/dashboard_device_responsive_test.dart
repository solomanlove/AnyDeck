import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/core/receiver/receiver_identity.dart';
import 'package:any_deck/features/devices/widgets/device_wall_card.dart';
import 'package:any_deck/app/window/widget/desktop_workspace_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

/// 在完整主窗口内验证断点，避免以局部容器宽度代替整窗宽度。
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

  for (final width in [1200.0, 730.0, 650.0, 490.0, 320.0]) {
    testWidgets('${width.toInt()}px 设备墙与列表遵循原型断点且不横向溢出', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpDashboard(tester);
      expect(tester.takeException(), isNull);
      final wall = tester.getRect(find.byKey(const Key('deviceWall')));
      final header = tester.getRect(find.byType(DesktopWorkspaceSurface));
      if (width == 1200) {
        // 桌面头部保持紧凑，避免装饰留白挤占设备展示区域。
        expect(tester.getSize(find.byKey(const Key('deviceManagementHeader'))).height,
            lessThanOrEqualTo(84));
      }
      final padding = width <= 490
          ? 8
          : width <= 650
          ? 12
          : 16;
      expect(wall.left - header.left, closeTo(padding, 0.1));
      final alpha = tester.getRect(
        find.byKey(const ValueKey('device-wall-responsive-alpha')),
      );
      final beta = tester.getRect(
        find.byKey(const ValueKey('device-wall-responsive-beta')),
      );
      if (width <= 490) {
        expect(alpha.top, closeTo(beta.top, .1));
        expect(beta.left - alpha.right, closeTo(4, .1));
      }
      expect(alpha.left, greaterThanOrEqualTo(0));
      expect(beta.right, lessThanOrEqualTo(width));
      expect(
        tester
            .widget<DeviceWallCard>(
              find.byKey(const ValueKey('device-wall-responsive-alpha')),
            )
            .ipAddress,
        '192.168.1.219',
      );

      await tester.tap(find.byKey(const Key('deviceView-list')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('deviceTableHeader')),
        width <= 490 ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('device-system-inline-responsive-alpha')),
        width <= 730 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('device-system-column-responsive-alpha')),
        width > 730 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('device-status-column-responsive-alpha')),
        width > 490 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('device-status-inline-responsive-alpha')),
        width <= 490 ? findsOneWidget : findsNothing,
      );
      if (width > 490) {
        final status = tester.getSize(
          find.byKey(const ValueKey('device-status-column-responsive-alpha')),
        );
        expect(status.width, 80);
      }
      expect(find.text('192.168.1.219'), findsOneWidget);
      final row = tester.getRect(
        find.byKey(const ValueKey('device-row-responsive-alpha')),
      );
      if (width > 730) expect(row.height, lessThanOrEqualTo(64));
      expect(row.left, greaterThanOrEqualTo(0));
      expect(row.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('320px 英文放大字体列表在${brightness.name}主题保持可用', (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpDashboard(
        tester,
        language: 'en',
        brightness: brightness,
        textScale: 1.6,
      );
      await tester.tap(find.byKey(const Key('deviceView-list')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deviceTableHeader')), findsNothing);
      expect(
        find.byKey(const ValueKey('device-status-inline-responsive-alpha')),
        findsOneWidget,
      );
      expect(find.text('Reconnect'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final listMode in [false, true]) {
    testWidgets('离线模拟器在${listMode ? '列表' : '手机墙'}中显示启动并进入模拟器管理', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await _pumpDashboard(tester);
      (container.read(deviceRegistryProvider.notifier) as _Registry)
          .addEmulator();
      await tester.pumpAndSettle();
      if (listMode) {
        await tester.tap(find.byKey(const Key('deviceView-list')));
        await tester.pumpAndSettle();
      }
      final emulator = find.byKey(
        ValueKey(
          listMode ? 'device-row-emulator-5554' : 'device-wall-emulator-5554',
        ),
      );
      await tester.tap(
        find.descendant(of: emulator, matching: find.text('启动')),
      );
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/emulators',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('批量模式禁用设备墙右键，清除空结果保留视图和已选设备', (tester) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await _pumpDashboard(tester);
    await tester.tap(find.byKey(const Key('deviceBatchManage')));
    await tester.pumpAndSettle();
    final alpha = find.byKey(const ValueKey('device-wall-responsive-alpha'));
    final card = tester.widget<DeviceWallCard>(alpha);
    expect(card.onSecondaryTapDown, isNull);
    await tester.tap(
      find.descendant(of: alpha, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deviceFilter-offline')));
    await tester.enterText(
      find.byKey(const Key('deviceListSearch')),
      'not-present',
    );
    await tester.pumpAndSettle();
    expect(find.byType(DeviceWallCard), findsNothing);
    await tester.tap(find.byKey(const Key('deviceResetFilters')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('deviceListSearch')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('deviceWall')), findsOneWidget);
    expect(find.byType(DeviceWallCard), findsNWidgets(2));
    expect(tester.widget<DeviceWallCard>(alpha).batchMode, isTrue);
    expect(tester.widget<DeviceWallCard>(alpha).selected, isTrue);
    expect(container.read(deviceRegistryProvider).first.isChecked, isTrue);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('deviceListSearch')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

class _Registry extends DeviceRegistryNotifier {
  void addEmulator() {
    state = [
      ...state,
      const RegisteredDevice(
        id: 'emulator-5554',
        model: 'Android Emulator',
        status: 'offline',
        isOnline: false,
      ),
    ];
  }

  @override
  void toggleCheck(String id) {
    state = state
        .map(
          (device) => device.id == id
              ? device.copyWith(isChecked: !device.isChecked)
              : device,
        )
        .toList();
  }

  @override
  List<RegisteredDevice> build() => const [
    RegisteredDevice(
      id: 'responsive-alpha',
      serial: 'responsive-alpha',
      model: 'Alpha Phone',
      androidVersion: 'Android 15',
      status: 'device',
      isOnline: true,
      ipAddress: '192.168.1.31',
    ),
    RegisteredDevice(
      id: 'responsive-beta',
      serial: 'responsive-beta',
      model: 'Beta Phone',
      androidVersion: 'Android 13',
      status: 'offline',
      isOnline: false,
      ipAddress: '192.168.1.32',
    ),
  ];
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
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      receiverIdentityProvider.overrideWith(
        (ref) async => const ReceiverIdentity(
          uuid: '00000000-0000-4000-8000-000000000000',
          computerName: 'AnyDeck QA',
        ),
      ),
      adbServiceProvider.overrideWithValue(FakeAdbService()),
      iosDeviceServiceProvider.overrideWithValue(_Ios()),
      discoveredDevicesProvider.overrideWith((ref) => Stream.value([])),
      deviceRegistryProvider.overrideWith(_Registry.new),
      for (final id in ['responsive-alpha', 'responsive-beta'])
        cachedDeviceOverviewProvider(id).overrideWith(
          (ref) async => DeviceOverview.fromJson({
            'name': id.endsWith('alpha') ? 'Alpha Phone' : 'Beta Phone',
            'brand': 'Android',
            'ipAddress': id.endsWith('alpha')
                ? '192.168.1.219'
                : '192.168.1.220',
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
