import '../../../core/nearby_share/harmony_share_send_queue.dart';
import '../../../core/nearby_share/share_core_client.dart';

/// 头像状态只描述选中的一个批次，不能用单个文件或累计字节冒充整批成功。
enum HarmonySharePeerPhase {
  ready,
  queued,
  waiting,
  sending,
  confirming,
  sent,
  failed,
  cancelled,
  cancelling,
}

/// 设备头像的纯展示快照；available 表示本轮发现仍可选择该目标。
/// batchId/fileCount/progress 对应同一批次，queuedBatches 不含当前批次。
class HarmonySharePeerState {
  const HarmonySharePeerState({
    required this.peer,
    required this.available,
    this.phase = HarmonySharePeerPhase.ready,
    this.batchId,
    this.fileCount = 0,
    this.queuedBatches = 0,
    this.progress,
  });

  final ShareCorePeer peer;
  final bool available;
  final HarmonySharePeerPhase phase;
  final String? batchId;
  final int fileCount;
  final int queuedBatches;
  final double? progress;

  // 名称一起参与匹配，避免同 IP 被另一台手机占用时继承旧发送状态。
  static String identity(ShareCorePeer peer) =>
      '${peer.address.address}\n${peer.name}';

  /// 当前活动批次优先，其次待发，最后才是该设备最近一次批次结果。
  /// 重新发现的端口优先用于操作；保留离线任务头像，但禁止用旧端口发起新发送。
  static List<HarmonySharePeerState> resolve({
    required List<ShareCorePeer> peers,
    List<ShareSendBatch> batches = const [],
    String? activeBatchId,
    bool cancelling = false,
  }) {
    final discovered = {for (final peer in peers) identity(peer): peer};
    final grouped = <String, List<ShareSendBatch>>{};
    for (final batch in batches) {
      if (batch.items.isEmpty) continue;
      final key = identity(batch.items.first.peer);
      (grouped[key] ??= []).add(batch);
    }
    final devices = {...discovered};
    for (final entry in grouped.entries) {
      devices.putIfAbsent(entry.key, () => entry.value.last.items.first.peer);
    }
    return [
      for (final entry in devices.entries)
        _resolveDevice(
          entry.value,
          discovered.containsKey(entry.key),
          grouped[entry.key] ?? const [],
          activeBatchId,
          cancelling,
        ),
    ];
  }

  static HarmonySharePeerState _resolveDevice(
    ShareCorePeer peer,
    bool available,
    List<ShareSendBatch> batches,
    String? activeId,
    bool cancelling,
  ) {
    if (batches.isEmpty) {
      return HarmonySharePeerState(peer: peer, available: available);
    }
    final pending = batches
        .where((batch) => batch.items.any((item) => !item.terminal))
        .toList();
    final active = pending.where((batch) => batch.id == activeId);
    final batch = active.firstOrNull ?? pending.firstOrNull ?? batches.last;
    final items = batch.items;
    final terminal = items.every((item) => item.terminal);
    final live = items.where((item) => !item.terminal);
    final total = batch.bytes;
    final bytes = batch.transferredBytes.clamp(0, total);
    final phase = terminal
        ? items.any((item) => item.status == ShareSendStatus.failed)
              ? HarmonySharePeerPhase.failed
              : items.any((item) => item.status == ShareSendStatus.cancelled)
              ? HarmonySharePeerPhase.cancelled
              : HarmonySharePeerPhase.sent
        : cancelling && batch.id == activeId
        ? HarmonySharePeerPhase.cancelling
        : live.every((item) => item.status == ShareSendStatus.queued)
        ? HarmonySharePeerPhase.queued
        : live.any((item) => item.status == ShareSendStatus.preparing)
        ? HarmonySharePeerPhase.waiting
        : bytes == total &&
              items.any((item) => item.status == ShareSendStatus.transferring)
        ? HarmonySharePeerPhase.confirming
        : bytes > 0
        ? HarmonySharePeerPhase.sending
        : HarmonySharePeerPhase.waiting;
    return HarmonySharePeerState(
      peer: peer,
      available: available,
      phase: phase,
      batchId: batch.id,
      fileCount: items.length,
      queuedBatches: pending.where((other) => other.id != batch.id).length,
      progress: total > 0 ? bytes / total : null,
    );
  }
}
