import 'dart:async';
import 'dart:io';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_history_database.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

class _Receiver extends Fake implements ShareCoreReceiveSession {
  final stream = StreamController<Map<String, dynamic>>();
  final decisions = <bool>[];
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  void decide(bool accept) => decisions.add(accept);
  @override
  Future<void> stop() async {}
}

class _Client extends Fake implements ShareCoreClient {
  final receiver = _Receiver();
  @override
  Future<ShareCoreReceiveSession> startBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
  }) async => receiver;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('history-recovery-');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => root.delete(recursive: true));

  test('真实 SQLite 子文件写入中断整批回滚，恢复补齐全部记录且不重放成功通知', () async {
    final database = ShareHistoryDatabase('${root.path}/history.sqlite');
    final history = ShareTransferHistory(open: () async => database);
    final completed = <String>[];
    final events = history.changes.listen((record) {
      if (record.status == ShareTransferStatus.succeeded) {
        completed.add(record.id);
      }
    });
    try {
      await history.initialize();
      final id = history.incoming(
        address: '127.0.0.1',
        name: 'fixture',
        bytes: 7,
        fileCount: 2,
      );
      await history.flush();
      final raw = sqlite3.open(database.path);
      raw.execute(
        "CREATE TRIGGER synthetic_failure BEFORE INSERT ON transfers WHEN NEW.batch_id IS NOT NULL BEGIN SELECT RAISE(ABORT,'synthetic storage failure'); END",
      );
      raw.dispose();
      history.receivedBatch(id, [
        for (var i = 0; i < 2; i++)
          {
            'path': '${root.path}/file-$i.bin',
            'bytes': i + 3,
            'sha256': 'a' * 64,
          },
      ], root.path);
      await history.flush();
      expect(history.error, isNotNull);
      expect(
        (await database.query()).single.status,
        ShareTransferStatus.awaitingAcceptance,
      );
      expect(await database.batchFiles(id), isEmpty);
      await expectLater(history.batchFiles(id), throwsStateError);
      final unrelated = history.incoming(
        address: '127.0.0.1',
        name: 'new',
        bytes: 1,
      );
      history.receiveChanged(unrelated, status: ShareTransferStatus.rejected);
      await history.flush();
      expect(history.error, isNotNull);
      expect((await database.query()).length, 1);
      final restored = sqlite3.open(database.path);
      restored.execute('DROP TRIGGER synthetic_failure');
      restored.dispose();
      expect(await history.retryPending(), isTrue);
      expect(history.error, isNull);
      final children = await history.batchFiles(id);
      expect(children.map((record) => record.bytes), [3, 4]);
      expect(children.every((record) => record.sha256 == 'a' * 64), isTrue);
      expect(
        (await database.query()).map((record) => record.status),
        containsAll([
          ShareTransferStatus.succeeded,
          ShareTransferStatus.rejected,
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completed, [id]);
      await history.remove(
        history.recent.firstWhere((record) => record.id == id),
      );
      await history.flush();
      expect(await database.batchFiles(id), isEmpty);
      expect((await database.query()).single.id, unrelated);
    } finally {
      await events.cancel();
      history.dispose();
    }
  });

  test('目录无法打开后可恢复，完整结果保留在内存并补写，不伪装空库', () async {
    final blocked = await File(
      '${root.path}/blocked',
    ).writeAsString('synthetic');
    final database = ShareHistoryDatabase('${blocked.path}/history.sqlite');
    final history = ShareTransferHistory(open: () async => database);
    try {
      await history.initialize();
      final id = history.incoming(
        address: '127.0.0.1',
        name: 'fixture',
        bytes: 1,
      );
      history.receiveChanged(
        id,
        status: ShareTransferStatus.succeeded,
        path: '${root.path}/synthetic.bin',
        fileName: 'synthetic.bin',
        transferredBytes: 1,
        sha256: 'b' * 64,
      );
      await history.flush();
      expect(history.error, isNotNull);
      await expectLater(history.query(), throwsStateError);
      await blocked.delete();
      expect(await history.retryPending(), isTrue);
      final stored = (await history.query()).single;
      expect(stored.status, ShareTransferStatus.succeeded);
      expect(stored.sha256, 'b' * 64);
      expect(stored.path, '${root.path}/synthetic.bin');
    } finally {
      history.dispose();
    }
  });

  test('缓冲容量不足在发送前失败，队列不遗留假排队状态', () async {
    final history = ShareTransferHistory(
      maxPendingRecords: 1,
      open: () async => ShareHistoryDatabase('${root.path}/history.sqlite'),
    );
    var sends = 0;
    final queue = HarmonyShareSendQueue(
      send: (_, _) async {},
      sendBatch: (_, _) async {
        sends++;
      },
      cancelActive: () {},
      onBatchQueued: history.queuedBatch,
      onBatchChanged: history.sentBatchChanged,
    );
    try {
      await queue.run(
        ShareCorePeer(
          address: InternetAddress.loopbackIPv4,
          port: 1234,
          name: 'fixture',
        ),
        ShareSendSelection([
          for (var i = 0; i < 2; i++)
            ShareSendFile(
              file: File('/synthetic/$i'),
              bytes: 1,
              modified: DateTime(2026),
            ),
        ]),
      );
      expect(sends, 0);
      expect(queue.count(ShareSendStatus.failed), 2);
      expect(queue.items.first.error, 'history_buffer_full');
      expect(history.recent, isEmpty);
    } finally {
      queue.dispose();
      history.dispose();
    }
  });

  test('缓冲容量不足时服务拒绝整批来件，不显示可接受的 offer', () async {
    final history = ShareTransferHistory(
      maxPendingRecords: 1,
      open: () async => ShareHistoryDatabase('${root.path}/history.sqlite'),
    );
    final client = _Client();
    final service = HarmonyShareService.testing(
      client: client,
      history: history,
      nativeBatch: true,
      downloads: () async => root,
      detectNetwork: () async => ShareNetwork(
        InternetAddress.loopbackIPv4,
        InternetAddress('127.255.255.255'),
      ),
    );
    try {
      await service.start();
      client.receiver.stream.add({'event': 'session_started'});
      client.receiver.stream.add({
        'event': 'incoming_batch',
        'ip': '127.0.0.1',
        'file_count': 2,
        'total_bytes': 2,
      });
      await Future<void>.delayed(Duration.zero);
      expect(client.receiver.decisions, [false]);
      expect(service.pendingOffer, isNull);
      expect(service.error, 'history_buffer_full');
      expect(history.recent, isEmpty);
    } finally {
      await service.stop();
      service.dispose();
      history.dispose();
      await client.receiver.stream.close();
    }
  });
}
