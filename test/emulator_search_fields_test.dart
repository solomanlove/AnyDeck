import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_providers.dart';
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

/// 固定空列表，验证搜索框样式与清除交互，不启动平台扫描或模拟器。
void main() {
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
                  emulatorListProvider.overrideWith((ref) async => []),
                  emulatorConnectionsProvider.overrideWith((ref) async => {}),
                  devecoEmulatorsProvider.overrideWith((ref) async => []),
                  iosSimulatorsProvider.overrideWith((ref) async => []),
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
              devecoEmulatorsProvider.overrideWith((ref) async => []),
              iosSimulatorsProvider.overrideWith((ref) async => []),
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
