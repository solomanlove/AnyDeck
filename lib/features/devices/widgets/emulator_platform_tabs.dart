import 'package:flutter/material.dart';

/// 模拟器支持的平台类型。
enum EmulatorPlatform {
  /// Android AVD 模拟器
  android('Android'),

  /// 华为 HarmonyOS DevEco 模拟器
  harmony('HarmonyOS'),

  /// 苹果 iOS Xcode Simulator 模拟器
  ios('iOS');

  const EmulatorPlatform(this.label);

  /// 平台显示名称
  final String label;

  /// 平台附带前置图标（如 iOS 对应苹果 logo）
  IconData? get icon => switch (this) {
        ios => Icons.apple,
        _ => null,
      };
}

/// 模拟器平台胶囊分段选择器（Android / HarmonyOS / iOS）。
///
/// 遵循设计规范，以胶囊圆角边框承载三端模拟器 Tab 切换，激活项呈现微青绿胶囊高亮底色，
/// 并为 iOS 项增加专属 Apple 图标。
class EmulatorPlatformTabs extends StatelessWidget {
  /// 创建模拟器平台切换 Tab 组件。
  ///
  /// [selectedPlatform] 当前选中的平台类型；
  /// [onPlatformChanged] 切换平台时的回调。
  const EmulatorPlatformTabs({
    super.key,
    required this.selectedPlatform,
    required this.onPlatformChanged,
  });

  /// 当前选中的平台
  final EmulatorPlatform selectedPlatform;

  /// 平台切换回调
  final ValueChanged<EmulatorPlatform> onPlatformChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE2E8F0);

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: EmulatorPlatform.values.map((platform) {
          final isSelected = platform == selectedPlatform;
          return _TabItem(
            platform: platform,
            isSelected: isSelected,
            isDark: isDark,
            onTap: () => onPlatformChanged(platform),
          );
        }).toList(),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.platform,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final EmulatorPlatform platform;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 激活背景色与文字色（微青绿色调，契合主题）
    final activeBg = isDark
        ? const Color(0xFF007A56).withValues(alpha: 0.28)
        : const Color(0xFFE8F4EC);
    final activeColor = isDark
        ? const Color(0xFF6EE7B7)
        : const Color(0xFF1B4D3E);

    // 未激活文字色
    final inactiveColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF374151);

    final color = isSelected ? activeColor : inactiveColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      hoverColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (platform.icon != null) ...[
              Icon(
                platform.icon,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              platform.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: color,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
