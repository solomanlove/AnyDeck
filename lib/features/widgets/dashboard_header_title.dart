import 'package:flutter/material.dart';

/// 仪表盘页面顶部标题组件。
///
/// 规范化呈现页面主标题，包含左侧圆形主题色徽标图标、粗体页面主标题以及下方弱化的功能副标题。
/// 适用于“设备管理”、“模拟器管理”等一级功能模块的顶部标题栏区域。
///
/// 示例：
/// ```dart
/// DashboardHeaderTitle(
///   title: context.l10n.t('devices'),
///   subtitle: context.l10n.t('devicesSubtitle'),
///   icon: Icons.devices_rounded,
/// )
/// ```
class DashboardHeaderTitle extends StatelessWidget {
  /// 创建仪表盘页面顶部标题组件。
  ///
  /// [title] 为主标题文案，例如“设备管理”；
  /// [subtitle] 为功能描述副标题，例如“统一管理 Android、HarmonyOS 与 iOS 设备”；
  /// [icon] 为徽标内部图标，默认为 [Icons.devices_rounded]；
  /// [badgeSize] 为圆形徽标直径，默认 48；
  /// [iconSize] 为徽标内部图标尺寸，默认 26。
  const DashboardHeaderTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.devices_rounded,
    this.badgeSize = 48.0,
    this.iconSize = 26.0,
  });

  /// 页面主标题
  final String title;

  /// 页面副标题描述
  final String subtitle;

  /// 圆形徽标内展示的图标
  final IconData icon;

  /// 圆形徽标的直径大小
  final double badgeSize;

  /// 图标尺寸
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 徽标背景与图标色：浅色模式下采用淡青绿底（#D1FAE5）与深青绿图标（#007A56），深色模式下自适应降低高光并提高图标对比度
    final badgeBgColor = isDark
        ? const Color(0xff007a56).withValues(alpha: 0.25)
        : const Color(0xffd1fae5);
    final badgeIconColor = isDark
        ? const Color(0xff34d399)
        : const Color(0xff007a56);

    // 主标题与副标题颜色：主标题高对比度加粗，副标题柔和弱化
    final titleColor = isDark
        ? const Color(0xffeceff1)
        : const Color(0xff17211f);
    final subtitleColor = isDark
        ? const Color(0xff94a3b8)
        : const Color(0xff64748b);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: badgeSize,
          height: badgeSize,
          decoration: BoxDecoration(
            color: badgeBgColor,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: iconSize,
            color: badgeIconColor,
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: subtitleColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
