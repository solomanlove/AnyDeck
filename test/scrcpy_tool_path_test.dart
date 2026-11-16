import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:any_deck/core/scrcpy/scrcpy_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用临时 CLI 记录 scrcpy 实际收到的 ADB 环境，不连接任何设备。
void main() {
  test('外部 scrcpy 每次启动使用当前 ADB，显式传入路径仍优先', () async {
    final temporary = await Directory.systemTemp.createTemp('anydeck scrcpy ');
    final capture = File('${temporary.path}/captured adb');
    final fakeScrcpy = File('${temporary.path}/custom scrcpy');
    await fakeScrcpy.writeAsString(
      '#!/bin/sh\nprintf "%s" "\$ADB" > "${capture.path}"\n',
    );
    await Process.run('chmod', ['700', fakeScrcpy.path]);
    final service = ScrcpyService();
    addTearDown(() async {
      await service.stopAll();
      replaceUserToolPaths({});
      await temporary.delete(recursive: true);
    });

    Future<String> launch({String? adbPath}) async {
      final exited = Completer<void>();
      await service.start(
        deviceId: 'test-only-device',
        adbPath: adbPath,
        onExit: (code) {
          expect(code, 0);
          exited.complete();
        },
      );
      await exited.future.timeout(const Duration(seconds: 5));
      return capture.readAsString();
    }

    final first = '${temporary.path}/first adb';
    final second = '${temporary.path}/second adb';
    replaceUserToolPaths({'adb': first, 'scrcpy': fakeScrcpy.path});
    expect(await launch(), first);
    replaceUserToolPaths({'adb': second, 'scrcpy': fakeScrcpy.path});
    expect(await launch(), second);
    expect(await launch(adbPath: '/explicit/adb'), '/explicit/adb');
  }, skip: Platform.isWindows);
}
