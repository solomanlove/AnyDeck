import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// 设备工作区共用的菜单外壳，统一背景、边框、圆角及窗口内的自适应宽度。
///
/// [buttonKey] 标识实际菜单按钮，[tooltip] 提供入口说明；[enabled] 控制可用态。
/// [itemBuilder] 构建业务菜单项，[onSelected] 接收所选值，[child] 为触发入口。
/// [baseWidth] 为默认字号下的逻辑像素宽度，随字号放大并限制在窗口内。
/// [matchButtonWidth] 用于宽度由工具栏约束的入口，使菜单与入口两侧对齐。
/// 连接设备和分组入口均通过此组件复用同一套菜单样式。
class DeviceWorkspacePopupMenu<T> extends StatelessWidget {
  const DeviceWorkspacePopupMenu({
    super.key,
    required this.buttonKey,
    required this.tooltip,
    required this.itemBuilder,
    required this.onSelected,
    required this.child,
    this.enabled = true,
    this.baseWidth = 240,
    this.matchButtonWidth = false,
  });

  final Key buttonKey;
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final ValueChanged<T> onSelected;
  final Widget child;
  final bool enabled;
  final double baseWidth;
  final bool matchButtonWidth;

  @override
  Widget build(BuildContext context) {
    if (!matchButtonWidth) return _buildMenu(context);
    return LayoutBuilder(
      builder: (context, constraints) => _buildMenu(
        context,
        buttonWidth: constraints.hasBoundedWidth ? constraints.maxWidth : null,
      ),
    );
  }

  Widget _buildMenu(BuildContext context, {double? buttonWidth}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final menuWidth = (buttonWidth ?? baseWidth * textScale.clamp(1.0, 1.4))
        .clamp(0.0, math.max(0.0, MediaQuery.sizeOf(context).width - 16))
        .toDouble();
    return PopupMenuButton<T>(
      key: buttonKey,
      tooltip: tooltip,
      enabled: enabled,
      borderRadius: AppThemeSizes.radiusMedium,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: BoxConstraints.tightFor(width: menuWidth),
      menuPadding: const EdgeInsets.all(6),
      color: theme.appColors.panelSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: scheme.shadow.withValues(alpha: .18),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppThemeSizes.radiusLarge,
        side: BorderSide(
          color: scheme.outlineVariant,
          width: AppThemeSizes.borderWidth,
        ),
      ),
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      child: child,
    );
  }
}
