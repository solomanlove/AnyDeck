import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_config_snippet_card.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_server_status_card.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_tools_toggle_list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只隔离服务初始化和配置落盘，工具开关仍调用真实的 toggleTool。
class _McpServer extends McpServerNotifier {
  int configUpdates = 0;

  @override
  McpServerState build() => McpServerState(
    isRunning: false,
    statusText: 'idle',
    config: const McpServerConfig(
      enableLegacy: true,
      platformTokens: {'android': 'a', 'harmony': 'h', 'ios': 'i'},
    ),
    registeredTools: [
      McpToolDefinition(
        name: 'theme_test',
        description: '主题开关回归工具',
        category: 'device',
        inputSchema: const {},
        handler: (_) async => {},
      ),
    ],
  );

  @override
  Future<void> updateConfig(McpServerConfig config) async {
    configUpdates++;
    state = state.copyWith(config: config);
  }
}

/// 保留真实卡片和 Provider，只更新 Theme，避免重建页面掩盖状态丢失。
Widget _app(
  Brightness brightness,
  TargetPlatform platform,
  ValueNotifier<AppThemeColor> color,
  _McpServer controller,
) => ProviderScope(
  overrides: [mcpServerProvider.overrideWith(() => controller)],
  child: ValueListenableBuilder<AppThemeColor>(
    valueListenable: color,
    child: const Column(
      children: [
        McpServerStatusCard(),
        McpConfigSnippetCard(),
        McpToolsToggleList(),
      ],
    ),
    builder: (context, selected, child) => MaterialApp(
      theme: buildAppTheme(brightness, themeColor: selected).copyWith(
        platform: platform,
        // 不依赖全局 Cupertino 兜底，卡片自身必须传入一致的颜色。
        cupertinoOverrideTheme: const CupertinoThemeData(
          applyThemeToAll: false,
        ),
      ),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

Finder _switchIn(Type card) =>
    find.descendant(of: find.byType(card), matching: find.byType(Switch));

/// 检查真实绘制：Cupertino 与 Material 的轨道和滑块均使用平台卡的配色。
void _expectStyle(
  WidgetTester tester,
  Finder finder,
  Switch reference,
  TargetPlatform platform, {
  bool selected = true,
}) {
  final control = tester.widget<Switch>(finder);
  final theme = Theme.of(tester.element(finder));
  expect(theme.platform, platform);
  expect(control.value, selected);
  expect(control.activeTrackColor, theme.colorScheme.primary);
  expect(control.activeThumbColor, theme.colorScheme.onPrimary);
  expect(control.activeTrackColor, reference.activeTrackColor);
  expect(control.activeThumbColor, reference.activeThumbColor);
  expect(control.onChanged, isNotNull);

  final paint = find.descendant(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter != null,
    ),
  );
  expect(paint, findsOneWidget);
  if (selected) {
    expect(paint, paints..rrect(color: reference.activeTrackColor));
    // SDK 的滑块可能使用 RRect、Circle 或 Path，均检查最终 Paint 前景。
    expect(
      paint,
      paints..something(
        (method, arguments) =>
            const {#drawRRect, #drawCircle, #drawPath}.contains(method) &&
            (arguments.last as Paint).color.toARGB32() ==
                reference.activeThumbColor!.toARGB32(),
      ),
    );
  } else {
    expect(paint, isNot(paints..rrect(color: reference.activeTrackColor)));
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      testWidgets('MCP 安全和 Tools 开关与平台开关绘制一致并实时换色 $platform $brightness', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final color = ValueNotifier(AppThemeColor.blue);
        addTearDown(color.dispose);
        final controller = _McpServer();
        await tester.pumpWidget(_app(brightness, platform, color, controller));
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();

        final platformSwitches = _switchIn(McpConfigSnippetCard);
        final guard = _switchIn(McpServerStatusCard);
        final tool = _switchIn(McpToolsToggleList);
        expect(platformSwitches, findsNWidgets(4));
        expect(guard, findsOneWidget);
        expect(tool, findsOneWidget);
        expect(find.text('theme_test'), findsOneWidget);
        final toolState = tester.state(find.byType(McpToolsToggleList));
        final initialReference = tester.widget<Switch>(platformSwitches.first);
        expect(initialReference.activeTrackColor, AppThemeColor.blue.color);
        for (final finder in [
          for (var index = 0; index < 4; index++) platformSwitches.at(index),
          guard,
          tool,
        ]) {
          _expectStyle(tester, finder, initialReference, platform);
        }
        expect(controller.configUpdates, 0);

        await tester.ensureVisible(guard);
        await tester.tap(guard);
        await tester.pumpAndSettle();
        await tester.ensureVisible(tool);
        await tester.tap(tool);
        await tester.pumpAndSettle();
        expect(controller.state.config.enableDangerousOperationGuard, isFalse);
        expect(controller.state.config.disabledToolNames, {'theme_test'});
        expect(controller.configUpdates, 2);
        final beforeTheme = controller.state.config;

        color.value = AppThemeColor.purple;
        await tester.pumpAndSettle();
        expect(controller.state.config, same(beforeTheme));
        expect(controller.configUpdates, 2);
        expect(tester.state(find.byType(McpToolsToggleList)), same(toolState));
        final updatedReference = tester.widget<Switch>(platformSwitches.first);
        expect(updatedReference.activeTrackColor, AppThemeColor.purple.color);
        for (var index = 0; index < 4; index++) {
          _expectStyle(
            tester,
            platformSwitches.at(index),
            updatedReference,
            platform,
          );
        }
        for (final finder in [guard, tool]) {
          _expectStyle(
            tester,
            finder,
            updatedReference,
            platform,
            selected: false,
          );
        }

        await tester.ensureVisible(guard);
        await tester.tap(guard);
        await tester.pumpAndSettle();
        await tester.ensureVisible(tool);
        await tester.tap(tool);
        await tester.pumpAndSettle();
        expect(controller.state.config.enableDangerousOperationGuard, isTrue);
        expect(controller.state.config.disabledToolNames, isEmpty);
        expect(controller.state.config.enableLegacy, isTrue);
        expect(controller.state.config.disabledPlatforms, isEmpty);
        expect(controller.configUpdates, 4);
        _expectStyle(tester, guard, updatedReference, platform);
        _expectStyle(tester, tool, updatedReference, platform);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
