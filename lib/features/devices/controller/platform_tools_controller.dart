import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_result.dart';
import '../../../core/harmony/hdc_service_server.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/process/tool_path_resolver.dart';
import '../../../core/providers/app_providers.dart';
import '../../widgets/dashboard_snack.dart';

/// 跨平台调试服务类型枚举
enum PlatformServiceType {
  all,
  adb,
  hdc,
  ios,
}

/// 跨平台工具目录与服务生命周期控制器
class PlatformToolsController {
  const PlatformToolsController._();

  /// 解析目标工具所在目录路径。
  static String? resolveToolDirectory(WidgetRef ref, String toolKey) {
    String? rawPath;
    if (toolKey == 'adb') {
      final adbExe = ref.read(adbServiceProvider).executable;
      if (adbExe.isNotEmpty && adbExe != 'adb') {
        rawPath = adbExe;
      }
    } else if (toolKey == 'hdc') {
      final hdcExe = ref.read(hdcServiceProvider).executable;
      if (hdcExe.isNotEmpty && hdcExe != 'hdc') {
        rawPath = hdcExe;
      }
    }

    if (rawPath == null || rawPath.isEmpty) {
      final resolved = resolveToolPath(toolKey);
      if (resolved != toolKey) {
        rawPath = resolved;
      }
    }

    if (rawPath != null && rawPath.isNotEmpty) {
      final file = File(rawPath);
      if (file.existsSync()) {
        return file.parent.path;
      }
      final dir = Directory(rawPath);
      if (dir.existsSync()) {
        return dir.path;
      }
    }
    return null;
  }

