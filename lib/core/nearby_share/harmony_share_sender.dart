import 'dart:async';

import 'harmony_share_send_queue.dart';
import 'share_core_client.dart';
import 'share_network.dart';
import 'share_local_name.dart';

/// 原生发送会话资源；批次与兼容单文件共用取消边界，退出时解除进度订阅。
class HarmonyShareSender {
  HarmonyShareSender({required this.client, required this.detectNetwork});
  final ShareCoreClient client;
  final Future<ShareNetwork> Function() detectNetwork;
  ShareCoreTransfer? _transfer;
  ShareBatchTransfer? _batchTransfer;

  void cancel() {
    _transfer?.cancel();
    _batchTransfer?.cancel();
  }

  /// 整批校验元数据后才启动 Core；Core 再负责 snapshot 与声明大小复核。
  Future<void> sendBatch(
    List<ShareSendItem> items, {
    String localName = ShareLocalName.defaultName,
    required bool Function() cancelled,
    required void Function(ShareCoreProgress) onProgress,
  }) async {
    void checkCancelled() {
      if (cancelled()) throw StateError('Transfer cancelled');
    }

    StreamSubscription<ShareCoreProgress>? events;
    try {
      checkCancelled();
      final request = ShareBatchRequest([
        for (final item in items)
          ShareBatchFile(item.file.file.path, item.file.bytes),
      ], localName: localName);
      for (final item in items) {
        await item.file.verifyUnchanged();
        checkCancelled();
      }
      final network = await detectNetwork();
      checkCancelled();
      final transfer = await client.sendBatchForTest(
        localAddress: network.local,
        peer: items.first.peer,
        request: request,
      );
      _batchTransfer = transfer;
      if (cancelled()) transfer.cancel();
      events = transfer.progress.listen(onProgress);
      await transfer.result;
    } finally {
      await events?.cancel();
      _batchTransfer = null;
    }
  }

  Future<void> send(
    ShareSendItem item, {
    required bool Function() cancelled,
    required void Function(ShareCoreProgress) onProgress,
  }) async {
    void checkCancelled() {
      if (cancelled()) throw StateError('Transfer cancelled');
    }

    StreamSubscription<ShareCoreProgress>? events;
    var previousBytes = 0;
    try {
      checkCancelled();
      await item.file.verifyUnchanged();
      checkCancelled();
      final network = await detectNetwork();
      checkCancelled();
      final transfer = await client.sendFileForTest(
        localAddress: network.local,
        peer: item.peer,
        file: item.file.file,
      );
      _transfer = transfer;
      if (cancelled()) transfer.cancel();
      events = transfer.progress.listen((update) {
        if (update.direction == 'send' &&
            update.totalBytes == item.file.bytes &&
            update.bytes >= previousBytes &&
            update.bytes <= update.totalBytes) {
          previousBytes = update.bytes;
          onProgress(update);
        }
      });
      await transfer.result;
    } finally {
      await events?.cancel();
      _transfer = null;
    }
  }
}
