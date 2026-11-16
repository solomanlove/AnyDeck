import 'dart:convert';
import 'dart:io';

import '../process/tool_path_resolver.dart';
import 'scrcpy_launch_options.dart';
import 'scrcpy_session.dart';

/// 启停 scrcpy 进程，并通过生成的 session id 跟踪。
class ScrcpyService {
  ScrcpyService({String? executable})
    : _executable = executable;

  final String? _executable;
  /// 路径设置只影响后续启动的命令，不中断已有进程或会话。
  String get executable => _executable ?? resolveToolPath('scrcpy');
  final Map<String, Process> _processes = {};

  /// 为设备启动 scrcpy，并记录进程用于后续清理。
  Future<ScrcpySession> start({
    required String deviceId,
    ScrcpyLaunchOptions options = const ScrcpyLaunchOptions(),
    String? adbPath,
    void Function(int exitCode)? onExit,
  }) async {
    final process = await Process.start(
      executable,
      options.toArgs(deviceId),
      // 外部 scrcpy 会自行查找 ADB，必须显式传递当前配置，避免回到 PATH 旧版本。
      environment: {'ADB': adbPath ?? resolveToolPath('adb')},
    );

    // 转发标准输出与标准错误输出，便于调试定位运行问题
    process.stdout.transform(utf8.decoder).listen((data) {
      stdout.write('[scrcpy stdout] $data');
    });
    process.stderr.transform(utf8.decoder).listen((data) {
      stderr.write('[scrcpy stderr] $data');
    });

    final session = ScrcpySession(
      id: '${deviceId}_${DateTime.now().microsecondsSinceEpoch}',
      deviceId: deviceId,
      pid: process.pid,
      startedAt: DateTime.now(),
    );
    _processes[session.id] = process;
    process.exitCode.whenComplete(() {
      _processes.remove(session.id);
    });
    if (onExit != null) {
      process.exitCode.then(onExit);
    }
    return session;
  }

  /// 查询特定 session id 的进程是否仍在运行。
  bool isRunning(String sessionId) => _processes.containsKey(sessionId);

  /// 按 session id 停止单个已跟踪的 scrcpy 进程。
  Future<void> stop(String sessionId) async {
    _processes.remove(sessionId)?.kill();
  }

  /// 停止所有已跟踪进程，通常在 provider 销毁时调用。
  Future<void> stopAll() async {
    for (final process in _processes.values) {
      process.kill();
    }
    _processes.clear();
  }
}
