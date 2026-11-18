import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前窗口共用两个截图槽；等待中的不可见卡片可撤回，不会启动额外 CLI。
final deviceScreenPreviewQueueProvider = Provider((ref) {
  final queue = DeviceScreenPreviewQueue();
  ref.onDispose(queue.dispose);
  return queue;
});

/// 静态截图队列；运行中的槽直到平台命令真正结束才释放。
class DeviceScreenPreviewQueue {
  DeviceScreenPreviewQueue({this.concurrency = 2});
  final int concurrency;
  final _waiting = <DeviceScreenPreviewRequest>[];
  var _running = 0;
  var _disposed = false;

  DeviceScreenPreviewRequest enqueue(
    Future<void> Function() action, {
    required bool Function() isCurrent,
  }) {
    final request = DeviceScreenPreviewRequest._(action, isCurrent);
    request._cancel = () {
      if (!request.started && _waiting.remove(request)) {
        request._done.complete();
      }
    };
    if (_disposed) {
      request._done.complete();
    } else {
      _waiting.add(request);
      _drain();
    }
    return request;
  }

  void _drain() {
    while (!_disposed && _running < concurrency && _waiting.isNotEmpty) {
      final request = _waiting.removeAt(0);
      if (!request._isCurrent()) {
        request._done.complete();
        continue;
      }
      request.started = true;
      _running++;
      unawaited(
        Future.sync(request._action)
            .then(
              (_) => request._done.complete(),
              onError: (Object error, StackTrace stack) =>
                  request._done.completeError(error, stack),
            )
            .whenComplete(() {
              _running--;
              _drain();
            }),
      );
    }
  }

  void dispose() {
    _disposed = true;
    for (final request in _waiting) {
      request._done.complete();
    }
    _waiting.clear();
  }
}

/// 单次排队凭据；取消只撤回未开始的任务，不假装终止不支持取消的 Future。
class DeviceScreenPreviewRequest {
  DeviceScreenPreviewRequest._(this._action, this._isCurrent);
  final Future<void> Function() _action;
  final bool Function() _isCurrent;
  final _done = Completer<void>();
  late final void Function() _cancel;
  bool started = false;
  Future<void> get future => _done.future;
  void cancel() => _cancel();
}
