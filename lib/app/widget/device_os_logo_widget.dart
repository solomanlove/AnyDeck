
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart' show PlatformDistributionType;
import 'package:flutter/material.dart';

/// 绘制各平台图标：直接复用项目中现成的 Android、华为与 Apple Logo
Widget buildPlatformIcon(PlatformDistributionType platform) {
  switch (platform) {
    case PlatformDistributionType.android:
      return Icon(
        Icons.android_rounded,
        size: 15,
        color: Color(0xff09c47c),
      );
    case PlatformDistributionType.harmony:
      return Image.asset(
        AppIcons.huaweiPetal,
        width: 15,
        height: 15,
        fit: BoxFit.contain,
      );
    case PlatformDistributionType.ios:
      return Icon(
        Icons.apple,
        size: 15,
        color: Colors.black,
      );
  }
}