import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/environment/connection_environment_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/core/receiver/receiver_identity.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/devices/widgets/harmony_wireless_connection_view.dart';
import 'package:any_deck/features/devices/widgets/platform_environment_guide_dialog.dart';
import 'package:any_deck/features/devices/widgets/tcpip_connection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

/// 从真实设备卡片和列表入口验证平台分流，外部 CLI 仅在服务边界替换。
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

  for (final listMode in [false, true]) {
    for (final harmony in [true, false]) {
      testWidgets(
        '${listMode ? '列表' : '设备墙'}离线${harmony ? '鸿蒙' : 'iOS'}重连使用对应协议',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({
            'harmony.wireless.autoReconnect': false,
          });
          final adb = _Adb();
          final hdc = _Hdc();
          final container = ProviderContainer(
            overrides: [
              adbServiceProvider.overrideWithValue(adb),
              hdcServiceProvider.overrideWithValue(hdc),
              iosDeviceServiceProvider.overrideWithValue(_Ios()),
              discoveredDevicesProvider.overrideWith((ref) => Stream.value([])),
              deviceRegistryProvider.overrideWith(() => _Registry(harmony)),
              runningEmulatorCountsProvider.overrideWithValue(noRunningEmulators),
              cachedDeviceOverviewProvider(
                'reconnect-target',
              ).overrideWith((ref) async => null),
              receiverIdentityProvider.overrideWith(
                (ref) async => const ReceiverIdentity(
                  uuid: '00000000-0000-4000-8000-000000000000',
                  computerName: 'AnyDeck QA',
                ),
              ),
              hostNetworkProvider.overrideWith(_HostNetwork.new),
              adbEnvironmentProvider.overrideWith(_ReadyAdb.new),
              connectionEnvironmentProvider.overrideWith(_Environment.new),
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
              child: MaterialApp(
                locale: const Locale('zh'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  ...GlobalMaterialLocalizations.delegates,
                ],
                theme: buildAppTheme(Brightness.light),
                home: const DashboardScreen(
                  route: DashboardRouteState.devices(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (listMode) {
            await tester.tap(find.byKey(const Key('deviceView-list')));
            await tester.pumpAndSettle();
          }
          final target = find.byKey(
            ValueKey(
              listMode
                  ? 'device-row-reconnect-target'
                  : 'device-wall-reconnect-target',
            ),
          );
          await tester.tap(
            find.descendant(of: target, matching: find.text('重新连接')),
          );
          // 手机墙的忙碌指示会持续到引导关闭，仅推进弹窗过渡。
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(TcpipConnectionDialog), findsNothing);
          expect(adb.commands, isEmpty, reason: 'HDC 与 iOS 连接不应执行 ADB');
          final registry =
              container.read(deviceRegistryProvider.notifier) as _Registry;
          expect(registry.adbWirelessCalls, 0);
          if (harmony) {
            expect(find.byType(HarmonyWirelessConnectionView), findsOneWidget);
            expect(find.byType(PlatformEnvironmentGuideDialog), findsNothing);
            expect(find.text('鸿蒙设备 HDC 无线调试'), findsOneWidget);
            await tester.enterText(
              find.widgetWithText(TextField, '设备局域网 IP:端口'),
              '192.168.1.80:5555',
            );
            await tester.tap(find.text('无线连接'));
            await tester.pump(const Duration(milliseconds: 400));
            expect(hdc.commands, [
              ['tconn', '192.168.1.80:5555'],
            ]);
            expect(registry.refreshes, 1);
            expect(
              container
                  .read(harmonyWirelessConnectionProvider)
                  .history
                  .single
                  .address,
              '192.168.1.80:5555',
            );
            expect(adb.commands, isEmpty);
          } else {
            final guide = tester.widget<PlatformEnvironmentGuideDialog>(
              find.byType(PlatformEnvironmentGuideDialog),
            );
            expect(guide.initialPlatform, TargetPlatformType.ios);
            expect(find.byType(HarmonyWirelessConnectionView), findsNothing);
            expect(find.textContaining('信任此电脑'), findsOneWidget);
            expect(
              (container.read(connectionEnvironmentProvider.notifier)
                      as _Environment)
                  .checks,
              1,
            );
            expect(hdc.commands, isEmpty);
          }
          await tester.tap(find.text('关闭'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class _Registry extends DeviceRegistryNotifier {
  _Registry(this.harmony);
  final bool harmony;
  int refreshes = 0;
  int adbWirelessCalls = 0;

  @override
  List<RegisteredDevice> build() => [
    RegisteredDevice(
      id: 'reconnect-target',
      model: harmony ? 'Harmony Phone' : 'iPhone',
      status: 'offline',
      isOnline: false,
      isHarmony: harmony,
      isIos: !harmony,
    ),
  ];

  @override
  Future<AdbResult> refreshDevices() async {
    refreshes++;
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<AdbResult> connectPreferredAdbWireless(RegisteredDevice device) async {
    adbWirelessCalls++;
    throw StateError('不能使用 ADB 重连其他平台');
  }
}

class _Adb extends FakeAdbService {
  final commands = <List<String>>[];
  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

class _Hdc extends HdcService {
  final commands = <List<String>>[];
  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    return const AdbResult(exitCode: 0, stdout: 'Connect OK', stderr: '');
  }

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async => const AdbResult(exitCode: 0, stdout: 'HarmonySerial', stderr: '');
}

class _Environment extends ConnectionEnvironmentNotifier {
  int checks = 0;
  @override
  Future<Map<TargetPlatformType, PlatformEnvironmentInfo>> checkAll() async {
    checks++;
    return state;
  }
}

class _Ios extends IosDeviceService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
}

class _HostNetwork extends HostNetworkNotifier {
  @override
  Future<HostNetworkInfo> build() async => const HostNetworkInfo();
}

class _ReadyAdb extends AdbEnvironmentNotifier {
  @override
  AdbEnvironmentInfo build() =>
      const AdbEnvironmentInfo(status: AdbEnvironmentStatus.ready);
  @override
  Future<void> checkAndPromptIfNeeded(BuildContext context) async {}
}
