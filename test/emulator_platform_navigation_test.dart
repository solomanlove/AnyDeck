import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_providers.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/devices/widgets/deveco_emulators_view.dart';
import 'package:any_deck/features/devices/widgets/emulator_platform_tabs.dart';
import 'package:any_deck/features/devices/widgets/ios_simulators_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';
import 'support/dashboard_test_environment.dart';

/// 真实路由测试仅替换设备发现、模拟器列表和系统环境探测。
class _EmptyRegistry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [];
}

class _HostNetwork extends HostNetworkNotifier {
  @override
  Future<HostNetworkInfo> build() async => const HostNetworkInfo();
}

void main() {
  testWidgets('重新进入模拟器管理时优先显示有运行实例的平台', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var counts = (android: 0, harmony: 0, ios: 1);
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(DashboardTestSettings.new),
        adbEnvironmentProvider.overrideWith(DashboardTestAdbEnvironment.new),
        adbServiceProvider.overrideWithValue(FakeAdbService()),
        discoveredDevicesProvider.overrideWith(
          (ref) => Stream.value(<DiscoveredDevice>[]),
        ),
        deviceRegistryProvider.overrideWith(_EmptyRegistry.new),
        hostNetworkProvider.overrideWith(_HostNetwork.new),
        runningEmulatorCountsProvider.overrideWith((ref) => counts),
        emulatorListProvider.overrideWith((ref) async => []),
        emulatorConnectionsProvider.overrideWith((ref) async => {}),
        devecoEmulatorsProvider.overrideWith((ref) async => []),
        iosSimulatorsProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildAppTheme(Brightness.light),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final platformTabs = find.byType(EmulatorPlatformTabs);
    EmulatorPlatform selectedPlatform() =>
        tester.widget<EmulatorPlatformTabs>(platformTabs).selectedPlatform;

    await tester.tap(find.byTooltip('模拟器管理'));
    await tester.pumpAndSettle();
    expect(selectedPlatform(), EmulatorPlatform.ios);
    expect(find.byType(IosSimulatorsView), findsOneWidget);

    // 用户切换平台后，后台更新运行状态不覆盖本次选择。
    await tester.tap(find.text('HarmonyOS'));
    await tester.pumpAndSettle();
    counts = (android: 2, harmony: 0, ios: 1);
    container.invalidate(runningEmulatorCountsProvider);
    await tester.pumpAndSettle();
    expect(selectedPlatform(), EmulatorPlatform.harmony);
    expect(find.byType(DevecoEmulatorsView), findsOneWidget);

    for (final (running, expected) in [
      (counts, EmulatorPlatform.android),
      ((android: 1, harmony: 3, ios: 2), EmulatorPlatform.android),
      ((android: 0, harmony: 1, ios: 2), EmulatorPlatform.harmony),
      ((android: 0, harmony: 1, ios: 0), EmulatorPlatform.harmony),
      ((android: 0, harmony: 0, ios: 1), EmulatorPlatform.ios),
      (noRunningEmulators, EmulatorPlatform.android),
    ]) {
      router.goNamed(AppRouteNames.systemVersions);
      await tester.pumpAndSettle();
      expect(platformTabs, findsNothing);
      counts = running;
      container.invalidate(runningEmulatorCountsProvider);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('模拟器管理'));
      await tester.pumpAndSettle();
      expect(selectedPlatform(), expected, reason: '$running');
    }

    // 检测结果晚于页面切换返回时，仍能显示已运行的平台。
    counts = (android: 0, harmony: 0, ios: 1);
    container.invalidate(runningEmulatorCountsProvider);
    await tester.pumpAndSettle();
    expect(selectedPlatform(), EmulatorPlatform.ios);
    expect(find.byType(IosSimulatorsView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
