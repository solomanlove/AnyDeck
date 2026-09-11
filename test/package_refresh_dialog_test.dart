import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/apps/package_refresh_progress.dart';
import 'package:any_deck/features/apps/widgets/package_refresh_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用可控刷新任务验证真实 Dialog 路由及键盘/遮罩交互。
Future<void> _mount(
  WidgetTester tester, {
  String language = 'zh',
  Brightness brightness = Brightness.light,
  required Future<void> Function(PackageRefreshCallback) refresh,
}) => tester.pumpWidget(
  MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPackageRefreshDialog(context, refresh: refresh),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('$language ${brightness.name} 显示阶段进度并在保存成功后自动关闭', (
        tester,
      ) async {
        final gate = Completer<void>();
        late PackageRefreshCallback report;
        var calls = 0;
        await _mount(
          tester,
          language: language,
          brightness: brightness,
          refresh: (callback) {
            calls++;
            report = callback;
            return gate.future;
          },
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text(
            language == 'zh' ? '正在读取应用信息…' : 'Reading app information…',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          isNull,
        );

        await tester.tapAt(const Offset(5, 5));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        final dialogContext = tester.element(find.byType(PackageRefreshDialog));
        await Navigator.of(dialogContext).maybePop();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(calls, 1);

        report(
          const PackageRefreshProgress(
            stage: PackageRefreshStage.enriching,
            processed: 150,
            total: 603,
          ),
        );
        await tester.pump();
        expect(
          find.text(
            language == 'zh' ? '已处理 150 / 603 个应用' : 'Processed 150 / 603 apps',
          ),
          findsOneWidget,
        );
        expect(find.text('24%'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          closeTo(150 / 603, .0001),
        );
        expect(
          Theme.of(tester.element(find.byType(AlertDialog))).brightness,
          brightness,
        );

        report(
          const PackageRefreshProgress(
            stage: PackageRefreshStage.saving,
            processed: 603,
            total: 603,
          ),
        );
        await tester.pump();
        expect(
          find.text(language == 'zh' ? '正在保存刷新结果…' : 'Saving refresh results…'),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final partial in [true, false]) {
    testWidgets('${partial ? '部分失败' : '整体异常'} 保留弹窗且允许关闭后重新刷新', (tester) async {
      var calls = 0;
      await _mount(
        tester,
        refresh: (report) async {
          calls++;
          if (!partial) throw StateError('device offline');
          report(
            const PackageRefreshProgress(
              stage: PackageRefreshStage.completed,
              processed: 53,
              total: 53,
              failed: 50,
            ),
          );
        },
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(partial ? '刷新结束，部分应用信息未能更新' : '刷新失败'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      if (partial) {
        expect(find.text('50 个应用未能完整刷新，可稍后重试。'), findsOneWidget);
      } else {
        expect(find.textContaining('device offline'), findsOneWidget);
      }
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('弹窗被外层销毁后不更新状态或误弹出其他页面', (tester) async {
    final gate = Completer<void>();
    late PackageRefreshCallback report;
    await _mount(
      tester,
      refresh: (callback) {
        report = callback;
        return gate.future;
      },
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    report(const PackageRefreshProgress(stage: PackageRefreshStage.saving));
    gate.completeError(StateError('disposed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
