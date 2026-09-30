import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'ios_simulator.dart';

/// iOS 模拟器服务接口，负责与 macOS 系统的 `xcrun simctl` 及 Simulator.app 交互。
class IosSimulatorService {
  const IosSimulatorService();

  /// 检查当前系统环境是否支持 iOS 模拟器管理（仅在 macOS 下有效）
  bool get isSupported => Platform.isMacOS;

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

  /// 启动指定的 iOS 模拟器并唤起 Simulator 桌面窗口
  Future<bool> bootSimulator(String udid) async {
    if (!Platform.isMacOS) return false;
    try {
      // 1. 若尚未 boot 则先执行 boot 指令
      await Process.run('xcrun', ['simctl', 'boot', udid]);
      // 2. 唤起系统 Simulator.app 并定位到该设备
      await Process.run('open', [
        '-a',
        'Simulator',
        '--args',
        '-CurrentDeviceUDID',
        udid,
      ]);
      return true;
    } catch (e) {
      debugPrint('Failed to boot iOS simulator $udid: $e');
      return false;
    }
  }

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

  /// 直接打开系统内置 Simulator.app
  Future<void> openSimulatorApp() async {
    if (!Platform.isMacOS) return;
    try {
      await Process.run('open', ['-a', 'Simulator']);
    } catch (e) {
      debugPrint('Failed to open Simulator.app: $e');
    }
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
