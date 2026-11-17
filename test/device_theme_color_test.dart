import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/airplay/airplay_server_service.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'package:any_deck/core/emulator/emulator_process.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_providers.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/airplay/widgets/airplay_active_banner.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/devices/widgets/deveco_emulators_view.dart';
import 'package:any_deck/features/devices/widgets/device_airplay_row_widgets.dart';
import 'package:any_deck/features/devices/widgets/ios_simulators_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AirPlaySessionData(
  id: 1,
  serverName: 'AnyDeck-AirPlay',
  rtspPort: 7000,
  videoPort: 7100,
  status: AirPlayServerStatus.mirroring,
  clientName: 'iPhone',
);

/// 固定镜像会话，不启动原生 AirPlay 接收服务。
class _Session extends AirPlayServerNotifier {
  @override
  AirPlaySessionData? build() => _session;
}

/// 仅展示模拟器列表，不启动进程监测与 ADB 扫描。
class _Launch extends EmulatorLaunchNotifier {
  @override
  Map<String, EmulatorLaunchState> build() => {};
}

/// 动态替换主题并保留当前页面及其选择状态。
Future<ValueNotifier<AppThemeColor>> _pumpPage(
  WidgetTester tester, {
  required Widget child,
  required ProviderContainer container,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(container.dispose);
  final color = ValueNotifier(AppThemeColor.blue);
  addTearDown(color.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<AppThemeColor>(
        valueListenable: color,
        builder: (context, value, child) => MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildAppTheme(brightness, themeColor: value),
          home: child,
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return color;
}

void main() {
  for (final brightness in Brightness.values) {
    for (final platform in ['Android', 'DevEco', 'iOS']) {
      testWidgets('$platform 启动和选中行在 $brightness 动态跟随主色', (tester) async {
        final container = ProviderContainer(
          overrides: [
            emulatorListProvider.overrideWith(
              (ref) async => [const AndroidEmulator(name: 'Pixel_Test')],
            ),
            emulatorConnectionsProvider.overrideWith((ref) async => {}),
            emulatorLaunchProvider.overrideWith(_Launch.new),
            devecoEmulatorsProvider.overrideWith(
              (ref) async => [
                const DevEcoEmulator(
                  name: 'DevEco Test',
                  apiVersion: 'API 12',
                  deviceType: 'Phone',
                  state: 'Stopped',
                ),
              ],
            ),
            iosSimulatorsProvider.overrideWith(
              (ref) async => [
                const IosSimulator(
                  udid: 'ios-test',
                  name: 'iPhone Test',
                  runtime: 'iOS 26',
                  deviceTypeIdentifier: 'iPhone',
                  state: 'Shutdown',
                  isAvailable: true,
                ),
              ],
            ),
          ],
        );
        final color = await _pumpPage(
          tester,
          container: container,
          brightness: brightness,
          child: switch (platform) {
            'Android' => const EmulatorListPanel(isFullPage: true),
            'DevEco' => const DevecoEmulatorsView(),
            _ => const IosSimulatorsView(),
          },
        );
        await tester.tap(
          find.text(switch (platform) {
            'Android' => 'Pixel Test',
            'DevEco' => 'DevEco Test',
            _ => 'iPhone Test',
          }),
        );
        // Android / iOS 行同时支持双击启动，单击需等待双击判定结束。
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        for (final value in [AppThemeColor.blue, AppThemeColor.pink]) {
          color.value = value;
          await tester.pumpAndSettle();
          final button = tester.widget<FilledButton>(
            find.byType(FilledButton).first,
          );
          expect(button.onPressed, isNotNull);
          expect(button.style?.backgroundColor?.resolve({}), value.color);
          final theme = Theme.of(
            tester.element(find.byType(FilledButton).first),
          );
          final selectedFill = theme.colorScheme.primaryContainer.withValues(
            alpha: platform == 'Android' ? 0.4 : 0.35,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color == selectedFill,
            ),
            findsOneWidget,
          );
          if (platform == 'iOS') {
            expect(
              tester
                  .widget<Icon>(find.byIcon(CupertinoIcons.play_circle))
                  .color,
              value.color,
            );
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('AirPlay 打开入口在 $brightness 跟随主色，LIVE 状态保持绿色', (tester) async {
      final color = await _pumpPage(
        tester,
        container: ProviderContainer(
          overrides: [airplaySessionProvider.overrideWith(_Session.new)],
        ),
        brightness: brightness,
        child: Column(
          children: [
            const AirPlayActiveBanner(),
            const DeviceAirPlayLiveBadge(),
            DeviceAirPlayActionButtons(
              device: RegisteredDevice(
                id: 'airplay-test',
                status: 'device',
                isOnline: true,
                isIos: true,
              ),
              session: _session,
            ),
          ],
        ),
      );
      for (final value in [AppThemeColor.blue, AppThemeColor.pink]) {
        color.value = value;
        await tester.pumpAndSettle();
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.style?.backgroundColor?.resolve({}), value.color);
        final action = find.descendant(
          of: find.byType(DeviceAirPlayActionButtons),
          matching: find.byIcon(Icons.airplay_rounded),
        );
        expect(tester.widget<Icon>(action).color, value.color);
        expect(
          tester.widget<Text>(find.text('AirPlay LIVE')).style?.color,
          const Color(0xff34c759),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('概览装饰在 $brightness 跟随主色，充电与 Root 保持成功色', (tester) async {
      final color = await _pumpPage(
        tester,
        container: ProviderContainer(
          overrides: [
            deviceRootStatusProvider('test').overrideWith((ref) async => true),
          ],
        ),
        brightness: brightness,
        child: DeviceOverviewContent(
          device: const DiscoveredDevice(id: 'test', status: 'device'),
          overview: DeviceOverview.fromJson({
            'name': 'AnyDeck Test',
            'brand': 'Android',
            'androidVersion': 'Android 16 (API 36)',
            'memory': '8G',
            'memoryUsed': '4G',
            'storage': '64G / 128G',
            'battery': {'level': 80, 'chargingState': 'charging'},
          }),
          onRefresh: () {},
        ),
      );
      for (final value in [AppThemeColor.blue, AppThemeColor.pink]) {
        color.value = value;
        await tester.pumpAndSettle();
        for (final bar in tester.widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )) {
          expect(bar.color, value.color);
        }
        expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
        expect(
          tester.widget<Icon>(find.byIcon(CupertinoIcons.wifi)).color,
          value.color,
        );
        expect(
          tester.widget<Text>(find.text('API 36')).style?.color,
          value.color,
        );
        expect(
          tester.widget<Text>(find.text('80%')).style?.color,
          AppPalette.primary,
        );
        expect(
          tester.widget<Icon>(find.byIcon(CupertinoIcons.lock_open_fill)).color,
          AppPalette.primary,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
