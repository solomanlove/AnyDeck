import 'package:any_deck/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('标准 ThemeData 未安装扩展时公共组件仍可读取明暗语义色', () {
    expect(ThemeData.light().appColors, AppThemeColors.light);
    expect(ThemeData.dark().appColors, AppThemeColors.dark);
    final custom = AppThemeColors.light.copyWith(success: Colors.blue);
    expect(ThemeData(extensions: [custom]).appColors, same(custom));
  });

  test('Light 和 Dark Theme 暴露统一语义色与尺寸规范', () {
    final light = buildAppTheme(Brightness.light);
    final dark = buildAppTheme(Brightness.dark);

    expect(light.colorScheme.primary, AppPalette.primary);
    expect(dark.colorScheme.primary, AppPalette.primary);
    expect(light.colorScheme.outlineVariant, AppThemeColors.light.subtleBorder);
    expect(dark.colorScheme.outlineVariant, AppThemeColors.dark.subtleBorder);
    expect(light.appColors.toolbarForeground, Colors.black87);
    expect(dark.appColors.toolbarForeground, Colors.white70);
    expect(light.appColors.panelSurface, Colors.white);
    expect(dark.appColors.panelSurface, const Color(0xff1e293b));
    expect(light.appColors.subtleDivider, Colors.black12);
    expect(dark.appColors.subtleDivider, Colors.white12);
    expect(
      light.inputDecorationTheme.border,
      isA<OutlineInputBorder>().having(
        (border) => border.borderRadius,
        'borderRadius',
        AppThemeSizes.radiusMedium,
      ),
    );
  });

  for (final brightness in Brightness.values) {
    for (final color in AppThemeColor.values) {
      test('${brightness.name} 下 ${color.name} 主题色用于组件并保留语义状态色', () {
        final theme = buildAppTheme(brightness, themeColor: color);
        final generated = ColorScheme.fromSeed(
          seedColor: color.color,
          brightness: brightness,
        );
        const selected = {WidgetState.selected};

        expect(theme.colorScheme.primary, color.color);
        expect(theme.colorScheme.primaryContainer, generated.primaryContainer);
        expect(theme.colorScheme.secondary, generated.secondary);
        expect(
          theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
          color.color,
        );
        expect(
          theme.outlinedButtonTheme.style!.foregroundColor!.resolve({}),
          color.color,
        );
        expect(
          theme.textButtonTheme.style!.foregroundColor!.resolve({}),
          color.color,
        );
        expect(theme.checkboxTheme.fillColor!.resolve(selected), color.color);
        expect(theme.radioTheme.fillColor!.resolve(selected), color.color);
        expect(theme.appColors.success, AppPalette.primary);
        expect(theme.appColors.warning, Colors.orange);
      });
    }
  }
}
