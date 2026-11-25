import 'dart:io';

import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用可控的工具路径验证真实设备发现入口的命令和日志行为。
void main() {
  late Directory temporary;
  late File hdcTool;
  late File iosTool;
  late List<String> logs;
  late HdcService hdc;
  late IosDeviceService ios;
  late IosCommandService iosCommands;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('anydeck discovery ');
    final suffix = Platform.isWindows ? '.exe' : '';
    hdcTool = File('${temporary.path}/hdc$suffix');
    iosTool = File('${temporary.path}/ios$suffix');
    replaceUserToolPaths({'hdc': hdcTool.path, 'ios': iosTool.path});
    logs = [];
    void onLog(String message, {String tag = '', String level = ''}) {
      logs.add('$tag $level $message');
    }

    hdc = HdcService(onLog: onLog);
    ios = IosDeviceService(onLog: onLog);
    iosCommands = IosCommandService(onLog: onLog);
  });

  tearDown(() async {
    replaceUserToolPaths({});
    await temporary.delete(recursive: true);
  });

  Future<void> installTool(File file, String script) async {
    await file.writeAsString('#!/bin/sh\n$script\n');
    expect((await Process.run('chmod', ['700', file.path])).exitCode, 0);
  }

  test('重复发现时，缺失的 HDC 和 iOS 工具不产生控制台日志', () async {
    for (var i = 0; i < 2; i++) {
      expect(await hdc.listDevices(), isEmpty);
      expect(await ios.listDevices(), isEmpty);
    }
    expect(logs, isEmpty);
  });

  test('工具缺失时重连和命令启动仍返回失败且不写控制台', () async {
    expect((await hdc.connectWireless('127.0.0.1:5555')).exitCode, 127);
    expect((await iosCommands.run(['version'])).exitCode, 127);
    await expectLater(hdc.start(['version']), throwsA(isA<ProcessException>()));
    await expectLater(
      iosCommands.start(['version']),
      throwsA(isA<ProcessException>()),
    );
    expect(logs, isEmpty);
  });

  test('文件无执行权限时跳过发现，补齐工具后下次发现即可使用', () async {
    await hdcTool.create();
    await iosTool.create();
    expect(await hdc.listDevices(), isEmpty);
    expect(await ios.listDevices(), isEmpty);
    expect(logs, isEmpty);

    await installTool(hdcTool, r'''
if [ "$1" = list ]; then
  printf '%s\n' 'harmony-test USB Connected localhost'
else
  printf '%s\n' 'Test Harmony Phone'
fi
''');
    await installTool(iosTool, r'''
printf '%s\n' '{"deviceList":[{"Udid":"ios-test","ProductType":"iPhone8,1"}]}'
''');
    expect((await hdc.listDevices()).single.id, 'harmony-test');
    expect((await ios.listDevices()).single.id, 'ios-test');
    expect(logs, contains('hdc I hdc list targets -v'));

    logs.clear();
    await hdcTool.delete();
    await iosTool.delete();
    expect(await hdc.listDevices(), isEmpty);
    expect(await ios.listDevices(), isEmpty);
    expect(logs, isEmpty);
  }, skip: Platform.isWindows);

  test('工具已安装时保留真实失败日志和 HDC 兼容回退', () async {
    await installTool(hdcTool, r'''
if [ "$3" = -v ]; then
  printf '%s\n' 'unsupported verbose' >&2
  exit 1
fi
if [ "$1" = list ]; then
  printf '%s\n' 'harmony-test'
else
  printf '%s\n' 'Test Harmony Phone'
fi
''');
    await installTool(
      iosTool,
      'printf "%s\\n" "device query failed" >&2\nexit 1',
    );

    expect((await hdc.listDevices()).single.id, 'harmony-test');
    expect(await ios.listDevices(), isEmpty);
    expect(logs, contains('hdc E Command failed: unsupported verbose'));
    expect(logs, contains('hdc I hdc list targets'));
    expect(logs, contains(startsWith('ios W go-ios list 失败')));
    expect(logs.last, contains('device query failed'));

    expect((await iosCommands.run(['version'])).isSuccess, isFalse);
    expect(logs, contains('ios I ios version'));
    expect(logs.last, contains('ios E go-ios 命令失败'));
  }, skip: Platform.isWindows);

  test('HDC 文件可执行但进程启动失败时仍记录错误', () async {
    await hdcTool.writeAsString('#!/nonexistent-anydeck-test-shell\n');
    expect((await Process.run('chmod', ['700', hdcTool.path])).exitCode, 0);

    expect((await hdc.run(['version'])).isSuccess, isFalse);
    expect(logs, [startsWith('hdc E Process error:')]);
  }, skip: Platform.isWindows);
}
