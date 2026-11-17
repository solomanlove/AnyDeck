part of 'share_batch_sessions_test.dart';

/// 荣耀在手机确认后先发开始事件；它不包含已传字节，也不代表完成。
void _transferStartedSessionCases() {
  ShareBatchRequest request() => ShareBatchRequest([
    const ShareBatchFile('/synthetic/confirm.txt', 8),
  ]);
  Map<String, dynamic> started() => {
    'event': 'transfer_started',
    'direction': 'send',
    'total_bytes': 8,
  };

  test('荣耀确认后开始事件不结束Core，后续进度和批次终态正常完成', () async {
    final process = _Process();
    final transfer = ShareBatchTransfer(process, request());
    final progress = Completer<ShareCoreProgress>();
    final subscription = transfer.progress.listen(progress.complete);
    addTearDown(subscription.cancel);
    addTearDown(process.stdin.close);
    addTearDown(process.finish);
    var completed = false;
    final result = transfer.result.then((value) {
      completed = true;
      return value;
    });
    process.emit(started());
    process.emit({
      'event': 'progress',
      'direction': 'send',
      'bytes': 2,
      'total_bytes': 8,
    });
    // 让真实解析结果推进断言；旧解析器在开始事件处先抛异常。
    await Future.any<Object?>([progress.future, result]);
    expect((await progress.future).bytes, 2);
    expect(completed, isFalse);
    expect(process.kills, 0);
    process.emit({
      'event': 'batch_sent',
      'file_count': 1,
      'total_bytes': 8,
      'remote_hash_verified': false,
    });
    await process.finish();
    expect((await result)['event'], 'batch_sent');
    expect(process.kills, 0);
  });

  test('只有发送开始事件而缺少完整终态仍失败', () async {
    final process = _Process();
    final transfer = ShareBatchTransfer(process, request());
    addTearDown(process.stdin.close);
    final failure = expectLater(transfer.result, throwsStateError);
    process.emit(started());
    await process.finish();
    await failure;
  });

  for (final mode in ['direction', 'size', 'type', 'missing', 'unknown']) {
    test('发送开始事件拒绝无效 $mode 并回收Core', () async {
      final process = _Process();
      final transfer = ShareBatchTransfer(process, request());
      addTearDown(process.stdin.close);
      final failure = expectLater(transfer.result, throwsFormatException);
      final event = started();
      switch (mode) {
        case 'direction':
          event['direction'] = 'receive';
        case 'size':
          event['total_bytes'] = 9;
        case 'type':
          event['total_bytes'] = 8.0;
        case 'missing':
          event.remove('total_bytes');
        case 'unknown':
          event['event'] = 'unknown_event';
      }
      process.emit(event);
      await failure;
      expect(process.kills, greaterThan(0));
    });
  }
}
