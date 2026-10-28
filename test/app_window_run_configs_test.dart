import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Run Configuration 生成器保留控制台和设备投屏，不再生成模拟器管理窗口', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'anydeck-window-config-test-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final adb = File('${temporary.path}/adb');
    await adb.writeAsString(
      '#!/bin/sh\nprintf "List of devices attached\\nserial-test device model:Pixel_Test\\n"\n',
    );
    await Process.run('/bin/chmod', ['+x', adb.path]);
    final output = '${temporary.path}/configs';
    final result = await Process.run(
      '/bin/bash',
      ['script/generate_app_window_run_configs.sh', '--output-dir', output],
      environment: {'PATH': '${temporary.path}:/usr/bin:/bin'},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final files = await Directory(
      output,
    ).list().where((file) => file is File).toList();
    expect(
      files.map((file) => file.uri.pathSegments.last),
      unorderedEquals(['console_window.xml', 'mirror_window_serial-test.xml']),
    );
    expect(
      await File('$output/console_window.xml').readAsString(),
      contains('type=console'),
    );
    expect(
      await File('$output/mirror_window_serial-test.xml').readAsString(),
      contains('type=mirror'),
    );
  });
}
