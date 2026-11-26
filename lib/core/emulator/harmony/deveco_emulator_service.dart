import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../process/bounded_process.dart';
import '../emulator_ide_service.dart';
import 'deveco_emulator.dart';

/// 华为 DevEco 模拟器管理服务。
class DevEcoEmulatorService {
  const DevEcoEmulatorService({
    this._runProcess = runBoundedProcess,
    this._platform,
    this._applicationDirectories,
  });

  static const _appNames = ['DevEco-Studio', 'DevEco Studio'];
  final EmulatorIdeCommandRunner _runProcess;
  final TargetPlatform? _platform;
  final List<String>? _applicationDirectories;

  /// 只有 macOS 使用应用包和 Spotlight 探测。
  bool get supportsStudioDetection =>
      (_platform ?? defaultTargetPlatform) == TargetPlatform.macOS;

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

  /// 先检查常用安装目录，再查询 Spotlight 中已索引的自定义位置。
  Future<String?> findDevEcoStudio() async {
    if (!supportsStudioDetection) return null;
    return EmulatorIdeService(
      runProcess: _runProcess,
      applicationDirectories: _applicationDirectories,
    ).findMacApplication(appNames: _appNames);
  }

  /// 空态使用探测到的应用路径，列表工具栏沿用应用名称启动。
  Future<bool> openDevEcoStudio({String? appPath}) async {
    try {
      final applications = appPath == null ? _appNames : [appPath];
      for (final application in applications) {
        final result = await _runProcess('open', [
          '-a',
          application,
        ], timeout: const Duration(seconds: 5));
        if (result.exitCode == 0) return true;
      }
      return false;
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
