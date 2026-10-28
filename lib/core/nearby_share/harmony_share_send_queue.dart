import 'package:flutter/foundation.dart';

import 'share_core_client.dart';
import 'share_send_selection.dart';

/// 文件状态独立于字节进度；字节达到 100% 后仍需等待核心最终成功事件。
enum ShareSendStatus {
  queued,
  preparing,
  transferring,
  succeeded,
  failed,
  cancelled,
}

/// 队列行的不可变快照；id 用于取消，file 用于展示/后续重试，error 保留该项失败原因。
class ShareSendItem {
  const ShareSendItem({
    required this.id,
    required this.peer,
    required this.file,
    this.status = ShareSendStatus.queued,
    this.transferredBytes = 0,
    this.error,
    this.retryOf,
  });
  final String id;
  final ShareCorePeer peer;
  final ShareSendFile file;
  final ShareSendStatus status;
  final int transferredBytes;
  final String? error;
  final String? retryOf;
  bool get terminal =>
      status == ShareSendStatus.succeeded ||
      status == ShareSendStatus.failed ||
      status == ShareSendStatus.cancelled;
  ShareSendItem update({ShareSendStatus? status, int? bytes, String? error}) =>
      ShareSendItem(
        id: id,
        peer: peer,
        file: file,
        status: status ?? this.status,
        transferredBytes: bytes ?? transferredBytes,
        error: error ?? this.error,
        retryOf: retryOf,
      );
}

/// 原生批次不可变快照；仅有整批字节进度，不推测每个文件的已传字节。
class ShareSendBatch {
  ShareSendBatch({
    required this.id,
    required List<ShareSendItem> items,
    required this.transferredBytes,
  }) : items = List.unmodifiable(items);
  final String id;
  final List<ShareSendItem> items;
  final int transferredBytes;
  int get bytes => items.fold(0, (sum, item) => sum + item.file.bytes);
  ShareSendStatus get status => items.first.status;
}

/// 用户选择对应一次原生批次；未配置 sendBatch 时兼容旧串行调用。
/// send 完成必须代表核心最终成功；cancelActive 负责终止实际进程，控制器不生成假进度。
class HarmonyShareSendQueue extends ChangeNotifier {
  HarmonyShareSendQueue({
    required this.send,
    required this.cancelActive,
    this.onQueued,
    this.onChanged,
    this.sendBatch,
    this.onBatchQueued,
    this.onBatchChanged,
  });
  final Future<void> Function(ShareSendItem, ValueChanged<ShareCoreProgress>)
  send;
  final Future<void> Function(
    List<ShareSendItem>,
    ValueChanged<ShareCoreProgress>,
  )?
  sendBatch;
  final Future<void> Function(ShareSendBatch)? onBatchQueued;
  final ValueChanged<ShareSendBatch>? onBatchChanged;
  final VoidCallback cancelActive;
  final Future<void> Function(List<ShareSendItem>)? onQueued;
  final ValueChanged<ShareSendItem>? onChanged;
  List<ShareSendItem> _items = [];
  final Set<String> _cancelled = {};
  int? _current;
  int _sequence = 0;
  bool running = false;
  String _batchId = '';
  int _batchBytes = 0;
  bool _batchCancelled = false;
  bool get nativeBatch => sendBatch != null;
  bool get cancelling => _batchCancelled && running;
  ShareSendBatch get batch =>
      ShareSendBatch(id: _batchId, items: items, transferredBytes: _batchBytes);
  List<ShareSendItem> get items => List.unmodifiable(_items);
  ShareSendItem? get current => _current == null ? null : _items[_current!];
  int get totalBytes =>
      _items.fold(0, (total, item) => total + item.file.bytes);
  int get transferredBytes => nativeBatch
      ? _batchBytes
      : _items.fold(0, (total, item) => total + item.transferredBytes);
  int get finished => _items.where((item) => item.terminal).length;
  int count(ShareSendStatus status) =>
      _items.where((item) => item.status == status).length;
  bool isCancelled(String id) => _cancelled.contains(id);

