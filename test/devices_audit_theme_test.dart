import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'package:any_deck/core/emulator/emulator_process.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_providers.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/devices/model/device_context_action.dart';
import 'package:any_deck/features/devices/widgets/deveco_emulators_view.dart';
import 'package:any_deck/features/devices/widgets/device_connection_indicators.dart';
import 'package:any_deck/features/devices/widgets/ios_simulators_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 隔离真实模拟器进程和启动状态监听，仅消费替代连接结果。
class _Launch extends EmulatorLaunchNotifier {
  @override
  Map<String, EmulatorLaunchState> build() => {};
}

Widget _app(Widget child, Brightness brightness, AppThemeColor color) =>
    MaterialApp(
      theme: buildAppTheme(brightness, themeColor: color),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: child),
    );

/// 从真实表格定位状态圆点，不依赖私有组件类名。
Iterable<BoxDecoration> _runtimeDots(WidgetTester tester, double diameter) =>
    tester
        .widgetList<Container>(find.byType(Container))
        .where((widget) => widget.constraints?.maxWidth == diameter)
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.shape == BoxShape.circle);

void main() {
  for (final brightness in Brightness.values) {
    for (final platform in ['Android', 'DevEco', 'iOS']) {
      testWidgets('$platform 运行圆点动态换色，停机后恢复灰色 $brightness', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var running = true;
        final container = ProviderContainer(
          overrides: [
            emulatorListProvider.overrideWith(
              (ref) async => [const AndroidEmulator(name: 'Audit_Emulator')],
            ),
            emulatorLaunchProvider.overrideWith(_Launch.new),
            emulatorConnectionsProvider.overrideWith(
              (ref) async => {
                if (running)
                  'Audit_Emulator': const DiscoveredDevice(
                    id: 'emulator-5554',
                    status: 'device',
                  ),
              },
            ),
            devecoEmulatorsProvider.overrideWith(
              (ref) async => [
                DevEcoEmulator(
                  name: 'Audit DevEco',
                  apiVersion: 'API 12',
                  deviceType: 'Phone',
                  state: running ? 'Running' : 'Stopped',
                ),
              ],
            ),
            iosSimulatorsProvider.overrideWith(
              (ref) async => [
                IosSimulator(
                  udid: 'audit-ios',
                  name: 'Audit iOS',
                  runtime: 'iOS 26',
                  deviceTypeIdentifier: 'iPhone',
                  state: running ? 'Booted' : 'Shutdown',
                  isAvailable: true,
                ),
              ],
            ),
          ],
        );
        addTearDown(container.dispose);
        final color = ValueNotifier(AppThemeColor.blue);
        addTearDown(color.dispose);
        final page = switch (platform) {
          'Android' => const EmulatorListPanel(isFullPage: true),
          'DevEco' => const DevecoEmulatorsView(),
          _ => const IosSimulatorsView(),
        };
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ValueListenableBuilder<AppThemeColor>(
              valueListenable: color,
              child: page,
              builder: (context, selected, child) =>
                  _app(child!, brightness, selected),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Audit');
        await tester.pumpAndSettle();
        final element = tester.element(find.byWidget(page));
        for (final selected in [AppThemeColor.blue, AppThemeColor.pink]) {
          color.value = selected;
          await tester.pumpAndSettle();
          expect(tester.element(find.byWidget(page)), same(element));
          expect(
            _runtimeDots(tester, platform == 'Android' ? 10 : 8).single.color,
            selected.color,
          );
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            'Audit',
          );
          if (platform != 'Android') {
            expect(
              tester.widget<Text>(find.text('已运行')).style!.color,
              selected.color,
            );
          }
        }
        running = false;
        container.invalidate(emulatorConnectionsProvider);
        container.invalidate(devecoEmulatorsProvider);
        container.invalidate(iosSimulatorsProvider);
        await tester.pumpAndSettle();
        expect(
          _runtimeDots(tester, platform == 'Android' ? 10 : 8).single.color,
          platform == 'Android'
              ? const Color(0xFF9E9E9E)
              : Colors.grey.shade400,
        );
        if (platform != 'Android') {
          expect(
            tester.widget<Text>(find.text('已停止')).style!.color,
            Colors.grey,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('AirPlay 连接标记动态换色且断开后隐藏 $brightness', (tester) async {
      const device = RegisteredDevice(
        id: 'airplay-test',
        model: 'iPhone',
        status: 'offline',
        isOnline: false,
      );
      for (final selected in [AppThemeColor.blue, AppThemeColor.pink]) {
        await tester.pumpWidget(
          _app(
            const DeviceConnectionIndicators(
              device: device,
              isAirplayMirroring: true,
            ),
            brightness,
            selected,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<Icon>(find.byIcon(Icons.airplay_rounded)).color,
          selected.color,
        );
      }
      await tester.pumpWidget(
        _app(
          const DeviceConnectionIndicators(device: device),
          brightness,
          AppThemeColor.pink,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.airplay_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('批量计划任务的选中标签使用主题色 $brightness', (tester) async {
      await withDeviceMenu(
        tester,
        (fixture) async {
          // 进入批量模式保留预选快照，直接使用工具栏上的定时任务入口。
          expect(find.byType(Checkbox), findsNothing);
          await tester.tap(find.byKey(const Key('deviceBatchManage')));
          await tester.pumpAndSettle();
          final device = find.byKey(const ValueKey('device-wall-device-a'));
          expect(
            tester
                .widget<Checkbox>(
                  find.descendant(of: device, matching: find.byType(Checkbox)),
                )
                .value,
            isTrue,
          );
          final schedule = find.byKey(const Key('deviceBatch-schedule'));
          expect(
            tester.widget<TextButton>(schedule).onPressed,
            isNotNull,
          );
          await tester.ensureVisible(schedule);
          await tester.tap(schedule);
          await tester.pumpAndSettle();
          final label = find.text('创建新任务');
          expect(label, findsOneWidget);
          final theme = Theme.of(tester.element(label));
          expect(
            DefaultTextStyle.of(tester.element(label)).style.color,
            theme.colorScheme.primary,
          );
          await tester.tap(find.text('任务管理列表'));
          await tester.pumpAndSettle();
          expect(find.text('暂无计划任务'), findsOneWidget);
          expect(
            DefaultTextStyle.of(
              tester.element(find.text('任务管理列表')),
            ).style.color,
            theme.colorScheme.primary,
          );
          expect(
            fixture.router.routeInformationProvider.value.uri.path,
            '/devices',
          );
          expect(tester.takeException(), isNull);
        },
        devices: [deviceMenuAndroid.copyWith(isChecked: true)],
        brightness: brightness,
        themeColor: AppThemeColor.pink,
      );
    });

    testWidgets('AirPlay 在设备墙与列表保留状态、主题与可用投屏入口 $brightness', (tester) async {
      for (final selected in [AppThemeColor.blue, AppThemeColor.pink]) {
        await withDeviceMenu(
          tester,
          (fixture) async {
            final l10n = AppLocalizations(const Locale('zh'));
            final footer = tester.getRect(
              find.byKey(const Key('hostNetworkFooter')),
            );
            for (final view in ['wall', 'list', 'wall']) {
              final switcher = find.byKey(Key('deviceView-$view'));
              await tester.tap(switcher);
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<TextButton>(switcher)
                    .style
                    ?.foregroundColor
                    ?.resolve({}),
                Theme.of(tester.element(switcher)).colorScheme.onSurface,
              );
              final device = find.byKey(
                ValueKey('device-${view == 'wall' ? 'wall' : 'row'}-airplay-1'),
              );
              // 同一设备在两种视图中的滚动区域都贴齐状态栏的左右上角。
              final viewport = find.ancestor(
                of: device,
                matching: find.byType(Viewport),
              ).first;
              expect(tester.getBottomLeft(viewport), footer.topLeft);
              expect(tester.getBottomRight(viewport), footer.topRight);
              final status = find.descendant(
                of: device,
                matching: find.text(
                  l10n.t(
                    'deviceWorkspaceAirplayConnection',
                  ),
                ),
              );
              expect(status, findsOneWidget);
              expect(find.descendant(of: device, matching: find.byWidgetPredicate(
                (widget) => widget is Tooltip && widget.message == l10n.t('deviceWorkspaceAirplay'),
              )), findsOneWidget);
              final theme = Theme.of(tester.element(status));
              expect(theme.colorScheme.primary, selected.color);
              expect(
                tester.widget<Text>(status).style?.color,
                theme.appColors.success,
              );

              // 更多入口确实提供可用投屏操作，查看与关闭菜单不切走当前设备页。
              await tester.tap(
                find.descendant(of: device, matching: find.byType(IconButton)),
              );
              await tester.pumpAndSettle();
              final entries = tester
                  .widgetList<PopupMenuItem<DeviceContextAction>>(
                    find.byType(PopupMenuItem<DeviceContextAction>),
                  );
              expect(entries.map((entry) => entry.value), [
                DeviceContextAction.mirror,
              ]);
              expect(entries.single.enabled, isTrue);
              expect(
                fixture.router.routeInformationProvider.value.uri.path,
                '/devices',
              );
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(
                find.byType(PopupMenuItem<DeviceContextAction>),
                findsNothing,
              );
              expect(
                fixture.router.routeInformationProvider.value.uri.path,
                '/devices',
              );
            }
            expect(tester.takeException(), isNull);
          },
          devices: const [],
          brightness: brightness,
          themeColor: selected,
          airplay: const AirPlaySessionData(
            id: 1,
            serverName: 'AnyDeck',
            rtspPort: 0,
            videoPort: 0,
            status: AirPlayServerStatus.mirroring,
            clientName: 'AirPlay audit',
            width: 720,
            height: 1280,
          ),
        );
      }
    });
  }
}
