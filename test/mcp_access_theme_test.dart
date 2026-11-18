import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_config_snippet_card.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_tools_toggle_list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定凭据与工具，记录 UI 配置更新，不启动原生 MCP 或执行设备命令。
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
      for (final platform in ['android', 'harmony', 'ios'])
        McpToolDefinition(
          name: '${platform}_device',
          description: '$platform device test',
          category: 'device',
          platforms: {platform},
          inputSchema: const {},
          handler: (_) async => {},
        ),
      McpToolDefinition(
        name: 'android_app',
        description: 'android app test',
        category: 'app',
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

/// 主题变化只更新 Theme，Provider、页面实例和已有筛选状态均保持挂载。
Widget _app(
  Brightness brightness,
  ValueNotifier<AppThemeColor> color,
  _McpServer controller,
  Widget child, {
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: [mcpServerProvider.overrideWith(() => controller)],
  child: ValueListenableBuilder<AppThemeColor>(
    valueListenable: color,
    builder: (context, selected, _) => MaterialApp(
      theme: buildAppTheme(
        brightness,
        themeColor: selected,
      ).copyWith(platform: platform),
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

/// 检查最终 Canvas 绘制的轨道颜色，而非只检查控件传入参数。
void _expectPaintedTrack(WidgetTester tester, Finder finder, Color color) {
  final paint = find.descendant(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter != null,
    ),
  );
  expect(paint, findsOneWidget);
  expect(paint, paints..rrect(color: color));
}

/// 同时验证 adaptive 参数和真实选中轨道绘制，捕捉 macOS 默认绿色回退。
void _expectAdaptiveSwitch(
  WidgetTester tester,
  Finder finder,
  AppThemeColor color, {
  required bool enabled,
}) {
  final control = tester.widget<Switch>(finder);
  final scheme = Theme.of(tester.element(finder)).colorScheme;
  expect(Theme.of(tester.element(finder)).platform, TargetPlatform.macOS);
  expect(control.value, enabled);
  expect(control.activeTrackColor, color.color);
  expect(control.activeThumbColor, scheme.onPrimary);

  // 旧 SDK 生成 CupertinoSwitch；Flutter 3.50 使用带 Cupertino 外观的 Painter。
  final cupertino = find.descendant(
    of: finder,
    matching: find.byType(CupertinoSwitch),
  );
  if (cupertino.evaluate().isNotEmpty) {
    final native = tester.widget<CupertinoSwitch>(cupertino);
    expect(native.value, enabled);
    expect(native.activeTrackColor, color.color);
    expect(native.thumbColor, scheme.onPrimary);
  }
  if (enabled) {
    _expectPaintedTrack(tester, finder, color.color);
  }
}

/// 选中背景与前景使用同一主题的 Material 语义配对，保证明暗模式可读。
void _expectSelectedChip(
  WidgetTester tester,
  String label,
  AppThemeColor color,
) {
  final finder = find.widgetWithText(ChoiceChip, label);
  final chip = tester.widget<ChoiceChip>(finder);
  final scheme = Theme.of(tester.element(finder)).colorScheme;
  expect(scheme.primary, color.color);
  expect(chip.selected, isTrue);
  expect(chip.selectedColor, scheme.primaryContainer);
  expect(chip.labelStyle!.color, scheme.onPrimaryContainer);
  expect(chip.checkmarkColor, scheme.onPrimaryContainer);
  final raw = tester.widget<RawChip>(
    find.descendant(of: finder, matching: find.byType(RawChip)),
  );
  expect(raw.showCheckmark, isTrue);
  expect(raw.selectedColor, scheme.primaryContainer);
  expect(raw.checkmarkColor, scheme.onPrimaryContainer);
  expect(
    DefaultTextStyle.of(tester.element(find.text(label))).style.color,
    scheme.onPrimaryContainer,
  );
}

void main() {
  for (final brightness in Brightness.values) {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      testWidgets('默认 adaptive 开关及列表开关实时使用主题轨道 $platform $brightness', (
        tester,
      ) async {
        final color = ValueNotifier(AppThemeColor.blue);
        addTearDown(color.dispose);
        var switchEnabled = true;
        var tileEnabled = true;
        final controls = StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              Switch.adaptive(
                value: switchEnabled,
                onChanged: (value) => setState(() => switchEnabled = value),
              ),
              SwitchListTile.adaptive(
                title: const Text('默认列表开关'),
                value: tileEnabled,
                onChanged: (value) => setState(() => tileEnabled = value),
              ),
            ],
          ),
        );
        await tester.pumpWidget(
          _app(brightness, color, _McpServer(), controls, platform: platform),
        );
        await tester.pumpAndSettle();
        final switches = find.byType(Switch);
        expect(switches, findsNWidgets(2));
        for (var index = 0; index < 2; index++) {
          final control = tester.widget<Switch>(switches.at(index));
          expect(control.activeTrackColor, isNull);
          expect(control.activeThumbColor, isNull);
          _expectPaintedTrack(
            tester,
            switches.at(index),
            AppThemeColor.blue.color,
          );
        }

        await tester.tap(switches.first);
        await tester.pumpAndSettle();
        expect(switchEnabled, isFalse);
        color.value = AppThemeColor.purple;
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(switches.first).value, isFalse);
        expect(tester.widget<Switch>(switches.last).value, isTrue);
        _expectPaintedTrack(tester, switches.last, AppThemeColor.purple.color);
        await tester.tap(switches.first);
        await tester.pumpAndSettle();
        expect(switchEnabled, isTrue);
        _expectPaintedTrack(tester, switches.first, AppThemeColor.purple.color);
        await tester.tap(switches.last);
        await tester.pumpAndSettle();
        expect(tileEnabled, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('macOS 平台接入与兼容开关轨道实时换色且保留配置 $brightness', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      final controller = _McpServer();
      await tester.pumpWidget(
        _app(brightness, color, controller, const McpConfigSnippetCard()),
      );
      await tester.pumpAndSettle();
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(4));
      for (var index = 0; index < 4; index++) {
        _expectAdaptiveSwitch(
          tester,
          switches.at(index),
          AppThemeColor.blue,
          enabled: true,
        );
      }

      final legacy = find.descendant(
        of: find.byType(SwitchListTile),
        matching: find.byType(Switch),
      );
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();
      await tester.tap(legacy);
      await tester.pumpAndSettle();
      expect(controller.state.config.disabledPlatforms, {'harmony'});
      expect(controller.state.config.enableLegacy, isFalse);
      final beforeTheme = controller.state.config;

      color.value = AppThemeColor.purple;
      await tester.pumpAndSettle();
      expect(controller.state.config, same(beforeTheme));
      expect(controller.configUpdates, 2);
      for (var index = 0; index < 4; index++) {
        _expectAdaptiveSwitch(
          tester,
          switches.at(index),
          AppThemeColor.purple,
          enabled: index == 0 || index == 2,
        );
      }
      await tester.tap(legacy);
      await tester.pumpAndSettle();
      _expectAdaptiveSwitch(
        tester,
        legacy,
        AppThemeColor.purple,
        enabled: true,
      );
      expect(controller.state.config.enableLegacy, isTrue);
      expect(controller.state.config.disabledPlatforms, {'harmony'});
      expect(controller.configUpdates, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MCP 平台与分类选中颜色实时变化并保留筛选和权限 $brightness', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      final controller = _McpServer();
      await tester.pumpWidget(
        _app(brightness, color, controller, const McpToolsToggleList()),
      );
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      _expectSelectedChip(tester, '全部平台', AppThemeColor.blue);
      _expectSelectedChip(tester, '全部', AppThemeColor.blue);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Android'));
      await tester.pumpAndSettle();
      expect(find.text('android_device'), findsOneWidget);
      expect(find.text('android_app'), findsOneWidget);
      expect(find.text('ios_device'), findsNothing);
      _expectSelectedChip(tester, 'Android', AppThemeColor.blue);
      await tester.tap(find.widgetWithText(ChoiceChip, '设备状态'));
      await tester.pumpAndSettle();
      expect(find.text('android_app'), findsNothing);
      _expectSelectedChip(tester, '设备状态', AppThemeColor.blue);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(controller.state.config.disabledToolNames, {'android_device'});

      await tester.enterText(find.byType(TextField), 'device');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'iOS'));
      await tester.pumpAndSettle();
      expect(find.text('ios_device'), findsOneWidget);
      expect(find.text('android_device'), findsNothing);
      final toolsState = tester.state(find.byType(McpToolsToggleList));
      final beforeTheme = controller.state.config;

      color.value = AppThemeColor.purple;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(McpToolsToggleList)), same(toolsState));
      expect(controller.state.config, same(beforeTheme));
      expect(controller.configUpdates, 1);
      _expectSelectedChip(tester, 'iOS', AppThemeColor.purple);
      _expectSelectedChip(tester, '设备状态', AppThemeColor.purple);
      expect(find.text('ios_device'), findsOneWidget);
      expect(find.text('android_device'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text ??
            tester
                .widget<EditableText>(find.byType(EditableText))
                .controller
                .text,
        'device',
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Android'));
      await tester.pumpAndSettle();
      _expectSelectedChip(tester, 'Android', AppThemeColor.purple);
      expect(find.text('android_device'), findsOneWidget);
      expect(find.text('android_app'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(controller.state.config.disabledToolNames, isEmpty);
      expect(controller.configUpdates, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
