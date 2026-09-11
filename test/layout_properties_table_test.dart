import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/layout_inspector/layout_node.dart';
import 'package:any_deck/features/layout/layout_properties_table.dart';

Widget _wrapWithApp(Widget child) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: SizedBox(width: 400, height: 600, child: child)),
  );
}

void main() {
  testWidgets('LayoutPropertiesTable renders empty state when selectedNode is null', (tester) async {
    await tester.pumpWidget(_wrapWithApp(const LayoutPropertiesTable(selectedNode: null)));
    await tester.pumpAndSettle();

    expect(find.text('未选择组件'), findsOneWidget);
  });

  testWidgets('LayoutPropertiesTable renders and scrolls properties without scrollbar assertion', (tester) async {
    final node = LayoutNode({
      'index': '0',
      'text': 'Test Component',
      'class': 'android.widget.TextView',
      'package': 'com.example.app',
      'resource-id': 'com.example.app:id/title',
      'bounds': '[0,0][1080,200]',
      'checkable': 'false',
      'checked': 'false',
      'clickable': 'true',
      'enabled': 'true',
      'focusable': 'true',
      'focused': 'false',
      'scrollable': 'false',
      'long-clickable': 'false',
      'password': 'false',
      'selected': 'false',
    });

    await tester.pumpWidget(_wrapWithApp(LayoutPropertiesTable(selectedNode: node)));
    await tester.pumpAndSettle();

    expect(find.text('属性列表'), findsOneWidget);
    expect(find.text('Test Component'), findsOneWidget);

    // 验证滚动不会触发 "The Scrollbar's ScrollController has no ScrollPosition attached"
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    // 触发动画控制器更新
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
