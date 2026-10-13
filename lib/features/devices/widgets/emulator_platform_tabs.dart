import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_icon.dart';

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

  /// 平台附带前置矢量图标（Android 机器人、Apple 图标）
  IconData? get icon => switch (this) {
        android => Icons.android_rounded,
        ios => Icons.apple,
        _ => null,
      };

  /// 平台附带的自定义资产图片路径（华为花瓣 Logo）
  String? get imageAsset => switch (this) {
        harmony => AppIcons.huaweiPetal,
        _ => null,
      };
}

/// 模拟器平台分段选择器（Android / HarmonyOS / iOS）。
///
/// 遵循应用和进程 Tab 的统一分段设计规范，采用 [CupertinoSlidingSegmentedControl]，
/// 选中项呈现纯白圆角浮起卡片与主题主色高亮文本，未选中项以垂直分割线区分。
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final segments = <EmulatorPlatform, Widget>{
      for (final platform in EmulatorPlatform.values)
        platform: _buildSegmentItem(
          context,
          platform,
          platform == selectedPlatform,
        ),
    };

    return CupertinoSlidingSegmentedControl<EmulatorPlatform>(
      groupValue: selectedPlatform,
      backgroundColor: isDark
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : const Color(0xFFF1F5F9),
      thumbColor: isDark
          ? theme.colorScheme.surfaceContainerHigh
          : Colors.white,
      padding: const EdgeInsets.all(3),
      children: segments,
      onValueChanged: (val) {
        if (val != null) {
          onPlatformChanged(val);
        }
      },
    );
  }

  /// 构建单个平台分段项，与应用和进程 Tab 的 Segment 样式完全保持一致。
  Widget _buildSegmentItem(
    BuildContext context,
    EmulatorPlatform platform,
    bool isSelected,
  ) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (platform.icon != null) ...[
            Icon(platform.icon, size: 15, color: color),
            const SizedBox(width: 2),
          ] else if (platform.imageAsset != null) ...[
            Image.asset(
              platform.imageAsset!,
              width: 14,
              height: 14,
              fit: BoxFit.contain,
              color: color,
            ),
            const SizedBox(width: 2),
          ],
          Text(
            platform.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
