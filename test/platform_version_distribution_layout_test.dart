// 验证系统版本页面的固定首尾、正文滚轮交互及窄窗口大字号下的阅读。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart';
import 'package:any_deck/features/overview/widget/harmony_distribution_details_pane.dart';
import 'package:any_deck/features/overview/widget/ios_distribution_details_pane.dart';
import 'package:any_deck/features/overview/widget/platform_version_distribution_shell_view.dart';
import 'package:any_deck/features/overview/widget/platform_version_switcher.dart';
import 'package:any_deck/features/overview/widget/system_versions_page.dart';
import 'package:any_deck/features/overview/widget/version_distribution_layout.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';

const _delegates = [
  AppLocalizationsDelegate(),
  ...GlobalMaterialLocalizations.delegates,
];

/// 将桌面滚轮事件发送至指定窗口坐标，等待滚动后的布局稳定。
Future<void> _wheel(WidgetTester tester, Offset point, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(position: point, scrollDelta: Offset(0, delta)),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (width, scale) in [(860.0, 1.0), (320.0, 1.6)]) {
    testWidgets('主窗口平台切换器固定在标题栏右侧 $width × $scale', (tester) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: _delegates,
            home: Scaffold(body: SystemVersionsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final header = find.byType(DashboardHeaderBar);
      final switcher = find.descendant(
        of: header,
        matching: find.byType(PlatformVersionSwitcher),
      );
      final headerRect = tester.getRect(header);
      final switcherRect = tester.getRect(switcher);
      expect(switcherRect.right, headerRect.right - 28);
      expect(switcherRect.center.dy, closeTo(headerRect.center.dy, 1));
      expect(switcherRect.intersect(headerRect), switcherRect);
      for (final platform in PlatformDistributionType.values) {
        expect(
          find
              .descendant(
                of: switcher,
                matching: find.text(platform.displayName),
              )
              .hitTestable(),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final mainWindow in [true, false]) {
    testWidgets('${mainWindow ? '主窗口' : '独立窗口'}三平台仅正文响应滚轮，标题和页脚固定', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(820, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: _delegates,
            home: Scaffold(
              body: mainWindow
                  ? const SystemVersionsPage()
                  : const PlatformVersionDistributionShellView(
                      isStandaloneWindow: true,
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final switcher = find.byType(PlatformVersionSwitcher);
      final l10n = tester.element(switcher).l10n;
      for (final platform in PlatformDistributionType.values) {
        await tester.tap(
          find.descendant(
            of: switcher,
            matching: find.text(platform.displayName),
          ),
        );
        // DragToMoveArea 需先完成标题栏双击判定。
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        expect(
          tester.widget<PlatformVersionSwitcher>(switcher).selectedPlatform,
          platform,
        );
        final title = find.text(
          l10n.t(mainWindow ? 'systemVersions' : platform.titleL10nKey),
        );
        final footer = find.text(
          '${l10n.t('lastUpdatedPrefix')}${platform.lastUpdatedDate}',
        );
        final fixed = [title, switcher, footer];
        final before = fixed.map(tester.getRect).toList();
        for (final widget in fixed) {
          expect(widget.hitTestable(), findsOneWidget);
          expect(
            find.ancestor(of: widget, matching: find.byType(Scrollable)),
            findsNothing,
          );
        }
        final layout = find.byType(VersionDistributionLayout);
        final list = find
            .descendant(of: layout, matching: find.byType(Scrollable))
            .first;
        final detailsPane = find
            .descendant(of: layout, matching: find.byType(SelectionArea))
            .first;
        final details = find
            .descendant(of: detailsPane, matching: find.byType(Scrollable))
            .first;
        final listPosition = tester.state<ScrollableState>(list).position;
        final detailsPosition = tester.state<ScrollableState>(details).position;

        await _wheel(tester, tester.getCenter(list), 90);
        expect(listPosition.pixels, greaterThan(0));
        final listOffset = listPosition.pixels;
        expect(detailsPosition.pixels, 0);
        final point = tester.getCenter(details);
        await _wheel(tester, point, 90);
        expect(detailsPosition.pixels, greaterThan(0));
        expect(listPosition.pixels, listOffset);

        // 到达详情上下端后继续滚动，外框和相邻版本列表也不能被带走。
        for (final delta in [100000.0, -100000.0]) {
          await _wheel(tester, point, delta);
          final edge = delta > 0
              ? detailsPosition.maxScrollExtent
              : detailsPosition.minScrollExtent;
          expect(detailsPosition.pixels, edge);
          await _wheel(tester, point, delta);
          expect(detailsPosition.pixels, edge);
          expect(listPosition.pixels, listOffset);
          expect(fixed.map(tester.getRect), orderedEquals(before));
        }
        for (final widget in fixed) {
          await _wheel(tester, tester.getCenter(widget), 120);
          expect(listPosition.pixels, listOffset);
          expect(detailsPosition.pixels, 0);
          expect(fixed.map(tester.getRect), orderedEquals(before));
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('624×180 主窗口可点选版本，大字号英文页脚完整且正文可滚动', (tester) async {
    tester.view.physicalSize = const Size(624, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _delegates,
          home: Scaffold(body: SystemVersionsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final frame = tester.widget<VersionDistributionPageLayout>(
      find.byType(VersionDistributionPageLayout),
    );
    final top = tester.getRect(find.byWidget(frame.header));
    final bottom = tester.getRect(find.byWidget(frame.footer));
    final body = Rect.fromLTRB(top.left, top.bottom, bottom.right, bottom.top);
    final list = find
        .descendant(
          of: find.byType(VersionDistributionLayout),
          matching: find.byType(Scrollable),
        )
        .first;
    final visibleList = tester.getRect(list).intersect(body);
    expect(visibleList.height, greaterThan(0));
    final version = find.descendant(of: list, matching: find.text('16   B'));
    final step = (visibleList.height / 2).clamp(1.0, 30.0);
    // 只在未被固定栏遮挡的列表区域发送滚轮，不跳转到预构建条目的位置。
    for (var i = 0; i < 150; i++) {
      await _wheel(tester, visibleList.center, step);
      if (version.hitTestable().evaluate().isNotEmpty) break;
    }
    expect(tester.state<ScrollableState>(list).position.pixels, greaterThan(0));
    expect(version.hitTestable(), findsOneWidget);
    await tester.tap(version);
    await tester.pumpAndSettle();
    expect(find.text('Android 16  •  API 36'), findsOneWidget);
    expect(tester.getRect(find.byWidget(frame.header)), top);
    expect(tester.getRect(find.byWidget(frame.footer)), bottom);
    expect(tester.takeException(), isNull);

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final switcher = find.byType(PlatformVersionSwitcher);
    final l10n = tester.element(switcher).l10n;
    for (final platform in [
      PlatformDistributionType.harmony,
      PlatformDistributionType.ios,
    ]) {
      await tester.tap(
        find.descendant(
          of: switcher,
          matching: find.text(platform.displayName),
        ),
      );
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      final page = tester.widget<VersionDistributionPageLayout>(
        find.byType(VersionDistributionPageLayout),
      );
      final header = tester.getRect(find.byWidget(page.header));
      final footer = tester.getRect(find.byWidget(page.footer));
      for (final text in [
        '${l10n.t('lastUpdatedPrefix')}${platform.lastUpdatedDate}',
        platform.localizedFlagNotice('en'),
      ]) {
        final label = find.text(text, findRichText: true);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse);
        final textRect = tester.getRect(label);
        expect(textRect.isEmpty, isFalse);
        expect(textRect.intersect(footer), textRect);
      }
      final visible = tester
          .getRect(list)
          .intersect(
            Rect.fromLTRB(header.left, header.bottom, footer.right, footer.top),
          );
      expect(visible.height, greaterThan(0));
      final position = tester.state<ScrollableState>(list).position;
      final initial = position.pixels;
      await _wheel(tester, visible.center, 40);
      expect(position.pixels, greaterThan(initial));
      expect(tester.getRect(find.byWidget(page.footer)), footer);
      expect(tester.takeException(), isNull);
    }
  });

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
      final switcher = find.byType(PlatformVersionSwitcher);
      final l10n = tester.element(switcher).l10n;
      for (final platform in PlatformDistributionType.values) {
        // 阅读正文后，固定的平台切换器仍可直接点击。
        final tab = find.descendant(
          of: switcher,
          matching: find.text(platform.displayName),
        );
        expect(tab.hitTestable(), findsOneWidget);
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
        localizationsDelegates: _delegates,
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
