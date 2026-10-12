import 'package:flutter/material.dart';

/// 全局 UI 尺寸规范，仅保存与明暗主题无关的边框和圆角尺寸。
abstract final class AppThemeSizes {
  static const double borderWidth = 1;
  static const double strongBorderWidth = 1.5;

  static const BorderRadius radiusSmall = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radiusMedium = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusLarge = BorderRadius.all(Radius.circular(12));
}
