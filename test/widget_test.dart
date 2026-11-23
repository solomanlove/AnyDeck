import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:any_deck/app/theme/app_navigation_icons.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:any_deck/features/processes/processes_tab.dart';
import 'support/dashboard_test_environment.dart';
import 'package:any_deck/app/any_deck_app.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/process/process_service.dart';
import 'package:any_deck/core/web_debug/webpage_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:any_deck/features/dashboard_screen.dart';

import 'fake_adb_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';

part 'support/shell_smoke_fixture.dart';

/// 桌面外壳基础冒烟测试，测试中会 mock adb 设备轮询。
void main() {
  testWidgets('shows AnyDeck shell in Chinese by default', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...dashboardTestPlatformOverrides(),
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          iosDeviceServiceProvider.overrideWithValue(FakeIosDeviceService()),
          discoveredDevicesProvider.overrideWith((ref) => Stream.value(<DiscoveredDevice>[])),
          emulatorListProvider.overrideWith(
            (ref) => Future.value(<AndroidEmulator>[]),
          ),
          runningEmulatorsProvider.overrideWith(
            (ref) => Future.value(<String, String>{}),
          ),
        ],
        child: const AnyDeckApp(),
      ),
    );

    expect(find.text('AnyDeck'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('app-identity-labels')), findsOneWidget);
    expect(find.text('设备管理'), findsWidgets);
    expect(find.text('选择设备'), findsNothing);
  });

  testWidgets('rail shows all tools when height is enough', (
    WidgetTester tester,
  ) async {
    // 为固定返回入口多留 44px 后，原本能完整展开的工具仍应全部可见。
    await _pumpDashboard(tester, size: const Size(1200, 944));

    expect(find.byTooltip('返回设备管理').hitTestable(), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.overview), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.control), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.apps), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.files), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.logs), findsOneWidget);
    expect(
      _railIcon(AppNavigationIcons.terminal),
      findsOneWidget,
    );
    expect(_railIcon(AppNavigationIcons.processes), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.web), findsOneWidget);
    expect(_railIcon(CupertinoIcons.ellipsis), findsNothing);
  });

  testWidgets('rail stays visible when width is narrow', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(700, 900));

    expect(
      _railIcon(AppNavigationIcons.overview, size: null),
      findsOneWidget,
    );
    expect(
      _railIcon(AppNavigationIcons.apps, size: null),
      findsOneWidget,
    );
    expect(_settingsButton(size: null), findsOneWidget);
    expect(_railIcon(CupertinoIcons.ellipsis), findsOneWidget);
  });

  testWidgets('rail moves trailing tools into more menu as height shrinks', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 500));

    expect(_railIcon(AppNavigationIcons.overview), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.control), findsOneWidget);
    expect(find.byTooltip('返回设备管理').hitTestable(), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.apps), findsNothing);
    expect(_railIcon(AppNavigationIcons.files), findsNothing);
    expect(_railIcon(AppNavigationIcons.logs), findsNothing);
    expect(
      _railIcon(AppNavigationIcons.terminal),
      findsNothing,
    );
    expect(_railIcon(AppNavigationIcons.processes), findsNothing);
    expect(_railIcon(AppNavigationIcons.web), findsNothing);
    expect(_railIcon(CupertinoIcons.ellipsis), findsOneWidget);

    await tester.tap(_railIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();

    expect(find.byIcon(AppNavigationIcons.apps), findsWidgets);
    expect(
      find.byIcon(AppNavigationIcons.terminal),
      findsWidgets,
    );
    expect(find.byIcon(AppNavigationIcons.processes), findsWidgets);
    expect(find.byIcon(AppNavigationIcons.web), findsWidgets);
  });

  testWidgets('rail keeps collapsing tools gradually at lower heights', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 460));

    expect(_railIcon(AppNavigationIcons.overview), findsOneWidget);
    expect(find.byTooltip('返回设备管理').hitTestable(), findsOneWidget);
    expect(_railIcon(AppNavigationIcons.control), findsNothing);
    expect(_railIcon(AppNavigationIcons.apps), findsNothing);
    expect(_railIcon(AppNavigationIcons.files), findsNothing);
    expect(_railIcon(AppNavigationIcons.logs), findsNothing);
    expect(_railIcon(CupertinoIcons.ellipsis), findsOneWidget);

    await tester.tap(_railIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();

    expect(find.byIcon(AppNavigationIcons.control), findsWidgets);
    expect(find.byIcon(AppNavigationIcons.files), findsWidgets);
    expect(find.byIcon(AppNavigationIcons.logs), findsWidgets);
    expect(
      find.byIcon(AppNavigationIcons.terminal),
      findsWidgets,
    );
    expect(find.byIcon(AppNavigationIcons.processes), findsWidgets);
    expect(find.byIcon(AppNavigationIcons.web), findsWidgets);
  });

  testWidgets('more button is selected only when selected tool is collapsed', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 500), selectedTool: 7);
    expect(_moreIcon(tester).color, const Color(0xff09c47c));

    await _pumpDashboard(tester, size: const Size(1200, 500), selectedTool: 2);
    expect(_moreIcon(tester).color, const Color(0xff09c47c));

    // 应用在当前高度已折叠，控制仍位于侧栏内。
    await _pumpDashboard(tester, size: const Size(1200, 500), selectedTool: 1);
    expect(_moreIcon(tester).color, const Color(0xff455a64));
  });

  testWidgets('overview cards do not overflow when width is extremely narrow', (tester) async {
    tester.view.physicalSize = const Size(160, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: [
      ...dashboardTestPlatformOverrides(),
      deviceRootStatusProvider(_mockDevice.id).overrideWith((ref) async => false),
    ], child: _localizedPage(DeviceOverviewContent(
      device: _mockDevice, overview: _mockOverview, onRefresh: () {},
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceOverviewContent), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overview prioritizes version and storage without basic duplicates',
    (WidgetTester tester) async {
      await _pumpDashboard(
        tester,
        size: const Size(1200, 900),
        selectedTool: 0,
      );

      expect(find.text('Android 13'), findsOneWidget);
      expect(find.text('API 33'), findsOneWidget);
      expect(find.text('202.92G / 225.43G'), findsOneWidget);
      expect(find.text('已用 90%'), findsOneWidget);
      expect(find.text('基本信息'), findsNothing);
      expect(find.text('mock_serial_123'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected device status follows registry refresh', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...dashboardTestPlatformOverrides(),
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          iosDeviceServiceProvider.overrideWithValue(FakeIosDeviceService()),
          discoveredDevicesProvider.overrideWith((ref) => Stream.value(<DiscoveredDevice>[])),
          deviceRegistryProvider.overrideWith(_FixedDeviceRegistryNotifier.new),
          selectedDeviceProvider.overrideWith(_StaleSelectedDeviceNotifier.new),
          selectedToolTabProvider.overrideWith(() => _FixedToolTabNotifier(0)),
          deviceOverviewProvider(
            _mockDevice.id,
          ).overrideWith((ref) => Stream.value(_mockOverview)),
          packagesProvider(
            _mockDevice.id,
          ).overrideWith(() => MockPackagesNotifier(<AdbPackage>[])),
          emulatorListProvider.overrideWith(
            (ref) => Future.value(<AndroidEmulator>[]),
          ),
          runningEmulatorsProvider.overrideWith(
            (ref) => Future.value(<String, String>{}),
          ),
        ],
        child: const AnyDeckApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardScreen)),
    );
    expect(container.read(selectedDeviceProvider)?.status, 'device');
  });

  testWidgets('processes tab hides refresh ui when device is offline', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...dashboardTestPlatformOverrides(),
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          iosDeviceServiceProvider.overrideWithValue(FakeIosDeviceService()),
          discoveredDevicesProvider.overrideWith((ref) => Stream.value(<DiscoveredDevice>[])),
          deviceRegistryProvider.overrideWith(
            _OfflineDeviceRegistryNotifier.new,
          ),
          selectedDeviceProvider.overrideWith(
            _OfflineSelectedDeviceNotifier.new,
          ),
          selectedToolTabProvider.overrideWith(() => _FixedToolTabNotifier(6)),
          processesProvider(
            _offlineMockDevice.id,
          ).overrideWith((ref) => Future.value(<AdbProcess>[])),
          packagesProvider(
            _offlineMockDevice.id,
          ).overrideWith(() => MockPackagesNotifier(<AdbPackage>[])),
          emulatorListProvider.overrideWith(
            (ref) => Future.value(<AndroidEmulator>[]),
          ),
          runningEmulatorsProvider.overrideWith(
            (ref) => Future.value(<String, String>{}),
          ),
        ],
        child: _localizedPage(const ProcessesTab(device: _offlineMockDevice, isVisible: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('手机离线，无法读取进程列表'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
