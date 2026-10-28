import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_history_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _History extends ShareTransferHistory {
  final rows = <ShareTransferRecord>[
    ShareTransferRecord(
      id: '1',
      direction: ShareTransferDirection.send,
      status: ShareTransferStatus.failed,
      deviceName: 'nova',
      address: '192.168.1.3',
      fileName: 'synthetic.bin',
      path: '/synthetic/file.bin',
      bytes: 100,
      createdAt: DateTime(2026, 10, 28),
      error: 'send_failed',
    ),
  ];
  final removed = <String>[];
  String search = '';
  ShareTransferDirection? direction;
  @override
  Future<List<ShareTransferRecord>> query({
    ShareTransferDirection? direction,
    String search = '',
    ShareTransferRecord? before,
  }) async {
    this.direction = direction;
    this.search = search;
    return rows;
  }

  @override
  Future<void> remove(ShareTransferRecord record) async {
    removed.add(record.id);
    rows.removeWhere((row) => row.id == record.id);
  }
}

class _FailHistory extends ShareTransferHistory {
  @override
  Future<List<ShareTransferRecord>> query({
    ShareTransferDirection? direction,
    String search = '',
    ShareTransferRecord? before,
  }) async => throw StateError('storage unavailable');
}

void main() {
  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    String language = 'zh',
  }) => MaterialApp(
    theme: buildAppTheme(brightness),
    locale: Locale(language),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(body: child),
  );
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('记录筛选/搜索与窄窗口 ${brightness.name} $language', (tester) async {
        tester.view.physicalSize = const Size(480, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final history = _History();
        await tester.pumpWidget(
          host(
            HarmonyShareHistoryDialog(
              history: history,
              onOpen: (_) async {},
              onFolder: (_) async {},
              onRetry: (_) async {},
            ),
            brightness: brightness,
            language: language,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('synthetic.bin'), findsOneWidget);
        await tester.tap(find.text(language == 'zh' ? '我接收的' : 'Received'));
        await tester.pumpAndSettle();
        expect(history.direction, ShareTransferDirection.receive);
        await tester.enterText(find.byType(TextField), 'nova');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(history.search, 'nova');
        history.dispose();
      });
    }
  }
  testWidgets('删除前明确确认，不触发文件打开或重试', (tester) async {
    final history = _History();
    var opened = false;
    var retried = false;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => HarmonyShareHistoryDialog(
                history: history,
                onOpen: (_) async {
                  opened = true;
                },
                onFolder: (_) async {},
                onRetry: (_) async {
                  retried = true;
                },
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('记录操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    expect(find.text('仅删除此任务及其文件记录，不会删除磁盘文件。'), findsOneWidget);
    expect(history.removed, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '删除记录'));
    await tester.pumpAndSettle();
    expect(history.removed, ['1']);
    expect(opened, isFalse);
    expect(retried, isFalse);
    expect(find.text('synthetic.bin'), findsNothing);
    history.dispose();
  });
  testWidgets('存储不可用不显示为没有记录', (tester) async {
    final history = _FailHistory();
    await tester.pumpWidget(
      host(
        HarmonyShareHistoryDialog(
          history: history,
          onOpen: (_) async {},
          onFolder: (_) async {},
          onRetry: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有传输记录'), findsNothing);
    expect(find.text('记录暂时无法读取或保存，请稍后重试。文件传输可继续。'), findsOneWidget);
    history.dispose();
  });
  testWidgets('重试由明确点击触发，保留原记录', (tester) async {
    final history = _History();
    ShareTransferRecord? retried;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => HarmonyShareHistoryDialog(
                history: history,
                onOpen: (_) async {},
                onFolder: (_) async {},
                onRetry: (record) async {
                  retried = record;
                },
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(retried, isNull);
    await tester.tap(find.byTooltip('记录操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试发送'));
    await tester.pumpAndSettle();
    expect(retried!.id, '1');
    expect(history.rows.length, 1);
    expect(history.removed, isEmpty);
    history.dispose();
  });
}
