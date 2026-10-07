import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 持续 WDA/forward 子进程：双流有界消费，仅清理本对象创建的 PID。
class IosWdaProcess {
  IosWdaProcess._(this.process) {
    for (final stream in [process.stdout, process.stderr]) {
      _subscriptions.add(
        stream.transform(const Utf8Decoder(allowMalformed: true)).listen((
          chunk,
        ) {
          _log = '$_log$chunk';
          if (_log.length > 8192) _log = _log.substring(_log.length - 8192);
        }),
      );
    }
    unawaited(process.exitCode.then((code) => exitCode = code));
  }
  final Process process;
  final List<StreamSubscription<String>> _subscriptions = [];
  int? exitCode;
  String _log = '';
  String get log => _log;

  static Future<IosWdaProcess> start(
    String executable,
    List<String> arguments,
  ) async => IosWdaProcess._(await Process.start(executable, arguments));

  Future<void> stop() async {
    if (exitCode == null) {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
    await Future.wait(_subscriptions.map((s) => s.cancel()));
  }
}
