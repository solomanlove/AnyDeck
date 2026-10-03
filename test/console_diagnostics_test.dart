import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/window/console/console_window_panel.dart';
import 'package:any_deck/core/logging/log_service.dart';
import 'package:any_deck/features/developer/widget/developer_local_logs_card.dart';
import 'package:flutter/material.dart';
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
  testWidgets('隐藏心跳保留错误，关键日志筛选排除普通信息', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [logHistoryProvider.overrideWith(_FixtureLogs.new)],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizationsDelegate()],
          home: Scaffold(body: ConsoleWindowPanel()),
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
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('devices -l failed', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('app: connected', findRichText: true),
      findsNothing,
    );
    expect(find.text('Capture local logs'), findsOneWidget);
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
