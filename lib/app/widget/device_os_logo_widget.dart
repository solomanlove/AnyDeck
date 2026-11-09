
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart' show PlatformDistributionType;
import 'package:flutter/material.dart';

/// 绘制统一的平台 Logo；[size] 指定边长，默认 15px，兼容现有平台 Tab。
/// Android 保留品牌绿色，Huawei 使用原色位图，Apple 随主题保持对比度。
Widget buildPlatformIcon(
  PlatformDistributionType platform, {
  double size = 15,
}) {
  switch (platform) {
    case PlatformDistributionType.android:
      return Icon(Icons.android_rounded, size: size, color: AppPalette.primary);
    case PlatformDistributionType.harmony:
      return Image.asset(
        AppIcons.huaweiPetal,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    case PlatformDistributionType.ios:
      return Builder(
        builder: (context) => Icon(
          Icons.apple,
          size: size,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
  }
}
