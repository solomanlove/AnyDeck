import 'dart:ui';
import 'package:flutter/material.dart';

/// 公共自适应高度的毛玻璃容器卡片，提供统一的半透明模糊、圆角及边框视觉质感。
///
/// 用于在各个设备控制页面（Android/HarmonyOS）中归类包裹成组的操作或状态。
class GlassSectionCard extends StatelessWidget {
  /// 构造公共毛玻璃卡片
  ///
  /// [title] 卡片顶部标题
  /// [icon] 标题左侧的装饰图标
  /// [children] 卡片内部展示的子控件列表
  /// [trailing] 可选的标题右侧控件（如操作按钮或开关）
  const GlassSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  /// 卡片标题
  final String title;

  /// 卡片头部图标
  final IconData icon;

  /// 卡片内容子控件列表
  final List<Widget> children;

  /// 标题栏尾部可选控件
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (trailing != null) ...[
                      const Spacer(),
                      trailing!,
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
