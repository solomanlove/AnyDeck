import 'dart:io';

import 'package:any_deck/core/process/tool_path_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用隔离文件验证本机工具环境，探测过程中不执行所选 CLI。
void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('anydeck availability ');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<File> createExecutable(String name) async {
    final file = File(
      '${temporary.path}/自定义 $name${Platform.isWindows ? '.EXE' : ''}',
    );
    // 若误加版本探测，会产生 marker；只进行文件和权限检查则不会创建它。
    await file.writeAsString(
      Platform.isWindows
          ? 'AnyDeck test executable'
          : '#!/bin/sh\nprintf ran > "${temporary.path}/executed"\nexit 25\n',
    );
    if (!Platform.isWindows) {
      expect((await Process.run('chmod', ['700', file.path])).exitCode, 0);
    }
    return file;
  }

  for (final tool in configurableToolNames) {
    test('$tool 的可执行绝对路径可用，支持中文空格且不运行 CLI', () async {
      final file = await createExecutable(tool);
      expect(await isToolPathAvailable(tool, file.path), isTrue);
      expect(File('${temporary.path}/executed').existsSync(), isFalse);
    });
  }

  test('所有工具的空路径、未解析工具名与不存在文件均不可用', () async {
    for (final tool in configurableToolNames) {
      for (final path in ['', '  ', tool, '${temporary.path}/missing-$tool']) {
        expect(await isToolPathAvailable(tool, path), isFalse, reason: path);
      }
    }
  });

  test('目录、已存在的相对文件、非法路径和未知工具均不可用', () async {
    final file = await createExecutable('adb');
    expect(await isToolPathAvailable('adb', temporary.path), isFalse);
    expect(await isToolPathAvailable('adb', 'pubspec.yaml'), isFalse);
    expect(await isToolPathAvailable('adb', '${file.path}\u0000'), isFalse);
    expect(await isToolPathAvailable('unknown-tool', file.path), isFalse);
  });

  test('已配置工具后来被删除时，下一次检查立即变为不可用', () async {
    final file = await createExecutable('hdc');
    expect(await isToolPathAvailable('hdc', file.path), isTrue);
    await file.delete();
    expect(await isToolPathAvailable('hdc', file.path), isFalse);
  });

  test('POSIX 普通文件没有执行位时环境不可用', () async {
    final file = await createExecutable('ios');
    expect((await Process.run('chmod', ['600', file.path])).exitCode, 0);
    expect(await isToolPathAvailable('ios', file.path), isFalse);
  }, skip: Platform.isWindows);

  test('POSIX 仅其他用户有执行位不代表当前文件所有者可执行', () async {
    if ((await Process.run('id', ['-u'])).stdout.toString().trim() == '0') {
      markTestSkipped('root 的 access(X_OK) 权限语义不同');
      return;
    }
    final file = await createExecutable('hdc');
    expect((await Process.run('chmod', ['001', file.path])).exitCode, 0);
    expect(await isToolPathAvailable('hdc', file.path), isFalse);
  }, skip: Platform.isWindows);

  test('Windows 仅接受 CLI 可执行扩展名', () async {
    for (final extension in ['exe', 'COM', 'bat', 'CMD']) {
      final file = await File('${temporary.path}/hdc.$extension').create();
      expect(await isToolPathAvailable('hdc', file.path), isTrue);
    }
    final file = await File('${temporary.path}/hdc.txt').create();
    expect(await isToolPathAvailable('hdc', file.path), isFalse);
  }, skip: !Platform.isWindows);
}
