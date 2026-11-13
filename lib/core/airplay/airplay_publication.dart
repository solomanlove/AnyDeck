import 'dart:async';

/// 等待 Bonjour 回调确认实际名称，不能用启动请求值冒充发布成功。
///
/// [readStatus] 返回 0 等待、1 已确认、2 失败；[readName] 只返回已确认名称。
/// 注入读取方法可验证异步重名和旧库能力边界，无需发布 LAN 服务。
Future<String> waitForAirplayPublication({
  required int Function() readStatus,
  required String? Function() readName,
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 40),
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    final status = readStatus();
    if (status == 2) throw StateError('AirPlay Bonjour publication failed');
    if (status == 1) {
      final name = readName();
      if (name != null && name.isNotEmpty) return name;
    }
    await Future<void>.delayed(interval);
  }
  throw TimeoutException('AirPlay Bonjour publication was not confirmed');
}
