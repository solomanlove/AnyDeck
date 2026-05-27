import 'dart:io';

import '../process/tool_path_resolver.dart';
import 'scrcpy_launch_options.dart';
import 'scrcpy_session.dart';

class ScrcpyService {
  ScrcpyService({String? executable})
    : executable = executable ?? resolveToolPath('scrcpy');

  final String executable;
  final Map<String, Process> _processes = {};

  Future<ScrcpySession> start({
    required String deviceId,
    ScrcpyLaunchOptions options = const ScrcpyLaunchOptions(),
  }) async {
    final process = await Process.start(executable, options.toArgs(deviceId));
    final session = ScrcpySession(
      id: '${deviceId}_${DateTime.now().microsecondsSinceEpoch}',
      deviceId: deviceId,
      pid: process.pid,
      startedAt: DateTime.now(),
    );
    _processes[session.id] = process;
    process.exitCode.whenComplete(() => _processes.remove(session.id));
    return session;
  }

  Future<void> stop(String sessionId) async {
    _processes.remove(sessionId)?.kill();
  }

  Future<void> stopAll() async {
    for (final process in _processes.values) {
      process.kill();
    }
    _processes.clear();
  }
}
