import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'package:any_deck/core/emulator/emulator_ide_providers.dart';
import 'package:any_deck/core/emulator/emulator_ide_service.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_providers.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_service.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/devices/widgets/deveco_emulators_view.dart';
import 'package:any_deck/features/devices/widgets/device_list_filters.dart';
import 'package:any_deck/features/devices/model/device_workspace_view_state.dart';
import 'package:any_deck/features/devices/widgets/ios_simulators_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/search_field_expectations.dart';

const _androidEmulator = AndroidEmulator(name: 'Test_AVD');
const _devecoEmulator = DevEcoEmulator(
  name: 'Test DevEco',
  apiVersion: 'API 12',
  deviceType: 'Phone',
  state: 'Stopped',
);
const _iosSimulator = IosSimulator(
  udid: 'test-ios',
  name: 'Test iPhone',
  runtime: 'iOS 26',
  deviceTypeIdentifier: 'iPhone',
  state: 'Shutdown',
  isAvailable: true,
);

/// 用替代列表验证工具栏显示、搜索样式与清除交互。
void main() {
  for (final platform in ['Android', 'HarmonyOS', 'iOS']) {
    for (final width in [620.0, 1200.0]) {
      testWidgets('$platform 无本地模拟器时隐藏工具栏 $width', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.reset);
        final scan = Completer<void>();
        var hasEmulator = false;
        final container = ProviderContainer(
          overrides: [
            runningEmulatorCountsProvider.overrideWithValue((
              android: 0,
              harmony: platform == 'HarmonyOS' ? 1 : 0,
              ios: platform == 'iOS' ? 1 : 0,
            )),
            emulatorListProvider.overrideWith((ref) async {
              await scan.future;
              return [if (hasEmulator) _androidEmulator];
            }),
            emulatorConnectionsProvider.overrideWith((ref) async => {}),
            emulatorIdeServiceProvider.overrideWithValue(
              const EmulatorIdeService(platform: TargetPlatform.macOS),
            ),
            androidStudioAppPathProvider.overrideWith(
              (ref) async => '/Applications/Android Studio.app',
            ),
            xcodeAppPathProvider.overrideWith(
              (ref) async => '/Applications/Xcode.app',
            ),
            devecoEmulatorsProvider.overrideWith((ref) async {
              await scan.future;
              return [if (hasEmulator) _devecoEmulator];
            }),
            devecoEmulatorServiceProvider.overrideWithValue(
              const DevEcoEmulatorService(platform: TargetPlatform.macOS),
            ),
            devecoStudioAppPathProvider.overrideWith(
              (ref) async => '/Applications/DevEco-Studio.app',
            ),
            iosSimulatorsProvider.overrideWith((ref) async {
              await scan.future;
              return [if (hasEmulator) _iosSimulator];
            }),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: const Scaffold(body: EmulatorListPanel(isFullPage: true)),
            ),
          ),
        );
        final scanning = find.textContaining(switch (platform) {
          'Android' => '正在扫描',
          'HarmonyOS' => '正在扫描 DevEco 模拟器',
          _ => '正在扫描 Xcode 模拟器',
        });
        expect(scanning, findsOneWidget);

        final search = find.byType(TextField);
        final controls = [
          search,
          find.byIcon(CupertinoIcons.play_arrow),
          find.byIcon(CupertinoIcons.stop),
          find.byIcon(CupertinoIcons.refresh),
          find.byIcon(Icons.open_in_new),
          find.byType(Divider),
        ];
        final hint = find.textContaining(switch (platform) {
          'Android' => '在 Android Studio 中打开 Device Manager',
          'HarmonyOS' => '在 DevEco Studio 的 Tools',
          _ => 'Xcode → Open Developer Tool → Device Hub',
        });
        final simulator = find.text(switch (platform) {
          'Android' => _androidEmulator.displayName,
          'HarmonyOS' => _devecoEmulator.name,
          _ => _iosSimulator.name,
        });

        // 首次扫描与扫描完成后的实际空列表都隐藏整行与分隔线。
        for (final control in controls) {
          expect(control, findsNothing);
        }
        scan.complete();
        await tester.pumpAndSettle();
        for (final control in controls) {
          expect(control, findsNothing);
        }
        expect(hint, findsOneWidget);
        if (platform == 'HarmonyOS') {
          expect(
            find.widgetWithText(FilledButton, '打开 DevEco Studio'),
            findsOneWidget,
          );
        }

        void refreshList() {
          switch (platform) {
            case 'Android':
              container.invalidate(emulatorListProvider);
            case 'HarmonyOS':
              container.invalidate(devecoEmulatorsProvider);
            case 'iOS':
              container.invalidate(iosSimulatorsProvider);
          }
        }

        hasEmulator = true;
        refreshList();
        await tester.pumpAndSettle();
        expect(simulator, findsOneWidget);
        expect(hint, findsNothing);

        // 搜索无匹配时仍然能清除输入并恢复列表。
        await tester.enterText(search, 'no matches');
        await tester.pumpAndSettle();
        expect(simulator, findsNothing);
        expect(hint, findsNothing);
        expect(search, findsOneWidget);
        expect(find.byIcon(CupertinoIcons.refresh), findsOneWidget);
        expect(find.byType(Divider), findsOneWidget);
        await tester.tap(find.byIcon(CupertinoIcons.clear_circled));
        await tester.pumpAndSettle();
        expect(simulator, findsOneWidget);

        // 刷新发现本地列表变空后，即使曾输入关键词，也恢复平台引导。
        await tester.enterText(search, 'no matches');
        hasEmulator = false;
        refreshList();
        await tester.pumpAndSettle();
        for (final control in controls) {
          expect(control, findsNothing);
        }
        expect(hint, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  final emulatorHeights = <String, double>{};
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final platform in ['Android', 'HarmonyOS', 'iOS']) {
        testWidgets('$platform 模拟器保留统一高度，设备页采用紧凑搜索 $language $brightness', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          for (final layout in [
            (width: 1200.0, scale: 1.0),
            (width: 620.0, scale: 1.0),
            (width: 1200.0, scale: 1.6),
          ]) {
            tester.view.physicalSize = Size(layout.width, 900);
            await tester.pumpWidget(
              ProviderScope(
                key: UniqueKey(),
                overrides: [
                  runningEmulatorCountsProvider.overrideWithValue(noRunningEmulators),
                  emulatorListProvider.overrideWith(
                    (ref) async => [_androidEmulator],
                  ),
                  emulatorConnectionsProvider.overrideWith((ref) async => {}),
                  devecoEmulatorsProvider.overrideWith(
                    (ref) async => [_devecoEmulator],
                  ),
                  iosSimulatorsProvider.overrideWith(
                    (ref) async => [_iosSimulator],
                  ),
                ],
                child: MaterialApp(
                  locale: Locale(language),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AppLocalizationsDelegate(),
                    ...GlobalMaterialLocalizations.delegates,
                  ],
                  theme: buildAppTheme(brightness),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Column(
                      children: [
                        DeviceListFilters(
                          controller: controller,
                          onlineCount: 0,
                          totalCount: 0,
                          filter: DeviceStatusFilter.all,
                          onFilterChanged: (_) {},
                          viewMode: DeviceViewMode.wall,
                          onViewModeChanged: (_) {},
                          batchMode: false,
                          onBatchModeChanged: (_) {},
                          onSearchChanged: (_) {},
                        ),
                        Expanded(
                          child: switch (platform) {
                            'Android' => const EmulatorListPanel(
                              isFullPage: true,
                            ),
                            'HarmonyOS' => const DevecoEmulatorsView(),
                            _ => const IosSimulatorsView(),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final reference = find.byKey(const Key('deviceListSearch'));
            final search = find.byType(TextField).last;
            // 设备页按手机墙原型采用 36px / 8px 圆角；模拟器仍使用既有 40px / Tab 圆角。
            final referenceHeight = tester.getSize(reference).height;
            final searchHeight = tester.getSize(search).height;
            if (layout.scale == 1) {
              expect(referenceHeight, 36);
              expect(searchHeight, 40);
            } else {
              expect(referenceHeight, greaterThan(36));
              expect(searchHeight, greaterThan(40));
            }
            expectSearchFieldRadius(tester, reference,
              radius: AppThemeSizes.radiusMedium);
            final layoutKey = '$language-$brightness-${layout.width}-${layout.scale}';
            expect(searchHeight, emulatorHeights.putIfAbsent(layoutKey, () => searchHeight));
            expectSearchFieldRadius(tester, search, focused: false);
            await tester.enterText(search, 'no matches');
            await tester.pumpAndSettle();
            expect(tester.getSize(search).height, searchHeight);
            expectSearchFieldRadius(tester, search, focused: true);
            await tester.tap(
              find.descendant(
                of: search,
                matching: find.byIcon(CupertinoIcons.clear_circled),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.widget<TextField>(search).controller!.text, isEmpty);
            expect(tester.getSize(search).height, searchHeight);
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }

  for (final brightness in Brightness.values) {
    for (final platform in ['DevEco', 'iOS']) {
      testWidgets('$platform 搜索框复用 Tab 圆角并保留清除交互 $brightness', (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              devecoEmulatorsProvider.overrideWith(
                (ref) async => [_devecoEmulator],
              ),
              iosSimulatorsProvider.overrideWith(
                (ref) async => [_iosSimulator],
              ),
            ],
            child: MaterialApp(
              theme: buildAppTheme(brightness),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [AppLocalizationsDelegate()],
              home: Scaffold(
                body: platform == 'DevEco'
                    ? const DevecoEmulatorsView()
                    : const IosSimulatorsView(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final search = find.byType(TextField);
        expectSearchFieldRadius(tester, search, focused: false);
        await tester.enterText(search, 'no matches');
        await tester.pumpAndSettle();
        expectSearchFieldRadius(tester, search, focused: true);
        expect(find.textContaining('没有匹配 "no matches"'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: search,
            matching: find.byIcon(CupertinoIcons.clear_circled),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        expect(find.textContaining('没有匹配 "no matches"'), findsNothing);
        expectSearchFieldRadius(tester, search);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
