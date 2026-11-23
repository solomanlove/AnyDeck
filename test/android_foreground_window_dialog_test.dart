import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/features/widgets/android_foreground_window_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 检查控制页与投屏共用的弹窗在成功、空结果和失败时的可见文案。
void main() {
  const component = 'com.ubrmb.app/com.ubrmb.app.ui.MainActivity';
  testWidgets('成功时只显示可选中的组件名，可通过关闭按钮退出', (tester) async {
    await _openDialog(
      tester,
      const AdbResult(exitCode: 0, stdout: component, stderr: ''),
    );
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).title, isNull);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      component,
    );

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AndroidForegroundWindowDialog), findsNothing);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('${locale.languageCode} 无组件时显示当前语言的空状态', (tester) async {
      await _openDialog(
        tester,
        const AdbResult(exitCode: 0, stdout: '', stderr: ''),
        locale: locale,
      );
      final l10n = AppLocalizations(locale);
      expect(find.text(l10n.t('foregroundUnavailable')), findsOneWidget);
    });
  }

  testWidgets('ADB 查询失败时展示错误信息', (tester) async {
    await _openDialog(
      tester,
      const AdbResult(exitCode: 1, stdout: '', stderr: 'device offline'),
    );
    expect(find.text('错误'), findsOneWidget);
    expect(find.text('device offline'), findsOneWidget);
  });
}

Future<void> _openDialog(
  WidgetTester tester,
  AdbResult result, {
  Locale locale = const Locale('zh'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AndroidForegroundWindowDialog(result: result),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
