import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../adb/adb_result.dart';

typedef CommandStarter = Future<Process> Function(String, List<String>);

/// 可取消、输出有界的单次 CLI 会话；慢启动、双流及超时均归同一生命周期管理。
class CommandSession {
  CommandSession({CommandStarter? startProcess})
    : _startProcess = startProcess ?? ((exe, args) => Process.start(exe, args));

  final CommandStarter _startProcess;
  Process? _process;
  Future<AdbResult>? _task;
  bool _closed = false;

  Future<AdbResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 8),
    int maxOutputBytes = 2 * 1024 * 1024,
  }) {
    if (_closed) return Future.error(StateError('Command session closed'));
    return _task ??= _run(executable, arguments, timeout, maxOutputBytes);
  }

  Future<AdbResult> _run(
    String executable,
    List<String> arguments,
    Duration timeout,
    int maxOutputBytes,
  ) async {
    final watch = Stopwatch()..start();
    var canceled = false;
    final subscriptions = <StreamSubscription<String>>[];
    try {
      final starting = _startProcess(executable, arguments);
      unawaited(
        starting.then((process) {
          if (canceled || _closed) process.kill(ProcessSignal.sigkill);
        }, onError: (Object _) {}),
      );
      final process = await starting.timeout(timeout);
      _process = process;
      var outputBytes = 0;
      Future<String> collect(Stream<List<int>> stream) {
        final done = Completer<String>();
        final buffer = StringBuffer();
        final bounded = stream
            .map((chunk) {
              outputBytes += chunk.length;
              if (outputBytes > maxOutputBytes) {
                process.kill(ProcessSignal.sigkill);
                throw StateError(
                  'Command output exceeded $maxOutputBytes bytes',
                );
              }
              return chunk;
            })
            .transform(const Utf8Decoder(allowMalformed: true));
        subscriptions.add(
          bounded.listen(
            buffer.write,
            onError: (Object error, StackTrace stack) {
              process.kill(ProcessSignal.sigkill);
              if (!done.isCompleted) done.completeError(error, stack);
            },
            onDone: () {
              if (!done.isCompleted) done.complete(buffer.toString());
            },
          ),
        );
        return done.future;
      }

      final out = collect(process.stdout);
      final err = collect(process.stderr);
      if (_closed) process.kill(ProcessSignal.sigkill);
      final remaining = timeout - watch.elapsed;
      final results = await Future.wait<Object>([
        process.exitCode,
        out,
        err,
      ]).timeout(remaining.isNegative ? Duration.zero : remaining);
      if (_closed) throw StateError('Command session closed');
      return AdbResult(
        exitCode: results[0] as int,
        stdout: results[1] as String,
        stderr: results[2] as String,
      );
    } on TimeoutException {
      canceled = true;
      return AdbResult(exitCode: 124, stdout: '', stderr: 'Command timed out');
    } finally {
      canceled = true;
      _process?.kill(ProcessSignal.sigkill);
      _process = null;
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  /// 可同步从 Provider/Widget 的 dispose 调用，迟到启动的进程也会被终止。
  void close() {
    _closed = true;
    _process?.kill(ProcessSignal.sigkill);
  }
}
