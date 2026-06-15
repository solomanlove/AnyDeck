import 'package:flutter/material.dart';

/// 基于同一个种子色构建 Material 3 的浅色和深色主题。
ThemeData buildAppTheme(Brightness brightness) {
  const seed = Color(0xff09c47c);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  ).copyWith(
    primary: seed,
    onPrimary: Colors.white,
  );
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xff0f172a)
        : const Color(0xfff7f8fb),
    canvasColor: isDark
        ? const Color(0xff1e293b)
        : Colors.white,
    visualDensity: VisualDensity.standard,
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xff1e293b) : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
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
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      checkColor: WidgetStateProperty.all(Colors.white),
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return Colors.transparent;
      }),
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return BorderSide(color: colorScheme.primary, width: 1.5);
        }
        return BorderSide(
          color: isDark ? const Color(0xff475569) : const Color(0xffcbd5e1),
          width: 1.5,
        );
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return isDark ? const Color(0xff475569) : const Color(0xffcbd5e1);
      }),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: isDark ? Colors.white : const Color(0xff1f2937),
        backgroundColor: isDark ? const Color(0xff1e293b) : Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
          ),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: colorScheme.primary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.primary),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
