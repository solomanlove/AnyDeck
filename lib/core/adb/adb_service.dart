import 'dart:async';
import 'dart:io';

import '../process/tool_path_resolver.dart';
import 'adb_device.dart';
import 'adb_result.dart';

class AdbService {
  AdbService({String? executable})
    : executable = executable ?? resolveToolPath('adb');

  final String executable;

  Future<List<AdbDevice>> listDevices() async {
    final result = await run(['devices', '-l']);
    if (!result.isSuccess) {
      throw AdbException(result.message);
    }
    return _parseDevices(result.stdout);
  }

  Stream<List<AdbDevice>> trackDevices({
    Duration interval = const Duration(seconds: 2),
  }) async* {
    yield await listDevices();
    yield* Stream.periodic(
      interval,
    ).asyncMap((_) => listDevices()).distinct(_sameDeviceList);
  }

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

  Future<AdbResult> shell(String deviceId, String command) {
    return run(['-s', deviceId, 'shell', command]);
  }

  Future<AdbResult> shellArgs(String deviceId, List<String> args) {
    return run(['-s', deviceId, 'shell', ...args]);
  }

  List<AdbDevice> _parseDevices(String output) {
    return output
        .split('\n')
        .skip(1)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_parseDeviceLine)
        .toList(growable: false);
  }

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

class AdbException implements Exception {
  const AdbException(this.message);

  final String message;

  @override
  String toString() => message;
}
