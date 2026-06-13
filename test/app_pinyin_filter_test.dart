import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:any_deck/app/any_deck_app.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'fake_adb_service.dart';

class MockPackagesNotifier extends PackagesNotifier {
  MockPackagesNotifier(this.packages) : super('');
  final List<AdbPackage> packages;

  @override
  AsyncValue<List<AdbPackage>> build() {
    return AsyncValue.data(packages);
  }
}

void main() {
  testWidgets('app list filters by pinyin (full pinyin and initials)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    final mockDevice = const AdbDevice(
      id: 'mock_serial_123',
      status: 'device',
      model: 'Redmi K40',
      product: 'alioth',
      transportId: '1',
    );

    final mockPackages = [
      const AdbPackage(
        name: 'com.ubrmb.app',
        label: '北京环球度假区',
        system: false,
        versionName: '1.0.0',
      ),
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
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          devicesProvider.overrideWith(
            (ref) => Stream.value(<AdbDevice>[mockDevice]),
          ),
          packagesProvider(
            mockDevice.id,
          ).overrideWith(() => MockPackagesNotifier(mockPackages)),
          deviceOverviewProvider(mockDevice.id).overrideWith(
            (ref) => Stream.value(
              const DeviceOverview(
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
              ),
            ),
          ),
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

    // 1. 选择设备
    final deviceTextFinder = find.text('Redmi K40');
    expect(deviceTextFinder, findsWidgets);
    await tester.tap(deviceTextFinder.first);
    await tester.pumpAndSettle();

    // 2. 切换到 "应用" tab (index 2)
    final appsTabFinder = find.byWidgetPredicate(
      (w) => w is Icon && w.icon == CupertinoIcons.square_grid_2x2 && w.size == 24.0,
    );
    expect(appsTabFinder, findsOneWidget);
    await tester.tap(appsTabFinder);
    await tester.pumpAndSettle();

    // 验证三个应用都在列表中
    expect(find.text('北京环球度假区'), findsOneWidget);
    expect(find.text('微信'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);

    // 3. 搜索 "bj" (北京首字母)
    final searchFieldFinder = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '筛选包名',
    );
    expect(searchFieldFinder, findsOneWidget);

    await tester.enterText(searchFieldFinder, 'bj');
    await tester.pumpAndSettle();

    // 验证只有 "北京环球度假区" 显示
    expect(find.text('北京环球度假区'), findsOneWidget);
    expect(find.text('微信'), findsNothing);
    expect(find.text('支付宝'), findsNothing);

    // 4. 搜索 "weixin" (微信全拼)
    await tester.enterText(searchFieldFinder, 'weixin');
    await tester.pumpAndSettle();

    // 验证只有 "微信" 显示
    expect(find.text('北京环球度假区'), findsNothing);
    expect(find.text('微信'), findsOneWidget);
    expect(find.text('支付宝'), findsNothing);

    // 5. 搜索 "zfb" (支付宝首字母)
    await tester.enterText(searchFieldFinder, 'zfb');
    await tester.pumpAndSettle();

    // 验证只有 "支付宝" 显示
    expect(find.text('北京环球度假区'), findsNothing);
    expect(find.text('微信'), findsNothing);
    expect(find.text('支付宝'), findsOneWidget);

    // 6. 搜索 "nonexistent"
    await tester.enterText(searchFieldFinder, 'nonexistent');
    await tester.pumpAndSettle();

    // 验证无匹配提示
    expect(find.text('北京环球度假区'), findsNothing);
    expect(find.text('微信'), findsNothing);
    expect(find.text('支付宝'), findsNothing);
  });
}
