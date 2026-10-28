import 'dart:io';
import 'dart:async';

import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_history_database.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:flutter_test/flutter_test.dart';

ShareTransferRecord _record(
  String id, {
  ShareTransferDirection direction = ShareTransferDirection.send,
  ShareTransferStatus status = ShareTransferStatus.succeeded,
  String name = 'synthetic.bin',
  String? path,
}) => ShareTransferRecord(
  id: id,
  direction: direction,
  status: status,
  deviceName: 'nova',
  address: '192.168.1.3',
  port: 44800,
  fileName: name,
  path: path,
  bytes: 100,
  transferredBytes: 25,
  createdAt: DateTime(2026, 10, 28),
);

void main() {
  late Directory root;
  late ShareHistoryDatabase database;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('anydeck-history-test-');
    database = ShareHistoryDatabase('${root.path}/history.sqlite');
  });
  tearDown(() async => root.delete(recursive: true));

  test('持久化完整元数据，方向与字面搜索正确，SQL内容不会被执行', () async {
    await database.save([
      _record('1', name: '用户%_文件.bin'),
      _record(
        '2',
        direction: ShareTransferDirection.receive,
        name: "x'; DROP TABLE transfers; --.bin",
      ),
    ]);
    final reopened = ShareHistoryDatabase(database.path);
    final records = await reopened.query();
    expect(records.length, 2);
    expect(records.first.toMap()['address'], '192.168.1.3');
    expect((await reopened.query(search: '%_')).single.fileName, '用户%_文件.bin');
    expect(
      (await reopened.query(
        direction: ShareTransferDirection.receive,
      )).single.id,
      '2',
    );
    expect((await reopened.query(search: 'DROP TABLE')).length, 1);
  });

  test('游标分页在同时间与新插入记录时不重复或漏旧记录', () async {
    await database.save([
      for (var i = 0; i < 112; i++) _record(i.toString().padLeft(3, '0')),
    ]);
    final first = await database.query();
    expect(first.length, 100);
    await database.save([_record('999')]);
    final next = await database.query(before: first.last);
    expect(next.length, 12);
    expect(
      {
        ...first.map((record) => record.id),
        ...next.map((record) => record.id),
      }.length,
      112,
    );
  });

  test('重启把悬挂任务标为中断，保留字节，已完成状态不变', () async {
    await database.save([
      _record('active', status: ShareTransferStatus.transferring),
      _record('done'),
    ]);
    await database.recoverInterrupted();
    final records = {
      for (final record in await database.query()) record.id: record,
    };
    expect(records['active']!.status, ShareTransferStatus.interrupted);
    expect(records['active']!.completedAt, isNotNull);
    expect(records['active']!.transferredBytes, 25);
    expect(records['done']!.status, ShareTransferStatus.succeeded);
  });

  test('删除只移除终态记录，不删除文件或进行中记录', () async {
    final file = await File(
      '${root.path}/synthetic.bin',
    ).writeAsBytes([1, 2, 3]);
    await database.save([
      _record('done', path: file.path),
      _record('active', status: ShareTransferStatus.queued),
    ]);
    await database.remove('active');
    await database.remove('done');
    expect((await database.query()).single.id, 'active');
    expect(await file.exists(), isTrue);
    expect(await file.length(), 3);
  });

  test('队列结果串行落盘，失败/取消保持独立，重开可回读', () async {
    final history = ShareTransferHistory(open: () async => database);
    final peer = ShareCorePeer(
      address: InternetAddress('192.168.1.3'),
      port: 44800,
      name: 'nova',
    );
    final items = [
      for (var i = 0; i < 3; i++)
        ShareSendItem(
          id: '$i',
          peer: peer,
          file: ShareSendFile(
            file: File('/synthetic/$i'),
            bytes: 100,
            modified: DateTime(2026),
          ),
        ),
    ];
    await history.queued(items);
    history.sentItemChanged(
      items[0].update(status: ShareSendStatus.failed, error: 'send_failed'),
    );
    history.sentItemChanged(
      items[1].update(status: ShareSendStatus.succeeded, bytes: 100),
    );
    history.sentItemChanged(items[2].update(status: ShareSendStatus.cancelled));
    await history.flush();
    final records = await history.query();
    expect(
      records.map((record) => record.status),
      containsAll([
        ShareTransferStatus.failed,
        ShareTransferStatus.succeeded,
        ShareTransferStatus.cancelled,
      ]),
    );
    expect(records.every((record) => record.completedAt != null), isTrue);
    expect(records.first.createdAt, isNotNull);
    history.dispose();
  });

  test('来件拒绝不被后续核心错误覆盖，接收成功保留路径与本机hash', () async {
    final history = ShareTransferHistory(open: () async => database);
    await history.initialize();
    final rejected = history.incoming(
      address: '192.168.1.3',
      name: 'nova',
      bytes: 100,
    );
    history.receiveChanged(rejected, status: ShareTransferStatus.rejected);
    history.receiveChanged(
      rejected,
      status: ShareTransferStatus.failed,
      error: 'user_rejected',
    );
    final received = history.incoming(
      address: '192.168.1.3',
      name: 'nova',
      bytes: 100,
    );
    history.receiveChanged(
      received,
      status: ShareTransferStatus.transferring,
      transferredBytes: 25,
    );
    history.receiveChanged(
      received,
      status: ShareTransferStatus.succeeded,
      transferredBytes: 100,
      fileName: 'received.bin',
      path: '/synthetic/received.bin',
      sha256: 'a' * 64,
    );
    final records = {
      for (final record in await history.query()) record.id: record,
    };
    expect(records[rejected]!.status, ShareTransferStatus.rejected);
    expect(records[received]!.path, '/synthetic/received.bin');
    expect(records[received]!.sha256, 'a' * 64);
    expect(records[received]!.transferredBytes, 100);
    history.dispose();
  });
  test('初始落盘期间整队取消也保存终态，重试保留原记录关联', () async {
    final history = ShareTransferHistory(open: () => Future.value(database));
    final gate = Completer<void>();
    var calls = 0;
    final queue = HarmonyShareSendQueue(
      send: (_, _) async {
        calls++;
      },
      cancelActive: () {},
      onQueued: (items) async {
        await gate.future;
        await history.queued(items);
      },
      onChanged: history.sentItemChanged,
    );
    final peer = ShareCorePeer(
      address: InternetAddress('192.168.1.3'),
      port: 44800,
      name: 'nova',
    );
    final selection = ShareSendSelection([
      ShareSendFile(
        file: File('/synthetic/a'),
        bytes: 10,
        modified: DateTime(2026),
      ),
    ]);
    final running = queue.run(peer, selection, retryOf: 'original-task');
    queue.cancelAll();
    gate.complete();
    await running;
    await history.flush();
    final record = (await history.query()).single;
    expect(record.status, ShareTransferStatus.cancelled);
    expect(record.retryOf, 'original-task');
    expect(calls, 0);
    queue.dispose();
    history.dispose();
  });
  test('接收取消后到达的核心成功保留真实落盘结果，拒绝不会被覆盖', () async {
    final history = ShareTransferHistory(open: () => Future.value(database));
    await history.initialize();
    final id = history.incoming(
      address: '192.168.1.3',
      name: 'nova',
      bytes: 10,
    );
    history.receiveChanged(id, status: ShareTransferStatus.cancelled);
    history.receiveChanged(
      id,
      status: ShareTransferStatus.succeeded,
      fileName: 'late.bin',
      path: '/synthetic/late.bin',
      transferredBytes: 10,
    );
    final rejected = history.incoming(
      address: '192.168.1.3',
      name: 'nova',
      bytes: 10,
    );
    history.receiveChanged(rejected, status: ShareTransferStatus.rejected);
    history.receiveChanged(rejected, status: ShareTransferStatus.succeeded);
    final rows = {for (final row in await history.query()) row.id: row};
    expect(rows[id]!.status, ShareTransferStatus.succeeded);
    expect(rows[id]!.path, '/synthetic/late.bin');
    expect(rows[rejected]!.status, ShareTransferStatus.rejected);
    history.dispose();
  });
}
