import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'share_core_contract.dart';

/// 优先让核心展开栈清理 staging；超时后保留可信网络 helper 的还原机会。
Future<void> stopShareCoreProcess(
  Process process, {
  String? coreExecutable,
  Duration gracefulTimeout = const Duration(seconds: 5),
}) async {
  process.kill();
  await process.exitCode.timeout(
    gracefulTimeout,
    onTimeout: () async {
      if (Platform.isMacOS) {
        try {
          final children = await Process.run('/usr/bin/pgrep', [
            '-P',
            '${process.pid}',
          ]).timeout(const Duration(seconds: 2));
          final childPids = children.stdout.toString().split('\n')
              .map((line) => int.tryParse(line.trim())).whereType<int>().toList();
          if (childPids.isNotEmpty) {
            final identities = await _readCoreProcessIdentities([
              process.pid, ...childPids,
            ]);
            final helper = await _trustedNetworkHelper(
              coreExecutable, identities[process.pid]?.executable,
            );
            for (final pid in childPids) {
              final child = identities[pid];
              if (child == null || child.parent != process.pid) continue;
              final restoresNetwork = helper != null &&
                  await _regularExecutable(child.executable) == helper;
              // Core 退出后会关闭 helper stdin；SIGTERM/EOF 均触发原网络恢复。
              Process.killPid(pid, restoresNetwork
                  ? ProcessSignal.sigterm : ProcessSignal.sigkill);
            }
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

/// 只读取 comm，不读取可能包含凭据的 argv；保留带空格的完整可执行路径。
Future<Map<int, ({int parent, String executable})>> _readCoreProcessIdentities(
  List<int> pids,
) async {
  final result = await Process.run('/bin/ps', [
    '-ww', '-p', pids.join(','), '-o', 'pid=,ppid=,comm=',
  ]).timeout(const Duration(seconds: 2));
  final identities = <int, ({int parent, String executable})>{};
  final pattern = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.+)$');
  for (final line in result.stdout.toString().split('\n')) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    identities[int.parse(match[1]!)] = (
      parent: int.parse(match[2]!), executable: match[3]!.trim(),
    );
  }
  return identities;
}

/// 仅保护当前 Core 目录下的真实 sibling；同名程序、symlink 与路径错配不豁免。
Future<String?> _trustedNetworkHelper(String? requestedCore, String? actualCore) async {
  if (requestedCore == null || actualCore == null) return null;
  final core = await _regularExecutable(requestedCore);
  if (core == null || File(core).uri.pathSegments.last != 'anydeck-share-core' ||
      await _regularExecutable(actualCore) != core) {
    return null;
  }
  return _regularExecutable('${File(core).parent.path}/share-network');
}

Future<String?> _regularExecutable(String path) async {
  try {
    final file = File(path);
    if (!file.isAbsolute || await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    return await file.resolveSymbolicLinks();
  } on FileSystemException {
    return null; // 进程退出或制品替换时，不把失效路径视为可信 helper。
  }
}

/// 一轮接收监听；接收开始后由核心独立控制传输期限。
class ShareCoreReceiveSession {
  ShareCoreReceiveSession(this._process, {String? coreExecutable})
      : _coreExecutable = coreExecutable {
    _errors = _process.stderr.listen((_) {});
    _output = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map(decodeShareCoreEvent)
        .listen(
          (event) {
            if (event['event'] == 'error' || event['event'] == 'file_received' || event['event'] == 'batch_received') {
              _terminal = true;
            }
            _events.add(event);
          },
          onError: _events.addError,
          onDone: () async {
            if (!_stopping && !_terminal) {
              _events.addError(StateError('Share Core receive_failed: core_stopped'));
            }
            final closed = _events.close();
            if (_listened) await closed;
            if (!_drained.isCompleted) _drained.complete();
          },
        );
  }
  final Process _process;
  final String? _coreExecutable;
  final _events = StreamController<Map<String, dynamic>>();
  final _drained = Completer<void>();
  late final StreamSubscription<List<int>> _errors;
  late final StreamSubscription<Map<String, dynamic>> _output;
  bool _listened = false;
  bool _stopping = false;
  bool _terminal = false;

  Stream<Map<String, dynamic>> get events {
    _listened = true;
    return _events.stream;
  }

  void decide(bool accept) {
    try {
      _process.stdin.writeln(jsonEncode({'command': accept ? 'accept' : 'reject'}));
      unawaited(_process.stdin.flush().timeout(const Duration(seconds: 2)).catchError((Object error) {
        if (!_events.isClosed) _events.addError(error);
      }));
    } catch (error) {
      if (!_events.isClosed) _events.addError(error);
    }
  }

  Future<void> stop() async {
    _stopping = true;
    await stopShareCoreProcess(_process, coreExecutable: _coreExecutable);
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
    try {
      await _process.stdin.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // 已退出核心的 stdin 可能已关闭；资源清理不覆盖原始传输结果。
    }
  }
}

/// 对单行 UTF-8 事件执行统一大小和对象边界校验。
Map<String, dynamic> decodeShareCoreEvent(String line) {
  if (utf8.encode(line).length > 65536) {
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
  ShareCoreTransfer(this._process, this._expectedEvent, {String? coreExecutable})
      : _coreExecutable = coreExecutable {
    _result = _run();
    // 核心可能在调用方取得会话前快速失败；提前接住错误，result 仍保留原失败语义。
    unawaited(_result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }
  final Process _process;
  final String? _coreExecutable;
  final String _expectedEvent;
  final _progress = StreamController<ShareCoreProgress>.broadcast();
  late final Future<Map<String, dynamic>> _result;
  bool _cancelled = false;
  bool _timedOut = false;

  Stream<ShareCoreProgress> get progress => _progress.stream;
  Future<Map<String, dynamic>> get result => _result;

  void cancel() {
    _cancelled = true;
    unawaited(stopShareCoreProcess(_process, coreExecutable: _coreExecutable));
  }

  Future<Map<String, dynamic>> _run() async {
    Map<String, dynamic>? terminal;
    Object? failure;
    final stderr = _process.stderr.listen((_) {});
    final timer = Timer(
      ShareCoreContract.transferTimeout + const Duration(seconds: 10),
      () {
        _timedOut = true;
        unawaited(stopShareCoreProcess(_process, coreExecutable: _coreExecutable));
      },
    );
    try {
      await for (final line
          in _process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final event = decodeShareCoreEvent(line);
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
      await stopShareCoreProcess(_process, coreExecutable: _coreExecutable);
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
