/// 按设备串行执行投屏启停，避免异步启动尚未登记 Session 时重复创建 sidecar。
/// 不同设备互不阻塞，失败的操作不会阻断后续清理或重试。
class HarmonyMirrorOperations {
  final Map<String, Future<void>> _pending = {};

  Future<T> run<T>(String deviceId, Future<T> Function() action) {
    final previous = _pending[deviceId] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final settled = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pending[deviceId] = settled;
    settled.then((_) {
      if (identical(_pending[deviceId], settled)) _pending.remove(deviceId);
    });
    return result;
  }
}
