import 'dart:async';

import 'harmony_share_send_queue.dart';
import 'share_core_client.dart';
import 'share_network.dart';

/// 单文件原生会话资源；队列/服务只负责调度，退出任何路径都会解除进度订阅。
class HarmonyShareSender {
  HarmonyShareSender({required this.client, required this.detectNetwork});
  final ShareCoreClient client;
  final Future<ShareNetwork> Function() detectNetwork;
  ShareCoreTransfer? _transfer;

  void cancel() => _transfer?.cancel();

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
