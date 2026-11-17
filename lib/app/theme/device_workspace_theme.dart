import 'package:flutter/material.dart';

import 'app_theme_colors.dart';

/// 设备管理页使用原型中的中性底色，保留用户的主色、字体和其他主题扩展。
///
/// 仅在设备管理 Shell 内应用；切换到其他工具页后继续使用原应用主题。
ThemeData buildDeviceWorkspaceTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final surface = dark ? const Color(0xff17181d) : Colors.white;
  final canvas = dark ? const Color(0xff1a1b20) : const Color(0xfff8f9fc);
  final sidebar = dark ? const Color(0xff1f2027) : const Color(0xfff3f4f8);
  final foreground = dark ? const Color(0xfff0eff5) : const Color(0xff2c2d37);
  final muted = dark ? const Color(0xffa2a4b1) : const Color(0xff747784);
  final border = dark ? const Color(0xff343641) : const Color(0xffe5e7ee);
  final colors = base.appColors.copyWith(
    panelSurface: surface,
    sunkenSurface: canvas,
    subtleSurface: dark ? const Color(0xff252730) : const Color(0xfff0f1f6),
    toolbarForeground: dark ? const Color(0xff999cae) : const Color(0xff363641),
    strongBorder: dark ? const Color(0xff4f5261) : const Color(0xffc9ccd7),
    subtleBorder: border,
    mutedForeground: muted,
  );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      surface: surface,
      surfaceContainerLow: sidebar,
      surfaceContainerHighest: sidebar,
      onSurface: foreground,
      onSurfaceVariant: muted,
      outlineVariant: border,
    ),
    scaffoldBackgroundColor: canvas,
    canvasColor: surface,
    textTheme: base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    extensions: [
      for (final extension in base.extensions.values)
        if (extension is! AppThemeColors) extension,
      colors,
    ],
  );
}
