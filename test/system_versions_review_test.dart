import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/overview/model/harmony_version_distribution_data.dart';
import 'package:any_deck/features/overview/model/android_version_distribution_data.dart';
import 'package:any_deck/features/overview/model/ios_version_distribution_data.dart';
import 'package:any_deck/features/overview/widget/system_versions_page.dart';
import 'package:any_deck/features/overview/widget/ios_adoption_samples.dart';
import 'package:any_deck/features/overview/widget/version_distribution_layout.dart';

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
      testWidgets('三平台版本资料随宽度重排、换行并可纵向阅读 $locale $brightness', (tester) async {
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
        final android = AndroidVersionDistributionData.findItem('17');
        final nextAndroid = AndroidVersionDistributionData.findItem('16');
        final nextHarmony = HarmonyVersionDistributionData.items[1];
        final nextIos = IosVersionDistributionData.items[1];
        for (final (platform, passage, versionLabel, detailTitle) in [
          (
            'Android',
            android.featureSections.last.localizedItems(locale).first,
            '${nextAndroid.platformVersion}   ${nextAndroid.codename}',
            'Android ${nextAndroid.platformVersion}  •  API ${nextAndroid.apiLevel}',
          ),
          (
            'HarmonyOS',
            HarmonyVersionDistributionData.items.first.impacts.last,
            nextHarmony.version,
            'HarmonyOS ${nextHarmony.version}',
          ),
          (
            'iOS',
            IosVersionDistributionData.items.first.impacts.last,
            'iOS ${nextIos.version}',
            'iOS ${nextIos.version}',
          ),
        ]) {
          await tester.tap(find.text(platform));
          await tester.pumpAndSettle();
          final layout = find.byType(VersionDistributionLayout);
          final list = find
              .descendant(of: layout, matching: find.bySubtype<ScrollView>())
              .first;
          final details = find
              .descendant(of: layout, matching: find.byType(SelectionArea))
              .first;
          for (final width in [820.0, 624.0]) {
            tester.view.physicalSize = Size(width, 780);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    axisDirectionToAxis(widget.axisDirection) ==
                        Axis.horizontal,
              ),
              findsNothing,
            );
            expect(
              find.text(
                locale == 'zh'
                    ? '可横向滚动阅读完整内容'
                    : 'Scroll horizontally for full content',
              ),
              findsNothing,
            );
            final listRect = tester.getRect(list);
            final detailsRect = tester.getRect(details);
            expect(detailsRect.right, lessThanOrEqualTo(width));
            if (width == 820) {
              expect(listRect.right, lessThanOrEqualTo(detailsRect.left));
            } else {
              expect(listRect.bottom, lessThanOrEqualTo(detailsRect.top));
            }
            // 检查真实排版的行框，单纯找到文本无法发现裁切和省略号。
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(passage, findRichText: true),
            );
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: passage.length),
            );
            expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
            expect(paragraph.didExceedMaxLines, isFalse);
          }
          final copyUrl = find.byTooltip(
            locale == 'zh' ? '复制 URL 地址' : 'Copy URL Address',
          );
          await tester.ensureVisible(copyUrl);
          await tester.pumpAndSettle();
          expect(copyUrl.hitTestable(), findsOneWidget);
          final next = find.descendant(
            of: list,
            matching: find.text(versionLabel),
          );
          // iOS 的同一分组卡片会提前构建多个版本，按实际可点击位置滚动。
          await tester.scrollUntilVisible(
            next.hitTestable(),
            80,
            scrollable: find.descendant(
              of: list,
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(next.hitTestable(), findsOneWidget);
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(
            find
                .descendant(of: details, matching: find.text(detailTitle))
                .hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        expect(find.byType(IosAdoptionSamples), findsOneWidget);
        expect(find.textContaining('2026-09-30'), findsWidgets);
        expect(find.textContaining('2026-06-07'), findsWidgets);
        expect(find.byType(FractionallySizedBox), findsNothing);
      });
    }
  }
}
