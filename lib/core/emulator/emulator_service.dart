import 'dart:async';
import 'dart:io';

import '../process/tool_path_resolver.dart';

/// 模拟器管理服务，封装 AVD 列表读取和后台启动。
class EmulatorService {
  EmulatorService({String? executable})
      : executable = executable ?? resolveToolPath('emulator');

  final String executable;

  /// 获取本地所有 AVD 模拟器名称列表。
  Future<List<String>> listEmulators() async {
    try {
      final result = await Process.run(executable, ['-list-avds']);
      if (result.exitCode != 0) {
        return [];
      }
      return result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 后台启动指定的 AVD 模拟器（使用 ProcessStartMode.detached 运行）。
  Future<bool> startEmulator(String avdName) async {
    try {
      await Process.start(
        executable,
        ['-avd', avdName],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
