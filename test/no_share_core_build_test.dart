import 'package:any_deck/app/config/build_features.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/harmony_share/controller/harmony_share_providers.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅验证编译开关与导航，不探测设备或启动外部服务。
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
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('构建开关控制互传入口：$language $brightness', (tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = ProviderContainer(
          overrides: [
            deviceRegistryProvider.overrideWith(_EmptyRegistry.new),
            runningEmulatorCountsProvider.overrideWithValue(noRunningEmulators),
            mcpServerProvider.overrideWith(_IdleMcp.new),
            if (!AnyDeckBuildFeatures.shareCore)
              harmonyShareServiceProvider.overrideWith((ref) {
                throw StateError('禁用入口不得创建 Share Core 服务');
              }),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              theme: buildAppTheme(brightness),
              home: const Scaffold(
                body: Row(children: [PrimaryRail(selectedDevice: null)]),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations(Locale(language));
        expect(
          find.byTooltip(l10n.t('harmonyShareTitle')),
          AnyDeckBuildFeatures.shareCore ? findsOneWidget : findsNothing,
        );
        expect(find.byTooltip(l10n.t('devices')), findsOneWidget);
        expect(find.byTooltip(l10n.t('receiverCenter')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('禁用构建将互传深链接重定向到设备列表', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    const target = Key('route-parser-context');
    await tester.pumpWidget(const MaterialApp(home: SizedBox(key: target)));
    final matches = await router.routeInformationParser
        .parseRouteInformationWithDependencies(
          RouteInformation(uri: Uri.parse('/harmony-share')),
          tester.element(find.byKey(target)),
        );
    expect(
      matches.uri.path,
      AnyDeckBuildFeatures.shareCore ? '/harmony-share' : '/devices',
    );
  });
}
