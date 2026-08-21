import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../adb/adb_device.dart';
import '../adb/adb_result.dart';
import '../process/tool_path_resolver.dart';

/// HDC (HarmonyOS Device Connector) 服务封装，提供与纯血鸿蒙设备的通信指令。
class HdcService {
  HdcService({
    String? executable,
    void Function(String message, {String tag, String level})? onLog,
  })  : executable = executable ?? resolveToolPath('hdc'),
        _onLog = onLog;

  final String executable;
  final void Function(String message, {String tag, String level})? _onLog;

  /// 获取已连接的鸿蒙设备列表。
  Future<List<AdbDevice>> listDevices() async {
    final result = await run(['list', 'targets']);
    if (!result.isSuccess) {
      return [];
    }
    return _parseDevices(result.stdout);
  }

  /// 封装的通用 hdc 命令执行。
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cmdStr = 'hdc ${args.join(' ')}';
    _onLog?.call(cmdStr, tag: 'hdc', level: 'I');
    Process? process;
    try {
      process = await Process.start(executable, args);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      final result = AdbResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
      );
      if (!result.isSuccess && result.stderr.isNotEmpty) {
        _onLog?.call('Command failed: ${result.stderr.trim()}', tag: 'hdc', level: 'E');
      }
      return result;
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      final errorMsg = 'hdc 命令超时(${timeout.inSeconds}s): $cmdStr';
      _onLog?.call(errorMsg, tag: 'hdc', level: 'E');
      return AdbResult(
        exitCode: 124,
        stdout: '',
        stderr: errorMsg,
      );
    } on ProcessException catch (error) {
      _onLog?.call('Process error: ${error.message}', tag: 'hdc', level: 'E');
      return AdbResult(exitCode: 127, stdout: '', stderr: error.message);
    }
  }

  /// 在指定设备上执行单条 shell 命令。
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return run(['-t', deviceId, 'shell', command], timeout: timeout);
  }

  /// 解析 `hdc list targets` 输出的设备列表。
  List<AdbDevice> _parseDevices(String output) {
    final devices = <AdbDevice>[];
    final lines = LineSplitter.split(output);
    for (final line in lines) {
      final trimmed = line.trim();
      // 过滤空白行和异常提示行（例如 "[Empty]" 或错误输出）
      if (trimmed.isEmpty || trimmed.contains('[Empty]') || trimmed.startsWith('[') || trimmed.contains(' ')) {
        continue;
      }
      // 鸿蒙 NEXT 的 hdc 默认直接输出设备的 UDID/ID
      devices.add(AdbDevice(
        id: trimmed,
        status: 'device',
        model: 'HarmonyOS NEXT Device ($trimmed)',
        product: 'HarmonyOS NEXT',
        transportId: '',
        isHarmony: true,
      ));
    }
    return devices;
  }
}
