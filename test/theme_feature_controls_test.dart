import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/core/notifications/notification_models.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/developer/widget/developer_section_card.dart';
import 'package:any_deck/features/developer/widget/settings_developer_entry.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_server_status_card.dart';
import 'package:any_deck/features/mcp/presentation/widgets/mcp_tools_toggle_list.dart';
import 'package:any_deck/features/messages/presentation/widgets/message_item_card.dart';
import 'package:any_deck/features/overview/widget/receiver_name_setting_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定设置与应用列表，不初始化原生服务或执行设备命令。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

class _Packages extends PackagesNotifier {
  _Packages() : super('theme-test');

  @override
  AsyncValue<List<AdbPackage>> build() => const AsyncData([]);
}

/// 保留实际 MCP 控件交互，隔离服务启动、配置持久化和设备连接。
class _McpServer extends McpServerNotifier {
  @override
  McpServerState build() => McpServerState(
    isRunning: false,
    statusText: 'idle',
    config: const McpServerConfig(),
    registeredTools: [
      McpToolDefinition(
        name: 'theme_test',
        description: 'theme test tool',
        category: 'device',
        inputSchema: const {},
        handler: (_) async => {},
      ),
    ],
  );

  @override
  Future<void> updateConfig(McpServerConfig config) async {
    state = state.copyWith(config: config);
  }

  @override
  Future<void> startServer() async {
    state = state.copyWith(isRunning: true);
  }
}

/// 复用同一 Widget 子树，仅通过 Theme 变更检验正在使用的控件实时换色。
Widget _app(
  Brightness brightness,
  ValueNotifier<AppThemeColor> color,
  Widget child,
) => ValueListenableBuilder<AppThemeColor>(
  valueListenable: color,
  builder: (context, value, _) => MaterialApp(
    theme: buildAppTheme(brightness, themeColor: value),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('开发者按钮、卡片与接收名称焦点边框实时跟随主题 $brightness', (tester) async {
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      var updates = 0;
      const defaultEntry = ValueKey('default-entry');
      const overrideEntry = ValueKey('override-entry');
      const receiver = ValueKey('receiver');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appSettingsProvider.overrideWith(_Settings.new)],
          child: _app(
            brightness,
            color,
            Column(
              children: [
                SettingsDeveloperEntry(
                  key: defaultEntry,
                  onCheckUpdate: () => updates++,
                ),
                SettingsDeveloperEntry(
                  key: overrideEntry,
                  brandGreen: Colors.amber,
                  onCheckUpdate: () {},
                ),
                const DeveloperSectionCard(
                  title: '主题测试',
                  icon: Icons.code,
                  children: [Text('卡片内容')],
                ),
                ReceiverNameSettingField(
                  key: receiver,
                  value: 'AnyDeck-AirPlay',
                  defaultName: 'AnyDeck-AirPlay',
                  resetTooltip: '恢复默认',
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      final receiverState = tester.state(find.byKey(receiver));
      await tester.enterText(find.byType(TextField), '会议室');
      for (final selected in [AppThemeColor.blue, AppThemeColor.purple]) {
        color.value = selected;
        await tester.pumpAndSettle();
        ElevatedButton button(Key key) => tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(ElevatedButton),
          ),
        );
        final primaryButton = button(defaultEntry);
        expect(
          primaryButton.style!.backgroundColor!.resolve({}),
          selected.color,
        );
        expect(
          primaryButton.style!.foregroundColor!.resolve({}),
          Theme.of(
            tester.element(find.byKey(defaultEntry)),
          ).colorScheme.onPrimary,
        );
        expect(
          button(overrideEntry).style!.backgroundColor!.resolve({}),
          Colors.amber,
        );
        expect(
          tester.widget<Icon>(find.byIcon(Icons.code)).color,
          selected.color,
        );
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(
          (field.decoration!.focusedBorder! as OutlineInputBorder)
              .borderSide
              .color,
          selected.color,
        );
        expect(field.controller!.text, '会议室');
        expect(tester.state(find.byKey(receiver)), same(receiverState));
      }
      await tester.tap(
        find.descendant(
          of: find.byKey(defaultEntry),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(updates, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MCP 启动、工具开关与运行状态实时跟随主题 $brightness', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      final controller = _McpServer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mcpServerProvider.overrideWith(() => controller)],
          child: _app(
            brightness,
            color,
            const Column(
              children: [McpServerStatusCard(), McpToolsToggleList()],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      final toolsState = tester.state(find.byType(McpToolsToggleList));
      for (final selected in [AppThemeColor.blue, AppThemeColor.purple]) {
        color.value = selected;
        await tester.pumpAndSettle();
        final start = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(start.style!.backgroundColor!.resolve({}), selected.color);
        final scheme = Theme.of(
          tester.element(find.byType(McpServerStatusCard)),
        ).colorScheme;
        for (final control in tester.widgetList<Switch>(find.byType(Switch))) {
          expect(control.activeThumbColor, scheme.onPrimary);
          expect(control.activeTrackColor, scheme.primary);
        }
        expect(tester.state(find.byType(McpToolsToggleList)), same(toolsState));
        expect(find.text('theme_test'), findsOneWidget);
      }
      final toolSwitch = find.descendant(
        of: find.byType(McpToolsToggleList),
        matching: find.byType(Switch),
      );
      await tester.tap(toolSwitch);
      await tester.pumpAndSettle();
      expect(controller.state.config.disabledToolNames, {'theme_test'});
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(controller.state.isRunning, isTrue);
      final statusDot = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(McpServerStatusCard),
              matching: find.byType(Container),
            ),
          )
          .singleWhere((container) => container.constraints?.maxWidth == 12);
      final theme = Theme.of(tester.element(find.byType(McpServerStatusCard)));
      expect(
        (statusDot.decoration! as BoxDecoration).color,
        theme.colorScheme.primary,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('消息目标高亮随实时主题换色 $brightness', (tester) async {
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      final time = DateTime(2026, 11, 17);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packagesProvider('theme-test').overrideWith(_Packages.new),
          ],
          child: _app(
            brightness,
            color,
            MessageItemCard(
              deviceId: 'theme-test',
              deviceLabel: '测试手机',
              isTarget: true,
              message: NotificationMessage(
                installationId: 'theme',
                androidUserId: 0,
                notificationKey: 'message',
                packageName: 'chat',
                title: '目标消息',
                content: '主题切换后仍显示正文',
                postTime: time,
                receivedTime: time,
              ),
            ),
          ),
        ),
      );
      for (final selected in [AppThemeColor.blue, AppThemeColor.purple]) {
        color.value = selected;
        await tester.pumpAndSettle();
        final card = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(MessageItemCard),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = card.decoration! as BoxDecoration;
        expect((decoration.border! as Border).top.color, selected.color);
        expect(
          decoration.color,
          selected.color.withValues(
            alpha: brightness == Brightness.dark ? 0.20 : 0.12,
          ),
        );
        expect(find.text('目标消息'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
