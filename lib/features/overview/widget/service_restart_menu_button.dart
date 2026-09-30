import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../devices/controller/platform_tools_controller.dart';

/// 跨平台调试服务重启与在线设备重启按钮组件。
///
/// 取代原有的单 ADB 重启按钮，支持一键重启全部调试服务、单独重启 Android (ADB)、
/// 鸿蒙 (HDC) 服务端与重置 iOS (go-ios) 调试服务，并支持一键重启所有在线设备。
class ServiceRestartMenuButton extends ConsumerWidget {
  const ServiceRestartMenuButton({
    super.key,
    required this.iconColor,
  });

  /// 图标展示颜色
  final Color iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final popupBgColor = isDark
        ? const Color(0xff1e222d)
        : Colors.white;
    final popupBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return PopupMenuButton<String>(
      tooltip: context.l10n.t('restartServices'),
      icon: const Icon(CupertinoIcons.restart),
      iconSize: 30,
      color: popupBgColor,
      elevation: 6,
      offset: const Offset(0, 52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: popupBorderColor, width: 1),
      ),
      style: IconButton.styleFrom(
        foregroundColor: iconColor,
        fixedSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      onSelected: (value) {
        switch (value) {
          case 'restart_all':
            PlatformToolsController.restartPlatformService(
              context,
              ref,
              PlatformServiceType.all,
            );
            break;
          case 'restart_adb':
            PlatformToolsController.restartPlatformService(
              context,
              ref,
              PlatformServiceType.adb,
            );
            break;
          case 'restart_hdc':
            PlatformToolsController.restartPlatformService(
              context,
              ref,
              PlatformServiceType.hdc,
            );
            break;
          case 'restart_ios':
            PlatformToolsController.restartPlatformService(
              context,
              ref,
              PlatformServiceType.ios,
            );
            break;
          case 'reboot_devices':
            PlatformToolsController.rebootAllOnlineDevices(
              context,
              ref,
            );
            break;
        }
      },
      itemBuilder: (context) => [
        // --- 一键重启所有服务 ---
        PopupMenuItem(
          value: 'restart_all',
          child: Row(
            children: [
              const Icon(CupertinoIcons.bolt_fill, size: 18, color: Color(0xfff59e0b)),
              const SizedBox(width: 10),
              Text(
                context.l10n.t('restartAllServices'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),

        // --- Android ADB ---
        PopupMenuItem(
          value: 'restart_adb',
          child: Row(
            children: [
              const Icon(Icons.android_rounded, size: 18, color: Color(0xff3ddc84)),
              const SizedBox(width: 10),
              Text(context.l10n.t('restartAdb')),
            ],
          ),
        ),

        // --- HarmonyOS HDC ---
        PopupMenuItem(
          value: 'restart_hdc',
          child: Row(
            children: [
              const Icon(CupertinoIcons.circle_grid_hex_fill, size: 18, color: Color(0xffe53935)),
              const SizedBox(width: 10),
              Text(context.l10n.t('restartHdc')),
            ],
          ),
        ),

        // --- iOS (go-ios) ---
        PopupMenuItem(
          value: 'restart_ios',
          child: Row(
            children: [
              const Icon(Icons.apple_rounded, size: 18, color: Color(0xff007aff)),
              const SizedBox(width: 10),
              Text(context.l10n.t('restartIos')),
            ],
          ),
        ),
        const PopupMenuDivider(),

        // --- 一键重启所有在线设备 ---
        PopupMenuItem(
          value: 'reboot_devices',
          child: Row(
            children: [
              const Icon(CupertinoIcons.device_phone_portrait, size: 18),
              const SizedBox(width: 10),
              Text(context.l10n.t('rebootOnlineDevices')),
            ],
          ),
        ),
      ],
    );
  }
}
