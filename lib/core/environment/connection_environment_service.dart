import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adb/adb_environment_service.dart';
import '../process/tool_path_resolver.dart';

/// 目标连接平台分类枚举。
enum TargetPlatformType {
  /// Android 设备 (ADB)
  android,

  /// 纯血鸿蒙 HarmonyOS NEXT 设备 (HDC)
  harmony,

  /// 苹果 iOS 设备 (go-ios)
  ios,
}

/// 工具运行环境状态枚举。
enum PlatformToolStatus {
  /// 尚未检测
  unknown,

  /// 正在执行检测
  checking,

  /// 环境已就绪（可正常通信并执行指令）
  ready,

  /// 未检测到工具或环境缺失（需要引导安装配置）
  missing,

  /// 正在下载工具中（主要针对 ADB 一键下载等）
  downloading,

  /// 正在解压并配置权限
  extracting,

  /// 配置或检测失败
  failed,
}

/// 某特定平台的连接工具环境信息。
class PlatformEnvironmentInfo {
  const PlatformEnvironmentInfo({
    required this.platform,
    required this.status,
    required this.toolName,
    this.executablePath = '',
    this.version = '',
    this.errorMessage = '',
    this.downloadProgress = 0.0,
  });

  /// 目标平台
  final TargetPlatformType platform;

  /// 工具状态
  final PlatformToolStatus status;

  /// 工具命令名称（如 adb, hdc, ios）
  final String toolName;

  /// 可执行文件绝对路径
  final String executablePath;

  /// 工具版本输出或版本号
  final String version;

  /// 错误或异常描述
  final String errorMessage;

  /// 下载或安装进度（0.0 ~ 1.0）
  final double downloadProgress;

  /// 是否已就绪
  bool get isReady => status == PlatformToolStatus.ready;

  /// 是否缺失环境
  bool get isMissing => status == PlatformToolStatus.missing || status == PlatformToolStatus.failed;

  /// 是否正在忙碌（检测或下载中）
  bool get isBusy =>
      status == PlatformToolStatus.checking ||
      status == PlatformToolStatus.downloading ||
      status == PlatformToolStatus.extracting;

  PlatformEnvironmentInfo copyWith({
    TargetPlatformType? platform,
    PlatformToolStatus? status,
    String? toolName,
    String? executablePath,
    String? version,
    String? errorMessage,
    double? downloadProgress,
  }) {
    return PlatformEnvironmentInfo(
      platform: platform ?? this.platform,
      status: status ?? this.status,
      toolName: toolName ?? this.toolName,
      executablePath: executablePath ?? this.executablePath,
      version: version ?? this.version,
      errorMessage: errorMessage ?? this.errorMessage,
      downloadProgress: downloadProgress ?? this.downloadProgress,
    );
  }
}

/// 全平台连接环境检测与引导服务。
///
/// 负责 Android (ADB)、纯血鸿蒙 (HDC) 以及 iOS (go-ios) 三大平台的工具探查、
/// 版本获取、缺失引导及官方下载指引。
class ConnectionEnvironmentService {
  final AdbEnvironmentService _adbEnvService = AdbEnvironmentService();

  /// 华为 DevEco Studio 官方下载页面
  static const String devecoStudioDownloadUrl =
      'https://developer.huawei.com/consumer/cn/deveco-studio/';

  /// go-ios 官方 GitHub Releases 页面
  static const String goIosReleasesUrl =
      'https://github.com/danielpaulus/go-ios/releases';

  /// Android Platform-Tools 官方下载页面
  static const String platformToolsOfficialUrl =
      'https://developer.android.com/tools/releases/platform-tools';

