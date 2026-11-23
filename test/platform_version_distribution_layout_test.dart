// 验证系统版本独立窗口在窄屏、低高度及放大字号下的阅读和版本选择。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart';
import 'package:any_deck/features/overview/widget/harmony_distribution_details_pane.dart';
import 'package:any_deck/features/overview/widget/ios_distribution_details_pane.dart';
import 'package:any_deck/features/overview/widget/platform_version_distribution_shell_view.dart';
import 'package:any_deck/features/overview/widget/platform_version_switcher.dart';
import 'package:any_deck/features/overview/widget/version_distribution_layout.dart';

void main() {
  for (final (size, scale) in [
    (const Size(460, 480), 1.0),
    (const Size(620, 340), 2.0),
    (const Size(748, 340), 2.0),
  ]) {
    testWidgets('窄版本窗口标题与操作完整可读 $size × $scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizationsDelegate()],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: PlatformVersionDistributionShellView()),
        ),
      );
      final switcher = find.byType(
        PlatformVersionSwitcher,
        skipOffstage: false,
      );
      final l10n = tester.element(switcher).l10n;
      for (final platform in PlatformDistributionType.values) {
        // 低窗口向下阅读后，平台切换器所在的 Sliver 可能在视口外。
        final tab = find.descendant(
          of: switcher,
          matching: find.text(platform.displayName, skipOffstage: false),
          skipOffstage: false,
        );
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
        final label = l10n.t(platform.titleL10nKey);
        final title = find.text(label);
        final titleRect = tester.getRect(title);
        expect(titleRect.overlaps(tester.getRect(switcher)), isFalse);
        // 检查最后一个字符的排版范围，确保换行后的标题未被固定高度裁切。
        final paragraph = tester.renderObject<RenderParagraph>(title);
        final lastGlyph = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: label.length - 1,
                extentOffset: label.length,
              ),
            )
            .single;
        expect(lastGlyph.bottom, lessThanOrEqualTo(titleRect.height + 1));
        if (platform == PlatformDistributionType.android && scale > 1) {
          // 回到版本列表并选中长代号，详情应显示对应的 API 数字。
          final list = find
              .descendant(
                of: find.byType(VersionDistributionLayout),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.ensureVisible(list);
          await tester.pumpAndSettle();
          final entry = find.text('4.0   Ice Cream Sandwich');
          await tester.scrollUntilVisible(entry, 100, scrollable: list);
          await Scrollable.ensureVisible(tester.element(entry), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(entry);
          await tester.pumpAndSettle();
          expect(find.text('Android 4.0  •  API 14'), findsOneWidget);
        }
        final close = find.widgetWithText(ElevatedButton, l10n.t('close'));
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        expect(close.hitTestable(), findsOneWidget);
        final notice = platform.localizedFlagNotice('en');
        if (notice.isNotEmpty) {
          final noticeRect = tester.getRect(find.text(notice));
          expect(
            noticeRect.right,
            lessThanOrEqualTo(tester.getRect(close).left),
          );
          if (scale > 1) {
            final history = find.textContaining('历史版本（');
            await tester.ensureVisible(history);
            await tester.pumpAndSettle();
            await tester.tap(history);
            await tester.pumpAndSettle();
            final oldest = find.text('${platform.displayName} 1.0');
            await tester.ensureVisible(oldest);
            await tester.pumpAndSettle();
            expect(oldest.hitTestable(), findsOneWidget);
          }
        }
      }
    });
  }

  testWidgets('窄窗口展开历史后可纵向读到最早记录并切换版本', (tester) async {
    tester.view.physicalSize = const Size(460, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(body: PlatformVersionDistributionShellView()),
      ),
    );
    for (final (platform, lastRecord, nextVersion, detailTitle) in [
      ('HarmonyOS', 'HarmonyOS 1.0', '6.1.1', 'HarmonyOS 6.1.1'),
      ('iOS', 'iOS 1.0', 'iOS 26', 'iOS 26'),
    ]) {
      await tester.tap(find.text(platform));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('历史版本（'));
      await tester.pumpAndSettle();

      // 历史表与版本选择各有独立的纵向滚动区域。
      final record = find.text(lastRecord);
      await tester.scrollUntilVisible(
        record.hitTestable(),
        50,
        scrollable: find
            .ancestor(of: record, matching: find.byType(Scrollable))
            .first,
      );
      expect(record.hitTestable(), findsOneWidget);
      final versions = find
          .descendant(
            of: find.byType(VersionDistributionLayout),
            matching: find.byType(Scrollable),
          )
          .first;
      final next = find.descendant(
        of: versions,
        matching: find.text(nextVersion),
      );
      await tester.scrollUntilVisible(
        next.hitTestable(),
        30,
        scrollable: versions,
      );
      await tester.tap(next);
      await tester.pumpAndSettle();
      final pane = find.byType(
        platform == 'iOS'
            ? IosDistributionDetailsPane
            : HarmonyDistributionDetailsPane,
      );
      expect(
        find.descendant(of: pane, matching: find.text(detailTitle)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
