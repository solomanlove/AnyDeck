import 'dart:async';

/// 主窗口持有的安装队列：相同请求合并，同一 serial 串行，不同设备独立。
class ApkInstallQueue {
  final _tails = <String, Future<void>>{};
  final _requests = <String, Future<Map<String, dynamic>>>{};

  Future<Map<String, dynamic>> run(
    String serial,
    String requestId,
    Future<Map<String, dynamic>> Function() install,
  ) {
    final existing = _requests[requestId];
    if (existing != null) return existing;
    final previous = _tails[serial] ?? Future<void>.value();
    final result = previous
        .then((_) => install())
        .catchError(
          (Object error) => <String, dynamic>{
            'success': false,
            'error': error.toString(),
          },
        );
    final tail = result.then<void>((_) {});
    _tails[serial] = tail;
    _requests[requestId] = result;
    unawaited(
      result.whenComplete(() {
        _requests.remove(requestId);
        if (identical(_tails[serial], tail)) _tails.remove(serial);
      }),
    );
    return result;
  }
}
