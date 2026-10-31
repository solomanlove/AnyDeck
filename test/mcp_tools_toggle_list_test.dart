import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_tools_toggle_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 隔离真实 MCP 服务，记录 UI 是否意外修改工具权限。
class _TestMcpServer extends McpServerNotifier {
  int configUpdates = 0;

  @override
  McpServerState build() => McpServerState(
    isRunning: false,
    statusText: '',
    config: const McpServerConfig(),
    registeredTools: [
      for (final category in ['device', 'app'])
        McpToolDefinition(
          name: '${category}_test',
          description: '$category description',
          category: category,
          inputSchema: const {},
          handler: (_) async => {},
        ),
    ],
  );

  @override
  Future<void> updateConfig(McpServerConfig newConfig) async {
    configUpdates++;
    state = state.copyWith(config: newConfig);
  }

  void refreshStatus() {
    state = state.copyWith(totalRequestsCount: state.totalRequestsCount + 1);
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('Tools 默认收起、可反复切换且保留筛选 $brightness/$language', (
        tester,
      ) async {
        final controller = _TestMcpServer();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mcpServerProvider.overrideWith(() => controller)],
            child: MaterialApp(
              theme: buildAppTheme(brightness),
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: const Scaffold(
                body: SingleChildScrollView(child: McpToolsToggleList()),
              ),
            ),
          ),
        );
        final title = language == 'zh'
            ? '已注册的 MCP Tools 工具清单 (2 个工具已就绪)'
            : 'Registered MCP Tools (2 tools ready)';
        expect(find.text(title), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.byType(Switch), findsNothing);
        expect(controller.configUpdates, 0);

        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.text('device_test'), findsOneWidget);
        expect(find.text('app_test'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'device');
        await tester.tap(find.widgetWithText(ChoiceChip, '设备状态'));
        await tester.pumpAndSettle();
        expect(find.text('app_test'), findsNothing);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(controller.state.config.disabledToolNames, {'device_test'});

        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('device_test'), findsNothing);
        // 服务刷新不应主动展开清单，也不应改变工具权限。
        controller.refreshStatus();
        await tester.pumpAndSettle();
        expect(find.byType(Switch), findsNothing);
        expect(controller.configUpdates, 1);

        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          'device',
        );
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '设备状态'))
              .selected,
          isTrue,
        );
        expect(find.text('device_test'), findsOneWidget);
        expect(find.text('app_test'), findsNothing);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
