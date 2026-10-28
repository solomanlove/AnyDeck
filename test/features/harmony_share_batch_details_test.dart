import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_history_recent.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_batch_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _History extends ShareTransferHistory {
  int queries = 0;
  @override
  Future<List<ShareTransferRecord>> batchFiles(String id) async {
    queries++;
    return [];
  }
}

void main() {
  final summary = ShareTransferRecord(
    id: 'batch',
    direction: ShareTransferDirection.receive,
    status: ShareTransferStatus.succeeded,
    deviceName: 'nova',
    address: '192.168.1.3',
    fileName: '',
    bytes: 7,
    fileCount: 2,
    createdAt: DateTime(2026),
  );
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('批次详情有界清单与显式打开 ${brightness.name} $language', (tester) async {
        tester.view.physicalSize = const Size(480, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var opened = 0;
        final files = [
          for (var i = 0; i < 2; i++)
            ShareTransferRecord(
              id: 'batch-$i',
              batchId: 'batch',
              direction: ShareTransferDirection.receive,
              status: ShareTransferStatus.succeeded,
              deviceName: 'nova',
              address: '192.168.1.3',
              fileName: 'synthetic-$i.bin',
              path: '/synthetic/$i',
              bytes: i + 3,
              createdAt: DateTime(2026),
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            locale: Locale(language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: HarmonyShareBatchDetails(
                record: summary,
                files: Future.value(files),
                onOpen: (_) async {
                  opened++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('synthetic-0.bin'), findsOneWidget);
        expect(opened, 0);
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            AppLocalizations(Locale(language)).t('harmonyShareOpenFile'),
          ),
        );
        await tester.pumpAndSettle();
        expect(opened, 1);
      });
    }
  }
  testWidgets('批次详情随主题更新但不重复查询清单', (tester) async {
    final history = _History();
    final mode = ValueNotifier(ThemeMode.light);
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (_, value, _) => MaterialApp(
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: value,
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: HarmonyShareHistoryRecent(
              records: [summary],
              history: history,
              onHistory: () {},
              onOpen: (_) async {},
              onFolder: (_) async {},
              onRetry: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('批次 · 2 个文件'));
    await tester.pumpAndSettle();
    expect(history.queries, 1);
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(history.queries, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    mode.dispose();
    history.dispose();
  });
}
