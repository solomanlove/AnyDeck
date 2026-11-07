import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/features/harmony_share/model/harmony_share_peer_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nova = ShareCorePeer(
    address: InternetAddress('192.168.1.2'),
    port: 1,
    name: 'nova',
  );
  final mate = ShareCorePeer(
    address: InternetAddress('192.168.1.3'),
    port: 2,
    name: 'Mate',
  );
  ShareSendItem item(
    ShareSendStatus status, {
    ShareCorePeer? peer,
    int bytes = 0,
  }) => ShareSendItem(
    id: 'file',
    peer: peer ?? nova,
    file: ShareSendFile(
      file: File('/synthetic/file'),
      bytes: 100,
      modified: DateTime(2026),
    ),
    status: status,
    transferredBytes: bytes,
  );
  ShareSendBatch batch(
    String id,
    ShareSendStatus status, {
    int bytes = 0,
    ShareCorePeer? peer,
    int count = 2,
  }) => ShareSendBatch(
    id: id,
    transferredBytes: bytes,
    items: [for (var i = 0; i < count; i++) item(status, peer: peer)],
  );
  List<HarmonySharePeerState> resolve(
    List<ShareSendBatch> batches, {
    String? active,
    bool cancelling = false,
    List<ShareCorePeer>? peers,
  }) => HarmonySharePeerState.resolve(
    peers: peers ?? [nova],
    batches: batches,
    activeBatchId: active,
    cancelling: cancelling,
  );

  test('发现空状态与无批次设备不继承历史发送状态', () {
    expect(HarmonySharePeerState.resolve(peers: []), isEmpty);
    expect(resolve([]).single.phase, HarmonySharePeerPhase.ready);
  });

  test('同一设备按活动批次展示，后续批次仅计入排队数量', () {
    final states = resolve([
      batch('active', ShareSendStatus.transferring, bytes: 100),
      batch('next', ShareSendStatus.queued, count: 3),
      batch('other-peer', ShareSendStatus.queued, peer: mate),
    ], active: 'active');
    final state = states.first;
    expect(state.batchId, 'active');
    expect(state.phase, HarmonySharePeerPhase.sending);
    expect(state.progress, .5);
    expect(state.fileCount, 2);
    expect(state.queuedBatches, 1);
    expect(states.last.phase, HarmonySharePeerPhase.queued);
  });

  test('前批成功后后批未接收，不沿用已发送或100%进度', () {
    final state = resolve([
      batch('done', ShareSendStatus.succeeded, bytes: 200),
      batch('next', ShareSendStatus.preparing, count: 3),
    ], active: 'next').single;
    expect(state.phase, HarmonySharePeerPhase.waiting);
    expect(state.progress, 0);
    expect(state.fileCount, 3);
    expect(state.batchId, 'next');
  });

  for (final entry in {
    ShareSendStatus.queued: HarmonySharePeerPhase.queued,
    ShareSendStatus.preparing: HarmonySharePeerPhase.waiting,
    ShareSendStatus.succeeded: HarmonySharePeerPhase.sent,
    ShareSendStatus.failed: HarmonySharePeerPhase.failed,
    ShareSendStatus.cancelled: HarmonySharePeerPhase.cancelled,
  }.entries) {
    test('真实终态/准备状态映射 ${entry.key.name}', () {
      expect(resolve([batch('batch', entry.key)]).single.phase, entry.value);
    });
  }

  test('整批字节满但尚未终态时只显示确认中', () {
    final state = resolve([
      batch('active', ShareSendStatus.transferring, bytes: 200),
    ], active: 'active').single;
    expect(state.phase, HarmonySharePeerPhase.confirming);
    expect(state.progress, 1);
  });

  test('取消只影响当前批次设备，不能误报其他设备已取消', () {
    final states = resolve(
      [
        batch('active', ShareSendStatus.transferring, bytes: 50),
        batch('next-peer', ShareSendStatus.queued, peer: mate),
      ],
      active: 'active',
      cancelling: true,
    );
    expect(states.first.phase, HarmonySharePeerPhase.cancelling);
    expect(states.last.phase, HarmonySharePeerPhase.queued);
  });

  test('兼容串行队列：部分文件成功后仍不能显示整批已发送', () {
    final state = resolve([
      ShareSendBatch(
        id: 'serial',
        transferredBytes: 100,
        items: [
          item(ShareSendStatus.succeeded, bytes: 100),
          item(ShareSendStatus.preparing),
        ],
      ),
    ]).single;
    expect(state.phase, HarmonySharePeerPhase.waiting);
    expect(state.progress, .5);
  });

  test('同IP改名隔离状态，重新发现同名设备使用最新端口', () {
    final renamed = ShareCorePeer(
      address: nova.address,
      port: 3,
      name: 'another phone',
    );
    final rediscovered = ShareCorePeer(
      address: nova.address,
      port: 4,
      name: nova.name,
    );
    final old = batch('done', ShareSendStatus.succeeded);
    final states = resolve([old], peers: [renamed]);
    expect(states.first.phase, HarmonySharePeerPhase.ready);
    expect(states.last.available, isFalse);
    expect(resolve([old], peers: [rediscovered]).single.peer.port, 4);
  });

  test('实际原生队列在100%后等待Core结果，下一批启动即切换状态', () async {
    final result = Completer<void>();
    late void Function(ShareCoreProgress) progress;
    final queue = HarmonyShareSendQueue(
      send: (_, _) async {},
      cancelActive: () {},
      sendBatch: (_, onProgress) {
        progress = onProgress;
        return result.future;
      },
    );
    addTearDown(queue.dispose);
    final running = queue.runPrepared(batch('real', ShareSendStatus.queued));
    expect(
      resolve([queue.batch], active: 'real').single.phase,
      HarmonySharePeerPhase.waiting,
    );
    progress(
      const ShareCoreProgress(direction: 'send', bytes: 200, totalBytes: 200),
    );
    expect(
      resolve([queue.batch], active: 'real').single.phase,
      HarmonySharePeerPhase.confirming,
    );
    result.complete();
    await running;
    expect(resolve([queue.batch]).single.phase, HarmonySharePeerPhase.sent);
  });
}
