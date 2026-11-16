import 'package:flutter/material.dart';

/// 全局 UI 尺寸规范，仅保存与明暗主题无关的布局、边框和圆角尺寸。
abstract final class AppThemeSizes {
  static const double borderWidth = 1;
  static const double strongBorderWidth = 1.5;

  static const BorderRadius radiusSmall = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radiusMedium = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusLarge = BorderRadius.all(Radius.circular(12));

  /// 主侧栏、设置分类与搜索框共用的圆角。
  static const BorderRadius radiusNavigation = BorderRadius.all(
    Radius.circular(10),
  );

  /// 设备与模拟器搜索框共用内边距，放大文字时允许自然增高。
  static const EdgeInsets searchFieldContentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );

  /// 搜索与清除图标的最小区域，避免默认 48px 高度撑高搜索框。
  static const BoxConstraints searchFieldIconConstraints = BoxConstraints(
    minWidth: 40,
    minHeight: 40,
  );
}