  /// 检测 Android (ADB) 环境
  Future<PlatformEnvironmentInfo> checkAndroidEnvironment() async {
    final adbInfo = await _adbEnvService.checkEnvironment();
    return PlatformEnvironmentInfo(
      platform: TargetPlatformType.android,
      status: adbInfo.isReady ? PlatformToolStatus.ready : PlatformToolStatus.missing,
      toolName: 'adb',
      executablePath: adbInfo.adbPath,
      version: adbInfo.version,
      errorMessage: adbInfo.errorMessage,
    );
  }

  /// 检测纯血鸿蒙 (HDC) 环境
  Future<PlatformEnvironmentInfo> checkHarmonyEnvironment() async {
    final hdcPath = resolveToolPath('hdc');
    final hasCandidate = File(hdcPath).existsSync() || hdcPath == 'hdc';

    if (!hasCandidate) {
      return const PlatformEnvironmentInfo(
        platform: TargetPlatformType.harmony,
        status: PlatformToolStatus.missing,
        toolName: 'hdc',
        errorMessage: '未在常用 SDK 路径或系统 PATH 中找到 hdc 可执行文件',
      );
    }

    try {
      // 运行 hdc -v 探测版本
      final result = await Process.run(
        hdcPath,
        ['-v'],
        runInShell: false,
      ).timeout(const Duration(seconds: 4));

      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        final firstLine = out.split('\n').firstOrNull ?? out;
        return PlatformEnvironmentInfo(
          platform: TargetPlatformType.harmony,
          status: PlatformToolStatus.ready,
          toolName: 'hdc',
          executablePath: hdcPath,
          version: firstLine,
        );
      } else {
        // 尝试 hdc version
        final fallback = await Process.run(
          hdcPath,
          ['version'],
          runInShell: false,
        ).timeout(const Duration(seconds: 3));

        if (fallback.exitCode == 0) {
          final out = (fallback.stdout as String).trim();
          final firstLine = out.split('\n').firstOrNull ?? out;
          return PlatformEnvironmentInfo(
            platform: TargetPlatformType.harmony,
            status: PlatformToolStatus.ready,
            toolName: 'hdc',
            executablePath: hdcPath,
            version: firstLine,
          );
        }

        return PlatformEnvironmentInfo(
          platform: TargetPlatformType.harmony,
          status: PlatformToolStatus.missing,
          toolName: 'hdc',
          executablePath: hdcPath,
          errorMessage: result.stderr.toString().trim(),
        );
      }
    } catch (e) {
      return PlatformEnvironmentInfo(
        platform: TargetPlatformType.harmony,
        status: PlatformToolStatus.missing,
        toolName: 'hdc',
        executablePath: hdcPath,
        errorMessage: e.toString(),
      );
    }
  }

  /// 检测苹果 iOS (go-ios / ios) 环境
  Future<PlatformEnvironmentInfo> checkIosEnvironment() async {
    var iosPath = resolveToolPath('ios');
    if (!File(iosPath).existsSync() && iosPath == 'ios') {
      final fallbackPath = resolveToolPath('go-ios');
      if (File(fallbackPath).existsSync() || fallbackPath != 'go-ios') {
        iosPath = fallbackPath;
      }
    }

    try {
      // 运行 ios version 获取版本（返回 JSON 如 {"version":"1.2.0"}）
      final result = await Process.run(
        iosPath,
        ['version'],
        runInShell: false,
      ).timeout(const Duration(seconds: 4));

      final stdoutStr = (result.stdout as String).trim();
      if (result.exitCode == 0 || stdoutStr.contains('"version"')) {
        String versionStr = 'v1.0.0+';
        try {
          for (final line in stdoutStr.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.startsWith('{') && trimmed.contains('"version"')) {
              final parsed = jsonDecode(trimmed) as Map<String, dynamic>;
              if (parsed.containsKey('version')) {
                versionStr = 'v${parsed['version']}';
                break;
              }
            }
          }
        } catch (_) {
          versionStr = stdoutStr.split('\n').firstOrNull ?? stdoutStr;
        }

        return PlatformEnvironmentInfo(
          platform: TargetPlatformType.ios,
          status: PlatformToolStatus.ready,
          toolName: 'go-ios',
          executablePath: iosPath,
          version: versionStr,
        );
      } else {
        return PlatformEnvironmentInfo(
          platform: TargetPlatformType.ios,
          status: PlatformToolStatus.missing,
          toolName: 'go-ios',
          executablePath: iosPath,
          errorMessage: result.stderr.toString().trim().isNotEmpty
              ? result.stderr.toString().trim()
              : '未找到可用的 go-ios 或 ios CLI 工具',
        );
      }
    } catch (e) {
      return PlatformEnvironmentInfo(
        platform: TargetPlatformType.ios,
        status: PlatformToolStatus.missing,
        toolName: 'go-ios',
        executablePath: iosPath,
        errorMessage: e.toString(),
      );
    }
  }

  /// 并行检测三大平台环境
  Future<Map<TargetPlatformType, PlatformEnvironmentInfo>> checkAllEnvironments() async {
    final results = await Future.wait([
      checkAndroidEnvironment(),
      checkHarmonyEnvironment(),
      checkIosEnvironment(),
    ]);

    return {
      TargetPlatformType.android: results[0],
      TargetPlatformType.harmony: results[1],
      TargetPlatformType.ios: results[2],
    };
  }

  /// 打开系统浏览器访问指定 URL
  static Future<void> openUrl(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  }
}

