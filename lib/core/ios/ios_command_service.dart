import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../adb/adb_result.dart';
import 'ios_control_gateway.dart';
import '../process/tool_path_resolver.dart';
import 'ios_app_info.dart';
import 'ios_process_info.dart';
import 'ios_process_parser.dart';
import 'ios_screenshot_capture.dart';

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
  late final _screenshotCapture = IosScreenshotCapture(run);

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
      final effectiveExitCode = exitCode == 0 &&
              (_containsFatalLog(stdout) || _containsFatalLog(stderr))
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
    final processes = parseProcesses(result.stdout);
    if (processes.isEmpty) return processes;
    // 应用元数据失败时保留原始进程，避免把补充信息失败当作进程查询失败。
    try {
      return IosProcessParser.associate(processes, await listApps(udid));
    } catch (error) {
      _onLog?.call('iOS 进程关联应用信息失败: $error', tag: 'ios', level: 'W');
      return processes;
    }
  }

  Future<AdbResult> killProcess(String udid, int pid) {
    return run(['kill', '--pid=$pid', '--udid=$udid']);
  }

  Future<Uint8List> captureScreenshot(String udid) {
    return _screenshotCapture.capture(udid);
  }

  /// 控制统一路由到主引擎，禁止隐式回退到另一个设备或控制后端。
  Future<AdbResult> _control(String udid, String action, [Map<String, dynamic> args = const {}]) async {
    try {
      final value = await IosControlGateway.call(udid, action, args);
      return AdbResult(exitCode: 0, stdout: jsonEncode(value), stderr: '');
    } catch (error) {
      return AdbResult(exitCode: 1, stdout: '', stderr: error.toString());
    }
  }

  Future<AdbResult> automationStatus(String udid) => _control(udid, 'status');
  Future<AdbResult> automationSource(String udid) => _control(udid, 'source');
  Future<AdbResult> tap(String udid, double x, double y) => _control(udid, 'tap', {'x': x, 'y': y});
  Future<AdbResult> swipe(String udid, {required double fromX, required double fromY,
    required double toX, required double toY}) => _control(udid, 'swipe', {
      'fromX': fromX, 'fromY': fromY, 'toX': toX, 'toY': toY,
    });
  Future<AdbResult> typeText(String udid, String text) => _control(udid, 'text', {'text': text});
  Future<AdbResult> pressButton(String udid, String button) => _control(udid, 'button', {'name': button});

  static List<IosAppInfo> parseApps(String output) {
    final apps = <String, IosAppInfo>{};
    // 找到应用对象即停止递归，避免把 Entitlements 等嵌套元数据误认作应用。
    void collect(Object? value, [String? fallbackId]) {
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is! Map) return;
      final map = value;
      final explicitId = _firstString(map, const [
        'CFBundleIdentifier',
        'bundleIdentifier',
        'BundleIdentifier',
        'bundleId',
      ]);
      final hasAppMetadata =
          map.containsKey('ApplicationType') ||
          map.containsKey('CFBundleName') ||
          map.containsKey('CFBundleDisplayName') ||
          map.containsKey('CFBundleVersion') ||
          map.containsKey('CFBundleShortVersionString');
      final bundleId = explicitId ?? (hasAppMetadata ? fallbackId : null);
      if (bundleId != null && bundleId.contains('.')) {
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
          path: _firstString(map, const ['Path', 'path']),
        );
        return;
      }
      if (map.containsKey('level') &&
          (map.containsKey('msg') || map.containsKey('message'))) {
        return;
      }
      for (final entry in map.entries) {
        collect(entry.value, entry.key.toString());
      }
    }
    for (final payload in _jsonPayloads(output)) {
      collect(payload);
    }
    final result = apps.values.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static List<IosProcessInfo> parseProcesses(String output) {
    return IosProcessParser.parse(output);
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
