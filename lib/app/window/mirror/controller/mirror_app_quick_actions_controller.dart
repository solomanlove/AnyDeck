import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';

import '../../../../core/adb/adb_service.dart';
import '../../../../core/apps/adb_package.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widget/app_toast.dart';
import '../../multi_window_compat.dart';
import '../mirror_aspect_resolver.dart';

/// 投屏窗口前台应用快捷操作控制器。
/// 封装针对当前应用的全部 ADB 快捷操作逻辑，与 UI 组件彻底解耦。
class MirrorAppQuickActionsController {
  final WidgetRef ref;
  final BuildContext context;
  final String deviceId;
  final AdbPackage package;

  MirrorAppQuickActionsController({
    required this.ref,
    required this.context,
    required this.deviceId,
    required this.package,
  });

  AdbService get _adb => ref.read(adbServiceProvider);
  String get _packageName => package.name;
  String get _displayName => package.displayName;

  /// 提示轻消息
  void _toast(String message, {bool isError = false}) {
    if (context.mounted) {
      AppToast.show(
        context,
        message,
        type: isError ? AppToastType.error : AppToastType.success,
      );
    }
  }

  // ==================== 1. 应用生命周期与基础控制 ====================

  /// 启动应用
  Future<void> launchApp() async {
    final service = ref.read(appManagementServiceProvider);
    final result = await service.launch(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已启动应用: $_displayName');
    } else {
      _toast('启动应用失败: ${result.message}', isError: true);
    }
  }

  /// 强行停止应用
  Future<void> forceStopApp() async {
    final service = ref.read(appManagementServiceProvider);
    final result = await service.forceStop(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已强行停止: $_displayName');
    } else {
      _toast('停止应用失败: ${result.message}', isError: true);
    }
  }

  /// 重启应用（强停后重新拉起）
  Future<void> restartApp() async {
    final service = ref.read(appManagementServiceProvider);
    await service.forceStop(deviceId, _packageName);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final result = await service.launch(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已重启应用: $_displayName');
    } else {
      _toast('重启应用失败: ${result.message}', isError: true);
    }
  }

  /// 清除应用数据
  Future<void> clearAppData() async {
    final service = ref.read(appManagementServiceProvider);
    final result = await service.clearData(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已清除应用数据: $_displayName');
    } else {
      _toast('清除数据失败: ${result.message}', isError: true);
    }
  }

  /// 清除数据并重启应用
  Future<void> clearAppDataAndRestart() async {
    final service = ref.read(appManagementServiceProvider);
    await service.clearData(deviceId, _packageName);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final result = await service.launch(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已清除数据并重启应用: $_displayName');
    } else {
      _toast('重启应用失败: ${result.message}', isError: true);
    }
  }

  /// 冻结或解冻应用
  Future<void> toggleFreezeApp() async {
    final service = ref.read(appManagementServiceProvider);
    final isEnabled = package.enabled;
    final result = isEnabled
        ? await service.freezeApp(deviceId, _packageName)
        : await service.unfreezeApp(deviceId, _packageName);

    if (result.isSuccess) {
      _toast(isEnabled ? '已冻结应用: $_displayName' : '已解冻启用: $_displayName');
      ref.read(packagesProvider(deviceId).notifier).refreshSinglePackage(_packageName);
    } else {
      _toast('操作失败: ${result.message}', isError: true);
    }
  }

  /// 卸载应用
  Future<void> uninstallApp() async {
    final service = ref.read(appManagementServiceProvider);
    final result = await service.uninstall(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已卸载应用: $_displayName');
      ref.read(packagesProvider(deviceId).notifier).refreshSinglePackage(_packageName);
    } else {
      _toast('卸载失败: ${result.message}', isError: true);
    }
  }

  // ==================== 2. ADB 调试运行 (Debug Operations) ====================

  /// 以调试模式启动应用 (等待调试器连接)
  Future<void> startAppWithDebugger() async {
    await _adb.shellArgs(deviceId, ['am', 'set-debug-app', '-w', _packageName]);
    final service = ref.read(appManagementServiceProvider);
    final result = await service.launch(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('以调试模式启动 (等待调试器): $_displayName');
    } else {
      _toast('调试模式启动失败: ${result.message}', isError: true);
    }
  }

