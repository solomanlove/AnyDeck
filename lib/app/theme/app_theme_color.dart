import 'package:flutter/material.dart';

import 'app_palette.dart';

/// 可持久化的主题主色；绿色沿用 AnyDeck 原有配色，状态色独立保留。
enum AppThemeColor {
  green(AppPalette.primary, 'themeColorGreen'),
  blue(Color(0xff2563eb), 'themeColorBlue'),
  purple(Color(0xff7c3aed), 'themeColorPurple'),
  orange(Color(0xffc2410c), 'themeColorOrange'),
  pink(Color(0xffdb2777), 'themeColorPink'),
  teal(Color(0xff0d9488), 'themeColorTeal');

  const AppThemeColor(this.color, this.labelKey);

  final Color color;
  final String labelKey;

  /// 兼容旧版本和无效存储值，始终回退到原有绿色。
  static AppThemeColor fromName(String? name) {
    return values.where((value) => value.name == name).firstOrNull ?? green;
  }
}
