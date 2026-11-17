import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/features/mcp/controller/mcp_audit_log_controller.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:any_deck/features/mcp/models/mcp_audit_log_entry.dart';
import 'package:any_deck/features/mcp/presentation/mcp_dashboard_tab.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_server_status_card.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定运行状态，状态切换仅更新内存，禁止真实 MCP、原生服务与持久化。
class _McpServer extends McpServerNotifier {
  @override
  McpServerState build() => const McpServerState(
    isRunning: true,
    statusText: 'running',
    config: McpServerConfig(),
    registeredTools: [],
  );

  void setRunning(bool running) => state = state.copyWith(isRunning: running);

  @override
  Future<void> updateConfig(McpServerConfig config) async {
    state = state.copyWith(config: config);
  }

  @override
  Future<void> startServer() async => setRunning(true);

  @override
  Future<void> stopServer() async => setRunning(false);
}

/// 审计面板保持空数据，不触发日志来源或外部 IO。
class _AuditLogs extends McpAuditLogNotifier {
  @override
  List<McpAuditLogEntry> build() => const [];
}

/// 通过 Theme 更新保留完整 MCP 页面与 Provider，验证正在运行时实时换色。
Widget _app(
  String language,
  Brightness brightness,
  ValueNotifier<AppThemeColor> color,
  _McpServer controller,
) => ProviderScope(
  overrides: [
    mcpServerProvider.overrideWith(() => controller),
    mcpAuditLogProvider.overrideWith(_AuditLogs.new),
  ],
  child: ValueListenableBuilder<AppThemeColor>(
    valueListenable: color,
    builder: (context, selected, _) => MaterialApp(
      theme: buildAppTheme(brightness, themeColor: selected),
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: const Scaffold(body: McpDashboardTab()),
    ),
  ),
);

/// 定位实际页头与服务卡中的状态圆点，避免依赖私有 Widget 名称。
BoxDecoration _dot(WidgetTester tester, Finder scope, double diameter) =>
    tester
            .widgetList<Container>(
              find.descendant(of: scope, matching: find.byType(Container)),
            )
            .singleWhere(
              (container) => container.constraints?.maxWidth == diameter,
            )
            .decoration!
        as BoxDecoration;

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('MCP 运行徽章与两处状态圆点实时换色，停止后恢复灰色 $language $brightness', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final color = ValueNotifier(AppThemeColor.blue);
        addTearDown(color.dispose);
        final controller = _McpServer();
        await tester.pumpWidget(_app(language, brightness, color, controller));
        await tester.pumpAndSettle();
        final header = find.byType(DashboardHeaderBar);
        final card = find.byType(McpServerStatusCard);
        final runningLabel = language == 'zh'
            ? '运行中 (端口: 8765)'
            : 'Running (Port: 8765)';
        final badgeFinder = find.descendant(
          of: header,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.padding ==
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        );
        final beforeTheme = controller.state;
        for (final selected in AppThemeColor.values) {
          color.value = selected;
          await tester.pumpAndSettle();
          expect(controller.state, same(beforeTheme));
          final badge =
              tester.widget<Container>(badgeFinder).decoration!
                  as BoxDecoration;
          final scheme = Theme.of(tester.element(header)).colorScheme;
          expect(badge.color, scheme.primaryContainer);
          expect(
            (badge.border! as Border).top.color,
            selected.color.withValues(alpha: 0.3),
          );
          expect(
            tester.widget<Text>(find.text(runningLabel)).style!.color,
            scheme.onPrimaryContainer,
          );
          final foreground = scheme.onPrimaryContainer.computeLuminance();
          final background = scheme.primaryContainer.computeLuminance();
          final contrast = foreground > background
              ? (foreground + 0.05) / (background + 0.05)
              : (background + 0.05) / (foreground + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          for (final dot in [_dot(tester, header, 8), _dot(tester, card, 12)]) {
            expect(dot.color, selected.color);
            expect(
              dot.boxShadow!.single.color,
              selected.color.withValues(alpha: 0.5),
            );
          }
          final stop = tester.widget<FilledButton>(
            find.descendant(of: card, matching: find.byType(FilledButton)),
          );
          expect(stop.style!.backgroundColor!.resolve({}), Colors.red.shade600);
          expect(find.byIcon(Icons.stop), findsOneWidget);
        }

        controller.setRunning(false);
        await tester.pumpAndSettle();
        final badgeGray = brightness == Brightness.dark
            ? Colors.grey.shade600
            : Colors.grey.shade500;
        final stoppedLabel = language == 'zh' ? '已停止' : 'Stopped';
        final stoppedBadge =
            tester.widget<Container>(badgeFinder).decoration! as BoxDecoration;
        expect(
          stoppedBadge.color,
          brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
        );
        expect(
          (stoppedBadge.border! as Border).top.color,
          badgeGray.withValues(alpha: 0.3),
        );
        expect(
          tester.widget<Text>(find.text(stoppedLabel)).style!.color,
          badgeGray,
        );
        expect(_dot(tester, header, 8).color, badgeGray);
        expect(_dot(tester, card, 12).color, Colors.grey);
        expect(_dot(tester, header, 8).boxShadow, isNull);
        expect(_dot(tester, card, 12).boxShadow, isNull);
        expect(find.byIcon(Icons.stop), findsNothing);
        final start = tester.widget<FilledButton>(
          find.descendant(of: card, matching: find.byType(FilledButton)),
        );
        expect(
          start.style!.backgroundColor!.resolve({}),
          AppThemeColor.values.last.color,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
