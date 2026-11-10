import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_navigation_item.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/harmony_share/controller/harmony_share_providers.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// AnyDeck 侧栏回归使用可控服务状态，不启动网络、设备发现或原生窗口。
class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [];
}

class _Mcp extends McpServerNotifier {
  @override
  McpServerState build() => const McpServerState(
    isRunning: false,
    statusText: '',
    config: McpServerConfig(),
    registeredTools: [],
  );

  void setRunning(bool value) => state = state.copyWith(isRunning: value);
}

class _Share extends ChangeNotifier implements HarmonyShareService {
  @override
  bool enabled = false;
  @override
  bool scanning = false;
  @override
  bool busy = false;
  @override
  String? error;

  void update({
    required bool enabled,
    bool scanning = false,
    bool busy = false,
    String? error,
  }) {
    this.enabled = enabled;
    this.scanning = scanning;
    this.busy = busy;
    this.error = error;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final width in [900.0, 1400.0]) {
        testWidgets('服务状态与当前页面选中独立：$language $brightness $width', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 950);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final share = _Share();
          final container = ProviderContainer(
            overrides: [
              deviceRegistryProvider.overrideWith(_Registry.new),
              mcpServerProvider.overrideWith(_Mcp.new),
              harmonyShareServiceProvider.overrideWithValue(share),
            ],
          );
          addTearDown(container.dispose);
          addTearDown(share.dispose);
          final l10n = AppLocalizations(Locale(language));
          final theme = buildAppTheme(brightness);
          final runningHint = l10n.t('navigationServiceRunning');

          Future<void> pumpRail({bool receiverRunning = false}) async {
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
                  theme: theme,
                  home: Scaffold(
                    body: Row(
                      children: [
                        PrimaryRail(
                          selectedDevice: null,
                          isAirplayReceiverRunning: receiverRunning,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          // 同时检查背景、图标与文字，防止状态只在某一种侧栏宽度解耦。
          void expectEntry(
            String labelKey, {
            required bool selected,
            bool running = false,
          }) {
            final entry = find.byTooltip(l10n.t(labelKey));
            expect(entry, findsOneWidget);
            final expectedColor = selected
                ? AppPalette.primary
                : theme.navigationForeground;
            final icon = find
                .descendant(of: entry, matching: find.byType(Icon))
                .first;
            expect(tester.widget<Icon>(icon).color, expectedColor);
            if (width >= 1000) {
              final nav = tester.widget<AppNavigationItem>(
                find.descendant(
                  of: entry,
                  matching: find.byType(AppNavigationItem),
                ),
              );
              expect(nav.selected, selected);
              final text = tester.widget<Text>(
                find.descendant(
                  of: entry,
                  matching: find.text(l10n.t(labelKey)),
                ),
              );
              expect(
                text.style?.fontWeight,
                selected ? FontWeight.bold : FontWeight.normal,
              );
            } else {
              final button = tester.widget<IconButton>(
                find.descendant(of: entry, matching: find.byType(IconButton)),
              );
              expect(
                button.style?.backgroundColor?.resolve({}),
                selected
                    ? theme.navigationSelectedBackground
                    : Colors.transparent,
              );
            }
            expect(
              find.descendant(of: entry, matching: find.byTooltip(runningHint)),
              running ? findsOneWidget : findsNothing,
            );
          }

          await pumpRail();
          expectEntry('devices', selected: true);
          for (final key in ['receiverCenter', 'harmonyShareTitle', 'aiMcp']) {
            expectEntry(key, selected: false);
          }

          final mcp = container.read(mcpServerProvider.notifier) as _Mcp;
          mcp.setRunning(true);
          share.update(enabled: true, scanning: true);
          await pumpRail(receiverRunning: true);
          expectEntry('devices', selected: true);
          for (final key in ['receiverCenter', 'harmonyShareTitle', 'aiMcp']) {
            expectEntry(key, selected: false, running: true);
          }

          // 页面切换只移动高亮，三个后台服务的绿点继续显示。
          for (final page in {
            -3: 'receiverCenter',
            -4: 'harmonyShareTitle',
            14: 'aiMcp',
          }.entries) {
            container.read(selectedToolTabProvider.notifier).select(page.key);
            await tester.pumpAndSettle();
            expectEntry('devices', selected: false);
            for (final key in [
              'receiverCenter',
              'harmonyShareTitle',
              'aiMcp',
            ]) {
              expectEntry(key, selected: key == page.value, running: true);
            }
          }

          // 选中页停服仍高亮；其他已停服务不残留绿点。
          mcp.setRunning(false);
          share.update(enabled: false);
          await pumpRail();
          expectEntry('aiMcp', selected: true);
          expectEntry('receiverCenter', selected: false);
          expectEntry('harmonyShareTitle', selected: false);

          // 启用、准备、失败与真实就绪分开，收发期间继续显示运行标记。
          share.update(enabled: true);
          await tester.pumpAndSettle();
          expectEntry('harmonyShareTitle', selected: false);
          share.update(enabled: true, error: 'discovery_failed');
          await tester.pumpAndSettle();
          expectEntry('harmonyShareTitle', selected: false);
          share.update(enabled: true, busy: true);
          await tester.pumpAndSettle();
          expectEntry('harmonyShareTitle', selected: false, running: true);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
