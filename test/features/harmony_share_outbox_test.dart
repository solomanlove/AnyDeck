import 'dart:io';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_rate.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_outbox_panel.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_queue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('追加与速率 480px $brightness $language，取消范围和最终等待', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final l10n = AppLocalizations(Locale(language));
        final peer = ShareCorePeer(
          address: InternetAddress.loopbackIPv4,
          port: 1234,
          name: 'fixture',
        );
        final item = ShareSendItem(
          id: 'item',
          peer: peer,
          file: ShareSendFile(
            file: File('/synthetic/file'),
            bytes: 1000,
            modified: DateTime(2026),
          ),
          status: ShareSendStatus.transferring,
        );
        var pendingCancelled = '';
        var allCancelled = 0;
        var activeCancelled = 0;
        Widget host(int bytes, ShareRateEstimate? rate) => MaterialApp(
          theme: buildAppTheme(brightness),
          locale: Locale(language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  HarmonyShareOutboxPanel(
                    batches: [
                      ShareSendBatch(
                        id: 'queued',
                        items: [item],
                        transferredBytes: 0,
                      ),
                    ],
                    onCancel: (id) => pendingCancelled = id,
                    onCancelAll: () => allCancelled++,
                    onClear: () {},
                    running: true,
                    failed: 2,
                  ),
                  HarmonyShareQueuePanel(
                    items: [item],
                    running: true,
                    nativeBatch: true,
                    batchTransferredBytes: bytes,
                    rate: rate,
                    onCancel: (_) {},
                    onCancelAll: () => activeCancelled++,
                    onClear: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          host(500, const ShareRateEstimate(100, Duration(seconds: 5))),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining(language == 'zh' ? '预计剩余 5 秒' : '~5s remaining'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip(l10n.t('harmonyShareCancelBatch')));
        expect(pendingCancelled, 'queued');
        await tester.tap(find.text(l10n.t('harmonyShareCancelOutbox')));
        expect(allCancelled, 1);
        expect(activeCancelled, 0);
        await tester.tap(
          find.widgetWithText(TextButton, l10n.t('harmonyShareCancelBatch')),
        );
        expect(activeCancelled, 1);
        await tester.pumpWidget(host(1000, null));
        expect(
          find.text(l10n.t('harmonyShareAwaitingBatchResult')),
          findsOneWidget,
        );
        expect(
          find.textContaining(language == 'zh' ? '预计剩余' : 'Current batch:'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
