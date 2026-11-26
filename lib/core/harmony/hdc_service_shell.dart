part of 'hdc_service.dart';

/// 原生 Shell 和异步 CLI 共用调用方的命令预算。
extension _HdcShell on HdcService {
  Future<AdbResult> _executeShell(
    String deviceId,
    String command,
    Duration timeout,
  ) async {
    final args = ['-t', deviceId, 'shell', command];
    if (timeout <= Duration.zero) {
      return _timeoutResult('hdc ${args.join(' ')}', timeout);
    }
    if (hasUserToolPath('hdc') || !_nativeBridge.supportsTimedShell) {
      return run(args, timeout: timeout);
    }

    final elapsed = Stopwatch()..start();
    try {
      final out = await _nativeBridge.executeShell(
        deviceId,
        command,
        platform: DevicePlatform.harmony,
        timeout: timeout,
      );
      return AdbResult(exitCode: 0, stdout: out, stderr: '');
    } catch (_) {
      // 原生命令已用完预算时直接返回超时，避免再次执行设备操作。
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        return _timeoutResult('hdc ${args.join(' ')}', timeout);
      }
      return run(args, timeout: remaining);
    }
  }

  AdbResult _timeoutResult(String command, Duration timeout) {
    final message = 'hdc 命令超时(${timeout.inMilliseconds}ms): $command';
    _onLog?.call(message, tag: 'hdc', level: 'E');
    return AdbResult(exitCode: 124, stdout: '', stderr: message);
  }
}
