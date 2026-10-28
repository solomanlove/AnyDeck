import 'dart:async';

import 'package:flutter/foundation.dart';

import 'harmony_share_send_queue.dart';
import 'share_history_database.dart';
import 'share_transfer_record.dart';
import 'share_batch_contract.dart';
import 'share_history_writer.dart';

/// 主窗口唯一记录协调器：小型内存摘要 + 串行持久化，进度最多每秒落盘一次。
class ShareTransferHistory extends ChangeNotifier {
  ShareTransferHistory({
    Future<ShareHistoryDatabase> Function()? open,
    int maxPendingRecords = 1024,
  }) : _maxPendingRecords = maxPendingRecords,
       _open = open ?? ShareHistoryDatabase.openDefault;
  final Future<ShareHistoryDatabase> Function() _open;
  final Map<String, ShareTransferRecord> _cache = {};
  final _changes = StreamController<ShareTransferRecord>.broadcast();
  /// 仅当前会话新产生的记录，不重放启动加载的历史。
  Stream<ShareTransferRecord> get changes => _changes.stream;
  final Map<String, DateTime> _checkpoints = {};
  ShareHistoryDatabase? _database;
  Future<void>? _initializing;
  final int _maxPendingRecords;
  bool _disposed = false;
  late final _writer = ShareHistoryWriter(
    maxRecords: _maxPendingRecords,
    persist: _persist,
    changed: () {
      if (!_disposed) notifyListeners();
    },
  );
  bool initialized = false;
  String? _loadError;
  String? get error => _loadError ?? _writer.error;
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
      _loadError = null;
    } catch (failure) {
      _loadError = '$failure';
    }
    if (!_disposed) notifyListeners();
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
    final saving = _save(records);
    for (final record in records) {
      _remember(record);
    }
    await saving;
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

  /// 发送清单已知：先以事务保存摘要/子文件；不会将总进度分摊到文件。
  Future<void> queuedBatch(ShareSendBatch batch) async {
    await initialize();
    final now = DateTime.now();
    final first = batch.items.first;
    final summary = ShareTransferRecord(
      id: 'send-${batch.id}',
      direction: ShareTransferDirection.send,
      status: ShareTransferStatus.queued,
      deviceName: first.peer.name,
      address: first.peer.address.address,
      port: first.peer.port,
      fileName: batch.items.length == 1 ? first.file.name : '',
      path: batch.items.length == 1 ? first.file.file.path : null,
      bytes: batch.bytes,
      fileCount: batch.items.length,
      createdAt: now,
      retryOf: first.retryOf,
    );
    final saving = _save(_sentBatchRecords(summary, batch));
    _remember(summary);
    await saving;
  }

  void sentBatchChanged(ShareSendBatch batch) {
    final previous = _cache['send-${batch.id}'];
    if (previous == null || previous.terminal) return;
    final next = previous.update(
      status: ShareTransferStatus.values.byName(batch.status.name),
      transferredBytes: batch.transferredBytes,
      completedAt: batch.items.first.terminal ? DateTime.now() : null,
      error: batch.items.first.error,
    );
    final checkpoint = _checkpoints[next.id];
    final persist =
        next.terminal ||
        next.status != previous.status ||
        checkpoint == null ||
        DateTime.now().difference(checkpoint).inSeconds >= 1;
    _remember(next);
    if (persist) {
      _checkpoints[next.id] = DateTime.now();
      unawaited(_save(_sentBatchRecords(next, batch)));
    }
  }

  List<ShareTransferRecord> _sentBatchRecords(
    ShareTransferRecord summary,
    ShareSendBatch batch,
  ) => [
    summary,
    if (batch.items.length > 1)
      for (final item in batch.items)
        ShareTransferRecord(
          id: 'send-${item.id}',
          batchId: summary.id,
          direction: ShareTransferDirection.send,
          status: summary.status,
          deviceName: summary.deviceName,
          address: summary.address,
          port: summary.port,
          fileName: item.file.name,
          path: item.file.file.path,
          bytes: item.file.bytes,
          transferredBytes: item.transferredBytes,
          error: item.error,
          createdAt: summary.createdAt,
          completedAt: summary.completedAt,
          retryOf: item.retryOf,
        ),
  ];

  /// 来件尚无文件名时只保存已知的设备与字节数，不生成假文件清单。
  String incoming({
    required String address,
    required String name,
    required int bytes,
    int fileCount = 1,
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
      fileCount: fileCount,
      bytes: bytes,
      createdAt: DateTime.now(),
    );
    final saving = _save([record]);
    _remember(record);
    unawaited(saving);
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

  /// 完整验证后的批次一次事务落盘；只发摘要事件，避免通知逐文件刷屏。
  bool receivedBatch(String? id, List<Map<String, Object>> files, String directory) {
    final previous = _cache[id];
    if (previous == null || files.length != previous.fileCount ||
        (previous.terminal && previous.status != ShareTransferStatus.cancelled && previous.status != ShareTransferStatus.interrupted)) { return false; }
    final checked = ShareBatchReceived(count: previous.fileCount, bytes: previous.bytes, directory: directory);
    for (var index = 0; index < files.length; index++) {
      checked.add({'event':'batch_file_received','index':index,...files[index]});
    }
    checked.finish({'event':'batch_received','file_count':previous.fileCount,'total_bytes':previous.bytes,'sender_hash_verified':false});
    final now = DateTime.now();
    final single = files.length == 1 ? files.single : null;
    final summary = previous.update(status: ShareTransferStatus.succeeded,
      fileName: single == null ? null : single['path'].toString().split('/').last,
      path: single == null ? directory : single['path'] as String,
      sha256: single?['sha256'] as String?, transferredBytes: previous.bytes, completedAt: now);
    final records = [summary,
      if (single == null) for (var index = 0; index < files.length; index++)
        ShareTransferRecord(id: '${previous.id}-${index.toString().padLeft(3,'0')}',
          direction: ShareTransferDirection.receive, status: ShareTransferStatus.succeeded,
          deviceName: previous.deviceName, address: previous.address,
          fileName: files[index]['path'].toString().split('/').last, path: files[index]['path'] as String,
          bytes: files[index]['bytes'] as int, transferredBytes: files[index]['bytes'] as int,
          sha256: files[index]['sha256'] as String, batchId: previous.id,
          createdAt: previous.createdAt, completedAt: now),
    ];
    final saving = _save(records);
    _remember(summary);
    unawaited(saving);
    return true;
  }

  Future<List<ShareTransferRecord>> batchFiles(String id) async {
    await initialize(); await flush();
    if (_database == null || error != null) throw StateError(error ?? 'History unavailable');
    return _database!.batchFiles(id);
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
    _changes.add(record);
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

  Future<void> _save(List<ShareTransferRecord> records) => _writer.save(records);

  Future<void> _persist(List<ShareTransferRecord> records) async {
    if (_database == null) await initialize();
    if (_database == null) {
      throw StateError(_loadError ?? 'History storage unavailable');
    }
    await _database!.save(records);
  }

  Future<void> flush() => _writer.flush();

  /// 手动恢复仅补写元数据，不重发文件或重放传输结果通知。
  Future<bool> retryPending() async {
    await initialize();
    await flush();
    return error == null;
  }

  @override
  void dispose() {
    _disposed = true;
    _writer.dispose();
    unawaited(_changes.close());
    super.dispose();
  }

  Future<List<ShareTransferRecord>> query({
    ShareTransferDirection? direction,
    String search = '',
    ShareTransferRecord? before,
  }) async {
    await initialize();
    await flush();
    if (_database == null || error != null) {
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
    if (_database == null || error != null) {
      throw StateError(error ?? 'History storage unavailable');
    }
    await _database!.remove(record.id);
    _cache.remove(record.id);
    _checkpoints.remove(record.id);
    notifyListeners();
  }
}
