import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_navigation_item.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
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

// 使用已知的 HDC 回环目标和可控的 simctl 结果模拟外部启停。
class _Hdc extends HdcService {
  final queriedTargets = <String>[];

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deviceId = args[1];
    queriedTargets.add(deviceId);
    expect(args, ['-t', deviceId, 'shell', 'param get | grep hvd']);
    return AdbResult(
      exitCode: 0,
      stdout: deviceId == '127.0.0.1:5555'
          ? 'ohos.qemu.hvd.name = Mate 90 RS\n'
          : 'ohos.qemu.hvd.name = \nother.hvd.property = phone',
      stderr: '',
    );
  }
}

class _IosSimulators extends IosSimulatorService {
  bool booted = false;
  int queries = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> hasBootedSimulator() async {
    queries++;
    return booted;
  }
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
          final devices = StreamController<List<DiscoveredDevice>>.broadcast();
          final hdc = _Hdc();
          final ios = _IosSimulators();
          final container = ProviderContainer(
            overrides: [
              deviceRegistryProvider.overrideWith(_Registry.new),
              discoveredDevicesProvider.overrideWith((ref) => devices.stream),
              hdcServiceProvider.overrideWithValue(hdc),
              iosSimulatorServiceProvider.overrideWithValue(ios),
              mcpServerProvider.overrideWith(_Mcp.new),
              harmonyShareServiceProvider.overrideWithValue(share),
            ],
          );
          addTearDown(share.dispose);
          addTearDown(devices.close);
          addTearDown(container.dispose);
          final l10n = AppLocalizations(Locale(language));
          var theme = buildAppTheme(brightness, themeColor: AppThemeColor.blue);
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
                ? theme.colorScheme.primary
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
            final status = find.descendant(
              of: entry,
              matching: find.byTooltip(runningHint),
            );
            expect(status, running ? findsOneWidget : findsNothing);
            if (running) {
              final dot = tester.widget<Container>(
                find.descendant(of: status, matching: find.byType(Container)),
              );
              expect(
                (dot.decoration as BoxDecoration).color,
                theme.colorScheme.primary,
              );
            }
          }

          await pumpRail();
          expectEntry('devices', selected: true);
          expectEntry('emulators', selected: false);

          const physicalDevices = [
            DiscoveredDevice(id: 'android-usb', status: 'device'),
            DiscoveredDevice(id: 'ios-usb', status: 'device', isIos: true),
            DiscoveredDevice(
              id: 'harmony-usb',
              status: 'device',
              isHarmony: true,
            ),
            DiscoveredDevice(
              id: '127.0.0.1:6000',
              status: 'device',
              isHarmony: true,
            ),
          ];
          const android = DiscoveredDevice(
            id: 'emulator-5554',
            status: 'unauthorized',
          );
          const harmony = DiscoveredDevice(
            id: '127.0.0.1:5555',
            status: 'device',
            isHarmony: true,
          );
          Future<void> publishDevices(List<DiscoveredDevice> emulators) async {
            devices.add([...physicalDevices, ...emulators]);
            await tester.pumpAndSettle();
          }

          await publishDevices([]);
          expectEntry('emulators', selected: false);
          await publishDevices([android]);
          expectEntry('emulators', selected: false, running: true);
          await publishDevices([]);
          expectEntry('emulators', selected: false);
          await publishDevices([harmony]);
          expectEntry('emulators', selected: false, running: true);
          await publishDevices([
            const DiscoveredDevice(
              id: 'emulator-5556',
              status: 'device',
              isHarmony: true,
            ),
          ]);
          expectEntry('emulators', selected: false, running: true);
          await publishDevices([]);
          expectEntry('emulators', selected: false);

          ios.booted = true;
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expectEntry('emulators', selected: false, running: true);
          await publishDevices([android, harmony]);
          ios.booted = false;
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          await publishDevices([harmony]);
          container.read(selectedToolTabProvider.notifier).select(-2);
          await tester.pumpAndSettle();
          expectEntry('emulators', selected: true, running: true);
          await publishDevices([]);
          expectEntry('emulators', selected: true);
          expect(hdc.queriedTargets, [
            '127.0.0.1:6000',
            '127.0.0.1:5555',
            '127.0.0.1:5555',
          ]);
          container.read(selectedToolTabProvider.notifier).select(-1);
          await tester.pumpAndSettle();
          for (final key in ['receiverCenter', 'harmonyShareTitle', 'aiMcp']) {
            expectEntry(key, selected: false);
          }

          final mcp = container.read(mcpServerProvider.notifier) as _Mcp;
          mcp.setRunning(true);
          share.update(enabled: true, scanning: true);
          await publishDevices([android]);
          await pumpRail(receiverRunning: true);
          expectEntry('devices', selected: true);
          for (final key in ['receiverCenter', 'harmonyShareTitle', 'aiMcp']) {
            expectEntry(key, selected: false, running: true);
          }

          // 页面切换只移动高亮，三个后台服务的运行圆点继续显示。
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

          // 服务运行中只更新 Theme，保留原侧栏 Element、Provider 与当前页面。
          final railElement = tester.element(find.byType(PrimaryRail));
          final selectedBeforeTheme = container.read(selectedToolTabProvider);
          final mcpBeforeTheme = container.read(mcpServerProvider);
          theme = buildAppTheme(brightness, themeColor: AppThemeColor.pink);
          await pumpRail(receiverRunning: true);
          expect(tester.element(find.byType(PrimaryRail)), same(railElement));
          expect(container.read(selectedToolTabProvider), selectedBeforeTheme);
          expect(container.read(mcpServerProvider.notifier), same(mcp));
          expect(container.read(mcpServerProvider), same(mcpBeforeTheme));
          expect(share.enabled, isTrue);
          expect(share.scanning, isTrue);
          expectEntry('devices', selected: false);
          expectEntry('aiMcp', selected: true, running: true);
          expectEntry('receiverCenter', selected: false, running: true);
          expectEntry('harmonyShareTitle', selected: false, running: true);
          expectEntry('emulators', selected: false, running: true);

          // 选中页停服仍高亮；其他已停服务不残留运行圆点。
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
          await tester.pump();
          final queriesAfterUnmount = ios.queries;
          await tester.pump(const Duration(seconds: 10));
          expect(ios.queries, queriesAfterUnmount);
        });
      }
    }
  }
}
