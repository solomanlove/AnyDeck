import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/webview/in_app_webview_widget.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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
      remark: 'QA phone',
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

/// 帮助中心测试仅检查页面导航与 WebView 请求，不启动原生浏览器。
class _TestWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _TestWebView(params);
}

class _TestWebView extends PlatformInAppWebViewWidget {
  _TestWebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      InAppWebViewController.fromPlatform(platform: controller) as T;

  @override
  void dispose() {}
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _TestWebViewPlatform();
  });

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
        cachedDeviceOverviewProvider(_device.id).overrideWith((ref) async =>
            DeviceOverview.fromJson({'name': 'Market Phone'})),
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
    router.goNamed(AppRouteNames.devices);
    await tester.pumpAndSettle();
    expect(find.text('Market Phone'), findsWidgets);
    expect(find.textContaining('1 在线'), findsOneWidget);
    expect(find.text('备注/用途'), findsNothing);
    expect(find.text('QA phone'), findsNothing);
    await tester.enterText(find.byKey(const Key('deviceListSearch')), 'qa phone');
    await tester.pumpAndSettle();
    expect(find.text('Market Phone'), findsWidgets);
    expect(find.byTooltip('编辑设备信息'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('deviceListSearch')), 'no-match');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的设备'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('deviceListSearch')), 'market');
    await tester.tap(find.byKey(const Key('deviceListOnlineOnly')));
    await tester.pumpAndSettle();
    expect(find.text('Market Phone'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    disposed = true;
    await tester.pumpAndSettle();
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('帮助中心在 $language $brightness 无需选择设备且切页保留浏览状态', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer(
          overrides: [
            adbServiceProvider.overrideWithValue(FakeAdbService()),
            iosDeviceServiceProvider.overrideWithValue(_Ios()),
            discoveredDevicesProvider.overrideWith(
              (ref) => Stream.value(<DiscoveredDevice>[]),
            ),
            deviceRegistryProvider.overrideWith(_Registry.new),
            cachedDeviceOverviewProvider(_device.id).overrideWith(
              (ref) async => DeviceOverview.fromJson({'name': 'Market Phone'}),
            ),
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
        final label = language == 'zh' ? '帮助中心' : 'Help Center';
        final entry = find.byTooltip(label);
        final webView = find.byType(InAppWebViewWidget);
        expect(container.read(selectedDeviceProvider), isNull);
        expect(find.byType(InAppWebViewWidget, skipOffstage: false), findsNothing);
        expect(
          find.descendant(
            of: entry,
            matching: find.byIcon(CupertinoIcons.question_circle),
          ),
          findsOneWidget,
        );

        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/wan-android');
        expect(container.read(selectedToolTabProvider), 13);
        expect(container.read(selectedDeviceProvider), isNull);
        expect(webView, findsOneWidget);
        expect(tester.widget<InAppWebViewWidget>(webView).title, label);
        expect(
          find.descendant(of: webView, matching: find.text(label)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<InAppWebView>(find.byType(InAppWebView))
              .platform
              .params
              .initialUrlRequest
              ?.url
              .toString(),
          'https://solomanlove.github.io/AnyDeckWeb/help.html',
        );

        final pageState = tester.state(webView);
        final browserState = tester.state(find.byType(InAppWebView));
        router.goNamed(AppRouteNames.systemVersions);
        await tester.pumpAndSettle();
        expect(webView, findsNothing);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(tester.state(webView), same(pageState));
        expect(tester.state(find.byType(InAppWebView)), same(browserState));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        disposed = true;
        await tester.pumpAndSettle();
      });
    }
  }
}
