import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../process/tool_path_resolver.dart';
import '../providers/app_providers.dart';
import '../../features/devices/widgets/adb_environment_dialog.dart';

/// ADB 环境检测与可用状态枚举。
enum AdbEnvironmentStatus {
  /// 尚未检测
  unknown,
  /// 正在执行检测
  checking,
  /// 环境已就绪（可正常执行 ADB 命令）
  ready,
  /// 未检测到 ADB 环境（需要引导或一键安装）
  missing,
  /// 正在下载官方 Platform-Tools
  downloading,
  /// 正在解压与配置权限
  extracting,
  /// 安装或配置失败
  failed,
}

/// ADB 环境详细信息状态模型。
class AdbEnvironmentInfo {
  const AdbEnvironmentInfo({
    required this.status,
    this.version = '',
    this.adbPath = '',
    this.downloadProgress = 0.0,
    this.stepDescription = '',
    this.errorMessage = '',
  });

  final AdbEnvironmentStatus status;
  final String version;
  final String adbPath;
  final double downloadProgress;
  final String stepDescription;
  final String errorMessage;

  bool get isReady => status == AdbEnvironmentStatus.ready;
  bool get isMissing => status == AdbEnvironmentStatus.missing;
  bool get isBusy =>
      status == AdbEnvironmentStatus.checking ||
      status == AdbEnvironmentStatus.downloading ||
      status == AdbEnvironmentStatus.extracting;

  AdbEnvironmentInfo copyWith({
    AdbEnvironmentStatus? status,
    String? version,
    String? adbPath,
    double? downloadProgress,
    String? stepDescription,
    String? errorMessage,
  }) {
    return AdbEnvironmentInfo(
      status: status ?? this.status,
      version: version ?? this.version,
      adbPath: adbPath ?? this.adbPath,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      stepDescription: stepDescription ?? this.stepDescription,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// ADB 环境自检与一键下载安装核心服务。
///
/// 启动时通过 `adb --version` 进行自检；若系统中缺失 ADB，
/// 提供直接从 Google 官方下载最新版 Platform-Tools 并解压至应用存储目录的能力。
class AdbEnvironmentService {
  AdbEnvironmentService();

  /// Google 官方各操作系统 Platform-Tools 最新压缩包下载地址
  static String get officialPlatformToolsUrl {
    if (Platform.isMacOS) {
      return 'https://dl.google.com/android/repository/platform-tools-latest-darwin.zip';
    } else if (Platform.isWindows) {
      return 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip';
    } else {
      return 'https://dl.google.com/android/repository/platform-tools-latest-linux.zip';
    }
  }

  /// 执行 `adb --version` 检测当前环境是否可用
  Future<AdbEnvironmentInfo> checkEnvironment() async {
    try {
      final adbPath = resolveToolPath('adb');
      final result = await Process.run(
        adbPath,
        ['--version'],
        runInShell: false,
      ).timeout(const Duration(seconds: 4));

      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        final firstLine = output.split('\n').firstOrNull ?? output;
        return AdbEnvironmentInfo(
          status: AdbEnvironmentStatus.ready,
          version: firstLine,
          adbPath: adbPath,
        );
      } else {
        return AdbEnvironmentInfo(
          status: AdbEnvironmentStatus.missing,
          errorMessage: result.stderr.toString().trim(),
        );
      }
    } catch (e) {
      return AdbEnvironmentInfo(
        status: AdbEnvironmentStatus.missing,
        errorMessage: e.toString(),
      );
    }
  }

  /// 一键从 Google 官方下载并解压配置 Platform-Tools
  Future<AdbEnvironmentInfo> downloadAndInstall({
    void Function(double progress, String step)? onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    File? tempZipFile;

    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final toolsDir = Directory('${appSupportDir.path}/tools');
      await toolsDir.create(recursive: true);

      tempZipFile = File('${toolsDir.path}/platform-tools.zip');
      if (tempZipFile.existsSync()) {
        try {
          await tempZipFile.delete();
        } catch (_) {}
      }

      onProgress?.call(0.01, 'downloading');
      final url = officialPlatformToolsUrl;
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('下载失败，HTTP 状态码: ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final sink = tempZipFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final ratio = (receivedBytes / totalBytes).clamp(0.0, 0.95);
          onProgress?.call(ratio, 'downloading');
        }
      }
      await sink.flush();
      await sink.close();

      // 解压并配置权限
      onProgress?.call(0.96, 'extracting');
      if (Platform.isWindows) {
        final tarResult = await Process.run(
          'tar',
          ['-xf', tempZipFile.path, '-C', toolsDir.path],
        );
        if (tarResult.exitCode != 0) {
          await Process.run('powershell', [
            '-Command',
            'Expand-Archive -Path "${tempZipFile.path}" -DestinationPath "${toolsDir.path}" -Force',
          ]);
        }
      } else {
        // macOS / Linux 优先使用系统 unzip
        final unzipResult = await Process.run(
          'unzip',
          ['-o', tempZipFile.path, '-d', toolsDir.path],
        );
        if (unzipResult.exitCode != 0) {
          await Process.run('tar', ['-xf', tempZipFile.path, '-C', toolsDir.path]);
        }

        final adbBin = File('${toolsDir.path}/platform-tools/adb');
        if (adbBin.existsSync()) {
          await Process.run('chmod', ['+x', adbBin.path]);
        }
      }

      // 清理临时压缩包
      try {
        if (tempZipFile.existsSync()) await tempZipFile.delete();
      } catch (_) {}

      final expectedBinary = File(
        '${toolsDir.path}/platform-tools/${Platform.isWindows ? 'adb.exe' : 'adb'}',
      );
      if (!expectedBinary.existsSync()) {
        throw Exception('解压完成，但在 ${expectedBinary.path} 未找到 adb 可执行文件');
      }

      // 注册到全局工具解析器
      registerCustomToolPath('adb', expectedBinary.path);

      // 校验安装后的 adb
      final verify = await Process.run(expectedBinary.path, ['--version']);
      if (verify.exitCode == 0) {
        final output = (verify.stdout as String).trim();
        final firstLine = output.split('\n').firstOrNull ?? output;
        onProgress?.call(1.0, 'ready');
        return AdbEnvironmentInfo(
          status: AdbEnvironmentStatus.ready,
          version: firstLine,
          adbPath: expectedBinary.path,
        );
      } else {
        throw Exception('ADB 自检未通过: ${verify.stderr}');
      }
    } catch (e) {
      return AdbEnvironmentInfo(
        status: AdbEnvironmentStatus.failed,
        errorMessage: e.toString(),
      );
    } finally {
      client.close();
      try {
        if (tempZipFile != null && tempZipFile.existsSync()) {
          await tempZipFile.delete();
        }
      } catch (_) {}
    }
  }
}

/// ADB 环境状态 Notifier 控制器。
class AdbEnvironmentNotifier extends Notifier<AdbEnvironmentInfo> {
  final AdbEnvironmentService _service = AdbEnvironmentService();
  bool _hasPromptedThisSession = false;

