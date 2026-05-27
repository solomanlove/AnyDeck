import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  const seed = Color(0xff2563eb);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xff0f172a)
        : const Color(0xfff7f8fb),
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: isDark
          ? const Color(0xff0f172a)
          : const Color(0xfff7f8fb),
      foregroundColor: isDark
          ? const Color(0xffe2e8f0)
          : const Color(0xff172033),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xff111827) : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    ),
  );
}
