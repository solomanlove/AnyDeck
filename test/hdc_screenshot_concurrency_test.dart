import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 保留真实临时文件收发与 finally，仅将 HDC 命令边界替换为可控传输。
void main() {
  test('并行 HDC 截图使用独立路径，完成一台不会串图或删除另一台文件', () async {
    final hdc = _ScreenshotHdc(holdTransfers: true);
    final alpha = hdc.captureScreenshot('alpha');
    final beta = hdc.captureScreenshot('beta');
    addTearDown(() async {
      for (final transfer in hdc.transfers) {
        if (!transfer.release.isCompleted) transfer.release.complete();
      }
      await Future.wait([alpha, beta]);
    });
    await hdc.receivedPair.future.timeout(const Duration(seconds: 5));

    final first = hdc.transfers.singleWhere((item) => item.deviceId == 'alpha');
    final second = hdc.transfers.singleWhere((item) => item.deviceId == 'beta');
    final firstDir = File(first.localPath).parent;
    final secondDir = File(second.localPath).parent;
    expect(first.localPath, isNot(second.localPath));
    expect(first.remotePath, isNot(second.remotePath));
    expect(firstDir.path, isNot(secondDir.path));
    expect(firstDir.path, isNot(Directory.systemTemp.path));
    expect(secondDir.path, isNot(Directory.systemTemp.path));

    first.release.complete();
    expect(await alpha, [1, 2]);
    expect(await firstDir.exists(), isFalse);
    expect(await secondDir.exists(), isTrue);
    expect(await File(second.localPath).readAsBytes(), [3, 4]);
    expect(hdc.cleaned, ['alpha:${first.remotePath}']);

    second.release.complete();
    expect(await beta, [3, 4]);
    expect(await secondDir.exists(), isFalse);
    expect(hdc.cleaned, [
      'alpha:${first.remotePath}',
      'beta:${second.remotePath}',
    ]);
  });

  test('HDC 接收失败仍删除部分图片和独立临时目录并清理远端文件', () async {
    final hdc = _ScreenshotHdc(failReceive: true);
    await expectLater(
      hdc.captureScreenshot('alpha'),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('file recv failed'),
        ),
      ),
    );
    final transfer = hdc.transfers.single;
    expect(await File(transfer.localPath).parent.exists(), isFalse);
    expect(hdc.cleaned, ['alpha:${transfer.remotePath}']);
  });

  test('HDC 截图保留 snapshot_display 回退，清理异常不覆盖成功图像', () async {
    final hdc = _ScreenshotHdc(failPrimary: true, throwOnCleanup: true);
    expect(await hdc.captureScreenshot('alpha'), [1, 2]);
    final transfer = hdc.transfers.single;
    expect(hdc.captureCommands, [
      'uitest screenCap -p ${transfer.remotePath}',
      'snapshot_display -f ${transfer.remotePath}',
    ]);
    expect(await File(transfer.localPath).parent.exists(), isFalse);
    expect(hdc.cleaned, ['alpha:${transfer.remotePath}']);
  });
}

class _Transfer {
  _Transfer(this.deviceId, this.remotePath, this.localPath);
  final String deviceId;
  final String remotePath;
  final String localPath;
  final release = Completer<void>();
}

/// 同时写入不同图像，故意暂停接收结束，覆盖两个请求实际重叠的时间窗。
class _ScreenshotHdc extends HdcService {
  _ScreenshotHdc({
    this.holdTransfers = false,
    this.failReceive = false,
    this.failPrimary = false,
    this.throwOnCleanup = false,
  });
  final bool holdTransfers;
  final bool failReceive;
  final bool failPrimary;
  final bool throwOnCleanup;
  final transfers = <_Transfer>[];
  final captureCommands = <String>[];
  final cleaned = <String>[];
  final receivedPair = Completer<void>();
  var _received = 0;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (command.startsWith('rm ')) {
      cleaned.add('$deviceId:${command.substring(3)}');
      if (throwOnCleanup) throw StateError('cleanup failed');
    } else {
      captureCommands.add(command);
      if (failPrimary && command.startsWith('uitest ')) {
        return const AdbResult(exitCode: 1, stdout: '', stderr: 'unsupported');
      }
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    expect(args.take(4), ['-t', args[1], 'file', 'recv']);
    final transfer = _Transfer(args[1], args[4], args[5]);
    transfers.add(transfer);
    await File(
      transfer.localPath,
    ).writeAsBytes(transfer.deviceId == 'alpha' ? [1, 2] : [3, 4]);
    _received++;
    if (holdTransfers) {
      if (_received == 2 && !receivedPair.isCompleted) {
        receivedPair.complete();
      }
      await transfer.release.future;
    }
    return AdbResult(
      exitCode: failReceive ? 1 : 0,
      stdout: '',
      stderr: failReceive ? 'receive failed' : '',
    );
  }
}
