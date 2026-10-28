import 'dart:async';
import 'package:flutter/foundation.dart';

import 'harmony_share_send_queue.dart';

/// 内部批次状态；对外只输出不可变快照，不在活动批次中途追加文件。
class _OutboxJob {
  _OutboxJob(this.batch);
  ShareSendBatch batch;
  bool ready = false;
  bool counted = false;
  bool get terminal => batch.items.first.terminal;
}

/// 主窗口持有的有界批次调度器；persist 在 Core 启动之前预留并保存任务。
/// execute 只能执行一个批次，cancelActive 只取消活动会话，changed 保存待发取消结果。
class HarmonyShareOutbox extends ChangeNotifier {
  HarmonyShareOutbox({
    required this.persist,
    required this.execute,
    required this.cancelActive,
    required this.changed,
  });
  static const maxBatches = 8;
  final Future<void> Function(ShareSendBatch) persist;
  final Future<ShareSendBatch> Function(ShareSendBatch) execute;
  final VoidCallback cancelActive;
  final ValueChanged<ShareSendBatch> changed;
  final _entries = <_OutboxJob>[];
  Completer<void>? _idle;
  int _preparing = 0;
  bool _working = false;
  bool _cancelledAll = false;
  bool _disposed = false;
  String? failure;
  String? cycleId;
  int succeeded = 0;
  int failed = 0;
  int cancelled = 0;
  String? activeId;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get running => _idle != null && !_idle!.isCompleted;
  bool get accepting => running && !_cancelledAll;
  Future<void> get idle => _idle?.future ?? Future.value();
  List<ShareSendBatch> get entries =>
      List.unmodifiable(_entries.map((entry) => entry.batch));
  List<ShareSendBatch> get waiting => List.unmodifiable(
    _entries
        .where((entry) => !entry.terminal && entry.batch.id != activeId)
        .map((entry) => entry.batch),
  );

  Future<void> enqueue(ShareSendBatch batch) async {
    if (_disposed) throw StateError('outbox_disposed');
    if (_entries.any((entry) => entry.batch.id == batch.id)) {
      throw ArgumentError('Duplicate outbox batch');
    }
    if (running && !accepting) throw StateError('outbox_cancelling');
    if (!running) {
      _entries.clear();
      _idle = Completer<void>();
      _cancelledAll = false;
      failure = null;
      cycleId = batch.id;
      succeeded = 0;
      failed = 0;
      cancelled = 0;
    }
    _entries.removeWhere(
      (entry) => entry.terminal && entry.ready && entry.batch.id != activeId,
    );
    if (_entries.length >= maxBatches) throw StateError('outbox_full');
    final entry = _OutboxJob(batch);
    _entries.add(entry);
    _preparing++;
    _notify();
    try {
      await persist(batch);
      entry.ready = true;
      // 保存首次 queued 期间的取消，在记录建立后重放一次终态。
      if (entry.terminal && !_disposed) changed(entry.batch);
      _count(entry);
    } catch (failure) {
      if (!entry.terminal) {
        entry.batch = _status(batch, ShareSendStatus.failed, '$failure');
      }
      entry.ready = true;
      this.failure ??= '$failure';
      _count(entry);
      rethrow;
    } finally {
      _preparing--;
      _notify();
      unawaited(_pump());
    }
  }

  void update(ShareSendBatch batch) {
    if (batch.id != activeId) return;
    _entries.firstWhere((entry) => entry.batch.id == batch.id).batch = batch;
    _notify();
  }

  Future<void> _pump() async {
    if (_working) return;
    if (_disposed) {
      _completeIfIdle();
      return;
    }
    _working = true;
    try {
      while (!_disposed) {
        final pending = _entries.where((entry) => !entry.terminal).toList();
        if (pending.isEmpty || !pending.first.ready) break;
        final entry = pending.first;
        activeId = entry.batch.id;
        _notify();
        try {
          entry.batch = await execute(entry.batch);
          if (entry.batch.status == ShareSendStatus.failed) {
            failure ??= entry.batch.items.first.error;
          }
        } catch (failure) {
          entry.batch = _status(
            entry.batch,
            ShareSendStatus.failed,
            '$failure',
          );
          this.failure ??= '$failure';
          if (!_disposed) changed(entry.batch);
        } finally {
          _count(entry);
          activeId = null;
          _notify();
        }
      }
    } finally {
      _working = false;
      _completeIfIdle();
    }
  }

  void _completeIfIdle() {
    if (!_working &&
        _preparing == 0 &&
        _entries.every((entry) => entry.terminal)) {
      if (_idle != null && !_idle!.isCompleted) _idle!.complete();
      _notify();
    }
  }

  void _count(_OutboxJob entry) {
    if (!entry.ready || !entry.terminal || entry.counted) return;
    entry.counted = true;
    switch (entry.batch.status) {
      case ShareSendStatus.succeeded:
        succeeded += entry.batch.items.length;
      case ShareSendStatus.failed:
        failed += entry.batch.items.length;
      case ShareSendStatus.cancelled:
        cancelled += entry.batch.items.length;
      default:
        break;
    }
  }

  void clear() {
    if (running) return;
    _entries.clear();
    succeeded = 0;
    failed = 0;
    cancelled = 0;
    _notify();
  }

  @override
  void dispose() {
    cancelAll();
    _disposed = true;
    super.dispose();
  }

  void cancel(String id) {
    final found = _entries.where((entry) => entry.batch.id == id);
    if (found.isEmpty || found.first.terminal) return;
    final entry = found.first;
    if (activeId == id) {
      cancelActive();
    } else {
      entry.batch = _status(entry.batch, ShareSendStatus.cancelled);
      if (entry.ready) changed(entry.batch);
      _count(entry);
      _notify();
      unawaited(_pump());
    }
  }

  void cancelAll() {
    if (!running || _cancelledAll) return;
    _cancelledAll = true;
    for (final entry in List<_OutboxJob>.of(_entries)) {
      cancel(entry.batch.id);
    }
    _notify();
  }

  ShareSendBatch _status(
    ShareSendBatch batch,
    ShareSendStatus status, [
    String? error,
  ]) => ShareSendBatch(
    id: batch.id,
    transferredBytes: batch.transferredBytes,
    items: [
      for (final item in batch.items) item.update(status: status, error: error),
    ],
  );
}
