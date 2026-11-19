import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/settings/desktop_autostart_service.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/device_share/device_share_provider.dart';
import 'package:any_deck/core/device_share/device_share_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/core/receiver/receiver_identity.dart';
import 'package:any_deck/features/devices/widgets/device_wall_card.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/overview/settings/autostart_setting_control.dart';
import 'package:any_deck/app/window/widget/desktop_workspace_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';
import 'support/dashboard_surface_expectations.dart';

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
      final header = tester.getRect(find.byType(DesktopWorkspaceSurface).first);
      if (width == 1200) {
        // 设备管理复用一级页面标题栏，避免单独调整后间距再次偏离。
        final bar = tester.widget<DashboardHeaderBar>(
          find.byKey(const Key('deviceManagementHeader')),
        );
        expect(bar.padding, const EdgeInsets.symmetric(horizontal: 28));
        expect(tester.getSize(find.byWidget(bar)).height, 72);
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

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('$language ${brightness.name} 设备与设置标题栏切换时对齐一致', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = await _pumpDashboard(
          tester,
          language: language,
          brightness: brightness,
        );
        // 侧栏保持原应用主题，设备页局部中性主题只作用于右侧。
        expect(
          Theme.of(tester.element(find.byType(PrimaryRail))).colorScheme,
          buildAppTheme(brightness).colorScheme,
        );
        await expectDashboardSurfaceSeparation(tester);
        final bar = find.byType(DashboardHeaderBar);
        final title = find.descendant(
          of: find.byType(DashboardHeaderTitle),
          matching: find.byType(Text),
        );
        final deviceBar = tester.getRect(bar);
        final deviceTitle = tester.getRect(title.first);
        final deviceSubtitle = tester.getRect(title.last);
        final refreshButton = find.byKey(const Key('deviceRefreshButton'));
        final refresh = tester.getRect(refreshButton);
        final button = tester.widget<OutlinedButton>(refreshButton);
        final scheme = Theme.of(tester.element(refreshButton)).colorScheme;
        final label = find.descendant(
          of: refreshButton,
          matching: find.text(AppLocalizations(Locale(language)).t('refresh')),
        );
        expect(label, findsOneWidget);
        expect(button.style!.foregroundColor!.resolve({}), scheme.onSurface);
        expect(button.style!.backgroundColor!.resolve({}), scheme.surface);
        expect(
          button.style!.side!.resolve({}),
          BorderSide(color: scheme.outlineVariant),
        );
        expect(
          button.style!.shape!.resolve({}),
          const RoundedRectangleBorder(
            borderRadius: AppThemeSizes.radiusLarge,
          ),
        );
        final icon = find.descendant(
          of: refreshButton,
          matching: find.byType(Icon),
        );
        expect(tester.getRect(icon).right, lessThan(tester.getRect(label).left));
        final connect = tester.getRect(
          find.byKey(const Key('deviceConnectionButton')),
        );
        expect(deviceTitle.left - deviceBar.left, 28);
        expect(deviceBar.right - connect.right, 28);
        expect(connect.left - refresh.right, 8);
        expect(connect.center.dy, closeTo(deviceBar.center.dy, .5));
        expect(refresh.center.dy, connect.center.dy);

        container.read(appRouterProvider).go('/settings');
        await tester.pumpAndSettle();
        await expectDashboardSurfaceSeparation(tester);
        expect(tester.getRect(bar), deviceBar);
        expect(tester.getTopLeft(title.first), deviceTitle.topLeft);
        expect(tester.getTopLeft(title.last), deviceSubtitle.topLeft);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('320px $language 放大字体列表在${brightness.name}主题保持可用', (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpDashboard(
          tester,
          language: language,
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
        expect(
          find.text(AppLocalizations(Locale(language)).t('deviceWorkspaceReconnect')),
          findsOneWidget,
        );
        // 大字号下标题允许省略，但刷新与连接入口仍须有界且可打开菜单。
        final bar = tester.getRect(find.byType(DashboardHeaderBar));
        final connect = tester.getRect(
          find.byKey(const Key('deviceConnectionButton')),
        );
        final title = tester.getRect(find.byType(DashboardHeaderTitle));
        final refreshButton = find.byKey(const Key('deviceRefreshButton'));
        final refresh = tester.getRect(refreshButton);
        expect(tester.widget<OutlinedButton>(refreshButton).onPressed, isNotNull);
        expect(
          find.descendant(of: refreshButton, matching: find.byType(Text)),
          findsNothing,
        );
        expect(
          find.byTooltip(AppLocalizations(Locale(language)).t('refreshDevices')),
          findsOneWidget,
        );
        expect(title.top, greaterThanOrEqualTo(bar.top + 32));
        expect(refresh.top, greaterThanOrEqualTo(bar.top + 32));
        expect(connect.top, greaterThanOrEqualTo(bar.top + 32));
        expect(title.right, lessThanOrEqualTo(refresh.left));
        expect(refresh.right, lessThanOrEqualTo(connect.left));
        expect(connect.right, lessThanOrEqualTo(bar.right));
        expect(connect.bottom, lessThanOrEqualTo(bar.bottom));
        await tester.tap(find.byKey(const Key('deviceConnectionButton')));
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deviceConnection-pair')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
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
  // 像素采样进入真实异步，使用内存共享服务隔离磁盘与 UDP 初始化。
  final adb = FakeAdbService();
  final sharing = DeviceShareService(adb);
  final container = ProviderContainer(
    overrides: [
      receiverIdentityProvider.overrideWith(
        (ref) async => const ReceiverIdentity(
          uuid: '00000000-0000-4000-8000-000000000000',
          computerName: 'AnyDeck QA',
        ),
      ),
      adbServiceProvider.overrideWithValue(adb),
      deviceShareServiceProvider.overrideWithValue(sharing),
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
      autoStartStatusProvider.overrideWith(
        (ref) async => DesktopAutoStartStatus.disabled,
      ),
      emulatorListProvider.overrideWith((ref) async => []),
      emulatorConnectionsProvider.overrideWith((ref) async => {}),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await sharing.dispose();
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
