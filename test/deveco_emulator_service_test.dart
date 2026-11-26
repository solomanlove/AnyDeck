import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/emulator/harmony/deveco_emulator_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 创建用于路径探测的应用包夹具。
Future<String> _createApp(Directory directory, String name) async {
  final path = '${directory.path}/$name.app';
  final manifest = File('$path/Contents/Info.plist');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('<plist/>');
  return path;
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anydeck-deveco-');
  });
  tearDown(() => temp.delete(recursive: true));

  test('系统和用户 Applications 目录优先于 Spotlight', () async {
    final system = Directory('${temp.path}/system/Applications');
    final user = Directory('${temp.path}/user/Applications');
    final userApp = await _createApp(user, 'DevEco Studio');
    final service = DevEcoEmulatorService(
      platform: TargetPlatform.macOS,
      applicationDirectories: [system.path, user.path],
      runProcess: (executable, arguments, {required timeout}) async {
        fail('常用安装目录已经有应用');
      },
    );

    expect(await service.findDevEcoStudio(), userApp);
    final systemApp = await _createApp(system, 'DevEco-Studio');
    expect(await service.findDevEcoStudio(), systemApp);
  });

  test('Spotlight 忽略失效路径，按自定义安装路径打开应用', () async {
    final custom = Directory('${temp.path}/Developer Tools');
    final app = await _createApp(custom, 'DevEco Studio');
    final missing = '${temp.path}/missing/DevEco-Studio.app';
    final other = await _createApp(custom, 'Other');
    var commands = 0;
    final service = DevEcoEmulatorService(
      platform: TargetPlatform.macOS,
      applicationDirectories: [],
      runProcess: (executable, arguments, {required timeout}) async {
        commands++;
        if (executable == '/usr/bin/mdfind') {
          expect(arguments.first, '-0');
          expect(arguments.last, contains('DevEco-Studio.app'));
          expect(arguments.last, contains('DevEco Studio.app'));
          expect(timeout, const Duration(seconds: 2));
          return ProcessResult(
            0,
            0,
            '$missing\u0000$other\u0000$app\u0000',
            '',
          );
        }

        expect(executable, 'open');
        expect(arguments, ['-a', app]);
        return ProcessResult(0, 0, '', '');
      },
    );

    final detected = await service.findDevEcoStudio();
    expect(detected, app);
    expect(await service.openDevEcoStudio(appPath: detected), isTrue);
    expect(commands, 2);
  });

  test('Spotlight 失败、超时或没有匹配项时返回空路径', () async {
    for (final result in [
      ProcessResult(0, 1, '', ''),
      ProcessResult(0, 0, '', ''),
      TimeoutException('Spotlight 查询超时'),
    ]) {
      final service = DevEcoEmulatorService(
        platform: TargetPlatform.macOS,
        applicationDirectories: [],
        runProcess: (executable, arguments, {required timeout}) async {
          if (result is ProcessResult) return result;
          throw result;
        },
      );
      expect(await service.findDevEcoStudio(), isNull);
    }
  });

  test('其他平台跳过 macOS 应用探测', () async {
    final service = DevEcoEmulatorService(
      platform: TargetPlatform.windows,
      runProcess: (executable, arguments, {required timeout}) async {
        fail('其他平台不应调用 Spotlight');
      },
    );
    expect(await service.findDevEcoStudio(), isNull);
  });
}
