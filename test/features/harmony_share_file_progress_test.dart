import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_queue_panel.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_receive_progress.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_record_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('实际文件字节/未知/等待整批/失败详情 480px ${brightness.name} $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget host(Widget child) => MaterialApp(
          theme: buildAppTheme(brightness),
          locale: Locale(language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );
        final peer = ShareCorePeer(
          address: InternetAddress('192.168.1.3'),
          port: 44800,
          name: 'fixture',
        );
        await tester.pumpWidget(
          host(
            Column(
              children: [
                HarmonyShareQueuePanel(
                  items: [
                    for (var i = 0; i < 3; i++)
                      ShareSendItem(
                        id: '$i',
                        peer: peer,
                        file: ShareSendFile(
                          file: File('/synthetic/$i'),
                          bytes: i == 0
                              ? 5
                              : i == 1
                              ? 4
                              : 3,
                          modified: DateTime(2026),
                        ),
                        status: ShareSendStatus.transferring,
                        transferredBytes: i == 0
                            ? 0
                            : i == 1
                            ? 2
                            : 3,
                        progressKnown: i != 0,
                      ),
                  ],
                  running: true,
                  nativeBatch: true,
                  batchTransferredBytes: 5,
                  onCancel: (_) {},
                  onCancelAll: () {},
                  onClear: () {},
                ),
                const HarmonyShareReceiveProgress(
                  files: [
                    ShareCoreFileProgress(
                      index: 0,
                      direction: 'receive',
                      bytes: 2,
                      totalBytes: 4,
                    ),
                    ShareCoreFileProgress(
                      index: 1,
                      direction: 'receive',
                      bytes: 3,
                      totalBytes: 3,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LinearProgressIndicator), findsNWidgets(5));
        expect(find.textContaining('0 B / 5 B'), findsNothing);
        final l10n = AppLocalizations(Locale(language));
        expect(
          find.text(l10n.t('harmonyShareFileBytesComplete')),
          findsNWidgets(2),
        );
        expect(
          find.text(l10n.t('harmonyShareFileIndex').replaceAll('{index}', '2')),
          findsOneWidget,
        );
        for (final known in [false, true]) {
          final record = ShareTransferRecord(
            id: 'partial',
            batchId: 'batch',
            fileIndex: 1,
            direction: ShareTransferDirection.receive,
            status: ShareTransferStatus.failed,
            deviceName: 'fixture',
            address: '192.168.1.3',
            fileName: '',
            bytes: 5,
            transferredBytes: known ? 2 : 0,
            progressKnown: known,
            createdAt: DateTime(2026),
          );
          await tester.pumpWidget(
            host(HarmonyShareRecordDetailsDialog(record: record)),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining(l10n.t('harmonyShareFileProgressUnknown')),
            known ? findsNothing : findsOneWidget,
          );
          expect(
            find.textContaining('2 B / 5 B'),
            known ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
        final partial = ShareTransferRecord(id: 'unpublished', batchId: 'batch',
          fileIndex: 1, direction: ShareTransferDirection.receive, status: ShareTransferStatus.failed,
          deviceName: 'fixture', address: '192.168.1.3', fileName: '', bytes: 5,
          transferredBytes: 2, progressKnown: true, createdAt: DateTime(2026));
        await tester.pumpWidget(host(HarmonyShareRecordTile(record: partial,
          onOpen: () => fail('Unpublished file cannot open'),
          onFolder: () => fail('Unpublished file has no folder action'))));
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        expect(find.text(l10n.t('harmonyShareOpenFile')), findsNothing);
        expect(find.text(l10n.t('harmonyShareOpenFolder')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
