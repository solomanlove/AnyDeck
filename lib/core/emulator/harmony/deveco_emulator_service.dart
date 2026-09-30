import 'dart:io';
import 'package:flutter/foundation.dart';
import 'deveco_emulator.dart';

/// 华为 DevEco 模拟器管理服务。
class DevEcoEmulatorService {
  const DevEcoEmulatorService();

  /// 扫描并获取本地 DevEco 模拟器列表
  Future<List<DevEcoEmulator>> fetchEmulators() async {
    final List<DevEcoEmulator> emulators = [];

    try {
      // 1. 扫描 DevEco 常见模拟器镜像/配置目录
      final userHome = Platform.environment['HOME'] ?? '';
      final candidateDirs = [
        Directory('$userHome/Library/Huawei/Sdk/hmscore/emulator'),
        Directory('$userHome/Library/Huawei/Sdk/openharmony/emulator'),
        Directory('$userHome/.Huawei/DevEcoStudio/emulator'),
      ];

      for (final dir in candidateDirs) {
        if (await dir.exists()) {
          final entries = await dir.list().toList();
          for (final entry in entries) {
            if (entry is Directory) {
              final dirName = entry.path.split(Platform.pathSeparator).last;
              if (dirName.startsWith('.')) continue;
              emulators.add(
                DevEcoEmulator(
                  name: dirName,
                  apiVersion: 'HarmonyOS NEXT',
                  deviceType: 'Phone',
                  state: 'Stopped',
                  configPath: entry.path,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning DevEco emulators: $e');
    }

    return emulators;
  }

  /// 唤起 DevEco Studio 应用程序
  Future<bool> openDevEcoStudio() async {
    try {
      final res = await Process.run('open', ['-a', 'DevEco-Studio']);
      if (res.exitCode == 0) return true;
      final resAlt = await Process.run('open', ['-a', 'DevEco Studio']);
      return resAlt.exitCode == 0;
    } catch (e) {
      debugPrint('Failed to open DevEco Studio: $e');
      return false;
    }
  }

  /// 打开指定的配置文件或数据目录
  Future<void> openFolder(String path) async {
    try {
      await Process.run('open', [path]);
    } catch (e) {
      debugPrint('Failed to open folder $path: $e');
    }
  }
}
