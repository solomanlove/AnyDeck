import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_share/device_share_service.dart';
import 'package:any_deck/core/device_share/device_share_provider.dart';
import 'package:any_deck/core/airplay/airplay_server_service.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_adb_service.dart';

const deviceMenuAndroid = RegisteredDevice(
  id: 'device-a',
  model: '设备甲',
  status: 'device',
  isOnline: true,
);
const deviceMenuTarget = RegisteredDevice(
  id: 'device-b',
  model: '设备乙',
  status: 'device',
  isOnline: true,
);
const deviceMenuOffline = RegisteredDevice(
  id: 'device-offline',
  model: '离线设备',
  status: 'offline',
  isOnline: false,
);
const deviceMenuHarmony = RegisteredDevice(
  id: 'harmony-device',
  model: '鸿蒙设备',
  status: 'device',
  isOnline: true,
  isHarmony: true,
);
const deviceMenuIos = RegisteredDevice(
  id: 'ios-device',
  model: 'iPhone',
  status: 'device',
  isOnline: true,
  isIos: true,
  iosConnectionTypes: {IosConnectionType.usb},
);
final deviceMenuImage = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

/// 截图后端均为测试桩，避免 Widget test 调用真实设备或系统剪贴板。
class DeviceMenuAdb extends FakeAdbService {
  final captures = <String>[];
  Completer<Uint8List>? gate;
  bool fail = false;

  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    captures.add(deviceId);
    if (fail) throw StateError('capture failed');
    return gate?.future ?? deviceMenuImage;
  }
}

class DeviceMenuHdc extends HdcService {
  DeviceMenuHdc() : super(executable: 'hdc');
  final captures = <String>[];

  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    captures.add(deviceId);
    return deviceMenuImage;
  }
}

class DeviceMenuIosCommands extends IosCommandService {
  DeviceMenuIosCommands() : super(executable: 'ios');
  final captures = <String>[];

  @override
  Future<Uint8List> captureScreenshot(String udid) async {
    captures.add(udid);
    return deviceMenuImage;
  }
}

class DeviceMenuHost extends HostPlatformService {
  DeviceMenuHost(this.directory);
  final Directory directory;
  final copied = Completer<void>();
  final savedFor = <String>[];
  Uint8List? clipboard;
  String? savePath;

  @override
  String generateScreenshotPath(String configuredPath, String deviceId) {
    savedFor.add(deviceId);
    return savePath = '${directory.path}/capture_${savedFor.length}.png';
  }

  @override
  Future<bool> copyImageToClipboard(Uint8List bytes) async {
    clipboard = bytes;
    if (!copied.isCompleted) copied.complete();
    return true;
  }
}

class DeviceMenuRegistry extends DeviceRegistryNotifier {
  DeviceMenuRegistry(this.devices);
  final List<RegisteredDevice> devices;

  @override
  List<RegisteredDevice> build() => devices;

  void disconnect(String id) => state = [
    for (final device in state)
      device.id == id
          ? device.copyWith(isOnline: false, status: 'offline')
          : device,
  ];

  void remove(String id) =>
      state = state.where((device) => device.id != id).toList();
}

class _Selection extends SelectedDeviceNotifier {
  @override
  DiscoveredDevice? build() => null;
}

class _Tab extends ToolTabNotifier {
  @override
  int build() => -1;
}

class _HostNetwork extends HostNetworkNotifier {
  _HostNetwork(this.info);
  final HostNetworkInfo info;
  @override
  Future<HostNetworkInfo> build() async => info;
}

class _IosDiscovery extends IosDeviceService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
}

class _AirPlay extends AirPlayServerNotifier {
  _AirPlay(this.session);
  final AirPlaySessionData? session;

  @override
  AirPlaySessionData? build() => session;
}

class _ReadyAdb extends AdbEnvironmentNotifier {
  @override
  AdbEnvironmentInfo build() =>
      const AdbEnvironmentInfo(status: AdbEnvironmentStatus.ready);

