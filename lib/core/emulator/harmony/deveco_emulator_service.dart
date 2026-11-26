import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../process/bounded_process.dart';
import 'deveco_emulator.dart';

/// 带超时的宿主机命令入口，可在测试中替换 Spotlight 和应用启动。
typedef DevEcoCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required Duration timeout,
});

/// 华为 DevEco 模拟器管理服务。
class DevEcoEmulatorService {
  const DevEcoEmulatorService({
    this._runProcess = runBoundedProcess,
    this._platform,
    this._applicationDirectories,
  });

  static const _appNames = ['DevEco-Studio', 'DevEco Studio'];
  final DevEcoCommandRunner _runProcess;
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
    final userHome = Platform.environment['HOME'];
    final directories =
        _applicationDirectories ??
        [
          '/Applications',
          if (userHome != null && userHome.isNotEmpty) '$userHome/Applications',
        ];
    for (final directory in directories) {
      for (final name in _appNames) {
        final path = '$directory/$name.app';
        if (await _isStudioBundle(path)) return path;
      }
    }

    try {
      final query = _appNames
          .map((name) => 'kMDItemFSName == "$name.app"c')
          .join(' || ');
      final result = await _runProcess('/usr/bin/mdfind', [
        '-0',
        query,
      ], timeout: const Duration(seconds: 2));
      if (result.exitCode != 0) return null;
      // 使用 NUL 分隔读取路径，兼容含空格或换行的安装目录。
      for (final path in (result.stdout as String).split('\u0000')) {
        if (await _isStudioBundle(path)) return path;
      }
    } on Exception catch (error) {
      debugPrint('Failed to find DevEco Studio: $error');
    }
    return null;
  }

  /// 校验索引结果仍指向 DevEco Studio 应用包。
  Future<bool> _isStudioBundle(String path) async {
    final app = File(path);
    if (!app.isAbsolute) return false;
    final bundleName = app.uri.pathSegments.last.toLowerCase();
    return _appNames.any((name) => bundleName == '$name.app'.toLowerCase()) &&
        await File('$path/Contents/Info.plist').exists();
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
