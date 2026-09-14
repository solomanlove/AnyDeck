import 'package:any_deck/app/any_deck_app.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/web_debug/webpage_target.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

class FakeIosDeviceService extends IosDeviceService {
  FakeIosDeviceService() : super();

  @override
  Future<List<AdbDevice>> listDevices() async {
    return [];
  }
}

class _FixedPackagesNotifier extends PackagesNotifier {
  _FixedPackagesNotifier(this.packages) : super('');
  final List<AdbPackage> packages;

  @override
  AsyncValue<List<AdbPackage>> build() => AsyncValue.data(packages);
}

const _mockDevice = AdbDevice(
  id: 'mock_serial_123',
  status: 'device',
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

const _mockOverview = DeviceOverview(
  name: 'Redmi K40',
  brand: 'Redmi',
  model: 'M2012K11AC',
  serial: 'mock_serial_123',
  androidId: 'abcdef1234567890',
  androidVersion: 'Android 13 (API 33)',
  kernelVersion: '4.19.157',
  processor: 'alioth 6 cores (arm64-v8a)',
  storage: '100G / 256G',
  memory: '8G',
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

class _FixedDeviceRegistryNotifier extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [_mockRegisteredDevice];
}

class _FixedToolTabNotifier extends ToolTabNotifier {
  @override
  int build() => 2; // Apps tab
}

void main() {
  testWidgets('apps tab filters user apps by default, and switches to system / all', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    final mockPackages = [
      const AdbPackage(
        name: 'com.tencent.mm',
        label: '微信',
        system: false,
        versionName: '8.0.0',
      ),
      const AdbPackage(
        name: 'com.eg.android.AlipayGphone',
        label: '支付宝',
        system: false,
        versionName: '10.2.0',
      ),
      const AdbPackage(
        name: 'com.android.settings',
        label: '设置',
        system: true,
        versionName: '13.0',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          iosDeviceServiceProvider.overrideWithValue(FakeIosDeviceService()),
          devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[_mockDevice])),
          deviceRegistryProvider.overrideWith(_FixedDeviceRegistryNotifier.new),
          selectedDeviceProvider.overrideWith(_FixedSelectedDeviceNotifier.new),
          selectedToolTabProvider.overrideWith(_FixedToolTabNotifier.new),
          packagesProvider(
            _mockDevice.id,
          ).overrideWith(() => _FixedPackagesNotifier(mockPackages)),
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
        child: const AnyDeckApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 默认选中“用户应用”
    expect(find.text('用户应用'), findsOneWidget);
    expect(find.text('系统应用'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);

    // 用户应用可见：微信、支付宝；系统应用设置不可见
    expect(find.text('微信'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('设置'), findsNothing);

    // 表头包含计数：共 2/3 个应用
    expect(find.textContaining('共 2/3 个应用'), findsOneWidget);

    // 切换到“系统应用”
    await tester.tap(find.text('系统应用'));
    await tester.pumpAndSettle();

    expect(find.text('微信'), findsNothing);
    expect(find.text('支付宝'), findsNothing);
    expect(find.text('设置'), findsOneWidget);
    expect(find.textContaining('共 1/3 个应用'), findsOneWidget);

    // 切换到“全部”
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(find.text('微信'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.textContaining('共 3/3 个应用'), findsOneWidget);
  });
}