  @override
  AdbEnvironmentInfo build() {
    return const AdbEnvironmentInfo(status: AdbEnvironmentStatus.unknown);
  }

  /// 异步执行环境检测
  Future<AdbEnvironmentInfo> check() async {
    state = state.copyWith(status: AdbEnvironmentStatus.checking);
    final result = await _service.checkEnvironment();
    state = result;
    return result;
  }

  /// 启动时自检；若 ADB 缺失且本会话未弹出过提示，则弹出引导下载弹窗
  Future<void> checkAndPromptIfNeeded(BuildContext context) async {
    if (_hasPromptedThisSession) return;
    final info = await check();
    if (!context.mounted) return;

    if (info.isMissing && !_hasPromptedThisSession) {
      _hasPromptedThisSession = true;
      await AdbEnvironmentDialog.show(context);
    }
  }

  /// 执行一键下载安装
  Future<bool> downloadAndInstall() async {
    state = state.copyWith(
      status: AdbEnvironmentStatus.downloading,
      downloadProgress: 0.01,
      stepDescription: 'downloading',
      errorMessage: '',
    );

    final result = await _service.downloadAndInstall(
      onProgress: (progress, step) {
        state = state.copyWith(
          status: step == 'extracting'
              ? AdbEnvironmentStatus.extracting
              : AdbEnvironmentStatus.downloading,
          downloadProgress: progress,
          stepDescription: step,
        );
      },
    );

    state = result;
    if (result.isReady) {
      // 刷新 ADB 服务并触发心跳，让设备列表立即开始工作
      ref.invalidate(adbServiceProvider);
      ref.read(adbHeartbeatControllerProvider).trigger();
      return true;
    }
    return false;
  }
}

/// 全局 ADB 环境状态 Riverpod Provider。
final adbEnvironmentProvider =
    NotifierProvider<AdbEnvironmentNotifier, AdbEnvironmentInfo>(
      AdbEnvironmentNotifier.new,
    );
