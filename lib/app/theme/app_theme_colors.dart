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
    required this.panelSurface,
    required this.sunkenSurface,
    required this.subtleSurface,
    required this.hoverSurface,
    required this.subtleDivider,
    required this.softDivider,
    required this.mutedForeground,
    required this.faintForeground,
  });

  final Color toolbarForeground;
  final Color subtleBorder;
  final Color strongBorder;
  final Color success;
  final Color warning;
  final Color glassSurface;
  final Color panelSurface;
  final Color sunkenSurface;
  final Color subtleSurface;
  final Color hoverSurface;
  final Color subtleDivider;
  final Color softDivider;
  final Color mutedForeground;
  final Color faintForeground;

  static const light = AppThemeColors(
    toolbarForeground: Colors.black87,
    subtleBorder: Color(0xffe2e8f0),
    strongBorder: Color(0xffcbd5e1),
    success: AppPalette.primary,
    warning: Colors.orange,
    glassSurface: Color(0x47ffffff),
    panelSurface: Colors.white,
    sunkenSurface: Color(0xfff7f8fb),
    subtleSurface: Color(0x05000000),
    hoverSurface: Color(0x0d000000),
    subtleDivider: Colors.black12,
    softDivider: Colors.black12,
    mutedForeground: Colors.black54,
    faintForeground: Colors.black38,
  );

  static const dark = AppThemeColors(
    toolbarForeground: Colors.white70,
    subtleBorder: Color(0xff334155),
    strongBorder: Color(0xff475569),
    success: AppPalette.primary,
    warning: Colors.orange,
    glassSurface: Color(0x2e000000),
    panelSurface: Color(0xff1e293b),
    sunkenSurface: Color(0xff0f172a),
    subtleSurface: Color(0x0affffff),
    hoverSurface: Color(0x14ffffff),
    subtleDivider: Colors.white12,
    softDivider: Colors.white10,
    mutedForeground: Colors.white60,
    faintForeground: Colors.white38,
  );

  @override
  AppThemeColors copyWith({
    Color? toolbarForeground,
    Color? subtleBorder,
    Color? strongBorder,
    Color? success,
    Color? warning,
    Color? glassSurface,
    Color? panelSurface,
    Color? sunkenSurface,
    Color? subtleSurface,
    Color? hoverSurface,
    Color? subtleDivider,
    Color? softDivider,
    Color? mutedForeground,
    Color? faintForeground,
  }) {
    return AppThemeColors(
      toolbarForeground: toolbarForeground ?? this.toolbarForeground,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      strongBorder: strongBorder ?? this.strongBorder,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      glassSurface: glassSurface ?? this.glassSurface,
      panelSurface: panelSurface ?? this.panelSurface,
      sunkenSurface: sunkenSurface ?? this.sunkenSurface,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      hoverSurface: hoverSurface ?? this.hoverSurface,
      subtleDivider: subtleDivider ?? this.subtleDivider,
      softDivider: softDivider ?? this.softDivider,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      faintForeground: faintForeground ?? this.faintForeground,
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
      panelSurface: Color.lerp(panelSurface, other.panelSurface, t)!,
      sunkenSurface: Color.lerp(sunkenSurface, other.sunkenSurface, t)!,
      subtleSurface: Color.lerp(subtleSurface, other.subtleSurface, t)!,
      hoverSurface: Color.lerp(hoverSurface, other.hoverSurface, t)!,
      subtleDivider: Color.lerp(subtleDivider, other.subtleDivider, t)!,
      softDivider: Color.lerp(softDivider, other.softDivider, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      faintForeground: Color.lerp(faintForeground, other.faintForeground, t)!,
    );
  }
}

/// 提供与 [ThemeData.colorScheme] 一致的业务语义色访问入口。
extension AppThemeDataColors on ThemeData {
  AppThemeColors get appColors => extension<AppThemeColors>()!;
}
