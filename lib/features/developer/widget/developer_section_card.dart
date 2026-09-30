import 'package:flutter/material.dart';

/// 开发者选项页面统一的卡片容器组件。
///
/// 提供一致的圆角背景、边框、毛玻璃效果以及标题栏，
/// 支持右侧自定义操作按钮（如刷新、重置等）。
class DeveloperSectionCard extends StatelessWidget {
  /// 创建开发者卡片组件
  ///
  /// [title] 卡片大标题
  /// [icon] 标题前导图标
  /// [children] 卡片内容区域子组件列表
  /// [subtitle] 可选的副标题说明
  /// [trailing] 可选的标题栏右侧操作组件
  const DeveloperSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.trailing,
  });

  /// 卡片标题
  final String title;

  /// 前导图标
  final IconData icon;

  /// 副标题说明
  final String? subtitle;

  /// 标题栏右侧自定义组件
  final Widget? trailing;

  /// 子组件列表
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const brandGreen = Color(0xff09c47c);

    final cardBgColor = isDark
        ? const Color(0xff1e293b).withValues(alpha: 0.7)
        : Colors.white.withValues(alpha: 0.85);

    final borderColor = isDark
        ? const Color(0xff334155).withValues(alpha: 0.6)
        : const Color(0xffe2e8f0);

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部标题栏
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: brandGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: brandGreen, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          // 内容区域
          ...children,
        ],
      ),
    );
  }
}