  /// 以调试模式重启应用
  Future<void> restartAppWithDebugger() async {
    final service = ref.read(appManagementServiceProvider);
    await service.forceStop(deviceId, _packageName);
    await _adb.shellArgs(deviceId, ['am', 'set-debug-app', '-w', _packageName]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final result = await service.launch(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已重启并在调试模式下运行: $_displayName');
    } else {
      _toast('重启调试模式失败: ${result.message}', isError: true);
    }
  }

  /// 清除应用数据并以调试模式重启
  Future<void> clearAppDataAndRestartWithDebugger() async {
    final service = ref.read(appManagementServiceProvider);
    await service.clearData(deviceId, _packageName);
    await _adb.shellArgs(deviceId, ['am', 'set-debug-app', '-w', _packageName]);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final result = await service.launch(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已清除数据并在调试模式下启动: $_displayName');
    } else {
      _toast('启动失败: ${result.message}', isError: true);
    }
  }

  /// 清除调试模式标记 (恢复正常启动)
  Future<void> clearDebugApp() async {
    final result = await _adb.shellArgs(deviceId, ['am', 'clear-debug-app']);
    if (result.isSuccess) {
      _toast('已清除应用的调试等待标记');
    } else {
      _toast('清除调试标记失败: ${result.message}', isError: true);
    }
  }

  // ==================== 3. 权限快捷管理 (Permissions) ====================

  /// 一键授予全部运行时权限
  Future<void> grantAllPermissions() async {
    final permissionService = ref.read(appPermissionServiceProvider);
    _toast('正在一键授予权限...');
    final count = await permissionService.grantAllRuntimePermissions(
      deviceId,
      _packageName,
    );
    if (count > 0) {
      _toast('成功授予 $count 项运行时权限');
    } else {
      _toast('未发现待授予的运行时权限或已全部授权');
    }
  }

  /// 一键撤销/重置所有运行时权限
  Future<void> revokeAllPermissions() async {
    final permissionService = ref.read(appPermissionServiceProvider);
    _toast('正在一键重置权限...');
    final count = await permissionService.revokeAllRuntimePermissions(
      deviceId,
      _packageName,
    );
    if (count > 0) {
      _toast('成功撤销 $count 项运行时权限');
    } else {
      _toast('未发现已授权的运行时权限');
    }
  }

  /// 撤销权限并重启应用
  Future<void> revokePermissionsAndRestart() async {
    final permissionService = ref.read(appPermissionServiceProvider);
    _toast('正在撤销权限并重启...');
    await permissionService.revokeAllRuntimePermissions(deviceId, _packageName);
    final service = ref.read(appManagementServiceProvider);
    await service.forceStop(deviceId, _packageName);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final result = await service.launch(deviceId, _packageName);
    if (result.isSuccess) {
      _toast('已重置权限并重启应用: $_displayName');
    } else {
      _toast('重启应用失败: ${result.message}', isError: true);
    }
  }

  // ==================== 4. 扩展工具与系统交互 ====================

  /// 打开系统应用设置详情页
  Future<void> openSystemSettings() async {
    final service = ref.read(appManagementServiceProvider);
    final result = await service.openAppInfo(deviceId, _packageName);
    if (!result.isSuccess) {
      _toast('打开系统设置失败: ${result.message}', isError: true);
    }
  }

  /// 查看并复制应用 APK 路径
  Future<void> showPackagePath() async {
    final service = ref.read(appManagementServiceProvider);
    final result = await service.packagePath(deviceId, _packageName);
    if (result.isSuccess && result.stdout.trim().isNotEmpty) {
      final path = result.stdout.trim().replaceFirst('package:', '');
      _toast('APK 路径: $path');
    } else {
      _toast('获取安装路径失败: ${result.message}', isError: true);
    }
  }

  /// 导出 APK 到本地
  Future<void> exportApk() async {
    final directory = await getDirectoryPath();
    if (directory == null) return;

    final safeLabel = _displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final versionStr = package.versionName != null ? '_v${package.versionName}' : '';
    final localSavePath = '$directory/${safeLabel}$versionStr.apk';

    _toast('正在导出 APK 安装包...');
    final service = ref.read(appManagementServiceProvider);
    final result = await service.exportApk(
      deviceId,
      _packageName,
      localSavePath,
      apkPath: package.apkPath,
    );
    if (result.isSuccess) {
      _toast('APK 导出成功: $localSavePath');
    } else {
      _toast('导出失败: ${result.message}', isError: true);
    }
  }

  /// 备份应用数据到电脑
  Future<void> backupAppData() async {
    final directory = await getDirectoryPath();
    if (directory == null) return;

    _toast('正在备份应用数据...');
    final service = ref.read(appDataBackupServiceProvider);
    final result = await service.backupData(
      deviceId,
      _packageName,
      directory,
      displayName: _displayName,
      versionName: package.versionName,
    );
    if (result.isSuccess) {
      _toast('数据备份成功: ${result.stdout}');
    } else {
      _toast('备份失败: ${result.message}', isError: true);
    }
  }

  /// 从电脑恢复应用数据
  Future<void> restoreAppData() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'App data backup', extensions: ['ab', 'tar']),
      ],
    );
    if (file == null) return;

    _toast('正在恢复应用数据...');
    final service = ref.read(appDataBackupServiceProvider);
    final result = await service.restoreData(deviceId, _packageName, file.path);
    if (result.isSuccess) {
      _toast('数据恢复成功');
    } else {
      _toast('恢复失败: ${result.message}', isError: true);
    }
  }

  /// 开启此应用的虚拟副屏独立投屏
  Future<void> openAppMirroring() async {
    final windowTitle = context.l10n
        .t('screenMirrorTitle')
        .replaceAll('{name}', _displayName);

    final textureId = ref.read(activeEmbeddedMirrorProvider(deviceId));
    if (textureId != null) {
      await ref.read(activeEmbeddedMirrorProvider(deviceId).notifier).forceStop();
    }

    try {
      final overviewAsync = ref.read(deviceOverviewProvider(deviceId));
      final resolution = overviewAsync.maybeWhen(
        data: (overview) => overview.physicalResolution,
        orElse: () => null,
      );

      String vdResolution = '1080x1920';
      if (resolution != null && resolution.contains('x')) {
        final parts = resolution.split('x');
        if (parts.length == 2) {
          final w = int.tryParse(parts[0].trim());
          final h = int.tryParse(parts[1].trim());
          if (w != null && h != null) {
            final minSide = w < h ? w : h;
            final maxSide = w > h ? w : h;
            double scale = 1.0;
            if (maxSide > 1920) {
              scale = 1920 / maxSide;
            }
            final targetW = ((minSide * scale).toInt() ~/ 2) * 2;
            final targetH = ((maxSide * scale).toInt() ~/ 2) * 2;
            vdResolution = '${targetW}x$targetH';
          }
        }
      }

      final initialSize = resolveMirrorInitialWindowSize(vdResolution);
      final devReg = ref.read(deviceRegistryProvider);
      final matchingDev = devReg.firstWhere(
        (d) => d.id == deviceId,
        orElse: () => RegisteredDevice(id: deviceId, status: 'unknown', isOnline: false),
      );

      await createAdbManageWindow(
        arguments: {
          'type': 'mirror',
          'deviceId': deviceId,
          'deviceName': _displayName,
          'newDisplay': vdResolution,
          'startApp': _packageName,
          'isIos': matchingDev.isIos,
          'isHarmony': matchingDev.isHarmony,
        },
        frame: Offset.zero & initialSize,
        title: windowTitle,
      );
    } catch (e) {
      _toast('开启应用投屏失败: $e', isError: true);
    }
  }

  // ==================== 5. 设备网络快捷开关 ====================

  /// 开启或关闭 Wi-Fi
  Future<void> toggleWifi(bool enable) async {
    final cmd = enable ? 'enable' : 'disable';
    final result = await _adb.shellArgs(deviceId, ['svc', 'wifi', cmd]);
    if (result.isSuccess) {
      _toast(enable ? '已开启 Wi-Fi' : '已关闭 Wi-Fi');
    } else {
      _toast('切换 Wi-Fi 失败: ${result.message}', isError: true);
    }
  }

  /// 开启或关闭移动网络
  Future<void> toggleMobileData(bool enable) async {
    final cmd = enable ? 'enable' : 'disable';
    final result = await _adb.shellArgs(deviceId, ['svc', 'data', cmd]);
    if (result.isSuccess) {
      _toast(enable ? '已开启移动网络' : '已关闭移动网络');
    } else {
      _toast('切换移动网络失败: ${result.message}', isError: true);
    }
  }
}
