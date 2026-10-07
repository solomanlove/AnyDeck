import 'dart:async';
import 'package:any_deck/core/ios/ios_app_info.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_wda_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// 不访问真机；控制安装清单查询完成时机，覆盖启动/停止竞态。
class _Commands extends IosCommandService {
  final apps = Completer<List<IosAppInfo>>();
  @override
  Future<List<IosAppInfo>> listApps(String udid) => apps.future;
}

void main() {
  test(
    'missing WDA returns explicit prerequisite and never reports ready',
    () async {
      final commands = _Commands()..apps.complete([]);
      final host = IosWdaHost(commands: commands);
      addTearDown(host.close);
      await expectLater(
        host.execute('phone', 'start', {}),
        throwsA(predicate((e) => '$e'.contains('iosWdaRunnerMissing'))),
      );
      expect((await host.execute('phone', 'status', {}))['ready'], false);
    },
  );
  test(
    'stop cancels pending start before any runner can be launched',
    () async {
      final commands = _Commands();
      final host = IosWdaHost(commands: commands);
      addTearDown(host.close);
      final starting = host.execute('phone', 'start', {});
      final assertion = expectLater(
        starting,
        throwsA(predicate((e) => '$e'.contains('iosControlClosed'))),
      );
      await host.execute('phone', 'stop', {});
      commands.apps.complete([]);
      await assertion;
      expect((await host.execute('phone', 'status', {}))['ready'], false);
    },
  );
  test(
    'same device rejects queued input and a different device stays independent',
    () async {
      final commands = _Commands();
      final host = IosWdaHost(commands: commands);
      addTearDown(host.close);
      final starting = host.execute('A', 'start', {});
      final assertion = expectLater(starting, throwsStateError);
      await expectLater(
        host.execute('A', 'tap', {'x': 1, 'y': 1}),
        throwsA(predicate((e) => '$e'.contains('iosControlBusy'))),
      );
      await expectLater(
        host.execute('B', 'tap', {'x': 1, 'y': 1}),
        throwsA(predicate((e) => '$e'.contains('iosWdaUnavailable'))),
      );
      commands.apps.complete([]);
      await assertion;
    },
  );
}
