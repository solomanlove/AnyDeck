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
  });
  final String id;
  final ShareCorePeer peer;
  final ShareSendFile file;
  final ShareSendStatus status;
  final int transferredBytes;
  final String? error;
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
      );
}

/// 单个用户选择的发送队列；严格串行，一个文件失败不阻断后续文件。
/// send 完成必须代表核心最终成功；cancelActive 负责终止实际进程，控制器不生成假进度。
class HarmonyShareSendQueue extends ChangeNotifier {
  HarmonyShareSendQueue({required this.send, required this.cancelActive});
  final Future<void> Function(ShareSendItem, ValueChanged<ShareCoreProgress>)
  send;
  final VoidCallback cancelActive;
  List<ShareSendItem> _items = [];
  final Set<String> _cancelled = {};
  int? _current;
  int _sequence = 0;
  bool running = false;
  List<ShareSendItem> get items => List.unmodifiable(_items);
  ShareSendItem? get current => _current == null ? null : _items[_current!];
  int get totalBytes =>
      _items.fold(0, (total, item) => total + item.file.bytes);
  int get transferredBytes =>
      _items.fold(0, (total, item) => total + item.transferredBytes);
  int get finished => _items.where((item) => item.terminal).length;
  int count(ShareSendStatus status) =>
      _items.where((item) => item.status == status).length;
  bool isCancelled(String id) => _cancelled.contains(id);

  Future<void> run(ShareCorePeer peer, ShareSendSelection selection) async {
    if (running) throw StateError('Send queue is already running');
    running = true;
    _cancelled.clear();
    final batch = DateTime.now().microsecondsSinceEpoch;
    _items = [
      for (final file in selection.files)
        ShareSendItem(id: '$batch-${_sequence++}', peer: peer, file: file),
    ];
    notifyListeners();
    try {
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

  void cancel(String id) {
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
    for (final item in List<ShareSendItem>.of(_items)) {
      cancel(item.id);
    }
  }

  void clear() {
    if (running) return;
    _items = [];
    _cancelled.clear();
    notifyListeners();
  }

  void _set(int index, ShareSendItem item) {
    _items[index] = item;
    notifyListeners();
  }
}
