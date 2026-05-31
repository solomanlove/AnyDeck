import 'package:flutter/material.dart';
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
  showTouchesEnabled: false,
  pointerLocationEnabled: false,
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
        devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
        deviceRegistryProvider.overrideWith(_FixedDeviceRegistryNotifier.new),
        selectedDeviceProvider.overrideWith(_FixedSelectedDeviceNotifier.new),
        selectedToolTabProvider.overrideWith(
          () => _FixedToolTabNotifier(selectedTool),
        ),
        packagesProvider(
          _mockDevice.id,
        ).overrideWith((ref) => Future.value(<AdbPackage>[])),
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
  return tester.widget<Icon>(find.byIcon(Icons.more_horiz));
}

Finder _settingsButton() {
  return find.byWidgetPredicate(
    (widget) => widget is Icon && widget.icon == Icons.settings_outlined,
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

    expect(find.text('手机管理'), findsOneWidget);
    expect(find.text('设备管理'), findsWidgets);
    expect(find.text('选择设备'), findsNothing);
  });

  testWidgets('rail shows all tools when height is enough', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 900));

    expect(find.byIcon(Icons.phone_android_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byIcon(Icons.apps_outlined), findsWidgets);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(find.byIcon(Icons.terminal_outlined), findsOneWidget);
    expect(find.byIcon(Icons.analytics_outlined), findsOneWidget);
    expect(find.byIcon(Icons.web_outlined), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('rail stays visible when width is narrow', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(700, 900));

    expect(find.byIcon(Icons.phone_android_outlined), findsOneWidget);
    expect(find.byIcon(Icons.apps_outlined), findsWidgets);
    expect(_settingsButton(), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('rail moves trailing tools into more menu as height shrinks', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 560));

    expect(find.byIcon(Icons.phone_android_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byIcon(Icons.apps_outlined), findsWidgets);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(find.byIcon(Icons.terminal_outlined), findsNothing);
    expect(find.byIcon(Icons.analytics_outlined), findsNothing);
    expect(find.byIcon(Icons.web_outlined), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.terminal_outlined), findsOneWidget);
    expect(find.byIcon(Icons.analytics_outlined), findsOneWidget);
    expect(find.byIcon(Icons.web_outlined), findsOneWidget);
  });

  testWidgets('rail keeps collapsing tools gradually at lower heights', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 440));

    expect(find.byIcon(Icons.phone_android_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byIcon(Icons.apps_outlined), findsWidgets);
    expect(find.byIcon(Icons.folder_outlined), findsNothing);
    expect(find.byIcon(Icons.article_outlined), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(find.byIcon(Icons.terminal_outlined), findsOneWidget);
    expect(find.byIcon(Icons.analytics_outlined), findsOneWidget);
    expect(find.byIcon(Icons.web_outlined), findsOneWidget);
  });

  testWidgets('more button is selected only when selected tool is collapsed', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(1200, 560), selectedTool: 7);
    expect(_moreIcon(tester).color, const Color(0xff09c47c));

    await _pumpDashboard(tester, size: const Size(1200, 560), selectedTool: 2);
    expect(_moreIcon(tester).color, const Color(0xff5f6b6e));
  });

  testWidgets('overview cards do not overflow when width is extremely narrow', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, size: const Size(160, 800), selectedTool: 0);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.phone_android_outlined), findsWidgets);
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
          devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
          deviceRegistryProvider.overrideWith(_FixedDeviceRegistryNotifier.new),
          selectedDeviceProvider.overrideWith(_StaleSelectedDeviceNotifier.new),
          selectedToolTabProvider.overrideWith(() => _FixedToolTabNotifier(0)),
          deviceOverviewProvider(
            _mockDevice.id,
          ).overrideWith((ref) => Stream.value(_mockOverview)),
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

    expect(find.text('device'), findsOneWidget);
    expect(find.text('offline'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
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
