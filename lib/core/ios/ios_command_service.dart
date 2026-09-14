import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../adb/adb_result.dart';
import '../dal/rust_dal_bridge.dart';
import '../process/tool_path_resolver.dart';
import 'ios_app_info.dart';
import 'ios_process_info.dart';

/// 统一封装 go-ios 的短命令、持续流和 JSON 解析。
class IosCommandService {
  IosCommandService({
    String? executable,
    void Function(String message, {String tag, String level})? onLog,
  }) : executable = executable ?? _resolveBinary(),
       _onLog = onLog;

  static const _defaultTimeout = Duration(seconds: 15);
  static const _transferTimeout = Duration(minutes: 5);

  final String executable;
  final void Function(String message, {String tag, String level})? _onLog;

  static String _resolveBinary() {
    final ios = resolveToolPath('ios');
    if (ios != 'ios' && File(ios).existsSync()) return ios;
    final goIos = resolveToolPath('go-ios');
    if (goIos != 'go-ios' && File(goIos).existsSync()) return goIos;
    return 'ios';
  }

  /// 执行一次性命令，参数始终以列表传递，避免 shell 注入。
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = _defaultTimeout,
  }) async {
    _onLog?.call('ios ${_displayArgs(args)}', tag: 'ios', level: 'I');
    Process? process;
    try {
      process = await Process.start(executable, args);
      final stdoutFuture = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final stderrFuture = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final exitCode = await process.exitCode.timeout(timeout);
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      final effectiveExitCode = exitCode == 0 && _containsFatalLog(stdout)
          ? 1
          : exitCode;
      final result = AdbResult(
        exitCode: effectiveExitCode,
        stdout: stdout,
        stderr: stderr,
      );
      if (!result.isSuccess) {
        _onLog?.call(
          'go-ios 命令失败: ${result.message.trim()}',
          tag: 'ios',
          level: 'E',
        );
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
      return AdbResult(
        exitCode: 124,
        stdout: '',
        stderr: 'go-ios 命令超时(${timeout.inSeconds}s)',
      );
    } on ProcessException catch (error) {
      return AdbResult(exitCode: 127, stdout: '', stderr: error.message);
    }
  }

  /// 启动需要由页面持有并回收的持续输出命令。
  Future<Process> start(List<String> args) {
    _onLog?.call('ios ${_displayArgs(args)}', tag: 'ios', level: 'I');
    return Process.start(executable, args);
  }

  Future<List<IosAppInfo>> listApps(String udid) async {
    final result = await run(['apps', '--all', '--udid=$udid']);
    if (!result.isSuccess) throw Exception(result.message);
    return parseApps(result.stdout);
  }

  Future<AdbResult> installApp(String udid, String localPath) {
    return run([
      'install',
      '--path=$localPath',
      '--udid=$udid',
    ], timeout: _transferTimeout);
  }

  Future<AdbResult> uninstallApp(String udid, String bundleId) {
    return run(['uninstall', bundleId, '--udid=$udid']);
  }

  Future<AdbResult> listFiles(
    String udid, {
    required String bundleId,
    required String remotePath,
  }) {
    return run([
      'fsync',
      '--app=$bundleId',
      'tree',
      '--path=$remotePath',
      '--udid=$udid',
    ]);
  }

  Future<AdbResult> pushFile(
    String udid, {
    required String bundleId,
    required String localPath,
    required String remotePath,
  }) {
    return run([
      'fsync',
      '--app=$bundleId',
      'push',
      '--srcPath=$localPath',
      '--dstPath=$remotePath',
      '--udid=$udid',
    ], timeout: _transferTimeout);
  }

  Future<AdbResult> pullFile(
    String udid, {
    required String bundleId,
    required String remotePath,
    required String localPath,
  }) {
    return run([
      'fsync',
      '--app=$bundleId',
      'pull',
      '--srcPath=$remotePath',
      '--dstPath=$localPath',
      '--udid=$udid',
    ], timeout: _transferTimeout);
  }

  Future<Process> startSyslog(String udid) {
    return start(['syslog', '--parse', '--udid=$udid']);
  }

  Future<List<IosProcessInfo>> listProcesses(String udid) async {
    final result = await run(['ps', '--apps', '--udid=$udid']);
    if (!result.isSuccess) throw Exception(result.message);
    return parseProcesses(result.stdout);
  }

  Future<AdbResult> killProcess(String udid, int pid) {
    return run(['kill', '--pid=$pid', '--udid=$udid']);
  }

  Future<Uint8List> captureScreenshot(String udid) async {
    final directory = await Directory.systemTemp.createTemp('anydeck_ios_');
    final file = File('${directory.path}/screenshot.png');
    try {
      final result = await run([
        'screenshot',
        '--output=${file.path}',
        '--udid=$udid',
      ]);
      if (!result.isSuccess) throw Exception(result.message);
      if (!await file.exists()) throw Exception('go-ios 未生成截图文件');
      return await file.readAsBytes();
    } finally {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<AdbResult> automationStatus(String udid, {int wdaPort = 8100}) async {
    if (RustDalBridge.instance.isAvailable) {
      try {
        final res = await RustDalBridge.instance.wdaRequest(
          port: wdaPort,
          endpoint: '/status',
          method: 'GET',
        );
        if (res['success'] == true) {
          return AdbResult(
            exitCode: 0,
            stdout: jsonEncode(res['payload']),
            stderr: '',
          );
        }
      } catch (_) {}
    }
    return run(['ui', 'status', '--driver=wda', '--udid=$udid']);
  }

  Future<AdbResult> automationSource(String udid) {
    return run(['ui', 'source', '--driver=wda', '--udid=$udid']);
  }

  Future<AdbResult> tap(String udid, double x, double y, {int wdaPort = 8100}) async {
    if (RustDalBridge.instance.isAvailable) {
      try {
        final res = await RustDalBridge.instance.wdaRequest(
          port: wdaPort,
          endpoint: '/wda/tap/nil',
          method: 'POST',
          bodyJson: jsonEncode({'x': x.round(), 'y': y.round()}),
        );
        if (res['success'] == true) {
          return const AdbResult(exitCode: 0, stdout: 'OK', stderr: '');
        }
      } catch (_) {}
    }
    return run([
      'ui',
      'tap',
      '--x=$x',
      '--y=$y',
      '--driver=wda',
      '--udid=$udid',
    ]);
  }

  Future<AdbResult> swipe(
    String udid, {
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
  }) {
    return run([
      'ui',
      'swipe',
      '--from-x=$fromX',
      '--from-y=$fromY',
      '--to-x=$toX',
      '--to-y=$toY',
      '--driver=wda',
      '--udid=$udid',
    ]);
  }

  Future<AdbResult> typeText(String udid, String text, {int wdaPort = 8100}) async {
    if (RustDalBridge.instance.isAvailable) {
      try {
        final res = await RustDalBridge.instance.wdaRequest(
          port: wdaPort,
          endpoint: '/wda/keys',
          method: 'POST',
          bodyJson: jsonEncode({'value': text.split('')}),
        );
        if (res['success'] == true) {
          return const AdbResult(exitCode: 0, stdout: 'OK', stderr: '');
        }
      } catch (_) {}
    }
    return run(['ui', 'type', '--text=$text', '--driver=wda', '--udid=$udid']);
  }

  Future<AdbResult> pressButton(String udid, String button, {int wdaPort = 8100}) async {
    if (RustDalBridge.instance.isAvailable) {
      try {
        final isHome = button.toLowerCase() == 'home';
        final endpoint = isHome ? '/wda/homescreen' : '/wda/pressButton';
        final bodyJson = isHome ? null : jsonEncode({'name': button});
        final res = await RustDalBridge.instance.wdaRequest(
          port: wdaPort,
          endpoint: endpoint,
          method: 'POST',
          bodyJson: bodyJson,
        );
        if (res['success'] == true) {
          return const AdbResult(exitCode: 0, stdout: 'OK', stderr: '');
        }
      } catch (_) {}
    }
    return run(['ui', 'button', button, '--driver=wda', '--udid=$udid']);
  }

  static List<IosAppInfo> parseApps(String output) {
    final apps = <String, IosAppInfo>{};
    for (final payload in _jsonPayloads(output)) {
      _walkMaps(payload, (map, fallbackKey) {
        final bundleId =
            _firstString(map, const [
              'CFBundleIdentifier',
              'bundleIdentifier',
              'BundleIdentifier',
              'bundleId',
            ]) ??
            fallbackKey;
        if (bundleId == null || !bundleId.contains('.')) return;
        final name =
            _firstString(map, const [
              'CFBundleDisplayName',
              'CFBundleName',
              'displayName',
              'name',
            ]) ??
            bundleId;
        final version = _firstString(map, const [
          'CFBundleShortVersionString',
          'CFBundleVersion',
          'version',
        ]);
        final appType = _firstString(map, const ['ApplicationType', 'type']);
        apps[bundleId] = IosAppInfo(
          bundleId: bundleId,
          name: name,
          version: version,
          system: appType?.toLowerCase() == 'system',
        );
      });
    }
    final result = apps.values.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static List<IosProcessInfo> parseProcesses(String output) {
    final processes = <int, IosProcessInfo>{};
    for (final payload in _jsonPayloads(output)) {
      if (payload is Map) {
        for (final entry in payload.entries) {
          final pid = entry.value is int
              ? entry.value as int
              : int.tryParse(entry.value?.toString() ?? '');
          if (pid != null) {
            processes[pid] = IosProcessInfo(
              pid: pid,
              name: entry.key.toString(),
            );
          }
        }
      }
      _walkMaps(payload, (map, fallbackKey) {
        final pidValue =
            map['pid'] ??
            map['Pid'] ??
            map['PID'] ??
            map['ProcessIdentifier'] ??
            (fallbackKey == null ? null : int.tryParse(fallbackKey));
        final pid = pidValue is int
            ? pidValue
            : int.tryParse(pidValue?.toString() ?? '');
        if (pid == null) return;
        final name =
            _firstString(map, const [
              'name',
              'processName',
              'ExecutableName',
              'bundleIdentifier',
            ]) ??
            map['value']?.toString() ??
            fallbackKey ??
            'PID $pid';
        processes[pid] = IosProcessInfo(pid: pid, name: name);
      });
    }
    final result = processes.values.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static bool _containsFatalLog(String output) {
    for (final line in const LineSplitter().convert(output)) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final level = decoded['level']?.toString().toLowerCase();
        if (level == 'error' || level == 'fatal') return true;
      } catch (_) {}
    }
    return false;
  }

  static Iterable<Object?> _jsonPayloads(String output) sync* {
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map && decoded.containsKey('level')) continue;
        yield decoded;
      } catch (_) {}
    }
  }

  static void _walkMaps(
    Object? value,
    void Function(Map<Object?, Object?> map, String? fallbackKey) visit, {
    String? fallbackKey,
  }) {
    if (value is Map) {
      visit(value, fallbackKey);
      for (final entry in value.entries) {
        _walkMaps(entry.value, visit, fallbackKey: entry.key.toString());
      }
    } else if (value is List) {
      for (final item in value) {
        _walkMaps(item, visit);
      }
    }
  }

  static String? _firstString(Map<Object?, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String _displayArgs(List<String> args) {
    return args
        .map((arg) => arg.startsWith('--text=') ? '--text=<redacted>' : arg)
        .join(' ');
  }
}
