import 'dart:io';
import 'dart:ui' as ui;

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_history_dialog.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_record_tile.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_queue_panel.dart';
import 'package:any_deck/features/harmony_share/harmony_share_dashboard_tab.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_panels.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_stage.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_settings_panel.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_batch_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 视觉 fixture 不接触用户数据库。
class _VisualHistory extends ShareTransferHistory {
  @override
  Future<List<ShareTransferRecord>> query({
    ShareTransferDirection? direction,
    String search = '',
    ShareTransferRecord? before,
  }) async => [
    ShareTransferRecord(
      id: 'visual-received',
      direction: ShareTransferDirection.receive,
      status: ShareTransferStatus.succeeded,
      deviceName: 'nova 12 Ultra',
      address: '192.168.1.3',
      fileName: 'synthetic-received.bin',
      path: '/synthetic/received.bin',
      bytes: 10 * 1024 * 1024,
      transferredBytes: 10 * 1024 * 1024,
      createdAt: DateTime(2026, 10, 28, 10),
      completedAt: DateTime(2026, 10, 28, 10, 1),
      sha256: 'a' * 64,
    ),
    ShareTransferRecord(
      id: 'visual-failed',
      direction: ShareTransferDirection.send,
      status: ShareTransferStatus.failed,
      deviceName: 'nova 12 Ultra',
      address: '192.168.1.3',
      fileName: 'synthetic-failed.bin',
      path: '/synthetic/failed.bin',
      bytes: 100 * 1024 * 1024,
      transferredBytes: 20 * 1024 * 1024,
      createdAt: DateTime(2026, 10, 28, 9),
      completedAt: DateTime(2026, 10, 28, 9, 1),
      error: 'send_failed',
    ),
  ];
}

/// 可选导出 Widget 渲染图，无需启动或停止用户的 App。
/// 使用 --dart-define=HARMONY_CAPTURE_DIR=绝对路径；字体路径仅用于本机视觉验收。
void main() {
  const output = String.fromEnvironment('HARMONY_CAPTURE_DIR');
  const font = String.fromEnvironment('HARMONY_CAPTURE_FONT');
  for (final brightness in Brightness.values) {
    testWidgets('发现舞台与来件面板视觉布局 ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(1060, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (font.isNotEmpty) {
        await tester.runAsync(() async {
          final loader = FontLoader('CaptureFont');
          loader.addFont(
            File(font).readAsBytes().then((data) => ByteData.sublistView(data)),
          );
          await loader.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      final key = GlobalKey();
      Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(brightness).copyWith(
          textTheme: buildAppTheme(
            brightness,
          ).textTheme.apply(fontFamily: font.isEmpty ? null : 'CaptureFont'),
        ),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: RepaintBoundary(
          key: key,
          child: Scaffold(body: child),
        ),
      );
      Future<void> capture(String name) async {
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await Directory(output).create(recursive: true);
          await File(
            '$output/$name-${brightness.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      await tester.pumpWidget(host(const HarmonyShareDashboardTab()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('empty');
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: Column(
              children: [
                HarmonyShareIdentity(enabled: true, onChanged: (_) {}),
                HarmonyShareStage(
                  peers: [
                    ShareCorePeer(
                      address: InternetAddress('192.168.1.2'),
                      port: 1234,
                      name: 'nova 12 Ultra',
                    ),
                  ],
                  enabled: true,
                  busy: false,
                  onPick: (_) {},
                  onDrop: (_, _) {},
                  onInvalidDrop: () {},
                ),
                const HarmonyShareRecent(paths: []),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('nearby');
      await tester.pumpWidget(
        host(
          const Center(
            child: HarmonyShareConfirmDialog(
              receiving: true,
              device: 'nova 12 Ultra',
              summary: '256 B',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('incoming');
      final statuses = [
        ShareSendStatus.succeeded,
        ShareSendStatus.transferring,
        ShareSendStatus.failed,
        ShareSendStatus.cancelled,
        ShareSendStatus.queued,
      ];
      final peer = ShareCorePeer(
        address: InternetAddress('192.168.1.2'),
        port: 44800,
        name: 'nova 12 Ultra',
      );
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                HarmonyShareIdentity(enabled: true, onChanged: (_) {}),
                HarmonyShareQueuePanel(
                  items: [
                    for (var index = 0; index < statuses.length; index++)
                      ShareSendItem(
                        id: '$index',
                        peer: peer,
                        file: ShareSendFile(
                          file: File('/synthetic/file-$index.bin'),
                          bytes: 10 * 1024 * 1024,
                          modified: DateTime(2026),
                        ),
                        status: statuses[index],
                        transferredBytes: index == 0
                            ? 10 * 1024 * 1024
                            : index == 1
                            ? 3 * 1024 * 1024
                            : 0,
                        error: index == 2 ? 'send_failed' : null,
                      ),
                  ],
                  running: true,
                  onCancel: (_) {},
                  onCancelAll: () {},
                  onClear: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('queue');
      final history = _VisualHistory();
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
      expect(tester.takeException(), isNull);
      await capture('history');
      final details = (await history.query()).first;
      await tester.pumpWidget(
        host(Center(child: HarmonyShareRecordDetailsDialog(record: details))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('record-details');
      await tester.pumpWidget(host(Center(child: AlertDialog(
        title: const Text('互传设置'),
        content: HarmonyShareSettingsPanel(
          notifications: true, directory: '/synthetic/Downloads',
          permission: 'denied', saving: false, busy: false,
          onNotifications: (_) {}, onChooseDirectory: () {}, onResetDirectory: () {},
          onPermission: () {}, onRefreshPermission: () {},
        ),
      ))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('settings');
      final batch = ShareTransferRecord(id: 'visual-batch', direction: ShareTransferDirection.receive,
        status: ShareTransferStatus.succeeded, deviceName: 'nova 12 Ultra', address: '192.168.1.3',
        fileName: '', fileCount: 2, bytes: 110 * 1024 * 1024, createdAt: DateTime(2026,10,28));
      await tester.pumpWidget(host(Center(child: HarmonyShareBatchDetails(record: batch,
        files: Future.value([for (var i = 0; i < 2; i++) ShareTransferRecord(id: 'visual-$i', batchId: batch.id,
          direction: ShareTransferDirection.receive, status: ShareTransferStatus.succeeded,
          deviceName: batch.deviceName, address: batch.address, fileName: 'synthetic-$i.bin',
          path: '/synthetic/$i.bin', bytes: (i == 0 ? 10 : 100) * 1024 * 1024, createdAt: batch.createdAt)],),
        onOpen: (_) async {}, onFolder: (_) async {}))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('batch-details');
      history.dispose();
    });
  }
}
