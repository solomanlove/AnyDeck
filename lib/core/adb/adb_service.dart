import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../process/tool_path_resolver.dart';
import 'adb_device.dart';
import 'adb_result.dart';

/// adb 薄封装，集中处理进程执行和设备列表解析。
class AdbService {
  AdbService({String? executable})
    : executable = executable ?? resolveToolPath('adb');

  static final RegExp _deviceLinePattern = RegExp(
    r'^(.*?)\s+(device|offline|unauthorized|recovery|sideload|bootloader|host|no permissions)(?:\s+(.*))?$',
  );

  final String executable;

  /// 获取已连接设备列表；adb 不可用时抛出异常。
  Future<List<AdbDevice>> listDevices() async {
    final result = await run(['devices', '-l']);
    if (!result.isSuccess) {
      throw AdbException(result.message);
    }
    return _parseDevices(result.stdout);
  }

  /// 定时轮询 adb，仅在可见设备列表变化时发出新值。
  Stream<List<AdbDevice>> trackDevices({
    Duration interval = const Duration(seconds: 2),
  }) async* {
    yield await listDevices();
    yield* Stream.periodic(
      interval,
    ).asyncMap((_) => listDevices()).distinct(_sameDeviceList);
  }

  /// 使用原始参数执行 adb，并将进程异常转换为 AdbResult。
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Process? process;
    try {
      process = await Process.start(executable, args);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      return AdbResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
      );
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      return AdbResult(
        exitCode: 124,
        stdout: '',
        stderr: 'adb命令超时(${timeout.inSeconds}s): adb ${args.join(' ')}',
      );
    } on ProcessException catch (error) {
      return AdbResult(exitCode: 127, stdout: '', stderr: error.message);
    }
  }

  /// 终止并重新启动 ADB 服务端。
  Future<AdbResult> restartServer() async {
    final killResult = await run(['kill-server']);
    if (!killResult.isSuccess) {
      return killResult;
    }
    return run(['start-server']);
  }

  /// 在指定设备上执行单条 shell 命令字符串。
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return run(['-s', deviceId, 'shell', command], timeout: timeout);
  }

  /// 在指定设备上执行 shell 参数列表，调用方无需手写 adb 前缀。
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return run(['-s', deviceId, 'shell', ...args], timeout: timeout);
  }

  /// 解析 `adb devices -l` 返回的表格文本。
  List<AdbDevice> _parseDevices(String output) {
    return output
        .split('\n')
        .skip(1)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_parseDeviceLine)
        .toList(growable: false);
  }

  /// 解析单行 adb 设备信息，并保留可选的 key:value 属性。
  AdbDevice _parseDeviceLine(String line) {
    final match = _deviceLinePattern.firstMatch(line);
    final id = match?.group(1) ?? line.split(RegExp(r'\s+')).first;
    final status = match?.group(2) ?? 'unknown';
    final attributesText = match?.group(3) ?? '';
    final parts = attributesText.split(RegExp(r'\s+'));
    final attributes = <String, String>{};

    for (final part in parts) {
      final separator = part.indexOf(':');
      if (separator > 0 && separator < part.length - 1) {
        attributes[part.substring(0, separator)] = part.substring(
          separator + 1,
        );
      }
    }

    return AdbDevice(
      id: id,
      status: status,
      model: attributes['model'],
      product: attributes['product'],
      transportId: attributes['transport_id'],
    );
  }

  /// 当 adb 连续返回相同列表时，避免 StreamProvider 重复刷新。
  /// 截取手机屏幕截图，返回 PNG 图像的原始字节。
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Process? process;
    try {
      process = await Process.start(executable, [
        '-s',
        deviceId,
        'exec-out',
        'screencap',
        '-p',
      ]);
      final stdoutFuture = process.stdout.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      final stderr = await stderrFuture;
      if (exitCode != 0) {
        throw AdbException(stderr.isNotEmpty ? stderr : 'Failed to capture screenshot (exit code $exitCode)');
      }
      return Uint8List.fromList(await stdoutFuture);
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      throw AdbException('adb截图命令超时(${timeout.inSeconds}s)');
    } on ProcessException catch (error) {
      throw AdbException(error.message);
    }
  }

  bool _sameDeviceList(List<AdbDevice> previous, List<AdbDevice> next) {
    if (previous.length != next.length) {
      return false;
    }
    for (var index = 0; index < previous.length; index += 1) {
      final left = previous[index];
      final right = next[index];
      if (left.id != right.id ||
          left.status != right.status ||
          left.model != right.model ||
          left.product != right.product) {
        return false;
      }
    }
    return true;
  }
}

/// adb 无法返回有效设备列表时使用的异常。
class AdbException implements Exception {
  const AdbException(this.message);

  final String message;

  @override
  String toString() => message;
}
