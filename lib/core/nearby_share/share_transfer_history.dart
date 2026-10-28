import 'dart:async';

import 'package:flutter/foundation.dart';

import 'harmony_share_send_queue.dart';
import 'share_history_database.dart';
import 'share_transfer_record.dart';

/// 主窗口唯一记录协调器：小型内存摘要 + 串行持久化，进度最多每秒落盘一次。
class ShareTransferHistory extends ChangeNotifier {
  ShareTransferHistory({Future<ShareHistoryDatabase> Function()? open})
    : _open = open ?? ShareHistoryDatabase.openDefault;
  final Future<ShareHistoryDatabase> Function() _open;
  final Map<String, ShareTransferRecord> _cache = {};
  final Map<String, DateTime> _checkpoints = {};
  ShareHistoryDatabase? _database;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  bool initialized = false;
  String? error;
  int _sequence = 0;

  List<ShareTransferRecord> get recent =>
      (_cache.values.toList()..sort((a, b) {
            final time = b.sortTime.compareTo(a.sortTime);
            return time == 0 ? b.id.compareTo(a.id) : time;
          }))
          .take(8)
          .toList();

  Future<void> initialize() async {
    if (initialized) return;
    if (_initializing != null) return _initializing;
    final operation = _load();
    _initializing = operation;
    try {
      await operation;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _load() async {
    try {
      final database = await _open();
      await database.recoverInterrupted();
      final records = await database.query(limit: 8);
      _database = database;
      for (final record in records) {
        _cache.putIfAbsent(record.id, () => record);
      }
      initialized = true;
      error = null;
    } catch (failure) {
      error = '$failure';
    }
    notifyListeners();
  }

  Future<void> queued(List<ShareSendItem> items) async {
    await initialize();
    final now = DateTime.now();
    final records = [
      for (final item in items)
        ShareTransferRecord(
          id: 'send-${item.id}',
          direction: ShareTransferDirection.send,
          status: ShareTransferStatus.queued,
          deviceName: item.peer.name,
          address: item.peer.address.address,
          port: item.peer.port,
          fileName: item.file.name,
          path: item.file.file.path,
          bytes: item.file.bytes,
          createdAt: now,
          retryOf: item.retryOf,
        ),
    ];
    for (final record in records) {
      _remember(record);
    }
    await _save(records);
  }

  void sentItemChanged(ShareSendItem item) {
    final previous = _cache['send-${item.id}'];
    if (previous == null || previous.terminal) return;
    final record = previous.update(
      status: switch (item.status) {
        ShareSendStatus.queued => ShareTransferStatus.queued,
        ShareSendStatus.preparing => ShareTransferStatus.preparing,
        ShareSendStatus.transferring => ShareTransferStatus.transferring,
        ShareSendStatus.succeeded => ShareTransferStatus.succeeded,
        ShareSendStatus.failed => ShareTransferStatus.failed,
        ShareSendStatus.cancelled => ShareTransferStatus.cancelled,
      },
      transferredBytes: item.transferredBytes,
      error: item.error,
      completedAt: item.terminal ? DateTime.now() : null,
    );
    _update(record);
  }

  /// 来件尚无文件名时只保存已知的设备与字节数，不生成假文件清单。
  String incoming({
    required String address,
    required String name,
    required int bytes,
  }) {
    final id =
        'receive-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final record = ShareTransferRecord(
      id: id,
      direction: ShareTransferDirection.receive,
      status: ShareTransferStatus.awaitingAcceptance,
      deviceName: name,
      address: address,
      fileName: '',
      bytes: bytes,
      createdAt: DateTime.now(),
    );
    _remember(record);
    unawaited(_save([record]));
    return id;
  }

  void receiveChanged(
    String? id, {
    ShareTransferStatus? status,
    int? transferredBytes,
    String? fileName,
    String? path,
    String? error,
    String? sha256,
  }) {
    final previous = _cache[id];
    if (previous == null) return;
    final lateSuccess =
        status == ShareTransferStatus.succeeded &&
        (previous.status == ShareTransferStatus.cancelled ||
            previous.status == ShareTransferStatus.interrupted);
    if (previous.terminal && !lateSuccess) return;
    final next = previous.update(
      status: status,
      transferredBytes: transferredBytes,
      fileName: fileName,
      path: path,
      error: error,
      sha256: sha256,
    );
    _update(next.terminal ? next.update(completedAt: DateTime.now()) : next);
  }

  void _update(ShareTransferRecord record) {
    final previous = _cache[record.id];
    final now = DateTime.now();
    final persist =
        record.terminal ||
        previous?.status != record.status ||
        now
                .difference(
                  _checkpoints[record.id] ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                )
                .inSeconds >=
            1;
    _remember(record);
    if (persist) {
      _checkpoints[record.id] = now;
      unawaited(_save([record]));
    }
  }

  void _remember(ShareTransferRecord record) {
    _cache[record.id] = record;
    if (_cache.length > 200) {
      final removable = _cache.values.where((item) => item.terminal).toList()
        ..sort((a, b) => a.sortTime.compareTo(b.sortTime));
      for (final old in removable.take(_cache.length - 200)) {
        _cache.remove(old.id);
        _checkpoints.remove(old.id);
      }
    }
    notifyListeners();
  }

  Future<void> _save(List<ShareTransferRecord> records) {
    final operation = _writes.then((_) async {
      try {
        if (_database == null) await initialize();
        if (_database == null) throw StateError('History storage unavailable');
        await _database!.save(records);
        error = null;
      } catch (failure) {
        error = '$failure';
      }
      notifyListeners();
    });
    _writes = operation;
    return operation;
  }

  Future<void> flush() => _writes;

  Future<List<ShareTransferRecord>> query({
    ShareTransferDirection? direction,
    String search = '',
    ShareTransferRecord? before,
  }) async {
    await initialize();
    await flush();
    if (_database == null) {
      throw StateError(error ?? 'History storage unavailable');
    }
    return _database!.query(
      direction: direction,
      search: search,
      before: before,
    );
  }

  Future<void> remove(ShareTransferRecord record) async {
    if (!record.terminal) return;
    await flush();
    if (_database == null) await initialize();
    if (_database == null) {
      throw StateError(error ?? 'History storage unavailable');
    }
    await _database!.remove(record.id);
    _cache.remove(record.id);
    _checkpoints.remove(record.id);
    notifyListeners();
  }
}
