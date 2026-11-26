import 'dart:io';

import 'package:any_deck/core/emulator/emulator_ide_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用临时文件模拟 IDE 安装，不依赖本机是否安装开发工具。
Future<void> _createFile(String path) async {
  await File(path).create(recursive: true);
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anydeck-emulator-ide-');
  });
  tearDown(() => temp.delete(recursive: true));

  test('macOS 在 Applications 中识别 Android Studio Preview', () async {
    final app = '${temp.path}/Android Studio Preview.app';
    await _createFile('$app/Contents/Info.plist');
    final service = EmulatorIdeService(
      platform: TargetPlatform.macOS,
      applicationDirectories: [temp.path],
      runProcess: (_, _, {required timeout}) async {
        fail('常用安装目录已有应用');
      },
    );
    expect(await service.findAndroidStudio(), app);
  });

  test('Spotlight 识别自定义 Android Studio 路径并使用原路径启动', () async {
    final app = '${temp.path}/Development/Custom Android IDE.app';
    await _createFile('$app/Contents/Info.plist');
    final service = EmulatorIdeService(
      platform: TargetPlatform.macOS,
      applicationDirectories: [],
      runProcess: (command, arguments, {required timeout}) async {
        if (command == '/usr/bin/mdfind') {
          expect(arguments.last, contains('com.google.android.studio'));
          expect(timeout, const Duration(seconds: 2));
          return ProcessResult(
            0,
            0,
            '${temp.path}/stale.app\u0000$app\u0000',
            '',
          );
        }
        expect(command, '/usr/bin/open');
        expect(arguments, ['-a', app]);
        return ProcessResult(0, 0, '', '');
      },
    );

    expect(await service.findAndroidStudio(), app);
    expect(await service.open(app), isTrue);
  });

  test('Xcode 优先使用指定的自定义 Developer 目录', () async {
    final app = '${temp.path}/Custom Xcode.app';
    await _createFile('$app/Contents/Info.plist');
    await _createFile('$app/Contents/Developer/usr/bin/xcodebuild');
    final service = EmulatorIdeService(
      platform: TargetPlatform.macOS,
      environment: {'DEVELOPER_DIR': '$app/Contents/Developer'},
      runProcess: (_, _, {required timeout}) async {
        fail('已取得指定的 Xcode 应用目录');
      },
    );
    expect(await service.findXcode(), app);
  });

  test('仅安装 Command Line Tools 时继续查找完整 Xcode', () async {
    final app = '${temp.path}/Xcode.app';
    final service = EmulatorIdeService(
      platform: TargetPlatform.macOS,
      environment: {},
      applicationDirectories: [temp.path],
      runProcess: (command, arguments, {required timeout}) async {
        if (command == '/usr/bin/xcode-select') {
          expect(arguments, ['-p']);
          return ProcessResult(
            0,
            0,
            '/Library/Developer/CommandLineTools\n',
            '',
          );
        }
        expect(command, '/usr/bin/mdfind');
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(await service.findXcode(), isNull);
    await _createFile('$app/Contents/Info.plist');
    expect(await service.findXcode(), app);
  });

  test('Windows 安装目录与 Linux PATH 可找到 Android Studio 启动器', () async {
    final windowsPath = '${temp.path}/Android/Android Studio/bin/studio64.exe';
    final linuxPath = '${temp.path}/bin/android-studio';
    await _createFile(windowsPath);
    await _createFile(linuxPath);
    final windows = EmulatorIdeService(
      platform: TargetPlatform.windows,
      environment: {'ProgramFiles': temp.path},
    );
    final linux = EmulatorIdeService(
      platform: TargetPlatform.linux,
      environment: {'PATH': '${temp.path}/bin'},
    );
    expect(await windows.findAndroidStudio(), windowsPath);
    expect(await linux.findAndroidStudio(), isNotNull);
    expect(await windows.findXcode(), isNull);
    expect(await linux.findXcode(), isNull);
  });
}
