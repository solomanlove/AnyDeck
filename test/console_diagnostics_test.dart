import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/console/console_window_panel.dart';
import 'package:any_deck/app/widget/local_log_capture_button.dart';
import 'package:any_deck/core/logging/log_service.dart';
import 'package:any_deck/features/developer/widget/developer_local_logs_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 隔离原生窗口通道，验证故障日志不会被 UI 默认筛选误隐藏。
class _FixtureLogs extends LogService {
  @override
  List<String> build() => [
    '2026-10-04T00:00:00.001 I [main] adb: devices -l',
    '2026-10-04T00:00:00.002 E [main] adb: devices -l failed\n#0 stack',
    '2026-10-04T00:00:00.003 W [main] app: warning',
    '2026-10-04T00:00:00.004 I [main] app: connected',
  ];

  @override
  Future<void> syncHistory() async {}
}

void main() {
  for (final embedded in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets('控制台导出样式与自适应布局 embedded=$embedded $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(900, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [logHistoryProvider.overrideWith(_FixtureLogs.new)],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const [AppLocalizationsDelegate()],
              theme: buildAppTheme(brightness),
              home: Scaffold(body: ConsoleWindowPanel(isEmbedded: embedded)),
            ),
          ),
        );
        await tester.pump();
        final exportButton = find.descendant(
          of: find.byType(LocalLogCaptureButton),
          matching: find.byType(IconButton),
        );
        final filterButton = find.descendant(
          of: find.byKey(const Key('consoleKeyLogsFilter')),
          matching: find.byType(IconButton),
        );
        expect(tester.getSize(exportButton), const Size.square(36));
        final exportStyle = tester.widget<IconButton>(exportButton).style!;
        final filterStyle = tester.widget<IconButton>(filterButton).style!;
        // 普通、Hover 和按下状态保持相同的颜色、圆角及交互覆盖层。
        for (final states in <Set<WidgetState>>[
          {},
          {WidgetState.hovered},
          {WidgetState.pressed},
        ]) {
          expect(
            exportStyle.foregroundColor?.resolve(states),
            filterStyle.foregroundColor?.resolve(states),
          );
          expect(
            exportStyle.backgroundColor?.resolve(states),
            filterStyle.backgroundColor?.resolve(states),
          );
          expect(
            exportStyle.shape?.resolve(states),
            filterStyle.shape?.resolve(states),
          );
          expect(
            exportStyle.overlayColor?.resolve(states),
            filterStyle.overlayColor?.resolve(states),
          );
        }
        if (!embedded) {
          final searchWidth = tester.getSize(find.byType(TextField)).width;
          final searchRight = tester.getTopRight(find.byType(TextField)).dx;
          expect(tester.getTopLeft(filterButton).dx - searchRight, 8);
          expect(
            tester.getTopLeft(exportButton).dx -
                tester.getTopRight(filterButton).dx,
            8,
          );
          tester.view.physicalSize = const Size(1100, 700);
          await tester.pump();
          expect(
            tester.getSize(find.byType(TextField)).width,
            searchWidth + 200,
          );
          expect(
            tester.getTopRight(find.byIcon(Icons.monitor_heart_outlined)).dx -
                tester.getTopRight(exportButton).dx,
            35,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('控制台时间使用空格分隔日期与时间', () {
    expect(
      formatConsoleTimestamp('2026-10-17T08:41:02.540920'),
      '2026-10-17 08:41:02.540920',
    );
    expect(formatConsoleTimestamp('08:41:02.540920'), '08:41:02.540920');
  });

  testWidgets('隐藏心跳保留错误，关键日志筛选排除普通信息', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [logHistoryProvider.overrideWith(_FixtureLogs.new)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizationsDelegate()],
          theme: buildAppTheme(Brightness.light),
          home: const Scaffold(body: ConsoleWindowPanel()),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('devices -l failed', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('app: connected', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('consoleKeyLogsFilter')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('devices -l failed', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('app: connected', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('2026-10-04 00:00:00.002', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('View AnyDeck runtime logs, commands, and errors'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('consoleTitleArea'))).width,
      320,
    );
    final description = tester.widget<Text>(
      find.byKey(const Key('consoleDescription')),
    );
    expect(description.softWrap, isFalse);
    expect(description.overflow, isNull);
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.byKey(const Key('consoleDescription')),
          )
          .didExceedMaxLines,
      isFalse,
    );
    expect(find.byTooltip('Export logs'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'devices -l failed');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export logs'));
    await tester.pumpAndSettle();
    expect(find.text('Export current filter (1 records)'), findsOneWidget);
    expect(find.text('Capture all history (ignores filters)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('调试日志卡片 $language $brightness', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(body: DeveloperLocalLogsCard()),
            ),
          ),
        );
        expect(
          find.text(language == 'zh' ? '抓取本地日志' : 'Capture local logs'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
