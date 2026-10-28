part of 'harmony_share_service.dart';

/// 发送调度与文件会话；接收生命周期仍由主窗口服务统一持有。
extension _HarmonyShareSendService on HarmonyShareService {
  void _batchChanged(ShareSendBatch batch) {
    history?.sentBatchChanged(batch);
    outbox.update(batch);
  }

  /// 追加先保存 queued；开始每批前仍重新检查全部文件。
  Future<void> _appendSelection(
    ShareCorePeer peer,
    ShareSendSelection selection, {
    String? retryOf,
  }) async {
    if (!canAppend) throw StateError('outbox_cancelling');
    await outbox.enqueue(sendQueue.prepare(peer, selection, retryOf: retryOf));
  }

  Future<void> _runBatch(
    ShareCorePeer peer,
    Future<ShareSendSelection> Function() prepare, {
    String? retryOf,
  }) async {
    if (busy) {
      if (canAppend) {
        await _appendSelection(peer, await prepare(), retryOf: retryOf);
      }
      return;
    }
    final operation = _executeBatch(peer, prepare, retryOf: retryOf);
    _sending = operation;
    try {
      await operation;
    } finally {
      if (_sending == operation) _sending = null;
    }
  }

  /// 停止服务会等待本次发送清理和记录落盘，避免销毁后仍输出状态。
  Future<void> _executeBatch(
    ShareCorePeer peer,
    Future<ShareSendSelection> Function() prepare, {
    String? retryOf,
  }) async {
    busy = true;
    _sendCancelled = false;
    error = null;
    sendQueue.clear();
    _changed();
    try {
      await _stopWindow();
      busy = true;
      if (_sendCancelled) throw StateError('Transfer cancelled');
      final selection = await prepare();
      if (_sendCancelled) throw StateError('Transfer cancelled');
      if (_nativeBatch) {
        await outbox.enqueue(
          sendQueue.prepare(peer, selection, retryOf: retryOf),
        );
        await outbox.idle;
      } else {
        await sendQueue.run(peer, selection, retryOf: retryOf);
      }
      await history?.flush();
      final failures = sendQueue.items.where(
        (item) => item.status == ShareSendStatus.failed,
      );
      error = _nativeBatch
          ? outbox.failure
          : (failures.isEmpty ? null : failures.first.error);
    } catch (failure) {
      error = '$failure';
      if (_nativeBatch) await outbox.idle;
    } finally {
      activeFile = null;
      progress = null;
      busy = false;
      _changed();
      if (_enabled) await _startWindow();
    }
  }

  /// 每项只占用一个核心会话；整个 batch 结束后才恢复接收监听。
  Future<void> _sendOne(
    ShareSendItem item,
    ValueChanged<ShareCoreProgress> onProgress,
  ) async {
    activeFile = item.file.name;
    progress = null;
    await _sender.send(
      item,
      cancelled: () => _sendCancelled || sendQueue.isCancelled(item.id),
      onProgress: (update) {
        progress = update;
        onProgress(update);
      },
    );
    recent.insert(0, item.file.file.path);
    if (recent.length > 50) recent.removeRange(50, recent.length);
    unawaited(_saveRecent());
  }

  /// 一次选择对应一次原生确认与发送，终态前不生成单文件成功结果。
  Future<void> _sendNativeBatch(
    List<ShareSendItem> items,
    ValueChanged<ShareCoreProgress> onProgress,
  ) async {
    activeFile = null;
    progress = null;
    await _sender.sendBatch(
      items,
      cancelled: () => _sendCancelled || sendQueue.cancelling,
      onProgress: (update) {
        progress = update;
        onProgress(update);
      },
    );
    recent.insertAll(0, items.map((item) => item.file.file.path));
    if (recent.length > 50) recent.removeRange(50, recent.length);
    unawaited(_saveRecent());
  }
}
