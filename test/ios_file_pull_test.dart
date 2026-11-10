import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/mcp/tools/mcp_ios_tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 go-ios 把远端文件写入 dstPath 目录，检查最终文件和失败保护。
class _Commands extends IosCommandService {
  final calls = <List<String>>[];
  bool produceFile = true;
  bool fail = false;
  List<int> bytes = [1, 2, 3];
  String? temporaryPath;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(args);
    expect(timeout, const Duration(minutes: 5));
    temporaryPath = args
        .singleWhere((a) => a.startsWith('--dstPath='))
        .substring('--dstPath='.length);
    if (fail) {
      return const AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: 'DeviceDisconnected',
      );
    }
    if (produceFile) {
      await File('$temporaryPath/remote.txt').writeAsBytes(bytes);
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ios-pull-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('下载到指定完整文件名，清理临时目录，返回真实路径和字节数', () async {
    final commands = _Commands();
    final destination = '${directory.path}/new folder/saved.txt';
    final tool = McpIosTools(
      commands: commands,
      isIosDevice: (_) async => true,
    ).getTools().singleWhere((t) => t.name == 'ios_file_pull');
    final result = await tool.handler({
      'deviceId': 'phone-a',
      'bundleId': 'com.example.test',
      'remotePath': '/Documents/remote.txt',
      'localPath': destination,
    });
    expect(await File(destination).readAsBytes(), [1, 2, 3]);
    expect(result['localPath'], destination);
    expect(result['byteLength'], 3);
    expect(commands.calls.single, contains('--udid=phone-a'));
    expect(commands.calls.single, contains('--app=com.example.test'));
    expect(await Directory(commands.temporaryPath!).exists(), isFalse);
  });

  for (final missingOutput in [true, false]) {
    test('下载${missingOutput ? '缺少产物' : '命令失败'}时保留旧文件并清理临时目录', () async {
      final commands = _Commands()
        ..produceFile = false
        ..fail = !missingOutput;
      final destination = await File(
        '${directory.path}/saved.txt',
      ).writeAsString('old');
      final result = await commands.pullFile(
        'phone-a',
        bundleId: 'com.example.test',
        remotePath: '/Documents/remote.txt',
        localPath: destination.path,
      );
      expect(result.isSuccess, isFalse);
      expect(await destination.readAsString(), 'old');
      expect(await Directory(commands.temporaryPath!).exists(), isFalse);
      if (!missingOutput) expect(result.stderr, 'DeviceDisconnected');
    });
  }

  test('目录目标被明确拒绝，不启动下载命令', () async {
    final commands = _Commands();
    final result = await commands.pullFile(
      'phone-a',
      bundleId: 'com.example.test',
      remotePath: '/Documents/remote.txt',
      localPath: directory.path,
    );
    expect(result.isSuccess, isFalse);
    expect(commands.calls, isEmpty);
  });

  test('成功后替换旧文件，允许合法的空文件', () async {
    final commands = _Commands()..bytes = [];
    final destination = await File(
      '${directory.path}/saved.txt',
    ).writeAsString('old');
    final result = await commands.pullFile(
      'phone-a',
      bundleId: 'com.example.test',
      remotePath: '/Documents/remote.txt',
      localPath: destination.path,
    );
    expect(result.isSuccess, isTrue);
    expect(await destination.length(), 0);
    expect(await Directory(commands.temporaryPath!).exists(), isFalse);
  });
}