  @override
  Future<void> checkAndPromptIfNeeded(BuildContext context) async {}
}

/// 截图仅需要保存目录，不启动全局设置的原生广播和开机启动探测。
class _Settings extends AppSettingsController {
  _Settings(this.path);
  final String path;

  @override
  AppSettings build() => AppSettings(screenshotSavePath: path);
}

/// 装配真实设备列表，用简化的目标 Route 验证跳转参数，避免启动终端等后台任务。
class DeviceMenuFixture {
  DeviceMenuFixture(
    this.container,
    this.router,
    this.adb,
    this.hdc,
    this.ios,
    this.host,
  );
  final ProviderContainer container;
  final GoRouter router;
  final DeviceMenuAdb adb;
  final DeviceMenuHdc hdc;
  final DeviceMenuIosCommands ios;
  final DeviceMenuHost host;

  DeviceMenuRegistry get registry =>
      container.read(deviceRegistryProvider.notifier) as DeviceMenuRegistry;

  Future<void> waitForSavedScreenshot(WidgetTester tester) async {
    // 交替推进真实文件 IO 和 Widget 微任务，避免在 FakeAsync 中等待自身。
    for (var i = 0; i < 100 && !host.copied.isCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(host.copied.isCompleted, isTrue, reason: '截图应完成写盘与剪贴板同步');
    await tester.pumpAndSettle();
  }
}

Future<void> withDeviceMenu(
  WidgetTester tester,
  Future<void> Function(DeviceMenuFixture fixture) verify, {
  List<RegisteredDevice> devices = const [
    deviceMenuAndroid,
    deviceMenuTarget,
    deviceMenuOffline,
    deviceMenuHarmony,
    deviceMenuIos,
  ],
  AirPlaySessionData? airplay,
  String language = 'zh',
  Brightness brightness = Brightness.light,
  DeviceShareService? sharing,
  HostNetworkInfo network = const HostNetworkInfo(),
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final directory = Directory.systemTemp.createTempSync('anydeck-device-menu-');
  final adb = DeviceMenuAdb();
  final hdc = DeviceMenuHdc();
  final ios = DeviceMenuIosCommands();
  final host = DeviceMenuHost(directory);
  final container = ProviderContainer(
    overrides: [
      if (sharing != null) deviceShareServiceProvider.overrideWithValue(sharing),
      adbServiceProvider.overrideWithValue(adb),
      hdcServiceProvider.overrideWithValue(hdc),
      iosCommandServiceProvider.overrideWithValue(ios),
      hostPlatformServiceProvider.overrideWithValue(host),
      appSettingsProvider.overrideWith(() => _Settings(directory.path)),
      iosDeviceServiceProvider.overrideWithValue(_IosDiscovery()),
      discoveredDevicesProvider.overrideWith(
        (ref) => Stream.value(<DiscoveredDevice>[]),
      ),
      deviceRegistryProvider.overrideWith(() => DeviceMenuRegistry(devices)),
      selectedDeviceProvider.overrideWith(_Selection.new),
      selectedToolTabProvider.overrideWith(_Tab.new),
      hostNetworkProvider.overrideWith(() => _HostNetwork(network)),
      adbEnvironmentProvider.overrideWith(_ReadyAdb.new),
      airplaySessionProvider.overrideWith(() => _AirPlay(airplay)),
      emulatorListProvider.overrideWith((ref) async => []),
      emulatorConnectionsProvider.overrideWith((ref) async => {}),
    ],
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/devices'),
      GoRoute(
        path: '/devices',
        builder: (context, state) =>
            const DashboardScreen(route: DashboardRouteState.devices()),
      ),
      GoRoute(
        path: '/devices/:deviceId/:tool',
        name: AppRouteNames.deviceTool,
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
  try {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildAppTheme(brightness),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await verify(DeviceMenuFixture(container, router, adb, hdc, ios, host));
  } finally {
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    router.dispose();
    await tester.pumpAndSettle();
    directory.deleteSync(recursive: true);
  }
}
