import 'package:any_deck/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
