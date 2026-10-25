import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// DLNA 视频回退窗口的置顶开关；文案由主窗口当前语言传入。
class DlnaPinButton extends StatelessWidget {
  const DlnaPinButton({
    super.key,
    required this.pinned,
    required this.pinLabel,
    required this.unpinLabel,
    required this.onPressed,
  });

  /// 当前窗口是否处于置顶层级。
  final bool pinned;

  /// 未置顶时的 Tooltip 文案。
  final String pinLabel;

  /// 已置顶时的 Tooltip 文案。
  final String unpinLabel;

  /// 点击后切换窗口层级，忙碌时传入 null。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: pinned ? unpinLabel : pinLabel,
      onPressed: onPressed,
      icon: Icon(pinned ? CupertinoIcons.pin_fill : CupertinoIcons.pin),
      color: pinned ? colors.primary : colors.onSurface,
      style: IconButton.styleFrom(
        backgroundColor: colors.surface.withValues(alpha: 0.85),
      ),
    );
  }
}