  /// 打开工具所在目录或在终端中定位至该目录
  static Future<void> openToolDirectory(
    BuildContext context,
    WidgetRef ref,
    String toolKey, {
    required bool terminal,
  }) async {
    final displayName = switch (toolKey) {
      'adb' => 'ADB',
      'hdc' => 'HDC',
      'ios' => 'iOS (go-ios)',
      _ => toolKey,
    };

    final dirPath = resolveToolDirectory(ref, toolKey);
    if (dirPath == null) {
      if (context.mounted) {
        DashboardSnack.show(
          context,
          context.l10n.t('toolPathNotFound').replaceAll('{tool}', displayName),
          isError: true,
        );
      }
      return;
    }

    try {
      final hostService = ref.read(hostPlatformServiceProvider);
      final bool success;
      if (terminal) {
        success = await hostService.openTerminal(dirPath);
      } else {
        success = await hostService.openDirectory(dirPath);
      }

      if (!context.mounted) return;
      if (success) {
        final templateKey = terminal ? 'toolTerminalOpened' : 'toolDirOpened';
        DashboardSnack.show(
          context,
          context.l10n
              .t(templateKey)
              .replaceAll('{tool}', displayName)
              .replaceAll('{path}', dirPath),
        );
      } else {
        DashboardSnack.show(
          context,
          '打开 $displayName ${terminal ? "终端" : "目录"}失败',
          isError: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        DashboardSnack.show(context, '操作异常: $e', isError: true);
      }
    }
  }

  /// 重启指定的调试服务或一键重启所有服务
  static Future<void> restartPlatformService(
    BuildContext context,
    WidgetRef ref,
    PlatformServiceType type,
  ) async {
    switch (type) {
      case PlatformServiceType.adb:
        DashboardSnack.show(context, context.l10n.t('restartingAdb'));
        final result =
            await ref.read(deviceRegistryProvider.notifier).restartAdb();
        if (!context.mounted) return;
        DashboardSnack.show(
          context,
          result.isSuccess
              ? context.l10n.t('restartAdbSuccess')
              : '${context.l10n.t("restartAdbFailed")}: ${result.message}',
          isError: !result.isSuccess,
        );
        break;

      case PlatformServiceType.hdc:
        DashboardSnack.show(context, context.l10n.t('restartingHdc'));
        final result = await ref.read(hdcServiceProvider).restartServer();
        await ref.read(deviceRegistryProvider.notifier).refreshDevices();
        if (!context.mounted) return;
        DashboardSnack.show(
          context,
          result.isSuccess
              ? context.l10n.t('restartHdcSuccess')
              : '${context.l10n.t("restartHdcFailed")}: ${result.message}',
          isError: !result.isSuccess,
        );
        break;

      case PlatformServiceType.ios:
        DashboardSnack.show(context, context.l10n.t('restartingIos'));
        final iosResult = await _resetIosService(ref);
        await ref.read(deviceRegistryProvider.notifier).refreshDevices();
        if (!context.mounted) return;
        DashboardSnack.show(
          context,
          iosResult.isSuccess
              ? context.l10n.t('restartIosSuccess')
              : '${context.l10n.t("restartIosFailed")}: ${iosResult.message}',
          isError: !iosResult.isSuccess,
        );
        break;

      case PlatformServiceType.all:
        DashboardSnack.show(context, context.l10n.t('restartingAllServices'));
        // 并行触发 ADB、HDC 重启及 iOS 调试服务重置
        final adbFuture =
            ref.read(deviceRegistryProvider.notifier).restartAdb();
        final hdcFuture = ref.read(hdcServiceProvider).restartServer();
        final iosFuture = _resetIosService(ref);

        final results = await Future.wait([adbFuture, hdcFuture, iosFuture]);
        final adbRes = results[0];
        final hdcRes = results[1];
        final iosRes = results[2];

        await ref.read(deviceRegistryProvider.notifier).refreshDevices();
        if (!context.mounted) return;

        final hasFailure =
            !adbRes.isSuccess || !hdcRes.isSuccess || !iosRes.isSuccess;
        if (!hasFailure) {
          DashboardSnack.show(
            context,
            context.l10n.t('restartAllServicesSuccess'),
          );
        } else {
          final summary = [
            'ADB: ${adbRes.isSuccess ? "✓" : "✗"}',
            'HDC: ${hdcRes.isSuccess ? "✓" : "✗"}',
            'iOS: ${iosRes.isSuccess ? "✓" : "✗"}',
          ].join(', ');
          DashboardSnack.show(
            context,
            '服务重启完成 ($summary)',
            isError: !adbRes.isSuccess && !hdcRes.isSuccess,
          );
        }
        break;
    }
  }

  /// 重置 iOS 本地进程与 tunnel 代理
  static Future<AdbResult> _resetIosService(WidgetRef ref) async {
    try {
      final cmd = ref.read(iosCommandServiceProvider);
      try {
        await cmd.run(
          ['tunnel', 'stopagent'],
          timeout: const Duration(seconds: 3),
        );
      } catch (_) {}

      if (Platform.isMacOS || Platform.isLinux) {
        try {
          await Process.run('killall', ['-9', 'go-ios']);
        } catch (_) {}
      }
      return const AdbResult(exitCode: 0, stdout: 'OK', stderr: '');
    } catch (e) {
      return AdbResult(exitCode: 1, stdout: '', stderr: e.toString());
    }
  }

  /// 一键重启所有当前在线设备
  static Future<void> rebootAllOnlineDevices(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final devices = ref
        .read(deviceRegistryProvider)
        .where((d) => d.isOnline)
        .toList();

    if (devices.isEmpty) {
      DashboardSnack.show(context, '当前没有在线设备', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.t('rebootOnlineDevices')),
        content: Text(
          '${ctx.l10n.t("rebootOnlineDevicesConfirm")}\n(共 ${devices.length} 台设备)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.t('confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    for (final device in devices) {
      try {
        if (device.isHarmony) {
          ref.read(hdcServiceProvider).shell(device.id, 'reboot');
        } else if (device.isIos) {
          ref
              .read(iosCommandServiceProvider)
              .run(['reboot', '--udid=${device.id}']);
        } else {
          ref.read(deviceActionServiceProvider).reboot(device.id);
        }
      } catch (_) {}
    }

    if (context.mounted) {
      DashboardSnack.show(context, context.l10n.t('rebootOnlineDevicesSent'));
    }
  }
}
