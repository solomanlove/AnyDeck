import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_config_snippet_card.dart';

class _Controller extends McpServerNotifier {
  @override
  McpServerState build() => const McpServerState(
    isRunning: false,
    statusText: '',
    config: McpServerConfig(
      platformTokens: {
        'android': 'test-a',
        'harmony': 'test-h',
        'ios': 'test-i',
      },
    ),
    registeredTools: [],
  );
  @override
  Future<void> updateConfig(McpServerConfig config) async {
    state = state.copyWith(config: config);
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('平台配置可复制、独立禁用与换凭据 $brightness/$language', (tester) async {
        final controller = _Controller();
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = call.arguments['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.binding.setSurfaceSize(const Size(600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mcpServerProvider.overrideWith(() => controller)],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: const Scaffold(
                body: SingleChildScrollView(child: McpConfigSnippetCard()),
              ),
            ),
          ),
        );
        expect(find.text('Android_MCP'), findsOneWidget);
        expect(find.textContaining('test-a'), findsNothing);
        await tester.tap(
          find
              .widgetWithText(
                OutlinedButton,
                language == 'zh' ? '复制配置' : 'Copy config',
              )
              .first,
        );
        await tester.pumpAndSettle();
        final data = jsonDecode(copied!)['mcpServers']['anydeck-android'];
        expect(data['url'], endsWith('/mcp/android'));
        expect(data['headers']['Authorization'], 'Bearer test-a');
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(controller.state.config.disabledPlatforms, {'android'});
        await tester.tap(
          find
              .widgetWithText(
                TextButton,
                language == 'zh' ? '更新凭据' : 'Rotate credentials',
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          controller.state.config.platformTokens['android'],
          isNot('test-a'),
        );
        expect(controller.state.config.platformTokens['ios'], 'test-i');
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
