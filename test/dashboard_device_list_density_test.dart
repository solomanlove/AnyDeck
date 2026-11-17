import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_asset_image.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/core/receiver/receiver_identity.dart';
import 'package:any_deck/features/devices/widgets/device_status_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

const _devices = [
  RegisteredDevice(
    id: 'logo-xiaomi',
    model: 'Camera phone',
    status: 'device',
    isOnline: true,
    ipAddress: '192.168.1.10',
    androidVersion: 'Android 15',
  ),
  RegisteredDevice(
    id: '192.168.1.11:5555',
    model: 'HONOR Magic V6',
    status: 'device',
    isOnline: true,
    androidVersion: 'Android 15',
  ),
  RegisteredDevice(
    id: 'logo-ios',
    model: 'iPhone',
    status: 'offline',
    isOnline: false,
    isIos: true,
    androidVersion: 'iOS 18',
  ),
  RegisteredDevice(
    id: 'logo-harmony',
    model: 'HUAWEI nova',
    status: 'offline',
    isOnline: false,
    isHarmony: true,
    androidVersion: 'HarmonyOS 6',
  ),
];

/// 使用真实 Dashboard 列表验证密度与品牌，所有概览和发现均由内存桩提供。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
      windows,
      (call) async => call.method == 'getAllWindows' ? <Object>[] : null,
    );
  });
  tearDown(() => messenger.setMockMethodCallHandler(windows, null));

  testWidgets('品牌头像默认仍读取完整概览，cacheOnly不改变其他入口行为', (tester) async {
    const device = RegisteredDevice(
      id: 'avatar-default',
      model: 'Phone',
      status: 'device',
      isOnline: true,
    );
    var fullOverviewReads = 0;
    var cachedOverviewReads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceOverviewProvider(device.id).overrideWith((ref) {
            fullOverviewReads++;
            return Stream.value(DeviceOverview.fromJson({'brand': 'Samsung'}));
          }),
          cachedDeviceOverviewProvider(device.id).overrideWith((ref) async {
            cachedOverviewReads++;
            return null;
          }),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const Scaffold(body: DeviceStatusAvatar(device: device)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fullOverviewReads, 1);
    expect(cachedOverviewReads, 0);
    expect(
      tester.widget<AppAssetImage>(find.byType(AppAssetImage)).assetName,
      AppIcons.samsung,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('列表恢复品牌Logo并紧凑显示连接方式 $language ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var fullOverviewReads = 0;
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
            hostNetworkProvider.overrideWith(_HostNetwork.new),
            adbEnvironmentProvider.overrideWith(_ReadyAdb.new),
            emulatorListProvider.overrideWith((ref) async => []),
            emulatorConnectionsProvider.overrideWith((ref) async => {}),
            for (final device in _devices) ...[
              cachedDeviceOverviewProvider(device.id).overrideWith(
                (ref) async => device.id == 'logo-xiaomi'
                    ? DeviceOverview.fromJson({'brand': 'Xiaomi'})
                    : null,
              ),
              deviceOverviewProvider(device.id).overrideWith((ref) {
                fullOverviewReads++;
                return Stream.value(DeviceOverview.fromJson({}));
              }),
            ],
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
        await tester.tap(find.byKey(const Key('deviceView-list')));
        await tester.pumpAndSettle();
        const assets = [
          AppIcons.xiaomiSvg,
          AppIcons.honor,
          AppIcons.apple,
          AppIcons.huawei,
        ];
        for (var index = 0; index < _devices.length; index++) {
          final device = _devices[index];
          final row = find.byKey(ValueKey('device-row-${device.id}'));
          expect(tester.getSize(row).height, 60);
          final actionLabel = device.isOnline
              ? language == 'zh'
                    ? '投屏'
                    : 'Screen Mirror'
              : language == 'zh'
              ? '重新连接'
              : 'Reconnect';
          expect(
            find.descendant(of: row, matching: find.byTooltip(actionLabel)),
            findsOneWidget,
          );
          expect(
            tester
                .widget<Text>(
                  find.descendant(of: row, matching: find.text(actionLabel)),
                )
                .maxLines,
            1,
          );
          final avatar = find.descendant(
            of: row,
            matching: find.byType(DeviceStatusAvatar),
          );
          expect(tester.widget<DeviceStatusAvatar>(avatar).cacheOnly, isTrue);
          expect(tester.getSize(avatar), const Size(36, 36));
          expect(
            tester
                .widget<AppAssetImage>(
                  find.descendant(
                    of: avatar,
                    matching: find.byType(AppAssetImage),
                  ),
                )
                .assetName,
            assets[index],
          );
          expect(
            find.descendant(of: avatar, matching: find.byType(ColorFiltered)),
            device.isOnline ? findsNothing : findsOneWidget,
          );
          expect(
            tester
                .getSize(
                  find.byKey(ValueKey('device-status-column-${device.id}')),
                )
                .width,
            80,
          );
        }
        final usb = find.byKey(
          const ValueKey('device-status-column-logo-xiaomi'),
        );
        final wifi = find.byKey(
          const ValueKey('device-status-column-192.168.1.11:5555'),
        );
        expect(
          find.descendant(of: usb, matching: find.text('USB')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: wifi, matching: find.text('Wi-Fi')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: usb, matching: find.byIcon(Icons.usb_rounded)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: wifi, matching: find.byIcon(Icons.wifi_rounded)),
          findsOneWidget,
        );
        expect(
          find.byTooltip(language == 'zh' ? 'USB 已连接' : 'USB connected'),
          findsOneWidget,
        );
        expect(
          find.byTooltip(language == 'zh' ? 'Wi-Fi 已连接' : 'Wi-Fi connected'),
          findsOneWidget,
        );
        expect(fullOverviewReads, 0, reason: '恢复品牌Logo不应启动每台设备的完整硬件探测');
        expect(find.byType(Checkbox), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => _devices;
}

class _HostNetwork extends HostNetworkNotifier {
  @override
  Future<HostNetworkInfo> build() async => const HostNetworkInfo();
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