/// 全平台连接环境状态 Notifier 控制器。
class ConnectionEnvironmentNotifier
    extends Notifier<Map<TargetPlatformType, PlatformEnvironmentInfo>> {
  final ConnectionEnvironmentService _service = ConnectionEnvironmentService();

  @override
  Map<TargetPlatformType, PlatformEnvironmentInfo> build() {
    return {
      TargetPlatformType.android: const PlatformEnvironmentInfo(
        platform: TargetPlatformType.android,
        status: PlatformToolStatus.unknown,
        toolName: 'adb',
      ),
      TargetPlatformType.harmony: const PlatformEnvironmentInfo(
        platform: TargetPlatformType.harmony,
        status: PlatformToolStatus.unknown,
        toolName: 'hdc',
      ),
      TargetPlatformType.ios: const PlatformEnvironmentInfo(
        platform: TargetPlatformType.ios,
        status: PlatformToolStatus.unknown,
        toolName: 'go-ios',
      ),
    };
  }

  /// 异步全量检测所有平台环境
  Future<Map<TargetPlatformType, PlatformEnvironmentInfo>> checkAll() async {
    final updated = await _service.checkAllEnvironments();
    state = updated;
    return updated;
  }

  /// 单独检测某一特定平台
  Future<PlatformEnvironmentInfo> checkPlatform(TargetPlatformType platform) async {
    state = {
      ...state,
      platform: state[platform]!.copyWith(status: PlatformToolStatus.checking),
    };

    final result = switch (platform) {
      TargetPlatformType.android => await _service.checkAndroidEnvironment(),
      TargetPlatformType.harmony => await _service.checkHarmonyEnvironment(),
      TargetPlatformType.ios => await _service.checkIosEnvironment(),
    };

    state = {
      ...state,
      platform: result,
    };
    return result;
  }

  /// 开发者选项测试专用：模拟特定平台的缺失状态
  void simulateMissing(TargetPlatformType platform) {
    state = {
      ...state,
      platform: state[platform]!.copyWith(
        status: PlatformToolStatus.missing,
        errorMessage: '开发者选项测试：模拟未找到 ${state[platform]!.toolName} 命令',
      ),
    };
  }
}

/// 全局多端连接环境 Riverpod Provider。
final connectionEnvironmentProvider = NotifierProvider<
    ConnectionEnvironmentNotifier,
    Map<TargetPlatformType, PlatformEnvironmentInfo>>(
  ConnectionEnvironmentNotifier.new,
);
