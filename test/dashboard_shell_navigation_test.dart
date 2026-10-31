import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

const _device = DiscoveredDevice(
  id: 'navigation-test',
  status: 'device',
  model: 'Pixel',
);

/// 固定设备、应用和主机网络，验证真实 Dashboard 而不执行任何设备命令。
class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [
    RegisteredDevice(
      id: _device.id,
      serial: _device.id,
      status: 'device',
      isOnline: true,
    ),
  ];
}

class _SelectedDevice extends SelectedDeviceNotifier {
  @override
  DiscoveredDevice? build() => _device;
}

class _Tab extends ToolTabNotifier {
  @override
  int build() => 2;
}

class _Packages extends PackagesNotifier {
  _Packages() : super(_device.id);

  @override
  AsyncValue<List<AdbPackage>> build() => const AsyncData([]);
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

void main() {
  testWidgets('底部控制台不改变设备上下文，系统版本导航与设备选择同步', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(FakeAdbService()),
        iosDeviceServiceProvider.overrideWithValue(_Ios()),
        discoveredDevicesProvider.overrideWith((ref) => Stream.value(<DiscoveredDevice>[])),
        deviceRegistryProvider.overrideWith(_Registry.new),
        selectedDeviceProvider.overrideWith(_SelectedDevice.new),
        selectedToolTabProvider.overrideWith(_Tab.new),
        packagesProvider(_device.id).overrideWith(_Packages.new),
        hostNetworkProvider.overrideWith(_HostNetwork.new),
        adbEnvironmentProvider.overrideWith(_ReadyAdb.new),
        emulatorListProvider.overrideWith((ref) async => []),
        emulatorConnectionsProvider.overrideWith((ref) async => {}),
      ],
    );
    var disposed = false;
    addTearDown(() {
      if (!disposed) container.dispose();
    });
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
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildAppTheme(Brightness.light),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/devices/navigation-test/apps',
    );
    final selected = container.read(selectedDeviceProvider);
    await tester.tap(find.byTooltip('控制台'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('consoleDockPanel')), findsOneWidget);
    expect(container.read(selectedDeviceProvider), selected);
    expect(container.read(selectedToolTabProvider), 2);

    router.goNamed(AppRouteNames.systemVersions);
    await tester.pumpAndSettle();
    expect(container.read(selectedDeviceProvider), isNull);
    expect(container.read(selectedToolTabProvider), -5);
    expect(
      find.byKey(const Key('systemVersionsHorizontalScroll')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('consoleDockPanel')), findsOneWidget);
    expect(find.byTooltip('系统版本'), findsOneWidget);
    await tester.tap(find.byTooltip('模拟器管理'));
    await tester.pumpAndSettle();
    expect(container.read(selectedToolTabProvider), -2);
    expect(find.byType(EmulatorListPanel), findsOneWidget);
    expect(find.byTooltip('在独立窗口显示'), findsNothing);
    expect(find.byKey(const Key('consoleDockPanel')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    disposed = true;
    await tester.pumpAndSettle();
  });
}
