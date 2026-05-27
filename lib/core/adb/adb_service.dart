import 'dart:async';
import 'dart:io';

import '../process/tool_path_resolver.dart';
import 'adb_device.dart';
import 'adb_result.dart';

/// adb 薄封装，集中处理进程执行和设备列表解析。
class AdbService {
  AdbService({String? executable})
    : executable = executable ?? resolveToolPath('adb');

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
  Future<AdbResult> run(List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      return AdbResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } on ProcessException catch (error) {
      return AdbResult(exitCode: 127, stdout: '', stderr: error.message);
    }
  }

  /// 在指定设备上执行单条 shell 命令字符串。
  Future<AdbResult> shell(String deviceId, String command) {
    return run(['-s', deviceId, 'shell', command]);
  }

  /// 在指定设备上执行 shell 参数列表，调用方无需手写 adb 前缀。
  Future<AdbResult> shellArgs(String deviceId, List<String> args) {
    return run(['-s', deviceId, 'shell', ...args]);
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
    final parts = line.split(RegExp(r'\s+'));
    final attributes = <String, String>{};

    for (final part in parts.skip(2)) {
      final separator = part.indexOf(':');
      if (separator > 0 && separator < part.length - 1) {
        attributes[part.substring(0, separator)] = part.substring(
          separator + 1,
        );
      }
    }

    return AdbDevice(
      id: parts.first,
      status: parts.length > 1 ? parts[1] : 'unknown',
      model: attributes['model'],
      product: attributes['product'],
      transportId: attributes['transport_id'],
    );
  }

  /// 当 adb 连续返回相同列表时，避免 StreamProvider 重复刷新。
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
