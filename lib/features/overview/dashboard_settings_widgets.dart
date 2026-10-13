part of '../dashboard_screen.dart';

/// 设置页通用组件扩展，包含分组卡片、设置行、下拉胶囊选择器与动作链接。
extension _SettingsTabWidgets on _SettingsTab {
  /// 构建分组设置卡片，包含卡片外部标题与带圆角边框及分割线的卡片容器。
  ///
  /// [title]: 分组标题文案（如“常规”、“存储”、“通知”）。
  /// [children]: 分组内的各项设置行控件，将自动在各行之间插入微细分割线。
  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 过滤掉不可见的空控件，避免渲染多余的分割线
    final visibleChildren = children.where((child) {
      if (child is SizedBox &&
          (child.width == null || child.width == 0) &&
          (child.height == null || child.height == 0) &&
          child.child == null) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visibleChildren.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF1F5F9),
                  ),
                visibleChildren[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 构建标准设置行组件，左侧为标题与副标题，右侧为交互控件。
  ///
  /// [label]: 设置项主标题。
  /// [subtitle]: 设置项副标题，可选。若为空则不渲染副标题。
  /// [child]: 右侧交互控件（如开关、下拉胶囊或文本按钮组）。
  Widget _buildSettingRow(
    BuildContext context, {
    required String label,
    String? subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(child: textColumn),
          const SizedBox(width: 16),
          child,
        ],
      ),
    );
  }

  /// 构建现代 macOS / iOS 胶囊型下拉选择器。
  ///
  /// [value]: 当前选中的值。
  /// [items]: 下拉选项列表。
  /// [onChanged]: 选项变更回调，为 null 时表示禁用。
  Widget _buildDropdownSelector<T>(
    BuildContext context, {
    required T value,
    required List<_DropdownOption<T>> items,
    required ValueChanged<T>? onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentItem = items.firstWhere(
      (item) => item.value == value,
      orElse: () => items.first,
    );

    return PopupMenuButton<T>(
      initialValue: value,
      tooltip: '',
      enabled: onChanged != null,
      offset: const Offset(0, 34),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 4,
      onSelected: onChanged,
      itemBuilder: (context) => items
          .map(
            (item) => PopupMenuItem<T>(
              value: item.value,
              height: 34,
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: item.value == value
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: item.value == value
                      ? AppPalette.primary
                      : (isDark ? Colors.white : const Color(0xFF1E293B)),
                ),
              ),
            ),
          )
          .toList(),
      child: Opacity(
        opacity: onChanged == null ? 0.45 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentItem.label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_down,
                size: 12,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建现代文本链接按钮，支持悬停指针与自定义颜色。
  ///
  /// [text]: 按钮文案。
  /// [onTap]: 点击回调，为 null 时禁用。
  /// [color]: 文本颜色，默认系统蓝，危险操作传红色。
  Widget _buildTextActionButton({
    required String text,
    required VoidCallback? onTap,
    Color color = const Color(0xFF2563EB),
  }) {
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: onTap != null ? color : color.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// 下拉菜单选项数据模型。
class _DropdownOption<T> {
  const _DropdownOption({required this.value, required this.label});

  final T value;
  final String label;
}
