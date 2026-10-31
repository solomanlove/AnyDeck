import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/overview/model/harmony_version_distribution_data.dart';
import 'package:any_deck/features/overview/model/android_version_distribution_data.dart';
import 'package:any_deck/features/overview/widget/system_versions_page.dart';
import 'package:any_deck/features/overview/widget/ios_adoption_samples.dart';

void main() {
  test('鸿蒙复制示例使用确定的兼容 API，不混入建议文案', () {
    for (final item in HarmonyVersionDistributionData.items) {
      final json = jsonDecode(
        item.buildProfileConfig.split('\n').skip(1).join('\n'),
      );
      final config = json['app']['products'][0];
      expect(config['compatibleSdkVersion'], isA<int>());
      expect(config['compatibleSdkVersion'], lessThanOrEqualTo(item.apiNum));
      expect(config['targetSdkVersion'], item.target);
    }
  });

  test('Android 17 发布状态不保留过期预测，核验日期独立于统计快照', () {
    final item = AndroidVersionDistributionData.findItem('17');
    expect(item.releaseDateZh, isNot(contains('预计')));
    expect(item.releaseDateEn, isNot(contains('Expected')));
    expect(item.releaseDateZh, contains('2026-10-31'));
    expect(
      AndroidVersionDistributionData.localizedLastUpdatedDate('en'),
      'October 13, 2026',
    );
  });

  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('1100 主窗口扣除侧栏后详情可达 $locale $brightness', (tester) async {
        tester.view.physicalSize = const Size(820, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(body: SystemVersionsPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final platform in ['Android', 'HarmonyOS', 'iOS']) {
          await tester.tap(find.text(platform));
          await tester.pumpAndSettle();
          await tester.tap(find.text(locale == 'zh' ? '查看详情' : 'View details'));
          await tester.pumpAndSettle();
          final scroll = tester.widget<SingleChildScrollView>(
            find.byKey(const Key('systemVersionsHorizontalScroll')),
          );
          expect(
            scroll.controller!.offset,
            scroll.controller!.position.maxScrollExtent,
          );
          expect(scroll.controller!.offset, greaterThan(0));
          expect(
            find
                .byType(Scrollbar)
                .evaluate()
                .any((e) => (e.widget as Scrollbar).thumbVisibility == true),
            true,
          );
          expect(tester.takeException(), null);
          await tester.tap(find.text(locale == 'zh' ? '版本列表' : 'Versions'));
          await tester.pumpAndSettle();
          expect(scroll.controller!.offset, 0);
        }
        expect(find.byType(IosAdoptionSamples), findsOneWidget);
        expect(find.textContaining('2026-09-30'), findsWidgets);
        expect(find.textContaining('2026-06-07'), findsWidgets);
        expect(find.byType(FractionallySizedBox), findsNothing);
      });
    }
  }
}
