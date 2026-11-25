import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../process/bounded_process.dart';
import 'ios_simulator.dart';

/// 带超时的模拟器 CLI 命令执行入口。
typedef IosSimulatorCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required Duration timeout,
});

/// 通过 `xcrun simctl` 管理设备，并打开对应的 macOS 模拟器窗口。
class IosSimulatorService {
  const IosSimulatorService({
    IosSimulatorCommandRunner runProcess = runBoundedProcess,
  }) : _runProcess = runProcess;

  final IosSimulatorCommandRunner _runProcess;

  /// 检查当前系统环境是否支持 iOS 模拟器管理（仅在 macOS 下有效）
  bool get isSupported => Platform.isMacOS;

  /// 只查询已启动实例，避免侧栏定期加载完整的模拟器配置列表。
  Future<int> countBootedSimulators() async {
    if (!isSupported) return 0;
    try {
      final result = await runBoundedProcess('xcrun', [
        'simctl',
        'list',
        '--json',
        'devices',
        'booted',
      ]);
      if (result.exitCode != 0) return 0;
      final json = jsonDecode(result.stdout as String);
      if (json is! Map<String, dynamic>) return 0;
      final devices = json['devices'];
      if (devices is! Map<String, dynamic>) return 0;
      return devices.values
          .whereType<List<dynamic>>()
          .expand((group) => group.whereType<Map<String, dynamic>>())
          .where((device) => device['state'] == 'Booted')
          .length;
    } on Exception {
      return 0;
    }
  }

  /// 读取本地所有可用的 iOS 模拟器列表
  Future<List<IosSimulator>> fetchSimulators() async {
    if (!Platform.isMacOS) {
      return const [];
    }

    try {
      final result = await Process.run(
        'xcrun',
        ['simctl', 'list', '--json', 'devices', 'available'],
      );

      if (result.exitCode != 0) {
        debugPrint('simctl list failed with exit code ${result.exitCode}: ${result.stderr}');
        return const [];
      }

      final jsonStr = result.stdout as String;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final devicesMap = data['devices'] as Map<String, dynamic>? ?? {};

      final List<IosSimulator> list = [];
      devicesMap.forEach((runtimeKey, deviceList) {
        if (deviceList is! List) return;
        final cleanRuntime = _formatRuntimeKey(runtimeKey);
        for (final item in deviceList) {
          if (item is Map<String, dynamic>) {
            final sim = IosSimulator.fromJson(item, runtime: cleanRuntime);
            list.add(sim);
          }
        }
      });

      // 排序：已启动 (Booted) 模拟器排在最前，其余按名称字母升序
      list.sort((a, b) {
        if (a.isBooted && !b.isBooted) return -1;
        if (!a.isBooted && b.isBooted) return 1;
        return a.name.compareTo(b.name);
      });

      return list;
    } catch (e, stack) {
      debugPrint('Error fetching iOS simulators: $e\n$stack');
      return const [];
    }
  }

  /// 等待设备就绪后再打开窗口，避免 Device Hub 收到请求时设备仍在启动。
  Future<bool> bootSimulator(String udid) async {
    if (!isSupported) return false;
    final result = await _runSimulatorCommand('xcrun', [
      'simctl',
      'bootstatus',
      udid,
      '-b',
    ], timeout: const Duration(minutes: 2));
    return result != null && await showSimulatorWindow(udid);
  }

  /// 显示已运行设备的桌面窗口，保留设备当前会话。
  Future<bool> showSimulatorWindow(String udid) => _openSimulatorApp(udid);

  /// 关闭指定的 iOS 模拟器
  Future<bool> shutdownSimulator(String udid) async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await Process.run('xcrun', ['simctl', 'shutdown', udid]);
      return res.exitCode == 0;
    } catch (e) {
      debugPrint('Failed to shutdown iOS simulator $udid: $e');
      return false;
    }
  }

  /// 抹掉模拟器所有内容与设置（Erase）
  Future<bool> eraseSimulator(String udid) async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await Process.run('xcrun', ['simctl', 'erase', udid]);
      return res.exitCode == 0;
    } catch (e) {
      debugPrint('Failed to erase iOS simulator $udid: $e');
      return false;
    }
  }

  /// 打开当前 Xcode 对应的模拟器管理应用。
  Future<bool> openSimulatorApp() => _openSimulatorApp(null);

  Future<bool> _openSimulatorApp(String? udid) async {
    if (!isSupported) return false;
    // 与 simctl 使用同一套 Xcode，兼容 DEVELOPER_DIR 和多版本安装。
    final result = await _runSimulatorCommand('xcrun', ['--find', 'simctl']);
    if (result == null) return false;
    final simctlPath = (result.stdout as String).trim();
    if (!simctlPath.startsWith('/')) return false;
    final developer = File(simctlPath).parent.parent.parent;
    final deviceHub = '${developer.parent.path}/Applications/DeviceHub.app';
    final simulator = '${developer.path}/Applications/Simulator.app';
    final List<String> args;
    if (await Directory(deviceHub).exists()) {
      // Xcode 27 通过 Device Hub 的 URL Scheme 定位设备窗口。
      args = [
        '-a',
        deviceHub,
        if (udid != null)
          Uri(
            scheme: 'devices',
            host: 'device',
            path: '/open',
            queryParameters: {'id': udid},
          ).toString(),
      ];
    } else if (await Directory(simulator).exists()) {
      args = [
        '-a',
        simulator,
        if (udid != null) ...['--args', '-CurrentDeviceUDID', udid],
      ];
    } else {
      debugPrint('No simulator window app under ${developer.parent.path}');
      return false;
    }
    return await _runSimulatorCommand('/usr/bin/open', args) != null;
  }

  /// 捕获命令退出和超时，供调用方反馈启动或窗口打开失败。
  Future<ProcessResult?> _runSimulatorCommand(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final result = await _runProcess(executable, arguments, timeout: timeout);
      if (result.exitCode == 0) return result;
      debugPrint('$executable ${arguments.first} failed: ${result.stderr}');
    } on Exception catch (e) {
      debugPrint('$executable ${arguments.first} failed: $e');
    }
    return null;
  }

  /// 在 Finder 中打开模拟器的数据沙盒目录
  Future<void> openDataFolder(String dataPath) async {
    if (!Platform.isMacOS) return;
    try {
      await Process.run('open', [dataPath]);
    } catch (e) {
      debugPrint('Failed to open data folder: $e');
    }
  }

  /// 将形如 "com.apple.CoreSimulator.SimRuntime.iOS-26-3" 转为可读性更好的 "iOS 26.3"
  String _formatRuntimeKey(String rawKey) {
    var key = rawKey.replaceFirst('com.apple.CoreSimulator.SimRuntime.', '');
    if (key.startsWith('iOS-')) {
      final versionPart = key.substring(4).replaceAll('-', '.');
      return 'iOS $versionPart';
    } else if (key.startsWith('watchOS-')) {
      final versionPart = key.substring(8).replaceAll('-', '.');
      return 'watchOS $versionPart';
    } else if (key.startsWith('tvOS-')) {
      final versionPart = key.substring(5).replaceAll('-', '.');
      return 'tvOS $versionPart';
    } else if (key.startsWith('xrOS-')) {
      final versionPart = key.substring(5).replaceAll('-', '.');
      return 'visionOS $versionPart';
    }
    return key;
  }
}
