import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/console/controller/console_dock_controller.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:any_deck/features/overview/widget/system_versions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 导航测试不启动设备探测、MCP Server 或原生窗口。
class _EmptyRegistry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [];
}

class _IdleMcp extends McpServerNotifier {
  @override
  McpServerState build() => const McpServerState(
    isRunning: false,
    statusText: '',
    config: McpServerConfig(),
    registeredTools: [],
  );
}

void main() {
  testWidgets('系统版本位于鸿蒙互联下面，控制台紧邻设置上方且不改变路由', (tester) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        deviceRegistryProvider.overrideWith(_EmptyRegistry.new),
        mcpServerProvider.overrideWith(_IdleMcp.new),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/devices',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(
            body: Row(
              children: [
                const PrimaryRail(selectedDevice: null),
                Expanded(child: child),
              ],
            ),
          ),
          routes: [
            GoRoute(
              path: '/devices',
              name: AppRouteNames.devices,
              builder: (context, state) => const Text('device workspace'),
            ),
            GoRoute(
              path: '/system-versions',
              name: AppRouteNames.systemVersions,
              builder: (context, state) => const SystemVersionsPage(),
            ),
            GoRoute(
              path: '/settings',
              name: AppRouteNames.settings,
              builder: (context, state) => const Text('settings workspace'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
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
    final versions = find.byTooltip('系统版本');
    final share = find.byTooltip('鸿蒙互联');
    final console = find.byTooltip('控制台');
    final settings = find.byTooltip('设置');
    expect(
      tester.getTopLeft(versions).dy,
      greaterThan(tester.getTopLeft(share).dy),
    );
    expect(
      tester.getTopLeft(settings).dy - tester.getTopLeft(console).dy,
      lessThan(70),
    );
    final tabBefore = container.read(selectedToolTabProvider);
    await tester.tap(console);
    await tester.pumpAndSettle();
    expect(container.read(consoleDockProvider).isOpen, isTrue);
    expect(container.read(selectedToolTabProvider), tabBefore);
    expect(router.routeInformationProvider.value.uri.path, '/devices');
    expect(find.text('device workspace'), findsOneWidget);
    await tester.tap(versions);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/system-versions');
    expect(find.byType(SystemVersionsPage), findsOneWidget);
    expect(container.read(consoleDockProvider).isOpen, isTrue);
    expect(find.text('关闭'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('系统版本三平台切换在窄窗口 $language $brightness 可用', (tester) async {
        tester.view.physicalSize = const Size(624, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: buildAppTheme(brightness),
              home: const Scaffold(body: SystemVersionsPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('API 37'), findsWidgets);
        expect(find.textContaining('2026-10-13'), findsOneWidget);
        await tester.tap(find.text('HarmonyOS'));
        await tester.pumpAndSettle();
        expect(find.text('HarmonyOS 7.0.0（当前最新）'), findsOneWidget);
        expect(find.textContaining('2026-10-07'), findsOneWidget);
        await tester.tap(find.text('iOS'));
        await tester.pumpAndSettle();
        expect(find.text('iOS 27'), findsWidgets);
        expect(find.textContaining('2026-06-07'), findsWidgets);
        await tester.drag(
          find.byKey(const Key('systemVersionsHorizontalScroll')),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('复制编译与适配要求'), findsOneWidget);
        tester.view.physicalSize = const Size(624, 180);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
