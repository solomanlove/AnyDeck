import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 显式管理可被远程客户端访问的 HDC Server；默认不启动且仅允许合法 IPv4:Port。
class HdcRemoteServer {
  HdcRemoteServer(this.executable);

  final String executable;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;

  bool get isRunning => _process != null;

  Future<void> start({required String host, required int port}) async {
    if (_process != null) return;
    final normalized = normalizeServerAddress(host, port);
    if (normalized == null) {
      throw const FormatException('Invalid HDC server address');
    }
    final process = await Process.start(executable, ['-s', normalized, '-m']);
    _process = process;
    _stdoutSubscription = process.stdout.transform(utf8.decoder).listen((_) {});
    _stderrSubscription = process.stderr.transform(utf8.decoder).listen((_) {});
    unawaited(process.exitCode.then((_) => _clear(process)));
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    } finally {
      await _clear(process);
    }
  }

  Future<void> _clear(Process process) async {
    if (!identical(_process, process)) return;
    _process = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
  }

  static String? normalizeServerAddress(String host, int port) {
    if (port < 1 || port > 65535) return null;
    if (host == '0.0.0.0' || host == '127.0.0.1') return '$host:$port';
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 ||
        parts.any((part) => part == null || part < 0 || part > 255)) {
      return null;
    }
    return '$host:$port';
  }
}
