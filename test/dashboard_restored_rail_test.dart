import 'package:any_deck/app/config/build_features.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_navigation_item.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/console/controller/console_dock_controller.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/harmony_share/controller/harmony_share_providers.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只隔离设备发现及服务启动，侧栏仍使用真实导航与控制台状态。
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
  bool get enabled => false;
  @override
  bool get scanning => false;
  @override
  bool get busy => false;
  @override
  String? get error => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

const _device = DiscoveredDevice(
  id: 'restored-rail-iphone',
  model: 'AnyDeck iPhone',
  status: 'device',
  isIos: true,
);

class _Selection extends SelectedDeviceNotifier {
  @override
  DiscoveredDevice? build() => _device;
}

/// 建立独立侧栏装配，测试不启动真实网络、原生设置同步或硬件探测。
ProviderContainer _container({bool selectedDevice = false}) {
  final share = _Share();
  final container = ProviderContainer(
    overrides: [
      deviceRegistryProvider.overrideWith(_Registry.new),
      mcpServerProvider.overrideWith(_Mcp.new),
      harmonyShareServiceProvider.overrideWithValue(share),
      appSettingsProvider.overrideWith(_Settings.new),
      if (selectedDevice) selectedDeviceProvider.overrideWith(_Selection.new),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(share.dispose);
  return container;
}

Future<void> _pumpRail(
  WidgetTester tester, {
  required ProviderContainer container,
  required String language,
  required ThemeData theme,
  DiscoveredDevice? device,
  bool receiverRunning = false,
}) async {
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
                selectedDevice: device,
                isAirplayReceiverRunning: receiverRunning,
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _entry(AppLocalizations l10n, String key) => find.byTooltip(l10n.t(key));

Finder _entryIcon(AppLocalizations l10n, String key, IconData icon) =>
    find.descendant(of: _entry(l10n, key), matching: find.byIcon(icon));

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 999.0, 1000.0, 1400.0]) {
        testWidgets('原侧栏宽度边界、品牌与导航组件 $language $brightness $width', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 950);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final container = _container();
          final l10n = AppLocalizations(Locale(language));
          final theme = buildAppTheme(
            brightness,
            themeColor: AppThemeColor.pink,
          );
          await _pumpRail(
            tester,
            container: container,
            language: language,
            theme: theme,
          );

          final isWide = width >= 1000;
          final rail = find.byType(PrimaryRail);
          expect(tester.getSize(rail).width, isWide ? 180 : 76);
          final logo = find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image == const AssetImage(AppIcons.appLogo),
          );
          expect(logo, findsOneWidget);
          expect(tester.getSize(logo).width, isWide ? 36 : 50);
          expect(
            find.byKey(const ValueKey('app-identity-labels')),
            isWide ? findsOneWidget : findsNothing,
          );

          // 固定旧图标与公共导航项，防止管理页再次引入另一套侧栏。
          final entries = {
            'devices': Icons.devices,
            'emulators': CupertinoIcons.device_desktop,
            'receiverCenter': Icons.cast_connected_rounded,
            if (AnyDeckBuildFeatures.shareCore)
              'harmonyShareTitle': Icons.share_rounded,
            'systemVersions': Icons.layers_outlined,
            'wanAndroid': CupertinoIcons.question_circle,
            'aiMcp': CupertinoIcons.sparkles,
            'console': CupertinoIcons.doc_plaintext,
            'settings': CupertinoIcons.settings,
          };
          for (final entry in entries.entries) {
            expect(_entry(l10n, entry.key), findsOneWidget);
            expect(_entryIcon(l10n, entry.key, entry.value), findsOneWidget);
            final navigation = find.descendant(
              of: _entry(l10n, entry.key),
              matching: find.byType(AppNavigationItem),
            );
            expect(navigation, isWide ? findsOneWidget : findsNothing);
            if (!isWide) {
              expect(
                find.descendant(
                  of: _entry(l10n, entry.key),
                  matching: find.byType(IconButton),
                ),
                findsOneWidget,
              );
            }
          }
          final active = tester.widget<Icon>(
            _entryIcon(l10n, 'devices', Icons.devices),
          );
          expect(active.color, theme.colorScheme.primary);
          expect(
            tester.getTopLeft(_entry(l10n, 'console')).dy,
            lessThan(tester.getTopLeft(_entry(l10n, 'settings')).dy),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }

      for (final width in [320.0, 1200.0]) {
        testWidgets('低高度折叠工具，服务状态与底部入口保留 $language $brightness $width', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 500);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final container = _container();
          final mcp = container.read(mcpServerProvider.notifier) as _Mcp;
          mcp.setRunning(true);
          final l10n = AppLocalizations(Locale(language));
          final theme = buildAppTheme(brightness);
          await _pumpRail(
            tester,
            container: container,
            language: language,
            theme: theme,
          );

          final railRect = tester.getRect(find.byType(PrimaryRail));
          for (final key in ['wanAndroid', 'aiMcp', 'console', 'settings']) {
            final rect = tester.getRect(_entry(l10n, key));
            expect(railRect.contains(rect.center), isTrue);
            expect(rect.bottom, lessThanOrEqualTo(500));
          }
          final status = find.descendant(
            of: _entry(l10n, 'aiMcp'),
            matching: find.byTooltip(l10n.t('navigationServiceRunning')),
          );
          expect(status, findsOneWidget);
          final dot = tester.widget<Container>(
            find.descendant(of: status, matching: find.byType(Container)),
          );
          expect(
            (dot.decoration as BoxDecoration).color,
            theme.colorScheme.primary,
          );
          expect(find.byIcon(Icons.layers_outlined), findsNothing);
          await tester.tap(_entry(l10n, 'moreTools'));
          await tester.pumpAndSettle();
          final versions = find.byWidgetPredicate(
            (widget) => widget is PopupMenuItem<int> && widget.value == -5,
          );
          expect(versions, findsOneWidget);
          expect(tester.widget<PopupMenuItem<int>>(versions).enabled, isTrue);
          expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(versions, findsNothing);
          expect(status, findsOneWidget);
          mcp.setRunning(false);
          await tester.pumpAndSettle();
          expect(status, findsNothing);
          expect(_entry(l10n, 'console'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final width in [320.0, 1200.0]) {
    testWidgets('原侧栏控制台开关保留选中设备、应用与工具 $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = _container(selectedDevice: true);
      container.read(selectedToolTabProvider.notifier).select(0);
      container.read(selectedAppPackageProvider.notifier).state =
          'com.anydeck.sample';
      await _pumpRail(
        tester,
        container: container,
        language: 'zh',
        theme: buildAppTheme(Brightness.light),
        device: _device,
      );
      final railElement = tester.element(find.byType(PrimaryRail));
      for (final isOpen in [true, false]) {
        await tester.tap(find.byTooltip('控制台'));
        await tester.pumpAndSettle();
        expect(container.read(consoleDockProvider).isOpen, isOpen);
        expect(container.read(selectedDeviceProvider), same(_device));
        expect(container.read(selectedToolTabProvider), 0);
        expect(
          container.read(selectedAppPackageProvider),
          'com.anydeck.sample',
        );
        expect(tester.element(find.byType(PrimaryRail)), same(railElement));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
