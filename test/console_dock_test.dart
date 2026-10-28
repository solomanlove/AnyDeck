import 'dart:convert';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/console/console_window_panel.dart';
import 'package:any_deck/core/logging/log_service.dart';
import 'package:any_deck/features/console/controller/console_dock_controller.dart';
import 'package:any_deck/features/console/widgets/console_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 直接提供主窗口汇总日志，避免测试访问真实文件和窗口通道。
class _Logs extends LogService {
  @override
  List<String> build() => ['2026-10-28T10:00:00.001 E [main] test: failure'];

  @override
  Future<void> syncHistory() async {}

  void append() => state = [
    ...state,
    '2026-10-28T10:00:01.001 W [window_2] test: new warning',
  ];
}

Future<ProviderContainer> _pumpDock(
  WidgetTester tester, {
  Size size = const Size(700, 600),
  String language = 'zh',
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [logHistoryProvider.overrideWith(_Logs.new)],
  );
  addTearDown(container.dispose);
  var count = 0;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildAppTheme(brightness),
        home: Scaffold(
          body: ConsoleDock(
            child: StatefulBuilder(
              builder: (context, setState) => Center(
                child: TextButton(
                  onPressed: () => setState(() => count++),
                  child: Text('workspace $count'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('打开、拖动、关闭和重新打开保留工作区状态与日志', (tester) async {
    final container = await _pumpDock(tester);
    expect(find.byType(ConsoleWindowPanel), findsNothing);
    await tester.tap(find.text('workspace 0'));
    await tester.pump();
    container.read(consoleDockProvider.notifier).toggle();
    await tester.pump();
    expect(find.text('workspace 1'), findsOneWidget);
    expect(
      find.textContaining('test: failure', findRichText: true),
      findsOneWidget,
    );

    final panel = find.byKey(const Key('consoleDockPanel'));
    final before = tester.getSize(panel).height;
    await tester.drag(
      find.byKey(const Key('consoleDockResizeHandle')),
      const Offset(0, -70),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, greaterThan(before));
    final resized = tester.getSize(panel).height;

    await tester.tap(find.byKey(const Key('consoleDockClose')));
    await tester.pump();
    expect(find.byType(ConsoleWindowPanel), findsNothing);
    (container.read(logHistoryProvider.notifier) as _Logs).append();
    container.read(consoleDockProvider.notifier).toggle();
    await tester.pump();
    expect(tester.getSize(panel).height, resized);
    expect(
      find.textContaining('new warning', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('workspace 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('最小宽度与缩小窗口 $language $brightness 不溢出', (tester) async {
        final container = await _pumpDock(
          tester,
          language: language,
          brightness: brightness,
        );
        container.read(consoleDockProvider.notifier).toggle();
        container.read(consoleDockProvider.notifier).resize(1000);
        await tester.pump();
        expect(
          tester.getSize(find.byKey(const Key('consoleDockPanel'))).height,
          412,
        );
        tester.view.physicalSize = const Size(624, 364);
        await tester.pump();
        expect(
          tester.getSize(find.byKey(const Key('consoleDockPanel'))).height,
          176,
        );
        expect(
          find.byKey(const Key('consoleDockPopOut')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('consoleDockClose')).hitTestable(),
          findsOneWidget,
        );
        // 屏幕尺寸变化只限制实际布局，不丢失原来的高度偏好。
        expect(container.read(consoleDockProvider).height, 1000);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('独立窗口打开失败保留底部日志，成功后复用窗口并收起面板', (tester) async {
    final container = await _pumpDock(tester);
    const channel = MethodChannel('mixin.one/desktop_multi_window');
    final messenger = tester.binding.defaultBinaryMessenger;
    var fail = true;
    var created = 0;
    final windows = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAllWindows') return windows;
      if (call.method == 'createWindow') {
        if (fail) throw PlatformException(code: 'window-failed');
        created++;
        final arguments = (call.arguments as Map)['arguments'] as String;
        expect(jsonDecode(arguments)['type'], 'console');
        windows.add({'windowId': 'console', 'windowArgument': arguments});
        return 'console';
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    container.read(consoleDockProvider.notifier).toggle();
    await tester.pump();
    await tester.tap(find.byKey(const Key('consoleDockPopOut')));
    await tester.pumpAndSettle();
    expect(container.read(consoleDockProvider).isOpen, isTrue);
    expect(find.text('无法打开独立控制台窗口，请重试。'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('consoleDockPopOut')));
    await tester.pumpAndSettle();
    expect(container.read(consoleDockProvider).isOpen, isFalse);
    expect(created, 1);
    container.read(consoleDockProvider.notifier).toggle();
    await tester.pump();
    await tester.tap(find.byKey(const Key('consoleDockPopOut')));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(container.read(consoleDockProvider).isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });
}
