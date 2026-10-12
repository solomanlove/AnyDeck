import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_theme_colors.dart';
import 'app_theme_sizes.dart';

export 'app_palette.dart';
export 'app_theme_colors.dart';
export 'app_theme_sizes.dart';

/// 基于同一个种子色构建 Material 3 的浅色和深色主题。
ThemeData buildAppTheme(Brightness brightness) {
  const seed = AppPalette.primary;
  final isDark = brightness == Brightness.dark;
  final colorScheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness).copyWith(
        primary: seed,
        onPrimary: Colors.white,
        outline: isDark
            ? AppThemeColors.dark.strongBorder
            : AppThemeColors.light.strongBorder,
        outlineVariant: isDark
            ? AppThemeColors.dark.subtleBorder
            : AppThemeColors.light.subtleBorder,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    extensions: <ThemeExtension<dynamic>>[
      isDark ? AppThemeColors.dark : AppThemeColors.light,
    ],
    scaffoldBackgroundColor: isDark
        ? const Color(0xff0f172a)
        : const Color(0xfff7f8fb),
    canvasColor: isDark ? const Color(0xff1e293b) : Colors.white,
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
        borderRadius: AppThemeSizes.radiusMedium,
        side: BorderSide(
          color: isDark
              ? AppThemeColors.dark.subtleBorder
              : AppThemeColors.light.subtleBorder,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: isDark
          ? AppThemeColors.dark.subtleBorder
          : AppThemeColors.light.subtleBorder,
      thickness: AppThemeSizes.borderWidth,
      space: AppThemeSizes.borderWidth,
    ),
    iconTheme: IconThemeData(
      color: isDark
          ? AppThemeColors.dark.toolbarForeground
          : AppThemeColors.light.toolbarForeground,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(
        borderRadius: AppThemeSizes.radiusMedium,
      ),
      isDense: true,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: AppThemeSizes.radiusSmall),
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
          width: AppThemeSizes.strongBorderWidth,
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
          borderRadius: AppThemeSizes.radiusMedium,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: colorScheme.primary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: const RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusMedium,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.primary),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: const RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusMedium,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: const RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusMedium,
        ),
      ),
    ),
  );
}
