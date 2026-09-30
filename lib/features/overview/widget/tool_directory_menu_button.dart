import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../devices/controller/platform_tools_controller.dart';

/// 跨平台调试工具目录打开按钮组件。
///
/// 支持一键定位打开 Android (ADB)、鸿蒙 (HDC) 以及 iOS (go-ios) 的可执行文件所在目录，
/// 或在终端中打开该目录以执行底层命令行操作。
class ToolDirectoryMenuButton extends ConsumerWidget {
  const ToolDirectoryMenuButton({
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
      tooltip: context.l10n.t('openToolDir'),
      icon: const Icon(CupertinoIcons.folder),
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
          case 'adb_dir':
            PlatformToolsController.openToolDirectory(
              context,
              ref,
              'adb',
              terminal: false,
            );
            break;
          case 'adb_terminal':
            PlatformToolsController.openToolDirectory(
              context,
              ref,
              'adb',
              terminal: true,
            );
            break;
          case 'hdc_dir':
            PlatformToolsController.openToolDirectory(
              context,
              ref,
              'hdc',
              terminal: false,
            );
            break;
          case 'hdc_terminal':
            PlatformToolsController.openToolDirectory(
              context,
              ref,
              'hdc',
              terminal: true,
            );
            break;
          case 'ios_dir':
            PlatformToolsController.openToolDirectory(
              context,
              ref,
              'ios',
              terminal: false,
            );
            break;
          case 'ios_terminal':
            PlatformToolsController.openToolDirectory(
              context,
              ref,
              'ios',
              terminal: true,
            );
            break;
        }
      },
      itemBuilder: (context) => [
        // --- Android (ADB) ---
        PopupMenuItem(
          value: 'adb_dir',
          child: Row(
            children: [
              const Icon(CupertinoIcons.folder, size: 18),
              const SizedBox(width: 10),
              Text(context.l10n.t('openAdbDir')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'adb_terminal',
          child: Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 18),
              const SizedBox(width: 10),
              Text(context.l10n.t('openAdbTerminal')),
            ],
          ),
        ),
        const PopupMenuDivider(),

        // --- HarmonyOS (HDC) ---
        PopupMenuItem(
          value: 'hdc_dir',
          child: Row(
            children: [
              const Icon(CupertinoIcons.folder, size: 18),
              const SizedBox(width: 10),
              Text(context.l10n.t('openHdcDir')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'hdc_terminal',
          child: Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 18),
              const SizedBox(width: 10),
              Text(context.l10n.t('openHdcTerminal')),
            ],
          ),
        ),
        const PopupMenuDivider(),

        // --- iOS (go-ios) ---
        PopupMenuItem(
          value: 'ios_dir',
          child: Row(
            children: [
              const Icon(CupertinoIcons.folder, size: 18),
              const SizedBox(width: 10),
              Text(context.l10n.t('openIosDir')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'ios_terminal',
          child: Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 18),
              const SizedBox(width: 10),
              Text(context.l10n.t('openIosTerminal')),
            ],
          ),
        ),
      ],
    );
  }
}
