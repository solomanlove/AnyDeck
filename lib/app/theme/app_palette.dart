import 'package:flutter/material.dart';

/// 与明暗主题无关的品牌基础色；业务 UI 优先通过 [ColorScheme] 获取语义颜色。
abstract final class AppPalette {
  static const Color primary = Color(0xff09c47c);

  /// 设备品牌封面与 Logo 共用白底，文字在明暗主题下均保持可读。
  static const Color deviceBrandCoverBackground = Colors.white;
  static const Color deviceBrandCoverForeground = Color(0xff616161);
}
