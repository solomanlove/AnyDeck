import 'dart:io';
import 'fake_adb_service.dart';

import 'package:any_deck/core/emulator/emulator_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用短命本地脚本模拟 emulator，不启动真实 AVD 或桌面应用。
void main() {
  late Directory temporary;

  setUp(
    () async => temporary = await Directory.systemTemp.createTemp('avd-test-'),
  );
  tearDown(() async => temporary.delete(recursive: true));

  Future<EmulatorService> service(String script) async {
    final executable = File('${temporary.path}/fake-emulator');
    await executable.writeAsString('#!/bin/sh\n$script');
    await Process.run('chmod', ['+x', executable.path]);
    return EmulatorService(
      executable: executable.path,
      adbService: FakeAdbService(),
    );
  }

  test('captures missing system image error and real exit code', () async {
    final emulator = await service('''
printf 'Missing system image android-35/google_apis_playstore/arm64-v8a.\\n' >&2
exit 1
''');
    final launched = await emulator.startEmulator('Small Phone API 35');
    final result = await launched.exited;
    expect(result.code, 1);
    expect(result.output, contains('Missing system image android-35'));
  }, skip: Platform.isWindows);

  test('captures stdout errors and bounds both output buffers', () async {
    final emulator = await service(
      "printf '%s' '${'x' * 40000}'\nprintf '\\nPANIC: broken AVD\\n'\nexit 2\n",
    );
    final result = await (await emulator.startEmulator('test')).exited;
    expect(result.code, 2);
    expect(result.output.length, lessThanOrEqualTo(16384));
    expect(result.output, endsWith('PANIC: broken AVD'));
  }, skip: Platform.isWindows);

  test('AVD name stays one literal argument', () async {
    final emulator = await service('printf \'%s\\n\' "\$#" "\$1" "\$2"\n');
    final result = await (await emulator.startEmulator(
      'Phone; echo injected',
    )).exited;
    expect(result.code, 0);
    expect(result.output, '2\n-avd\nPhone; echo injected');
  }, skip: Platform.isWindows);

  test(
    'cold boot skips snapshots and uses the resolved SDK environment',
    () async {
      final sdk = Directory('${temporary.path}/sdk');
      await Directory('${sdk.path}/platform-tools').create(recursive: true);
      final executable = File('${sdk.path}/emulator/emulator');
      await executable.parent.create(recursive: true);
      await executable.writeAsString(r'''#!/bin/sh
printf '%s\n' "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$ANDROID_AVD_HOME" "$3"
''');
      await Process.run('chmod', ['+x', executable.path]);
      final emulator = EmulatorService(
        executable: executable.path,
        avdHome: '${temporary.path}/avd',
        adbService: FakeAdbService(),
      );
      final result = await (await emulator.startEmulator(
        'test',
        coldBoot: true,
      )).exited;
      expect(
        result.output,
        '${sdk.path}\n${sdk.path}\n${temporary.path}/avd\n-no-snapshot-load',
      );
    },
    skip: Platform.isWindows,
  );

  test('missing executable propagates a diagnostic', () async {
    final emulator = EmulatorService(
      executable: '${temporary.path}/missing',
      adbService: FakeAdbService(),
    );
    await expectLater(
      emulator.startEmulator('test'),
      throwsA(isA<ProcessException>()),
    );
  });
}
