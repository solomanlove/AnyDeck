import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/nearby_share/share_batch_client.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存 IPC fixture；不启动网络进程或访问真实设备。
class _Process extends Fake implements Process {
  _Process() {
    input.stream.listen((bytes) => written.addAll(bytes));
  }
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final input = StreamController<List<int>>();
  final written = <int>[];
  final exit = Completer<int>();
  late final sink = IOSink(input.sink);
  Future<void>? _finishing;
  int kills = 0;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  IOSink get stdin => sink;
  @override
  Future<int> get exitCode => exit.future;
  @override
  int get pid => 12345;
  void emit(Map<String, dynamic> event) =>
      output.add(utf8.encode('${jsonEncode(event)}\n'));
  Future<void> finish() => _finishing ??= () async {
    if (!exit.isCompleted) exit.complete(0);
    await output.close();
    await errors.close();
  }();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    unawaited(finish());
    return true;
  }
}

class _BrokenSink extends Fake implements IOSink {
  @override
  void writeln([Object? object = '']) {
    throw StateError('synthetic pipe failure');
  }
}

class _BrokenProcess extends _Process {
  @override
  IOSink get stdin => _BrokenSink();
}

void main() {
  ShareBatchRequest request() => ShareBatchRequest([
    const ShareBatchFile('/synthetic/a', 1073741824),
    const ShareBatchFile('/synthetic/b', 1),
  ]);
  Map<String, dynamic> progress(
    int bytes, {
    String direction = 'send',
    int total = 1073741825,
  }) => {
    'event': 'progress',
    'direction': direction,
    'bytes': bytes,
    'total_bytes': total,
  };
  Map<String, dynamic> sent() => {
    'event': 'batch_sent',
    'file_count': 2,
    'total_bytes': 1073741825,
    'remote_hash_verified': false,
  };
  test('跨 1 GiB 进度不代替终态，完整成功优先于迟到取消', () async {
    final process = _Process();
    final transfer = ShareBatchTransfer(process, request());
    final seen = <ShareCoreProgress>[];
    final sub = transfer.progress.listen(seen.add);
    var completed = false;
    final result = transfer.result.then((value) {
      completed = true;
      return value;
    });
    process.emit(progress(1073741825));
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.fraction, 1);
    expect(completed, isFalse);
    process.emit(sent());
    transfer.cancel();
    expect((await result)['file_count'], 2);
    expect(process.kills, 1);
    await sub.cancel();
  });
  for (final mode in ['regress', 'total', 'terminal', 'missing', 'double']) {
    test('拒绝发送批次 $mode 并回收资源', () async {
      final process = _Process();
      final transfer = ShareBatchTransfer(process, request());
      final failure = expectLater(
        transfer.result,
        mode == 'missing' ? throwsStateError : throwsFormatException,
      );
      if (mode == 'regress') {
        process.emit(progress(10));
        process.emit(progress(9));
      }
      if (mode == 'total') process.emit(progress(1, total: 2));
      if (mode == 'terminal') process.emit({...sent(), 'file_count': 1});
      if (mode == 'double') {
        process.emit(sent());
        process.emit(sent());
      }
      if (mode == 'missing') await process.finish();
      await failure;
      if (mode != 'missing') expect(process.kills, greaterThan(0));
    });
  }
  test('接收只发布完整文件集合，确认只写入一次', () async {
    final process = _Process();
    final session = ShareBatchReceiveSession(
      process,
      directory: '/synthetic/received',
    );
    final events = <Map<String, dynamic>>[];
    final done = Completer<void>();
    final sub = session.events.listen(
      (event) {
        events.add(event);
        if (event['event'] == 'incoming_batch') {
          session.decide(true);
          session.decide(false);
        }
      },
      onError: done.completeError,
      onDone: done.complete,
    );
    process.emit({
      'event': 'incoming_batch',
      'ip': '127.0.0.2',
      'file_count': 2,
      'total_bytes': 3,
    });
    await Future<void>.delayed(Duration.zero);
    process.emit(progress(3, direction: 'receive', total: 3));
    for (var i = 0; i < 2; i++) {
      process.emit({
        'event': 'batch_file_received',
        'index': i,
        'path': '/synthetic/received/$i',
        'bytes': i + 1,
        'sha256': 'a' * 64,
      });
    }
    process.emit({
      'event': 'batch_received',
      'file_count': 2,
      'total_bytes': 3,
      'sender_hash_verified': false,
    });
    await process.finish();
    await done.future;
    expect(
      events.where((event) => event['event'] == 'batch_file_received'),
      isEmpty,
    );
    expect((events.last['files'] as List).length, 2);
    await process.stdin.flush();
    expect(
      utf8.decode(process.written).trim(),
      jsonEncode({'command': 'accept'}),
    );
    await sub.cancel();
    await session.stop();
    await process.stdin.close();
  });
  test('接收文件缺失时不发布完成，且停止进程', () async {
    final process = _Process();
    final session = ShareBatchReceiveSession(
      process,
      directory: '/synthetic/received',
    );
    final failure = expectLater(
      session.events.map((event) {
        if (event['event'] == 'incoming_batch') session.decide(true);
        return event;
      }).toList(),
      throwsFormatException,
    );
    process.emit({
      'event': 'incoming_batch',
      'ip': '127.0.0.2',
      'file_count': 2,
      'total_bytes': 3,
    });
    await Future<void>.delayed(Duration.zero);
    process.emit({
      'event': 'batch_received',
      'file_count': 2,
      'total_bytes': 3,
      'sender_hash_verified': false,
    });
    await failure;
    await session.stop();
    expect(process.kills, greaterThan(0));
    await process.stdin.close();
  });
  test('Client 写入完整请求并关闭发送 stdin，probe 失败不启动进程', () async {
    final process = _Process();
    var launches = 0;
    final client = ShareBatchClient(
      probe: () async {},
      launch: () async {
        launches++;
        return process;
      },
    );
    final transfer = await client.send(
      request: request(),
      local: InternetAddress.loopbackIPv4,
      peer: InternetAddress('127.0.0.2'),
      port: 1,
    );
    final value = jsonDecode(utf8.decode(process.written));
    expect(value['version'], 3);
    expect(value['files'].length, 2);
    process.emit(sent());
    await process.finish();
    await transfer.result;
    final broken = ShareBatchClient(
      probe: () async {
        throw StateError('handshake failed');
      },
      launch: () async {
        launches++;
        return _Process();
      },
    );
    await expectLater(
      broken.send(
        request: request(),
        local: InternetAddress.loopbackIPv4,
        peer: InternetAddress('127.0.0.2'),
        port: 1,
      ),
      throwsStateError,
    );
    expect(launches, 1);
  });
  test('stdin 写入失败会回收已经启动的发送进程', () async {
    final process = _BrokenProcess();
    final client = ShareBatchClient(
      probe: () async {},
      launch: () async => process,
    );
    await expectLater(
      client.send(
        request: request(),
        local: InternetAddress.loopbackIPv4,
        peer: InternetAddress('127.0.0.2'),
        port: 1,
      ),
      throwsStateError,
    );
    expect(process.kills, greaterThan(0));
  });
  test('接收 Client 写入 IPC 3 命令并保持确认通道，不自动接受', () async {
    final root = await Directory.systemTemp.createTemp('batch-client-');
    final process = _Process();
    final client = ShareBatchClient(
      probe: () async {},
      launch: () async => process,
    );
    try {
      final session = await client.receive(
        local: InternetAddress.loopbackIPv4,
        broadcast: InternetAddress('127.255.255.255'),
        output: Directory('${root.path}/received'),
      );
      final request = jsonDecode(utf8.decode(process.written));
      expect(request['command'], 'receive_batch_interactive');
      expect(request['version'], 3);
      final result = session.events.toList();
      process.emit({
        'event': 'error',
        'code': 'receive_failed',
        'reason': 'deadline',
      });
      await process.finish();
      expect((await result).single['event'], 'error');
      expect(utf8.decode(process.written), isNot(contains('accept')));
      await session.stop();
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('接收目标已存在则不 probe 或启动进程', () async {
    final root = await Directory.systemTemp.createTemp(
      'batch-client-existing-',
    );
    var touched = false;
    final client = ShareBatchClient(
      probe: () async {
        touched = true;
      },
      launch: () async {
        touched = true;
        return _Process();
      },
    );
    try {
      await expectLater(
        client.receive(
          local: InternetAddress.loopbackIPv4,
          broadcast: InternetAddress('127.255.255.255'),
          output: root,
        ),
        throwsFormatException,
      );
      expect(touched, isFalse);
    } finally {
      await root.delete();
    }
  });
}
