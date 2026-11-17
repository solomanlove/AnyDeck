import 'package:any_deck/app/theme/app_theme_sizes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 检查搜索框实际输入装饰的各状态边框；默认复用 Tab 圆角。
///
/// [field] 定位 TextField 或 TextFormField；[focused] 可同时验证当前焦点状态。
void expectSearchFieldRadius(
  WidgetTester tester,
  Finder field, {
  bool? focused,
  BorderRadius radius = AppThemeSizes.radiusNavigation,
}) {
  final decorator = tester.widget<InputDecorator>(
    find.descendant(of: field, matching: find.byType(InputDecorator)),
  );
  if (focused != null) expect(decorator.isFocused, focused);
  final decoration = decorator.decoration;
  expect(decoration.border, isA<OutlineInputBorder>());
  for (final border in [
    decoration.border,
    decoration.enabledBorder,
    decoration.focusedBorder,
    decoration.disabledBorder,
    decoration.errorBorder,
    decoration.focusedErrorBorder,
  ].nonNulls) {
    expect(
      border,
      isA<OutlineInputBorder>().having(
        (border) => border.borderRadius,
        'borderRadius',
        radius,
      ),
    );
  }
}
