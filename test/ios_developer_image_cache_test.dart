import 'dart:io';

import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_developer_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用真实短进程验证缓存参数能跨越只读工作目录和包含空格的路径。
void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('anydeck-ddi-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('自动挂载创建绝对缓存目录，不修改调用方参数', () async {
    final cache = Directory('${temporary.path}/cache with spaces/ddi');
    final args = ['image', 'auto', '--udid=device-a'];
    final prepared = await IosDeveloperImageCache(
      directory: cache,
    ).prepare(args);
    expect(prepared, [...args, '--basedir=${cache.absolute.path}']);
    expect(args, ['image', 'auto', '--udid=device-a']);
    expect(await cache.exists(), isTrue);
  });

  test('保留显式 basedir 的两种写法，普通命令不创建缓存', () async {
    final cache = Directory('${temporary.path}/unused');
    final helper = IosDeveloperImageCache(directory: cache);
    for (final args in [
      ['image', 'auto', '--basedir=/explicit/cache', '--udid=a'],
      ['image', 'auto', '--basedir', '/explicit/cache', '--udid=a'],
      ['image', 'list', '--udid=a'],
      ['screenshot', '--udid=a'],
    ]) {
      expect(await helper.prepare(args), same(args));
    }
    expect(await cache.exists(), isFalse);
  });

  test('默认缓存位于 AnyDeck 的绝对路径', () async {
    final args = await IosDeveloperImageCache().prepare(['image', 'auto']);
    final directory = args.last.substring('--basedir='.length);
    expect(Directory(directory).isAbsolute, isTrue);
    expect(directory.replaceAll('\\', '/'), endsWith('AnyDeck/ios/devimages'));
    expect(directory, isNot('${Directory.current.path}/devimages'));
  });

  test('只读工作目录下的真实子进程仍能使用缓存', () async {
    if (Platform.isWindows) return;
    final executable = File('${temporary.path}/fake-ios');
    await executable.writeAsString(r'''#!/bin/sh
cd / || exit 2
printf '%s\n' "$@"
for argument in "$@"; do
  case "$argument" in --basedir=*) cache="${argument#--basedir=}";; esac
done
case "$cache" in /*) test -d "$cache" || exit 3;; *) exit 4;; esac
''');
    await Process.run('chmod', ['+x', executable.path]);
    final cache = Directory('${temporary.path}/cache with spaces');
    final service = IosCommandService(
      executable: executable.path,
      developerImageCacheDirectory: cache,
    );
    final result = await service.run(['image', 'auto', '--udid=device-a']);
    expect(result.isSuccess, isTrue, reason: result.message);
    expect(result.stdout.split('\n'), contains('--basedir=${cache.path}'));
    expect(result.stdout, contains('--udid=device-a'));
  });

  test('缓存创建失败返回错误且不启动命令', () async {
    final file = await File(
      '${temporary.path}/not-a-directory',
    ).writeAsString('occupied');
    final service = IosCommandService(
      executable: '/not/an/executable',
      developerImageCacheDirectory: Directory('${file.path}/cache'),
    );
    final result = await service.run(['image', 'auto', '--udid=device-a']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('FileSystemException'));
  });
}
