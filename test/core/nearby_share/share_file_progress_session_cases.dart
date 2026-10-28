part of 'share_batch_sessions_test.dart';

/// 复用内存进程 fixture 验证真实 JSONL 边界，不启动网络或创建大样本。
void _fileProgressSessionCases() {
  ShareBatchRequest request() => ShareBatchRequest([
    const ShareBatchFile('/synthetic/a', 5),
    const ShareBatchFile('/synthetic/b', 3),
  ]);
  Map<String, dynamic> progress(
    int index,
    int bytes,
    int total, {
    String direction = 'send',
  }) => {
    'event': 'file_progress',
    'direction': direction,
    'index': index,
    'bytes': bytes,
    'total_bytes': total,
  };
  test('发送文件100%仍等待批次终态，文件与总进度分开传递', () async {
    final process = _Process();
    final transfer = ShareBatchTransfer(process, request());
    final seen = <ShareCoreProgress>[];
    final sub = transfer.progress.listen(seen.add);
    var completed = false;
    final result = transfer.result.then((event) {
      completed = true;
      return event;
    });
    process.emit(progress(1, 3, 3));
    process.emit(progress(0, 2, 5));
    process.emit({
      'event': 'progress',
      'direction': 'send',
      'bytes': 5,
      'total_bytes': 8,
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(seen.whereType<ShareCoreFileProgress>().map((file) => file.index), [
      1,
      0,
    ]);
    expect(seen.last is ShareCoreFileProgress, isFalse);
    process.emit({
      'event': 'batch_sent',
      'file_count': 2,
      'total_bytes': 8,
      'remote_hash_verified': false,
    });
    await process.finish();
    await result;
    await sub.cancel();
    await process.stdin.close();
  });
  for (final mode in ['index', 'size', 'regress', 'direction', 'type']) {
    test('发送 Session 拒绝文件进度 $mode 并回收进程', () async {
      final process = _Process();
      final transfer = ShareBatchTransfer(process, request());
      final failure = expectLater(transfer.result, throwsFormatException);
      process.emit(progress(0, 2, 5));
      final bad = switch (mode) {
        'index' => progress(2, 1, 1),
        'size' => progress(0, 3, 6),
        'regress' => progress(0, 1, 5),
        'direction' => progress(0, 3, 5, direction: 'receive'),
        _ => {...progress(0, 3, 5), 'bytes': 3.5},
      };
      process.emit(bad);
      await failure;
      expect(process.kills, greaterThan(0));
      await process.stdin.close();
    });
  }
  for (final mode in ['valid', 'unaccepted', 'mismatch']) {
    test('接收文件进度 $mode 需要接受且核对最终大小', () async {
      final process = _Process();
      final session = ShareBatchReceiveSession(
        process,
        directory: '/synthetic/received',
      );
      final seen = <Map<String, dynamic>>[];
      final done = Completer<void>();
      final sub = session.events.listen(
        (event) {
          seen.add(event);
          if (event['event'] == 'incoming_batch' && mode != 'unaccepted') {
            session.decide(true);
          }
        },
        onError: done.completeError,
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      final checked = mode == 'valid'
          ? done.future
          : expectLater(done.future, throwsFormatException);
      process.emit({
        'event': 'incoming_batch',
        'ip': '127.0.0.2',
        'file_count': 2,
        'total_bytes': 8,
      });
      await Future<void>.delayed(Duration.zero);
      process.emit(progress(0, 5, 5, direction: 'receive'));
      if (mode == 'valid') {
        process.emit(progress(1, 3, 3, direction: 'receive'));
        for (var index = 0; index < 2; index++) {
          process.emit({
            'event': 'batch_file_received',
            'index': index,
            'path': '/synthetic/received/$index',
            'bytes': index == 0 ? 5 : 3,
            'sha256': 'a' * 64,
          });
        }
        process.emit({
          'event': 'batch_received',
          'file_count': 2,
          'total_bytes': 8,
          'sender_hash_verified': false,
        });
        await process.finish();
      } else if (mode == 'mismatch') {
        process.emit({
          'event': 'batch_file_received',
          'index': 0,
          'path': '/synthetic/received/0',
          'bytes': 4,
          'sha256': 'a' * 64,
        });
      }
      await checked;
      if (mode == 'valid') {
        expect(
          seen.where((event) => event['event'] == 'file_progress').length,
          2,
        );
        expect(seen.last['event'], 'batch_received');
      } else {
        expect(process.kills, greaterThan(0));
      }
      await sub.cancel();
      await session.stop();
      await process.stdin.close();
    });
  }
}
