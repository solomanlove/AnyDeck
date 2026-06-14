import 'dart:async';
import 'dart:io';

import 'android_emulator.dart';
import '../process/tool_path_resolver.dart';
import '../process/host_platform_service.dart';

/// 模拟器管理服务，封装 AVD 列表读取、启动和删除。
class EmulatorService {
  EmulatorService({
    String? executable,
    String? avdManagerExecutable,
    String? avdHome,
    HostPlatformService? hostPlatformService,
  }) : executable = executable ?? resolveToolPath('emulator'),
       avdManagerExecutable =
           avdManagerExecutable ?? resolveToolPath('avdmanager'),
       avdHome = avdHome ?? _defaultAvdHome(),
       _hostPlatformService = hostPlatformService ?? HostPlatformService();

  final String executable;
  final String avdManagerExecutable;
  final String? avdHome;
  final HostPlatformService _hostPlatformService;

  /// 获取本地所有 AVD 模拟器配置摘要。
  Future<List<AndroidEmulator>> listEmulators() async {
    try {
      final result = await Process.run(executable, ['-list-avds']);
      if (result.exitCode != 0) {
        return [];
      }
      final names = result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      return Future.wait(names.map(_loadEmulator));
    } catch (_) {
      return [];
    }
  }

  /// 后台启动指定的 AVD 模拟器（使用 ProcessStartMode.detached 运行）。
  Future<bool> startEmulator(String avdName) async {
    try {
      await Process.start(executable, [
        '-avd',
        avdName,
      ], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 在系统文件管理器中打开指定 AVD 配置目录。
  Future<bool> openAvdDirectory(AndroidEmulator emulator) async {
    final directory = emulator.avdDirectory;
    if (directory == null) {
      return false;
    }
    return _hostPlatformService.openDirectory(directory.path);
  }

  /// 清空 AVD 的用户数据和快照缓存，保留系统镜像和基础配置。
  Future<bool> clearEmulatorData(AndroidEmulator emulator) async {
    final directory = emulator.avdDirectory;
    if (directory == null || !await directory.exists()) {
      return false;
    }

    try {
      const fileNames = [
        'cache.img',
        'cache.img.qcow2',
        'encryptionkey.img',
        'encryptionkey.img.qcow2',
        'userdata-qemu.img',
        'userdata-qemu.img.qcow2',
      ];
      for (final fileName in fileNames) {
        final file = File('${directory.path}/$fileName');
        if (await file.exists()) {
          await file.delete();
        }
      }

      final snapshots = Directory('${directory.path}/snapshots');
      if (await snapshots.exists()) {
        await snapshots.delete(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 删除 AVD 配置和本地镜像目录。
  Future<bool> deleteEmulator(AndroidEmulator emulator) async {
    try {
      final result = await Process.run(avdManagerExecutable, [
        'delete',
        'avd',
        '-n',
        emulator.name,
      ]);
      if (result.exitCode == 0) {
        return true;
      }
      return false;
    } catch (_) {
      // 部分精简 Android SDK 只带 emulator，不带 avdmanager，继续走本地文件兜底。
    }

    return _deleteAvdFiles(emulator);
  }

  Future<bool> _deleteAvdFiles(AndroidEmulator emulator) async {
    final home = avdHome;
    if (home == null) {
      return false;
    }

    try {
      var deleted = false;
      final metadata = File('$home/${emulator.name}.ini');
      if (await metadata.exists()) {
        await metadata.delete();
        deleted = true;
      }

      final directory = emulator.avdDirectory;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
        deleted = true;
      }
      return deleted;
    } catch (_) {
      return false;
    }
  }

  Future<AndroidEmulator> _loadEmulator(String name) async {
    final directory = await _resolveAvdDirectory(name);
    final config = await _readConfig(directory);
    return AndroidEmulator(
      name: name,
      avdDirectory: directory,
      resolution: _resolution(config),
      sdkVersion: _sdkVersion(config),
      abi: _abi(config),
      memory: _memory(config),
      storage: _storage(config),
      config: config,
    );
  }

  Future<Directory?> _resolveAvdDirectory(String name) async {
    final home = avdHome;
    if (home == null) {
      return null;
    }

    final metadata = File('$home/$name.ini');
    if (await metadata.exists()) {
      final values = _parseConfig(await metadata.readAsString());
      final path = values['path'];
      if (path != null && path.isNotEmpty) {
        return Directory(path);
      }
    }

    final fallback = Directory('$home/$name.avd');
    return await fallback.exists() ? fallback : fallback;
  }

  Future<Map<String, String>> _readConfig(Directory? directory) async {
    if (directory == null) {
      return const {};
    }

    final config = File('${directory.path}/config.ini');
    if (!await config.exists()) {
      return const {};
    }

    try {
      return _parseConfig(await config.readAsString());
    } catch (_) {
      return const {};
    }
  }

  static Map<String, String> _parseConfig(String raw) {
    final values = <String, String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final separator = trimmed.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      values[key] = value;
    }
    return values;
  }

  static String? _resolution(Map<String, String> config) {
    final width = config['hw.lcd.width'];
    final height = config['hw.lcd.height'];
    if (width == null || height == null || width.isEmpty || height.isEmpty) {
      return null;
    }
    return '${width}x$height';
  }

  static String? _sdkVersion(Map<String, String> config) {
    final target = config['target'];
    if (target == null || target.isEmpty) {
      return null;
    }
    return target
        .replaceFirst('android-', '')
        .replaceFirst('Google Inc.:Google APIs:', '')
        .replaceFirst('Google Inc.:Google Play:', '');
  }

  static String? _abi(Map<String, String> config) {
    final abi = config['abi.type'];
    if (abi != null && abi.isNotEmpty) {
      return abi;
    }

    final imagePath = config['image.sysdir.1'];
    if (imagePath == null || imagePath.isEmpty) {
      return null;
    }
    final parts = imagePath
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.last;
  }

  static String? _memory(Map<String, String> config) {
    return _sizeLabel(config['hw.ramSize'], defaultUnit: 'M');
  }

  static String? _storage(Map<String, String> config) {
    return _sizeLabel(config['disk.dataPartition.size'], defaultUnit: 'B');
  }

  static String? _sizeLabel(String? raw, {required String defaultUnit}) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final value = raw.trim().toUpperCase();
    final match = RegExp(r'^(\d+(?:\.\d+)?)([KMGTP]?B?)?$').firstMatch(value);
    if (match == null) {
      return raw.trim();
    }

    final number = double.tryParse(match.group(1)!);
    if (number == null) {
      return raw.trim();
    }

    final unit = (match.group(2)?.isEmpty ?? true)
        ? defaultUnit
        : match.group(2)!;
    final bytes = switch (unit) {
      'K' || 'KB' => number * 1024,
      'M' || 'MB' => number * 1024 * 1024,
      'G' || 'GB' => number * 1024 * 1024 * 1024,
      'T' || 'TB' => number * 1024 * 1024 * 1024 * 1024,
      'P' || 'PB' => number * 1024 * 1024 * 1024 * 1024 * 1024,
      _ => number,
    };

    const kib = 1024.0;
    const mib = kib * 1024;
    const gib = mib * 1024;
    const tib = gib * 1024;
    if (bytes >= tib && bytes % tib == 0) {
      return '${(bytes / tib).round()}T';
    }
    if (bytes >= gib && bytes % gib == 0) {
      return '${(bytes / gib).round()}G';
    }
    if (bytes >= mib && bytes % mib == 0) {
      return '${(bytes / mib).round()}M';
    }
    if (bytes >= kib && bytes % kib == 0) {
      return '${(bytes / kib).round()}K';
    }
    return '${bytes == bytes.roundToDouble() ? bytes.round() : bytes}B';
  }

  static String? _defaultAvdHome() {
    final env = Platform.environment;
    final explicitHome = env['ANDROID_AVD_HOME'];
    if (explicitHome != null && explicitHome.isNotEmpty) {
      return explicitHome;
    }

    final androidUserHome = env['ANDROID_USER_HOME'];
    if (androidUserHome != null && androidUserHome.isNotEmpty) {
      return '$androidUserHome/avd';
    }

    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home == null || home.isEmpty) {
      return null;
    }
    return '$home/.android/avd';
  }
}
