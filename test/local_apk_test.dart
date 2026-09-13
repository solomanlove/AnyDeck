import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/apk/apk_install_queue.dart';
import 'package:any_deck/core/apk/apk_file_open_queue.dart';
import 'package:any_deck/core/apk/apk_install_controller.dart';
import 'package:any_deck/core/apk/local_apk_service.dart';

void main() {
  test('设备选择不悄悄切换已经断开的显式目标', () {
    final rows = [
      <String, dynamic>{'id': 'usb-A', 'online': false},
      <String, dynamic>{'id': 'wifi-B', 'online': true},
    ];
    expect(chooseApkDevice(rows, 'usb-A', 'wifi-B'), isNull);
    expect(chooseApkDevice(rows, null, null), 'wifi-B');
    rows.add({'id': 'usb-C', 'online': true});
    expect(chooseApkDevice(rows, null, null), isNull);
    expect(chooseApkDevice(rows, null, 'usb-C'), 'usb-C');
  });

  test('相同设备串行、重复请求合并、不同设备可以完成', () async {
    final queue = ApkInstallQueue();
    final first = Completer<Map<String, dynamic>>();
    final events = <String>[];
    final a = queue.run('A', 'request-1', () {
      events.add('A1');
      return first.future;
    });
    final duplicate = queue.run(
      'A',
      'request-1',
      () async => throw StateError('duplicate'),
    );
    expect(identical(a, duplicate), isTrue);
    final b = queue.run('A', 'request-2', () async {
      events.add('A2');
      return {'success': true};
    });
    await queue.run('B', 'request-3', () async {
      events.add('B1');
      return {'success': true};
    });
    expect(events, ['A1', 'B1']);
    first.complete({
      'success': false,
      'error': 'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
    });
    expect((await a)['success'], false);
    expect((await b)['success'], true);
    expect(events, ['A1', 'B1', 'A2']);
  });

  test('安装异常不会阻塞同设备后续任务', () async {
    final queue = ApkInstallQueue();
    final a = queue.run('A', 'a', () async => throw StateError('offline'));
    final b = queue.run('A', 'b', () async => {'success': true});
    expect((await a)['error'], contains('offline'));
    expect((await b)['success'], true);
  });

  test('冷启动与运行中文件事件按序处理，符号链接统一路径', () async {
    final dir = await Directory.systemTemp.createTemp('apk-open-test-');
    addTearDown(() => dir.delete(recursive: true));
    final apk = File('${dir.path}/中文 a.apk');
    await apk.writeAsString('fixture');
    final alias = Link('${dir.path}/alias.apk');
    await alias.create(apk.path);
    final ready = Completer<void>();
    final opened = <String>[];
    final queue = ApkFileOpenQueue(
      ready: ready.future,
      openDocument: (path) async {
        opened.add(path);
      },
      onError: (error) => fail('$error'),
    );
    queue.add([apk.path, '/tmp/ignored.txt']);
    await Future<void>.delayed(Duration.zero);
    expect(opened, isEmpty);
    queue.add([alias.path]);
    ready.complete();
    await queue.idle;
    expect(opened, [
      await apk.resolveSymbolicLinks(),
      await apk.resolveSymbolicLinks(),
    ]);
  });

  group('宿主机解析进程', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anydeck-apk-test-');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });
    test('中文空格路径与同路径重新读取', () async {
      final file = File('${dir.path}/中文 app.APK');
      await file.writeAsString('{"packageName":"first","label":"中文"}');
      final service = LocalApkService(executable: '/bin/cat');
      addTearDown(service.dispose);
      expect((await service.inspect(file.path)).name, '中文');
      await file.writeAsString('{"packageName":"replacement"}');
      expect((await service.inspect(file.path)).packageName, 'replacement');
    });
    test('不存在、损坏、超量输出有明确错误', () async {
      final service = LocalApkService(executable: '/bin/cat');
      addTearDown(service.dispose);
      await expectLater(
        service.inspect('${dir.path}/missing.apk'),
        throwsFormatException,
      );
      final file = File('${dir.path}/bad.apk');
      await file.writeAsString('not json');
      await expectLater(service.inspect(file.path), throwsFormatException);
      await file.writeAsString('x' * (LocalApkService.maxOutputBytes + 1));
      await expectLater(
        service.inspect(file.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'apkOutputLimit',
          ),
        ),
      );
    });
    test('超时会结束解析器，不遗留运行中的进程', () async {
      final script = File('${dir.path}/parser');
      await script.writeAsString('#!/bin/sh\nexec /bin/sleep 30\n');
      await Process.run('/bin/chmod', ['+x', script.path]);
      final file = File('${dir.path}/app.apk');
      await file.writeAsString('{}');
      final service = LocalApkService(
        executable: script.path,
        timeout: const Duration(milliseconds: 100),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.inspect(file.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'apkParseTimeout',
          ),
        ),
      );
    });
  });
}
