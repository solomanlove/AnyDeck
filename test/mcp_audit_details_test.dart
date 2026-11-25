import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/mcp/models/mcp_audit_response_summary.dart';
import 'package:any_deck/features/mcp/controller/mcp_audit_log_controller.dart';
import 'package:any_deck/features/mcp/models/mcp_audit_log_entry.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_audit_logs_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只替换日志来源，经由生产组件打开详情。
class _AuditLogs extends McpAuditLogNotifier {
  _AuditLogs(this.entry);

  final McpAuditLogEntry entry;

  @override
  List<McpAuditLogEntry> build() => [entry];
}

Widget _app(McpAuditLogEntry entry, Locale locale, Brightness brightness) =>
    ProviderScope(
      overrides: [mcpAuditLogProvider.overrideWith(() => _AuditLogs(entry))],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildAppTheme(brightness),
        home: const Scaffold(
          body: SingleChildScrollView(child: McpAuditLogsViewer()),
        ),
      ),
    );

void main() {
  testWidgets('窄窗可打开工具调用详情并查看可选择的多行脱敏参数', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        McpAuditLogEntry(
          id: 'tool',
          method: 'tools/call',
          toolName: 'input_text',
          timestamp: DateTime(2026, 11, 25, 17, 26, 57),
          isSuccess: false,
          durationMs: 21,
          responseSummary: const McpAuditResponseSummary(
            protocolVersion: '2026-07-28',
            isToolError: true,
          ),
          arguments: {
            'platform': 'android',
            'deviceId': 'demo-device',
            'text': '[redacted]',
          },
        ),
        const Locale('zh'),
        Brightness.light,
      ),
    );

    await tester.tap(find.text('input_text'));
    await tester.pumpAndSettle();
    expect(find.text('调用详情'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('请求方法  tools/call', findRichText: true), findsOneWidget);
    expect(find.text('接入平台  android', findRichText: true), findsOneWidget);
    expect(find.text('调用耗时  21 ms', findRichText: true), findsOneWidget);
    expect(find.text('调用状态  失败', findRichText: true), findsOneWidget);
    expect(find.text('工具执行失败'), findsOneWidget);
    final parameters = find.textContaining('"text": "[redacted]"');
    expect(parameters, findsOneWidget);
    await tester.ensureVisible(parameters);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(parameters).data,
      '{\n  "deviceId": "demo-device",\n  "text": "[redacted]"\n}',
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('英文深色界面能查看历史来源和协议摘要', (tester) async {
    final entry = McpAuditLogEntry.fromJson({
      'id': 'discover',
      'timestamp': '2026-11-25T17:26:57.000',
      'method': 'server/discover',
      'platform': 'android',
      'isSuccess': true,
      'durationMs': 0,
      'responseSummary': {
        'protocolVersion': '2026-07-28',
        'supportedVersions': ['2026-07-28', '2025-11-25'],
      },
    });
    await tester.pumpWidget(_app(entry, const Locale('en'), Brightness.dark));
    await tester.tap(find.text('server/discover'));
    await tester.pumpAndSettle();

    expect(find.text('Call details'), findsOneWidget);
    expect(
      find.text('Local time  11/25/2026 17:26:57', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Protocol version  2026-07-28', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text(
        'Supported versions  2026-07-28, 2025-11-25',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text('Only a summary is saved for historical calls.'),
      findsOneWidget,
    );
    expect(find.text('Tool arguments'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
