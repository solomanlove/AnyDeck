import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_wda_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本地 HTTP/子进程故障注入：单次超时不能杀死可用会话，也不能重放输入。
void main() {
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
      requestTimeout: const Duration(milliseconds: 250),
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
        ]).timeout(const Duration(seconds: 3));
        expect(results.every((r) => r['ready'] == true), true);
        expect(results.first['width'], 375);
      }
    },
    skip: Platform.isWindows,
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
          jsonEncode({'kind': 'timeout', 'path': path}),
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
    );
  }

  for (final kind in ['timeout', 'invalidSession']) {
    test('$kind with unusable session clears ready', () async {
      await fault.writeAsString(jsonEncode({'kind': kind, 'path': '*'}));
      await expectLater(
        host.execute('phone', 'tap', {'x': 1, 'y': 2}),
        throwsA(predicate((e) => '$e'.contains('iosWdaConnectionLost'))),
      );
      expect((await host.execute('phone', 'status', {}))['ready'], false);
    }, skip: Platform.isWindows);
  }
}
