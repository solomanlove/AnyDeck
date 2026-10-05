import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_screenshot_capture.dart';
import 'package:flutter_test/flutter_test.dart';

const _success = AdbResult(exitCode: 0, stdout: '', stderr: '');
const _missingImage = AdbResult(
  exitCode: 1,
  stdout: '{"level":"WARN","msg":"go-ios agent is not running"}',
  stderr:
      '{"level":"ERROR","msg":"Starting screenshot service failed",'
      '"err":"the Developer Disk Image must be mounted — run ios image auto"}',
);

/// 命令桩写入指定输出，验证恢复顺序、文件生命周期及设备参数。
class _ScreenshotRunner {
  final calls = <List<String>>[];
  final timeouts = <Duration>[];
  final results = <AdbResult>[];
  bool writeFile = true;
  String? outputPath;
  Completer<void>? gate;

  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(args);
    timeouts.add(timeout);
    await gate?.future;
    final result = results.isEmpty ? _success : results.removeAt(0);
    if (args.first == 'screenshot') {
      outputPath = args
          .singleWhere((arg) => arg.startsWith('--output='))
          .substring('--output='.length);
      if (writeFile && result.isSuccess) {
        await File(outputPath!).writeAsBytes([137, 80, 78, 71]);
      }
    }
    return result;
  }
}

void main() {
  test('正常截图不挂载镜像，返回字节并清理临时目录', () async {
    final runner = _ScreenshotRunner();
    final bytes = await IosScreenshotCapture(runner.run).capture('device-a');
    expect(bytes, [137, 80, 78, 71]);
    expect(runner.calls, hasLength(1));
    expect(runner.calls.single, contains('--udid=device-a'));
    expect(await File(runner.outputPath!).parent.exists(), isFalse);
  });

  test('缺少镜像时定向挂载，再重试一次截图', () async {
    final runner = _ScreenshotRunner()
      ..results.addAll([_missingImage, _success, _success]);
    await IosScreenshotCapture(runner.run).capture('device-a');
    expect(runner.calls.map((args) => args.first), [
      'screenshot',
      'image',
      'screenshot',
    ]);
    expect(runner.calls[1], ['image', 'auto', '--udid=device-a']);
    expect(
      runner.calls.every((args) => args.contains('--udid=device-a')),
      isTrue,
    );
    expect(runner.timeouts[1], const Duration(minutes: 5));
    expect(await File(runner.outputPath!).parent.exists(), isFalse);
  });

  test('挂载失败保留 stderr 中的真实错误并停止重试', () async {
    final runner = _ScreenshotRunner()
      ..results.addAll([
        _missingImage,
        const AdbResult(
          exitCode: 1,
          stdout: '{"level":"WARN","msg":"agent is not running"}',
          stderr: '{"level":"ERROR","err":"DeviceLocked"}',
        ),
      ]);
    await expectLater(
      IosScreenshotCapture(runner.run).capture('device-a'),
      throwsA(
        predicate((error) => error.toString() == 'Exception: DeviceLocked'),
      ),
    );
    expect(runner.calls, hasLength(2));
    expect(await File(runner.outputPath!).parent.exists(), isFalse);
  });

  test('重试仍失败时终止，不无限挂载', () async {
    final runner = _ScreenshotRunner()
      ..results.addAll([_missingImage, _success, _missingImage]);
    await expectLater(
      IosScreenshotCapture(runner.run).capture('device-a'),
      throwsException,
    );
    expect(runner.calls, hasLength(3));
    expect(await File(runner.outputPath!).parent.exists(), isFalse);
  });

  test('普通断连和 tunnel 警告不触发镜像挂载', () async {
    final runner = _ScreenshotRunner()
      ..results.add(
        const AdbResult(
          exitCode: 1,
          stdout: '{"level":"WARN","msg":"go-ios agent is not running"}',
          stderr: 'device disconnected',
        ),
      );
    await expectLater(
      IosScreenshotCapture(runner.run).capture('device-a'),
      throwsA(
        predicate((error) => error.toString().contains('device disconnected')),
      ),
    );
    expect(runner.calls, hasLength(1));
  });

  test('命令成功但没有文件时仍失败且清理临时目录', () async {
    final runner = _ScreenshotRunner()..writeFile = false;
    await expectLater(
      IosScreenshotCapture(runner.run).capture('device-a'),
      throwsException,
    );
    expect(await File(runner.outputPath!).parent.exists(), isFalse);
  });

  test('同设备并发请求共享恢复流程，完成后允许新截图', () async {
    final gate = Completer<void>();
    final runner = _ScreenshotRunner()..gate = gate;
    final capture = IosScreenshotCapture(runner.run);
    final first = capture.capture('device-a');
    final second = capture.capture('device-a');
    expect(identical(first, second), isTrue);
    gate.complete();
    await Future.wait([first, second]);
    await capture.capture('device-a');
    expect(runner.calls, hasLength(2));
  });

  test('失败后的请求不会复用已失败的 Future', () async {
    final runner = _ScreenshotRunner()
      ..results.add(
        const AdbResult(exitCode: 1, stdout: '', stderr: 'offline'),
      );
    final capture = IosScreenshotCapture(runner.run);
    await expectLater(capture.capture('device-a'), throwsException);
    expect(await capture.capture('device-a'), isA<Uint8List>());
  });

  test('go-ios 退出码为零但 stderr 含 ERROR 时也判为失败', () async {
    if (Platform.isWindows) return;
    final service = IosCommandService(executable: '/bin/sh');
    final result = await service.run([
      '-c',
      '''printf '%s\\n' '{"level":"ERROR","err":"DeviceLocked"}' >&2''',
    ]);
    expect(result.isSuccess, isFalse);
    expect(result.stderr, contains('DeviceLocked'));
  });

  // 仅显式传入 UDID 时访问真机；常规回归不调用真实 go-ios。
  const udid = String.fromEnvironment('IOS_SCREENSHOT_UDID');
  if (udid.isNotEmpty) {
    test('真机截图字节可以被 Flutter 解码', () async {
      final bytes = await IosCommandService().captureScreenshot(udid);
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      image.dispose();
      codec.dispose();
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
