import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:adb_manage/app/adb_manage_app.dart';
import 'package:adb_manage/core/adb/adb_device.dart';
import 'package:adb_manage/core/apps/adb_package.dart';
import 'package:adb_manage/core/device_info/device_overview.dart';
import 'package:adb_manage/core/emulator/android_emulator.dart';
import 'package:adb_manage/core/providers/app_providers.dart';
import 'package:adb_manage/core/process/process_service.dart';
import 'package:adb_manage/core/web_debug/webpage_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adb_manage/features/dashboard/presentation/dashboard_screen.dart';

import 'fake_adb_service.dart';

class MockPackagesNotifier extends PackagesNotifier {
  MockPackagesNotifier(this.packages) : super('');
  final List<AdbPackage> packages;

  @override
  AsyncValue<List<AdbPackage>> build() {
    return AsyncValue.data(packages);
  }
}

const _mockDevice = AdbDevice(
  id: 'mock_serial_123',
  status: 'device',
  model: 'Redmi K40',
  product: 'alioth',
  transportId: '1',
);

const _offlineMockDevice = AdbDevice(
  id: 'mock_serial_123',
  status: 'offline',
  model: 'Redmi K40',
  product: 'alioth',
  transportId: '1',
);

final _mockRegisteredDevice = RegisteredDevice(
  id: _mockDevice.id,
  status: _mockDevice.status,
  model: _mockDevice.model,
  product: _mockDevice.product,
  transportId: _mockDevice.transportId,
  isOnline: true,
  serial: _mockDevice.id,
);

final _offlineMockRegisteredDevice = RegisteredDevice(
  id: _offlineMockDevice.id,
  status: _offlineMockDevice.status,
  model: _offlineMockDevice.model,
  product: _offlineMockDevice.product,
  transportId: _offlineMockDevice.transportId,
  isOnline: false,
  serial: _offlineMockDevice.id,
);

const _mockOverview = DeviceOverview(
  name: 'Redmi K40',
  brand: 'Redmi',
  model: 'M2012K11AC',
  serial: 'mock_serial_123',
  androidId: 'abcdef1234567890',
  androidVersion: 'Android 13 (API 33)',
  kernelVersion: '4.19.157',
  processor: 'alioth 6 cores (arm64-v8a)',
  storage: '202.92G / 225.43G',
  memory: '11.24G',
  physicalResolution: '1080x2400 (440dpi)',
  resolution: '1080x2400 (440dpi)',
  logicalDensity: '2.75x (xxhdpi)',
  refreshRate: '120 Hz',
  fontScale: '1x',
  wifi: 'jie',
  wifiEnabled: true,
  ipAddress: '192.168.31.54',
  macAddress: '6c:f7:84:80:c9:33',
  airplaneModeEnabled: false,
  mobileDataEnabled: true,
  talkbackEnabled: false,
  windowAnimationScale: '1.0',
  transitionAnimationScale: '1.0',
  animatorDurationScale: '1.0',
  rawResolution: '1080x2400',
  hwuiProfile: 'false',
  layoutBoundsEnabled: false,
  showTouchesEnabled: false,
  pointerLocationEnabled: false,
  demoModeEnabled: false,
);

class _FixedSelectedDeviceNotifier extends SelectedDeviceNotifier {
  @override
  AdbDevice? build() => _mockDevice;
}

class _OfflineSelectedDeviceNotifier extends SelectedDeviceNotifier {
  @override
  AdbDevice? build() => _offlineMockDevice;
}

class _StaleSelectedDeviceNotifier extends SelectedDeviceNotifier {
  @override
  AdbDevice? build() => _offlineMockDevice;
}

class _FixedDeviceRegistryNotifier extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [_mockRegisteredDevice];
}

class _OfflineDeviceRegistryNotifier extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [_offlineMockRegisteredDevice];
}

class _FixedToolTabNotifier extends ToolTabNotifier {
  _FixedToolTabNotifier(this.initialIndex);

  final int initialIndex;

  @override
  int build() => initialIndex;
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Size size,
  int selectedTool = 2,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        adbServiceProvider.overrideWithValue(FakeAdbService()),
        devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
        deviceRegistryProvider.overrideWith(_FixedDeviceRegistryNotifier.new),
        selectedDeviceProvider.overrideWith(_FixedSelectedDeviceNotifier.new),
        selectedToolTabProvider.overrideWith(
          () => _FixedToolTabNotifier(selectedTool),
        ),
        packagesProvider(
          _mockDevice.id,
        ).overrideWith(() => MockPackagesNotifier(<AdbPackage>[])),
        deviceOverviewProvider(
          _mockDevice.id,
        ).overrideWith((ref) => Stream.value(_mockOverview)),
        webTargetsProvider(
          _mockDevice.id,
        ).overrideWith((ref) => Future.value(<WebpageTarget>[])),
        emulatorListProvider.overrideWith(
          (ref) => Future.value(<AndroidEmulator>[]),
        ),
        runningEmulatorsProvider.overrideWith(
          (ref) => Future.value(<String, String>{}),
        ),
      ],
      child: const AdbManageApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Icon _moreIcon(WidgetTester tester) {
  return tester.widget<Icon>(
    find.byWidgetPredicate(
      (w) => w is Icon && w.icon == CupertinoIcons.ellipsis && w.size == 24.0,
    ),
  );
}

