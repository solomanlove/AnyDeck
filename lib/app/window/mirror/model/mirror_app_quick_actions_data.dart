import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/apps/adb_package.dart';
import '../controller/mirror_app_quick_actions_controller.dart';

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
}) {
  return [
    // 1. 生命周期与基础控制
    MirrorActionSectionData(
      categoryIndex: 1,
      title: '应用生命周期',
      items: [
        MirrorActionItemData(
          icon: CupertinoIcons.play_circle,
          iconColor: const Color(0xFF2EC46B),
          title: '启动应用',
          subtitle: '运行并启动此应用的主界面',
          onTap: () {
            Navigator.of(context).pop();
            controller.launchApp();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.arrow_counterclockwise_circle,
          iconColor: const Color(0xFF00ACC1),
          title: '重启应用',
          subtitle: '强行停止后重新启动主界面',
          onTap: () {
            Navigator.of(context).pop();
            controller.restartApp();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.stop_circle,
          iconColor: const Color(0xFFE53935),
          title: '强行停止',
          subtitle: '强行关闭此应用的所有后台进程',
          onTap: () {
            Navigator.of(context).pop();
            controller.forceStopApp();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.clear_circled,
          iconColor: const Color(0xFFFB8C00),
          title: '清除数据',
          subtitle: '清除所有应用数据及缓存',
          onTap: () {
            Navigator.of(context).pop();
            controller.clearAppData();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.arrow_2_circlepath_circle,
          iconColor: const Color(0xFFF57C00),
          title: '清除数据并重启',
          subtitle: '清空应用数据并重新拉起主界面',
          onTap: () {
            Navigator.of(context).pop();
            controller.clearAppDataAndRestart();
          },
        ),
        MirrorActionItemData(
          icon: package.enabled ? CupertinoIcons.snow : CupertinoIcons.flame,
          iconColor: const Color(0xFF0288D1),
          title: package.enabled ? '冻结应用' : '解冻应用',
          subtitle: package.enabled ? '禁用并隐藏此应用' : '恢复并启用此应用',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleFreezeApp();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.trash,
          iconColor: const Color(0xFFD32F2F),
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
          iconColor: const Color(0xFF7E57C2),
          title: '调试模式启动',
          subtitle: '设置调试等待标记并启动 (等待 Debugger)',
          onTap: () {
            Navigator.of(context).pop();
            controller.startAppWithDebugger();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.ant_fill,
          iconColor: const Color(0xFF5E35B1),
          title: '调试模式重启',
          subtitle: '强停后以调试器连接模式重新启动',
          onTap: () {
            Navigator.of(context).pop();
            controller.restartAppWithDebugger();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.ant_circle,
          iconColor: const Color(0xFF8E24AA),
          title: '清除数据并调试重启',
          subtitle: '清空数据后以等待调试器模式重新启动',
          onTap: () {
            Navigator.of(context).pop();
            controller.clearAppDataAndRestartWithDebugger();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.slash_circle,
          iconColor: const Color(0xFF78909C),
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
          iconColor: const Color(0xFF43A047),
          title: '授予全部权限',
          subtitle: '一键授予应用声明的所有运行时权限',
          onTap: () {
            Navigator.of(context).pop();
            controller.grantAllPermissions();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.lock_open,
          iconColor: const Color(0xFFD81B60),
          title: '重置全部权限',
          subtitle: '一键撤销当前应用的所有运行时权限',
          onTap: () {
            Navigator.of(context).pop();
            controller.revokeAllPermissions();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.arrow_2_circlepath,
          iconColor: const Color(0xFFC2185B),
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
          iconColor: const Color(0xFF8E24AA),
          title: '应用独立副屏投屏',
          subtitle: '在独立的虚拟副屏中开启此应用投屏',
          onTap: () {
            Navigator.of(context).pop();
            controller.openAppMirroring();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.settings,
          iconColor: const Color(0xFF546E7A),
          title: '系统应用详情',
          subtitle: '在手机中打开此应用系统设置详情页',
          onTap: () {
            Navigator.of(context).pop();
            controller.openSystemSettings();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.arrow_merge,
          iconColor: const Color(0xFF00ACC1),
          title: '查看安装路径',
          subtitle: '获取 APK 在设备中的物理存储路径',
          onTap: () {
            Navigator.of(context).pop();
            controller.showPackagePath();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.cloud_download,
          iconColor: const Color(0xFF3949AB),
          title: '导出 APK',
          subtitle: '提取并保存 APK 安装包到本地电脑',
          onTap: () {
            Navigator.of(context).pop();
            controller.exportApk();
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.archivebox,
          iconColor: const Color(0xFF5E35B1),
          title: '备份应用数据',
          subtitle: '备份此应用的数据到本地电脑',
          onTap: () {
            Navigator.of(context).pop();
            controller.backupAppData();
          },
        ),
        MirrorActionItemData(
          icon: Icons.restore,
          iconColor: const Color(0xFF039BE5),
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
          iconColor: const Color(0xFF00897B),
          title: '开启 Wi-Fi',
          subtitle: '通过 ADB 指令开启设备无线局域网',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleWifi(true);
          },
        ),
        MirrorActionItemData(
          icon: CupertinoIcons.wifi_slash,
          iconColor: const Color(0xFFE53935),
          title: '关闭 Wi-Fi',
          subtitle: '通过 ADB 指令关闭设备无线局域网',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleWifi(false);
          },
        ),
        MirrorActionItemData(
          icon: Icons.network_cell,
          iconColor: const Color(0xFF1E88E5),
          title: '开启移动网络',
          subtitle: '通过 ADB 指令开启设备蜂窝移动数据',
          onTap: () {
            Navigator.of(context).pop();
            controller.toggleMobileData(true);
          },
        ),
        MirrorActionItemData(
          icon: Icons.signal_cellular_off,
          iconColor: const Color(0xFFD81B60),
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
