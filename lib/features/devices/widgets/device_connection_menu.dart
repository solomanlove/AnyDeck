import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import 'device_workspace_popup_menu.dart';

/// 设备管理的连接入口，按原型展示三个带图标的选项和独立 USB 提示。
///
/// [onSelected] 将 pair / tcp / share 交给宿主打开已有连接流程；组件不执行连接。
/// [showLabel] 控制窄窗口是否隐藏按钮文字，隐藏后仍保留完整 Tooltip。
/// 原生 PopupMenuButton 负责焦点、键盘及点击外部关闭，尺寸随字号和窗口适配。
class DeviceConnectionMenu extends StatelessWidget {
  const DeviceConnectionMenu({
    super.key,
    required this.onSelected,
    this.showLabel = true,
  });

  final ValueChanged<String> onSelected;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: AppThemeSizes.radiusMedium,
      child: DeviceWorkspacePopupMenu<String>(
        buttonKey: const Key('deviceConnectionButton'),
        tooltip: context.l10n.t('deviceWorkspaceConnect'),
        onSelected: onSelected,
        itemBuilder: (context) => [
          _item(context, 'pair', LucideIcons.wifi, 'deviceWorkspacePair'),
          _item(context, 'tcp', LucideIcons.link, 'deviceWorkspaceConnectIp'),
          _item(
            context,
            'share',
            LucideIcons.users,
            'deviceWorkspaceJoinShare',
          ),
          PopupMenuItem<String>(
            enabled: false,
            height: 0,
            padding: EdgeInsets.zero,
            child: Column(
              key: const Key('deviceConnectionUsbHint'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, color: scheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  child: Text(
                    context.l10n.t('deviceWorkspaceUsbHint'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.normal,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: AppThemeSizes.radiusMedium,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plus, size: 17, color: scheme.onPrimary),
              if (showLabel) ...[
                const SizedBox(width: 7),
                Text(
                  context.l10n.t('deviceWorkspaceConnect'),
                  style: TextStyle(fontSize: 13, color: scheme.onPrimary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(
    BuildContext context,
    String action,
    IconData icon,
    String labelKey,
  ) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return PopupMenuItem<String>(
      key: Key('deviceConnection-$action'),
      value: action,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.t(labelKey),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                height: 1.4,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
