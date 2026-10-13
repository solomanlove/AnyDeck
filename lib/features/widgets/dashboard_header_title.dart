import 'package:flutter/material.dart';

/// 仪表盘页面顶部标题组件。
///
/// 规范化呈现页面主标题与功能描述副标题，采用干净的左对齐纯文本排版，
/// 使头部与内容列形成一致的竖直对齐线。
/// 适用于“设备管理”、“模拟器管理”、“AI MCP”、“设置”等一级功能模块的顶部标题栏区域。
///
/// 示例：
/// ```dart
/// DashboardHeaderTitle(
///   title: context.l10n.t('devices'),
///   subtitle: context.l10n.t('devicesSubtitle'),
/// )
/// ```
class DashboardHeaderTitle extends StatelessWidget {
  /// 创建仪表盘页面顶部标题组件。
  ///
  /// [title] 为主标题文案，例如“设备管理”；
  /// [subtitle] 为功能描述副标题，例如“统一管理 Android、HarmonyOS 与 iOS 设备”；
  /// [icon]、[badgeSize]、[iconSize] 为向后兼容保留的可选参数，不再渲染图标徽标。
  const DashboardHeaderTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.badgeSize = 48.0,
    this.iconSize = 26.0,
  });

  /// 页面主标题
  final String title;

  /// 页面副标题描述
  final String subtitle;

  /// 向后兼容保留参数
  final IconData? icon;

  /// 向后兼容保留参数
  final double badgeSize;

  /// 向后兼容保留参数
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 主标题与副标题颜色：主标题高对比度加粗，副标题柔和弱化
    final titleColor = isDark
        ? const Color(0xffeceff1)
        : const Color(0xff17211f);
    final subtitleColor = isDark
        ? const Color(0xff94a3b8)
        : const Color(0xff64748b);

    return Column(
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
    );
  }
}
