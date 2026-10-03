import 'dart:io';

import 'package:any_deck/core/logging/app_log_capture.dart';
import 'package:any_deck/core/logging/app_log_recorder.dart';
import 'package:any_deck/core/logging/local_log_export.dart';
import 'package:any_deck/core/logging/local_log_store.dart';
import 'package:any_deck/core/logging/log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 日志故障现场的持久化、容量控制、异常捕获与导出回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final recorder = AppLogRecorder.instance;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windowChannel = MethodChannel('mixin.one/desktop_multi_window');
  const messageChannel = MethodChannel(
    'mixin.one/desktop_multi_window/channels',
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anydeck_log_test_');
    recorder.store = null;
    messenger.setMockMethodCallHandler(windowChannel, (call) async => []);
    messenger.setMockMethodCallHandler(messageChannel, (call) async => null);
  });

  tearDown(() async {
    await recorder.store?.flush();
    recorder.store = null;
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(messageChannel, null);
    await temp.delete(recursive: true);
  });

  test('凭据在存储前脱敏，保留堆栈换行并限制单条长度', () {
    const input =
        'Authorization: Bearer abc123\n'
        '{"authorization":"Basic abc456","token":"xyz","password":"hunter2 with spaces"}\n'
        'Cookie: session=private; other=secretvalue\n'
        '#0 main (main.dart:1)';
    final result = AppLogRecorder.sanitize(input);
    for (final secret in [
      'abc123',
      'abc456',
      'xyz',
      'hunter2',
      'with spaces',
      'private',
      'secretvalue',
    ]) {
      expect(result, isNot(contains(secret)));
    }
    expect(result, contains('#0 main (main.dart:1)'));
    expect(AppLogRecorder.sanitize('x' * 10000), endsWith('[truncated]'));
  });

  test('关键日志识别兼容旧时间格式及包含心跳命令的错误', () {
    expect(
      AppLogRecorder.isKeyLog('12:01:02.000 W adb: devices -l failed'),
      isTrue,
    );
    expect(
      AppLogRecorder.isKeyLog(
        '2026-10-04T00:00:00.000 E [main] flutter: error\n#0',
      ),
      isTrue,
    );
    expect(
      AppLogRecorder.isKeyLog(
        '2026-10-04T00:00:00.000 I [main] adb: error keyword',
      ),
      isFalse,
    );
  });

  test('运行日志推断已捕获失败与警告的级别', () {
    expect(AppLogRecorder.runtimeLevel('Failed to start mirror'), 'E');
    expect(AppLogRecorder.runtimeLevel('连接超时'), 'E');
    expect(AppLogRecorder.runtimeLevel('Warning: retrying'), 'W');
    expect(AppLogRecorder.runtimeLevel('connected'), 'I');
  });

  test('内存日志有界且记录严重级别', () {
    final local = AppLogRecorder();
    for (var i = 0; i < 1010; i++) {
      local.record('record $i', level: 'W');
    }
    expect(local.history, hasLength(1000));
    expect(local.history.first, endsWith('record 10'));
    expect(AppLogRecorder.isKeyLog(local.history.last), isTrue);
  });

  test('并发 flush 保持写入顺序且不重复', () async {
    final store = LocalLogStore(temp, 'serial');
    store.add('first');
    final first = store.flush();
    store.add('第二条');
    await Future.wait([first, store.flush(), store.flush()]);
    expect(await File('${temp.path}/anydeck_serial.log').readAsLines(), [
      'first',
      '第二条',
    ]);
  });

  test('文件轮转仅保留当前和上一份并可跨实例读取', () async {
    final store = LocalLogStore(temp, 'rotate', maxBytes: 64);
    for (var i = 0; i < 6; i++) {
      store.add('$i${'x' * 29}');
      await store.flush();
    }
    final restored = LocalLogStore(temp, 'rotate', maxBytes: 64);
    final files = await restored.filesNewestFirst();
    expect(files, hasLength(2));
    for (final file in files) {
      expect(await file.length(), lessThanOrEqualTo(64));
    }
    expect(
      await File('${temp.path}/anydeck_rotate.log').readAsString(),
      contains('5xxx'),
    );
  });

  test('磁盘缓冲溢出有界且写入丢弃提示', () async {
    final store = LocalLogStore(temp, 'overflow');
    for (var i = 0; i < 300; i++) {
      store.add('line $i');
    }
    await store.flush();
    final lines = await File('${temp.path}/anydeck_overflow.log').readAsLines();
    expect(lines, hasLength(257));
    expect(lines.first, contains('Dropped 44'));
    expect(store.lostRecords, 44);
  });

  test('磁盘失败不抛出递归异常，恢复后保留丢失标记', () async {
    final blocker = File('${temp.path}/blocked');
    await blocker.writeAsString('file blocks directory');
    final store = LocalLogStore(Directory(blocker.path), 'failure');
    store.add('failed line');
    await store.flush();
    expect(store.lastError, isNotNull);
    expect(store.lostRecords, 1);
    await blocker.delete();
    store.add('recovered');
    await store.flush();
    expect(store.lastError, isNull);
    expect(store.lostRecords, 1);
  });

  test('历史清理保留新文件及无关文件', () async {
    final store = LocalLogStore(temp, 'prune');
    for (var i = 0; i < 4; i++) {
      final file = File('${temp.path}/anydeck_old_$i.log');
      await file.writeAsString('$i');
      await file.setLastModified(DateTime(2020, 1, i + 1));
    }
    await File('${temp.path}/other.txt').writeAsString('keep');
    await store.prune(keep: 2);
    expect(await store.filesNewestFirst(), hasLength(2));
    expect(await File('${temp.path}/anydeck_old_3.log').exists(), isTrue);
    expect(await File('${temp.path}/other.txt').exists(), isTrue);
  });

  test('Flutter 与 Platform 异常含堆栈且继续调用原处理器', () {
    final oldPrint = debugPrint;
    final oldFlutter = FlutterError.onError;
    final oldPlatform = PlatformDispatcher.instance.onError;
    var forwarded = 0;
    FlutterError.onError = (_) => forwarded++;
    PlatformDispatcher.instance.onError = (_, _) {
      forwarded++;
      return false;
    };
    try {
      installAppLogCapture();
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('capture-test'),
          stack: StackTrace.fromString('#0 capture-frame'),
        ),
      );
      expect(recorder.history.last, contains('#0 capture-frame'));
      expect(AppLogRecorder.isKeyLog(recorder.history.last), isTrue);
      expect(
        PlatformDispatcher.instance.onError!(
          StateError('platform-test'),
          StackTrace.current,
        ),
        isFalse,
      );
      expect(forwarded, 2);
    } finally {
      debugPrint = oldPrint;
      FlutterError.onError = oldFlutter;
      PlatformDispatcher.instance.onError = oldPlatform;
    }
  });

  test('控制台批处理有界，清空不会删除磁盘现场', () async {
    recorder.store = LocalLogStore(temp, 'console');
    final container = ProviderContainer();
    try {
      final service = container.read(logHistoryProvider.notifier);
      for (var i = 0; i < 1100; i++) {
        service.log('console record $i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(container.read(logHistoryProvider), hasLength(1000));
      await recorder.store!.flush();
      service.clear();
      expect(container.read(logHistoryProvider), isEmpty);
      expect(await recorder.store!.filesNewestFirst(), isNotEmpty);
    } finally {
      container.dispose();
    }
  });

  test('导出包含当前和历史会话，含环境信息且不依赖手机', () async {
    final directory = Directory('${temp.path}/logs');
    recorder.store = LocalLogStore(directory, 'current');
    await directory.create();
    await File(
      '${directory.path}/anydeck_old.log',
    ).writeAsString('previous crash stack');
    recorder.record('export current error', level: 'E');
    final target = '${temp.path}/report.log';
    final result = await LocalLogExporter().exportTo(target);
    final text = await File(target).readAsString();
    expect(result.partial, isFalse);
    expect(text, contains('previous crash stack'));
    expect(text, contains('export current error'));
    expect(text, contains('OS:'));
    expect(text, contains('Snapshot status: COMPLETE'));
  });

  test('单文件截断正确标记部分报告', () async {
    final directory = Directory('${temp.path}/logs');
    await directory.create();
    recorder.store = LocalLogStore(directory, 'snapshot');
    await File(
      '${directory.path}/anydeck_large.log',
    ).writeAsString('x' * (2 * 1024 * 1024 + 1));
    final result = await LocalLogExporter().exportTo(
      '${temp.path}/truncated.log',
    );
    expect(result.partial, isTrue);
    expect(await File(result.path).length(), lessThan(2 * 1024 * 1024 + 1024));
  });

  test('无法访问窗口或磁盘时导出内存日志并标记部分成功', () async {
    messenger.setMockMethodCallHandler(
      windowChannel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    recorder.record('fallback memory');
    final target = '${temp.path}/partial.log';
    final result = await LocalLogExporter().exportTo(target);
    expect(result.partial, isTrue);
    expect(await File(target).readAsString(), contains('fallback memory'));
  });

  test('导出不能覆盖托管日志文件，保存失败向调用方报告', () async {
    recorder.store = LocalLogStore(Directory('${temp.path}/logs'), 'protected');
    recorder.record('preserve source');
    await recorder.store!.flush();
    final source = (await recorder.store!.filesNewestFirst()).first;
    await expectLater(
      LocalLogExporter().exportTo(source.path),
      throwsStateError,
    );
    expect(await source.readAsString(), contains('preserve source'));
    await expectLater(
      LocalLogExporter().exportTo('${temp.path}/missing/report.log'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