Finder _settingsButton({double? size = 24.0}) {
  return find.byWidgetPredicate(
    (w) => w is Icon && w.icon == CupertinoIcons.settings && w.size == size,
  );
}

Finder _railIcon(IconData icon, {double? size = 24.0}) {
  return find.byWidgetPredicate(
    (w) => w is Icon && w.icon == icon && w.size == size,
  );
}

/// 桌面外壳基础冒烟测试，测试中会 mock adb 设备轮询。
void main() {
  testWidgets('shows AdbManage shell in Chinese by default', (
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
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
          emulatorListProvider.overrideWith(
            (ref) => Future.value(<AndroidEmulator>[]),
          ),
          runningEmulatorsProvider.overrideWith(
            (ref) => Future.value(<String, String>{}),
          ),
        ],
        child: const AdbManageApp(),
      ),
    );

    expect(find.text('手机管理'), findsNWidgets(2));
    expect(find.text('设备标识'), findsOneWidget);
    expect(find.text('选择设备'), findsNothing);
  });

  testWidgets('rail shows all tools when height is enough', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 900));

    expect(_railIcon(CupertinoIcons.device_phone_portrait), findsOneWidget);
    expect(_railIcon(CupertinoIcons.slider_horizontal_3), findsOneWidget);
    expect(_railIcon(CupertinoIcons.square_grid_2x2), findsOneWidget);
    expect(_railIcon(CupertinoIcons.folder), findsOneWidget);
    expect(_railIcon(CupertinoIcons.doc_text), findsOneWidget);
    expect(
      _railIcon(CupertinoIcons.chevron_left_slash_chevron_right),
      findsOneWidget,
    );
    expect(_railIcon(CupertinoIcons.list_bullet), findsOneWidget);
    expect(_railIcon(CupertinoIcons.globe), findsOneWidget);
    expect(_railIcon(CupertinoIcons.ellipsis), findsNothing);
  });

  testWidgets('rail stays visible when width is narrow', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(700, 900));

    expect(
      _railIcon(CupertinoIcons.device_phone_portrait, size: null),
      findsOneWidget,
    );
    expect(
      _railIcon(CupertinoIcons.square_grid_2x2, size: null),
      findsOneWidget,
    );
    expect(_settingsButton(size: null), findsOneWidget);
    expect(_railIcon(CupertinoIcons.ellipsis, size: 28.0), findsNothing);
  });

  testWidgets('rail moves trailing tools into more menu as height shrinks', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 500));

    expect(_railIcon(CupertinoIcons.device_phone_portrait), findsOneWidget);
    expect(_railIcon(CupertinoIcons.slider_horizontal_3), findsOneWidget);
    expect(_railIcon(CupertinoIcons.square_grid_2x2), findsOneWidget);
    expect(_railIcon(CupertinoIcons.folder), findsOneWidget);
    expect(_railIcon(CupertinoIcons.doc_text), findsOneWidget);
    expect(
      _railIcon(CupertinoIcons.chevron_left_slash_chevron_right),
      findsNothing,
    );
    expect(_railIcon(CupertinoIcons.list_bullet), findsNothing);
    expect(_railIcon(CupertinoIcons.globe), findsNothing);
    expect(_railIcon(CupertinoIcons.ellipsis), findsOneWidget);

    await tester.tap(_railIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(CupertinoIcons.chevron_left_slash_chevron_right),
      findsWidgets,
    );
    expect(find.byIcon(CupertinoIcons.list_bullet), findsWidgets);
    expect(find.byIcon(CupertinoIcons.globe), findsWidgets);
  });

  testWidgets('rail keeps collapsing tools gradually at lower heights', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 380));

    expect(_railIcon(CupertinoIcons.device_phone_portrait), findsOneWidget);
    expect(_railIcon(CupertinoIcons.slider_horizontal_3), findsOneWidget);
    expect(_railIcon(CupertinoIcons.square_grid_2x2), findsOneWidget);
    expect(_railIcon(CupertinoIcons.folder), findsNothing);
    expect(_railIcon(CupertinoIcons.doc_text), findsNothing);
    expect(_railIcon(CupertinoIcons.ellipsis), findsOneWidget);

    await tester.tap(_railIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.folder), findsWidgets);
    expect(find.byIcon(CupertinoIcons.doc_text), findsWidgets);
    expect(
      find.byIcon(CupertinoIcons.chevron_left_slash_chevron_right),
      findsWidgets,
    );
    expect(find.byIcon(CupertinoIcons.list_bullet), findsWidgets);
    expect(find.byIcon(CupertinoIcons.globe), findsWidgets);
  });

  testWidgets('more button is selected only when selected tool is collapsed', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 500), selectedTool: 7);
    expect(_moreIcon(tester).color, const Color(0xff09c47c));

    await _pumpDashboard(tester, size: const Size(1200, 500), selectedTool: 2);
    expect(_moreIcon(tester).color, const Color(0xff5f6b6e));
  });

  testWidgets('overview cards do not overflow when width is extremely narrow', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(160, 800), selectedTool: 0);

    expect(tester.takeException(), isNull);
    expect(
      _railIcon(CupertinoIcons.device_phone_portrait, size: null),
      findsOneWidget,
    );
  });

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
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
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
        child: const AdbManageApp(),
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
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
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
        child: const AdbManageApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('手机离线，无法读取进程列表'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
