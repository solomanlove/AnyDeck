import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../adb/adb_result.dart';
import 'ios_command_service.dart';

/// 进程页面独占的 CLI 会话，取消仅终止本会话的主机 CLI，不触碰设备进程。
class IosProcessSession {
  IosProcessSession(this.commands);

  final IosCommandService commands;
  final Set<Process> _running = {};
  bool _closed = false;

  void close() {
    _closed = true;
    for (final process in _running) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// 同时消费双流并限制输出大小；处理 Process.start 尚未返回就离页的竞态。
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_closed) throw StateError('iOS process session closed');
    final process = await commands.start(args);
    _running.add(process);
    final out = StringBuffer();
    final err = StringBuffer();
    var size = 0;
    var overflow = false;
    Stream<String> decode(Stream<List<int>> stream) => stream
        .map((chunk) {
          size += chunk.length;
          if (size > 8 * 1024 * 1024) {
            overflow = true;
            process.kill(ProcessSignal.sigkill);
            return <int>[];
          }
          return chunk;
        })
        .transform(const Utf8Decoder(allowMalformed: true));

    final outDone = Completer<void>();
    final errDone = Completer<void>();
    Object? streamError;
    void onError(Object error) {
      streamError = error;
      process.kill(ProcessSignal.sigkill);
    }

    final subscriptions = [
      decode(
        process.stdout,
      ).listen(out.write, onError: onError, onDone: outDone.complete),
      decode(
        process.stderr,
      ).listen(err.write, onError: onError, onDone: errDone.complete),
    ];
    if (_closed) process.kill(ProcessSignal.sigkill);
    try {
      final code = await process.exitCode.timeout(timeout);
      await Future.wait([
        outDone.future,
        errDone.future,
      ]).timeout(const Duration(seconds: 2));
      if (streamError != null) throw StateError('$streamError');
      if (_closed) throw StateError('iOS process session closed');
      if (overflow) throw StateError('go-ios output exceeded 8 MiB');
      final stdout = out.toString();
      final stderr = err.toString();
      final fatal = const LineSplitter().convert('$stdout\n$stderr').any((
        line,
      ) {
        try {
          final value = jsonDecode(line);
          return value is Map &&
              ['error', 'fatal'].contains('${value['level']}'.toLowerCase());
        } catch (_) {
          return false;
        }
      });
      return AdbResult(
        exitCode: code == 0 && fatal ? 1 : code,
        stdout: stdout,
        stderr: stderr,
      );
    } finally {
      process.kill(ProcessSignal.sigkill);
      await Future.wait(subscriptions.map((s) => s.cancel()));
      _running.remove(process);
    }
  }
}
