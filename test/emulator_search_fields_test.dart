import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_providers.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/features/devices/widgets/deveco_emulators_view.dart';
import 'package:any_deck/features/devices/widgets/ios_simulators_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/search_field_expectations.dart';

/// 固定空列表，验证搜索框样式与清除交互，不启动平台扫描或模拟器。
void main() {
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
