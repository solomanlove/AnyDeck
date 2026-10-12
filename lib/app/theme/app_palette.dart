import 'package:flutter/material.dart';

/// 与明暗主题无关的品牌基础色；业务 UI 优先通过 [ColorScheme] 获取语义颜色。
abstract final class AppPalette {
  static const Color primary = Color(0xff09c47c);
}
