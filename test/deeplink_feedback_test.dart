import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/features/control/deeplink_feedback.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证真实 Toast 的文案与图标，覆盖 am start 的非标准失败输出。
void main() {
  final cases = <(String, AdbResult, bool)>[
    (
      '正常启动',
      const AdbResult(
        exitCode: 0,
        stdout:
            'Starting: Intent { act=android.settings.DEVICE_INFO_SETTINGS }',
        stderr: '',
      ),
      true,
    ),
    (
      '非零退出码',
      const AdbResult(exitCode: 1, stdout: '', stderr: 'permission denied'),
      false,
    ),
    (
      '零退出码的 stdout 错误',
      const AdbResult(
        exitCode: 0,
        stdout: 'Starting: Intent { act=test }\nError: Activity not started',
        stderr: '',
      ),
      false,
    ),
    (
      '零退出码的 stderr 错误',
      const AdbResult(
        exitCode: 0,
        stdout: 'Starting: Intent { act=test }',
        stderr: 'Error type 3\nError: Activity class does not exist.',
      ),
      false,
    ),
    (
      '已有 Activity 接收 Intent',
      const AdbResult(
        exitCode: 0,
        stdout: 'Starting: Intent { dat=myapp://Error:example }',
        stderr:
            'Warning: Activity not started, intent has been delivered to '
            'currently running top-most instance.',
      ),
      true,
    ),
  ];

  for (final locale in ['zh', 'en']) {
    for (final (name, result, success) in cases) {
      testWidgets('$locale $name 显示友好提示', (tester) async {
        await _pumpAction(tester, locale, () => Future.value(result));
        await tester.tap(find.text('go'));
        await tester.pump();
        final expected = locale == 'zh'
            ? (success ? '跳转成功' : '跳转失败')
            : (success ? 'Navigation successful' : 'Navigation failed');
        expect(find.text(expected), findsOneWidget);
        expect(
          find.byIcon(
            success
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.exclamationmark_circle_fill,
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Starting: Intent'), findsNothing);
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }

  testWidgets('执行异常显示失败提示', (tester) async {
    await _pumpAction(
      tester,
      'zh',
      () => Future.error(StateError('process failed')),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('跳转失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });
}

Future<void> _pumpAction(
  WidgetTester tester,
  String locale,
  Future<AdbResult> Function() action,
) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => runDeeplinkAction(context, ref, action()),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  ),
);
