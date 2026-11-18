import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/apps/adb_package.dart';
import '../controller/mirror_app_quick_actions_controller.dart';
import '../../../l10n/app_localizations.dart';

/// 快捷操作项数据模型
class MirrorActionItemData {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDanger;

  const MirrorActionItemData({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.isDanger = false,
  });
}

/// 快捷操作分类区块数据模型
class MirrorActionSectionData {
  final int categoryIndex;
  final String title;
  final List<MirrorActionItemData> items;

  const MirrorActionSectionData({
    required this.categoryIndex,
    required this.title,
    required this.items,
  });
}

/// 构建前台应用所有的快捷操作区块数据
List<MirrorActionSectionData> buildMirrorAppQuickActionSections({
  required BuildContext context,
  required AdbPackage package,
  required MirrorAppQuickActionsController controller,
  required bool fusionEnabled,
}) {
  // 普通快捷操作使用主题主色，清数据和撤权等破坏性操作保留错误语义。
  final colors = Theme.of(context).colorScheme;
  return [
    // 1. 生命周期与基础控制
    MirrorActionSectionData(
      categoryIndex: 1,
      title: '应用生命周期',
      items: [
        MirrorActionItemData(
          icon: CupertinoIcons.play_circle,
          iconColor: colors.primary,
          title: '启动应用',
          subtitle: '运行并启动此应用的主界面',
          onTap: () {
            Navigator.of(context).pop();
            controller.launchApp();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.arrow_counterclockwise_circle,
          iconColor: colors.primary,
          title: '重启应用',
          subtitle: '强行停止后重新启动主界面',
          onTap: () {
            Navigator.of(context).pop();
            controller.restartApp();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.stop_circle,
          iconColor: colors.error,
          title: '强行停止',
          subtitle: '强行关闭此应用的所有后台进程',
          onTap: () {
            Navigator.of(context).pop();
            controller.forceStopApp();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.clear_circled,
          iconColor: colors.error,
          title: '清除数据',
          subtitle: '清除所有应用数据及缓存',
          onTap: () {
            Navigator.of(context).pop();
            controller.clearAppData();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.arrow_2_circlepath_circle,
          iconColor: colors.error,
          title: '清除数据并重启',
          subtitle: '清空应用数据并重新拉起主界面',
          onTap: () {
            Navigator.of(context).pop();
            controller.clearAppDataAndRestart();
          },
        ),
        MirrorActionItemData(
          icon: package.enabled ? CupertinoIcons.snow : CupertinoIcons.flame,
          iconColor: colors.primary,
          title: package.enabled ? '冻结应用' : '解冻应用',
          subtitle: package.enabled ? '禁用并隐藏此应用' : '恢复并启用此应用',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleFreezeApp();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.trash,
          iconColor: colors.error,
          title: '卸载应用',
          subtitle: '从设备中彻底卸载并删除此应用',
          isDanger: true,
          onTap: () {
            Navigator.of(context).pop();
            controller.uninstallApp();
          },
        ),
      ],
    ),

    // 2. ADB 调试运行
    MirrorActionSectionData(
      categoryIndex: 2,
      title: 'ADB 调试运行',
      items: [
        MirrorActionItemData(
          icon: CupertinoIcons.ant,
          iconColor: colors.primary,
          title: '调试模式启动',
          subtitle: '设置调试等待标记并启动 (等待 Debugger)',
          onTap: () {
            Navigator.of(context).pop();
            controller.startAppWithDebugger();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.ant_fill,
          iconColor: colors.primary,
          title: '调试模式重启',
          subtitle: '强停后以调试器连接模式重新启动',
          onTap: () {
            Navigator.of(context).pop();
            controller.restartAppWithDebugger();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.ant_circle,
          iconColor: colors.error,
          title: '清除数据并调试重启',
          subtitle: '清空数据后以等待调试器模式重新启动',
          onTap: () {
            Navigator.of(context).pop();
            controller.clearAppDataAndRestartWithDebugger();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.slash_circle,
          iconColor: colors.primary,
          title: '清除调试等待标记',
          subtitle: '取消应用的调试等待标记 (am clear-debug-app)',
          onTap: () {
            Navigator.of(context).pop();
            controller.clearDebugApp();
          },
        ),
      ],
    ),

    // 3. 权限快捷管理
    MirrorActionSectionData(
      categoryIndex: 3,
      title: '权限控制',
      items: [
        MirrorActionItemData(
          icon: CupertinoIcons.checkmark_shield,
          iconColor: colors.primary,
          title: '授予全部权限',
          subtitle: '一键授予应用声明的所有运行时权限',
          onTap: () {
            Navigator.of(context).pop();
            controller.grantAllPermissions();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.lock_open,
          iconColor: colors.error,
          title: '重置全部权限',
          subtitle: '一键撤销当前应用的所有运行时权限',
          onTap: () {
            Navigator.of(context).pop();
            controller.revokeAllPermissions();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.arrow_2_circlepath,
          iconColor: colors.error,
          title: '重置权限并重启',
          subtitle: '撤销所有运行时权限并立即重启应用',
          onTap: () {
            Navigator.of(context).pop();
            controller.revokePermissionsAndRestart();
          },
        ),
      ],
    ),

    // 4. 扩展工具
    MirrorActionSectionData(
      categoryIndex: 4,
      title: '扩展工具',
      items: [
        MirrorActionItemData(
          icon: Icons.cast,
          iconColor: colors.primary,
          title: context.l10n.t(
            fusionEnabled ? 'fusionAppTooltip' : 'primaryAppTooltip',
          ),
          subtitle: context.l10n.t('fusionMirrorActionHint'),
          onTap: () {
            Navigator.of(context).pop();
            controller.openAppMirroring();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.settings,
          iconColor: colors.primary,
          title: '系统应用详情',
          subtitle: '在手机中打开此应用系统设置详情页',
          onTap: () {
            Navigator.of(context).pop();
            controller.openSystemSettings();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.arrow_merge,
          iconColor: colors.primary,
          title: '查看安装路径',
          subtitle: '获取 APK 在设备中的物理存储路径',
          onTap: () {
            Navigator.of(context).pop();
            controller.showPackagePath();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.cloud_download,
          iconColor: colors.primary,
          title: '导出 APK',
          subtitle: '提取并保存 APK 安装包到本地电脑',
          onTap: () {
            Navigator.of(context).pop();
            controller.exportApk();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.archivebox,
          iconColor: colors.primary,
          title: '备份应用数据',
          subtitle: '备份此应用的数据到本地电脑',
          onTap: () {
            Navigator.of(context).pop();
            controller.backupAppData();
          },
        ),
        MirrorActionItemData(
          icon: Icons.restore,
          iconColor: colors.primary,
          title: '恢复应用数据',
          subtitle: '从本地备份文件中恢复应用数据',
          onTap: () {
            Navigator.of(context).pop();
            controller.restoreAppData();
          },
        ),
      ],
    ),

    // 5. 设备网络控制
    MirrorActionSectionData(
      categoryIndex: 5,
      title: '网络控制',
      items: [
        MirrorActionItemData(
          icon: CupertinoIcons.wifi,
          iconColor: colors.primary,
          title: '开启 Wi-Fi',
          subtitle: '通过 ADB 指令开启设备无线局域网',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleWifi(true);
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.wifi_slash,
          iconColor: colors.primary,
          title: '关闭 Wi-Fi',
          subtitle: '通过 ADB 指令关闭设备无线局域网',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleWifi(false);
          },
        ),
        MirrorActionItemData(
          icon: Icons.network_cell,
          iconColor: colors.primary,
          title: '开启移动网络',
          subtitle: '通过 ADB 指令开启设备蜂窝移动数据',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleMobileData(true);
          },
        ),
        MirrorActionItemData(
          icon: Icons.signal_cellular_off,
          iconColor: colors.primary,
          title: '关闭移动网络',
          subtitle: '通过 ADB 指令关闭设备蜂窝移动数据',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleMobileData(false);
          },
        ),
      ],
    ),
  ];
}
