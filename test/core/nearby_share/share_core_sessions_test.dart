import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用内存流验证 IPC，不启动私有核心或网络进程。
class _Process extends Fake implements Process {
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final exit = Completer<int>();
  bool killed = false;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  int get pid => 12345;
  void emit(Map<String, dynamic> event) =>
      output.add(utf8.encode('${jsonEncode(event)}\n'));
  Future<void> finish([int code = 0]) async {
    if (!exit.isCompleted) exit.complete(code);
    await output.close();
    await errors.close();
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    unawaited(finish());
    return true;
  }
}

void main() {
  test('进度在任务结束前可见，100%不替代完成事件', () async {
    final process = _Process();
    final transfer = ShareCoreTransfer(process, 'file_sent');
    final seen = <ShareCoreProgress>[];
    final subscription = transfer.progress.listen(seen.add);
    var completed = false;
    final result = transfer.result.then((value) {
      completed = true;
      return value;
    });
    process.emit({
      'event': 'progress',
      'direction': 'send',
      'bytes': 100,
      'total_bytes': 100,
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.fraction, 1);
    expect(completed, isFalse);
    process.emit({'event': 'file_sent', 'remote_hash_verified': false});
    await process.finish();
    expect((await result)['remote_hash_verified'], isFalse);
    await subscription.cancel();
  });

  test('收到错误时不把最后一条进度误判为成功', () async {
    final process = _Process();
    final transfer = ShareCoreTransfer(process, 'file_received');
    final failure = expectLater(transfer.result, throwsStateError);
    process.emit({
      'event': 'progress',
      'direction': 'receive',
      'bytes': 1,
      'total_bytes': 10,
    });
    process.emit({
      'event': 'error',
      'code': 'receive_failed',
      'reason': 'deadline',
    });
    await process.finish();
    await failure;
  });

  test('取消使原生进程退出并返回取消结果', () async {
    final process = _Process();
    final transfer = ShareCoreTransfer(process, 'file_sent');
    final failure = expectLater(transfer.result, throwsStateError);
    transfer.cancel();
    await failure;
    expect(process.killed, isTrue);
  });

  test('非法进度终止会话，不污染 UI 百分比', () async {
    final process = _Process();
    final transfer = ShareCoreTransfer(process, 'file_sent');
    final failure = expectLater(transfer.result, throwsFormatException);
    process.emit({
      'event': 'progress',
      'direction': 'send',
      'bytes': 11,
      'total_bytes': 10,
    });
    await failure;
    expect(process.killed, isTrue);
  });

  test('进度边界拒绝负数、浮点、无效方向和超量文件', () {
    for (final change in [
      {'bytes': -1},
      {'bytes': 1.5},
      {'direction': 'unknown'},
      {'total_bytes': 0},
      {'total_bytes': ShareCoreContract.maxFileBytes + 1},
    ]) {
      expect(
        () => ShareCoreProgress.parse({
          'event': 'progress',
          'direction': 'send',
          'bytes': 1,
          'total_bytes': 10,
          ...change,
        }),
        throwsFormatException,
      );
    }
  });
}
