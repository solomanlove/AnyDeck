import 'dart:io';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_batch_details.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_queue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, Brightness brightness, String language) =>
    MaterialApp(
      theme: buildAppTheme(brightness),
      locale: Locale(language),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: child),
    );

void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('原生发送 480px $brightness $language 整批进度与取消、子文件显式重试', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final l10n = AppLocalizations(Locale(language));
        var cancels = 0;
        final peer = ShareCorePeer(
          address: InternetAddress('192.168.1.3'),
          port: 44800,
          name: 'fixture',
        );
        Widget panel(bool cancelling) => HarmonyShareQueuePanel(
          items: [
            for (var i = 0; i < 100; i++)
              ShareSendItem(
                id: '$i',
                peer: peer,
                file: ShareSendFile(
                  file: File('/synthetic/$i.bin'),
                  bytes: 100,
                  modified: DateTime(2026),
                ),
                status: ShareSendStatus.transferring,
              ),
          ],
          running: true,
          nativeBatch: true,
          batchTransferredBytes: 4000,
          cancelling: cancelling,
          onCancel: (_) =>
              fail('No per-file cancellation in active native batch'),
          onCancelAll: () => cancels++,
          onClear: () {},
        );
        await tester.pumpWidget(host(panel(false), brightness, language));
        expect(tester.takeException(), isNull);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          .4,
        );
        expect(find.byTooltip(l10n.t('harmonyShareCancelItem')), findsNothing);
        await tester.tap(find.text(l10n.t('harmonyShareCancelBatch')));
        expect(cancels, 1);
        await tester.pumpWidget(host(panel(true), brightness, language));
        final cancelling = find.widgetWithText(
          TextButton,
          l10n.t('harmonyShareCancellingBatch'),
        );
        expect(tester.widget<TextButton>(cancelling).onPressed, isNull);
        final failed = ShareTransferRecord(
          id: 'file',
          batchId: 'batch',
          direction: ShareTransferDirection.send,
          status: ShareTransferStatus.failed,
          deviceName: 'fixture',
          address: '192.168.1.3',
          fileName: 'synthetic.bin',
          path: '/synthetic/file.bin',
          bytes: 100,
          createdAt: DateTime(2026),
        );
        var retries = 0;
        await tester.pumpWidget(
          host(
            HarmonyShareBatchDetails(
              record: failed,
              files: Future.value([failed]),
              onRetry: (_) async => retries++,
            ),
            brightness,
            language,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.t('harmonyShareRemoteHashUnknown')),
          findsOneWidget,
        );
        expect(retries, 0);
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.t('harmonyShareRetry')));
        await tester.pumpAndSettle();
        expect(retries, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
