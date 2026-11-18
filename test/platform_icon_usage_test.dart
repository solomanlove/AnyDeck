import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/device_os_logo_widget.dart';
import 'package:any_deck/features/diagnostics/controller/service_diagnostics_controller.dart';
import 'package:any_deck/features/diagnostics/widgets/service_diagnostic_row.dart';
import 'package:any_deck/core/diagnostics/service_diagnostic.dart';
import 'support/diagnostics_test_checks.dart';
import 'package:any_deck/core/environment/connection_environment_service.dart';
import 'package:any_deck/features/developer/widget/developer_connection_environment_card.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shortcut_test_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness 公共平台 Logo 支持不同尺寸与 Apple 主题对比度', (tester) async {
      final theme = buildAppTheme(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                for (final size in [15.0, 20.0, 48.0])
                  Row(
                    children: [
                      for (final platform in PlatformDistributionType.values)
                        buildPlatformIcon(platform, size: size),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final apple = find.byIcon(Icons.apple);
      expect(apple, findsNWidgets(3));
      expect(
        tester.widgetList<Icon>(apple).map((icon) => icon.color),
        everyElement(theme.colorScheme.onSurface),
      );
      expect(tester.widgetList<Icon>(apple).map((icon) => icon.size), [
        15,
        20,
        48,
      ]);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => image.width),
        [15, 20, 48],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$brightness 开发者入口复用全局诊断并保留平台引导', (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final probes = DiagnosticsTestChecks();
      final container = ProviderContainer(overrides: [
        serviceDiagnosticChecksProvider.overrideWithValue(probes.checks),
        connectionEnvironmentProvider.overrideWith(DiagnosticsTestEnvironment.new),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(shortcutTestApp(container: container,
        brightness: brightness, child: const DeveloperConnectionEnvironmentCard()));
      await tester.pumpAndSettle();
      expect(probes.calls, 0);
      await tester.tap(find.byKey(const ValueKey('services-diagnostics-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceDiagnosticRow), findsNWidgets(DiagnosticService.values.length));
      await tester.tap(find.byKey(const ValueKey('services-diagnostics-run')));
      await tester.pumpAndSettle();
      expect(probes.calls, DiagnosticService.values.length);
      expect(container.read(serviceDiagnosticsProvider).issueCount, 1);
      await tester.tap(find.byKey(const ValueKey('diagnostic-row-hdc')));
      await tester.pumpAndSettle();
      final guide = find.text('打开安装与配置引导');
      expect(guide, findsOneWidget);
      await tester.ensureVisible(guide);
      await tester.tap(guide);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('services-diagnostics-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
