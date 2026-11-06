import '../process/command_session.dart';
import '../process/tool_path_resolver.dart';

/// PID 映射是采集的辅助数据，单次查询可取消且不会阻塞实时日志启动。
class LogcatPidResolver {
  LogcatPidResolver({CommandStarter? startProcess})
    : _session = CommandSession(startProcess: startProcess);

  final CommandSession _session;

  Future<Map<String, String>> read(String deviceId, bool isHarmony) async {
    final result = await _session.run(
      resolveToolPath(isHarmony ? 'hdc' : 'adb'),
      isHarmony
          ? ['-t', deviceId, 'shell', 'ps', '-ef']
          : ['-s', deviceId, 'shell', 'ps', '-A', '-o', 'PID,NAME'],
    );
    if (!result.isSuccess) return {};
    final mapping = <String, String>{};
    for (final line in result.stdout.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      final pid = isHarmony && parts.length >= 8 ? parts[1] : parts.first;
      if (!RegExp(r'^\d+$').hasMatch(pid)) continue;
      final name = isHarmony && parts.length >= 8
          ? parts.skip(7).join(' ')
          : parts.skip(1).join(' ');
      if (name.isNotEmpty) mapping[pid] = name;
    }
    return mapping;
  }

  void close() => _session.close();
}
