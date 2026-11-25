part of '../widget_test.dart';

/// 壳层冒烟测试专用的设备快照、Provider 装配与组件定位。
class MockPackagesNotifier extends PackagesNotifier {
  MockPackagesNotifier(this.packages) : super('');
  final List<AdbPackage> packages;

  @override
  AsyncValue<List<AdbPackage>> build() {
    return AsyncValue.data(packages);
  }
}

const _mockDevice = DiscoveredDevice(
  id: 'mock_serial_123',
  status: 'device',
  model: 'Redmi K40',
  product: 'alioth',
  transportId: '1',
);

const _offlineMockDevice = DiscoveredDevice(
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
  wifi: 'Test Wi-Fi',
  wifiEnabled: true,
  ipAddress: '192.0.2.10',
  macAddress: '02:00:00:00:00:01',
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
  DiscoveredDevice? build() => _mockDevice;
}

class _OfflineSelectedDeviceNotifier extends SelectedDeviceNotifier {
  @override
  DiscoveredDevice? build() => _offlineMockDevice;
}

class _StaleSelectedDeviceNotifier extends SelectedDeviceNotifier {
  @override
  DiscoveredDevice? build() => _offlineMockDevice;
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
        ...dashboardTestPlatformOverrides(),
        adbServiceProvider.overrideWithValue(FakeAdbService()),
        iosDeviceServiceProvider.overrideWithValue(FakeIosDeviceService()),
        discoveredDevicesProvider.overrideWith(
          (ref) => Stream.value(<DiscoveredDevice>[]),
        ),
        deviceRegistryProvider.overrideWith(_FixedDeviceRegistryNotifier.new),
        selectedDeviceProvider.overrideWith(_FixedSelectedDeviceNotifier.new),
        selectedToolTabProvider.overrideWith(
          () => _FixedToolTabNotifier(selectedTool),
        ),
        packagesProvider(_mockDevice.id)
            .overrideWith(() => MockPackagesNotifier(<AdbPackage>[])),
        deviceOverviewProvider(_mockDevice.id)
            .overrideWith((ref) => Stream.value(_mockOverview)),
        webTargetsProvider(_mockDevice.id)
            .overrideWith((ref) => Future.value(<WebpageTarget>[])),
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
  await tester.pump(const Duration(milliseconds: 200));
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
    (w) =>
        w is Icon &&
        w.icon == CupertinoIcons.settings &&
        (size == null || w.size == size),
  );
}

Finder _railIcon(IconData icon, {double? size = 24.0}) => find.descendant(
  of: find.byType(PrimaryRail),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Icon &&
        widget.icon == icon &&
        (size == null || widget.size == size),
  ),
);

/// 单个工具内容的边界测试不装配侧栏、路由重定向或启动动效。
Widget _localizedPage(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: child),
);

class FakeIosDeviceService extends IosDeviceService {
  FakeIosDeviceService() : super();

  @override
  Future<List<DiscoveredDevice>> listDevices() async {
    return [];
  }
}
