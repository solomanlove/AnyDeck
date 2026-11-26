import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_wda_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本地 HTTP/子进程故障注入：单次超时不能杀死可用会话，也不能重放输入。
void main() {
  // 包含假 CLI 启动、WDA 就绪轮询和最慢的两次 HTTP 超时。
  const integrationTimeout = Timeout(Duration(seconds: 90));
  late Directory dir;
  late IosWdaHost host;
  late File fault;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wda-recovery-');
    final cli = await File(
      'test/fixtures/ios_wda_fake.py',
    ).copy('${dir.path}/ios.py');
    await Process.run('chmod', ['+x', cli.path]);
    fault = File('${dir.path}/ios.fault');
    host = IosWdaHost(
      commands: IosCommandService(executable: cli.path),
      forwardExecutable: cli.path,
      // 真实 HTTP/子进程在全量并行测试时也需要调度预算；故障由假服务持续阻塞响应注入。
      requestTimeout: const Duration(seconds: 5),
    );
    await host.execute('phone', 'start', {});
  });
  tearDown(() async {
    await host.close();
    await dir.delete(recursive: true);
  });

  test(
    'repeated shared geometry completes and does not block later input',
    () async {
      for (var i = 0; i < 3; i++) {
        final results = await Future.wait([
          host.execute('phone', 'geometry', {}),
          host.execute('phone', 'geometry', {}),
          host.execute('phone', 'tap', {'x': 1, 'y': 2}),
        ]).timeout(const Duration(seconds: 10));
        expect(results.every((r) => r['ready'] == true), true);
        expect(results.first['width'], 375);
      }
    },
    skip: Platform.isWindows,
    timeout: integrationTimeout,
  );

  for (final action in ['tap', 'geometry']) {
    test(
      '$action timeout preserves responsive session without replay',
      () async {
        final path = action == 'tap'
            ? '/session/phone/actions'
            : '/session/phone/window/size';
        if (action == 'geometry') {
          await Future<void>.delayed(const Duration(milliseconds: 550));
        }
        await fault.writeAsString(
          jsonEncode({'kind': 'timeout', 'path': path, 'delaySeconds': 20}),
        );
        await expectLater(
          host.execute('phone', action, {'x': 1, 'y': 2}),
          throwsA(predicate((e) => '$e'.contains('iosWdaRequestTimeout'))),
        );
        expect((await host.execute('phone', 'status', {}))['ready'], true);
        final requests = await File('${dir.path}/ios.requests').readAsLines();
        expect(
          requests.where((line) => line == path).length,
          action == 'tap' ? 1 : 2,
        );
        await fault.delete();
        expect(
          (await host.execute('phone', 'tap', {'x': 3, 'y': 4}))['ready'],
          true,
        );
      },
      skip: Platform.isWindows,
      timeout: integrationTimeout,
    );
  }

  for (final kind in ['timeout', 'invalidSession']) {
    test('$kind with unusable session clears ready', () async {
      await fault.writeAsString(
        jsonEncode({'kind': kind, 'path': '*', 'delaySeconds': 20}),
      );
      await expectLater(
        host.execute('phone', 'tap', {'x': 1, 'y': 2}),
        throwsA(predicate((e) => '$e'.contains('iosWdaConnectionLost'))),
      );
      expect((await host.execute('phone', 'status', {}))['ready'], false);
    }, skip: Platform.isWindows, timeout: integrationTimeout);
  }
}
