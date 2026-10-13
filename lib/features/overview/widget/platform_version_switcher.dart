import 'package:flutter/material.dart';

import '../../../app/theme/app_icon.dart';
import '../model/platform_distribution_type.dart';

/// 平台版本切换器组件（对齐原型设计稿中的 .pswitch 控件）。
///
/// 用于在「Android 平台与 API 分布」、「HarmonyOS 版本与 API 分布」以及
/// 「iOS 版本采用率与工具链」三大独立视图之间进行无缝切换。
/// 直接复用项目中现成的 Android、华为与 Apple 品牌 Logo 素材。
///
/// **用法示例**：
/// ```dart
/// PlatformVersionSwitcher(
///   selectedPlatform: PlatformDistributionType.android,
///   onPlatformChanged: (platform) {
///     setState(() => _currentPlatform = platform);
///   },
/// )
/// ```
class PlatformVersionSwitcher extends StatelessWidget {
  /// 构造函数
  const PlatformVersionSwitcher({
    super.key,
    required this.selectedPlatform,
    required this.onPlatformChanged,
  });

  /// 当前选中的平台类型
  final PlatformDistributionType selectedPlatform;

  /// 用户切换平台时的回调函数，参数为选中的新平台
  final ValueChanged<PlatformDistributionType> onPlatformChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 容器背景与边框颜色（自适应深浅主题）
    final containerBg = isDark ? const Color(0xFF202226) : const Color(0xFFE5E7EB);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildItem(
            context: context,
            platform: PlatformDistributionType.android,
            isDark: isDark,
          ),
          _buildDivider(isDark),
          _buildItem(
            context: context,
            platform: PlatformDistributionType.harmony,
            isDark: isDark,
          ),
          _buildDivider(isDark),
          _buildItem(
            context: context,
            platform: PlatformDistributionType.ios,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  /// 选项间细分割线
  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.1),
    );
  }

  /// 构建单个平台切换项
  Widget _buildItem({
    required BuildContext context,
    required PlatformDistributionType platform,
    required bool isDark,
  }) {
    final isSelected = selectedPlatform == platform;

    final selectedBg = isDark ? const Color(0xFF383B40) : Colors.white;
    final selectedFg = isDark ? Colors.white : const Color(0xFF1F2328);
    final unselectedFg = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF57606A);

    return _HoverablePlatformItem(
      isSelected: isSelected,
      selectedBg: selectedBg,
      selectedFg: selectedFg,
      unselectedFg: unselectedFg,
      isDark: isDark,
      platform: platform,
      onTap: () => onPlatformChanged(platform),
    );
  }
}

/// 支持悬浮 hover 响应的子项
class _HoverablePlatformItem extends StatefulWidget {
  const _HoverablePlatformItem({
    required this.isSelected,
    required this.selectedBg,
    required this.selectedFg,
    required this.unselectedFg,
    required this.isDark,
    required this.platform,
    required this.onTap,
  });

  final bool isSelected;
  final Color selectedBg;
  final Color selectedFg;
  final Color unselectedFg;
  final bool isDark;
  final PlatformDistributionType platform;
  final VoidCallback onTap;

  @override
  State<_HoverablePlatformItem> createState() => _HoverablePlatformItemState();
}

class _HoverablePlatformItemState extends State<_HoverablePlatformItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color? bgColor;
    if (widget.isSelected) {
      bgColor = widget.selectedBg;
    } else if (_isHovered) {
      bgColor = widget.isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.05);
    } else {
      bgColor = Colors.transparent;
    }

    final textColor = widget.isSelected ? widget.selectedFg : widget.unselectedFg;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: widget.isDark ? 0.25 : 0.08,
                      ),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPlatformIcon(widget.platform),
              const SizedBox(width: 6),
              Text(
                widget.platform.displayName,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 绘制各平台图标：直接复用项目中现成的 Android、华为与 Apple Logo
  Widget _buildPlatformIcon(PlatformDistributionType platform) {
    switch (platform) {
      case PlatformDistributionType.android:
        return Image.asset(
          AppIcons.androidDefaultAppIcon,
          width: 15,
          height: 15,
          fit: BoxFit.contain,
        );
      case PlatformDistributionType.harmony:
        return Image.asset(
          AppIcons.huaweiPetal,
          width: 15,
          height: 15,
          fit: BoxFit.contain,
        );
      case PlatformDistributionType.ios:
        return Image.asset(
          AppIcons.apple,
          width: 15,
          height: 15,
          fit: BoxFit.contain,
          color: widget.isSelected ? widget.selectedFg : widget.unselectedFg,
        );
    }
  }
}
