import 'package:flutter/material.dart';

import 'app_palette.dart';

/// AnyDeck 业务组件使用的语义颜色，补充 Material [ColorScheme] 未覆盖的场景。
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.toolbarForeground,
    required this.subtleBorder,
    required this.strongBorder,
    required this.success,
    required this.warning,
    required this.glassSurface,
  });

  final Color toolbarForeground;
  final Color subtleBorder;
  final Color strongBorder;
  final Color success;
  final Color warning;
  final Color glassSurface;

  static const light = AppThemeColors(
    toolbarForeground: Colors.black87,
    subtleBorder: Color(0xffe2e8f0),
    strongBorder: Color(0xffcbd5e1),
    success: AppPalette.primary,
    warning: Colors.orange,
    glassSurface: Color(0x47ffffff),
  );

  static const dark = AppThemeColors(
    toolbarForeground: Colors.white70,
    subtleBorder: Color(0xff334155),
    strongBorder: Color(0xff475569),
    success: AppPalette.primary,
    warning: Colors.orange,
    glassSurface: Color(0x2e000000),
  );

  @override
  AppThemeColors copyWith({
    Color? toolbarForeground,
    Color? subtleBorder,
    Color? strongBorder,
    Color? success,
    Color? warning,
    Color? glassSurface,
  }) {
    return AppThemeColors(
      toolbarForeground: toolbarForeground ?? this.toolbarForeground,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      strongBorder: strongBorder ?? this.strongBorder,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      glassSurface: glassSurface ?? this.glassSurface,
    );
  }

  @override
  AppThemeColors lerp(covariant AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      toolbarForeground: Color.lerp(
        toolbarForeground,
        other.toolbarForeground,
        t,
      )!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      strongBorder: Color.lerp(strongBorder, other.strongBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
    );
  }
}

/// 提供与 [ThemeData.colorScheme] 一致的业务语义色访问入口。
extension AppThemeDataColors on ThemeData {
  AppThemeColors get appColors => extension<AppThemeColors>()!;
}
