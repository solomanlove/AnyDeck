import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在实际设置页检查按钮墨水层、Hover 与展开菜单，不触发设置值变更。
Future<void> expectSettingsSelectorInk(WidgetTester tester) async {
  final selectors = [
    find.byType(PopupMenuButton<AppLanguage>),
    find.byType(PopupMenuButton<ThemeMode>),
    find.byType(PopupMenuButton<AppThemeColor>),
  ];
  for (final selector in selectors) {
    expect(selector, findsOneWidget);
    final inkWell = tester.widget<InkWell>(
      find.descendant(of: selector, matching: find.byType(InkWell)).first,
    );
    final ink = tester.widget<Ink>(
      find.descendant(of: selector, matching: find.byType(Ink)).first,
    );
    final decoration = ink.decoration! as BoxDecoration;
    expect(inkWell.borderRadius, AppThemeSizes.radiusMedium);
    expect(inkWell.borderRadius, decoration.borderRadius);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(selector));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final buttonRect = tester.getRect(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final menuItem = find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem,
    );
    expect(menuItem, findsWidgets);
    final menuRect = tester.getRect(menuItem.first);
    expect(menuRect.left, closeTo(buttonRect.left, 0.01));
    expect(menuRect.right, closeTo(buttonRect.right, 0.01));
    expect(menuRect.top, greaterThanOrEqualTo(buttonRect.bottom));
    // 取消菜单，保留原语言、主题和持久化设置。
    Navigator.of(tester.element(menuItem.first)).pop();
    await tester.pumpAndSettle();
    await mouse.removePointer();
  }
}
