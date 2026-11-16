import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../adb/adb_service.dart';

/// 可展示给用户的失败分类；底层命令和系统输出不进入 Tooltip。
enum FoldableScreenError {
  unsupported,
  unavailable,
  timeout,
  failed,
  busyExternal,
  screenOff,
  recording,
}

/// 切屏请求由设备侧进程持有；取消和关闭只释放本会话的请求。
abstract class FoldableScreenSession {
  bool get ownsOverride;
  Future<void> requestState(int stateId);
  Future<void> reset();
  Future<void> close();
}

typedef FoldableSessionFactory = Future<FoldableScreenSession> Function();

/// 以 JSON 行协议驱动设备 Helper，定期续命并限制握手、响应和退出时间。
class AdbFoldableScreenSession implements FoldableScreenSession {
  AdbFoldableScreenSession._(this._process) {
    _output = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (_) => _ended(), onDone: _ended);
    _errors = _process.stderr.listen((_) {});
    unawaited(_process.exitCode.then((_) => _ended()));
  }

  final Process _process;
  final _ready = Completer<void>();
  final _pending = <int, Completer<void>>{};
  late final StreamSubscription<String> _output;
  late final StreamSubscription<List<int>> _errors;
  Timer? _heartbeat;
  int _nextId = 0;
  int? _requestedState;
  bool _closed = false;
  Future<void>? _closing;

  @override
  bool get ownsOverride => _requestedState != null && !_closed;

  /// 使用内容哈希命名制品，避免多窗口覆盖正在使用的 DEX。
  static Future<FoldableScreenSession> start(
    AdbService adb,
    String deviceId,
  ) async {
    final data = await rootBundle.load(
      'assets/android/foldable-screen-helper.jar',
    );
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final digest = sha256.convert(bytes).toString();
    final remote = '/data/local/tmp/anydeck-foldable-$digest.jar';
    final existing = await adb.shellArgs(deviceId, ['test', '-f', remote]);
    if (!existing.isSuccess) {
      final directory = await Directory.systemTemp.createTemp(
        'anydeck-foldable-',
      );
      try {
        final local = await File(
          '${directory.path}/helper.jar',
        ).writeAsBytes(bytes);
        final pushed = await adb.run([
          '-s',
          deviceId,
          'push',
          local.path,
          remote,
        ]);
        if (!pushed.isSuccess) throw FoldableScreenError.unavailable;
      } finally {
        await directory.delete(recursive: true);
      }
    }
    final process = await adb.start([
      '-s',
      deviceId,
      'shell',
      '-T',
      'env',
      'CLASSPATH=$remote',
      'app_process',
      '/',
      'com.anydeck.helper.FoldableScreenHelper',
    ]);
    return connect(process);
  }

  /// 独立协议入口供进程测试复用；握手前不会发送任何屏幕状态请求。
  static Future<AdbFoldableScreenSession> connect(
    Process process, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final session = AdbFoldableScreenSession._(process);
    try {
      await session._ready.future.timeout(timeout);
      session._heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(
          session._send('ping').catchError((Object _) {
            unawaited(session.close());
          }),
        );
      });
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  void _onLine(String line) {
    // Android 的 app_process 可能先输出系统诊断；只接受协议 JSON 行。
    if (!line.startsWith('{')) return;
    try {
      final message = jsonDecode(line) as Map<String, dynamic>;
      if (message.containsKey('ready')) {
        if (_ready.isCompleted) return;
        if (message['ready'] == true && message['version'] == 1) {
          _ready.complete();
        } else {
          _ready.completeError(_failure(message));
        }
      } else if (message['event'] == 'canceled') {
        if (message['state'] == _requestedState) _requestedState = null;
      } else {
        final response = _pending.remove(message['id']);
        if (message['ok'] == true) {
          response?.complete();
        } else {
          response?.completeError(_failure(message));
        }
      }
    } catch (_) {
      // 非协议 JSON 不改变状态；真正的响应缺失会进入有界超时处理。
    }
  }

  FoldableScreenError _failure(Map<String, dynamic> message) =>
      message['code'] == 'busy' || message['code'] == 'external_override'
      ? FoldableScreenError.busyExternal
      : message['code'] == 'unsupported' || message['code'] == 'permission'
      ? FoldableScreenError.unsupported
      : FoldableScreenError.failed;

  void _ended() {
    _closed = true;
    _heartbeat?.cancel();
    _requestedState = null;
    if (!_ready.isCompleted) {
      _ready.completeError(FoldableScreenError.unavailable);
    }
    for (final pending in _pending.values) {
      pending.completeError(FoldableScreenError.unavailable);
    }
    _pending.clear();
  }

  Future<void> _send(String command, {int? stateId}) async {
    if (_closed) throw FoldableScreenError.unavailable;
    final id = ++_nextId;
    final response = Completer<void>();
    _pending[id] = response;
    try {
      _process.stdin.writeln(
        jsonEncode({'id': id, 'command': command, 'state': ?stateId}),
      );
      await Future.wait<void>([
        _process.stdin.flush(),
        response.future,
      ], eagerError: true).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw FoldableScreenError.timeout;
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Future<void> requestState(int stateId) async {
    await _send('state', stateId: stateId);
    _requestedState = stateId;
  }

  @override
  Future<void> reset() async {
    await _send('reset');
    _requestedState = null;
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _heartbeat?.cancel();
    try {
      if (!_closed && _ready.isCompleted) await _send('close');
    } catch (_) {
      // 即使协议失败，stdin EOF 与设备端 watchdog 仍负责主动取消请求。
    }
    try {
      await _process.stdin.close().timeout(const Duration(seconds: 2));
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      _process.kill();
      await _process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          _process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } finally {
      _ended();
      await _output.cancel();
      await _errors.cancel();
    }
  }
}
