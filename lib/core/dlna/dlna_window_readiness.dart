import 'dart:async';

/// 等待回退窗口注册通道，允许冷启动延迟，但限制总等待时长。
Future<bool> waitForDlnaWindowReady(
  Future<bool?> Function() probe, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    final remaining = timeout - watch.elapsed;
    try {
      if (await probe().timeout(remaining) == true) return true;
    } catch (_) {
      // 子窗口尚未注册通道时允许重试，不将瞬时 MissingPlugin 当作失败。
    }
    final delay = timeout - watch.elapsed;
    if (delay <= Duration.zero) break;
    await Future<void>.delayed(delay < interval ? delay : interval);
  }
  return false;
}
