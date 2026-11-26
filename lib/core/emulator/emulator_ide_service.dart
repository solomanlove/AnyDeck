import 'dart:io';

import 'package:flutter/foundation.dart';

import '../process/bounded_process.dart';

/// 用于有界探测与启动 macOS 应用，可在测试中替换系统命令。
typedef EmulatorIdeCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required Duration timeout,
});

/// 探测并打开模拟器的管理 IDE，独立于 SDK 工具和模拟器列表。
class EmulatorIdeService {
  const EmulatorIdeService({
    this._platform,
    this._environment,
    this._applicationDirectories,
    this._runProcess = runBoundedProcess,
  });

  final TargetPlatform? _platform;
  final Map<String, String>? _environment;
  final List<String>? _applicationDirectories;
  final EmulatorIdeCommandRunner _runProcess;
  static const _probeTimeout = Duration(seconds: 2);

  TargetPlatform get platform => _platform ?? defaultTargetPlatform;
  Map<String, String> get _env => _environment ?? Platform.environment;

  /// 检查 Android Studio 的应用包或桌面启动器。
  Future<String?> findAndroidStudio() async {
    if (platform == TargetPlatform.macOS) {
      return findMacApplication(
        appNames: ['Android Studio', 'Android Studio Preview'],
        bundleIdentifier: 'com.google.android.studio',
      );
    }

    if (platform == TargetPlatform.windows) {
      return _firstInstalledLauncher([
        for (final key in ['ProgramFiles', 'ProgramFiles(x86)'])
          if (_env[key] case final root? when root.isNotEmpty)
            '$root/Android/Android Studio/bin/studio64.exe',
        if (_env['LOCALAPPDATA'] case final root? when root.isNotEmpty)
          '$root/Programs/Android Studio/bin/studio64.exe',
        for (final directory in _pathDirectories(';'))
          '$directory/studio64.exe',
      ]);
    }

    if (platform == TargetPlatform.linux) {
      return _firstInstalledLauncher([
        for (final root in [
          '/opt',
          '/usr/local',
          if (_env['HOME'] case final root? when root.isNotEmpty) root,
        ]) ...[
          '$root/android-studio/bin/studio',
          '$root/android-studio/bin/studio.sh',
        ],
        '/snap/bin/android-studio',
        for (final directory in _pathDirectories(':')) ...[
          '$directory/android-studio',
          '$directory/studio.sh',
        ],
      ]);
    }

    return null;
  }

  /// 优先使用选中的 Xcode，再检查应用目录和 Spotlight 中的其他版本。
  Future<String?> findXcode() async {
    if (platform != TargetPlatform.macOS) return null;
    final override = _env['DEVELOPER_DIR'];
    if (override != null) {
      final path = await _xcodeApp(override);
      if (path != null) return path;
    }

    try {
      final result = await _runProcess('/usr/bin/xcode-select', [
        '-p',
      ], timeout: _probeTimeout);
      if (result.exitCode == 0) {
        final path = await _xcodeApp((result.stdout as String).trim());
        if (path != null) return path;
      }
    } on Exception catch (error) {
      debugPrint('Failed to read selected Xcode: $error');
    }

    return findMacApplication(
      appNames: ['Xcode', 'Xcode-beta'],
      bundleIdentifier: 'com.apple.dt.Xcode',
    );
  }

  /// 先检查常用安装目录，再通过有界 Spotlight 查询发现自定义安装路径。
  Future<String?> findMacApplication({
    required List<String> appNames,
    String? bundleIdentifier,
  }) async {
    final directories =
        _applicationDirectories ??
        [
          '/Applications',
          if (_env['HOME'] case final root? when root.isNotEmpty)
            '$root/Applications',
        ];
    for (final directory in directories) {
      for (final name in appNames) {
        final path = '$directory/$name.app';
        if (await _hasApplicationBundle(path)) return path;
      }
    }

    try {
      final query = [
        for (final name in appNames) 'kMDItemFSName == "$name.app"c',
        if (bundleIdentifier != null)
          'kMDItemCFBundleIdentifier == "$bundleIdentifier"c',
      ].join(' || ');
      final result = await _runProcess('/usr/bin/mdfind', [
        '-0',
        query,
      ], timeout: _probeTimeout);
      if (result.exitCode != 0) return null;
      // 以 NUL 分隔，保留自定义安装路径中的空格与换行。
      for (final path in (result.stdout as String).split('\u0000')) {
        if (!await _hasApplicationBundle(path)) continue;
        final name = File(path).uri.pathSegments.last.toLowerCase();
        if (bundleIdentifier != null ||
            appNames.any((item) => name == '$item.app'.toLowerCase())) {
          return path;
        }
      }
    } on Exception catch (error) {
      debugPrint('Failed to query installed emulator IDE: $error');
    }
    return null;
  }

  /// 启动已探测的 IDE，保持带空格的路径为独立参数。
  Future<bool> open(String path) async {
    try {
      if (platform == TargetPlatform.macOS) {
        final result = await _runProcess('/usr/bin/open', [
          '-a',
          path,
        ], timeout: const Duration(seconds: 5));
        return result.exitCode == 0;
      }
      // 桌面 IDE 是长期运行的应用，启动后独立于 AnyDeck 进程。
      await Process.start(path, [], mode: ProcessStartMode.detached);
      return true;
    } on Exception catch (error) {
      debugPrint('Failed to open emulator IDE: $error');
      return false;
    }
  }

  Iterable<String> _pathDirectories(String separator) =>
      (_env['PATH'] ?? '').split(separator).where((path) => path.isNotEmpty);

  Future<String?> _firstInstalledLauncher(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (file.isAbsolute && await file.exists()) return path;
    }
    return null;
  }

  Future<String?> _xcodeApp(String developerPath) async {
    const suffix = '/Contents/Developer';
    final path = developerPath.endsWith(suffix)
        ? developerPath.substring(0, developerPath.length - suffix.length)
        : developerPath;
    if (!await _hasApplicationBundle(path)) return null;
    // Command Line Tools 或其他应用目录不能作为完整 Xcode 打开。
    return await File('$path/Contents/Developer/usr/bin/xcodebuild').exists()
        ? path
        : null;
  }

  Future<bool> _hasApplicationBundle(String path) async {
    return path.toLowerCase().endsWith('.app') &&
        File(path).isAbsolute &&
        await File('$path/Contents/Info.plist').exists();
  }
}