  Future<void> run(
    ShareCorePeer peer,
    ShareSendSelection selection, {
    String? retryOf,
  }) async {
    if (running) throw StateError('Send queue is already running');
    running = true;
    _cancelled.clear();
    _batchBytes = 0;
    _batchCancelled = false;
    final batch = DateTime.now().microsecondsSinceEpoch;
    _batchId = '$batch-${_sequence++}';
    _items = [
      for (final file in selection.files)
        ShareSendItem(
          id: '$batch-${_sequence++}',
          peer: peer,
          file: file,
          retryOf: retryOf,
        ),
    ];
    notifyListeners();
    try {
      if (nativeBatch) {
        await onBatchQueued?.call(this.batch);
        await _runNative();
        return;
      }
      if (onQueued != null) {
        await onQueued!(items);
        // 初始落盘期间也允许取消；补齐当时已变成终态的记录。
        for (final item in _items.where((item) => item.terminal)) {
          onChanged?.call(item);
        }
      }
      for (var index = 0; index < _items.length; index++) {
        if (_items[index].terminal) continue;
        _current = index;
        _set(index, _items[index].update(status: ShareSendStatus.preparing));
        if (_cancelled.contains(_items[index].id)) {
          _set(index, _items[index].update(status: ShareSendStatus.cancelled));
          continue;
        }
        try {
          await send(_items[index], (progress) {
            if (_current != index ||
                _cancelled.contains(_items[index].id) ||
                progress.direction != 'send' ||
                progress.totalBytes != _items[index].file.bytes ||
                progress.bytes < _items[index].transferredBytes ||
                progress.bytes > progress.totalBytes ||
                progress.bytes < 0) {
              return;
            }
            _set(
              index,
              _items[index].update(
                status: ShareSendStatus.transferring,
                bytes: progress.bytes,
              ),
            );
          });
          // 取消可能晚于核心成功事件，最终成功为准，避免记录与队列状态相互矛盾。
          _set(
            index,
            _items[index].update(
              status: ShareSendStatus.succeeded,
              bytes: _items[index].file.bytes,
            ),
          );
        } catch (failure) {
          _set(
            index,
            _items[index].update(
              status: _cancelled.contains(_items[index].id)
                  ? ShareSendStatus.cancelled
                  : ShareSendStatus.failed,
              error: _cancelled.contains(_items[index].id) ? null : '$failure',
            ),
          );
        }
      }
    } finally {
      _current = null;
      running = false;
      notifyListeners();
    }
  }

  /// 原生批次只有完整成功/失败，所有文件共用结果；100% 字节仍等待终态。
  Future<void> _runNative() async {
    if (_batchCancelled) {
      _setBatch(ShareSendStatus.cancelled);
      return;
    }
    _setBatch(ShareSendStatus.preparing);
    final activeBatch = _batchId;
    try {
      await sendBatch!(items, (progress) {
        if (!running ||
            activeBatch != _batchId ||
            _items.first.terminal ||
            _batchCancelled ||
            progress.direction != 'send' ||
            progress.totalBytes != totalBytes ||
            progress.bytes < _batchBytes ||
            progress.bytes < 0 ||
            progress.bytes > totalBytes) {
          return;
        }
        _batchBytes = progress.bytes;
        if (_items.first.status != ShareSendStatus.transferring) {
          _setBatch(ShareSendStatus.transferring);
        } else {
          onBatchChanged?.call(batch);
          notifyListeners();
        }
      });
      _batchBytes = totalBytes;
      _setBatch(ShareSendStatus.succeeded);
    } catch (failure) {
      _setBatch(
        _batchCancelled ? ShareSendStatus.cancelled : ShareSendStatus.failed,
        error: _batchCancelled ? null : '$failure',
      );
    }
  }

  void _setBatch(ShareSendStatus status, {String? error}) {
    _items = [
      for (final item in _items)
        item.update(
          status: status,
          bytes: status == ShareSendStatus.succeeded ? item.file.bytes : 0,
          error: error,
        ),
    ];
    onBatchChanged?.call(batch);
    notifyListeners();
  }

  void cancel(String id) {
    if (nativeBatch) {
      if (_items.any((item) => item.id == id && !item.terminal)) cancelAll();
      return;
    }
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || _items[index].terminal) return;
    if (!_cancelled.add(id)) return;
    if (index == _current) {
      cancelActive();
    } else {
      _set(index, _items[index].update(status: ShareSendStatus.cancelled));
    }
  }

  void cancelAll() {
    if (nativeBatch) {
      if (!running || _batchCancelled || _items.every((item) => item.terminal)) {
        return;
      }
      _batchCancelled = true;
      _cancelled.addAll(_items.map((item) => item.id));
      cancelActive();
      notifyListeners();
      return;
    }
    for (final item in List<ShareSendItem>.of(_items)) {
      cancel(item.id);
    }
  }

  void clear() {
    if (running) return;
    _items = [];
    _batchBytes = 0;
    _cancelled.clear();
    notifyListeners();
  }

  void _set(int index, ShareSendItem item) {
    _items[index] = item;
    onChanged?.call(item);
    notifyListeners();
  }
}
