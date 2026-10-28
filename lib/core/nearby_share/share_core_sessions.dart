import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'share_core_contract.dart';

/// 优先让核心展开栈清理 staging；失去响应时再清理子进程并强制结束。
Future<void> stopShareCoreProcess(Process process) async {
  process.kill();
  await process.exitCode.timeout(
    const Duration(seconds: 5),
    onTimeout: () async {
      if (Platform.isMacOS) {
        try {
          final children = await Process.run('/usr/bin/pgrep', [
            '-P',
            '${process.pid}',
          ]).timeout(const Duration(seconds: 2));
          for (final line in children.stdout.toString().split('\n')) {
            final pid = int.tryParse(line.trim());
            if (pid != null) Process.killPid(pid, ProcessSignal.sigkill);
          }
        } catch (_) {
          // 原生进程可能已自行结束。
        }
      }
      process.kill(ProcessSignal.sigkill);
      return process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
    },
  );
}

/// 一轮接收监听；接收开始后由核心独立控制传输期限。
class ShareCoreReceiveSession {
  ShareCoreReceiveSession(this._process) {
    _errors = _process.stderr.listen((_) {});
    _output = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map(_decode)
        .listen(
          _events.add,
          onError: _events.addError,
          onDone: () async {
            final closed = _events.close();
            if (_listened) await closed;
            if (!_drained.isCompleted) _drained.complete();
          },
        );
  }
  final Process _process;
  final _events = StreamController<Map<String, dynamic>>();
  final _drained = Completer<void>();
  late final StreamSubscription<List<int>> _errors;
  late final StreamSubscription<Map<String, dynamic>> _output;
  bool _listened = false;

  Stream<Map<String, dynamic>> get events {
    _listened = true;
    return _events.stream;
  }

  void decide(bool accept) {
    _process.stdin.writeln(
      jsonEncode({'command': accept ? 'accept' : 'reject'}),
    );
  }

  Future<void> stop() async {
    await stopShareCoreProcess(_process);
    // 保留已经发出的终态事件，再解除订阅，避免取消与成功同时到达时丢失真实结果。
    if (_listened) {
      await _drained.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }
    await _output.cancel();
    if (!_events.isClosed) unawaited(_events.close());
    await _errors.cancel();
  }
}

Map<String, dynamic> _decode(String line) {
  if (line.length > 65536) {
    throw const FormatException('Share Core event too large');
  }
  final value = jsonDecode(line);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid Share Core event');
  }
  return value;
}

/// 单次收发的有界事件流；即时消费进度，只保存最终结果，不缓存全部 stdout。
class ShareCoreTransfer {
  ShareCoreTransfer(this._process, this._expectedEvent) {
    _result = _run();
    // 核心可能在调用方取得会话前快速失败；提前接住错误，result 仍保留原失败语义。
    unawaited(_result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }
  final Process _process;
  final String _expectedEvent;
  final _progress = StreamController<ShareCoreProgress>.broadcast();
  late final Future<Map<String, dynamic>> _result;
  bool _cancelled = false;
  bool _timedOut = false;

  Stream<ShareCoreProgress> get progress => _progress.stream;
  Future<Map<String, dynamic>> get result => _result;

  void cancel() {
    _cancelled = true;
    unawaited(stopShareCoreProcess(_process));
  }

  Future<Map<String, dynamic>> _run() async {
    Map<String, dynamic>? terminal;
    Object? failure;
    final stderr = _process.stderr.listen((_) {});
    final timer = Timer(
      ShareCoreContract.transferTimeout + const Duration(seconds: 10),
      () {
        _timedOut = true;
        unawaited(stopShareCoreProcess(_process));
      },
    );
    try {
      await for (final line
          in _process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final event = _decode(line);
        if (event['event'] == 'progress') {
          final update = ShareCoreProgress.parse(event);
          if (!_progress.isClosed) _progress.add(update);
        } else if (event['event'] == _expectedEvent ||
            event['event'] == 'error') {
          terminal = event;
        }
      }
    } catch (error) {
      failure = error;
      await stopShareCoreProcess(_process);
    } finally {
      await stderr.cancel();
      await _progress.close();
    }
    final exit = await _process.exitCode;
    timer.cancel();
    if (_cancelled) throw StateError('Transfer cancelled');
    if (_timedOut) throw TimeoutException('Share Core transfer timed out');
    if (failure != null) throw failure;
    if (exit != 0 || terminal?['event'] != _expectedEvent) {
      throw StateError(
        'Share Core ${terminal?['code'] ?? exit}: ${terminal?['phase'] ?? ''} ${terminal?['reason'] ?? ''}',
      );
    }
    return terminal!;
  }
}
