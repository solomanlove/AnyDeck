part of 'share_batch_sessions_test.dart';

/// 网络状态与文件终态分开验证；恢复警告不能跳过来件确认或破坏完整文件结果。
void _networkTransitionSessionCases() {
  Map<String, dynamic> offer() => {
    'event': 'incoming_batch',
    'ip': '127.0.0.2',
    'file_count': 1,
    'total_bytes': 3,
  };
  Map<String, dynamic> warning(Object? reason) => {
    'event': 'network_warning',
    'reason': reason,
  };
  for (final phase in ['beforeOffer', 'pending', 'rejected']) {
    for (final event in [
      {'event': 'network_connecting'},
      {'event': 'network_restoring'},
      warning('direct_network_restore_failed'),
    ]) {
      test('网络事件 ${event['event']} 在 $phase 未接受时拒绝', () async {
        final process = _Process();
        final session = ShareBatchReceiveSession(
          process,
          directory: '/synthetic/received',
        );
        final failure = expectLater(
          session.events.toList(),
          throwsFormatException,
        );
        try {
          if (phase != 'beforeOffer') {
            process.emit(offer());
            await Future<void>.delayed(Duration.zero);
            if (phase == 'rejected') session.decide(false);
          }
          process.emit(event);
          await failure;
          expect(process.kills, greaterThan(0));
        } finally {
          await session.stop();
          await process.stdin.close();
        }
      });
    }
  }

  for (final reason in [
    'direct_network_restore_failed',
    'direct_network_restore_pending',
  ]) {
    test('接受后转发网络状态及 $reason 警告，仍发布完整批次成功', () async {
      final process = _Process();
      final session = ShareBatchReceiveSession(
        process,
        directory: '/synthetic/received',
      );
      final seen = <Map<String, dynamic>>[];
      final done = Completer<void>();
      final subscription = session.events.listen(
        (event) {
          seen.add(event);
          if (event['event'] == 'incoming_batch') session.decide(true);
        },
        onError: done.completeError,
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      try {
        process.emit(offer());
        await Future<void>.delayed(Duration.zero);
        process.emit({'event': 'network_connecting'});
        process.emit({'event': 'network_restoring'});
        process.emit(warning(reason));
        process.emit({
          'event': 'batch_file_received',
          'index': 0,
          'path': '/synthetic/received/file.bin',
          'bytes': 3,
          'sha256': 'a' * 64,
        });
        process.emit({
          'event': 'batch_received',
          'file_count': 1,
          'total_bytes': 3,
          'sender_hash_verified': false,
        });
        await process.finish();
        await done.future;
        expect(seen.map((event) => event['event']), [
          'incoming_batch',
          'network_connecting',
          'network_restoring',
          'network_warning',
          'batch_received',
        ]);
        expect(seen[3]['reason'], reason);
        expect(seen.last['files'], [
          {
            'path': '/synthetic/received/file.bin',
            'bytes': 3,
            'sha256': 'a' * 64,
          },
        ]);
      } finally {
        await subscription.cancel();
        await session.stop();
        await process.stdin.close();
      }
    });
  }

  for (final reason in <Object?>[
    null,
    1,
    'direct_network_join_failed',
    'synthetic untrusted diagnostic',
  ]) {
    test('接受后仍拒绝未知 network_warning reason $reason', () async {
      final process = _Process();
      final session = ShareBatchReceiveSession(
        process,
        directory: '/synthetic/received',
      );
      final done = Completer<void>();
      final subscription = session.events.listen((event) {
        if (event['event'] == 'incoming_batch') session.decide(true);
      }, onError: done.completeError);
      final failure = expectLater(done.future, throwsFormatException);
      try {
        process.emit(offer());
        await Future<void>.delayed(Duration.zero);
        process.emit(warning(reason));
        await failure;
        expect(process.kills, greaterThan(0));
      } finally {
        await subscription.cancel();
        await session.stop();
        await process.stdin.close();
      }
    });
  }
}
