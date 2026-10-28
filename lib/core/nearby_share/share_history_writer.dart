import 'dart:async';

import 'share_transfer_record.dart';

/// 为活跃任务预留完整清单槽位，失败时保留最新事务，不丢弃旧记录腾空间。
class ShareHistoryBufferFull extends StateError {
  ShareHistoryBufferFull()
    : super(
        'History buffer full; retry saving before starting another transfer',
      );
  @override
  String toString() => 'history_buffer_full';
}

class _HistoryGroup {
  _HistoryGroup(this.capacity);
  final int capacity;
  final records = <String, ShareTransferRecord>{};
  int revision = 0;
  bool dirty = false;
}

/// 有界、串行的元数据写入器；同一批次始终作为完整事务重试。
/// persist 必须原子提交；changed 只通知保存状态，不重放传输成功/通知事件。
class ShareHistoryWriter {
  ShareHistoryWriter({
    required this.persist,
    required this.changed,
    this.maxRecords = 1024,
  }) {
    if (maxRecords < 1) throw ArgumentError.value(maxRecords, 'maxRecords');
  }
  final Future<void> Function(List<ShareTransferRecord>) persist;
  final void Function() changed;
  final int maxRecords;
  final _groups = <String, _HistoryGroup>{};
  Future<void>? _writing;
  Timer? _retry;
  int _failures = 0;
  bool _disposed = false;
  String? error;
  int get reservedRecords =>
      _groups.values.fold(0, (sum, group) => sum + group.capacity);
  int get pendingRecords => _groups.values
      .where((group) => group.dirty)
      .fold(0, (sum, group) => sum + group.records.length);

  /// 先完整检查容量再更新；已预留的任务可继续写入终态和全部子文件。
  Future<void> save(List<ShareTransferRecord> records) {
    if (_disposed) throw StateError('History writer disposed');
    final required = <String, int>{};
    for (final record in records) {
      final key = record.batchId ?? record.id;
      final size = record.batchId == null && record.fileCount > 1
          ? record.fileCount + 1
          : 1;
      if (size > (required[key] ?? 0)) required[key] = size;
    }
    final added = required.entries
        .where((entry) => !_groups.containsKey(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
    if (reservedRecords + added > maxRecords) throw ShareHistoryBufferFull();
    for (final entry in required.entries) {
      final existing = _groups[entry.key];
      if (existing != null && entry.value > existing.capacity) {
        throw StateError('History group capacity changed');
      }
    }
    for (final entry in required.entries) {
      final existing = _groups[entry.key];
      final members = {
        if (existing != null) ...existing.records.keys,
        for (final record in records)
          if ((record.batchId ?? record.id) == entry.key) record.id,
      };
      if (members.length > (existing?.capacity ?? entry.value) ||
          !members.contains(entry.key)) {
        throw StateError('Invalid history group members');
      }
    }
    for (final entry in required.entries) {
      _groups.putIfAbsent(entry.key, () => _HistoryGroup(entry.value));
    }
    for (final record in records) {
      final group = _groups[record.batchId ?? record.id]!;
      group.records[record.id] = record;
      group.revision++;
      group.dirty = true;
    }
    if (_retry != null) return Future.value();
    return _start();
  }

  /// 显式重试/退出前排空；一次失败就返回并保留错误，后台继续有退避地重试。
  Future<void> flush() {
    _retry?.cancel();
    _retry = null;
    return _start();
  }

  Future<void> _start() {
    if (_disposed) return Future.value();
    if (_writing != null) return _writing!;
    if (pendingRecords == 0) return Future.value();
    final operation = _drain().whenComplete(() {
      _writing = null;
      if (!_disposed) changed();
      if (!_disposed &&
          pendingRecords > 0 &&
          _retry == null &&
          _writing == null) {
        unawaited(_start());
      }
    });
    _writing = operation;
    return operation;
  }

  Future<void> _drain() async {
    while (!_disposed && pendingRecords > 0) {
      final snapshot = {
        for (final entry in _groups.entries)
          if (entry.value.dirty) entry.key: entry.value.revision,
      };
      final records = [
        for (final key in snapshot.keys) ..._groups[key]!.records.values,
      ];
      try {
        await persist(records);
      } catch (failure) {
        if (_disposed) return;
        error = '$failure';
        final seconds = [1, 2, 5, 10, 30][_failures.clamp(0, 4)];
        _failures = (_failures + 1).clamp(0, 4);
        _retry = Timer(Duration(seconds: seconds), () {
          _retry = null;
          unawaited(_start());
        });
        return;
      }
      for (final entry in snapshot.entries) {
        final group = _groups[entry.key]!;
        if (group.revision != entry.value) continue;
        group.dirty = false;
        if (group.records[entry.key]?.terminal == true) {
          _groups.remove(entry.key);
        }
      }
    }
    if (!_disposed) {
      error = null;
      _failures = 0;
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _retry = null;
  }
}
