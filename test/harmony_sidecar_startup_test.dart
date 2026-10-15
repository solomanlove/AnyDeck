import 'dart:async';
import 'dart:convert';

import 'package:any_deck/core/harmony/harmony_sidecar_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HarmonySidecarStartup', () {
    test('解析带空格且字段顺序变化的 ready JSON', () async {
      final stdout = StreamController<List<int>>();
      final stderr = StreamController<List<int>>();
      final exitCode = Completer<int>();

      final portFuture = HarmonySidecarStartup.waitForPort(
        stdoutStream: stdout.stream,
        stderrStream: stderr.stream,
        exitCode: exitCode.future,
      );
      stdout.add(utf8.encode('{"port": 52559, "ready": true}\n'));

      expect(await portFuture, 52559);
      await stdout.close();
      await stderr.close();
    });

    test('sidecar 提前退出时返回 stderr 原因', () async {
      final stdout = StreamController<List<int>>();
      final stderr = StreamController<List<int>>();
      final exitCode = Completer<int>();

      final portFuture = HarmonySidecarStartup.waitForPort(
        stdoutStream: stdout.stream,
        stderrStream: stderr.stream,
        exitCode: exitCode.future,
      );
      stderr.add(utf8.encode('Device offline\n'));
      await Future<void>.delayed(Duration.zero);
      exitCode.complete(3);

      await expectLater(
        portFuture,
        throwsA(
          predicate(
            (error) =>
                error.toString().contains('code 3') &&
                error.toString().contains('Device offline'),
          ),
        ),
      );
      await stdout.close();
      await stderr.close();
    });
  });
}
