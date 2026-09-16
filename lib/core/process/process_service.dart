import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import '../harmony/hdc_service.dart';

/// 表示 Android 设备上的一个运行进程。
class AdbProcess {
  final String pid;
  final String user;
  final String cpu;
  final String memory;
  final String cpuTime;
  final String name;

  AdbProcess({
    required this.pid,
    required this.user,
    required this.cpu,
    required this.memory,
    required this.cpuTime,
    required this.name,
  });

  @override
  String toString() {
    return 'AdbProcess(pid: $pid, user: $user, cpu: $cpu, memory: $memory, cpuTime: $cpuTime, name: $name)';
  }
}

/// 基于 ADB shell top 命令提供进程查看与管理能力。
class ProcessService {
  final AdbService _adb;
  final HdcService? _hdc;

  ProcessService(this._adb, [this._hdc]);

  /// 获取设备上当前运行的所有进程。鸿蒙走 `ps -ef`，安卓走 `top -b -n 1`。
  Future<List<AdbProcess>> getProcesses(
    String deviceId, {
    bool isHarmony = false,
  }) async {
    if (isHarmony && _hdc != null) {
      final result = await _hdc.shell(deviceId, 'ps -ef');
      if (!result.isSuccess) {
        throw Exception(result.message);
      }
      return parseHarmonyPsOutput(result.stdout);
    }
    final result = await _adb.shellArgs(deviceId, ['top', '-b', '-n', '1']);
    if (!result.isSuccess) {
      throw Exception(result.message);
    }
    return parseTopOutput(result.stdout);
  }

  /// 结束设备上指定 PID 的进程。
  /// 如果提供了 [processName] 且看起来像应用包名，会优先使用 `am force-stop`/`aa force-stop` 结束应用，
  /// 从而解决非 Root 设备上由于权限问题导致 `kill -9` 报 "Operation not permitted" 的错误。
  Future<AdbResult> killProcess(
    String deviceId,
    String pid, {
    String? processName,
    bool isHarmony = false,
  }) async {
    if (processName != null) {
      final cleanName = processName.trim();
      final basePackage = cleanName.contains(':')
          ? cleanName.split(':').first
          : cleanName;

      // 匹配典型的应用包名格式 (例如 com.example.app)
      final packageRegex = RegExp(
        r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
      );
      if (packageRegex.hasMatch(basePackage) &&
          !cleanName.startsWith('/') &&
          !cleanName.startsWith('[')) {
        if (isHarmony && _hdc != null) {
          // 鸿蒙使用 aa force-stop -b <bundle> 结束应用
          final stopResult = await _hdc.shell(
            deviceId,
            'aa force-stop -b "$basePackage"',
          );
          if (stopResult.isSuccess) {
            return stopResult;
          }
        } else {
          // 安卓使用 am force-stop
          final stopResult = await _adb.shellArgs(
            deviceId,
            ['am', 'force-stop', basePackage],
          );
          if (stopResult.isSuccess) {
            return stopResult;
          }
        }
      }
    }

    // 回退到常规的 kill -9 命令
    if (isHarmony && _hdc != null) {
      return _hdc.shell(deviceId, 'kill -9 $pid');
    }
    return _adb.shellArgs(deviceId, ['kill', '-9', pid]);
  }

  /// 解析鸿蒙 `ps -ef` 输出为进程列表。
  /// 格式：`UID PID PPID C STIME TTY TIME CMD`，无 CPU% 与内存信息。
  List<AdbProcess> parseHarmonyPsOutput(String stdout) {
    final lines = stdout.split('\n');
    final processes = <AdbProcess>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('UID')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 8) continue;
      final uid = parts[0];
      final pid = parts[1];
      if (int.tryParse(pid) == null) continue;
      final time = parts[6];
      final name = parts.sublist(7).join(' ');
      processes.add(
        AdbProcess(
          pid: pid,
          user: uid,
          cpu: '',
          memory: '',
          cpuTime: time,
          name: name,
        ),
      );
    }
    return processes;
  }

  /// 将 `top -b -n 1` 的文本输出解析为进程列表。
  List<AdbProcess> parseTopOutput(String stdout) {
    final lines = stdout.split('\n');
    final processes = <AdbProcess>[];

    int headerIndex = -1;
    final List<String> headers = [];

    // 寻找表头行
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('PID') &&
          (line.contains('ARGS') ||
              line.contains('NAME') ||
              line.contains('CMD') ||
              line.contains('COMMAND'))) {
        headerIndex = i;
        final rawTokens = line.trim().split(RegExp(r'\s+'));
        for (final token in rawTokens) {
          if (token == 'S[%CPU]') {
            headers.add('S');
            headers.add('%CPU');
          } else {
            headers.add(token);
          }
        }
        break;
      }
    }

    if (headerIndex == -1 || headers.isEmpty) {
      return [];
    }

    final pidIdx = headers.indexOf('PID');
    final userIdx = headers.indexOf('USER');

    int memIdx = headers.indexOf('RES');
    if (memIdx == -1) memIdx = headers.indexOf('RSS');
    if (memIdx == -1) memIdx = headers.indexOf('VIRT');
    if (memIdx == -1) memIdx = headers.indexOf('VSZ');

    final cpuIdx = headers.indexWhere((t) => t.contains('CPU'));
    final timeIdx = headers.indexWhere((t) => t.contains('TIME'));
    final argsIdx = headers.indexWhere(
      (t) => t == 'ARGS' || t == 'NAME' || t == 'CMD' || t == 'COMMAND',
    );

    if (pidIdx == -1 ||
        userIdx == -1 ||
        memIdx == -1 ||
        cpuIdx == -1 ||
        timeIdx == -1 ||
        argsIdx == -1) {
      return [];
    }

    for (int i = headerIndex + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length <= argsIdx) continue;

      final pid = parts[pidIdx];
      // 过滤非数字 PID 行（例如空行或其它不规则输出）
      if (int.tryParse(pid) == null) continue;

      final user = parts[userIdx];
      final cpu = parts[cpuIdx];
      final mem = parts[memIdx];
      final time = parts[timeIdx];
      final name = parts.sublist(argsIdx).join(' ');

      processes.add(
        AdbProcess(
          pid: pid,
          user: user,
          cpu: cpu,
          memory: mem,
          cpuTime: time,
          name: name,
        ),
      );
    }
    return processes;
  }
}
