import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../mirror_session_status_bar.dart';
import '../mirror_toolbar_button.dart';

/// 投屏标题栏，将应用入口与工具按钮放在窗口拖拽手势之外。
///
/// [deviceName] 是窗口标题，[foregroundAppAction] 是可选的前台应用入口；
/// 状态参数控制音频标记、计时与按钮样式，回调交由窗口 Controller 处理。
/// [onTitleHoverChanged] 控制设备信息浮层，[onSettings] 为空时隐藏设置。
class MirrorWindowTitleBar extends StatelessWidget {
  const MirrorWindowTitleBar({
    super.key,
    required this.deviceName,
    required this.backgroundColor,
    required this.isIos,
    required this.isAudioForwarded,
    required this.isMirrorActive,
    required this.isAlwaysOnTop,
    required this.isFullScreen,
    required this.onTitleHoverChanged,
    required this.onRetry,
    required this.onToggleAlwaysOnTop,
    required this.onToggleFullScreen,
    this.foregroundAppAction,
    this.onSettings,
  });

  final String deviceName;
  final Color backgroundColor;
  final bool isIos;
  final bool isAudioForwarded;
  final bool isMirrorActive;
  final bool isAlwaysOnTop;
  final bool isFullScreen;
  final ValueChanged<bool> onTitleHoverChanged;
  final VoidCallback onRetry;
  final VoidCallback onToggleAlwaysOnTop;
  final VoidCallback onToggleFullScreen;
  final Widget? foregroundAppAction;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).appColors.toolbarForeground;
    return Container(
      height: 30,
      padding: EdgeInsets.only(left: Platform.isMacOS ? 80 : 16, right: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 空白处可拖动；操作项先命中，避免父级拖拽或双击手势争抢点击。
          const DragToMoveArea(child: SizedBox.expand()),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: DragToMoveArea(
                        child: MouseRegion(
                          onEnter: (_) => onTitleHoverChanged(true),
                          onExit: (_) => onTitleHoverChanged(false),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: isIos
                                      ? '$deviceName · ${context.l10n.t('iosMirrorUsbNative')}'
                                      : deviceName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontSize: 16),
                                ),
                                if (isAudioForwarded)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.top,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Tooltip(
                                        message: context.l10n.t(
                                          'audioForwardingTooltip',
                                        ),
                                        child: Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    if (foregroundAppAction != null) ...[
                      const SizedBox(width: 8),
                      foregroundAppAction!,
                    ],
                  ],
                ),
              ),
              if (isMirrorActive) const MirrorSessionDuration(),
              MirrorToolbarButton(
                icon: Icon(CupertinoIcons.refresh, color: foreground, size: 16),
                tooltip: context.l10n.t('retry'),
                shortcut: MirrorShortcut.reconnect,
                onPressed: onRetry,
              ),
              MirrorToolbarButton(
                icon: Icon(
                  isAlwaysOnTop ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
                  color: isAlwaysOnTop ? Colors.orange : foreground,
                ),
                tooltip: context.l10n.t(
                  isAlwaysOnTop ? 'unpinAlwaysOnTop' : 'pinAlwaysOnTop',
                ),
                shortcut: MirrorShortcut.alwaysOnTop,
                onPressed: onToggleAlwaysOnTop,
              ),
              MirrorToolbarButton(
                icon: Icon(
                  isFullScreen
                      ? CupertinoIcons.fullscreen_exit
                      : CupertinoIcons.fullscreen,
                  color: foreground,
                ),
                tooltip: context.l10n.t(
                  isFullScreen ? 'exitFullScreen' : 'enterFullScreen',
                ),
                shortcut: MirrorShortcut.fullScreen,
                onPressed: onToggleFullScreen,
              ),
              if (onSettings != null)
                MirrorToolbarButton(
                  icon: Icon(CupertinoIcons.settings, color: foreground),
                  tooltip: context.l10n.t('mirrorQualitySettings'),
                  shortcut: MirrorShortcut.mirrorSettings,
                  onPressed: onSettings,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
