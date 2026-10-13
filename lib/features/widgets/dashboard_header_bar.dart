import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/window/widget/desktop_workspace_surface.dart';
import 'dashboard_header_title.dart';

export 'dashboard_header_title.dart';

/// 仪表盘一级模块页面顶部统一标准标题栏。
///
/// 封装 72px 标准高度、原生窗口拖拽（[DragToMoveArea]）、桌面工作区毛玻璃背景（[DesktopWorkspaceSurface]）
/// 以及统一的底部边框线。左侧采用规范的 [DashboardHeaderTitle]（圆形主题色图标徽章 + 粗体主标题 + 柔和副标题），
/// 右侧支持灵活承载各页面的操作工具栏、平台切换或状态标识。
///
/// 适用于“设备管理”、“模拟器管理”、“AI MCP”、“设置”等所有仪表盘顶级模块页面。
///
/// 示例：
/// ```dart
/// DashboardHeaderBar(
///   title: context.l10n.t('devices'),
///   subtitle: context.l10n.t('devicesSubtitle'),
///   icon: Icons.devices_rounded,
///   actions: [ ... ],
/// )
/// ```
class DashboardHeaderBar extends StatelessWidget {
  /// 创建仪表盘一级模块页面顶部统一标准标题栏。
  ///
  /// [title] 主标题文本；
  /// [subtitle] 副标题描述文本；
  /// [icon] 左侧圆形徽章内部图标；
  /// [badgeSize] 徽标外圈圆形直径，默认 48.0；
  /// [iconSize] 徽标内部图标尺寸，默认 26.0；
  /// [trailing] 标题栏右侧自定义组件（例如平台切换 Tabs 或状态徽章）；
  /// [actions] 标题栏右侧动作按钮组列表（与 [trailing] 互斥或排在 [trailing] 之后）；
  /// [padding] 标题栏内边距，默认水平 28；
  /// [height] 标题栏高度，默认 72.0。
  const DashboardHeaderBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badgeSize = 48.0,
    this.iconSize = 26.0,
    this.trailing,
    this.actions,
    this.padding = const EdgeInsets.symmetric(horizontal: 28),
    this.height = 72.0,
  });

  /// 页面主标题
  final String title;

  /// 页面副标题
  final String subtitle;

  /// 徽标图标
  final IconData icon;

  /// 徽标外圈圆形直径
  final double badgeSize;

  /// 徽标内部图标尺寸
  final double iconSize;

  /// 右侧单个尾随组件
  final Widget? trailing;

  /// 右侧操作按钮列表
  final List<Widget>? actions;

  /// 内边距
  final EdgeInsetsGeometry padding;

  /// 标题栏固定高度
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DragToMoveArea(
      child: DesktopWorkspaceSurface(
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          padding: padding,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: DashboardHeaderTitle(
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  badgeSize: badgeSize,
                  iconSize: iconSize,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 16),
                trailing!,
              ],
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(width: 16),
                for (var i = 0; i < actions!.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions![i],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
