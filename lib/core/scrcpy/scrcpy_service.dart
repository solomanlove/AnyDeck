import 'dart:convert';
import 'dart:io';

import '../process/tool_path_resolver.dart';
import 'scrcpy_launch_options.dart';
import 'scrcpy_session.dart';

/// 启停 scrcpy 进程，并通过生成的 session id 跟踪。
class ScrcpyService {
  ScrcpyService({String? executable})
    : executable = executable ?? resolveToolPath('scrcpy');

  final String executable;
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
      environment: adbPath != null ? {'ADB': adbPath} : null,
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

  /// 启动 scrcpy 的电脑本地录制进程（无窗口，直接录制到本地文件）。
  Future<Process> startRecording({
    required String deviceId,
    required String localSavePath,
  }) async {
    final process = await Process.start(
      executable,
      [
        '-s',
        deviceId,
        '--no-window',
        '--record',
        localSavePath,
        // 使用 AAC 音频编码，确保录制出的 MP4 文件在 macOS QuickTime Player 等播放器中能正常播放音频
        '--audio-codec=aac',
      ],
    );
    return process;
  }

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
