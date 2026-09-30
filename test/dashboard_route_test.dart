import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/features/splash/animated_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardRouteState', () {
    test('解析三个顶层管理页面', () {
      expect(
        DashboardRouteState.fromUri(Uri.parse('/devices')).kind,
        DashboardRouteKind.devices,
      );
      expect(
        DashboardRouteState.fromUri(Uri.parse('/emulators')).kind,
        DashboardRouteKind.emulators,
      );
      expect(
        DashboardRouteState.fromUri(Uri.parse('/settings')).kind,
        DashboardRouteKind.settings,
      );
    });

    test('解析设备工具和应用详情参数', () {
      final tool = DashboardRouteState.fromUri(
        Uri.parse('/devices/127.0.0.1%3A5555/files'),
      );
      expect(tool.deviceId, '127.0.0.1:5555');
      expect(tool.tabIndex, 3);
      expect(tool.packageName, isNull);

      final details = DashboardRouteState.fromUri(
        Uri.parse('/devices/serial-1/apps/com.example.demo'),
      );
      expect(details.deviceId, 'serial-1');
      expect(details.tabIndex, 2);
      expect(details.packageName, 'com.example.demo');
    });

    test('工具 slug 与现有 Tab index 可双向转换', () {
      const indexes = [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 15];
      for (final index in indexes) {
        expect(tabIndexForToolSlug(toolSlugForTabIndex(index)), index);
      }
      expect(tabIndexForToolSlug('unknown'), isNull);
      expect(toolSlugForTabIndex(8), 'capture');
    });
  });

  test('GoRouter 生成稳定的设备和应用路径', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    expect(router.routeInformationProvider.value.uri.path, '/devices');
    expect(
      router.namedLocation(
        AppRouteNames.deviceTool,
        pathParameters: {'deviceId': '127.0.0.1:5555', 'tool': 'overview'},
      ),
      '/devices/127.0.0.1%3A5555/overview',
    );
    expect(
      router.namedLocation(
        AppRouteNames.appDetails,
        pathParameters: {
          'deviceId': 'serial-1',
          'packageName': 'com.example.demo',
        },
      ),
      '/devices/serial-1/apps/com.example.demo',
    );
  });

  testWidgets('闪屏在淡出等待期间卸载时会清理 Timer', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          home: AnimatedSplashScreen(child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
