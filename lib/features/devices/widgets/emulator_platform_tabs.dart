import 'package:flutter/material.dart';

import '../../../app/theme/app_icon.dart';
import '../../overview/model/platform_distribution_type.dart';
import '../../overview/widget/platform_version_switcher.dart';

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
/// 复用系统版本页的 [PlatformVersionSwitcher]，统一图标、选中态与 hover 样式。
/// 仅适配平台枚举，模拟器页面继续持有选中状态并执行原有平台切换。
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
    return PlatformVersionSwitcher(
      selectedPlatform: switch (selectedPlatform) {
        EmulatorPlatform.android => PlatformDistributionType.android,
        EmulatorPlatform.harmony => PlatformDistributionType.harmony,
        EmulatorPlatform.ios => PlatformDistributionType.ios,
      },
      onPlatformChanged: (platform) => onPlatformChanged(switch (platform) {
        PlatformDistributionType.android => EmulatorPlatform.android,
        PlatformDistributionType.harmony => EmulatorPlatform.harmony,
        PlatformDistributionType.ios => EmulatorPlatform.ios,
      }),
    );
  }
}
