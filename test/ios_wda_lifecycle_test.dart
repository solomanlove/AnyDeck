import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_wda_host.dart';

/// 用本地假 CLI 检查完整会话启动和自有进程回收，而非只 Mock 单个方法。
void main() {
  test(
    'existing WDA is reused even when launching another runner would fail',
    () async {
      final dir = await Directory.systemTemp.createTemp('wda-reuse-');
      addTearDown(() => dir.delete(recursive: true));
      final cli = await File(
        'test/fixtures/ios_wda_fake.py',
      ).copy('${dir.path}/ios.py');
      await Process.run('chmod', ['+x', cli.path]);
      await File('${dir.path}/ios.ready-phone').create();
      await File('${dir.path}/ios.runner-fails').create();
      final host = IosWdaHost(
        commands: IosCommandService(executable: cli.path),
        forwardExecutable: cli.path,
      );
      addTearDown(host.close);
      for (var i = 0; i < 2; i++) {
        expect((await host.execute('phone', 'start', {}))['ready'], true);
        await host.execute('phone', 'geometry', {});
        await host.execute('phone', 'tap', {'x': 100, 'y': 200});
        await host.execute('phone', 'button', {'name': 'volumeUp'});
        await host.execute('phone', 'button', {'name': 'volumeDown'});
        await host.execute('phone', 'button', {'name': 'home'});
        await host.execute('phone', 'stop', {});
      }
      final calls = (await File(
        '${dir.path}/ios.calls',
      ).readAsLines()).map((line) => jsonDecode(line) as Map).toList();
      expect(calls.where((c) => c['args'][0] == 'runwda'), isEmpty);
      final payloads = (await File('${dir.path}/ios.payloads').readAsLines())
          .map((line) => jsonDecode(line) as Map).toList();
      final volume = payloads.where(
        (call) => call['path'] == '/session/phone/wda/performIoHidEvent',
      ).toList();
      expect(volume.map((call) => call['body']), [
        for (var i = 0; i < 2; i++) ...[
          {'page': 12, 'usage': 233, 'duration': 0.1},
          {'page': 12, 'usage': 234, 'duration': 0.1},
        ],
      ]);
      expect(payloads.where((call) => call['path'] == '/wda/homescreen'),
          hasLength(2));
      final proxies = calls.where((c) => c['args'][0] == '--source');
      expect(proxies, hasLength(2));
      for (final proxy in proxies) {
        expect(
          (await Process.run('kill', ['-0', '${proxy['pid']}'])).exitCode,
          isNot(0),
        );
      }
    },
    skip: Platform.isWindows,
  );

  test(
    'two devices use distinct loopback ports and all owned processes exit',
    () async {
      final dir = await Directory.systemTemp.createTemp('wda-lifecycle-');
      addTearDown(() => dir.delete(recursive: true));
      final cli = await File(
        'test/fixtures/ios_wda_fake.py',
      ).copy('${dir.path}/ios.py');
      await Process.run('chmod', ['+x', cli.path]);
      final host = IosWdaHost(
        commands: IosCommandService(executable: cli.path),
        forwardExecutable: cli.path,
      );
      addTearDown(host.close);
      final sessions = await Future.wait([
        host.execute('phone-A', 'start', {}),
        host.execute('phone-B', 'start', {}),
      ]);
      expect(sessions.every((s) => s['ready'] == true), true);
      expect(sessions[0]['port'], isNot(sessions[1]['port']));
      expect(sessions[0]['width'], 375);
      final again = await host.execute('phone-A', 'start', {});
      expect(again['ready'], true);
      await host.execute('phone-A', 'tap', {'x': 100, 'y': 200});
      await host.execute('phone-A', 'stop', {});
      expect((await host.execute('phone-B', 'status', {}))['ready'], true);
      await host.close();
      final calls = (await File(
        '${dir.path}/ios.calls',
      ).readAsLines()).map((l) => jsonDecode(l) as Map).toList();
      final owned = calls
          .where((c) => ['runwda', '--source'].contains(c['args'][0]))
          .toList();
      expect(owned, hasLength(4));
      for (final child in owned) {
        final probe = await Process.run('kill', ['-0', '${child['pid']}']);
        expect(probe.exitCode, isNot(0), reason: 'owned process must exit');
      }
      for (final session in sessions) {
        await expectLater(
          Socket.connect(
            '127.0.0.1',
            session['port'] as int,
            timeout: const Duration(milliseconds: 450),
          ),
          throwsA(isA<SocketException>()),
        );
      }
    },
    skip: Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
